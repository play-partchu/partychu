import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/host_pre_registration.dart';

// Firebase Functions 리전 — functions/hostPreRegistration.js와 일치해야 함.
const _functionsRegion = 'asia-northeast3';

/// 호스트 사전등록 — 읽기는 Firestore(관리자 읽기 규칙), 쓰기는 전부 콜러블.
class HostPreRegistrationService {
  HostPreRegistrationService._();

  /// FormHug 공개 신청폼.
  static const formUrl = 'https://formhug.ai/f/Sbyrul';

  /// 비공개 테스트 테스터 추가는 Console에서 사람이 한다 — 계정 정보는 코드에 없다.
  static const playConsoleUrl = 'https://play.google.com/console';

  static final _db = FirebaseFirestore.instance;
  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: _functionsRegion);

  /// 최신 신청순. 신청 규모가 작아 최근 500건을 실시간으로 받고 검색·필터는 화면에서 한다.
  static Stream<List<HostPreRegistration>> watchLatest({int limit = 500}) {
    return _db
        .collection('hostPreRegistrations')
        .orderBy('submittedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map((d) => HostPreRegistration.fromMap(d.id, d.data())).toList());
  }

  /// FormHug 필드 연결 설정이 저장돼 있는지.
  static Stream<bool> watchFieldMapReady() {
    return _db
        .collection('hostPreRegistrationConfig')
        .doc('formhug')
        .snapshots()
        .map((s) => s.exists && s.data()?['fields'] != null);
  }

  static Future<HostPreRegistrationDetail> getDetail(String id) async {
    final r = await _functions.httpsCallable('adminGetHostPreRegistration').call({'id': id});
    return HostPreRegistrationDetail.fromMap(asStringMap(r.data));
  }

  /// action: markPreregistered | markHostLinkSent | markRepresentativeLinkSent |
  ///         reject | reopen | saveMemo | linkHost | unlinkHost
  static Future<void> update(
    String id,
    String action, {
    String? memo,
    String? reason,
    String? uid,
    bool allowEmailMismatch = false,
  }) async {
    await _functions.httpsCallable('adminUpdateHostPreRegistration').call({
      'id': id,
      'action': action,
      'memo': ?memo,
      'reason': ?reason,
      'uid': ?uid,
      if (allowEmailMismatch) 'allowEmailMismatch': true,
    });
  }

  /// 대표자 인증 링크 생성/재발급. 링크는 **이 응답에서 한 번만** 온다.
  static Future<RepresentativeLinkResult> createRepresentativeLink(
    String id, {
    bool reissue = false,
  }) async {
    final r = await _functions
        .httpsCallable('adminCreateBusinessDelegationForPreregistration')
        .call({'id': id, 'reissue': reissue});
    final m = asStringMap(r.data);
    return RepresentativeLinkResult(
      delegationId: m['delegationId'] as String? ?? '',
      approvalUrl: m['approvalUrl'] as String? ?? '',
      expiresAt: DateTime.fromMillisecondsSinceEpoch((m['expiresAtMs'] as num?)?.toInt() ?? 0),
    );
  }

  static Future<Map<String, dynamic>> formSetup(Map<String, dynamic> data) async {
    final r = await _functions
        .httpsCallable(
          'adminHostPreRegistrationFormSetup',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
        )
        .call(data);
    return asStringMap(r.data);
  }

  static Future<void> openInNewTab(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) return;
    // 웹은 예전 그대로 새 탭. Android는 설치된 아무 브라우저로(특정 브라우저·
    // Custom Tab에 기대지 않는다).
    await launchUrl(
      uri,
      mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
  }
}

class RepresentativeLinkResult {
  const RepresentativeLinkResult({
    required this.delegationId,
    required this.approvalUrl,
    required this.expiresAt,
  });

  final String delegationId;
  final String approvalUrl;
  final DateTime expiresAt;
}

/// 콜러블 오류를 관리자에게 보여줄 문장으로.
String callableErrorMessage(Object e) {
  if (e is FirebaseFunctionsException) return e.message ?? e.code;
  return '$e';
}

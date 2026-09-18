import 'package:cloud_firestore/cloud_firestore.dart';

/// 호스트 사전등록 신청서(`hostPreRegistrations`) — 관리자 화면 모델.
///
/// ⚠️ **이 문서의 상태는 권한의 근거가 아니다.** 호스트가 실제로 사업자를 쓸 수
/// 있는지는 언제나 `users/{uid}.businessVerification`(서버만 기록)이 정한다.
/// 이 화면은 그 값을 서버 콜러블로 확인해 신청서 진행 상태를 맞춰 보여줄 뿐이다
/// (functions/hostPreRegistration.js).
///
/// 목록은 Firestore를 직접 읽고(규칙: 관리자 읽기만), 상세·처리는 전부
/// 콜러블을 거친다 — 클라이언트 쓰기는 규칙이 막아 두었다.
enum PreRegStatus {
  newApplication('new', '신규'),
  reviewing('reviewing', '확인중'),
  preregistered('preregistered', '사전등록 완료'),
  hostLinkSent('hostLinkSent', '호스트 안내 발송'),
  representativeVerificationRequired('representativeVerificationRequired', '대표자 확인 필요'),
  representativeLinkSent('representativeLinkSent', '대표자 링크 발송'),
  verified('verified', '인증 완료'),
  rejected('rejected', '반려');

  const PreRegStatus(this.key, this.label);
  final String key;
  final String label;

  static PreRegStatus fromKey(String? key) {
    for (final s in values) {
      if (s.key == key) return s;
    }
    return PreRegStatus.newApplication;
  }
}

/// 목록 필터. 반려 건은 '전체'에서만 보인다.
enum PreRegFilter {
  all('전체'),
  newOnly('신규'),
  inProgress('처리중'),
  representativeRequired('대표자 확인 필요'),
  done('완료'),
  unprocessed('미처리');

  const PreRegFilter(this.label);
  final String label;

  bool matches(HostPreRegistration p) {
    switch (this) {
      case PreRegFilter.all:
        return true;
      case PreRegFilter.newOnly:
        return p.status == PreRegStatus.newApplication;
      case PreRegFilter.inProgress:
        return const {
          PreRegStatus.reviewing,
          PreRegStatus.preregistered,
          PreRegStatus.hostLinkSent,
          PreRegStatus.representativeLinkSent,
        }.contains(p.status);
      case PreRegFilter.representativeRequired:
        return p.needsRepresentativeCheck;
      case PreRegFilter.done:
        return p.status == PreRegStatus.verified;
      case PreRegFilter.unprocessed:
        return p.status == PreRegStatus.newApplication || p.status == PreRegStatus.reviewing;
    }
  }
}

DateTime? _time(Object? v) {
  if (v is Timestamp) return v.toDate();
  if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
  return null;
}

String _str(Object? v) => v is String ? v : '';

Map<String, dynamic> asStringMap(Object? v) {
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  return <String, dynamic>{};
}

List<Object?> asList(Object? v) => v is List ? v : const [];

class HostPreRegistration {
  const HostPreRegistration({
    required this.id,
    required this.status,
    this.serialNumber,
    this.submittedAt,
    this.storeName = '',
    this.businessRegistrationNumber = '',
    this.hostName = '',
    this.hostEmail = '',
    this.hostPhone = '',
    this.sameAsRepresentative,
    this.representativeName = '',
    this.representativePhone = '',
    this.representativeEmail = '',
    this.deviceType,
    this.googlePlayScreenshotUrl = '',
    this.googlePlayScreenshotName = '',
    this.importState = '',
    this.missingRequired = const [],
    this.hostUid = '',
    this.delegationId = '',
    this.memo = '',
    this.rejectReason = '',
    this.processedAt,
    this.processedBy = '',
    this.updatedAt,
  });

  final String id;
  final PreRegStatus status;
  final int? serialNumber;
  final DateTime? submittedAt;
  final String storeName;
  final String businessRegistrationNumber;
  final String hostName;
  final String hostEmail;
  final String hostPhone;
  final bool? sameAsRepresentative;
  final String representativeName;
  final String representativePhone;
  final String representativeEmail;

  /// 'android' | 'ios' | 'both' | null
  final String? deviceType;

  /// FormHug 24시간 서명 링크 — 상세 조회 때 서버가 새로 받아 둔다.
  final String googlePlayScreenshotUrl;
  final String googlePlayScreenshotName;

  /// 'ok' | 'pending' | 'needsFieldMap' | 'fetchFailed'
  final String importState;
  final List<String> missingRequired;
  final String hostUid;
  final String delegationId;
  final String memo;
  final String rejectReason;
  final DateTime? processedAt;
  final String processedBy;
  final DateTime? updatedAt;

  factory HostPreRegistration.fromMap(String id, Map<String, dynamic> d) {
    final shot = asStringMap(d['googlePlayScreenshot']);
    return HostPreRegistration(
      id: id,
      status: PreRegStatus.fromKey(d['status'] as String?),
      serialNumber: (d['serialNumber'] as num?)?.toInt(),
      submittedAt: _time(d['submittedAt']),
      storeName: _str(d['storeName']),
      businessRegistrationNumber: _str(d['businessRegistrationNumber']),
      hostName: _str(d['hostName']),
      hostEmail: _str(d['hostEmail']),
      hostPhone: _str(d['hostPhone']),
      sameAsRepresentative: d['sameAsRepresentative'] as bool?,
      representativeName: _str(d['representativeName']),
      representativePhone: _str(d['representativePhone']),
      representativeEmail: _str(d['representativeEmail']),
      deviceType: d['deviceType'] as String?,
      googlePlayScreenshotUrl: _str(d['googlePlayScreenshotUrl']),
      googlePlayScreenshotName: _str(shot['name']),
      importState: _str(d['importState']),
      missingRequired: asList(d['missingRequired']).whereType<String>().toList(),
      hostUid: _str(d['hostUid']),
      delegationId: _str(d['delegationId']),
      memo: _str(d['memo']),
      rejectReason: _str(d['rejectReason']),
      processedAt: _time(d['processedAt']),
      processedBy: _str(d['processedBy']),
      updatedAt: _time(d['updatedAt']),
    );
  }

  bool get isNew => status == PreRegStatus.newApplication;
  bool get isClosed => status == PreRegStatus.verified || status == PreRegStatus.rejected;
  bool get usesAndroid => deviceType == 'android' || deviceType == 'both';
  bool get imported => importState == 'ok';

  /// 대표자가 호스트와 다르거나 서버가 대표자 확인 필요로 판정했고, 아직 끝나지 않은 건.
  bool get needsRepresentativeCheck =>
      !isClosed &&
      (sameAsRepresentative == false ||
          status == PreRegStatus.representativeVerificationRequired ||
          status == PreRegStatus.representativeLinkSent);

  String get deviceLabel => deviceLabelOf(deviceType);

  String get sameAsRepresentativeLabel => sameAsRepresentative == null
      ? '-'
      : (sameAsRepresentative! ? '동일' : '다름');

  /// 목록 검색 — 업체명·사업자번호·이름·이메일·전화번호(숫자만 비교).
  bool matchesQuery(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final qDigits = q.replaceAll(RegExp(r'[^0-9]'), '');
    final texts = [storeName, hostName, hostEmail, representativeName, representativeEmail];
    if (texts.any((t) => t.toLowerCase().contains(q))) return true;
    if (qDigits.length >= 3) {
      final numbers = [businessRegistrationNumber, hostPhone, representativePhone]
          .map((v) => v.replaceAll(RegExp(r'[^0-9]'), ''));
      if (numbers.any((n) => n.contains(qDigits))) return true;
    }
    return false;
  }
}

String deviceLabelOf(String? v) => switch (v) {
      'android' => 'Android',
      'ios' => 'iOS',
      'both' => '둘 다',
      _ => '-',
    };

/// 사업자등록번호 표시(10자리면 000-00-00000).
String formatBusinessNumber(String v) {
  final d = v.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.length != 10) return v.isEmpty ? '-' : v;
  return '${d.substring(0, 3)}-${d.substring(3, 5)}-${d.substring(5)}';
}

/// 상세 콜러블(adminGetHostPreRegistration) 응답.
class HostPreRegistrationDetail {
  const HostPreRegistrationDetail({
    required this.pre,
    required this.host,
    required this.candidates,
    required this.delegation,
    required this.history,
    required this.formUrl,
  });

  final HostPreRegistration pre;
  final PreRegHost? host;
  final List<PreRegHost> candidates;
  final PreRegDelegationLink? delegation;
  final List<PreRegHistoryEntry> history;
  final String formUrl;

  factory HostPreRegistrationDetail.fromMap(Map<String, dynamic> m) {
    final pre = asStringMap(m['preRegistration']);
    return HostPreRegistrationDetail(
      pre: HostPreRegistration.fromMap(_str(pre['id']), pre),
      host: m['host'] == null ? null : PreRegHost.fromMap(asStringMap(m['host'])),
      candidates: asList(m['candidates']).map((c) => PreRegHost.fromMap(asStringMap(c))).toList(),
      delegation: m['delegation'] == null
          ? null
          : PreRegDelegationLink.fromMap(asStringMap(m['delegation'])),
      history: asList(m['history']).map((h) => PreRegHistoryEntry.fromMap(asStringMap(h))).toList(),
      formUrl: _str(m['formUrl']),
    );
  }
}

/// 연결된(또는 후보) 회원 요약 — 서버가 CI·전화번호를 빼고 돌려준다.
class PreRegHost {
  const PreRegHost({
    required this.uid,
    this.nickname = '',
    this.email = '',
    this.signupProvider = '',
    this.identityVerified = false,
    this.accountStatus = 'active',
    this.createdAt,
    this.businessStatus = '',
    this.authorization = '',
    this.authorizationReason = '',
    this.businessNumberMatches = false,
    this.authorizedForThis = false,
    this.pendingOwnerApprovalForThis = false,
    this.verifiedRepresentativeName = '',
    this.matchedBy = const [],
  });

  final String uid;
  final String nickname;
  final String email;
  final String signupProvider;
  final bool identityVerified;
  final String accountStatus;
  final DateTime? createdAt;
  final String businessStatus;
  final String authorization;
  final String authorizationReason;
  final bool businessNumberMatches;
  final bool authorizedForThis;
  final bool pendingOwnerApprovalForThis;

  /// 국세청이 확인한 대표자명(호스트가 앱에서 사업자 인증을 한 경우).
  final String verifiedRepresentativeName;
  final List<String> matchedBy;

  factory PreRegHost.fromMap(Map<String, dynamic> m) {
    final b = asStringMap(m['business']);
    return PreRegHost(
      uid: _str(m['uid']),
      nickname: _str(m['nickname']),
      email: _str(m['email']),
      signupProvider: _str(m['signupProvider']),
      identityVerified: m['identityVerified'] == true,
      accountStatus: _str(m['accountStatus']).isEmpty ? 'active' : _str(m['accountStatus']),
      createdAt: _time(m['createdAtMs']),
      businessStatus: _str(b['status']),
      authorization: _str(b['authorization']),
      authorizationReason: _str(b['authorizationReason']),
      businessNumberMatches: b['businessNumberMatches'] == true,
      authorizedForThis: b['authorizedForThis'] == true,
      pendingOwnerApprovalForThis: b['pendingOwnerApprovalForThis'] == true,
      verifiedRepresentativeName: _str(b['verifiedRepresentativeName']),
      matchedBy: asList(m['matchedBy']).whereType<String>().toList(),
    );
  }

  String get matchedByLabel => matchedBy
      .map((k) => switch (k) {
            'accountEmail' => '가입 이메일',
            'socialAccountEmail' => '소셜 계정 이메일',
            'authEmail' => '로그인 이메일',
            _ => k,
          })
      .join(', ');
}

/// 대표자 인증 링크 — businessDelegations 상태를 서버가 표시용으로 바꿔 준다.
class PreRegDelegationLink {
  const PreRegDelegationLink({
    required this.id,
    required this.linkStatus,
    this.businessNumberMasked = '',
    this.requestedAt,
    this.expiresAt,
    this.approvedAt,
    this.attemptCount = 0,
    this.needsManualReview = false,
  });

  final String id;

  /// none | requested | approved | rejected | expired | revoked
  final String linkStatus;
  final String businessNumberMasked;
  final DateTime? requestedAt;
  final DateTime? expiresAt;
  final DateTime? approvedAt;
  final int attemptCount;
  final bool needsManualReview;

  factory PreRegDelegationLink.fromMap(Map<String, dynamic> m) => PreRegDelegationLink(
        id: _str(m['id']),
        linkStatus: _str(m['linkStatus']).isEmpty ? 'none' : _str(m['linkStatus']),
        businessNumberMasked: _str(m['businessNumberMasked']),
        requestedAt: _time(m['requestedAtMs']),
        expiresAt: _time(m['expiresAtMs']),
        approvedAt: _time(m['approvedAtMs']),
        attemptCount: (m['attemptCount'] as num?)?.toInt() ?? 0,
        needsManualReview: m['needsManualReview'] == true,
      );
}

String linkStatusLabel(String? s) => switch (s) {
      'requested' => '대기중',
      'approved' => '승인완료',
      'rejected' => '거절',
      'expired' => '만료',
      'revoked' => '취소',
      _ => '미생성',
    };

class PreRegHistoryEntry {
  const PreRegHistoryEntry({
    required this.type,
    required this.message,
    this.at,
    this.actorUid = '',
    this.actorType = '',
  });

  final String type;
  final String message;
  final DateTime? at;
  final String actorUid;

  /// 'admin' | 'system' | 'applicant'
  final String actorType;

  factory PreRegHistoryEntry.fromMap(Map<String, dynamic> m) => PreRegHistoryEntry(
        type: _str(m['type']),
        message: _str(m['message']),
        at: _time(m['at']),
        actorUid: _str(m['actorUid']),
        actorType: _str(m['actorType']),
      );

  String get actorLabel => switch (actorType) {
        'admin' => '관리자',
        'applicant' => '신청자',
        _ => '시스템',
      };
}

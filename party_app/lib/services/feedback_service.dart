import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:party_app/models/feedback_request.dart';
import 'package:party_app/services/cloudflare_service.dart';
import 'package:party_app/utils/user_session.dart';

/// 의견 보내기 — 제출/조회 서비스.
/// (관리자 웹은 별도로 Firestore를 직접 다룬다 — admin 코드는 이 파일을
///  import하지 않는다.)
class FeedbackService {
  FeedbackService._();

  /// 한 건에 붙일 수 있는 사진 수 상한 — 작성 화면도 이 값을 그대로 쓴다
  /// (양쪽에 따로 두면 한쪽만 바뀌어 고른 사진이 조용히 버려진다).
  static const int maxImages = 5;

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('feedbackRequests');

  /// 버그 신고일 때만 자동 수집. 민감한 개인정보(광고ID·시리얼 등)는 수집하지 않고
  /// 문제 재현에 필요한 최소 정보(기기 모델명·OS 버전)만 사용한다.
  static Future<Map<String, String?>> _collectDeviceMeta() async {
    String? appVersion;
    String? platform;
    String? osVersion;
    String? deviceInfo;

    try {
      final pkg = await PackageInfo.fromPlatform();
      appVersion = '${pkg.version}+${pkg.buildNumber}';
    } catch (_) {}

    // 기기 정보는 앱에서만 모은다 — 웹에서 `Platform.isAndroid`를 읽으면
    // dart:io가 UnsupportedError를 던진다(앱 버전은 위에서 이미 받았다).
    if (kIsWeb) {
      return {
        'appVersion': appVersion,
        'platform': 'Web',
        'osVersion': null,
        'deviceInfo': null,
      };
    }

    try {
      final deviceInfoPlugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        platform = 'Android';
        final info = await deviceInfoPlugin.androidInfo;
        osVersion =
            'Android ${info.version.release} (SDK ${info.version.sdkInt})';
        deviceInfo = '${info.manufacturer} ${info.model}';
      } else if (Platform.isIOS) {
        platform = 'iOS';
        final info = await deviceInfoPlugin.iosInfo;
        osVersion = '${info.systemName} ${info.systemVersion}';
        deviceInfo = info.utsname.machine;
      }
    } catch (_) {}

    return {
      'appVersion': appVersion,
      'platform': platform,
      'osVersion': osVersion,
      'deviceInfo': deviceInfo,
    };
  }

  /// 의견 제출. 이미지가 있으면 기존 Cloudflare R2 업로드를 재사용해 먼저 올린다.
  static Future<void> submit({
    required String type,
    required String title,
    required String content,
    required List<XFile> images,
    required String contactEmail,
    String contactPhone = '',
    bool screenshotUnavailable = false,
    String? screenshotUnavailableReason,
    String? relatedScreen,
  }) async {
    if (UserSession.userId.isEmpty) {
      throw Exception('로그인이 필요합니다.');
    }

    // 은퇴한 유형(결제/환불)은 새 문의로 받지 않는다 — 작성 화면이 선택지에서
    // 뺐지만, 이 서비스를 다른 경로에서 부르더라도 값이 새지 않도록 여기서도
    // 막는다(스크린샷·연락처 검사와 같은 자리·같은 이유). 이미 접수된 문서를
    // **읽는** 쪽은 그대로다 — [FeedbackType.all]과 라벨은 건드리지 않는다.
    if (!FeedbackType.isComposable(type)) {
      throw Exception(
        '결제·환불 문의는 고객센터에서 접수하지 않아요. '
        '해당 파티·플레이스·장소대여의 호스트에게 문의해주세요.',
      );
    }

    // 연락처는 **답변을 보낼 유일한 통로**다. 작성 화면이 버튼을 잠가 두지만,
    // 이 서비스를 다른 경로에서 부르더라도 빈 값이 새지 않도록 여기서도 막는다
    // (스크린샷 필수 검사와 같은 자리·같은 이유).
    final email = contactEmail.trim();
    final phone = contactPhone.trim();
    if (!FeedbackContact.isValidEmail(email)) {
      throw Exception('답변받을 이메일 주소를 정확히 입력해주세요.');
    }
    if (!FeedbackContact.isValidPhoneOrEmpty(phone)) {
      throw Exception('연락처 형식을 확인해주세요. 예: 010-1234-5678');
    }

    // "캡처할 수 없는 오류"는 버그 신고에만 있는 개념이다 — 다른 유형에서
    // 넘어오면 그냥 무시한다(첨부가 원래 선택이라 우회할 것도 없다).
    final blocked = type == FeedbackType.bug && screenshotUnavailable;
    final blockedReason = blocked
        ? (screenshotUnavailableReason ?? '').trim()
        : '';

    // 버그 신고는 오류 화면 스크린샷이 있어야 접수된다 — 작성 화면이 제출
    // 버튼을 잠가 두지만, 이 서비스를 다른 경로에서 부르더라도 규칙이 새지
    // 않도록 여기서도 막는다. 그 외 유형은 첨부가 선택이다.
    //
    // 예외: 알림 미수신처럼 화면으로 남길 수 없는 오류는 사진 없이 받되,
    // **사유를 반드시 받는다.** 사유까지 비면 예외가 그냥 "첨부 안 함"
    // 버튼이 되어 필수 정책이 무력해진다.
    if (type == FeedbackType.bug && images.isEmpty) {
      if (!blocked) {
        throw Exception('오류가 발생한 화면의 스크린샷을 1장 이상 첨부해주세요.');
      }
      if (blockedReason.isEmpty) {
        throw Exception('스크린샷을 첨부할 수 없는 이유를 입력해주세요.');
      }
    }

    final imageUrls = <String>[];
    for (final file in images.take(maxImages)) {
      imageUrls.add(await CloudflareService.uploadImage(file));
    }

    final meta = type == FeedbackType.bug
        ? await _collectDeviceMeta()
        : const <String, String?>{};

    await _col.add({
      'userId': UserSession.userId,
      'type': type,
      'title': title.trim(),
      'content': content.trim(),
      'imageUrls': imageUrls,
      // 관리자 목록에서 "사진이 없는 버그 신고"가 규칙 위반인지 정당한 예외인지
      // 구분할 수 있어야 한다 — 항상 함께 저장한다(예외가 아니면 false/null).
      'screenshotUnavailable': blocked,
      'screenshotUnavailableReason': blocked && blockedReason.isNotEmpty
          ? blockedReason
          : null,
      'relatedScreen': relatedScreen,
      // 답변받을 연락처. **작성자가 이 화면에서 직접 적은 값만** 담는다 —
      // 닉네임·계정 이메일·실명을 여기에 복제하지 않는다(관리자 화면은
      // userId로 users 문서를 붙여 보여준다).
      'contactEmail': email,
      // 선택 입력이라 안 적으면 빈 문자열이다. null 대신 ''로 두는 이유는
      // 관리자 목록이 '없음'과 '필드 없음'을 구분할 필요가 없어서다.
      'contactPhone': phone,
      'status': FeedbackStatus.received,
      'userReply': '',
      'adminMemo': '',
      'appVersion': meta['appVersion'],
      'platform': meta['platform'],
      'osVersion': meta['osVersion'],
      'deviceInfo': meta['deviceInfo'],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 본인이 작성한 의견만 최신순으로 조회 (Firestore Rules로도 강제됨).
  ///
  /// **복합 색인이 있어야 도는 쿼리다** — `where(userId) + orderBy(createdAt)`는
  /// `(userId ASC, createdAt DESC)` 색인을 요구하고, 없으면 목록이 뜨는 대신
  /// FAILED_PRECONDITION으로 스트림이 죽는다(제출은 영향 없음).
  /// 정의는 firestore.indexes.json에 있고, 배포해야 실제로 적용된다.
  static Stream<List<FeedbackRequest>> myFeedbackStream() {
    if (UserSession.userId.isEmpty) return const Stream.empty();
    return _col
        .where('userId', isEqualTo: UserSession.userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(FeedbackRequest.fromDoc).toList());
  }
}

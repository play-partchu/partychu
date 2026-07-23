import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:party_app/models/feedback_request.dart';
import 'package:party_app/services/cloudflare_service.dart';
import 'package:party_app/utils/user_session.dart';

/// 의견 보내기 — 모바일 앱 전용 제출/조회 서비스.
/// (관리자 웹은 별도로 Firestore를 직접 다룬다 — dart:io를 쓰는 이 파일은
///  웹 빌드에 포함시키지 않기 위해 admin 코드에서는 import하지 않는다.)
class FeedbackService {
  FeedbackService._();

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

    try {
      final deviceInfoPlugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        platform = 'Android';
        final info = await deviceInfoPlugin.androidInfo;
        osVersion = 'Android ${info.version.release} (SDK ${info.version.sdkInt})';
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
    required List<File> images,
    String? relatedScreen,
  }) async {
    if (UserSession.userId.isEmpty) {
      throw Exception('로그인이 필요합니다.');
    }

    final imageUrls = <String>[];
    for (final file in images.take(3)) {
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
      'relatedScreen': relatedScreen,
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
  static Stream<List<FeedbackRequest>> myFeedbackStream() {
    if (UserSession.userId.isEmpty) return const Stream.empty();
    return _col
        .where('userId', isEqualTo: UserSession.userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(FeedbackRequest.fromDoc).toList());
  }
}

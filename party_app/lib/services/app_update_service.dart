import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';

/// 앱 실행 시 필요한 조치.
enum AppUpdateStatus {
  /// 최신 버전 — 아무것도 하지 않음.
  none,

  /// 신버전이 있지만 강제는 아님 — 사용자가 "나중에"를 고를 수 있음.
  optional,

  /// 현재 버전이 최소 지원 버전보다 낮음 — 업데이트 전까지 앱 사용 불가.
  force,
}

class AppUpdateInfo {
  final AppUpdateStatus status;
  final String currentVersion;
  final String latestVersion;
  final String storeUrl;
  final String message;

  const AppUpdateInfo({
    required this.status,
    required this.currentVersion,
    required this.latestVersion,
    required this.storeUrl,
    required this.message,
  });

  static const none = AppUpdateInfo(
    status: AppUpdateStatus.none,
    currentVersion: '',
    latestVersion: '',
    storeUrl: '',
    message: '',
  );
}

/// 앱 업데이트 정책 — Firestore `appConfig/version` 문서 하나로 관리한다.
/// 코드 배포 없이 이 문서의 값만 바꾸면 강제/선택 업데이트 정책을 즉시 바꿀 수 있다.
///
/// 문서 구조 (Firebase Console에서 직접 생성):
/// ```
/// appConfig/version
/// {
///   android: {
///     latestVersion: "1.4.0",
///     minVersion:    "1.2.0",   // 이 버전 미만이면 강제 업데이트
///     storeUrl:      "https://play.google.com/store/apps/details?id=com.partychu.app",
///     message:       "새로운 기능이 추가되었습니다."  // 선택, 없으면 기본 문구 사용
///   },
///   ios: {
///     latestVersion: "1.4.0",
///     minVersion:    "1.2.0",
///     storeUrl:      "https://apps.apple.com/app/id0000000000",
///     message:       "..."
///   }
/// }
/// ```
class AppUpdateService {
  static const _docPath = 'appConfig/version';

  /// 네트워크 장애 등으로 확인이 안 되면 "확인 실패"로 앱 사용을 막지 않는다
  /// (업데이트 확인은 부가 기능이지 인증 게이트가 아님) — 그래서 짧은 timeout 후
  /// 실패 시 무조건 AppUpdateInfo.none을 반환한다.
  static Future<AppUpdateInfo> check() async {
    if (kIsWeb) return AppUpdateInfo.none; // 웹은 배포 즉시 반영되므로 대상 아님

    final platformKey = Platform.isAndroid
        ? 'android'
        : Platform.isIOS
            ? 'ios'
            : null;
    if (platformKey == null) return AppUpdateInfo.none;

    try {
      final snap = await FirebaseFirestore.instance
          .doc(_docPath)
          .get()
          .timeout(const Duration(seconds: 5));

      if (!snap.exists) return AppUpdateInfo.none;

      final platformData = snap.data()?[platformKey] as Map<String, dynamic>?;
      if (platformData == null) return AppUpdateInfo.none;

      final latestVersion = platformData['latestVersion'] as String? ?? '';
      final minVersion = platformData['minVersion'] as String? ?? '';
      final storeUrl = platformData['storeUrl'] as String? ?? '';
      final message = platformData['message'] as String? ??
          '새로운 버전이 출시되었습니다.\n최신 기능을 사용해보세요.';

      if (latestVersion.isEmpty || storeUrl.isEmpty) return AppUpdateInfo.none;

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      if (minVersion.isNotEmpty &&
          _compareVersions(currentVersion, minVersion) < 0) {
        return AppUpdateInfo(
          status: AppUpdateStatus.force,
          currentVersion: currentVersion,
          latestVersion: latestVersion,
          storeUrl: storeUrl,
          message: message,
        );
      }

      if (_compareVersions(currentVersion, latestVersion) < 0) {
        return AppUpdateInfo(
          status: AppUpdateStatus.optional,
          currentVersion: currentVersion,
          latestVersion: latestVersion,
          storeUrl: storeUrl,
          message: message,
        );
      }

      return AppUpdateInfo.none;
    } catch (e) {
      // 오프라인/타임아웃/문서 형식 오류 등 — 조용히 실패 처리(fail-open)
      return AppUpdateInfo.none;
    }
  }

  /// "1.4.0" vs "1.2.10" 같은 점(.) 구분 버전 문자열 비교.
  /// a < b 이면 음수, 같으면 0, a > b 이면 양수.
  /// 구성요소 개수가 다르면 없는 자리는 0으로 취급하고, 숫자가 아닌 조각은 0으로 취급한다.
  static int _compareVersions(String a, String b) {
    final aParts = a.split('.');
    final bParts = b.split('.');
    final length = aParts.length > bParts.length ? aParts.length : bParts.length;

    for (var i = 0; i < length; i++) {
      final aVal = i < aParts.length ? int.tryParse(aParts[i]) ?? 0 : 0;
      final bVal = i < bParts.length ? int.tryParse(bParts[i]) ?? 0 : 0;
      if (aVal != bVal) return aVal - bVal;
    }
    return 0;
  }
}

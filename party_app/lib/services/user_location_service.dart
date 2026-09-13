import 'package:flutter/foundation.dart' show debugPrint;
import 'package:geolocator/geolocator.dart';

/// 화면들이 "현재 위치가 이미 있으면 쓰고, 없으면 조용히 포기"할 때 쓰는 통로.
///
/// ## 권한을 **요청하지 않는다**
///
/// 상세 화면의 "내 위치에서 N km"는 부가 정보다. 그 문구 하나 때문에 화면을 열
/// 때마다 권한 팝업이 뜨면 안 되므로 [Geolocator.checkPermission]으로 **이미
/// 허용돼 있는지 확인만** 하고, 아니면 null을 돌려준다(호출부는 문구를 숨긴다).
/// 권한을 실제로 요청하는 곳은 사용자가 그 기능을 고른 지점(목록 거리순 정렬,
/// 지도의 "현재 위치" 버튼)뿐이다.
///
/// ## 매번 GPS를 켜지 않는다
///
/// 마지막으로 알려진 위치를 먼저 보고, 없을 때만 저정확도로 한 번 측정한다.
/// 결과는 [_ttl] 동안 캐시하므로 상세 화면을 여러 번 드나들어도 측위는 다시
/// 일어나지 않는다. 위치는 앱 밖에서 계산되므로 외부 API 호출도 없다.
class UserLocationService {
  UserLocationService._();

  static Position? _cached;
  static DateTime? _cachedAt;

  /// 캐시 수명 — 이 안에서는 같은 좌표를 그대로 돌려준다. 거리 표시는 100m
  /// 단위로 읽히는 값이라 몇 분 지난 위치로도 충분하다.
  static const Duration _ttl = Duration(minutes: 5);

  /// 지금 쓸 수 있는 현재 위치. 권한이 없거나 측위에 실패하면 **null**이다
  /// (예외를 던지지 않는다 — 호출부는 표시를 생략하면 된다).
  static Future<Position?> currentOrNull() async {
    final cached = _cached;
    final at = _cachedAt;
    if (cached != null && at != null && DateTime.now().difference(at) < _ttl) {
      return cached;
    }

    try {
      final permission = await Geolocator.checkPermission();
      final granted =
          permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
      // denied / deniedForever / unableToDetermine — 어느 쪽이든 요청하지 않고
      // 그냥 포기한다.
      if (!granted) return null;
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      final last = await Geolocator.getLastKnownPosition();
      final position =
          last ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: Duration(seconds: 5),
            ),
          );
      _cached = position;
      _cachedAt = DateTime.now();
      return position;
    } catch (e) {
      // 권한 조회 자체가 막힌 플랫폼(웹 등)이나 측위 타임아웃 — 조용히 없음.
      debugPrint('[UserLocation] 현재 위치를 쓸 수 없음: $e');
      return null;
    }
  }
}

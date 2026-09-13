import 'dart:math';

/// 좌표 사이 거리 계산·표기 — **외부 API를 부르지 않는다.**
///
/// 상세 화면의 "내 위치에서 N" 같은 표시 때문에 화면을 열 때마다 지도 API를
/// 호출하면 비용도 지연도 그대로 늘어난다. 직선거리는 좌표만 있으면 앱 안에서
/// 계산할 수 있으므로 여기서 끝낸다(거리순 정렬도 같은 함수를 쓴다).

/// 두 좌표 사이 직선거리(m). Haversine — 지구를 반지름 6371km 구로 본다.
///
/// 도보 경로가 아니라 직선이다. 화면 문구도 "내 위치에서 2.3km"처럼 대략적인
/// 감을 주는 용도이므로 이 정도면 충분하다.
double distanceMetersBetween(
  double lat1,
  double lng1,
  double lat2,
  double lng2,
) {
  const earthRadius = 6371000.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLng = (lng2 - lng1) * pi / 180;
  final a =
      sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) *
          cos(lat2 * pi / 180) *
          sin(dLng / 2) *
          sin(dLng / 2);
  return 2 * earthRadius * atan2(sqrt(a), sqrt(1 - a));
}

/// 사람이 읽는 거리 — 1km 미만은 '650m'(10m 단위), 그 이상은 '2.3km'.
///
/// 10m 단위로 끊는 이유: 직선거리라 한 자리 m까지 맞을 수 없는데 '653m'라고
/// 적으면 실제보다 정확해 보인다.
String formatDistanceLabel(double meters) {
  if (meters < 0) return '';
  if (meters < 1000) {
    final rounded = (meters / 10).round() * 10;
    // 995m처럼 반올림 결과가 1000m가 되면 km 표기로 넘긴다.
    if (rounded < 1000) return '${rounded}m';
  }
  return '${(meters / 1000).toStringAsFixed(1)}km';
}

/// 좌표가 실제로 쓸 만한지 — null이거나 (0, 0)이면 "없음"으로 본다
/// (등록 과정에서 지오코딩이 실패하면 0이 남는 문서가 있다).
bool hasUsableCoords(double? lat, double? lng) =>
    lat != null && lng != null && !(lat == 0 && lng == 0);

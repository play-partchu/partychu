// 지도 자동 재조회 — "언제 다시 찾을지"의 순수 규칙.
//
// 예전에는 지도를 움직이면 '이 지역에서 다시 찾기' 버튼이 떴고, 사용자가 눌러야
// 그 영역으로 목록·마커가 좁혀졌다. 지금은 카메라가 멈추면 앱이 알아서 한다.
//
// 그래서 두 가지 판단이 필요해졌다. 언제까지 기다렸다 할 것인가(debounce)와,
// 어느 정도 움직여야 할 것인가(이 파일). 둘 다 화면 없이 검증할 수 있게
// 여기 순수 함수로 둔다.
//
// ⚠ 이 조회는 **네트워크 요청이 아니다.** 지도 데이터는 컬렉션 구독으로 이미
//   메모리에 있고(map_screen의 ListingSources.*.snapshots()), 여기서 말하는
//   '조회'는 그 목록을 지금 화면 영역으로 거르는 계산이다. 그래도 마커를 다시
//   굽는 비용이 있어 쓸데없이 자주 돌리지 않는다.

/// 카메라가 멈춘 뒤 이만큼 더 기다렸다가 조회한다.
///
/// 드래그 → 확대 → 다시 드래그처럼 이어지는 조작에서는 그때마다 타이머를
/// 다시 걸어, **마지막 위치에서 한 번만** 돌게 한다.
const Duration kMapAutoSearchDebounce = Duration(milliseconds: 500);

/// 지도에 보이는 영역. 화면 코드의 `_boxOf`가 주는 것과 같은 모양이다.
typedef MapViewBox = ({double south, double west, double north, double east});

double _latSpan(MapViewBox b) => (b.north - b.south).abs();
double _lngSpan(MapViewBox b) => (b.east - b.west).abs();

/// 지난번 조회한 영역([last])과 견줘 다시 조회할 만큼 움직였는가.
///
/// 기준을 미터가 아니라 **화면 폭에 대한 비율**로 잡는다. 시·도가 다 보이는
/// 줌에서의 1km와 골목이 보이는 줌에서의 1km는 뜻이 전혀 다르기 때문이다.
///
///  · [moveRatio]  중심이 화면 폭의 이만큼 넘게 움직였으면 다시 찾는다.
///  · [zoomRatio]  보이는 폭이 이 비율 넘게 커지거나 작아졌으면 다시 찾는다
///                 (제자리 확대·축소를 잡는다).
///
/// 손가락이 스치거나 관성으로 몇 픽셀 밀린 정도로는 돌지 않는다.
bool mapViewChangedEnough(
  MapViewBox? last,
  MapViewBox now, {
  double moveRatio = 0.15,
  double zoomRatio = 0.2,
}) {
  // 아직 한 번도 조회하지 않았으면 무조건 한다.
  if (last == null) return true;

  final lastLat = _latSpan(last);
  final lastLng = _lngSpan(last);
  // 폭을 모르면(0이거나 이상한 값) 비율을 따질 수 없다 — 그냥 조회한다.
  if (lastLat <= 0 || lastLng <= 0) return true;

  final movedLat =
      ((now.north + now.south) - (last.north + last.south)).abs() / 2;
  final movedLng = ((now.east + now.west) - (last.east + last.west)).abs() / 2;
  if (movedLat > lastLat * moveRatio) return true;
  if (movedLng > lastLng * moveRatio) return true;

  final zoomedLat = (_latSpan(now) - lastLat).abs() / lastLat;
  final zoomedLng = (_lngSpan(now) - lastLng).abs() / lastLng;
  if (zoomedLat > zoomRatio || zoomedLng > zoomRatio) return true;

  return false;
}

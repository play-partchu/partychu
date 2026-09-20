import 'package:party_app/models/map_listing.dart';

/// 지도 마커를 눌렀을 때 할 일.
enum MapMarkerTapAction {
  /// 🎊 공공 축제 하나 — 곧장 공공 축제 상세.
  openFestivalDetail,

  /// 파티츄 콘텐츠 하나 — 미리보기 카드(홈은 강조 마커 + 작은 카드).
  previewSingle,

  /// 겹친 묶음 — 그 자리의 목록(겹침 시트)을 바로 연다.
  openGroupList,
}

/// 마커 탭의 결정 — 무엇을 열지와 **카메라를 옮길지**.
///
/// 묶음(2개 이상)은 **줌과 상관없이** 한 번 누르면 바로 목록이다. 예전에는
/// 홈에서 확대(zoomBy 2)를 먼저 하고 17 이상일 때만 목록을 열어, 묶음 하나를
/// 풀려면 여러 번 눌러야 했다. 묶음을 누를 때는 카메라를 전혀 옮기지 않는다.
///
/// 하나짜리는 예전 그대로다 — 파티츄 콘텐츠는 그 자리로 가운데 맞춤 후
/// 미리보기, 공공 축제는 카메라를 옮기지 않고 곧장 상세.
({MapMarkerTapAction action, bool centerCamera}) mapMarkerTapPlan(
  List<MapListing> items,
) {
  if (items.length >= 2) {
    return (action: MapMarkerTapAction.openGroupList, centerCamera: false);
  }
  if (items.single.kind == MapListingKind.festival) {
    return (action: MapMarkerTapAction.openFestivalDetail, centerCamera: false);
  }
  return (action: MapMarkerTapAction.previewSingle, centerCamera: true);
}

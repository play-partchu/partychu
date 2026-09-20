import 'package:party_app/models/map_listing.dart';

/// 지도 홈 상단의 가로 카테고리 한 칸.
///
/// **새 조건을 만들지 않는다** — 지도가 원래 쓰던 두 값의 조합일 뿐이다:
///   · [kinds] → 종류 선택(파티·플레이스·장소대여 중 무엇을 올릴지)
///   · [eventOnly] → 🎪 '이벤트 하는 곳만'(매장 이벤트·공간 이벤트 정본,
///     목록 탭의 🎪 이벤트 칸과 같은 판정)
///
/// 칸을 늘릴 때는 아래 목록에 한 줄을 더하면 된다. 단 **DB에 실제로 있는
/// 축**으로만 만든다(없는 카테고리를 임의로 만들지 않는다).
class MapHomeCategory {
  final String label;
  final Set<MapListingKind> kinds;
  final bool eventOnly;

  const MapHomeCategory({
    required this.label,
    required this.kinds,
    this.eventOnly = false,
  });
}

const List<MapHomeCategory> mapHomeCategories = [
  // 전체 = 지도에 올릴 수 있는 것 전부 — 🎊 공공 축제도 들어간다(이벤트가
  // 전체에 포함되는 것과 같은 정책).
  MapHomeCategory(
    label: '전체',
    kinds: {
      MapListingKind.party,
      MapListingKind.place,
      MapListingKind.rental,
      MapListingKind.festival,
    },
  ),
  MapHomeCategory(label: '파티', kinds: {MapListingKind.party}),
  // 이벤트 = 매장 이벤트(플레이스) + 공간 이벤트(장소대여) + 🎊 공공 축제.
  // 앞의 둘은 목록 탭의 🎪 이벤트 칸과 같은 정본·같은 판정이고
  // ([PlaceEventIndex]), 공공 축제는 그 자체가 행사라 그대로 통과한다.
  MapHomeCategory(
    label: '이벤트',
    kinds: {
      MapListingKind.place,
      MapListingKind.rental,
      MapListingKind.festival,
    },
    eventOnly: true,
  ),
  MapHomeCategory(label: '플레이스', kinds: {MapListingKind.place}),
  MapHomeCategory(label: '장소대여', kinds: {MapListingKind.rental}),
];

/// 지도 홈 카테고리 선택([selected] = 켜 둔 칸 번호, 비었으면 '전체') →
/// 지도에 올릴 종류. 켜 둔 칸들의 합집합이다.
Set<MapListingKind> mapHomeKindsFor(Set<int> selected) => selected.isEmpty
    ? {...mapHomeCategories[0].kinds}
    : {for (final i in selected) ...mapHomeCategories[i].kinds};

/// 지도 화면이 **처음** 올릴 종류.
///
/// 홈은 '전체'로 시작하므로 '전체' 칸의 종류(🎊 공공 축제 포함)다. 예전에는
/// 홈도 지도 화면과 같은 파티츄 세 종류로 시작해서, 카테고리 칸을 한 번도
/// 누르지 않은 '전체' 상태에서는 공공 축제 구독 조건(종류에 festival 포함)이
/// 성립하지 않았다 — '전체'를 다시 눌러도 선택이 그대로라 바뀌지 않았다.
///
/// 지도 화면(하단 목록 시트)은 종류 칩이 파티츄 세 종류뿐이라 그대로다.
Set<MapListingKind> mapInitialKinds({required bool home}) => home
    ? mapHomeKindsFor(const {})
    : MapListingKind.listingKinds.toSet();

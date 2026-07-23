/// 장소대여 탭 전용 상세검색 필터.
/// 파티(PartyFilter)와 완전히 분리된 모델 — 장소 서비스 특성에 맞는 항목만 보유.
class PlaceFilter {
  Set<String> regions;
  Set<String> priceRanges;
  Set<String> capacityRanges;
  Set<String> placeTypes;
  Set<String> facilities;

  PlaceFilter({
    Set<String>? regions,
    Set<String>? priceRanges,
    Set<String>? capacityRanges,
    Set<String>? placeTypes,
    Set<String>? facilities,
  })  : regions = regions ?? {},
        priceRanges = priceRanges ?? {},
        capacityRanges = capacityRanges ?? {},
        placeTypes = placeTypes ?? {},
        facilities = facilities ?? {};

  bool get isActive =>
      regions.isNotEmpty ||
      priceRanges.isNotEmpty ||
      capacityRanges.isNotEmpty ||
      placeTypes.isNotEmpty ||
      facilities.isNotEmpty;

  PlaceFilter copy() => PlaceFilter(
        regions: {...regions},
        priceRanges: {...priceRanges},
        capacityRanges: {...capacityRanges},
        placeTypes: {...placeTypes},
        facilities: {...facilities},
      );

  List<MapEntry<String, String>> get selectedEntries => [
        ...regions.map((v) => MapEntry('regions', v)),
        ...priceRanges.map((v) => MapEntry('priceRanges', v)),
        ...capacityRanges.map((v) => MapEntry('capacityRanges', v)),
        ...placeTypes.map((v) => MapEntry('placeTypes', v)),
        ...facilities.map((v) => MapEntry('facilities', v)),
      ];

  void removeValue(String category, String value) {
    switch (category) {
      case 'regions':
        regions.remove(value);
        break;
      case 'priceRanges':
        priceRanges.remove(value);
        break;
      case 'capacityRanges':
        capacityRanges.remove(value);
        break;
      case 'placeTypes':
        placeTypes.remove(value);
        break;
      case 'facilities':
        facilities.remove(value);
        break;
    }
  }
}

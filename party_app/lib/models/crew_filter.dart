/// 파티크루(파트너) 탭 전용 상세검색 필터.
/// 파티(PartyFilter)와 완전히 분리된 모델 — 구인/구직 서비스 특성에 맞는 항목만 보유.
class CrewFilter {
  Set<String> regions;
  Set<String> roles;
  Set<String> payTypes;
  Set<String> recruitCounts;
  bool beginnerFriendly;
  bool experiencedPreferred;

  CrewFilter({
    Set<String>? regions,
    Set<String>? roles,
    Set<String>? payTypes,
    Set<String>? recruitCounts,
    this.beginnerFriendly = false,
    this.experiencedPreferred = false,
  }) : regions = regions ?? {},
       roles = roles ?? {},
       payTypes = payTypes ?? {},
       recruitCounts = recruitCounts ?? {};

  bool get isActive =>
      regions.isNotEmpty ||
      roles.isNotEmpty ||
      payTypes.isNotEmpty ||
      recruitCounts.isNotEmpty ||
      beginnerFriendly ||
      experiencedPreferred;

  CrewFilter copy() => CrewFilter(
    regions: {...regions},
    roles: {...roles},
    payTypes: {...payTypes},
    recruitCounts: {...recruitCounts},
    beginnerFriendly: beginnerFriendly,
    experiencedPreferred: experiencedPreferred,
  );

  List<MapEntry<String, String>> get selectedEntries => [
    ...regions.map((v) => MapEntry('regions', v)),
    ...roles.map((v) => MapEntry('roles', v)),
    ...payTypes.map((v) => MapEntry('payTypes', v)),
    ...recruitCounts.map((v) => MapEntry('recruitCounts', v)),
    if (beginnerFriendly) const MapEntry('beginnerFriendly', '초보 가능'),
    if (experiencedPreferred) const MapEntry('experiencedPreferred', '경력 우대'),
  ];

  void removeValue(String category, String value) {
    switch (category) {
      case 'regions':
        regions.remove(value);
        break;
      case 'roles':
        roles.remove(value);
        break;
      case 'payTypes':
        payTypes.remove(value);
        break;
      case 'recruitCounts':
        recruitCounts.remove(value);
        break;
      case 'beginnerFriendly':
        beginnerFriendly = false;
        break;
      case 'experiencedPreferred':
        experiencedPreferred = false;
        break;
    }
  }
}

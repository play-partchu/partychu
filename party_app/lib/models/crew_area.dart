import 'package:party_app/models/region_data.dart';

/// 파티크루(구인·구직) 활동 지역 한 칸 — 시/도 + 구/군, 또는 시/도 전체.
///
/// 지역 목록은 앱 공용 [RegionData](파티 등록·상세검색, 장소 필터가 함께 쓰는
/// 2단계 시/도→구/군 데이터)를 그대로 쓴다 — 파티크루용 목록을 따로 두지
/// 않는다. 다만 '온라인'은 파티크루에만 있는 활동 형태라 시/도 자리에 한 칸만
/// 덧붙인다(구/군이 없어 '전체'만 고를 수 있다).
class CrewArea {
  /// 시/도 ('서울', '경기', … 또는 [online]).
  final String region;

  /// 구/군. null이면 그 시/도 **전 지역**(화면의 '전체').
  final String? district;

  const CrewArea(this.region, [this.district]);

  static const online = '온라인';
  static const allLabel = '전체';

  /// 첫 단계(시/도) 목록.
  static List<String> get regions => [...RegionData.regions, online];

  /// 두 번째 단계(구/군) 목록 — 화면에는 이 앞에 [allLabel]이 먼저 붙는다.
  /// '온라인'처럼 구/군이 없는 시/도는 빈 목록이라 '전체'만 남는다.
  static List<String> districtsOf(String region) =>
      RegionData.regionDistricts[region] ?? const [];

  bool get isWholeRegion => district == null;

  /// "서울 전체" / "서울 강남구" — 화면 표시 문구이자 Firestore 저장값.
  /// '온라인'처럼 구/군이 없는 시/도는 "온라인 전체"가 어색하므로 이름만 쓴다.
  String get label {
    if (district != null) return '$region $district';
    return districtsOf(region).isEmpty ? region : '$region $allLabel';
  }

  /// 저장값 되읽기. "서울 강남구" · "서울 전체" · "서울"(구버전, 광역만 저장돼
  /// 있던 값)을 모두 받는다.
  static CrewArea? parse(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    final sp = v.indexOf(' ');
    if (sp < 0) return CrewArea(v);
    final region = v.substring(0, sp);
    final rest = v.substring(sp + 1).trim();
    if (rest.isEmpty || rest == allLabel) return CrewArea(region);
    return CrewArea(region, rest);
  }

  /// crews 문서(또는 임시저장 payload) → 활동 지역 목록.
  ///
  /// 새 필드 `regionAreas`를 먼저 보고, 없으면 광역만 저장돼 있던 기존 문서
  /// (`regions`, 더 오래된 단일 `region`)를 "그 시/도 전체"로 살려 읽는다 —
  /// 옛 글을 수정 화면에서 열어도 선택이 비어 보이지 않는다.
  static List<CrewArea> fromCrewData(Map<String, dynamic> d) {
    final areas = d['regionAreas'];
    if (areas is List && areas.isNotEmpty) {
      return areas
          .whereType<String>()
          .map(parse)
          .whereType<CrewArea>()
          .toList();
    }
    final regions = d['regions'];
    if (regions is List && regions.isNotEmpty) {
      return regions.whereType<String>().map(CrewArea.new).toList();
    }
    final legacy = (d['region'] as String? ?? '').trim();
    return legacy.isEmpty ? const [] : [CrewArea(legacy)];
  }

  /// crews 문서에 저장할 지역 필드 3종 — 셋 다 이 함수에서만 만들어 서로
  /// 어긋나지 않게 한다.
  ///
  /// - `regionAreas`: 정본. 시/도와 구/군이 짝으로 남아 "대구 중구"와
  ///   "서울 중구"를 구분할 수 있다(동명 구가 여러 시/도에 있다).
  /// - `regions`: 광역만 뽑은 목록. 기존 파티크루 상세검색(광역 단위)과
  ///   목록 필터가 그대로 동작한다.
  /// - `districts`: 구/군만 뽑은 목록. 파티·장소가 쓰는 필드명과 같아서
  ///   나중에 구/군 단위 검색을 붙일 때 바로 쓸 수 있다('전체'는 제외).
  static Map<String, dynamic> toCrewFields(Iterable<CrewArea> areas) {
    final list = areas.toList();
    return {
      'regionAreas': list.map((a) => a.label).toList(),
      'regions': list.map((a) => a.region).toSet().toList(),
      'districts': list
          .map((a) => a.district)
          .whereType<String>()
          .toSet()
          .toList(),
    };
  }

  /// 카드·상세에서 쓰는 한 줄 표시 ("서울 강남구 · 부산 전체").
  static String labelOfCrewData(
    Map<String, dynamic> d, {
    String separator = ' · ',
  }) => fromCrewData(d).map((a) => a.label).join(separator);

  @override
  bool operator ==(Object other) =>
      other is CrewArea && other.region == region && other.district == district;

  @override
  int get hashCode => Object.hash(region, district);

  @override
  String toString() => label;
}

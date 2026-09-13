/// 플레이스의 "선택형 부가 정보" — 좌석·공간 유형, 이용 편의 옵션, 그리고
/// 앞으로 추가될 흡연실·주차·콘센트·와이파이·빔프로젝터 같은 편의시설까지
/// **하나의 확장 가능한 구조**로 담는다.
///
/// 새 항목이나 새 그룹을 추가할 때 고쳐야 하는 곳은 [PlaceFacilityCatalog]
/// 하나뿐이다. 등록/수정/콤보 등록/임시저장/상세페이지/목록 카드는 전부 이
/// 카탈로그를 읽어 그리므로, 카탈로그에 그룹 하나를 더하면 모든 화면에
/// 자동으로 반영된다(화면 코드 수정 불필요).
///
/// 저장 형태(Firestore) — 문서의 `facilityOptions` 필드:
/// ```
/// facilityOptions: {
///   seatingTypes: {
///     selected: ['개별룸', '단체석'],
///     capacities: { '개별룸': 35, '단체석': 80 },   // 인원 입력을 지원하는 그룹만
///   },
///   seatingConveniences: { selected: ['1인 방문 가능'] },
///   // 앞으로: smoking: {...}, parking: {...} — 그룹 키만 늘어난다.
/// }
/// ```
/// 저장값은 화면에 보이는 한국어 라벨 그대로다 — 기존 `themeTags`,
/// `commonFacilities`와 동일한 관례이며, 콘솔에서 바로 읽히고
/// `array-contains` 필터에도 그대로 쓸 수 있다. 그래서 **라벨 문자열은
/// 한 번 배포된 뒤에는 바꾸지 않는다**(바꾸면 기존 문서와 매칭이 끊긴다).
library;

/// 그룹 안의 선택지 하나.
class PlaceFacilityOption {
  /// 저장값이자 상세페이지 표시값. 배포 후 변경 금지(위 주석 참고).
  final String label;

  /// 상세페이지/목록에서 라벨 앞에 붙는 아이콘.
  final String emoji;

  /// 등록 화면 선택지에만 쓰는 짧은 표기. 그룹 제목이 이미 맥락을 주는데
  /// 선택지까지 길게 반복하면("외부 음식 반입" > "외부 음식 반입 가능")
  /// 읽기 나쁘기 때문이다. 생략하면 [label]을 그대로 쓴다.
  final String? pickerLabel;

  const PlaceFacilityOption(this.label, this.emoji, {this.pickerLabel});

  /// 등록 화면에 그릴 문구.
  String get shortLabel => pickerLabel ?? label;
}

/// 선택지 묶음 하나(= Firestore 하위 키 하나).
class PlaceFacilityGroup {
  /// Firestore `facilityOptions` 안의 키.
  final String key;

  /// 펼친 화면에서 보여줄 소제목.
  final String title;

  /// 소제목 옆 안내 문구(없으면 생략).
  final String? hint;

  final List<PlaceFacilityOption> options;

  /// true면 선택한 항목마다 "최대 N명"을 함께 입력받는다(좌석 유형 등).
  final bool supportsCapacity;

  /// true면 그룹 안에서 **하나만** 고를 수 있다 — 새로 고르면 이전 선택이
  /// 대체된다. "가능/불가능/협의 후 가능"처럼 서로 배타적인 정책용이다
  /// (다중 선택이면 "가능"과 "불가능"을 동시에 켤 수 있어 버린다).
  final bool singleChoice;

  const PlaceFacilityGroup({
    required this.key,
    required this.title,
    required this.options,
    this.hint,
    this.supportsCapacity = false,
    this.singleChoice = false,
  });

  PlaceFacilityOption? optionOf(String label) {
    for (final o in options) {
      if (o.label == label) return o;
    }
    return null;
  }
}

/// 앱 전체가 공유하는 선택지 정의. **새 편의시설은 여기에만 추가한다.**
class PlaceFacilityCatalog {
  PlaceFacilityCatalog._();

  static const seatingTypes = PlaceFacilityGroup(
    key: 'seatingTypes',
    title: '좌석·공간 유형',
    hint: '해당하는 좌석과 공간을 모두 골라주세요.',
    supportsCapacity: true,
    options: [
      PlaceFacilityOption('개별룸', '🚪'),
      PlaceFacilityOption('단체석', '👥'),
      PlaceFacilityOption('카운터석', '🍸'),
      PlaceFacilityOption('바 테이블', '🍺'),
      PlaceFacilityOption('일반 테이블', '🍽️'),
      PlaceFacilityOption('스탠딩 공간', '🕺'),
      PlaceFacilityOption('2인석', '💑'),
      PlaceFacilityOption('1인석', '🪑'),
      PlaceFacilityOption('야외석', '🌿'),
    ],
  );

  static const seatingConveniences = PlaceFacilityGroup(
    key: 'seatingConveniences',
    title: '이용 편의 옵션',
    options: [
      PlaceFacilityOption('1인 방문 가능', '🙋'),
      PlaceFacilityOption('혼자 앉기 편한 좌석', '😌'),
      PlaceFacilityOption('합석 가능', '🤝'),
      PlaceFacilityOption('단체 이용 가능', '🎉'),
      PlaceFacilityOption('전체 대관 가능', '🏠'),
    ],
  );

  /// 외부 음식 반입 — 서로 배타적인 셋 중 하나만 고른다.
  ///
  /// 저장값(=상세페이지 표기)은 길게 두고 등록 화면 선택지만 짧게 쓴다
  /// ([PlaceFacilityOption.pickerLabel]) — 상세에서는 "🍕 외부 음식 반입
  /// 가능"처럼 그 자체로 읽혀야 하고, 등록 화면에서는 그룹 제목이 이미
  /// 맥락을 주기 때문이다.
  static const outsideFood = PlaceFacilityGroup(
    key: 'outsideFood',
    title: '외부 음식 반입',
    hint: '손님이 음식을 사 와도 되는지 한 가지만 골라주세요.',
    singleChoice: true,
    options: [
      PlaceFacilityOption('외부 음식 반입 가능', '🍕', pickerLabel: '가능'),
      PlaceFacilityOption('외부 음식 반입 불가', '🚫', pickerLabel: '불가능'),
      PlaceFacilityOption('외부 음식 협의 가능', '📞', pickerLabel: '협의 후 가능'),
    ],
  );

  /// 상세검색의 "외부 음식 가능만 보기"가 찾는 저장값 — 화면과 필터가 같은
  /// 상수를 보게 해서 문구가 갈려 매칭이 끊기는 일을 막는다.
  static const String outsideFoodAllowedLabel = '외부 음식 반입 가능';

  /// "🪑 좌석·공간" 섹션 하나가 보여주는 그룹들.
  static const seatingSection = <PlaceFacilityGroup>[
    seatingTypes,
    seatingConveniences,
  ];

  /// "🍽 외부 음식" 섹션.
  static const foodSection = <PlaceFacilityGroup>[outsideFood];

  /// 저장/복원이 인식하는 전체 그룹. 새 섹션을 만들면 여기에도 더한다.
  static const all = <PlaceFacilityGroup>[...seatingSection, ...foodSection];

  static PlaceFacilityGroup? groupOf(String key) {
    for (final g in all) {
      if (g.key == key) return g;
    }
    return null;
  }

  /// 라벨에 대응하는 이모지 — 카탈로그에 없는(예전에 저장된) 라벨은 기본값.
  static String emojiFor(String label) {
    for (final g in all) {
      final o = g.optionOf(label);
      if (o != null) return o.emoji;
    }
    return '•';
  }
}

/// 선택 결과. 불변(immutable) — 바꿀 때는 [toggle]/[withCapacity]가 새 인스턴스를
/// 돌려준다.
class PlaceFacilityOptions {
  /// 그룹 키 → 선택된 라벨들.
  final Map<String, Set<String>> selections;

  /// 그룹 키 → 라벨 → 최대 이용 인원. 인원 입력을 지원하는 그룹에서만 쓴다.
  final Map<String, Map<String, int>> capacities;

  const PlaceFacilityOptions._(this.selections, this.capacities);

  factory PlaceFacilityOptions.empty() => const PlaceFacilityOptions._({}, {});

  bool get isEmpty => selections.values.every((s) => s.isEmpty);

  bool get isNotEmpty => !isEmpty;

  Set<String> selected(String groupKey) =>
      selections[groupKey] ?? const <String>{};

  bool isSelected(String groupKey, String label) =>
      selected(groupKey).contains(label);

  /// 이 그룹들 중 하나라도 고른 것이 있는지 — 섹션 제목을 그릴지 말지 판단할
  /// 때 쓴다. 그룹이 여럿인 지금은 [isNotEmpty]로 판단하면 안 된다(예: 외부
  /// 음식만 고른 문서에서 "좌석·공간" 제목만 덩그러니 남는다).
  bool hasAnyIn(List<PlaceFacilityGroup> groups) =>
      groups.any((g) => selected(g.key).isNotEmpty);

  int? capacityOf(String groupKey, String label) =>
      capacities[groupKey]?[label];

  /// 선택을 켜고 끈다. 끌 때는 그 항목의 인원 값도 함께 지운다.
  ///
  /// 단일 선택 그룹([PlaceFacilityGroup.singleChoice])이면 새로 고른 것이
  /// 이전 선택을 **대체**한다. 그룹 성격은 카탈로그에서 직접 찾으므로
  /// 호출부(등록 화면·임시저장 복원 등)가 따로 신경 쓸 것이 없다.
  PlaceFacilityOptions toggle(String groupKey, String label) {
    final nextSelections = _copySelections();
    final set = nextSelections.putIfAbsent(groupKey, () => <String>{});
    final nextCapacities = _copyCapacities();
    if (set.contains(label)) {
      // 고른 것을 다시 누르면 해제 — 단일 선택 그룹도 "미지정"으로 되돌릴 수
      // 있어야 한다(잘못 골랐을 때 빠져나갈 길이 없으면 안 된다).
      set.remove(label);
      nextCapacities[groupKey]?.remove(label);
    } else {
      if (PlaceFacilityCatalog.groupOf(groupKey)?.singleChoice ?? false) {
        set.clear();
        nextCapacities[groupKey]?.clear();
      }
      set.add(label);
    }
    return PlaceFacilityOptions._(nextSelections, nextCapacities);
  }

  /// [value]가 null이거나 0 이하면 인원 값을 지운다(= 미입력).
  PlaceFacilityOptions withCapacity(String groupKey, String label, int? value) {
    final nextCapacities = _copyCapacities();
    final group = nextCapacities.putIfAbsent(groupKey, () => <String, int>{});
    if (value == null || value <= 0) {
      group.remove(label);
    } else {
      group[label] = value;
    }
    return PlaceFacilityOptions._(_copySelections(), nextCapacities);
  }

  Map<String, Set<String>> _copySelections() => {
    for (final e in selections.entries) e.key: {...e.value},
  };

  Map<String, Map<String, int>> _copyCapacities() => {
    for (final e in capacities.entries) e.key: {...e.value},
  };

  /// 접힌 헤더·목록 카드에 쓰는 요약. 카탈로그 순서(좌석 유형 → 편의 옵션)를
  /// 그대로 따르므로 "카운터석 · 단체석 · 1인 방문 가능"처럼 대표 항목이
  /// 앞에 온다.
  List<String> summaryLabels({int max = 3}) {
    final result = <String>[];
    for (final group in PlaceFacilityCatalog.all) {
      for (final option in group.options) {
        if (!isSelected(group.key, option.label)) continue;
        result.add(option.label);
        if (result.length >= max) return result;
      }
    }
    return result;
  }

  /// '카운터석 · 단체석 · 1인 방문 가능' — 선택이 없으면 빈 문자열.
  String summaryText({int max = 3}) => summaryLabels(max: max).join(' · ');

  /// 선택한 항목 총 개수.
  int get selectedCount =>
      selections.values.fold(0, (sum, set) => sum + set.length);

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{};
    for (final group in PlaceFacilityCatalog.all) {
      // 카탈로그 순서를 유지해 저장한다(선택 순서에 따라 값이 흔들리지 않게).
      final picked = group.options
          .map((o) => o.label)
          .where((label) => isSelected(group.key, label))
          .toList();
      if (picked.isEmpty) continue;

      final entry = <String, dynamic>{'selected': picked};
      if (group.supportsCapacity) {
        final caps = <String, int>{};
        for (final label in picked) {
          final value = capacityOf(group.key, label);
          if (value != null && value > 0) caps[label] = value;
        }
        if (caps.isNotEmpty) entry['capacities'] = caps;
      }
      map[group.key] = entry;
    }
    return map;
  }

  static PlaceFacilityOptions fromMap(Map<String, dynamic>? map) {
    if (map == null || map.isEmpty) return PlaceFacilityOptions.empty();

    final selections = <String, Set<String>>{};
    final capacities = <String, Map<String, int>>{};

    for (final entry in map.entries) {
      final raw = entry.value;
      if (raw is! Map) continue;
      // 카탈로그에서 빠진 그룹(앱 버전 차이)도 값은 그대로 보존한다 —
      // 옛 버전 앱이 저장을 다시 하면서 남의 데이터를 지우지 않도록.
      final picked = ((raw['selected'] as List?) ?? const [])
          .whereType<String>()
          .toSet();
      if (picked.isNotEmpty) selections[entry.key] = picked;

      final rawCaps = raw['capacities'];
      if (rawCaps is Map) {
        final caps = <String, int>{};
        for (final c in rawCaps.entries) {
          final value = (c.value as num?)?.toInt();
          if (c.key is String && value != null && value > 0) {
            caps[c.key as String] = value;
          }
        }
        if (caps.isNotEmpty) capacities[entry.key] = caps;
      }
    }

    return PlaceFacilityOptions._(selections, capacities);
  }

  /// 임시저장(Draft)도 같은 형태를 쓴다 — Timestamp 같은 특수 타입이 없어
  /// 그대로 JSON 직렬화된다.
  Map<String, dynamic> toDraftMap() => toMap();

  static PlaceFacilityOptions fromDraftMap(dynamic raw) => raw is Map
      ? PlaceFacilityOptions.fromMap(Map<String, dynamic>.from(raw))
      : PlaceFacilityOptions.empty();
}

import 'package:flutter/material.dart' show TimeOfDay;

import 'package:party_app/models/capacity_filter.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/models/place_attributes.dart';
import 'package:party_app/models/place_availability.dart';
import 'package:party_app/models/place_party_index.dart';
import 'package:party_app/models/place_event_index.dart';
import 'package:party_app/models/place_event_taxonomy.dart';
import 'package:party_app/models/custom_amenity.dart';
import 'package:party_app/models/custom_play_item.dart';
import 'package:party_app/models/place_feature.dart';
import 'package:party_app/models/place_taxonomy.dart';
import 'package:party_app/models/place_weekly_hours.dart';
import 'package:party_app/models/region_selection.dart';

/// 플레이스(events) 탭 전용 상세검색 필터.
///
/// 장소대여([PlaceFilter])와 **완전히 분리된 모델**이다 — 같은 "장소"라도 두
/// 서비스가 파는 것이 달라서 조건이 겹치지 않는다. 장소대여는 "빌리는 것"이라
/// 수용 인원·시간당 요금·예약 가능 여부를 묻고, 플레이스는 "찾아가는 매장"이라
/// 업종·분위기·영업시간을 묻는다.
///
/// 다만 **다루는 방식은 장소대여와 똑같이** 맞췄다 — 지역은 같은
/// [RegionSelection] 키 형식(최대 [RegionSelection.maxCount]개)을 쓰고,
/// 시간 조건의 "전체/일부" 선택도 같은 [PlaceAvailabilityMode]를 그대로 쓴다.
/// 두 탭을 오갈 때 조작법이 달라지지 않게 하기 위함이다.
class EventFilter {
  /// 선택된 지역 — '서울'(시/도 전체) / '서울 강남구'(구까지) 두 형식.
  Set<String> regions;

  /// 대분류 — 맛집(화면 표기 '음식')·카페·디저트·술집·BAR·혼술바·클럽·
  /// 라이브·놀거리·체험 ([PlaceTaxonomy.all]). 목록/지도 **1단** 카테고리
  /// 영역이 켜고 끄는 값이다.
  ///
  /// 값 자체는 여러 개를 담을 수 있고 담기면 OR다("클럽 아니면 BAR") — 상세
  /// 검색은 그대로 여러 개를 켤 수 있다. 다만 **메인 카테고리 영역은 한 번에
  /// 하나만** 켠다([selectCategory]) — 고른 것이 바로 위에 보이는데 아래에
  /// 같은 말을 칩으로 또 쌓지 않기 위함이다.
  Set<String> categories;

  /// 소분류 — 한식·와인바처럼 대분류 한 단계 아래(OR).
  Set<String> subcategories;

  /// 🎪 이벤트 탐색 — **업종과 다른 축**이다([PlaceEventTaxonomy]).
  ///
  /// 홈에서는 다른 대분류와 같은 버튼처럼 보이지만, 데이터에서는 업종
  /// ([categories])과 나란히 존재한다. BAR이면서 생일 이벤트 중인 가게는
  /// 'BAR'로도, '이벤트 → 생일'로도 걸려야 하기 때문이다 — 그래서 이벤트를
  /// 켠다고 [categories]에 무언가를 넣지 않는다.
  ///
  /// true면 "지금 이벤트를 하는 곳만"([PlaceEventTaxonomy.isRunningAt]).
  bool eventOnly;

  /// 이벤트 갈래 — 한정·생일·상시·할인·혜택·증정·특별(OR).
  /// 소분류([subcategories])와 층은 같지만 축이 다르다.
  Set<String> eventKinds;

  /// 🎉 With파티 — **파티츄 파티가 실제로 걸려 있는 플레이스만**.
  ///
  /// 이것도 업종과 다른 축이다. 태그가 아니라 **관계**이고, 그 관계는 문서
  /// 안이 아니라 `parties.linkedEventId`에 있다([PlacePartyIndex]). 그래서
  /// 이 조건만은 문서 하나만 봐서 판정할 수 없고, [matchesDiscovery]에
  /// 색인과 문서 id를 함께 넘겨야 한다.
  ///
  /// 색인을 못 받은 채로 켜져 있으면 아무것도 통과시키지 않는다 — 파티가
  /// 없는 곳을 "파티 있음"으로 보여주는 쪽이 더 나쁘다.
  bool withPartyOnly;

  /// 빠른 탐색 특징 — 콜키지 가능·금연처럼 한 번 눌러 거르는 조건.
  ///
  /// **AND**다 — 겹쳐 누를수록 좁아진다. 대분류(OR)와 반대인 이유는 묻는
  /// 것이 달라서다: 대분류는 "어느 쪽이든", 특징은 "이것도 저것도".
  ///
  /// 값의 출처는 [PlaceFeatures.of] 하나뿐이라, 새 필드가 없는 옛 문서도
  /// themeTags·petPolicy·영업시간에서 유도돼 그대로 걸린다.
  Set<String> features;

  /// **기타 편의 서비스** — 호스트가 직접 입력한 값 중 게스트가 고른 것.
  ///
  /// 담는 값은 **표시 원문**이다("루프탑") — 필터 칩에 그대로 적히고 지우는
  /// 쪽도 같은 문자열을 되짚으면 되기 때문이다(themeTags와 같은 관례).
  /// 표기 차이는 판정에서 [CustomAmenities.matchesAll]이 정규화해 흡수하므로,
  /// 화면이 비교 규칙을 따로 들고 다닐 일은 없다.
  ///
  /// **AND**다 — [features]와 같은 자리(✨ 편의·서비스)에서 고르는 조건이라
  /// 결합 규칙이 다르면 결과를 읽을 수 없다.
  Set<String> customAmenities;

  /// 🎲 **기타 놀거리** — 호스트가 놀거리 '기타'에 직접 적은 값 중 게스트가
  /// 고른 것([CustomPlayItems]).
  ///
  /// 담는 값은 [customAmenities]와 같이 **표시 원문**이고("포켓볼"), 표기
  /// 차이는 판정에서 [CustomPlayItems.matchesAny]가 정규화해 흡수한다.
  ///
  /// **OR**다 — 놀거리 프리셋과 같은 그룹의 값이고 그 그룹은 "그룹 안 OR"라
  /// ([attributes]) 판정도 그 규칙을 그대로 따른다([_matchesPlayItems]).
  /// 기타 편의 서비스(AND)와 규칙이 다른 이유는 서 있는 자리가 달라서다.
  Set<String> customPlayItems;

  /// 세부 속성 — 그룹 키 → 고른 값들(예: musicGenres → {HIPHOP}).
  ///
  /// **그룹 안은 OR, 그룹 사이는 AND**다. "힙합이거나 R&B이면서, 하이볼
  /// 무제한인 곳"이 자연스러운 읽기다.
  Map<String, Set<String>> attributes;

  /// 업종 — 술집·바·카페 등([ListingConstants.eventBusinessTypes]).
  ///
  /// 대분류([categories])로 대체됐지만 **지우지 않는다** — 이미 저장된
  /// 문서와 예전 상세검색이 이 값을 쓰고, 둘은 AND로 함께 걸린다.
  Set<String> businessTypes;

  /// 분위기 — 등록 화면의 특징 태그를 그대로 쓴다. 상세검색에서만 고르고,
  /// 고를 수 있는 값은 [ListingConstants.placeThemeTags] 하나뿐이다.
  ///
  /// ⚠️ 은퇴한 태그([ListingConstants.retiredPlaceThemeTags])가 값으로 들어와도
  /// **그대로 동작한다** — 이미 저장돼 있던 조건이 조용히 깨지지 않게 하기
  /// 위함이다. 그중 '혼술바'는 대분류([PlaceTaxonomy.soloBar])로 승격됐으므로
  /// 새로 고르는 자리에서는 대분류 쪽 하나만 쓴다.
  Set<String> themeTags;

  /// 가격대 — [ListingConstants.eventPriceRanges].
  Set<String> priceRanges;

  /// 방문하려는 날짜 — **최대 [maxVisitDates]일**까지 여러 날을 고를 수 있다.
  /// 여러 날을 고르면 "그중 **하루라도** 여는 곳"을 뜻한다(OR 조건).
  ///
  /// 시간([startTime]/[endTime])과는 **완전히 독립**이다 — 날짜만, 시간만, 둘 다
  /// 고를 수 있고 서로를 지우지 않는다.
  ///
  /// 값은 항상 시각이 잘린 날짜([dayOf])로만 들어간다.
  Set<DateTime> visitDates;

  /// 한 번에 고를 수 있는 방문 날짜 수 — 메인 화면 날짜 버튼이 이 수를 넘기면
  /// 더 담지 않고 안내만 한다.
  static const int maxVisitDates = 5;

  /// 방문하려는 시간 범위. 종료가 시작보다 이르거나 같으면 자정을 넘긴 방문으로
  /// 본다(오후 10:00 ~ 익일 오전 3:00).
  ///
  /// **날짜 없이 시간만** 고를 수 있다 — 그때는 특정 요일이 아니라 "이 시간대에
  /// 여는 날이 하루라도 있는가"를 묻는 조건이 된다(밤 10시~새벽 3시에 문을 여는
  /// 가게 찾기). 장소대여([PlaceFilter])는 예약이 날짜에 붙는 서비스라 여전히
  /// 날짜가 있어야 시간이 뜻을 갖지만, 플레이스는 영업시간 패턴을 묻는 것이라
  /// 날짜가 없어도 성립한다.
  TimeOfDay? startTime;
  TimeOfDay? endTime;

  /// 고른 시간을 **전부** 영업해야 하는지(full), 일부만 겹쳐도 되는지(partial).
  /// 시간을 고르지 않으면 뜻이 없다(날짜 유무와는 무관하다). 장소대여의
  /// "이용 가능 조건"과 같은 enum을 써서 두 탭의 조작법을 통일한다.
  PlaceAvailabilityMode openMode;

  /// 파티츄 전용 혜택이 있는 곳만.
  bool partychuPerkOnly;

  /// 지금 이 시각 영업 중인 곳만.
  bool openNowOnly;

  /// 필요한 인원 — 이 인원을 받을 수 있는 곳만. null이면 조건 없음.
  ///
  /// 판정은 [CapacityFilter]가 한다(장소대여와 **같은 함수**를 쓴다) — 인원을
  /// 입력하지 않은 장소는 걸러지지 않는다.
  int? minCapacity;

  EventFilter({
    Set<String>? regions,
    Set<String>? categories,
    Set<String>? subcategories,
    this.eventOnly = false,
    this.withPartyOnly = false,
    Set<String>? eventKinds,
    Set<String>? features,
    Set<String>? customAmenities,
    Set<String>? customPlayItems,
    Map<String, Set<String>>? attributes,
    Set<String>? businessTypes,
    Set<String>? themeTags,
    Set<String>? priceRanges,
    Set<DateTime>? visitDates,
    // 날짜 하나만 다루는 호출부를 위한 지름길 — [visitDates]와 함께 줘도 된다.
    DateTime? visitDate,
    this.startTime,
    this.endTime,
    this.openMode = PlaceAvailabilityMode.full,
    this.partychuPerkOnly = false,
    this.openNowOnly = false,
    this.minCapacity,
  }) : regions = regions ?? {},
       categories = categories ?? {},
       subcategories = subcategories ?? {},
       eventKinds = eventKinds ?? {},
       features = features ?? {},
       customAmenities = customAmenities ?? {},
       customPlayItems = customPlayItems ?? {},
       attributes = {
         for (final e in (attributes ?? const {}).entries)
           if (e.value.isNotEmpty) e.key: {...e.value},
       },
       businessTypes = businessTypes ?? {},
       themeTags = themeTags ?? {},
       priceRanges = priceRanges ?? {},
       visitDates = {
         ...?visitDates?.map(dayOf),
         if (visitDate != null) dayOf(visitDate),
       };

  /// 시각을 잘라낸 날짜 — 날짜 집합에는 언제나 이 형태로만 담는다.
  static DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  /// 고른 날짜를 이른 순으로 — 칩 순서와 요약 표기가 항상 같은 순서가 된다.
  List<DateTime> get sortedVisitDates => visitDates.toList()..sort();

  /// 가장 이른 방문 날짜. **날짜를 하나만 다루는 화면**(플레이스 상세검색
  /// 시트)이 지금까지 쓰던 자리라, 여러 날을 고른 상태에서도 대표 하나를
  /// 돌려준다. 대입하면 그 하루만 남는다.
  DateTime? get visitDate => visitDates.isEmpty ? null : sortedVisitDates.first;

  set visitDate(DateTime? date) =>
      visitDates = date == null ? <DateTime>{} : {dayOf(date)};

  bool get isActive =>
      regions.isNotEmpty ||
      categories.isNotEmpty ||
      subcategories.isNotEmpty ||
      eventOnly ||
      withPartyOnly ||
      eventKinds.isNotEmpty ||
      features.isNotEmpty ||
      customAmenities.isNotEmpty ||
      customPlayItems.isNotEmpty ||
      attributes.values.any((v) => v.isNotEmpty) ||
      businessTypes.isNotEmpty ||
      themeTags.isNotEmpty ||
      priceRanges.isNotEmpty ||
      visitDates.isNotEmpty ||
      // 날짜 없이 시간만 골라도 그 자체로 조건이다.
      hasTimeCondition ||
      partychuPerkOnly ||
      openNowOnly ||
      minCapacity != null;

  /// 시작·종료를 모두 고른 상태인지 — "그 시간대 내내(또는 일부) 영업".
  bool get hasTimeRange => startTime != null && endTime != null;

  /// 시작 시각 하나만 고른 상태인지 — "그 **시각**에 영업 중"을 뜻한다.
  /// 메인 화면의 빠른 방문시간 필터(오늘 22:00 …)가 만드는 값이고, 상세검색
  /// 에서 시작 시간만 고른 경우도 똑같이 읽힌다(두 입구가 같은 값을 쓴다).
  bool get hasTimePoint => startTime != null && endTime == null;

  /// 시각이든 시간대든, 시간 조건이 하나라도 걸려 있는지.
  bool get hasTimeCondition => startTime != null;

  /// 자정을 넘긴 방문인지 — 종료가 시작보다 이르거나 같으면 다음 날로 본다.
  bool get crossesMidnight {
    if (!hasTimeRange) return false;
    final start = startTime!.hour * 60 + startTime!.minute;
    final end = endTime!.hour * 60 + endTime!.minute;
    return end <= start;
  }

  EventFilter copy() => EventFilter(
    regions: {...regions},
    categories: {...categories},
    subcategories: {...subcategories},
    eventOnly: eventOnly,
    withPartyOnly: withPartyOnly,
    eventKinds: {...eventKinds},
    features: {...features},
    customAmenities: {...customAmenities},
    customPlayItems: {...customPlayItems},
    attributes: {
      for (final e in attributes.entries) e.key: {...e.value},
    },
    businessTypes: {...businessTypes},
    themeTags: {...themeTags},
    priceRanges: {...priceRanges},
    visitDates: {...visitDates},
    startTime: startTime,
    endTime: endTime,
    openMode: openMode,
    partychuPerkOnly: partychuPerkOnly,
    openNowOnly: openNowOnly,
    minCapacity: minCapacity,
  );

  /// 상단 필터 칩에 그대로 뿌리는 목록 — 장소대여와 같은 (분류, 표기) 쌍이라
  /// 칩을 그리는 위젯을 두 탭이 공유할 수 있다.
  List<MapEntry<String, String>> get selectedEntries => [
    // 칩에는 '서울'이 아니라 '서울 전체'로 — 구 이름과 헷갈리지 않게.
    ...regions.map((v) => MapEntry('regions', RegionSelection.label(v))),
    // 고른 날짜 하나에 칩 하나 — 3일을 골랐으면 칩도 세 개라 어느 날을 지우는
    // 것인지 칩만 보고 알 수 있다.
    ...sortedVisitDates.map((d) => MapEntry('visitDate', '📅 ${dayLabel(d)}')),
    // 날짜와 시간은 각각 독립된 칩이다 — 한쪽 X를 눌러도 다른 쪽은 그대로
    // 남는다(removeValue). 운영시간 조건(전체/일부)은 시간 조건의 성격이라
    // 시간 칩에 붙여 둔다.
    if (hasTimeCondition) MapEntry('visitTime', '🕒 $timeChipLabel'),
    // 대분류·소분류·특징은 화면 표기(이모지 포함)로 칩을 만들고, 지우는
    // 쪽이 같은 표를 되짚어 저장값을 되찾는다(themeTags와 같은 관례).
    ...categories.map(
      (v) => MapEntry('categories', PlaceTaxonomy.displayOf(v)),
    ),
    ...subcategories.map((v) => MapEntry('subcategories', v)),
    // 🎪 매장 이벤트 — 파티(🎉)와 갈라 부른다([HostOffering]).
    if (eventOnly)
      const MapEntry(
        'eventOnly',
        '${PlaceEventTaxonomy.categoryEmoji} '
            '${PlaceEventTaxonomy.categoryLabel} 진행중',
      ),
    if (withPartyOnly) const MapEntry('withPartyOnly', '🎉 With파티'),
    ...eventKinds.map(
      (v) => MapEntry('eventKinds', PlaceEventTaxonomy.displayOf(v)),
    ),
    ...features.map((v) => MapEntry('features', PlaceFeatures.displayOf(v))),
    // 기타는 호스트가 만든 말이라 표기 표가 없다 — 저장한 원문이 곧 표기다.
    ...customAmenities.map((v) => MapEntry('customAmenities', v)),
    // 놀거리 자유기재도 원문이 곧 표기다. 다만 이름만으로는 어느 축인지
    // 알 수 없어(같은 말이 편의 서비스로도 등록될 수 있다) 그룹 이모지를
    // 앞에 붙인다 — 지우는 쪽이 같은 접두사를 떼어 값을 되찾는다.
    ...customPlayItems.map((v) => MapEntry('customPlayItems', '🎲 $v')),
    for (final e in attributes.entries)
      ...e.value.map((v) => MapEntry('attr:${e.key}', v)),
    ...businessTypes.map((v) => MapEntry('businessTypes', v)),
    // 칩에는 저장값이 아니라 표기를 적는다('이벤트' → '이벤트 진행중').
    // 지우는 쪽([removeValue])이 같은 표를 되짚어 값을 되찾는다.
    ...themeTags.map(
      (v) => MapEntry('themeTags', ListingConstants.placeThemeTagLabel(v)),
    ),
    ...priceRanges.map((v) => MapEntry('priceRanges', v)),
    if (minCapacity != null)
      MapEntry('minCapacity', '👥 ${CapacityFilter.label(minCapacity!)}'),
    if (partychuPerkOnly) const MapEntry('partychuPerkOnly', '🎁 파티츄 혜택만'),
    if (openNowOnly) const MapEntry('openNowOnly', '🟢 현재 영업 중'),
  ];

  void removeValue(String category, String value) {
    // 속성 칩은 'attr:<그룹키>' 꼴이라 switch로는 못 가른다.
    if (category.startsWith('attr:')) {
      final key = category.substring(5);
      attributes[key]?.remove(value);
      if (attributes[key]?.isEmpty ?? false) attributes.remove(key);
      return;
    }
    switch (category) {
      case 'regions':
        // 칩에 적힌 표기로 어느 지역인지 되찾는다 — 라벨을 만드는 곳과 지우는
        // 곳이 같은 [RegionSelection.label]을 쓰므로 표기가 갈라질 수 없다.
        regions.removeWhere((k) => RegionSelection.label(k) == value);
        break;
      // 날짜와 시간은 서로 독립이다 — 날짜 칩을 지운다고 시간이 사라지거나,
      // 시간 칩을 지운다고 날짜가 사라지지 않는다.
      case 'visitDate':
        // 칩 하나 = 날짜 하나. 칩에 적힌 표기로 어느 날인지 되찾아 그 날만
        // 지운다(다른 날은 그대로). 표기를 못 찾으면 날짜 조건을 통째로 비운다.
        final label = value.replaceFirst('📅 ', '');
        final before = visitDates.length;
        visitDates.removeWhere((d) => dayLabel(d) == label);
        if (visitDates.length == before) clearDate();
        break;
      case 'visitTime':
        clearTime();
        break;
      case 'categories':
        categories.removeWhere((c) => PlaceTaxonomy.displayOf(c) == value);
        // 대분류를 지우면 그 아래 소분류도 함께 사라진다 — 부모 없는
        // 소분류만 남으면 무엇을 걸러 주는 조건인지 읽히지 않는다.
        subcategories.removeWhere(
          (sub) => !categories.any((c) => PlaceTaxonomy.hasSubcategory(c, sub)),
        );
        break;
      case 'subcategories':
        subcategories.remove(value);
        break;
      case 'eventOnly':
        // 이벤트를 끄면 그 아래 갈래도 함께 빠진다 — 부모 없는 갈래만
        // 남으면 무엇을 걸러 주는 조건인지 읽히지 않는다(대분류와 같다).
        selectEvent(false);
        break;
      case 'withPartyOnly':
        withPartyOnly = false;
        break;
      case 'eventKinds':
        eventKinds.removeWhere((k) => PlaceEventTaxonomy.displayOf(k) == value);
        break;
      case 'features':
        features.removeWhere((f) => PlaceFeatures.displayOf(f) == value);
        break;
      case 'customAmenities':
        customAmenities.removeWhere((v) => CustomAmenities.sameItem(v, value));
        break;
      case 'customPlayItems':
        // 칩에 붙인 그룹 이모지를 떼고 원문으로 되짚는다.
        final name = value.replaceFirst('🎲 ', '');
        customPlayItems.removeWhere((v) => CustomPlayItems.sameItem(v, name));
        break;
      case 'businessTypes':
        businessTypes.remove(value);
        break;
      case 'themeTags':
        // 칩에 적힌 표기로 저장값을 되찾아 지운다 — 표기를 바꾸지 않은
        // 태그는 표기와 저장값이 같아 그대로 지워진다.
        themeTags.remove(ListingConstants.placeThemeTagValue(value));
        break;
      case 'priceRanges':
        priceRanges.remove(value);
        break;
      case 'partychuPerkOnly':
        partychuPerkOnly = false;
        break;
      case 'openNowOnly':
        openNowOnly = false;
        break;
      case 'minCapacity':
        minCapacity = null;
        break;
    }
  }

  /// 메인 탐색의 **단일 선택** 대분류.
  ///
  /// 메인에서는 대분류를 한 번에 하나만 켠다 — '음식'을 보다가 '클럽'을 누르면
  /// 음식이 저절로 꺼진다. 여러 개를 겹쳐 켜는 것은 상세검색 쪽 조작이라
  /// [toggleCategory](OR 다중 선택)는 그대로 남는다.
  ///
  /// null을 주면 대분류 조건을 푼다(= '전체'). 어느 쪽이든 새 대분류 아래에
  /// 없는 소분류는 함께 빠진다 — 부모 없는 소분류만 남으면 무엇을 걸러 주는
  /// 조건인지 읽히지 않는다.
  void selectCategory(String? category) {
    // 업종을 고르면 이벤트 축은 내려놓는다 — 홈에서 두 개가 동시에 켜져
    // 보이지 않게 하는 화면 규칙이다(저장된 문서는 여전히 둘 다에 걸린다).
    if (category != null) selectEvent(false);
    final value = category == null ? null : PlaceTaxonomy.canonical(category);
    categories = value == null ? <String>{} : {value};
    subcategories.removeWhere(
      (sub) => value == null || !PlaceTaxonomy.hasSubcategory(value, sub),
    );
  }

  /// 🎪 이벤트 대분류를 켜고 끈다.
  ///
  /// 홈에서는 대분류와 같은 자리를 쓰므로 **업종 선택을 함께 푼다** — 화면에서
  /// 두 개가 동시에 켜져 보이지 않게 하기 위함이다. 데이터 축은 여전히 서로
  /// 독립이라(이벤트를 켠다고 `placeCategory`에 아무것도 안 쓴다), BAR인 가게가
  /// 이벤트 탐색에서 빠지거나 업종을 잃는 일은 없다.
  void selectEvent(bool on) {
    eventOnly = on;
    if (!on) {
      eventKinds.clear();
      return;
    }
    categories.clear();
    subcategories.clear();
  }

  void toggleEventKind(String kind) {
    if (!eventKinds.remove(kind)) eventKinds.add(kind);
  }

  bool isEventKindOn(String kind) => eventKinds.contains(kind);

  /// 지금 켜진 대분류가 **정확히 하나**면 그 값. 없거나 여럿이면 null.
  ///
  /// 메인 카테고리 영역이 "소분류로 내려갈지"를 이 값 하나로 판단한다 —
  /// 상세검색에서 두 개를 겹쳐 켠 상태에서는 내려가지 않고 대분류 목록에
  /// 둘 다 켜진 채로 남는다(값을 임의로 하나 버리지 않는다).
  String? get soleCategory => categories.length == 1 ? categories.first : null;

  /// 대분류를 켜고 끈다. 끄면 그 아래 소분류도 함께 빠진다.
  void toggleCategory(String category) {
    if (categories.remove(category)) {
      subcategories.removeWhere(
        (sub) => PlaceTaxonomy.hasSubcategory(category, sub),
      );
      return;
    }
    categories.add(category);
  }

  bool isCategoryOn(String category) => categories.contains(category);

  void toggleSubcategory(String subcategory) {
    if (!subcategories.remove(subcategory)) subcategories.add(subcategory);
  }

  /// 빠른 필터 한 칸을 켜고 끈다.
  void toggleFeature(String feature) {
    if (!features.remove(feature)) features.add(feature);
  }

  bool isFeatureOn(String feature) => features.contains(feature);

  Set<String> attributeValues(String groupKey) =>
      attributes[groupKey] ?? const <String>{};

  void toggleAttribute(String groupKey, String value) {
    final set = attributes.putIfAbsent(groupKey, () => <String>{});
    if (!set.remove(value)) set.add(value);
    if (set.isEmpty) attributes.remove(groupKey);
  }

  bool isAttributeOn(String groupKey, String value) =>
      attributeValues(groupKey).contains(value);

  /// 빠른 필터 줄에 **보이지 않는** 조건이 몇 개나 걸려 있는지.
  ///
  /// 메인에서 고른 조건을 칩으로 다시 쌓지 않기로 했으므로(플레이스 카드가
  /// 아래로 밀린다), "어딘가 걸려 있는데 어디인지 모르는" 상태가 생기지
  /// 않도록 상세필터 버튼에 이 개수를 배지로 띄운다.
  ///
  /// 세지 않는 것: 대분류·소분류·이벤트 갈래(카테고리 영역에 그대로 보인다),
  /// 날짜·시간·인원(📅 🕐 👥 버튼이 각자 배지로 표시한다). 지금 줄에 나와 있는 특징·속성도
  /// [visibleFeatures]/[visibleAttributes]로 받아 빼고 센다 — 버튼 자체가
  /// 켜져 있는 조건을 배지가 한 번 더 세면 같은 말을 두 번 하는 것이 된다.
  int hiddenConditionCount({
    Set<String> visibleFeatures = const {},
    Map<String, Set<String>> visibleAttributes = const {},
    // '지금 영업중'은 이벤트 줄에서만 칩으로 나온다 — 그때는 세지 않는다.
    bool countOpenNow = true,
  }) {
    var n = features.where((f) => !visibleFeatures.contains(f)).length;
    for (final e in attributes.entries) {
      final shown = visibleAttributes[e.key] ?? const <String>{};
      n += e.value.where((v) => !shown.contains(v)).length;
    }
    n += customAmenities.length;
    // 자유기재 놀거리는 빠른 탐색 줄에 나오지 않는다 — 언제나 '안 보이는
    // 조건'이라 그대로 센다.
    n += customPlayItems.length;
    n += regions.length;
    n += businessTypes.length;
    n += themeTags.length;
    n += priceRanges.length;
    if (partychuPerkOnly) n++;
    if (openNowOnly && countOpenNow) n++;
    return n;
  }

  /// 대분류/소분류/특징/속성만 한 번에 비운다 — 지역·날짜는 그대로 둔다.
  void clearDiscovery() {
    categories.clear();
    subcategories.clear();
    eventOnly = false;
    withPartyOnly = false;
    eventKinds.clear();
    features.clear();
    customAmenities.clear();
    customPlayItems.clear();
    attributes.clear();
  }

  /// 이 문서가 대분류·소분류·이벤트·특징·속성 조건을 모두 통과하는가.
  ///
  /// 판정을 필터 모델에 두는 이유: 목록·지도·상세검색이 **같은 함수**를
  /// 부르게 해서, 화면마다 조건이 갈리는 일을 구조적으로 막는다.
  ///
  /// [now]는 이벤트 종료 판정에만 쓴다 — 넘기지 않으면 현재 시각이다.
  ///
  /// [docId]·[partyIndex]는 🎉 With파티 조건에만 쓴다. 이 조건은 문서 안이
  /// 아니라 **파티 쪽 관계**(`parties.linkedEventId`)에 있어서, 문서 하나만
  /// 봐서는 알 수 없기 때문이다([PlacePartyIndex]). 목록·지도가 이미 갖고
  /// 있는 파티 스냅샷으로 색인을 만들어 함께 넘긴다 — 두 화면이 **같은
  /// 색인**을 쓰므로 결과가 갈릴 수 없다.
  ///
  /// [eventIndex]는 🎪 이벤트 조건의 **정본**이다([PlaceEventIndex]) — 이것도
  /// 문서 안이 아니라 `placePromotions` 쪽에 있어서 문서 하나만 봐서는 알 수
  /// 없다. 넘기지 않으면 본체에 비춰 둔 미러로 판정한다(아래).
  bool matchesDiscovery(
    Map<String, dynamic> data, {
    DateTime? now,
    String? docId,
    PlacePartyIndex? partyIndex,
    PlaceEventIndex? eventIndex,
  }) {
    if (!PlaceTaxonomy.matchesAnyCategory(data, categories)) return false;
    if (!PlaceTaxonomy.matchesAnySubcategory(data, subcategories)) {
      return false;
    }

    // 🎉 With파티 — 지금 노출 가능한 파티가 걸려 있는 플레이스만.
    //
    // 색인을 못 받았으면 통과시키지 않는다. 파티를 아직 못 읽은 상태에서
    // 전부 통과시키면 "파티가 있다고 해서 들어왔는데 없는" 목록이 되고,
    // 그건 잠깐 비어 보이는 것보다 나쁘다.
    if (withPartyOnly && !(partyIndex?.has(docId) ?? false)) return false;

    // 🎪 이벤트는 업종과 **다른 축**이라 대분류 조건과 나란히 걸린다 —
    // 여기서 categories를 보지 않으므로 'BAR인데 생일 이벤트 중'인 가게가
    // 두 탐색 모두에 걸린다.
    //
    // 판정은 두 갈래다.
    //   ① 색인을 받았으면 그것이 정본이다 — `placePromotions`를 실제로 읽어
    //      "지금 보여줄 이벤트가 있는 매장"만 담은 집합이라
    //      ([PlaceEventIndex]), 숨김·종료만 남은 매장과 이벤트를 한 번도 올린
    //      적 없는 매장이 함께 빠진다. 카드를 눌러 상세에 들어갔는데 이벤트
    //      영역이 비어 있는 일이 없다.
    //   ② 색인이 없으면(아직 못 읽었거나, 이벤트 축을 모르는 호출부) 예전
    //      그대로 본체의 미러로 본다([PlaceEventTaxonomy.isRunningAt]).
    //      잠깐 목록이 통째로 비는 것보다, 조금 넉넉한 예전 판정이 낫다.
    if (eventOnly) {
      // 날짜·시간을 골랐으면 **그 조건에 맞는 이벤트가 있는가**까지 본다.
      //
      // 판정은 파티츄/이벤트 탭 목록과 같은 함수 하나다
      // ([PlaceEventTime.matches]를 [PlaceEventIndex.hasMatching]이 부른다) —
      // 지도도 이 함수를 거치므로 두 화면이 갈릴 수 없다. 영업중(전시간)
      // 이벤트의 영업시간은 지금 보고 있는 문서에서 읽는다.
      final byIndex = eventIndex?.hasMatching(
        docId,
        dates: visitDates,
        start: startTime,
        end: endTime,
        hours: PlaceWeeklyHours.fromPlaceDoc(data),
        now: now,
      );
      if (byIndex != null) {
        if (!byIndex) return false;
      } else if (!PlaceEventTaxonomy.isRunningAt(data, now ?? DateTime.now())) {
        return false;
      }
    }
    if (!PlaceEventTaxonomy.matchesAnyKind(data, eventKinds)) return false;

    if (!PlaceFeatures.matchesAll(data, features)) return false;
    // 기타 편의 서비스도 같은 자리에서 고르는 조건이라 바로 옆에서, 같은
    // 규칙(AND)으로 건다. 필드가 없는 옛 문서는 조건이 걸린 순간 빠진다 —
    // 아무것도 안 고르면([customAmenities]가 비면) 판정 자체가 없다.
    if (!CustomAmenities.matchesAll(data, customAmenities)) return false;

    if (attributes.isNotEmpty || customPlayItems.isNotEmpty) {
      final attrs = PlaceAttributes.fromDoc(data);
      // 놀거리는 프리셋과 자유기재를 **한 그룹의 OR**로 본다 — 게스트에게는
      // 같은 줄에서 고른 하나의 조건이다([_matchesPlayItems]).
      if (!_matchesPlayItems(data, attrs)) return false;
      for (final e in attributes.entries) {
        if (e.value.isEmpty) continue;
        // 놀거리는 바로 위에서 자유기재까지 함께 봤다.
        if (e.key == CustomPlayItems.groupKey) continue;
        // 그룹 안은 OR, 그룹 사이는 AND.
        final owned = e.key == PlaceAttributeCatalog.musicGenresKey
            // 음악 장르는 옛 클럽 소분류('힙합클럽')에서도 읽어낸다 — 장르를
            // 정본으로 삼으면서 그 값으로 등록된 가게를 잃지 않기 위한 다리다.
            ? {
                ...attrs.selected(e.key),
                ...PlaceTaxonomy.legacyClubGenresOf(data),
              }
            : attrs.selected(e.key);
        if (!e.value.any(owned.contains)) return false;
      }
    }
    return true;
  }

  /// 🎲 놀거리 — 프리셋(보드게임·다트…)과 자유기재(포켓볼·마작…)를 **같은
  /// 그룹의 OR**로 판정한다.
  ///
  /// 둘을 각각 그룹으로 세워 AND로 걸면, 게스트가 같은 줄에서 '다트'와
  /// '포켓볼'을 고른 순간 "둘 다 있는 곳"만 남는다 — 그 줄의 다른 값들은
  /// 전부 OR인데 하나만 규칙이 달라지는 셈이라 결과를 읽을 수 없다.
  bool _matchesPlayItems(Map<String, dynamic> data, PlaceAttributes attrs) {
    final preset = attributes[CustomPlayItems.groupKey] ?? const <String>{};
    if (preset.isEmpty && customPlayItems.isEmpty) return true;
    if (preset.any(attrs.selected(CustomPlayItems.groupKey).contains)) {
      return true;
    }
    // 아무것도 안 고른 쪽은 판정에 끼지 않는다 — matchesAny는 빈 조건에
    // true를 돌려주므로 여기서 직접 걸러야 한다.
    if (customPlayItems.isNotEmpty &&
        CustomPlayItems.matchesAny(data, customPlayItems)) {
      return true;
    }
    return false;
  }

  /// 날짜만 지운다 — 고른 날이 여러 개여도 한 번에, 시간 조건은 그대로 남는다.
  void clearDate() => visitDates.clear();

  /// 시간만 지운다 — 날짜 조건은 그대로 남는다. 운영시간 조건(전체/일부)은
  /// 시간이 없으면 뜻이 없으므로 기본값으로 되돌린다.
  void clearTime() {
    startTime = null;
    endTime = null;
    openMode = PlaceAvailabilityMode.full;
  }

  /// 날짜·시간을 한 번에 지운다(둘 다 비우고 싶을 때만).
  void clearSchedule() {
    clearDate();
    clearTime();
  }

  /// 날짜 하나의 표기 — '오늘(금)' / '내일(토)' / '모레(일)' / '8월 17일(월)'.
  ///
  /// 가까운 날짜는 이름으로 부르되 **요일을 항상 붙인다** — "언제 갈까"를 정할
  /// 때 실제로 보는 건 요일이라서다('요일'이라는 말은 빼고 한 글자만).
  /// 메인 화면 날짜 칩, 상단 필터 칩, 상세검색 요약이 모두 이 표기를 쓴다.
  static String dayLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final w = weekdayChar(date);
    return switch (dayOf(date).difference(today).inDays) {
      0 => '오늘($w)',
      1 => '내일($w)',
      2 => '모레($w)',
      _ => '${date.month}월 ${date.day}일($w)',
    };
  }

  /// 고른 날짜 전체의 요약 표기 — 하루면 '오늘', 여러 날이면 '오늘 외 2일'.
  String? get visitDateLabel {
    final dates = sortedVisitDates;
    if (dates.isEmpty) return null;
    final first = dayLabel(dates.first);
    return dates.length == 1 ? first : '$first 외 ${dates.length - 1}일';
  }

  /// '월' … '일' — 요일 한 글자.
  static String weekdayChar(DateTime d) => _weekdayLabels[d.weekday - 1];

  /// '8월 20일 (수)'.
  static String formatDate(DateTime d) =>
      '${d.month}월 ${d.day}일 (${_weekdayLabels[d.weekday - 1]})';

  /// '오후 7:00'.
  static String formatTime(TimeOfDay t) {
    final ampm = t.hour < 12 ? '오전' : '오후';
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$ampm $h:${t.minute.toString().padLeft(2, '0')}';
  }

  /// '오후 7:00 ~ 오후 11:00' / 자정을 넘기면 '오후 10:00 ~ 익일 오전 3:00'.
  String get timeRangeLabel {
    if (!hasTimeRange) return '';
    final end = formatTime(endTime!);
    return '${formatTime(startTime!)} ~ ${crossesMidnight ? '익일 $end' : end}';
  }

  /// '22:00~익일 03:00' — 필터 칩처럼 좁은 자리에 쓰는 24시간 표기.
  String get timeRangeChipLabel {
    if (!hasTimeRange) return '';
    final end = _hhmm(endTime!);
    return '${_hhmm(startTime!)}~${crossesMidnight ? '익일 $end' : end}';
  }

  /// '전체 영업' / '일부 영업' — 시간대 칩 뒤에 붙는 짧은 운영시간 조건 표기.
  String get openModeLabel =>
      openMode == PlaceAvailabilityMode.partial ? '일부 영업' : '전체 영업';

  /// '22:00' — 시각 하나만 고른 경우의 24시간 표기.
  String get timePointChipLabel => hasTimePoint ? _hhmm(startTime!) : '';

  /// 필터 칩에 그대로 쓰는 시간 조건 표기.
  /// 시각만 고르면 '22:00 영업 중', 시간대까지 고르면
  /// '22:00~익일 03:00 · 전체 영업'.
  String get timeChipLabel {
    if (hasTimeRange) return '$timeRangeChipLabel · $openModeLabel';
    return hasTimePoint ? '$timePointChipLabel 영업 중' : '';
  }

  static String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  /// 고른 시간대를 [date] 위에 얹은 실제 시작·끝(자정을 넘기면 종료가 다음
  /// 날이 된다). 시간을 덜 골랐으면 null.
  ///
  /// 날짜를 고르지 않은 검색은 특정 요일을 묻는 것이 아니므로, 호출부가
  /// 요일을 하나씩 대입해 보면서 이 함수를 다시 쓴다.
  ({DateTime start, DateTime end})? windowOn(DateTime date) {
    if (!hasTimeRange) return null;
    final start = DateTime(
      date.year,
      date.month,
      date.day,
      startTime!.hour,
      startTime!.minute,
    );
    var end = DateTime(
      date.year,
      date.month,
      date.day,
      endTime!.hour,
      endTime!.minute,
    );
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
    return (start: start, end: end);
  }

  /// 고른 날짜의 방문 시간대. 날짜나 시간을 덜 골랐으면 null.
  ({DateTime start, DateTime end})? get visitWindow {
    final date = visitDate;
    return date == null ? null : windowOn(date);
  }

  /// 시각 하나만 고른 경우, 그 시각을 [date] 위에 얹은 값. 시간대를 골랐거나
  /// 시간을 아예 안 골랐으면 null.
  DateTime? momentOn(DateTime date) => hasTimePoint
      ? DateTime(
          date.year,
          date.month,
          date.day,
          startTime!.hour,
          startTime!.minute,
        )
      : null;

  /// 메인 화면 빠른 필터에서 "22:00" 같은 **시각 하나**를 고른다 — 이미 같은
  /// 시각이 걸려 있으면 꺼진다. 시간대(종료 시간)는 시각 선택으로 대체된다.
  void toggleVisitMoment(TimeOfDay time) {
    if (hasTimePoint && _sameTime(startTime!, time)) {
      clearTime();
      return;
    }
    startTime = time;
    endTime = null;
    openMode = PlaceAvailabilityMode.full;
  }

  /// 지금 이 시각이 빠른 필터에서 고른 값인지 — 칩의 선택 표시에 쓴다.
  bool isVisitMoment(TimeOfDay time) =>
      hasTimePoint && _sameTime(startTime!, time);

  /// 메인 화면 빠른 필터에서 "22–02" 같은 **시간대**를 고른다. 종료가 시작보다
  /// 이르면 자정을 넘긴 방문이 된다([crossesMidnight]).
  ///
  /// 운영시간 조건([openMode])은 [mode]를 주지 않는 한 **건드리지 않는다** —
  /// 상세검색에서 고른 값이 있으면 그대로 이어서 쓴다. 하루 전체(24시간)처럼
  /// '일부만 겹쳐도 통과'로 두면 뜻이 사라지는 구간에서만 [mode]를 준다.
  void setVisitRange(
    TimeOfDay start,
    TimeOfDay end, {
    PlaceAvailabilityMode? mode,
  }) {
    startTime = start;
    endTime = end;
    if (mode != null) openMode = mode;
  }

  /// 지금 걸린 시간 조건이 바로 이 시간대인지 — 칩의 선택 표시에 쓴다.
  bool isVisitRange(TimeOfDay start, TimeOfDay end) =>
      hasTimeRange && _sameTime(startTime!, start) && _sameTime(endTime!, end);

  /// 메인 화면 날짜 버튼의 날짜 칩 — 이미 고른 날짜를 다시 누르면 그 날만
  /// 빠지고, 아닌 날짜는 더해진다(중복 선택). 시간 조건은 건드리지 않는다
  /// (날짜와 시간은 서로 독립).
  ///
  /// [maxVisitDates]개를 이미 골랐는데 새 날짜를 더하려 하면 **아무것도 바꾸지
  /// 않고** false를 돌려준다 — 호출부는 그때만 안내를 띄우면 된다.
  bool toggleVisitDate(DateTime date) {
    final day = dayOf(date);
    if (visitDates.remove(day)) return true;
    if (visitDates.length >= maxVisitDates) return false;
    visitDates.add(day);
    return true;
  }

  bool isVisitDate(DateTime date) => visitDates.contains(dayOf(date));

  static bool _sameTime(TimeOfDay a, TimeOfDay b) =>
      a.hour == b.hour && a.minute == b.minute;

  static const _weekdayLabels = ['월', '화', '수', '목', '금', '토', '일'];
}

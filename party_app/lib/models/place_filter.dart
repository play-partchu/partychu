import 'package:flutter/material.dart' show TimeOfDay;

import 'package:party_app/models/capacity_filter.dart';
import 'package:party_app/models/custom_amenity.dart';
import 'package:party_app/models/place_availability.dart';
import 'package:party_app/models/place_event_index.dart';
import 'package:party_app/models/reservation_modes.dart';
import 'package:party_app/models/region_selection.dart';

/// 장소대여 탭 전용 상세검색 필터.
/// 파티(PartyFilter)와 완전히 분리된 모델 — 장소 서비스 특성에 맞는 항목만 보유.
class PlaceFilter {
  /// 선택된 지역 — [RegionSelection]의 키 형식('서울' = 서울 전체,
  /// '서울 강남구' = 그 구만). 시/도만 담던 예전 값도 그대로 "시/도 전체"로
  /// 해석되므로 저장된 필터를 그대로 써도 된다. 최대
  /// [RegionSelection.maxCount]개.
  Set<String> regions;
  Set<String> priceRanges;
  Set<String> capacityRanges;
  Set<String> placeTypes;

  /// 정식 편의시설(`commonFacilities`) — **OR**다. 하나라도 있으면 걸린다.
  ///
  /// 이 규칙은 예전 그대로 둔다. 여기 담기는 값은 프리셋
  /// ([ListingConstants.placeFacilities])이고, 게스트가 "주차 아니면 수영장"
  /// 처럼 넓히려고 여러 개를 누르는 자리다.
  Set<String> facilities;

  /// **기타 편의 서비스** — 호스트가 직접 입력한 값 중 게스트가 고른 것.
  ///
  /// [facilities]와 **섞지 않는 별도 축**이다. 저장 필드부터 다르고
  /// (`customAmenities` — 플레이스와 공용), 결합 규칙도 다르다: 이쪽은
  /// **AND**다([CustomAmenities.matchesAll]). 플레이스 탭의 같은 축
  /// ([EventFilter.customAmenities])과 규칙이 갈리면 탭을 옮길 때마다 같은
  /// 조건이 다르게 걸린다.
  ///
  /// 담는 값은 표시 원문이고, 표기 차이는 판정이 정규화해 흡수한다.
  Set<String> customAmenities;

  /// 🎪 지금 이벤트를 하는 공간만 — **장소대여 탭의 이벤트 축**이다.
  ///
  /// 여기 걸리는 것은 공간대여·숙박(`places`)의 이벤트뿐이다. 매장 이벤트
  /// (`events`)는 플레이스 탭의 같은 축([EventFilter.eventOnly])이 맡고, 두
  /// 축은 서로의 것을 절대 보지 않는다 — 판정에 쓰는 색인부터 컬렉션별로
  /// 따로다([PlaceEventIndex.rentalCollection]).
  ///
  /// 대여 유형·인원처럼 **공간의 성질**을 묻는 조건과 나란히 걸린다(AND).
  bool eventOnly;

  bool petFriendlyOnly;

  /// 외부 음식을 가져와도 되는 곳만 — 등록 화면이 `facilityOptions.outsideFood`에
  /// 저장한 값을 본다("협의 후 가능"은 조건이 붙는 곳이라 포함하지 않는다).
  bool outsideFoodOnly;

  /// 이용하려는 날짜. 시간([startTime]/[endTime])은 이 값이 있어야 의미가 있다.
  DateTime? useDate;

  /// 이용하려는 시간 범위. 둘 다 골랐을 때만 시간까지 검사하고, 날짜만 고른
  /// 경우에는 "그날 이용할 수 있는 장소"까지만 거른다.
  ///
  /// 종료가 시작보다 이르거나 같으면 자정을 넘긴 이용으로 본다
  /// (20일 22:00 ~ 21일 02:00).
  TimeOfDay? startTime;
  TimeOfDay? endTime;

  /// 고른 시간 범위를 전부 써야 하는지(기본), 일부만 써도 되는지.
  /// 시간을 고르지 않으면 의미가 없다.
  PlaceAvailabilityMode availabilityMode;

  /// 필요한 인원 — 이 인원을 받을 수 있는 곳만. null이면 조건 없음.
  ///
  /// 플레이스 탭([EventFilter.minCapacity])과 **같은 판정**([CapacityFilter])을
  /// 쓴다. 기존 [capacityRanges]("10~20명" 같은 구간)와는 묻는 것이 달라
  /// 나란히 존재한다 — 이쪽은 "우리 일행이 들어가는가"다.
  int? minCapacity;

  /// 예약 방식 — null이면 '전체'(거르지 않는다). 하나만 고른다.
  ///
  /// 값의 정본은 **룸 문서의 `reservationModes`**이고, 장소 하나가 받는
  /// 방식은 [placeReservationModes]가 모아 준다 — 장소 문서에 새 필드를
  /// 만들지 않는다. 시간제와 숙박을 모두 받는 장소는 **두 조건 모두에서**
  /// 걸린다.
  ///
  /// 패키지(package)는 선택지로 두지 않는다 — 시간제/숙박과 같은 층의
  /// 구분이 아니라 그 위에 얹히는 상품 형태라, 게스트가 '어떻게 빌리나'로
  /// 고르는 축은 둘뿐이다.
  ReservationMode? reservationMode;

  PlaceFilter({
    Set<String>? regions,
    Set<String>? priceRanges,
    Set<String>? capacityRanges,
    Set<String>? placeTypes,
    Set<String>? facilities,
    Set<String>? customAmenities,
    this.eventOnly = false,
    this.petFriendlyOnly = false,
    this.outsideFoodOnly = false,
    this.useDate,
    this.startTime,
    this.endTime,
    this.availabilityMode = PlaceAvailabilityMode.full,
    this.minCapacity,
    this.reservationMode,
  }) : regions = regions ?? {},
       priceRanges = priceRanges ?? {},
       capacityRanges = capacityRanges ?? {},
       placeTypes = placeTypes ?? {},
       facilities = facilities ?? {},
       customAmenities = customAmenities ?? {};

  bool get isActive =>
      regions.isNotEmpty ||
      priceRanges.isNotEmpty ||
      capacityRanges.isNotEmpty ||
      placeTypes.isNotEmpty ||
      facilities.isNotEmpty ||
      customAmenities.isNotEmpty ||
      eventOnly ||
      petFriendlyOnly ||
      outsideFoodOnly ||
      useDate != null ||
      minCapacity != null ||
      reservationMode != null;

  /// 🏠 장소 유형 조건 하나만 본 판정 — **OR**다.
  ///
  /// 고른 유형 중 **하나라도** 가진 장소면 남는다(파티룸+루프탑+바를 고르면
  /// 셋 중 하나이기만 하면 된다). 장소는 유형을 여러 개 가질 수 있으므로
  /// (등록 화면이 [ListingConstants.placeTypes]에서 복수 선택), 여러 개를 가진
  /// 장소도 그중 하나만 겹치면 걸린다.
  ///
  /// 저장 필드는 등록 화면이 쓰는 그대로다 — 정본은 `types`(복수), 옛 문서는
  /// `type`(단일) 하나짜리 목록으로 본다. 여기서 새 필드를 만들지 않는다.
  ///
  /// 고르지 않았으면 언제나 통과. 목록 위 대여유형 시트와 상세검색이 **같은
  /// 한 칸**([placeTypes])을 고치므로, 어느 쪽에서 골라도 이 판정 하나를 지난다.
  bool matchesPlaceTypes(Map<String, dynamic> data) {
    if (placeTypes.isEmpty) return true;
    final types =
        (data['types'] as List?)?.cast<String>() ??
        [
          if ((data['type'] as String? ?? '').isNotEmpty)
            data['type'] as String,
        ];
    return types.any(placeTypes.contains);
  }

  /// 🎪 이벤트 조건 하나만 본 판정 — 이 장소를 장소대여 목록에 남길 것인가.
  ///
  /// 조건을 켜지 않았으면 언제나 통과다. 켰다면 **[index]가 정본**이고, 그
  /// 색인은 공간 이벤트만 담은 것이어야 한다
  /// ([PlaceEventIndex.rentalCollection]) — 매장 이벤트가 담긴 색인을 넘기면
  /// 장소대여 목록에 남의 탭 이벤트가 새어 들어온다.
  ///
  /// 색인이 아직 없으면(못 읽었으면) **아무것도 통과시키지 않는다.** 여기는
  /// 플레이스 탭([EventFilter.matchesDiscovery])과 달리 기댈 옛 미러 필드가
  /// 없어서, 통과시키면 조건을 안 건 것과 같아진다.
  ///
  /// 규칙 자체는 [PlaceEventIndex.allows]가 갖고 있다 — 지도의 장소대여
  /// 마커도 같은 함수를 부르므로 목록과 지도가 갈릴 수 없다.
  /// 🎪 공간 이벤트 조건. [doc]을 주면 고른 날짜·시간까지 함께 본다 —
  /// 판정은 매장 이벤트와 **같은 함수**다([PlaceEventIndex.allows]).
  ///
  /// 이 필터의 날짜는 하나뿐이므로([useDate]) 있으면 하루짜리 목록으로 넘긴다.
  bool matchesEvent(
    String? docId,
    PlaceEventIndex? index, {
    Map<String, dynamic>? doc,
  }) => PlaceEventIndex.allows(
    eventOnly: eventOnly,
    docId: docId,
    index: index,
    doc: doc,
    dates: useDate == null ? const <DateTime>[] : <DateTime>[useDate!],
    start: startTime,
    end: endTime,
  );

  /// 시간까지 모두 고른 상태인지.
  bool get hasTimeRange => startTime != null && endTime != null;

  /// 이용 가능 여부 판정에 넘길 요청. 날짜를 안 골랐으면 null.
  PlaceAvailabilityRequest? get availabilityRequest {
    final date = useDate;
    if (date == null) return null;
    return PlaceAvailabilityRequest.from(
      date: date,
      start: startTime,
      end: endTime,
      mode: availabilityMode,
    );
  }

  PlaceFilter copy() => PlaceFilter(
    regions: {...regions},
    priceRanges: {...priceRanges},
    capacityRanges: {...capacityRanges},
    placeTypes: {...placeTypes},
    facilities: {...facilities},
    customAmenities: {...customAmenities},
    eventOnly: eventOnly,
    petFriendlyOnly: petFriendlyOnly,
    outsideFoodOnly: outsideFoodOnly,
    useDate: useDate,
    startTime: startTime,
    endTime: endTime,
    availabilityMode: availabilityMode,
    minCapacity: minCapacity,
    reservationMode: reservationMode,
  );

  List<MapEntry<String, String>> get selectedEntries => [
    // 칩에는 '서울'이 아니라 '서울 전체'로 — 구 이름과 헷갈리지 않게.
    ...regions.map((v) => MapEntry('regions', RegionSelection.label(v))),
    if (useDate != null) MapEntry('useDate', '📅 ${formatDate(useDate!)}'),
    // 시간은 날짜에 딸린 조건이라 칩도 하나만 둔다. 이용 조건(전체/일부)은
    // 시간 조건의 성격이라 같은 칩에 붙여 둔다.
    if (useDate != null && hasTimeRange)
      MapEntry(
        'useTime',
        '🕒 $timeRangeLabel'
            '${availabilityMode == PlaceAvailabilityMode.partial ? ' · 일부 가능' : ''}',
      ),
    if (minCapacity != null)
      MapEntry('minCapacity', '👥 ${CapacityFilter.label(minCapacity!)}'),
    if (reservationMode != null)
      MapEntry('reservationMode', reservationMode!.chipLabel),
    ...priceRanges.map((v) => MapEntry('priceRanges', v)),
    ...capacityRanges.map((v) => MapEntry('capacityRanges', v)),
    ...placeTypes.map((v) => MapEntry('placeTypes', v)),
    ...facilities.map((v) => MapEntry('facilities', v)),
    // 기타는 호스트가 만든 말이라 표기 표가 없다 — 저장한 원문이 곧 표기다.
    ...customAmenities.map((v) => MapEntry('customAmenities', v)),
    if (eventOnly) const MapEntry('eventOnly', '✨ 이벤트 진행중'),
    if (petFriendlyOnly) const MapEntry('petFriendlyOnly', '애견동반 가능만 보기'),
    if (outsideFoodOnly) const MapEntry('outsideFoodOnly', '🍕 외부 음식 가능만 보기'),
  ];

  void removeValue(String category, String value) {
    switch (category) {
      case 'regions':
        // 칩에 적힌 표기로 어느 지역인지 되찾는다 — 라벨을 만드는 곳과 지우는
        // 곳이 같은 [RegionSelection.label]을 쓰므로 표기가 갈라질 수 없다.
        regions.removeWhere((k) => RegionSelection.label(k) == value);
        break;
      case 'useDate':
        // 날짜를 지우면 시간 조건도 함께 사라진다 — 날짜 없는 시간은 뜻이 없다.
        clearSchedule();
        break;
      case 'useTime':
        startTime = null;
        endTime = null;
        availabilityMode = PlaceAvailabilityMode.full;
        break;
      case 'priceRanges':
        priceRanges.remove(value);
        break;
      case 'capacityRanges':
        capacityRanges.remove(value);
        break;
      case 'minCapacity':
        minCapacity = null;
        break;
      case 'reservationMode':
        reservationMode = null;
        break;
      case 'placeTypes':
        placeTypes.remove(value);
        break;
      case 'facilities':
        facilities.remove(value);
        break;
      case 'customAmenities':
        customAmenities.removeWhere((v) => CustomAmenities.sameItem(v, value));
        break;
      case 'outsideFoodOnly':
        outsideFoodOnly = false;
        break;
      case 'eventOnly':
        eventOnly = false;
        break;
      case 'petFriendlyOnly':
        petFriendlyOnly = false;
        break;
    }
  }

  void clearSchedule() {
    useDate = null;
    startTime = null;
    endTime = null;
    availabilityMode = PlaceAvailabilityMode.full;
  }

  /// '8월 20일 (수)'.
  static String formatDate(DateTime d) =>
      '${d.month}월 ${d.day}일 (${_weekdayLabels[d.weekday - 1]})';

  /// '오후 7:00'.
  static String formatTime(TimeOfDay t) {
    final ampm = t.hour < 12 ? '오전' : '오후';
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$ampm $h:${t.minute.toString().padLeft(2, '0')}';
  }

  /// '오후 7:00 ~ 오후 11:00' / 자정을 넘기면 '오후 10:00 ~ 익일 오전 2:00'.
  String get timeRangeLabel {
    if (!hasTimeRange) return '';
    final crosses = availabilityRequest?.crossesMidnight ?? false;
    final end = formatTime(endTime!);
    return '${formatTime(startTime!)} ~ ${crosses ? '익일 $end' : end}';
  }

  static const _weekdayLabels = ['월', '화', '수', '목', '금', '토', '일'];
}

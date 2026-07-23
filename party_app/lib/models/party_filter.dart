import 'package:flutter/material.dart' show TimeOfDay;

/// 파티 목록 정렬 방식 — 메인/지도 화면과 상세검색 시트(정렬 아코디언)가 공유한다.
enum PartySortMode {
  defaultOrder('기본순'),
  distance('거리순'),
  deadlineSoon('마감 임박순'),
  feeLow('참가비 낮은순'),
  feeHigh('참가비 높은순'),
  capacityLow('정원 작은순'),
  capacityHigh('정원 높은순');

  const PartySortMode(this.label);
  final String label;
}

class PartyFilter {
  /// 선택된 구/시/군 (예: "강남구", "성남시"). 최대 [maxDistricts]개.
  Set<String> districts;
  Set<String> genderConditions;
  Set<String> dateOptions;
  Set<String> feeRanges;
  Set<String> partyTypes;
  Set<String> vibes;
  /// 연령대(10년 단위: "20대"/"30대"/"40대 이상") — 파티에 저장된 연령 제한
  /// 범위와 겹치는지로 매칭한다. 연령 제한이 없는 파티는 모든 연령대에 매칭된다.
  Set<String> ageGroups;
  /// 자유 입력 태그 키워드 — 파티에 달린 태그(호스트가 등록 시 직접 입력, 최대 5개)
  /// 중 하나라도 키워드를 포함하면 매칭된다.
  Set<String> tagKeywords;
  /// 로그인한 사용자의 성별/연령/모집 상태 기준으로 실제 신청 가능한 파티만
  /// 보여줄지 여부(구 "모집중만 보기"를 대체) — checkPartyEligibility로 판단.
  bool eligibleOnly;
  bool earlyBirdOnly;
  DateTime? selectedDate;
  TimeOfDay? startTime;
  TimeOfDay? endTime;

  /// "파티 시작 시간" 필터 — 날짜와 무관하게 시간대만 비교한다.
  /// (selectedDate+startTime/endTime과 달리 특정 날짜를 고르지 않아도 동작)
  TimeOfDay? timeOfDayStart;
  TimeOfDay? timeOfDayEnd;

  PartySortMode sortMode;

  static const int maxDistricts = 5;

  PartyFilter({
    Set<String>? districts,
    Set<String>? genderConditions,
    Set<String>? dateOptions,
    Set<String>? feeRanges,
    Set<String>? partyTypes,
    Set<String>? vibes,
    Set<String>? ageGroups,
    Set<String>? tagKeywords,
    this.eligibleOnly = false,
    this.earlyBirdOnly = false,
    this.selectedDate,
    this.startTime,
    this.endTime,
    this.timeOfDayStart,
    this.timeOfDayEnd,
    this.sortMode = PartySortMode.defaultOrder,
  })  : districts = districts ?? {},
        genderConditions = genderConditions ?? {},
        dateOptions = dateOptions ?? {},
        feeRanges = feeRanges ?? {},
        partyTypes = partyTypes ?? {},
        vibes = vibes ?? {},
        ageGroups = ageGroups ?? {},
        tagKeywords = tagKeywords ?? {};

  bool get isActive =>
      districts.isNotEmpty ||
      genderConditions.isNotEmpty ||
      dateOptions.isNotEmpty ||
      feeRanges.isNotEmpty ||
      partyTypes.isNotEmpty ||
      vibes.isNotEmpty ||
      ageGroups.isNotEmpty ||
      tagKeywords.isNotEmpty ||
      eligibleOnly ||
      earlyBirdOnly ||
      selectedDate != null ||
      timeOfDayStart != null ||
      timeOfDayEnd != null ||
      sortMode != PartySortMode.defaultOrder;

  bool get hasAny => isActive;

  PartyFilter copy() => PartyFilter(
        districts: {...districts},
        genderConditions: {...genderConditions},
        dateOptions: {...dateOptions},
        feeRanges: {...feeRanges},
        partyTypes: {...partyTypes},
        vibes: {...vibes},
        ageGroups: {...ageGroups},
        tagKeywords: {...tagKeywords},
        eligibleOnly: eligibleOnly,
        earlyBirdOnly: earlyBirdOnly,
        selectedDate: selectedDate,
        startTime: startTime,
        endTime: endTime,
        timeOfDayStart: timeOfDayStart,
        timeOfDayEnd: timeOfDayEnd,
        sortMode: sortMode,
      );

  List<MapEntry<String, String>> get selectedEntries => [
        ...districts.map((v) => MapEntry('districts', v)),
        ...genderConditions.map((v) => MapEntry('genderConditions', v)),
        ...dateOptions.map((v) => MapEntry('dateOptions', v)),
        ...feeRanges.map((v) => MapEntry('feeRanges', v)),
        ...partyTypes.map((v) => MapEntry('partyTypes', v)),
        ...vibes.map((v) => MapEntry('vibes', v)),
        ...ageGroups.map((v) => MapEntry('ageGroups', v)),
        ...tagKeywords.map((v) => MapEntry('tagKeywords', '#$v')),
        if (selectedDate != null)
          MapEntry('selectedDate',
              '${selectedDate!.month}월 ${selectedDate!.day}일$_timeLabel'),
        if (timeOfDayStart != null || timeOfDayEnd != null)
          MapEntry('timeOfDay', '🕒 $_timeOfDayLabel'),
        if (sortMode != PartySortMode.defaultOrder)
          MapEntry('sortMode', '↕ ${sortMode.label}'),
        if (earlyBirdOnly) const MapEntry('earlyBirdOnly', '🎉 얼리버드 진행중'),
        if (eligibleOnly)
          const MapEntry('eligibleOnly', '✅ 내가 참여 가능한 파티만'),
      ];

  String get _timeOfDayLabel {
    final s = timeOfDayStart != null ? formatAmPm(timeOfDayStart!) : '';
    final e = timeOfDayEnd != null ? formatAmPm(timeOfDayEnd!) : '';
    if (s.isNotEmpty && e.isNotEmpty) return '$s ~ $e';
    if (s.isNotEmpty) return '$s ~';
    return '~ $e';
  }

  /// "오후 6:00" 형식(오전/오후 + 12시간제). 상세검색 시트와 선택 칩이 공유.
  static String formatAmPm(TimeOfDay t) {
    final ampm = t.hour < 12 ? '오전' : '오후';
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$ampm $h:$m';
  }

  /// 하루(00:00~23:30)를 30분 단위로 나눈 시간 목록.
  static List<TimeOfDay> get halfHourSlots => List.generate(
        48,
        (i) => TimeOfDay(hour: i ~/ 2, minute: (i % 2) * 30),
      );

  String get _timeLabel {
    if (startTime == null && endTime == null) return '';
    final s = startTime != null ? _fmt(startTime!) : '';
    final e = endTime != null ? _fmt(endTime!) : '';
    if (s.isNotEmpty && e.isNotEmpty) return ' $s~$e';
    if (s.isNotEmpty) return ' $s~';
    return ' ~$e';
  }

  static String _fmt(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  void removeValue(String category, String value) {
    switch (category) {
      case 'districts':
        districts.remove(value);
        break;
      case 'genderConditions':
        genderConditions.remove(value);
        break;
      case 'dateOptions':
        dateOptions.remove(value);
        break;
      case 'feeRanges':
        feeRanges.remove(value);
        break;
      case 'partyTypes':
        partyTypes.remove(value);
        break;
      case 'vibes':
        vibes.remove(value);
        break;
      case 'ageGroups':
        ageGroups.remove(value);
        break;
      case 'tagKeywords':
        tagKeywords.remove(value.replaceFirst('#', ''));
        break;
      case 'selectedDate':
        selectedDate = null;
        startTime = null;
        endTime = null;
        break;
      case 'timeOfDay':
        timeOfDayStart = null;
        timeOfDayEnd = null;
        break;
      case 'sortMode':
        sortMode = PartySortMode.defaultOrder;
        break;
      case 'earlyBirdOnly':
        earlyBirdOnly = false;
        break;
      case 'eligibleOnly':
        eligibleOnly = false;
        break;
    }
  }
}

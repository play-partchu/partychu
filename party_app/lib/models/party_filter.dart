import 'package:flutter/material.dart' show TimeOfDay;

import 'package:party_app/utils/party_scale_filter.dart';

/// 파티 목록 정렬 방식 — 메인 목록의 **정렬 버튼**([PartySortSheet])에서만 고른다.
///
/// 예전에는 상세검색 시트에도 같은 정렬 아코디언이 있어 입구가 둘이었는데,
/// 두 곳이 같은 값을 가리키면서도 "검색 조건"과 "목록 정렬"이 뒤섞여 보였다.
/// 지금은 정렬 입구가 하나뿐이라, 이 값은 상세검색 시트를 열고 닫아도 바뀌지
/// 않는다([PartyFilter.isActive]·[PartyFilter.selectedEntries]에서 빠져 있는
/// 이유이기도 하다 — 정렬은 걸러내는 조건이 아니다).
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

  /// 연령대(10년 단위: "20대"/"30대"/"40대"/"50대+", 옛 값 "40대 이상"도
  /// 판정에서 계속 받는다) — 파티에 저장된 연령 제한
  /// 범위와 겹치는지로 매칭한다. 연령 제한이 없는 파티는 모든 연령대에 매칭된다.
  Set<String> ageGroups;

  /// 자유 입력 태그 키워드 — 파티에 달린 태그(호스트가 등록 시 직접 입력, 최대 5개)
  /// 중 하나라도 키워드를 포함하면 매칭된다.
  Set<String> tagKeywords;

  /// 로그인한 사용자의 성별/연령/모집 상태 기준으로 실제 신청 가능한 파티만
  /// 보여줄지 여부(구 "모집중만 보기"를 대체) — checkPartyEligibility로 판단.
  bool eligibleOnly;
  bool earlyBirdOnly;

  /// 달력에서 직접 고른 날짜들(00:00으로 정규화). 최대 [maxSelectedDates]개이고,
  /// **하나라도 해당하면 통과**(OR)한다 — '오늘+내일'처럼 여러 날을 한 번에 볼 수
  /// 있어야 하기 때문이다. 비어 있으면 날짜로 거르지 않는다.
  Set<DateTime> selectedDates;

  /// [selectedDates]에 함께 적용되는 시간 범위 — 고른 날짜들의 회차 시작 시각이
  /// 이 범위 안이어야 한다. 날짜를 하나도 고르지 않으면 의미가 없다.
  TimeOfDay? startTime;
  TimeOfDay? endTime;

  /// 파티의 **최대 모집 인원 구간**([PartyScaleFilter.options]의 id).
  /// null이면 규모로 거르지 않는다.
  ///
  /// '이 파티가 몇 명을 모으는 파티인가'만 본다 — 남은 자리·현재 신청자 수·
  /// 모집 마감은 보지 않는다(그건 [eligibleOnly]가 맡는 다른 축이다).
  String? partyScale;

  /// "파티 시작 시간" 필터 — 날짜와 무관하게 시간대만 비교한다.
  /// (selectedDate+startTime/endTime과 달리 특정 날짜를 고르지 않아도 동작)
  TimeOfDay? timeOfDayStart;
  TimeOfDay? timeOfDayEnd;

  PartySortMode sortMode;

  static const int maxDistricts = 5;

  /// 달력에서 한 번에 고를 수 있는 날짜 수.
  static const int maxSelectedDates = 5;

  PartyFilter({
    Set<String>? districts,
    Set<String>? genderConditions,
    Set<String>? dateOptions,
    Set<String>? feeRanges,
    Set<String>? partyTypes,
    Set<String>? vibes,
    Set<String>? ageGroups,
    Set<String>? tagKeywords,
    Set<DateTime>? selectedDates,
    this.partyScale,
    this.eligibleOnly = false,
    this.earlyBirdOnly = false,
    this.startTime,
    this.endTime,
    this.timeOfDayStart,
    this.timeOfDayEnd,
    this.sortMode = PartySortMode.defaultOrder,
  }) : selectedDates = selectedDates ?? {},
       districts = districts ?? {},
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
      partyScale != null ||
      eligibleOnly ||
      earlyBirdOnly ||
      selectedDates.isNotEmpty ||
      timeOfDayStart != null ||
      timeOfDayEnd != null;

  bool get hasAny => isActive;

  /// 날짜 하나를 켜고 끈다(toggle).
  ///
  /// 이미 고른 날짜면 해제하고, 새 날짜인데 이미 [maxSelectedDates]개를 골랐으면
  /// **아무것도 하지 않고 false**를 돌려준다 — 호출부가 "최대 N개" 안내를 띄운다.
  /// 마지막 날짜를 해제하면 그 날짜들에 딸려 있던 시간 범위도 함께 지운다.
  bool toggleDate(DateTime day) {
    final d = dateOnly(day);
    if (selectedDates.remove(d)) {
      if (selectedDates.isEmpty) {
        startTime = null;
        endTime = null;
      }
      return true;
    }
    if (selectedDates.length >= maxSelectedDates) return false;
    selectedDates.add(d);
    return true;
  }

  /// 고른 날짜들을 이른 순으로 — 요약·칩 표시는 고른 순서가 아니라 날짜 순이다.
  List<DateTime> get selectedDatesSorted =>
      selectedDates.toList()..sort((a, b) => a.compareTo(b));

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// '8월 15일' — 날짜 칩·요약이 함께 쓰는 표기.
  static String formatDateLabel(DateTime d) => '${d.month}월 ${d.day}일';

  PartyFilter copy() => PartyFilter(
    districts: {...districts},
    genderConditions: {...genderConditions},
    dateOptions: {...dateOptions},
    feeRanges: {...feeRanges},
    partyTypes: {...partyTypes},
    vibes: {...vibes},
    ageGroups: {...ageGroups},
    tagKeywords: {...tagKeywords},
    selectedDates: {...selectedDates},
    partyScale: partyScale,
    eligibleOnly: eligibleOnly,
    earlyBirdOnly: earlyBirdOnly,
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
    // 고른 날짜는 한 칸에 몰아넣지 않고 날짜마다 칩 하나로 — 여러 날을 고르는
    // 필터라 "8월 15일만 빼기"가 칩에서 바로 돼야 한다.
    ...selectedDatesSorted.map(
      (d) => MapEntry('selectedDates', formatDateLabel(d)),
    ),
    // 시간 범위는 고른 날짜 전체에 걸리므로 칩도 하나만 둔다.
    if (selectedDates.isNotEmpty && (startTime != null || endTime != null))
      MapEntry('dateTimeRange', '🕒$_timeLabel'),
    if (timeOfDayStart != null || timeOfDayEnd != null)
      MapEntry('timeOfDay', '🕒 $_timeOfDayLabel'),
    // 규모는 하나만 고르므로 칩도 하나다.
    if (partyScale != null)
      MapEntry('partyScale', '👥 ${PartyScaleFilter.label(partyScale!)}'),
    if (earlyBirdOnly) const MapEntry('earlyBirdOnly', '🎉 얼리버드 진행중'),
    if (eligibleOnly) const MapEntry('eligibleOnly', '✅ 내가 참여 가능한 파티만'),
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
  static List<TimeOfDay> get halfHourSlots =>
      List.generate(48, (i) => TimeOfDay(hour: i ~/ 2, minute: (i % 2) * 30));

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
      case 'selectedDates':
        // 칩에 적힌 라벨로 어느 날짜인지 되찾는다 — 라벨을 만드는 곳과 지우는
        // 곳이 같은 [formatDateLabel]을 쓰므로 표기가 갈라질 수 없다.
        selectedDates.removeWhere((d) => formatDateLabel(d) == value);
        if (selectedDates.isEmpty) {
          startTime = null;
          endTime = null;
        }
        break;
      case 'dateTimeRange':
        startTime = null;
        endTime = null;
        break;
      case 'timeOfDay':
        timeOfDayStart = null;
        timeOfDayEnd = null;
        break;
      case 'partyScale':
        partyScale = null;
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

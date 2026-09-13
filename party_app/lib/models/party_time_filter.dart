import 'package:flutter/material.dart' show TimeOfDay;

import 'package:party_app/models/day_time_match.dart';
import 'package:party_app/models/party_schedule.dart';

/// 파티 목록의 **시간 조건** — '지정 시간' 하나이거나 '지정 구간' 하나다.
///
/// ## 무엇을 묻는가
///
/// 두 방식은 뜻이 다르다.
///
/// - **지정 시간**(오후 7:00) → 그 시각에 **진행 중인** 파티. 7시에 시작하는
///   파티만이 아니라 6시에 시작해 9시에 끝나는 파티도 그 시각에 함께할 수
///   있으므로 걸린다.
/// - **지정 구간**(오후 6:00 ~ 오후 10:00) → 파티 진행 시간이 그 구간과
///   **겹치는** 파티. 구간 안에 통째로 들어와야 하는 것이 아니다.
///
/// 두 방식은 [PartyFilter.timeOfDayStart]/[PartyFilter.timeOfDayEnd] 한 쌍으로
/// 구별한다(플레이스 탭의 방문 시간과 **같은 규약**이다):
///
///   시작만 있음 → 지정 시간 · 둘 다 있음 → 지정 구간
///
/// ## 새 필드를 만들지 않는다
///
/// 진행 시간의 정본은 이미 있는 일정 구조다([PartySchedule]) — 정기 파티는
/// 요일별 회차(`recurringSchedule.slots`의 시작·종료), 일회성 파티는
/// `singleSchedule`의 시작·종료다. 여기서는 그 회차를 읽어 **하루 중 몇 분부터
/// 몇 분까지인지**로만 바꾼다.
class PartyTimeFilter {
  PartyTimeFilter._();

  /// 종료 시각이 없는 옛 문서를 몇 분짜리로 볼지.
  ///
  /// 종료를 안 적은 파티를 "0분짜리"로 보면 지정 시간이 시작 시각과 1분도
  /// 어긋나면 안 되는 조건이 되어 사실상 아무것도 걸리지 않는다. 차수 종료를
  /// 모를 때 2시간으로 채우는 [PartyRoundOffers]와 같은 값을 쓴다.
  static const int defaultDurationMinutes = 120;

  static int _minutesOf(DateTime d) => d.hour * 60 + d.minute;

  /// 회차 하나가 하루 중 차지하는 구간(분). 자정을 넘기면 [to]가 1440을 넘는다.
  static DayInterval _intervalOf(PartyOccurrence occ) {
    final from = _minutesOf(occ.start);
    // PartyOccurrence.end는 종료를 모르는 일회성 파티에서 시작과 같다.
    var to = occ.end.isAfter(occ.start)
        ? from + occ.end.difference(occ.start).inMinutes
        : from + defaultDurationMinutes;
    if (to <= from) to = from + defaultDurationMinutes;
    return DayInterval(from, to);
  }

  /// 이 파티가 실제로 진행되는 구간들.
  ///
  /// [onDays]가 있으면(= 날짜 조건이 걸려 있으면) **그 날짜의 회차만** 본다 —
  /// 요일마다 시각이 다른 정기 파티에서 "고른 날짜의 그 시간"이 되도록 하기
  /// 위해서다. 날짜 조건이 없으면 다음 회차 하나를 본다(목록 카드가 보여주는
  /// 그 회차다).
  static List<DayInterval> intervalsOf(
    Map<String, dynamic> data, {
    Iterable<DateTime> onDays = const [],
    DateTime? now,
  }) {
    final days = onDays.toList();
    if (days.isEmpty) {
      final occ = PartySchedule.nextOccurrence(data, now: now);
      return occ == null ? const [] : [_intervalOf(occ)];
    }
    final out = <DayInterval>[];
    for (final day in days) {
      final occ = _occurrenceOn(data, day, now: now);
      if (occ != null) out.add(_intervalOf(occ));
    }
    return out;
  }

  /// [day]에 열리는 회차 — 정기는 그 요일 회차, 일회성은 그날이 곧 그 파티일
  /// 때만. ([PartySchedule.startOnDay]와 같은 판정이고 종료까지 함께 준다.)
  static PartyOccurrence? _occurrenceOn(
    Map<String, dynamic> data,
    DateTime day, {
    DateTime? now,
  }) {
    if (PartySchedule.isRecurring(data)) {
      return PartySchedule.recurringOf(data)?.occurrenceOn(day);
    }
    final occ = PartySchedule.nextOccurrence(data, now: now);
    if (occ == null) return null;
    final s = occ.start;
    final sameDay =
        s.year == day.year && s.month == day.month && s.day == day.day;
    return sameDay ? occ : null;
  }

  /// 시간 조건이 걸려 있는지.
  static bool isActive(TimeOfDay? start, TimeOfDay? end) =>
      DayTimeMatch.isActive(start, end);

  /// [intervals] 중 **하나라도** 조건에 걸리면 true(회차가 여럿이면 OR).
  ///
  /// 조건이 없으면 언제나 true이고, 진행 시간을 읽지 못한 파티는 조건이 걸린
  /// 동안 빠진다(날짜 미정 파티를 빼는 것과 같은 태도).
  /// 규칙의 정본은 [DayTimeMatch.matches]다 — 매장 이벤트도 같은 함수를 쓴다.
  /// 여기 남은 것은 "파티 회차를 구간으로 바꾸는 일"([intervalsOf])뿐이다.
  static bool matches(
    List<DayInterval> intervals,
    TimeOfDay? start,
    TimeOfDay? end,
  ) => DayTimeMatch.matches(intervals, start, end);
}

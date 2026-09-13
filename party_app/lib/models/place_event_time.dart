import 'package:flutter/material.dart' show TimeOfDay;

import 'package:party_app/models/day_time_match.dart';
import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/models/place_weekly_hours.dart';

/// 매장·공간 이벤트의 **"언제 하는가"** 판정 — 날짜와 시간, 두 축.
///
/// ## 새 필드를 만들지 않는다
///
/// 이벤트 시간의 정본은 이미 [PlacePromotion]에 있다. 이 파일은 그 필드들을
/// 읽어 **판정만** 한다 — Firestore에 새로 적는 값은 하나도 없다.
///
/// | 필드 | 뜻 |
/// |---|---|
/// | `isAlways`            | 상시 진행 — 시작일·종료일과 무관하게 계속 |
/// | `startAt` / `endAt`   | 이벤트 기간(날짜). 날짜 단위로 양끝 포함 |
/// | `weekdays`            | 진행 요일(1=월…7=일). 비어 있으면 매일 |
/// | `startTime`/`endTime` | 진행 시간 'HH:mm'. **둘 다 비면 영업시간 전체** |
///
/// ## 영업중(전시간)을 새 필드로 만들지 않은 이유
///
/// `startTime`·`endTime`이 **둘 다 비어 있는 상태**가 예전부터 "시간 제한 없음"
/// 이었다. 그 뜻이 곧 "매장이 여는 동안 내내"이므로, 새 불리언을 하나 더 두면
/// 같은 것을 두 곳에 저장하게 되고 둘이 어긋날 때 어느 쪽이 정본인지 알 수
/// 없어진다. 그래서 **이미 있는 상태에 이름만 붙였다**([isBusinessHours]).
///
/// 덕분에 기존 문서가 그대로 이 뜻이 된다 — 마이그레이션이 0건이고, 옛 이벤트도
/// 시간 검색에서 빠지지 않는다.
///
/// ⚠️ 영업중(전시간)은 **24시간 영업이 아니다.** 매장이 18:00~02:00 영업이면
///    이벤트도 그 시간 동안만 적용된다 — 그래서 판정에 그 매장의 영업시간
///    정본([PlaceWeeklyHours])이 필요하다.
class PlaceEventTime {
  PlaceEventTime._();

  /// 이 이벤트가 **영업시간 전체**에 적용되는가 — 시작·종료를 둘 다 안 정했다.
  static bool isBusinessHours(PlacePromotion p) =>
      (p.startTime ?? '').trim().isEmpty && (p.endTime ?? '').trim().isEmpty;

  /// 화면에 쓰는 문구. 시간을 정했으면 '22:00 ~ 02:00', 아니면 '영업중(전시간)'.
  ///
  /// 카드·상세·등록 미리보기가 **이 함수 하나**를 부른다 — 자리마다 다른 말로
  /// 부르면 같은 이벤트가 화면마다 달라 보인다.
  static const String businessHoursLabel = '영업중(전시간)';

  static String timeLabelOf(PlacePromotion p) =>
      isBusinessHours(p) ? businessHoursLabel : (p.timeLabel ?? '');

  // ── 날짜 축 ───────────────────────────────────────────────────────────

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  /// [date]에 이 이벤트가 **실제로 진행 중**인가.
  ///
  /// 등록일이나 매장 영업일이 아니라 **이벤트 기간**을 본다. 기간이 9/1~9/10인
  /// 이벤트는 9/5에 걸리고 9/15에는 걸리지 않는다.
  ///
  /// 판정 순서:
  ///   ① 진행 요일을 정했으면 그 요일이 아닌 날은 제외한다.
  ///   ② 상시 진행이면 요일만 맞으면 언제나 진행 중이다(기간을 안 본다 —
  ///      [PlacePromotion.statusAt]이 상시를 다루는 방식과 같다).
  ///   ③ 기간이 있으면 시작일·종료일을 **양끝 포함**으로 본다.
  ///   ④ 기간을 아예 안 적었으면 날짜로는 거르지 않는다.
  static bool runsOn(PlacePromotion p, DateTime date) {
    final day = _dayOf(date);

    // ① 진행 요일 — 비어 있거나 이레 전부면 제한이 없다.
    if (p.weekdays.isNotEmpty &&
        p.weekdays.length < 7 &&
        !p.weekdays.contains(day.weekday)) {
      return false;
    }

    if (p.isAlways) return true;

    final start = p.startAt == null ? null : _dayOf(p.startAt!);
    final end = p.endAt == null ? null : _dayOf(p.endAt!);
    if (start != null && day.isBefore(start)) return false;
    if (end != null && day.isAfter(end)) return false;
    return true;
  }

  /// 고른 날짜들 중 **하루라도** 진행 중이면 통과(여러 날은 OR).
  /// 날짜를 안 골랐으면 조건이 없는 것이라 언제나 통과다.
  static bool matchesDates(PlacePromotion p, Iterable<DateTime> dates) {
    final list = dates.toList();
    if (list.isEmpty) return true;
    return list.any((d) => runsOn(p, d));
  }

  // ── 시간 축 ───────────────────────────────────────────────────────────

  /// 이 이벤트가 하루 중 차지하는 구간들(자정 기준 분).
  ///
  /// - **시간 지정** → 적어 둔 'HH:mm' 한 구간. 종료가 시작보다 이르면 자정을
  ///   넘긴 것으로 본다(22:00~02:00 → 1320~1560).
  /// - **한쪽만 적음** → 시작만 있으면 '그 시각부터 그날 끝까지', 종료만 있으면
  ///   '자정부터 그 시각까지'. 시간 필터가 끝만 고른 경우를 보는 방식과 같다.
  /// - **영업중(전시간)** → 그 매장의 [hours]에서 [date] 주변 영업 구간을 뜬다.
  ///   영업시간을 등록하지 않은 매장이면 **빈 목록**이다 — 모르는 시간을
  ///   추측해서 끼워 넣지 않는다.
  static List<DayInterval> intervalsOf(
    PlacePromotion p, {
    PlaceWeeklyHours? hours,
    DateTime? date,
  }) {
    if (!isBusinessHours(p)) {
      final both = DayInterval.fromHhmm(p.startTime, p.endTime);
      if (both != null) return [both];
      // 한쪽만 적은 이벤트 — 나머지 끝은 그날의 경계로 본다.
      final from = DayInterval.parseHhmm(p.startTime);
      if (from != null) return [DayInterval(from, DayTimeMatch.minutesPerDay)];
      final to = DayInterval.parseHhmm(p.endTime);
      if (to != null) return [DayInterval(0, to)];
      return const [];
    }

    // 영업중(전시간) — 매장 영업시간이 곧 이벤트 시간이다.
    if (hours == null) return const [];
    final base = _dayOf(date ?? DateTime.now());
    final out = <DayInterval>[];
    for (final seg in hours.openSegmentsAround(base)) {
      final from = seg.start.difference(base).inMinutes;
      final to = seg.end.difference(base).inMinutes;
      if (to > from) out.add(DayInterval(from, to));
    }
    return out;
  }

  /// 고른 시각·시간대에 이 이벤트가 **적용 중**인가.
  ///
  /// 판정 규칙은 파티와 **같은 함수** 하나다([DayTimeMatch.matches]) — 자정
  /// 넘김도 거기서 함께 처리된다. 여기서 하는 일은 이벤트 필드를 구간으로
  /// 바꾸는 것뿐이다.
  static bool matchesTime(
    PlacePromotion p, {
    required TimeOfDay? start,
    required TimeOfDay? end,
    PlaceWeeklyHours? hours,
    Iterable<DateTime> dates = const [],
    DateTime? now,
  }) {
    if (!DayTimeMatch.isActive(start, end)) return true;

    // 날짜를 골랐으면 **그 날짜의** 영업 구간을 본다(요일마다 영업시간이
    // 다른 매장에서 "고른 날의 그 시간"이 되도록). 안 골랐으면 오늘 기준.
    final days = dates.toList();
    if (days.isEmpty) {
      return DayTimeMatch.matches(
        intervalsOf(p, hours: hours, date: now),
        start,
        end,
      );
    }
    return days.any((d) {
      if (!runsOn(p, d)) return false;
      return DayTimeMatch.matches(
        intervalsOf(p, hours: hours, date: d),
        start,
        end,
      );
    });
  }

  /// 날짜와 시간을 **함께** 만족하는가 — 목록·지도가 부르는 입구 하나.
  ///
  /// 둘 다 걸려 있으면 두 조건을 모두 만족해야 한다. 한쪽만 걸려 있으면 그
  /// 조건만 본다. 아무것도 안 걸렸으면 통과다.
  static bool matches(
    PlacePromotion p, {
    Iterable<DateTime> dates = const [],
    TimeOfDay? start,
    TimeOfDay? end,
    PlaceWeeklyHours? hours,
    DateTime? now,
  }) {
    if (!matchesDates(p, dates)) return false;
    return matchesTime(
      p,
      start: start,
      end: end,
      hours: hours,
      dates: dates,
      now: now,
    );
  }
}

import 'package:flutter/foundation.dart' show immutable;

import 'package:party_app/models/party_schedule.dart';

/// 목록이 지금 **어떤 날짜를 보고 있는지** — 날짜 퀵필터(오늘/내일/이번 주/
/// 이번 주말)와 상세검색의 날짜 조건을 하나로 모은 값이다.
///
/// ## 왜 필요한가
///
/// 카드는 게시글 하나를 한 장으로만 보여준다. 그동안 그 한 장에 적히는 날짜는
/// 언제나 "가장 가까운 다음 회차"였는데, 사용자가 '내일'을 눌러도 카드에는
/// 오늘 회차 날짜가 그대로 남아 필터 결과와 카드가 서로 다른 말을 했다.
/// 매일 열리는 정기 파티에서 특히 어긋났다.
///
/// 그래서 "지금 보고 있는 기준"을 [PartyDateFocus]로 만들어 카드에 넘기고,
/// 카드는 그 범위 안에서 **실제로 열리는 첫 회차**를 그린다. 기준이 없으면
/// (전체 탭) 예전처럼 다음 회차를 보여준다.
///
/// 날짜 범위 계산은 목록 필터(`_matchesSingleCategoryTab`·`_matchesDateOption`)와
/// 같은 규칙을 쓴다 — 필터가 통과시킨 파티는 이 범위 안에 반드시 회차가 있다.
@immutable
class PartyDateFocus {
  /// 하루 단위 범위들(시작·끝 모두 포함, 00:00으로 정규화). 여러 탭을 동시에
  /// 고를 수 있어 목록이다.
  final List<({DateTime from, DateTime to})> ranges;

  const PartyDateFocus._(this.ranges);

  static const empty = PartyDateFocus._([]);

  /// 날짜 기준이 하나도 없으면(= 전체) true — 카드는 예전 동작을 그대로 쓴다.
  bool get isEmpty => ranges.isEmpty;

  /// 화면에 걸려 있는 날짜 조건들을 모아 기준을 만든다.
  ///
  /// - [tabs]: 상단 퀵필터('오늘'/'내일'/'이번 주'/'이번 주말'). 비어 있으면 전체.
  /// - [dateOptions]: 상세검색 시트의 같은 조건(표기가 '이번주'처럼 붙어 있다).
  /// - [selectedDates]: 상세검색에서 달력으로 콕 집은 날짜들(여러 개 가능).
  ///
  /// 조건이 여럿이면 범위를 모두 담고, 카드는 그중 가장 이른 회차를 보여준다
  /// (목록 필터도 OR 매칭이라 판정 기준이 같다).
  factory PartyDateFocus.of({
    Iterable<String> tabs = const [],
    Iterable<String> dateOptions = const [],
    Iterable<DateTime> selectedDates = const [],
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final today = DateTime(at.year, at.month, at.day);
    final monday = today.subtract(Duration(days: at.weekday - 1));
    final saturday = monday.add(const Duration(days: 5));
    final sunday = monday.add(const Duration(days: 6));
    // 이미 지난 날은 기준에서 뺀다 — '이번 주'를 목요일에 눌렀다면 월요일이
    // 아니라 오늘부터다(목록 필터와 같은 보정).
    DateTime notBeforeToday(DateTime d) => d.isBefore(today) ? today : d;

    final ranges = <({DateTime from, DateTime to})>[];
    void add(DateTime from, DateTime to) {
      if (to.isBefore(from)) return;
      if (ranges.any((r) => r.from == from && r.to == to)) return;
      ranges.add((from: from, to: to));
    }

    for (final raw in [...tabs, ...dateOptions]) {
      // 같은 조건인데 화면마다 '이번 주'/'이번주'로 표기가 다르다 — 공백을
      // 지우고 하나로 본다.
      switch (raw.replaceAll(' ', '')) {
        case '오늘':
          add(today, today);
        case '내일':
          final tomorrow = today.add(const Duration(days: 1));
          add(tomorrow, tomorrow);
        case '이번주':
          add(today, sunday);
        case '이번주말':
          add(notBeforeToday(saturday), sunday);
      }
    }

    // 고른 날짜는 하루짜리 범위를 하나씩 만든다 — 범위가 여러 개면 카드는 그중
    // 가장 이른 회차를 그린다([firstStart]). 목록 필터도 같은 OR 판정이다.
    for (final selected in selectedDates) {
      final day = DateTime(selected.year, selected.month, selected.day);
      add(day, day);
    }

    return ranges.isEmpty ? empty : PartyDateFocus._(ranges);
  }

  /// 이 기준 안에서 [data]가 **가장 먼저 열리는 회차의 시작 시각**.
  ///
  /// 기준이 없거나(전체) 범위 안에 회차가 없으면 null — 호출부(카드)는 그때
  /// 예전처럼 "다음 회차"를 보여준다.
  DateTime? firstStart(Map<String, dynamic> data) {
    DateTime? best;
    for (final range in ranges) {
      var cursor = range.from;
      while (!cursor.isAfter(range.to)) {
        final start = PartySchedule.startOnDay(data, cursor);
        if (start != null) {
          if (best == null || start.isBefore(best)) best = start;
          break; // 이 범위에서는 첫 회차만 보면 된다.
        }
        cursor = cursor.add(const Duration(days: 1));
      }
    }
    return best;
  }
}

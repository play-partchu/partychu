// 지도 홈 🕐 날짜·시간의 표기 — 목록 탭과 같은 PartyFilter 칸을 읽는다(버튼의
// 적용 중 점, 판 안의 시간 칩 문구).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/models/date_time_filter_label.dart';
import 'package:party_app/models/party_filter.dart';

final now = DateTime(2026, 9, 19, 15);

PartyFilter f({
  Set<DateTime> dates = const {},
  TimeOfDay? start,
  TimeOfDay? end,
  List<String> options = const [],
}) => PartyFilter()
  ..selectedDates = {...dates}
  ..timeOfDayStart = start
  ..timeOfDayEnd = end
  ..dateOptions.addAll(options);

void main() {
  test('조건이 없으면 null(기본 문구는 부르는 쪽)', () {
    expect(dateTimeFilterLabel(f(), now: now), isNull);
  });

  test('날짜 — 오늘·내일·모레, 그 뒤는 M.D, 여러 날은 외 N', () {
    expect(dateTimeFilterLabel(f(dates: {DateTime(2026, 9, 19)}), now: now), '오늘');
    expect(dateTimeFilterLabel(f(dates: {DateTime(2026, 9, 20)}), now: now), '내일');
    expect(dateTimeFilterLabel(f(dates: {DateTime(2026, 9, 21)}), now: now), '모레');
    expect(dateTimeFilterLabel(f(dates: {DateTime(2026, 9, 25)}), now: now), '9.25');
    expect(
      dateTimeFilterLabel(
        f(dates: {DateTime(2026, 9, 25), DateTime(2026, 9, 19), DateTime(2026, 9, 27)}),
        now: now,
      ),
      '오늘 외 2',
    );
  });

  test('시간 — 지정 시간·지정 구간', () {
    expect(
      dateTimeFilterLabel(f(start: const TimeOfDay(hour: 19, minute: 0)), now: now),
      '19:00',
    );
    expect(
      dateTimeFilterLabel(
        f(
          start: const TimeOfDay(hour: 18, minute: 0),
          end: const TimeOfDay(hour: 22, minute: 30),
        ),
        now: now,
      ),
      '18:00–22:30',
    );
  });

  test('둘 다 — 날짜 · 시간', () {
    expect(
      dateTimeFilterLabel(
        f(dates: {DateTime(2026, 9, 20)}, start: const TimeOfDay(hour: 19, minute: 0)),
        now: now,
      ),
      '내일 · 19:00',
    );
  });

  test('상세검색의 예전 날짜 옵션도 그대로 적는다', () {
    expect(dateTimeFilterLabel(f(options: ['이번주말']), now: now), '이번주말');
  });

  test('지도 홈은 목록 탭과 같은 위젯·시트·칸을 쓴다(소스)', () {
    final map = File('lib/screens/map_screen.dart')
        .readAsStringSync()
        .replaceAll(RegExp(r'\s+'), ' ');
    // 글자 알약이 아니라 🕐 원형 버튼 — 적용 여부는 같은 표기 함수로 판단한다.
    expect(map.contains("'📅 날짜 · 시간'"), isFalse);
    expect(map.contains('final dateLabel = dateTimeFilterLabel(_filter);'), isTrue);
    expect(map.contains('active: dateLabel != null'), isTrue);
    expect(map.contains('QuickDatePane('), isTrue);
    expect(map.contains('await showKoreanCalendarSheet('), isTrue);
    expect(map.contains('await showVisitTimePicker('), isTrue);
    expect(map.contains('_filter.toggleDate(date)'), isTrue);
  });
}

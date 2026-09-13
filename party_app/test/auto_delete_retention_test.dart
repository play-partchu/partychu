// 보관기간 14일과 '자동삭제 D-n' 표시 — 지난 파티·임시저장 공통 규칙.
//
// 지키는 것:
//   · 보관기간은 14일 하나뿐이고, 앱이 세는 기준점과 서버가 지우는 기준점이
//     같다(파티 = 최종 종료 시각, 임시저장 = 마지막 저장 시각).
//   · **음수 D-day가 절대 나오지 않는다.** 삭제는 하루 한 번 도는 작업이라
//     기한이 지나고도 문서가 몇 시간 남아 있는 구간이 정상이다 — 그때
//     'D--1'이 뜨면 고장으로 읽힌다.
//   · 정기 파티의 기준점은 **마지막 회차가 끝난 시각**이다(첫 회차 캐시인
//     partyDateTime이 아니다). 서버 functions/partySchedule.js의
//     finalPartyEndAt과 같은 값이어야 한다.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/utils/auto_delete_retention.dart';

PartyWeeklySlot _slot(int sh, int sm, int eh, int em) => PartyWeeklySlot(
  enabled: true,
  startTime: TimeOfDay(hour: sh, minute: sm),
  endTime: TimeOfDay(hour: eh, minute: em),
);

PartyRecurringSchedule _schedule({
  required DateTime startDate,
  DateTime? endDate,
  Map<String, PartyWeeklySlot> slots = const {},
}) {
  final weekly = <String, PartyWeeklySlot>{
    for (final k in kPartyWeekdayKeys) k: const PartyWeeklySlot.disabled(),
  }..addAll(slots);
  return PartyRecurringSchedule(
    startDate: startDate,
    endDate: endDate,
    weekly: weekly,
  );
}

Map<String, dynamic> _recurringDoc({
  required DateTime startDate,
  DateTime? endDate,
  Map<String, PartyWeeklySlot> slots = const {},
}) => {
  'scheduleType': 'recurring',
  // 등록 시점의 첫 회차 캐시 — 기준점이 이 값에 끌려가면 안 된다.
  'partyDateTime': Timestamp.fromDate(startDate),
  'recurringSchedule': _schedule(
    startDate: startDate,
    endDate: endDate,
    slots: slots,
  ).toMap(),
};

void main() {
  group('보관기간', () {
    test('지난 파티와 임시저장이 같은 14일을 쓴다', () {
      expect(AutoDeleteRetention.window, const Duration(days: 14));
    });

    test('삭제 예정 시각은 기준점 + 14일', () {
      expect(
        AutoDeleteRetention.deleteAt(DateTime(2026, 8, 1, 22, 0)),
        DateTime(2026, 8, 15, 22, 0),
      );
      expect(AutoDeleteRetention.deleteAt(null), isNull);
    });
  });

  group('D-day 문구', () {
    final base = DateTime(2026, 8, 1, 22, 0); // 삭제 예정 = 8/15

    test('남은 날이 있으면 D-n', () {
      expect(
        AutoDeleteRetention.label(base, now: DateTime(2026, 8, 1, 23, 0)),
        '자동삭제 D-14',
      );
      expect(
        AutoDeleteRetention.label(base, now: DateTime(2026, 8, 12, 9, 0)),
        '자동삭제 D-3',
      );
      expect(
        AutoDeleteRetention.label(base, now: DateTime(2026, 8, 14, 23, 59)),
        '자동삭제 D-1',
      );
    });

    test('삭제일 당일은 "오늘 자동삭제"', () {
      expect(
        AutoDeleteRetention.label(base, now: DateTime(2026, 8, 15, 0, 1)),
        '오늘 자동삭제',
      );
      // 삭제 시각(22:00)을 지나도 그날 안이면 같은 문구다 — 실행 시차 구간.
      expect(
        AutoDeleteRetention.label(base, now: DateTime(2026, 8, 15, 23, 30)),
        '오늘 자동삭제',
      );
    });

    test('날짜가 지났으면 음수 D-day 대신 "삭제 예정"', () {
      for (final now in [
        DateTime(2026, 8, 16, 1, 0),
        DateTime(2026, 8, 20),
        DateTime(2027, 1, 1),
      ]) {
        final label = AutoDeleteRetention.label(base, now: now);
        expect(label, '삭제 예정');
        expect(label, isNot(contains('D--')));
      }
    });

    test('기준점을 모르면 아무 말도 하지 않는다', () {
      expect(AutoDeleteRetention.label(null), isNull);
      expect(AutoDeleteRetention.isUrgent(null), isFalse);
    });

    test('3일 이하만 급한 것으로 본다', () {
      expect(
        AutoDeleteRetention.isUrgent(base, now: DateTime(2026, 8, 11)),
        isFalse, // D-4
      );
      expect(
        AutoDeleteRetention.isUrgent(base, now: DateTime(2026, 8, 12)),
        isTrue, // D-3
      );
      expect(
        AutoDeleteRetention.isUrgent(base, now: DateTime(2026, 8, 20)),
        isTrue, // 이미 지남
      );
    });
  });

  group('파티의 기준점 — 최종 종료 시각', () {
    test('정기 파티는 마지막 회차가 끝난 시각을 쓴다', () {
      // 8/3(월) 시작, 종료일 9/2(수), 월·수 19:00~22:00 → 마지막 회차는 9/2.
      final doc = _recurringDoc(
        startDate: DateTime(2026, 8, 3),
        endDate: DateTime(2026, 9, 2),
        slots: {'monday': _slot(19, 0, 22, 0), 'wednesday': _slot(19, 0, 22, 0)},
      );
      expect(PartySchedule.finalEndAt(doc), DateTime(2026, 9, 2, 22, 0));
    });

    test('종료일에 회차가 없으면 그 앞의 마지막 회차를 찾는다', () {
      final doc = _recurringDoc(
        startDate: DateTime(2026, 8, 3),
        endDate: DateTime(2026, 9, 5), // 토요일 — 켜진 요일이 아니다
        slots: {'wednesday': _slot(19, 0, 22, 0)},
      );
      expect(PartySchedule.finalEndAt(doc), DateTime(2026, 9, 2, 22, 0));
    });

    test('자정을 넘기는 마지막 회차는 다음 날 새벽이 기준점', () {
      final doc = _recurringDoc(
        startDate: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 29), // 토요일
        slots: {'saturday': _slot(19, 0, 3, 0)},
      );
      expect(PartySchedule.finalEndAt(doc), DateTime(2026, 8, 30, 3, 0));
    });

    test('종료일 없는 무기한 정기 파티는 기준점이 없다', () {
      final doc = _recurringDoc(
        startDate: DateTime(2026, 8, 1),
        slots: {'saturday': _slot(19, 0, 22, 0)},
      );
      expect(PartySchedule.finalEndAt(doc), isNull);
      expect(AutoDeleteRetention.label(PartySchedule.finalEndAt(doc)), isNull);
    });

    test('일회성 파티는 종료 시각, 없으면 시작 시각', () {
      final withEnd = {
        'scheduleType': 'single',
        'singleSchedule': PartySingleSchedule(
          date: DateTime(2026, 8, 15),
          startTime: const TimeOfDay(hour: 20, minute: 0),
          endTime: const TimeOfDay(hour: 23, minute: 30),
        ).toMap(),
      };
      expect(
        PartySchedule.finalEndAt(withEnd),
        DateTime(2026, 8, 15, 23, 30),
      );

      final noEnd = {
        'scheduleType': 'single',
        'singleSchedule': PartySingleSchedule(
          date: DateTime(2026, 8, 15),
          startTime: const TimeOfDay(hour: 20, minute: 0),
        ).toMap(),
      };
      expect(PartySchedule.finalEndAt(noEnd), DateTime(2026, 8, 15, 20, 0));
    });

    test('singleSchedule이 없는 옛 문서는 partyDateTime을 쓴다', () {
      final legacy = {
        'partyDateTime': Timestamp.fromDate(DateTime(2026, 8, 15, 20, 0)),
      };
      expect(PartySchedule.finalEndAt(legacy), DateTime(2026, 8, 15, 20, 0));
      expect(PartySchedule.finalEndAt(<String, dynamic>{}), isNull);
    });
  });
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/models/party_schedule.dart';

PartyRecurringSchedule _schedule({
  required DateTime startDate,
  DateTime? endDate,
  Map<String, PartyWeeklySlot> slots = const {},
  PartyRecruitDeadlineRule deadline = const PartyRecruitDeadlineRule(),
}) {
  final weekly = <String, PartyWeeklySlot>{
    for (final k in kPartyWeekdayKeys) k: const PartyWeeklySlot.disabled(),
  }..addAll(slots);
  return PartyRecurringSchedule(
    startDate: startDate,
    endDate: endDate,
    weekly: weekly,
    deadlineRule: deadline,
  );
}

PartyWeeklySlot _slot(int sh, int sm, int eh, int em) => PartyWeeklySlot(
  enabled: true,
  startTime: TimeOfDay(hour: sh, minute: sm),
  endTime: TimeOfDay(hour: eh, minute: em),
);

void main() {
  // 2026-08-01은 토요일.
  final saturday = DateTime(2026, 8, 1);
  final monday = DateTime(2026, 8, 3);

  group('PartyScheduleType', () {
    test('없는 값/기존 문서는 일회성으로 본다', () {
      expect(PartyScheduleType.fromKey(null), PartyScheduleType.single);
      expect(PartyScheduleType.fromKey('single'), PartyScheduleType.single);
      expect(
        PartyScheduleType.fromKey('recurring'),
        PartyScheduleType.recurring,
      );
      expect(PartySchedule.typeOf({}), PartyScheduleType.single);
    });
  });

  group('자정을 넘기는 시간대', () {
    test('19:00~03:00은 다음 날 오전 3시 종료', () {
      final s = _schedule(
        startDate: DateTime(2026, 7, 1),
        slots: {'saturday': _slot(19, 0, 3, 0)},
      );
      final occ = s.occurrenceOn(saturday)!;
      expect(occ.start, DateTime(2026, 8, 1, 19, 0));
      expect(occ.end, DateTime(2026, 8, 2, 3, 0));
      expect(occ.crossesMidnight, isTrue);
    });

    test('19:00~22:00은 같은 날 종료', () {
      final s = _schedule(
        startDate: DateTime(2026, 7, 1),
        slots: {'monday': _slot(19, 0, 22, 0)},
      );
      final occ = s.occurrenceOn(monday)!;
      expect(occ.end, DateTime(2026, 8, 3, 22, 0));
      expect(occ.crossesMidnight, isFalse);
    });

    test('시작과 종료가 같으면 24시간으로 본다', () {
      final s = _schedule(
        startDate: DateTime(2026, 7, 1),
        slots: {'monday': _slot(19, 0, 19, 0)},
      );
      expect(s.occurrenceOn(monday)!.end, DateTime(2026, 8, 4, 19, 0));
    });

    test('일회성 파티도 20:00~02:00을 다음 날로 넘긴다', () {
      final single = PartySingleSchedule(
        date: DateTime(2026, 8, 15),
        startTime: const TimeOfDay(hour: 20, minute: 0),
        endTime: const TimeOfDay(hour: 2, minute: 0),
      );
      expect(single.start, DateTime(2026, 8, 15, 20, 0));
      expect(single.end, DateTime(2026, 8, 16, 2, 0));
    });
  });

  group('nextOccurrence', () {
    final weekdayParty = _schedule(
      startDate: DateTime(2026, 7, 1),
      slots: {for (final k in kPartyWeekdayKeysWeekday) k: _slot(19, 0, 22, 0)},
    );

    test('평일 파티는 같은 날 낮에 그 날 회차를 돌려준다', () {
      final occ = weekdayParty.nextOccurrence(DateTime(2026, 8, 3, 12, 0))!;
      expect(occ.start, DateTime(2026, 8, 3, 19, 0));
    });

    test('진행 중인 회차는 아직 "다음 회차"다', () {
      final occ = weekdayParty.nextOccurrence(DateTime(2026, 8, 3, 20, 30))!;
      expect(occ.start, DateTime(2026, 8, 3, 19, 0));
    });

    test('회차가 끝나면 다음 날로 넘어간다', () {
      final occ = weekdayParty.nextOccurrence(DateTime(2026, 8, 3, 23, 0))!;
      expect(occ.start, DateTime(2026, 8, 4, 19, 0));
    });

    test('금요일 밤이면 다음 회차는 월요일', () {
      final occ = weekdayParty.nextOccurrence(DateTime(2026, 8, 7, 23, 0))!;
      expect(occ.start, DateTime(2026, 8, 10, 19, 0));
    });

    test('자정을 넘겨 진행 중인 주말 회차도 잡는다', () {
      final weekendParty = _schedule(
        startDate: DateTime(2026, 7, 1),
        slots: {
          for (final k in kPartyWeekdayKeysWeekend) k: _slot(19, 0, 3, 0),
        },
      );
      // 일요일 새벽 1시 — 토요일 19시에 시작한 회차가 아직 진행 중이다.
      final occ = weekendParty.nextOccurrence(DateTime(2026, 8, 2, 1, 0))!;
      expect(occ.start, DateTime(2026, 8, 1, 19, 0));
      expect(occ.end, DateTime(2026, 8, 2, 3, 0));
    });

    test('시작일 전에는 시작일 이후 첫 회차를 돌려준다', () {
      final s = _schedule(
        startDate: DateTime(2026, 8, 10),
        slots: {'monday': _slot(19, 0, 22, 0)},
      );
      expect(
        s.nextOccurrence(DateTime(2026, 8, 3, 12, 0))!.start,
        DateTime(2026, 8, 10, 19, 0),
      );
    });

    test('시작일이 한 달 뒤여도 첫 회차를 찾는다', () {
      // 지금 기준 9일만 훑던 시절엔 null이 나와서, 다음 달부터 시작하는
      // 정기 파티는 아예 등록조차 되지 않았다.
      final s = _schedule(
        startDate: DateTime(2026, 10, 5),
        slots: {'monday': _slot(19, 0, 22, 0)},
      );
      expect(
        s.nextOccurrence(DateTime(2026, 8, 3, 12, 0))!.start,
        DateTime(2026, 10, 5, 19, 0),
      );
    });

    test('종료일이 지나면 더 이상 회차가 없다', () {
      final s = _schedule(
        startDate: DateTime(2026, 7, 1),
        endDate: DateTime(2026, 8, 3),
        slots: {'monday': _slot(19, 0, 22, 0)},
      );
      expect(s.nextOccurrence(DateTime(2026, 8, 3, 12, 0)), isNotNull);
      expect(s.nextOccurrence(DateTime(2026, 8, 5, 12, 0)), isNull);
    });

    test('요일을 하나도 고르지 않으면 회차가 없다', () {
      final s = _schedule(startDate: DateTime(2026, 7, 1));
      expect(s.hasEnabledDay, isFalse);
      expect(s.nextOccurrence(DateTime(2026, 8, 3)), isNull);
    });
  });

  group('모집 마감 규칙', () {
    test('시작 1시간 전', () {
      const rule = PartyRecruitDeadlineRule(
        mode: PartyDeadlineMode.beforeStart,
        minutesBefore: 60,
      );
      expect(
        rule.resolve(DateTime(2026, 8, 3, 19, 0)),
        DateTime(2026, 8, 3, 18, 0),
      );
    });

    test('시작 59분 전 — 분 단위로 잡힌다', () {
      const rule = PartyRecruitDeadlineRule(
        mode: PartyDeadlineMode.beforeStart,
        minutesBefore: 59,
      );
      expect(
        rule.resolve(DateTime(2026, 8, 10, 22, 0)),
        DateTime(2026, 8, 10, 21, 1),
      );
    });

    test('시작 1시간 30분 전', () {
      const rule = PartyRecruitDeadlineRule(
        mode: PartyDeadlineMode.beforeStart,
        minutesBefore: 90,
      );
      expect(rule.label, '파티 시작 1시간 30분 전');
      expect(
        rule.resolve(DateTime(2026, 8, 3, 19, 0)),
        DateTime(2026, 8, 3, 17, 30),
      );
    });

    test('시작 날짜 18시', () {
      const rule = PartyRecruitDeadlineRule(
        mode: PartyDeadlineMode.startDayTime,
        dayTime: TimeOfDay(hour: 18, minute: 0),
      );
      expect(
        rule.resolve(DateTime(2026, 8, 3, 19, 0)),
        DateTime(2026, 8, 3, 18, 0),
      );
    });

    test('시작 날짜 시각이 시작보다 늦으면 시작 시각으로 당긴다', () {
      const rule = PartyRecruitDeadlineRule(
        mode: PartyDeadlineMode.startDayTime,
        dayTime: TimeOfDay(hour: 22, minute: 0),
      );
      expect(
        rule.resolve(DateTime(2026, 8, 3, 19, 0)),
        DateTime(2026, 8, 3, 19, 0),
      );
    });

    test('시작 전날 20시 — 자정을 넘겨 끝나도 기준은 시작 날짜', () {
      const rule = PartyRecruitDeadlineRule(
        mode: PartyDeadlineMode.prevDayTime,
        dayTime: TimeOfDay(hour: 20, minute: 0),
      );
      // 8/1 22:00 시작 → 8/2 03:00 종료. 전날은 7/31이다(월/연도 넘김 포함).
      expect(
        rule.resolve(
          DateTime(2026, 8, 1, 22, 0),
          occurrenceEnd: DateTime(2026, 8, 2, 3, 0),
        ),
        DateTime(2026, 7, 31, 20, 0),
      );
    });

    test('직접 지정 — 시작 이후도 되지만 종료는 못 넘는다', () {
      final start = DateTime(2026, 8, 10, 22, 0);
      final end = DateTime(2026, 8, 11, 3, 0);
      final afterStart = PartyRecruitDeadlineRule(
        mode: PartyDeadlineMode.customDateTime,
        customAt: DateTime(2026, 8, 11, 1, 0),
      );
      expect(
        afterStart.resolve(start, occurrenceEnd: end),
        DateTime(2026, 8, 11, 1, 0),
      );
      expect(afterStart.startsBeforeDeadline(start), isTrue);

      final afterEnd = PartyRecruitDeadlineRule(
        mode: PartyDeadlineMode.customDateTime,
        customAt: DateTime(2026, 8, 11, 5, 0),
      );
      expect(afterEnd.resolve(start, occurrenceEnd: end), end);
    });

    test('마감 없음', () {
      const rule = PartyRecruitDeadlineRule(mode: PartyDeadlineMode.none);
      expect(rule.resolve(DateTime(2026, 8, 3, 19, 0)), isNull);
    });

    test('예전 문서(hoursBefore/sameDayTime)도 그대로 읽힌다', () {
      final hours = PartyRecruitDeadlineRule.fromMap({
        'mode': 'hoursBefore',
        'hours': 3,
      });
      expect(hours.mode, PartyDeadlineMode.beforeStart);
      expect(hours.minutesBefore, 180);

      final sameDay = PartyRecruitDeadlineRule.fromMap({
        'mode': 'sameDayTime',
        'time': '18:00',
      });
      expect(sameDay.mode, PartyDeadlineMode.startDayTime);
      expect(sameDay.dayTime, const TimeOfDay(hour: 18, minute: 0));
    });

    test('규칙 toMap/fromMap 왕복', () {
      final rules = [
        const PartyRecruitDeadlineRule(
          mode: PartyDeadlineMode.beforeStart,
          minutesBefore: 90,
        ),
        const PartyRecruitDeadlineRule(
          mode: PartyDeadlineMode.prevDayTime,
          dayTime: TimeOfDay(hour: 20, minute: 30),
        ),
        PartyRecruitDeadlineRule(
          mode: PartyDeadlineMode.customDateTime,
          customAt: DateTime(2026, 8, 11, 1, 0),
        ),
        PartyRecruitDeadlineRule.noDeadline,
      ];
      for (final rule in rules) {
        expect(PartyRecruitDeadlineRule.fromMap(rule.toMap()), rule);
      }
    });

    test('마감이 지나면 nextOpenOccurrence가 다음 회차로 넘어간다', () {
      final s = _schedule(
        startDate: DateTime(2026, 7, 1),
        slots: {
          for (final k in kPartyWeekdayKeysWeekday) k: _slot(19, 0, 22, 0),
        },
        deadline: const PartyRecruitDeadlineRule(
          mode: PartyDeadlineMode.beforeStart,
          minutesBefore: 60,
        ),
      );
      // 월요일 18:30 — 그 날 회차(19시)는 이미 18시에 마감됐다.
      final now = DateTime(2026, 8, 3, 18, 30);
      expect(s.nextOccurrence(now)!.start, DateTime(2026, 8, 3, 19, 0));
      expect(s.nextOpenOccurrence(now)!.start, DateTime(2026, 8, 4, 19, 0));
    });
  });

  group('요일 묶음 적용', () {
    test('평일에 같은 시간대를 한 번에 적용하고 개별 수정도 된다', () {
      var s = _schedule(startDate: DateTime(2026, 7, 1));
      s = s.applyTimesTo(kPartyWeekdayKeysWeekday, _slot(19, 0, 22, 0));
      expect(s.enabledDayKeys, kPartyWeekdayKeysWeekday);

      s = s.withSlot('friday', _slot(20, 0, 2, 0));
      expect(s.slotFor('monday').endTime, const TimeOfDay(hour: 22, minute: 0));
      expect(s.slotFor('friday').endTime, const TimeOfDay(hour: 2, minute: 0));
      expect(s.slotFor('friday').crossesMidnight, isTrue);
    });

    test('summaryLabel은 시간대가 같은 요일끼리 묶는다', () {
      var s = _schedule(startDate: DateTime(2026, 7, 1));
      s = s.applyTimesTo(kPartyWeekdayKeysWeekday, _slot(19, 0, 22, 0));
      s = s.applyTimesTo(kPartyWeekdayKeysWeekend, _slot(19, 0, 3, 0));
      expect(s.summaryLabel, '매주 월·화·수·목·금 19:00~22:00, 매주 토·일 19:00~03:00');
    });
  });

  group('직렬화', () {
    test('toMap/fromMap 왕복 — 켜진 요일만 저장된다', () {
      var s = _schedule(
        startDate: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 12, 31),
        deadline: const PartyRecruitDeadlineRule(
          mode: PartyDeadlineMode.startDayTime,
          dayTime: TimeOfDay(hour: 18, minute: 0),
        ),
      );
      s = s.applyTimesTo(['monday'], _slot(19, 0, 22, 0));
      s = s.applyTimesTo(['saturday'], _slot(19, 0, 3, 0));

      final map = s.toMap();
      expect((map['weeklySchedule'] as Map).keys.toSet(), {
        'monday',
        'saturday',
      });
      expect((map['weeklySchedule'] as Map)['monday'], {
        'enabled': true,
        'startTime': '19:00',
        'endTime': '22:00',
      });

      final back = PartyRecurringSchedule.fromMap(map)!;
      expect(back.startDate, DateTime(2026, 8, 1));
      expect(back.endDate, DateTime(2026, 12, 31));
      expect(back.enabledDayKeys, ['monday', 'saturday']);
      expect(
        back.slotFor('saturday').endTime,
        const TimeOfDay(hour: 3, minute: 0),
      );
      expect(back.deadlineRule.mode, PartyDeadlineMode.startDayTime);
      expect(back.deadlineRule.dayTime, const TimeOfDay(hour: 18, minute: 0));
      expect(back.slotFor('tuesday').enabled, isFalse);
    });

    test('임시저장 맵은 꺼진 요일의 시간까지 보존한다', () {
      var s = _schedule(startDate: DateTime(2026, 8, 1));
      s = s.applyTimesTo(['monday'], _slot(19, 0, 22, 0));
      s = s.withSlot('tuesday', _slot(20, 0, 23, 0).copyWith(enabled: false));

      final back = PartyRecurringSchedule.fromMap(s.toDraftMap())!;
      expect(back.enabledDayKeys, ['monday']);
      expect(
        back.slotFor('tuesday').startTime,
        const TimeOfDay(hour: 20, minute: 0),
      );
    });

    test('종료일 없음(null)도 왕복된다', () {
      var s = _schedule(startDate: DateTime(2026, 8, 1));
      s = s.applyTimesTo(['monday'], _slot(19, 0, 22, 0));
      expect(PartyRecurringSchedule.fromMap(s.toMap())!.endDate, isNull);
    });
  });

  group('PartySchedule (Firestore 문서 진입점)', () {
    Map<String, dynamic> recurringDoc() {
      var s = _schedule(startDate: DateTime(2026, 7, 1));
      s = s.applyTimesTo(kPartyWeekdayKeysWeekday, _slot(19, 0, 22, 0));
      return {'scheduleType': 'recurring', 'recurringSchedule': s.toMap()};
    }

    test('정기 파티는 다음 회차 시작 시각을 돌려준다', () {
      expect(
        PartySchedule.startAt(recurringDoc(), now: DateTime(2026, 8, 3, 12, 0)),
        DateTime(2026, 8, 3, 19, 0),
      );
    });

    test('정기 파티의 마감은 회차마다 계산된다', () {
      expect(
        PartySchedule.deadlineAt(
          recurringDoc(),
          now: DateTime(2026, 8, 3, 12, 0),
        ),
        DateTime(2026, 8, 3, 18, 0),
      );
      // 한 주 뒤에도 같은 규칙으로 새 마감이 열린다.
      expect(
        PartySchedule.deadlineAt(
          recurringDoc(),
          now: DateTime(2026, 8, 10, 12, 0),
        ),
        DateTime(2026, 8, 10, 18, 0),
      );
    });

    test('occursOnDay — 평일 정기 파티는 주말에 열리지 않는다', () {
      final doc = recurringDoc();
      expect(PartySchedule.occursOnDay(doc, DateTime(2026, 8, 3)), isTrue);
      expect(PartySchedule.occursOnDay(doc, DateTime(2026, 8, 1)), isFalse);
    });

    test('레거시 문서(partyDateTime만 있음)도 그대로 동작한다', () {
      final doc = {
        'partyDateTime': Timestamp.fromDate(DateTime(2026, 8, 15, 20, 0)),
        'recruitDeadlineAt': Timestamp.fromDate(DateTime(2026, 8, 15, 18, 0)),
      };
      expect(PartySchedule.typeOf(doc), PartyScheduleType.single);
      expect(PartySchedule.startAt(doc), DateTime(2026, 8, 15, 20, 0));
      expect(PartySchedule.deadlineAt(doc), DateTime(2026, 8, 15, 18, 0));
      expect(PartySchedule.occursOnDay(doc, DateTime(2026, 8, 15)), isTrue);
      expect(PartySchedule.occursOnDay(doc, DateTime(2026, 8, 16)), isFalse);
    });

    test('일회성 파티 필드 묶음', () {
      final fields = PartySchedule.buildSingleFields(
        PartySingleSchedule(
          date: DateTime(2026, 8, 15),
          startTime: const TimeOfDay(hour: 20, minute: 0),
          endTime: const TimeOfDay(hour: 2, minute: 0),
          registrationDeadline: DateTime(2026, 8, 15, 18, 0),
        ),
      );
      expect(fields['scheduleType'], 'single');
      expect(fields['recurringSchedule'], isNull);
      final single = fields['singleSchedule'] as Map<String, dynamic>;
      expect(single['startTime'], '20:00');
      expect(single['endTime'], '02:00');
    });

    test('정기 파티 필드 묶음은 첫 회차를 partyDateTime으로 남기고 '
        '고정 recruitDeadlineAt은 남기지 않는다', () {
      var s = _schedule(startDate: DateTime(2026, 8, 1));
      s = s.applyTimesTo(['monday'], _slot(19, 0, 22, 0));
      final fields = PartySchedule.buildRecurringFields(
        s,
        now: DateTime(2026, 8, 1, 9, 0),
      );
      expect(fields['scheduleType'], 'recurring');
      expect(fields['singleSchedule'], isNull);
      expect(fields['recruitDeadlineAt'], isNull);
      expect(
        (fields['partyDateTime'] as Timestamp).toDate(),
        DateTime(2026, 8, 3, 19, 0),
      );
    });
  });
}

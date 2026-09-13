import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/party_early_bird.dart';
import 'package:party_app/models/party_early_bird_schedule.dart';
import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/utils/early_bird.dart';

/// 정기 파티 얼리버드 — 회차 시작 시각을 기준으로 종료 시각을 매번 새로
/// 계산하는 규칙을 고정한다.
///
/// 서버(functions/partySchedule.js의 resolveEarlyBirdEnd / partyCapacity.js의
/// computeAppliedFee)가 **같은 결과**를 내야 하며, 그쪽은
/// `npm run check:schedule` / `check:pricing`이 같은 케이스를 검증한다.
void main() {
  // 모든 검증의 기준 시각 — 2026-08-01(토) 오전 9:00.
  final kNow = DateTime(2026, 8, 1, 9, 0);

  DateTime day(int y, int m, int d, [int hh = 0, int mm = 0]) =>
      DateTime(y, m, d, hh, mm);

  /// [weekdays]에만 열리는 정기 파티 문서. 비우면 매일.
  Map<String, dynamic> recurringParty({
    required TimeOfDay start,
    required TimeOfDay end,
    Iterable<String>? weekdays,
    DateTime? startDate,
    DateTime? endDate,
    PartyEarlyBirdDeadlineRule? rule,
    int percent = 20,
    bool enabled = true,
    int price = 30000,
    PartyRecruitDeadlineRule deadline = const PartyRecruitDeadlineRule(
      mode: PartyDeadlineMode.none,
    ),
  }) {
    final keys = weekdays ?? kPartyWeekdayKeys;
    final schedule = PartyRecurringSchedule(
      startDate: startDate ?? day(2026, 7, 1),
      endDate: endDate,
      weekly: {
        for (final k in kPartyWeekdayKeys)
          k: PartyWeeklySlot(
            enabled: keys.contains(k),
            startTime: start,
            endTime: end,
          ),
      },
      deadlineRule: deadline,
    );
    return {
      'scheduleType': 'recurring',
      'recurringSchedule': schedule.toMap(),
      'pricingType': 'same',
      'price': price,
      'earlyBirdEnabled': enabled,
      'earlyBirdDiscountPercent': percent,
      if (rule != null) kEarlyBirdRuleField: rule.toMap(),
    };
  }

  group('규칙 → 종료 시각 계산', () {
    test('N일 전 + 시각 — 월요일 19시 파티는 금요일 23:59에 끝난다', () {
      const rule = PartyEarlyBirdDeadlineRule(
        mode: EarlyBirdDeadlineMode.daysBefore,
        days: 3,
        time: TimeOfDay(hour: 23, minute: 59),
      );
      // 2026-08-10은 월요일.
      expect(rule.resolve(day(2026, 8, 10, 19)), day(2026, 8, 7, 23, 59));
    });

    test('N시간 전 — 24시간 전', () {
      const rule = PartyEarlyBirdDeadlineRule(
        mode: EarlyBirdDeadlineMode.hoursBefore,
        hours: 24,
      );
      expect(rule.resolve(day(2026, 8, 7, 20)), day(2026, 8, 6, 20));
    });

    test('당일 특정 시각 — 당일 18:00', () {
      const rule = PartyEarlyBirdDeadlineRule(
        mode: EarlyBirdDeadlineMode.sameDayTime,
        time: TimeOfDay(hour: 18, minute: 0),
      );
      expect(rule.resolve(day(2026, 8, 7, 20)), day(2026, 8, 7, 18));
    });

    test('0일 전은 당일 종료 시각으로 처리된다', () {
      const rule = PartyEarlyBirdDeadlineRule(
        mode: EarlyBirdDeadlineMode.daysBefore,
        days: 0,
        time: TimeOfDay(hour: 12, minute: 0),
      );
      expect(rule.resolve(day(2026, 8, 7, 20)), day(2026, 8, 7, 12));
    });

    test('종료가 시작 이후로 계산되면 시작 시각까지만 적용된다', () {
      // 18시 시작 파티에 "당일 22시" → 시작 시각(18시)으로 당겨진다.
      const rule = PartyEarlyBirdDeadlineRule(
        mode: EarlyBirdDeadlineMode.sameDayTime,
        time: TimeOfDay(hour: 22, minute: 0),
      );
      expect(rule.resolve(day(2026, 8, 7, 18)), day(2026, 8, 7, 18));
    });
  });

  group('회차별 자동 계산', () {
    test('매주 금요일 20:00 · 2일 전 23:59 → 수요일 23:59', () {
      final data = recurringParty(
        start: const TimeOfDay(hour: 20, minute: 0),
        end: const TimeOfDay(hour: 23, minute: 0),
        weekdays: const ['friday'],
        rule: const PartyEarlyBirdDeadlineRule(
          mode: EarlyBirdDeadlineMode.daysBefore,
          days: 2,
          time: TimeOfDay(hour: 23, minute: 59),
        ),
      );
      // 기준 2026-08-01(토) → 다음 금요일은 8/7.
      expect(PartySchedule.startAt(data, now: kNow), day(2026, 8, 7, 20));
      expect(EarlyBird.endAt(data, now: kNow), day(2026, 8, 5, 23, 59));
    });

    test('이번 회차가 끝나면 다음 회차 기준으로 얼리버드가 다시 열린다', () {
      final data = recurringParty(
        start: const TimeOfDay(hour: 20, minute: 0),
        end: const TimeOfDay(hour: 23, minute: 0),
        weekdays: const ['friday'],
        rule: const PartyEarlyBirdDeadlineRule(
          mode: EarlyBirdDeadlineMode.daysBefore,
          days: 2,
          time: TimeOfDay(hour: 23, minute: 59),
        ),
      );
      // 8/5 23:59를 지나면 이번(8/7) 회차 얼리버드는 마감.
      final afterDeadline = day(2026, 8, 6, 10);
      expect(EarlyBird.isActive(data, now: afterDeadline), isFalse);
      // 예전에는 '다음 회차 얼리버드 진행 중'이라고만 했다 — "다음"이 며칠인지
      // 반복 규칙마다 달라 사용자가 알 수 없어서, 실제 회차 날짜로 바꿨다.
      // 8/7 회차가 마감됐으니 그 다음 금요일인 8/14가 최초 적용 회차다.
      expect(
        EarlyBird.statusLabel(data, now: afterDeadline),
        '8월 14일(금) 회차부터 얼리버드 할인',
      );

      // 8/7 회차가 끝난 뒤에는 다음 금요일(8/14) 기준으로 다시 열린다.
      final afterOccurrence = day(2026, 8, 8, 10);
      expect(
        PartySchedule.startAt(data, now: afterOccurrence),
        day(2026, 8, 14, 20),
      );
      expect(
        EarlyBird.endAt(data, now: afterOccurrence),
        day(2026, 8, 12, 23, 59),
      );
      expect(EarlyBird.isActive(data, now: afterOccurrence), isTrue);
    });

    test('매일 진행하는 파티 — 24시간 전 규칙', () {
      final data = recurringParty(
        start: const TimeOfDay(hour: 20, minute: 0),
        end: const TimeOfDay(hour: 23, minute: 0),
        rule: const PartyEarlyBirdDeadlineRule(
          mode: EarlyBirdDeadlineMode.hoursBefore,
          hours: 24,
        ),
      );
      // 기준 8/1 09:00 → 오늘 20:00 회차, 얼리버드는 어제 20:00에 이미 끝났다.
      expect(PartySchedule.startAt(data, now: kNow), day(2026, 8, 1, 20));
      expect(EarlyBird.endAt(data, now: kNow), day(2026, 7, 31, 20));
      expect(EarlyBird.isActive(data, now: kNow), isFalse);

      // 오늘 회차가 완전히 끝난 뒤에는 내일 회차 기준으로 다시 계산된다
      // (진행 중인 회차는 아직 '다음 회차'로 남는다 — 기존 일정 규칙 그대로).
      final afterTonight = day(2026, 8, 2, 1);
      expect(
        PartySchedule.startAt(data, now: afterTonight),
        day(2026, 8, 2, 20),
      );
      expect(EarlyBird.endAt(data, now: afterTonight), day(2026, 8, 1, 20));
    });

    test('자정을 넘겨 끝나는 파티(19:00~03:00)도 기준은 시작 시각이다', () {
      final data = recurringParty(
        start: const TimeOfDay(hour: 19, minute: 0),
        end: const TimeOfDay(hour: 3, minute: 0),
        weekdays: const ['saturday'],
        rule: const PartyEarlyBirdDeadlineRule(
          mode: EarlyBirdDeadlineMode.hoursBefore,
          hours: 3,
        ),
      );
      // 8/1은 토요일 → 오늘 19:00 시작(종료는 익일 03:00).
      expect(PartySchedule.startAt(data, now: kNow), day(2026, 8, 1, 19));
      // 종료(익일 03:00)가 아니라 시작(19:00)에서 3시간 전.
      expect(EarlyBird.endAt(data, now: kNow), day(2026, 8, 1, 16));
    });

    test('운영 종료일이 지나 남은 회차가 없으면 얼리버드도 적용되지 않는다', () {
      final data = recurringParty(
        start: const TimeOfDay(hour: 20, minute: 0),
        end: const TimeOfDay(hour: 23, minute: 0),
        endDate: day(2026, 7, 20),
        rule: const PartyEarlyBirdDeadlineRule(
          mode: EarlyBirdDeadlineMode.hoursBefore,
          hours: 1,
        ),
      );
      expect(EarlyBird.endAt(data, now: kNow), isNull);
      expect(EarlyBird.isActive(data, now: kNow), isFalse);
      expect(EarlyBird.effectivePrice(30000, data, now: kNow), 30000);
    });
  });

  group('가격 적용', () {
    final rule = const PartyEarlyBirdDeadlineRule(
      mode: EarlyBirdDeadlineMode.daysBefore,
      days: 2,
      time: TimeOfDay(hour: 23, minute: 59),
    );

    test('마감 전이면 할인가, 마감 후면 정상가', () {
      final data = recurringParty(
        start: const TimeOfDay(hour: 20, minute: 0),
        end: const TimeOfDay(hour: 23, minute: 0),
        weekdays: const ['friday'],
        rule: rule,
        percent: 20,
      );
      // 8/5 23:59 이전 → 30,000 → 24,000
      expect(EarlyBird.effectivePrice(30000, data, now: kNow), 24000);
      // 8/6 → 이번 회차 얼리버드 마감 → 정상가
      expect(
        EarlyBird.effectivePrice(30000, data, now: day(2026, 8, 6, 10)),
        30000,
      );
    });

    test('무료 파티에는 할인이 적용되지 않는다', () {
      final data = recurringParty(
        start: const TimeOfDay(hour: 20, minute: 0),
        end: const TimeOfDay(hour: 23, minute: 0),
        rule: rule,
      );
      expect(EarlyBird.effectivePrice(0, data, now: kNow), 0);
    });
  });

  group('표시 라벨', () {
    test('며칠 남았으면 D-n, 오늘 끝나면 시각 표시', () {
      final data = recurringParty(
        start: const TimeOfDay(hour: 20, minute: 0),
        end: const TimeOfDay(hour: 23, minute: 0),
        weekdays: const ['friday'],
        rule: const PartyEarlyBirdDeadlineRule(
          mode: EarlyBirdDeadlineMode.daysBefore,
          days: 2,
          time: TimeOfDay(hour: 23, minute: 59),
        ),
      );
      // 8/1 기준 종료는 8/5 → D-4
      expect(EarlyBird.statusLabel(data, now: kNow), '얼리버드 D-4');
      // 8/5 당일 → '오늘 23:59 마감'
      expect(
        EarlyBird.statusLabel(data, now: day(2026, 8, 5, 9)),
        '얼리버드 오늘 23:59 마감',
      );
    });

    test('마감 임박(24시간 이내)을 구분한다', () {
      final data = recurringParty(
        start: const TimeOfDay(hour: 20, minute: 0),
        end: const TimeOfDay(hour: 23, minute: 0),
        rule: const PartyEarlyBirdDeadlineRule(
          mode: EarlyBirdDeadlineMode.hoursBefore,
          hours: 2,
        ),
      );
      // 매일 20시 파티 · 2시간 전 종료 → 오늘 18:00. 09:00 기준 9시간 남음.
      expect(EarlyBird.isClosingSoon(data, now: kNow), isTrue);
    });

    test('얼리버드를 안 쓰는 파티는 빈 라벨', () {
      final data = recurringParty(
        start: const TimeOfDay(hour: 20, minute: 0),
        end: const TimeOfDay(hour: 23, minute: 0),
        enabled: false,
      );
      expect(EarlyBird.statusLabel(data, now: kNow), '');
    });
  });

  group('기존 일회성 파티 회귀 방지', () {
    Map<String, dynamic> oneOff(DateTime endAt) => {
      'scheduleType': 'single',
      'partyDateTime': Timestamp.fromDate(day(2026, 8, 20, 20)),
      'earlyBirdEnabled': true,
      'earlyBirdDiscountPercent': 10,
      'earlyBirdEndAt': Timestamp.fromDate(endAt),
    };

    test('저장된 고정 종료 시각을 그대로 쓴다', () {
      final data = oneOff(day(2026, 8, 15, 23, 59));
      expect(EarlyBird.endAt(data, now: kNow), day(2026, 8, 15, 23, 59));
      expect(EarlyBird.isActive(data, now: kNow), isTrue);
      expect(EarlyBird.effectivePrice(30000, data, now: kNow), 27000);
    });

    test('종료 시각이 지나면 정상가', () {
      final data = oneOff(day(2026, 7, 15, 23, 59));
      expect(EarlyBird.isActive(data, now: kNow), isFalse);
      expect(EarlyBird.effectivePrice(30000, data, now: kNow), 30000);
      expect(EarlyBird.statusLabel(data, now: kNow), '얼리버드 마감');
    });

    test('규칙이 없는 예전 정기 파티는 earlyBirdEndAt으로 폴백한다', () {
      final data = recurringParty(
        start: const TimeOfDay(hour: 20, minute: 0),
        end: const TimeOfDay(hour: 23, minute: 0),
      )..['earlyBirdEndAt'] = Timestamp.fromDate(day(2026, 8, 15, 23, 59));
      expect(EarlyBird.endAt(data, now: kNow), day(2026, 8, 15, 23, 59));
    });
  });

  group('저장/복원/검증', () {
    test('정기 파티는 규칙만, 일회성은 고정 시각만 저장한다', () {
      const eb = PartyEarlyBird(
        enabled: true,
        percent: 20,
        beforeStartRule: PartyEarlyBirdDeadlineRule(
          mode: EarlyBirdDeadlineMode.daysBefore,
          days: 3,
          time: TimeOfDay(hour: 23, minute: 59),
        ),
      );
      final recurringMap = eb.toMapFor(isRecurring: true);
      expect(recurringMap['earlyBirdEnabled'], isTrue);
      expect(recurringMap['earlyBirdEndAt'], isNull);
      expect(recurringMap[kEarlyBirdRuleField], {
        'mode': 'daysBefore',
        'days': 3,
        'time': '23:59',
      });

      final oneOff = PartyEarlyBird(
        enabled: true,
        percent: 20,
        endDate: day(2026, 8, 15),
        endTime: const TimeOfDay(hour: 23, minute: 59),
      ).toMapFor(isRecurring: false);
      expect(oneOff['earlyBirdEndAt'], isNotNull);
      expect(oneOff[kEarlyBirdRuleField], isNull);
    });

    test('문서에서 규칙을 그대로 복원한다', () {
      final restored = PartyEarlyBird.fromMap({
        'earlyBirdEnabled': true,
        'earlyBirdDiscountPercent': 15,
        kEarlyBirdRuleField: {'mode': 'hoursBefore', 'hours': 24},
      }, now: kNow);
      expect(restored.enabled, isTrue);
      expect(restored.percent, 15);
      expect(restored.beforeStartRule.mode, EarlyBirdDeadlineMode.hoursBefore);
      expect(restored.beforeStartRule.hours, 24);
    });

    test('임시저장에 규칙이 함께 남고 복원된다', () {
      const eb = PartyEarlyBird(
        enabled: true,
        percent: 20,
        beforeStartRule: PartyEarlyBirdDeadlineRule(
          mode: EarlyBirdDeadlineMode.sameDayTime,
          time: TimeOfDay(hour: 18, minute: 0),
        ),
      );
      final restored = PartyEarlyBird.fromDraftMap(eb.toDraftMap());
      expect(restored.beforeStartRule.mode, EarlyBirdDeadlineMode.sameDayTime);
      expect(
        restored.beforeStartRule.time,
        const TimeOfDay(hour: 18, minute: 0),
      );
    });

    test('정기 → 일회성 복사는 종료 시각을 비워 새로 정하게 한다', () {
      const eb = PartyEarlyBird(
        enabled: true,
        percent: 20,
        beforeStartRule: PartyEarlyBirdDeadlineRule(
          mode: EarlyBirdDeadlineMode.daysBefore,
          days: 3,
        ),
      );
      final copied = eb.toOneOffTemplate();
      expect(copied.enabled, isTrue);
      expect(copied.percent, 20);
      expect(copied.endAt, isNull);
      expect(
        copied.validate(isFree: false, now: kNow),
        '얼리버드 종료일과 시간을 선택해주세요.',
      );
    });

    test('얼리버드가 모집 마감보다 늦으면 저장을 막는다', () {
      const eb = PartyEarlyBird(
        enabled: true,
        percent: 20,
        beforeStartRule: PartyEarlyBirdDeadlineRule(
          mode: EarlyBirdDeadlineMode.hoursBefore,
          hours: 1,
        ),
      );
      final error = eb.validate(
        isFree: false,
        isRecurring: true,
        now: kNow,
        occurrenceStart: day(2026, 8, 7, 20),
        // 모집은 3시간 전에 끝나는데 얼리버드는 1시간 전까지 → 충돌.
        recruitDeadline: day(2026, 8, 7, 17),
      );
      expect(error, contains('모집 마감'));
    });

    test('정기 파티는 고정 종료 시각이 없어도 유효하다', () {
      const eb = PartyEarlyBird(enabled: true, percent: 20);
      expect(eb.validate(isFree: false, isRecurring: true, now: kNow), isNull);
      expect(eb.isEffectiveFor(isRecurring: true), isTrue);
      expect(eb.isEffectiveFor(isRecurring: false), isFalse);
    });
  });

  // ── 최초 적용 회차 계산 ───────────────────────────────────────────────────
  //
  // "다음 회차부터"처럼 상대적인 표현 대신 **실제 회차 날짜**를 계산한다.
  // 판정 기준은 서버 computeAppliedFee와 같다 — 회차 시작에 규칙을 적용한
  // 종료 시각이 지금보다 뒤면 그 회차는 할인가로 결제된다.
  group('얼리버드 최초 적용 회차', () {
    // 3일 전 23:59 마감 규칙 — 이 그룹 전체가 공유한다.
    const days3 = PartyEarlyBirdDeadlineRule(
      mode: EarlyBirdDeadlineMode.daysBefore,
      days: 3,
      time: TimeOfDay(hour: 23, minute: 59),
    );

    test('매일 파티 — 지금 기준 3일 뒤 회차부터 적용된다', () {
      // 기준: 8/1(토) 09:00. 3일 전 23:59가 지금보다 뒤여야 하므로
      // 8/4(화) 회차의 마감은 8/1 23:59 → 아직 안 지났다.
      final p = recurringParty(
        start: const TimeOfDay(hour: 19, minute: 0),
        end: const TimeOfDay(hour: 22, minute: 0),
        rule: days3,
      );
      final first = EarlyBird.firstDiscountedOccurrenceStart(p, now: kNow);
      expect(first, day(2026, 8, 4, 19));
    });

    test('화·목 파티 — 실제로 열리는 요일만 후보가 된다', () {
      // 8/1(토) 기준. 화=8/4(마감 8/1 23:59, 유효) → 8/4가 최초.
      final p = recurringParty(
        start: const TimeOfDay(hour: 20, minute: 0),
        end: const TimeOfDay(hour: 23, minute: 0),
        weekdays: const ['tuesday', 'thursday'],
        rule: days3,
      );
      final first = EarlyBird.firstDiscountedOccurrenceStart(p, now: kNow);
      expect(first, day(2026, 8, 4, 20));
      expect(first!.weekday, DateTime.tuesday);
    });

    test('주말 파티 — 토·일만 후보가 되고 평일은 건너뛴다', () {
      // 8/1(토) 09:00 기준. 8/1 토요일 회차는 마감이 7/29 23:59로 이미 지났고,
      // 8/2(일) 회차도 7/30 23:59로 지났다 → 8/8(토)이 최초(마감 8/5 23:59).
      final p = recurringParty(
        start: const TimeOfDay(hour: 18, minute: 0),
        end: const TimeOfDay(hour: 21, minute: 0),
        weekdays: const ['saturday', 'sunday'],
        rule: days3,
      );
      final first = EarlyBird.firstDiscountedOccurrenceStart(p, now: kNow);
      expect(first, day(2026, 8, 8, 18));
      expect(first!.weekday, DateTime.saturday);
    });

    test('마감이 아주 이른 규칙(30일 전)도 실제 회차를 찾아낸다', () {
      // 기본 지평(60일)으로는 못 찾을 수 있어 180일을 본다.
      const days30 = PartyEarlyBirdDeadlineRule(
        mode: EarlyBirdDeadlineMode.daysBefore,
        days: 30,
        time: TimeOfDay(hour: 23, minute: 59),
      );
      final p = recurringParty(
        start: const TimeOfDay(hour: 19, minute: 0),
        end: const TimeOfDay(hour: 22, minute: 0),
        weekdays: const ['saturday'],
        rule: days30,
      );
      final first = EarlyBird.firstDiscountedOccurrenceStart(p, now: kNow);
      expect(first, isNotNull);
      expect(first!.weekday, DateTime.saturday);
      // 마감이 지금보다 뒤여야 한다 = 실제로 할인이 붙는 회차다.
      expect(days30.resolve(first).isAfter(kNow), isTrue);
    });

    test('선택한 회차가 실제로 할인가로 계산된다 — 표시와 결제가 어긋나지 않게', () {
      final p = recurringParty(
        start: const TimeOfDay(hour: 19, minute: 0),
        end: const TimeOfDay(hour: 22, minute: 0),
        rule: days3,
        percent: 20,
        price: 30000,
      );
      final first = EarlyBird.firstDiscountedOccurrenceStart(p, now: kNow)!;
      final end = resolveEarlyBirdEndAt(p, now: kNow, occurrenceStart: first);
      expect(end!.isAfter(kNow), isTrue);
    });

    test('그 직전 회차는 이미 마감이라 후보가 아니다', () {
      final p = recurringParty(
        start: const TimeOfDay(hour: 19, minute: 0),
        end: const TimeOfDay(hour: 22, minute: 0),
        rule: days3,
      );
      final first = EarlyBird.firstDiscountedOccurrenceStart(p, now: kNow)!;
      final prev = first.subtract(const Duration(days: 1));
      expect(
        days3.resolve(prev).isAfter(kNow),
        isFalse,
        reason: '직전 회차가 아직 유효하면 그쪽이 최초여야 한다',
      );
    });

    test('운영이 끝난 정기 파티는 null — 남은 회차가 없다', () {
      final p = recurringParty(
        start: const TimeOfDay(hour: 19, minute: 0),
        end: const TimeOfDay(hour: 22, minute: 0),
        rule: days3,
        endDate: day(2026, 7, 20),
      );
      expect(EarlyBird.firstDiscountedOccurrenceStart(p, now: kNow), isNull);
    });

    test('★ 단일 날짜 파티는 null — 기존 동작 그대로 둔다', () {
      final single = {
        'scheduleType': 'single',
        'partyDateTime': Timestamp.fromDate(day(2026, 8, 20, 19)),
        'price': 30000,
        'earlyBirdEnabled': true,
        'earlyBirdDiscountPercent': 20,
        kEarlyBirdRuleField: days3.toMap(),
      };
      expect(
        EarlyBird.firstDiscountedOccurrenceStart(single, now: kNow),
        isNull,
      );
    });

    test('얼리버드를 안 쓰는 파티는 null', () {
      final p = recurringParty(
        start: const TimeOfDay(hour: 19, minute: 0),
        end: const TimeOfDay(hour: 22, minute: 0),
        rule: days3,
        enabled: false,
      );
      expect(EarlyBird.firstDiscountedOccurrenceStart(p, now: kNow), isNull);
    });

    test('고정 날짜 방식(규칙 없음)은 null — 회차별로 달라지지 않는다', () {
      final p = recurringParty(
        start: const TimeOfDay(hour: 19, minute: 0),
        end: const TimeOfDay(hour: 22, minute: 0),
      );
      expect(EarlyBird.firstDiscountedOccurrenceStart(p, now: kNow), isNull);
    });
  });

  group('상태 라벨 문구', () {
    const days3 = PartyEarlyBirdDeadlineRule(
      mode: EarlyBirdDeadlineMode.daysBefore,
      days: 3,
      time: TimeOfDay(hour: 23, minute: 59),
    );

    test('★ 적용 전이면 실제 날짜와 요일이 들어간다', () {
      final p = recurringParty(
        start: const TimeOfDay(hour: 18, minute: 0),
        end: const TimeOfDay(hour: 21, minute: 0),
        weekdays: const ['saturday', 'sunday'],
        rule: days3,
      );
      final label = EarlyBird.statusLabel(p, now: kNow);
      expect(label, '8월 8일(토) 회차부터 얼리버드 할인');
    });

    test("★ '다음 회차' 같은 상대 표현이 남아 있지 않다", () {
      final p = recurringParty(
        start: const TimeOfDay(hour: 18, minute: 0),
        end: const TimeOfDay(hour: 21, minute: 0),
        weekdays: const ['saturday', 'sunday'],
        rule: days3,
      );
      final label = EarlyBird.statusLabel(p, now: kNow);
      expect(label.contains('다음 회차'), isFalse);
      expect(label.contains('회차 이후'), isFalse);
    });

    test('해가 바뀌는 회차는 연도까지 붙는다', () {
      // 토요일만 열리는 파티. 12/31 10:00에는 1/2(토) 회차의 마감(12/30 23:59)이
      // 이미 지났으므로, 그다음 토요일인 2027-01-09가 최초 적용 회차다.
      final now = DateTime(2026, 12, 31, 10);
      final p = recurringParty(
        start: const TimeOfDay(hour: 19, minute: 0),
        end: const TimeOfDay(hour: 22, minute: 0),
        weekdays: const ['saturday'],
        startDate: day(2026, 12, 1),
        rule: days3,
      );
      final label = EarlyBird.statusLabel(p, now: now);
      expect(label, '2027년 1월 9일(토) 회차부터 얼리버드 할인');
    });

    test('얼리버드가 지금 유효하면 기존 D-day 문구 그대로다', () {
      // 당일 23:00 마감 규칙이면 8/1 09:00 시점에 이번 회차가 아직 유효하다.
      final p = recurringParty(
        start: const TimeOfDay(hour: 19, minute: 0),
        end: const TimeOfDay(hour: 22, minute: 0),
        rule: const PartyEarlyBirdDeadlineRule(
          mode: EarlyBirdDeadlineMode.sameDayTime,
          time: TimeOfDay(hour: 23, minute: 0),
        ),
      );
      expect(EarlyBird.isActive(p, now: kNow), isTrue);
      final label = EarlyBird.statusLabel(p, now: kNow);
      expect(label, startsWith('얼리버드'));
      expect(label.contains('회차부터'), isFalse);
    });

    test('★ 단일 날짜 파티의 마감 문구는 바뀌지 않았다', () {
      final single = {
        'scheduleType': 'single',
        'partyDateTime': Timestamp.fromDate(day(2026, 8, 20, 19)),
        'price': 30000,
        'earlyBirdEnabled': true,
        'earlyBirdDiscountPercent': 20,
        'earlyBirdEndAt': Timestamp.fromDate(day(2026, 7, 20, 23, 59)),
      };
      expect(EarlyBird.statusLabel(single, now: kNow), '얼리버드 마감');
    });
  });
}

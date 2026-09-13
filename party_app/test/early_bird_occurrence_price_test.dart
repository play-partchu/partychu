// 얼리버드 — **고른 회차** 기준으로 판정하는지 고정한다.
//
// 실제로 어긋났던 케이스(2026-08-21): 상세는 '8월 24일(월) 회차부터 얼리버드
// 할인'이라고 정확히 계산하는데, 8/25 회차를 골라 신청 화면에 들어가면 참가비가
// 정상가 그대로 떴다. 상세 안내는 회차를 순회해 판정([firstDiscountedOccurrenceStart])
// 하는 반면, 참가비·신청 금액은 회차를 넘기지 않아 "지금 기준 다음 회차"(8/21)의
// 이미 끝난 얼리버드로 판정했기 때문이다.
//
// 서버(functions/partyCapacity.js computeAppliedFee)는 이미 occurrence를 받아
// 회차 기준으로 계산한다 — 그래서 예약금 정책이 걸린 파티는 클라이언트가 보낸
// amounts가 서버 계산과 달라 assertClientAmountMatches에 걸려 신청 자체가 막혔다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/party_early_bird_schedule.dart';
import 'package:party_app/models/party_pricing.dart';
import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/utils/early_bird.dart';

void main() {
  // 스샷 케이스 그대로 — 2026-08-21(금) 오전 10:00, 매일 19:00 시작,
  // 참가비 20,000원, 얼리버드 20%, '파티 시작 3일 전 23:59까지'.
  final now = DateTime(2026, 8, 21, 10, 0);

  const rule = PartyEarlyBirdDeadlineRule(
    mode: EarlyBirdDeadlineMode.daysBefore,
    days: 3,
    time: TimeOfDay(hour: 23, minute: 59),
  );

  final data = <String, dynamic>{
    'scheduleType': 'recurring',
    'recurringSchedule': PartyRecurringSchedule(
      startDate: DateTime(2026, 7, 1),
      weekly: {
        for (final k in kPartyWeekdayKeys)
          k: const PartyWeeklySlot(
            enabled: true,
            startTime: TimeOfDay(hour: 19, minute: 0),
            endTime: TimeOfDay(hour: 23, minute: 0),
          ),
      },
    ).toMap(),
    'pricingType': 'same',
    'price': 20000,
    'earlyBirdEnabled': true,
    'earlyBirdDiscountPercent': 20,
    kEarlyBirdRuleField: rule.toMap(),
  };

  DateTime occ(int day) => DateTime(2026, 8, day, 19, 0);

  /// 신청 흐름이 서버로 보내는 예상 금액과 **같은 식**
  /// (party_detail_screen.dart `_startApplyFlow`의 expectedFee).
  int applyExpectedFee(DateTime? occurrenceStart) => EarlyBird.effectivePrice(
    PartyPricing.fromMap(data).displayPrice,
    data,
    now: now,
    occurrenceStart: occurrenceStart,
  );

  group('상세 안내가 말한 시작 회차', () {
    test('오늘 기준 얼리버드가 적용되는 첫 회차는 8/24다', () {
      expect(EarlyBird.firstDiscountedOccurrenceStart(data, now: now), occ(24));
      expect(EarlyBird.statusLabel(data, now: now), '8월 24일(월) 회차부터 얼리버드 할인');
    });
  });

  group('경계 — 시작일 포함(>=)', () {
    test('8/23(하루 전) → 할인 없음, 20,000원', () {
      expect(
        EarlyBird.isActive(data, now: now, occurrenceStart: occ(23)),
        isFalse,
      );
      expect(applyExpectedFee(occ(23)), 20000);
    });

    test('8/24(시작일 당일) → 할인 적용, 16,000원', () {
      expect(
        EarlyBird.isActive(data, now: now, occurrenceStart: occ(24)),
        isTrue,
      );
      expect(applyExpectedFee(occ(24)), 16000);
    });

    test('8/25(시작일 이후) → 할인 적용, 16,000원 — 원래 20,000원이 뜨던 버그', () {
      expect(
        EarlyBird.isActive(data, now: now, occurrenceStart: occ(25)),
        isTrue,
      );
      expect(applyExpectedFee(occ(25)), 16000);
    });

    test('8/26 이후 회차도 계속 할인된다', () {
      for (final d in [26, 27, 30]) {
        expect(applyExpectedFee(occ(d)), 16000, reason: '8/$d');
      }
    });
  });

  group('상세 안내와 실제 금액이 같은 판정을 쓴다', () {
    test('첫 할인 회차 이후 모든 회차에서 안내와 금액이 일치한다', () {
      final first = EarlyBird.firstDiscountedOccurrenceStart(data, now: now)!;
      for (var d = 21; d <= 30; d++) {
        final start = occ(d);
        final announced = !start.isBefore(first); // 안내 기준(시작일 포함)
        final charged = applyExpectedFee(start) < 20000; // 실제 금액 기준
        expect(charged, announced, reason: '8/$d — 안내와 금액이 어긋난다');
      }
    });
  });

  group('기존 동작 유지', () {
    test('일회성 파티는 회차를 넘기든 말든 예전과 같다', () {
      final once = <String, dynamic>{
        'pricingType': 'same',
        'price': 20000,
        'earlyBirdEnabled': true,
        'earlyBirdDiscountPercent': 20,
        kEarlyBirdRuleField: rule.toMap(),
        'partyDateTime': null,
        'startDateTime': DateTime(2026, 8, 30, 19).toIso8601String(),
      };
      expect(
        EarlyBird.effectivePrice(20000, once, now: now),
        EarlyBird.effectivePrice(
          20000,
          once,
          now: now,
          occurrenceStart: DateTime(2026, 8, 30, 19),
        ),
      );
    });

    test('얼리버드가 꺼진 파티는 어느 회차든 정상가', () {
      final off = Map<String, dynamic>.from(data)..['earlyBirdEnabled'] = false;
      expect(
        EarlyBird.effectivePrice(
          20000,
          off,
          now: now,
          occurrenceStart: occ(25),
        ),
        20000,
      );
    });

    test('무료 파티는 할인 대상이 아니다', () {
      expect(
        EarlyBird.effectivePrice(0, data, now: now, occurrenceStart: occ(25)),
        0,
      );
    });

    test('회차 마감(이미 지난 회차 기준)은 할인되지 않는다 — 기존 마감 조건 유지', () {
      // 8/21 회차의 얼리버드는 8/18 23:59에 이미 끝났다.
      expect(
        EarlyBird.isActive(data, now: now, occurrenceStart: occ(21)),
        isFalse,
      );
      expect(applyExpectedFee(occ(21)), 20000);
    });
  });

  group('한국시간 날짜 경계', () {
    test('경계 시각 직전/직후에 하루가 밀리지 않는다', () {
      // 8/24 회차의 얼리버드 종료는 8/21 23:59.
      final justBefore = DateTime(2026, 8, 21, 23, 58);
      final justAfter = DateTime(2026, 8, 22, 0, 0);
      expect(
        EarlyBird.isActive(data, now: justBefore, occurrenceStart: occ(24)),
        isTrue,
      );
      expect(
        EarlyBird.isActive(data, now: justAfter, occurrenceStart: occ(24)),
        isFalse,
      );
      // 그 순간 첫 할인 회차는 하루 뒤로 밀린다 — 8/25.
      expect(
        EarlyBird.firstDiscountedOccurrenceStart(data, now: justAfter),
        occ(25),
      );
    });
  });
}

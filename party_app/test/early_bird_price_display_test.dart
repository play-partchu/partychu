// 신청 화면에서 얼리버드 할인이 **보이는지** 확인한다.
//
// 회차 기준 판정은 early_bird_occurrence_price_test.dart가 이미 고정한다.
// 여기서 보는 것은 "그 결과가 화면에 정상가 취소선 + 할인가로 나타나는가"다.
// 예전에는 할인가 16,000원만 덩그러니 떠서 할인된 금액인지 알 수 없었다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/party_early_bird_schedule.dart';
import 'package:party_app/models/party_pricing.dart';
import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/models/payment_order_summary.dart';
import 'package:party_app/models/payment_policy.dart';
import 'package:party_app/screens/payment_method_screen.dart';
import 'package:party_app/utils/early_bird.dart';
import 'package:party_app/widgets/early_bird_price_line.dart';
import 'package:party_app/widgets/partychu_ui.dart';

void main() {
  // 스샷 케이스 — 2026-08-21(금) 10:00, 매일 19:00 시작, 20,000원,
  // 얼리버드 20%, '파티 시작 3일 전 23:59까지'.
  final now = DateTime(2026, 8, 21, 10, 0);
  const rule = PartyEarlyBirdDeadlineRule(
    mode: EarlyBirdDeadlineMode.daysBefore,
    days: 3,
    time: TimeOfDay(hour: 23, minute: 59),
  );

  Map<String, dynamic> party({int price = 20000, bool enabled = true}) => {
    'title': '금요일 살사 나이트',
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
    'price': price,
    'earlyBirdEnabled': enabled,
    'earlyBirdDiscountPercent': 20,
    kEarlyBirdRuleField: rule.toMap(),
  };

  DateTime occ(int day) => DateTime(2026, 8, day, 19, 0);

  /// party_detail_screen의 `_choosePayment`가 요약을 만드는 방식 그대로 —
  /// 표시 여부를 새로 계산하지 않고 정본(EarlyBird)의 결과만 쓴다.
  PaymentOrderSummary summaryFor(Map<String, dynamic> data, DateTime? start) {
    final original = PartyPricing.fromMap(data).displayPrice;
    final fee = EarlyBird.effectivePrice(
      original,
      data,
      now: now,
      occurrenceStart: start,
    );
    final earlyBirdOn = EarlyBird.isActive(
      data,
      now: now,
      occurrenceStart: start,
    );
    final shows = earlyBirdOn && EarlyBirdPriceLine.worthShowing(original, fee);
    return PaymentOrderSummary.party(
      partyName: data['title'] as String,
      dateText: '8월 25일(화) 오후 7:00',
      peopleText: '1명',
      fee: fee,
      originalFee: shows ? original : null,
      discountLabel: shows ? '얼리버드' : null,
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    PaymentOrderSummary summary, {
    PaymentBreakdown? breakdown,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        // hostId는 "돈을 받을 호스트" — 무통장입금을 열지 말지 판정하는 값이다.
        // 이 테스트가 보는 것은 금액 표기라, 계좌 조회가 실패해도(=무통장입금이
        // 목록에서 빠져도) 결과가 달라지지 않는 빈 값을 넘긴다.
        home: PaymentMethodScreen(
          summary: summary,
          breakdown: breakdown,
          hostId: '',
        ),
      ),
    );
    await tester.pump();
  }

  /// 해당 문구를 그리는 Text 위젯의 스타일.
  TextStyle styleOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text).first).style!;

  group('★ 스샷 케이스 — 8/25 회차', () {
    testWidgets('정상가 20,000원 취소선 + 얼리버드 배지 + 할인가 16,000원', (tester) async {
      final summary = summaryFor(party(), occ(25));

      // 전제: 정본이 할인을 인정한 상태여야 한다.
      expect(summary.amount, 16000);
      expect(summary.originalAmount, 20000);
      expect(summary.hasDiscount, isTrue);

      await pumpScreen(tester, summary);

      // 정상가 — 회색 + 취소선
      expect(find.text('20,000원'), findsOneWidget);
      final original = styleOf(tester, '20,000원');
      expect(original.decoration, TextDecoration.lineThrough);
      expect(original.color, Colors.black38);

      // 얼리버드 배지
      expect(find.text('얼리버드'), findsOneWidget);

      // 최종 할인가 — 굵은 핑크
      expect(find.text('16,000원'), findsOneWidget);
      final discounted = styleOf(tester, '16,000원');
      expect(discounted.color, PartyChuColors.primary);
      expect(discounted.fontWeight, FontWeight.w800);
      expect(discounted.decoration, isNot(TextDecoration.lineThrough));
    });
  });

  group('얼리버드 미적용', () {
    testWidgets('8/23 회차 — 정상가 하나만, 취소선도 배지도 없다', (tester) async {
      final summary = summaryFor(party(), occ(23));
      expect(summary.amount, 20000);
      expect(summary.hasDiscount, isFalse);

      await pumpScreen(tester, summary);

      expect(find.text('20,000원'), findsOneWidget);
      expect(
        styleOf(tester, '20,000원').decoration,
        isNot(TextDecoration.lineThrough),
      );
      expect(find.text('얼리버드'), findsNothing);
      expect(find.text('16,000원'), findsNothing);
    });

    testWidgets('얼리버드가 꺼진 파티도 정상가 하나만', (tester) async {
      final summary = summaryFor(party(enabled: false), occ(25));
      expect(summary.hasDiscount, isFalse);
      await pumpScreen(tester, summary);
      expect(find.text('얼리버드'), findsNothing);
    });
  });

  group('무료 파티는 기존 표시 유지', () {
    testWidgets('참가비 0원이면 "무료"', (tester) async {
      final summary = summaryFor(party(price: 0), occ(25));
      expect(summary.amount, 0);
      expect(summary.hasDiscount, isFalse);

      await pumpScreen(tester, summary);
      expect(find.text('무료'), findsOneWidget);
      expect(find.text('얼리버드'), findsNothing);
    });
  });

  group('결제 요약(금액 분해 카드)에도 같이 보인다', () {
    testWidgets('예약금 파티 — 총액 줄이 20,000원 취소선 → 16,000원', (tester) async {
      final summary = summaryFor(party(), occ(25));
      const policy = PaymentPolicy(
        mode: PaymentMode.partial,
        upfrontType: UpfrontType.percentage,
        upfrontPercent: 50,
      );
      final breakdown = PaymentBreakdown.of(policy, summary.amount);

      await pumpScreen(tester, summary, breakdown: breakdown);

      // 주문 정보 카드 + 금액 분해 카드 = 두 곳에 같은 표기.
      expect(find.text('20,000원'), findsNWidgets(2));
      expect(find.text('얼리버드'), findsNWidgets(2));
      expect(find.text('16,000원'), findsNWidgets(2));
      // 예약금·잔금은 이미 할인된 총액에서 갈라져 나온 값이라 취소선이
      // 붙지 않는다 — 붙이면 두 번 할인된 것처럼 읽힌다.
      expect(find.text('8,000원'), findsNWidgets(2));
    });
  });

  group('차수·패키지', () {
    testWidgets('차수 합계도 정상가 대비 할인가로 비교된다', (tester) async {
      // PartyRoundOffers가 회차 기준으로 계산해둔 두 합계를 그대로 받은 상황.
      final summary = PaymentOrderSummary.party(
        partyName: '2차까지 가는 파티',
        dateText: '8월 25일(화) 오후 7:00',
        peopleText: '1명',
        fee: 42000, // effectiveFee 합계
        originalFee: 50000, // fee 합계
        discountLabel: '얼리버드',
      );
      expect(summary.hasDiscount, isTrue);

      await pumpScreen(tester, summary);
      expect(find.text('50,000원'), findsOneWidget);
      expect(styleOf(tester, '50,000원').decoration, TextDecoration.lineThrough);
      expect(find.text('42,000원'), findsOneWidget);
      expect(find.text('얼리버드'), findsOneWidget);
    });

    testWidgets('그 차수에 얼리버드가 없으면 두 합계가 같아 표시하지 않는다', (tester) async {
      expect(EarlyBirdPriceLine.worthShowing(50000, 50000), isFalse);
      final summary = PaymentOrderSummary.party(
        partyName: '할인 없는 파티',
        dateText: '8월 25일(화) 오후 7:00',
        peopleText: '1명',
        fee: 50000,
      );
      expect(summary.hasDiscount, isFalse);
      await pumpScreen(tester, summary);
      expect(find.text('얼리버드'), findsNothing);
    });
  });
}

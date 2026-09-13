import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/models/host_sales_stats.dart';
import 'package:party_app/models/payment_method.dart';
import 'package:party_app/models/payment_status.dart';

/// 호스트 판매 통계 집계 — **돈 계산**을 못 박는다.
///
/// 여기서 지키는 것 두 가지:
///   ① 어떤 상태를 매출로 세는지(확정 / 미확정 / 제외)
///   ② 실제 확정 금액이 무엇인지 — 예약금 결제는 총액이 아니라 받은 돈이다
void main() {
  PaymentInfo payment(
    PaymentStatus status, {
    int? amount,
    PaymentMethod method = PaymentMethod.bankTransfer,
  }) => PaymentInfo(
    method: method,
    status: status,
    extra: {if (amount != null) 'amount': amount},
  );

  group('SalesEntry.judge — 상태별 매출 포함 기준', () {
    test('결제완료는 확정 수익이다', () {
      final r = SalesEntry.judge(
        payment: payment(PaymentStatus.paid, amount: 30000),
        lifecycleClosed: false,
        amountsSnapshot: null,
        fallbackTotal: 30000,
      );
      expect(r.state, SalesRevenueState.confirmed);
      expect(r.confirmed, 30000);
    });

    test('입금대기·승인대기·현장결제 예정은 미확정이라 총수익에 안 들어간다', () {
      for (final s in [
        PaymentStatus.awaitingApproval,
        PaymentStatus.awaitingDeposit,
        PaymentStatus.depositPending,
        PaymentStatus.onSiteScheduled,
      ]) {
        final r = SalesEntry.judge(
          payment: payment(s, amount: 30000),
          lifecycleClosed: false,
          amountsSnapshot: null,
          fallbackTotal: 30000,
        );
        expect(r.state, SalesRevenueState.pending, reason: s.key);
        expect(r.confirmed, 0, reason: s.key);
        // 총액은 살아 있다 — 목록에서 "얼마짜리 예약인지"는 보여야 한다.
        expect(r.total, 30000, reason: s.key);
      }
    });

    test('결제취소·환불완료·기한만료는 제외다', () {
      for (final s in [
        PaymentStatus.cancelled,
        PaymentStatus.refunded,
        PaymentStatus.expired,
      ]) {
        final r = SalesEntry.judge(
          payment: payment(s, amount: 30000),
          lifecycleClosed: false,
          amountsSnapshot: null,
          fallbackTotal: 30000,
        );
        expect(r.state, SalesRevenueState.excluded, reason: s.key);
        expect(r.confirmed, 0, reason: s.key);
      }
    });

    test('진행 상태가 끝났으면 결제완료라도 제외다 (호스트 취소·거절)', () {
      final r = SalesEntry.judge(
        payment: payment(PaymentStatus.paid, amount: 30000),
        lifecycleClosed: true,
        amountsSnapshot: null,
        fallbackTotal: 30000,
      );
      expect(r.state, SalesRevenueState.excluded);
      expect(r.confirmed, 0);
    });

    test('환불 대기는 결제완료여도 수익이 아니다 — 돈이 나갈 예정이다', () {
      final r = SalesEntry.judge(
        payment: payment(PaymentStatus.paid, amount: 30000),
        lifecycleClosed: false,
        refundPending: true,
        amountsSnapshot: null,
        fallbackTotal: 30000,
      );
      expect(r.state, SalesRevenueState.excluded);
      expect(r.confirmed, 0);
    });

    test('payment 없는 옛 문서·무료 건은 진행 중이면 확정으로 본다', () {
      final r = SalesEntry.judge(
        payment: null,
        lifecycleClosed: false,
        amountsSnapshot: null,
        fallbackTotal: 20000,
      );
      expect(r.state, SalesRevenueState.confirmed);
      expect(r.confirmed, 20000);
    });
  });

  group('SalesEntry.judge — 금액 정본', () {
    test('예약금 결제는 총액이 아니라 **받은 예약금**만 확정 수익이다', () {
      // 총 10만원짜리 예약을 예약금 30%(3만원)만 받고 확정한 건.
      final r = SalesEntry.judge(
        payment: payment(PaymentStatus.paid, amount: 30000),
        lifecycleClosed: false,
        amountsSnapshot: const {
          'paymentMode': 'partial',
          'totalAmount': 100000,
          'upfrontAmount': 30000,
          'remainingAmount': 70000,
        },
        fallbackTotal: 100000,
      );
      expect(r.total, 100000);
      expect(r.confirmed, 30000);
    });

    test('payment.amount가 없으면 스냅샷의 예약금으로 폴백한다', () {
      final r = SalesEntry.judge(
        payment: payment(PaymentStatus.paid),
        lifecycleClosed: false,
        amountsSnapshot: const {
          'paymentMode': 'partial',
          'totalAmount': 100000,
          'upfrontAmount': 30000,
        },
        fallbackTotal: 100000,
      );
      expect(r.confirmed, 30000);
    });

    test('amounts 스냅샷이 총액의 정본이다 — fallback보다 우선한다', () {
      // 호스트가 나중에 참가비를 올려도 이 건의 금액은 스냅샷 그대로여야 한다.
      final r = SalesEntry.judge(
        payment: payment(PaymentStatus.paid, amount: 45000),
        lifecycleClosed: false,
        amountsSnapshot: const {'totalAmount': 45000},
        fallbackTotal: 99999,
      );
      expect(r.total, 45000);
      expect(r.confirmed, 45000);
    });

    test('확정 금액은 총액을 넘지 못한다', () {
      final r = SalesEntry.judge(
        payment: payment(PaymentStatus.paid, amount: 999999),
        lifecycleClosed: false,
        amountsSnapshot: const {'totalAmount': 30000},
        fallbackTotal: 30000,
      );
      expect(r.confirmed, 30000);
    });
  });

  group('SalesEntry.pendingAmount', () {
    SalesEntry entry({
      required int total,
      required int confirmed,
      required SalesRevenueState state,
    }) => SalesEntry(
      kind: SalesKind.rental,
      id: 'r1',
      contentTitle: '내 장소',
      bookedAt: DateTime(2026, 8, 27, 10),
      headcount: 4,
      totalAmount: total,
      confirmedAmount: confirmed,
      revenueState: state,
      statusLabel: '예약 확정',
    );

    test('예약금 건의 현장 잔금이 미확정 금액이다', () {
      final e = entry(
        total: 100000,
        confirmed: 30000,
        state: SalesRevenueState.confirmed,
      );
      expect(e.pendingAmount, 70000);
    });

    test('취소·환불 건은 받을 돈이 없다', () {
      final e = entry(
        total: 100000,
        confirmed: 0,
        state: SalesRevenueState.excluded,
      );
      expect(e.pendingAmount, 0);
    });
  });

  group('HostSalesStats.from — 기간·유형·일자별 집계', () {
    SalesEntry at(
      DateTime when, {
      SalesKind kind = SalesKind.party,
      int headcount = 1,
      int total = 10000,
      int confirmed = 10000,
      SalesRevenueState state = SalesRevenueState.confirmed,
      String id = 'e',
    }) => SalesEntry(
      kind: kind,
      id: id,
      contentTitle: '콘텐츠',
      bookedAt: when,
      headcount: headcount,
      totalAmount: total,
      confirmedAmount: confirmed,
      revenueState: state,
      statusLabel: '결제완료',
    );

    final entries = [
      at(DateTime(2026, 8, 27, 9), id: 'a', headcount: 1, confirmed: 30000,
          total: 30000),
      at(DateTime(2026, 8, 27, 18), id: 'b', kind: SalesKind.place,
          headcount: 4, confirmed: 40000, total: 40000),
      at(DateTime(2026, 8, 26, 12), id: 'c', kind: SalesKind.rental,
          headcount: 6, confirmed: 250000, total: 250000),
      // 취소 건 — 건수·인원에는 들지만 수익에는 안 든다.
      at(DateTime(2026, 8, 26, 20), id: 'd', kind: SalesKind.party,
          headcount: 1, confirmed: 0, total: 20000,
          state: SalesRevenueState.excluded),
      // 기간 밖.
      at(DateTime(2026, 8, 1, 10), id: 'e', confirmed: 999999, total: 999999),
    ];

    final range = DateRange(DateTime(2026, 8, 26), DateTime(2026, 8, 28));

    test('기간 밖은 어느 숫자에도 들어가지 않는다', () {
      final s = HostSalesStats.from(entries, range: range);
      expect(s.count, 4);
      expect(s.confirmedRevenue, 320000);
    });

    test('건수·인원은 취소 건까지 세고, 수익만 상태로 거른다', () {
      final s = HostSalesStats.from(entries, range: range);
      expect(s.count, 4); // 취소 1건 포함
      expect(s.headcount, 12); // 1 + 4 + 6 + 1
      expect(s.confirmedRevenue, 320000); // 취소 건 20000원 제외
    });

    test('유형별 매출이 갈린다', () {
      final s = HostSalesStats.from(entries, range: range);
      expect(s.revenueByKind[SalesKind.party], 30000);
      expect(s.revenueByKind[SalesKind.place], 40000);
      expect(s.revenueByKind[SalesKind.rental], 250000);
      // 세 유형 합이 총수익과 같아야 한다 — 어긋나면 어딘가 이중 계상이다.
      expect(
        s.revenueByKind.values.reduce((a, b) => a + b),
        s.confirmedRevenue,
      );
    });

    test('유형 탭은 그 유형만 본다', () {
      final s = HostSalesStats.from(
        entries,
        range: range,
        kind: SalesKind.party,
      );
      expect(s.count, 2); // 8/27 신청 1건 + 8/26 취소 1건
      expect(s.confirmedRevenue, 30000);
    });

    test('날짜별로 묶이고 최신 날짜가 먼저 온다', () {
      final s = HostSalesStats.from(entries, range: range);
      expect(s.days.length, 2);
      expect(s.days.first.day, DateTime(2026, 8, 27));
      expect(s.days.first.count, 2);
      expect(s.days.first.headcount, 5);
      expect(s.days.first.confirmedRevenue, 70000);
      expect(s.days.last.day, DateTime(2026, 8, 26));
      expect(s.days.last.confirmedRevenue, 250000);
    });

    test('신청·예약이 없는 날은 줄 자체가 없다', () {
      final s = HostSalesStats.from(
        entries,
        range: DateRange(DateTime(2026, 8, 20), DateTime(2026, 8, 28)),
      );
      expect(s.days.map((d) => d.day), [
        DateTime(2026, 8, 27),
        DateTime(2026, 8, 26),
      ]);
    });
  });

  // 파티샵은 **네 번째 유형**이다. 위 집계 케이스들은 세 유형 기준의 숫자를
  // 그대로 못 박고 있으므로 건드리지 않고, 여기서 따로 세운다.
  group('HostSalesStats.from — 파티샵이 낀 집계', () {
    SalesEntry entry(
      SalesKind kind, {
      required int confirmed,
      required int headcount,
      required String id,
      int? total,
      SalesRevenueState state = SalesRevenueState.confirmed,
      DateTime? when,
      String hostId = '',
    }) => SalesEntry(
      kind: kind,
      id: id,
      hostId: hostId,
      contentTitle: kind == SalesKind.shop ? '츄샵' : '콘텐츠',
      bookedAt: when ?? DateTime(2026, 8, 27, 10),
      headcount: headcount,
      totalAmount: total ?? confirmed,
      confirmedAmount: confirmed,
      revenueState: state,
      statusLabel: '결제 완료',
    );

    final entries = [
      entry(SalesKind.party, id: 'p', confirmed: 30000, headcount: 1),
      entry(SalesKind.place, id: 'pl', confirmed: 40000, headcount: 4),
      entry(SalesKind.rental, id: 'r', confirmed: 250000, headcount: 6),
      // 파티샵 — 2개 팔린 34,000원짜리 주문.
      entry(SalesKind.shop, id: 's1', confirmed: 34000, headcount: 2),
      // 환불된 파티샵 주문 — 건수·수량에는 들지만 실매출에는 안 든다.
      entry(
        SalesKind.shop,
        id: 's2',
        confirmed: 0,
        total: 12000,
        headcount: 1,
        state: SalesRevenueState.excluded,
      ),
    ];

    final range = DateRange(DateTime(2026, 8, 27), DateTime(2026, 8, 28));

    test('전체 매출 합계에 파티샵 확정 판매금액이 들어간다', () {
      final s = HostSalesStats.from(entries, range: range);
      // 30000 + 40000 + 250000 + 34000 (환불 12000은 제외)
      expect(s.confirmedRevenue, 354000);
    });

    test('유형별로 파티샵이 따로 갈린다 — 네 유형 합 = 총수익', () {
      final s = HostSalesStats.from(entries, range: range);
      expect(s.revenueByKind[SalesKind.party], 30000);
      expect(s.revenueByKind[SalesKind.place], 40000);
      expect(s.revenueByKind[SalesKind.rental], 250000);
      expect(s.revenueByKind[SalesKind.shop], 34000);
      expect(
        s.revenueByKind.values.reduce((a, b) => a + b),
        s.confirmedRevenue,
        reason: '어긋나면 어딘가 이중 계상이거나 빠진 유형이 있다',
      );
    });

    test('파티샵 탭은 주문 건수·판매 수량·판매금액만 본다', () {
      final s = HostSalesStats.from(entries, range: range, kind: SalesKind.shop);
      expect(s.count, 2, reason: '환불 건도 주문 건수에는 든다');
      expect(s.headcount, 3, reason: '인원 축은 판매 수량이다 (2 + 1)');
      expect(s.confirmedRevenue, 34000);
      expect(s.cancelledCount, 1);
    });

    test('다른 유형 탭에는 파티샵이 섞이지 않는다', () {
      for (final k in [SalesKind.party, SalesKind.place, SalesKind.rental]) {
        final s = HostSalesStats.from(entries, range: range, kind: k);
        expect(s.count, 1, reason: k.name);
      }
    });

    test('빈 통계에도 파티샵 칸이 있다 — 화면이 null을 만나지 않는다', () {
      expect(HostSalesStats.empty.revenueByKind[SalesKind.shop], 0);
      expect(
        HostSalesStats.empty.revenueByKind.keys.toSet(),
        SalesKind.values.toSet(),
      );
    });

    test('판매자별 묶음에도 파티샵이 들어간다', () {
      final rows = SellerSales.group(
        [
          entry(
            SalesKind.shop,
            id: 's1',
            confirmed: 34000,
            headcount: 2,
            hostId: 'seller1',
          ),
          entry(
            SalesKind.party,
            id: 'p',
            confirmed: 30000,
            headcount: 1,
            hostId: 'seller1',
          ),
        ],
        range: range,
      );
      expect(rows, hasLength(1));
      expect(rows.single.revenueOf(SalesKind.shop), 34000);
      expect(rows.single.confirmedRevenue, 64000);
    });
  });

  group('HostSalesPeriod.rangeAt', () {
    final now = DateTime(2026, 8, 27, 15, 30);

    test('오늘은 자정부터 내일 자정 전까지다', () {
      final r = HostSalesPeriod.today.rangeAt(now)!;
      expect(r.start, DateTime(2026, 8, 27));
      expect(r.end, DateTime(2026, 8, 28));
      expect(r.contains(DateTime(2026, 8, 27, 23, 59)), isTrue);
      expect(r.contains(DateTime(2026, 8, 28)), isFalse);
    });

    test('최근 7일은 오늘을 포함해 7일이다', () {
      final r = HostSalesPeriod.last7.rangeAt(now)!;
      expect(r.start, DateTime(2026, 8, 21));
      expect(r.end, DateTime(2026, 8, 28));
    });

    test('최근 30일은 오늘을 포함해 30일이다', () {
      final r = HostSalesPeriod.last30.rangeAt(now)!;
      expect(r.start, DateTime(2026, 7, 29));
      expect(r.end, DateTime(2026, 8, 28));
    });

    test('이번 달은 1일부터 다음 달 1일 전까지다', () {
      final r = HostSalesPeriod.thisMonth.rangeAt(now)!;
      expect(r.start, DateTime(2026, 8));
      expect(r.end, DateTime(2026, 9));
      expect(r.contains(DateTime(2026, 8, 31, 23)), isTrue);
      expect(r.contains(DateTime(2026, 9, 1)), isFalse);
    });

    test('직접 선택은 프리셋이 만들지 않는다', () {
      expect(HostSalesPeriod.custom.rangeAt(now), isNull);
    });

    test('12월 이번 달은 다음 해 1월로 넘어간다', () {
      final r = HostSalesPeriod.thisMonth.rangeAt(DateTime(2026, 12, 15))!;
      expect(r.start, DateTime(2026, 12));
      expect(r.end, DateTime(2027));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/models/place_product.dart';
import 'package:party_app/models/place_sales_stats.dart';
import 'package:party_app/services/place_product_service.dart';

/// 사장님 판매 통계 집계 — 어떤 주문을 매출로 세는지, 오늘/이번 달을 어떻게
/// 가르는지를 못 박는다.
void main() {
  final now = DateTime(2026, 8, 5, 14); // 8월 5일 오후 2시

  PlaceProductOrder order({
    required int totalPrice,
    required DateTime paidAt,
    PlaceProductOrderStatus status = PlaceProductOrderStatus.usable,
    int quantity = 1,
    String productId = 'prod1',
    String productName = '생맥주 1잔',
    PlaceProductType type = PlaceProductType.drinkVoucher,
  }) => PlaceProductOrder.fromMap('o', {
    'productId': productId,
    'productName': productName,
    'productType': type.key,
    'placeId': 'place1',
    'hostId': 'host1',
    'buyerId': 'buyer1',
    'quantity': quantity,
    'totalPrice': totalPrice,
    'status': status.key,
    'paidAt': paidAt.millisecondsSinceEpoch,
    'createdAt': paidAt.millisecondsSinceEpoch,
  });

  group('오늘 집계', () {
    test('오늘 결제된 주문만 오늘 매출로 센다', () {
      final stats = PlaceSalesStats.from([
        order(totalPrice: 12000, paidAt: DateTime(2026, 8, 5, 10)),
        order(totalPrice: 8000, paidAt: DateTime(2026, 8, 5, 23, 59)),
        // 어제 — 오늘에서는 빠지고 이번 달에는 들어간다.
        order(totalPrice: 50000, paidAt: DateTime(2026, 8, 4, 23, 59)),
      ], now: now);

      expect(stats.todayOrderCount, 2);
      expect(stats.todayRevenue, 20000);
      expect(stats.monthOrderCount, 3);
      expect(stats.monthRevenue, 70000);
    });

    test('한 주문에 여러 개면 건수와 수량이 따로 잡힌다', () {
      final stats = PlaceSalesStats.from([
        order(totalPrice: 30000, quantity: 3, paidAt: DateTime(2026, 8, 5, 9)),
      ], now: now);

      expect(stats.todayOrderCount, 1);
      expect(stats.todayQuantity, 3);
    });

    test('자정 경계 — 오늘 00:00은 포함, 어제 23:59는 제외', () {
      final stats = PlaceSalesStats.from([
        order(totalPrice: 1000, paidAt: DateTime(2026, 8, 5)),
        order(totalPrice: 9000, paidAt: DateTime(2026, 8, 4, 23, 59, 59)),
      ], now: now);

      expect(stats.todayOrderCount, 1);
      expect(stats.todayRevenue, 1000);
    });
  });

  group('매출로 세는 상태', () {
    test('결제 완료·사용 가능·사용 완료만 매출이다', () {
      expect(
        PlaceSalesStats.countsAsRevenue(PlaceProductOrderStatus.paid),
        isTrue,
      );
      expect(
        PlaceSalesStats.countsAsRevenue(PlaceProductOrderStatus.usable),
        isTrue,
      );
      expect(
        PlaceSalesStats.countsAsRevenue(PlaceProductOrderStatus.used),
        isTrue,
      );
    });

    test('취소·환불·만료·결제대기는 매출에서 빠진다', () {
      for (final s in [
        PlaceProductOrderStatus.cancelled,
        PlaceProductOrderStatus.refunded,
        PlaceProductOrderStatus.expired,
        PlaceProductOrderStatus.paymentPending,
      ]) {
        expect(
          PlaceSalesStats.countsAsRevenue(s),
          isFalse,
          reason: '${s.label}은 매출이 아니어야 한다',
        );
      }
    });

    test('환불·취소된 주문은 집계에 전혀 들어가지 않는다', () {
      final stats = PlaceSalesStats.from([
        order(totalPrice: 10000, paidAt: DateTime(2026, 8, 5, 10)),
        order(
          totalPrice: 99000,
          paidAt: DateTime(2026, 8, 5, 11),
          status: PlaceProductOrderStatus.refunded,
        ),
        order(
          totalPrice: 77000,
          paidAt: DateTime(2026, 8, 5, 12),
          status: PlaceProductOrderStatus.cancelled,
        ),
      ], now: now);

      expect(stats.todayOrderCount, 1);
      expect(stats.todayRevenue, 10000);
      expect(stats.monthRevenue, 10000);
    });
  });

  group('최다 판매 상품', () {
    test('수량 합계가 가장 큰 상품을 고른다', () {
      final stats = PlaceSalesStats.from([
        order(
          productId: 'beer',
          productName: '생맥주 1잔',
          quantity: 20,
          totalPrice: 100000,
          paidAt: DateTime(2026, 8, 2),
        ),
        order(
          productId: 'beer',
          productName: '생맥주 1잔',
          quantity: 3,
          totalPrice: 15000,
          paidAt: DateTime(2026, 8, 5, 10),
        ),
        order(
          productId: 'seat',
          productName: '창가석 예약',
          type: PlaceProductType.seatReservation,
          quantity: 9,
          totalPrice: 90000,
          paidAt: DateTime(2026, 8, 3),
        ),
      ], now: now);

      expect(stats.topProduct, isNotNull);
      expect(stats.topProduct!.name, '생맥주 1잔');
      expect(stats.topProduct!.quantity, 23);
      expect(stats.topProduct!.type, PlaceProductType.drinkVoucher);
    });

    test('지난달 판매는 이번 달 최다 상품에 끼지 않는다', () {
      final stats = PlaceSalesStats.from([
        order(
          productId: 'old',
          productName: '지난달 인기상품',
          quantity: 999,
          totalPrice: 10000,
          paidAt: DateTime(2026, 7, 20),
        ),
        order(
          productId: 'beer',
          productName: '생맥주 1잔',
          quantity: 2,
          totalPrice: 10000,
          paidAt: DateTime(2026, 8, 1),
        ),
      ], now: now);

      expect(stats.topProduct!.name, '생맥주 1잔');
      expect(stats.monthRevenue, 10000, reason: '지난달 매출이 섞이면 안 된다');
    });

    test('판매가 없으면 null이고 나머지는 0이다', () {
      final stats = PlaceSalesStats.from(const [], now: now);
      expect(stats.topProduct, isNull);
      expect(stats.todayRevenue, 0);
      expect(stats.monthRevenue, 0);
      expect(stats.unusedVoucherCount, 0);
    });
  });

  group('미사용 이용권', () {
    test('결제 완료·사용 가능만 미사용으로 센다', () {
      final stats = PlaceSalesStats.from([
        order(
          totalPrice: 1000,
          paidAt: DateTime(2026, 8, 5),
          status: PlaceProductOrderStatus.usable,
        ),
        order(
          totalPrice: 1000,
          paidAt: DateTime(2026, 8, 5),
          status: PlaceProductOrderStatus.paid,
        ),
        order(
          totalPrice: 1000,
          paidAt: DateTime(2026, 8, 5),
          status: PlaceProductOrderStatus.used,
        ),
        order(
          totalPrice: 1000,
          paidAt: DateTime(2026, 8, 5),
          status: PlaceProductOrderStatus.refunded,
        ),
      ], now: now);

      expect(stats.unusedVoucherCount, 2);
      // 사용 완료도 이미 받은 돈이라 매출에는 들어간다.
      expect(stats.todayRevenue, 3000);
    });
  });

  test('paidAt이 없는 예전 주문은 createdAt으로 귀속한다', () {
    final o = PlaceProductOrder.fromMap('legacy', {
      'productId': 'p',
      'productName': '옛 상품',
      'quantity': 1,
      'totalPrice': 5000,
      'status': PlaceProductOrderStatus.used.key,
      'createdAt': DateTime(2026, 8, 5, 8).millisecondsSinceEpoch,
    });
    final stats = PlaceSalesStats.from([o], now: now);
    expect(stats.todayRevenue, 5000);
  });
}

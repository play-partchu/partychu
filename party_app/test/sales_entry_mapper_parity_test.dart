import 'package:flutter_test/flutter_test.dart';
import 'package:partychu_sales/partychu_sales.dart';

import 'package:party_app/models/place_product.dart';
import 'package:party_app/models/place_sales_stats.dart';
import 'package:party_app/models/place_rental_reservation.dart';
import 'package:party_app/models/place_visit_reservation.dart';
import 'package:party_app/models/shop_order.dart';
import 'package:party_app/services/host_sales_service.dart';
import 'package:party_app/services/place_visit_reservation_service.dart';

/// [SalesEntryMapper]가 들고 있는 "닫힌 상태" 집합이 **도메인 enum과 어긋나지
/// 않게** 못 박는다.
///
/// 왜 두 벌이 존재하는가: 매퍼는 packages/partychu_sales에 있고 그 패키지는
/// cloud_firestore를 모른다(관리자 웹이 콜러블로 받은 맵에도 같은 규칙을 써야
/// 하므로). 도메인 enum들은 `DocumentSnapshot`을 파싱하느라 Firestore에 묶여
/// 있어 그 패키지로 옮길 수 없다.
///
/// 그래서 정의는 두 곳이지만 **값은 하나여야 한다**. 도메인 enum에 상태를
/// 추가하고 매퍼를 안 고치면 그 상태의 매출이 조용히 잘못 잡히므로, 여기서
/// 먼저 깨지게 한다.
void main() {
  Set<String> closedKeysOf<T>(
    List<T> values,
    String Function(T) key,
    bool Function(T) isLive,
  ) => {
    for (final v in values)
      if (!isLive(v)) key(v),
  };

  test('플레이스 방문 예약 — VisitReservationStatus.isLive와 같은 집합이다', () {
    expect(
      SalesEntryMapper.visitClosedStatuses,
      closedKeysOf(
        VisitReservationStatus.values,
        (s) => s.key,
        (s) => s.isLive,
      ),
    );
  });

  test('장소대여·콤보 — PlaceRentalStatus.isLive와 같은 집합이다', () {
    expect(
      SalesEntryMapper.rentalClosedStatuses,
      closedKeysOf(PlaceRentalStatus.values, (s) => s.key, (s) => s.isLive),
    );
  });

  test('상품 주문 — 돈이 남지 않은 상태만 닫힌 것으로 본다', () {
    // PlaceProductOrderStatus에는 isLive가 없다(isAlive는 "아직 쓸 수 있는
    // 이용권"이라 뜻이 다르다). 매출 기준은 PlaceSalesStats.countsAsRevenue —
    // paid/usable/used가 매출이고 나머지 중 결제대기만 미확정이다.
    final revenue = PlaceProductOrderStatus.values
        .where(PlaceSalesStats.countsAsRevenue)
        .map((s) => s.key)
        .toSet();
    // 닫힌 것 ∩ 매출인 것 = 공집합이어야 한다.
    expect(
      SalesEntryMapper.orderClosedStatuses.intersection(revenue),
      isEmpty,
    );
    // 닫힌 것 ∪ 매출인 것 ∪ 결제대기 = 전체
    expect(
      {
        ...SalesEntryMapper.orderClosedStatuses,
        ...revenue,
        PlaceProductOrderStatus.paymentPending.key,
      },
      PlaceProductOrderStatus.values.map((s) => s.key).toSet(),
    );
  });

  test('파티 신청 — 노쇼는 닫힌 상태가 아니다 (돈은 이미 받았다)', () {
    expect(SalesEntryMapper.partyClosedStatuses, {'rejected', 'cancelled'});
    expect(SalesEntryMapper.partyClosedStatuses, isNot(contains('no_show')));
  });

  test('파티샵 주문 — ShopOrderStatus.isLive와 같은 집합이다', () {
    expect(
      SalesEntryMapper.shopClosedStatuses,
      closedKeysOf(ShopOrderStatus.values, (s) => s.key, (s) => s.isLive),
    );
    // 취소·환불·만료 셋이 실매출에서 빠지는 전부다.
    expect(SalesEntryMapper.shopClosedStatuses, {
      'cancelled',
      'refunded',
      'expired',
    });
    // 결제완료는 당연히 닫힌 상태가 아니다(매출이다).
    expect(
      SalesEntryMapper.shopClosedStatuses,
      isNot(contains(ShopOrderStatus.paid.key)),
    );
  });

  test('매퍼가 보는 컬렉션 이름이 각 서비스의 상수와 같다', () {
    expect(debugProductOrderCollectionMatches(), isTrue);
    // 파티샵(orders)과 플레이스 상품(placeProductOrders)은 **다른 컬렉션**이다.
    expect(debugShopOrderCollectionMatches(), isTrue);
    expect(
      SalesSource.rentalReservation.collection,
      RentalSource.rental.collection,
    );
    expect(
      SalesSource.packageBooking.collection,
      RentalSource.package.collection,
    );
    expect(
      SalesSource.visitReservation.collection,
      PlaceVisitReservationService.collection,
    );
  });

  group('SalesEntryMapper.fromDocument — 문서 해석', () {
    test('파티 신청은 appliedFee가 금액 정본이고 1문서 = 1명이다', () {
      final e = SalesEntryMapper.fromDocument(
        {
          'hostId': 'host1',
          'partyId': 'p1',
          'status': 'applied',
          'appliedFee': 30000,
          'appliedAt': DateTime(2026, 8, 27, 10).millisecondsSinceEpoch,
          'payment': {'method': 'bank_transfer', 'status': 'paid'},
        },
        source: SalesSource.partyApplication,
        id: 'p1_u1',
        contentTitle: '와인 모임',
      )!;
      expect(e.kind, SalesKind.party);
      expect(e.hostId, 'host1');
      expect(e.contentTitle, '와인 모임');
      expect(e.headcount, 1);
      expect(e.totalAmount, 30000);
      expect(e.confirmedAmount, 30000);
      expect(e.revenueState, SalesRevenueState.confirmed);
    });

    test('콤보 파티 신청은 null이다 — packageBookings에서 이미 센다', () {
      final e = SalesEntryMapper.fromDocument(
        {
          'hostId': 'host1',
          'partyId': 'p1',
          'status': 'applied',
          'appliedFee': 30000,
          'source': 'combo',
          'bundleBookingId': 'b1',
          'appliedAt': DateTime(2026, 8, 27).millisecondsSinceEpoch,
        },
        source: SalesSource.partyApplication,
        id: 'p1_u1',
      );
      expect(e, isNull);
    });

    test('콤보 예약은 totalPrice 한 번만 센다 (roomPrice + partyFee)', () {
      final e = SalesEntryMapper.fromDocument(
        {
          'hostId': 'host1',
          'placeName': '한강 하우스',
          'partyTitle': '와인 모임',
          'status': 'confirmed',
          'roomPrice': 200000,
          'partyFee': 30000,
          'totalPrice': 230000,
          'peopleCount': 4,
          'createdAt': DateTime(2026, 8, 27).millisecondsSinceEpoch,
          'payment': {'method': 'bank_transfer', 'status': 'paid'},
        },
        source: SalesSource.packageBooking,
        id: 'b1',
      )!;
      expect(e.kind, SalesKind.rental);
      expect(e.totalAmount, 230000);
      expect(e.confirmedAmount, 230000);
      expect(e.headcount, 4);
      expect(e.subtitle, contains('와인 모임'));
    });

    test('상품 주문은 인원 축이 수량이다', () {
      final e = SalesEntryMapper.fromDocument(
        {
          'hostId': 'host1',
          'placeName': '재즈바',
          'productName': '생맥주 1잔',
          'status': 'usable',
          'quantity': 3,
          'totalPrice': 15000,
          'createdAt': DateTime(2026, 8, 27).millisecondsSinceEpoch,
        },
        source: SalesSource.productOrder,
        id: 'o1',
      )!;
      expect(e.headcount, 3);
      expect(e.totalAmount, 15000);
      // payment 맵이 없는 옛 주문은 확정으로 본다.
      expect(e.revenueState, SalesRevenueState.confirmed);
    });

    test('취소된 방문 예약은 제외되고 상태 문구가 그대로 나온다', () {
      final e = SalesEntryMapper.fromDocument(
        {
          'hostId': 'host1',
          'placeName': '재즈바',
          'status': 'cancelled_by_guest',
          'depositAmount': 20000,
          'peopleCount': 2,
          'createdAt': DateTime(2026, 8, 27).millisecondsSinceEpoch,
          'payment': {'method': 'bank_transfer', 'status': 'paid'},
        },
        source: SalesSource.visitReservation,
        id: 'v1',
      )!;
      expect(e.revenueState, SalesRevenueState.excluded);
      expect(e.confirmedAmount, 0);
      expect(e.statusLabel, '예약 취소');
    });

    test('파티샵 주문은 amount가 금액 정본이고 판매자가 sellerId다', () {
      final e = SalesEntryMapper.fromDocument(
        {
          // hostId는 아예 없다 — 파티샵 주문 문서에는 sellerId만 있다.
          'sellerId': 'seller1',
          'buyerId': 'buyer1',
          'shopName': '츄샵',
          'productName': '텀블러',
          'selectedOptionName': '블랙',
          'status': 'paid',
          'quantity': 2,
          // 할인 전 금액(subtotal)과 쿠폰이 함께 있어도 정본은 amount다.
          'subtotal': 40000,
          'couponDiscount': 6000,
          'amount': 34000,
          'createdAt': DateTime(2026, 8, 27, 11).millisecondsSinceEpoch,
          'payment': {'method': 'bank_transfer', 'status': 'paid'},
        },
        source: SalesSource.shopOrder,
        id: 'so1',
      )!;
      expect(e.kind, SalesKind.shop);
      expect(e.hostId, 'seller1');
      expect(e.contentTitle, '츄샵');
      // 할인 전 40,000원이 아니라 **실제 판매금액** 34,000원이다.
      expect(e.totalAmount, 34000);
      expect(e.confirmedAmount, 34000);
      expect(e.headcount, 2, reason: '인원 축은 판매 수량이다');
      expect(e.revenueState, SalesRevenueState.confirmed);
      expect(e.subtitle, '텀블러 (블랙)');
      expect(e.statusLabel, '결제 완료');
    });

    test('파티샵 주문의 취소·환불·만료는 실매출에서 빠진다', () {
      for (final (status, label) in [
        ('cancelled', '취소됨'),
        ('refunded', '환불됨'),
        ('expired', '만료됨'),
      ]) {
        final e = SalesEntryMapper.fromDocument(
          {
            'sellerId': 'seller1',
            'shopName': '츄샵',
            'status': status,
            'quantity': 1,
            'amount': 34000,
            'createdAt': DateTime(2026, 8, 27).millisecondsSinceEpoch,
            // 이미 결제까지 갔던 건이어도 상태가 닫혔으면 매출이 아니다.
            'payment': {'method': 'bank_transfer', 'status': 'paid'},
          },
          source: SalesSource.shopOrder,
          id: 'so_$status',
        )!;
        expect(e.revenueState, SalesRevenueState.excluded, reason: status);
        expect(e.confirmedAmount, 0, reason: status);
        expect(e.pendingAmount, 0, reason: status);
        expect(e.statusLabel, label);
      }
    });

    test('입금 전 파티샵 주문은 미확정이다 — 0원으로 뭉개지 않는다', () {
      final e = SalesEntryMapper.fromDocument(
        {
          'sellerId': 'seller1',
          'shopName': '츄샵',
          'status': 'payment_pending',
          'quantity': 1,
          'amount': 34000,
          'createdAt': DateTime(2026, 8, 27).millisecondsSinceEpoch,
          'payment': {'method': 'bank_transfer', 'status': 'awaiting_deposit'},
        },
        source: SalesSource.shopOrder,
        id: 'so2',
      )!;
      expect(e.revenueState, SalesRevenueState.pending);
      expect(e.confirmedAmount, 0);
      expect(e.pendingAmount, 34000);
    });

    test('payment 맵이 없는 옛 파티샵 주문은 확정으로 본다', () {
      final e = SalesEntryMapper.fromDocument(
        {
          'sellerId': 'seller1',
          'shopName': '츄샵',
          'status': 'paid',
          'quantity': 1,
          'amount': 12000,
          'createdAt': DateTime(2026, 8, 27).millisecondsSinceEpoch,
        },
        source: SalesSource.shopOrder,
        id: 'so3',
      )!;
      expect(e.revenueState, SalesRevenueState.confirmed);
      expect(e.confirmedAmount, 12000);
    });

    test('날짜를 만들 수 없는 문서는 null이다', () {
      final e = SalesEntryMapper.fromDocument(
        {'hostId': 'host1', 'status': 'applied', 'appliedFee': 1000},
        source: SalesSource.partyApplication,
        id: 'x',
      );
      expect(e, isNull);
    });

    test('epoch ms · ISO 문자열 · DateTime을 모두 같은 날로 읽는다', () {
      // 관리자 웹은 콜러블이 내려준 ms를, 호스트 앱은 Firestore Timestamp를
      // 넘긴다 — 어느 쪽이든 같은 날짜 축에 서야 한다.
      final when = DateTime(2026, 8, 27, 13);
      for (final raw in <Object>[
        when.millisecondsSinceEpoch,
        when.toIso8601String(),
        when,
      ]) {
        final e = SalesEntryMapper.fromDocument(
          {
            'hostId': 'h',
            'status': 'applied',
            'appliedFee': 1000,
            'appliedAt': raw,
          },
          source: SalesSource.partyApplication,
          id: 'x',
        )!;
        expect(e.day, DateTime(2026, 8, 27), reason: '$raw');
      }
    });
  });
}

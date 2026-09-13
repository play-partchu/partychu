// ─────────────────────────────────────────────────────────────────────────────
// 사장님 판매 통계 — 주문 목록에서 집계만 하는 순수 로직.
//
// Firestore 쿼리나 위젯을 전혀 모르게 만들어, 집계 규칙(어떤 상태를 매출로
// 세는지, 어느 시각을 기준으로 오늘/이번 달을 가르는지)을 테스트로 못 박는다.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:party_app/models/place_product.dart';
import 'package:party_app/services/place_product_service.dart';

/// 가장 많이 팔린 상품 한 건.
typedef TopProduct = ({String name, PlaceProductType type, int quantity});

/// 사장님 대시보드가 보여주는 숫자 묶음.
class PlaceSalesStats {
  const PlaceSalesStats({
    required this.todayOrderCount,
    required this.todayQuantity,
    required this.todayRevenue,
    required this.monthOrderCount,
    required this.monthRevenue,
    required this.topProduct,
    required this.unusedVoucherCount,
  });

  /// 오늘 결제된 주문 건수.
  final int todayOrderCount;

  /// 오늘 팔린 수량 합계(건수와 달리 한 주문에 여러 개일 수 있다).
  final int todayQuantity;

  final int todayRevenue;

  final int monthOrderCount;
  final int monthRevenue;

  /// 이번 달 기준 최다 판매 상품 — 팔린 게 없으면 null.
  final TopProduct? topProduct;

  /// 아직 쓰지 않은 이용권 수(결제 완료 + 사용 가능). 사장님이 "앞으로 들어올
  /// 손님"을 가늠하는 데 쓴다.
  final int unusedVoucherCount;

  static const empty = PlaceSalesStats(
    todayOrderCount: 0,
    todayQuantity: 0,
    todayRevenue: 0,
    monthOrderCount: 0,
    monthRevenue: 0,
    topProduct: null,
    unusedVoucherCount: 0,
  );

  /// 매출로 세는 주문 상태.
  ///
  /// 결제가 끝난 것만 센다 — 취소·환불·기간 만료는 돈이 남지 않았고,
  /// 결제 대기는 아직 돈이 들어오지 않았다. `사용 완료`도 매출에는 포함된다
  /// (이미 받은 돈이라 손님이 썼는지와 무관하다).
  static bool countsAsRevenue(PlaceProductOrderStatus s) =>
      s == PlaceProductOrderStatus.paid ||
      s == PlaceProductOrderStatus.usable ||
      s == PlaceProductOrderStatus.used;

  /// [orders]를 [now] 기준으로 집계한다.
  ///
  /// 매출 귀속 시각은 `paidAt`이다 — 주문이 만들어진 때가 아니라 **돈이
  /// 확정된 때**가 매출 날짜이기 때문. 아주 예전 데이터처럼 paidAt이 없으면
  /// createdAt으로 대신한다.
  factory PlaceSalesStats.from(
    List<PlaceProductOrder> orders, {
    required DateTime now,
  }) {
    final todayStart = DateTime(now.year, now.month, now.day);
    final tomorrowStart = todayStart.add(const Duration(days: 1));
    final monthStart = DateTime(now.year, now.month);
    final nextMonthStart = DateTime(now.year, now.month + 1);

    var todayOrders = 0;
    var todayQty = 0;
    var todayRevenue = 0;
    var monthOrders = 0;
    var monthRevenue = 0;
    var unused = 0;

    // 이름이 같아도 상품이 다를 수 있으므로 productId로 묶고, 표시용 이름은
    // 마지막에 본 값을 쓴다(상품명이 바뀌면 최신 이름으로 보인다).
    final soldByProduct = <String, int>{};
    final nameByProduct = <String, String>{};
    final typeByProduct = <String, PlaceProductType>{};

    for (final o in orders) {
      if (o.status.isAlive) unused++;
      if (!countsAsRevenue(o.status)) continue;
      // 매출은 **돈이 실제로 들어온 건만** 센다. 주문 상태(paid/usable)는
      // 결제가 확인된 뒤에만 붙지만, 상태와 결제가 다른 축이 된 뒤로는
      // 상태만 믿지 않는다 — 입금대기·입금확인중·현장결제 예정은 제외된다.
      // (결제 정보가 없는 건은 옛 PG 흐름이라 이미 검증이 끝난 주문이다.)
      if (!o.isPaid) continue;

      final at = o.paidAt ?? o.createdAt;
      if (at == null) continue;

      final inMonth = !at.isBefore(monthStart) && at.isBefore(nextMonthStart);
      if (inMonth) {
        monthOrders++;
        monthRevenue += o.totalPrice;
        if (o.productId.isNotEmpty) {
          soldByProduct[o.productId] =
              (soldByProduct[o.productId] ?? 0) + o.quantity;
          nameByProduct[o.productId] = o.productName;
          typeByProduct[o.productId] = o.productType;
        }
      }

      if (!at.isBefore(todayStart) && at.isBefore(tomorrowStart)) {
        todayOrders++;
        todayQty += o.quantity;
        todayRevenue += o.totalPrice;
      }
    }

    TopProduct? top;
    for (final e in soldByProduct.entries) {
      if (top == null || e.value > top.quantity) {
        top = (
          name: nameByProduct[e.key] ?? '',
          type: typeByProduct[e.key] ?? PlaceProductType.etc,
          quantity: e.value,
        );
      }
    }

    return PlaceSalesStats(
      todayOrderCount: todayOrders,
      todayQuantity: todayQty,
      todayRevenue: todayRevenue,
      monthOrderCount: monthOrders,
      monthRevenue: monthRevenue,
      topProduct: top,
      unusedVoucherCount: unused,
    );
  }
}

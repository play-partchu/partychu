// ─────────────────────────────────────────────────────────────────────────────
// 파티샵 주문 1건 — `orders/{orderId}`.
//
// 결제는 파티 신청·예약들과 **같은 규칙**을 쓴다([PaymentInfo]/[DepositPanel]).
// 주문 진행 상태([ShopOrderStatus])와 결제 상태([PaymentStatus])는 서로 다른
// 축이다 — 주문이 접수됐어도 입금 전이면 '입금대기'이고, 판매자가 입금을
// 확인하는 순간 둘이 함께 결제완료로 넘어간다.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:party_app/models/payment_status.dart';

/// 주문 1건의 진행 상태. 서버(shopOrders.js)가 쓰는 문자열과 1:1이다.
enum ShopOrderStatus {
  /// 주문 접수 — 아직 돈이 들어오지 않았다(무통장입금이면 입금대기).
  paymentPending('payment_pending', '결제 대기', true),
  paid('paid', '결제 완료', true),
  cancelled('cancelled', '취소됨', false),
  refunded('refunded', '환불됨', false),
  expired('expired', '만료됨', false);

  const ShopOrderStatus(this.key, this.label, this.isLive);

  final String key;
  final String label;

  /// 아직 살아 있는 주문인지 — 목록의 '진행중' 탭 기준.
  final bool isLive;

  static ShopOrderStatus fromKey(String? key) =>
      values.firstWhere((s) => s.key == key, orElse: () => paymentPending);
}

/// 파티샵 주문 1건.
class ShopOrder {
  final String id;
  final String shopId;
  final String shopName;
  final String productId;
  final String productName;
  final String? selectedOptionName;

  final int quantity;
  final int subtotal;
  final int couponDiscount;

  /// 실제 청구 금액(쿠폰 할인 반영). 서버가 계산한 값이다.
  final int amount;

  final String buyerId;
  final String buyerName;
  final String sellerId;
  final String sellerName;

  /// 'delivery' | 'pickup' | 'scheduled' 등 — 샵이 정한 수령 방식 키.
  final String deliveryMethod;

  /// 수령 예정일(수령 방식이 'scheduled'일 때).
  final DateTime? scheduledDate;

  final ShopOrderStatus status;
  final DateTime? createdAt;

  /// 결제 정보 — 무료 주문과 옛 포트원 주문에는 없다(null).
  final PaymentInfo? payment;

  const ShopOrder({
    required this.id,
    required this.shopId,
    required this.shopName,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.amount,
    required this.buyerId,
    required this.sellerId,
    required this.status,
    this.selectedOptionName,
    this.subtotal = 0,
    this.couponDiscount = 0,
    this.buyerName = '',
    this.sellerName = '',
    this.deliveryMethod = '',
    this.scheduledDate,
    this.createdAt,
    this.payment,
  });

  factory ShopOrder.fromDoc(DocumentSnapshot<Object?> doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? const {};
    DateTime? at(String key) {
      final v = d[key];
      return v is Timestamp ? v.toDate().toLocal() : null;
    }

    return ShopOrder(
      id: doc.id,
      shopId: d['shopId'] as String? ?? '',
      shopName: d['shopName'] as String? ?? '파티샵',
      productId: d['productId'] as String? ?? '',
      productName: d['productName'] as String? ?? '상품',
      selectedOptionName: d['selectedOptionName'] as String?,
      quantity: (d['quantity'] as num?)?.toInt() ?? 1,
      subtotal: (d['subtotal'] as num?)?.toInt() ?? 0,
      couponDiscount: (d['couponDiscount'] as num?)?.toInt() ?? 0,
      amount: (d['amount'] as num?)?.toInt() ?? 0,
      buyerId: d['buyerId'] as String? ?? '',
      buyerName: d['buyerName'] as String? ?? '',
      sellerId: d['sellerId'] as String? ?? '',
      sellerName: d['sellerName'] as String? ?? '',
      deliveryMethod: d['deliveryMethod'] as String? ?? '',
      scheduledDate: at('scheduledDate'),
      status: ShopOrderStatus.fromKey(d['status'] as String?),
      createdAt: at('createdAt'),
      payment: PaymentInfo.fromMap(
        (d['payment'] as Map?)?.cast<String, dynamic>(),
      ),
    );
  }

  /// '상품명 (옵션) · 2개'.
  String get summaryLabel =>
      '$productName'
      '${selectedOptionName == null || selectedOptionName!.isEmpty ? '' : ' ($selectedOptionName)'}'
      ' · $quantity개';

  /// 구매자가 아직 취소할 수 있는지 — 결제 전이거나 결제 직후.
  bool get canCancel => status.isLive;

  /// 판매자가 지금 입금을 확인해줘야 하는 건인지 — 서버 조건
  /// (depositFlow.assertCanConfirm)과 같다.
  bool get needsDepositCheck {
    final p = payment;
    if (p == null || !status.isLive) return false;
    return p.status == PaymentStatus.depositPending ||
        p.status == PaymentStatus.awaitingDeposit;
  }
}

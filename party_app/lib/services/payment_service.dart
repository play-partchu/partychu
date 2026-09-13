import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:party_app/models/payment_status.dart';
import 'package:party_app/utils/format_utils.dart' as fmt;

/// 파티샵 상품 주문의 서버 창구.
///
/// ⚠ 예전에는 여기에 `processDummyPayment`(1.5초 뒤 무조건 성공)와
///   `createOrder`(클라이언트가 `orders` 문서에 `status:'paid'`를 직접 쓰기)가
///   있었다. 결제 검증이 전혀 없었고, `orders` 컬렉션에는 firestore.rules
///   규칙조차 없어(=기본 거부) 그 쓰기는 사실 항상 실패하고 있었다.
///
/// 지금은 파티 신청·예약들과 **같은 결제 규칙**을 쓴다. 결제 금액은 서버가
/// 상품 문서를 보고 직접 계산하고, 앱은 **결제수단만** 고른다. 클라이언트는
/// 주문 문서를 쓰지 않는다(읽기만 가능).
///
/// PG 계약 전이라 실제로 고를 수 있는 수단은 무통장입금·현장(수령 시) 결제뿐
/// 이고, 그 흐름은 다른 도메인과 완전히 같다(서버 depositFlow 공유):
///
///   [createPendingOrder] → 입금대기 → [markDepositSent]('입금했어요')
///     → 판매자 [confirmDeposit]('입금 확인') → 결제완료
///   기한 내 입금이 없으면 서버가 주문을 만료시키고 **재고를 되돌린다**.
class PaymentService {
  PaymentService._();

  static FirebaseFunctions get _fn =>
      FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  static const String collection = 'orders';

  /// 주문 생성. 재고 선점과 금액 계산은 전부 서버가 한다 — 그래서 금액
  /// 파라미터가 아예 없고, [payment]도 **수단만** 실려 간다.
  static Future<PendingShopOrder> createPendingOrder({
    required String shopId,
    required String productId,
    required int quantity,
    required String deliveryMethod,
    String? selectedOptionName,
    DateTime? scheduledDate,
    bool useCoupon = false,
    PaymentInfo? payment,
  }) async {
    final res = await _fn
        .httpsCallable('createPendingShopOrder')
        .call<Map<Object?, Object?>>({
          'shopId': shopId,
          'productId': productId,
          'quantity': quantity,
          'deliveryMethod': deliveryMethod,
          'selectedOptionName': ?selectedOptionName,
          'useCoupon': useCoupon,
          if (payment != null) 'payment': payment.toMap(),
          if (scheduledDate != null)
            'scheduledDateMs': scheduledDate.millisecondsSinceEpoch,
        });
    final data = res.data;
    return PendingShopOrder(
      orderId: data['orderId'] as String,
      totalPrice: (data['totalPrice'] as num).toInt(),
      productName: data['productName'] as String? ?? '',
      paymentStatus: PaymentStatus.fromKey(data['paymentStatus'] as String?),
    );
  }

  /// 구매자의 '입금했어요' — 입금대기 → 입금확인중.
  /// 이미 알린 뒤에 다시 부르면 서버가 막는다(중복 방지).
  static Future<void> markDepositSent(String orderId) async {
    await _fn.httpsCallable('markShopDepositSent').call<Object?>({
      'orderId': orderId,
    });
  }

  /// 판매자의 '입금 확인' — 입금확인중(또는 입금대기) → 결제완료.
  /// 돈이 확인된 순간이 곧 주문 확정이다.
  static Future<void> confirmDeposit(String orderId) async {
    await _fn.httpsCallable('confirmShopDeposit').call<Object?>({
      'orderId': orderId,
    });
  }

  /// 주문 취소 — 선점했던 재고가 상품으로 되돌아간다.
  /// 구매자와 판매자 둘 다 부를 수 있다.
  static Future<void> cancelOrder(String orderId) async {
    await _fn.httpsCallable('cancelShopOrder').call<Map<Object?, Object?>>({
      'orderId': orderId,
    });
  }

  /// 내가 산 주문 / 내 샵으로 들어온 주문. 복합 색인을 피하려고 정렬은 화면에서
  /// 한다(다른 목록 화면들과 같은 방식).
  static Query<Map<String, dynamic>> myPurchases(String uid) =>
      FirebaseFirestore.instance
          .collection(collection)
          .where('buyerId', isEqualTo: uid);

  static Query<Map<String, dynamic>> mySales(String uid) => FirebaseFirestore
      .instance
      .collection(collection)
      .where('sellerId', isEqualTo: uid);

  // ── 금액 표시 형식 (앱 전체 공통 포맷으로 위임) ──────────────────────
  static String fmtPrice(int p) => fmt.formatPrice(p);

  // ── 쿠폰 할인 계산 ───────────────────────────────────────────────
  static int applyCoupon({
    required int amount,
    required String discountType,
    required int discountValue,
    required int minAmount,
  }) {
    if (amount < minAmount) {
      return amount;
    }
    if (discountType == 'percent') {
      final disc = (amount * discountValue / 100).floor();
      return (amount - disc).clamp(0, amount);
    }
    return (amount - discountValue).clamp(0, amount);
  }
}

/// [PaymentService.createPendingOrder]의 결과 — 결과 안내에 쓰는 값들.
class PendingShopOrder {
  const PendingShopOrder({
    required this.orderId,
    required this.totalPrice,
    required this.productName,
    this.paymentStatus,
  });

  final String orderId;
  final int totalPrice;
  final String productName;

  /// 서버가 정한 결제 상태 — 무료 주문이면 null.
  final PaymentStatus? paymentStatus;
}

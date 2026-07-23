import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:party_app/utils/format_utils.dart' as fmt;
import 'package:party_app/utils/user_session.dart';

class PaymentResult {
  final bool success;
  final String? merchantUid;
  final String? errorMessage;

  const PaymentResult({
    required this.success,
    this.merchantUid,
    this.errorMessage,
  });
}

class PaymentService {
  // ── 더미 결제 (테스트용) ──────────────────────────────────────────
  // 실제 연동 시 이 메서드를 포트원/토스페이먼츠 웹뷰 호출로 교체
  static Future<PaymentResult> processDummyPayment({
    required String itemName,
    required int amount,
    String? buyerName,
  }) async {
    await Future.delayed(const Duration(milliseconds: 1500));
    final merchantUid =
        'test_${DateTime.now().millisecondsSinceEpoch}';
    return PaymentResult(success: true, merchantUid: merchantUid);
  }

  // ── 주문 저장 + 재고 차감 (Firestore 트랜잭션) ─────────────────────
  static Future<String> createOrder({
    required String shopId,
    required String productId,
    required String productName,
    required int amount,
    required String sellerId,
    required String sellerName,
    required String deliveryMethod,
    DateTime? scheduledDate,
    String? selectedOptionName,
    int optionAdditionalPrice = 0,
    String? merchantUid,
  }) async {
    final fs = FirebaseFirestore.instance;
    final orderRef = fs.collection('orders').doc();

    await fs.runTransaction((tx) async {
      final productRef = fs
          .collection('partyShops')
          .doc(shopId)
          .collection('products')
          .doc(productId);

      final snap = await tx.get(productRef);
      if (snap.exists) {
        final stock = (snap.data()?['stock'] as num?)?.toInt() ?? 0;
        if (stock > 0) {
          tx.update(productRef, {'stock': stock - 1});
        }
      }

      tx.set(orderRef, {
        'shopId':               shopId,
        'productId':            productId,
        'productName':          productName,
        'amount':               amount,
        'buyerId':              UserSession.userId,
        'buyerName':            UserSession.name,
        'sellerId':             sellerId,
        'sellerName':           sellerName,
        'deliveryMethod':       deliveryMethod,
        'scheduledDate':        scheduledDate != null
            ? Timestamp.fromDate(scheduledDate)
            : null,
        'selectedOptionName':   selectedOptionName,
        'optionAdditionalPrice': optionAdditionalPrice,
        'merchantUid':          merchantUid,
        'status':               'paid',
        'createdAt':            FieldValue.serverTimestamp(),
      });
    });

    return orderRef.id;
  }

  // ── 금액 표시 형식 (앱 전체 공통 포맷으로 위임) ──────────────────────
  static String fmtPrice(int p) => fmt.formatPrice(p);

  // ── 쿠폰 할인 계산 ───────────────────────────────────────────────
  static int applyCoupon({
    required int amount,
    required String discountType,
    required int discountValue,
    required int minAmount,
  }) {
    if (amount < minAmount) { return amount; }
    if (discountType == 'percent') {
      final disc = (amount * discountValue / 100).floor();
      return (amount - disc).clamp(0, amount);
    }
    return (amount - discountValue).clamp(0, amount);
  }
}

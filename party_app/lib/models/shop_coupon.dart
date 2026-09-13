// ─────────────────────────────────────────────────────────────────────────────
// 파티샵 할인쿠폰 — "언제 깎아주는가(조건)"와 "얼마를 깎아주는가(방식)"를
// 한 곳에서 읽고 쓰는 값.
//
// 원래는 방문 할인쿠폰 하나뿐이라 등록 화면과 상세 화면이 각각 Firestore
// 필드를 직접 꺼내 문구를 만들고 있었다. 조건이 넷으로 늘면서 같은 규칙이
// 여러 곳으로 갈라지면 "등록에서 본 문구"와 "손님이 보는 문구"가 어긋나므로
// 여기 하나로 모은다.
//
// Firestore 저장 형태 (partyShops/{shopId})
//   hasCoupon:            bool    ← 기존 필드, 그대로
//   couponDiscountType:   'percent' | 'amount'  ← 기존 필드, 그대로
//   couponDiscountValue:  int     ← 기존 필드, 그대로 (10 = 10%, 5000 = 5,000원)
//   couponMinAmount:      int     ← 기존 필드, '○○원 이상' 조건에서만 의미
//   couponCondition:      String  ← 새 필드 (없으면 아래 규칙으로 유추)
//   couponMinQuantity:    int     ← 새 필드, '○개 이상' 조건에서만 의미
//
// 하위호환: couponCondition이 없는 기존 문서는 couponMinAmount로 조건을
// 되돌려 읽는다 — 0보다 크면 금액 조건, 아니면 방문 할인. 그래야 예전에
// 등록된 샵의 표시가 지금과 똑같이 유지된다.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:party_app/utils/format_utils.dart';

/// 할인이 걸리는 조건. 넷 중 하나만 고른다.
enum ShopCouponCondition {
  /// 매장에 방문하면 할인 — 파티샵이 처음부터 갖고 있던 방식.
  visit('visit', '방문 할인'),

  /// ○○원 이상 구매 시 할인.
  minAmount('minAmount', '○○원 이상 구매 시 할인'),

  /// ○개 이상 구매 시 할인.
  minQuantity('minQuantity', '○개 이상 구매 시 할인'),

  /// 조건 없이 할인.
  none('none', '조건 없이 할인');

  const ShopCouponCondition(this.key, this.label);

  /// Firestore에 저장하는 값.
  final String key;

  /// 등록 화면에서 고르는 문구.
  final String label;

  static ShopCouponCondition? fromKey(String? key) {
    if (key == null || key.isEmpty) return null;
    for (final c in ShopCouponCondition.values) {
      if (c.key == key) return c;
    }
    return null;
  }
}

/// 할인 방식 — 기존 'percent' / 'amount' 두 값을 그대로 쓴다.
const String kShopCouponPercent = 'percent';
const String kShopCouponAmount = 'amount';

/// 등록 화면에서 고르는 할인 방식 문구 ↔ 저장값.
const String kShopCouponPercentLabel = '퍼센트 할인';
const String kShopCouponAmountLabel = '금액 할인';

class ShopCoupon {
  const ShopCoupon({
    required this.enabled,
    required this.condition,
    required this.discountType,
    required this.discountValue,
    this.minAmount = 0,
    this.minQuantity = 0,
  });

  /// 샵 문서에서 읽는다. 새 필드가 없는 기존 문서도 그대로 읽힌다.
  factory ShopCoupon.fromShopData(Map<String, dynamic> data) {
    final rawMinAmount = (data['couponMinAmount'] as num?)?.toInt() ?? 0;
    final condition =
        ShopCouponCondition.fromKey(data['couponCondition'] as String?) ??
        // 조건 필드가 없던 시절의 문서 — 최소 금액이 있으면 금액 조건,
        // 없으면 방문 할인이었다.
        (rawMinAmount > 0
            ? ShopCouponCondition.minAmount
            : ShopCouponCondition.visit);
    final rawType = data['couponDiscountType'] as String? ?? '';
    return ShopCoupon(
      enabled: data['hasCoupon'] as bool? ?? false,
      condition: condition,
      discountType: rawType == kShopCouponPercent
          ? kShopCouponPercent
          : kShopCouponAmount,
      discountValue: (data['couponDiscountValue'] as num?)?.toInt() ?? 0,
      minAmount: condition == ShopCouponCondition.minAmount ? rawMinAmount : 0,
      minQuantity: condition == ShopCouponCondition.minQuantity
          ? (data['couponMinQuantity'] as num?)?.toInt() ?? 0
          : 0,
    );
  }

  final bool enabled;
  final ShopCouponCondition condition;

  /// 'percent' 또는 'amount'.
  final String discountType;

  /// 퍼센트면 10 = 10%, 금액이면 5000 = 5,000원.
  final int discountValue;

  /// '○○원 이상' 조건에서만 쓰는 최소 구매 금액.
  final int minAmount;

  /// '○개 이상' 조건에서만 쓰는 최소 수량.
  final int minQuantity;

  /// 샵 문서에 쓸 쿠폰 필드들. 고른 조건에 해당하지 않는 값은 0으로 눕혀
  /// 둔다 — 그래야 서버(shopOrders)의 금액 조건 검사가 엉뚱한 값을 보지
  /// 않는다.
  Map<String, dynamic> toShopFields() => <String, dynamic>{
    'hasCoupon': enabled,
    'couponCondition': condition.key,
    'couponDiscountType': discountType,
    'couponDiscountValue': discountValue,
    'couponMinAmount': condition == ShopCouponCondition.minAmount
        ? minAmount
        : 0,
    'couponMinQuantity': condition == ShopCouponCondition.minQuantity
        ? minQuantity
        : 0,
  };

  bool get isPercent => discountType == kShopCouponPercent;

  /// 할인값까지 제대로 채워진 쿠폰인가.
  bool get hasDiscountValue => enabled && discountValue > 0;

  /// 온라인 주문 결제창에서 자동으로 적용할 수 있는 조건인가.
  ///
  /// 수량 조건은 주문 흐름에 수량 개념이 없어(상품 1건 + 옵션) 결제 시점에
  /// 검증할 방법이 없다. 그래서 결제창에서는 적용 버튼 대신 조건만 안내한다
  /// — 조건을 못 지키는데 깎아주는 일이 없어야 한다.
  bool get appliesToOnlineOrder => condition != ShopCouponCondition.minQuantity;

  /// '10% 할인' / '5,000원 할인'.
  String get discountLabel {
    if (discountValue <= 0) return '할인';
    return isPercent
        ? '$discountValue% 할인'
        : '${formatAmount(discountValue)} 할인';
  }

  /// '방문 시' / '3만원 이상 구매 시' / '2개 이상 구매 시' / ''(조건 없음).
  String get conditionLabel {
    switch (condition) {
      case ShopCouponCondition.visit:
        return '방문 시';
      case ShopCouponCondition.minAmount:
        return minAmount > 0 ? '${formatAmount(minAmount)} 이상 구매 시' : '';
      case ShopCouponCondition.minQuantity:
        return minQuantity > 0 ? '$minQuantity개 이상 구매 시' : '';
      case ShopCouponCondition.none:
        return '';
    }
  }

  /// 손님에게 보여주는 한 줄 — 조건과 할인을 함께 읽히게 한다.
  /// 예) '3만원 이상 구매 시 3,000원 할인', '2개 이상 구매 시 10% 할인'.
  String get guestLabel {
    if (!hasDiscountValue) {
      return condition == ShopCouponCondition.visit ? '방문 할인쿠폰 있음' : '할인쿠폰 있음';
    }
    final cond = conditionLabel;
    return cond.isEmpty ? discountLabel : '$cond $discountLabel';
  }

  /// 목록 카드에 붙는 짧은 표식 — 자리가 없어 조건까지는 못 담는다.
  String get badgeLabel =>
      condition == ShopCouponCondition.visit ? '방문쿠폰' : '할인쿠폰';
}

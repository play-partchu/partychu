import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/shop_coupon.dart';

/// 파티샵 할인쿠폰 정본([ShopCoupon])의 회귀 테스트.
///
/// 이 파일이 지키는 약속은 셋이다.
///  1. **조건 필드가 없던 기존 문서도 그대로 읽힌다** — 최소 금액이 있으면
///     금액 조건, 없으면 방문 할인. 예전에 등록된 샵의 표시가 바뀌면 안 된다.
///  2. **손님에게는 조건까지 보인다** — 그냥 '할인'이 아니라
///     '3만원 이상 구매 시 3,000원 할인'.
///  3. **고른 조건 밖의 값은 저장되지 않는다** — 수량 조건 쿠폰에
///     couponMinAmount가 남으면 서버(shopOrders)의 금액 검사가 엉뚱한 값을
///     본다.
void main() {
  group('하위호환 — couponCondition이 없는 기존 문서', () {
    test('최소 금액이 있으면 금액 조건으로 읽는다', () {
      final coupon = ShopCoupon.fromShopData({
        'hasCoupon': true,
        'couponDiscountType': 'amount',
        'couponDiscountValue': 3000,
        'couponMinAmount': 30000,
      });

      expect(coupon.condition, ShopCouponCondition.minAmount);
      expect(coupon.minAmount, 30000);
      expect(coupon.guestLabel, '3만원 이상 구매 시 3,000원 할인');
    });

    test('최소 금액이 없으면 방문 할인으로 읽는다', () {
      final coupon = ShopCoupon.fromShopData({
        'hasCoupon': true,
        'couponDiscountType': 'amount',
        'couponDiscountValue': 5000,
      });

      expect(coupon.condition, ShopCouponCondition.visit);
      expect(coupon.minAmount, 0);
      expect(coupon.guestLabel, '방문 시 5,000원 할인');
      expect(coupon.badgeLabel, '방문쿠폰');
    });

    test('할인값이 아직 없으면 "쿠폰 있음"까지만 말한다', () {
      expect(
        ShopCoupon.fromShopData({'hasCoupon': true}).guestLabel,
        '방문 할인쿠폰 있음',
      );
      expect(
        ShopCoupon.fromShopData({
          'hasCoupon': true,
          'couponCondition': 'none',
        }).guestLabel,
        '할인쿠폰 있음',
      );
    });

    test('쿠폰을 안 쓰는 샵은 꺼진 채로 읽힌다', () {
      expect(ShopCoupon.fromShopData(const {}).enabled, isFalse);
    });
  });

  group('조건별 손님 문구', () {
    ShopCoupon couponOf(Map<String, dynamic> extra) =>
        ShopCoupon.fromShopData({'hasCoupon': true, ...extra});

    test('○○원 이상 구매 시 — 정액 할인', () {
      expect(
        couponOf({
          'couponCondition': 'minAmount',
          'couponMinAmount': 30000,
          'couponDiscountType': 'amount',
          'couponDiscountValue': 3000,
        }).guestLabel,
        '3만원 이상 구매 시 3,000원 할인',
      );
    });

    test('○개 이상 구매 시 — 정률 할인', () {
      expect(
        couponOf({
          'couponCondition': 'minQuantity',
          'couponMinQuantity': 2,
          'couponDiscountType': 'percent',
          'couponDiscountValue': 10,
        }).guestLabel,
        '2개 이상 구매 시 10% 할인',
      );
    });

    test('조건 없이 할인은 조건 문구를 붙이지 않는다', () {
      expect(
        couponOf({
          'couponCondition': 'none',
          'couponDiscountType': 'amount',
          'couponDiscountValue': 3000,
        }).guestLabel,
        '3,000원 할인',
      );
    });

    test('조건은 골랐는데 값이 비었으면 조건 문구를 지어내지 않는다', () {
      expect(
        couponOf({
          'couponCondition': 'minQuantity',
          'couponDiscountType': 'percent',
          'couponDiscountValue': 10,
        }).guestLabel,
        '10% 할인',
      );
    });
  });

  group('결제창 적용 가능 여부', () {
    test('수량 조건은 주문에 수량 개념이 없어 자동 적용하지 않는다', () {
      final coupon = ShopCoupon.fromShopData({
        'hasCoupon': true,
        'couponCondition': 'minQuantity',
        'couponMinQuantity': 2,
        'couponDiscountType': 'percent',
        'couponDiscountValue': 10,
      });

      expect(coupon.appliesToOnlineOrder, isFalse);
    });

    test('나머지 조건은 지금까지처럼 결제창에서 적용된다', () {
      for (final key in ['visit', 'minAmount', 'none']) {
        final coupon = ShopCoupon.fromShopData({
          'hasCoupon': true,
          'couponCondition': key,
          'couponDiscountType': 'amount',
          'couponDiscountValue': 3000,
        });
        expect(coupon.appliesToOnlineOrder, isTrue, reason: key);
      }
    });
  });

  group('저장 형태', () {
    test('고른 조건 밖의 값은 0으로 눕는다', () {
      final fields = const ShopCoupon(
        enabled: true,
        condition: ShopCouponCondition.minQuantity,
        discountType: kShopCouponPercent,
        discountValue: 10,
        minAmount: 30000,
        minQuantity: 2,
      ).toShopFields();

      expect(fields['couponCondition'], 'minQuantity');
      expect(fields['couponMinQuantity'], 2);
      // 서버의 금액 조건 검사가 보면 안 되는 값이다.
      expect(fields['couponMinAmount'], 0);
    });

    test('쓴 값을 그대로 다시 읽어 온다', () {
      const written = ShopCoupon(
        enabled: true,
        condition: ShopCouponCondition.minAmount,
        discountType: kShopCouponAmount,
        discountValue: 3000,
        minAmount: 30000,
      );
      final reread = ShopCoupon.fromShopData(written.toShopFields());

      expect(reread.condition, ShopCouponCondition.minAmount);
      expect(reread.minAmount, 30000);
      expect(reread.discountType, kShopCouponAmount);
      expect(reread.discountValue, 3000);
      expect(reread.guestLabel, written.guestLabel);
    });
  });
}

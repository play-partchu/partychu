// 상품·이용권의 **환불 UX 노출 스위치**([ProductRefundFeature]).
//
// 지금은 내려 둔 상태다 — 결제수단이 무통장입금·현장결제뿐이고, 상품 주문에는
// 돌려주는 절차(refundRequests·계좌 수집·호스트 알림)가 아직 없기 때문이다.
// 여기서 확인하는 것은 세 가지다.
//
//  ① 화면에서만 내렸는가 — 필드·상태·서버 경로는 그대로여야 한다.
//  ② 구매·미결제 취소처럼 **환불과 무관한 흐름**은 그대로 열려 있는가.
//  ③ 스위치를 다시 켜면 옛 동작으로 돌아가는가.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partychu_sales/partychu_sales.dart'
    show PaymentInfo, PaymentMethod, PaymentStatus;

import 'package:party_app/models/place_product.dart';
import 'package:party_app/models/product_refund_feature.dart';
import 'package:party_app/services/place_product_service.dart';
import 'package:party_app/widgets/voucher_card.dart';

PlaceProductOrder order({
  required PlaceProductOrderStatus status,
  PaymentStatus? paymentStatus,
  String voucherCode = '',
}) => PlaceProductOrder(
  id: 'o1',
  productId: 'p1',
  productName: '웰컴드링크',
  productType: PlaceProductType.etc,
  placeId: 'pl1',
  placeCollection: 'events',
  placeName: '테스트 매장',
  hostId: 'host1',
  buyerId: 'buyer1',
  buyerName: '구매자',
  quantity: 1,
  unitPrice: 10000,
  totalPrice: 10000,
  status: status,
  voucherCode: voucherCode,
  useAt: null,
  useStartAt: null,
  useEndAt: null,
  reservationId: null,
  createdAt: null,
  paidAt: null,
  usedAt: null,
  payment: paymentStatus == null
      ? null
      : PaymentInfo(method: PaymentMethod.bankTransfer, status: paymentStatus),
);

void main() {
  group('스위치 자체', () {
    test('지금은 내려 있다 — 다시 켤 때 고칠 곳은 이 상수 하나다', () {
      expect(ProductRefundFeature.enabled, isFalse);
      expect(
        ProductRefundFeature.allowsPaidCancel,
        ProductRefundFeature.enabled,
      );
    });

    test('미결제 주문의 취소는 스위치와 무관하게 언제나 열려 있다', () {
      // 환불이 아니라 **주문 물리기**다 — 막으면 잘못 넣은 주문을 되돌릴 수
      // 없고 선점된 재고도 묶인다.
      expect(
        ProductRefundFeature.allowsCancel(
          PlaceProductOrderStatus.paymentPending,
        ),
        isTrue,
      );
    });

    test('결제가 끝난 이용권의 취소는 스위치를 따른다', () {
      for (final s in [
        PlaceProductOrderStatus.paid,
        PlaceProductOrderStatus.usable,
      ]) {
        expect(
          ProductRefundFeature.allowsCancel(s),
          ProductRefundFeature.enabled,
          reason: '$s',
        );
      }
    });

    test('이미 끝난 주문은 어느 쪽이든 취소 대상이 아니다', () {
      for (final s in [
        PlaceProductOrderStatus.used,
        PlaceProductOrderStatus.cancelled,
        PlaceProductOrderStatus.refunded,
        PlaceProductOrderStatus.expired,
      ]) {
        expect(ProductRefundFeature.allowsCancel(s), isFalse, reason: '$s');
      }
    });
  });

  group('스키마는 그대로', () {
    test('refundPolicy 필드는 살아 있고 값도 왕복한다', () {
      final loaded = PlaceProduct.fromMap('p1', {
        'name': '웰컴드링크',
        'refundPolicy': '구매 후 7일 이내 전액 환불',
      });
      expect(loaded.refundPolicy, '구매 후 7일 이내 전액 환불');
      // 입력칸이 화면에 없어도 저장 경로는 읽은 값을 그대로 다시 내보낸다 —
      // 기존 문서의 값이 조용히 지워지지 않는 근거다.
      expect(loaded.toMap()['refundPolicy'], '구매 후 7일 이내 전액 환불');
    });

    test('환불 상태와 규칙도 지우지 않았다', () {
      expect(PlaceProductOrderStatus.fromKey('refunded').label, '환불');
      expect(PlaceProductRefundPolicyRule.fieldLabel, '취소·환불 규정');
      // 규칙 자체는 순수하게 남아 있다 — 스위치는 부르는 쪽이 본다.
      expect(
        PlaceProductRefundPolicyRule.anyMissing([
          PlaceProduct.empty(
            placeId: 'p',
            placeCollection: 'events',
            hostId: 'h',
            sortOrder: 0,
          ),
        ]),
        isTrue,
      );
    });
  });

  group('이용권 카드', () {
    Future<void> pumpCard(WidgetTester tester, PlaceProductOrder o) async {
      tester.view.physicalSize = const Size(420, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: VoucherCard(order: o)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('입금 대기 중인 주문에는 취소 버튼이 그대로 있다', (tester) async {
      await pumpCard(
        tester,
        order(
          status: PlaceProductOrderStatus.paymentPending,
          paymentStatus: PaymentStatus.awaitingDeposit,
        ),
      );
      expect(find.text('취소 요청'), findsOneWidget);
      expect(find.text(ProductRefundFeature.cancelHiddenGuide), findsNothing);
    });

    testWidgets('결제가 끝난 이용권에서는 취소 대신 문의 안내가 뜬다', (tester) async {
      await pumpCard(
        tester,
        order(
          status: PlaceProductOrderStatus.usable,
          paymentStatus: PaymentStatus.paid,
          voucherCode: 'ABC123',
        ),
      );

      if (ProductRefundFeature.enabled) {
        expect(find.text('취소 요청'), findsOneWidget);
      } else {
        expect(find.text('취소 요청'), findsNothing);
        expect(
          find.text(ProductRefundFeature.cancelHiddenGuide),
          findsOneWidget,
          reason: '버튼만 사라지면 취소할 방법이 없는 화면이 된다',
        );
      }
    });

    testWidgets('QR 보기는 환불과 무관하게 그대로다', (tester) async {
      await pumpCard(
        tester,
        order(
          status: PlaceProductOrderStatus.usable,
          paymentStatus: PaymentStatus.paid,
          voucherCode: 'ABC123',
        ),
      );
      expect(find.text('QR 보기'), findsOneWidget);
    });
  });
}

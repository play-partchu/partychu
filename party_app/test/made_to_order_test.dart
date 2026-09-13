// 🛠 주문제작 — 파티샵 상품의 **불리언 하나**가 하는 일과, 하지 않는 일.
//
// 이 파일이 붙잡는 것 넷.
//   ① 판정 — 필드가 없으면 false(기존 상품은 전부 재고 상품 그대로).
//   ② 재고 — 주문제작은 stock 0이어도 살 수 있고, 재고 상품은 예전 그대로다.
//   ③ 문구 — 실제 주문 상태 머신이 하는 일과 어긋나지 않는다.
//   ④ 배선 — 등록 화면의 체크란/비활성/저장, 게스트·호스트 화면의 표시,
//      그리고 서버의 재고 예외까지. 화면은 Firebase 없이 그릴 수 없으므로
//      ①~③은 값으로, ④는 소스 가드로 확인한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/made_to_order.dart';
import 'package:party_app/models/shop_order.dart';

String _src(String path) => File(path).readAsStringSync();

/// 줄바꿈·들여쓰기를 지운 소스 — 배선만 보고 서식은 보지 않는다.
String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

void main() {
  // ── ① 판정 ─────────────────────────────────────────────────────────────
  group('주문제작 판정 — 필드가 없으면 재고 상품이다', () {
    test('필드가 아예 없는 기존 상품은 false', () {
      expect(isMadeToOrderProduct({'name': '머그컵', 'stock': 10}), isFalse);
    });

    test('true일 때만 주문제작 — 문자열/숫자로 들어와도 켜지지 않는다', () {
      expect(isMadeToOrderProduct({kMadeToOrderField: true}), isTrue);
      expect(isMadeToOrderProduct({kMadeToOrderField: false}), isFalse);
      expect(isMadeToOrderProduct({kMadeToOrderField: 'true'}), isFalse);
      expect(isMadeToOrderProduct({kMadeToOrderField: 1}), isFalse);
      expect(isMadeToOrderProduct(null), isFalse);
    });

    test('저장 키는 madeToOrder 하나뿐이다', () {
      expect(kMadeToOrderField, 'madeToOrder');
    });
  });

  // ── ② 재고 ─────────────────────────────────────────────────────────────
  group('재고 판정 — 주문제작만 예외다', () {
    test('주문제작은 재고 0이어도 살 수 있다', () {
      expect(shopProductInStock(stock: 0, madeToOrder: true), isTrue);
    });

    test('재고 상품 규칙은 예전 그대로 — 0이면 품절', () {
      expect(shopProductInStock(stock: 0, madeToOrder: false), isFalse);
      expect(shopProductInStock(stock: 1, madeToOrder: false), isTrue);
      expect(shopProductInStock(stock: 99, madeToOrder: false), isTrue);
    });
  });

  // ── ③ 문구 ─────────────────────────────────────────────────────────────
  group('문구가 실제 주문 상태 머신과 어긋나지 않는다', () {
    // 상품 주문의 상태는 이 다섯뿐이고, 그중 어디에도 '제작'도 '승인'도 없다.
    // 문구가 없는 단계를 말하기 시작하면 그 순간 거짓말이 된다.
    test('주문 상태에는 제작/승인 단계가 없다', () {
      expect(ShopOrderStatus.values.map((s) => s.key).toSet(), {
        'payment_pending',
        'paid',
        'cancelled',
        'refunded',
        'expired',
      });
    });

    test("'주문이 안 된다'고 말하지 않는다 — 주문은 접수 즉시 생성된다", () {
      for (final copy in [
        kMadeToOrderNotice,
        kMadeToOrderHostNotice,
        kMadeToOrderRefundNotice,
      ]) {
        expect(copy.contains('주문이 되지 않'), isFalse, reason: copy);
        expect(copy.contains('주문이 안 '), isFalse, reason: copy);
        // 호스트 승인 단계는 만들지 않았으므로 승인을 말하지 않는다.
        expect(copy.contains('승인'), isFalse, reason: copy);
      }
    });

    test('알림은 단정하지 않는다 — 앱이 강제하지 않는다', () {
      expect(kMadeToOrderHostNotice, '주문을 놓치지 않도록 알림 설정을 확인해 주세요.');
      expect(kMadeToOrderHostNotice.contains('필수'), isFalse);
      expect(kMadeToOrderHostNotice.contains('켜야'), isFalse);
    });

    test('환불은 정책을 바꾸지 않고 가능성만 알린다', () {
      expect(kMadeToOrderRefundNotice.contains('제한될 수 있어요'), isTrue);
      // '제한됩니다'로 단정하면 지금 환불 규칙과 다른 말이 된다.
      expect(kMadeToOrderRefundNotice.contains('제한됩니다'), isFalse);
    });

    test('배지 문구는 한 곳에서만 만들어진다', () {
      expect(kMadeToOrderBadge, '$kMadeToOrderEmoji $kMadeToOrderLabel');
      expect(kMadeToOrderBadge, '🛠 주문제작');
      expect(kMadeToOrderNotice, '주문이 들어오면 제작하는 상품이에요.');
    });
  });

  // ── ④ 배선 ─────────────────────────────────────────────────────────────
  group('등록 화면 — 체크하면 재고 수량을 묻지 않는다', () {
    final market = _flat(_src('lib/screens/party_market_register_screen.dart'));
    final product = _flat(
      _src('lib/screens/party_shop_product_register_screen.dart'),
    );

    test('상품 추가 시트: 재고 칸 아래 체크란, 켜면 입력칸 비활성', () {
      expect(market.contains('enabled: !madeToOrder,'), isTrue);
      expect(market.contains('_madeToOrderCheck('), isTrue);
      // 숨기지 않고 비활성으로 남긴다(껐을 때 폼이 튀지 않게).
      expect(
        market.contains('if (madeToOrder) _madeToOrderHostNote(),'),
        isTrue,
      );
    });

    test('상품 등록 화면도 같은 체크란과 같은 안내를 쓴다', () {
      expect(product.contains('enabled: !_madeToOrder,'), isTrue);
      expect(product.contains('_madeToOrderCheck(),'), isTrue);
      expect(
        product.contains('if (_madeToOrder) _madeToOrderHostNote(),'),
        isTrue,
      );
    });

    test('저장 — 켜면 재고는 0, 불리언 하나가 함께 적힌다', () {
      expect(
        market.contains(
          "'stock': madeToOrder ? 0 : int.tryParse(stockc.text.trim()) ?? 0, "
          'kMadeToOrderField: madeToOrder,',
        ),
        isTrue,
      );
      expect(
        product.contains(
          "'stock': _madeToOrder ? 0 : stock, "
          'kMadeToOrderField: _madeToOrder,',
        ),
        isTrue,
      );
    });

    test('임시저장에도 실려 이어서 작성이 값을 잃지 않는다', () {
      expect(product.contains('kMadeToOrderField: _madeToOrder,'), isTrue);
      expect(
        product.contains(
          '_madeToOrder = p[kMadeToOrderField] as bool? ?? false;',
        ),
        isTrue,
      );
    });

    test("샵의 '재고 있음' 집계에서 주문제작이 빠지지 않는다", () {
      for (final src in [market, product]) {
        expect(src.contains('shopProductInStock('), isTrue);
      }
    });
  });

  group('게스트 화면 — 주문제작은 품절로 막히지 않는다', () {
    final detail = _flat(_src('lib/screens/party_shop_detail_screen.dart'));

    test('목록 카드: 탭도 살아 있고 흐려지지도 않는다', () {
      expect(
        detail.contains(
          'final canBuy = shopProductInStock(stock: stock, '
          'madeToOrder: madeToOrder);',
        ),
        isTrue,
      );
      expect(detail.contains('onTap: canBuy ? onTap : null,'), isTrue);
      expect(detail.contains('opacity: canBuy ? 1.0 : 0.5,'), isTrue);
      // '품절' 칩은 재고 상품에만 남는다.
      expect(detail.contains('if (!madeToOrder && stock == 0)'), isTrue);
    });

    test('구매 시트: 🛠 배지 + 무엇인지 + 환불 안내', () {
      expect(detail.contains('if (madeToOrder) ...['), isTrue);
      for (final key in [
        'kMadeToOrderBadge',
        'kMadeToOrderNotice',
        'kMadeToOrderRefundNotice',
      ]) {
        expect(detail.contains(key), isTrue, reason: key);
      }
      // 잔여 수량은 재고 상품에만.
      expect(
        detail.contains('if (!madeToOrder && stock > 0 && stock <= 10)'),
        isTrue,
      );
    });
  });

  group('호스트 화면 — 주문제작이 품절로 읽히지 않는다', () {
    test('상품 관리 목록에서 빨간 품절 대신 🛠 주문제작', () {
      final manage = _flat(_src('lib/screens/party_shop_manage_screen.dart'));
      expect(
        manage.contains('final madeToOrder = isMadeToOrderProduct(d);'),
        isTrue,
      );
      expect(
        manage.contains(
          'madeToOrder ? kMadeToOrderBadge '
          ": (stock == 0 ? '품절' : '재고 \$stock개'),",
        ),
        isTrue,
      );
    });
  });

  group('서버 — 재고 검사·차감·복구를 모두 건너뛴다', () {
    final server = _flat(_src('../functions/shopOrders.js'));

    test('주문 생성: 품절로 거절하지 않는다', () {
      expect(
        server.contains('const madeToOrder = product.madeToOrder === true;'),
        isTrue,
      );
      expect(
        server.contains('if (!madeToOrder && stock < quantity) {'),
        isTrue,
      );
    });

    test('재고 선점을 하지 않는다', () {
      expect(
        server.contains(
          'if (!madeToOrder) { tx.update(productRef, '
          '{ stock: stock - quantity }); }',
        ),
        isTrue,
      );
    });

    test('취소·만료 때 없던 재고가 생기지 않는다', () {
      expect(
        server.contains('if (snap.data().madeToOrder === true) return null;'),
        isTrue,
      );
    });

    test('주문 상태를 새로 만들지 않았다 — 다섯 그대로', () {
      // 승인 단계를 넣지 않았다는 뜻이기도 하다 — 이 파일에서
      // `requireApproval`은 주석에만 있고, 어디에도 넘기지 않는다.
      expect(server.contains('requireApproval:'), isFalse);
      for (final added in ['making', 'in_production', 'accepted', '제작중']) {
        expect(server.contains("'$added'"), isFalse, reason: added);
      }
    });
  });
}

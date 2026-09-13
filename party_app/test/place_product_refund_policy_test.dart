// 상품·이용권의 '취소·환불 규정' 텍스트 — **빈 문자열이면 저장 불가**.
//
// 파티·장소대여의 티어형 환불 규정(RefundPolicyRule)과는 별개다. 그쪽은 구간
// 목록이라 '최소 1개 구간'으로 세지만, 상품 쪽은 호스트가 자유롭게 적는 안내문
// 하나라 셀 구간이 없다 — 그래서 규칙도 문구도 따로 둔다.
//
// 상품 판매 자체는 여전히 선택이다. 상품을 하나라도 등록했을 때만 그 상품에
// 대해 규정을 요구한다. 규정 없이 저장돼 있던 옛 상품은 열람·수정 화면 진입까지
// 그대로 되고, 다시 저장할 때부터 막힌다.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/place_product.dart';
import 'package:party_app/models/product_refund_feature.dart';
import 'package:party_app/widgets/place_form/place_product_editor.dart';

void main() {
  PlaceProduct product({required String refundPolicy, String name = '웰컴드링크'}) =>
      PlaceProduct.empty(
        placeId: 'p1',
        placeCollection: 'events',
        hostId: 'host1',
        sortOrder: 0,
      ).copyWith(name: name, refundPolicy: refundPolicy);

  group('공용 규칙', () {
    test('문구와 라벨은 한 곳에 고정돼 있다', () {
      expect(
        PlaceProductRefundPolicyRule.requiredMessage,
        '상품의 취소·환불 규정을 입력해주세요.',
      );
      expect(PlaceProductRefundPolicyRule.fieldLabel, '취소·환불 규정');
    });

    test('상품이 하나도 없으면 통과한다 — 판매는 선택이다', () {
      expect(PlaceProductRefundPolicyRule.anyMissing(const []), isFalse);
      expect(PlaceProductRefundPolicyRule.validate(const []), isNull);
      expect(PlaceProductRefundPolicyRule.firstMissingIndex(const []), -1);
    });

    test('빈 문자열 — 저장 불가', () {
      final products = [product(refundPolicy: '')];
      expect(PlaceProductRefundPolicyRule.anyMissing(products), isTrue);
      expect(
        PlaceProductRefundPolicyRule.validate(products),
        PlaceProductRefundPolicyRule.requiredMessage,
      );
    });

    test('공백만 있어도 빈 것으로 본다', () {
      final products = [product(refundPolicy: '   \n  ')];
      expect(PlaceProductRefundPolicyRule.anyMissing(products), isTrue);
    });

    test('내용이 있으면 저장 가능', () {
      final products = [product(refundPolicy: '구매 후 7일 이내 전액 환불')];
      expect(PlaceProductRefundPolicyRule.anyMissing(products), isFalse);
      expect(PlaceProductRefundPolicyRule.validate(products), isNull);
    });

    test('여러 상품 중 하나만 비어도 막히고, 그 상품을 짚어준다', () {
      final products = [
        product(refundPolicy: '전액 환불', name: 'A'),
        product(refundPolicy: '', name: 'B'),
        product(refundPolicy: '환불 불가', name: 'C'),
      ];
      expect(PlaceProductRefundPolicyRule.anyMissing(products), isTrue);
      expect(PlaceProductRefundPolicyRule.firstMissingIndex(products), 1);

      // 그 상품을 채우면 곧바로 통과한다.
      products[1] = products[1].copyWith(refundPolicy: '환불 불가');
      expect(PlaceProductRefundPolicyRule.anyMissing(products), isFalse);
    });

    test('규정 없이 저장돼 있던 옛 상품 — 읽기는 되고, 저장만 막힌다', () {
      // refundPolicy 키가 없던 옛 문서.
      final loaded = PlaceProduct.fromMap('id1', const {
        'placeId': 'p1',
        'placeCollection': 'events',
        'hostId': 'host1',
        'name': '옛 이용권',
      });
      expect(loaded.name, '옛 이용권', reason: '읽기 자체는 성공한다(화면 진입 허용)');
      expect(loaded.refundPolicy, '');
      expect(PlaceProductRefundPolicyRule.anyMissing([loaded]), isTrue);
    });

    test('validator 형태도 같은 판정이다', () {
      expect(
        PlaceProductRefundPolicyRule.validateText(null),
        PlaceProductRefundPolicyRule.requiredMessage,
      );
      expect(
        PlaceProductRefundPolicyRule.validateText('  '),
        PlaceProductRefundPolicyRule.requiredMessage,
      );
      expect(PlaceProductRefundPolicyRule.validateText('환불 불가'), isNull);
    });
  });

  group('전수 적용', () {
    /// 상품 판매 섹션을 그리는 화면 — 이 목록이 곧 저장 게이트를 둬야 할 곳이다.
    List<File> productScreens() {
      final out = <File>[];
      for (final entity in Directory('lib/screens').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.readAsStringSync().contains('PlaceProductSection(')) {
          out.add(entity);
        }
      }
      return out;
    }

    test('상품 섹션을 쓰는 화면을 실제로 찾아낸다', () {
      expect(
        productScreens(),
        isNotEmpty,
        reason: '탐지 방식이 깨졌다 — 아래 전수 검사가 무의미해진다',
      );
    });

    test('상품을 파는 화면은 하나도 빠짐없이 공용 규칙으로 저장을 막는다', () {
      // 두 가지 쓰임을 모두 인정한다 — 어느 쪽이든 **같은 공용 규칙** 하나다
      // (anyMissing은 firstMissingIndex(...) >= 0 그 자체다). 필수항목 안내가
      // "규정이 빈 첫 상품의 카드"를 펼쳐 그 입력칸까지 데려가려면 위치가
      // 필요해서, 화면들은 firstMissingIndex 쪽을 쓴다.
      const uses = [
        'PlaceProductRefundPolicyRule.anyMissing(',
        'PlaceProductRefundPolicyRule.firstMissingIndex(',
      ];
      final missing = <String>[];
      for (final f in productScreens()) {
        final src = f.readAsStringSync();
        if (!uses.any(src.contains)) missing.add(f.path);
      }
      expect(
        missing,
        isEmpty,
        reason:
            '상품을 파는데 취소·환불 규정 필수 검증(PlaceProductRefundPolicyRule.anyMissing)이\n'
            '없는 화면이 있다. 화면마다 검증을 따로 적지 말고 공용 규칙을 그대로 쓰자:\n'
            '${missing.join('\n')}',
      );
    });
  });

  group('입력칸', () {
    /// 상품 편집기를 Form 안에 띄운다 — 화면들이 쓰는 것과 같은 구조.
    Future<GlobalKey<FormState>> pumpEditor(
      WidgetTester tester,
      List<PlaceProduct> products,
    ) async {
      tester.view.physicalSize = const Size(500, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final formKey = GlobalKey<FormState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: PlaceProductEditor(
                  products: products,
                  onChanged: () {},
                  accent: const Color(0xFFFF6FA0),
                ),
              ),
            ),
          ),
        ),
      );
      // 상품 카드는 접힌 채로 열린다 — 펼쳐야 입력칸이 트리에 들어온다.
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pumpAndSettle();
      return formKey;
    }

    // 입력칸의 존재 여부는 환불 UX 스위치 하나가 정한다
    // ([ProductRefundFeature]). 두 상태를 모두 적어 두는 이유는, 나중에
    // 스위치를 다시 켰을 때 이 검사가 그대로 옛 동작을 지켜주기 때문이다.
    if (ProductRefundFeature.enabled) {
      testWidgets('필수 표시가 붙고, 비어 있으면 폼 검증이 막는다', (tester) async {
        final formKey = await pumpEditor(tester, [product(refundPolicy: '')]);

        // 라벨은 Text.rich(라벨 + 빨간 *)로 그려진다.
        expect(
          find.text('${PlaceProductRefundPolicyRule.fieldLabel} *'),
          findsOneWidget,
        );

        // 열자마자 빨간 문구가 뜨지는 않는다 — 열람은 그대로다.
        expect(
          find.text(PlaceProductRefundPolicyRule.requiredMessage),
          findsNothing,
        );

        expect(formKey.currentState!.validate(), isFalse);
        await tester.pumpAndSettle();
        expect(
          find.text(PlaceProductRefundPolicyRule.requiredMessage),
          findsOneWidget,
        );
      });

      testWidgets('내용을 채우면 폼 검증을 통과한다', (tester) async {
        final products = [product(refundPolicy: '')];
        final formKey = await pumpEditor(tester, products);

        expect(formKey.currentState!.validate(), isFalse);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byWidgetPredicate(
            (w) => w is TextFormField && w.key == const ValueKey('취소·환불 규정|0'),
          ),
          '구매 후 7일 이내 전액 환불',
        );
        await tester.pumpAndSettle();

        expect(formKey.currentState!.validate(), isTrue);
        await tester.pumpAndSettle();
        expect(
          find.text(PlaceProductRefundPolicyRule.requiredMessage),
          findsNothing,
        );
      });
    } else {
      testWidgets('환불 UX를 내린 동안에는 입력칸 자체가 없다', (tester) async {
        await pumpEditor(tester, [product(refundPolicy: '')]);

        expect(
          find.text('${PlaceProductRefundPolicyRule.fieldLabel} *'),
          findsNothing,
        );
        expect(
          find.byWidgetPredicate(
            (w) => w is TextFormField && w.key == const ValueKey('취소·환불 규정|0'),
          ),
          findsNothing,
        );
      });

      testWidgets('입력칸이 없으니 폼 검증도 막지 않는다', (tester) async {
        final formKey = await pumpEditor(tester, [product(refundPolicy: '')]);

        expect(formKey.currentState!.validate(), isTrue);
        await tester.pumpAndSettle();
        expect(
          find.text(PlaceProductRefundPolicyRule.requiredMessage),
          findsNothing,
        );
      });

      testWidgets('이미 값이 있는 상품도 화면에 규정을 드러내지 않는다', (tester) async {
        await pumpEditor(tester, [product(refundPolicy: '구매 후 7일 이내 전액 환불')]);

        expect(find.text('구매 후 7일 이내 전액 환불'), findsNothing);
      });
    }
  });
}

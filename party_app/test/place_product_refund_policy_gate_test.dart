// 상품의 '취소·환불 규정' — **등록 화면의 실제 저장 게이트**에서 확인한다.
//
// 입력칸의 validator만으로는 저장이 막히지 않는다(등록 화면들은 Form.validate()
// 결과를 표시용으로만 쓰거나, 아예 Form을 쓰지 않는다). 그래서 화면마다 공용
// 규칙으로 한 번 더 막는다 — 여기서는 플레이스(이벤트) 등록 화면을 띄워 그
// 게이트를 직접 확인한다.
//
//  상품 없음            → 이 안내는 뜨지 않는다(상품 판매는 여전히 선택)
//  상품 추가만 하고 저장 → 막히고 안내가 뜬다
//  규정을 채우고 저장    → 그 안내가 사라진다
//
// 나머지 세 화면(플레이스 등록/수정·파티+숙박·플레이스+파티)은 저장 시작 지점에
// FirebaseAuth를 만져 위젯 테스트로 그 지점까지 갈 수 없다. 대신 규칙을 쓰는지는
// place_product_refund_policy_test.dart의 전수 가드가 본다.

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:party_app/models/place_product.dart';
import 'package:party_app/models/product_refund_feature.dart';
import 'package:party_app/screens/event_register_screen.dart';
import 'package:party_app/utils/user_session.dart';

void main() {
  setUp(() {
    dotenv.testLoad(fileInput: '');
    SharedPreferences.setMockInitialValues({});
    UserSession.userId = 'test-user';
  });
  tearDown(() => UserSession.userId = '');

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: EventRegisterScreen()));
    await tester.pump(const Duration(milliseconds: 300));

    // 제목만 채우면 상품 검사 앞의 관문(제목·기간·시간)을 모두 통과한다
    // (기간은 기본이 '상시 진행', 시간 지정은 기본 꺼짐).
    await tester.enterText(
      find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            (w.decoration?.hintText ?? '') == '예: 키워드 1호점 여성 무료입장',
      ),
      '테스트 플레이스',
    );
    await tester.pumpAndSettle();
  }

  Future<void> scrollAndTap(WidgetTester tester, Finder finder) async {
    // 직전 안내 스낵바가 화면 아래를 덮고 있으면 등록 버튼 탭이 빗나간다.
    ScaffoldMessenger.of(
      tester.element(find.byType(Scaffold).first),
    ).clearSnackBars();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // 저장을 누르면 화면이 **첫 누락 항목으로 스스로 이동**한다(400ms 애니메이션).
    // 그게 끝나기 전에 입력하면 입력칸이 아직 자리를 잡지 않아 글자가 들어가지
    // 않는다 — 다음 조작 전에 그 이동을 먼저 끝낸다.
    await tester.pumpAndSettle();
  }

  bool blocked(WidgetTester tester) => find
      .text(PlaceProductRefundPolicyRule.requiredMessage)
      .evaluate()
      .isNotEmpty;

  testWidgets('상품이 없으면 이 안내는 뜨지 않는다 — 판매는 선택이다', (tester) async {
    await pumpScreen(tester);
    await scrollAndTap(tester, find.text('플레이스 등록하기'));

    expect(blocked(tester), isFalse);
  });

  // 게이트를 켜고 끄는 것은 환불 UX 스위치 하나다([ProductRefundFeature]).
  // 두 상태를 모두 적어 두면, 나중에 스위치를 다시 켰을 때 이 검사가 그대로
  // 옛 동작을 지켜준다.
  if (ProductRefundFeature.enabled) {
    testWidgets('상품을 추가하면 취소·환불 규정을 요구하고, 채우면 통과한다', (tester) async {
      await pumpScreen(tester);

      // 상품을 추가하면 그 카드가 펼쳐진 채로 열린다.
      await scrollAndTap(tester, find.text('상품 추가'));
      await tester.pumpAndSettle();
      expect(
        find.text('${PlaceProductRefundPolicyRule.fieldLabel} *'),
        findsOneWidget,
        reason: '상품 카드가 펼쳐진 채로 추가되지 않았다',
      );

      await scrollAndTap(tester, find.text('플레이스 등록하기'));
      expect(blocked(tester), isTrue, reason: '규정이 비었는데 막히지 않았다');

      await tester.enterText(
        find.byWidgetPredicate(
          (w) =>
              w is TextFormField &&
              w.key == ValueKey('${PlaceProductRefundPolicyRule.fieldLabel}|0'),
        ),
        '구매 후 7일 이내 전액 환불',
      );
      await tester.pumpAndSettle();

      await scrollAndTap(tester, find.text('플레이스 등록하기'));
      expect(blocked(tester), isFalse, reason: '채웠는데 여전히 막힌다');
    });
  } else {
    testWidgets('환불 UX를 내린 동안에는 상품만 추가해도 등록이 막히지 않는다', (tester) async {
      await pumpScreen(tester);

      await scrollAndTap(tester, find.text('상품 추가'));
      await tester.pumpAndSettle();
      // 입력칸이 아예 없다 — 그런데도 저장이 막히면 등록이 불가능해진다.
      expect(
        find.text('${PlaceProductRefundPolicyRule.fieldLabel} *'),
        findsNothing,
      );

      await scrollAndTap(tester, find.text('플레이스 등록하기'));
      expect(blocked(tester), isFalse, reason: '입력할 칸이 없는 항목으로 저장을 막고 있다');
    });
  }
}

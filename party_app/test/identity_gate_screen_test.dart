import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/screens/identity_verification_screen.dart';

/// 본인확인 게이트 화면이 **닫히지 않는다**는 성질을 그대로 못박는다.
///
/// 이 성질이 이번 수정의 핵심이다 — 예전 화면은 평범한 라우트라 안드로이드
/// 뒤로가기·iOS 스와이프로 사라졌고, 그 아래에 이미 MainScreen이 있었다.
/// 누군가 PopScope를 지우면 그 우회가 그대로 돌아오므로 테스트로 붙잡는다.
void main() {
  /// 화면이 직접 세운 PopScope의 canPop — 라우트 내부에도 PopScope가 있어서
  /// (Scaffold를 감싼) 우리 것만 골라낸다.
  bool gateCanPop(WidgetTester tester) {
    final ours =
        tester
                .widgetList<Widget>(
                  find.byWidgetPredicate(
                    (w) => w is PopScope && w.child is Scaffold,
                  ),
                )
                .single
            as PopScope;
    return ours.canPop;
  }

  group('본인확인 화면', () {
    testWidgets('뒤로가기로 닫을 수 없다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: IdentityVerificationScreen()),
      );
      expect(gateCanPop(tester), isFalse);
    });

    testWidgets('빠져나가는 길은 로그아웃뿐이다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: IdentityVerificationScreen()),
      );
      expect(find.text('본인확인이 필요해요'), findsOneWidget);
      expect(find.text('본인확인 시작'), findsOneWidget);
      expect(find.text('로그아웃'), findsOneWidget);
      // '닫기'·'나중에'처럼 인증 없이 통과하는 버튼은 없어야 한다.
      expect(find.text('나중에'), findsNothing);
      expect(find.text('닫기'), findsNothing);
      expect(find.text('건너뛰기'), findsNothing);
    });

    testWidgets('뒤로가기를 누르면 유일한 출구를 알려준다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: IdentityVerificationScreen()),
      );
      // 시스템 뒤로가기와 같은 경로(NavigatorState.maybePop)를 태운다.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      await navigator.maybePop();
      await tester.pump();
      // 화면은 그대로 남아 있고, 안내만 뜬다.
      expect(find.text('본인확인이 필요해요'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('확인 실패 화면', () {
    testWidgets('여기도 닫을 수 없고, 재시도와 로그아웃만 있다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: IdentityCheckFailedScreen()),
      );
      expect(gateCanPop(tester), isFalse);
      expect(find.text('다시 시도'), findsOneWidget);
      expect(find.text('로그아웃'), findsOneWidget);
      // 확인 실패를 '통과'로 바꿔주는 버튼은 없다(fail-closed).
      expect(find.text('계속하기'), findsNothing);
      expect(find.text('나중에'), findsNothing);
    });
  });
}

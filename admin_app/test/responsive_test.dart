// 반응형 기준점(utils/responsive.dart)이 화면 폭에 따라 무엇을 내주는지.
//
// 셸이 사이드바를 Drawer로 접을지, 고정 폭을 풀지가 전부 여기서 갈린다.
// 셸 자체를 띄우는 테스트는 dart:html 때문에 웹 플랫폼에서만 돌 수 있어
// (admin_shell_mobile_test.dart), 판단 규칙은 여기서 VM으로 확인한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partychu_admin/utils/responsive.dart';

/// 지정한 폭에서 [BuildContext]를 꺼내 준다.
Future<BuildContext> _contextAt(WidgetTester tester, double width) async {
  late BuildContext captured;
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(builder: (context) {
        captured = context;
        return const SizedBox.shrink();
      }),
    ),
  );
  return captured;
}

void main() {
  group('사이드바를 접는 기준', () {
    testWidgets('휴대폰 폭에서는 접는다', (tester) async {
      for (final w in [360.0, 390.0, 412.0, 430.0, 899.0]) {
        final context = await _contextAt(tester, w);
        expect(context.isMobileLayout, isTrue, reason: '$w px');
      }
    });

    testWidgets('900px부터는 기존 데스크톱 레이아웃을 그대로 쓴다', (tester) async {
      for (final w in [900.0, 1280.0, 1920.0]) {
        final context = await _contextAt(tester, w);
        expect(context.isMobileLayout, isFalse, reason: '$w px');
        expect(context.isCompact, isFalse, reason: '$w px');
      }
    });
  });

  group('fluid — 고정 폭을 본문 폭 안으로 들인다', () {
    testWidgets('좁으면 본문 폭까지 줄이고, 넓으면 원래 값 그대로', (tester) async {
      final narrow = await _contextAt(tester, 360);
      // 360 - 좌우 여백 16*2 = 328
      expect(narrow.contentMaxWidth, 328);
      expect(narrow.fluid(460), 328);
      expect(narrow.fluid(320), 320);

      final wide = await _contextAt(tester, 1440);
      // 1440 - 사이드바 232 - 여백 28*2 = 1152
      expect(wide.contentMaxWidth, 1152);
      expect(wide.fluid(460), 460, reason: 'PC에서는 디자인 폭이 그대로여야 한다');
      expect(wide.fluid(320), 320);
    });

    testWidgets('다이얼로그는 화면 밖으로 나가지 않는다', (tester) async {
      final narrow = await _contextAt(tester, 360);
      expect(narrow.dialogWidth(760), lessThanOrEqualTo(360));
      expect(narrow.dialogWidth(420), lessThanOrEqualTo(360));

      final wide = await _contextAt(tester, 1440);
      expect(wide.dialogWidth(760), 760);
    });
  });

  group('ResponsiveRow', () {
    testWidgets('좁으면 세로로 쌓고 넓으면 가로로 나란히 둔다', (tester) async {
      Widget build() => ResponsiveRow(children: [
            const SizedBox(key: ValueKey('a'), height: 10),
            const SizedBox(key: ValueKey('b'), height: 10),
          ]);

      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: build())));
      expect(find.byType(Column), findsWidgets);
      expect(find.byType(Expanded), findsNothing);

      tester.view.physicalSize = const Size(1440, 900);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: build())));
      await tester.pump();
      expect(find.byType(Expanded), findsNWidgets(2));
    });
  });
}

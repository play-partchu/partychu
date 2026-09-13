// 필수항목 누락 안내 → **그 입력칸으로 실제 이동**까지를 못 박는다.
//
// 고친 사고: 등록 화면 본문은 [ListView]인데, ListView는 화면 밖 항목을 아예
// 만들지 않는다. 그래서 아래쪽 섹션의 앵커는 `currentContext`가 null이었고,
// 배너의 '상품의 취소·환불 규정을 입력해주세요.'를 눌러도 넘길 것이 없어
// **아무 일도 일어나지 않았다**. 눈으로는 "눌러도 안 움직인다"로만 보인다.
//
// 그래서 여기서는 실제로 긴 ListView를 세우고, 화면 밖 앵커를 눌러 그 위젯이
// 만들어지고 보이는 자리까지 오는지를 좌표로 확인한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/utils/register_validation.dart';
import 'package:party_app/widgets/party_form/register_field_anchor.dart';
import 'package:party_app/widgets/party_form/register_missing_fields_banner.dart';

void main() {
  final farKey = GlobalKey();
  final nearKey = GlobalKey();

  // 강조 타이머는 화면이 사라져도 살아 있으면 안 된다 — 실제 화면도 같은
  // 이유로 dispose에서 끈다.
  tearDown(RegisterValidation.clearHighlight);

  /// 강조가 저절로 꺼질 때까지 흘려보낸다 — 남겨 두면 테스트 뒷정리에서
  /// "타이머가 살아 있다"로 걸린다(그게 곧 실제 앱에서도 남는다는 뜻이다).
  Future<void> drainHighlight(WidgetTester tester) async {
    await tester.pump(RegisterValidation.highlightDuration);
    await tester.pumpAndSettle();
  }

  /// 실제 등록 화면과 같은 모양 — 위에 배너, 아래로 긴 ListView.
  Widget harness({
    required List<RegisterFieldCheck> missing,
    required ScrollController ctrl,
    bool revealed = false,
    VoidCallback? onReveal,
  }) => MaterialApp(
    home: Scaffold(
      body: ListView(
        controller: ctrl,
        children: [
          RegisterMissingFieldsBanner(fields: missing),
          RegisterFieldAnchor(
            key: nearKey,
            child: Container(height: 120, color: Colors.blue.shade50),
          ),
          // 화면 밖으로 한참 밀어내는 더미 — ListView가 아래를 만들지 않게 한다.
          for (var i = 0; i < 12; i++)
            SizedBox(height: 300, child: Text('칸 $i')),
          // 접혀 있는 섹션 안의 입력칸 — 펼치기 전에는 트리에 없다.
          if (revealed)
            RegisterFieldAnchor(
              key: farKey,
              child: Container(height: 90, color: Colors.pink.shade50),
            ),
          const SizedBox(height: 400),
        ],
      ),
    ),
  );

  testWidgets('화면 밖 항목을 눌러도 그 자리로 온다 — 예전엔 아무 일도 없었다', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final ctrl = ScrollController();
    addTearDown(ctrl.dispose);
    var revealed = false;

    late StateSetter setOuter;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          setOuter = setState;
          return harness(
            ctrl: ctrl,
            revealed: revealed,
            missing: [
              RegisterFieldCheck(
                missing: true,
                message: '상품의 취소·환불 규정을 입력해주세요.',
                anchorKey: farKey,
                // 접힌 섹션이면 먼저 펼친다.
                reveal: () => setOuter(() => revealed = true),
                scrollController: ctrl,
              ),
            ],
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    // 아직 화면 밖이라 만들어지지도 않았다 — 이 상태가 버그의 출발점이었다.
    expect(farKey.currentContext, isNull);

    await tester.tap(find.text('상품의 취소·환불 규정을 입력해주세요.'));
    await tester.pumpAndSettle();

    // ① 접혀 있던 섹션이 펼쳐졌고, ② 위젯이 만들어졌으며, ③ 화면 안에 있다.
    expect(revealed, isTrue, reason: '접힌 섹션을 먼저 펼쳐야 한다');
    expect(farKey.currentContext, isNotNull, reason: '위젯이 만들어지지 않았다');
    final rect = tester.getRect(find.byKey(farKey));
    expect(rect.top, greaterThanOrEqualTo(0.0));
    expect(rect.bottom, lessThanOrEqualTo(800.0), reason: '화면 안으로 들어오지 않았다');

    await drainHighlight(tester);
  });

  testWidgets('도착한 영역을 잠깐 강조한다', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final ctrl = ScrollController();
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(
      harness(
        ctrl: ctrl,
        missing: [
          RegisterFieldCheck(
            missing: true,
            message: '주소를 입력해주세요.',
            anchorKey: nearKey,
            scrollController: ctrl,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(RegisterValidation.highlightRequest.value, isNull);

    await tester.tap(find.text('주소를 입력해주세요.'));
    await tester.pumpAndSettle();

    expect(
      RegisterValidation.highlightRequest.value?.anchorKey,
      same(nearKey),
      reason: '도착한 앵커가 강조 대상이어야 한다',
    );
    // 강조 테두리가 실제로 그려졌는지 — 요청만 세워 두고 안 그리면 소용없다.
    final decorated = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byKey(nearKey),
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect(
      (decorated.decoration as BoxDecoration).border!.top.color,
      const Color(0xFFFF6FA0),
    );

    // 잠시 뒤 저절로 꺼진다 — 강조가 계속 남아 있으면 오류처럼 읽힌다.
    await drainHighlight(tester);
    final faded = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byKey(nearKey),
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect(
      (faded.decoration as BoxDecoration).border!.top.color,
      Colors.transparent,
    );
  });

  testWidgets('키보드가 열려 있으면 먼저 내리고 이동한다', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final ctrl = ScrollController();
    addTearDown(ctrl.dispose);
    final focus = FocusNode();
    addTearDown(focus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: ctrl,
            children: [
              RegisterMissingFieldsBanner(
                fields: [
                  RegisterFieldCheck(
                    missing: true,
                    message: '주소를 입력해주세요.',
                    anchorKey: nearKey,
                    scrollController: ctrl,
                  ),
                ],
              ),
              TextField(focusNode: focus),
              RegisterFieldAnchor(
                key: nearKey,
                child: Container(height: 120, color: Colors.blue.shade50),
              ),
              const SizedBox(height: 1200),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(focus.hasPrimaryFocus, isTrue);

    await tester.tap(find.text('주소를 입력해주세요.'));
    await tester.pumpAndSettle();

    expect(focus.hasPrimaryFocus, isFalse, reason: '키보드를 먼저 내려야 위치가 안 어긋난다');

    await drainHighlight(tester);
  });

  testWidgets('배너는 누락 항목을 전부 보여주고, 각 줄이 누를 수 있다', (tester) async {
    final ctrl = ScrollController();
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(
      harness(
        ctrl: ctrl,
        missing: [
          RegisterFieldCheck(missing: true, message: '주소를 입력해주세요.'),
          RegisterFieldCheck(missing: true, message: '모집 인원을 입력해주세요.'),
          RegisterFieldCheck(missing: true, message: '상품의 취소·환불 규정을 입력해주세요.'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('아직 입력하지 않은 필수 항목이 3개 있어요'), findsOneWidget);
    expect(find.text('항목을 누르면 해당 입력칸으로 이동해요.'), findsOneWidget);
    for (final m in [
      '주소를 입력해주세요.',
      '모집 인원을 입력해주세요.',
      '상품의 취소·환불 규정을 입력해주세요.',
    ]) {
      expect(find.text(m), findsOneWidget, reason: m);
    }
    // 세 줄 모두 눌러서 이동할 수 있어야 한다(문구만 띄우고 끝나면 안 된다).
    expect(find.byType(InkWell), findsNWidgets(3));
  });
}

// 🧨 파티샵 등록 > 상품 추가 시트 — **키보드 + 뒤로가기**에서 터지던 회귀.
//
// ── 사용자가 본 것 ───────────────────────────────────────────────────────────
// 상품명/상품 설명을 누르면 삼성 키보드 레이아웃이 흐트러지고, 키보드가 열린
// 채로 시스템 뒤로가기를 누르면 빨간 화면이 떴다:
//
//     framework.dart:6268  Failed assertion: '_dependents.isEmpty': is not true
//
// ── 실제 원인 (예외는 두 개였고, 앞의 것이 진짜다) ───────────────────────────
// ① A TextEditingController was used after being disposed.
//      ↳ _AnimatedState.didUpdateWidget → _MergingListenable.addListener
//      ↳ (앱 코드) party_market_register_screen.dart `_showAddProductSheet`의
//        `showModalBottomSheet(...).whenComplete(() { namec.dispose(); ... })`
//
//    그 future는 [Navigator.pop]이 불린 **순간** 끝난다. 시트는 그때부터 닫히는
//    애니메이션을 시작하므로 아직 화면에 있고 매 프레임 다시 그려진다 — 이미
//    버린 컨트롤러를 TextField가 다시 구독하다 터졌다.
//
// ② '_dependents.isEmpty' — ①로 빌드가 중간에 끊기면서 의존자를 등록한 자식이
//    남은 채 라우트가 비활성화돼 뒤이어 터진 것. 사용자에게 보이던 빨간 화면은
//    이쪽이지만, 고쳐야 할 곳은 ①이다.
//
// 주문제작 기능과는 **무관하다** — 아래 '대조군'이 그 코드를 하나도 쓰지 않고
// 같은 패턴만으로 두 예외를 똑같이 재현한다.
//
// ── 고친 방식 ────────────────────────────────────────────────────────────────
// 수명을 위젯에 맡긴다([_DisposeOnUnmount]) — [State.dispose]는 엘리먼트가
// 트리에서 완전히 빠진 뒤에 불리고, 그 뒤로는 다시 그려질 일이 없다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:io';

import 'package:party_app/screens/party_market_register_screen.dart';
import 'package:party_app/utils/user_session.dart';

const Size _screen = Size(390, 844);

/// 시트 안 상품명/상품 설명 TextField를 가리키는 힌트 문구.
const String _nameHint = '예: 생일 케이크';
const String _descHint = '상품 설명 (선택)';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UserSession.userId = 'test-user';
  });
  tearDown(() => UserSession.userId = '');

  // pumpAndSettle을 쓰지 않는다 — 등록 화면에는 계속 도는 애니메이션이 있어
  // 영영 멈추지 않는다. 프레임을 정해진 수만큼 흘려보낸다.
  Future<void> settle(WidgetTester tester, {int frames = 40}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> openSheet(WidgetTester tester) async {
    tester.view.physicalSize = _screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: PartyMarketRegisterScreen()),
    );
    await settle(tester, frames: 20);

    final add = find.text('상품 추가').first;
    await tester.ensureVisible(add);
    await tester.tap(add, warnIfMissed: false);
    await settle(tester);
    expect(find.text('상품명'), findsOneWidget, reason: '시트가 열리지 않았다');
  }

  /// 키보드가 올라온 상태를 흉내 낸다 — 시트 높이가 viewInsets를 읽으므로
  /// 이 값이 바뀌면 시트가 매 프레임 다시 그려진다(터지던 조건 그대로).
  Future<void> showKeyboard(WidgetTester tester) async {
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await settle(tester, frames: 10);
  }

  Future<void> hideKeyboard(WidgetTester tester) async {
    tester.view.viewInsets = FakeViewPadding.zero;
    await settle(tester, frames: 10);
  }

  /// 안드로이드 시스템 뒤로가기 한 번.
  Future<void> systemBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await settle(tester);
  }

  Finder field(String hint) => find.widgetWithText(TextField, hint);

  /// 한 칸에 포커스를 주고 글자를 넣는다.
  Future<void> focusAndType(
    WidgetTester tester,
    String hint,
    String text,
  ) async {
    await tester.tap(field(hint));
    await settle(tester, frames: 10);
    await tester.enterText(field(hint), text);
    await settle(tester, frames: 10);
  }

  Future<void> toggleMadeToOrder(WidgetTester tester) async {
    await tester.ensureVisible(find.text('주문제작'));
    await tester.tap(find.text('주문제작'));
    await settle(tester, frames: 10);
  }

  // ── ① 상품명 ───────────────────────────────────────────────────────────
  testWidgets('상품명 포커스 → 키보드 → 뒤로가기 — 예외 0', (tester) async {
    await openSheet(tester);
    await focusAndType(tester, _nameHint, '레터링 케이크');
    await showKeyboard(tester);

    await systemBack(tester);
    await hideKeyboard(tester);

    expect(tester.takeException(), isNull);
    // 시트는 닫혔고 화면은 살아 있다.
    expect(find.text('상품명'), findsNothing);
    expect(find.byType(PartyMarketRegisterScreen), findsOneWidget);
  });

  // ── ② 상품 설명 ────────────────────────────────────────────────────────
  testWidgets('상품 설명 포커스 → 키보드 → 뒤로가기 — 예외 0', (tester) async {
    await openSheet(tester);
    await focusAndType(tester, _descHint, '수제 디저트예요');
    await showKeyboard(tester);

    await systemBack(tester);
    await hideKeyboard(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('상품명'), findsNothing);
  });

  // ── ③ 주문제작 ON ──────────────────────────────────────────────────────
  testWidgets('주문제작 ON 상태에서 포커스 → 뒤로가기 — 예외 0', (tester) async {
    await openSheet(tester);
    await toggleMadeToOrder(tester);
    // 재고 칸이 비활성이 되며 포커스 트리가 바뀌는 순간이 지나야 한다.
    await focusAndType(tester, _nameHint, '도시락 케이크');
    await showKeyboard(tester);

    await systemBack(tester);
    await hideKeyboard(tester);

    expect(tester.takeException(), isNull);
  });

  // ── ④ 주문제작 OFF(켰다 껐다) ──────────────────────────────────────────
  testWidgets('주문제작 켰다 끈 뒤 포커스 → 뒤로가기 — 예외 0', (tester) async {
    await openSheet(tester);
    await toggleMadeToOrder(tester); // ON
    await toggleMadeToOrder(tester); // OFF
    await focusAndType(tester, _nameHint, '컵케이크');
    await showKeyboard(tester);

    await systemBack(tester);
    await hideKeyboard(tester);

    expect(tester.takeException(), isNull);
  });

  // ── ⑤ 키보드를 먼저 닫고 시트 닫기 ─────────────────────────────────────
  testWidgets('키보드를 닫은 뒤 시트 닫기 — 예외 0', (tester) async {
    await openSheet(tester);
    await focusAndType(tester, _nameHint, '쿠키 세트');
    await showKeyboard(tester);

    // 실제 기기의 순서: 뒤로가기 1회는 키보드만 닫고(OS가 먹는다),
    // 2회째가 시트를 닫는다.
    await hideKeyboard(tester);
    expect(tester.takeException(), isNull);

    await systemBack(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('상품명'), findsNothing);
  });

  // ── ⑥ 입력값 유지 + 재진입 ─────────────────────────────────────────────
  testWidgets('키보드가 오르내려도 입력값이 남는다', (tester) async {
    await openSheet(tester);
    await focusAndType(tester, _nameHint, '레터링 케이크');
    await focusAndType(tester, _descHint, '주문 후 제작해요');
    await showKeyboard(tester);
    await hideKeyboard(tester);

    expect(find.text('레터링 케이크'), findsOneWidget);
    expect(find.text('주문 후 제작해요'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('시트를 닫았다 다시 열면 빈 칸으로 새로 시작한다', (tester) async {
    await openSheet(tester);
    await focusAndType(tester, _nameHint, '첫 번째 상품');
    await showKeyboard(tester);
    await systemBack(tester);
    await hideKeyboard(tester);
    expect(tester.takeException(), isNull);

    // 재진입 — 지난번 컨트롤러는 버려졌고 새 컨트롤러가 붙는다.
    final add = find.text('상품 추가').first;
    await tester.ensureVisible(add);
    await tester.tap(add, warnIfMissed: false);
    await settle(tester);

    expect(find.text('상품명'), findsOneWidget);
    expect(find.text('첫 번째 상품'), findsNothing, reason: '지난 입력이 남았다');

    // 새 컨트롤러가 멀쩡히 동작한다(버려진 컨트롤러를 다시 쓰면 여기서 터진다).
    await focusAndType(tester, _nameHint, '두 번째 상품');
    expect(find.text('두 번째 상품'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ── 두 예외의 문구를 직접 못박는다 ─────────────────────────────────────
  //
  // 위 검사들은 `takeException()`으로 "예외가 없다"만 본다. 여기서는 흐름
  // 전체에서 [FlutterError]로 올라오는 **모든** 메시지를 모아, 사용자가 봤던
  // 두 문구가 하나도 없는지 이름으로 확인한다 — 다른 예외로 바뀌어도 잡힌다.
  testWidgets('전 과정에서 그 두 예외가 한 번도 나지 않는다', (tester) async {
    final caught = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      caught.add(details.exception.toString());
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);

    // 상품명 → 설명 → 주문제작 ON → OFF → 키보드 → 뒤로가기 → 재진입.
    await openSheet(tester);
    await focusAndType(tester, _nameHint, '레터링 케이크');
    await focusAndType(tester, _descHint, '주문 후 제작해요');
    await toggleMadeToOrder(tester);
    await showKeyboard(tester);
    await toggleMadeToOrder(tester);
    await systemBack(tester);
    await hideKeyboard(tester);

    final add = find.text('상품 추가').first;
    await tester.ensureVisible(add);
    await tester.tap(add, warnIfMissed: false);
    await settle(tester);
    await focusAndType(tester, _nameHint, '두 번째 상품');
    await systemBack(tester);

    final all = caught.join('\n');
    expect(
      all.contains('A TextEditingController was used after being disposed'),
      isFalse,
      reason: all,
    );
    expect(all.contains('_dependents.isEmpty'), isFalse, reason: all);
    expect(caught, isEmpty, reason: all);
  });

  // ── 대조군: 원인이 주문제작이 아니라 **수명 패턴**임을 못박는다 ─────────
  testWidgets('대조군 — 같은 패턴이면 주문제작 없이도 똑같이 터진다', (tester) async {
    // 일부러 터뜨리는 검사라 예외를 **직접 받는다** — 그냥 두면 테스트 바인딩이
    // "예상치 못한 예외"로 잡아 이 검사 자체가 실패한다(여러 개가 연달아 난다).
    final caught = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) =>
        caught.add(details.exception.toString());
    addTearDown(() => FlutterError.onError = previous);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () {
                final c = TextEditingController();
                showModalBottomSheet(
                  context: ctx,
                  isScrollControlled: true,
                  builder: (_) =>
                      SizedBox(height: 300, child: TextField(controller: c)),
                  // ⚠️ 고치기 전의 그 패턴 — pop이 불린 순간 버린다.
                ).whenComplete(c.dispose);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await systemBack(tester);

    // 주문제작 코드가 한 줄도 없는데 사용자가 본 두 예외가 순서까지 그대로 난다.
    final all = caught.join('\n');
    expect(
      all.contains('A TextEditingController was used after being disposed'),
      isTrue,
      reason: all,
    );
    expect(all.contains('_dependents.isEmpty'), isTrue, reason: all);
  });

  // ── 소스 가드: 그 패턴으로 되돌아가지 않게 ─────────────────────────────
  test('상품 추가 시트가 whenComplete로 컨트롤러를 버리지 않는다', () {
    final src = File(
      'lib/screens/party_market_register_screen.dart',
    ).readAsStringSync();
    final flat = src.replaceAll(RegExp(r'\s+'), ' ');

    // 수명은 위젯이 쥔다.
    expect(flat.contains('builder: (ctx) => _DisposeOnUnmount('), isTrue);
    expect(
      flat.contains('void dispose() { widget.onDispose(); super.dispose(); }'),
      isTrue,
    );
    // 코드에서 `.whenComplete(`가 되살아나면 실패한다(주석의 언급은 제외).
    final code = src
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    expect(code.contains('.whenComplete('), isFalse);
  });

  test('시트 크기는 시트 자신의 context로 잰다', () {
    final flat = File(
      'lib/screens/party_market_register_screen.dart',
    ).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
    // 바깥 화면의 context로 재면 키보드가 오르내릴 때마다 등록 화면 전체가
    // 다시 그려진다(삼성 키보드 레이아웃이 흐트러지던 쪽).
    expect(flat.contains('MediaQuery.of(ctx).size.height * 0.85'), isTrue);
    expect(flat.contains('MediaQuery.of(context).size.height * 0.85'), isFalse);
  });
}

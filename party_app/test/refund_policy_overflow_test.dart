import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/screens/party_refund_policy_screen.dart';
import 'package:party_app/utils/refund_policy.dart';
import 'package:party_app/widgets/place_form/room_card.dart';
import 'package:party_app/widgets/refund_policy_editor.dart';

// 환불 규정 편집 — 구간을 아무리 많이 추가해도, 키보드가 올라온 상태에서도
// 오버플로(BOTTOM OVERFLOWED BY XX PIXELS)가 나지 않아야 한다.
//
// 위젯 테스트에서 RenderFlex 오버플로는 FlutterError로 보고되므로
// tester.takeException()으로 잡을 수 있다 — 화면을 일부러 작게 잡고(작은 폰)
// 구간을 30개까지 늘려가며 매번 확인한다.

/// 작은 화면(폭 390 × 높이 640, dpr 1)으로 고정 — 구간 몇 개만 넣어도 세로가
/// 모자라는 조건이라 오버플로가 있으면 바로 드러난다.
void _useSmallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetViewInsets();
  });
}

/// 소프트 키보드가 올라온 상태를 흉내낸다(높이 300).
void _showKeyboard(WidgetTester tester) {
  tester.view.viewInsets = const FakeViewPadding(bottom: 300);
}

Finder get _addButton => find.widgetWithText(OutlinedButton, '구간 추가');

/// 세로 스크롤 뷰만 고른다 — 한 줄짜리 입력칸(EditableText)도 내부에
/// Scrollable을 갖고 있어서 그냥 byType(Scrollable)로는 구분되지 않는다.
Finder get _verticalScrollables => find.byWidgetPredicate(
  (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
);

/// 구간 목록은 지연 생성(SliverList)이라 "구간 추가" 버튼이 아직 트리에
/// 없을 수 있다 — 보일 때까지 스크롤한다.
Future<void> _scrollToAddButton(WidgetTester tester, Finder list) async {
  await tester.scrollUntilVisible(_addButton, 300, scrollable: list);
  await tester.pumpAndSettle();
}

Future<void> _tapAdd(WidgetTester tester, Finder list) async {
  await _scrollToAddButton(tester, list);
  await tester.tap(_addButton);
  await tester.pumpAndSettle();
}

void main() {
  group('환불 규정 화면(PartyRefundPolicyScreen)', () {
    Finder list() => _verticalScrollables.first;

    Future<void> pumpScreen(
      WidgetTester tester, {
      required List<RefundTier> initial,
      ValueChanged<List<RefundTier>>? onChanged,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PartyRefundPolicyScreen(
            initialTiers: initial,
            onChanged: onChanged ?? (_) {},
          ),
        ),
      );
    }

    testWidgets('구간을 30개 추가해도 오버플로가 없다', (tester) async {
      _useSmallScreen(tester);
      var tiers = <RefundTier>[];
      await pumpScreen(tester, initial: const [], onChanged: (v) => tiers = v);

      for (var i = 0; i < 30; i++) {
        await _tapAdd(tester, list());
        expect(
          tester.takeException(),
          isNull,
          reason: '구간 ${i + 1}개에서 오버플로가 발생했습니다',
        );
      }

      expect(tiers.length, 30);
      // 지연 생성이라 30개가 전부 트리에 있진 않다 — 이게 오버플로가 없는 이유다.
      expect(find.byType(TextFormField), findsAtLeast(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('키보드가 올라온 상태에서도 오버플로가 없고 버튼까지 스크롤된다', (tester) async {
      _useSmallScreen(tester);
      await pumpScreen(
        tester,
        initial: List.generate(
          25,
          (i) => RefundTier(daysBefore: i + 1, refundPercent: 50),
        ),
      );
      expect(tester.takeException(), isNull);

      _showKeyboard(tester);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 키보드가 올라온 상태에서도 마지막 "구간 추가" 버튼까지 스크롤로 닿는다.
      await _scrollToAddButton(tester, list());
      expect(tester.takeException(), isNull);
      expect(_addButton.hitTestable(), findsOneWidget);
    });

    testWidgets('입력칸을 누르면 키보드가 올라와도 그 구간이 화면에 남는다', (tester) async {
      _useSmallScreen(tester);
      await pumpScreen(
        tester,
        initial: List.generate(
          20,
          (i) => RefundTier(daysBefore: i + 1, refundPercent: 10),
        ),
      );

      // 목록 아래쪽까지 스크롤한 뒤 거기 보이는 입력칸에 포커스를 준다.
      await _scrollToAddButton(tester, list());
      final field = find.byType(TextFormField).last;
      await tester.tap(field);
      await tester.pumpAndSettle();

      _showKeyboard(tester);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // 포커스된 입력칸이 키보드에 가려지지 않고 눌리는 위치에 남아 있다.
      expect(field.hitTestable(), findsOneWidget);
    });

    testWidgets('구간이 없어도 안내 문구가 보이고 오버플로가 없다', (tester) async {
      _useSmallScreen(tester);
      await pumpScreen(tester, initial: const []);
      expect(find.text('등록된 환불 구간이 없어요'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('룸 환불 규정 시트(RoomCard)', () {
    testWidgets('시트에서 구간을 25개 추가해도 오버플로가 없다', (tester) async {
      _useSmallScreen(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RoomCard(index: 0, onRemove: () {}),
            ),
          ),
        ),
      );

      await tester.ensureVisible(find.text('환불 규정 설정 (선택)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('환불 규정 설정 (선택)'));
      await tester.pumpAndSettle();

      final done = find.widgetWithText(ElevatedButton, '완료');
      expect(done, findsOneWidget); // 시트가 열렸다
      // 시트의 목록은 화면 트리에서 나중에 오므로 마지막 세로 스크롤 뷰다.
      Finder sheetList() => _verticalScrollables.last;

      for (var i = 0; i < 25; i++) {
        await _tapAdd(tester, sheetList());
        expect(
          tester.takeException(),
          isNull,
          reason: '시트에서 구간 ${i + 1}개일 때 오버플로가 발생했습니다',
        );
      }

      // 구간이 몇 개든 시트가 화면을 넘지 않아 "완료" 버튼이 계속 눌린다.
      expect(done.hitTestable(), findsOneWidget);

      _showKeyboard(tester);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(done.hitTestable(), findsOneWidget);
    });
  });

  group('바깥 스크롤 뷰에 끼워 넣는 배치(scrollable: false)', () {
    testWidgets('스크롤 뷰가 중첩되지 않고 Column으로만 그려진다', (tester) async {
      _useSmallScreen(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: RefundPolicyEditor(
                initialTiers: List.generate(
                  20,
                  (i) => RefundTier(daysBefore: i, refundPercent: 100),
                ),
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      // 에디터가 스크롤 뷰를 더 만들지 않는다(바깥 것 하나뿐).
      expect(find.byType(CustomScrollView), findsNothing);
      expect(_verticalScrollables, findsOneWidget);
      // Column 배치라 20개 구간이 모두 트리에 있다(지연 생성 아님).
      expect(find.byType(TextFormField), findsNWidgets(40));
    });
  });
}

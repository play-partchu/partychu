// 파티 상세검색 시트의 **밀도** — 같은 정보를 더 촘촘하게.
//
// 시트가 거의 전체화면인데도 카드·섹션 사이 여백이 커서 빈 자리가 많이 보였다.
// 글자를 줄이거나 문구를 빼는 대신 padding/gap만 좁혔으므로, 이 테스트가 보는
// 것은 셋이다.
//
//  1. **아무것도 사라지지 않았다** — 아홉 칸 제목, 토글 둘의 제목과 설명,
//     전체 초기화, 검색 버튼 문구가 모두 그대로 있다.
//  2. **더 촘촘해졌다** — 아홉 칸 격자와 토글 두 장이 예산 안에 들어온다.
//     여백을 다시 키우면 이 예산이 먼저 깨진다.
//  3. **작아지면 안 되는 것은 그대로다** — 검색어 입력칸과 검색 버튼의
//     터치 높이, 그리고 작은 화면에서 overflow가 없다는 것.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/party_filter.dart';
import 'package:party_app/widgets/detail_search_sheet.dart';
import 'package:party_app/widgets/filter_sheet_ui.dart';
import 'package:party_app/widgets/main/search_entry_sheet.dart';

void main() {
  const gridTitles = ['지역', '성별', '연령', '참가비', '파티 유형·분위기'];

  FlutterErrorDetails? firstError;
  void Function(FlutterErrorDetails)? prevOnError;

  setUp(() {
    firstError = null;
    prevOnError = FlutterError.onError;
    FlutterError.onError = (d) => firstError ??= d;
  });
  tearDown(() => FlutterError.onError = prevOnError);

  void assertNoOverflow(String step) {
    if (firstError == null) return;
    fail('[$step] 예외/오버플로가 났다\n${firstError!.exception}');
  }

  Future<void> pumpSheet(
    WidgetTester tester, {
    Size screen = const Size(360, 640),
    double textScale = 1.0,
    SearchEntryConfig? search,
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showModalBottomSheet<PartyFilter>(
                context: context,
                isScrollControlled: true,
                builder: (_) => DetailSearchSheet(
                  initialFilter: PartyFilter(),
                  search: search,
                ),
              ),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  Rect cardRectOf(WidgetTester tester, String title) => tester.getRect(
    find
        .ancestor(
          of: find.text(title).first,
          matching: find.byType(FilterScaleTap),
        )
        .first,
  );

  /// 토글 카드 한 장이 차지한 자리 — 카드 Container로 잡는다.
  Rect toggleRectOf(WidgetTester tester, String title) => tester.getRect(
    find.ancestor(of: find.text(title), matching: find.byType(Container)).first,
  );

  group('정보는 하나도 빠지지 않았다', () {
    testWidgets('아홉 칸 제목·토글 문구·버튼이 모두 그대로 있다', (tester) async {
      await pumpSheet(tester);

      for (final t in gridTitles) {
        expect(find.text(t), findsWidgets, reason: t);
      }
      expect(find.text('얼리버드 진행중만 보기'), findsOneWidget);
      expect(find.text('내가 참여 가능한 파티만 보기'), findsOneWidget);
      // 설명 문구도 줄이지 않았다.
      expect(
        find.text('성별·연령 조건과 모집 마감 여부를 반영해 실제로 신청 가능한 파티만 보여줘요.'),
        findsOneWidget,
      );
      expect(find.text('전체 초기화'), findsWidgets);
      expect(find.text('적용하기'), findsOneWidget);
      assertNoOverflow('기본 상태');
    });
  });

  group('더 촘촘해졌다', () {
    // ⚠️ 아래 예산을 늘려야 할 만큼 여백을 되돌리는 변경은, 시트가 다시
    //    길어진다는 뜻이다. 항목이 늘어난 게 아니라면 예산부터 의심할 것.

    testWidgets('다섯 칸 격자가 세 줄 예산 안에 들어온다', (tester) async {
      await pumpSheet(tester);

      final top = cardRectOf(tester, '지역').top;
      final bottom = cardRectOf(tester, '파티 유형·분위기').bottom;
      final gridHeight = bottom - top;

      // 2열이라 세 줄(2 + 2 + 1)이다. 카드 한 장 49 + 줄 간격 4 → 159.
      // 3열 시절보다 카드가 커진 만큼(폭이 1/2로 넓어져 여백·아이콘을 키웠다)
      // 격자는 조금 길지만, 시트 전체는 내용 높이로 열려 오히려 짧아졌다.
      expect(
        gridHeight,
        lessThanOrEqualTo(165.0),
        reason: '격자가 예산보다 길어졌다: $gridHeight',
      );
      // 너무 눌려 글자가 겹치는 것도 막는다 — 두 줄짜리 카드의 하한.
      expect(cardRectOf(tester, '지역').height, greaterThanOrEqualTo(40.0));
      assertNoOverflow('격자 높이');
    });

    testWidgets('토글 두 장이 합쳐 예산 안에 들어온다', (tester) async {
      await pumpSheet(tester);

      final early = toggleRectOf(tester, '얼리버드 진행중만 보기');
      final eligible = toggleRectOf(tester, '내가 참여 가능한 파티만 보기');
      final block = eligible.bottom - early.top;

      // 지금은 64.5 + 8(카드 사이) + 64.5 ≈ 137. 두 장의 높이가 같아졌는데도
      // 예전(129, 높이가 서로 달랐다)에서 거의 늘지 않았다.
      // 문구는 한 글자도 줄이지 않았다.
      expect(
        block,
        lessThanOrEqualTo(145.0),
        reason: '토글 두 장이 예산보다 길어졌다: $block',
      );
      // 스위치가 눌리지 않을 만큼 납작해지는 것도 막는다.
      expect(early.height, greaterThanOrEqualTo(40.0));
      assertNoOverflow('토글 높이');
    });

    testWidgets('시트가 처음 열릴 때 화면을 거의 다 덮지는 않는다', (tester) async {
      const screen = Size(360, 640);
      await pumpSheet(tester, screen: screen);

      final sheetTop = tester.getRect(find.byType(DetailSearchSheet)).top;
      // initialChildSize 0.82 — 예전 0.9보다 뒤 화면이 더 보인다.
      expect(sheetTop, greaterThan(screen.height * 0.1));
      assertNoOverflow('시트 높이');
    });
  });

  group('글자는 오히려 커졌다', () {
    // "글씨를 줄여서 카드를 낮춘" 것이 아님을 못 박는다 — 항목명과 선택값
    // 글자는 예전(12 / 11.5)보다 크고, 카드는 오히려 낮아졌다.
    testWidgets('항목명 13 · 선택값 12.5', (tester) async {
      await pumpSheet(tester);

      final title = tester.widget<Text>(find.text('지역').first);
      expect(title.style?.fontSize, greaterThanOrEqualTo(13.0));

      final card = find
          .ancestor(of: find.text('지역').first, matching: find.byType(Column))
          .first;
      final summary = find
          .descendant(of: card, matching: find.byType(Text))
          .evaluate()
          .map((e) => e.widget as Text)
          .firstWhere((t) => t.data == '전체');
      expect(summary.style?.fontSize, greaterThanOrEqualTo(12.5));
      assertNoOverflow('글자 크기');
    });
  });

  group('작아지면 안 되는 것', () {
    testWidgets('검색 버튼 높이는 그대로 56이다', (tester) async {
      await pumpSheet(tester);
      final apply = tester.getRect(
        find
            .ancestor(
              of: find.text('적용하기'),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      expect(apply.height, greaterThanOrEqualTo(56.0));
    });

    testWidgets('검색어 입력칸은 눌러도 될 만큼 남아 있다', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpSheet(
        tester,
        search: SearchEntryConfig(
          title: '파티 검색',
          hintText: '파티 이름을 검색해보세요',
          controller: controller,
          onQueryChanged: (_) {},
        ),
      );

      final field = tester.getRect(find.byType(SearchEntryField));
      // 여백을 줄였어도 권장 최소 터치 높이(48)는 지킨다.
      expect(
        field.height,
        greaterThanOrEqualTo(48.0),
        reason: '검색칸이 너무 눌렸다: ${field.height}',
      );
      assertNoOverflow('검색칸');
    });
  });

  group('작은 화면에서도 넘치지 않는다', () {
    testWidgets('320×480에서 overflow가 없다', (tester) async {
      await pumpSheet(tester, screen: const Size(320, 480));
      assertNoOverflow('320×480');
    });

    testWidgets('글자 크기를 키워도 overflow가 없다', (tester) async {
      await pumpSheet(tester, screen: const Size(320, 480), textScale: 1.4);
      assertNoOverflow('320×480 · 글자 1.4배');
    });

    testWidgets('넘치는 만큼은 세로로 스크롤된다 — 마지막 토글까지 닿는다', (tester) async {
      await pumpSheet(tester, screen: const Size(320, 480));

      await tester.dragUntilVisible(
        find.text('내가 참여 가능한 파티만 보기'),
        find.byType(ListView),
        const Offset(0, -60),
      );
      await tester.pumpAndSettle();
      expect(find.text('내가 참여 가능한 파티만 보기').hitTestable(), findsOneWidget);
      assertNoOverflow('스크롤');
    });
  });
}

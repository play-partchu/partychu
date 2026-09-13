import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/party_filter.dart';
import 'package:party_app/models/place_sort_mode.dart';
import 'package:party_app/widgets/main/day_date_filter_bar.dart';
import 'package:party_app/widgets/main/search_entry_sheet.dart';
import 'package:party_app/widgets/main/sort_entry_button.dart';
import 'package:party_app/widgets/party_sort_sheet.dart';
import 'package:party_app/widgets/place_sort_sheet.dart';

/// 정렬 시트가 **작은 화면에서도 넘치지 않고**, 정렬 버튼이 파티와 장소대여에서
/// **같은 위젯 하나**인지 고정한다.
///
/// 장소대여 정렬은 단위별 금액순까지 더해져 옵션이 아홉 줄이다. 예전에는 시트가
/// 내용만큼 세로로 자라기만 해서, 작은 기기에서 'BOTTOM OVERFLOWED BY 61
/// PIXELS'가 났고 마지막 옵션을 아예 고를 수 없었다. 고정 높이를 키우는 대신
/// **남는 높이를 Flexible이 받고 넘치는 만큼만 스크롤**되게 고친 구조를 여기서
/// 지킨다 — 옵션이 더 늘거나 기기 글꼴이 커져도 깨지지 않아야 한다.
void main() {
  /// main_screen이 시트를 여는 방식 그대로 — `isScrollControlled: true`.
  Future<T?> openSheet<T>(
    WidgetTester tester,
    Widget sheet, {
    required Size screen,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    T? picked;
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
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  picked = await showModalBottomSheet<T>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.white,
                    builder: (_) => sheet,
                  );
                },
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    return picked;
  }

  group('정렬 시트 — 넘치지 않는다', () {
    // 흔한 가장 작은 기기(iPhone SE / 소형 안드로이드)보다도 낮은 화면.
    const tiny = Size(320, 480);

    testWidgets('장소대여: 작은 화면에서 overflow가 없다', (tester) async {
      await openSheet<PlaceSortMode>(
        tester,
        const PlaceSortSheet(current: PlaceSortMode.defaultOrder),
        screen: tiny,
      );
      // RenderFlex overflow는 예외로 올라온다 — 하나도 없어야 한다.
      expect(tester.takeException(), isNull);
    });

    testWidgets('장소대여: 글자 크기를 키워도 overflow가 없다', (tester) async {
      await openSheet<PlaceSortMode>(
        tester,
        const PlaceSortSheet(current: PlaceSortMode.defaultOrder),
        screen: tiny,
        textScale: 1.6,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('파티: 같은 조건에서 overflow가 없다', (tester) async {
      await openSheet<PartySortMode>(
        tester,
        const PartySortSheet(current: PartySortMode.defaultOrder),
        screen: tiny,
        textScale: 1.6,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('시트가 화면을 통째로 덮지는 않는다(85% 상한)', (tester) async {
      await openSheet<PlaceSortMode>(
        tester,
        const PlaceSortSheet(current: PlaceSortMode.defaultOrder),
        screen: tiny,
      );
      final sheetHeight = tester.getSize(find.byType(PlaceSortSheet)).height;
      expect(sheetHeight, lessThanOrEqualTo(tiny.height * 0.85 + 1));
    });
  });

  group('정렬 시트 — 끝까지 스크롤해 고를 수 있다', () {
    const tiny = Size(320, 480);
    final lastOption = PlaceSortMode.values.last;

    testWidgets('마지막 옵션까지 스크롤로 닿는다', (tester) async {
      await openSheet<PlaceSortMode>(
        tester,
        const PlaceSortSheet(current: PlaceSortMode.defaultOrder),
        screen: tiny,
      );

      await tester.dragUntilVisible(
        find.text(lastOption.label),
        find.byType(SingleChildScrollView),
        const Offset(0, -60),
      );
      await tester.pumpAndSettle();
      expect(find.text(lastOption.label), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('스크롤해 닿은 마지막 옵션을 실제로 고를 수 있다', (tester) async {
      // 고른 값이 시트 밖으로 그대로 나오는지까지 본다 — 보이기만 하고
      // 눌리지 않으면 고칠 이유가 없다.
      PlaceSortMode? picked;
      tester.view.physicalSize = tiny;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    picked = await showModalBottomSheet<PlaceSortMode>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.white,
                      builder: (_) => const PlaceSortSheet(
                        current: PlaceSortMode.defaultOrder,
                      ),
                    );
                  },
                  child: const Text('열기'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.text(lastOption.label),
        find.byType(SingleChildScrollView),
        const Offset(0, -60),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(lastOption.label));
      await tester.pumpAndSettle();

      expect(picked, lastOption);
    });
  });

  group('정렬 버튼 — 파티와 장소대여가 같은 컴포넌트다', () {
    testWidgets('모양의 정본이 한 곳뿐이다 — 크기·터치 영역·색·아이콘', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: SortEntryIconButton(onTap: _noop)),
          ),
        ),
      );

      // 배경도 테두리도 없는 아이콘 하나 — 바로 옆에 붙는 돋보기와 같은 규격.
      final button = tester.widget<IconButton>(find.byType(IconButton));
      expect(
        button.constraints,
        const BoxConstraints(minWidth: 40, minHeight: 40),
      );
      expect(button.padding, EdgeInsets.zero);
      expect(tester.getSize(find.byType(IconButton)).width, 48);

      // ▼ 역삼각형 하나. 위아래 화살표(↕)가 아니다.
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.icon, Icons.arrow_drop_down);
      expect(icon.size, 22);
      expect(icon.color, const Color(0xFFFF6FA0));
    });

    testWidgets('바로 옆 돋보기와 같은 규격이다', (tester) async {
      // 두 버튼이 한 줄에 나란히 붙는 자리라, 한쪽만 크거나 여백이 다르면
      // 줄이 어긋나 보인다.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SearchEntryIconButton(onTap: _noop),
                const SortEntryIconButton(onTap: _noop),
              ],
            ),
          ),
        ),
      );
      final buttons = tester
          .widgetList<IconButton>(find.byType(IconButton))
          .toList();
      expect(buttons, hasLength(2));
      expect(buttons.first.constraints, buttons.last.constraints);
      expect(buttons.first.padding, buttons.last.padding);
      expect(
        tester.getSize(find.byType(SearchEntryIconButton)),
        tester.getSize(find.byType(SortEntryIconButton)),
      );
    });

    testWidgets('기본순이 아니면 활성 점이 붙는다', (tester) async {
      Future<int> dots(bool active) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SortEntryIconButton(onTap: _noop, active: active),
              ),
            ),
          ),
        );
        return tester
            .widgetList(
              find.descendant(
                of: find.byType(SortEntryIconButton),
                matching: find.byType(Container),
              ),
            )
            .length;
      }

      expect(await dots(false), 0);
      expect(await dots(true), 1);
    });

    testWidgets('파티 날짜 필터 바도 이 버튼을 그대로 쓴다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DayDateFilterBar(
              tabs: const ['전체', '오늘'],
              isSelected: (_) => false,
              onTapTab: (_) {},
              onOpenSort: () {},
              sortActive: true,
            ),
          ),
        ),
      );

      // 예전에는 이 바만 알약(DayFilterChip)으로 자기 정렬 버튼을 따로
      // 그렸다 — 이제 공용 버튼 하나뿐이다.
      expect(find.byType(SortEntryIconButton), findsOneWidget);
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byType(SortEntryIconButton),
          matching: find.byType(Icon),
        ),
      );
      expect(icon.icon, Icons.arrow_drop_down);
      // 폭은 단독으로 놓았을 때와 같다 — 높이만 바(42)에 맞춰 눌린다.
      expect(tester.getSize(find.byType(SortEntryIconButton)).width, 48);
      final button = tester.widget<IconButton>(
        find.descendant(
          of: find.byType(SortEntryIconButton),
          matching: find.byType(IconButton),
        ),
      );
      expect(
        button.constraints,
        const BoxConstraints(minWidth: 40, minHeight: 40),
      );
    });

    testWidgets('정렬 버튼이 없는 탭에는 자리도 생기지 않는다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DayDateFilterBar(
              tabs: const ['전체', '오늘'],
              isSelected: (_) => false,
              onTapTab: (_) {},
            ),
          ),
        ),
      );
      expect(find.byType(SortEntryIconButton), findsNothing);
    });
  });
}

void _noop() {}

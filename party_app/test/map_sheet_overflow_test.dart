import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/event_filter.dart';
import 'package:party_app/models/map_listing.dart';
import 'package:party_app/models/place_quick_picks.dart';
import 'package:party_app/models/place_taxonomy.dart';
import 'package:party_app/widgets/main/place_category_explorer.dart';
import 'package:party_app/widgets/main/place_quick_feature_bar.dart';
import 'package:party_app/widgets/map_kind_filter_bar.dart';

/// 지도 바텀시트가 **접혀 있을 때도 넘치지 않고, 어디를 잡아도 끌리는지**를
/// 고정한다.
///
/// ── 무엇이 깨졌었나 ───────────────────────────────────────────────────────
/// 시트 안이 `Column(손잡이 · 종류칩 · 플레이스필터, Expanded(ListView))`였다.
///
///  · 시트 높이는 `화면높이 × extent`다. 접힌 상태(minChildSize 0.15 ≈ 120px)
///    에서 고정 머리가 플레이스 필터까지 230px을 넘어가자, Expanded는 0 아래로
///    못 줄어드니 그대로 밖으로 넘쳤다("BOTTOM OVERFLOWED BY 151 PIXELS").
///    플레이스를 켰을 때만 터진 이유가 이것이다.
///  · DraggableScrollableSheet는 builder가 준 scrollController가 **붙은
///    스크롤 위젯** 위에서만 끌린다. 그 컨트롤러가 Expanded 안 ListView에만
///    달려 있어서 머리를 잡고 끌면 아무 일도 없었고, 오버플로로 ListView
///    높이가 0이 되면 잡을 곳 자체가 사라져 시트가 전혀 안 움직였다.
///
/// 지금은 손잡이부터 목록까지 **슬리버 하나의 스크롤**이다. 이 harness는
/// map_screen의 그 구조를 그대로 본떠, 아래 셋을 지킨다.
///
///  ① 최소·초기·최대 어느 높이에서도 RenderFlex 오버플로가 없다
///  ② 머리(플레이스 필터 위)를 잡고 끌면 시트가 실제로 움직인다
///  ③ 320px·360px 폭 모두에서 ①이 성립한다
void main() {
  const kMin = 0.15;
  const kInitial = 0.35;
  const kMax = 0.85;

  late DraggableScrollableController controller;

  /// map_screen의 시트와 **같은 뼈대** — CustomScrollView 하나에 머리 슬리버와
  /// 목록 슬리버를 얹는다(Column/Expanded 없음).
  Widget harness({
    required EventFilter filter,
    required bool placeOn,
    required int itemCount,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            const ColoredBox(color: Colors.blue, child: SizedBox.expand()),
            DraggableScrollableSheet(
              controller: controller,
              initialChildSize: kInitial,
              minChildSize: kMin,
              maxChildSize: kMax,
              builder: (context, scrollController) => Container(
                color: const Color(0xFFFFF4F8),
                child: CustomScrollView(
                  controller: scrollController,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 10),
                          Container(width: 44, height: 5, color: Colors.grey),
                          const SizedBox(height: 12),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: MapKindFilterBar(
                                    selected: placeOn
                                        ? const {MapListingKind.place}
                                        : const {MapListingKind.party},
                                    onChanged: (_) {},
                                    counts: const {},
                                    padding: const EdgeInsets.only(right: 6),
                                  ),
                                ),
                                const Icon(Icons.tune, size: 19),
                              ],
                            ),
                          ),
                          if (placeOn) ...[
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: PlaceCategoryExplorer(
                                key: const Key('explorer'),
                                filter: filter,
                                night: false,
                                onChanged: () {},
                              ),
                            ),
                            PlaceQuickFeatureBar(
                              filter: filter,
                              night: false,
                              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                              onChanged: () {},
                              onOpenMore: () {},
                            ),
                          ],
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                    if (itemCount == 0)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: Text('등록된 플레이스가 없습니다')),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.all(16),
                        sliver: SliverList.builder(
                          itemCount: itemCount,
                          itemBuilder: (context, i) => Container(
                            height: 120,
                            margin: const EdgeInsets.only(bottom: 12),
                            color: Colors.white,
                            child: Text('카드 $i'),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  FlutterErrorDetails? firstError;
  void Function(FlutterErrorDetails)? prevOnError;

  setUp(() {
    controller = DraggableScrollableController();
    firstError = null;
    prevOnError = FlutterError.onError;
    FlutterError.onError = (d) => firstError ??= d;
  });
  tearDown(() {
    FlutterError.onError = prevOnError;
    controller.dispose();
  });

  Future<void> pump(
    WidgetTester tester, {
    required Size size,
    bool placeOn = true,
    int itemCount = 8,
    EventFilter? filter,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness(
        filter: filter ?? EventFilter(),
        placeOn: placeOn,
        itemCount: itemCount,
      ),
    );
    await tester.pumpAndSettle();
  }

  void expectNoOverflow(String at) {
    expect(
      firstError,
      isNull,
      reason: '$at 에서 오버플로/예외가 났다: ${firstError?.exception}',
    );
  }

  group('오버플로 — 시트를 아무리 접어도 넘치지 않는다', () {
    for (final size in const [Size(360, 800), Size(320, 640)]) {
      testWidgets('${size.width.toInt()}px — 최소·초기·최대 세 높이 모두', (tester) async {
        await pump(tester, size: size);

        // 초기(0.35)
        expectNoOverflow('초기 높이');

        // 최소(0.15) — 예전에 "BOTTOM OVERFLOWED BY 151 PIXELS"가 나던 자리.
        controller.jumpTo(kMin);
        await tester.pumpAndSettle();
        expectNoOverflow('최소 높이');

        // 최대(0.85)
        controller.jumpTo(kMax);
        await tester.pumpAndSettle();
        expectNoOverflow('최대 높이');
      });
    }

    testWidgets('목록이 비어 있어도 넘치지 않는다 — 빈 화면도 같은 스크롤 안에 있다', (tester) async {
      await pump(tester, size: const Size(360, 800), itemCount: 0);
      controller.jumpTo(kMin);
      await tester.pumpAndSettle();
      expectNoOverflow('빈 목록 · 최소 높이');
    });

    testWidgets('대분류 → 드릴다운으로 머리 높이가 바뀌어도 넘치지 않는다', (tester) async {
      // 대분류 층(2줄 격자)에서 시작.
      await pump(tester, size: const Size(360, 800));
      controller.jumpTo(kMin);
      await tester.pumpAndSettle();
      final tall = tester.getSize(find.byKey(const Key('explorer'))).height;

      // 클럽을 고른 상태 = 드릴다운 층(1줄) — 머리가 줄어든다.
      await pump(
        tester,
        size: const Size(360, 800),
        filter: EventFilter(categories: {PlaceTaxonomy.club.label}),
      );
      controller.jumpTo(kMin);
      await tester.pumpAndSettle();
      final short = tester.getSize(find.byKey(const Key('explorer'))).height;

      expect(short, lessThan(tall), reason: '드릴다운 층이 더 낮아야 한다');
      expectNoOverflow('드릴다운 · 최소 높이');
    });

    testWidgets('파티만 켠 기존 동작도 그대로 — 플레이스 필터가 없으면 머리가 짧다', (tester) async {
      await pump(tester, size: const Size(360, 800), placeOn: false);
      expect(find.byKey(const Key('explorer')), findsNothing);
      controller.jumpTo(kMin);
      await tester.pumpAndSettle();
      expectNoOverflow('파티만 · 최소 높이');
    });
  });

  group('드래그 — 시트 어디를 잡아도 끌린다', () {
    testWidgets('플레이스 필터(머리) 위에서 끌어도 시트가 움직인다', (tester) async {
      const screen = Size(360, 800);
      await pump(tester, size: screen);
      controller.jumpTo(kInitial);
      await tester.pumpAndSettle();
      expect(controller.size, closeTo(kInitial, 0.001));

      /// 지금 시트 머리 한가운데 — 손잡이·종류칩 아래, 대분류 격자 위쪽.
      /// (위젯 중심을 쓰면 시트가 움직이는 동안 좌표가 흔들려 무엇을 잡았는지
      ///  불분명해진다. 화면 좌표를 직접 계산해 "머리를 잡았다"를 못 박는다.)
      Offset headerPoint() =>
          Offset(screen.width / 2, screen.height * (1 - controller.size) + 90);

      // 예전에는 이 자리에 scrollController가 안 붙어 있어 아무 일도 없었다.
      await tester.dragFrom(headerPoint(), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(
        controller.size,
        greaterThan(kInitial),
        reason: '머리를 위로 끌면 시트가 펼쳐져야 한다',
      );

      // 아래로 끌면 다시 접힌다.
      final expanded = controller.size;
      await tester.dragFrom(headerPoint(), const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(controller.size, lessThan(expanded));
      expectNoOverflow('드래그 후');
    });

    testWidgets('목록이 비어 있어도 끌린다 — 빈 화면에 컨트롤러가 없던 문제', (tester) async {
      await pump(tester, size: const Size(360, 800), itemCount: 0);
      controller.jumpTo(kInitial);
      await tester.pumpAndSettle();

      await tester.drag(find.text('등록된 플레이스가 없습니다'), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(controller.size, greaterThan(kInitial));
    });

    testWidgets('가로스크롤(빠른필터)은 세로 드래그를 가로채지 않는다', (tester) async {
      // 이 줄에 **어떤 칩이 나가는지**는 정본([PlaceQuickPicks.forCategory])이
      // 정하고 시간이 지나며 바뀐다 — 예전에는 특징이 하나씩 독립 칩
      // ('🔥 핫플')으로 나가 있었고, 지금은 '✨ 편의·서비스' 시트 하나가
      // 그것들을 받는다(place_quick_feature_bar.dart 주석). 이 검사가 보는
      // 것은 **가로스크롤 위에서의 제스처**이지 어느 조건이냐가 아니라서,
      // 문자열을 박아 두지 않고 정본에서 첫 칩을 가져온다.
      //
      // 대분류를 하나 골라 둔다 — 아무 대분류도 안 고른 줄은 칩이 둘뿐이라
      // 가로로 넘치지 않고, 그러면 "가로스크롤이 가로채지 않는다"가 검사할
      // 것 없이 조용히 통과한다.
      const category = PlaceTaxonomy.club;
      final filter = EventFilter(categories: {category.label});
      await pump(tester, size: const Size(360, 800), filter: filter);
      controller.jumpTo(kInitial);
      await tester.pumpAndSettle();

      // 줄이 정말로 가로로 넘치는 상태인지 먼저 못 박는다.
      final barScroll = find.descendant(
        of: find.byType(PlaceQuickFeatureBar),
        matching: find.byType(Scrollable),
      );
      expect(barScroll, findsOneWidget, reason: '빠른필터가 가로스크롤 줄이 아니다');
      expect(
        tester.state<ScrollableState>(barScroll).position.maxScrollExtent,
        greaterThan(0),
        reason: '줄이 가로로 넘치지 않으면 아래 두 단언이 헛돈다',
      );

      final chip = find.text(
        PlaceQuickPicks.forCategory(category.label).first.displayFor(filter),
      );
      expect(chip, findsOneWidget, reason: '빠른필터 첫 칩을 찾지 못했다');

      // 칩 위에서 **세로로** 끌면 시트가 움직여야 한다(축이 다르므로 가로
      // 리스트가 이 제스처를 가져가면 안 된다).
      await tester.drag(chip, const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(controller.size, greaterThan(kInitial));

      // 반대로 **가로로** 끌면 시트 높이는 그대로다.
      final after = controller.size;
      await tester.drag(chip, const Offset(-150, 0));
      await tester.pumpAndSettle();
      expect(controller.size, closeTo(after, 0.001));
      expectNoOverflow('가로/세로 드래그 후');
    });
  });
}

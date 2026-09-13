// 파티츄 / 플레이스 / 장소대여 세 탭의 "돋보기 → 검색 화면" UX가 실제로
// 똑같은지 화면을 띄워서 확인한다.
//
// 확인 항목
//  1. 돋보기를 누르면 시트가 **하나만** 열리고, 그 안에 검색어 입력창과
//     그 탭의 상세필터 항목이 함께 보이는지. 어떤 항목이냐는 탭마다 다르므로
//     이름을 박아 두지 않고 시트가 실제로 그린 것을 읽는다
//     ([expandableSectionTitles]).
//  2. 예전의 "상세검색 >" 버튼(= 팝업 위에 팝업)이 정말로 사라졌는지.
//  3. 세 탭의 검색어 입력창 **크기와 시트 안 위치**·문구가 완전히 같은지.
//     (시트가 화면에서 얼마나 올라오는지는 탭마다 정본이 다르게 정한다 —
//      [FilterSheetSizing] 참고.)
//  4. "검색"을 누르면 필터가 호출부로 돌아오고 시트 하나만 닫히는지
//     (= 목록에 곧바로 반영되는 기존 동작).
//  5. 뒤로가기 한 번이면 중간 단계 없이 목록으로 돌아오는지.
//  6. "전체 초기화"가 검색어와 상세조건을 **한 번에** 푸는지(검색어는 즉시,
//     이미 적용돼 있던 상세조건도 그 자리에서).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/event_filter.dart';
import 'package:party_app/models/party_filter.dart';
import 'package:party_app/models/place_filter.dart';
import 'package:party_app/screens/party_video_feed_screen.dart';
import 'package:party_app/screens/place_feed_screen.dart';
import 'package:party_app/widgets/detail_search_sheet.dart';
import 'package:party_app/widgets/filter_sheet_ui.dart';
import 'package:party_app/widgets/place_card_widget.dart';
import 'package:party_app/widgets/event_detail_search_sheet.dart';
import 'package:party_app/widgets/main/search_entry_sheet.dart';
import 'package:party_app/widgets/place_detail_search_sheet.dart';

/// main_screen.dart의 `_openSearchSheet`가 탭마다 넘기는 값 그대로.
class TabCase {
  final String tab;
  final String title;
  final String hintText;

  /// 그 탭의 검색 시트를 여는 함수 — main_screen의 `_openPartyDetailSearch` /
  /// `_openEventDetailSearch` / `_openPlaceDetailSearch`와 같은 모양이다
  /// (검색어 설정을 얹은 **그 탭의 기존 상세검색 시트**를 그대로 연다).
  final Future<bool> Function(BuildContext context, SearchEntryConfig search)
  openSearchSheet;

  /// 열린 시트의 타입 — "기존 시트를 그대로 쓰는지" 확인용.
  final Type sheetType;

  const TabCase({
    required this.tab,
    required this.title,
    required this.hintText,
    required this.openSearchSheet,
    required this.sheetType,
  });
}

/// "검색"으로 적용된 필터를 테스트가 들여다볼 수 있게 담아두는 상자.
final applied = <String, Object?>{};

/// "전체 초기화"가 시트를 닫지 않고 곧바로 넘겨준 빈 필터.
final resetApplied = <String, Object?>{};

/// 그 사이 호출부가 받은 마지막 검색어 — 전체 초기화가 검색어 조건까지
/// 즉시 푸는지 확인용.
final lastQuery = <String, String>{};

Future<T?> _showSheet<T>(BuildContext context, Widget sheet) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => sheet,
  );
}

final tabCases = <TabCase>[
  TabCase(
    tab: '파티츄',
    title: '파티 검색',
    hintText: '파티 제목, 장소, 키워드 검색',
    sheetType: DetailSearchSheet,
    openSearchSheet: (context, search) async {
      final result = await _showSheet<PartyFilter>(
        context,
        DetailSearchSheet(
          initialFilter: PartyFilter(),
          partyDates: const {},
          search: search,
          onFilterReset: (f) => resetApplied['파티츄'] = f,
        ),
      );
      if (result == null) return false;
      applied['파티츄'] = result;
      return true;
    },
  ),
  TabCase(
    tab: '플레이스',
    title: '플레이스 검색',
    hintText: '가게 이름, 지역, 키워드 검색',
    sheetType: EventDetailSearchSheet,
    openSearchSheet: (context, search) async {
      final result = await _showSheet<EventFilter>(
        context,
        EventDetailSearchSheet(
          initialFilter: EventFilter(),
          search: search,
          onFilterReset: (f) => resetApplied['플레이스'] = f,
        ),
      );
      if (result == null) return false;
      applied['플레이스'] = result;
      return true;
    },
  ),
  TabCase(
    tab: '장소대여',
    title: '장소대여 검색',
    hintText: '장소 이름, 지역, 키워드 검색',
    sheetType: PlaceDetailSearchSheet,
    openSearchSheet: (context, search) async {
      final result = await _showSheet<PlaceFilter>(
        context,
        PlaceDetailSearchSheet(
          initialFilter: PlaceFilter(),
          search: search,
          onFilterReset: (f) => resetApplied['장소대여'] = f,
        ),
      );
      if (result == null) return false;
      applied['장소대여'] = result;
      return true;
    },
  ),
];

/// 검색 시트 안의 검색어 입력창(다른 TextField — 파티 탭의 태그 입력 등 —
/// 과 섞이지 않도록 [SearchEntryField] 안쪽으로만 찾는다).
final queryField = find.descendant(
  of: find.byType(SearchEntryField),
  matching: find.byType(TextField),
);

/// 지금 열려 있는 시트가 **실제로 그린** 상세필터 항목 제목들.
///
/// 탭마다 항목도 배치도 다르고, 시간이 지나며 바뀐다 — 파티는 미니 카드 격자
/// ([FilterGridSection]), 플레이스·장소대여는 아코디언
/// ([FilterAccordionSection])이고, 장소대여는 '지역'을 시트 밖(목록 위 줄)으로
/// 옮겨 두었다. 그래서 이 파일은 **항목 이름을 알지 않는다**. 검색 진입 parity가
/// 지키려는 것은 "어떤 조건이 어디 있는가"가 아니라 "돋보기 하나로 검색어와
/// 상세조건이 한 화면에 오는가"이기 때문이다.
///
/// **그 자리에서 펼쳐지는 항목만** 준다 — 눌러서 또 다른 시트를 여는 칸
/// (파티의 '파티 유형·분위기', [FilterGridItem.canExpand]가 false)은
/// "같은 화면에서 조건을 고른다"의 예가 아니다.
List<String> expandableSectionTitles(WidgetTester tester) => [
  ...tester
      .widgetList<FilterAccordionSection>(find.byType(FilterAccordionSection))
      .map((w) => w.title),
  ...tester
      .widgetList<FilterGridSection>(find.byType(FilterGridSection))
      .expand((w) => w.items)
      .where((i) => i.canExpand)
      .map((i) => i.title),
];

/// 목록 헤더의 돋보기를 눌러 검색 시트를 여는 것까지 — 실제 화면과 같은
/// 경로(SearchEntryIconButton → 그 탭의 시트 + SearchEntryConfig)를 그대로 쓴다.
Future<void> tapMagnifier(
  WidgetTester tester,
  TabCase c,
  TextEditingController controller, {
  bool detailActive = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: SearchEntryIconButton(
              active: detailActive,
              onTap: () => c.openSearchSheet(
                context,
                SearchEntryConfig(
                  title: c.title,
                  hintText: c.hintText,
                  controller: controller,
                  // main_screen이 검색어 상태를 갱신하는 자리 — 여기까지
                  // 와야 목록이 다시 걸러진다.
                  onQueryChanged: (v) => lastQuery[c.tab] = v,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byType(SearchEntryIconButton));
  await tester.pumpAndSettle();
}

void main() {
  // 세 탭의 검색어 입력창 사각형을 모아 마지막에 서로 비교한다.
  // 세 탭의 검색어 입력창이 **같은 크기로, 시트 안 같은 자리**에 오는지를
  // 모아 마지막에 비교한다.
  //
  // 화면 좌표를 그대로 비교하지 않는다 — 시트가 얼마나 올라오는지는 탭마다
  // 정본이 다르게 정해 둔 값이기 때문이다([FilterSheetSizing]):
  //   · 파티 상세검색      : content — 격자가 2열 다섯 칸이라 내용만큼만 연다.
  //   · 플레이스·장소대여  : draggable — 화면 비율(0.82)로 연다.
  // 그래서 시트의 top은 서로 다른 것이 정상이고, parity가 지켜야 할 것은
  // "돋보기로 열면 어느 탭이든 시트 맨 위 **같은 자리에 같은 크기**의
  // 검색창이 온다"이다.
  final searchFieldPlacement = <String, ({Size size, double offsetInSheet})>{};

  for (final c in tabCases) {
    group('${c.tab} 탭', () {
      testWidgets('돋보기 → 한 시트 안에 검색어 입력과 상세필터가 함께 보인다', (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await tapMagnifier(tester, c, controller);

        // 1) 그 탭이 예전부터 쓰던 시트가 검색 시트로 열렸다.
        expect(find.byType(c.sheetType), findsOneWidget);
        expect(find.text(c.title), findsOneWidget);

        // 2) 검색어 입력이 있다(힌트까지 확인).
        expect(queryField, findsOneWidget);
        expect(find.text(c.hintText), findsOneWidget);

        // 3) 상세필터 항목이 **같은 화면에** 바로 펼쳐져 있다.
        //
        // 항목 이름을 박아 두지 않는다. 예전에는 '지역'이 세 탭 공통이라
        // 그걸로 확인했지만, 장소대여는 지역을 목록 위 줄의 '지역선택'
        // 버튼으로 옮겼다(place_detail_search_sheet.dart 주석 — 값
        // [PlaceFilter.regions]은 그대로다). 이 검사가 지키려는 것은 특정
        // 조건의 자리가 아니라 **"돋보기 하나로 검색어와 상세조건이 한
        // 화면에 온다"**는 것이므로, 그 시트가 실제로 그린 항목을 읽어 쓴다.
        // 파티 탭은 항목이 미니 카드라 접힌 본문에도 같은 제목이 들어 있다
        // (AnimatedCrossFade가 높이 0으로 눌러 둘 뿐 트리에는 남는다).
        // 여기서 보려는 건 "눈에 보이는 항목"이므로 hitTestable로 좁힌다.
        final sections = expandableSectionTitles(tester);
        expect(
          sections,
          isNotEmpty,
          reason: '${c.tab} 검색 시트에 상세필터 항목이 하나도 없다 — 검색창만 남은 시트다',
        );
        final firstSection = find.text(sections.first).hitTestable();
        expect(firstSection, findsOneWidget);
        expect(find.text('전체 초기화'), findsOneWidget);

        // 4) 팝업을 한 번 더 띄우던 "상세검색" 진입 버튼은 없다.
        expect(find.text('상세검색'), findsNothing);
        expect(find.widgetWithText(OutlinedButton, '상세검색'), findsNothing);

        // 5) 순서: 검색어 입력 → 상세필터 → 검색 버튼.
        final fieldRect = tester.getRect(queryField);
        final sectionRect = tester.getRect(firstSection);
        final submitRect = tester.getRect(find.text('검색'));
        expect(fieldRect.bottom, lessThanOrEqualTo(sectionRect.top));
        expect(sectionRect.bottom, lessThanOrEqualTo(submitRect.top));

        // 시트가 얼마나 올라오는지는 탭마다 다르므로(위 주석), 시트 자신의
        // 위쪽을 기준으로 잰다.
        final shellRect = tester.getRect(find.byType(FilterSheetShell));
        searchFieldPlacement[c.tab] = (
          size: fieldRect.size,
          offsetInSheet: fieldRect.top - shellRect.top,
        );
      });

      testWidgets('검색 → 필터가 호출부로 오고 시트 하나만 닫힌다', (tester) async {
        applied.remove(c.tab);
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await tapMagnifier(tester, c, controller);

        await tester.tap(find.text('검색'));
        await tester.pumpAndSettle();

        // 필터가 호출부(main_screen 자리)로 돌아왔다 = 목록에 반영된다.
        expect(applied[c.tab], isNotNull);
        // 닫을 시트는 하나뿐이라 곧바로 목록이 보인다.
        expect(find.byType(c.sheetType), findsNothing);
      });

      testWidgets('뒤로가기 한 번이면 중간 단계 없이 목록으로 돌아온다', (tester) async {
        applied.remove(c.tab);
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await tapMagnifier(tester, c, controller);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(find.byType(c.sheetType), findsNothing);
        // 적용하지 않고 닫았으므로 조건은 호출부로 넘어가지 않는다.
        expect(applied[c.tab], isNull);
      });

      testWidgets('검색어를 치면 컨트롤러에 남고 지우기 버튼이 생긴다', (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await tapMagnifier(tester, c, controller);

        await tester.enterText(queryField, '루프탑');
        await tester.pumpAndSettle();
        expect(controller.text, '루프탑');

        await tester.tap(
          find.descendant(
            of: find.byType(SearchEntryField),
            matching: find.byIcon(Icons.clear),
          ),
        );
        await tester.pumpAndSettle();
        expect(controller.text, isEmpty);
      });

      testWidgets('전체 초기화 → 검색어와 상세조건이 한 번에 풀린다', (tester) async {
        resetApplied.remove(c.tab);
        lastQuery.remove(c.tab);
        final controller = TextEditingController(text: '루프탑');
        addTearDown(controller.dispose);
        await tapMagnifier(tester, c, controller);

        // 검색어가 남아 있으니 지우기(x)도 보인다.
        final clearButton = find.descendant(
          of: find.byType(SearchEntryField),
          matching: find.byIcon(Icons.clear),
        );
        expect(clearButton, findsOneWidget);

        await tester.tap(find.text('전체 초기화'));
        await tester.pumpAndSettle();

        // 1) 입력값이 지워지고 지우기(x)도 함께 사라진다.
        expect(controller.text, isEmpty);
        expect(clearButton, findsNothing);
        // 2) 검색어로 걸려 있던 조건도 즉시 풀린다(호출부까지 전달).
        expect(lastQuery[c.tab], isEmpty);
        // 3) 이미 적용돼 있던 상세조건도 시트를 닫기 전에 풀린다.
        expect(resetApplied[c.tab], isNotNull);
        expect((resetApplied[c.tab] as dynamic).isActive, isFalse);
        // 4) 시트는 그대로 열려 있다 — 초기화지 닫기가 아니다.
        expect(find.byType(c.sheetType), findsOneWidget);
      });

      testWidgets('검색어만 지우면 상세조건은 그대로 남는다', (tester) async {
        resetApplied.remove(c.tab);
        lastQuery.remove(c.tab);
        final controller = TextEditingController(text: '루프탑');
        addTearDown(controller.dispose);
        await tapMagnifier(tester, c, controller);

        await tester.tap(
          find.descendant(
            of: find.byType(SearchEntryField),
            matching: find.byIcon(Icons.clear),
          ),
        );
        await tester.pumpAndSettle();

        expect(controller.text, isEmpty);
        expect(lastQuery[c.tab], isEmpty);
        // 지우기(x)는 검색어만 지운다 — 상세조건 초기화는 일어나지 않는다.
        expect(resetApplied[c.tab], isNull);
      });

      testWidgets('검색어와 상세조건을 함께 걸어도 서로를 지우지 않는다', (tester) async {
        applied.remove(c.tab);
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await tapMagnifier(tester, c, controller);

        // 검색어를 치고, 같은 화면에서 상세필터 항목을 펼쳐 본 뒤 검색한다.
        // 어느 항목이냐는 상관없다 — 그 시트가 첫 번째로 내놓는 것을 편다
        // ([expandableSectionTitles] 주석 참고).
        await tester.enterText(queryField, '루프탑');
        await tester.pumpAndSettle();
        final sections = expandableSectionTitles(tester);
        expect(sections, isNotEmpty, reason: '${c.tab} 시트에 펼칠 상세필터 항목이 없다');
        await tester.tap(find.text(sections.first).hitTestable());
        await tester.pumpAndSettle();

        // 조건을 고르는 중에도 검색어는 그대로 남아 있다.
        expect(controller.text, '루프탑');
        // 항목은 **같은 시트 안에서** 펼쳐진다 — 다른 화면이 덮었다면
        // 검색 버튼이 사라졌을 것이다.
        expect(find.text('검색'), findsOneWidget);

        await tester.tap(find.text('검색'));
        await tester.pumpAndSettle();

        expect(applied[c.tab], isNotNull);
        expect(controller.text, '루프탑');
      });
    });
  }

  // ── 큰 카드 전체화면 피드 ────────────────────────────────────────────
  // 두 전체화면도 목록과 같은 계약(돋보기 하나 → onOpenSearch → 바뀌었으면
  // 자기를 닫음)을 쓰는지, 별도 상세검색(튠) 아이콘이 남아있지 않은지 본다.
  group('큰 카드 전체화면', () {
    Future<Object?> pumpFeed(
      WidgetTester tester,
      Widget Function(Future<bool> Function() onOpenSearch) build, {
      required bool changed,
    }) async {
      Object? popped;
      var opened = false;
      late final Widget screen;
      screen = build(() async {
        opened = true;
        return changed;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  popped = await Navigator.push<Object?>(
                    context,
                    MaterialPageRoute(builder: (_) => screen),
                  );
                },
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      // 별도 상세검색(튠) 아이콘은 없고, 돋보기 하나만 있다.
      expect(find.byIcon(Icons.tune), findsNothing);
      expect(find.byIcon(Icons.tune_rounded), findsNothing);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();
      expect(opened, isTrue, reason: '돋보기가 목록 화면의 검색 시트를 열어야 한다');
      return popped;
    }

    testWidgets('플레이스 — 조건이 바뀌면 자기를 닫고 신호를 돌려준다', (tester) async {
      final popped = await pumpFeed(
        tester,
        (onOpenSearch) => PlaceFeedScreen(
          docs: const [],
          source: PlaceCardSource.place,
          onOpenSearch: onOpenSearch,
        ),
        changed: true,
      );
      expect((popped as PlaceFeedExitResult).searchChanged, isTrue);
    });

    testWidgets('플레이스 — 그냥 닫으면 전체화면이 그대로 남는다', (tester) async {
      await pumpFeed(
        tester,
        (onOpenSearch) => PlaceFeedScreen(
          docs: const [],
          source: PlaceCardSource.place,
          onOpenSearch: onOpenSearch,
        ),
        changed: false,
      );
      expect(find.byType(PlaceFeedScreen), findsOneWidget);
    });

    testWidgets('파티 영상 — 조건이 바뀌면 자기를 닫고 신호를 돌려준다', (tester) async {
      final popped = await pumpFeed(
        tester,
        (onOpenSearch) => PartyVideoFeedScreen(
          docs: const [],
          initialIndex: 0,
          onOpenSearch: onOpenSearch,
        ),
        changed: true,
      );
      expect((popped as VideoFeedExitResult).searchChanged, isTrue);
    });

    testWidgets('파티 영상 — 그냥 닫으면 전체화면이 그대로 남는다', (tester) async {
      await pumpFeed(
        tester,
        (onOpenSearch) => PartyVideoFeedScreen(
          docs: const [],
          initialIndex: 0,
          onOpenSearch: onOpenSearch,
        ),
        changed: false,
      );
      expect(find.byType(PartyVideoFeedScreen), findsOneWidget);
    });
  });

  test('세 탭의 검색어 입력창 크기와 시트 안 위치가 완전히 같다', () {
    // 탭 목록은 이 파일 위의 표([tabCases])가 정본이다 — 여기 다시 적으면
    // 탭이 늘거나 줄 때 두 곳이 어긋난다.
    expect(searchFieldPlacement.keys, containsAll(tabCases.map((c) => c.tab)));
    expect(
      searchFieldPlacement.values.toSet().length,
      1,
      reason: '탭마다 검색어 입력 크기/시트 안 위치가 다르다: $searchFieldPlacement',
    );
  });
}

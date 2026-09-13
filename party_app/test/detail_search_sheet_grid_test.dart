// 파티 상세검색 — 다섯 필터를 **2열 균일 격자**로 놓는 배치.
//
// 배치만 정리했다. 필터 값·선택 UI·전체 초기화·검색 결과는 전부 예전
// 그대로이고, 이 파일의 '동작은 예전 그대로' 묶음이 그것을 지킨다.
//
// 레이아웃에서 지켜야 하는 것은 넷이다.
//  1. 다섯 카드의 **가로폭·세로높이가 전부 같다** — 마지막 '파티 유형·분위기'
//     칸도 혼자 넓어지지 않는다(빈 자리는 비워 둔다)
//  2. 시트가 **내용 높이만큼만** 올라온다 — 검색 버튼 아래에 빈 공간이
//     생기지 않고, 내용이 넘칠 때만 안쪽이 스크롤된다
//  3. 토글 카드 두 장의 **높이와 안쪽 여백이 같다** — 설명문이 붙은 쪽만
//     높아지지 않는다
//  4. 320/360/390에서, 그리고 글자를 키워도 넘치지 않는다

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/party_constants.dart';
import 'package:party_app/models/party_filter.dart';
import 'package:party_app/widgets/detail_search_sheet.dart';
import 'package:party_app/widgets/filter_sheet_ui.dart';

void main() {
  /// 2열로 놓는 다섯 항목 — 지역/성별 · 연령/참가비 · 파티 유형·분위기.
  const gridTitles = ['지역', '성별', '연령', '참가비', '파티 유형·분위기'];

  /// 좁은 기기부터 흔한 기기까지 — 셋 다 넘치지 않아야 한다.
  const narrowWidths = [320.0, 360.0, 390.0];

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

  /// 시트를 띄운다. [width]로 좁은 기기를 흉내낸다.
  /// 돌려주는 상자에는 '적용하기'를 눌렀을 때의 결과가 담긴다.
  /// 시트를 띄운다. 화면 높이는 **실제 기기에 가깝게** 잡는다 — 예전처럼
  /// 1800px로 두면 시트가 내용 높이로 열리는지 화면을 다 덮는지 구분되지 않는다.
  Future<List<PartyFilter?>> pumpSheet(
    WidgetTester tester, {
    double width = 360,
    double height = 1400,
    double textScale = 1.0,
    PartyFilter? initial,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final results = <PartyFilter?>[];
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async => results.add(
                await showModalBottomSheet<PartyFilter>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => DetailSearchSheet(
                    initialFilter: initial ?? PartyFilter(),
                  ),
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
    return results;
  }

  /// 시트 전체가 차지한 자리 — 시트 안 검색 버튼의 조상 중 가장 바깥
  /// [FilterSheetShell]로 잡는다.
  Rect sheetRect(WidgetTester tester) =>
      tester.getRect(find.byType(FilterSheetShell));

  /// 토글 카드 한 장이 차지한 자리 — 스위치를 품은 카드 Container.
  Rect toggleRectOf(WidgetTester tester, String title) => tester.getRect(
    find.ancestor(of: find.text(title), matching: find.byType(Container)).first,
  );

  /// 그리드 칸의 선택값 Text — 제목과 같은 카드 안에 있는 두 번째 Text다.
  Text summaryOf(WidgetTester tester, String title) {
    final card = find.ancestor(
      of: find.text(title).first,
      matching: find.byType(Column),
    );
    final texts = find
        .descendant(of: card.first, matching: find.byType(Text))
        .evaluate()
        .map((e) => e.widget as Text)
        .toList();
    return texts.firstWhere((t) => t.data != title);
  }

  /// 미니 카드 한 장이 차지한 자리 — 카드 안쪽을 통째로 감싸는 터치 래퍼로 잡는다.
  Rect cardRectOf(WidgetTester tester, String title) => tester.getRect(
    find
        .ancestor(
          of: find.text(title).first,
          matching: find.byType(FilterScaleTap),
        )
        .first,
  );

  double round1(double v) => (v * 10).roundToDouble() / 10;

  group('3×3 미니 카드 배치', () {
    testWidgets('일곱 항목이 모두 그리드에 있고 기본값은 전체다', (tester) async {
      await pumpSheet(tester);

      expect(find.byType(FilterGridSection), findsOneWidget);
      // 가로 전체 폭 아코디언은 더 이상 남아 있지 않다 — 일곱 개 전부 칸이다.
      expect(find.byType(FilterAccordionSection), findsNothing);
      for (final t in gridTitles) {
        expect(find.text(t), findsWidgets, reason: t);
        expect(summaryOf(tester, t).data, '전체', reason: t);
      }
      assertNoOverflow('기본 표시');
    });

    testWidgets('없어진 두 칸(태그 · 분위기)은 격자에 남아 있지 않다', (tester) async {
      await pumpSheet(tester);

      // 태그는 상단 검색창이 대신 찾고, 분위기는 파티 유형·분위기 한 칸으로
      // 합쳐졌다 — 둘 다 **칸만** 사라졌고 조건은 살아 있다.
      expect(find.text('태그'), findsNothing);
      expect(find.text('분위기'), findsNothing);
      expect(find.text('파티 유형'), findsNothing);
      expect(find.text('파티 유형·분위기'), findsWidgets);
      assertNoOverflow('없어진 칸');
    });

    testWidgets('태그 조건은 그대로 살아 있다 — 칩으로 보이고 검색에 그대로 실린다', (tester) async {
      // 상세검색에서 **새로 넣는 입구만** 없앴다. 예전에 걸어 둔 태그
      // 조건은 계속 걸러 주고, 위 선택 칩에서 뺄 수 있다.
      final filter = PartyFilter()..tagKeywords.add('감성');
      final results = await pumpSheet(tester, initial: filter);
      expect(find.text('#감성'), findsOneWidget);

      await tester.tap(find.text('적용하기'));
      await tester.pumpAndSettle();
      expect(results.single!.tagKeywords, {'감성'});
    });

    testWidgets('2 / 2 / 1 — 두 열에 나란히 서고 마지막 칸은 넓어지지 않는다', (tester) async {
      await pumpSheet(tester, width: 320);
      assertNoOverflow('320px');

      final rects = {for (final t in gridTitles) t: cardRectOf(tester, t)};

      // 행: 위쪽 y가 세 종류뿐이다(2 + 2 + 1).
      final tops = rects.values.map((r) => round1(r.top)).toSet().toList()
        ..sort();
      expect(tops.length, 3, reason: '행은 세 개여야 한다: $tops');

      // 열: 왼쪽 x가 두 종류뿐이다.
      final lefts = rects.values.map((r) => round1(r.left)).toSet().toList()
        ..sort();
      expect(lefts.length, 2, reason: '열은 두 개여야 한다: $lefts');

      // 다섯 칸이 순서대로 (0,0) (1,0) (0,1) (1,1) (0,2)에 앉는다.
      for (var i = 0; i < gridTitles.length; i++) {
        final r = rects[gridTitles[i]]!;
        expect(round1(r.left), lefts[i % 2], reason: '${gridTitles[i]} 열 위치');
        expect(round1(r.top), tops[i ~/ 2], reason: '${gridTitles[i]} 행 위치');
      }

      // 마지막 칸은 **왼쪽 한 칸**에 그대로 머문다 — 줄을 넓게 쓰지 않는다.
      expect(round1(rects['파티 유형·분위기']!.left), lefts.first);
      expect(round1(rects['파티 유형·분위기']!.top), tops.last);

      // 화면 밖으로 나가지 않는다.
      for (final e in rects.entries) {
        expect(e.value.left, greaterThanOrEqualTo(0.0), reason: e.key);
        expect(e.value.right, lessThanOrEqualTo(320.0), reason: e.key);
      }
    });

    // 폭마다 시트를 새로 띄워야 한다 — 한 테스트 안에서 다시 pump하면 앞서
    // 열린 시트가 '열기' 버튼을 덮고 있어 두 번째 탭이 빗나간다.
    for (final w in narrowWidths) {
      testWidgets('다섯 카드의 폭과 높이가 전부 같다 — ${w.toInt()}dp', (tester) async {
        await pumpSheet(tester, width: w);

        final sizes = {
          for (final t in gridTitles) t: cardRectOf(tester, t).size,
        };
        final first = sizes[gridTitles.first]!;
        for (final e in sizes.entries) {
          expect(
            e.value.width,
            closeTo(first.width, 0.01),
            reason: '${e.key} 폭 — ${e.value.width} != ${first.width}',
          );
          expect(
            e.value.height,
            closeTo(first.height, 0.01),
            reason: '${e.key} 높이 — ${e.value.height} != ${first.height}',
          );
        }
        assertNoOverflow('크기 동일 $w');
      });
    }

    testWidgets('글자를 키워도 다섯 카드 크기는 서로 같고 넘치지 않는다', (tester) async {
      await pumpSheet(tester, width: 360, textScale: 1.3);

      final sizes = {for (final t in gridTitles) t: cardRectOf(tester, t).size};
      final first = sizes[gridTitles.first]!;
      for (final e in sizes.entries) {
        expect(e.value.width, closeTo(first.width, 0.01), reason: '${e.key} 폭');
        expect(
          e.value.height,
          closeTo(first.height, 0.01),
          reason: '${e.key} 높이',
        );
      }
      assertNoOverflow('글자 확대');
    });

    testWidgets('시트가 내용 높이만큼만 올라온다 — 검색 버튼 아래가 비지 않는다', (tester) async {
      const screenHeight = 800.0;
      await pumpSheet(tester, width: 360, height: screenHeight);

      final sheet = sheetRect(tester);
      // 화면을 다 덮지 않는다 — 위쪽이 남아 뒤 목록이 보이고 바깥을 눌러
      // 닫을 자리가 생긴다.
      expect(
        sheet.height,
        lessThan(screenHeight * 0.8),
        reason: '시트가 너무 높다: ${sheet.height} / $screenHeight',
      );
      // 그렇다고 쪼그라들지도 않는다 — 조건 다섯 칸과 토글 둘, 검색 버튼이
      // 한 화면에 들어갈 만큼은 된다.
      expect(
        sheet.height,
        greaterThan(screenHeight * 0.4),
        reason: '시트가 너무 낮다: ${sheet.height}',
      );
      // 바닥에 붙어 있다(모달 시트의 자리 그대로).
      expect(sheet.bottom, closeTo(screenHeight, 0.5));

      // 검색 버튼이 시트 안에 있고, 그 아래 남는 공간이 아주 작다 —
      // 예전에는 여기에 커다란 빈칸이 생겼다.
      final button = tester.getRect(find.text('적용하기'));
      expect(sheet.bottom - button.bottom, lessThan(40));
      assertNoOverflow('내용 높이 시트');
    });

    testWidgets('내용이 넘치면 시트가 커지는 대신 안쪽이 스크롤된다', (tester) async {
      // 아주 낮은 화면 — 조건을 다 넣을 수 없다.
      const screenHeight = 420.0;
      await pumpSheet(tester, width: 360, height: screenHeight);

      final sheet = sheetRect(tester);
      // 화면 상한을 넘지 않는다.
      expect(sheet.height, lessThanOrEqualTo(screenHeight));
      // 그래도 검색 버튼은 잘리지 않고 화면 안에 남는다 — 목록만 스크롤된다.
      final button = tester.getRect(find.text('적용하기'));
      expect(button.bottom, lessThanOrEqualTo(screenHeight + 0.5));
      expect(find.byType(Scrollable), findsWidgets);
      assertNoOverflow('낮은 화면');
    });

    for (final w in narrowWidths) {
      testWidgets('토글 카드 두 장의 높이와 폭이 같다 — ${w.toInt()}dp', (tester) async {
        await pumpSheet(tester, width: w);

        final early = toggleRectOf(tester, '얼리버드 진행중만 보기');
        final eligible = toggleRectOf(tester, '내가 참여 가능한 파티만 보기');
        // 설명문이 붙은 두 번째 카드만 높아지지 않는다.
        expect(
          eligible.height,
          closeTo(early.height, 0.01),
          reason: '토글 카드 높이: ${early.height} vs ${eligible.height}',
        );
        expect(eligible.width, closeTo(early.width, 0.01), reason: '폭');
        // 격자와 같은 가로 폭을 쓴다(전체 폭 카드).
        expect(
          early.width,
          greaterThan(cardRectOf(tester, '지역').width),
          reason: '토글은 전체 폭이어야 한다',
        );
        assertNoOverflow('토글 카드 $w');
      });
    }

    testWidgets('글자를 키워도 토글 카드 두 장의 높이가 같다', (tester) async {
      await pumpSheet(tester, width: 360, textScale: 1.3);
      final early = toggleRectOf(tester, '얼리버드 진행중만 보기');
      final eligible = toggleRectOf(tester, '내가 참여 가능한 파티만 보기');
      expect(eligible.height, closeTo(early.height, 0.01));
      assertNoOverflow('토글 글자 확대');
    });

    testWidgets('선택값이 길어도 카드가 커지지 않고 말줄임된다', (tester) async {
      // 파티 유형을 여러 개 고른 상태 — 요약이 아주 길어진다.
      final filter = PartyFilter()
        ..partyTypes.addAll(PartyConstants.partyTypes.take(6));
      await pumpSheet(tester, width: 320, initial: filter);

      final summary = summaryOf(tester, '파티 유형·분위기');
      expect(summary.overflow, TextOverflow.ellipsis);
      expect(summary.maxLines, 1);
      expect(summary.data, isNot('전체'));

      // 아무것도 안 고른 칸('지역' = 전체)과 크기가 같다 — 긴 값이 카드를
      // 키우지 않고 말줄임으로 끝난다.
      final plain = cardRectOf(tester, '지역').size;
      final picked = cardRectOf(tester, '파티 유형·분위기').size;
      expect(picked.height, closeTo(plain.height, 0.01));
      assertNoOverflow('긴 선택값');
    });
  });

  group('동작은 예전 그대로', () {
    testWidgets('항목을 누르면 그 자리에서 선택 UI가 열린다', (tester) async {
      await pumpSheet(tester);

      // 접힌 본문은 AnimatedCrossFade가 높이 0으로 눌러 둔다(기존 아코디언과
      // 같은 방식) — 트리에는 남아 있으므로 "누를 수 있는가"로 본다.
      expect(find.text('남녀무관').hitTestable(), findsNothing);

      await tester.tap(find.text('성별').first);
      await tester.pumpAndSettle();
      expect(find.text('남녀무관').hitTestable(), findsOneWidget);

      // 다시 누르면 접힌다.
      await tester.tap(find.text('성별').first);
      await tester.pumpAndSettle();
      expect(find.text('남녀무관').hitTestable(), findsNothing);
      assertNoOverflow('펼치기/접기');
    });

    testWidgets('파티 유형·분위기는 펼치지 않고 한 바텀시트를 연다', (tester) async {
      await pumpSheet(tester);

      final vibe = PartyConstants.vibes.first;
      expect(find.text(vibe), findsNothing, reason: '격자에는 본문 자리가 아예 없다');

      await tester.tap(find.text('파티 유형·분위기').first);
      await tester.pumpAndSettle();

      // 시트 하나에 **한 목록**이다 — 소제목도 구분선도 없이 칩이 같은
      // 레벨로 이어진다(고르는 사람에게는 원래 한 가지 질문이라서).
      expect(find.text('🎉 파티 유형 · 분위기'), findsOneWidget);
      expect(find.text('파티 유형'), findsNothing, reason: '소제목을 두지 않는다');
      expect(find.text('분위기'), findsNothing, reason: '소제목을 두지 않는다');

      // 기존 옵션이 **둘 다 전부** 들어 있다.
      // 분위기는 저장값과 보이는 글자가 다를 수 있다('💃 춤' → '🤸 춤') —
      // 화면에서 찾을 때는 라벨을 쓴다(저장값은 그대로다).
      for (final v in PartyConstants.vibes) {
        expect(
          find.text(PartyConstants.vibeLabelFor(v)).hitTestable(),
          findsOneWidget,
          reason: v,
        );
      }
      for (final t in PartyConstants.partyTypes) {
        expect(
          find.text(PartyConstants.labelFor(t)).hitTestable(),
          findsOneWidget,
          reason: t,
        );
      }

      await tester.tap(find.text(vibe).hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.text('적용'));
      await tester.pumpAndSettle();

      expect(summaryOf(tester, '파티 유형·분위기').data, vibe);
      assertNoOverflow('분위기 선택');
    });

    testWidgets('한 시트에서 유형과 분위기를 함께 고르고 저장값은 따로 남는다', (tester) async {
      final results = await pumpSheet(tester);

      await tester.tap(find.text('파티 유형·분위기').first);
      await tester.pumpAndSettle();

      // 화면에는 짧은 라벨, 저장은 원문 문자열(PartyConstants.labelFor).
      const raw = '하우스파티';
      final vibe = PartyConstants.vibes.first;
      await tester.tap(find.text(PartyConstants.labelFor(raw)).hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.text(vibe).hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.text('적용'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('적용하기'));
      await tester.pumpAndSettle();
      // 진입점만 하나로 합쳤다 — 저장값은 예전처럼 둘로 나뉜다.
      expect(results.single!.partyTypes, {raw});
      expect(results.single!.vibes, {vibe});
      assertNoOverflow('유형·분위기 선택');
    });

    testWidgets('⚡ 얼리버드는 격자 밖 독립 토글이다 — 열지 않아도 보인다', (tester) async {
      final results = await pumpSheet(tester);

      // '기타 필터' 칸은 사라졌고, 스위치가 격자 밖에 그대로 노출된다.
      expect(find.text('기타 필터'), findsNothing);
      final tile = find.text('얼리버드 진행중만 보기');
      expect(tile, findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(FilterGridSection),
          matching: find.byType(Switch),
        ),
        findsNothing,
        reason: '격자 안에는 스위치가 없다',
      );

      await tester.tap(tile);
      await tester.pumpAndSettle();
      await tester.tap(find.text('적용하기'));
      await tester.pumpAndSettle();
      expect(results.single!.earlyBirdOnly, isTrue);
      assertNoOverflow('얼리버드 토글');
    });

    testWidgets('맨 아래 순서는 얼리버드 → 참여 가능 → 검색이다', (tester) async {
      await pumpSheet(tester);

      final early = tester.getRect(find.text('얼리버드 진행중만 보기'));
      final eligible = tester.getRect(find.text('내가 참여 가능한 파티만 보기'));
      final apply = tester.getRect(find.text('적용하기'));
      expect(early.top, lessThan(eligible.top));
      expect(eligible.top, lessThan(apply.top));
    });

    testWidgets('고른 값이 요약에 그대로 나타난다', (tester) async {
      await pumpSheet(tester);

      await tester.tap(find.text('성별').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('여자만'));
      await tester.pumpAndSettle();

      expect(summaryOf(tester, '성별').data, '여자만');
      assertNoOverflow('선택 반영');
    });

    testWidgets('전체 초기화를 누르면 일곱 요약이 모두 전체로 돌아온다', (tester) async {
      await pumpSheet(tester);

      await tester.tap(find.text('연령').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('30대'));
      await tester.pumpAndSettle();
      expect(summaryOf(tester, '연령').data, '30대');

      await tester.tap(find.text('파티 유형·분위기').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(PartyConstants.vibes.first).hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.text('적용'));
      await tester.pumpAndSettle();
      expect(summaryOf(tester, '파티 유형·분위기').data, PartyConstants.vibes.first);

      await tester.tap(find.text('전체 초기화'));
      await tester.pumpAndSettle();

      for (final t in gridTitles) {
        expect(summaryOf(tester, t).data, '전체', reason: t);
      }
      assertNoOverflow('전체 초기화');
    });

    testWidgets('검색을 누르면 고른 조건이 그대로 돌아온다', (tester) async {
      final results = await pumpSheet(tester);

      await tester.tap(find.text('성별').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('남자만'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('연령').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('20대'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('적용하기'));
      await tester.pumpAndSettle();

      final applied = results.single!;
      expect(applied.genderConditions, {'남자만'});
      expect(applied.ageGroups, {'20대'});
      assertNoOverflow('검색 적용');
    });

    testWidgets('두 항목을 함께 펼쳐도 서로를 닫지 않는다', (tester) async {
      await pumpSheet(tester);

      await tester.tap(find.text('성별').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('연령').first);
      await tester.pumpAndSettle();

      expect(find.text('남녀무관').hitTestable(), findsOneWidget);
      expect(find.text('20대').hitTestable(), findsOneWidget);
      assertNoOverflow('동시 펼침');
    });

    testWidgets('내가 참여 가능한 파티만 보기 스위치는 그대로 있다', (tester) async {
      final results = await pumpSheet(tester);

      await tester.tap(find.text('내가 참여 가능한 파티만 보기'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('적용하기'));
      await tester.pumpAndSettle();

      expect(results.single!.eligibleOnly, isTrue);
      assertNoOverflow('참여 가능 스위치');
    });
  });
}

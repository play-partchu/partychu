// 기타 편의 서비스 — 호스트 입력 영역과 게스트 탐색 시트.
//
// 모델 검사(정규화·필터·초성)는 test/custom_amenity_test.dart에 있다. 여기서는
// **화면이 그 규칙을 실제로 쓰는지**만 본다: 안내 문구가 검색 키워드를 받는
// 칸으로 읽히는지, 추가/삭제가 되는지, 긴 문장이 막히는지, 탐색 시트가 초성
// 묶음과 개수를 보여주고 고른 값을 돌려주는지.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/custom_amenity.dart';
import 'package:party_app/models/event_filter.dart';
import 'package:party_app/models/place_filter.dart';
import 'package:party_app/widgets/custom_amenity_browse_sheet.dart';
import 'package:party_app/widgets/event_detail_search_sheet.dart';
import 'package:party_app/widgets/place_detail_search_sheet.dart';
import 'package:party_app/widgets/custom_amenity_view.dart';
import 'package:party_app/widgets/place_form/custom_amenity_section.dart';

Map<String, dynamic> _place(List<String> amenities) => <String, dynamic>{
  CustomAmenities.field: amenities,
};

void main() {
  group('호스트 입력 영역', () {
    /// 입력 영역을 띄우고, 바뀐 값을 담아 둘 리스트를 돌려준다.
    Future<List<String>> pumpSection(
      WidgetTester tester, {
      List<String> initial = const [],
    }) async {
      final items = <String>[...initial];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SingleChildScrollView(
                child: CustomAmenitySection(
                  items: items,
                  onChanged: (next) => setState(() {
                    items
                      ..clear()
                      ..addAll(next);
                  }),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return items;
    }

    testWidgets('검색 키워드를 받는 칸으로 읽히는 안내가 입력칸보다 먼저 있다', (tester) async {
      await pumpSection(tester);
      expect(find.text(CustomAmenities.inputGuide), findsOneWidget);
      expect(find.text(CustomAmenities.inputExamples), findsOneWidget);
      // 안내가 먼저, 추가 버튼이 나중.
      final guideY = tester.getTopLeft(find.text(CustomAmenities.inputGuide)).dy;
      final buttonY = tester.getTopLeft(find.text('＋ 기타 편의 서비스 추가')).dy;
      expect(guideY, lessThan(buttonY));
    });

    testWidgets('추가 버튼을 누르면 짧은 placeholder의 입력칸이 열린다', (tester) async {
      await pumpSection(tester);
      await tester.tap(find.text('＋ 기타 편의 서비스 추가'));
      await tester.pumpAndSettle();
      expect(find.text(CustomAmenities.inputHint), findsOneWidget);
    });

    testWidgets('여러 항목을 연달아 추가하면 항목 단위로 쌓인다', (tester) async {
      final items = await pumpSection(tester);
      await tester.tap(find.text('＋ 기타 편의 서비스 추가'));
      await tester.pumpAndSettle();

      for (final name in ['루프탑', '보드게임 대여']) {
        await tester.enterText(find.byType(TextField), name);
        await tester.tap(find.widgetWithText(TextButton, '추가'));
        await tester.pumpAndSettle();
      }

      expect(items, ['루프탑', '보드게임 대여']);
      expect(find.text('루프탑'), findsWidgets);
      expect(find.text('보드게임 대여'), findsWidgets);
    });

    testWidgets('앞뒤 공백은 떨어지고 표기 원문은 유지된다', (tester) async {
      final items = await pumpSection(tester);
      await tester.tap(find.text('＋ 기타 편의 서비스 추가'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  반려동물 물그릇  ');
      await tester.tap(find.widgetWithText(TextButton, '추가'));
      await tester.pumpAndSettle();

      expect(items, ['반려동물 물그릇']);
    });

    testWidgets('같은 항목을 표기만 바꿔 다시 넣으면 막는다', (tester) async {
      final items = await pumpSection(tester, initial: ['유아 의자']);
      await tester.tap(find.text('＋ 기타 편의 서비스 추가'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '유아의자');
      await tester.tap(find.widgetWithText(TextButton, '추가'));
      await tester.pumpAndSettle();

      expect(items, ['유아 의자']);
      expect(find.text('이미 추가한 편의 서비스예요.'), findsOneWidget);
    });

    testWidgets('빈 값은 저장되지 않는다', (tester) async {
      final items = await pumpSection(tester);
      await tester.tap(find.text('＋ 기타 편의 서비스 추가'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.widgetWithText(TextButton, '추가'));
      await tester.pumpAndSettle();

      expect(items, isEmpty);
    });

    testWidgets('긴 문장은 칸에서 잘리고 두세 단어는 그대로 들어간다', (tester) async {
      final items = await pumpSection(tester);
      await tester.tap(find.text('＋ 기타 편의 서비스 추가'));
      await tester.pumpAndSettle();

      // 입력칸 자체가 길이를 막는다 — 다 쓰고 나서 거절당하지 않게.
      await tester.enterText(
        find.byType(TextField),
        '루프탑에서 즐기는 특별한 밤을 선물해 드립니다 예약 문의 주세요',
      );
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(
        field.controller!.text.length,
        lessThanOrEqualTo(CustomAmenities.maxLength),
      );

      await tester.enterText(find.byType(TextField), '반려동물 물그릇');
      await tester.tap(find.widgetWithText(TextButton, '추가'));
      await tester.pumpAndSettle();
      expect(items, ['반려동물 물그릇'], reason: '두세 단어짜리 항목은 막으면 안 됩니다.');
    });

    testWidgets('X를 누르면 그 항목만 빠진다', (tester) async {
      final items = await pumpSection(
        tester,
        initial: ['루프탑', '보드게임 대여'],
      );
      // 칩의 X는 항목 순서대로 그려진다.
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();
      expect(items, ['보드게임 대여']);
    });
  });

  group('게스트 탐색 시트', () {
    /// [labels]를 가진 플레이스들로 목록을 만든다.
    List<CustomAmenityEntry> catalog(List<List<String>> docs) =>
        CustomAmenities.catalogOf(docs.map(_place));

    Future<Set<String>?> openSheet(
      WidgetTester tester,
      List<CustomAmenityEntry> entries, {
      Set<String> selected = const {},
    }) async {
      Set<String>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await CustomAmenityBrowseSheet.open(
                    context,
                    entries: entries,
                    selected: selected,
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
      return result;
    }

    testWidgets('있음/없음이 아니라 실제 항목과 개수를 보여준다', (tester) async {
      await openSheet(
        tester,
        catalog([
          ['루프탑', '보드게임 대여'],
          ['루프탑'],
        ]),
      );
      expect(find.text('루프탑'), findsOneWidget);
      expect(find.text('보드게임 대여'), findsOneWidget);
      expect(find.text('2'), findsOneWidget); // 루프탑 2건
      expect(find.text('1'), findsOneWidget); // 보드게임 대여 1건
    });

    testWidgets('0건 항목은 목록에 없다', (tester) async {
      await openSheet(tester, catalog([['루프탑']]));
      expect(find.text('수영장'), findsNothing);
    });

    testWidgets('항목이 적으면 초성 탭 없이 전부 보여준다', (tester) async {
      await openSheet(
        tester,
        catalog([
          ['루프탑', '보드게임 대여'],
        ]),
      );
      expect(find.text('전체'), findsNothing);
      expect(find.text('루프탑'), findsOneWidget);
    });

    testWidgets('항목이 많으면 초성 탭이 붙고 한글/영문/숫자가 갈린다', (tester) async {
      final many = [
        for (var i = 0; i < CustomAmenities.initialTabThreshold; i++) '항목$i',
        '루프탑',
        '레이저 조명',
        '보드게임 대여',
        'BBQ',
        '4K 빔프로젝터',
      ];
      await openSheet(tester, catalog([many]));

      expect(find.text('전체'), findsOneWidget);
      // 실제로 항목이 있는 묶음만 탭으로 나온다.
      for (final tab in ['ㄹ', 'ㅂ', 'ㅎ', 'B', '0-9']) {
        expect(find.text(tab), findsWidgets, reason: '$tab 탭이 있어야 합니다.');
      }
      expect(find.text('ㅋ'), findsNothing, reason: '비어 있는 묶음은 탭도 없어야 합니다.');
    });

    testWidgets('초성 탭을 누르면 그 묶음만 남는다', (tester) async {
      final many = [
        for (var i = 0; i < CustomAmenities.initialTabThreshold; i++) '항목$i',
        '루프탑',
        '레이저 조명',
        '보드게임 대여',
      ];
      await openSheet(tester, catalog([many]));

      await tester.tap(find.text('ㄹ').first);
      await tester.pumpAndSettle();
      expect(find.text('루프탑'), findsOneWidget);
      expect(find.text('레이저 조명'), findsOneWidget);
      expect(find.text('보드게임 대여'), findsNothing);
    });

    testWidgets('여러 개를 고르면 고른 항목이 그대로 돌아온다', (tester) async {
      Set<String>? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  picked = await CustomAmenityBrowseSheet.open(
                    context,
                    entries: catalog([
                      ['루프탑', '보드게임 대여', '유아 의자'],
                    ]),
                    selected: const {},
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

      await tester.tap(find.text('루프탑'));
      await tester.tap(find.text('보드게임 대여'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2개 적용'));
      await tester.pumpAndSettle();

      expect(picked, {'루프탑', '보드게임 대여'});
    });

    testWidgets('이미 고른 항목은 켜진 채로 열린다 — 표기가 달라도', (tester) async {
      await openSheet(
        tester,
        catalog([
          ['보드게임 대여'],
        ]),
        selected: {'보드게임대여'},
      );
      expect(find.text('1개 적용'), findsOneWidget);
    });

    testWidgets('등록된 기타가 하나도 없으면 그렇게 알린다', (tester) async {
      await openSheet(tester, const []);
      expect(find.text('아직 등록된 기타 편의 서비스가 없어요.'), findsOneWidget);
    });
  });

  // 플레이스와 장소대여 두 상세검색 시트가 **같은 탐색 UI**를 연다.
  group('두 탭의 상세검색이 같은 기타 탐색 시트를 연다', () {
    List<CustomAmenityEntry> catalog(List<String> labels) =>
        CustomAmenities.catalogOf([_place(labels)]);

    /// 시트를 띄우고 '기타 편의 서비스' 줄을 눌러 탐색 시트를 연다.
    Future<void> pumpAndOpen(WidgetTester tester, Widget sheet) async {
      tester.view.physicalSize = const Size(420, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: sheet)));
      await tester.pumpAndSettle();

      expect(find.text('기타 편의 서비스'), findsOneWidget);
      await tester.tap(find.text('기타 편의 서비스'));
      await tester.pumpAndSettle();
    }

    testWidgets('플레이스 상세검색 — 줄을 누르면 항목 목록이 열린다', (tester) async {
      await pumpAndOpen(
        tester,
        EventDetailSearchSheet(
          initialFilter: EventFilter(),
          customAmenityEntries: catalog(['루프탑', '보드게임 대여']),
        ),
      );
      expect(find.text('호스트가 직접 등록한 항목이에요'), findsOneWidget);
      expect(find.text('루프탑'), findsOneWidget);
    });

    testWidgets('장소대여 상세검색 — 같은 줄, 같은 시트', (tester) async {
      await pumpAndOpen(
        tester,
        PlaceDetailSearchSheet(
          initialFilter: PlaceFilter(),
          customAmenityEntries: catalog(['루프탑', '보드게임 대여']),
        ),
      );
      final sheet = find.byType(CustomAmenityBrowseSheet);
      expect(sheet, findsOneWidget);
      // ⚠️ 파인더를 시트 안으로 좁힌다 — 장소대여의 '장소 유형' 선택지에도
      // '루프탑'이 있어서(ListingConstants.placeTypes) 화면 전체로 찾으면
      // 두 개가 잡힌다. 이름이 겹칠 수 있다는 것 자체가 두 축이 다르다는
      // 증거이기도 하다.
      for (final label in ['루프탑', '보드게임 대여']) {
        expect(
          find.descendant(of: sheet, matching: find.text(label)),
          findsOneWidget,
        );
      }
    });

    testWidgets('장소대여 — 고른 항목이 실제로 PlaceFilter에 담겨 돌아온다', (tester) async {
      tester.view.physicalSize = const Size(420, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      PlaceFilter? applied;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  applied = await showModalBottomSheet<PlaceFilter>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => PlaceDetailSearchSheet(
                      initialFilter: PlaceFilter(),
                      customAmenityEntries: catalog(['보드게임 대여', '유아 의자']),
                    ),
                  );
                },
                child: const Text('상세검색'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('상세검색'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('기타 편의 서비스'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(CustomAmenityBrowseSheet),
          matching: find.text('보드게임 대여'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('1개 적용'));
      await tester.pumpAndSettle();

      // 상세검색 시트의 적용 — 여기서 나온 필터가 목록에 걸린다.
      await tester.tap(find.text('적용하기'));
      await tester.pumpAndSettle();

      expect(applied?.customAmenities, {'보드게임 대여'});
      expect(
        applied?.facilities,
        isEmpty,
        reason: '기타를 골랐다고 정식 편의시설 축이 켜지면 안 됩니다.',
      );
    });

    testWidgets('등록된 기타가 없으면 두 시트 모두 그 칸을 그리지 않는다', (tester) async {
      for (final sheet in [
        EventDetailSearchSheet(initialFilter: EventFilter()),
        PlaceDetailSearchSheet(initialFilter: PlaceFilter()),
      ]) {
        tester.view.physicalSize = const Size(420, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: sheet)));
        await tester.pumpAndSettle();
        expect(find.text('기타 편의 서비스'), findsNothing);
      }
    });

    testWidgets('장소대여의 정식 편의시설 칸은 그대로 남아 있다', (tester) async {
      tester.view.physicalSize = const Size(420, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaceDetailSearchSheet(
              initialFilter: PlaceFilter(),
              customAmenityEntries: catalog(['루프탑']),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 두 축이 나란히 선다 — 하나가 다른 하나를 대체하지 않는다.
      expect(find.text('편의시설'), findsOneWidget);
      expect(find.text('기타 편의 서비스'), findsOneWidget);
    });
  });

  group('카드 · 상세 표시', () {
    testWidgets("'기타' 한 단어가 아니라 실제 항목명을 보여준다", (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomAmenityView(
              data: _place(['루프탑', '보드게임 대여']),
              accent: const Color(0xFF7C5CBF),
            ),
          ),
        ),
      );
      expect(find.text('루프탑'), findsOneWidget);
      expect(find.text('보드게임 대여'), findsOneWidget);
      expect(find.text('기타'), findsNothing);
    });

    testWidgets('항목이 없는 기존 문서에는 아무것도 그리지 않는다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomAmenityView(
              data: const {},
              accent: Color(0xFF7C5CBF),
            ),
          ),
        ),
      );
      expect(find.text('✨ 기타 편의 서비스'), findsNothing);
    });

    test('카드 한 줄 요약은 앞에서 몇 개만 적고 나머지는 접는다', () {
      expect(
        CustomAmenitySummary.summaryOf(_place(['루프탑', '보드게임 대여'])),
        '루프탑 · 보드게임 대여',
      );
      expect(
        CustomAmenitySummary.summaryOf(
          _place(['루프탑', '보드게임 대여', '유아 의자', '반려동물 물그릇']),
        ),
        '루프탑 · 보드게임 대여 · 유아 의자 +1',
      );
      expect(CustomAmenitySummary.summaryOf(const {}), isNull);
    });
  });
}

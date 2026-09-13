// 🎲 기타 놀거리의 **게스트 쪽** — 목록으로 고르는 자리와 상세 표시.
//
// 여기서 확인하는 것은 두 가지다.
//  1. '기타'를 눌렀을 때 "기타인 곳 전부"가 아니라 **실제로 등록된 이름 목록**이
//     뜨고, 하나를 고르면 그 값을 등록한 곳만 남는가.
//  2. 상세에서 '기타'라고만 적히지 않고 호스트가 적은 이름이 그대로 보이는가.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/custom_play_item.dart';
import 'package:party_app/models/event_filter.dart';
import 'package:party_app/models/place_attributes.dart';
import 'package:party_app/widgets/custom_amenity_browse_sheet.dart';
import 'package:party_app/widgets/event_detail_search_sheet.dart';
import 'package:party_app/widgets/filter_sheet_ui.dart';
import 'package:party_app/widgets/place_attributes_view.dart';

Map<String, dynamic> _place({
  List<String> preset = const [],
  List<String> custom = const [],
  String category = '놀거리',
}) => {
  'placeCategory': category,
  if (preset.isNotEmpty)
    PlaceAttributeCatalog.field: {PlaceAttributeCatalog.playItemsKey: preset},
  if (custom.isNotEmpty) CustomPlayItems.field: custom,
};

Future<Set<String>?> openBrowse(
  WidgetTester tester, {
  required List<CustomPlayItemEntry> entries,
  Set<String> selected = const {},
}) async {
  Set<String>? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              result = await CustomAmenityBrowseSheet.open(
                context,
                entries: entries,
                selected: {...selected},
                title: CustomPlayItems.sectionTitle,
                subtitle: CustomPlayItems.browseSubtitle,
                emptyText: CustomPlayItems.emptyBrowseMessage,
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

void main() {
  group('기타 놀거리 목록', () {
    final docs = [
      _place(preset: ['기타'], custom: ['포켓볼', '테이블축구']),
      _place(preset: ['기타'], custom: ['포켓볼', '마작']),
      _place(preset: ['기타'], custom: ['VR게임']),
      _place(preset: ['기타'], custom: ['탁구']),
      _place(preset: ['다트']),
    ];

    testWidgets('등록된 이름만 뜬다 — 없는 항목은 만들지 않는다', (tester) async {
      await openBrowse(tester, entries: CustomPlayItems.catalogOf(docs));
      expect(find.text(CustomPlayItems.sectionTitle), findsOneWidget);
      for (final name in ['포켓볼', '테이블축구', '마작', 'VR게임', '탁구']) {
        expect(find.text(name), findsOneWidget, reason: '$name이 목록에 있어야 한다.');
      }
      expect(find.text('보드게임'), findsNothing);
      expect(find.text('기타'), findsNothing);
    });

    testWidgets('하나를 고르면 그 이름이 돌아온다', (tester) async {
      await openBrowse(tester, entries: CustomPlayItems.catalogOf(docs));
      await tester.tap(find.text('마작'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('적용'));
      await tester.pumpAndSettle();
      // 고른 값으로 필터를 걸면 그 값을 등록한 곳만 남는다.
      final filter = EventFilter(customPlayItems: {'마작'});
      expect(docs.where(filter.matchesDiscovery).toList(), [docs[1]]);
    });

    testWidgets('등록된 것이 없으면 그렇게 말한다', (tester) async {
      await openBrowse(tester, entries: const []);
      expect(find.text(CustomPlayItems.emptyBrowseMessage), findsOneWidget);
    });

    testWidgets('항목이 적으면 초성 탭을 억지로 띄우지 않는다', (tester) async {
      await openBrowse(tester, entries: CustomPlayItems.catalogOf(docs));
      expect(find.text('전체'), findsNothing);
    });

    testWidgets('항목이 많아지면 전체·초성 탭이 붙는다', (tester) async {
      final many = [
        for (var i = 0; i < CustomPlayItems.initialTabThreshold + 3; i++)
          _place(custom: ['놀거리$i']),
      ];
      await openBrowse(tester, entries: CustomPlayItems.catalogOf(many));
      expect(find.text('전체'), findsOneWidget);
    });
  });

  group('상세 표시', () {
    Future<void> pumpView(WidgetTester tester, Map<String, dynamic> data) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: PlaceAttributesView(data: data),
              ),
            ),
          ),
        );

    testWidgets("'기타' 대신 적어 둔 이름이 보인다", (tester) async {
      await pumpView(
        tester,
        _place(preset: ['보드게임', '기타'], custom: ['포켓볼', '테이블축구', '마작']),
      );
      expect(find.text('보드게임'), findsOneWidget);
      for (final name in ['포켓볼', '테이블축구', '마작']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('기타'), findsNothing, reason: "이름이 있으면 '기타'로 뭉개지 않는다.");
    });

    testWidgets('이름을 안 적었으면 예전처럼 기타가 그대로 남는다', (tester) async {
      await pumpView(tester, _place(preset: ['기타']));
      expect(find.text('기타'), findsOneWidget);
    });

    testWidgets('자유기재가 없는 옛 문서는 화면이 달라지지 않는다', (tester) async {
      await pumpView(tester, _place(preset: ['보드게임', '다트']));
      expect(find.text('보드게임'), findsOneWidget);
      expect(find.text('다트'), findsOneWidget);
      expect(find.textContaining('포켓볼'), findsNothing);
    });
  });

  group('상세검색 시트의 놀거리 줄', () {
    final entries = CustomPlayItems.catalogOf([
      _place(preset: ['기타'], custom: ['포켓볼', '마작']),
      _place(preset: ['기타'], custom: ['포켓볼']),
    ]);

    Future<EventFilter> pumpSheet(
      WidgetTester tester, {
      EventFilter? initial,
    }) async {
      final filter = initial ?? EventFilter();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EventDetailSearchSheet(
              initialFilter: filter,
              customPlayItemEntries: entries,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('세부 조건'));
      await tester.pumpAndSettle();
      return filter;
    }

    testWidgets("놀거리 '기타'를 누르면 등록된 이름 목록이 열린다", (tester) async {
      await pumpSheet(tester);
      // '기타' 칩은 생일 혜택 그룹에도 있으므로 놀거리 줄 안에서만 찾는다.
      final etc = find.descendant(
        of: find.byKey(EventDetailSearchSheet.playItemsRowKey),
        matching: find.widgetWithText(
          FilterOptionChip,
          CustomPlayItems.etcOption,
        ),
      );
      expect(etc, findsOneWidget);
      await tester.ensureVisible(etc);
      await tester.pumpAndSettle();
      await tester.tap(etc);
      await tester.pumpAndSettle();

      expect(find.text(CustomPlayItems.sectionTitle), findsOneWidget);
      expect(find.text('포켓볼'), findsOneWidget);
      expect(find.text('마작'), findsOneWidget);
      await tester.tap(find.text('포켓볼'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1개 적용'));
      await tester.pumpAndSettle();

      // 고른 값이 놀거리 줄에 그대로 드러난다 — 칩 이름과 그 아래 한 줄.
      final row = find.byKey(EventDetailSearchSheet.playItemsRowKey);
      expect(
        find.descendant(of: row, matching: find.text('기타 1')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('포켓볼')),
        findsOneWidget,
      );
    });
  });
}

// 플레이스 상세검색 시트의 **칸 구성**을 고정한다.
//
// 세 가지를 못 박는다(2026-08-27 정리):
//   ① 분위기 칸은 이 시트에 없다 — 📸 사진맛집은 ✨ 편의·서비스 시트가,
//      🎉 이벤트는 카테고리 영역이 같은 것을 묻는다.
//   ② 🎁 파티츄 혜택 선택지도 없다 — ✨ 편의·서비스 시트의 같은 칸이 맡는다.
//   ③ 🟢 현재 영업 중만 보기는 '기타 조건' 서랍에서 나와, 맨 아래
//      적용 버튼 **바로 위**의 독립 토글 카드가 됐다.
//
// ⚠ 셋 다 **화면에서만** 뺀 것이다. 값([EventFilter])도 판정
//   ([EventFilter.matchesDiscovery])도 하나도 건드리지 않았으므로, 다른
//   입구에서 켠 조건은 그대로 살아 있고 위 선택 칩에서 뺄 수도 있다.
//   아래 마지막 그룹이 그것까지 확인한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/event_filter.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/widgets/event_detail_search_sheet.dart';
import 'package:party_app/widgets/filter_sheet_ui.dart';

void main() {
  Future<EventFilter?> openSheet(
    WidgetTester tester, {
    EventFilter? initial,
    double width = 390,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    EventFilter? applied;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  applied = await showModalBottomSheet<EventFilter>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => EventDetailSearchSheet(
                      initialFilter: initial ?? EventFilter(),
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
    return applied;
  }

  group('1. 분위기 칸이 없다', () {
    testWidgets('아코디언 제목에도, 선택지에도 없다', (tester) async {
      await openSheet(tester);
      expect(find.text('분위기'), findsNothing);
      // 그 칸이 고르게 하던 값들도 시트 어디에도 없다.
      for (final tag in ListingConstants.placeThemeTags) {
        expect(
          find.textContaining(ListingConstants.placeThemeTagLabel(tag)),
          findsNothing,
          reason: tag,
        );
      }
    });
  });

  group('2. 🎁 파티츄 혜택 선택지가 없다', () {
    testWidgets('기타 조건 서랍째 사라졌다 — 열 칸 자체가 없다', (tester) async {
      await openSheet(tester);
      expect(find.text('기타 조건'), findsNothing);
      expect(find.textContaining('파티츄 혜택'), findsNothing);
    });
  });

  group('3. 🟢 현재 영업 중 — 서랍 밖 독립 토글 카드', () {
    const label = '🟢 현재 영업 중만 보기';

    testWidgets('접지 않아도 보인다', (tester) async {
      await openSheet(tester);
      expect(find.text(label), findsOneWidget);
      expect(find.byType(FilterToggleCard), findsOneWidget);
      // 서랍이 아니라 카드다 — 눌러서 펼치는 아코디언이 아니다.
      expect(
        find.descendant(
          of: find.byType(FilterAccordionSection),
          matching: find.text(label),
        ),
        findsNothing,
      );
    });

    testWidgets('적용 버튼 바로 위에 있다 — 마지막 아코디언보다 아래다', (tester) async {
      await openSheet(tester);
      final card = tester.getRect(find.byType(FilterToggleCard));
      final apply = tester.getRect(find.text('적용하기'));
      final lastAccordion = tester.getRect(find.text('가격대'));

      expect(
        card.top,
        greaterThan(lastAccordion.bottom),
        reason: '가격대 칸보다 위에 있다',
      );
      expect(card.bottom, lessThanOrEqualTo(apply.top), reason: '적용 버튼과 겹친다');
    });

    testWidgets('켜면 기존 값 하나(openNowOnly)가 그대로 바뀐다', (tester) async {
      await openSheet(tester);
      await tester.tap(find.text('적용하기'));
      await tester.pumpAndSettle();
      // 아무것도 안 건드리면 꺼진 채로 나온다.

      await openSheet(tester);
      await tester.tap(find.text('🟢 현재 영업 중만 보기'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Switch>(find.byType(Switch)).value,
        isTrue,
        reason: '카드를 눌러도 스위치가 넘어가야 한다',
      );
    });

    testWidgets('켠 채로 열면 켜진 상태로 복원된다', (tester) async {
      await openSheet(tester, initial: EventFilter(openNowOnly: true));
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    });
  });

  group('4. 화면에서만 뺐다 — 값과 판정은 그대로', () {
    test('빠진 두 조건의 필드가 EventFilter에 그대로 있다', () {
      final f = EventFilter(themeTags: {'핫플'}, partychuPerkOnly: true);
      expect(f.themeTags, {'핫플'});
      expect(f.partychuPerkOnly, isTrue);
      expect(f.isActive, isTrue, reason: '조건으로 계속 살아 있어야 한다');
    });

    testWidgets('다른 입구에서 켠 값은 시트를 열어도 풀리지 않고, 칩에서 뺄 수 있다', (tester) async {
      await openSheet(
        tester,
        initial: EventFilter(themeTags: {'핫플'}, partychuPerkOnly: true),
      );
      // 고를 자리는 없어도, 걸려 있다는 사실은 위 선택 칩에 그대로 보인다.
      expect(find.byType(FilterSelectedChips), findsOneWidget);
      final chips = tester.widget<FilterSelectedChips>(
        find.byType(FilterSelectedChips),
      );
      final keys = chips.entries.map((e) => e.key).toSet();
      expect(keys, containsAll(<String>['themeTags', 'partychuPerkOnly']));
    });
  });
}

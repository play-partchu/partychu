import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/event_filter.dart';
import 'package:party_app/models/place_quick_picks.dart';
import 'package:party_app/models/place_taxonomy.dart';

/// 푸드 업종 칩('🍽 업종')의 약속을 고정한다.
///
/// 소분류를 드릴다운 줄에서 시트로 옮긴 것은 **표현 방식**만 바꾼 것이라,
/// 켜는 값도([EventFilter.subcategories]) 판정도
/// ([EventFilter.matchesDiscovery]) 예전 그대로여야 한다. 나라별 소분류로
/// 이미 등록된 문서가 '글로벌푸드' 조건에서 빠지지 않는 것이 핵심이다.
void main() {
  PlaceQuickPick chipLabeled(String label) =>
      PlaceQuickPicks.foodKinds().firstWhere((p) => p.display == label);

  Map<String, dynamic> place(List<String> subs) => {
    'name': '테스트 식당',
    'placeCategory': '맛집',
    'placeSubcategories': subs,
  };

  group('업종 시트의 선택지', () {
    test('노출 순서가 정본 그대로다 — 고기·BBQ가 맨 앞, 기타가 맨 뒤', () {
      final labels = PlaceQuickPicks.foodKinds().map((p) => p.display).toList();
      expect(labels, ['고기·BBQ', '해산물', '한식', '중식', '일식', '양식', '글로벌푸드', '기타']);
    });

    // 순서를 화면마다 따로 늘어놓으면 같은 업종이 자리마다 다른 칸에 있게
    // 된다. 등록 화면([PlaceCategorySection])과 상세검색 시트는 정본 목록을
    // 그대로 훑으므로, 시트도 같은 목록에서 나왔는지를 여기서 못박는다.
    test('시트 순서는 정본 목록(PlaceTaxonomy.restaurant)에서 나온다', () {
      final sheet = PlaceQuickPicks.foodKinds()
          .map((p) => p.values.first)
          .toList();
      final canonical = [
        for (final s in PlaceTaxonomy.restaurant.subcategories)
          if (!PlaceTaxonomy.legacyGlobalFoodSubcategories.contains(s)) s,
      ];
      expect(sheet, canonical, reason: '나라별 여섯 칸을 접는 것 말고는 정본 순서와 같아야 한다');
    });

    test('나라별 칸은 선택지에서 사라지고, 나머지 기존 소분류는 남는다', () {
      final labels = PlaceQuickPicks.foodKinds().map((p) => p.display).toSet();
      for (final legacy in PlaceTaxonomy.legacyGlobalFoodSubcategories) {
        expect(labels, isNot(contains(legacy)), reason: '$legacy은 글로벌푸드로 묶였다');
      }
      expect(labels, containsAll(['양식', '해산물', '기타']));
    });

    test('푸드 드릴다운 줄은 비어 있다 — 업종 칩이 그 자리를 대신한다', () {
      expect(
        PlaceQuickPicks.drillFor(category: PlaceTaxonomy.restaurant.label),
        isEmpty,
      );
      // 다른 대분류는 그대로 드릴다운을 쓴다.
      expect(
        PlaceQuickPicks.drillFor(category: PlaceTaxonomy.cafe.label),
        isNotEmpty,
      );
    });

    test('푸드 빠른필터 줄의 첫 칸이 업종 시트 칩이다', () {
      final row = PlaceQuickPicks.forCategory(PlaceTaxonomy.restaurant.label);
      expect(row.first.opensSheet, isTrue);
      expect(row.first.display, '🍽 업종');
      expect(row.first.sheetTitle, '어떤 음식점을 찾으세요?');
    });
  });

  group('켜고 끄기', () {
    test('한 칸을 켜면 그 저장값 하나만 들어간다', () {
      final f = EventFilter(categories: {'맛집'});
      chipLabeled('고기·BBQ').toggle(f);
      expect(f.subcategories, {'고기·BBQ'});
    });

    test('글로벌푸드는 정본 값 하나만 심는다 — 옛 값 여섯을 흩뿌리지 않는다', () {
      final f = EventFilter(categories: {'맛집'});
      chipLabeled('글로벌푸드').toggle(f);
      expect(f.subcategories, {PlaceTaxonomy.globalFood});
    });

    test('상세검색에서 옛 나라별 값을 켜 두었어도 글로벌푸드 칸이 켜져 보이고, 끌 수 있다', () {
      final f = EventFilter(categories: {'맛집'}, subcategories: {'멕시칸', '태국'});
      final global = chipLabeled('글로벌푸드');
      expect(global.isOn(f), isTrue, reason: '안 보이는데 걸려 있는 조건을 만들지 않는다');
      global.toggle(f);
      expect(f.subcategories, isEmpty, reason: '끄고 나면 흔적이 남지 않는다');
    });

    test('업종 칩은 고른 개수를 자기 이름으로 말한다', () {
      final f = EventFilter(categories: {'맛집'});
      final chip = PlaceQuickPicks.foodKindChip();
      expect(chip.displayFor(f), '🍽 업종');

      chipLabeled('고기·BBQ').toggle(f);
      expect(chip.displayFor(f), '🍽 고기·BBQ');

      chipLabeled('한식').toggle(f);
      chipLabeled('중식').toggle(f);
      expect(chip.displayFor(f), '🍽 업종 3');
    });

    test('시트의 초기화는 이 칩이 켠 것만 전부 끈다', () {
      final f = EventFilter(categories: {'맛집'});
      chipLabeled('고기·BBQ').toggle(f);
      chipLabeled('글로벌푸드').toggle(f);
      PlaceQuickPicks.foodKindChip().clear(f);
      expect(f.subcategories, isEmpty);
    });
  });

  group('판정 — 저장값은 그대로 두고 매칭으로만 잇는다', () {
    test('글로벌푸드를 고르면 옛 나라별 값으로 등록된 곳도 함께 걸린다', () {
      final f = EventFilter(categories: {'맛집'});
      chipLabeled('글로벌푸드').toggle(f);

      expect(f.matchesDiscovery(place([PlaceTaxonomy.globalFood])), isTrue);
      for (final legacy in PlaceTaxonomy.legacyGlobalFoodSubcategories) {
        expect(f.matchesDiscovery(place([legacy])), isTrue, reason: legacy);
      }
      expect(f.matchesDiscovery(place(['한식'])), isFalse);
    });

    test('나라별 값을 콕 집어 고른 사람에게는 넓히지 않는다', () {
      final f = EventFilter(categories: {'맛집'}, subcategories: {'멕시칸'});
      expect(f.matchesDiscovery(place(['멕시칸'])), isTrue);
      expect(
        f.matchesDiscovery(place([PlaceTaxonomy.globalFood])),
        isFalse,
        reason: '좁힌 뜻이 사라지면 안 된다',
      );
    });

    test('나머지 업종은 예전 그대로 그 값 하나로만 걸린다', () {
      final f = EventFilter(categories: {'맛집'});
      chipLabeled('고기·BBQ').toggle(f);
      expect(f.matchesDiscovery(place(['고기·BBQ'])), isTrue);
      expect(f.matchesDiscovery(place(['한식'])), isFalse);
    });

    test('저장 taxonomy는 건드리지 않았다 — 등록 화면의 소분류는 그대로다', () {
      expect(
        PlaceTaxonomy.restaurant.subcategories,
        containsAll(PlaceTaxonomy.legacyGlobalFoodSubcategories),
      );
    });
  });
}

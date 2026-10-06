// 🎸 라이브클럽 — 새 대분류의 계약.
//
// 새 업종을 하나 더하는 일에서 실제로 위험한 것은 새 업종이 아니라 **옆에 있던
// 것**이다. '클럽'으로 등록된 가게가 조용히 새 칸으로 빨려 가거나, 반대로
// 라이브클럽 호스트가 고른 값이 저장 직전에 털려 나가는 쪽이 사고다. 둘 다
// 화면을 눈으로 봐서는 알 수 없어서 여기서 못 박는다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/place_attributes.dart';
import 'package:party_app/models/place_feature.dart';
import 'package:party_app/models/place_quick_picks.dart';
import 'package:party_app/models/place_taxonomy.dart';
import 'package:party_app/widgets/place_form/place_category_section.dart';

void main() {
  const label = '라이브클럽';

  group('대분류로 서 있다', () {
    test('고를 수 있고, 🎸로 라이브클럽이라 부른다', () {
      expect(PlaceTaxonomy.selectable.map((c) => c.label), contains(label));
      expect(PlaceTaxonomy.liveClub.emoji, '🎸');
      expect(PlaceTaxonomy.liveClub.displayName, label);
      expect(PlaceTaxonomy.liveClub.display, '🎸 라이브클럽');
      expect(PlaceTaxonomy.emojiOf(label), '🎸');
      expect(PlaceTaxonomy.displayOf(label), '🎸 라이브클럽');
      // 저장값 그대로 부른다 — name/aliases로 갈라 둔 대분류가 아니다.
      expect(PlaceTaxonomy.canonical(label), label);
    });

    test('클럽 바로 뒤에 선다 — 가장 헷갈리는 짝이라 나란히 보여야 한다', () {
      final all = PlaceTaxonomy.all.map((c) => c.label).toList();
      expect(all.indexOf(label), all.indexOf('클럽') + 1);
    });

    test('카테고리 바가 두 줄을 넘지 않는다 — 대분류 아홉이 상한이다', () {
      // 바는 한 줄 6칸이고 '전체'·'🎪 이벤트'·'파티샵'이 세 칸을 이미 쓴다.
      // 열을 넘기면 머리가 화면 1/3을 먹는다(place_filter_bars_height_test).
      expect(PlaceTaxonomy.selectable.length, lessThanOrEqualTo(9));
    });
  });

  group('클럽과는 완전히 다른 업종이다', () {
    const club = {'placeCategory': '클럽'};
    const liveClub = {'placeCategory': label};

    test('서로의 칸에 걸리지 않는다', () {
      expect(PlaceTaxonomy.matchesCategory(club, label), isFalse);
      expect(PlaceTaxonomy.matchesCategory(liveClub, '클럽'), isFalse);
      expect(PlaceTaxonomy.matchesAnyCategory(club, {label}), isFalse);
      expect(PlaceTaxonomy.matchesAnyCategory(liveClub, {'클럽'}), isFalse);
    });

    test('기존 클럽 문서는 그대로 클럽이다 — 값도 해석도 안 움직인다', () {
      expect(PlaceTaxonomy.categoryOf(club), '클럽');
      expect(PlaceTaxonomy.matchesCategory(club, '클럽'), isTrue);
      // 옛 businessTypes에서 유추되는 클럽도 마찬가지다.
      const legacy = {
        'businessTypes': ['클럽'],
      };
      expect(PlaceTaxonomy.categoryOf(legacy), '클럽');
      expect(PlaceTaxonomy.matchesCategory(legacy, label), isFalse);
    });

    test('클럽으로 저절로 승격되거나 강등되지 않는다', () {
      expect(PlaceTaxonomy.categoryOf(liveClub), label);
      expect(PlaceTaxonomy.byLabel(label), same(PlaceTaxonomy.liveClub));
      // '라이브클럽'이 클럽의 별칭으로 새어 들어가 있으면 안 된다.
      expect(PlaceTaxonomy.club.aliases, isNot(contains(label)));
    });
  });

  group('소분류는 새 값을 만들지 않았다', () {
    test('넷 다 라이브·공연에서 쓰던 저장값 그대로다', () {
      for (final sub in PlaceTaxonomy.liveClub.subcategories) {
        expect(
          PlaceTaxonomy.live.allSubcategories,
          contains(sub),
          reason: '$sub은 새로 만든 값이다 — 옛 문서와 영영 갈라진다',
        );
      }
    });

    test('DJ 공연·라이브카페는 일부러 뺐다', () {
      // DJ는 🎧 특징이 정본이고, 라이브카페의 집은 카페다.
      expect(PlaceTaxonomy.liveClub.subcategories, isNot(contains('DJ 공연')));
      expect(PlaceTaxonomy.liveClub.subcategories, isNot(contains('라이브카페')));
    });

    test('재즈바로 좁히면 옛 라이브 재즈바와 새 라이브클럽 재즈바가 함께 나온다', () {
      const old = {
        'placeCategory': '라이브·공연',
        'placeSubcategories': ['재즈바'],
      };
      const fresh = {
        'placeCategory': label,
        'placeSubcategories': ['재즈바'],
      };
      for (final doc in [old, fresh]) {
        expect(PlaceTaxonomy.matchesAnySubcategory(doc, {'재즈바'}), isTrue);
      }
      // 두 대분류 모두 '재즈바'를 자기 것으로 인정한다 — 대분류를 켤 때
      // 저장해 둔 소분류 조건이 조용히 풀리지 않는다.
      expect(PlaceTaxonomy.hasSubcategory(label, '재즈바'), isTrue);
      expect(PlaceTaxonomy.hasSubcategory('라이브·공연', '재즈바'), isTrue);
    });
  });

  group('집이 없던 라이브 가게가 집을 얻었다', () {
    // 인디공연·공연장·DJ 공연은 술집에도 카페에도 넣을 수 없어 '전체'에서만
    // 찾히던 값이다. 무대가 중심인 업장이 바로 그 셋이다.
    for (final sub in ['인디공연', '공연장', 'DJ 공연']) {
      test('$sub 가게는 라이브클럽에서 함께 뜬다', () {
        final doc = {
          'placeCategory': '라이브·공연',
          'placeSubcategories': [sub],
        };
        expect(PlaceTaxonomy.matchesCategory(doc, label), isTrue);
        // 저장값은 그대로다 — 어디서 걸리는가만 늘었다.
        expect(PlaceTaxonomy.categoryOf(doc), '라이브·공연');
      });
    }

    test('라이브펍·재즈바는 예전처럼 술집에서 뜬다 — 옮기지 않았다', () {
      for (final sub in ['라이브펍', '재즈바']) {
        final doc = {
          'placeCategory': '라이브·공연',
          'placeSubcategories': [sub],
        };
        expect(PlaceTaxonomy.matchesCategory(doc, '술집'), isTrue);
        expect(PlaceTaxonomy.matchesCategory(doc, label), isFalse);
      }
      const cafe = {
        'placeCategory': '라이브·공연',
        'placeSubcategories': ['라이브카페'],
      };
      expect(PlaceTaxonomy.matchesCategory(cafe, '카페·디저트'), isTrue);
    });
  });

  group('특징', () {
    test('🎤 라이브가 저절로 켜진다 — 정의상 무대가 있는 곳이다', () {
      const doc = {'placeCategory': label};
      expect(PlaceFeatures.of(doc), contains(PlaceFeatures.live.key));
    });

    test('장르를 골라도 🎧 DJ는 켜지지 않는다 — 트는 것이 아니라 연주다', () {
      const doc = {
        'placeCategory': label,
        'placeAttributes': {
          'musicGenres': ['HIPHOP'],
        },
      };
      expect(PlaceFeatures.of(doc), isNot(contains(PlaceFeatures.dj.key)));
    });

    test('클럽은 예전 그대로 장르로 DJ가 켜진다', () {
      const doc = {
        'placeCategory': '클럽',
        'placeAttributes': {
          'musicGenres': ['HIPHOP'],
        },
      };
      expect(PlaceFeatures.of(doc), contains(PlaceFeatures.dj.key));
    });
  });

  group('등록 화면에서 고른 값이 저장 직전에 털리지 않는다', () {
    // featureKeys가 없는 그룹(음악 장르·주류 종류)은 categories에 이 대분류가
    // 없으면 pruneAttributesFor가 통째로 지운다 — 가장 조용한 사고다.
    test('장르·주류·콜키지·무제한이 그대로 남는다', () {
      var attrs = PlaceAttributes.empty();
      attrs = attrs.toggle(PlaceAttributeCatalog.musicGenresKey, 'HIPHOP');
      attrs = attrs.toggle(PlaceAttributeCatalog.alcoholTypesKey, '와인');
      attrs = attrs.toggle(
        PlaceAttributeCatalog.corkageKey,
        PlaceAttributeCatalog.corkageFree,
      );
      attrs = attrs.toggle(
        PlaceAttributeCatalog.unlimitedKey,
        PlaceAttributeCatalog.unlimitedBeer,
      );

      final pruned = pruneAttributesFor(attrs, label);
      expect(
        pruned.selected(PlaceAttributeCatalog.musicGenresKey),
        contains('HIPHOP'),
      );
      expect(
        pruned.selected(PlaceAttributeCatalog.alcoholTypesKey),
        contains('와인'),
      );
      expect(pruned.selected(PlaceAttributeCatalog.corkageKey), isNotEmpty);
      expect(pruned.selected(PlaceAttributeCatalog.unlimitedKey), isNotEmpty);
    });

    test('입장 정보를 물을 자리가 있다 — 라이브클럽도 입장료를 받는다', () {
      // clubEntry의 유일한 featureKey는 featuresCoveredElsewhere라
      // extraGroupsFor가 건지지 못한다. categories에 없으면 칸 자체가 없다.
      final keys = PlaceAttributeCatalog.askableFor(
        label,
      ).map((g) => g.key).toList();
      expect(keys, contains(PlaceAttributeCatalog.clubEntryKey));

      var attrs = PlaceAttributes.empty();
      attrs = attrs.toggle(
        PlaceAttributeCatalog.clubEntryKey,
        PlaceAttributeCatalog.clubEntryFree,
      );
      expect(
        pruneAttributesFor(attrs, label).selected(
          PlaceAttributeCatalog.clubEntryKey,
        ),
        isNotEmpty,
      );
    });

    test('업종 표에 먼저 뜨는 그룹이 클럽과 같은 얼굴이다', () {
      final head = PlaceAttributeCatalog.groupsFor(label).map((g) => g.key);
      expect(
        head,
        containsAll([
          PlaceAttributeCatalog.musicGenresKey,
          PlaceAttributeCatalog.clubEntryKey,
          PlaceAttributeCatalog.alcoholTypesKey,
          'dj',
        ]),
      );
    });
  });

  group('등록·수정 화면에서 실제로 고를 수 있다', () {
    Future<void> pumpSection(
      WidgetTester tester, {
      String? category,
      required ValueChanged<String?> onCategory,
      Set<String> subcategories = const {},
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PlaceCategorySection(
                category: category,
                subcategories: subcategories,
                onCategoryChanged: onCategory,
                onSubcategoryToggled: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('새 등록에서 🎸 라이브클럽 칩이 뜨고, 누르면 그 값이 올라간다', (tester) async {
      String? picked;
      await pumpSection(tester, onCategory: (v) => picked = v);

      final chip = find.text('🎸 라이브클럽');
      expect(chip, findsOneWidget);
      await tester.tap(chip);
      // 화면에 보이는 말이 아니라 **저장값**이 올라가야 한다.
      expect(picked, label);
    });

    testWidgets('고르면 세부 업종 넷이 펼쳐진다', (tester) async {
      await pumpSection(tester, category: label, onCategory: (_) {});

      expect(find.text('🎸 라이브클럽 세부 업종'), findsOneWidget);
      for (final sub in ['라이브펍', '재즈바', '인디공연', '공연장']) {
        expect(find.text(sub), findsOneWidget, reason: '$sub 칩이 없다');
      }
    });

    testWidgets('라이브클럽으로 저장된 가게를 수정해도 칩이 그대로 선택돼 있다', (tester) async {
      // 은퇴 대분류가 아니므로 selectable에 그냥 있어야 한다 — 수정 화면에서
      // 아무것도 안 고른 것처럼 뜨면 실수로 다른 업종을 눌러 덮어쓴다.
      await pumpSection(
        tester,
        category: label,
        subcategories: {'재즈바'},
        onCategory: (_) {},
      );
      expect(find.text('🎸 라이브클럽'), findsOneWidget);
      expect(find.text('재즈바'), findsOneWidget);
    });
  });

  group('상세·필터 화면이 이 대분류를 안다', () {
    test('상세화면 블록 표가 덮는다', () {
      expect(PlaceDetailBlocks.covers(label), isTrue);
      expect(PlaceDetailBlocks.coversAllCategories, isTrue);
    });

    test('빠른 조건과 편의 추천이 일반값으로 떨어지지 않는다', () {
      final picks = PlaceQuickPicks.forCategory(label);
      expect(picks, isNotEmpty);
      expect(picks, isNot(PlaceQuickPicks.forCategory(null)));
    });

    test('♾ 무제한 시트가 추천 갈래를 갖는다', () {
      final kinds = PlaceQuickPicks.unlimitedKinds(label);
      expect(kinds, isNotEmpty);
      // 클럽과 같은 갈래가 앞에 온다 — 마시는 것이 먼저다.
      expect(
        kinds.map((k) => k.display).take(4),
        PlaceQuickPicks.unlimitedKinds('클럽').map((k) => k.display).take(4),
      );
    });
  });
}

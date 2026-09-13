import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/place_attributes.dart';
import 'package:party_app/models/place_feature.dart';
import 'package:party_app/models/place_taxonomy.dart';

/// 2026-08-30 업종 정리의 **하위호환 계약**.
///
/// 이 정리에서 실제로 위험한 것은 새 대분류가 아니라 **이미 저장된 문서**다.
/// BAR·라이브·클럽으로 등록된 가게가 조용히 안 보이게 되는 것이 가장 큰 사고고,
/// 그건 화면을 눈으로 봐서는 알 수 없다. 그래서 여기서 못 박는다.
void main() {
  group('은퇴한 대분류 — 새로 고를 수 없지만 아무것도 잃지 않는다', () {
    test('BAR·라이브는 등록 목록에서 빠지고 읽기 목록에는 남는다', () {
      final selectable = PlaceTaxonomy.selectable.map((c) => c.label);
      expect(selectable, isNot(contains('BAR')));
      expect(selectable, isNot(contains('라이브·공연')));

      // 읽기의 정본에는 그대로 있다 — 여기서 빠지면 byLabel·categoryOf가
      // 통째로 null이 되어 옛 문서가 '미분류'로 떨어진다.
      final all = PlaceTaxonomy.all.map((c) => c.label);
      expect(all, containsAll(['BAR', '라이브·공연']));
      expect(PlaceTaxonomy.byLabel('BAR'), isNotNull);
      expect(PlaceTaxonomy.byLabel('라이브·공연'), isNotNull);
    });

    test('BAR로 저장된 문서는 대분류도 소분류도 그대로 읽힌다', () {
      const doc = {
        'placeCategory': 'BAR',
        'placeSubcategories': ['와인바'],
      };
      expect(PlaceTaxonomy.categoryOf(doc), 'BAR');
      expect(PlaceTaxonomy.subcategoriesOf(doc), ['와인바']);
      expect(PlaceTaxonomy.matchesCategory(doc, 'BAR'), isTrue);
      expect(PlaceTaxonomy.hasSubcategory('BAR', '와인바'), isTrue);
    });

    test('BAR 가게는 술집을 켜도 함께 걸린다 — 바에서 칸이 내려갔기 때문', () {
      const doc = {'placeCategory': 'BAR'};
      expect(PlaceTaxonomy.matchesAnyCategory(doc, {'술집'}), isTrue);
      // 저장값은 건드리지 않았다는 뜻 — 대분류는 여전히 BAR다.
      expect(PlaceTaxonomy.categoryOf(doc), 'BAR');
    });

    test('옛 businessTypes(바)도 예전 그대로 BAR로 유추된다', () {
      const doc = {
        'businessTypes': ['바'],
      };
      expect(PlaceTaxonomy.categoryOf(doc), 'BAR');
      expect(PlaceTaxonomy.matchesAnyCategory(doc, {'술집'}), isTrue);
    });

    test('라이브 가게는 🎤 라이브 특징이 그대로 자동으로 켜진다', () {
      const doc = {'placeCategory': '라이브·공연'};
      expect(PlaceFeatures.of(doc), contains(PlaceFeatures.live.key));
    });

    test('라이브펍·재즈바는 술집에서, 라이브카페는 카페에서 함께 뜬다', () {
      const jazz = {
        'placeCategory': '라이브·공연',
        'placeSubcategories': ['재즈바'],
      };
      expect(PlaceTaxonomy.matchesAnyCategory(jazz, {'술집'}), isTrue);

      const liveCafe = {
        'placeCategory': '라이브·공연',
        'placeSubcategories': ['라이브카페'],
      };
      expect(PlaceTaxonomy.matchesAnyCategory(liveCafe, {'카페·디저트'}), isTrue);

      // 집을 알 수 없는 값은 억지로 넣지 않는다 — 공연장이 술집에 뜨면 안 된다.
      const hall = {
        'placeCategory': '라이브·공연',
        'placeSubcategories': ['공연장'],
      };
      expect(PlaceTaxonomy.matchesAnyCategory(hall, {'술집'}), isFalse);
    });
  });

  group('클럽 → 클럽·댄스 — 저장값은 그대로다', () {
    test('저장값 클럽은 그대로고 부르는 이름만 바뀐다', () {
      expect(PlaceTaxonomy.club.label, '클럽');
      expect(PlaceTaxonomy.club.displayName, '클럽·댄스');
      expect(PlaceTaxonomy.byLabel('클럽'), PlaceTaxonomy.club);
      // 새 이름이 필터 값·딥링크로 들어와도 같은 대분류로 풀린다.
      expect(PlaceTaxonomy.byLabel('클럽·댄스'), PlaceTaxonomy.club);
      expect(PlaceTaxonomy.canonical('클럽·댄스'), '클럽');
    });

    test('되살린 소분류는 새 값이 아니라 옛 저장값이다', () {
      expect(PlaceTaxonomy.club.subcategories, containsAll(['라운지클럽', '댄스클럽']));
      // 은퇴 목록에서 옮겨온 것이므로 양쪽에 겹쳐 있으면 안 된다.
      for (final s in PlaceTaxonomy.club.subcategories) {
        expect(PlaceTaxonomy.club.retiredSubcategories, isNot(contains(s)));
      }
      // 옛 값도 여전히 이 대분류의 것으로 인정된다.
      expect(PlaceTaxonomy.hasSubcategory('클럽', '힙합클럽'), isTrue);
    });

    test('옛 힙합클럽은 여전히 장르로 읽힌다', () {
      const doc = {
        'placeCategory': '클럽',
        'placeSubcategories': ['힙합클럽'],
      };
      expect(PlaceTaxonomy.legacyClubGenresOf(doc), contains('HIPHOP'));
    });
  });

  group('다이닝·파인다이닝 — 음식 종류가 아니라 업장 스타일을 나눈다', () {
    test('고를 수 있는 소분류는 다이닝 / 파인다이닝 둘뿐이다', () {
      expect(PlaceTaxonomy.dining.subcategories, ['다이닝', '파인다이닝']);
    });

    test('음식 종류는 푸드가 맡는다 — 다이닝에서 새로 고를 수 없다', () {
      for (final kind in ['한식', '중식', '일식', '양식']) {
        expect(
          PlaceTaxonomy.dining.subcategories,
          isNot(contains(kind)),
          reason: '$kind은 푸드에서 찾는 개념이다',
        );
        expect(PlaceTaxonomy.restaurant.subcategories, contains(kind));
      }
    });

    test("'전체'는 저장값이 아니다 — 소분류를 안 고른 상태가 전체다", () {
      expect(PlaceTaxonomy.dining.allSubcategories, isNot(contains('전체')));
    });

    test('옛 음식 종류 값은 지워지지 않고 이 대분류의 것으로 남는다', () {
      for (final kind in ['한식', '중식', '일식', '양식', '고기·BBQ']) {
        expect(PlaceTaxonomy.dining.retiredSubcategories, contains(kind));
        // 대분류를 켰을 때 조용히 풀리지 않으려면 이게 참이어야 한다
        // (EventFilter가 이 규칙으로 소분류를 털어낸다).
        expect(PlaceTaxonomy.hasSubcategory('다이닝·파인다이닝', kind), isTrue);
      }
    });

    test('일식으로 좁히면 맛집 일식집과 옛 다이닝 일식집이 함께 나온다', () {
      const food = {
        'placeCategory': '맛집',
        'placeSubcategories': ['일식'],
      };
      // 소분류 축이 바뀌기 전에 저장된 문서.
      const legacyFine = {
        'placeCategory': '다이닝·파인다이닝',
        'placeSubcategories': ['일식'],
      };
      expect(PlaceTaxonomy.matchesAnySubcategory(food, {'일식'}), isTrue);
      expect(PlaceTaxonomy.matchesAnySubcategory(legacyFine, {'일식'}), isTrue);
      // 대분류도 예전 그대로 읽힌다 — 저장값을 건드리지 않았다는 뜻.
      expect(PlaceTaxonomy.categoryOf(legacyFine), '다이닝·파인다이닝');
      expect(PlaceTaxonomy.subcategoriesOf(legacyFine), ['일식']);
    });

    test('새 값도 같은 placeSubcategories 배열에 그냥 들어간다', () {
      const doc = {
        'placeCategory': '다이닝·파인다이닝',
        'placeSubcategories': ['파인다이닝'],
      };
      expect(PlaceTaxonomy.matchesAnySubcategory(doc, {'파인다이닝'}), isTrue);
      expect(PlaceTaxonomy.hasSubcategory('다이닝·파인다이닝', '파인다이닝'), isTrue);
    });

    test('음식 종류 소분류의 대분류 해석은 맛집으로 고정이다', () {
      // dining이 all에서 restaurant보다 뒤에 있어야 이 값이 흔들리지 않는다.
      expect(PlaceTaxonomy.categoryOfSubcategory('일식'), '맛집');
    });

    test('대분류 이름 되돌리기는 소분류 값에 흔들리지 않는다', () {
      // '다이닝'은 이제 대분류 별칭이면서 소분류 값이기도 하다. 두 이름
      // 공간은 섞이지 않는다 — canonical/byLabel은 대분류 자리에서만 쓴다.
      expect(PlaceTaxonomy.byLabel('다이닝'), PlaceTaxonomy.dining);
      expect(PlaceTaxonomy.canonical('파인다이닝'), '다이닝·파인다이닝');
    });

    test('저장할 때 주류·콜키지가 털려 나가지 않는다', () {
      // alcoholTypes는 featureKeys가 없어, categories에 빠지면
      // pruneAttributesFor가 값을 통째로 지운다(가장 조용한 사고).
      var attrs = PlaceAttributes.empty();
      attrs = attrs.toggle(PlaceAttributeCatalog.alcoholTypesKey, '와인');
      attrs = attrs.toggle(
        PlaceAttributeCatalog.corkageKey,
        PlaceAttributeCatalog.corkageFree,
      );
      final pruned = pruneAttributesFor(attrs, '다이닝·파인다이닝');
      expect(
        pruned.selected(PlaceAttributeCatalog.alcoholTypesKey),
        contains('와인'),
      );
      expect(pruned.selected(PlaceAttributeCatalog.corkageKey), isNotEmpty);
    });

    test('상세화면 블록 표가 대분류 전부를 덮는다', () {
      expect(PlaceDetailBlocks.coversAllCategories, isTrue);
    });
  });

  group('라이브 공연은 이미 있던 속성 자리를 쓴다 — 새 분류를 만들지 않았다', () {
    test('purposes의 라이브공연이 🎤 라이브를 켠다', () {
      expect(
        PlaceAttributeCatalog.purposes.hasOption('라이브공연'),
        isTrue,
        reason: '라이브 공연의 자리는 예전부터 여기였다',
      );
      var attrs = PlaceAttributes.empty();
      attrs = attrs.toggle(PlaceAttributeCatalog.purposesKey, '라이브공연');
      final doc = {
        'placeCategory': '술집',
        PlaceAttributeCatalog.field: attrs.toMap(),
      };
      expect(PlaceFeatures.of(doc), contains(PlaceFeatures.live.key));
    });

    test('노래 그룹은 그대로 남아 있다 — 이번에 합치지 않았다', () {
      final singing = PlaceAttributeCatalog.groupOf(
        PlaceAttributeCatalog.singingKey,
      );
      expect(singing, isNotNull);
      expect(singing!.featureKeys, containsAll(['노래가능', '노래신청']));
    });

    test('업종을 가리지 않고 물어본다 — 어느 대분류로 등록해도 자리가 있다', () {
      for (final c in PlaceTaxonomy.all) {
        expect(
          PlaceAttributeCatalog.askableFor(c.label),
          contains(PlaceAttributeCatalog.purposes),
          reason: c.label,
        );
      }
    });
  });
}

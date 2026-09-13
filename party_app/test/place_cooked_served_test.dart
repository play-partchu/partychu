// 🍽️ 조리되어 나와요 — 등록 → 저장 → 수정 재진입 → 필터 검색이 **같은 값**을 쓰는지.
//
// 이 항목은 새 저장 필드를 만들지 않는다. 호스트가 등록 화면 '조리 제공'에서
// 고르면 `placeAttributes.cookedService`에 저장되고, 게스트 필터는
// [PlaceFeatures.of]가 그 값에서 유도한 특징 하나로 거른다. 즉 등록·수정·
// 메인 필터·상세검색·지도 필터가 전부 이 한 경로를 지난다.
//
// 그래서 이 테스트가 보는 것은 넷이다.
//  1. 🔥 구워줘요와 **별개**로 켜지고 꺼진다(서로를 배제하지 않는다)
//  2. 저장값에 이모지가 없고, 화면 표기에서만 🍽️ 조리되어 나와요다
//  3. 등록 → 저장 → 수정 재진입에서 선택이 그대로 복원된다
//  4. 편의·서비스 목록에서 🔥 구워줘요 **바로 옆**에 선다

import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/place_attributes.dart';
import 'package:party_app/models/place_feature.dart';
import 'package:party_app/models/place_quick_picks.dart';
import 'package:party_app/models/place_taxonomy.dart';

void main() {
  /// 등록 화면이 저장하는 모양 그대로 — `placeAttributes` 안의 그룹 하나.
  Map<String, dynamic> docWith(PlaceAttributes attrs) => {
    PlaceAttributeCatalog.field: attrs.toMap(),
  };

  /// 호스트가 '조리 제공 > 조리되어 나옴'을 고른 상태.
  PlaceAttributes cookedPicked() => PlaceAttributes.empty().toggle(
    PlaceAttributeCatalog.cookedKey,
    PlaceAttributeCatalog.cookedServed,
  );

  group('정의 — 저장값과 표기', () {
    test('저장값에는 이모지가 없다', () {
      expect(PlaceAttributeCatalog.cookedServed, '조리되어 나옴');
      expect(PlaceFeatures.cookedServed.key, '조리제공');
      for (final v in [
        PlaceAttributeCatalog.cookedServed,
        PlaceFeatures.cookedServed.key,
      ]) {
        expect(v.contains('🍽'), isFalse, reason: '저장값에 이모지가 섞였다: $v');
      }
    });

    test('화면 표기는 🍽️ 조리되어 나와요다 — "조리해서"가 아니다', () {
      expect(PlaceFeatures.cookedServed.display, '🍽️ 조리되어 나와요');
      expect(
        PlaceAttributeCatalog.cookedPhrase(PlaceAttributeCatalog.cookedServed),
        '조리되어 나와요',
      );
      expect(
        PlaceAttributeCatalog.phraseOf(
          PlaceAttributeCatalog.cookedKey,
          PlaceAttributeCatalog.cookedServed,
        ),
        '조리되어 나와요',
      );
      // 표기가 '조리해서 나와요'로 흘러가지 않게 못 박는다.
      expect(PlaceFeatures.cookedServed.label, isNot(contains('조리해서')));
    });

    test('공용 어휘와 선택 가능 목록에 한 번씩만 들어 있다', () {
      expect(
        PlaceFeatures.all.where((f) => f.key == PlaceFeatures.cookedServed.key),
        hasLength(1),
      );
      expect(PlaceFeatures.selectable, contains(PlaceFeatures.cookedServed));
      expect(PlaceFeatures.cookedServed.retired, isFalse);
      expect(
        PlaceFeatures.byKey(PlaceFeatures.cookedServed.key),
        PlaceFeatures.cookedServed,
      );
    });
  });

  group('구워줘요와 별개다', () {
    test('조리 제공만 골라도 켜진다 — 구워줌은 꺼진 채로', () {
      final features = PlaceFeatures.of(docWith(cookedPicked()));
      expect(features, contains(PlaceFeatures.cookedServed.key));
      expect(features, isNot(contains(PlaceFeatures.grill.key)));
    });

    test('구워줌만 골라도 조리 제공은 켜지지 않는다', () {
      final attrs = PlaceAttributes.empty().toggle(
        PlaceAttributeCatalog.grillKey,
        PlaceAttributeCatalog.grillAll,
      );
      final features = PlaceFeatures.of(docWith(attrs));
      expect(features, contains(PlaceFeatures.grill.key));
      expect(features, isNot(contains(PlaceFeatures.cookedServed.key)));
    });

    test('둘 다 고를 수 있다 — 서로를 대체하지 않는다', () {
      // 직원이 구워주면서 밑반찬도 조리되어 나오는 가게.
      final attrs = cookedPicked().toggle(
        PlaceAttributeCatalog.grillKey,
        PlaceAttributeCatalog.grillAll,
      );
      final features = PlaceFeatures.of(docWith(attrs));
      expect(
        features,
        containsAll([PlaceFeatures.grill.key, PlaceFeatures.cookedServed.key]),
      );
    });

    test('별도 그룹이라 구워주는 서비스의 단일선택에 걸리지 않는다', () {
      expect(
        PlaceAttributeCatalog.cookedKey,
        isNot(PlaceAttributeCatalog.grillKey),
      );
      // 구워주는 서비스는 하나만 고르는 그룹이다 — 여기에 선택지를 더했다면
      // 두 조건을 동시에 켤 수 없었을 것이다.
      expect(PlaceAttributeCatalog.grillService.singleChoice, isTrue);
      expect(
        PlaceAttributeCatalog.grillService.hasOption(
          PlaceAttributeCatalog.cookedServed,
        ),
        isFalse,
        reason: '구워주는 서비스 그룹에 섞이면 안 된다',
      );
    });
  });

  group('등록 → 저장 → 수정 재진입', () {
    test('저장한 값이 그대로 복원된다', () {
      final saved = docWith(cookedPicked());
      // 저장 모양 확인 — 그룹 키 아래 배열 하나.
      expect(saved[PlaceAttributeCatalog.field], {
        PlaceAttributeCatalog.cookedKey: [PlaceAttributeCatalog.cookedServed],
      });

      // 수정 화면이 문서에서 다시 읽어 들이는 경로.
      final restored = PlaceAttributes.fromDoc(saved);
      expect(
        restored.isSelected(
          PlaceAttributeCatalog.cookedKey,
          PlaceAttributeCatalog.cookedServed,
        ),
        isTrue,
      );
      // 다시 저장해도 같은 값이다(왕복이 값을 바꾸지 않는다).
      expect(restored.toMap(), saved[PlaceAttributeCatalog.field]);
    });

    test('임시저장(Draft) 왕복에서도 살아남는다', () {
      final restored = PlaceAttributes.fromDraftMap(
        cookedPicked().toDraftMap(),
      );
      expect(
        restored.isSelected(
          PlaceAttributeCatalog.cookedKey,
          PlaceAttributeCatalog.cookedServed,
        ),
        isTrue,
      );
    });

    test('끄면 저장값에서 사라지고 특징도 꺼진다', () {
      final off = cookedPicked().toggle(
        PlaceAttributeCatalog.cookedKey,
        PlaceAttributeCatalog.cookedServed,
      );
      expect(off.toMap().containsKey(PlaceAttributeCatalog.cookedKey), isFalse);
      expect(
        PlaceFeatures.of(docWith(off)),
        isNot(contains(PlaceFeatures.cookedServed.key)),
      );
    });
  });

  group('필터 검색', () {
    test('이 특징으로 검색하면 고른 플레이스만 걸린다', () {
      final picked = docWith(cookedPicked());
      final plain = docWith(PlaceAttributes.empty());
      final wanted = {PlaceFeatures.cookedServed.key};

      expect(PlaceFeatures.matchesAll(picked, wanted), isTrue);
      expect(PlaceFeatures.matchesAll(plain, wanted), isFalse);
    });

    test('구워줌만 켠 플레이스는 이 필터에 걸리지 않는다', () {
      final grillOnly = docWith(
        PlaceAttributes.empty().toggle(
          PlaceAttributeCatalog.grillKey,
          PlaceAttributeCatalog.grillAll,
        ),
      );
      expect(
        PlaceFeatures.matchesAll(grillOnly, {PlaceFeatures.cookedServed.key}),
        isFalse,
      );
    });

    test('옛 문서(값 없음)는 영향을 받지 않는다', () {
      // 기존 데이터를 건드리지 않았다는 뜻 — 새 필드가 없어도 그대로 동작한다.
      const legacy = <String, dynamic>{'name': '옛 가게'};
      expect(
        PlaceFeatures.of(legacy),
        isNot(contains(PlaceFeatures.cookedServed.key)),
      );
      expect(
        PlaceFeatures.matchesAll(legacy, {PlaceFeatures.cookedServed.key}),
        isFalse,
      );
    });
  });

  group('편의·서비스에서 구워줘요 바로 옆에 선다', () {
    // 구워주는 서비스를 묻는 업종에서는 두 칸이 붙어 있어야 한다.
    for (final category in PlaceAttributeCatalog.grillService.categories) {
      test('$category — 🔥 구워줘요 다음이 🍽️ 조리되어 나와요다', () {
        final kinds = PlaceQuickPicks.amenityKinds(category);
        final keys = [for (final k in kinds) ...k.values];
        final grillAt = keys.indexOf(PlaceFeatures.grill.key);
        final cookedAt = keys.indexOf(PlaceFeatures.cookedServed.key);

        expect(grillAt, isNonNegative, reason: '구워줘요가 시트에 없다');
        expect(cookedAt, isNonNegative, reason: '조리되어 나와요가 시트에 없다');
        expect(
          cookedAt,
          grillAt + 1,
          reason: '나란히 있지 않다: $grillAt vs $cookedAt',
        );
      });
    }

    test('등록 화면에서도 구워주는 서비스 바로 다음에 묻는다', () {
      final groups = PlaceAttributeCatalog.groupsFor(
        PlaceTaxonomy.restaurant.label,
      );
      final keys = [for (final g in groups) g.key];
      expect(
        keys.indexOf(PlaceAttributeCatalog.cookedKey),
        keys.indexOf(PlaceAttributeCatalog.grillKey) + 1,
      );
    });

    test('구워주는 서비스와 같은 업종에서 묻는다', () {
      expect(
        PlaceAttributeCatalog.cookedService.categories,
        PlaceAttributeCatalog.grillService.categories,
      );
    });
  });
}

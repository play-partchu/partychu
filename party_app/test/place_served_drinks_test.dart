import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/event_filter.dart';
import 'package:party_app/models/place_attributes.dart';
import 'package:party_app/models/place_feature.dart';
import 'package:party_app/models/place_quick_picks.dart';
import 'package:party_app/models/place_taxonomy.dart';

/// 🥃 하이볼 · 🏺 막걸리 — **등록 → 저장 → 복원 → 카드 → 상세 → 필터**가
/// 같은 값 하나를 공유하는지 전 구간으로 확인한다.
///
/// 두 항목은 서로 독립이다. 하나만 판다고 다른 하나가 켜지면 안 된다.
void main() {
  Map<String, dynamic> docWith(
    List<String> served, {
    List<String> alcohol = const [],
  }) => {
    'name': '가게',
    'placeCategory': PlaceTaxonomy.bar.label,
    PlaceAttributeCatalog.field: {
      if (served.isNotEmpty) PlaceAttributeCatalog.servedDrinksKey: served,
      if (alcohol.isNotEmpty) PlaceAttributeCatalog.alcoholTypesKey: alcohol,
    },
  };

  final highballOnly = docWith([PlaceAttributeCatalog.highballServed]);
  final makgeolliOnly = docWith([PlaceAttributeCatalog.makgeolliServed]);
  final both = docWith([
    PlaceAttributeCatalog.highballServed,
    PlaceAttributeCatalog.makgeolliServed,
  ]);
  final neither = docWith(const []);

  group('① 등록·수정 화면에서 켤 수 있다', () {
    test('그룹이 카탈로그에 있고 두 값을 모두 가진다', () {
      final group = PlaceAttributeCatalog.groupOf(
        PlaceAttributeCatalog.servedDrinksKey,
      );
      expect(group, isNotNull);
      expect(group!.hasOption(PlaceAttributeCatalog.highballServed), isTrue);
      expect(group.hasOption(PlaceAttributeCatalog.makgeolliServed), isTrue);
      // 단일 선택이 아니다 — 둘 다 파는 집이 있다.
      expect(group.singleChoice, isFalse);
    });

    test('업종을 가리지 않는다 — 하이볼 파는 카페도 켤 자리가 있다', () {
      final group = PlaceAttributeCatalog.groupOf(
        PlaceAttributeCatalog.servedDrinksKey,
      )!;
      for (final c in PlaceTaxonomy.all) {
        expect(
          PlaceAttributeCatalog.askableFor(c.label),
          contains(group),
          reason: c.label,
        );
      }
    });

    test('기존 주류 종류 그룹은 그대로다 — 업종 안에 머문다', () {
      final alcohol = PlaceAttributeCatalog.groupOf(
        PlaceAttributeCatalog.alcoholTypesKey,
      )!;
      expect(alcohol.featureKeys, isEmpty);
      expect(
        PlaceAttributeCatalog.groupsFor(PlaceTaxonomy.cafe.label),
        isNot(contains(alcohol)),
      );
    });
  });

  group('② 저장 → 재진입 복원', () {
    test('고른 값이 그대로 되살아난다', () {
      final restored = PlaceAttributes.fromDoc(both);
      expect(
        restored.isSelected(
          PlaceAttributeCatalog.servedDrinksKey,
          PlaceAttributeCatalog.highballServed,
        ),
        isTrue,
      );
      expect(
        restored.isSelected(
          PlaceAttributeCatalog.servedDrinksKey,
          PlaceAttributeCatalog.makgeolliServed,
        ),
        isTrue,
      );
    });

    test('복원 → 다시 저장해도 값이 유실되지 않는다', () {
      final restored = PlaceAttributes.fromDoc(both);
      final saved = restored.toMap();
      expect(saved[PlaceAttributeCatalog.servedDrinksKey], hasLength(2));
    });

    test('하나만 켠 문서는 하나만 복원된다', () {
      final restored = PlaceAttributes.fromDoc(highballOnly);
      expect(
        restored.isSelected(
          PlaceAttributeCatalog.servedDrinksKey,
          PlaceAttributeCatalog.makgeolliServed,
        ),
        isFalse,
      );
    });
  });

  group('③ 특징 유도 — 서로 독립이다', () {
    test('하이볼만 판매 → 하이볼만 켜진다', () {
      final f = PlaceFeatures.of(highballOnly);
      expect(f, contains(PlaceFeatures.highball.key));
      expect(f, isNot(contains(PlaceFeatures.makgeolli.key)));
    });

    test('막걸리만 판매 → 막걸리만 켜진다', () {
      final f = PlaceFeatures.of(makgeolliOnly);
      expect(f, contains(PlaceFeatures.makgeolli.key));
      expect(f, isNot(contains(PlaceFeatures.highball.key)));
    });

    test('둘 다 판매 → 둘 다 켜진다', () {
      final f = PlaceFeatures.of(both);
      expect(f, contains(PlaceFeatures.highball.key));
      expect(f, contains(PlaceFeatures.makgeolli.key));
    });

    test('아무것도 안 켠 집은 어느 쪽도 켜지지 않는다', () {
      final f = PlaceFeatures.of(neither);
      expect(f, isNot(contains(PlaceFeatures.highball.key)));
      expect(f, isNot(contains(PlaceFeatures.makgeolli.key)));
    });

    test('주류 종류에 하이볼을 골라 둔 옛 문서도 걸린다(다리)', () {
      final legacy = docWith(const [], alcohol: ['하이볼', '와인']);
      expect(PlaceFeatures.of(legacy), contains(PlaceFeatures.highball.key));
    });

    test('전통주는 막걸리로 읽지 않는다 — 없는 집이 걸리면 안 된다', () {
      final legacy = docWith(const [], alcohol: ['전통주']);
      expect(
        PlaceFeatures.of(legacy),
        isNot(contains(PlaceFeatures.makgeolli.key)),
      );
    });

    test('♾ 하이볼 무제한과는 다른 축이다', () {
      final unlimitedOnly = {
        'name': '가게',
        'placeCategory': PlaceTaxonomy.bar.label,
        PlaceAttributeCatalog.field: {
          PlaceAttributeCatalog.unlimitedKey: ['하이볼'],
        },
      };
      // 무제한은 무제한 특징만 켠다 — '판매하는가'는 따로 물어야 한다.
      expect(
        PlaceFeatures.of(unlimitedOnly),
        contains(PlaceFeatures.unlimited.key),
      );
      expect(
        PlaceFeatures.of(unlimitedOnly),
        isNot(contains(PlaceFeatures.highball.key)),
      );
    });
  });

  group('④ 메인 ✨ 편의·서비스 / 상세검색 / 지도 필터', () {
    /// 세 화면이 함께 쓰는 목록 하나에서 칩을 집는다 — 화면마다 따로
    /// 문자열을 비교하지 않는다는 뜻이다.
    PlaceQuickPick chipFor(String featureKey) =>
        PlaceQuickPicks.amenityKinds(PlaceTaxonomy.bar.label)
            .where((p) => p.values.isNotEmpty)
            .firstWhere((p) => p.values.first == featureKey);

    test('🥃 하이볼 필터는 하이볼 파는 집만 통과시킨다', () {
      final f = EventFilter();
      chipFor(PlaceFeatures.highball.key).toggle(f);
      expect(f.features, {'하이볼'});
      expect(f.matchesDiscovery(highballOnly), isTrue);
      expect(f.matchesDiscovery(both), isTrue);
      expect(f.matchesDiscovery(makgeolliOnly), isFalse);
      expect(f.matchesDiscovery(neither), isFalse);
    });

    test('🏺 막걸리 필터는 막걸리 파는 집만 통과시킨다', () {
      final f = EventFilter();
      chipFor(PlaceFeatures.makgeolli.key).toggle(f);
      expect(f.features, {'막걸리'});
      expect(f.matchesDiscovery(makgeolliOnly), isTrue);
      expect(f.matchesDiscovery(both), isTrue);
      expect(f.matchesDiscovery(highballOnly), isFalse);
      expect(f.matchesDiscovery(neither), isFalse);
    });

    test('두 필터를 함께 켜면 둘 다 파는 집만 남는다', () {
      final f = EventFilter();
      chipFor(PlaceFeatures.highball.key).toggle(f);
      chipFor(PlaceFeatures.makgeolli.key).toggle(f);
      expect(f.matchesDiscovery(both), isTrue);
      expect(f.matchesDiscovery(highballOnly), isFalse);
      expect(f.matchesDiscovery(makgeolliOnly), isFalse);
    });

    test('상세필터에서 고를 수 있다 — 은퇴 항목이 아니다', () {
      final keys = PlaceFeatures.selectable.map((f) => f.key).toSet();
      expect(keys, containsAll(<String>['하이볼', '막걸리']));
    });

    test('빠른필터 16칸은 건드리지 않았다', () {
      expect(PlaceFeatures.all.where((f) => f.quick).length, 16);
    });
  });

  group('⑤ 카드·상세 표기', () {
    test('필터명 그대로 나온다', () {
      expect(PlaceFeatures.displayOf('하이볼'), '🥃 하이볼');
      expect(PlaceFeatures.displayOf('막걸리'), '🏺 막걸리');
    });

    test('목록 카드 요약에 실린다', () {
      expect(
        PlaceFeatures.highlightLabelsOf(both, max: 8),
        containsAll(<String>['🥃 하이볼', '🏺 막걸리']),
      );
    });

    test('상세 상단 칩에도 같은 라벨로 실린다', () {
      expect(
        PlaceFeatures.highlightLabelsOf(highballOnly, max: 8, detailed: true),
        contains('🥃 하이볼'),
      );
    });

    test('안 켠 집에는 아무것도 안 붙는다', () {
      final labels = PlaceFeatures.highlightLabelsOf(neither, max: 8);
      expect(labels, isNot(contains('🥃 하이볼')));
      expect(labels, isNot(contains('🏺 막걸리')));
    });

    test('등록 화면 선택지 표기', () {
      expect(
        PlaceAttributeCatalog.emojiFor(PlaceAttributeCatalog.highballServed),
        '🥃',
      );
      expect(
        PlaceAttributeCatalog.emojiFor(PlaceAttributeCatalog.makgeolliServed),
        '🏺',
      );
    });
  });

  group('⑥ 다른 편의·서비스는 그대로다', () {
    test('콜키지 판정은 영향을 받지 않는다', () {
      final corkageDoc = {
        'name': '가게',
        PlaceAttributeCatalog.field: {
          PlaceAttributeCatalog.corkageKey: [PlaceAttributeCatalog.corkagePaid],
          PlaceAttributeCatalog.servedDrinksKey: [
            PlaceAttributeCatalog.highballServed,
          ],
        },
      };
      final f = PlaceFeatures.of(corkageDoc);
      expect(f, contains(PlaceFeatures.corkageAvailable.key));
      expect(f, contains(PlaceFeatures.highball.key));
    });

    test('특징 키가 겹치지 않는다', () {
      final keys = PlaceFeatures.all.map((f) => f.key).toList();
      expect(keys.toSet().length, keys.length);
    });
  });
}

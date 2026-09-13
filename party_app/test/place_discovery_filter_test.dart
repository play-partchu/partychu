import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/event_filter.dart';
import 'package:party_app/models/place_attributes.dart';
import 'package:party_app/models/place_feature.dart';
import 'package:party_app/models/place_taxonomy.dart';

/// 플레이스 탐색 필터([EventFilter.matchesDiscovery])의 약속을 고정한다.
///
/// 목록·지도·상세검색이 모두 이 함수 하나를 부르므로, 여기가 맞으면 세 화면의
/// 결과가 갈릴 수 없다.
void main() {
  // 새 구조로 등록된 힙합클럽.
  Map<String, dynamic> hiphopClub() => {
    'name': '테스트 클럽',
    'placeCategory': '클럽',
    'placeSubcategories': ['힙합클럽'],
    'placeAttributes': {
      'musicGenres': ['HIPHOP', 'R&B'],
      'dj': ['DJ 있음'],
      'smoking': [PlaceAttributeCatalog.smokingRoom],
      'clubEntry': ['테이블 예약 가능'],
    },
    'placeAttributeDetails': {
      'clubEntry': {'entryFee': '20,000원', 'peakTime': '23시~02시'},
    },
  };

  // 새 필드가 하나도 없는 옛 문서.
  Map<String, dynamic> legacyPub() => {
    'name': '옛날 포차',
    'businessTypes': ['포차'],
    'themeTags': ['핫플'],
    'petPolicy': {'status': 'possible'},
  };

  group('조건이 없으면 아무도 걸러지지 않는다', () {
    test('빈 필터는 모든 문서를 통과시킨다 — 하위호환의 핵심', () {
      final f = EventFilter();
      expect(f.isActive, isFalse);
      expect(f.matchesDiscovery(hiphopClub()), isTrue);
      expect(f.matchesDiscovery(legacyPub()), isTrue);
      expect(f.matchesDiscovery(<String, dynamic>{}), isTrue);
    });
  });

  group('대분류는 OR', () {
    test('고른 대분류 중 하나면 통과', () {
      final f = EventFilter(categories: {'클럽', 'BAR'});
      expect(f.matchesDiscovery(hiphopClub()), isTrue);
      expect(f.matchesDiscovery(legacyPub()), isFalse, reason: '포차는 술집');
    });

    test('옛 문서도 유추된 대분류로 걸린다', () {
      expect(
        EventFilter(categories: {'술집'}).matchesDiscovery(legacyPub()),
        isTrue,
      );
    });

    test('대분류를 끄면 그 아래 소분류도 함께 빠진다', () {
      final f = EventFilter()
        ..toggleCategory('클럽')
        ..toggleSubcategory('힙합클럽');
      expect(f.subcategories, contains('힙합클럽'));
      f.toggleCategory('클럽');
      expect(f.categories, isEmpty);
      expect(f.subcategories, isEmpty, reason: '부모 없는 소분류는 남기지 않는다');
    });
  });

  group('소분류는 대분류 안에서 한 단계 더 좁힌다', () {
    test('클럽 → 힙합클럽', () {
      final f = EventFilter(categories: {'클럽'}, subcategories: {'힙합클럽'});
      expect(f.matchesDiscovery(hiphopClub()), isTrue);

      final edm = hiphopClub()..['placeSubcategories'] = ['EDM클럽'];
      expect(f.matchesDiscovery(edm), isFalse);
    });
  });

  group('특징은 AND — 겹칠수록 좁아진다', () {
    test('둘 다 가진 곳만 통과', () {
      final club = hiphopClub();
      expect(
        EventFilter(features: {PlaceFeatures.dj.key}).matchesDiscovery(club),
        isTrue,
      );
      expect(
        EventFilter(
          features: {PlaceFeatures.dj.key, PlaceFeatures.smokingArea.key},
        ).matchesDiscovery(club),
        isTrue,
      );
      expect(
        EventFilter(
          features: {PlaceFeatures.dj.key, PlaceFeatures.pool.key},
        ).matchesDiscovery(club),
        isFalse,
      );
    });

    test('옛 문서도 유도된 특징으로 걸린다 — 핫플 · 반려동물', () {
      final pub = legacyPub();
      expect(
        EventFilter(features: {PlaceFeatures.hot.key}).matchesDiscovery(pub),
        isTrue,
      );
      expect(
        EventFilter(features: {PlaceFeatures.pet.key}).matchesDiscovery(pub),
        isTrue,
      );
    });

    test('금연과 흡연공간은 서로 배타적이지 않다', () {
      // 별도 흡연실 = 좌석은 금연 + 흡연할 곳도 있다.
      final club = hiphopClub();
      expect(
        EventFilter(
          features: {
            PlaceFeatures.smokeFree.key,
            PlaceFeatures.smokingArea.key,
          },
        ).matchesDiscovery(club),
        isTrue,
      );
    });
  });

  group('속성은 그룹 안 OR, 그룹 사이 AND', () {
    test('한 그룹에서 여러 값을 고르면 그중 하나만 있어도 통과', () {
      final f = EventFilter(
        attributes: {
          'musicGenres': {'HIPHOP', 'Techno'},
        },
      );
      expect(f.matchesDiscovery(hiphopClub()), isTrue);
    });

    test('그룹이 둘이면 둘 다 만족해야 통과', () {
      final both = EventFilter(
        attributes: {
          'musicGenres': {'HIPHOP'},
          'clubEntry': {'테이블 예약 가능'},
        },
      );
      expect(both.matchesDiscovery(hiphopClub()), isTrue);

      final missing = EventFilter(
        attributes: {
          'musicGenres': {'HIPHOP'},
          PlaceAttributeCatalog.unlimitedKey: {'하이볼'},
        },
      );
      expect(missing.matchesDiscovery(hiphopClub()), isFalse);
    });

    test('빈 그룹은 조건으로 치지 않는다', () {
      final f = EventFilter(attributes: {'musicGenres': <String>{}});
      expect(f.isActive, isFalse);
      expect(f.matchesDiscovery(legacyPub()), isTrue);
    });

    test('하이볼 무제한처럼 값으로 바로 검색된다', () {
      final bar = {
        'placeCategory': 'BAR',
        'placeAttributes': {
          PlaceAttributeCatalog.unlimitedKey: ['하이볼', '맥주'],
        },
      };
      expect(
        EventFilter(
          attributes: {
            PlaceAttributeCatalog.unlimitedKey: {'하이볼'},
          },
        ).matchesDiscovery(bar),
        isTrue,
      );
      expect(
        EventFilter(
          attributes: {
            PlaceAttributeCatalog.unlimitedKey: {'와인'},
          },
        ).matchesDiscovery(bar),
        isFalse,
      );
    });
  });

  group('필터 상태 관리', () {
    test('isActive는 새 조건도 센다', () {
      expect(EventFilter(categories: {'클럽'}).isActive, isTrue);
      expect(EventFilter(subcategories: {'힙합클럽'}).isActive, isTrue);
      expect(EventFilter(features: {PlaceFeatures.dj.key}).isActive, isTrue);
      expect(
        EventFilter(
          attributes: {
            'musicGenres': {'HIPHOP'},
          },
        ).isActive,
        isTrue,
      );
    });

    test('메인 대분류는 단일 선택 — 새로 고르면 이전 것이 꺼진다', () {
      final f = EventFilter()
        ..selectCategory('클럽')
        ..toggleSubcategory('힙합클럽');
      expect(f.categories, {'클럽'});
      expect(f.soleCategory, '클럽');

      f.selectCategory('맛집');
      expect(f.categories, {'맛집'}, reason: '클럽은 저절로 꺼진다');
      expect(f.subcategories, isEmpty, reason: '남의 소분류는 따라오지 않는다');

      // 화면 이름으로 골라도 저장값으로 들어간다.
      f.selectCategory('음식');
      expect(f.categories, {'맛집'});

      f.selectCategory(null);
      expect(f.categories, isEmpty);
      expect(f.soleCategory, isNull);
    });

    test('상세검색에서 겹쳐 켠 상태는 그대로 남는다 — 값을 임의로 버리지 않는다', () {
      final f = EventFilter()
        ..toggleCategory('클럽')
        ..toggleCategory('BAR');
      expect(f.categories, {'클럽', 'BAR'});
      // 하나가 아니므로 메인 카테고리 영역은 소분류 층으로 내려가지 않는다.
      expect(f.soleCategory, isNull);
    });

    test('상세필터 배지는 "이 줄에 안 보이는 조건"만 센다', () {
      final f = EventFilter(
        features: {'DJ', '심야영업'},
        attributes: {
          'musicGenres': {'HIPHOP'},
        },
        regions: {'서울 강남구'},
        priceRanges: {'3~5만원'},
        categories: {'클럽'},
        subcategories: {'힙합클럽'},
        minCapacity: 20,
      )..visitDate = DateTime(2026, 9, 1);

      // 아무것도 안 보인다고 하면 특징 2 + 속성 1 + 지역 1 + 가격 1 = 5.
      // 대분류·소분류는 카테고리 영역에, 날짜·인원은 📅 👥 버튼 배지에
      // 이미 보이므로 세지 않는다(같은 말을 두 번 하지 않는다).
      expect(f.hiddenConditionCount(), 5);

      // 줄에 나와 있는 것은 빠진다.
      expect(
        f.hiddenConditionCount(
          visibleFeatures: {'DJ'},
          visibleAttributes: {
            'musicGenres': {'HIPHOP'},
          },
        ),
        3,
      );
    });

    test('copy는 깊은 복사 — 사본을 고쳐도 원본이 안 바뀐다', () {
      final original = EventFilter(
        categories: {'클럽'},
        features: {PlaceFeatures.dj.key},
        attributes: {
          'musicGenres': {'HIPHOP'},
        },
      );
      final copy = original.copy()
        ..toggleCategory('BAR')
        ..toggleFeature(PlaceFeatures.pool.key)
        ..toggleAttribute('musicGenres', 'EDM');
      expect(original.categories, {'클럽'});
      expect(original.features, {PlaceFeatures.dj.key});
      expect(original.attributeValues('musicGenres'), {'HIPHOP'});
      expect(copy.categories, {'클럽', 'BAR'});
    });

    test('clearDiscovery는 지역·날짜를 남긴다', () {
      final f = EventFilter(
        regions: {'서울 강남구'},
        categories: {'클럽'},
        features: {PlaceFeatures.dj.key},
        attributes: {
          'musicGenres': {'HIPHOP'},
        },
      )..visitDate = DateTime(2026, 9, 1);

      f.clearDiscovery();
      expect(f.categories, isEmpty);
      expect(f.features, isEmpty);
      expect(f.attributes, isEmpty);
      expect(f.regions, {'서울 강남구'}, reason: '지역은 그대로');
      expect(f.visitDate, isNotNull, reason: '날짜도 그대로');
    });

    test('속성 토글은 마지막 값을 지우면 그룹 자체를 버린다', () {
      final f = EventFilter()..toggleAttribute('musicGenres', 'HIPHOP');
      expect(f.attributes.containsKey('musicGenres'), isTrue);
      f.toggleAttribute('musicGenres', 'HIPHOP');
      expect(f.attributes.containsKey('musicGenres'), isFalse);
    });
  });

  group('선택 칩 — 만드는 쪽과 지우는 쪽이 같은 표를 본다', () {
    test('대분류 칩을 지우면 소분류도 함께 사라진다', () {
      final f = EventFilter(categories: {'클럽'}, subcategories: {'힙합클럽'});
      final chip = f.selectedEntries.firstWhere((e) => e.key == 'categories');
      expect(chip.value, PlaceTaxonomy.displayOf('클럽'));
      f.removeValue(chip.key, chip.value);
      expect(f.categories, isEmpty);
      expect(f.subcategories, isEmpty);
    });

    test('특징 칩은 표기로 저장값을 되찾아 지운다', () {
      final f = EventFilter(features: {PlaceFeatures.corkageAvailable.key});
      final chip = f.selectedEntries.firstWhere((e) => e.key == 'features');
      expect(chip.value, PlaceFeatures.corkageAvailable.display);
      f.removeValue(chip.key, chip.value);
      expect(f.features, isEmpty);
    });

    test('속성 칩은 그룹 키를 달고 다닌다', () {
      final f = EventFilter(
        attributes: {
          'musicGenres': {'HIPHOP'},
        },
      );
      final chip = f.selectedEntries.firstWhere(
        (e) => e.key.startsWith('attr:'),
      );
      expect(chip.key, 'attr:musicGenres');
      expect(chip.value, 'HIPHOP');
      f.removeValue(chip.key, chip.value);
      expect(f.attributes, isEmpty);
    });
  });
}

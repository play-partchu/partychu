import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/place_attributes.dart';
import 'package:party_app/models/place_feature.dart';
import 'package:party_app/models/place_taxonomy.dart';

/// 플레이스 개편의 **하위호환**을 고정하는 테스트.
///
/// 여기서 지키는 약속은 하나다 — 새 필드가 하나도 없는 옛 플레이스 문서도
/// 새 카테고리 바와 빠른 필터에서 제자리에 나타나야 한다. 그게 깨지면 이미
/// 등록된 가게들이 지도에서 통째로 사라진다.
void main() {
  // 새 구조를 하나도 모르는, 실제로 등록돼 있을 법한 옛 문서.
  Map<String, dynamic> legacyDoc() => {
    'name': '옛날 포차',
    'isActive': true,
    'businessTypes': ['포차'],
    'themeTags': ['핫플', '이벤트'],
    'eventSubtype': '생일파티 이벤트',
    'priceRange': '1~3만원',
    'partychuPerk': '파티츄 보고 왔다고 하면 사이다 서비스',
    'petPolicy': {'status': 'possible'},
    'facilityOptions': {
      'seatingTypes': {
        'selected': ['개별룸', '단체석'],
      },
      'outsideFood': {
        'selected': ['외부 음식 반입 가능'],
      },
    },
  };

  group('대분류 — 옛 업종에서 유추한다', () {
    test('포차는 술집으로, 소분류까지 살린다', () {
      final data = legacyDoc();
      expect(PlaceTaxonomy.categoryOf(data), '술집');
      expect(PlaceTaxonomy.subcategoriesOf(data), contains('포차'));
    });

    test('업종별 유추 표', () {
      String? of(List<String> types) =>
          PlaceTaxonomy.categoryOf({'businessTypes': types});
      expect(of(['클럽']), '클럽');
      expect(of(['바']), 'BAR');
      expect(of(['라운지']), 'BAR');
      expect(of(['술집']), '술집');
      expect(of(['카페']), '카페·디저트');
      // '기타'는 어느 대분류인지 알 수 없으므로 유추하지 않는다.
      expect(of(['기타']), isNull);
    });

    test('업종이 여럿이면 좁은 쪽이 이긴다 — 클럽 > 술집', () {
      expect(
        PlaceTaxonomy.categoryOf({
          'businessTypes': ['술집', '클럽'],
        }),
        '클럽',
      );
    });

    test('옛 단일 businessType도 읽는다', () {
      expect(PlaceTaxonomy.categoryOf({'businessType': '카페'}), '카페·디저트');
    });

    test('호스트가 고른 값이 유추보다 우선한다', () {
      expect(
        PlaceTaxonomy.categoryOf({
          'businessTypes': ['카페'],
          'placeCategory': '클럽',
        }),
        '클럽',
      );
    });

    test('알 수 없는 대분류 값은 무시하고 유추로 떨어진다', () {
      expect(
        PlaceTaxonomy.categoryOf({
          'businessTypes': ['카페'],
          'placeCategory': '없는대분류',
        }),
        '카페·디저트',
      );
    });

    test('아무 정보도 없으면 미분류 — 전체에서는 그대로 보인다', () {
      final blank = <String, dynamic>{'name': '정보 없는 가게'};
      expect(PlaceTaxonomy.categoryOf(blank), isNull);
      // 대분류 조건이 없으면(=전체) 통과한다. 목록·지도에서 사라지지 않는다.
      expect(PlaceTaxonomy.matchesAnyCategory(blank, {}), isTrue);
      // 특정 대분류를 켰을 때만 빠진다.
      expect(PlaceTaxonomy.matchesAnyCategory(blank, {'클럽'}), isFalse);
    });

    test("'맛집'은 저장값 그대로고 화면에서만 '음식'으로 부른다", () {
      // 저장값을 바꾸면 이미 placeCategory: '맛집'으로 등록된 문서가 통째로
      // 사라진다 — 그래서 바꾸는 것은 이름뿐이다.
      expect(PlaceTaxonomy.restaurant.label, '맛집');
      expect(PlaceTaxonomy.restaurant.displayName, '푸드');
      expect(PlaceTaxonomy.displayOf('맛집'), '🍽 푸드');

      final doc = {'placeCategory': '맛집'};
      expect(PlaceTaxonomy.categoryOf(doc), '맛집');
      expect(PlaceTaxonomy.matchesAnyCategory(doc, {'맛집'}), isTrue);

      // 화면 이름이 값으로 새어 들어와도 같은 대분류로 풀린다.
      expect(PlaceTaxonomy.byLabel('푸드'), PlaceTaxonomy.restaurant);
      expect(PlaceTaxonomy.canonical('푸드'), '맛집');
      // 예전 화면 이름('음식')으로 저장된 조건도 그대로 풀린다.
      expect(PlaceTaxonomy.canonical('음식'), '맛집');
    });

    test('혼술바는 독립 대분류이고, 옛 특징 태그로 등록된 가게도 함께 걸린다', () {
      expect(PlaceTaxonomy.byLabel('혼술바'), isNotNull);
      expect(PlaceTaxonomy.bar.subcategories, isNot(contains('혼술바')));

      // 새로 등록한 문서 — 대분류를 직접 골랐다.
      final picked = {'placeCategory': '혼술바'};
      expect(PlaceTaxonomy.matchesAnyCategory(picked, {'혼술바'}), isTrue);

      // 옛 문서 — 대분류는 없고 특징 태그로만 '혼술바'다. 그래도 걸린다.
      final legacy = {
        'businessTypes': ['바'],
        'themeTags': ['혼술바'],
      };
      expect(PlaceTaxonomy.matchesAnyCategory(legacy, {'혼술바'}), isTrue);
      // ⚠️ 그러면서 원래 걸리던 BAR에서도 빠지지 않는다 — 한쪽으로 옮기면
      //    지금 BAR로 보고 있던 사람에게서 그 가게가 사라진다.
      expect(PlaceTaxonomy.categoryOf(legacy), 'BAR');
      expect(PlaceTaxonomy.matchesAnyCategory(legacy, {'BAR'}), isTrue);

      // 옛 단일 'category' 필드로만 태그가 있던 문서도 같은 규칙이다.
      expect(
        PlaceTaxonomy.matchesAnyCategory({'category': '혼술바'}, {'혼술바'}),
        isTrue,
      );
      // 태그가 없는 가게까지 딸려오지는 않는다.
      expect(
        PlaceTaxonomy.matchesAnyCategory({'placeCategory': 'BAR'}, {'혼술바'}),
        isFalse,
      );
    });

    test('클럽은 독립 대분류다 — 술집·BAR 아래에 없다', () {
      expect(PlaceTaxonomy.byLabel('클럽'), isNotNull);
      expect(PlaceTaxonomy.pub.allSubcategories, isNot(contains('힙합클럽')));
      expect(PlaceTaxonomy.bar.allSubcategories, isNot(contains('힙합클럽')));
    });

    test('클럽 장르는 musicGenres 하나가 정본 — 장르 소분류는 은퇴했다', () {
      // 장르를 뜻하는 소분류는 새로 고를 수 없다(같은 말을 두 곳에 저장하지
      // 않는다). 되살아난 넷은 장르가 아니라 **업장 형태**라 그 축과 겹치지
      // 않는다 — 그래서 여기서 확인하는 것은 "장르가 소분류로 돌아오지
      // 않았는가"다.
      for (final genreLike in ['힙합클럽', 'EDM클럽', '테크노']) {
        expect(
          PlaceTaxonomy.club.subcategories,
          isNot(contains(genreLike)),
          reason: '$genreLike은 장르(musicGenres)로만 저장해야 한다',
        );
      }
      expect(PlaceTaxonomy.club.retiredSubcategories, contains('힙합클럽'));
      // 은퇴한 값도 이 대분류의 것으로는 계속 인정된다(대분류를 끄면 함께 빠진다).
      expect(PlaceTaxonomy.hasSubcategory('클럽', '힙합클럽'), isTrue);

      // 옛 값으로 등록된 문서는 새 장르 필터에 다리로 걸린다.
      final legacy = {
        'placeCategory': '클럽',
        'placeSubcategories': ['힙합클럽'],
      };
      expect(PlaceTaxonomy.legacyClubGenresOf(legacy), contains('HIPHOP'));
      // 장르로 옮길 수 없는 값은 억지로 대응시키지 않는다.
      expect(
        PlaceTaxonomy.legacyClubGenresOf({
          'placeSubcategories': ['라운지클럽'],
        }),
        isEmpty,
      );
    });

    test('소분류 필터는 OR, 비어 있으면 조건 없음', () {
      final data = {
        'placeSubcategories': ['힙합클럽'],
      };
      expect(PlaceTaxonomy.matchesAnySubcategory(data, {}), isTrue);
      expect(
        PlaceTaxonomy.matchesAnySubcategory(data, {'힙합클럽', 'EDM클럽'}),
        isTrue,
      );
      expect(PlaceTaxonomy.matchesAnySubcategory(data, {'EDM클럽'}), isFalse);
    });
  });

  group('특징 — 옛 문서에서도 그대로 켜진다', () {
    test('옛 문서 하나에서 유도되는 특징들', () {
      final f = PlaceFeatures.of(legacyDoc());
      expect(f, contains(PlaceFeatures.hot.key), reason: 'themeTags 핫플');
      expect(f, contains(PlaceFeatures.eventNow.key), reason: 'themeTags 이벤트');
      expect(f, contains(PlaceFeatures.birthday.key), reason: 'eventSubtype');
      expect(f, contains(PlaceFeatures.pet.key), reason: 'petPolicy');
      expect(
        f,
        contains(PlaceFeatures.private.key),
        reason: 'facilityOptions 개별룸',
      );
      expect(
        f,
        contains(PlaceFeatures.groupSeat.key),
        reason: 'facilityOptions 단체석',
      );
      expect(f, contains(PlaceFeatures.outsideFood.key));
      expect(f, contains(PlaceFeatures.partychuPerk.key));
    });

    test('옛 단일 category 필드도 특징 태그로 읽는다', () {
      expect(
        PlaceFeatures.of({'category': '핫플'}),
        contains(PlaceFeatures.hot.key),
      );
    });

    test('빈 문서는 특징이 없고, 터지지 않는다', () {
      expect(PlaceFeatures.of(<String, dynamic>{}), isEmpty);
    });

    test('반려동물 불가는 켜지지 않는다', () {
      expect(
        PlaceFeatures.of({
          'petPolicy': {'status': 'notAllowed'},
        }),
        isNot(contains(PlaceFeatures.pet.key)),
      );
    });
  });

  group('특징 — 새 속성에서 유도된다', () {
    Map<String, dynamic> withAttrs(Map<String, List<String>> attrs) => {
      'placeAttributes': attrs,
    };

    test('무제한 · 콜키지 가능 · 대형스크린 · 놀거리', () {
      expect(
        PlaceFeatures.of(
          withAttrs({
            'unlimited': ['하이볼'],
          }),
        ),
        contains(PlaceFeatures.unlimited.key),
      );
      expect(
        PlaceFeatures.of(
          withAttrs({
            'corkage': ['콜키지 프리'],
          }),
        ),
        contains(PlaceFeatures.corkageAvailable.key),
      );
      // 필터가 묻는 것은 '무료인가'가 아니라 '허용하는가'다 — 유료도 켜진다.
      // (무료/유료 구분은 카드 배지가 맡는다: PlaceCorkage.cardBadge)
      expect(
        PlaceFeatures.of(
          withAttrs({
            'corkage': ['콜키지 유료'],
          }),
        ),
        contains(PlaceFeatures.corkageAvailable.key),
      );
      // 무료인지 유료인지 밝히지 않은 '콜키지 가능'도 허용이므로 켜진다.
      expect(
        PlaceFeatures.of(
          withAttrs({
            'corkage': ['콜키지 가능'],
          }),
        ),
        contains(PlaceFeatures.corkageAvailable.key),
      );
      // 불가만 막힌다.
      expect(
        PlaceFeatures.of(
          withAttrs({
            'corkage': ['콜키지 불가'],
          }),
        ),
        isNot(contains(PlaceFeatures.corkageAvailable.key)),
      );
      expect(
        PlaceFeatures.of(
          withAttrs({
            'screen': ['대형스크린 있음'],
          }),
        ),
        contains(PlaceFeatures.bigScreen.key),
      );
      expect(
        PlaceFeatures.of(
          withAttrs({
            'playItems': ['보드게임'],
          }),
        ),
        contains(PlaceFeatures.play.key),
      );
    });

    test('주차와 발렛은 각각 켜진다', () {
      final f = PlaceFeatures.of(
        withAttrs({
          'parking': ['발렛 가능'],
        }),
      );
      expect(f, contains(PlaceFeatures.parking.key));
      expect(f, contains(PlaceFeatures.valet.key));

      final onlyParking = PlaceFeatures.of(
        withAttrs({
          'parking': ['주차 가능'],
        }),
      );
      expect(onlyParking, contains(PlaceFeatures.parking.key));
      expect(onlyParking, isNot(contains(PlaceFeatures.valet.key)));
    });

    test('생일 혜택을 고르면 생일혜택 필터에 걸린다', () {
      expect(
        PlaceFeatures.of(
          withAttrs({
            'birthdayPerks': ['케이크'],
          }),
        ),
        contains(PlaceFeatures.birthday.key),
      );
    });

    test('놀거리 대분류는 놀거리 항목을 안 골라도 놀거리로 걸린다', () {
      expect(
        PlaceFeatures.of({'placeCategory': '놀거리'}),
        contains(PlaceFeatures.play.key),
      );
    });

    test('라이브·공연 대분류는 라이브로 걸린다', () {
      expect(
        PlaceFeatures.of({'placeCategory': '라이브·공연'}),
        contains(PlaceFeatures.live.key),
      );
    });
  });

  group('흡연 정책 — 실내 금연 + 흡연공간 조합을 표현한다', () {
    Set<String> featuresFor(String policy) => PlaceFeatures.of({
      'placeAttributes': {
        'smoking': [policy],
      },
    });

    test('전 구역 금연 — 금연만', () {
      final f = featuresFor(PlaceAttributeCatalog.smokeFreeAll);
      expect(f, contains(PlaceFeatures.smokeFree.key));
      expect(f, isNot(contains(PlaceFeatures.smokingArea.key)));
    });

    test('실내 금연 / 야외 흡연 가능 — 둘 다', () {
      final f = featuresFor(PlaceAttributeCatalog.smokeFreeIndoor);
      expect(f, contains(PlaceFeatures.smokeFree.key));
      expect(f, contains(PlaceFeatures.smokingArea.key));
    });

    test('별도 흡연실 · 흡연구역 — 좌석은 금연이고 흡연공간도 있다', () {
      for (final policy in [
        PlaceAttributeCatalog.smokingRoom,
        PlaceAttributeCatalog.smokingArea,
      ]) {
        final f = featuresFor(policy);
        expect(f, contains(PlaceFeatures.smokeFree.key), reason: policy);
        expect(f, contains(PlaceFeatures.smokingArea.key), reason: policy);
      }
    });

    test('흡연 가능 매장 — 흡연공간만, 금연은 아니다', () {
      final f = featuresFor(PlaceAttributeCatalog.smokingAllowed);
      expect(f, isNot(contains(PlaceFeatures.smokeFree.key)));
      expect(f, contains(PlaceFeatures.smokingArea.key));
    });

    test('흡연 정책을 안 적은 문서는 어느 쪽에도 안 걸린다', () {
      final f = PlaceFeatures.of(<String, dynamic>{});
      expect(f, isNot(contains(PlaceFeatures.smokeFree.key)));
      expect(f, isNot(contains(PlaceFeatures.smokingArea.key)));
    });
  });

  group('영업시간 — 심야·24시간은 이미 저장된 값에서 읽는다', () {
    Map<String, dynamic> hours(Map<String, dynamic> monday) => {
      'placeWeeklyHours': {'월': monday},
    };

    test('자정을 넘겨 닫으면 심야영업', () {
      final f = PlaceFeatures.of(
        hours({'open': '18:00', 'close': '03:00', 'isClosed': false}),
      );
      expect(f, contains(PlaceFeatures.lateNight.key));
    });

    test('밤 10시에 닫으면 심야영업이 아니다', () {
      final f = PlaceFeatures.of(
        hours({'open': '11:00', 'close': '22:00', 'isClosed': false}),
      );
      expect(f, isNot(contains(PlaceFeatures.lateNight.key)));
    });

    test('요일 24시간은 24시간 + 심야 둘 다', () {
      final f = PlaceFeatures.of(
        hours({'open': '00:00', 'close': '00:00', 'is24Hours': true}),
      );
      expect(f, contains(PlaceFeatures.open24.key));
      expect(f, contains(PlaceFeatures.lateNight.key));
    });

    test('문서 전체 24시간 플래그도 읽는다', () {
      final f = PlaceFeatures.of({'isOpen24Hours': true});
      expect(f, contains(PlaceFeatures.open24.key));
      expect(f, contains(PlaceFeatures.lateNight.key));
    });

    test('휴무일은 심야 판정에서 빠진다', () {
      final f = PlaceFeatures.of(
        hours({'open': '18:00', 'close': '03:00', 'isClosed': true}),
      );
      expect(f, isNot(contains(PlaceFeatures.lateNight.key)));
    });
  });

  group('필터 판정', () {
    test('여러 특징을 켜면 AND — 겹칠수록 좁아진다', () {
      final data = legacyDoc();
      expect(PlaceFeatures.matchesAll(data, {}), isTrue, reason: '조건 없음');
      expect(
        PlaceFeatures.matchesAll(data, {
          PlaceFeatures.hot.key,
          PlaceFeatures.pet.key,
        }),
        isTrue,
      );
      expect(
        PlaceFeatures.matchesAll(data, {
          PlaceFeatures.hot.key,
          PlaceFeatures.pool.key,
        }),
        isFalse,
      );
    });

    test('카드 하이라이트는 고른 필터를 앞으로 당긴다', () {
      final data = legacyDoc();
      final highlights = PlaceFeatures.highlightsOf(
        data,
        prefer: {PlaceFeatures.pet.key},
        max: 2,
      );
      expect(highlights.first.key, PlaceFeatures.pet.key);
      expect(highlights.length, 2);
    });
  });

  group('속성 값 객체', () {
    test('저장 → 복원 왕복', () {
      var a = PlaceAttributes.empty()
          .toggle('musicGenres', 'HIPHOP')
          .toggle('musicGenres', 'R&B')
          .toggle(PlaceAttributeCatalog.screenKey, '대형스크린 있음')
          .withDetail(PlaceAttributeCatalog.screenKey, 'size', '150인치');

      final restored = PlaceAttributes.fromMap(a.toMap(), a.detailsToMap());
      expect(restored.selected('musicGenres'), {'HIPHOP', 'R&B'});
      expect(
        restored.detailText(PlaceAttributeCatalog.screenKey, 'size'),
        '150인치',
      );
    });

    test('단일 선택 그룹은 새로 고르면 이전 값을 대체한다', () {
      final a = PlaceAttributes.empty()
          .toggle(PlaceAttributeCatalog.corkageKey, '콜키지 불가')
          .toggle(
            PlaceAttributeCatalog.corkageKey,
            PlaceAttributeCatalog.corkageFree,
          );
      expect(a.selected(PlaceAttributeCatalog.corkageKey), {
        PlaceAttributeCatalog.corkageFree,
      });
    });

    test('상세 입력란이 닫히면 그 값도 버린다', () {
      var a = PlaceAttributes.empty()
          .toggle(PlaceAttributeCatalog.firepitKey, '불멍 가능')
          .withDetail(PlaceAttributeCatalog.firepitKey, 'fee', '20,000원');
      expect(a.detailText(PlaceAttributeCatalog.firepitKey, 'fee'), '20,000원');

      // 불멍을 끄면 비용도 함께 사라져야 한다 — 남으면 다음에 켰을 때 예전
      // 값이 되살아난다.
      a = a.toggle(PlaceAttributeCatalog.firepitKey, '불멍 가능');
      expect(a.detailText(PlaceAttributeCatalog.firepitKey, 'fee'), '');
    });

    test('빈 값은 상세로 저장하지 않는다', () {
      final a = PlaceAttributes.empty()
          .toggle(PlaceAttributeCatalog.firepitKey, '불멍 가능')
          .withDetail(PlaceAttributeCatalog.firepitKey, 'fee', '   ');
      expect(a.detailsToMap(), isEmpty);
    });

    test('옛 문서가 단일 선택을 문자열로 적었어도 읽는다', () {
      final a = PlaceAttributes.fromMap({'corkage': '콜키지 프리'});
      expect(a.single('corkage'), '콜키지 프리');
    });

    test('카탈로그에 없는 그룹도 보존한다 — 옛 앱이 새 값을 지우지 않게', () {
      final a = PlaceAttributes.fromMap({
        '미래에추가될그룹': ['값'],
      });
      expect(a.toMap()['미래에추가될그룹'], ['값']);
    });

    test('대분류를 바꾸면 그 대분류에서 안 묻는 값은 털어낸다', () {
      final club = PlaceAttributes.empty()
          .toggle('musicGenres', 'HIPHOP')
          .toggle(PlaceAttributeCatalog.purposesKey, '데이트');
      // 카페로 바꾸면 음악 장르는 화면에서 사라지므로 값도 지운다.
      final cafe = pruneAttributesFor(club, '카페·디저트');
      expect(cafe.selected('musicGenres'), isEmpty);
      // 공통 그룹은 그대로 남는다.
      expect(cafe.selected(PlaceAttributeCatalog.purposesKey), {'데이트'});
    });
  });

  group('카탈로그 무결성', () {
    test('대분류마다 상세화면 블록 순서가 정의돼 있다', () {
      expect(PlaceDetailBlocks.coversAllCategories, isTrue);
    });

    test('대분류 전용 그룹은 그 대분류에서만 물어본다', () {
      final cafeGroups = PlaceAttributeCatalog.groupsFor(
        '카페·디저트',
      ).map((g) => g.key);
      expect(cafeGroups, isNot(contains('musicGenres')));
      expect(cafeGroups, isNot(contains('clubEntry')));

      final clubGroups = PlaceAttributeCatalog.groupsFor(
        '클럽',
      ).map((g) => g.key);
      expect(clubGroups, contains('musicGenres'));
      expect(clubGroups, contains('clubEntry'));
    });

    test('대분류를 모르는 옛 문서는 공통 그룹만 본다', () {
      final groups = PlaceAttributeCatalog.groupsFor(null).map((g) => g.key);
      expect(groups, isNot(contains('musicGenres')));
      expect(groups, contains(PlaceAttributeCatalog.smokingKey));
    });

    test('그룹 키가 겹치지 않는다', () {
      final keys = PlaceAttributeCatalog.all.map((g) => g.key).toList();
      expect(keys.toSet().length, keys.length);
    });

    test('특징 키가 겹치지 않는다', () {
      final keys = PlaceFeatures.all.map((f) => f.key).toList();
      expect(keys.toSet().length, keys.length);
    });

    test('빠른 필터는 16칸 — 첫 화면에 다 깔지 않는다', () {
      expect(PlaceFeatures.quick.length, 16);
      expect(PlaceFeatures.extra, isNotEmpty);
    });

    test('상세화면 블록은 카탈로그의 모든 그룹을 결국 보여준다', () {
      for (final category in PlaceTaxonomy.all) {
        final ordered = PlaceDetailBlocks.orderedFor(category.label);
        expect(
          ordered.length,
          PlaceAttributeCatalog.all.length,
          reason: category.label,
        );
        expect(ordered.toSet().length, ordered.length, reason: '중복 없음');
      }
    });
  });
}

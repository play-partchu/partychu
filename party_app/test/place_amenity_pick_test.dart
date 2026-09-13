import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/event_filter.dart';
import 'package:party_app/models/place_feature.dart';
import 'package:party_app/models/place_quick_picks.dart';
import 'package:party_app/models/place_taxonomy.dart';

/// '✨ 편의·서비스' 칩의 약속을 고정한다.
///
/// 특징 칩을 줄에서 시트로 옮긴 것은 **표현 방식**만 바꾼 것이라, 켜는 값도
/// ([EventFilter.features]) 판정도([PlaceFeatures.matchesAll] — 특징끼리 AND)
/// 예전 그대로여야 한다.
void main() {
  PlaceQuickPick amenityOf(String label) => PlaceQuickPicks.forCategory(
    label,
  ).firstWhere((p) => p.display == '✨ 편의·서비스');

  // 🎉 With파티 칩은 특징이 아니라 값이 비어 있다 — 먼저 걸러야 .first가
  // 터지지 않는다.
  /// 시트 안에서 **특징 축 칩만** 골라낸다 — 같은 시트에 🎉 With파티(다른 축,
  /// 값이 비어 있다)와 ♾ 무제한 묶음(속성 축, 값이 속성 라벨이다)도 함께
  /// 담기므로, 특징을 셀 때는 축으로 걸러야 한다.
  Iterable<PlaceQuickPick> featureOptions(PlaceQuickPick sheet) =>
      sheet.options.where((o) => o.axis == PlacePickAxis.feature);

  PlaceQuickPick option(PlaceQuickPick sheet, PlaceFeature f) =>
      featureOptions(sheet).firstWhere((o) => o.values.first == f.key);

  group('줄에는 개별 특징 칩이 남지 않는다', () {
    test('푸드 줄은 업종·편의·서비스 두 칸뿐이다', () {
      final row = PlaceQuickPicks.forCategory(PlaceTaxonomy.restaurant.label);
      // ♾ 무제한은 줄에서 자기 칩을 잃고 ✨ 편의·서비스 시트 맨 아래 묶음으로
      // 들어갔다 — 같은 갈래를 켜는 자리가 둘이 되지 않게 하기 위함이다.
      expect(row.map((p) => p.display), ['🍽 업종', '✨ 편의·서비스']);
    });

    test('어떤 대분류에서도 맨 특징 칩이 줄에 남아 있지 않다', () {
      for (final c in PlaceTaxonomy.all) {
        final bare = PlaceQuickPicks.forCategory(
          c.label,
        ).where((p) => p.axis == PlacePickAxis.feature).map((p) => p.display);
        expect(bare, isEmpty, reason: '${c.label}: $bare');
      }
      // '전체'와 🎉 이벤트 줄도 마찬가지다.
      expect(
        PlaceQuickPicks.forCategory(
          null,
        ).where((p) => p.axis == PlacePickAxis.feature),
        isEmpty,
      );
      expect(
        PlaceQuickPicks.forCategory(
          null,
          event: true,
        ).where((p) => p.axis == PlacePickAxis.feature),
        isEmpty,
      );
    });

    test('시트로 묶을 수 없는 축(주종·장르·놀거리·입장)은 줄에 그대로 남는다', () {
      final bar = PlaceQuickPicks.forCategory(
        PlaceTaxonomy.bar.label,
      ).map((p) => p.display);
      expect(bar, containsAll(['🥃 와인', '🥃 위스키']));
      // '지금 영업중'은 편의·서비스가 아니라 지금 상태라 줄에 남는다.
      expect(
        PlaceQuickPicks.forCategory(null, event: true).map((p) => p.display),
        contains('🟢 지금 영업중'),
      );
    });
  });

  group('시트 안 선택지', () {
    test('구워줘요·콜키지 가능·프라이빗이 푸드 추천 맨 앞쪽에 있다', () {
      final sheet = amenityOf(PlaceTaxonomy.restaurant.label);
      final head = sheet.recommendedOptions.map((o) => o.display).toList();
      // 🎉 With파티가 추천 묶음 맨 앞이고(업종을 가리지 않는 조건이라),
      // 그 뒤로 푸드 추천 특징이 예전 순서 그대로 따라온다.
      expect(head.take(5), [
        '🎉 With파티',
        '🔥 구워줘요',
        '🍽️ 조리되어 나와요',
        '🍶 콜키지 가능',
        '👥 단체석',
      ]);
    });

    test('추천 뒤로 나머지 특징이 전부 따라온다 — 끌 수 없는 조건이 생기지 않는다', () {
      for (final c in PlaceTaxonomy.all) {
        final sheet = amenityOf(c.label);
        final keys = featureOptions(sheet).map((o) => o.values.first).toList();
        expect(
          keys.toSet().length,
          keys.length,
          reason: '${c.label}: 같은 특징이 두 칸에 나오면 안 된다',
        );
        // 정본은 [PlaceFeatures.selectable] 하나다 — 은퇴한 값(24시간)은
        // 여기서 이미 빠져 있고, 아래 일곱은 이 시트에 일부러 안 넣는다
        // (place_amenity_host_parity_test.dart의 같은 목록과 짝이다):
        //   · 무제한 — 시트 맨 아래 '♾ 무제한' 묶음이 세부종류째 맡는다.
        //   · 이벤트중 — 카테고리 영역의 '🎉 이벤트'가 맡는 다른 축이다.
        //   · 놀거리·심야영업·케이크반입·배달음식·BBQ — 목록이 길어 뺐다.
        //     지도 상세필터·상세검색에는 그대로 있으므로 끌 자리는 남아 있다.
        const excluded = {'무제한', '이벤트중', '놀거리', '심야영업', '케이크반입', '배달음식', 'BBQ'};
        final expected = PlaceFeatures.selectable
            .map((f) => f.key)
            .where((k) => !excluded.contains(k))
            .toSet();
        expect(keys.toSet(), expected, reason: c.label);
      }
    });

    test("무제한은 '특징' 칩으로는 시트에 없다 — 맨 아래 자기 묶음이 맡는다", () {
      final sheet = amenityOf(PlaceTaxonomy.pub.label);
      expect(
        featureOptions(sheet).map((o) => o.values.first),
        isNot(contains(PlaceFeatures.unlimited.key)),
      );
    });

    test('옵션이 켜는 값은 예전 그대로 특징 키다', () {
      final sheet = amenityOf(PlaceTaxonomy.restaurant.label);
      expect(option(sheet, PlaceFeatures.grill).values, ['구워줌']);
      expect(option(sheet, PlaceFeatures.corkageAvailable).values, ['콜키지프리']);
      expect(option(sheet, PlaceFeatures.private).values, ['프라이빗']);
    });
  });

  group('무제한과 같은 UX', () {
    test('누르면 켜는 것이 아니라 시트를 연다', () {
      expect(amenityOf(PlaceTaxonomy.restaurant.label).opensSheet, isTrue);
      expect(
        amenityOf(PlaceTaxonomy.restaurant.label).sheetTitle,
        '어떤 편의·서비스가 필요하세요?',
      );
    });

    test('여러 개 고를 수 있고, 칩이 고른 개수를 스스로 말한다', () {
      final f = EventFilter(categories: {'맛집'});
      final sheet = amenityOf(PlaceTaxonomy.restaurant.label);
      expect(sheet.displayFor(f), '✨ 편의·서비스');
      expect(sheet.isOn(f), isFalse);

      option(sheet, PlaceFeatures.grill).toggle(f);
      // 하나만 골랐으면 그 이름을 그대로 — 특징은 자기 이모지를 갖고 있어서
      // 시트 이모지를 앞에 또 붙이지 않는다.
      expect(sheet.displayFor(f), '🔥 구워줘요');
      expect(sheet.isOn(f), isTrue, reason: '고른 게 있으면 상위 칩이 선택 상태다');

      option(sheet, PlaceFeatures.corkageAvailable).toggle(f);
      option(sheet, PlaceFeatures.private).toggle(f);
      expect(sheet.displayFor(f), '✨ 편의·서비스 3');
    });

    test('다시 열어도 고른 값이 그대로다 — 상태는 필터가 들고 있다', () {
      final f = EventFilter(categories: {'맛집'}, features: {'콜키지프리'});
      // 화면을 다시 그리며 칩을 새로 만들어도 켜진 채로 읽힌다.
      final reopened = amenityOf(PlaceTaxonomy.restaurant.label);
      expect(option(reopened, PlaceFeatures.corkageAvailable).isOn(f), isTrue);
      expect(reopened.displayFor(f), '🍶 콜키지 가능');
    });

    test('전체 해제 — 시트의 초기화가 이 칩이 켠 것만 전부 끈다', () {
      final f = EventFilter(
        categories: {'맛집'},
        features: {'구워줌', '콜키지프리', '프라이빗'},
      );
      amenityOf(PlaceTaxonomy.restaurant.label).clear(f);
      expect(f.features, isEmpty);
    });

    test('다른 업종 시트에서도 같은 값을 끌 수 있다', () {
      // 푸드에서 켠 '구워줌'을 카페 화면에서도 끌 수 있어야 한다 —
      // "안 보이는데 걸려 있는" 조건을 만들지 않는다.
      final f = EventFilter(categories: {'카페·디저트'}, features: {'구워줌'});
      final cafeSheet = amenityOf(PlaceTaxonomy.cafe.label);
      expect(cafeSheet.isOn(f), isTrue);
      cafeSheet.clear(f);
      expect(f.features, isEmpty);
    });
  });

  group('판정 — 특징은 예전 그대로 AND다', () {
    Map<String, dynamic> place(List<String> features) => {
      'name': '테스트 가게',
      'placeCategory': '맛집',
      PlaceFeatures.field: features,
    };

    test('두 개를 고르면 둘 다 갖춘 곳만 남는다', () {
      final f = EventFilter(categories: {'맛집'});
      final sheet = amenityOf(PlaceTaxonomy.restaurant.label);
      option(sheet, PlaceFeatures.grill).toggle(f);
      option(sheet, PlaceFeatures.private).toggle(f);

      expect(f.matchesDiscovery(place(['구워줌', '프라이빗'])), isTrue);
      expect(f.matchesDiscovery(place(['구워줌'])), isFalse, reason: 'OR이 아니다');
      expect(f.matchesDiscovery(place(['프라이빗'])), isFalse);
    });

    test('안내 문구가 AND라고 말한다 — 무제한(OR)과 반대라 베끼면 안 된다', () {
      expect(
        amenityOf(PlaceTaxonomy.restaurant.label).sheetHint,
        contains('모두 갖춘'),
      );
    });
  });

  group('＋ 조건 배지', () {
    test('시트가 든 특징은 배지가 다시 세지 않는다', () {
      final visible = PlaceQuickPicks.visibleFeatures(
        PlaceTaxonomy.restaurant.label,
      );
      expect(visible, contains('구워줌'));
      expect(visible, contains('콜키지프리'));

      final f = EventFilter(categories: {'맛집'}, features: {'구워줌', '콜키지프리'});
      expect(
        f.hiddenConditionCount(
          visibleFeatures: visible,
          visibleAttributes: PlaceQuickPicks.visibleAttributes(
            PlaceTaxonomy.restaurant.label,
          ),
        ),
        0,
        reason: '칩이 이름으로 이미 말하고 있다',
      );
    });
  });
}

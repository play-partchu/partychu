import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/capacity_filter.dart';
import 'package:party_app/models/event_filter.dart';
import 'package:party_app/models/host_offering.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/models/place_attributes.dart';
import 'package:party_app/models/place_event_taxonomy.dart';
import 'package:party_app/models/place_feature.dart';
import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/models/place_taxonomy.dart';
import 'package:party_app/widgets/place_form/place_attributes_section.dart';
import 'package:party_app/widgets/place_form/place_category_section.dart';

/// 플레이스 개편 **출시 전 마감** 항목을 고정한다.
///
///  1. 인원은 기존 CapacityFilter 그대로, 표시만 구간으로
///  2. '알바생 훈남훈녀'는 새로 고를 수 없되 저장된 값은 살아 있다
///  3. 업종별로 필요한 세부정보만 등록 화면에 나온다
///  4. 클럽 등록 흐름이 실제로 이어진다
///  5. 새 필드가 없는 옛 문서가 기본 화면에서 사라지지 않는다
void main() {
  group('1. 인원 — 데이터·판정은 그대로, 표시만 구간', () {
    test('구간은 다섯 개이고 각각 그 구간의 최대 인원을 든다', () {
      expect(CapacityFilter.presets.map((p) => p.label).toList(), [
        '4명 이하',
        '5~10명',
        '11~20명',
        '21~50명',
        '50명+',
      ]);
      expect(CapacityFilter.presets.map((p) => p.people).toList(), [
        4,
        10,
        20,
        50,
        51,
      ]);
    });

    test('구간은 고르는 자리에서만 보이고, 고른 값은 언제나 숫자로 적힌다', () {
      // 구간 이름은 인원 선택 시트의 지름길 버튼에만 쓴다.
      expect(CapacityFilter.presetLabel(4), '4명 이하');
      expect(CapacityFilter.presetLabel(20), '11~20명');
      expect(CapacityFilter.presetLabel(51), '50명+');
      expect(CapacityFilter.presetLabel(7), isNull, reason: '직접 적은 값은 구간이 아니다');

      // 칩·버튼 표기는 예전 계약 그대로 — 20에만 구간 이름이 붙으면
      // "20명 이상"이라는 다른 뜻으로 읽히기 때문이다
      // (test/capacity_filter_test.dart가 같은 것을 고정한다).
      expect(CapacityFilter.label(4), '4명');
      expect(CapacityFilter.label(20), '20명');
      expect(CapacityFilter.label(7), '7명');
      expect(CapacityFilter.label(200), '200명');
    });

    test('판정은 한 글자도 바뀌지 않았다 — 여전히 수용 인원 >= 고른 인원', () {
      final hall = {'capacityMax': 30};
      expect(CapacityFilter.matches(hall, 20), isTrue, reason: '11~20명 구간');
      expect(CapacityFilter.matches(hall, 50), isFalse, reason: '21~50명 구간');
      // 인원을 안 적은 문서는 어느 구간에서도 걸러지지 않는다(플레이스가 그렇다).
      for (final preset in CapacityFilter.presets) {
        expect(
          CapacityFilter.matches(<String, dynamic>{}, preset.people),
          isTrue,
          reason: preset.label,
        );
      }
    });

    test('필터 칩 표기는 바뀌지 않았다', () {
      final f = EventFilter(minCapacity: 20);
      final chip = f.selectedEntries.firstWhere((e) => e.key == 'minCapacity');
      expect(chip.value, '👥 20명');
    });
  });

  group('2. 알바생 훈남훈녀 — 새로 고를 수 없되 데이터는 산다', () {
    const retired = '알바생 훈남훈녀';

    test('선택지 목록에서 빠졌다 — 등록·콤보등록·상세검색이 이 목록을 쓴다', () {
      expect(ListingConstants.placeThemeTags, isNot(contains(retired)));
      expect(ListingConstants.retiredPlaceThemeTags, contains(retired));
    });

    test('아직 고를 수 있는 태그는 핫플·이벤트 둘뿐이다', () {
      expect(ListingConstants.placeThemeTags, ['핫플', '이벤트']);
    });

    test('표기표에는 남아 있다 — 이미 달린 문서를 그려야 한다', () {
      expect(ListingConstants.placeThemeTagEmojis[retired], '😎');
      expect(ListingConstants.placeThemeTagLabel(retired), retired);
    });

    test('이 태그를 단 옛 문서가 목록에서 사라지지 않는다', () {
      final doc = {
        'name': '옛 가게',
        'themeTags': [retired, '핫플'],
        'businessTypes': ['술집'],
      };
      // 조건 없는 기본 화면 — 통과.
      expect(EventFilter().matchesDiscovery(doc), isTrue);
      // 대분류·특징도 예전과 똑같이 걸린다.
      expect(PlaceTaxonomy.categoryOf(doc), '술집');
      expect(PlaceFeatures.of(doc), contains(PlaceFeatures.hot.key));
    });

    test('은퇴한 태그로도 여전히 걸러진다 — 저장된 조건이 깨지지 않게', () {
      // 필터 값 자체는 문자열이라, 어딘가에 저장돼 있던 조건이 그대로 동작한다.
      final f = EventFilter(themeTags: {retired});
      expect(f.isActive, isTrue);
    });
  });

  group('2-1. 혼술바 — 정본은 대분류 하나, 옛 태그는 읽기 전용', () {
    const tag = '혼술바';

    // 대분류가 생기기 전에 태그로만 등록된 가게.
    Map<String, dynamic> legacyTaggedBar() => {
      'name': '옛 혼술바',
      'businessTypes': ['바'],
      'themeTags': [tag, '핫플'],
    };

    test('새로 고르는 자리에서는 태그가 사라졌다 — 대분류로만 고른다', () {
      // 등록·콤보등록·상세검색이 모두 이 목록 하나를 선택지로 쓴다.
      expect(ListingConstants.placeThemeTags, isNot(contains(tag)));
      expect(ListingConstants.retiredPlaceThemeTags, contains(tag));
      // 대신 대분류에 있다.
      expect(PlaceTaxonomy.byLabel(tag), PlaceTaxonomy.soloBar);
    });

    test('표기는 남는다 — 이미 달린 문서를 카드·상세에 그려야 한다', () {
      expect(ListingConstants.placeThemeTagEmojis[tag], '🍷');
      expect(ListingConstants.placeThemeTagLabel(tag), tag);
      // 옛 태그와 새 대분류가 같은 이모지라 화면에서 같은 것으로 읽힌다.
      expect(PlaceTaxonomy.soloBar.emoji, '🍷');
    });

    test('옛 태그 문서는 새 혼술바 대분류 검색에 계속 걸린다', () {
      final doc = legacyTaggedBar();
      expect(EventFilter(categories: {tag}).matchesDiscovery(doc), isTrue);
    });

    test('그러면서 기존 BAR 노출도 깨지지 않는다 — 한쪽으로 옮기지 않았다', () {
      final doc = legacyTaggedBar();
      expect(PlaceTaxonomy.categoryOf(doc), 'BAR');
      expect(EventFilter(categories: {'BAR'}).matchesDiscovery(doc), isTrue);
      expect(
        EventFilter().matchesDiscovery(doc),
        isTrue,
        reason: '조건 없는 기본 화면',
      );
      expect(PlaceFeatures.of(doc), contains(PlaceFeatures.hot.key));
    });

    test('태그를 조건으로 들고 있던 옛 필터도 그대로 동작한다', () {
      final f = EventFilter(themeTags: {tag});
      expect(f.isActive, isTrue);
      // 칩 표기 ↔ 저장값 왕복도 그대로(표기를 따로 정하지 않은 태그).
      final chip = f.selectedEntries.firstWhere((e) => e.key == 'themeTags');
      expect(chip.value, tag);
      f.removeValue(chip.key, chip.value);
      expect(f.themeTags, isEmpty);
    });

    test('판정은 한 곳에서만 한다 — 대분류 다리는 혼술바에만 걸린다', () {
      // 다른 대분류를 골랐는데 태그 때문에 딸려오는 일이 없어야 한다.
      final doc = legacyTaggedBar();
      expect(EventFilter(categories: {'클럽'}).matchesDiscovery(doc), isFalse);
      expect(EventFilter(categories: {'맛집'}).matchesDiscovery(doc), isFalse);
      // 태그가 없는 BAR가 혼술바로 딸려오지도 않는다.
      expect(
        EventFilter(
          categories: {tag},
        ).matchesDiscovery({'placeCategory': 'BAR'}),
        isFalse,
      );
    });
  });

  group('2-2. 🎉 이벤트 — 업종과 다른 축, 업종을 덮어쓰지 않는다', () {
    final now = DateTime(2026, 9, 1);

    /// BAR로 등록된 가게가 생일 이벤트를 하는 중.
    Map<String, dynamic> barWithBirthdayEvent() => {
      'name': '생일 챙겨주는 바',
      'placeCategory': 'BAR',
      'themeTags': [ListingConstants.placeEventTag],
      PlaceEventTaxonomy.kindsField: [
        PlaceEventTaxonomy.birthday.key,
        PlaceEventTaxonomy.always.key,
      ],
    };

    test('이벤트는 대분류 저장값이 아니다 — 업종 목록에 들어 있지 않다', () {
      expect(PlaceTaxonomy.byLabel(PlaceEventTaxonomy.categoryLabel), isNull);
      // 화면에서만 같은 칸처럼 보인다. 이모지는 🎪(매장 이벤트) —
      // 참가자를 모집하는 🎉 파티와 절대 겹치지 않는다([HostOffering]).
      expect(PlaceEventTaxonomy.categoryEmoji, '✨');
      expect(PlaceEventTaxonomy.categoryEmoji, isNot(HostOffering.party.emoji));
      expect(PlaceEventTaxonomy.categoryLabel, '매장 이벤트');
    });

    test('BAR + 생일 이벤트인 가게는 **두 탐색 모두**에 걸린다', () {
      final doc = barWithBirthdayEvent();
      // 업종 축
      expect(
        EventFilter(categories: {'BAR'}).matchesDiscovery(doc, now: now),
        isTrue,
      );
      // 이벤트 축
      expect(
        EventFilter(eventOnly: true).matchesDiscovery(doc, now: now),
        isTrue,
      );
      expect(
        EventFilter(
          eventOnly: true,
          eventKinds: {PlaceEventTaxonomy.birthday.key},
        ).matchesDiscovery(doc, now: now),
        isTrue,
      );
    });

    test('이벤트를 켜도 placeCategory를 건드리지 않는다', () {
      final f = EventFilter(categories: {'BAR'})..selectEvent(true);
      expect(f.eventOnly, isTrue);
      // 화면에서만 배타적이다 — 저장값에 이벤트를 쓰지 않는다.
      expect(f.categories, isEmpty);
      // 반대 방향도 같다.
      f.selectCategory('클럽');
      expect(f.eventOnly, isFalse);
      expect(f.categories, {'클럽'});
    });

    test('옛 eventSubtype 문서도 새 생일 갈래에 걸린다 — 미러가 없어도', () {
      final legacy = {
        'businessTypes': ['술집'],
        'themeTags': [ListingConstants.placeEventTag],
        'eventSubtype': ListingConstants.birthdayEventSubtype,
      };
      expect(PlaceEventTaxonomy.kindsOf(legacy), {
        PlaceEventTaxonomy.birthday.key,
      });
      expect(
        EventFilter(
          eventOnly: true,
          eventKinds: {PlaceEventTaxonomy.birthday.key},
        ).matchesDiscovery(legacy, now: now),
        isTrue,
      );
      // 원래 걸리던 술집에서도 그대로 나온다.
      expect(
        EventFilter(categories: {'술집'}).matchesDiscovery(legacy, now: now),
        isTrue,
      );
    });

    test('갈래 미러가 없는 옛 이벤트 문서도 "이벤트 전체"에는 그대로 나온다', () {
      final legacy = {
        'themeTags': [ListingConstants.placeEventTag],
      };
      expect(PlaceEventTaxonomy.kindsOf(legacy), isEmpty);
      expect(
        EventFilter(eventOnly: true).matchesDiscovery(legacy, now: now),
        isTrue,
      );
      // 특정 갈래를 골랐을 때만 빠진다(미분류 대분류와 같은 취급).
      expect(
        EventFilter(
          eventOnly: true,
          eventKinds: {PlaceEventTaxonomy.limited.key},
        ).matchesDiscovery(legacy, now: now),
        isFalse,
      );
    });

    test('종료일이 지난 한정 이벤트는 탐색에서 저절로 빠진다', () {
      final ended = {
        'themeTags': [ListingConstants.placeEventTag],
        PlaceEventTaxonomy.kindsField: [PlaceEventTaxonomy.limited.key],
        PlaceEventTaxonomy.endsAtField: Timestamp.fromDate(
          DateTime(2026, 8, 31),
        ),
      };
      // 종료일 **그날 끝까지**는 진행 중이다.
      expect(
        PlaceEventTaxonomy.isRunningAt(ended, DateTime(2026, 8, 31, 23, 0)),
        isTrue,
      );
      expect(PlaceEventTaxonomy.isRunningAt(ended, now), isFalse);
      expect(
        EventFilter(eventOnly: true).matchesDiscovery(ended, now: now),
        isFalse,
      );
      // ⚠️ 그래도 업종 탐색·기본 목록에서는 사라지지 않는다.
      expect(EventFilter().matchesDiscovery(ended, now: now), isTrue);
    });

    test('상시 이벤트는 날짜가 없어도 계속 걸린다', () {
      final always = {
        'themeTags': [ListingConstants.placeEventTag],
        PlaceEventTaxonomy.kindsField: [PlaceEventTaxonomy.always.key],
        // endsAt 자체가 없다 — 기간으로는 끝나지 않는다는 뜻.
      };
      expect(
        EventFilter(
          eventOnly: true,
          eventKinds: {PlaceEventTaxonomy.always.key},
        ).matchesDiscovery(always, now: DateTime(2030, 1, 1)),
        isTrue,
      );
    });

    test('이벤트 태그가 없는 가게는 이벤트 탐색에 딸려오지 않는다', () {
      expect(
        EventFilter(
          eventOnly: true,
        ).matchesDiscovery({'placeCategory': 'BAR'}, now: now),
        isFalse,
      );
    });
  });

  group('2-3. 이벤트 갈래는 기존 프로모션에서 유도된다 — 두 번 묻지 않는다', () {
    PlacePromotion promo({
      PromotionType type = PromotionType.event,
      bool isAlways = false,
      DateTime? startAt,
      DateTime? endAt,
      String title = '이벤트',
      String benefit = '',
    }) => PlacePromotion(
      id: 'p',
      placeId: 'place',
      placeCollection: 'events',
      hostId: 'host',
      title: title,
      description: '',
      imageUrl: '',
      tags: const [],
      audience: '',
      startAt: startAt,
      endAt: endAt,
      isVisible: true,
      linkedProductIds: const [],
      sortOrder: 0,
      type: type,
      isAlways: isAlways,
      benefit: benefit,
    );

    test('기간이 있으면 한정, 상시 스위치면 상시', () {
      expect(
        PlaceEventTaxonomy.kindsOfPromotion(
          promo(endAt: DateTime(2026, 9, 30)),
        ),
        contains(PlaceEventTaxonomy.limited.key),
      );
      final always = PlaceEventTaxonomy.kindsOfPromotion(promo(isAlways: true));
      expect(always, contains(PlaceEventTaxonomy.always.key));
      expect(always, isNot(contains(PlaceEventTaxonomy.limited.key)));
    });

    test('호스트가 고른 유형이 그대로 갈래가 된다', () {
      expect(
        PlaceEventTaxonomy.kindsOfPromotion(promo(type: PromotionType.benefit)),
        contains(PlaceEventTaxonomy.benefit.key),
      );
      expect(
        PlaceEventTaxonomy.kindsOfPromotion(promo(type: PromotionType.package)),
        contains(PlaceEventTaxonomy.gift.key),
      );
      expect(
        PlaceEventTaxonomy.kindsOfPromotion(promo(type: PromotionType.event)),
        contains(PlaceEventTaxonomy.special.key),
      );
    });

    test('본문에서 생일·증정·할인을 읽어낸다 — 제목만 보지 않는다', () {
      final kinds = PlaceEventTaxonomy.kindsOfPromotion(
        promo(title: '9월 한 달', benefit: '생일자 웰컴드링크 무료'),
      );
      expect(kinds, contains(PlaceEventTaxonomy.birthday.key));
      expect(kinds, contains(PlaceEventTaxonomy.gift.key));
    });

    test('미러 — 상시가 하나라도 있으면 종료일을 두지 않는다', () {
      final now = DateTime(2026, 9, 1);
      final mixed = PlaceEventTaxonomy.mirrorFrom([
        promo(endAt: DateTime(2026, 9, 30)),
        promo(isAlways: true),
      ], now);
      expect(mixed.endsAt, isNull, reason: '기간으로는 끝나지 않는다');
      expect(mixed.kinds, contains(PlaceEventTaxonomy.limited.key));
      expect(mixed.kinds, contains(PlaceEventTaxonomy.always.key));

      // 한정만 있으면 **가장 늦은** 종료일이 미러가 된다.
      final onlyLimited = PlaceEventTaxonomy.mirrorFrom([
        promo(endAt: DateTime(2026, 9, 10)),
        promo(endAt: DateTime(2026, 9, 30)),
      ], now);
      expect(onlyLimited.endsAt, DateTime(2026, 9, 30));
    });

    test('숨겼거나 끝난 이벤트로는 갈래를 켜지 않는다', () {
      final now = DateTime(2026, 9, 1);
      final ended = promo(endAt: DateTime(2026, 8, 1));
      final mirror = PlaceEventTaxonomy.mirrorFrom([ended], now);
      expect(mirror.kinds, isEmpty);
      // 이벤트가 하나도 안 남으면 만료 판정을 걸지 않는다 — 태그만 켜 둔
      // 플레이스를 목록에서 지우지 않기 위함이다.
      expect(mirror.endsAt, isNull);
    });
  });

  group('3. 업종별로 필요한 세부정보만 나온다', () {
    /// 각 대분류에서 **나와야 하는 것**과 **나오면 안 되는 것**.
    const expectations = <String, ({List<String> shows, List<String> hides})>{
      '맛집': (
        shows: ['unlimited', 'corkage', 'alcoholTypes', 'bbq', 'smoking'],
        hides: ['musicGenres', 'clubEntry', 'dj'],
      ),
      '카페·디저트': (
        shows: ['unlimited', 'purposes', 'playItems', 'smoking'],
        hides: ['musicGenres', 'clubEntry', 'dj', 'alcoholTypes', 'corkage'],
      ),
      'BAR': (
        shows: ['alcoholTypes', 'corkage', 'dj', 'smoking'],
        hides: ['musicGenres', 'clubEntry'],
      ),
      '클럽': (
        shows: ['musicGenres', 'dj', 'clubEntry', 'smoking', 'unlimited'],
        hides: ['bbq'],
      ),
      '놀거리': (
        shows: ['playItems', 'screen', 'purposes', 'smoking', 'bbq'],
        hides: ['musicGenres', 'clubEntry', 'alcoholTypes', 'corkage'],
      ),
    };

    for (final entry in expectations.entries) {
      test('${entry.key} 등록 화면', () {
        final keys = PlaceAttributeCatalog.groupsFor(
          entry.key,
        ).map((g) => g.key).toSet();
        for (final k in entry.value.shows) {
          expect(keys, contains(k), reason: '${entry.key}에는 $k가 나와야 한다');
        }
        for (final k in entry.value.hides) {
          expect(
            keys,
            isNot(contains(k)),
            reason: '${entry.key}에 $k가 나오면 안 된다',
          );
        }
      });
    }

    test('흡연 정책은 모든 업종 공통', () {
      for (final c in PlaceTaxonomy.all) {
        expect(
          PlaceAttributeCatalog.groupsFor(c.label).map((g) => g.key),
          contains(PlaceAttributeCatalog.smokingKey),
          reason: c.label,
        );
      }
    });
  });

  group('4. 클럽 등록 흐름 — 대분류 → 장르 → DJ → 흡연', () {
    testWidgets('대분류를 고르면 그 대분류의 소분류만 펼쳐진다', (tester) async {
      String? category;
      final subs = <String>{};

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SingleChildScrollView(
                child: PlaceCategorySection(
                  category: category,
                  subcategories: subs,
                  onCategoryChanged: (v) => setState(() {
                    category = v;
                    subs.clear();
                  }),
                  onSubcategoryToggled: (s) => setState(() {
                    if (!subs.remove(s)) subs.add(s);
                  }),
                ),
              ),
            ),
          ),
        ),
      );

      // 아직 아무것도 안 골랐으면 소분류 자체가 없다 — 폼이 처음부터 길지 않다.
      expect(find.text('한식'), findsNothing);
      expect(find.text('와인바'), findsNothing);

      // 클럽은 **소분류를 더 이상 묻지 않는다** — 장르(musicGenres)가 정본이라
      //   같은 말을 두 곳에 저장하지 않기 위해서다. 은퇴한 값도 폼에 없다.
      await tester.tap(find.text(PlaceTaxonomy.club.display));
      await tester.pumpAndSettle();
      expect(category, '클럽');
      expect(find.text('힙합클럽'), findsNothing);
      expect(find.text('와인바'), findsNothing);

      // 소분류를 그대로 쓰는 대분류는 예전과 똑같이 펼쳐진다.
      await tester.tap(find.text(PlaceTaxonomy.restaurant.display));
      await tester.pumpAndSettle();
      expect(category, '맛집');
      expect(find.text('한식'), findsOneWidget);
      expect(find.text('와인바'), findsNothing);

      await tester.tap(find.text('한식'));
      await tester.pumpAndSettle();
      expect(subs, {'한식'});
    });

    testWidgets('클럽 세부정보 — 장르 → DJ → 라인업 → 흡연이 이어진다', (tester) async {
      var attrs = PlaceAttributes.empty();

      Future<void> pump(WidgetTester t) => t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SingleChildScrollView(
                child: PlaceAttributesSection(
                  category: '클럽',
                  value: attrs,
                  initiallyExpanded: true,
                  onChanged: (next) => setState(() => attrs = next),
                ),
              ),
            ),
          ),
        ),
      );

      await pump(tester);

      // 클럽에 필요한 것이 다 있다.
      expect(find.text('HIPHOP'), findsOneWidget);
      expect(find.text('R&B'), findsOneWidget);
      expect(find.text('🎧 DJ 있음'), findsOneWidget);
      expect(find.text('🚭 전 구역 금연'), findsOneWidget);
      // 음식점에서 주로 묻는 🍖 BBQ도 **끄지 않는다** — 게스트는 업종과
      // 상관없이 🍖으로 검색하므로, 클럽 호스트에게도 켤 자리가 있어야 한다.
      // 다만 위쪽 업종 표가 아니라 '그 밖의 편의·서비스' 아래로 내려간다.
      expect(find.text('그 밖의 편의·서비스'), findsOneWidget);
      expect(find.text('🍖 BBQ 가능'), findsOneWidget);

      // DJ를 켜기 전에는 라인업 입력란이 없다 — 폼이 처음부터 복잡하지 않다.
      expect(find.text('오늘 DJ · 라인업'), findsNothing);

      // 섹션이 길어 아래 항목은 화면 밖에 있다 — 실제 사용자처럼 스크롤해
      // 눈에 보이게 한 뒤 누른다.
      Future<void> tapChip(String label) async {
        final finder = find.text(label);
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await tapChip('HIPHOP');
      await tapChip('R&B');
      await tapChip('🎧 DJ 있음');

      // 켠 뒤에야 상세 입력란이 나타난다.
      expect(find.text('오늘 DJ · 라인업'), findsOneWidget);

      await tapChip('🚬 별도 흡연실 있음');

      expect(attrs.selected('musicGenres'), {'HIPHOP', 'R&B'});
      expect(attrs.isSelected('dj', 'DJ 있음'), isTrue);
      expect(
        attrs.single(PlaceAttributeCatalog.smokingKey),
        PlaceAttributeCatalog.smokingRoom,
      );

      // 이렇게 등록한 클럽이 곧바로 게스트 필터에 걸린다.
      final doc = {
        'placeCategory': '클럽',
        'placeSubcategories': ['힙합클럽'],
        'placeAttributes': attrs.toMap(),
      };
      final f = EventFilter(
        categories: {'클럽'},
        subcategories: {'힙합클럽'},
        features: {PlaceFeatures.dj.key, PlaceFeatures.smokeFree.key},
        attributes: {
          'musicGenres': {'HIPHOP'},
        },
      );
      expect(f.matchesDiscovery(doc), isTrue);
    });

    testWidgets('카페를 고르면 업종 안에서만 뜻이 있는 항목만 빠진다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PlaceAttributesSection(
                category: '카페·디저트',
                value: PlaceAttributes.empty(),
                initiallyExpanded: true,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      // 음악 장르·입장 정보는 특징을 하나도 안 켠다 — 클럽 밖에서는 물을
      // 이유가 없으므로 카페 폼에서 그대로 빠진다.
      expect(find.text('HIPHOP'), findsNothing);
      expect(find.text('입장 정보'), findsNothing);
      // 카페에 필요한 것은 그대로 있다.
      expect(find.text('🚭 전 구역 금연'), findsOneWidget);
      expect(find.text('보드게임'), findsOneWidget);
      // 반면 **게스트가 업종과 상관없이 검색하는 조건**은 '그 밖의 편의·서비스'
      // 아래에 반드시 있다 — 여기서 빠지면 "손님은 찾는데 카페 사장은 켤 수
      // 없는" 조건이 된다(🎧 DJ · 🍶 콜키지 가능 · 🍽️ 조리되어 나와요 …).
      expect(find.text('그 밖의 편의·서비스'), findsOneWidget);
      expect(find.text('🎧 DJ 있음'), findsOneWidget);
      // 등록 폼이 그리는 것은 필터 이름이 아니라 **선택지**다. 무료 선택지는
      // 저장값이 옛 '콜키지 프리' 그대로이고 보이는 글자만 '콜키지 무료'다
      // (PlaceAttributeOption.displayLabel).
      expect(find.text('🍶 콜키지 무료'), findsOneWidget);
      expect(find.text('💵 콜키지 유료'), findsOneWidget);
      expect(find.text('🍽️ 조리되어 나옴'), findsOneWidget);
      expect(find.text('🔥 직원이 전부 구워줌'), findsOneWidget);
      expect(find.text('🍖 BBQ 가능'), findsOneWidget);
    });
  });

  group('5. 옛 플레이스는 기본 화면에서 사라지지 않는다', () {
    /// 실제로 등록돼 있을 법한, 새 필드가 하나도 없는 문서들.
    final legacyDocs = <String, Map<String, dynamic>>{
      '업종만 있는 문서': {
        'name': 'A',
        'businessTypes': ['카페'],
      },
      '옛 단일 업종': {'name': 'B', 'businessType': '바'},
      '태그만 있는 문서': {
        'name': 'C',
        'themeTags': ['핫플'],
      },
      '옛 단일 category': {'name': 'D', 'category': '혼술바'},
      '이름밖에 없는 문서': {'name': 'E'},
      '업종이 기타뿐': {
        'name': 'F',
        'businessTypes': ['기타'],
      },
    };

    test('조건 없는 기본 화면에서 전부 통과한다', () {
      final f = EventFilter();
      expect(f.isActive, isFalse, reason: '기본 상태는 조건이 없다');
      for (final e in legacyDocs.entries) {
        expect(f.matchesDiscovery(e.value), isTrue, reason: e.key);
      }
    });

    test('특징 유도가 터지지 않는다 — 어떤 문서든 집합 하나를 돌려준다', () {
      for (final e in legacyDocs.entries) {
        expect(() => PlaceFeatures.of(e.value), returnsNormally, reason: e.key);
      }
    });

    test('빠른 필터를 켜야만 걸러진다 — 켜기 전에는 아무도 안 빠진다', () {
      final f = EventFilter();
      for (final e in legacyDocs.entries) {
        expect(f.matchesDiscovery(e.value), isTrue, reason: e.key);
      }
      f.toggleFeature(PlaceFeatures.pool.key);
      // 이제는 조건에 맞는 곳만 남는다(옛 문서는 수영장을 안 적었다).
      for (final e in legacyDocs.entries) {
        expect(f.matchesDiscovery(e.value), isFalse, reason: e.key);
      }
    });

    test('대분류를 유추할 수 있는 문서는 새 카테고리 바에도 제자리에 뜬다', () {
      expect(PlaceTaxonomy.categoryOf(legacyDocs['업종만 있는 문서']!), '카페·디저트');
      expect(PlaceTaxonomy.categoryOf(legacyDocs['옛 단일 업종']!), 'BAR');
      // 유추할 수 없는 문서는 미분류지만 '전체'에서는 그대로 보인다.
      expect(PlaceTaxonomy.categoryOf(legacyDocs['업종이 기타뿐']!), isNull);
      expect(EventFilter().matchesDiscovery(legacyDocs['업종이 기타뿐']!), isTrue);
    });
  });
}

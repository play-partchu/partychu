import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/event_filter.dart';
import 'package:party_app/models/place_party_index.dart';
import 'package:party_app/models/place_quick_picks.dart';
import 'package:party_app/models/place_taxonomy.dart';
import 'package:party_app/services/listing_sources.dart';
import 'package:party_app/services/place_party_link_service.dart';
import 'package:party_app/widgets/main/place_category_explorer.dart';

/// 🎉 With파티의 약속을 고정한다.
///
/// 핵심은 하나다 — **연결은 문서 안에 새로 적지 않는다.** 정본은 파티 쪽
/// `parties.linkedEventId`이고, "지금 노출 가능한 파티인가"는 파티 목록·지도가
/// 쓰는 판정([ListingSources.isPartyVisible]) 그대로다. 그래서 파티가 지워지거나
/// 지나가면 플레이스도 저절로 With파티에서 빠진다.
void main() {
  final now = DateTime(2026, 8, 26, 12);

  Map<String, dynamic> party({
    required String? linkedEventId,
    DateTime? at,
    bool deleted = false,
    String? linkedPlaceId,
  }) => {
    'title': '테스트 파티',
    if (linkedEventId != null) PlacePartyLink.linkedEventIdField: linkedEventId,
    if (linkedPlaceId != null) 'linkedPlaceId': linkedPlaceId,
    if (deleted) 'isDeleted': true,
    'date': (at ?? now.add(const Duration(days: 3))).toIso8601String(),
  };

  group('정본 — 파티의 linkedEventId 하나만 본다', () {
    test('연결된 파티가 있으면 그 플레이스 id가 색인에 들어간다', () {
      final index = PlacePartyIndex.fromParties([
        party(linkedEventId: 'place-A'),
      ], now: now);
      expect(index.has('place-A'), isTrue);
      expect(index.has('place-B'), isFalse);
    });

    test('연결이 없는 파티는 아무 플레이스도 켜지 않는다', () {
      final index = PlacePartyIndex.fromParties([
        party(linkedEventId: null),
      ], now: now);
      expect(index.isEmpty, isTrue);
    });

    test('장소대여 연결(linkedPlaceId)은 플레이스 With파티가 아니다', () {
      // 두 필드는 가리키는 컬렉션이 다르다(events / places).
      final index = PlacePartyIndex.fromParties([
        party(linkedEventId: null, linkedPlaceId: 'rental-A'),
      ], now: now);
      expect(index.has('rental-A'), isFalse);
    });

    test('플레이스 문서에 수동 필드를 만들지 않는다 — 판정은 파티에서만 온다', () {
      // 문서에 아무리 그럴듯한 값이 있어도 색인이 비면 안 걸린다.
      final f = EventFilter(withPartyOnly: true);
      final place = {
        'name': '가짜',
        'withParty': true,
        'linkedPartyIds': ['party-1'],
        'isCombo': true,
      };
      expect(
        f.matchesDiscovery(
          place,
          docId: 'place-A',
          partyIndex: PlacePartyIndex.empty,
        ),
        isFalse,
        reason: '보조 배열·수동 플래그는 정본이 아니다',
      );
    });
  });

  group('노출 정책 — 파티 목록과 같은 판정을 쓴다', () {
    test('삭제된 파티 연결은 인정하지 않는다', () {
      final index = PlacePartyIndex.fromParties([
        party(linkedEventId: 'place-A', deleted: true),
      ], now: now);
      expect(index.has('place-A'), isFalse);
    });

    test('이미 지난 파티 연결은 인정하지 않는다', () {
      final index = PlacePartyIndex.fromParties([
        party(
          linkedEventId: 'place-A',
          at: now.subtract(const Duration(days: 2)),
        ),
      ], now: now);
      expect(index.has('place-A'), isFalse);
    });

    test('오늘 열리는 파티는 인정한다 — 목록 판정과 같은 경계다', () {
      final doc = party(linkedEventId: 'place-A', at: now);
      expect(ListingSources.isPartyVisible(doc, now: now), isTrue);
      expect(
        PlacePartyIndex.fromParties([doc], now: now).has('place-A'),
        isTrue,
      );
    });

    test('판정을 새로 쓰지 않는다 — 색인과 파티 목록 결과가 언제나 같다', () {
      final docs = [
        party(linkedEventId: 'p1'),
        party(linkedEventId: 'p2', deleted: true),
        party(linkedEventId: 'p3', at: now.subtract(const Duration(days: 1))),
        party(linkedEventId: 'p4', at: now.add(const Duration(days: 30))),
      ];
      final index = PlacePartyIndex.fromParties(docs, now: now);
      final byListPolicy = {
        for (final d in docs)
          if (ListingSources.isPartyVisible(d, now: now))
            PlacePartyLink.linkedEventIdOf(d)!,
      };
      expect(index.placeIds, byListPolicy);
    });
  });

  group('플레이스 하나는 한 번만', () {
    test('파티가 여럿 붙어도 id는 하나다', () {
      final index = PlacePartyIndex.fromParties([
        party(linkedEventId: 'place-A'),
        party(linkedEventId: 'place-A'),
        party(linkedEventId: 'place-A', at: now.add(const Duration(days: 9))),
      ], now: now);
      expect(index.placeIds, {'place-A'});
    });

    test('살아 있는 파티가 하나라도 있으면 걸린다 — 지난 파티가 섞여 있어도', () {
      final index = PlacePartyIndex.fromParties([
        party(
          linkedEventId: 'place-A',
          at: now.subtract(const Duration(days: 5)),
        ),
        party(linkedEventId: 'place-A', at: now.add(const Duration(days: 5))),
      ], now: now);
      expect(index.has('place-A'), isTrue);
    });
  });

  group('필터 판정', () {
    final place = {'name': '연결된 매장', 'placeCategory': '맛집'};
    final index = PlacePartyIndex(const {'place-A'});

    test('켜면 연결된 곳만 통과한다', () {
      final f = EventFilter(withPartyOnly: true);
      expect(
        f.matchesDiscovery(place, docId: 'place-A', partyIndex: index),
        isTrue,
      );
      expect(
        f.matchesDiscovery(place, docId: 'place-B', partyIndex: index),
        isFalse,
      );
    });

    test('끄면 예전과 똑같이 전부 통과한다 — 옛 문서가 사라지지 않는다', () {
      final f = EventFilter();
      expect(f.matchesDiscovery(place), isTrue);
      expect(f.matchesDiscovery(place, docId: 'place-B'), isTrue);
    });

    test('색인을 못 받았으면 아무것도 통과시키지 않는다', () {
      final f = EventFilter(withPartyOnly: true);
      expect(f.matchesDiscovery(place, docId: 'place-A'), isFalse);
      expect(
        f.matchesDiscovery(
          place,
          docId: 'place-A',
          partyIndex: PlacePartyIndex.empty,
        ),
        isFalse,
      );
    });

    test('업종과 겹쳐 걸 수 있다 — 대분류를 덮어쓰지 않는 다른 축이다', () {
      final f = EventFilter(categories: {'맛집'}, withPartyOnly: true);
      expect(
        f.matchesDiscovery(place, docId: 'place-A', partyIndex: index),
        isTrue,
      );
      expect(
        f.matchesDiscovery(
          {'name': '카페', 'placeCategory': '카페·디저트'},
          docId: 'place-A',
          partyIndex: index,
        ),
        isFalse,
        reason: '업종 조건은 그대로 함께 걸린다',
      );
    });

    test('조건으로 인정되고 칩·해제가 다른 조건과 같은 방식이다', () {
      final f = EventFilter(withPartyOnly: true);
      expect(f.isActive, isTrue);
      final chip = f.selectedEntries.firstWhere(
        (e) => e.key == 'withPartyOnly',
      );
      expect(chip.value, '🎉 With파티');
      f.removeValue(chip.key, chip.value);
      expect(f.withPartyOnly, isFalse);
    });

    test('복사·초기화가 다른 조건과 같이 동작한다', () {
      final f = EventFilter(withPartyOnly: true);
      expect(f.copy().withPartyOnly, isTrue);
      f.clearDiscovery();
      expect(f.withPartyOnly, isFalse);
    });
  });

  group('상단 카테고리 구조', () {
    // 🎪 매장 이벤트 칸은 다시 격자로 돌아왔다(place_event_index_test.dart가
    // 그 자리를 지킨다). 여기서 지키는 것은 **축이 그대로 살아 있다**는 것 —
    // 칸이 있든 없든 조건·갈래·해제가 예전과 똑같이 동작해야 한다.
    test('🎪 매장 이벤트 축은 화면과 무관하게 그대로 살아 있다', () {
      // 데이터·판정은 한 번도 건드리지 않았다.
      final f = EventFilter(eventOnly: true);
      expect(f.isActive, isTrue);
      expect(f.selectedEntries.any((e) => e.key == 'eventOnly'), isTrue);
      // 켜진 상태로 들어오면 하위 탐색(갈래)도 예전 그대로 열린다.
      expect(PlaceQuickPicks.drillFor(event: true), isNotEmpty);
      // 끌 수도 있다.
      f.selectEvent(false);
      expect(f.eventOnly, isFalse);
    });

    test('✨ 편의·서비스는 대분류가 아니라 빠른필터 줄의 칩이다', () {
      // 편의·서비스는 업종(대분류)이 아니다 — 상단 격자에는 자리를 두지 않고,
      // 아래 빠른필터 줄의 '✨ 편의·서비스' 칩 하나만 시트를 연다.
      final fromRow = PlaceQuickPicks.forCategory(
        PlaceTaxonomy.pub.label,
      ).firstWhere((p) => p.display == '✨ 편의·서비스');
      expect(fromRow.opensSheet, isTrue);

      final f = EventFilter();
      // 🎉 With파티(다른 축)와 ♾ 무제한 묶음(속성 축)도 같은 시트에 담기므로,
      // 특징 값을 찾을 때는 값이 있는 칩만 본다.
      fromRow.options
          .where((o) => o.values.isNotEmpty)
          .firstWhere((o) => o.values.first == '콜키지프리')
          .toggle(f);
      expect(fromRow.isOn(f), isTrue);
      expect(f.features, contains('콜키지프리'));
    });

    testWidgets('🎉 With파티는 상단 카테고리 격자에 없다', (tester) async {
      // 이 줄은 '무슨 가게인가'(업종)를 고르는 자리다. With파티는 업종이
      // 아니라 조건이라, 여기 있으면 누를 때 카테고리가 바뀌는 것처럼
      // 읽힌다. 격자에 남는 것은 전체 + 업종 아홉 + 파티샵뿐이다.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PlaceCategoryExplorer(
                filter: EventFilter(),
                onChanged: () {},
                onSelectShop: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('With파티'), findsNothing);
      // 남아 있어야 할 칸은 전부 그대로다.
      expect(find.text('전체'), findsOneWidget);
      expect(find.text('파티샵'), findsOneWidget);
      // 격자에 서는 것은 **살아 있는** 대분류다 — 은퇴한 BAR·라이브는 칸을
      // 갖지 않고, 그 가게들은 살아 있는 대분류에서 함께 뜬다
      // ([PlaceTaxonomy.matchesAnyCategory]의 은퇴 다리).
      for (final c in PlaceTaxonomy.selectable) {
        expect(find.text(c.shortLabel), findsOneWidget, reason: c.shortLabel);
      }
    });

    test('🎉 With파티는 ✨ 편의·서비스 시트 안의 항목이다', () {
      // 자리만 옮겼다 — 켜는 값도([EventFilter.withPartyOnly]) 판정도
      // ([PlacePartyIndex]) 그대로다.
      final amenity = PlaceQuickPicks.forCategory(
        PlaceTaxonomy.pub.label,
      ).firstWhere((p) => p.display == '✨ 편의·서비스');
      final withParty = amenity.options.firstWhere(
        (o) => o.display == '🎉 With파티',
      );
      // 추천 묶음의 **맨 앞** — 업종이 무엇이든 가장 먼저 묻는 조건이라
      // 업종별 추천 표보다도 위에 붙는다('다른 편의·서비스'로 밀려나 있지 않다).
      expect(amenity.recommendedOptions.first, same(withParty));

      final f = EventFilter();
      withParty.toggle(f);
      expect(f.withPartyOnly, isTrue);
      expect(amenity.isOn(f), isTrue);
      // 시트 칩이 고른 항목 이름을 그대로 말한다(이모지가 겹치지 않는다).
      expect(amenity.displayFor(f), '🎉 With파티');
      withParty.toggle(f);
      expect(f.withPartyOnly, isFalse);
    });

    test('업종을 무엇으로 고르든 🎉 With파티는 편의·서비스 안에 있다', () {
      for (final category in [null, ...PlaceTaxonomy.all.map((c) => c.label)]) {
        final kinds = PlaceQuickPicks.amenityKinds(category);
        expect(
          kinds.where((k) => k.display == '🎉 With파티'),
          hasLength(1),
          reason: '${category ?? '전체'}에서 빠졌거나 두 번 들어갔다',
        );
      }
    });

    test('전용 식별자가 대분류 저장값과 겹치지 않는다', () {
      final reserved = {
        PlaceCategoryExplorer.withPartyValue,
        PlaceCategoryExplorer.eventValue,
        PlaceCategoryExplorer.shopValue,
      };
      expect(reserved.length, 3, reason: '식별자끼리도 겹치면 안 된다');
      for (final c in PlaceTaxonomy.all) {
        expect(reserved, isNot(contains(c.label)));
      }
    });
  });

  group('목록·지도 정본 공유', () {
    test('두 화면이 같은 색인 함수를 쓰면 결과가 같다', () {
      final docs = [
        party(linkedEventId: 'p1'),
        party(linkedEventId: 'p2', deleted: true),
      ];
      // 목록(main_screen)과 지도(map_screen)가 부르는 것과 같은 경로.
      final a = PlacePartyIndex.fromParties(docs, now: now);
      final b = PlacePartyIndex.fromParties(docs, now: now);
      expect(a.sameAs(b), isTrue);

      final f = EventFilter(withPartyOnly: true);
      const place = {'name': 'x'};
      for (final id in ['p1', 'p2']) {
        expect(
          f.matchesDiscovery(place, docId: id, partyIndex: a),
          f.matchesDiscovery(place, docId: id, partyIndex: b),
          reason: id,
        );
      }
    });

    test('sameAs가 집합이 달라지면 알아챈다 — 헛되이 다시 그리지 않기 위한 비교', () {
      expect(
        const PlacePartyIndex({'a'}).sameAs(const PlacePartyIndex({'a'})),
        isTrue,
      );
      expect(
        const PlacePartyIndex({'a'}).sameAs(const PlacePartyIndex({'b'})),
        isFalse,
      );
      expect(
        const PlacePartyIndex({'a'}).sameAs(const PlacePartyIndex({'a', 'b'})),
        isFalse,
      );
    });
  });
}

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/models/event_filter.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/models/place_event_index.dart';
import 'package:party_app/models/place_event_taxonomy.dart';
import 'package:party_app/models/place_filter.dart';
import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/models/place_taxonomy.dart';
import 'package:party_app/widgets/main/place_category_explorer.dart';

/// 🎉 이벤트 — **업종 격자의 한 칸**으로 고르면 기존 플레이스 목록이 이벤트
/// 중인 매장만 남는다.
///
/// 여기서 고정하는 것은 셋이다.
///   ① 어떤 매장이 이벤트 중인가([PlaceEventIndex]) — 노출 정책 자체는
///      [PlacePromotion.statusAt]이 갖고 있고, 이 색인은 그것을 그대로 따른다.
///   ② 그 판정이 **기존 목록 필터**에 그대로 걸리는가
///      ([EventFilter.matchesDiscovery]).
///   ③ 이벤트가 저장되는 업종이 아니라 탐색용 특수 항목인가.
void main() {
  final now = DateTime(2026, 8, 29, 20);

  PlacePromotion promo({
    required String id,
    required String placeId,
    String title = '이벤트',
    String placeCollection = 'events',
    bool isVisible = true,
    bool isAlways = false,
    DateTime? startAt,
    DateTime? endAt,
    int sortOrder = 0,
  }) => PlacePromotion.empty(
    placeId: placeId,
    placeCollection: placeCollection,
    hostId: 'host-$placeId',
    sortOrder: sortOrder,
  ).copyWith(
    id: id,
    title: title,
    isVisible: isVisible,
    isAlways: isAlways,
    startAt: startAt,
    endAt: endAt,
  );

  PlaceEventIndex index(List<PlacePromotion> promotions) =>
      PlaceEventIndex.fromPromotions(promotions, now: now);

  group('어떤 매장이 이벤트 중인가', () {
    test('이벤트가 하나도 없으면 빈 집합이다', () {
      expect(index(const []).isEmpty, isTrue);
    });

    test('이벤트 하나 있는 매장은 들어간다', () {
      final ids = index([promo(id: 'e1', placeId: 'p1')]);
      expect(ids.has('p1'), isTrue);
      expect(ids.has('p2'), isFalse, reason: '이벤트 없는 매장은 빠진다');
    });

    test('한 매장에 이벤트가 여럿이어도 id는 하나다 — 카드가 복제되지 않는다', () {
      final ids = index([
        promo(id: 'e1', placeId: 'p1', title: '첫 번째'),
        promo(id: 'e2', placeId: 'p1', title: '두 번째', sortOrder: 1),
        promo(id: 'e3', placeId: 'p1', title: '세 번째', sortOrder: 2),
      ]);
      expect(ids.placeIds, {'p1'});
      expect(ids.length, 1);
    });

    test('여러 매장 — 매장마다 id 하나', () {
      final ids = index([
        promo(id: 'e1', placeId: 'p1'),
        promo(id: 'e2', placeId: 'p2'),
        promo(id: 'e3', placeId: 'p3'),
      ]);
      expect(ids.placeIds, {'p1', 'p2', 'p3'});
    });
  });

  group('노출 정책 — 기존 판정을 그대로 따른다', () {
    test('종료된 이벤트만 있는 매장은 빠진다', () {
      final ids = index([
        promo(id: 'ended', placeId: 'p1', endAt: DateTime(2026, 8, 28)),
      ]);
      expect(ids.has('p1'), isFalse);
    });

    test('숨긴 이벤트만 있는 매장은 빠진다', () {
      final ids = index([
        promo(id: 'hidden', placeId: 'p1', isVisible: false),
      ]);
      expect(ids.has('p1'), isFalse);
    });

    test('종료·숨김이 섞여 있어도 살아 있는 이벤트가 하나면 남는다', () {
      final ids = index([
        promo(id: 'ended', placeId: 'p1', endAt: DateTime(2026, 8, 1)),
        promo(id: 'hidden', placeId: 'p1', isVisible: false),
        promo(id: 'live', placeId: 'p1', title: '진행 중'),
        // p2는 끝난 것뿐이라 빠진다.
        promo(id: 'ended2', placeId: 'p2', endAt: DateTime(2026, 8, 20)),
      ]);
      expect(ids.placeIds, {'p1'});
    });

    test('시작 전 이벤트도 "곧 하는 곳"으로 남는다', () {
      final ids = index([
        promo(id: 'soon', placeId: 'p1', startAt: DateTime(2026, 9, 5)),
      ]);
      expect(ids.has('p1'), isTrue);
    });

    test('종료일 당일에는 아직 남아 있다', () {
      final ids = index([
        promo(id: 'today', placeId: 'p1', endAt: DateTime(2026, 8, 29)),
      ]);
      expect(ids.has('p1'), isTrue);
    });

    test('상시 이벤트는 날짜와 무관하게 남는다', () {
      final ids = PlaceEventIndex.fromPromotions([
        promo(id: 'always', placeId: 'p1', isAlways: true),
      ], now: DateTime(2030, 1, 1));
      expect(ids.has('p1'), isTrue);
    });

    test('공간대여(places)의 프로모션은 세지 않는다', () {
      final ids = index([
        promo(id: 'e1', placeId: 'r1', placeCollection: 'places'),
      ]);
      expect(ids.isEmpty, isTrue);
    });
  });

  // 장소대여 탭에도 🎪 이벤트 축이 생겼다. 색인은 **컬렉션 하나만** 담으므로
  // 두 탭이 서로의 이벤트를 볼 수 없다 — id가 우연히 겹쳐도 마찬가지다.
  group('컬렉션별로 따로 담는다', () {
    test('장소대여 색인에는 places의 이벤트만 들어간다', () {
      final ids = PlaceEventIndex.fromPromotions(
        [
          promo(id: 'e1', placeId: 'venue', placeCollection: 'events'),
          promo(id: 'e2', placeId: 'rental', placeCollection: 'places'),
        ],
        now: now,
        collection: PlaceEventIndex.rentalCollection,
      );
      expect(ids.has('rental'), isTrue);
      expect(ids.has('venue'), isFalse, reason: '매장 이벤트가 장소대여에 섞였다');
    });

    test('id가 같아도 컬렉션이 다르면 서로를 집지 않는다', () {
      final promotions = [
        promo(id: 'e1', placeId: 'x', placeCollection: 'events'),
      ];
      expect(index(promotions).has('x'), isTrue);
      expect(
        PlaceEventIndex.fromPromotions(
          promotions,
          now: now,
          collection: PlaceEventIndex.rentalCollection,
        ).has('x'),
        isFalse,
      );
    });

    test('숨김·종료 판정은 컬렉션과 무관하게 같다', () {
      final ids = PlaceEventIndex.fromPromotions(
        [
          promo(id: 'hidden', placeId: 'r1', placeCollection: 'places',
              isVisible: false),
          promo(id: 'ended', placeId: 'r2', placeCollection: 'places',
              endAt: now.subtract(const Duration(days: 2))),
          promo(id: 'live', placeId: 'r3', placeCollection: 'places'),
        ],
        now: now,
        collection: PlaceEventIndex.rentalCollection,
      );
      expect(ids.placeIds, {'r3'});
    });
  });

  group('같은 집합인지 비교', () {
    test('순서가 달라도 같은 집합이면 같다 — 목록을 다시 그리지 않는다', () {
      final a = index([
        promo(id: 'e1', placeId: 'p1'),
        promo(id: 'e2', placeId: 'p2'),
      ]);
      final b = index([
        promo(id: 'e2', placeId: 'p2'),
        promo(id: 'e1', placeId: 'p1'),
      ]);
      expect(a.sameAs(b), isTrue);
    });

    test('매장이 하나 늘면 다른 집합이다', () {
      final a = index([promo(id: 'e1', placeId: 'p1')]);
      final b = index([
        promo(id: 'e1', placeId: 'p1'),
        promo(id: 'e2', placeId: 'p2'),
      ]);
      expect(a.sameAs(b), isFalse);
    });
  });

  // ── 기존 목록 필터에 그대로 걸린다 ────────────────────────────────────
  //
  // 🎉 이벤트를 고르면 **이벤트 목록**이 아니라 이 판정을 통과한 매장만 남은
  // 기존 플레이스 목록이 보인다. 카드도 상세도 평소와 같은 것이라, 여기서
  // 확인할 것은 "무엇이 남는가" 하나뿐이다.
  group('플레이스 목록 필터', () {
    Map<String, dynamic> bar() => {
      'name': '내잔 혼술바',
      'placeCategory': 'BAR',
      'themeTags': [ListingConstants.placeEventTag],
    };

    test('이벤트 색인에 있는 매장만 남는다', () {
      final ids = index([promo(id: 'e1', placeId: 'p1')]);
      final f = EventFilter(eventOnly: true);

      expect(
        f.matchesDiscovery(bar(), now: now, docId: 'p1', eventIndex: ids),
        isTrue,
      );
      expect(
        f.matchesDiscovery(bar(), now: now, docId: 'p2', eventIndex: ids),
        isFalse,
        reason: '이벤트가 없는 매장은 태그가 남아 있어도 빠진다',
      );
    });

    test('종료·숨김만 남은 매장은 빠진다 — 눌러도 볼 이벤트가 없다', () {
      final ids = index([
        promo(id: 'ended', placeId: 'p1', endAt: DateTime(2026, 8, 1)),
      ]);
      expect(
        EventFilter(
          eventOnly: true,
        ).matchesDiscovery(bar(), now: now, docId: 'p1', eventIndex: ids),
        isFalse,
      );
    });

    test('색인을 아직 못 읽었으면 예전 미러 판정 그대로다', () {
      // 목록이 잠깐 통째로 비는 것보다, 조금 넉넉한 예전 판정이 낫다.
      expect(
        EventFilter(eventOnly: true).matchesDiscovery(bar(), now: now),
        isTrue,
      );
      expect(
        EventFilter(
          eventOnly: true,
        ).matchesDiscovery({'placeCategory': 'BAR'}, now: now),
        isFalse,
      );
    });

    test('이벤트를 켜도 업종·조건 필터는 그대로 함께 걸린다', () {
      final ids = index([promo(id: 'e1', placeId: 'p1')]);
      // 갈래(소분류)는 예전처럼 본체 미러에서 본다.
      final doc = {
        ...bar(),
        PlaceEventTaxonomy.kindsField: [PlaceEventTaxonomy.birthday.key],
      };
      expect(
        EventFilter(
          eventOnly: true,
          eventKinds: {PlaceEventTaxonomy.birthday.key},
        ).matchesDiscovery(doc, now: now, docId: 'p1', eventIndex: ids),
        isTrue,
      );
      expect(
        EventFilter(
          eventOnly: true,
          eventKinds: {PlaceEventTaxonomy.limited.key},
        ).matchesDiscovery(doc, now: now, docId: 'p1', eventIndex: ids),
        isFalse,
      );
    });

    test('다른 업종을 골랐을 때는 이벤트 색인이 아무것도 바꾸지 않는다', () {
      final ids = index([promo(id: 'e1', placeId: 'p1')]);
      // 이벤트가 없는 매장(p2)도 업종 탐색에는 그대로 나온다.
      expect(
        EventFilter(
          categories: {'BAR'},
        ).matchesDiscovery(bar(), now: now, docId: 'p2', eventIndex: ids),
        isTrue,
      );
      expect(
        EventFilter().matchesDiscovery(
          bar(),
          now: now,
          docId: 'p2',
          eventIndex: ids,
        ),
        isTrue,
      );
    });
  });

  // ── 장소대여 목록도 같은 규칙, 다른 색인 ──────────────────────────────
  //
  // 장소대여 탭의 🎪 칸은 **공간 이벤트만** 봐야 한다. 판정은 화면이 아니라
  // [PlaceFilter.matchesEvent]에 있고, 정본은 컬렉션으로 좁힌 색인이다.
  group('장소대여 목록 필터', () {
    PlaceEventIndex rentalIndex(List<PlacePromotion> promotions) =>
        PlaceEventIndex.fromPromotions(
          promotions,
          now: now,
          collection: PlaceEventIndex.rentalCollection,
        );

    test('조건을 켜지 않으면 색인이 없어도 전부 통과한다', () {
      final f = PlaceFilter();
      expect(f.matchesEvent('r1', null), isTrue);
      expect(f.matchesEvent(null, null), isTrue);
    });

    test('공간 이벤트가 있는 장소만 남는다', () {
      final ids = rentalIndex([
        promo(id: 'e1', placeId: 'r1', placeCollection: 'places'),
      ]);
      final f = PlaceFilter(eventOnly: true);
      expect(f.matchesEvent('r1', ids), isTrue);
      expect(f.matchesEvent('r2', ids), isFalse);
    });

    test('매장 이벤트는 장소대여 목록을 통과시키지 못한다', () {
      // 같은 id로 매장 이벤트만 있는 상황 — 색인이 컬렉션으로 갈리므로
      // 장소대여 색인에는 아예 들어오지 않는다.
      final ids = rentalIndex([
        promo(id: 'e1', placeId: 'r1', placeCollection: 'events'),
      ]);
      expect(ids.isEmpty, isTrue);
      expect(PlaceFilter(eventOnly: true).matchesEvent('r1', ids), isFalse);
    });

    test('종료·숨김만 남은 장소는 빠진다', () {
      final ids = rentalIndex([
        promo(
          id: 'ended',
          placeId: 'r1',
          placeCollection: 'places',
          endAt: DateTime(2026, 8, 1),
        ),
        promo(
          id: 'hidden',
          placeId: 'r2',
          placeCollection: 'places',
          isVisible: false,
        ),
      ]);
      final f = PlaceFilter(eventOnly: true);
      expect(f.matchesEvent('r1', ids), isFalse);
      expect(f.matchesEvent('r2', ids), isFalse);
    });

    test('색인을 아직 못 읽었으면 아무것도 남기지 않는다', () {
      // 플레이스 탭과 다른 점 — 여기는 기댈 옛 미러 필드가 없어서, 통과시키면
      // 조건을 안 건 것과 같아진다.
      expect(PlaceFilter(eventOnly: true).matchesEvent('r1', null), isFalse);
    });
  });

  // ── 목록과 지도가 같은 판정을 쓴다 ────────────────────────────────────
  //
  // 예전에는 지도의 🎪 조건이 **플레이스 마커에만** 걸려서, 같은 조건인데
  // 장소대여는 목록에서만 걸러지고 지도에는 전부 남았다. 판정을 한 함수
  // ([PlaceEventIndex.allows])로 모아 두 화면이 그것만 부르게 한다.
  group('🎪 판정은 한 곳에만 있다', () {
    final withR1 = PlaceEventIndex.fromPromotions([
      promo(id: 'e1', placeId: 'r1', placeCollection: 'places'),
    ], now: now, collection: PlaceEventIndex.rentalCollection);

    test('조건을 켜지 않으면 색인과 무관하게 통과한다', () {
      expect(
        PlaceEventIndex.allows(eventOnly: false, docId: 'zzz', index: null),
        isTrue,
      );
    });

    test('켰으면 색인이 정본이고, 색인이 없으면 아무것도 통과하지 못한다', () {
      expect(
        PlaceEventIndex.allows(eventOnly: true, docId: 'r1', index: withR1),
        isTrue,
      );
      expect(
        PlaceEventIndex.allows(eventOnly: true, docId: 'r2', index: withR1),
        isFalse,
      );
      expect(
        PlaceEventIndex.allows(eventOnly: true, docId: 'r1', index: null),
        isFalse,
      );
      expect(
        PlaceEventIndex.allows(eventOnly: true, docId: null, index: withR1),
        isFalse,
      );
    });

    test('목록(PlaceFilter)과 지도(allows)가 모든 경우에 같은 답을 낸다', () {
      for (final eventOnly in [true, false]) {
        for (final index in [withR1, null]) {
          for (final docId in ['r1', 'r2', null]) {
            expect(
              PlaceFilter(eventOnly: eventOnly).matchesEvent(docId, index),
              PlaceEventIndex.allows(
                eventOnly: eventOnly,
                docId: docId,
                index: index,
              ),
              reason: 'eventOnly=$eventOnly index=${index?.length} id=$docId',
            );
          }
        }
      }
    });

    test('지도가 장소대여 마커를 그 판정으로, 공간 이벤트 색인으로 거른다', () {
      // 지도는 네이버 지도 SDK가 필요해 위젯 테스트로 띄울 수 없다 — 대신
      // "판정을 직접 다시 만들지 않았는지"를 소스에서 확인한다.
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      expect(
        src.contains('MapListingKind.rental &&'),
        isTrue,
        reason: '장소대여 마커에 거는 조건이 있어야 한다',
      );
      expect(src.contains('PlaceEventIndex.allows'), isTrue);
      expect(src.contains('index: _rentalEventIndex'), isTrue);
      expect(
        src.contains('collection: PlaceEventIndex.rentalCollection'),
        isTrue,
        reason: '색인은 places 컬렉션으로 만들어야 매장 이벤트가 섞이지 않는다',
      );
    });

    // ── 숨은 필터 상태를 만들지 않는다 ──────────────────────────────────
    //
    // 🎪는 플레이스·장소대여 **양쪽에 걸리는 조건**인데 컨트롤은 플레이스
    // 격자 안에만 있었다 — 플레이스 종류를 끄면 조건은 살아서 장소대여
    // 마커를 계속 거르는데 끌 방법이 사라졌다. 지도는 위젯 테스트로 띄울 수
    // 없어 여기서도 소스로 확인한다.
    test('플레이스를 꺼도 🎪를 끄고 켤 곳이 남는다', () {
      final src = File('lib/screens/map_screen.dart').readAsStringSync();
      expect(
        src.contains('else if (_showsStandaloneEventChip)'),
        isTrue,
        reason: '격자가 안 보일 때 대신 나오는 칩이 있어야 한다',
      );
      // 장소대여를 보고 있거나, 이미 켜져 있으면(= 끌 수 있어야 하면) 보인다.
      expect(
        src.contains(
          '_kinds.contains(MapListingKind.rental) || _placeDiscovery.eventOnly',
        ),
        isTrue,
        reason: '켜 둔 조건을 끌 수 없는 상태가 남으면 안 된다',
      );
      // 칩은 격자 칸과 같은 토글을 쓴다 — 값이 두 갈래로 갈리지 않게.
      expect(src.contains('_placeDiscovery.selectEvent(!on)'), isTrue);
      // 종류를 바꿀 때 조건을 자동으로 끄지 않는다(이 화면의 기존 규칙).
      final onKindsChanged = src.substring(
        src.indexOf('void _onKindsChanged('),
        src.indexOf('Future<void> _searchThisArea()'),
      );
      expect(
        onKindsChanged.contains('selectEvent') ||
            onKindsChanged.contains('eventOnly'),
        isFalse,
        reason: '종류 칩이 이벤트 조건을 건드리면 안 된다',
      );
    });
  });

  // ── 이벤트는 저장되는 업종이 아니다 ───────────────────────────────────
  group('업종 격자 안의 특수 항목', () {
    Future<EventFilter> pumpExplorer(WidgetTester tester) async {
      final filter = EventFilter();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => PlaceCategoryExplorer(
                filter: filter,
                onChanged: () => setState(() {}),
              ),
            ),
          ),
        ),
      );
      return filter;
    }

    /// 드릴다운 층의 머리 — '‹ 🎪 매장 이벤트'.
    final drillHead =
        '${PlaceEventTaxonomy.categoryEmoji} '
        '${PlaceEventTaxonomy.categoryLabel}';

    testWidgets('🎪 이벤트가 업종 칸들과 같은 격자에 있다', (tester) async {
      await pumpExplorer(tester);
      expect(find.text('전체'), findsOneWidget);
      expect(find.text('푸드'), findsOneWidget);
      // 칸이 좁아 격자에서는 축약 표기를 쓴다(이모지가 파티와 갈라 준다).
      expect(
        find.text(PlaceEventTaxonomy.categoryShortLabel),
        findsOneWidget,
      );
    });

    testWidgets('누르면 이벤트 조건만 켜진다 — 업종은 건드리지 않는다', (tester) async {
      final filter = await pumpExplorer(tester);
      await tester.tap(find.text(PlaceEventTaxonomy.categoryShortLabel));
      await tester.pumpAndSettle();

      expect(filter.eventOnly, isTrue);
      expect(filter.categories, isEmpty);
      // 켠 뒤에는 같은 자리가 이벤트 갈래 줄로 바뀐다(업종을 골랐을 때와 같다).
      // 자리가 생기므로 여기서는 정식 이름 '🎪 매장 이벤트'가 뜬다.
      expect(find.text(drillHead), findsOneWidget);
      expect(find.text(PlaceEventTaxonomy.birthday.shortLabel), findsOneWidget);
    });

    testWidgets('다른 업종을 고르면 이벤트가 꺼진다 — 칸은 한 번에 하나', (tester) async {
      final filter = await pumpExplorer(tester);
      await tester.tap(find.text(PlaceEventTaxonomy.categoryShortLabel));
      await tester.pumpAndSettle();
      // '‹ 🎪 매장 이벤트'로 되돌아온 뒤 업종을 고른다.
      await tester.tap(find.text(drillHead));
      await tester.pumpAndSettle();
      await tester.tap(find.text('푸드'));
      await tester.pumpAndSettle();

      expect(filter.eventOnly, isFalse);
      expect(filter.categories, isNotEmpty);
    });

    test('이벤트 칸 값은 업종 저장값과 겹치지 않는다', () {
      expect(PlaceTaxonomy.byLabel(PlaceEventTaxonomy.categoryLabel), isNull);
      expect(
        PlaceTaxonomy.all.map((c) => c.label),
        isNot(contains(PlaceCategoryExplorer.eventValue)),
      );
    });

    test('이벤트를 켜도 placeCategory 조건을 쓰지 않는다', () {
      final f = EventFilter(categories: {'BAR'})..selectEvent(true);
      expect(f.eventOnly, isTrue);
      expect(f.categories, isEmpty, reason: '화면에서만 배타적이다');

      // 반대 방향 — 업종을 고르면 이벤트가 꺼진다(칸은 한 번에 하나).
      f.selectCategory('클럽');
      expect(f.eventOnly, isFalse);
      expect(f.categories, {'클럽'});
    });
  });

  // ── 서버 쿼리의 전제 ──────────────────────────────────────────────────
  // 색인은 `placePromotions`를 `isVisible == true`로 **서버에서** 거른 결과를
  // 받는다([PlacePromotionService.watchPublicAll]). Firestore의 등호 필터는
  // 필드가 아예 없는 문서를 제외하므로, 저장 경로가 이 필드를 빠뜨리는 순간
  // 이벤트가 조용히 사라진다. 그 전제를 여기서 못 박아 둔다.
  test('저장 형식에는 isVisible이 항상 들어간다', () {
    for (final visible in [true, false]) {
      final map = promo(id: 'e1', placeId: 'p1', isVisible: visible).toMap();
      expect(map.containsKey('isVisible'), isTrue);
      expect(map['isVisible'], visible);
    }
  });

  // 미러(본체 문서)와 정본(프로모션)이 같은 사실을 말하는지 — 색인이 정본을
  // 보고, 카드의 '🎪 이벤트 진행중' 배지는 미러를 보므로 둘이 갈리면 배지 없는
  // 카드가 이벤트 목록에 뜬다.
  test('보여줄 이벤트가 있으면 미러도 이벤트 태그를 켠다', () {
    final live = [promo(id: 'e1', placeId: 'p1')];
    expect(PlaceEventIndex.fromPromotions(live, now: now).has('p1'), isTrue);

    final mirror = PlaceEventTaxonomy.mirrorFrom(live, now);
    expect(mirror.kinds, isNotEmpty);
    expect(
      PlaceEventTaxonomy.isRunningAt({
        'themeTags': [ListingConstants.placeEventTag],
        PlaceEventTaxonomy.kindsField: mirror.kinds.toList(),
        if (mirror.endsAt != null)
          PlaceEventTaxonomy.endsAtField: Timestamp.fromDate(mirror.endsAt!),
      }, now),
      isTrue,
    );
  });
}

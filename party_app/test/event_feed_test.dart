// 🎉🎪 파티츄/이벤트 탭의 표시용 피드([EventFeed])가 지키는 것.
//
//   ① 전체는 세 종류(파티 · 매장 이벤트 · 공간 이벤트)를 한 목록에 세우고,
//      위 세그먼트는 그 목록을 좁히기만 한다.
//   ② 같은 것이 같은 목록에 두 번 뜨지 않는다 — 같은 열쇠는 덮어쓰기다.
//      (한 원본의 이벤트 여러 건은 [EventFeed.build]가 한 칸에 모으지만, 그
//      묶음은 중간 결과다 — 화면에 서는 카드는 [EventFeed.expandEvents]가 편
//      이벤트 한 건씩이고 이는 전체 칸/이벤트 칸이 같다.)
//   ③ 매장 이벤트와 공간 이벤트가 서로의 원본을 집지 않는다.
//   ④ 숨김·종료 이벤트와, 목록에 없는 원본의 이벤트는 빠진다.
//   ⑤ 정본을 합치거나 변환하지 않는다 — 칸이 들고 있는 것은 원본 문서다.

import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/event_feed.dart';
import 'package:party_app/models/place_promotion.dart';

PlacePromotion _promo({
  required String id,
  required String placeId,
  required String collection,
  String title = '이벤트',
  bool visible = true,
  DateTime? startAt,
  DateTime? endAt,
  int sortOrder = 0,
}) => PlacePromotion(
  id: id,
  placeId: placeId,
  placeCollection: collection,
  hostId: 'host',
  title: title,
  description: '',
  imageUrl: '',
  tags: const [],
  audience: '',
  startAt: startAt,
  endAt: endAt,
  isVisible: visible,
  linkedProductIds: const [],
  sortOrder: sortOrder,
);

void main() {
  final now = DateTime(2026, 8, 30, 20);
  DateTime? partyStart(Map<String, dynamic> p) => p['at'] as DateTime?;

  List<EventFeedItem> build({
    Map<String, Map<String, dynamic>> parties = const {},
    Map<String, Map<String, dynamic>> venues = const {},
    Map<String, Map<String, dynamic>> rentals = const {},
    List<PlacePromotion> promotions = const [],
  }) => EventFeed.build(
    parties: parties,
    venues: venues,
    rentals: rentals,
    promotions: promotions,
    partyStartAt: partyStart,
    now: now,
  );

  /// 파티 하나 · 매장 이벤트 하나 · 공간 이벤트 하나.
  List<EventFeedItem> threeKinds() => build(
    parties: {
      'p1': {'at': now.add(const Duration(hours: 2))},
    },
    venues: {
      'v1': {'name': '혼술바'},
    },
    rentals: {
      'r1': {'name': '루프탑 파티룸'},
    },
    promotions: [
      _promo(id: 'm1', placeId: 'v1', collection: 'events', title: '수요일 DJ'),
      _promo(id: 'm2', placeId: 'r1', collection: 'places', title: '가을 대관전'),
    ],
  );

  group('전체 / 파티 / 이벤트', () {
    test('전체에는 세 종류가 함께 선다', () {
      final items = threeKinds();

      expect(items.length, 3);
      expect(items.map((i) => i.kind).toSet(), {
        EventFeedKind.party,
        EventFeedKind.placeEvent,
        EventFeedKind.rentalEvent,
      });
      expect(EventFeed.countOf(items, EventFeedFilter.all), 3);
    });

    test('파티 칸에는 파티만 남는다', () {
      final only = EventFeed.where(threeKinds(), EventFeedFilter.party);
      expect(only.length, 1);
      expect(only.single, isA<PartyFeedItem>());
      expect(only.single.kind, EventFeedKind.party);
    });

    test('이벤트 칸에는 매장 이벤트와 공간 이벤트만 남는다', () {
      final only = EventFeed.where(threeKinds(), EventFeedFilter.event);
      expect(only.length, 2);
      expect(only.every((i) => i is VenueEventFeedItem), isTrue);
      expect(only.map((i) => i.kind).toSet(), {
        EventFeedKind.placeEvent,
        EventFeedKind.rentalEvent,
      });
    });

    test('세그먼트가 무엇을 그릴지 말해 준다', () {
      expect(EventFeedFilter.all.showsParties, isTrue);
      expect(EventFeedFilter.all.showsEvents, isTrue);
      expect(EventFeedFilter.party.showsParties, isTrue);
      expect(EventFeedFilter.party.showsEvents, isFalse);
      expect(EventFeedFilter.event.showsParties, isFalse);
      expect(EventFeedFilter.event.showsEvents, isTrue);
    });

    test('배지는 세 종류를 갈라 부른다', () {
      expect(EventFeedKind.party.badge, '🎉 파티');
      expect(EventFeedKind.placeEvent.badge, '✨ 매장 이벤트');
      expect(EventFeedKind.rentalEvent.badge, '✨ 공간 이벤트');
    });
  });

  group('중복 노출 없음', () {
    // [build]의 묶음은 화면 목록이 아니라 **중간 결과**다 — 원본 안에서
    // 곧 열리는 순서를 세우는 자리. 화면에 서는 카드는
    // [EventFeed.expandEvents]가 편 이벤트 한 건씩이다(아래 테스트).
    test('한 원본에 이벤트가 여러 건이면 한 칸에 곧 열리는 순서로 담긴다', () {
      final items = build(
        venues: {
          'v1': {'name': '혼술바'},
        },
        promotions: [
          _promo(
            id: 'm1',
            placeId: 'v1',
            collection: 'events',
            title: '수요일 DJ',
            sortOrder: 0,
          ),
          _promo(
            id: 'm2',
            placeId: 'v1',
            collection: 'events',
            title: '시음회',
            sortOrder: 1,
          ),
          _promo(
            id: 'm3',
            placeId: 'v1',
            collection: 'events',
            title: '시즌 행사',
            sortOrder: 2,
          ),
        ],
      );

      expect(items.length, 1);
      final item = items.single as VenueEventFeedItem;
      expect(item.placeId, 'v1');
      expect(item.promotions.length, 3);
      expect(item.promotions.map((p) => p.title), [
        '수요일 DJ',
        '시음회',
        '시즌 행사',
      ]);
      // 묶인 칸은 이벤트 하나를 가리키지 않는다 — 화면에 그대로 서지 않는다.
      expect(item.eventId, isNull);
    });

    test('화면에 서는 것은 편 목록 — 이벤트 3건이면 카드도 3장', () {
      final items = build(
        venues: {
          'v1': {'name': '혼술바'},
        },
        promotions: [
          _promo(id: 'm1', placeId: 'v1', collection: 'events', title: '수요일 DJ'),
          _promo(
            id: 'm2',
            placeId: 'v1',
            collection: 'events',
            title: '시음회',
            sortOrder: 1,
          ),
          _promo(
            id: 'm3',
            placeId: 'v1',
            collection: 'events',
            title: '시즌 행사',
            sortOrder: 2,
          ),
        ],
      );

      final cards = EventFeed.expandEvents(
        items,
        now: now,
      ).cast<VenueEventFeedItem>();
      expect(cards.length, 3);
      expect(cards.map((c) => c.promotions.single.title), [
        '수요일 DJ',
        '시음회',
        '시즌 행사',
      ]);
      // 카드마다 열쇠가 다르다 — 같은 매장이어도 겹치지 않는다.
      expect(cards.map((c) => c.key).toSet().length, 3);
    });

    test('열쇠는 종류마다 달라, 셋이 서로를 덮어쓰지 않는다', () {
      // id가 셋 다 'x'여도 카드는 셋이다.
      final items = build(
        parties: {
          'x': {'at': now},
        },
        venues: {
          'x': {'name': '혼술바'},
        },
        rentals: {
          'x': {'name': '파티룸'},
        },
        promotions: [
          _promo(id: 'm1', placeId: 'x', collection: 'events'),
          _promo(id: 'm2', placeId: 'x', collection: 'places'),
        ],
      );

      expect(items.length, 3);
      expect(items.map((i) => i.key).toSet().length, 3);
    });
  });

  group('두 이벤트 정본이 섞이지 않는다', () {
    test('매장 이벤트는 매장 원본에만, 공간 이벤트는 공간 원본에만 붙는다', () {
      final items = build(
        venues: {
          'v1': {'name': '혼술바'},
        },
        rentals: {
          'r1': {'name': '파티룸'},
        },
        promotions: [
          _promo(id: 'm1', placeId: 'v1', collection: 'events'),
          _promo(id: 'm2', placeId: 'r1', collection: 'places'),
        ],
      );

      final byKind = {for (final i in items) i.kind: i as VenueEventFeedItem};
      expect(byKind[EventFeedKind.placeEvent]!.placeId, 'v1');
      expect(byKind[EventFeedKind.rentalEvent]!.placeId, 'r1');
    });

    test('컬렉션이 반대면 원본을 찾지 못해 빠진다', () {
      // 매장 이벤트인데 원본은 장소대여 쪽에만 있다 → 어느 쪽에도 안 걸린다.
      final items = build(
        rentals: {
          'r1': {'name': '파티룸'},
        },
        promotions: [_promo(id: 'm1', placeId: 'r1', collection: 'events')],
      );
      expect(items, isEmpty);
    });
  });

  group('노출 판정', () {
    test('숨김·종료·목록에 없는 원본의 이벤트는 빠진다', () {
      final items = build(
        venues: {
          'v1': {'name': '혼술바'},
        },
        rentals: {
          'r1': {'name': '파티룸'},
        },
        promotions: [
          _promo(
            id: 'hidden',
            placeId: 'v1',
            collection: 'events',
            visible: false,
          ),
          _promo(
            id: 'ended',
            placeId: 'r1',
            collection: 'places',
            endAt: now.subtract(const Duration(days: 2)),
          ),
          // 목록에 없는(숨김·삭제된) 원본 — 눌러 갈 곳이 없다.
          _promo(id: 'gone', placeId: 'v9', collection: 'events'),
        ],
      );

      expect(items, isEmpty);
    });
  });

  group('원본을 그대로 들고 있다', () {
    test('합치거나 변환하지 않는다', () {
      final party = {'at': now, 'title': '와인 모임'};
      final venue = {'name': '루프탑 바', 'placeCategory': 'BAR'};
      final rental = {'name': '한강 파티룸'};
      final items = build(
        parties: {'p1': party},
        venues: {'v1': venue},
        rentals: {'r1': rental},
        promotions: [
          _promo(id: 'm1', placeId: 'v1', collection: 'events', title: '시음회'),
          _promo(id: 'm2', placeId: 'r1', collection: 'places', title: '대관전'),
        ],
      );

      final p = items.whereType<PartyFeedItem>().single;
      expect(identical(p.party, party), isTrue);

      final venueItem = items
          .whereType<VenueEventFeedItem>()
          .firstWhere((i) => i.kind == EventFeedKind.placeEvent);
      expect(identical(venueItem.place, venue), isTrue);
      expect(venueItem.promotions.single.id, 'm1');

      final rentalItem = items
          .whereType<VenueEventFeedItem>()
          .firstWhere((i) => i.kind == EventFeedKind.rentalEvent);
      expect(identical(rentalItem.place, rental), isTrue);
      expect(rentalItem.promotions.single.id, 'm2');
    });
  });

  test('곧 열리는 것부터 — 진행 중은 맨 뒤로 밀리지 않는다', () {
    final items = build(
      parties: {
        'late': {'at': now.add(const Duration(days: 7))},
        'soon': {'at': now.add(const Duration(hours: 1))},
      },
      venues: {
        'v1': {'name': '혼술바'},
      },
      // 이미 시작한 이벤트 — 기준 시각으로 끌어올려 맨 앞에 선다.
      promotions: [
        _promo(
          id: 'm1',
          placeId: 'v1',
          collection: 'events',
          startAt: now.subtract(const Duration(days: 3)),
        ),
      ],
    );

    expect(items.map((i) => i.key).toList(), [
      'events:v1',
      'party:soon',
      'party:late',
    ]);
  });
}

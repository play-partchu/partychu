// 🎊 공공 축제(publicEvents)가 이벤트 피드에 합쳐지는 규칙.
//
//   · 파티츄 이벤트 칸은 그대로 남고, 공공 축제는 자기 칸(PublicEventFeedItem)으로
//     선다 — 사용자 등록 이벤트 모양으로 옮겨 적지 않는다.
//   · 순서는 "곧 볼 수 있는 것부터" — 진행 중이 앞, 같은 시각이면 파티츄
//     이벤트가 먼저, 공공 축제끼리는 곧 끝나는 것부터.
//   · 숨김·종료는 빠지고, 같은 문서가 두 번 와도 한 칸이다.
//   · ✨ 이벤트 칸에 들어가고 🎉 파티 칸에는 들어가지 않는다.

import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/models/event_feed.dart';
import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/models/public_event.dart';
import 'package:party_app/widgets/public_event_card.dart';

final now = DateTime(2026, 9, 19, 18);

PublicEvent pub(
  String id,
  DateTime start,
  DateTime end, {
  bool visible = true,
  String startDate = '20260918',
  String endDate = '20260920',
}) => PublicEvent(
  id: id,
  source: 'tourapi',
  sourceId: id,
  title: '축제 $id',
  startAt: start,
  endAt: end,
  startDate: startDate,
  endDate: endDate,
  attribution: '한국관광공사',
  status: 'active',
  isVisible: visible,
);

List<EventFeedItem> venueItems() => EventFeed.expandEvents(
  EventFeed.build(
    parties: const {},
    venues: {
      'v1': {'name': '매장'},
    },
    rentals: const {},
    promotions: [
      PlacePromotion.fromMap('p-ongoing', {
        'placeId': 'v1',
        'placeCollection': 'events',
        'title': '진행 중 매장 이벤트',
        'isVisible': true,
        'startAt': DateTime(2026, 9, 1),
        'endAt': DateTime(2026, 9, 30),
      }),
      PlacePromotion.fromMap('p-later', {
        'placeId': 'v1',
        'placeCollection': 'events',
        'title': '다음 주 매장 이벤트',
        'isVisible': true,
        'startAt': DateTime(2026, 9, 25),
        'endAt': DateTime(2026, 9, 27),
      }),
    ],
    partyStartAt: (_) => null,
    now: now,
  ),
  now: now,
);

void main() {
  test('파티츄 이벤트와 공공 축제가 한 순서로 선다', () {
    final merged = EventFeed.withPublicEvents(venueItems(), [
      pub('later', DateTime(2026, 10, 1), DateTime(2026, 10, 3)),
      pub('ongoingLong', DateTime(2026, 5, 1), DateTime(2026, 12, 1)),
      pub('ongoingShort', DateTime(2026, 9, 18), DateTime(2026, 9, 20)),
      pub('soon', DateTime(2026, 9, 21), DateTime(2026, 9, 22)),
    ], now: now);
    String label(EventFeedItem i) => switch (i) {
      PublicEventFeedItem() => i.event.id,
      VenueEventFeedItem() => i.promotions.single.id,
      PartyFeedItem() => 'party',
    };
    expect(merged.map(label), [
      'p-ongoing', // 진행 중 — 파티츄 이벤트가 먼저
      'ongoingShort', // 진행 중 공공 축제 — 곧 끝나는 것부터
      'ongoingLong',
      'soon',
      'p-later',
      'later',
    ]);
  });

  test('숨김·종료는 빠지고 같은 문서는 한 칸이다', () {
    final merged = EventFeed.withPublicEvents(const [], [
      pub('a', DateTime(2026, 9, 18), DateTime(2026, 9, 20)),
      pub('a', DateTime(2026, 9, 18), DateTime(2026, 9, 20)),
      pub('hidden', DateTime(2026, 9, 18), DateTime(2026, 9, 20), visible: false),
      pub('ended', DateTime(2026, 9, 1), DateTime(2026, 9, 18)),
    ], now: now);
    expect(merged.map((i) => i.key), ['public:a']);
  });

  test('공공 축제는 ✨ 이벤트 칸에 들어가고 🎉 파티 칸에는 없다', () {
    final merged = EventFeed.withPublicEvents(const [], [
      pub('a', DateTime(2026, 9, 18), DateTime(2026, 9, 20)),
    ], now: now);
    expect(EventFeed.where(merged, EventFeedFilter.event).length, 1);
    expect(EventFeed.where(merged, EventFeedFilter.party), isEmpty);
    expect(EventFeedKind.publicFestival.badge, '🎊 공공 축제');
    expect(EventFeedKind.publicFestival.isEvent, isTrue);
    // 컬렉션으로 갈라 담는 목록에는 들어가지 않는다(placePromotions 전용).
    expect(EventFeedKind.events.contains(EventFeedKind.publicFestival), isFalse);
  });

  test('📅 고른 날에 기간이 걸치는지', () {
    final e = pub('a', DateTime(2026, 9, 18), DateTime(2026, 9, 20, 23, 59));
    expect(e.overlapsDay(DateTime(2026, 9, 18)), isTrue);
    expect(e.overlapsDay(DateTime(2026, 9, 20)), isTrue);
    expect(e.overlapsDay(DateTime(2026, 9, 21)), isFalse);
    expect(e.overlapsDay(DateTime(2026, 9, 17)), isFalse);
  });

  test('카드 문구 — 지역·기간', () {
    expect(
      publicEventAreaLabel('서울특별시 강동구 올림픽로 875 (암사동)'),
      '서울 강동구',
    );
    expect(
      publicEventAreaLabel('경기도 고양시 일산동구 호수로 595 (장항동)'),
      '경기 고양시 일산동구',
    );
    expect(publicEventAreaLabel(null), '');
    final e = pub('a', now, now, startDate: '20261016', endDate: '20261018');
    expect(publicEventPeriodLabel(e, now: now), '10.16 ~ 10.18');
    final one = pub('b', now, now, startDate: '20260920', endDate: '20260920');
    expect(publicEventPeriodLabel(one, now: now), '9.20');
    final cross = pub('c', now, now, startDate: '20261228', endDate: '20270103');
    expect(publicEventPeriodLabel(cross, now: now), '2026.12.28 ~ 2027.1.3');
  });
}

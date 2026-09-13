// ✨ 이벤트 카드는 **이벤트 중심**이고, 어느 칸에서 봐도 **같은 카드**다.
//
// 예전에는 카드 본문이 원본 매장/공간이었다. 큰 제목은 '내잔 혼술바', 사진은
// 매장 대표 사진이고, 정작 이벤트 제목은 카드 위 배지 줄에 작게 붙는 곁가지였다
// — 이벤트를 찾으러 온 사람에게 이벤트가 가장 약하게 보였다. 그 뒤 ✨ 이벤트
// 칸만 이벤트 중심 카드로 바꿨는데, 이번엔 **같은 이벤트가 칸에 따라 다르게**
// 보였다: 전체 칸에서는 매장 사진에 매장 이름, 이벤트 두 건은 '외 1건'으로
// 접혀 한 장. 지금은 두 칸이 같은 목록·같은 카드를 쓴다.
//
// 이 파일이 붙잡는 것 다섯.
//   ① 대표 미디어는 **그 이벤트의 정본**에서 나온다(placePromotions의 cover
//      필드). 판정 함수는 파티·플레이스와 공유하는 [getPartyCoverMedia] 하나다.
//   ② 사진과 제목이 **같은 한 건**에서 나온다 — 한 매장이 이벤트를 여럿 열어도
//      A의 사진에 B의 제목이 붙지 않는다.
//   ③ 매장 이벤트(events)와 공간 이벤트(places)가 같은 규칙을 쓴다.
//   ④ 전체 칸과 ✨ 이벤트 칸이 **같은 단위·같은 카드**를 쓴다 — 칸에 따른
//      변환·그룹핑·별도 카드가 남아 있지 않다.
//   ⑤ 파티 카드 규칙은 **그대로다** — 바뀐 것은 이벤트뿐이다.
//
// ①~③은 순수 계산이라 값으로 확인하고, 화면 배선(어느 칸에서 어느 카드를
// 그리는지)은 소스 가드로 확인한다 — 카드는 Firebase 없이 그릴 수 없다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/event_feed.dart';
import 'package:party_app/models/place_event_index.dart';
import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/utils/party_utils.dart';

String _src(String path) => File(path).readAsStringSync();

/// 줄바꿈·들여쓰기를 지운 소스 — 배선만 보고 서식은 보지 않는다.
String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

PlacePromotion _promo({
  required String id,
  required String placeId,
  String collection = PlaceEventIndex.placeCollection,
  String title = '이벤트',
  DateTime? startAt,
  int sortOrder = 0,
  String? coverMediaType,
  String? coverImageUrl,
  String? coverVideoUrl,
  String? coverVideoUid,
  String? coverThumbnailUrl,
  List<String> imageUrls = const [],
  String? videoUrl,
  String? videoThumbnailUrl,
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
  endAt: null,
  isVisible: true,
  linkedProductIds: const [],
  sortOrder: sortOrder,
  imageUrls: imageUrls,
  videoUrl: videoUrl,
  videoThumbnailUrl: videoThumbnailUrl,
  coverMediaType: coverMediaType,
  coverImageUrl: coverImageUrl,
  coverVideoUrl: coverVideoUrl,
  coverVideoUid: coverVideoUid,
  coverThumbnailUrl: coverThumbnailUrl,
);

/// 카드가 하는 것과 **같은 계산** — 이벤트 하나의 대표 미디어.
PartyCoverMedia? _coverOf(PlacePromotion p) =>
    getPartyCoverMedia(p.coverMediaMap, tag: 'test');

void main() {
  final now = DateTime(2026, 8, 31, 20);

  // ── ① 이벤트 정본에서 대표 미디어가 나온다 ───────────────────────────
  group('대표 미디어는 그 이벤트의 정본에서 나온다', () {
    test('사진을 대표로 지정한 이벤트 → 그 사진', () {
      final cover = _coverOf(
        _promo(
          id: 'e1',
          placeId: 'p1',
          coverMediaType: 'image',
          coverImageUrl: 'event-cover.jpg',
          imageUrls: const ['other.jpg', 'event-cover.jpg'],
        ),
      );
      expect(cover?.isVideo, isFalse);
      expect(cover?.imageUrl, 'event-cover.jpg');
      // 카드가 실제로 그리는 값(썸네일)도 그 사진이다.
      expect(cover?.thumbnailUrl, 'event-cover.jpg');
    });

    test('영상을 대표로 지정한 이벤트 → 영상 + 그 영상의 썸네일', () {
      final cover = _coverOf(
        _promo(
          id: 'e2',
          placeId: 'p1',
          coverMediaType: 'video',
          coverVideoUrl: 'event.m3u8',
          coverVideoUid: 'uid-2',
          coverThumbnailUrl: 'event-thumb.jpg',
          imageUrls: const ['photo.jpg'],
        ),
      );
      expect(cover?.isVideo, isTrue);
      expect(cover?.videoUrl, 'event.m3u8');
      expect(cover?.videoUid, 'uid-2');
      expect(cover?.thumbnailUrl, 'event-thumb.jpg');
    });

    test('대표 지정이 없는 구형 이벤트 → 기존 하위호환 규칙(첫 사진)', () {
      final cover = _coverOf(
        _promo(
          id: 'e3',
          placeId: 'p1',
          imageUrls: const ['old1.jpg', 'old2.jpg'],
        ),
      );
      expect(cover?.isVideo, isFalse);
      expect(cover?.imageUrl, 'old1.jpg');
    });

    test('사진 없이 영상만 있던 구형 이벤트 → 영상이 대표(기존 규칙 그대로)', () {
      final cover = _coverOf(
        _promo(
          id: 'e4',
          placeId: 'p1',
          videoUrl: 'legacy.m3u8',
          videoThumbnailUrl: 'legacy-thumb.jpg',
        ),
      );
      expect(cover?.isVideo, isTrue);
      expect(cover?.videoUrl, 'legacy.m3u8');
      expect(cover?.thumbnailUrl, 'legacy-thumb.jpg');
    });

    test('미디어가 하나도 없는 이벤트 → null(카드가 원본 사진으로 되돌아간다)', () {
      expect(_coverOf(_promo(id: 'e5', placeId: 'p1')), isNull);
    });
  });

  // ── ② 사진과 제목이 같은 한 건에서 나온다 ────────────────────────────
  group('한 매장이 이벤트를 여럿 열어도 사진과 제목이 어긋나지 않는다', () {
    // 같은 매장의 두 이벤트 — 늦게 시작하는 쪽을 **먼저** 넣어 둔다.
    final late$ = _promo(
      id: 'late',
      placeId: 'p1',
      title: '늦게 여는 이벤트',
      startAt: now.add(const Duration(days: 3)),
      coverMediaType: 'image',
      coverImageUrl: 'late.jpg',
    );
    final soon = _promo(
      id: 'soon',
      placeId: 'p1',
      title: '오늘 밤 위스키 한 잔 무료 · 9월 한 달 내내 진행하는 가을맞이 이벤트',
      startAt: now.add(const Duration(hours: 2)),
      coverMediaType: 'image',
      coverImageUrl: 'soon.jpg',
    );

    final items = EventFeed.build(
      parties: const {},
      venues: {
        'p1': {'name': '내잔 혼술바', 'location': '서울 광진구 화양동'},
      },
      rentals: const {},
      promotions: [late$, soon],
      partyStartAt: (_) => null,
      now: now,
    );

    test('[build]의 묶음은 중간 결과다 — 화면에 그대로 서지 않는다', () {
      expect(items.length, 1);
      final item = items.single as VenueEventFeedItem;
      expect(item.promotions.length, 2);
      // 묶인 칸은 이벤트 하나를 가리키지 않는다.
      expect(item.eventId, isNull);
    });

    // 화면 목록 — **이벤트 한 건이 카드 한 장**이다(전체 칸도 ✨ 칸도 같다).
    final expanded = EventFeed.expandEvents(
      items,
      now: now,
    ).cast<VenueEventFeedItem>();

    test('이벤트 2건이면 카드도 2장이다', () {
      expect(expanded.length, 2);
      // 곧 열리는 것이 먼저.
      expect(expanded.map((i) => i.promotions.single.id), ['soon', 'late']);
      // 한 장이 한 건만 들고 있으니 '외 N건'이라는 말이 없다.
      expect(expanded.every((i) => i.promotions.length == 1), isTrue);
    });

    test('카드마다 열쇠가 다르다 — 같은 매장이어도 두 칸이 겹치지 않는다', () {
      expect(expanded.map((i) => i.key).toSet().length, 2);
      expect(expanded.first.key, contains('#soon'));
      expect(expanded.first.eventId, 'soon');
    });

    test('카드마다 제목과 사진이 자기 이벤트의 것이다 — 서로 바뀌지 않는다', () {
      final soonCard = expanded.firstWhere(
        (i) => i.promotions.single.id == 'soon',
      );
      final lateCard = expanded.firstWhere(
        (i) => i.promotions.single.id == 'late',
      );
      expect(soonCard.promotions.single.title, startsWith('오늘 밤 위스키 한 잔 무료'));
      expect(_coverOf(soonCard.promotions.single)?.imageUrl, 'soon.jpg');
      expect(lateCard.promotions.single.title, '늦게 여는 이벤트');
      expect(_coverOf(lateCard.promotions.single)?.imageUrl, 'late.jpg');
    });

    test('펼쳐도 원본 문서는 그대로 달려 있다 — 매장명·이동 경로가 살아 있다', () {
      for (final card in expanded) {
        expect(card.placeId, 'p1');
        expect(card.place['name'], '내잔 혼술바');
      }
    });
  });

  // ── ③ 매장 이벤트 · 공간 이벤트가 같은 규칙 ──────────────────────────
  test('매장 이벤트와 공간 이벤트가 같은 규칙을 쓴다', () {
    final venueEvent = _promo(
      id: 'v1',
      placeId: 'shop',
      collection: PlaceEventIndex.placeCollection,
      title: '매장 이벤트 제목',
      coverMediaType: 'image',
      coverImageUrl: 'shop-event.jpg',
    );
    final rentalEvent = _promo(
      id: 'r1',
      placeId: 'space',
      collection: PlaceEventIndex.rentalCollection,
      title: '공간 이벤트 제목',
      coverMediaType: 'video',
      coverVideoUrl: 'space.m3u8',
      coverThumbnailUrl: 'space-thumb.jpg',
    );

    final items = EventFeed.build(
      parties: const {},
      venues: {
        'shop': {'name': '내잔 혼술바'},
      },
      rentals: {
        'space': {'name': '한강 뷰 파티룸'},
      },
      promotions: [venueEvent, rentalEvent],
      partyStartAt: (_) => null,
      now: now,
    ).cast<VenueEventFeedItem>();

    final byKind = {for (final i in items) i.kind: i};
    expect(byKind.keys.toSet(), {
      EventFeedKind.placeEvent,
      EventFeedKind.rentalEvent,
    });

    final shop = byKind[EventFeedKind.placeEvent]!.promotions.first;
    expect(shop.title, '매장 이벤트 제목');
    expect(_coverOf(shop)?.imageUrl, 'shop-event.jpg');

    final space = byKind[EventFeedKind.rentalEvent]!.promotions.first;
    expect(space.title, '공간 이벤트 제목');
    expect(_coverOf(space)?.isVideo, isTrue);
    expect(_coverOf(space)?.thumbnailUrl, 'space-thumb.jpg');
  });

  // ── ④ 화면 배선 ──────────────────────────────────────────────────────
  group('전체 칸과 ✨ 이벤트 칸이 같은 이벤트 카드를 쓴다', () {
    final section = _flat(_src('lib/widgets/main/event_feed_section.dart'));
    final main = _flat(_src('lib/screens/main_screen.dart'));

    test('이벤트를 그리는 카드는 한 종류뿐 — 칸에 따른 분기가 없다', () {
      expect(section.contains('PlaceEventCompactCard('), isTrue);
      // 칸을 갈라 원본 카드로 되돌리던 자리가 없어야 한다.
      expect(section.contains('PlaceCompactCard('), isFalse);
      expect(section.contains('eventFocused'), isFalse);
    });

    test('카드에 넘기는 것은 이벤트 한 건이다 — 맵을 따로 만들지 않는다', () {
      expect(
        section.contains(
          'final lead = item.promotions.isEmpty ? null : item.promotions.first;',
        ),
        isTrue,
      );
      expect(section.contains('promotion: lead,'), isTrue);
    });

    test('두 화면 폭이 같은 위젯을 같은 인자로 쓴다', () {
      // 좁은 화면·넓은 화면 둘 다. 칸에 따라 넘기는 값은 머리글뿐이다.
      expect('EventFeedSection('.allMatches(main).length, 2);
      expect(
        'showHeader: _feedFilter.showsParties,'.allMatches(main).length,
        2,
      );
      expect(main.contains('eventFocused'), isFalse);
    });

    test('유형 구분은 카드 밖이 아니라 카드 안에 있다', () {
      // ✨ 매장 이벤트 / ✨ 공간 이벤트 구분 자체는 그대로다 — 자리만 옮겼다.
      expect(
        'eventSourceBadge: item.kind.badge,'.allMatches(section).length,
        1,
      );
      // 카드 위에 유형 배지를 다시 그리던 줄은 없다 — 같은 뜻이 위아래로
      // 두 번 보이던 자리다.
      expect(section.contains('_badge(item),'), isFalse);
      // 카드 위 보조 줄('제목 외 N건 · 시간')도 없다 — 제목·시간은 전부 카드
      // 본문에 있고, '외 N건'이라는 묶음 자체가 사라졌다.
      expect(section.contains('_eventNote'), isFalse);
      expect(section.contains('extraCount'), isFalse);
    });

    test('카드 안 배지는 ① 이벤트 유형 → ② 장소 카테고리 순으로 만들어진다', () {
      final card = _flat(_src('lib/widgets/place_card_widget.dart'));
      // '✨ 이벤트 진행중' 상태칩은 이벤트 목록에서만 빠진다 —
      // 문구는 [ListingConstants]의 표기표 하나를 그대로 거친다.
      expect(
        card.contains(
          'final drop = eventSourceBadge == null ? null : '
          '_placeEventStatusBadge;',
        ),
        isTrue,
      );
      // 배지 **생성 순서 자체**가 ① 이벤트 유형 → ② 장소 카테고리다.
      // Wrap의 자식 순서가 곧 이 목록 순서라, 좁은 화면에서 배지가 다음 줄로
      // 접혀도 첫 줄 첫 칸은 언제나 이벤트 유형이다(화면에서 우연히 앞서는
      // 것이 아니다).
      final eventTypeAt = card.indexOf(
        'if (eventSourceBadge != null) _placeMiniBadge(eventSourceBadge),',
      );
      final categoryAt = card.indexOf(
        'if (info.type.isNotEmpty && info.type != drop) '
        '_placeMiniBadge(info.type),',
      );
      expect(eventTypeAt, isNonNegative);
      expect(categoryAt, isNonNegative);
      expect(eventTypeAt, lessThan(categoryAt));
      // 다른 목록(플레이스·장소대여 탭·지도)은 인자를 주지 않으므로 상태칩이
      // 그대로 남는다.
      expect(
        card.contains(
          'List<Widget> placeCardBadges(PlaceCardInfo info, '
          '{String? eventSourceBadge}) {',
        ),
        isTrue,
      );
    });

    test('목록은 언제나 이벤트 단위로 편다 — 칸을 가리지 않는다', () {
      expect(
        section.contains('_items = EventFeed.expandEvents(grouped);'),
        isTrue,
      );
      // 묶인 중간 결과를 그대로 그리던 갈래가 없어야 한다.
      expect(section.contains(': grouped;'), isFalse);
    });
  });

  group('이벤트 카드가 이벤트를 앞세운다', () {
    final card = _src('lib/widgets/place_card_widget.dart');
    final flat = _flat(card);

    test('대표 미디어는 이벤트 정본 → 없으면 원본으로 되돌아간다', () {
      expect(
        flat.contains(
          "getPartyCoverMedia(promotion.coverMediaMap, tag: 'EventFeedCard') "
          '?? info.cover;',
        ),
        isTrue,
      );
    });

    test('가장 큰 제목이 이벤트 제목이고 두 줄까지 쓴다', () {
      expect(
        flat.contains('_placeTitle(promotion.title, maxLines: 2)'),
        isTrue,
      );
    });

    test('매장명은 지우지 않고 📍 보조 줄로 내린다', () {
      final body = card.substring(card.indexOf('class PlaceEventCompactCard'));
      expect(body.contains('if (info.name.isNotEmpty) info.name,'), isTrue);
      expect(
        _flat(body).contains(
          'if (where.isNotEmpty) _placeInfoLine(Icons.location_on, where),',
        ),
        isTrue,
      );
    });

    test('🕒 줄은 이벤트 시간 — 없으면 매장 영업시간', () {
      expect(
        flat.contains(
          'final when = timeLabel.isNotEmpty ? timeLabel : info.hoursLabel;',
        ),
        isTrue,
      );
      // 문구의 정본은 상세·헤더와 같은 함수 하나다.
      expect(
        _flat(
          _src('lib/widgets/main/event_feed_section.dart'),
        ).contains('timeLabel: PlaceEventTime.timeLabelOf(lead),'),
        isTrue,
      );
    });

    test('누르면 가는 곳은 예전과 같다 — 상세·신청·문의 경로 그대로', () {
      final body = card.substring(card.indexOf('class PlaceEventCompactCard'));
      expect(
        body.contains('_openPlaceDetail(context, source, placeId, place)'),
        isTrue,
      );
      // 찜도 원본에 붙는다(기존 찜 목록과 어긋나지 않게).
      expect(body.contains('_placeFavoriteOverlay(placeId, source)'), isTrue);
    });

    test('플레이스·장소대여 탭·지도가 쓰는 원본 카드 규칙은 건드리지 않았다', () {
      final compact = card.substring(
        card.indexOf('class PlaceCompactCard'),
        card.indexOf('class PlaceEventCompactCard'),
      );
      // 원본 카드의 큰 제목은 여전히 장소명 한 줄이다.
      expect(compact.contains('_placeTitle(info.name)'), isTrue);
      expect(compact.contains('promotion'), isFalse);
    });
  });

  // ── ⑤ 파티는 그대로 ──────────────────────────────────────────────────
  group('파티 노출은 손대지 않았다', () {
    final section = _flat(_src('lib/widgets/main/event_feed_section.dart'));
    final main = _flat(_src('lib/screens/main_screen.dart'));

    test('이벤트 구획은 파티를 읽지도 그리지도 않는다', () {
      // 파티 맵을 빈 채로 넘긴다 — 파티 칸은 파티 목록이 예전 그대로 그린다.
      expect(section.contains('parties: const {},'), isTrue);
      // 이 구획이 그리는 것은 이벤트 칸뿐이다.
      expect(
        section.contains(
          'for (final item in _items.whereType<VenueEventFeedItem>()) _row(item),',
        ),
        isTrue,
      );
    });

    test('파티 목록은 예전 그대로 자기 카드 열을 그린다', () {
      // 좁은 화면·넓은 화면 둘 다 파티 칸이면 파티 카드 열.
      expect(main.contains('if (_feedFilter.showsParties)'), isTrue);
      expect('_buildPartyCardsColumn('.allMatches(main).length, greaterThan(1));
    });

    test('파티 칸은 이벤트 카드로 그려지지 않는다', () {
      final feed = _flat(_src('lib/models/event_feed.dart'));
      // 편 목록에서도 파티 칸은 그대로 지나간다.
      expect(
        feed.contains('if (item is! VenueEventFeedItem) { out.add(item); continue; }'),
        isTrue,
      );
    });
  });
}

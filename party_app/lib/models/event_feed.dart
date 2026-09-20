// ─────────────────────────────────────────────────────────────────────────────
// 🎉🎪 **파티츄/이벤트 탭의 표시용 피드** — 세 정본을 한 목록에 세우는 규칙.
//
// ── 무엇을 합치고 무엇을 합치지 않는가 ───────────────────────────────────────
// 합치는 것은 **보여주는 자리** 하나뿐이다. 저장 구조는 예전 그대로 셋이다.
//
//   🎉 파티        = `parties` 한 건 — 참가자를 모집하고 신청을 받는다.
//   🎪 매장 이벤트 = `placePromotions`(placeCollection: 'events') 한 건.
//   🎪 공간 이벤트 = `placePromotions`(placeCollection: 'places') 한 건.
//   🎊 공공 축제   = `publicEvents` 한 건 — 한국관광공사 TourAPI에서 서버가
//                    가져온 축제·행사. 파티츄 장소에 매달리지 않는다.
//
// 새 컬렉션도, 한쪽을 다른 쪽으로 옮겨 적는 미러 필드도 만들지 않는다 — 이
// 파일이 만드는 것은 **화면에 그릴 목록 한 벌**뿐이고, 그 목록의 각 칸은 원본
// 문서를 그대로 들고 있다. 공공 축제도 [PublicEvent]를 그대로 들고 서며,
// 사용자 등록 이벤트([PlacePromotion]) 모양으로 옮겨 적지 않는다.
//
// 공공 축제는 [build]·[expandEvents]를 거치지 않는다 — 원본 매장/공간이 없어
// 묶을 것도 펼 것도 없다. 편 목록에 [withPublicEvents]로 **나중에 합친다**.
//
// ── 탭마다 보는 범위가 다르다 ────────────────────────────────────────────────
//   · 파티츄/이벤트 → 셋 다(여기, [EventFeed]).
//   · 플레이스      → 매장 이벤트만([PlaceEventIndex] with `events`).
//   · 장소대여      → 공간 이벤트만([PlaceEventIndex] with `places`).
// 이 피드는 **파티츄/이벤트 탭 전용**이다. 나머지 두 탭은 예전처럼 자기 목록을
// 좁히는 색인만 쓴다 — 그래야 남의 탭 이벤트가 새어 들어올 길이 없다.
//
// ── 이벤트를 묶는 단위는 **어느 칸에서나 같다** ──────────────────────────────
// 화면에 서는 단위는 **이벤트 한 건이 카드 한 장**이다 — '전체' 칸이든 ✨ 이벤트
// 칸이든 똑같다. 예전에는 '전체' 칸만 원본 하나당 칸 하나로 묶어 '외 N건'으로
// 접었는데, 그러면 같은 이벤트가 어느 칸에서 보느냐에 따라 사진도 제목도 개수도
// 달랐다.
//
// [build]가 원본 단위로 묶는 것은 그대로다. 다만 그것은 **화면에 그릴 목록이
// 아니라 중간 결과**다 — 원본 안에서 곧 열리는 순서를 세우고, 목록에 없는
// 원본의 이벤트를 떨어내는 자리다. 화면은 그 묶음을 [expandEvents]로 펴서
// 쓴다: 판정도 정렬도 다시 만들지 않고, [build]를 통과한 칸을 펴서 같은
// 기준으로 다시 세울 뿐이다.
//
// ── 중복 카드가 생길 수 없는 이유 ────────────────────────────────────────────
// 세 종류 모두 **id를 열쇠로 하는 맵**을 거쳐 나온다 — 파티는 파티 문서 id,
// 이벤트는 (컬렉션, 원본 id)다. 같은 열쇠가 두 번 들어오면 덮어쓰기라 칸이
// 늘지 않는다. 컬렉션이 열쇠에 들어 있으므로 events의 'x'와 places의 'x'가
// 우연히 같아도 서로를 지우지 않는다.
//
// ── 노출 판정을 새로 만들지 않는다 ───────────────────────────────────────────
// 이벤트가 지금 보일지는 [PlacePromotion.statusAt]이 정한다 — 상세의 이벤트
// 영역·기존 🎪 색인이 쓰는 것과 **같은 판정**이다(숨김·종료는 빠진다). 원본
// 매장/공간이 보일지는 호출부가 [ListingSources]의 판정으로 걸러 넘기고,
// 파티가 보일지도 마찬가지다([ListingSources.isPartyVisible]).
//
// Firestore도 Flutter도 모르는 순수 함수다 — 화면 없이 테스트할 수 있다.
// 파티의 "다음 회차 시각"만 계산이 필요한데, 그 정본은 위젯 쪽
// (`PartyCard.parsePartyDateTime`)에 있으므로 함수로 주입받는다.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:party_app/models/host_offering.dart';
import 'package:party_app/models/place_event_index.dart';
import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/models/public_event.dart';

/// 피드 한 칸의 정체 — 배지에 그대로 적히는 값이다.
enum EventFeedKind {
  /// 🎉 참가자를 모집하고 신청을 받는 행사. 누르면 파티 상세로 간다.
  party(emoji: '🎉', label: '파티', collection: null, isEvent: false),

  /// ✨ 매장·즐길거리가 여는 행사. 누르면 **그 매장 상세**로 간다.
  placeEvent(
    emoji: kPlaceEventEmoji,
    label: '매장 이벤트',
    collection: PlaceEventIndex.placeCollection,
    isEvent: true,
  ),

  /// ✨ 공간대여·숙박이 여는 행사. 누르면 **그 장소 상세**로 간다.
  rentalEvent(
    emoji: kPlaceEventEmoji,
    label: '공간 이벤트',
    collection: PlaceEventIndex.rentalCollection,
    isEvent: true,
  ),

  /// 🎊 한국관광공사가 제공하는 공공 축제·행사(publicEvents). 파티츄 장소에
  /// 매달리지 않아 [collection]이 없다. 누르면 공공 축제 전용 상세로 간다
  /// ([PublicEventFeedItem]).
  publicFestival(
    emoji: '🎊',
    label: '공공 축제',
    collection: null,
    isEvent: true,
  );

  const EventFeedKind({
    required this.emoji,
    required this.label,
    required this.collection,
    required this.isEvent,
  });

  final String emoji;
  final String label;

  /// 이 종류가 읽는 `placePromotions.placeCollection` 값 — 파티와 공공
  /// 축제는 null.
  final String? collection;

  /// ✨ 이벤트 칸에 들어가는가 — 파티만 false다. 예전에는 [collection]
  /// 유무로 판정했지만, 공공 축제는 컬렉션 없이도 이벤트라 값으로 갖는다.
  final bool isEvent;

  /// 카드 위에 붙는 배지 문구 — '🎉 파티' / '✨ 매장 이벤트' / '✨ 공간 이벤트'
  /// / '🎊 공공 축제'.
  String get badge => '$emoji $label';

  /// placePromotions에서 오는 이벤트 두 종류만 — 컬렉션으로 갈라 담을 때
  /// 쓴다(공공 축제는 넣지 않는다).
  static const List<EventFeedKind> events = [placeEvent, rentalEvent];
}

/// 파티츄/이벤트 탭 상단의 [ 전체 | 🎉 파티 | ✨ 이벤트 ] 세 칸.
enum EventFeedFilter {
  all('전체', null),
  party('🎉 파티', false),
  event('$kPlaceEventEmoji 이벤트', true);

  const EventFeedFilter(this.label, this._wantEvent);

  final String label;

  /// null = 가리지 않음, false = 파티만, true = 이벤트만.
  final bool? _wantEvent;

  bool accepts(EventFeedKind kind) =>
      _wantEvent == null || _wantEvent == kind.isEvent;

  /// 이 칸이 파티 목록을 보여주는가 — 화면이 파티 구획을 그릴지 정한다.
  bool get showsParties => accepts(EventFeedKind.party);

  /// 이 칸이 이벤트 구획을 보여주는가.
  bool get showsEvents => accepts(EventFeedKind.placeEvent);
}

/// 피드 한 칸. 원본 문서를 그대로 들고 있다 — 변환하지 않는다.
sealed class EventFeedItem {
  const EventFeedItem({required this.kind, required this.sortAt});

  final EventFeedKind kind;

  /// "언제 볼 수 있나" — 정렬 기준. 이미 진행 중이면 기준 시각(now)이다.
  final DateTime sortAt;

  /// 목록 안에서 이 칸을 가리키는 열쇠 — **중복 판정의 정본**이다.
  String get key;
}

/// 🎉 파티 — 누르면 기존 파티 상세로 간다.
class PartyFeedItem extends EventFeedItem {
  const PartyFeedItem({
    required this.partyId,
    required this.party,
    required super.sortAt,
  }) : super(kind: EventFeedKind.party);

  final String partyId;

  /// `parties` 문서 그대로 — 기존 파티 카드가 이 맵을 받아 그린다.
  final Map<String, dynamic> party;

  @override
  String get key => 'party:$partyId';
}

/// 🎪 이벤트 — 누르면 **그 원본의 기존 상세**로 간다(별도 이벤트 상세가 아니다).
class VenueEventFeedItem extends EventFeedItem {
  const VenueEventFeedItem({
    required super.kind,
    required this.placeId,
    required this.place,
    required this.promotions,
    required super.sortAt,
    bool single = false,
  }) : _single = single;

  /// 원본 문서 id — `events` 또는 `places`([EventFeedKind.collection]).
  final String placeId;

  /// 원본 문서 그대로 — 기존 플레이스/장소대여 카드가 이 맵을 받는다.
  final Map<String, dynamic> place;

  /// 이 원본에서 **지금 보여줄** 이벤트들 — 곧 열리는 것부터.
  ///
  /// [build]가 만든 칸에서는 여러 건일 수 있지만 그 칸은 **중간 결과**다.
  /// 화면에 그려지는 칸은 [EventFeed.expandEvents]를 거쳐 **항상 한 건**이다 —
  /// '외 N건'으로 묶어 보여주는 자리는 이제 없다(맨 위 주석).
  final List<PlacePromotion> promotions;

  /// 이 칸이 이벤트 **한 건만** 가리키는가 — [EventFeed.expandEvents]가 편
  /// 칸이면 그 이벤트의 id다. [build]의 중간 결과에서는 null이다.
  ///
  /// 열쇠에 들어간다. 같은 매장의 이벤트 두 건이 카드 두 장이 되는 화면에서
  /// 열쇠가 같으면 Flutter가 두 칸을 같은 위젯으로 보고 스크롤·애니메이션이
  /// 엉킨다.
  String? get eventId =>
      promotions.length == 1 && _single ? promotions.first.id : null;

  /// [eventId]가 "한 건짜리 칸"을 뜻하려면, 원본에 이벤트가 원래 한 건뿐인
  /// 경우와 갈라야 한다 — 전자는 카드가 그 한 건을 그리고, 후자는 원본을
  /// 그린다. 값을 만드는 곳이 [EventFeed]뿐이라 생성자에서만 켠다.
  final bool _single;

  @override
  String get key {
    final id = eventId;
    return id == null
        ? '${kind.collection}:$placeId'
        : '${kind.collection}:$placeId#$id';
  }
}

/// 🎊 공공 축제 — 한국관광공사 TourAPI(publicEvents) 한 건.
///
/// 파티츄 장소가 없으므로 [VenueEventFeedItem]과 달리 원본 문서를 들지
/// 않는다. 누르면 이 [event]를 그대로 들고 공공 축제 전용 상세로 간다 —
/// 원본 매장/공간 상세로는 가지 않는다.
class PublicEventFeedItem extends EventFeedItem {
  const PublicEventFeedItem({required this.event, required super.sortAt})
    : super(kind: EventFeedKind.publicFestival);

  final PublicEvent event;

  /// 문서 id(`tour_<contentid>`)가 곧 열쇠다 — 같은 축제가 두 칸이 될 수 없고,
  /// 'public:' 접두어로 매장/공간 이벤트의 열쇠와도 겹치지 않는다.
  @override
  String get key => 'public:${event.id}';
}

/// 세 정본을 읽어 **한 목록**으로 세우는 순수 함수 묶음.
class EventFeed {
  EventFeed._();

  /// [parties]·[venues]·[rentals]는 이미 각자의 노출 판정을 통과한 문서
  /// (문서 id → 문서)이고, [promotions]는 걸러지지 않아도 된다 — 노출 판정과
  /// 컬렉션 확인을 여기서 다시 하므로 호출부가 무엇을 걸렀는지와 무관하게
  /// 결과가 같다([PlaceEventIndex]와 같은 규칙).
  ///
  /// [partyStartAt]은 파티의 다음 회차 시각을 돌려준다(정본은
  /// `PartyCard.parsePartyDateTime`). 알 수 없으면 null이어도 되고, 그때는
  /// 기준 시각으로 둔다 — 목록에서 사라지지는 않는다.
  static List<EventFeedItem> build({
    required Map<String, Map<String, dynamic>> parties,
    required Map<String, Map<String, dynamic>> venues,
    required Map<String, Map<String, dynamic>> rentals,
    required Iterable<PlacePromotion> promotions,
    required DateTime? Function(Map<String, dynamic> party) partyStartAt,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final items = <EventFeedItem>[];

    // ① 🎉 파티 — 문서 id가 곧 열쇠라 같은 파티가 두 칸이 될 수 없다.
    parties.forEach((id, data) {
      items.add(
        PartyFeedItem(
          partyId: id,
          party: data,
          sortAt: _notBefore(partyStartAt(data), at),
        ),
      );
    });

    // ② 🎪 이벤트 — **원본 단위로 묶는다**(위 주석). 컬렉션별로 갈라 담아
    //    매장 이벤트와 공간 이벤트가 서로의 원본을 집지 않게 한다.
    final sources = {
      EventFeedKind.placeEvent: venues,
      EventFeedKind.rentalEvent: rentals,
    };
    for (final entry in sources.entries) {
      final kind = entry.key;
      final places = entry.value;
      final byPlace = <String, List<PlacePromotion>>{};
      for (final p in promotions) {
        if (p.placeCollection != kind.collection) continue;
        if (p.placeId.isEmpty) continue;
        // 목록에 없는(숨김·삭제된) 원본의 이벤트는 눌러 갈 곳이 없다.
        if (!places.containsKey(p.placeId)) continue;
        if (!p.statusAt(at).isPublic) continue;
        byPlace.putIfAbsent(p.placeId, () => <PlacePromotion>[]).add(p);
      }
      byPlace.forEach((placeId, list) {
        // 원본 안에서는 곧 열리는 것부터 — 카드 한 줄에 적히는 것이 그 첫 건이다.
        list.sort((a, b) {
          final c = _notBefore(
            a.startAt,
            at,
          ).compareTo(_notBefore(b.startAt, at));
          return c != 0 ? c : a.sortOrder.compareTo(b.sortOrder);
        });
        items.add(
          VenueEventFeedItem(
            kind: kind,
            placeId: placeId,
            place: places[placeId]!,
            promotions: List.unmodifiable(list),
            sortAt: _notBefore(list.first.startAt, at),
          ),
        );
      });
    }

    // ③ 섞어서 "곧 볼 수 있는 것"부터. 같은 시각이면 종류 선언 순서로, 그다음
    //    열쇠로 갈라 — 스냅샷이 새로 와도 카드가 까닭 없이 자리를 바꾸지 않는다.
    items.sort((a, b) {
      final c = a.sortAt.compareTo(b.sortAt);
      if (c != 0) return c;
      final k = a.kind.index.compareTo(b.kind.index);
      return k != 0 ? k : a.key.compareTo(b.key);
    });
    return items;
  }

  /// **화면에 그리는 목록의 정본** — 카드 한 장이 이벤트 한 건이다.
  ///
  /// [build]는 원본(매장/공간) 단위로 묶지만 그 묶음은 중간 결과다. 화면에
  /// 서는 것은 언제나 이 목록이다 — '전체' 칸이든 ✨ 이벤트 칸이든
  /// ([EventFeedSection]). 묶어서 보여주면 두 번째 건은 '외 1건'이라는 숫자로만
  /// 남아 제목도 사진도 볼 수 없고, 같은 이벤트가 칸에 따라 다르게 보인다.
  ///
  /// 묶음을 푸는 것뿐이다. 노출 판정·필터·정렬 규칙을 다시 만들지 않는다 —
  /// 이미 [build]를 통과한 칸을 펼쳐, 같은 기준(곧 열리는 것부터)으로 다시
  /// 세울 뿐이다. 파티 칸은 그대로 지나간다.
  static List<EventFeedItem> expandEvents(
    List<EventFeedItem> items, {
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final out = <EventFeedItem>[];
    for (final item in items) {
      if (item is! VenueEventFeedItem) {
        out.add(item);
        continue;
      }
      for (final p in item.promotions) {
        out.add(
          VenueEventFeedItem(
            kind: item.kind,
            placeId: item.placeId,
            place: item.place,
            promotions: List.unmodifiable([p]),
            sortAt: _notBefore(p.startAt, at),
            single: true,
          ),
        );
      }
    }
    // [build]의 ③과 같은 순서 — 곧 볼 수 있는 것부터, 같은 시각이면 종류·열쇠.
    out.sort((a, b) {
      final c = a.sortAt.compareTo(b.sortAt);
      if (c != 0) return c;
      final k = a.kind.index.compareTo(b.kind.index);
      return k != 0 ? k : a.key.compareTo(b.key);
    });
    return out;
  }

  /// [expandEvents]가 편 목록에 🎊 공공 축제를 합쳐 **한 순서**로 세운다.
  ///
  /// [publicEvents]는 이미 노출 판정([PublicEvent.isVisible])과 종료 거르기를
  /// 통과한 것이어도 되고 아니어도 된다 — 여기서 다시 거른다. 문서 id가
  /// 열쇠라 같은 축제가 두 번 들어와도 한 칸이다.
  ///
  /// 순서는 [build]·[expandEvents]와 같은 "곧 볼 수 있는 것부터"다:
  ///   ① max(시작, 지금) — 진행 중이면 모두 '지금'이라 앞에 선다.
  ///   ② 같은 시각이면 종류 선언 순서 — 진행 중끼리는 파티츄 이벤트가
  ///      공공 축제보다 앞이다.
  ///   ③ 공공 축제끼리는 곧 끝나는 것부터(놓치기 쉬운 것을 앞에).
  ///   ④ 그래도 같으면 열쇠 — 스냅샷이 새로 와도 자리가 흔들리지 않는다.
  /// ①은 각 칸이 만들어진 시각이 달라도 같은 [now]로 다시 잰다 — 편 목록의
  /// '지금'과 여기의 '지금'이 몇 밀리초 어긋나 진행 중 칸이 갈라지지 않게.
  static List<EventFeedItem> withPublicEvents(
    List<EventFeedItem> items,
    Iterable<PublicEvent> publicEvents, {
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final byId = <String, PublicEventFeedItem>{};
    for (final e in publicEvents) {
      if (!e.isVisible || !e.isOpenAt(at)) continue;
      byId[e.id] = PublicEventFeedItem(
        event: e,
        sortAt: _notBefore(e.startAt, at),
      );
    }
    final out = <EventFeedItem>[
      for (final item in items)
        if (item is! PublicEventFeedItem) item,
      ...byId.values,
    ];
    out.sort((a, b) {
      final c = _notBefore(a.sortAt, at).compareTo(_notBefore(b.sortAt, at));
      if (c != 0) return c;
      final k = a.kind.index.compareTo(b.kind.index);
      if (k != 0) return k;
      if (a is PublicEventFeedItem && b is PublicEventFeedItem) {
        final e = a.event.endAt.compareTo(b.event.endAt);
        if (e != 0) return e;
      }
      return a.key.compareTo(b.key);
    });
    return out;
  }

  /// 상단 세그먼트가 고른 것만 남긴다 — 목록을 다시 만들지 않는다.
  static List<EventFeedItem> where(
    List<EventFeedItem> items,
    EventFeedFilter filter,
  ) => items.where((i) => filter.accepts(i.kind)).toList();

  static int countOf(List<EventFeedItem> items, EventFeedFilter filter) =>
      items.where((i) => filter.accepts(i.kind)).length;

  /// 이미 지난(또는 없는) 시각은 기준 시각으로 끌어올린다 — "진행 중"과
  /// "상시"가 목록 맨 뒤로 밀리지 않게 한다.
  static DateTime _notBefore(DateTime? value, DateTime at) =>
      (value == null || value.isBefore(at)) ? at : value;
}

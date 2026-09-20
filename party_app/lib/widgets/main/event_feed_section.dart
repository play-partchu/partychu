// ─────────────────────────────────────────────────────────────────────────────
// 🎪 파티츄/이벤트 탭의 **이벤트 구획** — 매장 이벤트와 공간 이벤트를 함께.
//
// ── 왜 파티 목록과 한 위젯이 아닌가 ──────────────────────────────────────────
// 파티 목록은 날짜·시간·인원·정렬·보기방식·검색이 전부 걸리는 자리다. 이벤트에는
// **인원·정렬**이 뜻을 갖지 않는다(신청도 정원도 없다). 그래서 두 목록을 한
// 덩어리로 섞지 않고, 이벤트는 **이 구획이 따로** 그린다 — 상단 세그먼트가 둘 중
// 무엇을 보일지만 정한다([EventFeedFilter]).
//
// **날짜·시간은 이벤트에도 그대로 걸린다.** 다만 판정에 쓰는 데이터가 다르다 —
// 파티는 회차 일정([PartyTimeFilter]), 이벤트는 이벤트 기간·진행 시간
// ([PlaceEventTime])이다. 규칙(자정 넘김 등)은 두 쪽이 같은 함수를 쓴다
// ([DayTimeMatch]). 그래서 같은 조건을 걸어도 각자 자기 데이터로 올바르게
// 걸러진다.
//
// ── 여기서 읽는 것 ───────────────────────────────────────────────────────────
// 이벤트 카드는 **이벤트 문서만으로는 그릴 수 없다** — 카드에 뜨는 사진·이름·
// 지역은 원본 매장/공간 문서에 있다. 그래서 이벤트 목록과 두 원본 목록을 함께
// 읽어 id로 잇는다. 셋 다 목록·지도가 이미 쓰는 그 쿼리다
// ([ListingSources] / [PlacePromotionService.watchPublicAll]) — 새 컬렉션도
// 미러 필드도 만들지 않는다.
//
// ── 카드의 정본은 하나다 ─────────────────────────────────────────────────────
// 이벤트가 어느 칸에 나오든 **같은 카드 한 종류**다([PlaceEventCompactCard]) —
// 같은 단위(이벤트 한 건 = 카드 한 장), 같은 대표 미디어, 같은 큰 제목, 같은
// 배지, 같은 정렬. 예전에는 '전체' 칸만 원본(매장/공간) 단위로 묶어 원본 카드
// ([PlaceCompactCard])로 그리고 그 위에 '제목 외 N건' 보조 줄을 덧붙였는데,
// 그러면 **같은 이벤트가 어느 칸에서 보느냐에 따라** 사진도 제목도 개수도
// 달랐다. 지금은 이 구획이 칸을 가리지 않고 [EventFeed.expandEvents]가 편 목록
// 하나만 그린다 — '전체' 칸이 다르게 보일 여지 자체를 없앤 것이다.
//
// 칸이 정하는 것은 **머리글을 얹을지**뿐이다([showHeader]) — 파티 목록과 함께
// 보일 때 어디부터 이벤트인지 알려주는 줄이다. 전체 칸의 **파티 카드는 예전
// 그대로**이고(파티 목록이 따로 그린다) 여기서 바뀐 것은 이벤트뿐이다.
//
// ── 누르면 원래 있던 상세로 ──────────────────────────────────────────────────
// 🎪 매장 이벤트 → 매장 상세, 🎪 공간 이벤트 → 장소대여 상세. 카드가 원본
// 문서와 이동 경로를 그대로 들고 있어([PlaceCardSource]) 이동도 예전 동작
// 그대로이고, 이벤트 내용은 상세에 이미 있는 이벤트 영역
// ([PlacePromotionListSection])이 보여준다 — 이벤트만 따로 떼어낸 상세를
// 만들지 않는다.
//
// ── 🎊 공공 축제(publicEvents) ──────────────────────────────────────────────
// 한국관광공사 TourAPI에서 서버가 가져온 축제도 이 구획에 함께 선다
// ([PublicEventService.watchOpen]). 매장/공간 이벤트와 달리 원본 장소가 없어
// 자기 카드([PublicEventCompactCard])로 그리고, 편 목록에 나중에 합친다
// ([EventFeed.withPublicEvents]) — 순서는 같은 "곧 볼 수 있는 것부터"다.
// 📅 날짜 조건은 축제 기간으로 거르고, 🕐 시간 조건으로는 거르지 않는다(진행
// 시각이 없는 행사는 전시간으로 보는 이벤트 규칙과 같다).
//
// 공공 축제 카드를 누르면 공공 축제 전용 상세로 간다(카드가 가진 객체를 그대로
// 넘긴다 — 매장/공간 상세로는 가지 않는다). 공공 축제를 못 읽어도 이 구획
// 전체를 오류로 덮지 않는다(그 경우 파티츄 이벤트만 보인다).
//
// ── 한 번에 다 그리지 않는다 ─────────────────────────────────────────────────
// 이 구획은 부모의 SingleChildScrollView 안 Column이라 자식이 **전부 한꺼번에**
// 만들어진다. 공공 축제만 수백 건이라 [_pageSize]장씩 그리고 '더보기'로 늘린다.
// 조건(📅🕐)이 바뀌면 처음 [_pageSize]장으로 돌아간다.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:party_app/models/day_time_match.dart';
import 'package:party_app/models/event_feed.dart';
import 'package:party_app/models/place_event_index.dart';
import 'package:party_app/models/place_event_time.dart';
import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/models/place_weekly_hours.dart';
import 'package:party_app/models/public_event.dart';
import 'package:party_app/services/listing_sources.dart';
import 'package:party_app/services/place_promotion_service.dart';
import 'package:party_app/services/public_event_service.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/widgets/place_card_widget.dart';
import 'package:party_app/widgets/public_event_card.dart';

const Color _kPink = Color(0xFFFF6FA0);

class EventFeedSection extends StatefulWidget {
  const EventFeedSection({
    super.key,
    required this.showHeader,
    this.dates = const [],
    this.timeStart,
    this.timeEnd,
  });

  /// 파티 목록과 **함께** 보일 때는 어디부터 이벤트인지 알려주는 머리글을
  /// 얹는다. 이벤트만 보는 칸에서는 화면 전체가 이벤트라 필요 없다.
  ///
  /// 이 구획이 칸마다 달리 하는 일은 **이 줄 하나뿐**이다 — 카드도, 카드가
  /// 서는 단위도, 정렬도 어느 칸에서나 같다(맨 위 주석).
  final bool showHeader;

  /// 📅 고른 날짜들 — 비어 있으면 날짜로 거르지 않는다. 여러 날은 OR다
  /// (파티 쪽 [PartyFilter.selectedDates]와 **같은 값**을 그대로 받는다).
  final Iterable<DateTime> dates;

  /// 🕐 고른 시각·시간대. 시작만 있으면 '그 시각에 적용 중',
  /// 둘 다 있으면 '그 구간과 겹치는' 이벤트다([PlaceEventTime.matchesTime]).
  final TimeOfDay? timeStart;
  final TimeOfDay? timeEnd;

  @override
  State<EventFeedSection> createState() => _EventFeedSectionState();
}

class _EventFeedSectionState extends State<EventFeedSection> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _venueSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _rentalSub;
  StreamSubscription<List<PlacePromotion>>? _promoSub;
  StreamSubscription<List<PublicEvent>>? _publicSub;

  /// 한 번에 그리는 카드 수 — '더보기'를 누를 때마다 이만큼 늘어난다.
  static const int _pageSize = 20;
  int _shown = _pageSize;

  /// null은 "아직 못 읽었다" — 빈 맵("없다")과 구분해야 첫 프레임에 "이벤트가
  /// 없어요"가 잠깐 스쳤다 사라지지 않는다.
  Map<String, Map<String, dynamic>>? _venues;
  Map<String, Map<String, dynamic>>? _rentals;
  List<PlacePromotion>? _promotions;

  /// 🎊 공공 축제 — null은 "아직 못 읽었다". 읽다가 실패하면 빈 목록으로 두고
  /// 파티츄 이벤트만 보여준다([_error]로 구획 전체를 덮지 않는다).
  List<PublicEvent>? _publicEvents;

  Object? _error;

  List<EventFeedItem> _items = const [];

  bool get _loading =>
      _error == null &&
      (_venues == null ||
          _rentals == null ||
          _promotions == null ||
          _publicEvents == null);

  @override
  void didUpdateWidget(covariant EventFeedSection old) {
    super.didUpdateWidget(old);
    // 스냅샷은 그대로인데 **조건만** 바뀌는 경우가 대부분이다(사용자가 날짜를
    // 고른 순간). _apply는 스냅샷이 올 때만 도는 자리라, 여기서 한 번 더
    // 세워 주지 않으면 필터를 바꿔도 목록이 그대로 남는다.
    if (!_sameFilter(old)) {
      // 조건이 바뀌면 목록이 새로 서므로 처음 몇 장부터 다시 보여준다.
      _shown = _pageSize;
      _rebuild();
    }
  }

  bool _sameFilter(EventFeedSection old) =>
      // 칸을 옮겨도 카드 단위는 바뀌지 않는다(어느 칸에서나 이벤트 한 건이
      // 카드 한 장) — 목록을 다시 세우게 만드는 것은 📅🕐 조건뿐이다.
      old.timeStart == widget.timeStart &&
      old.timeEnd == widget.timeEnd &&
      _sameDates(old.dates, widget.dates);

  static bool _sameDates(Iterable<DateTime> a, Iterable<DateTime> b) {
    final x = a.toList()..sort();
    final y = b.toList()..sort();
    if (x.length != y.length) return false;
    for (var i = 0; i < x.length; i++) {
      if (!x[i].isAtSameMomentAs(y[i])) return false;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    // 매장·즐길거리 — 플레이스 목록과 같은 쿼리·같은 판정.
    _venueSub = ListingSources.events().snapshots().listen(
      (snap) =>
          _apply(() => _venues = _visible(snap, ListingSources.isEventVisible)),
      onError: _onError('EventFeedSection.venues'),
    );
    // 공간대여·숙박 — 장소대여 목록과 같은 쿼리·같은 판정.
    _rentalSub = ListingSources.places().snapshots().listen(
      (snap) => _apply(
        () => _rentals = _visible(snap, ListingSources.isRentalVisible),
      ),
      onError: _onError('EventFeedSection.rentals'),
    );
    // 이벤트 — 🎪 색인이 쓰는 그 스트림(숨김·종료는 여기서 이미 빠진다).
    _promoSub = PlacePromotionService.watchPublicAll().listen(
      (list) => _apply(() => _promotions = list),
      onError: _onError('EventFeedSection.promotions'),
    );
    // 🎊 공공 축제 — 노출(isVisible)만 서버에서 거르고, 끝난 것은 서비스가
    // 거른다.
    _publicSub = PublicEventService.watchOpen().listen(
      (list) => _apply(() => _publicEvents = list),
      onError: (Object e, StackTrace s) {
        logFirestoreStreamError('EventFeedSection.publicEvents', e, s);
        _apply(() => _publicEvents = const []);
      },
    );
  }

  Map<String, Map<String, dynamic>> _visible(
    QuerySnapshot<Map<String, dynamic>> snap,
    bool Function(Map<String, dynamic>) isVisible,
  ) {
    final out = <String, Map<String, dynamic>>{};
    for (final d in snap.docs) {
      final data = d.data();
      if (!isVisible(data)) continue;
      out[d.id] = data;
    }
    return out;
  }

  /// 스냅샷이 하나라도 새로 왔을 때만 목록을 다시 세운다 — build마다 다시
  /// 정렬하지 않는다.
  void _apply(VoidCallback update) {
    if (!mounted) return;
    setState(() {
      update();
      _buildItems();
    });
  }

  void _rebuild() {
    if (!mounted) return;
    setState(_buildItems);
  }

  void _buildItems() {
    if (_venues == null ||
        _rentals == null ||
        _promotions == null ||
        _publicEvents == null) {
      return;
    }
    final grouped = EventFeed.build(
      // 파티는 이 구획이 그리지 않는다 — 파티 목록이 예전 그대로 그린다.
      parties: const {},
      venues: _venues!,
      rentals: _rentals!,
      promotions: _filteredPromotions(),
      partyStartAt: (_) => null,
    );
    // **이벤트 한 건이 카드 한 장**이다 — 같은 매장의 이벤트 두 건이면 카드도
    // 두 장이고, 이는 어느 칸에서 보든 같다. 여기서 칸에 따라 갈라 놓으면 같은
    // 이벤트가 전체 칸과 이벤트 칸에서 다른 카드로 보인다
    // ([EventFeed.expandEvents]의 주석).
    _items = EventFeed.expandEvents(grouped);
    // 🎊 공공 축제를 같은 순서 규칙으로 합친다 — 원본 장소가 없어 묶거나 펼
    // 것이 없으므로 편 목록에 바로 얹는다.
    _items = EventFeed.withPublicEvents(_items, _filteredPublicEvents());
  }

  /// 📅 조건을 통과한 공공 축제만 — 고른 날 중 하루라도 기간이 걸치면 남는다.
  /// 🕐 시간 조건은 보지 않는다(진행 시각이 없는 행사 = 전시간).
  List<PublicEvent> _filteredPublicEvents() {
    final all = _publicEvents!;
    final dates = widget.dates.toList();
    if (dates.isEmpty) return all;
    return [
      for (final e in all)
        if (dates.any(e.overlapsDay)) e,
    ];
  }

  /// 📅🕐 조건을 통과한 이벤트만.
  ///
  /// **원본이 아니라 이벤트를 거른다** — 매장 하나가 이벤트를 여럿 열었을 때
  /// 조건에 맞는 것만 남아야 카드의 '외 N건'도 맞는 수가 된다. 남은 이벤트가
  /// 하나도 없는 매장은 [EventFeed.build]가 알아서 카드를 만들지 않는다.
  ///
  /// 영업중(전시간) 이벤트는 **그 매장의 영업시간**으로 판정하므로 원본
  /// 문서에서 영업시간을 꺼내 함께 넘긴다([PlaceWeeklyHours.fromPlaceDoc]).
  List<PlacePromotion> _filteredPromotions() {
    final all = _promotions!;
    final dates = widget.dates.toList();
    final hasTime = DayTimeMatch.isActive(widget.timeStart, widget.timeEnd);
    if (dates.isEmpty && !hasTime) return all;
    return [
      for (final p in all)
        if (PlaceEventTime.matches(
          p,
          dates: dates,
          start: widget.timeStart,
          end: widget.timeEnd,
          hours: _hoursOf(p),
        ))
          p,
    ];
  }

  /// 이 이벤트를 연 원본의 영업시간 — 매장이든 공간이든 같은 두 필드를 본다.
  PlaceWeeklyHours? _hoursOf(PlacePromotion p) {
    final isRental = p.placeCollection == PlaceEventIndex.rentalCollection;
    final source = isRental ? _rentals : _venues;
    final doc = source?[p.placeId];
    if (doc == null) return null;
    return PlaceWeeklyHours.fromPlaceDoc(doc);
  }

  void Function(Object, StackTrace) _onError(String tag) =>
      (Object e, StackTrace s) {
        logFirestoreStreamError(tag, e, s);
        if (!mounted) return;
        setState(() => _error = e);
      };

  @override
  void dispose() {
    _venueSub?.cancel();
    _rentalSub?.cancel();
    _promoSub?.cancel();
    _publicSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _note('이벤트를 불러오지 못했어요. 잠시 후 다시 시도해주세요.');
    }
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: _kPink),
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return _note('지금 진행 중인 이벤트가 없어요.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showHeader) ...[
          const Padding(
            padding: EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              '✨ 지금 하는 이벤트',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ],
        // 이 구획이 그리는 것은 이벤트뿐이다(파티는 파티 목록이 그린다) —
        // 매장/공간 이벤트와 🎊 공공 축제. 파티 칸이 섞여 들어와도 화면이
        // 죽는 대신 건너뛴다([_card]). 처음 [_shown]장만 만든다.
        for (final item in _items.take(_shown)) _card(item),
        if (_items.length > _shown) _moreButton(_items.length - _shown),
      ],
    );
  }

  Widget _card(EventFeedItem item) => switch (item) {
    VenueEventFeedItem() => _row(item),
    PublicEventFeedItem() => PublicEventCompactCard(
      key: ValueKey(item.key),
      event: item.event,
      badge: item.kind.badge,
      // 누르면 공공 축제 상세 — 카드의 기본 동작([openPublicEventDetail]).
    ),
    PartyFeedItem() => const SizedBox.shrink(),
  };

  /// '이벤트 N개 더보기' — 누를 때마다 [_pageSize]장씩 더 그린다.
  Widget _moreButton(int hidden) => Center(
    child: TextButton(
      onPressed: () => setState(() => _shown += _pageSize),
      style: TextButton.styleFrom(foregroundColor: _kPink),
      child: Text(
        '이벤트 $hidden개 더보기',
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
    ),
  );

  /// 카드 하나 — 어느 칸에서든 **같은 이벤트 카드**
  /// ([PlaceEventCompactCard]) 하나다. 카드 위에 덧붙는 보조 줄도, 칸에 따른
  /// 분기도 없다.
  ///
  /// ✨ 매장 이벤트 / ✨ 공간 이벤트 구분은 **카드 안에** 있다
  /// ([placeCardBadges]의 `eventSourceBadge`). 카드 밖과 안에 같은 뜻의 배지가
  /// 둘이면 이벤트 한 건이 두 번 라벨링되어 보인다 — 남기는 것은 업종 배지와
  /// 나란히 서는 카드 안쪽 하나다.
  ///
  /// 예전 전체 칸에는 카드 위에 '제목 외 N건 · 시간' 한 줄이 있었다. 그 줄은
  /// 카드 본문이 이벤트가 아니라 매장/공간이던 시절의 보완물이다 — 지금은
  /// 제목도 시간도 카드 본문에 크게 있고 '외 N건'이라는 묶음 자체가 없으므로,
  /// 그 줄을 남기면 같은 문구가 위아래로 두 번 보인다.
  Widget _row(VenueEventFeedItem item) {
    final source = item.kind == EventFeedKind.rentalEvent
        ? PlaceCardSource.rental
        : PlaceCardSource.place;
    // 목록은 이미 이벤트 단위로 펴져 있어 여기 오는 칸은 **이벤트 한 건**이다
    // ([EventFeed.expandEvents]). 사진과 제목이 반드시 같은 건에서 나와야 해서
    // 카드에 이벤트 객체 하나를 통째로 넘긴다.
    final lead = item.promotions.isEmpty ? null : item.promotions.first;
    if (lead == null) return const SizedBox.shrink();
    return PlaceEventCompactCard(
      key: ValueKey(item.key),
      place: item.place,
      placeId: item.placeId,
      // 매장 이벤트 → 매장 상세, 공간 이벤트 → 장소대여 상세.
      // 카드의 기존 동작 그대로다.
      source: source,
      promotion: lead,
      // ✨ 매장 이벤트 / ✨ 공간 이벤트 — 카드 안, 업종 배지 바로 앞.
      eventSourceBadge: item.kind.badge,
      // 문구의 정본은 상세와 같은 함수 하나다 — 시각을 안 정한 이벤트는
      // 여기서도 '영업중(전시간)'으로 읽힌다.
      timeLabel: PlaceEventTime.timeLabelOf(lead),
    );
  }

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13.5, color: Colors.black45),
      ),
    ),
  );
}

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/event_filter.dart';
import 'package:party_app/models/place_event_index.dart';
import 'package:party_app/models/place_event_time.dart';
import 'package:party_app/models/place_filter.dart';
import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/models/place_weekly_hours.dart';

/// **지도와 목록이 같은 답을 내는가.**
///
/// 지도(map_screen)와 플레이스 목록은 [EventFilter.matchesDiscovery] 하나를
/// 함께 부르고, 장소대여는 [PlaceFilter.matchesEvent] 하나를 함께 부른다.
/// 둘 다 안쪽에서 [PlaceEventIndex.hasMatching] → [PlaceEventTime.matches]로
/// 내려가므로, 두 화면이 갈라지려면 **판정 함수가 둘이어야** 한다.
///
/// 그래서 이 파일은 "지도용 판정"을 따로 검사하지 않는다 — 같은 함수에 같은
/// 조건을 넣었을 때 이벤트 탭 목록과 답이 같은지를 본다.

PlacePromotion promo({
  String id = 'e1',
  String placeId = 'place1',
  String collection = PlaceEventIndex.placeCollection,
  bool isAlways = false,
  DateTime? startAt,
  DateTime? endAt,
  List<int> weekdays = const [],
  String? startTime,
  String? endTime,
}) => PlacePromotion.fromMap(id, {
  'placeId': placeId,
  'placeCollection': collection,
  'hostId': 'host1',
  'title': '이벤트',
  'isAlways': isAlways,
  if (startAt != null) 'startAt': startAt,
  if (endAt != null) 'endAt': endAt,
  'weekdays': weekdays,
  if (startTime != null) 'startTime': startTime,
  if (endTime != null) 'endTime': endTime,
});

/// 18:00~02:00 영업하는 매장 문서.
Map<String, dynamic> nightPlaceDoc() => {
  'name': '야간 매장',
  'placeWeeklyHours': {
    for (final d in PlaceWeeklyHours.weekdays)
      d: {'open': '18:00', 'close': '02:00', 'isClosed': false},
  },
};

/// 영업시간을 아예 등록하지 않은 매장 문서.
Map<String, dynamic> noHoursDoc() => {'name': '영업시간 미등록'};

/// 지도·플레이스 목록이 함께 쓰는 입구.
bool discoveryAllows({
  required Map<String, dynamic> doc,
  required PlaceEventIndex index,
  Set<DateTime> dates = const {},
  TimeOfDay? start,
  TimeOfDay? end,
  DateTime? now,
}) {
  final f = EventFilter()
    ..eventOnly = true
    ..visitDates.addAll(dates)
    ..startTime = start
    ..endTime = end;
  return f.matchesDiscovery(
    doc,
    docId: 'place1',
    eventIndex: index,
    now: now,
  );
}

/// 이벤트 탭 목록이 쓰는 입구(같은 판정의 반대쪽 끝).
bool feedAllows(
  PlacePromotion p, {
  Set<DateTime> dates = const {},
  TimeOfDay? start,
  TimeOfDay? end,
  PlaceWeeklyHours? hours,
}) => PlaceEventTime.matches(
  p,
  dates: dates.toList(),
  start: start,
  end: end,
  hours: hours,
);

void main() {
  final now = DateTime(2026, 9, 5, 12);

  group('지도(플레이스 축)와 이벤트 탭 목록이 같은 답을 낸다', () {
    void parity(
      String name,
      PlacePromotion p, {
      Set<DateTime> dates = const {},
      TimeOfDay? start,
      TimeOfDay? end,
      required Map<String, dynamic> doc,
      required bool expected,
    }) {
      test(name, () {
        final index = PlaceEventIndex.fromPromotions([p], now: now);
        final onMap = discoveryAllows(
          doc: doc,
          index: index,
          dates: dates,
          start: start,
          end: end,
          now: now,
        );
        final onFeed = feedAllows(
          p,
          dates: dates,
          start: start,
          end: end,
          hours: PlaceWeeklyHours.fromPlaceDoc(doc),
        );
        expect(onMap, expected, reason: '지도 판정이 다르다');
        expect(onFeed, expected, reason: '목록 판정이 다르다');
        expect(onMap, onFeed, reason: '지도와 목록이 갈렸다');
      });
    }

    // ── 날짜만 ────────────────────────────────────────────────────────
    parity(
      '날짜만 — 기간 안이면 남는다',
      promo(startAt: DateTime(2026, 9, 1), endAt: DateTime(2026, 9, 10)),
      dates: {DateTime(2026, 9, 5)},
      doc: nightPlaceDoc(),
      expected: true,
    );
    parity(
      '날짜만 — 기간 밖이면 빠진다',
      promo(startAt: DateTime(2026, 9, 1), endAt: DateTime(2026, 9, 10)),
      dates: {DateTime(2026, 9, 15)},
      doc: nightPlaceDoc(),
      expected: false,
    );

    // ── 시간만 ────────────────────────────────────────────────────────
    parity(
      '시간만 — 18:00~21:00 이벤트는 23:00에 빠진다',
      promo(isAlways: true, startTime: '18:00', endTime: '21:00'),
      start: const TimeOfDay(hour: 23, minute: 0),
      doc: nightPlaceDoc(),
      expected: false,
    );
    parity(
      '시간만 — 22:00~02:00 이벤트는 23:00에 남는다',
      promo(isAlways: true, startTime: '22:00', endTime: '02:00'),
      start: const TimeOfDay(hour: 23, minute: 0),
      doc: nightPlaceDoc(),
      expected: true,
    );

    // ── 자정 넘김 ─────────────────────────────────────────────────────
    parity(
      '자정 넘김 — 22:00~02:00 이벤트는 01:00에도 남는다',
      promo(isAlways: true, startTime: '22:00', endTime: '02:00'),
      start: const TimeOfDay(hour: 1, minute: 0),
      doc: nightPlaceDoc(),
      expected: true,
    );

    // ── 날짜 + 시간 ───────────────────────────────────────────────────
    parity(
      '날짜+시간 — 둘 다 맞아야 남는다',
      promo(
        startAt: DateTime(2026, 9, 1),
        endAt: DateTime(2026, 9, 10),
        startTime: '22:00',
        endTime: '02:00',
      ),
      dates: {DateTime(2026, 9, 5)},
      start: const TimeOfDay(hour: 23, minute: 0),
      doc: nightPlaceDoc(),
      expected: true,
    );
    parity(
      '날짜+시간 — 날짜는 맞고 시간이 어긋나면 빠진다',
      promo(
        startAt: DateTime(2026, 9, 1),
        endAt: DateTime(2026, 9, 10),
        startTime: '22:00',
        endTime: '02:00',
      ),
      dates: {DateTime(2026, 9, 5)},
      start: const TimeOfDay(hour: 19, minute: 0),
      doc: nightPlaceDoc(),
      expected: false,
    );

    // ── 상시 진행 ─────────────────────────────────────────────────────
    parity(
      '상시 진행 — 어느 날짜에도 남는다',
      promo(isAlways: true, startTime: '22:00', endTime: '02:00'),
      dates: {DateTime(2030, 12, 31)},
      doc: nightPlaceDoc(),
      expected: true,
    );

    // ── 영업중(전시간) ────────────────────────────────────────────────
    parity(
      '영업중(전시간) — 영업 중인 23:00에는 남는다',
      promo(isAlways: true),
      start: const TimeOfDay(hour: 23, minute: 0),
      doc: nightPlaceDoc(),
      expected: true,
    );
    parity(
      '영업중(전시간) — 문 닫은 15:00에는 빠진다(24시간이 아니다)',
      promo(isAlways: true),
      start: const TimeOfDay(hour: 15, minute: 0),
      doc: nightPlaceDoc(),
      expected: false,
    );
    parity(
      '영업시간 미등록 매장 — 시간 조건이 걸리면 빠진다',
      promo(isAlways: true),
      start: const TimeOfDay(hour: 23, minute: 0),
      doc: noHoursDoc(),
      expected: false,
    );
    parity(
      '영업시간 미등록 매장 — 조건이 없으면 그대로 남는다',
      promo(isAlways: true),
      doc: noHoursDoc(),
      expected: true,
    );
  });

  group('장소대여(공간 이벤트) 축도 같은 함수를 쓴다', () {
    PlaceFilter rentalFilter({DateTime? date, TimeOfDay? start, TimeOfDay? end}) =>
        PlaceFilter(useDate: date, startTime: start, endTime: end)
          ..eventOnly = true;

    test('공간 이벤트도 시간 조건으로 걸러진다', () {
      final p = promo(
        collection: PlaceEventIndex.rentalCollection,
        isAlways: true,
        startTime: '22:00',
        endTime: '02:00',
      );
      final index = PlaceEventIndex.fromPromotions(
        [p],
        now: now,
        collection: PlaceEventIndex.rentalCollection,
      );
      final doc = nightPlaceDoc();

      expect(
        rentalFilter(start: const TimeOfDay(hour: 23, minute: 0))
            .matchesEvent('place1', index, doc: doc),
        isTrue,
      );
      expect(
        rentalFilter(start: const TimeOfDay(hour: 19, minute: 0))
            .matchesEvent('place1', index, doc: doc),
        isFalse,
      );
    });

    test('영업중(전시간) 공간 이벤트도 영업시간으로 판정된다', () {
      final p = promo(
        collection: PlaceEventIndex.rentalCollection,
        isAlways: true,
      );
      final index = PlaceEventIndex.fromPromotions(
        [p],
        now: now,
        collection: PlaceEventIndex.rentalCollection,
      );
      expect(
        rentalFilter(start: const TimeOfDay(hour: 23, minute: 0))
            .matchesEvent('place1', index, doc: nightPlaceDoc()),
        isTrue,
      );
      expect(
        rentalFilter(start: const TimeOfDay(hour: 15, minute: 0))
            .matchesEvent('place1', index, doc: nightPlaceDoc()),
        isFalse,
      );
    });
  });

  group('두 컬렉션은 여전히 섞이지 않는다', () {
    test('매장 이벤트는 공간 색인에 들어가지 않는다', () {
      final venue = promo(collection: PlaceEventIndex.placeCollection);
      final rentalIndex = PlaceEventIndex.fromPromotions(
        [venue],
        now: now,
        collection: PlaceEventIndex.rentalCollection,
      );
      expect(rentalIndex.has('place1'), isFalse);
      expect(rentalIndex.byPlace, isEmpty);
    });

    test('공간 이벤트는 매장 색인에 들어가지 않는다', () {
      final rental = promo(collection: PlaceEventIndex.rentalCollection);
      final venueIndex = PlaceEventIndex.fromPromotions([rental], now: now);
      expect(venueIndex.has('place1'), isFalse);
      expect(venueIndex.byPlace, isEmpty);
    });
  });

  group('색인 자체의 계약', () {
    test('조건이 없으면 예전 그대로 has()와 같다', () {
      final index = PlaceEventIndex.fromPromotions([
        promo(isAlways: true, startTime: '22:00', endTime: '02:00'),
      ], now: now);
      expect(index.hasMatching('place1'), index.has('place1'));
      expect(index.hasMatching('place1'), isTrue);
      expect(index.hasMatching('없는곳'), isFalse);
    });

    test('한 매장의 이벤트가 여럿이면 하나만 맞아도 남는다', () {
      final index = PlaceEventIndex.fromPromotions([
        promo(id: 'e1', isAlways: true, startTime: '18:00', endTime: '21:00'),
        promo(id: 'e2', isAlways: true, startTime: '22:00', endTime: '02:00'),
      ], now: now);
      expect(index.byPlace['place1'], hasLength(2));
      expect(
        index.hasMatching(
          'place1',
          start: const TimeOfDay(hour: 23, minute: 0),
        ),
        isTrue,
      );
      expect(
        index.hasMatching(
          'place1',
          start: const TimeOfDay(hour: 4, minute: 0),
        ),
        isFalse,
      );
    });

    test('시각만 바뀌어도 색인이 다시 만들어진다 — 낡은 시각으로 거르지 않는다', () {
      final before = PlaceEventIndex.fromPromotions([
        promo(isAlways: true, startTime: '22:00', endTime: '02:00'),
      ], now: now);
      final after = PlaceEventIndex.fromPromotions([
        promo(isAlways: true, startTime: '20:00', endTime: '02:00'),
      ], now: now);
      // id 집합은 같지만 판정에 쓰는 값이 달라졌다.
      expect(before.placeIds, after.placeIds);
      expect(before.sameAs(after), isFalse);
    });

    test('순서만 다르면 같은 색인이다 — 스크롤이 튀지 않는다', () {
      // 지문을 순서대로 이어 붙이면 이 계약이 깨진다(스트림은 순서를 보장하지
      // 않는다). 정렬해서 이어 붙이는 이유가 이것이다.
      final a = PlaceEventIndex.fromPromotions([
        promo(id: 'e1', placeId: 'p1', isAlways: true),
        promo(id: 'e2', placeId: 'p2', isAlways: true),
      ], now: now);
      final b = PlaceEventIndex.fromPromotions([
        promo(id: 'e2', placeId: 'p2', isAlways: true),
        promo(id: 'e1', placeId: 'p1', isAlways: true),
      ], now: now);
      expect(a.sameAs(b), isTrue);
    });

    test('아무것도 안 바뀌면 다시 그리지 않는다', () {
      PlaceEventIndex build() => PlaceEventIndex.fromPromotions([
        promo(isAlways: true, startTime: '22:00', endTime: '02:00'),
      ], now: now);
      expect(build().sameAs(build()), isTrue);
    });
  });
}

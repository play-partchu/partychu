// 🧭 **고정형 장소 기준선** — 4단계(이동형 지도 연동) 전에 못 박는 현재 동작.
//
// 이 파일은 새 기능을 검증하지 않는다. **이동형을 붙이면서 고정형 판정이
// 조용히 달라지는 것**을 잡으려고 둔다. 그래서 단정은 전부 "지금 이렇다"이고,
// 바뀌는 순간 깨지는 것이 목적이다.
//
// 4단계에서 알게 된 구조(바꾸지 않는다):
//
//  · 지도 핀 좌표는 문서의 평면 `latitude`/`longitude` 하나다.
//    (0,0)이면 핀을 올리지 않는다([MapListing.from]).
//  · 지도의 플레이스 조건은 목록과 **같은 함수**([EventFilter.matchesDiscovery])
//    를 쓰는데, 그 함수에는 **영업시간 게이트가 없다.** 날짜·시간으로 영업
//    여부를 거르는 것은 목록 화면(`main_screen`의 `_opensOn`)에만 있다.
//    → 즉 **지금 지도는 고정형 장소를 날짜·시간으로 거르지 않는다.**
//      이것을 고치는 것은 4단계의 일이 아니다(고정형 판정 변경 금지).
//  · `MapListing.key`는 `kind:docId`다 — 마커 id와 중복 제거가 이 값을 쓴다.

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/event_filter.dart';
import 'package:party_app/models/map_listing.dart';
import 'package:party_app/models/place_weekly_hours.dart';

/// 2026-10-12는 월요일.
final monday = DateTime(2026, 10, 12);
final tuesday = DateTime(2026, 10, 13);

/// 옛 고정형 플레이스 문서 — 운영 Firestore에서 확인한 필드 모양 그대로.
Map<String, dynamic> fixedPlaceDoc({
  double lat = 37.5665,
  double lng = 126.9780,
  Map<String, dynamic>? weeklyHours,
  String category = '술집',
  bool includeMobileFields = false,
}) => {
  'name': '혼술바',
  'placeCategory': category,
  'latitude': lat,
  'longitude': lng,
  'address': '서울 중구',
  'isActive': true,
  'placeWeeklyHours': ?weeklyHours,
  if (includeMobileFields) 'isMobilePlace': false,
};

Map<String, dynamic> hoursMap({
  String open = '11:00',
  String close = '22:00',
  List<String> closedDays = const [],
}) => {
  for (final day in PlaceWeeklyHours.weekdays)
    day: {
      'open': open,
      'close': close,
      'isClosed': closedDays.contains(day),
      'is24Hours': false,
      'hasBreakTime': false,
    },
};

void main() {
  test('테스트가 쓰는 날짜의 요일', () {
    expect(monday.weekday, DateTime.monday);
  });

  group('기준선 — 핀 좌표는 문서의 평면 필드 하나', () {
    test('latitude/longitude를 읽는다', () {
      final item = MapListing.from(
        MapListingKind.place,
        'abc',
        fixedPlaceDoc(lat: 37.1, lng: 127.2),
      );
      expect(item, isNotNull);
      expect(item!.lat, 37.1);
      expect(item.lng, 127.2);
    });

    test('lat/lng(짧은 이름)는 읽지 않는다 — 장소대여 스키마와 섞지 않는다', () {
      final item = MapListing.from(MapListingKind.place, 'abc', {
        'name': '어딘가',
        'lat': 37.1,
        'lng': 127.2,
      });
      expect(item, isNull, reason: '평면 latitude/longitude 외의 필드를 읽기 시작했다');
    });

    test('좌표가 0이면 핀을 올리지 않는다', () {
      expect(
        MapListing.from(MapListingKind.place, 'a', fixedPlaceDoc(lat: 0)),
        isNull,
      );
      expect(
        MapListing.from(MapListingKind.place, 'a', fixedPlaceDoc(lng: 0)),
        isNull,
      );
      expect(MapListing.from(MapListingKind.place, 'a', {'name': 'x'}), isNull);
    });

    test('key는 kind:docId다 — 마커 id와 중복 제거가 이 값을 쓴다', () {
      final item = MapListing.from(
        MapListingKind.place,
        'abc123',
        fixedPlaceDoc(),
      )!;
      expect(item.key, 'place:abc123');
    });

    test('종류가 다르면 키가 갈린다', () {
      final place = MapListing.from(
        MapListingKind.place,
        'same',
        fixedPlaceDoc(),
      )!;
      final rental = MapListing.from(MapListingKind.rental, 'same', {
        'name': '공간',
        'latitude': 37.5,
        'longitude': 127.0,
      })!;
      expect(place.key, isNot(rental.key));
    });

    test('원본 문서를 그대로 들고 다닌다 — 상세 화면이 같은 필드를 읽는다', () {
      final doc = fixedPlaceDoc();
      final item = MapListing.from(MapListingKind.place, 'abc', doc)!;
      expect(item.docId, 'abc');
      expect(item.data, same(doc));
    });
  });

  group('기준선 — 지도의 플레이스 조건에는 영업시간 게이트가 없다', () {
    // ⚠️ 이것이 4단계에서 가장 조심할 지점이다. 지도는 목록과 같은
    //    [EventFilter.matchesDiscovery]만 부르고, 그 함수는 날짜·시간으로
    //    영업 여부를 보지 않는다. 이동형을 붙이면서 여기에 게이트를 더하면
    //    **운영시간이 없는 기존 고정형 장소가 지도에서 통째로 사라진다.**

    test('날짜를 골라도 운영시간 없는 고정형 장소가 통과한다', () {
      final f = EventFilter(visitDates: {monday});
      expect(
        f.matchesDiscovery(fixedPlaceDoc(), now: monday),
        isTrue,
        reason: '지도의 공용 판정에 영업시간 게이트가 생겼다 — 옛 문서가 지도에서 사라진다',
      );
    });

    test('시간을 골라도 통과한다', () {
      final f = EventFilter(
        startTime: const TimeOfDay(hour: 3, minute: 0),
        endTime: const TimeOfDay(hour: 5, minute: 0),
      );
      expect(f.matchesDiscovery(fixedPlaceDoc(), now: monday), isTrue);
    });

    test('그 요일이 휴무로 적혀 있어도 공용 판정은 통과시킨다', () {
      final f = EventFilter(visitDates: {monday});
      final doc = fixedPlaceDoc(
        weeklyHours: hoursMap(closedDays: const ['월']),
      );
      expect(
        f.matchesDiscovery(doc, now: monday),
        isTrue,
        reason: '공용 판정이 휴무를 보기 시작했다 — 목록과 지도의 역할이 섞였다',
      );
    });

    test('업종 조건은 예전 그대로 걸린다', () {
      expect(
        EventFilter(categories: {'술집'}).matchesDiscovery(fixedPlaceDoc()),
        isTrue,
      );
      expect(
        EventFilter(categories: {'카페·디저트'}).matchesDiscovery(fixedPlaceDoc()),
        isFalse,
      );
    });

    test('업종이 없는 옛 문서도 조건 없이는 통과한다', () {
      expect(
        EventFilter().matchesDiscovery({'name': '옛 가게'}),
        isTrue,
        reason: 'placeCategory가 없는 운영 문서(4건 중 1건)가 빠지면 안 된다',
      );
    });
  });

  group('기준선 — 영업시간 해석은 기존 정본 그대로', () {
    test('placeWeeklyHours를 읽고, 없으면 weeklyOperatingHours로 폴백한다', () {
      expect(
        PlaceWeeklyHours.fromPlaceDoc({'placeWeeklyHours': hoursMap()}),
        isNotNull,
      );
      expect(
        PlaceWeeklyHours.fromPlaceDoc({'weeklyOperatingHours': hoursMap()}),
        isNotNull,
      );
    });

    test('둘 다 없으면 null — "여는지 알 수 없는 곳"이다', () {
      expect(PlaceWeeklyHours.fromPlaceDoc(fixedPlaceDoc()), isNull);
    });

    test('요일당 칸이 하나다 — 이동형이 이 구조를 쓸 수 없는 이유', () {
      final hours = PlaceWeeklyHours.fromPlaceDoc({
        'placeWeeklyHours': hoursMap(),
      })!;
      final segments = hours.openSegmentsAround(monday);
      // 월요일 11:00~22:00 하나뿐(앞뒤 날 구간이 함께 오지만 월요일에 걸치는
      // 것은 하나다).
      expect(
        segments.where((s) => s.start.day == monday.day),
        hasLength(1),
        reason: '요일당 여러 구간이 생겼다 — PlaceWeeklyHours 구조가 바뀌었다',
      );
    });

    test('자정 넘김은 앞뒤 날을 함께 모아 판정한다', () {
      final hours = PlaceWeeklyHours.fromPlaceDoc({
        'placeWeeklyHours': hoursMap(open: '22:00', close: '02:00'),
      })!;
      final segments = hours.openSegmentsAround(tuesday);
      expect(
        segments.any(
          (s) => s.start.isBefore(tuesday) && s.end.isAfter(tuesday),
        ),
        isTrue,
        reason: '전날 밤에 시작한 구간을 더 이상 모으지 않는다',
      );
    });
  });

  group('기준선 — 이동형 필드가 없는 문서는 고정형이다', () {
    test('isMobilePlace가 아예 없으면 이동형 해석을 하지 않는다', () {
      // 운영 문서 4건 전부 이 상태다(mobileSchedule 0/4).
      expect(fixedPlaceDoc().containsKey('isMobilePlace'), isFalse);
      expect(fixedPlaceDoc().containsKey('mobileSchedule'), isFalse);
    });

    test('isMobilePlace: false가 적혀 있어도 고정형이다', () {
      final doc = fixedPlaceDoc(includeMobileFields: true);
      expect(doc['isMobilePlace'], isFalse);
      // 좌표는 여전히 문서에서 읽는다.
      final item = MapListing.from(MapListingKind.place, 'a', doc)!;
      expect(item.lat, 37.5665);
    });
  });
}

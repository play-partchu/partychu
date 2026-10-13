// 🔧 통합 검수에서 찾은 **사용자 노출 오류 두 건**의 수정.
//
//  ① 목록 탭이 이동형을 `placeWeeklyHours`(등록 운영시간)로 걸러 냈다.
//     → 이제 `mobileSchedule`이 정본이다. 지도와 목록이 같은 답을 낸다.
//
//  ② 지도 하단 '이 근처' 카드가 **기준 주소**를 보여 줬다(핀은 홍대, 카드는
//     '서울 중구'). → 이제 그 날 자리로 바꾼 **사본**을 받는다.
//
// 고정형 장소의 판정·표시는 둘 다 **한 글자도 바뀌지 않아야** 한다.

import 'dart:io';


import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/map_listing.dart';
import 'package:party_app/models/mobile_place_schedule.dart';
import 'package:party_app/models/place_weekly_hours.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _codeOnly(String path) => _read(path)
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .split('\n')
    .map((line) {
      final c = line.indexOf('//');
      return c < 0 ? line : line.substring(0, c);
    })
    .join('\n');

const _kMain = 'lib/screens/main_screen.dart';
const _kMapScreen = 'lib/screens/map_screen.dart';
const _kListing = 'lib/models/map_listing.dart';

/// 2026-10-12 = 월요일.
final monday = DateTime(2026, 10, 12);
final tuesday = DateTime(2026, 10, 13);
final thursday = DateTime(2026, 10, 15);
final friday = DateTime(2026, 10, 16);
final saturday = DateTime(2026, 10, 17);

ScheduledStop stopAt(String name, double lat, double lng) => ScheduledStop(
  placeName: name,
  address: '서울 $name구 어딘가 1',
  roadAddress: '서울 마포구 양화로 160',
  latitude: lat,
  longitude: lng,
);

final hongdae = ScheduledStop(
  placeName: '홍대입구역',
  address: '서울 마포구 동교동 1',
  roadAddress: '서울 마포구 양화로 160',
  latitude: 37.5563,
  longitude: 126.9236,
);
final gangnam = stopAt('강남', 37.4979, 127.0276);

ScheduleSlot slot(ScheduledStop stop, [String s = '11:00', String e = '20:00']) =>
    ScheduleSlot(stop: stop, startTime: s, endTime: e);

/// 등록 화면이 저장하는 모양 — **운영시간이 함께 남아 있다**(09:00~18:00).
/// 실제 영업은 11:00~20:00이라 둘이 어긋난 상태가 저장된다.
Map<String, dynamic> mobileDoc(MobilePlaceSchedule schedule) => {
  'name': '테스트 푸드트럭',
  'placeCategory': '맛집',
  'address': '서울 중구 어딘가',
  'location': '서울 중구 어딘가 (사무실)',
  'latitude': 37.5665,
  'longitude': 126.9780,
  'openTime': '09:00',
  'closeTime': '18:00',
  'isOpen24Hours': false,
  'placeWeeklyHours': {
    for (final day in PlaceWeeklyHours.weekdays)
      day: {
        'open': '09:00',
        'close': '18:00',
        'isClosed': false,
        'is24Hours': false,
        'hasBreakTime': false,
      },
  },
  MobilePlaceSchedule.isMobileFieldName: true,
  MobilePlaceSchedule.fieldName: schedule.toMap(),
};

final fixedDoc = <String, dynamic>{
  'name': '혼술바',
  'address': '서울 중구 명동길 1',
  'latitude': 37.5665,
  'longitude': 126.9780,
  'openTime': '09:00',
  'closeTime': '18:00',
};

final example = const MobilePlaceSchedule()
    .withRegular(DateTime.monday, slot(hongdae))
    .withRegular(DateTime.tuesday, slot(gangnam))
    .withClosedWeekday(DateTime.thursday, true);

void main() {
  group('① 목록 탭 판정 — mobileSchedule이 정본', () {
    final schedule = MobilePlaceSchedule.ofPlace(mobileDoc(example))!;

    test('선택 날짜에 영업하면 통과, 아니면 빠진다', () {
      expect(schedule.openingMatching(date: monday), isNotNull);
      expect(schedule.openingMatching(date: tuesday), isNotNull);
      expect(schedule.openingMatching(date: friday), isNull);
    });

    test('휴무일에는 빠진다', () {
      expect(schedule.openingMatching(date: thursday), isNull);
    });

    test('⚠️ 등록 운영시간(09:00)이 아니라 실제 일정(11:00)으로 판정한다', () {
      // 10시 — 운영시간으로는 영업 중이지만 실제로는 아직 안 열었다.
      expect(
        schedule.openingMatching(
          date: monday,
          moment: DateTime(2026, 10, 12, 10),
        ),
        isNull,
        reason: '등록 운영시간으로 판정하고 있다 — 목록과 지도가 갈린다',
      );
      // 19시 — 운영시간으로는 닫혔지만 실제로는 영업 중이다.
      expect(
        schedule.openingMatching(
          date: monday,
          moment: DateTime(2026, 10, 12, 19),
        ),
        isNotNull,
      );
    });

    test('시각 하나 — 그 순간 영업 중인가', () {
      expect(
        schedule
            .openingMatching(
              date: monday,
              moment: DateTime(2026, 10, 12, 13),
            )
            ?.stop,
        hongdae,
      );
      expect(
        schedule.openingMatching(
          date: monday,
          moment: DateTime(2026, 10, 12, 22),
        ),
        isNull,
      );
    });

    test('구간 전체 포함 — 고정형과 같은 의미', () {
      // 12~15시는 11~20시 안에 통째로 들어간다.
      expect(
        schedule.openingMatching(
          date: monday,
          windowStart: DateTime(2026, 10, 12, 12),
          windowEnd: DateTime(2026, 10, 12, 15),
          requireFullWindow: true,
        ),
        isNotNull,
      );
      // 18~22시는 20시에 끊긴다 → 전체 포함 실패.
      expect(
        schedule.openingMatching(
          date: monday,
          windowStart: DateTime(2026, 10, 12, 18),
          windowEnd: DateTime(2026, 10, 12, 22),
          requireFullWindow: true,
        ),
        isNull,
      );
    });

    test('구간 일부 겹침', () {
      expect(
        schedule.openingMatching(
          date: monday,
          windowStart: DateTime(2026, 10, 12, 18),
          windowEnd: DateTime(2026, 10, 12, 22),
        ),
        isNotNull,
      );
      // 맞닿기만 한 것은 겹침이 아니다.
      expect(
        schedule.openingMatching(
          date: monday,
          windowStart: DateTime(2026, 10, 12, 20),
          windowEnd: DateTime(2026, 10, 12, 22),
        ),
        isNull,
      );
    });

    test('예외 일정이 반영된다', () {
      final withException = example.upsertException(
        ScheduleException(
          id: 'e',
          dateKey: ScheduleException.dateKeyOf(thursday),
          mode: ScheduleExceptionMode.replaceDay,
          slot: slot(gangnam, '10:00', '14:00'),
        ),
      );
      final s = MobilePlaceSchedule.ofPlace(mobileDoc(withException))!;
      // 원래 휴무였던 목요일이 영업일이 된다.
      expect(s.openingMatching(date: thursday)?.stop, gangnam);
      expect(
        s.openingMatching(date: thursday, moment: DateTime(2026, 10, 15, 11)),
        isNotNull,
      );
      expect(
        s.openingMatching(date: thursday, moment: DateTime(2026, 10, 15, 16)),
        isNull,
      );
    });

    test('오늘만 영업하는 일정이 반영되고 내일에는 번지지 않는다', () {
      final s = MobilePlaceSchedule.ofPlace(
        mobileDoc(
          example.withTodayStop(
            monday,
            stop: gangnam,
            startTime: '15:00',
            endTime: '22:00',
          ),
        ),
      )!;
      expect(s.openingMatching(date: monday)?.stop, gangnam);
      expect(
        s.openingMatching(date: monday, moment: DateTime(2026, 10, 12, 21)),
        isNotNull,
        reason: '오늘만 바꾼 시간이 반영되지 않았다',
      );
      // 화요일은 정기 그대로.
      expect(s.openingMatching(date: tuesday)?.stop, gangnam);
      expect(
        s.openingMatching(date: tuesday, moment: DateTime(2026, 10, 13, 21)),
        isNull,
        reason: '오늘 변경이 내일까지 번졌다',
      );
    });

    test('자정 넘김 — 다음 날 새벽 조건에 걸린다', () {
      final s = const MobilePlaceSchedule().withRegular(
        DateTime.friday,
        slot(gangnam, '22:00', '02:00'),
      );
      expect(
        s.openingMatching(date: saturday, moment: DateTime(2026, 10, 17, 1)),
        isNotNull,
      );
      expect(
        s.openingMatching(date: saturday, moment: DateTime(2026, 10, 17, 5)),
        isNull,
      );
    });

    test('조건이 없으면 openingFor와 같은 답이다', () {
      for (final date in [monday, tuesday, thursday, friday]) {
        expect(
          schedule.openingMatching(date: date)?.stop,
          schedule.openingFor(date: date)?.stop,
          reason: '$date — 두 경로의 답이 갈렸다',
        );
      }
    });
  });

  group('① 목록 화면 연결 — 고정형 판정은 그대로', () {
    final main = _codeOnly(_kMain);

    test('이동형 분기가 isOpen24Hours·운영시간보다 먼저 온다', () {
      final opensOn = main.substring(main.indexOf('bool _opensOn('));
      final mobileAt = opensOn.indexOf('MobilePlaceSchedule.ofPlace(data)');
      final h24At = opensOn.indexOf("data['isOpen24Hours'] == true");
      final hoursAt = opensOn.indexOf('_eventWeeklyHours(data)');
      expect(mobileAt, greaterThan(-1), reason: '이동형 분기가 없다');
      expect(
        mobileAt,
        lessThan(h24At),
        reason: 'isOpen24Hours가 먼저 와서 쉬는 트럭이 통과한다',
      );
      expect(
        mobileAt,
        lessThan(hoursAt),
        reason: '운영시간이 먼저 와서 등록 시간으로 걸러진다',
      );
    });

    test('판정을 모델에 넘긴다 — 시간 비교를 화면에 복사하지 않았다', () {
      expect(main, contains('mobile.openingMatching('));
      final opensOn = main.substring(
        main.indexOf('bool _opensOn('),
        main.indexOf('PlaceWeeklyHours? _eventWeeklyHours('),
      );
      final mobileBranch = opensOn.substring(
        opensOn.indexOf('MobilePlaceSchedule.ofPlace(data)'),
        opensOn.indexOf("data['isOpen24Hours'] == true"),
      );
      expect(
        RegExp(r'\b1440\b').hasMatch(mobileBranch),
        isFalse,
        reason: '이동형 분기가 시간 계산을 직접 하고 있다',
      );
      expect(mobileBranch.contains('openSegmentsAround'), isFalse);
    });

    test('고정형 경로가 그대로 남아 있다', () {
      expect(main, contains("if (data['isOpen24Hours'] == true) return true;"));
      // 운영시간을 못 읽은 고정형 문서는 날짜 조건에서 빠진다(기존 규칙).
      expect(main, contains('if (hours == null) return false;'));
      expect(main, contains('final merged = hours.openSegmentsAround(date);'));
      expect(
        main,
        contains('if (f.openMode == PlaceAvailabilityMode.partial) {'),
      );
      expect(
        main,
        contains('PlaceWeeklyHours? _eventWeeklyHours(Map<String, dynamic> data) =>'),
      );
    });

    test('지금 영업 중 조건도 이동형을 따로 본다', () {
      expect(main, contains('mobileNow.openingAt(now)'));
      // 고정형 경로는 else 안에 그대로.
      expect(main, contains('hours.statusAt(now) != PlaceHoursStatus.open'));
    });

    test('시간만 고른 경로에서 이동형의 isOpen24Hours를 무시한다', () {
      expect(
        main,
        contains(
          'if (MobilePlaceSchedule.ofPlace(data) == null &&\n'
          "        data['isOpen24Hours'] == true) {",
        ),
      );
    });

    test('본인확인·소셜 로그인·채팅 코드를 건드리지 않았다', () {
      for (final untouched in ['signInWith', 'AppReviewLogin', 'niceIntc']) {
        expect(main.contains(untouched), isFalse, reason: '$untouched 가 들어왔다');
      }
    });
  });

  group('② 지도 카드 — 그 날 자리를 보여 준다', () {
    MapListing pinOn(DateTime date, {required MobilePlaceSchedule schedule}) {
      final doc = mobileDoc(schedule);
      final base = MapListing.from(MapListingKind.place, 'truck-1', doc)!;
      return base.atStop(schedule.openingOn(date)!);
    }

    test('이동형 카드 데이터는 그 날 장소명·주소를 쓴다', () {
      final card = pinOn(monday, schedule: example).cardData(now: monday);
      // 날짜 + 장소명 — 날짜를 여럿 고르면 카드가 여러 장 뜨므로 구분이 필요하다.
      expect(card['address'], '오늘 · 홍대입구역');
      expect(card['location'], '서울 마포구 양화로 160');
      expect(
        card['address'],
        isNot('서울 중구 어딘가'),
        reason: '기준 주소가 그대로 남았다',
      );
    });

    test('영업시간도 그 날 것으로 바뀐다', () {
      final card = pinOn(monday, schedule: example).cardData(now: monday);
      expect(card['openTime'], '11:00');
      expect(card['closeTime'], '20:00');
      expect(card['isOpen24Hours'], isFalse);
    });

    test('날짜가 바뀌면 카드 주소도 함께 바뀐다', () {
      expect(
        pinOn(monday, schedule: example).cardData(now: monday)['address'],
        '오늘 · 홍대입구역',
      );
      expect(
        pinOn(tuesday, schedule: example).cardData(now: monday)['address'],
        '10/13 (화) · 강남',
      );
    });

    test('⚠️ 원본 문서를 변형하지 않는다', () {
      final doc = mobileDoc(example);
      final base = MapListing.from(MapListingKind.place, 'truck-1', doc)!;
      final pin = base.atStop(example.openingOn(monday)!);
      final card = pin.cardData(now: monday);

      // 날짜 + 장소명 — 날짜를 여럿 고르면 카드가 여러 장 뜨므로 구분이 필요하다.
      expect(card['address'], '오늘 · 홍대입구역');
      // 원본은 그대로.
      expect(doc['address'], '서울 중구 어딘가');
      expect(doc['openTime'], '09:00');
      expect(pin.data['address'], '서울 중구 어딘가');
      expect(identical(card, doc), isFalse, reason: '같은 맵을 돌려주고 있다');
    });

    test('핀 좌표와 카드가 가리키는 자리가 같다', () {
      final pin = pinOn(monday, schedule: example);
      final card = pin.cardData(now: monday);
      // 카드에 좌표 필드는 없지만, 주소가 그 좌표의 자리여야 한다.
      expect(pin.lat, hongdae.latitude);
      expect(pin.lng, hongdae.longitude);
      expect(card['address'], '오늘 · ${hongdae.placeName}');
      expect(card['location'], hongdae.roadAddress);
      // 마커 탭 카드와 같은 말을 한다.
      expect(pin.shortAddress, hongdae.placeName);
    });

    test('장소명이 없으면 주소를 쓴다', () {
      final noName = const MobilePlaceSchedule().withRegular(
        DateTime.monday,
        slot(
          const ScheduledStop(
            roadAddress: '서울 마포구 양화로 160',
            latitude: 37.55,
            longitude: 126.92,
          ),
        ),
      );
      expect(
        pinOn(monday, schedule: noName).cardData(now: monday)['address'],
        '오늘 · 서울 마포구 양화로 160',
      );
    });

    test('고정형 카드 데이터는 원본 그대로다 — 같은 인스턴스', () {
      final base = MapListing.from(MapListingKind.place, 'bar-1', fixedDoc)!;
      expect(base.opening, isNull);
      expect(
        identical(base.cardData(now: monday), fixedDoc),
        isTrue,
        reason: '고정형에 사본이 생겼다 — 불필요한 변경이다',
      );
      expect(base.cardData(now: monday)['address'], '서울 중구 명동길 1');
      expect(base.cardData(now: monday)['openTime'], '09:00');
    });

    test('파티·장소대여·공공 축제도 원본 그대로다', () {
      final rental = MapListing.from(MapListingKind.rental, 'r1', {
        'name': '공간',
        'address': '서울 강남구',
        'latitude': 37.5,
        'longitude': 127.0,
      })!;
      expect(identical(rental.cardData(now: monday), rental.data), isTrue);
    });
  });

  group('② 지도 화면 연결', () {
    final mapScreen = _codeOnly(_kMapScreen);

    test("'이 근처' 카드가 cardData를 받는다", () {
      expect(mapScreen, contains('place: item.cardData(),'));
      expect(
        mapScreen.contains('place: item.data,'),
        isFalse,
        reason: '아직 원본 문서를 카드에 넘기는 곳이 있다',
      );
    });

    test('카드 탭도 선택 날짜를 상세로 넘긴다', () {
      // 카드 onTap은 _openDetail(item)으로 모이고, 그 안에서 focusDate를 넘긴다.
      expect(mapScreen, contains('focusDate: item.opening?.start,'));
      expect(mapScreen, contains('void _openDetail(MapListing item)'));
    });

    test('상세로는 여전히 원본 문서를 넘긴다 — 카드 사본이 새지 않는다', () {
      expect(mapScreen, contains('eventData: item.data,'));
    });
  });

  group('② cardData 구현 — 변형 금지가 코드로도 지켜진다', () {
    final listing = _codeOnly(_kListing);

    test('사본을 만들어 돌려준다', () {
      expect(listing, contains('return {\n      ...data,'));
    });

    test('원본 맵에 대입하지 않는다', () {
      for (final forbidden in [
        "data['address'] =",
        "data['location'] =",
        "data['openTime'] =",
        'data.addAll(',
        'data.remove(',
      ]) {
        expect(
          listing.contains(forbidden),
          isFalse,
          reason: '원본 문서를 변형한다 — $forbidden',
        );
      }
    });

    test('고정형은 이른 반환으로 원본을 그대로 준다', () {
      expect(listing, contains('if (stop == null) return data;'));
    });
  });
}

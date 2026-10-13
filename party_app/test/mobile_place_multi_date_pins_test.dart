// 🗺 **날짜 복수 선택** — 고른 날짜마다 그 날의 영업 자리에 핀 하나.
//
//     월 선택        → 홍대 1개
//     월+화          → 홍대·강남 2개
//     월+화+수       → 홍대·강남·여의도 3개
//     목(휴무)       → 없음
//
// 불변식은 그대로다: **한 업체는 하루에 한 장소.** 핀이 여러 개가 되는 것은
// 날짜가 여러 개일 때뿐이고, 날짜 하나에는 언제나 0개 또는 1개다.
//
// 이 파일이 지키는 것:
//   · 고른 날짜만 — 안 고른 날짜의 핀은 만들지 않는다
//   · 휴무·일정 없는 날짜는 건너뛴다
//   · 날짜별 **핀 ID가 충돌하지 않는다**
//   · 같은 좌표에서 다른 날에 영업해도 **날짜 정보가 사라지지 않는다**
//   · 자정 넘김 영업은 **핀 하나**로 남는다(두 날짜 질의에 모두 걸리지만)
//   · 카드에 날짜·장소명·영업시간이 함께 뜬다
//   · 고정형은 날짜를 몇 개 골라도 핀 하나(예전 그대로)

import 'dart:io';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/map_listing.dart';
import 'package:party_app/models/mobile_place_pins.dart';
import 'package:party_app/models/mobile_place_schedule.dart';

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

const _kMapScreen = 'lib/screens/map_screen.dart';
const _kPins = 'lib/models/mobile_place_pins.dart';

/// 2026-10-12 = 월요일.
final monday = DateTime(2026, 10, 12);
final tuesday = DateTime(2026, 10, 13);
final wednesday = DateTime(2026, 10, 14);
final thursday = DateTime(2026, 10, 15);
final friday = DateTime(2026, 10, 16);
final saturday = DateTime(2026, 10, 17);
final sunday = DateTime(2026, 10, 18);

ScheduledStop stopAt(String name, double lat, double lng) => ScheduledStop(
  placeName: name,
  address: '서울 $name로 1',
  roadAddress: '서울 $name로 1',
  latitude: lat,
  longitude: lng,
);

final hongdae = stopAt('홍대', 37.5563, 126.9236);
final gangnam = stopAt('강남', 37.4979, 127.0276);
final yeouido = stopAt('여의도', 37.5219, 126.9245);

ScheduleSlot slot(ScheduledStop stop, [String s = '11:00', String e = '20:00']) =>
    ScheduleSlot(stop: stop, startTime: s, endTime: e);

/// 월 홍대 / 화 강남 / 수 여의도 / 목 휴무.
final example = const MobilePlaceSchedule()
    .withRegular(DateTime.monday, slot(hongdae))
    .withRegular(DateTime.tuesday, slot(gangnam))
    .withRegular(DateTime.wednesday, slot(yeouido))
    .withClosedWeekday(DateTime.thursday, true);

Map<String, dynamic> mobileDoc(MobilePlaceSchedule schedule) => {
  'name': '테스트 푸드트럭',
  'placeCategory': '맛집',
  'address': '서울 중구 어딘가',
  'latitude': 37.5665,
  'longitude': 126.9780,
  'openTime': '09:00',
  'closeTime': '18:00',
  MobilePlaceSchedule.isMobileFieldName: true,
  MobilePlaceSchedule.fieldName: schedule.toMap(),
};

final fixedDoc = <String, dynamic>{
  'name': '혼술바',
  'address': '서울 중구 명동길 1',
  'latitude': 37.5665,
  'longitude': 126.9780,
};

/// 지도가 하는 일 — `_resolvePins`와 같은 네 줄이다.
List<MapListing> pinsFor(
  Map<String, dynamic> doc, {
  Set<DateTime> dates = const {},
  TimeOfDay? startTime,
  TimeOfDay? endTime,
  required DateTime now,
  String docId = 'truck-1',
}) {
  final base = MapListing.from(MapListingKind.place, docId, doc);
  if (base == null) return const [];
  final resolved = MobilePlacePins.resolve(
    doc,
    dates: dates,
    startTime: startTime,
    endTime: endTime,
    now: now,
  );
  if (!resolved.isMobile) return [base];
  return [for (final o in resolved.openings) base.atStop(o)];
}

void main() {
  test('테스트가 쓰는 날짜의 요일', () {
    expect(monday.weekday, DateTime.monday);
    expect(thursday.weekday, DateTime.thursday);
  });

  group('고른 날짜마다 핀 하나', () {
    final doc = mobileDoc(example);

    test('날짜 1개 → 핀 1개', () {
      final pins = pinsFor(doc, dates: {monday}, now: monday);
      expect(pins, hasLength(1));
      expect(pins.single.lng, hongdae.longitude);
    });

    test('날짜 2개 → 핀 2개(홍대·강남)', () {
      final pins = pinsFor(doc, dates: {monday, tuesday}, now: monday);
      expect(pins, hasLength(2));
      expect(pins.map((p) => p.lng), [hongdae.longitude, gangnam.longitude]);
    });

    test('날짜 3개 → 핀 3개(홍대·강남·여의도)', () {
      final pins = pinsFor(
        doc,
        dates: {monday, tuesday, wednesday},
        now: monday,
      );
      expect(pins, hasLength(3));
      expect(pins.map((p) => p.lng), [
        hongdae.longitude,
        gangnam.longitude,
        yeouido.longitude,
      ]);
    });

    test('날짜 5개(최대) — 영업하는 날만 핀이 된다', () {
      // 월·화·수 영업 / 목 휴무 / 금 일정 없음 → 3개.
      final pins = pinsFor(
        doc,
        dates: {monday, tuesday, wednesday, thursday, friday},
        now: monday,
      );
      expect(pins, hasLength(3));
    });

    test('영업 시작 순으로 나온다', () {
      final pins = pinsFor(
        doc,
        dates: {wednesday, monday, tuesday},
        now: monday,
      );
      expect(pins.map((p) => p.openingDate), [monday, tuesday, wednesday]);
    });

    test('휴무일만 고르면 핀이 없다', () {
      expect(pinsFor(doc, dates: {thursday}, now: monday), isEmpty);
    });

    test('일정 없는 날짜만 고르면 핀이 없다', () {
      expect(pinsFor(doc, dates: {friday, saturday, sunday}, now: monday), isEmpty);
    });

    test('휴무일이 섞여 있어도 그 날짜만 빠진다', () {
      final pins = pinsFor(doc, dates: {monday, thursday}, now: monday);
      expect(pins, hasLength(1));
      expect(pins.single.openingDate, monday);
    });

    test('고르지 않은 날짜의 핀은 만들지 않는다', () {
      final pins = pinsFor(doc, dates: {tuesday}, now: monday);
      expect(pins.map((p) => p.openingDate), [tuesday]);
      expect(
        pins.any((p) => p.lng == hongdae.longitude),
        isFalse,
        reason: '고르지 않은 월요일 핀이 생겼다',
      );
    });

    test('날짜를 고르지 않으면 오늘 기준 핀 하나', () {
      expect(pinsFor(doc, now: monday).single.lng, hongdae.longitude);
      expect(pinsFor(doc, now: tuesday).single.lng, gangnam.longitude);
      expect(pinsFor(doc, now: thursday), isEmpty);
    });
  });

  group('선택 날짜 변경 시 이전 핀 제거', () {
    final doc = mobileDoc(example);

    test('월→화로 바꾸면 홍대 핀이 사라진다', () {
      final before = pinsFor(doc, dates: {monday}, now: monday);
      final after = pinsFor(doc, dates: {tuesday}, now: monday);
      expect(before.single.lng, hongdae.longitude);
      expect(after.single.lng, gangnam.longitude);
      expect(after.any((p) => p.key == before.single.key), isFalse);
    });

    test('월+화 → 화만으로 줄이면 홍대 핀이 사라진다', () {
      final before = pinsFor(doc, dates: {monday, tuesday}, now: monday);
      final after = pinsFor(doc, dates: {tuesday}, now: monday);
      expect(before, hasLength(2));
      expect(after, hasLength(1));
      final goneKey = before.first.key;
      expect(after.any((p) => p.key == goneKey), isFalse, reason: '이전 핀이 남았다');
    });

    test('날짜를 늘리면 핀만 더해진다 — 기존 핀 키는 그대로', () {
      final one = pinsFor(doc, dates: {monday}, now: monday);
      final two = pinsFor(doc, dates: {monday, tuesday}, now: monday);
      expect(two.map((p) => p.key), contains(one.single.key));
      expect(two, hasLength(2));
    });
  });

  group('핀 ID 충돌 방지', () {
    final doc = mobileDoc(example);

    test('날짜별로 키가 다르다', () {
      final pins = pinsFor(
        doc,
        dates: {monday, tuesday, wednesday},
        now: monday,
      );
      expect(pins.map((p) => p.key).toSet(), hasLength(3));
    });

    test('키에 문서 id와 날짜가 함께 들어 있다', () {
      final pins = pinsFor(doc, dates: {monday, tuesday}, now: monday);
      expect(pins[0].key, 'place:truck-1@2026-10-12');
      expect(pins[1].key, 'place:truck-1@2026-10-13');
    });

    test('고정형 키는 예전 형식 그대로다', () {
      final pin = pinsFor(fixedDoc, dates: {monday, tuesday}, now: monday);
      expect(pin, hasLength(1));
      expect(pin.single.key, 'place:truck-1');
      expect(pin.single.openingDate, isNull);
    });

    test('다른 업체끼리도 겹치지 않는다', () {
      final a = pinsFor(doc, dates: {monday}, now: monday, docId: 'truck-a');
      final b = pinsFor(doc, dates: {monday}, now: monday, docId: 'truck-b');
      expect(a.single.key, isNot(b.single.key));
    });
  });

  group('같은 좌표, 다른 날짜 — 날짜 정보가 사라지지 않는다', () {
    /// 월·수 모두 홍대에서 영업.
    final sameSpot = mobileDoc(
      const MobilePlaceSchedule()
          .withRegular(DateTime.monday, slot(hongdae, '11:00', '15:00'))
          .withRegular(DateTime.wednesday, slot(hongdae, '17:00', '21:00')),
    );

    test('핀이 두 개 남는다 — 좌표가 같아도 접지 않는다', () {
      final pins = pinsFor(sameSpot, dates: {monday, wednesday}, now: monday);
      expect(pins, hasLength(2), reason: '같은 좌표라고 핀을 합쳤다 — 날짜가 사라진다');
      expect(pins.map((p) => p.lat).toSet(), {hongdae.latitude});
    });

    test('키가 날짜로 갈려 둘 다 살아남는다', () {
      final pins = pinsFor(sameSpot, dates: {monday, wednesday}, now: monday);
      expect(pins.map((p) => p.key), [
        'place:truck-1@2026-10-12',
        'place:truck-1@2026-10-14',
      ]);
    });

    test('카드가 날짜로 구분된다', () {
      final pins = pinsFor(sameSpot, dates: {monday, wednesday}, now: monday);
      final labels = pins.map((p) => p.cardData(now: monday)['address'] as String).toList();
      expect(labels, hasLength(2));
      expect(labels[0], isNot(labels[1]), reason: '두 카드가 같은 말을 한다');
      expect(labels[1], contains('10/14'));
      // 시간도 날짜별로 다르다.
      expect(pins[0].cardData(now: monday)['openTime'], '11:00');
      expect(pins[1].cardData(now: monday)['openTime'], '17:00');
    });
  });

  group('자정 넘김 — 두 날짜에 걸려도 핀 하나', () {
    final lateNight = mobileDoc(
      const MobilePlaceSchedule().withRegular(
        DateTime.friday,
        slot(gangnam, '22:00', '02:00'),
      ),
    );

    test('금+토를 함께 골라도 핀이 하나다', () {
      final pins = pinsFor(
        lateNight,
        dates: {friday, saturday},
        startTime: const TimeOfDay(hour: 1, minute: 0),
        now: friday,
      );
      // 토 01:00은 금요일 밤 구간 하나에만 들어간다.
      expect(pins, hasLength(1), reason: '같은 영업에 핀이 두 개 생겼다');
      expect(pins.single.openingDate, friday, reason: '핀 날짜가 영업 시작 날이 아니다');
    });

    test('날짜만 고르면 금·토 모두 그 영업을 가리키고 핀은 하나다', () {
      final pins = pinsFor(lateNight, dates: {friday, saturday}, now: friday);
      expect(pins, hasLength(1));
      expect(pins.single.key, 'place:truck-1@2026-10-16');
    });

    test('토요일만 골라도 전날 밤 영업이 핀이 된다', () {
      final pins = pinsFor(
        lateNight,
        dates: {saturday},
        startTime: const TimeOfDay(hour: 1, minute: 0),
        now: friday,
      );
      expect(pins, hasLength(1));
      expect(pins.single.lng, gangnam.longitude);
    });
  });

  group('시간 필터 — 날짜마다 따로 판정한다', () {
    /// 월 11~15시 홍대 / 화 18~23시 강남.
    final doc = mobileDoc(
      const MobilePlaceSchedule()
          .withRegular(DateTime.monday, slot(hongdae, '11:00', '15:00'))
          .withRegular(DateTime.tuesday, slot(gangnam, '18:00', '23:00')),
    );

    test('12시 — 월요일만 걸린다', () {
      final pins = pinsFor(
        doc,
        dates: {monday, tuesday},
        startTime: const TimeOfDay(hour: 12, minute: 0),
        now: monday,
      );
      expect(pins, hasLength(1));
      expect(pins.single.openingDate, monday);
    });

    test('20시 — 화요일만 걸린다', () {
      final pins = pinsFor(
        doc,
        dates: {monday, tuesday},
        startTime: const TimeOfDay(hour: 20, minute: 0),
        now: monday,
      );
      expect(pins, hasLength(1));
      expect(pins.single.openingDate, tuesday);
    });

    test('두 날 모두 안 여는 시각이면 핀이 없다', () {
      expect(
        pinsFor(
          doc,
          dates: {monday, tuesday},
          startTime: const TimeOfDay(hour: 16, minute: 30),
          now: monday,
        ),
        isEmpty,
      );
    });

    test('시간을 안 고르면 두 날 모두 핀', () {
      expect(pinsFor(doc, dates: {monday, tuesday}, now: monday), hasLength(2));
    });
  });

  group('카드 — 날짜·장소명·영업시간', () {
    final doc = mobileDoc(example);

    test('오늘 핀은 "오늘"로 적는다', () {
      final card = pinsFor(doc, dates: {monday}, now: monday).single.cardData(now: monday);
      expect(card['address'], '오늘 · 홍대');
      expect(card['openTime'], '11:00');
      expect(card['closeTime'], '20:00');
    });

    test('다른 날 핀은 날짜와 요일을 적는다', () {
      final card = pinsFor(doc, dates: {tuesday}, now: monday).single.cardData(now: monday);
      expect(card['address'], '10/13 (화) · 강남');
    });

    test('날짜별 카드가 서로 구분된다', () {
      final pins = pinsFor(doc, dates: {monday, tuesday, wednesday}, now: monday);
      final labels = pins.map((p) => p.cardData(now: monday)['address']).toList();
      expect(labels, ['오늘 · 홍대', '10/13 (화) · 강남', '10/14 (수) · 여의도']);
    });

    test('원본 문서를 변형하지 않는다', () {
      final original = mobileDoc(example);
      final pins = pinsFor(original, dates: {monday, tuesday}, now: monday);
      for (final pin in pins) {
        pin.cardData(now: monday); // 사본을 만든다
      }
      expect(original['address'], '서울 중구 어딘가');
      expect(original['openTime'], '09:00');
    });

    test('고정형 카드는 원본 그대로 — 같은 인스턴스', () {
      final pin = pinsFor(fixedDoc, dates: {monday, tuesday}, now: monday).single;
      expect(identical(pin.cardData(now: monday), fixedDoc), isTrue);
      expect(pin.cardData(now: monday)['address'], '서울 중구 명동길 1');
    });
  });

  group('상세 화면 전달 — 날짜별 핀이 각자의 날짜를 넘긴다', () {
    final doc = mobileDoc(example);

    test('핀마다 opening.start가 그 날짜다', () {
      final pins = pinsFor(doc, dates: {monday, tuesday, wednesday}, now: monday);
      expect(pins.map((p) => p.opening!.start), [
        DateTime(2026, 10, 12, 11),
        DateTime(2026, 10, 13, 11),
        DateTime(2026, 10, 14, 11),
      ]);
    });

    test('업체 ID·문서는 날짜가 달라도 하나다', () {
      final pins = pinsFor(doc, dates: {monday, tuesday, wednesday}, now: monday);
      for (final pin in pins) {
        expect(pin.docId, 'truck-1');
        expect(pin.data, same(doc));
        expect(pin.title, '테스트 푸드트럭');
      }
    });

    test('마커 탭 카드 주소도 그 날 자리다', () {
      final pins = pinsFor(doc, dates: {monday, tuesday}, now: monday);
      expect(pins.map((p) => p.shortAddress), ['홍대', '강남']);
    });
  });

  group('고정형 회귀 — 날짜를 몇 개 골라도 그대로', () {
    test('핀 하나, 문서 좌표, 예전 키', () {
      for (final dates in [
        <DateTime>{},
        {monday},
        {monday, tuesday},
        {monday, tuesday, wednesday, thursday, friday},
      ]) {
        final pins = pinsFor(fixedDoc, dates: dates, now: monday);
        expect(pins, hasLength(1), reason: '$dates — 고정형 핀 개수가 바뀌었다');
        expect(pins.single.lat, 37.5665);
        expect(pins.single.key, 'place:truck-1');
        expect(pins.single.opening, isNull);
      }
    });

    test('휴무 요일만 골라도 고정형은 남는다', () {
      expect(pinsFor(fixedDoc, dates: {thursday}, now: monday), hasLength(1));
    });
  });

  group('중복 로직 금지 · 기존 기능 보존', () {
    final mapScreen = _codeOnly(_kMapScreen);
    final pins = _codeOnly(_kPins);

    test('지도가 고른 날짜 집합을 그대로 넘긴다', () {
      expect(mapScreen, contains('dates: _placeDiscovery.visitDates'));
      expect(
        mapScreen.contains('date: _placeDiscovery.visitDate'),
        isFalse,
        reason: '가장 이른 날짜만 쓰는 코드가 남아 있다',
      );
    });

    test('핀 해석기가 모델에 판정을 넘긴다', () {
      expect(pins, contains('schedule.openingFor('));
      expect(
        RegExp(r'\b1440\b').hasMatch(pins),
        isFalse,
        reason: '자정 넘김 계산을 핀 해석기에 복사했다',
      );
      for (final forbidden in [
        'openingOn(',
        'closedWeekdays',
        'ScheduleExceptionMode',
        'DayTimeMatch',
      ]) {
        expect(pins.contains(forbidden), isFalse, reason: '$forbidden 을 직접 다룬다');
      }
    });

    test('지도 화면에 일정 계산이 없다', () {
      for (final forbidden in [
        'MobilePlaceSchedule',
        'ScheduleException',
        'openingFor',
      ]) {
        expect(mapScreen.contains(forbidden), isFalse, reason: forbidden);
      }
      expect(mapScreen, contains('MobilePlacePins.resolve('));
    });

    test('addSlot을 다시 들이지 않았다', () {
      expect(ScheduleExceptionMode.values, hasLength(2));
      expect(
        _codeOnly('lib/models/mobile_place_schedule.dart').contains('addSlot,'),
        isFalse,
        reason: 'addSlot이 다시 생겼다',
      );
    });

    test('하루 한 장소 구조가 그대로다', () {
      expect(example.regular, isA<Map<int, ScheduleSlot>>());
      // 요일당 하나 — 타입이 막는다.
      expect(example.regular[DateTime.monday], isA<ScheduleSlot>());
    });

    test('추가 Firestore 조회를 만들지 않았다', () {
      final block = mapScreen.substring(
        mapScreen.indexOf('Iterable<MapListing> _resolvePins('),
      );
      final body = block.substring(0, block.indexOf('\n  }'));
      for (final forbidden in ['collection(', 'get()', 'snapshots(', 'await']) {
        expect(body.contains(forbidden), isFalse, reason: forbidden);
      }
    });
  });

  group('작은 화면 — 카드 라벨이 길어지지 않는다', () {
    test('날짜 라벨이 짧다', () {
      final doc = mobileDoc(example);
      for (final date in [monday, tuesday, wednesday]) {
        final label = pinsFor(doc, dates: {date}, now: monday)
            .single
            .cardData(now: monday)['address'] as String;
        expect(
          label.length,
          lessThanOrEqualTo(24),
          reason: '카드 주소 한 줄이 너무 길다: "$label"',
        );
      }
    });

    test('긴 장소명도 카드 한 줄을 터뜨리지 않는다', () {
      final longName = mobileDoc(
        const MobilePlaceSchedule().withRegular(
          DateTime.monday,
          slot(stopAt('아주아주 긴 이름을 가진 영업 장소입니다', 37.5, 127.0)),
        ),
      );
      final label = pinsFor(longName, dates: {monday}, now: monday)
          .single
          .cardData(now: monday)['address'] as String;
      // 길어도 예외 없이 문자열로 만들어진다(줄임은 카드 위젯이 한다).
      expect(label, startsWith('오늘 · '));
    });
  });
}

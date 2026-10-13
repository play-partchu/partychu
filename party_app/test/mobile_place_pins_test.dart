// 🗺 이동형 플레이스의 **지도 핀** — 업체당 날짜당 핀 하나.
//
//     월: 홍대 핀만 · 화: 강남 핀만 · 수: 여의도 핀만 · 목: 핀 없음
//
// 지도 화면은 테스트에서 띄울 수 없다(네이버 지도 SDK·Firestore 구독). 그래서
// **핀을 정하는 결정 전부**를 순수 함수로 꺼내 두고([MobilePlacePins],
// [MapListing.atStop]) 여기서 검증한다. 지도 화면에 남은 것은 그 결과를 쓰는
// 두 줄뿐이고, 그 두 줄은 아래 소스 감사가 지킨다.
//
// 고정형 장소의 기존 동작은 test/map_fixed_place_baseline_test.dart가 따로
// 못 박는다 — 이 파일은 **이동형이 그 판정을 건드리지 않는지**를 본다.

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

const _kPins = 'lib/models/mobile_place_pins.dart';
const _kMapScreen = 'lib/screens/map_screen.dart';
const _kListing = 'lib/models/map_listing.dart';

/// 2026-10-12 = 월요일.
final monday = DateTime(2026, 10, 12);
final tuesday = DateTime(2026, 10, 13);
final wednesday = DateTime(2026, 10, 14);
final thursday = DateTime(2026, 10, 15);
final friday = DateTime(2026, 10, 16);
final saturday = DateTime(2026, 10, 17);
final nextMonday = DateTime(2026, 10, 19);

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
final festival = stopAt('축제장', 37.5000, 127.0000);

ScheduleSlot slot(ScheduledStop stop, [String s = '11:00', String e = '20:00']) =>
    ScheduleSlot(stop: stop, startTime: s, endTime: e);

ScheduleException exception(
  DateTime date,
  ScheduleExceptionMode mode, {
  ScheduleSlot? slot,
}) => ScheduleException(
  id: 'x-${ScheduleException.dateKeyOf(date)}',
  dateKey: ScheduleException.dateKeyOf(date),
  mode: mode,
  slot: slot,
);

/// 사용자가 든 예시 — 월 홍대 / 화 강남 / 수 여의도 / 목 휴무.
final exampleSchedule = MobilePlaceSchedule(
  regular: {
    DateTime.monday: slot(hongdae),
    DateTime.tuesday: slot(gangnam),
    DateTime.wednesday: slot(yeouido),
  },
  closedWeekdays: const {DateTime.thursday},
);

Map<String, dynamic> mobileDoc(MobilePlaceSchedule schedule) => {
  'name': '파티츄 푸드트럭',
  'placeCategory': '맛집',
  // 기준 주소·좌표는 그대로 남는다 — 이동형이어도 문서 모양이 깨지지 않는다.
  'latitude': 37.5665,
  'longitude': 126.9780,
  'address': '서울 중구 어딘가',
  'isActive': true,
  MobilePlaceSchedule.isMobileFieldName: true,
  MobilePlaceSchedule.fieldName: schedule.toMap(),
};

final fixedDoc = <String, dynamic>{
  'name': '혼술바',
  'latitude': 37.5665,
  'longitude': 126.9780,
  'address': '서울 중구 명동길 1',
};

/// 지도가 하는 일을 그대로 흉내낸다 — `_resolvePins`와 같은 세 줄이다.
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
  return [for (final opening in resolved.openings) base.atStop(opening)];
}

void main() {
  group('고정형은 예전 경로 그대로', () {
    test('isMobilePlace가 없으면 fixed', () {
      final r = MobilePlacePins.resolve(fixedDoc, now: monday);
      expect(r.isMobile, isFalse);
      expect(r.openings, isEmpty);
      expect(r.hasPin, isTrue, reason: '고정형 핀이 사라졌다');
    });

    test('isMobilePlace: false여도 fixed', () {
      final r = MobilePlacePins.resolve({
        MobilePlaceSchedule.isMobileFieldName: false,
        MobilePlaceSchedule.fieldName: {'regular': {}},
      }, now: monday);
      expect(r.isMobile, isFalse);
    });

    test('mobileSchedule이 없어도 정상 작동한다 — 운영 문서 4건 전부 이 상태', () {
      expect(
        MobilePlacePins.resolve({'placeWeeklyHours': {}}, now: monday).isMobile,
        isFalse,
      );
    });

    test('고정형 핀은 문서 좌표 하나, 키도 예전 형식', () {
      final pins = pinsFor(fixedDoc, now: monday);
      expect(pins, hasLength(1));
      expect(pins.single.lat, 37.5665);
      expect(pins.single.key, 'place:truck-1');
      expect(pins.single.opening, isNull);
      expect(pins.single.shortAddress, isNot('홍대'));
    });

    test('고정형은 날짜·시간을 걸어도 그대로 남는다', () {
      for (final date in [monday, thursday, saturday]) {
        expect(
          pinsFor(
            fixedDoc,
            dates: {date},
            startTime: const TimeOfDay(hour: 3, minute: 0),
            now: monday,
          ),
          hasLength(1),
          reason: '고정형 판정이 바뀌었다',
        );
      }
    });

    test('"고정형"과 "이동형인데 쉰다"가 구분된다', () {
      final fixed = MobilePlacePins.resolve(fixedDoc, now: monday);
      final closed = MobilePlacePins.resolve(
        mobileDoc(exampleSchedule),
        dates: {thursday},
        now: monday,
      );
      expect(fixed.isMobile, isFalse);
      expect(fixed.hasPin, isTrue);
      expect(closed.isMobile, isTrue);
      expect(closed.hasPin, isFalse);
    });
  });

  group('오늘 기본 날짜 표시', () {
    final doc = mobileDoc(exampleSchedule);

    test('날짜를 고르지 않으면 오늘 기준으로 핀이 찍힌다', () {
      expect(pinsFor(doc, now: monday).single.lng, hongdae.longitude);
      expect(pinsFor(doc, now: tuesday).single.lng, gangnam.longitude);
    });

    test('오늘이 휴무면 핀이 없다', () {
      expect(pinsFor(doc, now: thursday), isEmpty);
    });

    test('오늘 일정이 없으면 핀이 없다 — 기준 좌표에 찍지 않는다', () {
      expect(
        pinsFor(doc, now: saturday),
        isEmpty,
        reason: '일정이 없는데 문서 기준 좌표에 핀을 찍었다',
      );
    });

    test('핀 좌표가 문서의 기준 좌표가 아니다', () {
      expect(pinsFor(doc, now: monday).single.lat, isNot(37.5665));
    });
  });

  group('날짜 변경 시 핀 위치 변경 · 이전 날짜 핀 제거', () {
    final doc = mobileDoc(exampleSchedule);

    test('날짜를 바꾸면 그 날짜의 좌표로 옮겨간다', () {
      expect(pinsFor(doc, dates: {monday}, now: monday).single.lng, hongdae.longitude);
      expect(pinsFor(doc, dates: {tuesday}, now: monday).single.lng, gangnam.longitude);
      expect(
        pinsFor(doc, dates: {wednesday}, now: monday).single.lng,
        yeouido.longitude,
      );
    });

    test('이전 날짜의 핀은 남지 않는다 — 결과가 통째로 갈린다', () {
      final mon = pinsFor(doc, dates: {monday}, now: monday);
      final tue = pinsFor(doc, dates: {tuesday}, now: monday);
      expect(mon.single.lng, isNot(tue.single.lng));
      // 월요일 좌표가 화요일 결과에 섞여 있지 않다.
      expect(tue.any((p) => p.lng == hongdae.longitude), isFalse);
    });

    test('날짜가 바뀌면 키도 바뀐다 — 이전 날짜 핀이 남지 않는다', () {
      // 날짜를 여럿 고를 수 있으므로 키에 날짜가 들어간다(핀 id 충돌 방지).
      // 날짜별 동작 전체는 mobile_place_multi_date_pins_test가 본다.
      expect(
        pinsFor(doc, dates: {monday}, now: monday).single.key,
        isNot(pinsFor(doc, dates: {tuesday}, now: monday).single.key),
      );
      expect(
        pinsFor(doc, dates: {monday}, now: monday).single.key,
        'place:truck-1@2026-10-12',
      );
    });

    test('핀 카드 주소도 그 날짜의 자리를 가리킨다', () {
      expect(pinsFor(doc, dates: {monday}, now: monday).single.shortAddress, '홍대');
      expect(pinsFor(doc, dates: {tuesday}, now: monday).single.shortAddress, '강남');
    });
  });

  group('휴무일 핀 미표시', () {
    test('정기 휴무 요일에는 핀이 없다', () {
      expect(pinsFor(mobileDoc(exampleSchedule), dates: {thursday}, now: monday), isEmpty);
    });

    test('예외 휴무일에도 핀이 없다', () {
      final doc = mobileDoc(
        exampleSchedule.upsertException(
          exception(nextMonday, ScheduleExceptionMode.closed),
        ),
      );
      expect(pinsFor(doc, dates: {nextMonday}, now: monday), isEmpty);
      // 같은 요일의 다른 주는 그대로.
      expect(pinsFor(doc, dates: {monday}, now: monday), hasLength(1));
    });
  });

  group('업체당 날짜당 핀 하나', () {
    test('어떤 날짜를 골라도 핀은 0개 또는 1개다', () {
      final doc = mobileDoc(exampleSchedule);
      for (final date in [monday, tuesday, wednesday, thursday, friday, saturday]) {
        expect(
          pinsFor(doc, dates: {date}, now: monday).length,
          lessThanOrEqualTo(1),
          reason: '$date 에 핀이 둘 이상 생겼다',
        );
      }
    });

    test('날짜 하나를 고르면 영업도 하나다', () {
      final r = MobilePlacePins.resolve(
        mobileDoc(exampleSchedule),
        dates: {monday},
        now: monday,
      );
      expect(r.openings, hasLength(1));
    });

    test('예외와 정기가 같은 날 있어도 하나다', () {
      final doc = mobileDoc(
        exampleSchedule.upsertException(
          exception(
            nextMonday,
            ScheduleExceptionMode.replaceDay,
            slot: slot(festival, '18:00', '22:00'),
          ),
        ),
      );
      final pins = pinsFor(doc, dates: {nextMonday}, now: monday);
      expect(pins, hasLength(1));
      expect(pins.single.lng, festival.longitude, reason: '예외가 정기를 이기지 않았다');
    });
  });

  group('시간 필터 영업 여부 판정', () {
    final doc = mobileDoc(
      MobilePlaceSchedule(
        regular: {DateTime.monday: slot(hongdae, '11:00', '15:00')},
      ),
    );

    test('시간을 고르지 않으면 그 날 일정이 있으면 뜬다', () {
      expect(pinsFor(doc, dates: {monday}, now: monday), hasLength(1));
    });

    test('영업 중인 시각이면 뜬다', () {
      expect(
        pinsFor(
          doc,
          dates: {monday},
          startTime: const TimeOfDay(hour: 12, minute: 0),
          now: monday,
        ),
        hasLength(1),
      );
    });

    test('영업하지 않는 시각이면 **빠진다** — 다른 장소로 바뀌지 않는다', () {
      final pins = pinsFor(
        doc,
        dates: {monday},
        startTime: const TimeOfDay(hour: 18, minute: 0),
        now: monday,
      );
      expect(pins, isEmpty, reason: '영업 안 하는 시각인데 핀이 남았다');
    });

    test('구간을 고르면 겹치면 뜬다', () {
      expect(
        pinsFor(
          doc,
          dates: {monday},
          startTime: const TimeOfDay(hour: 14, minute: 0),
          endTime: const TimeOfDay(hour: 18, minute: 0),
          now: monday,
        ),
        hasLength(1),
      );
      expect(
        pinsFor(
          doc,
          dates: {monday},
          startTime: const TimeOfDay(hour: 16, minute: 0),
          endTime: const TimeOfDay(hour: 18, minute: 0),
          now: monday,
        ),
        isEmpty,
      );
    });

    test('자정을 넘기는 영업이 새벽 조건에 걸린다', () {
      final lateNight = mobileDoc(
        MobilePlaceSchedule(
          regular: {DateTime.friday: slot(gangnam, '22:00', '02:00')},
        ),
      );
      final pins = pinsFor(
        lateNight,
        dates: {saturday},
        startTime: const TimeOfDay(hour: 1, minute: 0),
        now: monday,
      );
      expect(pins, hasLength(1));
      expect(pins.single.lng, gangnam.longitude);
    });
  });

  group('오늘만 영업하는 장소', () {
    final base = MobilePlaceSchedule(
      regular: {DateTime.monday: slot(hongdae)},
    );
    final doc = mobileDoc(
      base.withTodayStop(
        monday,
        stop: festival,
        startTime: '12:00',
        endTime: '19:00',
      ),
    );

    test('오늘은 바뀐 자리에 뜬다', () {
      expect(pinsFor(doc, now: monday).single.lng, festival.longitude);
    });

    test('다음 날에는 영향이 없다', () {
      expect(pinsFor(doc, now: tuesday), isEmpty);
    });

    test('다음 주 같은 요일은 정기 자리로 복귀한다', () {
      expect(
        pinsFor(doc, now: nextMonday).single.lng,
        hongdae.longitude,
        reason: '오늘 변경이 정기 일정까지 바꿨다',
      );
    });
  });

  group('예외 삭제 후 정기 장소 복귀', () {
    test('예외를 지우면 지도가 정기 자리로 돌아온다', () {
      final withException = exampleSchedule.upsertException(
        exception(
          nextMonday,
          ScheduleExceptionMode.replaceDay,
          slot: slot(festival),
        ),
      );
      expect(
        pinsFor(mobileDoc(withException), dates: {nextMonday}, now: monday)
            .single
            .lng,
        festival.longitude,
      );
      final restored = withException.withoutExceptionOn(nextMonday);
      expect(
        pinsFor(mobileDoc(restored), dates: {nextMonday}, now: monday).single.lng,
        hongdae.longitude,
        reason: '예외를 지웠는데 지도가 정기 자리로 돌아오지 않았다',
      );
    });

    test('휴무 예외를 지우면 핀이 다시 생긴다', () {
      final closed = exampleSchedule.upsertException(
        exception(nextMonday, ScheduleExceptionMode.closed),
      );
      expect(pinsFor(mobileDoc(closed), dates: {nextMonday}, now: monday), isEmpty);
      expect(
        pinsFor(
          mobileDoc(closed.withoutExceptionOn(nextMonday)),
          dates: {nextMonday},
          now: monday,
        ),
        hasLength(1),
      );
    });
  });

  group('과거 일정이 지도에 남지 않는다', () {
    test('지난 예외만 있는 업체는 오늘 핀이 없다', () {
      final doc = mobileDoc(
        MobilePlaceSchedule(
          exceptions: [
            exception(
              DateTime(2026, 9, 20),
              ScheduleExceptionMode.replaceDay,
              slot: slot(festival),
            ),
          ],
        ),
      );
      expect(pinsFor(doc, now: monday), isEmpty);
    });

    test('일정이 아예 없으면 핀이 없다', () {
      expect(pinsFor(mobileDoc(const MobilePlaceSchedule()), now: monday), isEmpty);
    });
  });

  group('깨진 데이터에도 지도가 죽지 않는다', () {
    test('좌표 0인 일정은 핀이 되지 않는다', () {
      final doc = mobileDoc(
        const MobilePlaceSchedule(
          regular: {
            1: ScheduleSlot(
              stop: ScheduledStop(latitude: 0, longitude: 0),
              startTime: '11:00',
              endTime: '14:00',
            ),
          },
        ),
      );
      expect(pinsFor(doc, now: monday), isEmpty);
    });

    test('mobileSchedule이 Map이 아니어도 예외가 나지 않는다', () {
      final doc = {
        MobilePlaceSchedule.isMobileFieldName: true,
        MobilePlaceSchedule.fieldName: '깨진 값',
      };
      expect(() => MobilePlacePins.resolve(doc, now: monday), returnsNormally);
      final r = MobilePlacePins.resolve(doc, now: monday);
      expect(r.isMobile, isTrue);
      expect(r.openings, isEmpty);
    });

    test('일정 안에 쓰레기 값이 섞여도 나머지가 뜬다', () {
      final doc = {
        'name': '트럭',
        'latitude': 37.5,
        'longitude': 127.0,
        MobilePlaceSchedule.isMobileFieldName: true,
        MobilePlaceSchedule.fieldName: {
          'regular': {
            '99': {'startTime': '11:00'},
            '1': {
              'startTime': '11:00',
              'endTime': '14:00',
              'stop': {
                'latitude': 37.5563,
                'longitude': 126.9236,
                'placeName': '홍대',
              },
            },
          },
          'exceptions': ['쓰레기', {'date': '없는날짜'}],
        },
      };
      final pins = pinsFor(doc, now: monday);
      expect(pins, hasLength(1));
      expect(pins.single.lng, 126.9236);
    });

    test('날짜 형식이 깨진 예외는 판정에 끼지 않는다', () {
      final doc = {
        'name': '트럭',
        'latitude': 37.5,
        'longitude': 127.0,
        MobilePlaceSchedule.isMobileFieldName: true,
        MobilePlaceSchedule.fieldName: {
          'regular': {
            '1': {
              'startTime': '11:00',
              'endTime': '14:00',
              'stop': {'latitude': 37.5563, 'longitude': 126.9236},
            },
          },
          'exceptions': [
            {'date': '2026-02-30', 'mode': 'closed'},
          ],
        },
      };
      expect(pinsFor(doc, now: monday), hasLength(1));
    });
  });

  group('마커 식별과 상세 화면 연결', () {
    final doc = mobileDoc(exampleSchedule);

    test('키에 문서 id와 날짜가 들어 있다 — 좌표는 섞지 않는다', () {
      final key = pinsFor(doc, dates: {monday}, now: monday).single.key;
      expect(key, 'place:truck-1@2026-10-12');
      expect(key.contains('37.'), isFalse, reason: '좌표가 키에 섞였다');
    });

    test('docId와 data는 바뀌지 않는다 — 상세·사진·리뷰·채팅이 같은 곳으로 간다', () {
      for (final date in [monday, tuesday, wednesday]) {
        final pin = pinsFor(doc, dates: {date}, now: monday).single;
        expect(pin.docId, 'truck-1');
        expect(pin.data, same(doc));
        expect(pin.kind, MapListingKind.place);
        expect(pin.title, '파티츄 푸드트럭');
      }
    });

    test('날짜가 달라도 같은 상세로 들어간다', () {
      final mon = pinsFor(doc, dates: {monday}, now: monday).single;
      final tue = pinsFor(doc, dates: {tuesday}, now: monday).single;
      // _openDetail은 kind·docId·data만 쓴다.
      expect(mon.docId, tue.docId);
      expect(mon.data, same(tue.data));
    });
  });

  group('중복 로직 금지 — 지도에 일정 계산을 두지 않았다', () {
    final pins = _codeOnly(_kPins);
    final mapScreen = _codeOnly(_kMapScreen);

    test('핀 해석기가 모델에 판정을 넘긴다', () {
      expect(pins, contains('MobilePlaceSchedule.ofPlace('));
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
        expect(
          pins.contains(forbidden),
          isFalse,
          reason: '$forbidden 을 직접 다루고 있다 — 우선순위 판정이 두 곳으로 갈라진다',
        );
      }
    });

    test('지도 화면에 일정 계산이 없다', () {
      for (final forbidden in [
        'MobilePlaceSchedule',
        'ScheduleException',
        'openingOn',
        'openingFor',
      ]) {
        expect(
          mapScreen.contains(forbidden),
          isFalse,
          reason: '지도 화면이 일정을 직접 해석한다 — $forbidden',
        );
      }
      expect(mapScreen, contains('MobilePlacePins.resolve('));
    });

    test('고정형 분기가 한 곳뿐이다', () {
      expect(mapScreen, contains('Iterable<MapListing> _resolvePins('));
      expect(
        mapScreen.split('MobilePlacePins.resolve(').length - 1,
        1,
        reason: '핀 해석을 지도 화면 여러 곳에서 부르고 있다',
      );
      expect(mapScreen, contains('if (item.kind != MapListingKind.place)'));
    });

    test('날짜는 기존 복수 선택 집합을 그대로 쓴다', () {
      // 고정형과 **같은 집합**을 넘긴다 — 기존 날짜 복수 선택 UX가 그대로다.
      expect(mapScreen, contains('dates: _placeDiscovery.visitDates'));
      // `visitDates`(집합)는 이벤트 색인 등 **기존 경로**가 그대로 쓴다.
      // 그러니 전체 파일이 아니라 핀 해석 블록만 본다.
      final resolveBlock = mapScreen.substring(
        mapScreen.indexOf('Iterable<MapListing> _resolvePins('),
      );
      final block = resolveBlock.substring(0, resolveBlock.indexOf('\n  }'));
      expect(
        block.contains('visitDate,'),
        isFalse,
        reason: '가장 이른 날짜만 쓰는 코드가 남아 있다',
      );
    });

    test('추가 Firestore 조회를 만들지 않았다', () {
      final resolveBlock = mapScreen.substring(
        mapScreen.indexOf('Iterable<MapListing> _resolvePins('),
      );
      final block = resolveBlock.substring(0, resolveBlock.indexOf('\n  }'));
      for (final forbidden in ['collection(', 'get()', 'snapshots(', 'await']) {
        expect(
          block.contains(forbidden),
          isFalse,
          reason: '핀 해석이 $forbidden 으로 추가 조회를 한다',
        );
      }
    });

    test('자동 재조회·영역 검색 경로를 그대로 쓴다', () {
      expect(mapScreen, contains('void _recomputeVisible()'));
      expect(mapScreen, contains('_filterByBounds('));
      expect(mapScreen, contains('_runAreaSearch'));
    });

    test('MapListing의 이동형 필드는 선택이고, 키는 기준선 형식이다', () {
      final listing = _codeOnly(_kListing);
      expect(listing, contains('final PlaceOpening? opening;'));
      // 키는 이동형일 때만 날짜가 붙는다 — 고정형은 예전 형식 그대로다.
      expect(listing, contains("final base = '\${kind.name}:\$docId';"));
      expect(listing, contains('date == null'));
    });
  });

  group('기존 데이터와 신규 데이터가 섞여도 된다', () {
    test('고정형·이동형·휴무 이동형이 한 지도에 함께 올라간다', () {
      final docs = <String, Map<String, dynamic>>{
        'fixed': fixedDoc,
        'truck': mobileDoc(exampleSchedule),
        'closedTruck': mobileDoc(
          MobilePlaceSchedule(
            regular: {DateTime.monday: slot(gangnam)},
            closedWeekdays: const {DateTime.monday},
          ),
        ),
        'legacyNoCategory': {
          'name': '옛 가게',
          'latitude': 37.6,
          'longitude': 127.1,
        },
      };

      final all = <MapListing>[];
      docs.forEach((id, doc) {
        all.addAll(pinsFor(doc, dates: {monday}, now: monday, docId: id));
      });

      // 고정형 2건 + 트럭 1건. 휴무 트럭은 빠진다.
      expect(all.map((i) => i.docId).toList(), [
        'fixed',
        'truck',
        'legacyNoCategory',
      ]);
      expect(all.map((i) => i.key).toSet(), hasLength(3));
      expect(all[0].lat, 37.5665, reason: '고정형이 문서 좌표를 잃었다');
      expect(all[1].lat, hongdae.latitude);
    });

    test('날짜를 바꿔도 고정형 개수는 그대로다', () {
      for (final date in [monday, thursday, saturday]) {
        final fixed = pinsFor(fixedDoc, dates: {date}, now: monday, docId: 'fixed');
        expect(fixed, hasLength(1), reason: '$date 에 고정형이 사라졌다');
      }
    });
  });
}

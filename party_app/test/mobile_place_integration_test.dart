// 🔗 **1~5단계 통합 검수** — 등록 → 저장 → 복원 → 지도 핀 → 상세 → 길찾기.
//
// 각 단계는 자기 테스트가 있지만, **이음새**는 아무도 보지 않았다. 이 파일은
// 사슬을 통째로 이어 돌린다:
//
//   등록 화면이 만드는 payload 모양
//     → MobilePlaceSchedule.toMap()
//       → `events` 문서(운영 스키마 모양)
//         → MobilePlaceSchedule.ofPlace()
//           → MobilePlacePins.resolve() → MapListing.atStop()  (지도 핀)
//             → EventDetailScreen(focusDate:) → MobileScheduleDetailCard
//               → PlaceAddressRow(latitude/longitude)          (길찾기)
//
// 가장 중요한 단정은 하나다: **지도 핀 좌표와 상세 화면이 보여 주는 장소가
// 언제나 같아야 한다.** 둘이 어긋나면 사용자는 핀을 보고 갔는데 다른 주소를
// 안내받는다.
//
// ⚠️ 이 파일은 **코드 사슬**을 검증한다. 실제 기기에서 Firestore에 저장하고
//    지도를 띄워 본 것이 아니다 — 그 부분은 보고서의 "미검증"에 남긴다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/map_listing.dart';
import 'package:party_app/models/mobile_place_pins.dart';
import 'package:party_app/models/mobile_place_schedule.dart';
import 'package:party_app/widgets/mobile_schedule_detail_card.dart';
import 'package:party_app/widgets/place_address_row.dart';

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
  address: '서울 $name구 어딘가 1',
  roadAddress: '서울 $name구 $name로 1',
  detailAddress: '$name 광장 앞',
  latitude: lat,
  longitude: lng,
);

final hongdae = stopAt('홍대', 37.5563, 126.9236);
final gangnam = stopAt('강남', 37.4979, 127.0276);
final yeouido = stopAt('여의도', 37.5219, 126.9245);
final festival = stopAt('축제장', 37.5100, 127.0100);

ScheduleSlot slot(ScheduledStop stop, [String s = '11:00', String e = '20:00']) =>
    ScheduleSlot(stop: stop, startTime: s, endTime: e);

/// 호스트가 등록 화면에서 만드는 일정 — **모델 편집 메서드만** 써서 쌓는다
/// (위젯이 부르는 것과 같은 경로다).
MobilePlaceSchedule buildByHost() => const MobilePlaceSchedule()
    .withRegular(DateTime.monday, slot(hongdae))
    .withRegular(DateTime.tuesday, slot(gangnam))
    .withRegular(DateTime.wednesday, slot(yeouido))
    .withClosedWeekday(DateTime.thursday, true);

/// 등록 화면이 Firestore에 쓰는 문서 모양.
///
/// 운영에서 확인한 `events` 필드를 그대로 쓴다 — 기준 주소·좌표·운영시간이
/// **함께 남아 있는 상태**가 실제 모습이고, 그 상태에서 이동형 경로가 올바로
/// 도는지가 이 테스트의 요점이다.
Map<String, dynamic> savedDoc(
  MobilePlaceSchedule schedule, {
  bool isMobile = true,
}) => {
  'name': '파티츄 푸드트럭',
  'placeCategory': '맛집',
  'isActive': true,
  'createdAt': 'ts',
  'hostId': 'host-1',
  // 등록 화면은 이동형이어도 **기준 주소·좌표를 그대로 저장한다.**
  'address': '서울 중구 어딘가',
  'roadAddress': '서울 중구 세종대로 1',
  'location': '서울 중구 어딘가 (사무실)',
  'latitude': 37.5665,
  'longitude': 126.9780,
  // 운영시간도 함께 저장된다(섹션이 화면에 남아 있다).
  'placeWeeklyHours': {
    for (final day in ['월', '화', '수', '목', '금', '토', '일'])
      day: {
        'open': '09:00',
        'close': '18:00',
        'isClosed': false,
        'is24Hours': false,
        'hasBreakTime': false,
      },
  },
  MobilePlaceSchedule.isMobileFieldName: isMobile,
  MobilePlaceSchedule.fieldName: schedule.toMap(),
};

/// 지도가 하는 일 — `_resolvePins`와 같다.
MapListing? pinFor(
  Map<String, dynamic> doc, {
  DateTime? date,
  TimeOfDay? startTime,
  required DateTime now,
}) {
  final base = MapListing.from(MapListingKind.place, 'truck-1', doc);
  if (base == null) return null;
  final resolved = MobilePlacePins.resolve(
    doc,
    dates: date == null ? const {} : {date},
    startTime: startTime,
    now: now,
  );
  if (!resolved.isMobile) return base;
  final openings = resolved.openings;
  return openings.isEmpty ? null : base.atStop(openings.first);
}

void main() {
  group('① 등록 → 저장 → 복원', () {
    test('호스트가 만든 일정이 문서를 거쳐 그대로 돌아온다', () {
      final restored = MobilePlaceSchedule.ofPlace(savedDoc(buildByHost()));
      expect(restored, isNotNull);
      expect(restored!.openingOn(monday)?.stop, hongdae);
      expect(restored.openingOn(tuesday)?.stop, gangnam);
      expect(restored.openingOn(wednesday)?.stop, yeouido);
      expect(restored.openingOn(thursday), isNull);
      // 상세주소까지 살아 돌아온다(길찾기 안내에 쓰인다).
      expect(restored.openingOn(monday)?.stop.detailAddress, '홍대 광장 앞');
    });

    test('고정형으로 저장되면 이동형 경로를 타지 않는다', () {
      final doc = savedDoc(buildByHost(), isMobile: false);
      expect(MobilePlaceSchedule.ofPlace(doc), isNull);
      // 핀은 문서의 기준 좌표 하나.
      final pin = pinFor(doc, now: monday)!;
      expect(pin.lat, 37.5665);
      expect(pin.opening, isNull);
    });

    test('일정을 지우고 고정형으로 되돌려도 문서가 깨지지 않는다', () {
      // 등록 화면은 고정형 전환 시 일정을 **지우지 않는다**(2단계 규칙).
      final doc = savedDoc(buildByHost(), isMobile: false);
      expect(doc[MobilePlaceSchedule.fieldName], isNotNull);
      expect(MobilePlaceSchedule.ofPlace(doc), isNull, reason: '플래그가 꺼졌는데 읽혔다');
    });
  });

  group('② 지도 핀 ↔ 상세 화면이 같은 장소를 가리킨다', () {
    final doc = savedDoc(buildByHost());

    /// 핀을 띄우고, 그 핀으로 상세 카드를 열어 **길찾기 좌표**까지 꺼낸다.
    Future<({MapListing pin, PlaceAddressRow row})> openFromPin(
      WidgetTester tester, {
      DateTime? date,
      required DateTime now,
    }) async {
      final pin = pinFor(doc, date: date, now: now)!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MobileScheduleDetailCard(
                schedule: MobilePlaceSchedule.ofPlace(pin.data)!,
                placeName: pin.data['name'] as String,
                // 지도가 넘기는 값과 같다(`focusDate: item.opening?.start`).
                focusDate: pin.opening?.start,
                now: now,
              ),
            ),
          ),
        ),
      );
      final row = tester.widget<PlaceAddressRow>(find.byType(PlaceAddressRow));
      return (pin: pin, row: row);
    }

    testWidgets('월요일 — 핀 좌표 = 상세 길찾기 좌표 = 홍대', (tester) async {
      final r = await openFromPin(tester, now: DateTime(2026, 10, 12, 13));
      expect(r.pin.lat, hongdae.latitude);
      expect(r.row.latitude, hongdae.latitude);
      expect(r.row.longitude, hongdae.longitude);
      expect(r.row.address, contains('홍대로 1'));
      expect(find.text('오늘 여기서 영업 중'), findsOneWidget);
    });

    testWidgets('화요일로 날짜를 바꾸면 둘이 함께 강남으로 옮겨간다', (tester) async {
      final r = await openFromPin(
        tester,
        date: tuesday,
        now: DateTime(2026, 10, 12, 13),
      );
      expect(r.pin.lat, gangnam.latitude);
      expect(r.row.latitude, gangnam.latitude);
      expect(r.row.address, contains('강남로 1'));
      // 이전 날짜(홍대) 좌표가 어디에도 남지 않는다.
      expect(r.pin.lat, isNot(hongdae.latitude));
      expect(r.row.latitude, isNot(hongdae.latitude));
      expect(find.textContaining('홍대로 1'), findsNothing);
    });

    testWidgets('⚠️ 어느 날짜든 핀과 길찾기 좌표가 어긋나지 않는다', (tester) async {
      for (final date in [monday, tuesday, wednesday, nextMonday]) {
        final r = await openFromPin(
          tester,
          date: date,
          now: DateTime(2026, 10, 12, 13),
        );
        expect(
          r.row.latitude,
          r.pin.lat,
          reason: '$date — 핀과 상세 길찾기 위도가 다르다',
        );
        expect(
          r.row.longitude,
          r.pin.lng,
          reason: '$date — 핀과 상세 길찾기 경도가 다르다',
        );
      }
    });

    testWidgets('⚠️ 길찾기 좌표가 문서의 기준 좌표가 아니다', (tester) async {
      final r = await openFromPin(tester, now: DateTime(2026, 10, 12, 13));
      expect(
        r.row.latitude,
        isNot(37.5665),
        reason: '길찾기가 등록 기준 좌표로 간다 — 손님이 엉뚱한 곳에 도착한다',
      );
      expect(r.row.address, isNot(contains('세종대로')));
    });
  });

  group('③ 휴무 — 핀도 상세도 영업을 만들지 않는다', () {
    final doc = savedDoc(buildByHost());

    test('정기 휴무 요일에는 핀이 없다', () {
      expect(pinFor(doc, date: thursday, now: monday), isNull);
    });

    test('일정이 없는 요일에도 핀이 없다', () {
      expect(pinFor(doc, date: friday, now: monday), isNull);
      expect(pinFor(doc, date: saturday, now: monday), isNull);
    });

    testWidgets('상세는 그 날 휴무라고 말하고 주소 줄을 띄우지 않는다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MobileScheduleDetailCard(
                schedule: MobilePlaceSchedule.ofPlace(doc)!,
                placeName: '파티츄 푸드트럭',
                focusDate: thursday,
                now: DateTime(2026, 10, 15, 13),
              ),
            ),
          ),
        ),
      );
      expect(find.text('오늘은 영업하지 않아요.'), findsOneWidget);
      expect(
        find.byType(PlaceAddressRow),
        findsNothing,
        reason: '휴무인데 주소·길찾기 줄이 떴다',
      );
    });
  });

  group('④ 자정 넘김 영업', () {
    final doc = savedDoc(
      const MobilePlaceSchedule().withRegular(
        DateTime.friday,
        slot(gangnam, '22:00', '02:00'),
      ),
    );

    test('금요일 23시 — 핀이 강남에 선다', () {
      final pin = pinFor(
        doc,
        date: friday,
        startTime: const TimeOfDay(hour: 23, minute: 0),
        now: friday,
      );
      expect(pin?.lat, gangnam.latitude);
    });

    test('토요일 01시 — 전날 밤 영업이 그대로 걸린다', () {
      final pin = pinFor(
        doc,
        date: saturday,
        startTime: const TimeOfDay(hour: 1, minute: 0),
        now: friday,
      );
      expect(pin?.lat, gangnam.latitude);
    });

    test('토요일 05시 — 이미 닫았으므로 핀이 없다', () {
      expect(
        pinFor(
          doc,
          date: saturday,
          startTime: const TimeOfDay(hour: 5, minute: 0),
          now: friday,
        ),
        isNull,
      );
    });

    testWidgets('상세가 자정 넘김을 (익일)로 표시한다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MobileScheduleDetailCard(
                schedule: MobilePlaceSchedule.ofPlace(doc)!,
                placeName: '파티츄 푸드트럭',
                focusDate: friday,
                now: DateTime(2026, 10, 16, 23),
              ),
            ),
          ),
        ),
      );
      expect(find.text('22:00 ~ 02:00 (익일)'), findsOneWidget);
      expect(find.text('오늘 여기서 영업 중'), findsOneWidget);
    });
  });

  group('⑤ 예외 일정과 "오늘만 영업"', () {
    test('하루 대체 — 그 날만 핀이 옮겨간다', () {
      final doc = savedDoc(
        buildByHost().upsertException(
          ScheduleException(
            id: 'e1',
            dateKey: ScheduleException.dateKeyOf(nextMonday),
            mode: ScheduleExceptionMode.replaceDay,
            slot: slot(festival, '10:00', '18:00'),
          ),
        ),
      );
      expect(pinFor(doc, date: nextMonday, now: monday)?.lat, festival.latitude);
      expect(pinFor(doc, date: monday, now: monday)?.lat, hongdae.latitude);
    });

    test('예외 휴무 — 그 날만 핀이 사라진다', () {
      final doc = savedDoc(
        buildByHost().upsertException(
          ScheduleException(
            id: 'e2',
            dateKey: ScheduleException.dateKeyOf(nextMonday),
            mode: ScheduleExceptionMode.closed,
          ),
        ),
      );
      expect(pinFor(doc, date: nextMonday, now: monday), isNull);
      expect(pinFor(doc, date: monday, now: monday), isNotNull);
    });

    test('예외를 지우면 정기 장소로 돌아온다', () {
      final withException = buildByHost().upsertException(
        ScheduleException(
          id: 'e3',
          dateKey: ScheduleException.dateKeyOf(nextMonday),
          mode: ScheduleExceptionMode.replaceDay,
          slot: slot(festival),
        ),
      );
      final restored = MobilePlaceSchedule.ofPlace(
        savedDoc(withException.withoutExceptionOn(nextMonday)),
      )!;
      expect(restored.openingOn(nextMonday)?.stop, hongdae);
    });

    testWidgets('오늘만 영업 — 오늘 핀·상세가 함께 바뀌고 다음 주는 그대로', (tester) async {
      final doc = savedDoc(
        buildByHost().withTodayStop(
          monday,
          stop: festival,
          startTime: '12:00',
          endTime: '19:00',
        ),
      );
      final now = DateTime(2026, 10, 12, 13);

      final pin = pinFor(doc, now: now)!;
      expect(pin.lat, festival.latitude);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MobileScheduleDetailCard(
                schedule: MobilePlaceSchedule.ofPlace(doc)!,
                placeName: '파티츄 푸드트럭',
                focusDate: pin.opening?.start,
                now: now,
              ),
            ),
          ),
        ),
      );
      final row = tester.widget<PlaceAddressRow>(find.byType(PlaceAddressRow));
      expect(row.latitude, festival.latitude, reason: '핀과 상세가 어긋났다');
      expect(find.text('이 날만'), findsOneWidget);

      // 다음 주 같은 요일은 정기 장소.
      expect(
        pinFor(doc, date: nextMonday, now: now)?.lat,
        hongdae.latitude,
      );
      // 내일은 화요일 정기 장소(오늘 변경이 번지지 않는다).
      expect(pinFor(doc, date: tuesday, now: now)?.lat, gangnam.latitude);
    });
  });

  group('⑥ 상세 화면 안에서 날짜를 바꿔도 어긋나지 않는다', () {
    testWidgets('칩으로 날짜를 옮기면 길찾기 좌표가 함께 따라온다', (tester) async {
      final doc = savedDoc(buildByHost());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MobileScheduleDetailCard(
                schedule: MobilePlaceSchedule.ofPlace(doc)!,
                placeName: '파티츄 푸드트럭',
                now: DateTime(2026, 10, 12, 13),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.widget<PlaceAddressRow>(find.byType(PlaceAddressRow)).latitude,
        hongdae.latitude,
      );

      await tester.tap(
        find.byKey(MobileScheduleDetailCard.dateChipKey(wednesday)),
      );
      await tester.pump();

      final row = tester.widget<PlaceAddressRow>(find.byType(PlaceAddressRow));
      expect(row.latitude, yeouido.latitude);
      expect(row.address, contains('여의도로 1'));
      // 그 날짜의 지도 핀과도 같다.
      expect(
        pinFor(doc, date: wednesday, now: DateTime(2026, 10, 12, 13))?.lat,
        row.latitude,
      );
    });
  });

  group('⑦ 기존·신규 혼합 — 한 지도에서', () {
    test('고정형은 문서 좌표, 이동형은 그 날 좌표, 휴무는 빠진다', () {
      final docs = <String, Map<String, dynamic>>{
        'fixed': {
          'name': '혼술바',
          'latitude': 37.5665,
          'longitude': 126.9780,
          'address': '서울 중구',
        },
        'truck': savedDoc(buildByHost()),
        'closedTruck': savedDoc(
          const MobilePlaceSchedule()
              .withRegular(DateTime.monday, slot(gangnam))
              .withClosedWeekday(DateTime.monday, true),
        ),
      };
      final pins = <String, MapListing?>{
        for (final e in docs.entries)
          e.key: pinFor(e.value, date: monday, now: monday),
      };
      expect(pins['fixed']?.lat, 37.5665);
      expect(pins['truck']?.lat, hongdae.latitude);
      expect(pins['closedTruck'], isNull);
    });
  });

  group('🔴 아직 이어지지 않은 곳 — 이 테스트가 드러낸 것', () {
    // 아래 두 단정은 **지금 동작을 사실대로 적은 것**이다. 고치면 깨진다 —
    // 즉 이 자리가 다음에 손볼 곳임을 표시해 둔다(보고서의 '수정 필요').

    test('목록 탭의 날짜 판정은 아직 placeWeeklyHours만 본다', () {
      // 이동형 문서에도 운영시간이 함께 저장되므로(등록 화면이 쓴다),
      // 목록 탭은 트럭을 **고정 운영시간**으로 걸러 낸다. 지도와 답이 갈린다.
      final doc = savedDoc(buildByHost());
      expect(doc['placeWeeklyHours'], isNotNull);
      // 저장된 운영시간(09:00~18:00)은 실제 영업(11:00~20:00)과 다르다.
      final hours = (doc['placeWeeklyHours'] as Map)['월'] as Map;
      expect(hours['open'], '09:00');
      expect(
        MobilePlaceSchedule.ofPlace(doc)!.openingOn(monday)?.start.hour,
        11,
        reason: '운영시간과 이동형 일정이 어긋난 상태가 저장된다',
      );
    });

    test('지도 카드(PlaceCompactCard)는 아직 기준 주소를 쓴다', () {
      // 카드는 `item.data`를 그대로 받으므로 `opening`을 모른다.
      final doc = savedDoc(buildByHost());
      expect(doc['address'], '서울 중구 어딘가');
      final pin = pinFor(doc, date: monday, now: monday)!;
      // 핀 좌표는 홍대인데 문서 주소는 중구다 — 카드가 이 값을 쓴다.
      expect(pin.lat, hongdae.latitude);
      expect(
        pin.shortAddress,
        '홍대',
        reason: 'MapListing.shortAddress는 고쳤다(마커 탭 카드용)',
      );
    });
  });
}

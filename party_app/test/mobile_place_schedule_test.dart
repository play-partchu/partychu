// 🚚 이동형 플레이스(푸드트럭) 영업 일정 — 모델과 해석.
//
// **불변식: 한 업체는 하루에 한 장소에서 영업한다.**
//
//     월: 홍대 · 화: 강남 · 수: 여의도 · 목: 휴무
//
// 이 파일이 지키는 것은 그 불변식과, 그것이 지도 핀으로 번역되는 규칙이다:
//
//   · 요일당 장소 하나, 날짜당 예외 하나, 예외 안의 장소도 하나
//   · 예외가 정기를 이기고, 지우면 정기로 **되돌아온다**
//   · 일정이 없는 날·휴무일에는 **아무 것도 돌려주지 않는다**
//   · 시간은 **영업 여부를 가리는 게이트**다 — 장소를 고르는 데 쓰지 않는다
//   · 자정을 넘기는 영업이 새벽 검색에 걸린다
//   · "오늘 여기서 영업해요"가 정기 일정을 건드리지 않는다
//   · 고정형 장소는 이 코드를 타지 않는다

import 'dart:io';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/mobile_place_schedule.dart';

/// 2026-10-12는 **월요일**이다(아래 guard 테스트가 확인한다).
final monday = DateTime(2026, 10, 12);
final tuesday = DateTime(2026, 10, 13);
final wednesday = DateTime(2026, 10, 14);
final thursday = DateTime(2026, 10, 15);
final friday = DateTime(2026, 10, 16);
final saturday = DateTime(2026, 10, 17);
final sunday = DateTime(2026, 10, 18);
final nextMonday = DateTime(2026, 10, 19);

ScheduledStop stopAt(String name, [double lat = 37.5, double lng = 127.0]) =>
    ScheduledStop(
      placeName: name,
      address: '$name 앞',
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
  String id = 'x',
}) => ScheduleException(
  id: id,
  dateKey: ScheduleException.dateKeyOf(date),
  mode: mode,
  slot: slot,
);

/// 사용자가 든 예시 그대로 — 월 홍대 / 화 강남 / 수 여의도 / 목 휴무.
final example = MobilePlaceSchedule(
  regular: {
    DateTime.monday: slot(hongdae),
    DateTime.tuesday: slot(gangnam),
    DateTime.wednesday: slot(yeouido),
  },
  closedWeekdays: const {DateTime.thursday},
);

void main() {
  test('테스트가 쓰는 날짜의 요일이 맞다', () {
    expect(monday.weekday, DateTime.monday);
    expect(thursday.weekday, DateTime.thursday);
    expect(friday.weekday, DateTime.friday);
    expect(saturday.weekday, DateTime.saturday);
    expect(nextMonday.weekday, DateTime.monday);
  });

  group('고정형 장소는 이 코드를 타지 않는다', () {
    test('isMobilePlace가 없으면 null — 옛 문서에 일정이 생기지 않는다', () {
      expect(MobilePlaceSchedule.ofPlace({'name': '혼술바'}), isNull);
      expect(
        MobilePlaceSchedule.ofPlace({'latitude': 37.5, 'longitude': 127.0}),
        isNull,
      );
    });

    test('isMobilePlace가 false면 null', () {
      expect(
        MobilePlaceSchedule.ofPlace({
          'isMobilePlace': false,
          'mobileSchedule': {},
        }),
        isNull,
      );
    });

    test('isMobilePlace가 true면 일정이 비어 있어도 객체를 돌려준다', () {
      final s = MobilePlaceSchedule.ofPlace({'isMobilePlace': true});
      expect(s, isNotNull);
      expect(s!.isEmpty, isTrue);
    });
  });

  group('날짜별 한 장소 — 요일마다 다른 곳', () {
    test('예시대로 요일마다 한 곳씩 나온다', () {
      expect(example.openingOn(monday)?.stop, hongdae);
      expect(example.openingOn(tuesday)?.stop, gangnam);
      expect(example.openingOn(wednesday)?.stop, yeouido);
      expect(example.openingOn(thursday), isNull, reason: '휴무인데 영업이 나왔다');
    });

    test('일정을 넣지 않은 요일에는 아무것도 없다', () {
      expect(example.openingOn(friday), isNull);
      expect(example.openingOn(saturday), isNull);
      expect(example.openingOn(sunday), isNull);
    });

    test('돌려주는 값이 **하나**다 — 타입이 이미 막는다', () {
      // openingOn은 PlaceOpening? 하나다. 목록이 아니므로 "하루 두 곳"을
      // 표현할 방법이 없다.
      final opening = example.openingOn(monday);
      expect(opening, isA<PlaceOpening?>());
      expect(opening?.start, DateTime(2026, 10, 12, 11));
      expect(opening?.end, DateTime(2026, 10, 12, 20));
    });

    test('같은 요일에 다시 넣으면 **갈아 끼운다** — 쌓이지 않는다', () {
      var s = example;
      s = s.withRegular(DateTime.monday, slot(gangnam));
      expect(s.regular[DateTime.monday]!.stop, gangnam);
      expect(s.regular.length, 3, reason: '요일 수가 늘었다');
      expect(s.openingOn(monday)?.stop, gangnam);
    });

    test('장소를 넣으면 그 요일 휴무가 풀린다', () {
      final s = example.withRegular(DateTime.thursday, slot(festival));
      expect(s.closedWeekdays, isNot(contains(DateTime.thursday)));
      expect(s.openingOn(thursday)?.stop, festival);
    });

    test('정기 일정을 지울 수 있다', () {
      final s = example.withoutRegular(DateTime.monday);
      expect(s.openingOn(monday), isNull);
      expect(s.openingOn(tuesday)?.stop, gangnam, reason: '다른 요일이 함께 지워졌다');
    });

    test('휴무를 켜도 등록해 둔 장소는 남는다', () {
      final s = example.withClosedWeekday(DateTime.monday, true);
      expect(s.openingOn(monday), isNull);
      expect(s.regular[DateTime.monday]!.stop, hongdae, reason: '휴무를 켜며 장소를 지웠다');
      // 끄면 그대로 살아난다.
      expect(
        s.withClosedWeekday(DateTime.monday, false).openingOn(monday)?.stop,
        hongdae,
      );
    });

    test('좌표가 0인 장소는 영업이 되지 않는다 — (0,0)에 핀을 찍지 않는다', () {
      final s = MobilePlaceSchedule(
        regular: {
          DateTime.monday: slot(const ScheduledStop(latitude: 0, longitude: 0)),
        },
      );
      expect(s.openingOn(monday), isNull);
    });

    test('시간 형식이 아니면 영업이 되지 않는다 — 추측하지 않는다', () {
      final s = MobilePlaceSchedule(
        regular: {DateTime.monday: slot(hongdae, '점심때', '저녁')},
      );
      expect(s.openingOn(monday), isNull);
    });
  });

  group('예외가 정기를 이긴다 — 날짜당 하나', () {
    test('하루 대체 — 그 날만 다른 곳', () {
      final s = example.upsertException(
        exception(
          nextMonday,
          ScheduleExceptionMode.replaceDay,
          slot: slot(festival, '10:00', '18:00'),
        ),
      );
      expect(s.openingOn(nextMonday)?.stop, festival);
      expect(s.openingOn(nextMonday)?.isException, isTrue);
      // 같은 요일의 다른 주는 그대로.
      expect(s.openingOn(monday)?.stop, hongdae);
    });

    test('휴무 — 그 날은 쉰다', () {
      final s = example.upsertException(
        exception(nextMonday, ScheduleExceptionMode.closed),
      );
      expect(s.openingOn(nextMonday), isNull);
      expect(s.openingOn(monday)?.stop, hongdae);
    });

    test('모드는 둘뿐이다 — 정기에 "더하는" 모드가 없다', () {
      expect(ScheduleExceptionMode.values, [
        ScheduleExceptionMode.replaceDay,
        ScheduleExceptionMode.closed,
      ]);
    });

    test('같은 날짜에 예외를 다시 넣으면 갈아 끼운다', () {
      var s = example.upsertException(
        exception(nextMonday, ScheduleExceptionMode.closed, id: 'a'),
      );
      s = s.upsertException(
        exception(
          nextMonday,
          ScheduleExceptionMode.replaceDay,
          slot: slot(festival),
          id: 'b',
        ),
      );
      expect(s.exceptions, hasLength(1));
      expect(s.exceptions.single.id, 'b');
      expect(s.openingOn(nextMonday)?.stop, festival);
    });

    test('한 날짜에 예외가 여러 건이어도 답이 순서에 흔들리지 않는다', () {
      // 손으로 넣은 문서 등 — closed가 섞여 있으면 쉬는 쪽을 따른다.
      final closedLast = example.copyWith(
        exceptions: [
          exception(
            nextMonday,
            ScheduleExceptionMode.replaceDay,
            slot: slot(festival),
            id: 'a',
          ),
          exception(nextMonday, ScheduleExceptionMode.closed, id: 'b'),
        ],
      );
      final closedFirst = example.copyWith(
        exceptions: [
          exception(nextMonday, ScheduleExceptionMode.closed, id: 'b'),
          exception(
            nextMonday,
            ScheduleExceptionMode.replaceDay,
            slot: slot(festival),
            id: 'a',
          ),
        ],
      );
      expect(closedLast.openingOn(nextMonday), isNull);
      expect(closedFirst.openingOn(nextMonday), isNull);
    });

    test('정기 일정이 없는 날짜에도 예외로 영업할 수 있다', () {
      final s = example.upsertException(
        exception(
          saturday,
          ScheduleExceptionMode.replaceDay,
          slot: slot(festival),
        ),
      );
      expect(s.openingOn(saturday)?.stop, festival);
    });

    test('예외에 장소가 없으면 영업이 아니다', () {
      final s = example.upsertException(
        exception(nextMonday, ScheduleExceptionMode.replaceDay),
      );
      expect(s.openingOn(nextMonday), isNull);
    });

    test('다른 날짜의 예외는 영향이 없다', () {
      final s = example.upsertException(
        exception(tuesday, ScheduleExceptionMode.closed),
      );
      expect(s.openingOn(monday)?.stop, hongdae);
    });
  });

  group('예외 삭제 후 정기 장소 복귀', () {
    test('하루 대체를 지우면 정기 장소로 돌아온다', () {
      final s = example.upsertException(
        exception(
          nextMonday,
          ScheduleExceptionMode.replaceDay,
          slot: slot(festival),
        ),
      );
      expect(s.openingOn(nextMonday)?.stop, festival);
      final restored = s.withoutExceptionOn(nextMonday);
      expect(
        restored.openingOn(nextMonday)?.stop,
        hongdae,
        reason: '예외를 지웠는데 정기 장소로 돌아오지 않았다',
      );
      expect(restored.exceptions, isEmpty);
    });

    test('휴무 예외를 지워도 정기 장소로 돌아온다', () {
      final s = example
          .upsertException(exception(nextMonday, ScheduleExceptionMode.closed))
          .withoutExceptionOn(nextMonday);
      expect(s.openingOn(nextMonday)?.stop, hongdae);
    });

    test('정기 휴무 요일의 예외를 지우면 다시 휴무다', () {
      final s = example
          .upsertException(
            exception(
              DateTime(2026, 10, 22), // 목요일
              ScheduleExceptionMode.replaceDay,
              slot: slot(festival),
            ),
          )
          .withoutExceptionOn(DateTime(2026, 10, 22));
      expect(DateTime(2026, 10, 22).weekday, DateTime.thursday);
      expect(s.openingOn(DateTime(2026, 10, 22)), isNull);
    });
  });

  group('오늘 여기서 영업해요 — 오늘만', () {
    test('오늘만 장소가 바뀌고 다음 주 같은 요일은 그대로다', () {
      final s = example.withTodayStop(
        monday,
        stop: festival,
        startTime: '12:00',
        endTime: '19:00',
      );
      expect(s.openingOn(monday)?.stop, festival);
      expect(
        s.openingOn(nextMonday)?.stop,
        hongdae,
        reason: '정기 일정이 바뀌었다 — 하루만 바꾸는 기능이 아니게 됐다',
      );
      expect(s.regular, example.regular, reason: 'regular가 변경됐다');
    });

    test('다음 날에는 영향이 없다', () {
      final s = example.withTodayStop(
        monday,
        stop: festival,
        startTime: '12:00',
        endTime: '19:00',
      );
      expect(s.openingOn(tuesday)?.stop, gangnam, reason: '내일 일정까지 바뀌었다');
    });

    test('두 번 눌러도 예외가 쌓이지 않는다', () {
      final once = example.withTodayStop(
        monday,
        stop: festival,
        startTime: '12:00',
        endTime: '19:00',
      );
      final twice = once.withTodayStop(
        monday,
        stop: yeouido,
        startTime: '13:00',
        endTime: '20:00',
      );
      expect(twice.exceptions, hasLength(1));
      expect(twice.openingOn(monday)?.stop, yeouido);
    });

    test('되돌리면 정기 장소로 복귀한다', () {
      final s = example
          .withTodayStop(
            monday,
            stop: festival,
            startTime: '12:00',
            endTime: '19:00',
          )
          .withoutExceptionOn(monday);
      expect(s.openingOn(monday)?.stop, hongdae);
    });
  });

  group('시간 필터는 영업 여부 게이트다 — 장소를 고르지 않는다', () {
    final s = MobilePlaceSchedule(
      regular: {DateTime.monday: slot(hongdae, '11:00', '15:00')},
    );

    test('시간을 고르지 않으면 그 날 일정이 있으면 통과', () {
      expect(s.openingFor(date: monday)?.stop, hongdae);
    });

    test('영업 중인 시각이면 통과', () {
      expect(
        s
            .openingFor(
              date: monday,
              startTime: const TimeOfDay(hour: 12, minute: 0),
            )
            ?.stop,
        hongdae,
      );
    });

    test('영업하지 않는 시각이면 **그 업체가 빠진다** — 다른 장소로 바뀌지 않는다', () {
      expect(
        s.openingFor(
          date: monday,
          startTime: const TimeOfDay(hour: 18, minute: 0),
        ),
        isNull,
      );
    });

    test('구간을 고르면 겹치면 통과', () {
      expect(
        s
            .openingFor(
              date: monday,
              startTime: const TimeOfDay(hour: 14, minute: 0),
              endTime: const TimeOfDay(hour: 18, minute: 0),
            )
            ?.stop,
        hongdae,
      );
      expect(
        s.openingFor(
          date: monday,
          startTime: const TimeOfDay(hour: 16, minute: 0),
          endTime: const TimeOfDay(hour: 18, minute: 0),
        ),
        isNull,
      );
    });

    test('휴무일에는 시간을 어떻게 걸어도 null', () {
      for (final t in [null, const TimeOfDay(hour: 12, minute: 0)]) {
        expect(example.openingFor(date: thursday, startTime: t), isNull);
      }
    });

    test('일정이 없는 날에는 시간을 어떻게 걸어도 null', () {
      expect(example.openingFor(date: saturday), isNull);
    });
  });

  group('자정 넘김 — 기존 DayTimeMatch 정본을 쓴다', () {
    final s = MobilePlaceSchedule(
      regular: {DateTime.friday: slot(gangnam, '22:00', '02:00')},
    );

    test('종료가 시작보다 이르면 다음 날로 넘어간다', () {
      final fri = s.openingOn(friday)!;
      expect(fri.start, DateTime(2026, 10, 16, 22));
      expect(fri.end, DateTime(2026, 10, 17, 2));
    });

    test('토요일 01:00 검색에 금요일 밤 영업이 걸린다', () {
      expect(
        s
            .openingFor(
              date: saturday,
              startTime: const TimeOfDay(hour: 1, minute: 0),
            )
            ?.stop,
        gangnam,
      );
    });

    test('토요일 05:00에는 걸리지 않는다 — 이미 닫았다', () {
      expect(
        s.openingFor(
          date: saturday,
          startTime: const TimeOfDay(hour: 5, minute: 0),
        ),
        isNull,
      );
    });

    test('그 날짜 자신의 일정이 있으면 그쪽이 우선이다 — 결과는 언제나 하나', () {
      final both = MobilePlaceSchedule(
        regular: {
          DateTime.friday: slot(gangnam, '22:00', '02:00'),
          DateTime.saturday: slot(hongdae, '11:00', '15:00'),
        },
      );
      // 토요일 01:00은 금요일 밤 구간에만 들어간다.
      expect(
        both
            .openingFor(
              date: saturday,
              startTime: const TimeOfDay(hour: 1, minute: 0),
            )
            ?.stop,
        gangnam,
      );
      // 날짜만 고르면 토요일 자신의 일정이 이긴다.
      expect(both.openingFor(date: saturday)?.stop, hongdae);
    });

    test('그 순간 영업 중인 곳을 집어낸다', () {
      expect(s.openingAt(DateTime(2026, 10, 17, 1, 30))?.stop, gangnam);
      expect(s.openingAt(DateTime(2026, 10, 17, 3)), isNull);
      expect(s.openingAt(DateTime(2026, 10, 16, 21, 59)), isNull);
    });
  });

  group('과거 일정이 현재에 남지 않는다', () {
    test('지난 예외만 있는 업체는 오늘 결과가 없다', () {
      final s = MobilePlaceSchedule(
        exceptions: [
          exception(
            DateTime(2026, 9, 20),
            ScheduleExceptionMode.replaceDay,
            slot: slot(festival),
          ),
        ],
      );
      expect(s.openingFor(date: monday), isNull);
      expect(s.openingAt(DateTime(2026, 10, 12, 13)), isNull);
      expect(s.nextOpeningAfter(DateTime(2026, 10, 12, 9)), isNull);
    });
  });

  group('다음 영업 예정', () {
    test('같은 날 아직 안 열었으면 그것을 집는다', () {
      final next = example.nextOpeningAfter(DateTime(2026, 10, 12, 9));
      expect(next?.stop, hongdae);
      expect(next?.start, DateTime(2026, 10, 12, 11));
    });

    test('오늘 영업이 끝났으면 다음 날로 넘어간다', () {
      final next = example.nextOpeningAfter(DateTime(2026, 10, 12, 21));
      expect(next?.stop, gangnam);
      expect(next?.start, DateTime(2026, 10, 13, 11));
    });

    test('휴무일은 다음 영업 후보에서 빠진다', () {
      // 수요일 20시 이후 → 목요일 휴무를 건너뛰고 다음 주 월요일.
      final next = example.nextOpeningAfter(DateTime(2026, 10, 14, 21));
      expect(next?.stop, hongdae);
      expect(next?.start, DateTime(2026, 10, 19, 11));
    });

    test('창 안에 일정이 없으면 null — 없는 예정을 만들지 않는다', () {
      final onlyMonday = MobilePlaceSchedule(
        regular: {DateTime.monday: slot(hongdae)},
      );
      expect(
        onlyMonday.nextOpeningAfter(DateTime(2026, 10, 12, 21), withinDays: 3),
        isNull,
      );
    });
  });

  group('보관 기간 — 90일', () {
    final now = DateTime(2026, 10, 12);
    final s = MobilePlaceSchedule(
      exceptions: [
        exception(DateTime(2026, 10, 10), ScheduleExceptionMode.closed, id: 'recent'),
        exception(DateTime(2026, 7, 20), ScheduleExceptionMode.closed, id: 'edge-in'),
        exception(DateTime(2026, 5, 1), ScheduleExceptionMode.closed, id: 'old'),
        exception(nextMonday, ScheduleExceptionMode.closed, id: 'future'),
      ],
    );

    test('보관 창이 90일이다', () {
      expect(MobilePlaceSchedule.retention, const Duration(days: 90));
    });

    test('창 안과 밖을 가른다', () {
      expect(s.exceptionsWithin(now).map((e) => e.id), [
        'recent',
        'edge-in',
        'future',
      ]);
      expect(s.exceptionsBeyondRetention(now).map((e) => e.id), ['old']);
    });

    test('목록에는 오늘 이후만, 지난 것은 개수로만', () {
      expect(s.upcomingExceptions(now).map((e) => e.id), ['future']);
      expect(s.pastExceptionCount(now), 3);
    });

    test('toMap은 오래된 예외도 **버리지 않는다** — 임의 삭제 금지', () {
      expect((s.toMap()['exceptions'] as List), hasLength(4));
    });

    test('prunedBeyondRetention은 사본만 만든다', () {
      expect(s.prunedBeyondRetention(now).exceptions, hasLength(3));
      expect(s.exceptions, hasLength(4), reason: '원본이 변경됐다');
    });
  });

  group('저장 왕복', () {
    test('fromMap(toMap())이 같은 해석을 낸다', () {
      final original = example.upsertException(
        exception(
          nextMonday,
          ScheduleExceptionMode.replaceDay,
          slot: slot(festival, '10:00', '02:00'),
          id: 'x1',
        ),
      );
      final round = MobilePlaceSchedule.fromMap(original.toMap());

      expect(round.regular.keys.toList()..sort(), [1, 2, 3]);
      expect(round.closedWeekdays, {DateTime.thursday});
      expect(round.exceptions, hasLength(1));
      expect(round.openingOn(monday)?.stop, hongdae);
      expect(round.openingOn(tuesday)?.stop, gangnam);
      expect(round.openingOn(thursday), isNull);
      expect(round.openingOn(nextMonday)?.stop, festival);
      // 자정 넘김도 그대로.
      expect(round.openingOn(nextMonday)?.end, DateTime(2026, 10, 20, 2));
    });

    test('판 번호를 함께 저장한다', () {
      expect(const MobilePlaceSchedule().toMap()['version'], 2);
    });

    test('요일 키는 문자열 1~7이다 — Firestore 맵 키 규칙', () {
      final saved = example.toMap()['regular'] as Map;
      expect(saved.keys.toList(), ['1', '2', '3']);
    });

    test('휴무 예외는 slot 없이 저장된다', () {
      final saved =
          MobilePlaceSchedule(
                exceptions: [exception(monday, ScheduleExceptionMode.closed)],
              ).toMap()['exceptions']
              as List;
      expect((saved.single as Map).containsKey('slot'), isFalse);
    });

    test('망가진 입력은 조용히 건너뛴다 — 예외를 던지지 않는다', () {
      final s = MobilePlaceSchedule.fromMap({
        'regular': {
          '99': {'startTime': '11:00'},
          'abc': {'startTime': '11:00'},
          '1': '문자열',
        },
        'closedWeekdays': ['3', 99, null],
        'exceptions': [
          {'date': '2026-13-45', 'mode': 'closed'},
          {'mode': 'closed'},
          {'date': '2026-10-12', 'mode': '모르는모드'},
        ],
      });
      expect(s.regular, isEmpty);
      expect(s.closedWeekdays, {3});
      expect(s.exceptions.where((e) => e.date != null), isEmpty);
      expect(s.openingOn(monday), isNull);
    });

    test('필드 이름이 기존 문서와 충돌하지 않는다', () {
      expect(MobilePlaceSchedule.fieldName, 'mobileSchedule');
      expect(MobilePlaceSchedule.isMobileFieldName, 'isMobilePlace');
    });
  });

  group('읽기 호환 — 옛 형식(복수 장소)도 깨지지 않는다', () {
    test('옛 목록 형식을 읽고, 같은 요일은 첫 번째만 쓴다', () {
      final s = MobilePlaceSchedule.fromMap({
        'regular': [
          {
            'weekday': 1,
            'startTime': '11:00',
            'endTime': '14:00',
            'stop': {'placeName': '홍대', 'latitude': 37.5563, 'longitude': 126.9236},
          },
          {
            'weekday': 1,
            'startTime': '18:00',
            'endTime': '22:00',
            'stop': {'placeName': '강남', 'latitude': 37.4979, 'longitude': 127.0276},
          },
        ],
      });
      expect(s.regular, hasLength(1));
      expect(s.openingOn(monday)?.stop.placeName, '홍대');
      expect(s.openingOn(monday)?.start, DateTime(2026, 10, 12, 11));
    });

    test("옛 'addSlot' 모드는 하루 대체로 읽는다", () {
      final s = MobilePlaceSchedule.fromMap({
        'exceptions': [
          {
            'date': '2026-10-19',
            'mode': 'addSlot',
            'slots': [
              {
                'startTime': '10:00',
                'endTime': '20:00',
                'stop': {
                  'placeName': '축제장',
                  'latitude': 37.5,
                  'longitude': 127.0,
                },
              },
            ],
          },
        ],
      });
      expect(s.exceptions.single.mode, ScheduleExceptionMode.replaceDay);
      expect(s.exceptions.single.slot?.stop.placeName, '축제장');
    });

    test("옛 'slots' 목록은 첫 번째만 쓴다", () {
      final s = MobilePlaceSchedule.fromMap({
        'exceptions': [
          {
            'date': '2026-10-19',
            'mode': 'replaceDay',
            'slots': [
              {
                'startTime': '10:00',
                'endTime': '14:00',
                'stop': {'placeName': '첫째', 'latitude': 37.5, 'longitude': 127.0},
              },
              {
                'startTime': '18:00',
                'endTime': '22:00',
                'stop': {'placeName': '둘째', 'latitude': 37.6, 'longitude': 127.1},
              },
            ],
          },
        ],
      });
      expect(s.openingOn(nextMonday)?.stop.placeName, '첫째');
    });

    test('새 형식과 옛 형식을 섞어도 읽힌다', () {
      final s = MobilePlaceSchedule.fromMap({
        'regular': {
          '2': {
            'startTime': '11:00',
            'endTime': '20:00',
            'stop': {'placeName': '강남', 'latitude': 37.4979, 'longitude': 127.0276},
          },
        },
        'exceptions': [
          {
            'date': '2026-10-19',
            'mode': 'addSlot',
            'slot': {
              'startTime': '10:00',
              'endTime': '20:00',
              'stop': {'placeName': '축제장', 'latitude': 37.5, 'longitude': 127.0},
            },
          },
        ],
      });
      expect(s.openingOn(tuesday)?.stop.placeName, '강남');
      expect(s.openingOn(nextMonday)?.stop.placeName, '축제장');
    });
  });

  group('검증 — 구조가 막는 것을 또 지키지 않는다', () {
    test('겹침 검사가 사라졌다 — 요일당 하나라서 겹칠 수 없다', () {
      final src = File(
        'lib/models/mobile_place_schedule.dart',
      ).readAsStringSync();
      expect(
        src.contains('overlappingRegular'),
        isFalse,
        reason: '구조로 막는 것을 경고로 또 지키면 둘 중 하나가 낡는다',
      );
    });

    test('빈 일정은 저장할 수 없다', () {
      expect(const MobilePlaceSchedule().validationErrors(), isNotEmpty);
    });

    test('좌표 없는 장소를 짚어 준다', () {
      final s = MobilePlaceSchedule(
        regular: {
          DateTime.monday: slot(const ScheduledStop(latitude: 0, longitude: 0)),
        },
      );
      expect(s.validationErrors().any((e) => e.contains('위치')), isTrue);
    });

    test('온전한 일정은 오류가 없다', () {
      expect(example.validationErrors(), isEmpty);
    });
  });

  group('실시간 GPS가 아니다 — 이름과 구조로 못 박는다', () {
    final src = File(
      'lib/models/mobile_place_schedule.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final code = src
        .split('\n')
        .map((l) {
          final c = l.indexOf('//');
          return c < 0 ? l : l.substring(0, c);
        })
        .join('\n');

    test('실시간 추적을 뜻하는 식별자를 쓰지 않는다', () {
      for (final forbidden in [
        'Geolocator',
        'getCurrentPosition',
        'liveLocation',
        'trackLocation',
        'currentPosition',
      ]) {
        expect(code.contains(forbidden), isFalse, reason: '$forbidden 을 쓰고 있다');
      }
    });

    test('자정 넘김 규칙을 복사하지 않고 정본을 가져다 쓴다', () {
      expect(
        src,
        contains("import 'package:party_app/models/day_time_match.dart'"),
      );
      expect(code, contains('DayTimeMatch.matches'));
      expect(code, contains('DayInterval.fromHhmm'));
      expect(
        RegExp(r'\b1440\b').hasMatch(code),
        isFalse,
        reason: '자정 넘김 계산을 모델 안에 복사했다',
      );
    });
  });
}

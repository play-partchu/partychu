// 🗓 예외 일정 UI와 "오늘 여기서 영업해요!".
//
// **날짜당 장소 하나**가 불변식이다. 그래서 모드가 둘뿐이고
// (`하루 대체`·`휴무`), 한 날짜에 장소를 더 넣는 버튼이 화면에 없다.
//
// 지키는 것:
//
//  · 예외가 정기를 이기고, **지우면 정기로 되돌아온다**
//  · 날짜당 하나 — 같은 날짜를 몇 번 등록해도 쌓이지 않는다
//  · "오늘"은 오늘만 — 내일과 다음 주 같은 요일은 그대로다
//  · 모드를 바꿔도 **등록해 둔 장소를 지우지 않는다**(되돌릴 수 있어야 한다)
//  · 판정 로직은 모델에만 있다

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/mobile_place_schedule.dart';
import 'package:party_app/widgets/place_form/mobile_exception_editor.dart';

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

const _kEditor = 'lib/widgets/place_form/mobile_exception_editor.dart';
const _kSection = 'lib/widgets/place_form/mobile_schedule_section.dart';

/// 2026-10-12는 월요일.
final monday = DateTime(2026, 10, 12);
final tuesday = DateTime(2026, 10, 13);
final nextMonday = DateTime(2026, 10, 19);

ScheduledStop stopAt(String name) => ScheduledStop(
  placeName: name,
  address: '$name 앞',
  latitude: 37.5,
  longitude: 127.0,
);

final hongdae = stopAt('홍대');
final gangnam = stopAt('강남');
final festival = stopAt('축제장');

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

/// 월 홍대 — 예외가 이 위에 얹힌다.
final base = MobilePlaceSchedule(
  regular: {DateTime.monday: slot(hongdae, '11:00', '14:00')},
);

void main() {
  /// 편집기를 띄운다. 장소·시간 선택은 **가짜**로 바꿔 끼워 실제 화면 이동
  /// 없이 흐름만 확인한다(장소 선택 화면 자체는 섹션 테스트가 검증한다).
  ({
    Widget widget,
    List<MobilePlaceSchedule> calls,
    List<String> pickTitles,
    List<ScheduledStop?> pickStopInitials,
  })
  host({
    required MobilePlaceSchedule schedule,
    ScheduledStop? pickedStop,
    String? pickedStart,
    String? pickedEnd,
  }) {
    final calls = <MobilePlaceSchedule>[];
    final pickTitles = <String>[];
    final pickStopInitials = <ScheduledStop?>[];
    var timeCall = 0;
    return (
      widget: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MobileExceptionEditor(
              schedule: schedule,
              today: monday,
              onChanged: calls.add,
              onPickStop: ({ScheduledStop? initial}) async {
                pickStopInitials.add(initial);
                return pickedStop;
              },
              onPickTime: ({required initial, required title}) async {
                pickTitles.add(title);
                timeCall++;
                return timeCall == 1 ? pickedStart : pickedEnd;
              },
            ),
          ),
        ),
      ),
      calls: calls,
      pickTitles: pickTitles,
      pickStopInitials: pickStopInitials,
    );
  }

  group('모드는 둘뿐이다', () {
    testWidgets('하루 대체와 휴무만 보인다 — "일정 추가"가 없다', (tester) async {
      await tester.pumpWidget(
        host(
          schedule: base.upsertException(
            exception(
              nextMonday,
              ScheduleExceptionMode.replaceDay,
              slot: slot(festival, '10:00', '20:00'),
            ),
          ),
        ).widget,
      );
      expect(find.text('하루 대체'), findsOneWidget);
      expect(find.text('휴무'), findsOneWidget);
      expect(
        find.text('일정 추가'),
        findsNothing,
        reason: '"정기에 더하는" 모드가 다시 생겼다 — 하루 두 곳이 된다',
      );
    });

    test('모델 쪽 모드도 둘이다', () {
      expect(ScheduleExceptionMode.values, hasLength(2));
    });

    testWidgets('한 날짜에 장소를 더 넣는 버튼이 없다', (tester) async {
      await tester.pumpWidget(
        host(
          schedule: base.upsertException(
            exception(
              nextMonday,
              ScheduleExceptionMode.replaceDay,
              slot: slot(festival),
            ),
          ),
        ).widget,
      );
      expect(find.text('+ 이 날 장소 추가'), findsNothing);
      expect(find.text('장소 변경'), findsOneWidget);
    });
  });

  group('오늘 여기서 영업해요!', () {
    testWidgets('버튼과 안내가 보인다', (tester) async {
      await tester.pumpWidget(host(schedule: base).widget);
      expect(find.text('오늘 여기서 영업해요!'), findsOneWidget);
      expect(
        find.text('오늘 하루만 장소를 바꿔요. 다음 주 정기 일정은 그대로예요.'),
        findsOneWidget,
      );
    });

    testWidgets('장소·시간을 고르면 오늘만 대체된다', (tester) async {
      final h = host(
        schedule: base,
        pickedStop: festival,
        pickedStart: '12:00',
        pickedEnd: '19:00',
      );
      await tester.pumpWidget(h.widget);
      await tester.tap(find.byKey(MobileExceptionEditor.todayButtonKey()));
      await tester.pumpAndSettle();

      expect(h.pickTitles, ['오늘 영업 시작 시간', '오늘 영업 종료 시간']);
      final next = h.calls.single;
      expect(next.openingOn(monday)?.stop, festival);
      expect(next.openingOn(monday)?.start, DateTime(2026, 10, 12, 12));
      // 다음 주 같은 요일은 그대로.
      expect(next.openingOn(nextMonday)?.stop, hongdae);
      // 내일에도 영향이 없다.
      expect(next.openingOn(tuesday), isNull);
      // 정기 일정 자체가 바뀌지 않았다.
      expect(next.regular, base.regular);
    });

    testWidgets('장소 선택을 취소하면 아무 일도 없다', (tester) async {
      final h = host(schedule: base);
      await tester.pumpWidget(h.widget);
      await tester.tap(find.byKey(MobileExceptionEditor.todayButtonKey()));
      await tester.pumpAndSettle();
      expect(h.calls, isEmpty);
    });

    testWidgets('반복해서 눌러도 예외가 쌓이지 않는다', (tester) async {
      var schedule = base;
      for (final stop in [festival, gangnam, hongdae]) {
        final h = host(
          schedule: schedule,
          pickedStop: stop,
          pickedStart: '12:00',
          pickedEnd: '19:00',
        );
        await tester.pumpWidget(h.widget);
        await tester.tap(find.byKey(MobileExceptionEditor.todayButtonKey()));
        await tester.pumpAndSettle();
        schedule = h.calls.single;
      }
      expect(schedule.exceptions, hasLength(1), reason: '예외가 중복으로 쌓였다');
      expect(schedule.openingOn(monday)?.stop, hongdae);
    });

    testWidgets('이미 설정되어 있으면 지금 장소를 보여 준다', (tester) async {
      await tester.pumpWidget(
        host(
          schedule: base.withTodayStop(
            monday,
            stop: festival,
            startTime: '12:00',
            endTime: '19:00',
          ),
        ).widget,
      );
      expect(find.text('오늘은 축제장에서 영업해요'), findsOneWidget);
    });
  });

  group('예외 카드 — 날짜별 장소 변경', () {
    final withException = base.upsertException(
      exception(
        nextMonday,
        ScheduleExceptionMode.replaceDay,
        slot: slot(festival, '10:00', '20:00'),
      ),
    );

    testWidgets('날짜·모드·설명이 보인다', (tester) async {
      await tester.pumpWidget(host(schedule: withException).widget);
      expect(find.text('10월 19일 (월)'), findsOneWidget);
      expect(find.text('이 날은 정기 장소 대신 아래 한 곳에서 영업해요.'), findsOneWidget);
      expect(find.text('축제장'), findsOneWidget);
      expect(find.text('10:00'), findsOneWidget);
    });

    testWidgets('정기보다 우선이라고 표시한다', (tester) async {
      await tester.pumpWidget(host(schedule: withException).widget);
      expect(find.text('예외 일정'), findsOneWidget);
      expect(find.text('정기보다 우선'), findsOneWidget);
    });

    testWidgets('휴무로 바꾸면 장소를 지우지 않고 쉰다', (tester) async {
      final h = host(schedule: withException);
      await tester.pumpWidget(h.widget);
      await tester.tap(
        find.byKey(
          MobileExceptionEditor.modeKey(
            '2026-10-19',
            ScheduleExceptionMode.closed,
          ),
        ),
      );
      await tester.pump();

      final next = h.calls.single;
      expect(next.openingOn(nextMonday), isNull);
      expect(
        next.exceptions.single.slot,
        isNotNull,
        reason: '휴무로 바꾸며 장소를 지웠다 — 되돌릴 수 없게 된다',
      );
    });

    testWidgets('휴무에서 하루 대체로 되돌리면 장소가 살아난다', (tester) async {
      final h = host(
        schedule: base.upsertException(
          exception(
            nextMonday,
            ScheduleExceptionMode.closed,
            slot: slot(festival),
          ),
        ),
      );
      await tester.pumpWidget(h.widget);
      await tester.tap(
        find.byKey(
          MobileExceptionEditor.modeKey(
            '2026-10-19',
            ScheduleExceptionMode.replaceDay,
          ),
        ),
      );
      await tester.pump();
      expect(h.calls.single.openingOn(nextMonday)?.stop, festival);
    });

    testWidgets('휴무 카드는 장소 영역을 감추고 되돌릴 수 있다고 알린다', (tester) async {
      await tester.pumpWidget(
        host(
          schedule: base.upsertException(
            exception(
              nextMonday,
              ScheduleExceptionMode.closed,
              slot: slot(festival),
            ),
          ),
        ).widget,
      );
      expect(find.text('이 날은 쉬어요. 정기 일정도 적용되지 않아요.'), findsOneWidget);
      expect(find.text('장소 변경'), findsNothing);
      expect(find.textContaining('모드를 바꾸면 돌아와요'), findsOneWidget);
    });

    testWidgets('장소를 다시 고를 때 기존 값을 넘겨 준다', (tester) async {
      final h = host(schedule: withException, pickedStop: gangnam);
      await tester.pumpWidget(h.widget);
      await tester.tap(find.text('장소 변경'));
      await tester.pumpAndSettle();
      expect(h.pickStopInitials, [festival]);
      expect(h.calls.single.openingOn(nextMonday)?.stop, gangnam);
      // 시간은 그대로.
      expect(h.calls.single.openingOn(nextMonday)?.start, DateTime(2026, 10, 19, 10));
    });

    testWidgets('장소를 바꿔도 예외가 하나다', (tester) async {
      final h = host(schedule: withException, pickedStop: gangnam);
      await tester.pumpWidget(h.widget);
      await tester.tap(find.text('장소 변경'));
      await tester.pumpAndSettle();
      expect(h.calls.single.exceptions, hasLength(1));
    });

    testWidgets('장소가 비어 있으면 선택 버튼을 보여 준다', (tester) async {
      await tester.pumpWidget(
        host(
          schedule: base.upsertException(
            exception(nextMonday, ScheduleExceptionMode.replaceDay),
          ),
        ).widget,
      );
      expect(find.text('이 날 영업할 장소 선택'), findsOneWidget);
    });

    testWidgets('자정을 넘기는 예외에 익일 표시가 붙는다', (tester) async {
      await tester.pumpWidget(
        host(
          schedule: base.upsertException(
            exception(
              nextMonday,
              ScheduleExceptionMode.replaceDay,
              slot: slot(festival, '22:00', '02:00'),
            ),
          ),
        ).widget,
      );
      expect(find.text('익일'), findsOneWidget);
    });
  });

  group('정기 일정 복귀', () {
    testWidgets('예외를 지우면 그 날짜가 정기 일정으로 돌아온다', (tester) async {
      final h = host(
        schedule: base.upsertException(
          exception(
            nextMonday,
            ScheduleExceptionMode.replaceDay,
            slot: slot(festival),
          ),
        ),
      );
      await tester.pumpWidget(h.widget);
      await tester.tap(
        find.byKey(MobileExceptionEditor.removeExceptionKey('2026-10-19')),
      );
      await tester.pump();

      final next = h.calls.single;
      expect(next.exceptions, isEmpty);
      expect(
        next.openingOn(nextMonday)?.stop,
        hongdae,
        reason: '예외를 지웠는데 정기 일정으로 돌아오지 않았다',
      );
    });

    testWidgets('휴무 예외를 지워도 정기 일정으로 돌아온다', (tester) async {
      final h = host(
        schedule: base.upsertException(
          exception(nextMonday, ScheduleExceptionMode.closed),
        ),
      );
      await tester.pumpWidget(h.widget);
      await tester.tap(
        find.byKey(MobileExceptionEditor.removeExceptionKey('2026-10-19')),
      );
      await tester.pump();
      expect(h.calls.single.openingOn(nextMonday)?.stop, hongdae);
    });
  });

  group('휴무와 장소 변경이 부딪히지 않게 안내한다', () {
    testWidgets('정기 장소가 없는 요일에 대체를 두면 짚어 준다', (tester) async {
      await tester.pumpWidget(
        host(
          schedule: MobilePlaceSchedule(
            exceptions: [
              exception(
                nextMonday,
                ScheduleExceptionMode.replaceDay,
                slot: slot(festival),
              ),
            ],
          ),
        ).widget,
      );
      expect(
        find.text('이 요일에는 정기 장소가 없어요. 대체가 아니라 이 날만 새로 영업하는 것과 같아요.'),
        findsOneWidget,
      );
    });

    testWidgets('정기 휴무 요일에 대체를 두면 같은 안내가 나온다', (tester) async {
      await tester.pumpWidget(
        host(
          schedule: base.copyWith(closedWeekdays: const {DateTime.monday}).
              upsertException(
            exception(
              nextMonday,
              ScheduleExceptionMode.replaceDay,
              slot: slot(festival),
            ),
          ),
        ).widget,
      );
      expect(find.textContaining('정기 장소가 없어요'), findsOneWidget);
    });

    testWidgets('정기 장소가 있으면 불필요한 안내를 띄우지 않는다', (tester) async {
      await tester.pumpWidget(
        host(
          schedule: base.upsertException(
            exception(
              nextMonday,
              ScheduleExceptionMode.replaceDay,
              slot: slot(festival),
            ),
          ),
        ).widget,
      );
      expect(find.byIcon(Icons.info_outline), findsNothing);
    });
  });

  group('예외 날짜 추가 — 날짜 선택부터', () {
    testWidgets('버튼을 누르면 날짜 선택기가 열린다', (tester) async {
      await tester.pumpWidget(host(schedule: base).widget);
      await tester.tap(find.byKey(MobileExceptionEditor.addExceptionKey()));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
    });

    test('과거 날짜는 고를 수 없게 막는다', () {
      final code = _codeOnly(_kEditor);
      expect(code, contains('firstDate: _today'));
      expect(code, contains("helpText: '예외 날짜 선택'"));
    });

    test('날짜 → 장소 → 시간 순서로 묻는다', () {
      final code = _codeOnly(_kEditor);
      final addBlock = code.substring(
        code.indexOf('Future<void> _addException('),
        code.indexOf('Future<void> _editSlotStop('),
      );
      final date = addBlock.indexOf('showDatePicker(');
      final stop = addBlock.indexOf('onPickStop(');
      final time = addBlock.indexOf('onPickTime(');
      expect(date, greaterThan(-1));
      expect(stop, greaterThan(date), reason: '장소를 날짜보다 먼저 묻는다');
      expect(time, greaterThan(stop), reason: '시간을 장소보다 먼저 묻는다');
    });

    test('새 예외는 하루 대체로 만들고, 같은 날짜는 갈아 끼운다', () {
      final code = _codeOnly(_kEditor);
      expect(code, contains('mode: ScheduleExceptionMode.replaceDay'));
      expect(code, contains('schedule.upsertException('));
      // 예전처럼 슬롯을 누적하지 않는다.
      expect(
        code.contains('...e.slots'),
        isFalse,
        reason: '한 날짜에 장소를 쌓는 코드가 남아 있다',
      );
    });

    test('지난 예외 개수 안내가 남아 있다', () {
      expect(_codeOnly(_kEditor), contains('schedule.pastExceptionCount('));
    });
  });

  group('모델만 쓴다 — 중복 로직 금지', () {
    final editor = _codeOnly(_kEditor);

    test('날짜당 하나 규칙을 모델에 맡긴다', () {
      expect(editor, contains('schedule.upsertException('));
      expect(editor, contains('schedule.withTodayStop('));
      expect(editor, contains('schedule.withoutExceptionOn('));
      expect(editor, contains('schedule.upcomingExceptions('));
      expect(editor, contains('schedule.exceptionFor('));
    });

    test('시간 계산을 위젯에 복사하지 않았다', () {
      expect(
        RegExp(r'\b1440\b').hasMatch(editor),
        isFalse,
        reason: '자정 넘김 계산을 위젯에 복사했다',
      );
      expect(editor, contains('slot.interval'));
    });

    test('요일 라벨을 다시 적지 않았다', () {
      expect(editor, contains('PlaceWeeklyHours.weekdays['));
      expect(RegExp(r"\['월',\s*'화'").hasMatch(editor), isFalse);
    });

    test('Firestore를 직접 건드리지 않는다', () {
      for (final forbidden in [
        'FirebaseFirestore',
        'FieldValue',
        'collection(',
      ]) {
        expect(editor.contains(forbidden), isFalse, reason: '$forbidden 을 쓰고 있다');
      }
    });

    test('실시간 GPS를 쓰지 않는다 — 예정 좌표만 다룬다', () {
      for (final forbidden in [
        'Geolocator',
        'getCurrentPosition',
        'liveLocation',
      ]) {
        expect(editor.contains(forbidden), isFalse);
      }
    });
  });

  group('지도 핀 선택 화면을 새로 만들지 않았다', () {
    test('편집기는 좌표를 스스로 고르지 않고 콜백으로만 받는다', () {
      final editor = _codeOnly(_kEditor);
      for (final forbidden in [
        'NaverMap',
        'NLatLng',
        'AddressSearchScreen',
        'Navigator.push',
      ]) {
        expect(
          editor.contains(forbidden),
          isFalse,
          reason: '$forbidden 을 쓰고 있다 — 장소 선택은 호출부가 한다',
        );
      }
      expect(editor, contains('onPickStop'));
    });

    test('장소 선택은 기존 주소 검색 하나로 모인다', () {
      final section = _codeOnly(_kSection);
      expect(section, contains('PartyLocationPickerScreen('));
      expect(section.contains('NaverMap'), isFalse);
      expect(section, contains('onPickStop: ({ScheduledStop? initial}) =>'));
      expect(section, contains('onPickTime: ({required String initial'));
    });

    test('좌표 자리는 그대로 남아 있다 — 나중에 핀으로 바꿀 수 있다', () {
      const stop = ScheduledStop(latitude: 37.5, longitude: 127.0);
      expect(stop.hasCoordinates, isTrue);
      expect(stop.toMap()['latitude'], 37.5);
      expect(stop.toMap()['longitude'], 127.0);
    });
  });

  group('정기와 예외를 갈라 보여 준다', () {
    test('섹션이 둘 사이에 구분선을 둔다', () {
      final section = _codeOnly(_kSection);
      final regular = section.indexOf('_regularEditor(context)');
      final divider = section.indexOf('Divider(');
      final exceptionEditor = section.indexOf('MobileExceptionEditor(');
      expect(regular, greaterThan(-1));
      expect(divider, greaterThan(regular));
      expect(
        exceptionEditor,
        greaterThan(divider),
        reason: '예외 편집기가 구분선 앞에 있다',
      );
    });
  });

  group('좁은 화면', () {
    testWidgets('320px에서 오버플로가 없다', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        host(
          schedule: base.copyWith(closedWeekdays: const {1}).upsertException(
            exception(
              nextMonday,
              ScheduleExceptionMode.replaceDay,
              slot: slot(stopAt('아주아주 긴 이름의 예외 영업 장소입니다'), '22:00', '02:00'),
            ),
          ),
        ).widget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}

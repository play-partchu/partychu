// 🚚 "장소가 매번 바뀌시나요?" 섹션과 정기 일정 편집기.
//
// **요일당 장소 하나**가 이 UI의 불변식이다. 그래서 버튼이 "장소 추가"가
// 아니라 **"장소 변경"**이고, 같은 요일에 둘을 넣을 방법이 화면에 없다.
//
// 그리고 지키는 것 두 가지:
//
//  1. **기존 고정형 등록이 한 걸음도 달라지지 않는다.** 기본값이 '아니요'이고,
//     그 상태에서는 일정 UI가 아예 그려지지 않는다.
//  2. **판정 로직이 두 곳으로 갈라지지 않는다.** 요일 좌표·`'HH:mm'` 해석·
//     자정 넘김은 모델([MobilePlaceSchedule])만 쓴다.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/mobile_place_schedule.dart';
import 'package:party_app/widgets/place_form/mobile_schedule_section.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

/// 주석을 걷어낸 소스 — 설명문의 낱말이 감사에 걸리지 않게 한다.
String _codeOnly(String path) => _read(path)
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .split('\n')
    .map((line) {
      final c = line.indexOf('//');
      return c < 0 ? line : line.substring(0, c);
    })
    .join('\n');

const _kSection = 'lib/widgets/place_form/mobile_schedule_section.dart';
const _kScreen = 'lib/screens/event_register_screen.dart';

/// 2026-10-12 = 월요일.
final monday = DateTime(2026, 10, 12);

ScheduledStop stopAt(String name) => ScheduledStop(
  placeName: name,
  address: '$name 앞',
  latitude: 37.5,
  longitude: 127.0,
);

ScheduleSlot slot(String name, [String s = '11:00', String e = '20:00']) =>
    ScheduleSlot(stop: stopAt(name), startTime: s, endTime: e);

void main() {
  /// 테스트에서 섹션을 띄우고, 돌아온 값을 받아 둔다.
  ({
    Widget widget,
    List<bool> isMobileCalls,
    List<MobilePlaceSchedule> scheduleCalls,
  })
  host({bool isMobile = false, MobilePlaceSchedule? schedule}) {
    final isMobileCalls = <bool>[];
    final scheduleCalls = <MobilePlaceSchedule>[];
    return (
      widget: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MobileScheduleSection(
              isMobile: isMobile,
              schedule: schedule ?? const MobilePlaceSchedule(),
              today: monday,
              onIsMobileChanged: isMobileCalls.add,
              onChanged: scheduleCalls.add,
            ),
          ),
        ),
      ),
      isMobileCalls: isMobileCalls,
      scheduleCalls: scheduleCalls,
    );
  }

  group('기본값은 고정형 — 기존 등록 흐름 그대로', () {
    testWidgets('질문과 선택지 두 줄만 보인다', (tester) async {
      await tester.pumpWidget(host().widget);

      expect(find.text('장소가 매번 바뀌시나요?'), findsOneWidget);
      expect(
        find.text('푸드트럭, 이동식 팝업스토어 등 여러 장소에서 운영하는 경우 선택해 주세요.'),
        findsOneWidget,
      );
      expect(find.text('아니요, 고정된 장소에서 운영해요.'), findsOneWidget);
      expect(find.text('네, 여러 장소를 이동하며 운영해요.'), findsOneWidget);
    });

    testWidgets("'아니요'일 때 일정 UI가 아예 없다", (tester) async {
      await tester.pumpWidget(host().widget);
      expect(find.text('정기 영업 일정'), findsNothing);
      expect(find.text('예외 일정'), findsNothing);
      expect(find.text('장소 선택'), findsNothing);
      expect(find.text('휴무'), findsNothing);
      expect(
        find.byKey(MobileScheduleSection.closedToggleKey(DateTime.monday)),
        findsNothing,
      );
    });

    testWidgets("'아니요'가 선택된 상태로 그려진다", (tester) async {
      await tester.pumpWidget(host().widget);
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
    });

    testWidgets("'네'를 누르면 알린다 — 스스로 상태를 바꾸지 않는다", (tester) async {
      final h = host();
      await tester.pumpWidget(h.widget);
      await tester.tap(find.text('네, 여러 장소를 이동하며 운영해요.'));
      await tester.pump();

      expect(h.isMobileCalls, [true]);
      expect(find.text('정기 영업 일정'), findsNothing);
    });

    testWidgets("'아니요'로 되돌릴 수 있다", (tester) async {
      final h = host(isMobile: true);
      await tester.pumpWidget(h.widget);
      await tester.tap(find.text('아니요, 고정된 장소에서 운영해요.'));
      await tester.pump();
      expect(h.isMobileCalls, [false]);
    });
  });

  group('요일당 한 장소', () {
    testWidgets('월~일 일곱 칸과 장소 선택 버튼이 있다', (tester) async {
      await tester.pumpWidget(host(isMobile: true).widget);
      expect(find.text('정기 영업 일정'), findsOneWidget);
      expect(
        find.text('요일마다 영업하는 장소 한 곳과 시간을 등록해 주세요. 하루에 한 장소만 등록할 수 있어요.'),
        findsOneWidget,
      );
      for (final day in ['월', '화', '수', '목', '금', '토', '일']) {
        expect(find.text(day), findsOneWidget, reason: '$day 칸이 없다');
      }
      expect(find.text('장소 선택'), findsNWidgets(7));
      expect(find.text('등록된 장소가 없어요'), findsNWidgets(7));
    });

    testWidgets('"장소 추가" 버튼이 **없다** — 추가할 자리가 없다', (tester) async {
      await tester.pumpWidget(host(isMobile: true).widget);
      expect(
        find.text('+ 장소 추가'),
        findsNothing,
        reason: '요일당 여러 장소를 넣는 버튼이 다시 생겼다',
      );
    });

    testWidgets('등록된 장소는 "한 곳"으로 표시되고 변경 버튼이 붙는다', (tester) async {
      await tester.pumpWidget(
        host(
          isMobile: true,
          schedule: MobilePlaceSchedule(
            regular: {DateTime.monday: slot('홍대', '11:00', '14:00')},
          ),
        ).widget,
      );
      expect(find.text('홍대'), findsOneWidget);
      expect(find.text('11:00'), findsOneWidget);
      expect(find.text('14:00'), findsOneWidget);
      expect(find.text('한 곳'), findsOneWidget);
      expect(find.text('장소 변경'), findsOneWidget);
      // 그 요일에는 '장소 선택' 버튼이 사라진다.
      expect(find.text('장소 선택'), findsNWidgets(6));
    });

    testWidgets('예시대로 요일마다 다른 곳을 보여 준다', (tester) async {
      await tester.pumpWidget(
        host(
          isMobile: true,
          schedule: MobilePlaceSchedule(
            regular: {
              DateTime.monday: slot('홍대'),
              DateTime.tuesday: slot('강남'),
              DateTime.wednesday: slot('여의도'),
            },
            closedWeekdays: const {DateTime.thursday},
          ),
        ).widget,
      );
      expect(find.text('홍대'), findsOneWidget);
      expect(find.text('강남'), findsOneWidget);
      expect(find.text('여의도'), findsOneWidget);
      expect(find.text('한 곳'), findsNWidgets(3));
      expect(find.text('이 요일은 쉬어요'), findsOneWidget);
    });

    testWidgets('자정을 넘기는 일정에 익일 표시가 붙는다', (tester) async {
      await tester.pumpWidget(
        host(
          isMobile: true,
          schedule: MobilePlaceSchedule(
            regular: {DateTime.friday: slot('강남', '22:00', '02:00')},
          ),
        ).widget,
      );
      expect(find.text('익일'), findsOneWidget);
    });

    testWidgets('좌표 없는 장소는 선택을 유도한다', (tester) async {
      await tester.pumpWidget(
        host(
          isMobile: true,
          schedule: const MobilePlaceSchedule(
            regular: {
              1: ScheduleSlot(
                stop: ScheduledStop(latitude: 0, longitude: 0),
                startTime: '11:00',
                endTime: '14:00',
              ),
            },
          ),
        ).widget,
      );
      expect(find.text('장소를 선택해주세요'), findsOneWidget);
    });
  });

  group('수정과 삭제', () {
    testWidgets('삭제를 누르면 그 요일만 빠진다', (tester) async {
      final h = host(
        isMobile: true,
        schedule: MobilePlaceSchedule(
          regular: {
            DateTime.monday: slot('홍대'),
            DateTime.tuesday: slot('강남'),
          },
        ),
      );
      await tester.pumpWidget(h.widget);
      await tester.tap(find.byTooltip('삭제').first);
      await tester.pump();

      expect(h.scheduleCalls, hasLength(1));
      expect(h.scheduleCalls.single.regular.keys, [DateTime.tuesday]);
      expect(h.scheduleCalls.single.openingOn(monday), isNull);
    });

    testWidgets('휴무를 켜면 일정을 지우지 않고 요일만 쉰다', (tester) async {
      final h = host(
        isMobile: true,
        schedule: MobilePlaceSchedule(regular: {DateTime.monday: slot('홍대')}),
      );
      await tester.pumpWidget(h.widget);
      await tester.tap(
        find.byKey(MobileScheduleSection.closedToggleKey(DateTime.monday)),
      );
      await tester.pump();

      final next = h.scheduleCalls.single;
      expect(next.closedWeekdays, contains(DateTime.monday));
      expect(next.regular, hasLength(1), reason: '휴무를 켜며 일정을 지웠다');
      expect(next.openingOn(monday), isNull);
    });

    testWidgets('휴무를 끄면 등록해 둔 일정이 살아난다', (tester) async {
      final h = host(
        isMobile: true,
        schedule: MobilePlaceSchedule(
          regular: {DateTime.monday: slot('홍대')},
          closedWeekdays: const {DateTime.monday},
        ),
      );
      await tester.pumpWidget(h.widget);
      await tester.tap(
        find.byKey(MobileScheduleSection.closedToggleKey(DateTime.monday)),
      );
      await tester.pump();

      final next = h.scheduleCalls.single;
      expect(next.closedWeekdays, isNot(contains(DateTime.monday)));
      expect(next.openingOn(monday)?.stop.placeName, '홍대');
    });

    testWidgets('휴무인 요일은 장소 버튼을 감춘다', (tester) async {
      await tester.pumpWidget(
        host(
          isMobile: true,
          schedule: const MobilePlaceSchedule(closedWeekdays: {1, 2}),
        ).widget,
      );
      expect(find.text('장소 선택'), findsNWidgets(5));
    });
  });

  group('겹침 경고가 사라졌다 — 구조가 막는다', () {
    testWidgets('같은 요일에 둘을 넣을 수 없으므로 경고도 없다', (tester) async {
      await tester.pumpWidget(
        host(
          isMobile: true,
          schedule: MobilePlaceSchedule(
            regular: {
              DateTime.monday: slot('홍대', '11:00', '15:00'),
              DateTime.tuesday: slot('강남', '14:00', '18:00'),
            },
          ),
        ).widget,
      );
      expect(find.textContaining('겹치는'), findsNothing);
    });

    test('섹션 소스에 겹침 경고가 남아 있지 않다', () {
      final section = _codeOnly(_kSection);
      expect(section.contains('overlappingRegular'), isFalse);
      expect(section.contains('_warning'), isFalse);
    });
  });

  group('좁은 화면', () {
    testWidgets('320px에서 오버플로가 없다', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        host(
          isMobile: true,
          schedule: MobilePlaceSchedule(
            regular: {
              DateTime.saturday: slot('아주아주 긴 장소 이름이 들어간 푸드트럭 영업 장소'),
            },
          ),
        ).widget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('모델만 쓴다 — 중복 로직 금지', () {
    final section = _codeOnly(_kSection);

    test('시간 계산을 위젯 안에 복사하지 않았다', () {
      expect(
        RegExp(r'\b1440\b').hasMatch(section),
        isFalse,
        reason: '자정 넘김 계산을 위젯에 복사했다',
      );
      expect(section, contains('slot.interval'));
    });

    test('요일당 하나를 모델 메서드로 지킨다', () {
      expect(section, contains('schedule.withRegular('));
      expect(section, contains('schedule.withoutRegular('));
      expect(section, contains('schedule.withClosedWeekday('));
      // 맵을 직접 조립하지 않는다 — "요일당 하나" 규칙이 두 곳으로 갈라진다.
      expect(
        RegExp(r'copyWith\(\s*regular:').hasMatch(section),
        isFalse,
        reason: '위젯이 regular 맵을 직접 손대고 있다',
      );
    });

    test('요일 라벨도 기존 정본에서 가져온다', () {
      expect(section, contains('PlaceWeeklyHours.weekdays['));
      expect(
        RegExp(r"\['월',\s*'화'").hasMatch(section),
        isFalse,
        reason: '요일 배열을 위젯에 다시 적었다',
      );
    });

    test('장소 선택은 기존 화면을 재사용한다 — 새 픽커를 만들지 않았다', () {
      expect(section, contains('PartyLocationPickerScreen('));
      expect(section, contains('showWheelTimePicker('));
      expect(
        section.contains('NaverMap'),
        isFalse,
        reason: '새 지도 선택 화면이 생겼다 — 향후 작업으로 미룬 것이다',
      );
    });

    test('Firestore를 직접 건드리지 않는다', () {
      for (final forbidden in [
        'FirebaseFirestore',
        'collection(',
        'FieldValue',
      ]) {
        expect(
          section.contains(forbidden),
          isFalse,
          reason: '$forbidden 을 쓰고 있다 — 저장은 등록 화면이 한다',
        );
      }
    });

    test('실시간 GPS를 쓰지 않는다', () {
      for (final forbidden in ['Geolocator', 'getCurrentPosition']) {
        expect(section.contains(forbidden), isFalse);
      }
    });
  });

  group('등록 화면 연결 — 기존 동작 보존', () {
    final screen = _codeOnly(_kScreen);

    test('기본값이 고정형이다', () {
      expect(screen, contains('bool _isMobilePlace = false;'));
      expect(
        screen,
        contains(
          'MobilePlaceSchedule _mobileSchedule = const MobilePlaceSchedule();',
        ),
      );
    });

    test('필드 이름을 문자열로 다시 적지 않고 모델 상수를 쓴다', () {
      expect(screen, contains('MobilePlaceSchedule.isMobileFieldName'));
      expect(screen, contains('MobilePlaceSchedule.fieldName'));
      expect(screen.contains("'isMobilePlace'"), isFalse);
      expect(screen.contains("'mobileSchedule'"), isFalse);
    });

    test('수정으로 열 때 필드가 없으면 고정형이다', () {
      expect(
        screen,
        contains(
          '_isMobilePlace = d[MobilePlaceSchedule.isMobileFieldName] == true;',
        ),
      );
    });

    test('옛 임시저장도 고정형으로 열린다', () {
      expect(
        screen,
        contains(
          '_isMobilePlace = p[MobilePlaceSchedule.isMobileFieldName] as bool? ?? false;',
        ),
      );
    });

    test('옛 문서에 없던 필드를 새로 만들지 않는다 — 운영시간과 같은 규칙', () {
      expect(
        screen,
        contains(
          'if (!_isEdit || _mobileScheduleTouched || _hadMobileSchedule) {',
        ),
      );
    });

    test('고정형으로 되돌려도 일정을 지우지 않는다', () {
      expect(
        RegExp(
          r'MobilePlaceSchedule\.fieldName\]\s*=\s*FieldValue\.delete',
        ).hasMatch(screen),
        isFalse,
        reason: '고정형 전환이 등록해 둔 일정을 삭제한다',
      );
    });

    test('기존 운영시간·방문예약 저장이 그대로다', () {
      expect(
        screen,
        contains("doc['placeWeeklyHours'] = _placeWeeklyHours.toMap();"),
      );
      expect(
        screen,
        contains("doc['weeklyOperatingHours'] = _placeWeeklyHours.toMap();"),
      );
      expect(
        screen,
        contains("doc['visitReservation'] = _visitReservation.toMap();"),
      );
      expect(screen, contains('if (!_isEdit || _hadHours || _hoursTouched) {'));
    });

    test('기존 좌표 저장이 그대로다 — 고정형 지도 동작 보존', () {
      expect(
        screen,
        contains("doc['latitude'] = _selectedAddress?.latitude ?? 0.0;"),
      );
      expect(
        screen,
        contains("doc['longitude'] = _selectedAddress?.longitude ?? 0.0;"),
      );
    });

    test('임시저장에 두 필드가 함께 담긴다', () {
      expect(
        screen,
        contains('MobilePlaceSchedule.isMobileFieldName: _isMobilePlace,'),
      );
      expect(
        screen,
        contains('MobilePlaceSchedule.fieldName: _mobileSchedule.toMap(),'),
      );
    });

    test('섹션이 운영시간 바로 위에 있다', () {
      final section = screen.indexOf('MobileScheduleSection(');
      final hours = screen.indexOf('PlaceHoursSection(');
      expect(section, greaterThan(-1), reason: '섹션이 화면에 없다');
      expect(hours, greaterThan(-1));
      expect(section, lessThan(hours));
    });

    test('본인확인·소셜 로그인 코드를 건드리지 않았다', () {
      for (final untouched in ['signInWith', 'AppReviewLogin', 'niceIntc']) {
        expect(
          screen.contains(untouched),
          isFalse,
          reason: '등록 화면에 $untouched 가 들어왔다',
        );
      }
    });
  });
}

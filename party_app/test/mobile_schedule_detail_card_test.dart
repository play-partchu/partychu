// 🚚 이동형 플레이스 **상세 화면**의 영업 정보 카드.
//
// 날짜마다 영업 장소가 달라지므로, 상세 화면이 답해야 하는 것은 하나다:
// **"오늘(또는 고른 날) 어디서, 몇 시에 하는가."**
//
// 이 파일이 지키는 것:
//
//   · 영업 중 / 영업 전 / 영업 종료 / 휴무를 **정확히 가른다**
//   · 휴무·일정 없는 날에 **장소가 있는 것처럼 보이지 않는다**
//   · 과거 일정은 **기본적으로 숨긴다**
//   · 다음 영업 예정(날짜·장소·시간)을 알려 준다
//   · 지도에서 넘어온 날짜를 **우선** 쓴다
//   · ⚠️ 문서의 **기준 주소를 현재 영업 장소처럼 쓰지 않는다**
//   · 판정 로직은 모델에만 있다

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/mobile_place_schedule.dart';
import 'package:party_app/widgets/mobile_schedule_detail_card.dart';

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

const _kCard = 'lib/widgets/mobile_schedule_detail_card.dart';
const _kDetail = 'lib/screens/event_detail_screen.dart';
const _kMapScreen = 'lib/screens/map_screen.dart';
const _kModel = 'lib/models/mobile_place_schedule.dart';

/// 2026-10-12 = 월요일.
final monday = DateTime(2026, 10, 12);
final tuesday = DateTime(2026, 10, 13);
final wednesday = DateTime(2026, 10, 14);
final thursday = DateTime(2026, 10, 15);
final nextMonday = DateTime(2026, 10, 19);

ScheduledStop stopAt(String name, [double lat = 37.5, double lng = 127.0]) =>
    ScheduledStop(
      placeName: name,
      address: '서울 $name구 어딘가',
      roadAddress: '서울 $name구 $name로 1',
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

/// 월 홍대 / 화 강남 / 수 여의도 / 목 휴무.
final example = MobilePlaceSchedule(
  regular: {
    DateTime.monday: slot(hongdae),
    DateTime.tuesday: slot(gangnam),
    DateTime.wednesday: slot(yeouido),
  },
  closedWeekdays: const {DateTime.thursday},
);

void main() {
  Widget host({
    MobilePlaceSchedule? schedule,
    DateTime? focusDate,
    required DateTime now,
  }) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: MobileScheduleDetailCard(
          schedule: schedule ?? example,
          placeName: '파티츄 푸드트럭',
          focusDate: focusDate,
          now: now,
        ),
      ),
    ),
  );

  group('오늘 영업 중 / 영업 전 / 영업 종료', () {
    testWidgets('영업 시간 안이면 "오늘 여기서 영업 중"', (tester) async {
      await tester.pumpWidget(host(now: DateTime(2026, 10, 12, 13)));
      expect(find.text('오늘 여기서 영업 중'), findsOneWidget);
      expect(find.text('홍대'), findsWidgets);
      // 시간 줄은 머리에만 있어 하나다.
      expect(find.text('11:00 ~ 20:00'), findsOneWidget);
    });

    testWidgets('아직 안 열었으면 "오늘 영업 전"', (tester) async {
      await tester.pumpWidget(host(now: DateTime(2026, 10, 12, 9)));
      expect(find.text('오늘 영업 전'), findsOneWidget);
      expect(find.text('오늘 여기서 영업 중'), findsNothing);
      // 장소·시간은 그대로 보여 준다 — 언제 어디로 가면 되는지가 답이다.
      expect(find.text('홍대'), findsWidgets);
      expect(find.text('11:00 ~ 20:00'), findsOneWidget);
    });

    testWidgets('끝났으면 "오늘 영업 종료"', (tester) async {
      await tester.pumpWidget(host(now: DateTime(2026, 10, 12, 21)));
      expect(find.text('오늘 영업 종료'), findsOneWidget);
      expect(find.text('오늘 여기서 영업 중'), findsNothing);
    });

    testWidgets('종료 시각 정각에는 이미 끝난 것으로 본다', (tester) async {
      await tester.pumpWidget(host(now: DateTime(2026, 10, 12, 20)));
      expect(find.text('오늘 영업 종료'), findsOneWidget);
    });

    testWidgets('개시 시각 정각에는 영업 중이다', (tester) async {
      await tester.pumpWidget(host(now: DateTime(2026, 10, 12, 11)));
      expect(find.text('오늘 여기서 영업 중'), findsOneWidget);
    });
  });

  group('오늘 휴무', () {
    testWidgets('휴무면 휴무로 표시하고 장소를 띄우지 않는다', (tester) async {
      await tester.pumpWidget(host(now: DateTime(2026, 10, 15, 13)));
      expect(find.text('휴무'), findsWidgets);
      expect(find.text('오늘은 영업하지 않아요.'), findsOneWidget);
      // 어떤 장소 이름도 "오늘 여기"로 뜨지 않는다.
      expect(find.text('11:00 ~ 20:00'), findsNothing);
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('일정이 아예 없는 날도 영업하지 않는다고 말한다', (tester) async {
      // 금요일 — 등록된 일정이 없다.
      await tester.pumpWidget(host(now: DateTime(2026, 10, 16, 13)));
      expect(find.text('오늘은 영업하지 않아요.'), findsOneWidget);
    });

    testWidgets('일정이 하나도 없으면 카드가 깨지지 않는다', (tester) async {
      await tester.pumpWidget(
        host(schedule: const MobilePlaceSchedule(), now: DateTime(2026, 10, 12, 13)),
      );
      expect(find.text('오늘은 영업하지 않아요.'), findsOneWidget);
      expect(find.textContaining('다음 영업'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('다음 영업 예정', () {
    testWidgets('날짜·장소·시간을 함께 알려 준다', (tester) async {
      // 목요일(휴무) → 다음 영업은 다음 주 월요일 홍대.
      await tester.pumpWidget(host(now: DateTime(2026, 10, 15, 13)));
      expect(
        find.text('다음 영업 · 10월 19일 (월) 홍대 11:00~20:00'),
        findsOneWidget,
      );
    });

    testWidgets('오늘 영업이 끝났으면 내일 일정을 알려 준다', (tester) async {
      await tester.pumpWidget(host(now: DateTime(2026, 10, 12, 21)));
      expect(
        find.text('다음 영업 · 10월 13일 (화) 강남 11:00~20:00'),
        findsOneWidget,
      );
    });

    testWidgets('보고 있는 날짜의 영업이 곧 다음이면 두 번 말하지 않는다', (tester) async {
      // 오늘 아침 — 오늘 영업이 그대로 "다음"이다.
      await tester.pumpWidget(host(now: DateTime(2026, 10, 12, 9)));
      expect(find.textContaining('다음 영업'), findsNothing);
    });
  });

  group('날짜별 장소 변경', () {
    testWidgets('날짜 칩에 요일·일·장소가 보인다', (tester) async {
      await tester.pumpWidget(host(now: DateTime(2026, 10, 12, 13)));
      expect(find.text('날짜별 영업 장소'), findsOneWidget);
      expect(find.text('오늘'), findsWidgets);
      // 칩 안의 장소 이름(머리의 '홍대'와 함께 2개가 된다).
      expect(find.text('강남'), findsWidgets);
      expect(find.text('여의도'), findsWidgets);
    });

    testWidgets('날짜를 고르면 그 날짜의 장소·주소·시간으로 바뀐다', (tester) async {
      await tester.pumpWidget(host(now: DateTime(2026, 10, 12, 13)));
      await tester.tap(
        find.byKey(MobileScheduleDetailCard.dateChipKey(wednesday)),
      );
      await tester.pump();

      expect(find.text('10월 14일 (수)'), findsOneWidget);
      expect(find.text('영업 예정'), findsOneWidget);
      expect(find.textContaining('서울 여의도구 여의도로 1'), findsOneWidget);
      // 오늘 상태 문구는 사라진다.
      expect(find.text('오늘 여기서 영업 중'), findsNothing);
    });

    testWidgets('휴무일 칩을 고르면 영업하지 않는다고 말한다', (tester) async {
      await tester.pumpWidget(host(now: DateTime(2026, 10, 12, 13)));
      await tester.tap(
        find.byKey(MobileScheduleDetailCard.dateChipKey(thursday)),
      );
      await tester.pump();
      expect(find.text('이 날은 영업하지 않아요.'), findsOneWidget);
    });

    testWidgets('휴무일 칩에는 장소 이름 대신 "휴무"가 적힌다', (tester) async {
      await tester.pumpWidget(host(now: DateTime(2026, 10, 12, 13)));
      final chip = find.byKey(MobileScheduleDetailCard.dateChipKey(thursday));
      expect(
        find.descendant(of: chip, matching: find.text('휴무')),
        findsOneWidget,
        reason: '휴무일 칩에 장소가 있는 것처럼 보인다',
      );
    });
  });

  group('과거 일정은 기본적으로 숨긴다', () {
    testWidgets('날짜 칩이 오늘부터 시작한다', (tester) async {
      await tester.pumpWidget(host(now: DateTime(2026, 10, 14, 13)));
      // 어제(13일) 칩은 없다.
      expect(
        find.byKey(MobileScheduleDetailCard.dateChipKey(tuesday)),
        findsNothing,
        reason: '지난 날짜 칩이 남아 있다',
      );
      expect(
        find.byKey(MobileScheduleDetailCard.dateChipKey(wednesday)),
        findsOneWidget,
      );
    });

    testWidgets('지도에서 과거 날짜가 넘어와도 오늘로 끌어온다', (tester) async {
      await tester.pumpWidget(
        host(focusDate: monday, now: DateTime(2026, 10, 14, 13)),
      );
      // 오늘(수)의 영업을 보여 준다.
      expect(find.text('오늘 여기서 영업 중'), findsOneWidget);
      expect(find.text('여의도'), findsWidgets);
    });
  });

  group('예외 일정 적용 및 삭제 후 복귀', () {
    testWidgets('예외가 있으면 그 장소를 보여 주고 "이 날만" 배지를 붙인다', (tester) async {
      await tester.pumpWidget(
        host(
          schedule: example.upsertException(
            exception(
              nextMonday,
              ScheduleExceptionMode.replaceDay,
              slot: slot(festival, '10:00', '18:00'),
            ),
          ),
          focusDate: nextMonday,
          now: DateTime(2026, 10, 12, 13),
        ),
      );
      expect(find.text('축제장'), findsWidgets);
      expect(find.text('10:00 ~ 18:00'), findsOneWidget);
      expect(find.text('이 날만'), findsOneWidget);
    });

    testWidgets('정기 일정에는 "이 날만" 배지가 없다', (tester) async {
      await tester.pumpWidget(host(now: DateTime(2026, 10, 12, 13)));
      expect(find.text('이 날만'), findsNothing);
    });

    testWidgets('예외 휴무면 그 날 휴무로 보인다', (tester) async {
      await tester.pumpWidget(
        host(
          schedule: example.upsertException(
            exception(nextMonday, ScheduleExceptionMode.closed),
          ),
          focusDate: nextMonday,
          now: DateTime(2026, 10, 12, 13),
        ),
      );
      expect(find.text('이 날은 영업하지 않아요.'), findsOneWidget);
    });

    testWidgets('예외를 지우면 정기 장소로 돌아온다', (tester) async {
      final withException = example.upsertException(
        exception(
          nextMonday,
          ScheduleExceptionMode.replaceDay,
          slot: slot(festival),
        ),
      );
      await tester.pumpWidget(
        host(
          schedule: withException.withoutExceptionOn(nextMonday),
          focusDate: nextMonday,
          now: DateTime(2026, 10, 12, 13),
        ),
      );
      expect(find.text('축제장'), findsNothing);
      expect(find.text('홍대'), findsWidgets);
    });
  });

  group('지도 선택 날짜의 상세 화면 전달', () {
    testWidgets('넘어온 날짜의 영업 정보를 먼저 보여 준다', (tester) async {
      await tester.pumpWidget(
        host(focusDate: wednesday, now: DateTime(2026, 10, 12, 13)),
      );
      expect(find.text('10월 14일 (수)'), findsOneWidget);
      expect(find.text('여의도'), findsWidgets);
      // 오늘(월)의 장소를 머리에 띄우지 않는다.
      expect(find.text('오늘 여기서 영업 중'), findsNothing);
    });

    testWidgets('날짜가 없으면 오늘이 기본값이다', (tester) async {
      await tester.pumpWidget(host(now: DateTime(2026, 10, 13, 13)));
      expect(find.text('오늘 여기서 영업 중'), findsOneWidget);
      expect(find.text('강남'), findsWidgets);
    });

    test('지도가 핀의 날짜를 넘긴다', () {
      final mapScreen = _codeOnly(_kMapScreen);
      expect(mapScreen, contains('focusDate: item.opening?.start'));
    });

    test('상세 화면이 날짜를 선택 인자로 받는다 — 고정형은 영향 없음', () {
      final detail = _codeOnly(_kDetail);
      expect(detail, contains('final DateTime? focusDate;'));
      expect(detail, contains('this.focusDate,'));
      expect(detail, contains('focusDate: widget.focusDate'));
    });
  });

  group('⚠️ 문서의 기준 주소를 현재 영업 장소처럼 쓰지 않는다', () {
    test('카드가 문서를 아예 읽지 않는다 — 일정만 받는다', () {
      final card = _codeOnly(_kCard);
      for (final forbidden in [
        "_data[",
        "eventData",
        "['address']",
        "['latitude']",
        "['longitude']",
        "['roadAddress']",
      ]) {
        expect(
          card.contains(forbidden),
          isFalse,
          reason: '카드가 $forbidden 로 문서의 기준 주소를 읽고 있다',
        );
      }
    });

    testWidgets('길찾기 좌표가 그 날 자리다', (tester) async {
      await tester.pumpWidget(host(now: DateTime(2026, 10, 12, 13)));
      // 주소 줄에 그 날 자리의 도로명이 뜬다.
      expect(find.textContaining('서울 홍대구 홍대로 1'), findsOneWidget);
      // 기준 주소(문서의 '서울 중구')는 이 카드가 모른다.
      expect(find.textContaining('서울 중구'), findsNothing);
    });

    test('상세 화면이 이동형일 때 기준 주소 줄을 쓰지 않는다', () {
      final detail = _codeOnly(_kDetail);
      // 이동형이면 카드, 아니면 기존 PlaceAddressRow — else로 갈린다.
      expect(detail, contains('if (mobileSchedule != null)'));
      expect(detail, contains('else if (location.isNotEmpty) ...['));
      final cardAt = detail.indexOf('MobileScheduleDetailCard(');
      final rowAt = detail.indexOf('PlaceAddressRow(');
      expect(cardAt, greaterThan(-1));
      expect(
        rowAt,
        greaterThan(cardAt),
        reason: '기존 주소 줄이 이동형 카드보다 먼저 그려진다',
      );
    });
  });

  group('고정형 상세 화면 회귀', () {
    final detail = _codeOnly(_kDetail);

    test('이동형 일정이 없으면 null이고, 기존 주소 줄이 그대로다', () {
      expect(detail, contains('MobilePlaceSchedule.ofPlace(_data)'));
      expect(
        detail,
        contains("""PlaceAddressRow(
                      address: location,
                      placeName: name,"""),
      );
      expect(
        detail,
        contains("latitude: (_data['latitude'] as num?)?.toDouble(),"),
      );
    });

    test('고정형 문서는 ofPlace가 null을 돌려준다', () {
      expect(
        MobilePlaceSchedule.ofPlace({
          'name': '혼술바',
          'address': '서울 중구',
          'latitude': 37.5,
          'longitude': 127.0,
        }),
        isNull,
      );
    });

    test('기존 섹션 구성이 그대로다', () {
      for (final kept in [
        'PlaceProductListSection(',
        'PlaceAddressRow.joinAddress(',
        "_data['description']",
        "_data['mainImageUrl']",
      ]) {
        expect(detail, contains(kept), reason: '$kept 가 사라졌다');
      }
    });

    test('본인확인·소셜 로그인·채팅 코드를 건드리지 않았다', () {
      for (final untouched in ['signInWith', 'AppReviewLogin', 'niceIntc']) {
        expect(detail.contains(untouched), isFalse);
      }
    });
  });

  group('중복 로직 금지 — 모델만 쓴다', () {
    final card = _codeOnly(_kCard);

    test('상태·일정 계산을 모델에 넘긴다', () {
      expect(card, contains('schedule.statusOn('));
      expect(card, contains('schedule.upcomingDays('));
      expect(card, contains('schedule.nextOpeningAfter('));
    });

    test('시간 계산을 카드에 복사하지 않았다', () {
      expect(
        RegExp(r'\b1440\b').hasMatch(card),
        isFalse,
        reason: '자정 넘김 계산을 카드에 복사했다',
      );
      for (final forbidden in [
        'DayTimeMatch',
        'DayInterval',
        'openingOn(',
        'closedWeekdays',
        'ScheduleExceptionMode',
      ]) {
        expect(
          card.contains(forbidden),
          isFalse,
          reason: '$forbidden 을 직접 다루고 있다 — 판정이 두 곳으로 갈라진다',
        );
      }
    });

    test('요일 라벨도 기존 정본에서 가져온다', () {
      expect(card, contains('PlaceWeeklyHours.weekdays['));
      expect(RegExp(r"\['월',\s*'화'").hasMatch(card), isFalse);
    });

    test('추가 Firestore 조회를 만들지 않았다', () {
      for (final forbidden in [
        'FirebaseFirestore',
        'collection(',
        'snapshots(',
        'get()',
      ]) {
        expect(card.contains(forbidden), isFalse, reason: '$forbidden 을 쓰고 있다');
      }
    });

    test('실시간 GPS를 쓰지 않는다', () {
      for (final forbidden in ['Geolocator', 'getCurrentPosition']) {
        expect(card.contains(forbidden), isFalse);
      }
    });

    test('상태 판정은 모델이 openingOn 하나로 한다', () {
      final model = _codeOnly(_kModel);
      // statusOn 본문만 — 다음 메서드(upcomingDays) 앞까지 자른다.
      final block = model.substring(
        model.indexOf('statusOn('),
        model.indexOf('upcomingDays('),
      );
      expect(block, contains('openingOn(date)'));
      expect(block, contains('containsMoment('));
      expect(
        RegExp(r'\b1440\b').hasMatch(block),
        isFalse,
        reason: '상태 판정이 시간 계산을 다시 하고 있다',
      );
    });

    test('upcomingDays는 과거를 담지 않는다', () {
      final days = example.upcomingDays(wednesday, days: 3);
      expect(days.map((d) => d.date), [
        wednesday,
        thursday,
        DateTime(2026, 10, 16),
      ]);
      // 휴무일은 opening이 null — 화면이 "없는 영업"을 그릴 수 없다.
      expect(days[1].opening, isNull);
    });
  });

  group('작은 화면 UI 오버플로', () {
    testWidgets('320px에서 오버플로가 없다', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        host(
          schedule: example.upsertException(
            exception(
              nextMonday,
              ScheduleExceptionMode.replaceDay,
              slot: slot(
                stopAt('아주아주 긴 이름을 가진 예외 영업 장소입니다'),
                '22:00',
                '02:00',
              ),
            ),
          ),
          focusDate: nextMonday,
          now: DateTime(2026, 10, 12, 13),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('자정을 넘기는 영업에 (익일)이 붙는다', (tester) async {
      await tester.pumpWidget(
        host(
          schedule: MobilePlaceSchedule(
            regular: {DateTime.monday: slot(hongdae, '22:00', '02:00')},
          ),
          now: DateTime(2026, 10, 12, 23),
        ),
      );
      expect(find.text('22:00 ~ 02:00 (익일)'), findsOneWidget);
      expect(find.text('오늘 여기서 영업 중'), findsOneWidget);
    });

    testWidgets('날짜 칩이 가로로 스크롤된다 — 14개가 세로를 늘리지 않는다', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 720 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(now: DateTime(2026, 10, 12, 13)));
      expect(
        find.descendant(
          of: find.byType(MobileScheduleDetailCard),
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}

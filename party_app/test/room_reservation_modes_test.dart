import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/models/reservation_modes.dart';
import 'package:party_app/widgets/place_form/room_card.dart';

import 'support/field_finders.dart';

// 객실 유형: 예약 방식 복수 선택(숙박/시간제/패키지)과, 선택한 방식의 입력
// 섹션만 펼쳐지는지 확인.

Future<RoomCardState> _pump(
  WidgetTester tester,
  GlobalKey<RoomCardState> key, {
  Map<String, dynamic>? initialData,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: RoomCard(
            key: key,
            index: 0,
            onRemove: () {},
            initialData: initialData,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return key.currentState!;
}

void main() {
  testWidgets('예약 방식 칩 3개(숙박/시간제/패키지)가 보인다', (tester) async {
    await _pump(tester, GlobalKey<RoomCardState>());
    expect(find.text('🛏 숙박'), findsOneWidget);
    expect(find.text('⏱ 시간제'), findsOneWidget);
    expect(find.text('📦 패키지'), findsOneWidget);
    // 단일 선택 시절의 합성 칩은 사라졌다.
    expect(find.text('시간제 + 패키지 둘 다'), findsNothing);
  });

  testWidgets('기본(시간제)에서는 시간제 입력만 펼쳐진다', (tester) async {
    await _pump(tester, GlobalKey<RoomCardState>());
    expect(find.text('시간당 가격 (원) *'), findsOneWidget);
    expect(find.text('1박 요금 (원) *'), findsNothing);
    expect(find.text('패키지 관리 *'), findsNothing);
  });

  testWidgets('숙박을 켜면 숙박 입력이 함께 펼쳐진다(숙박 + 시간제)', (tester) async {
    final key = GlobalKey<RoomCardState>();
    final state = await _pump(tester, key);

    await tester.tap(find.text('🛏 숙박'));
    await tester.pump();

    expect(find.text('1박 요금 (원) *'), findsOneWidget);
    expect(find.text('체크인 / 체크아웃'), findsOneWidget);
    expect(find.text('최소 숙박일'), findsOneWidget);
    // 시간제도 켜져 있으므로 시간제 입력이 그대로 남는다.
    expect(find.text('시간당 가격 (원) *'), findsOneWidget);

    expect(state.getDraftData()['reservationModes'], ['stay', 'hourly']);
  });

  testWidgets('숙박만 남기면 시간제 입력이 사라진다', (tester) async {
    final key = GlobalKey<RoomCardState>();
    final state = await _pump(tester, key);

    await tester.tap(find.text('🛏 숙박'));
    await tester.pump();
    await tester.tap(find.text('⏱ 시간제'));
    await tester.pump();

    expect(find.text('1박 요금 (원) *'), findsOneWidget);
    expect(find.text('시간당 가격 (원) *'), findsNothing);
    // 시간제에만 의미 있는 운영 시간 입력도 함께 숨는다.
    expect(find.text('룸별 운영 시간 (선택)'), findsNothing);

    expect(state.getDraftData()['reservationModes'], ['stay']);
  });

  testWidgets('마지막 하나 남은 방식은 끌 수 없다', (tester) async {
    final key = GlobalKey<RoomCardState>();
    final state = await _pump(tester, key);

    await tester.tap(find.text('⏱ 시간제')); // 유일하게 켜진 방식
    await tester.pump();

    expect(state.getDraftData()['reservationModes'], ['hourly']);
    expect(find.text('시간당 가격 (원) *'), findsOneWidget);
  });

  testWidgets('숙박을 켰는데 1박 요금이 비면 검증 실패', (tester) async {
    final key = GlobalKey<RoomCardState>();
    // 환불 규정은 이 검사의 관심사가 아니지만 저장 게이트라서
    // ([RoomCardState.validate]의 RefundPolicyRule.isMissing), 비워 두면
    // "1박 요금을 채웠는데도 검증 실패"가 되어 이 테스트가 무엇을 보는지
    // 흐려진다. 미리 채워 두고 **1박 요금만** 남긴다.
    // (환불 규정 자체의 게이트는 room_card_refund_policy_test.dart가 본다.)
    final state = await _pump(
      tester,
      key,
      initialData: {
        'refundPolicy': [
          {'daysBefore': 7, 'refundPercent': 100},
        ],
      },
    );

    await tester.tap(find.text('🛏 숙박'));
    await tester.pump();
    await tester.tap(find.text('⏱ 시간제')); // 숙박만 남긴다
    await tester.pump();

    await tester.enterText(fieldWithHint(kRoomNameHint), '디럭스 더블');
    await tester.enterText(find.widgetWithText(TextField, '예: 4'), '2');
    await tester.pump();

    expect(state.validate(), isFalse);
    await tester.pump();
    expect(find.text('1박 요금을 입력해주세요'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, '예: 120000'),
      '120000',
    );
    await tester.pump();
    expect(state.validate(), isTrue);
  });

  testWidgets('저장 형태에 숙박 설정과 구버전 미러가 함께 담긴다', (tester) async {
    final key = GlobalKey<RoomCardState>();
    final state = await _pump(tester, key);

    await tester.tap(find.text('🛏 숙박'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, '예: 120000'),
      '95000',
    );
    await tester.pump();

    final draft = state.getDraftData();
    expect(draft['reservationModes'], ['stay', 'hourly']);
    // 아직 업데이트되지 않은 앱도 최소한 시간제로는 예약할 수 있어야 한다.
    expect(draft['reservationMode'], 'hourly');
    expect(draft['stayPricePerNight'], 95000);
    expect(draft['stayCheckInTime'], '16:00');
    expect(draft['stayCheckOutTime'], '11:00');
    expect(draft['stayMinNights'], 1);
    expect(draft['stayMaxNights'], isNull);
  });

  testWidgets('기존 룸(숙박+패키지) 복원 → 임시저장 왕복', (tester) async {
    final key = GlobalKey<RoomCardState>();
    final state = await _pump(
      tester,
      key,
      initialData: {
        'roomName': '한옥 별채',
        'capacityMin': 2,
        'capacityMax': 6,
        'reservationModes': ['stay', 'package'],
        'stayPricePerNight': 210000,
        'stayCheckInTime': '15:00',
        'stayCheckOutTime': '12:00',
        'stayMinNights': 2,
        'stayMaxNights': 5,
        'packages': [
          {
            'id': 'p1',
            'name': '조식 포함',
            'startTime': '15:00',
            'endTime': '12:00',
          },
        ],
      },
    );

    expect(find.text('1박 요금 (원) *'), findsOneWidget);
    expect(find.text('패키지 관리 *'), findsOneWidget);
    expect(find.text('시간당 가격 (원) *'), findsNothing);

    final draft = state.getDraftData();
    expect(draft['reservationModes'], ['stay', 'package']);
    expect(draft['reservationMode'], 'package');
    expect(draft['stayPricePerNight'], 210000);
    expect(draft['stayCheckInTime'], '15:00');
    expect(draft['stayCheckOutTime'], '12:00');
    expect(draft['stayMinNights'], 2);
    expect(draft['stayMaxNights'], 5);
    expect(parseReservationModes(draft), {
      ReservationMode.stay,
      ReservationMode.package,
    });
  });

  testWidgets('구 스키마(reservationMode: both) 룸은 시간제+패키지로 복원된다', (tester) async {
    final key = GlobalKey<RoomCardState>();
    final state = await _pump(
      tester,
      key,
      initialData: {
        'roomName': '파티룸 A',
        'reservationMode': 'both',
        'pricePerHour': 40000,
        'packages': [
          {'id': 'p1', 'name': '올나잇', 'startTime': '22:00', 'endTime': '08:00'},
        ],
      },
    );

    expect(find.text('시간당 가격 (원) *'), findsOneWidget);
    expect(find.text('패키지 관리 *'), findsOneWidget);
    expect(find.text('1박 요금 (원) *'), findsNothing);
    expect(state.getDraftData()['reservationModes'], ['hourly', 'package']);
  });
}

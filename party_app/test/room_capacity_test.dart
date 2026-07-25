import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/widgets/place_form/room_card.dart';

// 객실 유형: 기준인원 / 최대 수용 가능 인원 입력 UI·검증 확인.

Future<RoomCardState> _pump(WidgetTester tester, GlobalKey<RoomCardState> key) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: RoomCard(key: key, index: 0, onRemove: () {}),
      ),
    ),
  ));
  await tester.pump();
  return key.currentState!;
}

void main() {
  testWidgets('기준인원 / 최대 수용 가능 인원 라벨이 보인다', (tester) async {
    final key = GlobalKey<RoomCardState>();
    await _pump(tester, key);
    expect(find.text('기준인원 *'), findsOneWidget);
    expect(find.text('최대 수용 가능 인원 *'), findsOneWidget);
    expect(find.text('수용 인원 *'), findsNothing); // 기존 라벨 제거됨
  });

  testWidgets('최대 < 기준이면 검증 실패 + 안내 문구', (tester) async {
    final key = GlobalKey<RoomCardState>();
    final state = await _pump(tester, key);

    // 룸명(필수)과 기준 4 / 최대 2 입력 → 최대가 기준보다 작음.
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '테스트 룸'); // 룸명
    await tester.enterText(find.widgetWithText(TextField, '예: 2'), '4'); // 기준인원
    await tester.enterText(find.widgetWithText(TextField, '예: 4'), '2'); // 최대
    await tester.pump();

    expect(state.validate(), isFalse);
    await tester.pump();
    expect(find.textContaining('기준인원'), findsWidgets); // 오류 문구에 기준인원 언급
    expect(find.textContaining('작을 수 없어요'), findsOneWidget);
  });

  testWidgets('기준 2 / 최대 4는 통과(용량 항목 기준)', (tester) async {
    final key = GlobalKey<RoomCardState>();
    await _pump(tester, key);
    await tester.enterText(find.byType(TextField).at(0), '테스트 룸');
    await tester.enterText(find.widgetWithText(TextField, '예: 2'), '2');
    await tester.enterText(find.widgetWithText(TextField, '예: 4'), '4');
    await tester.pump();
    // 용량 오류 문구는 없어야 한다(예약방식 등 다른 필수는 별개).
    expect(find.textContaining('작을 수 없어요'), findsNothing);
    expect(find.text('최대 수용 가능 인원을 입력해주세요'), findsNothing);
  });

  testWidgets('숫자만 입력된다(문자 무시)', (tester) async {
    final key = GlobalKey<RoomCardState>();
    await _pump(tester, key);
    await tester.enterText(find.widgetWithText(TextField, '예: 4'), '4명abc');
    await tester.pump();
    final maxField = tester.widget<TextField>(find.widgetWithText(TextField, '예: 4'));
    expect(maxField.controller?.text, '4'); // digitsOnly로 숫자만 남음
  });
}

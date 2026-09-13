// 장소대여(룸) — 환불 정책 최소 1개를 **실제 저장 게이트**로 확인한다.
//
// 룸 카드는 장소 등록/수정([PlaceRegisterScreen])과 파티+숙박 콤보가 함께 쓰는
// 위젯이고, 두 화면 모두 저장 전에 `RoomCardState.validate()`를 부른다. 그래서
// 여기서 validate()를 직접 보면 두 화면의 저장 가능 여부를 그대로 보는 셈이다.
//
//  0개 → 저장 불가(+안내 문구) / 1개 → 가능 / 여러 개 → 가능
//  구간 없이 저장돼 있던 옛 룸 → 화면 진입은 되고, 저장에서만 막힌다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/utils/refund_policy.dart';
import 'package:party_app/widgets/place_form/room_card.dart';

void main() {
  /// 환불 규정을 뺀 나머지 필수값은 모두 채운 룸 문서 — 그래야 validate()의
  /// 결과가 오롯이 환불 규정 때문인지 알 수 있다.
  Map<String, dynamic> roomDoc({List<Map<String, dynamic>>? refundPolicy}) => {
    'roomName': '루프탑 A',
    'capacityMin': 1,
    'capacityMax': 10,
    'pricePerHour': 20000,
    'refundPolicy': ?refundPolicy,
  };

  List<Map<String, dynamic>> policy(int n) => [
    for (var i = 0; i < n; i++)
      {'daysBefore': 7 - i, 'refundPercent': 100 - i * 10},
  ];

  Future<GlobalKey<RoomCardState>> pumpRoom(
    WidgetTester tester,
    Map<String, dynamic> data,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final key = GlobalKey<RoomCardState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RoomCard(
              key: key,
              index: 0,
              onRemove: () {},
              roomId: 'room1',
              initialData: data,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return key;
  }

  testWidgets('0개 — 저장 불가, 안내 문구가 뜬다', (tester) async {
    final key = await pumpRoom(tester, roomDoc());

    // 저장 전에는 아무 오류도 떠 있지 않다.
    expect(find.text(RefundPolicyRule.requiredMessage), findsNothing);

    expect(key.currentState!.validate(), isFalse);
    await tester.pumpAndSettle();

    expect(find.text(RefundPolicyRule.requiredMessage), findsOneWidget);
    // 요약 행도 "선택"이 아니라 필수로 말한다.
    expect(find.text('환불 규정 설정 (필수)'), findsOneWidget);
  });

  testWidgets('1개 — 저장 가능', (tester) async {
    final key = await pumpRoom(tester, roomDoc(refundPolicy: policy(1)));

    expect(key.currentState!.validate(), isTrue);
    await tester.pumpAndSettle();

    expect(find.text(RefundPolicyRule.requiredMessage), findsNothing);
    expect(find.text('1단계 환불 규정 설정됨'), findsOneWidget);
  });

  testWidgets('여러 개 — 저장 가능', (tester) async {
    final key = await pumpRoom(tester, roomDoc(refundPolicy: policy(3)));

    expect(key.currentState!.validate(), isTrue);
    await tester.pumpAndSettle();

    expect(find.text('3단계 환불 규정 설정됨'), findsOneWidget);
  });

  testWidgets('구간 없이 저장돼 있던 옛 룸 — 열람은 되고 저장만 막힌다', (tester) async {
    // refundPolicy 키 자체가 없고, 옛 자유 입력만 남은 문서.
    final key = await pumpRoom(tester, {
      ...roomDoc(),
      'cancelPolicy': '이용 3일 전까지 전액 환불',
    });

    // 화면은 그대로 열린다 — 다른 내용을 고치러 온 호스트를 막지 않는다.
    expect(find.byType(RoomCard), findsOneWidget);
    expect(find.textContaining('이전 안내: 이용 3일 전까지 전액 환불'), findsOneWidget);
    expect(find.text(RefundPolicyRule.requiredMessage), findsNothing);

    // 다시 저장할 때부터 최소 1개를 요구한다.
    expect(key.currentState!.validate(), isFalse);
    await tester.pumpAndSettle();
    expect(find.text(RefundPolicyRule.requiredMessage), findsOneWidget);
  });

  testWidgets('구간을 채우면 곧바로 오류 표시가 풀리고 저장이 통과한다', (tester) async {
    final key = await pumpRoom(tester, roomDoc());

    expect(key.currentState!.validate(), isFalse);
    await tester.pumpAndSettle();
    expect(find.text(RefundPolicyRule.requiredMessage), findsOneWidget);

    // 요약 행 → 편집 시트 → '구간 추가'.
    await tester.tap(find.text('환불 규정 설정 (필수)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('구간 추가'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(RoomCard))).pop();
    await tester.pumpAndSettle();

    expect(find.text(RefundPolicyRule.requiredMessage), findsNothing);
    expect(find.text('1단계 환불 규정 설정됨'), findsOneWidget);
    expect(key.currentState!.validate(), isTrue);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/utils/refund_policy.dart';
import 'package:party_app/widgets/place_form/room_card.dart';
import 'package:party_app/widgets/refund_policy_editor.dart';

// 객실 환불규정: 파티와 동일한 구조(RefundTier)로 저장/표시되는지 확인.

void main() {
  testWidgets('RefundPolicyView는 subjectLabel로 맥락에 맞게 표시된다',
      (tester) async {
    final tiers = [
      RefundTier(daysBefore: 7, refundPercent: 90),
      RefundTier(daysBefore: 3, refundPercent: 100),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: RefundPolicyView(tiers: tiers, subjectLabel: '이용')),
    ));
    await tester.pump();
    // 큰 daysBefore부터 정렬 — '이용 7일 전부터: 90% 환불'
    expect(find.text('이용 7일 전부터: 90% 환불'), findsOneWidget);
    expect(find.text('이용 3일 전부터: 100% 환불'), findsOneWidget);
  });

  testWidgets('RefundPolicyView 기본 subjectLabel은 파티 그대로(회귀 방지)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RefundPolicyView(tiers: [RefundTier(daysBefore: 5, refundPercent: 50)]),
      ),
    ));
    await tester.pump();
    expect(find.text('파티 시작 5일 전부터: 50% 환불'), findsOneWidget);
  });

  testWidgets('RoomCard: refundPolicy 있는 룸은 "N단계 환불 규정 설정됨" 표시 + getDraftData 왕복',
      (tester) async {
    final key = GlobalKey<RoomCardState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: RoomCard(
            key: key,
            index: 0,
            onRemove: () {},
            initialData: const {
              'roomName': '오션뷰 4인실',
              'capacityMin': 2,
              'capacityMax': 4,
              'pricePerHour': 30000,
              'refundPolicy': [
                {'daysBefore': 7, 'refundPercent': 90},
                {'daysBefore': 3, 'refundPercent': 100},
              ],
            },
          ),
        ),
      ),
    ));
    await tester.pump();

    // 요약 문구
    expect(find.text('2단계 환불 규정 설정됨'), findsOneWidget);
    expect(find.text('환불/취소 규정'), findsNothing); // 기존 자유입력 라벨 제거됨

    // 저장(임시저장) 왕복 — refundPolicy(구조화)로 나가야 하고 cancelPolicy는 없어야 함
    final draft = key.currentState!.getDraftData();
    expect(draft.containsKey('cancelPolicy'), isFalse);
    final rp = draft['refundPolicy'] as List;
    expect(rp.length, 2);
    expect((rp.first as Map)['daysBefore'], anyOf(7, 3));
  });

  testWidgets('RoomCard: 구 스키마(cancelPolicy 문자열)만 있으면 안내로 보존',
      (tester) async {
    final key = GlobalKey<RoomCardState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: RoomCard(
            key: key,
            index: 0,
            onRemove: () {},
            initialData: const {
              'roomName': '레거시 룸',
              'capacityMax': 4,
              'cancelPolicy': '이용 24시간 전 100% 환불',
            },
          ),
        ),
      ),
    ));
    await tester.pump();
    // 옛 안내가 보이고, 저장 시엔 구조화된 refundPolicy(빈 목록)로 전환된다.
    expect(find.textContaining('이전 안내'), findsOneWidget);
    final draft = key.currentState!.getDraftData();
    expect(draft.containsKey('cancelPolicy'), isFalse);
    expect((draft['refundPolicy'] as List).isEmpty, isTrue);
  });
}

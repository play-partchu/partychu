// 플레이스·장소대여 상세의 '이곳에서 열리는 파티' 미니카드 —
// **모집상태 배지를 그리지 않는다.**
//
// 매일·상시 반복 파티는 지금 회차의 모집이 닫혀도 다음 회차가 계속 열리는데,
// 장소 상세에 '모집마감'이 붙으면 "이 파티는 이제 안 열린다"로 읽힌다.
// 판정 로직([PartyCard.effectiveStatus]/[PartyCard.statusChip])은 그대로 두고
// 이 카드에서만 렌더링을 뺐다 — 목록·검색 카드와 파티 상세는 예전 그대로다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/widgets/linked_party_card.dart';
import 'package:party_app/widgets/party_card_widget.dart';

void main() {
  const statusLabels = ['모집중', '모집마감', '신청가능', '오픈예정', '취소'];

  Future<void> pumpCard(WidgetTester tester, Map<String, dynamic> party) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LinkedPartyCard(partyId: 'p1', party: party),
          ),
        ),
      ),
    );
  }

  /// 매일 열리는 정기 파티 — 이번 회차 모집은 이미 닫혔다.
  Map<String, dynamic> dailyParty() => {
    'title': '매일 열리는 살사 나이트',
    'scheduleType': 'recurring',
    'recurringSchedule': PartyRecurringSchedule(
      startDate: DateTime(2020, 1, 1),
      endDate: DateTime(2020, 3, 1), // 운영 종료 → effectiveStatus '모집마감'
      weekly: {
        for (final k in kPartyWeekdayKeys)
          k: const PartyWeeklySlot(
            enabled: true,
            startTime: TimeOfDay(hour: 19, minute: 0),
            endTime: TimeOfDay(hour: 23, minute: 0),
          ),
      },
    ).toMap(),
    'pricingType': 'same',
    'price': 20000,
  };

  /// 단일 날짜 파티 — 모집마감 상태로 저장돼 있다.
  Map<String, dynamic> singleParty() => {
    'title': '단일 파티',
    'recruitStatus': '모집마감',
    'startDateTime': DateTime(2020, 5, 5, 19).toIso8601String(),
    'pricingType': 'same',
    'price': 30000,
  };

  group('연결 파티 미니카드에는 모집상태가 없다', () {
    testWidgets('매일/반복 파티 — 상태 배지가 보이지 않는다', (tester) async {
      final party = dailyParty();
      // 전제 확인: 이 문서는 원래 배지가 붙던 상태다(테스트가 헛돌지 않게).
      expect(PartyCard.effectiveStatus(party), '모집마감');

      await pumpCard(tester, party);

      for (final label in statusLabels) {
        expect(find.text(label), findsNothing, reason: '연결 카드에 "$label"이 그려졌다');
      }
      expect(find.text('매일 열리는 살사 나이트'), findsOneWidget);
      expect(find.text('자세히 보기'), findsOneWidget);
    });

    testWidgets('단일 파티 — 상태 배지가 보이지 않는다', (tester) async {
      final party = singleParty();
      expect(PartyCard.effectiveStatus(party), '모집마감');

      await pumpCard(tester, party);

      for (final label in statusLabels) {
        expect(find.text(label), findsNothing, reason: '연결 카드에 "$label"이 그려졌다');
      }
      expect(find.text('단일 파티'), findsOneWidget);
      expect(find.text('자세히 보기'), findsOneWidget);
    });

    testWidgets('파티명·일정·참가비·상세보기는 그대로 남는다', (tester) async {
      await pumpCard(tester, singleParty());
      expect(find.text('단일 파티'), findsOneWidget);
      expect(find.textContaining('일정 : '), findsOneWidget);
      expect(find.textContaining('참가비 : '), findsOneWidget);
      expect(find.text('자세히 보기'), findsOneWidget);
    });
  });

  group('상태 판정 로직 자체는 살아 있다', () {
    testWidgets('statusChip은 목록·검색 카드에서 여전히 배지를 그린다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: PartyCard.statusChip('모집마감'))),
        ),
      );
      expect(find.text('모집마감'), findsOneWidget);
    });
  });
}

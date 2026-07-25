import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:party_app/screens/party_market_register_screen.dart';
import 'package:party_app/screens/party_place_combo_register_screen.dart';
import 'package:party_app/screens/place_party_combo_register_screen.dart';
import 'package:party_app/utils/user_session.dart';

// 숙박+파티 / 플레이스+파티 / 파티샵 등록의 임시저장 라운드트립 검증.
// register_drafts_roundtrip_test.dart(이벤트·파티크루)와 동일한 방식 —
// 테스트 환경엔 Firebase가 없어 DraftService의 Firestore 접근은 조용히
// 실패하고 SharedPreferences 로컬 미러가 소스가 된다.

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UserSession.userId = 'test-user';
  });
  tearDown(() {
    UserSession.userId = '';
  });

  Future<Map<String, dynamic>> payloadOf(String prefsKey) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    expect(raw, isNotNull, reason: '$prefsKey 에 임시저장이 기록되지 않았습니다.');
    return (jsonDecode(raw!) as Map<String, dynamic>)['payload']
        as Map<String, dynamic>;
  }

  String seed(String typeKey, Map<String, dynamic> payload, String title) =>
      jsonEncode({
        'type': typeKey,
        'title': title,
        'payload': payload,
        'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
        'schemaVersion': 1,
      });

  // ── 파티샵 등록 ───────────────────────────────────────────────────────

  testWidgets('파티샵: 입력 → 임시저장 버튼 → draft_market 로컬 미러 기록',
      (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: PartyMarketRegisterScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '파티용품 대장간');
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '임시저장'));
    await tester.pumpAndSettle();

    final payload = await payloadOf('draft_market');
    expect(payload['name'], '파티용품 대장간');
  });

  testWidgets('파티샵: 임시저장 있으면 재진입 시 이어서 작성으로 복구', (tester) async {
    SharedPreferences.setMockInitialValues({
      'draft_market': seed('market', {
        'name': '복구된 샵',
        'description': '샵 설명',
        'deliveryOpts': ['pickup'],
        'hasCoupon': true,
        'couponDiscType': '금액 할인',
        'couponMin': '30000',
        'couponValue': '5000',
      }, '복구된 샵'),
    });
    await tester
        .pumpWidget(const MaterialApp(home: PartyMarketRegisterScreen()));
    await tester.pumpAndSettle();

    expect(find.text('작성 중인 내용이 있습니다'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, '이어서 작성'));
    await tester.pumpAndSettle();

    final name = tester.widget<TextField>(find.byType(TextField).first);
    expect(name.controller?.text, '복구된 샵');
    // 쿠폰은 스위치가 켜져야 입력란이 보이므로, 복구가 UI까지 반영됐는지 확인.
    expect(find.text('방문 할인쿠폰'), findsOneWidget);
    expect(find.text('금액 할인'), findsWidgets);
  });

  // ── 숙박+파티 등록 ────────────────────────────────────────────────────

  testWidgets('숙박+파티: 입력 → 임시저장 버튼 → draft_stay_party_combo 기록',
      (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: PartyPlaceComboRegisterScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '양평 감성 게스트하우스');
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '임시저장'));
    await tester.pumpAndSettle();

    final payload = await payloadOf('draft_stay_party_combo');
    expect(payload['name'], '양평 감성 게스트하우스');
    // 파티 파트 필드도 같은 payload에 함께 담긴다(파티 등록과 동일한 키).
    expect(payload.containsKey('dateSlots'), isTrue);
    expect(payload.containsKey('refundPolicy'), isTrue);
    expect(payload.containsKey('rooms'), isTrue);
  });

  testWidgets('숙박+파티: 객실·파티 필드까지 복구된다', (tester) async {
    SharedPreferences.setMockInitialValues({
      'draft_stay_party_combo': seed('stay_party_combo', {
        'name': '복구 게하',
        'contact': '010-0000-0000',
        'placeType': '게스트하우스',
        'checkInTime': {'h': 15, 'm': 0},
        'rooms': [
          {'name': '2인실', 'price': 50000},
          {'name': '4인실', 'price': 90000},
        ],
        'capacityText': '20',
        'maleFeeText': '20000',
        'partyTypes': ['클럽/디제이'],
      }, '복구 게하'),
    });
    await tester
        .pumpWidget(const MaterialApp(home: PartyPlaceComboRegisterScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, '이어서 작성'));
    await tester.pumpAndSettle();

    final name = tester.widget<TextField>(find.byType(TextField).first);
    expect(name.controller?.text, '복구 게하');

    // 복구 직후 다시 저장하면 객실 2개와 파티 입력이 그대로 남아 있어야 한다.
    await tester.tap(find.widgetWithText(TextButton, '임시저장'));
    await tester.pumpAndSettle();
    final payload = await payloadOf('draft_stay_party_combo');
    expect((payload['rooms'] as List).length, 2);
    expect(payload['capacityText'], '20');
    expect(payload['maleFeeText'], '20000');
    expect(payload['partyTypes'], ['클럽/디제이']);
    expect(payload['checkInTime'], {'h': 15, 'm': 0});
  });

  testWidgets('숙박+파티: 아코디언을 펼쳤다 접어도 객실이 임시저장에서 사라지지 않는다',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'draft_stay_party_combo': seed('stay_party_combo', {
        'name': '접힘 테스트 게하',
        'rooms': [
          {'roomName': '2인실', 'pricePerHour': 50000},
        ],
      }, '접힘 테스트 게하'),
    });
    // 긴 폼이라 기본 600dp 화면에서는 섹션 헤더가 화면 밖으로 밀려 탭이
    // 빗나간다 — 폼 전체가 들어가는 세로로 긴 화면으로 검사한다.
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester
        .pumpWidget(const MaterialApp(home: PartyPlaceComboRegisterScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, '이어서 작성'));
    await tester.pumpAndSettle();

    // "숙박 등록" 섹션을 펼쳐 객실을 고친 뒤 다시 접는다 — 접힌 뒤에 저장해도
    // 편집 내용이 남아 있어야 한다.
    Future<void> toggleStaySection() async {
      final header = find.text('숙박 등록');
      await tester.ensureVisible(header);
      await tester.pumpAndSettle();
      await tester.tap(header);
      await tester.pumpAndSettle();
    }

    await toggleStaySection();

    final roomName = find.widgetWithText(TextField, '2인실');
    expect(roomName, findsOneWidget, reason: '복원된 객실 카드가 보여야 합니다.');
    await tester.enterText(roomName, '2인실(수정)');
    await tester.pump();

    await toggleStaySection();

    await tester.tap(find.widgetWithText(TextButton, '임시저장'));
    await tester.pumpAndSettle();
    final payload = await payloadOf('draft_stay_party_combo');
    final rooms = payload['rooms'] as List;
    expect(rooms.length, 1, reason: '아코디언을 접었다고 객실이 사라지면 안 됩니다.');
    expect((rooms.first as Map)['roomName'], '2인실(수정)',
        reason: '펼친 상태에서 고친 객실 이름이 접은 뒤에도 유지돼야 합니다.');
  });

  // ── 플레이스+파티 등록 ────────────────────────────────────────────────

  testWidgets('플레이스+파티: 입력 → 임시저장 버튼 → draft_place_party_combo 기록',
      (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: PlacePartyComboRegisterScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '연남동 혼술바');
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '임시저장'));
    await tester.pumpAndSettle();

    final payload = await payloadOf('draft_place_party_combo');
    expect(payload['name'], '연남동 혼술바');
  });

  testWidgets('플레이스+파티: 파티 날짜·인원까지 복구된다', (tester) async {
    final partyDay = DateTime(2030, 5, 20);
    SharedPreferences.setMockInitialValues({
      'draft_place_party_combo': seed('place_party_combo', {
        'name': '복구 바',
        'partyCapacity': '15',
        'partyFee': '30000',
        'partyDateMs': partyDay.millisecondsSinceEpoch,
        'partyStartTime': {'h': 20, 'm': 30},
        'themeTags': ['혼술'],
      }, '복구 바'),
    });
    await tester
        .pumpWidget(const MaterialApp(home: PlacePartyComboRegisterScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, '이어서 작성'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, '임시저장'));
    await tester.pumpAndSettle();
    final payload = await payloadOf('draft_place_party_combo');
    expect(payload['name'], '복구 바');
    expect(payload['partyCapacity'], '15');
    expect(payload['partyFee'], '30000');
    expect(payload['partyDateMs'], partyDay.millisecondsSinceEpoch);
    expect(payload['partyStartTime'], {'h': 20, 'm': 30});
    expect(payload['themeTags'], ['혼술']);
  });
}

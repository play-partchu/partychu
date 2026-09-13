import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:party_app/screens/party_register_screen.dart';
import 'package:party_app/utils/user_session.dart';

import 'support/field_finders.dart';

// 파티 등록 임시저장 라운드트립 검증.
//
// 테스트 환경에는 Firebase 앱이 없어 DraftService의 Firestore 접근은 모두
// try/catch로 조용히 실패하고, SharedPreferences 로컬 미러가 소스가 된다
// (draft_service.dart의 오프라인 안전망 경로와 동일). 그래서 이 테스트는
// 실제 화면을 띄워 입력 → 임시저장 → 재진입 복구를 로컬 미러만으로도
// 검증할 수 있다.

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UserSession.userId = 'test-user';
  });

  tearDown(() {
    UserSession.userId = '';
  });

  /// 파티 등록 폼은 길다 — 기본 테스트 화면(800×600)에서는 파티명 칸이
  /// 화면 밖이라 **아예 만들어지지 않는다**(ListView는 보이는 만큼만 만든다).
  /// 폼 전체를 한 화면에 펼쳐 둔다(combo_draft_restore_test.dart와 같은 방식).
  void useTallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(420, 4800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('입력 → 임시저장 버튼 → 로컬 미러에 payload가 기록된다', (tester) async {
    useTallScreen(tester);
    await tester.pumpWidget(const MaterialApp(home: PartyRegisterScreen()));
    await tester.pumpAndSettle();

    // 파티명 입력 — 자리가 아니라 힌트로 찾는다(support/field_finders.dart).
    await tester.enterText(fieldWithHint(kPartyTitleHint), '테스트 번개 파티');
    await tester.pump();

    // AppBar의 '임시저장' 버튼 탭.
    await tester.tap(find.widgetWithText(TextButton, '임시저장'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('draft_party');
    expect(raw, isNotNull, reason: '임시저장 시 로컬 미러가 기록되어야 합니다.');

    final decoded = jsonDecode(raw!) as Map<String, dynamic>;
    expect(decoded['type'], 'party');
    expect(decoded['title'], '테스트 번개 파티');
    final payload = decoded['payload'] as Map<String, dynamic>;
    expect(payload['titleText'], '테스트 번개 파티');
  });

  testWidgets('임시저장이 있으면 재진입 시 "이어서 작성"으로 복구된다', (tester) async {
    // 로컬 미러에 파티 임시저장을 심어둔다(DraftService._encodeLocal 형태).
    final draft = jsonEncode({
      'type': 'party',
      'title': '복구된 파티',
      'coverImageUrl': null,
      'payload': {
        'titleText': '복구된 파티',
        'introText': '소개글 복구 확인',
        'partyTypes': ['음악'],
        'tags': ['한강', '드라이브'],
      },
      'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
      'schemaVersion': 1,
    });
    SharedPreferences.setMockInitialValues({'draft_party': draft});

    useTallScreen(tester);
    await tester.pumpWidget(const MaterialApp(home: PartyRegisterScreen()));
    await tester.pumpAndSettle();

    // 복구 다이얼로그가 뜨고, "이어서 작성"을 누른다.
    expect(find.text('작성 중인 내용이 있습니다'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, '이어서 작성'));
    await tester.pumpAndSettle();

    // 파티명 필드가 복구된 값으로 채워졌는지 확인.
    // 자리가 아니라 힌트로 찾는다(support/field_finders.dart).
    expect(textInField(tester, kPartyTitleHint), '복구된 파티');
  });
}

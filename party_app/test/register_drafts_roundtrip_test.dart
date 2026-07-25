import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:party_app/screens/event_register_screen.dart';
import 'package:party_app/screens/crew_register_screen.dart';
import 'package:party_app/utils/user_session.dart';

// 새 등록 화면(이벤트/파티크루)의 임시저장 라운드트립 검증. 파티 테스트와
// 동일하게, 테스트 환경엔 Firebase가 없어 DraftService의 Firestore 접근은
// 조용히 실패하고 SharedPreferences 로컬 미러가 소스가 된다.

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UserSession.userId = 'test-user';
  });
  tearDown(() {
    UserSession.userId = '';
  });

  testWidgets('이벤트: 입력 → 임시저장 버튼 → draft_event 로컬 미러 기록',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: EventRegisterScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '주말 플리마켓');
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '임시저장'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('draft_event');
    expect(raw, isNotNull);
    final payload =
        (jsonDecode(raw!) as Map<String, dynamic>)['payload'] as Map<String, dynamic>;
    expect(payload['name'], '주말 플리마켓');
  });

  testWidgets('이벤트: 임시저장 있으면 재진입 시 이어서 작성으로 복구',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'draft_event': jsonEncode({
        'type': 'event',
        'title': '복구 이벤트',
        'payload': {'name': '복구 이벤트', 'description': '설명'},
        'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
        'schemaVersion': 1,
      }),
    });
    await tester.pumpWidget(const MaterialApp(home: EventRegisterScreen()));
    await tester.pumpAndSettle();

    expect(find.text('작성 중인 내용이 있습니다'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, '이어서 작성'));
    await tester.pumpAndSettle();

    final title = tester.widget<TextField>(find.byType(TextField).first);
    expect(title.controller?.text, '복구 이벤트');
  });

  testWidgets('파티크루: 기본(구인) 입력 → draft_crew_recruit에 기록',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CrewRegisterScreen()));
    await tester.pumpAndSettle();

    // 첫 TextField는 제목(구인 기본).
    await tester.enterText(find.byType(TextField).first, '스탭 급구');
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '임시저장'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    // 구인이므로 crew_recruit 키에 저장되고, crew_seek에는 없어야 한다.
    expect(prefs.getString('draft_crew_recruit'), isNotNull);
    expect(prefs.getString('draft_crew_seek'), isNull);
    final payload = (jsonDecode(prefs.getString('draft_crew_recruit')!)
        as Map<String, dynamic>)['payload'] as Map<String, dynamic>;
    expect(payload['crewType'], '구인');
    expect(payload['title'], '스탭 급구');
  });

  testWidgets('파티크루: 구직 임시저장을 initialCrewType으로 복구',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'draft_crew_seek': jsonEncode({
        'type': 'crew_seek',
        'title': '구직합니다',
        'payload': {'crewType': '구직', 'title': '구직합니다', 'content': '경력 3년'},
        'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
        'schemaVersion': 1,
      }),
    });
    await tester.pumpWidget(const MaterialApp(
      home: CrewRegisterScreen(autoRestoreDraft: true, initialCrewType: '구직'),
    ));
    await tester.pumpAndSettle();

    // autoRestore라 다이얼로그 없이 바로 복구 — 제목 필드가 채워진다.
    final title = tester.widget<TextField>(find.byType(TextField).first);
    expect(title.controller?.text, '구직합니다');
  });
}

// 기타 편의 서비스가 **등록 화면을 통해** 저장되고 되살아나는지.
//
// 모델(custom_amenity_test)과 위젯(custom_amenity_ui_test)이 각자 규칙을
// 확인하지만, 그 둘이 실제 등록 화면에서 이어져 있는지는 별개다 — 화면이
// payload에 담지 않거나 복원에서 빠뜨리면 두 검사 모두 통과하면서 기능은
// 동작하지 않는다.
//
// 테스트 환경엔 Firebase가 없어 DraftService의 Firestore 접근은 조용히 실패하고
// SharedPreferences 로컬 미러가 소스가 된다(register_drafts_roundtrip_test와
// 같은 구조). 그래서 화면 → payload → 화면의 왕복을 그대로 볼 수 있다.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:party_app/models/custom_amenity.dart';
import 'package:party_app/screens/event_register_screen.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/place_form/custom_amenity_section.dart';

import 'support/field_finders.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UserSession.userId = 'test-user';
  });
  tearDown(() => UserSession.userId = '');

  /// 등록 화면은 길다 — 기본 800×600에서는 아래쪽 섹션이 아예 만들어지지 않는다.
  void useTallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(420, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<Map<String, dynamic>> saveDraft(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, '임시저장'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('draft_event');
    expect(raw, isNotNull, reason: '임시저장 로컬 미러가 기록되어야 합니다.');
    return (jsonDecode(raw!) as Map<String, dynamic>)['payload']
        as Map<String, dynamic>;
  }

  /// 기타 입력칸을 열고 [name]을 추가한다.
  Future<void> addAmenity(WidgetTester tester, String name) async {
    await tester.ensureVisible(find.byType(CustomAmenitySection));
    await tester.pumpAndSettle();
    // 이미 열려 있으면 버튼이 없다.
    final addButton = find.text('＋ 기타 편의 서비스 추가');
    if (addButton.evaluate().isNotEmpty) {
      await tester.tap(addButton);
      await tester.pumpAndSettle();
    }
    final field = find.descendant(
      of: find.byType(CustomAmenitySection),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, name);
    await tester.tap(
      find.descendant(
        of: find.byType(CustomAmenitySection),
        matching: find.widgetWithText(TextButton, '추가'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('여러 개를 입력하면 항목 배열로 저장된다', (tester) async {
    useTallScreen(tester);
    await tester.pumpWidget(const MaterialApp(home: EventRegisterScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(fieldWithHint(kEventNameHint), '루프탑 보드게임 바');
    await addAmenity(tester, '루프탑');
    await addAmenity(tester, '보드게임 대여');

    final payload = await saveDraft(tester);
    expect(payload[CustomAmenities.field], ['루프탑', '보드게임 대여']);
    expect(
      payload[CustomAmenities.field],
      isA<List<dynamic>>(),
      reason: '하나의 긴 문자열로 합치면 안 됩니다.',
    );
  });

  testWidgets('저장한 항목이 재진입에서 그대로 복원된다', (tester) async {
    SharedPreferences.setMockInitialValues({
      'draft_event': jsonEncode({
        'type': 'event',
        'title': '복구 플레이스',
        'payload': {
          'name': '복구 플레이스',
          CustomAmenities.field: ['루프탑', '반려동물 물그릇'],
        },
        'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
      }),
    });
    useTallScreen(tester);
    await tester.pumpWidget(const MaterialApp(home: EventRegisterScreen()));
    await tester.pumpAndSettle();

    // 복구 여부를 묻는다 — '이어서 작성'을 고른다.
    final resume = find.text('이어서 작성');
    if (resume.evaluate().isNotEmpty) {
      await tester.tap(resume);
      await tester.pumpAndSettle();
    }

    await tester.ensureVisible(find.byType(CustomAmenitySection));
    await tester.pumpAndSettle();
    expect(find.text('루프탑'), findsWidgets);
    expect(find.text('반려동물 물그릇'), findsWidgets);
  });

  testWidgets('수정 — 추가하면 늘고 삭제하면 그 항목만 빠진다', (tester) async {
    useTallScreen(tester);
    await tester.pumpWidget(const MaterialApp(home: EventRegisterScreen()));
    await tester.pumpAndSettle();
    await tester.enterText(fieldWithHint(kEventNameHint), '수정 검사');

    await addAmenity(tester, '루프탑');
    await addAmenity(tester, '보드게임 대여');
    expect((await saveDraft(tester))[CustomAmenities.field], [
      '루프탑',
      '보드게임 대여',
    ]);

    // 첫 항목의 X — 칩은 항목 순서대로 그려진다.
    await tester.ensureVisible(find.byType(CustomAmenitySection));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byType(CustomAmenitySection),
            matching: find.byIcon(Icons.close),
          )
          .first,
    );
    await tester.pumpAndSettle();

    expect((await saveDraft(tester))[CustomAmenities.field], ['보드게임 대여']);
  });

  testWidgets('기타를 하나도 안 넣으면 기존 등록과 똑같다 — 빈 배열', (tester) async {
    useTallScreen(tester);
    await tester.pumpWidget(const MaterialApp(home: EventRegisterScreen()));
    await tester.pumpAndSettle();
    await tester.enterText(fieldWithHint(kEventNameHint), '기타 없는 가게');

    final payload = await saveDraft(tester);
    expect(payload[CustomAmenities.field], isEmpty);
    expect(CustomAmenities.of(payload), isEmpty);
  });
}

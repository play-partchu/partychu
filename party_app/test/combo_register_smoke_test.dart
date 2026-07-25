import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:party_app/screens/register_type_screen.dart';
import 'package:party_app/screens/party_place_combo_register_screen.dart';
import 'package:party_app/utils/user_session.dart';

// 숙박+파티 등록: (1) 등록 유형 카드 → 콤보 화면 이동, (2) 최종 등록 버튼이
// 빈 입력일 때 조용히 끝내지 않고 안내를 띄우는지 검증.

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UserSession.userId = 'test-user';
  });
  tearDown(() => UserSession.userId = '');

  testWidgets('"숙박+파티 등록" 카드를 누르면 콤보 등록 화면으로 이동한다',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: RegisterTypeScreen()));
    await tester.pump(const Duration(milliseconds: 300));

    final card = find.text('숙박+파티 등록');
    await tester.ensureVisible(card);
    await tester.pump();
    await tester.tap(card);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(PartyPlaceComboRegisterScreen), findsOneWidget);
  });

  testWidgets('빈 입력으로 "숙박+파티 등록하기"를 누르면 안내가 뜬다(먹통 아님)',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PartyPlaceComboRegisterScreen()),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final submit = find.text('숙박+파티 등록하기');
    await tester.scrollUntilVisible(submit, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pump();
    await tester.tap(submit);
    await tester.pump(); // _submit 실행 → setState
    await tester.pump(const Duration(milliseconds: 300));

    // 조용히 끝내지 않고 필수 항목 안내 스낵바가 떠야 한다.
    expect(find.textContaining('필수 항목'), findsOneWidget);
    // 화면은 그대로 유지(등록으로 넘어가지 않음).
    expect(find.byType(PartyPlaceComboRegisterScreen), findsOneWidget);
  });
}

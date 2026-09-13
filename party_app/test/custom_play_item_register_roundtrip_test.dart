// 🎲 기타 놀거리가 **등록 화면을 통해** 입력되고 담기고 되살아나는지.
//
// 모델(custom_play_item_test)이 규칙을 못 박지만, 그 규칙이 실제 화면에
// 이어져 있는지는 별개다 — 화면이 payload에 담지 않거나 복원에서 빠뜨리면
// 모델 검사는 통과하면서 기능은 동작하지 않는다.
//
// 테스트 환경엔 Firebase가 없어 DraftService의 Firestore 접근은 조용히 실패하고
// SharedPreferences 로컬 미러가 소스가 된다(custom_amenity_register_roundtrip_
// test와 같은 구조).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:party_app/models/custom_play_item.dart';
import 'package:party_app/models/place_attributes.dart';
import 'package:party_app/screens/event_register_screen.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/place_form/custom_play_item_section.dart';
import 'package:party_app/widgets/place_form/place_attributes_section.dart';

import 'support/field_finders.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UserSession.userId = 'test-user';
  });
  tearDown(() => UserSession.userId = '');

  void useTallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(420, 9000);
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

  /// 세부 정보 아코디언을 펼친다.
  Future<void> expandAttributes(WidgetTester tester) async {
    await tester.ensureVisible(find.byType(PlaceAttributesSection));
    await tester.pumpAndSettle();
    final open = find.descendant(
      of: find.byType(PlaceAttributesSection),
      matching: find.text('자세히 설정'),
    );
    if (open.evaluate().isNotEmpty) {
      await tester.tap(open);
      await tester.pumpAndSettle();
    }
  }

  /// 놀거리 그룹 안의 칩만 찾는다 — '기타'는 ♾ 무제한 그룹에도 있다.
  Finder playItemsChip(String label) => find.descendant(
    of: find
        .ancestor(
          of: find.text(PlaceAttributeCatalog.playItems.display),
          matching: find.byType(Column),
        )
        .first,
    matching: find.text(label),
  );

  Future<void> toggleEtc(WidgetTester tester) async {
    await expandAttributes(tester);
    final etc = playItemsChip(CustomPlayItems.etcOption);
    await tester.ensureVisible(etc);
    await tester.pumpAndSettle();
    await tester.tap(etc);
    await tester.pumpAndSettle();
  }

  Future<void> addPlayItem(WidgetTester tester, String name) async {
    await tester.ensureVisible(find.byType(CustomPlayItemSection));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(CustomPlayItemSection),
        matching: find.byType(TextField),
      ),
      name,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(CustomPlayItemSection),
        matching: find.widgetWithText(TextButton, '추가'),
      ),
    );
    await tester.pumpAndSettle();
  }

  String? errorTextOf(WidgetTester tester) => tester
      .widget<TextField>(
        find.descendant(
          of: find.byType(CustomPlayItemSection),
          matching: find.byType(TextField),
        ),
      )
      .decoration
      ?.errorText;

  testWidgets("'기타'를 골라야 입력칸이 나온다", (tester) async {
    useTallScreen(tester);
    await tester.pumpWidget(const MaterialApp(home: EventRegisterScreen()));
    await tester.pumpAndSettle();

    await expandAttributes(tester);
    expect(find.byType(CustomPlayItemSection), findsNothing);

    await toggleEtc(tester);
    expect(find.byType(CustomPlayItemSection), findsOneWidget);
    expect(find.text(CustomPlayItems.sectionTitle), findsOneWidget);
    expect(find.text(CustomPlayItems.inputGuide), findsOneWidget);
  });

  testWidgets('추가한 항목이 칩으로 쌓이고 ×로 하나씩 빠진다', (tester) async {
    useTallScreen(tester);
    await tester.pumpWidget(const MaterialApp(home: EventRegisterScreen()));
    await tester.pumpAndSettle();
    await tester.enterText(fieldWithHint(kEventNameHint), '놀거리 매장');

    await toggleEtc(tester);
    await addPlayItem(tester, '포켓볼');
    await addPlayItem(tester, '테이블축구');
    await addPlayItem(tester, '마작');
    expect((await saveDraft(tester))[CustomPlayItems.field], [
      '포켓볼',
      '테이블축구',
      '마작',
    ]);

    await tester.ensureVisible(find.byType(CustomPlayItemSection));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byType(CustomPlayItemSection),
            matching: find.byIcon(Icons.close),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect((await saveDraft(tester))[CustomPlayItems.field], ['테이블축구', '마작']);
  });

  testWidgets('빈 값·중복·긴 문장은 안내와 함께 막힌다', (tester) async {
    useTallScreen(tester);
    await tester.pumpWidget(const MaterialApp(home: EventRegisterScreen()));
    await tester.pumpAndSettle();
    await toggleEtc(tester);

    await addPlayItem(tester, '   ');
    expect(errorTextOf(tester), CustomPlayItems.shortNameMessage);

    await addPlayItem(tester, '테이블축구');
    // 띄어쓰기만 다른 값 — 같은 항목으로 막힌다.
    await addPlayItem(tester, '테이블 축구');
    expect(errorTextOf(tester), CustomPlayItems.duplicateMessage);

    await tester.ensureVisible(find.byType(CustomPlayItemSection));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(CustomPlayItemSection),
        matching: find.byIcon(Icons.close),
      ),
      findsOneWidget,
      reason: '막힌 입력은 칩으로 쌓이지 않는다.',
    );
  });

  testWidgets('최대 10개 — 11번째는 칸 자체가 막힌다', (tester) async {
    useTallScreen(tester);
    await tester.pumpWidget(const MaterialApp(home: EventRegisterScreen()));
    await tester.pumpAndSettle();
    await tester.enterText(fieldWithHint(kEventNameHint), '열 개 매장');
    await toggleEtc(tester);

    for (var i = 1; i <= CustomPlayItems.maxCount; i++) {
      await addPlayItem(tester, '놀거리$i');
    }
    final payload = await saveDraft(tester);
    expect(payload[CustomPlayItems.field], hasLength(CustomPlayItems.maxCount));

    await tester.ensureVisible(find.byType(CustomPlayItemSection));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byType(CustomPlayItemSection),
        matching: find.byType(TextField),
      ),
    );
    expect(field.enabled, isFalse, reason: '가득 차면 더 칠 수 없다.');
    expect(find.text(CustomPlayItems.fullMessage), findsOneWidget);

    await addPlayItem(tester, '놀거리11');
    expect(
      (await saveDraft(tester))[CustomPlayItems.field],
      hasLength(CustomPlayItems.maxCount),
    );
  });

  testWidgets("'기타'를 끄면 칸만 접히고 값은 살아 있다 — 임시저장에도 담긴다", (tester) async {
    useTallScreen(tester);
    await tester.pumpWidget(const MaterialApp(home: EventRegisterScreen()));
    await tester.pumpAndSettle();
    await tester.enterText(fieldWithHint(kEventNameHint), '실수로 끈 매장');

    await toggleEtc(tester);
    await addPlayItem(tester, '포켓볼');
    await addPlayItem(tester, '마작');

    // 다시 눌러 '기타'를 끈다.
    await toggleEtc(tester);
    expect(find.byType(CustomPlayItemSection), findsNothing);

    // 열 개를 날리지 않는다 — 임시저장에는 그대로 담긴다.
    expect((await saveDraft(tester))[CustomPlayItems.field], ['포켓볼', '마작']);

    // 다시 켜면 칩이 그대로 돌아온다.
    await toggleEtc(tester);
    await tester.ensureVisible(find.byType(CustomPlayItemSection));
    await tester.pumpAndSettle();
    expect(find.text('포켓볼'), findsWidgets);
    expect(find.text('마작'), findsWidgets);
  });

  testWidgets('임시저장 왕복 — 저장한 값이 재진입에서 그대로 복원된다', (tester) async {
    SharedPreferences.setMockInitialValues({
      'draft_event': jsonEncode({
        'type': 'event',
        'title': '복구 매장',
        'payload': {
          'name': '복구 매장',
          'placeAttributes': {
            'selections': {
              PlaceAttributeCatalog.playItemsKey: ['보드게임', '기타'],
            },
            'details': <String, dynamic>{},
          },
          CustomPlayItems.field: ['포켓볼', '테이블축구'],
        },
        'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
      }),
    });
    useTallScreen(tester);
    await tester.pumpWidget(const MaterialApp(home: EventRegisterScreen()));
    await tester.pumpAndSettle();

    final resume = find.text('이어서 작성');
    if (resume.evaluate().isNotEmpty) {
      await tester.tap(resume);
      await tester.pumpAndSettle();
    }

    await expandAttributes(tester);
    await tester.ensureVisible(find.byType(CustomPlayItemSection));
    await tester.pumpAndSettle();
    expect(find.text('포켓볼'), findsWidgets);
    expect(find.text('테이블축구'), findsWidgets);

    // 다시 저장해도 그대로 나간다(재저장 왕복).
    expect((await saveDraft(tester))[CustomPlayItems.field], ['포켓볼', '테이블축구']);
  });

  testWidgets('아무것도 안 적으면 예전 등록과 똑같다 — 빈 배열', (tester) async {
    useTallScreen(tester);
    await tester.pumpWidget(const MaterialApp(home: EventRegisterScreen()));
    await tester.pumpAndSettle();
    await tester.enterText(fieldWithHint(kEventNameHint), '놀거리 없는 매장');

    final payload = await saveDraft(tester);
    expect(payload[CustomPlayItems.field], isEmpty);
    expect(CustomPlayItems.of(payload), isEmpty);
  });
}

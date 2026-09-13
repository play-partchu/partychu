// 프로필 사진 요청 — **호스트 설정 화면과 신청자 제출 화면**을 직접 띄워 본다.
//
//  호스트 쪽: 승인제일 때만 토글이 보이고, 기본은 꺼짐이며, 즉시확정으로
//            되돌리면 값이 함께 꺼진 채로 돌아온다.
//  신청자 쪽: OFF면 사진 칸이 아예 없고 0장으로 제출이 되며,
//            ON이면 칸이 뜨고 0장에서는 제출 버튼이 잠긴다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/party_application_form.dart';
import 'package:party_app/screens/party_application_answer_screen.dart';
import 'package:party_app/widgets/party_form/application_form_section.dart';

void main() {
  const photoTitle = '📷 프로필 사진 등록 요청';
  const photoDesc = '승인 심사를 위해 신청자에게 프로필 사진 제출을 요청합니다.';

  PartyApplicationQuestion question() => const PartyApplicationQuestion(
    id: 'q1',
    text: '참여 이유가 무엇인가요?',
    required: true,
  );

  group('호스트 설정', () {
    /// 설정 시트를 열고, '확인'을 눌렀을 때의 결과를 담는 상자를 돌려준다.
    Future<List<ApplicationFormResult?>> openSheet(
      WidgetTester tester, {
      required PartyApprovalMode mode,
      List<PartyApplicationQuestion> questions = const [],
      bool requirePhotos = false,
    }) async {
      tester.view.physicalSize = const Size(500, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final results = <ApplicationFormResult?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async => results.add(
                  await showApplicationFormSheet(
                    context,
                    mode: mode,
                    questions: questions,
                    requirePhotos: requirePhotos,
                  ),
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      return results;
    }

    testWidgets('즉시확정이면 옵션 자체가 보이지 않는다', (tester) async {
      await openSheet(tester, mode: PartyApprovalMode.auto);
      expect(find.text(photoTitle), findsNothing);
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('승인제면 옵션이 보이고 기본값은 꺼짐이다', (tester) async {
      await openSheet(tester, mode: PartyApprovalMode.manual);

      expect(find.text(photoTitle), findsOneWidget);
      expect(find.text(photoDesc), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    });

    testWidgets('켜고 확인하면 ON으로 돌아온다', (tester) async {
      final results = await openSheet(tester, mode: PartyApprovalMode.manual);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();

      final r = results.single!;
      expect(r.requirePhotos, isTrue);
      expect(r.mode, PartyApprovalMode.manual);
    });

    testWidgets('저장된 ON 상태가 그대로 켜진 채로 열린다 — 수정 화면', (tester) async {
      await openSheet(
        tester,
        mode: PartyApprovalMode.manual,
        questions: [question()],
        requirePhotos: true,
      );
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    });

    testWidgets('사전질문과 독립이다 — 질문 없이도 켤 수 있다', (tester) async {
      final results = await openSheet(tester, mode: PartyApprovalMode.manual);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();

      final r = results.single!;
      expect(r.questions, isEmpty);
      expect(r.requirePhotos, isTrue);
    });

    testWidgets('즉시확정으로 되돌리면 사진 요청도 함께 꺼져서 나온다', (tester) async {
      final results = await openSheet(
        tester,
        mode: PartyApprovalMode.manual,
        requirePhotos: true,
      );

      await tester.tap(find.text(PartyApprovalMode.auto.label));
      await tester.pumpAndSettle();
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();

      final r = results.single!;
      expect(r.mode, PartyApprovalMode.auto);
      expect(r.requirePhotos, isFalse);
    });
  });

  group('신청자 제출 화면', () {
    Future<void> pumpAnswer(
      WidgetTester tester,
      PartyApplicationForm form,
    ) async {
      tester.view.physicalSize = const Size(500, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: PartyApplicationAnswerScreen(
            partyId: 'party1',
            hostId: 'host1',
            applicationId: 'app1',
            form: form,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    bool submitEnabled(WidgetTester tester) =>
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed !=
        null;

    testWidgets('사진 OFF — 칸이 아예 없고 0장으로도 제출할 수 있다', (tester) async {
      await pumpAnswer(
        tester,
        PartyApplicationForm(
          mode: PartyApprovalMode.manual,
          questions: [question()],
        ),
      );

      expect(find.text('프로필 사진 제출'), findsNothing);
      expect(find.text('사진 추가'), findsNothing);

      // 필수 질문만 채우면 곧바로 제출할 수 있다.
      expect(submitEnabled(tester), isFalse, reason: '필수 질문이 아직 비었다');
      await tester.enterText(find.byType(TextField).first, '분위기가 좋아 보여서요');
      await tester.pumpAndSettle();
      expect(submitEnabled(tester), isTrue, reason: '사진 0장이어도 통과해야 한다');
    });

    testWidgets('사진 ON — 칸이 뜨고 0장이면 제출이 잠긴다', (tester) async {
      await pumpAnswer(
        tester,
        const PartyApplicationForm(
          mode: PartyApprovalMode.manual,
          requirePhotos: true,
        ),
      );

      expect(find.text('프로필 사진 제출'), findsOneWidget);
      expect(find.text('사진 추가'), findsOneWidget);
      expect(find.text('필수'), findsOneWidget, reason: '필수 배지가 붙는다');
      expect(
        find.text('0/${PartyApplicationLimits.maxPhotos}'),
        findsOneWidget,
      );

      // 물어볼 질문이 없는데도 사진 때문에 잠겨 있어야 한다.
      expect(submitEnabled(tester), isFalse);
    });

    testWidgets('질문 없음 + 사진 ON — 질문 칸 없이 사진만 묻는다', (tester) async {
      await pumpAnswer(
        tester,
        const PartyApplicationForm(
          mode: PartyApprovalMode.manual,
          requirePhotos: true,
        ),
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.text('프로필 사진 제출'), findsOneWidget);
    });

    testWidgets('질문 있음 + 사진 ON — 둘 다 뜬다', (tester) async {
      await pumpAnswer(
        tester,
        PartyApplicationForm(
          mode: PartyApprovalMode.manual,
          questions: [question()],
          requirePhotos: true,
        ),
      );
      expect(find.text(question().text), findsOneWidget);
      expect(find.text('프로필 사진 제출'), findsOneWidget);

      // 질문을 채워도 사진이 0장이면 잠긴 그대로다.
      await tester.enterText(find.byType(TextField).first, '분위기가 좋아 보여서요');
      await tester.pumpAndSettle();
      expect(submitEnabled(tester), isFalse);
    });
  });
}

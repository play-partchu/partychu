import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/utils/register_validation.dart';

/// 등록 화면 4곳이 공유하는 검증/자동 이동 로직 검증.
void main() {
  group('안내 문구', () {
    test('1개 누락', () {
      expect(
        RegisterValidation.summaryMessage(1),
        '입력하지 않은 필수 항목이 있어요. 표시된 항목을 확인해주세요.',
      );
    });

    test('여러 개 누락이면 개수를 알려준다', () {
      expect(RegisterValidation.summaryMessage(3), '필수 항목 3개를 확인해주세요.');
    });

    test('서버 오류 문구에는 기술적인 내용이 없다', () {
      const msg = RegisterValidation.submitFailedMessage;
      expect(msg, '등록 중 문제가 발생했습니다. 잠시 후 다시 시도해주세요.');
      for (final banned in ['Exception', 'Firebase', 'Error', 'null']) {
        expect(msg.contains(banned), isFalse);
      }
    });
  });

  group('check()', () {
    /// 세로로 긴 폼 — 아래쪽 항목은 스크롤해야 보인다.
    Future<
      ({
        GlobalKey top,
        GlobalKey middle,
        GlobalKey bottom,
        FocusNode focus,
        BuildContext context,
      })
    >
    pumpForm(WidgetTester tester) async {
      final top = GlobalKey();
      final middle = GlobalKey();
      final bottom = GlobalKey();
      final focus = FocusNode();
      late BuildContext ctx;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) {
                ctx = c;
                return ListView(
                  children: [
                    SizedBox(key: top, height: 400, child: const Text('상단')),
                    SizedBox(key: middle, height: 400, child: const Text('중간')),
                    SizedBox(
                      key: bottom,
                      height: 400,
                      child: TextField(focusNode: focus),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      return (
        top: top,
        middle: middle,
        bottom: bottom,
        focus: focus,
        context: ctx,
      );
    }

    testWidgets('누락이 없으면 true — 스낵바를 띄우지 않는다', (tester) async {
      final f = await pumpForm(tester);

      final passed = RegisterValidation.check(f.context, [
        const RegisterFieldCheck(missing: false, message: 'a'),
        const RegisterFieldCheck(missing: false, message: 'b'),
      ]);
      await tester.pumpAndSettle();

      expect(passed, isTrue);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('누락이 있으면 false + 안내 스낵바', (tester) async {
      final f = await pumpForm(tester);

      final passed = RegisterValidation.check(f.context, [
        RegisterFieldCheck(
          missing: true,
          message: '파티 날짜를 선택해주세요.',
          anchorKey: f.middle,
        ),
      ]);
      await tester.pumpAndSettle();

      expect(passed, isFalse);
      // 스낵바는 요약이 아니라 **그 항목의 구체적인 문구**를 그대로 띄운다 —
      // "필수 항목이 있어요"만 보면 어디가 문제인지 알 수 없기 때문이다
      // ([RegisterValidation.check] 주석 참고). 하나뿐일 때는 개수도 붙지 않는다.
      expect(find.text('파티 날짜를 선택해주세요.'), findsOneWidget);
    });

    testWidgets('여러 개 누락이면 개수를 안내한다', (tester) async {
      final f = await pumpForm(tester);

      RegisterValidation.check(f.context, [
        RegisterFieldCheck(missing: true, message: 'a', anchorKey: f.top),
        RegisterFieldCheck(missing: true, message: 'b', anchorKey: f.middle),
        RegisterFieldCheck(missing: true, message: 'c', anchorKey: f.bottom),
      ]);
      await tester.pumpAndSettle();

      // 첫 누락 항목의 문구 + 남은 개수. 나머지는 상단 배너 목록에 남는다.
      expect(find.text('a (확인할 항목 3개)'), findsOneWidget);
    });

    testWidgets('화면 위에서 가장 먼저 나오는 누락 항목으로 스크롤한다', (tester) async {
      final f = await pumpForm(tester);
      // 처음에는 중간 항목이 화면 아래쪽(첫 화면 밖)에 있다.
      expect(tester.getTopLeft(find.byKey(f.middle)).dy, greaterThan(300));

      // 목록 순서상 middle이 bottom보다 앞 → middle이 이동 대상.
      RegisterValidation.check(f.context, [
        const RegisterFieldCheck(missing: false, message: '채워짐'),
        RegisterFieldCheck(missing: true, message: 'b', anchorKey: f.middle),
        RegisterFieldCheck(missing: true, message: 'c', anchorKey: f.bottom),
      ]);
      await tester.pumpAndSettle();

      final middleTop = tester.getTopLeft(find.byKey(f.middle)).dy;
      expect(middleTop, lessThan(100));
    });

    testWidgets('접힌 섹션은 reveal로 먼저 펼친 뒤 이동한다', (tester) async {
      final f = await pumpForm(tester);
      var revealed = false;

      RegisterValidation.check(f.context, [
        RegisterFieldCheck(
          missing: true,
          message: '객실을 추가해주세요.',
          anchorKey: f.bottom,
          reveal: () => revealed = true,
        ),
      ]);
      await tester.pumpAndSettle();

      expect(revealed, isTrue);
    });

    testWidgets('첫 누락 항목의 reveal만 호출된다', (tester) async {
      final f = await pumpForm(tester);
      var firstRevealed = false;
      var secondRevealed = false;

      RegisterValidation.check(f.context, [
        RegisterFieldCheck(
          missing: true,
          message: 'a',
          anchorKey: f.top,
          reveal: () => firstRevealed = true,
        ),
        RegisterFieldCheck(
          missing: true,
          message: 'b',
          anchorKey: f.bottom,
          reveal: () => secondRevealed = true,
        ),
      ]);
      await tester.pumpAndSettle();

      expect(firstRevealed, isTrue);
      expect(secondRevealed, isFalse);
    });

    testWidgets('입력칸에 커서를 놓는다', (tester) async {
      final f = await pumpForm(tester);
      expect(f.focus.hasFocus, isFalse);

      RegisterValidation.check(f.context, [
        RegisterFieldCheck(
          missing: true,
          message: '모집 인원을 입력해주세요.',
          anchorKey: f.bottom,
          focusNode: f.focus,
        ),
      ]);
      await tester.pumpAndSettle();

      expect(f.focus.hasFocus, isTrue);
    });

    testWidgets('anchorKey가 없어도 죽지 않는다', (tester) async {
      final f = await pumpForm(tester);

      final passed = RegisterValidation.check(f.context, [
        const RegisterFieldCheck(missing: true, message: '어딘가 비었어요.'),
      ]);
      await tester.pumpAndSettle();

      expect(passed, isFalse);
    });
  });
}

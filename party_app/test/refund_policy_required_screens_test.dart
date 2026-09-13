// 환불 정책 최소 1개 — **각 등록 화면의 실제 저장 게이트**에서 확인한다.
//
// 공용 규칙 자체는 refund_policy_required_test.dart가 본다. 여기서는 그 규칙이
// 화면마다 실제로 저장을 막는지를, 등록 버튼을 눌러 나오는 안내로 확인한다.
//
//  0개  → 등록 버튼을 눌러도 넘어가지 않고 '환불 정책을 1개 이상 선택해주세요.'
//  1개  → 그 안내가 사라진다(다른 필수값이 남아 있어도 환불 규정은 통과)
//  여러 개 → 마찬가지로 통과
//
// 장소대여(룸)는 room_card_refund_policy_test.dart가, 구간 없이 저장된 옛 문서의
// "열람은 되고 저장만 막힌다"도 거기서 본다.

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:party_app/screens/party_register_screen.dart';
import 'package:party_app/utils/refund_policy.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/party_form/section_summary_row.dart';

void main() {
  setUp(() {
    dotenv.testLoad(fileInput: '');
    SharedPreferences.setMockInitialValues({});
    UserSession.userId = 'test-user';
  });
  tearDown(() => UserSession.userId = '');

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// 화면을 아래로 훑어 [finder]를 찾아 누른다 — 등록 버튼도 요약 행도
  /// 스크롤 안에 있어서 그냥 tap하면 빗나간다.
  Future<void> scrollAndTap(WidgetTester tester, Finder finder) async {
    // 직전 안내 스낵바가 화면 아래를 덮고 있으면 등록 버튼 탭이 빗나간다.
    ScaffoldMessenger.of(
      tester.element(find.byType(Scaffold).first),
    ).clearSnackBars();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// 환불 규정 편집 화면을 **한 번** 열어 구간을 [count]개 추가하고 돌아온다.
  ///
  /// [expandSection]은 접힌 아코디언 안에 요약 행이 있는 화면(파티+숙박 콤보)에서
  /// 먼저 펼칠 섹션 제목이다 — 접혀 있으면 행이 트리에는 있어도 눌리지 않는다.
  Future<void> addTiers(
    WidgetTester tester,
    int count, {
    String? expandSection,
  }) async {
    if (expandSection != null) {
      await scrollAndTap(tester, find.text(expandSection));
      await tester.pumpAndSettle();
    }
    // 제목은 Text.rich(제목 + 빨간 *)라 find.text로는 잡히지 않는다 —
    // 요약 행 위젯 자체를 찾아 누른다.
    await scrollAndTap(
      tester,
      find.byWidgetPredicate(
        (w) =>
            w is SectionSummaryRow && w.title == RefundPolicyRule.sectionTitle,
      ),
    );
    await tester.pumpAndSettle();

    for (var i = 0; i < count; i++) {
      await tester.tap(find.text('구간 추가'));
      await tester.pumpAndSettle();
    }
    // 편집 화면을 닫고 등록 화면으로 돌아온다.
    Navigator.of(tester.element(find.text('구간 추가'))).pop();
    await tester.pumpAndSettle();
  }

  /// 등록 버튼을 눌렀을 때 환불 규정 안내가 떴는가.
  ///
  /// 등록을 누르면 화면이 **첫 누락 항목으로 스스로 이동**한다. 그러면 폼 맨
  /// 위의 안내 배너도, 폼 중간의 환불 규정 행도 화면 밖으로 밀려나고, 본문이
  /// [ListView]인 화면은 그것들을 아예 만들지 않는다. 그래서 "어딘가에 문구가
  /// 있나"를 한 번 보고 끝내면 안 되고, 위로 조금씩 되돌리며 확인해야 한다.
  Future<bool> refundBlocked(WidgetTester tester) async {
    // 자동 이동이 끝나기 전에 끌면 둘이 서로 밀어내 엉뚱한 자리에 선다.
    await tester.pumpAndSettle();
    bool found() =>
        find.text(RefundPolicyRule.requiredMessage).evaluate().isNotEmpty;
    for (var i = 0; i < 16; i++) {
      if (found()) return true;
      await tester.dragFrom(const Offset(195, 400), const Offset(0, 300));
      await tester.pump(const Duration(milliseconds: 20));
    }
    return found();
  }

  /// 한 화면에서 "0개면 막히고, [tiers]개를 채우면 풀린다"를 확인한다.
  Future<void> runCase(
    WidgetTester tester, {
    required Widget screen,
    required String submitLabel,
    required int tiers,
    String? expandSection,
  }) async {
    await pump(tester, screen);

    await scrollAndTap(tester, find.text(submitLabel));
    expect(await refundBlocked(tester), isTrue, reason: '0개인데 저장이 막히지 않았다');

    // 다른 필수값은 여전히 비어 있다 — 그래도 환불 규정만은 통과해야 한다.
    await addTiers(tester, tiers, expandSection: expandSection);
    await scrollAndTap(tester, find.text(submitLabel));
    expect(await refundBlocked(tester), isFalse, reason: '$tiers개인데 여전히 막힌다');
  }

  final screens =
      <String, ({Widget screen, String submitLabel, String? expandSection})>{
        '파티 등록': (
          screen: const PartyRegisterScreen(),
          submitLabel: '파티 등록하기',
          expandSection: null,
        ),
      };

  for (final entry in screens.entries) {
    group(entry.key, () {
      testWidgets('0개 → 저장 불가, 1개 → 저장 가능', (tester) async {
        await runCase(
          tester,
          screen: entry.value.screen,
          submitLabel: entry.value.submitLabel,
          tiers: 1,
          expandSection: entry.value.expandSection,
        );
      });

      testWidgets('여러 개도 정상 저장', (tester) async {
        await runCase(
          tester,
          screen: entry.value.screen,
          submitLabel: entry.value.submitLabel,
          tiers: 3,
          expandSection: entry.value.expandSection,
        );
      });
    });
  }
}

// 새 파티 등록 진입 정책.
//
// ── 정본은 사업자 인증 하나 ─────────────────────────────────────────────────
// 자격은 `users/{uid}.businessVerification.status == 'verified'` 하나로만
// 정한다([PartyCreateEligibility]). 개인(사업자 미인증) 호스트의 파티 등록은
// 준비 중이라 지금은 잠겨 있고, `appConfig/policy`의
// individualHostPartyCreateEnabled를 true로 바꾸면 **앱 재배포 없이** 열린다.
//
// ── 이 파일이 지키는 것 ─────────────────────────────────────────────────────
//   · 사업자 + 공간 있음  → '내 플레이스에서 여는 파티' / '새 파티 만들기'
//   · 사업자 + 공간 없음  → 곧장 등록 폼(진입이 하나도 안 바뀐다)
//   · 새 파티 만들기      → 연결 필드를 자동으로 넣지 않는다
//   · 내 플레이스에서     → 고른 공간이 그대로 연결 대상으로 들어간다
//   · 개인               → 폼에 못 들어가고 "준비 중" 안내만 받는다
//   · 개인 안내          → 플레이스 등록을 권하지 않는다(자격이 없는 길이다)
//   · 정책이 열리면      → 개인도 그대로 통과한다
//   · 자격을 못 읽으면   → 막는다(fail-closed)
//
// 저장 스키마와 연결 로직은 이 검사의 대상이 아니다 — 진입만 본다.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:party_app/screens/party_register_entry_choice_screen.dart';
import 'package:party_app/screens/party_register_screen.dart';
import 'package:party_app/services/party_create_eligibility.dart';
import 'package:party_app/services/place_party_link_service.dart';
import 'package:party_app/utils/user_session.dart';

const _me = 'host-me';

PartyPrelinkTarget _space(
  String id,
  String name, {
  PartyLinkTarget target = PartyLinkTarget.place,
}) => PartyPrelinkTarget(
  target: target,
  targetId: id,
  data: {
    'hostId': _me,
    'name': name,
    'address': '서울 마포구 와우산로 1',
    'latitude': 37.55,
    'longitude': 126.92,
  },
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UserSession.userId = _me;
  });

  tearDown(() {
    PartyCreateEligibility.debugResetSource();
    UserSession.userId = '';
  });

  /// 사업자 인증 상태와 개인 등록 정책을 고정한다.
  void useAccount({required bool business, bool individualOpen = false}) {
    PartyCreateEligibility.debugSetSource(
      businessVerified: () async => business,
      individualEnabled: () async => individualOpen,
    );
  }

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pumpAndSettle();
  }

  // ── 자격 판정 ───────────────────────────────────────────────────────────

  group('자격 판정', () {
    test('사업자 인증을 마쳤으면 통과한다', () async {
      useAccount(business: true);
      expect(await PartyCreateEligibility.evaluate(), PartyCreateGate.allowed);
    });

    test('사업자면 개인 정책이 꺼져 있어도 통과한다', () async {
      useAccount(business: true, individualOpen: false);
      expect(await PartyCreateEligibility.evaluate(), PartyCreateGate.allowed);
    });

    test('사업자면 개인 정책을 읽지도 않는다', () async {
      var readPolicy = false;
      PartyCreateEligibility.debugSetSource(
        businessVerified: () async => true,
        individualEnabled: () async {
          readPolicy = true;
          return false;
        },
      );

      expect(await PartyCreateEligibility.evaluate(), PartyCreateGate.allowed);
      expect(
        readPolicy,
        isFalse,
        reason: '개인 정책 문서를 못 읽는다고 사업자 등록이 막히면 안 된다',
      );
    });

    test('개인은 정책이 잠겨 있으면 막힌다', () async {
      useAccount(business: false, individualOpen: false);
      expect(
        await PartyCreateEligibility.evaluate(),
        PartyCreateGate.blockedIndividual,
      );
    });

    // 앱 재배포 없이 열리는 구조인지 — 정책 값 하나만 바뀌면 된다.
    test('정책이 열리면 개인도 통과한다', () async {
      useAccount(business: false, individualOpen: true);
      expect(await PartyCreateEligibility.evaluate(), PartyCreateGate.allowed);
    });
  });

  // ── 사업자 ─────────────────────────────────────────────────────────────

  group('사업자 + 공간 있음', () {
    testWidgets('연결 / 새 파티 두 선택지를 준다', (tester) async {
      useAccount(business: true);
      await pump(
        tester,
        partyRegisterEntryScreen([_space('E1', 'OO 혼술바')]),
      );

      expect(find.text('내 플레이스에서 여는 파티'), findsOneWidget);
      expect(find.text('등록한 플레이스 또는 대여 공간과 연결해서 파티를 등록해요.'), findsOneWidget);
      expect(find.text('새 파티 만들기'), findsOneWidget);
      expect(find.text('내 플레이스와 연결하지 않고 새로운 파티를 등록해요.'), findsOneWidget);
    });

    testWidgets("'새 파티 만들기'는 연결 대상 없이 폼을 연다", (tester) async {
      useAccount(business: true);
      await pump(
        tester,
        partyRegisterEntryScreen([_space('E1', 'OO 혼술바')]),
      );

      await tester.tap(find.text('새 파티 만들기'));
      await tester.pumpAndSettle();

      final form = tester.widget<PartyRegisterScreen>(
        find.byType(PartyRegisterScreen),
      );
      expect(
        form.initialSpace,
        isNull,
        reason: 'linkedEventId/linkedPlaceId를 자동으로 넣는 경로가 생겼다',
      );
    });

    testWidgets("'내 플레이스에서 여는 파티'는 고른 공간을 그대로 넘긴다", (tester) async {
      useAccount(business: true);
      await pump(
        tester,
        partyRegisterEntryScreen([
          _space('E1', 'OO 혼술바'),
          _space('P1', 'OO 파티룸', target: PartyLinkTarget.rental),
        ]),
      );

      await tester.tap(find.text('내 플레이스에서 여는 파티'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OO 파티룸'));
      await tester.pumpAndSettle();

      final form = tester.widget<PartyRegisterScreen>(
        find.byType(PartyRegisterScreen),
      );
      expect(form.initialSpace?.targetId, 'P1');
      expect(form.initialSpace?.target, PartyLinkTarget.rental);
    });
  });

  group('사업자 + 공간 없음', () {
    // 공간을 안 가진 호스트에게는 진입이 조금도 달라지지 않는다.
    testWidgets('선택 화면 없이 곧장 등록 폼이다', (tester) async {
      useAccount(business: true);

      final screen = partyRegisterEntryScreen(const []);
      expect(screen, isA<PartyRegisterScreen>());
      expect(screen, isNot(isA<PartyRegisterEntryChoiceScreen>()));

      await pump(tester, screen);
      expect(find.text('어떤 파티인가요?'), findsNothing);
    });
  });

  // ── 개인 ───────────────────────────────────────────────────────────────

  group('개인(사업자 미인증)', () {
    /// 관문이 돌려준 값 — 막히면 안내를 **닫은 뒤에야** 채워진다
    /// ([PartyCreateEligibility.ensure]가 시트가 닫힐 때까지 기다린다).
    bool? gateResult;

    setUp(() => gateResult = null);

    /// 관문을 직접 통과시켜 본다 — 통과하면 호출부가 폼을 연다.
    Future<void> tapGate(WidgetTester tester) async {
      await pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  gateResult = await PartyCreateEligibility.ensure(context);
                },
                child: const Text('파티 등록'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('파티 등록'));
      await tester.pumpAndSettle();
    }

    /// 안내를 닫아 관문이 값을 돌려주게 한다.
    Future<void> dismissNotice(WidgetTester tester) async {
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
    }

    testWidgets('신규 파티 폼으로 들어가지 못한다', (tester) async {
      useAccount(business: false);
      await tapGate(tester);

      expect(find.byType(PartyRegisterScreen), findsNothing);
      await dismissNotice(tester);
      expect(gateResult, isFalse, reason: '관문이 통과를 돌려주면 호출부가 폼을 연다');
    });

    testWidgets('준비 중 안내를 받는다', (tester) async {
      useAccount(business: false);
      await tapGate(tester);

      expect(find.text('개인 파티 등록은 준비 중이에요'), findsOneWidget);
      expect(
        find.textContaining('사업자가 아닌 개인 호스트의 파티 등록 기능은'),
        findsOneWidget,
      );
      expect(find.textContaining('약 한 달 후'), findsOneWidget);
    });

    // 플레이스 등록도 사업자 자격이 필요한 길이라, 권하면 눌러서 또 막힌다.
    testWidgets('플레이스 등록을 권하지 않는다', (tester) async {
      useAccount(business: false);
      await tapGate(tester);

      expect(find.text('플레이스 등록하기'), findsNothing);
      expect(find.textContaining('플레이스를 먼저 등록'), findsNothing);
      // 아무 데도 보내지 않고 닫기만 있다.
      expect(find.text('확인'), findsOneWidget);
    });

    testWidgets('정책이 열리면 안내 없이 그대로 통과한다', (tester) async {
      useAccount(business: false, individualOpen: true);
      await tapGate(tester);

      expect(gateResult, isTrue);
      expect(find.text('개인 파티 등록은 준비 중이에요'), findsNothing);
    });

    // 자격을 못 읽는 상태가 곧 정책 우회가 되면 안 된다.
    testWidgets('자격 조회가 실패해도 열리지 않는다', (tester) async {
      PartyCreateEligibility.debugSetSource(
        businessVerified: () async => false,
        individualEnabled: () async => false,
      );
      await tapGate(tester);

      expect(find.text('개인 파티 등록은 준비 중이에요'), findsOneWidget);
      await dismissNotice(tester);
      expect(gateResult, isFalse);
    });
  });

  // ── 우회로가 없다 ───────────────────────────────────────────────────────
  //
  // 관문을 등록 화면에만 두면 임시저장 이어쓰기·재등록·플레이스 연결이 그대로
  // 우회로가 된다. 새 파티를 만드는 **모든 입구**가 같은 함수를 부르는지
  // 파일 단위로 묶어 둔다.

  group('전수 가드 — 새 파티를 만드는 입구는 모두 관문을 지난다', () {
    const entries = {
      // 진입 단일 창구 — 등록 유형 화면의 '파티 등록' 카드도 이 함수를 거친다
      // (openPartyRegisterEntry). 그래서 register_type_screen은 이 목록에
      // 없다: 저장 한 번에 파티까지 만들던 "플레이스+파티 등록"이 없어지면서,
      // 그 화면에서 파티가 만들어지는 길은 이 창구 하나만 남았다.
      'lib/screens/party_register_entry_choice_screen.dart': '파티 등록 진입',
      // 마이 > 임시저장 "이어서 작성"
      'lib/screens/drafts_list_screen.dart': '임시저장 이어쓰기',
      // 마이 > 파티츄 호스트 "재등록"
      'lib/screens/my_host_hub_screen.dart': '지난 파티 재등록',
      // 파티 상세 "재등록"
      'lib/screens/party_detail_screen.dart': '파티 상세 재등록',
      // 플레이스 연결 관리 "새 파티 만들기"
      'lib/screens/place_party_link_screen.dart': '플레이스 연결 관리',
      // 플레이스 상세 호스트 "파티 추가"
      'lib/widgets/place_product/place_promotion_list_section.dart': '플레이스 상세',
      // 플레이스 등록 직후 "파티 등록하기"
      'lib/services/place_followup_entry.dart': '플레이스 등록 후속',
    };

    test('모든 입구가 PartyCreateEligibility를 부른다', () {
      final missing = <String>[];
      entries.forEach((path, label) {
        final src = File(path).readAsStringSync();
        if (!src.contains('PartyCreateEligibility.ensure(')) {
          missing.add('$path — $label');
        }
      });
      expect(
        missing,
        isEmpty,
        reason:
            '새 파티를 만드는 입구인데 관문을 지나지 않는 곳이 있다.\n'
            '화면마다 자격 판정을 따로 적지 말고 PartyCreateEligibility.ensure를 쓰자:\n'
            '${missing.join('\n')}',
      );
    });
  });
}

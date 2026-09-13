// 새 플레이스 등록 진입 정책.
//
// ── 정본은 사업자 **권한** 하나 ─────────────────────────────────────────────
// 자격은 [BusinessVerification.isVerified] 하나로만 정한다 — 진위(status)와
// 권한(authorization)을 **둘 다** 본다. 파티 등록과 달리 개인에게 열어주는
// 정책 예외가 없다 — 플레이스는 실제 매장·공간을 운영하는 사업자만 올린다.
//
//     status == verified && (authorization == self ||
//                            (authorization == delegated && delegationId 있음))
//
// ⚠️ `status == verified` 하나만으로 통과시키면 남의 사업자등록증 사본 한 장으로
//    플레이스를 올릴 수 있다. 서버(isBusinessAuthorized)·규칙(isBusinessVerified)도
//    같은 두 축을 보므로, 여기만 넓히면 "앱은 열어줬는데 서버가 막는" 상태가 된다.
//
// ── 이 파일이 지키는 것 ─────────────────────────────────────────────────────
//   · verified + self / delegated(+id)     → 통과한다
//   · delegated인데 id가 없다              → 막힌다
//   · verified인데 authorization이 없다     → 막힌다 **+ 화면이 그 사실을 말한다**
//   · verified + pendingOwnerApproval      → 막힌다 + 대표자 승인으로 보낸다
//   · unverified/pending/failed/suspended  → 전부 막힌다
//   · 안내                                 → 갈 곳이 있다(사업자 인증 화면)
//   · 다녀온 뒤                            → 캐시가 아니라 **서버를 다시 읽는다**
//   · 자격을 못 읽으면                      → 막는다(fail-closed)
//   · 우회로가 없다                         → 모든 입구가 이 관문을 지난다
//
// ── 이 파일이 막는 재발 ─────────────────────────────────────────────────────
// 권한 축이 생기기 전에 인증을 마친 계정(status: verified, authorization 없음)이
// 화면에서는 '인증 완료'로 보이는데 등록은 막혀, 안내 시트와 인증 완료 화면
// 사이를 무한히 오가던 버그가 있었다. 관문은 옳았고 **문구가 거짓말**이었다.
// 아래 '문구가 상태와 어긋나지 않는다' 그룹이 그 조합을 고정한다.
//
// 기존 플레이스의 조회·수정·관리는 이 검사의 대상이 아니다 — 신규 생성 진입만
// 본다(firestore.rules의 events/places도 create에만 같은 조건을 건다).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:party_app/models/business_verification.dart';
import 'package:party_app/services/place_create_eligibility.dart';
import 'package:party_app/utils/user_session.dart';

const _me = 'host-me';

/// 권한까지 열린 정상 사업자 — 이 파일에서 "통과해야 하는 상태"의 기준값.
const _authorized = BusinessVerification(
  status: BusinessVerificationStatus.verified,
  authorization: BusinessAuthorization.self,
);

/// 권한 축이 기록되기 전에 인증을 마친 계정(이번 버그의 실제 데이터).
const _legacyVerified = BusinessVerification(
  status: BusinessVerificationStatus.verified,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UserSession.userId = _me;
  });

  tearDown(() {
    PlaceCreateEligibility.debugResetSource();
    UserSession.userId = '';
  });

  /// 사업자 인증 상태를 고정한다.
  void use(BusinessVerification v) {
    PlaceCreateEligibility.debugSetSource(() async => v);
  }

  /// 진위 축만 지정한다(권한 없음 — 옛 데이터와 같은 모양).
  void useStatus(BusinessVerificationStatus status) {
    use(BusinessVerification(status: status));
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
    test('본인 명의 확인(self)은 통과한다', () async {
      use(_authorized);
      expect(await PlaceCreateEligibility.evaluate(), PlaceCreateGate.allowed);
    });

    test('대표자 위임(delegated + 근거 문서 id)도 통과한다', () async {
      use(
        const BusinessVerification(
          status: BusinessVerificationStatus.verified,
          authorization: BusinessAuthorization.delegated,
          delegationId: 'DLG1',
        ),
      );
      expect(await PlaceCreateEligibility.evaluate(), PlaceCreateGate.allowed);
    });

    // 근거 문서 id가 빈 delegated는 어떤 정상 경로로도 만들어지지 않는다 —
    // 그 값을 인정하면 authorization 문자열 하나로 권한이 열린다.
    test('delegated인데 근거 문서 id가 없으면 막힌다', () async {
      use(
        const BusinessVerification(
          status: BusinessVerificationStatus.verified,
          authorization: BusinessAuthorization.delegated,
        ),
      );
      expect(
        await PlaceCreateEligibility.evaluate(),
        PlaceCreateGate.blockedNotBusiness,
      );
    });

    // ⚠️ 이번 버그의 실제 데이터. 화면이 '인증 완료'로 보였다고 해서 여기를
    //    열면, 남의 사업자등록증으로 통과한 계정까지 함께 열린다.
    test('verified인데 authorization이 없으면 막힌다(옛 데이터)', () async {
      use(_legacyVerified);
      expect(
        await PlaceCreateEligibility.evaluate(),
        PlaceCreateGate.blockedNotBusiness,
      );
    });

    test('대표자 확인 대기(pendingOwnerApproval)는 막힌다', () async {
      use(
        const BusinessVerification(
          status: BusinessVerificationStatus.verified,
          authorization: BusinessAuthorization.pendingOwnerApproval,
        ),
      );
      expect(
        await PlaceCreateEligibility.evaluate(),
        PlaceCreateGate.blockedNotBusiness,
      );
    });

    // 국세청 확인을 통과한 verified만 사업자다 — 나머지는 "아직"이지 사업자가
    // 아니다. 하나라도 통과시키면 인증 없이 플레이스가 올라간다.
    test('verified가 아닌 상태는 권한이 있어도 막힌다', () async {
      for (final status in [
        BusinessVerificationStatus.unverified,
        BusinessVerificationStatus.pending,
        BusinessVerificationStatus.failed,
        BusinessVerificationStatus.suspended,
      ]) {
        // authorization을 self로 줘도 막혀야 한다 — 두 축을 **모두** 본다.
        use(
          BusinessVerification(
            status: status,
            authorization: BusinessAuthorization.self,
          ),
        );
        expect(
          await PlaceCreateEligibility.evaluate(),
          PlaceCreateGate.blockedNotBusiness,
          reason: '${status.key}가 통과했다 — 진위 축도 함께 봐야 한다',
        );
      }
    });

    // 파티 등록에는 `appConfig/policy`로 개인을 열어주는 예외가 있다. 플레이스에
    // 그 예외가 생기면 정책 값 하나로 인증 없는 플레이스가 열린다.
    test('개인에게 열어주는 정책 예외가 없다', () {
      final src = File(
        'lib/services/place_create_eligibility.dart',
      ).readAsStringSync();
      expect(
        src.contains('HostOpenPolicyService'),
        isFalse,
        reason: '플레이스 등록에 개인 호스트 정책 예외가 생겼다',
      );
    });
  });

  // ── 관문 ───────────────────────────────────────────────────────────────

  group('관문', () {
    /// 관문이 돌려준 값 — 막히면 안내를 **닫은 뒤에야** 채워진다
    /// ([PlaceCreateEligibility.ensure]가 시트가 닫힐 때까지 기다린다).
    bool? gateResult;

    setUp(() => gateResult = null);

    /// 관문을 직접 통과시켜 본다 — 통과하면 호출부가 등록 화면을 연다.
    Future<void> tapGate(WidgetTester tester) async {
      await pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  gateResult = await PlaceCreateEligibility.ensure(context);
                },
                child: const Text('플레이스 등록'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('플레이스 등록'));
      await tester.pumpAndSettle();
    }

    /// 안내를 닫아 관문이 값을 돌려주게 한다.
    Future<void> dismissNotice(WidgetTester tester) async {
      await tester.tap(find.text('나중에'));
      await tester.pumpAndSettle();
    }

    testWidgets('권한까지 있는 사업자는 안내 없이 그대로 통과한다', (tester) async {
      use(_authorized);
      await tapGate(tester);

      expect(gateResult, isTrue);
      expect(find.text('플레이스 등록은 사업자 인증이 필요해요'), findsNothing);
    });

    testWidgets('미인증은 안내를 받고 통과하지 못한다', (tester) async {
      useStatus(BusinessVerificationStatus.unverified);
      await tapGate(tester);

      expect(find.text('플레이스 등록은 사업자 인증이 필요해요'), findsOneWidget);
      expect(find.textContaining('사업자 인증을 마친 호스트만'), findsOneWidget);

      await dismissNotice(tester);
      expect(gateResult, isFalse, reason: '관문이 통과를 돌려주면 호출부가 폼을 연다');
    });

    // 파티 쪽 안내("준비 중")와 달리 여기는 **갈 곳이 있다** — 인증만 마치면
    // 바로 등록할 수 있으므로 그 자리로 보낸다.
    testWidgets('안내가 사업자 인증으로 보낸다', (tester) async {
      useStatus(BusinessVerificationStatus.unverified);
      await tapGate(tester);

      expect(find.text('사업자 인증하기'), findsOneWidget);
    });

    // 이미 시도해 본 계정에는 "왜 아직 안 되는지"를 상태별 문구로 말해준다 —
    // 문구는 BusinessVerification.guidance 정본을 그대로 쓴다.
    testWidgets('이미 시도한 상태는 그 이유를 말해준다', (tester) async {
      useStatus(BusinessVerificationStatus.suspended);
      await tapGate(tester);

      expect(
        find.text(
          const BusinessVerification(
            status: BusinessVerificationStatus.suspended,
          ).guidance,
        ),
        findsOneWidget,
      );
      expect(find.text('사업자 인증 다시 확인하기'), findsOneWidget);
    });

    // 자격을 못 읽는 상태가 곧 정책 우회가 되면 안 된다
    // (BusinessVerificationService.fetch가 실패 시 none을 돌려준다).
    testWidgets('자격 조회가 실패해도 열리지 않는다', (tester) async {
      PlaceCreateEligibility.debugSetSource(
        () async => BusinessVerification.none,
      );
      await tapGate(tester);

      expect(find.text('플레이스 등록은 사업자 인증이 필요해요'), findsOneWidget);
      await dismissNotice(tester);
      expect(gateResult, isFalse);
    });

    // ── 안내가 남은 일을 정확히 말한다 ──────────────────────────────────
    //
    // 국세청 확인을 이미 통과한 사람에게 "사업자 인증 다시 확인하기"만 보여
    // 주면, 인증 화면에 갔다가 "이미 됐는데?" 하고 돌아와 같은 시트를 다시
    // 만난다. 그 왕복이 이번 버그의 체감 증상이었다.

    testWidgets('authorization 없는 verified — 권한 확인이 필요하다고 말한다', (
      tester,
    ) async {
      use(_legacyVerified);
      await tapGate(tester);

      expect(find.text('사업자 권한 확인이 한 번 더 필요해요'), findsOneWidget);
      expect(find.text('사업자 권한 확인하기'), findsOneWidget);
      // 인증이 끝났다는 말이 차단 안내 안에 함께 있으면 안 된다.
      expect(find.textContaining('모두 끝났어요'), findsNothing);

      await dismissNotice(tester);
      expect(gateResult, isFalse);
    });

    testWidgets('pendingOwnerApproval — 대표자 승인으로 보낸다', (tester) async {
      use(
        const BusinessVerification(
          status: BusinessVerificationStatus.verified,
          authorization: BusinessAuthorization.pendingOwnerApproval,
        ),
      );
      await tapGate(tester);

      expect(find.text('플레이스 등록에 대표자 승인이 필요해요'), findsOneWidget);
      expect(find.text('대표자 승인 받으러 가기'), findsOneWidget);
      // 본인이 다시 확인해서 풀 수 있는 일이 아니다 — 그렇게 말하면 안 된다.
      expect(find.text('사업자 권한 확인하기'), findsNothing);

      await dismissNotice(tester);
      expect(gateResult, isFalse);
    });
  });

  // ── 다녀온 뒤 다시 읽는다 ───────────────────────────────────────────────
  //
  // 예전에는 안내 시트가 인증 화면을 열어 두고 곧바로 false를 돌려줬다. 인증을
  // 마치고 돌아와도 관문은 이미 끝나 있어서, 등록을 처음부터 다시 눌러야 했다.

  group('인증 화면을 다녀온 뒤', () {
    bool? gateResult;
    late int fetchCount;

    setUp(() {
      gateResult = null;
      fetchCount = 0;
    });

    /// 첫 조회는 [before], 인증 화면을 다녀온 뒤 조회는 [after]를 돌려준다.
    void useSequence(BusinessVerification before, BusinessVerification after) {
      PlaceCreateEligibility.debugSetSource(() async {
        fetchCount += 1;
        return fetchCount == 1 ? before : after;
      });
    }

    /// 실물 [BusinessVerificationScreen]은 Firestore를 읽어 위젯 테스트에서
    /// 띄울 수 없다 — 다녀올 화면만 대역으로 갈아 끼운다.
    void useStubScreen() {
      PlaceCreateEligibility.debugSetVerificationRoute(
        () => MaterialPageRoute<void>(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('인증 마치고 돌아가기'),
              ),
            ),
          ),
        ),
      );
    }

    Future<void> runGate(WidgetTester tester) async {
      tester.view.physicalSize = const Size(420, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    gateResult = await PlaceCreateEligibility.ensure(context);
                  },
                  child: const Text('플레이스 등록'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('플레이스 등록'));
      await tester.pumpAndSettle();
    }

    testWidgets('인증을 마치고 돌아오면 최신 상태를 다시 읽고 통과시킨다', (tester) async {
      useSequence(_legacyVerified, _authorized);
      useStubScreen();
      await runGate(tester);

      await tester.tap(find.text('사업자 권한 확인하기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('인증 마치고 돌아가기'));
      await tester.pumpAndSettle();

      expect(fetchCount, 2, reason: '들고 있던 값으로 판정하면 다시 읽지 않는다');
      expect(gateResult, isTrue, reason: '통과했는데 등록을 또 눌러야 하면 무한 반복이다');
    });

    // "다녀왔으니 통과"가 되면 그것이 곧 우회로다 — 다시 읽은 값으로만 정한다.
    testWidgets('다녀왔어도 권한이 없으면 통과하지 않는다', (tester) async {
      useSequence(_legacyVerified, _legacyVerified);
      useStubScreen();
      await runGate(tester);

      await tester.tap(find.text('사업자 권한 확인하기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('인증 마치고 돌아가기'));
      await tester.pumpAndSettle();

      expect(fetchCount, 2);
      expect(gateResult, isFalse);
    });

    testWidgets('대표자 승인 대기로 끝나도 등록 화면으로 보내지 않는다', (tester) async {
      useSequence(
        _legacyVerified,
        const BusinessVerification(
          status: BusinessVerificationStatus.verified,
          authorization: BusinessAuthorization.pendingOwnerApproval,
        ),
      );
      useStubScreen();
      await runGate(tester);

      await tester.tap(find.text('사업자 권한 확인하기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('인증 마치고 돌아가기'));
      await tester.pumpAndSettle();

      expect(gateResult, isFalse);
    });

    testWidgets('"나중에"를 누르면 인증 화면을 열지 않는다', (tester) async {
      useSequence(_legacyVerified, _authorized);
      useStubScreen();
      await runGate(tester);

      await tester.tap(find.text('나중에'));
      await tester.pumpAndSettle();

      expect(find.text('인증 마치고 돌아가기'), findsNothing);
      expect(fetchCount, 1, reason: '가지 않았는데 다시 읽을 이유가 없다');
      expect(gateResult, isFalse);
    });
  });

  // ── 문구가 상태와 어긋나지 않는다 ───────────────────────────────────────
  //
  // 관문은 처음부터 옳았다. 무한 반복을 만든 것은 **문구**다 — 권한이 없는데
  // 화면이 '인증 완료'라고 말하니, 사용자는 다 됐다고 믿고 등록을 다시 눌렀다.

  group('문구가 상태와 어긋나지 않는다', () {
    test('권한 없는 verified는 "인증 완료"라고 말하지 않는다', () {
      expect(_legacyVerified.isVerified, isFalse);
      expect(_legacyVerified.headline, isNot(BusinessVerificationStatus.verified.label));
      expect(_legacyVerified.headline, '사업자 권한 확인이 필요해요');
      expect(_legacyVerified.guidance, isNot(contains('모두 끝났어요')));
      expect(_legacyVerified.needsReverification, isTrue);
    });

    test('근거 문서 id 없는 delegated도 마찬가지다', () {
      const v = BusinessVerification(
        status: BusinessVerificationStatus.verified,
        authorization: BusinessAuthorization.delegated,
      );
      expect(v.isVerified, isFalse);
      expect(v.needsReverification, isTrue);
      expect(v.headline, isNot(BusinessVerificationStatus.verified.label));
    });

    test('대표자 승인 대기는 재확인이 아니라 승인으로 안내한다', () {
      const v = BusinessVerification(
        status: BusinessVerificationStatus.verified,
        authorization: BusinessAuthorization.pendingOwnerApproval,
      );
      expect(v.needsOwnerApproval, isTrue);
      expect(v.needsReverification, isFalse, reason: '본인이 다시 눌러서 풀리는 일이 아니다');
      // 제목은 **끝난 사실**부터 말한다(실패가 아니다). 남은 일은 guidance가
      // 이어서 말하므로, 제목이 '인증 완료'와 같아지지만 않으면 된다.
      expect(v.headline, '사업자 정보는 확인됐어요');
      expect(v.headline, isNot(BusinessVerificationStatus.verified.label));
      expect(v.guidance, contains('대표자 확인이 필요합니다'));
    });

    // 성공 문구는 **권한까지 열렸을 때만** 나와야 한다. 이 한 줄이 무너지면
    // 이번 버그가 그대로 재발한다.
    test('성공 문구는 권한이 열린 상태에서만 나온다', () {
      expect(_authorized.isVerified, isTrue);
      expect(_authorized.headline, BusinessVerificationStatus.verified.label);
      expect(_authorized.guidance, contains('모두 끝났어요'));

      for (final v in [
        _legacyVerified,
        const BusinessVerification(
          status: BusinessVerificationStatus.verified,
          authorization: BusinessAuthorization.pendingOwnerApproval,
        ),
        const BusinessVerification(
          status: BusinessVerificationStatus.verified,
          authorization: BusinessAuthorization.delegated,
        ),
      ]) {
        expect(
          v.guidance,
          isNot(contains('모두 끝났어요')),
          reason: '권한이 없는데 성공 문구가 나온다 — 등록은 막히므로 모순이다',
        );
      }
    });

    // 화면이 status만 보고 색을 고르면 초록 '인증 완료' 카드가 그대로 뜬다.
    test('권한 없는 verified는 하나의 값으로 걸러진다', () {
      expect(_legacyVerified.verifiedWithoutAuthorization, isTrue);
      expect(_authorized.verifiedWithoutAuthorization, isFalse);
      expect(
        const BusinessVerification(
          status: BusinessVerificationStatus.failed,
        ).verifiedWithoutAuthorization,
        isFalse,
        reason: '진위부터 실패한 상태까지 여기로 오면 안내가 뒤바뀐다',
      );
    });

    // 상태 카드가 그 값을 실제로 쓰는지 — 색 분기가 status로 되돌아가면
    // 문구는 고쳐졌는데 카드만 초록으로 남는다.
    test('상태 카드가 권한 축을 보고 색을 고른다', () {
      final src = File(
        'lib/screens/business_verification_screen.dart',
      ).readAsStringSync();
      expect(
        src.contains('verification.verifiedWithoutAuthorization'),
        isTrue,
        reason: '상태 카드가 권한 없는 verified를 초록 인증 완료로 그린다',
      );
    });
  });

  // ── 우회로가 없다 ───────────────────────────────────────────────────────
  //
  // 관문을 등록 유형 화면에만 두면 상단바 "등록하기"·임시저장 이어쓰기·이벤트
  // 등록 안내가 그대로 우회로가 된다. 새 플레이스를 만드는 **모든 입구**가 같은
  // 함수를 부르는지 파일 단위로 묶어 둔다.

  group('전수 가드 — 새 플레이스를 만드는 입구는 모두 관문을 지난다', () {
    const entries = {
      // 등록 > 플레이스 등록
      'lib/screens/register_type_screen.dart': '등록 유형 화면',
      // 데스크톱 상단바 "등록하기"(플레이스·장소대여 탭)
      'lib/screens/main_screen.dart': '상단바 등록하기',
      // 마이 > 임시저장 "이어서 작성"(event = 매장, place = 공간대여)
      'lib/screens/drafts_list_screen.dart': '임시저장 이어쓰기',
      // 이벤트 등록 > "플레이스를 먼저 등록해주세요" > "플레이스 등록하기"
      'lib/services/place_event_entry.dart': '이벤트 등록 안내',
    };

    test('모든 입구가 PlaceCreateEligibility를 부른다', () {
      final missing = <String>[];
      entries.forEach((path, label) {
        final src = File(path).readAsStringSync();
        if (!src.contains('PlaceCreateEligibility.ensure(')) {
          missing.add('$path — $label');
        }
      });
      expect(
        missing,
        isEmpty,
        reason:
            '새 플레이스를 만드는 입구인데 관문을 지나지 않는 곳이 있다.\n'
            '화면마다 자격 판정을 따로 적지 말고 PlaceCreateEligibility.ensure를 쓰자:\n'
            '${missing.join('\n')}',
      );
    });
  });

  // ── 서버도 같은 조건을 본다 ─────────────────────────────────────────────
  //
  // 앱 관문은 **화면을 열지 말지**를 정할 뿐이다. 구버전 앱과 SDK 직접 호출은
  // firestore.rules가 막는다 — 두 컬렉션 모두 create에만 조건이 붙어야 한다
  // (update·delete까지 막으면 기존 플레이스의 관리가 통째로 멈춘다).

  group('firestore.rules', () {
    late final String rules = File('../firestore.rules').readAsStringSync();

    /// `match /<collection>/{...} { ... }` 한 덩어리.
    String blockOf(String collection) {
      final start = rules.indexOf('match /$collection/{');
      expect(start, isNot(-1), reason: '$collection 규칙을 찾지 못했다');
      final end = rules.indexOf('\n    }', start);
      expect(end, isNot(-1), reason: '$collection 규칙의 끝을 찾지 못했다');
      return rules.substring(start, end);
    }

    for (final collection in ['places', 'events']) {
      test('$collection create가 사업자 인증을 요구한다', () {
        final block = blockOf(collection);
        final create = block.substring(block.indexOf('allow create:'));
        expect(
          create.substring(0, create.indexOf(';')),
          contains('isBusinessVerified()'),
          reason: '$collection 신규 생성이 본인확인만으로 통과한다',
        );
      });

      // 레거시 개인 소유 플레이스를 삭제·이관하지 않기로 했으므로, 그 호스트가
      // 자기 문서를 계속 다룰 수 있어야 한다.
      test('$collection update·delete는 그대로다', () {
        final block = blockOf(collection);
        for (final op in ['allow update', 'allow delete']) {
          final at = block.indexOf(op);
          if (at == -1) continue;
          expect(
            block.substring(at, block.indexOf(';', at)),
            isNot(contains('isBusinessVerified()')),
            reason: '$collection $op까지 막으면 기존 플레이스 관리가 멈춘다',
          );
        }
      });
    }
  });
}

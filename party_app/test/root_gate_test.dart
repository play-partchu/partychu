import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/utils/root_gate.dart';
import 'package:party_app/utils/user_session.dart';

/// 루트 게이트 판정 — 앱의 첫 화면을 고르는 규칙 하나를 그대로 못박는다.
///
/// 여기서 확인하는 것은 "미인증 계정이 서비스 화면에 도달할 수 있는가"다.
/// 화면을 띄우고 닫는 방식(뒤로가기·pop)이 아니라 **판정 자체**를 시험하는
/// 이유는, 이번 수정의 핵심이 "닫을 화면을 만들지 않는다"이기 때문이다 —
/// 판정이 main을 돌려주지 않으면 MainScreen 위젯 자체가 만들어지지 않는다.
///
/// 서버 쪽 같은 정책은 functions/identityGuard.selfcheck.js가 본다.
void main() {
  RootGateScreen screenFor({
    bool isLoggedIn = true,
    String accountStatus = 'active',
    IdentityStatus identityStatus = IdentityStatus.verified,
  }) => resolveRootGateScreen(
    isLoggedIn: isLoggedIn,
    accountStatus: accountStatus,
    identityStatus: identityStatus,
  );

  group('로그인 회원', () {
    test('본인확인을 마쳤으면 서비스 화면', () {
      expect(
        screenFor(identityStatus: IdentityStatus.verified),
        RootGateScreen.main,
      );
    });

    test('미인증이면 본인확인 화면 — 신규가입·재로그인·세션복원 모두 같은 판정', () {
      // 이 판정에는 "어떻게 들어왔는가"가 없다. 그래서 신규 가입도, 네 가지
      // 로그인도, 로그아웃 후 재로그인도, 앱 강제종료 후 세션 복원도 전부
      // 같은 결과를 받는다 — 경로마다 게이트를 따로 걸던 예전 구조에서
      // 세션 복원 경로만 빠져 있던 것이 우회의 원인이었다.
      expect(
        screenFor(identityStatus: IdentityStatus.unverified),
        RootGateScreen.identityVerification,
      );
    });

    test('확인하는 중에는 로딩 — 실패로 단정하지 않는다', () {
      // 로그인 버튼을 누른 직후가 이 구간이다. 여기서 실패 화면을 띄우면
      // 정상 로그인 도중에 오류 화면이 번쩍이고 로그인 화면까지 걷힌다.
      expect(
        screenFor(identityStatus: IdentityStatus.checking),
        RootGateScreen.checking,
      );
      // 다만 서비스 화면도 아니다 — 판정 전에는 아무것도 통과시키지 않는다.
      expect(
        screenFor(identityStatus: IdentityStatus.checking),
        isNot(RootGateScreen.main),
      );
    });

    test('확인하지 못했으면 통과시키지 않고 확인 실패 화면(fail-closed)', () {
      // 네트워크 오류를 통과로 처리하면 연결을 끊는 것만으로 우회된다.
      expect(
        screenFor(identityStatus: IdentityStatus.unknown),
        RootGateScreen.identityCheckFailed,
      );
      // 그렇다고 인증 완료 사용자를 가두지도 않는다 — 확인 실패 화면은
      // 재시도와 로그아웃을 주고, 재시도가 성공하면 아래 판정으로 바뀐다.
      expect(
        screenFor(identityStatus: IdentityStatus.verified),
        RootGateScreen.main,
      );
    });
  });

  group('소셜 로그인 테스트 모드(allowUnverifiedMember)', () {
    // 운영 기본값은 false다 — 위 그룹의 판정이 곧 Release/Profile 동작이다.
    // 이 인자는 Android Debug 빌드에서만 true로 들어온다(root_gate.dart의
    // socialLoginTestMode).
    RootGateScreen testModeFor(
      IdentityStatus status, {
      String accountStatus = 'active',
    }) => resolveRootGateScreen(
      isLoggedIn: true,
      accountStatus: accountStatus,
      identityStatus: status,
      allowUnverifiedMember: true,
    );

    test('미인증 계정만 서비스 화면으로 통과시킨다', () {
      expect(testModeFor(IdentityStatus.unverified), RootGateScreen.main);
    });

    test('확인 중·확인 실패·탈퇴 대기는 테스트 모드여도 그대로다', () {
      expect(testModeFor(IdentityStatus.checking), RootGateScreen.checking);
      expect(
        testModeFor(IdentityStatus.unknown),
        RootGateScreen.identityCheckFailed,
      );
      expect(
        testModeFor(
          IdentityStatus.unverified,
          accountStatus: 'withdrawal_pending',
        ),
        RootGateScreen.withdrawalPending,
      );
    });
  });

  group('비로그인', () {
    test('본인확인 상태와 무관하게 서비스 화면 — 공유 링크로 온 사람이 파티를 볼 수 있어야 한다', () {
      for (final status in IdentityStatus.values) {
        expect(
          screenFor(isLoggedIn: false, identityStatus: status),
          RootGateScreen.main,
          reason: '비로그인인데 $status에서 막혔다',
        );
      }
    });
  });

  group('탈퇴 대기', () {
    test('본인확인 여부보다 앞선다', () {
      for (final status in IdentityStatus.values) {
        expect(
          screenFor(
            accountStatus: 'withdrawal_pending',
            identityStatus: status,
          ),
          RootGateScreen.withdrawalPending,
          reason: '탈퇴 대기인데 $status에서 다른 화면이 나왔다',
        );
      }
    });
  });

  group('세션 상태 연동', () {
    test('로그아웃하면 직전 계정의 인증 상태가 남지 않는다', () {
      UserSession.clear();
      expect(UserSession.isLoggedIn, isFalse);
      expect(UserSession.identityVerified, isFalse);
      // 비로그인이므로 게이트는 통과 — 이때의 상태는 판정에 쓰이지 않는다.
      expect(currentRootGateScreen(), RootGateScreen.main);
    });

    test('로그인 직후(프로필 읽기 전)에는 통과시키지 않고 확인 중으로 둔다', () {
      UserSession.clear();
      UserSession.userId = 'uid-under-test';
      // 프로필을 아직 읽지 않았다 — 인증도 미인증도 아니다.
      expect(UserSession.identityStatus, IdentityStatus.checking);
      expect(currentRootGateScreen(), RootGateScreen.checking);
      // 이 구간에도 딥링크·푸시는 화면을 쌓지 못한다.
      expect(rootGateBlocksService, isTrue);
      UserSession.clear();
    });
  });
}

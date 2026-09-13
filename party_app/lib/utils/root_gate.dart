import 'package:party_app/utils/user_session.dart';

/// 앱의 **첫 화면을 무엇으로 할지** 정하는 단 하나의 판단식.
///
/// ── 왜 루트인가 ─────────────────────────────────────────────────────────
/// 파티츄의 회원 정책은 "가입/로그인 후 본인확인을 마쳐야 회원 기능을 쓴다"다.
/// 예전에는 이 정책을 **기능 진입 시점**에 지켰다 — 로그인 성공 직후와 하단
/// 탭(등록·채팅·마이)에서 본인확인 화면을 `push`했다. 그 구조에는 두 가지
/// 구멍이 있었고, 둘 다 정상 사용자가 우연히 밟을 수 있는 경로였다.
///
///  1) 띄운 화면이 **닫혔다.** `push`한 평범한 라우트라 안드로이드 뒤로가기와
///     iOS 스와이프로 사라졌고, 그 아래에는 이미 MainScreen이 있었다.
///  2) 앱을 다시 켜면 **아무도 묻지 않았다.** 세션 복원 경로에는 본인확인
///     호출 자체가 없어서, 한 번 닫은 계정은 그 뒤로 영영 미인증으로 남았다.
///
/// 그래서 판정을 화면 진입이 아니라 **트리의 뿌리**로 옮겼다. 미인증 계정은
/// MainScreen이라는 위젯을 애초에 만들지 않는다 — 닫을 화면이 없으니 닫고
/// 들어갈 수도 없고, 앱을 다시 켜도 같은 판정이 처음부터 다시 걸린다.
///
/// ── 그래서 신청 버튼에는 게이트가 없다 ────────────────────────────────────
/// MainScreen에 서 있는 로그인 사용자는 **이미 본인확인을 마친 사람뿐**이다.
/// 그러므로 신청·예약 버튼마다 본인확인 화면을 다시 띄우는 중복 UX는 두지
/// 않는다(그건 정상 사용자에게 이유 없는 화면을 하나 더 보여주는 일이다).
/// 구버전 앱·직접 호출처럼 이 게이트를 건너뛴 요청은 UI가 아니라 서버가
/// 막는다 — functions/identityGuard.js와 firestore.rules의 isVerifiedMember().
enum RootGateScreen {
  /// 정상 서비스 화면.
  main,

  /// 본인확인 여부를 **확인하는 중** — 로딩만 보여준다.
  ///
  /// 로그인 버튼을 누른 직후가 이 구간이다. 이때 '확인 실패' 화면을 띄우면
  /// 정상 로그인 중에 오류 화면이 번쩍이고, 그 위의 로그인 화면까지 걷힌다.
  checking,

  /// 본인확인이 필요하다(서버에서 '미완료'를 확인함).
  identityVerification,

  /// 본인확인 여부를 **확인하지 못했다** — 재시도/로그아웃만 제공한다.
  identityCheckFailed,

  /// 탈퇴 대기 중.
  withdrawalPending,
}

/// 순수 함수 — 세션 전역 상태를 읽지 않으므로 그대로 테스트할 수 있다.
/// (party_app/test/root_gate_test.dart)
RootGateScreen resolveRootGateScreen({
  required bool isLoggedIn,
  required String accountStatus,
  required IdentityStatus identityStatus,
}) {
  // 비로그인은 그대로 통과시킨다. 본인확인은 **회원**에게 요구하는 것이고,
  // 공유 링크로 들어온 사람에게 로그인부터 강요하면 파티를 볼 방법이 없다.
  // 로그인하는 순간 이 판단식이 다시 돌아 아래 분기로 들어간다.
  if (!isLoggedIn) return RootGateScreen.main;

  // 탈퇴 대기가 본인확인보다 앞이다 — 떠나기로 한 계정에게 본인확인을
  // 요구하는 것은 앞뒤가 맞지 않고, 대기 화면에는 취소·로그아웃 경로가 있다.
  if (accountStatus == 'withdrawal_pending') {
    return RootGateScreen.withdrawalPending;
  }

  switch (identityStatus) {
    case IdentityStatus.verified:
      return RootGateScreen.main;
    case IdentityStatus.unverified:
      return RootGateScreen.identityVerification;
    // 아직 답이 없는 구간 — 통과시키지도, 실패로 단정하지도 않는다.
    case IdentityStatus.checking:
      return RootGateScreen.checking;
    // 확인하지 못한 상태를 통과시키지 않는다(fail-closed). 예전에는 여기서
    // 통과시켰는데, 그러면 네트워크가 막힌 기기에서 미인증 계정이 그대로
    // 들어왔다. 대신 **가두지도 않는다** — 확인 실패 화면이 재시도와
    // 로그아웃을 함께 주므로, 인증을 마친 사용자는 다시 시도해서 들어온다.
    case IdentityStatus.unknown:
      return RootGateScreen.identityCheckFailed;
  }
}

/// 지금 세션 기준의 판정.
RootGateScreen currentRootGateScreen() => resolveRootGateScreen(
  isLoggedIn: UserSession.isLoggedIn,
  accountStatus: UserSession.accountStatus,
  identityStatus: UserSession.identityStatus,
);

/// 게이트가 지금 서비스 화면을 막고 있는가.
///
/// 딥링크와 푸시는 루트 게이트를 거치지 않고 전역 네비게이터에 화면을 **쌓기**
/// 때문에, 이걸 보지 않으면 본인확인 화면 위로 파티 상세가 올라가 게이트가
/// 그대로 무력화된다. 두 서비스가 이동 직전에 이 값을 확인한다.
bool get rootGateBlocksService =>
    currentRootGateScreen() != RootGateScreen.main;

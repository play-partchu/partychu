import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Apple App Review 심사관용 로그인 경로 — **iOS 전용**.
///
/// ── 왜 필요한가 ──────────────────────────────────────────────────────────
/// 파티츄는 "1명 = 계정 1개"를 NICE 본인확인(한국 통신사 휴대폰 인증)으로
/// 지킨다. 그래서 심사관이 자기 Apple ID로 로그인하면 미인증 상태가 되고,
/// 루트 게이트가 본인확인 화면에 세운다([resolveRootGateScreen]) — 해외
/// 심사관은 그 인증을 **통과할 방법이 없다.** 앱에 들어갈 길이 없으니 심사가
/// 불가능하다.
///
/// 이미 본인확인을 마친 상태로 세팅된 심사용 계정이 있다(Firestore
/// `users/{uid}.identityVerified == true`). 문제는 그 계정으로 들어갈 입구가
/// `kDebugMode` 블록 안에만 있어서 **App Store 빌드에는 존재하지 않았다**는
/// 것이다. 이 파일이 그 입구를 Release iOS에 연다.
///
/// ── 열어 주는 것과 열지 않는 것 ──────────────────────────────────────────
/// 여는 것은 **로그인 입구 하나**뿐이다. 본인확인 판정은 손대지 않는다 —
/// 로그인 뒤에도 세션은 평소처럼 서버의 `users/{uid}`를 읽어
/// `identityVerified`를 확정하고([UserSession.resolveIdentityVerified]),
/// 루트 게이트가 그 값으로 화면을 고른다. 심사용 계정이 메인으로 들어가는
/// 것은 **그 문서가 실제로 인증 완료이기 때문**이고, 클라이언트가 상태를
/// 조작해서가 아니다. 미인증 계정을 이 경로로 넣어도 똑같이 본인확인 화면에
/// 선다.
///
/// ── 일반 이메일 로그인이 아니다 ──────────────────────────────────────────
/// [allowedEmails]에 적힌 주소만 통과시킨다. 이 입구가 "아무 이메일로나
/// 가입·로그인하는 기능"으로 자라면, 소셜 로그인만으로 1인 1계정을 지키던
/// 구조에 우회로가 생긴다.
///
/// ⚠️ **비밀번호는 여기에 없다.** 심사관이 직접 입력하고 Firebase Auth가
///    검증한다. 저장소·앱 바이너리 어디에도 심사 계정 비밀번호를 넣지 않는다
///    (비밀번호는 `functions/scripts/createTestAccounts.js`가 환경변수로
///    받는다).
class AppReviewLogin {
  AppReviewLogin._();

  /// 이 입구를 열어도 되는 플랫폼인가 — iOS만.
  ///
  /// Android·웹은 그대로 둔다. 이 입구는 **Apple 심사**를 위한 것이고,
  /// 다른 플랫폼에 같은 우회로를 늘릴 이유가 없다(Android 개발용 입구는
  /// 예전부터 `kDebugMode` 블록에 따로 있다).
  static bool get isAvailable =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// 이 경로로 로그인할 수 있는 **이메일 주소**(비밀번호 아님).
  ///
  /// 심사용 계정의 역할:
  ///   · `host@test.com`  — 호스트/주최자(파티·플레이스·장소대여 등록)
  ///   · `guest@test.com` — 참가자(신청·예약)
  ///
  /// 두 계정 모두 `users/{uid}`가 본인확인 완료로 세팅돼 있다
  /// (`functions/scripts/createTestAccounts.js`).
  static const Set<String> allowedEmails = {'host@test.com', 'guest@test.com'};

  /// 입력한 이메일을 비교 가능한 형태로 — 앞뒤 공백과 대소문자 차이로
  /// 심사관이 막히지 않게 한다(키보드가 첫 글자를 대문자로 올리는 일이 흔하다).
  static String normalizeEmail(String raw) => raw.trim().toLowerCase();

  /// 허용된 심사용 계정인가.
  static bool isAllowedEmail(String raw) =>
      allowedEmails.contains(normalizeEmail(raw));
}

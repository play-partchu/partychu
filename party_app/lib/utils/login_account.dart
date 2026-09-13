import 'package:firebase_auth/firebase_auth.dart';
import 'package:party_app/utils/user_session.dart';

/// 마이페이지 "로그인 계정"에 보여줄 로그인 수단.
enum LoginProvider {
  google('Google'),
  kakao('카카오'),
  naver('네이버'),
  // Debug 전용 QA 이메일 로그인(login.dart) — 운영 가입 경로는 아니다.
  email('이메일');

  const LoginProvider(this.label);

  final String label;
}

/// 사용자에게 보여줘도 되는 로그인 계정 정보 — **제공자 이름과 이메일뿐이다.**
///
/// Firebase UID, 카카오·네이버의 내부 id, 토큰은 여기에 담지 않는다.
/// 담지 않으면 화면이 실수로 그릴 수도 없다.
class LoginAccount {
  const LoginAccount({required this.provider, this.email = ''});

  final LoginProvider provider;

  /// 비어 있을 수 있다 — 소셜 쪽에서 이메일 제공에 동의하지 않은 경우.
  final String email;

  bool get hasEmail => email.isNotEmpty;

  /// 이메일이 없을 때 대신 쓰는 문구.
  String get signedInText => '${provider.label} 계정으로 로그인됨';
}

/// 로그인 수단과 이메일을 판정한다. 순수 함수라 입력만으로 결과가 정해진다.
///
/// ── 제공자 판정 순서 ─────────────────────────────────────────────────────
///  1. uid 접두어 `kakao:` / `naver:` — functions/socialAuth.js가 커스텀 토큰
///     계정을 이 형태로만 만든다. 커스텀 토큰 로그인은 Firebase providerData에
///     제공자가 남지 않아서, 이게 가장 확실한 근거다.
///  2. providerData의 `google.com` — Firebase가 직접 붙이는 값.
///  3. users 문서의 `signupProvider` — 앱이 최초 로그인 때 한 번 기록한다
///     (login.dart). 도입 이전 가입자에게는 없어서 폴백으로만 쓴다.
///  4. providerData의 `password` — 이메일 로그인.
///
/// ── 이메일 ───────────────────────────────────────────────────────────────
/// 카카오·네이버: users.socialAccount.email → Auth email → users.email.
///   socialAccount는 서버가 **매 로그인마다** 소셜 프로필에서 받아 쓴다
///   (socialAuth.js). Auth email은 계정 생성 때 한 번만 들어가서 기존 가입자는
///   비어 있다. 네이버는 로그인 아이디를 API로 주지 않아 이메일이 식별값이다.
///   socialAccount는 판정한 제공자와 같을 때만 믿는다.
/// Google·이메일: Auth email → providerData email → users.email.
/// `@`가 없는 값은 이메일로 보지 않는다.
LoginAccount? resolveLoginAccount({
  required String uid,
  List<String> providerIds = const [],
  String authEmail = '',
  List<String> providerEmails = const [],
  String signupProvider = '',
  String storedEmail = '',
  String socialAccountProvider = '',
  String socialAccountEmail = '',
}) {
  if (uid.isEmpty) return null;

  final LoginProvider? provider;
  if (uid.startsWith('kakao:')) {
    provider = LoginProvider.kakao;
  } else if (uid.startsWith('naver:')) {
    provider = LoginProvider.naver;
  } else if (providerIds.contains('google.com')) {
    provider = LoginProvider.google;
  } else if (signupProvider == 'google') {
    provider = LoginProvider.google;
  } else if (signupProvider == 'kakao') {
    provider = LoginProvider.kakao;
  } else if (signupProvider == 'naver') {
    provider = LoginProvider.naver;
  } else if (providerIds.contains('password')) {
    provider = LoginProvider.email;
  } else {
    provider = null;
  }
  if (provider == null) return null;

  final candidates = switch (provider) {
    LoginProvider.kakao || LoginProvider.naver => [
      if (socialAccountProvider == provider.name) socialAccountEmail,
      authEmail,
      ...providerEmails,
      storedEmail,
    ],
    LoginProvider.google ||
    LoginProvider.email => [authEmail, ...providerEmails, storedEmail],
  };
  final email = candidates
      .map((e) => e.trim())
      .firstWhere((e) => e.contains('@'), orElse: () => '');

  return LoginAccount(provider: provider, email: email);
}

/// 지금 로그인한 계정 — 로그아웃 상태이거나 수단을 알 수 없으면 null.
LoginAccount? currentLoginAccount() {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;
  return resolveLoginAccount(
    uid: user.uid,
    providerIds: [for (final p in user.providerData) p.providerId],
    authEmail: user.email ?? '',
    providerEmails: [
      for (final p in user.providerData)
        if (p.email != null) p.email!,
    ],
    signupProvider: UserSession.signupProvider,
    storedEmail: UserSession.accountEmail,
    socialAccountProvider: UserSession.socialAccountProvider,
    socialAccountEmail: UserSession.socialAccountEmail,
  );
}

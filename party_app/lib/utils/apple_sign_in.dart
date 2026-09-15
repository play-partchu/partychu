import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Sign in with Apple — **iOS 전용**.
///
/// App Store 심사 4.8: 구글·카카오·네이버 같은 서드파티 로그인을 제공하면
/// 동등한 선택지로 Sign in with Apple을 함께 제공해야 한다.
///
/// ── 왜 별도 패키지를 쓰지 않는가 ────────────────────────────────────────
/// 이미 쓰는 firebase_auth(5.7.0)가 iOS에서 `signInWithProvider(AppleAuthProvider)`를
/// 네이티브(ASAuthorizationController)로 처리한다. sign_in_with_apple 같은
/// 플러그인을 더하면 Android·웹 빌드에도 코드가 들어가므로, 이 경로를 쓰고
/// 버튼·호출은 [isAvailable]로 iOS에서만 연다.
///
/// ── nonce ────────────────────────────────────────────────────────────────
/// 플러그인(FLTFirebaseAuthPlugin.m `launchAppleSignInRequest`)이 매 요청마다
/// 32자 무작위 nonce를 만들어 **SHA256 해시를 Apple 요청에 싣고**, 응답의
/// idToken과 **원문 nonce**로 `appleCredentialWithIDToken:rawNonce:fullName:`
/// 자격증명을 만들어 Firebase에 로그인한다. 토큰 재사용(replay)을 Firebase가
/// 거부하는 표준 방식이고, 앱 코드가 nonce를 직접 다루지 않으니 실수할 틈도 없다.
///
/// ── 이름·이메일 ──────────────────────────────────────────────────────────
/// Apple은 이름을 **최초 1회만** 준다. 이 앱은 Firebase displayName을 쓰지
/// 않는다(실명은 NICE 본인확인, 표시명은 닉네임) — 재로그인 때 이름이 없어도
/// 영향이 없다. "나의 이메일 가리기"를 고르면 `…@privaterelay.appleid.com`이
/// Auth 이메일이 되고, onUserCreated가 그대로 users.email에 복사한다.
///
/// ── 탈퇴 시 토큰 폐기 ───────────────────────────────────────────────────
/// App Review 5.1.1(v): Apple로 가입한 계정을 삭제할 때 Apple 토큰을 폐기해야
/// 한다. 폐기에는 **방금 받은** authorization code가 필요해서(유효 5분), 탈퇴
/// 직전에 Apple로 재인증해 새 코드를 받는다([revokeForAccountDeletion]).
class AppleSignIn {
  AppleSignIn._();

  static const providerId = 'apple.com';

  /// Apple 로그인 버튼·호출을 열어도 되는 플랫폼인가.
  static bool get isAvailable =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static AppleAuthProvider _provider() =>
      AppleAuthProvider()
        ..addScope('email')
        ..addScope('name');

  /// Apple 네이티브 창을 띄우고 Firebase에 로그인한다.
  static Future<UserCredential> signIn() =>
      FirebaseAuth.instance.signInWithProvider(_provider());

  /// 이 계정이 Apple로 로그인한 계정인가.
  static bool usesApple(User? user) =>
      user?.providerData.any((p) => p.providerId == providerId) ?? false;

  /// 사용자가 Apple 창을 스스로 닫았는가 — 실패 문구를 띄우지 않는다.
  /// (플러그인이 ASAuthorizationErrorCanceled를 'canceled'로 넘긴다.)
  static bool isCancellation(Object error) =>
      error is FirebaseAuthException &&
      (error.code == 'canceled' || error.code == 'web-context-canceled');

  /// 탈퇴 전 Apple 토큰 폐기 — 재인증으로 새 authorization code를 받아 폐기한다.
  ///
  /// 실패하면 예외를 그대로 던진다. 호출부는 **탈퇴 신청을 보내지 않고**
  /// 다시 시도하도록 안내해야 한다.
  static Future<void> revokeForAccountDeletion() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: '로그인 상태가 아닙니다.',
      );
    }
    final credential = await user.reauthenticateWithProvider(_provider());
    final code = credential.additionalUserInfo?.authorizationCode;
    if (code == null || code.isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-authorization-code',
        message: 'Apple 인증 코드를 받지 못했습니다.',
      );
    }
    await FirebaseAuth.instance.revokeTokenWithAuthorizationCode(code);
  }
}

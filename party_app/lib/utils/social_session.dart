import 'package:flutter/foundation.dart'
    show debugPrint, defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_naver_login/flutter_naver_login.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 소셜 로그인 SDK 쪽 세션 정리와 "다음 로그인은 계정 선택부터" 표시.
///
/// `FirebaseAuth.signOut()`은 Firebase 세션만 끊는다. 구글/카카오/네이버 SDK는
/// 마지막에 로그인한 계정과 토큰을 각자 따로 들고 있어서, 그걸 그대로 두면
/// 다음 로그인 때 계정 선택 화면 없이 직전 계정으로 곧장 다시 로그인된다.
///
/// 여기 있는 정리 작업은 **사용자가 직접 로그아웃했을 때만** 실행된다. 앱을
/// 재실행하는 것만으로는 아무것도 지워지지 않으므로, 로그아웃하지 않은
/// 사용자의 로그인 유지에는 영향이 없다.
class SocialSession {
  /// iOS에서 구글 SDK가 쓸 OAuth 클라이언트 ID.
  ///
  /// iOS 플러그인은 `GoogleService-Info.plist`의 `CLIENT_ID`를 읽거나, 없으면
  /// 여기서 넘긴 값을 쓴다. **둘 다 없으면 GIDSignIn이 NSException을 던지고
  /// 플러그인이 그것을 그대로 다시 raise 해서 앱이 죽는다**
  /// (FLTGoogleSignInPlugin.m:169-171) — Dart의 try/catch로는 못 막는다.
  /// 그래서 부르기 전에 [googleReady]로 미리 확인한다.
  /// `.env`가 1순위, `firebase_options.dart`의 `iosClientId`가 2순위다.
  /// 후자는 `GoogleService-Info.plist`를 넣고 `flutterfire configure`를 다시
  /// 돌리면 자동으로 채워진다 — 그때 .env를 비워 둬도 막히지 않게 하려고
  /// 함께 본다.
  static String get _iosClientId {
    final fromEnv = (dotenv.env['GOOGLE_IOS_CLIENT_ID'] ?? '').trim();
    if (fromEnv.isNotEmpty) return fromEnv;
    try {
      return (Firebase.app().options.iosClientId ?? '').trim();
    } catch (e) {
      // Firebase 초기화 전에 불릴 일은 없지만, 여기서 던지면 로그인 화면이
      // 통째로 죽는다 — 없는 것으로 보고 넘어간다.
      debugPrint('[SocialSession] Firebase iosClientId 조회 실패: $e');
      return '';
    }
  }

  static bool get _isApple =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// 지금 플랫폼에서 구글 로그인을 부를 수 있는가.
  ///
  /// iOS는 plist나 .env 중 하나로 클라이언트 ID가 있어야 한다. 확인 없이
  /// 부르면 실패가 아니라 **크래시**라, 버튼을 누른 사람에게 안내조차 못 준다.
  /// plist가 번들에 들어 있으면 .env가 비어 있어도 정상이므로, 여기서는
  /// .env만으로 단정하지 않고 [googleClientIdMissing]으로 나눠 본다.
  static bool get googleClientIdMissing => _isApple && _iosClientId.isEmpty;

  /// 구글 SDK 인스턴스 — 로그인(login.dart)과 로그아웃이 같은 객체를 쓰도록
  /// 여기서 하나만 만들어 공유한다.
  ///
  /// iOS에서만 clientId를 넘긴다. 안드로이드는 google-services.json의
  /// 서명 기반 클라이언트를 쓰고, 웹은 index.html의 meta 태그를 쓴다 —
  /// 그쪽에 iOS용 ID를 넘기면 오히려 어긋난다.
  static final GoogleSignIn google = GoogleSignIn(
    clientId: _isApple && _iosClientId.isNotEmpty ? _iosClientId : null,
  );

  static const _prefsKeyChooseAccount = 'social_choose_account_next_login';

  /// 정리 호출 하나가 응답을 오래 끌어도 로그아웃 자체는 바로 끝나야 한다.
  /// 실패하거나 시간이 초과돼도 아래 표시가 남아 다음 로그인에서 다시 정리된다.
  static const _timeout = Duration(seconds: 3);

  /// 사용자가 직접 로그아웃했을 때 각 소셜 SDK의 로그인 세션을 끊는다.
  /// 전부 best-effort — 하나가 실패해도 나머지는 계속 정리한다.
  static Future<void> signOutAll() async {
    // 표시부터 남긴다 — 아래 정리가 네트워크 문제로 실패하거나 도중에 앱이
    // 종료돼도, 다음 로그인은 계정 선택부터 시작한다.
    await setChooseAccountNextLogin(true);

    // 구글: 캐시된 "직전 로그인 계정"을 비운다. 이걸 안 하면 다음 signIn()이
    // 계정 선택 화면 없이 그 계정으로 조용히 성공한다.
    await _guard('google', () => google.signOut());

    // 카카오: SDK가 보관 중인 액세스/리프레시 토큰을 만료시킨다.
    await _guard('kakao', () => UserApi.instance.logout());

    // 네이버: 네이티브 전용 플러그인이라 웹에서는 호출 자체가 없다.
    if (!kIsWeb) {
      await _guard('naver', () => FlutterNaverLogin.logOutAndDeleteToken());
    }
  }

  /// 직전에 사용자가 명시적으로 로그아웃했는지 — 그렇다면 이번 로그인은
  /// 계정을 다시 고를 수 있어야 한다. 로그인에 성공하면
  /// [setChooseAccountNextLogin]`(false)`로 지운다.
  static Future<bool> shouldChooseAccount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKeyChooseAccount) ?? false;
  }

  static Future<void> setChooseAccountNextLogin(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value) {
      await prefs.setBool(_prefsKeyChooseAccount, true);
    } else {
      await prefs.remove(_prefsKeyChooseAccount);
    }
  }

  static Future<void> _guard(
    String tag,
    Future<Object?> Function() action,
  ) async {
    try {
      await action().timeout(_timeout);
    } catch (e) {
      // 이미 로그아웃 상태(토큰 없음)이거나 네트워크 실패 — 어느 쪽도
      // 로그아웃을 막을 이유는 아니다.
      debugPrint('[SocialSession] $tag 세션 정리 실패(무시): $e');
    }
  }
}

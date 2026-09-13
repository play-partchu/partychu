import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MissingPluginException, SystemUiOverlayStyle;
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:flutter_naver_login/flutter_naver_login.dart';
import 'package:flutter_naver_login/interface/types/naver_login_result.dart';
import 'package:flutter_naver_login/interface/types/naver_login_status.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/utils/last_login_method.dart';
import 'package:party_app/utils/social_session.dart';
import 'package:party_app/utils/root_gate.dart' show socialLoginTestMode;
import 'package:party_app/services/push_notification_service.dart';

// Firebase Functions 리전 (functions/index.js의 region과 일치해야 함)
const _functionsRegion = 'asia-northeast3';

// 화면 배경 — login.png 자체의 배경 픽셀 색(연핑크)과 동일한 값을 그대로
// 써서, 정사각 이미지를 그대로 얹어도 이미지 가장자리가 화면과 이어져
// 보이게 한다(별도 흰 박스/그라데이션 없이 단색 한 장). 상태바/하단
// 시스템 영역도 같은 색으로 자연스럽게 이어지도록 AnnotatedRegion에도
// 그대로 재사용한다.
const _kBgColor = Color(0xFFFFE0EA);

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  LastLoginMethod? _lastMethod;

  late final TapGestureRecognizer _termsRecognizer = TapGestureRecognizer()
    ..onTap = () => _openLegalUrl('terms.html');
  late final TapGestureRecognizer _privacyRecognizer = TapGestureRecognizer()
    ..onTap = () => _openLegalUrl('privacy.html');

  @override
  void initState() {
    super.initState();
    LastLoginMethod.load().then((method) {
      if (mounted) setState(() => _lastMethod = method);
    });
  }

  @override
  void dispose() {
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    super.dispose();
  }

  // 관리자 웹 "가입 경로" 통계용 — 최초 로그인 시점에 어떤 소셜 버튼을
  // 눌렀는지는 클라이언트만 알 수 있어(카카오/네이버는 커스텀 토큰이라
  // Firebase Auth의 providerData에도 안 남는다) 여기서 직접 기록한다.
  // firestore.rules가 이 필드를 "값이 아직 없을 때 정해진 값 중 하나로
  // 딱 한 번만" 쓰도록 막아두므로, 두 번째 로그인부터는 규칙이 조용히 막고
  // 이 catch가 그 실패를 무시한다 — 재작성 방지 로직을 클라이언트에 또
  // 두지 않아도 된다.
  Future<void> _recordSignupProviderOnce(String provider) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'signupProvider': provider,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[Login] signupProvider 기록 생략(이미 기록됨 등): $e');
    }
  }

  // 관리자 웹 "최근 로그인일" 통계용 — 세션 복원(앱 재실행) 시에도 갱신되는
  // 기존 UserSession.loadFromFirestore()의 lastActiveAt과 달리, 이 함수는
  // 실제로 로그인 버튼을 눌러 성공했을 때(_onLoginSuccess)만 호출된다.
  // 실패해도 로그인 자체를 막지 않는다.
  Future<void> _recordLogin() async {
    try {
      await FirebaseFunctions.instanceFor(
        region: _functionsRegion,
      ).httpsCallable('recordLogin').call();
    } catch (e) {
      debugPrint('[Login] recordLogin 호출 실패(non-fatal): $e');
    }
  }

  /// 소셜 로그인 성공 후 공통 처리.
  /// Firestore 로드 실패는 로그인 자체를 막지 않는다.
  Future<void> _onLoginSuccess(BuildContext context, {String? provider}) async {
    debugPrint('[Login] _onLoginSuccess uid=${UserSession.userId}');

    // 계정 선택을 강제하는 표시는 "명시적 로그아웃 후 첫 로그인" 한 번만
    // 쓰고 지운다. 다음부터는 각 SDK의 평소 흐름 그대로 로그인한다.
    await SocialSession.setChooseAccountNextLogin(false);

    unawaited(_recordLogin());

    // 이 기기를 이 계정의 푸시 대상으로 등록한다. 권한이 아직 없으면 아무것도
    // 하지 않으므로(PushNotificationService.registerForUser) 여기서 권한
    // 팝업이 뜨지는 않는다 — 알림 권한은 "왜 필요한지 아는 시점"에 따로
    // 요청한다. 등록 실패가 로그인을 막지 않도록 기다리지 않는다.
    unawaited(PushNotificationService.registerForUser());

    // 서버(users/{uid})를 실제로 읽어 세션의 본인확인 상태를 확정해 둔다.
    //
    // **여기서는 화면을 고르지 않는다.** 예전에는 이 자리에서 미인증이면
    // 본인확인 화면으로 갈아치웠는데, 그 화면은 뒤로가기로 닫혔고 앱을 다시
    // 켜면 아무도 다시 묻지 않았다. 이제 첫 화면을 고르는 곳은 루트 게이트
    // 하나뿐이다(main.dart의 _AuthGate · utils/root_gate.dart) — 이 읽기가
    // 끝나 세션 상태가 바뀌면 게이트가 스스로 다시 평가한다.
    //
    // 그래서 이 함수가 할 일은 **로그인 화면을 닫는 것뿐**이다. 미인증이든
    // 확인 실패든, 게이트가 그 아래에서 이미 알맞은 화면으로 바뀌어 있다.
    final verified = await UserSession.resolveIdentityVerified(force: true);
    debugPrint('[Login] identityVerified=$verified (null=확인 실패)');

    // 가입 경로 기록은 **프로필을 다 읽은 뒤**에 한다.
    //
    // 이 쓰기는 users/{uid}에 대한 merge라 Firestore가 로컬 캐시에 곧바로
    // 반영한다 — 읽기보다 먼저 나가면 캐시에 `signupProvider`만 든 문서가
    // 생긴다. 그 상태에서 서버 읽기가 실패해 캐시 폴백을 타면
    // (_loadOnce의 마지막 시도) "문서는 있는데 identityVerified가 없다"가 되어
    // **인증을 마친 계정이 미인증처럼 읽힌다.** 순서를 뒤로 미루는 것만으로
    // 그 오염 경로가 사라진다.
    //
    // 통계용이라 실패해도 로그인을 막지 않는다.
    if (provider != null) unawaited(_recordSignupProviderOnce(provider));

    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  // ─── Google ──────────────────────────────────────────────────────────────
  Future<void> signInWithGoogle(BuildContext context) async {
    // iOS는 클라이언트 ID가 없으면 로그인이 "실패"하지 않고 **앱이 죽는다** —
    // GIDSignIn이 던진 NSException을 플러그인이 그대로 다시 raise 하기
    // 때문에(FLTGoogleSignInPlugin.m:169-171) Dart의 catch까지 오지 않는다.
    // 그래서 부르기 전에 막는다.
    if (SocialSession.googleClientIdMissing) {
      debugPrint(
        '[Login] Google 설정 없음 — GoogleService-Info.plist가 번들에 없고 '
        '.env의 GOOGLE_IOS_CLIENT_ID도 비어 있다. signIn()을 부르면 크래시한다.',
      );
      _showError(context, '구글 로그인 설정이 준비되지 않았습니다. 다른 방법으로 로그인해주세요.');
      return;
    }
    try {
      // 명시적으로 로그아웃한 뒤의 첫 로그인이면 SDK에 캐시된 직전 계정을 한 번
      // 더 비운다 — 로그아웃 당시 정리가 실패했더라도(오프라인 등) 여기서
      // 계정 선택 화면이 뜨도록 보장한다.
      if (await SocialSession.shouldChooseAccount()) {
        try {
          await SocialSession.google.signOut();
        } catch (e) {
          debugPrint('[Login] Google 이전 세션 정리 실패(무시): $e');
        }
      }

      final googleUser = await SocialSession.google.signIn();
      if (googleUser == null) {
        debugPrint('[Login] Google signIn cancelled by user');
        return;
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);

      final uid = FirebaseAuth.instance.currentUser?.uid;
      debugPrint('[Login] Google signIn done. uid=$uid');
      if (uid == null) {
        if (context.mounted) _showError(context, '구글 로그인에 실패했습니다.');
        return;
      }
      UserSession.beginSession(uid);
      await LastLoginMethod.google.save();

      if (context.mounted) await _onLoginSuccess(context, provider: 'google');
    } on FirebaseAuthException catch (error, st) {
      // 같은 이메일이 이미 다른 로그인 수단의 계정에 묶여 있으면 Firebase가
      // account-exists-with-different-credential로 거부한다. 여기서 계정을
      // **자동으로 합치거나 지우지 않는다** — 그러면 기존 계정의 제공자 연결이
      // 바뀌어 운영 계정이 망가질 수 있다. 원인만 드러낸다.
      debugPrint(
        '[Login] Google FirebaseAuth 실패 code=${error.code} '
        'email=${error.email} provider=${error.credential?.providerId} '
        'message=${error.message}\n$st',
      );
      if (context.mounted) {
        _showError(
          context,
          socialLoginTestMode
              ? '구글 로그인에 실패했습니다. (${error.code})'
              : '구글 로그인에 실패했습니다.',
        );
      }
    } catch (error, st) {
      debugPrint('[Login] Google error: $error\n$st');
      if (context.mounted) _showError(context, '구글 로그인에 실패했습니다.');
    }
  }

  // ─── Kakao ───────────────────────────────────────────────────────────────
  Future<void> signInWithKakao(BuildContext context) async {
    try {
      // 카카오톡 앱으로 로그인하면 계정이 그 앱에 로그인된 계정으로 고정된다
      // (카카오가 계정 선택 화면을 제공하지 않는다). 그래서 명시적 로그아웃
      // 직후 한 번은 카카오계정 로그인으로 돌리고 prompt=select_account를 붙여
      // 계정을 다시 고를 수 있게 한다. 평소(설치+미로그아웃)에는 기존처럼
      // 카카오톡 로그인을 그대로 쓴다.
      //
      // 웹에는 "카카오톡 앱 설치 여부" 개념이 없다 — 항상 계정 로그인(웹은
      // SDK가 내부적으로 팝업 창을 띄워 처리)으로 진행한다.
      final chooseAccount = await SocialSession.shouldChooseAccount();
      OAuthToken token;
      if (!kIsWeb && !chooseAccount && await isKakaoTalkInstalled()) {
        token = await UserApi.instance.loginWithKakaoTalk();
      } else {
        token = await UserApi.instance.loginWithKakaoAccount(
          prompts: chooseAccount ? const [Prompt.selectAccount] : null,
        );
      }
      debugPrint('[Login] Kakao token acquired');

      final callable = FirebaseFunctions.instanceFor(
        region: _functionsRegion,
      ).httpsCallable('kakaoCustomToken');
      final result = await callable.call({'token': token.accessToken});
      final customToken = result.data['customToken'] as String;
      debugPrint('[Login] Kakao customToken acquired');

      await FirebaseAuth.instance.signInWithCustomToken(customToken);

      final uid = FirebaseAuth.instance.currentUser?.uid;
      debugPrint('[Login] Kakao signIn done. uid=$uid');
      if (uid == null) {
        if (context.mounted) _showError(context, '카카오 로그인에 실패했습니다.');
        return;
      }
      UserSession.beginSession(uid);
      await LastLoginMethod.kakao.save();

      if (context.mounted) await _onLoginSuccess(context, provider: 'kakao');
    } catch (error, st) {
      debugPrint('[Login] Kakao error: $error\n$st');
      if (context.mounted) _showError(context, '카카오 로그인에 실패했습니다.');
    }
  }

  /// 네이버 로그인이 **사용자 취소**로 끝났는가.
  ///
  /// flutter_naver_login의 상태값은 `loggedIn / loggedOut / error` 셋뿐이고
  /// 취소 전용 값이 없다. 취소는 두 모양으로 온다:
  ///   · `loggedOut`  — 로그인하지 않은 채 돌아왔다(뒤로가기 등)
  ///   · `error` + 메시지에 취소 표시(SDK가 네이버가 준 문구를 그대로 싣는다)
  /// 둘 다 사용자의 선택이므로 실패 문구를 띄우지 않는다.
  bool _naverUserCancelled(NaverLoginResult result) {
    if (result.status == NaverLoginStatus.loggedOut) return true;
    final message = (result.errorMessage ?? '').toLowerCase();
    return message.contains('cancel') || message.contains('취소');
  }

  // ─── Naver ───────────────────────────────────────────────────────────────
  // flutter_naver_login은 Android/iOS 전용 네이티브 플러그인 — 웹 구현이
  // 없다. 웹에서는 버튼 자체를 숨기지만(build() 참고), 방어적으로 한 번 더 막는다.
  Future<void> signInWithNaver(BuildContext context) async {
    if (kIsWeb) {
      _showError(context, '네이버 로그인은 아직 웹에서 지원하지 않습니다. 모바일 앱을 이용해주세요.');
      return;
    }
    try {
      // 네이버 SDK에는 구글/카카오 같은 "계정 선택 강제" 옵션이 없다. 명시적
      // 로그아웃 직후라면 SDK에 남은 토큰을 한 번 더 비워, 저장된 토큰으로
      // 조용히 재로그인되지 않고 네이버 로그인 화면을 거치게 하는 것까지가
      // 할 수 있는 전부다(네이버 앱/브라우저에 로그인 세션이 남아 있으면
      // 그 화면에서 계정이 이미 선택돼 있을 수 있다).
      if (await SocialSession.shouldChooseAccount()) {
        try {
          await FlutterNaverLogin.logOut();
        } catch (e) {
          debugPrint('[Login] Naver 이전 세션 정리 실패(무시): $e');
        }
      }

      final loginResult = await FlutterNaverLogin.logIn();
      if (loginResult.status != NaverLoginStatus.loggedIn) {
        // errorMessage까지 남긴다 — status만 찍으면 'error' 한 단어뿐이라
        // 무엇이 잘못됐는지 로그에서도 사라진다(이번 릴리즈 장애를 진단할 때
        // 실제로 여기서 막혔다).
        debugPrint(
          '[Login] Naver logIn 실패. status=${loginResult.status} '
          'errorMessage=${loginResult.errorMessage}',
        );
        // 사용자가 스스로 취소한 것은 실패가 아니다 — 구글(signIn()==null)·
        // 카카오와 같이 조용히 끝낸다. 취소에 실패 문구를 띄우면 뒤로가기를
        // 누른 사람에게 매번 오류가 뜬다.
        if (_naverUserCancelled(loginResult)) return;
        if (context.mounted) {
          _showError(context, '네이버 로그인에 실패했습니다. 다시 시도해주세요.');
        }
        return;
      }

      final tokenResult = await FlutterNaverLogin.getCurrentAccessToken();
      debugPrint(
        '[Login] Naver token acquired. empty=${tokenResult.accessToken.isEmpty}',
      );

      final callable = FirebaseFunctions.instanceFor(
        region: _functionsRegion,
      ).httpsCallable('naverCustomToken');
      final result = await callable.call({'token': tokenResult.accessToken});
      final customToken = result.data['customToken'] as String;
      debugPrint('[Login] Naver customToken acquired');

      await FirebaseAuth.instance.signInWithCustomToken(customToken);

      final uid = FirebaseAuth.instance.currentUser?.uid;
      debugPrint('[Login] Naver signIn done. uid=$uid');
      if (uid == null) {
        if (context.mounted) _showError(context, '네이버 로그인에 실패했습니다.');
        return;
      }
      UserSession.beginSession(uid);
      await LastLoginMethod.naver.save();

      if (context.mounted) await _onLoginSuccess(context, provider: 'naver');
    } on MissingPluginException catch (error) {
      // iOS 플러그인은 Info.plist의 NidClientID/NidClientSecret/NidAppName/
      // NidUrlScheme 중 하나라도 없으면 **메서드 채널 자체를 등록하지 않는다**
      // (FlutterNaverLoginPlugin.swift:110-116). 그래서 로그인 실패가 아니라
      // "그런 메서드 없음"으로 온다 — 원인이 전혀 다르므로 갈라서 남긴다.
      debugPrint(
        '[Login] Naver 플러그인 미등록: $error\n'
        '  → iOS Info.plist의 Nid* 네 키를 확인할 것.',
      );
      if (context.mounted) {
        _showError(context, '네이버 로그인 설정이 준비되지 않았습니다. 다른 방법으로 로그인해주세요.');
      }
    } catch (error, st) {
      debugPrint('[Login] Naver error(${error.runtimeType}): $error\n$st');
      if (context.mounted) _showError(context, '네이버 로그인에 실패했습니다.');
    }
  }

  // ─── 이메일/비밀번호 (Debug 전용 QA 테스트 로그인) ─────────────────────────
  // 일반 사용자에게는 노출되지 않는다 — kDebugMode가 false인 release 빌드에는
  // 이 메서드를 호출하는 UI 자체가 트리에 포함되지 않는다(build() 참고).
  // Google/Kakao/Naver 로그인 로직에는 전혀 관여하지 않는다.
  Future<void> signInWithEmail(
    BuildContext context,
    String email,
    String password,
  ) async {
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = FirebaseAuth.instance.currentUser?.uid;
      debugPrint('[Login] Email signIn done. uid=$uid');
      if (uid == null) {
        if (context.mounted) _showError(context, '테스트 로그인에 실패했습니다.');
        return;
      }
      UserSession.beginSession(uid);

      if (context.mounted) await _onLoginSuccess(context);
    } catch (error, st) {
      debugPrint('[Login] Email error: $error\n$st');
      if (context.mounted) _showError(context, '테스트 로그인에 실패했습니다: $error');
    }
  }

  void _showDebugTestLoginSheet(BuildContext context) {
    final emailCtrl = TextEditingController(text: 'host@test.com');
    final passwordCtrl = TextEditingController(text: 'Host1234!@');

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.bug_report, color: Colors.deepOrange, size: 20),
                  SizedBox(width: 8),
                  Text(
                    '테스트 로그인 (Debug 전용)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                '이 메뉴는 release 빌드에는 표시되지 않아요.',
                style: TextStyle(fontSize: 12, color: Colors.black45),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        emailCtrl.text = 'host@test.com';
                        passwordCtrl.text = 'Host1234!@';
                      },
                      child: const Text('호스트 계정'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        emailCtrl.text = 'guest@test.com';
                        passwordCtrl.text = 'Guest1234!@';
                      },
                      child: const Text('참가자 계정'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: '이메일'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: '비밀번호'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    signInWithEmail(
                      context,
                      emailCtrl.text.trim(),
                      passwordCtrl.text,
                    );
                  },
                  child: const Text('로그인'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openLegalUrl(String path) async {
    final uri = Uri.parse('https://partychu.co.kr/$path');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[Login] $path 열기 실패: $e');
    }
  }

  // ── 소셜 로고 아이콘 ────────────────────────────────────────────────
  Widget _googleIcon() => const Text(
    'G',
    style: TextStyle(
      fontSize: 19,
      fontWeight: FontWeight.w900,
      height: 1,
      color: Color(0xFF4285F4),
    ),
  );

  Widget _kakaoIcon() =>
      const Icon(Icons.chat_bubble_rounded, size: 18, color: Colors.black);

  Widget _naverIcon() => Container(
    width: 20,
    height: 20,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(5),
    ),
    child: const Text(
      'N',
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w900,
        height: 1,
        color: Color(0xFF03C75A),
      ),
    ),
  );

  /// 소셜 로그인 버튼 하나 — 왼쪽에 서비스 로고, 가운데 라벨. [method]가 최근
  /// 사용한 로그인 방식이면 우측 상단에 "최근 사용" 배지를 얹는다.
  Widget _providerButton({
    required LastLoginMethod method,
    required VoidCallback onPressed,
    required String label,
    required Widget icon,
    required Color background,
    required Color textColor,
    Color? borderColor,
  }) {
    final isLast = _lastMethod == method;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: onPressed,
          child: Container(
            width: double.infinity,
            height: 46,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(23),
              border: borderColor != null
                  ? Border.all(color: borderColor)
                  : null,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(left: 18, child: icon),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isLast)
          Positioned(
            top: -8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0F5),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: const Text(
                '최근 사용',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFD94F7A),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _termsFooter() {
    const linkStyle = TextStyle(
      fontSize: 12,
      color: Color(0xFFD94F7A),
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationColor: Color(0xFFD94F7A),
    );
    const plainStyle = TextStyle(
      fontSize: 12,
      color: Colors.black38,
      height: 1.5,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: plainStyle,
          children: [
            const TextSpan(text: '로그인하면 '),
            TextSpan(
              text: '이용약관',
              style: linkStyle,
              recognizer: _termsRecognizer,
            ),
            const TextSpan(text: ' 및 '),
            TextSpan(
              text: '개인정보처리방침',
              style: linkStyle,
              recognizer: _privacyRecognizer,
            ),
            const TextSpan(text: '에 동의하게 됩니다.'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // 배경이 밝은 핑크라 상태바/하단 내비게이션 아이콘은 어두운 톤으로,
      // 색은 화면 배경과 이어지도록 투명/동일 색을 준다.
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: _kBgColor,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: _kBgColor,
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(color: _kBgColor),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 32,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        children: [
                          // 키보드가 없는 화면이라 콘텐츠를 정중앙보다 살짝
                          // 위로 올린다(위:아래 여백 비율 4:6).
                          const Spacer(flex: 4),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 400),
                            child: Column(
                              children: [
                                // login.png는 배경까지 포함된 정사각 일러스트가
                                // 아니라, 배경색 자체가 화면 배경(_kBgColor)과
                                // 동일해서 그대로 얹으면 별도 박스 없이 화면에
                                // 자연스럽게 녹아든다. 카드/그림자/틴트 없이
                                // 이미지 그대로 하나의 장면처럼 보여준다.
                                Image.asset(
                                  'assets/images/login.png',
                                  width: 260,
                                  fit: BoxFit.contain,
                                ),
                                const SizedBox(height: 14),
                                const Text(
                                  '파티츄에 오신 걸 환영해요 💕',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 21,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF3A2E39),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  '간편하게 로그인하고 파티를 찾아보세요',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.black45,
                                  ),
                                ),
                                const SizedBox(height: 32),
                                // 버튼 폭을 콘텐츠보다 좌우로 더 좁게 — 상단
                                // 일러스트보다 한층 아담하고 동글동글하게
                                // 보이도록 좌우를 넉넉히 들여쓴다.
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 56,
                                  ),
                                  child: Column(
                                    children: [
                                      _providerButton(
                                        method: LastLoginMethod.google,
                                        onPressed: () =>
                                            signInWithGoogle(context),
                                        label: 'Google로 계속하기',
                                        icon: _googleIcon(),
                                        background: Colors.white,
                                        textColor: const Color(0xFF3C4043),
                                        borderColor: const Color(0xFFE3E3E3),
                                      ),
                                      const SizedBox(height: 11),
                                      _providerButton(
                                        method: LastLoginMethod.kakao,
                                        onPressed: () =>
                                            signInWithKakao(context),
                                        label: '카카오로 계속하기',
                                        icon: _kakaoIcon(),
                                        background: const Color(0xFFFEE500),
                                        textColor: Colors.black,
                                      ),
                                      // 네이버 로그인 SDK는 웹 플랫폼을 지원하지
                                      // 않아 웹에서는 버튼 자체를 노출하지 않는다
                                      // (모바일에서는 그대로 노출).
                                      if (!kIsWeb) ...[
                                        const SizedBox(height: 11),
                                        _providerButton(
                                          method: LastLoginMethod.naver,
                                          onPressed: () =>
                                              signInWithNaver(context),
                                          label: '네이버로 계속하기',
                                          icon: _naverIcon(),
                                          background: const Color(0xFF03C75A),
                                          textColor: Colors.white,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 22),
                                _termsFooter(),
                                // QA 테스트 로그인 — kDebugMode가 false인
                                // release 빌드에는 이 블록 자체가 빌드되지
                                // 않아 일반 사용자에게는 절대 노출되지 않는다.
                                if (kDebugMode) ...[
                                  const SizedBox(height: 12),
                                  TextButton.icon(
                                    onPressed: () =>
                                        _showDebugTestLoginSheet(context),
                                    icon: const Icon(
                                      Icons.bug_report,
                                      size: 16,
                                      color: Colors.black38,
                                    ),
                                    label: const Text(
                                      '테스트 로그인 (Debug)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.black38,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const Spacer(flex: 6),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

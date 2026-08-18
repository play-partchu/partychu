import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:flutter_naver_login/flutter_naver_login.dart';
import 'package:flutter_naver_login/interface/types/naver_login_status.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/utils/last_login_method.dart';
import 'package:party_app/services/push_notification_service.dart';
import 'package:party_app/screens/identity_verification_screen.dart';
import 'package:party_app/widgets/web_frame.dart';

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
  final GoogleSignIn _googleSignIn = GoogleSignIn();

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
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'signupProvider': provider}, SetOptions(merge: true));
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
      await FirebaseFunctions.instanceFor(region: _functionsRegion)
          .httpsCallable('recordLogin')
          .call();
    } catch (e) {
      debugPrint('[Login] recordLogin 호출 실패(non-fatal): $e');
    }
  }

  /// 소셜 로그인 성공 후 공통 처리.
  /// Firestore 로드 실패는 로그인 자체를 막지 않는다.
  Future<void> _onLoginSuccess(BuildContext context) async {
    debugPrint('[Login] _onLoginSuccess uid=${UserSession.userId}');

    unawaited(_recordLogin());

    // 이 기기를 이 계정의 푸시 대상으로 등록한다. 권한이 아직 없으면 아무것도
    // 하지 않으므로(PushNotificationService.registerForUser) 여기서 권한
    // 팝업이 뜨지는 않는다 — 알림 권한은 "왜 필요한지 아는 시점"에 따로
    // 요청한다. 등록 실패가 로그인을 막지 않도록 기다리지 않는다.
    unawaited(PushNotificationService.registerForUser());

    try {
      await UserSession.loadFromFirestore();
      debugPrint('[Login] loadFromFirestore done. identityVerified=${UserSession.identityVerified}');
    } catch (e) {
      debugPrint('[Login] loadFromFirestore error (non-fatal): $e');
    }

    if (!context.mounted) return;

    if (!UserSession.identityVerified) {
      // 본인인증 미완료 → LoginPage를 닫고 본인확인 화면으로 대체
      // (LoginPage 뒤에는 MainScreen이 있으므로 인증 완료 후 pop 시 MainScreen으로 복귀)
      Navigator.of(context).pushReplacement(
        webFramedRoute((_) => const IdentityVerificationScreen()),
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  // ─── Google ──────────────────────────────────────────────────────────────
  Future<void> signInWithGoogle(BuildContext context) async {
    try {
      final googleUser = await _googleSignIn.signIn();
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
      UserSession.userId = uid;
      await LastLoginMethod.google.save();
      await _recordSignupProviderOnce('google');

      if (context.mounted) await _onLoginSuccess(context);
    } catch (error, st) {
      debugPrint('[Login] Google error: $error\n$st');
      if (context.mounted) _showError(context, '구글 로그인에 실패했습니다.');
    }
  }

  // ─── Kakao ───────────────────────────────────────────────────────────────
  Future<void> signInWithKakao(BuildContext context) async {
    try {
      // 웹에는 "카카오톡 앱 설치 여부" 개념이 없다 — 항상 계정 로그인(웹은
      // SDK가 내부적으로 팝업 창을 띄워 처리)으로 진행한다.
      OAuthToken token;
      if (!kIsWeb && await isKakaoTalkInstalled()) {
        token = await UserApi.instance.loginWithKakaoTalk();
      } else {
        token = await UserApi.instance.loginWithKakaoAccount();
      }
      debugPrint('[Login] Kakao token acquired');

      final callable = FirebaseFunctions.instanceFor(region: _functionsRegion)
          .httpsCallable('kakaoCustomToken');
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
      UserSession.userId = uid;
      await LastLoginMethod.kakao.save();
      await _recordSignupProviderOnce('kakao');

      if (context.mounted) await _onLoginSuccess(context);
    } catch (error, st) {
      debugPrint('[Login] Kakao error: $error\n$st');
      if (context.mounted) _showError(context, '카카오 로그인에 실패했습니다.');
    }
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
      final loginResult = await FlutterNaverLogin.logIn();
      if (loginResult.status != NaverLoginStatus.loggedIn) {
        debugPrint('[Login] Naver logIn status=${loginResult.status}');
        return;
      }

      final tokenResult = await FlutterNaverLogin.getCurrentAccessToken();
      debugPrint('[Login] Naver token acquired. empty=${tokenResult.accessToken.isEmpty}');

      final callable = FirebaseFunctions.instanceFor(region: _functionsRegion)
          .httpsCallable('naverCustomToken');
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
      UserSession.userId = uid;
      await LastLoginMethod.naver.save();
      await _recordSignupProviderOnce('naver');

      if (context.mounted) await _onLoginSuccess(context);
    } catch (error, st) {
      debugPrint('[Login] Naver error: $error\n$st');
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
      UserSession.userId = uid;

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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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

  Widget _kakaoIcon() => const Icon(
        Icons.chat_bubble_rounded,
        size: 18,
        color: Colors.black,
      );

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
              border: borderColor != null ? Border.all(color: borderColor) : null,
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
    const plainStyle = TextStyle(fontSize: 12, color: Colors.black38, height: 1.5);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: plainStyle,
          children: [
            const TextSpan(text: '로그인하면 '),
            TextSpan(text: '이용약관', style: linkStyle, recognizer: _termsRecognizer),
            const TextSpan(text: ' 및 '),
            TextSpan(text: '개인정보처리방침', style: linkStyle, recognizer: _privacyRecognizer),
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
          decoration: const BoxDecoration(
            color: _kBgColor,
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
                                  padding: const EdgeInsets.symmetric(horizontal: 56),
                                  child: Column(
                                    children: [
                                      _providerButton(
                                        method: LastLoginMethod.google,
                                        onPressed: () => signInWithGoogle(context),
                                        label: 'Google로 계속하기',
                                        icon: _googleIcon(),
                                        background: Colors.white,
                                        textColor: const Color(0xFF3C4043),
                                        borderColor: const Color(0xFFE3E3E3),
                                      ),
                                      const SizedBox(height: 11),
                                      _providerButton(
                                        method: LastLoginMethod.kakao,
                                        onPressed: () => signInWithKakao(context),
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
                                          onPressed: () => signInWithNaver(context),
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

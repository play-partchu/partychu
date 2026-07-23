import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' hide User;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'firebase_options.dart';
import 'package:party_app/admin/admin_app.dart';
import 'package:party_app/screens/main_screen.dart';
import 'package:party_app/services/analytics_service.dart';
import 'package:party_app/services/deep_link_service.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/app_update_gate.dart';

/// App Links/Universal Links/커스텀 스킴으로 들어온 파티 상세 화면을 어느
/// 화면 위에서든 push할 수 있도록 앱 전역에서 하나만 쓰는 네비게이터 키.
final navigatorKey = GlobalKey<NavigatorState>();

/// 브라우저 URL이 /admin 으로 시작하면 관리자 웹(AdminApp)을 실행한다.
/// Flutter Web 빌드에서만 의미 있는 분기 — 모바일(Uri.base.path == '/')에서는
/// 항상 false라 일반 앱만 실행된다.
bool get _isAdminRoute => kIsWeb && Uri.base.path.startsWith('/admin');

void main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // 웹에서 /#/party/{id} 대신 /party/{id} 형태의 깨끗한 URL을 쓰기 위함 —
  // SEO・공유 링크 모두 해시 없는 경로를 기대한다.
  if (kIsWeb) {
    usePathUrlStrategy();
  }

  // 관리자 웹은 Kakao/Naver SDK, 스플래시 등 모바일 전용 초기화가 필요 없어
  // Firebase만 초기화하고 곧바로 AdminApp을 실행한다.
  if (_isAdminRoute) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    runApp(const AdminApp());
    return;
  }

  // 네이티브 스플래시/카카오 네이티브 로그인/네이버 지도 SDK는 모바일 전용이다.
  // Naver Map SDK는 web 플랫폼 구현이 없어 웹에서 init을 호출하면 실패하므로
  // kIsWeb으로 분기해 건너뛴다.
  if (!kIsWeb) {
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  }

  await initializeDateFormatting('ko_KR', null);
  await dotenv.load(fileName: '.env');
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 카카오 SDK는 플랫폼별로 다른 앱 키를 쓴다 — 모바일은 네이티브 앱 키,
  // 웹은 JavaScript 키(카카오 개발자 콘솔의 "Web" 플랫폼에 도메인을 등록하고
  // 발급받아야 함). KakaoSdk.appKey getter가 kIsWeb에 따라 자동으로 골라 쓴다.
  KakaoSdk.init(
    nativeAppKey: dotenv.env['KAKAO_NATIVE_APP_KEY'] ?? '',
    javaScriptAppKey: dotenv.env['KAKAO_JAVASCRIPT_APP_KEY'] ?? '',
  );

  if (!kIsWeb) {
    await FlutterNaverMap().init(clientId: dotenv.env['NAVER_MAP_CLIENT_ID'] ?? '');
  }

  if (!kIsWeb) {
    FlutterNativeSplash.remove();
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      // 로그인 여부와 무관하게(로그인 화면이든 메인 화면이든) 앱을 켤 때마다
      // 한 번씩 최신 버전을 확인해야 하므로 최상단에서 감싼다.
      home: const AppUpdateGate(child: _AuthGate()),
    );
  }
}

/// 앱 시작 시 Firebase Auth 상태가 복원될 때까지 로딩 화면을 보여주고,
/// 완료되면 MainScreen으로 전환합니다.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _loading = true;
  // 앱이 살아있는 동안 계속 구독 — 로그인 화면에서 로그인 버튼을 누른 뒤
  // Firebase Auth 상태가 바뀌는 즉시 UserSession을 갱신해서, 이전 화면으로
  // 돌아왔을 때 뒤로 갔다 다시 들어오지 않아도 곧바로 로그인 상태가
  // 반영되게 한다(UserSession.userId setter가 revision을 올려
  // AuthRebuilder로 감싼 화면들이 자동으로 다시 그려진다).
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    _init();
    // 로그인 여부와 무관하게 파티 상세는 누구나 볼 수 있어, 로딩 화면 위에서든
    // 메인 화면 위에서든 링크가 도착하는 즉시 처리할 수 있도록 바로 등록한다.
    DeepLinkService.init(navigatorKey);
  }

  Future<void> _init() async {
    try {
      // authStateChanges().first 는 Firebase Auth가 로컬 저장소에서
      // 세션을 복원한 뒤 첫 번째 이벤트를 발행할 때 완료됩니다.
      final user = await FirebaseAuth.instance
          .authStateChanges()
          .first
          .timeout(const Duration(seconds: 5), onTimeout: () => null);

      if (user != null) {
        UserSession.userId = user.uid;
        await UserSession.loadFromFirestore();
        AnalyticsService.logEvent(AnalyticsEventType.appOpen);
      }
    } catch (_) {
      // 오류 발생 시 비로그인 상태로 MainScreen을 표시
    }
    if (mounted) setState(() => _loading = false);

    // 초기 복원이 끝난 뒤부터 계속 구독한다 — 로그인/로그아웃/토큰 만료 등
    // Firebase Auth 상태가 바뀔 때마다 UserSession을 최신으로 유지한다.
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      final uid = user?.uid ?? '';
      if (UserSession.userId == uid) return; // 로그인 화면에서 이미 반영한 경우 등 — 중복 방지
      if (uid.isEmpty) {
        UserSession.clear();
      } else {
        UserSession.userId = uid;
        try {
          await UserSession.loadFromFirestore();
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFFFF4F8),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFFF6FA0)),
        ),
      );
    }
    return const MainScreen();
  }
}

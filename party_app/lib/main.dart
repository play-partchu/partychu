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
import 'package:party_app/services/push_notification_service.dart';
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

  // 이미 로그인된 사용자의 기기를 다시 등록한다.
  //
  // 토큰 등록은 로그인 성공 시점에만 걸려 있는데, 세션이 남아 있으면 앱을
  // 다시 켜도 그 지점을 지나지 않는다. 그래서 로그인 당시 등록이 실패했다면
  // (오프라인·서버 오류) **다시 로그인하기 전까지 영영 복구되지 않는다.**
  // 여기서 한 번 더 부르면 다음 실행에서 저절로 복구된다.
  //
  // 권한이 없으면 registerForUser가 아무것도 하지 않으므로 팝업은 뜨지 않고,
  // 문서 id가 토큰이라 재등록해도 문서는 하나로 합쳐진다(lastSeenAt만 갱신).
  // await하지 않는 이유는 등록 실패나 지연이 앱 시작을 막으면 안 되기 때문.
  if (!kIsWeb && FirebaseAuth.instance.currentUser != null) {
    unawaited(PushNotificationService.registerForUser());
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
    // 푸시 수신 준비(채널 생성·포그라운드 표시·탭 이동). 링크와 같은 자리에
    // 거는 이유도 같다 — 알림을 눌러 들어온 사용자는 로그인 복원이 끝나기 전에
    // 이미 화면을 기다리고 있고, 이동은 로딩 화면 위로도 얹을 수 있어야 한다.
    // 권한을 묻지는 않는다(그건 PushPermissionGate가 맥락이 생겼을 때 한다).
    unawaited(PushNotificationService.initMessaging(navigatorKey));
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

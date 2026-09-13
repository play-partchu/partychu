import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
import 'package:party_app/services/block_service.dart';
import 'package:party_app/services/deep_link_service.dart';
import 'package:party_app/screens/identity_verification_screen.dart';
import 'package:party_app/screens/withdrawal_pending_screen.dart';
import 'package:party_app/services/account_withdrawal_service.dart';
import 'package:party_app/services/push_notification_service.dart';
import 'package:party_app/utils/root_gate.dart';
import 'package:party_app/utils/web_launch_url.dart';
import 'package:party_app/utils/web_video_hls.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/app_update_gate.dart';
import 'package:party_app/widgets/partychu_perk_plaque.dart';
import 'package:party_app/widgets/web_frame.dart';

/// App Links/Universal Links/커스텀 스킴으로 들어온 파티 상세 화면을 어느
/// 화면 위에서든 push할 수 있도록 앱 전역에서 하나만 쓰는 네비게이터 키.
final navigatorKey = GlobalKey<NavigatorState>();

/// 브라우저 URL이 /admin 으로 시작하면 관리자 웹(AdminApp)을 실행한다.
/// Flutter Web 빌드에서만 의미 있는 분기 — 모바일(Uri.base.path == '/')에서는
/// 항상 false라 일반 앱만 실행된다.
bool get _isAdminRoute => kIsWeb && Uri.base.path.startsWith('/admin');

void main() async {
  // 랜딩페이지가 넘겨준 주소(`/app/?tab=place`, `/app/?register=1`)를 **여기서**
  // 붙잡는다 — 아래 usePathUrlStrategy가 첫 라우트를 세우며 주소를 base href로
  // 덮어써서, 화면에서 Uri.base를 읽을 때는 쿼리가 이미 사라져 있다.
  WebLaunchUrl.capture();

  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // 웹에서 /#/party/{id} 대신 /party/{id} 형태의 깨끗한 URL을 쓰기 위함 —
  // SEO・공유 링크 모두 해시 없는 경로를 기대한다.
  if (kIsWeb) {
    usePathUrlStrategy();
    // 🎬 Cloudflare Stream 동영상(.m3u8)을 Chrome·Edge·Firefox에서도 재생하게
    // 만드는 **유일한 자리**. 화면·카드 코드는 한 줄도 바뀌지 않는다 —
    // video_player의 웹 구현 아래 한 층에서 갈아끼운다([WebVideoHls]).
    // 플러그인 등록이 끝난 뒤여야 하므로 main() 안에서 부른다.
    WebVideoHls.install();
  }

  // 관리자 웹은 Kakao/Naver SDK, 스플래시 등 모바일 전용 초기화가 필요 없어
  // Firebase만 초기화하고 곧바로 AdminApp을 실행한다.
  if (_isAdminRoute) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
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
  // .env가 없어도 앱은 뜬다.
  //
  // 여기 담긴 값은 전부 클라이언트용 식별자(카카오 JS 키·네이버 지도 클라이언트
  // ID)라, 없으면 그 기능 하나만 비활성화되면 될 일이지 앱 전체가 흰 화면이 될
  // 일이 아니다. 웹에서는 실제로 그럴 위험이 있었다 — 호스팅의 ignore 규칙이
  // 점으로 시작하는 파일을 걸러서 `assets/.env`가 배포에서 빠질 수 있고,
  // 그러면 이 한 줄에서 예외가 나 runApp까지 가지 못한다(firebase.json의
  // "!app/assets/.env" 예외가 1차 방어, 이 try가 2차 방어다).
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint('[main] .env를 읽지 못했습니다 — 카카오 로그인·지도만 비활성화됩니다: $e');
  }
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 차단 목록을 로그인 상태에 붙여 둔다 — 로그인/로그아웃을 스스로 따라가므로
  // 로그인 경로(구글·카카오·네이버·세션 복원)마다 따로 부를 필요가 없다.
  // 목록·지도·채팅이 이 값을 **동기적으로** 읽는다(services/block_service.dart).
  BlockService.attach();

  // 카카오 SDK는 플랫폼별로 다른 앱 키를 쓴다 — 모바일은 네이티브 앱 키,
  // 웹은 JavaScript 키(카카오 개발자 콘솔의 "Web" 플랫폼에 도메인을 등록하고
  // 발급받아야 함). KakaoSdk.appKey getter가 kIsWeb에 따라 자동으로 골라 쓴다.
  KakaoSdk.init(
    nativeAppKey: dotenv.env['KAKAO_NATIVE_APP_KEY'] ?? '',
    javaScriptAppKey: dotenv.env['KAKAO_JAVASCRIPT_APP_KEY'] ?? '',
  );

  if (!kIsWeb) {
    // onAuthFailed를 **반드시** 넘긴다 — 없으면 앱이 죽는다.
    //
    // 플러그인은 이 콜백 유무를 `setAuthFailedListener`로 네이티브에 전달하고,
    // 없으면(false) 인증 실패 시 초기화 때 이미 응답을 끝낸 MethodChannel
    // Result에 `result.error()`를 한 번 더 부른다 →
    // `IllegalStateException: Reply already submitted`가 안드로이드 메인
    // 스레드에서 터지고, Dart 예외가 아니라 미처리 Java 예외라 Flutter가
    // 잡지 못한 채 프로세스가 SIG 9로 종료된다.
    // 콜백을 넘기면 안전한 invokeMethod 경로를 타서 로그만 남고 앱은 산다.
    //
    // 지도는 부가 정보이므로 여기서 재시도하거나 사용자에게 팝업을 띄우지
    // 않는다 — 지도만 비고 나머지 화면은 그대로 쓸 수 있어야 한다.
    await FlutterNaverMap().init(
      clientId: dotenv.env['NAVER_MAP_CLIENT_ID'] ?? '',
      onAuthFailed: (ex) => debugPrint('[NaverMap] 인증 실패 — 지도만 비활성화됩니다: $ex'),
    );
  }

  if (!kIsWeb) {
    FlutterNativeSplash.remove();
  }

  // "파티츄 전용 혜택" 명판 이미지를 미리 깎아둔다 — 첫 목록이 뜬 뒤에 로딩이
  // 끝나면 명판이 한 박자 늦게 나타난다. await하지 않으므로 앱 시작은 안 늦다.
  PartychuPerkPlaqueArt.ensureLoaded();

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
      // 웹에서 브라우저 탭 제목이 된다 — 주지 않으면 Flutter가 문서 제목을
      // 빈 문자열로 덮어써서 /app/ 탭이 이름 없이 뜬다(index.html의 <title>도
      // 지워진다). 모바일에서는 최근 앱 목록 라벨로만 쓰인다.
      title: '파티츄',
      navigatorKey: navigatorKey,
      // 앱 전체를 한국어로 — 이 델리게이트가 있어야 Material 기본 달력·시계가
      // 'Select date / Wed, Aug 19 / OK'가 아니라 '날짜 선택 / 8월 19일 (수) /
      // 확인'으로 뜬다(앱 안 모든 showDatePicker에 한 번에 적용된다).
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ko', 'KR')],
      locale: const Locale('ko', 'KR'),
      // 로그인 여부와 무관하게(로그인 화면이든 메인 화면이든) 앱을 켤 때마다
      // 한 번씩 최신 버전을 확인해야 하므로 최상단에서 감싼다.
      home: const AppUpdateGate(child: _AuthGate()),
    );
  }
}

/// 앱의 **루트 게이트** — 첫 화면을 고르는 단 하나의 자리.
///
/// Firebase Auth 세션이 복원될 때까지 로딩을 보여주고, 그다음부터는
/// [resolveRootGateScreen]의 판정대로 서비스 화면·본인확인·확인 실패·탈퇴
/// 대기 중 하나를 그린다. 세션이 바뀌면 스스로 다시 평가한다.
///
/// **본인확인을 여기서 보는 이유**는 root_gate.dart 상단에 적어 두었다 —
/// 요약하면, 기능 진입 시점에 화면을 띄우는 방식은 뒤로가기로 닫혔고 앱을
/// 다시 켜면 아무도 묻지 않았기 때문이다.
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
      final user = await FirebaseAuth.instance.authStateChanges().first.timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );

      if (user != null) {
        // uid 대입과 '아직 안 읽었다' 표시를 한 번에 — 그 사이로는 한 프레임도
        // 그려질 수 없으므로, 세션 복원 직후에 기본값 false를 보고 본인확인
        // 화면이 뜨는 일이 없다(UserSession.beginSession 참고).
        UserSession.beginSession(user.uid);
        // 프로필(본인확인 여부 포함)을 다 읽을 때까지 로딩 화면을 유지한다 —
        // 아직 안 읽힌 상태로 MainScreen을 띄우면, 이미 본인확인을 마친
        // 사용자도 "미인증"으로 보여 본인확인 화면이 자동으로 떴다.
        await UserSession.loadFromFirestore();
        AnalyticsService.logEvent(AnalyticsEventType.appOpen);
      }
    } catch (_) {
      // 읽기에 실패하면 UserSession이 '확인 못 함'([IdentityStatus.unknown])
      // 상태로 남는다. 그대로 들여보내지 않는다 — 아래 루트 게이트가 재시도와
      // 로그아웃만 있는 확인 실패 화면을 띄운다(root_gate.dart 참고).
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
        UserSession.beginSession(uid);
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

  /// 앱 시작 시(세션 복원)와 게이트가 판정을 기다리는 동안 쓰는 같은 화면.
  Widget _loadingScreen() => const Scaffold(
    backgroundColor: Color(0xFFFFF4F8),
    body: Center(child: CircularProgressIndicator(color: Color(0xFFFF6FA0))),
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) return _loadingScreen();

    // ── 루트 게이트 ────────────────────────────────────────────────────
    //
    // 첫 화면을 무엇으로 할지는 [resolveRootGateScreen] 하나가 정한다. 여기서
    // 막는 것은 두 가지다.
    //
    //  · 탈퇴 대기 — 규칙과 서버가 쓰기를 막고 있어 그대로 들여보내면 버튼마다
    //    실패하는 앱이 되고, 사용자는 왜 안 되는지 알 수 없다.
    //  · 본인확인 미완료·확인 실패 — 회원 기능의 전제 조건이다. 예전에는 이
    //    판정을 로그인 성공 시점과 하단 탭에서 화면을 **push**해 지켰는데,
    //    그 화면은 뒤로가기로 닫혔고 앱을 다시 켜면 아예 묻지도 않았다.
    //    이제 미인증 계정에게는 MainScreen이라는 위젯 자체가 만들어지지 않는다.
    //
    // 세 상태(로그인 여부·계정 상태·본인확인)를 모두 구독해 그린다 — 어느
    // 쪽이 바뀌든 게이트가 스스로 다시 평가한다. 화면 전환을 각 화면이 직접
    // push/pop해서 흉내내면 세션과 화면이 어긋난다.
    return AnimatedBuilder(
      // revision 하나로 로그인·로그아웃과 **프로필 읽기 완료**가 모두 들어온다
      // (UserSession.identityStatus는 저장값이 아니라 계산값이라, 그 재료가
      //  바뀌는 모든 길목이 이 카운터를 올린다).
      animation: Listenable.merge([
        UserSession.revision,
        UserSession.accountStatusListenable,
      ]),
      builder: (context, _) {
        final screen = currentRootGateScreen();
        if (screen == RootGateScreen.main) return const MainScreen();
        // 확인하는 중에는 로딩만 — 여기서 화면을 걷어내면 로그인 화면이
        // 정상 로그인 도중에 사라진다(아래 popUntil을 타면 안 되는 유일한 가지).
        if (screen == RootGateScreen.checking) return _loadingScreen();

        // 게이트가 닫히는 순간 위에 쌓여 있던 화면(등록·예약·상세 등)을
        // 걷어낸다. 게이트는 첫 화면만 갈아끼우므로, 그 위에 올라가 있던
        // 경로는 그대로 남아 사용자가 계속 조작할 수 있었다. 로그인 화면을
        // 거쳐 미인증으로 판정된 경우도 이 한 줄로 함께 정리된다.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final nav = navigatorKey.currentState;
          if (nav != null && nav.canPop()) {
            nav.popUntil((r) => r.isFirst);
          }
        });

        return switch (screen) {
          RootGateScreen.withdrawalPending => WithdrawalPendingScreen(
            status: WithdrawalStatus(
              status: UserSession.accountStatus,
              graceDays: 7,
              scheduledAt: UserSession.withdrawalScheduledAt,
            ),
            // 취소·로그아웃 후 이 위젯을 다시 그려 정상 화면으로 돌아가게 한다.
            onRestored: () {
              if (mounted) setState(() {});
            },
          ),
          RootGateScreen.identityVerification => const WebFrame(
            child: IdentityVerificationScreen(),
          ),
          RootGateScreen.identityCheckFailed => const WebFrame(
            child: IdentityCheckFailedScreen(),
          ),
          // 위에서 이미 걸러진 값들 — switch를 총망라로 유지하기 위한 가지다.
          RootGateScreen.main => const MainScreen(),
          RootGateScreen.checking => _loadingScreen(),
        };
      },
    );
  }
}

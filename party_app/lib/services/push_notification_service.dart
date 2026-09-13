import 'dart:convert';
import 'dart:io' show Platform;

import 'package:app_settings/app_settings.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:party_app/screens/notifications_screen.dart';
import 'package:party_app/services/notification_service.dart';
import 'package:party_app/utils/notification_route.dart';
import 'package:party_app/utils/root_gate.dart';
import 'package:party_app/widgets/web_frame.dart';

/// 사용자에게 보여줄 알림 권한 상태.
///
/// OS가 돌려주는 값을 그대로 쓰지 않고 네 갈래로 정리한다 — 화면이 "다시 물을
/// 수 있는가 / 설정으로 보내야 하는가"를 이 값 하나로 판단할 수 있어야 하기
/// 때문이다.
enum PushPermissionState {
  /// 아직 한 번도 묻지 않았다 — 사전 안내 후 OS 팝업을 띄울 수 있다.
  notAsked,

  /// 허용됨.
  granted,

  /// 거부했지만 다시 물어볼 수 있다(iOS는 이 상태가 사실상 없다).
  denied,

  /// "다시 묻지 않음" 또는 시스템 설정에서 꺼둠 — **OS 팝업을 다시 띄울 수
  /// 없다.** 이 상태에서 requestPermission을 불러도 팝업 없이 즉시 거부로
  /// 떨어지므로, 화면은 반드시 "설정에서 알림 켜기"로 안내해야 한다.
  blocked,
}

extension PushPermissionStateX on PushPermissionState {
  bool get isGranted => this == PushPermissionState.granted;

  /// OS 권한 팝업을 띄우는 게 의미가 있는 상태인가.
  bool get canPrompt =>
      this == PushPermissionState.notAsked ||
      this == PushPermissionState.denied;

  /// 앱 설정 화면으로 보내야 하는 상태인가.
  bool get needsSettings => this == PushPermissionState.blocked;
}

/// FCM 토큰과 알림 권한을 다루는 단 하나의 창구.
///
/// ── 토큰을 서버 함수로만 등록하는 이유 ────────────────────────────────────
/// 토큰은 `users/{uid}/devices/{token}`에 저장되는데, 이 컬렉션은 규칙이
/// 클라이언트 쓰기를 완전히 막고 있다(firestore.rules). 계정을 바꿔 로그인했을
/// 때 **이전 사용자 밑에 남은 같은 토큰 문서를 지워야** 하는데, 그건 남의
/// 문서라 클라이언트가 직접 지울 수 없기 때문이다. 그 정리를 포함해 등록을
/// registerPushToken onCall이 대신한다(functions/pushTokens.js).
class PushNotificationService {
  PushNotificationService._();

  static final _messaging = FirebaseMessaging.instance;

  static FirebaseFunctions get _fn =>
      FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  /// 마지막으로 서버에 등록한 토큰 — 로그아웃 때 이 값을 해제한다.
  static String? _registeredToken;

  /// 토큰 갱신 구독. 로그인 상태에서만 살아 있다.
  static bool _refreshHooked = false;

  /// 앱이 떠 있을 때 알림을 그리는 창구.
  static final _local = FlutterLocalNotificationsPlugin();

  /// [initMessaging]을 두 번 하지 않기 위한 표시(구독이 중복되면 알림도 겹친다).
  static bool _messagingReady = false;

  /// 알림 id — 같은 값을 쓰면 뒤 알림이 앞 알림을 덮어쓴다. 겹치지 않게 센다.
  static int _localId = 0;

  /// 지금 사용자가 열어둔 채팅방. 서버는 누가 방을 보고 있는지 알 수 없어
  /// 그냥 보내므로, **보고 있는 대화의 알림은 앱이 그리지 않는다** — 읽고 있는
  /// 메시지가 그대로 알림으로 또 뜨는 건 잡음일 뿐이다.
  /// 방을 나갈 때 반드시 null로 되돌려야 한다(ChatRoomScreen이 한다).
  static String? activeChatRoomId;

  /// 매니페스트의 default_notification_channel_id와 **반드시 같은 값**이어야
  /// 한다(android/app/src/main/AndroidManifest.xml). 값이 어긋나면 앱이 꺼져
  /// 있을 때 오는 알림만 다른(존재하지 않는) 채널로 떨어져, 사용자가 설정에서
  /// 끄고 켜는 스위치와 실제 알림이 따로 논다.
  static const _channelId = 'partychu_default';

  // ── 권한 상태 조회 ──────────────────────────────────────────────────
  //
  // permission_handler와 firebase_messaging을 함께 본다. 전자는 "다시 묻지
  // 않음"(permanentlyDenied)을 알려주고, 후자는 iOS의 provisional 같은 세부
  // 상태를 알려준다. 웹은 권한 모델이 달라 이 화면 흐름을 타지 않는다.
  static Future<PushPermissionState> currentState() async {
    if (kIsWeb) return PushPermissionState.notAsked;

    final status = await Permission.notification.status;

    // OS가 이 앱의 알림을 실제로 내보내 주는지. firebase_messaging은 Android
    // 에서 이 값을 areNotificationsEnabled()로 판정한다.
    final settings = await _messaging.getNotificationSettings();
    final osWillDeliver =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;

    // **권한이 있다고 알림이 나가는 건 아니다.** Android 13+ 에서 사용자가
    // 설정에서 알림 토글을 끄면 POST_NOTIFICATIONS 레코드는 granted로 남는데
    // (permission_handler는 checkSelfPermission만 본다) 알림은 실제로 막힌다.
    // 권한만 보고 granted로 단락하면 이 상태를 '허용'으로 읽어, 안내도 못
    // 띄우고 토큰만 등록해 **서버가 영영 도착하지 않을 알림을 계속 보낸다.**
    // 그래서 두 값을 함께 본다.
    if (status.isGranted) {
      return osWillDeliver
          ? PushPermissionState.granted
          : PushPermissionState.blocked;
    }
    if (status.isPermanentlyDenied) return PushPermissionState.blocked;

    // Android 12 이하에는 런타임 권한이 없어 permission_handler가 늘 granted를
    // 주지만, 사용자가 시스템 설정에서 앱 알림을 통째로 꺼둘 수 있다. 그
    // 경우를 잡으려면 OS 알림 설정 자체를 봐야 한다.
    switch (settings.authorizationStatus) {
      case AuthorizationStatus.authorized:
      case AuthorizationStatus.provisional:
        return PushPermissionState.granted;
      case AuthorizationStatus.denied:
        // 아직 물어본 적이 없으면 denied로 오지 않는다 — denied인데
        // permission_handler가 permanentlyDenied가 아니라면 다시 물을 수 있다.
        return status.isDenied
            ? PushPermissionState.denied
            : PushPermissionState.blocked;
      case AuthorizationStatus.notDetermined:
        return PushPermissionState.notAsked;
    }
  }

  /// OS 권한 팝업을 띄운다. **사전 안내 UI를 보여준 뒤에만 부를 것** —
  /// 한 번 거부되면 다시 띄울 수 없으므로 맥락 없이 소모하면 안 된다.
  ///
  /// 이미 [PushPermissionState.blocked]면 팝업이 뜨지 않으므로 부르지 않는다.
  static Future<PushPermissionState> requestPermission() async {
    final before = await currentState();
    if (before.needsSettings || before.isGranted) return before;

    await _messaging.requestPermission(alert: true, badge: true, sound: true);
    return currentState();
  }

  /// 시스템의 앱 **알림** 설정 화면을 연다(꺼둔 사용자를 위한 유일한 경로).
  ///
  /// permission_handler의 openAppSettings()는 앱 정보(App info) 화면까지만
  /// 열어서, 사용자가 거기서 '알림'을 한 번 더 찾아 들어가야 한다. 알림을
  /// 켜라고 보낸 자리인 만큼 알림 설정으로 곧장 보낸다.
  static Future<void> openSettings() =>
      AppSettings.openAppSettings(type: AppSettingsType.notification);

  // ── 수신 · 표시 · 이동 ──────────────────────────────────────────────
  //
  // 알림이 도착하는 상태는 셋이고, 각각 다른 사람이 그린다.
  //
  //   앱이 꺼짐/백그라운드 → **OS가 그린다.** 서버가 notification 페이로드를
  //     함께 보내므로 앱 코드가 필요 없다. 그래서 백그라운드 핸들러(별도
  //     isolate)를 두지 않았다 — 둘 다 그리면 알림이 두 번 뜬다.
  //   앱이 떠 있음 → **OS는 그리지 않는다.** 이때만 아래 onMessage가 받아
  //     flutter_local_notifications로 직접 그린다.
  //
  // 이동은 어느 경로로 눌렀든 [notificationTarget] 하나로 모은다.

  /// 앱 시작 시 한 번 호출. 권한과 무관하게 불러도 된다 — 여기서는 채널을
  /// 만들고 구독만 걸 뿐, 권한을 묻지 않는다(그건 PushPermissionGate의 몫).
  ///
  /// [navigatorKey]를 인자로 받는 이유: main.dart를 import하면 서비스가 앱
  /// 진입점을 거꾸로 참조하게 된다. DeepLinkService와 같은 방식으로 맞췄다.
  static Future<void> initMessaging(GlobalKey<NavigatorState> key) async {
    if (kIsWeb || _messagingReady) return;
    _messagingReady = true;

    try {
      await _local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // 권한 요청을 여기서 하지 않는다. 초기화만으로 iOS 권한 팝업이 뜨면
          // 사전 안내 없이 소모돼, 한 번 거부당한 뒤로는 앱에서 다시 띄울 수
          // 없다 — 권한은 반드시 PushPermissionGate를 거친다.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) =>
            _openFromPayload(response.payload, key),
      );

      // Android 8+ 는 채널 없이는 알림을 띄울 수 없다. 매니페스트에 id만
      // 적어두는 것으로는 채널이 생기지 않으므로(그건 OS에게 "이 id를 쓰라"고
      // 알려줄 뿐) 앱이 같은 id로 실제 채널을 만들어줘야 한다.
      await _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelId,
              '파티츄 알림',
              description: '채팅 메시지, 예약·파티 소식을 알려드려요.',
              importance: Importance.high,
            ),
          );

      // iOS가 앱이 떠 있을 때 스스로 배너를 띄우지 않게 한다. 띄우게 두면
      // 아래 onMessage가 그리는 알림과 겹쳐 **같은 알림이 두 번 보인다.**
      // (뱃지는 OS가 세는 값이라 그대로 둔다.)
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: true,
        sound: false,
      );

      FirebaseMessaging.onMessage.listen(_showForeground);
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _open(m.data, key));

      // 앱이 완전히 꺼져 있을 때 알림을 눌러 실행된 경우. 이 시점엔 아직
      // Navigator가 붙기 전이라 한 프레임 뒤로 미룬다(DeepLinkService와 동일).
      final initial = await _messaging.getInitialMessage();
      if (initial != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _open(initial.data, key),
        );
      }
    } catch (e) {
      // 알림을 못 받는 것이 앱을 못 쓰는 것이 되면 안 된다.
      debugPrint('[Push] 메시지 수신 초기화 실패: $e');
    }
  }

  /// 앱이 떠 있을 때 도착한 메시지를 직접 그린다.
  static Future<void> _showForeground(RemoteMessage message) async {
    final data = message.data;

    // 지금 보고 있는 대화의 메시지는 그리지 않는다(위 activeChatRoomId 주석).
    if (data['type'] == 'chat' &&
        activeChatRoomId != null &&
        data['roomId'] == activeChatRoomId) {
      return;
    }

    // 제목·본문은 notification 페이로드에서 온다. data 쪽도 보는 건 나중에
    // data만 담은 메시지를 보내게 되더라도 조용히 사라지지 않게 하기 위함이다.
    final title = (message.notification?.title ?? data['title'] ?? '')
        .toString();
    final body = (message.notification?.body ?? data['body'] ?? '').toString();
    if (title.isEmpty) return;

    _localId = (_localId + 1) % 100000;
    try {
      await _local.show(
        _localId,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            '파티츄 알림',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: jsonEncode(data),
      );
    } catch (e) {
      debugPrint('[Push] 알림 표시 실패: $e');
    }
  }

  static void _openFromPayload(String? payload, GlobalKey<NavigatorState> key) {
    if (payload == null || payload.isEmpty) return;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) _open(Map<String, dynamic>.from(decoded), key);
    } catch (e) {
      debugPrint('[Push] 알림 payload 해석 실패: $e');
    }
  }

  /// 알림을 눌렀을 때의 이동. 갈 곳을 못 정하면 알림함을 연다 — 알림이 왔는데
  /// 눌러도 아무 일이 없으면 사용자는 소식을 확인할 방법을 잃는다.
  static void _open(Map<String, dynamic> data, GlobalKey<NavigatorState> key) {
    final navigator = key.currentState;
    if (navigator == null) return;
    // 루트 게이트가 막고 있으면 그 위에 화면을 쌓지 않는다 — 알림 탭은 게이트를
    // 거치지 않고 전역 네비게이터에 직접 push하므로, 이걸 보지 않으면 본인확인
    // 화면 위로 상세·알림함이 올라가 게이트가 무력화된다(deep_link_service.dart
    // 와 같은 처리). 게이트를 통과하고 나면 알림함에서 같은 소식을 볼 수 있다.
    if (rootGateBlocksService) {
      debugPrint('[Push] 루트 게이트가 막고 있어 이동하지 않음');
      return;
    }
    // 푸시를 눌러 소식을 확인했으면 알림함에서도 읽은 것이다 — 여기서 읽음
    // 처리하지 않으면 알림함을 따로 열어 다시 누르기 전까지 종 배지가 계속
    // 켜져 있다. 서버가 payload에 이미 넣어 둔 문서 id를 쓸 뿐이라
    // (functions/pushDispatch.js의 routeData) 발송·이동 로직은 그대로다.
    _markPushRead(data);
    final target = notificationTarget(data) ?? const NotificationsScreen();
    navigator.push(webFramedRoute((_) => target));
  }

  /// 푸시가 가리키는 알림 문서를 읽음으로. 실패해도 이동은 막지 않는다 —
  /// 읽음 표시가 안 된 것보다 소식을 못 여는 쪽이 훨씬 나쁘다.
  /// (채팅 푸시처럼 알림 문서가 없는 종류는 id가 비어 있어 그냥 지나간다.)
  static void _markPushRead(Map<String, dynamic> data) {
    final id = data['notificationId'];
    if (id is! String || id.isEmpty) return;
    NotificationService.markRead(
      id,
    ).catchError((Object e) => debugPrint('[Push] 읽음 처리 실패: $e'));
  }

  // ── 토큰 수명주기 ───────────────────────────────────────────────────

  /// 로그인 직후 호출. 권한이 없으면 토큰을 만들지 않는다 — 권한이 없는 기기의
  /// 토큰을 등록해두면 서버가 보낼 수 없는 곳으로 계속 발송을 시도하게 된다.
  static Future<void> registerForUser() async {
    if (kIsWeb) return;
    final state = await currentState();
    if (!state.isGranted) return;

    try {
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) return;
      await _sendTokenToServer(token);
      _hookRefresh();
    } catch (e) {
      // 토큰 등록 실패가 로그인 자체를 막지는 않는다.
      debugPrint('[Push] 토큰 등록 실패: $e');
    }
  }

  /// 토큰 갱신 구독 — FCM이 토큰을 재발급하면 서버에 즉시 반영한다.
  /// 구독을 한 번만 걸어 로그인/로그아웃을 반복해도 중복되지 않게 한다.
  static void _hookRefresh() {
    if (_refreshHooked) return;
    _refreshHooked = true;
    _messaging.onTokenRefresh.listen((token) async {
      try {
        await _sendTokenToServer(token);
      } catch (e) {
        debugPrint('[Push] 갱신 토큰 반영 실패: $e');
      }
    });
  }

  static Future<void> _sendTokenToServer(String token) async {
    final info = await PackageInfo.fromPlatform();
    await _fn.httpsCallable('registerPushToken').call<void>({
      'token': token,
      'platform': Platform.isIOS ? 'ios' : 'android',
      'deviceId': await _deviceId(),
      'appVersion': info.version,
    });
    _registeredToken = token;
  }

  /// 로그아웃 시 호출 — 이 기기를 사용자에게서 떼어낸다.
  ///
  /// 서버 문서를 지우는 것만으로는 부족하다. 토큰 자체를 버려야(deleteToken)
  /// 다음에 로그인하는 **다른 계정이 같은 토큰을 물려받지 않는다** — 물려받으면
  /// 서버가 두 계정을 같은 기기로 착각할 여지가 남는다.
  static Future<void> unregisterForUser() async {
    if (kIsWeb) return;
    try {
      final token = _registeredToken ?? await _messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _fn.httpsCallable('unregisterPushToken').call<void>({
          'token': token,
        });
      }
      await _messaging.deleteToken();
    } catch (e) {
      // 로그아웃은 어떤 경우에도 진행돼야 한다.
      debugPrint('[Push] 토큰 해제 실패: $e');
    } finally {
      _registeredToken = null;
    }
  }

  /// 기기 식별자 — 같은 기기의 재설치를 알아보기 위한 참고값일 뿐,
  /// 발송 대상 판정에는 쓰지 않는다(그건 토큰이 한다).
  static Future<String?> _deviceId() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) return (await plugin.androidInfo).id;
      if (Platform.isIOS) return (await plugin.iosInfo).identifierForVendor;
    } catch (_) {
      // 식별자를 못 읽어도 등록은 진행한다.
    }
    return null;
  }
}

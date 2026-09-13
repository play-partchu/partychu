import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 지금 신청자 사진을 어떻게 다뤄야 하는가.
///
/// 값이 하나뿐인 이유가 있다 — 보호가 필요한 사유는 겹칠 수 있는데(녹화 중에
/// 스크린샷을 찍고 앱을 내리는 것도 가능하다) 화면이 할 일은 결국 "가린다 /
/// 안 가린다" 하나다. 겹칠 때 무엇을 보여줄지는 [ScreenCaptureGuard]가 한
/// 곳에서 정한다.
enum PhotoProtectionState {
  /// 그대로 보여준다.
  visible,

  /// 앱이 내려가 있다 — App Switcher 미리보기에 남지 않게 덮는다.
  background,

  /// 화면 녹화·미러링 중. **확인을 눌러도 풀리지 않는다** — 푸는 순간
  /// 그대로 녹화에 찍히기 때문이다. 녹화가 끝나야 다시 보인다.
  recording,

  /// 스크린샷이 찍혔다. 경고를 읽고 확인을 눌러야 다시 보인다.
  screenshot,
}

/// 승인제 파티 **신청자 제출 사진**이 화면에 있는 동안만 캡처 보호를 거는
/// 잠금장치.
///
/// ── 왜 화면 단위로 켜고 끄는가 ──────────────────────────────────────────────
///
/// Android의 `FLAG_SECURE`는 **창(Window) 전체**에 걸린다. 앱을 켤 때 한 번
/// 걸어 두면 지도·파티 상세·영수증까지 전부 캡처가 막혀서, 사용자가 파티를
/// 친구에게 캡처해 보내는 지극히 정상적인 사용까지 함께 죽는다. 그래서
/// 신청자 사진이 실제로 화면에 있는 동안에만 걸고, 닫으면 곧바로 푼다.
///
/// ── 왜 참조 개수(ref count)인가 ─────────────────────────────────────────────
///
/// 사진 썸네일이 있는 심사 시트 **위에** 전체화면 뷰어가 다시 열린다. 뷰어를
/// 닫을 때 무조건 풀어 버리면, 아직 썸네일이 남아 있는 시트가 보호 없이
/// 드러난다. 그래서 화면마다 표를 하나씩 받아 가고([acquire]) 돌려주며
/// ([release]), **마지막 하나가 돌려줄 때만** 실제로 푼다. 겹쳐 있는 동안
/// 경고창은 맨 위 화면만 띄운다([isFrontmost]) — 안 그러면 같은 경고가 두 장
/// 겹쳐 뜬다.
///
/// ── 플랫폼별로 실제 보호 수준이 다르다 ─────────────────────────────────────
///
///   · Android — `FLAG_SECURE`로 스크린샷·화면 녹화가 OS 차원에서 막히고,
///     최근앱(App Switcher) 미리보기에도 내용이 남지 않는다. 애초에 캡처가
///     안 되므로 아래의 감지 이벤트는 올라올 일이 없다.
///   · iOS — 같은 기능이 **아예 없다.** 스크린샷을 사전에 막을 공식 방법이
///     없어서, 공식 API로 할 수 있는 것만 한다.
///       (1) `UIScreen.isCaptured` — 녹화·미러링이 켜지면 [recording],
///       (2) `userDidTakeScreenshotNotification` — 찍힌 **뒤에** [screenshot],
///       (3) 앱이 내려갈 때 창을 덮어 App Switcher 미리보기 보호.
///     비공식 우회(secureTextEntry 트릭 등)는 쓰지 않는다 — OS 업데이트나
///     심사에서 언제든 깨지는 것에 보호를 걸어 두면, 깨진 줄도 모르고
///     "막고 있다"고 안내하게 된다.
///   · 그 밖(웹/데스크톱) — 브라우저 우클릭 메뉴만 잠근다. 나머지는 아무것도
///     하지 않고, 안내 문구도 딱 그만큼만 말한다.
class ScreenCaptureGuard with WidgetsBindingObserver {
  ScreenCaptureGuard._();

  static final ScreenCaptureGuard instance = ScreenCaptureGuard._();

  static const MethodChannel _channel = MethodChannel(
    'kr.co.partychu.app/screen_capture_guard',
  );
  static const EventChannel _events = EventChannel(
    'kr.co.partychu.app/screen_capture_guard/events',
  );

  /// 네이티브 구현이 있는 플랫폼인가.
  ///
  /// `kIsWeb`을 **먼저** 본다 — 웹에서도 `defaultTargetPlatform`은 브라우저가
  /// 도는 OS(android/iOS)를 그대로 돌려주기 때문에, 이 순서가 아니면 모바일
  /// 브라우저에서 있지도 않은 채널을 부르게 된다.
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// 지금 보호를 잡고 있는 화면들. 마지막이 맨 위 화면이다.
  final List<Object> _holders = [];

  StreamSubscription<dynamic>? _subscription;

  /// 화면이 지금 무엇을 해야 하는지. 사진을 그리는 쪽은 이것만 보면 된다.
  final ValueNotifier<PhotoProtectionState> protection =
      ValueNotifier<PhotoProtectionState>(PhotoProtectionState.visible);

  /// 이번 보호 구간에서 스크린샷이 몇 번 감지됐는지.
  ///
  /// 값이 **바뀔 때마다** 맨 위 화면이 경고창을 띄운다. 횟수를 함께 들고 있는
  /// 이유는 반복될수록 문구를 분명하게 하기 위해서다 — 세는 것은 여기까지이고,
  /// 이용 제한이나 신고 같은 제재는 하지 않는다.
  final ValueNotifier<int> screenshotCount = ValueNotifier<int>(0);

  bool _captured = false;
  bool _screenshotPending = false;
  bool _foreground = true;

  /// 이 표가 맨 위 화면의 것인가 — 경고창을 한 장만 띄우기 위한 판정.
  bool isFrontmost(Object token) =>
      _holders.isNotEmpty && identical(_holders.last, token);

  /// 보호를 하나 잡고 표를 받는다. 받은 표는 반드시 [release]로 돌려준다.
  Object acquire() {
    final token = Object();
    _holders.add(token);
    if (_holders.length == 1) _start();
    return token;
  }

  /// 표를 돌려준다. **마지막 하나**가 돌아올 때만 실제로 풀린다.
  void release(Object token) {
    if (!_holders.remove(token)) return;
    if (_holders.isEmpty) _stop();
  }

  void _start() {
    WidgetsBinding.instance.addObserver(this);
    // 첫 프레임 전에는 null이다 — 그때는 앱이 앞에 있다고 본다.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _recompute();

    // 웹에서 사진을 우클릭·길게 눌러 브라우저 저장 메뉴가 뜨는 것을 막는다.
    // Flutter가 이미지를 자기 캔버스에 직접 그리므로 iOS/Android에는 이런
    // 시스템 메뉴 자체가 없고, 앱에도 저장·공유 버튼을 두지 않았다.
    if (kIsWeb) BrowserContextMenu.disableContextMenu();

    // 웹·데스크톱은 여기까지다 — 채널이 없으니 부르지 않는다.
    if (!isSupported) return;
    _listen();
    unawaited(_enable());
  }

  Future<void> _enable() async {
    try {
      // 이미 녹화 중인 상태에서 화면을 열었을 수도 있어, 켜는 시점의 상태를
      // 그대로 받아 온다.
      final captured = await _channel.invokeMethod<bool>('enable');
      // 응답을 기다리는 사이 화면이 닫혔으면 그 결과는 버린다.
      if (_holders.isEmpty) return;
      _captured = captured == true;
      _recompute();
    } on MissingPluginException {
      // 채널이 없는 빌드 — 보호 없이 그대로 보여준다(열람 자체를 막지 않는다).
    } on PlatformException catch (e) {
      debugPrint('[화면보호] 켜기 실패: $e');
    }
  }

  void _stop() {
    WidgetsBinding.instance.removeObserver(this);
    if (kIsWeb) BrowserContextMenu.enableContextMenu();

    // 보호 구간이 끝났으니 세어 둔 것도 함께 지운다 — 다음에 다른 신청자의
    // 사진을 열었을 때 지난 화면의 경고 단계를 물려받으면 안 된다.
    _captured = false;
    _screenshotPending = false;
    _foreground = true;
    screenshotCount.value = 0;
    protection.value = PhotoProtectionState.visible;

    unawaited(_subscription?.cancel());
    _subscription = null;
    if (!isSupported) return;
    _channel.invokeMethod<void>('disable').catchError((Object e) {
      // 여기서 실패하면 캡처 금지가 남는다 — 화면이 멈추지는 않지만 사용자가
      // 다른 화면을 캡처하지 못하게 되므로 로그로는 남긴다.
      if (e is! MissingPluginException) debugPrint('[화면보호] 끄기 실패: $e');
      return null;
    });
  }

  /// 경고를 읽고 확인을 눌렀다.
  ///
  /// **녹화 중이면 이것만으로는 풀리지 않는다** — [_recompute]가 녹화를 먼저
  /// 보기 때문이다. 녹화가 끝나야 사진이 돌아온다.
  void acknowledgeScreenshot() {
    if (!_screenshotPending) return;
    _screenshotPending = false;
    _recompute();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // resumed가 아니면 전부 "앞에 없음"이다(inactive·hidden·paused). 알림창을
    // 내리거나 앱을 전환하는 그 순간부터 덮여야 미리보기에 남지 않는다.
    _foreground = state == AppLifecycleState.resumed;
    _recompute();
  }

  /// 겹친 사유 중 **가장 강한 것 하나**를 고른다.
  ///
  /// 순서가 곧 정책이다 — 앱이 내려가 있으면 무조건 덮고, 녹화 중이면 확인을
  /// 눌러도 안 풀리고, 그 다음이 확인으로 풀 수 있는 스크린샷이다.
  void _recompute() {
    protection.value = !_foreground
        ? PhotoProtectionState.background
        : _captured
        ? PhotoProtectionState.recording
        : _screenshotPending
        ? PhotoProtectionState.screenshot
        : PhotoProtectionState.visible;
  }

  void _listen() {
    _subscription ??= _events.receiveBroadcastStream().listen(
      _onEvent,
      onError: (Object e) => debugPrint('[화면보호] 이벤트 오류: $e'),
    );
  }

  void _onEvent(dynamic raw) {
    if (raw is! Map || _holders.isEmpty) return;

    final captured = raw['captured'];
    if (captured is bool && captured != _captured) {
      _captured = captured;
      _recompute();
    }

    if (raw['screenshot'] == true) {
      _screenshotPending = true;
      // 가리는 것이 먼저다 — 경고창은 이미 덮인 화면 위에 뜬다.
      _recompute();
      screenshotCount.value++;
    }
  }
}

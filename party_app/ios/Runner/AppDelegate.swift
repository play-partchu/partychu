import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // 신청자 제출 사진 보호. 엔진이 사는 동안 함께 살아야 해서 여기 붙들어 둔다.
  private var screenCaptureGuard: ScreenCaptureGuard?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ScreenCaptureGuard") {
      screenCaptureGuard = ScreenCaptureGuard(messenger: registrar.messenger())
    }
  }
}

/// 승인제 파티 신청자의 제출 사진을 iOS에서 **가능한 만큼** 지키는 쪽.
///
/// Android의 `FLAG_SECURE`에 해당하는 것이 iOS에는 없다. 스크린샷도 화면
/// 녹화도 OS 수준에서 막을 방법이 없어서, 할 수 있는 세 가지만 한다.
///
///   1. 녹화·미러링 감지 — `UIScreen.isCaptured`가 켜지면 Flutter에 알려
///      사진을 즉시 가린다. 녹화에 찍히는 것은 합성된 화면이라, 가린 그림이
///      찍힌다.
///   2. App Switcher 미리보기 — 앱이 내려가기 직전에 창 전체를 덮개로 덮고,
///      돌아오면 걷는다. iOS가 그 사이에 찍는 미리보기에는 덮개만 남는다.
///   3. 스크린샷 감지 — **찍힌 뒤**에 알 수 있을 뿐이라 막지는 못하고,
///      Flutter가 "찍혔다"고 안내하도록 알리기만 한다.
///
/// 셋 다 보호가 켜져 있는 동안(=신청자 사진 화면이 떠 있는 동안)에만 돈다.
/// 앱 전체를 늘 덮어 두면 다른 화면의 정상적인 캡처까지 죽는다.
final class ScreenCaptureGuard: NSObject, FlutterStreamHandler {
  private static let channelName = "kr.co.partychu.app/screen_capture_guard"

  private var eventSink: FlutterEventSink?

  /// 지금 보호를 요청받은 상태인가(Flutter의 `ScreenCaptureGuard`가 잡고 있는가).
  private var active = false

  /// App Switcher 미리보기를 가리는 덮개. 덮여 있는 동안에만 값이 있다.
  private weak var shield: UIView?

  init(messenger: FlutterBinaryMessenger) {
    super.init()

    FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        guard let self = self else { return result(nil) }
        switch call.method {
        case "enable":
          self.active = true
          // 이미 녹화 중인 상태에서 화면을 열었을 수도 있다 — 지금 상태를
          // 그대로 돌려줘야 첫 프레임부터 가려진다.
          result(self.isCaptured)
        case "disable":
          self.active = false
          self.hideShield()
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }

    FlutterEventChannel(
      name: "\(Self.channelName)/events", binaryMessenger: messenger
    ).setStreamHandler(self)

    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(capturedDidChange),
      name: UIScreen.capturedDidChangeNotification, object: nil)
    center.addObserver(
      self, selector: #selector(didTakeScreenshot),
      name: UIApplication.userDidTakeScreenshotNotification, object: nil)

    // 앱이 내려가는 신호는 씬 기반(iOS 13+)과 앱 기반이 따로 온다. 어느 쪽이
    // 오든 같은 일을 하고, 두 번 와도 덮개는 하나뿐이라 그대로 둬도 된다.
    for name in [
      UIApplication.willResignActiveNotification,
      UIScene.willDeactivateNotification,
    ] {
      center.addObserver(self, selector: #selector(willHide), name: name, object: nil)
    }
    for name in [
      UIApplication.didBecomeActiveNotification,
      UIScene.didActivateNotification,
    ] {
      center.addObserver(self, selector: #selector(didShow), name: name, object: nil)
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: - 녹화·미러링

  /// 앱이 실제로 올라와 있는 화면. `UIScreen.main`은 iOS 16부터 권장되지
  /// 않아, 활성 씬의 화면으로만 판정한다(씬이 없으면 볼 화면도 없다).
  private var currentScreen: UIScreen? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    return scene?.screen
  }

  private var isCaptured: Bool { currentScreen?.isCaptured ?? false }

  @objc private func capturedDidChange() {
    guard active else { return }
    eventSink?(["captured": isCaptured])
  }

  @objc private func didTakeScreenshot() {
    guard active else { return }
    eventSink?(["screenshot": true])
  }

  // MARK: - App Switcher 미리보기

  @objc private func willHide() {
    guard active, shield == nil else { return }
    guard let window = keyWindow else { return }
    let cover = UIView(frame: window.bounds)
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    // 반투명이면 미리보기에 사진이 비친다 — 불투명이어야 한다.
    cover.backgroundColor = UIColor(red: 0.078, green: 0.078, blue: 0.102, alpha: 1)

    let label = UILabel()
    label.text = "🔒 신청자 사진 보호 중"
    label.textColor = UIColor.white.withAlphaComponent(0.7)
    label.font = .systemFont(ofSize: 15, weight: .semibold)
    label.translatesAutoresizingMaskIntoConstraints = false
    cover.addSubview(label)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: cover.centerYAnchor),
    ])

    window.addSubview(cover)
    shield = cover
  }

  @objc private func didShow() {
    hideShield()
    // 앱이 내려가 있는 동안 녹화가 시작·종료됐을 수 있다. 그 사이의
    // 알림은 놓칠 수 있으므로 돌아온 시점의 상태를 다시 알린다.
    guard active else { return }
    eventSink?(["captured": isCaptured])
  }

  private func hideShield() {
    shield?.removeFromSuperview()
    shield = nil
  }

  private var keyWindow: UIWindow? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
      ?? UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first
  }

  // MARK: - FlutterStreamHandler

  func onListen(
    withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 본인확인 인증번호 문자를 **사용자 동의로** 받아 "복사" 버튼에 쓸 값만 들고 있는다.
///
/// ── 어디에 쓰이나 ────────────────────────────────────────────────────────
/// NICE 표준창은 WebView 안의 웹페이지라 우리 앱에 인증번호 입력칸이 없다.
/// 그래서 자동 입력이 아니라 **복사를 쉽게** 해 주는 쪽으로 돕는다 —
/// 문자가 오면 화면 위에 인증번호와 "복사" 버튼을 띄우고
/// ([SmsCodeCopyBanner]), 사용자가 버튼을 눌러 복사한 뒤 입력칸에 붙여넣는다.
///
/// ── 지키는 선 ───────────────────────────────────────────────────────────
/// · **Android 전용**이다([isSupported]). iOS는 WKWebView가
///   `autocomplete="one-time-code"`를 보고 키보드에서 직접 제안하므로
///   이 경로가 필요 없다(`webview_otp_autofill.dart`).
/// · **클립보드는 [copyToClipboard]를 부를 때만** 쓴다. 문자가 도착하는
///   것만으로는 아무것도 복사하지 않는다.
/// · **시스템 클립보드를 비우지 않는다.** 화면을 떠날 때 지우는 것은 앱이
///   들고 있던 값뿐이다([dispose]) — 사용자가 복사한 뒤 화면을 벗어나도
///   붙여넣기가 깨지지 않게 한다.
/// · 인증번호는 **이 클래스 안에만** 있다. 화면은 "도착했다"는 사실만 받고
///   값을 위젯 트리에 넣지 않는다 — 숫자가 화면이나 스크린샷에 남지 않는다
///   ([SmsCodeCopyBanner]는 인증번호를 인자로 받지도 않는다).
/// · ⚠️ **문자 본문도 인증번호도 로그에 남기지 않는다.** 아래 [debugPrint]는
///   전부 실패 사유만 찍는다.
/// · NICE 인증 페이지의 입력값·DOM·인증 로직에는 손대지 않는다. 이 클래스는
///   WebView를 모른다.
/// · [dispose]가 수신 창을 닫고 들고 있던 인증번호를 비운다.
///
/// 문자를 못 받거나 사용자가 동의를 거부하면 **아무 일도 하지 않는다** —
/// 배너가 뜨지 않고, 기존 수동 입력 흐름이 그대로 남는다.
///
/// ── ⚠️ 실기기 검증 전: NICE 문자와의 호환은 **미확인** ──────────────────
/// SMS User Consent API는 문자를 아무 것이나 주지 않는다. 구글 문서 기준으로
/// 다음을 모두 만족해야 매칭된다:
///   · [start] 호출 **이후**에 도착한 문자 (약 5분 창)
///   · 발신번호가 사용자 연락처에 **없어야** 함
///   · 본문에 4~10자 영숫자 코드가 있고 그중 숫자가 1자 이상
///
/// NICE가 실제로 보내는 인증번호 문자가 이 조건을 만족하는지는 **아직
/// 확인하지 못했다** — 실기기에서 본인확인을 한 번 돌려 동의 다이얼로그가
/// 뜨는지 봐야 안다. 만족하지 않으면 이 경로는 조용히 동작하지 않고,
/// 기존 수동 입력이 그대로 쓰인다(기능이 깨지지는 않는다).
///
/// [extractVerificationCode]의 추출 규칙도 같다 — 단위 테스트는 흔한 국내
/// 인증 문자 형태로 고정해 뒀지만, **NICE의 실제 문구는 확인 전이다.**
class SmsConsentService {
  SmsConsentService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_handleNative);
  }

  static const String channelName = 'kr.co.partychu.app/sms_consent';

  final MethodChannel _channel;

  /// 이 경로를 쓸 수 있는 플랫폼인가 — Android만.
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 지금 보여 줄 인증번호(없으면 null). 배너가 이 값을 읽는다.
  String? get code => _code;
  String? _code;

  /// 인증번호가 새로 들어왔을 때 화면을 다시 그리라고 알린다.
  VoidCallback? onCodeChanged;

  bool _disposed = false;

  // ── 수신 창 ──────────────────────────────────────────────────────────

  /// 문자 수신 창을 연다(약 5분). 본인확인 화면이 페이지를 넘길 때마다 다시
  /// 불러 창을 갱신한다 — 인증번호 문자는 사용자가 정보를 넣은 **뒤에**
  /// 오므로, 화면을 열 때 한 번만 열어 두면 창이 먼저 닫힐 수 있다.
  Future<void> start() async {
    if (!isSupported || _disposed) return;
    try {
      await _channel.invokeMethod<bool>('start');
    } on PlatformException catch (e) {
      // Play 서비스가 없는 기기 등 — 수동 입력으로 간다.
      debugPrint('[SmsConsent] 수신 창 열기 실패(non-fatal): ${e.code}');
    } on MissingPluginException {
      // 네이티브 브리지가 없는 빌드(테스트 등).
      debugPrint('[SmsConsent] 네이티브 브리지 없음 — 건너뜀');
    }
  }

  /// 수신 창을 닫고 들고 있던 인증번호를 **비운다.**
  Future<void> stop() async {
    final had = _code != null;
    _code = null;
    if (had) onCodeChanged?.call();
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException catch (e) {
      debugPrint('[SmsConsent] 수신 창 닫기 실패(non-fatal): ${e.code}');
    } on MissingPluginException {
      // 열린 적이 없으면 닫을 것도 없다.
    }
  }

  /// 화면을 떠날 때 부른다 — 수신 창을 닫고 인증번호를 지운다.
  Future<void> dispose() async {
    _disposed = true;
    onCodeChanged = null;
    await stop();
    _channel.setMethodCallHandler(null);
  }

  // ── 네이티브 → Dart ──────────────────────────────────────────────────

  Future<void> _handleNative(MethodCall call) async {
    if (_disposed) return;
    switch (call.method) {
      case 'onSmsReceived':
        // ⚠️ 본문을 찍지 않는다.
        final body = call.arguments as String?;
        final extracted = extractVerificationCode(body ?? '');
        if (extracted == null) {
          debugPrint('[SmsConsent] 문자에서 인증번호를 찾지 못함 — 수동 입력 유지');
          return;
        }
        _code = extracted;
        onCodeChanged?.call();
      case 'onUnavailable':
        // 사용자가 동의를 거부했거나 수신 창이 만료됐다. 사유만 남긴다.
        debugPrint('[SmsConsent] 사용 불가: ${call.arguments}');
      default:
        break;
    }
  }

  // ── 클립보드 ─────────────────────────────────────────────────────────

  /// **버튼을 눌렀을 때만** 호출된다. 복사에 성공하면 true.
  Future<bool> copyToClipboard() async {
    final value = _code;
    if (value == null) return false;
    try {
      await Clipboard.setData(ClipboardData(text: value));
      return true;
    } catch (e) {
      // 값은 찍지 않는다.
      debugPrint('[SmsConsent] 복사 실패: ${e.runtimeType}');
      return false;
    }
  }

  // ── 인증번호 추출 ────────────────────────────────────────────────────

  /// 문자 본문에서 인증번호만 뽑는다. 찾지 못하면 null(= 배너를 띄우지 않음).
  ///
  /// 순서가 중요하다:
  ///   1. "인증번호" 같은 **라벨 뒤**의 숫자를 먼저 본다. 본문에 발신번호나
  ///      금액이 섞여 있어도 엉뚱한 숫자를 집지 않는다.
  ///   2. 라벨이 없으면 독립된 4~8자리 숫자 중 **6자리를 우선**한다(국내
  ///      본인확인 인증번호가 6자리다).
  ///
  /// 9자리 이상 숫자는 후보에서 제외된다 — 전화번호·사업자번호가 그 길이다.
  static String? extractVerificationCode(String body) {
    if (body.isEmpty) return null;

    final labeled = RegExp(
      r'(?:인증\s*번호|인증\s*코드|확인\s*번호|verification\s*code|auth(?:entication)?\s*code|otp)'
      r'\D{0,12}(\d{4,8})(?!\d)',
      caseSensitive: false,
    ).firstMatch(body);
    if (labeled != null) return labeled.group(1);

    final candidates = RegExp(r'(?<!\d)(\d{4,8})(?!\d)')
        .allMatches(body)
        .map((m) => m.group(1)!)
        .toList(growable: false);
    if (candidates.isEmpty) return null;

    for (final candidate in candidates) {
      if (candidate.length == 6) return candidate;
    }
    return candidates.first;
  }
}

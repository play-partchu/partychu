// 📩 본인확인 인증번호 문자 — 사용자 동의 수신 + "복사" 버튼.
//
// 여기서 지키는 것은 두 가지다.
//
//  1. **인증번호가 밖으로 나가지 않는다.** 로그에도, 분석 서비스에도, NICE
//     인증 페이지의 DOM에도. 클립보드는 사용자가 버튼을 눌렀을 때만 쓴다.
//  2. **실패하면 조용히 비켜난다.** 문자를 못 받거나 동의를 거부하면 배너가
//     뜨지 않고 기존 수동 입력 흐름이 그대로 남아야 한다.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/services/sms_consent_service.dart';
import 'package:party_app/widgets/sms_code_copy_banner.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

/// 주석을 걷어낸 소스.
///
/// "이 클래스는 WebView를 모른다" 같은 **설명문**이 "WebView를 쓴다"로 오판되면
/// 감사가 제 역할을 못 한다. 실제로 호출하는 코드만 남겨 놓고 본다.
String _codeOnly(String path) => _read(path)
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .split('\n')
    .map((line) {
      final comment = line.indexOf('//');
      return comment < 0 ? line : line.substring(0, comment);
    })
    .join('\n');

const _channel = MethodChannel(SmsConsentService.channelName);
const _kKotlinBridge =
    'android/app/src/main/kotlin/kr/co/partychu/app/SmsConsentBridge.kt';

TestDefaultBinaryMessenger get messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

/// 네이티브가 Dart로 올려 보내는 호출을 흉내낸다.
Future<void> sendFromNative(MethodCall call) => messenger.handlePlatformMessage(
  SmsConsentService.channelName,
  const StandardMethodCodec().encodeMethodCall(call),
  (_) {},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('인증번호 추출', () {
    test('라벨이 있으면 라벨 뒤 숫자를 집는다', () {
      const cases = {
        '[NICE] 인증번호 [123456] 입력해주세요': '123456',
        '인증번호 483920를 입력해주세요': '483920',
        '인증번호: 1234': '1234',
        '[Web발신] 인증 번호 775533 (3분 내 입력)': '775533',
        '확인번호 9087 입력': '9087',
        'Your OTP is 246802': '246802',
      };
      cases.forEach((body, expected) {
        expect(
          SmsConsentService.extractVerificationCode(body),
          expected,
          reason: '"$body" 에서 $expected 를 뽑지 못했다',
        );
      });
    });

    test('본문에 전화번호가 섞여 있어도 라벨 쪽을 집는다', () {
      // 라벨을 먼저 보는 이유가 이것이다 — 고객센터 번호를 인증번호로
      // 착각하면 사용자가 잘못된 값을 붙여넣는다.
      expect(
        SmsConsentService.extractVerificationCode(
          '[파티츄] 문의 0220001234 / 인증번호 556677',
        ),
        '556677',
      );
    });

    test('라벨이 없으면 6자리를 우선한다 — 국내 본인확인이 6자리다', () {
      expect(
        SmsConsentService.extractVerificationCode('고객센터 15881234 코드 445566'),
        '445566',
      );
      expect(
        SmsConsentService.extractVerificationCode('본인확인 847261 유효시간 3분'),
        '847261',
      );
    });

    test('9자리 이상 숫자는 후보가 아니다 — 전화번호·사업자번호가 그 길이다', () {
      expect(
        SmsConsentService.extractVerificationCode('발신 01012345678'),
        isNull,
      );
      expect(
        SmsConsentService.extractVerificationCode('사업자 1234567890 안내'),
        isNull,
      );
    });

    test('찾지 못하면 null — 배너를 띄우지 않는다', () {
      for (final body in [
        '',
        '인증 안내 문자입니다',
        '코드 12',
        '   ',
        '한글만 있는 문자',
      ]) {
        expect(
          SmsConsentService.extractVerificationCode(body),
          isNull,
          reason: '"$body" 에서 엉뚱한 값을 뽑았다',
        );
      }
    });
  });

  group('플랫폼 — Android만', () {
    final original = debugDefaultTargetPlatformOverride;
    tearDown(() => debugDefaultTargetPlatformOverride = original);

    test('Android면 열린다', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(SmsConsentService.isSupported, isTrue);
    });

    test('iOS에서는 닫혀 있다 — 키보드 자동완성이 대신한다', () {
      for (final platform in [
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(
          SmsConsentService.isSupported,
          isFalse,
          reason: '$platform 에 문자 수신 경로가 생겼다',
        );
      }
    });

    test('kIsWeb이 판정에 들어 있다', () {
      // VM에서 kIsWeb을 바꿀 수 없어 소스로 확인한다.
      expect(_read('lib/services/sms_consent_service.dart'), contains('!kIsWeb'));
    });
  });

  group('수신 창과 상태', () {
    late List<MethodCall> calls;
    late SmsConsentService service;
    final original = debugDefaultTargetPlatformOverride;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        return null;
      });
      service = SmsConsentService();
    });

    tearDown(() async {
      messenger.setMockMethodCallHandler(_channel, null);
      debugDefaultTargetPlatformOverride = original;
    });

    test('start가 네이티브 수신 창을 연다', () async {
      await service.start();
      expect(calls.map((c) => c.method), ['start']);
    });

    test('문자가 오면 인증번호를 들고 화면에 알린다', () async {
      var notified = 0;
      service.onCodeChanged = () => notified++;
      await sendFromNative(const MethodCall('onSmsReceived', '인증번호 135791 입력'));
      expect(service.code, '135791');
      expect(notified, 1);
    });

    test('인증번호를 못 뽑으면 상태가 그대로다 — 수동 입력 유지', () async {
      var notified = 0;
      service.onCodeChanged = () => notified++;
      await sendFromNative(const MethodCall('onSmsReceived', '광고 문자입니다'));
      expect(service.code, isNull);
      expect(notified, 0, reason: '뽑은 것이 없는데 화면을 깨웠다');
    });

    test('동의 거부·만료는 아무 상태도 만들지 않는다', () async {
      await sendFromNative(const MethodCall('onUnavailable', 'declined'));
      expect(service.code, isNull);
      await sendFromNative(const MethodCall('onUnavailable', 'timeout'));
      expect(service.code, isNull);
    });

    test('stop이 수신 창을 닫고 인증번호를 비운다', () async {
      await sendFromNative(const MethodCall('onSmsReceived', '인증번호 112233'));
      expect(service.code, '112233');
      calls.clear();
      await service.stop();
      expect(service.code, isNull, reason: '인증번호가 남아 있다');
      expect(calls.map((c) => c.method), ['stop']);
    });

    test('dispose가 인증번호를 지우고 수신 창을 닫는다 — 요구사항 5', () async {
      await sendFromNative(const MethodCall('onSmsReceived', '인증번호 445566'));
      calls.clear();
      await service.dispose();
      expect(service.code, isNull);
      expect(calls.map((c) => c.method), contains('stop'));
    });

    test('dispose 뒤에 올라온 문자는 무시한다', () async {
      await service.dispose();
      await sendFromNative(const MethodCall('onSmsReceived', '인증번호 999888'));
      expect(service.code, isNull);
    });

    test('네이티브 브리지가 없어도 예외가 올라오지 않는다', () async {
      messenger.setMockMethodCallHandler(_channel, null);
      await expectLater(service.start(), completes);
      await expectLater(service.stop(), completes);
    });
  });

  group('클립보드는 버튼을 눌렀을 때만', () {
    late List<MethodCall> platformCalls;
    late SmsConsentService service;
    final original = debugDefaultTargetPlatformOverride;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      platformCalls = <MethodCall>[];
      messenger.setMockMethodCallHandler(_channel, (_) async => null);
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        platformCalls.add(call);
        return null;
      });
      service = SmsConsentService();
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(_channel, null);
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      debugDefaultTargetPlatformOverride = original;
    });

    test('문자가 도착하는 것만으로는 복사하지 않는다 — 요구사항 2', () async {
      await sendFromNative(const MethodCall('onSmsReceived', '인증번호 314159'));
      expect(
        platformCalls.where((c) => c.method == 'Clipboard.setData'),
        isEmpty,
        reason: '사용자가 누르지 않았는데 클립보드에 썼다',
      );
    });

    test('버튼을 누르면 그 인증번호를 복사한다', () async {
      await sendFromNative(const MethodCall('onSmsReceived', '인증번호 314159'));
      expect(await service.copyToClipboard(), isTrue);
      final copy = platformCalls.firstWhere(
        (c) => c.method == 'Clipboard.setData',
      );
      expect((copy.arguments as Map)['text'], '314159');
    });

    test('인증번호가 없으면 복사하지 않는다', () async {
      expect(await service.copyToClipboard(), isFalse);
      expect(
        platformCalls.where((c) => c.method == 'Clipboard.setData'),
        isEmpty,
      );
    });
  });

  group('인증번호를 기록하지 않는다 — 요구사항 4', () {
    final dart = _codeOnly('lib/services/sms_consent_service.dart');

    test('Dart가 문자 본문·인증번호를 로그에 찍지 않는다', () {
      for (final token in ['body', 'extracted', '_code', 'value']) {
        expect(
          RegExp('debugPrint\\([^;]*\\\$\\{?$token').hasMatch(dart),
          isFalse,
          reason: 'debugPrint가 $token 을 찍고 있다',
        );
      }
    });

    test('분석·크래시 리포팅 서비스를 쓰지 않는다', () {
      for (final forbidden in [
        'firebase_analytics',
        'firebase_crashlytics',
        'logEvent',
        'recordError',
      ]) {
        expect(dart.contains(forbidden), isFalse, reason: '$forbidden 을 쓰고 있다');
      }
    });

    test('Kotlin이 문자 본문을 로그에 찍지 않는다', () {
      final kotlin = _codeOnly(_kKotlinBridge);
      expect(
        RegExp(r'Log\.[a-z]+\([^)]*message').hasMatch(kotlin),
        isFalse,
        reason: 'Log 호출에 문자 본문이 들어갔다',
      );
      // 본문은 꺼낸 즉시 Dart로만 넘긴다.
      expect(kotlin, contains('SmsRetriever.EXTRA_SMS_MESSAGE'));
      expect(kotlin, contains("channel.invokeMethod(\"onSmsReceived\", message)"));
    });
  });

  group('NICE 인증 로직을 건드리지 않는다 — 요구사항 3', () {
    test('Kotlin 브리지가 WebView를 모른다', () {
      final kotlin = _codeOnly(_kKotlinBridge);
      for (final forbidden in ['WebView', 'evaluateJavascript', 'loadUrl']) {
        expect(kotlin.contains(forbidden), isFalse, reason: '$forbidden 을 쓰고 있다');
      }
    });

    test('Dart 서비스가 WebView를 모른다', () {
      final dart = _codeOnly('lib/services/sms_consent_service.dart');
      for (final forbidden in [
        'WebView',
        'webview_flutter',
        'runJavaScript',
      ]) {
        expect(dart.contains(forbidden), isFalse, reason: '$forbidden 을 쓰고 있다');
      }
    });

    test('자동완성 주입 스크립트는 여전히 값을 쓰지 않는다 — 요구사항 7', () {
      // iOS 경로가 그대로 남아 있는지 함께 확인한다.
      final autofill = _read('lib/services/webview_otp_autofill.dart');
      expect(autofill, contains("autocomplete', 'one-time-code'"));
      expect(RegExp(r'\.value\s*=(?!=)').hasMatch(autofill), isFalse);
    });

    test('본인확인 화면의 콜백 처리가 그대로다', () {
      final screen = _read('lib/screens/nice_auth_verification_screen.dart');
      expect(screen, contains('if (req.url.startsWith(_kNiceReturnUrl))'));
      expect(screen, contains('_startResultCheck(webTransactionId)'));
      expect(screen, contains('_isProcessingResult'));
      // iOS 자동완성 주입도 유지.
      expect(screen, contains('WebViewOtpAutofill.apply(ctrl)'));
      // 배너는 화면을 떠날 때 정리된다.
      expect(screen, contains('_smsConsent?.dispose()'));
    });
  });

  group('인증번호를 화면에 띄우지 않는다 — 요구사항 1', () {
    test('배너는 인증번호를 인자로 받지도 않는다', () {
      final src = _codeOnly('lib/widgets/sms_code_copy_banner.dart');
      expect(src.contains('this.code'), isFalse);
      expect(
        RegExp(r'final\s+String\s+code').hasMatch(src),
        isFalse,
        reason: '배너가 인증번호를 들고 있다 — 화면에 뜰 수 있다',
      );
    });

    test('화면도 인증번호 값을 들지 않는다 — 도착 여부만 안다', () {
      final screen = _codeOnly(
        'lib/screens/nice_auth_verification_screen.dart',
      );
      // 값을 담는 필드가 없어야 한다(_smsCodeReady·_smsCodeCopied만 둔다).
      expect(
        RegExp(r'_smsCode\b(?!Ready|Copied)').hasMatch(screen),
        isFalse,
        reason: '화면이 인증번호 값을 필드에 담고 있다',
      );
      // 서비스에서 꺼내는 것은 null 여부뿐이다.
      expect(screen, contains('service.code != null'));
      // 배너 호출에 code 인자가 없다.
      expect(
        RegExp(r'SmsCodeCopyBanner\(\s*copied:').hasMatch(screen),
        isTrue,
        reason: '배너에 인증번호를 넘기고 있다',
      );
    });
  });

  group('클립보드를 자동으로 비우지 않는다 — 요구사항 3', () {
    final dart = _codeOnly('lib/services/sms_consent_service.dart');
    final screen = _codeOnly('lib/screens/nice_auth_verification_screen.dart');

    test('빈 값으로 클립보드를 덮어쓰지 않는다', () {
      for (final src in {'서비스': dart, '화면': screen}.entries) {
        expect(
          RegExp("""ClipboardData\\(\\s*text:\\s*['"]['"]""").hasMatch(src.value),
          isFalse,
          reason: '${src.key}가 빈 문자열로 클립보드를 비우고 있다',
        );
      }
    });

    test('클립보드에 쓰는 곳은 copyToClipboard 한 곳뿐이다', () {
      expect(dart.split('Clipboard.setData').length - 1, 1);
      // 화면은 서비스의 copyToClipboard()만 부른다 — 직접 쓰지 않는다.
      expect(
        screen.contains('Clipboard.setData'),
        isFalse,
        reason: '화면이 직접 클립보드에 쓰고 있다 — 복사 경로가 둘이 된다',
      );
      expect(screen, contains('copyToClipboard()'));
    });
  });

  group('복사 줄이 표준창을 덮지 않는다 — 요구사항 4', () {
    final screen = _read('lib/screens/nice_auth_verification_screen.dart');
    final body = screen.substring(screen.indexOf('body: Column('));

    test('오버레이가 아니라 Column에서 자리를 따로 받는다', () {
      expect(
        screen,
        contains('body: Column('),
        reason: '본문이 Column이 아니다 — 복사 줄이 다시 WebView 위로 떴을 수 있다',
      );
      final banner = body.indexOf('SmsCodeCopyBanner(');
      expect(banner, greaterThan(-1), reason: '복사 줄이 사라졌다');
      expect(
        body.indexOf('Expanded('),
        greaterThan(banner),
        reason: '복사 줄이 WebView 영역 뒤로 갔다',
      );
      expect(
        body.indexOf('Stack('),
        greaterThan(banner),
        reason: '복사 줄이 WebView Stack 안으로 들어갔다 — 표준창을 덮을 수 있다',
      );
    });

    test('WebView는 남은 공간을 Expanded로 받는다', () {
      final expanded = body.indexOf('Expanded(');
      final webView = body.indexOf('WebViewWidget(');
      expect(webView, greaterThan(expanded), reason: 'WebView가 Expanded 밖으로 나갔다');
    });

    test('로딩 오버레이에 가려지는 동안에는 띄우지 않는다', () {
      expect(
        screen,
        contains('_smsCodeReady && _isWebViewVisible && !_loading && !_completing'),
      );
    });
  });

  group('SMS 권한을 요구하지 않는다', () {
    test('매니페스트에 SMS 권한이 없다 — User Consent API는 권한이 필요 없다', () {
      final manifest = _read('android/app/src/main/AndroidManifest.xml');
      for (final permission in ['READ_SMS', 'RECEIVE_SMS', 'READ_PHONE_STATE']) {
        expect(
          manifest.contains(permission),
          isFalse,
          reason: '$permission 이 들어갔다 — 스토어 심사에서 문제가 된다',
        );
      }
    });

    test('SmsRetriever가 아니라 User Consent를 쓴다', () {
      final kotlin = _read(_kKotlinBridge);
      // startSmsRetriever는 문자 본문에 앱 해시를 요구해 이 경우 쓸 수 없다.
      expect(kotlin.contains('startSmsRetriever'), isFalse);
      expect(kotlin, contains('startSmsUserConsent(null)'));
    });

    test('의존성이 build.gradle.kts에 들어 있다', () {
      expect(
        _read('android/app/build.gradle.kts'),
        contains('play-services-auth-api-phone'),
      );
    });

    test('MainActivity가 동의 결과를 넘겨받고 정리한다', () {
      final main = _read(
        'android/app/src/main/kotlin/kr/co/partychu/app/MainActivity.kt',
      );
      expect(main, contains('SmsConsentBridge(this'));
      expect(main, contains('smsConsent?.onActivityResult('));
      expect(main, contains('smsConsent?.dispose()'));
      // 우리 요청이 아니면 평소대로 넘긴다 — 소셜 로그인이 이 경로를 쓴다.
      expect(main, contains('super.onActivityResult(requestCode, resultCode, data)'));
    });
  });

  group('복사 배너', () {
    Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('도착 안내와 복사하기 버튼만 보여 준다', (tester) async {
      await tester.pumpWidget(
        host(SmsCodeCopyBanner(onCopy: () {}, onDismiss: () {})),
      );
      expect(find.text('인증번호가 도착했어요'), findsOneWidget);
      expect(find.text('복사하기'), findsOneWidget);
    });

    testWidgets('인증번호 숫자를 화면에 띄우지 않는다', (tester) async {
      // 이 위젯은 인증번호를 **받지도 않는다.** 아래 단정은 그 사실을 화면
      // 쪽에서 한 번 더 확인한다 — 숫자가 섞여 들어오면 깨진다.
      await tester.pumpWidget(
        host(SmsCodeCopyBanner(copied: true, onCopy: () {}, onDismiss: () {})),
      );
      final digits = RegExp(r'\d{4,8}');
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        final data = text.data ?? '';
        expect(
          digits.hasMatch(data),
          isFalse,
          reason: '배너에 인증번호로 보이는 숫자가 떴다: "$data"',
        );
      }
    });

    testWidgets('복사하기는 한 번 누르면 한 번만 알린다', (tester) async {
      var copied = 0;
      await tester.pumpWidget(
        host(SmsCodeCopyBanner(onCopy: () => copied++, onDismiss: () {})),
      );
      await tester.tap(find.text('복사하기'));
      await tester.pump();
      expect(copied, 1);
    });

    testWidgets('닫기를 누르면 알린다', (tester) async {
      var dismissed = 0;
      await tester.pumpWidget(
        host(SmsCodeCopyBanner(onCopy: () {}, onDismiss: () => dismissed++)),
      );
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(dismissed, 1);
    });

    testWidgets('복사한 뒤에는 붙여넣기 안내로 바뀐다', (tester) async {
      await tester.pumpWidget(
        host(SmsCodeCopyBanner(copied: true, onCopy: () {}, onDismiss: () {})),
      );
      expect(find.textContaining('붙여넣기'), findsOneWidget);
      expect(find.text('인증번호가 도착했어요'), findsNothing);
    });

    testWidgets('좁은 화면에서도 넘치지 않는다', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        host(SmsCodeCopyBanner(copied: true, onCopy: () {}, onDismiss: () {})),
      );
      expect(tester.takeException(), isNull);
    });

    test('배너가 스스로 클립보드를 건드리지 않는다', () {
      // 복사는 화면이 서비스를 통해서만 한다 — 위젯은 눌렸다고 알릴 뿐이다.
      final src = _codeOnly('lib/widgets/sms_code_copy_banner.dart');
      for (final forbidden in [
        'Clipboard.setData',
        'SystemChannels',
        'MethodChannel',
      ]) {
        expect(src.contains(forbidden), isFalse, reason: '$forbidden 을 쓰고 있다');
      }
    });
  });
}

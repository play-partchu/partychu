// 🔐 NICE 표준창(WebView) 인증번호 자동완성 힌트.
//
// 여기서 지키는 것은 **주입 스크립트의 범위**다. 이 스크립트는 남의 인증
// 페이지 안에서 돈다. 조금만 넓어지면 "인증번호를 코드가 대신 넣는" 것이
// 되고, 그 순간 본인확인의 의미가 사라진다.
//
// 그래서 값에 손대는 코드가 하나라도 들어오면 여기서 깨지게 해 둔다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:party_app/services/webview_otp_autofill.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

/// 주입 스크립트 원문 — 서비스 파일에서 그대로 읽어 검사한다.
final String _script = _read('lib/services/webview_otp_autofill.dart');

void main() {
  group('스크립트는 인증번호에 손대지 않는다', () {
    test('입력값을 쓰는 코드가 없다 — 자동 입력이 아니라 제안일 뿐이다', () {
      // `el.value = ...` / `setAttribute('value', ...)` 둘 다 막는다.
      expect(
        RegExp(r'\.value\s*=(?!=)').hasMatch(_script),
        isFalse,
        reason: '스크립트가 입력칸에 값을 쓰고 있다 — 인증번호를 코드가 대신 넣는 구조가 됐다',
      );
      expect(
        RegExp("""setAttribute\\(\\s*['"]value['"]""").hasMatch(_script),
        isFalse,
        reason: 'value 속성을 쓰고 있다',
      );
    });

    test('입력값을 읽는 코드가 없다 — 인증번호를 앱이 가져가지 않는다', () {
      expect(
        RegExp(r'\.value\b(?!\s*=)').hasMatch(_script),
        isFalse,
        reason: '스크립트가 입력칸 값을 읽고 있다',
      );
    });

    test('폼을 대신 제출하지 않는다 — 확인 버튼은 사용자가 누른다', () {
      for (final forbidden in ['.submit(', '.click(', 'requestSubmit']) {
        expect(
          _script.contains(forbidden),
          isFalse,
          reason: '스크립트가 $forbidden 로 인증 절차를 대신 진행한다',
        );
      }
    });

    test('서버 검증에 쓰이는 속성은 건드리지 않는다', () {
      // NICE가 이 값들로 검증하므로 바꾸면 인증이 깨진다.
      for (final attr in ['type', 'name', 'maxlength', 'pattern', 'form']) {
        expect(
          RegExp("""setAttribute\\(\\s*['"]$attr['"]""").hasMatch(_script),
          isFalse,
          reason: '$attr 속성을 덮어쓰고 있다 — NICE 서버 검증이 깨질 수 있다',
        );
      }
    });

    test('쓰는 속성은 표시 힌트 세 개뿐이다', () {
      final written = RegExp(r"""setAttribute\(\s*'([a-z-]+)'""")
          .allMatches(_script)
          .map((m) => m.group(1))
          .toSet();
      expect(written, {'autocomplete', 'inputmode'});
      // 선택 허용은 style로만 — 레이아웃·동작에 영향이 없는 표시 속성이다.
      expect(_script, contains('style.userSelect'));
    });
  });

  group('입력칸 판별 — 엉뚱한 칸에 붙지 않는다', () {
    test('휴대폰번호·생년월일·이름 칸은 제외 목록에 있다', () {
      // 이 칸에 one-time-code가 붙으면 키보드가 그 자리에 SMS 인증번호를
      // 제안해 사용자를 헷갈리게 만든다.
      final deny = RegExp(r'var DENY = /\((.+?)\)/i').firstMatch(_script);
      expect(deny, isNotNull, reason: '제외 목록이 사라졌다');
      final terms = deny!.group(1)!;
      for (final term in [
        'phone',
        'mobile',
        'tel',
        'birth',
        'name',
        '휴대',
        '전화',
        '생년',
        '이름',
      ]) {
        expect(terms, contains(term), reason: '$term 이 제외 목록에서 빠졌다');
      }
    });

    test('허용 단서에 인증번호 어휘가 들어 있다', () {
      final allow = RegExp(r'var ALLOW = /\((.+?)\)/i').firstMatch(_script);
      expect(allow, isNotNull);
      for (final term in ['otp', 'auth', 'cert', 'sms', '인증']) {
        expect(allow!.group(1)!, contains(term));
      }
    });

    test('제외 목록을 허용 단서보다 먼저 본다', () {
      // 순서가 뒤집히면 "인증용 휴대폰번호" 같은 칸이 통과한다.
      final denyAt = _script.indexOf('if (DENY.test(clues)) return false;');
      final allowAt = _script.indexOf('if (!ALLOW.test(clues)) return false;');
      expect(denyAt, greaterThan(-1));
      expect(allowAt, greaterThan(-1));
      expect(denyAt, lessThan(allowAt));
    });

    test('길이 4~8자만 — 11자 휴대폰번호 칸이 걸러진다', () {
      expect(_script, contains('max < 4 || max > 8'));
    });
  });

  group('실패해도 인증을 막지 않는다', () {
    test('교차 출처 iframe 접근은 try/catch로 감싸져 있다', () {
      // 브라우저가 막는 정상 상황이다 — 예외가 올라가면 안 된다.
      final frameBlock = _script.substring(
        _script.indexOf("querySelectorAll('iframe, frame')"),
      );
      expect(frameBlock, contains('catch (e) { blockedFrames++; }'));
    });

    test('주입 실패를 Dart 쪽에서 삼킨다', () {
      expect(_script, contains('catch (e)'));
      expect(
        _script,
        contains("debugPrint('[OtpAutofill] 힌트 주입 생략(non-fatal): \$e')"),
      );
    });

    test('MutationObserver가 속성 변경을 관찰하지 않는다 — 자기 자신을 다시 부르면 무한 루프다', () {
      expect(_script, contains('{ childList: true, subtree: true }'));
      expect(
        RegExp(r'observe\([^)]*attributes:\s*true').hasMatch(_script),
        isFalse,
        reason: '속성 변경을 관찰하면 setAttribute가 observer를 다시 깨운다',
      );
    });
  });

  group('진단 로그', () {
    test('JavaScript 채널을 만들지 않는다 — NICE 페이지에 전역 객체를 추가하지 않는다', () {
      expect(_script.contains('addJavaScriptChannel'), isFalse);
      expect(_script.contains('JavaScriptChannelParams'), isFalse);
    });

    test('스크립트가 찍는 태그와 Dart 쪽 필터가 같다', () {
      expect(WebViewOtpAutofill.consoleTag, '[partychu-otp]');
      expect(_script, contains("var TAG = '${WebViewOtpAutofill.consoleTag}'"));
    });

    test('다른 콘솔 메시지는 흘려보낸다', () {
      // 예외 없이 지나가기만 하면 된다(로그는 debugPrint로만 나간다).
      expect(
        () => WebViewOtpAutofill.logConsoleMessage(
          const JavaScriptConsoleMessage(
            level: JavaScriptLogLevel.log,
            message: 'NICE 표준창의 평소 로그',
          ),
        ),
        returnsNormally,
      );
      expect(
        () => WebViewOtpAutofill.logConsoleMessage(
          const JavaScriptConsoleMessage(
            level: JavaScriptLogLevel.log,
            message: '[partychu-otp] inputs=3 marked=1 candidates=authNo/max=6',
          ),
        ),
        returnsNormally,
      );
    });
  });

  group('기존 NICE 인증 로직은 그대로다', () {
    late final String screen = _read(
      'lib/screens/nice_auth_verification_screen.dart',
    );

    test('콜백 감지와 중복 차단이 남아 있다', () {
      expect(screen, contains('if (req.url.startsWith(_kNiceReturnUrl))'));
      expect(screen, contains('_isProcessingResult'));
      expect(screen, contains("uri?.queryParameters['web_transaction_id']"));
      expect(screen, contains('_startResultCheck(webTransactionId)'));
      expect(screen, contains('NavigationDecision.prevent'));
    });

    test('자동완성 주입이 페이지 로드마다 걸린다', () {
      expect(screen, contains('WebViewOtpAutofill.apply(ctrl)'));
      expect(
        screen,
        contains('setOnConsoleMessage(WebViewOtpAutofill.logConsoleMessage)'),
      );
      // onPageFinished 안에서 불러야 한다 — 표준창은 여러 페이지로 이어진다.
      final finished = screen.indexOf('onPageFinished:');
      final apply = screen.indexOf('WebViewOtpAutofill.apply(ctrl)');
      final navRequest = screen.indexOf('onNavigationRequest:');
      expect(finished, greaterThan(-1));
      expect(apply, greaterThan(finished));
      expect(
        apply,
        lessThan(navRequest),
        reason: '주입이 onPageFinished 블록 밖으로 나갔다',
      );
    });

    test('자동완성이 네비게이션 판정을 바꾸지 않는다', () {
      // 주입은 onPageFinished(로드 완료 후)에서만 한다 — 콜백 가로채기가
      // 도는 onNavigationRequest에는 들어가지 않는다.
      final navBlock = screen.substring(
        screen.indexOf('onNavigationRequest:'),
        screen.indexOf('onWebResourceError:'),
      );
      expect(navBlock.contains('WebViewOtpAutofill'), isFalse);
    });
  });

  group('SMS 읽기 권한을 요구하지 않는다', () {
    test('Android 매니페스트에 SMS 권한이 없다', () {
      for (final manifest in [
        'android/app/src/main/AndroidManifest.xml',
        'android/app/src/debug/AndroidManifest.xml',
      ]) {
        final file = File(manifest);
        if (!file.existsSync()) continue;
        final src = file.readAsStringSync();
        for (final permission in [
          'READ_SMS',
          'RECEIVE_SMS',
          'READ_PHONE_NUMBERS',
        ]) {
          expect(
            src.contains(permission),
            isFalse,
            reason: '$manifest 에 $permission 이 들어갔다 — 스토어 심사에서 문제가 된다',
          );
        }
      }
    });
  });
}

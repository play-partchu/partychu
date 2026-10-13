import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// NICE 표준창(WebView) 안의 **인증번호 입력칸에 OS 자동완성 힌트를 붙인다.**
///
/// ── 왜 이 방식인가 ────────────────────────────────────────────────────────
/// 본인확인 화면은 NICE가 서비스하는 웹페이지를 그대로 띄운다
/// (`nice_auth_verification_screen.dart`). 인증번호 입력칸은 그 페이지의 HTML
/// `<input>`이므로 Flutter 쪽에 `TextField`가 없다 — `AutofillHints.oneTimeCode`
/// 나 iOS `textContentType`을 붙일 대상이 애초에 존재하지 않는다.
///
/// 대신 **WebKit/Chromium이 HTML 속성을 보고 OS 자동완성을 켠다.**
///   · iOS: `autocomplete="one-time-code"`가 있으면 WKWebView가 그 칸의
///     텍스트 입력 특성을 `UITextContentType.oneTimeCode`로 매핑하고, 방금
///     도착한 SMS 인증번호를 키보드 상단(QuickType)에 제안한다(iOS 14+).
///   · Android: `inputmode="numeric"`으로 숫자 키패드가 뜨고, Gboard의
///     클립보드 제안("문자에서 복사한 코드")이 그 위에 올라온다.
///
/// 그래서 **NICE의 HTML을 바꾸지 않고도** 속성만 덧붙이면 자동완성이 열린다.
///
/// ── 무엇을 하지 않는가 ───────────────────────────────────────────────────
/// ⚠️ 이 코드는 **인증번호를 읽지도, 쓰지도, 제출하지도 않는다.**
///    힌트 속성(`autocomplete`·`inputmode`)과 선택 허용(`user-select`)만
///    덧붙인다. 실제 입력은 사용자가 제안을 **직접 탭**해야 일어난다 —
///    인증 절차나 보안 검증을 우회하는 지점이 한 곳도 없다.
///
///    `value`·`type`·`name`·`maxlength`·`pattern`은 건드리지 않는다. NICE가
///    그 값으로 서버 검증을 하므로 손대면 인증이 깨진다.
///
/// 주입이 실패하거나 입력칸을 못 찾으면 **조용히 아무 일도 하지 않는다.**
/// NICE가 마크업을 바꿔도 자동완성만 안 될 뿐, 인증 자체는 그대로 돌아간다.
class WebViewOtpAutofill {
  WebViewOtpAutofill._();

  /// 주입된 스크립트가 진단을 남길 때 쓰는 접두사.
  ///
  /// JavaScript 채널을 만들지 않고 `console.log`로만 내보낸다 — 남의 인증
  /// 페이지에 `window.*` 객체를 하나도 추가하지 않기 위해서다. Flutter 쪽은
  /// [WebViewController.setOnConsoleMessage]로 받는다([logConsoleMessage]).
  static const String consoleTag = '[partychu-otp]';

  /// 페이지가 로드될 때마다 호출한다(`onPageFinished`).
  ///
  /// NICE 표준창은 통신사 선택 → 정보 입력 → 인증번호 입력이 **여러 페이지로**
  /// 이어지고, 인증번호 칸은 마지막 단계에서야 나타난다. 그래서 한 번만
  /// 주입하면 안 되고, 페이지마다 다시 건다. 같은 페이지 안에서 AJAX로 늦게
  /// 그려지는 경우는 스크립트 안의 MutationObserver가 받는다.
  static Future<void> apply(WebViewController controller) async {
    try {
      await controller.runJavaScript(_script);
    } catch (e) {
      // 주입 실패는 인증을 막지 않는다 — 자동완성만 없는 상태로 진행한다.
      debugPrint('[OtpAutofill] 힌트 주입 생략(non-fatal): $e');
    }
  }

  /// WebView 콘솔 메시지 중 이 스크립트의 진단만 골라 찍는다.
  ///
  /// 실기기에서 "인증번호 칸을 찾았는지"를 확인하는 **유일한 수단**이다.
  /// NICE 표준창의 마크업은 공개돼 있지 않아서, 어떤 `name`/`maxlength`를
  /// 쓰는지는 실제로 돌려 보고 이 로그를 읽어야 안다.
  static void logConsoleMessage(JavaScriptConsoleMessage message) {
    if (!message.message.contains(consoleTag)) return;
    debugPrint('[OtpAutofill] ${message.message}');
  }

  // ── 주입 스크립트 ────────────────────────────────────────────────────────
  //
  // 입력칸을 고르는 기준은 **보수적으로** 잡았다. 휴대폰번호·생년월일·이름
  // 칸에 `one-time-code`를 붙이면 키보드가 그 자리에 SMS 인증번호를 제안해
  // 사용자를 헷갈리게 만든다. 그래서 제외 목록(DENY)을 먼저 보고, 허용
  // 단서(ALLOW)가 있고, 길이가 인증번호다운(4~8자) 칸만 표시한다.
  //
  // 교차 출처 iframe은 접근이 막혀 있다(브라우저 보안). try/catch로 감싸
  // 조용히 건너뛰고, 그 경우는 진단 로그에 남는다.
  static const String _script = r'''
(function () {
  var TAG = '[partychu-otp]';

  // 인증번호가 **아닌** 칸. 먼저 걸러낸다.
  var DENY = /(phone|mobile|tel|hp|birth|jumin|rrn|ssn|name|carrier|addr|email|id$|pwd|password|휴대|전화|생년|주민|이름|통신|주소|아이디)/i;
  // 인증번호 칸일 가능성을 올려 주는 단서.
  var ALLOW = /(otp|auth|cert|sms|vrfc|verify|valid|confirm|인증|승인|확인번호)/i;

  function cluesOf(el) {
    var parts = [el.name, el.id, el.className, el.placeholder,
                 el.getAttribute('title'), el.getAttribute('aria-label')];
    // name이 축약어면 라벨 텍스트가 유일한 단서다.
    try {
      if (el.labels) {
        for (var i = 0; i < el.labels.length; i++) parts.push(el.labels[i].textContent);
      }
    } catch (e) {}
    return parts.filter(Boolean).join(' ');
  }

  function isOtpInput(el) {
    if (!el || el.tagName !== 'INPUT') return false;
    var type = (el.getAttribute('type') || 'text').toLowerCase();
    if (type !== 'text' && type !== 'tel' && type !== 'number') return false;
    var clues = cluesOf(el);
    if (!clues) return false;
    if (DENY.test(clues)) return false;
    if (!ALLOW.test(clues)) return false;
    // 인증번호는 4~8자다. 휴대폰번호(11자)·생년월일은 여기서 떨어진다.
    var max = parseInt(el.getAttribute('maxlength') || '0', 10);
    if (max && (max < 4 || max > 8)) return false;
    return true;
  }

  function markIn(doc) {
    var result = { seen: 0, marked: 0, clues: [] };
    var inputs = doc.querySelectorAll('input');
    result.seen = inputs.length;
    for (var i = 0; i < inputs.length; i++) {
      var el = inputs[i];
      if (!isOtpInput(el)) continue;
      result.clues.push((el.name || el.id || '(unnamed)') +
                        '/max=' + (el.getAttribute('maxlength') || '-'));
      // ⚠️ 힌트만 붙인다 — value·type·name·maxlength는 그대로 둔다.
      if (el.getAttribute('autocomplete') !== 'one-time-code') {
        el.setAttribute('autocomplete', 'one-time-code');
        result.marked++;
      }
      if (!el.getAttribute('inputmode')) {
        el.setAttribute('inputmode', 'numeric');
      }
      // 붙여넣기를 위해 선택을 막아 둔 경우만 되살린다(표시 속성뿐이다).
      try {
        el.style.webkitUserSelect = 'text';
        el.style.userSelect = 'text';
      } catch (e) {}
    }
    return result;
  }

  function run() {
    var docs = [document];
    var blockedFrames = 0;
    try {
      var frames = document.querySelectorAll('iframe, frame');
      for (var i = 0; i < frames.length; i++) {
        try {
          if (frames[i].contentDocument) docs.push(frames[i].contentDocument);
          else blockedFrames++;
        } catch (e) { blockedFrames++; }
      }
    } catch (e) {}

    var seen = 0, marked = 0, clues = [];
    for (var d = 0; d < docs.length; d++) {
      try {
        var r = markIn(docs[d]);
        seen += r.seen; marked += r.marked; clues = clues.concat(r.clues);
      } catch (e) {}
    }
    console.log(TAG + ' inputs=' + seen + ' marked=' + marked +
                ' blockedFrames=' + blockedFrames +
                ' candidates=' + (clues.join(',') || 'none'));
  }

  run();

  // AJAX로 뒤늦게 그려지는 인증번호 칸을 받는다. 속성 변경은 관찰하지 않으므로
  // (childList/subtree만) 위의 setAttribute가 자신을 다시 부르는 일은 없다.
  if (!window.__partychuOtpObserver) {
    try {
      var pending = null;
      var observer = new MutationObserver(function () {
        if (pending) return;
        pending = setTimeout(function () { pending = null; run(); }, 300);
      });
      observer.observe(document.documentElement, { childList: true, subtree: true });
      window.__partychuOtpObserver = observer;
    } catch (e) {
      console.log(TAG + ' observer unavailable: ' + e);
    }
  }
})();
''';
}

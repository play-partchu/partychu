// 포트원(PortOne) V2 Browser SDK를 웹에서 직접 호출한다 — 모바일은
// webview_flutter로 결제창을 띄우지만, webview_flutter는 웹 플랫폼 구현이
// 없어 그 방식을 그대로 쓸 수 없다. 페이로드/응답 모두 JSON
// 문자열(JSON.parse/JSON.stringify)로 주고받아, 타입이 있는 JS interop
// 선언 없이도 임의의 중첩 객체를 안전하게 다룬다.
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

const String _sdkUrl = 'https://cdn.portone.io/v2/browser-sdk.js';
Future<void>? _sdkLoadFuture;

@JS('PortOne.requestPayment')
external JSPromise<JSAny?> _requestPayment(JSAny? options);

@JS('JSON.parse')
external JSAny? _jsonParse(JSString text);

@JS('JSON.stringify')
external JSString _jsonStringify(JSAny? value);

Future<void> _ensureSdkLoaded() {
  if (globalContext.has('PortOne')) return Future.value();
  return _sdkLoadFuture ??= () {
    final completer = Completer<void>();
    final script = html.ScriptElement()
      ..src = _sdkUrl
      ..onLoad.listen((_) => completer.complete())
      ..onError.listen(
        (e) => completer.completeError(StateError('PortOne SDK 로드 실패: $e')),
      );
    html.document.head!.append(script);
    return completer.future;
  }();
}

/// [PortoneCheckoutScreen]의 webview HTML(`_buildHtml()`)이 하던 것과 동일한
/// `PortOne.requestPayment(...)` 호출을 페이지에서 직접 수행한다. 반환값은
/// webview의 JavaScript 채널 콜백과 같은 모양(`{success, message}`)으로
/// 맞춰서, 호출부(portone_checkout_screen.dart)가 플랫폼과 무관하게 같은
/// 방식으로 결과를 처리할 수 있게 한다.
Future<Map<String, dynamic>> requestPortOnePayment({
  required String storeId,
  required String channelKey,
  required String paymentId,
  required String orderName,
  required int totalAmount,
  required String buyerName,
  required String buyerPhone,
}) async {
  await _ensureSdkLoaded();

  final payloadJson = jsonEncode({
    'storeId': storeId,
    'channelKey': channelKey,
    'paymentId': paymentId,
    'orderName': orderName,
    'totalAmount': totalAmount,
    'currency': 'CURRENCY_KRW',
    'payMethod': 'CARD',
    'customer': {'fullName': buyerName, 'phoneNumber': buyerPhone},
  });

  try {
    final resultJs = await _requestPayment(_jsonParse(payloadJson.toJS)).toDart;
    final resultMap =
        jsonDecode(_jsonStringify(resultJs).toDart) as Map<String, dynamic>;
    // requestPayment 응답은 실패 시에만 code 필드를 갖는다(포트원 V2 Browser
    // SDK 공식 계약) — code가 없으면 결제창에서의 진행은 성공.
    if (resultMap['code'] != null) {
      return {
        'success': false,
        'message': (resultMap['message'] ?? resultMap['code']).toString(),
      };
    }
    return {'success': true};
  } catch (e) {
    return {'success': false, 'message': e.toString()};
  }
}

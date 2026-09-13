// NICE 통합인증 API 개발 가이드 문서 1.5 "표준창 인증 요청"의 웹 브라우저
// 예시(window.open 팝업)를 그대로 따른다. 팝업이 return_url(website/nice/callback.html)로
// 이동하면, 그 페이지가 window.opener로 JSON 문자열 postMessage를 보내고 스스로 닫는다.
// (객체를 그대로 postMessage하면 dart:html에서 JS 객체 프로퍼티 접근이 불안정해질 수
// 있어, 문자열로 직렬화해서 주고받는다.)
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

Future<String?> openNicePopupAndWaitForCallback(String authUrl) async {
  final popup = html.window.open(
    authUrl,
    'nice_auth_popup',
    'width=440,height=760,menubar=no,toolbar=no,location=no,status=no,scrollbars=yes',
  );

  final completer = Completer<String?>();
  StreamSubscription? messageSub;
  Timer? closedPoller;

  void finish(String? value) {
    if (completer.isCompleted) return;
    messageSub?.cancel();
    closedPoller?.cancel();
    completer.complete(value);
  }

  messageSub = html.window.onMessage.listen((event) {
    final raw = event.data;
    if (raw is! String) return;
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return; // 우리 콜백 메시지가 아님 — 무시
    }
    if (decoded['source'] != 'nice_callback') return;

    final webTransactionId = decoded['webTransactionId'] as String?;
    try {
      popup.close();
    } catch (_) {
      /* no-op */
    }
    finish(
      webTransactionId != null && webTransactionId.isNotEmpty
          ? webTransactionId
          : null,
    );
  });

  // 사용자가 표준창(팝업)을 직접 닫아버린 경우(취소) — 무한 대기하지 않도록
  // 주기적으로 팝업 생존 여부를 확인한다.
  closedPoller = Timer.periodic(const Duration(milliseconds: 500), (_) {
    if (popup.closed == true) {
      finish(null);
    }
  });

  return completer.future;
}

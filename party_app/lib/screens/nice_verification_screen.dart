import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:webview_flutter/webview_flutter.dart';

const _kNiceReturnUrlPrefix = 'https://partychu-30c24.web.app/nice/callback';
const _kRegion = 'asia-northeast3';

enum _NiceStep {
  requestUrl('1단계: 인증 URL 요청 중'),
  loadWebView('2단계: 본인확인 화면 로드 중'),
  completing('3단계: 인증 결과 처리 중');

  const _NiceStep(this.label);
  final String label;
}

/// NICE 통합인증 표준창을 WebView로 표시하는 화면.
///
/// Navigator.push 결과:
///   true  — 본인확인 성공 (UserSession 갱신 완료)
///   false — 취소 또는 실패
class NiceVerificationScreen extends StatefulWidget {
  const NiceVerificationScreen({super.key});

  @override
  State<NiceVerificationScreen> createState() => _NiceVerificationScreenState();
}

class _NiceVerificationScreenState extends State<NiceVerificationScreen> {
  WebViewController? _ctrl;
  bool _loadingRequest = true;
  bool _loadingPage = false;
  bool _completing = false;
  String? _error;
  _NiceStep _step = _NiceStep.requestUrl;

  @override
  void initState() {
    super.initState();
    _requestAuthUrl();
  }

  // ── 1단계: Firebase Function에서 인증 URL 수신 ──────────────────────────────

  Future<void> _requestAuthUrl() async {
    setState(() {
      _loadingRequest = true;
      _error = null;
      _ctrl = null;
      _step = _NiceStep.requestUrl;
    });

    debugPrint('[NICE] ▶ ${_step.label} (uid=${UserSession.userId})');

    try {
      final callable = FirebaseFunctions.instanceFor(region: _kRegion)
          .httpsCallable(
            'niceIntcRequestUrl',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
          );

      debugPrint('[NICE] niceIntcRequestUrl 호출 → region=$_kRegion');
      final result = await callable.call();
      final data = Map<String, dynamic>.from(result.data as Map);

      final authUrl = data['authUrl'] as String? ?? '';

      debugPrint('[NICE] ✅ 인증 URL 수신 완료 (len=${authUrl.length})');

      if (authUrl.isEmpty) {
        throw Exception('서버 응답 필드 누락: authUrl이 비어 있습니다.');
      }

      _buildWebView(authUrl);
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
        '[NICE] ❌ FirebaseFunctionsException'
        ' code=${e.code}'
        ' message=${e.message}'
        ' details=${e.details}',
      );

      if (e.code == 'already-exists') {
        debugPrint('[NICE] 이미 본인확인 완료 → 성공 처리');
        if (mounted) Navigator.pop(context, true);
        return;
      }

      final String errMsg;
      if (e.code == 'not-found') {
        errMsg =
            'Firebase Functions가 배포되어 있지 않습니다.\n\n'
            '아래 명령어를 실행한 뒤 다시 시도해주세요:\n'
            'firebase deploy --only functions';
      } else if (e.code == 'unauthenticated') {
        errMsg = '로그인 후 다시 시도해주세요. (${e.code})';
      } else {
        errMsg = '[${e.code}] ${e.message ?? 'NICE 요청 준비 중 오류가 발생했습니다.'}';
      }

      setState(() {
        _loadingRequest = false;
        _error = errMsg;
      });
    } catch (e, st) {
      debugPrint('[NICE] ❌ 예상치 못한 오류: $e\n$st');
      setState(() {
        _loadingRequest = false;
        _error = '서버 연결에 실패했습니다.\n(${e.runtimeType})\n잠시 후 다시 시도해주세요.';
      });
    }
  }

  // ── 2단계: WebView에 NICE 표준창 GET 로드 ───────────────────────────────

  void _buildWebView(String authUrl) {
    setState(() => _step = _NiceStep.loadWebView);
    debugPrint('[NICE] ▶ ${_step.label}');
    debugPrint('[NICE] auth_url: $authUrl');
    debugPrint('[NICE] Return URL prefix: $_kNiceReturnUrlPrefix');

    late final WebViewController ctrl;
    ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // 콜백 페이지가 실제로 로드될 경우를 위한 채널 (fallback)
      ..addJavaScriptChannel(
        'NiceChannel',
        onMessageReceived: (JavaScriptMessage msg) {
          debugPrint('[NICE] JavaScriptChannel 수신: ${msg.message}');
          if (msg.message.isNotEmpty) _completeVerification(msg.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            debugPrint('[NICE] 페이지 시작(onPageStarted): $url');
            setState(() => _loadingPage = true);
            // NICE 표준창이 인증 완료 후 return_url을 window.open()으로 새 창에
            // 띄우려 시도하는 경우, webview_flutter는 팝업 생성을 처리하는 콜백이
            // 없어 아무 반응 없이 무시해버림 → 콜백이 영영 도달하지 않음.
            // window.open을 현재 프레임 네비게이션으로 강제 전환해
            // onNavigationRequest가 반드시 발생하도록 함.
            //
            // 또한 onNavigationRequest는 메인 프레임 내비게이션만 전달받음
            // (webview_flutter_android 소스: _handleNavigation의 `!isForMainFrame`
            // 체크로 서브프레임 요청은 무조건 드롭됨). NICE가 iframe 안에서
            // return_url로 리다이렉트하면 onNavigationRequest/onPageStarted 모두
            // 절대 호출되지 않으므로, iframe 안에서 로드되는 callback.html이
            // window.parent로 postMessage를 보내고, 메인 프레임(여기)에서
            // message 이벤트를 받아 NiceChannel로 릴레이한다.
            ctrl
                .runJavaScript('''
            (function() {
              window.open = function(url) {
                if (url) { window.location.href = url; }
                return null;
              };
              if (!window.__niceMessageRelayInstalled) {
                window.__niceMessageRelayInstalled = true;
                window.addEventListener('message', function(event) {
                  var data = event.data;
                  if (data && data.source === 'nice_callback' && data.webTransactionId) {
                    if (typeof NiceChannel !== 'undefined' && NiceChannel.postMessage) {
                      NiceChannel.postMessage(data.webTransactionId);
                    }
                  }
                });
              }
            })();
          ''')
                .catchError((e) {
                  debugPrint('[NICE] window.open 오버라이드/message 릴레이 주입 실패: $e');
                });
          },
          onPageFinished: (url) {
            debugPrint('[NICE] 페이지 완료(onPageFinished): $url');
            setState(() => _loadingPage = false);
          },
          onUrlChange: (UrlChange change) {
            debugPrint('[NICE] URL 변경(onUrlChange): ${change.url}');
          },
          onHttpError: (HttpResponseError error) {
            debugPrint(
              '[NICE] HTTP 오류(onHttpError)'
              ' statusCode=${error.response?.statusCode}'
              ' url=${error.request?.uri}',
            );
          },
          onNavigationRequest: (NavigationRequest req) {
            debugPrint(
              '[NICE] 내비게이션 요청(onNavigationRequest): ${req.url}'
              ' isMainFrame=${req.isMainFrame}',
            );

            // return_url 인터셉트 (primary 경로)
            if (req.url.startsWith(_kNiceReturnUrlPrefix)) {
              debugPrint('[NICE] ✅ returnUrl 인터셉트: ${req.url}');
              final uri = Uri.tryParse(req.url);

              if (uri?.queryParameters['closed'] == '1') {
                debugPrint('[NICE] 닫기 버튼으로 취소');
                if (mounted) Navigator.pop(context, false);
                return NavigationDecision.prevent;
              }

              final webTransactionId =
                  uri?.queryParameters['web_transaction_id'];
              debugPrint(
                '[NICE] web_transaction_id 존재=${webTransactionId != null}',
              );

              if (webTransactionId != null && webTransactionId.isNotEmpty) {
                _completeVerification(webTransactionId);
              } else {
                debugPrint('[NICE] ⚠️ web_transaction_id 없음 → 취소 처리');
                if (mounted) Navigator.pop(context, false);
              }
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (WebResourceError err) {
            debugPrint(
              '[NICE] WebResourceError'
              ' isForMainFrame=${err.isForMainFrame}'
              ' errorType=${err.errorType}'
              ' errorCode=${err.errorCode}'
              ' description=${err.description}'
              ' url=${err.url}',
            );
          },
        ),
      )
      ..loadRequest(Uri.parse(authUrl));

    debugPrint('[NICE] WebView loadRequest(GET) 전송 완료');

    setState(() {
      _ctrl = ctrl;
      _loadingRequest = false;
    });
  }

  // ── 3단계: web_transaction_id를 서버로 전달 → 조회·검증·복호화·저장 ─────────

  Future<void> _completeVerification(String webTransactionId) async {
    if (_completing) return;
    setState(() {
      _completing = true;
      _step = _NiceStep.completing;
    });

    debugPrint('[NICE] ▶ ${_step.label} (webTransactionId=$webTransactionId)');

    try {
      final callable = FirebaseFunctions.instanceFor(region: _kRegion)
          .httpsCallable(
            'niceIntcResult',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
          );
      await callable.call({'webTransactionId': webTransactionId});

      debugPrint('[NICE] ✅ niceIntcResult 성공 → UserSession 갱신');
      // 갱신 실패가 인증 성공을 되돌리면 안 된다 — 호출부가 서버 값으로
      // 다시 확인하므로 여기서는 넘어간다.
      try {
        await UserSession.loadFromFirestore();
      } catch (e) {
        debugPrint('[NICE] 세션 갱신 실패(무시): $e');
      }
      if (mounted) Navigator.pop(context, true);
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
        '[NICE] ❌ niceIntcResult 오류: code=${e.code} message=${e.message}',
      );
      if (!mounted) return;

      if (e.code == 'cancelled') {
        Navigator.pop(context, false);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('[${e.code}] ${e.message ?? '본인확인 처리 중 오류가 발생했습니다.'}'),
        ),
      );
      setState(() => _completing = false);
    } catch (e, st) {
      debugPrint('[NICE] ❌ niceIntcResult 예외: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('본인확인 처리 중 오류가 발생했습니다. (${e.runtimeType})')),
      );
      setState(() => _completing = false);
    }
  }

  // ── 빌드 ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          '본인확인',
          style: TextStyle(
            color: Colors.black87,
            fontFamily: 'SeoulHangang',
            fontWeight: FontWeight.w500,
            shadows: [
              Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
              Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
            ],
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: '닫기',
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: Stack(
        children: [
          // WebView 본체
          if (_ctrl != null && _error == null)
            WebViewWidget(controller: _ctrl!),

          // 오류 화면
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 56,
                      color: Colors.redAccent,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 28),
                    ElevatedButton(
                      onPressed: _requestAuthUrl,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6FA0),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 14,
                        ),
                      ),
                      child: const Text(
                        '다시 시도',
                        style: TextStyle(fontSize: 15),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 로딩 오버레이
          if (_loadingRequest || _loadingPage || _completing)
            Container(
              color: Colors.white.withValues(alpha: 0.80),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFFFF6FA0)),
                    const SizedBox(height: 16),
                    Text(
                      _step.label,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:party_app/services/nice_web_popup/nice_web_popup.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:webview_flutter/webview_flutter.dart';

// NICE 통합인증 API 개발 가이드(v1.0.0) 기준 재구현.
// 기존 NiceVerificationScreen(nice_verification_screen.dart)과 완전히 분리된
// 별도 화면 — 기존 코드/세션/우회 로직에 의존하지 않는다.
//
// 문서 1.5 "표준창 인증 요청":
//   인증URL 요청 후 응답받은 auth_url을 그대로 사용 (GET/POST 모두 가능, 별도 form 불필요).
//   표준창이 인증을 완료하면 return_url로 web_transaction_id가 GET Query String으로 전달됨.
const _kNiceReturnUrl = 'https://partychu-30c24.web.app/nice/callback';
const _kRegion = 'asia-northeast3';

// ── 결과 조회 재시도 정책 ──────────────────────────────────────────────────
// NICE 인증 완료 직후에는 결과가 아직 준비되지 않았을 수 있으므로, 긴 요청
// 한 번으로 기다리지 않고 "즉시 → 1초 후 → 2초 후 → 3초 후" 총 4회까지
// 짧게 재조회한다. 전체 대기시간은 하드 데드라인(_kOverallDeadline)으로
// 강제 종료되어 어떤 경우에도 무한 로딩이 발생하지 않는다.
const _kRetryDelays = <Duration>[
  Duration.zero,
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 3),
];
const _kAttemptTimeout = Duration(seconds: 4);
const _kOverallDeadline = Duration(seconds: 10);

enum _Step {
  requestUrl('인증 URL 요청 중'),
  loadWebView('본인확인 화면 로드 중'),
  webPopup('새 창에서 본인확인을 진행해주세요.\n팝업이 보이지 않는다면 팝업 차단을 해제해주세요.'),
  completing('본인인증이 완료되었습니다.\n결과를 확인하고 있습니다.');

  const _Step(this.label);
  final String label;
}

/// 인증 실패의 성격 — 재시도 가능한지 여부를 구분한다.
enum _FailureKind {
  /// 서버가 아직 결과를 확인하지 못함(타임아웃 등) — 다음 시도로 재시도.
  retryable,

  /// NICE가 명확히 실패/취소를 응답함 — 재시도해도 결과가 바뀌지 않음.
  permanent,
}

class _AttemptOutcome {
  final bool success;
  final _FailureKind? failureKind;
  final String logTag; // success / timeout / failure / duplicate

  /// 서버가 "이 CI는 이미 다른 계정에 연결됨"이라고 답한 경우의 안내 문구.
  /// null이 아니면 재시도 대상이 아니라 정책상 거부이므로, 재시도 버튼 없이
  /// 이 문구만 보여주고 화면을 닫게 한다.
  final String? blockMessage;

  const _AttemptOutcome.success()
    : success = true,
      failureKind = null,
      blockMessage = null,
      logTag = 'success';
  const _AttemptOutcome.retryable(this.logTag)
    : success = false,
      blockMessage = null,
      failureKind = _FailureKind.retryable;
  const _AttemptOutcome.permanent(this.logTag)
    : success = false,
      blockMessage = null,
      failureKind = _FailureKind.permanent;
  const _AttemptOutcome.blocked(this.blockMessage)
    : success = false,
      logTag = 'duplicate',
      failureKind = _FailureKind.permanent;
}

/// Navigator.push 결과: true = 성공, false = 취소/실패
class NiceAuthVerificationScreen extends StatefulWidget {
  const NiceAuthVerificationScreen({super.key});

  @override
  State<NiceAuthVerificationScreen> createState() =>
      _NiceAuthVerificationScreenState();
}

class _NiceAuthVerificationScreenState
    extends State<NiceAuthVerificationScreen> {
  WebViewController? _ctrl;
  bool _loading = true;
  bool _completing = false;
  String? _error; // 인증 URL 요청 단계 오류 (기존 "다시 시도" 버튼 1개)
  bool _resultCheckFailed = false; // 결과 조회 단계 오류 (버튼 2개)
  _Step _step = _Step.requestUrl;

  /// 결과 조회 중 콜백이 중복 실행되지 않도록 막는 플래그.
  /// WebView 리다이렉트/재로드로 동일한 return_url이 여러 번 감지되어도
  /// _fetchResult가 한 번만 실행되도록 onNavigationRequest 단계에서 즉시 세운다.
  bool _isProcessingResult = false;
  String? _lastWebTransactionId;

  /// "이미 다른 계정에서 본인확인이 완료됨" 안내 — 정책상 거부이므로 재시도
  /// 버튼 없이 이 문구만 보여준다(null이면 해당 상태가 아님).
  String? _blockedMessage;

  @override
  void initState() {
    super.initState();
    _requestAuthUrl();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  bool _disposed = false;

  /// dispose된 이후에는 절대 setState를 호출하지 않는다.
  void _safeSetState(VoidCallback fn) {
    if (_disposed || !mounted) return;
    setState(fn);
  }

  // ── 1. 인증 URL 요청 (문서 2. API 명세서 §2) ────────────────────────────────

  Future<void> _requestAuthUrl() async {
    _safeSetState(() {
      _loading = true;
      _error = null;
      _resultCheckFailed = false;
      _ctrl = null;
      _step = _Step.requestUrl;
    });

    debugPrint('[NiceAuth] ▶ ${_step.label} uid=${UserSession.userId}');

    try {
      final result = await FirebaseFunctions.instanceFor(region: _kRegion)
          .httpsCallable(
            'niceAuthRequestUrl',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
          )
          .call();

      final data = Map<String, dynamic>.from(result.data as Map);
      final authUrl = data['authUrl'] as String? ?? '';
      debugPrint('[NiceAuth] auth_url 수신 (len=${authUrl.length})');

      if (authUrl.isEmpty) {
        throw Exception('authUrl이 비어 있습니다.');
      }

      if (kIsWeb) {
        _startWebPopupFlow(authUrl);
      } else {
        _loadAuthUrl(authUrl);
      }
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[NiceAuth] ❌ ${e.code}: ${e.message}');

      if (e.code == 'already-exists') {
        // 서버가 "이미 본인확인된 계정"이라고 답한 경우 — 세션도 그 사실로
        // 맞춰 두어야, 앱이 다시 이 화면으로 보내지 않는다.
        try {
          await UserSession.loadFromFirestore();
        } catch (_) {}
        if (mounted) Navigator.pop(context, true);
        return;
      }

      _safeSetState(() {
        _loading = false;
        _error = '[${e.code}] ${e.message ?? '인증 URL 요청에 실패했습니다.'}';
      });
    } catch (e) {
      debugPrint('[NiceAuth] ❌ $e');
      _safeSetState(() {
        _loading = false;
        _error = '서버 연결에 실패했습니다. 잠시 후 다시 시도해주세요.';
      });
    }
  }

  // ── 2-web. 표준창 로드 — Flutter Web (문서 1.5 "표준창 인증 요청") ────────────
  //
  // 문서 1.5가 예시로 드는 그대로 웹 브라우저는 window.open() 팝업으로 표준창을
  // 띄운다(모바일처럼 WebView 안에 auth_url을 로드하는 방식은 웹에는 없음).
  // 팝업이 return_url로 이동하면 website/nice/callback.html이 opener(이 창)에게
  // postMessage로 web_transaction_id를 전달하고 스스로 닫는다.
  Future<void> _startWebPopupFlow(String authUrl) async {
    // _loading을 계속 true로 유지해 로딩 오버레이가 "새 창에서 진행해주세요"
    // 안내를 보여준다 — 화면이 빈 상태로 남지 않도록.
    _safeSetState(() => _step = _Step.webPopup);
    debugPrint('[NiceAuth] ▶ ${_step.label}');

    final webTransactionId = await openNicePopupAndWaitForCallback(authUrl);
    if (_disposed) return;

    if (webTransactionId == null || webTransactionId.isEmpty) {
      debugPrint('[NiceAuth] 웹 팝업 취소/종료 — web_transaction_id 없음');
      if (mounted) Navigator.pop(context, false);
      return;
    }

    if (_isProcessingResult) return; // 방어적 중복 차단
    _isProcessingResult = true;
    _lastWebTransactionId = webTransactionId;
    // 이후 로딩 오버레이 표시는 _completing(결과 조회 단계)만으로 제어한다 —
    // mobile의 _loadAuthUrl과 동일한 시점(표준창 처리가 끝난 시점)에 끈다.
    _safeSetState(() => _loading = false);
    _startResultCheck(webTransactionId);
  }

  // ── 2. 표준창 로드 (문서 1.5 "표준창 인증 요청") ─────────────────────────────
  //
  // 문서는 웹 브라우저의 popup(window.open) 호출을 예시로 들지만, "별도 요청할
  // form이 없으며 GET/POST로 요청 가능"하다고 명시하므로 모바일 WebView에서는
  // auth_url을 직접 로드하는 것으로 대체한다. 표준창 내부 동작은 NICE가 전적으로
  // 제어하는 영역이라 iframe 감지/postMessage 릴레이 등 추가 로직은 넣지 않는다 —
  // 문서에 명시된 유일한 계약은 "return_url로 web_transaction_id가 GET Query
  // String으로 전달된다"는 것뿐이다.
  void _loadAuthUrl(String authUrl) {
    _safeSetState(() => _step = _Step.loadWebView);
    debugPrint('[NiceAuth] ▶ ${_step.label}');
    debugPrint('[NiceAuth] auth_url=$authUrl');

    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) => debugPrint('[NiceAuth] onPageStarted: $url'),
          onPageFinished: (url) =>
              debugPrint('[NiceAuth] onPageFinished: $url'),
          onNavigationRequest: (NavigationRequest req) {
            debugPrint(
              '[NiceAuth] onNavigationRequest: ${req.url}'
              ' isMainFrame=${req.isMainFrame}',
            );

            if (req.url.startsWith(_kNiceReturnUrl)) {
              // 콜백 URL 감지는 여기서 한 번만 처리한다 — 이미 결과 조회를
              // 시작했다면(_isProcessingResult) 리다이렉트가 중복 감지되어도
              // 다시 트리거하지 않는다.
              if (_isProcessingResult) {
                debugPrint('[NiceAuth] 콜백 중복 감지 — 무시');
                return NavigationDecision.prevent;
              }

              final uri = Uri.tryParse(req.url);

              if (uri?.queryParameters['closed'] == '1') {
                debugPrint('[NiceAuth] 닫기 버튼으로 취소');
                if (mounted) Navigator.pop(context, false);
                return NavigationDecision.prevent;
              }

              // 문서 1.5 GET 방식 예시: web_transaction_id를 Query String에서 추출
              final webTransactionId =
                  uri?.queryParameters['web_transaction_id'];
              debugPrint('[NiceAuth APP] callback detected');

              if (webTransactionId != null && webTransactionId.isNotEmpty) {
                _isProcessingResult = true; // 동기적으로 즉시 세워 중복 진입 차단
                _lastWebTransactionId = webTransactionId;
                _startResultCheck(webTransactionId);
              } else {
                // 문서: "해당 값을 받지 못할 경우 사용자 인증이 완료되지 않은 상태"
                debugPrint('[NiceAuth] web_transaction_id 없음 → 인증 미완료');
                if (mounted) Navigator.pop(context, false);
              }
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (WebResourceError e) => debugPrint(
            '[NiceAuth] onWebResourceError: ${e.errorCode} ${e.description} url=${e.url}',
          ),
          onHttpError: (HttpResponseError e) => debugPrint(
            '[NiceAuth] onHttpError: ${e.response?.statusCode} url=${e.request?.uri}',
          ),
        ),
      )
      ..loadRequest(Uri.parse(authUrl));

    _safeSetState(() {
      _ctrl = ctrl;
      _loading = false;
    });
  }

  // ── 3. 인증 결과 요청 — 짧은 재시도 루프 (문서 2. API 명세서 §3) ──────────────
  //
  // 성공/실패/지연을 명확히 구분한다:
  //   - 성공: 즉시 화면 종료
  //   - 재시도 가능한 실패(timeout 등): 남은 예산 안에서 다음 지연 후 재시도
  //   - 영구 실패(취소/세션만료 등): 즉시 재시도 중단, 안내 화면 표시
  // 전체 대기시간은 _kOverallDeadline(10초)을 절대 넘기지 않는다 — 이후에는
  // 반드시 로딩을 끝내고 오류/재시도 화면으로 전환한다("빈 화면"으로 남지 않음).
  Future<void> _startResultCheck(String webTransactionId) async {
    _safeSetState(() {
      _completing = true;
      _resultCheckFailed = false;
      _step = _Step.completing;
    });

    final overallStopwatch = Stopwatch()..start();

    for (var attempt = 0; attempt < _kRetryDelays.length; attempt++) {
      if (_disposed) return; // 화면이 이미 닫힘 — 더 이상 진행하지 않음

      final delay = _kRetryDelays[attempt];
      if (delay > Duration.zero) {
        final remaining = _kOverallDeadline - overallStopwatch.elapsed;
        if (remaining <= Duration.zero) break;
        await Future.delayed(delay < remaining ? delay : remaining);
        if (_disposed) return;
      }

      final remainingBudget = _kOverallDeadline - overallStopwatch.elapsed;
      if (remainingBudget <= Duration.zero) break;
      final attemptTimeout = remainingBudget < _kAttemptTimeout
          ? remainingBudget
          : _kAttemptTimeout;

      debugPrint('[NiceAuth APP] result request attempt ${attempt + 1}');
      final attemptStopwatch = Stopwatch()..start();
      final outcome = await _fetchResultOnce(webTransactionId, attemptTimeout);
      debugPrint(
        '[NiceAuth APP] attempt ${attempt + 1} completed: '
        '${attemptStopwatch.elapsedMilliseconds}ms — ${outcome.logTag}',
      );

      if (_disposed) return;

      if (outcome.success) {
        debugPrint('[NiceAuth APP] success');
        // 세션 갱신에 실패하더라도 인증 성공 자체는 그대로 알린다 — 여기서
        // 막히면 인증을 마친 사용자가 이 화면에 갇힌다(호출부가 서버 값을
        // 다시 확인한다).
        try {
          await UserSession.loadFromFirestore();
        } catch (e) {
          debugPrint('[NiceAuth APP] 세션 갱신 실패(무시): $e');
        }
        if (mounted) Navigator.pop(context, true);
        return;
      }

      // 정책상 거부(같은 사람이 이미 다른 계정에서 인증 완료) — 재시도해도
      // 결과가 바뀌지 않으므로 안내 문구만 보여주고 끝낸다.
      if (outcome.blockMessage != null) {
        debugPrint('[NiceAuth APP] blocked (duplicate identity)');
        _safeSetState(() {
          _completing = false;
          _loading = false;
          _blockedMessage = outcome.blockMessage;
        });
        return;
      }

      if (outcome.failureKind == _FailureKind.permanent) {
        debugPrint('[NiceAuth APP] failure (permanent)');
        // permanent 실패 중 "취소"는 별도 안내 없이 화면을 닫는다(기존 동작 유지).
        if (outcome.logTag == 'cancelled') {
          if (mounted) Navigator.pop(context, false);
          return;
        }
        break;
      }
      // retryable — 루프 계속 (다음 delay 이후 재시도)
      debugPrint('[NiceAuth APP] timeout — 재시도 예정');
    }

    // 예산 소진 또는 permanent 실패 — 무한 로딩 금지, 명확한 재시도 화면으로 전환
    if (_disposed) return;
    _safeSetState(() {
      _completing = false;
      _resultCheckFailed = true;
    });
  }

  Future<_AttemptOutcome> _fetchResultOnce(
    String webTransactionId,
    Duration timeout,
  ) async {
    try {
      await FirebaseFunctions.instanceFor(region: _kRegion)
          .httpsCallable(
            'niceAuthResult',
            options: HttpsCallableOptions(timeout: timeout),
          )
          .call({'webTransactionId': webTransactionId})
          .timeout(timeout);

      return const _AttemptOutcome.success();
    } on TimeoutException {
      // 클라이언트 쪽에서 지정한 attempt 예산을 넘김 — 서버 응답을 더 기다리지
      // 않고 즉시 다음 재시도로 넘어간다(서버 실행 자체는 백그라운드에서
      // 계속되다 자체 timeout으로 종료되지만, 이 Future는 여기서 손을 뗀다).
      return const _AttemptOutcome.retryable('timeout');
    } on FirebaseFunctionsException catch (e) {
      final detailCode = (e.details is Map)
          ? e.details['code'] as String?
          : null;
      debugPrint(
        '[NiceAuth] niceAuthResult 오류: ${e.code} detail=$detailCode '
        '${e.message}',
      );

      // "1명의 실사용자 = 파티츄 계정 1개" 정책 위반 — CI가 이미 다른 계정에
      // 연결되어 서버가 인증을 거부했다. 서버 문구를 그대로 보여준다.
      if (detailCode == 'IDENTITY_ALREADY_LINKED') {
        return _AttemptOutcome.blocked(
          e.message ??
              '이미 다른 파티츄 계정에서 본인확인이 완료된 정보입니다.\n'
                  '기존 계정으로 로그인해주세요.',
        );
      }

      // 서버가 명시적으로 "재시도 가능"이라고 알려주는 경우
      if (detailCode == 'NICE_RESULT_TIMEOUT' ||
          e.code == 'deadline-exceeded') {
        return const _AttemptOutcome.retryable('timeout');
      }
      // 사용자가 표준창에서 취소했거나 NICE가 실패로 응답 — 재시도 무의미
      if (e.code == 'cancelled') {
        return const _AttemptOutcome.permanent('cancelled');
      }
      // 그 외(세션 없음/만료/이미 사용/무결성 실패 등) — 영구 실패로 취급
      return const _AttemptOutcome.permanent('failure');
    } catch (e) {
      debugPrint('[NiceAuth] niceAuthResult 예외: $e');
      return const _AttemptOutcome.retryable('timeout');
    }
  }

  void _retryResultCheck() {
    final webTransactionId = _lastWebTransactionId;
    if (webTransactionId == null) {
      _requestAuthUrl();
      return;
    }
    _startResultCheck(webTransactionId);
  }

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
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: Stack(
        children: [
          if (_ctrl != null &&
              _error == null &&
              !_resultCheckFailed &&
              _blockedMessage == null)
            WebViewWidget(controller: _ctrl!),
          if (_error != null) _buildUrlErrorView(),
          if (_resultCheckFailed) _buildResultFailedView(),
          if (_blockedMessage != null) _buildBlockedView(),
          if (_loading || _completing) _buildLoadingOverlay(),
        ],
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.white.withValues(alpha: 0.80),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Color(0xFFFF6FA0)),
              const SizedBox(height: 16),
              Text(
                _step.label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.black45),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUrlErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 56, color: Colors.redAccent),
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
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }

  /// "1명의 실사용자 = 파티츄 계정 1개" 정책 안내 — 이미 다른 계정에서 본인확인을
  /// 마친 사람이라 재시도로 풀리지 않는다. 그래서 재시도 버튼을 두지 않고
  /// "확인"으로 화면을 닫는 것만 제공한다.
  Widget _buildBlockedView() {
    return Container(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.person_off_outlined,
                size: 56,
                color: Color(0xFFFF6FA0),
              ),
              const SizedBox(height: 20),
              Text(
                _blockedMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black54,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, false),
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
                child: const Text('확인'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultFailedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 56, color: Colors.redAccent),
            const SizedBox(height: 20),
            const Text(
              '인증 결과를 확인하지 못했습니다.\n잠시 후 다시 시도해주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.black54,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  onPressed: _retryResultCheck,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF6FA0),
                    side: const BorderSide(color: Color(0xFFFF6FA0)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                  ),
                  child: const Text('다시 확인'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    _isProcessingResult = false;
                    _lastWebTransactionId = null;
                    _requestAuthUrl();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6FA0),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                  ),
                  child: const Text('본인인증 다시하기'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

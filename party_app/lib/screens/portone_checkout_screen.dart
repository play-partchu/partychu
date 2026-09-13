import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:party_app/services/portone_web_checkout/portone_web_checkout.dart';

// ⚠️ 포트원(PortOne) 가맹점 콘솔에서 발급받은 값으로 반드시 교체해야 실제
// 결제가 동작한다. storeId/channelKey는 클라이언트에 노출돼도 되는 공개
// 식별자다(결제 API 시크릿과는 다름 — 그건 Cloud Functions 쪽에만 존재).
const String kPortOneStoreId = 'REPLACE_WITH_PORTONE_STORE_ID';
const String kPortOneChannelKey = 'REPLACE_WITH_PORTONE_CHANNEL_KEY';

// PG사 계약/심사가 끝나기 전에는 위 두 값이 플레이스홀더 그대로다 — 그
// 상태일 때만 테스트 모드로 판단해 실제 PortOne 결제창 대신 짧은 지연 후
// 테스트 결제 성공을 시뮬레이션한다(모바일/웹 동일). 실제 값으로 교체하는
// 순간 이 상수가 true가 되어 자동으로 실결제 경로로 전환된다 —
// functions/portOne.js의 PORTONE_API_SECRET 플레이스홀더 판정과 쌍을
// 이루는 클라이언트 쪽 판정이다.
bool get kPortOnePaymentsConfigured =>
    kPortOneStoreId != 'REPLACE_WITH_PORTONE_STORE_ID' &&
    kPortOneChannelKey != 'REPLACE_WITH_PORTONE_CHANNEL_KEY';

/// 포트원 V2 결제창(체크아웃) 방식 연동.
/// - PG 계약 전(테스트 모드, [kPortOnePaymentsConfigured] == false): 실제
///   결제창 대신 짧은 지연 후 테스트 결제 성공을 시뮬레이션한다.
/// - 모바일: nice_auth_verification_screen.dart와 동일하게 "중요한 외부
///   결제/인증은 WebView로" 원칙을 따른다.
/// - 웹: webview_flutter가 웹 플랫폼 구현이 없어 그 방식을 쓸 수 없으므로,
///   PortOne V2 Browser SDK를 페이지에서 직접 호출한다
///   (services/portone_web_checkout).
///
/// Navigator.push 결과: true = 결제 성공(클라이언트 보고 기준 — 실제 확정은
/// 항상 서버(verifyAndConfirmReservation 등)의 재검증을 거친다), false = 실패/취소.
class PortoneCheckoutScreen extends StatefulWidget {
  final String paymentId;
  final String orderName;
  final int amount;
  final String buyerName;
  final String buyerPhone;

  const PortoneCheckoutScreen({
    super.key,
    required this.paymentId,
    required this.orderName,
    required this.amount,
    required this.buyerName,
    required this.buyerPhone,
  });

  @override
  State<PortoneCheckoutScreen> createState() => _PortoneCheckoutScreenState();
}

class _PortoneCheckoutScreenState extends State<PortoneCheckoutScreen> {
  WebViewController? _ctrl;
  bool _loading = true;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    if (!kPortOnePaymentsConfigured) {
      _runTestModePayment();
    } else if (kIsWeb) {
      _runWebPayment();
    } else {
      _setupMobileWebView();
    }
  }

  // ── 테스트 모드(PG 계약 전) — 실제 결제창 없이 성공을 시뮬레이션 ─────────
  Future<void> _runTestModePayment() async {
    await Future.delayed(const Duration(milliseconds: 900));
    _finish({'success': true});
  }

  // ── 웹: PortOne Browser SDK를 페이지에서 직접 호출 ──────────────────────
  Future<void> _runWebPayment() async {
    final result = await requestPortOnePayment(
      storeId: kPortOneStoreId,
      channelKey: kPortOneChannelKey,
      paymentId: widget.paymentId,
      orderName: widget.orderName,
      totalAmount: widget.amount,
      buyerName: widget.buyerName,
      buyerPhone: widget.buyerPhone,
    );
    _finish(result);
  }

  // ── 모바일: WebView 안에서 PortOne Browser SDK 호출 ─────────────────────
  void _setupMobileWebView() {
    _ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..addJavaScriptChannel(
        'PortOneResult',
        onMessageReceived: _onWebViewResult,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadHtmlString(_buildHtml());
  }

  void _onWebViewResult(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      _finish(data);
    } catch (e) {
      _finish({'success': false, 'message': '결과 파싱 오류: $e'});
    }
  }

  void _finish(Map<String, dynamic> data) {
    if (_finished) return; // 중복 콜백 방지
    _finished = true;
    final success = data['success'] == true;
    if (!success) {
      debugPrint('[PortOne] 결제 실패/취소: ${data['message']}');
    }
    if (mounted) Navigator.pop(context, success);
  }

  String _buildHtml() {
    // requestPayment의 응답 객체는 실패 시에만 code 필드를 갖는다(포트원 V2
    // Browser SDK 공식 계약) — code가 없으면 결제창에서의 진행은 성공.
    final orderNameJson = jsonEncode(widget.orderName);
    final buyerNameJson = jsonEncode(widget.buyerName);
    final buyerPhoneJson = jsonEncode(widget.buyerPhone);
    final paymentIdJson = jsonEncode(widget.paymentId);
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <script src="https://cdn.portone.io/v2/browser-sdk.js"></script>
  <style>
    body { margin:0; padding:0; font-family:-apple-system,sans-serif; }
  </style>
</head>
<body>
  <script>
    async function pay() {
      try {
        const response = await PortOne.requestPayment({
          storeId: "$kPortOneStoreId",
          channelKey: "$kPortOneChannelKey",
          paymentId: $paymentIdJson,
          orderName: $orderNameJson,
          totalAmount: ${widget.amount},
          currency: "CURRENCY_KRW",
          payMethod: "CARD",
          customer: {
            fullName: $buyerNameJson,
            phoneNumber: $buyerPhoneJson
          }
        });
        if (response && response.code) {
          PortOneResult.postMessage(JSON.stringify({
            success: false,
            message: response.message || response.code
          }));
        } else {
          PortOneResult.postMessage(JSON.stringify({ success: true }));
        }
      } catch (e) {
        PortOneResult.postMessage(JSON.stringify({
          success: false,
          message: String(e)
        }));
      }
    }
    pay();
  </script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          '결제하기',
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
          onPressed: () {
            if (!_finished) {
              _finished = true;
              Navigator.pop(context, false);
            }
          },
        ),
      ),
      body: Stack(
        children: [
          if (ctrl != null) WebViewWidget(controller: ctrl),
          if (_loading || ctrl == null)
            Container(
              color: Colors.white,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFFFF6FA0)),
                    if (!kPortOnePaymentsConfigured) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'PG사 연동 전 테스트 모드입니다',
                        style: TextStyle(color: Colors.black45, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

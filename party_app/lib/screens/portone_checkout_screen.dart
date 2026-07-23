import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

// ⚠️ 포트원(PortOne) 가맹점 콘솔에서 발급받은 값으로 반드시 교체해야 실제
// 결제가 동작한다. storeId/channelKey는 클라이언트에 노출돼도 되는 공개
// 식별자다(결제 API 시크릿과는 다름 — 그건 Cloud Functions 쪽에만 존재).
const String kPortOneStoreId = 'REPLACE_WITH_PORTONE_STORE_ID';
const String kPortOneChannelKey = 'REPLACE_WITH_PORTONE_CHANNEL_KEY';

/// 포트원 V2 결제창(체크안웃) 방식 연동 — nice_auth_verification_screen.dart와
/// 동일하게 "중요한 외부 결제/인증은 WebView로" 원칙을 따른다.
///
/// Navigator.push 결과: true = 결제 성공(클라이언트 보고 기준 — 실제 확정은
/// 항상 서버(verifyAndConfirmReservation)의 재검증을 거친다), false = 실패/취소.
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
  late final WebViewController _ctrl;
  bool _loading = true;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..addJavaScriptChannel(
        'PortOneResult',
        onMessageReceived: _onResult,
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

  void _onResult(JavaScriptMessage message) {
    if (_finished) return; // 중복 콜백 방지
    _finished = true;
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      final success = data['success'] == true;
      if (!success) {
        debugPrint('[PortOne] 결제 실패/취소: ${data['message']}');
      }
      if (mounted) Navigator.pop(context, success);
    } catch (e) {
      debugPrint('[PortOne] 결과 파싱 오류: $e');
      if (mounted) Navigator.pop(context, false);
    }
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          '결제하기',
          style: TextStyle(color: Colors.black87, fontFamily: 'SeoulHangang', fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))]),
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
          WebViewWidget(controller: _ctrl),
          if (_loading)
            Container(
              color: Colors.white,
              child: const Center(
                child: CircularProgressIndicator(color: Color(0xFFFF6FA0)),
              ),
            ),
        ],
      ),
    );
  }
}

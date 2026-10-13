import 'package:flutter/material.dart';

/// 본인확인 화면에서 **"인증번호가 도착했어요 · 복사하기"** 만 알리는 줄.
///
/// ── 인증번호를 보여 주지 않는다 ─────────────────────────────────────────
/// 이 위젯은 인증번호를 **받지도 않는다.** 값을 넘기지 않으므로 화면에 뜰
/// 수도, 스크린샷·화면 녹화에 남을 수도 없다. 복사는 [onCopy]를 받은 화면이
/// `SmsConsentService.copyToClipboard()`로 하고, 그 값은 서비스 안에만 있다.
///
/// ── 가리지 않는다 ───────────────────────────────────────────────────────
/// WebView 위에 떠 있지 않다. 본인확인 화면이 이 줄에 **자리를 따로 주고**
/// 남은 공간을 WebView에 주므로(`nice_auth_verification_screen.dart`의
/// Column), NICE 표준창의 버튼·입력칸을 덮는 일이 구조적으로 없다.
class SmsCodeCopyBanner extends StatelessWidget {
  const SmsCodeCopyBanner({
    super.key,
    required this.onCopy,
    required this.onDismiss,
    this.copied = false,
  });

  /// "복사하기"를 눌렀을 때.
  final VoidCallback onCopy;

  /// 닫기(×)를 눌렀을 때.
  final VoidCallback onDismiss;

  /// 이미 한 번 복사했는가 — 안내 문구만 바뀐다.
  final bool copied;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1B2A00),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
          child: Row(
            children: [
              const Icon(
                Icons.sms_outlined,
                size: 18,
                color: Color(0xFFDCFF3F),
              ),
              const SizedBox(width: 10),
              // 좁은 화면에서도 줄이 깨지지 않도록 가변 영역에 둔다.
              Expanded(
                child: Text(
                  copied ? '복사했어요 · 입력칸을 길게 눌러 붙여넣기' : '인증번호가 도착했어요',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onCopy,
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFFDCFF3F),
                  foregroundColor: const Color(0xFF1B2A00),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  '복사하기',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.close, size: 18),
                color: Colors.white54,
                visualDensity: VisualDensity.compact,
                tooltip: '닫기',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

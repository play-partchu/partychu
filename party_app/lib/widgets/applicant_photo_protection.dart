import 'package:flutter/material.dart';
import 'package:party_app/models/party_application_form.dart';
import 'package:party_app/services/screen_capture_guard.dart';

/// 신청자 제출 사진이 **화면에 떠 있는 동안만** 캡처 보호를 켜 두는 껍데기.
///
/// 살아 있는 동안 [ScreenCaptureGuard]에서 표를 하나 받아 두고, 사라지면
/// 돌려준다. 썸네일 목록과 전체화면 뷰어가 각각 하나씩 잡기 때문에 뷰어만
/// 닫아도 아래 썸네일은 계속 보호된다(잠금장치가 참조 개수로 세는 이유).
///
/// ── 무엇을 가리는가 ────────────────────────────────────────────────────────
///
/// [ScreenCaptureGuard.protection]이 알려 주는 사유대로 자식 위를 **불투명**
/// 덮개로 가린다. 자식을 지우지 않고 덮는 이유는 레이아웃 때문이다 — 목록
/// 한가운데서 사진이 사라졌다 나타나면 스크롤이 튄다. 녹화·미리보기에 찍히는
/// 것은 어차피 합성된 화면이라, 덮으면 덮인 그림이 찍힌다.
///
/// 스크린샷이 감지되면 덮는 데서 끝내지 않고 경고창까지 띄운다. **확인을
/// 눌러야** 사진이 돌아온다. 다만 녹화 중이라면 확인을 눌러도 돌아오지 않는다
/// — 푸는 순간 그대로 녹화에 담기기 때문이고, 그 판정은 잠금장치가 한다.
///
/// 겹쳐 있을 때 경고창은 **맨 위 화면만** 띄운다. 안 그러면 썸네일과 뷰어가
/// 같은 경고를 두 장 겹쳐 띄운다.
class ProtectedPhotoScope extends StatefulWidget {
  final Widget child;

  /// 가려졌을 때 덮개의 모서리를 자식과 맞추고 싶을 때 쓴다.
  final BorderRadius? borderRadius;

  /// 검은 배경(전체화면 뷰어)용 덮개인지 — 흰 카드 위와 색을 달리한다.
  final bool dark;

  const ProtectedPhotoScope({
    super.key,
    required this.child,
    this.borderRadius,
    this.dark = false,
  });

  @override
  State<ProtectedPhotoScope> createState() => _ProtectedPhotoScopeState();
}

class _ProtectedPhotoScopeState extends State<ProtectedPhotoScope> {
  final _guard = ScreenCaptureGuard.instance;

  /// 이 화면이 받아 둔 표 — 겹쳤을 때 누가 맨 위인지 가리는 데도 쓴다.
  //
  // **initState에서 곧바로 받아 둔다.** 지연 초기화(late final의 기본)로
  // 두면 표를 처음 들여다보는 순간까지 보호가 켜지지 않는다 — 화면은
  // 이미 사진을 그리고 있는데 잠금장치는 잠들어 있는 상태가 된다.
  late final Object _token;

  /// 경고창이 이미 떠 있는가. 연달아 찍히면 한 장 위에 또 한 장이 쌓인다.
  bool _warning = false;

  @override
  void initState() {
    super.initState();
    _token = _guard.acquire();
    _guard.screenshotCount.addListener(_onScreenshot);
  }

  @override
  void dispose() {
    _guard.screenshotCount.removeListener(_onScreenshot);
    _guard.release(_token);
    super.dispose();
  }

  void _onScreenshot() {
    final count = _guard.screenshotCount.value;
    // 0은 보호 구간이 끝나며 되돌린 값이다(감지가 아니다).
    if (count == 0 || _warning || !mounted) return;
    if (!_guard.isFrontmost(_token)) return;
    _warn(count);
  }

  /// 캡처 경고 — 읽고 확인을 눌러야 사진이 돌아온다.
  ///
  /// 반복될수록 문구가 분명해진다. 다만 **세는 것이 전부**다 — 이용 제한이나
  /// 계정 정지 같은 제재는 하지 않는다. 하지도 않을 일을 경고에 적으면 그것도
  /// 거짓 안내다.
  Future<void> _warn(int count) async {
    _warning = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        // 뒤로가기로 지나칠 수 없다 — 확인이 곧 사진을 다시 여는 열쇠다.
        canPop: false,
        child: AlertDialog(
          title: const Text(
            '🔒 신청자 사진 보호 안내',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          content: Text(
            _warningBody(count),
            style: const TextStyle(fontSize: 13.5, height: 1.55),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('확인'),
            ),
          ],
        ),
      ),
    );
    _warning = false;
    final latest = _guard.screenshotCount.value;
    if (latest != count) {
      // 경고를 읽는 동안 또 찍혔다 — 그 건은 아직 확인받지 않았으므로
      // 사진을 가린 채로 한 번 더 경고한다(가림은 이미 걸려 있다).
      if (mounted && _guard.isFrontmost(_token)) return _warn(latest);
    }
    // 녹화 중이라면 이걸로도 풀리지 않는다(잠금장치가 녹화를 먼저 본다).
    _guard.acknowledgeScreenshot();
  }

  static String _warningBody(int count) {
    const base =
        '화면 캡처가 감지되었습니다.\n'
        '신청자 사진은 파티 승인 확인 목적으로만 제공되며, '
        '저장·공유·재배포를 삼가주세요.';
    if (count <= 1) return base;
    if (count == 2) {
      return '$base\n\n이 화면에서 캡처가 2번 감지됐어요. '
          '이미 촬영한 이미지는 지금 삭제해주세요.';
    }
    return '$base\n\n이 화면에서 캡처가 $count번 감지됐어요. '
        '신청자 동의 없이 사진을 저장하거나 공유하는 것은 '
        '개인정보 침해가 될 수 있어요.';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PhotoProtectionState>(
      valueListenable: _guard.protection,
      builder: (context, state, child) => Stack(
        fit: StackFit.passthrough,
        children: [
          child!,
          if (state != PhotoProtectionState.visible)
            Positioned.fill(child: _cover(state)),
        ],
      ),
      child: widget.child,
    );
  }

  Widget _cover(PhotoProtectionState state) {
    final (IconData icon, String text) = switch (state) {
      PhotoProtectionState.recording => (
        Icons.screen_share_outlined,
        '화면 녹화 또는 미러링이 감지되어\n신청자 사진을 보호하고 있어요.\n'
            '녹화를 끄면 다시 볼 수 있어요.',
      ),
      PhotoProtectionState.screenshot => (
        Icons.no_photography_outlined,
        '화면 캡처가 감지되어 사진을 가렸어요.\n안내를 확인하면 다시 볼 수 있어요.',
      ),
      // 앱이 내려간 동안의 덮개 — 미리보기에만 남고 사용자는 볼 일이 없다.
      _ => (Icons.lock_outline, '신청자 사진 보호 중'),
    };

    return ClipRRect(
      borderRadius: widget.borderRadius ?? BorderRadius.zero,
      child: Container(
        color: widget.dark ? const Color(0xFF14141A) : const Color(0xFFEDEEF4),
        padding: const EdgeInsets.all(10),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 22,
                color: widget.dark ? Colors.white70 : Colors.black45,
              ),
              const SizedBox(height: 6),
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                  color: widget.dark ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 호스트의 신청자 사진 옆에 작게 붙는 보호 안내.
///
/// 문구는 지금 기기에서 실제로 되는 만큼만 말한다
/// ([applicantPhotoHostNotice]) — iOS에서 "캡처를 차단한다"고 적지 않는다.
class ApplicantPhotoHostNotice extends StatelessWidget {
  /// 검은 배경(전체화면 뷰어) 위에 얹을 때 색을 뒤집는다.
  final bool dark;

  const ApplicantPhotoHostNotice({super.key, this.dark = false});

  @override
  Widget build(BuildContext context) => Text(
    applicantPhotoHostNotice(),
    textAlign: dark ? TextAlign.center : TextAlign.start,
    style: TextStyle(
      fontSize: 11.5,
      height: 1.45,
      color: dark ? Colors.white60 : Colors.black45,
    ),
  );
}

/// 사진을 내는(또는 이미 낸) 게스트에게 보여주는 안심 안내 카드.
class ApplicantPhotoGuestNotice extends StatelessWidget {
  /// 카드를 감싸는 바깥 여백 — 놓이는 화면마다 다르다.
  final EdgeInsetsGeometry margin;

  const ApplicantPhotoGuestNotice({super.key, this.margin = EdgeInsets.zero});

  static const _ink = Color(0xFF2E5D53);

  @override
  Widget build(BuildContext context) => Container(
    margin: margin,
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: const Color(0xFFEFF9F5),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFC9E9DC)),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          kApplicantPhotoGuestNoticeTitle,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
        SizedBox(height: 6),
        Text(
          kApplicantPhotoGuestNoticeBody,
          style: TextStyle(fontSize: 12, height: 1.5, color: Color(0xFF3E6B61)),
        ),
        SizedBox(height: 7),
        Text(
          kApplicantPhotoGuestNoticeSub,
          style: TextStyle(fontSize: 11.5, height: 1.4, color: Colors.black45),
        ),
      ],
    ),
  );
}

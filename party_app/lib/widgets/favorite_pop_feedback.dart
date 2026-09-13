import 'package:flutter/material.dart';

import 'package:party_app/widgets/partychu_ui.dart' show PartyChuColors;

/// 찜 버튼 옆에 잠깐 떴다 사라지는 한 줄 — 고양이발 + '찜!'.
///
/// ## 고양이발은 이모지가 아니라 아이콘이다
/// 이모지 🐾는 글자 하나에 **발자국이 둘** 찍힌 그림이라, 발바닥 하나를 쓰는
/// 찜 버튼·관심 목록([Icons.pets])과 개수가 어긋나 보인다. 그래서 여기서도
/// 같은 [Icons.pets]를 글자 앞에 붙여 앱 전체에서 고양이발이 **항상 하나**로
/// 보이게 한다.
///
/// ## 왜 스낵바가 아닌가
/// 찜은 카드 목록에서 연달아 누르는 동작이라, 화면 아래를 덮는 스낵바가 뜨면
/// 다음 카드를 가리고 큐에 밀려 몇 초씩 남는다. 여기서는 **누른 버튼 바로 위에**
/// 떠서 스스로 사라지는 오버레이를 쓴다 — 레이아웃을 밀지 않고([Overlay]),
/// 탭을 가로채지도 않는다([IgnorePointer]).
///
/// 저장 성공이 확정된 뒤에만 부른다(FavoriteStarButton 참고) — 실패했는데
/// '찜!'이 뜨면 사용자는 찜된 줄 알고 넘어간다.
class FavoritePopFeedback {
  FavoritePopFeedback._();

  /// 찜 등록 성공 — 통통 튀며 떠오르는 발바닥 하나 + '찜!'.
  static void showFavorited(BuildContext context, {Color? color}) {
    _show(
      context,
      text: '찜!',
      icon: Icons.pets,
      color: color ?? PartyChuColors.primary,
      background: Colors.white,
      duration: const Duration(milliseconds: 850),
      rise: 26,
      fontSize: 13,
    );
  }

  /// 찜 해제 — 같은 자리에서 더 작고 조용하게 흩어진다(소리 없음).
  static void showUnfavorited(BuildContext context) {
    _show(
      context,
      text: '찜 해제',
      color: Colors.black54,
      background: Colors.white,
      duration: const Duration(milliseconds: 620),
      rise: 16,
      fontSize: 11.5,
    );
  }

  static void _show(
    BuildContext context, {
    required String text,
    required Color color,
    required Color background,
    required Duration duration,
    required double rise,
    required double fontSize,
    IconData? icon,
  }) {
    // 위젯이 이미 화면에서 빠졌거나(연타 후 카드가 스크롤로 사라짐) 오버레이가
    // 없는 곳이면 조용히 아무것도 하지 않는다 — 피드백 때문에 예외가 나면 안 된다.
    final overlay = Overlay.maybeOf(context);
    final box = context.findRenderObject();
    if (overlay == null || box is! RenderBox || !box.hasSize) return;

    final origin = box.localToGlobal(Offset(box.size.width / 2, 0));
    final screen = MediaQuery.sizeOf(context);

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _FavoritePopLayer(
        origin: origin,
        screen: screen,
        text: text,
        icon: icon,
        color: color,
        background: background,
        duration: duration,
        rise: rise,
        fontSize: fontSize,
        onDone: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }
}

class _FavoritePopLayer extends StatefulWidget {
  final Offset origin;
  final Size screen;
  final String text;

  /// 글자 앞에 붙는 아이콘 — 찜 등록은 발바닥 하나([Icons.pets]), 해제는 없다.
  final IconData? icon;

  final Color color;
  final Color background;
  final Duration duration;
  final double rise;
  final double fontSize;
  final VoidCallback onDone;

  const _FavoritePopLayer({
    required this.origin,
    required this.screen,
    required this.text,
    required this.icon,
    required this.color,
    required this.background,
    required this.duration,
    required this.rise,
    required this.fontSize,
    required this.onDone,
  });

  @override
  State<_FavoritePopLayer> createState() => _FavoritePopLayerState();
}

class _FavoritePopLayerState extends State<_FavoritePopLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void initState() {
    super.initState();
    _ctrl.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 문구 폭을 미리 알 수 없어 넉넉한 박스를 잡고 그 안에서 가운데 정렬한다.
    // 화면 밖으로 나가는지는 **박스가 아니라 알약 자체**를 기준으로 본다 —
    // 박스 폭으로 밀어내면 오른쪽 끝 버튼(사진 위 오버레이)에서 알약이 눌린
    // 버튼보다 한참 왼쪽에 뜬다.
    const maxWidth = 120.0;
    const pillWidth = 84.0;
    final centerX = widget.origin.dx.clamp(
      8.0 + pillWidth / 2,
      widget.screen.width - 8.0 - pillWidth / 2,
    );
    final left = centerX - maxWidth / 2;
    // 버튼 위쪽에 띄운다. 화면 최상단에 붙은 버튼이면 아래로 내려 잡는다.
    final top = widget.origin.dy - 34;

    return Positioned(
      left: left,
      top: top < 8 ? widget.origin.dy + 24 : top,
      width: maxWidth,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) {
            final t = _ctrl.value;
            // 뜰 때는 빠르게, 사라질 때는 천천히 — 처음 15%에 나타나고
            // 마지막 40% 동안 흐려진다.
            final opacity = t < 0.15
                ? (t / 0.15)
                : (t < 0.6 ? 1.0 : (1 - (t - 0.6) / 0.4));
            // 살짝 튀어 올랐다가(overshoot) 계속 떠오른다.
            final scale =
                0.7 +
                Curves.easeOutBack.transform(t.clamp(0.0, 0.35) / 0.35) * 0.3;
            return Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, -widget.rise * Curves.easeOut.transform(t)),
                child: Transform.scale(scale: scale, child: child),
              ),
            );
          },
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: widget.background,
                borderRadius: BorderRadius.circular(999),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x26000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              // 아이콘이 있으면 글자 앞에 한 칸 붙인다 — 이모지 🐾(발자국 둘)
              // 대신 찜 버튼과 같은 발바닥 하나를 쓰기 위해서다.
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    Icon(
                      widget.icon,
                      size: widget.fontSize + 1,
                      color: widget.color,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    widget.text,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: widget.fontSize,
                      fontWeight: FontWeight.w800,
                      color: widget.color,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

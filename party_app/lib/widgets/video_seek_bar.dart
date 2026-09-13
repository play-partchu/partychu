import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 앱 전체가 공유하는 동영상 진행바 — 큰 카드(릴스형 피드)에서 처음 만들어진
// 스타일 그대로다. 평소엔 2px로 아주 얇게 떠 있다가, 화면 또는 진행바 자체를
// 터치하면(active=true) 4px로 살짝 두꺼워지며 현재/전체 시간을 잠깐 보여준다
// — 두꺼워지는 애니메이션과 시간 표시/숨김 타이밍은 부모가 관리하고, 이
// 위젯은 그 상태([active]/[onInteract])를 그대로 반영만 한다. 유튜브 쇼츠처럼
// 화면을 덮는 두꺼운 컨트롤 대신, 평소엔 거의 보이지 않을 만큼 얇게 둬서 영상
// 감상을 방해하지 않는다. 파티 상세페이지(MediaGallery)도 이 위젯을 그대로
// 재사용해 색상·두께·터치/드래그 동작이 완전히 동일하다.
// ─────────────────────────────────────────────────────────────────────────────
class VideoSeekBar extends StatefulWidget {
  final VideoPlayerController controller;
  final bool active;
  final VoidCallback onInteract;

  const VideoSeekBar({
    super.key,
    required this.controller,
    required this.active,
    required this.onInteract,
  });

  @override
  State<VideoSeekBar> createState() => _VideoSeekBarState();
}

class _VideoSeekBarState extends State<VideoSeekBar> {
  // 드래그하는 동안에는 seekTo()의 실제 반영(네트워크 지연)을 기다리지 않고
  // 손가락 위치를 그대로 진행률로 써서 끊김 없이 움직인다.
  double? _dragFraction;

  void _seekToFraction(double fraction) {
    final duration = widget.controller.value.duration;
    if (duration <= Duration.zero) return;
    widget.controller.seekTo(duration * fraction.clamp(0.0, 1.0));
  }

  void _handleLocalDx(double dx, double width) {
    if (width <= 0) return;
    final fraction = (dx / width).clamp(0.0, 1.0);
    setState(() => _dragFraction = fraction);
    _seekToFraction(fraction);
  }

  String _formatDuration(Duration d) {
    final totalSeconds = d.inSeconds < 0 ? 0 : d.inSeconds;
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        final duration = value.duration;
        final position = value.position;
        final liveFraction = duration.inMilliseconds > 0
            ? (position.inMilliseconds / duration.inMilliseconds).clamp(
                0.0,
                1.0,
              )
            : 0.0;
        final fraction = _dragFraction ?? liveFraction;

        return LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) {
                widget.onInteract();
                _handleLocalDx(d.localPosition.dx, constraints.maxWidth);
              },
              onHorizontalDragStart: (d) {
                widget.onInteract();
                _handleLocalDx(d.localPosition.dx, constraints.maxWidth);
              },
              onHorizontalDragUpdate: (d) =>
                  _handleLocalDx(d.localPosition.dx, constraints.maxWidth),
              onHorizontalDragEnd: (_) => setState(() => _dragFraction = null),
              child: Padding(
                // 실제 바는 얇지만 터치 영역은 위아래로 넉넉하게 잡아 탭/드래그가 쉽다.
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedOpacity(
                      opacity: widget.active ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 180),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Text(
                          '${_formatDuration(position)} / ${_formatDuration(duration)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      height: widget.active ? 4 : 2.2,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: fraction.isFinite ? fraction : 0.0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF6FA0),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

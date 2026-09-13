import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:party_app/utils/feed_video_manager.dart';
import 'package:party_app/widgets/partychu_ui.dart' show PartyChuColors;

/// 찜/공유/음소거처럼 앱 전체에서 반복되는 "프리미엄 아이콘 버튼"의 공통
/// 인터랙션 껍데기 — 원형 배경 없이 아이콘만 놓고, 누르면 0.9→1.0 스케일
/// (150ms)로 살짝 눌리는 느낌을 준 뒤, 그림자 대신 아주 은은한 핑크/보라
/// 네온 글로우만 감돈다. 사진·동영상처럼 배경이 어두워질 수 있는 곳에서도
/// 아이콘이 묻히지 않도록 아주 옅은 블랙 그림자로 먼저 대비를 잡아준다.
class PartyChuIconTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final String? tooltip;
  final Color glowColor;
  final double glowAlpha;
  final double glowBlur;
  final EdgeInsetsGeometry padding;
  // false면 그림자/글로우 없이 아이콘 자체 색만 남긴다(음소거 버튼처럼
  // 번짐 없는 깔끔한 느낌이 필요할 때).
  final bool glow;

  const PartyChuIconTap({
    super.key,
    required this.child,
    this.onTap,
    this.tooltip,
    this.glowColor = PartyChuColors.primary,
    this.glowAlpha = 0.22,
    this.glowBlur = 7,
    this.padding = const EdgeInsets.all(8),
    this.glow = true,
  });

  @override
  State<PartyChuIconTap> createState() => _PartyChuIconTapState();
}

class _PartyChuIconTapState extends State<PartyChuIconTap> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    Widget result = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
      onTapUp: widget.onTap == null ? null : (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: Padding(
        padding: widget.padding,
        child: AnimatedScale(
          scale: _pressed ? 0.9 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: widget.glow
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      const BoxShadow(
                        color: Color(0x1F000000),
                        blurRadius: 2.5,
                      ),
                      BoxShadow(
                        color: widget.glowColor.withValues(
                          alpha: _pressed
                              ? (widget.glowAlpha + 0.28).clamp(0.0, 1.0)
                              : widget.glowAlpha,
                        ),
                        blurRadius: _pressed
                            ? widget.glowBlur * 1.7
                            : widget.glowBlur,
                        spreadRadius: _pressed ? 1.4 : 0.4,
                      ),
                    ],
                  ),
                  child: widget.child,
                )
              : widget.child,
        ),
      ),
    );
    if (widget.tooltip != null) {
      result = Tooltip(message: widget.tooltip!, child: result);
    }
    return result;
  }
}

/// 공유 아이콘 버튼 — 흔한 노드형(●─●─●) 공유 아이콘 대신, 모서리가 열린
/// 사각형에서 화살표가 빠져나가는 Hugeicons의 샤프한 "내보내기" 형태를
/// 쓴다. 흰색 라인 + 아주 옅은 핑크 글로우로 사진/동영상 위에서도 또렷하게
/// 뜬다.
class ShareIconButton extends StatelessWidget {
  final VoidCallback onTap;
  final double size;
  final Color color;

  const ShareIconButton({
    super.key,
    required this.onTap,
    this.size = 26,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return PartyChuIconTap(
      onTap: onTap,
      tooltip: '공유',
      glowColor: PartyChuColors.primary,
      glow: false,
      child: HugeIcon(
        icon: HugeIcons.strokeRoundedShare04,
        color: color,
        size: size,
      ),
    );
  }
}

/// 전역 음소거 상태(FeedVideoManager.instance.mutedNotifier)를 보여주고
/// 전환하는 아이콘 버튼 — 재생 중인 모든 동영상이 이 상태 하나를 공유한다.
/// 소리 켜짐/꺼짐은 같은 스피커 모양에 사운드 웨이브가 있는지(켜짐) X
/// 표시가 있는지(꺼짐)로 한눈에 구분되고, 색조도 밝은 핑크(켜짐)/짙은
/// 핑크(꺼짐)로 갈린다.
class MuteToggleIconButton extends StatelessWidget {
  final double size;
  final Color activeColor;
  final Color mutedColor;
  final EdgeInsetsGeometry padding;

  const MuteToggleIconButton({
    super.key,
    this.size = 26,
    this.activeColor = PartyChuColors.primary,
    this.mutedColor = PartyChuColors.primaryDeep,
    this.padding = const EdgeInsets.all(8),
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: FeedVideoManager.instance.mutedNotifier,
      builder: (context, muted, _) {
        final color = muted ? mutedColor : activeColor;
        return PartyChuIconTap(
          onTap: () => FeedVideoManager.instance.setMuted(!muted),
          tooltip: muted ? '소리 켜기' : '소리 끄기',
          glowColor: color,
          padding: padding,
          glow: false,
          child: HugeIcon(
            icon: muted
                ? HugeIcons.strokeRoundedVolumeMute02
                : HugeIcons.strokeRoundedVolumeHigh,
            color: color,
            size: size,
          ),
        );
      },
    );
  }
}

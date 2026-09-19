import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

// ══════════════════════════════════════════════════════════════════════════
// 큰 화면 보기의 **가로형 동영상** 표시.
//
// 세로 화면에서 가로 영상을 cover로 채우면 좌우가 크게 잘린다. 그래서 가로
// 영상만 이렇게 그린다:
//   - 가운데: 원본 비율 그대로 contain(잘림·찌그러짐 없음)
//   - 위/아래 빈 곳: **같은 영상**을 cover로 키워 흐리게 + 살짝 어둡게
//
// 두 겹 모두 같은 VideoPlayerController의 화면(텍스처)을 그린다 — 영상을
// 두 번 받거나 두 번 디코드하지 않고, 재생 위치도 따로 놀 수 없다.
//
// 가로/세로 판정은 영상을 실제로 불러온 뒤의 크기로만 한다
// ([isLandscapeVideoSize]). 썸네일이나 카드 크기로 추정하지 않는다.
// ══════════════════════════════════════════════════════════════════════════

/// 불러온 영상의 실제 크기로 가로형인지 — 정사각형·크기 미상은 세로 취급
/// (기존 표시 그대로).
bool isLandscapeVideoSize(Size size) =>
    size.width > 0 && size.height > 0 && size.width > size.height;

/// 배경 블러 세기와 어둡기.
const double landscapeBackdropBlur = 28;
const double landscapeBackdropDim = 0.45;

class FeedLandscapeVideo extends StatelessWidget {
  /// 실제 영상의 가로/세로 비율(1보다 크다).
  final double aspectRatio;

  /// 영상 화면 — 같은 컨트롤러의 `VideoPlayer`를 돌려준다. 가운데와 배경이
  /// 각각 한 번씩 부른다.
  final Widget Function() player;

  /// 웹 전용 배경. 웹의 영상 화면은 `<video>` 요소 하나라서 두 곳에 동시에
  /// 붙일 수 없다 — 웹에서는 영상 대신 이것(썸네일)을 흐리게 깐다.
  final Widget? webBackdrop;

  /// 테스트에서 웹 분기를 확인할 때만 쓴다.
  @visibleForTesting
  final bool? forceWeb;

  const FeedLandscapeVideo({
    super.key,
    required this.aspectRatio,
    required this.player,
    this.webBackdrop,
    this.forceWeb,
  });

  @override
  Widget build(BuildContext context) {
    final web = forceWeb ?? kIsWeb;
    final backdropSource = web ? webBackdrop : player();

    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        if (backdropSource != null)
          ClipRect(
            child: ImageFiltered(
              key: const ValueKey('landscape-backdrop'),
              imageFilter: ui.ImageFilter.blur(
                sigmaX: landscapeBackdropBlur,
                sigmaY: landscapeBackdropBlur,
                tileMode: TileMode.clamp,
              ),
              child: FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: aspectRatio * 100,
                  height: 100,
                  child: backdropSource,
                ),
              ),
            ),
          ),
        ColoredBox(color: Colors.black.withValues(alpha: landscapeBackdropDim)),
        Center(
          child: AspectRatio(
            key: const ValueKey('landscape-foreground'),
            aspectRatio: aspectRatio,
            child: player(),
          ),
        ),
      ],
    );
  }
}

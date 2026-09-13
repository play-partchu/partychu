import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:party_app/widgets/list_card_shell.dart';

/// "파티츄 혜택" 명판을 **카드 위쪽 모서리에 걸쳐서** 얹는 배지 — 목록 카드
/// 전용이다. 전체화면 큰 카드는 모서리가 아니라 제목을 기준으로 붙이므로 이
/// 오버레이가 아니라 [PartychuPerkPlaqueImage]를 쓴다.
///
/// 사진·영상이 주인공이고 명판은 보조 요소다. 그래서:
/// - **사진을 최대한 건드리지 않는 모서리**를 골라 붙인다
///   ([PartychuPerkPlaqueSize.corner]). 사진이 카드 폭 전체를 쓰는 2열 기본
///   카드는 왼쪽 위, 사진이 왼쪽 104 썸네일뿐인 **가로형 작은 카드는 오른쪽
///   위** — 작은 카드에서는 명판이 사진 반대쪽 정보 영역에 붙으므로 대표
///   이미지를 1px도 가리지 않는다.
/// - 세로로는 명판 높이의 절반 가까이를 **카드 위쪽 경계 바깥으로** 내보낸다
///   ([PartychuPerkPlaqueSize.topOverhangRatio]). "사진 위에 붙은 스티커"가
///   아니라 "카드 모서리에 걸린 명판"으로 보이게 하는 게 목적이고, 덕분에
///   카드 안쪽으로 들어오는 높이가 작은 카드 정보 열의 위쪽 빈 여백
///   ([ListCardShell.contentPadding] 10px) 안에 들어가 글자·배지와도 겹치지
///   않는다.
/// - 카드 종류마다 자리가 들쭉날쭉하지 않도록 기준점은 항상 **카드의 위쪽
///   모서리** 하나뿐이다. 사진 비율·카드 높이가 달라도 위치가 변하지 않는다.
/// - 크기는 "파티츄 혜택" 글자가 읽히는 선까지만 잡는다
///   ([PartychuPerkPlaqueSize] 참고).
///
/// ## 레이아웃에 전혀 관여하지 않는다
///
/// 카드 껍데기가 이 위젯을 `Positioned.fill`로 덮어씌우므로 카드 크기·미디어
/// 높이·카드 간격이 1px도 변하지 않는다. 명판이 차지할 자리를 만들려고 카드에
/// padding이나 margin을 더하지 않는다. 경계 밖으로 나가는 부분이 잘리지 않는
/// 것은 카드 셸의 `Stack(clipBehavior: Clip.none)`이 보장한다.
///
/// ```
///  2열 그리드 카드              가로형 작은 카드(목록·지도·플레이스)
/// [혜택]                                              [혜택]
/// ╭┴────────────────╮         ╭────────────┬─────────────┴─╮
/// │    카드 사진    │         │ 썸네일 104 │  제목·날짜    │
///
///  전체화면 큰 카드 — 모서리가 아니라 제목을 기준으로 붙는다
///  ([PartychuPerkPlaqueImage]).
/// │  [혜택]                     │
/// │  ▓ 파티 제목 ▓              │
/// ```
///
/// 사진 위에 얹는 다른 배지(모집 상태 등)는 명판 아래로 내려 겹치지 않게
/// 한다 — 얼마나 내릴지는 [PartychuPerkPlaqueSize.overlayBadgeTop]가 알려준다.
class PartychuPerkPlaquePainter extends CustomPainter {
  /// 명판 크기를 잡을 기준 폭. null이면 그려지는 영역(=카드) 폭을 쓴다.
  ///
  /// 명판이 사진 위에 올라가는 배치([PartychuPerkPlaqueCorner.topLeft])에서만
  /// 의미가 있다 — 사진 폭을 넘기면 명판이 사진 밖으로 삐져나오지 않는 크기로
  /// 잡힌다. 사진 반대쪽에 붙는 작은 카드는 사진 폭과 무관하므로 넘기지 않는다.
  final double? mediaWidth;

  /// 카드 종류별 크기 규칙.
  final PartychuPerkPlaqueSize size;

  PartychuPerkPlaquePainter({
    this.mediaWidth,
    this.size = PartychuPerkPlaqueSize.standard,
  }) : super(repaint: PartychuPerkPlaqueArt.revision);

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final image = PartychuPerkPlaqueArt.value;
    if (image == null) return;

    final area = math.min(mediaWidth ?? canvasSize.width, canvasSize.width);
    if (area < 48) return;

    // 미디어 폭에 비례하되 위아래로 묶는다 — 좁은 카드에서 글자가 아예 뭉개질
    // 만큼 작아지지도, 넓은 카드에서 혼자 커지지도 않게. 마지막 min은 명판이
    // 미디어 밖으로 삐져나오지 않게 하는 안전장치다.
    final width = math.min(
      (area * size.widthRatio).clamp(size.minWidth, size.maxWidth),
      area - _kEdgeGap * 2,
    );
    if (width <= 0) return;
    // 원본 비율 그대로 — 기울이거나 늘리지 않는다(가로만 늘리면 글자가 뭉개진다).
    final height = width * image.height / image.width;

    // 세로 위치는 **카드 위쪽 경계(y=0)** 기준이다 — 사진 높이나 비율을 보지
    // 않으므로 어떤 카드에서도 같은 자리에 온다. 양수 비율이면 그만큼 경계
    // 바깥(위)으로 걸치고, 음수면 카드 안쪽으로 들어간다.
    final top = -height * size.topOverhangRatio;
    // 가로 위치도 카드 경계 기준 — 어느 쪽 모서리에 붙일지는 카드 종류가
    // 정한다(작은 카드는 사진이 없는 오른쪽).
    final left = switch (size.corner) {
      PartychuPerkPlaqueCorner.topLeft => _kEdgeGap,
      PartychuPerkPlaqueCorner.topRight => canvasSize.width - width - _kEdgeGap,
    };

    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(left, top, width, height),
      Paint()
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(covariant PartychuPerkPlaquePainter oldDelegate) =>
      oldDelegate.mediaWidth != mediaWidth || oldDelegate.size != size;
}

/// 명판을 붙일 카드 위쪽 모서리 — **사진이 없는 쪽**을 고른다.
enum PartychuPerkPlaqueCorner {
  /// 왼쪽 위. 사진이 카드 폭 전체를 쓰는 카드(2열 기본 카드·전체화면 카드)는
  /// 어느 쪽이든 사진 위이므로, 정보가 몰리지 않는 왼쪽 위에 둔다.
  topLeft,

  /// 오른쪽 위. 사진이 왼쪽 104 썸네일뿐인 가로형 작은 카드 — 사진 반대쪽
  /// 정보 열 위라서 대표 이미지를 전혀 가리지 않는다.
  topRight,
}

/// 카드 종류별 명판 배치 규칙 — 크기(기준 폭 대비 비율과 그 위아래 한계),
/// 어느 모서리에 붙는지, 카드 위쪽 경계에 얼마나 걸치는지.
///
/// 폭은 "파티츄 혜택" 글자가 읽히는 선까지만 잡는다. 사진을 덜 가리는 몫은
/// 폭을 줄이는 대신 [corner]와 [topOverhangRatio]로 해결한다 — 명판 그림
/// 비율은 절대 건드리지 않으므로(원본 그대로) 폭을 줄이면 글자도 같이 작아져
/// 읽을 수 없게 된다.
enum PartychuPerkPlaqueSize {
  /// 가로형 작은 카드(목록·지도·플레이스 작은 카드) — 사진 반대쪽인 정보 열
  /// 오른쪽 위 빈 여백에 붙는다.
  ///
  /// 실제 그려지는 크기를 [standard](기본 2열 카드)와 **같게** 맞춘 값이다.
  /// 두 카드는 기준 폭이 다르다 — 작은 카드는 카드 폭 전체(화면폭−32), 기본
  /// 카드는 2열의 한 칸((화면폭−42)÷2)이라 절반쯤 좁다. 그래서 비율도 [standard]
  /// 의 절반 남짓(0.37 → 0.18)이어야 같은 픽셀 폭이 나온다. 상·하한은 [standard]
  /// 와 똑같이 둬서 아주 좁은/넓은 화면에서도 두 카드가 같은 값에 걸린다.
  ///  · 360dp 화면: 작은 카드 328×0.18 = 59.0 / 기본 카드 159×0.37 = 58.8
  ///  · 430dp 화면: 둘 다 상한 70
  ///
  /// [topOverhangRatio]는 [standard]보다 크다 — 폭이 커진 만큼 높이도 커지므로,
  /// 카드 안으로 들어오는 부분(21.7×0.45 ≒ 9.8px)이 정보 열 위쪽 빈 여백
  /// ([ListCardShell.contentPadding] 10px)을 넘지 않게 더 내보낸다.
  compact(
    widthRatio: 0.18,
    minWidth: 48,
    maxWidth: 70,
    topOverhangRatio: 0.55,
    corner: PartychuPerkPlaqueCorner.topRight,
  ),

  /// 기본 2열 그리드 카드 — 사진 폭의 37%.
  ///
  /// (전체화면 큰 카드는 이 오버레이 방식을 쓰지 않는다 — 제목을 기준으로
  /// 붙는 [PartychuPerkPlaqueImage]를 쓴다.)
  standard(
    widthRatio: 0.37,
    minWidth: 48,
    maxWidth: 70,
    topOverhangRatio: 0.45,
    corner: PartychuPerkPlaqueCorner.topLeft,
  );

  const PartychuPerkPlaqueSize({
    required this.widthRatio,
    required this.minWidth,
    required this.maxWidth,
    required this.topOverhangRatio,
    required this.corner,
  });

  final double widthRatio;
  final double minWidth;
  final double maxWidth;

  /// 명판 높이 대비, 카드 위쪽 경계 **바깥(위)으로** 내보낼 비율.
  ///  ·  0.45 → 높이의 45%가 카드 밖으로 나가고 55%만 카드 안에 걸친다.
  ///  · -0.25 → 걸치지 않고 카드 안쪽으로 높이의 25%만큼 들여 그린다.
  final double topOverhangRatio;

  final PartychuPerkPlaqueCorner corner;

  /// 이 명판이 **사진을** 덮는 최대 높이(px) — 카드 위쪽 경계에서부터 잰다.
  /// 폭이 [maxWidth]까지 커진 최악의 경우 기준이라 실제로는 이보다 덜 덮는다.
  /// 사진 반대쪽 모서리([PartychuPerkPlaqueCorner.topRight])에 붙는 배치는
  /// 사진을 아예 덮지 않으므로 0이다.
  double get mediaCoverHeight => corner == PartychuPerkPlaqueCorner.topRight
      ? 0
      : maxWidth * _kPlaqueAspectRatio * (1 - topOverhangRatio);

  /// 사진 위에 얹는 다른 배지(모집 상태 등)를 명판과 겹치지 않게 두려면
  /// 필요한 최소 `top` 값 — 명판이 덮는 높이 + 배지 간격. 명판이 사진을 덮지
  /// 않는 배치에서는 배지 원래 자리(10)를 그대로 돌려준다.
  double get overlayBadgeTop => math.max(10, mediaCoverHeight + 4);
}

/// 카드 위에 얹을 명판 한 장. **크기를 스스로 정하지 않으므로** 부르는 쪽에서
/// `Positioned.fill`(또는 카드 껍데기의 `decorationOverlay`)로 카드 전체를
/// 덮게 넣어야 한다 — 그 영역의 폭을 기준으로 명판 크기를 계산한다.
Widget partychuPerkPlaqueOverlay({
  PartychuPerkPlaqueSize size = PartychuPerkPlaqueSize.standard,
  double? mediaWidth,
}) {
  PartychuPerkPlaqueArt.ensureLoaded();
  return IgnorePointer(
    child: CustomPaint(
      painter: PartychuPerkPlaquePainter(mediaWidth: mediaWidth, size: size),
    ),
  );
}

/// 가로형 작은 카드(왼쪽 104 정사각 썸네일 + 오른쪽 정보 열)용 명판 —
/// 작은 카드·지도 목록·플레이스 작은 카드가 **모두 이 함수 하나**를 쓴다(세
/// 카드의 명판 위치·크기가 따로 놀 수 없다).
///
/// 명판이 썸네일 반대쪽(정보 열 오른쪽 위)에 붙으므로 [mediaWidth]는 넘기지
/// 않는다 — 썸네일 폭은 이제 명판 크기와 아무 상관이 없고, 크기는
/// [PartychuPerkPlaqueSize.compact]의 좁은 상·하한이 사실상 고정한다.
Widget partychuPerkPlaqueOverlayCompact() =>
    partychuPerkPlaqueOverlay(size: PartychuPerkPlaqueSize.compact);

/// **제목 바로 위**에 놓는 명판 — 전체화면 큰 카드가 쓴다.
///
/// 위 두 함수(오버레이)와 결정적으로 다른 점: 화면·카드 모서리에 그리지 않고
/// 자기 크기를 가진 **보통 위젯**이라, 제목이 들어 있는 Column에 그대로 끼워
/// 넣는다. 그래서 제목 줄 수·아래 정보 줄 수가 달라져 제목이 위아래로
/// 움직여도 명판이 언제나 제목을 따라간다(예전에는 화면 왼쪽 위에 고정돼
/// 제목과 아무 관계가 없었다).
///
/// 크기는 화면 폭과 무관하게 [width] 하나로 정해진다 — 제목과 나란히 읽히는
/// 요소라 화면이 넓다고 혼자 커지면 제목과의 균형이 깨진다.
class PartychuPerkPlaqueImage extends StatelessWidget {
  const PartychuPerkPlaqueImage({super.key, this.width = _kTitleAnchoredWidth});

  final double width;

  @override
  Widget build(BuildContext context) {
    PartychuPerkPlaqueArt.ensureLoaded();
    return IgnorePointer(
      child: SizedBox(
        width: width,
        // 원본 비율 그대로 — 늘리거나 눌러 그리지 않는다.
        height: width * _kPlaqueAspectRatio,
        child: CustomPaint(painter: _PartychuPerkPlaqueFitPainter()),
      ),
    );
  }
}

/// 주어진 영역을 그대로 채우는 명판 — 자리와 크기는 부모가 정한다
/// ([PartychuPerkPlaqueImage]의 `SizedBox`).
class _PartychuPerkPlaqueFitPainter extends CustomPainter {
  _PartychuPerkPlaqueFitPainter()
    : super(repaint: PartychuPerkPlaqueArt.revision);

  @override
  void paint(Canvas canvas, Size size) {
    final image = PartychuPerkPlaqueArt.value;
    if (image == null) return;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.medium,
    );
  }

  // 그림 자체가 바뀌는 경우(에셋 로딩 완료)는 repaint 통지로 처리한다.
  @override
  bool shouldRepaint(covariant _PartychuPerkPlaqueFitPainter oldDelegate) =>
      false;
}

/// 명판 그림 — "파티츄 혜택" 문구가 박힌 로즈골드 명판(배경 투명).
const String _kPlaqueAsset = 'assets/images/partychu_perk_plaque_v2.png';

/// [_kPlaqueAsset]의 높이÷폭(337×124). 오버레이로 그릴 때는 읽어온 이미지의
/// 원본 크기를 쓰고, 이 값은 그리기 **전에** 자리·높이 계산이 필요한 곳
/// ([PartychuPerkPlaqueSize.mediaCoverHeight]·[PartychuPerkPlaqueImage])에 쓴다.
const double _kPlaqueAspectRatio = 124 / 337;

/// 카드 **좌·우 가장자리**에서 떨어지는 거리(오버레이 배치). 세로 위치는 이
/// 값과 무관하다([PartychuPerkPlaqueSize.topOverhangRatio]가 정한다).
const double _kEdgeGap = 6.0;

/// 제목 위에 붙는 명판([PartychuPerkPlaqueImage])의 기본 폭 — 예전에 화면
/// 왼쪽 위에 고정으로 그릴 때의 최대 폭과 같은 값이라, 자리만 옮기고 크기는
/// 그대로다.
const double _kTitleAnchoredWidth = 88.0;

/// 명판 그림을 한 번만 읽어 들고 있는 곳.
class PartychuPerkPlaqueArt {
  PartychuPerkPlaqueArt._();

  static ui.Image? _loaded;
  static bool _loading = false;

  /// 그림이 준비되면 값이 바뀐다 — [CustomPainter.repaint]로 넘겨 이미 떠 있는
  /// 카드들이 다시 그려지게 한다.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static ui.Image? get value => _loaded;

  /// 명판이 처음 필요할 때 자동으로 불린다(중복 호출 안전). 첫 목록이 뜨자마자
  /// 명판이 보이도록 앱 시작 시 미리 한 번 더 불러도 된다.
  static void ensureLoaded() {
    if (_loaded != null || _loading) return;
    _loading = true;
    _load().then(
      (image) {
        _loaded = image;
        revision.value++;
      },
      onError: (Object _) {
        // 에셋이 없거나 깨졌으면 명판만 안 그린다 — 카드 자체는 멀쩡하다.
        _loading = false;
      },
    );
  }

  static Future<ui.Image> _load() async {
    final bytes = await rootBundle.load(_kPlaqueAsset);
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
    return (await codec.getNextFrame()).image;
  }
}

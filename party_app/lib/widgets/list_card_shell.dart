import 'package:flutter/material.dart';
import 'package:party_app/utils/video_crop.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 목록 카드 "껍데기" 공용 셸 — 카드의 크기·비율·여백·모서리·그림자만 담는다.
//
// 파티 카드(지도 '이 근처 파티' / 파티 목록 기본 카드)와 플레이스 카드가 서로
// 같은 값을 각자 하드코딩하다 조금씩 어긋나던 것을 한 곳으로 모은 것이다 —
// 여기 상수를 고치면 두 탭의 카드가 항상 같이 바뀐다.
//
// 안에 들어가는 "내용"(어떤 텍스트/배지를 어떤 순서로 그릴지)은 각 카드가
// 자기 데이터에 맞게 만들어 넣는다. 셸은 내용에 대해 아무것도 모른다.
// ─────────────────────────────────────────────────────────────────────────────

/// 가로형 목록 카드 셸 — 지도 '이 근처 파티' 카드(PartyCard)와 플레이스
/// "작은 화면" 카드가 공유한다. 왼쪽 정사각 썸네일 + 가운데 정보 열 +
/// (선택) 오른쪽 좁은 숫자 열 구조를 전제로 한 크기값들이다.
///
/// 크기·여백·모서리·배경은 파티 "작은 카드"([PartyCompactCard])를 기준으로
/// 맞춰져 있다 — 그쪽도 이 상수를 그대로 가져다 쓰므로 세 카드가 항상 같은
/// 모양이다. 핵심은 **썸네일이 카드 위·아래·왼쪽 끝에 바로 붙는다**는 것:
/// 세로 여백이 0이라 사진/동영상 위로 카드 배경이 비치지 않는다.
class ListCardShell extends StatelessWidget {
  /// 왼쪽 썸네일 한 변(정사각) — 정보 열의 높이도 이 값으로 고정된다.
  /// 파티 작은 카드와 같은 104.
  static const double imgSize = 104.0;

  /// 카드 바깥 모서리.
  static const double radius = 16.0;

  /// 썸네일의 **안쪽**(정보 열과 맞닿는 오른쪽) 모서리.
  /// 바깥쪽(왼쪽) 모서리는 카드와 똑같이 [radius]를 쓴다 — 세로 여백이 0이라
  /// 값이 다르면 둥근 모서리 틈으로 카드 배경이 비친다.
  static const double thumbRadius = 14.0;

  /// 카드 사이 세로 간격.
  static const EdgeInsets outerMargin = EdgeInsets.only(bottom: 8);

  /// 카드 안쪽 여백 — 썸네일이 카드 위·아래·왼쪽 끝에 바로 붙도록 세 방향은
  /// 0이고, 정보 열 바깥쪽인 오른쪽만 남긴다.
  static const EdgeInsets innerPadding = EdgeInsets.fromLTRB(0, 0, 12, 0);

  /// 썸네일과 정보 열 사이 간격.
  static const double contentGap = 12.0;

  /// 썸네일을 뺀 나머지(정보 열)에만 주는 세로 여백.
  ///
  /// 카드 [innerPadding]을 0으로 만들어 사진/동영상을 카드 끝에 붙인 대신,
  /// 글자·배지가 카드 모서리에 닿지 않도록 여백을 이쪽으로 옮긴 것이다 —
  /// 덕분에 텍스트/배지의 세로 위치는 예전(카드 전체 padding 10)과 같다.
  static const EdgeInsets contentPadding = EdgeInsets.symmetric(vertical: 10);

  /// 오른쪽 숫자 열(참가인원 / 최대 수용 인원) 폭.
  ///
  /// 좁은 화면에서 이 열이 카드 폭을 과하게 먹지 않도록 일부러 작게 잡았고,
  /// "12/100"처럼 긴 값이 들어와도 열이 넓어지거나 두 줄로 접히지 않게
  /// [trailingStat]에서 글자를 이 폭에 맞춰 줄인다.
  static const double trailingWidth = 34.0;

  /// 정보 열의 각 줄(배지 / 제목 / 지역 / 날짜·요금) 사이 간격.
  static const double rowGap = 6.0;

  /// 배지 사이 가로 간격.
  static const double badgeSpacing = 4.0;

  /// 배지가 다음 줄로 접혔을 때 줄 사이 간격.
  static const double badgeRunSpacing = 3.0;

  /// 카드 배경 — 썸네일이 카드 끝에 바로 붙으므로 테두리선 대신 옅은 분홍
  /// 그림자로만 카드를 띄운다(파티 작은 카드와 동일). 예전의 회색 배경 +
  /// 1px 테두리는 세로 여백이 없어지면 사진 가장자리에 선이 겹쳐 보였다.
  static const Color background = Colors.white;

  static const BoxShadow baseShadow = BoxShadow(
    color: Color(0x0FFF6FA0),
    blurRadius: 8,
    offset: Offset(0, 2),
  );

  final Widget child;
  final VoidCallback onTap;

  /// 카드 그림자에 더할 값 — 파티츄 전용 혜택 글로우처럼 카드별로 다른 효과용.
  final List<BoxShadow> extraShadows;

  /// 카드 전체를 덮는 장식 층(파티츄 전용 혜택 명판 등). 터치는 통과시킨다.
  ///
  /// 테두리를 [BoxDecoration.border]로 주면 그만큼 안쪽 내용이 밀려 카드마다
  /// 썸네일 위치가 달라지므로, 크기에 영향을 주지 않는 덧그리기로 받는다.
  ///
  /// 카드 크기로 늘리는 것은 셸이 한다([GridCardShell]과 같다) — 넘길 때는
  /// 크기를 스스로 정하지 않는 CustomPaint 같은 것을 그대로 주면 된다.
  final Widget? decorationOverlay;

  const ListCardShell({
    super.key,
    required this.child,
    required this.onTap,
    this.extraShadows = const [],
    this.decorationOverlay,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: outerMargin,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [baseShadow, ...extraShadows],
        ),
        // Clip.none — 카드 경계선에 딱 붙여 그리는 장식층(얼리버드 테두리 등)이
        // Stack 기본값(Clip.hardEdge)에 잘려나가지 않게 한다.
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(padding: innerPadding, child: child),
            if (decorationOverlay != null)
              Positioned.fill(child: IgnorePointer(child: decorationOverlay!)),
          ],
        ),
      ),
    );
  }

  /// 썸네일 박스 — 폭은 [imgSize]로 고정하고, **높이는 주어진 만큼 꽉 채운다**.
  ///
  /// 어떤 비율의 원본이 와도 이 박스 안에서만 잘린다(세로로 긴 사진이 카드
  /// 높이를 밀어 올리지 않는다). 높이를 [imgSize]로 못 박지 않는 것이 핵심인데,
  /// 고정해두면 정보 열이 104보다 길어지는 순간 카드만 늘어나고 사진은 104에
  /// 머물러 **사진 아래에 흰 여백**이 남는다([horizontalBody] 참고).
  /// 카드 높이가 104일 때는 예전과 똑같은 정사각 썸네일이다.
  ///
  /// 바깥쪽(왼쪽) 모서리만 카드 모서리와 똑같이 [radius]로 둥글려, 상하좌
  /// 여백이 0인 상태에서도 사진과 카드 모서리가 그대로 이어진다.
  static Widget thumbnailBox({required Widget child}) => ClipRRect(
    borderRadius: const BorderRadius.only(
      topLeft: Radius.circular(radius),
      bottomLeft: Radius.circular(radius),
      topRight: Radius.circular(thumbRadius),
      bottomRight: Radius.circular(thumbRadius),
    ),
    child: SizedBox(width: imgSize, height: double.infinity, child: child),
  );

  /// 가로형 카드의 본문 — 썸네일 + 정보 열 (+ 오른쪽 숫자 열).
  ///
  /// **사진이 카드 세로 높이를 정확히 채운다.** 예전에는 104×104 정사각
  /// 썸네일과 정보 열을 Row에 그냥 나란히 놓았는데, 정보 열이 104보다
  /// 길어지는 순간(배지가 두 줄로 접히거나 줄이 하나 더 붙을 때) 카드만
  /// 늘어나고 사진은 104에 머물러 사진 아래에 빈 공간이 남았다.
  ///
  /// 그래서 **카드 높이는 정보 열이 정하게 두고**(Stack의 크기를 정하는
  /// 유일한 비-Positioned 자식), 사진은 그 높이에 맞춰 위아래 끝까지 늘린다.
  /// 정보 열이 짧을 때는 [infoColumn]의 최소 높이([imgSize])가 그대로 살아
  /// 있어 카드 모양이 예전과 픽셀 단위로 같다.
  ///
  /// IntrinsicHeight + CrossAxisAlignment.stretch를 쓰지 않은 이유:
  /// 배지 줄([badgeWrap])이 LayoutBuilder를 쓰는데 LayoutBuilder는 intrinsic
  /// 높이 계산을 지원하지 않아 디버그 빌드에서 그대로 예외가 난다.
  static Widget horizontalBody({
    required Widget thumbnail,
    required Widget info,
    Widget? trailing,
  }) => Stack(
    children: [
      // ① 카드 높이를 정하는 층 — 썸네일 자리는 폭만 비워둔다.
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: imgSize),
          const SizedBox(width: contentGap),
          Expanded(child: info),
          ?trailing,
        ],
      ),
      // ② 사진 층 — ①이 정한 높이를 위에서 아래까지 그대로 채운다.
      //    top/bottom을 함께 주므로 높이가 tight로 내려가고, BoxFit.cover가
      //    늘어난 영역까지 꽉 채운다(아래로 여백이 남지 않는다).
      Positioned(left: 0, top: 0, bottom: 0, width: imgSize, child: thumbnail),
    ],
  );

  /// 오른쪽 숫자 열 — 아이콘 + 값 + 단위를 세로 가운데 정렬로 쌓는다.
  /// (파티는 참가인원, 플레이스는 최대 수용 인원이 여기 들어간다.)
  ///
  /// 값은 [trailingWidth] 안에서 한 줄로만 그린다 — "12/100"처럼 긴 값이
  /// 두 줄로 접히면서 카드 높이를 밀어 올리거나 좁은 화면에서 열 폭을
  /// 넘기던 것을 막기 위해 폭이 모자라면 글자를 줄여 맞춘다.
  static Widget trailingStat({
    required IconData icon,
    required String value,
    required String unit,
  }) => SizedBox(
    width: trailingWidth,
    height: imgSize,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 13, color: const Color(0xFFFF6FA0)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFFFF6FA0),
            ),
          ),
        ),
        Text(unit, style: const TextStyle(fontSize: 9, color: Colors.black45)),
      ],
    ),
  );

  /// 카드 상단 배지 줄.
  ///
  /// Row로 나란히 붙이면 배지가 하나 늘어날 때마다 정보 열 폭을 그대로
  /// 넘겨 RenderFlex overflow("RIGHT OVERFLOWED BY … PIXELS")가 났다.
  /// Wrap이라 폭이 모자라는 순간 자연스럽게 다음 줄로 내려가고, 배지 하나가
  /// 혼자 정보 열보다 넓어지는 경우도 각 배지에 걸어둔 최대 폭(= 정보 열
  /// 폭)이 막아준다. 잘라내거나 숨기는 게 아니라 실제로 안 넘치게 하는 것이다.
  static Widget badgeWrap(List<Widget> badges) {
    if (badges.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: badgeSpacing,
        runSpacing: badgeRunSpacing,
        children: [
          for (final badge in badges)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth),
              child: badge,
            ),
        ],
      ),
    );
  }

  /// 썸네일 오른쪽 정보 열 — 넘겨준 줄들을 [rowGap] 간격으로 쌓는다.
  ///
  /// 높이는 썸네일과 같은 [imgSize]를 **최소값**으로만 쓴다. 고정해두면
  /// 배지가 두 줄로 접히는 순간 세로 overflow가 나기 때문에, 내용이 길어지면
  /// 카드가 그만큼 자연스럽게 늘어나게 했다.
  /// (빈 줄은 아예 넘기지 않는 쪽이 간격이 깔끔하다.)
  ///
  /// 세로 여백([contentPadding])은 카드가 아니라 여기서 준다 — 썸네일은 카드
  /// 끝에 붙고 글자만 안쪽으로 들어간다.
  static Widget infoColumn(List<Widget> rows) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: imgSize),
    child: Padding(
      padding: contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: rowGap),
            rows[i],
          ],
        ],
      ),
    ),
  );
}

/// 2열 그리드용 세로형 카드 셸 — 파티 "기본 카드"(PartyStandardCard)와
/// 플레이스 "기본 화면" 카드가 공유한다. 위쪽 고정 높이 미디어 + 아래쪽
/// 정보 영역 구조를 전제로 한 크기값들이다.
class GridCardShell extends StatelessWidget {
  /// 미디어 영역 높이 — 고정이라 사진 비율이 제각각이어도 목록이 들쑥날쑥
  /// 해지지 않는다.
  static const double imageHeight = 130.0;

  static const double radius = 16.0;

  /// 정보 영역 여백.
  static const EdgeInsets infoPadding = EdgeInsets.symmetric(
    horizontal: 10,
    vertical: 8,
  );

  static const BoxShadow baseShadow = BoxShadow(
    color: Color(0x0FFF6FA0),
    blurRadius: 8,
    offset: Offset(0, 2),
  );

  /// 미디어 영역을 꽉 채울 위젯(사진/동영상/플레이스홀더).
  final Widget media;

  /// 미디어 위에 얹을 배지·버튼들(Positioned 등). 미디어 영역 Stack 안에 그대로 들어간다.
  final List<Widget> mediaOverlays;

  /// 미디어 아래 정보 영역 내용.
  final Widget info;

  /// 카드 그림자에 더할 값 — 얼리버드 글로우처럼 카드별로 다른 효과용.
  final List<BoxShadow> extraShadows;

  /// 카드 전체를 덮는 장식 레이어(얼리버드 그라데이션 테두리, 파티츄 전용 혜택
  /// 명판 등). 터치는 통과시킨다. 카드 크기로 늘리는 것은 셸이 한다.
  final Widget? decorationOverlay;

  final VoidCallback onTap;

  const GridCardShell({
    super.key,
    required this.media,
    required this.info,
    required this.onTap,
    this.mediaOverlays = const [],
    this.extraShadows = const [],
    this.decorationOverlay,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [baseShadow, ...extraShadows],
        ),
        // Clip.none — 카드 경계선에 딱 붙여 그리는 장식층(얼리버드 테두리 등)이
        // Stack 기본값(Clip.hardEdge)에 잘려나가지 않게 한다.
        // (사진은 아래 ClipRRect가 따로 잘라내므로 영향 없다.)
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(radius),
                  ),
                  child: SizedBox(
                    height: imageHeight,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [media, ...mediaOverlays],
                    ),
                  ),
                ),
                Padding(padding: infoPadding, child: info),
              ],
            ),
            if (decorationOverlay != null)
              Positioned.fill(child: IgnorePointer(child: decorationOverlay!)),
          ],
        ),
      ),
    );
  }
}

/// [GridCardShell]의 미디어 영역에 사진을 그리는 공용 방식.
///
/// 그냥 `BoxFit.cover` 중앙 정렬로 넣으면 세로로 긴 사진의 가운데만 크게
/// 확대돼 보이는(= 과하게 잘린) 문제가 생긴다. 그래서 등록/수정 화면에서
/// 기본 카드 비율(카드폭×130) 미리보기로 지정해둔 초점([focalX]/[focalY])과
/// 확대 배율([scale])을 그대로 반영한다 — 값이 없는 기존 데이터는
/// 0.5/0.5/1.0이라 예전 렌더링과 픽셀 단위로 동일하다([CroppedMedia] 참고).
Widget gridCardPhoto({
  required String url,
  required double focalX,
  required double focalY,
  required double scale,
  Widget? errorChild,
}) {
  return CroppedMedia(
    cropX: focalX,
    cropY: focalY,
    cropScale: scale,
    child: Image.network(
      url,
      fit: BoxFit.cover,
      alignment: videoCropAlignment(focalX, focalY),
      errorBuilder: (ctx, e, st) =>
          errorChild ?? Container(color: const Color(0xFFFFE0EE)),
    ),
  );
}

import 'package:flutter/material.dart';

/// 플레이스 상세 "🎉 파티 | ✨ 이벤트" 2열 영역의 카드 **껍데기**.
///
/// 파티 카드([LinkedPartyCard])와 매장 이벤트 카드(_PromotionCard)가 이 껍데기
/// 하나를 함께 쓴다 — 나란히 선 두 카드의 모서리 둥근 정도·테두리·사진 자리·
/// 안쪽 여백이 **정의상 같아진다**. 예전에는 두 카드가 각자 Container를 그려서
/// 파티는 라운드 16·사진 없음, 이벤트는 라운드 14·사진 있음이라 한 영역 안에
/// 서로 다른 물건 두 개가 서 있었다.
///
/// 껍데기는 **자리만** 안다 — 무엇을 그릴지(제목·일정·혜택·CTA)는 각 카드가
/// 정한다. 그래서 이벤트 카드를 파티에 억지로 재사용하지 않으면서도 모양은
/// 어긋나지 않는다.
///
/// 색은 카드마다 다르다(파티 = 파티츄 핑크 선, 이벤트 = 샴페인 골드 선) —
/// 두 열이 무엇인지 테두리 색만으로 갈리는 기존 규칙 그대로다.
class OfferingCardShell extends StatelessWidget {
  const OfferingCardShell({
    super.key,
    required this.borderColor,
    required this.onTap,
    required this.content,
    this.background = Colors.white,
    this.media,
    this.mediaAspectRatio,
    this.mediaOverlays = const [],
    this.contentPadding = const EdgeInsets.fromLTRB(10, 9, 10, 10),
  });

  /// 카드 바깥선 색 — **바깥선 하나**만 두른다. 사진 영역과 글자 영역을 따로
  /// 두르면 한 장이 두 장으로 쪼개져 보인다.
  final Color borderColor;

  final Color background;

  final VoidCallback onTap;

  /// 카드 상단 사진/동영상. null이면 사진 자리 없이 내용만 그린다.
  final Widget? media;

  /// [media]가 들어갈 상자의 가로:세로 비율. 사진 원본 비율이 아니라 **카드가
  /// 정한 비율**이다 — 여기는 갤러리가 아니라 썸네일 카드라, 세로로 긴 사진이
  /// 들어와도 카드가 길어지지 않는다.
  final double? mediaAspectRatio;

  /// 사진 위에 얹을 배지(재생 아이콘, 콤보 배지 등).
  final List<Widget> mediaOverlays;

  final EdgeInsets contentPadding;

  final Widget content;

  static const double radius = 14;

  /// 사진 모서리는 카드보다 테두리 두께(1)만큼 안쪽이다 — 같은 값을 쓰면
  /// 사진 모서리가 테두리를 비집고 나온다.
  static const double _mediaRadius = radius - 1;

  @override
  Widget build(BuildContext context) {
    final m = media;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (m != null)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(_mediaRadius),
                ),
                child: AspectRatio(
                  aspectRatio: mediaAspectRatio ?? 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [m, ...mediaOverlays],
                  ),
                ),
              ),
            Padding(padding: contentPadding, child: content),
          ],
        ),
      ),
    );
  }
}

/// 카드 맨 아래 "자세히 보기 >" 한 줄 — 파티·이벤트 카드가 같은 자리에서 같은
/// 모양으로 쓴다(글자 크기·굵기·화살표까지). 색만 각 카드의 강조색이다.
class OfferingCardMoreLink extends StatelessWidget {
  const OfferingCardMoreLink({
    super.key,
    required this.color,
    this.label = '자세히 보기',
  });

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Flexible(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
      Icon(Icons.chevron_right, size: 16, color: color),
    ],
  );
}

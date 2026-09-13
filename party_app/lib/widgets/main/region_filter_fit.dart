import 'package:flutter/widgets.dart';

/// 장소대여 상단 줄의 **지역 필터 버튼을 어떻게 줄여 그릴지** 정하는 계산.
///
/// ── 왜 계산이 필요한가 ────────────────────────────────────────────────────
/// 그 줄에는 지역 · 대여유형 · 인원 · 보기방식 · 검색 · 정렬이 함께 앉는다.
/// 좁은 폰(320dp)에서는 이것들이 자리를 다 쓰고 지역 버튼에 40px 남짓만
/// 남는데, 예전에는 그 폭에 라벨을 **말줄임**으로 욱여넣어 `지…`가 됐다.
/// 무슨 필터인지 읽을 수 없으면 그 칸은 없는 것과 같다.
///
/// ── 규칙: 글자는 자르지 않는다 ────────────────────────────────────────────
/// 폭이 모자라면 글자를 자르는 대신 **곁가지부터 뗀다** — 핀(📍) → 좌우
/// 여백 → 화살표(▾) 순이고, 그래도 모자라면 이름 자체를 `'지역선택'` →
/// `'지역'`으로 **통째로** 바꾼다. 어떤 단계에서도 `지…`는 나오지 않고,
/// 마지막 단계에서도 `지역` 두 글자는 온전히 남는다.
///
/// 고른 지역명(`강남구` 등)은 이 규칙 밖이다 — 그쪽은 길면 말줄임한다.
/// 필터 **이름**과 필터 **값**은 읽히지 않았을 때 잃는 것이 다르다.
@immutable
class RegionFilterFit {
  const RegionFilterFit(
    this.label, {
    required this.showIcon,
    required this.showChevron,
    required this.hPadding,
  });

  /// 통째로 그릴 글자 — `'지역선택 (2)'` / `'지역 (2)'` / `'지역'`.
  final String label;

  /// 앞의 핀 아이콘. 뜻을 잃지 않는 장식이라 가장 먼저 떨어진다.
  final bool showIcon;

  /// 뒤의 아래 화살표. "눌러서 여는 버튼"이라는 신호라 핀보다 늦게 뗀다.
  final bool showChevron;

  /// 버튼 좌우 안쪽 여백.
  final double hPadding;

  static const String labelFull = '지역선택';
  static const String labelShort = '지역';

  /// 버튼 글자 스타일 — **재는 값과 그리는 값이 같아야** 계산이 뜻을 가진다.
  /// 색은 폭에 영향이 없어 여기 두지 않는다.
  static const TextStyle textStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
  );

  static const double iconWidth = 14;
  static const double iconGap = 4;
  static const double chevronWidth = 16;
  static const double chevronGap = 4;

  /// 글자 폭이 [textWidth]일 때 이 버튼이 실제로 차지하는 폭.
  double widthFor(double textWidth) =>
      hPadding * 2 +
      (showIcon ? iconWidth + iconGap : 0) +
      textWidth +
      (showChevron ? chevronGap + chevronWidth : 0);

  /// 이 조합을 실제로 그렸을 때의 폭.
  double get width => widthFor(measureText(label));

  /// [textStyle]로 그린 [text]의 폭.
  static double measureText(String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  /// [maxWidth]에 들어가는 **가장 넉넉한** 조합.
  ///
  /// 후보를 넓은 것부터 훑어 처음 들어가는 것을 쓴다. 하나도 안 들어가면
  /// 마지막(가장 좁은) 조합을 준다 — `'지역'` 두 글자 + 최소 여백이라
  /// 40px 남짓이고, 실기기 폭에서는 도달하지 않는다.
  static RegionFilterFit resolve({
    required double maxWidth,
    required int count,
  }) {
    for (final c in candidates(count)) {
      if (c.width <= maxWidth) return c;
    }
    return candidates(count).last;
  }

  /// 넓은 것부터 좁은 것 순의 후보 — 떼는 순서가 그대로 드러난다.
  static List<RegionFilterFit> candidates(int count) {
    final full = count > 0 ? '$labelFull ($count)' : labelFull;
    final short = count > 0 ? '$labelShort ($count)' : labelShort;
    return <RegionFilterFit>[
      RegionFilterFit(full, showIcon: true, showChevron: true, hPadding: 14),
      RegionFilterFit(full, showIcon: false, showChevron: true, hPadding: 14),
      RegionFilterFit(short, showIcon: false, showChevron: true, hPadding: 14),
      RegionFilterFit(short, showIcon: false, showChevron: true, hPadding: 8),
      RegionFilterFit(labelShort, showIcon: false, showChevron: true, hPadding: 8),
      RegionFilterFit(labelShort, showIcon: false, showChevron: false, hPadding: 8),
      RegionFilterFit(labelShort, showIcon: false, showChevron: false, hPadding: 4),
    ];
  }
}

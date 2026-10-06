import 'package:flutter/material.dart';

import 'package:party_app/models/place_feature_chips.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 플레이스 카드의 **특징 강조 칩** 한 줄.
//
// ── 왜 따로 만드는가 ─────────────────────────────────────────────────────────
// 특징(🔥 불멍 · 🖥 150인치)은 예전에 주소와 같은 줄에 `' · '`로 이어 붙인
// **평범한 글자**였다. 카드에서 가장 먼저 읽혀야 하는 "왜 가볼 만한가"가
// 정작 가장 눈에 안 띄는 모양을 하고 있었던 셈이다. 카테고리 배지(연한 핑크
// 알약, [cardMiniBadge])와도 구별되지 않아, 업종인지 특징인지 색으로 가릴 수
// 없었다.
//
// 그래서 특징만 **색과 모양이 둘 다 다른** 칩으로 뺀다:
//   · 카테고리 = 연한 핑크 · 알약(radius 20) · 보통 굵기   ← 그대로 둔다
//   · 특징     = 형광 라임 · 둥근 사각(radius 7) · 굵게      ← 여기
// 색만 바꾸면 색약인 사람에게는 같은 것이 되므로 모양도 함께 갈랐다.
//
// ── 한 줄을 넘지 않는다 ──────────────────────────────────────────────────────
// 칩이 여러 줄로 접히면 카드 높이가 문서마다 달라져 2열 그리드에서 좌우 카드의
// 아래끝이 어긋난다(이 카드들의 오래된 규칙이다). 그래서 **한 줄에 들어가는
// 만큼만** 그리고 나머지는 '+N'으로 접는다. 몇 개가 들어가는지는
// [fitFeatureChips]가 정하고, 여기서는 그 계산에 넘길 **실제 폭만** 잰다.
//
// 폭을 잴 때 [MediaQuery.textScalerOf]를 그대로 물려준다 — 시스템 글자 크기를
// 키운 기기에서 계산과 실제 렌더가 어긋나면 그 순간 칩이 줄 밖으로 밀려
// overflow가 난다(정확히 이런 자리에서 나는 사고다).
// ─────────────────────────────────────────────────────────────────────────────

/// 특징 칩의 글자·여백 — 폭 계산과 실제 렌더가 **같은 값**을 봐야 하므로
/// 상수로 둔다(둘이 갈리면 '+N'이 줄 밖으로 나간다).
const double _kFontSize = 10;
const FontWeight _kFontWeight = FontWeight.w800;
const double _kHorizontalPadding = 6;
const double _kVerticalPadding = 2;
const double _kRadius = 7;

/// 칩 사이 간격.
///
/// 여백(6)과 간격(3)이 카테고리 배지(7 / 4)보다 1px씩 좁다 — 일부러다.
/// 360px 기기의 작은 카드는 정보 열이 230px쯤이라 1px이 칩 한 개를 가른다
/// (390px에서 이 1px 덕에 칩이 하나 더 선다). 색이 이미 충분히 도드라지므로
/// 여백으로 존재감을 살 필요가 없다.
const double kPlaceFeatureChipSpacing = 3;

/// 강조 칩 한 줄의 높이.
///
/// 상수인 것이 중요하다 — 기본 카드(2열 그리드)에서 이 줄은 정보 줄 한 칸을
/// **대신 차지**하고, 특징이 없는 카드는 같은 자리에 좌석·공간 요약 글자를
/// 넣는다. 두 경우의 높이가 다르면 좌우 카드의 아래끝이 어긋난다.
const double kPlaceFeatureRowHeight = 18;

/// 형광 라임 — 카드의 어떤 배지와도 겹치지 않는 색이다.
const Color _kChipBackground = Color(0xFFDCFF3F);
const Color _kChipForeground = Color(0xFF1B2A00);

/// '+N'은 같은 라임 계열이지만 한 단계 연하다 — 접혔다는 표시이지 특징 자체가
/// 아니라서, 실제 특징 칩보다 먼저 눈에 들어오면 안 된다.
const Color _kOverflowBackground = Color(0xFFF1FFAE);
const Color _kOverflowForeground = Color(0xFF41560A);

const TextStyle _kChipTextStyle = TextStyle(
  fontSize: _kFontSize,
  fontWeight: _kFontWeight,
  color: _kChipForeground,
  height: 1.1,
);

/// 특징 칩 하나. [overflow]면 '+N' 칩이다.
Widget placeFeatureChip(String label, {bool overflow = false}) => Container(
  padding: const EdgeInsets.symmetric(
    horizontal: _kHorizontalPadding,
    vertical: _kVerticalPadding,
  ),
  decoration: BoxDecoration(
    color: overflow ? _kOverflowBackground : _kChipBackground,
    borderRadius: BorderRadius.circular(_kRadius),
  ),
  child: Text(
    label,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: overflow
        ? _kChipTextStyle.copyWith(color: _kOverflowForeground)
        : _kChipTextStyle,
  ),
);

/// 특징 강조 칩 한 줄 — 들어가는 만큼만 그리고 나머지는 '+N'.
///
/// [labels]가 비어 있으면 아무것도 그리지 않는다([SizedBox.shrink]) — 호출부가
/// 줄 자체를 넣을지 말지 정하게 해서, 빈 줄 때문에 간격이 생기지 않게 한다.
class PlaceFeatureChipRow extends StatelessWidget {
  const PlaceFeatureChipRow({super.key, required this.labels});

  /// 이미 **중요한 순서로** 정렬된 특징 표기들
  /// ([PlaceFeatures.highlightLabelsOf]의 순서 그대로).
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();
    final scaler = MediaQuery.textScalerOf(context);

    double widthOf(String label) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: _kChipTextStyle),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      return painter.width + _kHorizontalPadding * 2;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 폭을 모르는 자리(가로 무한)에서는 자를 수 없다 — 전부 그린다.
        final available = constraints.maxWidth.isFinite
            // 반올림 때문에 마지막 칩이 0.x px 밀려 나가는 것을 막는 여유.
            ? constraints.maxWidth - 0.5
            : double.infinity;
        final fit = fitFeatureChips(
          labels: labels,
          maxWidth: available,
          spacing: kPlaceFeatureChipSpacing,
          widthOf: widthOf,
          overflowWidthOf: (hidden) => widthOf(featureOverflowLabel(hidden)),
        );

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < fit.visible.length; i++) ...[
              if (i > 0) const SizedBox(width: kPlaceFeatureChipSpacing),
              placeFeatureChip(fit.visible[i]),
            ],
            if (fit.hidden > 0) ...[
              const SizedBox(width: kPlaceFeatureChipSpacing),
              placeFeatureChip(
                featureOverflowLabel(fit.hidden),
                overflow: true,
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 기본·큰 카드의 정보 줄 **한 칸**에 들어가는 특징 줄.
///
/// 높이를 [kPlaceFeatureRowHeight]로 고정한다 — 같은 자리에 글자 한 줄이 올
/// 수도 있어서(특징이 없는 플레이스) 두 경우의 높이가 같아야 한다.
class PlaceFeatureSlot extends StatelessWidget {
  const PlaceFeatureSlot({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: kPlaceFeatureRowHeight,
    child: Align(alignment: Alignment.centerLeft, child: child),
  );
}

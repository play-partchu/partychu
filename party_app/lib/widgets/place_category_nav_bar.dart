import 'package:flutter/material.dart';

/// 플레이스 탭 카테고리 하나(예: 🔥 핫플, 🛍️ 파티샵)를 나타내는 값 객체.
/// [value]가 null이면 "전체" 항목을 뜻한다.
class PlaceCategoryNavItem {
  const PlaceCategoryNavItem({this.value, this.emoji, required this.label});

  final String? value;
  final String? emoji;
  final String label;
}

// 밤 모드(다크 글래스) 팔레트.
const Color _kNeonPink = Color(0xFFFF6FA0);
const Color _kNeonPurple = Color(0xFFB14EFF);

// 낮 모드(화이트 글래스) 팔레트 — 형태는 밤 모드와 완전히 같고 재질/색만
// 바뀐다. 비선택 타일은 반투명 흰색이라 뒤 배경이 살짝 비친다.
const Color _kGlassBorder = Color(0xFFFFD9E8);
const Color _kGlassPinkFrom = Color(0xFFFF72AE);
const Color _kGlassPinkTo = Color(0xFFFF9FD0);
const Color _kGlassLabel = Color(0xFF4A4A55);
// 평균이 사양(0.75)이 되도록 위/아래로 벌린 값 — 이 미세한 명암 차가 있어야
// 반투명 타일끼리 맞닿는 사선 경계가 눈에 보인다(밤 모드의 다크 그라데이션과
// 같은 역할).
const Color _kGlassFillFrom = Color(0xD9FFFFFF); // white 85%
const Color _kGlassFillTo = Color(0xA6FFFFFF); // white 65%

/// 게임 UI/네온 스타일의 커스텀 카테고리 탭바.
///
/// ChoiceChip/FilterChip 같은 알약(pill) 모양 대신, 좌우가 사선으로 이어지는
/// 패널(육각형 느낌) 세그먼트들이 서로 맞물려 하나의 바처럼 보이도록
/// [ClipPath] + 커스텀 [CustomClipper]로 각 세그먼트를 그린다. 선택 여부에
/// 따른 그라데이션/글로우/살짝 떠 보이는 효과는 모두 암시적 애니메이션
/// (AnimatedContainer 등)으로 200~250ms에 걸쳐 부드럽게 전환된다.
///
/// 뒤에 별도의 사각형 카드 배경은 없다 — 세그먼트 자체의 그라데이션
/// 채움만으로 바 모양이 드러난다.
///
/// 항목이 한 줄에 다 안 들어가면 두 줄로 나누는데, 위/아래 줄이 각자 따로
/// 떠 보이지 않도록:
///  - 두 줄 사이에는 간격을 아예 두지 않는다(줄 사이 SizedBox 없음).
///  - 세그먼트의 테두리는 "바깥쪽으로 향한 가장자리"에만 그린다(첫 줄은
///    위쪽만, 둘째 줄은 아래쪽만). 두 줄이 맞닿는 안쪽 경계에는 테두리를
///    그리지 않으므로, 거기서 두 줄의 그라데이션 채움이 곧바로 맞닿아
///    이어져 보인다 — 테두리 두 줄이 겹쳐 "이중선(=틈처럼 보임)"이
///    생기던 문제를 근본적으로 없앤다.
///  - 두 줄 모두 부모가 준 가로폭을 그대로 꽉 채운다 — 각 세그먼트 폭은
///    라벨 길이에 비례해 나눠 갖되(가중치 배분), 겹침(_skew)을 더한 뒤의
///    최종 오른쪽 끝이 정확히 부모 폭에 닿도록 계산하므로 줄마다 항목
///    개수가 달라도 두 줄의 좌우 시작/끝 위치가 항상 일치한다.
///  - 줄의 맨 왼쪽/맨 오른쪽 바깥 변만 수직으로 자른다. 바깥까지 사선이면
///    윗줄 아래꼭짓점과 아랫줄 위꼭짓점이 skew만큼 어긋나 계단처럼 보이기
///    때문이다. 버튼과 버튼 사이의 사선 맞물림은 전부 그대로 유지된다.
///
/// 선택 상태 판정과 탭 처리(다중 선택, 배타 선택 등)는 전부 호출부가
/// [isSelected]/[onSelect]로 넘겨주므로, 이 위젯은 순수하게 "보여주는 것"만
/// 담당하고 기존 필터링 로직에는 관여하지 않는다.
class PlaceCategoryNavBar extends StatelessWidget {
  const PlaceCategoryNavBar({
    super.key,
    required this.items,
    required this.isSelected,
    required this.onSelect,
    this.height = 42,
    this.night = true,
  });

  final List<PlaceCategoryNavItem> items;
  final bool Function(PlaceCategoryNavItem item) isSelected;
  final ValueChanged<PlaceCategoryNavItem> onSelect;
  final double height;

  /// true면 다크 글래스(밤), false면 화이트 글래스(낮). 사선 형태·2줄
  /// 레이아웃·폭 배분은 두 모드가 완전히 동일하고 재질과 색만 달라진다.
  final bool night;

  static const double _skew = 10;

  /// 인접 세그먼트를 사선 폭(_skew)보다 아주 살짝 더 겹쳐, 두 사선이 정확히
  /// 겹칠 때 생기는 안티에일리어싱 이음새(머리카락 같은 세로줄)를 없앤다.
  /// 뒤에 그려지는 세그먼트가 이 만큼을 덮어쓴다.
  static const double _bleed = 0.6;

  /// 세그먼트 안쪽 좌우 여백(사선 몫 _skew는 여기에 따로 더해진다).
  static const double _labelPadding = 13;

  @override
  Widget build(BuildContext context) {
    // 한 줄에 다 못 넣고 두 줄로 나눠 보여준다 — 앞쪽 절반(홀수면 한 개 더)을
    // 첫 줄에, 나머지를 둘째 줄에 배치한다.
    final splitAt = (items.length / 2).ceil();
    final firstRow = items.sublist(0, splitAt);
    final secondRow = items.sublist(splitAt);

    // 좌우로는 여백을 두지 않는다 — 부모가 준 폭(호출부의 화면 좌우 여백)에
    // 두 줄이 그대로 꽉 차야 시작/끝이 화면 기준으로 정확히 맞는다. 선택 시
    // 살짝 떠 보이는 lift(-3)와 글로우는 Clip.none이라 잘리지 않는다.
    final rows = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildRow(firstRow, isFirstRow: true),
        if (secondRow.isNotEmpty) _buildRow(secondRow, isFirstRow: false),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      // 낮 모드의 은은한 핑크 그림자는 타일마다가 아니라 바 전체에 한 번만
      // 준다 — 타일이 빈틈없이 맞물려 있어서 개별 그림자는 서로의 반투명
      // 면에 비쳐 탁해 보이기만 하고, 실제로 보이는 건 바 바깥 테두리뿐이다.
      // 두 줄의 합집합이 정확히 직사각형이라 이 그림자 하나로 딱 맞는다.
      child: night
          ? rows
          : DecoratedBox(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: _kGlassPinkFrom.withValues(alpha: 0.09),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: rows,
            ),
    );
  }

  /// 한 줄을 부모 폭에 정확히 맞춰 채운다.
  ///
  /// 각 세그먼트는 사선 때문에 옆 세그먼트와 [_skew]+[_bleed] 만큼 겹치므로,
  /// 겹치는 양을 미리 더한 값(totalBoxWidth)을 라벨 길이 비례로 나눈 뒤 그
  /// 만큼씩 왼쪽으로 당겨 배치한다. 그러면 마지막 세그먼트의 오른쪽 끝이
  /// 정확히 부모 폭에 떨어져, 항목 개수가 다른 두 줄의 좌우 끝이 일치한다.
  Widget _buildRow(
    List<PlaceCategoryNavItem> rowItems, {
    required bool isFirstRow,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final n = rowItems.length;
        final overlap = _skew + _bleed;
        final natural = [
          for (int i = 0; i < n; i++)
            _naturalWidth(
              context,
              rowItems[i],
              slantLeft: i > 0,
              slantRight: i < n - 1,
            ),
        ];
        final naturalSum = natural.reduce((a, b) => a + b);
        // 폭이 무한(가로 스크롤뷰 등)일 땐 비율 배분이 불가능하니 내용
        // 폭 그대로 쓴다.
        final rowWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : naturalSum - overlap * (n - 1);
        final totalBoxWidth = rowWidth + overlap * (n - 1);
        // 화면이 좁아 내용보다 작게 눌릴 땐 라벨 여백도 같은 비율로 줄여
        // 글자가 과하게 축소되는 걸 막는다(사선 몫 _skew는 그대로 유지).
        final squeeze = (totalBoxWidth / naturalSum).clamp(0.45, 1.0);

        final unselected = <Widget>[];
        final selectedTiles = <Widget>[];
        double x = 0;
        for (int i = 0; i < n; i++) {
          final w = totalBoxWidth * natural[i] / naturalSum;
          final selected = isSelected(rowItems[i]);
          final tile = Positioned(
            left: x - overlap * i,
            top: 0,
            bottom: 0,
            width: w,
            child: _PlaceCategorySegment(
              item: rowItems[i],
              selected: selected,
              onTap: () => onSelect(rowItems[i]),
              skew: _skew,
              labelPadding: _labelPadding * squeeze,
              // 줄의 맨 왼쪽/맨 오른쪽 바깥 변만 수직으로 잘라, 두 줄의
              // 좌우 끝이 y좌표와 무관하게 정확히 같은 x에 떨어진다.
              // 버튼 사이의 사선 맞물림은 전부 그대로다.
              slantLeft: i > 0,
              slantRight: i < n - 1,
              isFirstRow: isFirstRow,
              night: night,
            ),
          );
          // 낮 모드는 선택 타일이 살짝 커지며 떠오르므로, 뒤에 그려야 옆
          // 타일에 잘리지 않는다(Stack은 나중 자식이 위에 그려진다).
          // 위치는 Positioned가 잡으므로 순서를 바꿔도 레이아웃은 그대로다.
          (!night && selected ? selectedTiles : unselected).add(tile);
          x += w;
        }

        return SizedBox(
          height: height,
          // 선택된 세그먼트의 lift/글로우가 바깥으로 번져야 하므로 클립 없음.
          child: Stack(
            clipBehavior: Clip.none,
            children: [...unselected, ...selectedTiles],
          ),
        );
      },
    );
  }

  /// 라벨(+이모지)과 여백을 더한 세그먼트의 "자연스러운" 폭 — 이 값의 비율로
  /// 줄 전체 폭을 나눠 가지므로, 긴 라벨일수록 자동으로 더 넓어진다.
  /// 사선이 없는 바깥쪽 변에는 사선 몫(_skew)을 더하지 않는다.
  double _naturalWidth(
    BuildContext context,
    PlaceCategoryNavItem item, {
    required bool slantLeft,
    required bool slantRight,
  }) {
    final scaler = MediaQuery.textScalerOf(context);
    var w =
        _labelPadding * 2 + (slantLeft ? _skew : 0) + (slantRight ? _skew : 0);
    if (item.emoji != null) {
      w +=
          _measureText(item.emoji!, _PlaceCategorySegment.emojiStyle, scaler) +
          5;
    }
    // 선택 시 글자가 굵어져도 배분이 흔들리지 않도록 항상 굵은 쪽으로 잰다.
    w += _measureText(
      item.label,
      _PlaceCategorySegment.selectedLabelStyle,
      scaler,
    );
    return w;
  }

  static double _measureText(String text, TextStyle style, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    return painter.width;
  }
}

class _PlaceCategorySegment extends StatelessWidget {
  const _PlaceCategorySegment({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.skew,
    required this.labelPadding,
    required this.slantLeft,
    required this.slantRight,
    required this.isFirstRow,
    required this.night,
  });

  final PlaceCategoryNavItem item;
  final bool selected;
  final VoidCallback onTap;
  final double skew;
  final double labelPadding;
  final bool slantLeft;
  final bool slantRight;
  final bool isFirstRow;
  final bool night;

  static const Duration _dur = Duration(milliseconds: 220);
  static const Curve _curve = Curves.easeOutCubic;

  /// 낮 모드에서 선택 타일이 살짝 떠오르는 모션 — iOS처럼 튕김 없이
  /// 부드럽게, 0.15초.
  static const Duration _liftDur = Duration(milliseconds: 150);
  // 1.03 — 더 키우면 줄 맨 끝 타일이 선택됐을 때 바 바깥으로 눈에 띄게
  // 삐져나와, 두 줄의 좌우 끝이 맞아 보이지 않는다.
  static const double _liftScale = 1.03;

  // 폭 배분 계산(_naturalWidth)과 실제 렌더링이 같은 값을 쓰도록 공유한다.
  static const TextStyle emojiStyle = TextStyle(fontSize: 13.5);
  static const TextStyle selectedLabelStyle = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.1,
  );

  @override
  Widget build(BuildContext context) {
    final borderSide = night
        ? BorderSide(
            color: selected
                ? Colors.white.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.10),
            width: selected ? 1.2 : 1,
          )
        : BorderSide(
            // 낮은 유리 가장자리처럼 연핑크 실선 — 선택 시엔 하이라이트로.
            color: selected
                ? Colors.white.withValues(alpha: 0.7)
                : _kGlassBorder,
            width: selected ? 1.2 : 1,
          );

    // 폭과 위치(사선 겹침 포함)는 부모(PlaceCategoryNavBar)가 Positioned로
    // 정해주므로, 여기서는 세로 lift(선택 시 살짝 떠 보이는 효과)와
    // 글로우만 신경 쓴다.
    final tile = AnimatedContainer(
      duration: _dur,
      curve: _curve,
      transform: Matrix4.translationValues(0, selected ? -3 : 0, 0),
      transformAlignment: Alignment.center,
      decoration: BoxDecoration(
        // 선택된 세그먼트만 바깥으로 은은하게 번진다 — 밤은 네온 글로우,
        // 낮은 같은 자리에 조금 더 진한 핑크 그림자.
        boxShadow: !selected
            ? const []
            : night
            ? [
                BoxShadow(
                  color: _kNeonPink.withValues(alpha: 0.55),
                  blurRadius: 16,
                  spreadRadius: 0.5,
                ),
                BoxShadow(
                  color: _kNeonPurple.withValues(alpha: 0.35),
                  blurRadius: 24,
                  spreadRadius: 1,
                ),
              ]
            : [
                BoxShadow(
                  color: _kGlassPinkFrom.withValues(alpha: 0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: ClipPath(
        clipper: _ParallelogramClipper(
          skew: skew,
          slantLeft: slantLeft,
          slantRight: slantRight,
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: _dur,
            curve: _curve,
            // 사선이 있는 쪽에만 사선 몫(skew)을 더한다 — 수직으로 자른
            // 바깥 변은 여백을 더 줄 필요가 없어서 글자가 가운데로 치우쳐
            // 보이지 않는다.
            padding: EdgeInsets.only(
              left: labelPadding + (slantLeft ? skew : 0),
              right: labelPadding + (slantRight ? skew : 0),
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // 형태는 그대로 두고 재질만 바꾼다 — 밤은 다크 글래스,
              // 낮은 화이트 글래스(반투명이라 뒤 배경이 살짝 비친다).
              gradient: night
                  ? (selected
                        ? const LinearGradient(
                            colors: [_kNeonPink, _kNeonPurple],
                          )
                        : const LinearGradient(
                            colors: [Color(0xFF262A3D), Color(0xFF161724)],
                          ))
                  : (selected
                        ? const LinearGradient(
                            colors: [_kGlassPinkFrom, _kGlassPinkTo],
                          )
                        : const LinearGradient(
                            colors: [_kGlassFillFrom, _kGlassFillTo],
                          )),
              // 클리핑 후에는 사각형의 위/아래 변만 사선 모서리를 따라
              // 그대로 보이고, 좌/우 변은 대각선에 가려 거의 보이지
              // 않는다(테두리는 직선 4변에만 그려지고 대각선 자체에는
              // 그려지지 않기 때문). 그래서 "바깥으로 향한 가장자리"만
              // 골라 그리면 두 줄이 맞닿는 안쪽 경계에는 선이 전혀 남지
              // 않아 완전히 이어져 보인다 — 첫 줄은 위쪽만, 둘째 줄은
              // 아래쪽만. 수직으로 자른 바깥 변(줄의 양 끝)에도 같은 규칙을
              // 적용해, 두 줄의 좌·우 테두리가 하나의 직선으로 이어진다.
              border: Border(
                top: isFirstRow ? borderSide : BorderSide.none,
                bottom: isFirstRow ? BorderSide.none : borderSide,
                left: slantLeft ? BorderSide.none : borderSide,
                right: slantRight ? BorderSide.none : borderSide,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.emoji != null) ...[
                  AnimatedOpacity(
                    duration: _dur,
                    opacity: selected ? 1 : 0.6,
                    child: Text(item.emoji!, style: emojiStyle),
                  ),
                  const SizedBox(width: 5),
                ],
                // 아주 좁은 기기에서 배분된 폭이 라벨보다 작아져도 잘리거나
                // 넘치지 않도록 마지막 방어선으로 살짝 축소만 한다.
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      item.label,
                      maxLines: 1,
                      softWrap: false,
                      style: selectedLabelStyle.copyWith(
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: selected
                            ? Colors.white
                            : (night
                                  ? Colors.white.withValues(alpha: 0.75)
                                  : _kGlassLabel),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (night) return tile;
    // 낮 모드에서만: 선택 타일이 살짝 커지며 떠오른다(0.15초, 튕김 없이).
    // 밤 모드는 기존 lift(-3)만 그대로 유지한다.
    return AnimatedScale(
      duration: _liftDur,
      curve: _curve,
      scale: selected ? _liftScale : 1,
      child: tile,
    );
  }
}

/// 좌우가 사선으로 이어지는 육각형(패널) 느낌의 세그먼트 모양.
/// 인접한 세그먼트를 [skew]만큼 겹쳐 배치하면 사선 모서리가 서로 맞물려
/// 하나로 연결된 바처럼 보인다.
///
/// [slantLeft]/[slantRight]가 false면 그쪽 변만 수직으로 자른다 — 줄의 맨
/// 왼쪽/맨 오른쪽 끝에만 쓰여서, 항목 수가 다른 두 줄이 정확히 같은 x에서
/// 시작하고 끝나게 한다. 버튼과 버튼 사이(안쪽)의 사선은 전부 그대로다.
class _ParallelogramClipper extends CustomClipper<Path> {
  const _ParallelogramClipper({
    required this.skew,
    required this.slantLeft,
    required this.slantRight,
  });

  final double skew;
  final bool slantLeft;
  final bool slantRight;

  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(slantLeft ? skew : 0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(slantRight ? size.width - skew : size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant _ParallelogramClipper oldClipper) =>
      oldClipper.skew != skew ||
      oldClipper.slantLeft != slantLeft ||
      oldClipper.slantRight != slantRight;
}

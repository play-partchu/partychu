import 'package:flutter/material.dart';

/// 플레이스 탭 카테고리 하나(예: 🔥 핫플, 🛍️ 파티샵)를 나타내는 값 객체.
/// [value]가 null이면 "전체" 항목을 뜻한다.
class PlaceCategoryNavItem {
  const PlaceCategoryNavItem({this.value, this.emoji, required this.label});

  final String? value;
  final String? emoji;
  final String label;
}

const Color _kNeonPink = Color(0xFFFF6FA0);
const Color _kNeonPurple = Color(0xFFB14EFF);

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
///  - 두 줄 모두 [IntrinsicWidth] + [CrossAxisAlignment.stretch]로 정확히
///    같은 폭에 맞춰서 좌우 시작/끝 위치가 항상 일치한다.
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
  });

  final List<PlaceCategoryNavItem> items;
  final bool Function(PlaceCategoryNavItem item) isSelected;
  final ValueChanged<PlaceCategoryNavItem> onSelect;
  final double height;

  static const double _skew = 10;

  @override
  Widget build(BuildContext context) {
    // 한 줄에 다 못 넣고 두 줄로 나눠 보여준다 — 앞쪽 절반(홀수면 한 개 더)을
    // 첫 줄에, 나머지를 둘째 줄에 배치한다.
    final splitAt = (items.length / 2).ceil();
    final firstRow = items.sublist(0, splitAt);
    final secondRow = items.sublist(splitAt);

    // 선택 시 살짝 떠 보이는 lift(-3)와 글로우가 잘리지 않도록 최소한의
    // 여백만 둔다 — 배경/테두리/그림자가 있는 별도 카드가 아니다.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: IntrinsicWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildRow(firstRow, isFirstRow: true),
            if (secondRow.isNotEmpty) _buildRow(secondRow, isFirstRow: false),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(List<PlaceCategoryNavItem> rowItems, {required bool isFirstRow}) {
    // 두 줄 다 스크롤 없는 일반 Row다 — 애초에 한 줄에 다 못 담을
    // 항목을 두 줄로 쪼갠 것이라 줄당 개수가 이미 적어 가로 스크롤이
    // 필요 없고, 스크롤뷰를 빼야 IntrinsicWidth가 두 줄의 실제 내용
    // 폭을 정확히 비교해 더 넓은 쪽에 맞출 수 있다.
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (int i = 0; i < rowItems.length; i++)
          // Container/AnimatedContainer의 margin은 음수를 허용하지
          // 않는다(assert(margin.isNonNegative)) — 그래서 레이아웃이
          // 아니라 페인트 시점에만 위치를 옮기는 Transform.translate로
          // 겹쳐서, 사선 모서리가 서로 맞물리게 한다. Transform은
          // 히트테스트도 함께 이동시키므로 탭 판정은 그대로 정확하다.
          Transform.translate(
            offset: Offset(-_skew * i, 0),
            child: _PlaceCategorySegment(
              item: rowItems[i],
              selected: isSelected(rowItems[i]),
              onTap: () => onSelect(rowItems[i]),
              height: height,
              skew: _skew,
              isFirstRow: isFirstRow,
            ),
          ),
      ],
    );
  }
}

class _PlaceCategorySegment extends StatelessWidget {
  const _PlaceCategorySegment({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.height,
    required this.skew,
    required this.isFirstRow,
  });

  final PlaceCategoryNavItem item;
  final bool selected;
  final VoidCallback onTap;
  final double height;
  final double skew;
  final bool isFirstRow;

  static const Duration _dur = Duration(milliseconds: 220);
  static const Curve _curve = Curves.easeOutCubic;

  @override
  Widget build(BuildContext context) {
    final borderSide = BorderSide(
      color: selected
          ? Colors.white.withValues(alpha: 0.55)
          : Colors.white.withValues(alpha: 0.10),
      width: selected ? 1.2 : 1,
    );

    // 인접 세그먼트와의 사선 겹침은 부모(PlaceCategoryNavBar)의
    // Transform.translate가 처리하므로, 여기서는 세로 lift(선택 시 살짝
    // 떠 보이는 효과)와 글로우만 신경 쓴다.
    return AnimatedContainer(
      duration: _dur,
      curve: _curve,
      transform: Matrix4.translationValues(0, selected ? -3 : 0, 0),
      transformAlignment: Alignment.center,
      decoration: BoxDecoration(
        // 선택된 세그먼트만 바깥으로 은은하게 번지는 네온 글로우.
        boxShadow: selected
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
            : const [],
      ),
      child: ClipPath(
        clipper: _ParallelogramClipper(skew),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: _dur,
            curve: _curve,
            height: height,
            padding: EdgeInsets.symmetric(horizontal: 13 + skew),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: selected
                  ? const LinearGradient(
                      colors: [_kNeonPink, _kNeonPurple],
                    )
                  : const LinearGradient(
                      colors: [Color(0xFF262A3D), Color(0xFF161724)],
                    ),
              // 클리핑 후에는 사각형의 위/아래 변만 사선 모서리를 따라
              // 그대로 보이고, 좌/우 변은 대각선에 가려 거의 보이지
              // 않는다(테두리는 직선 4변에만 그려지고 대각선 자체에는
              // 그려지지 않기 때문). 그래서 "바깥으로 향한 가장자리"만
              // 골라 그리면 두 줄이 맞닿는 안쪽 경계에는 선이 전혀 남지
              // 않아 완전히 이어져 보인다 — 첫 줄은 위쪽만, 둘째 줄은
              // 아래쪽만.
              border: Border(
                top: isFirstRow ? borderSide : BorderSide.none,
                bottom: isFirstRow ? BorderSide.none : borderSide,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.emoji != null) ...[
                  AnimatedOpacity(
                    duration: _dur,
                    opacity: selected ? 1 : 0.6,
                    child: Text(
                      item.emoji!,
                      style: const TextStyle(fontSize: 13.5),
                    ),
                  ),
                  const SizedBox(width: 5),
                ],
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.75),
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 좌우가 사선으로 이어지는 육각형(패널) 느낌의 세그먼트 모양.
/// 인접한 세그먼트를 [skew]만큼 겹쳐 배치하면 사선 모서리가 서로 맞물려
/// 하나로 연결된 바처럼 보인다.
class _ParallelogramClipper extends CustomClipper<Path> {
  const _ParallelogramClipper(this.skew);

  final double skew;

  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(skew, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width - skew, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant _ParallelogramClipper oldClipper) =>
      oldClipper.skew != skew;
}

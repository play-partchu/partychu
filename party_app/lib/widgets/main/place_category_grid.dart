import 'package:flutter/material.dart';

/// 대분류 칸 하나. [value]가 null이면 '전체'.
class PlaceCategoryTile {
  const PlaceCategoryTile({
    required this.emoji,
    required this.label,
    this.value,
  });

  /// 저장값(또는 파티샵·이벤트 같은 전용 식별자). null이면 '전체'.
  final String? value;
  final String emoji;
  final String label;
}

/// 플레이스 홈의 **대분류 칸 격자**.
///
/// ── 왜 사선 바를 걷어냈나 ─────────────────────────────────────────────────
/// 예전 카테고리 바는 사선으로 맞물린 세그먼트 안에 13.5px 이모지와 12.5px
/// 글씨를 나란히 눕혀 놨다. 열두 칸이 360px를 나눠 가지니 칸당 30px 남짓이라
/// 이모지도 이름도 훑어서 읽히지 않았다 — "뭐 할까"를 고르는 첫 화면인데
/// 무엇을 고르는 자리인지가 안 보인다.
///
/// 그래서 **이모지를 위, 이름을 아래**로 세운다. 같은 칸 너비에서 이모지를
/// 두 배 가까이 키울 수 있고(13.5 → 24), 이름도 줄바꿈 없이 들어간다.
///
///        ┌──────┬──────┬──────┬──────┬──────┬──────┐
///        │  🧭  │  🎪  │  🍽  │  ☕  │  🍻  │  🍷  │
///        │ 전체 │이벤트│ 푸드 │ 카페 │ 술집 │혼술바│
///        ├──────┼──────┼──────┼──────┼──────┼──────┤
///        │  🍸  │  🔥  │  🎤  │  🎮  │  🎨  │  🛍️  │
///        │ BAR │ 클럽 │라이브│놀거리│ 체험 │파티샵│
///        └──────┴──────┴──────┴──────┴──────┴──────┘
///
/// ── 목록을 밀어내지 않는다 ───────────────────────────────────────────────
/// 칸이 커지면 플레이스 카드가 아래로 밀린다. 그래서 두 줄로 **딱 잘라** 두고
/// ([_rowHeight] × 2), 칸 높이는 터치 영역 기준(48px)을 넘기되 그 이상 키우지
/// 않는다. 대분류를 하나 고르면 이 격자는 통째로 사라지고 한 줄짜리 소분류
/// 줄이 그 자리를 쓰므로([PlaceCategoryExplorer]), 고를수록 목록은 오히려
/// 위로 올라온다.
///
/// 선택 판정과 탭 처리는 전부 호출부가 [isSelected]/[onSelect]로 넘겨준다 —
/// 이 위젯은 그리기만 하고 필터 로직에는 관여하지 않는다.
class PlaceCategoryGrid extends StatelessWidget {
  const PlaceCategoryGrid({
    super.key,
    required this.items,
    required this.isSelected,
    required this.onSelect,
    this.night = true,
  });

  final List<PlaceCategoryTile> items;
  final bool Function(PlaceCategoryTile item) isSelected;
  final ValueChanged<PlaceCategoryTile> onSelect;

  /// true면 다크 글래스(밤), false면 화이트 글래스(낮).
  final bool night;

  /// 한 줄에 몇 칸 — 360px에서 칸당 약 57px(이모지 24 + 이름 11.5가 들어간다).
  static const int _columns = 6;

  /// 칸 하나의 높이. 이모지(24) + 간격(3) + 이름(15) + 위아래 여백 = 56.
  /// 손가락 터치 기준(48)을 넘기면서 두 줄이 112px에 들어오는 값이다.
  static const double _rowHeight = 56;

  static const double _gap = 5;

  static const Color _pink = Color(0xFFFF6FA0);
  static const Color _purple = Color(0xFFB14EFF);

  @override
  Widget build(BuildContext context) {
    final rows = <List<PlaceCategoryTile>>[];
    for (var i = 0; i < items.length; i += _columns) {
      rows.add(items.sublist(i, (i + _columns).clamp(0, items.length)));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) const SizedBox(height: _gap),
          SizedBox(height: _rowHeight, child: _row(rows[r])),
        ],
      ],
    );
  }

  /// 마지막 줄이 덜 찼어도 **칸 너비는 위 줄과 같아야** 한다 — 남는 칸은 빈
  /// 자리로 두고, 폭을 늘려 채우지 않는다(줄마다 칸 크기가 달라 보이면 격자로
  /// 읽히지 않는다).
  Widget _row(List<PlaceCategoryTile> rowItems) {
    return Row(
      children: [
        for (var i = 0; i < _columns; i++) ...[
          if (i > 0) const SizedBox(width: _gap),
          Expanded(
            child: i < rowItems.length
                ? _tile(rowItems[i])
                : const SizedBox.shrink(),
          ),
        ],
      ],
    );
  }

  Widget _tile(PlaceCategoryTile item) {
    final selected = isSelected(item);

    final gradient = selected
        ? LinearGradient(
            colors: night
                ? const [_pink, _purple]
                : const [Color(0xFFFF72AE), Color(0xFFFF9FD0)],
          )
        : LinearGradient(
            colors: night
                ? const [Color(0xFF262A3D), Color(0xFF161724)]
                : const [Color(0xD9FFFFFF), Color(0xA6FFFFFF)],
          );

    final borderColor = selected
        ? Colors.white.withValues(alpha: 0.6)
        : night
        ? Colors.white.withValues(alpha: 0.10)
        : const Color(0xFFFFD9E8);

    final labelColor = selected
        ? Colors.white
        : night
        ? Colors.white.withValues(alpha: 0.78)
        : const Color(0xFF4A4A55);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onSelect(item),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: selected ? 1.4 : 1),
          // 고른 칸만 바깥으로 번진다 — 두 줄 열두 칸에서 "지금 어디를 보고
          // 있는지"가 색만으로는 잘 안 읽힌다.
          boxShadow: !selected
              ? const []
              : night
              ? [
                  BoxShadow(
                    color: _pink.withValues(alpha: 0.5),
                    blurRadius: 14,
                    spreadRadius: 0.5,
                  ),
                ]
              : [
                  BoxShadow(
                    color: _pink.withValues(alpha: 0.3),
                    blurRadius: 14,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(item.emoji, style: const TextStyle(fontSize: 22, height: 1.1)),
            const SizedBox(height: 2),
            // 아주 좁은 기기(320px)에서 이름이 칸보다 커져도 잘리지 않도록
            // 마지막 방어선으로 살짝 축소만 한다.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  item.label,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.1,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: labelColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

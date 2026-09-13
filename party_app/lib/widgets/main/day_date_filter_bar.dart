import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:party_app/widgets/main/sort_entry_button.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 낮 모드 전용 날짜 필터 바 — 밤 모드의 검정 네온 바(_buildNeonCategorySection)
// 와 분위기를 가르는 미니멀 + 귀여운 iOS 감성의 파스텔 알약(Pill) UI.
//
// 버튼 뒤에는 어떤 장식(구름/판/바 배경)도 두지 않는다. 대신 알약 하나하나에
// 광택(윗면 하이라이트)·바닥 톤·그림자를 넣어 입체감만으로 심심하지 않게 만든다.
// 선택/비선택은 형태를 바꾸지 않고 색(흰색 ↔ 핑크 그라데이션)과 그림자 세기만
// 바뀐다.
//
// 필터 로직은 전부 호출부(main_screen)에 그대로 있고, 이 위젯은 라벨/선택
// 여부/탭 콜백만 받아 그리기만 한다.
// ─────────────────────────────────────────────────────────────────────────────

/// 낮 모드 알약 버튼 팔레트 — 파스텔 톤.
class DayFilterPalette {
  const DayFilterPalette._();

  /// 비선택 버튼 윗면(순백).
  static const Color pillTop = Color(0xFFFFFFFF);

  /// 비선택 버튼 아랫면 — 아주 옅은 핑크. 위아래 차이로 볼륨감을 만든다.
  static const Color pillBottom = Color(0xFFFFF6FA);

  /// 버튼 외곽선(연핑크).
  static const Color outline = Color(0xFFFFD6E8);

  /// 선택 시 그라데이션 (진한 핑크 → 연한 핑크).
  static const Color selectedFrom = Color(0xFFFF73AF);
  static const Color selectedTo = Color(0xFFFF9CC8);

  /// 핑크톤 그림자.
  static const Color shadow = Color(0xFFFF73AF);

  /// 비선택 글자 — 진회색.
  static const Color label = Color(0xFF4A4A4A);
}

/// 날짜 퀵필터(전체/오늘/내일/이번 주/이번 주말) + 정렬 버튼 한 줄.
class DayDateFilterBar extends StatelessWidget {
  /// 표시 순서 그대로의 탭 라벨.
  final List<String> tabs;

  /// 라벨 → 선택 여부.
  final bool Function(String tab) isSelected;

  /// 라벨 탭 콜백.
  final ValueChanged<String> onTapTab;

  /// 오른쪽 끝의 정렬 버튼 — null이면 버튼 자체를 두지 않는다
  /// (정렬이 없는 탭에서 자리만 차지하지 않도록).
  ///
  /// 상세검색(튠) 버튼은 더 이상 이 바에 없다 — 목록 헤더의 돋보기로 열리는
  /// 검색 시트(SearchEntrySheet) 안으로 옮겨져 세 탭이 같은 입구를 쓴다.
  final VoidCallback? onOpenSort;

  /// 기본순이 아닌 정렬이 걸려 있는지 — 버튼에 분홍 점이 찍힌다.
  final bool sortActive;

  /// 정렬 버튼 툴팁('정렬 · 거리순'). 장소대여 쪽과 같은 규칙이다.
  final String sortTooltip;

  const DayDateFilterBar({
    super.key,
    required this.tabs,
    required this.isSelected,
    required this.onTapTab,
    this.onOpenSort,
    this.sortActive = false,
    this.sortTooltip = '정렬',
  });

  /// 검정 네온 바(42)와 같은 높이 — 두 모드에서 상단 레이아웃이 흔들리지 않는다.
  static const double barHeight = 42.0;

  /// 그림자가 잘리지 않도록 알약 위아래로 남겨두는 여백.
  static const double _pillInsetV = 3.0;

  @override
  Widget build(BuildContext context) {
    // 바 자체에는 배경이 없다 — 알약만 떠 있는 상태가 이 UI의 핵심.
    return SizedBox(
      height: barHeight,
      child: Row(
        children: [
          for (final tab in tabs)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 2.5,
                  vertical: _pillInsetV,
                ),
                child: DayFilterChip(
                  label: tab,
                  selected: isSelected(tab),
                  onTap: () => onTapTab(tab),
                ),
              ),
            ),
          if (onOpenSort != null) ...[
            const SizedBox(width: 3),
            // 정렬 버튼은 이 바가 직접 그리지 않는다 — 장소대여 목록과
            // **같은 위젯**([SortEntryIconButton])을 쓴다. 예전에는 여기만
            // 알약(DayFilterChip)이라 같은 버튼이 탭마다 달라 보였다.
            //
            // 알약 여백(_pillInsetV)을 주지 않는 이유: 버튼이 40×40 터치
            // 영역을 그대로 확보해야 장소대여 쪽과 같은 크기가 된다
            // (바 높이가 42라 그대로 들어간다).
            SortEntryIconButton(
              onTap: onOpenSort!,
              active: sortActive,
              tooltip: sortTooltip,
            ),
          ],
        ],
      ),
    );
  }
}

/// 알약 버튼 하나 — 라벨 또는 아이콘 하나를 담는다.
///
/// 탭하면 0.18초 동안 1.0 → 1.05 → 1.0으로 살짝 부풀었다 돌아오고, 선택
/// 색상은 같은 길이로 부드럽게 전환된다(형태는 그대로).
class DayFilterChip extends StatefulWidget {
  final String? label;
  final IconData? icon;

  /// 아이콘 지름. 글리프가 상자를 채우는 정도는 아이콘마다 달라서, 같은 값을
  /// 줘도 어떤 것은 크고 어떤 것은 작아 보인다 — 호출부가 눈으로 맞춘다.
  final double iconSize;
  final String? tooltip;
  final bool selected;
  final VoidCallback onTap;

  const DayFilterChip({
    super.key,
    this.label,
    this.icon,
    this.iconSize = 17,
    this.tooltip,
    required this.selected,
    required this.onTap,
  }) : assert(label != null || icon != null, 'label 또는 icon 중 하나는 필요하다');

  @override
  State<DayFilterChip> createState() => _DayFilterChipState();
}

class _DayFilterChipState extends State<DayFilterChip>
    with SingleTickerProviderStateMixin {
  static const Duration _kPop = Duration(milliseconds: 180);

  late final AnimationController _popCtrl = AnimationController(
    vsync: this,
    duration: _kPop,
  );
  // 1.0 → 1.05 → 1.0. 커질 때보다 돌아올 때를 조금 길게 잡아 말랑한 느낌.
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.05,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.05,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 60,
    ),
  ]).animate(_popCtrl);

  @override
  void dispose() {
    _popCtrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    _popCtrl.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final chip = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: widget.selected ? 1.0 : 0.0),
        duration: _kPop,
        curve: Curves.easeOut,
        builder: (context, t, child) => ScaleTransition(
          scale: _scale,
          child: CustomPaint(painter: _PillPainter(t), child: _buildContent(t)),
        ),
      ),
    );
    if (widget.tooltip == null) return chip;
    return Tooltip(message: widget.tooltip!, child: chip);
  }

  Widget _buildContent(double t) {
    final fg = Color.lerp(DayFilterPalette.label, Colors.white, t)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: widget.icon != null
            ? Icon(
                widget.icon,
                size: widget.iconSize,
                color: Color.lerp(
                  DayFilterPalette.selectedFrom,
                  Colors.white,
                  t,
                ),
              )
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  widget.label!,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    color: fg,
                    fontSize: 12,
                    fontWeight: t > 0.5 ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
      ),
    );
  }
}

/// 알약 버튼 한 개를 그리는 페인터 — 그림자 → 본체 → 광택 → 외곽선 순.
///
/// [t]는 0(비선택) → 1(선택) 전환값이고, 형태는 [t]와 무관하게 항상 같은
/// 캡슐이다. 색·그림자·광택 세기만 보간한다.
class _PillPainter extends CustomPainter {
  final double t;

  const _PillPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final radius = Radius.circular(size.height / 2);
    final pill = RRect.fromRectAndRadius(rect, radius);

    // 1) 그림자 — 흩어지는 blur 없이 아주 얕은 입체감만 남긴다.
    canvas.drawRRect(
      pill.shift(Offset(0, 0.5 + 0.5 * t)),
      Paint()
        ..color = DayFilterPalette.shadow.withValues(alpha: 0.04 + 0.08 * t),
    );

    // 2) 본체 — 평평하고 깔끔한 알약 형태만 유지한다. 선택 시와 비선택 시의
    //    색 변화는 있지만, 흐릿한 번짐 효과는 제거한다.
    canvas.drawRRect(
      pill,
      Paint()
        ..isAntiAlias = true
        ..shader = ui.Gradient.linear(
          Offset(rect.width * 0.15, 0),
          Offset(rect.width * 0.85, rect.height),
          [
            Color.lerp(
              DayFilterPalette.pillTop,
              DayFilterPalette.selectedFrom,
              t,
            )!,
            Color.lerp(
              DayFilterPalette.pillBottom,
              DayFilterPalette.selectedTo,
              t,
            )!,
          ],
        ),
    );

    // 3) 외곽선 — 비선택은 연핑크 라인 그대로, 선택 시엔 흰 림라이트로 바뀌어
    //    핑크 위에서도 테두리가 남는다. 번지는 광택은 제거한다.
    canvas.drawRRect(
      pill.deflate(0.55),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..isAntiAlias = true
        ..color = Color.lerp(
          DayFilterPalette.outline,
          Colors.white.withValues(alpha: 0.5),
          t,
        )!,
    );
  }

  @override
  bool shouldRepaint(covariant _PillPainter oldDelegate) => oldDelegate.t != t;

  @override
  bool hitTest(Offset position) => true;
}

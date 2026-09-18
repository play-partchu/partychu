import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// 관리자 웹은 PC 화면을 기준으로 만들어졌다. 이 파일은 **그 디자인을 그대로
/// 두고** 좁은 화면에서만 폭을 풀어주기 위한 기준점만 모아둔다.
///
/// 원칙: 화면이 넓으면 기존에 박아둔 고정 폭이 그대로 나오고(= PC 디자인
/// 무변경), 좁을 때만 본문 폭에 맞춰 줄어든다.
class AdminBreakpoints {
  AdminBreakpoints._();

  /// 이 폭 미만이면 좌측 사이드바를 Drawer로 접는다.
  static const sidebar = 900.0;

  /// 이 폭 미만이면 제목과 버튼을 한 줄에 두지 않고 줄을 나눈다.
  static const compact = 600.0;

  /// 데스크톱에서 사이드바가 차지하는 폭.
  static const sidebarWidth = 232.0;

  /// 본문(컨텐츠 영역)의 좌우 여백.
  static const pagePaddingWide = 28.0;
  static const pagePaddingNarrow = 16.0;
}

extension AdminResponsive on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;

  /// 사이드바가 Drawer로 접히는 폭인지.
  bool get isMobileLayout => screenWidth < AdminBreakpoints.sidebar;

  /// 제목줄·버튼줄을 세로로 쌓아야 하는 폭인지.
  bool get isCompact => screenWidth < AdminBreakpoints.compact;

  /// 본문에서 실제로 쓸 수 있는 최대 폭(사이드바·페이지 여백 제외).
  double get contentMaxWidth {
    final padding = (isMobileLayout
            ? AdminBreakpoints.pagePaddingNarrow
            : AdminBreakpoints.pagePaddingWide) *
        2;
    final sidebar = isMobileLayout ? 0.0 : AdminBreakpoints.sidebarWidth;
    return math.max(0, screenWidth - sidebar - padding);
  }

  /// PC 기준으로 박아둔 고정 폭을 그대로 쓰되, 본문 폭을 넘으면 줄인다.
  /// 넓은 화면에서는 [design]이 그대로 나오므로 기존 레이아웃이 변하지 않는다.
  double fluid(double design) => math.min(design, contentMaxWidth);

  /// 다이얼로그 내용 폭 — 화면에서 좌우 여백([margin])을 뺀 값을 넘지 않게 한다.
  /// AlertDialog 자체 패딩까지 감안해 기본 여백을 넉넉히 둔다.
  double dialogWidth(double design, {double margin = 44}) =>
      math.min(design, math.max(0, screenWidth - margin * 2));
}

/// 넓은 화면에서는 각 칸을 [Expanded]로 나란히 놓고(= 기존 `Row(Expanded…)`와
/// 같은 결과), 좁은 화면에서는 세로로 쌓는다.
///
/// 카드 2~3개를 가로로 붙여 두던 자리에 그대로 끼워 넣기 위한 것이다 —
/// 360px에서 3단이면 칸당 100px도 안 나와 내용이 서로 겹친다.
class ResponsiveRow extends StatelessWidget {
  const ResponsiveRow({
    super.key,
    required this.children,
    this.spacing = 16,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  final List<Widget> children;
  final double spacing;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    if (context.isMobileLayout) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: spacing),
            children[i],
          ],
        ],
      );
    }
    return Row(
      crossAxisAlignment: crossAxisAlignment,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(width: spacing),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}

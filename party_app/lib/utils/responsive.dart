import 'package:flutter/widgets.dart';

/// 앱 전체에서 공통으로 쓰는 반응형 브레이크포인트.
/// 모바일 UI는 그대로 유지하고, 이 값 이상일 때만 데스크톱/태블릿 전용
/// 레이아웃(예: 좌측 필터 / 가운데 목록 / 우측 지도·상세 3단 구성)로 분기한다.
class Responsive {
  Responsive._();

  static const double tabletBreakpoint = 700;
  static const double desktopBreakpoint = 1100;

  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < tabletBreakpoint;

  static bool isTablet(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= tabletBreakpoint && w < desktopBreakpoint;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= desktopBreakpoint;
}

/// 브레이크포인트별로 다른 위젯을 보여주고 싶을 때 쓰는 헬퍼.
/// tablet/desktop을 생략하면 mobile 위젯을 그대로 재사용한다 — 즉 기존
/// 모바일 화면 코드를 건드리지 않고 데스크톱 전용 래퍼만 추가할 수 있다.
class ResponsiveLayout extends StatelessWidget {
  final WidgetBuilder mobile;
  final WidgetBuilder? tablet;
  final WidgetBuilder? desktop;

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    if (Responsive.isDesktop(context) && desktop != null) {
      return desktop!(context);
    }
    if (Responsive.isTablet(context) && (tablet ?? desktop) != null) {
      return (tablet ?? desktop)!(context);
    }
    return mobile(context);
  }
}

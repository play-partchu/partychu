import 'package:flutter/material.dart';
import 'package:party_app/utils/responsive.dart';

/// 태블릿/데스크톱 폭(웹 브라우저)에서, 기존 모바일 화면을 새로 디자인하지
/// 않고 그대로 휴대폰 비율의 고정폭 카드 안에 가운데 정렬해 보여준다 —
/// 늘어진 모바일 레이아웃 대신 앱과 동일한 UX를 유지하기 위함.
///
/// `main_screen.dart`는 이미 전용 데스크톱(3단)/태블릿(2단) 레이아웃을 갖고
/// 있어 이 래퍼를 쓰지 않는다 — 그 화면을 제외한, `Navigator.push`로 열리는
/// 나머지 모든 화면(상세/등록/마이페이지/채팅 등)에 [webFramedRoute]를 통해
/// 적용된다.
///
/// 모바일 폭(네이티브 앱 포함, `Responsive.isMobile`)에서는 완전히
/// no-op으로 child를 그대로 반환하므로 기존 모바일 동작에는 전혀 영향이
/// 없다.
class WebFrame extends StatelessWidget {
  final Widget child;

  static const double frameWidth = 480;

  const WebFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (Responsive.isMobile(context)) return child;
    return ColoredBox(
      color: const Color(0xFFEDE3E7),
      child: Center(
        child: Container(
          width: frameWidth,
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 28,
                offset: Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }
}

/// 기존에 `MaterialPageRoute(builder: ...)`로 화면을 열던 자리를 그대로
/// 대체하는 헬퍼 — 화면 파일 자체는 손대지 않고, 웹의 넓은 화면에서만
/// [WebFrame]으로 감싸 보여준다. `fullscreenDialog`는 기존 호출부 그대로
/// 전달할 수 있도록 옵션으로 남겨둔다.
Route<T> webFramedRoute<T>(
  WidgetBuilder builder, {
  bool fullscreenDialog = false,
}) {
  return MaterialPageRoute<T>(
    builder: (context) => WebFrame(child: builder(context)),
    fullscreenDialog: fullscreenDialog,
  );
}

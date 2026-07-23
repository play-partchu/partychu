import 'package:flutter/material.dart';
import 'package:party_app/utils/user_session.dart';

/// 로그인 상태(또는 닉네임/본인인증 같은 프로필 필드)가 바뀔 때마다 자식을
/// 다시 그리는 래퍼 — "로그인이 필요합니다" 화면에서 로그인을 마치고
/// 돌아왔을 때, 사용자가 뒤로 갔다 다시 들어오지 않아도 즉시 로그인된
/// 상태로 갱신되게 한다. [UserSession.revision]을 구독하기만 하면 되므로,
/// 로그인 화면을 어떤 경로로 열었든(await 여부와 무관하게) 항상 반영된다.
class AuthRebuilder extends StatelessWidget {
  final WidgetBuilder builder;

  const AuthRebuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: UserSession.revision,
      builder: (context, revision, _) => builder(context),
    );
  }
}

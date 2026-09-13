import 'package:flutter/foundation.dart' show kIsWeb;

/// 웹에서 앱을 **처음 연 주소**를 붙잡아 두는 곳.
///
/// ── 왜 필요한가 ──────────────────────────────────────────────────────────
/// 화면 쪽에서 `Uri.base`를 읽으면 이미 늦다. Flutter가 경로 기반 URL 전략
/// (`usePathUrlStrategy`)으로 첫 라우트를 세우면서 브라우저 주소를 base href
/// (`/app/`)로 덮어쓰기 때문에, **쿼리스트링이 통째로 사라진 뒤**에 읽게 된다.
/// 실제로 랜딩페이지가 넘겨준 `/app/?tab=place` 의 `tab`은 MainScreen의
/// initState 시점에 이미 비어 있었다.
///
/// 그래서 `runApp` 전에 [capture]를 한 번 불러 그 순간의 주소를 남긴다.
/// 이후에는 어디서든 [param]으로 같은 값을 읽는다.
///
/// 앱(Android/iOS)에서는 의미가 없다 — `Uri.base`가 파일 URI라 [param]은
/// 항상 null이고, 딥링크는 app_links가 따로 다룬다.
class WebLaunchUrl {
  WebLaunchUrl._();

  static Uri _uri = Uri.base;
  static bool _captured = false;

  /// main()의 **맨 앞**에서 한 번 부른다(usePathUrlStrategy·runApp보다 먼저).
  static void capture() {
    if (_captured) return;
    _uri = Uri.base;
    _captured = true;
  }

  /// 붙잡아 둔 최초 주소. [capture] 전에 읽으면 지금의 `Uri.base`다.
  static Uri get value => _uri;

  /// 최초 주소의 쿼리 파라미터 — 웹이 아니면 항상 null.
  static String? param(String name) =>
      kIsWeb ? _uri.queryParameters[name] : null;
}

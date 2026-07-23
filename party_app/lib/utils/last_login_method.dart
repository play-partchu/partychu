import 'package:shared_preferences/shared_preferences.dart';

/// 마지막으로 성공한 소셜 로그인 방식 — 로그인 화면에서 "최근 사용" 배지를
/// 표시해 사용자가 매번 쓰는 버튼을 바로 찾을 수 있게 한다.
enum LastLoginMethod {
  google,
  kakao,
  naver;

  static const _prefsKey = 'last_login_method';

  static Future<LastLoginMethod?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    for (final m in LastLoginMethod.values) {
      if (m.name == raw) return m;
    }
    return null;
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, name);
  }
}

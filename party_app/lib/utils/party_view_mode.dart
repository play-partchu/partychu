import 'package:shared_preferences/shared_preferences.dart';

/// 파티 목록 "보기 방식" — 사용자가 고른 값은 기기에 저장되어 앱을 다시
/// 실행해도 유지된다.
enum PartyViewMode {
  /// 작은 카드 — 한 화면에 4~6개, 정보 위주.
  compact,

  /// 기본 카드(기본값) — 지금과 동일한 카드.
  standard,

  /// 영상 크게 보기 — 카드 하나가 화면 대부분을 차지, 대표 동영상 자동재생.
  video;

  static const _prefsKey = 'party_view_mode';

  String get label => switch (this) {
    PartyViewMode.compact => '작은 카드',
    PartyViewMode.standard => '기본 카드',
    PartyViewMode.video => '영상 크게 보기',
  };

  static Future<PartyViewMode> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    return PartyViewMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => PartyViewMode.standard,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, name);
  }
}

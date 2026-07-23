import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 파티 상세페이지의 detailBlocks 보기 방식 — `party_view_mode.dart`(파티
/// 목록 보기 방식)와 동일한 패턴. 사용자가 고른 값은 파티별이 아니라
/// 기기 전역 취향으로 저장되어, 다른 파티 상세화면에 들어가거나 앱을
/// 다시 실행해도 마지막으로 고른 방식이 유지된다.
enum PartyDetailViewMode {
  /// 상세페이지 보기(기본값) — PartyDetailBlockPreview 그대로.
  designed,

  /// 글만 보기 — 텍스트 블록만 읽기 편하게 재구성.
  textOnly;

  static const _prefsKey = 'party_detail_view_mode';

  String get label => switch (this) {
        PartyDetailViewMode.designed => '상세페이지',
        PartyDetailViewMode.textOnly => '글만보기',
      };

  /// 저장된 값이 없거나(최초 실행) 알 수 없는 값(예전 버전의 값 등)이면
  /// 항상 [designed]로 안전하게 대체한다.
  static Future<PartyDetailViewMode> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    return PartyDetailViewMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => PartyDetailViewMode.designed,
    );
  }

  /// 저장에 실패해도(디스크 오류 등) 화면 동작에는 영향이 없어야 하므로
  /// 예외를 삼키고 로그만 남긴다.
  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, name);
    } catch (e) {
      debugPrint('[PartyDetailViewMode] 저장 실패: $e');
    }
  }
}

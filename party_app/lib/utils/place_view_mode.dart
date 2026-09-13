import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 장소대여(플레이스) 목록 "보기 방식" — 파티 목록의 [PartyViewMode]와 같은
/// 방식으로 기기에 저장되어 앱을 다시 실행해도 유지된다.
///
/// 파티 목록은 "큰 카드"를 별도 전체화면 피드로 열지만, 플레이스/장소대여는
/// 목록 안에서 카드 한 장씩 크게 보여준다 — 카드 구조(대표 미디어 + 하단
/// 그라디언트 위 정보 오버레이 + 상세보기 버튼)는 파티 큰 카드와 동일하다.
enum PlaceViewMode {
  /// 작은 카드 — 지도 '이 근처 파티' 카드와 같은 가로형 카드(ListCardShell).
  compact,

  /// 기본 카드(기본값) — 파티 목록 기본 카드와 같은 2열 그리드 카드(GridCardShell).
  standard,

  /// 큰 카드 — 파티 목록 큰 카드(PartyVideoFeedCard)와 같은 구조의 1열 대형 카드.
  large;

  static const _prefsKey = 'place_view_mode';

  /// 토글 버튼에는 글씨 없이 아이콘만 쓰지만(복잡해 보여서), 접근성 라벨과
  /// 툴팁에는 이 이름을 그대로 쓴다.
  String get label => switch (this) {
    PlaceViewMode.compact => '작은 카드 보기',
    PlaceViewMode.standard => '기본 카드 보기',
    PlaceViewMode.large => '큰 카드 보기',
  };

  /// 보기 방식 아이콘 — 가로줄 목록 / 2열 그리드 / 세로로 큰 한 장.
  IconData get icon => switch (this) {
    PlaceViewMode.compact => Icons.view_list_rounded,
    PlaceViewMode.standard => Icons.grid_view_rounded,
    PlaceViewMode.large => Icons.crop_portrait_rounded,
  };

  static Future<PlaceViewMode> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    return PlaceViewMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => PlaceViewMode.standard,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, name);
  }
}

/// 🛍️ 파티샵 목록의 보기 방식 — **값은 플레이스와 같은 [PlaceViewMode]**를
/// 그대로 쓰고, 저장 자리만 따로 둔다.
///
/// ## 왜 enum을 새로 만들지 않는가
/// 칸 셋(작은/기본/큰)도, 아이콘도, 이름도 플레이스와 **완전히 같아야** 한다 —
/// 같은 성격의 컨트롤이 탭마다 다르게 보이면 서비스가 따로 만든 화면처럼
/// 읽힌다([ViewModeMenuButton] 상단 주석과 같은 이유). 값을 복제하면 한쪽 아이콘을
/// 바꿨을 때 다른 쪽만 남는다.
///
/// ## 왜 저장 키는 따로인가
/// 파티·플레이스가 각자 키를 쓰는 것과 같은 이유다 — 파티샵 목록을 작은 카드로
/// 보기로 했다고 플레이스 목록까지 바뀌면 곤란하다. 두 목록은 카드가 담는
/// 것도, 보는 목적도 다르다.
extension ShopViewModePrefs on PlaceViewMode {
  static const _shopPrefsKey = 'shop_view_mode';

  /// 저장된 파티샵 보기 방식 — 처음이면 **기본 카드**다.
  static Future<PlaceViewMode> loadForShop() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_shopPrefsKey);
    return PlaceViewMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => PlaceViewMode.standard,
    );
  }

  Future<void> saveForShop() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_shopPrefsKey, name);
  }
}

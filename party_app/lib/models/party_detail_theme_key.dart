/// 파티 상세페이지(detailBlocks) 디자인 테마 키 — Firestore `parties.detailTheme`에
/// 이 enum의 `.name` 문자열만 저장한다(테마 객체 전체는 저장하지 않음).
/// 순수 Dart(Flutter Color/IconData 의존 없음) — 실제 색상 팔레트는
/// 위젯 계층인 `lib/widgets/party_detail_theme.dart`에서만 정의한다.
library;

enum PartyDetailThemeKey {
  /// PartyChu 기본 — 흰 배경 + 핑크 포인트, 가장 밝고 친근한 기본 디자인.
  partychu,

  /// 러블리 — 아이보리/연핑크 배경 + 핑크·라벤더 포인트.
  lovely,

  /// 프리미엄 다크 — 검정/차콜 배경 + 골드 포인트.
  premiumDark,

  /// 클럽 네온 — 매우 어두운 배경 + 네온 핑크/퍼플 포인트.
  clubNeon,

  /// 감성 미니멀 — 화이트/오프화이트 배경 + 베이지·브라운 포인트, 넓은 여백.
  minimal,
}

/// 저장된 값이 없거나(기존 파티) 알 수 없는 값이면 항상 [PartyDetailThemeKey.partychu]로
/// 안전하게 대체한다 — 잘못된 테마 값 하나 때문에 상세화면 전체가 깨지지 않도록.
PartyDetailThemeKey partyDetailThemeKeyFromString(String? raw) {
  for (final key in PartyDetailThemeKey.values) {
    if (key.name == raw) return key;
  }
  return PartyDetailThemeKey.partychu;
}

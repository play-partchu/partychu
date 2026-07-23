/// 파티 상세 설명 방식 — "간편 자동 꾸미기" 또는 "직접 상세페이지 만들기"
/// 중 하나만 선택한다. Firestore `parties.detailDescriptionMode`에 이
/// enum의 `.name` 문자열만 저장한다. 순수 Dart(Flutter 의존 없음).
///
/// 이 필드가 아예 없는(이 기능 이전에 등록된) 파티는 [fromString]을 쓰지
/// 않고 호출부에서 `detailBlocks` 유무로 직접 추론한다 — 기존 화면과
/// 완전히 동일하게 렌더링하기 위함(`party_detail_screen.dart` 참고).
library;

enum PartyDescriptionMode {
  /// 간편 자동 꾸미기 — 소개글(`description`)만 작성하면 테마/강도에 맞춰
  /// 자동으로 꾸며 보여준다. 일반 사용자 기본 추천.
  auto,

  /// 직접 상세페이지 만들기 — 기존 블록 에디터(`detailBlocks`)로 사진/글
  /// 블록을 직접 배치한다.
  blocks,
}

/// 저장된 값이 없거나 알 수 없는 값이면 항상 [PartyDescriptionMode.auto]로
/// 안전하게 대체한다(신규 등록 기본값과 동일).
PartyDescriptionMode partyDescriptionModeFromString(String? raw) {
  for (final value in PartyDescriptionMode.values) {
    if (value.name == raw) return value;
  }
  return PartyDescriptionMode.auto;
}

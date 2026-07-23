/// 블록형 상세페이지 자동 꾸미기 강도 — Firestore `parties.detailDecorationIntensity`에
/// 이 enum의 `.name` 문자열만 저장한다. 순수 Dart(Flutter 의존 없음) — 실제
/// 장식(그라데이션/글로우/장식 요소)은 위젯 계층인
/// `lib/widgets/party_detail_decoration.dart`에서만 정의한다.
library;

enum PartyDetailDecorationIntensity {
  /// 심플 — 사진 카드에 여백·둥근 모서리·얇은 테두리만 적용. 배경 장식/구분
  /// 장식/첫 사진 강조 장식 없음(기존 렌더링과 사실상 동일).
  simple,

  /// 기본(기본값) — 배경 그라데이션+글로우+장식, 사진 카드 그림자, 블록 구분
  /// 장식, 첫 사진 프레임+그라데이션까지 적용.
  standard,

  /// 화려하게 — 기본에 장식 밀도를 더 높이고 첫 사진에 반짝이/빛 번짐 추가.
  rich,
}

/// 저장된 값이 없거나(기존 파티) 알 수 없는 값이면 항상
/// [PartyDetailDecorationIntensity.standard]로 안전하게 대체한다.
PartyDetailDecorationIntensity partyDetailDecorationIntensityFromString(String? raw) {
  for (final value in PartyDetailDecorationIntensity.values) {
    if (value.name == raw) return value;
  }
  return PartyDetailDecorationIntensity.standard;
}

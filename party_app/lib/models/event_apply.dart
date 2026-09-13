// ─────────────────────────────────────────────────────────────────────────────
// 매장 이벤트가 **신청을 받는 방식**.
//
// ── 왜 생겼나 ────────────────────────────────────────────────────────────────
// 예전에는 매장 이벤트를 "신청 없이 방문해서 즐기는 행사"로 정의하고, 신청을
// 받고 싶으면 🎉 파티로 보냈다. 그런데 신청 여부는 두 개념을 가르는 기준이
// 아니다 — 생일 이벤트처럼 **매장이 여는 행사인데 사전 신청을 받는 것**이
// 얼마든지 있다([HostOffering] 상단 주석). 그 이벤트는 갈 곳이 없었다.
//
//   🎪 매장 이벤트 = 매장이 주체가 되어 여는 행사·프로모션·혜택
//   🎉 파티        = 참가자 모집이 중심인 모임
//
// 신청은 이제 **양쪽 다 할 수 있는 일**이고, 이 파일이 매장 이벤트 쪽 스위치다.
//
// ── 문의(inquiryEnabled)와 어떻게 겹치나 ─────────────────────────────────────
// 문의 받기는 이미 세 도메인 공용 필드가 있다([ListingInquiry]). 여기서 그것을
// 다시 만들지 않는다 — 이 값은 문의를 **넓히지 못하고 좁히기만 한다.**
//
//   applyMode        문의 버튼            신청 버튼
//   none             inquiryEnabled 그대로   없음      ← 이 필드가 없던 옛 이벤트
//   applyOnly        숨김                   있음
//   inquiryAndApply  inquiryEnabled 그대로   있음
//
// 그래서 `inquiryEnabled: false`인 이벤트를 `inquiryAndApply`로 바꿔도 문의
// 버튼이 몰래 켜지지 않는다. 문의의 정본은 끝까지 [ListingInquiry] 하나다.
// ─────────────────────────────────────────────────────────────────────────────

/// 이 이벤트가 신청을 받는가, 받는다면 어떤 모습으로 받는가.
///
/// 키는 Firestore에 그대로 저장되므로 **바꾸면 기존 문서가 못 읽는다.**
/// 문구(label)는 화면 표시용이라 자유롭게 다듬어도 된다.
enum EventApplyMode {
  /// 신청을 받지 않는다 — 자유롭게 방문하는 행사.
  ///
  /// **필드가 없던 옛 이벤트의 해석값이기도 하다.** 그래서 이 기능이 생기기
  /// 전에 등록된 이벤트는 게스트 화면이 예전과 한 픽셀도 다르지 않다.
  none(key: 'none', label: '신청 안 받음'),

  /// 신청하기 버튼만 보여준다.
  applyOnly(key: 'apply', label: '신청하기'),

  /// 문의하기와 신청하기를 나란히 보여준다.
  inquiryAndApply(key: 'inquiry_and_apply', label: '문의 및 신청하기');

  const EventApplyMode({required this.key, required this.label});

  /// Firestore에 저장되는 값.
  final String key;

  /// 등록 화면 선택지에 뜨는 이름.
  final String label;

  /// 이 이벤트가 신청을 받는가 — 등록 화면의 ON/OFF 스위치가 보는 값.
  bool get receivesApplications => this != none;

  /// 문의 버튼을 함께 둘 수 있는가.
  ///
  /// ⚠️ "둔다"가 아니라 "둘 수 있다"이다. 실제로 그릴지는 여기에 더해
  ///    [ListingInquiry.isEnabled]가 함께 참이어야 한다 — 이 값 혼자서는
  ///    호스트가 꺼 둔 문의를 절대 켜지 못한다.
  bool get allowsInquiry => this != applyOnly;

  /// 모르는 값·빈 값은 전부 [none]이다.
  ///
  /// 판정을 못 했을 때 신청을 열지 않는다 — 호스트가 켠 적 없는 이벤트에
  /// 신청 버튼이 생기면 그 신청은 아무도 받지 않는다.
  static EventApplyMode fromKey(String? key) {
    for (final m in EventApplyMode.values) {
      if (m.key == key) return m;
    }
    return defaultMode;
  }

  /// 등록 화면 기본값이자, 필드가 없는 문서의 해석값.
  static const EventApplyMode defaultMode = none;

  /// 신청 받기를 켰을 때 고를 수 있는 방식 — ON/OFF 스위치가 켜진 뒤의 선택지다.
  static const List<EventApplyMode> pickable = [applyOnly, inquiryAndApply];

  /// placePromotions 문서에 저장되는 필드 이름.
  static const String field = 'applyMode';
}

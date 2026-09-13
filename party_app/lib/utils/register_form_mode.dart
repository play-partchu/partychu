/// 등록 화면이 "무엇을 하는 중인지" 나타내는 공용 모드.
///
/// ── 이 파일이 있는 이유 ──────────────────────────────────────────────────
/// 예전에는 등록과 재등록이 서로 다른 화면 파일에 각각 구현돼 있었다. 그래서
/// 등록에만 기능이 추가되고 재등록에는 빠지는 일이 반복됐다(파티 재등록에는
/// 차수 편집기·연령제한 시트·미입력 항목 배너가 아예 없었다).
///
/// 이제 규칙은 하나다.
///
///   **등록 화면이 정본이다.** 재등록은 등록 화면을 [RegisterFormMode.reregister]
///   로 열어 **같은 폼, 같은 위젯, 같은 검증**을 그대로 쓴다. 모드가 갈라도 되는
///   것은 아래 세 가지뿐이다.
///
///     1. 화면 제목·제출 버튼 문구
///     2. 진입 시 기존 문서 내용을 불러오는지(prefill)
///     3. 임시저장(Draft)을 쓰는지 — 재등록은 이미 불러온 내용이 있으므로 끈다
///
///   저장 대상은 모드와 무관하게 **항상 새 문서**다. 재등록은 "내용은 복사하되
///   모집은 새로 시작"이므로, 원본 파티는 지난 기록으로 그대로 보존되고 신청자·
///   참가 인원·모집 상태 같은 실시간 값만 초기화된 새 문서가 만들어진다.
///
/// 새 도메인(플레이스·플레이스+파티·공간대여·파티크루)을 통합할 때도 이 enum을
/// 그대로 쓴다 — 도메인마다 mode 이름을 새로 만들면 다시 갈라지기 때문이다.
enum RegisterFormMode {
  /// 빈 화면에서 새로 등록한다. 임시저장 복구/자동저장이 동작한다.
  create,

  /// 기존 문서의 내용을 불러와 **새 문서로** 다시 등록한다.
  /// 임시저장은 쓰지 않는다(이미 불러온 내용이 있어 덮어쓸 위험만 있다).
  reregister,

  /// 기존 문서를 불러와 **그 문서를 갱신**한다.
  ///
  /// 도메인마다 이 모드를 쓸지가 갈린다. 플레이스처럼 문서에 매달린 실시간
  /// 상태(신청자·정원 등)가 없는 도메인은 등록 폼을 그대로 재사용하는 게 맞고,
  /// 파티처럼 이미 신청자가 붙은 문서를 이어받아야 하는 도메인은 보존 규칙이
  /// 완전히 달라서 별도 화면(PartyEditScreen)을 그대로 둔다.
  ///
  /// 플레이스에서는 숨김(isActive:false) 상태에서 이 모드로 저장하는 것이 곧
  /// "재등록"이다 — 저장과 동시에 다시 노출된다.
  edit;

  bool get isCreate => this == RegisterFormMode.create;
  bool get isReregister => this == RegisterFormMode.reregister;
  bool get isEdit => this == RegisterFormMode.edit;

  /// 기존 문서를 불러와 시작하는 모드인지 — prefill이 필요한지의 판단 기준.
  bool get startsFromExistingDoc => isReregister || isEdit;

  /// AppBar 제목에 쓸 접두어 — '파티', '플레이스'처럼 도메인 이름을 넘긴다.
  String screenTitle(String noun) => switch (this) {
    RegisterFormMode.create => '$noun 등록',
    RegisterFormMode.reregister => '$noun 재등록',
    RegisterFormMode.edit => '$noun 수정',
  };

  /// 하단 제출 버튼 문구.
  String submitLabel(String noun) => switch (this) {
    RegisterFormMode.create => '$noun 등록하기',
    RegisterFormMode.reregister => '$noun 재등록하기',
    RegisterFormMode.edit => '수정 완료',
  };
}

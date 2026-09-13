/// 파티 오픈 상태 — `openState` 필드 하나로 "오픈예정 / 정상 파티"를 가른다.
///
/// `recruitStatus`('모집중'/'마감'/'취소')에는 값을 추가하지 **않는다**. 그
/// 문자열은 앱과 서버 10여 곳에 하드코딩돼 있어서, 값을 하나 늘리면 한 군데만
/// 놓쳐도 오픈예정 파티에 신청이 들어간다. 대신 독립 필드를 두고 기존
/// recruitStatus 로직은 그대로 둔다.
///
/// 서버 규칙(`functions/partyOpenState.js`)과 **같은 판정을 하게 유지해야
/// 한다** — 특히 "필드가 없으면 open"은 기존 운영 데이터를 지키는 규칙이라
/// 양쪽이 어긋나면 운영 중인 파티가 통째로 잠긴다.
class PartyOpenState {
  PartyOpenState._();

  /// 오픈예정 — 신청·예약·결제 전부 불가. 오픈 알림만 받을 수 있다.
  static const preopen = 'preopen';

  /// 정상 파티 — 기존 recruitStatus/마감/정원 로직이 그대로 적용된다.
  static const open = 'open';

  /// 목록 카드·상세에 띄우는 라벨.
  static const preopenLabel = '오픈예정';

  /// 날짜를 아직 정하지 않은 사전등록 파티의 라벨.
  static const dateTbdLabel = '날짜 미정';

  /// 파티 문서의 오픈 상태. **필드가 없으면 항상 [open]** — 이 기본값 덕분에
  /// 이 기능 이전에 만들어진 파티는 아무 영향도 받지 않는다.
  static String of(Map<String, dynamic> d) =>
      d['openState'] == preopen ? preopen : open;

  /// 오픈예정 파티인가.
  static bool isPreopen(Map<String, dynamic> d) => of(d) == preopen;

  /// 날짜가 아직 정해지지 않았는가.
  ///
  /// 오픈예정 파티만 날짜 없이 등록될 수 있다. 정상 파티에 이 플래그가
  /// 남아 있어도 날짜 기반 화면이 깨지지 않도록 `openState`와 함께 본다.
  static bool isDateTbd(Map<String, dynamic> d) =>
      isPreopen(d) && d['dateTbd'] == true;

  /// 신청·예약·결제를 받을 수 있는 상태인가.
  ///
  /// 마감·정원·연령 같은 나머지 조건은 여기서 보지 않는다 — 이 함수는
  /// "오픈 자체가 됐는가"만 답한다.
  static bool acceptsApplications(Map<String, dynamic> d) => !isPreopen(d);

  /// 호스트가 등록한 사업자가 인증을 마쳤는지(공개 문서 미러링 값).
  ///
  /// 원본은 `users/{uid}.businessVerification.status`인데 그 문서는 본인과
  /// 관리자만 읽을 수 있어서, 공개 카드/상세용으로 불리언 하나만 파티 문서에
  /// 복사해 둔다(사업자등록번호·대표자명 등 원문은 절대 복사하지 않는다).
  static bool hostBusinessVerified(Map<String, dynamic> d) =>
      d['hostBusinessVerified'] == true;
}

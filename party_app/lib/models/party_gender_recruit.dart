/// 파티의 **성별별 모집 상태** — 호스트가 남성 모집과 여성 모집을 따로 열고
/// 닫는 설정 하나(Firestore `genderRecruitStatus`).
///
/// ## 왜 recruitStatus에 값을 더하지 않는가
///
/// `recruitStatus`('모집중'/'마감'/'취소')는 앱과 서버 10여 곳에 문자열
/// 그대로 박혀 있어서, 값을 하나 늘리면 한 군데만 놓쳐도 마감된 파티에 신청이
/// 들어간다([PartyOpenState]가 같은 이유로 독립 필드를 쓴다). 그래서 여기서도
/// 독립 필드를 두고 **기존 recruitStatus 로직은 그대로 둔다** — 전체 모집마감은
/// 지금처럼 `recruitStatus: '마감'`이고, 이 필드는 "전체는 모집중인데 한쪽
/// 성별만 닫혔다"만 표현한다.
///
/// ## 저장 형태
///
/// ```
/// genderRecruitStatus: { male: 'open' | 'closed', female: 'open' | 'closed' }
/// ```
///
/// **필드가 없거나 키가 없으면 언제나 열림([open])이다.** 이 기본값 덕분에 이
/// 기능 이전에 만들어진 파티는 아무 영향도 받지 않는다(하위호환).
///
/// ## 파티 전체 설정이다 (회차별이 아니다)
///
/// 판정 단위는 `recruitStatus`와 **완전히 같다** — 파티 문서 하나에 한 벌이다.
///
///  · 정기 파티(scheduleType: 'recurring')는 문서 하나가 모든 회차를 담으므로
///    이 설정도 모든 회차에 함께 걸린다. 회차 하나만 닫는 수단은 이미 따로
///    있다(최소 인원 미달 자동 취소 = `occurrenceCancellations`, 그리고 회차별
///    마감 시각). 여기에 회차별 성별 상태를 더하면 같은 뜻의 스위치가 둘이 되고,
///    서버·앱 양쪽에서 어느 쪽이 이기는지가 매번 문제가 된다.
///  · 날짜 슬롯을 여러 개 만든 게시글은 **날짜마다 문서가 따로**라 날짜별로
///    다르게 둘 수 있다(모집 상태와 같은 성질 — [PartySlotSyncService]의
///    perDateStateKeys에 함께 들어간다).
///  · 차수(`rounds`)에는 걸리지 않는다. 차수는 모집 창구가 시각으로만 열리고
///    닫힌다(isRoundRecruitOpen) — 성별 개념이 없다.
///
/// ## 참가자 성비 공개 설정과는 별개다
///
/// [ParticipantGenderVisibility]는 "지금 참가한 사람들의 남/여 인원"을 감춘다.
/// 이쪽은 "지금 어느 성별의 신청을 받는가"라는 **모집 조건**이라, 성비를 감춘
/// 파티에서도 게스트에게 그대로 보여준다(감추면 신청할 수 있는지조차 알 수
/// 없다). 두 설정은 서로를 참조하지 않는다.
///
/// ## 표시만이 아니라 실제 차단이다
///
/// 최종 차단은 서버(`functions/partyGenderRecruit.js` →
/// reserveApplicantSlot)가 **같은 규칙으로** 한다 — 콜러블을 직접 불러도
/// 우회되지 않는다. 이 클래스는 그 서버 규칙의 거울이므로, 한쪽만 고치면
/// 화면과 실제 신청 결과가 어긋난다.
class PartyGenderRecruit {
  PartyGenderRecruit._();

  /// Firestore 필드명.
  static const field = 'genderRecruitStatus';

  static const male = 'male';
  static const female = 'female';

  /// 모집 중.
  static const open = 'open';

  /// 그 성별만 모집 마감.
  static const closed = 'closed';

  /// 게스트에게 보여주는 라벨.
  static const maleClosedLabel = '남성 모집마감';
  static const femaleClosedLabel = '여성 모집마감';
  static const maleOpenLabel = '남성 모집중';
  static const femaleOpenLabel = '여성 모집중';

  static Map<String, dynamic>? _map(Map<String, dynamic> data) {
    final raw = data[field];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  /// 저장된 값이 명시적으로 [closed]일 때만 닫힌 것으로 읽는다 —
  /// 필드·키가 없거나 값이 이상하면 **열림**이다(하위호환).
  ///
  /// 회차별 모집 상태([PartyOccurrenceRecruit])도 같은 모양의 맵을 회차 칸에
  /// 담으므로 **이 함수 하나로** 읽는다 — 규칙이 두 벌이 되면 문서 단위와
  /// 회차 단위의 하위호환 판정이 갈린다.
  static bool isClosedIn(Map<String, dynamic>? genderMap, String gender) =>
      genderMap?[gender] == closed;

  static bool _closed(Map<String, dynamic> data, String gender) =>
      isClosedIn(_map(data), gender);

  static bool isMaleClosed(Map<String, dynamic> data) => _closed(data, male);

  static bool isFemaleClosed(Map<String, dynamic> data) =>
      _closed(data, female);

  /// 이 성별의 신청을 지금 받는가. 성별을 모르면(비로그인·미인증) 판정하지
  /// 않고 true를 돌려준다 — 그런 사용자는 어차피 신청 전에 본인확인을 거치고,
  /// 서버가 그때의 정본 성별로 다시 판정한다.
  static bool acceptsGender(Map<String, dynamic> data, String? gender) =>
      !isClosedFor(data, gender);

  /// 이 성별에게 모집이 닫혀 있는가.
  ///
  /// 성별을 모르면 **양쪽이 다 닫힌 경우에만** 닫힘이다(그때는 성별과 무관하게
  /// 아무도 신청할 수 없으므로 판정에 성별이 필요 없다).
  static bool isClosedFor(Map<String, dynamic> data, String? gender) {
    if (gender == male) return isMaleClosed(data);
    if (gender == female) return isFemaleClosed(data);
    return isMaleClosed(data) && isFemaleClosed(data);
  }

  /// 성별 설정만으로 파티 전체가 닫힌 상태인가.
  ///
  /// 성별 제한 파티(`genderLimit`)는 받는 성별 하나만 보면 된다 — 남자만 받는
  /// 파티에서 남성 모집을 닫으면 그것으로 전체 마감이다.
  static bool isFullyClosed(Map<String, dynamic> data) {
    final limit = data['genderLimit'] as String? ?? 'all';
    if (limit == male) return isMaleClosed(data);
    if (limit == female) return isFemaleClosed(data);
    return isMaleClosed(data) && isFemaleClosed(data);
  }

  /// 한쪽만 닫힌 상태 — "남성 모집마감 · 여성 모집중"처럼 성별에 따라 답이
  /// 갈리는 파티인가. 이럴 때만 모집중인 성별에게도 상태를 알려준다
  /// (그러지 않으면 모집중 파티마다 배지가 붙는다).
  static bool hasSplit(Map<String, dynamic> data) =>
      isMaleClosed(data) != isFemaleClosed(data);

  /// 이 성별에게 보여줄 한 줄 — 자기 성별 기준이다.
  /// 성별을 모르면 null(공통 모집 상태만 보여준다).
  static String? labelFor(Map<String, dynamic> data, String? gender) {
    if (gender == male) {
      return isMaleClosed(data) ? maleClosedLabel : maleOpenLabel;
    }
    if (gender == female) {
      return isFemaleClosed(data) ? femaleClosedLabel : femaleOpenLabel;
    }
    return null;
  }

  /// 호스트·관리 화면용 요약 — '남성 모집마감 · 여성 모집중'.
  static String summaryLabel(Map<String, dynamic> data) => [
    isMaleClosed(data) ? maleClosedLabel : maleOpenLabel,
    isFemaleClosed(data) ? femaleClosedLabel : femaleOpenLabel,
  ].join(' · ');

  /// Firestore에 저장할 값. **둘 다 열려 있으면 필드를 지운다**(null) — 기본값과
  /// 같은 상태를 굳이 문서에 남기지 않아야, 이 기능을 쓰지 않는 파티가 예전
  /// 문서와 똑같이 유지된다.
  static Map<String, String>? toField({
    required bool maleClosed,
    required bool femaleClosed,
  }) {
    if (!maleClosed && !femaleClosed) return null;
    return {
      male: maleClosed ? closed : open,
      female: femaleClosed ? closed : open,
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 🎪 매장 이벤트 vs 🎉 파티 — **두 개념의 정본 문구**.
//
// ── 왜 한 곳에 모으나 ────────────────────────────────────────────────────────
// 이 둘은 데이터도 화면도 완전히 따로다(`placePromotions` / `parties`). 그런데
// 이름은 둘 다 "행사"라서, 등록하는 사장님도 보는 손님도 어느 쪽인지 헷갈렸다 —
// 화면마다 '이벤트'·'행사'·'파티'를 제각각 적어 두면 그 혼동이 굳는다.
//
// 그래서 **부르는 이름과 한 줄 정의는 여기 하나뿐**이다. 등록 선택 화면,
// 등록 폼 머리말, 서로를 가리키는 안내 줄이 전부 이 표를 읽는다.
//
// ── 구분 기준은 "무엇을 하는가"가 아니다 ─────────────────────────────────────
// DJ 공연도, 와인 모임도 양쪽 다 될 수 있다. 갈리는 지점은 **주체**다.
//
//   **매장이 여는 행사인가, 참가자를 모아 함께하는 모임인가?**
//
//     매장이 연다 → ✨ 매장 이벤트 (매장이 진행하는 행사·프로모션·혜택)
//     사람을 모은다 → 🎉 파티      (참가자를 모집해 신청·승인을 받는 모임)
//
// ⚠️ **신청 여부로 가르지 않는다.** 한 달간 주류 할인·1+1·시음처럼 그냥
//    방문하면 되는 것도, 생일 이벤트처럼 사전 신청이 필요한 것도 전부 매장이
//    여는 행사다 — 신청을 받는다는 이유로 파티가 되지 않는다. 예전 문구가
//    매장 이벤트를 "신청 없이 방문해서 즐기는 행사"로 못박아, 신청을 받는
//    매장 이벤트를 표현할 수 없게 만들었다.
//
// 이 문장([criterionHeadline])이 선택 화면 맨 위에 그대로 올라간다.
//
// ── 데이터는 합치지 않는다 ───────────────────────────────────────────────────
// 파티에는 신청·승인·참가자·참가비·결제가 달려 있고([parties]), 매장 이벤트는
// 매장 문서에 붙는 홍보 한 건이다([PlacePromotion]). 여기서 통일하는 것은
// **부르는 말과 고르는 자리**뿐이고, 저장 구조·기능은 예전 그대로다.
// ─────────────────────────────────────────────────────────────────────────────

// ── const가 필요한 자리를 위한 낱값 ─────────────────────────────────────────
// enum 인스턴스의 필드는 const 식이 아니라, 위젯의 const 생성자나 다른 정본의
// `static const`에 그대로 넣을 수 없다. 그런 자리에서도 **같은 문자열**을 쓰게
// 하려고 낱값을 따로 둔다 — 아래 enum도 이 값들로 만들어지므로 갈라질 수 없다.

/// ✨ — 매장 이벤트. 파티(🎉)와 절대 겹치지 않는 표시다.
const String kPlaceEventEmoji = '✨';
const String kPlaceEventLabel = '매장 이벤트';

/// 좁은 자리(격자 칸·배지)용 축약 — 이모지가 이미 ✨라 이것만으로 갈린다.
const String kPlaceEventShortLabel = '이벤트';

/// 매장 이벤트 **한 줄 정의**. 등록 선택 카드의 부제([HostOffering.criterion]),
/// 파티 쪽에서 건너오라고 묻는 줄([HostOffering.toPlaceEventPrompt]), 등록 폼
/// 머리말이 전부 이 한 문장을 쓴다 — 자리마다 다시 쓰면 그 순간 정의가 갈린다.
const String kPlaceEventCriterion = '매장에서 진행하는 이벤트·혜택';

/// 🎉 — 파티.
const String kPartyEmoji = '🎉';
const String kPartyLabel = '파티';

/// 호스트가 만들 수 있는 두 가지 '행사'.
enum HostOffering {
  /// 🎪 매장 이벤트 — `placePromotions` 한 건([PlacePromotion]).
  placeEvent(
    emoji: kPlaceEventEmoji,
    label: kPlaceEventLabel,
    shortLabel: kPlaceEventShortLabel,
    guestQuestion: '이 매장에서 지금 뭐 하지?',
    meaning:
        '매장이 주체가 되어 진행하는 행사·프로모션·혜택. '
        '주류 할인·1+1·생일 이벤트·공연·DJ·시음·시즌 행사 등',
    criterion: kPlaceEventCriterion,
    // 부제가 이미 '매장에서 진행하는'을 말하므로 여기서는 되풀이하지 않는다 —
    // 좁은 카드에서 한 줄이 통째로 늘어나 답답해진다(파티 카드와 높이도 어긋난다).
    registerDescription: '주류 할인·1+1·생일 이벤트 등 매장 소식과 혜택을 알려요.',
  ),

  /// 🎉 파티 — `parties` 한 건. 신청·승인·참가비가 달린 모집글이다.
  party(
    emoji: kPartyEmoji,
    label: kPartyLabel,
    shortLabel: kPartyLabel,
    guestQuestion: '내가 참가할 모임이 뭐 있지?',
    meaning: '참가자를 모집하고 신청을 받아 함께 즐기는 모임·파티',
    criterion: '참가자를 모집하거나 티켓을 판매하는 행사',
    registerDescription:
        '인원을 모집하고 참가 신청·승인을 받거나, 공연·행사 티켓을 판매할 수 있어요.',
  );

  const HostOffering({
    required this.emoji,
    required this.label,
    required this.shortLabel,
    required this.guestQuestion,
    required this.meaning,
    required this.criterion,
    required this.registerDescription,
  });

  /// 🎪 / 🎉 — 두 개념을 한 글자로 갈라 두는 표시. 좁은 배지에서는 이모지와
  /// [shortLabel]만으로 줄여도 된다('🎪 이벤트').
  final String emoji;

  /// 정식 이름 — 제목·머리말처럼 자리가 있는 곳에서 쓴다.
  final String label;

  /// 좁은 자리(격자 칸·배지)용 축약. 파티는 원래 짧아 같은 값이다.
  final String shortLabel;

  /// 게스트가 이걸 볼 때 품는 질문 — 이 한 줄이 두 개념의 차이를 가장 빨리
  /// 설명한다.
  final String guestQuestion;

  /// 한 줄 정의.
  final String meaning;

  /// 등록 선택 화면의 부제 — **판단 기준**을 그대로 적는다.
  ///
  /// 기준은 주체다(매장이 여는가 / 참가자를 모으는가). 신청을 받는지로 적으면
  /// 안 된다 — 생일 이벤트처럼 사전 신청을 받는 매장 이벤트가 갈 곳을 잃는다.
  final String criterion;

  /// 등록 선택 카드의 설명.
  final String registerDescription;

  String get display => '$emoji $label';

  /// 좁은 자리용 표기 — '🎪 이벤트'.
  String get shortDisplay => '$emoji $shortLabel';

  /// 반대쪽 개념 — 서로를 가리키는 안내 줄에서 쓴다.
  HostOffering get other =>
      this == placeEvent ? HostOffering.party : HostOffering.placeEvent;

  /// 등록 선택 화면 맨 위 — 무엇으로 고르는지 한 문장.
  ///
  /// 카드 두 장 바로 위에 붙는 줄이라, 여기서 신청 여부를 기준으로 말하면
  /// 아래 카드 문구와 어긋난다.
  static const String criterionHeadline =
      '매장이 여는 행사인지, 참가자를 모집하는 모임인지로 선택해주세요.';

  /// 등록 선택 화면의 제목.
  static const String choiceTitle = '무엇을 만들까요?';

  /// 매장 이벤트 **등록 폼** 머리말의 둘째 줄.
  ///
  /// 선택 카드의 [registerDescription]과 갈라 둔다 — 카드는 "무엇을 올리는
  /// 자리인가"(주류 할인·1+1·생일 이벤트)를 말하고, 폼에 들어온 사람에게는
  /// **어디까지 담을 수 있는가**를 말해야 한다. 신청을 받는 이벤트도 여기서
  /// 만든다는 사실이 폼 맨 위에 있어야 신청 스위치를 찾는다.
  static const String placeEventFormSubtitle =
      '자유롭게 방문하는 행사부터 사전 신청을 받는 행사까지 등록할 수 있어요.';

  /// 매장 이벤트 폼에서 **파티 쪽으로** 보내는 물음.
  ///
  /// ⚠️ "신청을 받을 예정인가요?"로 되돌리면 안 된다. 매장 이벤트도 신청을
  ///    받으므로([EventApplyMode]) 그 물음은 신청을 받는 호스트를 전부 파티로
  ///    보내 버린다. 가르는 것은 신청 여부가 아니라 **무엇이 중심인가**다.
  static const String toPartyPrompt = '참가자 모집이 중심인 모임·파티를 열 예정인가요?';

  /// 파티 진입에서 **매장 이벤트 쪽으로** 보내는 물음.
  ///
  /// 카드 부제와 **같은 한 문장**을 쓴다([kPlaceEventCriterion]) — 건너온
  /// 사람이 선택 화면에서 읽은 말과 같은 말을 다시 보게 된다.
  ///
  /// ⚠️ "신청 모집 없이"로 되돌리면 안 된다. 생일 이벤트처럼 사전 신청을 받는
  ///    매장 이벤트가 이 물음에 '아니오'가 되어 파티로 잘못 흘러간다.
  static const String toPlaceEventPrompt = '$kPlaceEventCriterion인가요?';

  /// **이쪽으로 오라고** 묻는 문장 — 목적지를 기준으로 고른다.
  /// (매장 이벤트 폼에는 `HostOffering.party.crossPrompt`가 걸린다.)
  String get crossPrompt => this == party ? toPartyPrompt : toPlaceEventPrompt;
}

/// 게스트 문의 받기 — **파티·플레이스·장소대여가 공유하는 단 하나의 기준**.
///
/// 호스트가 등록·수정 화면에서 켜고 끄는 값이고, 문서에는 세 도메인 모두
/// `inquiryEnabled: true/false`로 똑같이 저장된다. 도메인마다 필드 이름이나
/// 기본값이 갈리면 "플레이스는 꺼졌는데 파티는 켜진 것처럼 보이는" 상태가
/// 생기므로, 읽는 자리도 쓰는 자리도 이 파일 하나를 지난다.
///
/// ── 기본값이 왜 ON인가 ──────────────────────────────────────────────────
/// 필드가 아직 없는 문서(이 기능이 생기기 전에 등록된 것)는 **켜진 것으로**
/// 본다. 호스트가 끈 적이 없는데 꺼진 것으로 취급하면, 아무도 손대지 않은
/// 게시글이 조용히 "문의를 받지 않는 파티"가 되어 버린다. 등록 화면의 기본값도
/// 같은 이유로 ON이다.
///
/// ── externalLinkEnabled와는 **완전히 별개**다 ───────────────────────────
/// 문의를 끈다고 해서 외부 카카오톡·SNS·예약 링크를 대신 올릴 수 있게 되는
/// 것이 아니다. 반대로 외부 링크 권한이 열린다고 문의가 꺼지는 것도 아니다.
/// 두 값은 성격이 다르다.
///
///   · [inquiryEnabled]      — 호스트가 스스로 정하는 **운영 방식**
///   · `externalLinkEnabled` — 파티츄가 부여하는 **권한**(향후 월정액 등)
///
/// 그래서 한쪽에서 다른 쪽을 읽어 판단하는 코드를 **절대 만들지 않는다.**
/// 이 파일에도 링크 권한을 다루는 값이 없는 것이 그 약속이다 — 링크 권한이
/// 생기면 자기 파일에서 자기 기준으로 판단해야 하고, 두 값을 하나의 헬퍼로
/// 묶는 순간 "문의를 끄면 링크가 열린다" 같은 결합이 슬며시 생긴다.
class ListingInquiry {
  ListingInquiry._();

  /// 문서에 저장되는 필드 이름 — 세 도메인 공통.
  static const String field = 'inquiryEnabled';

  /// 호스트가 적어 두는 "문의 전 확인해주세요" 안내문 — 세 도메인 공통.
  ///
  /// 게스트가 문의하기를 누르면 채팅방으로 바로 가지 않고 이 글을 먼저 본다.
  /// 비어 있으면 안내를 띄우지 않고 곧장 채팅으로 보낸다 — 빈 팝업은 단계만
  /// 하나 늘릴 뿐이다.
  static const String guideField = 'inquiryGuide';

  /// 안내문 길이 상한. 바텀시트에서 스크롤 없이 읽히는 선이다 —
  /// 이보다 길어지면 '채팅 시작하기' 버튼이 접혀 정작 눌러야 할 것이 가린다.
  static const int maxGuideLength = 300;

  /// 등록 화면 기본값이자, 필드가 없는 문서의 해석값.
  static const bool defaultEnabled = true;

  /// 이 게시글이 지금 문의를 받는가.
  ///
  /// 문서 데이터를 그대로 넘긴다(파티/플레이스/장소대여 어느 쪽이든).
  /// 불리언이 아닌 값이 들어 있으면 기본값으로 되돌린다 — 판정이 흔들리는
  /// 것보다 "켜져 있다"로 일관되게 읽히는 편이 낫다.
  static bool isEnabled(Map<String, dynamic>? data) {
    final raw = data?[field];
    return raw is bool ? raw : defaultEnabled;
  }

  /// 호스트가 적어 둔 안내문. 없거나 문자열이 아니면 빈 문자열이다.
  ///
  /// 앞뒤 공백을 털고 상한으로 자른다 — 옛 문서나 다른 경로로 들어온 값이
  /// 상한보다 길어도 화면이 무너지지 않는다.
  static String guideOf(Map<String, dynamic>? data) {
    final raw = data?[guideField];
    if (raw is! String) return '';
    final trimmed = raw.trim();
    return trimmed.length <= maxGuideLength
        ? trimmed
        : trimmed.substring(0, maxGuideLength);
  }

  /// 저장할 때 쓰는 한 조각 — 세 등록 화면이 payload에 그대로 펼쳐 넣는다.
  ///
  /// 문의를 끄면 안내문은 **빈 문자열로 지운다.** 꺼 둔 채 남겨 두면 나중에
  /// 다시 켰을 때 예전 안내가 아무 예고 없이 되살아난다.
  static Map<String, dynamic> toMap(bool enabled, [String guide = '']) {
    final cleaned = enabled ? guide.trim() : '';
    return {
      field: enabled,
      guideField: cleaned.length <= maxGuideLength
          ? cleaned
          : cleaned.substring(0, maxGuideLength),
    };
  }
}

/// 문의 대상 종류 — 채팅방 열쇠(`relatedType`)와 원본 컬렉션을 함께 정한다.
///
/// 두 값을 한 곳에 묶어 두는 이유: 화면마다 손으로 적으면 문의 채팅방과 예약
/// 채팅방이 **다른 방으로 갈라진다**(방 id가 `{guest}_{relatedType}_{id}`라
/// relatedType 한 글자가 곧 다른 방이다).
///
/// 예전에는 `noun`('파티'/'플레이스'/'장소')도 함께 들고 있었다. 문의가 꺼져
/// 있을 때 "호스트가 문의 채팅을 운영하지 않는 파티입니다" 안내 박스를 띄우던
/// 시절의 값인데, 그 안내를 없애고 **자리를 비우는 쪽으로 바꾸면서**
/// ([GuestInquiryButton]) 쓰는 곳이 하나도 남지 않아 함께 뺐다. 게시글 종류
/// 이름이 필요한 자리는 연결 대상 정본(`PartyLinkTarget.noun`)을 쓴다.
enum InquiryTarget {
  party(relatedType: 'party', collection: 'parties'),
  place(relatedType: 'place', collection: 'events'),
  rental(relatedType: 'place', collection: 'places'),

  /// 이벤트·혜택 한 건(placePromotions)에 대한 문의.
  ///
  /// 플레이스(`place`)와 **일부러 다른 relatedType을 쓴다.** 한 플레이스에
  /// 이벤트가 여러 개 달리는데 같은 값을 쓰면 방 id(`{guest}_{type}_{id}`)의
  /// relatedId만 달라 방은 갈라지지만, 호스트 목록에서 "파티장소 문의"로
  /// 뭉뚱그려져 어느 이벤트 이야기인지 알 수 없다. 무엇보다 서버가
  /// relatedType으로 원본 컬렉션을 정하는데(functions/chatRooms.js의
  /// LISTING_COLLECTIONS), `place`는 events·places만 뒤지므로
  /// placePromotions 문서를 아예 찾지 못한다.
  ///
  /// ⚠️ 서버 표에 `event: ['placePromotions']`가 **배포돼 있어야** 동작한다.
  /// 배포 전에는 createChatRoom이 invalid-argument로 거부한다.
  event(relatedType: 'event', collection: 'placePromotions');

  const InquiryTarget({
    required this.relatedType,
    required this.collection,
  });

  /// [ChatService.getOrCreateRoom]에 넘기는 값.
  ///
  /// ⚠️ 컬렉션 이름과 1:1이 **아니다.** 플레이스(events)와 장소대여(places)는
  /// 둘 다 `'place'`를 쓴다 — 기존 예약·이용권 채팅이 이미 그렇게 쓰고 있고
  /// (chat_target_list_screen.dart), 여기서 새 값을 만들면 같은 게시글에
  /// "문의 방"과 "예약 방"이 따로 생겨 대화가 두 갈래로 쪼개진다.
  final String relatedType;

  /// `inquiryEnabled`가 실제로 적혀 있는 원본 문서의 컬렉션.
  ///
  /// [relatedType]만으로는 events와 places를 가를 수 없어 따로 들고 간다.
  ///
  /// 앱이 이 값을 서버로 보내지는 **않는다** — 채팅방을 만들 때 어느 컬렉션을
  /// 볼지는 서버가 relatedType으로 직접 정한다(functions/chatRooms.js의
  /// LISTING_COLLECTIONS). 여기 남겨 둔 것은 화면·테스트가 "이 대상의 원본이
  /// 어디에 있는지"를 한 곳에서 확인하기 위해서고, 서버 표와 어긋나면 안 된다.
  final String collection;
}

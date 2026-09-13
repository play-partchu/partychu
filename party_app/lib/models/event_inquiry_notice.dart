/// 이벤트 문의를 **껐을 때** 게스트에게 대신 보여줄 안내.
///
/// ── 왜 [ListingInquiry]의 inquiryGuide를 쓰지 않는가 ─────────────────────
/// 두 값은 뜻이 정반대다.
///
///   · `inquiryGuide`      — 문의를 **켠** 채로 "문의 전에 이것부터 읽어주세요".
///                            채팅으로 넘어가기 직전에 한 번 보여준다.
///   · 이 파일의 안내       — 문의를 **끈** 자리에 "대신 이렇게 하세요".
///
/// 그래서 `ListingInquiry.toMap`은 문의를 끄면 inquiryGuide를 **빈 문자열로
/// 지운다**(꺼 둔 채 남겨 두면 다시 켰을 때 옛 안내가 되살아난다). 같은 필드에
/// OFF 안내를 담으면 저장하는 순간 지워지고, 억지로 남기면 파티·플레이스·
/// 장소대여 세 도메인의 기존 동작이 함께 바뀐다.
///
/// 그래서 ON/OFF 판정은 [ListingInquiry.isEnabled] 하나를 그대로 쓰고,
/// **이 파일의 필드는 placePromotions 문서에만** 붙인다. 다른 도메인 문서는
/// 이 값을 쓰지도 저장하지도 않는다.
library;

/// 문의를 끈 이벤트가 게스트에게 보여줄 안내 방식.
///
/// 키는 Firestore에 그대로 저장되므로 **바꾸면 기존 문서가 못 읽는다.**
/// 문구(label)는 화면 표시용이라 자유롭게 다듬어도 된다.
enum EventInquiryNotice {
  visitToAsk(key: 'visit_to_ask', label: '현장 방문 시 문의 가능'),
  visitAll(key: 'visit_all', label: '현장 방문 시 모두 가능'),
  noInquiryNeeded(key: 'no_inquiry_needed', label: '별도 문의 없이 이용 가능'),

  /// 호스트가 직접 적은 문구를 쓴다 — 실제 문구는 별도 필드에 있다.
  custom(key: 'custom', label: '직접 안내 문구 입력');

  const EventInquiryNotice({required this.key, required this.label});

  /// Firestore에 저장되는 값.
  final String key;

  /// 등록 화면의 선택지에 뜨는 이름이자, [custom]이 아닐 때 게스트가 보는 문구.
  final String label;

  static EventInquiryNotice fromKey(String? key) {
    for (final n in EventInquiryNotice.values) {
      if (n.key == key) return n;
    }
    return defaultNotice;
  }

  /// 고른 적이 없는 이벤트(이 기능 이전에 등록된 것 포함)의 해석값.
  ///
  /// 가장 무난하고 사실일 확률이 높은 쪽을 고른다 — 문의를 안 받는 매장
  /// 이벤트는 대개 그냥 가면 되는 것들이다. 여기서 [custom]을 기본값으로
  /// 두면 문구가 비어 있어 안내 자리가 통째로 빈다.
  static const EventInquiryNotice defaultNotice = visitToAsk;
}

/// placePromotions 문서에 붙는 OFF 안내 필드 두 개를 읽고 쓴다.
class EventInquiryNoticeFields {
  EventInquiryNoticeFields._();

  /// 프리셋 키가 저장되는 필드.
  static const String noticeField = 'inquiryOffNotice';

  /// [EventInquiryNotice.custom]일 때 쓸 직접 입력 문구.
  static const String customTextField = 'inquiryOffNoticeText';

  /// 직접 입력 문구 길이 상한 — 상세에서 버튼 자리에 한두 줄로 앉는 길이다.
  static const int maxTextLength = 80;

  static EventInquiryNotice noticeOf(Map<String, dynamic>? data) =>
      EventInquiryNotice.fromKey(data?[noticeField] as String?);

  /// 직접 입력 문구. 없거나 문자열이 아니면 빈 문자열이고, 상한으로 자른다.
  static String customTextOf(Map<String, dynamic>? data) {
    final raw = data?[customTextField];
    if (raw is! String) return '';
    final trimmed = raw.trim();
    return trimmed.length <= maxTextLength
        ? trimmed
        : trimmed.substring(0, maxTextLength);
  }

  /// 게스트에게 실제로 보여줄 한 줄. 보여줄 것이 없으면 빈 문자열이다.
  ///
  /// [custom]인데 문구가 비어 있으면 **빈 문자열을 돌려준다** — "직접 입력"만
  /// 고르고 아무것도 안 적은 경우다. 이때 상세 화면은 안내 자리를 그냥
  /// 비운다(빈 상자를 그리지 않는다).
  static String displayTextOf(Map<String, dynamic>? data) {
    final notice = noticeOf(data);
    if (notice != EventInquiryNotice.custom) return notice.label;
    return customTextOf(data);
  }

  /// 저장 조각.
  ///
  /// 문의를 **켜면** 두 값을 지운다 — 켜 둔 채 남겨 두면 나중에 다시 껐을 때
  /// 예전 안내가 아무 예고 없이 되살아난다([ListingInquiry.toMap]이
  /// inquiryGuide에 대해 하는 것과 같은 규칙이다).
  ///
  /// 프리셋이 [custom]이 아니면 직접 입력 문구도 함께 지운다 — 프리셋을
  /// 골라 둔 이벤트에 옛 문구가 남아 있으면, 나중에 "직접 입력"으로 바꾸는
  /// 순간 적은 적 없는 글이 튀어나온다.
  static Map<String, dynamic> toMap({
    required bool inquiryEnabled,
    required EventInquiryNotice notice,
    String customText = '',
  }) {
    if (inquiryEnabled) {
      return {noticeField: null, customTextField: null};
    }
    final cleaned = notice == EventInquiryNotice.custom
        ? customText.trim()
        : '';
    return {
      noticeField: notice.key,
      customTextField: cleaned.length <= maxTextLength
          ? cleaned
          : cleaned.substring(0, maxTextLength),
    };
  }
}

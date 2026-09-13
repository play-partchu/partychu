/// 신고 사유와 신고 대상 종류.
///
/// ⚠️ 여기 문자열은 **Firestore 문서에 그대로 저장된다.** 이미 접수된 신고가
/// 들고 있는 값이므로 바꾸면 옛 신고가 라벨을 잃는다 — 추가만 한다
/// (models/feedback_request.dart의 FeedbackType과 같은 규칙).
class ReportReason {
  ReportReason._();

  static const spam = 'spam';
  static const harassment = 'harassment';
  static const sexualContent = 'sexual_content';
  static const fraud = 'fraud';
  static const impersonation = 'impersonation';
  static const illegal = 'illegal';
  static const other = 'other';

  /// 신고 화면의 선택지 순서이자 읽기용 전체 목록.
  static const List<String> all = [
    spam,
    harassment,
    sexualContent,
    fraud,
    impersonation,
    illegal,
    other,
  ];

  static String label(String reason) => switch (reason) {
    spam => '스팸 · 광고',
    harassment => '욕설 · 괴롭힘 · 혐오 표현',
    sexualContent => '음란물 · 부적절한 성적 콘텐츠',
    fraud => '사기 · 금전 피해',
    impersonation => '사칭 · 명의 도용',
    illegal => '불법 정보 · 범죄 관련',
    other => '기타',
    _ => reason,
  };

  static String hint(String reason) => switch (reason) {
    other => '어떤 점이 문제인지 알려주세요. (필수)',
    _ => '자세한 상황을 적어주시면 확인에 도움이 됩니다. (선택)',
  };

  /// '기타'는 사유만으로는 운영자가 무엇을 봐야 할지 알 수 없다 —
  /// 상세 내용을 반드시 받는다. 앱과 firestore.rules가 같은 조건을 건다.
  static bool requiresDetail(String reason) => reason == other;

  static bool isValid(String reason) => all.contains(reason);
}

/// 무엇을 신고하는가.
///
/// 값은 FavoriteType(utils/favorites_service.dart)과 같은 어휘를 쓴다 —
/// 관리자 화면에서 대상 문서를 찾아갈 때 같은 이름으로 다루기 위해서다.
class ReportTargetType {
  ReportTargetType._();

  /// 사용자 그 자체(프로필·닉네임·행위). targetId == 상대 uid.
  static const user = 'user';

  /// 사용자가 만든 콘텐츠(UGC).
  static const party = 'party';
  static const event = 'event'; // 플레이스
  static const place = 'place'; // 장소대여
  static const shop = 'shop';
  static const crew = 'crew';

  /// 채팅방 안의 대화. targetId == roomId.
  static const chatRoom = 'chatRoom';

  /// 파티 참여 후기 한 줄. targetId == partyReviews 문서 id.
  ///
  /// 관리자가 신고를 보고 지우는 자리는 firestore.rules의
  /// `partyReviews … allow delete: if isAdmin()`이다 — 호스트에게는 그 권한이
  /// 없다(불리한 후기를 치우는 경로를 만들지 않는다).
  static const partyReview = 'partyReview';

  static const List<String> all = [
    user,
    party,
    event,
    place,
    shop,
    crew,
    chatRoom,
    partyReview,
  ];

  static String label(String type) => switch (type) {
    user => '사용자',
    party => '파티',
    event => '플레이스',
    place => '장소대여',
    shop => '파티샵',
    crew => '파티크루',
    chatRoom => '채팅',
    partyReview => '참여 후기',
    _ => type,
  };

  static bool isValid(String type) => all.contains(type);
}

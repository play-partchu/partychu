// ─────────────────────────────────────────────────────────────────────────────
// 💬 파티 참여 후기 — 실제 참여를 마친 게스트가 남기는 **한 줄** 후기.
//
// 별점이 없다. 호스트 평점·후기 통계·랭킹도 없다 — 출시 전이라 "한 줄 글 하나"
// 까지만 둔다.
//
// ── 여기서 하는 판정은 '표시'뿐이다 ─────────────────────────────────────────
// 작성 자격(참여 완료 여부)과 기한은 **서버가 정한다**(functions/partyReviews.js).
// 이 파일의 [ReviewWindow]는 버튼을 보여줄지와 'D-12' 같은 문구를 고르는 데만
// 쓴다. 여기 계산이 틀려도 서버가 막으므로 자격이 새지 않는다 — 반대로 여기서
// 통과시켜도 서버가 거절하면 그 메시지를 그대로 보여준다.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';

/// 한 줄 후기 길이 — 서버 partyReviews.js의 MIN/MAX_LENGTH와 **같은 값**이어야
/// 한다. 어긋나면 앱이 통과시킨 글을 서버가 거절해 사용자가 이유를 알 수 없다.
class PartyReviewLimits {
  PartyReviewLimits._();

  static const int minLength = 5;
  static const int maxLength = 100;

  /// 작성·수정·삭제가 가능한 기간. 기준점은 **그 게스트가 참여한 회차의 종료**
  /// 시각이다(정기 파티의 마지막 회차가 아니다 — 서버와 같은 규칙).
  static const int windowDays = 14;

  /// 줄바꿈 없는 한 줄로 접는다. 서버 normalizeReviewText와 같은 규칙이라,
  /// 앱이 보여주는 글자 수와 서버가 세는 글자 수가 어긋나지 않는다.
  static String normalize(String raw) =>
      raw.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// 지금 이 글을 낼 수 있는지 — 버튼 활성화 판정.
  static bool isValid(String raw) {
    final t = normalize(raw);
    return t.length >= minLength && t.length <= maxLength;
  }
}

/// 후기를 쓸 수 있는 기간이 지금 어디쯤인지.
///
/// 화면 세 곳(게스트 허브 배지·작성 시트·파티 상세)이 같은 문구를 쓰도록
/// 판정과 표기를 여기 한 곳에 둔다.
class ReviewWindow {
  const ReviewWindow._({required this.daysLeft, required this.endsAt});

  /// 남은 일수. 0이면 오늘이 마지막 날이고, 음수면 이미 지났다.
  final int daysLeft;

  /// 기한(이 시각 **전까지**). 서버가 후기 문서에 박아 둔 값과 같은 뜻이다.
  final DateTime endsAt;

  /// 아직 쓰거나 고칠 수 있는가.
  bool get isOpen => daysLeft >= 0;

  /// 오늘이 마지막 날인가.
  bool get isLastDay => daysLeft == 0;

  /// '후기 작성 D-12' · '후기 작성 D-1' · '오늘까지 작성 가능'.
  ///
  /// D-0을 쓰지 않는다 — 마지막 날에 'D-0'은 이미 끝난 것처럼 읽힌다.
  String label({String prefix = '후기 작성'}) =>
      isLastDay ? '오늘까지 작성 가능' : '$prefix D-$daysLeft';

  /// 참여한 회차의 종료 시각으로부터 기간을 만든다.
  ///
  /// 남은 일수는 **자정 기준**으로 센다 — 시각까지 따지면 같은 날인데도
  /// 사람마다 'D-1'과 'D-2'가 갈려서 "어제는 D-2였는데 오늘도 D-2"처럼 보인다.
  static ReviewWindow? fromOccurrenceEnd(DateTime? occurrenceEnd, {DateTime? now}) {
    if (occurrenceEnd == null) return null;
    final at = now ?? DateTime.now();
    final endsAt = occurrenceEnd.add(
      const Duration(days: PartyReviewLimits.windowDays),
    );
    final today = DateTime(at.year, at.month, at.day);
    final lastDay = DateTime(endsAt.year, endsAt.month, endsAt.day);
    return ReviewWindow._(
      daysLeft: lastDay.difference(today).inDays,
      endsAt: endsAt,
    );
  }

  /// 이미 쓴 후기 문서의 기한(서버가 박아 둔 `reviewWindowEndsAt`)으로 만든다.
  /// 회차 종료를 다시 계산하지 않으므로 서버 판정과 절대 갈리지 않는다.
  static ReviewWindow? fromEndsAt(DateTime? endsAt, {DateTime? now}) {
    if (endsAt == null) return null;
    final at = now ?? DateTime.now();
    final today = DateTime(at.year, at.month, at.day);
    final lastDay = DateTime(endsAt.year, endsAt.month, endsAt.day);
    return ReviewWindow._(
      daysLeft: lastDay.difference(today).inDays,
      endsAt: endsAt,
    );
  }
}

/// 후기 한 건 — `partyReviews/{partyId}_{applicationId}`.
///
/// 파티 문서가 자동삭제(14일)로 사라져도 이 문서 하나로 목록을 그릴 수 있게,
/// 서버가 표시에 필요한 최소 스냅샷(파티명·호스트·회차 시작시각)을 함께
/// 넣어 둔다. 그래서 여기서는 파티를 다시 읽지 않는다.
class PartyReview {
  const PartyReview({
    required this.id,
    required this.partyId,
    required this.applicationId,
    required this.authorUid,
    required this.authorNickname,
    required this.text,
    this.occurrenceId,
    this.hostId = '',
    this.partyTitle = '',
    this.createdAt,
    this.updatedAt,
    this.reviewWindowEndsAt,
  });

  final String id;
  final String partyId;
  final String applicationId;

  /// 정기 파티에서 어느 회차의 참여인지. 일회성이면 null.
  final String? occurrenceId;

  final String authorUid;

  /// 공개 표시용 이름 — **닉네임 스냅샷 하나뿐**이다.
  ///
  /// 실명(users.name)은 본인확인으로 확인된 값이라 호스트에게만 나가는 정보다
  /// (functions/applicantIdentity.js). 후기는 누구나 보는 자리라 실명은 물론
  /// uid도 화면에 그리지 않는다.
  final String authorNickname;

  final String text;

  final String hostId;

  /// 파티 스냅샷 — 파티가 지워진 뒤 '내가 쓴 후기' 목록에서 쓸 이름.
  final String partyTitle;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// 서버가 계산해 박아 둔 수정·삭제 기한.
  final DateTime? reviewWindowEndsAt;

  /// 지금 이 후기를 고치거나 지울 수 있는가(작성자 본인 기준).
  bool canEditAt(DateTime now) {
    final w = ReviewWindow.fromEndsAt(reviewWindowEndsAt, now: now);
    return w != null && w.isOpen;
  }

  /// '8월 27일' — 카드 한 줄에 닉네임과 나란히 붙는다.
  String get writtenDateLabel {
    final d = createdAt;
    if (d == null) return '';
    return '${d.month}월 ${d.day}일';
  }

  static DateTime? _at(Object? v) =>
      v is Timestamp ? v.toDate().toLocal() : null;

  factory PartyReview.fromDoc(DocumentSnapshot<Object?> doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? const {};
    return PartyReview(
      id: doc.id,
      partyId: d['partyId'] as String? ?? '',
      applicationId: d['applicationId'] as String? ?? '',
      occurrenceId: d['occurrenceId'] as String?,
      authorUid: d['authorUid'] as String? ?? '',
      authorNickname: (d['authorNickname'] as String? ?? '').trim().isEmpty
          ? '참여자'
          : d['authorNickname'] as String,
      text: d['text'] as String? ?? '',
      hostId: d['hostId'] as String? ?? '',
      partyTitle: d['partyTitle'] as String? ?? '',
      createdAt: _at(d['createdAt']),
      updatedAt: _at(d['updatedAt']),
      reviewWindowEndsAt: _at(d['reviewWindowEndsAt']),
    );
  }
}

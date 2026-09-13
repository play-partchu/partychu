// ─────────────────────────────────────────────────────────────────────────────
// 매장 이벤트 **신청 한 건**의 정본.
//
// ── 왜 채팅이 아니라 문서인가 ────────────────────────────────────────────────
// 처음에는 신청하기가 이벤트 채팅방에 "[신청] … 신청합니다." 한 줄을 보내는
// 것으로 끝났다. 그러면 **신청 데이터가 어디에도 남지 않는다** — 호스트는
// 채팅 목록을 눈으로 훑어야 하고, 몇 명이 신청했는지 셀 방법이 없고, 게스트는
// 자기가 신청했는지 다시 눌러 보기 전에는 모른다. 문의와 신청이 같은 방에서
// 섞이기까지 했다.
//
// 그래서 신청은 **자기 문서**를 갖는다. 문의는 예전 그대로 채팅이다
// ([ListingInquiry]) — 둘은 이제 서로를 모른다.
//
//   문의하기 → chatRooms/{guestId}_event_{eventId}      (예전 구조 그대로)
//   신청하기 → placeEventApplications/{eventId}_{guestId}
//
// ── 이 문서는 **앱이 쓰지 않는다** ───────────────────────────────────────────
// 신청·취소는 서버 콜러블만 한다(functions/placeEventApplications.js —
// applyToPlaceEvent / cancelPlaceEventApplication)이고, firestore.rules는 이
// 컬렉션의 클라이언트 쓰기를 **전부** 막는다. 앱은 읽기만 한다.
//
// 그 이유는 종료 판정이다. "종료된 이벤트에 신청할 수 없다"는 `isAlways`·
// `endAt`을 **그 날 23:59:59**로 접는 계산이고([PlacePromotion.statusAt]),
// 이 판정을 rules로 옮겨 적으면 하루의 경계에서 앱과 어긋난다. 그렇다고 규칙에
// 넣지 않으면 변조된 클라이언트가 종료된 이벤트에 그대로 신청을 넣는다 —
// "버튼이 안 보인다"는 방어가 아니다.
//
// 그래서 이 클래스는 **읽기 모델**이다. 여기 있는 필드는 전부 서버가 쓴 값이고,
// [createMap] 같은 쓰기용 헬퍼는 없다.
//
// ── 파티 신청과 무엇이 다른가 ────────────────────────────────────────────────
// `parties/{id}/applications`에는 정원·승인·참가비·성별가·회차·결제·환불이
// 달려 있다. 매장 이벤트에는 **그 축이 하나도 없다.** 그래서 그 파이프라인을
// 옮겨 오지 않았다 — 필요한 것은 "누가 이 이벤트에 신청했는가" 하나뿐이다.
//
// 컬렉션을 파티 쪽 서브컬렉션 이름(`applications`)으로 만들지 않은 이유도
// 같다. firestore.rules에는 재귀 와일드카드 `/{path=**}/applications/{id}`
// 규칙이 있고, 서버에도 `collectionGroup('applications')`를 도는 코드가 여럿
// 있다(탈퇴 차단 accountWithdrawal.js, 매출 집계 adminSalesStats.js). 그 이름을
// 재사용하면 매장 이벤트 신청이 **파티 신청으로 세어진다** — 탈퇴가 막히고
// 매출 통계에 빈 건이 섞인다.
//
// ── 문서 id가 곧 중복 방지다 ─────────────────────────────────────────────────
// id를 `{eventId}_{guestId}`로 고정했다. 같은 사람이 같은 이벤트에 두 번
// 신청하면 **같은 문서**를 가리키므로 두 건이 될 수 없다 — 서버가 쓰는 지금도
// 재시도나 동시 호출이 두 건을 만들지 못한다.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';

/// 신청 한 건의 상태.
///
/// 승인제가 없으므로 두 개뿐이다. 호스트가 결정을 내리는 구간이 없고,
/// 게스트가 스스로 넣고 스스로 무른다.
enum PlaceEventApplicationStatus {
  /// 신청함 — 호스트의 신청자 목록·건수에 잡히는 유일한 상태.
  applied(key: 'applied', label: '신청 완료'),

  /// 게스트가 무른 신청. **문서는 지우지 않고 남긴다** — 지우면 "신청했다가
  /// 취소했다"가 사라져 호스트가 자리를 비워 둔 이유를 알 수 없다.
  cancelled(key: 'cancelled', label: '신청 취소');

  const PlaceEventApplicationStatus({required this.key, required this.label});

  /// Firestore에 그대로 저장되는 값 — 바꾸면 기존 문서를 못 읽는다.
  final String key;
  final String label;

  /// 지금 신청자 수에 포함되는가.
  bool get countsAsApplicant => this == applied;

  /// 모르는 값·빈 값은 [applied]다.
  ///
  /// 여기서만은 fail-**open**이다: 판정을 못 한 문서를 '취소'로 보면 호스트의
  /// 신청자 목록에서 실제 신청자가 조용히 사라진다. 상태를 모를 때 더 안전한
  /// 쪽은 "일단 보여준다"이다.
  static PlaceEventApplicationStatus fromKey(String? key) {
    for (final s in PlaceEventApplicationStatus.values) {
      if (s.key == key) return s;
    }
    return applied;
  }
}

/// 매장 이벤트 신청 한 건 — **읽기 모델**이다(쓰기는 서버만 한다).
class PlaceEventApplication {
  const PlaceEventApplication({
    required this.id,
    required this.eventId,
    required this.placeId,
    required this.hostId,
    required this.guestId,
    required this.status,
    this.placeCollection = 'events',
    this.eventTitle = '',
    this.placeName = '',
    this.eventIsAlways = false,
    this.eventStartAt,
    this.eventEndAt,
    this.createdAt,
    this.updatedAt,
    this.cancelledAt,
  });

  /// 문서가 사는 최상위 컬렉션.
  static const String collection = 'placeEventApplications';

  /// 문서 id — `{eventId}_{guestId}`.
  ///
  /// **이 형태가 중복 방지 그 자체다.** 서버도 같은 식으로 문서를 지목하므로
  /// (functions의 `docIdFor`), 여기를 바꾸면 서버도 함께 바꿔야 한다.
  /// (eventId는 Firestore 자동 id라 `_`를 포함하지 않는다.)
  static String docIdFor({required String eventId, required String guestId}) =>
      '${eventId}_$guestId';

  final String id;

  /// 신청 대상 이벤트 — `placePromotions/{eventId}`.
  final String eventId;

  /// 그 이벤트가 붙어 있는 장소. 호스트가 "이 가게의 신청 전부"를 한 번에
  /// 셀 수 있어야 해서 신청서에도 적어 둔다(이벤트 문서를 N번 되짚지 않게).
  final String placeId;

  /// 'events'(플레이스) 또는 'places'(장소대여·숙박).
  final String placeCollection;

  /// 이벤트의 주인. 호스트 조회의 **유일한 근거**다 — 규칙이 이 값으로 목록
  /// 쿼리를 허용한다. 그래서 클라이언트가 쓸 수 없고, 서버가 원본 이벤트에서
  /// 읽은 값만 들어간다.
  final String hostId;

  /// 신청한 사람 — 서버가 `request.auth.uid`로 적는다.
  final String guestId;

  final PlaceEventApplicationStatus status;

  // ── 원본에서 베낀 스냅샷 ────────────────────────────────────────────────
  //
  // 게스트 신청 내역이 이벤트 문서를 다시 읽지 않고도 목록을 그릴 수 있게
  // 서버가 신청 시점에 베껴 둔 값들이다(파티 신청의 `partyTitle`·
  // `partyDateTime`과 같은 취급). **전부 서버가 쓴다** — 예전처럼 앱이 제목을
  // 실어 보내면 "이벤트 제목 = 아무 문자열"로 위조할 수 있었다.

  final String eventTitle;
  final String placeName;
  final bool eventIsAlways;
  final DateTime? eventStartAt;
  final DateTime? eventEndAt;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? cancelledAt;

  bool get isApplied => status.countsAsApplicant;

  /// "8.1 ~ 8.31" 같은 기간 한 줄. 상시 진행이거나 기간이 없으면 null.
  /// 표기는 [PlacePromotion.periodLabel]과 같은 규칙이다.
  String? get periodLabel {
    if (eventIsAlways) return null;
    String d(DateTime t) => '${t.month}.${t.day}';
    final s = eventStartAt;
    final e = eventEndAt;
    if (s == null && e == null) return null;
    if (s != null && e != null) return '${d(s)} ~ ${d(e)}';
    if (e != null) return '${d(e)}까지';
    return '${d(s!)}부터';
  }

  /// 목록 한 줄에 그릴 일정 — 상시 진행이면 그 말이 곧 일정이다.
  String get scheduleLabel {
    if (eventIsAlways) return '상시 진행';
    return periodLabel ?? '';
  }

  static DateTime? _time(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    return null;
  }

  factory PlaceEventApplication.fromMap(String id, Map<String, dynamic> m) =>
      PlaceEventApplication(
        id: id,
        eventId: m['eventId'] as String? ?? '',
        placeId: m['placeId'] as String? ?? '',
        placeCollection: m['placeCollection'] as String? ?? 'events',
        hostId: m['hostId'] as String? ?? '',
        guestId: m['guestId'] as String? ?? '',
        status: PlaceEventApplicationStatus.fromKey(m['status'] as String?),
        eventTitle: m['eventTitle'] as String? ?? '',
        placeName: m['placeName'] as String? ?? '',
        eventIsAlways: m['eventIsAlways'] == true,
        eventStartAt: _time(m['eventStartAt']),
        eventEndAt: _time(m['eventEndAt']),
        createdAt: _time(m['createdAt']),
        updatedAt: _time(m['updatedAt']),
        cancelledAt: _time(m['cancelledAt']),
      );

  /// 이 목록에서 **지금 신청 중인** 건수. 취소는 세지 않는다.
  static int countApplied(Iterable<PlaceEventApplication> items) =>
      items.where((a) => a.isApplied).length;
}

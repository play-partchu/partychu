import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// 앱 알림 한 건 — 서버(Cloud Functions)가 `notifications` 컬렉션에 남긴 문서.
///
/// 지금 쌓이는 종류
/// - 파티 최소 모집 인원 미달 자동 취소 안내(functions/partyMinCapacity.js)
/// - 플레이스 방문 예약의 신청/승인/거절/취소/만료
///   (functions/placeVisitReservations.js의 pushNotification)
///
/// 알림이 어디로 이동할지는 [partyId] 또는 [placeId]/[refCollection]으로 정한다
/// (규칙은 notification_route.dart 한 곳에 있다).
///
/// 이 문서가 만들어지면 서버 트리거가 곧바로 FCM 푸시도 보낸다
/// (functions/pushDispatch.js). 그래서 알림 종류를 새로 추가할 때 발송 코드를
/// 따로 붙일 필요가 없다 — 알림함에 뜨는 것은 전부 푸시로도 나간다.
@immutable
class AppNotification {
  final String id;
  final String type;
  final String title;
  final String body;

  /// 눌렀을 때 열 파티. 없으면 이동하지 않는다.
  final String? partyId;

  /// 눌렀을 때 열 플레이스(events 문서 id) — 방문 예약 알림이 쓴다.
  final String? placeId;

  /// 알림이 가리키는 문서('placeVisitReservations' 등). 나중에 알림 종류가
  /// 늘어도 이 두 필드로 어디로 갈지 정할 수 있다.
  final String? refCollection;
  final String? refId;

  /// 'applicant' | 'host' | 'guest' — 같은 사건이라도 문구가 다르다.
  final String role;

  final bool read;
  final DateTime? createdAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.partyId,
    this.placeId,
    this.refCollection,
    this.refId,
    this.role = 'applicant',
    this.read = false,
    this.createdAt,
  });

  factory AppNotification.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data();
    final ts = d['createdAt'];
    return AppNotification(
      id: doc.id,
      type: d['type'] as String? ?? '',
      title: d['title'] as String? ?? '알림',
      body: d['body'] as String? ?? '',
      partyId: d['partyId'] as String?,
      placeId: d['placeId'] as String?,
      refCollection: d['refCollection'] as String?,
      refId: d['refId'] as String?,
      role: d['role'] as String? ?? 'applicant',
      read: d['read'] as bool? ?? false,
      createdAt: ts is Timestamp ? ts.toDate().toLocal() : null,
    );
  }
}

/// 알림함이 읽고 쓰는 곳. 서버가 문서를 만들고, 앱은 읽기와 읽음 표시만 한다
/// (Firestore 규칙도 그렇게 열려 있다 — create는 서버 전용).
class NotificationService {
  NotificationService._();

  static final _db = FirebaseFirestore.instance;

  static Query<Map<String, dynamic>> _query(String uid) => _db
      .collection('notifications')
      .where('uid', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(100);

  /// 내 알림 목록(최신순).
  static Stream<List<AppNotification>> watch(String uid) {
    if (uid.isEmpty) return Stream.value(const []);
    return _query(
      uid,
    ).snapshots().map((s) => s.docs.map(AppNotification.fromDoc).toList());
  }

  /// 안 읽은 개수 — 하단 탭/마이페이지의 빨간 점에 쓴다.
  static Stream<int> watchUnreadCount(String uid) {
    if (uid.isEmpty) return Stream.value(0);
    return _db
        .collection('notifications')
        .where('uid', isEqualTo: uid)
        .where('read', isEqualTo: false)
        .snapshots()
        .map((s) => s.docs.length);
  }

  /// 알림 한 건을 읽음으로.
  ///
  /// 부르는 곳은 셋이고 전부 **사용자가 실제로 그 소식을 연 순간**이다:
  /// 알림함에서 카드를 눌렀을 때, 그 카드의 CTA를 눌렀을 때, 푸시를 눌러
  /// 들어왔을 때(push_notification_service). 화면을 열었다는 이유만으로는
  /// 부르지 않는다 — 그러면 안 읽은 알림이라는 상태 자체가 사용자 눈에
  /// 보이지 않게 된다.
  ///
  /// Firestore가 쓰기를 로컬에 먼저 반영하므로, 목록을 보고 있는 스트림은
  /// 서버 응답을 기다리지 않고 그 자리에서 '읽음'으로 다시 그려진다. 쓰기가
  /// 끝내 실패하면 되돌려지므로 화면도 저절로 '안 읽음'으로 돌아온다.
  ///
  /// 규칙은 본인 문서의 `read` 필드 하나만 바꾸도록 열려 있다(firestore.rules).
  static Future<void> markRead(String id) =>
      _db.collection('notifications').doc(id).update({'read': true});

  /// 안 읽은 알림을 한 번에 읽음으로 — 알림함 앱바의 '모두 읽음'이 부른다.
  ///
  /// ⚠️ 화면 진입(initState)에서 부르지 않는다. 예전에는 그렇게 했는데, 목록이
  /// 그려지기도 전에 전부 읽음이 되어 강조·읽음 표시·종 배지가 모두 뜻을
  /// 잃었다. 지금은 사용자가 이 버튼을 눌렀을 때만 실행된다.
  static Future<void> markAllRead(String uid) async {
    if (uid.isEmpty) return;
    final snap = await _db
        .collection('notifications')
        .where('uid', isEqualTo: uid)
        .where('read', isEqualTo: false)
        .limit(300)
        .get();
    if (snap.docs.isEmpty) return;
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }

  static Future<void> delete(String id) =>
      _db.collection('notifications').doc(id).delete();
}

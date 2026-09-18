import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/admin_notification.dart';

/// 관리자 업무 알림을 읽고 읽음 표시하는 곳.
///
/// 서버가 문서를 만들고(functions/adminNotifications.js), 관리자 앱은 **읽기와
/// 읽음 표시만** 한다 — Firestore 규칙도 그렇게 열려 있다(create·delete는
/// 아예 막혀 있고, update는 `readBy`에 자기 uid를 넣는 것만 허용).
///
/// 읽음 표시를 콜러블이 아니라 Firestore 직접 쓰기로 하는 이유: 사용자 알림
/// (party_app의 NotificationService)과 같다 — Firestore가 쓰기를 로컬에 먼저
/// 반영하므로 배지가 그 자리에서 내려가고, 실패하면 저절로 되돌아온다.
/// 콜러블을 거치면 콜드 스타트 때문에 1~2초 멈칫한다.
class AdminNotificationService {
  AdminNotificationService._();

  static final _db = FirebaseFirestore.instance;

  static const _collection = 'adminNotifications';

  /// 종 목록에 띄우는 최근 개수.
  static const recentLimit = 20;

  /// 전체 알림 화면이 한 번에 받는 개수.
  static const allLimit = 200;

  /// 위젯 테스트에서만 채운다 — 로그인한 관리자를 흉내 내기 위한 것이고,
  /// 운영에서는 항상 null이라 [FirebaseAuth]를 그대로 본다.
  @visibleForTesting
  static String? debugUidOverride;

  /// 지금 로그인한 관리자 uid. 로그아웃 상태면 빈 문자열.
  static String get currentUid =>
      debugUidOverride ?? FirebaseAuth.instance.currentUser?.uid ?? '';

  /// 최신순 알림 스트림.
  ///
  /// 안 읽음 개수를 **서버에서 세지 않는다.** `readBy` 배열에 내 uid가
  /// 없는 것을 세야 하는데 Firestore는 배열 부정 조건을 지원하지 않는다.
  /// 알림이 주당 몇 건 수준이라 최근 [limit]건을 받아 화면에서 세는 쪽이
  /// 훨씬 싸고 단순하다. 물량이 크게 늘면 집계 필드로 옮겨야 한다.
  static Stream<List<AdminNotification>> watch({int limit = recentLimit}) {
    return _db
        .collection(_collection)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(AdminNotification.fromDoc).toList());
  }

  /// 안 읽은 개수 — 종 아이콘의 숫자 배지.
  static Stream<int> watchUnreadCount({int limit = allLimit}) {
    final uid = currentUid;
    return watch(limit: limit)
        .map((list) => list.where((n) => !n.isReadBy(uid)).length);
  }

  /// 알림 한 건을 읽음으로.
  ///
  /// `arrayUnion`이라 같은 uid를 두 번 넣어도 배열이 자라지 않고, 다른
  /// 관리자의 uid는 손대지 않는다(규칙도 그것만 허용한다).
  static Future<void> markRead(String id) {
    final uid = currentUid;
    if (uid.isEmpty) return Future.value();
    return _db.collection(_collection).doc(id).update({
      'readBy': FieldValue.arrayUnion([uid]),
    });
  }

  /// 안 읽은 알림을 한 번에 읽음으로 — '모두 읽음'이 부른다.
  ///
  /// ⚠️ 화면을 열었다는 이유로 부르지 않는다. 목록이 그려지기도 전에 전부
  /// 읽음이 되면 무엇이 새 소식이었는지 알 수 없게 된다(사용자 앱 알림함이
  /// 같은 이유로 진입 시 자동 읽음을 없앴다).
  static Future<void> markAllRead(List<AdminNotification> shown) async {
    final uid = currentUid;
    if (uid.isEmpty) return;
    final unread = shown.where((n) => !n.isReadBy(uid)).toList();
    if (unread.isEmpty) return;

    final batch = _db.batch();
    for (final n in unread) {
      batch.update(_db.collection(_collection).doc(n.id), {
        'readBy': FieldValue.arrayUnion([uid]),
      });
    }
    await batch.commit();
  }
}

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/utils/user_session.dart';

/// 사용자 차단 — Firestore `userBlocks` 컬렉션.
///
/// ── 왜 이 모양인가 ───────────────────────────────────────────────────────
/// 문서 id를 `"{차단한사람}_{차단당한사람}"`으로 **고정한다.** favorites와
/// 완전히 같은 이유다(utils/favorites_service.dart 참고).
///
///   · 같은 사람을 두 번 차단하는 문서가 구조적으로 생길 수 없다.
///   · 규칙이 **문서 id만 보고** 판단할 수 있다. 아직 없는 문서를 get()하면
///     규칙 안에서 resource가 null이라 `resource.data.blockerId`를 보는 조건은
///     평가 자체가 실패한다(= 항상 PERMISSION_DENIED). id가 내 uid로 시작하면
///     그 함정을 통째로 피한다.
///   · 별도의 색인도, 마이그레이션도 필요 없다. 기존 사용자 문서를 한 글자도
///     건드리지 않는다.
///
/// ── 차단은 한 방향이다 ───────────────────────────────────────────────────
/// A가 B를 차단해도 B의 문서에는 아무것도 쓰지 않는다. **상대는 자기가
/// 차단당했는지 알 수 없어야 하고**, 알림도 가지 않는다. 그래서 이 컬렉션의
/// 읽기 권한은 "차단한 본인과 관리자"뿐이다(firestore.rules).
///
/// 다만 **효과는 양방향**이다 — 새 1:1 채팅은 어느 쪽에서 시도하든 열리지
/// 않는다. 그 판정은 앱이 아니라 서버가 한다(functions/chatRooms.js의
/// createChatRoom). 앱이 하는 판정은 앱을 고치면 사라지기 때문이다.
///
/// ── 신고와는 별개다 ──────────────────────────────────────────────────────
/// 차단은 **내 화면에서 안 보이게 하는 것**이고, 신고는 **운영자에게 알리는
/// 것**이다. 차단해도 신고되지 않고, 신고해도 차단되지 않는다
/// (services/report_service.dart).
class BlockService {
  BlockService._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('userBlocks');

  static String docIdFor(String blockerId, String blockedId) =>
      '${blockerId}_$blockedId';

  /// 지금 로그인한 사람이 차단한 uid 전부.
  ///
  /// 목록 화면들이 **동기적으로** 물어볼 수 있어야 해서 메모리에 들고 있다
  /// (카드 한 장 그릴 때마다 Firestore를 읽을 수는 없다). 로그인 전이거나
  /// 아직 못 읽었으면 빈 집합이라, 차단 기능이 목록을 잘못 비우는 일은 없다
  /// — 모르면 **보여준다**(fail-open). 진짜 차단은 서버가 건다.
  static final ValueNotifier<Set<String>> blockedIds =
      ValueNotifier<Set<String>>(<String>{});

  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  static StreamSubscription<User?>? _authSub;
  static String _watchingUid = '';

  /// 앱 시작 시 **한 번** 부른다(main.dart). 로그인/로그아웃을 따라다니며
  /// 차단 목록 구독을 갈아 끼운다 — 로그인 경로(구글·카카오·네이버·세션
  /// 복원)마다 따로 부를 필요가 없다.
  static void attach() {
    _authSub ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      _watch(user?.uid ?? '');
    });
  }

  static void _watch(String uid) {
    if (uid == _watchingUid) return;
    _watchingUid = uid;
    _sub?.cancel();
    _sub = null;
    if (uid.isEmpty) {
      blockedIds.value = <String>{};
      return;
    }
    _sub = _col
        .where('blockerId', isEqualTo: uid)
        .snapshots()
        .listen(
          (snap) {
            blockedIds.value = snap.docs
                .map((d) => d.data()['blockedId'] as String? ?? '')
                .where((s) => s.isNotEmpty)
                .toSet();
          },
          onError: (Object e, StackTrace s) {
            // 못 읽으면 차단이 화면에 반영되지 않을 뿐, 목록·채팅은 그대로
            // 돌아야 한다. 여기서 빈 집합으로 되돌리지도 않는다 — 직전까지
            // 읽어둔 값이 아무것도 없는 것보다 낫다.
            logFirestoreStreamError('BlockService.watch', e, s);
          },
        );
  }

  /// 목록·카드가 부르는 동기 판정.
  static bool isBlocked(String? uid) =>
      uid != null && uid.isNotEmpty && blockedIds.value.contains(uid);

  /// 차단 여부를 서버에서 직접 확인한다(메뉴를 열 때처럼 정확해야 하는 자리).
  static Future<bool> isBlockedFromServer(String targetUid) async {
    final me = UserSession.userId;
    if (me.isEmpty || targetUid.isEmpty) return false;
    try {
      final snap = await _col.doc(docIdFor(me, targetUid)).get();
      return snap.exists;
    } catch (e, st) {
      logFirestoreStreamError('BlockService.isBlockedFromServer', e, st);
      return isBlocked(targetUid); // 못 읽으면 메모리 값으로 답한다
    }
  }

  /// 차단 목록 화면이 구독하는 스트림.
  static Stream<QuerySnapshot<Map<String, dynamic>>> watchMyBlocks() {
    final me = UserSession.userId;
    if (me.isEmpty) return const Stream.empty();
    return _col
        .where('blockerId', isEqualTo: me)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// 차단하기. 이미 차단돼 있으면 아무 일도 하지 않는다(재실행 안전).
  ///
  /// **상대에게는 아무 신호도 가지 않는다** — 상대 문서에 쓰지 않고, 푸시도
  /// 보내지 않는다.
  static Future<void> block(String targetUid, {String? targetName}) async {
    final me = UserSession.userId;
    if (me.isEmpty) throw StateError('로그인이 필요합니다');
    if (targetUid.isEmpty) throw ArgumentError('대상이 비어 있습니다');
    // 본인 차단은 만들 수 없다. 규칙에서도 한 번 더 막는다(firestore.rules).
    if (targetUid == me) throw ArgumentError('자기 자신은 차단할 수 없습니다');

    await _col.doc(docIdFor(me, targetUid)).set({
      'blockerId': me,
      'blockedId': targetUid,
      // 목록에 이름을 보여주려는 표시용 값. 판정에는 쓰지 않는다(상대가
      // 닉네임을 바꾸면 옛 이름이 남을 수 있고, 그래도 차단은 uid로 걸린다).
      'blockedName': targetName ?? '',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// 차단 해제.
  static Future<void> unblock(String targetUid) async {
    final me = UserSession.userId;
    if (me.isEmpty) throw StateError('로그인이 필요합니다');
    if (targetUid.isEmpty) return;
    await _col.doc(docIdFor(me, targetUid)).delete();
  }

  /// 목록에서 차단한 사람의 글을 빼는 공용 필터.
  ///
  /// [ownerFields]를 여러 개 받는 이유: 컬렉션마다 작성자 필드 이름이 다르다
  /// (parties/places는 `hostId`, 일부 문서는 `hostUid`·`ownerId`). 하나라도
  /// 차단 대상이면 뺀다.
  static List<T> withoutBlocked<T extends DocumentSnapshot>(
    List<T> docs, {
    List<String> ownerFields = const ['hostId', 'hostUid', 'ownerId', 'userId'],
  }) {
    if (blockedIds.value.isEmpty) return docs;
    return docs.where((doc) {
      final data = doc.data();
      if (data is! Map<String, dynamic>) return true;
      for (final f in ownerFields) {
        if (isBlocked(data[f] as String?)) return false;
      }
      return true;
    }).toList();
  }

  /// 문서 하나가 차단한 사람의 글인지 — [withoutBlocked]와 같은 판정을
  /// 맵 하나에 대해 쓰는 형태(ListingSources의 노출 판정이 쓴다).
  static bool isBlockedOwner(
    Map<String, dynamic> data, {
    List<String> ownerFields = const ['hostId', 'hostUid', 'ownerId', 'userId'],
  }) {
    if (blockedIds.value.isEmpty) return false;
    for (final f in ownerFields) {
      if (isBlocked(data[f] as String?)) return true;
    }
    return false;
  }

  /// 테스트에서 상태를 직접 세우기 위한 자리 — 실제 앱 경로에서는 쓰지 않는다.
  @visibleForTesting
  static void setBlockedIdsForTest(Set<String> ids) {
    blockedIds.value = ids;
  }
}

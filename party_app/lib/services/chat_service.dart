import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

// 방 문서의 `origin`('inquiry' | 'booking')은 **서버가 적는다.**
// 무엇이 그 방을 열어 줬는지에 대한 판정 결과이므로 앱에는 그 값을 만드는
// 자리가 없다 — 앱이 적을 수 있으면 그건 판정이 아니라 신고다
// (functions/chatRooms.js 상단 주석 참고).

class ChatService {
  static final _db = FirebaseFirestore.instance;

  static FirebaseFunctions get _fn =>
      FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  /// 같은 (호스트, 게스트, 대상)이면 **언제나 같은 문서 하나**를 쓰기 위한 id.
  ///
  /// 예전에는 방을 찾을 때 `participants array-contains` + `hostId ==` +
  /// `relatedId ==` 3중 쿼리를 돌렸다. 이 조합은 복합 색인이 필요한데
  /// chatRooms에는 그 색인이 없어서(firestore.indexes.json) 조회가 실패했고,
  /// 실패하면 "기존 방이 없다"로 읽혀 누를 때마다 새 방이 생겼다. 문서 id를
  /// 값에서 직접 만들면 색인도, 조회 실패도, 연타 경합도 전부 사라진다 —
  /// 두 번 눌러도 같은 문서를 가리키므로 중복 방이 **구조적으로** 못 생긴다.
  ///
  /// **guestId를 맨 앞에 둔다** — favorites와 같은 이유다. 아직 없는 문서를
  /// get()하면 규칙 안에서 resource가 null이라 `resource.data.participants`를
  /// 보는 조건은 평가 자체가 실패한다(= 항상 PERMISSION_DENIED). 그래서
  /// 규칙이 **문서 id만 보고** 판단할 수 있어야 하고, 그러려면 id가 내 uid로
  /// 시작해야 한다(firestore.rules chatRooms get 규칙 참고).
  static String roomIdFor({
    required String relatedType,
    required String relatedId,
    required String guestId,
  }) => '${guestId}_${relatedType}_$relatedId';

  // ── 채팅방 생성 또는 기존 채팅방 반환 ──────────────────────────────
  //
  // 만드는 일은 **서버가 한다**(functions/chatRooms.js의 createChatRoom).
  // 앱은 "어느 글에 말을 걸고 싶다"만 말하고, 열어도 되는지는 서버가 정한다.
  //
  //   · 이미 예약·신청·주문한 사이인가 → 서버가 기록을 직접 찾는다
  //   · 아니면 호스트가 문의를 열어 뒀는가 → 원본 글의 inquiryEnabled
  //
  // 앱에서 판정하지 않는 이유는 간단하다 — 앱이 하는 판정은 앱을 고치면
  // 사라진다. 예전에는 이 함수가 방 문서를 직접 만들면서 "문의인지 예약인지"를
  // 스스로 적었고, 그 값을 손으로 바꾸면 문의 OFF가 통째로 무력해졌다.
  //
  // hostId·hostName도 이제 표시용 힌트일 뿐이다. 서버가 원본 글에서 다시
  // 읽으므로, 여기 무엇을 넣든 남의 이름이 걸린 방은 만들어지지 않는다.
  static Future<String> getOrCreateRoom({
    required String hostId,
    required String hostName,
    required String guestId,
    required String guestName,
    required String relatedType, // 'party' | 'shop' | 'place' | 'crew'
    required String relatedId,
    required String relatedTitle,
    String? deliveryMethod,
    DateTime? appointmentAt,
  }) async {
    // 이미 있는 방이면 콜러블까지 가지 않는다 — 대화를 다시 여는 흔한 경로가
    // 네트워크 왕복 하나로 끝난다. 방이 없으면(또는 규칙이 없는 문서 읽기를
    // 막으면) 조용히 아래로 내려간다.
    final deterministicId = roomIdFor(
      relatedType: relatedType,
      relatedId: relatedId,
      guestId: guestId,
    );
    try {
      final byId = await _db.collection('chatRooms').doc(deterministicId).get();
      if (byId.exists) return byId.id;
    } catch (_) {
      // 없는 문서이거나 규칙 미갱신 — 어느 쪽이든 "기존 방 없음"으로 본다.
    }

    // 옛 임의 id 방 찾기도 서버가 함께 처리한다(색인이 없어 앱에서는 종종
    // 실패하던 쿼리다 — 실패하면 새 방이 생겨 대화가 둘로 갈라졌다).
    final result = await _fn
        .httpsCallable('createChatRoom')
        .call<Map<String, dynamic>>({
          'relatedType': relatedType,
          'relatedId': relatedId,
          'relatedTitle': relatedTitle,
          'guestName': guestName,
          // 원본 글에 hostName이 없을 때만 쓰이는 폴백이다.
          'hostName': hostName,
          'deliveryMethod': deliveryMethod,
          'appointmentAtMs': appointmentAt?.millisecondsSinceEpoch,
        });
    final roomId = result.data['roomId'] as String?;
    if (roomId == null || roomId.isEmpty) {
      throw StateError('채팅방 id를 받지 못했습니다.');
    }
    return roomId;
  }

  // ── 메시지 전송 ──────────────────────────────────────────────────
  //
  // 여기는 **사람이 직접 친 말**만 지나간다. senderId는 언제나 보내는 본인의
  // uid여야 하고, 규칙이 그것을 못 박는다(firestore.rules의 messages create).
  // 호스트 이름으로 나가는 자동 안내는 이 경로를 쓰지 않는다 — 서버에서만
  // 만들어진다(chatAutoMessages.js).
  static Future<void> sendMessage({
    required String roomId,
    required String senderId,
    required String senderName,
    required String text,
  }) async {
    final batch = _db.batch();

    final msgRef = _db
        .collection('chatRooms')
        .doc(roomId)
        .collection('messages')
        .doc();
    batch.set(msgRef, {
      'senderId': senderId,
      'senderName': senderName,
      'text': text,
      'isAuto': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final roomRef = _db.collection('chatRooms').doc(roomId);
    batch.update(roomRef, {
      'lastMessage': text,
      'lastMessageAt': FieldValue.serverTimestamp(),
      // 마지막으로 말한 사람 — 안 읽음 판정의 절반이다([isRoomUnread]).
      // **내가 보낸 메시지가 내 배지를 켜지 않는다**는 성질을 쓰기 성공 여부가
      // 아니라 구조로 보장하려고 여기 남긴다(읽음 표시 쓰기가 실패해도 내
      // 메시지는 영원히 unread가 되지 않는다).
      'lastSenderId': senderId,
    });

    await batch.commit();
  }

  /// 지워진 말이 있던 자리에 보여줄 문구. 대화 화면과 목록 미리보기가 **같은
  /// 문구**를 쓴다 — 한쪽만 바뀌면 목록에는 원문이, 대화에는 안내가 남는다.
  static const deletedMessageText = '삭제된 메시지입니다.';

  // ── 내가 보낸 메시지 삭제 (soft delete) ─────────────────────────
  //
  // 문서는 남기고 **원문만 지운다.** 화면에서 가리는 방식으로는 이미 문서를
  // 받아 간 상대 기기도, 관리자 화면도 막지 못한다 — 가림은 숨김이지 삭제가
  // 아니다. text를 빈 문자열로 덮고 deletedAt/deletedBy만 남기면 "있었다가
  // 지워졌다"는 기록은 그대로면서 원문은 어디에서도 읽히지 않는다.
  //
  // 남의 말을 지우는 경로는 **규칙이** 막는다(messages update의
  // resource.data.senderId == uid()). 그러니 여기서 messageId를 바꿔치기해도
  // 통하지 않는다 — 화면이 내 말풍선에만 메뉴를 띄우는 것은 편의일 뿐이다.
  static Future<void> deleteMessage({
    required String roomId,
    required String messageId,
    required String uid,
    bool isLastMessage = false,
  }) async {
    final roomRef = _db.collection('chatRooms').doc(roomId);
    final batch = _db.batch();

    batch.update(roomRef.collection('messages').doc(messageId), {
      'text': '',
      'deletedAt': FieldValue.serverTimestamp(),
      'deletedBy': uid,
    });

    // 지운 말이 마지막 말이면 목록 미리보기에 원문이 그대로 남는다. 미리보기
    // 하나만 바꾸고 lastMessageAt·lastSenderId는 건드리지 않는다 — 대화 순서와
    // 안 읽음 판정이 삭제 때문에 흔들리면 안 된다.
    if (isLastMessage) {
      batch.update(roomRef, {'lastMessage': deletedMessageText});
    }

    await batch.commit();
  }

  /// 지워진 말인가 — 원문 자리에 안내 문구를 그릴지 정한다.
  static bool isMessageDeleted(Map<String, dynamic> msg) =>
      msg['deletedAt'] != null;

  // ── 자동 안내 예약 (서버 전용) ──────────────────────────────────
  //
  // 예전에는 앱이 pendingAutoMessages 문서를 직접 만들고, 채팅방에 들어갈 때
  // **호스트의 uid를 senderId로 박아** 메시지를 대신 썼다. 그래서 규칙이
  // senderId를 uid()로 못 박지 못했고, 참가자끼리 서로를 사칭할 수 있었다.
  //
  // 이제 앱은 roomId만 넘긴다. 보내는 사람도, 문구 원문도, 발송 시각도 전부
  // 서버가 방 문서와 원본 글에서 되짚어 정한다(functions/chatAutoMessages.js).
  // pendingAutoMessages는 서버 전용 컬렉션이라 앱에서 읽지도 쓰지도 못한다.
  //
  // [productId]·[deliveryMethod]·[appointmentAt]은 파티샵처럼 같은 방에서
  // 주문마다 안내가 갈리는 경우에만 필요하다 — "어느 상품의 어느 수령 방법"인지
  // 고르는 값일 뿐, 누구 이름으로 나갈지에는 영향을 주지 않는다.
  static Future<void> scheduleAutoMessage({
    required String roomId,
    String? productId,
    String? deliveryMethod,
    DateTime? appointmentAt,
  }) async {
    await _fn.httpsCallable('scheduleChatAutoMessage').call<void>({
      'roomId': roomId,
      'productId': productId,
      'deliveryMethod': deliveryMethod,
      'appointmentAtMs': appointmentAt?.millisecondsSinceEpoch,
    });
  }

  // ── 자동 안내 발송 (채팅방 입장 시 체크) ────────────────────────
  // 발송 시각이 지난 예약을 서버가 호스트 이름으로 내보낸다. 실제 쓰기는 전부
  // 서버에서 일어나고, 앱은 방을 열었다는 신호만 준다.
  static Future<void> flushPendingAutoMessages(String roomId) async {
    await _fn.httpsCallable('flushChatAutoMessages').call<void>({
      'roomId': roomId,
    });
  }

  // ── 채팅방 실시간 스트림 ─────────────────────────────────────────
  static Stream<QuerySnapshot> messagesStream(String roomId) => _db
      .collection('chatRooms')
      .doc(roomId)
      .collection('messages')
      .orderBy('createdAt', descending: false)
      .snapshots();

  /// 방 문서 하나를 지켜본다 — 대화 화면이 "여기까지 읽었다"를 갱신할 시점을
  /// 알기 위해 쓴다. 메시지 목록과 따로 구독하는 이유는, 판정에 필요한 값
  /// (lastMessageAt·lastSenderId·lastReadAt)이 전부 **방 문서**에 있어서다 —
  /// 메시지를 세지 않으므로 대화가 길어져도 비용이 늘지 않는다.
  static Stream<DocumentSnapshot<Map<String, dynamic>>> roomStream(
    String roomId,
  ) => _db.collection('chatRooms').doc(roomId).snapshots();

  // ── 안 읽음 ──────────────────────────────────────────────────────
  //
  // chatRooms에는 원래 읽음 상태가 **아예 없었다**(adminChatViewer.js 주석
  // 참고). 알림함의 정본(notifications.read)은 채팅에 쓸 수 없다 — 채팅은
  // 알림 문서를 만들지 않기 때문이다(메시지마다 문서를 남기면 알림함이 대화로
  // 뒤덮인다, pushDispatch.js 참고).
  //
  // 그래서 방 문서에 두 필드를 얹는다.
  //
  //   · lastSenderId          — 마지막으로 말한 사람(메시지를 보낼 때 함께 적는다)
  //   · lastReadAt: {uid: ts} — 참가자별로 **자기 칸만** 적는 읽음 시각
  //
  // 메시지를 전수 조회하지 않는다. 배지는 채팅 목록이 이미 구독하는
  // participants array-contains 스트림 하나에서 그대로 나온다 — 방이 몇 개든
  // 쿼리는 하나이고, 하위컬렉션은 건드리지 않는다.

  /// 이 방을 **여기까지 읽었다**고 표시한다 — 내 칸(lastReadAt.{uid})만 쓴다.
  ///
  /// 다른 방의 안 읽음은 이 쓰기와 무관하게 그대로 남는다(방마다 자기 칸).
  static Future<void> markRoomRead(String roomId, String uid) {
    if (roomId.isEmpty || uid.isEmpty) return Future.value();
    return _db.collection('chatRooms').doc(roomId).update({
      'lastReadAt.$uid': FieldValue.serverTimestamp(),
    });
  }

  /// 이 방에 **내가 아직 안 읽은 상대 메시지**가 있는가.
  ///
  /// 호스트인지 게스트인지 보지 않는다 — participants 안의 누구에게나 같은
  /// 판정이라 문의·예약 채팅이 따로 놀지 않는다.
  static bool isRoomUnread(Map<String, dynamic> room, String uid) {
    if (uid.isEmpty) return false;
    // 내가 마지막으로 말했다면 안 읽은 것이 없다.
    if ((room['lastSenderId'] as String? ?? '') == uid) return false;
    // 방만 열리고 아직 아무 말도 오가지 않은 상태 — 알릴 것이 없다.
    if ((room['lastMessage'] as String? ?? '').trim().isEmpty) return false;
    final lastAt = room['lastMessageAt'] as Timestamp?;
    if (lastAt == null) return false;
    final read =
        (room['lastReadAt'] as Map<String, dynamic>?)?[uid] as Timestamp?;
    // 한 번도 열어보지 않은 방은 안 읽은 것으로 본다 — 모르면 "없다"가 아니라
    // "있다" 쪽으로 기운다(알림 종과 같은 태도).
    if (read == null) return true;
    return lastAt.compareTo(read) > 0;
  }

  // ── 채팅방 삭제 (사용자별 soft delete) ──────────────────────────
  //
  // 방 문서도 메시지도 지우지 않는다. `deletedAt: {uid: ts}`에 **내 칸만**
  // 적고, 목록이 그 표시를 보고 내 화면에서만 감춘다. 남의 칸을 적는 길은
  // 규칙이 막는다(lastReadAt과 같은 자리, 같은 이유 — firestore.rules).
  //
  //   · 상대의 목록은 그대로다. 내 칸만 적었기 때문이다.
  //   · 관리자 채팅 관리에는 방도 메시지도 그대로 남는다 — 그쪽은 Admin SDK로
  //     문서를 직접 읽고, 이 표시를 보지 않는다(adminChatViewer.js).
  //   · **상대가 다시 말을 걸면 방이 되살아난다.** 흔한 메신저와 같은 동작이고,
  //     판정은 아래 [isRoomDeletedFor] 한 곳에만 있다.
  static Future<void> deleteRoomForMe(String roomId, String uid) {
    if (roomId.isEmpty || uid.isEmpty) return Future.value();
    return _db.collection('chatRooms').doc(roomId).update({
      'deletedAt.$uid': FieldValue.serverTimestamp(),
    });
  }

  /// 이 방이 **내 목록에서** 지워진 상태인가.
  ///
  /// 삭제한 뒤에 온 말이 하나라도 있으면 false — 방이 다시 나타난다. 삭제
  /// 시각과 같은 시각의 메시지는 삭제 전으로 본다(<=).
  static bool isRoomDeletedFor(Map<String, dynamic> room, String uid) {
    if (uid.isEmpty) return false;
    final deleted = (room['deletedAt'] as Map<String, dynamic>?)?[uid];
    // 서버 타임스탬프가 아직 반영되지 않은 순간에는 null이 올 수 있다 —
    // 그때는 '아직 안 지운 방'으로 두고 다음 스냅샷에서 사라지게 한다.
    if (deleted is! Timestamp) return false;
    final lastAt = room['lastMessageAt'] as Timestamp?;
    if (lastAt == null) return true;
    return lastAt.compareTo(deleted) <= 0;
  }

  /// 안 읽은 **대화방 수** — 하단 채팅 탭 배지.
  ///
  /// 로그아웃 직후 uid가 비면 0을 돌려준다 — 이전 계정의 숫자가 남지 않는다.
  static Stream<int> unreadRoomCountStream(String uid) {
    if (uid.isEmpty) return Stream.value(0);
    return roomsStream(
      uid,
    ).map((docs) => docs.where((d) => isRoomUnread(d.data(), uid)).length);
  }

  /// 내 채팅방 목록 — 최근 대화순.
  ///
  /// ⚠️ orderBy('lastMessageAt')를 서버에 맡기면 `participants array-contains`와
  /// 함께 복합 색인이 필요한데, chatRooms에는 그 색인이 없다
  /// (firestore.indexes.json). 색인을 새로 배포하는 대신 정렬을 클라이언트로
  /// 옮겨 색인 자체를 필요 없게 만든다 — 내 장소·파티크루 목록과 같은 패턴이고,
  /// 한 사람의 채팅방 수는 많아야 수십 개라 이걸로 충분하다.
  ///
  /// 정렬만 여기서 하고 필터(participants array-contains)는 그대로 서버에 남긴다 —
  /// 그게 규칙이 통과를 허용하는 근거이기도 하다(firestore.rules chatRooms 참고).
  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> roomsStream(
    String userId,
  ) => userId.isEmpty
      ? Stream.value(const [])
      : _db
            .collection('chatRooms')
            .where('participants', arrayContains: userId)
            .snapshots()
            .map((snap) {
              // 내가 지운 방은 여기서 걸러낸다. 목록도 하단 탭 배지도
              // (unreadRoomCountStream) 이 스트림 하나를 보므로, 거르는 자리가
              // 하나면 숫자와 목록이 어긋날 수 없다.
              final docs = snap.docs
                  .where((d) => !isRoomDeletedFor(d.data(), userId))
                  .toList();
              docs.sort((a, b) {
                final at = a.data()['lastMessageAt'] as Timestamp?;
                final bt = b.data()['lastMessageAt'] as Timestamp?;
                if (at == null && bt == null) return 0;
                if (at == null) return 1;
                if (bt == null) return -1;
                return bt.compareTo(at);
              });
              return docs;
            });
}

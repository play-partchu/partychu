import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class ChatService {
  static final _db = FirebaseFirestore.instance;

  static FirebaseFunctions get _fn =>
      FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  // ── 채팅방 생성 또는 기존 채팅방 반환 ──────────────────────────────
  // 동일한 (hostId, guestId, relatedType, relatedId) 조합이면 재사용
  static Future<String> getOrCreateRoom({
    required String hostId,
    required String hostName,
    required String guestId,
    required String guestName,
    required String relatedType, // 'shop' | 'place' | 'crew'
    required String relatedId,
    required String relatedTitle,
    String? deliveryMethod,
    DateTime? appointmentAt,
  }) async {
    // 기존 채팅방 조회
    final existing = await _db
        .collection('chatRooms')
        .where('participants', arrayContains: guestId)
        .where('hostId', isEqualTo: hostId)
        .where('relatedId', isEqualTo: relatedId)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) return existing.docs.first.id;

    // 새 채팅방 생성
    final ref = _db.collection('chatRooms').doc();
    final data = <String, dynamic>{
      'participants':     [hostId, guestId],
      'participantNames': {hostId: hostName, guestId: guestName},
      'hostId':          hostId,
      'guestId':         guestId,
      'relatedType':     relatedType,
      'relatedId':       relatedId,
      'relatedTitle':    relatedTitle,
      'lastMessage':     '',
      'lastMessageAt':   FieldValue.serverTimestamp(),
      'createdAt':       FieldValue.serverTimestamp(),
    };
    if (deliveryMethod != null) data['deliveryMethod'] = deliveryMethod;
    if (appointmentAt  != null) {
      data['appointmentAt'] = Timestamp.fromDate(appointmentAt);
    }
    await ref.set(data);
    return ref.id;
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
      'senderId':   senderId,
      'senderName': senderName,
      'text':       text,
      'isAuto':     false,
      'createdAt':  FieldValue.serverTimestamp(),
    });

    final roomRef = _db.collection('chatRooms').doc(roomId);
    batch.update(roomRef, {
      'lastMessage':   text,
      'lastMessageAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

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
      'roomId':          roomId,
      'productId':       productId,
      'deliveryMethod':  deliveryMethod,
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
  static Stream<QuerySnapshot> messagesStream(String roomId) =>
      _db
          .collection('chatRooms')
          .doc(roomId)
          .collection('messages')
          .orderBy('createdAt', descending: false)
          .snapshots();

  static Stream<QuerySnapshot> roomsStream(String userId) =>
      _db
          .collection('chatRooms')
          .where('participants', arrayContains: userId)
          .orderBy('lastMessageAt', descending: true)
          .snapshots();
}

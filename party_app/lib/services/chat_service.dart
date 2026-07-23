import 'package:cloud_firestore/cloud_firestore.dart';

class ChatService {
  static final _db = FirebaseFirestore.instance;

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
  static Future<void> sendMessage({
    required String roomId,
    required String senderId,
    required String senderName,
    required String text,
    bool isAuto = false,
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
      'isAuto':     isAuto,
      'createdAt':  FieldValue.serverTimestamp(),
    });

    final roomRef = _db.collection('chatRooms').doc(roomId);
    batch.update(roomRef, {
      'lastMessage':   text,
      'lastMessageAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  // ── 자동발송 예약 등록 ──────────────────────────────────────────
  static Future<void> schedulePendingAutoMessage({
    required String roomId,
    required String hostId,
    required String hostName,
    required String message,
    required DateTime sendAt,
  }) async {
    await _db.collection('pendingAutoMessages').add({
      'roomId':    roomId,
      'hostId':    hostId,
      'hostName':  hostName,
      'message':   message,
      'sendAt':    Timestamp.fromDate(sendAt),
      'sent':      false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ── 자동발송 실행 (채팅방 입장 시 체크) ─────────────────────────
  // pendingAutoMessages 중 sendAt <= now && sent == false 인 것을 발송
  static Future<void> flushPendingAutoMessages(String roomId) async {
    final now   = Timestamp.now();
    final snap  = await _db
        .collection('pendingAutoMessages')
        .where('roomId', isEqualTo: roomId)
        .where('sent', isEqualTo: false)
        .get();

    for (final doc in snap.docs) {
      final d      = doc.data();
      final sendAt = d['sendAt'] as Timestamp;
      if (sendAt.compareTo(now) > 0) continue; // 아직 시간 안 됨

      await sendMessage(
        roomId:     roomId,
        senderId:   d['hostId']   as String,
        senderName: d['hostName'] as String,
        text:       d['message']  as String,
        isAuto:     true,
      );
      await doc.reference.update({'sent': true});
    }
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

const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

const { sendPushToUsers } = require('./pushSender');

// ── 알림을 푸시로 바꾸는 자리 ────────────────────────────────────────────────
//
// 발송을 **문서가 생긴 뒤의 트리거**로 받는다. 알림을 만드는 곳(예약 승인,
// 최소 인원 미달 자동 취소, 오픈 알림, 환불 처리…)마다 발송 호출을 심지 않는
// 이유는 두 가지다.
//
// 1) 그 자리들은 대부분 배치/트랜잭션 안이다. 트랜잭션은 충돌하면 **처음부터
//    다시 실행된다** — 그 안에서 푸시를 보내면 재시도마다 같은 알림이 다시
//    나가고, 되돌릴 방법도 없다(보낸 알림은 롤백되지 않는다). 문서 생성은
//    커밋될 때 한 번만 일어나므로 트리거는 정확히 한 번 깨어난다.
// 2) 알림 문서를 만드는 곳이 지금도 네 군데고 계속 는다. 새로 추가하는 사람이
//    발송 호출을 잊으면 그 종류만 조용히 푸시가 빠진다 — 여기 하나로 모으면
//    "알림함에 뜨는데 푸시는 안 온다"는 상태 자체가 생기지 않는다.
//
// 대가는 알림함 문서를 만들지 않는 알림은 이 경로를 타지 않는다는 것이다.
// 채팅이 그렇다(메시지마다 알림 문서를 남기면 알림함이 대화로 뒤덮인다).
// 그래서 채팅만 아래에 별도 트리거를 둔다.

const REGION = 'asia-northeast3';

/**
 * 알림 문서를 눌렀을 때 어디로 갈지를 앱에 넘긴다.
 * 앱의 라우팅 규칙(notification_route.dart)이 이 값들만 보고 화면을 고른다 —
 * 알림함에서 누른 것과 푸시에서 누른 것이 같은 곳으로 가야 하기 때문이다.
 */
function routeData(id, d) {
  return {
    notificationId: id,
    type: d.type || '',
    role: d.role || '',
    partyId: d.partyId || '',
    placeId: d.placeId || '',
    placeCollection: d.placeCollection || '',
    refCollection: d.refCollection || '',
    refId: d.refId || '',
  };
}

exports.onNotificationCreated = onDocumentCreated(
  { document: 'notifications/{notificationId}', region: REGION },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const d = snap.data() || {};
    if (!d.uid || !d.title) return;

    const res = await sendPushToUsers(d.uid, {
      title: d.title,
      body: d.body || '',
      data: routeData(snap.id, d),
    });
    console.log(
      `[push] 알림 발송 type=${d.type} uid=${d.uid} ` +
        `sent=${res.sent} failed=${res.failed} pruned=${res.pruned}`,
    );
  },
);

// ── 채팅 ─────────────────────────────────────────────────────────────────────
//
// 받는 사람은 방의 participants에서 **보낸 사람을 뺀 나머지**다. senderId를
// 그대로 믿어도 되는 이유: 사람이 친 메시지는 규칙이 senderId == request.auth.uid
// 를 못 박고(firestore.rules), 호스트 이름으로 나가는 자동 안내는 서버만
// 쓴다(chatAutoMessages.js).
//
// 방에 들어와 대화를 보고 있는 사람에게도 서버는 그냥 보낸다 — 누가 지금 방을
// 보고 있는지는 서버가 알 수 없다. 대신 앱이 자기가 열어둔 방의 메시지면
// 알림을 그리지 않는다(PushNotificationService.activeChatRoomId).
exports.onChatMessageCreated = onDocumentCreated(
  { document: 'chatRooms/{roomId}/messages/{messageId}', region: REGION },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const msg = snap.data() || {};
    const text = (msg.text || '').toString();
    if (!text.trim()) return;

    const roomId = event.params.roomId;
    const roomSnap = await admin
      .firestore()
      .collection('chatRooms')
      .doc(roomId)
      .get();
    if (!roomSnap.exists) return;

    const room = roomSnap.data() || {};
    const participants = Array.isArray(room.participants)
      ? room.participants
      : [];
    const targets = participants.filter((uid) => uid && uid !== msg.senderId);
    if (targets.length === 0) return;

    // 제목은 보낸 사람 이름 — 알림 목록에 여러 대화가 쌓였을 때 누구와의
    // 대화인지가 제목에서 바로 보여야 한다. 방 문서의 이름을 우선 쓰고
    // (닉네임 변경이 반영된 최신값), 없으면 메시지에 박힌 이름을 쓴다.
    const names = room.participantNames || {};
    const senderName =
      names[msg.senderId] || msg.senderName || '새 메시지';

    const res = await sendPushToUsers(targets, {
      title: senderName,
      body: text,
      data: {
        type: 'chat',
        roomId,
        otherName: senderName,
        relatedTitle: room.relatedTitle || '',
      },
    });
    console.log(
      `[push] 채팅 발송 room=${roomId} targets=${targets.length} ` +
        `sent=${res.sent} failed=${res.failed} pruned=${res.pruned}`,
    );
  },
);

exports.__helpers = { routeData };

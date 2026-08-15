const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

// 채팅 자동 안내 문구 — **서버 전용 발송 경로**.
//
// ── 왜 옮겼나 ────────────────────────────────────────────────────────────────
// 예전에는 게스트 기기가 pendingAutoMessages에 예약을 써 두고, 채팅방에 들어가는
// 순간 **호스트의 uid를 senderId로 박아** 직접 메시지를 만들었다
// (ChatService.flushPendingAutoMessages). 그 구조 때문에 firestore.rules의
// messages create는 senderId를 uid()로 못 박지 못하고 "이 방의 참가자 중 하나"
// 까지만 허용할 수밖에 없었다 — 즉 참가자 A가 참가자 B를 사칭해 아무 말이나
// 남길 수 있었다.
//
// 이제 자동 안내는 여기(Admin SDK)에서만 만들어진다. Admin SDK는 규칙을
// 우회하므로, 규칙 쪽은 클라이언트에 대해 senderId == uid()를 그냥 못 박으면
// 된다. 사칭 경로가 규칙이 아니라 **코드 구조에서** 사라진 것이다.
//
// ── 클라이언트가 넘기는 값 / 서버가 정하는 값 ───────────────────────────────
// 클라이언트: roomId (+ 파티샵만 productId·deliveryMethod·appointmentAt)
// 서버      : 보내는 사람(hostId·hostName), 문구 원문, 발송 시각, 발송 자체
//
// 문구와 호스트를 클라이언트에서 받지 않는 게 핵심이다. 방 문서
// (chatRooms/{roomId})가 이미 hostId·guestId·relatedType·relatedId·
// participantNames를 들고 있으므로, 서버는 roomId 하나로 원본 글까지 되짚어
// 갈 수 있다. 클라이언트가 조작할 수 있는 값은 "어느 상품의 안내인가"와
// "언제 만나기로 했나"뿐이고, 둘 다 호스트가 직접 쓴 문구 중 어느 것을 언제
// 보낼지만 고를 뿐 남을 사칭하는 데는 쓸 수 없다.
//
// ── pendingAutoMessages 컬렉션 ──────────────────────────────────────────────
// 서버 내부 큐다. 클라이언트 read/write는 규칙에서 전면 차단돼 있다
// (firestore.rules의 pendingAutoMessages 블록 — allow read, write: if false).
// 앱은 이 컬렉션을 직접 만지지 않고 아래 두 onCall만 부른다.

const REGION = 'asia-northeast3';

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;
const KST_OFFSET_MS = 9 * HOUR_MS;

/** 자동 안내를 붙일 수 있는 글 종류 — 방 문서의 relatedType과 같은 값. */
const SUPPORTED_TYPES = new Set(['crew', 'shop', 'place']);

// ── 순수 규칙(발송 시각·문구 선택) ───────────────────────────────────────────
// Cloud Functions 런타임은 UTC지만 기존 앱 코드는 **기기 로컬(한국)** 기준으로
// 시각을 계산하고 있었다. 그대로 UTC로 옮기면 안내가 9시간 어긋나므로 KST를
// 명시적으로 다룬다.

/** ms(UTC)가 속한 **KST 날짜**의 자정을 UTC ms로 돌려준다. */
function kstDayStartMs(ms) {
  return Math.floor((ms + KST_OFFSET_MS) / DAY_MS) * DAY_MS - KST_OFFSET_MS;
}

/**
 * 발송 시각 — 옮기기 전 클라이언트 계산과 **같은 값**을 낸다.
 *
 *   crew  : 지금 (문의를 걸자마자 인사)
 *   shop  : 수령/이용일이 있으면 그날 KST 10:00의 2시간 전(= KST 08:00),
 *           없으면 지금(예전 코드의 `now+2h`에서 다시 2시간을 뺀 값)
 *   place : 이용일 KST 08:00. 이용일이 없으면 예약할 것도 없다(null).
 *
 * @returns {number|null} UTC ms. null이면 예약하지 않는다.
 */
function computeSendAtMs({ relatedType, appointmentAtMs, nowMs }) {
  const hasAppointment = Number.isFinite(appointmentAtMs);
  if (relatedType === 'crew') return nowMs;
  if (relatedType === 'shop') {
    return hasAppointment ? kstDayStartMs(appointmentAtMs) + 8 * HOUR_MS : nowMs;
  }
  if (relatedType === 'place') {
    return hasAppointment ? kstDayStartMs(appointmentAtMs) + 8 * HOUR_MS : null;
  }
  return null;
}

/**
 * 클라이언트가 보낸 약속일(ms)을 정규화한다 — 값이 **실제로 있을 때만** 약속일로
 * 인정하고, 없으면 null을 돌려준다.
 *
 * ⚠ `Number(null)`은 NaN이 아니라 **0**이다. 그래서 null을 그대로 Number()에
 *   넘긴 뒤 Number.isFinite()로 거르면 통과해 버리고, epoch(1970-01-01)가 실제
 *   약속일로 취급된다 — 그러면 sendAt이 1969-12-31로 계산된다(KST 08:00 - 9h).
 *   수령일 없는 파티샵 주문은 "지금 발송"이어야 하고, 이용일 없는 장소는 아예
 *   예약하지 않아야 하는데 둘 다 어긋난다.
 */
function normalizeAppointmentMs(value) {
  if (value == null) return null;
  const ms = Number(value);
  return Number.isFinite(ms) ? ms : null;
}

/**
 * 원본 글에서 안내 문구를 고른다 — 문구는 **항상 호스트가 쓴 문서에서** 읽는다.
 * 파티샵만 배송/수령 방법별로 문구가 갈린다.
 */
function resolveAutoText(relatedType, sourceData, { deliveryMethod } = {}) {
  if (!sourceData) return '';
  if (relatedType === 'shop') {
    const byMethod = sourceData.autoMessages;
    if (!byMethod || typeof byMethod !== 'object' || !deliveryMethod) return '';
    const text = byMethod[deliveryMethod];
    return typeof text === 'string' ? text.trim() : '';
  }
  const text = sourceData.autoMessage;
  return typeof text === 'string' ? text.trim() : '';
}

// ── 공통 조회 헬퍼 ───────────────────────────────────────────────────────────

function requireAuth(request) {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
  return uid;
}

/** 방 문서를 읽고 호출자가 그 방 참가자인지 확인한다. */
async function loadRoomForParticipant(db, roomId, uid) {
  if (typeof roomId !== 'string' || !roomId) {
    throw new HttpsError('invalid-argument', 'roomId가 필요합니다.');
  }
  const ref = db.collection('chatRooms').doc(roomId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError('not-found', '채팅방을 찾을 수 없습니다.');
  }
  const room = snap.data();
  const participants = Array.isArray(room.participants) ? room.participants : [];
  if (!participants.includes(uid)) {
    throw new HttpsError('permission-denied', '이 채팅방의 참가자가 아닙니다.');
  }
  return { ref, room, participants };
}

/**
 * 방이 가리키는 원본 글을 읽어 { hostId, autoText }를 돌려준다.
 *
 * 원본 글의 hostId가 방의 hostId와 다르면 예약하지 않는다 — 글이 지워졌다가
 * 같은 id로 되살아났거나, 방이 엉뚱한 글을 가리키는 상태에서 남의 이름으로
 * 안내가 나가는 것을 막는다.
 */
async function resolveSource(db, { room, productId, deliveryMethod }) {
  const relatedType = room.relatedType;
  const relatedId = room.relatedId;
  if (!SUPPORTED_TYPES.has(relatedType) || typeof relatedId !== 'string' || !relatedId) {
    return null;
  }

  if (relatedType === 'shop') {
    if (typeof productId !== 'string' || !productId) return null;
    const shopSnap = await db.collection('partyShops').doc(relatedId).get();
    if (!shopSnap.exists) return null;
    // 문구는 상품 문서에, 주인은 샵 문서에 있다. 상품은 반드시 이 샵 아래에서만
    // 찾으므로 다른 샵의 문구를 끌어올 수는 없다.
    const productSnap = await shopSnap.ref.collection('products').doc(productId).get();
    if (!productSnap.exists) return null;
    return {
      hostId: shopSnap.data().hostId,
      autoText: resolveAutoText('shop', productSnap.data(), { deliveryMethod }),
    };
  }

  const collection = relatedType === 'crew' ? 'crews' : 'places';
  const snap = await db.collection(collection).doc(relatedId).get();
  if (!snap.exists) return null;
  return {
    hostId: snap.data().hostId,
    autoText: resolveAutoText(relatedType, snap.data()),
  };
}

// ── ① 자동 안내 예약 ─────────────────────────────────────────────────────────

exports.scheduleChatAutoMessage = onCall(
  { region: REGION },
  async (request) => {
    const uid = requireAuth(request);
    const db = admin.firestore();
    const {
      roomId,
      productId = null,
      deliveryMethod = null,
      appointmentAtMs = null,
    } = request.data || {};

    const { room } = await loadRoomForParticipant(db, roomId, uid);

    const hostId = room.hostId;
    if (typeof hostId !== 'string' || !hostId) {
      return { scheduled: false, reason: 'no-host' };
    }

    // 이미 말이 오간 방에는 예약하지 않는다 — 문의 버튼을 누를 때마다 같은
    // 인사가 쌓이는 것을 막는다(옮기기 전 crew 경로가 하던 isFresh 검사를
    // 서버로 가져왔고, 이제 모든 종류에 똑같이 적용된다).
    const lastMessage = typeof room.lastMessage === 'string' ? room.lastMessage : '';
    const alreadyTalking = lastMessage.length > 0;
    if (alreadyTalking && room.relatedType === 'crew') {
      return { scheduled: false, reason: 'room-not-fresh' };
    }

    const source = await resolveSource(db, { room, productId, deliveryMethod });
    if (!source) return { scheduled: false, reason: 'source-missing' };
    if (source.hostId !== hostId) {
      return { scheduled: false, reason: 'host-mismatch' };
    }
    if (!source.autoText) return { scheduled: false, reason: 'no-auto-message' };

    const nowMs = Date.now();
    const sendAtMs = computeSendAtMs({
      relatedType: room.relatedType,
      appointmentAtMs: normalizeAppointmentMs(appointmentAtMs),
      nowMs,
    });
    if (sendAtMs == null) return { scheduled: false, reason: 'no-send-time' };

    const names = room.participantNames || {};
    const hostName =
      typeof names[hostId] === 'string' && names[hostId] ? names[hostId] : '호스트';

    // 같은 방에 같은 문구가 아직 안 나갔다면 또 넣지 않는다. 사용자가 결제
    // 화면을 두 번 통과하거나 네트워크 재시도가 걸려도 안내는 한 번만 나간다.
    const dupe = await db
      .collection('pendingAutoMessages')
      .where('roomId', '==', roomId)
      .where('sent', '==', false)
      .get();
    if (dupe.docs.some((d) => d.data().message === source.autoText)) {
      return { scheduled: false, reason: 'already-scheduled' };
    }

    await db.collection('pendingAutoMessages').add({
      roomId,
      hostId,
      hostName,
      message: source.autoText,
      sendAt: admin.firestore.Timestamp.fromMillis(sendAtMs),
      sent: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      // 누가 이 예약을 유발했는지 — 사후 추적용. 발송 권한과는 무관하다.
      requestedBy: uid,
    });

    return { scheduled: true, sendAtMs };
  },
);

// ── ② 자동 안내 발송 ─────────────────────────────────────────────────────────

exports.flushChatAutoMessages = onCall(
  { region: REGION },
  async (request) => {
    const uid = requireAuth(request);
    const db = admin.firestore();
    const { roomId } = request.data || {};

    const { ref: roomRef, room, participants } =
      await loadRoomForParticipant(db, roomId, uid);

    const pending = await db
      .collection('pendingAutoMessages')
      .where('roomId', '==', roomId)
      .where('sent', '==', false)
      .get();
    if (pending.empty) return { sent: 0 };

    const nowMs = Date.now();
    let sent = 0;

    for (const doc of pending.docs) {
      const d = doc.data();
      const sendAt = d.sendAt;
      if (!sendAt || sendAt.toMillis() > nowMs) continue; // 아직 시간이 안 됐다

      // 보내는 사람은 반드시 **이 방의 호스트**여야 한다. 큐가 서버 전용이라
      // 어긋날 일이 없지만, 여기서 한 번 더 막아 두면 큐에 이상한 값이 들어와도
      // 방 밖 제3자 이름으로 메시지가 나가지는 않는다.
      if (d.hostId !== room.hostId || !participants.includes(d.hostId)) continue;

      // 한 트랜잭션 안에서 "아직 안 보냈나" 확인 → 메시지 쓰기 → 보냄 표시를
      // 함께 처리한다. 양쪽이 동시에 방에 들어와도 안내는 한 번만 나간다.
      const delivered = await db.runTransaction(async (tx) => {
        const fresh = await tx.get(doc.ref);
        if (!fresh.exists || fresh.data().sent === true) return false;

        const msgRef = roomRef.collection('messages').doc();
        tx.set(msgRef, {
          senderId: d.hostId,
          senderName: typeof d.hostName === 'string' ? d.hostName : '호스트',
          text: d.message,
          isAuto: true,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        tx.update(roomRef, {
          lastMessage: d.message,
          lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        tx.update(doc.ref, {
          sent: true,
          sentAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return true;
      });

      if (delivered) sent += 1;
    }

    return { sent };
  },
);

// 순수 규칙만 자체 검증에 노출한다(chatAutoMessages.selfcheck.js).
exports.__test = {
  computeSendAtMs, resolveAutoText, kstDayStartMs, normalizeAppointmentMs,
};

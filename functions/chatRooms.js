// 채팅방 **생성**은 서버에서만 한다.
//
// ── 왜 옮겼는가 ──────────────────────────────────────────────────────────
// 호스트가 "게스트 문의 받기"를 끄면 새 문의 방이 만들어지면 안 된다. 그런데
// 무엇을 막을지는 방 하나만 봐서는 알 수 없다 — 같은 (호스트, 게스트, 대상)이면
// 문의로 열었든 예약으로 열렸든 **같은 방**이기 때문이다(roomIdFor).
//
//   · 문의로 여는 방  → 게시글의 inquiryEnabled가 켜져 있어야 한다
//   · 예약으로 여는 방 → 문의 설정과 무관하게 언제나 열려야 한다
//
// 규칙(firestore.rules)만으로는 뒤쪽을 확인할 수 없다. 예약 기록은
// placeVisitReservations·placeReservationGroups·packageBookings·
// placeProductOrders·orders처럼 **임의 id 문서를 쿼리해야** 찾을 수 있는데,
// 보안 규칙은 쿼리를 할 수 없다(exists/get으로 경로 하나만 볼 수 있다).
// 그래서 규칙에 맡기면 "예약자인지"를 클라이언트가 스스로 신고하는 구조가 되고,
// 실제로 origin: 'booking'을 손으로 적어 보내면 문의 OFF가 통째로 무력해졌다.
//
// 이제 **클라이언트가 보낸 값 중 판정에 쓰이는 것은 하나도 없다.**
//   · 어떤 컬렉션의 글인지 → relatedType으로 서버가 정한다
//   · 호스트가 누구인지    → 원본 문서에서 서버가 읽는다
//   · 문의인지 예약인지    → 서버가 예약 기록을 직접 찾아 정한다
// 클라이언트가 정하는 것은 "어느 글에 말을 걸고 싶다"는 사실뿐이다.
//
// ── 메시지는 그대로다 ────────────────────────────────────────────────────
// 방이 만들어진 뒤의 대화는 예전 규칙 그대로 참가자만 보면 된다. 그래서
// 문의를 끄더라도 **이미 있던 방은 계속 열려 있다** — 대화방도, 관리자
// 채팅내역도 지우지 않는다는 정책과 같은 이야기다.

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

const REGION = 'asia-northeast3';

/// relatedType → 원본 글이 있을 수 있는 컬렉션.
///
/// 'place' 하나가 두 컬렉션을 가리키는 것은 **기존 채팅이 이미 그렇게 쓰고
/// 있어서**다(플레이스=events, 장소대여=places가 같은 relatedType을 쓴다).
/// 여기서 새 값을 만들면 같은 게시글에 방이 두 개 생긴다.
const LISTING_COLLECTIONS = {
  party: ['parties'],
  place: ['events', 'places'],
  shop: ['partyShops'],
  crew: ['crews'],
  // 이벤트·혜택 한 건. 플레이스(events/places)와 **일부러 나눈다** — 한
  // 플레이스에 이벤트가 여러 개 달리므로 같은 relatedType을 쓰면 호스트
  // 목록에서 어느 이벤트 이야기인지 구분되지 않는다. 무엇보다 'place'는
  // events·places만 뒤지므로 placePromotions 문서를 아예 찾지 못한다.
  //
  // 이 문서도 hostId와 inquiryEnabled를 그대로 들고 있어, 아래 자격 판정
  // (호스트 확인 · 문의 열림 확인)은 손댈 것이 없다.
  event: ['placePromotions'],
};

/// 게스트와 게시글 사이에 **실제 거래 기록**이 있는지 찾는 방법.
///
/// 전부 동등 비교만 쓴다 — Firestore는 등호 조건만 있는 쿼리를 단일 필드
/// 색인으로 처리하므로 복합 색인을 새로 만들지 않아도 된다.
///
/// 취소된 기록도 인정한다. 취소·환불이야말로 호스트와 이야기가 필요한
/// 순간인데, 상태로 걸러 버리면 그때 대화를 열 수 없다.
const BOOKING_LOOKUPS = {
  party: [
    // 신청 문서는 파티 문서 아래에 있다(문서 id는 uid 또는 uid_회차).
    { subOf: 'parties', sub: 'applications', guestField: 'uid' },
  ],
  place: [
    { collection: 'placeVisitReservations', guestField: 'requesterId', listingField: 'placeId' },
    { collection: 'placeReservationGroups', guestField: 'requesterId', listingField: 'placeId' },
    { collection: 'packageBookings', guestField: 'requesterId', listingField: 'placeId' },
    { collection: 'placeProductOrders', guestField: 'buyerId', listingField: 'placeId' },
  ],
  shop: [
    { collection: 'orders', guestField: 'buyerId', listingField: 'shopId' },
  ],
  // 파티크루에는 거래가 없다 — 구인/구직 글이라 문의가 유일한 대화 경로다.
  crew: [],
  // 이벤트도 마찬가지다. 결제·예약이 붙는 것은 이벤트가 아니라 플레이스의
  // 상품·이용권이고, 그 대화는 이미 relatedType 'place'로 열린다.
  event: [],
};

/// 같은 (호스트, 게스트, 대상)이면 언제나 같은 문서 하나 — 앱의
/// ChatService.roomIdFor와 **반드시 같은 규칙**이어야 한다.
function roomIdFor({ relatedType, relatedId, guestId }) {
  return `${guestId}_${relatedType}_${relatedId}`;
}

/// 원본 글을 찾아 { collection, id, data }로 돌려준다. 못 찾으면 null.
async function findListing(db, relatedType, relatedId) {
  const candidates = LISTING_COLLECTIONS[relatedType] || [];
  for (const collection of candidates) {
    const snap = await db.collection(collection).doc(relatedId).get();
    if (snap.exists) return { collection, id: relatedId, data: snap.data() || {} };
  }
  return null;
}

/// 이 게스트가 이 게시글에 실제 신청·예약·주문을 남긴 적이 있는가.
async function hasBookingRecord(db, { relatedType, relatedId, guestId }) {
  for (const lookup of BOOKING_LOOKUPS[relatedType] || []) {
    try {
      const query = lookup.subOf
        ? db
            .collection(lookup.subOf)
            .doc(relatedId)
            .collection(lookup.sub)
            .where(lookup.guestField, '==', guestId)
            .limit(1)
        : db
            .collection(lookup.collection)
            .where(lookup.guestField, '==', guestId)
            .where(lookup.listingField, '==', relatedId)
            .limit(1);
      const snap = await query.get();
      if (!snap.empty) return true;
    } catch (e) {
      // 한 컬렉션 조회가 실패해도 나머지는 계속 본다 — 여기서 통째로
      // 실패하면 예약자가 대화를 못 여는 쪽이 되어 더 나쁘다.
      console.error(`[chatRooms] 예약 조회 실패 ${JSON.stringify(lookup)}: ${e}`);
    }
  }
  return false;
}

/// 이 규칙이 생기기 전에 임의 id로 만들어진 방 — 있으면 그걸 그대로 쓴다.
/// 색인이 없어 실패할 수 있어 감싸 둔다(못 찾으면 새로 만든다).
async function findLegacyRoom(db, { guestId, hostId, relatedId }) {
  try {
    const snap = await db
      .collection('chatRooms')
      .where('participants', 'array-contains', guestId)
      .where('hostId', '==', hostId)
      .where('relatedId', '==', relatedId)
      .limit(1)
      .get();
    if (!snap.empty) return snap.docs[0].id;
  } catch (e) {
    console.error(`[chatRooms] 옛 방 조회 실패(무시): ${e}`);
  }
  return null;
}

/// 두 사람 사이에 차단이 걸려 있는가 — **어느 방향이든** true.
///
/// 차단은 기록으로는 한 방향이지만(A가 B를 차단), 효과는 양방향이어야 한다.
/// 차단당한 쪽이 말을 걸 수 있으면 차단한 사람에게 알림이 가고, 그건 차단이
/// 아니다. 반대로 차단한 쪽이 말을 거는 것도 앞뒤가 맞지 않는다.
///
/// 문서 id가 "{차단한사람}_{차단당한사람}"이라 쿼리 없이 **문서 두 개만
/// 읽으면** 끝난다(색인도 필요 없다 — favorites와 같은 패턴).
///
/// ⚠️ 앱도 차단한 상대에게 채팅을 걸지 않지만, 그건 안내일 뿐이다. 구버전
/// 앱과 콜러블 직접 호출은 화면을 거치지 않으므로 **판정은 여기가 정본**이다.
async function isBlockedBetween(db, a, b) {
  if (!a || !b || a === b) return false;
  const [ab, ba] = await Promise.all([
    db.collection('userBlocks').doc(`${a}_${b}`).get(),
    db.collection('userBlocks').doc(`${b}_${a}`).get(),
  ]);
  return ab.exists || ba.exists;
}

exports.createChatRoom = onCall({ region: REGION }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
  const guestId = request.auth.uid;
  const db = admin.firestore();

  const data = request.data || {};
  const relatedType = String(data.relatedType || '');
  const relatedId = String(data.relatedId || '');
  if (!LISTING_COLLECTIONS[relatedType]) {
    throw new HttpsError('invalid-argument', 'relatedType이 올바르지 않습니다.');
  }
  if (!relatedId) {
    throw new HttpsError('invalid-argument', 'relatedId가 필요합니다.');
  }

  // 표시용 값만 클라이언트에서 받는다 — 판정에는 쓰지 않는다.
  const guestName = String(data.guestName || '').slice(0, 60);
  const relatedTitle = String(data.relatedTitle || '').slice(0, 200);
  const deliveryMethod = data.deliveryMethod ? String(data.deliveryMethod) : null;
  const appointmentAtMs = data.appointmentAtMs != null ? Number(data.appointmentAtMs) : null;

  const roomId = roomIdFor({ relatedType, relatedId, guestId });

  // 이미 있는 방이면 설정과 무관하게 그대로 돌려준다 — 문의를 닫아도 기존
  // 대화는 계속된다는 정책이 여기서 지켜진다.
  const existing = await db.collection('chatRooms').doc(roomId).get();
  if (existing.exists) return { roomId, created: false };

  const listing = await findListing(db, relatedType, relatedId);
  if (!listing) throw new HttpsError('not-found', '대상을 찾을 수 없어요.');

  // 호스트는 **원본 문서에서 읽는다.** 클라이언트가 보낸 hostId를 쓰면 남의
  // 이름이 걸린 대화방을 만들 수 있다.
  const hostId = listing.data.hostId || '';
  if (!hostId) throw new HttpsError('failed-precondition', '호스트 정보를 찾을 수 없어요.');
  if (hostId === guestId) {
    throw new HttpsError('failed-precondition', '자신의 게시글에는 문의할 수 없어요.');
  }

  // ── 차단 ───────────────────────────────────────────────────────────────
  // 자격 판정보다 **먼저** 본다. 예약자여도, 문의가 열려 있어도, 차단이
  // 걸려 있으면 새 방은 열리지 않는다.
  //
  // 오류 문구는 **누가 차단했는지 드러내지 않는다.** "상대가 당신을
  // 차단했습니다"라고 알려주면 차단이 통보가 되어 버린다 — 차단한 사람이
  // 보복을 당하는 경로를 만들지 않는 것이 이 문구의 목적이다.
  if (await isBlockedBetween(db, guestId, hostId)) {
    throw new HttpsError(
      'failed-precondition',
      '지금은 이 사용자와 대화를 시작할 수 없어요.'
    );
  }

  // ── 방을 열 자격 ───────────────────────────────────────────────────────
  // 예약 기록을 먼저 본다. 그래야 origin에 "무엇이 이 방을 열어 줬는지"가
  // 사실대로 남는다(문의가 열려 있어도 예약자면 booking이다).
  const booked = await hasBookingRecord(db, { relatedType, relatedId, guestId });
  const inquiryOpen = listing.data.inquiryEnabled !== false;
  const origin = booked ? 'booking' : inquiryOpen ? 'inquiry' : null;
  if (origin === null) {
    throw new HttpsError(
      'failed-precondition',
      '호스트가 문의 채팅을 운영하지 않아요. 신청·예약이 확정되면 채팅으로 연락할 수 있어요.'
    );
  }

  // 옛 방이 남아 있으면 새로 만들지 않는다.
  const legacyId = await findLegacyRoom(db, { guestId, hostId, relatedId });
  if (legacyId) return { roomId: legacyId, created: false };

  const hostName =
    listing.data.hostName || String(data.hostName || '').slice(0, 60) || '호스트';

  const room = {
    participants: [hostId, guestId],
    participantNames: { [hostId]: hostName, [guestId]: guestName },
    hostId,
    guestId,
    relatedType,
    relatedId,
    relatedTitle,
    lastMessage: '',
    lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    // 무엇이 이 방을 열어 줬는지 — 서버 판정 결과다(클라이언트가 보낸 값이
    // 아니다). 관리자 채팅 열람에서 "문의였는지 예약이었는지"를 읽는 데 쓴다.
    origin,
    // 원본이 어느 컬렉션 문서였는지 — relatedType만으로는 events와 places를
    // 가를 수 없어 함께 남긴다.
    relatedCollection: listing.collection,
  };
  if (deliveryMethod) room.deliveryMethod = deliveryMethod;
  if (appointmentAtMs && Number.isFinite(appointmentAtMs)) {
    room.appointmentAt = admin.firestore.Timestamp.fromMillis(appointmentAtMs);
  }

  await db.collection('chatRooms').doc(roomId).set(room);
  return { roomId, created: true };
});

exports.__helpers = {
  isBlockedBetween,
  roomIdFor,
  findListing,
  hasBookingRecord,
  LISTING_COLLECTIONS,
  BOOKING_LOOKUPS,
};

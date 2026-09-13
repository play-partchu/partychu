const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const { logUserActivity } = require('./memberActivityHelpers');

// ── 관리자: 사용자 간 채팅 열람 (읽기 전용) ──────────────────────────────────
//
// **왜 Firestore Rules에 `allow read: if isAdmin()`을 넣지 않았나**
//
// chatRooms는 개인 간 1:1 대화다. 규칙 쪽을 관리자에게 열면 그 순간부터
// "admin claim을 가진 아무 클라이언트나 collectionGroup/list로 전 국민의
// 개인 대화를 통째로 긁을 수 있는" 구조가 된다 — 앱 클라이언트든, 유출된
// 관리자 세션이든, 사내 다른 도구든 전부. 게다가 규칙에는 "누가 언제 무엇을
// 읽었는지" 남길 방법이 아예 없다.
//
// 그래서 이 파일의 onCall 두 개가 **유일한 열람 통로**다. 이미 같은 이유로
// Admin SDK를 거치고 있는 adminGetUserApplications / adminGetApplicationStatusCount
// (memberManagement.js)와 완전히 같은 패턴이고, 여기에 감사 로그가 더해진다.
//
//   · 관리자 판정: users/{uid}.role == 'admin' (규칙의 isAdmin()과 같은 근거)
//   · 감사 로그: userActivityLogs (기존 시스템 재사용 — 새 컬렉션 만들지 않음)
//   · 쓰기: **없다.** 방/메시지에 어떤 필드도 쓰지 않는다(아래 "읽기 전용" 참고).
//
// ── 읽기 전용이라는 말의 의미 ────────────────────────────────────────────────
// chatRooms 스키마에는 readAt·unreadCount 같은 읽음 상태 필드가 **애초에 없다**
// (chat_service.dart / chat_list_screen.dart 참고 — 앱에도 읽음 표시가 없다).
// 그래서 "관리자가 봐도 사용자에게 읽음으로 처리되지 않게" 하는 데 특별한 장치가
// 필요하지 않고, 이 파일이 lastMessage/lastMessageAt을 포함해 **어떤 필드도
// 갱신하지 않는 것**으로 충분하다. 나중에 읽음 상태가 생기더라도 이 원칙은
// 그대로다 — 관리자 열람은 사용자 대화의 상태를 절대 건드리지 않는다.

const REGION = 'asia-northeast3';

/** 한 번의 목록 요청이 훑어보는 방 문서 수 상한(후처리 필터가 있을 때의 안전장치). */
const MAX_SCAN_ROUNDS = 5;
const MAX_SCAN_PER_ROUND = 300;
/** 상세 화면이 한 번에 내려받는 메시지 수. 넘으면 cursor로 이어 받는다. */
const MESSAGE_PAGE_SIZE = 300;
/** 닉네임 검색이 후보로 삼는 사용자 수 상한. */
const NICKNAME_CANDIDATE_LIMIT = 20;

/**
 * 방 문서의 relatedType만으로는 **장소 계열을 더 못 가른다.**
 *
 * 앱에서 플레이스 방문예약·장소대여·패키지·이용권 문의는 전부
 * `relatedType: 'place'` + `relatedId: placeId` 한 방을 공유한다
 * (chat_target_list_screen.dart의 dedupeKey 참고 — 예약 건마다가 아니라
 * 대상 글마다 방이 하나다). 그래서 관리자 화면에서도 "패키지 문의만"처럼
 * 예약 종류로는 가를 수 없고, **어느 컬렉션의 글이냐**로만 가른다:
 *
 *   events = 술집·바·카페(플레이스)   places = 공간대여·숙박(장소대여)
 *   (combo_place_type.dart의 placeCollection과 같은 구분)
 */
const KIND_LABELS = {
  party: '파티',
  venue: '플레이스',
  stay: '장소대여/숙박',
  shop: '파티샵',
  crew: '파티크루',
  other: '기타',
};

const KIND_VALUES = Object.keys(KIND_LABELS);
const SEARCH_FIELDS = ['uid', 'nickname', 'roomId', 'relatedId', 'title'];

/** relatedType → 원본 글이 있는 컬렉션. place는 events/places 두 곳을 다 본다. */
const SOURCE_COLLECTIONS = {
  party: ['parties'],
  shop: ['partyShops'],
  crew: ['crews'],
  place: ['places', 'events'],
};

function toIso(v) {
  return v && typeof v.toDate === 'function' ? v.toDate().toISOString() : null;
}

async function requireAdmin(request) {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
  }
  const db = admin.firestore();
  const callerSnap = await db.collection('users').doc(request.auth.uid).get();
  if (callerSnap.data()?.role !== 'admin') {
    throw new HttpsError('permission-denied', '관리자만 사용할 수 있습니다.');
  }
  return { db, callerUid: request.auth.uid };
}

/**
 * 방 문서들이 가리키는 원본 글을 한 번에 확인해 { relatedId: {kind, exists} }를
 * 돌려준다. 방마다 개별 get()을 부르는 N+1을 피하려고 컬렉션별 getAll로 묶는다.
 */
async function classifyRooms(db, roomDatas) {
  const idsByCollection = new Map(); // collection → Set(relatedId)
  for (const d of roomDatas) {
    const type = d.relatedType;
    const id = d.relatedId;
    if (typeof id !== 'string' || !id) continue;
    for (const col of SOURCE_COLLECTIONS[type] || []) {
      if (!idsByCollection.has(col)) idsByCollection.set(col, new Set());
      idsByCollection.get(col).add(id);
    }
  }

  const found = new Map(); // "collection/id" → true
  await Promise.all(
    [...idsByCollection.entries()].map(async ([col, ids]) => {
      const refs = [...ids].map((id) => db.collection(col).doc(id));
      if (refs.length === 0) return;
      const snaps = await db.getAll(...refs);
      for (const snap of snaps) {
        if (snap.exists) found.set(`${col}/${snap.id}`, true);
      }
    })
  );

  return (d) => {
    const type = d.relatedType;
    const id = typeof d.relatedId === 'string' ? d.relatedId : '';
    if (type === 'party') {
      return { kind: 'party', sourceExists: found.has(`parties/${id}`) };
    }
    if (type === 'shop') {
      return { kind: 'shop', sourceExists: found.has(`partyShops/${id}`) };
    }
    if (type === 'crew') {
      return { kind: 'crew', sourceExists: found.has(`crews/${id}`) };
    }
    if (type === 'place') {
      // 공간대여·숙박(places)을 먼저 본다 — 두 컬렉션에 같은 id가 동시에
      // 존재할 일은 없지만, 순서를 못 박아 두면 판정이 흔들리지 않는다.
      if (found.has(`places/${id}`)) return { kind: 'stay', sourceExists: true };
      if (found.has(`events/${id}`)) return { kind: 'venue', sourceExists: true };
      // 원본 글이 지워진 장소 방 — 어느 쪽이었는지 되짚을 근거가 없다.
      return { kind: 'other', sourceExists: false };
    }
    return { kind: 'other', sourceExists: false };
  };
}

/** 참가자 uid → 표시용 사용자 정보. users는 관리자가 읽을 수 있지만(규칙),
 *  화면마다 uid 개수만큼 조회가 나가지 않도록 서버에서 한 번에 붙여 보낸다. */
async function fetchUserBriefs(db, uids) {
  const unique = [...new Set(uids.filter((u) => typeof u === 'string' && u))];
  if (unique.length === 0) return {};
  const result = {};
  const CHUNK = 100;
  for (let i = 0; i < unique.length; i += CHUNK) {
    const refs = unique.slice(i, i + CHUNK).map((u) => db.collection('users').doc(u));
    const snaps = await db.getAll(...refs);
    for (const snap of snaps) {
      if (!snap.exists) continue;
      const d = snap.data();
      result[snap.id] = {
        uid: snap.id,
        nickname: d.nickname || null,
        name: d.name || null,
        email: d.email || null,
        accountStatus: d.accountStatus || null,
        isTestAccount: d.isTestAccount === true,
      };
    }
  }
  return result;
}

/** 방 문서 하나 → 목록/상세가 함께 쓰는 요약 형태. */
function buildRoomSummary(doc, { kind, sourceExists }, briefs, messageCount) {
  const d = doc.data();
  const participants = Array.isArray(d.participants) ? d.participants : [];
  // hostId/guestId가 비어 있는 옛 문서를 대비해 participants로 보정한다.
  const hostId = typeof d.hostId === 'string' && d.hostId ? d.hostId : null;
  const guestId = typeof d.guestId === 'string' && d.guestId ? d.guestId : null;
  const storedNames = (d.participantNames && typeof d.participantNames === 'object')
    ? d.participantNames
    : {};

  const brief = (uid) => (uid && briefs[uid]) || null;

  return {
    roomId: doc.id,
    kind,
    kindLabel: KIND_LABELS[kind] || KIND_LABELS.other,
    relatedType: d.relatedType || null,
    relatedId: d.relatedId || null,
    relatedTitle: d.relatedTitle || null,
    sourceExists,
    participants,
    hostId,
    hostNameInRoom: hostId ? storedNames[hostId] || null : null,
    host: brief(hostId),
    guestId,
    guestNameInRoom: guestId ? storedNames[guestId] || null : null,
    guest: brief(guestId),
    lastMessage: typeof d.lastMessage === 'string' ? d.lastMessage : '',
    lastMessageAt: toIso(d.lastMessageAt),
    createdAt: toIso(d.createdAt),
    messageCount,
    // 결정적 id("{guestId}_{relatedType}_{relatedId}")로 만들어진 방인지,
    // 그 규칙 이전의 임의 id 방인지 — 둘 다 여기서 똑같이 조회된다.
    // 마이그레이션이 필요 없다는 사실을 화면에서도 눈으로 확인할 수 있게 실어 보낸다.
    idScheme:
      guestId && d.relatedType && d.relatedId &&
      doc.id === `${guestId}_${d.relatedType}_${d.relatedId}`
        ? 'deterministic'
        : 'legacy',
  };
}

// ── ① 채팅방 목록 ────────────────────────────────────────────────────────────
//
// 정렬은 언제나 최근 메시지순(lastMessageAt desc)이다. 방 문서는 만들어질 때
// lastMessageAt에 serverTimestamp를 채우므로(옛 방 포함) 이 정렬에서 빠지는
// 방은 없다.
exports.adminListChatRooms = onCall({ region: REGION }, async (request) => {
  const { db } = await requireAdmin(request);

  const {
    kind = 'all',
    searchField = null,
    searchValue = '',
    limit = 50,
    cursorId = null,
  } = request.data || {};

  if (kind !== 'all' && !KIND_VALUES.includes(kind)) {
    throw new HttpsError('invalid-argument', 'kind 값이 올바르지 않습니다.');
  }
  if (searchField != null && !SEARCH_FIELDS.includes(searchField)) {
    throw new HttpsError('invalid-argument', 'searchField 값이 올바르지 않습니다.');
  }
  const pageSize = Math.min(Math.max(Number(limit) || 50, 1), 100);
  const term = String(searchValue || '').trim();
  const hasSearch = searchField != null && term.length > 0;

  const rooms = db.collection('chatRooms');

  // 방 id 검색은 목록 쿼리가 아니라 단건 조회다 — 옛 임의 id든 새 결정적
  // id든 문서 하나를 그대로 집어 온다.
  if (hasSearch && searchField === 'roomId') {
    const snap = await rooms.doc(term).get();
    const docs = snap.exists ? [snap] : [];
    return finalize(db, docs, kind, pageSize, {});
  }

  // 닉네임 검색: 닉네임 → uid로 먼저 옮긴다(chatRooms에는 닉네임이 없다).
  // nicknameLower prefix 범위 조회는 회원 검색이 이미 쓰는 방식과 같다.
  let uidCandidates = null;
  if (hasSearch && searchField === 'nickname') {
    const lower = term.toLowerCase();
    const userSnap = await db
      .collection('users')
      .orderBy('nicknameLower')
      .startAt(lower)
      .endAt(`${lower}`)
      .limit(NICKNAME_CANDIDATE_LIMIT)
      .get();
    uidCandidates = userSnap.docs.map((d) => d.id);
    if (uidCandidates.length === 0) {
      return { rooms: [], nextCursor: null, truncated: false, kindLabels: KIND_LABELS };
    }
  }

  /** 어떤 검색이든 "정렬된 방 쿼리 하나"로 환원한다. */
  function baseQueryFor(uid) {
    let q = rooms;
    if (uid) {
      q = q.where('participants', 'array-contains', uid);
    } else if (hasSearch && searchField === 'uid') {
      q = q.where('participants', 'array-contains', term);
    } else if (hasSearch && searchField === 'relatedId') {
      q = q.where('relatedId', '==', term);
    }
    // 종류 필터를 쿼리로 내릴 수 있는 건 relatedType이 곧 종류인 것들뿐이다.
    // venue/stay는 둘 다 relatedType == 'place'라 원본 글을 봐야 갈리고,
    // other는 "알려진 값이 아닌 것"이라 부등호 조합이 필요해 둘 다 후처리한다.
    if (kind === 'party' || kind === 'shop' || kind === 'crew') {
      q = q.where('relatedType', '==', kind);
    } else if (kind === 'venue' || kind === 'stay') {
      q = q.where('relatedType', '==', 'place');
    }
    return q.orderBy('lastMessageAt', 'desc');
  }

  // 제목/장소명 검색만 정렬 축이 다르다 — 범위 조회는 그 필드로 정렬해야
  // 해서(Firestore 제약) relatedTitle 순으로 받아온 뒤 최근순으로 다시 세운다.
  if (hasSearch && searchField === 'title') {
    let q = rooms.orderBy('relatedTitle').startAt(term).endAt(`${term}`);
    if (kind === 'party' || kind === 'shop' || kind === 'crew') {
      q = q.where('relatedType', '==', kind);
    } else if (kind === 'venue' || kind === 'stay') {
      q = q.where('relatedType', '==', 'place');
    }
    const snap = await q.limit(MAX_SCAN_PER_ROUND).get();
    const docs = snap.docs.sort((a, b) => {
      const at = a.data().lastMessageAt;
      const bt = b.data().lastMessageAt;
      return (bt?.toMillis?.() ?? 0) - (at?.toMillis?.() ?? 0);
    });
    return finalize(db, docs.slice(0, pageSize), kind, pageSize, {
      truncated: snap.size >= MAX_SCAN_PER_ROUND,
    });
  }

  // 닉네임 검색은 후보 uid마다 방 목록을 따로 받아 합친다(닉네임 하나가 여러
  // 계정일 수 있고, Firestore는 array-contains를 OR로 묶어주지 않는다).
  if (uidCandidates) {
    const snaps = await Promise.all(
      uidCandidates.map((uid) => baseQueryFor(uid).limit(pageSize * 2).get())
    );
    const byId = new Map();
    for (const snap of snaps) for (const doc of snap.docs) byId.set(doc.id, doc);
    const docs = [...byId.values()].sort((a, b) => {
      const at = a.data().lastMessageAt;
      const bt = b.data().lastMessageAt;
      return (bt?.toMillis?.() ?? 0) - (at?.toMillis?.() ?? 0);
    });
    return finalize(db, docs.slice(0, pageSize), kind, pageSize, {
      truncated: docs.length > pageSize,
    });
  }

  // ── 일반 목록(+ uid/대상ID 검색) — 커서 페이지네이션 ────────────────────
  //
  // venue/stay/other 필터는 원본 글을 확인해야 갈리므로 쿼리 뒤에서 걸러진다.
  // 그래서 한 번에 pageSize만 받아오면 걸러낸 만큼 페이지가 비게 된다 —
  // 목표 개수를 채울 때까지 몇 라운드만 더 훑고, 그래도 못 채우면 truncated로
  // 알린다(조용히 잘라내지 않는다).
  const needsPostFilter = kind === 'venue' || kind === 'stay' || kind === 'other';
  const scanSize = Math.min(needsPostFilter ? pageSize * 4 : pageSize, MAX_SCAN_PER_ROUND);

  const matched = [];
  let cursorDoc = null;
  if (cursorId) {
    const c = await rooms.doc(String(cursorId)).get();
    if (c.exists) cursorDoc = c;
  }
  let exhausted = false;
  let rounds = 0;
  let nextCursor = null;

  while (matched.length < pageSize && !exhausted && rounds < MAX_SCAN_ROUNDS) {
    rounds += 1;
    let q = baseQueryFor(null);
    if (cursorDoc) q = q.startAfter(cursorDoc);
    const snap = await q.limit(scanSize).get();
    if (snap.size < scanSize) exhausted = true;
    if (snap.empty) break;

    const classify = await classifyRooms(db, snap.docs.map((d) => d.data()));
    for (const doc of snap.docs) {
      cursorDoc = doc;
      const info = classify(doc.data());
      if (needsPostFilter && info.kind !== kind) continue;
      matched.push({ doc, info });
      if (matched.length >= pageSize) {
        nextCursor = doc.id;
        break;
      }
    }
  }

  return finalize(db, matched, kind, pageSize, {
    nextCursor: matched.length >= pageSize ? nextCursor : null,
    truncated: matched.length < pageSize && !exhausted,
    preClassified: true,
  });
});

/**
 * 방 문서 목록 → 응답. 종류 판정·사용자 정보·메시지 개수를 한 번에 붙인다.
 * [docs]는 DocumentSnapshot 배열이거나, 이미 판정을 마친 {doc, info} 배열이다.
 */
async function finalize(db, docs, kind, pageSize, opts = {}) {
  const entries = opts.preClassified
    ? docs
    : await (async () => {
        const classify = await classifyRooms(db, docs.map((d) => d.data()));
        return docs.map((doc) => ({ doc, info: classify(doc.data()) }));
      })();

  // 단건/제목/닉네임 경로는 종류 필터를 여기서 마저 적용한다.
  const filtered = kind === 'all'
    ? entries
    : entries.filter((e) => e.info.kind === kind);

  const uids = [];
  for (const { doc } of filtered) {
    const d = doc.data();
    if (Array.isArray(d.participants)) uids.push(...d.participants);
    if (d.hostId) uids.push(d.hostId);
    if (d.guestId) uids.push(d.guestId);
  }

  const [briefs, counts] = await Promise.all([
    fetchUserBriefs(db, uids),
    Promise.all(
      filtered.map(async ({ doc }) => {
        try {
          const agg = await doc.ref.collection('messages').count().get();
          return agg.data().count;
        } catch (_) {
          // 개수를 못 세도 목록 자체는 보여준다.
          return null;
        }
      })
    ),
  ]);

  return {
    rooms: filtered.map(({ doc, info }, i) => buildRoomSummary(doc, info, briefs, counts[i])),
    nextCursor: opts.nextCursor || null,
    truncated: opts.truncated === true,
    kindLabels: KIND_LABELS,
  };
}

// ── ② 채팅방 상세(메시지 전문) ───────────────────────────────────────────────
//
// 시간순(createdAt asc) 그대로 내려보낸다. 여기서도 쓰기는 **채팅 쪽에 대해서는
// 전혀 없고**, 감사 로그(userActivityLogs)만 남긴다.
exports.adminGetChatRoom = onCall({ region: REGION }, async (request) => {
  const { db, callerUid } = await requireAdmin(request);

  const { roomId, cursorId = null, limit = MESSAGE_PAGE_SIZE } = request.data || {};
  if (!roomId || typeof roomId !== 'string') {
    throw new HttpsError('invalid-argument', 'roomId가 필요합니다.');
  }
  const pageSize = Math.min(Math.max(Number(limit) || MESSAGE_PAGE_SIZE, 1), 500);

  const roomRef = db.collection('chatRooms').doc(roomId);
  const roomSnap = await roomRef.get();
  if (!roomSnap.exists) {
    throw new HttpsError('not-found', '채팅방을 찾을 수 없습니다.');
  }
  const roomData = roomSnap.data();

  let q = roomRef.collection('messages').orderBy('createdAt', 'asc');
  if (cursorId) {
    const c = await roomRef.collection('messages').doc(String(cursorId)).get();
    if (c.exists) q = q.startAfter(c);
  }
  const msgSnap = await q.limit(pageSize + 1).get();
  const pageDocs = msgSnap.docs.slice(0, pageSize);
  const hasMore = msgSnap.size > pageSize;

  const participants = Array.isArray(roomData.participants) ? roomData.participants : [];
  const classify = await classifyRooms(db, [roomData]);
  const senderUids = pageDocs.map((d) => d.data().senderId).filter(Boolean);
  const [briefs, countAgg] = await Promise.all([
    fetchUserBriefs(db, [...participants, roomData.hostId, roomData.guestId, ...senderUids]),
    roomRef.collection('messages').count().get().catch(() => null),
  ]);

  // 사람이 보낸 말·서버 자동 안내 둘 다 정확히 이 5개 키만 쓴다
  // (firestore.rules의 messages create가 hasOnly로 못 박고, 서버 자동 안내도
  // 같은 모양으로 쓴다 — chatAutoMessages.js). 그래도 그 밖의 키가 있으면
  // 조용히 버리지 않고 extraFields로 그대로 올려 보낸다: 나중에 첨부/삭제
  // 표시 같은 필드가 생겨도 관리자 화면이 먼저 그것을 보게 하기 위함이다.
  const KNOWN_KEYS = new Set(['senderId', 'senderName', 'text', 'isAuto', 'createdAt']);

  const messages = pageDocs.map((doc) => {
    const m = doc.data();
    const senderId = typeof m.senderId === 'string' ? m.senderId : null;
    const extraFields = {};
    for (const [k, v] of Object.entries(m)) {
      if (KNOWN_KEYS.has(k)) continue;
      extraFields[k] = v && typeof v.toDate === 'function' ? v.toDate().toISOString() : v;
    }
    let role = 'unknown';
    if (senderId && senderId === roomData.hostId) role = 'host';
    else if (senderId && senderId === roomData.guestId) role = 'guest';
    else if (senderId && participants.includes(senderId)) role = 'participant';

    return {
      id: doc.id,
      senderId,
      role,
      // 방에 저장된 이름과 현재 계정 닉네임은 다를 수 있다(닉네임 변경).
      // 관리자는 둘 다 봐야 "그때 이 이름으로 보였다"를 알 수 있다.
      senderNameInMessage: typeof m.senderName === 'string' ? m.senderName : null,
      senderNickname: senderId && briefs[senderId] ? briefs[senderId].nickname : null,
      text: typeof m.text === 'string' ? m.text : '',
      isAuto: m.isAuto === true,
      // 방 참가자가 아닌 uid가 보낸 말 = 시스템/이상 발신. 지금 스키마에는
      // 시스템 메시지 개념이 따로 없어 이 조건이 곧 그 자리다.
      isSystem: !!senderId && !participants.includes(senderId),
      createdAt: toIso(m.createdAt),
      extraFields: Object.keys(extraFields).length > 0 ? extraFields : null,
    };
  });

  // ── 감사 로그 ──────────────────────────────────────────────────────────
  // 기존 관리자 활동 로그(userActivityLogs, actorType:'admin')를 그대로 쓴다 —
  // adminUpdateMember가 계정상태 변경을 남기는 것과 같은 자리다. 새 컬렉션을
  // 만들지 않으므로 회원 상세의 "통합 활동 타임라인"에서 곧바로 보인다.
  // 이어보기(cursorId)까지 매번 남기면 같은 열람이 여러 줄로 쪼개져 로그가
  // 흐려지므로 첫 페이지에서만 남긴다.
  if (!cursorId) {
    const subjects = [...new Set([roomData.guestId, roomData.hostId].filter(Boolean))];
    await Promise.all(
      subjects.map((uid) =>
        logUserActivity(db, {
          uid,
          activityType: 'admin_chat_viewed',
          refCollection: 'chatRooms',
          refId: roomId,
          actorType: 'admin',
          actorUid: callerUid,
          extra: {
            relatedType: roomData.relatedType || null,
            relatedId: roomData.relatedId || null,
            relatedTitle: roomData.relatedTitle || null,
            counterpartUid: subjects.find((u) => u !== uid) || null,
          },
        })
      )
    );
  }

  return {
    room: buildRoomSummary(
      roomSnap,
      classify(roomData),
      briefs,
      countAgg ? countAgg.data().count : null
    ),
    messages,
    hasMore,
    nextCursor: hasMore && pageDocs.length > 0 ? pageDocs[pageDocs.length - 1].id : null,
  };
});

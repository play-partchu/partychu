// ══════════════════════════════════════════════════════════════════════════
// 매장 이벤트 신청 — **서버가 정본**이다.
//
// ── 왜 클라이언트 직접 쓰기를 접었나 ──────────────────────────────────────
// 처음에는 신청·취소를 앱이 firestore.rules 아래에서 직접 쓰게 했다. 정원도
// 승인도 결제도 없어 트랜잭션으로 지킬 불변식이 없다고 봤기 때문이다. 그런데
// **종료된 이벤트를 막을 수 없었다.**
//
// 종료 판정은 앱에서 이렇게 계산된다(PlacePromotion.statusAt).
//
//     isAlways면 끝나지 않는다
//     endAt이 있고, now가 **endAt이 속한 날의 23:59:59**를 지났으면 종료
//
// 이 판정을 rules로 옮겨 적으려면 저장된 Timestamp를 KST 날짜로 접고 그 날의
// 끝을 만들어야 한다. rules의 시간 연산으로도 흉내는 낼 수 있지만, 흉내낸
// 판정과 Dart 판정이 하루의 경계에서 어긋나는 순간 **앱에는 버튼이 있는데
// 서버가 거부하는** 상태가 된다. 그리고 "버튼이 안 보이니 괜찮다"는 방어가
// 아니다 — 변조된 클라이언트는 버튼을 거치지 않는다.
//
// 그래서 판정을 한 곳에 모았다. 신청·취소는 이 파일의 콜러블만 쓰고,
// rules는 placeEventApplications의 **모든 클라이언트 쓰기를 막는다**
// (parties/{id}/applications가 쓰는 것과 같은 보호 패턴이다).
//
// ── 파생 필드는 전부 서버가 쓴다 ──────────────────────────────────────────
// hostId · placeId · placeCollection · eventTitle · placeName · 일정은 모두
// **원본 이벤트(와 그 장소) 문서에서 읽은 값**이다. 클라이언트는 eventId
// 하나만 보낸다. 그래서 "이벤트 제목 = 아무 문자열"이나 "hostId = 내 uid"
// 같은 위조가 구조적으로 불가능하다 — 위조할 입력 자체가 없다.
//
// ── 중복 방지는 여전히 문서 id다 ──────────────────────────────────────────
// `{eventId}_{uid}` 고정. 서버가 써도 이 성질은 그대로 쓸모 있다 — 재시도나
// 동시 호출이 두 건을 만들지 못한다.
//
// ── 컬렉션 이름 ───────────────────────────────────────────────────────────
// ⚠️ `applications`가 **아니다.** 파티 신청 서브컬렉션과 이름을 공유하면
//    `/{path=**}/applications/{id}` 재귀 규칙과 `collectionGroup('applications')`
//    집계(탈퇴 차단 accountWithdrawal.js, 매출 통계 adminSalesStats.js)가 매장
//    이벤트 신청까지 파티 신청으로 센다.
// ══════════════════════════════════════════════════════════════════════════

const admin = require('firebase-admin');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentDeleted } = require('firebase-functions/v2/firestore');

const { buildApplicantIdentity } = require('./applicantIdentity');
const { assertIdentityVerified } = require('./identityGuard');

const REGION = 'asia-northeast3';

/// 신청 문서가 사는 최상위 컬렉션 — 앱의 [PlaceEventApplication.collection]과
/// **글자 하나까지 같아야 한다.**
const COLLECTION = 'placeEventApplications';

/// 이벤트 본문이 사는 곳.
const EVENT_COLLECTION = 'placePromotions';

/// 이벤트가 붙을 수 있는 부모 장소 컬렉션 — 그 밖의 값은 신뢰하지 않는다
/// (firestore.rules의 ownsSourcePlace 화이트리스트와 같은 둘).
const PLACE_COLLECTIONS = ['events', 'places'];

/// 한 번에 내려주는 신청 건수 상한.
const LIMIT = 500;

/// users 문서를 한 번에 가져오는 개수.
const USER_CHUNK = 100;

/// 정리 트리거가 한 번에 지우는 문서 수(Firestore 배치 상한 500 아래).
const CLEANUP_BATCH = 400;

const KST_OFFSET_MS = 9 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

/// 사용자에게 그대로 보여주는 문구 — 앱은 서버가 준 message를 띄운다.
const MESSAGES = {
  notFound: '이벤트를 찾을 수 없어요.',
  notAccepting: '지금은 신청을 받지 않는 이벤트예요.',
  hidden: '지금은 볼 수 없는 이벤트예요.',
  ended: '이미 종료된 이벤트예요.',
  ownEvent: '내가 연 이벤트에는 신청할 수 없어요.',
  noApplication: '신청 내역을 찾을 수 없어요.',
  notMine: '내 신청만 취소할 수 있어요.',
};

// ── 순수 판정 (Firestore를 모른다 — selfcheck가 그대로 확인한다) ───────────

/** 문서 id. 앱의 [PlaceEventApplication.docIdFor]와 **같은 식**이다. */
function docIdFor(eventId, guestId) {
  return `${eventId}_${guestId}`;
}

/** ms(UTC)가 속한 **KST 날짜**의 자정을 UTC ms로. */
function kstDayStartMs(ms) {
  return Math.floor((ms + KST_OFFSET_MS) / DAY_MS) * DAY_MS - KST_OFFSET_MS;
}

/**
 * Timestamp | Date | number 무엇이 와도 UTC ms로. 값이 없으면 null.
 */
function toMillis(value) {
  if (value == null) return null;
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'number') return value;
  return null;
}

/**
 * 이 이벤트가 [nowMs] 시점에 **종료되었는가.**
 *
 * 앱의 `PlacePromotion.statusAt`이 쓰는 종료 조건을 그대로 옮긴 것이다.
 *
 *   · 상시 진행(isAlways)이면 날짜로는 끝나지 않는다
 *   · endAt이 없으면 끝나지 않는다
 *   · endAt이 **속한 날의 23:59:59**를 지나야 종료다(그 날 하루는 살아 있다)
 *
 * 앱은 기기 로컬 시각(국내 사용자는 KST)으로 그 날의 끝을 만든다. 서버는 KST로
 * 고정해 만든다 — UTC로 접으면 하루가 9시간 어긋나 "앱에는 진행 중인데 서버가
 * 거부하는" 구간이 생긴다.
 */
function isEndedAt(eventData, nowMs) {
  const ev = eventData || {};
  if (ev.isAlways === true) return false;
  const endMs = toMillis(ev.endAt);
  if (endMs == null) return false;
  // 그 날 23:59:59.000 — Dart의 DateTime(y, m, d, 23, 59, 59)와 같은 지점.
  const boundary = kstDayStartMs(endMs) + 23 * 3600000 + 59 * 60000 + 59 * 1000;
  return nowMs > boundary;
}

/** 이 이벤트가 신청을 받는 설정인가 — 앱의 EventApplyMode와 같은 키다. */
function acceptsApplications(eventData) {
  const mode = (eventData || {}).applyMode || 'none';
  return mode === 'apply' || mode === 'inquiry_and_apply';
}

/**
 * 신청해도 되는가. 통과면 `{ ok: true }`, 아니면 `{ ok:false, code, message }`.
 *
 * **여기가 신청 가능 판정의 정본이다.** 앱의 `showsApplyButtonAt`은 같은 결론을
 * 내는 화면용 힌트이고, 그 둘이 어긋나도 실제로 들어가는 신청은 이쪽만 따른다.
 */
function evaluateApplyEligibility({ eventData, uid, nowMs }) {
  if (!eventData) {
    return { ok: false, code: 'not-found', message: MESSAGES.notFound };
  }
  if (eventData.hostId && eventData.hostId === uid) {
    return { ok: false, code: 'failed-precondition', message: MESSAGES.ownEvent };
  }
  if (eventData.isVisible !== true) {
    return { ok: false, code: 'failed-precondition', message: MESSAGES.hidden };
  }
  if (!acceptsApplications(eventData)) {
    return {
      ok: false,
      code: 'failed-precondition',
      message: MESSAGES.notAccepting,
    };
  }
  if (isEndedAt(eventData, nowMs)) {
    return { ok: false, code: 'failed-precondition', message: MESSAGES.ended };
  }
  return { ok: true };
}

/**
 * 신청 문서에 남길 **원본에서 베낀 값들**.
 *
 * 게스트 신청 내역이 이벤트 문서를 다시 읽지 않고도 목록을 그릴 수 있게 하는
 * 스냅샷이다(파티 신청의 `partyTitle`·`partyDateTime`과 같은 취급). 전부
 * 서버가 읽은 값이라 클라이언트가 손댈 수 없다.
 */
function buildApplicationSnapshot({ eventId, eventData, placeData }) {
  const ev = eventData || {};
  const placeCollection = PLACE_COLLECTIONS.includes(ev.placeCollection)
    ? ev.placeCollection
    : 'events';
  return {
    eventId,
    placeId: ev.placeId || '',
    placeCollection,
    hostId: ev.hostId || '',
    eventTitle: ev.title || '',
    placeName: (placeData && (placeData.name || placeData.placeName)) || '',
    eventIsAlways: ev.isAlways === true,
    eventStartAt: ev.startAt || null,
    eventEndAt: ev.endAt || null,
  };
}

// ── 콜러블 ────────────────────────────────────────────────────────────────

/**
 * 신청한다(또는 무른 신청을 다시 켠다).
 *
 * 클라이언트가 보내는 것은 `eventId` 하나뿐이다.
 */
const applyToPlaceEvent = onCall({ region: REGION }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', '로그인이 필요해요.');
  }
  const uid = request.auth.uid;
  const eventId = String((request.data || {}).eventId || '').trim();
  if (!eventId) {
    throw new HttpsError('invalid-argument', MESSAGES.notFound);
  }

  const db = admin.firestore();

  // 본인확인 게이트 — 서버가 users/{uid}를 직접 읽는다(identityGuard.js).
  // 앱 루트 게이트만으로는 구버전 앱·직접 호출을 막지 못한다.
  await assertIdentityVerified(db, uid);

  const eventSnap = await db.collection(EVENT_COLLECTION).doc(eventId).get();
  const eventData = eventSnap.exists ? eventSnap.data() : null;
  const verdict = evaluateApplyEligibility({
    eventData,
    uid,
    nowMs: Date.now(),
  });
  if (!verdict.ok) throw new HttpsError(verdict.code, verdict.message);

  // 장소 이름은 신청 내역 목록에 그대로 뜨는 값이라 여기서 한 번 베껴 둔다.
  // 못 읽어도 신청 자체를 막지는 않는다(이름 한 줄이 없을 뿐이다).
  let placeData = null;
  if (eventData.placeId) {
    const placeCollection = PLACE_COLLECTIONS.includes(eventData.placeCollection)
      ? eventData.placeCollection
      : 'events';
    const placeSnap = await db
      .collection(placeCollection)
      .doc(eventData.placeId)
      .get();
    placeData = placeSnap.exists ? placeSnap.data() : null;
  }

  const snapshot = buildApplicationSnapshot({ eventId, eventData, placeData });
  const ref = db.collection(COLLECTION).doc(docIdFor(eventId, uid));
  const now = admin.firestore.FieldValue.serverTimestamp();

  const created = await db.runTransaction(async (tx) => {
    const cur = await tx.get(ref);
    if (!cur.exists) {
      tx.set(ref, {
        ...snapshot,
        guestId: uid,
        status: 'applied',
        createdAt: now,
        updatedAt: now,
      });
      return true;
    }
    if (cur.get('status') === 'applied') return false; // 이미 신청함 — 그대로 둔다
    // 무른 신청을 다시 켠다. 처음 신청한 시각(createdAt)은 남기고, 그 사이
    // 호스트가 제목·기간을 고쳤을 수 있으므로 스냅샷은 새로 베낀다.
    tx.update(ref, {
      ...snapshot,
      status: 'applied',
      updatedAt: now,
      cancelledAt: admin.firestore.FieldValue.delete(),
    });
    return true;
  });

  return { applicationId: ref.id, status: 'applied', changed: created };
});

/**
 * 신청을 무른다. **문서는 지우지 않는다** — 지우면 "신청했다가 취소했다"는
 * 사실까지 사라진다.
 *
 * 종료된 이벤트여도 취소는 언제나 된다(막을 이유가 없다).
 */
const cancelPlaceEventApplication = onCall(
  { region: REGION },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', '로그인이 필요해요.');
    }
    const uid = request.auth.uid;
    const eventId = String((request.data || {}).eventId || '').trim();
    if (!eventId) {
      throw new HttpsError('invalid-argument', MESSAGES.noApplication);
    }

    const db = admin.firestore();
    const ref = db.collection(COLLECTION).doc(docIdFor(eventId, uid));

    await db.runTransaction(async (tx) => {
      const cur = await tx.get(ref);
      if (!cur.exists) {
        throw new HttpsError('not-found', MESSAGES.noApplication);
      }
      // 문서 id가 이미 uid를 담고 있어 남의 문서를 지목할 수 없지만, 근거를
      // 경로 모양이 아니라 **문서 내용**에 두는 편이 안전하다.
      if (cur.get('guestId') !== uid) {
        throw new HttpsError('permission-denied', MESSAGES.notMine);
      }
      if (cur.get('status') === 'cancelled') return;
      const now = admin.firestore.FieldValue.serverTimestamp();
      tx.update(ref, {
        status: 'cancelled',
        updatedAt: now,
        cancelledAt: now,
      });
    });

    return { applicationId: ref.id, status: 'cancelled' };
  },
);

/**
 * 이벤트 하나의 신청자 목록 — **호스트 전용**.
 *
 * 신청자의 닉네임·실명은 `users/{uid}`에 있고 규칙상 본인·관리자만 읽을 수
 * 있다. 그래서 호스트 앱이 직접 조회할 방법이 없고, uid를 대신 보여주는 것은
 * 금지다. 신원을 만드는 함수는 파티와 **같은 것**을 쓴다(applicantIdentity.js).
 */
const getPlaceEventApplicants = onCall({ region: REGION }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', '로그인이 필요해요.');
  }
  const uid = request.auth.uid;
  const eventId = String((request.data || {}).eventId || '').trim();
  if (!eventId) {
    throw new HttpsError('invalid-argument', MESSAGES.notFound);
  }

  const db = admin.firestore();

  // 주인 확인은 **이벤트 문서를 읽어서** 한다. 요청에 실려 온 값은 쓰지 않는다.
  const eventSnap = await db.collection(EVENT_COLLECTION).doc(eventId).get();
  if (!eventSnap.exists) {
    throw new HttpsError('not-found', MESSAGES.notFound);
  }
  if ((eventSnap.get('hostId') || '') !== uid) {
    throw new HttpsError(
      'permission-denied',
      '이 이벤트의 호스트만 신청자를 볼 수 있어요.',
    );
  }

  const snap = await db
    .collection(COLLECTION)
    .where('eventId', '==', eventId)
    .limit(LIMIT)
    .get();

  const docs = snap.docs;
  if (docs.length === 0) {
    return { applicants: [], appliedCount: 0, truncated: false };
  }

  const guestIds = [
    ...new Set(docs.map((d) => d.get('guestId')).filter(Boolean)),
  ];
  const users = new Map();
  for (let i = 0; i < guestIds.length; i += USER_CHUNK) {
    const chunk = guestIds.slice(i, i + USER_CHUNK);
    const refs = chunk.map((id) => db.collection('users').doc(id));
    const snaps = await db.getAll(...refs);
    snaps.forEach((s) => users.set(s.id, s.exists ? s.data() : null));
  }

  // 정렬은 메모리에서 한다 — `where(eventId) + orderBy(createdAt)`은 복합
  // 색인을 요구하고, 이 목록은 색인을 새로 배포할 만큼 크지 않다.
  const applicants = docs
    .map((d) => {
      const { identity } = buildApplicantIdentity(
        users.get(d.get('guestId')) || null,
      );
      return toRow(d, identity);
    })
    .sort(byAppliedAt);

  return {
    applicants,
    appliedCount: countApplied(applicants),
    truncated: docs.length >= LIMIT,
  };
});

/**
 * 신청 문서 하나를 응답 한 줄로 — **guestId(uid)는 담지 않는다.**
 *
 * 호스트 화면이 신청자를 지목할 때 쓰는 값은 `applicationId` 하나다. uid를
 * 내려보내면 화면 어딘가에 그대로 그려질 길이 생긴다(파티 신청자 화면이
 * 지키는 원칙과 같다).
 */
function toRow(doc, identity) {
  const d = doc.data() || {};
  return {
    applicationId: doc.id,
    status: d.status || 'applied',
    appliedAt: toMillis(d.createdAt),
    identity,
  };
}

/**
 * 오래 신청한 사람이 위로. 시각이 없는 문서는 맨 뒤로 보낸다(신청 순서를
 * 모르는 건을 맨 앞에 세우면 목록 번호가 매번 달라진다).
 */
function byAppliedAt(a, b) {
  const av = a.appliedAt == null ? Number.MAX_SAFE_INTEGER : a.appliedAt;
  const bv = b.appliedAt == null ? Number.MAX_SAFE_INTEGER : b.appliedAt;
  return av - bv;
}

/** 지금 신청 중인 건수 — 취소는 세지 않는다(앱의 countApplied와 같은 판정). */
function countApplied(rows) {
  return rows.filter((r) => r.status !== 'cancelled').length;
}

// ── 정리 ──────────────────────────────────────────────────────────────────

/**
 * 이벤트 문서가 지워지면 그 신청도 함께 지운다.
 *
 * 신청 문서는 **아무도 지울 수 없다** — 게스트는 취소(상태 전환)만 하고,
 * 호스트에게는 삭제 권한이 없으며, rules가 클라이언트 쓰기를 전부 막는다.
 * 그래서 이벤트만 사라지면 신청서는 가리킬 대상 없이 영영 남는다.
 *
 * 장소를 통째로 지우는 경로(contentCleanup.js)는 placeId로 신청서를 함께
 * 지우지만, **이벤트 한 건만 지우는 경로**(관리 화면의 삭제 버튼 →
 * PlacePromotionService.deleteById)는 그 정리를 거치지 않는다. 이 트리거가
 * 양쪽을 모두 덮는다 — 장소 삭제로 지워진 이벤트에도 똑같이 걸리므로,
 * 어느 경로로 지워도 신청서가 남지 않는다(두 번 지워도 무해하다).
 */
const onPlacePromotionDeleted = onDocumentDeleted(
  { document: `${EVENT_COLLECTION}/{promotionId}`, region: REGION },
  async (event) => {
    const eventId = event.params.promotionId;
    const db = admin.firestore();
    await deleteApplicationsForEvent(db, eventId);
  },
);

/** eventId로 걸린 신청을 전부 지운다. 배치로 나눠 돈다. */
async function deleteApplicationsForEvent(db, eventId) {
  let removed = 0;
  for (;;) {
    const snap = await db
      .collection(COLLECTION)
      .where('eventId', '==', eventId)
      .limit(CLEANUP_BATCH)
      .get();
    if (snap.empty) break;
    const batch = db.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    removed += snap.size;
    if (snap.size < CLEANUP_BATCH) break;
  }
  return removed;
}

module.exports = {
  COLLECTION,
  EVENT_COLLECTION,
  PLACE_COLLECTIONS,
  LIMIT,
  CLEANUP_BATCH,
  MESSAGES,
  docIdFor,
  kstDayStartMs,
  toMillis,
  isEndedAt,
  acceptsApplications,
  evaluateApplyEligibility,
  buildApplicationSnapshot,
  toRow,
  byAppliedAt,
  countApplied,
  deleteApplicationsForEvent,
  applyToPlaceEvent,
  cancelPlaceEventApplication,
  getPlaceEventApplicants,
  onPlacePromotionDeleted,
};

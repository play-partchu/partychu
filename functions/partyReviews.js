// ─────────────────────────────────────────────────────────────────────────────
// 💬 파티 참여 후기 — 실제 참여를 마친 게스트가 남기는 **한 줄** 후기.
//
// 별점이 없다. 호스트 평점·후기 통계·랭킹도 만들지 않는다 — 출시 전이라
// 의도적으로 "한 줄 글 하나"까지만 둔다.
//
// ── 참여 완료의 서버 정본 ───────────────────────────────────────────────────
// **`applications/{id}.checkedInAt`이다.** 신청 상태 `attended`가 아니다 —
// 그 값은 아무도 쓰지 않는 죽은 값이고(checkInRules.js 상단 주석), 체크인은
// status를 건드리지 않고 checkedInAt만 찍는다(checkInTokens.js의 CONSUMERS).
// 그 필드는 호스트가 QR을 찍었을 때 **Admin SDK만** 쓰므로 클라이언트가
// 만들어낼 수 없다. 그래서 자격 검증은 이 필드 하나로 끝난다.
//
// 단순 신청(applied)·승인(approved)만으로는 못 쓴다. 체크인을 되돌리면
// (revokeCheckIn) checkedInAt이 null이 되고, 그 뒤로는 새 후기를 쓸 수 없다.
//
// ── 작성 기간은 "그 게스트가 참여한 회차"가 기준이다 ────────────────────────
// 정기 파티는 전체 파티의 마지막 회차가 아니라 **그 신청 문서의 회차 종료
// 시각**(`occurrenceEndAt`)부터 14일이다. 8/1 회차에 참여한 사람의 기한은
// 8/15까지이고, 그 파티가 12월까지 이어지는지와 무관하다.
// 일회성 파티는 회차 필드가 없으므로 파티의 최종 종료 시각을 쓴다
// (partySchedule.finalPartyEndAt — 일회성에서는 그 값이 곧 그 회차의 끝이다).
//
// ── ⚠ 파티 자동삭제(14일)와 겹친다 ──────────────────────────────────────────
// deleteExpiredParties가 최종 종료 + 14일에 파티 문서를 지운다(index.js의
// RETENTION_DAYS). 일회성 파티는 작성 기한과 삭제 시점이 **같은 날**이다.
// 그래서 후기는 파티 하위가 아니라 **독립 루트 컬렉션**이고, 표시에 필요한
// 최소 스냅샷(partyTitle·hostId·회차 시작시각)을 자기 안에 들고 있다.
// contentCleanup.js의 party 정리 대상은 `applications`와 `packageBookings`
// 뿐이라, 부모 파티가 사라져도 이 컬렉션은 **건드려지지 않는다**(그래서
// 여기에 후기를 추가하지 않는 것이 곧 보존 설계다 — 손대지 말 것).
//
// ── 권한 ────────────────────────────────────────────────────────────────────
// firestore.rules의 partyReviews는 읽기 공개 / 클라이언트 쓰기 전면 차단이고,
// 삭제는 관리자만 가능하다. 작성·수정·삭제는 전부 아래 콜러블(Admin SDK)을
// 지나므로, 앱이 `checkedInAt`이나 기한을 위조해 후기를 만들 수 없다.
// **호스트는 자기 파티의 후기를 고치거나 지울 수 없다** — 이 파일 어디에도
// 호스트를 작성자로 인정하는 경로가 없다.
// ─────────────────────────────────────────────────────────────────────────────

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

const { applicationDocId } = require('./partyCapacity');
const { finalPartyEndAt } = require('./partySchedule');

const REGION = 'asia-northeast3';
const COLLECTION = 'partyReviews';

/// 작성·수정 가능 기간. 파티 자동삭제(index.js RETENTION_DAYS)와 **같은 14일**
/// 이지만 기준점이 다르다 — 저쪽은 파티의 최종 종료, 이쪽은 그 게스트가 참여한
/// 회차의 종료다. 정기 파티에서는 이 값이 훨씬 먼저 끝난다.
const REVIEW_WINDOW_DAYS = 14;
const REVIEW_WINDOW_MS = REVIEW_WINDOW_DAYS * 24 * 60 * 60 * 1000;

/// 한 줄 후기 길이. 앱(party_review.dart)의 상수와 같은 값이어야 한다 —
/// 어긋나면 앱이 통과시킨 글을 서버가 거절해서 사용자가 이유를 알 수 없다.
const MIN_LENGTH = 5;
const MAX_LENGTH = 100;

/**
 * 후기 문서 id — `{partyId}_{applicationId}`.
 *
 * **한 신청/참여 건당 후기 1개**를 구조로 보장한다(favorites·userBlocks·
 * reports와 같은 결정적 id 패턴). 중복을 세는 카운터도, 별도 색인도 필요 없다.
 * 정기 파티는 applicationId 자체가 `{uid}_{occurrenceId}`라 회차마다 다른
 * 문서가 되므로, 같은 파티라도 회차별로 한 개씩 쓸 수 있다.
 */
function reviewDocId(partyId, applicationId) {
  return `${partyId}_${applicationId}`;
}

/** Timestamp | Date | number → ms. 없으면 null. */
function toMs(v) {
  if (v == null) return null;
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (typeof v.toDate === 'function') return v.toDate().getTime();
  if (v instanceof Date) return v.getTime();
  if (typeof v === 'number') return v;
  return null;
}

/**
 * 이 신청이 **참여를 마친 회차의 종료 시각**(ms).
 *
 * 정기 파티는 신청 문서에 박힌 회차 종료(`occurrenceEndAt`)를 그대로 쓴다 —
 * 그 게스트가 실제로 참여한 회차다. 일회성 파티는 회차 필드가 없어 파티의
 * 최종 종료 시각을 쓰고(그 값이 곧 그 회차의 끝이다), 파티 문서가 이미
 * 지워졌으면 신청 시점에 베껴 둔 `partyDateTime`으로 물러선다.
 *
 * 셋 다 없으면 null — 기한을 계산할 수 없으므로 작성을 막는다(추측하지 않는다).
 */
function occurrenceEndMsOf(app, partyData) {
  const occurrence = toMs(app && app.occurrenceEndAt);
  if (occurrence !== null) return occurrence;

  const final = partyData ? finalPartyEndAt(partyData) : null;
  if (final) return final.getTime();

  return toMs(app && app.partyDateTime);
}

/** 회차 종료 + 14일. 이 시각 **이전**까지만 쓰고 고칠 수 있다. */
function windowEndMs(occurrenceEnd) {
  return occurrenceEnd === null ? null : occurrenceEnd + REVIEW_WINDOW_MS;
}

/**
 * 한 줄 후기 정규화 — 줄바꿈 없는 한 줄로 만들고 길이를 본다.
 *
 * 줄바꿈·탭은 **거절하지 않고 공백 하나로 접는다**. 붙여넣기 한 번에 섞여
 * 들어오는 값이라 거절하면 사용자가 무엇이 문제인지 모른다. 접고 나서도
 * 길이가 안 맞으면 그때 이유를 말한다.
 *
 * @returns {{ok: true, text: string} | {ok: false, reason: string}}
 */
function normalizeReviewText(raw) {
  if (typeof raw !== 'string') {
    return { ok: false, reason: '후기 내용을 입력해주세요.' };
  }
  const text = raw.replace(/\s+/g, ' ').trim();
  if (text.length < MIN_LENGTH) {
    return { ok: false, reason: `후기는 ${MIN_LENGTH}자 이상 입력해주세요.` };
  }
  if (text.length > MAX_LENGTH) {
    return { ok: false, reason: `후기는 ${MAX_LENGTH}자까지 쓸 수 있어요.` };
  }
  return { ok: true, text };
}

/**
 * 이 사람이 지금 이 신청 건에 후기를 쓸 수 있는가 — **판정은 여기 하나**다.
 *
 * 순수 함수라 Firestore를 모른다(셀프체크가 그대로 돌린다). 호출부는 문서를
 * 읽어서 넘기기만 한다.
 *
 * @param {object|null} app       applications/{id} 문서 데이터
 * @param {object|null} partyData parties/{partyId} 문서 데이터(삭제됐으면 null)
 * @param {string} uid            요청자
 * @param {number} nowMs
 * @returns {{ok: true, windowEndMs: number} | {ok: false, code: string, message: string}}
 */
function judgeEligibility(app, partyData, uid, nowMs) {
  if (!app) {
    return {
      ok: false,
      code: 'not-found',
      message: '이 파티에 참여한 기록이 없어요.',
    };
  }

  // 남의 신청서로 쓰는 것을 막는다. 문서 id를 uid로 만들긴 하지만, 판정은
  // 문서 안의 값으로 한다(id 파싱에 기대지 않는다 — partyCapacity.js의
  // applicationDocId 주석과 같은 이유).
  if (app.uid !== uid) {
    return {
      ok: false,
      code: 'permission-denied',
      message: '본인의 참여 건에만 후기를 쓸 수 있어요.',
    };
  }

  // 호스트 본인 작성 금지. 파티 문서가 이미 지워졌어도 신청서에 박힌 hostId로
  // 판정할 수 있다(파티를 다시 읽지 않아도 되는 이유).
  const hostId = (partyData && partyData.hostId) || app.hostId || null;
  if (hostId && hostId === uid) {
    return {
      ok: false,
      code: 'permission-denied',
      message: '호스트는 자기 파티에 후기를 쓸 수 없어요.',
    };
  }

  // ⚠ 참여 완료의 정본 — status가 아니라 checkedInAt이다(파일 상단 참고).
  if (toMs(app.checkedInAt) === null) {
    return {
      ok: false,
      code: 'failed-precondition',
      message: '참여가 확인된 파티에만 후기를 쓸 수 있어요.',
    };
  }

  const end = windowEndMs(occurrenceEndMsOf(app, partyData));
  if (end === null) {
    return {
      ok: false,
      code: 'failed-precondition',
      message: '이 참여 건의 후기 작성 기간을 확인할 수 없어요.',
    };
  }
  if (nowMs >= end) {
    return {
      ok: false,
      code: 'failed-precondition',
      message: `후기는 파티가 끝난 뒤 ${REVIEW_WINDOW_DAYS}일 안에만 쓸 수 있어요.`,
    };
  }

  return { ok: true, windowEndMs: end };
}

/** 요청에서 uid를 꺼낸다. */
function requireAuth(request) {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
  }
  return request.auth.uid;
}

/** 문자열 파라미터 하나 — 비었거나 너무 길면 거절. */
function readId(value, label) {
  if (typeof value !== 'string' || !value.trim() || value.length > 200) {
    throw new HttpsError('invalid-argument', `${label}가 올바르지 않습니다.`);
  }
  return value.trim();
}

// ── 작성·수정 ───────────────────────────────────────────────────────────────

/**
 * 후기 작성 또는 수정. 같은 신청 건에 다시 부르면 **덮어쓴다**(문서 id가
 * 결정적이라 중복 문서가 생길 수 없다).
 *
 * data: { partyId, occurrenceId?, text }
 */
exports.submitPartyReview = onCall({ region: REGION }, async (request) => {
  const uid = requireAuth(request);
  const partyId = readId(request.data && request.data.partyId, '파티 정보');
  const occurrenceId =
    request.data && request.data.occurrenceId
      ? readId(request.data.occurrenceId, '회차 정보')
      : null;

  const normalized = normalizeReviewText(request.data && request.data.text);
  if (!normalized.ok) {
    throw new HttpsError('invalid-argument', normalized.reason);
  }

  const db = admin.firestore();
  // 신청 문서 id는 서버가 만든다 — 앱이 보낸 id를 그대로 쓰면 남의 신청서를
  // 가리킬 수 있다. 규칙은 partyCapacity.applicationDocId 하나뿐이다.
  const applicationId = applicationDocId(uid, occurrenceId);
  const appRef = db
    .collection('parties')
    .doc(partyId)
    .collection('applications')
    .doc(applicationId);

  const [appSnap, partySnap] = await Promise.all([
    appRef.get(),
    db.collection('parties').doc(partyId).get(),
  ]);

  const app = appSnap.exists ? appSnap.data() : null;
  const partyData = partySnap.exists ? partySnap.data() : null;

  const verdict = judgeEligibility(app, partyData, uid, Date.now());
  if (!verdict.ok) throw new HttpsError(verdict.code, verdict.message);

  // 공개 표시용 작성자 정보는 **닉네임 하나뿐**이다. 실명(users.name)은
  // 본인확인으로 확인된 값이라 호스트에게만 나가는 정보이고(applicantIdentity.js),
  // 후기는 누구나 보는 자리라 절대 여기 실으면 안 된다.
  const userSnap = await db.collection('users').doc(uid).get();
  const u = userSnap.exists ? userSnap.data() : {};
  const nickname = (u.nickname || '').trim() || '참여자';

  const ref = db.collection(COLLECTION).doc(reviewDocId(partyId, applicationId));
  const existing = await ref.get();

  await ref.set(
    {
      partyId,
      applicationId,
      occurrenceId: occurrenceId || null,
      authorUid: uid,
      // 표시용 스냅샷 — 나중에 닉네임을 바꿔도 옛 후기가 깨지지 않는다.
      authorNickname: nickname,
      text: normalized.text,
      // 파티가 자동삭제된 뒤에도 후기 한 줄을 그릴 수 있게 하는 최소 스냅샷.
      hostId: (partyData && partyData.hostId) || app.hostId || null,
      partyTitle:
        ((partyData && partyData.title) || '').trim() || '(삭제된 파티)',
      occurrenceStartAt: app.occurrenceStartAt || app.partyDateTime || null,
      // 앱이 "언제까지 고칠 수 있는지"를 다시 계산하지 않아도 되게 박아 둔다.
      reviewWindowEndsAt: admin.firestore.Timestamp.fromMillis(
        verdict.windowEndMs,
      ),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...(existing.exists
        ? {}
        : { createdAt: admin.firestore.FieldValue.serverTimestamp() }),
    },
    { merge: true },
  );

  return { reviewId: ref.id, updated: existing.exists };
});

// ── 삭제 ────────────────────────────────────────────────────────────────────

/**
 * 본인 후기 삭제. 작성 기간 안에서만 가능하다.
 *
 * 관리자 삭제는 이 경로가 아니라 firestore.rules의 `allow delete: if isAdmin()`
 * 으로 처리한다(신고 처리 흐름과 같은 자리 — 기존 UGC 관리 정책 그대로).
 */
exports.deletePartyReview = onCall({ region: REGION }, async (request) => {
  const uid = requireAuth(request);
  const reviewId = readId(request.data && request.data.reviewId, '후기 정보');

  const db = admin.firestore();
  const ref = db.collection(COLLECTION).doc(reviewId);
  const snap = await ref.get();
  if (!snap.exists) return { deleted: false };

  const review = snap.data();
  if (review.authorUid !== uid) {
    // 호스트도 여기서 막힌다 — 자기 파티의 후기라도 지울 수 없다.
    throw new HttpsError('permission-denied', '본인이 쓴 후기만 삭제할 수 있어요.');
  }

  const endMs = toMs(review.reviewWindowEndsAt);
  if (endMs !== null && Date.now() >= endMs) {
    throw new HttpsError(
      'failed-precondition',
      `후기는 작성 기간(${REVIEW_WINDOW_DAYS}일) 안에만 삭제할 수 있어요.`,
    );
  }

  await ref.delete();
  return { deleted: true };
});

// 자기검증용 export — partyReviews.selfcheck.js가 쓴다.
module.exports.__test = {
  COLLECTION,
  REVIEW_WINDOW_DAYS,
  REVIEW_WINDOW_MS,
  MIN_LENGTH,
  MAX_LENGTH,
  reviewDocId,
  normalizeReviewText,
  occurrenceEndMsOf,
  windowEndMs,
  judgeEligibility,
};

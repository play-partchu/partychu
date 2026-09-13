const admin = require('firebase-admin');

// 통합 회원 관리 공용 헬퍼 — 순수 함수만 모아둔 파일. partyCapacity.js와
// 동일한 컨벤션: Cloud Functions(onCall/onDocumentCreated 등)를 전혀 export
// 하지 않으므로, index.js/memberManagement.js는 이 파일을
// `Object.assign(exports, require(...))`가 아니라 항상 구조분해로만 가져다
// 쓴다 — 그래야 배포 대상(Cloud Functions) 목록에 순수 헬퍼가 섞이지 않는다.

async function logUserActivity(db, {
  uid,
  activityType,
  refCollection = null,
  refId = null,
  actorType = 'system',
  actorUid = null,
  extra = null,
}) {
  if (!uid || !activityType) return;
  await db.collection('userActivityLogs').add({
    uid,
    activityType,
    refCollection,
    refId,
    actorType,
    actorUid,
    extra,
    occurredAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

async function addActivityRole(db, uid, role) {
  if (!uid || !role) return;
  await db.collection('users').doc(uid).set(
    { activityRoles: admin.firestore.FieldValue.arrayUnion(role) },
    { merge: true }
  );
}

// 테스트 계정 여부 조회 — parties/places 등 생성 트리거가 실사용자 KPI에
// 테스트 계정 활동을 섞지 않으려고 host/actor의 isTestAccount를 먼저 확인할
// 때 쓴다. 문서가 없거나 필드가 없으면 안전하게 false(실사용자 취급).
async function isTestAccountUid(db, uid) {
  if (!uid) return false;
  const snap = await db.collection('users').doc(uid).get();
  return snap.exists && snap.data().isTestAccount === true;
}

/**
 * userStats 카운터 갱신 — 모든 회원 통계가 여기 한 곳을 거친다.
 *
 * ── 매출·정산 집계 규칙 (반드시 지킬 것) ────────────────────────────────────
 * **금액 계열(cumulativePaymentAmount 등)은 예약/신청/주문의 진행 상태가 아니라
 * `payment.status === 'paid'`로 넘어가는 전이에만 반영한다.**
 *
 * 무통장입금이 붙으면서 진행 상태와 결제 상태는 완전히 다른 축이 됐다 —
 * 예약이 '확정'(confirmed)이어도 입금대기·입금확인중·현장결제 예정이면 아직
 * 받은 돈이 없다. 확정 시점에 금액을 세면 입금 없이 만료될 건까지 매출로
 * 잡히고, 그 숫자로 정산하면 실제로 들어오지 않은 돈을 지급하게 된다.
 *
 * 건수 계열(totalPlaceReservationsAsHost 등)은 지금처럼 확정 시점에 세도 된다 —
 * "몇 건이 잡혔나"는 돈과 다른 질문이기 때문이다.
 *
 * 판정은 [becamePaid](memberManagement.js)를 쓴다. payment 맵이 없는 옛 문서
 * (포트원 흐름)는 그때 confirmed가 곧 결제완료였으므로 예전 규칙을 유지한다.
 */
async function bumpUserStats(db, uid, patch) {
  if (!uid) return;
  await db.collection('userStats').doc(uid).set(
    { ...patch, updatedAt: admin.firestore.FieldValue.serverTimestamp() },
    { merge: true }
  );
}

// 찜 대상 타입 → 실제로 hostId를 갖고 있는 컬렉션. onFavoriteWrite(index.js)가
// 호출해 "이 항목을 등록한 사람"의 받은 찜 수를 올린다.
const FAVORITE_TYPE_TO_COLLECTION = {
  party: 'parties',
  place: 'places',
  shop: 'partyShops',
  crew: 'crews',
};

async function bumpFavoriteReceivedCount(db, type, itemId) {
  const coll = FAVORITE_TYPE_TO_COLLECTION[type];
  if (!coll || !itemId) return;
  const snap = await db.collection(coll).doc(itemId).get();
  const hostId = snap.exists ? snap.data().hostId : null;
  if (!hostId) return;
  await bumpUserStats(db, hostId, {
    totalFavoritesReceived: admin.firestore.FieldValue.increment(1),
  });
}

// 스케줄 함수 실패 기록 — Cloud Logging에는 이미 남지만(gcloud로만 조회
// 가능), 관리자 웹에서도 바로 확인할 수 있도록 Firestore에도 남긴다.
// 함수 전체가 예외로 죽은 경우든(top-level catch), 개별 문서 처리 중
// 일부만 실패한 경우든(예: expireStalePackageBookings의 문서별 catch)
// 동일하게 이 헬퍼로 남긴다.
async function logScheduledFunctionError(db, functionName, error, context = null) {
  try {
    await db.collection('systemFunctionErrors').add({
      functionName,
      message: error && error.message ? String(error.message) : String(error),
      stack: error && error.stack ? String(error.stack).slice(0, 2000) : null,
      context: context || null,
      occurredAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (e) {
    // 오류 기록 자체가 실패해도 원래 함수 흐름을 막지 않는다 — 콘솔 로그로만 남김.
    console.error(`[logScheduledFunctionError] ${functionName} 오류 기록 실패`, e);
  }
}

module.exports = {
  logUserActivity,
  addActivityRole,
  bumpUserStats,
  bumpFavoriteReceivedCount,
  logScheduledFunctionError,
  isTestAccountUid,
};

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

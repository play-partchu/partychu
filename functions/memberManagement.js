const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentCreated, onDocumentWritten } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');
const { logUserActivity, addActivityRole, bumpUserStats } = require('./memberActivityHelpers');

// 통합 회원 관리 — 관리자 웹의 회원 목록/상세 페이지가 매번 여러 컬렉션을
// 반복 조회하지 않도록, 실제 활동이 일어나는 시점(파티/플레이스/상품/크루
// 등록, 예약·구매, 찜 등)마다 이 파일의 트리거가 userStats(집계 수치)와
// users.activityRoles(활동 배지)를 미리 갱신하고, userActivityLogs(통합
// 활동 타임라인)에 로그를 남긴다. 기존 결제/환불 트랜잭션(placeReservations.js,
// packageBookings.js)은 전혀 건드리지 않고, 그 결과로 만들어진 문서의 쓰기에
// 반응만 한다 — 결제 로직과 완전히 분리되어 있어 안전하다.
//
// 이 파일은 Cloud Functions(트리거/onCall)만 export한다 — 공용 헬퍼는
// memberActivityHelpers.js에 따로 두고 구조분해로만 가져다 쓴다(index.js도
// 같은 이유로 이 헬퍼들을 memberActivityHelpers.js에서 직접 가져온다).
//
// 이번 범위에서 항상 0/자리만 있는 것: 크루 지원("구직 지원")과 신고는 앱에
// 기능 자체가 없어 트리거도, activityType도 실제로 발생하지 않는다(필드/
// enum 값만 예약해두고, 나중에 해당 기능이 생기면 여기 로직만 추가하면 됨).

const REGION = 'asia-northeast3';

// ── 파티샵 상품 등록 ─────────────────────────────────────────────────────────
exports.onProductCreated = onDocumentCreated(
  { document: 'partyShops/{shopId}/products/{productId}', region: REGION },
  async (event) => {
    const data = event.data?.data();
    const hostId = data?.hostId;
    if (!hostId) return;
    const db = admin.firestore();
    await bumpUserStats(db, hostId, {
      totalProductsRegistered: admin.firestore.FieldValue.increment(1),
    });
    await addActivityRole(db, hostId, 'shop_seller');
    await logUserActivity(db, {
      uid: hostId,
      activityType: 'product_registered',
      refCollection: 'products',
      refId: event.params.productId,
    });
  }
);

// ── 크루 공고 등록(구인/구직 — crewType 필드로 구분) ─────────────────────────
exports.onCrewCreated = onDocumentCreated(
  { document: 'crews/{crewId}', region: REGION },
  async (event) => {
    const data = event.data?.data();
    const hostId = data?.hostId;
    if (!hostId) return;
    const db = admin.firestore();
    const role = data.crewType === '구인' ? 'crew_recruiting' : 'crew_seeking';
    await bumpUserStats(db, hostId, {
      totalCrewPostings: admin.firestore.FieldValue.increment(1),
    });
    await addActivityRole(db, hostId, role);
    await logUserActivity(db, {
      uid: hostId,
      activityType: 'crew_posted',
      refCollection: 'crews',
      refId: event.params.crewId,
      extra: { crewType: data.crewType || null },
    });
  }
);

// ── 파티샵 주문 — orders는 더미(테스트용) 결제 경로라 건수만 집계하고
// 금액(cumulativePaymentAmount)은 절대 반영하지 않는다.
exports.onOrderCreated = onDocumentCreated(
  { document: 'orders/{orderId}', region: REGION },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    const db = admin.firestore();
    const { buyerId, sellerId } = data;
    if (buyerId) {
      await bumpUserStats(db, buyerId, {
        totalProductPurchases: admin.firestore.FieldValue.increment(1),
      });
      await logUserActivity(db, {
        uid: buyerId,
        activityType: 'product_purchased',
        refCollection: 'orders',
        refId: event.params.orderId,
      });
    }
    if (sellerId) {
      await bumpUserStats(db, sellerId, {
        totalProductSales: admin.firestore.FieldValue.increment(1),
      });
      await logUserActivity(db, {
        uid: sellerId,
        activityType: 'product_sold',
        refCollection: 'orders',
        refId: event.params.orderId,
      });
    }
  }
);

// ── 장소 예약(placeReservationGroups) 상태 전이 ──────────────────────────────
// placeReservations.js의 결제 트랜잭션은 건드리지 않고, 그 결과 문서 쓰기에만
// 반응한다. 이 컬렉션은 취소 시 환불 필드가 없어(placeReservations.js 확인)
// cumulativeRefundAmount는 여기서 절대 증가시키지 않는다.
exports.onPlaceReservationGroupWrite = onDocumentWritten(
  { document: 'placeReservationGroups/{groupId}', region: REGION },
  async (event) => {
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.exists ? event.data.after.data() : null;
    if (!after) return;
    const prevStatus = before?.status;
    const newStatus = after.status;
    if (prevStatus === newStatus) return;

    const db = admin.firestore();
    const groupId = event.params.groupId;
    const { requesterId, hostId, totalPrice } = after;

    if (newStatus === 'confirmed') {
      if (requesterId) {
        await bumpUserStats(db, requesterId, {
          totalPlaceReservationsAsGuest: admin.firestore.FieldValue.increment(1),
        });
        await logUserActivity(db, {
          uid: requesterId,
          activityType: 'place_reservation_confirmed',
          refCollection: 'placeReservationGroups',
          refId: groupId,
        });
      }
      if (hostId) {
        await bumpUserStats(db, hostId, {
          totalPlaceReservationsAsHost: admin.firestore.FieldValue.increment(1),
          cumulativePaymentAmount: admin.firestore.FieldValue.increment(Number(totalPrice) || 0),
        });
        await logUserActivity(db, {
          uid: hostId,
          activityType: 'place_reservation_confirmed',
          refCollection: 'placeReservationGroups',
          refId: groupId,
        });
      }
    } else if (newStatus === 'cancelled') {
      if (requesterId) {
        await logUserActivity(db, {
          uid: requesterId,
          activityType: 'place_reservation_cancelled',
          refCollection: 'placeReservationGroups',
          refId: groupId,
        });
      }
      if (hostId) {
        await logUserActivity(db, {
          uid: hostId,
          activityType: 'place_reservation_cancelled',
          refCollection: 'placeReservationGroups',
          refId: groupId,
        });
      }
    }
  }
);

// ── 숙박+파티 패키지 예약(packageBookings) 상태 전이 ─────────────────────────
// 이쪽은 refundAmount 필드가 있어(packageBookings.js 확인) 취소 시 실제
// 환불액을 cumulativeRefundAmount에 반영한다.
exports.onPackageBookingWrite = onDocumentWritten(
  { document: 'packageBookings/{bookingId}', region: REGION },
  async (event) => {
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.exists ? event.data.after.data() : null;
    if (!after) return;
    const prevStatus = before?.status;
    const newStatus = after.status;
    if (prevStatus === newStatus) return;

    const db = admin.firestore();
    const bookingId = event.params.bookingId;
    const { requesterId, hostId, totalPrice, refundAmount } = after;

    if (newStatus === 'confirmed') {
      if (requesterId) {
        await bumpUserStats(db, requesterId, {
          totalPackageBookingsAsGuest: admin.firestore.FieldValue.increment(1),
        });
        await logUserActivity(db, {
          uid: requesterId,
          activityType: 'package_booking_confirmed',
          refCollection: 'packageBookings',
          refId: bookingId,
        });
      }
      if (hostId) {
        await bumpUserStats(db, hostId, {
          totalPackageBookingsAsHost: admin.firestore.FieldValue.increment(1),
          cumulativePaymentAmount: admin.firestore.FieldValue.increment(Number(totalPrice) || 0),
        });
        await logUserActivity(db, {
          uid: hostId,
          activityType: 'package_booking_confirmed',
          refCollection: 'packageBookings',
          refId: bookingId,
        });
      }
    } else if (newStatus === 'cancelled') {
      const refund = Number(refundAmount) || 0;
      if (hostId && refund > 0) {
        await bumpUserStats(db, hostId, {
          cumulativeRefundAmount: admin.firestore.FieldValue.increment(refund),
        });
      }
      if (requesterId) {
        await logUserActivity(db, {
          uid: requesterId,
          activityType: 'package_booking_cancelled',
          refCollection: 'packageBookings',
          refId: bookingId,
          extra: { refundAmount: refund },
        });
      }
      if (hostId) {
        await logUserActivity(db, {
          uid: hostId,
          activityType: 'package_booking_cancelled',
          refCollection: 'packageBookings',
          refId: bookingId,
          extra: { refundAmount: refund },
        });
      }
    }
  }
);

// ── 파티 문서 수정/삭제 활동 로그 ────────────────────────────────────────────
// index.js의 onPartyCancelledByHost(환불 처리 전담)와는 완전히 별개의
// 트리거다 — 같은 문서 경로에 여러 onDocumentWritten이 동시에 붙을 수
// 있으므로, 기존 환불 로직은 전혀 건드리지 않고 순수 로그만 남긴다.
exports.onPartyActivityLog = onDocumentWritten(
  { document: 'parties/{partyId}', region: REGION },
  async (event) => {
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.exists ? event.data.after.data() : null;
    if (!before || !after) return; // 생성은 onPartyCreated가 처리, 문서 자체 삭제는 다루지 않음
    const hostId = after.hostId;
    if (!hostId) return;
    const db = admin.firestore();
    const partyId = event.params.partyId;

    if (before.isDeleted !== true && after.isDeleted === true) {
      await logUserActivity(db, {
        uid: hostId, activityType: 'party_deleted', refCollection: 'parties', refId: partyId,
      });
      return;
    }
    if (before.recruitStatus !== '취소' && after.recruitStatus === '취소') {
      await logUserActivity(db, {
        uid: hostId, activityType: 'party_cancelled', refCollection: 'parties', refId: partyId,
      });
      return;
    }
    // 신청 접수/승인 처리로 바뀌는 필드(applicants·인원 카운터)만 바뀐 건
    // "파티 수정"으로 남기지 않는다 — 신청이 들어올 때마다 호스트 타임라인에
    // 노이즈가 찍히는 걸 막기 위함.
    const ignoredKeys = ['applicants', 'currentParticipants', 'currentMaleCount', 'currentFemaleCount'];
    const changedKeys = Object.keys(after).filter(
      (k) => JSON.stringify(after[k]) !== JSON.stringify(before[k])
    );
    const onlyIgnored = changedKeys.length > 0 && changedKeys.every((k) => ignoredKeys.includes(k));
    if (changedKeys.length > 0 && !onlyIgnored) {
      await logUserActivity(db, {
        uid: hostId, activityType: 'party_updated', refCollection: 'parties', refId: partyId,
      });
    }
  }
);

// ── 로그인 시점 기록 ─────────────────────────────────────────────────────────
// 앱 재실행 시 세션이 복원되기만 해도 갱신되는 기존 users.lastActiveAt과
// 달리, 이 함수는 실제로 로그인 버튼을 눌러 성공했을 때만(party_app의
// login.dart _onLoginSuccess) 호출된다.
exports.recordLogin = onCall({ region: REGION }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
  }
  const uid = request.auth.uid;
  const db = admin.firestore();
  await db.collection('users').doc(uid).set(
    { lastLoginAt: admin.firestore.FieldValue.serverTimestamp() },
    { merge: true }
  );
  await logUserActivity(db, { uid, activityType: 'login', actorType: 'user' });
  return { success: true };
});

// ── 관리자: 특정 회원의 신청 내역 조회 ───────────────────────────────────────
// parties/{partyId}/applications 컬렉션 그룹의 보안 규칙(get()으로 파티
// 문서의 hostId를 조회하는 조건 포함)은 클라이언트가 이 컬렉션 그룹을 직접
// 쿼리하는 걸 막는다(index.js의 getApplicants 도입 배경과 동일한 제약 —
// party_applicants_screen.dart도 같은 이유로 클라이언트 직접 쿼리 대신 Function
// 호출로 전환했었다). 회원 상세 화면의 "신청·참여 내역"도 같은 제약에 걸리므로
// Admin SDK로 우회 조회한다.
exports.adminGetUserApplications = onCall({ region: REGION }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
  }
  const db = admin.firestore();
  const callerSnap = await db.collection('users').doc(request.auth.uid).get();
  if (callerSnap.data()?.role !== 'admin') {
    throw new HttpsError('permission-denied', '관리자만 사용할 수 있습니다.');
  }

  const { targetUid } = request.data || {};
  if (!targetUid || typeof targetUid !== 'string') {
    throw new HttpsError('invalid-argument', 'targetUid가 필요합니다.');
  }

  const snap = await db
    .collectionGroup('applications')
    .where('uid', '==', targetUid)
    .orderBy('appliedAt', 'desc')
    .get();

  const toIso = (v) => (v && typeof v.toDate === 'function' ? v.toDate().toISOString() : null);
  const applications = snap.docs.map((doc) => {
    const d = doc.data();
    return {
      partyId: d.partyId || null,
      status: d.status || null,
      region: d.region || null,
      appliedAt: toIso(d.appliedAt),
      statusUpdatedAt: toIso(d.statusUpdatedAt),
      partyDateTime: toIso(d.partyDateTime),
    };
  });

  return { applications };
});

// ── 관리자: 신청 상태별 건수(대시보드 승인/실제참여/취소/노쇼 수) ───────────
// applications 컬렉션 그룹의 보안 규칙도 위 adminGetUserApplications과 같은
// 이유(문서마다 다른 partyId로 get() 호출)로 클라이언트의 직접 쿼리를
// 막으므로, 이 집계도 반드시 Admin SDK로 우회 조회해야 한다.
const APPLICATION_STATUS_VALUES = ['applied', 'approved', 'attended', 'cancelled', 'rejected', 'no_show'];

exports.adminGetApplicationStatusCount = onCall({ region: REGION }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
  }
  const db = admin.firestore();
  const callerSnap = await db.collection('users').doc(request.auth.uid).get();
  if (callerSnap.data()?.role !== 'admin') {
    throw new HttpsError('permission-denied', '관리자만 사용할 수 있습니다.');
  }

  const { status } = request.data || {};
  if (!APPLICATION_STATUS_VALUES.includes(status)) {
    throw new HttpsError('invalid-argument', 'status 값이 올바르지 않습니다.');
  }

  // count() 집계 쿼리는 복합 인덱스의 선행 필드(prefix)만으로는 실행되지
  // 않고, 인덱스 필드 순서와 정확히 일치하는 orderBy가 있어야 한다(이미
  // 배포된 status+appliedAt 복합 인덱스를 그대로 타도록 orderBy를 맞춘다).
  // isTestAccount==false는 onApplicationStatusWrite가 신청 문서 생성 시
  // 항상 채워두므로(테스트 계정 실사용자 판별과 동일한 원리), 실사용자
  // 신청만 센다.
  const snap = await db
    .collectionGroup('applications')
    .where('status', '==', status)
    .where('isTestAccount', '==', false)
    .orderBy('appliedAt', 'desc')
    .count()
    .get();

  return { count: snap.data().count };
});

// ── 관리자: 계정 상태/메모/테스트계정 변경 ───────────────────────────────────
// Admin SDK로 처리해 firestore.rules에 새 예외를 만들지 않고, 변경+감사로그를
// 한 번의 호출로 묶는다(packageBookings.js/placeReservations.js가 이미 쓰는
// "민감한 상태 전이는 onCall로만" 패턴과 동일).
const ACCOUNT_STATUS_VALUES = ['active', 'dormant', 'restricted', 'withdrawn'];

exports.adminUpdateMember = onCall({ region: REGION }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
  }
  const callerUid = request.auth.uid;
  const db = admin.firestore();
  const callerSnap = await db.collection('users').doc(callerUid).get();
  if (callerSnap.data()?.role !== 'admin') {
    throw new HttpsError('permission-denied', '관리자만 사용할 수 있습니다.');
  }

  const { targetUid, accountStatus, accountStatusReason, adminMemo, isTestAccount } = request.data || {};
  if (!targetUid || typeof targetUid !== 'string') {
    throw new HttpsError('invalid-argument', 'targetUid가 필요합니다.');
  }

  const patch = {};
  let statusChanged = false;
  let memoChanged = false;

  if (accountStatus !== undefined) {
    if (!ACCOUNT_STATUS_VALUES.includes(accountStatus)) {
      throw new HttpsError('invalid-argument', 'accountStatus 값이 올바르지 않습니다.');
    }
    patch.accountStatus = accountStatus;
    patch.accountStatusUpdatedAt = admin.firestore.FieldValue.serverTimestamp();
    patch.accountStatusUpdatedBy = callerUid;
    patch.accountStatusReason = accountStatusReason || null;
    statusChanged = true;
  }
  if (adminMemo !== undefined) {
    patch.adminMemo = String(adminMemo);
    patch.adminMemoUpdatedAt = admin.firestore.FieldValue.serverTimestamp();
    patch.adminMemoUpdatedBy = callerUid;
    memoChanged = true;
  }
  if (isTestAccount !== undefined) {
    patch.isTestAccount = Boolean(isTestAccount);
  }

  if (Object.keys(patch).length === 0) {
    throw new HttpsError('invalid-argument', '변경할 값이 없습니다.');
  }

  await db.collection('users').doc(targetUid).set(patch, { merge: true });

  if (statusChanged) {
    await logUserActivity(db, {
      uid: targetUid,
      activityType: 'admin_status_changed',
      actorType: 'admin',
      actorUid: callerUid,
      extra: { accountStatus, accountStatusReason: accountStatusReason || null },
    });
  }
  if (memoChanged) {
    await logUserActivity(db, {
      uid: targetUid,
      activityType: 'admin_memo_updated',
      actorType: 'admin',
      actorUid: callerUid,
    });
  }

  return { success: true };
});

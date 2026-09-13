const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentCreated, onDocumentWritten } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');
const { logUserActivity, addActivityRole, bumpUserStats } = require('./memberActivityHelpers');
// "1명의 실사용자 = 파티츄 계정 1개" 정책의 CI 링크 관리 (identityLink.js)
const {
  backfillIdentityLinks,
  releaseIdentityLink,
  reactivateIdentityLink,
  RELEASE_COOLDOWN_DAYS,
} = require('./identityLink');

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

/**
 * 이번 쓰기에서 **돈이 실제로 들어온 순간**인지.
 *
 * 무통장입금이 붙으면서 `status: 'confirmed'`는 "자리 확정"만 뜻하게 됐다 —
 * 확정이어도 입금대기·입금확인중·현장결제 예정이면 아직 받은 돈이 없다. 그래서
 * 매출 누적(cumulativePaymentAmount)은 status가 아니라 **payment.status가
 * 'paid'로 넘어가는 전이**에만 반응해야 한다.
 *
 * payment 맵이 아예 없는 문서는 옛 포트원 흐름이라 confirmed가 곧 결제완료였다 —
 * 그때는 예전처럼 확정 시점에 센다.
 */
function becamePaid(before, after) {
  if (!after.payment) {
    return before?.status !== 'confirmed' && after.status === 'confirmed';
  }
  return before?.payment?.status !== 'paid' && after.payment.status === 'paid';
}

// 자기검증용 export — packageBookings.selfcheck.js가 매출 집계 규칙을,
// partyActivityLog.selfcheck.js가 "호스트 수정 vs 시스템 카운터" 판정을 확인한다.
// (isHostContentEdit는 아래에서 정의된 뒤 같은 객체에 덧붙인다.)
module.exports.__test = { becamePaid };

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

    const db = admin.firestore();
    const groupId = event.params.groupId;
    const { requesterId, hostId, totalPrice } = after;

    // 매출 누적은 입금이 확인된 순간에만 — status 전이와 별개로 판정한다
    // (입금 확인은 status를 바꾸지 않으므로 아래 분기에 걸리지 않는다).
    if (hostId && becamePaid(before, after)) {
      await bumpUserStats(db, hostId, {
        cumulativePaymentAmount: admin.firestore.FieldValue.increment(Number(totalPrice) || 0),
      });
    }

    const prevStatus = before?.status;
    const newStatus = after.status;
    if (prevStatus === newStatus) return;

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

    const db = admin.firestore();
    const bookingId = event.params.bookingId;
    const { requesterId, hostId, totalPrice, refundAmount } = after;

    // 장소대여와 같은 이유로, 매출은 입금이 확인된 순간에만 센다.
    if (hostId && becamePaid(before, after)) {
      await bumpUserStats(db, hostId, {
        cumulativePaymentAmount: admin.firestore.FieldValue.increment(Number(totalPrice) || 0),
      });
    }

    const prevStatus = before?.status;
    const newStatus = after.status;
    if (prevStatus === newStatus) return;

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

// 신청/승인/취소/입금만료로 **서버가 자동으로 바꾸는** 파티 필드.
//
// 목록의 근거는 partyCapacity.js의 reserveApplicantSlot/releaseApplicantSlot이
// 돌려주는 updateData다 — applyToParty · cancelApplication ·
// createPendingPackageBooking · cancelPackageBooking · expirePartyDeposits ·
// applyBundleRelease가 파티 문서를 건드릴 때 전부 그 한 쌍만 쓴다. 거기서
// 쓰이는 최상단 필드가 곧 여기 있어야 할 필드이고, 하나라도 빠지면 신청 한
// 건마다 호스트 타임라인에 party_updated가 남는다.
//
// maxParticipants/maxCapacity는 일부러 넣지 않는다 — 서버가 다시 쓰긴 하지만
// 값은 차수 정원의 합이라 신청/취소로는 변하지 않고, 실제로 값이 달라졌다면
// 그건 호스트가 정원을 고친 것이다.
const SYSTEM_MANAGED_PARTY_KEYS = new Set([
  // 신청자 명단 — 취소가 approved/rejected 배열에서도 uid를 뺀다.
  'applicants',
  'approvedApplicants',
  'rejectedApplicants',
  // 인원 카운터
  'currentParticipants',
  'currentMaleCount',
  'currentFemaleCount',
  // "3/10명" 표시 문자열 — 위 카운터에서 파생된 값이라 인원이 바뀌면 같이 바뀐다.
  'people',
  // 정기 파티의 회차별 칸(인원·신청자 명단·차수 카운터). 서버만 쓴다
  // (party_slot_sync_service.dart의 perDateStateKeys 주석 참고).
  'occurrenceStats',
  // onPartyCreated가 생성 직후 문서에 찍는 표식(index.js). 이게 빠져 있으면
  // 파티를 만들 때마다 party_created 바로 뒤에 party_updated가 한 건 더 남는다
  // — 호스트가 아무것도 고치지 않았는데 "수정함"으로 보인다. 앱은 파티 문서의
  // 이 필드를 쓰지 않는다(서버 전용 표식).
  'isTestAccount',
]);

// rounds[] 안에서 서버가 올리는 인원 칸. 나머지(라벨·시간·정원·참가비)는
// 호스트가 고치는 차수 정의다.
const ROUND_COUNTER_KEYS = ['currentParticipants', 'currentMaleCount', 'currentFemaleCount'];

function roundsWithoutCounters(rounds) {
  if (!Array.isArray(rounds)) return rounds;
  return rounds.map((r) => {
    if (!r || typeof r !== 'object') return r;
    const rest = { ...r };
    for (const k of ROUND_COUNTER_KEYS) delete rest[k];
    return rest;
  });
}

/**
 * 이번 쓰기가 **호스트가 파티 내용을 고친 것**인지 판정한다.
 *
 * 시스템이 자동으로 바꾸는 필드(위 목록)만 달라졌으면 false —
 * 제목·설명·날짜·장소·가격·환불정책처럼 호스트가 만지는 값이 하나라도
 * 달라졌으면 true다.
 *
 * rounds[]는 호스트가 고치는 "차수 정의"와 서버가 올리는 "차수 인원"이 한
 * 배열에 섞여 있다. 통째로 무시하면 호스트의 차수 수정이 안 남고, 그대로
 * 비교하면 차수 파티는 신청마다 로그가 남는다 — 인원 칸만 걷어내고 비교해서
 * 둘을 가른다.
 */
function isHostContentEdit(before, after) {
  if (!before || !after) return false;
  const unchanged = (k) =>
    k === 'rounds'
      ? JSON.stringify(roundsWithoutCounters(after[k])) ===
        JSON.stringify(roundsWithoutCounters(before[k]))
      : JSON.stringify(after[k]) === JSON.stringify(before[k]);

  // 지워진 필드도 변경이다 — after의 키만 훑으면 삭제를 통째로 놓친다.
  const allKeys = new Set([...Object.keys(before), ...Object.keys(after)]);
  for (const k of allKeys) {
    if (SYSTEM_MANAGED_PARTY_KEYS.has(k)) continue;
    if (!unchanged(k)) return true;
  }
  return false;
}

module.exports.__test.isHostContentEdit = isHostContentEdit;
module.exports.__test.SYSTEM_MANAGED_PARTY_KEYS = SYSTEM_MANAGED_PARTY_KEYS;

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
    // 신청/승인/취소/입금만료로 서버가 자동으로 바꾸는 필드만 달라진 쓰기는
    // "파티 수정"으로 남기지 않는다(isHostContentEdit 참고).
    if (isHostContentEdit(before, after)) {
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
// 'attended'는 레거시다 — 그 상태를 쓰는 코드가 서버·앱 어디에도 없어 이
// 집계는 언제나 0이었다. 옛 문서를 세어 볼 수 있게 값은 남겨 둔다.
const APPLICATION_STATUS_VALUES = ['applied', 'approved', 'attended', 'cancelled', 'rejected', 'no_show'];

/**
 * 신청 상태가 아니라 **현장 출석**을 세라는 특별한 값.
 *
 * 실제 출석의 정본은 신청 문서의 checkedInAt이다(호스트가 QR을 찍으면
 * partyCheckIn.js가 그 전이에서 통계를 움직인다). 상태 목록에 섞지 않고 따로
 * 둔 이유는 이것이 status 값이 아니기 때문이다 — 관리자 웹도 같은 문자열을
 * 쓴다(admin_app/lib/services/admin_firestore_service.dart).
 */
const CHECKED_IN = 'checked_in';

/** "체크인 시각이 실제로 찍혀 있다"를 뜻하는 하한 — 어떤 체크인보다도 이르다. */
const CHECKED_IN_EPOCH = new Date(0);

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
  if (status !== CHECKED_IN && !APPLICATION_STATUS_VALUES.includes(status)) {
    throw new HttpsError('invalid-argument', 'status 값이 올바르지 않습니다.');
  }

  // ── 실제 현장 출석은 status가 아니라 checkedInAt이다 ──────────────────────
  //
  // "필드가 있는 문서"를 세면 안 된다 — 체크인을 되돌리면 필드가 지워지는 게
  // 아니라 **null이 들어간다**(revokeCheckIn). null도 값이라 존재 검사에는
  // 걸린다. 그래서 시각이 실제로 찍혀 있는지를 부등호로 묻는다.
  if (status === CHECKED_IN) {
    const snap = await db
      .collectionGroup('applications')
      .where('isTestAccount', '==', false)
      .where('checkedInAt', '>', CHECKED_IN_EPOCH)
      .count()
      .get();
    return { count: snap.data().count };
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

  // 탈퇴/복구 시 CI 링크 상태를 함께 옮긴다 — 탈퇴해도 링크를 지우지 않고
  // 'released' + 유예기간(reusableAt)으로만 표시해, 탈퇴 직후 새 계정을 만들어
  // 제재를 세탁하는 경로를 막는다(identityLink.js 참고).
  if (statusChanged) {
    try {
      if (accountStatus === 'withdrawn') {
        const r = await releaseIdentityLink(db, targetUid);
        console.log(`[IdentityLink] 탈퇴 처리 uid=${targetUid} ${JSON.stringify(r)}`);
      } else {
        const r = await reactivateIdentityLink(db, targetUid);
        console.log(`[IdentityLink] 계정 복구 uid=${targetUid} ${JSON.stringify(r)}`);
      }
    } catch (e) {
      // 링크 갱신 실패가 계정 상태 변경 자체를 막지는 않도록 한다 —
      // 링크는 다음 인증 시도 시점에도 다시 판정되기 때문.
      console.error(`[IdentityLink] 링크 상태 갱신 실패 uid=${targetUid}`, e);
    }
  }

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

// ── 관리자: 기존 인증 회원의 CI 링크 일괄 생성 ───────────────────────────────
// 정책 도입 이전에 본인확인을 마친 회원(users.ci만 있고 identityLinks 문서가
// 없는 회원)의 링크 문서를 만들어 둔다. 링크가 없어도 인증 시 users.ci 조회로
// 중복은 막히지만, 링크가 있으면 판정이 문서 1건 조회로 끝난다.
// dryRun: true로 먼저 호출하면 아무것도 쓰지 않고 중복 CI 계정(conflicts)만 보고한다.
exports.backfillIdentityLinks = onCall({ region: REGION }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');

  const db = admin.firestore();
  const callerSnap = await db.collection('users').doc(request.auth.uid).get();
  if (callerSnap.data()?.role !== 'admin') {
    throw new HttpsError('permission-denied', '관리자만 사용할 수 있습니다.');
  }

  const result = await backfillIdentityLinks(db, { dryRun: request.data?.dryRun === true });
  return { ...result, cooldownDays: RELEASE_COOLDOWN_DAYS };
});

// ── 관리자: 탈퇴·재가입 계정 연결 조회 ───────────────────────────────────────
//
// identityLinks는 보안 규칙이 read/write를 모두 막아 둔 컬렉션이다(해시만으로
// "이 CI가 가입돼 있나"를 조회하는 채널이 되면 안 되기 때문). 그래서 관리자
// 웹이 직접 읽을 수 없고, Admin SDK를 거치는 이 함수가 유일한 통로다.
//
// 양방향으로 답한다 — 어느 쪽 uid를 들고 있든 반대편을 찾을 수 있어야 한다.
//   · 현재 계정 uid → users.identityCiHash → 링크의 previousUids (이전 계정들)
//   · 탈퇴 계정 uid → previousUids array-contains 역방향 조회 → 현재 계정
//     (탈퇴 시 identityCiHash가 지워져 정방향으로는 찾을 수 없다)
//
// 본인확인을 마치지 않은 회원은 CI가 없어 링크 문서 자체가 없다 — 추적 불가가
// 정상이며, linked:false로 그 사실을 그대로 돌려준다.
exports.adminGetAccountLinkHistory = onCall({ region: REGION }, async (request) => {
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

  const targetSnap = await db.collection('users').doc(targetUid).get();
  const targetData = targetSnap.exists ? targetSnap.data() : null;

  // ① 정방향 — 아직 CI가 붙어 있는 계정(현역)
  let linkDoc = null;
  const hash = targetData && targetData.identityCiHash;
  if (typeof hash === 'string' && hash !== '') {
    const s = await db.collection('identityLinks').doc(hash).get();
    if (s.exists) linkDoc = { id: s.id, ...s.data() };
  }

  // ② 역방향 — 탈퇴 계정은 identityCiHash가 지워져 ①로는 못 찾는다.
  //    previousUids는 배열 단일 필드라 자동 색인으로 조회된다(복합 색인 불필요).
  if (!linkDoc) {
    const q = await db
      .collection('identityLinks')
      .where('previousUids', 'array-contains', targetUid)
      .limit(1)
      .get();
    if (!q.empty) linkDoc = { id: q.docs[0].id, ...q.docs[0].data() };
  }

  if (!linkDoc) {
    return { linked: false, isRejoined: false, currentUid: null, previous: [] };
  }

  const toIso = (v) => (v && typeof v.toDate === 'function' ? v.toDate().toISOString() : null);

  // 이 CI를 거쳐 간 계정 전부에서 자기 자신만 뺀다.
  const previousUids = Array.isArray(linkDoc.previousUids) ? linkDoc.previousUids : [];
  const others = [...new Set([...previousUids, linkDoc.uid].filter(Boolean))]
    .filter((u) => u !== targetUid);

  // 비석에서 운영에 필요한 값만 읽는다. 개인정보(이름·연락처)는 이미 지워져
  // 있으므로 여기서 더 가릴 것이 없다.
  const previous = [];
  for (let i = 0; i < others.length; i += 10) {
    const refs = others.slice(i, i + 10).map((u) => db.collection('users').doc(u));
    const snaps = await db.getAll(...refs);
    for (const s of snaps) {
      const d = s.exists ? s.data() : {};
      previous.push({
        uid: s.id,
        exists: s.exists,
        accountStatus: d.accountStatus || null,
        createdAt: toIso(d.createdAt),
        withdrawalRequestedAt: toIso(d.withdrawalRequestedAt),
        withdrawnAt: toIso(d.withdrawnAt),
        withdrawnMemberType: d.withdrawnMemberType || null,
        withdrawalReasonCode: d.withdrawalReasonCode || null,
        withdrawnFromStatus: d.withdrawnFromStatus || null,
      });
    }
  }
  previous.sort((a, b) => String(b.withdrawnAt || '').localeCompare(String(a.withdrawnAt || '')));

  return {
    linked: true,
    // 이 CI를 지금 쓰고 있는 계정. status가 released면 아직 아무도 안 가져갔다.
    currentUid: linkDoc.status === 'released' ? null : (linkDoc.uid || null),
    linkStatus: linkDoc.status || null,
    reusableAt: toIso(linkDoc.reusableAt),
    // 이전 계정이 하나라도 있으면 재가입 계정이다.
    isRejoined: previous.length > 0 && linkDoc.status !== 'released',
    previous,
  };
});

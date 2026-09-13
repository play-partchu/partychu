const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');

const { releaseIdentityLink, RELEASE_COOLDOWN_DAYS } = require('./identityLink');
const { revokeDelegationsForGrantee } = require('./businessDelegation');
const { releaseNickname } = require('./nicknames');
const {
  readCloudflareCreds,
  deleteR2Object,
  MEDIA_CLEANUP_SECRETS,
} = require('./cloudflareCleanup');
const { logUserActivity } = require('./memberActivityHelpers');

// ── 회원 탈퇴 ────────────────────────────────────────────────────────────────
//
// 탈퇴는 **두 단계**다. 신청하면 곧바로 지우지 않고 7일간 '탈퇴 대기'로 두고,
// 그 사이에는 서비스를 쓸 수 없지만 본인이 취소할 수 있다. 7일이 지나면 서버가
// 알아서 완전 탈퇴로 넘긴다.
//
// 즉시 지우지 않는 이유는 되돌릴 수 없기 때문이다. 계정 탈취나 홧김에 누른
// 탈퇴를 되살릴 방법이 없으면 그 피해는 전부 사용자가 진다. 반대로 대기 중에도
// 서비스를 계속 쓸 수 있게 두면 "탈퇴했는데 왜 아직 활동이 되냐"는 상태가 되고,
// 대기 중에 새 예약이 생기면 7일 뒤 삭제가 다시 막힌다 — 그래서 대기 = 완전
// 차단이다.
//
// ── 완전 탈퇴의 순서가 고정인 이유 ──────────────────────────────────────────
// 아래 5단계는 순서를 바꾸면 조용히 깨진다. 특히 1번이 2번보다 먼저여야 한다:
// releaseIdentityLink()는 users.identityCiHash / users.ci를 읽어 해시를 구하는데
// (identityLink.js의 resolveCiHash), 그걸 먼저 지우면 'no-ci'로 아무 일도 하지
// 않고 끝나 **30일 재가입 제한이 걸리지 않는다.** 에러도 나지 않아 알아채기
// 어렵다.
//
// ── 30일 재가입 제한의 기준 시각 ────────────────────────────────────────────
// releaseIdentityLink()가 reusableAt을 "호출 시점 + 30일"로 잡는다. 이 함수는
// 7일 대기가 끝난 **완전 탈퇴 시점**에만 불리므로, 재가입 제한은 신청일이 아니라
// 탈퇴가 확정된 날부터 30일이다(대기 7일과 겹치지 않는다). 신청 단계에서 미리
// 링크를 풀지 않는 이유가 이것이다 — 취소할 수 있는 상태에서 링크를 풀면
// 취소하고 돌아온 사용자의 CI가 이미 남에게 넘어가 있을 수 있다.

const REGION = 'asia-northeast3';

/** 탈퇴 신청 후 완전 탈퇴까지의 대기 기간. */
const GRACE_DAYS = 7;

const STATUS_PENDING = 'withdrawal_pending';
const STATUS_WITHDRAWN = 'withdrawn';
const STATUS_ACTIVE = 'active';

// ── 탈퇴 사유 ────────────────────────────────────────────────────────────────
//
// 사유는 **두 갈래로 나눠 저장한다.**
//
//   · 선택형 코드(withdrawalReasonCode) → users 비석에 uid와 함께 남긴다.
//     관리자가 "이 회원이 왜 나갔는지"를 봐야 하고, 코드는 미리 정해진 값
//     중 하나라 그 자체로 새로운 개인정보가 되지 않는다.
//   · 자유서술(reason) → 지금까지처럼 uid 없이 withdrawalReasons에만 쌓는다.
//     사용자가 무엇을 적을지 통제할 수 없어(제3자 이름·연락처·민감한 사정이
//     섞인다) uid에 묶는 순간 수집 범위를 예측할 수 없게 된다.
//
// 이 구분이 "탈퇴 사유를 남긴다"와 "탈퇴자가 쓴 글을 계정에 영구 보관한다"를
// 가르는 선이다.
const WITHDRAWAL_REASON_CODES = [
  'no_longer_use',   // 더 이상 이용하지 않음
  'few_listings',    // 원하는 파티·장소가 없음
  'privacy',         // 개인정보가 걱정됨
  'bad_experience',  // 이용 중 불쾌한 경험
  'app_issue',       // 앱 오류·사용 불편
  'price',           // 비용 부담
  'switch_account',  // 다른 계정으로 옮김
  'other',           // 기타
];

/** 저장해도 되는 사유 코드인가. 목록에 없으면 조용히 버린다(신청 자체는 막지 않는다). */
function normalizeReasonCode(raw) {
  return typeof raw === 'string' && WITHDRAWAL_REASON_CODES.includes(raw) ? raw : null;
}

/**
 * 탈퇴 당시 회원 유형 — 관리자 목록의 "회원 구분" 열이 쓸 값.
 *
 * 사업자 판정 근거는 users.businessVerification 맵이 있느냐 하나뿐인데
 * (관리자 웹 members_screen과 같은 규칙), 그 맵은 완전 탈퇴 때 지워진다.
 * 지우기 **전에** 유형만 뽑아 스칼라로 남겨야 탈퇴자가 전원 '일반회원'으로
 * 보이는 일이 없다. 사업자였다는 사실 자체는 사업자번호·상호와 달리
 * 개인을 특정하지 않으므로 남겨도 되는 값이다.
 */
function memberTypeOf(userData) {
  const bv = userData && userData.businessVerification;
  return bv && typeof bv === 'object' ? 'business' : 'individual';
}

/** 아직 끝나지 않은 거래 — contentCleanup.js와 같은 값을 써야 두 곳이 어긋나지 않는다. */
// 'pending'은 승인제 파티에서 호스트 결정을 기다리는 구간이다 — 진행 중인
// 신청이므로 'applied'/'approved'와 똑같이 탈퇴를 막는다. 여기서 빠지면 승인을
// 기다리던 사람이 그대로 탈퇴해 호스트가 유령 신청을 심사하게 된다.
const LIVE_APPLICATION_STATUSES = ['applied', 'pending', 'approved'];
const LIVE_RESERVATION_STATUSES = ['pending', 'confirmed', 'paid', 'reserved'];
const LIVE_ORDER_STATUSES = ['pending', 'paid', 'confirmed', 'issued'];
const LIVE_REFUND_STATUSES = ['requested', 'pending', 'reviewing', 'approved'];

/**
 * 내가 당사자인 문서를 소유자 필드 하나로만 조회하고 상태는 메모리에서 거른다.
 *
 * `where(owner) + where(status in)` 으로 짜면 컬렉션마다 복합 색인이 필요한데,
 * 한 사람이 가진 문서 수는 많아야 수십 건이라 색인을 늘릴 만한 이득이 없다.
 */
async function countLive(db, collection, ownerField, uid, liveStatuses) {
  try {
    const snap = await db.collection(collection).where(ownerField, '==', uid).get();
    return snap.docs.filter((d) => liveStatuses.includes(d.get('status'))).length;
  } catch (e) {
    // 조회 실패를 '없음'으로 보면 진행 중 거래를 놓친 채 탈퇴가 진행된다.
    // 알 수 없을 때는 막는 쪽이 안전하므로 예외를 그대로 올린다.
    throw new HttpsError('internal', `거래 확인에 실패했습니다(${collection}).`);
  }
}

/** 파티 신청은 parties/{id}/applications 서브컬렉션이라 컬렉션 그룹으로 찾는다. */
async function countLiveApplications(db, uid) {
  const snap = await db.collectionGroup('applications').where('uid', '==', uid).get();
  return snap.docs.filter((d) => LIVE_APPLICATION_STATUSES.includes(d.get('status'))).length;
}

/**
 * 탈퇴를 막아야 하는 이유를 모은다. 비어 있으면 신청할 수 있다.
 *
 * 사용자에게 "탈퇴할 수 없습니다"로만 끝내지 않으려고 종류·건수·이동할 화면을
 * 함께 돌려준다.
 */
async function collectBlockers(db, uid) {
  const blockers = [];
  const add = (kind, count, message, route) => {
    if (count > 0) blockers.push({ kind, count, message, route });
  };

  const [apps, resGroups, visits, packages, productOrders, shopOrders, refunds] =
    await Promise.all([
      countLiveApplications(db, uid),
      countLive(db, 'placeReservationGroups', 'requesterId', uid, LIVE_RESERVATION_STATUSES),
      countLive(db, 'placeVisitReservations', 'requesterId', uid, LIVE_RESERVATION_STATUSES),
      countLive(db, 'packageBookings', 'requesterId', uid, LIVE_RESERVATION_STATUSES),
      countLive(db, 'placeProductOrders', 'buyerId', uid, LIVE_ORDER_STATUSES),
      countLive(db, 'orders', 'buyerId', uid, LIVE_ORDER_STATUSES),
      countLive(db, 'refundRequests', 'requesterId', uid, LIVE_REFUND_STATUSES),
    ]);

  add('application', apps, `진행 중인 파티 신청 ${apps}건`, 'guest_applications');
  add('reservation', resGroups, `진행 중인 장소 예약 ${resGroups}건`, 'guest_reservations');
  add('visit', visits, `진행 중인 방문 예약 ${visits}건`, 'guest_visits');
  add('package', packages, `진행 중인 패키지 예약 ${packages}건`, 'guest_reservations');
  add('order', productOrders + shopOrders, `진행 중인 주문 ${productOrders + shopOrders}건`, 'guest_orders');
  add('refund', refunds, `처리 중인 환불 요청 ${refunds}건`, 'guest_refunds');

  // ── 호스트로서 남은 것 ────────────────────────────────────────────────
  const [hostGroups, hostVisits, hostPackages, hostProducts, hostShop] = await Promise.all([
    countLive(db, 'placeReservationGroups', 'hostId', uid, LIVE_RESERVATION_STATUSES),
    countLive(db, 'placeVisitReservations', 'hostId', uid, LIVE_RESERVATION_STATUSES),
    countLive(db, 'packageBookings', 'hostId', uid, LIVE_RESERVATION_STATUSES),
    countLive(db, 'placeProductOrders', 'hostId', uid, LIVE_ORDER_STATUSES),
    countLive(db, 'orders', 'sellerId', uid, LIVE_ORDER_STATUSES),
  ]);
  const hostTotal = hostGroups + hostVisits + hostPackages + hostProducts + hostShop;
  add('host_reservation', hostTotal, `내 등록물에 진행 중인 예약·주문 ${hostTotal}건`, 'host_hub');

  return blockers;
}

/**
 * 정산 확인이 필요한 계정인가.
 *
 * 정산은 원장 컬렉션 없이 사람이 처리하고 있어서 "받을 돈이 남았는지"를 서버가
 * 계산할 근거가 없다. 계산할 수 없는 값을 추측해서 통과시키면 정산 전에 계정이
 * 사라지고, 그 뒤엔 누구에게 얼마를 보내야 하는지 확인할 방법이 없다. 그래서
 * 호스트였던 적이 있으면 **완전 탈퇴만** 보류하고 운영자 확인을 받는다.
 *
 * 신청 자체를 막지 않는 이유: 사용자는 7일 대기에 들어가 서비스가 차단되므로
 * 새 거래가 생기지 않고, 그 사이 운영자가 정산을 끝낼 수 있다.
 */
function needsSettlementReview(userData) {
  if (!userData) return false;
  if (userData.settlementClearedAt) return false;
  const roles = Array.isArray(userData.activityRoles) ? userData.activityRoles : [];
  return userData.isHost === true || roles.includes('host');
}

// ── 신청 ─────────────────────────────────────────────────────────────────────
exports.requestAccountWithdrawal = onCall({ region: REGION }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
  const uid = request.auth.uid;
  const reason = (request.data && request.data.reason ? String(request.data.reason) : '').slice(0, 500);
  const reasonCode = normalizeReasonCode(request.data && request.data.reasonCode);

  const db = admin.firestore();
  const userRef = db.collection('users').doc(uid);
  const snap = await userRef.get();
  if (!snap.exists) throw new HttpsError('not-found', '회원 정보를 찾을 수 없습니다.');

  const status = snap.get('accountStatus');
  if (status === STATUS_WITHDRAWN) {
    throw new HttpsError('failed-precondition', '이미 탈퇴한 계정입니다.');
  }
  if (status === STATUS_PENDING) {
    return {
      success: true,
      alreadyPending: true,
      scheduledAt: snap.get('withdrawalScheduledAt') || null,
    };
  }

  const blockers = await collectBlockers(db, uid);
  if (blockers.length > 0) {
    return { success: false, blockers };
  }

  const now = Date.now();
  const scheduledAt = admin.firestore.Timestamp.fromDate(
    new Date(now + GRACE_DAYS * 24 * 60 * 60 * 1000),
  );

  await userRef.set(
    {
      accountStatus: STATUS_PENDING,
      accountStatusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      accountStatusUpdatedBy: uid,
      accountStatusReason: '본인 탈퇴 신청',
      withdrawalRequestedAt: admin.firestore.FieldValue.serverTimestamp(),
      withdrawalScheduledAt: scheduledAt,
      // 자유서술 제공 여부만 불리언으로. 본문은 uid 없이 따로 쌓는다(아래).
      withdrawalReasonProvided: reason.length > 0,
      // 선택형 사유 코드는 uid와 함께 남긴다 — 관리자 탈퇴 회원 목록이 읽는 값이다.
      withdrawalReasonCode: reasonCode,
      // ── 탈퇴 직전 계정 상태 ────────────────────────────────────────────
      // 바로 위에서 accountStatus를 'withdrawal_pending'으로 덮어쓰기 때문에,
      // 여기서 붙잡아 두지 않으면 **제재 중이던 회원이 탈퇴했다는 사실이
      // 사라진다.** 완전 탈퇴 시점에는 이미 'withdrawal_pending'이라 그때
      // 기록해서는 늦는다 — 반드시 신청 시점에 남겨야 한다.
      withdrawnFromStatus: status || STATUS_ACTIVE,
    },
    { merge: true },
  );

  if (reason || reasonCode) {
    // uid를 붙이지 않는다. 자유서술에 무엇이 적힐지 통제할 수 없어서, uid에
    // 묶는 순간 수집 범위를 예측할 수 없는 개인정보가 된다. 코드도 함께
    // 넣어두면 이 컬렉션만으로 "코드별 이탈 사유" 집계가 된다.
    await db.collection('withdrawalReasons').add({
      reason: reason || null,
      reasonCode,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  await logUserActivity(db, {
    uid,
    activityType: 'withdrawal_requested',
    actorType: 'user',
    actorUid: uid,
    extra: { graceDays: GRACE_DAYS, reasonCode },
  });

  console.log(`[withdrawal] 신청 uid=${uid} 완료예정=${scheduledAt.toDate().toISOString()}`);
  return { success: true, scheduledAt, graceDays: GRACE_DAYS };
});

// ── 취소 ─────────────────────────────────────────────────────────────────────
exports.cancelAccountWithdrawal = onCall({ region: REGION }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
  const uid = request.auth.uid;

  const db = admin.firestore();
  const userRef = db.collection('users').doc(uid);
  const snap = await userRef.get();
  if (!snap.exists) throw new HttpsError('not-found', '회원 정보를 찾을 수 없습니다.');

  const status = snap.get('accountStatus');
  if (status === STATUS_WITHDRAWN) {
    // 이미 지워진 계정은 되돌릴 수 없다 — 되돌릴 개인정보가 남아 있지 않다.
    throw new HttpsError('failed-precondition', '이미 탈퇴가 완료되어 취소할 수 없습니다.');
  }
  if (status !== STATUS_PENDING) {
    throw new HttpsError('failed-precondition', '탈퇴 대기 상태가 아닙니다.');
  }

  // 취소하면 **탈퇴 신청 직전의 상태로** 돌아간다. 무조건 'active'로 되돌리면
  // 이용제한 중이던 회원이 탈퇴를 신청했다 취소하는 것만으로 제재가 풀린다 —
  // 탈퇴가 제재 세탁 통로가 되면 안 된다. 이 필드가 없는 옛 대기 건은 예전대로
  // 'active'로 돌아간다(하위 호환).
  const restoredStatus = snap.get('withdrawnFromStatus') || STATUS_ACTIVE;

  await userRef.set(
    {
      accountStatus: restoredStatus,
      accountStatusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      accountStatusUpdatedBy: uid,
      accountStatusReason: '본인 탈퇴 취소',
      withdrawalRequestedAt: admin.firestore.FieldValue.delete(),
      withdrawalScheduledAt: admin.firestore.FieldValue.delete(),
      withdrawalReasonProvided: admin.firestore.FieldValue.delete(),
      withdrawalReasonCode: admin.firestore.FieldValue.delete(),
      withdrawnFromStatus: admin.firestore.FieldValue.delete(),
      withdrawalHold: admin.firestore.FieldValue.delete(),
      withdrawalHoldSince: admin.firestore.FieldValue.delete(),
    },
    { merge: true },
  );

  await logUserActivity(db, {
    uid,
    activityType: 'withdrawal_cancelled',
    actorType: 'user',
    actorUid: uid,
  });

  console.log(`[withdrawal] 취소 uid=${uid}`);
  return { success: true };
});

// ── 상태 조회 ────────────────────────────────────────────────────────────────
exports.getAccountWithdrawalStatus = onCall({ region: REGION }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
  const uid = request.auth.uid;

  const db = admin.firestore();
  const snap = await db.collection('users').doc(uid).get();
  if (!snap.exists) throw new HttpsError('not-found', '회원 정보를 찾을 수 없습니다.');

  const status = snap.get('accountStatus') || STATUS_ACTIVE;
  if (status === STATUS_PENDING) {
    return {
      status,
      graceDays: GRACE_DAYS,
      requestedAt: snap.get('withdrawalRequestedAt') || null,
      scheduledAt: snap.get('withdrawalScheduledAt') || null,
      hold: snap.get('withdrawalHold') || null,
      blockers: [],
    };
  }

  // 대기 중이 아니면 지금 신청할 수 있는지까지 함께 돌려준다 — 화면이 진입
  // 시점에 바로 안내할 수 있어야 "눌렀더니 안 된다"가 없다.
  const blockers = await collectBlockers(db, uid);
  return { status, graceDays: GRACE_DAYS, blockers };
});

// ── 완전 탈퇴 ────────────────────────────────────────────────────────────────

/** users 문서에서 지울 개인정보 필드. 남는 건 비석(tombstone)뿐이다. */
const PERSONAL_FIELDS = [
  // 본인확인 원문 — 보존할 법적 근거가 없다.
  'ci', 'di', 'identityCiHash', 'name', 'nameLower',
  'gender', 'birthYear', 'birthMonth', 'birthDay',
  'identityVerified', 'identityVerifiedAt', 'isVerified', 'verifiedAt',
  'verificationProvider', 'phoneNumber',
  // 계정 프로필
  'nickname', 'nicknameLower', 'email', 'emailLower', 'profileImageUrl',
  'address', 'signupProvider', 'provider',
  // 로그인 계정 표시용 소셜 계정 이메일 — socialAuth.js가 로그인마다 기록한다.
  'socialAccount',
  // 금융 — 참가자 환불계좌 · (향후) 플랫폼 정산계좌 · 호스트 수취계좌.
  // 수취계좌는 계좌 원문과 인증 기록을 함께 지운다. 이미 만들어진 신청·주문
  // 문서에는 그때 안내한 계좌 스냅샷이 남지만 그건 거래기록이라 보존 대상이다
  // (payoutAccounts.js · paymentInfo.js 참고).
  'refundAccount', 'settlementInfo', 'settlementAgreed',
  'payoutAccount', 'payoutAccountVerification',
  // 사업자 — 계정에 붙은 프로필성 정보. 거래 문서에는 사업자 정보가 스냅샷으로
  // 들어가지 않으므로(주문·예약 문서 확인) 여기서 지우면 남지 않는다.
  'businessVerification', 'businessName', 'businessNumber',
  'businessAddress', 'businessType', 'businessTypes',
  // 기기/접속
  'deviceId', 'appVersion', 'lastSeenAt',
];

/** uid가 소유자인 개인 데이터 — 거래기록이 아니라서 통째로 지운다. */
const PERSONAL_COLLECTIONS = [
  { name: 'favorites', field: 'userId' },
  { name: 'partyOpenAlerts', field: 'userId' },
  { name: 'drafts', field: 'userId' },
  { name: 'notifications', field: 'uid' },
  { name: 'niceAuthSessions', field: 'uid' },
  { name: 'verificationSessions', field: 'uid' },
];

async function deleteQueryBatched(db, query) {
  const snap = await query.get();
  if (snap.empty) return 0;
  let removed = 0;
  for (let i = 0; i < snap.docs.length; i += 400) {
    const batch = db.batch();
    for (const doc of snap.docs.slice(i, i + 400)) batch.delete(doc.ref);
    await batch.commit();
    removed += Math.min(400, snap.docs.length - i);
  }
  return removed;
}

/** R2 키는 절대 URL로 저장돼 있어 버킷 공개 URL 접두사를 떼어내야 한다. */
function r2KeyFromUrl(url) {
  if (typeof url !== 'string' || !url.includes('/party_images/')) return null;
  const i = url.indexOf('/party_images/');
  return url.slice(i + 1);
}

/**
 * 완전 탈퇴 — 순서가 고정이다(파일 상단 주석 참고).
 *
 * 어느 단계가 실패해도 나머지는 계속 진행한다. 중간에 멈추면 개인정보 일부만
 * 지워진 채로 남고, 다시 부를 방법도 없어 오히려 나쁘다. 실패한 단계는 결과에
 * 담아 돌려주고 로그로 남긴다.
 */
async function completeWithdrawal(db, uid, creds) {
  const result = { uid, steps: {}, errors: [] };
  const step = async (name, fn) => {
    try {
      result.steps[name] = await fn();
    } catch (e) {
      result.steps[name] = 'failed';
      result.errors.push(`${name}: ${e.message}`);
      console.error(`[withdrawal] ${name} 실패 uid=${uid}`, e);
    }
  };

  const userRef = db.collection('users').doc(uid);
  const userSnap = await userRef.get();
  const userData = userSnap.exists ? userSnap.data() : {};

  // ① CI 링크 해제 + 30일 재가입 제한 — 반드시 ②보다 먼저.
  await step('identityLink', async () => {
    const r = await releaseIdentityLink(db, uid);
    return { ...r, cooldownDays: RELEASE_COOLDOWN_DAYS };
  });

  // ①-1 대표자 위임 취소 — 역시 ②보다 **먼저**.
  //
  // 개인정보를 지우고 나면 businessVerification이 사라져 이 계정이 어느
  // 위임으로 권한을 받고 있었는지 알 수 없다(releaseIdentityLink를 먼저
  // 두는 것과 같은 순서 함정). 남겨두면 탈퇴한 계정 앞으로 발급된 위임이
  // 영원히 approved로 남아 대표자의 관리 링크가 유령을 가리키게 된다.
  await step('revokeDelegations', async () => revokeDelegationsForGrantee(db, uid));

  // ①-2 닉네임 예약 해제 — **탈퇴 후 재사용 가능** 정책.
  //
  // users.nickname을 지우는 ②보다 **반드시 먼저** 해야 한다. 지운 뒤에는 어떤
  // 이름을 예약했었는지 알 수 없어 nicknames/{normalized} 문서가 영원히 남고,
  // 그 이름은 누구도 다시 쓸 수 없게 된다(releaseIdentityLink를 ②보다 먼저
  // 두는 것과 같은 이유다).
  await step('releaseNickname', async () => {
    const released = await releaseNickname(db, uid, userData.nickname || '');
    return { released, nickname: userData.nickname || '' };
  });

  // ② 본인확인 원문을 포함한 개인정보 필드 제거.
  await step('personalFields', async () => {
    const patch = {};
    for (const f of PERSONAL_FIELDS) patch[f] = admin.firestore.FieldValue.delete();
    patch.accountStatus = STATUS_WITHDRAWN;
    patch.accountStatusUpdatedAt = admin.firestore.FieldValue.serverTimestamp();
    patch.accountStatusReason = '탈퇴 완료';
    patch.withdrawnAt = admin.firestore.FieldValue.serverTimestamp();
    patch.withdrawalScheduledAt = admin.firestore.FieldValue.delete();
    // ── 탈퇴 회원 관리용 비석 필드 ────────────────────────────────────
    // withdrawalRequestedAt은 **지우지 않는다.** 관리자 탈퇴 회원 목록이
    // "언제 신청해서 언제 끝났는지"를 봐야 하는데, 지우면 완료일만 남아
    // 유예 기간에 무슨 일이 있었는지 되짚을 수 없다.
    //
    // 회원 유형은 businessVerification이 이 patch에서 지워지기 **전에**
    // 미리 읽어둔 userData로 뽑는다(memberTypeOf 주석 참고).
    patch.withdrawnMemberType = memberTypeOf(userData);
    // 보존 기간은 retentionPolicy.withdrawnMemberAdmin이 관리한다 — 법정
    // 보존이 아니라 운영 편의용 보관이라 거래기록과 기간이 다르다.
    // (withdrawalReasonCode·withdrawnFromStatus는 신청 시점에 기록돼 있고
    //  여기서 건드리지 않으므로 그대로 남는다.)
    // 보류 표시는 "아직 완료하지 못한 이유"라서 완료된 계정에는 의미가 없다.
    // 남겨두면 비석에 끝난 처리의 상태값이 붙어 있어, 나중에 이 문서를 보는
    // 사람이 아직 정산 확인을 기다리는 계정으로 읽는다.
    patch.withdrawalHold = admin.firestore.FieldValue.delete();
    patch.withdrawalHoldSince = admin.firestore.FieldValue.delete();
    // 문서 자체는 남긴다 — 5년 보존되는 거래기록이 이 uid를 참조하므로
    // 문서를 지우면 그 기록들이 주인 없는 상태가 된다.
    await userRef.set(patch, { merge: true });
    return PERSONAL_FIELDS.length;
  });

  // ③ 개인 데이터 · 푸시 토큰 · 업로드 파일.
  await step('devices', async () => {
    const snap = await userRef.collection('devices').get();
    if (snap.empty) return 0;
    const batch = db.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    return snap.size;
  });

  await step('personalCollections', async () => {
    const counts = {};
    for (const { name, field } of PERSONAL_COLLECTIONS) {
      try {
        counts[name] = await deleteQueryBatched(db, db.collection(name).where(field, '==', uid));
      } catch (e) {
        counts[name] = `failed(${e.message})`;
      }
    }
    return counts;
  });

  await step('uploads', async () => {
    // 탈퇴가 지우는 것은 사진뿐이라 R2 설정만 본다(동영상은 파티/플레이스
    // 문서를 지울 때 contentCleanup이 이미 함께 지운다).
    if (!creds || !creds.r2) return 'skipped(no-credentials)';
    const r2 = creds.r2;
    const keys = new Set();
    const profileKey = r2KeyFromUrl(userData.profileImageUrl);
    if (profileKey) keys.add(profileKey);
    // 사용자가 올린 이미지는 전부 party_images/ 아래에 있지만 R2는 접두사
    // 삭제를 제공하지 않는다. 남은 문서에 박힌 URL로 지울 수 있는 것만 지우고,
    // 나머지는 접두사 정리 대상으로 로그에 남긴다.
    //
    // 접두사가 둘인 이유: 파티 상세 이미지는 대표 사진과 섞이지 않게
    // party_images/detail/{uid}/ 아래에 올라간다
    // (party_app/lib/models/party_detail_image.dart의 storageFolder).
    // 여기에 함께 적지 않으면 그 폴더만 정리 대상에서 조용히 빠진다.
    let deleted = 0;
    for (const key of keys) {
      try {
        await deleteR2Object(r2, key);
        deleted += 1;
      } catch (e) {
        console.error(`[withdrawal] R2 삭제 실패 key=${key}`, e.message);
      }
    }
    const prefixes = [`party_images/${uid}/`, `party_images/detail/${uid}/`];
    console.log(`[withdrawal] R2 접두사 정리 필요: ${prefixes.join(', ')}`);
    return { deleted, prefix: prefixes[0], prefixes };
  });

  // ③-b 사전질문 답변·제출 사진 — 신청 문서는 남기고 이 세 필드만 지운다.
  //
  // 신청 문서 자체는 거래기록이라 5년 보존되지만, 사전질문 답변과 제출 사진은
  // 거래의 증빙이 아니라 **심사를 위해 받은 개인정보**다. 파티가 끝난 뒤에도
  // 신청 이력과 함께 남기는 것이 정책이지만(호스트가 지난 심사를 되짚을 수
  // 있어야 한다), 계정이 탈퇴하면 보존할 근거가 사라진다 — 본인확인 원문을
  // PERSONAL_FIELDS에서 지우는 것과 같은 판단이다.
  //
  // 금액·환불·참석 같은 거래 필드는 건드리지 않는다.
  await step('applicationAnswers', async () => {
    const snap = await db.collectionGroup('applications').where('uid', '==', uid).get();
    if (snap.empty) return { docs: 0, photos: 0 };
    let photoCount = 0;
    const targets = [];
    for (const doc of snap.docs) {
      const d = doc.data();
      const hasAnswers = d.answers || d.questionsSnapshot;
      const photos = Array.isArray(d.photos) ? d.photos : [];
      if (!hasAnswers && photos.length === 0) continue;
      photoCount += photos.length;
      targets.push({ ref: doc.ref, partyId: d.partyId || doc.ref.parent.parent.id, appId: doc.id });
    }
    for (let i = 0; i < targets.length; i += 400) {
      const batch = db.batch();
      for (const t of targets.slice(i, i + 400)) {
        batch.set(
          t.ref,
          {
            answers: admin.firestore.FieldValue.delete(),
            questionsSnapshot: admin.firestore.FieldValue.delete(),
            photos: admin.firestore.FieldValue.delete(),
            // 무엇이 왜 사라졌는지 남긴다 — 호스트 화면이 "삭제됨"과 "원래
            // 없었음"을 구분해서 그릴 수 있어야 한다.
            applicationDataErasedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }
      await batch.commit();
    }
    // Storage의 사진 파일도 같은 시점에 지운다. 실패해도 탈퇴 자체는 계속
    // 진행한다(step 헬퍼가 오류를 모아 보고한다).
    let deleted = 0;
    for (const t of targets) {
      const prefix = `partyApplications/${t.partyId}/${t.appId}/`;
      try {
        await admin.storage().bucket().deleteFiles({ prefix });
        deleted += 1;
      } catch (e) {
        console.error(`[withdrawal] Storage 삭제 실패 prefix=${prefix}`, e.message);
      }
    }
    return { docs: targets.length, photos: photoCount, storagePrefixes: deleted };
  });

  // ④ 법정 보존 데이터 익명화 — 지우지 않고 나를 가린다.
  await step('anonymize', async () => {
    const counts = { chatRooms: 0, orders: 0 };
    // 채팅방: 표시 이름만 바꾼다. 메시지 본문은 상대방의 거래 증빙이라 남긴다.
    const rooms = await db.collection('chatRooms').where('participants', 'array-contains', uid).get();
    for (let i = 0; i < rooms.docs.length; i += 400) {
      const batch = db.batch();
      for (const doc of rooms.docs.slice(i, i + 400)) {
        batch.set(doc.ref, { participantNames: { [uid]: '탈퇴한 회원' } }, { merge: true });
      }
      await batch.commit();
      counts.chatRooms += Math.min(400, rooms.docs.length - i);
    }
    // 주문 문서에 박힌 이름 스냅샷.
    for (const [coll, field, nameField] of [
      ['orders', 'buyerId', 'buyerName'],
      ['orders', 'sellerId', 'sellerName'],
    ]) {
      const snap = await db.collection(coll).where(field, '==', uid).get();
      for (let i = 0; i < snap.docs.length; i += 400) {
        const batch = db.batch();
        for (const doc of snap.docs.slice(i, i + 400)) {
          batch.set(doc.ref, { [nameField]: '탈퇴한 회원' }, { merge: true });
        }
        await batch.commit();
        counts.orders += Math.min(400, snap.docs.length - i);
      }
    }
    return counts;
  });

  // ⑤ Firebase Auth 계정 삭제 — 마지막. 이걸 먼저 하면 위 단계의 권한 근거가 사라진다.
  await step('authDelete', async () => {
    try {
      await admin.auth().deleteUser(uid);
      return 'deleted';
    } catch (e) {
      if (e.code === 'auth/user-not-found') return 'already-absent';
      throw e;
    }
  });

  await logUserActivity(db, {
    uid,
    activityType: 'withdrawal_completed',
    actorType: 'system',
    extra: { errors: result.errors.length ? result.errors : null },
  });

  console.log(`[withdrawal] 완료 uid=${uid} 오류=${result.errors.length}`);
  return result;
}

// ── 자동 처리 스케줄러 ───────────────────────────────────────────────────────
//
// 앱을 다시 켜지 않아도 7일이 지나면 처리돼야 하므로 전적으로 서버에서 돈다.
// 하루 한 번이면 최대 24시간이 밀리므로 1시간마다 돈다 — 대기 만료는 사용자가
// "7일 뒤"로 안내받은 시각이라 하루씩 밀리면 안내와 어긋난다.
exports.completeExpiredWithdrawals = onSchedule(
  {
    schedule: 'every 60 minutes',
    timeZone: 'Asia/Seoul',
    region: REGION,
    secrets: MEDIA_CLEANUP_SECRETS,
  },
  async () => {
    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();

    const due = await db
      .collection('users')
      .where('accountStatus', '==', STATUS_PENDING)
      .where('withdrawalScheduledAt', '<=', now)
      .limit(50)
      .get();

    if (due.empty) return;

    const creds = readCloudflareCreds('[withdrawal]');

    for (const doc of due.docs) {
      const uid = doc.id;
      // 정산 확인이 남았으면 완료만 보류한다. 대기 상태는 유지되므로 서비스는
      // 계속 차단되고, 운영자가 settlementClearedAt을 채우면 다음 회차에 끝난다.
      if (needsSettlementReview(doc.data())) {
        await doc.ref.set(
          {
            withdrawalHold: 'settlement',
            withdrawalHoldSince:
              doc.get('withdrawalHoldSince') || admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        console.warn(`[withdrawal] 정산 확인 대기로 보류 uid=${uid}`);
        continue;
      }

      // 대기 중에는 규칙과 앱이 활동을 막지만, 그 사이 어떤 경로로든 새 거래가
      // 생겼다면 지우면 안 된다. 완료 직전에 한 번 더 확인한다 — 신청 시점의
      // 검사만 믿으면 7일 사이에 생긴 예약을 남긴 채 계정이 사라진다.
      let liveBlockers = [];
      try {
        liveBlockers = await collectBlockers(db, uid);
      } catch (e) {
        console.error(`[withdrawal] 완료 전 재확인 실패 uid=${uid}`, e);
        continue; // 확인할 수 없으면 지우지 않는다.
      }
      if (liveBlockers.length > 0) {
        await doc.ref.set(
          {
            withdrawalHold: 'live_transaction',
            withdrawalHoldSince:
              doc.get('withdrawalHoldSince') || admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        console.warn(`[withdrawal] 진행 중 거래로 보류 uid=${uid} ${JSON.stringify(liveBlockers)}`);
        continue;
      }

      try {
        await completeWithdrawal(db, uid, creds);
      } catch (e) {
        console.error(`[withdrawal] 완전 탈퇴 실패 uid=${uid}`, e);
      }
    }
  },
);

module.exports.__helpers = {
  GRACE_DAYS,
  STATUS_PENDING,
  STATUS_WITHDRAWN,
  STATUS_ACTIVE,
  PERSONAL_FIELDS,
  PERSONAL_COLLECTIONS,
  needsSettlementReview,
  r2KeyFromUrl,
  completeWithdrawal,
  LIVE_APPLICATION_STATUSES,
  LIVE_RESERVATION_STATUSES,
  LIVE_ORDER_STATUSES,
  LIVE_REFUND_STATUSES,
  WITHDRAWAL_REASON_CODES,
  normalizeReasonCode,
  memberTypeOf,
};

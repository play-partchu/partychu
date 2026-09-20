// ── 본인확인 CI 단일 계정 정책 ("1명의 실사용자 = 파티츄 계정 1개") ──────────────
//
// NICE 본인확인 결과의 CI(연계정보)는 실사용자 1명당 전 기관 공통으로 동일한
// 값이 나온다. 따라서 CI를 파티츄 계정과 1:1로 묶어두면, 같은 사람이 다른
// 구글/카카오/네이버 계정으로 새로 가입해 본인확인을 다시 받는 우회를 막을 수
// 있다(노쇼 제재·신고·리뷰·이벤트 중복 참여 우회 차단).
//
// 저장 구조
//   identityLinks/{sha256(ci)} = {
//     uid, provider, status: 'active' | 'released',
//     linkedAt, updatedAt, releasedAt, reusableAt
//   }
//   - 문서 ID를 CI 원문이 아니라 SHA-256 해시로 쓴다. 문서 경로는 로그/모니터링
//     /에러 메시지에 그대로 노출되기 쉬운데, CI 원문이 그런 곳에 남으면 안 된다.
//   - 클라이언트 읽기·쓰기는 firestore.rules에서 전면 차단(Admin SDK 전용).
//
// 동시성
//   두 기기에서 동시에 인증을 마쳐도 중복 연결이 생기면 안 되므로, "이미 연결
//   되어 있는지 확인 → 연결 기록 생성 → users 문서 갱신"을 하나의 Firestore
//   트랜잭션으로 묶는다. Firestore 트랜잭션은 읽은 문서에 락을 걸고 커밋 시
//   충돌하면 자동 재시도하므로, 두 트랜잭션 중 하나만 링크를 만들 수 있다.
//
// 기존 가입자 호환
//   정책 도입 이전에 인증을 마친 회원은 identityLinks 문서가 없고 users.ci만
//   갖고 있다. 그래서 링크 문서가 없을 때는 같은 트랜잭션 안에서
//   users where ci == <ci> 를 한 번 더 조회해 "다른 계정이 이미 이 CI를 쓰고
//   있는지"를 확인한다(users.ci는 단일 필드 자동 색인 대상이라 별도 인덱스가
//   필요 없다). 기존 회원 본인은 uid가 같으므로 영향을 받지 않고, 다음 인증
//   시점에 링크 문서가 자연스럽게 채워진다(backfillIdentityLinks로 일괄 생성도 가능).

// 이 파일은 순수 헬퍼 모듈이다 — Cloud Function을 직접 export하지 않는다
// (index.js가 Object.assign으로 흡수하는 모듈이 아니므로, 여기에 onCall을 두면
//  배포 대상으로 잡히지 않는다). 관리자용 backfill 엔드포인트는
//  memberManagement.js의 backfillIdentityLinks에 있다.

const { HttpsError } = require('firebase-functions/v2/https');
const admin  = require('firebase-admin');
const crypto = require('crypto');

const IDENTITY_LINKS = 'identityLinks';

/// 중복 계정 안내 문구 — 클라이언트가 그대로 노출한다.
const DUPLICATE_MESSAGE =
  '이미 다른 파티츄 계정에서 본인확인이 완료된 정보입니다.\n기존 계정으로 로그인해주세요.';

/// 클라이언트가 분기 처리할 수 있는 머신 코드.
const DUPLICATE_CODE = 'IDENTITY_ALREADY_LINKED';

/// 탈퇴(accountStatus: 'withdrawn') 후 같은 CI를 새 계정에 다시 연결할 수 있게
/// 되기까지의 유예 기간. 탈퇴 직후 재가입으로 제재를 세탁하는 것을 막는다.
const RELEASE_COOLDOWN_DAYS = 30;

// ── 다중계정 예외 (테스트 계정용) ──────────────────────────────────────────
//
// 특정 CI 해시에 한해 여러 uid에서 본인확인을 허용한다. 소셜 로그인
// (구글·카카오·네이버·Apple)을 계정마다 실제로 끝까지 태워 봐야 하는데,
// 1인 1계정 정책이 두 번째 계정부터 막기 때문이다.
//
// **허용 목록은 코드가 아니라 Firestore에 둔다.**
//   serverConfig/identityMultiAccount = {
//     enabled: true,                 // false면 목록이 있어도 전부 차단
//     allowedCiHashes: ['<sha256 hex 64자>', ...],
//   }
//
// 왜 코드가 아닌가 — 예전에는 이 목록이 배포된 identityLink.js 안에만 있었고
// 저장소에는 없었다. 그래서 누가 Functions를 배포하면 예외가 조용히 사라지고,
// 테스터는 갑자기 IDENTITY_ALREADY_LINKED로 막히면서 원인을 찾기 어려웠다.
// 설정이 코드 밖 DB에 있으면 무엇을 배포하든 남고, 끌 때도 배포가 필요 없다.
//
// 값은 저장소에 두지 않는다. CI 해시는 실사용자 1명을 가리키는 식별자라
// 코드·로그·테스트에 원문을 남기지 않는다(문서 경로만 남긴다).
//
// 클라이언트는 이 문서를 읽을 수 없다 — firestore.rules에 serverConfig match가
// 없어 기본 거부이고, 서버는 Admin SDK로 규칙을 우회해 읽는다
// (tourApiUsage와 같은 방식).
const SERVER_CONFIG = 'serverConfig';
const MULTI_ACCOUNT_DOC = 'identityMultiAccount';

/// 인스턴스 안에서 설정을 붙들고 있는 시간. 본인확인 1건마다 문서를 읽지
/// 않으려는 것뿐이라 짧게 둔다 — 목록을 비우면 1분 안에 반영된다.
const MULTI_ACCOUNT_CACHE_MS = 60 * 1000;

let multiAccountCache = null;
let multiAccountWarned = false;

function ciHash(ci) {
  return crypto.createHash('sha256').update(ci, 'utf8').digest('hex');
}

/// 설정 문서 → 허용 해시 집합. 순수 함수라 셀프체크가 그대로 부른다.
///
/// 읽을 수 없는 모양이면 **빈 집합**을 준다. 빈 집합은 곧 "예외 없음"이고
/// 기존 1인 1계정 동작이다(fail-closed).
function parseMultiAccountAllowlist(data) {
  const out = new Set();
  if (!data || typeof data !== 'object') return out;
  // enabled를 명시적으로 끄면 목록이 남아 있어도 전부 차단한다.
  if (data.enabled === false) return out;
  const raw = Array.isArray(data.allowedCiHashes) ? data.allowedCiHashes : [];
  for (const entry of raw) {
    if (typeof entry !== 'string') continue;
    const hash = entry.trim().toLowerCase();
    // sha256 hex가 아닌 값은 버린다 — CI 원문을 실수로 넣는 사고를 막는다.
    if (/^[0-9a-f]{64}$/.test(hash)) out.add(hash);
  }
  return out;
}

/// 예외가 하나도 없을 때 한 번만 알린다. 이게 정상 상태일 수도 있으므로
/// 오류가 아니라 경고이고, 본인확인마다 찍히지 않게 인스턴스당 1회로 묶는다.
function warnNoMultiAccountConfig(reason) {
  if (multiAccountWarned) return;
  multiAccountWarned = true;
  console.warn('[IdentityLink] 다중계정 예외 없음 — 1인 1계정으로 동작', {
    path: `${SERVER_CONFIG}/${MULTI_ACCOUNT_DOC}`,
    reason,
  });
}

/// 테스트·재설정용. 다음 호출에서 설정을 다시 읽는다.
function resetMultiAccountCache() {
  multiAccountCache = null;
  multiAccountWarned = false;
}

async function loadMultiAccountAllowlist(db, { nowMs = Date.now(), cacheMs = MULTI_ACCOUNT_CACHE_MS } = {}) {
  if (multiAccountCache && nowMs - multiAccountCache.at < cacheMs) {
    return multiAccountCache.hashes;
  }
  let hashes = new Set();
  try {
    const snap = await db.collection(SERVER_CONFIG).doc(MULTI_ACCOUNT_DOC).get();
    if (!snap || !snap.exists) {
      warnNoMultiAccountConfig('문서 없음');
    } else {
      hashes = parseMultiAccountAllowlist(snap.data());
      if (hashes.size === 0) warnNoMultiAccountConfig('허용 목록이 비어 있음');
    }
  } catch (err) {
    // 설정을 못 읽는 상태가 곧 정책 우회가 되면 안 된다 — 막는 쪽으로 넘어간다.
    console.warn('[IdentityLink] 다중계정 예외 설정을 읽지 못해 차단으로 처리', {
      path: `${SERVER_CONFIG}/${MULTI_ACCOUNT_DOC}`,
      message: err && err.message,
    });
    hashes = new Set();
  }
  multiAccountCache = { hashes, at: nowMs };
  return hashes;
}

/// 이 CI 해시가 다중계정 예외 대상인가.
async function isMultiAccountAllowed(db, hash, options) {
  const hashes = await loadMultiAccountAllowlist(db, options);
  return hashes.has(hash);
}

function duplicateError() {
  return new HttpsError('already-exists', DUPLICATE_MESSAGE, { code: DUPLICATE_CODE });
}

/// 다른 계정에 걸린 링크가 "지금도 그 계정을 잠그고 있는지" 판정한다.
///   - status !== 'released' → 사용 중인 계정이므로 항상 차단
///   - released + reusableAt 미도래 → 탈퇴 유예 기간 중이므로 차단
///   - released + reusableAt 경과(또는 미설정) → 새 계정에 재연결 허용
function isLinkBlocking(link, nowMs) {
  if (!link || link.status !== 'released') return true;
  const reusableAt = link.reusableAt;
  if (!reusableAt || typeof reusableAt.toMillis !== 'function') return false;
  return reusableAt.toMillis() > nowMs;
}

/// CI를 현재 계정에 원자적으로 연결하고, 같은 트랜잭션에서 본인확인 결과를
/// users/{uid}에 저장한다.
///
/// 이미 다른 계정에 연결된 CI라면 아무것도 쓰지 않고 duplicateError를 던진다
/// (users 문서도 갱신되지 않으므로 "인증 거부"가 그대로 성립한다).
async function linkIdentityAndSaveVerification(db, { uid, ci, userPatch, provider }) {
  if (typeof ci !== 'string' || ci.trim() === '') {
    // CI 없이 인증을 통과시키면 정책 자체가 무력화되므로 실패로 처리한다.
    throw new HttpsError(
      'failed-precondition',
      '본인확인 정보(CI)를 확인하지 못했습니다. 다시 시도해주세요.',
      { code: 'NICE_RESULT_FAILED' },
    );
  }

  const hash     = ciHash(ci);
  // 설정 문서 읽기 — 트랜잭션 밖에서 한 번만. 경합하는 상태가 아니라 설정이다.
  const allowMultiAccount = await isMultiAccountAllowed(db, hash);
  if (allowMultiAccount) {
    // 감사 로그: 누가 예외로 통과했는지 남긴다. 해시는 남기지 않는다 —
    // uid만으로 나중에 identityLinks/users에서 역추적할 수 있다.
    console.warn('[IdentityLink] 다중계정 예외 적용 — 중복 차단을 건너뛴다', {
      uid, provider: provider || null,
    });
  }
  const linkRef  = db.collection(IDENTITY_LINKS).doc(hash);
  const userRef  = db.collection('users').doc(uid);
  // 기존 가입자(링크 문서가 아직 없는 회원) 탐지용 — 트랜잭션 안에서 읽어야
  // 동시 인증 시에도 "둘 다 통과"가 생기지 않는다.
  const legacyQuery = db.collection('users').where('ci', '==', ci).limit(10);

  await db.runTransaction(async (tx) => {
    // Firestore 트랜잭션은 모든 읽기를 쓰기보다 먼저 수행해야 한다.
    const linkSnap   = await tx.get(linkRef);
    const legacySnap = await tx.get(legacyQuery);

    const nowMs = Date.now();
    const link  = linkSnap.exists ? linkSnap.data() : null;

    if (!allowMultiAccount && link && link.uid !== uid && isLinkBlocking(link, nowMs)) {
      console.warn('[IdentityLink] 중복 본인확인 차단(링크 존재)', {
        uid, linkedUid: link.uid, status: link.status,
      });
      throw duplicateError();
    }

    if (!allowMultiAccount && !link) {
      const other = legacySnap.docs.find((d) => d.id !== uid);
      if (other) {
        console.warn('[IdentityLink] 중복 본인확인 차단(기존 가입자)', {
          uid, linkedUid: other.id,
        });
        throw duplicateError();
      }
    }

    // 링크 문서는 병합이 아니라 통째로 다시 쓴다 — 유예 기간이 끝나 다른
    // 계정으로 넘어가는 경우 released/reusableAt 흔적이 남으면 안 된다.
    const keepLinkedAt = link && link.uid === uid && link.linkedAt ? link.linkedAt : null;

    // ── 재가입 추적 ────────────────────────────────────────────────────
    // 이 CI를 예전에 쓰던 계정 목록은 **덮어쓰기에서 손으로 살려낸다.**
    // 바로 위 주석대로 이 set은 merge가 아니라서, 아무것도 하지 않으면 탈퇴
    // 때 쌓아둔 previousUids가 재가입하는 순간 사라진다 — 하필 그 순간이
    // 이력이 가장 필요한 시점이다(같은 사람이 새 uid로 돌아온 시점).
    const carried = link && Array.isArray(link.previousUids) ? link.previousUids : [];
    // 링크가 다른 계정으로 넘어가는 경우 직전 주인도 이력에 넣는다. 정상
    // 탈퇴는 releaseIdentityLink가 이미 넣어두지만, 그 경로를 타지 않고
    // 넘어간 링크(정책 도입 전 문서 등)에서도 연결이 끊기지 않게 한다.
    const previousUids =
      link && link.uid && link.uid !== uid && !carried.includes(link.uid)
        ? [...carried, link.uid]
        : carried;

    tx.set(linkRef, {
      uid,
      provider:   provider || null,
      status:     'active',
      linkedAt:   keepLinkedAt || admin.firestore.FieldValue.serverTimestamp(),
      updatedAt:  admin.firestore.FieldValue.serverTimestamp(),
      releasedAt: null,
      reusableAt: null,
      previousUids,
    });

    tx.set(userRef, { ...userPatch, identityCiHash: hash }, { merge: true });
  });

  return { ciHash: hash };
}

/// 탈퇴 처리 시 호출 — 링크를 유지하되 'released'로 표시하고 재사용 가능
/// 시각을 유예 기간 뒤로 설정한다. 링크 자체를 지우지 않는 이유는, 지워버리면
/// 탈퇴 직후 곧바로 새 계정을 만들어 제재를 회피할 수 있기 때문이다.
async function releaseIdentityLink(db, uid, { cooldownDays = RELEASE_COOLDOWN_DAYS } = {}) {
  const hash = await resolveCiHash(db, uid);
  if (!hash) return { released: false, reason: 'no-ci' };

  const linkRef = db.collection(IDENTITY_LINKS).doc(hash);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(linkRef);
    if (!snap.exists || snap.data().uid !== uid) {
      return { released: false, reason: 'not-linked-to-uid' };
    }
    tx.set(linkRef, {
      status:     'released',
      releasedAt: admin.firestore.FieldValue.serverTimestamp(),
      reusableAt: admin.firestore.Timestamp.fromDate(
        new Date(Date.now() + cooldownDays * 24 * 60 * 60 * 1000),
      ),
      updatedAt:  admin.firestore.FieldValue.serverTimestamp(),
      // 재가입 추적 — 탈퇴하는 계정을 이력에 적는다. 이 시점이 마지막 기회다:
      // users의 ci/identityCiHash는 곧 지워지고, 그 뒤로는 이 uid와 CI를 잇는
      // 근거가 어디에도 남지 않는다.
      //
      // 보존 기간은 retentionPolicy.identityRelink가 따로 관리한다 — 이 배열은
      // "탈퇴해도 같은 사람임을 계속 아는" 연결이라, 다른 탈퇴 기록과 같은
      // 기간을 쓸 수 없다.
      previousUids: admin.firestore.FieldValue.arrayUnion(uid),
    }, { merge: true });
    return { released: true, cooldownDays };
  });
}

/// 탈퇴를 되돌릴 때(계정 상태를 다시 active 등으로 변경) 호출 — 유예 기간
/// 중에 다른 계정이 CI를 가져가지 않았다면 링크를 다시 'active'로 되돌린다.
async function reactivateIdentityLink(db, uid) {
  const hash = await resolveCiHash(db, uid);
  if (!hash) return { reactivated: false, reason: 'no-ci' };

  const linkRef = db.collection(IDENTITY_LINKS).doc(hash);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(linkRef);
    if (!snap.exists || snap.data().uid !== uid) {
      // 유예 기간이 끝나 다른 계정이 이미 이 CI를 가져간 경우 — 되돌리지 않는다.
      return { reactivated: false, reason: 'not-linked-to-uid' };
    }
    tx.set(linkRef, {
      status:     'active',
      releasedAt: null,
      reusableAt: null,
      updatedAt:  admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return { reactivated: true };
  });
}

/// 이미 읽어 둔 users 문서에서 링크 문서 ID를 구한다 — **순수 함수**.
///
/// [resolveCiHash]에서 판정만 떼어낸 것이다. 사용자 문서를 이미 손에 들고
/// 있는 호출부(businessVerification의 본인확인 게이트가 그렇다)가 같은 문서를
/// 다시 읽지 않게 하려는 것이고, 판정 규칙 자체는 한 곳에 그대로 있다.
///
/// 정책 도입 이전 회원은 identityCiHash가 없으므로 저장된 ci 원문으로 계산한다.
function ciHashOfUserData(userData) {
  if (!userData) return null;
  if (typeof userData.identityCiHash === 'string' && userData.identityCiHash !== '') {
    return userData.identityCiHash;
  }
  if (typeof userData.ci === 'string' && userData.ci.trim() !== '') {
    return ciHash(userData.ci);
  }
  return null;
}

/// users/{uid}를 읽어 링크 문서 ID를 구한다. 판정은 [ciHashOfUserData]가 한다.
async function resolveCiHash(db, uid) {
  const snap = await db.collection('users').doc(uid).get();
  if (!snap.exists) return null;
  return ciHashOfUserData(snap.data());
}

// ── 기존 인증 회원 → identityLinks 일괄 생성 ────────────────────────────────
//
// 정책 도입 이전에 인증을 마친 회원들의 링크 문서를 미리 만들어 둔다. 링크가
// 없어도 위의 legacyQuery 경로가 중복을 막아주므로 필수는 아니지만, 회원 수가
// 늘어날수록 매 인증마다 users 조회를 타는 것보다 링크 문서 조회가 저렴하다.
//
// 같은 CI를 쓰는 계정이 이미 여러 개 있다면(정책 도입 전 생성된 중복 계정)
// 가장 먼저 인증한 계정을 링크 주인으로 삼고 나머지는 conflicts로 보고만 한다
// — 기존 계정을 함부로 잠그지 않기 위해서다.
async function backfillIdentityLinks(db, { dryRun = false } = {}) {
  // ci가 있는 회원만 대상. 인증 시각 순으로 훑어 "먼저 인증한 계정"이 주인이 되게 한다.
  const snap = await db.collection('users').where('ci', '>', '').get();
  const rows = snap.docs
    .map((d) => ({
      uid: d.id,
      ci: d.data().ci,
      at: d.data().identityVerifiedAt?.toMillis?.() ?? d.data().verifiedAt?.toMillis?.() ?? 0,
      provider: d.data().verificationProvider || null,
    }))
    .filter((r) => typeof r.ci === 'string' && r.ci.trim() !== '')
    .sort((a, b) => a.at - b.at);

  const owners    = new Map(); // ciHash → uid
  const conflicts = [];
  let created = 0;

  for (const row of rows) {
    const hash = ciHash(row.ci);
    if (owners.has(hash)) {
      conflicts.push({ ciHash: hash, ownerUid: owners.get(hash), duplicateUid: row.uid });
      continue;
    }
    owners.set(hash, row.uid);

    if (dryRun) continue;

    const linkRef = db.collection(IDENTITY_LINKS).doc(hash);
    const existing = await linkRef.get();
    if (existing.exists) continue;

    await linkRef.set({
      uid:        row.uid,
      provider:   row.provider,
      status:     'active',
      linkedAt:   row.at ? admin.firestore.Timestamp.fromMillis(row.at)
                         : admin.firestore.FieldValue.serverTimestamp(),
      updatedAt:  admin.firestore.FieldValue.serverTimestamp(),
      releasedAt: null,
      reusableAt: null,
      backfilled: true,
    });
    await db.collection('users').doc(row.uid).set({ identityCiHash: hash }, { merge: true });
    created += 1;
  }

  console.log(`[IdentityLink] backfill 완료. scanned=${rows.length} created=${created}`
    + ` conflicts=${conflicts.length} dryRun=${dryRun}`);

  return { scanned: rows.length, created, conflicts, dryRun };
}

exports.backfillIdentityLinks = backfillIdentityLinks;
exports.ciHash = ciHash;
exports.duplicateError = duplicateError;
exports.isLinkBlocking = isLinkBlocking;
exports.linkIdentityAndSaveVerification = linkIdentityAndSaveVerification;
exports.releaseIdentityLink = releaseIdentityLink;
exports.reactivateIdentityLink = reactivateIdentityLink;
exports.resolveCiHash = resolveCiHash;
exports.ciHashOfUserData = ciHashOfUserData;
exports.DUPLICATE_MESSAGE = DUPLICATE_MESSAGE;
exports.DUPLICATE_CODE = DUPLICATE_CODE;
exports.SERVER_CONFIG = SERVER_CONFIG;
exports.MULTI_ACCOUNT_DOC = MULTI_ACCOUNT_DOC;
exports.MULTI_ACCOUNT_CACHE_MS = MULTI_ACCOUNT_CACHE_MS;
exports.parseMultiAccountAllowlist = parseMultiAccountAllowlist;
exports.loadMultiAccountAllowlist = loadMultiAccountAllowlist;
exports.isMultiAccountAllowed = isMultiAccountAllowed;
exports.resetMultiAccountCache = resetMultiAccountCache;
exports.RELEASE_COOLDOWN_DAYS = RELEASE_COOLDOWN_DAYS;
exports.IDENTITY_LINKS = IDENTITY_LINKS;

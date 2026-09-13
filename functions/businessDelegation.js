// ══════════════════════════════════════════════════════════════════════════
// 대표자 위임 — "본인 명의가 아닌 사업자"를 대표자 승인으로 여는 길
//
// 1단계가 만든 상태는 두 축이었다(businessVerification.js "두 축" 절).
//   status         국세청이 확인한 사업자 정보의 진위
//   authorization  이 계정이 그 사업자를 쓸 수 있는 권한
// 배우자·가족·직원 명의 사업장은 진위는 통과하지만 권한이 없어
// `pendingOwnerApproval`에 멈춘다. 이 파일이 그 상태를 푸는 유일한 경로다.
//
// ── 무엇을 증명하는가 ────────────────────────────────────────────────────
// **관계가 아니라 승인이다.** 배우자인지 직원인지 가족인지 묻지 않고,
// 확인하지도 저장하지도 않는다. 확인하는 것은 딱 하나다:
//
//   국세청이 확인해 준 그 사업자의 대표자가, NICE 본인확인을 직접 통과한 뒤,
//   특정 파티츄 계정에 운영 권한을 주겠다고 명시적으로 말했는가.
//
// ── 승인 링크를 가진 것은 권한이 아니다 ─────────────────────────────────
// 토큰은 "어느 요청인가"만 지시한다. 권한은 [evaluateApproval]의 12개 검사가
// 준다. 링크를 통째로 가로채도 **국세청에 등록된 대표자명 그대로 NICE를
// 통과하지 못하면** 아무것도 할 수 없다. 그래서 토큰은 원문을 저장하지 않고
// 해시만 두며, 72시간·1회성이다.
//
// ── 회원 본인확인과 완전히 분리 ─────────────────────────────────────────
// ⚠️ 이 파일은 **절대** linkIdentityAndSaveVerification /
//    releaseIdentityLink / reactivateIdentityLink를 부르지 않는다.
//    대표자는 파티츄 회원이 아닐 수 있고, 회원이어도 그 사람의 계정·CI 연결을
//    건드리면 안 된다("1명의 실사용자 = 파티츄 계정 1개" 정책, identityLink.js).
//    identityLinks는 **읽기 한 번**만 한다 — 대표자에게 계정이 있으면 감사용
//    grantorUid를 남기기 위해서고, 없으면 아무것도 만들지 않는다.
//
//    NICE 세션도 별도 정본(businessApprovalSessions)이고 purpose를 검증한다.
//    niceAuthSessions를 재사용하면 (1) 문서 id가 uid라 비회원을 담을 수 없고
//    (2) niceAuthResult가 그 세션으로 성공하는 순간 **대표자의 CI가 신청자
//    계정에 연결**된다 — 1인1계정 정책이 통째로 무너진다.
//
// ── 소유와 운영권은 다른 문서다 ─────────────────────────────────────────
//   businessOwnership/{sha256(사업자번호)}   대표자 identity 정본 (0~1)
//   businessDelegations/{delegationId}       운영권 정본        (0~N)
//
// 위임받은 운영자를 holderUid에 덮어쓰지 않는다. 한 칸을 같이 쓰면 대표자
// 본인이 나중에 자기 계정으로 인증할 때 자기 사업자에서 막힌다 — 거꾸로다.
// 한 사업자에 **대표자 본인 계정 0~1 + 위임 운영자 0~N**이 공존한다.
//
// 승인이 남기는 것은 `representativeCiHash` + 그 확인 등급이다.
//
// ── 이 승인이 증명하는 것과 증명하지 않는 것 ────────────────────────────
// 이 흐름이 확인하는 것은 **NICE 실명 문자열 == 국세청이 확인해 준 대표자명**
// 하나뿐이다. 국세청 응답에는 대표자의 CI도 생년월일도 연락처도 없어서,
// 두 API의 교집합이 이름 문자열밖에 없다.
//
// 그래서 이 승인이 남기는 핀의 등급은 [REP_VERIFICATION_LEVEL.nameMatched]다.
// **`self` 자동승인과 정확히 같은 등급이고, 둘 중 어느 쪽도 사업자와 CI를
// 직접 결합해 확인하지 않는다.**
//
//   ⚠️ 그러므로 사업자등록정보를 아는 동명이인은 이 승인도 통과할 수 있고,
//      그 사람의 CI가 먼저 박히면 **나중에 온 실제 대표자가 오히려 막힌다.**
//      이것이 알려진 역전 위험이다. 그래서 CI 충돌은 자동으로 풀지 않고
//      needsManualReview로 사람에게 넘긴다.
//
// 핀이 실제로 해주는 일은 **충돌 감지**다 — 최초 확인 이후 서로 다른 CI가
// 같은 사업자의 대표자를 주장하면 자동으로 알아채고 멈춘다. 어느 쪽이
// 진짜인지는 이 값이 답하지 못한다.
//
// 사업자와 CI를 직접 결합해 검증하는 수단(NICE 사업자 대표자 확인, 사업자
// 공동인증서 등)이 붙으면 그때 'strongVerified' 등급이 생긴다. 현재 계약
// 범위에는 없다. 이 한계는 승인 페이지 문구에도 그대로 적는다.
//
// 신청자가 대표자 휴대폰 번호를 안다는 것은 **소유 증명이 아니므로** 쓰지
// 않는다. NICE mobile_no는 대조하지도 저장하지도 않는다.
// ══════════════════════════════════════════════════════════════════════════

const { onCall, onRequest, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const crypto = require('crypto');

const {
  NICE_FUNCTION_OPTIONS,
  niceClientId,
  niceClientSecret,
  niceRequestNo,
  postNiceIntc,
  toNiceHttpsError,
  getAccessToken,
  verifyAndDecrypt,
} = require('./niceIntcClient');

const { assertIdentityVerifiedData } = require('./identityGuard');
const { ciHashOfUserData, IDENTITY_LINKS } = require('./identityLink');
// 이름 대조·시각 변환은 이미 있는 정본을 그대로 쓴다.
const { holderMatches, normalizeHolderName, toMillis } = require('./payoutAccounts');
const {
  AUTHORIZATION,
  AUTH_REASON,
  BUSINESS_OWNERSHIP,
  OWNERSHIP_STATUS,
  businessNumberHash,
  maskBusinessNumber,
  REP_VERIFICATION_LEVEL,
  canSupersedePin,
  representativeLevelOf,
  normalizeBusinessNumber,
  normalizeOpeningDate,
  resolveVerificationWrite,
} = require('./businessVerification');
const { escapeHtml } = require('./partyLandingPage');

// ── 컬렉션 ──────────────────────────────────────────────────────────────
const DELEGATIONS = 'businessDelegations';
const APPROVAL_SESSIONS = 'businessApprovalSessions';

/// NICE 세션의 목적. **결과 처리기가 맨 앞에서 이 값을 단언한다.**
/// 회원 본인확인 세션이 실수로라도 이 경로를 타면 안 된다.
const APPROVAL_PURPOSE = 'businessDelegation';

// ── 정책값 ──────────────────────────────────────────────────────────────
const REQUEST_TTL_MS = 72 * 60 * 60 * 1000; // 승인 요청 유효기간 72시간
const SESSION_TTL_MS = 10 * 60 * 1000;      // NICE transaction_id 유효시간과 같다
const MAX_NICE_ATTEMPTS = 5;                // 요청 1건당 NICE 시도
const MAX_REQUESTS_PER_DAY = 3;             // 신청자 1명당 하루 요청 생성
const MAX_ACTIVE_DELEGATES = 10;            // 사업자 1개당 활성 위임

const STATUS = {
  requested: 'requested',
  approved: 'approved',
  rejected: 'rejected',
  expired: 'expired',
  revoked: 'revoked',
};

/// 승인/취소를 거절한 이유. 화면 문구와 운영 추적에 쓴다.
/// ⚠️ 대표자에게 보여줄 때는 [refusalMessage]로 뭉뚱그린다 — 어느 검사에서
///    걸렸는지 그대로 알려주면 링크를 주운 사람에게 탐침을 쥐여주는 셈이다.
const REFUSAL = {
  linkInvalid: 'linkInvalid',
  linkUsed: 'linkUsed',
  linkExpired: 'linkExpired',
  tooManyAttempts: 'tooManyAttempts',
  sessionInvalid: 'sessionInvalid',
  sessionPurpose: 'sessionPurpose',
  sessionUsed: 'sessionUsed',
  sessionExpired: 'sessionExpired',
  sessionMismatch: 'sessionMismatch',
  consentMissing: 'consentMissing',
  representativeMismatch: 'representativeMismatch',
  subjectChanged: 'subjectChanged',
  selfApproval: 'selfApproval',
  representativeCiMismatch: 'representativeCiMismatch',
  delegateLimit: 'delegateLimit',
  notGrantor: 'notGrantor',
  notApproved: 'notApproved',
};

const SITE_ORIGIN = 'https://partychu-30c24.web.app';
const APPROVAL_BASE = `${SITE_ORIGIN}/biz-approval`;

// ⚠️ **회원 본인확인의 /nice/callback과 반드시 다른 경로여야 한다.** 같은 URL을
//    쓰면 앱 WebView의 콜백 처리기가 대표자 승인 트랜잭션을 집어먹는다.
const APPROVAL_RETURN_URL = `${APPROVAL_BASE}/callback`;
const APPROVAL_CLOSE_URL = `${APPROVAL_BASE}/closed`;

/// 세션 손잡이를 담는 쿠키. HttpOnly라 페이지 스크립트가 읽지 못하고,
/// SameSite=Lax라 NICE에서 돌아오는 최상위 GET 이동에는 그대로 실린다.
const SESSION_COOKIE = 'bizApprovalSid';

// ══════════════════════════════════════════════════════════════════════════
// 순수 헬퍼 — 네트워크·Firestore 없이 셀프체크할 수 있다
// ══════════════════════════════════════════════════════════════════════════

/// 승인/관리 링크 토큰. 256비트 CSPRNG.
function newToken() {
  return crypto.randomBytes(32).toString('base64url');
}

/// **토큰 원문은 어디에도 저장하지 않는다.** 문서에 남는 것은 이 해시뿐이다 —
/// DB가 통째로 새어도 링크를 만들 수 없다(원문은 URL로 한 번 나갔을 뿐이다).
function hashToken(token) {
  return crypto.createHash('sha256').update(String(token || ''), 'utf8').digest('hex');
}

/// CI 해시 — identityLinks와 같은 계산. **CI 원문은 저장하지 않는다.**
function hashCi(ci) {
  return crypto.createHash('sha256').update(String(ci || ''), 'utf8').digest('hex');
}

/**
 * 승인 대상 지문 — "요청 생성 후 대상이 바뀌면 승인이 성립하지 않는다"의 집행자.
 *
 * 신청자 uid와 국세청이 검증한 3항목을 한 값으로 묶는다. 승인 시점에 신청자
 * 문서에서 **다시 계산해** 저장된 값과 대조하므로, 그 사이 신청자가 사업자
 * 정보를 바꿨거나 다른 계정으로 갈아탔으면 지문이 달라져 승인이 거절된다.
 *
 * 이 지문 덕분에 delegation 문서는 **대표자명을 저장할 필요가 없다** —
 * 대조 기준은 승인 시점의 신청자 문서에서 읽고, 그 문서가 바뀌지 않았다는
 * 것은 지문이 증명한다. 그래서 이 컬렉션에 남는 개인정보는 CI 해시뿐이다.
 */
function subjectFingerprint({ granteeUid, businessNumber, openingDate, representativeName }) {
  const parts = [
    String(granteeUid || ''),
    normalizeBusinessNumber(businessNumber) || '',
    normalizeOpeningDate(openingDate) || '',
    normalizeHolderName(representativeName),
  ];
  return crypto.createHash('sha256').update(parts.join('\u0000'), 'utf8').digest('hex');
}

/// 승인 대상 사업자 정보 한 벌 — [resolveVerificationWrite]의 input 모양 그대로.
function pickSubjectInput(src) {
  const s = src || {};
  return {
    businessNumber: String(s.businessNumber || ''),
    representativeName: String(s.representativeName || ''),
    openingDate: String(s.openingDate || ''),
    businessName: String(s.businessName || ''),
    businessAddress: String(s.businessAddress || ''),
    businessBaseAddress: String(s.businessBaseAddress || ''),
    businessDetailAddress: String(s.businessDetailAddress || ''),
    ntsStatusLabel: String(s.ntsStatusLabel || ''),
    taxType: String(s.taxType || ''),
  };
}

/**
 * 신청자의 businessVerification에서 **대표자 승인을 기다리는 사업자**를 찾는다.
 *
 * 그 사업자는 두 자리 중 하나에 있다.
 *   · 최상위        — 처음부터 타인 명의였던 경우
 *   · pendingChange — 이미 본인 명의 사업자를 쓰던 사람이 다른 사업자를
 *                     시도한 경우(기존 권한은 그대로 유지된다)
 *
 * **둘 다 pendingOwnerApproval일 수는 없다.** 최상위가 그 상태면 기존 권한이
 * 없다는 뜻이라 keptVerified 갈래 자체가 일어나지 않고, 그래서 pendingChange가
 * 비어 있다(businessVerification.js의 resolveVerificationWrite). 그 불변식
 * 덕분에 이 함수의 답이 하나로 결정된다.
 *
 * @returns {{source: 'current'|'pendingChange', input: object}|null}
 */
function resolvePendingSubject(bv) {
  const v = bv || {};
  const isPending = (m) =>
    !!m
    && m.status === 'verified'
    && m.authorization === AUTHORIZATION.pendingOwnerApproval;

  if (isPending(v.pendingChange)) {
    return { source: 'pendingChange', input: pickSubjectInput(v.pendingChange) };
  }
  if (isPending(v)) {
    return { source: 'current', input: pickSubjectInput(v) };
  }
  return null;
}

/// 승인 시점에 되살리는 국세청 판정.
///
/// ⚠️ **국세청을 다시 부르지 않는다.** 근거는 신청자가 인증할 때 받은 결과이고,
///    요청 유효기간이 72시간이므로 그보다 오래된 결과가 쓰이지는 않는다.
///    "승인 이후 폐업" 같은 변화는 주기적 재검증(다음 단계)이 다룬다.
function outcomeFromSubject(input) {
  return {
    status: 'verified',
    failReason: null,
    // pendingChange 스냅샷에는 상태코드가 담기지 않는다 — 통과했다는 것은
    // 계속사업자였다는 뜻이므로 '01'로 되살린다.
    ntsStatusCode: '01',
    ntsStatusLabel: input.ntsStatusLabel || '',
    taxType: input.taxType || '',
    nameMatched: null,
    addressMatched: null,
  };
}

/// 표시용 사업자번호 — 대표자가 **자기 사업장을 알아볼 수 있을 만큼만** 보인다.
/// 로그용 [maskBusinessNumber](앞 3자리)와 다른 이유: 로그는 알아볼 필요가
/// 없지만 승인 화면은 알아봐야 한다. 대신 화면 밖으로는 나가지 않는다.
function maskForDisplay(bNo) {
  const d = String(bNo || '').replace(/[^0-9]/g, '');
  if (d.length !== 10) return '***-**-*****';
  return `${d.slice(0, 3)}-${d.slice(3, 5)}-*****`;
}

/**
 * **승인 가능 여부 — 보안 불변식 12개.** 순수 함수라 전수 검증할 수 있다.
 *
 * 순서가 규칙이다. 링크가 유효하지 않으면 세션을 볼 이유가 없고, 대표자
 * 본인이 아니면 대상이 바뀌었는지 따질 이유가 없다.
 *
 * ⚠️ 이 함수가 `{ ok: true }`를 돌려주기 **전에는 어떤 경로로도 'delegated'를
 *    쓰지 않는다.** 호출부는 반환값을 보고서만 쓰기를 시작한다.
 */
function evaluateApproval({
  delegation,
  session,
  now,
  consent,
  niceName,
  niceCiHash,
  subject,
  subjectFingerprintNow,
  granteeCiHash,
  ownershipRepCiHash,
  ownershipRepLevel = REP_VERIFICATION_LEVEL.nameMatched,
  activeDelegateCount,
}) {
  const no = (refusal) => ({ ok: false, refusal });

  // ① 링크 — 존재하고, 아직 requested이고, 만료되지 않았고, 시도 한계 안이다.
  if (!delegation) return no(REFUSAL.linkInvalid);
  if (delegation.status !== STATUS.requested) {
    // 승인·거절·만료·취소된 요청의 토큰은 **다시 쓸 수 없다.**
    return no(REFUSAL.linkUsed);
  }
  if ((toMillis(delegation.expiresAt) ?? 0) <= now) return no(REFUSAL.linkExpired);
  if ((delegation.attemptCount || 0) > MAX_NICE_ATTEMPTS) {
    return no(REFUSAL.tooManyAttempts);
  }

  // ② 세션 — 이 요청의 것이고, 목적이 맞고, 아직 쓰이지 않았고, 만료 전이다.
  if (!session) return no(REFUSAL.sessionInvalid);
  if (session.purpose !== APPROVAL_PURPOSE) return no(REFUSAL.sessionPurpose);
  if (session.used === true) return no(REFUSAL.sessionUsed);
  if ((toMillis(session.expiresAt) ?? 0) <= now) return no(REFUSAL.sessionExpired);
  if (session.delegationId !== delegation.id) return no(REFUSAL.sessionMismatch);

  // ③ 대표자의 명시적 승인 — 화면 체크가 아니라 요청에 실려 온 값이다.
  if (consent !== true || session.consentAt == null) return no(REFUSAL.consentMissing);

  // ④ NICE 실명 == 국세청이 확인해 준 대표자명.
  //    ⚠️ 이름이 같다는 것이 동일인의 증명은 아니다(파일 상단 주석).
  if (!subject) return no(REFUSAL.subjectChanged);
  if (!holderMatches(niceName, subject.input.representativeName)) {
    return no(REFUSAL.representativeMismatch);
  }

  // ⑤ 요청 생성 후 대상(신청자 uid + 사업자 3항목)이 바뀌지 않았다.
  if (subjectFingerprintNow !== delegation.subjectFingerprint) {
    return no(REFUSAL.subjectChanged);
  }

  // ⑥ 자기 자신에게 주는 승인이 아니다.
  //    정상 경로에서는 일어날 수 없지만(이름이 같았다면 self를 받았을 것이다)
  //    권한을 만드는 지점이라 방어적으로 막는다.
  if (granteeCiHash && niceCiHash === granteeCiHash) return no(REFUSAL.selfApproval);

  // ⑦ 이 사업자에 이미 박힌 대표자 CI와 같은 자연인이다.
  //
  //    다르면 **서로 다른 CI가 같은 사업자의 대표자를 주장하는 충돌**이다.
  //    누가 진짜인지 여기서 정하지 않는다 — 기존 핀도 이름 대조 등급이라
  //    먼저 온 쪽이 옳다는 근거가 없다. 자동 대체도 자동 승인도 하지 않고
  //    멈춘 뒤 사람에게 넘긴다([canSupersedePin]이 그 판단의 유일한 지점).
  if (ownershipRepCiHash && ownershipRepCiHash !== niceCiHash) {
    // 이번 승인도 이름 대조 등급이다 — 기존 핀과 우열을 가릴 근거가 없다.
    if (!canSupersedePin(ownershipRepLevel, REP_VERIFICATION_LEVEL.nameMatched)) {
      return no(REFUSAL.representativeCiMismatch);
    }
  }

  // ⑧ 활성 위임 상한.
  if ((activeDelegateCount || 0) >= MAX_ACTIVE_DELEGATES) {
    return no(REFUSAL.delegateLimit);
  }

  return { ok: true, refusal: null };
}

/**
 * **취소 가능 여부.** 관리 링크를 가진 것만으로는 취소되지 않는다 —
 * 승인했던 그 대표자가 NICE를 다시 통과해야 한다.
 */
function evaluateRevoke({ delegation, session, now, niceName, niceCiHash, subjectRepName }) {
  const no = (refusal) => ({ ok: false, refusal });

  if (!delegation) return no(REFUSAL.linkInvalid);
  if (delegation.status !== STATUS.approved) return no(REFUSAL.notApproved);
  if ((delegation.attemptCount || 0) > MAX_NICE_ATTEMPTS) {
    return no(REFUSAL.tooManyAttempts);
  }

  if (!session) return no(REFUSAL.sessionInvalid);
  if (session.purpose !== APPROVAL_PURPOSE) return no(REFUSAL.sessionPurpose);
  if (session.used === true) return no(REFUSAL.sessionUsed);
  if ((toMillis(session.expiresAt) ?? 0) <= now) return no(REFUSAL.sessionExpired);
  if (session.delegationId !== delegation.id) return no(REFUSAL.sessionMismatch);

  // 이름과 CI를 **둘 다** 본다. CI만 보면 승인 당시 CI를 어떻게든 알아낸
  // 경우를 막지 못하고, 이름만 보면 동명이인이 남의 위임을 끊을 수 있다.
  if (subjectRepName && !holderMatches(niceName, subjectRepName)) {
    return no(REFUSAL.representativeMismatch);
  }
  if (delegation.grantorCiHash !== niceCiHash) return no(REFUSAL.notGrantor);

  return { ok: true, refusal: null };
}

/// 대표자에게 보여줄 문구. **어느 검사에서 걸렸는지 그대로 알려주지 않는다** —
/// 링크를 주운 사람에게 탐침을 쥐여주지 않기 위해서다(운영 추적은 로그로 한다).
function refusalMessage(refusal) {
  switch (refusal) {
    case REFUSAL.linkExpired:
      return '승인 링크가 만료됐어요. 요청하신 분께 새 링크를 받아주세요.';
    case REFUSAL.linkUsed:
      return '이미 처리된 요청이에요.';
    case REFUSAL.tooManyAttempts:
      return '시도 횟수를 초과했어요. 요청하신 분께 새 링크를 받아주세요.';
    case REFUSAL.subjectChanged:
      return '요청 내용이 변경되어 승인할 수 없어요. 새 링크를 받아주세요.';
    case REFUSAL.representativeMismatch:
      return '본인확인하신 성함이 사업자등록상 대표자와 달라 승인할 수 없어요.';
    case REFUSAL.representativeCiMismatch:
      // ⚠️ "당신은 대표자가 아니다"라고 말하지 않는다. 먼저 확인된 쪽이
      //    진짜라는 보장이 없으므로(파일 상단), 사실만 말하고 사람에게 넘긴다.
      return '이 사업자에 기존에 확인된 대표자 본인확인 정보와 일치하지 않아 '
        + '자동으로 처리할 수 없어요. 고객센터로 문의해주세요.';
    case REFUSAL.delegateLimit:
      return '이 사업자에 부여할 수 있는 운영 권한 수를 초과했어요.';
    case REFUSAL.notGrantor:
      return '이 권한을 부여하신 분만 취소할 수 있어요.';
    case REFUSAL.notApproved:
      return '이미 취소되었거나 유효하지 않은 위임이에요.';
    default:
      return '요청을 처리할 수 없어요. 요청하신 분께 새 링크를 받아주세요.';
  }
}

/// 이번 승인이 신청자 문서에 쓸 권한 판정.
function delegatedDecision(delegationId) {
  return {
    authorization: AUTHORIZATION.delegated,
    authorizationReason: null,
    // ⚠️ 위임은 **점유하지 않는다.** 점유(businessOwnership.holderUid)는 대표자
    //    본인의 자리이고, 위임 운영자가 그것을 가져가면 대표자 본인이 나중에
    //    자기 사업자에서 막힌다.
    claimOwnership: false,
    delegationId,
  };
}

/// 위임이 끊긴 계정이 되돌아갈 상태 — 권한만 닫고 사업자 진위는 건드리지 않는다.
function revokedPatch(now) {
  return {
    authorization: AUTHORIZATION.pendingOwnerApproval,
    authorizationReason: AUTH_REASON.delegationRevoked,
    delegationId: null,
    authorizedAt: null,
    // status·businessNumber는 그대로 둔다 — 사업자 자체는 여전히 실재한다.
    // 이미 모집 중인 파티도 끊지 않는다(규칙은 create만 막는다).
    revokedAt: now,
  };
}

// ══════════════════════════════════════════════════════════════════════════
// Firestore
// ══════════════════════════════════════════════════════════════════════════

const delegationRef = (db, id) => db.collection(DELEGATIONS).doc(id);
const sessionRef = (db, id) => db.collection(APPROVAL_SESSIONS).doc(id);
const ownerRefOf = (db, bNo) =>
  db.collection(BUSINESS_OWNERSHIP).doc(businessNumberHash(bNo));

/// 토큰 해시로 위임 문서를 찾는다. 원문은 절대 저장돼 있지 않으므로 해시로만
/// 찾을 수 있다. 단일 필드라 Firestore 자동 색인으로 충분하다.
async function findByTokenHash(db, field, hash) {
  const snap = await db.collection(DELEGATIONS).where(field, '==', hash).limit(1).get();
  if (snap.empty) return null;
  return { id: snap.docs[0].id, ...snap.docs[0].data() };
}

/// 이 사업자에 지금 살아 있는 위임 수.
async function countActiveDelegates(db, bnHash) {
  const snap = await db
    .collection(DELEGATIONS)
    .where('businessNumberHash', '==', bnHash)
    .where('status', '==', STATUS.approved)
    .get();
  return snap.size;
}

/// 대표자에게 파티츄 계정이 있으면 그 uid — **읽기 전용.**
/// 없으면 null이고, 아무 문서도 만들지 않는다.
async function lookupGrantorUid(db, ciHash) {
  try {
    const snap = await db.collection(IDENTITY_LINKS).doc(ciHash).get();
    if (!snap.exists) return null;
    const d = snap.data();
    return d.status === 'active' ? (d.uid || null) : null;
  } catch (e) {
    // 감사 편의 값일 뿐이라 실패해도 승인을 막지 않는다.
    console.warn('[bizDelegation] grantorUid 조회 실패', e && e.message);
    return null;
  }
}

// ── 요청 생성 ───────────────────────────────────────────────────────────

/**
 * 승인 요청을 만들고 **일회성 링크**를 돌려준다.
 *
 * 같은 신청자의 기존 `requested` 요청은 전부 만료시킨다 — 살아 있는 링크를
 * 하나로 유지해야 "어느 링크가 유효한가"가 흔들리지 않는다.
 */
async function createDelegationRequest(db, uid, { now, todayKey }) {
  const userRef = db.collection('users').doc(uid);

  return db.runTransaction(async (tx) => {
    const userSnap = await tx.get(userRef);
    const userData = userSnap.exists ? userSnap.data() : null;

    // 게이트: 본인확인. 대표자 승인이라도 **신청자**는 회원이어야 한다.
    assertIdentityVerifiedData(userData);

    const bv = (userData && userData.businessVerification) || {};
    const subject = resolvePendingSubject(bv);
    if (!subject) {
      throw new HttpsError(
        'failed-precondition',
        '대표자 승인이 필요한 사업자 정보가 없어요. 사업자 인증을 먼저 진행해주세요.',
      );
    }

    // 하루 요청 생성 제한. 카운터를 businessVerification 안에 두는 이유는
    // 그 맵 전체가 클라이언트 쓰기 금지 필드라서다 — 바깥에 새 필드를 만들면
    // 규칙의 잠금 목록 밖이라 클라이언트가 초기화할 수 있다.
    const quota = bv.delegationRequest || {};
    const usedToday = quota.date === todayKey ? (quota.count || 0) : 0;
    if (usedToday >= MAX_REQUESTS_PER_DAY) {
      throw new HttpsError(
        'resource-exhausted',
        `하루 승인 요청 횟수(${MAX_REQUESTS_PER_DAY}회)를 초과했어요. 내일 다시 시도해주세요.`,
      );
    }

    const bnHash = businessNumberHash(subject.input.businessNumber);
    const activeCount = await countActiveDelegates(db, bnHash);
    if (activeCount >= MAX_ACTIVE_DELEGATES) {
      throw new HttpsError(
        'resource-exhausted',
        '이 사업자에 부여할 수 있는 운영 권한 수를 초과했어요.',
      );
    }

    // 살아 있는 이전 요청을 만료시킨다(링크는 항상 하나만 유효하다).
    const prior = await db
      .collection(DELEGATIONS)
      .where('granteeUid', '==', uid)
      .where('status', '==', STATUS.requested)
      .get();

    const token = newToken();
    const ref = db.collection(DELEGATIONS).doc();
    const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + REQUEST_TTL_MS);

    for (const doc of prior.docs) {
      tx.set(doc.ref, {
        status: STATUS.expired,
        expiredAt: now,
        expiredReason: 'superseded',
        updatedAt: now,
      }, { merge: true });
    }

    tx.set(ref, {
      granteeUid: uid,
      businessNumberHash: bnHash,
      // 원문 대신 표시용 마스킹만 — 이 문서에 사업자번호 원문은 두지 않는다.
      businessNumberMasked: maskForDisplay(subject.input.businessNumber),
      subjectFingerprint: subjectFingerprint({
        granteeUid: uid,
        businessNumber: subject.input.businessNumber,
        openingDate: subject.input.openingDate,
        representativeName: subject.input.representativeName,
      }),
      requestTokenHash: hashToken(token),
      manageTokenHash: null,
      status: STATUS.requested,
      attemptCount: 0,
      requestedAt: now,
      expiresAt,
      updatedAt: now,
      // 승인 전에는 대표자에 대해 아는 것이 하나도 없다.
      grantorCiHash: null,
      grantorUid: null,
      approvalMethod: null,
      niceTransactionId: null,
    });

    tx.set(userRef, {
      businessVerification: {
        delegationRequest: { date: todayKey, count: usedToday + 1 },
      },
    }, { merge: true });

    return {
      delegationId: ref.id,
      token,
      expiresAtMs: expiresAt.toMillis(),
      businessNumberMasked: maskForDisplay(subject.input.businessNumber),
    };
  });
}

// ── NICE 세션 시작 ──────────────────────────────────────────────────────

/**
 * 대표자용 NICE 인증 URL을 발급하고 세션을 만든다.
 *
 * ⚠️ 세션 문서 id는 uid가 아니라 **무작위 값**이다 — 대표자는 계정이 없을 수
 *    있다. 그 id는 HttpOnly 쿠키로만 브라우저에 남는다.
 */
async function startApprovalSession(db, { delegation, action, clientId, clientSecret }) {
  const { accessToken, iterators, ticket } = await getAccessToken(clientId, clientSecret);

  const requestNo = niceRequestNo();
  const { status, body } = await postNiceIntc(
    '/ido/intc/v1.0/auth/url',
    {
      request_no: requestNo,
      return_url: APPROVAL_RETURN_URL,
      close_url: APPROVAL_CLOSE_URL,
      svc_types: ['M'],
      method_type: 'GET',
      exp_mods: ['closeButtonOn'],
    },
    { Authorization: `Bearer ${accessToken}`, 'X-Intc-DevLang': 'Linux/Node.js' },
  );

  if (status !== 200 || body.result_code !== '0000') {
    console.error('[bizDelegation] 인증URL 요청 실패:', {
      delegationId: delegation.id, httpStatus: status, result_code: body.result_code,
    });
    throw new HttpsError('internal', 'NICE 인증 준비에 실패했습니다.');
  }

  const sid = crypto.randomBytes(24).toString('base64url');
  await sessionRef(db, sid).set({
    // 목적 — 결과 처리기가 맨 앞에서 단언한다.
    purpose: APPROVAL_PURPOSE,
    action, // 'approve' | 'revoke'
    delegationId: delegation.id,
    requestNo,
    transactionId: body.transaction_id,
    ticket,
    iterators,
    used: false,
    // 대표자는 **본인확인 전에** 무엇을 승인하는지 보고 동의했다.
    consentAt: admin.firestore.FieldValue.serverTimestamp(),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + SESSION_TTL_MS),
  });

  await delegationRef(db, delegation.id).set({
    attemptCount: admin.firestore.FieldValue.increment(1),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  return { sid, authUrl: body.auth_url };
}

/// NICE 인증 결과를 받아 복호화한다. **여기서 identity를 만들지 않는다.**
async function fetchNiceResult(session, webTransactionId, clientId, clientSecret) {
  const { accessToken } = await getAccessToken(clientId, clientSecret);
  const { status, body } = await postNiceIntc(
    '/ido/intc/v1.0/auth/result',
    {
      web_transaction_id: webTransactionId,
      transaction_id: session.transactionId,
      request_no: session.requestNo,
    },
    { Authorization: `Bearer ${accessToken}`, 'X-Intc-DevLang': 'Linux/Node.js' },
  );
  if (status !== 200 || body.result_code !== '0000') {
    throw new HttpsError('cancelled', 'NICE 인증이 취소되었거나 실패했습니다.');
  }
  // 무결성 HMAC 대조 → AES-256-GCM 복호화(공용 모듈).
  return verifyAndDecrypt(body, session, 'bizDelegation');
}

// ── 승인 확정 ───────────────────────────────────────────────────────────

/**
 * 12개 검사를 모두 통과했을 때에만 `delegated`를 쓴다 — **한 트랜잭션에서**
 * 위임·세션·신청자 문서·점유 문서를 함께 갱신한다.
 */
async function completeApproval(db, { sid, niceResult }) {
  const niceName = String(niceResult.name || '').trim();
  const niceCiHash = hashCi(niceResult.ci || '');
  const grantorUid = await lookupGrantorUid(db, niceCiHash);

  const sRef = sessionRef(db, sid);
  const preSession = await sRef.get();
  if (!preSession.exists) return { ok: false, refusal: REFUSAL.sessionInvalid };
  const delegationId = preSession.data().delegationId;
  const dRef = delegationRef(db, delegationId);

  // 상한 검사에 쓰는 값 — 트랜잭션 밖에서 센다(정확한 상한이 아니라 방어선이다).
  const preDelegation = await dRef.get();
  if (!preDelegation.exists) return { ok: false, refusal: REFUSAL.linkInvalid };
  const activeDelegateCount = await countActiveDelegates(
    db, preDelegation.data().businessNumberHash,
  );

  return db.runTransaction(async (tx) => {
    // ⚠️ 읽기를 전부 먼저.
    const [sessionSnap, delegationSnap] = await Promise.all([tx.get(sRef), tx.get(dRef)]);
    const session = sessionSnap.exists ? sessionSnap.data() : null;
    const delegation = delegationSnap.exists
      ? { id: delegationSnap.id, ...delegationSnap.data() }
      : null;

    const granteeUid = delegation && delegation.granteeUid;
    const userRef = granteeUid ? db.collection('users').doc(granteeUid) : null;
    const userSnap = userRef ? await tx.get(userRef) : null;
    const userData = userSnap && userSnap.exists ? userSnap.data() : null;
    const bv = (userData && userData.businessVerification) || {};
    const subject = resolvePendingSubject(bv);

    const ownerRef = subject ? ownerRefOf(db, subject.input.businessNumber) : null;
    const ownerSnap = ownerRef ? await tx.get(ownerRef) : null;
    const ownerData = ownerSnap && ownerSnap.exists ? ownerSnap.data() : null;

    const verdict = evaluateApproval({
      delegation,
      session,
      now: Date.now(),
      consent: true, // 세션 생성 시 동의를 받았고, consentAt으로 다시 확인한다
      niceName,
      niceCiHash,
      subject,
      subjectFingerprintNow: subject
        ? subjectFingerprint({
          granteeUid,
          businessNumber: subject.input.businessNumber,
          openingDate: subject.input.openingDate,
          representativeName: subject.input.representativeName,
        })
        : null,
      granteeCiHash: ciHashOfUserData(userData),
      ownershipRepCiHash: (ownerData && ownerData.representativeCiHash) || null,
      ownershipRepLevel: representativeLevelOf(ownerData),
      activeDelegateCount,
    });

    if (!verdict.ok) {
      // 거절도 문서에 남긴다 — 상태는 그대로 requested다(다시 시도할 수 있다).
      //
      // representativeCiMismatch는 **자동으로는 풀 수 없는 충돌**이다:
      // 같은 사업자에 대해 서로 다른 자연인이 대표자를 주장했다는 뜻인데,
      // 양쪽 근거가 모두 이름 대조뿐이라 우열을 가릴 수 없다. 먼저 온 쪽이
      // 동명이인이고 지금 온 쪽이 실제 대표자일 수도 있다. 그 사실을
      // 플래그로 남겨 관리자가 찾을 수 있게 한다(심사 절차는 다음 단계다).
      if (delegationSnap.exists) {
        tx.set(dRef, {
          lastRefusal: verdict.refusal,
          lastRefusedAt: admin.firestore.FieldValue.serverTimestamp(),
          needsManualReview: verdict.refusal === REFUSAL.representativeCiMismatch,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }
      return verdict;
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    const manageToken = newToken();

    // ① 위임 승인.
    tx.set(dRef, {
      status: STATUS.approved,
      approvalMethod: 'nice',
      grantorCiHash: niceCiHash,
      grantorUid,
      niceTransactionId: session.transactionId,
      manageTokenHash: hashToken(manageToken),
      // 승인 링크는 여기서 죽는다 — 같은 토큰으로 다시 들어올 수 없다.
      requestTokenHash: null,
      approvedAt: now,
      updatedAt: now,
      ntsSnapshot: {
        ntsStatusLabel: subject.input.ntsStatusLabel,
        taxType: subject.input.taxType,
      },
    }, { merge: true });

    // ② 세션 소비 — **성공이 확정된 시점에만**(niceAuthResult와 같은 이유).
    tx.set(sRef, { used: true, usedAt: now }, { merge: true });

    // ③ 신청자 문서 — 어떻게 쓸지는 resolveVerificationWrite 하나가 정한다.
    const resolved = resolveVerificationWrite({
      prev: bv,
      outcome: outcomeFromSubject(subject.input),
      decision: delegatedDecision(delegation.id),
      input: subject.input,
      now,
      historyNow: admin.firestore.Timestamp.now(),
      todayKey: bv.attemptDate || '',
      attemptsToday: bv.attemptDate ? (bv.attemptCount || 0) : 0,
    });
    tx.set(userRef, { businessVerification: resolved.record }, { merge: true });

    // ④ 대표자 CI 기록 — "이 사업자의 대표자라고 주장하며 본인확인을 통과한
    //    자연인"을 적어 둔다. **대표자임이 증명된 사람이 아니다**(이름 대조
    //    등급). 나중에 다른 CI가 같은 주장을 하면 충돌로 알아채기 위한 값이다.
    //
    //    holderUid는 건드리지 않는다 — 대표자 본인 계정의 자리다.
    //    이미 같은 CI가 박혀 있으면 등급도 그대로다(덮어써도 같은 값).
    tx.set(ownerRef, {
      businessNumberMasked: maskBusinessNumber(subject.input.businessNumber),
      representativeCiHash: niceCiHash,
      representativeVerificationLevel: REP_VERIFICATION_LEVEL.nameMatched,
      representativeSource: 'ownerApproval',
      representativePinnedAt: now,
      status: ownerData ? ownerData.status : OWNERSHIP_STATUS.active,
      updatedAt: now,
    }, { merge: true });

    return { ok: true, refusal: null, manageToken, delegationId: delegation.id };
  });
}

// ── 취소 확정 ───────────────────────────────────────────────────────────

async function completeRevoke(db, { sid, niceResult }) {
  const niceName = String(niceResult.name || '').trim();
  const niceCiHash = hashCi(niceResult.ci || '');

  const sRef = sessionRef(db, sid);
  const preSession = await sRef.get();
  if (!preSession.exists) return { ok: false, refusal: REFUSAL.sessionInvalid };
  const dRef = delegationRef(db, preSession.data().delegationId);

  return db.runTransaction(async (tx) => {
    const [sessionSnap, delegationSnap] = await Promise.all([tx.get(sRef), tx.get(dRef)]);
    const session = sessionSnap.exists ? sessionSnap.data() : null;
    const delegation = delegationSnap.exists
      ? { id: delegationSnap.id, ...delegationSnap.data() }
      : null;

    const granteeUid = delegation && delegation.granteeUid;
    const userRef = granteeUid ? db.collection('users').doc(granteeUid) : null;
    const userSnap = userRef ? await tx.get(userRef) : null;
    const bv = (userSnap && userSnap.exists && userSnap.data().businessVerification) || {};

    const verdict = evaluateRevoke({
      delegation,
      session,
      now: Date.now(),
      niceName,
      niceCiHash,
      // 취소 시점의 대표자명은 신청자 문서의 현재 사업자에서 읽는다.
      subjectRepName: bv.representativeName || '',
    });
    if (!verdict.ok) return verdict;

    const now = admin.firestore.FieldValue.serverTimestamp();

    tx.set(dRef, {
      status: STATUS.revoked,
      revokedAt: now,
      revokedBy: 'representative',
      manageTokenHash: null, // 관리 링크도 여기서 죽는다
      updatedAt: now,
    }, { merge: true });
    tx.set(sRef, { used: true, usedAt: now }, { merge: true });

    // 이 위임으로 열린 권한만 닫는다 — 그 사이 다른 근거로 권한을 얻었다면
    // (본인 명의 재인증 등) 건드리지 않는다.
    if (userRef && bv.delegationId === delegation.id) {
      tx.set(userRef, {
        businessVerification: revokedPatch(now),
      }, { merge: true });
    }

    return { ok: true, refusal: null, delegationId: delegation.id };
  });
}

/**
 * 신청자 탈퇴 시 그 계정의 위임을 끊는다.
 *
 * accountWithdrawal이 개인정보를 지우기 **전에** 부른다 — 지운 뒤에는
 * businessVerification이 사라져 어느 위임이 이 계정 것인지 알 수 없다
 * (releaseIdentityLink와 같은 순서 함정).
 */
async function revokeDelegationsForGrantee(db, uid) {
  const snap = await db
    .collection(DELEGATIONS)
    .where('granteeUid', '==', uid)
    .where('status', 'in', [STATUS.requested, STATUS.approved])
    .get();
  if (snap.empty) return { revoked: 0 };

  const now = admin.firestore.FieldValue.serverTimestamp();
  const batch = db.batch();
  for (const doc of snap.docs) {
    batch.set(doc.ref, {
      status: STATUS.revoked,
      revokedAt: now,
      revokedBy: 'granteeWithdrawal',
      requestTokenHash: null,
      manageTokenHash: null,
      updatedAt: now,
    }, { merge: true });
  }
  await batch.commit();
  console.log(`[bizDelegation] 탈퇴로 위임 취소. uid=${uid} count=${snap.size}`);
  return { revoked: snap.size };
}

// ══════════════════════════════════════════════════════════════════════════
// 콜러블 — 신청자 쪽
// ══════════════════════════════════════════════════════════════════════════

exports.requestBusinessDelegation = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const uid = request.auth.uid;
    const db = admin.firestore();

    const result = await createDelegationRequest(db, uid, {
      now: admin.firestore.FieldValue.serverTimestamp(),
      todayKey: new Date().toISOString().slice(0, 10),
    });

    // ⚠️ 토큰 원문은 **이 응답에서 한 번만** 나간다. 로그에 남기지 않는다.
    console.log(
      `[bizDelegation] 승인 요청 생성. uid=${uid} delegationId=${result.delegationId}`,
    );

    return {
      delegationId: result.delegationId,
      approvalUrl: `${APPROVAL_BASE}?t=${encodeURIComponent(result.token)}`,
      expiresAtMs: result.expiresAtMs,
      businessNumberMasked: result.businessNumberMasked,
    };
  },
);

/// 신청자가 자기 요청의 진행 상태를 본다(토큰은 돌려주지 않는다).
exports.getBusinessDelegationStatus = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const db = admin.firestore();
    const snap = await db
      .collection(DELEGATIONS)
      .where('granteeUid', '==', request.auth.uid)
      .orderBy('requestedAt', 'desc')
      .limit(1)
      .get();
    if (snap.empty) return { exists: false };
    const d = snap.docs[0].data();
    return {
      exists: true,
      delegationId: snap.docs[0].id,
      status: d.status,
      businessNumberMasked: d.businessNumberMasked || '',
      expiresAtMs: toMillis(d.expiresAt),
      requestedAtMs: toMillis(d.requestedAt),
    };
  },
);

// ══════════════════════════════════════════════════════════════════════════
// 웹 — 대표자 쪽 (로그인 없이 접근한다)
// ══════════════════════════════════════════════════════════════════════════

function page(title, bodyHtml) {
  return `<!DOCTYPE html><html lang="ko"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<meta name="referrer" content="no-referrer">
<title>${escapeHtml(title)}</title>
<style>
:root{color-scheme:light}
body{margin:0;background:#FFF4F8;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#111}
.wrap{max-width:420px;margin:0 auto;padding:32px 20px 56px}
.card{background:#fff;border-radius:16px;padding:22px;box-shadow:0 1px 3px rgba(0,0,0,.06)}
h1{font-size:20px;margin:0 0 6px}
p{font-size:14px;line-height:1.6;color:#444;margin:8px 0}
.kv{display:flex;gap:10px;font-size:13px;padding:7px 0;border-top:1px solid #F1F1F4}
.kv b{width:96px;color:#888;font-weight:500;flex:none}
.grant{background:#FFF7FA;border:1px solid #FFD6E4;border-radius:12px;padding:14px;margin:16px 0;font-size:14px;line-height:1.6}
.note{font-size:12px;color:#888;line-height:1.6;margin-top:14px}
button{width:100%;height:50px;border:0;border-radius:12px;background:#FF6FA0;color:#fff;font-size:15px;font-weight:700;cursor:pointer}
button.ghost{background:#fff;color:#666;border:1px solid #E5E7EB;height:44px;font-weight:500;margin-top:10px}
.ok{color:#047857}.bad{color:#B91C1C}
label{display:flex;gap:9px;align-items:flex-start;font-size:13px;line-height:1.5;margin:14px 0;cursor:pointer}
input[type=checkbox]{margin-top:2px;width:17px;height:17px;flex:none;accent-color:#FF6FA0}
code{background:#F3F4F6;padding:2px 6px;border-radius:5px;font-size:12px;word-break:break-all}
</style></head><body><div class="wrap"><div class="card">${bodyHtml}</div></div></body></html>`;
}

function resultPage(okTitle, message, extraHtml = '') {
  return page(okTitle, `<h1>${escapeHtml(okTitle)}</h1><p>${escapeHtml(message)}</p>${extraHtml}`);
}

function parseCookies(req) {
  const raw = req.headers.cookie || '';
  const out = {};
  for (const part of raw.split(';')) {
    const i = part.indexOf('=');
    if (i < 0) continue;
    out[part.slice(0, i).trim()] = decodeURIComponent(part.slice(i + 1).trim());
  }
  return out;
}

/// 승인/취소 랜딩 — **최소 정보만** 보여준다.
///
/// 상호명은 신청자가 자기 신고한 값이라 화면에 쓰지 않는다(공격자가 문구를
/// 통제하는 길이 된다). 대표자가 자기 사업장을 알아보는 데는 마스킹된
/// 사업자번호로 충분하고, 요청자는 검증된 닉네임으로 가리킨다.
function landingHtml({ action, delegation, granteeNickname }) {
  const isRevoke = action === 'revoke';
  const who = escapeHtml(granteeNickname || '요청자');
  const grant = isRevoke
    ? `<b>${who}</b>님에게 부여한 이 사업장의 파티츄 운영 권한을 <b>취소</b>합니다.`
    : `<b>${who}</b>님이 이 사업장을 파티츄에서 운영하도록 <b>허용</b>합니다.`;

  return page(isRevoke ? '운영 권한 취소' : '사업장 운영 권한 승인', `
<h1>${isRevoke ? '운영 권한 취소' : '사업장 운영 권한 승인'}</h1>
<p>${isRevoke ? '아래 권한을 취소하려면' : '아래 내용을 확인하시고'} 대표자 본인확인을 진행해주세요.</p>
<div class="kv"><b>사업자등록번호</b><span>${escapeHtml(delegation.businessNumberMasked || '-')}</span></div>
<div class="kv"><b>${isRevoke ? '권한 보유자' : '요청자'}</b><span>${who}</span></div>
<div class="grant">${grant}</div>
<form method="POST" action="/biz-approval/start">
  <input type="hidden" name="t" value="${escapeHtml(delegation.__rawToken)}">
  <input type="hidden" name="action" value="${escapeHtml(action)}">
  <label><input type="checkbox" name="consent" value="1" required>
    위 내용에 동의하며, 본인이 이 사업자의 대표자임을 확인합니다.</label>
  <button type="submit">동의하고 본인확인</button>
</form>
<div class="note">
  · 휴대폰 본인확인(NICE)으로 확인된 성함이 국세청에 등록된 대표자와 같아야 ${isRevoke ? '취소' : '승인'}됩니다.<br>
  · 이 링크만으로는 아무 권한도 생기지 않습니다.<br>
  · 확인하는 것은 <b>성함 일치</b>까지입니다. 동명이인을 가려내지는 못하므로,
    이후 다른 분이 같은 사업장의 대표자로 확인을 시도하면 자동 처리가 멈추고
    고객센터 확인 절차로 넘어갑니다.<br>
  · 본인이 요청한 적이 없다면 이 페이지를 닫고 링크를 보낸 사람에게 확인해주세요.
</div>`);
}

exports.businessApprovalPage = onRequest(
  { secrets: [niceClientId, niceClientSecret], ...NICE_FUNCTION_OPTIONS },
  async (req, res) => {
    const db = admin.firestore();
    const html = (code, body) =>
      res.status(code).set('Content-Type', 'text/html; charset=utf-8')
        .set('Cache-Control', 'no-store').send(body);

    // Hosting rewrite는 원래 경로를 그대로 넘긴다.
    const path = (req.path || '/').replace(/^\/biz-approval/, '') || '/';

    try {
      // ── 랜딩(승인) ──────────────────────────────────────────────────
      if (path === '/' && req.method === 'GET') {
        const token = String(req.query.t || '');
        const d = token ? await findByTokenHash(db, 'requestTokenHash', hashToken(token)) : null;
        if (!d || d.status !== STATUS.requested || (toMillis(d.expiresAt) ?? 0) <= Date.now()) {
          return html(404, resultPage('링크를 확인할 수 없어요',
            refusalMessage(d ? REFUSAL.linkExpired : REFUSAL.linkInvalid)));
        }
        const g = await db.collection('users').doc(d.granteeUid).get();
        return html(200, landingHtml({
          action: 'approve',
          delegation: { ...d, __rawToken: token },
          granteeNickname: g.exists ? g.data().nickname : '',
        }));
      }

      // ── 랜딩(취소) ──────────────────────────────────────────────────
      if (path === '/manage' && req.method === 'GET') {
        const token = String(req.query.t || '');
        const d = token ? await findByTokenHash(db, 'manageTokenHash', hashToken(token)) : null;
        if (!d || d.status !== STATUS.approved) {
          return html(404, resultPage('링크를 확인할 수 없어요',
            refusalMessage(d ? REFUSAL.notApproved : REFUSAL.linkInvalid)));
        }
        const g = await db.collection('users').doc(d.granteeUid).get();
        return html(200, landingHtml({
          action: 'revoke',
          delegation: { ...d, __rawToken: token },
          granteeNickname: g.exists ? g.data().nickname : '',
        }));
      }

      // ── 본인확인 시작 ───────────────────────────────────────────────
      if (path === '/start' && req.method === 'POST') {
        const body = req.body || {};
        const action = body.action === 'revoke' ? 'revoke' : 'approve';
        const token = String(body.t || '');
        if (body.consent !== '1' && body.consent !== true) {
          return html(400, resultPage('동의가 필요해요',
            '내용에 동의하셔야 본인확인을 진행할 수 있어요.'));
        }
        const field = action === 'revoke' ? 'manageTokenHash' : 'requestTokenHash';
        const want = action === 'revoke' ? STATUS.approved : STATUS.requested;
        const d = token ? await findByTokenHash(db, field, hashToken(token)) : null;
        if (!d || d.status !== want) {
          return html(404, resultPage('링크를 확인할 수 없어요', refusalMessage(REFUSAL.linkInvalid)));
        }
        if (action === 'approve' && (toMillis(d.expiresAt) ?? 0) <= Date.now()) {
          return html(410, resultPage('링크가 만료됐어요', refusalMessage(REFUSAL.linkExpired)));
        }
        if ((d.attemptCount || 0) >= MAX_NICE_ATTEMPTS) {
          return html(429, resultPage('시도 횟수를 초과했어요',
            refusalMessage(REFUSAL.tooManyAttempts)));
        }

        const { sid, authUrl } = await startApprovalSession(db, {
          delegation: d,
          action,
          clientId: niceClientId.value().trim(),
          clientSecret: niceClientSecret.value().trim(),
        });
        // HttpOnly — 페이지 스크립트가 읽지 못한다. SameSite=Lax라 NICE에서
        // 돌아오는 최상위 GET 이동에는 그대로 실린다.
        res.set('Set-Cookie',
          `${SESSION_COOKIE}=${sid}; Max-Age=600; Path=/biz-approval; HttpOnly; Secure; SameSite=Lax`);
        return res.redirect(302, authUrl);
      }

      // ── NICE 복귀 ───────────────────────────────────────────────────
      if (path === '/callback' && req.method === 'GET') {
        const sid = parseCookies(req)[SESSION_COOKIE];
        const webTransactionId = String(req.query.web_transaction_id || '');
        if (!sid || !webTransactionId) {
          return html(400, resultPage('본인확인을 완료하지 못했어요',
            '처음부터 다시 시도해주세요.'));
        }
        const sSnap = await sessionRef(db, sid).get();
        if (!sSnap.exists) {
          return html(400, resultPage('본인확인 세션이 없어요', '처음부터 다시 시도해주세요.'));
        }
        const session = sSnap.data();
        // ⚠️ 목적 단언 — 회원 본인확인 세션이 이 경로를 타면 안 된다.
        if (session.purpose !== APPROVAL_PURPOSE) {
          console.error('[bizDelegation] 세션 목적 불일치', { sid, purpose: session.purpose });
          return html(400, resultPage('처리할 수 없는 요청이에요', '처음부터 다시 시도해주세요.'));
        }

        const niceResult = await fetchNiceResult(
          session, webTransactionId,
          niceClientId.value().trim(), niceClientSecret.value().trim(),
        );

        const isRevoke = session.action === 'revoke';
        const out = isRevoke
          ? await completeRevoke(db, { sid, niceResult })
          : await completeApproval(db, { sid, niceResult });

        if (!out.ok) {
          console.warn(`[bizDelegation] ${isRevoke ? '취소' : '승인'} 거절.`
            + ` delegationId=${session.delegationId} refusal=${out.refusal}`);
          return html(200, resultPage(
            isRevoke ? '취소하지 못했어요' : '승인하지 못했어요',
            refusalMessage(out.refusal),
          ));
        }

        console.log(`[bizDelegation] ${isRevoke ? '취소' : '승인'} 완료.`
          + ` delegationId=${out.delegationId}`);

        if (isRevoke) {
          return html(200, resultPage('운영 권한을 취소했어요',
            '해당 계정의 사업장 운영 권한이 즉시 해제됐어요.'));
        }
        const manageUrl = `${APPROVAL_BASE}/manage?t=${encodeURIComponent(out.manageToken)}`;
        return html(200, resultPage(
          '운영 권한을 승인했어요',
          '요청하신 분이 이제 이 사업장으로 파티츄를 운영할 수 있어요.',
          `<div class="grant"><b>권한 취소 링크</b><br>
             나중에 권한을 취소하시려면 아래 링크를 보관해주세요. 취소할 때도
             대표자 본인확인이 필요합니다.<br><br>
             <code>${escapeHtml(manageUrl)}</code></div>`,
        ));
      }

      if (path === '/closed') {
        return html(200, resultPage('본인확인을 취소했어요', '창을 닫으셔도 됩니다.'));
      }

      return html(404, resultPage('페이지를 찾을 수 없어요', '주소를 다시 확인해주세요.'));
    } catch (err) {
      const e = err instanceof HttpsError ? err : toNiceHttpsError(err);
      console.error('[bizDelegation] 처리 오류', { code: e.code, message: e.message });
      return html(500, resultPage('처리 중 오류가 발생했어요', '잠시 후 다시 시도해주세요.'));
    }
  },
);

module.exports.DELEGATIONS = DELEGATIONS;
module.exports.APPROVAL_SESSIONS = APPROVAL_SESSIONS;
module.exports.APPROVAL_PURPOSE = APPROVAL_PURPOSE;
module.exports.STATUS = STATUS;
module.exports.REFUSAL = REFUSAL;
module.exports.REQUEST_TTL_MS = REQUEST_TTL_MS;
module.exports.SESSION_TTL_MS = SESSION_TTL_MS;
module.exports.MAX_NICE_ATTEMPTS = MAX_NICE_ATTEMPTS;
module.exports.MAX_REQUESTS_PER_DAY = MAX_REQUESTS_PER_DAY;
module.exports.MAX_ACTIVE_DELEGATES = MAX_ACTIVE_DELEGATES;
module.exports.newToken = newToken;
module.exports.hashToken = hashToken;
module.exports.hashCi = hashCi;
module.exports.subjectFingerprint = subjectFingerprint;
module.exports.resolvePendingSubject = resolvePendingSubject;
module.exports.pickSubjectInput = pickSubjectInput;
module.exports.outcomeFromSubject = outcomeFromSubject;
module.exports.maskForDisplay = maskForDisplay;
module.exports.landingHtml = landingHtml;
module.exports.refusalMessage = refusalMessage;
module.exports.evaluateApproval = evaluateApproval;
module.exports.evaluateRevoke = evaluateRevoke;
module.exports.refusalMessage = refusalMessage;
module.exports.delegatedDecision = delegatedDecision;
module.exports.revokedPatch = revokedPatch;
module.exports.createDelegationRequest = createDelegationRequest;
module.exports.completeApproval = completeApproval;
module.exports.completeRevoke = completeRevoke;
module.exports.revokeDelegationsForGrantee = revokeDelegationsForGrantee;

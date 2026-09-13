const admin = require('firebase-admin');
const crypto = require('crypto');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');

const popbill = require('./popbill');

// ══════════════════════════════════════════════════════════════════════════
// 호스트 **수취계좌**(payoutAccount) — 참가자가 무통장입금으로 돈을 보내는 곳.
//
// ── 이 앱의 계좌는 세 가지이고, 서로 절대 섞지 않는다 ─────────────────────
//   1. 참가자 → **호스트**    = users/{uid}.payoutAccount      ← 이 파일
//      파티·플레이스·장소대여·파티샵의 무통장입금 안내 계좌. 파티츄는 이 돈을
//      보관하지 않는다(에스크로/PG 집금이 아니다).
//   2. 파티츄 → 호스트        = users/{uid}.settlementInfo
//      **향후** 플랫폼 정산이 생길 때 쓸 계좌. 지금은 실제 송금 코드가 없다.
//   3. 호스트/파티츄 → 참가자 = users/{uid}.refundAccount (refundAccounts.js)
//
// 1과 2는 같은 사람의 계좌일 수 있지만 **역할이 다르다**. 한 필드로 합치면
// 나중에 정산이 붙는 순간 "이 계좌가 받는 계좌인지 보내는 계좌인지"가 사라진다.
//
// ── 왜 인증이 필요한가 ────────────────────────────────────────────────────
// 이 계좌는 참가자에게 그대로 안내되어 **실제 송금 대상**이 된다. 검증 없이
// 저장하면 오타 하나로 참가자 돈이 남의 계좌로 가고, 악의적으로는 타인 명의
// 계좌를 적어 둘 수도 있다. 그래서 두 겹으로 확인한다.
//   ① 은행이 알고 있는 예금주 성명 == 호스트가 입력한 예금주명  (팝빌 성명조회)
//   ② 그 성명 == 본인확인으로 확보한 호스트 실명(users.name)    (NICE 인증값)
//
// ── 클라이언트는 이 값을 절대 쓰지 못한다 ─────────────────────────────────
// payoutAccount / payoutAccountVerification 둘 다 **Admin SDK만** 기록한다
// (firestore.rules의 isVerificationFieldChange 잠금 목록). 인증 상태만 막고
// 계좌번호를 클라이언트가 쓰게 두면 "인증은 A계좌로 받고 저장은 B계좌로"라는
// 우회가 생기기 때문에, 계좌 원문까지 서버 전용으로 둔다.
// ══════════════════════════════════════════════════════════════════════════

const LOG = 'payoutAccount';

const popbillLinkId = defineSecret('POPBILL_LINK_ID');
const popbillSecretKey = defineSecret('POPBILL_SECRET_KEY');
const popbillCorpNum = defineSecret('POPBILL_CORP_NUM');

/**
 * 수취계좌 상태 — 앱의 PayoutAccountStatus와 키가 1:1로 맞다.
 *
 * `required`는 "계좌는 있는데 아직 인증되지 않았다"는 뜻이다. 계좌번호를
 * 고치면 인증이 자동으로 풀려 여기로 떨어진다([statusOf]의 지문 비교).
 */
const STATUS = {
  none: 'none', // 미등록
  required: 'required', // 인증 필요
  verified: 'verified', // 인증 완료
};

/**
 * 계좌 명의 유형 — **입금을 받을 계좌의 명의가 누구인지**만 구분한다.
 *
 * 이 값은 사업자 자격·사업자 인증 상태에 아무 영향도 주지 않는다. 사업자
 * 호스트가 대표자 개인계좌를 쓰겠다고 골라도 사업자 인증은 그대로다
 * (반대로 개인 호스트는 business를 고를 수 없다 — 사업자 인증이 없으니까).
 */
const ACCOUNT_TYPE = {
  personal: 'personal', // 개인(대표자 개인명의 포함)
  business: 'business', // 사업자·법인 명의
};

/** 인증이 실패한 이유 — 화면 문구는 앱이 만든다(여기서는 코드만 남긴다). */
const FAIL_REASON = {
  notConfigured: 'notConfigured', // 예금주조회 서비스 미연결(키 미발급)
  apiUnavailable: 'apiUnavailable', // 조회 서비스 일시 장애
  accountNotFound: 'accountNotFound', // 존재하지 않거나 조회 불가한 계좌
  holderMismatch: 'holderMismatch', // 예금주명이 입력값과 다름
  identityMismatch: 'identityMismatch', // 예금주가 본인확인 실명과 다름
  // ── 사업자·법인 명의 계좌 전용 ──────────────────────────────────────
  businessNotVerified: 'businessNotVerified', // 사업자 인증을 아직 마치지 않음
  businessHolderMismatch: 'businessHolderMismatch', // 예금주가 대표자명과 다름
};

// ── 금융기관 목록 ────────────────────────────────────────────────────────
//
// 금융결제원 표준 기관코드. 앱(lib/models/bank_codes.dart)에 **같은 표**를
// 두고, 저장·조회는 언제나 코드로 한다 — 기관 이름이 바뀌어도 이미 등록된
// 계좌의 식별자가 흔들리지 않는다.
//
// ── 표에 넣는 기준: 팝빌 성명조회가 지원하는가 ────────────────────────────
// 수취계좌는 인증에 성공해야만 게스트에게 안내되므로, 기준은 "송금이 되는
// 곳"이 아니라 **"팝빌 성명조회(CheckAccountInfo)가 예금주를 확인해 주는
// 곳"**이다. 팝빌 공식 「성명조회 지원기관」(은행 33 + 증권 29)이 정본이고,
// 거기 없는 기관은 넣지 않는다 — 넣어도 인증이 실패해 등록되지 않는다.
//
// 증권사(238·240·243·247·218·264·271·288 …)도 성명조회 지원기관이라 CMA 등
// 증권 계좌를 수취계좌로 쓸 수 있다. 코드 체계가 은행과 같아 팝빌 4자리 변환
// (popbill.toPopbillBankCode)에 예외를 둘 것이 없다.
//
// ⚠️ 팝빌 예금주조회의 기관코드가 이 표와 다른 기관이 있으면 연동 시점에
//    바로잡는다(팝빌 문서의 기관코드 표가 정본이다).
const BANK_NAMES = {
  // ── 은행 ──
  '002': '산업은행',
  '003': '기업은행',
  '004': '국민은행',
  '007': '수협은행',
  '011': '농협은행',
  // 농협은행(011)과 다른 기관코드다 — 지역 농·축협 단위조합 계좌.
  '012': '농축협(지역농협·축협)',
  '020': '우리은행',
  '023': 'SC제일은행',
  '027': '한국씨티은행',
  '031': '대구은행',
  '032': '부산은행',
  '034': '광주은행',
  '035': '제주은행',
  '037': '전북은행',
  '039': '경남은행',
  '045': '새마을금고',
  '048': '신협',
  '050': '저축은행',
  '064': '산림조합',
  '071': '우체국',
  '081': '하나은행',
  '088': '신한은행',
  '089': '케이뱅크',
  '090': '카카오뱅크',
  '092': '토스뱅크',
  // ── 증권 ── 팝빌 성명조회 지원 29곳. 표기는 현재 상호(0278은 팝빌 표의
  //           '신한금융투자'가 아니라 '신한투자증권'으로 적는다).
  '209': '유안타증권',
  '218': 'KB증권',
  '221': '상상인증권',
  '224': 'BNK투자증권',
  '225': 'IBK투자증권',
  '227': '다올투자증권',
  '238': '미래에셋증권',
  '240': '삼성증권',
  '243': '한국투자증권',
  '247': 'NH투자증권',
  '261': '교보증권',
  '262': '아이엠증권',
  '263': '현대차증권',
  '264': '키움증권',
  '265': 'LS증권',
  '266': 'SK증권',
  '267': '대신증권',
  '269': '한화투자증권',
  '270': '하나증권',
  '271': '토스증권',
  '278': '신한투자증권',
  '279': 'DB금융투자',
  '280': '유진투자증권',
  '287': '메리츠증권',
  '288': '카카오페이증권',
  '290': '부국증권',
  '291': '신영증권',
  '292': '케이프투자증권',
  '294': '우리투자증권',
};

// ── 순수 헬퍼 ────────────────────────────────────────────────────────────

/** 계좌번호에서 숫자만 남긴다 — '123-456-789'와 '123456789'는 같은 계좌다. */
function digitsOnly(value) {
  return String(value == null ? '' : value).replace(/[^0-9]/g, '');
}

/**
 * 로그·관리자 목록용 마스킹 — **뒤 4자리만** 남긴다.
 *
 * 계좌번호 원문은 로그·에러 메시지·분석 이벤트 어디에도 남기지 않는다
 * (businessVerification.js의 사업자번호 마스킹과 같은 규칙).
 */
function maskAccountNumber(value) {
  const digits = digitsOnly(value);
  if (!digits) return '';
  if (digits.length <= 4) return '*'.repeat(digits.length);
  return `${'*'.repeat(digits.length - 4)}${digits.slice(-4)}`;
}

/** 예금주명 비교용 정규화 — 공백 제거. 은행은 '홍 길동'을 주기도 한다. */
function normalizeHolderName(value) {
  return String(value == null ? '' : value).replace(/\s+/g, '');
}

/** 두 예금주명이 같은 사람인가 — 공백만 다른 경우는 같다고 본다. */
function holderMatches(a, b) {
  const x = normalizeHolderName(a);
  const y = normalizeHolderName(b);
  return x.length > 0 && x === y;
}

/**
 * 계좌 지문 — 은행+계좌번호의 sha256.
 *
 * 인증 결과를 **어느 계좌에 대한 것인지**로 묶어 둔다. 계좌를 바꾸면 지문이
 * 달라져 인증이 자동으로 풀린다(상태만 따로 들고 있으면, 인증받은 계좌를
 * 지우고 다른 계좌를 넣어도 '인증 완료'가 남는다).
 */
function accountFingerprint(account) {
  const a = account || {};
  // 은행·계좌번호뿐 아니라 **예금주와 명의 유형까지** 넣는다. 넷 중 하나라도
  // 바뀌면 지문이 달라져 [statusOf]가 곧바로 '인증 필요'로 떨어진다 —
  // 인증받은 계좌의 예금주만 바꿔 다른 사람의 계좌로 안내하는 길을 막는다.
  const parts = [
    String(a.bankCode || '').trim(),
    digitsOnly(a.accountNumber),
    normalizeHolderName(a.accountHolder),
    a.accountType === ACCOUNT_TYPE.business
      ? ACCOUNT_TYPE.business
      : ACCOUNT_TYPE.personal,
  ];
  return crypto.createHash('sha256').update(parts.join(':')).digest('hex');
}

/**
 * 저장 형태로 정규화한다. 하나라도 비면 null(= 등록으로 치지 않는다).
 *
 * @returns {{bankCode:string, bankName:string, accountNumber:string,
 *            accountHolder:string}|null}
 */
function normalizePayoutAccount(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const bankCode = String(raw.bankCode || '').trim();
  const bankName = BANK_NAMES[bankCode] || String(raw.bankName || '').trim();
  const accountNumber = digitsOnly(raw.accountNumber);
  const accountHolder = String(raw.accountHolder || '').trim();
  // 모르는 값·없는 값은 전부 개인으로 읽는다. 이 필드가 없던 기존 문서가
  // 그대로 열려야 하고, 사업자 경로는 **명시적으로 고른 경우에만** 탄다.
  const accountType =
    raw.accountType === ACCOUNT_TYPE.business
      ? ACCOUNT_TYPE.business
      : ACCOUNT_TYPE.personal;
  if (!bankCode || !bankName || !accountNumber || !accountHolder) return null;
  return { bankCode, bankName, accountNumber, accountHolder, accountType };
}

/**
 * 지금 이 사용자 문서의 수취계좌 상태 — 저장된 계좌와 인증 기록을 함께 본다.
 *
 * 인증 기록이 **지금 계좌의 지문과 다르면** 인증으로 치지 않는다.
 */
function statusOf(userData) {
  const account = normalizePayoutAccount((userData || {}).payoutAccount);
  if (!account) return STATUS.none;
  const v = (userData || {}).payoutAccountVerification || {};
  const sameAccount = v.accountFingerprint === accountFingerprint(account);
  return v.status === STATUS.verified && sameAccount
    ? STATUS.verified
    : STATUS.required;
}

// ── 인증 완료 후 30일 잠금 ────────────────────────────────────────────────
//
// 인증된 계좌는 그대로 게스트의 무통장입금 안내에 실린다. 인증만 받아 두고
// 곧바로 다른 계좌로 갈아끼우면 "검증된 계좌"라는 표시만 남고 실제 입금은
// 검증되지 않은 계좌로 가므로, 인증 완료 시점부터 30일 동안 계좌를 잠근다.
//
// 잠금 대상은 **금융기관·계좌번호·예금주명·계좌유형 전부**다. 넷 중 하나만
// 바뀌어도 다른 계좌이므로 따로 나눌 이유가 없고, 실제로 이 콜러블은 계좌
// 항목별 수정을 받지 않는다(언제나 한 벌을 통째로 인증한다).
//
// 잠금은 **인증에 성공했을 때만** 걸린다. 실패는 고쳐서 다시 시도해야 하는
// 상태이므로 잠그면 계좌를 영영 등록할 수 없게 된다.
const LOCK_DAYS = 30;
const LOCK_MS = LOCK_DAYS * 24 * 60 * 60 * 1000;

// 같은 요청이 겹쳐 들어온 것으로 볼 시간. 팝빌 조회는 건당 과금이라 버튼
// 연타·재시도로 두 번 나가면 그대로 두 번 청구된다. 함수 타임아웃(30초)보다
// 길게 잡아, 앞 호출이 죽어도 이 시간이 지나면 스스로 풀린다.
const IN_FLIGHT_TTL_MS = 60 * 1000;

/**
 * Firestore Timestamp·Date·숫자를 epoch ms로. 읽을 수 없으면 null.
 *
 * 문서에서 온 값은 Timestamp지만, self-check와 콜러블 응답에서는 Date·숫자로도
 * 다룬다. 여기서 한 번에 흡수해 두면 잠금 계산이 값의 출처를 몰라도 된다.
 */
function toMillis(value) {
  if (value == null) return null;
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value._seconds === 'number') {
    return value._seconds * 1000 + Math.floor((value._nanoseconds || 0) / 1e6);
  }
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  return null;
}

/**
 * 잠금이 풀리는 시각(epoch ms). 잠금이 걸릴 상태가 아니면 null.
 *
 * 기준 시각은 **인증이 완료된 그 순간**이고, 이미 `payoutAccountVerification`
 * .checkedAt에 서버 시각으로 들어 있다 — 잠금 때문에 새 필드를 만들지 않는다.
 * 그 값이 인증 완료 시각인 이유: checkedAt은 인증을 시도할 때마다 갱신되지만,
 * 상태가 verified가 된 뒤로는 이 콜러블이 잠금에 걸려 아무것도 쓰지 않는다.
 *
 * 시각을 읽지 못하면 null을 준다(= 잠그지 않는다). 인증 기록이 깨진 계정을
 * 영구히 묶어 두는 쪽이, 잠금이 한 번 안 걸리는 쪽보다 나쁘다.
 */
function lockedUntilOf(userData) {
  if (statusOf(userData) !== STATUS.verified) return null;
  const v = (userData || {}).payoutAccountVerification || {};
  const verifiedAt = toMillis(v.checkedAt);
  if (verifiedAt === null) return null;
  return verifiedAt + LOCK_MS;
}

/**
 * 지금 계좌를 바꿀 수 있는가.
 *
 * 경계는 **정확히 30일**이다. 29일 23:59는 잠금, 30일 정각부터 변경 가능.
 */
function isAccountLocked(userData, nowMs) {
  const until = lockedUntilOf(userData);
  if (until === null) return false;
  return nowMs < until;
}

/** 잠금 해제일을 한국 날짜 YYYY.MM.DD로. 앱 표시와 같은 형식이다. */
function lockReleaseDateString(ms) {
  // 서버는 UTC로 돈다. 사용자가 보는 날짜는 한국 날짜여야 하므로 +9시간.
  const d = new Date(ms + 9 * 60 * 60 * 1000);
  const month = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  return `${d.getUTCFullYear()}.${month}.${day}`;
}

/** 잠금 중 변경을 시도했을 때 호스트에게 그대로 보여줄 안내. */
function lockedMessage(untilMs) {
  return (
    `인증된 수취계좌는 인증 완료 후 ${LOCK_DAYS}일 동안 변경할 수 없어요. `
    + `${lockReleaseDateString(untilMs)}부터 변경 가능합니다.`
  );
}

/**
 * 참가자에게 안내할 계좌 스냅샷 — **인증 완료일 때만** 값이 나온다.
 *
 * 미인증 계좌를 안내하면 검증되지 않은 계좌로 돈이 가므로, null이면 호출부가
 * 무통장입금 자체를 막는다([assertBankTransferPayable]).
 */
function paymentSnapshotOf(userData) {
  if (statusOf(userData) !== STATUS.verified) return null;
  const a = normalizePayoutAccount(userData.payoutAccount);
  return {
    bankName: a.bankName,
    accountNumber: a.accountNumber,
    accountHolder: a.accountHolder,
  };
}

/**
 * 무통장입금을 받을 수 있는 상태인지 확인한다.
 *
 * 앱도 같은 조건으로 결제수단 목록에서 무통장입금을 빼지만(헛걸음 방지),
 * 최종 판정은 언제나 여기다 — 구버전 앱이나 직접 호출은 화면을 거치지 않는다.
 */
function assertBankTransferPayable(method, snapshot) {
  if (method !== 'bank_transfer') return;
  if (!snapshot) {
    throw new HttpsError(
      'failed-precondition',
      '호스트가 아직 입금받을 계좌를 인증하지 않아 무통장입금을 받을 수 없어요. '
        + '다른 결제수단을 고르거나 호스트에게 문의해주세요.',
    );
  }
}

// ── Firestore ────────────────────────────────────────────────────────────

/**
 * 호스트의 **인증된** 수취계좌 스냅샷을 읽어 온다. 없으면 null.
 *
 * 트랜잭션 **밖에서** 부른다 — 이 값은 그 시점의 사본을 문서에 박아 두는
 * 용도(스냅샷)라 트랜잭션 일관성이 필요 없고, 도메인마다 트랜잭션 안에서
 * 사용자 문서를 읽게 하면 읽기 순서 제약만 늘어난다.
 */
async function loadPayoutSnapshot(db, hostUid) {
  if (!hostUid || typeof hostUid !== 'string') return null;
  const snap = await db.collection('users').doc(hostUid).get();
  if (!snap.exists) return null;
  const account = paymentSnapshotOf(snap.data());
  // 계좌 주인을 함께 실어 보낸다 — 결제 문서만 보고도 "이 돈을 받은 사람"과
  // "환불을 처리할 사람"을 알 수 있어야 한다(refundRequests가 이 값을 쓴다).
  return account ? { ...account, hostUid } : null;
}

/**
 * 조회된 예금주 성명으로 **인증 결과를 판정한다** — 순수 함수.
 *
 * 이 판정에는 네트워크도 Firestore도 끼지 않는다. 그래서 다섯 갈래
 * (성공·계좌 없음·예금주 불일치·본인확인 실명 불일치, 그리고 호출 자체가
 * 실패한 경우는 [popbill.failReasonOf])를 self-check로 그대로 확인할 수 있다.
 *
 * 순서가 규칙이다. 성명을 못 받았으면 대조할 것이 없고(계좌 없음), 입력한
 * 예금주명이 다르면 본인확인까지 갈 이유가 없다.
 */
function decideVerification({
  holderName,
  accountHolder,
  realName,
  accountType,
  business,
}) {
  const name = String(holderName == null ? '' : holderName).trim();
  if (!name) {
    return { status: STATUS.required, failReason: FAIL_REASON.accountNotFound };
  }
  // 어느 유형이든 **호스트가 입력한 예금주와 은행 기록이 같아야** 한다.
  if (!holderMatches(name, accountHolder)) {
    return { status: STATUS.required, failReason: FAIL_REASON.holderMismatch };
  }

  if (accountType === ACCOUNT_TYPE.business) {
    return decideBusinessAccount(name, business);
  }

  // 본인확인 실명은 확보돼 있을 때만 본다 — 본인확인 전에도 계좌 등록 자체는
  // 할 수 있어야 한다(예약·오픈 권한 쪽에서 이미 따로 요구한다).
  const real = String(realName == null ? '' : realName).trim();
  if (real && !holderMatches(name, real)) {
    return { status: STATUS.required, failReason: FAIL_REASON.identityMismatch };
  }
  return { status: STATUS.verified, verifiedHolderName: name };
}

/**
 * 사업자·법인 명의 계좌 판정.
 *
 * ── 무엇을 기준으로 삼을 수 있는가 ─────────────────────────────────────
 * users/{uid}.businessVerification에는 국세청이 **검증한 값**과 호스트가
 * **자기 신고한 값**이 함께 들어 있다(businessVerification.js 상단 주석).
 *
 *   검증됨   businessNumber · representativeName · openingDate
 *   자기신고 businessName(상호) · businessAddress
 *
 * 그래서 **상호명을 대조 기준으로 쓰지 않는다.** 상호 칸은 국세청에 보내지
 * 않는 자유 입력이라, 남의 계좌 예금주와 같은 문자열을 적어 넣으면 그 계좌가
 * 그대로 통과한다 — 계좌 도용을 막자고 만든 절차가 정반대로 쓰인다.
 * contains 같은 부분 일치를 쓰지 않는 이유도 같다("김밥천국"이 "김밥"을
 * 통과시키면 안 된다).
 *
 * ── 지금 통과시키는 것 ─────────────────────────────────────────────────
 * 예금주가 **국세청으로 검증된 대표자명과 정확히 일치**할 때만 통과한다.
 * 개인사업자 계좌의 예금주가 대표자명으로 오는 경우가 여기 해당한다.
 *
 * ── 아직 통과시키지 않는 것 ───────────────────────────────────────────
 * 예금주가 상호명 형태로 오는 계좌(법인 계좌 등)는 businessHolderMismatch로
 * 남긴다. 은행이 상호를 어떤 표기로 돌려주는지("(주)파티츄" / "주식회사
 * 파티츄" / "파티츄 홍길동")를 **실제 응답으로 확인하기 전에는** 정규화
 * 규칙을 정할 수 없고, 추측으로 만든 규칙은 위의 도용 경로를 그대로 연다.
 * 실응답을 확인하면 이 함수 한 곳만 고치면 된다.
 *
 * ── 사업자 '권한'이 먼저다 ─────────────────────────────────────────────
 * `status == 'verified'`만으로는 부족하다. 그것은 "사업자 정보가 진짜인가"일
 * 뿐이고, 남의 사업자등록증 3항목을 아는 사람도 거기까지는 통과한다. 이
 * 계정이 그 사업자를 **쓸 수 있는지**는 authorization이 답한다
 * (businessVerification.js 상단의 "두 축" 절).
 *
 * 이 계좌는 **참가자가 실제로 돈을 보내는 곳**이라 특히 중요하다 — status만
 * 보면, 남의 사업자로 대표자 확인을 기다리는(pendingOwnerApproval) 계정이
 * 그 대표자 명의 계좌를 무통장입금 안내 계좌로 올릴 수 있다.
 *
 * 판정식은 [isBusinessAuthorized] 하나뿐이다 — 두 조건짜리 규칙을 여기 다시
 * 적으면 한쪽만 고쳐져 어긋난다.
 */
function decideBusinessAccount(holderName, business) {
  const b = business || {};
  // ⚠️ 함수 안에서 require하는 이유: businessVerification.js가 이 파일의
  //    holderMatches를 쓰고, 이 파일이 그쪽의 권한 판정을 쓴다(순환 참조).
  //    모듈 최상단에서 부르면 아직 채워지지 않은 exports를 받는다. 호출
  //    시점에는 양쪽 모두 로드가 끝나 있어 안전하다.
  const { isBusinessAuthorized } = require('./businessVerification');
  if (!isBusinessAuthorized(b)) {
    return {
      status: STATUS.required,
      failReason: FAIL_REASON.businessNotVerified,
    };
  }
  const rep = String(b.representativeName == null ? '' : b.representativeName)
    .trim();
  if (rep && holderMatches(holderName, rep)) {
    return { status: STATUS.verified, verifiedHolderName: holderName };
  }
  return {
    status: STATUS.required,
    failReason: FAIL_REASON.businessHolderMismatch,
  };
}

// ── 콜러블 ───────────────────────────────────────────────────────────────
//
// 입력: { bankCode, accountNumber, accountHolder }
// 출력: { status, failReason?, verifiedHolderName?, maskedAccountNumber }
//
// 성공하든 실패하든 **서버가** users/{uid}에 결과를 기록한다. 클라이언트는 그
// 문서를 읽기만 한다(자기 문서라 읽기는 허용, 쓰기는 규칙이 막는다).

const verifyPayoutAccount = onCall(
  {
    region: 'asia-northeast3',
    secrets: [popbillLinkId, popbillSecretKey, popbillCorpNum],
    timeoutSeconds: 30,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', '로그인이 필요해요.');
    }
    const uid = request.auth.uid;

    // 표에 없는 기관코드를 **따로** 거절한다.
    //
    // 이걸 합쳐 두면 안 되는 이유: normalizePayoutAccount는 코드가 표에
    // 없으면 bankName을 못 찾아 null을 돌려주고, 그러면 아래 '모두
    // 입력해주세요'로 나간다. 값을 다 채워 보낸 사용자에게는 말이 되지 않는
    // 안내이고, 로그도 남지 않아 서버에서는 아무 흔적 없는 400만 보인다.
    // (2026-08-25 미래에셋증권 인증 실패가 정확히 이 경로였다 — 증권사
    //  코드가 아직 배포되지 않은 서버가 조용히 400을 냈다.)
    const requestedBankCode = String(
      (request.data || {}).bankCode == null ? '' : (request.data || {}).bankCode,
    ).trim();
    if (requestedBankCode && !BANK_NAMES[requestedBankCode]) {
      console.warn(
        `[${LOG}] 지원하지 않는 기관코드. uid=${uid} bank=${requestedBankCode}`,
      );
      throw new HttpsError(
        'invalid-argument',
        '지원하지 않는 금융기관이에요. 목록에서 다시 선택해주세요.',
      );
    }

    const account = normalizePayoutAccount(request.data);
    if (!account) {
      // 계좌번호·예금주는 남기지 않는다 — 어느 칸이 비었는지만 남겨도
      // 400의 원인을 추적할 수 있다.
      console.warn(
        `[${LOG}] 입력값이 부족합니다. uid=${uid} bank=${requestedBankCode || '(없음)'}`,
      );
      throw new HttpsError(
        'invalid-argument',
        '금융기관·계좌번호·예금주명을 모두 입력해주세요.',
      );
    }

    const db = admin.firestore();
    const userRef = db.collection('users').doc(uid);

    // ── 팝빌을 부르기 **전에** 두 가지를 원자적으로 끝낸다 ─────────────────
    //
    //   ① 30일 잠금 — 인증 완료 후 30일이 지나지 않았으면 조회 없이 거절한다.
    //   ② 중복 호출 선점 — 버튼 연타·재시도로 같은 요청이 겹치면 뒤엣것을
    //      거절한다.
    //
    // 둘 다 **조회 전**이어야 하는 이유는 같다: 팝빌 예금주조회는 건당
    // 과금이라, 거절할 요청으로 조회가 나가면 그대로 비용이 된다. 그래서
    // 잠금 판정을 앱에만 두지 않고 여기서도 한다 — 앱을 우회해 콜러블을 직접
    // 불러도 같은 자리에서 막힌다.
    //
    // 읽고 쓰는 사이에 다른 호출이 끼어들면 선점이 의미가 없으므로 트랜잭션
    // 안에서 처리한다. 거절 사유는 밖으로 들고 나와서 던진다 — 트랜잭션 안에서
    // 던지면 재시도 규칙과 얽혀 흐름이 읽기 어려워진다.
    let userData = {};
    let rejection = null;
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(userRef);
      userData = snap.exists ? snap.data() : {};
      const now = Date.now();
      rejection = null; // 트랜잭션이 재시도되면 앞선 판단은 버린다.

      const lockedUntil = lockedUntilOf(userData);
      if (lockedUntil !== null && now < lockedUntil) {
        rejection = {
          code: 'failed-precondition',
          message: lockedMessage(lockedUntil),
          log: `잠금 중 변경 시도. 해제=${lockReleaseDateString(lockedUntil)}`,
        };
        return;
      }

      const inFlightAt = toMillis(
        (userData.payoutAccountVerification || {}).inFlightAt,
      );
      if (inFlightAt !== null && now - inFlightAt < IN_FLIGHT_TTL_MS) {
        rejection = {
          code: 'already-exists',
          message: '이미 계좌를 확인하고 있어요. 잠시만 기다려주세요.',
          log: '중복 요청 거절',
        };
        return;
      }

      // 선점 표시. 결과가 나오는 순간 [write]가 지우므로, 인증에 실패했다면
      // 곧바로 다시 시도할 수 있다(잠기는 것은 성공했을 때뿐이다).
      tx.set(
        userRef,
        {
          payoutAccountVerification: {
            inFlightAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        },
        { merge: true },
      );
    });

    if (rejection) {
      console.warn(`[${LOG}] ${rejection.log} uid=${uid}`);
      throw new HttpsError(rejection.code, rejection.message);
    }

    const masked = maskAccountNumber(account.accountNumber);
    const fingerprint = accountFingerprint(account);

    /** 결과를 한 곳에서만 기록한다 — 성공·실패가 모두 이 함수를 지난다. */
    const write = async (status, extra = {}) => {
      await userRef.set(
        {
          // 계좌 원문도 서버가 쓴다. 인증에 실패해도 입력값은 남겨 둬야
          // 화면이 "무엇을 고쳐야 하는지"를 보여줄 수 있다.
          payoutAccount: {
            ...account,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          payoutAccountVerification: {
            status,
            accountFingerprint: fingerprint,
            // 성공했다면 이 값이 곧 **인증 완료 시각**이고 30일 잠금의
            // 기준점이 된다([lockedUntilOf]). 그래서 잠금용 필드를 따로
            // 만들지 않는다.
            checkedAt: admin.firestore.FieldValue.serverTimestamp(),
            // 선점 표시는 결과가 나온 순간 지운다.
            inFlightAt: admin.firestore.FieldValue.delete(),
            // 지난 실패 사유가 남아 있으면 안 된다 — 이번에도 실패했다면
            // 아래 extra가 새 사유로 덮는다.
            failReason: admin.firestore.FieldValue.delete(),
            ...extra,
          },
        },
        { merge: true },
      );
      return { status, maskedAccountNumber: masked, ...extra };
    };

    // ① 은행이 알고 있는 예금주 성명을 묻는다.
    let holderName;
    try {
      holderName = await popbill.checkAccountName({
        bankCode: account.bankCode,
        accountNumber: account.accountNumber,
        linkId: popbillLinkId,
        secretKey: popbillSecretKey,
        corpNum: popbillCorpNum,
      });
    } catch (e) {
      const reason = popbill.failReasonOf(e, FAIL_REASON);
      // 계좌번호는 절대 남기지 않는다 — 은행·사유·마스킹만.
      console.warn(
        `[${LOG}] 예금주조회 실패. uid=${uid} bank=${account.bankCode} `
          + `acc=${masked} reason=${reason}`,
      );
      return write(STATUS.required, { failReason: reason });
    }

    // ② 조회 결과로 판정한다 — 규칙은 [decideVerification] 하나뿐이다.
    const decision = decideVerification({
      holderName,
      accountHolder: account.accountHolder,
      realName: userData.name,
      accountType: account.accountType,
      // 사업자 명의 계좌일 때만 쓰인다. 개인 계좌 판정에는 영향을 주지
      // 않으므로, 사업자 인증이 없는 호스트도 개인 계좌는 그대로 인증된다.
      business: userData.businessVerification,
    });

    if (decision.status !== STATUS.verified) {
      // 계좌번호는 절대 남기지 않는다 — 은행·사유·마스킹만.
      console.warn(
        `[${LOG}] 인증 실패(${decision.failReason}). uid=${uid} `
          + `bank=${account.bankCode} acc=${masked}`,
      );
      return write(STATUS.required, { failReason: decision.failReason });
    }

    console.log(
      `[${LOG}] 인증 완료. uid=${uid} bank=${account.bankCode} acc=${masked}`,
    );
    return write(STATUS.verified, {
      verifiedHolderName: decision.verifiedHolderName,
    });
  },
);

/**
 * "이 호스트가 무통장입금을 받을 수 있는가"만 답한다 — 계좌 값은 주지 않는다.
 *
 * 참가자 앱이 결제수단 목록에서 무통장입금을 뺄지 정하려면 이 사실 하나가
 * 필요하다. 그렇다고 users/{hostId} 읽기를 열 수는 없으므로(그 문서에는 실명·
 * CI·계좌가 들어 있다) **불리언 하나만** 돌려주는 창구를 따로 둔다.
 *
 * 계좌번호·예금주는 여기서 절대 나가지 않는다. 참가자가 그 값을 보는 시점은
 * 신청·예약·주문이 **실제로 만들어진 뒤**이고, 그때는 문서에 박힌 스냅샷을
 * 자기 문서에서 읽는다(buildPaymentInfo).
 */
const getPayoutAccountStatus = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', '로그인이 필요해요.');
    }
    const hostUid = String((request.data || {}).hostId || '').trim();
    if (!hostUid) {
      throw new HttpsError('invalid-argument', 'hostId가 필요합니다.');
    }
    const snap = await admin.firestore().collection('users').doc(hostUid).get();
    const status = snap.exists ? statusOf(snap.data()) : STATUS.none;
    return { canReceiveBankTransfer: status === STATUS.verified };
  },
);

module.exports = {
  STATUS,
  ACCOUNT_TYPE,
  FAIL_REASON,
  BANK_NAMES,
  LOCK_DAYS,
  IN_FLIGHT_TTL_MS,
  toMillis,
  lockedUntilOf,
  isAccountLocked,
  lockReleaseDateString,
  lockedMessage,
  getPayoutAccountStatus,
  digitsOnly,
  maskAccountNumber,
  normalizeHolderName,
  holderMatches,
  accountFingerprint,
  normalizePayoutAccount,
  statusOf,
  decideVerification,
  paymentSnapshotOf,
  assertBankTransferPayable,
  loadPayoutSnapshot,
  verifyPayoutAccount,
};

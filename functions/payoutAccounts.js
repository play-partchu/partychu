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

/** 인증이 실패한 이유 — 화면 문구는 앱이 만든다(여기서는 코드만 남긴다). */
const FAIL_REASON = {
  notConfigured: 'notConfigured', // 예금주조회 서비스 미연결(키 미발급)
  apiUnavailable: 'apiUnavailable', // 조회 서비스 일시 장애
  accountNotFound: 'accountNotFound', // 존재하지 않거나 조회 불가한 계좌
  holderMismatch: 'holderMismatch', // 예금주명이 입력값과 다름
  identityMismatch: 'identityMismatch', // 예금주가 본인확인 실명과 다름
};

// ── 은행 목록 ────────────────────────────────────────────────────────────
//
// 금융결제원 표준 기관코드. 앱(lib/models/bank_codes.dart)에 **같은 표**를
// 두고, 저장·조회는 언제나 코드로 한다 — 은행 이름이 바뀌어도 이미 등록된
// 계좌의 식별자가 흔들리지 않는다.
//
// ⚠️ 팝빌 예금주조회의 기관코드가 이 표와 다른 은행이 있으면 연동 시점에
//    바로잡는다(팝빌 문서의 기관코드 표가 정본이다).
const BANK_NAMES = {
  '002': '산업은행',
  '003': '기업은행',
  '004': '국민은행',
  '007': '수협은행',
  '011': '농협은행',
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
function accountFingerprint(bankCode, accountNumber) {
  return crypto
    .createHash('sha256')
    .update(`${String(bankCode || '').trim()}:${digitsOnly(accountNumber)}`)
    .digest('hex');
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
  if (!bankCode || !bankName || !accountNumber || !accountHolder) return null;
  return { bankCode, bankName, accountNumber, accountHolder };
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
  const sameAccount =
    v.accountFingerprint ===
    accountFingerprint(account.bankCode, account.accountNumber);
  return v.status === STATUS.verified && sameAccount
    ? STATUS.verified
    : STATUS.required;
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
function decideVerification({ holderName, accountHolder, realName }) {
  const name = String(holderName == null ? '' : holderName).trim();
  if (!name) {
    return { status: STATUS.required, failReason: FAIL_REASON.accountNotFound };
  }
  if (!holderMatches(name, accountHolder)) {
    return { status: STATUS.required, failReason: FAIL_REASON.holderMismatch };
  }
  // 본인확인 실명은 확보돼 있을 때만 본다 — 본인확인 전에도 계좌 등록 자체는
  // 할 수 있어야 한다(예약·오픈 권한 쪽에서 이미 따로 요구한다).
  const real = String(realName == null ? '' : realName).trim();
  if (real && !holderMatches(name, real)) {
    return { status: STATUS.required, failReason: FAIL_REASON.identityMismatch };
  }
  return { status: STATUS.verified, verifiedHolderName: name };
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
    const account = normalizePayoutAccount(request.data);
    if (!account) {
      throw new HttpsError(
        'invalid-argument',
        '은행·계좌번호·예금주명을 모두 입력해주세요.',
      );
    }

    const db = admin.firestore();
    const userRef = db.collection('users').doc(uid);
    const userSnap = await userRef.get();
    const userData = userSnap.exists ? userSnap.data() : {};

    const masked = maskAccountNumber(account.accountNumber);
    const fingerprint = accountFingerprint(
      account.bankCode,
      account.accountNumber,
    );

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
            checkedAt: admin.firestore.FieldValue.serverTimestamp(),
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
  FAIL_REASON,
  BANK_NAMES,
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

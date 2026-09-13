const admin = require('firebase-admin');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');

const popbill = require('./popbill');
const payoutAccounts = require('./payoutAccounts');

/**
 * 게스트 **환불계좌 인증** — users/{uid}.refundAccountVerification.
 *
 * ── 이 파일과 refundAccounts.js의 경계 ───────────────────────────────────
 * refundAccounts.js는 **환불 요청**(refundRequests 큐·상태·스냅샷)을 다룬다.
 * 여기는 **그 계좌가 본인 것이 맞는지 확인하는 절차**만 다룬다. 두 관심사가
 * 한 파일에 섞이면 "요청 상태"와 "인증 상태"를 같은 말로 부르게 된다.
 *
 * ── 세 계좌는 끝까지 따로다 ──────────────────────────────────────────────
 *   payoutAccount   호스트가 참가비를 **받을** 계좌   (payoutAccounts.js)
 *   settlementInfo  파티츄가 호스트에게 **보낼** 계좌
 *   refundAccount   게스트가 환불을 **돌려받을** 계좌 ← 이 파일이 인증한다
 * 같은 사람이 호스트이면서 게스트일 수 있으므로 상태를 절대 공유하지 않는다.
 *
 * ── 인증 엔진은 재사용한다 ───────────────────────────────────────────────
 * 성명조회(팝빌)와 판정 규칙은 계좌의 **역할과 무관한 공통 절차**다. 그래서
 * [payoutAccounts.decideVerification]을 그대로 부르고, 다른 것은 저장 자리뿐
 * 이다 — 규칙을 복사하면 한쪽만 고쳐져 두 계좌의 기준이 갈라진다.
 *
 * ── 환불계좌는 언제나 본인 명의(personal)다 ──────────────────────────────
 * 수취계좌와 달리 사업자·법인 갈래가 없다. 환불금은 낸 사람에게 돌아가야
 * 하므로 예금주가 **본인확인 실명과 같아야** 한다(personal 경로가 그 판정을
 * 그대로 한다).
 */

const LOG = 'refundAccountVerify';

const popbillLinkId = defineSecret('POPBILL_LINK_ID');
const popbillSecretKey = defineSecret('POPBILL_SECRET_KEY');
const popbillCorpNum = defineSecret('POPBILL_CORP_NUM');

const { STATUS, ACCOUNT_TYPE, FAIL_REASON, BANK_NAMES, IN_FLIGHT_TTL_MS } =
  payoutAccounts;

const ACCOUNT_FIELD = 'refundAccount';
const VERIFICATION_FIELD = 'refundAccountVerification';

/**
 * 인증 절차가 다루는 형태로 환불계좌를 정규화한다.
 *
 * ⚠️ refundAccounts.js에도 같은 이름의 함수가 있지만 **다른 형태**를 만든다.
 * 그쪽은 취소 시점에 자유 입력으로 받는 `{bankName, accountNumber,
 * accountHolder}`이고, 여기는 성명조회에 필요한 `bankCode`까지 갖춘 형태다.
 * 그래서 이름을 달리 두고 서로 부르지 않는다.
 *
 * 계좌유형은 언제나 personal로 못박는다 — business가 넘어와도 환불계좌에서는
 * 뜻이 없고, 그대로 두면 사업자 판정 경로를 탈 수 있다.
 *
 * 옛 문서 호환: 인증이 없던 시절의 `refundAccount`에는 `bankCode`가 없다.
 * 그런 값은 여기서 null이 되어 상태가 `none`이 된다 — "아직 인증되지 않은
 * 계좌"로 취급되므로 안전한 방향이고, 저장된 데이터는 건드리지 않는다.
 */
function normalizeVerifiedRefundAccount(raw) {
  const account = payoutAccounts.normalizePayoutAccount(raw);
  if (!account) return null;
  return { ...account, accountType: ACCOUNT_TYPE.personal };
}

/**
 * 지금 이 사용자의 환불계좌 인증 상태.
 *
 * 인증 기록이 **지금 계좌의 지문과 다르면 인증으로 치지 않는다.** 이 한 줄이
 * 보안의 핵심이다 — 취소 흐름이나 옛 경로가 `refundAccount`를 덮어써도
 * 지문이 어긋나 `required`로 떨어질 뿐, 인증된 것처럼 보이게 만들 수는 없다
 * (`refundAccountVerification`은 규칙상 서버만 쓴다).
 */
function statusOf(userData) {
  const account = normalizeVerifiedRefundAccount(
    (userData || {})[ACCOUNT_FIELD],
  );
  if (!account) return STATUS.none;
  const v = (userData || {})[VERIFICATION_FIELD] || {};
  const sameAccount =
    v.accountFingerprint === payoutAccounts.accountFingerprint(account);
  return v.status === STATUS.verified && sameAccount
    ? STATUS.verified
    : STATUS.required;
}

/**
 * 무통장입금으로 **신청할 수 있는** 상태인지 — fail-closed.
 *
 * 앱도 같은 조건으로 신청 전에 안내를 띄우지만(헛걸음 방지), 최종 판정은
 * 언제나 여기다 — 구버전 앱이나 콜러블 직접 호출은 화면을 거치지 않는다.
 *
 * **현장결제(on_site)에는 적용하지 않는다.** 현장에서 내는 돈은 계좌로 환불할
 * 일이 없다. `method`가 `bank_transfer`가 아니면 즉시 통과한다 — 무료 신청도
 * payment 자체가 없으므로 여기까지 오지 않는다.
 */
function assertRefundAccountVerified(method, userData) {
  if (method !== 'bank_transfer') return;
  if (statusOf(userData) === STATUS.verified) return;
  throw new HttpsError(
    'failed-precondition',
    '무통장입금으로 신청하려면 환불받을 계좌를 먼저 인증해야 해요. '
      + '마이페이지 > 환불 계좌 관리에서 인증한 뒤 다시 시도해주세요.',
  );
}

/**
 * 환불 요청 문서에 박을 **계좌 스냅샷** — 인증된 계좌일 때만 값이 나온다.
 *
 * ⚠️ 클라이언트가 보낸 값은 절대 쓰지 않는다. 취소·재제출 콜러블은 이 함수가
 * 돌려준 값만 refundRequests에 박는다 — 그래서 임의의 계좌번호를 넘겨
 * "남의 계좌로 환불받는" 요청을 만들 수 없다.
 *
 * 모양은 refundAccounts.buildRefundRequest가 받는 세 값 그대로다(bankCode는
 * 넣지 않는다 — 운영자가 보는 값은 기관명이고, 요청 문서에 조회용 코드까지
 * 늘릴 이유가 없다).
 */
function verifiedSnapshotOf(userData) {
  if (statusOf(userData) !== STATUS.verified) return null;
  const a = normalizeVerifiedRefundAccount((userData || {})[ACCOUNT_FIELD]);
  if (!a) return null;
  return {
    bankName: a.bankName,
    accountNumber: a.accountNumber,
    accountHolder: a.accountHolder,
  };
}

/**
 * 인증된 환불계좌 스냅샷을 읽어 온다. 인증돼 있지 않으면 null.
 *
 * 트랜잭션 **밖에서** 부른다 — 문서에 박을 사본을 뜨는 용도라 트랜잭션
 * 일관성이 필요 없고, 도메인마다 트랜잭션 안에서 사용자 문서를 읽게 하면
 * 읽기 순서 제약만 늘어난다([payoutAccounts.loadPayoutSnapshot]과 같다).
 */
async function loadVerifiedRefundSnapshot(db, uid) {
  if (!uid || typeof uid !== 'string') return null;
  const snap = await db.collection('users').doc(uid).get();
  if (!snap.exists) return null;
  return verifiedSnapshotOf(snap.data());
}

/**
 * 신청자 본인 문서를 읽어 온다 — 위 검증에 넘길 용도.
 *
 * 트랜잭션 **밖에서** 부른다([payoutAccounts.loadPayoutSnapshot]과 같은
 * 이유). 문서가 없으면 빈 객체를 돌려주고, 그러면 상태는 `none`이 되어
 * 무통장입금이 거절된다(fail-closed).
 */
async function loadRefundAccountOwner(db, uid) {
  if (!uid || typeof uid !== 'string') return {};
  const snap = await db.collection('users').doc(uid).get();
  return snap.exists ? snap.data() : {};
}

// ── 콜러블 ───────────────────────────────────────────────────────────────
//
// 입력: { bankCode, accountNumber, accountHolder }
// 출력: { status, failReason?, verifiedHolderName?, maskedAccountNumber }
//
// 성공하든 실패하든 **서버가** 결과를 기록한다. 클라이언트는 읽기만 한다.
//
// 수취계좌와 달리 **30일 잠금이 없다.** 그 잠금은 "인증만 받아 두고 다른
// 계좌로 갈아끼워 게스트에게 안내되게 하는 것"을 막는 장치인데, 환불계좌는
// 남에게 안내되지 않고 본인이 돌려받을 자리라 바꿀 이유가 정당하다.
// 중복 호출 선점(조회 과금 방지)은 그대로 둔다.

const verifyRefundAccount = onCall(
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

    // 표에 없는 기관코드를 따로 거절한다 — 값을 다 채워 보낸 사용자에게
    // '모두 입력해주세요'가 나가지 않도록(수취계좌와 같은 이유).
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

    const account = normalizeVerifiedRefundAccount(request.data);
    if (!account) {
      // 계좌번호·예금주는 남기지 않는다 — 어느 칸이 비었는지만으로도 추적된다.
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

    // 팝빌을 부르기 **전에** 중복 호출을 선점해 거절한다 — 예금주조회는 건당
    // 과금이라, 거절할 요청으로 조회가 나가면 그대로 비용이 된다.
    let userData = {};
    let rejection = null;
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(userRef);
      userData = snap.exists ? snap.data() : {};
      rejection = null; // 트랜잭션이 재시도되면 앞선 판단은 버린다.

      const inFlightAt = payoutAccounts.toMillis(
        (userData[VERIFICATION_FIELD] || {}).inFlightAt,
      );
      if (inFlightAt !== null && Date.now() - inFlightAt < IN_FLIGHT_TTL_MS) {
        rejection = {
          code: 'already-exists',
          message: '이미 계좌를 확인하고 있어요. 잠시만 기다려주세요.',
          log: '중복 요청 거절',
        };
        return;
      }

      tx.set(
        userRef,
        {
          [VERIFICATION_FIELD]: {
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

    const masked = payoutAccounts.maskAccountNumber(account.accountNumber);
    const fingerprint = payoutAccounts.accountFingerprint(account);

    /** 결과를 한 곳에서만 기록한다 — 성공·실패가 모두 이 함수를 지난다. */
    const write = async (status, extra = {}) => {
      await userRef.set(
        {
          // 계좌 원문도 서버가 쓴다. 인증에 실패해도 입력값은 남겨 둬야
          // 화면이 "무엇을 고쳐야 하는지"를 보여줄 수 있다.
          [ACCOUNT_FIELD]: {
            ...account,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          [VERIFICATION_FIELD]: {
            status,
            accountFingerprint: fingerprint,
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

    // ② 판정 규칙은 수취계좌와 **같은 함수** 하나다. accountType이 personal로
    //    고정돼 있으므로 사업자 경로는 타지 않고, 본인확인 실명(users.name)
    //    과의 대조가 그대로 걸린다.
    const decision = payoutAccounts.decideVerification({
      holderName,
      accountHolder: account.accountHolder,
      realName: userData.name,
      accountType: ACCOUNT_TYPE.personal,
    });

    if (decision.status !== STATUS.verified) {
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

module.exports = {
  ACCOUNT_FIELD,
  VERIFICATION_FIELD,
  normalizeVerifiedRefundAccount,
  statusOf,
  assertRefundAccountVerified,
  verifiedSnapshotOf,
  loadVerifiedRefundSnapshot,
  loadRefundAccountOwner,
  verifyRefundAccount,
};

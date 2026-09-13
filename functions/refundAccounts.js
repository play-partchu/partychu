const admin = require('firebase-admin');

// 참가자 **환불계좌** 규칙 — 순수 헬퍼 모듈이다.
//
// Cloud Function(운영자 처리)은 refundRequests.js에 따로 있다. 이 저장소 규칙:
// Object.assign(exports, ...) 대상은 Cloud Function만이고, 순수 헬퍼는 언제나
// 구조분해로만 가져다 쓴다(index.js 상단 주석 참고).
//
// ── 이 앱의 계좌는 세 가지이고, 서로 절대 섞지 않는다 ───────────────────────
//   1. 참가자가 **입금하는** 계좌      = 파티츄 법인 계좌 (paymentInfo.js)
//   2. 파티츄가 **호스트에게 정산**할 계좌 = users/{uid}.settlementInfo
//   3. 파티츄가 **참가자에게 환불**할 계좌 = users/{uid}.refundAccount ← 여기
//
// 2와 3은 이름이 비슷하지만 **주인도 용도도 다른 남남**이다. 같은 필드에 두면
// 호스트이면서 참가자인 사람의 계좌가 서로 덮어써지고, 정산 대상과 환불 대상이
// 뒤섞인다. 그래서 필드도 화면도 끝까지 분리한다.
//
// ── 왜 환불계좌가 필요한가 ──────────────────────────────────────────────────
// PG가 아직 연결돼 있지 않아 **원결제 취소라는 경로가 없다**. 무통장입금으로
// 실제 입금까지 끝난 건을 취소하면 돈을 돌려줄 방법이 계좌이체뿐이고, 그러려면
// 참가자의 계좌를 알아야 한다. 반대로 무료 신청·현장결제·입금 전 취소는 돌려줄
// 돈 자체가 없으므로 계좌를 묻지 않는다([requiresRefundAccount]).
//
// ── 스냅샷 원칙 ─────────────────────────────────────────────────────────────
// 환불 요청 문서에는 **그때 쓴 계좌를 복사해 둔다**. 사용자가 나중에
// 마이페이지에서 환불계좌를 바꿔도 이미 접수된 요청의 입금처가 따라 바뀌면
// 안 된다(운영자가 이미 그 계좌로 보냈을 수 있다).



/**
 * 환불 요청 상태 — 자동 송금이 없으므로 운영자가 손으로 넘긴다.
 *
 * rejected는 **막다른 길이 아니다**: 계좌를 잘못 적어 반려된 참가자가 계좌를
 * 고쳐 다시 낼 수 있어야 한다. 그 재제출은 기존 문서를 덮어쓰지 않고
 * **새 요청 문서**로 만든다(resubmittedFrom으로 앞 건을 가리킨다) — 반려된
 * 요청의 계좌 사본이 조용히 바뀌면 "어느 계좌로 보내려다 반려됐는지"가
 * 사라져 이력을 추적할 수 없다.
 */
const REFUND_REQUEST_STATUS = {
  requested: 'requested', // 접수됨 — 운영자 확인 대기
  completed: 'completed', // 송금 완료
  rejected: 'rejected', // 반려 — 참가자가 계좌를 고쳐 재제출할 수 있다
};

/**
 * 계좌를 실제로 물어봐야 하는 건인지.
 *
 * 무통장입금으로 **돈이 실제로 들어온**(status: 'paid') 건에서 환불액이 있을
 * 때만 true다. 현장결제는 현장에서 현금으로 돌려주므로 계좌가 필요 없고,
 * 입금 전(입금대기·승인대기) 취소는 받은 돈이 없어 환불액 자체가 0이다.
 */
function requiresRefundAccount(payment, refundAmount) {
  const amount = Number(refundAmount) || 0;
  if (amount <= 0) return false;
  if (!payment || typeof payment !== 'object') return false;
  return payment.method === 'bank_transfer' && payment.status === 'paid';
}

/**
 * 클라이언트가 보낸 환불계좌를 정규화한다. 세 값이 모두 있어야 성립한다.
 * @returns {{bankName:string, accountNumber:string, accountHolder:string}|null}
 */
function normalizeRefundAccount(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const s = (v) => (typeof v === 'string' ? v.trim() : '');
  const bankName = s(raw.bankName);
  // 계좌번호는 숫자만 남긴다 — 하이픈 유무로 같은 계좌가 다르게 보이지 않게.
  const accountNumber = s(raw.accountNumber).replace(/[^0-9]/g, '');
  const accountHolder = s(raw.accountHolder);
  if (!bankName || !accountNumber || !accountHolder) return null;
  return { bankName, accountNumber, accountHolder };
}

/**
 * 환불 요청 문서 한 건의 내용을 만든다(쓰기는 호출부의 트랜잭션이 한다).
 *
 * @param {object} p
 * @param {string} p.requesterId  환불받을 참가자 uid
 * @param {string} p.domain       'party' 등 — 나중에 도메인이 늘어도 같은 큐를 쓴다
 * @param {string} p.refId        파티 id 등
 * @param {string} p.applicationPath 신청 문서 경로(운영자가 원본을 찾아갈 수 있게)
 * @param {number} p.refundAmount
 * @param {object} p.account      normalizeRefundAccount 결과 — **스냅샷으로 박힌다**
 */
function buildRefundRequest({
  requesterId,
  domain,
  refId,
  applicationPath,
  refundAmount,
  account,
  hostId = null,
  title = null,
  /** 반려된 앞 요청을 고쳐 다시 낸 것이면 그 문서 id. 이력 추적용. */
  resubmittedFrom = null,
  /** 재제출 회차 — 처음 접수는 1. */
  attempt = 1,
}) {
  return {
    requesterId,
    domain,
    refId,
    applicationPath,
    hostId,
    title,
    refundAmount: Number(refundAmount) || 0,
    // 요청 시점의 계좌 사본 — 사용자가 나중에 계좌를 바꿔도 이 값은 그대로다.
    account: { ...account },
    status: REFUND_REQUEST_STATUS.requested,
    resubmittedFrom,
    attempt,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    completedAt: null,
    completedBy: null,
    // 누가 어떤 방식으로 끝냈는지 — 아래 COMPLETED_BY / COMPLETION_METHOD.
    completedByRole: null,
    completionMethod: null,
    adminMemo: null,
    rejectedReason: null,
    // 호스트에게 "아직 안 보냈다"고 다시 알린 시각. 재촉이 두 번 가지 않게
    // 표시해 둔다(refundOverdue 스케줄러).
    overdueNotifiedAt: null,
  };
}

/** 완료 처리를 누른 사람의 역할. */
const COMPLETED_BY = {
  host: 'host', // 돈을 받은 호스트 본인
  admin: 'admin', // 운영자 개입(분쟁·장기 미처리 등)
};

/**
 * 완료가 어떤 뜻인지 — **지금은 하나뿐이고, 자동 송금이 아니다.**
 *
 * 참가자 돈은 파티츄가 아니라 호스트가 직접 받으므로(payoutAccounts.js),
 * 환불도 호스트가 자기 계좌에서 손으로 보낸다. 시스템은 그 송금을 확인할
 * 방법이 없다 — '완료'는 어디까지나 **"보냈다고 표시함"**이다.
 *
 * 나중에 PG 환불 API가 붙으면 그때 'pg_refund' 같은 값이 생기고, 그 둘은
 * 화면에서도 다르게 표기해야 한다(한쪽은 증빙이 있고 한쪽은 없다).
 */
const COMPLETION_METHOD = {
  markedManually: 'marked_manually',
};

/**
 * 접수된 지 오래됐는데 아직 처리되지 않았는가.
 *
 * 호스트가 방치하면 참가자는 돈을 못 돌려받은 채로 남는다. 자동 송금이 없는
 * 구조에서는 이 판정이 유일한 안전망이라, 재촉 알림과 관리자 개입이 모두 이
 * 값 하나를 본다(화면·스케줄러가 따로 계산하면 기준이 갈린다).
 */
const OVERDUE_MS = 3 * 24 * 60 * 60 * 1000; // 3일

function isOverdue(requestData, nowMs, thresholdMs = OVERDUE_MS) {
  if (!requestData || requestData.status !== REFUND_REQUEST_STATUS.requested) {
    return false;
  }
  const createdAt = requestData.createdAt;
  const createdMs =
    createdAt && typeof createdAt.toMillis === 'function'
      ? createdAt.toMillis()
      : Number(createdAt) || 0;
  if (!createdMs) return false;
  return nowMs - createdMs >= thresholdMs;
}

module.exports = {
  REFUND_REQUEST_STATUS,
  COMPLETED_BY,
  COMPLETION_METHOD,
  OVERDUE_MS,
  requiresRefundAccount,
  normalizeRefundAccount,
  buildRefundRequest,
  isOverdue,
};

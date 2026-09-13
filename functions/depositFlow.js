const { HttpsError } = require('firebase-functions/v2/https');

/**
 * 무통장입금 **상태 전이 규칙** — 파티 신청과 플레이스 방문예약이 함께 쓴다.
 *
 *   (승인제만) 승인대기 awaiting_approval
 *        │ 호스트/업주 승인
 *        ▼
 *   입금대기 awaiting_deposit
 *        │ 이용자 '입금했어요'
 *        ▼
 *   입금확인중 deposit_pending
 *        │ 호스트/업주 '입금 확인'
 *        ▼
 *   결제완료 paid
 *
 *   기한 초과: awaiting_deposit → expired (deposit_pending은 **대상 아님**)
 *
 * 도메인마다 다른 것은 "어느 문서인가 / 확정되면 무슨 상태가 되나 / 자리를 어떻게
 * 돌려주나"뿐이고, **어떤 상태에서 무엇을 할 수 있는가**는 완전히 같다. 그래서
 * 그 판정만 여기 모아 두고 두 도메인이 같은 함수를 부른다(규칙이 갈라지면
 * 한쪽만 고쳐 두 화면이 다르게 동작하는 사고가 난다).
 *
 * 모든 함수는 순수하다 — Firestore를 모르므로 자체 검증에서 그대로 부를 수 있다.
 */

const STATUS = {
  awaitingApproval: 'awaiting_approval',
  awaitingDeposit: 'awaiting_deposit',
  depositPending: 'deposit_pending',
  onSiteScheduled: 'on_site_scheduled',
  paid: 'paid',
  cancelled: 'cancelled',
  expired: 'expired',
};

/** 무통장입금 기한 기본값 — 24시간. */
const DEPOSIT_WINDOW_MS = 24 * 60 * 60 * 1000;

/**
 * 입금기한 계산. 기준 시각 + 24시간이되, **이용 시각을 넘지 않는다** —
 * 방문이 12시간 뒤인데 기한이 24시간이면 기한이 뜻을 잃는다.
 *
 * 이용 시각이 이미 24시간 안이면 그 시각이 곧 기한이고, 이용 시각을 모르면
 * (파티처럼 호출부가 안 넘기면) 24시간 그대로다.
 */
function depositDeadlineMs(fromMs, { notAfterMs = null } = {}) {
  const base = fromMs + DEPOSIT_WINDOW_MS;
  if (notAfterMs && notAfterMs < base) return notAfterMs;
  return base;
}

/** 이 건이 무통장입금인지 — 아니면 null. */
function bankPaymentOf(payment) {
  if (!payment || payment.method !== 'bank_transfer') return null;
  return payment;
}

/**
 * 이용자가 '입금했어요'를 누를 수 있는 상태인지. 아니면 던진다.
 *
 * 중복 클릭 차단이 이 규칙 하나에 걸려 있다 — 이미 알린 뒤(deposit_pending)나
 * 확인이 끝난 뒤(paid)에는 다시 누를 수 없다.
 */
function assertCanMarkSent(payment, { cancelled = false } = {}) {
  if (cancelled) {
    throw new HttpsError('failed-precondition', '취소된 건이에요.');
  }
  const p = bankPaymentOf(payment);
  if (!p) {
    throw new HttpsError('failed-precondition', '무통장입금 건이 아니에요.');
  }
  if (p.status === STATUS.awaitingApproval) {
    throw new HttpsError('failed-precondition', '아직 승인 전이에요. 승인되면 입금 안내를 보내드려요.');
  }
  if (p.status === STATUS.depositPending) {
    throw new HttpsError('failed-precondition', '이미 입금 확인을 기다리고 있어요.');
  }
  if (p.status !== STATUS.awaitingDeposit) {
    throw new HttpsError('failed-precondition', '지금은 입금 확인을 요청할 수 없어요.');
  }
  return p;
}

/**
 * 호스트/업주가 '입금 확인'을 누를 수 있는 상태인지. 아니면 던진다.
 *
 * 이용자가 '입금했어요'를 누르지 않았어도(awaiting_deposit) 실제로 돈이
 * 들어왔다면 확인할 수 있어야 하므로 두 상태를 모두 받는다. 승인 전
 * (awaiting_approval)에는 애초에 입금을 요구하지 않았으므로 막는다.
 */
function assertCanConfirm(payment, { cancelled = false } = {}) {
  if (cancelled) {
    throw new HttpsError('failed-precondition', '취소된 건이에요.');
  }
  const p = bankPaymentOf(payment);
  if (!p) {
    throw new HttpsError('failed-precondition', '무통장입금 건이 아니에요.');
  }
  if (p.status === STATUS.paid) {
    throw new HttpsError('failed-precondition', '이미 입금이 확인된 건이에요.');
  }
  if (p.status === STATUS.awaitingApproval) {
    throw new HttpsError('failed-precondition', '먼저 예약을 승인해주세요.');
  }
  if (p.status !== STATUS.depositPending && p.status !== STATUS.awaitingDeposit) {
    throw new HttpsError('failed-precondition', '지금은 입금을 확인할 수 없어요.');
  }
  return p;
}

/**
 * 판매자가 **돈을 받았다고 확인**할 수 있는 상태인지 — 무통장입금과
 * 현장결제를 **함께** 받는다. 아니면 던진다.
 *
 * [assertCanConfirm]과 무엇이 다른가: 그쪽은 무통장입금 전용이라 현장결제를
 * 거절한다(예약 도메인들은 현장결제를 "방문해서 내는 것"으로만 두고 확인
 * 절차를 두지 않았다). 하지만 QR 이용권처럼 **돈을 받아야 비로소 무언가를
 * 발급**하는 도메인에서는 현장결제도 확인 시점이 있어야 한다 — 그러지 않으면
 * 현장결제 이용권이 영영 사용 가능해지지 않거나, 반대로 돈을 받기도 전에
 * 사용 가능해진다.
 *
 * 기존 호출부(파티·방문예약·장소대여·콤보)는 [assertCanConfirm]을 그대로 쓰므로
 * 동작이 바뀌지 않는다.
 */
function assertCanConfirmReceived(payment, { cancelled = false } = {}) {
  if (cancelled) {
    throw new HttpsError('failed-precondition', '취소된 건이에요.');
  }
  if (!payment) {
    throw new HttpsError('failed-precondition', '결제 정보가 없는 건이에요.');
  }
  if (payment.status === STATUS.paid) {
    throw new HttpsError('failed-precondition', '이미 결제가 확인된 건이에요.');
  }
  if (payment.status === STATUS.awaitingApproval) {
    throw new HttpsError('failed-precondition', '먼저 예약을 승인해주세요.');
  }
  // 현장결제는 '현장결제 예정'에서 바로 확인한다(입금 안내 단계가 없다).
  if (payment.method === 'on_site') {
    if (payment.status !== STATUS.onSiteScheduled) {
      throw new HttpsError('failed-precondition', '지금은 결제를 확인할 수 없어요.');
    }
    return payment;
  }
  return assertCanConfirm(payment, { cancelled });
}

/** '입금했어요' 이후 문서에 반영할 값. */
function markSentPatch(nowMs) {
  return { status: STATUS.depositPending, depositedAtMs: nowMs };
}

/** '입금 확인' 이후 문서에 반영할 값. */
function confirmPatch(nowMs, confirmedBy) {
  return { status: STATUS.paid, paidAtMs: nowMs, confirmedBy };
}

/**
 * 승인제 건이 **승인된 순간** 결제 상태에 반영할 값.
 *
 * 승인 전에는 입금을 요구하지 않으므로(거절 시 계좌 환불이 필요해진다) 여기서
 * 비로소 입금대기가 되고 기한이 시작된다. 무통장이 아니거나 이미 다음 단계로
 * 간 건은 아무것도 바꾸지 않는다(null).
 */
function approvePatch(payment, nowMs, { notAfterMs = null } = {}) {
  const p = bankPaymentOf(payment);
  if (!p || p.status !== STATUS.awaitingApproval) return null;
  return {
    status: STATUS.awaitingDeposit,
    depositDeadlineMs: depositDeadlineMs(nowMs, { notAfterMs }),
  };
}

/**
 * 이 건의 돈이 **실제로 들어왔는지** — 매출 집계와 QR 이용권 발급·사용의
 * 단 하나의 기준이다.
 *
 * 진행 상태(예약 confirmed / 주문 paid)와 절대 섞지 않는다: 입금대기·
 * 입금확인중·현장결제 예정은 전부 "아직 안 받은 돈"이다. 결제 정보가 없는
 * 건(무료 또는 옛 PG 흐름)은 호출부가 판단하도록 false를 돌려준다.
 */
function isPaid(payment) {
  return !!payment && payment.status === STATUS.paid;
}

/**
 * 기한이 지나 자동 정리할 대상인지.
 *
 * **입금확인중은 대상이 아니다** — 이용자는 입금했다고 알렸는데 확인이 늦은
 * 것뿐일 수 있어, 자동 취소하면 이미 돈을 낸 사람을 떨어뜨리게 된다. 그 건은
 * 호스트/업주가 목록에서 직접 처리한다.
 */
function isExpirable(payment, nowMs) {
  const p = bankPaymentOf(payment);
  if (!p) return false;
  if (p.status !== STATUS.awaitingDeposit) return false;
  return typeof p.depositDeadlineMs === 'number' && p.depositDeadlineMs < nowMs;
}

/** 기한 만료 시 문서에 반영할 값. */
function expirePatch(nowMs) {
  return { status: STATUS.expired, cancelledAtMs: nowMs };
}

module.exports = {
  STATUS,
  DEPOSIT_WINDOW_MS,
  depositDeadlineMs,
  bankPaymentOf,
  assertCanMarkSent,
  assertCanConfirm,
  assertCanConfirmReceived,
  isPaid,
  markSentPatch,
  confirmPatch,
  approvePatch,
  isExpirable,
  expirePatch,
};

/**
 * **QR 이용권 코드가 생기는 단 하나의 지점.**
 *
 * 원래 placeProductOrders.js 안에만 있었다. 통합 QR 체크인이 현장결제를
 * 그 자리에서 확인할 수 있게 되면서(같은 화면에서 결제 확인 → 사용 처리),
 * 이용권을 발급하는 코드가 두 곳이 될 뻔했다 — 그러면 "결제 없이 발급된
 * 이용권이 있는가"를 따질 때 봐야 할 곳이 둘이 된다.
 *
 * 규칙은 바뀌지 않았다. 코드는 **결제가 확인된 뒤에만** 생기고, 그 판정은
 * 부르는 쪽이 자기 방식으로 끝낸 뒤 이 함수를 부른다
 * (PortOne 조회 / depositFlow.assertCanConfirmReceived).
 */

const admin = require('firebase-admin');
const crypto = require('crypto');

const { tsToMs } = require('./checkInRules');

function newVoucherCode() {
  return crypto.randomBytes(24).toString('base64url');
}

/**
 * 결제 확정 직후의 상태 — 이용 시작일이 아직 안 왔으면 '결제 완료'로 두고,
 * 이미 이용 가능 기간이면 바로 '사용 가능'으로 연다. QR 사용 처리는 '사용
 * 가능'에서만 통과하므로, 이 구분이 곧 "다음 주 행사 티켓을 오늘 쓰지 못하게"
 * 막는 장치다.
 */
function resolveConfirmedStatus(order, nowMs) {
  const startMs = tsToMs(order.useStartAt);
  if (startMs !== null && nowMs < startMs) return 'paid';
  return 'usable';
}

/** 결제가 확인된 주문에 반영할 값 — 이용권 코드가 생기는 유일한 지점. */
function issueVoucherPatch(order, nowMs) {
  return {
    status: resolveConfirmedStatus(order, nowMs),
    // QR을 쓰지 않는 상품은 코드가 없다(빈 문자열 그대로).
    voucherCode: order.useQrCheck === true ? newVoucherCode() : '',
    paidAt: admin.firestore.FieldValue.serverTimestamp(),
    // 확정된 주문은 더 이상 만료 대상이 아니다.
    expiresAt: null,
  };
}

/** 이미 끝난 주문인지 — depositFlow에 넘길 문맥. */
const orderContext = (order) => ({
  cancelled:
    order.status === 'cancelled' ||
    order.status === 'refunded' ||
    order.status === 'expired' ||
    order.status === 'used',
});

module.exports = {
  newVoucherCode,
  resolveConfirmedStatus,
  issueVoucherPatch,
  orderContext,
};

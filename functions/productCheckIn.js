/**
 * 상품·이용권의 **통합 QR 식별자** — 현장결제 주문이 결제 전에도 스캔되도록.
 *
 * ── 왜 필요했나 ─────────────────────────────────────────────────────────────
 * 현장결제는 "손님이 와서 QR을 보여주고 → 호스트가 누가 무엇을 사러 왔는지
 * 확인하고 → 돈을 받고 → 사용 처리"가 한 흐름이다. 그런데 상품의 QR 값은
 * `voucherCode` 하나뿐이었고 그건 **결제가 확인된 뒤에만** 생긴다. 결과적으로
 * 현장결제 손님에게는 보여줄 QR이 아예 없었고, 스캐너의 '결제 확인' 버튼
 * (confirmCheckInPayment)에 도달할 길이 없었다.
 *
 * ── 두 값의 역할을 섞지 않는다 ──────────────────────────────────────────────
 *   · checkInToken   이 이용 건을 안전하게 **조회**하기 위한 QR 식별자.
 *                    결제 증명이 아니다. 주문이 생기는 순간(현장결제만) 붙는다.
 *   · voucherCode    결제가 확인된 뒤에 생기는 **이용권 코드**. 의미도 발급
 *                    시점도 그대로다(voucherIssue.js가 유일한 발급 지점).
 *
 * 손님 화면의 QR 값은 checkInToken이 있으면 그것이다. 그래서 **결제 전후로 QR이
 * 바뀌지 않는다** — 호스트가 스캔하고, 결제를 확인하고, 같은 화면에서 다시
 * 조회해 사용 처리까지 가는 동안 손님은 화면을 새로 열 필요가 없다.
 *
 * ── 무통장입금은 그대로 ─────────────────────────────────────────────────────
 * 입금 대기 주문에는 QR을 만들지 않는다(checkInRules.productQrActive). 입금은
 * 계좌에서 확인되므로 사전 스캔이 필요 없고, "입금 확인 전에는 쓸 수 있는 QR을
 * 노출하지 않는다"는 기존 정책을 이번 변경으로 흔들지 않기 위해서다.
 *
 * ── 통과는 여전히 막힌다 ────────────────────────────────────────────────────
 * 조회가 열린 것이지 사용이 열린 것이 아니다. 결제 전 사용 처리는
 * checkInRules.voucherBlockReason이 그대로 거절한다.
 */

const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

const rules = require('./checkInRules');
const store = require('./checkInTokenStore');

const REGION = 'asia-northeast3';

/** 왜 QR이 죽었는지 — 감사용. 손님에게는 언제나 같은 문장이 나간다. */
function revokeReasonOf(order) {
  return 'order_status_' + ((order && order.status) || 'missing');
}

/**
 * 트리거 본체 — self-check가 가짜 Firestore로 직접 부를 수 있게 떼어 뒀다.
 */
async function handleProductOrderWrite(db, event) {
  const after = event.data.after.exists ? event.data.after.data() : null;
  const refPath = `placeProductOrders/${event.params.id}`;

  if (!after) {
    await store.revokeCheckInTokenFor(db, refPath, 'order_deleted');
    return;
  }

  await store.syncTokenField(db, {
    ref: event.data.after.ref,
    after,
    refPath,
    domain: rules.DOMAIN.voucher,
    hostId: after.hostId || '',
    guestUid: after.buyerId || '',
    active: rules.productQrActive(after),
    revokeReason: revokeReasonOf(after),
  });
}

exports.onPlaceProductOrderCheckIn = onDocumentWritten(
  { document: 'placeProductOrders/{id}', region: REGION },
  (event) => handleProductOrderWrite(admin.firestore(), event),
);

module.exports.__test = { revokeReasonOf, handleProductOrderWrite };

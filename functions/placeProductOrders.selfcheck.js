// placeProductOrders.js 자체 검증 — 배포 전에 `npm run check:products`로 돌린다.
// functions에는 테스트 러너가 없으므로 node 기본 assert만 쓴다(의존성 0).
//
// 여기서 확인하는 규칙은 클라이언트(lib/models/place_product.dart,
// test/place_product_test.dart)와 반드시 같은 결과를 내야 한다 — 판매 상태
// 판정이 어긋나면 앱에서는 살 수 있어 보이는데 서버가 거절하는 상태가 되고,
// QR 차단 사유가 어긋나면 현장에서 사장님이 설명할 수 없는 실패가 생긴다.

const assert = require('assert');

// admin.initializeApp 없이 모듈을 require하면 onCall 등록 자체는 문제없지만
// firebase-functions가 환경변수를 요구할 수 있어, 순수 헬퍼만 뽑아 쓴다.
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'selfcheck';
const admin = require('firebase-admin');
if (admin.apps.length === 0) admin.initializeApp({ projectId: 'selfcheck' });

const {
  productStatusAt,
  resolveConfirmedStatus,
  redeemBlockReason,
  issueVoucherPatch,
  orderContext,
  isSameKstDay,
  kstDateStr,
  DATE_BOUND_TYPES,
} = require('./placeProductOrders').__test;
const flow = require('./depositFlow');
const { buildPaymentInfo } = require('./paymentInfo');

/** Firestore Timestamp를 흉내내는 최소 객체(toMillis만 쓰인다). */
function ts(ms) {
  return { toMillis: () => ms };
}

const NOW = Date.UTC(2026, 7, 4, 3, 0); // 2026-08-04 12:00 KST
const DAY = 24 * 60 * 60 * 1000;

// ── 1. 판매 상태 판정 (Dart PlaceProduct.statusAt과 동일해야 함) ─────────────

function productOf(o = {}) {
  return {
    manuallyStopped: false,
    saleStartAt: null,
    saleEndAt: null,
    totalStock: 0,
    soldCount: 0,
    ...o,
  };
}

assert.strictEqual(productStatusAt(productOf(), NOW), 'on_sale',
  '기간·재고 제한이 없으면 판매 중');

assert.strictEqual(
  productStatusAt(productOf({ saleStartAt: ts(NOW + DAY) }), NOW),
  'scheduled', '판매 시작 전이면 판매 예정');

assert.strictEqual(
  productStatusAt(productOf({ saleEndAt: ts(NOW - 1) }), NOW),
  'ended', '판매 종료 후면 판매 종료');

assert.strictEqual(
  productStatusAt(productOf({ totalStock: 10, soldCount: 10 }), NOW),
  'sold_out', '수량을 다 팔면 품절');

assert.strictEqual(
  productStatusAt(productOf({ totalStock: 0, soldCount: 999 }), NOW),
  'on_sale', '수량 0(무제한)이면 많이 팔려도 품절이 아니다');

assert.strictEqual(
  productStatusAt(
    productOf({ manuallyStopped: true, saleStartAt: ts(NOW - DAY), saleEndAt: ts(NOW + DAY) }),
    NOW,
  ),
  'stopped', '수동 중지가 기간·재고보다 우선');

assert.strictEqual(
  productStatusAt(
    productOf({ totalStock: 5, soldCount: 5, saleEndAt: ts(NOW - 1) }),
    NOW,
  ),
  'ended', '판매 기간이 끝났으면 품절보다 판매 종료로 읽는다');

// ── 2. 결제 확정 직후 상태 ───────────────────────────────────────────────────

assert.strictEqual(
  resolveConfirmedStatus({ useStartAt: null }, NOW), 'usable',
  '이용 시작일이 없으면 바로 사용 가능');

assert.strictEqual(
  resolveConfirmedStatus({ useStartAt: ts(NOW + DAY) }, NOW), 'paid',
  '이용 시작 전이면 결제 완료 상태로 대기 — 미리 못 쓰게 막는 핵심');

assert.strictEqual(
  resolveConfirmedStatus({ useStartAt: ts(NOW - DAY) }, NOW), 'usable',
  '이용 기간에 들어와 있으면 사용 가능');

// ── 3. QR 사용 처리 차단 사유 ────────────────────────────────────────────────

function orderOf(o = {}) {
  return {
    status: 'usable',
    productType: 'drink',
    useStartAt: null,
    useEndAt: null,
    useAt: null,
    ...o,
  };
}

assert.strictEqual(redeemBlockReason(orderOf(), NOW), null,
  '사용 가능하고 기간 제한이 없으면 통과');

for (const [status, expected] of [
  ['used', '이미 사용한'],
  ['cancelled', '취소된'],
  ['refunded', '환불된'],
  ['expired', '기간이 만료된'],
  ['payment_pending', '결제가 완료되지'],
]) {
  const reason = redeemBlockReason(orderOf({ status }), NOW);
  assert.ok(reason && reason.includes(expected),
    `${status} 상태는 "${expected}…" 사유로 막혀야 한다 (실제: ${reason})`);
}

assert.ok(
  redeemBlockReason(orderOf({ useStartAt: ts(NOW + DAY) }), NOW).includes('이용 시작일'),
  '이용 시작 전이면 막는다');

assert.ok(
  redeemBlockReason(orderOf({ useEndAt: ts(NOW - 1) }), NOW).includes('이용 기간이 지난'),
  '이용 기간이 지나면 막는다');

// 날짜 지정 상품 — 예정일이 아니면 막고, 같은 날이면 통과한다.
assert.ok(
  redeemBlockReason(
    orderOf({ productType: 'ticket', useAt: ts(NOW + 3 * DAY) }), NOW,
  ).includes('이용 예정일이 아니에요'),
  '입장권은 예정일이 아니면 막는다');

assert.strictEqual(
  redeemBlockReason(
    orderOf({ productType: 'ticket', useAt: ts(NOW + 60 * 60 * 1000) }), NOW,
  ),
  null, '같은 날이면 시각이 달라도 통과한다(현장 판단 몫)');

// 날짜 비지정 유형은 useAt이 달라도 날짜 검증을 하지 않는다.
assert.strictEqual(
  redeemBlockReason(
    orderOf({ productType: 'membership', useAt: ts(NOW + 3 * DAY) }), NOW,
  ),
  null, '멤버십은 날짜 검증 대상이 아니다');

// paid(이용 시작 전 대기) 상태는 사용 처리 대상이 아니다.
assert.ok(
  redeemBlockReason(orderOf({ status: 'paid' }), NOW).includes('아직 사용할 수 없는'),
  'paid 상태는 아직 사용할 수 없다');

// ── 4. Dart와 유형 목록이 어긋나지 않는지 ────────────────────────────────────

assert.deepStrictEqual(
  [...DATE_BOUND_TYPES].sort(),
  ['bottle', 'experience', 'seat', 'ticket'],
  'DATE_BOUND_TYPES가 Dart PlaceProductType.isDateBound와 어긋났다',
);

// ── 5. KST 날짜 경계 ─────────────────────────────────────────────────────────

// 2026-08-04 23:30 KST = 2026-08-04 14:30 UTC
const lateNightKst = Date.UTC(2026, 7, 4, 14, 30);
assert.strictEqual(kstDateStr(lateNightKst), '2026-08-04',
  'KST 자정 직전은 아직 같은 날');

// 2026-08-05 00:30 KST = 2026-08-04 15:30 UTC
const afterMidnightKst = Date.UTC(2026, 7, 4, 15, 30);
assert.strictEqual(kstDateStr(afterMidnightKst), '2026-08-05',
  'KST 자정을 넘기면 다음 날');

assert.strictEqual(isSameKstDay(lateNightKst, afterMidnightKst), false,
  'KST 자정을 사이에 두면 다른 날');

assert.strictEqual(isSameKstDay(NOW, lateNightKst), true,
  '같은 KST 날짜면 시각이 달라도 같은 날');

// ── 6. QR 이용권은 "돈이 들어온 뒤"에만 존재하고 사용된다 ────────────────────
//
// 이 도메인의 핵심 안전장치다. 결제 상태(payment.status)와 주문 상태(status)가
// 다른 축이 된 뒤로, status만 믿으면 입금 전 이용권이 통과할 수 있다.

/** 결제수단이 붙은, QR을 쓰는 이용권 한 건. status는 '사용 가능'으로 둔다. */
const voucherOf = (paymentStatus, method = 'bank_transfer') => ({
  ...orderOf({ status: 'usable' }),
  useQrCheck: true,
  payment: { method, status: paymentStatus },
});

// ① 돈이 들어오기 전 세 상태에서는 **사용이 막힌다**.
for (const status of [flow.STATUS.awaitingDeposit, flow.STATUS.depositPending]) {
  const reason = redeemBlockReason(voucherOf(status), NOW);
  assert.ok(
    reason && reason.includes('입금'),
    `${status}에서 QR이 통과되면 안 된다 (reason=${reason})`,
  );
}
assert.ok(
  (redeemBlockReason(voucherOf(flow.STATUS.onSiteScheduled, 'on_site'), NOW) || '')
    .includes('현장 결제'),
  '현장결제가 확인되기 전에는 QR이 통과되면 안 된다',
);

// ② 결제가 확인된 뒤에야 통과한다.
assert.strictEqual(
  redeemBlockReason(voucherOf(flow.STATUS.paid), NOW), null,
  '결제완료 이용권은 사용할 수 있어야 한다');
assert.strictEqual(
  redeemBlockReason(voucherOf(flow.STATUS.paid, 'on_site'), NOW), null,
  '현장결제도 확인된 뒤에는 사용할 수 있어야 한다');

// ③ 결제 정보가 없는 옛 PG 주문은 예전 규칙 그대로다(PortOne 검증 완료분).
assert.strictEqual(
  redeemBlockReason({ ...orderOf({ status: 'usable' }), useQrCheck: true }, NOW),
  null,
  '옛 포트원 주문의 동작이 바뀌면 안 된다');

// ④ 이용권 코드는 발급 함수를 거쳐야만 생긴다.
const issued = issueVoucherPatch({ useQrCheck: true }, NOW);
assert.ok(issued.voucherCode.length > 20, '이용권 코드가 추측 가능하면 안 된다');
assert.strictEqual(issued.status, 'usable');
assert.strictEqual(issued.expiresAt, null, '확정된 주문은 만료 대상이 아니다');
assert.strictEqual(
  issueVoucherPatch({ useQrCheck: false }, NOW).voucherCode, '',
  'QR 미사용 상품에는 코드가 생기지 않는다');
// 이용 시작 전 상품은 발급돼도 아직 '사용 가능'이 아니다.
assert.strictEqual(
  issueVoucherPatch({ useQrCheck: true, useStartAt: ts(NOW + DAY) }, NOW).status,
  'paid');

// ⑤ 판매자 확인은 무통장입금과 현장결제를 모두 받고, 그 전에는 막힌다.
const liveCtx = orderContext({ status: 'payment_pending' });
assert.doesNotThrow(
  () => flow.assertCanConfirmReceived(
    { method: 'on_site', status: flow.STATUS.onSiteScheduled }, liveCtx),
  '현장결제도 판매자가 확인할 수 있어야 한다');
assert.doesNotThrow(
  () => flow.assertCanConfirmReceived(
    { method: 'bank_transfer', status: flow.STATUS.depositPending }, liveCtx));
assert.throws(
  () => flow.assertCanConfirmReceived(
    { method: 'bank_transfer', status: flow.STATUS.paid }, liveCtx),
  /이미 결제가 확인/,
  '두 번 확인해 이용권이 재발급되면 안 된다');
// 이미 사용한 주문은 확인 대상이 아니다.
assert.throws(
  () => flow.assertCanConfirmReceived(
    { method: 'on_site', status: flow.STATUS.onSiteScheduled },
    orderContext({ status: 'used' })),
  /취소된 건/);

// ⑥ PG 수단은 이 도메인에서도 거절된다.
for (const method of ['card', 'transfer', 'virtual_account', 'easy_pay']) {
  assert.throws(
    () => buildPaymentInfo({ method }, { amount: 20000, nowMs: NOW }),
    /준비 중/,
    `${method}로 이용권 주문이 만들어지면 안 된다`);
}

console.log('✅ placeProductOrders.selfcheck 통과');

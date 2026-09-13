// 파티샵 주문의 결제·만료 규칙 자체 검증 — `npm run check:shop`.
//
// 파티샵은 예약과 달리 승인 단계가 없다(재고만 있으면 성립하는 거래). 대신
// **만료 경로가 둘**이라 그 경계가 이 도메인의 유일한 위험 지점이다:
//
//   expireStaleShopOrders     10분 — 옛 포트원 결제 대기 주문
//   expireShopOrderDeposits   24시간 — 무통장입금 주문
//
// 무통장입금 주문이 10분짜리 만료에 걸리면 입금할 시간도 없이 주문이 사라지고
// 재고만 되돌아간다. 그래서 여기서 못 박는 것은 세 가지다.
// 1. 두 만료 경로가 서로의 주문을 절대 건드리지 않는다.
// 2. '입금했어요' 이후에는 어떤 만료도 주문을 지우지 않는다.
// 3. PG 수단으로는 주문이 만들어지지 않는다.

const assert = require('assert');
const flow = require('./depositFlow');
const { buildPaymentInfo } = require('./paymentInfo');
const { couponDiscountFor, isLegacyPendingOrder, orderContext } =
  require('./shopOrders').__test;

const cases = [];
function test(name, fn) {
  cases.push([name, fn]);
}

const NOW = 1_700_000_000_000;
const HOUR = 3600000;

// 무통장입금은 **판매자의 인증된 수취계좌**가 있어야 성립한다(payoutAccounts.js).
const SELLER_ACCOUNT = {
  bankName: '국민은행',
  accountNumber: '12345678901234',
  accountHolder: '홍길동',
};

test('무통장입금 주문 — 주문 즉시 입금대기 + 기한 24시간', () => {
  const info = buildPaymentInfo(
    { method: 'bank_transfer', depositorName: '김파티' },
    { amount: 45000, nowMs: NOW, payoutAccount: SELLER_ACCOUNT },
  );
  // 파티샵에는 승인 단계가 없다 — 승인대기를 거치지 않고 바로 입금대기다.
  assert.strictEqual(info.status, flow.STATUS.awaitingDeposit);
  assert.strictEqual(info.depositDeadlineMs, NOW + 24 * HOUR);
  assert.strictEqual(info.amount, 45000);
  assert.doesNotThrow(() => flow.assertCanMarkSent(info, { cancelled: false }));
});

test('현장(수령 시) 결제 — 현장결제 예정, 계좌·기한 없음', () => {
  const info = buildPaymentInfo({ method: 'on_site' }, { amount: 45000, nowMs: NOW });
  assert.strictEqual(info.status, flow.STATUS.onSiteScheduled);
  assert.strictEqual(info.depositDeadlineMs, undefined);
  // 무통장입금이 아니므로 '입금했어요'/'입금 확인' 대상이 아니다.
  assert.throws(() => flow.assertCanMarkSent(info, { cancelled: false }), /무통장입금/);
});

test('PG 수단은 파티샵에서도 거절된다 — 재고 선점까지 함께 롤백된다', () => {
  for (const method of ['card', 'transfer', 'virtual_account', 'easy_pay']) {
    assert.throws(
      () => buildPaymentInfo({ method }, { amount: 45000, nowMs: NOW }),
      /준비 중/,
      `${method}로 주문이 만들어지면 안 된다`,
    );
  }
});

test('두 만료 경로가 서로의 주문을 건드리지 않는다', () => {
  // 옛 포트원 주문 — payment 맵이 없다. 10분 만료의 대상.
  const legacy = { status: 'payment_pending' };
  assert.strictEqual(isLegacyPendingOrder(legacy), true);

  // 무통장입금 주문 — 10분 만료의 대상이 절대 아니다.
  const deposit = {
    status: 'payment_pending',
    payment: {
      method: 'bank_transfer',
      status: flow.STATUS.awaitingDeposit,
      depositDeadlineMs: NOW + 24 * HOUR,
    },
  };
  assert.strictEqual(
    isLegacyPendingOrder(deposit),
    false,
    '무통장입금 주문이 10분 만에 사라지면 안 된다',
  );
  // 대신 24시간 기한이 지나면 그쪽 스케줄러가 가져간다.
  assert.strictEqual(flow.isExpirable(deposit.payment, NOW + 23 * HOUR), false);
  assert.strictEqual(flow.isExpirable(deposit.payment, NOW + 25 * HOUR), true);

  // 이미 끝난 주문은 어느 쪽도 대상이 아니다.
  for (const status of ['paid', 'cancelled', 'refunded', 'expired']) {
    assert.strictEqual(isLegacyPendingOrder({ status }), false);
  }
});

test('입금했어요 이후에는 어떤 만료도 주문을 지우지 않는다', () => {
  const order = {
    status: 'payment_pending',
    payment: {
      method: 'bank_transfer',
      status: flow.STATUS.depositPending,
      depositDeadlineMs: NOW - HOUR, // 이미 지난 기한
    },
  };
  assert.strictEqual(isLegacyPendingOrder(order), false, '10분 만료 대상 아님');
  assert.strictEqual(
    flow.isExpirable(order.payment, NOW + 999 * HOUR),
    false,
    '입금확인중은 24시간 만료 대상도 아니다',
  );
});

test('끝난 주문은 입금·확인 어느 쪽도 통과하지 않는다', () => {
  const payment = { method: 'bank_transfer', status: flow.STATUS.awaitingDeposit };
  for (const status of ['cancelled', 'refunded', 'expired']) {
    const ctx = orderContext({ status });
    assert.strictEqual(ctx.cancelled, true, `${status}는 종료 상태여야 한다`);
    assert.throws(() => flow.assertCanMarkSent(payment, ctx), /취소/);
    assert.throws(() => flow.assertCanConfirm(payment, ctx), /취소/);
  }
  // 살아 있는 주문은 통과한다.
  assert.strictEqual(orderContext({ status: 'payment_pending' }).cancelled, false);
});

test('입금 확인은 결제완료로만 한 번 — 두 번째는 막힌다', () => {
  const ctx = orderContext({ status: 'payment_pending' });
  const sent = { method: 'bank_transfer', status: flow.STATUS.depositPending };
  assert.doesNotThrow(() => flow.assertCanConfirm(sent, ctx));
  const paid = { method: 'bank_transfer', status: flow.STATUS.paid };
  assert.throws(() => flow.assertCanConfirm(paid, ctx), /이미 입금이 확인/);
  // 구매자도 확인이 끝난 뒤에는 다시 누를 수 없다.
  assert.throws(() => flow.assertCanMarkSent(paid, ctx), /지금은/);
});

test('쿠폰 할인은 서버가 샵 문서로 다시 계산한다', () => {
  const shop = {
    hasCoupon: true,
    couponDiscountType: 'percent',
    couponDiscountValue: 10,
    couponMinAmount: 30000,
  };
  const product = {};
  // 최소 금액 미달이면 할인 없음.
  assert.strictEqual(couponDiscountFor(shop, product, 20000, true), 0);
  assert.strictEqual(couponDiscountFor(shop, product, 50000, true), 5000);
  // 쓰겠다고 하지 않으면 적용하지 않는다.
  assert.strictEqual(couponDiscountFor(shop, product, 50000, false), 0);
  // 상품이 쿠폰 대상이 아니면 무시.
  assert.strictEqual(
    couponDiscountFor(shop, { isCouponApplicable: false }, 50000, true),
    0,
  );
  // 할인액은 결제 금액을 넘지 못한다(음수 결제 방지).
  assert.strictEqual(
    couponDiscountFor(
      { hasCoupon: true, couponDiscountType: 'amount', couponDiscountValue: 99999 },
      product,
      10000,
      true,
    ),
    10000,
  );
});

let failed = 0;
for (const [name, fn] of cases) {
  try {
    fn();
    console.log(`  ✓ ${name}`);
  } catch (e) {
    failed += 1;
    console.error(`  ✗ ${name}\n    ${e.message}`);
  }
}
console.log(
  failed === 0
    ? `\n파티샵 주문 결제 흐름 검증 통과 — ${cases.length}건`
    : `\n실패 ${failed}건 / 전체 ${cases.length}건`,
);
process.exit(failed === 0 ? 0 : 1);

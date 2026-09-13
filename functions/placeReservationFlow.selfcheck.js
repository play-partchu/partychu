// 장소대여 예약의 승인·입금·슬롯 점유 규칙 자체 검증 — `npm run check:rental`.
//
// 여기서 못 박는 것은 딱 두 가지다.
// 1. **승인 전에는 입금을 요구하지 않는다** — 승인제 룸은 '승인대기'로 시작하고,
//    승인되는 순간에야 입금대기 + 기한이 생긴다.
// 2. **자리를 언제까지 잡고 있는가**가 상태 조합마다 하나로 정해진다 —
//    입금기한이 지나면 풀리고, 입금했다고 알린 뒤에는 풀리지 않는다.
//
// 예약 방식(stay/hourly/package)은 슬롯 배열 길이만 다를 뿐 규칙이 같으므로
// 방식별 분기가 없다는 것도 함께 확인한다.

const assert = require('assert');
const rental = require('./placeReservationFlow');
const flow = require('./depositFlow');
const { buildPaymentInfo } = require('./paymentInfo');

const cases = [];
function test(name, fn) {
  cases.push([name, fn]);
}

const NOW = 1_700_000_000_000;
const HOUR = 3600000;
const MIDNIGHT = 1_700_000_000_000; // 기준 자정(값 자체는 뜻이 없다)

// 세 예약 방식이 만들어내는 구간(window) 모양 — roomAvailability.computeWindows가
// 실제로 돌려주는 형태와 같다.
const WINDOWS = {
  // 체크인 16:00 → 다음날 체크아웃 11:00
  stay: [{ start: 960, end: 2100, price: 100000 }],
  // 14:00~16:00, 18:00~20:00 두 구간
  hourly: [
    { start: 840, end: 960, price: 20000 },
    { start: 1080, end: 1200, price: 20000 },
  ],
  // 22:00~다음날 05:00 올나잇 패키지
  package: [{ start: 1320, end: 1740, price: 80000 }],
};

test('승인 방식 — 설정이 없으면 지금까지처럼 자동승인이다', () => {
  assert.strictEqual(rental.normalizeApprovalMode(undefined), 'auto');
  assert.strictEqual(rental.normalizeApprovalMode(null), 'auto');
  assert.strictEqual(rental.normalizeApprovalMode('auto'), 'auto');
  assert.strictEqual(rental.normalizeApprovalMode('manual'), 'manual');
  // 알 수 없는 값이 승인제로 읽혀 예약이 멈추는 일이 없게 한다.
  assert.strictEqual(rental.normalizeApprovalMode('yes'), 'auto');
});

test('이용 시작·종료 시각 — 시간제는 가장 이른/늦은 구간이 기준이다', () => {
  assert.strictEqual(
    rental.useStartMs(MIDNIGHT, WINDOWS.hourly),
    MIDNIGHT + 840 * 60000,
  );
  assert.strictEqual(
    rental.useEndMs(MIDNIGHT, WINDOWS.hourly),
    MIDNIGHT + 1200 * 60000,
  );
  // 숙박·패키지는 구간이 하나뿐이라 그 값 그대로.
  assert.strictEqual(rental.useStartMs(MIDNIGHT, WINDOWS.stay), MIDNIGHT + 960 * 60000);
  assert.strictEqual(rental.useEndMs(MIDNIGHT, WINDOWS.package), MIDNIGHT + 1740 * 60000);
  assert.strictEqual(rental.useStartMs(MIDNIGHT, []), null);
});

test('승인 기한은 이용 시작 시각을 넘지 않는다', () => {
  // 12시간 기한인데 이용이 3시간 뒤 — 그때가 곧 마감이다.
  const soon = NOW + 3 * HOUR;
  assert.strictEqual(rental.approvalDeadlineMs(NOW, 12, soon), soon);
  // 이용이 한참 뒤면 설정한 시간이 그대로 기한이다.
  const later = NOW + 100 * HOUR;
  assert.strictEqual(rental.approvalDeadlineMs(NOW, 12, later), NOW + 12 * HOUR);
  // 설정이 없으면 기본 12시간.
  assert.strictEqual(
    rental.approvalDeadlineMs(NOW, undefined, later),
    NOW + rental.DEFAULT_APPROVAL_HOURS * HOUR,
  );
});

// 무통장입금은 **호스트의 인증된 수취계좌**가 있어야 성립한다(payoutAccounts.js).
// 이 파일이 보는 것은 상태 전이라 계좌는 최소 형태로만 넘긴다.
const HOST_ACCOUNT = {
  bankName: '국민은행',
  accountNumber: '12345678901234',
  accountHolder: '홍길동',
};

test('승인제 — 승인 전에는 입금대기가 되지 않고 입금 버튼도 막힌다', () => {
  const info = buildPaymentInfo(
    { method: 'bank_transfer' },
    {
      amount: 100000,
      nowMs: NOW,
      requireApproval: true,
      useAtMs: NOW + 100 * HOUR,
      payoutAccount: HOST_ACCOUNT,
    },
  );
  assert.strictEqual(info.status, flow.STATUS.awaitingApproval);
  // 승인 전에는 기한 자체가 없다 — 아직 입금을 요구하지 않았기 때문.
  assert.strictEqual(info.depositDeadlineMs, undefined);
  assert.throws(
    () => flow.assertCanMarkSent(info, { cancelled: false }),
    /승인/,
    '승인 전에 입금했어요가 통과되면 안 된다',
  );
});

test('자동승인 — 예약 직후 바로 입금대기 + 기한 시작', () => {
  const info = buildPaymentInfo(
    { method: 'bank_transfer' },
    {
      amount: 100000,
      nowMs: NOW,
      requireApproval: false,
      useAtMs: NOW + 100 * HOUR,
      payoutAccount: HOST_ACCOUNT,
    },
  );
  assert.strictEqual(info.status, flow.STATUS.awaitingDeposit);
  assert.strictEqual(info.depositDeadlineMs, NOW + 24 * HOUR);
  // 이 상태에서는 '입금했어요'를 누를 수 있다.
  assert.doesNotThrow(() => flow.assertCanMarkSent(info, { cancelled: false }));
});

test('승인 시점에 비로소 입금대기가 되고, 기한은 이용 시각을 넘지 않는다', () => {
  const info = buildPaymentInfo(
    { method: 'bank_transfer' },
    {
      amount: 100000,
      nowMs: NOW,
      requireApproval: true,
      useAtMs: NOW + 6 * HOUR,
      payoutAccount: HOST_ACCOUNT,
    },
  );
  const approved = flow.approvePatch(info, NOW + HOUR, { notAfterMs: NOW + 6 * HOUR });
  assert.strictEqual(approved.status, flow.STATUS.awaitingDeposit);
  // 승인 + 24시간이 아니라 이용 시작 시각(6시간 뒤)이 기한이다.
  assert.strictEqual(approved.depositDeadlineMs, NOW + 6 * HOUR);
});

test('슬롯 점유 — 승인대기는 업주 응답 기한까지만 잡는다', () => {
  const respondByMs = NOW + 12 * HOUR;
  const hold = rental.slotHoldOf(rental.STATUS.requested, null, { respondByMs });
  assert.deepStrictEqual(hold, { status: 'pending', expiresAtMs: respondByMs });
});

test('슬롯 점유 — 확정 + 입금대기는 입금기한까지만 잡는다(지나면 풀린다)', () => {
  const payment = {
    method: 'bank_transfer',
    status: flow.STATUS.awaitingDeposit,
    depositDeadlineMs: NOW + 24 * HOUR,
  };
  const hold = rental.slotHoldOf(rental.STATUS.confirmed, payment);
  assert.deepStrictEqual(hold, { status: 'pending', expiresAtMs: NOW + 24 * HOUR });
  // 실제로 만료 대상으로 잡히는지도 같은 값으로 확인한다.
  assert.strictEqual(flow.isExpirable(payment, NOW + 25 * HOUR), true);
});

test('슬롯 점유 — 입금했다고 알린 뒤에는 기한 없이 잡는다', () => {
  const payment = {
    method: 'bank_transfer',
    status: flow.STATUS.depositPending,
    depositDeadlineMs: NOW + HOUR,
  };
  const hold = rental.slotHoldOf(rental.STATUS.confirmed, payment);
  assert.deepStrictEqual(hold, { status: 'confirmed', expiresAtMs: null });
  // 자동 만료 대상에서도 빠진다 — 이미 낸 사람의 자리를 뺏지 않는다.
  assert.strictEqual(flow.isExpirable(payment, NOW + 24 * HOUR), false);
});

test('슬롯 점유 — 결제완료·현장결제·무료는 기한 없이 확정으로 잡는다', () => {
  for (const payment of [
    { method: 'bank_transfer', status: flow.STATUS.paid },
    { method: 'on_site', status: flow.STATUS.onSiteScheduled },
    null,
  ]) {
    assert.deepStrictEqual(
      rental.slotHoldOf(rental.STATUS.confirmed, payment),
      { status: 'confirmed', expiresAtMs: null },
      `${payment && payment.status} 가 확정 점유여야 한다`,
    );
  }
});

test('슬롯 점유 — 끝난 예약은 해제 로직이 따로 다룬다(null)', () => {
  for (const status of ['cancelled', 'rejected', 'expired']) {
    assert.strictEqual(rental.slotHoldOf(status, null), null);
    assert.strictEqual(rental.isLive(status), false);
  }
  for (const status of ['pending', 'requested', 'confirmed']) {
    assert.strictEqual(rental.isLive(status), true);
  }
});

test('예약 방식 세 가지가 같은 규칙을 탄다 — 구간 개수만 다르다', () => {
  const payment = {
    method: 'bank_transfer',
    status: flow.STATUS.awaitingDeposit,
    depositDeadlineMs: NOW + 24 * HOUR,
  };
  const expected = rental.slotHoldOf(rental.STATUS.confirmed, payment);
  for (const [mode, windows] of Object.entries(WINDOWS)) {
    // 어떤 방식이든 슬롯 점유 판정은 완전히 같다(분기 없음).
    assert.deepStrictEqual(
      rental.slotHoldOf(rental.STATUS.confirmed, payment),
      expected,
      `${mode}가 다른 규칙을 타면 안 된다`,
    );
    // 이용 시각만 구간에서 뽑힌다.
    assert.ok(rental.useStartMs(MIDNIGHT, windows) < rental.useEndMs(MIDNIGHT, windows));
  }
});

test('취소된 예약은 입금·확인 어느 쪽도 통과하지 않는다', () => {
  const payment = { method: 'bank_transfer', status: flow.STATUS.awaitingDeposit };
  const ctx = rental.docContext({ status: 'cancelled' });
  assert.strictEqual(ctx.cancelled, true);
  assert.throws(() => flow.assertCanMarkSent(payment, ctx), /취소/);
  assert.throws(() => flow.assertCanConfirm(payment, ctx), /취소/);
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
    ? `\n장소대여 예약 흐름 자체 검증 통과 — ${cases.length}건`
    : `\n실패 ${failed}건 / 전체 ${cases.length}건`,
);
process.exit(failed === 0 ? 0 : 1);

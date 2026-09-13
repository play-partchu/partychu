// 결제 정보(payment) 서버 규칙 자체 검증 — `npm run check:payment`.
//
// 돈이 걸린 부분이라 두 가지를 못 박는다.
// 1. 클라이언트가 보낸 status는 **무시**된다(paid를 보내도 결제완료가 안 된다).
// 2. 준비중인 수단(카드·간편결제 등)으로는 주문이 만들어지지 않는다.

const assert = require('assert');
const { buildPaymentInfo, DEPOSIT_WINDOW_MS } = require('./paymentInfo');

const cases = [];
function test(name, fn) {
  cases.push([name, fn]);
}

const NOW = 1_700_000_000_000;

test('무료면 결제 정보 자체가 없다', () => {
  assert.strictEqual(buildPaymentInfo(undefined, { amount: 0, nowMs: NOW }), null);
  assert.strictEqual(
    buildPaymentInfo({ method: 'bank_transfer' }, { amount: 0, nowMs: NOW }),
    null,
  );
});

// 호스트의 **인증된 수취계좌** — 무통장입금은 이 값이 있어야만 성립한다.
// (파티츄 공용 계좌 상수는 없앴다 — paymentInfo.js 상단 주석 참고.)
const HOST_ACCOUNT = {
  bankName: '국민은행',
  accountNumber: '12345678901234',
  accountHolder: '홍길동',
  hostUid: 'host-1',
};

test('무통장입금 — 입금대기 + 기한 24시간 + 호스트 계좌 스냅샷', () => {
  const info = buildPaymentInfo(
    { method: 'bank_transfer', depositorName: '  김파티  ' },
    { amount: 30000, nowMs: NOW, payoutAccount: HOST_ACCOUNT },
  );
  assert.strictEqual(info.method, 'bank_transfer');
  assert.strictEqual(info.status, 'awaiting_deposit');
  assert.strictEqual(info.amount, 30000);
  assert.strictEqual(info.depositorName, '김파티');
  assert.strictEqual(info.depositDeadlineMs, NOW + DEPOSIT_WINDOW_MS);
  // 안내 계좌는 플랫폼 공용이 아니라 **그 콘텐츠 호스트의 계좌**다.
  assert.strictEqual(info.bankName, '국민은행');
  assert.strictEqual(info.accountNumber, '12345678901234');
  assert.strictEqual(info.accountHolder, '홍길동');
  // 이 돈을 받은 사람 = 나중에 환불을 처리할 사람.
  assert.strictEqual(info.payoutHostUid, 'host-1');
});

test('호스트가 계좌를 인증하지 않았으면 무통장입금은 거절된다', () => {
  // 폴백이 있으면 검증되지 않은(혹은 남의) 계좌로 돈이 나간다 — 폴백 없음.
  assert.throws(
    () =>
      buildPaymentInfo(
        { method: 'bank_transfer' },
        { amount: 30000, nowMs: NOW, payoutAccount: null },
      ),
    /무통장입금/,
  );
  assert.throws(
    () => buildPaymentInfo({ method: 'bank_transfer' }, { amount: 30000, nowMs: NOW }),
    /무통장입금/,
    '아예 넘기지 않은 경우도 같다',
  );
});

test('현장결제 — 현장결제 예정, 계좌 정보 없음', () => {
  const info = buildPaymentInfo({ method: 'on_site' }, { amount: 30000, nowMs: NOW });
  assert.strictEqual(info.status, 'on_site_scheduled');
  assert.strictEqual(info.accountNumber, undefined);
  assert.strictEqual(info.depositDeadlineMs, undefined);
});

test('클라이언트가 보낸 status는 무시된다', () => {
  const info = buildPaymentInfo(
    { method: 'bank_transfer', status: 'paid', paidAtMs: NOW },
    { amount: 10000, nowMs: NOW, payoutAccount: HOST_ACCOUNT },
  );
  assert.strictEqual(info.status, 'awaiting_deposit');
  assert.strictEqual(info.paidAtMs, undefined);
});

test('준비중 수단은 거절된다', () => {
  for (const method of ['card', 'transfer', 'virtual_account', 'easy_pay']) {
    assert.throws(
      () => buildPaymentInfo({ method }, { amount: 10000, nowMs: NOW }),
      /준비 중/,
      `${method}가 통과되면 안 된다`,
    );
  }
});

test('유료인데 결제수단이 없으면 거절된다', () => {
  assert.throws(
    () => buildPaymentInfo(undefined, { amount: 10000, nowMs: NOW }),
    /결제수단/,
  );
  assert.throws(
    () => buildPaymentInfo({ method: 'wire' }, { amount: 10000, nowMs: NOW }),
    /지원하지 않는/,
  );
});

// ── 파티 무통장입금 상태 전이 ─────────────────────────────────────────
// (Firestore 없이 판정 규칙만 검사한다 — 중복 클릭 차단이 여기 걸려 있다.)
const { assertCanMarkSent, assertCanConfirm } = require('./partyDeposits');

const app = (paymentStatus, status = 'applied') => ({
  status,
  payment: { method: 'bank_transfer', status: paymentStatus },
});

test('입금했어요 — 입금대기일 때만 가능', () => {
  assert.doesNotThrow(() => assertCanMarkSent(app('awaiting_deposit')));
});

test('입금했어요 — 두 번 누를 수 없다', () => {
  assert.throws(() => assertCanMarkSent(app('deposit_pending')), /기다리고 있어요/);
});

test('입금했어요 — 확인이 끝났거나 만료·취소된 건은 불가', () => {
  assert.throws(() => assertCanMarkSent(app('paid')), /요청할 수 없어요/);
  assert.throws(() => assertCanMarkSent(app('expired')), /요청할 수 없어요/);
  assert.throws(
    () => assertCanMarkSent(app('awaiting_deposit', 'cancelled')),
    /취소된 건/,
  );
});

test('입금했어요 — 현장결제 신청에는 없는 동작', () => {
  assert.throws(
    () => assertCanMarkSent({ status: 'applied', payment: { method: 'on_site', status: 'on_site_scheduled' } }),
    /무통장입금 건이 아니/,
  );
});

test('입금 확인 — 입금대기·입금확인중 둘 다 가능', () => {
  assert.doesNotThrow(() => assertCanConfirm(app('deposit_pending')));
  assert.doesNotThrow(() => assertCanConfirm(app('awaiting_deposit')));
});

test('입금 확인 — 두 번 확정되지 않는다', () => {
  assert.throws(() => assertCanConfirm(app('paid')), /이미 입금이 확인/);
});

test('입금 확인 — 만료·취소된 건은 불가', () => {
  assert.throws(() => assertCanConfirm(app('expired')), /확인할 수 없어요/);
  assert.throws(
    () => assertCanConfirm(app('deposit_pending', 'cancelled')),
    /취소된 건/,
  );
});

// ── 승인제(플레이스 방문예약) — 승인 후 입금 ──────────────────────────
const flow = require('./depositFlow');

test('승인제 매장 — 무통장은 승인대기로 시작하고 기한이 아직 없다', () => {
  const info = buildPaymentInfo(
    { method: 'bank_transfer' },
    { amount: 40000, nowMs: NOW, requireApproval: true, payoutAccount: HOST_ACCOUNT },
  );
  assert.strictEqual(info.status, 'awaiting_approval');
  assert.strictEqual(info.depositDeadlineMs, undefined);
});

test('승인제 매장 — 현장결제는 승인과 무관하게 현장결제 예정', () => {
  const info = buildPaymentInfo(
    { method: 'on_site' },
    { amount: 40000, nowMs: NOW, requireApproval: true },
  );
  assert.strictEqual(info.status, 'on_site_scheduled');
});

test('자동승인 매장 — 신청 즉시 입금대기 + 기한은 방문 시각을 넘지 않는다', () => {
  const visitInTwoHours = NOW + 2 * 3600000;
  const info = buildPaymentInfo(
    { method: 'bank_transfer' },
    { amount: 40000, nowMs: NOW, useAtMs: visitInTwoHours, payoutAccount: HOST_ACCOUNT },
  );
  assert.strictEqual(info.status, 'awaiting_deposit');
  assert.strictEqual(info.depositDeadlineMs, visitInTwoHours);
});

test('승인대기 상태에서는 입금했어요·입금확인 둘 다 막힌다', () => {
  const p = { method: 'bank_transfer', status: 'awaiting_approval' };
  assert.throws(() => flow.assertCanMarkSent(p), /아직 승인 전/);
  assert.throws(() => flow.assertCanConfirm(p), /먼저 예약을 승인/);
});

test('승인되면 입금대기로 바뀌고 기한이 시작된다', () => {
  const p = { method: 'bank_transfer', status: 'awaiting_approval' };
  const patch = flow.approvePatch(p, NOW, { notAfterMs: null });
  assert.strictEqual(patch.status, 'awaiting_deposit');
  assert.strictEqual(patch.depositDeadlineMs, NOW + DEPOSIT_WINDOW_MS);
  // 이미 입금대기인 건을 다시 승인해도 기한이 밀리지 않는다.
  assert.strictEqual(
    flow.approvePatch({ method: 'bank_transfer', status: 'awaiting_deposit' }, NOW),
    null,
  );
  // 현장결제는 승인해도 결제 상태가 바뀌지 않는다.
  assert.strictEqual(
    flow.approvePatch({ method: 'on_site', status: 'on_site_scheduled' }, NOW),
    null,
  );
});

test('자동 만료 대상 — 입금대기만, 입금확인중은 제외', () => {
  const past = NOW - 1000;
  assert.strictEqual(
    flow.isExpirable(
      { method: 'bank_transfer', status: 'awaiting_deposit', depositDeadlineMs: past },
      NOW,
    ),
    true,
  );
  assert.strictEqual(
    flow.isExpirable(
      { method: 'bank_transfer', status: 'deposit_pending', depositDeadlineMs: past },
      NOW,
    ),
    false,
  );
  assert.strictEqual(
    flow.isExpirable(
      { method: 'bank_transfer', status: 'awaiting_approval', depositDeadlineMs: past },
      NOW,
    ),
    false,
  );
});

let failed = 0;
for (const [name, fn] of cases) {
  try {
    fn();
    console.log(`  ok  ${name}`);
  } catch (e) {
    failed++;
    console.error(`FAIL  ${name}\n      ${e.message}`);
  }
}
console.log(`\n${cases.length - failed}/${cases.length} passed`);
process.exit(failed === 0 ? 0 : 1);

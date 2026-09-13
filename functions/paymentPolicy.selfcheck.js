// 호스트 결제 정책(예약금) 서버 규칙 자체 검증 — `npm run check:policy`.
//
// 돈이 걸린 부분이라 아래를 못 박는다.
// 1. 정책이 없는 **기존 문서는 지금까지의 동작 그대로**다(구매자가 수단 자유 선택).
// 2. 비율 예약금은 **예약 당시 최종 이용요금** 기준으로만 계산된다.
// 3. 총액이 확정되지 않으면 비율 예약금은 아예 만들 수 없고, 잔금은 null이다.
// 4. 고정 예약금은 총액을 넘지 못한다.
// 5. 호스트 정책과 다른 결제수단은 서버가 거절한다.
// 6. 환불 상한이 되는 '실제 결제된 금액'은 payment.status === 'paid'일 때만 잡힌다.

const assert = require('assert');
const p = require('./paymentPolicy');

const cases = [];
function test(name, fn) {
  cases.push([name, fn]);
}

function throws(fn, re) {
  assert.throws(fn, (e) => (re ? re.test(e.message) : true));
}

// ── 정책 없음(legacy) ─────────────────────────────────────────────────────

test('정책이 없으면 null로 정규화된다 — 기존 문서', () => {
  assert.strictEqual(p.normalizePolicy(undefined), null);
  assert.strictEqual(p.normalizePolicy(null), null);
  assert.strictEqual(p.normalizePolicy({}), null);
  assert.strictEqual(p.normalizePolicy({ paymentMode: 'nope' }), null);
});

test('정책이 없으면 무통장입금·현장결제를 모두 고를 수 있다', () => {
  assert.deepStrictEqual(p.allowedMethodsFor(null), ['bank_transfer', 'on_site']);
  p.assertMethodAllowed(null, 'bank_transfer');
  p.assertMethodAllowed(null, 'on_site');
});

test('정책이 없으면 금액은 전액 그대로 — 기존 동작 유지', () => {
  const b = p.computeBreakdown(null, 30000);
  assert.strictEqual(b.paymentMode, null);
  assert.strictEqual(b.totalAmount, 30000);
  assert.strictEqual(b.paymentAmount, 30000);
  // 예약금 개념이 없으므로 지어내지 않는다.
  assert.strictEqual(b.upfrontAmount, null);
  assert.strictEqual(b.remainingAmount, null);
});

// ── 문서에서 정책 필드 뽑기 (평평한 저장 형태) ────────────────────────────
//
// 앱은 PaymentPolicy.toMap()을 파티/룸 문서에 **그대로 펼쳐** 저장한다.
// 서버가 중첩(doc.paymentPolicy)으로 읽으면 정책이 조용히 무시되어 예약금이
// 걸린 예약에서 전액이 청구된다 — 실제로 운영 검증에서 잡힌 사고다.

test('문서 최상단의 평평한 필드에서 정책을 뽑는다', () => {
  const partyDoc = {
    title: 'QA', price: 50000, hostId: 'abc',
    paymentMode: 'partial', upfrontType: 'percentage', upfrontPercent: 20,
  };
  const picked = p.pickPolicyFields(partyDoc);
  assert.strictEqual(picked.paymentMode, 'partial');
  assert.strictEqual(picked.upfrontPercent, 20);
  const pol = p.normalizePolicy(picked);
  assert.strictEqual(p.computeBreakdown(pol, 50000).upfrontAmount, 10000);
});

test('paymentMode가 없는 문서는 null — 기존 파티/룸', () => {
  assert.strictEqual(p.pickPolicyFields({ title: 'old', price: 30000 }), null);
  assert.strictEqual(p.pickPolicyFields(null), null);
  assert.strictEqual(p.pickPolicyFields(undefined), null);
});

test('중첩 맵으로 감싸 넘기면 정책이 잡히지 않는다 — 저장 형태는 평평이다', () => {
  const wrapped = { paymentPolicy: { paymentMode: 'partial', upfrontType: 'fixed', upfrontFixedAmount: 5000 } };
  assert.strictEqual(p.pickPolicyFields(wrapped), null);
});

// ── prepaid ───────────────────────────────────────────────────────────────

test('전액 선결제 — 지금 전액, 잔금 0', () => {
  const pol = p.normalizePolicy({ paymentMode: 'prepaid' });
  const b = p.computeBreakdown(pol, 200000);
  assert.strictEqual(b.upfrontAmount, 200000);
  assert.strictEqual(b.remainingAmount, 0);
  assert.strictEqual(b.paymentAmount, 200000);
  assert.deepStrictEqual(p.allowedMethodsFor('prepaid'), ['bank_transfer']);
});

test('전액 선결제에 현장결제를 보내면 거절', () => {
  const pol = p.normalizePolicy({ paymentMode: 'prepaid' });
  throws(() => p.assertMethodAllowed(pol, 'on_site'), /전액 선결제/);
});

test('총액 미확정 도메인에서는 전액 선결제를 설정할 수 없다', () => {
  throws(
    () => p.normalizePolicy({ paymentMode: 'prepaid' }, { allowPrepaid: false }),
    /전액 선결제/,
  );
});

// ── onsite ────────────────────────────────────────────────────────────────

test('현장 전액결제 — 지금 0원, 현장에서 전액', () => {
  const pol = p.normalizePolicy({ paymentMode: 'onsite' });
  const b = p.computeBreakdown(pol, 200000);
  assert.strictEqual(b.upfrontAmount, 0);
  assert.strictEqual(b.remainingAmount, 200000);
  assert.deepStrictEqual(p.allowedMethodsFor('onsite'), ['on_site']);
});

test('현장 전액결제에 무통장입금을 보내면 거절', () => {
  const pol = p.normalizePolicy({ paymentMode: 'onsite' });
  throws(() => p.assertMethodAllowed(pol, 'bank_transfer'), /현장결제만/);
});

test('prepaid·onsite는 예약금 항목을 저장하지 않는다', () => {
  const a = p.normalizePolicy({
    paymentMode: 'onsite',
    upfrontType: 'percentage',
    upfrontPercent: 20,
  });
  assert.deepStrictEqual(a, { paymentMode: 'onsite' });
});

// ── partial: 비율 ─────────────────────────────────────────────────────────

test('비율 예약금 — 최종 이용요금 기준으로 계산', () => {
  const pol = p.normalizePolicy({
    paymentMode: 'partial',
    upfrontType: 'percentage',
    upfrontPercent: 20,
  });
  const b = p.computeBreakdown(pol, 300000);
  assert.strictEqual(b.upfrontAmount, 60000);
  assert.strictEqual(b.remainingAmount, 240000);
  assert.strictEqual(b.paymentAmount, 60000);
});

test('비율 예약금 — 총액이 달라지면 예약금도 함께 달라진다', () => {
  const pol = p.normalizePolicy({
    paymentMode: 'partial',
    upfrontType: 'percentage',
    upfrontPercent: 20,
  });
  // 숙박일수·주말가격·옵션으로 최종금액이 커진 경우
  assert.strictEqual(p.computeBreakdown(pol, 450000).upfrontAmount, 90000);
  assert.strictEqual(p.computeBreakdown(pol, 450000).remainingAmount, 360000);
});

test('비율은 1~100%만 허용', () => {
  const bad = (pct) =>
    p.normalizePolicy({ paymentMode: 'partial', upfrontType: 'percentage', upfrontPercent: pct });
  throws(() => bad(0), /1~100/);
  throws(() => bad(-10), /1~100/);
  throws(() => bad(101), /1~100/);
  assert.strictEqual(bad(100).upfrontPercent, 100);
});

test('총액 미확정 도메인에서는 비율 예약금을 설정할 수 없다', () => {
  throws(
    () =>
      p.normalizePolicy(
        { paymentMode: 'partial', upfrontType: 'percentage', upfrontPercent: 20 },
        { allowPercentage: false },
      ),
    /비율 예약금/,
  );
});

test('총액을 모르는데 비율 정책이 남아 있으면 계산을 거부한다', () => {
  const pol = {
    paymentMode: 'partial',
    upfrontType: 'percentage',
    upfrontPercent: 20,
  };
  throws(() => p.computeBreakdown(pol, null), /알 수 없어/);
});

// ── partial: 고정 ─────────────────────────────────────────────────────────

test('고정 예약금 — 지금 고정액, 잔금은 나머지', () => {
  const pol = p.normalizePolicy({
    paymentMode: 'partial',
    upfrontType: 'fixed',
    upfrontFixedAmount: 50000,
  });
  const b = p.computeBreakdown(pol, 300000);
  assert.strictEqual(b.upfrontAmount, 50000);
  assert.strictEqual(b.remainingAmount, 250000);
});

test('고정 예약금은 총 이용요금을 넘을 수 없다', () => {
  const pol = p.normalizePolicy({
    paymentMode: 'partial',
    upfrontType: 'fixed',
    upfrontFixedAmount: 500000,
  });
  const b = p.computeBreakdown(pol, 300000);
  assert.strictEqual(b.upfrontAmount, 300000);
  assert.strictEqual(b.remainingAmount, 0); // 잔금이 음수가 되지 않는다
});

test('고정 예약금 금액은 0보다 커야 한다', () => {
  throws(
    () =>
      p.normalizePolicy({ paymentMode: 'partial', upfrontType: 'fixed', upfrontFixedAmount: 0 }),
    /예약금 금액/,
  );
});

test('예약금 방식을 고르지 않으면 거절', () => {
  throws(() => p.normalizePolicy({ paymentMode: 'partial' }), /예약금 방식/);
});

test('총액 미확정 + 고정 예약금 — 잔금은 0이 아니라 null(모름)', () => {
  const pol = p.normalizePolicy(
    { paymentMode: 'partial', upfrontType: 'fixed', upfrontFixedAmount: 20000 },
    { allowPercentage: false, allowPrepaid: false },
  );
  const b = p.computeBreakdown(pol, null);
  assert.strictEqual(b.upfrontAmount, 20000);
  assert.strictEqual(b.remainingAmount, null);
  assert.strictEqual(b.totalAmount, null);
});

// ── 스냅샷 ────────────────────────────────────────────────────────────────

test('스냅샷에 정책값까지 복사된다 — 나중에 호스트가 바꿔도 불변', () => {
  const pol = p.normalizePolicy({
    paymentMode: 'partial',
    upfrontType: 'percentage',
    upfrontPercent: 20,
  });
  const snap = p.snapshotOf(pol, 300000);
  assert.deepStrictEqual(snap, {
    paymentMode: 'partial',
    totalAmount: 300000,
    upfrontAmount: 60000,
    remainingAmount: 240000,
    upfrontType: 'percentage',
    upfrontPercent: 20,
  });

  // 호스트가 40%로 바꿔도 위 스냅샷은 그대로다(재계산하지 않는다).
  const changed = p.normalizePolicy({
    paymentMode: 'partial',
    upfrontType: 'percentage',
    upfrontPercent: 40,
  });
  assert.strictEqual(p.snapshotOf(changed, 300000).upfrontAmount, 120000);
  assert.strictEqual(snap.upfrontAmount, 60000);
});

test('legacy 스냅샷에는 예약금 항목이 없다', () => {
  const snap = p.snapshotOf(null, 30000);
  assert.strictEqual(snap.paymentMode, null);
  assert.strictEqual(snap.upfrontType, undefined);
});

// ── 클라이언트 금액 대조 ──────────────────────────────────────────────────

test('클라이언트가 보낸 금액이 서버 계산과 다르면 거절', () => {
  const pol = p.normalizePolicy({
    paymentMode: 'partial',
    upfrontType: 'percentage',
    upfrontPercent: 20,
  });
  const b = p.computeBreakdown(pol, 300000);
  // 총액 300,000에 예약금 1원을 주장하는 경우
  throws(() => p.assertClientAmountMatches(b, { upfrontAmount: 1 }), /금액이 변경/);
  throws(() => p.assertClientAmountMatches(b, { totalAmount: 1000 }), /금액이 변경/);
  // 일치하면 통과
  p.assertClientAmountMatches(b, { totalAmount: 300000, upfrontAmount: 60000 });
  // 아예 안 보내면 검사하지 않는다(서버 계산이 정본).
  p.assertClientAmountMatches(b, undefined);
});

// ── 실결제액(환불 상한) ───────────────────────────────────────────────────

test('결제완료가 아니면 실결제액은 0원', () => {
  assert.strictEqual(p.paidAmountOf(null), 0);
  assert.strictEqual(p.paidAmountOf({ status: 'awaiting_deposit', amount: 60000 }), 0);
  assert.strictEqual(p.paidAmountOf({ status: 'deposit_pending', amount: 60000 }), 0);
  // 현장결제 예정 — 아직 한 푼도 받지 않았다.
  assert.strictEqual(p.paidAmountOf({ status: 'on_site_scheduled', amount: 200000 }), 0);
});

test('예약금 결제 건의 실결제액은 예약금뿐', () => {
  const snap = { upfrontAmount: 60000, totalAmount: 200000 };
  assert.strictEqual(p.paidAmountOf({ status: 'paid', amount: 60000 }, snap), 60000);
});

test('금액이 비어 있으면 스냅샷의 예약금으로 보정', () => {
  const snap = { upfrontAmount: 60000, totalAmount: 200000 };
  assert.strictEqual(p.paidAmountOf({ status: 'paid' }, snap), 60000);
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

// 환불 규정 스냅샷 자체 검증 — `npm run check:refundsnapshot`.
//
// 못 박는 것은 하나다: **신청·예약이 접수된 뒤 호스트가 환불 규정을 바꿔도
// 이미 접수된 건의 환불 조건은 변하지 않는다.**
//
// 예전에는 취소 시점에 파티 문서의 현재 refundPolicy를 읽었다. 그래서 호스트가
// "3일 전 80% 환불"로 모집해 놓고 신청을 받은 뒤 "환불 불가"로 바꾸면, 이미
// 신청한 사람의 환불까지 소급해서 0%가 됐다. 참가자가 신청 전에 확인하고
// 동의한 조건과 달라지는 것이라 금액 스냅샷(appliedFee/amounts)과 같은 방식으로
// 규정도 신청 문서에 박아둔다.
//
// 마이그레이션은 하지 않는다 — 스냅샷 필드가 아예 없는 옛 문서만 예전처럼
// 파티의 현재 규정으로 폴백한다(하위 호환).

process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'selfcheck';

const assert = require('assert');
const {
  computeRefund,
  snapshotRefundPolicy,
  effectiveRefundPolicy,
} = require('./partyCapacity');
const { buildApplicationDoc, applicationDocOf } = require('./packageBookings').__test;

const cases = [];
const test = (name, fn) => cases.push([name, fn]);

// 호스트가 모집 시점에 걸어둔 규정(A)과, 나중에 바꾼 규정(B).
const POLICY_A = [{ daysBefore: 3, refundPercent: 80 }];
const POLICY_B = [{ daysBefore: 3, refundPercent: 10 }];
const FEE = 50000;
const IN_10_DAYS = () => new Date(Date.now() + 10 * 24 * 60 * 60 * 1000);

// ── 스냅샷 생성 ──────────────────────────────────────────────────────────

test('파티의 환불 규정을 그대로 복사한다', () => {
  assert.deepStrictEqual(snapshotRefundPolicy({ refundPolicy: POLICY_A }), POLICY_A);
});

test('규정을 설정하지 않은 파티는 빈 배열로 스냅샷된다 — null이 아니다', () => {
  // 빈 배열이어야 "스냅샷은 있고 내용이 없음"(환불 0%)과 "스냅샷 자체가 없는
  // 옛 문서"(폴백 대상)가 구분된다.
  assert.deepStrictEqual(snapshotRefundPolicy({}), []);
  assert.deepStrictEqual(snapshotRefundPolicy({ refundPolicy: null }), []);
  assert.deepStrictEqual(snapshotRefundPolicy(null), []);
});

test('형식이 깨진 구간은 걸러낸다 — 잘못된 값이 환불 계산에 들어가지 않게', () => {
  const dirty = [
    { daysBefore: 3, refundPercent: 80 },
    { daysBefore: '3', refundPercent: 80 },
    { daysBefore: 1 },
    null,
  ];
  assert.deepStrictEqual(snapshotRefundPolicy({ refundPolicy: dirty }), [
    { daysBefore: 3, refundPercent: 80 },
  ]);
});

test('스냅샷은 파티 문서와 참조를 공유하지 않는다 — 나중 수정이 새어들지 않게', () => {
  const party = { refundPolicy: [{ daysBefore: 3, refundPercent: 80 }] };
  const snap = snapshotRefundPolicy(party);
  party.refundPolicy[0].refundPercent = 0;
  assert.strictEqual(snap[0].refundPercent, 80);
});

// ── 어떤 규정을 적용할지 ─────────────────────────────────────────────────

test('신청 문서에 스냅샷이 있으면 파티의 현재 규정을 무시한다', () => {
  const app = { refundPolicy: POLICY_A };
  const party = { refundPolicy: POLICY_B };
  assert.deepStrictEqual(effectiveRefundPolicy(app, party), POLICY_A);
});

test('스냅샷이 빈 배열이면 그것도 스냅샷이다 — 폴백하지 않는다', () => {
  // 규정 없이 모집했으면 환불 0%가 그 신청의 조건이다. 호스트가 나중에
  // 관대한 규정을 넣었다고 소급 적용하지 않는다.
  assert.deepStrictEqual(effectiveRefundPolicy({ refundPolicy: [] }, { refundPolicy: POLICY_B }), []);
});

test('스냅샷 필드가 없는 옛 문서만 파티의 현재 규정으로 폴백한다', () => {
  assert.deepStrictEqual(effectiveRefundPolicy({}, { refundPolicy: POLICY_B }), POLICY_B);
  assert.strictEqual(effectiveRefundPolicy({}, {}), null);
  assert.strictEqual(effectiveRefundPolicy(null, null), null);
});

// ── 실제 환불 계산까지 이어서 ────────────────────────────────────────────

test('정책 A로 신청 → 호스트가 B로 변경 → 취소는 A 기준', () => {
  const app = { refundPolicy: snapshotRefundPolicy({ refundPolicy: POLICY_A }) };
  const partyNow = { refundPolicy: POLICY_B };
  const r = computeRefund(effectiveRefundPolicy(app, partyNow), FEE, IN_10_DAYS(), {
    paidAmount: FEE,
  });
  assert.strictEqual(r.refundPercent, 80);
  assert.strictEqual(r.refundAmount, 40000);
});

test('변경 후 새로 신청한 사람은 B 기준', () => {
  const app = { refundPolicy: snapshotRefundPolicy({ refundPolicy: POLICY_B }) };
  const r = computeRefund(effectiveRefundPolicy(app, { refundPolicy: POLICY_B }), FEE, IN_10_DAYS(), {
    paidAmount: FEE,
  });
  assert.strictEqual(r.refundPercent, 10);
  assert.strictEqual(r.refundAmount, 5000);
});

test('스냅샷 없는 구버전 신청은 예전처럼 파티의 현재 규정으로 계산된다', () => {
  const legacyApp = { appliedFee: FEE }; // refundPolicy 필드 자체가 없다
  const r = computeRefund(effectiveRefundPolicy(legacyApp, { refundPolicy: POLICY_B }), FEE, IN_10_DAYS(), {
    paidAmount: FEE,
  });
  assert.strictEqual(r.refundPercent, 10);
});

// ── 기존 계산 규칙 회귀 ──────────────────────────────────────────────────

test('무료 파티는 스냅샷과 무관하게 환불 대상이 아니다', () => {
  const r = computeRefund(POLICY_A, 0, IN_10_DAYS(), { paidAmount: 0 });
  assert.strictEqual(r.refundStatus, 'not_applicable');
  assert.strictEqual(r.refundAmount, 0);
});

test('한 푼도 안 낸 신청은 환불 금액이 0이다 — 현장결제/입금대기', () => {
  const r = computeRefund(POLICY_A, FEE, IN_10_DAYS(), { paidAmount: 0 });
  assert.strictEqual(r.refundStatus, 'not_applicable');
  assert.strictEqual(r.refundAmount, 0);
});

test('환불 상한은 실제로 받은 돈이다 — 예약금만 낸 건', () => {
  const r = computeRefund(POLICY_A, FEE, IN_10_DAYS(), { paidAmount: 10000 });
  assert.strictEqual(r.refundPercent, 80); // 명목 비율은 그대로
  assert.strictEqual(r.refundAmount, 10000); // 금액은 실결제액으로 잘린다
});

test('스냅샷이 빈 배열이면 환불 0% — 규정 없이 모집한 파티', () => {
  const r = computeRefund([], FEE, IN_10_DAYS(), { paidAmount: FEE });
  assert.strictEqual(r.refundPercent, 0);
  assert.strictEqual(r.refundAmount, 0);
});

// ── 패키지(숙박+파티) 예약 ───────────────────────────────────────────────

test('패키지 예약 문서의 스냅샷이 신청 문서로 그대로 전달된다', () => {
  const doc = applicationDocOf({ requesterId: 'u1', partyId: 'p1', refundPolicy: POLICY_A }, 'b1');
  assert.deepStrictEqual(doc.refundPolicy, POLICY_A);
});

test('스냅샷 없는 옛 패키지 예약에서 만든 신청 문서에는 필드가 없다 — 폴백 대상', () => {
  const doc = applicationDocOf({ requesterId: 'u1', partyId: 'p1' }, 'b1');
  assert.ok(!('refundPolicy' in doc));
});

test('buildApplicationDoc은 배열일 때만 스냅샷을 담는다', () => {
  const withSnap = buildApplicationDoc({ uid: 'u1', partyId: 'p1', refundPolicy: [] });
  assert.deepStrictEqual(withSnap.refundPolicy, []);
  const without = buildApplicationDoc({ uid: 'u1', partyId: 'p1' });
  assert.ok(!('refundPolicy' in without));
});

test('패키지 취소도 예약 시점 스냅샷을 먼저 본다', () => {
  const group = { refundPolicy: POLICY_A, totalPrice: FEE };
  const partyNow = { refundPolicy: POLICY_B };
  const r = computeRefund(effectiveRefundPolicy(group, partyNow), group.totalPrice, IN_10_DAYS(), {
    paidAmount: FEE,
  });
  assert.strictEqual(r.refundPercent, 80);
});

// ── 호스트 취소 / 최소인원 미달 자동취소 ─────────────────────────────────

test('호스트·시스템 취소 경로는 환불 규정을 아예 보지 않는다 (소스 확인)', () => {
  // 이 경로는 규정과 무관하게 "받은 돈 전액"이라 스냅샷 도입의 영향을 받으면
  // 안 된다. 계산식이 아니라 코드 자체를 확인한다.
  const fs = require('fs');
  const src = fs.readFileSync(require.resolve('./index.js'), 'utf8');
  const marker = "const cancelledBy = after.cancelReason ? 'system' : 'host';";
  const start = src.indexOf(marker);
  assert.ok(start > 0, '호스트 취소 블록을 찾지 못했다');
  const block = src.slice(start, start + 1200);
  assert.ok(!block.includes('refundPolicy'), '호스트 취소 경로가 환불 규정을 참조한다');
  assert.ok(block.includes('refundPercent: paidAmount > 0 ? 100 : 0'), '전액 환불 규칙이 바뀌었다');
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
    ? `\n환불 규정 스냅샷 검증 통과 — ${cases.length}건`
    : `\n실패 ${failed}건 / 전체 ${cases.length}건`,
);
process.exit(failed === 0 ? 0 : 1);

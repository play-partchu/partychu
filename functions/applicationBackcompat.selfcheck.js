// 기존 즉시확정 파티 흐름 무영향 검증 — `npm run check:backcompat`.
//
// 승인제·사전질문을 얹으면서 **가장 위험한 것은 새 기능이 아니라 기존 파티**다.
// 운영 중인 파티에는 applicationApprovalMode 필드가 아예 없으므로, 그 문서들이
// 조금이라도 다르게 읽히면 지금 신청을 받고 있는 파티 전체가 한꺼번에 망가진다.
//
// 그래서 여기서는 "새 기능이 동작하는가"가 아니라 **"옛 문서가 예전과 똑같이
// 읽히는가"** 만 못 박는다.

process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'selfcheck';

const assert = require('assert');
const aq = require('./applicationQuestions');
const { buildPaymentInfo } = require('./paymentInfo');

const cases = [];
const test = (name, fn) => cases.push([name, fn]);

/// 실제 운영 중인 파티 문서 모양(사전질문 도입 전).
const LEGACY_PARTY = {
  title: '금요일 와인 파티',
  hostId: 'host_uid',
  recruitStatus: '모집중',
  maleFee: 30000,
  femaleFee: 25000,
  maxCapacity: 20,
  applicants: ['a', 'b'],
  refundPolicy: [{ daysBefore: 3, refundPercent: 50 }],
};

// ── 읽기 ─────────────────────────────────────────────────────────────────────

test('옛 파티는 승인이 필요 없다', () => {
  assert.strictEqual(aq.requiresApproval(LEGACY_PARTY), false);
  assert.strictEqual(aq.approvalModeOf(LEGACY_PARTY), 'auto');
});

test('옛 파티에는 사전질문이 없다', () => {
  assert.deepStrictEqual(aq.questionsOf(LEGACY_PARTY), []);
});

test('옛 파티는 답변 검증 자체를 건너뛴다 — 신청이 막히면 안 된다', () => {
  const r = aq.validateAnswers(aq.questionsOf(LEGACY_PARTY), null);
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.answers, null);
  assert.strictEqual(r.snapshot, null);
});

test('옛 파티에 답변이 딸려와도 저장되지 않는다', () => {
  // 구버전/조작된 클라이언트가 answers를 실어 보내는 경우.
  const r = aq.validateAnswers(aq.questionsOf(LEGACY_PARTY), { q1: '몰래 넣기' });
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.answers, null, '즉시확정 파티에 답변이 저장되면 안 된다');
});

test('옛 파티에 사진이 딸려와도 저장되지 않는다', () => {
  // applyToParty는 requireApproval이 false면 validatePhotos를 아예 부르지 않고
  // photos: null로 굳힌다 — 그 분기를 그대로 재현한다.
  const requireApproval = aq.requiresApproval(LEGACY_PARTY);
  const photoResult = requireApproval
    ? aq.validatePhotos([{ id: 'p1' }])
    : { ok: true, photos: null };
  assert.strictEqual(photoResult.photos, null);
});

// ── 신청 상태 ────────────────────────────────────────────────────────────────

test("옛 파티의 신청 상태는 예전 그대로 'applied'다", () => {
  const status = aq.requiresApproval(LEGACY_PARTY) ? 'pending' : 'applied';
  assert.strictEqual(status, 'applied');
});

test("승인제 파티만 'pending'으로 시작한다", () => {
  const manual = { ...LEGACY_PARTY, applicationApprovalMode: 'manual' };
  const status = aq.requiresApproval(manual) ? 'pending' : 'applied';
  assert.strictEqual(status, 'pending');
});

// ── 결제 ─────────────────────────────────────────────────────────────────────
//
// 무통장입금은 이제 **호스트의 인증된 수취계좌**가 있어야 성립한다
// (payoutAccounts.js). 옛 파티라고 예외를 두지는 않는다 — 계좌 없이 안내할
// 계좌가 애초에 없기 때문이다. 여기서 보는 것은 그 계좌가 있을 때의 상태
// 전이가 예전과 같은가다.
const HOST_ACCOUNT = {
  bankName: '국민은행',
  accountNumber: '12345678901234',
  accountHolder: '홍길동',
};

test('옛 파티의 무통장입금은 예전처럼 바로 입금대기다', () => {
  const info = buildPaymentInfo(
    { method: 'bank_transfer', depositorName: '홍길동' },
    {
      amount: 30000,
      nowMs: 1_700_000_000_000,
      requireApproval: aq.requiresApproval(LEGACY_PARTY),
      payoutAccount: HOST_ACCOUNT,
    },
  );
  assert.strictEqual(info.status, 'awaiting_deposit');
  assert.ok(info.depositDeadlineMs > 0, '입금기한이 바로 시작돼야 한다');
});

test('승인제 파티의 무통장입금만 승인대기로 시작한다', () => {
  const manual = { ...LEGACY_PARTY, applicationApprovalMode: 'manual' };
  const info = buildPaymentInfo(
    { method: 'bank_transfer', depositorName: '홍길동' },
    {
      amount: 30000,
      nowMs: 1_700_000_000_000,
      requireApproval: aq.requiresApproval(manual),
      payoutAccount: HOST_ACCOUNT,
    },
  );
  assert.strictEqual(info.status, 'awaiting_approval');
  assert.strictEqual(
    info.depositDeadlineMs,
    undefined,
    '승인 전에는 입금기한이 시작되면 안 된다',
  );
});

test('현장결제는 승인 방식과 무관하게 예전 그대로다', () => {
  for (const party of [LEGACY_PARTY, { ...LEGACY_PARTY, applicationApprovalMode: 'manual' }]) {
    const info = buildPaymentInfo(
      { method: 'on_site' },
      { amount: 30000, nowMs: 1_700_000_000_000, requireApproval: aq.requiresApproval(party) },
    );
    assert.strictEqual(info.status, 'on_site_scheduled');
  }
});

test('무료 파티는 결제 정보 자체가 없다 — 예전 그대로', () => {
  const info = buildPaymentInfo(null, { amount: 0, requireApproval: false });
  assert.strictEqual(info, null);
});

// ── 되돌리기 ─────────────────────────────────────────────────────────────────

test('승인제를 껐다가 되돌리면 질문이 노출되지 않는다', () => {
  const reverted = {
    ...LEGACY_PARTY,
    applicationApprovalMode: 'auto',
    applicationQuestions: [{ id: 'q1', text: '참여 이유', required: true, order: 0 }],
  };
  assert.deepStrictEqual(aq.questionsOf(reverted), []);
  assert.strictEqual(aq.requiresApproval(reverted), false);
});

test('오타 난 승인 방식은 즉시확정으로 떨어진다 — 파티가 잠기면 안 된다', () => {
  for (const bad of ['MANUAL', 'approval', '승인제', '', null, undefined, 123]) {
    const party = { ...LEGACY_PARTY, applicationApprovalMode: bad };
    assert.strictEqual(aq.requiresApproval(party), false, `실패한 값: ${bad}`);
  }
});

// ── 진행 중 신청 판정 ────────────────────────────────────────────────────────

test("탈퇴 차단·삭제 차단 목록이 'pending'을 포함하고 서로 같다", () => {
  // 두 파일이 갈라지면 탈퇴는 막히는데 파티는 지워지는 식으로 어긋난다.
  const withdrawal = require('fs')
    .readFileSync(`${__dirname}/accountWithdrawal.js`, 'utf8')
    .match(/const LIVE_APPLICATION_STATUSES = (\[[^\]]*\])/)[1];
  const cleanup = require('fs')
    .readFileSync(`${__dirname}/contentCleanup.js`, 'utf8')
    .match(/const LIVE_APPLICATION_STATUSES = (\[[^\]]*\])/)[1];
  assert.strictEqual(withdrawal, cleanup, '두 목록이 달라졌다');
  assert.ok(withdrawal.includes('pending'), "'pending'이 빠졌다");
  assert.ok(withdrawal.includes('applied'), "기존 'applied'가 사라졌다");
  assert.ok(withdrawal.includes('approved'), "기존 'approved'가 사라졌다");
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
    ? `\n기존 파티 흐름 무영향 검증 통과 — ${cases.length}건`
    : `\n실패 ${failed}건 / 전체 ${cases.length}건`,
);
process.exit(failed === 0 ? 0 : 1);

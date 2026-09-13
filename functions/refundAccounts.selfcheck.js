// 참가자 환불계좌 규칙 자체 검증 — `npm run check:refund`.
//
// 여기서 못 박는 것은 두 가지다.
// 1. **언제 계좌를 묻는가.** 필요 없는 건에까지 계좌를 요구하면 취소가 막히고,
//    필요한 건에 안 물으면 돈을 돌려줄 곳을 모른 채 신청만 사라진다.
// 2. **계좌 스냅샷.** 환불 요청에는 요청 당시 계좌가 박혀야 한다 — 사용자가
//    나중에 마이페이지에서 계좌를 바꿔도 접수된 건이 따라 바뀌면 안 된다.

const assert = require('assert');
const {
  COMPLETION_METHOD,
  OVERDUE_MS,
  isOverdue,
  requiresRefundAccount,
  normalizeRefundAccount,
  buildRefundRequest,
  REFUND_REQUEST_STATUS,
} = require('./refundAccounts');

const cases = [];
const test = (name, fn) => cases.push([name, fn]);

const PAID_BANK = { method: 'bank_transfer', status: 'paid' };

// ── 언제 계좌를 묻는가 ───────────────────────────────────────────────────────

test('무통장입금 + 입금완료 + 환불액 있음 → 계좌를 묻는다', () => {
  assert.strictEqual(requiresRefundAccount(PAID_BANK, 20000), true);
});

test('현장결제는 현장에서 돌려주므로 묻지 않는다', () => {
  assert.strictEqual(
    requiresRefundAccount({ method: 'on_site', status: 'paid' }, 20000),
    false,
  );
});

test('입금 전(입금대기·승인대기·입금확인중)은 받은 돈이 없어 묻지 않는다', () => {
  for (const status of ['awaiting_deposit', 'awaiting_approval', 'deposit_pending']) {
    assert.strictEqual(
      requiresRefundAccount({ method: 'bank_transfer', status }, 20000),
      false,
      `${status}에서 계좌를 요구했다`,
    );
  }
});

test('환불액이 0이면 묻지 않는다(규정상 0% 환불 포함)', () => {
  assert.strictEqual(requiresRefundAccount(PAID_BANK, 0), false);
  assert.strictEqual(requiresRefundAccount(PAID_BANK, -1), false);
});

test('무료 신청(payment 자체가 없음)은 묻지 않는다', () => {
  assert.strictEqual(requiresRefundAccount(null, 0), false);
  assert.strictEqual(requiresRefundAccount(undefined, 10000), false);
});

// ── 계좌 정규화 ──────────────────────────────────────────────────────────────

test('계좌번호는 숫자만 남는다 — 하이픈 유무로 같은 계좌가 갈리지 않게', () => {
  const a = normalizeRefundAccount({
    bankName: ' 카카오뱅크 ',
    accountNumber: '3333-01-2345678',
    accountHolder: ' 홍길동 ',
  });
  assert.deepStrictEqual(a, {
    bankName: '카카오뱅크',
    accountNumber: '3333012345678',
    accountHolder: '홍길동',
  });
});

test('셋 중 하나라도 비면 계좌로 인정하지 않는다', () => {
  assert.strictEqual(normalizeRefundAccount({ bankName: '국민', accountNumber: '1', accountHolder: '' }), null);
  assert.strictEqual(normalizeRefundAccount({ bankName: '', accountNumber: '1', accountHolder: '홍' }), null);
  assert.strictEqual(normalizeRefundAccount({ bankName: '국민', accountNumber: '---', accountHolder: '홍' }), null);
  assert.strictEqual(normalizeRefundAccount(null), null);
  assert.strictEqual(normalizeRefundAccount('국민 123'), null);
});

// ── 스냅샷 ───────────────────────────────────────────────────────────────────

test('환불 요청은 접수 상태로 시작하고 금액을 그대로 담는다', () => {
  const req = buildRefundRequest({
    requesterId: 'u1', domain: 'party', refId: 'p1',
    applicationPath: 'parties/p1/applications/u1',
    refundAmount: 18000,
    account: { bankName: '국민', accountNumber: '123', accountHolder: '홍' },
  });
  assert.strictEqual(req.status, REFUND_REQUEST_STATUS.requested);
  assert.strictEqual(req.refundAmount, 18000);
  assert.strictEqual(req.requesterId, 'u1');
  assert.strictEqual(req.applicationPath, 'parties/p1/applications/u1');
});

test('계좌는 **사본**으로 박힌다 — 원본을 나중에 고쳐도 요청은 안 바뀐다', () => {
  const account = { bankName: '국민', accountNumber: '123', accountHolder: '홍' };
  const req = buildRefundRequest({
    requesterId: 'u1', domain: 'party', refId: 'p1',
    applicationPath: 'parties/p1/applications/u1',
    refundAmount: 1000, account,
  });
  // 사용자가 마이페이지에서 환불계좌를 바꾼 상황을 흉내낸다.
  account.bankName = '신한';
  account.accountNumber = '999';
  assert.strictEqual(req.account.bankName, '국민', '요청의 은행이 따라 바뀌었다');
  assert.strictEqual(req.account.accountNumber, '123', '요청의 계좌번호가 따라 바뀌었다');
});

// ── 장기 미처리 판정 ────────────────────────────────────────────────────────
// 호스트가 방치하면 참가자는 돈을 못 받는다. 재촉 알림과 관리자 개입이 모두
// 이 판정 하나를 보므로, 기준이 갈리지 않게 여기서 잠근다.
{
  const NOW = 1_700_000_000_000;
  const req = (createdMs, status = 'requested') => ({ status, createdAt: createdMs });

  assert.strictEqual(isOverdue(req(NOW - OVERDUE_MS), NOW), true, '3일이 지나면 미처리');
  assert.strictEqual(isOverdue(req(NOW - OVERDUE_MS + 1000), NOW), false, '아직 3일 전');
  assert.strictEqual(
    isOverdue(req(NOW - OVERDUE_MS, 'completed'), NOW),
    false,
    '이미 처리된 건은 재촉 대상이 아니다',
  );
  assert.strictEqual(
    isOverdue(req(NOW - OVERDUE_MS, 'rejected'), NOW),
    false,
    '반려된 건도 아니다',
  );
  assert.strictEqual(isOverdue({ status: 'requested' }, NOW), false, '접수 시각이 없으면 판단하지 않는다');
  assert.strictEqual(isOverdue(null, NOW), false);

  // Firestore Timestamp처럼 toMillis()를 가진 값도 그대로 읽는다.
  assert.strictEqual(
    isOverdue({ status: 'requested', createdAt: { toMillis: () => NOW - OVERDUE_MS } }, NOW),
    true,
  );

  // 완료는 '자동 송금'이 아니라 **사람이 보냈다고 표시한 것**이다.
  assert.deepStrictEqual(Object.keys(COMPLETION_METHOD), ['markedManually']);
  assert.strictEqual(COMPLETION_METHOD.markedManually, 'marked_manually');
  console.log('  ✓ 장기 미처리 판정과 완료 표기 의미');
}

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
    ? `\n참가자 환불계좌 규칙 검증 통과 — ${cases.length}건`
    : `\n실패 ${failed}건 / 전체 ${cases.length}건`,
);
process.exit(failed === 0 ? 0 : 1);

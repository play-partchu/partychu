// 호스트 수취계좌 규칙 자체 점검 — `npm run check:payout`
//
// Firestore도 팝빌도 부르지 않는 **순수 판정만** 본다. 이 기능에서 사고가 나는
// 자리는 정확히 셋이다.
//   1. 인증되지 않은 계좌가 참가자에게 안내되는 것
//   2. 인증받은 뒤 계좌를 바꿔치기했는데 '인증 완료'가 남는 것
//   3. 계좌번호가 로그로 새는 것
// 셋 다 여기서 잠근다.

const assert = require('assert');

const {
  STATUS,
  FAIL_REASON,
  digitsOnly,
  maskAccountNumber,
  holderMatches,
  accountFingerprint,
  normalizePayoutAccount,
  statusOf,
  decideVerification,
  paymentSnapshotOf,
  assertBankTransferPayable,
} = require('./payoutAccounts');

const popbill = require('./popbill');

// ── 정규화 ────────────────────────────────────────────────────────────────
assert.deepStrictEqual(
  normalizePayoutAccount({
    bankCode: '004',
    accountNumber: '123456-78-901234',
    accountHolder: ' 홍길동 ',
  }),
  {
    bankCode: '004',
    bankName: '국민은행',
    accountNumber: '12345678901234',
    accountHolder: '홍길동',
  },
  '계좌번호는 숫자만, 은행명은 코드표에서, 예금주는 trim',
);

// 하나라도 비면 등록으로 치지 않는다.
assert.strictEqual(normalizePayoutAccount(null), null);
assert.strictEqual(
  normalizePayoutAccount({ bankCode: '004', accountNumber: '123' }),
  null,
  '예금주명이 없으면 계좌가 아니다',
);
assert.strictEqual(
  normalizePayoutAccount({
    bankCode: '',
    accountNumber: '123',
    accountHolder: '홍길동',
  }),
  null,
  '은행을 고르지 않으면 계좌가 아니다',
);
assert.strictEqual(
  normalizePayoutAccount({
    bankCode: '004',
    accountNumber: '---',
    accountHolder: '홍길동',
  }),
  null,
  '숫자가 하나도 없는 계좌번호는 계좌가 아니다',
);

// ── 마스킹 ────────────────────────────────────────────────────────────────
assert.strictEqual(maskAccountNumber('123456-78-901234'), '**********1234');
assert.strictEqual(maskAccountNumber('123'), '***', '짧아도 원문을 남기지 않는다');
assert.strictEqual(maskAccountNumber(''), '');
// 마스킹 결과에 원문 앞자리가 남으면 안 된다.
assert.ok(
  !maskAccountNumber('123456789').includes('12345'),
  '마스킹이 앞자리를 흘리면 안 된다',
);
assert.strictEqual(digitsOnly('12-34'), '1234');

// ── 예금주명 대조 ─────────────────────────────────────────────────────────
assert.ok(holderMatches('홍 길동', '홍길동'), '공백만 다른 이름은 같은 사람');
assert.ok(!holderMatches('홍길동', '홍길순'));
assert.ok(!holderMatches('', ''), '빈 이름끼리는 일치로 보지 않는다');

// ── 상태 판정 ─────────────────────────────────────────────────────────────
const account = {
  bankCode: '004',
  bankName: '국민은행',
  accountNumber: '12345678901234',
  accountHolder: '홍길동',
};
const fingerprint = accountFingerprint(account.bankCode, account.accountNumber);

assert.strictEqual(statusOf({}), STATUS.none, '계좌가 없으면 미등록');
assert.strictEqual(
  statusOf({ payoutAccount: account }),
  STATUS.required,
  '계좌만 있고 인증 기록이 없으면 인증 필요',
);
assert.strictEqual(
  statusOf({
    payoutAccount: account,
    payoutAccountVerification: { status: STATUS.verified, accountFingerprint: fingerprint },
  }),
  STATUS.verified,
);

// ★ 인증받은 뒤 계좌를 바꿔치기하면 인증이 풀린다.
assert.strictEqual(
  statusOf({
    payoutAccount: { ...account, accountNumber: '99999999999999' },
    payoutAccountVerification: { status: STATUS.verified, accountFingerprint: fingerprint },
  }),
  STATUS.required,
  '계좌를 바꾸면 예전 인증 기록이 따라오면 안 된다',
);

// 클라이언트가 상태만 위조해도(규칙이 막지만) 지문이 없으면 인증이 아니다.
assert.strictEqual(
  statusOf({
    payoutAccount: account,
    payoutAccountVerification: { status: STATUS.verified },
  }),
  STATUS.required,
  '지문 없는 verified는 인증으로 치지 않는다',
);

// ── 참가자에게 나가는 스냅샷 ──────────────────────────────────────────────
assert.strictEqual(
  paymentSnapshotOf({ payoutAccount: account }),
  null,
  '미인증 계좌는 절대 안내되지 않는다',
);
assert.deepStrictEqual(
  paymentSnapshotOf({
    payoutAccount: account,
    payoutAccountVerification: { status: STATUS.verified, accountFingerprint: fingerprint },
  }),
  {
    bankName: '국민은행',
    accountNumber: '12345678901234',
    accountHolder: '홍길동',
  },
  '스냅샷에는 은행·계좌번호·예금주만 담는다(지문·상태는 빼고)',
);

// ── 무통장입금 게이팅 ─────────────────────────────────────────────────────
assert.throws(
  () => assertBankTransferPayable('bank_transfer', null),
  /무통장입금/,
  '인증 계좌가 없으면 무통장입금은 거절된다',
);
assert.doesNotThrow(
  () => assertBankTransferPayable('on_site', null),
  '현장결제는 수취계좌와 무관하다',
);
assert.doesNotThrow(() =>
  assertBankTransferPayable('bank_transfer', {
    bankName: '국민은행',
    accountNumber: '12345678901234',
    accountHolder: '홍길동',
  }),
);

// ── 실패 사유 표 ──────────────────────────────────────────────────────────
// 앱(PayoutAccountFailReason)과 키가 1:1이어야 문구가 갈리지 않는다.
assert.deepStrictEqual(Object.keys(FAIL_REASON).sort(), [
  'accountNotFound',
  'apiUnavailable',
  'holderMismatch',
  'identityMismatch',
  'notConfigured',
]);

// ── 예금주조회 판정 다섯 갈래 ─────────────────────────────────────────────
//
// 팝빌을 부르지 않는다. 조회 결과(성명 문자열)나 조회 실패(오류 객체)를
// 그대로 넣어 **어떤 상태로 떨어지는지**만 본다 — 이 판정이 곧 참가자 돈이
// 어느 계좌로 나가는지를 정한다.

// ① 성공 — 은행이 준 성명 == 입력 예금주명 == 본인확인 실명
assert.deepStrictEqual(
  decideVerification({
    holderName: '홍길동',
    accountHolder: '홍길동',
    realName: '홍길동',
  }),
  { status: STATUS.verified, verifiedHolderName: '홍길동' },
);

// 은행이 '홍 길동'처럼 공백을 끼워 주는 경우도 같은 사람으로 본다.
assert.strictEqual(
  decideVerification({
    holderName: '홍 길동',
    accountHolder: '홍길동',
    realName: '홍길동',
  }).status,
  STATUS.verified,
);

// 본인확인 전(실명 없음)에도 계좌 등록·인증 자체는 된다.
assert.strictEqual(
  decideVerification({ holderName: '홍길동', accountHolder: '홍길동', realName: '' })
    .status,
  STATUS.verified,
);

// ② 조회실패(계좌 없음) — 성명을 못 받으면 대조할 것이 없다.
for (const empty of ['', '   ', null, undefined]) {
  assert.deepStrictEqual(
    decideVerification({
      holderName: empty,
      accountHolder: '홍길동',
      realName: '홍길동',
    }),
    { status: STATUS.required, failReason: FAIL_REASON.accountNotFound },
    '성명이 없으면 인증되지 않는다',
  );
}

// ③ 예금주 불일치 — 입력한 이름이 은행 기록과 다르다.
assert.deepStrictEqual(
  decideVerification({
    holderName: '홍길동',
    accountHolder: '김철수',
    realName: '홍길동',
  }),
  { status: STATUS.required, failReason: FAIL_REASON.holderMismatch },
);

// ④ 본인확인 실명 불일치 — 남의 계좌를 자기 이름처럼 등록하는 경로를 막는다.
assert.deepStrictEqual(
  decideVerification({
    holderName: '김철수',
    accountHolder: '김철수',
    realName: '홍길동',
  }),
  { status: STATUS.required, failReason: FAIL_REASON.identityMismatch },
);

// 어느 갈래로 떨어지든 **verified가 아니면 인증되지 않는다**(fail-closed).
for (const d of [
  decideVerification({ holderName: '', accountHolder: '홍길동', realName: '' }),
  decideVerification({ holderName: '홍길동', accountHolder: '김철수', realName: '' }),
  decideVerification({
    holderName: '김철수',
    accountHolder: '김철수',
    realName: '홍길동',
  }),
]) {
  assert.notStrictEqual(d.status, STATUS.verified);
  assert.ok(d.failReason, '실패에는 반드시 사유가 붙는다');
}

// ⑤ 팝빌 장애·미연결 — 조회 자체가 실패한 경우의 사유 매핑.
assert.strictEqual(
  popbill.failReasonOf(
    new popbill.PopbillError(popbill.NOT_CONFIGURED),
    FAIL_REASON,
  ),
  FAIL_REASON.notConfigured,
);
assert.strictEqual(
  popbill.failReasonOf(
    new popbill.PopbillError(popbill.ACCOUNT_NOT_FOUND),
    FAIL_REASON,
  ),
  FAIL_REASON.accountNotFound,
);
assert.strictEqual(
  popbill.failReasonOf(new popbill.PopbillError(popbill.UNAVAILABLE), FAIL_REASON),
  FAIL_REASON.apiUnavailable,
);
// 모르는 오류도 통과가 아니라 '일시 장애'로 떨어진다.
assert.strictEqual(
  popbill.failReasonOf(new Error('boom'), FAIL_REASON),
  FAIL_REASON.apiUnavailable,
);

// SDK 입력 검증 실패(-99999999)는 '조회 불가한 계좌'로, 나머지는 일시 장애로.
assert.strictEqual(
  popbill.classify({ code: -99999999, message: '기관코드가 올바르지 않습니다.' }),
  popbill.ACCOUNT_NOT_FOUND,
);
assert.strictEqual(popbill.classify({ code: -10000 }), popbill.UNAVAILABLE);
assert.strictEqual(popbill.classify(new Error('network')), popbill.UNAVAILABLE);

// ── 팝빌 어댑터 ──────────────────────────────────────────────────────────

// 운영 전환은 상수 하나로 갈린다 — 검증이 끝나기 전에는 반드시 테스트 환경.
assert.strictEqual(popbill.IS_TEST, true, '아직 운영 전환 전이다');

// 키가 없으면 '설정됨'이 될 수 없다(fail-closed의 출발점).
assert.ok(!popbill.isConfigured({ linkId: '', secretKey: '', corpNum: '' }));
assert.ok(
  !popbill.isConfigured({
    linkId: 'TEST_MODE',
    secretKey: 'TEST_MODE',
    corpNum: 'TEST_MODE',
  }),
  '자리표시자는 설정된 것으로 치지 않는다',
);
assert.ok(
  popbill.isConfigured({ linkId: 'a', secretKey: 'b', corpNum: '1234567890' }),
);

// 저장은 3자리, 팝빌은 4자리 — 우리 은행 표 전체가 변환된다.
const { BANK_NAMES } = require('./payoutAccounts');
for (const code of Object.keys(BANK_NAMES)) {
  const converted = popbill.toPopbillBankCode(code);
  assert.strictEqual(
    converted.length,
    4,
    `기관코드 변환 실패: ${code} -> ${converted}`,
  );
}
assert.strictEqual(popbill.toPopbillBankCode('004'), '0004');
assert.strictEqual(popbill.toPopbillBankCode('090'), '0090');
assert.strictEqual(popbill.toPopbillBankCode(''), '', '빈 값은 조회하지 않는다');
assert.strictEqual(popbill.toPopbillBankCode('12345'), '', '4자리를 넘으면 거절');

// 응답에서 성명 읽기.
assert.strictEqual(popbill.holderNameOf({ accountName: ' 홍길동 ' }), '홍길동');
assert.strictEqual(popbill.holderNameOf({ accountName: '' }), '');
assert.strictEqual(popbill.holderNameOf(null), '');

// 조회 실패는 **예외가 아니라 200 응답**으로 온다(2026-08-24 테스트 환경에서
// 확인한 실제 모양). 성명 자리가 비고 결과 코드가 실려 온다 — 이걸 '형식
// 변경'으로 오해하면 없는 계좌가 '일시 장애'로 안내된다.
const notFoundResponse = {
  bankCode: '0004',
  // 판정에 쓰이지 않는 자리다. 실제 조회에 넣은 값은 여기 적지 않는다 —
  // 계좌번호는 테스트 픽스처에도 남기지 않는 것이 이 파일의 규칙이다.
  accountNumber: '',
  accountName: '',
  checkDate: '',
  result: '',
  resultCode: '',
  resultMessage: '',
  checkDT: '',
};
assert.strictEqual(popbill.holderNameOf(notFoundResponse), '');
assert.ok(
  popbill.looksLikePopbillResult(notFoundResponse),
  '결과 코드가 실려 있으면 팝빌이 형식을 갖춰 답한 것이다',
);
// 결과 코드조차 없으면 형식이 달라졌다는 신호 — 일시 장애로 올린다.
assert.ok(!popbill.looksLikePopbillResult({ foo: 1 }));
assert.ok(!popbill.looksLikePopbillResult(null));
// 성공 응답은 성명이 있으므로 결과 코드 판단까지 가지 않는다.
assert.strictEqual(
  popbill.holderNameOf({ ...notFoundResponse, accountName: '홍길동' }),
  '홍길동',
);

// 성명 없는 응답을 '계좌 문제'와 '서비스 문제'로 가른다.
// 2026-08-24 테스트 환경 실측: result=400 resultCode=S054
// (금융기관으로부터 거래가 제한된 계좌번호) — 계좌 문제로 안내해야 맞다.
assert.strictEqual(
  popbill.resultKindOf({ result: 400, resultCode: 'S054' }),
  popbill.ACCOUNT_NOT_FOUND,
);
assert.strictEqual(
  popbill.resultKindOf({ result: '400', resultCode: 'S054' }),
  popbill.ACCOUNT_NOT_FOUND,
  '문자열로 와도 같게 읽는다',
);
assert.strictEqual(
  popbill.resultKindOf({ result: 500 }),
  popbill.UNAVAILABLE,
  '서비스 쪽 사정은 일시 장애로',
);
assert.strictEqual(
  popbill.resultKindOf({ resultCode: 'S054' }),
  popbill.ACCOUNT_NOT_FOUND,
  '숫자를 못 읽으면 확인 실패 쪽으로 둔다',
);

console.log('payoutAccounts.selfcheck: OK');

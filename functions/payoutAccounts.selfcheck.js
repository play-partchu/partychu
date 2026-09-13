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
  ACCOUNT_TYPE,
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
    // 이 필드가 없던 기존 문서는 개인 계좌로 읽힌다(하위호환).
    accountType: ACCOUNT_TYPE.personal,
  },
  '계좌번호는 숫자만, 은행명은 코드표에서, 예금주는 trim',
);

// 사업자 명의는 **명시적으로 고른 경우에만** 잡힌다 — 모르는 값은 개인.
assert.strictEqual(
  normalizePayoutAccount({
    bankCode: '004',
    accountNumber: '12345678901234',
    accountHolder: '홍길동',
    accountType: 'business',
  }).accountType,
  ACCOUNT_TYPE.business,
);
assert.strictEqual(
  normalizePayoutAccount({
    bankCode: '004',
    accountNumber: '12345678901234',
    accountHolder: '홍길동',
    accountType: '아무거나',
  }).accountType,
  ACCOUNT_TYPE.personal,
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
const fingerprint = accountFingerprint(account);

// ── 계좌를 고치면 인증이 풀린다 ───────────────────────────────────────────
// 은행·계좌번호뿐 아니라 **예금주와 명의 유형**까지 지문에 들어간다.
// 넷 중 하나만 바뀌어도 지문이 달라져 statusOf가 '인증 필요'로 떨어진다.
for (const changed of [
  { ...account, bankCode: '088' },
  { ...account, accountNumber: '99999999999999' },
  { ...account, accountHolder: '김철수' },
  { ...account, accountType: ACCOUNT_TYPE.business },
]) {
  assert.notStrictEqual(
    accountFingerprint(changed),
    fingerprint,
    '계좌 구성이 바뀌면 지문도 바뀌어야 한다',
  );
}
// 공백만 다른 예금주는 같은 계좌다(대조 규칙과 같은 정규화).
assert.strictEqual(
  accountFingerprint({ ...account, accountHolder: '홍 길동' }),
  fingerprint,
);

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
  'businessHolderMismatch',
  'businessNotVerified',
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

// 링크허브 인증·연동 오류(-990100xx)는 **재시도로 풀리지 않는 설정 문제**다.
// 2026-08-30 운영에서 실제로 받은 -99010016이 여기 해당한다(테스트베드 키로
// 운영 엔드포인트를 부른 경우). 일시 장애로 분류하면 앱이 "잠시 후 다시
// 시도해주세요"만 반복해, 사용자가 멀쩡한 자기 계좌를 계속 다시 치게 된다.
assert.strictEqual(
  popbill.classify({ code: -99010016 }),
  popbill.NOT_CONFIGURED,
);
assert.strictEqual(
  popbill.classify({ code: -99010001 }),
  popbill.NOT_CONFIGURED,
);
assert.strictEqual(
  popbill.failReasonOf(
    new popbill.PopbillError(popbill.classify({ code: -99010016 })),
    FAIL_REASON,
  ),
  FAIL_REASON.notConfigured,
);
// 경계 밖은 그대로 일시 장애다 — 범위를 넓히지 않는다.
assert.strictEqual(popbill.classify({ code: -99011000 }), popbill.UNAVAILABLE);
assert.strictEqual(popbill.classify({ code: -99009999 }), popbill.UNAVAILABLE);

// ── 팝빌 어댑터 ──────────────────────────────────────────────────────────

// ── 팝빌 환경 판정 ───────────────────────────────────────────────────────
//
// 예전에는 `IS_TEST === true`를 못박아 두고 "아직 운영 전환 전"을 확인했다.
// 이제 환경은 상수가 아니라 [resolvePopbillEnv]가 정하므로, 검증 대상도
// **값이 아니라 규칙**이다. 핵심은 하나 — **정해지지 않았을 때 test로
// 흘러가지 않는다.**
//
// env를 인자로 주입하므로 이 self-check는 실행 환경(운영/로컬)과 무관하게
// 같은 결과를 낸다 — 운영 전환 때문에 테스트가 깨지지 않는다.
assert.strictEqual(
  popbill.resolvePopbillEnv({ POPBILL_ENV: 'production' }),
  'production',
  '명시적 production은 그대로 따른다',
);
assert.strictEqual(
  popbill.resolvePopbillEnv({ POPBILL_ENV: 'test' }),
  'test',
  '명시적 test는 그대로 따른다 — 테스트가 환경을 주입하는 통로다',
);
assert.strictEqual(
  popbill.resolvePopbillEnv({ POPBILL_ENV: '  PRODUCTION  ' }),
  'production',
  '공백·대소문자는 정규화한다',
);
assert.strictEqual(
  popbill.resolvePopbillEnv({}),
  null,
  '아무것도 없으면 정하지 않는다 — 절대 test로 떨어지지 않는다',
);
assert.strictEqual(
  popbill.resolvePopbillEnv({ POPBILL_ENV: 'staging' }),
  null,
  '모르는 값은 추측하지 않는다',
);
assert.strictEqual(
  popbill.resolvePopbillEnv({ GCLOUD_PROJECT: 'partychu-30c24' }),
  'production',
  '운영 프로젝트에 배포되면 설정이 없어도 운영 엔드포인트다',
);
assert.strictEqual(
  popbill.resolvePopbillEnv({ GCLOUD_PROJECT: 'some-other-project' }),
  null,
  '모르는 프로젝트는 정하지 않는다',
);
// 운영 프로젝트라도 명시 설정이 이긴다 — 운영 프로젝트에서 테스트 조회를
// 돌려 봐야 하는 경우가 있고, 그때도 '조용히'가 아니라 '명시적으로'다.
assert.strictEqual(
  popbill.resolvePopbillEnv({
    POPBILL_ENV: 'test',
    GCLOUD_PROJECT: 'partychu-30c24',
  }),
  'test',
);
// SDK에 넘어가는 IsTest — production이면 반드시 false다.
assert.strictEqual(popbill.isTestEnv('production'), false);
assert.strictEqual(popbill.isTestEnv('test'), true);
assert.strictEqual(popbill.isTestEnv(null), false, 'null도 test가 아니다');

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

// ── 사업자·법인 명의 계좌 ────────────────────────────────────────────────
//
// 핵심은 "상호명으로는 통과할 수 없다"는 것이다. 상호는 국세청에 보내지
// 않는 자기 신고값이라, 그걸 기준으로 삼으면 남의 계좌를 통과시킬 수 있다.
//
// 그리고 사업자 '권한'이 먼저다 — status(진위)만 있고 authorization(권한)이
// 없는 계정은 사업자 명의 계좌 자체를 쓸 수 없다. 이 계좌는 참가자가 실제로
// 돈을 보내는 곳이라, 남의 사업자로 대표자 확인을 기다리는 계정이 그 대표자
// 명의 계좌를 안내 계좌로 올릴 수 있으면 안 된다.
const bizVerified = {
  status: 'verified',
  authorization: 'self', // 권한 축 — 이것까지 있어야 사업자 계좌를 쓴다
  representativeName: '홍길동', // 국세청이 검증한 값
  businessName: '파티츄', // 자기 신고값 — 대조에 쓰지 않는다
};

// 예금주가 검증된 대표자명과 같으면 통과한다(본인확인 실명은 보지 않는다 —
// 대표자 본인이라는 사실은 사업자 인증이 이미 보장한다).
assert.deepStrictEqual(
  decideVerification({
    holderName: '홍길동',
    accountHolder: '홍길동',
    realName: '',
    accountType: ACCOUNT_TYPE.business,
    business: bizVerified,
  }),
  { status: STATUS.verified, verifiedHolderName: '홍길동' },
);

// 상호명은 대조 기준이 아니다 — 예금주가 상호로 오면 아직 통과시키지 않는다.
assert.deepStrictEqual(
  decideVerification({
    holderName: '파티츄',
    accountHolder: '파티츄',
    realName: '홍길동',
    accountType: ACCOUNT_TYPE.business,
    business: bizVerified,
  }),
  { status: STATUS.required, failReason: FAIL_REASON.businessHolderMismatch },
  '상호명 일치만으로는 통과할 수 없다',
);

// 남의 상호를 적어 넣어도 통과하지 않는다(자기 신고값 위조 경로 차단).
assert.strictEqual(
  decideVerification({
    holderName: '김철수',
    accountHolder: '김철수',
    realName: '홍길동',
    accountType: ACCOUNT_TYPE.business,
    business: { ...bizVerified, businessName: '김철수' },
  }).failReason,
  FAIL_REASON.businessHolderMismatch,
);

// 부분 일치로 통과하지 않는다.
assert.strictEqual(
  decideVerification({
    holderName: '홍길동상사',
    accountHolder: '홍길동상사',
    realName: '홍길동',
    accountType: ACCOUNT_TYPE.business,
    business: bizVerified,
  }).failReason,
  FAIL_REASON.businessHolderMismatch,
  'contains 방식이면 통과했을 값이다',
);

// 사업자 인증을 마치지 않았으면 사업자 명의 계좌 자체를 쓸 수 없다.
//
// 마지막 두 개가 이번에 막은 경로다:
//   · 진위는 통과했는데 권한이 없는 계정(타인 명의 — 대표자 확인 대기)
//   · authorization 자체가 없는 문서(권한 축 도입 전 형태)
// 둘 다 status만 보면 'verified'라 예전에는 그대로 통과했다.
for (const biz of [
  null,
  undefined,
  {},
  { status: 'pending' },
  { ...bizVerified, authorization: 'pendingOwnerApproval' },
  { status: 'verified', representativeName: '홍길동' },
]) {
  assert.strictEqual(
    decideVerification({
      holderName: '홍길동',
      accountHolder: '홍길동',
      realName: '홍길동',
      accountType: ACCOUNT_TYPE.business,
      business: biz,
    }).failReason,
    FAIL_REASON.businessNotVerified,
  );
}

// 입력 예금주 대조는 유형과 무관하게 먼저 걸린다.
assert.strictEqual(
  decideVerification({
    holderName: '홍길동',
    accountHolder: '김철수',
    realName: '홍길동',
    accountType: ACCOUNT_TYPE.business,
    business: bizVerified,
  }).failReason,
  FAIL_REASON.holderMismatch,
);

// 개인 계좌 판정은 사업자 인증 유무에 영향받지 않는다 — 사업자 호스트가
// 대표자 개인계좌를 골라도 예전과 똑같이 본인확인 실명으로만 대조한다.
assert.strictEqual(
  decideVerification({
    holderName: '홍길동',
    accountHolder: '홍길동',
    realName: '홍길동',
    accountType: ACCOUNT_TYPE.personal,
    business: bizVerified,
  }).status,
  STATUS.verified,
);
assert.strictEqual(
  decideVerification({
    holderName: '김철수',
    accountHolder: '김철수',
    realName: '홍길동',
    accountType: ACCOUNT_TYPE.personal,
    business: bizVerified,
  }).failReason,
  FAIL_REASON.identityMismatch,
);

// ══════════════════════════════════════════════════════════════════════════
// 인증 완료 후 30일 잠금
// ══════════════════════════════════════════════════════════════════════════

const {
  LOCK_DAYS,
  IN_FLIGHT_TTL_MS,
  toMillis,
  lockedUntilOf,
  isAccountLocked,
  lockReleaseDateString,
  lockedMessage,
} = require('./payoutAccounts');

const DAY = 24 * 60 * 60 * 1000;

// 시각 읽기 — 문서에서 오는 Timestamp, self-check의 Date·숫자를 모두 흡수한다.
assert.strictEqual(toMillis({ toMillis: () => 1234 }), 1234);
assert.strictEqual(toMillis(new Date(1234)), 1234);
assert.strictEqual(toMillis({ _seconds: 2, _nanoseconds: 500000000 }), 2500);
assert.strictEqual(toMillis(1234), 1234);
assert.strictEqual(toMillis(null), null, '값이 없으면 잠금 계산을 하지 않는다');
assert.strictEqual(toMillis('2026-08-25'), null, '문자열은 읽지 않는다');

/** 인증된 계좌 한 벌을 가진 users 문서를 만든다. */
function verifiedUserDoc(verifiedAtMs, overrides = {}) {
  const payoutAccount = {
    bankCode: '238',
    bankName: '미래에셋증권',
    accountNumber: '12345678901234',
    accountHolder: '홍길동',
    accountType: ACCOUNT_TYPE.personal,
    ...overrides,
  };
  return {
    payoutAccount,
    payoutAccountVerification: {
      status: STATUS.verified,
      accountFingerprint: accountFingerprint(payoutAccount),
      checkedAt: new Date(verifiedAtMs),
    },
  };
}

const VERIFIED_AT = Date.UTC(2026, 7, 25, 3, 0, 0); // 2026-08-25 12:00 KST
const doc = verifiedUserDoc(VERIFIED_AT);

// 해제 시각은 인증 완료 시각 + 정확히 30일이다.
assert.strictEqual(lockedUntilOf(doc), VERIFIED_AT + LOCK_DAYS * DAY);

// ── 경계 ──────────────────────────────────────────────────────────────────
assert.ok(isAccountLocked(doc, VERIFIED_AT), '인증 직후는 잠금');
assert.ok(
  isAccountLocked(doc, VERIFIED_AT + 29 * DAY + (23 * 60 + 59) * 60 * 1000),
  '29일 23:59는 아직 잠금',
);
assert.ok(
  isAccountLocked(doc, VERIFIED_AT + 30 * DAY - 1),
  '30일 1ms 전은 아직 잠금',
);
assert.ok(
  !isAccountLocked(doc, VERIFIED_AT + 30 * DAY),
  '정확히 30일이 되면 변경 가능 — 경계는 열려 있다',
);
assert.ok(!isAccountLocked(doc, VERIFIED_AT + 31 * DAY), '30일 이후는 변경 가능');

// ── 인증 실패는 잠그지 않는다 ─────────────────────────────────────────────
// 실패는 고쳐서 다시 시도해야 하는 상태다. 여기서 잠기면 계좌를 영영 등록할 수
// 없게 된다.
const failedDoc = verifiedUserDoc(VERIFIED_AT);
failedDoc.payoutAccountVerification.status = STATUS.required;
failedDoc.payoutAccountVerification.failReason = FAIL_REASON.holderMismatch;
assert.strictEqual(lockedUntilOf(failedDoc), null);
assert.ok(!isAccountLocked(failedDoc, VERIFIED_AT), '실패 직후 곧바로 재시도 가능');

// 아직 아무 계좌도 없는 계정.
assert.strictEqual(lockedUntilOf({}), null);
assert.ok(!isAccountLocked({}, VERIFIED_AT));

// ── 계좌가 바뀌면 인증이 풀리고 잠금도 함께 풀린다 ────────────────────────
// 지문이 어긋나면 statusOf가 required로 떨어지므로, 30일이 지나 계좌를 바꾼
// 문서는 잠금 대상이 아니다(= 새 계좌는 팝빌 재인증을 거쳐야 한다).
const changedDoc = verifiedUserDoc(VERIFIED_AT);
changedDoc.payoutAccount.accountNumber = '99999999999999';
assert.strictEqual(statusOf(changedDoc), STATUS.required);
assert.strictEqual(lockedUntilOf(changedDoc), null);

// 예금주명만 바꿔도 마찬가지다(지문에 예금주·명의유형까지 들어간다).
const renamedDoc = verifiedUserDoc(VERIFIED_AT);
renamedDoc.payoutAccount.accountHolder = '김철수';
assert.strictEqual(statusOf(renamedDoc), STATUS.required);
const retypedDoc = verifiedUserDoc(VERIFIED_AT);
retypedDoc.payoutAccount.accountType = ACCOUNT_TYPE.business;
assert.strictEqual(statusOf(retypedDoc), STATUS.required);

// ── 인증 시각을 읽을 수 없으면 잠그지 않는다 ──────────────────────────────
// 기록이 깨진 계정을 영구히 묶어 두는 쪽이 더 나쁘다.
const noTimeDoc = verifiedUserDoc(VERIFIED_AT);
delete noTimeDoc.payoutAccountVerification.checkedAt;
assert.strictEqual(lockedUntilOf(noTimeDoc), null);

// ── 안내 문구 ─────────────────────────────────────────────────────────────
// 날짜는 **한국 날짜**여야 한다. UTC로 찍으면 하루 어긋난다.
assert.strictEqual(
  lockReleaseDateString(Date.UTC(2026, 8, 23, 15, 30)),
  '2026.09.24',
  'UTC 15:30은 한국에서 다음 날이다',
);
assert.strictEqual(
  lockReleaseDateString(Date.UTC(2026, 8, 24, 0, 30)),
  '2026.09.24',
);
assert.strictEqual(
  lockedMessage(lockedUntilOf(doc)),
  '인증된 수취계좌는 인증 완료 후 30일 동안 변경할 수 없어요. '
    + '2026.09.24부터 변경 가능합니다.',
);

// ══════════════════════════════════════════════════════════════════════════
// 콜러블 경로 검증 — Firestore와 팝빌을 **대역**으로 세우고 실제 핸들러를 돌린다
//
// 여기서 확인하는 것은 순수 함수로는 고정할 수 없는 것들이다.
//   · 잠금 판정이 **팝빌 조회보다 먼저** 일어나는가(= 거절될 요청에 과금되지
//     않는가)
//   · 앱을 거치지 않고 콜러블을 직접 불러도 같은 자리에서 막히는가
//   · 겹쳐 들어온 요청 중 하나만 조회로 나가는가
//   · 실패한 뒤에는 곧바로 다시 시도할 수 있는가
//
// Firestore 트랜잭션의 원자성 자체는 Firestore의 계약이라 여기서 증명하지
// 않는다. 대역은 트랜잭션을 **직렬화**해서, 우리 코드가 그 직렬성 위에서
// 올바르게 선점하는지만 본다.
// ══════════════════════════════════════════════════════════════════════════

const admin = require('firebase-admin');
const popbillModule = require('./popbill');
const { verifyPayoutAccount } = require('./payoutAccounts');

/** 사용자·서버 시각을 한 손잡이로 움직인다. */
const clock = { now: VERIFIED_AT };

/** serverTimestamp()/delete() 자리표시자 — 대역이 병합할 때 풀어낸다. */
const SERVER_TIMESTAMP = { __sentinel: 'serverTimestamp' };
const DELETE_FIELD = { __sentinel: 'delete' };

function isPlainMap(v) {
  return (
    v !== null
    && typeof v === 'object'
    && !(v instanceof Date)
    && !Array.isArray(v)
    && !v.__sentinel
  );
}

/** Firestore의 set(merge:true) 의미를 그대로 흉내 낸다. */
function mergeInto(target, patch) {
  for (const [k, v] of Object.entries(patch)) {
    if (v === DELETE_FIELD) {
      delete target[k];
    } else if (v === SERVER_TIMESTAMP) {
      target[k] = new Date(clock.now);
    } else if (isPlainMap(v)) {
      if (!isPlainMap(target[k])) target[k] = {};
      mergeInto(target[k], v);
    } else {
      target[k] = v;
    }
  }
}

/** users/{uid} 하나만 있는 최소 Firestore 대역. */
function makeFakeFirestore(docs) {
  const store = new Map(Object.entries(docs));
  // 트랜잭션은 한 번에 하나씩만 — 경합할 때 실제 Firestore가 보장하는 것과 같다.
  let chain = Promise.resolve();

  const refFor = (path) => ({
    path,
    async get() {
      const data = store.get(path);
      return { exists: data !== undefined, data: () => data };
    },
    async set(patch, options) {
      const next = options && options.merge ? store.get(path) || {} : {};
      mergeInto(next, patch);
      store.set(path, next);
    },
  });

  return {
    _store: store,
    collection: (name) => ({ doc: (id) => refFor(`${name}/${id}`) }),
    runTransaction(fn) {
      const run = chain.then(() =>
        fn({
          get: (ref) => ref.get(),
          set: (ref, patch, options) => ref.set(patch, options),
        }),
      );
      // 실패해도 뒤 트랜잭션이 멈추지 않게 체인은 따로 잇는다.
      chain = run.then(
        () => undefined,
        () => undefined,
      );
      return run;
    },
  };
}

/** 대역을 걸고 본문을 실행한 뒤 반드시 원래대로 되돌린다. */
async function withHarness(docs, popbillImpl, body) {
  // admin.firestore는 getter 프로퍼티라 그냥 대입하면 조용히 무시된다
  // (그러면 진짜 Firestore가 불려 app/no-app으로 죽는다). 서술자를 바꾼다.
  const realFirestoreDesc = Object.getOwnPropertyDescriptor(admin, 'firestore');
  const realCheck = popbillModule.checkAccountName;
  const realNow = Date.now;

  const db = makeFakeFirestore(docs);
  const calls = [];
  const fakeFirestore = () => db;
  fakeFirestore.FieldValue = {
    serverTimestamp: () => SERVER_TIMESTAMP,
    delete: () => DELETE_FIELD,
  };
  Object.defineProperty(admin, 'firestore', {
    value: fakeFirestore,
    configurable: true,
    writable: true,
  });
  popbillModule.checkAccountName = async (args) => {
    calls.push(args.bankCode);
    return popbillImpl(args);
  };
  Date.now = () => clock.now;

  try {
    return await body({ db, calls });
  } finally {
    // 원래 firestore는 admin의 own 프로퍼티가 아닐 수 있다(지연 정의).
    // 그럴 때는 우리가 덮어쓴 own 프로퍼티를 지우면 원래 것이 다시 드러난다.
    if (realFirestoreDesc) {
      Object.defineProperty(admin, 'firestore', realFirestoreDesc);
    } else {
      delete admin.firestore;
    }
    popbillModule.checkAccountName = realCheck;
    Date.now = realNow;
  }
}

const UID = 'host-under-test';
const REQUEST = {
  bankCode: '238',
  accountNumber: '1234-5678-901234',
  accountHolder: '홍길동',
  accountType: ACCOUNT_TYPE.personal,
};
const call = (data) =>
  verifyPayoutAccount.run({ auth: { uid: UID }, data: data || REQUEST });

/** 인증 완료 상태의 users 문서 한 벌 — NICE 실명까지 갖춘 형태. */
function verifiedHostDoc(verifiedAtMs) {
  const d = verifiedUserDoc(verifiedAtMs);
  d.name = '홍길동';
  return d;
}

async function expectHttpsError(promise, code) {
  try {
    await promise;
  } catch (e) {
    assert.strictEqual(e.code, code, `기대한 code=${code}, 실제=${e.code}`);
    return e;
  }
  return assert.fail(`오류가 나야 하는데 성공했다 (code=${code})`);
}

const LOCK_MESSAGE =
  '인증된 수취계좌는 인증 완료 후 30일 동안 변경할 수 없어요. '
  + '2026.09.24부터 변경 가능합니다.';

(async () => {
  // ── ① 잠금 중 콜러블 직접 호출 — 앱을 거치지 않아도 막힌다 ──────────────
  await withHarness(
    { [`users/${UID}`]: verifiedHostDoc(VERIFIED_AT) },
    async () => '홍길동',
    async ({ db, calls }) => {
      clock.now = VERIFIED_AT + 29 * DAY + (23 * 60 + 59) * 60 * 1000;
      const before = JSON.stringify(db._store.get(`users/${UID}`));

      // 계좌를 통째로 바꿔 보내도 마찬가지다.
      const err = await expectHttpsError(
        call({ ...REQUEST, bankCode: '004', accountNumber: '99999999' }),
        'failed-precondition',
      );
      assert.strictEqual(err.message, LOCK_MESSAGE);
      assert.strictEqual(calls.length, 0, '잠금 중에는 팝빌을 부르지 않는다');
      assert.strictEqual(
        JSON.stringify(db._store.get(`users/${UID}`)),
        before,
        '거절된 요청은 문서를 건드리지 않는다(선점 표시도 남기지 않는다)',
      );
    },
  );

  // ── ② 정확히 30일 — 경계가 열리고, 바꾼 계좌는 다시 인증을 거친다 ───────
  await withHarness(
    { [`users/${UID}`]: verifiedHostDoc(VERIFIED_AT) },
    async () => '홍길동',
    async ({ db, calls }) => {
      clock.now = VERIFIED_AT + 30 * DAY;
      const res = await call({ ...REQUEST, accountNumber: '99999999999999' });
      assert.strictEqual(res.status, STATUS.verified);
      assert.strictEqual(calls.length, 1, '30일이 지나면 팝빌로 나간다');

      const doc = db._store.get(`users/${UID}`);
      assert.strictEqual(doc.payoutAccount.accountNumber, '99999999999999');
      assert.strictEqual(
        lockedUntilOf(doc),
        clock.now + LOCK_DAYS * DAY,
        '계좌를 바꿔 재인증하면 30일이 새로 시작한다',
      );
      assert.ok(
        !('inFlightAt' in doc.payoutAccountVerification),
        '선점 표시는 결과와 함께 지워진다',
      );
      assert.ok(
        !('failReason' in doc.payoutAccountVerification),
        '성공하면 지난 실패 사유가 남지 않는다',
      );
    },
  );

  // ── ③ 인증 실패 → 고쳐서 즉시 재시도 (잠기지 않는다) ────────────────────
  await withHarness(
    { [`users/${UID}`]: { name: '홍길동' } },
    async (args) => (args.accountNumber === '12345678901234' ? '김철수' : '홍길동'),
    async ({ db, calls }) => {
      clock.now = VERIFIED_AT;
      const failed = await call();
      assert.strictEqual(failed.status, STATUS.required);
      assert.strictEqual(failed.failReason, FAIL_REASON.holderMismatch);
      const v = () => db._store.get(`users/${UID}`).payoutAccountVerification;
      assert.ok(
        !('inFlightAt' in v()),
        '실패해도 선점은 풀린다 — 곧바로 다시 시도할 수 있어야 한다',
      );
      assert.strictEqual(lockedUntilOf(db._store.get(`users/${UID}`)), null);

      // 같은 순간 곧바로 재시도 — 잠금도, 중복 판정도 걸리지 않는다.
      const ok = await call({ ...REQUEST, accountNumber: '55555555555555' });
      assert.strictEqual(ok.status, STATUS.verified);
      assert.strictEqual(calls.length, 2, '재시도는 정상적으로 조회된다');
      assert.ok(!('failReason' in v()), '성공하면 실패 사유가 지워진다');
    },
  );

  // ── ④ 버튼 연타·중복 호출 — 조회는 한 번만 나간다 ───────────────────────
  await withHarness(
    { [`users/${UID}`]: { name: '홍길동' } },
    // 앞 호출이 조회 중일 때 뒤 호출이 들어오도록 일부러 늦춘다.
    () => new Promise((resolve) => setTimeout(() => resolve('홍길동'), 50)),
    async ({ calls }) => {
      clock.now = VERIFIED_AT;
      const first = call();
      const second = call();
      const [firstResult, secondError] = await Promise.all([
        first,
        expectHttpsError(second, 'already-exists'),
      ]);
      assert.strictEqual(firstResult.status, STATUS.verified);
      assert.ok(secondError.message.includes('이미 계좌를 확인하고 있어요'));
      assert.strictEqual(calls.length, 1, '겹친 요청은 팝빌을 한 번만 부른다');
    },
  );

  // ── ⑤ 죽은 선점은 스스로 풀린다 ────────────────────────────────────────
  // 앞 호출이 타임아웃으로 죽어 선점 표시만 남은 경우, TTL이 지나면 다시
  // 시도할 수 있어야 한다(영구히 막히면 계좌를 등록할 방법이 없다).
  await withHarness(
    {
      [`users/${UID}`]: {
        name: '홍길동',
        payoutAccountVerification: { inFlightAt: new Date(VERIFIED_AT) },
      },
    },
    async () => '홍길동',
    async ({ calls }) => {
      clock.now = VERIFIED_AT + IN_FLIGHT_TTL_MS - 1;
      await expectHttpsError(call(), 'already-exists');
      assert.strictEqual(calls.length, 0);

      clock.now = VERIFIED_AT + IN_FLIGHT_TTL_MS;
      const res = await call();
      assert.strictEqual(res.status, STATUS.verified);
      assert.strictEqual(calls.length, 1);
    },
  );

  console.log('payoutAccounts.selfcheck: OK');
})().catch((e) => {
  console.error(e);
  process.exit(1);
});

// 사업자 인증 판정 규칙 자체 검증 — `npm run check:bizverify`.
//
// 여기서 못 박는 것은 세 가지다.
// 4. **사업자 정보 변경은 성공한 순간에만 반영된다.** 새 번호가 틀렸거나
//    국세청 API가 죽었다고 기존 인증을 날리면, 잘못 눌러본 대가가 영업 중단이
//    된다(오픈·예약 권한이 status == 'verified' 하나만 본다). 반대로 같은
//    번호가 폐업으로 나온 것은 국세청이 내린 결론이라 반드시 반영해야 한다.
//
// 1. **통과 조건은 세 항목 + 계속사업자뿐.** 사업자등록번호·대표자명·개업일자가
//    국세청 등록정보와 일치하고 계속사업자일 때만 verified다.
// 2. **상호명·사업장 주소는 국세청에 보내지도 않는다.** 본점 주소와 실제 개최
//    장소가 다른 게 정상인데, 국세청 진위확인은 선택 항목도 일치 조건에 넣어
//    표기 차이 하나로 valid=02를 돌려준다(2026-08-21 실측). 앱에는 저장하되
//    validate 요청 본문에는 필수 3개만 담는다.
// 3. **모르면 절대 통과시키지 않는다.** API가 죽었거나 키가 없으면 pending이지
//    verified가 아니다 — "검증 실패 = 통과"가 되는 순간 인증이 무의미해진다.
// 5. **진위와 권한은 다른 축이다.** 국세청을 통과했다는 것(status)과 이 계정이
//    그 사업자를 쓸 수 있다는 것(authorization)은 별개다. 사업자등록증 사본
//    한 장이면 진위 3항목이 전부 나오므로, status만으로 권한을 열면 남의
//    사업자등록증을 주운 사람이 그대로 사업자 호스트가 된다.
// 6. **두 값은 함께만 움직인다.** 한 레코드에 status만 쓰고 authorization을
//    안 쓰는 경로가 하나라도 있으면, 옛 'self'가 새 사업자에 그대로 얹힌다.
// 7. **같은 사업자번호를 두 계정이 동시에 self로 가져갈 수 없다.** 그 판정은
//    where 조회가 아니라 점유 문서 하나를 두고 벌이는 트랜잭션 경쟁이다.

process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'selfcheck';

const assert = require('assert');

// 가짜 Firestore가 쓰는 시각 값 — **require보다 먼저** 갈아끼운다.
const admin = require('firebase-admin');
admin.firestore.FieldValue = { serverTimestamp: () => '<now>' };
admin.firestore.Timestamp = { now: () => '<historyNow>' };

const {
  evaluateNtsResult,
  buildValidatePayload,
  normalizeBusinessNumber,
  normalizeOpeningDate,
  maskBusinessNumber,
  resolveVerificationWrite,
  coreFieldsChanged,
  BUSINESS_HISTORY_LIMIT,
  // ── 권한 축 ──
  isBusinessAuthorized,
  decideAuthorization,
  ownershipHolderOf,
  representativeCiHashOf,
  representativeLevelOf,
  canSupersedePin,
  REP_VERIFICATION_LEVEL,
  AUTH_REASON,
  resolveIdentityBasis,
  applyVerificationOutcome,
  businessNumberHash,
  AUTHORIZATION,
  BUSINESS_OWNERSHIP,
  OWNERSHIP_STATUS,
} = require('./businessVerification');

const cases = [];
const test = (name, fn) => cases.push([name, fn]);

const ACTIVE = { b_no: '1234567890', b_stt: '계속사업자', b_stt_cd: '01', tax_type: '부가가치세 일반과세자' };
const VALID_OK = { b_no: '1234567890', valid: '01', valid_msg: '' };

// ── 통과 조건 ────────────────────────────────────────────────────────────────

test('계속사업자 + 진위확인 일치 → verified', () => {
  const r = evaluateNtsResult(ACTIVE, VALID_OK);
  assert.strictEqual(r.status, 'verified');
  assert.strictEqual(r.failReason, null);
  assert.strictEqual(r.ntsStatusCode, '01');
});

test('진위확인 불일치(valid 02) → failed/mismatch — 계속사업자여도 통과 못 한다', () => {
  const r = evaluateNtsResult(ACTIVE, { valid: '02', valid_msg: '확인할 수 없습니다.' });
  assert.strictEqual(r.status, 'failed');
  assert.strictEqual(r.failReason, 'mismatch');
});

test('등록되지 않은 사업자번호(b_stt_cd 빈값) → failed/notRegistered', () => {
  const r = evaluateNtsResult(
    { b_no: '9999999999', b_stt_cd: '', tax_type: '국세청에 등록되지 않은 사업자등록번호입니다.' },
    null,
  );
  assert.strictEqual(r.status, 'failed');
  assert.strictEqual(r.failReason, 'notRegistered');
});

// ── 휴·폐업 ──────────────────────────────────────────────────────────────────

test('휴업자(02) → suspended — 진위확인이 일치해도 오픈 권한을 주지 않는다', () => {
  const r = evaluateNtsResult({ ...ACTIVE, b_stt: '휴업자', b_stt_cd: '02' }, VALID_OK);
  assert.strictEqual(r.status, 'suspended');
  assert.strictEqual(r.failReason, 'suspended');
  assert.notStrictEqual(r.status, 'verified');
});

test('폐업자(03) → suspended/closed', () => {
  const r = evaluateNtsResult({ ...ACTIVE, b_stt: '폐업자', b_stt_cd: '03' }, VALID_OK);
  assert.strictEqual(r.status, 'suspended');
  assert.strictEqual(r.failReason, 'closed');
});

// ── validate 요청 본문 — 필수 3개만 ─────────────────────────────────────────

test('진위확인 요청에는 b_no/start_dt/p_nm 세 개만 담는다', () => {
  const payload = buildValidatePayload('1234567890', '20200105', '홍길동');
  assert.deepStrictEqual(
    Object.keys(payload).sort(),
    ['b_no', 'p_nm', 'start_dt'],
    'b_nm·b_adr 등 선택 항목을 실으면 사업자등록증 그대로 입력해도 valid=02가 난다',
  );
  assert.strictEqual(payload.b_no, '1234567890');
  assert.strictEqual(payload.start_dt, '20200105');
  assert.strictEqual(payload.p_nm, '홍길동');
});

// ── 상호명·주소는 참고 정보일 뿐 ─────────────────────────────────────────────

test('상호명 불일치가 valid_msg에 언급돼도 valid=01이면 verified다', () => {
  const r = evaluateNtsResult(ACTIVE, { valid: '01', valid_msg: '상호는 확인할 수 없습니다.' });
  assert.strictEqual(r.status, 'verified', '상호명은 실패 조건이 아니다');
  assert.strictEqual(r.nameMatched, false, '불일치는 참고용으로 기록만 한다');
});

test('주소 불일치도 통과를 막지 않는다 — 본점/지점 주소는 다를 수 있다', () => {
  const r = evaluateNtsResult(ACTIVE, { valid: '01', valid_msg: '주소는 확인할 수 없습니다.' });
  assert.strictEqual(r.status, 'verified');
  assert.strictEqual(r.addressMatched, false);
});

test('참고 항목 언급이 없으면 null(판단 안 함)이지 true가 아니다', () => {
  const r = evaluateNtsResult(ACTIVE, VALID_OK);
  assert.strictEqual(r.nameMatched, null);
  assert.strictEqual(r.addressMatched, null);
});

// ── 모르면 통과시키지 않는다 ─────────────────────────────────────────────────

test('상태조회 응답이 없으면(API 장애) pending — verified가 아니다', () => {
  const r = evaluateNtsResult(null, VALID_OK);
  assert.strictEqual(r.status, 'pending');
  assert.strictEqual(r.failReason, 'apiUnavailable');
});

test('계속사업자지만 진위확인 응답이 없으면 pending', () => {
  const r = evaluateNtsResult(ACTIVE, null);
  assert.strictEqual(r.status, 'pending');
  assert.strictEqual(r.failReason, 'apiUnavailable');
});

test('알 수 없는 상태코드는 통과시키지 않는다', () => {
  const r = evaluateNtsResult({ ...ACTIVE, b_stt_cd: '99' }, VALID_OK);
  assert.notStrictEqual(r.status, 'verified');
});

// ── 입력 정규화 ──────────────────────────────────────────────────────────────

test('사업자번호는 하이픈을 떼고 10자리만 받는다', () => {
  assert.strictEqual(normalizeBusinessNumber('123-45-67890'), '1234567890');
  assert.strictEqual(normalizeBusinessNumber('1234567890'), '1234567890');
  assert.strictEqual(normalizeBusinessNumber('12345'), null);
  assert.strictEqual(normalizeBusinessNumber(''), null);
});

test('개업일자는 구분자와 무관하게 yyyymmdd로 정규화된다', () => {
  assert.strictEqual(normalizeOpeningDate('2020-01-05'), '20200105');
  assert.strictEqual(normalizeOpeningDate('2020.01.05'), '20200105');
  assert.strictEqual(normalizeOpeningDate('20200105'), '20200105');
});

test('말이 안 되는 개업일자는 거른다', () => {
  assert.strictEqual(normalizeOpeningDate('20201305'), null, '13월');
  assert.strictEqual(normalizeOpeningDate('20200132'), null, '32일');
  assert.strictEqual(normalizeOpeningDate('202001'), null, '자릿수 부족');
});

test('로그용 마스킹은 앞 3자리만 남긴다 — 사업자번호 전체가 로그에 남으면 안 된다', () => {
  const masked = maskBusinessNumber('1234567890');
  assert.strictEqual(masked, '123*******');
  assert.ok(!masked.includes('4567890'));
});

// ── 사업자 정보 변경 / 사업자번호 변경 ──────────────────────────────────────
//
// 아래는 전부 resolveVerificationWrite(순수 함수)로, 네트워크 없이 돌린다.
// 시각은 문자열 센티널을 넣어 "어느 값이 들어갔는지"를 그대로 확인한다.

const NOW = '<now>';
const HISTORY_NOW = '<historyNow>';
const TODAY = '2026-08-24';

const OK = { status: 'verified', failReason: null, ntsStatusCode: '01', ntsStatusLabel: '계속사업자', taxType: '일반', nameMatched: null, addressMatched: null };
const MISMATCH = { status: 'failed', failReason: 'mismatch', ntsStatusCode: '01', ntsStatusLabel: '계속사업자', taxType: '일반', nameMatched: null, addressMatched: null };
const NOT_REGISTERED = { status: 'failed', failReason: 'notRegistered', ntsStatusCode: '', ntsStatusLabel: '', taxType: '', nameMatched: null, addressMatched: null };
const API_DOWN = { status: 'pending', failReason: 'apiUnavailable', ntsStatusCode: '', ntsStatusLabel: '', taxType: '', nameMatched: null, addressMatched: null };
const CLOSED = { status: 'suspended', failReason: 'closed', ntsStatusCode: '03', ntsStatusLabel: '폐업자', taxType: '일반', nameMatched: null, addressMatched: null };

const inputOf = (o = {}) => ({
  businessNumber: '1234567890',
  representativeName: '홍길동',
  openingDate: '20200105',
  businessName: '파티츄 라운지',
  businessAddress: '서울 강남구 1로 1 3층',
  businessBaseAddress: '서울 강남구 1로 1',
  businessDetailAddress: '3층',
  ...o,
});

/// 지금 **실제로 쓰이고 있는** 권한을 가진 계정의 기존 기록.
/// authorization이 없으면 그것은 권한이 아니다(isBusinessAuthorized).
const verifiedPrev = (o = {}) => ({
  status: 'verified',
  authorization: 'self',
  businessNumber: '1234567890',
  representativeName: '홍길동',
  openingDate: '20200105',
  businessName: '파티츄 라운지',
  businessAddress: '서울 강남구 1로 1 3층',
  verifiedAt: '<oldVerifiedAt>',
  lastCheckedAt: '<oldCheckedAt>',
  ...o,
});

// 권한 판정(decideAuthorization의 결과 모양) — 아래 테스트가 갈아끼운다.
const SELF = {
  authorization: 'self',
  authorizationReason: null,
  claimOwnership: true,
};
const OTHERS_NAME = {
  authorization: 'pendingOwnerApproval',
  authorizationReason: 'representativeMismatch',
  claimOwnership: false,
};
const NO_AUTH = {
  authorization: 'none',
  authorizationReason: null,
  claimOwnership: false,
};

/// 판정을 따로 주지 않으면 "국세청을 통과했으면 본인 명의"로 본다 —
/// 이 파일의 기존 테스트가 전부 그 경우를 다루고 있어서다.
const run = (prev, outcome, input, attemptsToday = 0, decision = null) =>
  resolveVerificationWrite({
    prev,
    outcome,
    decision: decision || (outcome.status === 'verified' ? SELF : NO_AUTH),
    input: inputOf(input),
    now: NOW,
    historyNow: HISTORY_NOW,
    todayKey: TODAY,
    attemptsToday,
  });

test('변경① 미인증 → 최초 인증 성공: 새 기록으로 저장되고 verifiedAt이 찍힌다', () => {
  const { record, mode } = run({}, OK, {});
  assert.strictEqual(mode, 'replaced');
  assert.strictEqual(record.status, 'verified');
  assert.strictEqual(record.businessNumber, '1234567890');
  assert.strictEqual(record.verifiedAt, NOW);
  assert.strictEqual(record.pendingChange, null);
  // 최초 인증에는 교체 이력이 없다.
  assert.strictEqual(record.history, undefined);
  assert.strictEqual(record.previousBusinessNumber, undefined);
});

test('변경② 미인증 → 최초 인증 실패: 예전 그대로 실패 상태가 기록된다', () => {
  const { record, mode } = run({}, NOT_REGISTERED, {});
  assert.strictEqual(mode, 'overwritten');
  assert.strictEqual(record.status, 'failed');
  assert.strictEqual(record.failReason, 'notRegistered');
  // 지킬 인증이 없으므로 verifiedAt도 생기지 않는다.
  assert.strictEqual(record.verifiedAt, undefined);
});

test('변경③ 인증 완료 → 상호·주소만 수정 후 재인증: 최초 인증일을 유지한 채 교체된다', () => {
  const { record, mode, numberChanged } = run(verifiedPrev(), OK, {
    businessName: '파티츄 라운지 2호점',
    businessAddress: '서울 마포구 2로 2 1층',
    businessBaseAddress: '서울 마포구 2로 2',
    businessDetailAddress: '1층',
  });
  assert.strictEqual(mode, 'replaced');
  assert.strictEqual(numberChanged, false);
  assert.strictEqual(record.status, 'verified');
  assert.strictEqual(record.businessName, '파티츄 라운지 2호점');
  assert.strictEqual(record.businessAddress, '서울 마포구 2로 2 1층');
  // 같은 사업자를 다시 확인한 것뿐이라 최초 인증일은 그대로다.
  assert.strictEqual(record.verifiedAt, '<oldVerifiedAt>');
  // 번호가 안 바뀌었으니 교체 이력도 남기지 않는다.
  assert.strictEqual(record.history, undefined);
});

test('변경④ 인증 완료 → 사업자번호 변경 후 재인증 성공: 새 정보로 완전히 교체 + 감사 기록', () => {
  const { record, mode, numberChanged } = run(verifiedPrev(), OK, {
    businessNumber: '9876543210',
    representativeName: '김철수',
    openingDate: '20240301',
    businessName: '파티츄 컴퍼니',
  });
  assert.strictEqual(mode, 'replaced');
  assert.strictEqual(numberChanged, true);
  assert.strictEqual(record.status, 'verified');
  assert.strictEqual(record.businessNumber, '9876543210');
  assert.strictEqual(record.representativeName, '김철수');
  assert.strictEqual(record.openingDate, '20240301');
  // 새 사업자의 인증일이므로 지금으로 다시 잡는다.
  assert.strictEqual(record.verifiedAt, NOW);
  // 감사용 기록 — 화면에 띄우지 않아도 운영에서 추적할 수 있어야 한다.
  assert.strictEqual(record.previousBusinessNumber, '1234567890');
  assert.strictEqual(record.previousVerifiedAt, '<oldVerifiedAt>');
  assert.strictEqual(record.changedAt, NOW);
  assert.strictEqual(record.changeCount, 1);
  assert.strictEqual(record.history.length, 1);
  assert.strictEqual(record.history[0].businessNumber, '1234567890');
  assert.strictEqual(record.history[0].replacedAt, HISTORY_NOW);
  // 이전 변경 시도의 흔적은 성공과 함께 지워진다.
  assert.strictEqual(record.pendingChange, null);
});

test('변경⑤ 인증 완료 → 잘못된 새 번호: 기존 인증을 건드리지 않는다', () => {
  const { record, mode } = run(verifiedPrev(), NOT_REGISTERED, {
    businessNumber: '9999999999',
  });
  assert.strictEqual(mode, 'keptVerified');
  // status·businessNumber·verifiedAt 어느 것도 쓰지 않는다 = merge로 보존된다.
  assert.strictEqual(record.status, undefined);
  assert.strictEqual(record.businessNumber, undefined);
  assert.strictEqual(record.verifiedAt, undefined);
  // lastCheckedAt도 손대지 않는다 — 인증된 사업자를 확인한 시각이 아니다.
  assert.strictEqual(record.lastCheckedAt, undefined);
  // 실패한 시도는 별도 칸에만 남는다.
  assert.strictEqual(record.pendingChange.status, 'failed');
  assert.strictEqual(record.pendingChange.failReason, 'notRegistered');
  assert.strictEqual(record.pendingChange.businessNumber, '9999999999');
  assert.strictEqual(record.pendingChange.attemptedAt, NOW);
});

test('변경⑥ 인증 완료 → 새 번호가 국세청 정보와 불일치: 역시 기존 인증 유지', () => {
  const { record, mode } = run(verifiedPrev(), MISMATCH, {
    businessNumber: '9876543210',
    representativeName: '엉뚱한이름',
  });
  assert.strictEqual(mode, 'keptVerified');
  assert.strictEqual(record.status, undefined);
  assert.strictEqual(record.pendingChange.failReason, 'mismatch');
});

test('변경⑦ 인증 완료 → NTS API 장애(pending): 같은 번호 재확인이어도 인증을 날리지 않는다', () => {
  const { record, mode } = run(verifiedPrev(), API_DOWN, {});
  assert.strictEqual(mode, 'keptVerified');
  assert.strictEqual(record.status, undefined);
  assert.strictEqual(record.pendingChange.status, 'pending');
  assert.strictEqual(record.pendingChange.failReason, 'apiUnavailable');
});

test('변경⑧ 인증 완료 → 새 번호인데 NTS 장애: 기존 인증 유지', () => {
  const { mode } = run(verifiedPrev(), API_DOWN, { businessNumber: '9876543210' });
  assert.strictEqual(mode, 'keptVerified');
});

test('변경⑨ 인증 완료 → 같은 번호가 폐업으로 조회: 국세청 결론이므로 그대로 반영한다', () => {
  const { record, mode } = run(verifiedPrev(), CLOSED, {});
  assert.strictEqual(mode, 'overwritten');
  assert.strictEqual(record.status, 'suspended');
  assert.strictEqual(record.failReason, 'closed');
  // 최초 통과 시각은 이력으로 남긴다(예전 동작 그대로).
  assert.strictEqual(record.verifiedAt, '<oldVerifiedAt>');
});

test('변경⑩ 인증 완료 → 같은 번호가 불일치로 조회: 그대로 반영한다', () => {
  const { record, mode } = run(verifiedPrev(), MISMATCH, {});
  assert.strictEqual(mode, 'overwritten');
  assert.strictEqual(record.status, 'failed');
});

test('판정 3항목만 변경으로 본다 — 상호·주소는 아니다', () => {
  const prev = verifiedPrev();
  assert.strictEqual(coreFieldsChanged(prev, inputOf({ businessName: '다른 상호' })), false);
  assert.strictEqual(coreFieldsChanged(prev, inputOf({ businessAddress: '다른 주소' })), false);
  assert.strictEqual(coreFieldsChanged(prev, inputOf({ businessNumber: '9876543210' })), true);
  assert.strictEqual(coreFieldsChanged(prev, inputOf({ representativeName: '김철수' })), true);
  assert.strictEqual(coreFieldsChanged(prev, inputOf({ openingDate: '20240301' })), true);
});

test('하루 시도 횟수는 어느 갈래로 가든 똑같이 센다', () => {
  for (const outcome of [OK, MISMATCH, API_DOWN, CLOSED]) {
    const { record } = run(verifiedPrev(), outcome, { businessNumber: '9876543210' }, 4);
    assert.strictEqual(record.attemptCount, 5, 'outcome=' + outcome.status);
    assert.strictEqual(record.attemptDate, TODAY, 'outcome=' + outcome.status);
  }
});

test('교체 이력은 최근 ' + BUSINESS_HISTORY_LIMIT + '건만 남는다', () => {
  const old = Array.from({ length: BUSINESS_HISTORY_LIMIT }, (_, i) => ({
    businessNumber: '000000000' + i,
  }));
  const { record } = run(verifiedPrev({ history: old }), OK, {
    businessNumber: '9876543210',
  });
  assert.strictEqual(record.history.length, BUSINESS_HISTORY_LIMIT);
  // 가장 오래된 것이 밀려나고 방금 교체된 사업자가 맨 뒤에 붙는다.
  assert.strictEqual(record.history[0].businessNumber, '0000000001');
  assert.strictEqual(record.history[BUSINESS_HISTORY_LIMIT - 1].businessNumber, '1234567890');
});

test('변경 성공 시 새 정보만 남는다 — 옛 상호·주소가 섞이지 않는다', () => {
  const { record } = run(verifiedPrev(), OK, {
    businessNumber: '9876543210',
    representativeName: '김철수',
    openingDate: '20240301',
    businessName: '새 상호',
    businessAddress: '새 주소 101호',
    businessBaseAddress: '새 주소',
    businessDetailAddress: '101호',
  });
  // 교체 레코드는 소비 경로가 읽는 필드를 **모두** 새 값으로 덮는다.
  const expected = {
    businessNumber: '9876543210',
    representativeName: '김철수',
    openingDate: '20240301',
    businessName: '새 상호',
    businessAddress: '새 주소 101호',
    businessBaseAddress: '새 주소',
    businessDetailAddress: '101호',
  };
  for (const k of Object.keys(expected)) {
    assert.strictEqual(record[k], expected[k], k + '가 새 값으로 안 바뀌었다');
  }
});

// ══════════════════════════════════════════════════════════════════════════
// 권한 축(authorization) — "사업자가 진짜인가"와 "이 계정이 쓸 수 있는가"
// ══════════════════════════════════════════════════════════════════════════

// ── 게이트: isBusinessAuthorized ────────────────────────────────────────
//
// 이 함수 하나가 파티 오픈·플레이스 등록·사업자 수취계좌 권한을 전부 가른다
// (firestore.rules의 isBusinessVerified()가 같은 두 조건을 규칙 문법으로 다시 쓴다).

test('게이트: verified + self만 권한이 열린다', () => {
  assert.strictEqual(
    isBusinessAuthorized({ status: 'verified', authorization: 'self' }),
    true,
  );
});

test('게이트: authorization이 없는 문서는 통과하지 못한다 — legacy 예외는 두지 않는다', () => {
  // 예외를 하나라도 두면 "그 필드를 안 쓰면 통과"가 되어 판정이 무력해진다.
  assert.strictEqual(isBusinessAuthorized({ status: 'verified' }), false);
  assert.strictEqual(
    isBusinessAuthorized({ status: 'verified', authorization: null }),
    false,
  );
  assert.strictEqual(
    isBusinessAuthorized({ status: 'verified', authorization: '' }),
    false,
  );
});

test('게이트: 대표자 확인이 필요한 계정은 권한이 없다 — status는 verified여도', () => {
  assert.strictEqual(
    isBusinessAuthorized({
      status: 'verified',
      authorization: 'pendingOwnerApproval',
    }),
    false,
  );
});

test('게이트: 권한이 self여도 사업자가 확인되지 않았으면 열리지 않는다', () => {
  for (const status of ['failed', 'suspended', 'pending', 'unverified']) {
    assert.strictEqual(
      isBusinessAuthorized({ status, authorization: 'self' }),
      false,
      `${status} + self가 통과했다`,
    );
  }
});

test('게이트: 모르는 authorization 값은 통과하지 못한다(위임은 아직 열려 있지 않다)', () => {
  // 'delegated'는 2단계에서 열린다 — 지금 문서에 그 값이 적혀 있어도 안 된다.
  assert.strictEqual(
    isBusinessAuthorized({ status: 'verified', authorization: 'delegated' }),
    false,
  );
  assert.strictEqual(
    isBusinessAuthorized({ status: 'verified', authorization: 'admin' }),
    false,
  );
});

test('게이트: 문서 자체가 없으면 권한이 없다(fail-closed)', () => {
  assert.strictEqual(isBusinessAuthorized(null), false);
  assert.strictEqual(isBusinessAuthorized(undefined), false);
  assert.strictEqual(isBusinessAuthorized({}), false);
});

// ── 권한 판정: decideAuthorization ──────────────────────────────────────

test('권한: 국세청을 통과하지 못하면 권한을 따지지 않는다(none)', () => {
  for (const outcome of [MISMATCH, NOT_REGISTERED, API_DOWN, CLOSED]) {
    const d = decideAuthorization({
      outcome,
      nameMatchesIdentity: true,
      ownershipHolderUid: null,
      uid: 'uidA',
    });
    assert.strictEqual(d.authorization, AUTHORIZATION.none);
    assert.strictEqual(d.claimOwnership, false, '통과도 못 했는데 점유를 시도했다');
  }
});

test('권한: 본인 명의 + 아무도 안 잡고 있으면 self, 그리고 점유한다', () => {
  const d = decideAuthorization({
    outcome: OK,
    nameMatchesIdentity: true,
    ownershipHolderUid: null,
    uid: 'uidA',
  });
  assert.strictEqual(d.authorization, AUTHORIZATION.self);
  assert.strictEqual(d.authorizationReason, null);
  assert.strictEqual(d.claimOwnership, true);
});

test('권한: 대표자명이 다르면 pendingOwnerApproval — 그리고 **점유하지 않는다**', () => {
  // 여기서 점유까지 해버리면 남의 사업자번호를 선점해 실제 대표자의 자동승인을
  // 막을 수 있다(서비스 거부). 그래서 이름이 맞을 때만 점유한다.
  const d = decideAuthorization({
    outcome: OK,
    nameMatchesIdentity: false,
    ownershipHolderUid: null,
    uid: 'uidA',
  });
  assert.strictEqual(d.authorization, AUTHORIZATION.pendingOwnerApproval);
  assert.strictEqual(d.authorizationReason, 'representativeMismatch');
  assert.strictEqual(d.claimOwnership, false);
});

test('권한: 이름이 맞아도 다른 계정이 점유 중이면 pendingOwnerApproval', () => {
  const d = decideAuthorization({
    outcome: OK,
    nameMatchesIdentity: true,
    ownershipHolderUid: 'uidB',
    uid: 'uidA',
  });
  assert.strictEqual(d.authorization, AUTHORIZATION.pendingOwnerApproval);
  assert.strictEqual(d.authorizationReason, 'ownedByAnotherAccount');
  assert.strictEqual(d.claimOwnership, false);
});

test('권한: 내가 이미 점유한 번호는 다시 인증해도 self다', () => {
  const d = decideAuthorization({
    outcome: OK,
    nameMatchesIdentity: true,
    ownershipHolderUid: 'uidA',
    uid: 'uidA',
  });
  assert.strictEqual(d.authorization, AUTHORIZATION.self);
  assert.strictEqual(d.claimOwnership, true);
});

test('권한: 이름 불일치가 점유 여부보다 먼저 걸린다 — 순서가 규칙이다', () => {
  const d = decideAuthorization({
    outcome: OK,
    nameMatchesIdentity: false,
    ownershipHolderUid: 'uidB',
    uid: 'uidA',
  });
  assert.strictEqual(d.authorizationReason, 'representativeMismatch');
});

// ── 대표자 CI 핀의 **신뢰 강도** ────────────────────────────────────────
//
// 핀은 "대표자임이 증명된 사람"이 아니다. 지금 만들어지는 등급은 이름 대조
// 하나뿐이고, 그래서 핀이 해주는 일은 판정이 아니라 **충돌 감지**다.
// 아래 테스트들이 그 의미를 못 박는다.

test('핀 등급: 지금 만들어지는 등급은 nameMatched 하나뿐이다', () => {
  // self 자동승인도, 대표자 승인도 사업자와 CI를 직접 결합해 확인하지 않는다.
  // strongVerified를 만드는 수단이 붙기 전까지 그 값은 아무도 쓰지 않는다.
  const src = require('fs').readFileSync(
    require('path').join(__dirname, 'businessVerification.js'), 'utf8',
  ) + require('fs').readFileSync(
    require('path').join(__dirname, 'businessDelegation.js'), 'utf8',
  );
  const writes = [...src.matchAll(/representativeVerificationLevel:\s*([^,\n]+)/g)]
    .map((m) => m[1].trim());
  assert.ok(writes.length >= 2, '점유 문서에 등급을 안 쓰는 경로가 있다');
  for (const w of writes) {
    assert.strictEqual(
      w, 'REP_VERIFICATION_LEVEL.nameMatched',
      `현재 계약 범위 밖의 등급을 쓰고 있다: ${w}`,
    );
  }
});

test('핀 등급: 등급이 없는 옛 문서는 nameMatched로 읽는다(강한 등급으로 승격 금지)', () => {
  assert.strictEqual(
    representativeLevelOf({ representativeCiHash: 'X' }),
    REP_VERIFICATION_LEVEL.nameMatched,
  );
  assert.strictEqual(representativeLevelOf(null), REP_VERIFICATION_LEVEL.nameMatched);
  // 모르는 값도 승격시키지 않는다.
  assert.strictEqual(
    representativeLevelOf({ representativeVerificationLevel: 'somethingElse' }),
    REP_VERIFICATION_LEVEL.nameMatched,
  );
});

test('핀 등급: 이름 대조끼리는 우열이 없어 자동 대체가 되지 않는다', () => {
  const { nameMatched, strongVerified } = REP_VERIFICATION_LEVEL;
  // 지금 실제로 일어나는 유일한 조합 — 항상 false여야 한다.
  assert.strictEqual(canSupersedePin(nameMatched, nameMatched), false);
  // 강한 등급을 약한 등급이 밀어낼 수는 없다.
  assert.strictEqual(canSupersedePin(strongVerified, nameMatched), false);
  assert.strictEqual(canSupersedePin(strongVerified, strongVerified), false);
  // 확장 지점 — 사업자와 CI를 직접 결합해 검증하는 수단이 붙었을 때만.
  assert.strictEqual(canSupersedePin(nameMatched, strongVerified), true);
});

test('핀 등급: **역전 위험** — 먼저 박힌 CI가 동명이인이면 실제 대표자가 막힌다', () => {
  // 이것은 버그가 아니라 알려진 한계이고, 그래서 자동으로 풀지 않는다.
  // 실제 대표자가 뒤에 와도 결과는 '차단 + 사람이 확인'이다.
  const realOwner = decideAuthorization({
    outcome: OK,
    nameMatchesIdentity: true,          // 진짜 대표자다(이름도 맞다)
    ownershipHolderUid: null,
    ownershipRepCiHash: 'CI_먼저온_동명이인',
    ownershipRepLevel: REP_VERIFICATION_LEVEL.nameMatched,
    identityCiHash: 'CI_실제_대표자',
    uid: 'uid진짜',
  });
  assert.strictEqual(realOwner.authorization, AUTHORIZATION.pendingOwnerApproval);
  assert.strictEqual(realOwner.authorizationReason, AUTH_REASON.representativeCiMismatch);
  assert.strictEqual(realOwner.claimOwnership, false, '실제 대표자가 핀을 뺏어갔다');
});

test('CI 핀: 이름이 맞아도 기존 대표자 CI와 다르면 self를 주지 않는다', () => {
  const d = decideAuthorization({
    outcome: OK,
    nameMatchesIdentity: true,
    ownershipHolderUid: null,
    ownershipRepCiHash: 'CI_진짜대표자',
    identityCiHash: 'CI_동명이인',
    uid: 'uidX',
  });
  assert.strictEqual(d.authorization, AUTHORIZATION.pendingOwnerApproval);
  assert.strictEqual(d.authorizationReason, AUTH_REASON.representativeCiMismatch);
  assert.strictEqual(d.claimOwnership, false, '동명이인이 점유를 가져갔다');
});

test('CI 핀: 대표자 CI가 같으면 계정이 달라도 self다(탈퇴 후 재가입)', () => {
  const d = decideAuthorization({
    outcome: OK,
    nameMatchesIdentity: true,
    ownershipHolderUid: 'oldUid',
    ownershipRepCiHash: 'CI_같은사람',
    identityCiHash: 'CI_같은사람',
    uid: 'newUid',
  });
  assert.strictEqual(d.authorization, AUTHORIZATION.self);
});

test('CI 핀: 핀이 없으면 예전처럼 uid 점유로만 판정한다', () => {
  const d = decideAuthorization({
    outcome: OK,
    nameMatchesIdentity: true,
    ownershipHolderUid: 'uidB',
    ownershipRepCiHash: null,
    identityCiHash: 'CI_A',
    uid: 'uidA',
  });
  assert.strictEqual(d.authorizationReason, AUTH_REASON.ownedByAnotherAccount);
});

test('CI 핀: 이름 불일치가 CI 핀보다 먼저 걸린다', () => {
  const d = decideAuthorization({
    outcome: OK,
    nameMatchesIdentity: false,
    ownershipRepCiHash: 'CI_진짜대표자',
    identityCiHash: 'CI_다른사람',
    ownershipHolderUid: null,
    uid: 'uidX',
  });
  assert.strictEqual(d.authorizationReason, AUTH_REASON.representativeMismatch);
});

test('CI 핀 읽기: released여도 대표자 CI는 그대로 읽힌다(충돌 감지를 위해)', () => {
  assert.strictEqual(
    representativeCiHashOf({ status: 'released', representativeCiHash: 'CI_A' }),
    'CI_A',
    'release가 "누가 대표자라고 주장했는가"까지 지웠다',
  );
  assert.strictEqual(representativeCiHashOf(null), null);
  assert.strictEqual(representativeCiHashOf({ status: 'active' }), null);
});

test('게이트: delegated는 근거 문서 id가 있어야만 권한이 열린다', () => {
  assert.strictEqual(
    isBusinessAuthorized({ status: 'verified', authorization: 'delegated' }),
    false,
    'delegationId 없는 위임이 통과했다',
  );
  assert.strictEqual(
    isBusinessAuthorized({ status: 'verified', authorization: 'delegated', delegationId: '' }),
    false,
  );
  assert.strictEqual(
    isBusinessAuthorized({ status: 'verified', authorization: 'delegated', delegationId: 'DLG1' }),
    true,
  );
});

test('레코드: 위임이 아닌 갈래는 delegationId를 null로 **지운다**', () => {
  // merge 저장이라 명시적으로 지우지 않으면 옛 위임 문서 id가 남고,
  // 그 id가 새 사업자의 권한 근거로 읽힌다.
  const prev = {
    status: 'verified',
    authorization: 'delegated',
    delegationId: 'DLG_OLD',
    businessNumber: '1234567890',
  };
  const { record } = run(prev, OK, {}, 0, SELF);
  assert.strictEqual(record.authorization, 'self');
  assert.strictEqual(record.delegationId, null);
});

test('점유: released 문서는 아무도 잡고 있지 않은 것으로 본다', () => {
  assert.strictEqual(ownershipHolderOf({ status: 'active', holderUid: 'uidA' }), 'uidA');
  assert.strictEqual(ownershipHolderOf({ status: 'released', holderUid: 'uidA' }), null);
  assert.strictEqual(ownershipHolderOf(null), null);
  assert.strictEqual(ownershipHolderOf({ holderUid: 'uidA' }), null);
});

// ══════════════════════════════════════════════════════════════════════════
// SDK 직접호출 우회 — resolveIdentityBasis
//
// 앱의 루트 게이트는 화면만 막는다. 구버전 앱과 SDK 직접 호출은 콜러블에 곧장
// 닿으므로, 서버가 users 문서를 직접 읽어 판정하는 이 지점이 실질적인 관문이다.
// ══════════════════════════════════════════════════════════════════════════

const throwsPrecondition = (fn) => {
  try {
    fn();
  } catch (e) {
    return e.code === 'failed-precondition';
  }
  return false;
};

test('우회① 본인확인을 마치지 않은 계정은 국세청을 부르기도 전에 거부된다', () => {
  assert.ok(
    throwsPrecondition(() => resolveIdentityBasis({ name: '홍길동' }, '홍길동')),
    '미인증 계정이 통과했다',
  );
});

test('우회② users 문서가 아예 없는 계정도 거부된다(fail-closed)', () => {
  assert.ok(throwsPrecondition(() => resolveIdentityBasis(null, '홍길동')));
  assert.ok(throwsPrecondition(() => resolveIdentityBasis({}, '홍길동')));
});

test('우회③ 이름만 대표자와 같게 맞춰도 본인확인 없이는 통과하지 못한다', () => {
  // 공격자가 사업자등록증 3항목을 전부 알고 users.name까지 맞췄다고 가정해도,
  // 그 name은 클라이언트가 쓸 수 없는 필드라 애초에 들어갈 수 없고(rules),
  // 설령 들어갔더라도 identityVerified가 없으면 여기서 끝난다.
  assert.ok(
    throwsPrecondition(() =>
      resolveIdentityBasis(
        { name: '홍길동', identityVerified: false, isVerified: false },
        '홍길동',
      ),
    ),
  );
});

test('우회④ 하위호환 isVerified만 있는 계정은 통과한다(identityGuard와 같은 기준)', () => {
  const basis = resolveIdentityBasis({ isVerified: true, name: '홍길동' }, '홍길동');
  assert.strictEqual(basis.nameMatchesIdentity, true);
});

test('이름 대조: NICE 실명과 대표자명이 같으면 일치', () => {
  const basis = resolveIdentityBasis(
    { identityVerified: true, name: '홍길동' },
    '홍길동',
  );
  assert.strictEqual(basis.nameMatchesIdentity, true);
});

test('이름 대조: 공백 차이는 같은 사람으로 본다(payoutAccounts의 정규화를 그대로 쓴다)', () => {
  const basis = resolveIdentityBasis(
    { identityVerified: true, name: '홍 길동' },
    ' 홍길동 ',
  );
  assert.strictEqual(basis.nameMatchesIdentity, true);
});

test('이름 대조: 다른 사람이면 불일치 — 부분 일치도 통과시키지 않는다', () => {
  const b1 = resolveIdentityBasis(
    { identityVerified: true, name: '홍길동' },
    '김철수',
  );
  assert.strictEqual(b1.nameMatchesIdentity, false);
  const b2 = resolveIdentityBasis(
    { identityVerified: true, name: '홍길' },
    '홍길동',
  );
  assert.strictEqual(b2.nameMatchesIdentity, false, '부분 일치가 통과했다');
});

test('이름 대조: 실명이 비어 있으면 절대 일치가 아니다(빈 값끼리 통과 금지)', () => {
  const basis = resolveIdentityBasis({ identityVerified: true, name: '' }, '');
  assert.strictEqual(basis.nameMatchesIdentity, false);
  const basis2 = resolveIdentityBasis({ identityVerified: true }, '홍길동');
  assert.strictEqual(basis2.nameMatchesIdentity, false);
});

test('CI 해시: identityCiHash가 있으면 그대로, 없으면 ci로 계산한다', () => {
  const a = resolveIdentityBasis(
    { identityVerified: true, name: '홍길동', identityCiHash: 'HASH' },
    '홍길동',
  );
  assert.strictEqual(a.ownerCiHash, 'HASH');
  const b = resolveIdentityBasis(
    { identityVerified: true, name: '홍길동', ci: 'CI원문' },
    '홍길동',
  );
  assert.strictEqual(typeof b.ownerCiHash, 'string');
  assert.strictEqual(b.ownerCiHash.length, 64, 'sha256 hex가 아니다');
});

// ══════════════════════════════════════════════════════════════════════════
// lifecycle — 이전 self 권한이 **잘못 남지 않는가**
// ══════════════════════════════════════════════════════════════════════════

test('생명주기① 본인 명의 최초 인증: self가 붙고 authorizedAt이 찍힌다', () => {
  const { record, mode } = run({}, OK, {}, 0, SELF);
  assert.strictEqual(mode, 'replaced');
  assert.strictEqual(record.status, 'verified');
  assert.strictEqual(record.authorization, 'self');
  assert.strictEqual(record.authorizationReason, null);
  assert.strictEqual(record.authorizedAt, NOW);
});

test('생명주기② 타인 명의 최초 인증: status는 verified인데 권한은 열리지 않는다', () => {
  const { record, mode } = run({}, OK, {}, 0, OTHERS_NAME);
  assert.strictEqual(mode, 'overwritten');
  // 사업자 정보 자체는 국세청에서 확인됐다 — 실패로 기록하면 거짓말이다.
  assert.strictEqual(record.status, 'verified');
  assert.strictEqual(record.verifiedAt, NOW, '확인 시각은 남아야 한다');
  // 그러나 권한은 없다.
  assert.strictEqual(record.authorization, 'pendingOwnerApproval');
  assert.strictEqual(record.authorizationReason, 'representativeMismatch');
  assert.strictEqual(record.authorizedAt, null);
  assert.strictEqual(isBusinessAuthorized(record), false, '권한이 열려버렸다');
});

test('생명주기③ **핵심** — self 보유자가 남의 사업자를 확인해 봐도 기존 권한이 안 뺏긴다', () => {
  // 배우자 명의 사업자를 실수로/시험삼아 넣어 본 경우. 국세청은 통과하지만
  // 권한은 못 얻는다 — 그렇다고 멀쩡히 쓰던 기존 사업자 권한을 뺏으면
  // 그 순간 파티 오픈이 통째로 막힌다.
  const { record, mode } = run(
    verifiedPrev(),
    OK,
    { businessNumber: '9876543210', representativeName: '김철수' },
    0,
    OTHERS_NAME,
  );
  assert.strictEqual(mode, 'keptVerified');
  assert.strictEqual(record.status, undefined, '기존 status를 건드렸다');
  assert.strictEqual(record.authorization, undefined, '기존 권한을 건드렸다');
  assert.strictEqual(record.businessNumber, undefined);
  // 무슨 일이 있었는지는 pendingChange에 남는다.
  assert.strictEqual(record.pendingChange.businessNumber, '9876543210');
  assert.strictEqual(record.pendingChange.authorization, 'pendingOwnerApproval');
  assert.strictEqual(
    record.pendingChange.authorizationReason,
    'representativeMismatch',
  );
});

test('생명주기④ 권한 없는 계정(pendingOwnerApproval)에는 지킬 것이 없다 — 그대로 덮어쓴다', () => {
  const prev = {
    status: 'verified',
    authorization: 'pendingOwnerApproval',
    businessNumber: '1234567890',
    representativeName: '홍길동',
    openingDate: '20200105',
    verifiedAt: '<oldVerifiedAt>',
  };
  const { record, mode } = run(
    prev,
    NOT_REGISTERED,
    { businessNumber: '9876543210' },
    0,
    NO_AUTH,
  );
  assert.strictEqual(mode, 'overwritten');
  assert.strictEqual(record.status, 'failed');
  assert.strictEqual(record.authorization, 'none');
  assert.strictEqual(record.authorizedAt, null);
});

test('생명주기⑤ 번호가 바뀌면 옛 번호의 인증 시각을 물려받지 않는다', () => {
  // 물려받으면 "다른 사업자의 통과 날짜"가 새 사업자에 얹힌다.
  const prev = {
    status: 'verified',
    authorization: 'pendingOwnerApproval',
    businessNumber: '1234567890',
    verifiedAt: '<oldVerifiedAt>',
  };
  const { record } = run(
    prev,
    OK,
    { businessNumber: '9876543210' },
    0,
    OTHERS_NAME,
  );
  assert.strictEqual(record.verifiedAt, NOW, '옛 번호의 시각이 남았다');
});

test('생명주기⑥ 번호가 바뀌었는데 이번엔 실패면 옛 통과 시각을 지운다(merge 잔존 방지)', () => {
  const prev = {
    status: 'failed',
    businessNumber: '1234567890',
    verifiedAt: '<oldVerifiedAt>',
  };
  const { record } = run(prev, NOT_REGISTERED, { businessNumber: '9876543210' });
  assert.strictEqual(record.verifiedAt, null, '다른 사업자의 날짜가 그대로 남는다');
});

test('생명주기⑦ 같은 번호가 폐업으로 나오면 self가 남으면 안 된다', () => {
  const { record, mode } = run(verifiedPrev(), CLOSED, {}, 0, NO_AUTH);
  assert.strictEqual(mode, 'overwritten');
  assert.strictEqual(record.status, 'suspended');
  assert.strictEqual(record.authorization, 'none');
  assert.strictEqual(record.authorizedAt, null);
  assert.strictEqual(isBusinessAuthorized(record), false);
});

test('생명주기⑧ 같은 번호를 다시 인증하면 최초 인증일은 유지하고 권한도 유지된다', () => {
  const { record, mode } = run(verifiedPrev(), OK, {}, 0, SELF);
  assert.strictEqual(mode, 'replaced');
  assert.strictEqual(record.verifiedAt, '<oldVerifiedAt>');
  assert.strictEqual(record.authorization, 'self');
  assert.strictEqual(record.authorizedAt, NOW, '권한 확인 시각은 갱신된다');
});

test('생명주기⑨ 번호를 바꿔 본인 명의로 재인증하면 이력이 남고 권한도 그대로 self', () => {
  const { record, mode, numberChanged } = run(
    verifiedPrev(),
    OK,
    { businessNumber: '9876543210', representativeName: '홍길동' },
    0,
    SELF,
  );
  assert.strictEqual(mode, 'replaced');
  assert.strictEqual(numberChanged, true);
  assert.strictEqual(record.authorization, 'self');
  assert.strictEqual(record.verifiedAt, NOW, '새 사업자의 인증일로 다시 잡힌다');
  assert.strictEqual(record.previousBusinessNumber, '1234567890');
  assert.strictEqual(record.history.length, 1);
});

test('생명주기⑩ API 장애는 권한을 흔들지 않는다 — 모름은 취소 사유가 아니다', () => {
  const { record, mode } = run(verifiedPrev(), API_DOWN, {}, 0, NO_AUTH);
  assert.strictEqual(mode, 'keptVerified');
  assert.strictEqual(record.authorization, undefined, '기존 권한을 건드렸다');
  assert.strictEqual(record.status, undefined);
});

test('불변식: status와 authorization은 **항상 함께** 쓰이거나 둘 다 안 쓰인다', () => {
  // 이 불변식이 깨지면 "status는 새 사업자인데 authorization은 옛 self"가
  // 만들어지고, 그것이 곧 남의 사업자로 권한을 얻는 경로가 된다.
  const scenarios = [
    ['미인증 → 성공', {}, OK, SELF],
    ['미인증 → 타인명의', {}, OK, OTHERS_NAME],
    ['미인증 → 실패', {}, NOT_REGISTERED, NO_AUTH],
    ['미인증 → 보류', {}, API_DOWN, NO_AUTH],
    ['self → 같은번호 성공', verifiedPrev(), OK, SELF],
    ['self → 같은번호 폐업', verifiedPrev(), CLOSED, NO_AUTH],
    ['self → 보류', verifiedPrev(), API_DOWN, NO_AUTH],
    ['pendingOwner → 실패', { status: 'verified', authorization: 'pendingOwnerApproval' }, MISMATCH, NO_AUTH],
  ];
  for (const [label, prev, outcome, decision] of scenarios) {
    for (const input of [{}, { businessNumber: '9876543210' }]) {
      const { record } = run(prev, outcome, input, 0, decision);
      const hasStatus = Object.prototype.hasOwnProperty.call(record, 'status');
      const hasAuth = Object.prototype.hasOwnProperty.call(record, 'authorization');
      assert.strictEqual(
        hasStatus,
        hasAuth,
        `${label} — status(${hasStatus})와 authorization(${hasAuth})이 따로 쓰였다`,
      );
    }
  }
});

test('불변식: 권한이 열린 레코드는 반드시 isBusinessAuthorized를 통과한다', () => {
  const { record } = run({}, OK, {}, 0, SELF);
  assert.strictEqual(isBusinessAuthorized(record), true);
  // 반대로, 권한을 주지 않은 어떤 레코드도 통과해서는 안 된다.
  for (const decision of [OTHERS_NAME, NO_AUTH]) {
    for (const outcome of [OK, MISMATCH, CLOSED, API_DOWN]) {
      const r = run({}, outcome, {}, 0, decision).record;
      assert.strictEqual(
        isBusinessAuthorized(r),
        false,
        `권한 없는 판정(${decision.authorization}/${outcome.status})이 통과했다`,
      );
    }
  }
});

// ══════════════════════════════════════════════════════════════════════════
// 사업자번호 점유 — 동시 요청(race)까지 재현한다
//
// "where로 훑어보고 없으면 쓴다"는 중복을 막지 못한다(두 사람이 동시에
// 조회하면 둘 다 '없음'을 본다). 그래서 아래 가짜 Firestore는 **읽은 문서가
// 그 사이 바뀌면 커밋을 거부하고 재시도**시켜, 진짜 Firestore의 낙관적
// 동시성을 그대로 흉내낸다.
// ══════════════════════════════════════════════════════════════════════════

/**
 * Firestore `set(..., { merge: true })`의 **재귀 병합**을 그대로 흉내낸다.
 *
 * ⚠️ 얕은 병합(`{ ...기존, ...새값 }`)으로 두면 안 된다. 이 파일이 검사하는
 *    businessVerification은 **중첩 맵**이라, 그 맵 하나만 담은 부분 저장이
 *    얕은 병합에서는 나머지 필드를 통째로 날려버린다. 그러면 keptVerified
 *    갈래("기존 인증을 그대로 둔다")를 검증할 수 없을 뿐 아니라, 더 나쁘게는
 *    **가짜 DB에서만 일어나는 일을 진짜 동작으로 읽게 된다.**
 *
 * 규칙(실제 Firestore와 같다):
 *   · 양쪽 모두 맵이면 재귀 병합
 *   · 그 외(null·배열·스칼라)는 새 값이 덮어쓴다 — `pendingChange: null`이
 *     기존 맵을 지우는 것이 이 규칙이다
 */
function deepMerge(base, patch) {
  const isMap = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
  const out = { ...(base || {}) };
  for (const [k, v] of Object.entries(patch)) {
    out[k] = isMap(v) && isMap(out[k]) ? deepMerge(out[k], v) : v;
  }
  return out;
}

function makeDb(seed = {}) {
  const store = new Map(Object.entries(seed));
  const key = (path, id) => `${path}/${id}`;
  const docRef = (path, id) => ({ path, id, __key: key(path, id) });
  return {
    __store: store,
    collection: (path) => ({ doc: (id) => docRef(path, id) }),
    async runTransaction(fn, { maxAttempts = 5 } = {}) {
      for (let attempt = 1; ; attempt += 1) {
        const reads = [];
        const writes = [];
        const tx = {
          async get(ref) {
            const data = store.get(ref.__key);
            reads.push([ref.__key, data !== undefined]);
            return {
              exists: data !== undefined,
              data: () => data,
              get: (f) => (data ? data[f] : undefined),
            };
          },
          set(ref, value, opts) {
            writes.push([ref.__key, value, opts]);
          },
        };
        const result = await fn(tx);
        // 낙관적 동시성 — 읽은 문서가 그 사이 생기거나 사라졌으면 커밋 거부.
        const conflict = reads.some(([k, existed]) => store.has(k) !== existed);
        if (conflict) {
          if (attempt >= maxAttempts) throw new Error('ABORTED: 재시도 한계');
          continue; // 진짜 Firestore처럼 처음부터 다시 실행한다
        }
        for (const [k, value, opts] of writes) {
          store.set(
            k,
            opts && opts.merge ? deepMerge(store.get(k), value) : value,
          );
        }
        return result;
      }
    },
  };
}

const BNO_A = '1234567890';
const BNO_B = '9876543210';
const ownerKey = (bNo) => `${BUSINESS_OWNERSHIP}/${businessNumberHash(bNo)}`;

const apply = (db, uid, { outcome = OK, bNo = BNO_A, nameMatches = true, ciHash = 'CI_' + uid } = {}) =>
  applyVerificationOutcome(db, {
    uid,
    outcome,
    input: inputOf({ businessNumber: bNo }),
    nameMatchesIdentity: nameMatches,
    ownerCiHash: ciHash,
    masked: '123*******',
    todayKey: TODAY,
  });

test('점유① 본인 명의로 통과하면 점유 문서가 생기고 users에 self가 쓰인다', async () => {
  const db = makeDb();
  const r = await apply(db, 'uidA');
  assert.strictEqual(r.decision.authorization, 'self');
  const owner = db.__store.get(ownerKey(BNO_A));
  assert.ok(owner, '점유 문서가 생기지 않았다');
  assert.strictEqual(owner.holderUid, 'uidA');
  assert.strictEqual(owner.status, OWNERSHIP_STATUS.active);
  assert.strictEqual(owner.representativeCiHash, 'CI_uidA');
  // 등급은 값과 **반드시 함께** 적힌다 — 떨어지면 읽는 쪽이 최대치로 오해한다.
  assert.strictEqual(
    owner.representativeVerificationLevel,
    REP_VERIFICATION_LEVEL.nameMatched,
    'self 점유가 이름 대조보다 강한 등급으로 기록됐다',
  );
  assert.strictEqual(owner.representativeSource, 'selfClaim');
  assert.strictEqual(
    db.__store.get('users/uidA').businessVerification.authorization,
    'self',
  );
});

test('점유② **race** — 동시에 같은 사업자번호를 잡으면 한쪽만 self가 된다', async () => {
  const db = makeDb();
  const [a, b] = await Promise.all([apply(db, 'uidA'), apply(db, 'uidB')]);
  const auths = [a.decision.authorization, b.decision.authorization].sort();
  assert.deepStrictEqual(
    auths,
    ['pendingOwnerApproval', 'self'],
    `둘 다 권한을 가져갔다 (${auths.join(', ')})`,
  );
  // 진 쪽이 걸리는 이유는 **대표자 CI 충돌**이다 — 이긴 쪽의 CI가 먼저
  // 적히면서, 같은 이름이어도 다른 자연인은 자동 처리가 멈춘다.
  // (이긴 쪽이 진짜 대표자라는 뜻은 아니다 — 둘 다 이름 대조뿐이다.)
  const loser = a.decision.authorization === 'self' ? b : a;
  assert.strictEqual(
    loser.decision.authorizationReason,
    AUTH_REASON.representativeCiMismatch,
  );
});

test('점유③ race 후 점유 문서는 정확히 한 개이고, 주인은 이긴 쪽이다', async () => {
  const db = makeDb();
  const [a, b] = await Promise.all([apply(db, 'uidA'), apply(db, 'uidB')]);
  const ownerDocs = [...db.__store.keys()].filter((k) =>
    k.startsWith(BUSINESS_OWNERSHIP + '/'),
  );
  assert.strictEqual(ownerDocs.length, 1, `점유 문서가 ${ownerDocs.length}개다`);
  const winner = a.decision.authorization === 'self' ? 'uidA' : 'uidB';
  assert.strictEqual(db.__store.get(ownerKey(BNO_A)).holderUid, winner);
  // 진 쪽의 users 문서에도 권한이 열려 있으면 안 된다.
  const loser = winner === 'uidA' ? 'uidB' : 'uidA';
  assert.strictEqual(
    isBusinessAuthorized(db.__store.get('users/' + loser).businessVerification),
    false,
    '진 쪽에 권한이 남았다',
  );
});

test('점유④ 이미 점유된 번호를 나중에 입력하면 자동 승인되지 않는다', async () => {
  const db = makeDb();
  await apply(db, 'uidA');
  const r = await apply(db, 'uidB');
  assert.strictEqual(r.decision.authorization, 'pendingOwnerApproval');
  assert.strictEqual(
    r.decision.authorizationReason,
    AUTH_REASON.representativeCiMismatch,
    '동명이인은 CI 핀에서 걸려야 한다',
  );
  assert.strictEqual(db.__store.get(ownerKey(BNO_A)).holderUid, 'uidA', '점유가 넘어갔다');
});

test('점유⑤ 대표자명이 다르면 점유 문서를 만들지 않는다 — 선점 차단', async () => {
  // 만들어 버리면 남의 사업자번호를 미리 잡아 실제 대표자의 자동승인을
  // 막을 수 있다(서비스 거부).
  const db = makeDb();
  const r = await apply(db, 'uidA', { nameMatches: false });
  assert.strictEqual(r.decision.authorization, 'pendingOwnerApproval');
  assert.strictEqual(db.__store.get(ownerKey(BNO_A)), undefined, '선점됐다');
  // 실제 대표자는 그대로 자동승인된다.
  const real = await apply(db, 'uidB', { nameMatches: true });
  assert.strictEqual(real.decision.authorization, 'self');
});

test('점유⑥ 국세청을 통과하지 못하면 점유 문서를 만들지 않는다', async () => {
  const db = makeDb();
  for (const outcome of [MISMATCH, NOT_REGISTERED, API_DOWN, CLOSED]) {
    const r = await apply(db, 'uidA', { outcome });
    assert.strictEqual(r.decision.claimOwnership, false);
  }
  assert.strictEqual(db.__store.get(ownerKey(BNO_A)), undefined);
});

test('점유⑦ 같은 계정이 다시 인증하면 점유를 유지하고 최초 점유 시각도 유지한다', async () => {
  const db = makeDb();
  await apply(db, 'uidA');
  db.__store.get(ownerKey(BNO_A)).claimedAt = '<firstClaim>';
  const r = await apply(db, 'uidA');
  assert.strictEqual(r.decision.authorization, 'self');
  assert.strictEqual(db.__store.get(ownerKey(BNO_A)).claimedAt, '<firstClaim>');
});

test('점유⑧ 번호를 바꿔 재인증하면 옛 번호를 놓아주고 새 번호를 점유한다', async () => {
  const db = makeDb();
  await apply(db, 'uidA', { bNo: BNO_A });
  await apply(db, 'uidA', { bNo: BNO_B });
  const oldOwner = db.__store.get(ownerKey(BNO_A));
  assert.strictEqual(oldOwner.status, OWNERSHIP_STATUS.released, '옛 번호를 계속 잡고 있다');
  assert.strictEqual(oldOwner.releasedFromUid, 'uidA');
  assert.strictEqual(db.__store.get(ownerKey(BNO_B)).holderUid, 'uidA');
});

test('점유⑨ 놓아준 번호는 **같은 자연인**이 다시 잡을 수 있다(탈퇴 후 재가입 등)', async () => {
  const db = makeDb();
  await apply(db, 'uidA', { bNo: BNO_A });
  await apply(db, 'uidA', { bNo: BNO_B }); // A가 BNO_A를 놓아준다
  // 같은 사람(CI 동일)이 새 계정으로 다시 잡는다.
  const r = await apply(db, 'uidA2', { bNo: BNO_A, ciHash: 'CI_uidA' });
  assert.strictEqual(r.decision.authorization, 'self');
  const owner = db.__store.get(ownerKey(BNO_A));
  assert.strictEqual(owner.holderUid, 'uidA2');
  assert.strictEqual(owner.status, OWNERSHIP_STATUS.active);
  assert.strictEqual(owner.releasedAt, null, 'released 흔적이 남았다');
  assert.strictEqual(owner.releasedFromUid, null);
});

test('점유⑩ 놓아준 번호라도 **다른 자연인**은 이어받지 못한다 — CI 핀은 release로 풀리지 않는다', async () => {
  // 계정 점유는 풀려도 "이 사업자에 대해 누가 대표자라고 주장했는가"는
  // 남는다 — 그 기록이 있어야 다른 CI가 들어올 때 충돌을 알아챌 수 있다.
  const db = makeDb();
  await apply(db, 'uidA', { bNo: BNO_A });
  await apply(db, 'uidA', { bNo: BNO_B });
  const r = await apply(db, 'uidB', { bNo: BNO_A }); // 이름은 같고 CI는 다르다
  assert.strictEqual(r.decision.authorization, 'pendingOwnerApproval');
  assert.strictEqual(
    r.decision.authorizationReason,
    AUTH_REASON.representativeCiMismatch,
  );
  assert.strictEqual(db.__store.get(ownerKey(BNO_A)).holderUid, 'uidA');
});

test('점유⑪ 남의 점유는 절대 놓아주지 않는다', async () => {
  const db = makeDb();
  await apply(db, 'uidA', { bNo: BNO_A }); // A가 BNO_A 점유
  // B가 BNO_A를 시도했다가 막히고(pendingOwnerApproval, 문서에는 BNO_A가 남는다),
  // 이어서 자기 명의 BNO_B로 성공한다.
  await apply(db, 'uidB', { bNo: BNO_A });
  await apply(db, 'uidB', { bNo: BNO_B });
  assert.strictEqual(
    db.__store.get(ownerKey(BNO_A)).status,
    OWNERSHIP_STATUS.active,
    'B가 A의 점유를 놓아버렸다',
  );
  assert.strictEqual(db.__store.get(ownerKey(BNO_A)).holderUid, 'uidA');
});

test('점유⑫ 권한을 못 얻은 시도도 하루 시도 횟수에는 그대로 센다', async () => {
  const db = makeDb();
  await apply(db, 'uidA', { nameMatches: false });
  await apply(db, 'uidA', { nameMatches: false });
  const bv = db.__store.get('users/uidA').businessVerification;
  assert.strictEqual(bv.attemptDate, TODAY);
  assert.strictEqual(bv.attemptCount, 2);
});

test('가짜 DB: merge 저장은 중첩 맵을 재귀 병합한다(실제 Firestore와 같게)', () => {
  // 이 성질이 깨지면 아래 keptVerified 검사가 통과해도 아무 의미가 없다.
  assert.deepStrictEqual(
    deepMerge({ a: { x: 1, y: 2 }, b: 3 }, { a: { y: 9 } }),
    { a: { x: 1, y: 9 }, b: 3 },
  );
  // null은 맵을 덮어쓴다 — pendingChange: null이 기존 맵을 지우는 규칙.
  assert.deepStrictEqual(deepMerge({ a: { x: 1 } }, { a: null }), { a: null });
});

test('keptVerified 전 구간 — 남의 사업자를 확인해 봐도 문서에 A만 남는다', async () => {
  // 1단계에서 순수 함수로만 확인하던 것을 **저장까지 태워서** 확인한다.
  // (가짜 DB가 얕은 병합이던 동안에는 이 검사를 쓸 수 없었다.)
  const db = makeDb();
  await apply(db, 'uidA', { bNo: BNO_A }); // A를 본인 명의로
  const r = await apply(db, 'uidA', { bNo: BNO_B, nameMatches: false });
  assert.strictEqual(r.mode, 'keptVerified');

  const bv = db.__store.get('users/uidA').businessVerification;
  // 최상위는 전부 A 그대로.
  assert.strictEqual(bv.status, 'verified');
  assert.strictEqual(bv.authorization, 'self');
  assert.strictEqual(bv.businessNumber, BNO_A);
  assert.strictEqual(isBusinessAuthorized(bv), true, '기존 권한이 사라졌다');
  // B는 pendingChange 안에만, 권한 판정까지 함께.
  assert.strictEqual(bv.pendingChange.businessNumber, BNO_B);
  assert.strictEqual(bv.pendingChange.authorization, 'pendingOwnerApproval');
  // B는 점유하지 않는다.
  assert.strictEqual(db.__store.get(ownerKey(BNO_B)), undefined);
  assert.strictEqual(db.__store.get(ownerKey(BNO_A)).holderUid, 'uidA');
});

test('점유⑬ 동시 시도의 시도 횟수가 사라지지 않는다(트랜잭션 안에서 다시 센다)', async () => {
  const db = makeDb();
  await Promise.all([
    apply(db, 'uidA', { bNo: BNO_A }),
    apply(db, 'uidA', { bNo: BNO_A }),
  ]);
  assert.strictEqual(
    db.__store.get('users/uidA').businessVerification.attemptCount,
    2,
    '동시 요청 하나가 통째로 사라졌다',
  );
});

(async () => {
  let failed = 0;
  for (const [name, fn] of cases) {
    try {
      await fn();
      console.log(`  ✓ ${name}`);
    } catch (e) {
      failed += 1;
      console.error(`  ✗ ${name}\n    ${e.message}`);
    }
  }
  console.log(
    failed === 0
      ? `\n사업자 인증 판정 규칙 검증 통과 — ${cases.length}건`
      : `\n실패 ${failed}건 / 전체 ${cases.length}건`,
  );
  process.exit(failed === 0 ? 0 : 1);
})();

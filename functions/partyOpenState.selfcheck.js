// 파티 오픈 상태 규칙 자체 검증 — `npm run check:openstate`.
//
// 여기서 못 박는 것은 세 가지다.
// 1. **기존 파티 무영향.** openState 필드가 없는 문서는 무조건 'open'이다.
//    이게 깨지면 운영 중인 파티가 전부 신청 불가가 된다.
// 2. **정책이 꺼져 있으면 미인증 호스트는 못 연다.** UI 버튼을 숨기는 것과
//    별개로 서버 판정이 막아야 한다.
// 3. **날짜 미정인 채로는 못 연다.** 오픈예정은 날짜 없이 등록할 수 있지만,
//    실제 오픈에는 날짜가 확정돼 있어야 한다.

process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'selfcheck';

const assert = require('assert');
const {
  openStateOf,
  isPreopen,
  missingFieldsForOpen,
  evaluateOpenPermission,
  evaluatePartyCreatePermission,
} = require('./partyOpenState');

const cases = [];
const test = (name, fn) => cases.push([name, fn]);

const COMPLETE = {
  title: '금요일 와인 파티',
  address: '서울 마포구 어울마당로 1',
  partyDateTime: new Date('2026-09-01T19:00:00+09:00'),
  people: 12,
};

// ── 기존 파티 무영향 ─────────────────────────────────────────────────────────

test('openState 필드가 없으면 open으로 간주한다 — 기존 운영 데이터 보호', () => {
  assert.strictEqual(openStateOf({}), 'open');
  assert.strictEqual(openStateOf({ recruitStatus: '모집중' }), 'open');
  assert.strictEqual(isPreopen({}), false);
});

test('알 수 없는 값도 open으로 떨어진다 — 오타로 파티가 잠기면 안 된다', () => {
  assert.strictEqual(openStateOf({ openState: 'OPEN' }), 'open');
  assert.strictEqual(openStateOf({ openState: null }), 'open');
});

test('preopen만 정확히 preopen이다', () => {
  assert.strictEqual(openStateOf({ openState: 'preopen' }), 'preopen');
  assert.strictEqual(isPreopen({ openState: 'preopen' }), true);
});

// ── 오픈 권한 ────────────────────────────────────────────────────────────────

test('사업자 인증 호스트는 정책값과 무관하게 오픈할 수 있다', () => {
  assert.strictEqual(
    evaluateOpenPermission({ businessVerified: true, individualHostOpeningEnabled: false }).allowed,
    true,
  );
});

test('미인증 호스트는 정책이 꺼져 있으면 오픈할 수 없다', () => {
  const r = evaluateOpenPermission({ businessVerified: false, individualHostOpeningEnabled: false });
  assert.strictEqual(r.allowed, false);
  assert.strictEqual(r.reason, 'individualHostOpeningDisabled');
});

test('정책이 켜지면 미인증 호스트도 오픈할 수 있다', () => {
  assert.strictEqual(
    evaluateOpenPermission({ businessVerified: false, individualHostOpeningEnabled: true }).allowed,
    true,
  );
});

test('정책값이 없거나 true가 아니면 잠긴 것으로 본다', () => {
  assert.strictEqual(
    evaluateOpenPermission({ businessVerified: false, individualHostOpeningEnabled: undefined }).allowed,
    false,
  );
  assert.strictEqual(
    evaluateOpenPermission({ businessVerified: false, individualHostOpeningEnabled: 'true' }).allowed,
    false,
    '문자열 true는 true가 아니다',
  );
});

// ── 생성 권한 ────────────────────────────────────────────────────────────────
//
// 오픈 권한과 **다른 질문**이다 — 이쪽은 "파티를 만들 수 있는가"다. 정책 키도
// 다르다(individualHostPartyCreateEnabled). 두 판정이 한 키를 공유하면
// "만들 수는 있는데 못 여는" 중간 단계를 표현할 수 없다.

test('사업자 인증 호스트는 정책값과 무관하게 파티를 만들 수 있다', () => {
  assert.strictEqual(
    evaluatePartyCreatePermission({
      businessVerified: true,
      individualHostPartyCreateEnabled: false,
    }).allowed,
    true,
  );
});

test('개인 호스트는 정책이 꺼져 있으면 파티를 만들 수 없다', () => {
  const r = evaluatePartyCreatePermission({
    businessVerified: false,
    individualHostPartyCreateEnabled: false,
  });
  assert.strictEqual(r.allowed, false);
  assert.strictEqual(r.reason, 'individualHostPartyCreateDisabled');
});

test('정책이 켜지면 개인 호스트도 파티를 만들 수 있다', () => {
  assert.strictEqual(
    evaluatePartyCreatePermission({
      businessVerified: false,
      individualHostPartyCreateEnabled: true,
    }).allowed,
    true,
  );
});

test('생성 정책값이 없거나 true가 아니면 잠긴 것으로 본다', () => {
  assert.strictEqual(
    evaluatePartyCreatePermission({
      businessVerified: false,
      individualHostPartyCreateEnabled: undefined,
    }).allowed,
    false,
  );
  assert.strictEqual(
    evaluatePartyCreatePermission({
      businessVerified: false,
      individualHostPartyCreateEnabled: 'true',
    }).allowed,
    false,
    '문자열 true는 true가 아니다',
  );
});

// ── 필수정보 ─────────────────────────────────────────────────────────────────

test('필수정보가 다 있으면 빠진 항목이 없다', () => {
  assert.deepStrictEqual(missingFieldsForOpen(COMPLETE), []);
});

test('dateTbd가 남아 있으면 날짜 미완성으로 막는다', () => {
  const missing = missingFieldsForOpen({ ...COMPLETE, dateTbd: true });
  assert.ok(missing.includes('파티 날짜'));
});

test('날짜 없는 오픈예정 파티는 그대로 오픈할 수 없다', () => {
  const { partyDateTime, ...noDate } = COMPLETE;
  assert.ok(missingFieldsForOpen(noDate).includes('파티 날짜'));
});

test('정기 파티는 partyDateTime 없이도 요일 스케줄로 날짜가 확정된 것으로 본다', () => {
  const { partyDateTime, ...rest } = COMPLETE;
  const recurring = {
    ...rest,
    scheduleType: 'recurring',
    recurringDays: [1, 3],
    recurringStartTime: '19:00',
  };
  assert.ok(!missingFieldsForOpen(recurring).includes('파티 날짜'));
});

test('파티명·장소·인원이 빠지면 각각 잡아낸다', () => {
  const missing = missingFieldsForOpen({ ...COMPLETE, title: '   ', address: '', people: 0 });
  assert.ok(missing.includes('파티명'));
  assert.ok(missing.includes('장소'));
  assert.ok(missing.includes('모집 인원'));
});

test('도로명/지번 주소만 있어도 장소는 채워진 것으로 본다', () => {
  const { address, ...rest } = COMPLETE;
  assert.ok(!missingFieldsForOpen({ ...rest, roadAddress: '서울 마포구 어울마당로 1' }).includes('장소'));
});

test('maxParticipants로만 인원이 잡힌 옛 문서도 통과한다', () => {
  const { people, ...rest } = COMPLETE;
  assert.ok(!missingFieldsForOpen({ ...rest, maxParticipants: 8 }).includes('모집 인원'));
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
    ? `\n파티 오픈 상태 규칙 검증 통과 — ${cases.length}건`
    : `\n실패 ${failed}건 / 전체 ${cases.length}건`,
);
process.exit(failed === 0 ? 0 : 1);

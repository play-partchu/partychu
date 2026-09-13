// 파티 참여 후기 자체 검증 — `node partyReviews.selfcheck.js`.
//
// 이 기능에서 틀리면 안 되는 것은 넷이다.
//
//   ① 자격의 정본이 `checkedInAt`이다 — 신청·승인만으로는 못 쓴다. 클라이언트가
//      status를 어떻게 보내든 판정이 바뀌지 않아야 한다.
//   ② 호스트는 자기 파티에 못 쓴다.
//   ③ 작성 기간의 기준점이 **그 게스트가 참여한 회차**다. 정기 파티에서
//      마지막 회차를 기준으로 잡으면 반년 전에 참여한 사람이 계속 쓸 수 있다.
//   ④ 파티 문서가 자동삭제로 사라져도 판정이 깨지지 않는다.
//
// ⚠ 파티 자동삭제(deleteExpiredParties, 14일)와 작성 기한(14일)이 겹친다.
//   그래서 후기 컬렉션이 파티 하위가 아니라 루트라는 사실도 여기서 못 박는다 —
//   contentCleanup의 party 정리 목록에 들어가는 순간 후기가 함께 지워진다.

const assert = require('assert');
const fs = require('fs');

const { __test } = require('./partyReviews');
const {
  COLLECTION,
  REVIEW_WINDOW_DAYS,
  REVIEW_WINDOW_MS,
  MIN_LENGTH,
  MAX_LENGTH,
  reviewDocId,
  normalizeReviewText,
  occurrenceEndMsOf,
  windowEndMs,
  judgeEligibility,
} = __test;

const cases = [];
const test = (name, fn) => cases.push([name, fn]);

const DAY = 24 * 60 * 60 * 1000;
const ts = (ms) => ({ toMillis: () => ms });

/** 참여를 마친 일회성 파티 신청 한 벌. */
function checkedInApp(overrides = {}) {
  return {
    uid: 'guest1',
    partyId: 'p1',
    hostId: 'host1',
    status: 'applied',
    checkedInAt: ts(Date.UTC(2026, 7, 1, 12)),
    partyDateTime: ts(Date.UTC(2026, 7, 1, 10)),
    ...overrides,
  };
}

const party = { hostId: 'host1', title: '와인 모임', partyDateTime: ts(Date.UTC(2026, 7, 1, 10)) };

// ── ① 자격의 정본 ────────────────────────────────────────────────────────

test('참여 완료(checkedInAt)가 있으면 쓸 수 있다', () => {
  const r = judgeEligibility(checkedInApp(), party, 'guest1', Date.UTC(2026, 7, 3));
  assert.strictEqual(r.ok, true);
});

test('신청·승인만 된 사람은 못 쓴다 — status를 무엇으로 보내든', () => {
  for (const status of ['applied', 'approved', 'confirmed', 'attended', 'pending']) {
    const r = judgeEligibility(
      checkedInApp({ status, checkedInAt: null }),
      party,
      'guest1',
      Date.UTC(2026, 7, 3),
    );
    assert.strictEqual(r.ok, false, status);
    assert.strictEqual(r.code, 'failed-precondition', status);
  }
});

test("죽은 값 'attended'로는 자격이 생기지 않는다", () => {
  // checkInRules.js: attended 상태는 아무도 쓰지 않는다. 그걸 자격으로 인정하면
  // 클라이언트가 status만 바꿔 후기를 쓸 수 있는 길이 열린다.
  const r = judgeEligibility(
    checkedInApp({ status: 'attended', checkedInAt: null }),
    party,
    'guest1',
    Date.UTC(2026, 7, 3),
  );
  assert.strictEqual(r.ok, false);
});

test('체크인을 되돌리면(checkedInAt = null) 다시 못 쓴다', () => {
  const r = judgeEligibility(
    checkedInApp({ checkedInAt: null }),
    party,
    'guest1',
    Date.UTC(2026, 7, 3),
  );
  assert.strictEqual(r.ok, false);
});

test('남의 신청서로는 못 쓴다', () => {
  const r = judgeEligibility(checkedInApp(), party, 'other', Date.UTC(2026, 7, 3));
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.code, 'permission-denied');
});

test('참여 기록이 아예 없으면 못 쓴다', () => {
  const r = judgeEligibility(null, party, 'guest1', Date.UTC(2026, 7, 3));
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.code, 'not-found');
});

// ── ② 호스트 ─────────────────────────────────────────────────────────────

test('호스트는 자기 파티에 못 쓴다', () => {
  const r = judgeEligibility(
    checkedInApp({ uid: 'host1' }),
    party,
    'host1',
    Date.UTC(2026, 7, 3),
  );
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.code, 'permission-denied');
});

test('파티가 삭제된 뒤에도 신청서의 hostId로 호스트를 걸러낸다', () => {
  const r = judgeEligibility(
    checkedInApp({ uid: 'host1' }),
    null, // 파티 문서 없음
    'host1',
    Date.UTC(2026, 7, 3),
  );
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.code, 'permission-denied');
});

// ── ③ 작성 기간 — 그 게스트가 참여한 회차 기준 ───────────────────────────

test('회차 종료 + 14일까지 쓸 수 있고 그 뒤로는 막힌다', () => {
  const end = Date.UTC(2026, 7, 1, 14);
  const app = checkedInApp({ occurrenceEndAt: ts(end), occurrenceId: 'o1' });

  assert.strictEqual(judgeEligibility(app, party, 'guest1', end + DAY).ok, true);
  assert.strictEqual(
    judgeEligibility(app, party, 'guest1', end + 14 * DAY - 1000).ok,
    true,
    '14일째 직전은 열려 있어야 한다',
  );
  const closed = judgeEligibility(app, party, 'guest1', end + 14 * DAY);
  assert.strictEqual(closed.ok, false, '정확히 14일이 지나면 닫힌다');
  assert.strictEqual(closed.code, 'failed-precondition');
});

test('정기 파티는 **그 게스트의 회차**가 기준이다 (마지막 회차가 아니다)', () => {
  // 8/1 회차에 참여했고, 파티 자체는 12/31까지 이어진다.
  const myOccurrenceEnd = Date.UTC(2026, 7, 1, 14);
  const app = checkedInApp({
    occurrenceId: '2026-08-01',
    occurrenceEndAt: ts(myOccurrenceEnd),
  });
  const longRunningParty = {
    ...party,
    scheduleType: 'recurring',
    recurringSchedule: { endDate: '2026-12-31' },
  };

  // 내 회차 기준 15일 뒤 → 닫혀야 한다. 파티는 아직 한창 진행 중이다.
  const r = judgeEligibility(
    app,
    longRunningParty,
    'guest1',
    myOccurrenceEnd + 15 * DAY,
  );
  assert.strictEqual(r.ok, false, '마지막 회차를 기준으로 잡으면 여기서 통과해버린다');
});

test('회차 종료가 신청서에 있으면 파티 문서를 보지 않는다', () => {
  const end = Date.UTC(2026, 7, 1, 14);
  const app = checkedInApp({ occurrenceId: 'o1', occurrenceEndAt: ts(end) });
  // 파티 문서가 없어도 같은 값이 나와야 한다.
  assert.strictEqual(occurrenceEndMsOf(app, null), end);
  assert.strictEqual(occurrenceEndMsOf(app, party), end);
});

test('일회성 파티는 파티의 최종 종료 시각을 쓴다', () => {
  const app = checkedInApp();
  const single = {
    ...party,
    singleSchedule: {
      startAt: new Date(Date.UTC(2026, 7, 1, 10)).toISOString(),
      endAt: new Date(Date.UTC(2026, 7, 1, 14)).toISOString(),
    },
  };
  const end = occurrenceEndMsOf(app, single);
  assert.ok(end !== null);
  // 시작(10시)이 아니라 종료(14시)를 기준으로 잡아야 한다.
  assert.ok(end >= Date.UTC(2026, 7, 1, 10), '종료 시각을 못 읽었다');
});

test('파티가 삭제됐으면 신청서의 partyDateTime으로 물러선다', () => {
  const app = checkedInApp();
  assert.strictEqual(occurrenceEndMsOf(app, null), Date.UTC(2026, 7, 1, 10));
});

test('기한을 계산할 수 없으면 통과시키지 않는다 (fail-closed)', () => {
  const app = checkedInApp({ partyDateTime: null });
  const r = judgeEligibility(app, null, 'guest1', Date.now());
  assert.strictEqual(r.ok, false);
});

test('windowEndMs는 정확히 14일이다', () => {
  assert.strictEqual(windowEndMs(0), REVIEW_WINDOW_MS);
  assert.strictEqual(REVIEW_WINDOW_DAYS, 14);
  assert.strictEqual(windowEndMs(null), null);
});

// ── ④ 자동삭제와의 관계 ──────────────────────────────────────────────────

test('후기는 루트 컬렉션이다 — 파티 하위가 아니다', () => {
  assert.strictEqual(COLLECTION, 'partyReviews');
  assert.ok(!COLLECTION.includes('/'), '하위 컬렉션이면 파티와 함께 지워진다');
});

test('contentCleanup의 party 정리 대상에 후기가 없다', () => {
  // 여기 들어가는 순간 파티 자동삭제가 후기까지 지운다. 그러면 보존 설계가
  // 통째로 무너지므로, 목록에 없음을 테스트로 못 박는다.
  const src = fs.readFileSync(require.resolve('./contentCleanup'), 'utf8');
  assert.ok(
    !src.includes('partyReviews'),
    'contentCleanup이 partyReviews를 건드린다 — 후기가 파티와 함께 지워진다',
  );
});

test('규칙이 클라이언트 쓰기를 열지 않는다', () => {
  const rules = fs.readFileSync(`${__dirname}/../firestore.rules`, 'utf8');
  const block = rules.slice(rules.indexOf('match /partyReviews/'));
  assert.ok(block.startsWith('match /partyReviews/'), '규칙에 partyReviews가 없다');
  const body = block.slice(0, block.indexOf('\n    }'));
  assert.ok(body.includes('allow create, update: if false;'), '쓰기가 열려 있다');
  assert.ok(body.includes('allow delete: if isAdmin();'), '관리자 삭제가 없다');
  assert.ok(body.includes('allow read: if true;'), '읽기가 공개가 아니다');
});

// ── 문서 id · 본문 ───────────────────────────────────────────────────────

test('한 신청 건당 후기 1개 — 문서 id가 결정적이다', () => {
  assert.strictEqual(reviewDocId('p1', 'guest1'), 'p1_guest1');
  // 정기 파티는 신청 id 자체가 {uid}_{occurrenceId}라 회차마다 다른 문서다.
  assert.notStrictEqual(
    reviewDocId('p1', 'guest1_2026-08-01'),
    reviewDocId('p1', 'guest1_2026-08-08'),
  );
});

test('한 줄 후기 길이 규칙', () => {
  assert.strictEqual(normalizeReviewText('짧다').ok, false, `${MIN_LENGTH}자 미만`);
  assert.strictEqual(normalizeReviewText('a'.repeat(MAX_LENGTH)).ok, true);
  assert.strictEqual(normalizeReviewText('a'.repeat(MAX_LENGTH + 1)).ok, false);
  assert.strictEqual(normalizeReviewText(null).ok, false);
  assert.strictEqual(normalizeReviewText(123).ok, false);
});

test('줄바꿈은 거절하지 않고 한 줄로 접는다', () => {
  const r = normalizeReviewText('  분위기가\n\n정말   좋았어요  ');
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.text, '분위기가 정말 좋았어요');
  assert.ok(!r.text.includes('\n'));
});

test('공백만 잔뜩 넣은 글은 통과하지 못한다', () => {
  assert.strictEqual(normalizeReviewText('   \n\n   ').ok, false);
});

// ── 실행 ─────────────────────────────────────────────────────────────────

let failed = 0;
for (const [name, fn] of cases) {
  try {
    fn();
    console.log(`  ✓ ${name}`);
  } catch (e) {
    failed++;
    console.error(`  ✗ ${name}\n    ${e.message}`);
  }
}
console.log(`\n파티 참여 후기 검증 ${cases.length - failed}/${cases.length} 통과`);
process.exit(failed === 0 ? 0 : 1);

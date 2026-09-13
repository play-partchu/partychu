// 취소 대상 신청 문서 고르기 자체 검증 — `npm run check:canceltarget`.
//
// 여기서 지켜야 하는 것은 두 줄이다.
//   · 구버전 앱(회차 미지정)도 **살아 있는 신청이 유일하면** 취소된다
//   · 살아 있는 신청이 여럿이면 **아무것도 취소하지 않는다** — 회차를 지정하게 한다
//
// 두 번째 줄이 이 파일의 존재 이유다. "회차를 못 보내니 살아 있는 것 아무거나
// 취소하자"로 가면, 8/22를 취소하려던 사람의 8/29 신청이 조용히 사라진다.

process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'selfcheck';

const assert = require('assert');
const {
  LIVE_APPLICATION_STATUSES,
  needsCandidateLookup,
  resolveCancelTarget,
} = require('./partyApplicationTargets');

const cases = [];
const test = (name, fn) => cases.push([name, fn]);

const UID = 'u1';
const OCC_A = '2026-08-16';
const OCC_B = '2026-08-23';

/** 신청 문서 한 장 — 실제 문서 id 규칙(uid / uid_회차)을 그대로 쓴다. */
const app = (occurrenceId, status, extra = {}) => ({
  id: occurrenceId ? `${UID}_${occurrenceId}` : UID,
  data: { uid: UID, status, ...(occurrenceId ? { occurrenceId } : {}), ...extra },
});
/** 회차가 붙기 전의 옛 문서 — id는 uid인데 occurrenceId 필드만 있는 경우도 있다. */
const legacyApp = (status, occurrenceId = null) => ({
  id: UID,
  data: { uid: UID, status, ...(occurrenceId ? { occurrenceId } : {}) },
});

// ── ① 회차를 지정한 요청 ────────────────────────────────────────────────

test('회차 지정 — 그 회차 문서가 있으면 그 문서', () => {
  const r = resolveCancelTarget({
    occurrenceId: OCC_A,
    scoped: app(OCC_A, 'applied'),
    legacy: legacyApp('cancelled', '2026-08-15'),
    activeCandidates: null,
  });
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.target.id, `${UID}_${OCC_A}`);
});

test('회차 지정 — 회차 문서가 이미 취소됐어도 그 문서를 돌려준다(이유는 호출부가 말한다)', () => {
  // 여기서 not-found로 바꾸면 '이미취소' 대신 '신청 내역 없음'이 떠서
  // 사용자가 무슨 일이 일어났는지 알 수 없게 된다.
  const r = resolveCancelTarget({
    occurrenceId: OCC_A,
    scoped: app(OCC_A, 'cancelled'),
    legacy: null,
    activeCandidates: null,
  });
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.target.data.status, 'cancelled');
});

test('회차 지정 — 회차 문서가 없으면 같은 회차의 옛 uid 문서로 폴백', () => {
  const r = resolveCancelTarget({
    occurrenceId: OCC_A,
    scoped: null,
    legacy: legacyApp('applied', OCC_A),
    activeCandidates: null,
  });
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.target.id, UID);
});

test('회차 지정 — 옛 uid 문서가 다른 회차면 폴백하지 않는다', () => {
  // 8/16을 취소하려는데 8/15 옛 신청이 취소되면 남의 회차가 사라진다.
  const r = resolveCancelTarget({
    occurrenceId: OCC_A,
    scoped: null,
    legacy: legacyApp('applied', '2026-08-15'),
    activeCandidates: null,
  });
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.code, 'not-found');
});

test('회차 지정 — 옛 uid 문서가 이미 취소됐으면 폴백하지 않는다', () => {
  const r = resolveCancelTarget({
    occurrenceId: OCC_A,
    scoped: null,
    legacy: legacyApp('cancelled', OCC_A),
    activeCandidates: null,
  });
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.code, 'not-found');
});

// ── ② 회차를 지정하지 않은 요청(구버전 앱) ──────────────────────────────

test('회차 미지정 — uid 문서가 살아 있으면 그 문서(기존 동작 그대로)', () => {
  const r = resolveCancelTarget({
    occurrenceId: null,
    scoped: legacyApp('applied'),
    legacy: null,
    activeCandidates: null,
  });
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.target.id, UID);
});

test('회차 미지정 — 단일 날짜 기존 파티: 문서가 uid 하나뿐이라 조회 없이 끝난다', () => {
  const scoped = legacyApp('approved');
  assert.strictEqual(
    needsCandidateLookup({ occurrenceId: null, scoped }),
    false,
    '살아 있는 uid 문서가 있으면 추가 조회를 하면 안 된다',
  );
  const r = resolveCancelTarget({
    occurrenceId: null,
    scoped,
    legacy: null,
    activeCandidates: null,
  });
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.target.id, UID);
});

test('회차 미지정 — 옛 uid 문서 cancelled + 회차 문서 1건 active → 회차 문서(운영 사고 재현)', () => {
  // 2026-08-21 운영에서 난 그 건이다. 예전에는 여기서 '이미취소'가 났다.
  const scoped = legacyApp('cancelled', '2026-08-15');
  assert.strictEqual(needsCandidateLookup({ occurrenceId: null, scoped }), true);
  const r = resolveCancelTarget({
    occurrenceId: null,
    scoped,
    legacy: null,
    activeCandidates: [scoped, app(OCC_A, 'applied')],
  });
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.target.id, `${UID}_${OCC_A}`);
});

test('회차 미지정 — uid 문서가 아예 없고 회차 문서 1건 active → 그 문서', () => {
  const r = resolveCancelTarget({
    occurrenceId: null,
    scoped: null,
    legacy: null,
    activeCandidates: [app(OCC_A, 'pending')],
  });
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.target.id, `${UID}_${OCC_A}`);
});

test('회차 미지정 — 살아 있는 회차 신청이 둘이면 아무것도 취소하지 않는다', () => {
  const r = resolveCancelTarget({
    occurrenceId: null,
    scoped: null,
    legacy: null,
    activeCandidates: [app(OCC_A, 'applied'), app(OCC_B, 'approved')],
  });
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.code, 'failed-precondition');
  assert.ok(
    r.message.includes('회차를 지정'),
    '앱이 이 문구로 이 경우를 알아본다(party_detail_screen.dart _cancelFailure)',
  );
});

test('회차 미지정 — 승인대기(pending)와 확정(approved)이 섞여 있어도 둘이면 거절', () => {
  const r = resolveCancelTarget({
    occurrenceId: null,
    scoped: legacyApp('cancelled'),
    legacy: null,
    activeCandidates: [app(OCC_A, 'pending'), app(OCC_B, 'applied')],
  });
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.code, 'failed-precondition');
});

test('회차 미지정 — 끝난 신청(cancelled/attended/no_show/rejected)은 후보가 아니다', () => {
  const r = resolveCancelTarget({
    occurrenceId: null,
    scoped: legacyApp('cancelled'),
    legacy: null,
    activeCandidates: [
      legacyApp('cancelled'),
      app(OCC_A, 'attended'),
      app(OCC_B, 'no_show'),
      app('2026-08-30', 'rejected'),
      app('2026-09-06', 'applied'),
    ],
  });
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.target.id, `${UID}_2026-09-06`, '살아 있는 한 건만 골라야 한다');
});

test('회차 미지정 — 이미 취소된 신청뿐이면 그 문서를 돌려줘 이유를 말하게 한다', () => {
  const scoped = legacyApp('cancelled');
  const r = resolveCancelTarget({
    occurrenceId: null,
    scoped,
    legacy: null,
    activeCandidates: [scoped],
  });
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.target.data.status, 'cancelled', "호출부가 '이미취소'를 던진다");
});

test('회차 미지정 — 신청 문서가 하나도 없으면 not-found', () => {
  const r = resolveCancelTarget({
    occurrenceId: null,
    scoped: null,
    legacy: null,
    activeCandidates: [],
  });
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.code, 'not-found');
});

// ── 조회 여부 판정 ──────────────────────────────────────────────────────

test('회차를 지정한 요청은 추가 조회를 하지 않는다', () => {
  assert.strictEqual(
    needsCandidateLookup({ occurrenceId: OCC_A, scoped: null }),
    false,
    '대상이 이미 유일한데 트랜잭션 안에서 쿼리를 더 돌릴 이유가 없다',
  );
});

test('회차 미지정 + uid 문서 없음/끝남 → 조회한다', () => {
  assert.strictEqual(needsCandidateLookup({ occurrenceId: null, scoped: null }), true);
  assert.strictEqual(
    needsCandidateLookup({ occurrenceId: null, scoped: legacyApp('cancelled') }),
    true,
  );
});

// ── 상태 목록이 다른 곳과 어긋나지 않는지 ───────────────────────────────

test('LIVE_APPLICATION_STATUSES가 accountWithdrawal/contentCleanup과 같다', () => {
  const pick = (file) =>
    require('fs')
      .readFileSync(`${__dirname}/${file}`, 'utf8')
      .match(/const LIVE_APPLICATION_STATUSES = (\[[^\]]*\])/)[1];
  const mine = pick('partyApplicationTargets.js');
  assert.strictEqual(mine, pick('accountWithdrawal.js'), '탈퇴 차단 목록과 달라졌다');
  assert.strictEqual(mine, pick('contentCleanup.js'), '정리 작업 목록과 달라졌다');
  assert.deepStrictEqual(LIVE_APPLICATION_STATUSES, ['applied', 'pending', 'approved']);
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
    ? `\n취소 대상 판정 검증 통과 — ${cases.length}건`
    : `\n실패 ${failed}건 / 전체 ${cases.length}건`,
);
process.exit(failed === 0 ? 0 : 1);

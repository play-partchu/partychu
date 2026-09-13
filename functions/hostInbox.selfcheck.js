// 통합 신청자·예약자 관리의 판정 확인 — `node hostInbox.selfcheck.js`
//
// 두 가지만 본다.
//   1. 미처리 판정 — 배지 숫자가 이 함수 하나로 정해진다. 취소/거절이 새면
//      호스트에게 "처리할 게 3건"이라고 떠 있는데 들어가면 할 일이 없다.
//   2. 회차 날짜 — 정기 파티는 회차마다 신청이 따로다. 여기가 틀리면 8/22
//      신청에 8/15가 찍혀 호스트가 엉뚱한 날짜를 보고 승인한다.

const assert = require('assert');

const {
  HOST_INBOX_LIMIT,
  isPartyApplicationUnhandled,
  isComboGeneratedApplication,
  applicationStartAtMs,
} = require('./hostInbox');

const ts = (ms) => ({ toMillis: () => ms });
const bank = (status) => ({ method: 'bank_transfer', status });

// ── 1. 미처리 판정 ──────────────────────────────────────────────────────────

// 승인제 대기는 호스트가 승인해야 확정된다 — 가장 중요한 한 건.
assert.strictEqual(isPartyApplicationUnhandled({ status: 'pending' }), true);

// 참가자가 '입금했어요'를 눌렀으면 호스트가 대조해야 한다.
assert.strictEqual(
  isPartyApplicationUnhandled({ status: 'applied', payment: bank('deposit_pending') }),
  true,
);

// 아직 입금 전이면 호스트가 할 수 있는 일이 없다 — 배지에 넣지 않는다.
assert.strictEqual(
  isPartyApplicationUnhandled({ status: 'applied', payment: bank('awaiting_deposit') }),
  false,
);

// 취소·거절은 처리가 끝난 것이다. 결제 상태가 무엇으로 남아 있든 제외한다.
assert.strictEqual(
  isPartyApplicationUnhandled({ status: 'cancelled', payment: bank('deposit_pending') }),
  false,
);
assert.strictEqual(
  isPartyApplicationUnhandled({ status: 'rejected', payment: bank('deposit_pending') }),
  false,
);
// 승인 대기였다가 거절된 건도 마찬가지 — status가 우선이다.
assert.strictEqual(isPartyApplicationUnhandled({ status: 'rejected' }), false);

// 즉시확정·확정·참석은 할 일이 없다.
for (const status of ['applied', 'approved', 'attended', 'no_show']) {
  assert.strictEqual(isPartyApplicationUnhandled({ status }), false, status);
}

// 무통장입금이 아닌 결제는 호스트가 대조할 것이 없다(현장결제 등).
assert.strictEqual(
  isPartyApplicationUnhandled({
    status: 'applied',
    payment: { method: 'on_site', status: 'deposit_pending' },
  }),
  false,
);

// 결제 맵이 없던 옛 신청 · 빈 값에도 죽지 않는다.
assert.strictEqual(isPartyApplicationUnhandled({}), false);
assert.strictEqual(isPartyApplicationUnhandled(null), false);
assert.strictEqual(isPartyApplicationUnhandled(undefined), false);

// ── 2. 콤보에서 파생된 신청 ─────────────────────────────────────────────────
//
// 숙박+파티 콤보는 예약 문서와 파티 신청 문서를 함께 만든다. 이걸 못 걸러내면
// 예약 한 건에 알림이 두 번 가고 통합 목록에도 두 줄로 뜬다.

assert.strictEqual(
  isComboGeneratedApplication({ bundleBookingId: 'bundle_1' }),
  true,
);
// 파티 단독 신청에는 이 필드가 아예 없다.
assert.strictEqual(isComboGeneratedApplication({ status: 'pending' }), false);
assert.strictEqual(isComboGeneratedApplication({ bundleBookingId: null }), false);
assert.strictEqual(isComboGeneratedApplication({}), false);
assert.strictEqual(isComboGeneratedApplication(null), false);

// ── 3. 회차 날짜 ────────────────────────────────────────────────────────────

// 회차가 있으면 **회차 시작 시각이 정본**이다 — partyDateTime(첫 회차 캐시)이
// 함께 있어도 그쪽을 쓰면 안 된다.
assert.strictEqual(
  applicationStartAtMs({ occurrenceStartAt: ts(200), partyDateTime: ts(100) }),
  200,
);

// 회차가 없는 단일 날짜 파티는 partyDateTime으로 떨어진다.
assert.strictEqual(applicationStartAtMs({ partyDateTime: ts(100) }), 100);

// 둘 다 없으면 null — 화면이 날짜 자리를 비운다(0으로 만들면 1970년이 찍힌다).
assert.strictEqual(applicationStartAtMs({}), null);
assert.strictEqual(applicationStartAtMs(null), null);

// Timestamp가 아닌 값이 들어와도 죽지 않는다(옛 문서에 문자열이 남은 경우).
assert.strictEqual(applicationStartAtMs({ partyDateTime: '2026-08-22' }), null);

// ── 4. 상한 ─────────────────────────────────────────────────────────────────

assert.ok(HOST_INBOX_LIMIT > 0);

console.log('hostInbox.selfcheck: 통과');

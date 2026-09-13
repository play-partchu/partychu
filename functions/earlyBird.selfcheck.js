// 얼리버드(정기 파티 포함) 자체 검증 — 배포 전에 `npm run check:earlybird`.
// functions에는 테스트 러너가 없으므로 node 기본 assert만 쓴다(의존성 0).
//
// 여기서 확인하는 규칙은 클라이언트와 **반드시 같은 결과**를 내야 한다:
//   lib/models/party_early_bird_schedule.dart
//   lib/utils/early_bird.dart
//   test/early_bird_recurring_test.dart   ← 같은 케이스를 그대로 옮겨 놓았다
//
// 한쪽만 고치면 "앱에는 얼리버드 가격이 보이는데 서버는 정상가로 결제"하는
// 상태가 되므로, 규칙을 바꿀 때는 양쪽을 함께 고치고 두 테스트를 모두 돌린다.

const assert = require('assert');
const { resolveEarlyBirdEnd, earlyBirdEndAtFor } = require('./partySchedule');
const {
  computeAppliedFee,
  computeAppliedFeeForRounds,
} = require('./partyCapacity');

// KST 벽시계 → 절대 시각(UTC-9h). 기대값을 사람이 읽는 그대로 쓰기 위한 헬퍼.
function kst(y, m, d, hh = 0, mm = 0) {
  return new Date(Date.UTC(y, m - 1, d, hh, mm) - 9 * 60 * 60 * 1000);
}

function ts(date) {
  return { toDate: () => date };
}

const ALL_DAYS = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];

function recurringParty({
  days = ALL_DAYS,
  startTime = '20:00',
  endTime = '23:00',
  startDate = kst(2026, 7, 1),
  endDate = null,
  rule = null,
  percent = 20,
  enabled = true,
  price = 30000,
} = {}) {
  const weekly = {};
  for (const d of days) weekly[d] = { enabled: true, startTime, endTime };
  return {
    scheduleType: 'recurring',
    // 필드 이름은 partySchedule.selfcheck.js의 recurringDoc과 동일하게 맞춘다
    // (Firestore에 실제로 저장되는 키: weeklySchedule / registrationDeadline).
    recurringSchedule: {
      startDate: ts(startDate),
      endDate: endDate ? ts(endDate) : null,
      weeklySchedule: weekly,
      registrationDeadline: { mode: 'none' },
    },
    pricingType: 'same',
    price,
    earlyBirdEnabled: enabled,
    earlyBirdDiscountPercent: percent,
    ...(rule ? { earlyBirdDeadlineRule: rule } : {}),
  };
}

const cases = [];
function test(name, fn) {
  cases.push([name, fn]);
}

// 기준 시각 — 2026-08-01(토) 09:00 KST. Dart 테스트와 동일.
const NOW = kst(2026, 8, 1, 9, 0);

// ── 규칙 → 종료 시각 ───────────────────────────────────────────────────
test('N일 전 + 시각 — 월요일 19시 파티는 금요일 23:59에 끝난다', () => {
  const rule = { mode: 'daysBefore', days: 3, time: '23:59' };
  assert.deepStrictEqual(
    resolveEarlyBirdEnd(rule, kst(2026, 8, 10, 19)),
    kst(2026, 8, 7, 23, 59),
  );
});

test('N시간 전 — 24시간 전', () => {
  const rule = { mode: 'hoursBefore', hours: 24 };
  assert.deepStrictEqual(
    resolveEarlyBirdEnd(rule, kst(2026, 8, 7, 20)),
    kst(2026, 8, 6, 20),
  );
});

test('당일 특정 시각 — 당일 18:00', () => {
  const rule = { mode: 'sameDayTime', time: '18:00' };
  assert.deepStrictEqual(
    resolveEarlyBirdEnd(rule, kst(2026, 8, 7, 20)),
    kst(2026, 8, 7, 18),
  );
});

test('0일 전은 당일 종료 시각으로 처리된다', () => {
  const rule = { mode: 'daysBefore', days: 0, time: '12:00' };
  assert.deepStrictEqual(
    resolveEarlyBirdEnd(rule, kst(2026, 8, 7, 20)),
    kst(2026, 8, 7, 12),
  );
});

test('종료가 시작 이후로 계산되면 시작 시각까지만 적용된다', () => {
  const rule = { mode: 'sameDayTime', time: '22:00' };
  assert.deepStrictEqual(
    resolveEarlyBirdEnd(rule, kst(2026, 8, 7, 18)),
    kst(2026, 8, 7, 18),
  );
});

test('알 수 없는 규칙이면 null(= 얼리버드 없음)', () => {
  assert.strictEqual(resolveEarlyBirdEnd({ mode: 'nope' }, kst(2026, 8, 7, 18)), null);
  assert.strictEqual(resolveEarlyBirdEnd(null, kst(2026, 8, 7, 18)), null);
  assert.strictEqual(resolveEarlyBirdEnd({ mode: 'daysBefore' }, kst(2026, 8, 7)), null);
});

// ── 회차별 자동 계산 ───────────────────────────────────────────────────
test('매주 금요일 20:00 · 2일 전 23:59 → 수요일 23:59', () => {
  const data = recurringParty({
    days: ['friday'],
    rule: { mode: 'daysBefore', days: 2, time: '23:59' },
  });
  assert.deepStrictEqual(earlyBirdEndAtFor(data, NOW), kst(2026, 8, 5, 23, 59));
});

test('이번 회차가 끝나면 다음 회차 기준으로 다시 열린다', () => {
  const data = recurringParty({
    days: ['friday'],
    rule: { mode: 'daysBefore', days: 2, time: '23:59' },
  });
  // 8/8(토) → 다음 금요일 8/14 기준
  assert.deepStrictEqual(
    earlyBirdEndAtFor(data, kst(2026, 8, 8, 10)),
    kst(2026, 8, 12, 23, 59),
  );
});

test('자정을 넘겨 끝나는 파티(19:00~03:00)도 기준은 시작 시각', () => {
  const data = recurringParty({
    days: ['saturday'],
    startTime: '19:00',
    endTime: '03:00',
    rule: { mode: 'hoursBefore', hours: 3 },
  });
  assert.deepStrictEqual(earlyBirdEndAtFor(data, NOW), kst(2026, 8, 1, 16));
});

test('남은 회차가 없으면 null', () => {
  const data = recurringParty({
    endDate: kst(2026, 7, 20),
    rule: { mode: 'hoursBefore', hours: 1 },
  });
  assert.strictEqual(earlyBirdEndAtFor(data, NOW), null);
});

test('규칙이 없는 예전 정기 파티는 earlyBirdEndAt으로 폴백', () => {
  const data = recurringParty();
  data.earlyBirdEndAt = ts(kst(2026, 8, 15, 23, 59));
  assert.deepStrictEqual(earlyBirdEndAtFor(data, NOW), kst(2026, 8, 15, 23, 59));
});

// ── 서버가 확정하는 가격 ───────────────────────────────────────────────
test('정기 파티 — 마감 전이면 할인가, 마감 후면 정상가', () => {
  const data = recurringParty({
    days: ['friday'],
    rule: { mode: 'daysBefore', days: 2, time: '23:59' },
    percent: 20,
    price: 30000,
  });
  assert.strictEqual(computeAppliedFee(data, 'male', NOW), 24000);
  assert.strictEqual(
    computeAppliedFee(data, 'male', kst(2026, 8, 6, 10)),
    30000,
  );
});

test('정기 파티 — 특정 회차를 골라 신청하면 그 회차 기준으로 판정', () => {
  const data = recurringParty({
    days: ['friday'],
    rule: { mode: 'daysBefore', days: 2, time: '23:59' },
  });
  // 8/6에 신청하지만 회차는 8/14를 골랐다면 그 회차 얼리버드(8/12까지)가 산다.
  const occurrence = { start: kst(2026, 8, 14, 20) };
  assert.strictEqual(
    computeAppliedFee(data, 'male', kst(2026, 8, 6, 10), occurrence),
    24000,
  );
});

test('남은 회차가 없으면 정상가', () => {
  const data = recurringParty({
    endDate: kst(2026, 7, 20),
    rule: { mode: 'hoursBefore', hours: 1 },
  });
  assert.strictEqual(computeAppliedFee(data, 'male', NOW), 30000);
});

test('무료 파티에는 할인이 적용되지 않는다', () => {
  const data = recurringParty({
    price: 0,
    rule: { mode: 'hoursBefore', hours: 1 },
  });
  data.pricingType = 'free';
  assert.strictEqual(computeAppliedFee(data, 'male', NOW), 0);
});

// ── 기존 일회성 파티 회귀 방지 ─────────────────────────────────────────
test('일회성 — 저장된 고정 종료 시각을 그대로 쓴다', () => {
  const data = {
    scheduleType: 'single',
    pricingType: 'same',
    price: 30000,
    earlyBirdEnabled: true,
    earlyBirdDiscountPercent: 10,
    earlyBirdEndAt: ts(kst(2026, 8, 15, 23, 59)),
  };
  assert.deepStrictEqual(earlyBirdEndAtFor(data, NOW), kst(2026, 8, 15, 23, 59));
  assert.strictEqual(computeAppliedFee(data, 'male', NOW), 27000);
});

test('일회성 — 종료 시각이 지나면 정상가', () => {
  const data = {
    scheduleType: 'single',
    pricingType: 'same',
    price: 30000,
    earlyBirdEnabled: true,
    earlyBirdDiscountPercent: 10,
    earlyBirdEndAt: ts(kst(2026, 7, 15, 23, 59)),
  };
  assert.strictEqual(computeAppliedFee(data, 'male', NOW), 30000);
});

test('scheduleType이 없는 옛 문서도 예전 그대로 동작한다', () => {
  const data = {
    maleFee: 30000,
    femaleFee: 20000,
    earlyBirdEnabled: true,
    earlyBirdDiscountPercent: 50,
    earlyBirdEndAt: ts(kst(2026, 8, 15, 23, 59)),
  };
  assert.strictEqual(computeAppliedFee(data, 'male', NOW), 15000);
  assert.strictEqual(computeAppliedFee(data, 'female', NOW), 10000);
});

test('얼리버드가 꺼져 있으면 언제나 정상가', () => {
  const data = recurringParty({
    enabled: false,
    rule: { mode: 'hoursBefore', hours: 1 },
  });
  assert.strictEqual(computeAppliedFee(data, 'male', NOW), 30000);
});

// ── 차수별 참가비 (라운드 진행 파티) ────────────────────────────────────
//
// 라운드 파티의 실제 결제 금액은 **차수 자신의 참가비**로 계산된다. 등록
// 화면이 1차 참가비를 라운드 설정에서 받도록 바뀐 뒤에도 이 규칙은 그대로다 —
// 화면이 바뀐 것이지 계산이 바뀐 것이 아니라는 사실을 여기서 못박아 둔다.
// (클라이언트 lib/models/party_round_offer.dart의 _roundOffer와 같은 결과)

// 차수 하나 — 시각은 판정에 쓰이므로 항상 채운다.
function roundAt(number, extra = {}) {
  return {
    roundNumber: number,
    time: ts(kst(2026, 8, 10, 19 + number, 0)),
    endAt: ts(kst(2026, 8, 10, 21 + number, 0)),
    ...extra,
  };
}

test('차수별 참가비 — 고른 차수의 금액만 더한다', () => {
  const rounds = [
    roundAt(1, { maleFee: 20000, femaleFee: 15000 }),
    roundAt(2, { maleFee: 30000, femaleFee: 25000 }),
  ];
  assert.strictEqual(computeAppliedFeeForRounds(rounds, [1], 'male'), 20000);
  assert.strictEqual(computeAppliedFeeForRounds(rounds, [2], 'male'), 30000);
  assert.strictEqual(computeAppliedFeeForRounds(rounds, [2], 'female'), 25000);
  assert.strictEqual(computeAppliedFeeForRounds(rounds, [1, 2], 'male'), 50000);
});

test('모든 차수 동일 얼리버드 — 할인은 차수마다 자기 참가비 기준', () => {
  // 화면에서 "전체 차수 20%"를 고르면 같은 규칙이 모든 차수에 복사돼 저장된다.
  const eb = {
    earlyBirdEnabled: true,
    earlyBirdDiscountPercent: 20,
    earlyBirdDeadlineRule: { mode: 'hoursBefore', hours: 1 },
  };
  const rounds = [
    roundAt(1, { maleFee: 20000, femaleFee: 20000, ...eb }),
    roundAt(2, { maleFee: 30000, femaleFee: 30000, ...eb }),
  ];
  // 할인된 금액 하나를 저장하는 방식이었다면 두 차수가 같은 값이 됐을 것이다.
  assert.strictEqual(
    computeAppliedFeeForRounds(rounds, [1], 'male', NOW),
    16000
  );
  assert.strictEqual(
    computeAppliedFeeForRounds(rounds, [2], 'male', NOW),
    24000
  );
});

test('차수별 얼리버드 — 1차만 켜면 2차는 정상가', () => {
  const rounds = [
    roundAt(1, {
      maleFee: 20000,
      femaleFee: 20000,
      earlyBirdEnabled: true,
      earlyBirdDiscountPercent: 20,
      earlyBirdDeadlineRule: { mode: 'hoursBefore', hours: 1 },
    }),
    roundAt(2, { maleFee: 30000, femaleFee: 30000, earlyBirdEnabled: false }),
  ];
  assert.strictEqual(
    computeAppliedFeeForRounds(rounds, [1], 'male', NOW),
    16000
  );
  assert.strictEqual(
    computeAppliedFeeForRounds(rounds, [2], 'male', NOW),
    30000
  );
});

test('옛 문서 폴백 — 차수에 참가비가 없으면 문서 최상단 값을 쓴다', () => {
  // 차수별 참가비를 저장하기 전에 만든 라운드 파티: 가격이 문서에만 있다.
  const data = { pricingType: 'same', price: 25000 };
  const rounds = [roundAt(1), roundAt(2)];
  assert.strictEqual(
    computeAppliedFeeForRounds(rounds, [1], 'male', NOW, data),
    25000
  );
  // 폴백을 넘기지 않으면 예전처럼 0원 — 호출부가 data를 반드시 넘겨야 한다.
  assert.strictEqual(computeAppliedFeeForRounds(rounds, [1], 'male', NOW), 0);
});

test('옛 문서 폴백 — 차수에 얼리버드가 없으면 문서 규칙을 그 차수에 적용', () => {
  const data = {
    pricingType: 'same',
    price: 20000,
    earlyBirdEnabled: true,
    earlyBirdDiscountPercent: 25,
    earlyBirdDeadlineRule: { mode: 'hoursBefore', hours: 1 },
  };
  assert.strictEqual(
    computeAppliedFeeForRounds([roundAt(1)], [1], 'male', NOW, data),
    15000
  );
});

test('폴백은 값이 아예 없을 때만 — 차수가 끈 얼리버드를 되살리지 않는다', () => {
  const data = {
    earlyBirdEnabled: true,
    earlyBirdDiscountPercent: 25,
    earlyBirdDeadlineRule: { mode: 'hoursBefore', hours: 1 },
  };
  const rounds = [
    roundAt(1, { maleFee: 20000, femaleFee: 20000, earlyBirdEnabled: false }),
  ];
  assert.strictEqual(
    computeAppliedFeeForRounds(rounds, [1], 'male', NOW, data),
    20000
  );
});

// ── 실행 ───────────────────────────────────────────────────────────────
let failed = 0;
for (const [name, fn] of cases) {
  try {
    fn();
    console.log(`  ok  ${name}`);
  } catch (e) {
    failed++;
    console.error(`FAIL  ${name}\n      ${e.message}`);
  }
}
console.log(`\n${cases.length - failed}/${cases.length} passed`);
process.exit(failed === 0 ? 0 : 1);

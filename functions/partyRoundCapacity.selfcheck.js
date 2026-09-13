// 차수별 정원 판정 자체 검증 — `node partyRoundCapacity.selfcheck.js`.
//
// 핵심 회귀 방지: 남녀무관(unlimited) + 차수별 정원 조합에서 예전에는
// maleCapacity/femaleCapacity(둘 다 0)를 보는 바람에 **아무도 신청할 수
// 없었다**. 이제는 차수의 maxCapacity만 본다.

const assert = require('assert');
const admin = require('firebase-admin');
if (!admin.apps.length) {
  admin.firestore = Object.assign(admin.firestore, {
    FieldValue: {
      serverTimestamp: () => '<ts>',
      arrayUnion: (v) => ({ __arrayUnion: v }),
      arrayRemove: (v) => ({ __arrayRemove: v }),
    },
  });
}

const { reserveApplicantSlot, releaseApplicantSlot } = require('./partyCapacity');

const future = new Date(Date.now() + 48 * 3600e3);
const ts = (d) => ({ toDate: () => d });

function party({ mode = 'unlimited', rounds }) {
  return {
    recruitStatus: '모집중',
    hasMultipleRounds: true,
    roundCapacityMode: 'perRound',
    genderCapacityMode: mode,
    partyDateTime: ts(future),
    rounds,
  };
}

const roundOf = (o) => ({
  roundNumber: 1,
  label: '1차',
  time: ts(future),
  recruitCloseAt: ts(new Date(future.getTime() - 3600e3)),
  maleFee: 10000,
  femaleFee: 10000,
  ...o,
});

const cases = [];
const test = (n, f) => cases.push([n, f]);

// ── 남녀무관(unlimited) ────────────────────────────────────────────────
test('남녀무관: 남녀 정원이 0이어도 maxCapacity로 신청된다(회귀 방지)', () => {
  const data = party({
    rounds: [roundOf({ maxCapacity: 10, maleCapacity: 0, femaleCapacity: 0, currentParticipants: 0 })],
  });
  const r = reserveApplicantSlot(data, { uid: 'u1', gender: 'male', selectedRounds: [1] });
  assert.strictEqual(r.updateData.rounds[0].currentParticipants, 1);
  assert.strictEqual(r.updateData.maxCapacity, 10);
});

test('남녀무관: 성별을 몰라도(미인증) 신청된다', () => {
  const data = party({
    rounds: [roundOf({ maxCapacity: 10, maleCapacity: 0, femaleCapacity: 0, currentParticipants: 3 })],
  });
  const r = reserveApplicantSlot(data, { uid: 'u1', gender: null, selectedRounds: [1] });
  assert.strictEqual(r.updateData.rounds[0].currentParticipants, 4);
});

test('남녀무관: 정원이 차면 마감', () => {
  const data = party({
    rounds: [roundOf({ maxCapacity: 10, currentParticipants: 10 })],
  });
  assert.throws(
    () => reserveApplicantSlot(data, { uid: 'u1', gender: 'male', selectedRounds: [1] }),
    /마감/,
  );
});

test('남녀무관: 정원 0은 제한 없음으로 본다(최상단 분기와 동일)', () => {
  const data = party({
    rounds: [roundOf({ maxCapacity: 0, maleCapacity: 0, femaleCapacity: 0, currentParticipants: 99 })],
  });
  const r = reserveApplicantSlot(data, { uid: 'u1', gender: 'male', selectedRounds: [1] });
  assert.strictEqual(r.updateData.rounds[0].currentParticipants, 100);
});

test('남녀무관: 취소하면 전체 인원이 정확히 1 줄어든다', () => {
  const data = party({
    rounds: [roundOf({ maxCapacity: 10, currentParticipants: 4, currentMaleCount: 2 })],
  });
  const r = releaseApplicantSlot(data, { uid: 'u1', gender: 'male', selectedRounds: [1] });
  assert.strictEqual(r.rounds[0].currentParticipants, 3);
});

test('남녀무관: 신청 → 취소 왕복이면 인원이 제자리로', () => {
  const start = 5;
  const data = party({ rounds: [roundOf({ maxCapacity: 10, currentParticipants: start })] });
  const res = reserveApplicantSlot(data, { uid: 'u1', gender: null, selectedRounds: [1] });
  const after = party({ rounds: res.updateData.rounds });
  const rel = releaseApplicantSlot(after, { uid: 'u1', gender: null, selectedRounds: [1] });
  assert.strictEqual(rel.rounds[0].currentParticipants, start);
});

// ── 남녀별(separate) — 기존 동작 그대로여야 한다 ────────────────────────
test('남녀별: 남자 정원이 차면 마감(기존 로직 유지)', () => {
  const data = party({
    mode: 'separate',
    rounds: [roundOf({ maxCapacity: 10, maleCapacity: 5, femaleCapacity: 5, currentMaleCount: 5 })],
  });
  assert.throws(
    () => reserveApplicantSlot(data, { uid: 'u1', gender: 'male', selectedRounds: [1] }),
    /마감/,
  );
});

test('남녀별: 남자가 차도 여자는 신청 가능(기존 로직 유지)', () => {
  const data = party({
    mode: 'separate',
    rounds: [roundOf({ maxCapacity: 10, maleCapacity: 5, femaleCapacity: 5, currentMaleCount: 5, currentFemaleCount: 1 })],
  });
  const r = reserveApplicantSlot(data, { uid: 'u1', gender: 'female', selectedRounds: [1] });
  assert.strictEqual(r.updateData.rounds[0].currentFemaleCount, 2);
  // 남녀별은 예전처럼 남녀 합계가 전체 인원이다.
  assert.strictEqual(r.updateData.rounds[0].currentParticipants, 7);
});

test('남녀별: 성별 미인증이면 거부(기존 로직 유지)', () => {
  const data = party({
    mode: 'separate',
    rounds: [roundOf({ maxCapacity: 10, maleCapacity: 5, femaleCapacity: 5 })],
  });
  assert.throws(
    () => reserveApplicantSlot(data, { uid: 'u1', gender: null, selectedRounds: [1] }),
    /미인증/,
  );
});

// ── 구버전 문서 호환 ───────────────────────────────────────────────────
test('구버전: genderCapacityMode가 없으면 남녀무관으로 본다', () => {
  const data = {
    recruitStatus: '모집중',
    hasMultipleRounds: true,
    roundCapacityMode: 'perRound',
    partyDateTime: ts(future),
    rounds: [roundOf({ maxCapacity: 10, currentParticipants: 2 })],
  };
  const r = reserveApplicantSlot(data, { uid: 'u1', gender: 'male', selectedRounds: [1] });
  assert.strictEqual(r.updateData.rounds[0].currentParticipants, 3);
});

test('구버전: maxCapacity가 없으면 남녀 정원의 합으로 판정한다', () => {
  const data = party({
    rounds: [roundOf({ maleCapacity: 3, femaleCapacity: 3, currentParticipants: 6 })],
  });
  assert.throws(
    () => reserveApplicantSlot(data, { uid: 'u1', gender: 'male', selectedRounds: [1] }),
    /마감/,
  );
  const ok = party({
    rounds: [roundOf({ maleCapacity: 3, femaleCapacity: 3, currentParticipants: 5 })],
  });
  assert.doesNotThrow(() =>
    reserveApplicantSlot(ok, { uid: 'u1', gender: 'male', selectedRounds: [1] }),
  );
});

test('구버전: currentParticipants가 없으면 남녀 카운터 합으로 읽는다', () => {
  const data = party({
    rounds: [roundOf({ maxCapacity: 4, currentMaleCount: 2, currentFemaleCount: 2 })],
  });
  assert.throws(
    () => reserveApplicantSlot(data, { uid: 'u1', gender: 'male', selectedRounds: [1] }),
    /마감/,
  );
});

// ── 차수 패키지 ────────────────────────────────────────────────────────
// 패키지는 별도 판매가 하나로 계산하되, 정원은 포함된 **모든 차수**에서 1명씩
// 차지한다 — 아래 케이스들이 그 두 가지를 함께 지킨다.
const twoRounds = (o1 = {}, o2 = {}) => [
  roundOf({ maxCapacity: 10, maleFee: 30000, femaleFee: 20000, ...o1 }),
  roundOf({
    roundNumber: 2,
    label: '2차',
    time: ts(new Date(future.getTime() + 3 * 3600e3)),
    maxCapacity: 10,
    maleFee: 25000,
    femaleFee: 15000,
    ...o2,
  }),
];

const pkg = (o = {}) => ({
  id: 'pkg_1',
  name: '1+2차 통합권',
  roundNumbers: [1, 2],
  maleFee: 45000,
  femaleFee: 30000,
  earlyBirdEnabled: false,
  ...o,
});

function packageParty(overrides = {}, rounds) {
  return {
    ...party({ rounds: rounds ?? twoRounds() }),
    roundPackages: [pkg(overrides)],
  };
}

test('패키지: 포함된 모든 차수의 정원을 1명씩 차지한다', () => {
  const data = packageParty();
  const r = reserveApplicantSlot(data, {
    uid: 'u1',
    gender: 'male',
    packageId: 'pkg_1',
  });
  assert.deepStrictEqual(r.effectiveSelectedRounds, [1, 2]);
  assert.strictEqual(r.updateData.rounds[0].currentParticipants, 1);
  assert.strictEqual(r.updateData.rounds[1].currentParticipants, 1);
});

test('패키지: 금액은 개별 합산이 아니라 패키지 판매가다', () => {
  const data = packageParty();
  const male = reserveApplicantSlot(data, {
    uid: 'u1',
    gender: 'male',
    packageId: 'pkg_1',
  });
  // 개별 합계 55,000이 아니라 패키지가 45,000.
  assert.strictEqual(male.appliedFee, 45000);
  const female = reserveApplicantSlot(data, {
    uid: 'u2',
    gender: 'female',
    packageId: 'pkg_1',
  });
  assert.strictEqual(female.appliedFee, 30000);
});

test('패키지: 클라이언트가 보낸 차수 목록은 무시하고 패키지 정의를 쓴다', () => {
  const data = packageParty();
  const r = reserveApplicantSlot(data, {
    uid: 'u1',
    gender: 'male',
    // 조작된 요청 — 1차만 차지하고 패키지 가격을 받으려는 시도.
    selectedRounds: [1],
    packageId: 'pkg_1',
  });
  assert.deepStrictEqual(r.effectiveSelectedRounds, [1, 2]);
});

test('패키지: 포함 차수 하나라도 정원이 차면 신청 불가', () => {
  const data = packageParty({}, twoRounds({}, { currentParticipants: 10 }));
  assert.throws(
    () =>
      reserveApplicantSlot(data, {
        uid: 'u1',
        gender: 'male',
        packageId: 'pkg_1',
      }),
    /마감/,
  );
});

test('패키지: 성비 맞춤이면 포함 차수의 그 성별 자리를 모두 봐야 한다', () => {
  const rounds = twoRounds(
    { maleCapacity: 5, femaleCapacity: 5, currentMaleCount: 1 },
    { maleCapacity: 5, femaleCapacity: 5, currentMaleCount: 5 },
  );
  const data = {
    ...party({ mode: 'separate', rounds }),
    roundPackages: [pkg()],
  };
  // 2차 남자 자리가 없으므로 1차가 남아도 패키지는 막힌다.
  assert.throws(
    () =>
      reserveApplicantSlot(data, {
        uid: 'u1',
        gender: 'male',
        packageId: 'pkg_1',
      }),
    /마감/,
  );
  // 같은 파티에서 여자는 양쪽 자리가 남아 신청된다.
  const ok = reserveApplicantSlot(data, {
    uid: 'u2',
    gender: 'female',
    packageId: 'pkg_1',
  });
  assert.strictEqual(ok.updateData.rounds[0].currentFemaleCount, 1);
  assert.strictEqual(ok.updateData.rounds[1].currentFemaleCount, 1);
});

test('패키지: 취소하면 포함된 모든 차수가 정확히 1씩 줄어든다', () => {
  const data = packageParty();
  const res = reserveApplicantSlot(data, {
    uid: 'u1',
    gender: 'male',
    packageId: 'pkg_1',
  });
  const after = { ...data, rounds: res.updateData.rounds };
  // 취소는 신청 문서에 남은 selectedRounds(= 패키지 포함 차수)로 되돌린다.
  const rel = releaseApplicantSlot(after, {
    uid: 'u1',
    gender: 'male',
    selectedRounds: res.effectiveSelectedRounds,
  });
  assert.strictEqual(rel.rounds[0].currentParticipants, 0);
  assert.strictEqual(rel.rounds[1].currentParticipants, 0);
});

test('패키지: 얼리버드가 유효하면 얼리버드 판매가로 계산한다', () => {
  const data = packageParty({
    earlyBirdEnabled: true,
    earlyBirdMaleFee: 40000,
    earlyBirdFemaleFee: 25000,
    earlyBirdEndAt: ts(new Date(Date.now() + 3600e3)),
  });
  const r = reserveApplicantSlot(data, {
    uid: 'u1',
    gender: 'male',
    packageId: 'pkg_1',
  });
  assert.strictEqual(r.appliedFee, 40000);
});

test('패키지: 얼리버드가 지났으면 정상 판매가', () => {
  const data = packageParty({
    earlyBirdEnabled: true,
    earlyBirdMaleFee: 40000,
    earlyBirdEndAt: ts(new Date(Date.now() - 3600e3)),
  });
  const r = reserveApplicantSlot(data, {
    uid: 'u1',
    gender: 'male',
    packageId: 'pkg_1',
  });
  assert.strictEqual(r.appliedFee, 45000);
});

test('패키지: 없는 패키지 id는 거부', () => {
  const data = packageParty();
  assert.throws(
    () =>
      reserveApplicantSlot(data, {
        uid: 'u1',
        gender: 'male',
        packageId: 'pkg_없음',
      }),
    /존재하지 않는 패키지/,
  );
});

test('패키지: 통합 정원 모드에서는 쓸 수 없다', () => {
  const data = {
    ...packageParty(),
    roundCapacityMode: 'unified',
  };
  assert.throws(
    () =>
      reserveApplicantSlot(data, {
        uid: 'u1',
        gender: 'male',
        packageId: 'pkg_1',
      }),
    /차수 패키지를 사용할 수 없습니다/,
  );
});

test('패키지: 포함 차수가 사라졌으면 신청 불가', () => {
  const data = packageParty({}, [twoRounds()[0]]);
  assert.throws(
    () =>
      reserveApplicantSlot(data, {
        uid: 'u1',
        gender: 'male',
        packageId: 'pkg_1',
      }),
    /변경되어 신청할 수 없습니다/,
  );
});

test('패키지: 이미 신청한 사람은 개별 차수든 패키지든 다시 신청할 수 없다', () => {
  const data = { ...packageParty(), applicants: ['u1'] };
  assert.throws(
    () =>
      reserveApplicantSlot(data, {
        uid: 'u1',
        gender: 'male',
        packageId: 'pkg_1',
      }),
    /이미신청/,
  );
  assert.throws(
    () =>
      reserveApplicantSlot(data, {
        uid: 'u1',
        gender: 'male',
        selectedRounds: [1],
      }),
    /이미신청/,
  );
});

// ── 차수 시각의 회차 기준 재계산 ────────────────────────────────────────
// rounds[].time은 등록 시점 날짜로 굳어 있는 캐시라, 그대로 판정에 쓰면 첫
// 회차가 지난 순간부터 모든 차수가 "이미 끝난 차수"가 된다(정기 파티는 영구히,
// 날짜만 바꿔 재등록한 문서는 원본 날짜 기준으로). 아래가 그 회귀를 막는다 —
// partyCapacity.js의 rebaseRounds / 클라이언트 PartyRound.resolveOn과 짝이다.
const past = new Date(Date.now() - 7 * 24 * 3600e3);
const kstDate = (d) => {
  const s = new Date(d.getTime() + 9 * 3600e3);
  return `${s.getUTCFullYear()}-${String(s.getUTCMonth() + 1).padStart(2, '0')}-${String(
    s.getUTCDate()
  ).padStart(2, '0')}`;
};
// 시각은 그대로인데 날짜만 과거인 차수 — 실제 문서에서 관찰된 모양이다.
const staleRound = (o = {}) =>
  roundOf({
    maxCapacity: 10,
    time: ts(past),
    recruitCloseAt: ts(new Date(past.getTime() - 3600e3)),
    ...o,
  });

test('정기: rounds[].time이 지난 회차여도 고른 회차 기준으로 신청된다', () => {
  const data = {
    recruitStatus: '모집중',
    hasMultipleRounds: true,
    roundCapacityMode: 'perRound',
    genderCapacityMode: 'unlimited',
    scheduleType: 'recurring',
    partyDateTime: ts(past),
    rounds: [staleRound()],
  };
  // 사용자가 고른 회차(미래) — index.js가 recurringSchedule로 다시 계산해 넘긴다.
  const occurrence = { start: future, end: future, deadline: null, recruitOpenAt: null };
  const r = reserveApplicantSlot(data, {
    uid: 'u1',
    gender: 'male',
    selectedRounds: [1],
    occurrence,
    occurrenceId: kstDate(future),
  });
  // 차수 인원은 **그 회차 칸**에 잡힌다 — 정기 파티는 차수 정원도 회차별로
  // 독립이라(8/15 1차 ≠ 8/22 1차) 최상단 rounds[]에 올리면 안 된다.
  const occKey = `occurrenceStats.${kstDate(future)}.rounds`;
  assert.strictEqual(r.updateData[occKey]['1'].currentParticipants, 1);
  assert.strictEqual(r.roundCounterScope, 'occurrence');
  // 최상단 rounds[]는 아예 건드리지 않는다 — 다른 회차 신청자의 인원과
  // 원본 시각이 그대로 남아 있어야 한다.
  assert.strictEqual(r.updateData.rounds, undefined);
});

test('일회성: 파티 날짜는 미래인데 rounds[].time만 과거인 문서도 신청된다', () => {
  const data = party({ rounds: [staleRound()] });
  const r = reserveApplicantSlot(data, { uid: 'u1', gender: 'male', selectedRounds: [1] });
  assert.strictEqual(r.updateData.rounds[0].currentParticipants, 1);
});

test('레거시: 차수에 모집 창구가 없어도 회차 날짜 기준으로 열린다', () => {
  const data = party({
    rounds: [
      {
        // endAt/recruitOpenAt/recruitCloseAt이 아예 없는 예전 문서
        roundNumber: 1,
        label: '1차',
        time: ts(past),
        maleFee: 20000,
        femaleFee: 20000,
        maxCapacity: 20,
      },
    ],
  });
  const r = reserveApplicantSlot(data, { uid: 'u1', gender: 'male', selectedRounds: [1] });
  assert.strictEqual(r.updateData.rounds[0].currentParticipants, 1);
});

test('진짜 지난 파티는 그대로 거부한다(과잉 교정 방지)', () => {
  const data = party({ rounds: [staleRound()] });
  data.partyDateTime = ts(past); // 파티 날짜 자체가 과거 = 정말 끝난 파티
  assert.throws(
    () => reserveApplicantSlot(data, { uid: 'u1', gender: 'male', selectedRounds: [1] }),
    /신청받지 않습니다/,
  );
});

test('모집 마감이 지난 차수는 회차를 옮겨도 거부한다', () => {
  // 시작은 아직 멀었지만 마감이 이미 지난 차수 — 재계산해도 닫혀 있어야 한다.
  const data = party({
    rounds: [
      roundOf({
        maxCapacity: 10,
        time: ts(future),
        recruitCloseAt: ts(new Date(Date.now() - 3600e3)),
      }),
    ],
  });
  assert.throws(
    () => reserveApplicantSlot(data, { uid: 'u1', gender: 'male', selectedRounds: [1] }),
    /신청받지 않습니다/,
  );
});

// ── 실행 ────────────────────────────────────────────────────────────────
let passed = 0;
for (const [name, fn] of cases) {
  try {
    fn();
    console.log(`  ok  ${name}`);
    passed++;
  } catch (e) {
    console.error(`  FAIL ${name}\n       ${e.message}`);
  }
}
console.log(`\n${passed}/${cases.length} passed`);
if (passed !== cases.length) process.exit(1);

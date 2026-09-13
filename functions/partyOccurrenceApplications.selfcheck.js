// 정기 파티 **회차별 신청** 자체 검증 — `node partyOccurrenceApplications.selfcheck.js`.
//
// 지켜야 하는 정책은 네 줄이다.
//   · 일회성 파티      : 같은 사람 중복 신청 불가 (기존 그대로)
//   · 정기 파티        : 같은 회차 중복 신청 불가 / 다른 회차는 다시 신청 가능
//   · 한 회차를 취소해도 **다른 회차의 신청·승인·정원은 그대로**
//   · 회차 신청은 회차 칸이 정본 — 최상단 카운터를 회차 값으로 덮어쓰지 않는다
//
// 마지막 두 줄이 이 파일의 존재 이유다. 예전에는 applicants 배열 하나를 회차
// 구분 없이 쓰고 있어서, 8/15를 취소하면 arrayRemove(uid)가 8/22 신청의 흔적까지
// 지워버렸다(승인 상태·파티 수정 차단 판정이 한꺼번에 틀어졌다).

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

const {
  reserveApplicantSlot,
  releaseApplicantSlot,
  applicationDocId,
} = require('./partyCapacity');

const DAY_MS = 24 * 3600e3;
const future = new Date(Date.now() + 48 * 3600e3);
const ts = (d) => ({ toDate: () => d });

// ── 회차 날짜는 **실행 시점 기준 상대값**이다 ──────────────────────────────
//
// 예전에는 '2026-08-15'·'2026-08-22'를 상수로 박아 뒀다. 그 날짜가 지나는
// 순간(2026-08-22) 앞 회차가 과거가 되면서, reserveApplicantSlot의 "이미
// 시작한 회차는 신청받지 않는다" 판정(partyCapacity.js의
// `occurrence.start <= now` → '마감')에 15건이 한꺼번에 걸렸다.
//
// 이 검증이 확인하려는 것은 **회차끼리의 격리**(앞 회차를 취소해도 뒤 회차가
// 멀쩡한가)이지 마감 판정이 아니다. 그래서 마감 판정을 느슨하게 만드는 대신
// 두 회차를 항상 미래로 잡는다 — 운영 로직은 그대로 두고 픽스처만 고친다.
//
// 하루 중 언제 돌려도 안전하다: +7일 날짜의 19:00은 지금보다 최소 6일 19시간
// 뒤다(now의 시각이 19:00보다 늦어도 하루를 넘지 않는다).
const OCC_A_DAYS_AHEAD = 7; // 앞 회차
const OCC_B_DAYS_AHEAD = 14; // 뒤 회차

/** Date → 'YYYY-MM-DD'(로컬 달력). 회차 id 형식은 서버와 같다. */
function occurrenceIdOf(date) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

const OCC_A = occurrenceIdOf(new Date(Date.now() + OCC_A_DAYS_AHEAD * DAY_MS));
const OCC_B = occurrenceIdOf(new Date(Date.now() + OCC_B_DAYS_AHEAD * DAY_MS));

const occ = (id) => {
  const [y, m, d] = id.split('-').map(Number);
  const start = new Date(y, m - 1, d, 19, 0, 0);
  return { id, start, end: new Date(start.getTime() + 3 * 3600e3), deadline: null };
};

// 두 회차가 정말 미래인지 여기서 한 번 못박는다 — 이 전제가 깨지면 아래
// 15건이 전부 '마감'으로 무너지므로, 원인을 테스트 본문이 아니라 여기서
// 바로 알 수 있어야 한다.
for (const [name, id] of [['OCC_A', OCC_A], ['OCC_B', OCC_B]]) {
  const start = occ(id).start;
  assert.ok(
    start.getTime() > Date.now(),
    `${name}(${id} 19:00)이 미래여야 한다 — 회차 격리 검증의 전제`,
  );
}

/** 정기 파티 문서 한 장. occurrenceStats는 서버가 회차별로 쌓는 칸이다. */
function recurringParty(occurrenceStats = {}) {
  return {
    recruitStatus: '모집중',
    scheduleType: 'recurring',
    genderCapacityMode: 'unlimited',
    genderLimit: 'all',
    maxParticipants: 10,
    partyDateTime: ts(future),
    recurringSchedule: {
      weekdays: [5],
      startTime: '19:00',
      endTime: '22:00',
      // 회차 날짜와 같은 이유로 상대값이다(운영 시작일이 회차보다 뒤면
      // 일정 자체가 성립하지 않는다).
      startDate: occurrenceIdOf(new Date(Date.now() - DAY_MS)),
    },
    applicants: [],
    occurrenceStats,
  };
}

function onceParty(extra = {}) {
  return {
    recruitStatus: '모집중',
    genderCapacityMode: 'unlimited',
    genderLimit: 'all',
    maxParticipants: 10,
    partyDateTime: ts(future),
    applicants: [],
    ...extra,
  };
}

/**
 * FieldValue.arrayUnion/arrayRemove 자리를 알아본다.
 *
 * 위 stub이 먹히면 `__arrayUnion` 모양이고, 실제 admin SDK가 살아 있으면
 * ArrayUnion/ArrayRemoveTransform 객체다 — 둘 다 받아야 이 검증이 환경에
 * 상관없이 같은 결과를 낸다.
 */
function transformOf(value) {
  if (!value || typeof value !== 'object') return null;
  if (value.__arrayUnion !== undefined) return { op: 'union', elements: [value.__arrayUnion] };
  if (value.__arrayRemove !== undefined) return { op: 'remove', elements: [value.__arrayRemove] };
  const name = value.constructor && value.constructor.name;
  if (name === 'ArrayUnionTransform') return { op: 'union', elements: value.elements };
  if (name === 'ArrayRemoveTransform') return { op: 'remove', elements: value.elements };
  return null;
}

/** updateData를 파티 문서에 실제로 반영해 "다음 상태"를 만든다. */
function apply(partyData, updateData) {
  const next = {
    ...partyData,
    applicants: [...(partyData.applicants || [])],
    approvedApplicants: [...(partyData.approvedApplicants || [])],
    rejectedApplicants: [...(partyData.rejectedApplicants || [])],
    occurrenceStats: Object.fromEntries(
      Object.entries(partyData.occurrenceStats || {}).map(([id, stat]) => [
        id,
        { ...stat, applicants: [...(stat.applicants || [])] },
      ]),
    ),
  };
  for (const [path, value] of Object.entries(updateData)) {
    const segs = path.split('.');
    let cursor = next;
    for (let i = 0; i < segs.length - 1; i++) {
      cursor[segs[i]] = cursor[segs[i]] || {};
      cursor = cursor[segs[i]];
    }
    const key = segs[segs.length - 1];
    const tf = transformOf(value);
    if (!tf) {
      cursor[key] = value;
      continue;
    }
    const list = Array.isArray(cursor[key]) ? cursor[key] : [];
    cursor[key] = tf.op === 'union'
      ? [...list, ...tf.elements.filter((e) => !list.includes(e))]
      : list.filter((v) => !tf.elements.includes(v));
  }
  return next;
}

const reserve = (partyData, occurrenceId) =>
  reserveApplicantSlot(partyData, {
    uid: 'u1',
    gender: 'male',
    birthYear: 1995,
    occurrence: occurrenceId ? occ(occurrenceId) : null,
    occurrenceId,
  }).updateData;

const release = (partyData, occurrenceId) =>
  releaseApplicantSlot(partyData, { uid: 'u1', gender: 'male', occurrenceId });

const cases = [];
const test = (name, fn) => cases.push([name, fn]);

// ── 문서 ID ─────────────────────────────────────────────────────────────
test('회차가 없으면 문서 ID는 예전 그대로 uid다(기존 문서 호환)', () => {
  assert.strictEqual(applicationDocId('u1', null), 'u1');
  assert.strictEqual(applicationDocId('u1', undefined), 'u1');
});

test('회차가 있으면 회차마다 문서 ID가 다르다', () => {
  assert.notStrictEqual(applicationDocId('u1', OCC_A), applicationDocId('u1', OCC_B));
  assert.strictEqual(applicationDocId('u1', OCC_A), `u1_${OCC_A}`);
});

test('구분자가 들어 있는 소셜 uid도 회차마다 유일하다', () => {
  // socialAuth가 만드는 커스텀 토큰 uid('kakao:123')도 문서 ID로 쓸 수 있어야
  // 한다. 되돌려 파싱하지 않으므로 구분자가 섞여도 문제되지 않는다.
  assert.strictEqual(applicationDocId('kakao:123', OCC_A), `kakao:123_${OCC_A}`);
  assert.notStrictEqual(
    applicationDocId('kakao:123', OCC_A),
    applicationDocId('kakao:123', OCC_B),
  );
});

// ── 중복 신청 ───────────────────────────────────────────────────────────
test('일회성 파티 — 같은 사람이 두 번 신청할 수 없다', () => {
  const after = apply(onceParty(), reserve(onceParty(), null));
  assert.throws(() => reserve(after, null), /이미신청/);
});

test('정기 파티 — 같은 회차를 두 번 신청할 수 없다', () => {
  const after = apply(recurringParty(), reserve(recurringParty(), OCC_A));
  assert.throws(() => reserve(after, OCC_A), /이미신청/);
});

test('정기 파티 — 앞 회차에 신청했어도 뒤 회차는 신청할 수 있다', () => {
  const after = apply(recurringParty(), reserve(recurringParty(), OCC_A));
  assert.doesNotThrow(() => reserve(after, OCC_B));
});

test('옛 신청(회차 없음)이 있어도 새 회차 신청은 막히지 않는다', () => {
  // 구조 변경 전 신청은 어느 회차의 것인지 알 수 없다 — 최상단 명단에만 있다.
  const legacy = recurringParty();
  legacy.applicants = ['u1'];
  assert.doesNotThrow(() => reserve(legacy, OCC_A));
});

// ── 정원 정본 ───────────────────────────────────────────────────────────
test('회차 신청은 최상단 카운터를 덮어쓰지 않는다', () => {
  const patch = reserve(recurringParty(), OCC_A);
  assert.strictEqual(patch.currentParticipants, undefined);
  assert.strictEqual(patch.people, undefined);
  assert.strictEqual(patch[`occurrenceStats.${OCC_A}.currentParticipants`], 1);
});

test('일회성 파티는 최상단 카운터를 그대로 쓴다', () => {
  const patch = reserve(onceParty(), null);
  assert.strictEqual(patch.currentParticipants, 1);
  assert.ok(patch.people.startsWith('1/'));
});

test('회차별 인원은 서로 섞이지 않는다', () => {
  let p = apply(recurringParty(), reserve(recurringParty(), OCC_A));
  p = apply(p, reserve(p, OCC_B));
  assert.strictEqual(p.occurrenceStats[OCC_A].currentParticipants, 1);
  assert.strictEqual(p.occurrenceStats[OCC_B].currentParticipants, 1);
});

// ── 취소 격리 (이 파일의 핵심) ──────────────────────────────────────────
test('앞 회차를 취소해도 뒤 회차 신청은 명단에 그대로 남는다', () => {
  let p = apply(recurringParty(), reserve(recurringParty(), OCC_A));
  p = apply(p, reserve(p, OCC_B));
  p = apply(p, release(p, OCC_A));

  assert.deepStrictEqual(p.occurrenceStats[OCC_A].applicants, []);
  assert.deepStrictEqual(p.occurrenceStats[OCC_B].applicants, ['u1']);
  // 최상단 명단은 "살아 있는 신청이 하나라도 있는 사람" — 8/22가 남아 있으므로
  // 여기서 지워지면 안 된다.
  assert.deepStrictEqual(p.applicants, ['u1']);
});

test('앞 회차를 취소해도 뒤 회차 정원은 줄지 않는다', () => {
  let p = apply(recurringParty(), reserve(recurringParty(), OCC_A));
  p = apply(p, reserve(p, OCC_B));
  p = apply(p, release(p, OCC_A));

  assert.strictEqual(p.occurrenceStats[OCC_A].currentParticipants, 0);
  assert.strictEqual(p.occurrenceStats[OCC_B].currentParticipants, 1);
});

test('앞 회차를 취소해도 승인 상태(레거시 배열)가 함께 풀리지 않는다', () => {
  let p = apply(recurringParty(), reserve(recurringParty(), OCC_A));
  p = apply(p, reserve(p, OCC_B));
  p.approvedApplicants = ['u1'];
  p = apply(p, release(p, OCC_A));
  assert.deepStrictEqual(p.approvedApplicants, ['u1']);
});

test('마지막 회차까지 취소하면 최상단 명단에서도 빠진다', () => {
  let p = apply(recurringParty(), reserve(recurringParty(), OCC_A));
  p = apply(p, reserve(p, OCC_B));
  p.approvedApplicants = ['u1'];
  p = apply(p, release(p, OCC_A));
  p = apply(p, release(p, OCC_B));
  assert.deepStrictEqual(p.applicants, []);
  assert.deepStrictEqual(p.approvedApplicants, []);
});

test('취소한 회차는 다시 신청할 수 있다', () => {
  let p = apply(recurringParty(), reserve(recurringParty(), OCC_A));
  p = apply(p, release(p, OCC_A));
  assert.doesNotThrow(() => reserve(p, OCC_A));
});

test('일회성 파티 취소는 예전 그대로 최상단만 되돌린다', () => {
  const p = apply(onceParty(), reserve(onceParty(), null));
  const patch = release(p, null);
  assert.strictEqual(patch.currentParticipants, 0);
  const tf = transformOf(patch.applicants);
  assert.ok(tf && tf.op === 'remove' && tf.elements.includes('u1'));
});

// ── 회차별 차수 정원 ────────────────────────────────────────────────────
//
// 정기 파티는 **차수 정원도 회차별**이다. 예전에는 rounds[]가 문서 최상단에만
// 있어서 8/15 1차 신청이 8/22 1차 자리를 잡아먹었다.

/** 차수별 정원 모드의 정기 파티. 1차·2차 각각 정원 1명. */
function recurringPerRound(occurrenceStats = {}) {
  return {
    ...recurringParty(occurrenceStats),
    hasMultipleRounds: true,
    roundCapacityMode: 'perRound',
    rounds: [
      { roundNumber: 1, label: '1차', maxCapacity: 1, maleFee: 10000, femaleFee: 10000 },
      { roundNumber: 2, label: '2차', maxCapacity: 1, maleFee: 10000, femaleFee: 10000 },
    ],
    roundPackages: [
      { id: 'pkg12', name: '1+2차', roundNumbers: [1, 2], maleFee: 18000, femaleFee: 18000 },
    ],
  };
}

const reserveRounds = (partyData, occurrenceId, rounds, uid = 'u1') =>
  reserveApplicantSlot(partyData, {
    uid,
    gender: 'male',
    birthYear: 1995,
    selectedRounds: rounds,
    occurrence: occurrenceId ? occ(occurrenceId) : null,
    occurrenceId,
  });

test('회차 신청은 최상단 rounds[]를 건드리지 않는다', () => {
  const r = reserveRounds(recurringPerRound(), OCC_A, [1]);
  assert.strictEqual(r.updateData.rounds, undefined);
  assert.strictEqual(r.roundCounterScope, 'occurrence');
  assert.strictEqual(
    r.updateData[`occurrenceStats.${OCC_A}.rounds`]['1'].currentParticipants,
    1,
  );
});

test('앞 회차 1차가 차도 뒤 회차 1차는 비어 있다', () => {
  const p0 = recurringPerRound();
  const p = apply(p0, reserveRounds(p0, OCC_A, [1]).updateData);
  // 8/15 1차는 정원 1명이 찼다 — 다른 사람이 더 못 들어간다.
  assert.throws(() => reserveRounds(p, OCC_A, [1], 'u2'), /마감/);
  // 8/22 1차는 그대로 비어 있다.
  assert.doesNotThrow(() => reserveRounds(p, OCC_B, [1], 'u2'));
});

test('같은 회차의 1차가 차도 2차는 신청할 수 있다', () => {
  const p0 = recurringPerRound();
  const p = apply(p0, reserveRounds(p0, OCC_A, [1]).updateData);
  assert.doesNotThrow(() => reserveRounds(p, OCC_A, [2], 'u2'));
});

test('패키지(1+2차) 신청은 그 회차의 두 차수만 채운다', () => {
  const p0 = recurringPerRound();
  const r = reserveApplicantSlot(p0, {
    uid: 'u1',
    gender: 'male',
    birthYear: 1995,
    packageId: 'pkg12',
    occurrence: occ(OCC_A),
    occurrenceId: OCC_A,
  });
  const p = apply(p0, r.updateData);
  assert.strictEqual(p.occurrenceStats[OCC_A].rounds['1'].currentParticipants, 1);
  assert.strictEqual(p.occurrenceStats[OCC_A].rounds['2'].currentParticipants, 1);
  assert.strictEqual(p.occurrenceStats[OCC_B], undefined);
  assert.strictEqual(p.rounds[0].currentParticipants, undefined);
});

test('회차 차수 취소는 그 회차의 그 차수만 원복한다', () => {
  const p0 = recurringPerRound();
  let p = apply(p0, reserveRounds(p0, OCC_A, [1]).updateData);
  p = apply(p, reserveRounds(p, OCC_B, [1], 'u2').updateData);
  p = apply(p, releaseApplicantSlot(p, {
    uid: 'u1',
    gender: 'male',
    selectedRounds: [1],
    occurrenceId: OCC_A,
    roundCounterScope: 'occurrence',
  }));
  assert.strictEqual(p.occurrenceStats[OCC_A].rounds['1'].currentParticipants, 0);
  // 8/22는 손대지 않는다.
  assert.strictEqual(p.occurrenceStats[OCC_B].rounds['1'].currentParticipants, 1);
  assert.doesNotThrow(() => reserveRounds(p, OCC_A, [1], 'u3'));
});

test('옛 회차 신청(최상단 누적)의 취소는 최상단만 되돌린다', () => {
  // 회차별 차수 카운터 도입 **전에** 만들어진 신청은 roundCounterScope가 없다.
  // 그 신청이 취소될 때 회차 칸을 건드리면 남의 자리를 반납하게 된다.
  const p = recurringPerRound({
    [OCC_A]: { applicants: ['u2'], rounds: { '1': { currentParticipants: 1 } } },
  });
  p.rounds[0].currentParticipants = 1;
  const patch = releaseApplicantSlot(p, {
    uid: 'u1',
    gender: 'male',
    selectedRounds: [1],
    occurrenceId: OCC_A,
    roundCounterScope: null,
  });
  assert.strictEqual(patch.rounds[0].currentParticipants, 0);
  assert.strictEqual(patch[`occurrenceStats.${OCC_A}.rounds`], undefined);
});

test('없던 회차 차수 칸은 0에서 시작한다 — 최상단 누적을 복사하지 않는다', () => {
  // 최상단에 지난 회차들이 쌓아 올린 인원이 남아 있어도, 새 회차는 빈 칸이다.
  const p = recurringPerRound();
  p.rounds[0].currentParticipants = 5;
  p.rounds[0].currentMaleCount = 5;
  const r = reserveRounds(p, OCC_B, [1]);
  assert.strictEqual(
    r.updateData[`occurrenceStats.${OCC_B}.rounds`]['1'].currentParticipants,
    1,
  );
});

test('일회성 파티의 차수 정원은 예전 그대로 최상단이다', () => {
  const p = {
    ...onceParty(),
    hasMultipleRounds: true,
    roundCapacityMode: 'perRound',
    rounds: [{ roundNumber: 1, label: '1차', maxCapacity: 2, maleFee: 0, femaleFee: 0 }],
  };
  const r = reserveRounds(p, null, [1]);
  assert.strictEqual(r.updateData.rounds[0].currentParticipants, 1);
  assert.strictEqual(r.roundCounterScope, null);
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

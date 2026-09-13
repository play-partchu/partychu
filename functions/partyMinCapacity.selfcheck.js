// partyMinCapacity.js 자체 검증 — `node partyMinCapacity.selfcheck.js`.
// functions에는 테스트 러너가 없으므로 node 기본 assert만 쓴다(의존성 0).
//
// 여기서 확인하는 규칙은 클라이언트(lib/models/party_capacity_status.dart,
// test/party_capacity_status_test.dart)와 같은 결과를 내야 한다.

const assert = require('assert');

// admin.firestore.FieldValue를 쓰는 모듈이라 초기화 없이 require하면 죽는다 —
// 판정 함수만 검증하므로 최소한의 스텁을 심는다.
const admin = require('firebase-admin');
if (!admin.apps.length) {
  admin.firestore = Object.assign(admin.firestore, {
    FieldValue: { serverTimestamp: () => '<serverTimestamp>' },
  });
}

const {
  currentParticipantsOf,
  partyMinCapacityOf,
  isLegacySummedMin,
  isConfirmedApplication,
  confirmedCountOf,
  isOccurrenceCancelled,
  isAutoCancelCandidate,
  autoCancelsBelowMin,
  shouldAutoCancel,
  autoCancelFields,
  dueOccurrencesOf,
  occurrenceCancelFields,
  notificationDoc,
  MIN_CAPACITY_NOT_MET,
} = require('./partyMinCapacity');

function ts(date) {
  return { toDate: () => date };
}

const NOW = new Date('2026-08-10T12:00:00Z');
const PAST = new Date('2026-08-10T11:00:00Z');
const FUTURE = new Date('2026-08-10T13:00:00Z');

function party(overrides = {}) {
  return {
    title: '테스트 파티',
    recruitStatus: '모집중',
    minCapacity: 10,
    minCapacityPolicy: 'autoCancel',
    currentParticipants: 5,
    recruitDeadlineAt: ts(PAST),
    ...overrides,
  };
}

const cases = [];
function test(name, fn) {
  cases.push([name, fn]);
}

// ── 현재 인원 읽기 ──────────────────────────────────────────────────────
test('성비 맞춤 파티는 남녀 신청자를 합산한다', () => {
  assert.strictEqual(
    currentParticipantsOf({
      genderCapacityMode: 'separate',
      currentMaleCount: 4,
      currentFemaleCount: 3,
      currentParticipants: 99, // 분리 모드에서는 보지 않는다
    }),
    7,
  );
  assert.strictEqual(currentParticipantsOf({ currentParticipants: 6 }), 6);
});

// ── 자동 취소 판정 ──────────────────────────────────────────────────────
test('마감이 지났고 최소 인원 미달이면 취소 대상', () => {
  assert.strictEqual(shouldAutoCancel(party(), NOW), true);
});

test('최소 인원을 채웠으면 취소하지 않는다', () => {
  assert.strictEqual(
    shouldAutoCancel(party({ currentParticipants: 10 }), NOW),
    false,
  );
});

test('마감 전에는 취소하지 않는다', () => {
  assert.strictEqual(
    shouldAutoCancel(party({ recruitDeadlineAt: ts(FUTURE) }), NOW),
    false,
  );
});

test("'정상 진행'으로 둔 파티는 건드리지 않는다", () => {
  assert.strictEqual(
    shouldAutoCancel(party({ minCapacityPolicy: 'proceed' }), NOW),
    false,
  );
  // 값이 없던 예전 문서도 정상 진행이다.
  assert.strictEqual(
    shouldAutoCancel(party({ minCapacityPolicy: undefined }), NOW),
    false,
  );
});

test('최소 인원을 안 정한 파티는 대상이 아니다', () => {
  assert.strictEqual(shouldAutoCancel(party({ minCapacity: 0 }), NOW), false);
});

test('이미 취소/마감된 파티는 다시 건드리지 않는다', () => {
  assert.strictEqual(
    shouldAutoCancel(party({ recruitStatus: '취소' }), NOW),
    false,
  );
  assert.strictEqual(
    shouldAutoCancel(party({ recruitStatus: '마감' }), NOW),
    false,
  );
});

test('삭제된 파티는 대상이 아니다', () => {
  assert.strictEqual(shouldAutoCancel(party({ isDeleted: true }), NOW), false);
});

test('마감 시각이 없으면(마감 없음) 취소하지 않는다', () => {
  assert.strictEqual(
    shouldAutoCancel(party({ recruitDeadlineAt: null }), NOW),
    false,
  );
});

test('정기 파티는 회차마다 모집이 새로 열리므로 제외한다', () => {
  assert.strictEqual(
    shouldAutoCancel(party({ scheduleType: 'recurring' }), NOW),
    false,
  );
});

test('성비 맞춤 파티도 합산 인원으로 판정한다', () => {
  const base = {
    genderCapacityMode: 'separate',
    currentParticipants: 0,
    minCapacity: 10,
  };
  assert.strictEqual(
    shouldAutoCancel(
      party({ ...base, currentMaleCount: 4, currentFemaleCount: 4 }),
      NOW,
    ),
    true,
  );
  assert.strictEqual(
    shouldAutoCancel(
      party({ ...base, currentMaleCount: 5, currentFemaleCount: 5 }),
      NOW,
    ),
    false,
  );
});

// ── 저장 필드 / 알림 ────────────────────────────────────────────────────
test('취소 필드에 사유와 그 시점 인원이 함께 남는다', () => {
  const fields = autoCancelFields(party());
  assert.strictEqual(fields.recruitStatus, '취소');
  assert.strictEqual(fields.cancelReason, MIN_CAPACITY_NOT_MET);
  assert.strictEqual(fields.cancelledBySystem, true);
  assert.strictEqual(fields.minCapacityAtCancel, 10);
  assert.strictEqual(fields.participantsAtCancel, 5);
});

test('신청자와 호스트 알림 문구가 다르다', () => {
  const data = party();
  const applicant = notificationDoc({
    uid: 'u1',
    partyId: 'p1',
    partyTitle: '금요일 와인바',
    role: 'applicant',
    data,
  });
  const host = notificationDoc({
    uid: 'h1',
    partyId: 'p1',
    partyTitle: '금요일 와인바',
    role: 'host',
    data,
  });

  assert.strictEqual(applicant.type, 'partyAutoCancelledMinCapacity');
  assert.ok(applicant.body.includes('전액 환불'));
  assert.ok(host.body.includes('10명'));
  assert.ok(host.body.includes('5명'));
  assert.strictEqual(applicant.read, false);
});


// ── 파티 전체 최소 모집 인원 읽기 (차수 합계 금지) ──────────────────────
//
// 여기서 확인하는 규칙은 클라이언트 PartyMinCapacity.of와 같은 결과여야 한다.
test('새 필드(partyMinCapacity)가 있으면 그 값이 정본이다', () => {
  assert.strictEqual(
    partyMinCapacityOf({ partyMinCapacity: 6, minCapacity: 4 }),
    6,
  );
  // 0도 "호스트가 제한 없음으로 정했다"는 뜻이라 옛 필드로 넘어가지 않는다.
  assert.strictEqual(
    partyMinCapacityOf({ partyMinCapacity: 0, minCapacity: 4 }),
    0,
  );
});

test('차수 없는 옛 문서는 minCapacity를 그대로 믿는다', () => {
  assert.strictEqual(partyMinCapacityOf({ minCapacity: 10 }), 10);
  assert.strictEqual(
    partyMinCapacityOf({
      minCapacity: 10,
      hasMultipleRounds: true,
      roundCapacityMode: 'unified',
    }),
    10,
  );
});

test('차수별 정원 옛 문서의 minCapacity는 합계라 0으로 본다', () => {
  // 1차 최소 2명 + 2차 최소 2명 → minCapacity 4로 저장돼 있던 문서.
  // 그 4는 "이 파티가 열리려면 4명"이라는 뜻이 아니므로 쓰지 않는다.
  const legacy = {
    minCapacity: 4,
    hasMultipleRounds: true,
    roundCapacityMode: 'perRound',
  };
  assert.strictEqual(partyMinCapacityOf(legacy), 0);
  assert.strictEqual(isLegacySummedMin(legacy), true);
  // 다시 저장돼 새 필드가 붙으면 더 이상 오염된 문서가 아니다.
  assert.strictEqual(
    partyMinCapacityOf({ ...legacy, partyMinCapacity: 6 }),
    6,
  );
  assert.strictEqual(isLegacySummedMin({ ...legacy, partyMinCapacity: 6 }), false);
});

test('폴백이 0이면 자동 취소 대상이 되지 않는다', () => {
  // 최소 인원을 알 수 없는 옛 문서를 추정해서 취소하면 안 된다.
  assert.strictEqual(
    shouldAutoCancel(
      party({
        minCapacity: 4,
        hasMultipleRounds: true,
        roundCapacityMode: 'perRound',
        currentParticipants: 0,
      }),
      NOW,
    ),
    false,
  );
});

// ── 확정 인원 세기 ──────────────────────────────────────────────────────
test('승인 대기(pending)는 확정 인원에 넣지 않는다', () => {
  const apps = [
    { status: 'applied' },
    { status: 'approved' },
    { status: 'pending' }, // 승인제 파티의 승인 대기
    { status: 'cancelled' },
    { status: 'rejected' },
  ];
  assert.strictEqual(confirmedCountOf(apps), 2);
  assert.strictEqual(isConfirmedApplication({ status: 'pending' }), false);
  assert.strictEqual(isConfirmedApplication({ status: 'approved' }), true);
});

test('회차를 주면 그 회차 신청만 센다', () => {
  const apps = [
    { status: 'applied', occurrenceId: '2026-08-22' },
    { status: 'approved', occurrenceId: '2026-08-22' },
    { status: 'applied', occurrenceId: '2026-08-24' },
    { status: 'applied' }, // 회차 없는 옛 신청
  ];
  assert.strictEqual(confirmedCountOf(apps, '2026-08-22'), 2);
  assert.strictEqual(confirmedCountOf(apps, '2026-08-24'), 1);
});

// ── 정기 파티 회차 단위 자동 취소 ───────────────────────────────────────
//
// 매주 수·금·일 19:00~22:00, 회차 시작 1시간 전 마감인 파티.
function recurringParty(overrides = {}) {
  return {
    title: '정기 테스트',
    recruitStatus: '모집중',
    scheduleType: 'recurring',
    partyMinCapacity: 6,
    minCapacityPolicy: 'autoCancel',
    recurringSchedule: {
      startDate: '2026-08-01T00:00:00+09:00',
      weeklySchedule: {
        wednesday: { startTime: '19:00', endTime: '22:00' },
        friday: { startTime: '19:00', endTime: '22:00' },
        sunday: { startTime: '19:00', endTime: '22:00' },
      },
      registrationDeadline: { mode: 'beforeStart', minutes: 60 },
    },
    ...overrides,
  };
}

test('정기 파티는 마감이 지난 회차만 판정 대상이 된다', () => {
  const data = recurringParty();
  // 2026-08-21(금) 19:00 시작 → 마감 18:00 KST = 09:00 UTC.
  // 마감 직후이자 시작 전인 시각.
  const now = new Date('2026-08-21T09:30:00Z');
  const due = dueOccurrencesOf(data, now);
  assert.ok(
    due.some((d) => d.occurrenceId === '2026-08-21'),
    `마감 지난 8/21 회차가 대상이어야 한다: ${JSON.stringify(due.map((d) => d.occurrenceId))}`,
  );
  // 아직 마감 전인 회차(8/23 일)는 들어오지 않는다.
  assert.ok(!due.some((d) => d.occurrenceId === '2026-08-23'));
});

test('이미 시작한 회차는 뒤늦게 취소하지 않는다', () => {
  const data = recurringParty();
  // 8/21 19:00(=10:00 UTC) 이후 — 파티가 이미 열렸다.
  const now = new Date('2026-08-21T11:00:00Z');
  const due = dueOccurrencesOf(data, now);
  assert.ok(!due.some((d) => d.occurrenceId === '2026-08-21'));
});

test('이미 취소 기록이 있는 회차는 다시 처리하지 않는다', () => {
  const now = new Date('2026-08-21T09:30:00Z');
  const data = recurringParty({
    occurrenceCancellations: { '2026-08-21': { reason: MIN_CAPACITY_NOT_MET } },
  });
  assert.strictEqual(isOccurrenceCancelled(data, '2026-08-21'), true);
  assert.ok(!dueOccurrencesOf(data, now).some((d) => d.occurrenceId === '2026-08-21'));
});

test("'정상 진행'이거나 최소 인원이 없으면 회차 대상이 없다", () => {
  const now = new Date('2026-08-21T09:30:00Z');
  assert.deepStrictEqual(
    dueOccurrencesOf(recurringParty({ minCapacityPolicy: 'proceed' }), now),
    [],
  );
  assert.deepStrictEqual(
    dueOccurrencesOf(recurringParty({ partyMinCapacity: 0 }), now),
    [],
  );
});

test('회차 취소는 파티 문서 전체를 취소하지 않는다', () => {
  const data = recurringParty();
  const fields = occurrenceCancelFields(data, '2026-08-21', 2);
  // recruitStatus를 건드리지 않아야 다른 날짜 회차가 그대로 열려 있다.
  assert.strictEqual(fields.recruitStatus, undefined);
  const entry = fields['occurrenceCancellations.2026-08-21'];
  assert.strictEqual(entry.reason, MIN_CAPACITY_NOT_MET);
  assert.strictEqual(entry.minCapacityAtCancel, 6);
  assert.strictEqual(entry.participantsAtCancel, 2);
});

test('회차 취소 알림은 "그 회차만" 취소됐다고 알린다', () => {
  const data = recurringParty();
  const applicant = notificationDoc({
    uid: 'u1',
    partyId: 'p1',
    partyTitle: '수금일 와인',
    role: 'applicant',
    data,
    occurrenceId: '2026-08-21',
    participants: 2,
  });
  assert.strictEqual(applicant.occurrenceId, '2026-08-21');
  assert.ok(applicant.body.includes('2026-08-21 회차'));
  assert.ok(applicant.body.includes('다른 날짜 회차는 그대로'));
  assert.ok(applicant.body.includes('전액 환불'));
});

// ── 확정 인원 — 나머지 상태들 ───────────────────────────────────────────
test('취소·거절·만료 신청은 확정 인원에서 빠진다', () => {
  const apps = [
    { status: 'applied' },
    { status: 'approved' },
    { status: 'cancelled' },
    { status: 'rejected' },
    { status: 'expired' }, // 무통장입금 기한 초과
    { status: 'no_show' },
    { status: 'pending' },
  ];
  assert.strictEqual(confirmedCountOf(apps), 2);
  for (const s of ['cancelled', 'rejected', 'expired', 'no_show', 'pending']) {
    assert.strictEqual(
      isConfirmedApplication({ status: s }),
      false,
      `${s}는 확정 인원이 아니다`,
    );
  }
  // 현장결제 예정처럼 아직 돈이 안 들어온 신청도 참가는 확정이다.
  assert.strictEqual(
    isConfirmedApplication({
      status: 'applied',
      payment: { status: 'on_site_scheduled' },
    }),
    true,
  );
});

// ── 자동 취소 OFF ───────────────────────────────────────────────────────
test('자동 취소를 끄면 미달이어도 회차를 취소하지 않는다', () => {
  const now = new Date('2026-08-21T09:30:00Z');
  const off = recurringParty({ minCapacityPolicy: 'proceed' });
  assert.strictEqual(autoCancelsBelowMin(off), false);
  assert.deepStrictEqual(dueOccurrencesOf(off, now), []);
  // 값(최소 인원)은 그대로 남아 '확정' 표시에만 쓰인다.
  assert.strictEqual(partyMinCapacityOf(off), 6);
});

test('자동 취소를 끄면 일회성 파티도 마감 후 미달이어도 그대로다', () => {
  assert.strictEqual(
    shouldAutoCancel(party({ minCapacityPolicy: 'proceed' }), NOW),
    false,
  );
  assert.strictEqual(
    isAutoCancelCandidate(party({ minCapacityPolicy: 'proceed' }), NOW),
    false,
  );
});

// ── 취소된 회차는 신청을 받지 않는다 (applyToParty 가드) ────────────────
//
// 회차 취소는 파티 문서의 recruitStatus를 건드리지 않으므로, 기존 마감 검사만
// 으로는 걸러지지 않는다 — partyCapacity.js가 취소 기록을 따로 봐야 한다.
// 여기서 확인하는 것이 "A회차만 막히고 B회차는 그대로 열려 있는가"다.
const { reserveApplicantSlot } = require('./partyCapacity');

const DAY = 24 * 3600e3;
const dayId = (d) =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(
    d.getDate(),
  ).padStart(2, '0')}`;
// 회차는 항상 미래여야 한다(과거면 '이미 시작한 회차' 판정에 먼저 걸려
// 이 검증이 무엇을 봤는지 알 수 없게 된다).
const OCC_A = dayId(new Date(Date.now() + 7 * DAY));
const OCC_B = dayId(new Date(Date.now() + 14 * DAY));
const occOf = (id) => {
  const [y, m, d] = id.split('-').map(Number);
  const start = new Date(y, m - 1, d, 19, 0, 0);
  return { id, start, end: new Date(start.getTime() + 3 * 3600e3), deadline: null };
};

function applyParty(cancellations = {}) {
  return {
    recruitStatus: '모집중', // 파티 전체는 여전히 모집중이다
    scheduleType: 'recurring',
    genderCapacityMode: 'unlimited',
    genderLimit: 'all',
    maxParticipants: 10,
    partyMinCapacity: 6,
    minCapacityPolicy: 'autoCancel',
    applicants: [],
    occurrenceStats: {},
    occurrenceCancellations: cancellations,
  };
}

const tryApply = (data, occurrenceId) =>
  reserveApplicantSlot(data, {
    uid: 'u1',
    gender: 'male',
    birthYear: 1995,
    occurrence: occOf(occurrenceId),
    occurrenceId,
  });

test('A회차가 취소되면 A회차 신청은 막힌다', () => {
  const data = applyParty({
    [OCC_A]: { reason: MIN_CAPACITY_NOT_MET, participantsAtCancel: 2 },
  });
  assert.throws(() => tryApply(data, OCC_A), /취소된 회차/);
});

test('A회차가 취소돼도 B회차는 그대로 신청할 수 있다', () => {
  const data = applyParty({
    [OCC_A]: { reason: MIN_CAPACITY_NOT_MET, participantsAtCancel: 2 },
  });
  assert.doesNotThrow(() => tryApply(data, OCC_B));
});

test('취소 기록이 없으면 두 회차 모두 신청할 수 있다', () => {
  const data = applyParty();
  assert.doesNotThrow(() => tryApply(data, OCC_A));
  assert.doesNotThrow(() => tryApply(data, OCC_B));
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

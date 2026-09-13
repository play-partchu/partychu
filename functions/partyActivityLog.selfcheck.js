// 호스트 활동로그(party_updated) 자체 검증 — `npm run check:partyactivity`.
//
// 못 박는 것은 하나다: **신청·취소로 인원이 움직이는 것은 "호스트가 파티를
// 수정한 것"이 아니다.**
//
// 예전에는 onPartyActivityLog가 무시할 필드를 네 개(applicants·인원 카운터 3종)만
// 들고 있었다. 그런데 partyCapacity.js의 reserveApplicantSlot/releaseApplicantSlot은
// 그보다 훨씬 많은 필드를 건드린다 — 표시 문자열 `people`, 승인/거절 명단,
// 정기 파티의 `occurrenceStats`, 차수 파티의 `rounds[]` 인원 칸. 그래서 신청이
// 한 건 들어올 때마다 호스트 타임라인에 party_updated가 찍혔다.
//
// 이 파일이 지키는 것은 두 가지다.
//   ① 용량 헬퍼가 실제로 쓰는 필드가 전부 "시스템 관리" 목록에 들어 있는지
//      — 목록을 손으로 관리하다 빠뜨리는 것이 이 버그의 원인이었으므로,
//        진짜 코드가 돌려주는 키에서 역으로 검증한다.
//   ② 호스트가 제목·가격·날짜·환불정책·차수 정의를 고친 것은 계속 로그로
//      남는지.

process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'selfcheck';

const assert = require('assert');
const { reserveApplicantSlot, releaseApplicantSlot } = require('./partyCapacity');
const { isHostContentEdit, SYSTEM_MANAGED_PARTY_KEYS } = require('./memberManagement').__test;

const cases = [];
const test = (name, fn) => cases.push([name, fn]);

// 서버가 다시 쓰지만 값이 그대로라 변경으로 잡히지 않는 필드
// (차수 정원의 합 — 신청/취소로는 변하지 않는다).
const REWRITTEN_BUT_STABLE = new Set(['maxParticipants', 'maxCapacity']);
// 인원 칸만 걷어내고 비교하는 필드.
const COUNTER_STRIPPED = new Set(['rounds']);

/** `occurrenceStats.8-22.rounds` 같은 경로를 최상단 필드명으로 줄인다. */
const topLevel = (key) => String(key).split('.')[0];

/** Firestore Timestamp와 같은 모양(일 단위 오프셋). */
const ts = (days) => {
  const at = new Date(Date.now() + days * 864e5);
  return {
    _seconds: Math.floor(at.getTime() / 1000),
    _nanoseconds: 0,
    toDate: () => at,
  };
};

const simpleParty = () => ({
  hostId: 'host1',
  title: '테스트 파티',
  recruitStatus: '모집중',
  pricingType: 'same',
  price: 30000,
  maxParticipants: 10,
  currentParticipants: 2,
  currentMaleCount: 1,
  currentFemaleCount: 1,
  people: '2/10명',
  applicants: ['a', 'b'],
  genderCapacityMode: 'unlimited',
  genderLimit: 'all',
  // 실제 트리거가 받는 것과 같은 모양으로 둔다 — Firestore Timestamp는
  // _seconds/_nanoseconds를 자기 속성으로 들고 있어 JSON 비교에 그대로 잡힌다.
  partyDateTime: ts(7),
  refundPolicy: [{ daysBefore: 3, refundPercent: 80 }],
});

const roundParty = () => ({
  ...simpleParty(),
  hasMultipleRounds: true,
  roundCapacityMode: 'perRound',
  rounds: [
    {
      roundNumber: 1,
      label: '1부',
      maxCapacity: 5,
      maleCapacity: 3,
      femaleCapacity: 2,
      maleFee: 30000,
      femaleFee: 20000,
      currentParticipants: 1,
      currentMaleCount: 1,
      currentFemaleCount: 0,
    },
  ],
});

// ── ① 용량 헬퍼가 쓰는 필드가 전부 목록에 잡히는지 ───────────────────────
//
// 이 검사가 이 파일의 핵심이다. 앞으로 누가 reserveApplicantSlot에 새 필드를
// 더하면, 그 필드를 목록에 넣기 전까지 여기서 빨간불이 난다.

function assertKeysCovered(updateData, label) {
  const uncovered = Object.keys(updateData)
    .map(topLevel)
    .filter(
      (k) =>
        !SYSTEM_MANAGED_PARTY_KEYS.has(k) &&
        !REWRITTEN_BUT_STABLE.has(k) &&
        !COUNTER_STRIPPED.has(k),
    );
  assert.deepStrictEqual(
    [...new Set(uncovered)],
    [],
    `${label}: 시스템 관리 목록에 없는 필드가 파티 문서에 쓰인다 -> 신청마다 party_updated가 남는다`,
  );
}

test('일회성 파티 신청이 쓰는 필드가 전부 시스템 관리로 분류된다', () => {
  const { updateData } = reserveApplicantSlot(simpleParty(), {
    uid: 'newbie', gender: 'female', birthYear: 1995,
  });
  assertKeysCovered(updateData, 'reserveApplicantSlot(일회성)');
});

test('일회성 파티 취소가 쓰는 필드가 전부 시스템 관리로 분류된다', () => {
  const updateData = releaseApplicantSlot(simpleParty(), { uid: 'a', gender: 'male' });
  assertKeysCovered(updateData, 'releaseApplicantSlot(일회성)');
});

test('차수 파티 신청이 쓰는 필드가 전부 시스템 관리로 분류된다', () => {
  const { updateData } = reserveApplicantSlot(roundParty(), {
    uid: 'newbie', gender: 'female', birthYear: 1995, selectedRounds: [1],
  });
  assertKeysCovered(updateData, 'reserveApplicantSlot(차수)');
});

test('차수 파티 취소가 쓰는 필드가 전부 시스템 관리로 분류된다', () => {
  const updateData = releaseApplicantSlot(roundParty(), {
    uid: 'a', gender: 'male', selectedRounds: [1],
  });
  assertKeysCovered(updateData, 'releaseApplicantSlot(차수)');
});

test('정기 파티 회차 신청이 쓰는 필드도(occurrenceStats.*) 전부 분류된다', () => {
  // 회차 id만 넘겨 occurrenceStats 쓰기 경로를 태운다(정기 일정 규칙 검증은
  // partySchedule.selfcheck.js 몫이라 여기서는 재현하지 않는다).
  const party = {
    ...simpleParty(),
    occurrenceStats: { '2026-09-05': { currentParticipants: 1, applicants: ['a'] } },
  };
  const { updateData } = reserveApplicantSlot(party, {
    uid: 'newbie', gender: 'female', birthYear: 1995, occurrenceId: '2026-09-05',
  });
  assertKeysCovered(updateData, 'reserveApplicantSlot(정기 회차)');
});

// ── ② 시스템 변경만 있으면 로그를 남기지 않는다 ──────────────────────────

test('people만 바뀌면 파티 수정이 아니다 — 이번 버그의 재현 케이스', () => {
  const before = simpleParty();
  const after = { ...before, people: '3/10명' };
  assert.strictEqual(isHostContentEdit(before, after), false);
});

test('신청 한 건이 만드는 변화 전체(명단+카운터+people)도 파티 수정이 아니다', () => {
  const before = simpleParty();
  const after = {
    ...before,
    applicants: ['a', 'b', 'c'],
    currentParticipants: 3,
    currentFemaleCount: 2,
    people: '3/10명',
  };
  assert.strictEqual(isHostContentEdit(before, after), false);
});

test('취소가 승인/거절 명단에서 uid를 빼는 것도 파티 수정이 아니다', () => {
  const before = { ...simpleParty(), approvedApplicants: ['a'], rejectedApplicants: ['z'] };
  const after = {
    ...before,
    applicants: ['b'],
    approvedApplicants: [],
    rejectedApplicants: [],
    currentParticipants: 1,
    currentMaleCount: 0,
    people: '1/10명',
  };
  assert.strictEqual(isHostContentEdit(before, after), false);
});

test('정기 파티의 회차 칸(occurrenceStats)만 움직이는 것도 파티 수정이 아니다', () => {
  const before = { ...simpleParty(), occurrenceStats: { '2026-09-05': { currentParticipants: 1 } } };
  const after = {
    ...before,
    occurrenceStats: { '2026-09-05': { currentParticipants: 2, applicants: ['a'] } },
  };
  assert.strictEqual(isHostContentEdit(before, after), false);
});

test('차수 인원만 오른 rounds[]는 파티 수정이 아니다', () => {
  const before = roundParty();
  const after = {
    ...before,
    rounds: [{ ...before.rounds[0], currentParticipants: 2, currentFemaleCount: 1 }],
  };
  assert.strictEqual(isHostContentEdit(before, after), false);
});

test('생성 직후 onPartyCreated가 찍는 isTestAccount는 파티 수정이 아니다', () => {
  const before = simpleParty();
  const after = { ...before, isTestAccount: false };
  assert.strictEqual(isHostContentEdit(before, after), false);
});

test('변경이 아예 없으면 로그를 남기지 않는다', () => {
  assert.strictEqual(isHostContentEdit(simpleParty(), simpleParty()), false);
});

// ── ③ 호스트가 실제로 고친 것은 계속 로그로 남는다 ───────────────────────

const hostEdits = {
  '제목': (p) => ({ ...p, title: '바뀐 제목' }),
  '설명': (p) => ({ ...p, description: '새 설명' }),
  '날짜': (p) => ({ ...p, partyDateTime: ts(14) }),
  '장소': (p) => ({ ...p, placeName: '새 장소' }),
  '가격': (p) => ({ ...p, price: 50000 }),
  '환불정책': (p) => ({ ...p, refundPolicy: [{ daysBefore: 7, refundPercent: 50 }] }),
  '정원': (p) => ({ ...p, maxParticipants: 20 }),
  '모집상태(마감)': (p) => ({ ...p, recruitStatus: '마감' }),
  '오픈상태': (p) => ({ ...p, openState: 'open' }),
};
for (const [label, edit] of Object.entries(hostEdits)) {
  test(`호스트가 ${label}을(를) 고치면 파티 수정으로 남는다`, () => {
    const before = simpleParty();
    assert.strictEqual(isHostContentEdit(before, edit(before)), true);
  });
}

test('호스트가 차수 정의(정원·참가비)를 고치면 파티 수정으로 남는다', () => {
  const before = roundParty();
  const after = {
    ...before,
    rounds: [{ ...before.rounds[0], maxCapacity: 8, maleFee: 40000 }],
  };
  assert.strictEqual(isHostContentEdit(before, after), true);
});

test('인원과 차수 정의가 같이 바뀌면 파티 수정으로 남는다', () => {
  const before = roundParty();
  const after = {
    ...before,
    people: '3/10명',
    currentParticipants: 3,
    rounds: [{ ...before.rounds[0], label: '1부(변경)', currentParticipants: 3 }],
  };
  assert.strictEqual(isHostContentEdit(before, after), true);
});

test('필드가 지워진 것도 파티 수정이다 — after 키만 훑던 옛 로직이 놓치던 구간', () => {
  const before = simpleParty();
  const after = { ...before };
  delete after.refundPolicy;
  assert.strictEqual(isHostContentEdit(before, after), true);
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
    ? `\n파티 활동로그 검증 통과 — ${cases.length}건`
    : `\n실패 ${failed}건 / 전체 ${cases.length}건`,
);
process.exit(failed === 0 ? 0 : 1);

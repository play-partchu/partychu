// 회차별 모집 상태 자체 검증 — `node partyOccurrenceRecruit.selfcheck.js`.
//
// 확인하는 것은 두 층이다:
//   1) 판정 헬퍼(partyOccurrenceRecruit.js) — 앱(party_occurrence_recruit.dart)의 거울
//   2) **실제 신청 차단**(reserveApplicantSlot) — 표시만 바뀌고 신청이 뚫리는
//      일이 없도록, 회차를 바꿔 가며 그대로 통과시켜 본다.
//
// 이 기능의 약속은 하나다: **한 회차를 닫아도 다른 회차는 그대로 열려 있다.**
// 반복 파티가 통째로 닫히는 회귀를 여기서 잡는다.

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
  occurrenceStatusOf,
  isMaleClosedAt,
  isFemaleClosedAt,
  isGenderRecruitClosedAt,
} = require('./partyOccurrenceRecruit');
const { reserveApplicantSlot } = require('./partyCapacity');
const { occurrenceIdOf } = require('./partyMinCapacity');

const DAY = 24 * 3600e3;
const day1 = new Date(Date.now() + 3 * DAY);
const day2 = new Date(Date.now() + 10 * DAY);
const OCC1 = occurrenceIdOf(day1);
const OCC2 = occurrenceIdOf(day2);
const ts = (d) => ({ toDate: () => d });

/** 정기 파티 한 건 — 남녀별 정원(성별 판정이 실제로 걸리는 형태). */
function party(occurrenceRecruit, extra = {}) {
  return {
    recruitStatus: '모집중',
    scheduleType: 'recurring',
    partyDateTime: ts(day1),
    genderCapacityMode: 'separate',
    maleCapacity: 10,
    femaleCapacity: 10,
    currentMaleCount: 0,
    currentFemaleCount: 0,
    ...(occurrenceRecruit ? { occurrenceRecruit } : {}),
    ...extra,
  };
}

const occurrenceOf = (start) => ({
  start,
  end: start,
  deadline: null,
  recruitOpenAt: null,
});

const cases = [];
const test = (n, f) => cases.push([n, f]);

/** 그 회차에 신청이 실제로 통과하는가(자리를 잡았는가). */
function applies(data, gender, start) {
  const id = occurrenceIdOf(start);
  const r = reserveApplicantSlot(data, {
    uid: 'u1',
    gender,
    occurrence: occurrenceOf(start),
    occurrenceId: id,
  });
  const key =
    gender === 'male'
      ? `occurrenceStats.${id}.currentMaleCount`
      : `occurrenceStats.${id}.currentFemaleCount`;
  assert.ok(
    r.updateData[key] !== undefined || r.updateData.currentParticipants >= 0,
    '자리를 잡지 못했다'
  );
  return true;
}

/** 그 회차 신청이 막히는가 — 막히면 거절 문구를 돌려준다. */
function blocked(data, gender, start) {
  try {
    reserveApplicantSlot(data, {
      uid: 'u1',
      gender,
      occurrence: occurrenceOf(start),
      occurrenceId: occurrenceIdOf(start),
    });
    return null;
  } catch (e) {
    return e.message || `${e}`;
  }
}

// ── 판정 헬퍼 ──────────────────────────────────────────────────────────
test('회차 칸이 없으면 문서 값으로 폴백한다 — 기존 파티 무영향', () => {
  const data = party(null, { recruitStatus: '마감' });
  assert.strictEqual(occurrenceStatusOf(data, OCC1), '마감');
  assert.strictEqual(occurrenceStatusOf(data, null), '마감');
  assert.strictEqual(occurrenceStatusOf(party(null), OCC1), '모집중');
});

test('회차 칸이 문서 값을 이긴다 — 전체 마감 파티의 한 회차만 열 수 있다', () => {
  const data = party({ [OCC2]: { status: '모집중' } }, { recruitStatus: '마감' });
  assert.strictEqual(occurrenceStatusOf(data, OCC1), '마감');
  assert.strictEqual(occurrenceStatusOf(data, OCC2), '모집중');
});

test('모르는 값이 들어 있으면 문서 값으로 돌아간다', () => {
  const data = party({ [OCC1]: { status: '이상한값' } });
  assert.strictEqual(occurrenceStatusOf(data, OCC1), '모집중');
});

test('성별 칸도 회차별이고, 없으면 문서 값이다', () => {
  const data = party(
    { [OCC1]: { genderRecruitStatus: { male: 'open', female: 'closed' } } },
    { genderRecruitStatus: { male: 'closed', female: 'open' } }
  );
  assert.strictEqual(isFemaleClosedAt(data, OCC1), true);
  assert.strictEqual(isMaleClosedAt(data, OCC1), false);
  // 손대지 않은 회차는 문서 값 그대로.
  assert.strictEqual(isMaleClosedAt(data, OCC2), true);
  assert.strictEqual(isFemaleClosedAt(data, OCC2), false);
});

test('성별을 모르면 양쪽이 다 닫힌 회차에서만 닫힘이다', () => {
  const oneSide = party({
    [OCC1]: { genderRecruitStatus: { male: 'closed', female: 'open' } },
  });
  const bothSides = party({
    [OCC1]: { genderRecruitStatus: { male: 'closed', female: 'closed' } },
  });
  assert.strictEqual(isGenderRecruitClosedAt(oneSide, null, OCC1), false);
  assert.strictEqual(isGenderRecruitClosedAt(bothSides, null, OCC1), true);
});

// ── 실제 신청 차단 ─────────────────────────────────────────────────────
test('한 회차를 마감해도 다른 회차는 그대로 신청된다', () => {
  const data = party({ [OCC1]: { status: '마감' } });
  assert.strictEqual(blocked(data, 'male', day1), '마감');
  applies(data, 'male', day2);
});

test('회차 취소도 그 회차에만 걸린다', () => {
  const data = party({ [OCC1]: { status: '취소' } });
  assert.strictEqual(blocked(data, 'female', day1), '마감');
  applies(data, 'female', day2);
});

test('여성 모집만 닫은 회차 — 여성만 막히고 남성은 통과', () => {
  const data = party({
    [OCC1]: { genderRecruitStatus: { male: 'open', female: 'closed' } },
  });
  assert.strictEqual(blocked(data, 'female', day1), '여성 모집이 마감되었습니다.');
  applies(data, 'male', day1);
  // 다른 회차는 성별과 무관하게 열려 있다.
  applies(data, 'female', day2);
});

test('남성 모집만 닫은 회차 — 남성만 막히고 여성은 통과', () => {
  const data = party({
    [OCC1]: { genderRecruitStatus: { male: 'closed', female: 'open' } },
  });
  assert.strictEqual(blocked(data, 'male', day1), '남성 모집이 마감되었습니다.');
  applies(data, 'female', day1);
});

test('전체 마감인 회차는 성별 설정과 무관하게 아무도 신청할 수 없다', () => {
  const data = party({
    [OCC1]: {
      status: '마감',
      genderRecruitStatus: { male: 'open', female: 'open' },
    },
  });
  assert.strictEqual(blocked(data, 'male', day1), '마감');
  assert.strictEqual(blocked(data, 'female', day1), '마감');
});

test('전체 마감 파티에서 한 회차만 열면 그 회차만 신청된다', () => {
  const data = party({ [OCC2]: { status: '모집중' } }, { recruitStatus: '마감' });
  assert.strictEqual(blocked(data, 'male', day1), '마감');
  applies(data, 'male', day2);
});

test('회차 칸이 없는 정기 파티는 예전 판정 그대로다', () => {
  applies(party(null), 'male', day1);
  assert.strictEqual(blocked(party(null, { recruitStatus: '마감' }), 'male', day1), '마감');
});

test('일회성 파티(회차 없음)는 문서 값만 본다 — 예전 그대로', () => {
  const single = {
    recruitStatus: '모집중',
    partyDateTime: ts(day1),
    genderCapacityMode: 'separate',
    maleCapacity: 10,
    femaleCapacity: 10,
    currentMaleCount: 0,
    currentFemaleCount: 0,
    // 회차 칸이 있어도 회차를 모르는 신청에는 걸리지 않는다.
    occurrenceRecruit: { [OCC1]: { status: '마감' } },
  };
  const r = reserveApplicantSlot(single, { uid: 'u1', gender: 'male' });
  assert.strictEqual(r.updateData.currentMaleCount, 1);
});

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
console.log(
  failed === 0
    ? `\n회차별 모집 상태 ${cases.length}건 전부 통과`
    : `\n${failed}/${cases.length}건 실패`
);
process.exit(failed === 0 ? 0 : 1);

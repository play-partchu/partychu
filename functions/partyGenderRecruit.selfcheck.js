// 성별별 모집 상태 자체 검증 — `node partyGenderRecruit.selfcheck.js`.
//
// 확인하는 것은 두 층이다:
//   1) 판정 헬퍼(partyGenderRecruit.js) — 앱(party_gender_recruit.dart)의 거울
//   2) **실제 신청 차단**(reserveApplicantSlot) — 표시만 바뀌고 신청이 뚫리는
//      일이 없도록, 남/여 조합 네 가지를 그대로 통과시켜 본다.
//
// 조합: 남 모집중·여 모집중 / 남 마감·여 모집중 / 남 모집중·여 마감 / 전체 마감

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
  isMaleClosed,
  isFemaleClosed,
  isRecruitClosedFor,
  isFullyClosed,
} = require('./partyGenderRecruit');
const { reserveApplicantSlot } = require('./partyCapacity');

const future = new Date(Date.now() + 48 * 3600e3);
const ts = (d) => ({ toDate: () => d });

// 남녀별 정원(separate) 파티 — 성비 분리 모집이 이 기능의 주 무대다.
function party(genderRecruitStatus, extra = {}) {
  return {
    recruitStatus: '모집중',
    partyDateTime: ts(future),
    genderCapacityMode: 'separate',
    maleCapacity: 10,
    femaleCapacity: 10,
    currentMaleCount: 0,
    currentFemaleCount: 0,
    ...(genderRecruitStatus ? { genderRecruitStatus } : {}),
    ...extra,
  };
}

const BOTH_OPEN = null; // 필드 자체가 없는 기존 파티 = 남·여 모두 모집중
const MALE_CLOSED = { male: 'closed', female: 'open' };
const FEMALE_CLOSED = { male: 'open', female: 'closed' };
const BOTH_CLOSED = { male: 'closed', female: 'closed' };

const cases = [];
const test = (n, f) => cases.push([n, f]);

/** 신청이 실제로 통과하는가(정원 카운터가 올라갔는가). */
function applies(data, gender) {
  const r = reserveApplicantSlot(data, { uid: 'u1', gender });
  const key = gender === 'male' ? 'currentMaleCount' : 'currentFemaleCount';
  assert.strictEqual(r.updateData[key], 1, '자리를 잡지 못했다');
  return true;
}

// ── 1. 하위호환 — 필드가 없으면 예전 그대로 ────────────────────────────
test('필드 없음: 남·여 모두 모집중으로 읽힌다', () => {
  const p = party(BOTH_OPEN);
  assert.strictEqual(isMaleClosed(p), false);
  assert.strictEqual(isFemaleClosed(p), false);
  assert.strictEqual(isFullyClosed(p), false);
  assert.strictEqual(isRecruitClosedFor(p, 'male'), false);
  assert.strictEqual(isRecruitClosedFor(p, 'female'), false);
  assert.strictEqual(isRecruitClosedFor(p, null), false);
});

test('알 수 없는 값은 열림으로 읽는다(닫힘은 명시적 closed뿐)', () => {
  const p = party({ male: '마감', female: true });
  assert.strictEqual(isMaleClosed(p), false);
  assert.strictEqual(isFemaleClosed(p), false);
});

// ── 2. 조합 네 가지 — 판정 ────────────────────────────────────────────
test('조합 ① 남 모집중·여 모집중', () => {
  const p = party(BOTH_OPEN);
  assert.strictEqual(isRecruitClosedFor(p, 'male'), false);
  assert.strictEqual(isRecruitClosedFor(p, 'female'), false);
});

test('조합 ② 남 모집마감·여 모집중', () => {
  const p = party(MALE_CLOSED);
  assert.strictEqual(isRecruitClosedFor(p, 'male'), true);
  assert.strictEqual(isRecruitClosedFor(p, 'female'), false);
  assert.strictEqual(isFullyClosed(p), false); // 파티 전체는 아직 모집중이다
});

test('조합 ③ 남 모집중·여 모집마감', () => {
  const p = party(FEMALE_CLOSED);
  assert.strictEqual(isRecruitClosedFor(p, 'male'), false);
  assert.strictEqual(isRecruitClosedFor(p, 'female'), true);
  assert.strictEqual(isFullyClosed(p), false);
});

test('조합 ④ 전체 모집마감(남·여 모두 닫힘)', () => {
  const p = party(BOTH_CLOSED);
  assert.strictEqual(isRecruitClosedFor(p, 'male'), true);
  assert.strictEqual(isRecruitClosedFor(p, 'female'), true);
  assert.strictEqual(isFullyClosed(p), true);
  // 성별을 몰라도 막힌다 — 이때만 성별이 필요 없다.
  assert.strictEqual(isRecruitClosedFor(p, null), true);
});

test('한쪽만 닫힌 파티는 성별을 모르면 막지 않는다', () => {
  assert.strictEqual(isRecruitClosedFor(party(MALE_CLOSED), null), false);
  assert.strictEqual(isRecruitClosedFor(party(FEMALE_CLOSED), undefined), false);
});

test('성별 제한 파티: 받는 성별 하나만 닫혀도 전체 마감이다', () => {
  assert.strictEqual(
    isFullyClosed(party(MALE_CLOSED, { genderLimit: 'male' })),
    true,
  );
  // 남자만 받는 파티에서 '여성 모집마감'은 뜻이 없다 — 전체 마감이 아니다.
  assert.strictEqual(
    isFullyClosed(party(FEMALE_CLOSED, { genderLimit: 'male' })),
    false,
  );
});

// ── 3. 조합 네 가지 — 실제 신청 차단(reserveApplicantSlot) ─────────────
test('① 남 모집중·여 모집중 → 남녀 모두 신청된다', () => {
  assert.ok(applies(party(BOTH_OPEN), 'male'));
  assert.ok(applies(party(BOTH_OPEN), 'female'));
});

test('② 남 모집마감·여 모집중 → 남성만 막히고 여성은 신청된다', () => {
  assert.throws(
    () => reserveApplicantSlot(party(MALE_CLOSED), { uid: 'u1', gender: 'male' }),
    /남성 모집이 마감/,
  );
  assert.ok(applies(party(MALE_CLOSED), 'female'));
});

test('③ 남 모집중·여 모집마감 → 여성만 막히고 남성은 신청된다', () => {
  assert.throws(
    () => reserveApplicantSlot(party(FEMALE_CLOSED), { uid: 'u1', gender: 'female' }),
    /여성 모집이 마감/,
  );
  assert.ok(applies(party(FEMALE_CLOSED), 'male'));
});

test('④ 전체 모집마감 → 남녀 모두 막힌다', () => {
  assert.throws(
    () => reserveApplicantSlot(party(BOTH_CLOSED), { uid: 'u1', gender: 'male' }),
    /남성 모집이 마감/,
  );
  assert.throws(
    () => reserveApplicantSlot(party(BOTH_CLOSED), { uid: 'u1', gender: 'female' }),
    /여성 모집이 마감/,
  );
});

test('기존 전체 마감(recruitStatus)이 성별 설정보다 먼저다', () => {
  const p = party(MALE_CLOSED, { recruitStatus: '마감' });
  assert.throws(
    () => reserveApplicantSlot(p, { uid: 'u1', gender: 'female' }),
    /마감/,
  );
});

test('남녀무관(unlimited) 파티에도 그대로 걸린다', () => {
  const p = party(MALE_CLOSED, {
    genderCapacityMode: 'unlimited',
    maxParticipants: 20,
    currentParticipants: 0,
  });
  assert.throws(
    () => reserveApplicantSlot(p, { uid: 'u1', gender: 'male' }),
    /남성 모집이 마감/,
  );
  const ok = reserveApplicantSlot(p, { uid: 'u2', gender: 'female' });
  assert.strictEqual(ok.updateData.currentParticipants, 1);
});

test('정기 파티도 파티 문서 공통 설정이다 — 회차를 바꿔도 풀리지 않는다', () => {
  const p = party(MALE_CLOSED, {
    scheduleType: 'recurring',
    recurringSchedule: { days: [1, 2, 3, 4, 5, 6, 7], startTime: '19:00', endTime: '22:00' },
  });
  assert.throws(
    () => reserveApplicantSlot(p, { uid: 'u1', gender: 'male' }),
    /남성 모집이 마감/,
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

// 성별별 연령 제한 자체 검증 — `node partyAgeRestriction.selfcheck.js`.
//
// 두 층을 함께 본다.
//
//   ① partyAgeRestriction.js  — 저장 필드 조립 / 하위호환 읽기 / 자격 판정
//   ② partyCapacity.js reserveApplicantSlot — **서버의 유일한 강제 지점**
//
// ②가 이 파일의 핵심이다. 앱 화면이 회색으로 막아 두는 것과 무관하게,
// applyToParty / createPendingPackageBooking을 **직접 불러도** 자기 성별의
// 연령 범위를 벗어나면 거절돼야 한다. 생년·성별은 클라이언트 입력이 아니라
// 호출부가 users 문서(본인확인 정본)에서 읽어 넘기는 값이다.

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

const A = require('./partyAgeRestriction');
const { reserveApplicantSlot } = require('./partyCapacity');
const R = require('./partyRegistration');

const cases = [];
const test = (n, f) => cases.push([n, f]);

// 2026년 기준 남 25~35 / 여 23~32에 해당하는 출생연도. 테스트가 "돌리는 해"에
// 흔들리지 않도록 절대값으로 둔다.
const MALE = { enabled: true, minBirthYear: 1991, maxBirthYear: 2001 }; // 25~35
const FEMALE = { enabled: true, minBirthYear: 1994, maxBirthYear: 2003 }; // 23~32
const OFF = { enabled: false, minBirthYear: null, maxBirthYear: null };

const future = new Date(Date.now() + 48 * 3600e3);
const ts = (d) => ({ toDate: () => d });

/// reserveApplicantSlot이 받아들이는 가장 단순한 일회성 파티.
function partyDoc(ageFields, extra = {}) {
  return {
    recruitStatus: '모집중',
    partyDateTime: ts(future),
    genderCapacityMode: 'unlimited',
    genderLimit: 'all',
    maxParticipants: 50,
    currentParticipants: 0,
    ...ageFields,
    ...extra,
  };
}

/// 파티 문서에 신청을 시도한다 — 통과하면 true, 자격 미달이면 오류 메시지.
function tryApply(data, { gender, birthYear }) {
  try {
    reserveApplicantSlot(data, { uid: 'u1', gender, birthYear });
    return true;
  } catch (e) {
    return e.message;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ① 저장 필드 — ageFields()
// ═══════════════════════════════════════════════════════════════════════════

test('남녀 동일 제한 — 성별 필드 + 구버전용 공통 필드가 함께 남는다', () => {
  const f = A.ageFields({ enabled: true, male: MALE, female: MALE }, 'all');
  assert.deepStrictEqual(f, {
    ageRestrictionEnabled: true,
    maleAgeRestrictionEnabled: true,
    maleMinBirthYear: 1991,
    maleMaxBirthYear: 2001,
    femaleAgeRestrictionEnabled: true,
    femaleMinBirthYear: 1991,
    femaleMaxBirthYear: 2001,
    minBirthYear: 1991,
    maxBirthYear: 2001,
  });
});

test('남녀 다른 제한 — 공통 필드는 합집합(가장 넓은 범위)', () => {
  const f = A.ageFields({ enabled: true, male: MALE, female: FEMALE }, 'all');
  assert.strictEqual(f.maleMinBirthYear, 1991);
  assert.strictEqual(f.femaleMaxBirthYear, 2003);
  assert.strictEqual(f.minBirthYear, 1991);
  assert.strictEqual(f.maxBirthYear, 2003);
});

test('남성만 제한 — 여성 필드도, 공통 필드도 만들지 않는다', () => {
  const f = A.ageFields({ enabled: true, male: MALE, female: OFF }, 'all');
  assert.strictEqual(f.maleAgeRestrictionEnabled, true);
  assert.strictEqual(f.femaleAgeRestrictionEnabled, false);
  assert.ok(!('femaleMinBirthYear' in f));
  // 한쪽이 제한 없음이면 공통 범위로 표현할 수 없다 → 필드를 아예 안 쓴다.
  assert.ok(!('minBirthYear' in f));
  assert.ok(!('maxBirthYear' in f));
});

test('여성만 제한 — 남성 필드도, 공통 필드도 만들지 않는다', () => {
  const f = A.ageFields({ enabled: true, male: OFF, female: FEMALE }, 'all');
  assert.strictEqual(f.maleAgeRestrictionEnabled, false);
  assert.strictEqual(f.femaleAgeRestrictionEnabled, true);
  assert.ok(!('maleMinBirthYear' in f));
  assert.ok(!('minBirthYear' in f));
});

test('여성만 모집 파티 — 남성 제한은 지워진다(유령 값 방지)', () => {
  const f = A.ageFields({ enabled: true, male: MALE, female: FEMALE }, 'female');
  assert.strictEqual(f.maleAgeRestrictionEnabled, false);
  assert.ok(!('maleMinBirthYear' in f));
  // 모집하는 성별이 여성뿐이므로 공통 범위는 여성 범위 그대로다.
  assert.strictEqual(f.minBirthYear, 1994);
  assert.strictEqual(f.maxBirthYear, 2003);
});

test('남성만 모집 파티 — 여성 제한은 지워진다', () => {
  const f = A.ageFields({ enabled: true, male: MALE, female: FEMALE }, 'male');
  assert.strictEqual(f.femaleAgeRestrictionEnabled, false);
  assert.ok(!('femaleMinBirthYear' in f));
  assert.strictEqual(f.minBirthYear, 1991);
  assert.strictEqual(f.maxBirthYear, 2001);
});

test('마스터 스위치는 켰지만 성별 제한이 하나도 없으면 꺼진 것으로 저장된다', () => {
  const f = A.ageFields({ enabled: true, male: OFF, female: OFF }, 'all');
  assert.deepStrictEqual(f, { ageRestrictionEnabled: false });
});

test('마스터 스위치가 꺼져 있으면 성별 값이 있어도 저장하지 않는다', () => {
  const f = A.ageFields({ enabled: false, male: MALE, female: FEMALE }, 'all');
  assert.deepStrictEqual(f, { ageRestrictionEnabled: false });
});

test('여성만 모집 + 여성 제한 없음 — 남성 제한이 남아 있어도 꺼진 것으로 저장', () => {
  const f = A.ageFields({ enabled: true, male: MALE, female: OFF }, 'female');
  assert.deepStrictEqual(f, { ageRestrictionEnabled: false });
});

// ═══════════════════════════════════════════════════════════════════════════
// ② 입력 정규화 — normalizeAgeInput()
// ═══════════════════════════════════════════════════════════════════════════

test('옛 스키마 입력(공통 minBirthYear/maxBirthYear)은 남녀 양쪽에 채워진다', () => {
  const n = A.normalizeAgeInput({ enabled: true, minBirthYear: 1990, maxBirthYear: 2000 });
  assert.deepStrictEqual(n.male, { enabled: true, minBirthYear: 1990, maxBirthYear: 2000 });
  assert.deepStrictEqual(n.female, { enabled: true, minBirthYear: 1990, maxBirthYear: 2000 });
});

test('성별 블록이 하나라도 있으면 새 스키마로 읽는다', () => {
  const n = A.normalizeAgeInput({
    enabled: true,
    male: { enabled: true, minBirthYear: 1991, maxBirthYear: 2001 },
  });
  assert.strictEqual(n.male.enabled, true);
  assert.strictEqual(n.female.enabled, false);
});

// ═══════════════════════════════════════════════════════════════════════════
// ③ 문서 읽기 하위호환 — parseAgeRestriction()
// ═══════════════════════════════════════════════════════════════════════════

test('기존 파티(공통 필드만) — 남녀 모두에게 같은 범위가 적용된다', () => {
  const age = A.parseAgeRestriction({
    ageRestrictionEnabled: true,
    minBirthYear: 1990,
    maxBirthYear: 2000,
  });
  assert.strictEqual(age.perGender, false);
  assert.strictEqual(A.allowsApplicant(age, 'male', 1995), true);
  assert.strictEqual(A.allowsApplicant(age, 'female', 1995), true);
  assert.strictEqual(A.allowsApplicant(age, 'male', 2002), false);
  assert.strictEqual(A.allowsApplicant(age, 'female', 1989), false);
});

test('기존 파티 — 성별을 몰라도 예전처럼 범위만으로 판정한다', () => {
  const age = A.parseAgeRestriction({
    ageRestrictionEnabled: true,
    minBirthYear: 1990,
    maxBirthYear: 2000,
  });
  assert.strictEqual(A.allowsApplicant(age, null, 1995), true);
  assert.strictEqual(A.allowsApplicant(age, null, 2002), false);
});

test('신규 파티 — 성별을 모르면 판정 불가(우회 차단)', () => {
  const age = A.parseAgeRestriction({
    ageRestrictionEnabled: true,
    maleAgeRestrictionEnabled: true,
    maleMinBirthYear: 1991,
    maleMaxBirthYear: 2001,
    femaleAgeRestrictionEnabled: false,
  });
  assert.strictEqual(A.effectiveLimitFor(age, null), null);
  assert.strictEqual(A.allowsApplicant(age, null, 1995), false);
});

// ═══════════════════════════════════════════════════════════════════════════
// ④ 신청 자격 — 서버 강제 지점(reserveApplicantSlot)
// ═══════════════════════════════════════════════════════════════════════════

const DIFFERENT = partyDoc(A.ageFields({ enabled: true, male: MALE, female: FEMALE }, 'all'));

test('남녀 다른 제한 — 24세 남성은 신청 불가', () => {
  // 2026년 기준 24세 = 2002년생. 남성 범위(1991~2001) 밖.
  assert.match(tryApply(DIFFERENT, { gender: 'male', birthYear: 2002 }), /연령제한/);
});

test('남녀 다른 제한 — 24세 여성은 신청 가능', () => {
  // 여성 범위(1994~2003) 안.
  assert.strictEqual(tryApply(DIFFERENT, { gender: 'female', birthYear: 2002 }), true);
});

test('남녀 다른 제한 — 36세 남성은 신청 불가', () => {
  // 2026년 기준 36세 = 1990년생. 남성 하한(1991)보다 이르다.
  assert.match(tryApply(DIFFERENT, { gender: 'male', birthYear: 1990 }), /연령제한/);
});

test('남녀 다른 제한 — 33세 여성은 신청 불가', () => {
  // 2026년 기준 33세 = 1993년생. 여성 하한(1994)보다 이르다.
  assert.match(tryApply(DIFFERENT, { gender: 'female', birthYear: 1993 }), /연령제한/);
});

test('경계 나이 — min/max 당사자는 신청 가능(포함)', () => {
  assert.strictEqual(tryApply(DIFFERENT, { gender: 'male', birthYear: 1991 }), true);
  assert.strictEqual(tryApply(DIFFERENT, { gender: 'male', birthYear: 2001 }), true);
  assert.strictEqual(tryApply(DIFFERENT, { gender: 'female', birthYear: 1994 }), true);
  assert.strictEqual(tryApply(DIFFERENT, { gender: 'female', birthYear: 2003 }), true);
});

test('경계 밖 한 살 — 양쪽 모두 거절', () => {
  assert.match(tryApply(DIFFERENT, { gender: 'male', birthYear: 1990 }), /연령제한/);
  assert.match(tryApply(DIFFERENT, { gender: 'male', birthYear: 2002 }), /연령제한/);
  assert.match(tryApply(DIFFERENT, { gender: 'female', birthYear: 1993 }), /연령제한/);
  assert.match(tryApply(DIFFERENT, { gender: 'female', birthYear: 2004 }), /연령제한/);
});

test('남성만 제한 — 여성은 나이와 무관하게 신청 가능', () => {
  const data = partyDoc(A.ageFields({ enabled: true, male: MALE, female: OFF }, 'all'));
  assert.strictEqual(tryApply(data, { gender: 'female', birthYear: 1970 }), true);
  assert.strictEqual(tryApply(data, { gender: 'female', birthYear: 2007 }), true);
  assert.match(tryApply(data, { gender: 'male', birthYear: 1970 }), /연령제한/);
  assert.strictEqual(tryApply(data, { gender: 'male', birthYear: 1995 }), true);
});

test('여성만 제한 — 남성은 나이와 무관하게 신청 가능', () => {
  const data = partyDoc(A.ageFields({ enabled: true, male: OFF, female: FEMALE }, 'all'));
  assert.strictEqual(tryApply(data, { gender: 'male', birthYear: 1970 }), true);
  assert.match(tryApply(data, { gender: 'female', birthYear: 1970 }), /연령제한/);
});

test('남성만 제한 — 제한 없는 성별은 생년을 몰라도 통과한다', () => {
  const data = partyDoc(A.ageFields({ enabled: true, male: MALE, female: OFF }, 'all'));
  assert.strictEqual(tryApply(data, { gender: 'female', birthYear: null }), true);
  assert.match(tryApply(data, { gender: 'male', birthYear: null }), /연령미인증/);
});

test('성별별 제한 파티는 성별을 안 보낸 직접 호출을 거절한다(우회 차단)', () => {
  assert.match(tryApply(DIFFERENT, { gender: null, birthYear: 1995 }), /미인증/);
});

test('기존 파티(공통 필드) — 판정도 저장도 예전 그대로', () => {
  const legacy = partyDoc({
    ageRestrictionEnabled: true,
    minBirthYear: 1990,
    maxBirthYear: 2000,
  });
  assert.strictEqual(tryApply(legacy, { gender: 'male', birthYear: 1995 }), true);
  assert.strictEqual(tryApply(legacy, { gender: 'female', birthYear: 1995 }), true);
  assert.match(tryApply(legacy, { gender: 'male', birthYear: 2002 }), /연령제한/);
  // 성별을 몰라도 예전처럼 통과한다 — 이 변경으로 기존 파티 동작이 달라지면 안 된다.
  assert.strictEqual(tryApply(legacy, { gender: null, birthYear: 1995 }), true);
});

test('연령 제한이 없는 파티는 생년·성별을 몰라도 통과한다', () => {
  const open = partyDoc({ ageRestrictionEnabled: false });
  assert.strictEqual(tryApply(open, { gender: null, birthYear: null }), true);
});

test('여성만 모집 파티 — 남성의 옛 제한이 남성 신청 판정에 되살아나지 않는다', () => {
  // 저장 시점에 남성 제한이 지워지므로, 문서에는 여성 제한만 남는다.
  // (성별 제한 자체는 genderLimit이 따로 막는다 — 여기서는 연령 판정만 본다.)
  const data = partyDoc(
    A.ageFields({ enabled: true, male: MALE, female: FEMALE }, 'female'),
    { genderLimit: 'all' }
  );
  assert.strictEqual(tryApply(data, { gender: 'male', birthYear: 1970 }), true);
  assert.match(tryApply(data, { gender: 'female', birthYear: 1970 }), /연령제한/);
});

// ═══════════════════════════════════════════════════════════════════════════
// ⑤ 등록 정본과의 연결 — createParty 입력 → 파티 문서
// ═══════════════════════════════════════════════════════════════════════════

function registeredFields(ageInput, capacityOverride = {}) {
  const input = R.normalizeInput({
    title: '연령 테스트 파티',
    description: '',
    capacity: {
      genderLimit: 'all',
      genderCapacityMode: 'unlimited',
      maxCapacity: 20,
      minCapacity: 0,
      ...capacityOverride,
    },
    pricing: { male: 0, female: 0 },
    earlyBird: { enabled: false },
    refundTiers: [{ daysBefore: 1, refundPercent: 100 }],
    age: ageInput,
    taxonomy: { partyTypes: [], vibes: [], tags: [] },
    schedule: {
      type: 'single',
      slots: [{ date: '2099-10-02', startTime: '19:00', endTime: '23:00' }],
      deadlineRule: { mode: 'none' },
      openRule: { mode: 'none' },
    },
  });
  const slot = input.schedule.slots[0];
  return R.buildSharedFields(input, {
    primarySlot: slot,
    businessVerified: true,
    now: new Date('2026-01-01T00:00:00Z'),
  });
}

test('등록 정본(createParty)도 성별별 필드를 만든다', () => {
  const f = registeredFields({
    enabled: true,
    male: { enabled: true, minBirthYear: 1991, maxBirthYear: 2001 },
    female: { enabled: true, minBirthYear: 1994, maxBirthYear: 2003 },
  });
  assert.strictEqual(f.maleMinBirthYear, 1991);
  assert.strictEqual(f.femaleMaxBirthYear, 2003);
  assert.strictEqual(f.minBirthYear, 1991);
  assert.strictEqual(f.maxBirthYear, 2003);
});

test('등록 → 저장 → 신청 판정이 한 줄로 이어진다', () => {
  const doc = partyDoc(
    registeredFields({
      enabled: true,
      male: { enabled: true, minBirthYear: 1991, maxBirthYear: 2001 },
      female: { enabled: true, minBirthYear: 1994, maxBirthYear: 2003 },
    })
  );
  assert.match(tryApply(doc, { gender: 'male', birthYear: 2002 }), /연령제한/);
  assert.strictEqual(tryApply(doc, { gender: 'female', birthYear: 2002 }), true);
});

test('등록 검증 — 뒤집힌 범위는 거절된다(직접 호출 방어)', () => {
  const input = {
    title: 't',
    capacity: { genderLimit: 'all', genderCapacityMode: 'unlimited', maxCapacity: 10 },
    pricing: { male: 0, female: 0 },
    refundTiers: [{ daysBefore: 1, refundPercent: 100 }],
    age: {
      enabled: true,
      male: { enabled: true, minBirthYear: 2001, maxBirthYear: 1991 },
      female: { enabled: false },
    },
    taxonomy: {},
    schedule: {
      type: 'single',
      slots: [{ date: '2099-10-02', startTime: '19:00', endTime: '23:00' }],
    },
  };
  const errors = R.validateRegistration(R.normalizeInput(input), {
    now: new Date('2026-01-01T00:00:00Z'),
  });
  assert.ok(errors.some((e) => e.field === 'age'), '연령 오류가 보고되지 않았습니다.');
});

test('등록 검증 — 모집하지 않는 성별의 뒤집힌 범위는 등록을 막지 않는다', () => {
  const input = {
    title: 't',
    capacity: { genderLimit: 'female', genderCapacityMode: 'unlimited', maxCapacity: 10 },
    pricing: { male: 0, female: 0 },
    refundTiers: [{ daysBefore: 1, refundPercent: 100 }],
    age: {
      enabled: true,
      // 남성 범위가 뒤집혀 있지만 남성은 모집하지 않는다 → 저장 전에 지워진다.
      male: { enabled: true, minBirthYear: 2001, maxBirthYear: 1991 },
      female: { enabled: true, minBirthYear: 1994, maxBirthYear: 2003 },
    },
    taxonomy: {},
    schedule: {
      type: 'single',
      slots: [{ date: '2099-10-02', startTime: '19:00', endTime: '23:00' }],
    },
  };
  const errors = R.validateRegistration(R.normalizeInput(input), {
    now: new Date('2026-01-01T00:00:00Z'),
  });
  assert.ok(!errors.some((e) => e.field === 'age'), JSON.stringify(errors));
});

// ═══════════════════════════════════════════════════════════════════════════
// ⑥ 등록 → 저장 → 수정 → 복원
// ═══════════════════════════════════════════════════════════════════════════

test('저장한 문서를 다시 읽으면 성별별 값이 그대로 돌아온다', () => {
  const saved = A.ageFields({ enabled: true, male: MALE, female: FEMALE }, 'all');
  const back = A.parseAgeRestriction(saved);
  assert.strictEqual(back.perGender, true);
  assert.deepStrictEqual(back.male, MALE);
  assert.deepStrictEqual(back.female, FEMALE);
  // 그대로 다시 저장해도 같은 문서다(수정 후 저장이 값을 바꾸지 않는다).
  assert.deepStrictEqual(A.ageFields(back, 'all'), saved);
});

test('한쪽만 제한한 문서도 왕복에서 모양이 유지된다', () => {
  const saved = A.ageFields({ enabled: true, male: MALE, female: OFF }, 'all');
  const back = A.parseAgeRestriction(saved);
  assert.strictEqual(back.male.enabled, true);
  assert.strictEqual(back.female.enabled, false);
  assert.deepStrictEqual(A.ageFields(back, 'all'), saved);
});

test('기존 파티를 수정하면 성별별 정본으로 승격된다(값은 그대로)', () => {
  const legacyDoc = { ageRestrictionEnabled: true, minBirthYear: 1990, maxBirthYear: 2000 };
  const back = A.parseAgeRestriction(legacyDoc);
  const resaved = A.ageFields(back, 'all');
  assert.strictEqual(resaved.maleMinBirthYear, 1990);
  assert.strictEqual(resaved.femaleMaxBirthYear, 2000);
  // 옛 공통 필드도 같은 값으로 남는다 — 구버전 앱이 읽어도 어긋나지 않는다.
  assert.strictEqual(resaved.minBirthYear, 1990);
  assert.strictEqual(resaved.maxBirthYear, 2000);
});

// ═══════════════════════════════════════════════════════════════════════════
// ⑦ 연령대 필터(목록·지도)와 같은 판정
// ═══════════════════════════════════════════════════════════════════════════

test('연령대 겹침 — 모집하는 성별 중 하나라도 겹치면 열려 있다', () => {
  const age = A.parseAgeRestriction(
    A.ageFields({ enabled: true, male: MALE, female: FEMALE }, 'all')
  );
  const overlaps = (lo, hi, genderLimit = 'all') => {
    const eff = A.normalizedFor(age, genderLimit);
    if (!A.hasAnyLimit(eff)) return true;
    return A.applicableGenders(genderLimit).some((g) => {
      const l = A.limitFor(eff, g);
      if (!l.enabled) return true;
      return (l.minBirthYear ?? -1e8) <= hi && (l.maxBirthYear ?? 1e8) >= lo;
    });
  };
  // 20대(2026 기준 1997~2006년생)는 남녀 어느 쪽과도 겹친다.
  assert.strictEqual(overlaps(1997, 2006), true);
  // 1970년대생과는 어느 쪽도 겹치지 않는다.
  assert.strictEqual(overlaps(1970, 1979), false);
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

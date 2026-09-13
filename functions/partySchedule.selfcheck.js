// partySchedule.js 자체 검증 — 배포 전에 `npm run check:schedule`로 돌린다.
// functions에는 테스트 러너가 없으므로 node 기본 assert만 쓴다(의존성 0).
//
// 여기서 확인하는 규칙은 클라이언트(lib/models/party_schedule.dart,
// test/party_schedule_test.dart)와 반드시 같은 결과를 내야 한다.

const assert = require('assert');
const {
  parseRecurringSchedule,
  nextOccurrence,
  isRecurringParty,
  effectivePartyStartAt,
  checkRecurringRecruitOpen,
  finalPartyEndAt,
} = require('./partySchedule');

// KST 벽시계 → 절대 시각(UTC-9h). 기대값을 사람이 읽는 그대로 쓰기 위한 헬퍼.
function kst(y, m, d, hh = 0, mm = 0) {
  return new Date(Date.UTC(y, m - 1, d, hh, mm) - 9 * 60 * 60 * 1000);
}

// Firestore Timestamp 흉내(서버 SDK는 toDate()를 제공한다).
function ts(date) {
  return { toDate: () => date };
}

function weeklyOf(days, startTime, endTime) {
  const weekly = {};
  for (const d of days) weekly[d] = { enabled: true, startTime, endTime };
  return weekly;
}

function recurringDoc({
  days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday'],
  startTime = '19:00',
  endTime = '22:00',
  startDate = kst(2026, 7, 1),
  endDate = null,
  deadline = { mode: 'hoursBefore', hours: 1 },
  open = null,
} = {}) {
  return {
    scheduleType: 'recurring',
    // 등록 시점의 첫 회차 캐시 — 계산이 이 값에 끌려가면 안 된다.
    partyDateTime: ts(kst(2026, 7, 1, 19, 0)),
    recurringSchedule: {
      startDate: ts(startDate),
      endDate: endDate ? ts(endDate) : null,
      weeklySchedule: weeklyOf(days, startTime, endTime),
      registrationDeadline: deadline,
      registrationOpen: open,
    },
  };
}

const cases = [];
function test(name, fn) {
  cases.push([name, fn]);
}

// ── 자정 넘김 ──────────────────────────────────────────────────────────
test('19:00~03:00은 다음 날 오전 3시 종료(KST)', () => {
  const s = parseRecurringSchedule(
    recurringDoc({ days: ['saturday'], startTime: '19:00', endTime: '03:00' })
      .recurringSchedule,
  );
  // 2026-08-01은 토요일.
  const occ = nextOccurrence(s, kst(2026, 8, 1, 12, 0));
  assert.deepStrictEqual(occ.start, kst(2026, 8, 1, 19, 0));
  assert.deepStrictEqual(occ.end, kst(2026, 8, 2, 3, 0));
});

test('자정을 넘겨 진행 중인 회차도 "다음 회차"로 잡힌다', () => {
  const s = parseRecurringSchedule(
    recurringDoc({ days: ['saturday'], startTime: '19:00', endTime: '03:00' })
      .recurringSchedule,
  );
  const occ = nextOccurrence(s, kst(2026, 8, 2, 1, 0)); // 일요일 새벽 1시
  assert.deepStrictEqual(occ.start, kst(2026, 8, 1, 19, 0));
});

// ── 다음 회차 ──────────────────────────────────────────────────────────
test('평일 파티: 회차가 끝나면 다음 날로 넘어간다', () => {
  const s = parseRecurringSchedule(recurringDoc().recurringSchedule);
  assert.deepStrictEqual(
    nextOccurrence(s, kst(2026, 8, 3, 23, 0)).start,
    kst(2026, 8, 4, 19, 0),
  );
});

test('평일 파티: 금요일 밤이면 다음 회차는 월요일', () => {
  const s = parseRecurringSchedule(recurringDoc().recurringSchedule);
  assert.deepStrictEqual(
    nextOccurrence(s, kst(2026, 8, 7, 23, 30)).start,
    kst(2026, 8, 10, 19, 0),
  );
});

test('KST 기준으로 요일을 판정한다(UTC로 계산하면 하루가 밀린다)', () => {
  // 토요일만 여는 파티. 2026-08-01 KST 23:00 = 2026-08-01T14:00Z.
  // UTC 기준으로 요일을 읽어도 토요일이라 구분이 안 되므로, KST로 자정을
  // 갓 넘긴 시각(= UTC로는 아직 전날)을 쓴다.
  const s = parseRecurringSchedule(
    recurringDoc({ days: ['sunday'], startTime: '01:00', endTime: '05:00' })
      .recurringSchedule,
  );
  // KST 2026-08-02(일) 00:30 → UTC로는 2026-08-01(토) 15:30.
  const occ = nextOccurrence(s, kst(2026, 8, 2, 0, 30));
  assert.deepStrictEqual(occ.start, kst(2026, 8, 2, 1, 0));
});

test('시작일 전에는 시작일 이후 첫 회차', () => {
  const s = parseRecurringSchedule(
    recurringDoc({ days: ['monday'], startDate: kst(2026, 8, 10) })
      .recurringSchedule,
  );
  assert.deepStrictEqual(
    nextOccurrence(s, kst(2026, 8, 3, 12, 0)).start,
    kst(2026, 8, 10, 19, 0),
  );
});

test('시작일이 한 달 뒤여도 첫 회차를 찾는다', () => {
  // 지금 기준 9일만 훑던 시절엔 null이 나와 신청이 영구 차단됐다.
  const s = parseRecurringSchedule(
    recurringDoc({ days: ['monday'], startDate: kst(2026, 10, 5) })
      .recurringSchedule,
  );
  assert.deepStrictEqual(
    nextOccurrence(s, kst(2026, 8, 3, 12, 0)).start,
    kst(2026, 10, 5, 19, 0),
  );
});

test('종료일이 지나면 회차가 없다', () => {
  const s = parseRecurringSchedule(
    recurringDoc({ days: ['monday'], endDate: kst(2026, 8, 3) }).recurringSchedule,
  );
  assert.ok(nextOccurrence(s, kst(2026, 8, 3, 12, 0)));
  assert.strictEqual(nextOccurrence(s, kst(2026, 8, 5, 12, 0)), null);
});

// ── 모집 마감 규칙 ─────────────────────────────────────────────────────
test('마감: 각 회차 시작 1시간 전', () => {
  const s = parseRecurringSchedule(recurringDoc().recurringSchedule);
  assert.deepStrictEqual(
    nextOccurrence(s, kst(2026, 8, 3, 12, 0)).deadline,
    kst(2026, 8, 3, 18, 0),
  );
});

test('마감: 당일 18시', () => {
  const s = parseRecurringSchedule(
    recurringDoc({ deadline: { mode: 'sameDayTime', time: '18:00' } })
      .recurringSchedule,
  );
  assert.deepStrictEqual(
    nextOccurrence(s, kst(2026, 8, 3, 12, 0)).deadline,
    kst(2026, 8, 3, 18, 0),
  );
});

test('마감: 당일 시각이 시작보다 늦으면 시작 시각으로 당긴다', () => {
  const s = parseRecurringSchedule(
    recurringDoc({ deadline: { mode: 'sameDayTime', time: '22:00' } })
      .recurringSchedule,
  );
  assert.deepStrictEqual(
    nextOccurrence(s, kst(2026, 8, 3, 12, 0)).deadline,
    kst(2026, 8, 3, 19, 0),
  );
});

test('마감: 시작 90분 전(분 단위)', () => {
  const s = parseRecurringSchedule(
    recurringDoc({ deadline: { mode: 'beforeStart', minutes: 90 } })
      .recurringSchedule,
  );
  assert.deepStrictEqual(
    nextOccurrence(s, kst(2026, 8, 3, 12, 0)).deadline,
    kst(2026, 8, 3, 17, 30),
  );
});

test('마감: 시작 59분 전', () => {
  const s = parseRecurringSchedule(
    recurringDoc({ deadline: { mode: 'beforeStart', minutes: 59 } })
      .recurringSchedule,
  );
  assert.deepStrictEqual(
    nextOccurrence(s, kst(2026, 8, 3, 12, 0)).deadline,
    kst(2026, 8, 3, 18, 1),
  );
});

test('마감: 예전 hoursBefore 문서(minutes 없음)도 그대로 읽힌다', () => {
  const s = parseRecurringSchedule(
    recurringDoc({ deadline: { mode: 'hoursBefore', hours: 3 } })
      .recurringSchedule,
  );
  assert.deepStrictEqual(
    nextOccurrence(s, kst(2026, 8, 3, 12, 0)).deadline,
    kst(2026, 8, 3, 16, 0),
  );
});

test('마감: 시작 날짜 지정 시각(startDayTime)', () => {
  const s = parseRecurringSchedule(
    recurringDoc({ deadline: { mode: 'startDayTime', time: '18:00' } })
      .recurringSchedule,
  );
  assert.deepStrictEqual(
    nextOccurrence(s, kst(2026, 8, 3, 12, 0)).deadline,
    kst(2026, 8, 3, 18, 0),
  );
});

test('마감: 시작 전날 지정 시각(prevDayTime)', () => {
  const s = parseRecurringSchedule(
    recurringDoc({ deadline: { mode: 'prevDayTime', time: '20:00' } })
      .recurringSchedule,
  );
  assert.deepStrictEqual(
    nextOccurrence(s, kst(2026, 8, 3, 12, 0)).deadline,
    kst(2026, 8, 2, 20, 0),
  );
});

test('마감: 자정을 넘겨 끝나도 기준은 시작 날짜다', () => {
  // 8/3 19:00 시작 → 8/4 03:00 종료. '시작 전날'은 종료 날짜(8/4)의 전날이
  // 아니라 시작 날짜(8/3)의 전날인 8/2다.
  const s = parseRecurringSchedule(
    recurringDoc({
      endTime: '03:00',
      deadline: { mode: 'prevDayTime', time: '20:00' },
    }).recurringSchedule,
  );
  assert.deepStrictEqual(
    nextOccurrence(s, kst(2026, 8, 3, 12, 0)).deadline,
    kst(2026, 8, 2, 20, 0),
  );
});

test('마감: 마감 없음', () => {
  const s = parseRecurringSchedule(
    recurringDoc({ deadline: { mode: 'none' } }).recurringSchedule,
  );
  assert.strictEqual(nextOccurrence(s, kst(2026, 8, 3, 12, 0)).deadline, null);
});

// ── 모집 시작 규칙 ─────────────────────────────────────────────────────
test('모집 시작: 규칙이 없으면 제한 없음(null)', () => {
  const s = parseRecurringSchedule(recurringDoc().recurringSchedule);
  assert.strictEqual(
    nextOccurrence(s, kst(2026, 8, 3, 12, 0)).recruitOpenAt,
    null,
  );
});

test('모집 시작: 시작 3일 전(4320분)부터', () => {
  const s = parseRecurringSchedule(
    recurringDoc({ open: { mode: 'beforeStart', minutes: 3 * 24 * 60 } })
      .recurringSchedule,
  );
  assert.deepStrictEqual(
    nextOccurrence(s, kst(2026, 8, 3, 12, 0)).recruitOpenAt,
    kst(2026, 7, 31, 19, 0),
  );
});

test('모집 시작 전에는 신청이 막힌다', () => {
  const doc = recurringDoc({
    open: { mode: 'prevDayTime', time: '20:00' },
  });
  // 8/3 회차의 모집은 8/2 20:00부터 — 8/2 19:00에는 아직 닫혀 있다.
  const before = checkRecurringRecruitOpen(doc, kst(2026, 8, 2, 19, 0));
  assert.strictEqual(before.open, false);
  assert.strictEqual(before.reason, 'notYet');

  const after = checkRecurringRecruitOpen(doc, kst(2026, 8, 2, 20, 1));
  assert.strictEqual(after.open, true);
});

// ── 신청 차단 판정(서버가 실제로 쓰는 함수) ────────────────────────────
test('마감 전에는 신청이 열려 있다', () => {
  const r = checkRecurringRecruitOpen(recurringDoc(), kst(2026, 8, 3, 17, 59));
  assert.strictEqual(r.open, true);
});

test('마감 시각을 지나면 그 회차 신청이 막힌다', () => {
  const r = checkRecurringRecruitOpen(recurringDoc(), kst(2026, 8, 3, 18, 1));
  assert.strictEqual(r.open, false);
  assert.strictEqual(r.reason, 'deadline');
});

test('회차가 끝나면 다음 회차 모집이 다시 열린다', () => {
  // 월요일 회차가 끝난 직후(23:00) → 화요일 회차 기준으로 다시 열린다.
  const r = checkRecurringRecruitOpen(recurringDoc(), kst(2026, 8, 3, 23, 0));
  assert.strictEqual(r.open, true);
  assert.deepStrictEqual(r.occurrence.start, kst(2026, 8, 4, 19, 0));
});

test('운영 종료일이 지나면 영구 마감', () => {
  const r = checkRecurringRecruitOpen(
    recurringDoc({ days: ['monday'], endDate: kst(2026, 8, 3) }),
    kst(2026, 8, 5, 12, 0),
  );
  assert.strictEqual(r.open, false);
  assert.strictEqual(r.reason, 'ended');
});

test('recurringSchedule이 깨졌으면 신청을 막는다', () => {
  assert.strictEqual(
    checkRecurringRecruitOpen({ scheduleType: 'recurring' }, new Date()).reason,
    'invalid',
  );
  assert.strictEqual(
    checkRecurringRecruitOpen(
      { scheduleType: 'recurring', recurringSchedule: { startDate: ts(kst(2026, 7, 1)) } },
      new Date(),
    ).open,
    false,
  );
});

test('요일이 하나도 켜져 있지 않으면 신청을 막는다', () => {
  const doc = recurringDoc();
  doc.recurringSchedule.weeklySchedule = {
    monday: { enabled: false, startTime: '19:00', endTime: '22:00' },
  };
  assert.strictEqual(checkRecurringRecruitOpen(doc, kst(2026, 8, 3, 12, 0)).open, false);
});

// ── 일회성 파티 회귀 방지 ──────────────────────────────────────────────
test('일회성 파티는 저장된 partyDateTime을 그대로 쓴다', () => {
  const at = kst(2026, 8, 15, 20, 0);
  const doc = { scheduleType: 'single', partyDateTime: ts(at) };
  assert.strictEqual(isRecurringParty(doc), false);
  assert.deepStrictEqual(effectivePartyStartAt(doc, kst(2026, 8, 1)), at);
  // scheduleType 필드가 아예 없는 옛 문서도 동일하다.
  assert.deepStrictEqual(
    effectivePartyStartAt({ partyDateTime: ts(at) }, kst(2026, 8, 1)),
    at,
  );
});

test('날짜 정보가 없는 문서도 죽지 않는다', () => {
  assert.strictEqual(effectivePartyStartAt({}, new Date()), null);
  assert.strictEqual(effectivePartyStartAt(null, new Date()), null);
});

test('정기 파티는 오래된 partyDateTime 대신 다음 회차를 쓴다', () => {
  assert.deepStrictEqual(
    effectivePartyStartAt(recurringDoc(), kst(2026, 8, 3, 12, 0)),
    kst(2026, 8, 3, 19, 0),
  );
});

// ── 최종 종료 시각(보관기간 기준점) ────────────────────────────────────
//
// 만료 자동 삭제(index.js deleteExpiredParties)가 여기서부터 14일을 센다.
// 클라이언트 PartySchedule.finalEndAt과 같은 값을 내야 한다.
test('정기 파티는 마지막 회차가 끝난 시각이 최종 종료다', () => {
  // 2026-08-31은 월요일 — 종료일(9/2 수)까지 중 마지막 평일 회차는 9/2.
  const doc = recurringDoc({
    days: ['monday', 'wednesday'],
    startTime: '19:00',
    endTime: '22:00',
    startDate: kst(2026, 8, 3),
    endDate: kst(2026, 9, 2),
  });
  assert.deepStrictEqual(finalPartyEndAt(doc), kst(2026, 9, 2, 22, 0));
});

test('종료일이 켜지지 않은 요일이면 그 앞의 마지막 회차를 찾는다', () => {
  // 종료일 9/5(토)에는 회차가 없다 — 직전 회차는 9/2(수).
  const doc = recurringDoc({
    days: ['wednesday'],
    startDate: kst(2026, 8, 3),
    endDate: kst(2026, 9, 5),
  });
  assert.deepStrictEqual(finalPartyEndAt(doc), kst(2026, 9, 2, 22, 0));
});

test('자정을 넘기는 마지막 회차는 다음 날 새벽이 최종 종료다', () => {
  const doc = recurringDoc({
    days: ['saturday'],
    startTime: '19:00',
    endTime: '03:00',
    startDate: kst(2026, 8, 1),
    endDate: kst(2026, 8, 29),
  });
  assert.deepStrictEqual(finalPartyEndAt(doc), kst(2026, 8, 30, 3, 0));
});

test('종료일 없는 무기한 정기 파티는 최종 종료가 없다(삭제 대상이 아니다)', () => {
  assert.strictEqual(finalPartyEndAt(recurringDoc({ endDate: null })), null);
});

test('일회성 파티는 singleSchedule의 종료 시각이 기준이다', () => {
  const doc = {
    scheduleType: 'single',
    partyDateTime: ts(kst(2026, 8, 15, 20, 0)),
    singleSchedule: {
      date: ts(kst(2026, 8, 15)),
      startTime: '20:00',
      endTime: '23:30',
    },
  };
  assert.deepStrictEqual(finalPartyEndAt(doc), kst(2026, 8, 15, 23, 30));
});

test('종료 시각을 안 적은 일회성 파티는 시작 시각이 기준이다', () => {
  const doc = {
    scheduleType: 'single',
    partyDateTime: ts(kst(2026, 8, 15, 20, 0)),
    singleSchedule: {
      date: ts(kst(2026, 8, 15)),
      startTime: '20:00',
      endTime: null,
    },
  };
  assert.deepStrictEqual(finalPartyEndAt(doc), kst(2026, 8, 15, 20, 0));
});

test('자정을 넘기는 일회성 파티도 다음 날 종료로 읽는다', () => {
  const doc = {
    scheduleType: 'single',
    singleSchedule: {
      date: ts(kst(2026, 8, 15)),
      startTime: '21:00',
      endTime: '02:00',
    },
  };
  assert.deepStrictEqual(finalPartyEndAt(doc), kst(2026, 8, 16, 2, 0));
});

test('singleSchedule이 없는 옛 문서는 partyDateTime을 그대로 쓴다', () => {
  const at = kst(2026, 8, 15, 20, 0);
  assert.deepStrictEqual(finalPartyEndAt({ partyDateTime: ts(at) }), at);
  assert.strictEqual(finalPartyEndAt({}), null);
  assert.strictEqual(finalPartyEndAt(null), null);
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

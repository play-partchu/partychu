// roomAvailability.js 자체 검증 — 배포 전에 `npm run check:rooms`로 돌린다.
// functions에는 테스트 러너가 없으므로 node 기본 assert만 쓴다(의존성 0).
//
// 여기서 확인하는 규칙은 클라이언트(lib/models/reservation_modes.dart,
// test/reservation_modes_test.dart)와 반드시 같은 결과를 내야 한다 — 특히
// 예약 방식 해석(하위호환)과 숙박 구간 계산이 어긋나면, 앱에서는 예약
// 가능해 보이는데 서버가 거절하는 상태가 된다.

const assert = require('assert');
const {
  normalizeReservationModes,
  computeWindows,
  windowsOverlap,
} = require('./roomAvailability');

function cfgOf(overrides = {}) {
  return {
    reservationModes: ['stay', 'hourly', 'package'],
    packages: [],
    stayPricePerNight: 120000,
    stayCheckInMinutes: 16 * 60,
    stayCheckOutMinutes: 11 * 60,
    stayMinNights: 1,
    stayMaxNights: 7,
    unitMinutes: 60,
    openMinutes: 9 * 60,
    closeMinutes: 23 * 60,
    minBookingMinutes: 60,
    maxBookingMinutes: null,
    pricePerHour: 30000,
    capacity: 4,
    ...overrides,
  };
}

const cases = [];
function test(name, fn) {
  cases.push([name, fn]);
}

function throwsWith(fn, fragment) {
  assert.throws(fn, (e) => String(e.message).includes(fragment),
    `"${fragment}"을(를) 포함한 오류를 기대했습니다.`);
}

// ── 예약 방식 해석(하위호환) ────────────────────────────────────────────
test('reservationModes 배열이 정본이다', () => {
  assert.deepStrictEqual(
    normalizeReservationModes({ reservationModes: ['stay', 'hourly'] }, []),
    ['stay', 'hourly'],
  );
});

test('알 수 없는 값은 걸러지고, 전부 무효면 구 필드로 넘어간다', () => {
  assert.deepStrictEqual(
    normalizeReservationModes({ reservationModes: ['stay', 'weekly'] }, []),
    ['stay'],
  );
  assert.deepStrictEqual(
    normalizeReservationModes(
      { reservationModes: ['weekly'], reservationMode: 'package' }, []),
    ['package'],
  );
});

test('구 스키마 reservationMode 문자열을 해석한다', () => {
  assert.deepStrictEqual(
    normalizeReservationModes({ reservationMode: 'both' }, []),
    ['hourly', 'package'],
  );
  assert.deepStrictEqual(
    normalizeReservationModes({ reservationMode: 'daily' }, []),
    ['stay'],
  );
});

test('아무 값도 없으면 패키지 유무로 추론한다', () => {
  assert.deepStrictEqual(normalizeReservationModes({}, []), ['hourly']);
  assert.deepStrictEqual(
    normalizeReservationModes({}, [{ id: 'p1' }]),
    ['package'],
  );
});

// ── 숙박 구간 계산 ──────────────────────────────────────────────────────
test('2박은 자정 기준 960분 ~ 3540분을 점유한다', () => {
  const r = computeWindows(cfgOf(), 'stay', { nights: 2 });
  assert.deepStrictEqual(r.windows, [
    { start: 960, end: 3540, price: 240000 },
  ]);
  assert.strictEqual(r.totalMinutes, 2580);
});

test('숙박 요금은 1박 요금 × 박수', () => {
  const r = computeWindows(cfgOf({ stayPricePerNight: 95000 }), 'stay', {
    nights: 3,
  });
  assert.strictEqual(r.windows[0].price, 285000);
});

test('숙박을 받지 않는 룸은 숙박 예약을 거절한다', () => {
  throwsWith(
    () => computeWindows(cfgOf({ reservationModes: ['hourly'] }), 'stay', { nights: 1 }),
    '숙박 예약을 지원하지 않아요',
  );
});

test('최소/최대 숙박일을 벗어나면 거절한다', () => {
  const cfg = cfgOf({ stayMinNights: 2, stayMaxNights: 5 });
  throwsWith(() => computeWindows(cfg, 'stay', { nights: 1 }), '최소 2박부터');
  throwsWith(() => computeWindows(cfg, 'stay', { nights: 6 }), '최대 5박까지');
  assert.strictEqual(computeWindows(cfg, 'stay', { nights: 5 }).windows.length, 1);
});

test('박수가 정수가 아니거나 0 이하면 거절한다', () => {
  throwsWith(() => computeWindows(cfgOf(), 'stay', { nights: 0 }), '숙박일 수가 올바르지');
  throwsWith(() => computeWindows(cfgOf(), 'stay', { nights: 1.5 }), '숙박일 수가 올바르지');
  throwsWith(() => computeWindows(cfgOf(), 'stay', {}), '숙박일 수가 올바르지');
});

// ── 숙박 ↔ 시간제/패키지 겹침 ───────────────────────────────────────────
test('2박 숙박은 그 사이 날짜의 시간제 예약과 겹친다', () => {
  const stay = computeWindows(cfgOf(), 'stay', { nights: 2 }).windows[0];
  // 다음 날(1440~) 오후 2시~4시 시간제 — 숙박 한가운데다.
  assert.strictEqual(windowsOverlap(stay, { start: 1440 + 840, end: 1440 + 960 }), true);
});

test('체크아웃 이후 시간제 예약은 겹치지 않는다', () => {
  const stay = computeWindows(cfgOf(), 'stay', { nights: 1 }).windows[0];
  // 다음 날 체크아웃(11:00 = 2100분) 뒤인 12시~13시.
  assert.strictEqual(windowsOverlap(stay, { start: 1440 + 720, end: 1440 + 780 }), false);
});

test('체크인 전 같은 날 오전 시간제 예약은 겹치지 않는다', () => {
  const stay = computeWindows(cfgOf(), 'stay', { nights: 1 }).windows[0];
  assert.strictEqual(windowsOverlap(stay, { start: 600, end: 720 }), false);
});

// ── 복수 선택이 다른 방식 검증에 미치는 영향 ─────────────────────────────
test('숙박+시간제 룸은 시간제 예약을 받고 패키지 예약은 거절한다', () => {
  const cfg = cfgOf({ reservationModes: ['stay', 'hourly'] });
  const r = computeWindows(cfg, 'hourly', { ranges: [{ start: 600, end: 720 }] });
  assert.strictEqual(r.windows[0].price, 60000);
  throwsWith(
    () => computeWindows(cfg, 'package', { packageId: 'p1' }),
    '패키지 예약을 지원하지 않아요',
  );
});

test('숙박 전용 룸은 시간제 예약을 거절한다', () => {
  throwsWith(
    () => computeWindows(cfgOf({ reservationModes: ['stay'] }), 'hourly', {
      ranges: [{ start: 600, end: 720 }],
    }),
    '시간제 예약을 지원하지 않아요',
  );
});

test('구 스키마(both) 룸은 시간제·패키지 모두 그대로 받는다', () => {
  const pkg = {
    id: 'p1', name: '올나잇', startTime: '22:00', endTime: '08:00', price: 200000, days: [],
  };
  const cfg = cfgOf({
    reservationModes: normalizeReservationModes({ reservationMode: 'both' }, [pkg]),
    packages: [pkg],
  });
  assert.strictEqual(
    computeWindows(cfg, 'hourly', { ranges: [{ start: 600, end: 720 }] }).totalMinutes,
    120,
  );
  const r = computeWindows(cfg, 'package', { packageId: 'p1', peopleCount: 2 });
  assert.deepStrictEqual(r.windows, [{ start: 1320, end: 1920, price: 200000 }]);
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

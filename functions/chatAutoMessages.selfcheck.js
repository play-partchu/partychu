// 채팅 자동 안내의 **발송 시각·문구 선택** 규칙 자체 검증 — `npm run check:chat`.
//
// 이 로직은 원래 앱(기기 로컬시각 = 한국)에 있었고 서버(UTC)로 옮겼다. 옮기면서
// 값이 9시간 어긋나면 "이용 2시간 전 안내"가 전날 밤이나 당일 저녁에 도착한다.
// 그래서 여기서 못 박는 것은 세 가지다.
//
//   1. 예약일이 있으면 발송은 **그날 KST 08:00**이다(10:00의 2시간 전).
//   2. 날짜 경계(KST 자정 직후·직전)에서도 날이 밀리지 않는다.
//   3. 문구는 호스트 문서에서만 오고, 파티샵은 수령 방법이 맞을 때만 나온다.

const assert = require('assert');
const { computeSendAtMs, resolveAutoText, kstDayStartMs, normalizeAppointmentMs } =
  require('./chatAutoMessages').__test;

const cases = [];
function test(name, fn) {
  cases.push([name, fn]);
}

const HOUR = 3600000;
const KST = 9 * HOUR;

/** KST 벽시계 → UTC ms. 테스트를 한국 시각으로 읽기 위한 헬퍼. */
function kst(y, m, d, hh = 0, mm = 0) {
  return Date.UTC(y, m - 1, d, hh, mm) - KST;
}

const NOW = kst(2026, 8, 15, 13, 30); // 2026-08-15 13:30 KST

test('파티크루 문의 — 지금 바로 발송', () => {
  assert.strictEqual(
    computeSendAtMs({ relatedType: 'crew', appointmentAtMs: null, nowMs: NOW }),
    NOW,
  );
});

test('장소 예약 — 이용일 KST 08:00에 발송', () => {
  const appt = kst(2026, 9, 3, 19, 0); // 9/3 저녁 이용
  assert.strictEqual(
    computeSendAtMs({ relatedType: 'place', appointmentAtMs: appt, nowMs: NOW }),
    kst(2026, 9, 3, 8, 0),
  );
});

test('장소 예약 — 이용일이 없으면 예약하지 않는다', () => {
  assert.strictEqual(
    computeSendAtMs({ relatedType: 'place', appointmentAtMs: null, nowMs: NOW }),
    null,
  );
});

test('파티샵 — 수령일이 있으면 그날 KST 08:00', () => {
  const appt = kst(2026, 9, 3, 15, 0);
  assert.strictEqual(
    computeSendAtMs({ relatedType: 'shop', appointmentAtMs: appt, nowMs: NOW }),
    kst(2026, 9, 3, 8, 0),
  );
});

test('파티샵 — 수령일이 없으면 지금 발송(옮기기 전 now+2h-2h와 같은 값)', () => {
  assert.strictEqual(
    computeSendAtMs({ relatedType: 'shop', appointmentAtMs: null, nowMs: NOW }),
    NOW,
  );
});

test('날짜 경계 — KST 자정 직후 예약도 그날 08:00이다(전날로 밀리지 않는다)', () => {
  const appt = kst(2026, 9, 3, 0, 1);
  assert.strictEqual(
    computeSendAtMs({ relatedType: 'place', appointmentAtMs: appt, nowMs: NOW }),
    kst(2026, 9, 3, 8, 0),
  );
});

test('날짜 경계 — KST 23:59 예약도 같은 날 08:00이다(다음날로 넘어가지 않는다)', () => {
  const appt = kst(2026, 9, 3, 23, 59);
  assert.strictEqual(
    computeSendAtMs({ relatedType: 'place', appointmentAtMs: appt, nowMs: NOW }),
    kst(2026, 9, 3, 8, 0),
  );
});

test('날짜 경계 — UTC 기준으로 계산하면 날이 밀리는 시각(KST 08:30)에서도 옳다', () => {
  // KST 08:30 = UTC 전날 23:30. UTC 날짜로 자르면 하루 전으로 밀린다.
  const appt = kst(2026, 9, 3, 8, 30);
  assert.strictEqual(kstDayStartMs(appt), kst(2026, 9, 3, 0, 0));
});

// ── 약속일 정규화 — 실제로 났던 결함(1969년 sendAt)을 못 박는다 ─────────────
// `Number(null)`은 0이라, 예전 호출부는 "수령일 없음"을 epoch로 착각해
// sendAt을 1969-12-31로 만들었다. 아래 세 케이스가 그 재발을 막는다.

test('약속일 정규화 — null이면 null (0으로 떨어지지 않는다)', () => {
  assert.strictEqual(normalizeAppointmentMs(null), null);
});

test('약속일 정규화 — 누락(undefined)이면 null', () => {
  assert.strictEqual(normalizeAppointmentMs(undefined), null);
});

test('약속일 정규화 — 정상 timestamp는 그대로 통과', () => {
  const appt = kst(2026, 9, 3, 19, 0);
  assert.strictEqual(normalizeAppointmentMs(appt), appt);
});

test('약속일 정규화 — 숫자가 아니면 null', () => {
  assert.strictEqual(normalizeAppointmentMs('내일'), null);
  assert.strictEqual(normalizeAppointmentMs(NaN), null);
});

test('파티샵 수령일 없음(null) — 1970 epoch가 아니라 "지금"으로 발송', () => {
  const sendAt = computeSendAtMs({
    relatedType: 'shop',
    appointmentAtMs: normalizeAppointmentMs(null),
    nowMs: NOW,
  });
  assert.strictEqual(sendAt, NOW);
  // 결함이 있으면 1969-12-31이 나왔다. 1970 근처 값이면 무조건 실패다.
  assert.ok(sendAt > kst(2000, 1, 1), `sendAt이 과거 epoch로 떨어졌다: ${new Date(sendAt).toISOString()}`);
});

test('파티샵 수령일 누락(undefined) — 마찬가지로 "지금"', () => {
  const sendAt = computeSendAtMs({
    relatedType: 'shop',
    appointmentAtMs: normalizeAppointmentMs(undefined),
    nowMs: NOW,
  });
  assert.strictEqual(sendAt, NOW);
  assert.ok(sendAt > kst(2000, 1, 1));
});

test('장소 이용일 없음(null) — 예약 자체를 하지 않는다(즉시 발송되면 안 된다)', () => {
  assert.strictEqual(
    computeSendAtMs({
      relatedType: 'place',
      appointmentAtMs: normalizeAppointmentMs(null),
      nowMs: NOW,
    }),
    null,
  );
});

test('정상 예약일이 있으면 정규화를 거쳐도 KST 08:00이 유지된다', () => {
  const appt = kst(2026, 9, 3, 19, 0);
  for (const type of ['shop', 'place']) {
    assert.strictEqual(
      computeSendAtMs({
        relatedType: type,
        appointmentAtMs: normalizeAppointmentMs(appt),
        nowMs: NOW,
      }),
      kst(2026, 9, 3, 8, 0),
      `${type} 경로에서 KST 08:00이 깨졌다`,
    );
  }
});

test('알 수 없는 글 종류는 예약하지 않는다', () => {
  assert.strictEqual(
    computeSendAtMs({ relatedType: 'party', appointmentAtMs: NOW, nowMs: NOW }),
    null,
  );
});

test('문구 — 크루/장소는 autoMessage를 쓰고 공백은 제거한다', () => {
  assert.strictEqual(resolveAutoText('crew', { autoMessage: '  안녕하세요  ' }), '안녕하세요');
  assert.strictEqual(resolveAutoText('place', { autoMessage: '' }), '');
  assert.strictEqual(resolveAutoText('place', {}), '');
  assert.strictEqual(resolveAutoText('place', null), '');
});

test('문구 — 파티샵은 수령 방법별로 갈린다', () => {
  const product = { autoMessages: { delivery: '택배로 보내드려요', pickup: '매장에서 받으세요' } };
  assert.strictEqual(resolveAutoText('shop', product, { deliveryMethod: 'pickup' }), '매장에서 받으세요');
  assert.strictEqual(resolveAutoText('shop', product, { deliveryMethod: 'delivery' }), '택배로 보내드려요');
});

test('문구 — 파티샵에서 수령 방법이 없거나 그 방법의 문구가 없으면 빈 값', () => {
  const product = { autoMessages: { pickup: '매장에서 받으세요' } };
  assert.strictEqual(resolveAutoText('shop', product, {}), '');
  assert.strictEqual(resolveAutoText('shop', product, { deliveryMethod: 'delivery' }), '');
  assert.strictEqual(resolveAutoText('shop', { autoMessage: '엉뚱한 필드' }, { deliveryMethod: 'pickup' }), '');
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
    ? `\n채팅 자동 안내 규칙 검증 통과 — ${cases.length}건`
    : `\n실패 ${failed}건 / 전체 ${cases.length}건`,
);
process.exit(failed === 0 ? 0 : 1);

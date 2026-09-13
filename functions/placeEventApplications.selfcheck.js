// 매장 이벤트 신청 **서버 판정** 검증 — `npm run check:placeeventapply`.
//
// ── 왜 이 판정이 서버에 있나 ──────────────────────────────────────────────
// 신청 문서는 firestore.rules가 클라이언트 쓰기를 전면 차단한다. 그래서
// "이 신청을 받아도 되는가"를 정하는 것은 **오직 여기**다. 앱의
// `showsApplyButtonAt`은 버튼을 그릴지 정하는 힌트일 뿐 막는 힘이 없다 —
// 변조된 클라이언트는 버튼을 거치지 않는다.
//
// 그중에서도 **종료 판정**이 이 파일의 핵심이다. 앱은 이렇게 본다
// (PlacePromotion.statusAt).
//
//     상시 진행(isAlways)이면 날짜로는 끝나지 않는다
//     endAt이 **속한 날의 23:59:59**를 지나야 종료 — 그 날 하루는 살아 있다
//
// 서버가 이 경계를 하루라도 당겨 잡으면 오늘 열리는 이벤트에 신청이 막히고,
// 늦춰 잡으면 끝난 이벤트에 신청이 들어온다. 그래서 경계를 **분 단위로**
// 확인한다. 서버는 KST로 고정해 접는다(UTC로 접으면 하루가 9시간 어긋난다).
//
// 실제 규칙 엔진(권한·조회 범위) 검증은 placeEventApplicationRules.selfcheck.js.

const assert = require('assert');

process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'selfcheck';

const {
  MESSAGES,
  docIdFor,
  kstDayStartMs,
  isEndedAt,
  acceptsApplications,
  evaluateApplyEligibility,
  buildApplicationSnapshot,
  toRow,
  byAppliedAt,
  countApplied,
} = require('./placeEventApplications');

const cases = [];
const test = (name, fn) => cases.push([name, fn]);

const KST = 9 * 3600000;
/** KST 벽시계로 읽은 시각을 UTC ms로 — 테스트를 사람이 읽을 수 있게. */
const kst = (y, mo, d, h = 0, mi = 0, s = 0) =>
  Date.UTC(y, mo - 1, d, h, mi, s) - KST;
/** Firestore Timestamp 흉내. */
const ts = (ms) => ({ toMillis: () => ms });

const GUEST = 'guest-1';
const HOST = 'host-1';

function event(extra = {}) {
  return {
    hostId: HOST,
    placeId: 'PL1',
    placeCollection: 'events',
    title: '생일 이벤트',
    isVisible: true,
    applyMode: 'apply',
    isAlways: true,
    ...extra,
  };
}

// ══════════════════════════════════════════════════════════════════════════
// ① 문서 id — 중복 방지 그 자체
// ══════════════════════════════════════════════════════════════════════════

test('같은 사람 · 같은 이벤트는 언제나 같은 문서다', () => {
  assert.strictEqual(docIdFor('EV1', GUEST), docIdFor('EV1', GUEST));
  assert.strictEqual(docIdFor('EV1', GUEST), 'EV1_guest-1');
});

test('사람이나 이벤트가 다르면 다른 문서다', () => {
  assert.notStrictEqual(docIdFor('EV1', GUEST), docIdFor('EV1', 'guest-2'));
  assert.notStrictEqual(docIdFor('EV1', GUEST), docIdFor('EV2', GUEST));
});

// ══════════════════════════════════════════════════════════════════════════
// ② 종료 판정 — 하루의 경계
// ══════════════════════════════════════════════════════════════════════════

test('KST 날짜 자정을 정확히 집는다', () => {
  // 2026-08-30 00:00 KST == 2026-08-29 15:00 UTC
  assert.strictEqual(kstDayStartMs(kst(2026, 8, 30, 12)), kst(2026, 8, 30));
  // UTC 자정 직후(= KST 09:00)도 같은 KST 날짜다 — UTC로 접으면 여기서 갈린다.
  assert.strictEqual(kstDayStartMs(Date.UTC(2026, 7, 30, 0, 30)), kst(2026, 8, 30));
  // KST 00:30은 그 날의 시작을 넘긴 직후다.
  assert.strictEqual(kstDayStartMs(kst(2026, 8, 30, 0, 30)), kst(2026, 8, 30));
});

test('상시 진행은 날짜로 끝나지 않는다', () => {
  const ev = event({ isAlways: true, endAt: ts(kst(2020, 1, 1)) });
  assert.strictEqual(isEndedAt(ev, kst(2026, 8, 30, 12)), false);
});

test('종료일이 없으면 끝나지 않는다', () => {
  const ev = event({ isAlways: false, endAt: null });
  assert.strictEqual(isEndedAt(ev, kst(2026, 8, 30, 12)), false);
});

test('종료일 **당일**은 하루 종일 살아 있다', () => {
  const ev = event({ isAlways: false, endAt: ts(kst(2026, 8, 30)) });
  for (const [h, mi, s] of [[0, 0, 0], [12, 0, 0], [23, 59, 58], [23, 59, 59]]) {
    assert.strictEqual(
      isEndedAt(ev, kst(2026, 8, 30, h, mi, s)),
      false,
      `${h}:${mi}:${s}`,
    );
  }
});

test('종료일 23:59:59를 지나는 순간 끝난다', () => {
  const ev = event({ isAlways: false, endAt: ts(kst(2026, 8, 30)) });
  // 23:59:59.000까지는 살아 있고, 그 뒤 1ms부터 종료 — Dart의
  // `now.isAfter(DateTime(y, m, d, 23, 59, 59))`와 같은 경계다.
  assert.strictEqual(isEndedAt(ev, kst(2026, 8, 30, 23, 59, 59)), false);
  assert.strictEqual(isEndedAt(ev, kst(2026, 8, 30, 23, 59, 59) + 1), true);
  assert.strictEqual(isEndedAt(ev, kst(2026, 8, 31, 0, 0, 0)), true);
});

test('종료일에 시각이 함께 저장돼 있어도 그 날 하루는 살아 있다', () => {
  // 호스트가 날짜만 고르지만, 옛 문서에는 시각이 붙어 있을 수 있다.
  const ev = event({ isAlways: false, endAt: ts(kst(2026, 8, 30, 9, 30)) });
  assert.strictEqual(isEndedAt(ev, kst(2026, 8, 30, 22, 0)), false);
  assert.strictEqual(isEndedAt(ev, kst(2026, 8, 31, 0, 1)), true);
});

test('UTC로 접지 않는다 — KST 밤 시간대가 하루 일찍 끝나지 않는다', () => {
  const ev = event({ isAlways: false, endAt: ts(kst(2026, 8, 30)) });
  // KST 8/30 22:00 == UTC 8/30 13:00. UTC 기준으로 접으면 여기서 이미
  // "다음 날"로 넘어가는 구현이 나올 수 있는데, 그러면 오늘 이벤트가 막힌다.
  assert.strictEqual(isEndedAt(ev, kst(2026, 8, 30, 22, 0)), false);
});

// ══════════════════════════════════════════════════════════════════════════
// ③ 신청 가능 판정
// ══════════════════════════════════════════════════════════════════════════

const NOW = kst(2026, 8, 30, 12);
const check = (ev, uid = GUEST) =>
  evaluateApplyEligibility({ eventData: ev, uid, nowMs: NOW });

test('신청 방식 — apply / inquiry_and_apply만 신청을 받는다', () => {
  assert.strictEqual(acceptsApplications({ applyMode: 'apply' }), true);
  assert.strictEqual(acceptsApplications({ applyMode: 'inquiry_and_apply' }), true);
  assert.strictEqual(acceptsApplications({ applyMode: 'none' }), false);
  // 필드가 없던 옛 이벤트는 신청을 받지 않는다(앱의 하위호환과 같은 값).
  assert.strictEqual(acceptsApplications({}), false);
  // 모르는 값도 열지 않는다(fail-closed).
  assert.strictEqual(acceptsApplications({ applyMode: 'someday' }), false);
});

test('정상 — 상시 진행 이벤트는 신청할 수 있다', () => {
  assert.strictEqual(check(event()).ok, true);
});

test('정상 — **시작 전** 이벤트도 신청할 수 있다', () => {
  // 오히려 그때가 사전 신청 기간이다. 시작일로 막지 않는다.
  const ev = event({
    isAlways: false,
    startAt: ts(kst(2026, 9, 20)),
    endAt: ts(kst(2026, 9, 30)),
  });
  assert.strictEqual(check(ev).ok, true);
});

test('종료된 이벤트는 거부한다', () => {
  const ev = event({
    isAlways: false,
    startAt: ts(kst(2026, 8, 1)),
    endAt: ts(kst(2026, 8, 10)),
  });
  const r = check(ev);
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.code, 'failed-precondition');
  assert.strictEqual(r.message, MESSAGES.ended);
});

test('숨긴 이벤트는 거부한다', () => {
  const r = check(event({ isVisible: false }));
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.message, MESSAGES.hidden);
});

test('isVisible이 없는 문서도 거부한다(fail-closed)', () => {
  const ev = event();
  delete ev.isVisible;
  assert.strictEqual(check(ev).ok, false);
});

test('신청을 안 받는 이벤트는 거부한다', () => {
  const r = check(event({ applyMode: 'none' }));
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.message, MESSAGES.notAccepting);
});

test('없는 이벤트는 거부한다', () => {
  const r = evaluateApplyEligibility({ eventData: null, uid: GUEST, nowMs: NOW });
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.code, 'not-found');
});

test('내 이벤트에는 신청할 수 없다', () => {
  const r = check(event(), HOST);
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.message, MESSAGES.ownEvent);
});

// 판정 순서가 바뀌면 사용자에게 엉뚱한 이유가 간다. 가장 앞에 오는 것부터.
test('내 이벤트 판정이 다른 이유보다 먼저다', () => {
  const ev = event({ isVisible: false, applyMode: 'none' });
  assert.strictEqual(check(ev, HOST).message, MESSAGES.ownEvent);
});

// ══════════════════════════════════════════════════════════════════════════
// ④ 스냅샷 — 클라이언트가 손댈 수 없는 값들
// ══════════════════════════════════════════════════════════════════════════

test('신청 문서의 파생 필드는 전부 원본에서 온다', () => {
  const snap = buildApplicationSnapshot({
    eventId: 'EV1',
    eventData: event({ title: '진짜 제목' }),
    placeData: { name: '혼술바' },
  });
  assert.strictEqual(snap.eventId, 'EV1');
  assert.strictEqual(snap.hostId, HOST);
  assert.strictEqual(snap.placeId, 'PL1');
  assert.strictEqual(snap.eventTitle, '진짜 제목');
  assert.strictEqual(snap.placeName, '혼술바');
  // guestId·status는 스냅샷이 아니라 호출부가 auth에서 넣는다.
  assert.strictEqual('guestId' in snap, false);
  assert.strictEqual('status' in snap, false);
});

test('부모 컬렉션은 화이트리스트 밖 값을 신뢰하지 않는다', () => {
  const snap = buildApplicationSnapshot({
    eventId: 'EV1',
    eventData: event({ placeCollection: 'placeRooms' }),
    placeData: null,
  });
  assert.strictEqual(snap.placeCollection, 'events');
  assert.strictEqual(
    buildApplicationSnapshot({
      eventId: 'EV1',
      eventData: event({ placeCollection: 'places' }),
      placeData: null,
    }).placeCollection,
    'places',
  );
});

test('장소를 못 읽어도 신청 자체는 막지 않는다', () => {
  const snap = buildApplicationSnapshot({
    eventId: 'EV1',
    eventData: event(),
    placeData: null,
  });
  assert.strictEqual(snap.placeName, '');
});

test('일정도 원본 그대로 베낀다', () => {
  const start = ts(kst(2026, 9, 20));
  const end = ts(kst(2026, 9, 30));
  const snap = buildApplicationSnapshot({
    eventId: 'EV1',
    eventData: event({ isAlways: false, startAt: start, endAt: end }),
    placeData: null,
  });
  assert.strictEqual(snap.eventIsAlways, false);
  assert.strictEqual(snap.eventStartAt, start);
  assert.strictEqual(snap.eventEndAt, end);
});

// ══════════════════════════════════════════════════════════════════════════
// ⑤ 호스트 목록 응답
// ══════════════════════════════════════════════════════════════════════════

const doc = (id, data) => ({ id, data: () => data });

test('응답에 uid를 담지 않는다', () => {
  const row = toRow(
    doc('EV1_guest-1', { guestId: GUEST, status: 'applied', createdAt: ts(1) }),
    { available: true, nickname: '냥냥이' },
  );
  assert.strictEqual(row.applicationId, 'EV1_guest-1');
  assert.strictEqual('guestId' in row, false);
  assert.strictEqual('uid' in row, false);
});

test('오래 신청한 사람이 위로, 시각을 모르는 건은 맨 뒤로', () => {
  const rows = [
    { applicationId: 'c', appliedAt: null },
    { applicationId: 'b', appliedAt: 200 },
    { applicationId: 'a', appliedAt: 100 },
  ].sort(byAppliedAt);
  assert.deepStrictEqual(rows.map((r) => r.applicationId), ['a', 'b', 'c']);
});

test('취소는 신청자 수에 들어가지 않는다', () => {
  assert.strictEqual(
    countApplied([
      { status: 'applied' },
      { status: 'applied' },
      { status: 'cancelled' },
    ]),
    2,
  );
});

// ══════════════════════════════════════════════════════════════════════════
(async () => {
  let failed = 0;
  for (const [name, fn] of cases) {
    try {
      await fn();
      console.log(`  ✓ ${name}`);
    } catch (e) {
      failed += 1;
      console.error(`  ✗ ${name}\n    ${e.message}`);
    }
  }
  console.log(
    failed === 0
      ? `\n매장 이벤트 신청 서버 판정 통과 — ${cases.length}건`
      : `\n실패 ${failed}건 / 전체 ${cases.length}건`,
  );
  process.exit(failed === 0 ? 0 : 1);
})();

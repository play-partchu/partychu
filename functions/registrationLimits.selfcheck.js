// 등록 개수 제한 규칙 자체 검증 — `npm run check:limits`.
//
// 여기서 못 박는 것.
//   1. **유형별 각각 10개다.** 합산이 아니다 — 파티가 꽉 차도 이벤트는 열려 있다.
//   2. **다중 날짜 파티는 하나다.** 날짜 문서 5개짜리 파티가 5개로 세지면
//      호스트는 파티 두 개만 만들고 한도에 걸린다.
//   3. **끝난 것은 자리를 차지하지 않는다.** 지난 파티·종료 이벤트·숨긴 장소는
//      14일 뒤 자동 삭제 대기열이지, 새 등록을 막는 이유가 아니다.
//   4. **수정은 개수를 늘리지 않는다.** 세는 것은 "지금 있는 것"이다.
//   5. 앱(registration_limits.dart)과 **같은 판정**이다 — 상한 숫자와 살아
//      있음의 정의가 갈리면 앱은 통과시키고 서버가 지운다.

process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'selfcheck';

const assert = require('assert');
const {
  MAX_PER_TYPE,
  limitMessage,
  isPartyDocLive,
  isPromotionLive,
  promotionGoneAt,
  isPlaceDocLive,
  groupKeyOf,
  countLiveEntries,
} = require('./registrationLimits');

const cases = [];
const test = (name, fn) => cases.push([name, fn]);

const NOW = new Date('2026-08-31T12:00:00+09:00');
const ago = (days) => new Date(NOW.getTime() - days * 24 * 60 * 60 * 1000);
const ahead = (days) => new Date(NOW.getTime() + days * 24 * 60 * 60 * 1000);

/// 일회성 파티 한 날짜 문서.
const partyDoc = (id, { seriesId, at = ahead(3), deleted = false } = {}) => ({
  id,
  data: {
    hostId: 'host',
    seriesId,
    partyDateTime: at,
    singleSchedule: { startAt: at, endAt: new Date(at.getTime() + 3 * 3600000) },
    ...(deleted ? { isDeleted: true } : {}),
  },
});

const promoDoc = (id, extra = {}) => ({
  id,
  data: { hostId: 'host', title: '이벤트', isVisible: true, ...extra },
});

const placeDoc = (id, extra = {}) => ({ id, data: { hostId: 'host', ...extra } });

// ── 1. 상한과 안내 ──────────────────────────────────────────────────────────

test('상한은 유형마다 10개다', () => {
  assert.strictEqual(MAX_PER_TYPE, 10);
});

test('안내 문구에 유형 이름이 들어간다', () => {
  assert.ok(limitMessage('party').includes('파티'));
  assert.ok(limitMessage('promotion').includes('이벤트'));
  assert.ok(limitMessage('event').includes('플레이스'));
  assert.ok(limitMessage('place').includes('장소대여'));
  assert.ok(limitMessage('party').includes('10개'));
});

// ── 2. 파티 — 게시글 단위 ───────────────────────────────────────────────────

test('다중 날짜 파티 하나는 1개다 — 문서 5개여도', () => {
  const docs = ['a', 'b', 'c', 'd', 'e'].map((id) =>
    partyDoc(id, { seriesId: 's1', at: ahead(id.charCodeAt(0) - 96) }),
  );
  assert.strictEqual(countLiveEntries('party', docs, { now: NOW }), 1);
});

test('seriesId가 다르면 서로 다른 파티다', () => {
  const docs = [
    partyDoc('a', { seriesId: 's1' }),
    partyDoc('b', { seriesId: 's2' }),
  ];
  assert.strictEqual(countLiveEntries('party', docs, { now: NOW }), 2);
});

test('seriesId 없는 옛 문서는 문서 하나가 파티 하나다', () => {
  const docs = [partyDoc('a'), partyDoc('b')];
  assert.strictEqual(countLiveEntries('party', docs, { now: NOW }), 2);
});

test('파티만 게시글 단위로 묶는다 — 나머지는 문서가 곧 등록물이다', () => {
  assert.strictEqual(groupKeyOf('party', 'doc', { seriesId: 's1' }), 's1');
  assert.strictEqual(groupKeyOf('promotion', 'doc', { seriesId: 's1' }), 'doc');
  assert.strictEqual(groupKeyOf('event', 'doc', {}), 'doc');
});

test('지난 파티는 자리를 차지하지 않는다', () => {
  const past = partyDoc('old', { at: ago(3) });
  assert.strictEqual(isPartyDocLive(past.data, NOW), false);
  assert.strictEqual(countLiveEntries('party', [past], { now: NOW }), 0);
});

test('시리즈에 남은 날짜가 하나라도 있으면 아직 살아 있다', () => {
  const docs = [
    partyDoc('past', { seriesId: 's1', at: ago(5) }),
    partyDoc('next', { seriesId: 's1', at: ahead(2) }),
  ];
  assert.strictEqual(countLiveEntries('party', docs, { now: NOW }), 1);
});

test('삭제된 파티는 세지 않는다', () => {
  const docs = [partyDoc('x', { deleted: true })];
  assert.strictEqual(countLiveEntries('party', docs, { now: NOW }), 0);
  assert.strictEqual(
    countLiveEntries('party', [{ id: 'y', data: { status: 'deleted' } }], { now: NOW }),
    0,
  );
});

test('종료일 없는 무기한 정기 파티는 계속 살아 있다', () => {
  const forever = {
    id: 'r1',
    data: {
      hostId: 'host',
      scheduleType: 'recurring',
      recurringSchedule: {
        weekdays: ['fri'],
        startTime: '19:00',
        endTime: '23:00',
        startDate: '2026-01-01',
      },
    },
  };
  assert.strictEqual(isPartyDocLive(forever.data, NOW), true);
  assert.strictEqual(countLiveEntries('party', [forever], { now: NOW }), 1);
});

// ── 3. 이벤트(placePromotions) ──────────────────────────────────────────────

test('진행 중·시작 전 이벤트는 자리를 차지한다', () => {
  assert.strictEqual(isPromotionLive(promoDoc('a', { endAt: ahead(5) }).data, NOW), true);
  assert.strictEqual(isPromotionLive(promoDoc('b', { startAt: ahead(5) }).data, NOW), true);
  assert.strictEqual(isPromotionLive(promoDoc('c', { isAlways: true }).data, NOW), true);
  // 기간을 아예 안 적은 이벤트도 끝나는 때가 없다.
  assert.strictEqual(isPromotionLive(promoDoc('d').data, NOW), true);
});

test('종료·숨김 이벤트는 자리를 차지하지 않는다', () => {
  assert.strictEqual(isPromotionLive(promoDoc('a', { endAt: ago(1) }).data, NOW), false);
  assert.strictEqual(isPromotionLive(promoDoc('b', { isVisible: false }).data, NOW), false);
});

test('종료일 당일은 아직 진행 중이다 — 하루 끝까지 본다', () => {
  const today = new Date(NOW.getFullYear(), NOW.getMonth(), NOW.getDate(), 1);
  assert.strictEqual(isPromotionLive(promoDoc('a', { endAt: today }).data, NOW), true);
});

test('상시 이벤트는 종료일이 지나 있어도 진행 중이다', () => {
  const data = promoDoc('a', { isAlways: true, endAt: ago(30) }).data;
  assert.strictEqual(isPromotionLive(data, NOW), true);
});

test('한 매장에 여러 이벤트를 만들어도 계정 전체로 센다', () => {
  const docs = [
    promoDoc('a', { placeId: 'p1' }),
    promoDoc('b', { placeId: 'p1' }),
    promoDoc('c', { placeId: 'p2' }),
  ];
  assert.strictEqual(countLiveEntries('promotion', docs, { now: NOW }), 3);
});

// ── 4. 플레이스 · 장소대여 ──────────────────────────────────────────────────

test('숨긴 플레이스·장소대여는 자리를 차지하지 않는다', () => {
  assert.strictEqual(isPlaceDocLive({ isActive: false }), false);
  assert.strictEqual(isPlaceDocLive({ isActive: true }), true);
  // 값이 없는 옛 문서는 노출 중이다(목록 판정과 같다).
  assert.strictEqual(isPlaceDocLive({}), true);
});

test('플레이스와 장소대여는 서로 다른 통이다', () => {
  const events = [placeDoc('e1'), placeDoc('e2')];
  const places = [placeDoc('p1')];
  assert.strictEqual(countLiveEntries('event', events, { now: NOW }), 2);
  assert.strictEqual(countLiveEntries('place', places, { now: NOW }), 1);
});

// ── 5. 한도 판정 ────────────────────────────────────────────────────────────

test('10개면 꽉 찼고, 11번째는 만들 수 없다', () => {
  const ten = Array.from({ length: MAX_PER_TYPE }, (_, i) => placeDoc(`p${i}`));
  assert.strictEqual(countLiveEntries('event', ten, { now: NOW }), MAX_PER_TYPE);
  assert.ok(countLiveEntries('event', ten, { now: NOW }) >= MAX_PER_TYPE);
});

test('방금 만든 것을 빼고 셀 수 있다 — 자기 자신 때문에 걸리지 않게', () => {
  const eleven = Array.from({ length: 11 }, (_, i) => placeDoc(`p${i}`));
  // 11번째(p10)를 빼면 10 — 이 값이 상한 이상이면 그 문서는 초과 생성이다.
  assert.strictEqual(
    countLiveEntries('event', eleven, { now: NOW, excludeKeys: ['p10'] }),
    10,
  );
  // 열 번째(p9)를 만들던 시점에는 9였다 → 통과.
  const ten = eleven.slice(0, 10);
  assert.strictEqual(
    countLiveEntries('event', ten, { now: NOW, excludeKeys: ['p9'] }),
    9,
  );
});

test('수정은 개수를 늘리지 않는다 — 같은 문서는 한 번만 센다', () => {
  const docs = [placeDoc('p1', { updatedAt: NOW }), placeDoc('p1', { updatedAt: NOW })];
  assert.strictEqual(countLiveEntries('event', docs, { now: NOW }), 1);
});

test('파티 시리즈를 통째로 뺄 수 있다 — 방금 만든 다중 날짜 파티', () => {
  const docs = [
    ...Array.from({ length: 10 }, (_, i) => partyDoc(`old${i}`, { seriesId: `s${i}` })),
    partyDoc('new1', { seriesId: 'new' }),
    partyDoc('new2', { seriesId: 'new' }),
  ];
  assert.strictEqual(
    countLiveEntries('party', docs, { now: NOW, excludeKeys: ['new'] }),
    10,
  );
});

// ── 6. 자동 삭제 기준점(이벤트) ─────────────────────────────────────────────
//
// deleteExpiredPromotions가 "언제부터 14일을 세는가"를 정하는 판정이다.
// 앱의 PlacePromotion.goneAt과 **같은 규칙**이어야 한다.

test('기간이 끝난 이벤트 → 종료일의 끝이 기준점', () => {
  const gone = promotionGoneAt({ endAt: ago(20), isVisible: true }, NOW);
  assert.ok(gone != null);
  // 그 날의 23:59:59다(하루 끝까지 진행 중이므로).
  assert.strictEqual(gone.getHours(), 23);
  assert.strictEqual(gone.getDate(), ago(20).getDate());
});

test('호스트가 종료를 누른 이벤트 → 숨긴 시각이 기준점', () => {
  const hiddenAt = ago(20);
  const gone = promotionGoneAt(
    { isVisible: false, hiddenAt, endAt: ahead(30) }, NOW,
  );
  assert.strictEqual(gone.getTime(), hiddenAt.getTime());
});

test('둘 다 겪었으면 먼저 일어난 쪽이 기준점', () => {
  // 8/1에 기간이 끝났고, 8/20에 감췄다 → 기준은 8/1.
  const endAt = ago(30);
  const gone = promotionGoneAt(
    { isVisible: false, hiddenAt: ago(10), endAt }, NOW,
  );
  assert.strictEqual(gone.getDate(), endAt.getDate());
});

test('아직 진행 중이거나 상시인 이벤트는 기준점이 없다 — 지우지 않는다', () => {
  assert.strictEqual(promotionGoneAt({ isVisible: true }, NOW), null);
  assert.strictEqual(
    promotionGoneAt({ isVisible: true, endAt: ahead(5) }, NOW), null,
  );
  assert.strictEqual(
    promotionGoneAt({ isVisible: true, isAlways: true, endAt: ago(30) }, NOW),
    null,
  );
});

test('감췄지만 hiddenAt이 없는 옛 이벤트는 지우지 않는다', () => {
  assert.strictEqual(promotionGoneAt({ isVisible: false }, NOW), null);
});

test('이미 삭제 표시된 문서는 대상이 아니다', () => {
  assert.strictEqual(
    promotionGoneAt({ isVisible: false, hiddenAt: ago(30), isDeleted: true }, NOW),
    null,
  );
});

test('14일 전에는 남고, 지나면 대상이 된다', () => {
  const cutoff = new Date(NOW.getTime() - 14 * 24 * 60 * 60 * 1000);
  const justHidden = promotionGoneAt({ isVisible: false, hiddenAt: ago(13) }, NOW);
  const longHidden = promotionGoneAt({ isVisible: false, hiddenAt: ago(15) }, NOW);
  assert.ok(justHidden.getTime() >= cutoff.getTime(), '13일: 아직 남는다');
  assert.ok(longHidden.getTime() < cutoff.getTime(), '15일: 삭제 대상');
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
    ? `\n등록 개수 제한 규칙 검증 통과 — ${cases.length}건`
    : `\n실패 ${failed}건 / 전체 ${cases.length}건`,
);
process.exit(failed === 0 ? 0 : 1);

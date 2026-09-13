// 콘텐츠 정리 대상 자체 검증 — `npm run check:cleanup`.
//
// 장소/플레이스를 지울 때 "무엇을 같이 치우는가"는 조용히 틀리는 종류의 코드다.
// collectLinkedRefs에서 컬렉션 하나를 빠뜨려도 삭제는 성공하고 예외도 안 난다 —
// 없어진 장소를 가리키는 고아 문서만 DB에 남고, 아무도 모른다. 실제로
// placeMenus·placeVisitReservations·visitSlots가 그렇게 빠져 있었다.
//
// 그래서 여기서는 가짜 Firestore를 만들어 **진짜 collectLinkedRefs/blockingReason을
// 태우고**, placeId로 장소를 가리키는 문서가 refs(삭제) 또는 preserve(보존) 중
// 어느 한쪽에는 반드시 들어갔는지 — 즉 고아가 남지 않는지 — 를 검사한다.

const assert = require('assert');

// contentCleanup이 require하는 Cloudflare 정리를 먼저 가짜로 바꾼다.
// (사진 삭제는 이 검증의 관심사가 아니고, 실제로 네트워크를 타면 안 된다.)
const cfPath = require.resolve('./cloudflareCleanup');
const mediaCalls = [];
require.cache[cfPath] = {
  id: cfPath,
  filename: cfPath,
  loaded: true,
  exports: {
    deleteDocMedia: async (_creds, data) => { mediaCalls.push(data); },
    readCloudflareCreds: () => ({ accountId: 'x', apiToken: 'x', bucket: 'x' }),
  },
};

const { collectLinkedRefs, blockingReason } = require('./contentCleanup');

// ── 가짜 Firestore ────────────────────────────────────────────────────────
// 경로 문자열 → [{ id, data }]. 하위 컬렉션은 'events/PID/visitSlots'처럼 쓴다.
let STORE = {};

function makeDocRef(collPath, id) {
  return {
    id,
    path: `${collPath}/${id}`,
    collection: (sub) => makeCollRef(`${collPath}/${id}/${sub}`),
  };
}

function makeCollRef(collPath) {
  const filters = [];
  const api = {
    where(field, op, value) { filters.push([field, op, value]); return api; },
    async get() {
      let rows = (STORE[collPath] || []).slice();
      for (const [field, op, value] of filters) {
        rows = rows.filter((r) => (op === 'in'
          ? value.includes(r.data[field])
          : r.data[field] === value));
      }
      const docs = rows.map((r) => ({
        id: r.id,
        ref: makeDocRef(collPath, r.id),
        data: () => r.data,
      }));
      return { docs, empty: docs.length === 0, size: docs.length };
    },
  };
  return api;
}

const db = { collection: (c) => makeCollRef(c) };

const PID = 'PLACE_1';
const CREDS = { accountId: 'x', apiToken: 'x', bucket: 'x' };

/// 이 장소를 가리키는 문서를 한 벌 깔아 둔다.
/// live 인자로 방문예약 상태만 바꿔 가며 재사용한다.
function seed({ visitStatus = 'completed' } = {}) {
  STORE = {
    placeRooms:             [{ id: 'room1',  data: { placeId: PID } }],
    placeProducts:          [{ id: 'prod1',  data: { placeId: PID, soldCount: 0 } }],
    placePromotions:        [{ id: 'promo1', data: { placeId: PID, imageUrl: 'p.jpg' } }],
    // ↓ 예전에 빠져 있던 것들
    placeMenus:             [{ id: 'menu1',  data: { placeId: PID, imageUrl: 'm.jpg' } },
                             { id: 'menu2',  data: { placeId: PID } }],
    placeVisitReservations: [{ id: 'visit1', data: { placeId: PID, status: visitStatus } }],
    // 거래기록
    placeReservationGroups: [{ id: 'grp1',   data: { placeId: PID, status: 'completed' } }],
    packageBookings:        [{ id: 'pkg1',   data: { placeId: PID, status: 'completed' } }],
    placeBookings:          [],
    reservations:           [],
    placeProductOrders:     [{ id: 'ord1',   data: { placeId: PID, status: 'used' } }],
    chatRooms:              [{ id: 'chat1',  data: { relatedId: PID } }],
    favorites:              [{ id: 'fav1',   data: { itemId: PID } }],
    [`events/${PID}/reservationSlots`]: [{ id: 'slot1', data: {} }],
    [`events/${PID}/visitSlots`]:       [{ id: 'vslot1', data: {} }],
    'chatRooms/chat1/messages':         [{ id: 'msg1',  data: {} }],
  };
  return makeDocRef('events', PID);
}

const cases = [];
function test(name, fn) { cases.push([name, fn]); }

/// refs/preserve에 담긴 문서 경로 집합.
function pathsOf({ refs, preserve }) {
  return new Set([
    ...refs.map((r) => r.path),
    ...preserve.map((d) => d.ref.path),
  ]);
}

// ── 검사 ──────────────────────────────────────────────────────────────────

test('메뉴(placeMenus)가 삭제 대상에 들어간다', async () => {
  const ref = seed();
  const { refs } = await collectLinkedRefs(db, 'event', ref, CREDS);
  const paths = refs.map((r) => r.path);
  assert.ok(paths.includes('placeMenus/menu1'), 'menu1이 빠졌다');
  assert.ok(paths.includes('placeMenus/menu2'), 'menu2가 빠졌다');
});

test('메뉴 사진도 함께 정리한다(프로모션과 동일)', async () => {
  const ref = seed();
  mediaCalls.length = 0;
  await collectLinkedRefs(db, 'event', ref, CREDS);
  assert.ok(
    mediaCalls.some((d) => d.imageUrl === 'm.jpg'),
    '메뉴 사진이 deleteDocMedia로 넘어가지 않았다',
  );
});

test('방문예약(placeVisitReservations)은 거래기록이라 보존한다', async () => {
  const ref = seed();
  const { refs, preserve } = await collectLinkedRefs(db, 'event', ref, CREDS);
  assert.ok(
    preserve.some((d) => d.ref.path === 'placeVisitReservations/visit1'),
    '방문예약이 보존 목록에 없다',
  );
  assert.ok(
    !refs.some((r) => r.path === 'placeVisitReservations/visit1'),
    '방문예약을 삭제하면 안 된다(거래기록)',
  );
});

test('방문예약 슬롯(visitSlots)은 삭제 대상이다', async () => {
  const ref = seed();
  const { refs } = await collectLinkedRefs(db, 'event', ref, CREDS);
  assert.ok(
    refs.some((r) => r.path === `events/${PID}/visitSlots/vslot1`),
    'visitSlots가 남는다 — 고아 슬롯이 된다',
  );
});

test('고아 없음 — placeId로 장소를 가리키는 문서가 전부 refs/preserve에 잡힌다', async () => {
  const ref = seed();
  const result = await collectLinkedRefs(db, 'event', ref, CREDS);
  const covered = pathsOf(result);

  const missing = [];
  for (const [collPath, rows] of Object.entries(STORE)) {
    for (const row of rows) {
      const d = row.data;
      const pointsHere = d.placeId === PID || d.relatedId === PID || d.itemId === PID
        || collPath.startsWith(`events/${PID}/`);
      if (!pointsHere) continue;
      if (!covered.has(`${collPath}/${row.id}`)) missing.push(`${collPath}/${row.id}`);
    }
  }
  assert.deepStrictEqual(missing, [], `정리되지 않는 고아 문서: ${missing.join(', ')}`);
});

test('살아있는 방문예약이 있으면 삭제를 막는다', async () => {
  for (const status of ['requested', 'approved']) {
    const ref = seed({ visitStatus: status });
    const reason = await blockingReason(db, 'event', ref);
    assert.ok(reason, `status=${status} 인데 삭제가 막히지 않았다`);
    assert.ok(reason.includes('방문예약'), `사유 문구가 방문예약을 가리키지 않는다: ${reason}`);
  }
});

test('끝난 방문예약은 삭제를 막지 않는다', async () => {
  for (const status of ['completed', 'cancelled', 'rejected', 'expired']) {
    const ref = seed({ visitStatus: status });
    const reason = await blockingReason(db, 'event', ref);
    assert.strictEqual(reason, null, `status=${status} 인데 삭제가 막혔다: ${reason}`);
  }
});

test('장소(place) 유형에서도 같은 규칙이 걸린다', async () => {
  const ref = seed();
  const { refs, preserve } = await collectLinkedRefs(db, 'place', ref, CREDS);
  assert.ok(refs.some((r) => r.path === 'placeMenus/menu1'), 'place에서 메뉴가 빠졌다');
  assert.ok(
    preserve.some((d) => d.ref.path === 'placeVisitReservations/visit1'),
    'place에서 방문예약 보존이 빠졌다',
  );
});

test('기존 정책은 그대로 — 룸·프로모션은 삭제, 예약·이용권은 보존', async () => {
  const ref = seed();
  const { refs, preserve } = await collectLinkedRefs(db, 'event', ref, CREDS);
  const del = refs.map((r) => r.path);
  const keep = preserve.map((d) => d.ref.path);
  for (const p of ['placeRooms/room1', 'placePromotions/promo1', 'placeProducts/prod1',
    'chatRooms/chat1', 'favorites/fav1', `events/${PID}/reservationSlots/slot1`]) {
    assert.ok(del.includes(p), `${p} 가 삭제 대상에서 빠졌다`);
  }
  for (const p of ['placeReservationGroups/grp1', 'packageBookings/pkg1',
    'placeProductOrders/ord1']) {
    assert.ok(keep.includes(p), `${p} 가 보존 대상에서 빠졌다`);
  }
});

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
      ? `\n콘텐츠 정리 대상 검증 통과 — ${cases.length}건`
      : `\n실패 ${failed}건 / 전체 ${cases.length}건`,
  );
  process.exit(failed === 0 ? 0 : 1);
})();

// 채팅방 생성 판정 자체 검증 — `node chatRooms.selfcheck.js`.
//
// 여기서 못박는 것은 "누가 새 방을 열 수 있는가" 하나다.
//
//   · 실제 신청·예약·주문 기록이 있으면  → 문의 설정과 무관하게 열린다
//   · 기록이 없으면                      → 호스트가 문의를 열어 뒀을 때만 열린다
//   · 둘 다 아니면                       → 열리지 않는다
//
// 예전에는 이 판정을 방 문서의 origin 필드가 대신했다. 그 값을 쓰는 쪽이
// 클라이언트라 'booking'이라고 적어 보내면 문의 OFF가 통째로 무력해졌다.
// 그래서 아래 테스트에는 **클라이언트가 보낸 값으로 판정이 바뀌는 경로가
// 하나도 없다** — 있으면 그게 곧 회귀다.
//
// 클라이언트 쪽 같은 정책은 party_app/test/guest_inquiry_test.dart가 본다.

const assert = require('assert');
const {
  roomIdFor,
  findListing,
  hasBookingRecord,
  LISTING_COLLECTIONS,
  BOOKING_LOOKUPS,
} = require('./chatRooms').__helpers;

const cases = [];
const test = (name, fn) => cases.push([name, fn]);

// ── Firestore 흉내 ──────────────────────────────────────────────────────
//
// docs: { '컬렉션/문서id': {필드} }
// rows: { '컬렉션': [ {필드}, ... ] }  ← 쿼리 대상
function fakeDb({ docs = {}, rows = {} } = {}) {
  function makeQuery(list, filters) {
    return {
      where(field, op, value) {
        assert.strictEqual(op, '==', '동등 비교만 쓴다(복합 색인 불필요)');
        return makeQuery(list, [...filters, [field, value]]);
      },
      limit() {
        return this;
      },
      async get() {
        const hit = list.filter((r) => filters.every(([f, v]) => r[f] === v));
        return { empty: hit.length === 0, docs: hit.map((d) => ({ data: () => d })) };
      },
    };
  }

  function collection(name) {
    return {
      ...makeQuery(rows[name] || [], []),
      doc(id) {
        return {
          async get() {
            const data = docs[`${name}/${id}`];
            return { exists: data !== undefined, data: () => data };
          },
          collection(sub) {
            return makeQuery(rows[`${name}/${id}/${sub}`] || [], []);
          },
        };
      },
    };
  }
  return { collection };
}

// ── 방 id는 앱과 같은 규칙이어야 한다 ───────────────────────────────────

test('방 id 규칙이 앱(ChatService.roomIdFor)과 같다', () => {
  assert.strictEqual(
    roomIdFor({ relatedType: 'party', relatedId: 'p1', guestId: 'g1' }),
    'g1_party_p1'
  );
  // 게스트 uid가 맨 앞이라야 규칙이 문서 id만 보고 "내 방"을 판별할 수 있다.
  assert.ok(roomIdFor({ relatedType: 'place', relatedId: 'x', guestId: 'g1' })
    .startsWith('g1_'));
});

// ── 원본 글 찾기 ────────────────────────────────────────────────────────

test("relatedType 'place'는 events와 places 양쪽에서 찾는다", async () => {
  // 플레이스(events)와 장소대여(places)가 같은 relatedType을 쓰기 때문이다.
  const db = fakeDb({ docs: { 'places/x': { hostId: 'h1' } } });
  const found = await findListing(db, 'place', 'x');
  assert.strictEqual(found.collection, 'places');

  const db2 = fakeDb({ docs: { 'events/x': { hostId: 'h1' } } });
  assert.strictEqual((await findListing(db2, 'place', 'x')).collection, 'events');
});

test('없는 글은 null이다 — 있지도 않은 대상에 방을 열 수 없다', async () => {
  const db = fakeDb({ docs: {} });
  assert.strictEqual(await findListing(db, 'party', 'nope'), null);
});

test('컬렉션 표는 relatedType에서만 나온다 — 클라이언트가 고르지 않는다', () => {
  assert.deepStrictEqual(LISTING_COLLECTIONS.party, ['parties']);
  assert.deepStrictEqual(LISTING_COLLECTIONS.place, ['events', 'places']);
  assert.deepStrictEqual(LISTING_COLLECTIONS.shop, ['partyShops']);
  assert.deepStrictEqual(LISTING_COLLECTIONS.crew, ['crews']);
  // 이벤트는 플레이스와 **다른 컬렉션**이다. 'place'로 뭉뚱그리면
  // placePromotions 문서를 못 찾아 문의가 not-found로 죽는다.
  assert.deepStrictEqual(LISTING_COLLECTIONS.event, ['placePromotions']);
  assert.ok(!LISTING_COLLECTIONS.place.includes('placePromotions'));
  // 이 표에 없는 relatedType은 콜러블이 invalid-argument로 막는다.
  assert.strictEqual(LISTING_COLLECTIONS.users, undefined);
});

test('이벤트에는 거래 기록이 없다 — 문의가 유일한 경로다', async () => {
  const db = fakeDb({ rows: {} });
  assert.strictEqual(
    await hasBookingRecord(db, {
      relatedType: 'event',
      relatedId: 'promo1',
      guestId: 'g1',
    }),
    false
  );
});

// ── 예약 기록 찾기 ──────────────────────────────────────────────────────

test('파티 신청 기록을 찾는다 — 파티 문서 아래 applications', async () => {
  const db = fakeDb({ rows: { 'parties/p1/applications': [{ uid: 'g1' }] } });
  assert.strictEqual(
    await hasBookingRecord(db, { relatedType: 'party', relatedId: 'p1', guestId: 'g1' }),
    true
  );
  // 남의 신청은 내 것이 아니다.
  assert.strictEqual(
    await hasBookingRecord(db, { relatedType: 'party', relatedId: 'p1', guestId: 'other' }),
    false
  );
});

test('플레이스·장소대여의 네 가지 기록을 모두 본다', async () => {
  const sources = {
    placeVisitReservations: { requesterId: 'g1', placeId: 'x' },
    placeReservationGroups: { requesterId: 'g1', placeId: 'x' },
    packageBookings: { requesterId: 'g1', placeId: 'x' },
    placeProductOrders: { buyerId: 'g1', placeId: 'x' },
  };
  for (const [collection, row] of Object.entries(sources)) {
    const db = fakeDb({ rows: { [collection]: [row] } });
    assert.strictEqual(
      await hasBookingRecord(db, { relatedType: 'place', relatedId: 'x', guestId: 'g1' }),
      true,
      `${collection}을(를) 보지 않는다`
    );
  }
});

test('다른 장소의 예약으로는 이 장소의 방을 열 수 없다', async () => {
  const db = fakeDb({
    rows: { placeVisitReservations: [{ requesterId: 'g1', placeId: '다른곳' }] },
  });
  assert.strictEqual(
    await hasBookingRecord(db, { relatedType: 'place', relatedId: 'x', guestId: 'g1' }),
    false
  );
});

test('파티샵 주문 기록을 찾는다', async () => {
  const db = fakeDb({ rows: { orders: [{ buyerId: 'g1', shopId: 's1' }] } });
  assert.strictEqual(
    await hasBookingRecord(db, { relatedType: 'shop', relatedId: 's1', guestId: 'g1' }),
    true
  );
});

test('파티크루에는 거래 기록이 없다 — 문의가 유일한 경로다', async () => {
  assert.deepStrictEqual(BOOKING_LOOKUPS.crew, []);
  const db = fakeDb({});
  assert.strictEqual(
    await hasBookingRecord(db, { relatedType: 'crew', relatedId: 'c1', guestId: 'g1' }),
    false
  );
});

test('기록이 하나도 없으면 false다 — 판정을 못 해도 통과시키지 않는다', async () => {
  const db = fakeDb({});
  for (const relatedType of ['party', 'place', 'shop']) {
    assert.strictEqual(
      await hasBookingRecord(db, { relatedType, relatedId: 'x', guestId: 'g1' }),
      false
    );
  }
});

test('한 컬렉션 조회가 실패해도 나머지에서 찾는다', async () => {
  // 색인 문제 등으로 한 쪽이 터져도 예약자가 대화를 못 여는 일은 없어야 한다.
  const db = fakeDb({ rows: { packageBookings: [{ requesterId: 'g1', placeId: 'x' }] } });
  const original = db.collection;
  db.collection = (name) => {
    if (name === 'placeVisitReservations') {
      return { where: () => { throw new Error('색인 없음'); } };
    }
    return original(name);
  };
  assert.strictEqual(
    await hasBookingRecord(db, { relatedType: 'place', relatedId: 'x', guestId: 'g1' }),
    true
  );
});

// ── 판정 조합(콜러블이 쓰는 규칙 그대로) ────────────────────────────────

test('예약자면 문의를 닫아도 열리고, 아니면 문의 설정을 따른다', async () => {
  // 콜러블 본문의 판정식과 같은 형태로 조합해 본다.
  const decide = (booked, inquiryEnabled) =>
    booked ? 'booking' : inquiryEnabled !== false ? 'inquiry' : null;

  assert.strictEqual(decide(true, false), 'booking', '예약자는 OFF여도 열려야 한다');
  assert.strictEqual(decide(true, true), 'booking', '예약자는 booking으로 기록된다');
  assert.strictEqual(decide(false, true), 'inquiry');
  assert.strictEqual(decide(false, undefined), 'inquiry', '필드 없음 = ON');
  assert.strictEqual(decide(false, false), null, '문의 OFF + 기록 없음 → 거부');
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
  console.log(failed === 0 ? `\n채팅방 생성 판정 ${cases.length}건 통과` : `\n${failed}건 실패`);
  process.exit(failed === 0 ? 0 : 1);
})();

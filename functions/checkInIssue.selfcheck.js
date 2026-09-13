// QR **발급 생명주기** 확인 — `node checkInIssue.selfcheck.js`
//
// checkInTokens.selfcheck.js가 "지금 이 QR로 들어갈 수 있나"(차단 사유)를 본다면,
// 이쪽은 "QR이 애초에 존재하는가"를 본다. 틀리면 손님이 QR을 못 받거나(입장
// 불가), 취소된 QR이 살아남는다(공짜 입장).
//
// 진짜 Firestore 대신 **가짜 db**를 쓴다. 트랜잭션·increment·serverTimestamp만
// 흉내 내면 checkInTokenStore와 두 트리거 본체를 그대로 돌릴 수 있고, 그래야
// "트리거를 두 번 실행하면?" 같은 질문을 실제로 물어볼 수 있다.

const assert = require('assert');

const store = require('./checkInTokenStore');
const rules = require('./checkInRules');
const party = require('./partyCheckIn').__test;
const reservation = require('./reservationCheckIn').__test;
const product = require('./productCheckIn').__test;

// ── 가짜 Firestore ──────────────────────────────────────────────────────────
//
// 문서를 경로 문자열 → 평평한 맵으로 담는다. merge/increment/serverTimestamp만
// 흉내 내면 되고, 트랜잭션은 단일 스레드라 그냥 순서대로 적용하면 된다.

const NOW = Date.UTC(2026, 7, 30, 11, 0); // 2026-08-30 20:00 KST

/**
 * FieldValue 센티널을 해석한다.
 *
 * 실제 SDK가 만든 값을 그대로 받는다 — 가짜로 바꿔치기하지 않는 이유는
 * `admin.firestore.FieldValue`가 getter라 대입이 조용히 무시되고, 그러면
 * increment가 안 먹은 채로 "통과"하는 자체 검증이 되기 때문이다.
 */
function transformOf(v) {
  const name = v && typeof v === 'object' && v.constructor && v.constructor.name;
  if (name === 'NumericIncrementTransform') return { inc: v.operand };
  if (name === 'ServerTimestampTransform') return { now: true };
  return null;
}

function applyPatch(target, patch) {
  for (const [k, v] of Object.entries(patch)) {
    const t = transformOf(v);
    if (t && t.inc !== undefined) {
      target[k] = (typeof target[k] === 'number' ? target[k] : 0) + t.inc;
    } else if (t && t.now) {
      target[k] = { toMillis: () => NOW };
    } else {
      target[k] = v;
    }
  }
}

function makeDb() {
  const docs = new Map();
  const writes = [];

  const ref = (path) => ({
    path,
    id: path.split('/').pop(),
    collection: (name) => collectionRef(`${path}/${name}`),
    async get() {
      return snapOf(path);
    },
    async set(patch, opts) {
      writes.push(path);
      const base = opts && opts.merge ? { ...(docs.get(path) || {}) } : {};
      applyPatch(base, patch);
      docs.set(path, base);
    },
    async update(patch) {
      writes.push(path);
      if (!docs.has(path)) throw new Error('update on missing doc: ' + path);
      const base = { ...docs.get(path) };
      applyPatch(base, patch);
      docs.set(path, base);
    },
  });

  const snapOf = (path) => ({
    exists: docs.has(path),
    ref: ref(path),
    id: path.split('/').pop(),
    data: () => docs.get(path),
  });

  const collectionRef = (base) => ({
    doc: (id) => ref(`${base}/${id || 'auto' + docs.size}`),
    async add(value) {
      const path = `${base}/auto${docs.size}`;
      docs.set(path, value);
      writes.push(path);
    },
  });

  return {
    docs,
    writes,
    collection: collectionRef,
    doc: (path) => ref(path),
    async runTransaction(fn) {
      return fn({
        get: (r) => Promise.resolve(snapOf(r.path)),
        set: (r, patch, opts) => r.set(patch, opts),
        update: (r, patch) => r.update(patch),
      });
    },
  };
}

// ── 헬퍼 ────────────────────────────────────────────────────────────────────

const PARTY_ID = 'p1';
const APP_ID = 'u1';
const APP_PATH = `parties/${PARTY_ID}/applications/${APP_ID}`;

/** 신청 문서 한 벌 — 필요한 필드만. */
function application(overrides = {}) {
  return {
    uid: 'u1',
    hostId: 'host1',
    status: 'approved',
    region: '서울',
    district: '마포구',
    partyStartHour: 20,
    isTestAccount: false,
    ...overrides,
  };
}

/** 트리거 이벤트 흉내 — before/after와 after.ref만 있으면 된다. */
function event(db, path, before, after, params) {
  const docRef = db.doc(path);
  if (after) db.docs.set(path, { ...after });
  else db.docs.delete(path);
  return {
    params,
    data: {
      before: { exists: !!before, data: () => before },
      after: { exists: !!after, data: () => after, ref: docRef },
    },
  };
}

/** 파티 트리거를 한 번 돌린다. 문서에 남은 최종 상태를 돌려준다. */
async function runParty(db, before, after) {
  const ev = event(db, APP_PATH, before, after, {
    partyId: PARTY_ID,
    applicationId: APP_ID,
  });
  await party.handlePartyApplicationWrite(db, ev);
  return db.docs.get(APP_PATH);
}

/** 지금 이 원본에 붙어 있는 **살아 있는** 토큰(없으면 null). */
function liveToken(db, refPath) {
  const idx = db.docs.get(
    `checkInTokenIndex/${store.tokenIndexKey(refPath)}`,
  );
  if (!idx) return null;
  const t = db.docs.get(`checkInTokens/${idx.token}`);
  return t && store.isTokenActive(t) ? idx.token : null;
}

/** 살아 있든 죽었든, 이 원본을 가리키는 토큰 문서를 전부 센다. */
function allTokensFor(db, refPath) {
  return [...db.docs.entries()].filter(
    ([path, v]) =>
      path.startsWith('checkInTokens/') &&
      path.split('/').length === 2 &&
      v.refPath === refPath,
  );
}

async function main() {
  // ═════════════════════════════════════════════════════════════════════════
  // 1. 파티 — 승인 전에는 QR이 없다
  // ═════════════════════════════════════════════════════════════════════════

  {
    const db = makeDb();
    const doc = await runParty(db, null, application({ status: 'pending' }));
    assert.strictEqual(
      doc.checkInToken,
      undefined,
      '승인 대기 신청에 QR이 발급되면 승인 전에 입장할 수 있게 된다',
    );
    assert.strictEqual(liveToken(db, APP_PATH), null);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // 2. 승인되면 QR이 **딱 하나** 생기고, 트리거를 다시 돌려도 늘지 않는다
  // ═════════════════════════════════════════════════════════════════════════

  {
    const db = makeDb();
    const approved = application();
    const doc = await runParty(db, application({ status: 'pending' }), approved);
    const token = doc.checkInToken;
    assert.ok(token, '승인된 신청에는 QR이 있어야 한다');
    assert.strictEqual(liveToken(db, APP_PATH), token);
    assert.strictEqual(allTokensFor(db, APP_PATH).length, 1);

    // 트리거 재실행 — 같은 문서로 몇 번을 더 돌려도 토큰은 그대로다.
    for (let i = 0; i < 3; i += 1) {
      const again = await runParty(db, approved, { ...approved, checkInToken: token });
      assert.strictEqual(again.checkInToken, token, '재실행이 새 토큰을 만들면 안 된다');
    }
    assert.strictEqual(
      allTokensFor(db, APP_PATH).length,
      1,
      '트리거 재실행마다 토큰이 늘면 취소한 QR로 입장할 수 있게 된다',
    );

    // 그리고 **아무것도 쓰지 않는다** — 자기 쓰기로 다시 깨어나면 끝나지 않는다.
    const before = db.writes.length;
    await runParty(db, approved, { ...approved, checkInToken: token });
    assert.strictEqual(
      db.writes.length,
      before,
      '바뀔 것이 없는 재실행이 문서를 다시 쓰면 트리거가 무한히 돈다',
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // 3. 취소·거절되면 QR이 죽고, 다시 승인되면 **새** 토큰이 나온다
  // ═════════════════════════════════════════════════════════════════════════

  {
    const db = makeDb();
    const approved = application();
    const first = (await runParty(db, null, approved)).checkInToken;

    const cancelled = { ...approved, status: 'cancelled', checkInToken: first };
    const afterCancel = await runParty(db, approved, cancelled);
    assert.strictEqual(afterCancel.checkInToken, null, '취소된 신청에는 QR이 남으면 안 된다');
    assert.strictEqual(liveToken(db, APP_PATH), null);
    assert.strictEqual(
      db.docs.get(`checkInTokens/${first}`).active,
      false,
      '토큰 문서는 지우지 않고 죽인다 — "없는 QR"이 아니라 "쓸 수 없는 QR"이어야 한다',
    );

    // 다시 승인 — 죽은 토큰을 되살리지 않는다(취소 기간에 퍼진 캡처본이 살아난다).
    const reapproved = { ...approved, checkInToken: null };
    const second = (await runParty(db, cancelled, reapproved)).checkInToken;
    assert.ok(second, '다시 승인되면 QR이 다시 나와야 한다');
    assert.notStrictEqual(second, first, '죽은 토큰을 되살리면 옛 QR이 다시 통과한다');
    assert.strictEqual(
      db.docs.get(`checkInTokens/${first}`).active,
      false,
      '옛 토큰은 영원히 죽은 채여야 한다',
    );
    assert.strictEqual(liveToken(db, APP_PATH), second);
    // 두 개가 존재하지만 **살아 있는 것은 하나**다.
    assert.strictEqual(allTokensFor(db, APP_PATH).length, 2);
    assert.strictEqual(
      allTokensFor(db, APP_PATH).filter(([, v]) => store.isTokenActive(v)).length,
      1,
      '동시에 유효한 QR이 둘이면 취소가 뜻을 잃는다',
    );
  }

  // 거절된 신청도 같다.
  {
    const db = makeDb();
    const approved = application();
    const token = (await runParty(db, null, approved)).checkInToken;
    await runParty(db, approved, { ...approved, status: 'rejected', checkInToken: token });
    assert.strictEqual(liveToken(db, APP_PATH), null, '거절된 신청의 QR은 살아 있으면 안 된다');
  }

  // 즉시확정 파티('applied')도 QR을 받는다 — 승인 단계가 없어 approved가 되지
  // 않으므로, 여기서 빠지면 그 파티 참가자는 QR을 영영 못 받는다.
  {
    const db = makeDb();
    const doc = await runParty(db, null, application({ status: 'applied' }));
    assert.ok(doc.checkInToken, '즉시확정 파티 참가자도 QR을 받아야 한다');
  }

  // ═════════════════════════════════════════════════════════════════════════
  // 4. 파티 QR 스캔만으로는 체크인되지 않는다 — 출석은 checkedInAt이 정본
  // ═════════════════════════════════════════════════════════════════════════

  {
    const db = makeDb();
    const approved = application();
    const token = (await runParty(db, null, approved)).checkInToken;
    const issued = { ...approved, checkInToken: token };

    // 발급만으로는 출석 카운터가 움직이지 않는다.
    assert.strictEqual(db.docs.get('userStats/u1'), undefined);
    assert.strictEqual(db.docs.get('dailyStats/2026-08-30'), undefined);

    // 호스트가 체크인 버튼을 눌러 checkedInAt이 찍힌 순간 +1.
    const checkedIn = {
      ...issued,
      checkedInAt: { toMillis: () => NOW },
      checkedInBy: 'host1',
    };
    await runParty(db, issued, checkedIn);
    assert.strictEqual(db.docs.get('userStats/u1').totalAttended, 1);
    assert.strictEqual(db.docs.get('dailyStats/2026-08-30').attended, 1);
    assert.strictEqual(db.docs.get('regionStats/서울_마포구').totalAttended, 1);
    assert.strictEqual(db.docs.get('hourlyStats/20').attended, 1);
    assert.strictEqual(
      db.docs.get(APP_PATH).status,
      'approved',
      '체크인은 신청 상태를 바꾸지 않는다 — approved가 그대로 유지돼야 한다',
    );

    // 같은 문서가 다른 이유로 또 쓰여도 두 번 세지 않는다.
    await runParty(db, checkedIn, { ...checkedIn, hostMessage: '메모' });
    assert.strictEqual(
      db.docs.get('userStats/u1').totalAttended,
      1,
      '체크인 뒤의 다른 쓰기가 출석을 또 세면 안 된다',
    );

    // 되돌리면 정확히 그만큼 줄어든다.
    const revoked = {
      ...checkedIn,
      checkedInAt: null,
      checkedInBy: null,
      checkInRevokedBy: 'host1',
    };
    await runParty(db, checkedIn, revoked);
    assert.strictEqual(db.docs.get('userStats/u1').totalAttended, 0);
    assert.strictEqual(
      db.docs.get('dailyStats/2026-08-30').attended,
      0,
      '되돌리기는 **체크인한 날**의 칸을 줄여야 한다',
    );
    assert.strictEqual(db.docs.get('regionStats/서울_마포구').totalAttended, 0);
    assert.strictEqual(db.docs.get('hourlyStats/20').attended, 0);
  }

  // 되돌리기가 자정을 넘겨도 늘렸던 날의 칸을 줄인다.
  {
    const yesterdayMs = Date.UTC(2026, 7, 29, 11, 0); // 8/29 20:00 KST
    assert.strictEqual(
      party.dateKeyOfCheckIn(
        { checkedInAt: { toMillis: () => yesterdayMs } },
        { checkedInAt: null },
        -1,
      ),
      '2026-08-29',
      '되돌린 날짜를 깎으면 엉뚱한 날의 통계가 줄어든다',
    );
  }

  // 테스트 계정의 체크인은 서비스 KPI에 섞이지 않는다(본인 기록에는 남는다).
  {
    const db = makeDb();
    const app = application({ isTestAccount: true });
    const token = (await runParty(db, null, app)).checkInToken;
    const issued = { ...app, checkInToken: token };
    await runParty(db, issued, { ...issued, checkedInAt: { toMillis: () => NOW } });
    assert.strictEqual(db.docs.get('userStats/u1').totalAttended, 1);
    assert.strictEqual(db.docs.get('dailyStats/2026-08-30'), undefined);
    assert.strictEqual(db.docs.get('regionStats/서울_마포구'), undefined);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // 5. 예약 — 확정 전에는 QR이 없고, 취소·만료되면 죽는다
  // ═════════════════════════════════════════════════════════════════════════

  /** 예약 트리거를 한 번 돌린다. */
  async function runReservation(db, collection, id, before, after) {
    const path = `${collection}/${id}`;
    const ev = event(db, path, before, after, { id });
    await reservation.syncReservationToken(db, ev, collection);
    return db.docs.get(path);
  }

  const RESERVATION_CASES = [
    // [컬렉션, 확정 상태, 확정 전 상태, 끝난 상태]
    ['placeVisitReservations', 'approved', 'requested', 'cancelled_by_guest'],
    ['placeReservationGroups', 'confirmed', 'requested', 'cancelled'],
    ['packageBookings', 'confirmed', 'requested', 'expired'],
  ];

  for (const [collection, confirmed, waiting, ended] of RESERVATION_CASES) {
    const db = makeDb();
    const path = `${collection}/r1`;
    const base = { hostId: 'host1', requesterId: 'u1' };

    // 확정 전 — QR 없음.
    const pending = { ...base, status: waiting };
    const p = await runReservation(db, collection, 'r1', null, pending);
    assert.strictEqual(
      p.checkInToken,
      undefined,
      `${collection}: 확정 전에 QR이 나오면 승인 전 입장이 된다`,
    );

    // 확정 — QR 하나.
    const ok = { ...base, status: confirmed };
    const token = (await runReservation(db, collection, 'r1', pending, ok))
      .checkInToken;
    assert.ok(token, `${collection}: 확정된 예약에는 QR이 있어야 한다`);
    assert.strictEqual(liveToken(db, path), token);

    // 재실행 — 늘지 않는다.
    await runReservation(db, collection, 'r1', ok, { ...ok, checkInToken: token });
    assert.strictEqual(
      allTokensFor(db, path).length,
      1,
      `${collection}: 트리거 재실행이 토큰을 늘리면 안 된다`,
    );

    // 취소·만료 — 죽는다.
    const dead = { ...ok, status: ended, checkInToken: token };
    const afterEnd = await runReservation(db, collection, 'r1', ok, dead);
    assert.strictEqual(afterEnd.checkInToken, null);
    assert.strictEqual(
      liveToken(db, path),
      null,
      `${collection}: ${ended} 상태의 QR이 살아 있으면 안 된다`,
    );
    assert.strictEqual(db.docs.get(`checkInTokens/${token}`).active, false);

    // 문서 자체가 사라져도 죽는다.
    const db2 = makeDb();
    const t2 = (await runReservation(db2, collection, 'r1', null, ok)).checkInToken;
    await runReservation(db2, collection, 'r1', ok, null);
    assert.strictEqual(db2.docs.get(`checkInTokens/${t2}`).active, false);
  }

  // 표에 없는 컬렉션은 아예 발급하지 않는다 — 새 예약 도메인이 생겼을 때 엉뚱한
  // QR이 나오는 것보다 안 나오는 편이 안전하다.
  assert.strictEqual(rules.reservationQrActive('placeBookings', { status: 'confirmed' }), false);

  // ═════════════════════════════════════════════════════════════════════════
  // 6. 포인터는 원본 경로에서 결정된다 — 같은 원본이면 언제나 같은 자리
  // ═════════════════════════════════════════════════════════════════════════

  assert.strictEqual(
    store.tokenIndexKey(APP_PATH),
    store.tokenIndexKey(APP_PATH),
    '같은 경로가 다른 포인터를 가리키면 멱등성이 통째로 깨진다',
  );
  assert.notStrictEqual(
    store.tokenIndexKey(APP_PATH),
    store.tokenIndexKey(`parties/${PARTY_ID}/applications/u2`),
  );

  // 필드가 없던 옛 토큰은 살아 있는 것으로 읽는다(하위 호환).
  assert.strictEqual(store.isTokenActive({ domain: 'party' }), true);
  assert.strictEqual(store.isTokenActive({ active: false }), false);

  // ═════════════════════════════════════════════════════════════════════════
  // 7. 이미 발급된 상품 이용권은 새 스캐너에서도 그대로 동작한다
  // ═════════════════════════════════════════════════════════════════════════
  //
  // 파티·예약은 checkInTokens 토큰을 쓰지만, 이용권은 지금도 주문 문서의
  // voucherCode가 QR 값이다. 여기를 지우면 **이미 손님 폰에 있는 QR**과 옛
  // 앱이 부르는 redeemProductVoucher가 한꺼번에 죽는다.
  {
    const src = require('fs').readFileSync('./checkInTokens.js', 'utf8');
    assert.ok(
      src.includes("where('voucherCode', '==', token)"),
      '토큰 문서가 없는 옛 이용권을 찾는 경로가 사라지면 이미 뿌린 QR이 전부 죽는다',
    );
    const exported = require('./placeProductOrders');
    assert.ok(
      exported.redeemProductVoucher,
      '옛 앱이 부르는 redeemProductVoucher가 사라지면 업데이트 안 한 사장님의 스캔이 죽는다',
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // 8. 상품 — 현장결제만 결제 전에 QR을 갖는다
  // ═════════════════════════════════════════════════════════════════════════
  //
  // checkInToken은 **조회용 식별자**이지 결제 증명이 아니다. 그래서 현장결제
  // 주문은 돈이 들어오기 전에도 QR을 갖고, 무통장입금 주문은 갖지 않는다
  // (입금 확인 전에는 쓸 수 있는 QR을 노출하지 않는 기존 정책 그대로).

  /** 상품 트리거를 한 번 돌린다. */
  async function runProduct(db, id, before, after) {
    const path = `placeProductOrders/${id}`;
    const ev = event(db, path, before, after, { id });
    await product.handleProductOrderWrite(db, ev);
    return db.docs.get(path);
  }

  const onSiteOrder = (extra = {}) => ({
    hostId: 'host1',
    buyerId: 'u1',
    productName: '보틀 1병',
    productType: 'bottle',
    quantity: 1,
    totalPrice: 60000,
    status: 'payment_pending',
    voucherCode: '',
    useQrCheck: true,
    payment: { method: 'on_site', status: 'on_site_scheduled', amount: 60000 },
    ...extra,
  });

  {
    const db = makeDb();
    const path = 'placeProductOrders/o1';

    // 현장결제 — 주문이 생기는 순간 QR이 붙는다.
    const created = onSiteOrder();
    const doc = await runProduct(db, 'o1', null, created);
    const token = doc.checkInToken;
    assert.ok(token, '현장결제 주문에 QR이 없으면 손님이 보여줄 것이 없다');
    assert.strictEqual(liveToken(db, path), token);
    assert.strictEqual(
      doc.voucherCode,
      '',
      'checkInToken 발급이 voucherCode를 건드리면 두 값의 역할이 섞인다',
    );

    // 트리거 재실행 — 토큰은 그대로고 아무것도 쓰지 않는다.
    const issued = { ...created, checkInToken: token };
    const writes = db.writes.length;
    await runProduct(db, 'o1', created, issued);
    assert.strictEqual(db.writes.length, writes, '재실행이 문서를 다시 쓰면 트리거가 무한히 돈다');
    assert.strictEqual(allTokensFor(db, path).length, 1);

    // 결제 확인 — voucherCode가 그때 생기고, **QR 값은 바뀌지 않는다**.
    const paid = {
      ...issued,
      status: 'usable',
      voucherCode: 'voucher-issued-now',
      payment: { ...issued.payment, status: 'paid' },
    };
    const afterPaid = await runProduct(db, 'o1', issued, paid);
    assert.strictEqual(
      afterPaid.checkInToken,
      token,
      '결제 전후로 QR 값이 바뀌면 호스트가 다시 스캔해야 한다',
    );
    assert.strictEqual(afterPaid.voucherCode, 'voucher-issued-now');

    // 사용 완료 — 토큰은 살려 둔다.
    const used = { ...paid, status: 'used' };
    await runProduct(db, 'o1', paid, used);
    assert.strictEqual(
      liveToken(db, path),
      token,
      '사용 완료 토큰을 죽이면 다시 찍었을 때 "이미 사용함"이 아니라 "없는 QR"로 보인다',
    );

    // 취소 — 여기서 죽는다.
    const cancelled = { ...paid, status: 'cancelled' };
    const afterCancel = await runProduct(db, 'o1', paid, cancelled);
    assert.strictEqual(afterCancel.checkInToken, null);
    assert.strictEqual(liveToken(db, path), null, '취소된 주문의 QR이 살아 있으면 안 된다');
  }

  // 무통장입금은 그대로 — 결제 전에는 QR을 만들지 않는다.
  {
    const db = makeDb();
    const bank = onSiteOrder({
      payment: { method: 'bank_transfer', status: 'awaiting_deposit', amount: 60000 },
    });
    const doc = await runProduct(db, 'o2', null, bank);
    assert.strictEqual(
      doc.checkInToken,
      undefined,
      '무통장입금 대기 주문에 사전 QR을 주면 기존 정책이 흔들린다',
    );
    assert.strictEqual(liveToken(db, 'placeProductOrders/o2'), null);

    // 입금이 확인돼도 checkInToken은 만들지 않는다 — 그쪽 QR은 voucherCode다.
    const confirmed = {
      ...bank,
      status: 'usable',
      voucherCode: 'bank-voucher',
      payment: { ...bank.payment, status: 'paid' },
    };
    const after = await runProduct(db, 'o2', bank, confirmed);
    assert.strictEqual(after.checkInToken, undefined);
    assert.strictEqual(after.voucherCode, 'bank-voucher', '무통장입금의 QR은 예전 그대로 voucherCode다');
  }

  // QR을 쓰지 않는 상품은 아예 대상이 아니다.
  {
    const db = makeDb();
    const doc = await runProduct(db, 'o3', null, onSiteOrder({ useQrCheck: false }));
    assert.strictEqual(doc.checkInToken, undefined);
  }

  // 결제 맵이 없는 옛 주문도 건드리지 않는다.
  assert.strictEqual(
    rules.productQrActive({ useQrCheck: true, status: 'usable' }),
    false,
    '옛 PG 주문은 voucherCode 경로 그대로 둔다',
  );

  console.log('✅ checkInIssue.selfcheck 통과');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

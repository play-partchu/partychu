// 숙박+파티 콤보 예약의 **선점/반납 불변식** 자체 검증 — `npm run check:package`.
//
// 콤보의 선점은 세 곳에 걸쳐 있다: 방 슬롯 / 파티 정원 카운터 / 파티 신청 문서.
// 하나만 풀리면 "방은 비었는데 파티 정원은 찬"(또는 그 반대) 상태가 되고, 그건
// 어떤 화면에서도 고칠 수 없다. 그래서 여기서 못 박는 것은 두 가지다.
//
// 1. 예약 수명의 **모든 상태**에서 방 슬롯과 파티 정원이 함께 유지되거나
//    함께 반납된다.
// 2. **'입금했어요' 이후에는 입금기한이 지나도 아무것도 풀리지 않는다.**
//
// Firestore를 띄우지 않고 확인하려고 트랜잭션/DB는 기록만 하는 가짜를 쓴다 —
// 검증 대상은 "무엇을 쓰기로 결정했는가"이지 Firestore 자체가 아니다.

const assert = require('assert');
const flow = require('./depositFlow');
const rental = require('./placeReservationFlow');
const { buildPaymentInfo } = require('./paymentInfo');
const {
  applyBundleRelease,
  applySlotHold,
  isPaidBooking,
  buildApplicationDoc,
} = require('./packageBookings').__test;
const { becamePaid } = require('./memberManagement').__test;

const cases = [];
function test(name, fn) {
  cases.push([name, fn]);
}

const NOW = 1_700_000_000_000;
const HOUR = 3600000;

// ── 가짜 Firestore ───────────────────────────────────────────────────────────
// 경로 문자열과 쓰기 내용만 기록한다.

function fakeDb() {
  const make = (path) => ({
    path,
    doc: (id) => make(`${path}/${id}`),
    collection: (name) => make(`${path}/${name}`),
  });
  return { collection: (name) => make(name) };
}

function fakeTransaction() {
  const writes = [];
  return {
    writes,
    set: (ref, data, opts) => writes.push({ op: 'set', path: ref.path, data, opts }),
    update: (ref, data) => writes.push({ op: 'update', path: ref.path, data }),
    slotWrites: () => writes.filter((w) => w.path.includes('/reservationSlots/')),
    partyWrites: () => writes.filter((w) => /^parties\/[^/]+$/.test(w.path)),
    applicationWrites: () => writes.filter((w) => w.path.includes('/applications/')),
  };
}

/** 방 2칸을 잡고 있는 콤보 예약 한 건(시간제 두 구간이라고 보면 된다). */
function bookingWith(payment, status = rental.STATUS.confirmed) {
  return {
    placeId: 'place1',
    partyId: 'party1',
    requesterId: 'user1',
    gender: 'female',
    selectedRounds: [1, 2],
    reservationIds: ['slotA', 'slotB'],
    totalPrice: 150000,
    status,
    payment,
  };
}

/** 정원이 이미 1명 차 있는 파티(남녀무관 모드). */
const PARTY_DATA = {
  genderCapacityMode: 'unlimited',
  maxParticipants: 10,
  currentParticipants: 3,
  applicants: ['user1', 'other'],
};

function releaseHandle({ partyExists = true, applicationExists = true } = {}) {
  const db = fakeDb();
  const partyRef = db.collection('parties').doc('party1');
  return {
    db,
    release: {
      partyRef,
      partySnap: { exists: partyExists, data: () => PARTY_DATA },
      applicationRef: partyRef.collection('applications').doc('user1'),
      applicationExists,
    },
  };
}

// ── 1. 살아있는 상태들 — 슬롯도 정원도 유지된다 ──────────────────────────────

// 무통장입금은 호스트의 인증된 수취계좌가 있어야 성립한다(payoutAccounts.js).
const HOST_ACCOUNT = {
  bankName: '국민은행',
  accountNumber: '12345678901234',
  accountHolder: '홍길동',
};

test('승인대기 — 슬롯은 업주 응답 기한까지만 잡고, 정원은 그대로 유지', () => {
  const payment = buildPaymentInfo(
    { method: 'bank_transfer' },
    {
      amount: 150000,
      nowMs: NOW,
      requireApproval: true,
      useAtMs: NOW + 100 * HOUR,
      payoutAccount: HOST_ACCOUNT,
    },
  );
  assert.strictEqual(payment.status, flow.STATUS.awaitingApproval);
  const respondByMs = NOW + 12 * HOUR;
  const hold = rental.slotHoldOf(rental.STATUS.requested, payment, { respondByMs });
  assert.deepStrictEqual(hold, { status: 'pending', expiresAtMs: respondByMs });
  // 승인 전에는 입금 자체가 막힌다.
  assert.throws(() => flow.assertCanMarkSent(payment, { cancelled: false }), /승인/);
  // 이 구간에서 정원을 반납하는 경로는 없다(만료/거절 때만 반납된다).
  assert.strictEqual(flow.isExpirable(payment, NOW + 100 * HOUR), false);
});

test('승인 후 입금대기 — 슬롯은 입금기한까지, 정원은 유지', () => {
  const payment = {
    method: 'bank_transfer',
    status: flow.STATUS.awaitingDeposit,
    depositDeadlineMs: NOW + 24 * HOUR,
  };
  assert.deepStrictEqual(rental.slotHoldOf(rental.STATUS.confirmed, payment), {
    status: 'pending',
    expiresAtMs: NOW + 24 * HOUR,
  });
  // 기한이 지나야 비로소 만료 대상이 된다.
  assert.strictEqual(flow.isExpirable(payment, NOW + 23 * HOUR), false);
  assert.strictEqual(flow.isExpirable(payment, NOW + 25 * HOUR), true);
});

test('입금확인중 — 입금기한이 한참 지나도 슬롯·정원 모두 유지된다', () => {
  const payment = {
    method: 'bank_transfer',
    status: flow.STATUS.depositPending,
    depositDeadlineMs: NOW - HOUR, // 이미 지난 기한
  };
  // ① 슬롯 점유에서 기한이 사라진다(= 겹침 판정에서 영원히 자리를 지킨다).
  assert.deepStrictEqual(rental.slotHoldOf(rental.STATUS.confirmed, payment), {
    status: 'confirmed',
    expiresAtMs: null,
  });
  // ② 만료 스케줄러의 대상에서도 빠진다 → 정원 반납이 아예 호출되지 않는다.
  assert.strictEqual(flow.isExpirable(payment, NOW + 999 * HOUR), false);

  // ③ 실제로 슬롯에 쓰이는 값도 '기한 없음'인지 확인한다.
  const tx = fakeTransaction();
  applySlotHold(tx, fakeDb(), bookingWith(payment), rental.slotHoldOf(rental.STATUS.confirmed, payment));
  assert.strictEqual(tx.slotWrites().length, 2);
  for (const w of tx.slotWrites()) {
    assert.strictEqual(w.data.status, 'confirmed');
    assert.strictEqual(w.data.expiresAt, null, '입금확인중 슬롯에 만료 기한이 남으면 안 된다');
  }
});

test('입금완료 / 현장결제 확정 — 슬롯 기한 없음, 정원 유지', () => {
  for (const payment of [
    { method: 'bank_transfer', status: flow.STATUS.paid },
    { method: 'on_site', status: flow.STATUS.onSiteScheduled },
  ]) {
    assert.deepStrictEqual(rental.slotHoldOf(rental.STATUS.confirmed, payment), {
      status: 'confirmed',
      expiresAtMs: null,
    });
    assert.strictEqual(flow.isExpirable(payment, NOW + 999 * HOUR), false);
  }
});

// ── 2. 반납 경로 — 셋이 반드시 함께 풀린다 ───────────────────────────────────

test('업주 거절 — 슬롯·정원이 함께 반납된다(신청 문서는 아직 없음)', () => {
  const group = bookingWith(
    { method: 'bank_transfer', status: flow.STATUS.awaitingApproval },
    rental.STATUS.requested,
  );
  // 승인대기 구간에는 신청 문서가 만들어지기 전이다.
  const { db, release } = releaseHandle({ applicationExists: false });
  const tx = fakeTransaction();
  applyBundleRelease(tx, db, group, release, {
    slotStatus: 'cancelled',
    cancelledBy: 'host',
    cancelReason: 'rejected',
  });

  assert.strictEqual(tx.slotWrites().length, 2, '슬롯 2칸이 모두 반납돼야 한다');
  for (const w of tx.slotWrites()) assert.strictEqual(w.data.status, 'cancelled');
  assert.strictEqual(tx.partyWrites().length, 1, '파티 정원이 반드시 함께 반납돼야 한다');
  assert.strictEqual(tx.partyWrites()[0].data.currentParticipants, 2);
  assert.strictEqual(tx.applicationWrites().length, 0);
});

test('사용자 취소(입금완료 건) — 셋 다 반납되고 환불액이 신청 문서에 남는다', () => {
  const group = bookingWith({ method: 'bank_transfer', status: flow.STATUS.paid });
  assert.strictEqual(isPaidBooking(group), true, '결제완료 건이어야 환불을 계산한다');

  const { db, release } = releaseHandle();
  const tx = fakeTransaction();
  const refund = { refundPercent: 50, refundAmount: 75000, refundStatus: 'pending', matchedTier: { daysBefore: 7, refundPercent: 50 } };
  applyBundleRelease(tx, db, group, release, {
    slotStatus: 'cancelled',
    cancelledBy: 'user',
    cancelReason: 'cancelled',
    refund,
  });

  assert.strictEqual(tx.slotWrites().length, 2);
  assert.strictEqual(tx.partyWrites().length, 1);
  assert.strictEqual(tx.partyWrites()[0].data.currentParticipants, 2);
  const app = tx.applicationWrites()[0];
  assert.strictEqual(app.data.status, 'cancelled');
  assert.strictEqual(app.data.refundAmount, 75000);
});

test('입금 전 취소 — 받은 돈이 없으므로 환불을 계산하지 않는다', () => {
  // 확정(confirmed)이어도 입금대기·입금확인중·현장결제는 아직 받은 돈이 없다.
  for (const status of [
    flow.STATUS.awaitingDeposit,
    flow.STATUS.depositPending,
    flow.STATUS.onSiteScheduled,
  ]) {
    assert.strictEqual(
      isPaidBooking(bookingWith({ method: 'bank_transfer', status })),
      false,
      `${status}는 결제완료가 아니다`,
    );
  }
  // payment 맵이 없는 옛 포트원 건은 confirmed가 곧 결제완료였다.
  const legacy = bookingWith(undefined);
  delete legacy.payment;
  assert.strictEqual(isPaidBooking(legacy), true);

  const { db, release } = releaseHandle();
  const tx = fakeTransaction();
  applyBundleRelease(
    tx,
    db,
    bookingWith({ method: 'bank_transfer', status: flow.STATUS.awaitingDeposit }),
    release,
    { slotStatus: 'cancelled', cancelledBy: 'user', cancelReason: 'cancelled' },
  );
  const app = tx.applicationWrites()[0];
  assert.strictEqual(app.data.refundAmount, 0);
  assert.strictEqual(app.data.refundStatus, 'not_applicable');
});

test('승인기한 만료 — 슬롯·정원이 함께 반납된다', () => {
  const group = bookingWith(
    { method: 'bank_transfer', status: flow.STATUS.awaitingApproval },
    rental.STATUS.requested,
  );
  const { db, release } = releaseHandle({ applicationExists: false });
  const tx = fakeTransaction();
  applyBundleRelease(tx, db, group, release, {
    slotStatus: 'expired',
    cancelledBy: 'system',
    cancelReason: 'approval_timeout',
  });
  assert.strictEqual(tx.slotWrites().length, 2);
  for (const w of tx.slotWrites()) assert.strictEqual(w.data.status, 'expired');
  assert.strictEqual(tx.partyWrites().length, 1);
});

test('입금기한 만료 — 슬롯·정원·신청 문서가 함께 반납된다', () => {
  const group = bookingWith({
    method: 'bank_transfer',
    status: flow.STATUS.awaitingDeposit,
    depositDeadlineMs: NOW - HOUR,
  });
  assert.strictEqual(flow.isExpirable(group.payment, NOW), true);

  const { db, release } = releaseHandle();
  const tx = fakeTransaction();
  applyBundleRelease(tx, db, group, release, {
    slotStatus: 'expired',
    cancelledBy: 'system',
    cancelReason: 'deposit_expired',
  });
  assert.strictEqual(tx.slotWrites().length, 2);
  assert.strictEqual(tx.partyWrites().length, 1);
  assert.strictEqual(tx.partyWrites()[0].data.currentParticipants, 2);
  const app = tx.applicationWrites()[0];
  assert.strictEqual(app.data.status, 'cancelled');
  assert.strictEqual(app.data.cancelReason, 'deposit_expired');
});

test('반납은 언제나 슬롯과 정원을 함께 쓴다 — 어떤 사유든', () => {
  for (const reason of ['rejected', 'cancelled', 'approval_timeout', 'deposit_expired', 'payment_timeout']) {
    const { db, release } = releaseHandle();
    const tx = fakeTransaction();
    applyBundleRelease(tx, db, bookingWith({ method: 'bank_transfer', status: flow.STATUS.awaitingDeposit }), release, {
      slotStatus: 'cancelled',
      cancelledBy: 'system',
      cancelReason: reason,
    });
    assert.ok(tx.slotWrites().length > 0, `${reason}: 슬롯 반납 누락`);
    assert.strictEqual(tx.partyWrites().length, 1, `${reason}: 파티 정원 반납 누락`);
  }
});

// ── 3. 신청 문서 연결 필드 ───────────────────────────────────────────────────

test('콤보 신청 문서 — payment는 복사하지 않고 연결 필드만 남긴다', () => {
  const doc = buildApplicationDoc({
    uid: 'user1',
    partyId: 'party1',
    hostId: 'host1',
    gender: 'female',
    partyFee: 30000,
    partyData: { region: '서울', district: '마포', category: '와인' },
    partyDateTime: new Date(NOW),
    selectedRounds: [1, 2],
    bundleBookingId: 'bundle1',
  });

  // 결제 상태의 단일 진실 소스는 packageBookings 하나뿐이다 — 여기 복사되면
  // expirePartyDeposits가 파티 정원만 반납하는 경로가 열린다.
  assert.strictEqual(doc.payment, undefined, '신청 문서에 payment가 있으면 안 된다');
  // 대신 추적용 연결 필드로 언제나 진짜 결제 상태를 찾아갈 수 있어야 한다.
  assert.strictEqual(doc.source, 'combo');
  assert.strictEqual(doc.bundleBookingId, 'bundle1');
  // 나머지는 파티 단독 신청과 같은 shape.
  assert.strictEqual(doc.status, 'applied');
  assert.strictEqual(doc.appliedFee, 30000);
  assert.deepStrictEqual(doc.selectedRounds, [1, 2]);
});

// ── 4. 매출·정산 집계 기준 ───────────────────────────────────────────────────

test('매출은 payment.status가 paid로 넘어갈 때만 잡힌다', () => {
  const at = (paymentStatus, status = 'confirmed') => ({
    status,
    payment: { method: 'bank_transfer', status: paymentStatus },
  });

  // 자리 확정만으로는 매출이 아니다 — 아직 받은 돈이 없다.
  assert.strictEqual(
    becamePaid({ status: 'requested', payment: { status: flow.STATUS.awaitingApproval } }, at(flow.STATUS.awaitingDeposit)),
    false,
    '승인 후 입금대기는 매출이 아니다',
  );
  assert.strictEqual(
    becamePaid(at(flow.STATUS.awaitingDeposit), at(flow.STATUS.depositPending)),
    false,
    '입금확인중은 아직 대조 전이라 매출이 아니다',
  );
  assert.strictEqual(
    becamePaid(null, at(flow.STATUS.onSiteScheduled)),
    false,
    '현장결제 예정은 매출이 아니다',
  );

  // 업주가 입금을 확인한 순간에만 잡힌다.
  assert.strictEqual(
    becamePaid(at(flow.STATUS.depositPending), at(flow.STATUS.paid)),
    true,
  );
  // 그리고 딱 한 번만 — 이후 취소 등으로 문서가 또 써져도 다시 세지 않는다.
  assert.strictEqual(
    becamePaid(at(flow.STATUS.paid), at(flow.STATUS.paid, 'cancelled')),
    false,
    '같은 건이 두 번 매출로 잡히면 안 된다',
  );

  // payment 맵이 없는 옛 포트원 문서는 confirmed가 곧 결제완료였다.
  assert.strictEqual(becamePaid({ status: 'pending' }, { status: 'confirmed' }), true);
  assert.strictEqual(becamePaid({ status: 'confirmed' }, { status: 'cancelled' }), false);
});

// ── 5. 결제수단 노출 정책 ────────────────────────────────────────────────────

test('PG 수단은 콤보에서도 거절된다 — 무통장입금·현장결제만 통과', () => {
  for (const method of ['card', 'transfer', 'virtual_account', 'easy_pay']) {
    assert.throws(
      () => buildPaymentInfo({ method }, { amount: 150000, nowMs: NOW }),
      /준비 중/,
      `${method}로 콤보 예약이 만들어지면 안 된다`,
    );
  }
  for (const method of ['bank_transfer', 'on_site']) {
    assert.ok(
      buildPaymentInfo(
        { method },
        { amount: 150000, nowMs: NOW, payoutAccount: HOST_ACCOUNT },
      ),
    );
  }
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
    ? `\n콤보 예약 선점/반납 불변식 검증 통과 — ${cases.length}건`
    : `\n실패 ${failed}건 / 전체 ${cases.length}건`,
);
process.exit(failed === 0 ? 0 : 1);

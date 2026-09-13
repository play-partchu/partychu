// 통합 QR 체크인의 판정 확인 — `node checkInTokens.selfcheck.js`
//
// 현장에서 틀리면 손님을 돌려보내거나 공짜로 들여보내는 자리만 본다.
//   1. 결제 전에는 절대 통과하지 않는다(현장결제 포함).
//   2. 날짜가 다른 QR은 막고, 그 날짜를 말해 준다.
//   3. 이미 처리된 건은 "차단"이 아니라 "이미 처리됨"으로 보인다.
//   4. 결과 모양은 세 도메인이 같다 — 화면이 하나뿐이라서다.

const assert = require('assert');

const {
  DOMAIN,
  CHECK_IN_STATUS,
  voucherBlockReason,
  partyBlockReason,
  reservationBlockReason,
  paymentBlockReason,
  buildCheckInResult,
  emptyCheckInResult,
  paymentSummary,
  partyQrActive,
  reservationQrActive,
  attendanceDelta,
  productQrActive,
  PRODUCT_QR_DEAD_STATUSES,
} = require('./checkInRules');

const ts = (ms) => ({ toMillis: () => ms });
const DATE_BOUND = { dateBoundTypes: new Set(['seat', 'ticket']) };

// 2026-08-30 20:00 KST
const NOW = Date.UTC(2026, 7, 30, 11, 0);
const SAME_DAY = Date.UTC(2026, 7, 30, 3, 0); // 같은 날 12:00 KST
const NEXT_DAY = Date.UTC(2026, 7, 31, 11, 0);

// ── 1. 결제 전에는 통과하지 않는다 ──────────────────────────────────────────

assert.strictEqual(
  paymentBlockReason({ method: 'on_site', status: 'on_site_scheduled' }),
  '현장 결제가 아직 확인되지 않았어요.',
  '현장결제 미확인 건이 통과하면 공짜 입장이 된다',
);
assert.strictEqual(
  paymentBlockReason({ method: 'bank_transfer', status: 'awaiting_deposit' }),
  '입금이 아직 확인되지 않았어요.',
);
assert.strictEqual(
  paymentBlockReason({ method: 'bank_transfer', status: 'deposit_pending' }),
  '입금이 아직 확인되지 않았어요.',
  "'입금했어요'만으로는 통과하지 않는다 — 호스트가 대조해야 한다",
);
assert.strictEqual(
  paymentBlockReason({ method: 'on_site', status: 'paid' }),
  null,
);
// 결제 정보가 없는 건(무료·옛 PG)은 이 축에서 막지 않는다.
assert.strictEqual(paymentBlockReason(null), null);

// 세 도메인이 **같은 문장**을 쓴다 — 현장에서 말이 갈리면 안 된다.
const onSite = { method: 'on_site', status: 'on_site_scheduled' };
assert.strictEqual(
  voucherBlockReason(
    { status: 'usable', payment: onSite, productType: 'etc' },
    NOW,
    DATE_BOUND,
  ),
  '현장 결제가 아직 확인되지 않았어요.',
);
assert.strictEqual(
  partyBlockReason({ status: 'approved', payment: onSite, partyDateTime: ts(NOW) }, {}, NOW),
  '현장 결제가 아직 확인되지 않았어요.',
);
assert.strictEqual(
  reservationBlockReason({ status: 'approved', payment: onSite, visitAt: ts(NOW) }, NOW),
  '현장 결제가 아직 확인되지 않았어요.',
);

// ── 2. 날짜 ─────────────────────────────────────────────────────────────────

assert.strictEqual(
  partyBlockReason({ status: 'approved', partyDateTime: ts(SAME_DAY) }, {}, NOW),
  null,
  '같은 날이면 시각이 달라도 통과한다 — 일찍 온 손님을 돌려보내지 않는다',
);
assert.strictEqual(
  partyBlockReason({ status: 'approved', partyDateTime: ts(NEXT_DAY) }, {}, NOW),
  '오늘 파티가 아니에요 (2026-08-31).',
  '다른 날 QR은 막고 그 날짜를 말해 준다',
);
// 신청 문서에 일시가 없으면 파티 본문에서 읽는다.
assert.strictEqual(
  partyBlockReason({ status: 'approved' }, { dateTime: ts(NEXT_DAY) }, NOW),
  '오늘 파티가 아니에요 (2026-08-31).',
);

assert.strictEqual(
  reservationBlockReason({ status: 'approved', visitAt: ts(SAME_DAY) }, NOW),
  null,
);
assert.strictEqual(
  reservationBlockReason({ status: 'confirmed', visitAt: ts(NEXT_DAY) }, NOW),
  '예약일이 아니에요 (2026-08-31).',
);
// 숙박은 여러 날에 걸친다 — 구간 안이면 통과한다.
assert.strictEqual(
  reservationBlockReason(
    {
      status: 'confirmed',
      useStartAt: ts(Date.UTC(2026, 7, 29, 7, 0)),
      useEndAt: ts(Date.UTC(2026, 7, 31, 2, 0)),
    },
    NOW,
  ),
  null,
  '1박 이상 예약은 체크인 날부터 체크아웃 날까지 통과해야 한다',
);

// ── 3. 상태 ─────────────────────────────────────────────────────────────────

assert.strictEqual(
  partyBlockReason({ status: 'pending', partyDateTime: ts(NOW) }, {}, NOW),
  '아직 승인되지 않은 신청이에요.',
);
for (const s of ['cancelled', 'rejected', 'no_show']) {
  assert.ok(
    partyBlockReason({ status: s, partyDateTime: ts(NOW) }, {}, NOW),
    `${s}는 막혀야 한다`,
  );
}
assert.strictEqual(
  reservationBlockReason({ status: 'requested', visitAt: ts(NOW) }, NOW),
  '아직 승인되지 않은 예약이에요.',
);
for (const s of ['cancelled_by_guest', 'cancelled_by_host', 'cancelled', 'rejected', 'expired']) {
  assert.ok(
    reservationBlockReason({ status: s, visitAt: ts(NOW) }, NOW),
    `${s}는 막혀야 한다`,
  );
}

// ── 4. 결과 모양 ────────────────────────────────────────────────────────────

const identity = {
  available: true,
  verified: true,
  name: '박파티',
  nickname: '파티러',
  gender: 'male',
  birthYear: 1991,
  birthMonth: 3,
  birthDay: 2,
};

const ready = buildCheckInResult({
  domain: DOMAIN.party,
  identity,
  core: { title: '루프탑 파티', atMs: NOW, people: 1 },
});
assert.strictEqual(ready.ok, true);
assert.strictEqual(ready.checkInStatus, CHECK_IN_STATUS.ready);
assert.strictEqual(ready.blockReason, null);

// 나이는 서버가 계산하지 않는다 — 해가 바뀌면 틀린 값이 문서에 남는다.
assert.ok(!('age' in ready.guest), '나이를 실어 보내면 안 된다');
assert.strictEqual(ready.guest.name, '박파티');

const blocked = buildCheckInResult({
  domain: DOMAIN.voucher,
  identity,
  core: { title: '테스트 매장' },
  blockReason: '현장 결제가 아직 확인되지 않았어요.',
});
assert.strictEqual(blocked.ok, false);
assert.strictEqual(blocked.checkInStatus, CHECK_IN_STATUS.blocked);

// 이미 처리된 건은 차단 사유가 함께 있어도 '이미 처리됨'으로 보인다 —
// 호스트가 알아야 하는 것은 "다시 찍어도 소용없다"이다.
const done = buildCheckInResult({
  domain: DOMAIN.voucher,
  identity,
  core: { title: '테스트 매장', checkedInAtMs: NOW },
  blockReason: '이미 사용한 이용권이에요.',
  alreadyDone: true,
});
assert.strictEqual(done.checkInStatus, CHECK_IN_STATUS.done);
assert.strictEqual(done.ok, false);
assert.strictEqual(done.checkedInAtMs, NOW);

// 세 도메인이 같은 키를 돌려준다 — 화면이 하나뿐이라 모양이 갈리면 안 된다.
const keys = (r) => Object.keys(r).sort().join(',');
const reservationResult = buildCheckInResult({
  domain: DOMAIN.reservation,
  identity,
  core: { title: '파티룸', people: 4 },
});
assert.strictEqual(keys(ready), keys(reservationResult));
assert.strictEqual(keys(ready), keys(blocked));

// 결제 요약에는 계좌가 실리지 않는다.
const summary = paymentSummary({
  method: 'bank_transfer',
  status: 'awaiting_deposit',
  amount: 20000,
  accountNumber: '3333-01-1234567',
  accountHolder: '홍길동',
  depositorName: '박파티',
});
assert.deepStrictEqual(summary, {
  paymentMethod: 'bank_transfer',
  paymentStatus: 'awaiting_deposit',
  paymentAmount: 20000,
});

// 결제 확인 버튼은 기본으로 닫혀 있다 — 켜는 것은 서버가 결제 상태를 보고 정한다.
assert.strictEqual(ready.canConfirmPayment, false);
assert.strictEqual(
  buildCheckInResult({
    domain: DOMAIN.voucher,
    identity,
    core: { title: '테스트 매장' },
    blockReason: '현장 결제가 아직 확인되지 않았어요.',
    canConfirmPayment: true,
  }).canConfirmPayment,
  true,
);

// ── 6. QR이 애초에 존재해야 하는가 ──────────────────────────────────────────
//
// 위(1~5)가 "지금 이 QR로 들어갈 수 있나"라면 여기는 "QR이 있어야 하나"다.
// 발급·무효화 트리거가 이 판정 하나만 보고 움직인다. 실제 발급 흐름(멱등성·
// 취소 후 재승인 등)은 checkInIssue.selfcheck.js가 가짜 Firestore로 돌린다.

// 승인 전에는 QR이 없다.
assert.strictEqual(partyQrActive({ status: 'pending' }), false);
assert.strictEqual(partyQrActive({ status: 'rejected' }), false);
assert.strictEqual(partyQrActive({ status: 'cancelled' }), false);
assert.strictEqual(partyQrActive({ status: 'no_show' }), false);
assert.strictEqual(partyQrActive(null), false);
// 승인제 승인과 즉시확정 접수는 둘 다 "자리가 확정됨"이다.
assert.strictEqual(partyQrActive({ status: 'approved' }), true);
assert.strictEqual(
  partyQrActive({ status: 'applied' }),
  true,
  '즉시확정 파티는 approved가 되지 않는다 — 빠지면 그 파티 참가자는 QR을 영영 못 받는다',
);

// 예약은 컬렉션마다 확정을 뜻하는 단어가 다르다.
assert.strictEqual(
  reservationQrActive('placeVisitReservations', { status: 'approved' }),
  true,
);
assert.strictEqual(
  reservationQrActive('placeVisitReservations', { status: 'requested' }),
  false,
);
assert.strictEqual(
  reservationQrActive('placeReservationGroups', { status: 'confirmed' }),
  true,
);
assert.strictEqual(
  reservationQrActive('placeReservationGroups', { status: 'approved' }),
  false,
  "장소대여의 확정은 'confirmed'다 — 단어를 섞으면 QR이 안 나온다",
);
assert.strictEqual(
  reservationQrActive('packageBookings', { status: 'confirmed' }),
  true,
);
for (const dead of ['cancelled', 'cancelled_by_guest', 'rejected', 'expired']) {
  assert.strictEqual(
    reservationQrActive('placeReservationGroups', { status: dead }),
    false,
    `${dead} 예약의 QR이 살아 있으면 취소가 뜻을 잃는다`,
  );
}
// 표에 없는 컬렉션은 발급하지 않는다.
assert.strictEqual(reservationQrActive('placeBookings', { status: 'confirmed' }), false);
assert.strictEqual(reservationQrActive('placeReservationGroups', null), false);

// ── 7. 출석 집계는 checkedInAt의 **차분**으로 움직인다 ──────────────────────
//
// 'attended' 상태는 더 이상 아무도 쓰지 않는다. 체크인은 되돌릴 수 있으므로
// "+1"이 아니라 켜짐/꺼짐의 차분이어야 하고, 그래야 되돌리기가 정확히 역산된다.

const stamp = ts(NOW);
assert.strictEqual(attendanceDelta(null, { status: 'approved' }), 0);
assert.strictEqual(attendanceDelta({}, { checkedInAt: stamp }), 1, '체크인은 +1');
assert.strictEqual(attendanceDelta({ checkedInAt: stamp }, {}), -1, '되돌리기는 -1');
assert.strictEqual(
  attendanceDelta({ checkedInAt: stamp }, { checkedInAt: stamp }),
  0,
  '체크인 뒤의 다른 쓰기가 출석을 또 세면 안 된다',
);
assert.strictEqual(
  attendanceDelta({ checkedInAt: stamp }, { checkedInAt: ts(NOW + 1000) }),
  0,
  '시각만 바뀐 쓰기는 새 출석이 아니다',
);

// ── 8. 없는 QR·죽은 QR·남의 QR은 아무것도 알려주지 않는다 ──────────────────
//
// 셋을 구분해 주면 남의 QR을 주운 사람이 그 차이만으로 무언가를 알게 된다.
// 사유 문장만 다르고 개인정보는 한 칸도 실리지 않아야 한다.

const denied = emptyCheckInResult('이 QR을 확인할 권한이 없어요.');
assert.deepStrictEqual(denied, {
  ok: false,
  domain: null,
  checkInStatus: CHECK_IN_STATUS.blocked,
  blockReason: '이 QR을 확인할 권한이 없어요.',
  guest: null,
});
// 응답 어디에도 신원·제목·일시·금액이 없다 — 키 자체가 없어야 한다.
for (const leaked of [
  'title',
  'subtitle',
  'atMs',
  'endAtMs',
  'people',
  'quantity',
  'purchasedItem',
  'paymentAmount',
  'paymentMethod',
  'checkedInAtMs',
  'detail',
]) {
  assert.ok(
    !(leaked in denied),
    `남의 QR 응답에 ${leaked}이 실리면 주운 QR로 남의 이용을 들여다볼 수 있다`,
  );
}

// ── 9. 옛 이용권 판정은 통합 스캐너와 **같은 함수**다 ──────────────────────
//
// 기존 앱이 부르는 redeemProductVoucher가 그대로 남아 있어도, 판정이 두 벌이
// 되면 같은 이용권이 스캐너에 따라 다르게 막힌다.
const legacyVoucher = require('./placeProductOrders').__test;
const sample = { status: 'usable', productType: 'etc', payment: null };
assert.strictEqual(
  legacyVoucher.redeemBlockReason(sample, NOW),
  voucherBlockReason(sample, NOW, {
    dateBoundTypes: legacyVoucher.DATE_BOUND_TYPES,
  }),
  '옛 콜러블과 통합 스캐너의 판정이 갈리면 현장에서 무엇이 맞는지 알 수 없다',
);
assert.strictEqual(
  legacyVoucher.redeemBlockReason(
    { status: 'usable', productType: 'etc', payment: onSite },
    NOW,
  ),
  '현장 결제가 아직 확인되지 않았어요.',
  '현장결제 미확인 이용권은 옛 경로에서도 통과하면 안 된다',
);

// ── 10. 스캔·사용 처리가 파티 신청 상태를 건드리지 않는다 ──────────────────
//
// 파티는 approved를 그대로 두고 checkedInAt만 찍는다. 여기서 status를 바꾸면
// 승인 통계가 출석과 뒤엉키고, 되돌리기가 "무슨 상태로" 돌아갈지 알 수 없어진다.
const consumers = require('./checkInTokens').__test.CONSUMERS;

const partyPatch = consumers[DOMAIN.party]({ status: 'approved' }).patch;
assert.deepStrictEqual(
  Object.keys(partyPatch).sort(),
  ['checkedInAt', 'checkedInBy'],
  '파티 체크인이 status를 건드리면 승인 통계와 출석 통계가 뒤엉킨다',
);
assert.strictEqual(
  consumers[DOMAIN.party]({ status: 'approved', checkedInAt: ts(NOW) }).already,
  true,
  '이미 찍힌 QR을 또 찍으면 "이미 처리됨"이어야 한다',
);

// 예약도 같다 — 확정 상태는 그대로 두고 체크인 흔적만 남긴다.
assert.deepStrictEqual(
  Object.keys(consumers[DOMAIN.reservation]({ status: 'confirmed' }).patch).sort(),
  ['checkedInAt', 'checkedInBy'],
);

// 이용권만 예외다 — 재고·매출이 status에 걸려 있어 예전 그대로 소진시킨다.
assert.deepStrictEqual(
  Object.keys(consumers[DOMAIN.voucher]({ status: 'usable' }).patch).sort(),
  ['status', 'usedAt', 'usedBy'],
);
assert.strictEqual(consumers[DOMAIN.voucher]({ status: 'used' }).already, true);

// ── 11. 상품 QR — checkInToken과 voucherCode의 역할은 섞이지 않는다 ─────────
//
// checkInToken은 "이 이용 건을 조회하기 위한 식별자"이고 voucherCode는 "돈이
// 들어왔고 쓸 수 있다"는 뜻이다. 전자를 결제 증명처럼 다루면 결제 없이 통과하는
// 길이 열린다 — 아래 두 가지가 그 경계다.

// (1) 현장결제 주문은 결제 전에도 QR을 갖는다 — 조회만 열린 것이다.
const onSitePending = {
  useQrCheck: true,
  status: 'payment_pending',
  payment: { method: 'on_site', status: 'on_site_scheduled' },
};
assert.strictEqual(productQrActive(onSitePending), true, '현장결제는 결제 전에도 QR이 있어야 한다');

// (2) 그런데 **통과는 막힌다.** 판정은 결제 상태를 다시 본다.
assert.strictEqual(
  voucherBlockReason(onSitePending, NOW, DATE_BOUND),
  '결제가 완료되지 않은 주문이에요.',
  'QR이 있다고 통과되면 공짜 입장이 된다',
);
// 결제만 끝나고 아직 usable이 아닌 순간도 막힌다.
assert.strictEqual(
  voucherBlockReason(
    { ...onSitePending, status: 'paid', payment: { method: 'on_site', status: 'paid' } },
    NOW,
    DATE_BOUND,
  ),
  '아직 사용할 수 없는 이용권이에요.',
);
// 결제 확인이 끝나 usable이 되어야 통과한다.
assert.strictEqual(
  voucherBlockReason(
    { useQrCheck: true, status: 'usable', productType: 'etc', payment: { method: 'on_site', status: 'paid' } },
    NOW,
    DATE_BOUND,
  ),
  null,
);

// (3) 무통장입금은 결제 전에도 후에도 checkInToken을 만들지 않는다.
for (const status of ['awaiting_deposit', 'deposit_pending', 'paid']) {
  assert.strictEqual(
    productQrActive({
      useQrCheck: true,
      status: status === 'paid' ? 'usable' : 'payment_pending',
      payment: { method: 'bank_transfer', status },
    }),
    false,
    `무통장입금(${status})에 사전 QR을 주면 기존 정책이 흔들린다`,
  );
}

// (4) 죽는 상태는 취소·환불·만료뿐이다. 'used'는 살려 둬야 "이미 사용함"이라고
//     답할 수 있다.
for (const dead of [...PRODUCT_QR_DEAD_STATUSES]) {
  assert.strictEqual(
    productQrActive({ useQrCheck: true, status: dead, payment: { method: 'on_site' } }),
    false,
  );
}
assert.strictEqual(
  productQrActive({ useQrCheck: true, status: 'used', payment: { method: 'on_site' } }),
  true,
  "'used' 토큰을 죽이면 재스캔이 '없는 QR'로 보여 호스트가 상황을 알 수 없다",
);

console.log('✅ checkInTokens.selfcheck 통과');

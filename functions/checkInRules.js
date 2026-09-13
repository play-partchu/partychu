/**
 * 통합 QR 체크인의 **판정과 결과 조립** — 순수 함수만 모은다.
 *
 * 발급·조회·사용·되돌리기 전체 계약은 docs/checkin_qr_contract.md 에 한 장으로
 * 정리돼 있다. 이 파일의 판정을 고칠 때는 그 문서도 함께 본다.
 *
 * ── 왜 규칙을 여기 모으나 ───────────────────────────────────────────────────
 * 호스트에게 스캐너는 하나뿐이어야 한다. 그런데 뒤에 붙는 도메인은 셋이다:
 *
 *   · party             — 파티 신청 1건(parties/{id}/applications/{uid})
 *   · place_reservation — 방문예약 / 장소대여·패키지 예약
 *   · product_voucher   — 상품·이용권 주문(placeProductOrders)
 *
 * 같은 QR을 두 경로가 서로 다르게 막으면(한쪽은 통과, 한쪽은 거절) 현장에서
 * 무엇이 맞는지 알 수 없다. 그래서 **차단 사유도 결과 모양도 이 파일 하나**가
 * 정하고, 기존 상품 이용권 판정(redeemBlockReason)도 여기로 옮겨 왔다 —
 * placeProductOrders.js가 이 파일을 읽어 쓰므로 두 벌이 될 수 없다.
 *
 * ── 이 파일이 하지 않는 것 ─────────────────────────────────────────────────
 * Firestore를 읽지 않고, 권한도 보지 않고, 상태도 바꾸지 않는다. 전부
 * checkInTokens.js가 한다. 그래서 이 파일은 self-check로 전수 확인할 수 있다.
 *
 * ── 개인정보 ───────────────────────────────────────────────────────────────
 * 게스트 정보는 buildApplicantIdentity가 만든 것을 **그대로** 싣는다 —
 * 본인확인을 마친 계정의 실명·성별·생년월일뿐이고, 전화번호·CI는 애초에 그
 * 함수에 들어 있지 않다. 나이는 계산하지 않는다(해가 바뀌면 틀린다 — 화면이
 * ApplicantIdentity.ageAt()으로 그린다).
 */

const { isSameKstDay, kstDateStr } = require('./kstTime');
const flow = require('./depositFlow');

/** QR 하나가 가리키는 이용의 종류. 저장값이므로 변경 금지. */
const DOMAIN = {
  party: 'party',
  reservation: 'place_reservation',
  voucher: 'product_voucher',
};

/** 체크인 진행 상태 — 화면이 버튼을 열지 잠글지 정하는 축. */
const CHECK_IN_STATUS = {
  // 아직 안 찍음 — 사용 처리 가능(차단 사유가 없다면).
  ready: 'ready',
  // 이미 체크인/사용 완료.
  done: 'done',
  // 지금은 쓸 수 없음(결제 전·날짜 아님·취소됨 …).
  blocked: 'blocked',
};

function tsToMs(ts) {
  if (!ts) return null;
  if (typeof ts.toMillis === 'function') return ts.toMillis();
  if (ts instanceof Date) return ts.getTime();
  if (typeof ts === 'number') return ts;
  return null;
}

/**
 * 결제가 아직 안 끝났으면 그 사유 — 세 도메인이 **같은 말**을 쓴다.
 *
 * 결제수단과 QR을 분리하기 위한 자리다: 현장결제 건도 스캔해서 정보는 볼 수
 * 있어야 하고(그래야 호스트가 얼마를 받을지 안다), 사용 처리만 막힌다.
 */
function paymentBlockReason(payment) {
  if (!payment || flow.isPaid(payment)) return null;
  return payment.method === 'on_site'
    ? '현장 결제가 아직 확인되지 않았어요.'
    : '입금이 아직 확인되지 않았어요.';
}

// ── 1. 도메인별 차단 사유 ───────────────────────────────────────────────────

/**
 * 상품·이용권의 사용 처리를 막아야 하는 이유 — 없으면 null.
 *
 * 원래 placeProductOrders.js에 있던 redeemBlockReason 그대로다(그 파일이 이제
 * 여기서 읽어 간다). 규칙은 한 줄도 바꾸지 않았다 — 옮기기만 했다.
 */
function voucherBlockReason(order, nowMs, { dateBoundTypes }) {
  const status = order.status;
  if (status === 'used') return '이미 사용한 이용권이에요.';
  if (status === 'cancelled') return '취소된 이용권이에요.';
  if (status === 'refunded') return '환불된 이용권이에요.';
  if (status === 'expired') return '기간이 만료된 이용권이에요.';
  if (status === 'payment_pending') return '결제가 완료되지 않은 주문이에요.';

  // ── 돈이 실제로 들어왔는지 다시 본다 (마지막 방어선) ─────────────────────
  // 위의 status 검사는 "주문이 어디까지 갔나"이고, 이건 "돈이 들어왔나"다.
  // 두 축이 갈라진 뒤로는 status만 믿으면 안 된다 — 입금대기·입금확인중·
  // 현장결제 예정인 건은 어떤 이유로 코드가 먼저 생겼더라도 통과시키지 않는다.
  // (결제 정보가 없는 건은 옛 PG 흐름이라 PortOne 검증이 이미 끝난 주문이다.)
  const payBlock = paymentBlockReason(order.payment);
  if (payBlock) return payBlock;

  const startMs = tsToMs(order.useStartAt);
  if (startMs !== null && nowMs < startMs) {
    return '아직 이용 시작일이 되지 않았어요.';
  }
  const endMs = tsToMs(order.useEndAt);
  if (endMs !== null && nowMs > endMs) {
    return '이용 기간이 지난 이용권이에요.';
  }

  // 좌석 예약·입장권처럼 일시를 지정해 산 상품은 그 날짜가 맞는지까지 본다.
  // 하루 단위로 비교한다 — 분 단위로 막으면 조금 일찍 온 손님을 돌려보내게
  // 되고, 그건 현장에서 사장님이 판단할 몫이다.
  if (dateBoundTypes.has(order.productType) && order.useAt) {
    const useAtMs = tsToMs(order.useAt);
    if (useAtMs !== null && !isSameKstDay(useAtMs, nowMs)) {
      return `이용 예정일이 아니에요 (${kstDateStr(useAtMs)}).`;
    }
  }

  // 여기까지 왔는데 usable이 아니면(=paid) 이용 시작 전이라는 뜻이다.
  if (status !== 'usable') return '아직 사용할 수 없는 이용권이에요.';
  return null;
}

/**
 * 파티 신청의 체크인을 막아야 하는 이유 — 없으면 null.
 *
 * 파티는 상품과 달리 **status를 바꾸지 않는다**(approved를 그대로 두고
 * checkedInAt만 찍는다). 그래서 "이미 찍었나"는 status가 아니라 그 필드로
 * 본다 — 이 함수는 그 판정에 끼지 않는다.
 */
function partyBlockReason(app, party, nowMs) {
  const status = app.status;
  if (status === 'cancelled') return '취소된 신청이에요.';
  if (status === 'rejected') return '거절된 신청이에요.';
  if (status === 'no_show') return '노쇼 처리된 신청이에요.';
  // 승인제 파티에서 아직 승인 전이면 입장시킬 근거가 없다.
  if (status === 'pending') return '아직 승인되지 않은 신청이에요.';

  const payBlock = paymentBlockReason(app.payment);
  if (payBlock) return payBlock;

  // 파티 날짜 — 하루 단위로만 본다(상품과 같은 이유).
  const startMs = tsToMs(app.partyDateTime) ?? tsToMs(party && party.dateTime);
  if (startMs !== null && !isSameKstDay(startMs, nowMs)) {
    return `오늘 파티가 아니에요 (${kstDateStr(startMs)}).`;
  }
  return null;
}

/** 예약(방문·장소대여·패키지)의 체크인을 막아야 하는 이유 — 없으면 null. */
function reservationBlockReason(reservation, nowMs) {
  const status = reservation.status;
  if (status === 'rejected') return '거절된 예약이에요.';
  if (status === 'expired') return '기한이 만료된 예약이에요.';
  if (
    status === 'cancelled' ||
    status === 'cancelled_by_guest' ||
    status === 'cancelled_by_host'
  ) {
    return '취소된 예약이에요.';
  }
  if (status === 'requested') return '아직 승인되지 않은 예약이에요.';
  if (status === 'pending') return '결제가 완료되지 않은 예약이에요.';

  const payBlock = paymentBlockReason(reservation.payment);
  if (payBlock) return payBlock;

  // 예약 일시 — 숙박은 여러 날에 걸치므로 시작~종료 구간으로 본다.
  const startMs = tsToMs(reservation.visitAt) ?? tsToMs(reservation.useStartAt);
  const endMs = tsToMs(reservation.useEndAt);
  if (startMs === null) return null;
  if (endMs !== null && endMs > startMs) {
    const beforeStart = nowMs < startMs && !isSameKstDay(startMs, nowMs);
    const afterEnd = nowMs > endMs && !isSameKstDay(endMs, nowMs);
    if (beforeStart || afterEnd) {
      return `예약일이 아니에요 (${kstDateStr(startMs)}).`;
    }
    return null;
  }
  if (!isSameKstDay(startMs, nowMs)) {
    return `예약일이 아니에요 (${kstDateStr(startMs)}).`;
  }
  return null;
}

// ── 1-b. QR을 가져야 하는가 (발급·무효화의 기준) ────────────────────────────
//
// 위의 차단 사유가 "지금 이 QR로 들어갈 수 있나"라면, 여기는 "애초에 QR이
// 존재해야 하나"다. 두 축을 갈라 두는 이유:
//
//   · 현장결제 예약도 QR은 있어야 한다 — 호스트가 스캔해서 누가 왔는지 보고
//     그 자리에서 돈을 받는다. 통과만 막히고 조회는 되어야 한다.
//   · 반대로 취소·거절된 건은 조회조차 되면 안 된다 — 토큰 자체를 죽인다.
//
// 순수 함수라 self-check가 전수로 확인한다(checkInTokens.selfcheck.js).

/**
 * **자리가 확정된** 파티 신청의 상태.
 *
 * 'approved'는 승인제 파티에서 호스트가 승인했거나 입금이 확인된 상태다.
 * 'applied'가 함께 들어 있는 것은 즉시확정 파티 때문이다 — 그 파티에는 승인
 * 단계 자체가 없어 '접수 = 자리 확정'이고(index.js applyToParty의
 * `status: requireApproval ? 'pending' : 'applied'`), 여기서 빼면 즉시확정
 * 파티 참가자에게는 QR이 영영 발급되지 않는다.
 *
 * 'pending'(승인 대기)은 들어 있지 않다 — 승인 전에 입장시킬 근거가 없고,
 * partyBlockReason도 같은 이유로 그 상태를 막는다.
 */
const PARTY_QR_STATUSES = new Set(['approved', 'applied']);

/** 이 파티 신청이 지금 유효한 입장 QR을 가져야 하는가. */
function partyQrActive(app) {
  if (!app) return false;
  return PARTY_QR_STATUSES.has(app.status);
}

/**
 * 예약이 **확정**을 뜻하는 상태 — 컬렉션마다 단어가 다르다.
 *
 * 방문예약은 'approved'(업주 승인), 장소대여·패키지는 'confirmed'(자리 확정)다.
 * 여기 없는 컬렉션은 QR을 발급하지 않는다 — 새 예약 도메인이 생겼는데 이 표에
 * 넣는 걸 잊으면 QR이 안 나올 뿐, 엉뚱한 QR이 나오지는 않는다.
 */
const RESERVATION_QR_STATUS = {
  placeVisitReservations: 'approved',
  placeReservationGroups: 'confirmed',
  packageBookings: 'confirmed',
};

/** 이 예약이 지금 유효한 QR을 가져야 하는가. */
function reservationQrActive(collection, doc) {
  if (!doc) return false;
  const confirmed = RESERVATION_QR_STATUS[collection];
  if (!confirmed) return false;
  return doc.status === confirmed;
}

/**
 * 상품 주문이 **통합 QR 식별자**를 가져야 하는가.
 *
 * ── checkInToken과 voucherCode는 다른 것이다 ────────────────────────────────
 *   · checkInToken  이 이용 건을 안전하게 조회하기 위한 QR 식별자. 결제 증명이
 *                   아니다. 그래서 **현장결제 주문은 돈이 들어오기 전에도** 갖는다.
 *   · voucherCode   결제가 확인된 뒤에 생기는 이용권 코드. 의미는 그대로다
 *                   (voucherIssue.js가 유일한 발급 지점).
 *
 * 왜 현장결제만 미리 주는가: 현장결제는 "손님이 와서 QR을 보여주고, 호스트가
 * 누가 무엇을 사러 왔는지 확인한 뒤 돈을 받는" 흐름이다. QR이 없으면 그 첫
 * 걸음이 성립하지 않는다. 무통장입금은 돈이 계좌에서 확인되므로 사전 스캔이
 * 필요 없고, 입금 전에는 QR을 아예 노출하지 않는 지금 정책을 그대로 둔다.
 *
 * **조회가 열린다고 통과가 열리는 것은 아니다.** 결제 전 사용 처리는
 * voucherBlockReason이 그대로 막는다(paymentBlockReason → status !== 'usable').
 */

/** QR을 죽여야 하는 주문 상태 — 되살아날 일이 없는 것들. */
const PRODUCT_QR_DEAD_STATUSES = new Set(['cancelled', 'refunded', 'expired']);

function productQrActive(order) {
  if (!order) return false;
  // QR을 쓰지 않는 상품은 애초에 스캔 대상이 아니다.
  if (order.useQrCheck !== true) return false;
  if (PRODUCT_QR_DEAD_STATUSES.has(order.status)) return false;
  // 'used'는 살려 둔다 — 죽이면 다시 찍었을 때 "이미 사용한 이용권"이 아니라
  // "없는 QR"로 보여서, 호스트가 무슨 일이 있었는지 알 수 없다.
  return !!order.payment && order.payment.method === 'on_site';
}

// ── 1-c. 출석 집계 (checkedInAt이 정본) ─────────────────────────────────────
//
// 'attended' 상태는 더 이상 아무도 쓰지 않는다(그 값을 쓰는 코드가 서버·앱
// 어디에도 없다). 실제 현장 출석의 정본은 **체크인 시각**이고, 되돌리기가
// 있으므로 집계는 "켜졌다/꺼졌다"의 차분으로 움직여야 한다.

/**
 * 이번 쓰기가 출석 카운터를 얼마나 움직여야 하는가.
 *
 *   null → 시각 : +1 (체크인)
 *   시각 → null : -1 (체크인 되돌리기)
 *   그 밖       :  0 (토큰 기록 등 다른 필드만 바뀐 쓰기)
 *
 * 시각 → 다른 시각도 0이다 — 이미 한 번 센 출석을 다시 세지 않는다.
 */
function attendanceDelta(before, after) {
  const had = tsToMs(before && before.checkedInAt) !== null;
  const has = tsToMs(after && after.checkedInAt) !== null;
  if (had === has) return 0;
  return has ? 1 : -1;
}

// ── 2. 공용 결과 DTO ────────────────────────────────────────────────────────

/**
 * 호스트 화면이 그리는 **하나의 결과 모양**.
 *
 * 유형이 무엇이든 상단은 같다(누가 왔나) — 그래야 스캐너가 하나로 유지된다.
 * 유형별로만 다른 값은 detail에 담고, 화면은 있는 줄만 그린다.
 */
function buildCheckInResult({
  domain,
  identity,
  core,
  blockReason = null,
  alreadyDone = false,
  canConfirmPayment = false,
}) {
  // 이미 끝난 건이 먼저다 — "이미 사용됨"과 "지금은 못 씀"이 겹칠 때 호스트가
  // 알아야 하는 것은 전자다(다시 찍어도 소용없다는 뜻이므로).
  const status = alreadyDone
    ? CHECK_IN_STATUS.done
    : blockReason
      ? CHECK_IN_STATUS.blocked
      : CHECK_IN_STATUS.ready;
  return {
    ok: status === CHECK_IN_STATUS.ready,
    domain,
    checkInStatus: status,
    blockReason: blockReason || null,
    // 게스트 — 나이는 넣지 않는다(화면이 생년월일로 계산한다).
    guest: identity,
    title: core.title || '',
    subtitle: core.subtitle || '',
    atMs: core.atMs ?? null,
    endAtMs: core.endAtMs ?? null,
    people: core.people ?? null,
    quantity: core.quantity ?? null,
    purchasedItem: core.purchasedItem || '',
    paymentMethod: core.paymentMethod || null,
    paymentStatus: core.paymentStatus || null,
    paymentAmount: core.paymentAmount ?? null,
    checkedInAtMs: core.checkedInAtMs ?? null,
    // 이 화면에서 곧바로 현장결제·입금을 확인할 수 있는가 — 확인하면 그 순간
    // 이용권이 발급되고 사용 처리가 열린다(confirmCheckInPayment).
    canConfirmPayment,
    detail: core.detail || {},
  };
}

/**
 * **아무것도 알려주지 않는** 결과 — 없는 QR, 죽은 QR, 남의 QR.
 *
 * 셋을 같은 모양으로 돌려주는 이유: 남의 QR을 주워 서버에 물어보는 사람에게
 * "이건 존재하지만 네 것이 아니다"라고 답하면 그 자체가 정보다. 사유 문장만
 * 다르고 게스트 신원·제목·일시·금액은 **한 칸도 싣지 않는다**.
 *
 * 순수 함수로 떼어 둔 덕에 self-check가 "정말 아무것도 안 실렸는지"를 전수로
 * 확인할 수 있다 — 나중에 필드가 하나 늘 때 여기 빠뜨리면 바로 걸린다.
 */
function emptyCheckInResult(reason) {
  return {
    ok: false,
    domain: null,
    checkInStatus: CHECK_IN_STATUS.blocked,
    blockReason: reason,
    guest: null,
  };
}

/**
 * 결제 맵에서 화면이 쓰는 값만 꺼낸다.
 *
 * 계좌번호·예금주·입금자명은 **넣지 않는다** — 체크인 화면은 "얼마를 어떤
 * 수단으로 받아야 하나"만 알면 되고, 계좌는 구매자에게 안내된 값이지 호스트가
 * 현장에서 볼 값이 아니다.
 */
function paymentSummary(payment) {
  if (!payment) {
    return { paymentMethod: null, paymentStatus: null, paymentAmount: null };
  }
  return {
    paymentMethod: payment.method || null,
    paymentStatus: payment.status || null,
    paymentAmount: typeof payment.amount === 'number' ? payment.amount : null,
  };
}

module.exports = {
  DOMAIN,
  CHECK_IN_STATUS,
  PARTY_QR_STATUSES,
  RESERVATION_QR_STATUS,
  PRODUCT_QR_DEAD_STATUSES,
  partyQrActive,
  reservationQrActive,
  productQrActive,
  attendanceDelta,
  voucherBlockReason,
  partyBlockReason,
  reservationBlockReason,
  paymentBlockReason,
  buildCheckInResult,
  emptyCheckInResult,
  paymentSummary,
  tsToMs,
};

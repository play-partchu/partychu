const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');
const crypto = require('crypto');

const { verifyPortOnePayment } = require('./portOne');
const { logScheduledFunctionError } = require('./memberActivityHelpers');
// 결제수단·결제상태는 다른 도메인과 **같은 규칙**을 쓴다(수단은 앱이 고르고
// 상태는 서버가 정한다). 전이 규칙도 depositFlow 하나를 공유한다.
const { buildPaymentInfo } = require('./paymentInfo');
// 호스트 수취계좌 — 무통장입금 안내 계좌는 이 값 하나에서만 나온다.
const { loadPayoutSnapshot } = require('./payoutAccounts');
const flow = require('./depositFlow');
// 통합 QR 체크인과 **같은 판정**을 쓴다 — 스캐너가 하나뿐이어도, 옛 앱이 부르는
// redeemProductVoucher와 새 체크인이 다른 규칙으로 막으면 안 된다.
const rules = require('./checkInRules');
const { isSameKstDay, kstDateStr } = require('./kstTime');
// 이용권 코드가 생기는 유일한 지점 — 통합 QR 체크인의 현장결제 확인도 같은
// 함수를 쓴다(voucherIssue.js 상단 주석).
const {
  newVoucherCode,
  resolveConfirmedStatus,
  issueVoucherPatch,
  orderContext,
} = require('./voucherIssue');
// 본인확인 게이트 — 거래성 요청은 앱 UI와 무관하게 서버가 직접 확인한다.
const { assertIdentityVerified } = require('./identityGuard');

// 플레이스 상품·이용권 주문 — 술집·바·카페(events)와 공간대여·숙박(places)이
// 같은 `placeProducts` 컬렉션을 공유하므로 주문 로직도 하나뿐이다.
//
// placeReservations.js와 **동일한 4단 구조**를 따른다:
//   createPendingProductOrder (재고 선점 + TTL)
//     → 클라이언트 PortOne 결제
//     → verifyAndConfirmProductOrder (서버가 PortOne 조회로 금액·상태 검증)
//     → cancelProductOrder / expireStaleProductOrders
//
// ── 클라이언트를 믿지 않는 지점 (중요) ──────────────────────────────────────
//  - 결제 금액은 클라이언트가 보낸 값을 **쓰지 않는다**. 서버가 상품 문서의
//    salePrice × quantity로 직접 계산해 pending 문서에 적고, 결제 검증 때도
//    그 값을 기대 금액으로 쓴다.
//  - 재고(soldCount)는 pending 생성 시점에 이미 선점한다. 결제 확정까지
//    기다리면 결제를 마친 뒤에야 "품절"로 실패할 수 있기 때문 —
//    packageBookings.js가 파티 정원을 미리 잡는 것과 같은 이유다.
//  - 주문 문서는 firestore.rules에서 클라이언트 쓰기가 전면 차단돼 있다.
//    상태 전환은 전부 여기(Admin SDK)에서만 일어난다.
//
// paymentId 규칙 — 주문 문서 id를 그대로 PortOne paymentId로 쓴다
// (placeReservations가 groupId를 쓰는 것과 동일).
//
// ── 결제 흐름 (무통장입금·현장결제) ──────────────────────────────────────────
// PG 계약 전이라 실제로 받을 수 있는 수단은 무통장입금과 현장결제뿐이고, 흐름은
// 다른 도메인과 완전히 같다(depositFlow 공유). 이 도메인에만 있는 규칙은
// **QR 이용권의 발급·사용 조건** 하나다.
//
// ── QR 이용권은 "돈이 실제로 들어온 뒤"에만 존재한다 (중요) ──────────────────
// 이용권 코드(voucherCode)는 주문 생성 시점에 **만들지 않는다**(''로 시작).
// 코드가 결제 전에 존재하면 결제 없이 스캔을 시도할 여지가 생기기 때문이다.
// 코드가 생기는 지점은 오직 하나 — `issueVoucherPatch()`이고, 그 함수는
// **결제가 확인된 뒤**에만 호출된다:
//
//   무통장입금: 판매자가 '입금 확인'(confirmPlaceProductDeposit) → paid → 발급
//   현장결제  : 판매자가 '결제 확인'(같은 함수)             → paid → 발급
//   옛 PG     : PortOne 조회 검증 통과                       → 발급
//
// 따라서 awaiting_deposit · deposit_pending · on_site_scheduled 세 상태에서는
// 이용권이 **아예 만들어지지 않고**, 만들어질 수 없으므로 사용도 불가능하다.
// 그럼에도 사용(redeem) 시점에 payment.status === 'paid'를 **한 번 더** 본다
// (redeemBlockReason) — 코드가 어떤 경로로든 먼저 생긴 문서/수기 수정/옛
// 데이터가 있어도 돈을 받지 않은 이용권이 통과하지 않게 하는 마지막 방어선이다.
//
// ⚠ expiresAt 주의 — 무통장입금 주문에는 이 필드를 **아예 만들지 않는다**.
// expireStaleProductOrders는 `status == 'payment_pending' && expiresAt < now`로
// 찾는데, Firestore 타입 순서상 null은 어떤 Timestamp보다 작아서 `null`을 넣으면
// 24시간짜리 주문이 10분 만에 걸려버린다(필드가 없으면 색인에서 빠진다).

const portOneApiSecret = defineSecret('PORTONE_API_SECRET');

/** 결제 대기 유효 시간 — 예약(placeReservations)과 동일하게 10분. */
const PENDING_TTL_MS = 10 * 60 * 1000;

/** 한 번에 살 수 있는 최대 수량 — 오입력/스크립트 남용 방어선. */
const MAX_QUANTITY_PER_ORDER = 50;

/** 상품 컬렉션이 QR 검증에서 날짜·시간까지 봐야 하는 유형들.
 *  Dart의 PlaceProductType.isDateBound와 반드시 같은 목록을 유지한다. */
const DATE_BOUND_TYPES = new Set(['seat', 'ticket', 'bottle', 'experience']);

/** 1인당 구매 한도를 계산할 때 "이미 산 것"으로 세는 주문 상태.
 *  취소·환불·만료된 주문은 한도를 되돌려준다. */
const COUNTED_TOWARD_LIMIT = new Set(['payment_pending', 'paid', 'usable', 'used']);

/** QR에 담는 1회용 코드 — 추측 불가능해야 하므로 암호학적 난수를 쓴다. */

function tsToMs(ts) {
  if (!ts) return null;
  if (typeof ts.toMillis === 'function') return ts.toMillis();
  if (ts instanceof Date) return ts.getTime();
  return null;
}

/**
 * 상품의 지금 판매 상태 — Dart의 PlaceProduct.statusAt과 같은 우선순위
 * (수동 중지 > 판매 종료 > 판매 예정 > 품절 > 판매 중)를 그대로 구현한다.
 * 클라이언트가 계산한 상태는 믿지 않고 서버가 다시 판정한다.
 */
function productStatusAt(product, nowMs) {
  if (product.manuallyStopped === true) return 'stopped';
  const saleEnd = tsToMs(product.saleEndAt);
  if (saleEnd !== null && nowMs > saleEnd) return 'ended';
  const saleStart = tsToMs(product.saleStartAt);
  if (saleStart !== null && nowMs < saleStart) return 'scheduled';
  const total = Number(product.totalStock) || 0;
  const sold = Number(product.soldCount) || 0;
  if (total > 0 && sold >= total) return 'sold_out';
  return 'on_sale';
}

const STATUS_MESSAGE = {
  stopped: '지금은 판매가 중지된 상품이에요.',
  ended: '판매가 종료된 상품이에요.',
  scheduled: '아직 판매가 시작되지 않은 상품이에요.',
  sold_out: '품절된 상품이에요.',
};

// ── 1. 결제 대기 주문 생성 ───────────────────────────────────────────────────

exports.createPendingProductOrder = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const uid = request.auth.uid;
    const db = admin.firestore();
    // 본인확인은 **다른 어떤 검증보다 먼저** 본다(identityGuard.js 참고).
    await assertIdentityVerified(db, uid);

    const data = request.data || {};
    const productId = data.productId;
    const quantity = Number(data.quantity) || 0;
    const useAtMs = data.useAtMs != null ? Number(data.useAtMs) : null;
    const reservationId = data.reservationId ? String(data.reservationId) : null;
    const buyerMessage = String(data.buyerMessage || '').trim().slice(0, 500);
    // 결제수단만 받는다 — 금액도 결제 상태도 서버가 정한다.
    const payment = data.payment;

    if (!productId || typeof productId !== 'string') {
      throw new HttpsError('invalid-argument', 'productId가 필요합니다.');
    }
    if (!Number.isInteger(quantity) || quantity < 1 || quantity > MAX_QUANTITY_PER_ORDER) {
      throw new HttpsError('invalid-argument', '구매 수량이 올바르지 않습니다.');
    }

    // 구매자 이름은 users 문서에서 가져온다 — 클라이언트가 보낸 이름을 쓰면
    // 사장님 화면에 아무 이름이나 띄울 수 있다.
    const userSnap = await db.collection('users').doc(uid).get();
    const buyerName = (userSnap.exists && userSnap.data().name) || '구매자';

    const productRef = db.collection('placeProducts').doc(productId);
    const orderRef = db.collection('placeProductOrders').doc();
    const nowMs = Date.now();

    const result = await db.runTransaction(async (tx) => {
      const productSnap = await tx.get(productRef);
      if (!productSnap.exists) {
        throw new HttpsError('not-found', '상품을 찾을 수 없어요.');
      }
      const product = productSnap.data();

      const status = productStatusAt(product, nowMs);
      if (status !== 'on_sale') {
        throw new HttpsError('failed-precondition', STATUS_MESSAGE[status] || '지금은 구매할 수 없는 상품이에요.');
      }

      const total = Number(product.totalStock) || 0;
      const sold = Number(product.soldCount) || 0;
      if (total > 0 && sold + quantity > total) {
        throw new HttpsError('failed-precondition', `남은 수량이 ${total - sold}개예요.`);
      }

      // 1인당 구매 한도 — 이미 산(취소/환불이 아닌) 수량을 합산해 확인한다.
      //
      // 반드시 tx.get으로 읽는다 — 트랜잭션 밖의 db.get()을 쓰면 재시도될 때
      // 낡은 결과를 보고 한도를 넘겨 통과시킬 수 있다. 상태 필터는 쿼리에
      // 넣지 않고 여기서 거른다(equality 두 개 + in 조합은 복합 색인을
      // 요구하는데, 한 사람의 한 상품 주문 수는 어차피 몇 건뿐이다).
      const perPersonLimit = Number(product.perPersonLimit) || 0;
      if (perPersonLimit > 0) {
        const mine = await tx.get(
          db
            .collection('placeProductOrders')
            .where('productId', '==', productId)
            .where('buyerId', '==', uid),
        );
        const bought = mine.docs.reduce((sum, d) => {
          const o = d.data();
          return COUNTED_TOWARD_LIMIT.has(o.status)
            ? sum + (Number(o.quantity) || 0)
            : sum;
        }, 0);
        if (bought + quantity > perPersonLimit) {
          throw new HttpsError(
            'failed-precondition',
            `1인당 ${perPersonLimit}개까지 구매할 수 있어요.`,
          );
        }
      }

      // 금액은 서버가 계산한다 — 클라이언트가 보낸 값은 아예 받지 않는다.
      const unitPrice = Number(product.salePrice) || 0;
      const totalPrice = unitPrice * quantity;

      // 결제수단을 보낸 앱이면 무통장입금/현장결제 흐름을 타고, 보내지 않은
      // 옛 앱이면 지금까지의 포트원 10분 pending 흐름을 그대로 탄다.
      // 준비중인 수단(카드·간편결제 등)은 여기서 거절되고, 그러면 트랜잭션
      // 전체가 롤백돼 재고 선점도 함께 되돌아간다.
      const usesDepositFlow = payment != null || totalPrice <= 0;
      const paymentInfo = usesDepositFlow
        ? buildPaymentInfo(payment, {
            amount: totalPrice,
            nowMs,
            // 이용 예정일이 있으면 입금기한이 그날을 넘지 않게 자른다 —
            // 이용 당일이 지나서 입금하는 건 뜻이 없다.
            useAtMs,
            // 무통장입금 안내 계좌 = 이 상품 호스트의 인증된 수취계좌.
            payoutAccount: await loadPayoutSnapshot(db, product.hostId),
          })
        : null;

      // 재고 선점. 결제가 안 끝나면 만료 스케줄러가 되돌린다.
      tx.update(productRef, {
        soldCount: sold + quantity,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      tx.set(orderRef, {
        productId,
        productName: product.name || '',
        productType: product.type || 'etc',
        placeId: product.placeId || '',
        placeCollection: product.placeCollection || 'events',
        placeName: product.placeName || '',
        hostId: product.hostId || '',
        buyerId: uid,
        buyerName,
        buyerMessage,
        quantity,
        unitPrice,
        totalPrice,
        status: 'payment_pending',
        // QR 이용권은 **돈이 확인된 뒤에만** 발급한다 — 결제 전 코드가
        // 존재하면 결제 없이 스캔을 시도할 여지가 생긴다(파일 상단 주석 참고).
        voucherCode: '',
        useQrCheck: product.useQrCheck === true,
        ...(paymentInfo ? { payment: paymentInfo } : {}),
        useAt: useAtMs != null ? admin.firestore.Timestamp.fromMillis(useAtMs) : null,
        // 상품이 나중에 수정돼도 구매 시점 조건이 이용권에 남아야 한다.
        useStartAt: product.useStartAt || null,
        useEndAt: product.useEndAt || null,
        reservationId,
        // 포트원 10분 대기는 옛 흐름에만 있다(파일 상단 ⚠ 주석 참고).
        ...(usesDepositFlow
          ? {}
          : { expiresAt: admin.firestore.Timestamp.fromMillis(nowMs + PENDING_TTL_MS) }),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return {
        totalPrice,
        productName: product.name || '',
        paymentStatus: paymentInfo ? paymentInfo.status : null,
      };
    });

    return {
      orderId: orderRef.id,
      totalPrice: result.totalPrice,
      productName: result.productName,
      // 앱이 결과 안내를 고를 때 쓴다 — 입금대기인지, 현장결제 예정인지.
      paymentStatus: result.paymentStatus,
    };
  },
);

// ── 1-1. 결제 확인 → **이 순간에만** 이용권이 발급된다 ───────────────────────

/**
 * 결제가 확인된 주문에 반영할 값 — **이용권 코드가 생기는 유일한 지점**이다.
 *
 * 포트원 경로와 무통장입금/현장결제 경로가 같은 함수를 쓴다. 어느 경로든
 * "돈이 확인됐다"가 선행 조건이고, 그 판정은 각 호출부가 자기 방식으로
 * (PortOne 조회 / depositFlow.assertCanConfirmReceived) 끝낸 뒤 부른다.
 */

exports.markPlaceProductDepositSent = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const uid = request.auth.uid;
    const orderId = String((request.data || {}).orderId || '');
    if (!orderId) throw new HttpsError('invalid-argument', 'orderId가 필요합니다.');

    const db = admin.firestore();
    const orderRef = db.collection('placeProductOrders').doc(orderId);

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(orderRef);
      if (!snap.exists) throw new HttpsError('not-found', '주문을 찾을 수 없어요.');
      const order = snap.data();
      if (order.buyerId !== uid) {
        throw new HttpsError('permission-denied', '내 주문만 처리할 수 있어요.');
      }
      // 트랜잭션 안에서 다시 읽은 값으로 판정한다 — 두 번 눌러도 두 번째는
      // 여기서 걸린다(중복 방지).
      flow.assertCanMarkSent(order.payment, orderContext(order));

      const patch = flow.markSentPatch(Date.now());
      tx.update(orderRef, {
        'payment.status': patch.status,
        'payment.depositedAtMs': patch.depositedAtMs,
        // 이용권은 여전히 발급되지 않는다 — '입금확인중'은 아직 받은 돈이
        // 아니다. 판매자가 대조를 끝내야 비로소 코드가 생긴다.
      });
    });

    return { success: true, status: flow.STATUS.depositPending };
  },
);

/**
 * 판매자의 '입금 확인'(무통장입금) / '결제 확인'(현장결제).
 *
 * **이 함수가 성공해야만 이용권이 존재하게 된다.** 현장결제도 여기를 거치므로,
 * 실제로 현장에서 돈을 받기 전까지는 QR이 사용 가능해지지 않는다.
 */
exports.confirmPlaceProductDeposit = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const uid = request.auth.uid;
    const orderId = String((request.data || {}).orderId || '');
    if (!orderId) throw new HttpsError('invalid-argument', 'orderId가 필요합니다.');

    const db = admin.firestore();
    const orderRef = db.collection('placeProductOrders').doc(orderId);
    let voucherCode = '';

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(orderRef);
      if (!snap.exists) throw new HttpsError('not-found', '주문을 찾을 수 없어요.');
      const order = snap.data();
      if (order.hostId !== uid) {
        throw new HttpsError('permission-denied', '내 플레이스의 주문만 처리할 수 있어요.');
      }
      // 무통장입금과 현장결제를 함께 받는다 — 어느 쪽이든 "돈을 받았다"를
      // 판매자가 확인하는 같은 행위다(depositFlow 공용 판정).
      flow.assertCanConfirmReceived(order.payment, orderContext(order));

      const nowMs = Date.now();
      const paid = flow.confirmPatch(nowMs, uid);
      const issued = issueVoucherPatch(order, nowMs);
      voucherCode = issued.voucherCode;

      tx.update(orderRef, {
        'payment.status': paid.status,
        'payment.paidAtMs': paid.paidAtMs,
        'payment.confirmedBy': paid.confirmedBy,
        // 돈이 확인된 지금에야 이용권이 생기고 사용 가능해진다.
        ...issued,
      });
    });

    return { success: true, status: flow.STATUS.paid, voucherCode };
  },
);

// ── 1-2. 입금기한 초과 정리 (10분마다) ───────────────────────────────────────
//
// 기한이 지나도록 **입금대기**인 주문은 재고를 되돌리고 만료시킨다.
// '입금확인중'은 대상이 아니다(다른 도메인과 같은 정책).

exports.expirePlaceProductDeposits = onSchedule(
  { schedule: 'every 10 minutes', timeZone: 'Asia/Seoul', region: 'asia-northeast3' },
  async () => {
    const db = admin.firestore();
    try {
      const nowMs = Date.now();
      const snap = await db
        .collection('placeProductOrders')
        .where('payment.status', '==', flow.STATUS.awaitingDeposit)
        .where('payment.depositDeadlineMs', '<', nowMs)
        .limit(200)
        .get();

      console.log(`[expirePlaceProductDeposits] 만료 대상 ${snap.size}건`);

      for (const doc of snap.docs) {
        try {
          await db.runTransaction(async (tx) => {
            const fresh = await tx.get(doc.ref);
            if (!fresh.exists) return;
            const order = fresh.data();
            // 그 사이에 입금했다고 알렸거나 확인이 끝났으면 건드리지 않는다.
            if (!flow.isExpirable(order.payment, nowMs)) return;
            if (order.status !== 'payment_pending') return;

            // 재고 복구는 취소·만료가 쓰던 **기존 헬퍼 그대로**다.
            const release = await prepareStockRelease(tx, db, order);
            const expired = flow.expirePatch(nowMs);
            tx.update(doc.ref, {
              'payment.status': expired.status,
              'payment.cancelledAtMs': expired.cancelledAtMs,
              status: 'expired',
              cancelReason: 'deposit_expired',
              expiredAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            applyStockRelease(tx, release);
          });
        } catch (e) {
          console.error(`[expirePlaceProductDeposits] ${doc.id} 실패: ${e.message}`);
        }
      }
    } catch (e) {
      await logScheduledFunctionError(db, 'expirePlaceProductDeposits', e);
    }
  },
);

// ── 2. 결제 검증 + 확정 ──────────────────────────────────────────────────────

exports.verifyAndConfirmProductOrder = onCall(
  { region: 'asia-northeast3', secrets: [portOneApiSecret] },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const uid = request.auth.uid;
    const orderId = request.data && request.data.orderId;
    if (!orderId || typeof orderId !== 'string') {
      throw new HttpsError('invalid-argument', 'orderId가 필요합니다.');
    }

    const db = admin.firestore();
    const orderRef = db.collection('placeProductOrders').doc(orderId);
    const orderSnap = await orderRef.get();
    if (!orderSnap.exists) throw new HttpsError('not-found', '주문을 찾을 수 없어요.');
    const order = orderSnap.data();

    if (order.buyerId !== uid) {
      throw new HttpsError('permission-denied', '본인 주문만 확인할 수 있어요.');
    }
    // 이미 확정됨 — 재호출에도 안전(idempotent). 결제창이 두 번 콜백을
    // 보내거나 사용자가 새로고침해도 이용권이 두 장 생기지 않는다.
    if (order.status === 'paid' || order.status === 'usable' || order.status === 'used') {
      return { success: true, voucherCode: order.voucherCode || '' };
    }
    // 무통장입금·현장결제 주문은 애초에 포트원을 거치지 않는다 — 옛 앱이
    // 습관적으로 이 함수를 불러도 결제 상태를 건드리지 않고 통과시킨다.
    // (여기서 이용권을 발급하면 입금 전에 QR이 생겨버린다.)
    if (order.payment) {
      return { success: true, voucherCode: order.voucherCode || '' };
    }
    if (order.status !== 'payment_pending') {
      throw new HttpsError('failed-precondition', '이미 취소되었거나 만료된 주문이에요.');
    }
    if (order.expiresAt && order.expiresAt.toMillis() < Date.now()) {
      throw new HttpsError('deadline-exceeded', '결제 대기 시간이 만료됐어요. 다시 주문해주세요.');
    }

    // 결제 검증 — 기대 금액은 pending 생성 시 **서버가 계산해 저장한** 값이다.
    if (Number(order.totalPrice) > 0) {
      const verify = await verifyPortOnePayment(
        orderId,
        Number(order.totalPrice),
        portOneApiSecret,
      );
      if (!verify.ok) {
        console.error('[verifyAndConfirmProductOrder] 결제 검증 실패', {
          orderId,
          ...verify,
        });
        throw new HttpsError('failed-precondition', '결제 금액/상태가 일치하지 않습니다.');
      }
    }

    // 이용권 발급은 무통장입금 경로와 **같은 함수**를 쓴다 — 코드가 생기는
    // 지점을 하나로 묶어두면 "어떤 경로에서 결제 없이 발급됐는가"를 따질 일이
    // 없다.
    const issued = issueVoucherPatch(order, Date.now());

    await db.runTransaction(async (tx) => {
      const fresh = await tx.get(orderRef);
      if (!fresh.exists || fresh.data().status !== 'payment_pending') return;
      tx.update(orderRef, issued);
    });

    return { success: true, voucherCode: issued.voucherCode };
  },
);

/**
 * 결제 확정 직후의 상태 — 이용 시작일이 아직 안 왔으면 '결제 완료'로 두고,
 * 이미 이용 가능 기간이면 바로 '사용 가능'으로 연다. QR 사용 처리는 '사용
 * 가능'에서만 통과하므로(redeemProductVoucher), 이 구분이 곧 "다음 주 행사
 * 티켓을 오늘 쓰지 못하게" 막는 장치다.
 */

// ── 3. 주문 취소 ─────────────────────────────────────────────────────────────

exports.cancelProductOrder = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const uid = request.auth.uid;
    const orderId = request.data && request.data.orderId;
    if (!orderId || typeof orderId !== 'string') {
      throw new HttpsError('invalid-argument', 'orderId가 필요합니다.');
    }

    const db = admin.firestore();
    const orderRef = db.collection('placeProductOrders').doc(orderId);

    await db.runTransaction(async (tx) => {
      const orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists) throw new HttpsError('not-found', '주문을 찾을 수 없어요.');
      const order = orderSnap.data();

      // 구매자 본인 또는 해당 플레이스 사장님이 취소할 수 있다.
      if (order.buyerId !== uid && order.hostId !== uid) {
        throw new HttpsError('permission-denied', '이 주문을 취소할 권한이 없어요.');
      }
      if (order.status === 'cancelled' || order.status === 'refunded' || order.status === 'expired') {
        return; // 이미 끝난 주문 — 재호출에도 안전
      }
      if (order.status === 'used') {
        throw new HttpsError('failed-precondition', '이미 사용한 이용권은 취소할 수 없어요.');
      }

      // 재고 되돌리기에 필요한 읽기를 **쓰기 전에** 끝낸다 — Firestore
      // 트랜잭션은 모든 읽기가 모든 쓰기보다 앞서야 한다.
      const release = await prepareStockRelease(tx, db, order);

      // 결제가 끝난 주문은 '환불', 결제 전이면 '취소'로 구분해 남긴다 —
      // 실제 환불 처리(PG 취소)는 별도 정산 절차에서 이 상태를 보고 진행한다.
      const paid = order.status === 'paid' || order.status === 'usable';
      tx.update(orderRef, {
        status: paid ? 'refunded' : 'cancelled',
        cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
        // 취소된 이용권의 QR은 즉시 무력화한다.
        voucherCode: '',
      });

      applyStockRelease(tx, release);
    });

    return { success: true };
  },
);

/**
 * 주문이 잡고 있던 수량을 되돌리기 위한 **읽기 단계**.
 * 트랜잭션의 읽기/쓰기 순서 제약 때문에 읽기와 쓰기를 두 함수로 나눈다.
 */
async function prepareStockRelease(tx, db, order) {
  if (!order.productId) return null;
  const productRef = db.collection('placeProducts').doc(order.productId);
  const productSnap = await tx.get(productRef);
  if (!productSnap.exists) return null;
  const sold = Number(productSnap.data().soldCount) || 0;
  const qty = Number(order.quantity) || 0;
  return { ref: productRef, nextSoldCount: Math.max(0, sold - qty) };
}

/** [prepareStockRelease]가 계산해둔 값을 실제로 반영하는 **쓰기 단계**. */
function applyStockRelease(tx, release) {
  if (!release) return;
  tx.update(release.ref, {
    soldCount: release.nextSoldCount,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

// ── 4. 미결제 주문 자동 만료 (5분마다) ───────────────────────────────────────

exports.expireStaleProductOrders = onSchedule(
  {
    schedule: 'every 5 minutes',
    timeZone: 'Asia/Seoul',
    region: 'asia-northeast3',
  },
  async () => {
    const db = admin.firestore();
    try {
      const now = admin.firestore.Timestamp.now();
      const snap = await db
        .collection('placeProductOrders')
        .where('status', '==', 'payment_pending')
        .where('expiresAt', '<', now)
        .limit(200)
        .get();

      for (const doc of snap.docs) {
        // 문서 하나씩 트랜잭션으로 처리한다 — 한 건이 실패해도 나머지가
        // 함께 롤백되지 않게 하려는 것(deleteExpiredParties와 같은 방침).
        try {
          await db.runTransaction(async (tx) => {
            const fresh = await tx.get(doc.ref);
            if (!fresh.exists || fresh.data().status !== 'payment_pending') return;
            const order = fresh.data();
            // 무통장입금 주문은 24시간 기한을 따로 갖는다 — 이 10분짜리
            // 만료가 절대 건드리면 안 된다(expirePlaceProductDeposits 담당).
            // 생성 시 expiresAt 자체를 만들지 않아 쿼리에서 이미 빠지지만,
            // 한 겹 더 막아둔다.
            if (order.payment) return;
            // 읽기를 먼저 전부 끝내고 나서 쓴다(트랜잭션 순서 제약).
            const release = await prepareStockRelease(tx, db, order);
            tx.update(doc.ref, {
              status: 'expired',
              expiredAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            applyStockRelease(tx, release);
          });
        } catch (e) {
          console.error('[expireStaleProductOrders] 개별 만료 실패', doc.id, e);
        }
      }

      if (snap.size > 0) {
        console.log(`[expireStaleProductOrders] ${snap.size}건 만료 처리`);
      }
    } catch (e) {
      console.error('[expireStaleProductOrders] 실패', e);
      await logScheduledFunctionError(db, 'expireStaleProductOrders', e);
    }
  },
);

// ── 5. QR 이용권 확인 / 사용 처리 ────────────────────────────────────────────

exports.redeemProductVoucher = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const uid = request.auth.uid;
    const data = request.data || {};
    const voucherCode = String(data.voucherCode || '').trim();
    const placeId = String(data.placeId || '').trim();
    const verifyOnly = data.verifyOnly === true;

    if (!voucherCode) throw new HttpsError('invalid-argument', 'voucherCode가 필요합니다.');
    if (!placeId) throw new HttpsError('invalid-argument', 'placeId가 필요합니다.');

    const db = admin.firestore();
    const found = await db
      .collection('placeProductOrders')
      .where('voucherCode', '==', voucherCode)
      .limit(1)
      .get();

    if (found.empty) {
      // 코드 자체가 없을 때는 주문 정보를 아무것도 돌려주지 않는다 —
      // 무작위 코드를 넣어보며 남의 주문을 탐색하는 걸 막는다.
      return fail('등록되지 않은 이용권이에요.');
    }

    const orderRef = found.docs[0].ref;
    const order = found.docs[0].data();

    // 스캔한 사람이 그 플레이스의 사장님인지 — 남의 매장 이용권을 임의로
    // 소진시키지 못하게 하는 1차 방어선.
    if (order.hostId !== uid) {
      throw new HttpsError('permission-denied', '이 플레이스의 이용권을 확인할 권한이 없어요.');
    }

    const belongsToPlace = order.placeId === placeId;
    const info = {
      productName: order.productName || '',
      buyerName: order.buyerName || '',
      quantity: Number(order.quantity) || 0,
      status: order.status || 'payment_pending',
      useStartAtMs: tsToMs(order.useStartAt),
      useEndAtMs: tsToMs(order.useEndAt),
      belongsToPlace,
    };

    if (!belongsToPlace) {
      return { ...info, ok: false, redeemed: false, message: '다른 플레이스의 이용권이에요.' };
    }

    const nowMs = Date.now();
    const reason = redeemBlockReason(order, nowMs);
    if (reason) {
      return { ...info, ok: false, redeemed: false, message: reason };
    }

    if (verifyOnly) {
      return { ...info, ok: true, redeemed: false, message: '사용 가능한 이용권이에요.' };
    }

    // 사용 처리 — 트랜잭션 안에서 상태를 다시 확인해, 두 기기에서 동시에
    // 스캔해도 한 번만 소진되게 한다.
    let alreadyUsed = false;
    await db.runTransaction(async (tx) => {
      const fresh = await tx.get(orderRef);
      if (!fresh.exists) return;
      if (fresh.data().status !== 'usable') {
        alreadyUsed = true;
        return;
      }
      tx.update(orderRef, {
        status: 'used',
        usedAt: admin.firestore.FieldValue.serverTimestamp(),
        usedBy: uid,
      });
    });

    if (alreadyUsed) {
      return {
        ...info,
        status: 'used',
        ok: false,
        redeemed: false,
        message: '방금 다른 기기에서 이미 사용 처리됐어요.',
      };
    }

    return {
      ...info,
      status: 'used',
      ok: true,
      redeemed: true,
      message: '사용 완료 처리했어요.',
    };
  },
);

/**
 * 사용 처리를 막아야 하는 이유 — 없으면 null.
 *
 * 판정 본체는 통합 QR 체크인과 **같은 파일**에 있다(checkInRules.js). 스캐너가
 * 둘이던 시절에는 규칙도 둘이었는데, 같은 이용권이 어느 스캐너로 찍히느냐에
 * 따라 다르게 막히면 현장에서 무엇이 맞는지 알 수 없다.
 */
function redeemBlockReason(order, nowMs) {
  return rules.voucherBlockReason(order, nowMs, {
    dateBoundTypes: DATE_BOUND_TYPES,
  });
}


/** 주문 정보를 노출하지 않는 실패 응답. */
function fail(message) {
  return {
    ok: false,
    redeemed: false,
    message,
    productName: '',
    buyerName: '',
    quantity: 0,
    status: 'expired',
    useStartAtMs: null,
    useEndAtMs: null,
    belongsToPlace: false,
  };
}

// 자기검증용 export — placeProductOrders.selfcheck.js가 쓴다.
module.exports.__test = {
  productStatusAt,
  resolveConfirmedStatus,
  redeemBlockReason,
  issueVoucherPatch,
  orderContext,
  isSameKstDay,
  kstDateStr,
  DATE_BOUND_TYPES,
  PENDING_TTL_MS,
  MAX_QUANTITY_PER_ORDER,
};

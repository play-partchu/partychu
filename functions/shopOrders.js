const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');

const { verifyPortOnePayment } = require('./portOne');
const { logScheduledFunctionError } = require('./memberActivityHelpers');
// 결제수단·결제상태는 다른 세 도메인과 **같은 규칙**을 쓴다(수단은 앱이 고르고
// 상태는 서버가 정한다). 전이 규칙도 depositFlow 하나를 공유하며, 파티샵 전용
// 결제 상태 머신은 만들지 않는다.
const { buildPaymentInfo } = require('./paymentInfo');
// 호스트 수취계좌 — 무통장입금 안내 계좌는 이 값 하나에서만 나온다.
const { loadPayoutSnapshot } = require('./payoutAccounts');
const flow = require('./depositFlow');
// 본인확인 게이트 — 거래성 요청은 앱 UI와 무관하게 서버가 직접 확인한다.
const { assertIdentityVerified } = require('./identityGuard');

// 파티샵(partyShops/{shopId}/products/{productId}) 상품 주문.
//
// ⚠ 이 파일이 생기기 전의 동작 — 클라이언트가 1.5초 기다렸다 무조건 성공을
//    돌려주는 더미 결제(PaymentService.processDummyPayment)를 거친 뒤,
//    orders 문서에 status:'paid'를 **직접** 쓰려 했다. 게다가 orders 컬렉션은
//    firestore.rules에 규칙 자체가 없어(=기본 거부) 그 쓰기는 항상 실패했다.
//    즉 파티샵 결제는 사실상 동작하지 않는 상태였다.
//
// 이제 placeReservations.js / placeProductOrders.js와 **동일한 4단 구조**를
// 쓴다. 결제 금액은 서버가 상품 문서를 보고 직접 계산하고, 확정은 PortOne
// 조회로 금액·상태를 검증한 뒤에만 일어난다. 주문 문서는 rules에서 클라이언트
// 쓰기가 전면 차단돼 있고, 상태 전환은 전부 여기(Admin SDK)에서만 한다.
//
// paymentId 규칙 — 주문 문서 id를 그대로 PortOne paymentId로 쓴다.
//
// ── 결제 흐름 (무통장입금·현장결제) ──────────────────────────────────────────
// PG 계약 전이라 실제로 받을 수 있는 수단은 무통장입금과 현장(수령 시) 결제뿐
// 이고, 흐름은 파티 신청·예약들과 **완전히 같다**(depositFlow 공유):
//
//   주문 즉시 재고 선점 + 입금대기(기한 시작)   ← 판매자 승인 단계는 없다
//     → 구매자 '입금했어요'  → 입금확인중
//     → 판매자 '입금 확인'   → 결제완료(status: 'paid')
//   입금기한 초과 → 주문 만료 + **재고 복구**(기존 prepareStockRelease 재사용)
//
// 예약과 달리 승인 단계를 두지 않는다 — 상품 주문은 판매자가 받아줄지 고르는
// 절차가 아니라 재고가 있으면 성립하는 거래이고, 기존 4단 구조에도 승인이
// 없었다. 그래서 `requireApproval`은 넘기지 않는다(기본값 false).
//
// ⚠ expiresAt 주의 — 무통장입금 주문에는 이 필드를 **아예 만들지 않는다**.
// expireStaleShopOrders는 `status == 'payment_pending' && expiresAt < now`로
// 찾는데, Firestore 타입 순서상 null은 어떤 Timestamp보다 작아서 `null`을 넣으면
// 24시간짜리 주문이 10분 만에 걸려버린다. 필드가 없으면 색인에 들어가지 않아
// 쿼리에서 자연히 빠진다(만료 트랜잭션에도 방어 검사를 한 겹 더 뒀다).

const portOneApiSecret = defineSecret('PORTONE_API_SECRET');

/** 결제 대기 유효 시간 — 다른 결제 흐름과 동일하게 10분. */
const PENDING_TTL_MS = 10 * 60 * 1000;

const MAX_QUANTITY_PER_ORDER = 50;

/**
 * 샵 쿠폰 할인액. 클라이언트(PaymentService.applyCoupon)와 **같은 계산**이어야
 * 하는데, 결제 금액의 정본은 서버이므로 여기서 다시 계산한다 — 예전에는
 * 쿠폰이 클라이언트에만 있어서, 서버가 계산한 결제 금액과 화면에 보이는
 * 금액이 어긋날 수 있었다.
 *
 * 쿠폰 조건(할인 종류·값·최소 금액)은 전부 샵 문서에서 읽는다. 클라이언트는
 * "쿠폰을 쓰겠다"는 의사(useCoupon)만 보낸다.
 */
function couponDiscountFor(shop, product, amount, useCoupon) {
  if (!useCoupon) return 0;
  if (shop.hasCoupon !== true) return 0;
  // 상품이 쿠폰 적용 대상이 아니면 무시한다.
  if (product.isCouponApplicable === false) return 0;

  const min = Number(shop.couponMinAmount) || 0;
  if (amount < min) return 0;

  const value = Number(shop.couponDiscountValue) || 0;
  const discount = shop.couponDiscountType === 'percent'
    ? Math.floor((amount * value) / 100)
    : value;
  return Math.min(Math.max(discount, 0), amount);
}

/** 재고를 되돌릴 때 읽기/쓰기를 나눈다(트랜잭션은 읽기가 쓰기보다 앞서야 한다). */
async function prepareStockRelease(tx, db, order) {
  if (!order.shopId || !order.productId) return null;
  const ref = db
    .collection('partyShops')
    .doc(order.shopId)
    .collection('products')
    .doc(order.productId);
  const snap = await tx.get(ref);
  if (!snap.exists) return null;
  // 🛠 주문제작은 선점한 재고가 없다 — 되돌리면 0에서 수량만큼 **늘어난다**
  // (없던 재고가 취소할 때마다 생긴다). 판정은 주문 생성 때와 같은 필드다.
  if (snap.data().madeToOrder === true) return null;
  const stock = Number(snap.data().stock) || 0;
  return { ref, nextStock: stock + (Number(order.quantity) || 0) };
}

function applyStockRelease(tx, release) {
  if (!release) return;
  tx.update(release.ref, { stock: release.nextStock });
}

/**
 * 이 주문이 옛 포트원 10분 만료의 대상인지.
 *
 * 무통장입금 주문은 24시간짜리 기한을 따로 갖고(expireShopOrderDeposits),
 * 생성 시 expiresAt 자체를 만들지 않아 그 쿼리에서 이미 빠진다. 이 판정은
 * 만에 하나 옛 문서/수기 수정으로 두 필드가 함께 있을 때를 위한 방어선이다.
 */
function isLegacyPendingOrder(order) {
  return !order.payment && order.status === 'payment_pending';
}

// ── 1. 결제 대기 주문 생성 ───────────────────────────────────────────────────

exports.createPendingShopOrder = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const uid = request.auth.uid;
    const db = admin.firestore();
    // 본인확인은 **다른 어떤 검증보다 먼저** 본다(identityGuard.js 참고).
    await assertIdentityVerified(db, uid);

    const data = request.data || {};
    const shopId = data.shopId;
    const productId = data.productId;
    const quantity = Number(data.quantity) || 1;
    const deliveryMethod = String(data.deliveryMethod || '').trim();
    const selectedOptionName = data.selectedOptionName
      ? String(data.selectedOptionName)
      : null;
    const scheduledDateMs = data.scheduledDateMs != null
      ? Number(data.scheduledDateMs)
      : null;
    // 쿠폰은 "쓰겠다"는 의사만 받고, 할인액은 서버가 샵 문서를 보고 계산한다.
    const useCoupon = data.useCoupon === true;
    // 결제수단만 받는다 — 금액도 결제 상태도 서버가 정한다.
    const payment = data.payment;

    if (!shopId || !productId) {
      throw new HttpsError('invalid-argument', 'shopId와 productId가 필요합니다.');
    }
    if (!Number.isInteger(quantity) || quantity < 1 || quantity > MAX_QUANTITY_PER_ORDER) {
      throw new HttpsError('invalid-argument', '구매 수량이 올바르지 않습니다.');
    }
    if (!deliveryMethod) {
      throw new HttpsError('invalid-argument', '배송/수령 방식이 필요합니다.');
    }

    const userSnap = await db.collection('users').doc(uid).get();
    const buyerName = (userSnap.exists && userSnap.data().name) || '구매자';

    const shopRef = db.collection('partyShops').doc(shopId);
    const productRef = shopRef.collection('products').doc(productId);
    const orderRef = db.collection('orders').doc();
    const nowMs = Date.now();

    const result = await db.runTransaction(async (tx) => {
      const [shopSnap, productSnap] = await Promise.all([
        tx.get(shopRef),
        tx.get(productRef),
      ]);
      if (!shopSnap.exists) throw new HttpsError('not-found', '샵을 찾을 수 없어요.');
      if (!productSnap.exists) throw new HttpsError('not-found', '상품을 찾을 수 없어요.');

      const shop = shopSnap.data();
      const product = productSnap.data();

      // 🛠 주문제작 상품은 재고를 세지 않는다 — 호스트가 등록 화면에서
      // '주문제작'을 켠 상품이고, 그런 상품의 stock은 0으로 저장된다.
      // 여기서 예외를 두지 않으면 주문제작 상품은 **항상 '품절'로 거절**된다.
      // 판정 규칙은 앱과 같다(party_app/lib/models/made_to_order.dart).
      const madeToOrder = product.madeToOrder === true;
      const stock = Number(product.stock) || 0;
      if (!madeToOrder && stock < quantity) {
        throw new HttpsError('failed-precondition',
          stock <= 0 ? '품절된 상품이에요.' : `남은 수량이 ${stock}개예요.`);
      }

      // 금액은 서버가 계산한다 — 클라이언트가 보낸 금액은 아예 받지 않는다.
      // 옵션 추가금도 상품 문서에 저장된 값에서만 찾는다.
      const unitPrice = Number(product.price) || 0;
      let optionAdditionalPrice = 0;
      if (selectedOptionName) {
        const options = Array.isArray(product.options) ? product.options : [];
        const found = options.find((o) => o && o.name === selectedOptionName);
        if (!found) {
          throw new HttpsError('invalid-argument', '선택한 옵션을 찾을 수 없어요.');
        }
        optionAdditionalPrice = Number(found.additionalPrice) || 0;
      }
      const subtotal = (unitPrice + optionAdditionalPrice) * quantity;
      const couponDiscount = couponDiscountFor(shop, product, subtotal, useCoupon);
      const totalPrice = subtotal - couponDiscount;

      // 결제수단을 보낸 앱이면 무통장입금/현장결제 흐름을 타고, 보내지 않은
      // 옛 앱이면 지금까지의 포트원 10분 pending 흐름을 그대로 탄다.
      // 준비중인 수단(카드·간편결제·실시간계좌이체·가상계좌)은 여기서 거절되고,
      // 그러면 트랜잭션 전체가 롤백돼 재고 선점도 함께 되돌아간다.
      const usesDepositFlow = payment != null || totalPrice <= 0;
      const paymentInfo = usesDepositFlow
        ? buildPaymentInfo(payment, {
            amount: totalPrice,
            nowMs,
            // 무통장입금 안내 계좌 = 이 샵 판매자의 인증된 수취계좌.
            payoutAccount: await loadPayoutSnapshot(db, shop.hostId),
          })
        : null;

      // 재고 선점 — 결제가 끝나지 않으면 만료 스케줄러가 되돌린다.
      // 주문제작은 셀 재고가 없어 선점할 것도 없다(되돌릴 것도 없다 —
      // prepareStockRelease가 같은 판정으로 건너뛴다).
      if (!madeToOrder) {
        tx.update(productRef, { stock: stock - quantity });
      }

      tx.set(orderRef, {
        shopId,
        shopName: shop.name || '',
        productId,
        productName: product.name || '',
        quantity,
        unitPrice,
        optionAdditionalPrice,
        selectedOptionName,
        subtotal,
        couponDiscount,
        amount: totalPrice,
        buyerId: uid,
        buyerName,
        sellerId: shop.hostId || '',
        sellerName: shop.hostName || '판매자',
        deliveryMethod,
        scheduledDate: scheduledDateMs != null
          ? admin.firestore.Timestamp.fromMillis(scheduledDateMs)
          : null,
        status: 'payment_pending',
        ...(paymentInfo ? { payment: paymentInfo } : {}),
        // 포트원 10분 대기는 옛 흐름에만 있다 — 무통장입금 주문에는 이 필드를
        // 아예 만들지 않는다(파일 상단 ⚠ 주석 참고).
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

// ── 1-1. 무통장입금 (구매자 '입금했어요' / 판매자 '입금 확인') ────────────────
//
// 전이 판정은 전부 depositFlow가 한다. 파티샵에서 다른 것은 "확인이 끝나면
// 주문이 결제완료(status: 'paid')가 된다"는 도메인 사정 하나뿐이다 — 파티
// 신청이 확인과 동시에 확정되는 것과 같은 구조다.

/** 이미 끝난 주문인지 — depositFlow에 넘길 문맥. */
const orderContext = (order) => ({
  cancelled:
    order.status === 'cancelled' ||
    order.status === 'refunded' ||
    order.status === 'expired',
});

exports.markShopDepositSent = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const uid = request.auth.uid;
    const orderId = String((request.data || {}).orderId || '');
    if (!orderId) throw new HttpsError('invalid-argument', 'orderId가 필요합니다.');

    const db = admin.firestore();
    const orderRef = db.collection('orders').doc(orderId);

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
      });
    });

    return { success: true, status: flow.STATUS.depositPending };
  },
);

exports.confirmShopDeposit = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const uid = request.auth.uid;
    const orderId = String((request.data || {}).orderId || '');
    if (!orderId) throw new HttpsError('invalid-argument', 'orderId가 필요합니다.');

    const db = admin.firestore();
    const orderRef = db.collection('orders').doc(orderId);

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(orderRef);
      if (!snap.exists) throw new HttpsError('not-found', '주문을 찾을 수 없어요.');
      const order = snap.data();
      if (order.sellerId !== uid) {
        throw new HttpsError('permission-denied', '내 샵의 주문만 처리할 수 있어요.');
      }
      flow.assertCanConfirm(order.payment, orderContext(order));

      const patch = flow.confirmPatch(Date.now(), uid);
      tx.update(orderRef, {
        'payment.status': patch.status,
        'payment.paidAtMs': patch.paidAtMs,
        'payment.confirmedBy': patch.confirmedBy,
        // 돈이 확인된 순간이 곧 주문 확정이다(파티 신청과 같은 구조).
        status: 'paid',
        paidAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    return { success: true, status: flow.STATUS.paid };
  },
);

// ── 1-2. 입금기한 초과 정리 (10분마다) ───────────────────────────────────────
//
// 기한이 지나도록 **입금대기**인 주문은 재고를 되돌리고 만료시킨다.
// '입금확인중'은 대상이 아니다(다른 도메인과 같은 정책) — 구매자는 입금했다고
// 알렸는데 판매자 확인이 늦은 것뿐일 수 있어, 자동 취소하면 이미 낸 사람의
// 주문을 지우게 된다.

// 자기검증용 export — shopOrders.selfcheck.js가 쓴다.
module.exports.__test = {
  couponDiscountFor,
  isLegacyPendingOrder,
  orderContext,
  PENDING_TTL_MS,
  MAX_QUANTITY_PER_ORDER,
};

exports.expireShopOrderDeposits = onSchedule(
  { schedule: 'every 10 minutes', timeZone: 'Asia/Seoul', region: 'asia-northeast3' },
  async () => {
    const db = admin.firestore();
    try {
      const nowMs = Date.now();
      const snap = await db
        .collection('orders')
        .where('payment.status', '==', flow.STATUS.awaitingDeposit)
        .where('payment.depositDeadlineMs', '<', nowMs)
        .limit(200)
        .get();

      console.log(`[expireShopOrderDeposits] 만료 대상 ${snap.size}건`);

      for (const doc of snap.docs) {
        try {
          await db.runTransaction(async (tx) => {
            const fresh = await tx.get(doc.ref);
            if (!fresh.exists) return;
            const order = fresh.data();
            // 그 사이에 입금했다고 알렸거나 확인이 끝났으면 건드리지 않는다.
            if (!flow.isExpirable(order.payment, nowMs)) return;
            if (order.status !== 'payment_pending') return;

            // 재고 복구는 취소·만료가 쓰던 **기존 로직 그대로**다.
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
          console.error(`[expireShopOrderDeposits] ${doc.id} 실패: ${e.message}`);
        }
      }
    } catch (e) {
      await logScheduledFunctionError(db, 'expireShopOrderDeposits', e);
    }
  },
);

// ── 2. 결제 검증 + 확정 ──────────────────────────────────────────────────────

exports.verifyAndConfirmShopOrder = onCall(
  { region: 'asia-northeast3', secrets: [portOneApiSecret] },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const uid = request.auth.uid;
    const orderId = request.data && request.data.orderId;
    if (!orderId || typeof orderId !== 'string') {
      throw new HttpsError('invalid-argument', 'orderId가 필요합니다.');
    }

    const db = admin.firestore();
    const orderRef = db.collection('orders').doc(orderId);
    const snap = await orderRef.get();
    if (!snap.exists) throw new HttpsError('not-found', '주문을 찾을 수 없어요.');
    const order = snap.data();

    if (order.buyerId !== uid) {
      throw new HttpsError('permission-denied', '본인 주문만 확인할 수 있어요.');
    }
    if (order.status === 'paid') return { success: true }; // 재호출 안전
    // 무통장입금·현장결제 주문은 애초에 포트원을 거치지 않는다 — 옛 앱이
    // 습관적으로 이 함수를 불러도 결제 상태를 건드리지 않고 그냥 통과시킨다.
    if (order.payment) {
      return { success: true, paymentStatus: order.payment.status };
    }
    if (order.status !== 'payment_pending') {
      throw new HttpsError('failed-precondition', '이미 취소되었거나 만료된 주문이에요.');
    }
    if (order.expiresAt && order.expiresAt.toMillis() < Date.now()) {
      throw new HttpsError('deadline-exceeded', '결제 대기 시간이 만료됐어요. 다시 주문해주세요.');
    }

    if (Number(order.amount) > 0) {
      const verify = await verifyPortOnePayment(
        orderId, Number(order.amount), portOneApiSecret,
      );
      if (!verify.ok) {
        console.error('[verifyAndConfirmShopOrder] 결제 검증 실패', { orderId, ...verify });
        throw new HttpsError('failed-precondition', '결제 금액/상태가 일치하지 않습니다.');
      }
    }

    await db.runTransaction(async (tx) => {
      const fresh = await tx.get(orderRef);
      if (!fresh.exists || fresh.data().status !== 'payment_pending') return;
      tx.update(orderRef, {
        status: 'paid',
        paidAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt: null,
      });
    });

    return { success: true };
  },
);

// ── 3. 주문 취소 ─────────────────────────────────────────────────────────────

exports.cancelShopOrder = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const uid = request.auth.uid;
    const orderId = request.data && request.data.orderId;
    if (!orderId || typeof orderId !== 'string') {
      throw new HttpsError('invalid-argument', 'orderId가 필요합니다.');
    }

    const db = admin.firestore();
    const orderRef = db.collection('orders').doc(orderId);

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(orderRef);
      if (!snap.exists) throw new HttpsError('not-found', '주문을 찾을 수 없어요.');
      const order = snap.data();
      if (order.buyerId !== uid && order.sellerId !== uid) {
        throw new HttpsError('permission-denied', '이 주문을 취소할 권한이 없어요.');
      }
      if (order.status === 'cancelled' || order.status === 'refunded' ||
          order.status === 'expired') {
        return;
      }

      const release = await prepareStockRelease(tx, db, order);
      tx.update(orderRef, {
        status: order.status === 'paid' ? 'refunded' : 'cancelled',
        cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      applyStockRelease(tx, release);
    });

    return { success: true };
  },
);

// ── 4. 미결제 주문 자동 만료 (5분마다) ───────────────────────────────────────

exports.expireStaleShopOrders = onSchedule(
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
        .collection('orders')
        .where('status', '==', 'payment_pending')
        .where('expiresAt', '<', now)
        .limit(200)
        .get();

      for (const doc of snap.docs) {
        try {
          await db.runTransaction(async (tx) => {
            const fresh = await tx.get(doc.ref);
            if (!fresh.exists) return;
            // 무통장입금 주문은 24시간 기한을 따로 갖는다 — 이 10분짜리
            // 만료가 절대 건드리면 안 된다(expireShopOrderDeposits 담당).
            if (!isLegacyPendingOrder(fresh.data())) return;
            const release = await prepareStockRelease(tx, db, fresh.data());
            tx.update(doc.ref, {
              status: 'expired',
              expiredAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            applyStockRelease(tx, release);
          });
        } catch (e) {
          console.error('[expireStaleShopOrders] 개별 만료 실패', doc.id, e);
        }
      }

      if (snap.size > 0) console.log(`[expireStaleShopOrders] ${snap.size}건 만료 처리`);
    } catch (e) {
      console.error('[expireStaleShopOrders] 실패', e);
      await logScheduledFunctionError(db, 'expireStaleShopOrders', e);
    }
  },
);

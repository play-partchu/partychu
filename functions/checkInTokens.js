/**
 * 파티츄 **통합 QR 체크인** — 호스트에게 스캐너는 하나뿐이다.
 *
 * ── 왜 하나여야 하나 ────────────────────────────────────────────────────────
 * 손님이 내미는 QR은 파티 참가권일 수도, 예약일 수도, 상품 이용권일 수도 있다.
 * 호스트가 그걸 미리 알고 스캐너를 골라야 한다면 그건 손님에게 "무슨 QR이냐"고
 * 먼저 묻는 것과 같다. 그래서 **종류 판별은 서버가** 한다.
 *
 * ── 흐름 ────────────────────────────────────────────────────────────────────
 *   QR 스캔 → resolveCheckInToken   (조회만, 상태 안 바꿈)
 *           → 호스트가 눈으로 확인
 *           → consumeCheckIn        (여기서만 상태가 바뀐다)
 *
 * **스캔 = 소진이 아니다.** 다른 날짜 QR을 잘못 찍거나, 손님이 화면을 잘못
 * 열었을 수 있다. 그래서 조회는 몇 번을 해도 아무것도 변하지 않는다.
 *
 * ── 토큰 ────────────────────────────────────────────────────────────────────
 * QR에는 **난수 토큰 하나**만 들어간다. 이름도 예약번호도 넣지 않는다 —
 * QR 이미지가 유출돼도 그 자체로는 아무 정보가 아니고, 호스트가 아닌 사람이
 * 서버에 물어봐도 권한 검사에서 막힌다.
 *
 *   checkInTokens/{token}
 *     domain    'party' | 'place_reservation' | 'product_voucher'
 *     refPath   원본 문서 경로(이 파일 밖에서는 쓰지 않는다)
 *     hostId    스캔할 수 있는 사람
 *     guestUid  누구의 이용인가(신원 조회용)
 *     active    살아 있는 QR인가 — 취소·거절·만료로 죽으면 false로 남는다
 *
 * 문서 **id가 곧 토큰**이라 조회에 색인이 필요 없다. 클라이언트는 이 컬렉션을
 * 읽지도 쓰지도 못한다(firestore.rules) — 서버만 만들고 서버만 읽는다.
 *
 * 발급·무효화는 이 파일이 하지 않는다. 원본 1건당 **살아 있는 토큰이 하나뿐**
 * 이라는 불변식은 checkInTokenStore.js가 지키고, 파티 승인·예약 확정 트리거가
 * 그 모듈을 부른다(partyCheckIn.js · reservationCheckIn.js).
 *
 * ── 기존 상품 이용권과의 호환 (중요) ────────────────────────────────────────
 * 이미 발급된 이용권은 `placeProductOrders.voucherCode`에 코드가 들어 있고
 * checkInTokens 문서가 없다. 그래서 토큰을 못 찾으면 **그 필드로 한 번 더**
 * 찾는다. 옛 QR도 새 스캐너에서 그대로 동작하고, 옛 앱이 부르는
 * redeemProductVoucher도 그대로 남아 있다(판정은 checkInRules 하나를 공유).
 *
 * ── 권한 ────────────────────────────────────────────────────────────────────
 * 토큰을 가진 사람이 아니라 **원본 문서의 호스트**만 조회·사용할 수 있다.
 * 게스트 자신이 자기 토큰을 넣어도 신원 정보를 되돌려받지 못한다 —
 * 남의 QR을 주워 서버에 물어보는 경로를 막기 위해서다.
 */

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

const rules = require('./checkInRules');
// 토큰 발급·무효화는 트리거들과 **같은 모듈**을 쓴다 — 원본 1건당 살아 있는
// 토큰이 하나뿐이라는 불변식이 여기서만 지켜진다(checkInTokenStore.js).
const store = require('./checkInTokenStore');
const { isSameKstDay } = require('./kstTime');
// 호스트에게 보여줄 신원 한 벌 — 파티 신청자 목록과 **같은 정본**이다.
// 본인확인을 마친 계정의 실명·성별·생년월일만 실리고 전화번호·CI는 없다.
const { buildApplicantIdentity } = require('./applicantIdentity');
// 결제 확인 판정과 이용권 발급은 판매 화면과 **같은 함수**를 쓴다.
const flow = require('./depositFlow');
const voucher = require('./voucherIssue');

const REGION = 'asia-northeast3';

/** 컬렉션 이름 — 저장값이라 변경 금지. */
const TOKENS = store.TOKENS;

/** 토큰이 가리킬 수 있는 컬렉션 — 여기 없는 경로는 아예 읽지 않는다. */
const ALLOWED_ROOTS = new Set([
  'parties',
  'placeVisitReservations',
  'placeReservationGroups',
  'packageBookings',
  'placeProductOrders',
]);

/** 상품 유형 중 날짜까지 맞아야 하는 것들 — placeProductOrders와 같은 목록. */
const DATE_BOUND_TYPES = new Set(['seat', 'ticket', 'bottle', 'experience']);

/** 체크인을 되돌릴 수 있는 시간 — 찍은 날(KST) 안에서만. */
const REVOKE_SAME_DAY_ONLY = true;

// ── 토큰 → 원본 문서 ────────────────────────────────────────────────────────

/**
 * 토큰이 가리키는 원본을 찾는다. 못 찾으면 null.
 *
 * 두 경로를 본다 — 새 토큰 문서가 먼저고, 없으면 이미 발급된 상품 이용권의
 * voucherCode로 한 번 더 찾는다(파일 상단 '기존 상품 이용권과의 호환' 참고).
 */
async function locate(db, token) {
  const tokenSnap = await db.collection(TOKENS).doc(token).get();
  if (tokenSnap.exists) {
    const t = tokenSnap.data();
    // 무효화된 토큰(취소·거절·만료로 죽은 QR)은 여기서 끝난다. 죽은 채로
    // 남겨 두는 이유는 checkInTokenStore.js 상단 주석 참고 — "없는 QR"이
    // 아니라 "쓸 수 없는 QR"이라고 답할 수 있어야 한다.
    if (!store.isTokenActive(t)) return { revoked: true };
    const refPath = String(t.refPath || '');
    // 경로를 그대로 믿지 않는다 — 콘솔에서 손댄 문서가 엉뚱한 컬렉션을 읽게
    // 만들 수 있다. 허용한 뿌리와 짝수 세그먼트(문서 경로)만 통과시킨다.
    const parts = refPath.split('/').filter(Boolean);
    if (parts.length < 2 || parts.length % 2 !== 0) return null;
    if (!ALLOWED_ROOTS.has(parts[0])) return null;
    return {
      token,
      tokenRef: tokenSnap.ref,
      domain: t.domain,
      ref: db.doc(refPath),
      hostId: t.hostId || '',
      guestUid: t.guestUid || '',
    };
  }

  // 옛 상품 이용권 — 토큰 문서가 없다.
  const found = await db
    .collection('placeProductOrders')
    .where('voucherCode', '==', token)
    .limit(1)
    .get();
  if (found.empty) return null;
  const order = found.docs[0].data();
  return {
    token,
    tokenRef: null,
    domain: rules.DOMAIN.voucher,
    ref: found.docs[0].ref,
    hostId: order.hostId || '',
    guestUid: order.buyerId || '',
  };
}

/** 호스트에게 보여줄 신원 — users 문서 한 벌에서 만든다. */
async function loadIdentity(db, guestUid) {
  if (!guestUid) return buildApplicantIdentity(null).identity;
  const snap = await db.collection('users').doc(guestUid).get();
  return buildApplicantIdentity(snap.exists ? snap.data() : null).identity;
}

// ── 도메인별 조립 ───────────────────────────────────────────────────────────

/** 파티 신청 1건. */
async function loadParty(db, ref, nowMs) {
  const snap = await ref.get();
  if (!snap.exists) return null;
  const app = snap.data();
  // parties/{partyId}/applications/{appId} — 파티 본문에서 제목·일시를 읽는다.
  const partySnap = await ref.parent.parent.get();
  const party = partySnap.exists ? partySnap.data() : {};
  const checkedInAtMs = rules.tsToMs(app.checkedInAt);
  return {
    doc: app,
    hostId: app.hostId || party.hostId || '',
    guestUid: app.uid || snap.id,
    alreadyDone: checkedInAtMs !== null,
    blockReason: rules.partyBlockReason(app, party, nowMs),
    core: {
      title: party.title || '파티',
      subtitle: party.location || party.address || '',
      atMs: rules.tsToMs(app.partyDateTime) ?? rules.tsToMs(party.dateTime),
      // 파티 신청은 1건 = 1명이다. 차수/패키지는 "몇 명"이 아니라 "몇 번"이라
      // 인원으로 세지 않고 detail에 적는다.
      people: 1,
      purchasedItem: app.packageName || '',
      checkedInAtMs,
      ...rules.paymentSummary(app.payment),
      detail: {
        applicationStatus: app.status || '',
        applicationType: app.applicationType || 'round',
        selectedRounds: Array.isArray(app.selectedRounds)
          ? app.selectedRounds
          : null,
        appliedFee:
          typeof app.appliedFee === 'number' ? app.appliedFee : null,
      },
    },
  };
}

/** 방문예약 / 장소대여 / 패키지 예약. 세 컬렉션의 필드 이름이 다르다. */
async function loadReservation(db, ref, nowMs) {
  const snap = await ref.get();
  if (!snap.exists) return null;
  const r = snap.data();
  const checkedInAtMs = rules.tsToMs(r.checkedInAt);
  const startMs =
    rules.tsToMs(r.visitAt) ??
    rules.tsToMs(r.useStartAt) ??
    rules.tsToMs(r.startAt);
  return {
    doc: r,
    hostId: r.hostId || '',
    guestUid: r.requesterId || r.guestId || '',
    alreadyDone: checkedInAtMs !== null,
    blockReason: rules.reservationBlockReason(
      { ...r, useStartAt: r.useStartAt ?? r.startAt },
      nowMs,
    ),
    core: {
      title: r.placeName || '예약',
      subtitle: r.roomName || r.packageName || '',
      atMs: startMs,
      endAtMs: rules.tsToMs(r.useEndAt) ?? rules.tsToMs(r.endAt),
      people: typeof r.peopleCount === 'number' ? r.peopleCount : null,
      purchasedItem: r.roomName || r.packageName || '',
      checkedInAtMs,
      ...rules.paymentSummary(r.payment),
      detail: {
        reservationStatus: r.status || '',
        bookingType: r.bookingType || '',
        nights: typeof r.nights === 'number' ? r.nights : null,
        totalPrice: typeof r.totalPrice === 'number' ? r.totalPrice : null,
        collection: ref.parent.id,
      },
    },
  };
}

/** 상품·이용권 주문. */
async function loadVoucher(db, ref, nowMs) {
  const snap = await ref.get();
  if (!snap.exists) return null;
  const o = snap.data();
  const usedAtMs = rules.tsToMs(o.usedAt);
  return {
    doc: o,
    hostId: o.hostId || '',
    guestUid: o.buyerId || '',
    alreadyDone: o.status === 'used',
    blockReason: rules.voucherBlockReason(o, nowMs, {
      dateBoundTypes: DATE_BOUND_TYPES,
    }),
    core: {
      title: o.placeName || '이용권',
      subtitle: o.productName || '',
      atMs: rules.tsToMs(o.useAt),
      endAtMs: rules.tsToMs(o.useEndAt),
      quantity: typeof o.quantity === 'number' ? o.quantity : null,
      purchasedItem: o.productName || '',
      checkedInAtMs: usedAtMs,
      ...rules.paymentSummary(o.payment),
      detail: {
        orderStatus: o.status || '',
        productType: o.productType || '',
        totalPrice: typeof o.totalPrice === 'number' ? o.totalPrice : null,
        useQrCheck: o.useQrCheck === true,
      },
    },
  };
}

const LOADERS = {
  [rules.DOMAIN.party]: loadParty,
  [rules.DOMAIN.reservation]: loadReservation,
  [rules.DOMAIN.voucher]: loadVoucher,
};

// ── 공통 관문 ───────────────────────────────────────────────────────────────

/** 토큰을 읽어 원본·신원까지 갖춘 한 벌로 만든다. 권한도 여기서 본다. */
async function open(db, uid, token, nowMs) {
  const located = await locate(db, token);
  // 없는 토큰은 **아무것도 알려주지 않는다** — 무작위 코드를 넣어 보며 남의
  // 이용을 탐색하는 걸 막는다.
  if (!located) return { error: '등록되지 않은 QR이에요.' };
  // 죽은 토큰만 예외다. 취소된 예약의 QR을 들고 온 손님에게 "없는 QR"이라고
  // 하면 현장에서 다툼이 된다 — 내용은 여전히 한 글자도 싣지 않는다.
  if (located.revoked) return { error: '더 이상 사용할 수 없는 QR이에요.' };

  const loader = LOADERS[located.domain];
  if (!loader) return { error: '알 수 없는 QR이에요.' };

  const loaded = await loader(db, located.ref, nowMs);
  if (!loaded) return { error: '이용 정보를 찾을 수 없어요.' };

  // 권한은 **원본 문서의 hostId**로 본다. 토큰 문서에 적힌 값을 그대로 믿으면,
  // 콘솔에서 손댄 토큰 하나로 남의 이용을 열어볼 수 있다.
  const ownerId = loaded.hostId || located.hostId;
  if (!ownerId || ownerId !== uid) {
    // 내용은 한 글자도 싣지 않는다 — "내 것이 아니다"까지만 알려준다.
    return { error: '이 QR을 확인할 권한이 없어요.' };
  }

  return {
    ...located,
    ...loaded,
    guestUid: loaded.guestUid || located.guestUid,
  };
}

/** 감사 기록 — 토큰 문서가 있는 건에만 남긴다(옛 이용권은 usedAt/usedBy). */
function writeAudit(tx, opened, action, uid) {
  if (!opened.tokenRef) return;
  tx.set(opened.tokenRef.collection('events').doc(), {
    action,
    byUid: uid,
    at: admin.firestore.FieldValue.serverTimestamp(),
  });
}

function readToken(data) {
  const token = String((data && data.token) || '').trim();
  if (!token || token.length > 200) {
    throw new HttpsError('invalid-argument', 'token이 필요합니다.');
  }
  return token;
}

function requireUid(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
  return request.auth.uid;
}

// ── 1. 조회 — 상태를 바꾸지 않는다 ──────────────────────────────────────────

exports.resolveCheckInToken = onCall({ region: REGION }, async (request) => {
  const uid = requireUid(request);
  const token = readToken(request.data);
  const db = admin.firestore();
  const nowMs = Date.now();

  const opened = await open(db, uid, token, nowMs);
  // 없는 QR·죽은 QR·남의 QR은 **같은 모양**으로 돌려준다 — 셋을 구분해 주면
  // 남의 QR을 주운 사람이 그 차이만으로 무언가를 알게 된다.
  if (opened.error) return rules.emptyCheckInResult(opened.error);

  return rules.buildCheckInResult({
    domain: opened.domain,
    identity: await loadIdentity(db, opened.guestUid),
    core: opened.core,
    blockReason: opened.blockReason,
    alreadyDone: opened.alreadyDone,
    // 현장결제00b7입금 대기 중인 이용권은 이 화면에서 바로 확인할 수 있다.
    canConfirmPayment:
      opened.domain === rules.DOMAIN.voucher &&
      !opened.alreadyDone &&
      rules.paymentBlockReason(opened.doc.payment) !== null,
  });
});

// ── 2. 사용 처리 — **여기서만** 상태가 바뀐다 ───────────────────────────────

/** 도메인별 전이. 트랜잭션 안에서 최신 문서를 다시 읽고 판정한다. */
const CONSUMERS = {
  // 파티는 status를 건드리지 않는다 — 승인 상태는 그대로 두고 체크인 흔적만
  // 남긴다. 'attended'로 바꾸면 참석 통계 트리거가 함께 도는데, 체크인은
  // 출석 집계와 별개 축으로 두기로 했다(checkedInAt이 그 정본이다).
  [rules.DOMAIN.party]: (fresh) =>
    rules.tsToMs(fresh.checkedInAt) !== null
      ? { already: true }
      : {
          patch: {
            checkedInAt: admin.firestore.FieldValue.serverTimestamp(),
            checkedInBy: null, // 아래에서 uid로 채운다
          },
        },
  [rules.DOMAIN.reservation]: (fresh) =>
    rules.tsToMs(fresh.checkedInAt) !== null
      ? { already: true }
      : {
          patch: {
            checkedInAt: admin.firestore.FieldValue.serverTimestamp(),
            checkedInBy: null,
          },
        },
  // 이용권은 예전 그대로 status를 소진시킨다 — 재고·매출이 이 값에 걸려 있다.
  [rules.DOMAIN.voucher]: (fresh) =>
    fresh.status !== 'usable'
      ? { already: true }
      : {
          patch: {
            status: 'used',
            usedAt: admin.firestore.FieldValue.serverTimestamp(),
            usedBy: null,
          },
        },
};

exports.consumeCheckIn = onCall({ region: REGION }, async (request) => {
  const uid = requireUid(request);
  const token = readToken(request.data);
  const db = admin.firestore();
  const nowMs = Date.now();

  const opened = await open(db, uid, token, nowMs);
  if (opened.error) throw new HttpsError('failed-precondition', opened.error);
  if (opened.alreadyDone) {
    throw new HttpsError('failed-precondition', '이미 처리된 QR이에요.');
  }
  if (opened.blockReason) {
    throw new HttpsError('failed-precondition', opened.blockReason);
  }

  // 같은 QR을 두 기기에서 동시에 들이대도 한 번만 통과한다 — 판정을
  // 트랜잭션 안에서 **다시** 한다(위 검사는 빨리 알려주기 용도다).
  let already = false;
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(opened.ref);
    if (!snap.exists) throw new HttpsError('not-found', '이용 정보를 찾을 수 없어요.');
    const decided = CONSUMERS[opened.domain](snap.data());
    if (decided.already) {
      already = true;
      return;
    }
    const patch = { ...decided.patch };
    if ('checkedInBy' in patch) patch.checkedInBy = uid;
    if ('usedBy' in patch) patch.usedBy = uid;
    tx.update(opened.ref, patch);
    writeAudit(tx, opened, 'consume', uid);
  });

  if (already) {
    throw new HttpsError('failed-precondition', '방금 다른 기기에서 이미 처리됐어요.');
  }
  return { ok: true, domain: opened.domain };
});

// ── 3. 되돌리기 — 잘못 찍은 것을 그날 안에만 ────────────────────────────────
//
// 왜 필요한가: 줄이 길 때 옆 사람 QR을 먼저 찍는 실수가 실제로 난다. 되돌릴 수
// 없으면 손님은 입장했는데 기록은 다른 사람에게 남는다.
//
// 왜 좁게 여는가:
//   · **호스트만** — 게스트가 스스로 체크인을 지울 수 있으면 기록이 무의미해진다.
//   · **찍은 날(KST) 안에서만** — 다음 날 되돌리기는 실수 정정이 아니라 기록
//     수정이다. 그건 사람이 개입할 일이지 버튼이 할 일이 아니다.
//   · **이용권은 되돌리지 않는다** — used를 usable로 돌리면 이미 내준 상품을
//     다시 쓸 수 있게 되고 재고·매출과 얽힌다. 잘못 판 건은 주문 취소
//     (cancelProductOrder)라는 별도 경로가 이미 있다.
//
// 되돌린 사실도 남긴다(checkInTokens/{token}/events) — 지운 흔적이 없으면
// 분쟁이 났을 때 무슨 일이 있었는지 아무도 모른다.

exports.revokeCheckIn = onCall({ region: REGION }, async (request) => {
  const uid = requireUid(request);
  const token = readToken(request.data);
  const db = admin.firestore();
  const nowMs = Date.now();

  const opened = await open(db, uid, token, nowMs);
  if (opened.error) throw new HttpsError('failed-precondition', opened.error);
  if (opened.domain === rules.DOMAIN.voucher) {
    throw new HttpsError(
      'failed-precondition',
      '이용권 사용은 되돌릴 수 없어요. 주문 취소를 이용해주세요.',
    );
  }
  if (!opened.alreadyDone) {
    throw new HttpsError('failed-precondition', '아직 체크인하지 않았어요.');
  }

  const checkedInAtMs = opened.core.checkedInAtMs;
  if (
    REVOKE_SAME_DAY_ONLY &&
    checkedInAtMs !== null &&
    !isSameKstDay(checkedInAtMs, nowMs)
  ) {
    throw new HttpsError(
      'failed-precondition',
      '체크인한 날에만 되돌릴 수 있어요.',
    );
  }

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(opened.ref);
    if (!snap.exists) throw new HttpsError('not-found', '이용 정보를 찾을 수 없어요.');
    tx.update(opened.ref, {
      checkedInAt: null,
      checkedInBy: null,
      checkInRevokedAt: admin.firestore.FieldValue.serverTimestamp(),
      checkInRevokedBy: uid,
    });
    writeAudit(tx, opened, 'revoke', uid);
  });

  return { ok: true, domain: opened.domain };
});


// ── 4. 현장결제 확인 — 스캐너를 벗어나지 않고 ───────────────────────────────
//
// 현장에서는 "QR 스캔 → 손님 확인 → 돈 받음 → 사용 처리"가 한 흐름이다.
// 결제를 확인하러 다른 화면으로 보내면 그 사이 손님은 줄 앞에 서 있게 된다.
//
// 판정은 **기존 경로와 같은 함수**를 쓴다 —
//   · 돈을 받았다고 표시할 수 있는 상태인가 : depositFlow.assertCanConfirmReceived
//   · 그 순간 이용권이 생긴다               : voucherIssue.issueVoucherPatch
// 그래서 이 콜러블로 확인하든 판매 화면에서 확인하든 결과가 같다.
//
// 지금 붙어 있는 도메인은 이용권 하나다. 파티·예약의 현장결제 확인은 각자
// 전용 콜러블이 이미 있으므로(호스트가 신청자·예약 화면에서 누른다),
// 2단계에서 그 경로를 여기로 이어 붙인다.

exports.confirmCheckInPayment = onCall({ region: REGION }, async (request) => {
  const uid = requireUid(request);
  const token = readToken(request.data);
  const db = admin.firestore();
  const nowMs = Date.now();

  const opened = await open(db, uid, token, nowMs);
  if (opened.error) throw new HttpsError('failed-precondition', opened.error);
  if (opened.domain !== rules.DOMAIN.voucher) {
    throw new HttpsError(
      'failed-precondition',
      '이 QR은 여기서 결제를 확인할 수 없어요.',
    );
  }

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(opened.ref);
    if (!snap.exists) throw new HttpsError('not-found', '주문을 찾을 수 없어요.');
    const order = snap.data();
    // 소유자 확인은 open()이 이미 했다. 여기서는 "지금 확인해도 되는 상태인가"만.
    flow.assertCanConfirmReceived(order.payment, voucher.orderContext(order));

    const paid = flow.confirmPatch(nowMs, uid);
    tx.update(opened.ref, {
      'payment.status': paid.status,
      'payment.paidAtMs': paid.paidAtMs,
      'payment.confirmedBy': paid.confirmedBy,
      // 돈이 확인된 지금에야 이용권이 생기고 사용 가능해진다.
      ...voucher.issueVoucherPatch(order, nowMs),
    });
    writeAudit(tx, opened, 'confirm_payment', uid);
  });

  return { ok: true, domain: opened.domain };
});

// 발급·무효화는 checkInTokenStore.js가 정본이다. 여기서 다시 내보내지 않는
// 이유는 index.js가 이 모듈을 통째로 exports에 붙이기 때문이다 — 콜러블이
// 아닌 것이 섞이면 배포 목록이 흐려진다.

module.exports.__test = {
  TOKENS,
  ALLOWED_ROOTS,
  DATE_BOUND_TYPES,
  REVOKE_SAME_DAY_ONLY,
  CONSUMERS,
};

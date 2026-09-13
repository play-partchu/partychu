const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');
const {
  PENDING_TTL_MS,
  STAY_LOOKBACK_DAYS,
  kstMidnight,
  kstWeekdayLabel,
  windowsOverlap,
  loadReservationConfig,
  computeWindows,
} = require('./roomAvailability');
const { verifyPortOnePayment } = require('./portOne');
const { logScheduledFunctionError } = require('./memberActivityHelpers');
// 결제수단·결제상태는 파티 신청·플레이스 방문예약과 **같은 규칙**을 쓴다
// (수단은 앱이 고르고 상태는 서버가 정한다). 전이 규칙도 depositFlow 하나를
// 공유하며, 장소대여 전용 상태 머신은 만들지 않는다.
const { buildPaymentInfo } = require('./paymentInfo');
// 호스트 수취계좌 — 무통장입금 안내 계좌는 이 값 하나에서만 나온다.
const { loadPayoutSnapshot } = require('./payoutAccounts');
// 예약금 정책. 'upfront'(예약금)와 'deposit'(무통장입금)은 서로 다른 축이다 —
// paymentPolicy.js 상단 주석 참고.
const paymentPolicy = require('./paymentPolicy');
const flow = require('./depositFlow');
const rental = require('./placeReservationFlow');
const { pushNotification: pushReservationNotification } = require('./reservationNotifications');
// 본인확인 게이트 — 거래성 요청은 앱 UI와 무관하게 서버가 직접 확인한다.
const { assertIdentityVerified } = require('./identityGuard');

// 장소대여 예약 — 시간제/패키지/하루단위를 전부 "선택한 날짜 자정(KST) 기준
// 분(minute) 좌표의 시간 구간(window)" 하나의 개념으로 통일해 다룬다.
// 이렇게 하면 시간제 슬롯이 패키지 시간과 겹치는지, 하루단위 예약이 시간제
// 슬롯과 겹치는지를 전부 같은 겹침 판정 함수 하나로 처리할 수 있다(클라이언트
// place_detail_screen.dart의 _loadBooked/_hasConflict와 동일한 좌표계).
//
// applyToParty(index.js)와 동일한 onCall+transaction 패턴, deleteExpiredParties와
// 동일한 청크 배치 스케줄 패턴을 따른다. PortOne 호출은 geocodeSingle처럼 새
// npm 의존성 없이 raw https 모듈로 한다.
//
// ── 개인정보 분리 (중요) ─────────────────────────────────────────────────────
// 예약 데이터를 두 컬렉션으로 나눈다:
//   - places/{placeId}/reservationSlots/{slotId}: 시간대·상태만 담은 "공개"
//     문서 — 다른 이용자가 예약 가능 여부를 확인할 때 읽는 대상. 예약자
//     이름·연락처·인원·가격 등 개인정보/영업정보는 절대 넣지 않는다.
//   - placeReservationGroups/{groupId}: 예약자 정보·결제금액 등 전체 상세를
//     담은 "비공개" 문서 — 본인(requesterId)·해당 장소 호스트(hostId)·
//     관리자만 읽을 수 있다(firestore.rules).
// 두 문서는 groupId로 연결되고, 상태 전환(확정/취소/만료)은 항상 두 곳을
// 함께 갱신한다.
//
// ── 결제 흐름 (무통장입금·현장결제) ──────────────────────────────────────────
// PG 계약 전이라 실제로 받을 수 있는 수단은 무통장입금과 현장결제뿐이다.
// 그래서 방문예약(placeVisitReservations.js)과 **완전히 같은 흐름**을 쓴다:
//
//   자동승인 룸: 예약 즉시 confirmed + 입금대기(기한 시작)
//   승인제 룸:   requested(승인대기, 입금 불가) → 업주 승인 → confirmed + 입금대기
//   공통:        '입금했어요' → 입금확인중 → 업주 '입금 확인' → 결제완료
//   기한 초과:   예약 취소 + 시간 슬롯 반납
//
// 상태 전이 판정은 전부 depositFlow가 하고(파티·방문예약과 같은 모듈),
// "그 상태에서 슬롯을 언제까지 잡고 있어야 하나"만 placeReservationFlow가
// 정한다 — stay/hourly/package 모두 같은 슬롯 구조라 예약 방식별 분기가 없다.
//
// 옛 앱(결제수단을 보내지 않는 버전)은 지금까지의 포트원 10분 pending 흐름을
// 그대로 탄다 — 아래 createPendingReservation의 usesDepositFlow 분기 참고.

const portOneApiSecret = defineSecret('PORTONE_API_SECRET');

/** 알림 — 장소대여는 places 컬렉션 + placeReservationGroups를 가리킨다. */
function pushNotification(batchOrTx, db, args) {
  return pushReservationNotification(batchOrTx, db, {
    ...args,
    placeCollection: 'places',
    refCollection: 'placeReservationGroups',
  });
}

// ── 1. 예약 생성 (pending) ────────────────────────────────────────────────────

exports.createPendingReservation = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const uid = request.auth.uid;
    const db = admin.firestore();
    // 본인확인은 **다른 어떤 검증보다 먼저** 본다(identityGuard.js 참고).
    await assertIdentityVerified(db, uid);

    const data = request.data || {};
    const placeId = data.placeId;
    const roomId = data.roomId || null;
    const bookingType = data.bookingType;
    const dateStr = data.date;
    const peopleCount = Number(data.peopleCount) || 1;
    const requesterName = String(data.requesterName || '').trim();
    const requesterPhone = String(data.requesterPhone || '').trim();
    const requestMessage = String(data.requestMessage || '').trim();
    // 결제수단만 받는다 — 금액도 결제 상태도 서버가 정한다.
    const payment = data.payment;
    // 앱이 화면에 띄운 금액(총액/예약금/잔금). 정본은 서버 계산이고 이 값은
    // **대조용**이다 — 화면 금액과 실제 청구가 어긋난 채 진행되지 않게 한다.
    const amounts = data.amounts;

    if (!placeId || typeof placeId !== 'string') {
      throw new HttpsError('invalid-argument', 'placeId가 필요합니다.');
    }
    if (!['stay', 'hourly', 'package', 'daily'].includes(bookingType)) {
      throw new HttpsError('invalid-argument', 'bookingType이 올바르지 않습니다.');
    }
    if (!dateStr || typeof dateStr !== 'string') {
      throw new HttpsError('invalid-argument', 'date가 필요합니다.');
    }
    if (!requesterName || !requesterPhone) {
      throw new HttpsError('invalid-argument', '예약자 정보가 필요합니다.');
    }

    const midnight = kstMidnight(dateStr);
    const weekdayLabel = kstWeekdayLabel(midnight);
    const cfg = await loadReservationConfig(db, placeId, roomId);
    if (peopleCount > cfg.capacity) {
      throw new HttpsError('failed-precondition', '최대 인원을 초과했어요.');
    }

    const { windows, totalMinutes, packageId, packageName } = computeWindows(
      cfg,
      bookingType,
      { ...data, peopleCount, weekdayLabel },
    );
    const totalPrice = windows.reduce((sum, w) => sum + w.price, 0);

    const slotsRef = db.collection('places').doc(placeId).collection('reservationSlots');
    const groupRef = db.collection('placeReservationGroups').doc();
    const groupId = groupRef.id;
    const now = new Date();
    const expiresAt = new Date(now.getTime() + PENDING_TTL_MS);

    // ── 결제·승인 ─────────────────────────────────────────────────────
    // 결제수단을 보낸 앱이면 무통장입금/현장결제 흐름을 타고, 보내지 않은
    // 옛 앱이면 지금까지의 포트원 10분 pending 흐름을 그대로 탄다. 무료
    // 예약(0원)은 어느 쪽이든 결제 정보 없이 바로 자리를 잡는다.
    const usesDepositFlow = payment != null || totalPrice <= 0;
    const autoApprove = cfg.approvalMode === 'auto';
    const useAtMs = rental.useStartMs(midnight.getTime(), windows);
    const useEndAtMs = rental.useEndMs(midnight.getTime(), windows);

    // 승인제는 **승인 후 입금**이다: 승인 전에 받으면 거절 시 계좌로 수동
    // 환불해야 하는데 PG가 없어 자동 환불이 불가능하다. 입금기한은 이용
    // 시작 시각을 넘지 않는다(depositFlow가 잘라준다).
    //
    // 호스트 결제 정책 — 숙박/시간제 모두 예약 시점에 최종 이용요금(totalPrice)이
    // 확정되므로 비율 예약금·고정 예약금·전액 선결제를 전부 쓸 수 있다.
    // **비율 예약금은 반드시 이 totalPrice 기준으로 계산된다** — 숙박일수·
    // 요일별 가격·패키지가 이미 반영된 뒤의 금액이다(computeWindows 결과 합계).
    //
    // 정책이 없는 기존 장소는 policy가 null이라 지금까지와 완전히 동일하게
    // 동작한다(구매자가 무통장입금/현장결제를 자유 선택, 금액은 전액).
    const policy = totalPrice > 0 ? paymentPolicy.normalizePolicy(cfg.paymentPolicy) : null;
    const breakdown = paymentPolicy.computeBreakdown(policy, totalPrice);
    if (usesDepositFlow && totalPrice > 0) {
      paymentPolicy.assertMethodAllowed(policy, payment && payment.method);
      paymentPolicy.assertClientAmountMatches(breakdown, amounts);
    }

    const paymentInfo = usesDepositFlow
      ? buildPaymentInfo(payment, {
          // 이번에 받을 금액 — 예약금 방식이면 예약금만, 그 외에는 전액.
          amount: breakdown.paymentAmount,
          requireApproval: !autoApprove,
          useAtMs,
          // 무통장입금 안내 계좌 = 이 장소 호스트의 인증된 수취계좌.
          payoutAccount: await loadPayoutSnapshot(db, cfg.hostId),
        })
      : null;

    const groupStatus = usesDepositFlow
      ? (autoApprove ? rental.STATUS.confirmed : rental.STATUS.requested)
      : rental.STATUS.pending;
    const respondByMs = usesDepositFlow && !autoApprove
      ? rental.approvalDeadlineMs(now.getTime(), cfg.approvalHours, useAtMs)
      : null;

    // 이 예약이 시간 슬롯을 언제까지 잡고 있어야 하는지 — 예약 방식
    // (stay/hourly/package)과 무관하게 같은 규칙 하나가 정한다.
    const hold = usesDepositFlow
      ? rental.slotHoldOf(groupStatus, paymentInfo, { respondByMs })
      : { status: 'pending', expiresAtMs: expiresAt.getTime() };
    const holdExpiresAt = hold.expiresAtMs
      ? admin.firestore.Timestamp.fromMillis(hold.expiresAtMs)
      : null;

    // 겹침 판정에 필요한 조회 폭 — 기본은 앞뒤 하루(전날 밤부터 시작해
    // 다음날로 넘어가는 올나잇 패키지 등을 잡기 위해). 숙박을 받는 룸은 예약
    // 하나가 여러 날을 덮으므로, 이 날짜를 "관통하는" 장기 숙박까지 보이도록
    // 앞뒤를 크게 넓힌다(클라이언트 _loadBooked와 동일한 규칙).
    const supportsStay = cfg.reservationModes.includes('stay');
    const lookbackDays = supportsStay ? STAY_LOOKBACK_DAYS : 1;
    // 이번 예약이 실제로 뻗어나가는 마지막 지점까지는 반드시 조회 대상에
    // 들어가야 한다 — 2박 예약이면 최소 3일치.
    const maxWindowEnd = windows.reduce((m, w) => Math.max(m, w.end), 1440);
    const horizonDays = Math.ceil(maxWindowEnd / 1440);
    const DAY_MS = 24 * 60 * 60 * 1000;

    await db.runTransaction(async (transaction) => {
      // roomId 등호 필터는 걸지 않고(복합 색인 불필요) 조회 후 코드에서 거른다
      // — 클라이언트 _loadBooked와 동일한 방식.
      const queryStart = admin.firestore.Timestamp.fromDate(
        new Date(midnight.getTime() - lookbackDays * DAY_MS),
      );
      const queryEnd = admin.firestore.Timestamp.fromDate(
        new Date(midnight.getTime() + horizonDays * DAY_MS),
      );
      const snap = await transaction.get(
        slotsRef
          .where('startAt', '>=', queryStart)
          .where('startAt', '<', queryEnd),
      );

      const existingRanges = [];
      for (const doc of snap.docs) {
        const d = doc.data();
        const status = d.status || 'pending';
        if (status === 'cancelled' || status === 'expired') continue;
        if (status === 'pending' && d.expiresAt && d.expiresAt.toDate() < now) continue;
        if ((roomId || null) !== (d.roomId || null)) continue;
        const startAt = d.startAt && d.startAt.toDate();
        const endAt = d.endAt && d.endAt.toDate();
        if (!startAt || !endAt) continue;
        const startMin = Math.round((startAt.getTime() - midnight.getTime()) / 60000);
        const endMin = Math.round((endAt.getTime() - midnight.getTime()) / 60000);
        if (endMin <= 0 || startMin >= horizonDays * 1440 || startMin >= endMin) continue;
        existingRanges.push({ start: startMin, end: endMin });
      }

      for (const w of windows) {
        if (existingRanges.some((r) => windowsOverlap(w, r))) {
          throw new HttpsError('already-exists', '선택한 시간에 이미 예약이 있어요. 다른 시간을 선택해주세요.');
        }
      }

      // 공개 슬롯 문서 — 다른 이용자의 겹침 확인용. 시간대·상태 외에는
      // 아무것도 담지 않는다(개인정보/영업정보 전면 배제, firestore.rules에서
      // 누구나 읽을 수 있게 열어둔 이유이기도 하다).
      const reservationIds = [];
      for (const w of windows) {
        const ref = slotsRef.doc();
        reservationIds.push(ref.id);
        transaction.set(ref, {
          roomId,
          groupId,
          startAt: admin.firestore.Timestamp.fromDate(
            new Date(midnight.getTime() + w.start * 60000),
          ),
          endAt: admin.firestore.Timestamp.fromDate(
            new Date(midnight.getTime() + w.end * 60000),
          ),
          status: hold.status,
          expiresAt: holdExpiresAt,
        });
      }

      // 비공개 그룹 문서 — 예약자 정보·결제금액 등 전체 상세. 본인·해당 장소
      // 호스트·관리자만 읽을 수 있다(firestore.rules).
      transaction.set(groupRef, {
        placeId,
        placeName: cfg.placeName,
        roomId,
        roomName: cfg.roomName,
        hostId: cfg.hostId,
        bookingType,
        packageId,
        packageName,
        date: dateStr,
        // 숙박이면 몇 박인지 — 예약 내역 화면이 "N박"을 그대로 보여준다.
        nights: bookingType === 'stay' ? Number(data.nights) : null,
        totalMinutes,
        totalPrice,
        // 금액 스냅샷 — 예약 당시의 결제 방식·예약금·잔금을 그대로 얼려 둔다.
        // 호스트가 나중에 가격이나 예약금 비율을 바꿔도 이 예약의 금액은
        // 변하지 않는다(어떤 화면도 호스트 설정을 다시 읽어 재계산하지 않는다).
        amounts: paymentPolicy.snapshotOf(policy, totalPrice),
        peopleCount,
        requesterId: uid,
        requesterName,
        requesterPhone,
        requestMessage,
        reservationIds,
        status: groupStatus,
        approvalMode: cfg.approvalMode,
        autoApproved: usesDepositFlow ? autoApprove : null,
        // 이용 시각 — 승인 시점에 입금기한을 자를 때, 목록에서 "이용일시"를
        // 보여줄 때 쓴다(구간이 여러 개인 시간제는 처음~끝을 덮는다).
        useStartAt: useAtMs ? admin.firestore.Timestamp.fromMillis(useAtMs) : null,
        useEndAt: useEndAtMs ? admin.firestore.Timestamp.fromMillis(useEndAtMs) : null,
        ...(paymentInfo ? { payment: paymentInfo } : {}),
        hostMessage: '',
        respondBy: respondByMs
          ? admin.firestore.Timestamp.fromMillis(respondByMs)
          : null,
        // 포트원 10분 대기는 옛 흐름에만 있다 — 무통장입금 건에 이 값이 남아
        // 있으면 expireStalePlaceReservations가 24시간 기한을 무시하고
        // 10분 만에 지워버린다.
        expiresAt: usesDepositFlow
          ? null
          : admin.firestore.Timestamp.fromDate(expiresAt),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        decidedAt: usesDepositFlow && autoApprove
          ? admin.firestore.FieldValue.serverTimestamp()
          : null,
      });

      // 업주 알림 — 자동 승인이어도 "예약이 잡혔다"는 사실은 알려야 한다.
      if (usesDepositFlow && cfg.hostId) {
        pushNotification(transaction, db, {
          uid: cfg.hostId,
          role: 'host',
          type: autoApprove
            ? 'place_reservation_auto_confirmed'
            : 'place_reservation_requested',
          title: autoApprove ? '새 장소대여 예약이 확정됐어요' : '새 장소대여 예약 신청',
          body: `${cfg.placeName || '내 장소'} · ${dateStr} ${bookingSummary(bookingType, data, packageName)}`,
          placeId,
          refId: groupId,
        });
      }
    });

    return {
      groupId,
      totalPrice,
      totalMinutes,
      // 앱이 완료 안내에 "지금 결제할 예약금 / 현장 결제 잔금"을 그대로 쓴다.
      amounts: paymentPolicy.snapshotOf(policy, totalPrice),
      status: groupStatus,
      autoApproved: usesDepositFlow ? autoApprove : null,
      // 앱이 결과 안내를 고를 때 쓴다 — 승인대기인지, 바로 입금대기인지.
      paymentStatus: paymentInfo ? paymentInfo.status : null,
    };
  },
);

/** '숙박 2박' / '시간제 예약' / 패키지명 — 알림 문구에 쓰는 한 줄 요약. */
function bookingSummary(bookingType, data, packageName) {
  if (bookingType === 'stay') return `숙박 ${Number(data.nights) || 1}박`;
  if (bookingType === 'package') return packageName || '패키지';
  if (bookingType === 'daily') return '하루 단위 대여';
  return '시간제 예약';
}

// ── 2. 포트원 결제 검증 → 확정 ────────────────────────────────────────────────

exports.verifyAndConfirmReservation = onCall(
  { region: 'asia-northeast3', secrets: [portOneApiSecret] },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const uid = request.auth.uid;
    const groupId = request.data && request.data.groupId;
    if (!groupId || typeof groupId !== 'string') {
      throw new HttpsError('invalid-argument', 'groupId가 필요합니다.');
    }

    const db = admin.firestore();
    const groupRef = db.collection('placeReservationGroups').doc(groupId);
    const groupSnap = await groupRef.get();
    if (!groupSnap.exists) throw new HttpsError('not-found', '예약을 찾을 수 없어요.');
    const group = groupSnap.data();

    if (group.requesterId !== uid) {
      throw new HttpsError('permission-denied', '본인 예약만 확인할 수 있어요.');
    }
    // 이미 자리가 잡힌 건 — 재호출에도 안전(idempotent). 무통장입금 흐름으로
    // 만들어진 예약(confirmed/requested)은 애초에 포트원을 거치지 않으므로,
    // 옛 앱이 습관적으로 이 함수를 불러도 그냥 성공으로 돌려준다.
    if (group.status === 'confirmed' || group.status === 'requested') {
      return { success: true, status: group.status };
    }
    if (group.status !== 'pending') {
      throw new HttpsError('failed-precondition', '이미 취소되었거나 만료된 예약이에요.');
    }
    if (group.expiresAt && group.expiresAt.toDate() < new Date()) {
      throw new HttpsError('deadline-exceeded', '결제 대기 시간이 만료됐어요. 다시 예약해주세요.');
    }

    if (group.totalPrice > 0) {
      const verify = await verifyPortOnePayment(groupId, group.totalPrice, portOneApiSecret);
      if (!verify.ok) {
        console.error('[verifyAndConfirmReservation] 결제 검증 실패', verify);
        throw new HttpsError('failed-precondition', '결제 금액/상태가 일치하지 않습니다.');
      }
    }

    const placeId = group.placeId;
    const slotsRef = db.collection('places').doc(placeId).collection('reservationSlots');
    await db.runTransaction(async (transaction) => {
      const freshSnap = await transaction.get(groupRef);
      if (!freshSnap.exists || freshSnap.data().status !== 'pending') return;
      transaction.update(groupRef, {
        status: 'confirmed',
        paidAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      for (const id of group.reservationIds || []) {
        transaction.update(slotsRef.doc(id), { status: 'confirmed' });
      }
    });

    return { success: true };
  },
);

// ── 2-1. 업주 승인 / 거절 (승인제 룸) ────────────────────────────────────────
//
// 승인되는 순간이 곧 **입금 안내 시작**이다 — 그전까지 결제 상태는 '승인대기'
// 이고 이용자는 '입금했어요'를 누를 수 없다(depositFlow.assertCanMarkSent).
// 거절이면 결제 상태를 건드리지 않는다: 애초에 입금을 요구하지 않았고 받은
// 돈도 없다. 대신 잡아뒀던 시간 슬롯을 즉시 돌려준다.

exports.decidePlaceReservation = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const uid = request.auth.uid;
    const data = request.data || {};
    const groupId = String(data.groupId || '');
    const approve = data.approve === true;
    const hostMessage = String(data.hostMessage || '').trim().slice(0, 300);
    if (!groupId) throw new HttpsError('invalid-argument', 'groupId가 필요합니다.');

    const db = admin.firestore();
    const groupRef = db.collection('placeReservationGroups').doc(groupId);

    await db.runTransaction(async (transaction) => {
      const snap = await transaction.get(groupRef);
      if (!snap.exists) throw new HttpsError('not-found', '예약을 찾을 수 없어요.');
      const group = snap.data();
      if (group.hostId !== uid) {
        throw new HttpsError('permission-denied', '내 장소의 예약만 처리할 수 있어요.');
      }
      if (group.status !== rental.STATUS.requested) {
        throw new HttpsError('failed-precondition', '이미 처리된 예약이에요.');
      }

      // 승인되는 순간 무통장입금은 '승인대기 → 입금대기'가 되고 기한이
      // 시작된다(파티·방문예약과 같은 depositFlow.approvePatch).
      const approvePatch = approve
        ? flow.approvePatch(group.payment, Date.now(), {
            notAfterMs: group.useStartAt ? group.useStartAt.toMillis() : null,
          })
        : null;

      if (!approve) {
        transaction.update(groupRef, {
          status: rental.STATUS.rejected,
          hostMessage,
          decidedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        releaseSlots(transaction, db, group, 'cancelled');
      } else {
        // 승인 뒤의 결제 상태로 슬롯 점유를 다시 계산한다 — 무통장입금이면
        // 입금기한까지, 현장결제·무료면 기한 없이 확정으로 잡는다.
        const nextPayment = approvePatch
          ? { ...group.payment, ...approvePatch }
          : group.payment;
        transaction.update(groupRef, {
          status: rental.STATUS.confirmed,
          hostMessage,
          decidedAt: admin.firestore.FieldValue.serverTimestamp(),
          ...(approvePatch
            ? {
                'payment.status': approvePatch.status,
                'payment.depositDeadlineMs': approvePatch.depositDeadlineMs,
              }
            : {}),
        });
        applySlotHold(
          transaction,
          db,
          group,
          rental.slotHoldOf(rental.STATUS.confirmed, nextPayment),
        );
      }

      pushNotification(transaction, db, {
        uid: group.requesterId,
        role: 'guest',
        type: approve ? 'place_reservation_approved' : 'place_reservation_rejected',
        title: approve ? '장소대여 예약이 확정됐어요' : '장소대여 예약이 거절됐어요',
        body: `${group.placeName || '장소'} · ${group.date || ''}`
          + (hostMessage ? ` — ${hostMessage}` : '')
          // 승인과 동시에 입금대기가 시작됐다면 그 사실을 함께 알린다 —
          // 확정 알림만 보면 결제까지 끝난 줄 오해할 수 있다.
          + (approvePatch ? ' — 기한 내 입금하시면 예약이 유지돼요.' : ''),
        placeId: group.placeId,
        refId: groupId,
      });
    });

    return { success: true };
  },
);

// ── 2-2. 무통장입금 (이용자 '입금했어요' / 업주 '입금 확인') ──────────────────
//
// 전이 규칙은 파티 신청·방문예약과 **같은 모듈**(depositFlow)을 쓴다. 여기서는
// 예약 문서를 그 규칙에 끼워 넣고, 상태가 바뀔 때마다 시간 슬롯 점유를 다시
// 계산해 반영하는 것만 한다.
//
// 파티와 다른 점: 장소대여는 **입금 확인이 곧 승인이 아니다**. 승인은 업주가
// 이미 했거나(승인제) 예약 즉시 자동으로 났고(자동승인), 입금 확인은 돈만
// 확인하는 절차라 status(confirmed)는 그대로 둔다.

exports.markPlaceDepositSent = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const uid = request.auth.uid;
    const groupId = String((request.data || {}).groupId || '');
    if (!groupId) throw new HttpsError('invalid-argument', 'groupId가 필요합니다.');

    const db = admin.firestore();
    const groupRef = db.collection('placeReservationGroups').doc(groupId);

    await db.runTransaction(async (transaction) => {
      const snap = await transaction.get(groupRef);
      if (!snap.exists) throw new HttpsError('not-found', '예약을 찾을 수 없어요.');
      const group = snap.data();
      if (group.requesterId !== uid) {
        throw new HttpsError('permission-denied', '내 예약만 처리할 수 있어요.');
      }
      // 트랜잭션 안에서 다시 읽은 값으로 판정한다 — 두 번 눌러도 두 번째는
      // 여기서 걸린다(중복 방지).
      flow.assertCanMarkSent(group.payment, rental.docContext(group));

      const patch = flow.markSentPatch(Date.now());
      transaction.update(groupRef, {
        'payment.status': patch.status,
        'payment.depositedAtMs': patch.depositedAtMs,
      });
      // 입금했다고 알린 순간 슬롯의 만료 기한을 없앤다 — 기한 직전에 누른
      // 사람의 자리가 몇 초 뒤 남에게 넘어가면 안 된다(자동 만료 대상에서도
      // 빠진다: depositFlow.isExpirable).
      applySlotHold(
        transaction,
        db,
        group,
        rental.slotHoldOf(rental.STATUS.confirmed, {
          ...group.payment,
          status: patch.status,
        }),
      );

      pushNotification(transaction, db, {
        uid: group.hostId,
        role: 'host',
        type: 'place_reservation_deposit_sent',
        title: '입금 확인 요청이 왔어요',
        body: `${group.placeName || '내 장소'} · ${group.date || ''} — `
          + `${group.requesterName || '예약자'}님이 입금했다고 알렸어요.`,
        placeId: group.placeId,
        refId: groupId,
      });
    });

    return { success: true, status: flow.STATUS.depositPending };
  },
);

exports.confirmPlaceDeposit = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const uid = request.auth.uid;
    const groupId = String((request.data || {}).groupId || '');
    if (!groupId) throw new HttpsError('invalid-argument', 'groupId가 필요합니다.');

    const db = admin.firestore();
    const groupRef = db.collection('placeReservationGroups').doc(groupId);

    await db.runTransaction(async (transaction) => {
      const snap = await transaction.get(groupRef);
      if (!snap.exists) throw new HttpsError('not-found', '예약을 찾을 수 없어요.');
      const group = snap.data();
      if (group.hostId !== uid) {
        throw new HttpsError('permission-denied', '내 장소의 예약만 처리할 수 있어요.');
      }
      flow.assertCanConfirm(group.payment, rental.docContext(group));

      const patch = flow.confirmPatch(Date.now(), uid);
      transaction.update(groupRef, {
        'payment.status': patch.status,
        'payment.paidAtMs': patch.paidAtMs,
        'payment.confirmedBy': patch.confirmedBy,
        paidAt: admin.firestore.FieldValue.serverTimestamp(),
        // 예약 진행 상태(status)는 건드리지 않는다 — 승인은 이미 끝났고,
        // 여기서는 돈만 확인한다.
      });
      applySlotHold(
        transaction,
        db,
        group,
        rental.slotHoldOf(rental.STATUS.confirmed, {
          ...group.payment,
          status: patch.status,
        }),
      );

      pushNotification(transaction, db, {
        uid: group.requesterId,
        role: 'guest',
        type: 'place_reservation_deposit_confirmed',
        title: '입금이 확인됐어요',
        body: `${group.placeName || '장소'} · ${group.date || ''} — 예약이 확정 상태로 유지돼요.`,
        placeId: group.placeId,
        refId: groupId,
      });
    });

    return { success: true, status: flow.STATUS.paid };
  },
);

// ── 3. 예약 취소 ──────────────────────────────────────────────────────────────

exports.cancelReservation = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const uid = request.auth.uid;
    const data = request.data || {};
    const groupId = data.groupId;
    const message = String(data.message || '').trim().slice(0, 300);
    if (!groupId || typeof groupId !== 'string') {
      throw new HttpsError('invalid-argument', 'groupId가 필요합니다.');
    }

    const db = admin.firestore();
    const groupRef = db.collection('placeReservationGroups').doc(groupId);

    await db.runTransaction(async (transaction) => {
      const groupSnap = await transaction.get(groupRef);
      if (!groupSnap.exists) throw new HttpsError('not-found', '예약을 찾을 수 없어요.');
      const group = groupSnap.data();
      // 예약자 본인과 해당 장소 업주 둘 다 취소할 수 있다(방문예약과 같다).
      const isGuest = group.requesterId === uid;
      const isHost = group.hostId === uid;
      if (!isGuest && !isHost) {
        throw new HttpsError('permission-denied', '이 예약을 취소할 권한이 없어요.');
      }
      if (!rental.isLive(group.status)) return; // 이미 끝난 예약 — 조용히 통과

      transaction.update(groupRef, {
        status: rental.STATUS.cancelled,
        cancelledBy: isGuest ? 'guest' : 'host',
        hostMessage: isHost ? message : group.hostMessage || '',
        cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      releaseSlots(transaction, db, group, 'cancelled');

      // 취소는 상대방에게 알린다(내가 취소했으면 상대에게만).
      pushNotification(transaction, db, {
        uid: isGuest ? group.hostId : group.requesterId,
        role: isGuest ? 'host' : 'guest',
        type: 'place_reservation_cancelled',
        title: isGuest ? '장소대여 예약이 취소됐어요' : '장소가 예약을 취소했어요',
        body: `${group.placeName || '장소'} · ${group.date || ''}`
          + (isHost && message ? ` — ${message}` : ''),
        placeId: group.placeId,
        refId: groupId,
      });
    });

    return { success: true };
  },
);

// ── 4. pending 예약 자동 만료 (5분마다) ───────────────────────────────────────

exports.expireStalePlaceReservations = onSchedule(
  { schedule: 'every 5 minutes', timeZone: 'Asia/Seoul', region: 'asia-northeast3' },
  async () => {
    const db = admin.firestore();
    try {
      const now = admin.firestore.Timestamp.now();
      const snap = await db.collection('placeReservationGroups')
        .where('status', '==', 'pending')
        .where('expiresAt', '<', now)
        .get();

      console.log(`[expireStalePlaceReservations] 만료 대상 ${snap.size}건`);

      const CHUNK = 100; // 그룹당 예약 문서 수까지 감안해 넉넉히 작게 청크
      const groups = snap.docs;
      for (let i = 0; i < groups.length; i += CHUNK) {
        const batch = db.batch();
        for (const doc of groups.slice(i, i + CHUNK)) {
          batch.update(doc.ref, { status: 'expired' });
          releaseSlots(batch, db, doc.data(), 'expired');
        }
        await batch.commit();
      }

      console.log(`[expireStalePlaceReservations] 완료 — ${groups.length}개 그룹 만료 처리`);
    } catch (e) {
      await logScheduledFunctionError(db, 'expireStalePlaceReservations', e);
      throw e; // Cloud Scheduler 재시도/실패 기록은 기존과 동일하게 유지
    }
  },
);

// ── 5. 입금기한 초과 정리 (10분마다) ─────────────────────────────────────────
//
// 기한이 지나도록 **입금대기**인 예약은 시간 슬롯을 반납하고 취소한다.
// '입금확인중'은 대상이 아니다(파티·방문예약과 같은 정책) — 이용자는 입금했다고
// 알렸는데 업주 확인이 늦은 것뿐일 수 있어, 자동 취소하면 이미 낸 사람의 자리를
// 뺏게 된다. 그 건은 업주가 예약 관리 화면에서 직접 처리한다.
//
// 포트원 10분 만료(expireStalePlaceReservations)와는 **대상이 다르다** —
// 그쪽은 status가 'pending'인 옛 흐름이고, 이쪽은 확정된 무통장입금 건이다.

exports.expirePlaceReservationDeposits = onSchedule(
  { schedule: 'every 10 minutes', timeZone: 'Asia/Seoul', region: 'asia-northeast3' },
  async () => {
    const db = admin.firestore();
    try {
      const nowMs = Date.now();
      const snap = await db
        .collection('placeReservationGroups')
        .where('payment.status', '==', flow.STATUS.awaitingDeposit)
        .where('payment.depositDeadlineMs', '<', nowMs)
        .get();

      console.log(`[expirePlaceReservationDeposits] 만료 대상 ${snap.size}건`);

      for (const doc of snap.docs) {
        try {
          await db.runTransaction(async (transaction) => {
            const fresh = await transaction.get(doc.ref);
            if (!fresh.exists) return;
            const group = fresh.data();
            // 그 사이에 입금했다고 알렸거나 확인이 끝났으면 건드리지 않는다.
            if (!flow.isExpirable(group.payment, nowMs)) return;
            if (!rental.isLive(group.status)) return;

            const expired = flow.expirePatch(nowMs);
            transaction.update(doc.ref, {
              'payment.status': expired.status,
              'payment.cancelledAtMs': expired.cancelledAtMs,
              status: rental.STATUS.expired,
              cancelReason: 'deposit_expired',
              expiredAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            releaseSlots(transaction, db, group, 'expired');

            pushNotification(transaction, db, {
              uid: group.requesterId,
              role: 'guest',
              type: 'place_reservation_deposit_expired',
              title: '장소대여 예약이 취소됐어요',
              body: `${group.placeName || '장소'} · ${group.date || ''} — 입금기한이 지나 자동 취소됐어요.`,
              placeId: group.placeId,
              refId: doc.id,
            });
          });
        } catch (e) {
          console.error(`[expirePlaceReservationDeposits] ${doc.ref.path} 실패: ${e.message}`);
        }
      }
    } catch (e) {
      await logScheduledFunctionError(db, 'expirePlaceReservationDeposits', e);
    }
  },
);

// ── 6. 업주 무응답 승인 요청 자동 만료 (10분마다) ────────────────────────────
//
// 승인제 룸에 신청해뒀는데 업주가 기한 안에 응답하지 않은 건 — 잡아둔 시간을
// 계속 죽여둘 수 없으므로 반납한다. 아직 입금을 요구한 적이 없으므로 돌려줄
// 돈도 없다(결제 상태는 '승인대기' 그대로 두고 예약만 만료시킨다).

exports.expireStalePlaceReservationApprovals = onSchedule(
  { schedule: 'every 10 minutes', timeZone: 'Asia/Seoul', region: 'asia-northeast3' },
  async () => {
    const db = admin.firestore();
    try {
      const now = admin.firestore.Timestamp.now();
      const snap = await db
        .collection('placeReservationGroups')
        .where('status', '==', rental.STATUS.requested)
        .where('respondBy', '<', now)
        .get();

      console.log(`[expireStalePlaceReservationApprovals] 만료 대상 ${snap.size}건`);

      const CHUNK = 100;
      for (let i = 0; i < snap.docs.length; i += CHUNK) {
        const batch = db.batch();
        for (const doc of snap.docs.slice(i, i + CHUNK)) {
          const group = doc.data();
          batch.update(doc.ref, {
            status: rental.STATUS.expired,
            cancelReason: 'approval_timeout',
            expiredAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          releaseSlots(batch, db, group, 'expired');
          pushNotification(batch, db, {
            uid: group.requesterId,
            role: 'guest',
            type: 'place_reservation_expired',
            title: '장소대여 예약 신청이 만료됐어요',
            body: `${group.placeName || '장소'} · ${group.date || ''} — 업주 응답이 없어 자동 취소됐어요.`,
            placeId: group.placeId,
            refId: doc.id,
          });
        }
        await batch.commit();
      }
    } catch (e) {
      await logScheduledFunctionError(db, 'expireStalePlaceReservationApprovals', e);
    }
  },
);

// ── 공통: 시간 슬롯 점유 ─────────────────────────────────────────────────────
//
// 예약 1건이 잡고 있는 슬롯 문서들을 한 번에 다룬다. stay(한 덩어리 구간) ·
// hourly(구간 여러 개) · package(자정을 넘길 수 있는 한 구간)가 전부 같은
// reservationIds 배열로 표현되므로, 예약 방식별 분기가 필요 없다 — 재고 복구가
// 세 방식에서 완전히 같은 이유다.

/** 예약이 잡고 있던 시간 슬롯을 돌려준다(취소·거절·만료 공통). */
function releaseSlots(batchOrTx, db, group, status) {
  const ids = group.reservationIds || [];
  if (!ids.length || !group.placeId) return;
  const slotsRef = db.collection('places').doc(group.placeId).collection('reservationSlots');
  for (const id of ids) {
    // update가 아니라 merge set을 쓴다 — 슬롯 문서가 이미 지워졌더라도
    // 트랜잭션 전체가 실패하지 않게(방문예약 releaseSlots와 같은 방침).
    batchOrTx.set(slotsRef.doc(id), { status, expiresAt: null }, { merge: true });
  }
}

/** [placeReservationFlow.slotHoldOf]가 계산한 점유 상태를 슬롯에 반영한다. */
function applySlotHold(batchOrTx, db, group, hold) {
  if (!hold) return;
  const ids = group.reservationIds || [];
  if (!ids.length || !group.placeId) return;
  const slotsRef = db.collection('places').doc(group.placeId).collection('reservationSlots');
  const expiresAt = hold.expiresAtMs
    ? admin.firestore.Timestamp.fromMillis(hold.expiresAtMs)
    : null;
  for (const id of ids) {
    batchOrTx.set(slotsRef.doc(id), { status: hold.status, expiresAt }, { merge: true });
  }
}

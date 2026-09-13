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
const {
  computeRefund,
  snapshotRefundPolicy,
  effectiveRefundPolicy,
  reserveApplicantSlot,
  releaseApplicantSlot,
  applicationDocId,
} = require('./partyCapacity');
const {
  effectivePartyStartAt,
  isRecurringParty,
  occurrenceForId,
} = require('./partySchedule');
const { logScheduledFunctionError } = require('./memberActivityHelpers');
// 결제는 파티 신청·방문예약·장소대여와 **같은 모듈**을 쓴다. 콤보 전용 결제
// 상태 머신은 만들지 않는다 — 상태 전이는 depositFlow, 수단 검증·초기 상태는
// paymentInfo, 슬롯 점유 기간은 placeReservationFlow가 정한다.
const { buildPaymentInfo } = require('./paymentInfo');
// 호스트 수취계좌 — 무통장입금 안내 계좌는 이 값 하나에서만 나온다.
const { loadPayoutSnapshot } = require('./payoutAccounts');
// 예약금 정책 · 실결제액 계산. 'upfront'(예약금)와 'deposit'(무통장입금)은
// 서로 다른 축이다 — paymentPolicy.js 상단 주석 참고.
const paymentPolicy = require('./paymentPolicy');
const flow = require('./depositFlow');
const rental = require('./placeReservationFlow');
const { pushNotification: pushReservationNotification } = require('./reservationNotifications');
// 본인확인 게이트 — 거래성 요청은 앱 UI와 무관하게 서버가 직접 확인한다.
const { assertIdentityVerified } = require('./identityGuard');

// 숙박+파티 패키지 예약 — party_place_combo_register_screen.dart로 등록한
// 콤보(`places.packageBookingEnabled === true`)에서만 쓰이는 통합 예약/결제.
// 기존 개별 "숙박 예약"(placeReservations.js)과 "파티 신청"(index.js의
// applyToParty/cancelApplication)은 전혀 건드리지 않고 그대로 유지한 채,
// 두 로직(방 시간대 겹침 검증 + 파티 정원/자격 검증)을 하나의 트랜잭션
// 안에서 함께 수행해 "한쪽만 생기는" 상황을 방지한다.
//
// 데이터 모델 — placeReservationGroups를 별도로 만들지 않는다. 패키지 예약
// 1건의 단일 진실 소스는 packageBookings/{bundleBookingId} 하나뿐이고, 방
// 시간대는 기존 places/{placeId}/reservationSlots 서브컬렉션을 그대로
// 재사용하되 슬롯의 groupId 필드에 bundleBookingId를 넣어 연결한다.
//
// 파티 쪽 정원은 결제 전(pending) 단계에서 이미 선점한다 — 방 슬롯이
// pending 상태로 즉시 다른 이용자의 겹침 후보에서 제외되는 것과 동일한
// 이유다(10분 결제 대기 동안 자리를 확실히 잡아두지 않으면, 결제까지 마친
// 뒤에야 "정원이 찼어요"로 실패할 수 있음). 그래서
// parties/{partyId}/applications/{uid} 문서 자체는 **자리가 확정되는 시점**에만
// 만들어지지만, 정원 카운터(currentParticipants 등)는 pending 생성 시점에
// 이미 반영돼 있다.
//
// ── 결제 흐름 (무통장입금·현장결제) ──────────────────────────────────────────
// PG 계약 전이라 실제로 받을 수 있는 수단은 무통장입금과 현장결제뿐이고,
// 흐름은 장소대여·방문예약과 **완전히 같다**(depositFlow 공유):
//
//   자동승인 룸: 예약 즉시 confirmed + 입금대기(기한 시작)
//   승인제 룸:   requested(승인대기, 입금 불가) → 업주 승인 → confirmed + 입금대기
//   공통:        '입금했어요' → 입금확인중 → 업주 '입금 확인' → 결제완료
//
// **콤보에만 있는 불변식** — 장소 슬롯과 파티 정원은 언제나 함께 움직인다.
// 하나만 풀리면 "방은 비었는데 파티 정원은 찬" 상태가 되므로, 반납은 반드시
// prepareBundleRelease/applyBundleRelease 한 쌍을 통해서만 한다(거절·취소·
// 승인기한 만료·입금기한 만료 네 경로가 모두 같은 함수를 부른다).
//
// 입금기한 만료는 **입금대기(awaiting_deposit)만** 대상이다 — '입금했어요'를
// 누른 뒤(deposit_pending)에는 슬롯도 정원도 절대 풀리지 않는다
// (depositFlow.isExpirable + placeReservationFlow.slotHoldOf가 같은 판정을 한다).
//
// ── 결제 상태의 단일 진실 소스 ───────────────────────────────────────────────
// 콤보의 payment 맵은 packageBookings 문서에만 둔다. 신청 문서
// (applications/{uid})에는 **일부러 복사하지 않는다** — 복사하면
// markPartyDepositSent/confirmPartyDeposit(파티 단독 신청용)이 신청 문서만
// 바꾸거나, expirePartyDeposits가 신청만 취소해 파티 정원만 반납하고 장소
// 슬롯은 남기는 사고가 난다. payment 맵이 없으면 그 함수들의 사전조건
// (depositFlow.bankPaymentOf)에서 자연스럽게 걸러진다.

const KST_OFFSET_MS = 9 * 60 * 60 * 1000;

/** 알림 — 콤보는 places 컬렉션 + packageBookings를 가리킨다. */
function pushNotification(batchOrTx, db, args) {
  return pushReservationNotification(batchOrTx, db, {
    ...args,
    placeCollection: 'places',
    refCollection: 'packageBookings',
  });
}

function kstDateStr(date) {
  const kst = new Date(date.getTime() + KST_OFFSET_MS);
  const y = kst.getUTCFullYear();
  const m = String(kst.getUTCMonth() + 1).padStart(2, '0');
  const d = String(kst.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function kstParts(date) {
  const kst = new Date(date.getTime() + KST_OFFSET_MS);
  const utcDay = kst.getUTCDay(); // 0=일 ~ 6=토
  return {
    dateKey: kstDateStr(date),
    hour: kst.getUTCHours(),
    dayOfWeek: utcDay === 0 ? 7 : utcDay, // 1=월 ~ 7=일로 변환
  };
}

const portOneApiSecret = defineSecret('PORTONE_API_SECRET');

// ── 1. 패키지 예약 생성 (pending — 방 슬롯 + 파티 정원을 함께 선점) ────────────

exports.createPendingPackageBooking = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const uid = request.auth.uid;
    const db = admin.firestore();
    // 본인확인은 **다른 어떤 검증보다 먼저** 본다 — 미인증 요청은 장소/파티
    // 문서를 읽을 필요도, 자리를 잡을 필요도 없다(identityGuard.js 참고).
    await assertIdentityVerified(db, uid);

    const data = request.data || {};
    const placeId = data.placeId;
    const roomId = data.roomId || null;
    const partyId = data.partyId;
    const bookingType = data.bookingType;
    const peopleCount = Number(data.peopleCount) || 1;
    const requesterName = String(data.requesterName || '').trim();
    const requesterPhone = String(data.requesterPhone || '').trim();
    const requestMessage = String(data.requestMessage || '').trim();
    const selectedRounds = data.selectedRounds;
    // 결제수단만 받는다 — 금액도 결제 상태도 서버가 정한다.
    const payment = data.payment;

    if (!placeId || typeof placeId !== 'string') {
      throw new HttpsError('invalid-argument', 'placeId가 필요합니다.');
    }
    if (!partyId || typeof partyId !== 'string') {
      throw new HttpsError('invalid-argument', 'partyId가 필요합니다.');
    }
    if (!['stay', 'hourly', 'package', 'daily'].includes(bookingType)) {
      throw new HttpsError('invalid-argument', 'bookingType이 올바르지 않습니다.');
    }
    if (!requesterName || !requesterPhone) {
      throw new HttpsError('invalid-argument', '예약자 정보가 필요합니다.');
    }
    if (selectedRounds !== undefined) {
      const valid =
        Array.isArray(selectedRounds) &&
        selectedRounds.length > 0 &&
        selectedRounds.every((n) => Number.isInteger(n) && n > 0);
      if (!valid) {
        throw new HttpsError('invalid-argument', 'selectedRounds가 올바르지 않습니다.');
      }
    }

    // ── 콤보 연결 검증 — 임의의 place/party 조합으로 패키지 예약을 만들 수
    // 없도록, 두 문서가 실제로 서로를 가리키고 패키지 예약이 켜져 있는지
    // 확인한다.
    const placeSnap = await db.collection('places').doc(placeId).get();
    if (!placeSnap.exists) throw new HttpsError('not-found', '장소를 찾을 수 없어요.');
    const placeDoc = placeSnap.data();
    if (placeDoc.linkedPartyId !== partyId || placeDoc.packageBookingEnabled !== true) {
      throw new HttpsError('failed-precondition', '패키지 예약이 불가능한 조합이에요.');
    }

    const partyForDateSnap = await db.collection('parties').doc(partyId).get();
    if (!partyForDateSnap.exists) throw new HttpsError('not-found', '파티를 찾을 수 없어요.');
    const partyForDate = partyForDateSnap.data();
    // 오픈예정 파티는 어떤 경로로도 예약·결제를 받지 않는다. 파티 신청은
    // reserveApplicantSlot이 막지만(partyCapacity.js), 패키지 예약은 그
    // 경로를 타지 않으므로 여기서 따로 막는다. 필드가 없던 기존 파티는
    // 'open'으로 간주되어 그대로 통과한다(partyOpenState.js 참고).
    if (partyForDate.openState === 'preopen') {
      throw new HttpsError('failed-precondition', '아직 오픈 전인 파티입니다.');
    }
    // 정기 파티는 저장된 partyDateTime이 첫 회차라 그대로 쓰면 과거 날짜로
    // 숙박을 잡게 된다 — 지금 기준 다음 회차 날짜를 쓴다(일회성은 저장값 그대로).
    // ── 참석 회차 확정 ────────────────────────────────────────────────────
    //
    // 콤보는 "파티 날짜 = 숙박 날짜"라 어느 회차에 가느냐가 곧 어느 날 묵느냐다.
    // 정기 파티는 회차가 여럿이므로 앱이 고른 회차를 받되, **그 값을 그대로
    // 믿지 않는다** — 저장된 recurringSchedule로 서버가 그 날짜의 회차를 다시
    // 계산해서 실제로 열리는 회차인지 확인한다(조작된 요청으로 열리지도 않는
    // 날짜에 예약이 생기면 안 된다).
    //
    // 회차를 지정하지 않으면 이 예약이 어느 날 파티에 대한 것인지 데이터로
    // 남지 않고 정원도 회차 칸에 잡히지 않는다 — 정기 파티는 회차 없이
    // 예약이 만들어지는 상태를 허용하지 않는다(옛 앱은 아래 폴백을 탄다).
    const requestedOccurrenceId = data.occurrenceId;
    if (
      requestedOccurrenceId !== undefined &&
      requestedOccurrenceId !== null &&
      typeof requestedOccurrenceId !== 'string'
    ) {
      throw new HttpsError('invalid-argument', 'occurrenceId가 올바르지 않습니다.');
    }

    let comboOccurrence = null;
    let comboOccurrenceId = null;
    let partyDateTime;

    if (isRecurringParty(partyForDate)) {
      // 앱이 회차를 보내지 않았으면(옛 앱) 지금 기준 다음 회차로 폴백한다 —
      // 예약 자체를 막으면 업데이트 전 앱이 통째로 죽는다.
      const fallbackStart = effectivePartyStartAt(partyForDate, new Date());
      const wantedId = requestedOccurrenceId
        || (fallbackStart ? kstDateStr(fallbackStart) : null);
      if (!wantedId) {
        throw new HttpsError('failed-precondition', '남아 있는 파티 회차가 없어요.');
      }
      comboOccurrence = occurrenceForId(partyForDate, wantedId);
      if (!comboOccurrence) {
        throw new HttpsError(
          'failed-precondition',
          '그 날짜에는 파티가 열리지 않아요. 다른 날짜를 선택해주세요.',
        );
      }
      // 이미 지났거나 모집이 닫힌 회차로는 예약을 만들지 않는다.
      const now = new Date();
      if (comboOccurrence.start.getTime() <= now.getTime()) {
        throw new HttpsError('failed-precondition', '이미 지난 회차예요.');
      }
      if (comboOccurrence.deadline && comboOccurrence.deadline.getTime() < now.getTime()) {
        throw new HttpsError('failed-precondition', '그 회차는 모집이 마감됐어요.');
      }
      if (
        comboOccurrence.recruitOpenAt &&
        comboOccurrence.recruitOpenAt.getTime() > now.getTime()
      ) {
        throw new HttpsError('failed-precondition', '그 회차는 아직 모집 시작 전이에요.');
      }
      comboOccurrenceId = wantedId;
      partyDateTime = comboOccurrence.start;
    } else {
      // 일회성 파티는 저장된 날짜 하나뿐이라 고를 것이 없다 — 예전 그대로다.
      // 앱이 회차를 보냈어도 이 파티에는 회차가 없으므로 무시한다.
      partyDateTime = effectivePartyStartAt(partyForDate, new Date());
    }

    if (!partyDateTime) {
      throw new HttpsError('failed-precondition', '파티 날짜 정보가 올바르지 않아요.');
    }

    // 숙박 날짜 = 확정된 파티 회차의 날짜.
    const dateStr = kstDateStr(partyDateTime);
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
    const roomPrice = windows.reduce((sum, w) => sum + w.price, 0);

    // users/{uid}는 Admin SDK로만 읽으므로 클라이언트가 gender/birthYear를
    // 위조할 수 없다(applyToParty와 동일).
    const userDoc = await db.collection('users').doc(uid).get();
    const userData = userDoc.exists ? userDoc.data() : {};
    const gender = userData.gender || null;
    const birthYear = userData.birthYear != null ? Number(userData.birthYear) : null;

    const slotsRef = db.collection('places').doc(placeId).collection('reservationSlots');
    const partyRef = db.collection('parties').doc(partyId);
    const bundleRef = db.collection('packageBookings').doc();
    const bundleBookingId = bundleRef.id;
    const now = new Date();
    const expiresAt = new Date(now.getTime() + PENDING_TTL_MS);

    let partyFee = 0;
    let partyTitle = null;
    let effectiveSelectedRounds = null;
    // 차수 인원을 회차 칸에 올렸는지 — 예약 문서에 남겨 취소·만료가 같은 칸을
    // 되돌리게 한다(파티 단독 신청의 applications.roundCounterScope와 같은 값).
    let roundCounterScope = null;
    // 파티 참가비는 트랜잭션 안(reserveApplicantSlot)에서야 확정되므로, 결제
    // 정보도 그 뒤에 만들어진다 — 아래 트랜잭션에서 채운다.
    let paymentInfo = null;
    let groupStatus = rental.STATUS.pending;
    const autoApprove = cfg.approvalMode === 'auto';
    const useAtMs = rental.useStartMs(midnight.getTime(), windows);
    const useEndAtMs = rental.useEndMs(midnight.getTime(), windows);
    // 트랜잭션이 재시도돼도 기한이 흔들리지 않게 기준 시각을 고정한다.
    const nowMs = now.getTime();

    // 숙박은 예약 하나가 여러 날을 덮으므로 겹침 조회 폭을 넓힌다 —
    // createPendingReservation과 동일한 규칙.
    const supportsStay = cfg.reservationModes.includes('stay');
    const lookbackDays = supportsStay ? STAY_LOOKBACK_DAYS : 1;
    const maxWindowEnd = windows.reduce((m, w) => Math.max(m, w.end), 1440);
    const horizonDays = Math.ceil(maxWindowEnd / 1440);
    const DAY_MS = 24 * 60 * 60 * 1000;

    await db.runTransaction(async (transaction) => {
      // ① 방 시간대 겹침 검증 — createPendingReservation과 동일한 방식.
      const queryStart = admin.firestore.Timestamp.fromDate(
        new Date(midnight.getTime() - lookbackDays * DAY_MS),
      );
      const queryEnd = admin.firestore.Timestamp.fromDate(
        new Date(midnight.getTime() + horizonDays * DAY_MS),
      );
      const slotsSnap = await transaction.get(
        slotsRef
          .where('startAt', '>=', queryStart)
          .where('startAt', '<', queryEnd),
      );

      const existingRanges = [];
      for (const doc of slotsSnap.docs) {
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

      // ② 파티 정원/자격 검증 + 선점 — 실패 시 여기서 throw돼 트랜잭션
      // 전체가 롤백되므로 방 슬롯도 함께 만들어지지 않는다(원자성).
      const partySnap = await transaction.get(partyRef);
      if (!partySnap.exists) throw new HttpsError('not-found', '파티를 찾을 수 없어요');
      const partyData = partySnap.data();
      partyTitle = partyData.title || null;

      const reserved = reserveApplicantSlot(partyData, {
        uid,
        gender,
        birthYear,
        selectedRounds,
        // 정기 파티면 그 회차 칸에 자리를 잡는다 — 파티 단독 신청과 같은 규칙.
        occurrence: comboOccurrence,
        occurrenceId: comboOccurrenceId,
      });
      partyFee = reserved.appliedFee;
      effectiveSelectedRounds = reserved.effectiveSelectedRounds;
      roundCounterScope = reserved.roundCounterScope;
      transaction.update(partyRef, reserved.updateData);

      // ②-1 결제·승인 — 파티 참가비가 확정된 지금에야 총액을 알 수 있다.
      // 결제수단을 보낸 앱이면 무통장입금/현장결제 흐름을 타고, 보내지 않은
      // 옛 앱이면 지금까지의 포트원 10분 pending 흐름을 그대로 탄다.
      // 준비중인 수단(카드·간편결제·실시간계좌이체·가상계좌)은 buildPaymentInfo가
      // 여기서 거절하고, 그러면 트랜잭션 전체가 롤백돼 파티 정원 선점도 함께
      // 되돌아간다(부분 상태가 남지 않는다).
      const totalPrice = roomPrice + partyFee;
      const usesDepositFlow = payment != null || totalPrice <= 0;
      paymentInfo = usesDepositFlow
        ? buildPaymentInfo(payment, {
            amount: totalPrice,
            nowMs,
            requireApproval: !autoApprove,
            useAtMs,
            // 무통장입금 안내 계좌 = 이 장소 호스트의 인증된 수취계좌.
            payoutAccount: await loadPayoutSnapshot(db, cfg.hostId),
          })
        : null;
      groupStatus = usesDepositFlow
        ? (autoApprove ? rental.STATUS.confirmed : rental.STATUS.requested)
        : rental.STATUS.pending;
      const respondByMs = usesDepositFlow && !autoApprove
        ? rental.approvalDeadlineMs(nowMs, cfg.approvalHours, useAtMs)
        : null;

      // 이 예약이 방 슬롯을 언제까지 잡고 있어야 하는지 — 장소대여와 **같은
      // 규칙**을 쓴다. 파티 정원은 이 기간 내내 그대로 유지되고, 슬롯이 풀리는
      // 순간(만료 스케줄러)에만 함께 반납된다.
      const hold = usesDepositFlow
        ? rental.slotHoldOf(groupStatus, paymentInfo, { respondByMs })
        : { status: 'pending', expiresAtMs: expiresAt.getTime() };
      const holdExpiresAt = hold.expiresAtMs
        ? admin.firestore.Timestamp.fromMillis(hold.expiresAtMs)
        : null;

      // ③ 방 슬롯 — 개인정보 없는 공개 문서.
      const reservationIds = [];
      for (const w of windows) {
        const ref = slotsRef.doc();
        reservationIds.push(ref.id);
        transaction.set(ref, {
          roomId,
          groupId: bundleBookingId,
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

      // ④ packageBookings(비공개) — 패키지 예약 1건의 단일 진실 소스.
      transaction.set(bundleRef, {
        placeId,
        placeName: cfg.placeName,
        roomId,
        roomName: cfg.roomName,
        hostId: cfg.hostId,
        bookingType,
        packageId,
        packageName,
        nights: bookingType === 'stay' ? Number(data.nights) : null,
        totalMinutes,
        roomPrice,
        partyId,
        partyTitle,
        partyFee,
        totalPrice: roomPrice + partyFee,
        gender,
        selectedRounds: effectiveSelectedRounds,
        region: partyData.region || null,
        district: partyData.district || null,
        partyCategory: partyData.category || null,
        // 환불 규정 스냅샷 — 예약 시점 기준. 호스트가 파티 환불 규정을
        // 나중에 바꿔도 이 예약의 환불 조건은 변하지 않는다.
        refundPolicy: snapshotRefundPolicy(partyData),
        // 위에서 계산한 실제 참석 회차를 스냅샷으로 남긴다(정기 파티 대응).
        partyDateTime: admin.firestore.Timestamp.fromDate(partyDateTime),
        // 어느 회차에 대한 예약인지 — 승인·취소·만료가 전부 이 값으로 그
        // 회차의 신청 문서와 정원 칸을 되짚는다(일회성 파티는 null).
        occurrenceId: comboOccurrenceId,
        occurrenceStartAt: comboOccurrence
          ? admin.firestore.Timestamp.fromDate(comboOccurrence.start)
          : null,
        roundCounterScope,
        date: dateStr,
        useStartAt: useAtMs ? admin.firestore.Timestamp.fromMillis(useAtMs) : null,
        useEndAt: useEndAtMs ? admin.firestore.Timestamp.fromMillis(useEndAtMs) : null,
        peopleCount,
        requesterId: uid,
        requesterName,
        requesterPhone,
        requestMessage,
        reservationIds,
        status: groupStatus,
        approvalMode: cfg.approvalMode,
        autoApproved: usesDepositFlow ? autoApprove : null,
        ...(paymentInfo ? { payment: paymentInfo } : {}),
        hostMessage: '',
        respondBy: respondByMs
          ? admin.firestore.Timestamp.fromMillis(respondByMs)
          : null,
        // 포트원 10분 대기는 옛 흐름에만 있다 — 무통장입금 건에 이 값이 남아
        // 있으면 expireStalePackageBookings가 24시간 기한을 무시하고 10분 만에
        // 정원과 슬롯을 반납해버린다.
        expiresAt: usesDepositFlow
          ? null
          : admin.firestore.Timestamp.fromDate(expiresAt),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        decidedAt: usesDepositFlow && autoApprove
          ? admin.firestore.FieldValue.serverTimestamp()
          : null,
      });

      // ⑤ 신청 문서 — **자리가 확정된 경우에만** 만든다.
      //
      // 옛 흐름은 결제 확정 시점에 만들었지만, 무통장입금은 확정까지 최대
      // 24시간이 걸린다. 그동안 파티 정원 카운터만 +1이고 신청자 목록에는
      // 아무도 없는 구간이 생기면 호스트가 정원을 맞출 수 없다. 그래서
      // "자리를 잡은 순간"(자동승인=지금 / 승인제=승인 시점)에 만든다 —
      // 파티 단독 신청의 무통장입금(applied + 입금대기 → approved)과 같은 의미다.
      if (usesDepositFlow && autoApprove) {
        transaction.set(
          partyRef
            .collection('applications')
            .doc(applicationDocId(uid, comboOccurrenceId)),
          buildApplicationDoc({
            uid,
            partyId,
            hostId: cfg.hostId,
            gender,
            partyFee,
            partyData,
            partyDateTime,
            selectedRounds: effectiveSelectedRounds,
            bundleBookingId,
            occurrenceId: comboOccurrenceId,
            occurrence: comboOccurrence,
            refundPolicy: snapshotRefundPolicy(partyData),
          }),
        );
      }

      if (usesDepositFlow && cfg.hostId) {
        pushNotification(transaction, db, {
          uid: cfg.hostId,
          role: 'host',
          type: autoApprove
            ? 'package_booking_auto_confirmed'
            : 'package_booking_requested',
          title: autoApprove ? '새 숙박+파티 예약이 확정됐어요' : '새 숙박+파티 예약 신청',
          body: `${cfg.placeName || '내 장소'} · ${partyTitle || '파티'} · ${dateStr}`,
          placeId,
          refId: bundleBookingId,
        });
      }
    });

    return {
      bundleBookingId,
      roomPrice,
      partyFee,
      totalPrice: roomPrice + partyFee,
      status: groupStatus,
      autoApproved: groupStatus === rental.STATUS.pending ? null : autoApprove,
      // 앱이 결과 안내를 고를 때 쓴다 — 승인대기인지, 바로 입금대기인지.
      paymentStatus: paymentInfo ? paymentInfo.status : null,
    };
  },
);

/**
 * 콤보 예약의 파티 신청 문서 — applyToParty가 만드는 것과 같은 shape에
 * **연결 필드 두 개**(source·bundleBookingId)를 더한 것이다. 호스트의 신청자
 * 화면은 콤보 참가자도 똑같이 보되, 이 두 필드로 "이 신청은 숙박+파티 패키지에
 * 딸려 온 것"임을 알 수 있다(결제·취소는 packageBookings 쪽에서 일어난다).
 *
 * **payment 맵은 일부러 넣지 않는다** — 파일 상단 '단일 진실 소스' 주석 참고.
 * 결제 상태를 여기 복사하면 파티 단독 신청용 함수들
 * (markPartyDepositSent/confirmPartyDeposit/expirePartyDeposits)이 이 문서만
 * 건드려 파티 정원만 반납하고 장소 슬롯은 남기는 사고가 난다. 대신 아래 연결
 * 필드를 따라가면 언제나 진짜 결제 상태를 찾을 수 있다.
 */
function buildApplicationDoc({
  uid,
  partyId,
  hostId,
  gender,
  partyFee,
  partyData,
  partyDateTime,
  selectedRounds,
  bundleBookingId,
  occurrenceId = null,
  occurrence = null,
  refundPolicy = null,
}) {
  const kst = partyDateTime ? kstParts(partyDateTime) : null;
  return {
    uid,
    partyId,
    // 정기 파티 콤보가 어느 회차의 것인지 — 파티 단독 신청과 같은 필드다
    // (취소·환불·집계가 전부 이 값으로 회차를 되짚는다).
    ...(occurrenceId
      ? {
          occurrenceId,
          ...(occurrence
            ? {
                occurrenceStartAt: admin.firestore.Timestamp.fromDate(occurrence.start),
                occurrenceEndAt: admin.firestore.Timestamp.fromDate(occurrence.end),
              }
            : {}),
        }
      : {}),
    hostId: hostId || null,
    status: 'applied',
    gender: gender || null,
    appliedFee: partyFee || 0,
    region: (partyData && partyData.region) || null,
    district: (partyData && partyData.district) || null,
    partyDateTime: partyDateTime
      ? admin.firestore.Timestamp.fromDate(partyDateTime)
      : null,
    partyDate: kst ? kst.dateKey : null,
    partyStartHour: kst ? kst.hour : null,
    dayOfWeek: kst ? kst.dayOfWeek : null,
    partyCategory: (partyData && partyData.category) || null,
    appliedAt: admin.firestore.FieldValue.serverTimestamp(),
    statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    confirmedAt: null,
    attendedAt: null,
    cancelledAt: null,
    // ── 연결 필드 ────────────────────────────────────────────────────────
    // source: 이 신청이 어디서 왔는지. 파티 단독 신청(applyToParty)에는 없으므로
    //   읽는 쪽은 "없으면 단독 신청"으로 본다(하위 호환).
    // bundleBookingId: packageBookings/{id} — 결제 상태·환불·취소의 진짜 출처.
    source: 'combo',
    bundleBookingId,
    ...(selectedRounds ? { selectedRounds } : {}),
    // 환불 규정 스냅샷 — 배열일 때만 쓴다. 스냅샷이 없는 옛 예약에서
    // 만들어진 신청 문서는 필드가 없고, 취소가 파티 현재 규정으로
    // 폴백한다(effectiveRefundPolicy).
    ...(Array.isArray(refundPolicy) ? { refundPolicy } : {}),
  };
}

// ── 2. 포트원 결제 검증 → 확정 ────────────────────────────────────────────────
//
// TODO(PG 재도입): 이 함수는 **아직 배포되지 않았다.**
//   환불 규정 스냅샷(2026-08-20)을 선택 배포할 때 applyToParty · cancelApplication ·
//   createPendingPackageBooking · decidePackageBooking · cancelPackageBooking 다섯 개만
//   올렸다. 이 함수도 아래 applicationDocOf를 공유하므로 같은 변경에 걸리지만,
//   PG 계약 전이라 앱·관리자 웹 어디에서도 호출하지 않는 휴면 경로여서 제외했다.
//   (지금 열려 있는 결제수단은 무통장입금·현장결제뿐 — paymentInfo.ENABLED_METHODS)
//
//   PG를 다시 붙일 때 반드시 이 함수를 함께 배포할 것. 그러지 않으면 카드 결제로
//   확정된 콤보의 신청 문서에만 refundPolicy 스냅샷이 빠져, 그 건의 취소가
//   예약 시점 규정이 아니라 파티의 **현재** 규정으로 계산된다.

exports.verifyAndConfirmPackageBooking = onCall(
  { region: 'asia-northeast3', secrets: [portOneApiSecret] },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const uid = request.auth.uid;
    const bundleBookingId = request.data && request.data.bundleBookingId;
    if (!bundleBookingId || typeof bundleBookingId !== 'string') {
      throw new HttpsError('invalid-argument', 'bundleBookingId가 필요합니다.');
    }

    const db = admin.firestore();
    const bundleRef = db.collection('packageBookings').doc(bundleBookingId);
    const bundleSnap = await bundleRef.get();
    if (!bundleSnap.exists) throw new HttpsError('not-found', '예약을 찾을 수 없어요.');
    const group = bundleSnap.data();

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
      const verify = await verifyPortOnePayment(bundleBookingId, group.totalPrice, portOneApiSecret);
      if (!verify.ok) {
        console.error('[verifyAndConfirmPackageBooking] 결제 검증 실패', verify);
        throw new HttpsError('failed-precondition', '결제 금액/상태가 일치하지 않습니다.');
      }
    }

    const slotsRef = db.collection('places').doc(group.placeId).collection('reservationSlots');
    // 회차별 신청 — 예약 문서에 남은 occurrenceId로 그 회차의 신청 문서를
    // 정확히 지목한다(일회성 파티는 예전 그대로 uid 하나다).
    const applicationRef = db.collection('parties').doc(group.partyId)
      .collection('applications')
      .doc(applicationDocId(uid, group.occurrenceId || null));

    await db.runTransaction(async (transaction) => {
      const freshSnap = await transaction.get(bundleRef);
      if (!freshSnap.exists || freshSnap.data().status !== 'pending') return;

      transaction.update(bundleRef, {
        status: 'confirmed',
        paidAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      for (const id of group.reservationIds || []) {
        transaction.update(slotsRef.doc(id), { status: 'confirmed' });
      }

      // 파티 정원은 pending 생성 시점에 이미 선점돼 있으므로 여기서는
      // applications 문서만 만든다.
      transaction.set(applicationRef, applicationDocOf(group, bundleBookingId));
    });

    return { success: true };
  },
);

/** 저장된 콤보 문서로 신청 문서를 만든다 — 승인·확정 시점이 공유한다. */
function applicationDocOf(group, bundleBookingId) {
  const partyDateTime =
    group.partyDateTime && typeof group.partyDateTime.toDate === 'function'
      ? group.partyDateTime.toDate()
      : null;
  return buildApplicationDoc({
    uid: group.requesterId,
    partyId: group.partyId,
    hostId: group.hostId,
    gender: group.gender,
    partyFee: group.partyFee,
    partyData: {
      region: group.region,
      district: group.district,
      category: group.partyCategory,
    },
    partyDateTime,
    selectedRounds: group.selectedRounds,
    refundPolicy: Array.isArray(group.refundPolicy) ? group.refundPolicy : null,
    bundleBookingId,
  });
}

// ── 2-1. 업주 승인 / 거절 (승인제 룸) ────────────────────────────────────────
//
// 승인되는 순간이 곧 **입금 안내 시작**이다 — 그전까지 결제 상태는 '승인대기'
// 이고 이용자는 '입금했어요'를 누를 수 없다.
//
// 거절이면 **방 슬롯과 파티 정원을 함께** 반납한다(applyBundleRelease). 아직
// 입금을 요구한 적이 없으므로 돌려줄 돈은 없다.

exports.decidePackageBooking = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const uid = request.auth.uid;
    const data = request.data || {};
    const bundleBookingId = String(data.bundleBookingId || '');
    const approve = data.approve === true;
    const hostMessage = String(data.hostMessage || '').trim().slice(0, 300);
    if (!bundleBookingId) {
      throw new HttpsError('invalid-argument', 'bundleBookingId가 필요합니다.');
    }

    const db = admin.firestore();
    const bundleRef = db.collection('packageBookings').doc(bundleBookingId);

    await db.runTransaction(async (transaction) => {
      const snap = await transaction.get(bundleRef);
      if (!snap.exists) throw new HttpsError('not-found', '예약을 찾을 수 없어요.');
      const group = snap.data();
      if (group.hostId !== uid) {
        throw new HttpsError('permission-denied', '내 장소의 예약만 처리할 수 있어요.');
      }
      if (group.status !== rental.STATUS.requested) {
        throw new HttpsError('failed-precondition', '이미 처리된 예약이에요.');
      }

      // 거절이면 정원·신청 문서를 되돌려야 하므로 읽기를 먼저 끝낸다
      // (Firestore 트랜잭션은 모든 읽기가 모든 쓰기보다 앞서야 한다).
      const release = approve ? null : await prepareBundleRelease(transaction, db, group);

      const approvePatch = approve
        ? flow.approvePatch(group.payment, Date.now(), {
            notAfterMs: group.useStartAt ? group.useStartAt.toMillis() : null,
          })
        : null;

      if (!approve) {
        transaction.update(bundleRef, {
          status: rental.STATUS.rejected,
          hostMessage,
          decidedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        applyBundleRelease(transaction, db, group, release, {
          slotStatus: 'cancelled',
          cancelledBy: 'host',
          cancelReason: 'rejected',
        });
      } else {
        const nextPayment = approvePatch
          ? { ...group.payment, ...approvePatch }
          : group.payment;
        transaction.update(bundleRef, {
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
        // 승인 = 자리 확정 — 이제야 신청 문서를 만든다(파티 정원은 예약
        // 생성 시점부터 이미 잡혀 있었다).
        transaction.set(
          db.collection('parties').doc(group.partyId)
            .collection('applications')
            .doc(applicationDocId(group.requesterId, group.occurrenceId || null)),
          applicationDocOf(group, bundleBookingId),
        );
      }

      pushNotification(transaction, db, {
        uid: group.requesterId,
        role: 'guest',
        type: approve ? 'package_booking_approved' : 'package_booking_rejected',
        title: approve ? '숙박+파티 예약이 확정됐어요' : '숙박+파티 예약이 거절됐어요',
        body: `${group.placeName || '장소'} · ${group.partyTitle || '파티'} · ${group.date || ''}`
          + (hostMessage ? ` — ${hostMessage}` : '')
          + (approvePatch ? ' — 기한 내 입금하시면 예약이 유지돼요.' : ''),
        placeId: group.placeId,
        refId: bundleBookingId,
      });
    });

    return { success: true };
  },
);

// ── 2-2. 무통장입금 (이용자 '입금했어요' / 업주 '입금 확인') ──────────────────
//
// 전이 판정은 전부 depositFlow가 한다. 콤보에서 특별한 것은 **'입금했어요'를
// 누른 순간 방 슬롯의 만료 기한을 없앤다**는 것뿐이다 — 기한이 지났다는 이유로
// 슬롯이 풀리면 그 뒤 만료 스케줄러가 파티 정원까지 반납해버리기 때문이다.

exports.markPackageDepositSent = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const uid = request.auth.uid;
    const bundleBookingId = String((request.data || {}).bundleBookingId || '');
    if (!bundleBookingId) {
      throw new HttpsError('invalid-argument', 'bundleBookingId가 필요합니다.');
    }

    const db = admin.firestore();
    const bundleRef = db.collection('packageBookings').doc(bundleBookingId);

    await db.runTransaction(async (transaction) => {
      const snap = await transaction.get(bundleRef);
      if (!snap.exists) throw new HttpsError('not-found', '예약을 찾을 수 없어요.');
      const group = snap.data();
      if (group.requesterId !== uid) {
        throw new HttpsError('permission-denied', '내 예약만 처리할 수 있어요.');
      }
      flow.assertCanMarkSent(group.payment, rental.docContext(group));

      const patch = flow.markSentPatch(Date.now());
      transaction.update(bundleRef, {
        'payment.status': patch.status,
        'payment.depositedAtMs': patch.depositedAtMs,
      });
      // 입금확인중은 기한 없는 점유다 — 여기서 슬롯 기한을 지우면 입금기한
      // 만료 스케줄러(입금대기만 대상)와 함께 "입금했는데 자리를 잃는" 경로가
      // 완전히 닫힌다. 파티 정원은 애초에 반납 경로에서만 풀리므로 그대로다.
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
        type: 'package_booking_deposit_sent',
        title: '입금 확인 요청이 왔어요',
        body: `${group.placeName || '내 장소'} · ${group.date || ''} — `
          + `${group.requesterName || '예약자'}님이 입금했다고 알렸어요.`,
        placeId: group.placeId,
        refId: bundleBookingId,
      });
    });

    return { success: true, status: flow.STATUS.depositPending };
  },
);

exports.confirmPackageDeposit = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const uid = request.auth.uid;
    const bundleBookingId = String((request.data || {}).bundleBookingId || '');
    if (!bundleBookingId) {
      throw new HttpsError('invalid-argument', 'bundleBookingId가 필요합니다.');
    }

    const db = admin.firestore();
    const bundleRef = db.collection('packageBookings').doc(bundleBookingId);

    await db.runTransaction(async (transaction) => {
      const snap = await transaction.get(bundleRef);
      if (!snap.exists) throw new HttpsError('not-found', '예약을 찾을 수 없어요.');
      const group = snap.data();
      if (group.hostId !== uid) {
        throw new HttpsError('permission-denied', '내 장소의 예약만 처리할 수 있어요.');
      }
      flow.assertCanConfirm(group.payment, rental.docContext(group));

      const patch = flow.confirmPatch(Date.now(), uid);
      transaction.update(bundleRef, {
        'payment.status': patch.status,
        'payment.paidAtMs': patch.paidAtMs,
        'payment.confirmedBy': patch.confirmedBy,
        paidAt: admin.firestore.FieldValue.serverTimestamp(),
        // 예약 진행 상태(confirmed)는 건드리지 않는다 — 승인은 이미 끝났고
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
      // 파티 신청도 확정으로 넘긴다 — 파티 단독 신청의 confirmPartyDeposit이
      // 하는 것과 같은 처리다(정원은 이미 잡혀 있으므로 손대지 않는다).
      transaction.update(
        db.collection('parties').doc(group.partyId)
          .collection('applications')
          .doc(applicationDocId(group.requesterId, group.occurrenceId || null)),
        {
          status: 'approved',
          confirmedAt: admin.firestore.FieldValue.serverTimestamp(),
          statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
      );

      pushNotification(transaction, db, {
        uid: group.requesterId,
        role: 'guest',
        type: 'package_booking_deposit_confirmed',
        title: '입금이 확인됐어요',
        body: `${group.placeName || '장소'} · ${group.partyTitle || '파티'} — 예약이 확정 상태로 유지돼요.`,
        placeId: group.placeId,
        refId: bundleBookingId,
      });
    });

    return { success: true, status: flow.STATUS.paid };
  },
);

// ── 3. 패키지 예약 취소 ──────────────────────────────────────────────────────

exports.cancelPackageBooking = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const uid = request.auth.uid;
    const data = request.data || {};
    const bundleBookingId = data.bundleBookingId;
    const message = String(data.message || '').trim().slice(0, 300);
    if (!bundleBookingId || typeof bundleBookingId !== 'string') {
      throw new HttpsError('invalid-argument', 'bundleBookingId가 필요합니다.');
    }

    const db = admin.firestore();
    const bundleRef = db.collection('packageBookings').doc(bundleBookingId);

    let result = { refundPercent: 0, refundAmount: 0, refundStatus: 'not_applicable' };

    await db.runTransaction(async (transaction) => {
      const bundleSnap = await transaction.get(bundleRef);
      if (!bundleSnap.exists) throw new HttpsError('not-found', '예약을 찾을 수 없어요.');
      const group = bundleSnap.data();
      // 예약자 본인과 해당 장소 업주 둘 다 취소할 수 있다(장소대여와 같다).
      const isGuest = group.requesterId === uid;
      const isHost = group.hostId === uid;
      if (!isGuest && !isHost) {
        throw new HttpsError('permission-denied', '이 예약을 취소할 권한이 없어요.');
      }
      if (!rental.isLive(group.status)) return; // 이미 끝난 예약 — 조용히 통과

      // 읽기를 전부 먼저 끝낸다(트랜잭션 순서 제약).
      const release = await prepareBundleRelease(transaction, db, group);

      // 실제로 **돈이 들어온** 예약만 환불을 계산한다. 확정(confirmed)이어도
      // 입금대기·입금확인중·현장결제 예정이면 받은 돈이 없다 — 예전에는
      // confirmed = 결제완료였지만 무통장입금이 붙으면서 두 축이 갈라졌다.
      const paid = isPaidBooking(group);
      if (paid) {
        // 패키지 총액 기준으로 환불액을 계산한다(방/파티를 나누지 않고 하나의
        // 환불 규정을 적용).
        // 예약 시점 스냅샷이 있으면 그것, 없으면(옛 예약) 파티의 현재 규정.
        const refundPolicy = effectiveRefundPolicy(
          group,
          release.partySnap.exists ? release.partySnap.data() : null,
        );
        // 환불액은 실제로 받은 돈을 넘지 않는다 — 예약금만 받은 예약을
        // 총액 기준으로 환불하면 받지 않은 돈을 돌려주게 된다.
        const refund = computeRefund(refundPolicy, group.totalPrice, group.partyDateTime, {
          paidAmount: paymentPolicy.paidAmountOf(group.payment, group.amounts),
        });
        result = refund;
        transaction.update(bundleRef, {
          status: rental.STATUS.cancelled,
          cancelledBy: isGuest ? 'user' : 'host',
          hostMessage: isHost ? message : group.hostMessage || '',
          cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
          refundPercent: refund.refundPercent,
          refundAmount: refund.refundAmount,
          refundStatus: refund.refundStatus,
          appliedRefundTier: refund.matchedTier,
        });
      } else {
        transaction.update(bundleRef, {
          status: rental.STATUS.cancelled,
          cancelledBy: isGuest ? 'user' : 'host',
          hostMessage: isHost ? message : group.hostMessage || '',
          cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      // 방 슬롯 + 파티 정원 + 신청 문서를 한 번에 되돌린다.
      applyBundleRelease(transaction, db, group, release, {
        slotStatus: 'cancelled',
        cancelledBy: isGuest ? 'user' : 'host',
        cancelReason: 'cancelled',
        refund: paid ? result : null,
      });

      // 취소는 상대방에게 알린다(내가 취소했으면 상대에게만).
      pushNotification(transaction, db, {
        uid: isGuest ? group.hostId : group.requesterId,
        role: isGuest ? 'host' : 'guest',
        type: 'package_booking_cancelled',
        title: isGuest ? '숙박+파티 예약이 취소됐어요' : '장소가 예약을 취소했어요',
        body: `${group.placeName || '장소'} · ${group.partyTitle || '파티'} · ${group.date || ''}`
          + (isHost && message ? ` — ${message}` : ''),
        placeId: group.placeId,
        refId: bundleBookingId,
      });
    });

    return { success: true, ...result };
  },
);

/**
 * 이 예약에 **실제로 돈이 들어왔는지**.
 *
 * 무통장입금은 업주가 확인해야(paid) 비로소 받은 것이고, 현장결제는 아직
 * 받지 않았다. payment 맵이 아예 없는 건은 옛 포트원 흐름이라 confirmed가
 * 곧 결제완료였다.
 */
function isPaidBooking(group) {
  if (!group.payment) return group.status === rental.STATUS.confirmed;
  return group.payment.status === flow.STATUS.paid;
}

// ── 4. pending 패키지 예약 자동 만료 (5분마다) ────────────────────────────────
//
// expireStalePlaceReservations(placeReservations.js)는 상태만 뒤집으면
// 끝이라 일괄 batch로 처리하지만, 패키지 예약은 파티 정원 카운터를 현재
// 문서 상태 기준으로 다시 계산해서 롤백해야 하므로(releaseApplicantSlot이
// 배열/객체 필드를 통째로 재계산) 건별 트랜잭션으로 처리한다.

exports.expireStalePackageBookings = onSchedule(
  { schedule: 'every 5 minutes', timeZone: 'Asia/Seoul', region: 'asia-northeast3' },
  async () => {
    const db = admin.firestore();
    try {
      const now = admin.firestore.Timestamp.now();
      const snap = await db.collection('packageBookings')
        .where('status', '==', 'pending')
        .where('expiresAt', '<', now)
        .get();

      console.log(`[expireStalePackageBookings] 만료 대상 ${snap.size}건`);

      for (const doc of snap.docs) {
        try {
          await db.runTransaction(async (transaction) => {
            const freshSnap = await transaction.get(doc.ref);
            if (!freshSnap.exists || freshSnap.data().status !== 'pending') return;
            const group = freshSnap.data();

            // Firestore 트랜잭션은 모든 읽기가 모든 쓰기보다 먼저 실행돼야 한다 —
            // 정원·신청 문서 읽기를 슬롯 업데이트(쓰기)보다 반드시 앞에 둔다.
            const release = await prepareBundleRelease(transaction, db, group);
            transaction.update(doc.ref, { status: rental.STATUS.expired });
            applyBundleRelease(transaction, db, group, release, {
              slotStatus: 'expired',
              cancelledBy: 'system',
              cancelReason: 'payment_timeout',
            });
          });
        } catch (e) {
          console.error(`[expireStalePackageBookings] ${doc.id} 만료 처리 실패`, e);
          await logScheduledFunctionError(db, 'expireStalePackageBookings', e, { bookingId: doc.id });
        }
      }

      console.log(`[expireStalePackageBookings] 완료 — ${snap.size}건 처리 시도`);
    } catch (e) {
      await logScheduledFunctionError(db, 'expireStalePackageBookings', e);
      throw e; // Cloud Scheduler 재시도/실패 기록은 기존과 동일하게 유지
    }
  },
);

// ── 5. 입금기한 초과 정리 (10분마다) ─────────────────────────────────────────
//
// 기한이 지나도록 **입금대기**인 예약은 방 슬롯과 파티 정원을 함께 반납한다.
// '입금확인중'은 대상이 아니다 — depositFlow.isExpirable이 그 상태를 제외하고,
// markPackageDepositSent가 슬롯 기한까지 지워 두므로 두 겹으로 막혀 있다.

exports.expirePackageBookingDeposits = onSchedule(
  { schedule: 'every 10 minutes', timeZone: 'Asia/Seoul', region: 'asia-northeast3' },
  async () => {
    const db = admin.firestore();
    try {
      const nowMs = Date.now();
      const snap = await db
        .collection('packageBookings')
        .where('payment.status', '==', flow.STATUS.awaitingDeposit)
        .where('payment.depositDeadlineMs', '<', nowMs)
        .get();

      console.log(`[expirePackageBookingDeposits] 만료 대상 ${snap.size}건`);

      for (const doc of snap.docs) {
        try {
          await db.runTransaction(async (transaction) => {
            const fresh = await transaction.get(doc.ref);
            if (!fresh.exists) return;
            const group = fresh.data();
            // 그 사이에 입금했다고 알렸거나 확인이 끝났으면 건드리지 않는다.
            if (!flow.isExpirable(group.payment, nowMs)) return;
            if (!rental.isLive(group.status)) return;

            const release = await prepareBundleRelease(transaction, db, group);
            const expired = flow.expirePatch(nowMs);
            transaction.update(doc.ref, {
              'payment.status': expired.status,
              'payment.cancelledAtMs': expired.cancelledAtMs,
              status: rental.STATUS.expired,
              cancelReason: 'deposit_expired',
              expiredAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            applyBundleRelease(transaction, db, group, release, {
              slotStatus: 'expired',
              cancelledBy: 'system',
              cancelReason: 'deposit_expired',
            });

            pushNotification(transaction, db, {
              uid: group.requesterId,
              role: 'guest',
              type: 'package_booking_deposit_expired',
              title: '숙박+파티 예약이 취소됐어요',
              body: `${group.placeName || '장소'} · ${group.date || ''} — 입금기한이 지나 자동 취소됐어요.`,
              placeId: group.placeId,
              refId: doc.id,
            });
          });
        } catch (e) {
          console.error(`[expirePackageBookingDeposits] ${doc.ref.path} 실패: ${e.message}`);
        }
      }
    } catch (e) {
      await logScheduledFunctionError(db, 'expirePackageBookingDeposits', e);
    }
  },
);

// ── 6. 업주 무응답 승인 요청 자동 만료 (10분마다) ────────────────────────────
//
// 승인제 룸에 신청해뒀는데 업주가 기한 안에 응답하지 않은 건 — 방과 파티 자리를
// 계속 죽여둘 수 없으므로 함께 반납한다. 아직 입금을 요구한 적이 없으므로
// 돌려줄 돈도 없다(신청 문서도 아직 만들어지지 않았다).

exports.expireStalePackageBookingApprovals = onSchedule(
  { schedule: 'every 10 minutes', timeZone: 'Asia/Seoul', region: 'asia-northeast3' },
  async () => {
    const db = admin.firestore();
    try {
      const now = admin.firestore.Timestamp.now();
      const snap = await db
        .collection('packageBookings')
        .where('status', '==', rental.STATUS.requested)
        .where('respondBy', '<', now)
        .get();

      console.log(`[expireStalePackageBookingApprovals] 만료 대상 ${snap.size}건`);

      for (const doc of snap.docs) {
        try {
          await db.runTransaction(async (transaction) => {
            const fresh = await transaction.get(doc.ref);
            if (!fresh.exists) return;
            const group = fresh.data();
            if (group.status !== rental.STATUS.requested) return;

            const release = await prepareBundleRelease(transaction, db, group);
            transaction.update(doc.ref, {
              status: rental.STATUS.expired,
              cancelReason: 'approval_timeout',
              expiredAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            applyBundleRelease(transaction, db, group, release, {
              slotStatus: 'expired',
              cancelledBy: 'system',
              cancelReason: 'approval_timeout',
            });

            pushNotification(transaction, db, {
              uid: group.requesterId,
              role: 'guest',
              type: 'package_booking_expired',
              title: '숙박+파티 예약 신청이 만료됐어요',
              body: `${group.placeName || '장소'} · ${group.date || ''} — 업주 응답이 없어 자동 취소됐어요.`,
              placeId: group.placeId,
              refId: doc.id,
            });
          });
        } catch (e) {
          console.error(`[expireStalePackageBookingApprovals] ${doc.ref.path} 실패: ${e.message}`);
        }
      }
    } catch (e) {
      await logScheduledFunctionError(db, 'expireStalePackageBookingApprovals', e);
    }
  },
);

// ── 공통: 선점 해제 / 슬롯 점유 ───────────────────────────────────────────────
//
// 콤보의 선점은 **세 곳**에 걸쳐 있다 — 방 슬롯, 파티 정원 카운터, 파티 신청
// 문서. 하나만 풀리면 "방은 비었는데 파티 정원은 찬" 또는 그 반대가 되므로,
// 되돌리는 경로(거절·취소·승인기한 만료·입금기한 만료)는 전부 아래 한 쌍만
// 쓴다. Firestore 트랜잭션의 "읽기 먼저" 제약 때문에 읽기/쓰기를 나눈다
// (placeProductOrders.js의 prepare/applyStockRelease와 같은 방식).

/** 정원·신청 문서를 되돌리는 데 필요한 **읽기 단계**. */
async function prepareBundleRelease(transaction, db, group) {
  const partyRef = db.collection('parties').doc(group.partyId);
  const applicationRef = partyRef
    .collection('applications')
    .doc(applicationDocId(group.requesterId, group.occurrenceId || null));
  const [partySnap, applicationSnap] = await Promise.all([
    transaction.get(partyRef),
    transaction.get(applicationRef),
  ]);
  return { partyRef, partySnap, applicationRef, applicationExists: applicationSnap.exists };
}

/**
 * 방 슬롯 + 파티 정원 + 신청 문서를 **한 번에** 되돌리는 쓰기 단계.
 *
 * 파티 정원 롤백은 기존 `releaseApplicantSlot`을 그대로 쓴다 — 차수별/성별
 * 카운터와 occurrenceStats까지 되돌리는 규칙이 이미 여기에 있고, 콤보라고
 * 다르게 계산할 이유가 없다(다르게 계산하면 파티 단독 취소와 결과가 갈린다).
 */
function applyBundleRelease(
  transaction,
  db,
  group,
  release,
  { slotStatus, cancelledBy, cancelReason, refund = null },
) {
  // ① 방 슬롯 — pending이든 confirmed든 동일하게 반납한다. update가 아니라
  // merge set을 쓴다(슬롯 문서가 이미 지워졌어도 트랜잭션이 죽지 않게).
  const slotsRef = db.collection('places').doc(group.placeId).collection('reservationSlots');
  for (const id of group.reservationIds || []) {
    transaction.set(
      slotsRef.doc(id),
      { status: slotStatus, expiresAt: null },
      { merge: true },
    );
  }

  // ② 파티 정원 — 예약 생성 시점에 선점해뒀던 자리를 되돌린다.
  if (release.partySnap.exists) {
    transaction.update(
      release.partyRef,
      releaseApplicantSlot(release.partySnap.data(), {
        uid: group.requesterId,
        gender: group.gender,
        selectedRounds: group.selectedRounds,
        // 회차 칸에 잡아둔 자리를 그 회차에서만 반납한다 — 다른 회차 예약이
        // 남아 있으면 그쪽 정원·명단은 그대로다. 차수 인원도 예약 때 올린
        // 칸(최상단 rounds[] 또는 그 회차의 rounds)만 되돌린다.
        occurrenceId: group.occurrenceId || null,
        roundCounterScope: group.roundCounterScope || null,
      }),
    );
  }

  // ③ 신청 문서 — 자리가 확정된 뒤에만 존재한다(승인대기 중에는 없다).
  if (release.applicationExists) {
    transaction.update(release.applicationRef, {
      status: 'cancelled',
      cancelledBy,
      cancelReason: cancelReason || null,
      refundPercent: refund ? refund.refundPercent : 0,
      refundAmount: refund ? refund.refundAmount : 0,
      refundStatus: refund ? refund.refundStatus : 'not_applicable',
      ...(refund ? { appliedRefundTier: refund.matchedTier } : {}),
      cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
      statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
}

// 자기검증용 export — packageBookings.selfcheck.js가 쓴다.
module.exports.__test = {
  prepareBundleRelease,
  applyBundleRelease,
  applySlotHold,
  isPaidBooking,
  buildApplicationDoc,
  applicationDocOf,
};

/** [placeReservationFlow.slotHoldOf]가 계산한 점유 상태를 방 슬롯에 반영한다. */
function applySlotHold(transaction, db, group, hold) {
  if (!hold) return;
  const ids = group.reservationIds || [];
  if (!ids.length || !group.placeId) return;
  const slotsRef = db.collection('places').doc(group.placeId).collection('reservationSlots');
  const expiresAt = hold.expiresAtMs
    ? admin.firestore.Timestamp.fromMillis(hold.expiresAtMs)
    : null;
  for (const id of ids) {
    transaction.set(slotsRef.doc(id), { status: hold.status, expiresAt }, { merge: true });
  }
}

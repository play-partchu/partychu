const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');
const {
  PENDING_TTL_MS,
  kstMidnight,
  kstWeekdayLabel,
  windowsOverlap,
  loadReservationConfig,
  computeWindows,
} = require('./roomAvailability');
const { portOneGetPayment } = require('./portOne');
const {
  computeRefund,
  reserveApplicantSlot,
  releaseApplicantSlot,
} = require('./partyCapacity');
const { logScheduledFunctionError } = require('./memberActivityHelpers');

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
// parties/{partyId}/applications/{uid} 문서 자체는 결제 확정 시점에만
// 만들어지지만, 정원 카운터(currentParticipants 등)는 pending 생성 시점에
// 이미 반영돼 있다.

const KST_OFFSET_MS = 9 * 60 * 60 * 1000;

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

    if (!placeId || typeof placeId !== 'string') {
      throw new HttpsError('invalid-argument', 'placeId가 필요합니다.');
    }
    if (!partyId || typeof partyId !== 'string') {
      throw new HttpsError('invalid-argument', 'partyId가 필요합니다.');
    }
    if (!['hourly', 'package', 'daily'].includes(bookingType)) {
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
    const partyDateTime = partyForDate.partyDateTime;
    if (!partyDateTime || typeof partyDateTime.toDate !== 'function') {
      throw new HttpsError('failed-precondition', '파티 날짜 정보가 올바르지 않아요.');
    }

    // 콤보 v1은 파티 날짜 = 숙박 날짜로 고정한다(별도 날짜 선택 UI 없음).
    const dateStr = kstDateStr(partyDateTime.toDate());
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

    await db.runTransaction(async (transaction) => {
      // ① 방 시간대 겹침 검증 — createPendingReservation과 동일한 방식.
      const queryStart = admin.firestore.Timestamp.fromDate(
        new Date(midnight.getTime() - 24 * 60 * 60 * 1000),
      );
      const queryEnd = admin.firestore.Timestamp.fromDate(
        new Date(midnight.getTime() + 24 * 60 * 60 * 1000),
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
        if (endMin <= 0 || startMin >= 1440 || startMin >= endMin) continue;
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
      });
      partyFee = reserved.appliedFee;
      effectiveSelectedRounds = reserved.effectiveSelectedRounds;
      transaction.update(partyRef, reserved.updateData);

      // ③ 방 슬롯(pending) — 개인정보 없는 공개 문서.
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
          status: 'pending',
          expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
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
        partyDateTime: partyData.partyDateTime || null,
        date: dateStr,
        peopleCount,
        requesterId: uid,
        requesterName,
        requesterPhone,
        requestMessage,
        reservationIds,
        status: 'pending',
        expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    return {
      bundleBookingId,
      roomPrice,
      partyFee,
      totalPrice: roomPrice + partyFee,
    };
  },
);

// ── 2. 포트원 결제 검증 → 확정 ────────────────────────────────────────────────

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
    if (group.status === 'confirmed') {
      return { success: true }; // 이미 확정됨 — 재호출에도 안전(idempotent)
    }
    if (group.status !== 'pending') {
      throw new HttpsError('failed-precondition', '이미 취소되었거나 만료된 예약이에요.');
    }
    if (group.expiresAt && group.expiresAt.toDate() < new Date()) {
      throw new HttpsError('deadline-exceeded', '결제 대기 시간이 만료됐어요. 다시 예약해주세요.');
    }

    if (group.totalPrice > 0) {
      let apiSecret;
      try {
        apiSecret = portOneApiSecret.value().trim();
      } catch (e) {
        throw new HttpsError('internal', `결제 시크릿 로딩 실패: ${e.message}`);
      }

      const { statusCode, body } = await portOneGetPayment(bundleBookingId, apiSecret);
      if (statusCode !== 200) {
        console.error('[verifyAndConfirmPackageBooking] PortOne 조회 실패', statusCode, body);
        throw new HttpsError('internal', '결제 확인에 실패했습니다.');
      }
      const paidAmount = body && body.amount && body.amount.total;
      const status = body && body.status;
      if (status !== 'PAID' || paidAmount !== group.totalPrice) {
        console.error('[verifyAndConfirmPackageBooking] 결제 검증 불일치',
          { status, paidAmount, expected: group.totalPrice });
        throw new HttpsError('failed-precondition', '결제 금액/상태가 일치하지 않습니다.');
      }
    }

    const slotsRef = db.collection('places').doc(group.placeId).collection('reservationSlots');
    const applicationRef = db.collection('parties').doc(group.partyId)
      .collection('applications').doc(uid);

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
      // applications 문서만 만든다(applyToParty와 동일한 shape +
      // bundleBookingId).
      const partyDateTime = group.partyDateTime && typeof group.partyDateTime.toDate === 'function'
        ? group.partyDateTime.toDate()
        : null;
      const kst = partyDateTime ? kstParts(partyDateTime) : null;

      transaction.set(applicationRef, {
        uid,
        partyId: group.partyId,
        hostId: group.hostId || null,
        status: 'applied',
        gender: group.gender || null,
        appliedFee: group.partyFee || 0,
        region: group.region || null,
        district: group.district || null,
        partyDateTime: group.partyDateTime || null,
        partyDate: kst?.dateKey || null,
        partyStartHour: kst?.hour ?? null,
        dayOfWeek: kst?.dayOfWeek ?? null,
        partyCategory: group.partyCategory || null,
        appliedAt: admin.firestore.FieldValue.serverTimestamp(),
        statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        confirmedAt: null,
        attendedAt: null,
        cancelledAt: null,
        bundleBookingId,
        ...(group.selectedRounds ? { selectedRounds: group.selectedRounds } : {}),
      });
    });

    return { success: true };
  },
);

// ── 3. 패키지 예약 취소 ──────────────────────────────────────────────────────

exports.cancelPackageBooking = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const uid = request.auth.uid;
    const bundleBookingId = request.data && request.data.bundleBookingId;
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
      if (group.requesterId !== uid) {
        throw new HttpsError('permission-denied', '본인 예약만 취소할 수 있어요.');
      }
      if (group.status === 'cancelled' || group.status === 'expired') return;

      const partyRef = db.collection('parties').doc(group.partyId);
      const partySnap = await transaction.get(partyRef);
      const slotsRef = db.collection('places').doc(group.placeId).collection('reservationSlots');

      // 방 슬롯은 pending이든 confirmed든 동일하게 cancelled 처리.
      for (const id of group.reservationIds || []) {
        transaction.update(slotsRef.doc(id), { status: 'cancelled' });
      }

      // 파티 정원 롤백 — pending 생성 시점에 선점해뒀던 자리를 되돌린다.
      if (partySnap.exists) {
        const releaseUpdate = releaseApplicantSlot(partySnap.data(), {
          uid,
          gender: group.gender,
          selectedRounds: group.selectedRounds,
        });
        transaction.update(partyRef, releaseUpdate);
      }

      if (group.status === 'confirmed') {
        // 실제 결제까지 마친 예약의 취소 — 패키지 총액 기준으로 환불액을
        // 계산한다(방/파티를 나누지 않고 하나의 환불 규정을 적용).
        const refundPolicy = partySnap.exists ? partySnap.data().refundPolicy : null;
        const refund = computeRefund(refundPolicy, group.totalPrice, group.partyDateTime);
        result = refund;

        const applicationRef = partyRef.collection('applications').doc(uid);
        transaction.update(applicationRef, {
          status: 'cancelled',
          cancelledBy: 'user',
          refundPercent: refund.refundPercent,
          refundAmount: refund.refundAmount,
          refundStatus: refund.refundStatus,
          appliedRefundTier: refund.matchedTier,
          statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        transaction.update(bundleRef, {
          status: 'cancelled',
          cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
          refundPercent: refund.refundPercent,
          refundAmount: refund.refundAmount,
          refundStatus: refund.refundStatus,
          appliedRefundTier: refund.matchedTier,
        });
      } else {
        // 결제 전(pending) 이탈 — 아무것도 결제되지 않았으므로 환불 계산 없이
        // 선점만 풀고 취소 처리한다(applications 문서는 애초에 없음).
        transaction.update(bundleRef, {
          status: 'cancelled',
          cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    });

    return { success: true, ...result };
  },
);

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
            // partyRef 읽기를 슬롯 업데이트(쓰기)보다 반드시 앞에 둔다.
            const partyRef = db.collection('parties').doc(group.partyId);
            const partySnap = await transaction.get(partyRef);

            const slotsRef = db.collection('places').doc(group.placeId).collection('reservationSlots');
            for (const id of group.reservationIds || []) {
              transaction.update(slotsRef.doc(id), { status: 'expired' });
            }

            if (partySnap.exists) {
              const releaseUpdate = releaseApplicantSlot(partySnap.data(), {
                uid: group.requesterId,
                gender: group.gender,
                selectedRounds: group.selectedRounds,
              });
              transaction.update(partyRef, releaseUpdate);
            }

            transaction.update(doc.ref, { status: 'expired' });
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

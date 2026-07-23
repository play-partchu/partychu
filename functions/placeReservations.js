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
const { logScheduledFunctionError } = require('./memberActivityHelpers');

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

const portOneApiSecret = defineSecret('PORTONE_API_SECRET');

// ── 1. 예약 생성 (pending) ────────────────────────────────────────────────────

exports.createPendingReservation = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const uid = request.auth.uid;
    const db = admin.firestore();

    const data = request.data || {};
    const placeId = data.placeId;
    const roomId = data.roomId || null;
    const bookingType = data.bookingType;
    const dateStr = data.date;
    const peopleCount = Number(data.peopleCount) || 1;
    const requesterName = String(data.requesterName || '').trim();
    const requesterPhone = String(data.requesterPhone || '').trim();
    const requestMessage = String(data.requestMessage || '').trim();

    if (!placeId || typeof placeId !== 'string') {
      throw new HttpsError('invalid-argument', 'placeId가 필요합니다.');
    }
    if (!['hourly', 'package', 'daily'].includes(bookingType)) {
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

    await db.runTransaction(async (transaction) => {
      // 전날 밤부터 시작해 다음날로 넘어가는 예약(올나잇 패키지 등)도 겹침
      // 판정에 포함하기 위해 하루 앞선 시점부터 다음날 자정 전까지 조회한다.
      // roomId 등호 필터는 걸지 않고(복합 색인 불필요) 조회 후 코드에서 거른다
      // — 클라이언트 _loadBooked와 동일한 방식.
      const queryStart = admin.firestore.Timestamp.fromDate(
        new Date(midnight.getTime() - 24 * 60 * 60 * 1000),
      );
      const queryEnd = admin.firestore.Timestamp.fromDate(
        new Date(midnight.getTime() + 24 * 60 * 60 * 1000),
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
        if (endMin <= 0 || startMin >= 1440 || startMin >= endMin) continue;
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
          status: 'pending',
          expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
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
        totalMinutes,
        totalPrice,
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

    return { groupId, totalPrice, totalMinutes };
  },
);

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

      const { statusCode, body } = await portOneGetPayment(groupId, apiSecret);
      if (statusCode !== 200) {
        console.error('[verifyAndConfirmReservation] PortOne 조회 실패', statusCode, body);
        throw new HttpsError('internal', '결제 확인에 실패했습니다.');
      }
      const paidAmount = body && body.amount && body.amount.total;
      const status = body && body.status;
      if (status !== 'PAID' || paidAmount !== group.totalPrice) {
        console.error('[verifyAndConfirmReservation] 결제 검증 불일치',
          { status, paidAmount, expected: group.totalPrice });
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

// ── 3. 예약 취소 ──────────────────────────────────────────────────────────────

exports.cancelReservation = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const uid = request.auth.uid;
    const groupId = request.data && request.data.groupId;
    if (!groupId || typeof groupId !== 'string') {
      throw new HttpsError('invalid-argument', 'groupId가 필요합니다.');
    }

    const db = admin.firestore();
    const groupRef = db.collection('placeReservationGroups').doc(groupId);

    await db.runTransaction(async (transaction) => {
      const groupSnap = await transaction.get(groupRef);
      if (!groupSnap.exists) throw new HttpsError('not-found', '예약을 찾을 수 없어요.');
      const group = groupSnap.data();
      if (group.requesterId !== uid) {
        throw new HttpsError('permission-denied', '본인 예약만 취소할 수 있어요.');
      }
      if (group.status === 'cancelled' || group.status === 'expired') return;

      const placeId = group.placeId;
      const slotsRef = db.collection('places').doc(placeId).collection('reservationSlots');
      transaction.update(groupRef, {
        status: 'cancelled',
        cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      for (const id of group.reservationIds || []) {
        transaction.update(slotsRef.doc(id), { status: 'cancelled' });
      }
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
          const group = doc.data();
          batch.update(doc.ref, { status: 'expired' });
          const slotsRef = db.collection('places').doc(group.placeId).collection('reservationSlots');
          for (const id of group.reservationIds || []) {
            batch.update(slotsRef.doc(id), { status: 'expired' });
          }
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

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');

const { kstMidnight, kstWeekdayLabel, parseTimeStr } = require('./roomAvailability');
const { logScheduledFunctionError } = require('./memberActivityHelpers');
// 결제수단·결제상태는 파티 신청과 **같은 규칙**을 쓴다(수단은 앱이 고르고
// 상태는 서버가 정한다). 전이 규칙도 depositFlow 하나를 공유한다.
const { buildPaymentInfo } = require('./paymentInfo');
// 호스트 수취계좌 — 무통장입금 안내 계좌는 이 값 하나에서만 나온다.
const { loadPayoutSnapshot } = require('./payoutAccounts');
// 예약금 정책 — 방문예약은 총액 미확정 도메인이라 '고정 예약금'만 성립한다.
// 'upfront'(예약금)와 'deposit'(무통장입금)은 서로 다른 축이다.
const paymentPolicy = require('./paymentPolicy');
const flow = require('./depositFlow');
const { pushNotification: pushReservationNotification } = require('./reservationNotifications');
// 본인확인 게이트 — 거래성 요청은 앱 UI와 무관하게 서버가 직접 확인한다.
const { assertIdentityVerified } = require('./identityGuard');

// 플레이스(events) **무료 방문 예약** — "몇 시에 몇 명 갈게요"를 매장에 알리고
// 업주가 받아주는 흐름. 결제가 없다(PortOne 미연결).
//
// 장소대여 예약(placeReservations.js)과 **다른 기능·다른 컬렉션**이다:
//   - 장소대여: 룸을 통째로 빌려 그 시간을 독점 → 겹치면 실패
//   - 방문 예약: 같은 시간에 여러 팀이 들어감 → 좌석 총량(인원 합계)으로만 제한
// 유료 좌석 상품(placeProductOrders.js의 'seat')과도 별개다 — 그쪽은 결제하고
// QR 이용권을 받는 상품 구매다.
//
// 다만 **구조는 placeReservations.js를 그대로 따른다**:
//   onCall + 트랜잭션 / 개인정보 2분할 / 스케줄 만료 / 클라이언트 쓰기 전면 차단.
//
// ── 개인정보 분리 ────────────────────────────────────────────────────────────
//   - events/{placeId}/visitSlots/{dateKey_HHmm}: 시간대별 **예약 인원 합계**만
//     담은 공개 문서. 다른 이용자가 "이 시간 자리 있나"를 확인하는 용도라
//     이름·연락처는 절대 넣지 않는다.
//   - placeVisitReservations/{id}: 예약자 이름·연락처·요청사항까지 담은 비공개
//     문서. 본인(requesterId)·해당 매장 업주(hostId)·관리자만 읽는다.
// 두 문서는 한 트랜잭션에서 함께 갱신된다.
//
// ── 알림 ─────────────────────────────────────────────────────────────────────
// notifications 컬렉션에 인앱 알림을 남긴다(서버 전용 생성 — firestore.rules).
// FCM 푸시는 아직 붙이지 않았지만, 알림 문서를 만드는 곳을 pushNotification()
// 한 곳으로 모아 두었으므로 나중에 그 함수 안에서 토큰 발송만 더하면 된다.

const MINUTES_PER_DAY = 1440;

/** 예약 문서가 살아 있다고 보는 상태 — 정원 계산에 세는 값. */
const LIVE_STATUSES = new Set(['requested', 'approved']);

/** 한 사람이 같은 매장에 동시에 걸어둘 수 있는 살아있는 예약 수. */
const MAX_LIVE_PER_PLACE = 3;

// ── 설정 읽기 ────────────────────────────────────────────────────────────────

/**
 * events/{placeId}.visitReservation 을 서버 기준으로 정규화한다.
 * 클라이언트가 보낸 설정은 **쓰지 않는다** — 항상 문서에서 다시 읽는다.
 * Dart의 PlaceVisitReservationConfig.fromMap과 같은 기본값을 유지한다.
 */
function readConfig(placeData) {
  const raw = (placeData && placeData.visitReservation) || {};
  const int = (v, fallback) => {
    const n = Number(v);
    return Number.isFinite(n) && n > 0 ? Math.floor(n) : fallback;
  };
  return {
    enabled: raw.enabled === true,
    approvalMode: raw.approvalMode === 'auto' ? 'auto' : 'manual',
    slotMinutes: int(raw.slotMinutes, 30),
    openFrom: typeof raw.openFrom === 'string' ? raw.openFrom : null,
    openTo: typeof raw.openTo === 'string' ? raw.openTo : null,
    stayMinutes: int(raw.stayMinutes, 120),
    minPeople: int(raw.minPeople, 1),
    maxPeople: int(raw.maxPeople, 8),
    capacityPerSlot: int(raw.capacityPerSlot, 20),
    leadTimeMinutes: Number.isFinite(Number(raw.leadTimeMinutes))
      ? Math.max(0, Math.floor(Number(raw.leadTimeMinutes)))
      : 60,
    maxAdvanceDays: int(raw.maxAdvanceDays, 30),
    autoExpireHours: int(raw.autoExpireHours, 12),
    blockedDates: Array.isArray(raw.blockedDates) ? raw.blockedDates : [],
    // 1인당 예약금 — 0이면 지금까지와 똑같은 **무료 예약**이다(설정이 없는
    // 기존 매장은 전부 여기에 해당한다).
    //
    // depositType은 지금 'per_person' 하나뿐이지만, 나중에 'per_booking'
    // (예약 1건당 고정액)을 더할 수 있게 필드로 남겨 둔다 — 금액 계산은 반드시
    // depositAmountOf()를 거치게 해서 넓힐 때 한 곳만 고치면 되게 한다.
    depositType: raw.depositType === 'per_booking' ? 'per_booking' : 'per_person',
    depositPerPerson: Number.isFinite(Number(raw.depositPerPerson))
      ? Math.max(0, Math.floor(Number(raw.depositPerPerson)))
      : 0,
  };
}

/**
 * 이 예약에서 받을 금액 — 지금은 **1인당 예약금 × 인원**뿐이다.
 * 금액은 언제나 서버가 매장 설정을 다시 읽어 계산한다(앱이 보낸 금액은 쓰지
 * 않는다).
 */
function depositAmountOf(cfg, peopleCount) {
  if (!cfg.depositPerPerson) return 0;
  return cfg.depositPerPerson * peopleCount;
}

/**
 * 방문예약의 **결제 정책**을 기존 설정에서 유도한다 — 새 필드도 마이그레이션도
 * 없다.
 *
 * 방문예약은 "자리만 잡고 음식·주류는 현장에서 주문"하는 형태라 예약 시점에
 * 총 이용금액을 알 수 없다. 그래서 쓸 수 있는 방식이 두 가지뿐이다.
 *
 *   depositPerPerson === 0  →  onsite  (예약금 없음 · 지금까지의 무료 방문예약)
 *   depositPerPerson  > 0   →  partial (고정 예약금 · 지금까지의 1인당 예약금)
 *
 * 비율(%) 예약금과 전액 선결제는 총액을 모르므로 성립하지 않는다 — 총액이
 * 확정되지 않았는데 비율을 계산하거나 잔금을 숫자로 적으면 그건 거짓말이다.
 * 잔금은 0이 아니라 **null**(모름)로 남고, 화면은 "추가 이용금액은 현장에서
 * 결제"라고만 쓴다.
 */
function policyOf(cfg, peopleCount) {
  const amount = depositAmountOf(cfg, peopleCount);
  if (amount <= 0) return { paymentMode: paymentPolicy.MODE.onsite };
  return {
    paymentMode: paymentPolicy.MODE.partial,
    upfrontType: paymentPolicy.UPFRONT_TYPE.fixed,
    upfrontFixedAmount: amount,
  };
}

/** 그날 영업 구간(자정 기준 분). 휴무면 null — Dart VisitSlotCalculator와 같은 규칙. */
function openWindowOf(placeData, weekdayLabel) {
  if (placeData.isOpen24Hours === true) return { start: 0, end: MINUTES_PER_DAY };
  const weekly = placeData.placeWeeklyHours || placeData.weeklyOperatingHours;
  const day = weekly && weekly[weekdayLabel];
  if (!day) return null;
  if (day.isClosed === true) return null;
  if (day.is24Hours === true) return { start: 0, end: MINUTES_PER_DAY };
  const open = parseTimeStr(day.open || day.openTime);
  let close = parseTimeStr(day.close || day.closeTime);
  if (close <= open) close += MINUTES_PER_DAY; // 자정을 넘겨 닫는 가게
  return { start: open, end: close };
}

/** 그날 브레이크 타임 구간(자정 기준 분). 없으면 null. */
function breakWindowOf(placeData, weekdayLabel) {
  const weekly = placeData.placeWeeklyHours || placeData.weeklyOperatingHours;
  const day = weekly && weekly[weekdayLabel];
  if (!day || day.hasBreakTime !== true || day.isClosed === true) return null;
  const base = day.is24Hours === true ? 0 : parseTimeStr(day.open || day.openTime);
  const offset = (t) => {
    const diff = parseTimeStr(t) - base;
    return diff < 0 ? diff + MINUTES_PER_DAY : diff;
  };
  const start = base + offset(day.breakStart);
  const end = base + offset(day.breakEnd);
  return end > start ? { start, end } : null;
}

/** 'HH:mm' → 자정 기준 분. 없으면 null. */
function minutesOrNull(hhmm) {
  return typeof hhmm === 'string' && hhmm.includes(':') ? parseTimeStr(hhmm) : null;
}

function pad2(n) {
  return String(n).padStart(2, '0');
}

/** 자정 기준 분 → 슬롯 키('1830'). 하루를 넘어가면 다음 날 시각으로 접는다. */
function slotKeyOfMinutes(minutes) {
  const inDay = ((minutes % MINUTES_PER_DAY) + MINUTES_PER_DAY) % MINUTES_PER_DAY;
  return `${pad2(Math.floor(inDay / 60))}${pad2(inDay % 60)}`;
}

/** 'YYYY-MM-DD' — KST 기준. */
function dateKeyOfMs(ms) {
  const kst = new Date(ms + 9 * 60 * 60 * 1000);
  return `${kst.getUTCFullYear()}-${pad2(kst.getUTCMonth() + 1)}-${pad2(kst.getUTCDate())}`;
}

/**
 * 이 예약이 자리를 차지하는 슬롯 문서 id들 — 머무는 시간(stayMinutes) 동안
 * 걸치는 모든 칸을 차지한다(19:00 방문 + 2시간이면 19:00·19:30·20:00·20:30).
 * 자정을 넘기면 다음 날짜 문서로 자연스럽게 넘어간다.
 */
function occupiedSlotIds(midnightMs, startMinutes, cfg) {
  const ids = [];
  const end = startMinutes + cfg.stayMinutes;
  for (let m = startMinutes; m < end; m += cfg.slotMinutes) {
    const dayOffset = Math.floor(m / MINUTES_PER_DAY);
    const dateKey = dateKeyOfMs(midnightMs + dayOffset * MINUTES_PER_DAY * 60000);
    ids.push(`${dateKey}_${slotKeyOfMinutes(m)}`);
  }
  return ids;
}

// ── 알림 (FCM 확장 지점) ──────────────────────────────────────────────────────

/**
 * 인앱 알림 한 건 — 알림 문서를 만드는 규칙 자체는 장소대여 예약과 같은
 * 모듈([reservationNotifications])이 갖고 있고(필드가 갈라지면 알림함이 한쪽만
 * 열린다), 여기서는 "어느 컬렉션을 가리키는 알림인가"만 채워 넘긴다.
 */
function pushNotification(batchOrTx, db, { reservationId, ...args }) {
  return pushReservationNotification(batchOrTx, db, {
    ...args,
    placeCollection: 'events',
    refCollection: 'placeVisitReservations',
    refId: reservationId,
  });
}

// ── 1. 예약 신청 ──────────────────────────────────────────────────────────────

exports.createVisitReservation = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const uid = request.auth.uid;
    const db = admin.firestore();
    // 본인확인은 **다른 어떤 검증보다 먼저** 본다 — 무료 예약이라도 매장에
    // 사람이 찾아가는 약속이므로 회원 정책은 동일하다(identityGuard.js 참고).
    await assertIdentityVerified(db, uid);

    const data = request.data || {};
    const placeId = String(data.placeId || '');
    const dateStr = String(data.date || ''); // 'YYYY-MM-DD'
    const timeStr = String(data.time || ''); // 'HH:mm'
    const peopleCount = Math.floor(Number(data.peopleCount) || 0);
    const requesterName = String(data.requesterName || '').trim();
    const requesterPhone = String(data.requesterPhone || '').trim();
    const requestMessage = String(data.requestMessage || '').trim().slice(0, 500);
    // 결제수단만 받는다 — 금액도 상태도 서버가 정한다.
    const payment = data.payment;

    if (!placeId) throw new HttpsError('invalid-argument', 'placeId가 필요합니다.');
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dateStr)) {
      throw new HttpsError('invalid-argument', '날짜 형식이 올바르지 않습니다.');
    }
    if (!/^\d{2}:\d{2}$/.test(timeStr)) {
      throw new HttpsError('invalid-argument', '시간 형식이 올바르지 않습니다.');
    }
    if (!requesterName || !requesterPhone) {
      throw new HttpsError('invalid-argument', '예약자 이름과 연락처가 필요합니다.');
    }

    const placeRef = db.collection('events').doc(placeId);
    const placeSnap = await placeRef.get();
    if (!placeSnap.exists) throw new HttpsError('not-found', '플레이스를 찾을 수 없어요.');
    const place = placeSnap.data();

    // 설정은 항상 서버가 문서에서 다시 읽는다 — 클라이언트가 보낸 값은 쓰지 않는다.
    const cfg = readConfig(place);
    if (!cfg.enabled) {
      throw new HttpsError('failed-precondition', '지금은 방문 예약을 받지 않는 곳이에요.');
    }
    if (place.hostId === uid) {
      throw new HttpsError('failed-precondition', '내 매장에는 예약할 수 없어요.');
    }
    // 주인을 알 수 없는 옛 문서는 승인할 사람이 없다 — 신청을 받아두면 그대로
    // 만료될 뿐이므로 아예 막는다.
    if (!place.hostId) {
      throw new HttpsError('failed-precondition', '지금은 이 매장의 예약을 받을 수 없어요.');
    }
    if (peopleCount < cfg.minPeople || peopleCount > cfg.maxPeople) {
      throw new HttpsError(
        'invalid-argument',
        `예약 인원은 ${cfg.minPeople}~${cfg.maxPeople}명이에요.`,
      );
    }
    if (cfg.blockedDates.includes(dateStr)) {
      throw new HttpsError('failed-precondition', '그날은 예약을 받지 않아요.');
    }

    const midnight = kstMidnight(dateStr);
    const startMinutes = parseTimeStr(timeStr);
    const visitAt = new Date(midnight.getTime() + startMinutes * 60000);
    const endAt = new Date(visitAt.getTime() + cfg.stayMinutes * 60000);
    const now = new Date();

    // 예약 가능 기간·마감 시간
    const daysAhead = Math.floor(
      (midnight.getTime() - kstMidnight(dateKeyOfMs(now.getTime())).getTime()) / 86400000,
    );
    if (daysAhead < 0 || daysAhead > cfg.maxAdvanceDays) {
      throw new HttpsError('failed-precondition', '예약할 수 있는 기간이 아니에요.');
    }
    if (visitAt.getTime() - now.getTime() < cfg.leadTimeMinutes * 60000) {
      throw new HttpsError('failed-precondition', '예약 마감 시간이 지났어요.');
    }

    // 영업시간 안인지 — 화면에서 고를 수 없게 막고 있지만, 서버도 다시 본다.
    const weekdayLabel = kstWeekdayLabel(midnight);
    const open = openWindowOf(place, weekdayLabel);
    if (!open) throw new HttpsError('failed-precondition', '그날은 영업하지 않아요.');
    let acceptStart = open.start;
    let acceptEnd = open.end;
    const from = minutesOrNull(cfg.openFrom);
    const to = minutesOrNull(cfg.openTo);
    if (from !== null && from > acceptStart) acceptStart = from;
    if (to !== null) {
      const normalizedTo = from !== null && to <= from ? to + MINUTES_PER_DAY : to;
      if (normalizedTo < acceptEnd) acceptEnd = normalizedTo;
    }
    if (startMinutes < acceptStart || startMinutes >= acceptEnd) {
      throw new HttpsError('failed-precondition', '예약을 받는 시간이 아니에요.');
    }
    if ((startMinutes - acceptStart) % cfg.slotMinutes !== 0) {
      throw new HttpsError('invalid-argument', '예약할 수 없는 시각이에요.');
    }
    const brk = breakWindowOf(place, weekdayLabel);
    if (brk && startMinutes >= brk.start && startMinutes < brk.end) {
      throw new HttpsError('failed-precondition', '브레이크 타임에는 예약할 수 없어요.');
    }

    // 같은 사람이 같은 매장에 예약을 무한정 걸어두지 못하게 막는다.
    const mineSnap = await db
      .collection('placeVisitReservations')
      .where('requesterId', '==', uid)
      .where('placeId', '==', placeId)
      .get();
    const live = mineSnap.docs.filter((d) => LIVE_STATUSES.has(d.data().status));
    if (live.length >= MAX_LIVE_PER_PLACE) {
      throw new HttpsError('failed-precondition', '이 매장에 이미 진행 중인 예약이 있어요.');
    }
    if (live.some((d) => {
      const at = d.data().visitAt;
      return at && Math.abs(at.toDate().getTime() - visitAt.getTime()) < 60000;
    })) {
      throw new HttpsError('already-exists', '같은 시간에 이미 신청한 예약이 있어요.');
    }

    const slotIds = occupiedSlotIds(midnight.getTime(), startMinutes, cfg);
    const slotsRef = placeRef.collection('visitSlots');
    const reservationRef = db.collection('placeVisitReservations').doc();
    const autoApprove = cfg.approvalMode === 'auto';

    // ── 예약금 ────────────────────────────────────────────────────────
    // 무료 예약(예약금 0원)이면 결제 자체가 없어 payment 필드도 만들지 않는다
    // — 지금까지의 무료 방문예약과 완전히 같게 동작한다.
    //
    // 승인제 매장은 **승인 후 입금**이다(requireApproval): 승인 전에 입금을
    // 받으면 거절 시 계좌로 수동 환불해야 하는데, PG가 없어 자동 환불이
    // 불가능하다. 자동승인 매장은 신청 즉시 확정이므로 바로 입금대기가 된다.
    //
    // 입금기한은 방문 시각을 넘지 않는다(depositFlow가 잘라준다).
    const depositAmount = depositAmountOf(cfg, peopleCount);
    // 총액이 확정되지 않는 예약이므로 totalAmount는 null이다 — 예약금만 확정되고
    // 잔금은 "모름"으로 남는다(0으로 적으면 "더 낼 돈이 없다"는 거짓말이 된다).
    //
    // ⚠ 여기서는 결제수단을 **제한하지 않는다.** 지금까지 예약금이 있는 매장도
    //   구매자가 무통장입금/현장결제를 자유롭게 골랐고, 그 동작을 그대로
    //   유지해야 한다(설정 필드도 depositPerPerson 하나뿐이라 "호스트가 수단을
    //   정했다"고 볼 근거가 없다). 정책은 금액 표시·스냅샷 용도로만 쓴다.
    const policy = policyOf(cfg, peopleCount);
    const amountSnapshot = paymentPolicy.snapshotOf(policy, null);
    // 무통장입금 안내 계좌는 **이 매장 업주의 인증된 수취계좌**다. 트랜잭션
    // 밖에서 한 번 읽어 스냅샷으로 넘긴다(payoutAccounts.js 참고).
    const paymentInfo = buildPaymentInfo(payment, {
      amount: depositAmount,
      requireApproval: !autoApprove,
      useAtMs: visitAt.getTime(),
      payoutAccount: await loadPayoutSnapshot(db, place.hostId),
    });
    const respondBy = new Date(
      Math.min(
        now.getTime() + cfg.autoExpireHours * 3600000,
        visitAt.getTime(), // 방문 시각이 먼저 오면 그때가 곧 마감이다
      ),
    );

    await db.runTransaction(async (tx) => {
      const slotSnaps = await Promise.all(slotIds.map((id) => tx.get(slotsRef.doc(id))));

      // 자리가 남았는지 — 걸치는 칸이 하나라도 모자라면 받지 않는다(대기목록 없음).
      slotSnaps.forEach((snap, i) => {
        const reserved = snap.exists ? Number(snap.data().reservedPeople) || 0 : 0;
        if (reserved + peopleCount > cfg.capacityPerSlot) {
          throw new HttpsError(
            'resource-exhausted',
            `${slotIds[i].split('_')[1].replace(/^(\d{2})(\d{2})$/, '$1:$2')} 시간대는 자리가 다 찼어요.`,
          );
        }
      });

      slotSnaps.forEach((snap, i) => {
        const id = slotIds[i];
        const [dateKey, slotKey] = id.split('_');
        const startAt = new Date(
          kstMidnight(dateKey).getTime() + parseTimeStr(`${slotKey.slice(0, 2)}:${slotKey.slice(2)}`) * 60000,
        );
        tx.set(
          slotsRef.doc(id),
          {
            date: dateKey,
            startAt: admin.firestore.Timestamp.fromDate(startAt),
            endAt: admin.firestore.Timestamp.fromDate(
              new Date(startAt.getTime() + cfg.slotMinutes * 60000),
            ),
            capacity: cfg.capacityPerSlot,
            reservedPeople: admin.firestore.FieldValue.increment(peopleCount),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      });

      tx.set(reservationRef, {
        placeId,
        placeCollection: 'events',
        placeName: place.title || place.name || '',
        placeAddress: place.address || place.roadAddress || '',
        hostId: place.hostId || '',
        requesterId: uid,
        requesterName,
        requesterPhone,
        peopleCount,
        date: dateStr,
        visitAt: admin.firestore.Timestamp.fromDate(visitAt),
        endAt: admin.firestore.Timestamp.fromDate(endAt),
        slotIds,
        status: autoApprove ? 'approved' : 'requested',
        autoApproved: autoApprove,
        approvalMode: cfg.approvalMode,
        // 예약금 — 서버가 매장 설정으로 다시 계산한 금액이다(0이면 무료).
        depositAmount,
        // 금액 스냅샷 — 총액 미확정 예약이라 totalAmount·remainingAmount는
        // null이고 예약금만 확정값이다. 업주가 나중에 1인당 예약금을 바꿔도
        // 이 예약의 금액은 변하지 않는다.
        amounts: amountSnapshot,
        ...(paymentInfo ? { payment: paymentInfo } : {}),
        requestMessage,
        hostMessage: '',
        respondBy: autoApprove ? null : admin.firestore.Timestamp.fromDate(respondBy),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        decidedAt: autoApprove ? admin.firestore.FieldValue.serverTimestamp() : null,
      });

      // 업주 알림 — 자동 승인이어도 "예약이 잡혔다"는 사실은 알려야 한다.
      if (place.hostId) {
        pushNotification(tx, db, {
          uid: place.hostId,
          role: 'host',
          type: autoApprove ? 'visit_reservation_auto_confirmed' : 'visit_reservation_requested',
          title: autoApprove ? '새 방문 예약이 확정됐어요' : '새 방문 예약 신청',
          body: `${place.title || '내 플레이스'} · ${dateStr} ${timeStr} ${peopleCount}명`,
          placeId,
          reservationId: reservationRef.id,
        });
      }
    });

    return {
      reservationId: reservationRef.id,
      status: autoApprove ? 'approved' : 'requested',
      autoApproved: autoApprove,
    };
  },
);

// ── 2. 업주 승인 / 거절 ───────────────────────────────────────────────────────

exports.decideVisitReservation = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const uid = request.auth.uid;
    const data = request.data || {};
    const reservationId = String(data.reservationId || '');
    const approve = data.approve === true;
    const hostMessage = String(data.hostMessage || '').trim().slice(0, 300);
    if (!reservationId) {
      throw new HttpsError('invalid-argument', 'reservationId가 필요합니다.');
    }

    const db = admin.firestore();
    const ref = db.collection('placeVisitReservations').doc(reservationId);

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) throw new HttpsError('not-found', '예약을 찾을 수 없어요.');
      const r = snap.data();
      if (r.hostId !== uid) {
        throw new HttpsError('permission-denied', '내 매장의 예약만 처리할 수 있어요.');
      }
      if (r.status !== 'requested') {
        throw new HttpsError('failed-precondition', '이미 처리된 예약이에요.');
      }

      // 승인되는 순간이 곧 **입금 안내 시작**이다(승인제 매장의 무통장입금).
      // 거절이면 결제 상태를 건드리지 않는다 — 애초에 입금을 요구하지 않았고
      // 받은 돈도 없다.
      const approvePatch = approve
        ? flow.approvePatch(r.payment, Date.now(), {
            notAfterMs: r.visitAt ? r.visitAt.toDate().getTime() : null,
          })
        : null;

      tx.update(ref, {
        status: approve ? 'approved' : 'rejected',
        hostMessage,
        decidedAt: admin.firestore.FieldValue.serverTimestamp(),
        ...(approvePatch
          ? {
              'payment.status': approvePatch.status,
              'payment.depositDeadlineMs': approvePatch.depositDeadlineMs,
            }
          : {}),
      });

      // 거절하면 잡아뒀던 자리를 즉시 돌려준다.
      if (!approve) releaseSlots(tx, db, r);

      pushNotification(tx, db, {
        uid: r.requesterId,
        role: 'guest',
        type: approve ? 'visit_reservation_approved' : 'visit_reservation_rejected',
        title: approve ? '방문 예약이 확정됐어요' : '방문 예약이 거절됐어요',
        body: `${r.placeName || '플레이스'} · ${r.date} ${formatVisitTime(r.visitAt)}`
          + (hostMessage ? ` — ${hostMessage}` : '')
          // 승인과 동시에 입금대기가 시작됐다면 그 사실을 함께 알린다 —
          // 확정 알림만 보면 결제까지 끝난 줄 오해할 수 있다.
          + (approvePatch ? ' — 기한 내 입금하시면 예약이 유지돼요.' : ''),
        placeId: r.placeId,
        reservationId,
      });
    });

    return { success: true };
  },
);

// ── 2-1. 무통장입금 (이용자 '입금했어요' / 업주 '입금 확인') ──────────────────
//
// 전이 규칙은 파티 신청과 **같은 모듈**(depositFlow)을 쓴다. 여기서는 예약
// 문서를 그 규칙에 끼워 넣고, 확인이 끝났을 때 예약 상태를 어떻게 둘지만
// 도메인 사정에 맞게 정한다.
//
// 파티와 다른 점: 방문예약은 **결제 확인이 곧 승인이 아니다**. 승인은 업주가
// 이미 했거나(승인제) 신청 즉시 자동으로 났고(자동승인), 입금 확인은 돈만
// 확인하는 절차라 status(approved)는 그대로 둔다.

const visitDocContext = (r) => ({
  cancelled:
    r.status === 'cancelled_by_guest' ||
    r.status === 'cancelled_by_host' ||
    r.status === 'rejected' ||
    r.status === 'expired',
});

exports.markVisitDepositSent = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const uid = request.auth.uid;
    const reservationId = String((request.data || {}).reservationId || '');
    if (!reservationId) {
      throw new HttpsError('invalid-argument', 'reservationId가 필요합니다.');
    }

    const db = admin.firestore();
    const ref = db.collection('placeVisitReservations').doc(reservationId);

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) throw new HttpsError('not-found', '예약을 찾을 수 없어요.');
      const r = snap.data();
      if (r.requesterId !== uid) {
        throw new HttpsError('permission-denied', '내 예약만 처리할 수 있어요.');
      }
      // 트랜잭션 안에서 다시 읽은 값으로 판정한다 — 두 번 눌러도 두 번째는
      // 여기서 걸린다(중복 방지).
      flow.assertCanMarkSent(r.payment, visitDocContext(r));

      const patch = flow.markSentPatch(Date.now());
      tx.update(ref, {
        'payment.status': patch.status,
        'payment.depositedAtMs': patch.depositedAtMs,
      });

      if (r.hostId) {
        pushNotification(tx, db, {
          uid: r.hostId,
          role: 'host',
          type: 'visit_reservation_deposit_sent',
          title: '입금 확인 요청이 왔어요',
          body: `${r.placeName || '내 플레이스'} · ${r.date} ${formatVisitTime(r.visitAt)} — `
            + `${r.requesterName || '예약자'}님이 입금했다고 알렸어요.`,
          placeId: r.placeId,
          reservationId,
        });
      }
    });

    return { success: true, status: flow.STATUS.depositPending };
  },
);

exports.confirmVisitDeposit = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const uid = request.auth.uid;
    const reservationId = String((request.data || {}).reservationId || '');
    if (!reservationId) {
      throw new HttpsError('invalid-argument', 'reservationId가 필요합니다.');
    }

    const db = admin.firestore();
    const ref = db.collection('placeVisitReservations').doc(reservationId);

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) throw new HttpsError('not-found', '예약을 찾을 수 없어요.');
      const r = snap.data();
      if (r.hostId !== uid) {
        throw new HttpsError('permission-denied', '내 매장의 예약만 처리할 수 있어요.');
      }
      flow.assertCanConfirm(r.payment, visitDocContext(r));

      const patch = flow.confirmPatch(Date.now(), uid);
      tx.update(ref, {
        'payment.status': patch.status,
        'payment.paidAtMs': patch.paidAtMs,
        'payment.confirmedBy': patch.confirmedBy,
        // 예약 진행 상태(status)는 건드리지 않는다 — 승인은 이미 끝났고,
        // 여기서는 돈만 확인한다.
      });

      pushNotification(tx, db, {
        uid: r.requesterId,
        role: 'guest',
        type: 'visit_reservation_deposit_confirmed',
        title: '입금이 확인됐어요',
        body: `${r.placeName || '플레이스'} · ${r.date} ${formatVisitTime(r.visitAt)} — 예약이 확정 상태로 유지돼요.`,
        placeId: r.placeId,
        reservationId,
      });
    });

    return { success: true, status: flow.STATUS.paid };
  },
);

// ── 2-2. 입금기한 만료 정리 ──────────────────────────────────────────────────
//
// 기한이 지나도록 **입금대기**인 예약은 자리를 반납하고 취소한다.
// '입금확인중'은 대상이 아니다(파티와 같은 정책) — 이용자는 입금했다고 알렸는데
// 업주 확인이 늦은 것뿐일 수 있어, 자동 취소하면 이미 낸 사람을 떨어뜨린다.
//
// 업주 무응답 만료(expireStaleVisitReservations)와는 **사유가 다르다** —
// 그쪽은 status만 'expired'이고, 이쪽은 cancelReason으로 미입금임을 남긴다.
exports.expireVisitDeposits = onSchedule(
  {
    schedule: 'every 10 minutes',
    timeZone: 'Asia/Seoul',
    region: 'asia-northeast3',
  },
  async () => {
    const db = admin.firestore();
    try {
      const nowMs = Date.now();
      const snap = await db
        .collection('placeVisitReservations')
        .where('payment.status', '==', flow.STATUS.awaitingDeposit)
        .where('payment.depositDeadlineMs', '<', nowMs)
        .get();

      console.log(`[expireVisitDeposits] 만료 대상 ${snap.size}건`);

      for (const doc of snap.docs) {
        try {
          await db.runTransaction(async (tx) => {
            const fresh = await tx.get(doc.ref);
            if (!fresh.exists) return;
            const r = fresh.data();
            // 그 사이에 입금했다고 알렸거나 확인이 끝났으면 건드리지 않는다.
            if (!flow.isExpirable(r.payment, nowMs)) return;
            if (!LIVE_STATUSES.has(r.status)) return;

            const expired = flow.expirePatch(nowMs);
            tx.update(doc.ref, {
              'payment.status': expired.status,
              'payment.cancelledAtMs': expired.cancelledAtMs,
              status: 'expired',
              cancelReason: 'deposit_expired',
              expiredAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            releaseSlots(tx, db, r);

            pushNotification(tx, db, {
              uid: r.requesterId,
              role: 'guest',
              type: 'visit_reservation_deposit_expired',
              title: '방문 예약이 취소됐어요',
              body: `${r.placeName || '플레이스'} · ${r.date} ${formatVisitTime(r.visitAt)} — 입금기한이 지나 자동 취소됐어요.`,
              placeId: r.placeId,
              reservationId: doc.id,
            });
          });
        } catch (e) {
          console.error(`[expireVisitDeposits] ${doc.ref.path} 실패: ${e.message}`);
        }
      }
    } catch (e) {
      await logScheduledFunctionError(db, 'expireVisitDeposits', e);
    }
  },
);

// ── 3. 취소 (이용자 본인 또는 업주) ───────────────────────────────────────────

exports.cancelVisitReservation = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const uid = request.auth.uid;
    const data = request.data || {};
    const reservationId = String(data.reservationId || '');
    const message = String(data.message || '').trim().slice(0, 300);
    if (!reservationId) {
      throw new HttpsError('invalid-argument', 'reservationId가 필요합니다.');
    }

    const db = admin.firestore();
    const ref = db.collection('placeVisitReservations').doc(reservationId);

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) throw new HttpsError('not-found', '예약을 찾을 수 없어요.');
      const r = snap.data();
      const isGuest = r.requesterId === uid;
      const isHost = r.hostId === uid;
      if (!isGuest && !isHost) {
        throw new HttpsError('permission-denied', '이 예약을 취소할 권한이 없어요.');
      }
      if (!LIVE_STATUSES.has(r.status)) return; // 이미 끝난 예약 — 조용히 통과

      tx.update(ref, {
        status: isGuest ? 'cancelled_by_guest' : 'cancelled_by_host',
        hostMessage: isHost ? message : r.hostMessage || '',
        cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      releaseSlots(tx, db, r);

      // 취소는 상대방에게 알린다(내가 취소했으면 상대에게만).
      pushNotification(tx, db, {
        uid: isGuest ? r.hostId : r.requesterId,
        role: isGuest ? 'host' : 'guest',
        type: 'visit_reservation_cancelled',
        title: isGuest ? '방문 예약이 취소됐어요' : '매장이 예약을 취소했어요',
        body: `${r.placeName || '플레이스'} · ${r.date} ${formatVisitTime(r.visitAt)}`
          + (isHost && message ? ` — ${message}` : ''),
        placeId: r.placeId,
        reservationId,
      });
    });

    return { success: true };
  },
);

// ── 4. 응답 없는 신청 자동 만료 (10분마다) ────────────────────────────────────

exports.expireStaleVisitReservations = onSchedule(
  {
    schedule: 'every 10 minutes',
    timeZone: 'Asia/Seoul',
    region: 'asia-northeast3',
  },
  async () => {
    const db = admin.firestore();
    try {
      const now = admin.firestore.Timestamp.now();
      const snap = await db
        .collection('placeVisitReservations')
        .where('status', '==', 'requested')
        .where('respondBy', '<', now)
        .get();

      console.log(`[expireStaleVisitReservations] 만료 대상 ${snap.size}건`);

      const CHUNK = 100;
      for (let i = 0; i < snap.docs.length; i += CHUNK) {
        const batch = db.batch();
        for (const doc of snap.docs.slice(i, i + CHUNK)) {
          const r = doc.data();
          batch.update(doc.ref, {
            status: 'expired',
            expiredAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          releaseSlots(batch, db, r);
          pushNotification(batch, db, {
            uid: r.requesterId,
            role: 'guest',
            type: 'visit_reservation_expired',
            title: '방문 예약 신청이 만료됐어요',
            body: `${r.placeName || '플레이스'} · ${r.date} ${formatVisitTime(r.visitAt)} — 매장 응답이 없어 자동 취소됐어요.`,
            placeId: r.placeId,
            reservationId: doc.id,
          });
        }
        await batch.commit();
      }

      console.log(`[expireStaleVisitReservations] 완료 — ${snap.size}건`);
    } catch (e) {
      await logScheduledFunctionError(db, 'expireStaleVisitReservations', e);
      throw e;
    }
  },
);

// ── 공통 ─────────────────────────────────────────────────────────────────────

/** 예약이 잡고 있던 좌석 수를 슬롯 문서에서 되돌린다. */
function releaseSlots(batchOrTx, db, reservation) {
  const slotIds = reservation.slotIds || [];
  if (!slotIds.length || !reservation.placeId) return;
  const slotsRef = db.collection('events').doc(reservation.placeId).collection('visitSlots');
  const people = Number(reservation.peopleCount) || 0;
  for (const id of slotIds) {
    batchOrTx.set(
      slotsRef.doc(id),
      {
        reservedPeople: admin.firestore.FieldValue.increment(-people),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }
}

/** Timestamp → 'HH:mm'(KST). 알림 문구용. */
function formatVisitTime(ts) {
  if (!ts || typeof ts.toDate !== 'function') return '';
  const kst = new Date(ts.toDate().getTime() + 9 * 60 * 60 * 1000);
  return `${pad2(kst.getUTCHours())}:${pad2(kst.getUTCMinutes())}`;
}

// 장소대여(방) 예약의 "시간 구간(window)" 계산·겹침 판정 공통 헬퍼 —
// placeReservations.js(개별 예약)와 packageBookings.js(숙박+파티 패키지
// 예약)가 동일한 로직을 공유한다. 원래 placeReservations.js에 있던 코드를
// 그대로 옮긴 것으로, 동작은 바뀌지 않는다.

const { HttpsError } = require('firebase-functions/v2/https');
// 호스트 결제 정책(예약금) 필드 추출 — 룸/장소 문서 최상단에 평평하게 저장된다.
const paymentPolicyModule = require('./paymentPolicy');
const {
  normalizeApprovalMode,
  normalizeApprovalHours,
} = require('./placeReservationFlow');

const PENDING_TTL_MS = 10 * 60 * 1000; // 결제 대기 10분 — 이후 자동 만료
const WEEKDAY_LABELS = ['월', '화', '수', '목', '금', '토', '일'];

function parseTimeStr(t) {
  if (typeof t !== 'string' || !t.includes(':')) return 0;
  const [h, m] = t.split(':').map((n) => parseInt(n, 10));
  return (h || 0) * 60 + (m || 0);
}

// 'YYYY-MM-DD' 문자열을 그 날짜의 KST 자정(UTC 기준 Date)으로 변환.
function kstMidnight(dateStr) {
  const d = new Date(`${dateStr}T00:00:00+09:00`);
  if (Number.isNaN(d.getTime())) {
    throw new HttpsError('invalid-argument', '날짜 형식이 올바르지 않습니다.');
  }
  return d;
}

const KST_OFFSET_MS = 9 * 60 * 60 * 1000;

// 1=월 ~ 7=일 (place_detail_screen.dart의 _weekdays 인덱싱과 동일한 순서)
function kstWeekdayLabel(midnight) {
  const kst = new Date(midnight.getTime() + KST_OFFSET_MS);
  const utcDay = kst.getUTCDay(); // 0=일 ~ 6=토
  const mondayFirst = utcDay === 0 ? 6 : utcDay - 1; // 0=월 ~ 6=일
  return WEEKDAY_LABELS[mondayFirst];
}

function windowsOverlap(a, b) {
  return a.start < b.end && a.end > b.start;
}

// ── 예약 방식(복수 선택) ──────────────────────────────────────────────────────
// 'stay'(숙박 1박) | 'hourly'(시간제) | 'package'. 룸 문서의 정본은
// reservationModes 배열이고, reservationMode(단수)는 아직 업데이트되지 않은
// 앱을 위한 하위호환 미러다. 해석 규칙은 클라이언트
// (party_app/lib/models/reservation_modes.dart)와 반드시 같아야 한다.

const RESERVATION_MODES = ['stay', 'hourly', 'package'];

function normalizeReservationModes(cfg, packages) {
  const raw = cfg.reservationModes;
  if (Array.isArray(raw)) {
    const parsed = raw.filter((m) => RESERVATION_MODES.includes(m));
    if (parsed.length > 0) return parsed;
  }
  switch (cfg.reservationMode) {
    case 'both': return ['hourly', 'package'];
    case 'hourly': return ['hourly'];
    case 'package': return ['package'];
    // 'daily'는 옛 하루단위 대여 값 — 의미상 숙박에 가장 가깝다.
    case 'stay':
    case 'daily': return ['stay'];
    default: break;
  }
  return packages.length > 0 ? ['package'] : ['hourly'];
}

// 숙박 예약은 하나가 여러 날에 걸쳐 있어서, 겹침 판정용 슬롯 조회를 하루보다
// 훨씬 넓게 해야 한다 — 선택한 날짜를 "관통하는" 장기 숙박을 놓치지 않으려는
// 것(placeReservations.js / packageBookings.js가 이 값을 그대로 쓴다).
const STAY_LOOKBACK_DAYS = 31;

// ── 룸/장소 설정 로드 (룸 있으면 룸 스키마, 없으면 place 구 스키마로 폴백) ──────

async function loadReservationConfig(db, placeId, roomId) {
  const placeRef = db.collection('places').doc(placeId);
  const placeSnap = await placeRef.get();
  if (!placeSnap.exists) throw new HttpsError('not-found', '장소를 찾을 수 없어요.');
  const placeData = placeSnap.data();

  let cfg = placeData;
  if (roomId) {
    const roomSnap = await db.collection('placeRooms').doc(roomId).get();
    if (!roomSnap.exists || roomSnap.data().placeId !== placeId) {
      throw new HttpsError('not-found', '룸을 찾을 수 없어요.');
    }
    cfg = roomSnap.data();
  }

  const packages = (Array.isArray(cfg.packages) ? cfg.packages : [])
    .filter((p) => p && p.isActive !== false);
  const reservationModes = normalizeReservationModes(cfg, packages);

  return {
    hostId: placeData.hostId || null,
    placeName: placeData.name || null,
    roomName: roomId ? (cfg.roomName || null) : null,
    reservationModes,
    packages,
    // 승인 방식 — 'auto'(신청 즉시 확정) | 'manual'(업주 승인 후 확정).
    // 룸에 설정이 없으면 장소 문서를 보고, 그것도 없으면 'auto'다(지금까지
    // 장소대여에는 승인 단계가 아예 없었으므로 그 동작을 그대로 지킨다).
    approvalMode: normalizeApprovalMode(
      cfg.reservationApprovalMode || placeData.reservationApprovalMode,
    ),
    approvalHours: normalizeApprovalHours(
      cfg.reservationApprovalHours || placeData.reservationApprovalHours,
    ),
    // 호스트 결제 정책(전액 선결제 / 예약금 / 현장 전액결제) — 승인 방식과
    // 같은 규칙으로 룸 설정을 먼저 보고 없으면 장소 문서를 본다. 둘 다 없으면
    // null이고, 그때는 지금까지처럼 구매자가 결제수단을 자유롭게 고른다.
    // (정규화·검증은 paymentPolicy.normalizePolicy가 호출 시점에 한다 —
    //  여기서는 원본을 그대로 실어 나른다.)
    // 정책 필드는 룸/장소 문서 최상단에 평평하게 저장된다(paymentMode 등).
    paymentPolicy:
      paymentPolicyModule.pickPolicyFields(cfg) ||
      paymentPolicyModule.pickPolicyFields(placeData),
    // 숙박(1박) 설정 — StayConfig(reservation_modes.dart)와 같은 필드.
    stayPricePerNight: Number(cfg.stayPricePerNight) || 0,
    stayCheckInMinutes: parseTimeStr(cfg.stayCheckInTime || '16:00'),
    stayCheckOutMinutes: parseTimeStr(cfg.stayCheckOutTime || '11:00'),
    stayMinNights: Number(cfg.stayMinNights) || 1,
    stayMaxNights: cfg.stayMaxNights != null ? Number(cfg.stayMaxNights) : null,
    unitMinutes: Number(cfg.bookingUnitMinutes) || 60,
    openMinutes: cfg.openTime ? parseTimeStr(cfg.openTime)
      : (Number(cfg.openHour) || 9) * 60,
    closeMinutes: cfg.closeTime ? parseTimeStr(cfg.closeTime)
      : (Number(cfg.closeHour) || 23) * 60,
    minBookingMinutes: Number(cfg.minBookingMinutes)
      || (Number(cfg.minHours) || 1) * 60,
    maxBookingMinutes: cfg.maxBookingMinutes != null ? Number(cfg.maxBookingMinutes) : null,
    pricePerHour: Number(cfg.pricePerHour) || 0,
    capacity: Number(cfg.capacityMax || cfg.capacity || cfg.maxCapacity) || 50,
  };
}

// ── 요청 → 예약 구간(window) 목록 계산 + 검증 ──────────────────────────────────

function computeWindows(cfg, bookingType, data) {
  // 숙박(1박 단위) — 체크인 시각부터 N일 뒤 체크아웃 시각까지를 하나의
  // 구간으로 점유한다. 예) 체크인 16:00 / 체크아웃 11:00 짜리 2박이면
  // 자정 기준 960분 ~ 3540분(2×1440+660). 이렇게 두면 그 사이에 들어오는
  // 시간제·패키지 예약이 같은 겹침 판정 함수 하나로 전부 걸러진다.
  if (bookingType === 'stay') {
    if (!cfg.reservationModes.includes('stay')) {
      throw new HttpsError('failed-precondition', '이 룸은 숙박 예약을 지원하지 않아요.');
    }
    const nights = Number(data.nights) || 0;
    if (!Number.isInteger(nights) || nights < 1) {
      throw new HttpsError('invalid-argument', '숙박일 수가 올바르지 않습니다.');
    }
    if (nights < cfg.stayMinNights) {
      throw new HttpsError('failed-precondition', `최소 ${cfg.stayMinNights}박부터 예약할 수 있어요.`);
    }
    if (cfg.stayMaxNights != null && nights > cfg.stayMaxNights) {
      throw new HttpsError('failed-precondition', `최대 ${cfg.stayMaxNights}박까지 예약할 수 있어요.`);
    }
    const start = cfg.stayCheckInMinutes;
    const end = nights * 1440 + cfg.stayCheckOutMinutes;
    if (end <= start) {
      throw new HttpsError('failed-precondition', '체크인/체크아웃 시각 설정이 올바르지 않아요.');
    }
    return {
      windows: [{ start, end, price: cfg.stayPricePerNight * nights }],
      totalMinutes: end - start,
      packageId: null,
      packageName: null,
    };
  }

  if (bookingType === 'daily') {
    const totalMinutes = 1440;
    return {
      windows: [{ start: 0, end: 1440, price: Math.round(cfg.pricePerHour * 24) }],
      totalMinutes,
      packageId: null,
      packageName: null,
    };
  }

  if (bookingType === 'package') {
    if (!cfg.reservationModes.includes('package')) {
      throw new HttpsError('failed-precondition', '이 룸은 패키지 예약을 지원하지 않아요.');
    }
    const packageId = data.packageId;
    const pkg = cfg.packages.find((p) => p.id === packageId);
    if (!pkg) throw new HttpsError('not-found', '패키지를 찾을 수 없어요.');

    const days = Array.isArray(pkg.days) ? pkg.days : [];
    if (days.length > 0 && !days.includes(data.weekdayLabel)) {
      throw new HttpsError('failed-precondition', '선택한 날짜에는 이용할 수 없는 패키지예요.');
    }
    const minPeople = pkg.minPeople != null ? Number(pkg.minPeople) : null;
    const maxPeople = pkg.maxPeople != null ? Number(pkg.maxPeople) : null;
    if (minPeople != null && data.peopleCount < minPeople) {
      throw new HttpsError('failed-precondition', `최소 ${minPeople}명부터 예약할 수 있어요.`);
    }
    if (maxPeople != null && data.peopleCount > maxPeople) {
      throw new HttpsError('failed-precondition', `최대 ${maxPeople}명까지 예약할 수 있어요.`);
    }

    const start = parseTimeStr(pkg.startTime);
    let end = parseTimeStr(pkg.endTime);
    if (end <= start) end += 1440; // 익일까지(올나잇 등)
    const price = Number(pkg.price) || 0;

    return {
      windows: [{ start, end, price }],
      totalMinutes: end - start,
      packageId: pkg.id,
      packageName: pkg.name || null,
    };
  }

  // hourly
  if (!cfg.reservationModes.includes('hourly')) {
    throw new HttpsError('failed-precondition', '이 룸은 시간제 예약을 지원하지 않아요.');
  }
  const ranges = Array.isArray(data.ranges) ? data.ranges : [];
  if (ranges.length === 0) {
    throw new HttpsError('invalid-argument', '예약 시간을 선택해주세요.');
  }

  const windows = [];
  let totalMinutes = 0;
  const sorted = [...ranges].sort((a, b) => a.start - b.start);
  for (const r of sorted) {
    const start = Number(r.start);
    const end = Number(r.end);
    if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start) {
      throw new HttpsError('invalid-argument', '예약 시간 형식이 올바르지 않습니다.');
    }
    if ((start - cfg.openMinutes) % cfg.unitMinutes !== 0
      || (end - start) % cfg.unitMinutes !== 0) {
      throw new HttpsError('invalid-argument', '예약 시간 단위가 올바르지 않습니다.');
    }
    if (start < cfg.openMinutes || end > cfg.closeMinutes) {
      throw new HttpsError('failed-precondition', '운영 시간 밖입니다.');
    }
    const duration = end - start;
    const price = Math.round((cfg.pricePerHour * duration) / 60);
    windows.push({ start, end, price });
    totalMinutes += duration;
  }
  // 요청 구간끼리 겹치지 않는지도 확인 (클라이언트 버그로 중복 전송된 경우 방지)
  for (let i = 0; i < windows.length; i++) {
    for (let j = i + 1; j < windows.length; j++) {
      if (windowsOverlap(windows[i], windows[j])) {
        throw new HttpsError('invalid-argument', '선택한 시간이 중복됩니다.');
      }
    }
  }

  if (totalMinutes < cfg.minBookingMinutes) {
    throw new HttpsError('failed-precondition', `최소 ${cfg.minBookingMinutes}분 이상 선택해주세요.`);
  }
  if (cfg.maxBookingMinutes != null && totalMinutes > cfg.maxBookingMinutes) {
    throw new HttpsError('failed-precondition', `최대 ${cfg.maxBookingMinutes}분까지 예약할 수 있어요.`);
  }

  return { windows, totalMinutes, packageId: null, packageName: null };
}

module.exports = {
  PENDING_TTL_MS,
  WEEKDAY_LABELS,
  RESERVATION_MODES,
  STAY_LOOKBACK_DAYS,
  normalizeReservationModes,
  parseTimeStr,
  kstMidnight,
  kstWeekdayLabel,
  windowsOverlap,
  loadReservationConfig,
  computeWindows,
};

// 장소대여(방) 예약의 "시간 구간(window)" 계산·겹침 판정 공통 헬퍼 —
// placeReservations.js(개별 예약)와 packageBookings.js(숙박+파티 패키지
// 예약)가 동일한 로직을 공유한다. 원래 placeReservations.js에 있던 코드를
// 그대로 옮긴 것으로, 동작은 바뀌지 않는다.

const { HttpsError } = require('firebase-functions/v2/https');

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
  const reservationMode = cfg.reservationMode
    || (packages.length > 0 ? 'package' : 'hourly');

  return {
    hostId: placeData.hostId || null,
    placeName: placeData.name || null,
    roomName: roomId ? (cfg.roomName || null) : null,
    reservationMode,
    packages,
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
    if (cfg.reservationMode === 'hourly') {
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
  if (cfg.reservationMode === 'package') {
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
  parseTimeStr,
  kstMidnight,
  kstWeekdayLabel,
  windowsOverlap,
  loadReservationConfig,
  computeWindows,
};

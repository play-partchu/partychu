// party_app의 party_card_widget.dart(PartyCard.parsePartyDateTime 등)와
// functions/partyLandingPage.js의 표시 로직을 웹에서 동일하게 재현한다 —
// 같은 Firestore 문서를 앱과 동일한 방식으로 읽고 보여주기 위함.

const KST_OFFSET_MS = 9 * 60 * 60 * 1000;
const WEEKDAY_KO = ['일', '월', '화', '수', '목', '금', '토'];

export function toDate(value) {
  if (!value) return null;
  if (typeof value.toDate === 'function') return value.toDate();
  if (typeof value.seconds === 'number') return new Date(value.seconds * 1000);
  if (typeof value === 'string' && value) {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  return null;
}

// party_card_widget.dart의 PartyCard.parsePartyDateTime과 동일한 우선순위:
// partyDateTime(Timestamp) → startDateTime(Timestamp|String) → date(String).
export function partyDateTime(data) {
  return (
    toDate(data.partyDateTime) ||
    toDate(data.startDateTime) ||
    toDate(data.date)
  );
}

export function formatKstDateTime(date) {
  if (!date) return null;
  const kst = new Date(date.getTime() + KST_OFFSET_MS);
  const y = kst.getUTCFullYear();
  const m = kst.getUTCMonth() + 1;
  const d = kst.getUTCDate();
  const weekday = WEEKDAY_KO[kst.getUTCDay()];
  const hour24 = kst.getUTCHours();
  const period = hour24 < 12 ? '오전' : '오후';
  const hour12 = hour24 % 12 === 0 ? 12 : hour24 % 12;
  const minute = String(kst.getUTCMinutes()).padStart(2, '0');
  return `${y}.${String(m).padStart(2, '0')}.${String(d).padStart(2, '0')} (${weekday}) ${period} ${hour12}:${minute}`;
}

export function formatFee(data) {
  const maleFee = Number(data.maleFee ?? NaN);
  const femaleFee = Number(data.femaleFee ?? NaN);
  const fee = Number(data.fee ?? NaN);
  const fmt = (n) => (n <= 0 ? '무료' : `${n.toLocaleString('ko-KR')}원`);
  if (!Number.isNaN(maleFee) && !Number.isNaN(femaleFee) && maleFee !== femaleFee) {
    return `여성 ${fmt(femaleFee)} · 남성 ${fmt(maleFee)}`;
  }
  const base = !Number.isNaN(maleFee)
    ? maleFee
    : !Number.isNaN(femaleFee)
      ? femaleFee
      : Number.isNaN(fee) ? 0 : fee;
  return fmt(base);
}

export function addressLabel(data) {
  return data.roadAddress || data.address || data.location || '';
}

export function coverImage(data) {
  return (
    data.coverThumbnailUrl ||
    data.coverImageUrl ||
    data.mainImageUrl ||
    (Array.isArray(data.images) && data.images[0]) ||
    (Array.isArray(data.imageUrls) && data.imageUrls[0]) ||
    data.videoThumbnailUrl ||
    null
  );
}

export function capacityLabel(data) {
  const cap = Number(data.maxParticipants ?? data.maxCapacity ?? 0);
  if (!(cap > 0)) return null;
  const current =
    data.genderCapacityMode === 'separate'
      ? Number(data.currentMaleCount ?? 0) + Number(data.currentFemaleCount ?? 0)
      : Number(data.currentParticipants ?? 0);
  return `${current} / ${cap}명`;
}

export function genderLabel(data) {
  const gl = data.genderLimit || 'all';
  const gcm = data.genderCapacityMode || 'unlimited';
  const gm = data.genderMode || '';
  if (gl === 'male') return '남자만';
  if (gl === 'female') return '여자만';
  if (gm === 'balanced' || gcm === 'separate') return '성비 맞춤';
  return '남녀무관';
}

export function isRecruitClosed(data) {
  const stored = data.recruitStatus || '모집중';
  if (stored !== '모집중') return true;
  const deadline = toDate(data.recruitDeadlineAt);
  if (deadline && deadline.getTime() < Date.now()) return true;
  const dt = partyDateTime(data);
  return !!(dt && dt.getTime() < Date.now());
}

function startOfDayUtc(date) {
  return Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate());
}

// party_card_widget.dart의 PartyCard.isVisibleInList와 동일 — 이미 지난
// 날짜의 파티는 목록에서 제외한다(오늘은 포함).
export function isUpcoming(data) {
  const dt = partyDateTime(data);
  if (!dt) return true;
  const now = new Date();
  return startOfDayUtc(dt) >= startOfDayUtc(now);
}

// main_screen.dart의 날짜 카테고리 탭(오늘/내일/이번 주/이번 주말)을 웹에서
// 근사적으로 재현한다 — KST 기준, 이번 주는 "오늘부터 이번 주 일요일까지",
// 이번 주말은 "이번 주 토·일" 기준.
export function matchesCategory(data, category) {
  if (category === 'all') return true;
  const dt = partyDateTime(data);
  if (!dt) return false;

  const kstNow = new Date(Date.now() + KST_OFFSET_MS);
  const kstDt = new Date(dt.getTime() + KST_OFFSET_MS);
  const todayStart = startOfDayUtc(kstNow);
  const dtStart = startOfDayUtc(kstDt);
  const diffDays = Math.round((dtStart - todayStart) / 86400000);

  if (category === 'today') return diffDays === 0;
  if (category === 'tomorrow') return diffDays === 1;

  const weekday = kstNow.getUTCDay(); // 0=일요일 ... 6=토요일
  const daysUntilSunday = weekday === 0 ? 0 : 7 - weekday;
  if (category === 'week') return diffDays >= 0 && diffDays <= daysUntilSunday;

  if (category === 'weekend') {
    const dtWeekday = kstDt.getUTCDay();
    return diffDays >= 0 && diffDays <= daysUntilSunday && (dtWeekday === 6 || dtWeekday === 0);
  }
  return true;
}

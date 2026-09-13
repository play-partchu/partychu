// 정기 파티(scheduleType: 'recurring') 일정 해석 — 서버 판정용.
//
// 클라이언트의 lib/models/party_schedule.dart와 **같은 규칙**을 다시 구현한
// 것이다. 두 곳의 판정이 어긋나면 "앱에서는 신청 버튼이 열려 있는데 서버가
// 거부"하는 최악의 상태가 되므로, 자정 넘김·다음 회차·마감 계산 규칙을 바꿀
// 때는 반드시 양쪽을 함께 고쳐야 한다.
//
// 시간대: 파티 일정의 '19:00' 같은 값은 한국 시간(KST) 벽시계 기준이다.
// Cloud Functions는 UTC로 돌기 때문에, 이 파일 안의 모든 날짜 계산은
// 기존 index.js/packageBookings.js와 동일한 "+9시간 시프트 후 UTC 필드 읽기"
// 방식으로 KST 달력을 다룬다(한국은 서머타임이 없어 고정 오프셋으로 정확하다).

const KST_OFFSET_MS = 9 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

// Date#getUTCDay() 인덱스(0=일)와 맞춘 요일 키 — Firestore weeklySchedule의 키.
const WEEKDAY_KEYS = [
  'sunday',
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
];

// Firestore Timestamp / Date / ISO 문자열 / epoch 숫자를 모두 Date로 정규화.
function toDate(value) {
  if (!value) return null;
  if (value instanceof Date) return isNaN(value.getTime()) ? null : value;
  if (typeof value.toDate === 'function') {
    const d = value.toDate();
    return d instanceof Date && !isNaN(d.getTime()) ? d : null;
  }
  if (typeof value === 'number') return new Date(value);
  if (typeof value === 'string') {
    const d = new Date(value);
    return isNaN(d.getTime()) ? null : d;
  }
  // {_seconds, _nanoseconds} 형태(직렬화된 Timestamp)
  if (typeof value._seconds === 'number') return new Date(value._seconds * 1000);
  return null;
}

// 절대 시각이 속한 "KST 달력 날짜"의 00:00(절대 시각)을 돌려준다.
function kstMidnightOf(date) {
  const shifted = new Date(date.getTime() + KST_OFFSET_MS);
  return new Date(
    Date.UTC(shifted.getUTCFullYear(), shifted.getUTCMonth(), shifted.getUTCDate()) -
      KST_OFFSET_MS
  );
}

// KST 자정(절대 시각) → 비교용 정수(YYYYMMDD)와 요일 키.
function kstDayInfo(kstMidnight) {
  const shifted = new Date(kstMidnight.getTime() + KST_OFFSET_MS);
  const y = shifted.getUTCFullYear();
  const m = shifted.getUTCMonth() + 1;
  const d = shifted.getUTCDate();
  return {
    number: y * 10000 + m * 100 + d,
    weekdayKey: WEEKDAY_KEYS[shifted.getUTCDay()],
  };
}

// '19:00' → 분 단위(1140). 형식이 틀리면 null.
function parseHmToMinutes(value) {
  if (typeof value !== 'string') return null;
  const match = /^(\d{1,2}):(\d{2})$/.exec(value.trim());
  if (!match) return null;
  const h = Number(match[1]);
  const m = Number(match[2]);
  if (h < 0 || h > 23 || m < 0 || m > 59) return null;
  return h * 60 + m;
}

// Firestore의 recurringSchedule 맵을 계산하기 좋은 형태로 정규화한다.
// 형식이 깨졌거나 켜진 요일이 하나도 없으면 null(= 열릴 회차 없음).
function parseRecurringSchedule(raw) {
  if (!raw || typeof raw !== 'object') return null;

  const startDate = toDate(raw.startDate);
  if (!startDate) return null;
  const endDate = toDate(raw.endDate); // null이면 종료일 없음(무기한)

  const weeklyRaw = raw.weeklySchedule;
  if (!weeklyRaw || typeof weeklyRaw !== 'object') return null;

  const weekly = {};
  for (const key of WEEKDAY_KEYS) {
    const slot = weeklyRaw[key];
    if (!slot || typeof slot !== 'object') continue;
    // enabled 키가 없는 문서는 "칸이 있으면 켜진 것"으로 해석한다(Dart와 동일).
    if (slot.enabled === false) continue;
    const start = parseHmToMinutes(slot.startTime);
    const end = parseHmToMinutes(slot.endTime);
    if (start == null || end == null) continue;
    weekly[key] = { startMin: start, endMin: end };
  }
  if (Object.keys(weekly).length === 0) return null;

  const deadline = parseDeadlineRule(raw.registrationDeadline);
  // 모집 시작 규칙 — 없던 예전 문서는 "제한 없음"이라 null로 둔다.
  const open = raw.registrationOpen
    ? parseDeadlineRule(raw.registrationOpen)
    : null;

  const startMidnight = kstMidnightOf(startDate);
  const endMidnight = endDate ? kstMidnightOf(endDate) : null;
  return {
    // KST 자정(절대 시각)과 비교용 정수(YYYYMMDD)를 함께 들고 있는다 —
    // 정수는 기간 판정에, 자정 시각은 "시작일부터 훑기"에 쓴다.
    startMidnight,
    startDayNumber: kstDayInfo(startMidnight).number,
    // 종료일 쪽도 같은 짝을 들고 있는다 — 마지막 회차를 찾을 때
    // "종료일부터 거꾸로 훑기"가 필요하다([finalPartyEndAt]).
    endMidnight,
    endDayNumber: endMidnight ? kstDayInfo(endMidnight).number : null,
    weekly,
    deadline,
    open,
  };
}

// Firestore의 모집 마감 규칙 맵을 계산하기 좋은 형태로 정규화한다.
//
// 클라이언트 lib/models/party_schedule.dart의 PartyRecruitDeadlineRule과
// **같은 규칙**이다 — 한쪽만 고치면 "앱에는 아직 모집 중인데 서버는 마감"인
// 상태가 된다.
//
// 예전 키도 그대로 읽는다: hoursBefore → beforeStart(hours × 60분),
// sameDayTime → startDayTime.
function parseDeadlineRule(raw) {
  if (!raw || typeof raw !== 'object') {
    return { mode: 'beforeStart', minutes: 60, timeMin: null, atMs: null };
  }
  let mode = raw.mode || 'beforeStart';
  if (mode === 'hoursBefore') mode = 'beforeStart';
  if (mode === 'sameDayTime') mode = 'startDayTime';

  // 새 문서는 전체 분('minutes'), 예전 문서는 시간('hours')만 갖고 있다.
  const rawMinutes = Number(raw.minutes);
  const rawHours = Number(raw.hours);
  const minutes = Number.isFinite(rawMinutes)
    ? rawMinutes
    : Number.isFinite(rawHours)
      ? rawHours * 60
      : 60;

  const at = toDate(raw.atMs != null ? raw.atMs : raw.at);
  return {
    mode,
    minutes: minutes < 0 ? 0 : minutes,
    timeMin: parseHmToMinutes(raw.time),
    atMs: at ? at.getTime() : null,
  };
}

// 회차 시작 시각에 마감 규칙을 적용한다 — Dart의 resolve()와 같은 규칙.
//
//  · beforeStart   : 시작에서 N분 전(분 단위로 저장한다)
//  · startDayTime  : 시작 '날짜'의 지정 시각. 시작보다 뒤로 계산되면 시작
//                    시각으로 당긴다(= 실수로 시작 후 신청이 열리지 않도록).
//  · prevDayTime   : 시작 '전날'의 지정 시각
//  · customDateTime: 저장된 절대 시각 그대로. 호스트가 직접 확인하고 고른
//                    값이라 시작 이후여도 그대로 두되, 회차 종료는 못 넘는다.
function resolveDeadline(rule, kstMidnight, start, end) {
  if (!rule || rule.mode === 'none') return null;

  switch (rule.mode) {
    case 'startDayTime': {
      if (rule.timeMin == null) return null;
      const at = new Date(kstMidnight.getTime() + rule.timeMin * 60000);
      return at.getTime() > start.getTime() ? start : at;
    }
    case 'prevDayTime': {
      if (rule.timeMin == null) return null;
      return new Date(kstMidnight.getTime() - DAY_MS + rule.timeMin * 60000);
    }
    case 'customDateTime': {
      if (rule.atMs == null) return null;
      const at = new Date(rule.atMs);
      if (end && at.getTime() > end.getTime()) return end;
      return at;
    }
    default: {
      // beforeStart(예전 hoursBefore 포함)
      const minutes = Number.isFinite(rule.minutes) ? rule.minutes : 60;
      return new Date(start.getTime() - minutes * 60000);
    }
  }
}

// 주어진 KST 날짜(자정 절대 시각)에 열리는 회차. 없으면 null.
function occurrenceOnKstDay(schedule, kstMidnight) {
  const info = kstDayInfo(kstMidnight);
  if (info.number < schedule.startDayNumber) return null;
  if (schedule.endDayNumber != null && info.number > schedule.endDayNumber) return null;

  const slot = schedule.weekly[info.weekdayKey];
  if (!slot) return null;

  const start = new Date(kstMidnight.getTime() + slot.startMin * 60000);
  let end = new Date(kstMidnight.getTime() + slot.endMin * 60000);
  // 자정을 넘기는 시간대(19:00~03:00)는 종료를 다음 날로 넘긴다.
  if (end.getTime() <= start.getTime()) end = new Date(end.getTime() + DAY_MS);

  return {
    start,
    end,
    deadline: resolveDeadline(schedule.deadline, kstMidnight, start, end),
    recruitOpenAt: resolveDeadline(schedule.open, kstMidnight, start, end),
  };
}

// [now] 시점에 아직 끝나지 않은 가장 가까운 회차. 진행 중인 회차(어제 19시
// 시작 → 오늘 새벽 3시 종료)도 포함하므로 하루 전부터 훑는다.
// 종료일이 지나 남은 회차가 없으면 null.
function nextOccurrence(schedule, now) {
  let cursor = new Date(kstMidnightOf(now).getTime() - DAY_MS);
  // 운영 시작일이 아직 한참 뒤면(예: 다음 달부터 시작) 지금 근처를 훑어봐야
  // 회차가 없다 — 시작일부터 훑어야 "첫 회차"를 찾을 수 있다
  // (클라이언트 party_schedule.dart와 동일 규칙).
  if (cursor.getTime() < schedule.startMidnight.getTime()) {
    cursor = schedule.startMidnight;
  }
  for (let i = 0; i < 9; i++) {
    if (
      schedule.endDayNumber != null &&
      kstDayInfo(cursor).number > schedule.endDayNumber
    ) {
      return null;
    }
    const occ = occurrenceOnKstDay(schedule, cursor);
    if (occ && occ.end.getTime() > now.getTime()) return occ;
    cursor = new Date(cursor.getTime() + DAY_MS);
  }
  return null;
}

// ── 파티 문서(Firestore 맵) 진입점 ──────────────────────────────────────

// 반복 여부의 **유일한 판정 기준**. 문서의 `isRecurring` 불리언은 "매주
// 반복"이 아니라 "재등록 가능"을 뜻하는 옛 이름이라 여기서도, 어디서도 쓰지
// 않는다(일회성 파티에도 true가 들어 있다).
//
// scheduleType이 없던 시절의 문서는 recurringSchedule의 존재로 판정한다 —
// 클라이언트 PartySchedule.typeOf와 같은 규칙이어야 한다.
function isRecurringParty(partyData) {
  if (!partyData) return false;
  if (partyData.scheduleType) return partyData.scheduleType === 'recurring';
  const raw = partyData.recurringSchedule;
  return !!raw && typeof raw === 'object' && Object.keys(raw).length > 0;
}

// 정기 파티의 "지금 기준 다음 회차". 일회성 파티면 null.
function nextPartyOccurrence(partyData, now = new Date()) {
  if (!isRecurringParty(partyData)) return null;
  const schedule = parseRecurringSchedule(partyData.recurringSchedule);
  if (!schedule) return null;
  return nextOccurrence(schedule, now);
}

// 이 파티의 "실제 시작 시각".
// - 정기 파티: 다음 회차의 시작 시각(남은 회차가 없으면 null)
// - 일회성 파티: 저장된 partyDateTime 그대로(기존 동작)
//
// 정기 파티에도 partyDateTime이 남아 있지만 그건 등록 시점의 "첫 회차"
// 캐시일 뿐이라 시간이 지나면 과거값이 된다 — 취소 가능 여부/환불 계산처럼
// 돈이 걸린 판정에서 그 값을 그대로 쓰면 안 된다.
function effectivePartyStartAt(partyData, now = new Date()) {
  if (isRecurringParty(partyData)) {
    const occ = nextPartyOccurrence(partyData, now);
    return occ ? occ.start : null;
  }
  return toDate(partyData ? partyData.partyDateTime : null);
}

// ── 파티가 완전히 끝나는 시각 ────────────────────────────────────────────
//
// [effectivePartyStartAt]이 "다음에 열릴 때"라면 이건 "다시는 열리지 않는
// 때"다. 보관기간(만료 자동 삭제)의 **기준점**이 이 값이다 — 지난 파티를
// 언제부터 세는지가 여기서 정해진다.
//
// 클라이언트 lib/models/party_schedule.dart의 PartySchedule.finalEndAt과
// **같은 규칙**이어야 한다(앱이 보여주는 D-day와 서버가 지우는 날이 어긋나면
// 안 된다).

// singleSchedule 맵(날짜 + 'HH:mm')을 절대 시각 창으로 푼다.
// Dart PartySingleSchedule.start/end와 같은 규칙 — 종료가 시작보다 이르거나
// 같으면 자정을 넘긴 것으로 보고 하루를 더한다(19:00~03:00).
function singleScheduleWindow(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const date = toDate(raw.date);
  const startMin = parseHmToMinutes(raw.startTime);
  if (!date || startMin == null) return null;
  const midnight = kstMidnightOf(date);
  const start = new Date(midnight.getTime() + startMin * 60000);
  const endMin = parseHmToMinutes(raw.endTime);
  if (endMin == null) return { start, end: null };
  let end = new Date(midnight.getTime() + endMin * 60000);
  if (end.getTime() <= start.getTime()) end = new Date(end.getTime() + DAY_MS);
  return { start, end };
}

// 정기 파티의 **마지막 회차 종료 시각**. 운영 종료일부터 거꾸로 훑어 켜진
// 요일을 처음 만나는 날의 회차가 마지막이다(요일이 하나라도 켜져 있으면 8일
// 안에 반드시 만난다). 종료일이 없으면(무기한) 마지막 회차가 없다 → null.
function lastRecurringEnd(schedule) {
  if (!schedule || !schedule.endMidnight) return null;
  let cursor = schedule.endMidnight;
  for (let i = 0; i < 9; i++) {
    if (cursor.getTime() < schedule.startMidnight.getTime()) return null;
    const occ = occurrenceOnKstDay(schedule, cursor);
    if (occ) return occ.end;
    cursor = new Date(cursor.getTime() - DAY_MS);
  }
  return null;
}

// 이 파티의 "최종 종료 시각".
// - 정기 파티: 마지막 회차의 종료 시각(무기한이면 null — 끝나는 때가 없다)
// - 일회성 파티: singleSchedule의 종료 시각. 종료 시각을 안 적었으면 시작
//   시각(레거시 문서는 partyDateTime)이 그대로 기준이 된다.
function finalPartyEndAt(partyData) {
  if (!partyData) return null;
  if (isRecurringParty(partyData)) {
    return lastRecurringEnd(parseRecurringSchedule(partyData.recurringSchedule));
  }
  const single = singleScheduleWindow(partyData.singleSchedule);
  if (single) return single.end || single.start;
  return toDate(partyData.partyDateTime);
}

// ── 얼리버드 종료 시각 ────────────────────────────────────────────────
//
// 클라이언트 lib/models/party_early_bird_schedule.dart의
// PartyEarlyBirdDeadlineRule.resolve()와 **같은 규칙**이다. 한쪽만 고치면
// "앱에는 얼리버드 가격이 보이는데 서버는 정상가로 결제"하는 상태가 된다.
//
//  · daysBefore : 회차 시작 '날짜'에서 N일을 뺀 날의 지정 시각(0일 = 당일)
//  · hoursBefore: 회차 시작 시각에서 N시간 전
//  · sameDayTime: 회차 당일의 지정 시각
//
// 어떤 방식이든 결과가 회차 시작을 넘으면 시작 시각으로 당긴다.
// 자정을 넘겨 끝나는 파티(19:00~03:00)도 기준은 시작 시각(19:00)이다 —
// 이 함수는 회차 종료 시각을 아예 보지 않으므로 자동으로 그렇게 동작한다.
function resolveEarlyBirdEnd(rule, start) {
  if (!rule || typeof rule !== 'object' || !start) return null;
  const timeMin = parseHmToMinutes(rule.time);
  let at = null;

  switch (rule.mode) {
    case 'daysBefore': {
      if (timeMin == null) return null;
      const days = Math.max(0, Number(rule.days) || 0);
      // 회차 시작일의 KST 자정에서 N일을 빼고 지정 시각을 얹는다.
      at = new Date(
        kstMidnightOf(start).getTime() - days * DAY_MS + timeMin * 60000
      );
      break;
    }
    case 'hoursBefore': {
      const hours = Math.max(0, Number(rule.hours) || 0);
      at = new Date(start.getTime() - hours * 60 * 60 * 1000);
      break;
    }
    case 'sameDayTime': {
      if (timeMin == null) return null;
      at = new Date(kstMidnightOf(start).getTime() + timeMin * 60000);
      break;
    }
    default:
      return null;
  }
  return at.getTime() > start.getTime() ? start : at;
}

// 파티 문서 하나의 "적용 대상 시작 시각 기준" 얼리버드 종료 시각.
//
// 종료 기준(earlyBirdEndType)은 두 가지다 — 클라이언트
// (party_early_bird_schedule.dart의 resolveEarlyBirdEndAt)와 **같은 규칙**이라
// 한쪽만 고치면 "앱에는 할인가가 보이는데 서버는 정상가로 결제"하게 된다.
//
//  · 'beforeStart' : 시작 시각에서 규칙만큼 뺀 시각.
//      - 정기 파티      : [occurrence]가 있으면 그 회차, 없으면 다음 회차의
//                         시작 시각. 남은 회차가 없으면 null(= 할인 없음).
//      - 일회성/여러 날짜: 그 문서 자신의 시작 시각. 날짜를 여러 개 고르면
//                         문서가 날짜마다 하나씩 생기므로 각자 자기 날짜가 기준.
//  · 'fixedDate'   : 저장된 earlyBirdEndAt 그대로.
//
// endType이 없는 예전 문서는 규칙 유무로 판별하고, 규칙이 없으면
// earlyBirdEndAt으로 폴백한다(하위 호환).
//
// 클라이언트가 보낸 시각은 쓰지 않는다 — 저장된 파티/회차 시작 시각으로
// 서버가 다시 계산한다.
function earlyBirdEndAtFor(partyData, now = new Date(), occurrence = null) {
  if (!partyData) return null;
  const absolute = () => toDate(partyData.earlyBirdEndAt);

  const rule = partyData.earlyBirdDeadlineRule;
  const hasRule = rule && typeof rule === 'object';
  const endType = typeof partyData.earlyBirdEndType === 'string'
    ? partyData.earlyBirdEndType
    : (hasRule ? 'beforeStart' : 'fixedDate');

  if (endType !== 'beforeStart' || !hasRule) return absolute();

  const start = occurrence
    ? occurrence.start
    : effectivePartyStartAt(partyData, now);
  if (!start) return null;
  return resolveEarlyBirdEnd(rule, start);
}

// 'YYYY-MM-DD'(회차 시작일, KST 달력 기준) → 그날 실제로 열리는 회차.
//
// 클라이언트가 보낸 occurrenceId를 **그대로 믿지 않고** 서버가 같은 일정
// 규칙으로 다시 계산해서 확인하기 위한 함수다. 그 날짜에 회차가 없으면
// (요일이 꺼져 있거나 운영 기간 밖이면) null.
function occurrenceForId(partyData, occurrenceId) {
  if (!isRecurringParty(partyData)) return null;
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(occurrenceId || '').trim());
  if (!match) return null;
  const schedule = parseRecurringSchedule(partyData.recurringSchedule);
  if (!schedule) return null;
  const kstMidnight = new Date(
    Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])) - KST_OFFSET_MS
  );
  return occurrenceOnKstDay(schedule, kstMidnight);
}

// 정기 파티의 모집 마감 상태. 일회성 파티는 이 함수를 쓰지 않는다
// (기존 recruitDeadlineAt 검사 그대로).
//
// 반환: { open: boolean, reason: 'ok' | 'ended' | 'deadline' | 'notYet' | 'invalid' }
// - ended   : 운영 종료일이 지나 더 열릴 회차가 없음
// - deadline: 다음 회차의 모집 마감 시각이 이미 지남
// - notYet  : 다음 회차의 모집 시작 시각이 아직 오지 않음
// - invalid : recurringSchedule이 없거나 깨짐(등록 화면이 만들 수 없는 형태)
function checkRecurringRecruitOpen(partyData, now = new Date()) {
  const schedule = parseRecurringSchedule(partyData.recurringSchedule);
  if (!schedule) return { open: false, reason: 'invalid' };
  const occ = nextOccurrence(schedule, now);
  if (!occ) return { open: false, reason: 'ended' };
  if (occ.deadline && occ.deadline.getTime() < now.getTime()) {
    return { open: false, reason: 'deadline', occurrence: occ };
  }
  if (occ.recruitOpenAt && occ.recruitOpenAt.getTime() > now.getTime()) {
    return { open: false, reason: 'notYet', occurrence: occ };
  }
  return { open: true, reason: 'ok', occurrence: occ };
}

module.exports = {
  KST_OFFSET_MS,
  WEEKDAY_KEYS,
  toDate,
  // 등록 조립(partyRegistration.js)이 같은 마감 계산을 재사용한다 — 규칙을
  // 두 번 구현하지 않기 위해 순수 함수 두 개를 함께 내보낸다.
  parseDeadlineRule,
  resolveDeadline,
  parseRecurringSchedule,
  occurrenceOnKstDay,
  kstMidnightOf,
  nextOccurrence,
  isRecurringParty,
  nextPartyOccurrence,
  effectivePartyStartAt,
  // 보관기간(만료 자동 삭제)의 기준점 — index.js의 deleteExpiredParties가 쓴다.
  singleScheduleWindow,
  lastRecurringEnd,
  finalPartyEndAt,
  checkRecurringRecruitOpen,
  occurrenceForId,
  resolveEarlyBirdEnd,
  earlyBirdEndAtFor,
};

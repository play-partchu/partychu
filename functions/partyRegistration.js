// ── 파티 등록 — 앱·웹이 공유하는 단 하나의 조립·검증 규칙 ────────────────────
//
// 이 파일이 하는 일은 딱 하나다: **"호스트가 고른 원시값" 하나를 받아서
// parties 문서 필드를 만든다.** 값을 어디에 그릴지(앱 화면 / 웹 폼)는 이
// 파일이 모른다.
//
// ── 왜 이 파일이 생겼나 ─────────────────────────────────────────────────
//
// 파티 등록은 지금까지 **클라이언트가 Firestore에 직접 쓰는** 구조였다
// (party_register_screen.dart의 collection('parties').add). firestore.rules의
// parties create가 검사하는 것은 hostId·openState·hostBusinessVerified 뿐이라,
// 참가비·정원·차수·일정·얼리버드가 서로 맞는지는 **오직 Dart 화면 코드만**
// 알고 있었다.
//
// 웹 등록이 생기면 그 판정이 한 벌 더 늘어난다. 앱과 웹이 각자 계산하면
// "같은 입력인데 문서 모양이 다른 파티"가 만들어지고, 그건 나중에
// applyToParty가 금액을 다르게 계산하는 형태로 터진다. 그래서 조립·검증을
// 여기 한 곳으로 모으고, 웹은 createParty(Functions)를 통해서만 등록한다.
//
// ── 이 파일의 정본은 "지금 앱이 저장하는 결과"다 ────────────────────────
//
// 개선하고 싶은 점이 보여도 여기서 조용히 고치지 않는다. 앱과 결과가 달라지는
// 순간 이 파일의 존재 이유가 사라지기 때문이다. 차이를 발견하면
// docs/party-registration-parity.md에 적고, 앱·서버를 함께 고치는 별도 작업으로
// 처리한다.
//
// 대응하는 Dart 코드(모두 lib/ 기준):
//   models/party_registration_data.dart  → buildSharedFields
//   models/party_pricing.dart            → pricingFields
//   models/party_early_bird.dart         → earlyBirdFields
//   models/party_schedule.dart           → buildSingleFields/buildRecurringFields
//   models/party_round.dart              → roundFields
//   models/party_round_package.dart      → roundPackageFields
//   screens/party_register_screen.dart   → buildPartyDocuments (슬롯 팬아웃)
//
// ── 시간대 ──────────────────────────────────────────────────────────────
//
// 입력의 날짜·시각은 전부 **KST 벽시계 문자열**이다('2026-09-05', '20:00').
// 앱은 기기 로컬 시간(한국 사용자 = KST)으로 DateTime을 만들고, Functions는
// UTC로 돌기 때문에, 여기서는 partySchedule.js와 같은 고정 오프셋(+9) 방식으로
// KST 달력을 다룬다. 한국은 서머타임이 없어 고정 오프셋으로 정확하다.
//
// 반환하는 시각 값은 **네이티브 Date**다. Firestore Admin SDK가 Date를 그대로
// Timestamp로 저장하므로 변환이 필요 없고, 이 파일이 firebase-admin에 의존하지
// 않아 `node partyRegistration.selfcheck.js`로 그냥 돌릴 수 있다.

const {
  toDate,
  kstMidnightOf,
  parseRecurringSchedule,
  nextOccurrence,
  parseDeadlineRule,
  resolveDeadline,
  resolveEarlyBirdEnd,
} = require('./partySchedule');

const {
  normalizeAgeInput,
  normalizedFor: normalizedAgeFor,
  ageFields,
} = require('./partyAgeRestriction');

const KST_OFFSET_MS = 9 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

/// 정기 파티의 요일 키 — Firestore weeklySchedule 맵의 키.
/// 순서는 Dart의 kPartyWeekdayKeys와 **같아야 한다**(월 시작). 저장되는 맵의
/// 키 순서까지 앱과 맞추기 위해서다.
const WEEKDAY_KEYS_MON_FIRST = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];

/// 파티 전체 최소 모집 인원의 정본 필드(partyMinCapacity.js와 같은 이름).
const PARTY_MIN_CAPACITY_FIELD = 'partyMinCapacity';

/// 게스트에게 **현재 참가자의 남/여 인원**을 보여줄지
/// (Dart ParticipantGenderVisibility.field와 같은 이름·같은 뜻).
///
/// 감추는 것은 "지금 참가한 사람들의 성별 내역"뿐이다 — 총 참가 인원과 호스트가
/// 정해 둔 모집 정원(남자 10명 등)은 그대로 보인다. 호스트 본인은 설정과
/// 무관하게 언제나 본다(그 판정은 읽는 쪽에 있다).
const PARTICIPANT_GENDER_VISIBILITY_FIELD = 'revealParticipantGenderRatio';

/// 위 설정의 기본값 — **공개**(Dart ParticipantGenderVisibility.defaultValue).
///
/// 이 설정이 생기기 전 파티는 성비를 보여줬으므로 읽는 쪽이 "필드 없음 = 공개"
/// 로 읽는다. 새로 만드는 문서의 기본값도 같아야, 설정이 생겼다는 이유만으로
/// 이미 열려 있던 파티와 새 파티의 화면이 갈리지 않는다.
const PARTICIPANT_GENDER_VISIBILITY_DEFAULT = true;

/// 게스트 문의 받기 — 파티·플레이스·장소대여 공통 필드(ListingInquiry.field).
const INQUIRY_FIELD = 'inquiryEnabled';

/// 문의 전 안내문 — 위 필드와 짝이다(ListingInquiry.guideField).
/// 문의를 끄면 빈 문자열로 지운다(앱의 ListingInquiry.toMap과 같은 규칙).
const INQUIRY_GUIDE_FIELD = 'inquiryGuide';
const INQUIRY_GUIDE_MAX = 300;

/// 파티츄 전용 혜택 필드(kPartychuPerkField).
const PARTYCHU_PERK_FIELD = 'partychuPerk';

/// 파티 유형의 화면 표시용 라벨 — Dart PartyConstants.partyTypeLabels의 사본.
///
/// 문서의  필드에는 **라벨**이 저장된다(검색값 원문이 아니다).
/// 앱이 그렇게 저장해 왔고, 목록·필터가 그 값을 그대로 읽는다. 두 곳의 표를
/// 함께 고치지 않으면 웹으로 등록한 파티만 카테고리 표기가 달라진다.
const PARTY_TYPE_LABELS = {
  '하우스파티': '🏠 하우스',
  '게스트하우스 파티': '🏡 게스트하우스',
  '풀파티': '🎉 풀파티',
  '루프탑 파티': '🌇 루프탑',
  '클럽 파티': '🎧 클럽',
  'EDM 파티': '🎵 EDM',
  'DJ 파티': '🎤 DJ',
  '라이브 파티': '🎤 라이브',
  '공연 파티': '🎭 공연',
  '포차 파티': '🍻 포차',
  '와인 파티': '🍷 와인',
  '칵테일 파티': '🍸 칵테일',
  '맥주 파티': '🍺 맥주',
  'BBQ 파티': '🥩 BBQ',
  '캠핑 파티': '🏕️ 캠핑',
  '글램핑 파티': '⛺ 글램핑',
  '요트 파티': '🛥️ 요트',
  '선상 파티': '🚢 선상',
  '페스티벌': '🎪 페스티벌',
  '맥주축제': '🍺 맥주축제',
  '뮤직 페스티벌': '🎶 뮤직 페스티벌',
  '라운지 파티': '🥂 라운지',
  '프라이빗 파티': '🔒 프라이빗',
  '애프터파티': '✨ 애프터',
  '시즌 파티': '🌸 시즌',
  '코스프레 파티': '🎭 코스프레',
  '할로윈 파티': '🎃 할로윈',
  '크리스마스 파티': '🎄 크리스마스',
  '신년 파티': '🎆 신년',
  '외국인 파티': '🌐 외국인',
  '펍 파티': '🍻 펍',
  '소개팅 파티': '💑 소개팅',
};


/// 파티 유형의 **검색값(원문)** — Dart PartyConstants.partyTypes의 사본.
/// 순서까지 같게 둔다(웹 폼이 이 순서로 칩을 그린다).
const PARTY_TYPES = [
  '하우스파티',
  '게스트하우스 파티',
  '풀파티',
  '루프탑 파티',
  '클럽 파티',
  'EDM 파티',
  'DJ 파티',
  '라이브 파티',
  '공연 파티',
  '포차 파티',
  '와인 파티',
  '칵테일 파티',
  '맥주 파티',
  'BBQ 파티',
  '캠핑 파티',
  '글램핑 파티',
  '요트 파티',
  '선상 파티',
  '페스티벌',
  '맥주축제',
  '뮤직 페스티벌',
  '라운지 파티',
  '프라이빗 파티',
  '애프터파티',
  '시즌 파티',
  '코스프레 파티',
  '할로윈 파티',
  '크리스마스 파티',
  '신년 파티',
  '외국인 파티',
  '펍 파티',
  '소개팅 파티',
];

/// 분위기 — Dart PartyConstants.vibes의 사본.
const PARTY_VIBES = [
  '🔥 신나는',
  '🍺 술 중심',
  '🙅 논알콜',
  '🎵 음악 중심',
  '💃 춤',
  '🌍 글로벌',
  '🎉 대규모',
  '🏠 소규모',
  '✨ 프리미엄',
  '🌅 야외',
  '🏡 실내',
];

/// 고를 수 있는 최대 개수 — Dart PartyConstants의 max* 상수와 같다.
const MAX_PARTY_TYPES = 5;
const MAX_VIBES = 3;
const MAX_TAGS = 6;

/// 검색값(원문) → 표시용 라벨. 매핑이 없는 값은 원문 그대로(Dart labelFor).
function partyTypeLabelOf(type) {
  return PARTY_TYPE_LABELS[type] || type;
}

// ═══════════════════════════════════════════════════════════════════════════
// KST 벽시계 헬퍼
// ═══════════════════════════════════════════════════════════════════════════

/// 'YYYY-MM-DD' → {y, m, d}. 형식이 아니면 null.
function parseIsoDate(value) {
  if (value instanceof Date) {
    const shifted = new Date(value.getTime() + KST_OFFSET_MS);
    return {
      y: shifted.getUTCFullYear(),
      m: shifted.getUTCMonth() + 1,
      d: shifted.getUTCDate(),
    };
  }
  if (typeof value !== 'string') return null;
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value.trim());
  if (!m) return null;
  const y = Number(m[1]);
  const mo = Number(m[2]);
  const d = Number(m[3]);
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  return { y, m: mo, d };
}

/// 'HH:mm' → {h, m}. 형식이 아니면 null.
function parseHm(value) {
  if (typeof value !== 'string') return null;
  const m = /^(\d{1,2}):(\d{2})$/.exec(value.trim());
  if (!m) return null;
  const h = Number(m[1]);
  const min = Number(m[2]);
  if (h < 0 || h > 23 || min < 0 || min > 59) return null;
  return { h, m: min };
}

/// KST 벽시계(연·월·일·시·분) → 절대 시각. 월/일이 넘쳐도 Date.UTC가 알아서
/// 넘겨준다(Dart의 DateTime(y, m, d - 1, ...)과 같은 동작).
function kstAt(y, m, d, hh = 0, mm = 0) {
  return new Date(Date.UTC(y, m - 1, d, hh, mm) - KST_OFFSET_MS);
}

/// 'HH:mm' 정규화 — 저장되는 문자열은 언제나 두 자리다(formatScheduleTime).
function formatHm(hm) {
  if (!hm) return null;
  return `${String(hm.h).padStart(2, '0')}:${String(hm.m).padStart(2, '0')}`;
}

/// '2026.09.05' — 문서의 legacy `date` 문자열 앞부분(formatPartyDate).
function formatPartyDate(iso) {
  const p = parseIsoDate(iso);
  if (!p) return '날짜 선택';
  return `${p.y}.${String(p.m).padStart(2, '0')}.${String(p.d).padStart(2, '0')}`;
}

/// '오후 08:00' — 문서의 legacy `date` 문자열 뒷부분(formatPartyTime).
/// **시(hour)를 두 자리로 채운다** — 사람이 읽는 다른 표기(formatKoreanTimeOfDay)와
/// 달리 이 값은 문서에 그대로 남으므로 앱과 한 글자도 달라선 안 된다.
function formatPartyTime(hm) {
  if (!hm) return '시간 선택';
  const period = hm.h < 12 ? '오전' : '오후';
  const h12 = hm.h % 12 === 0 ? 12 : hm.h % 12;
  return `${period} ${String(h12).padStart(2, '0')}:${String(hm.m).padStart(2, '0')}`;
}

function intOf(value, fallback = 0) {
  const n = Number(value);
  return Number.isFinite(n) ? Math.trunc(n) : fallback;
}

function trimmed(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function stringList(raw, { limit = null } = {}) {
  if (!Array.isArray(raw)) return [];
  const out = [];
  for (const v of raw) {
    const s = trimmed(v);
    if (!s || out.includes(s)) continue;
    out.push(s);
    if (limit != null && out.length >= limit) break;
  }
  return out;
}

// ═══════════════════════════════════════════════════════════════════════════
// 모집 시작/마감 규칙 (PartyRecruitDeadlineRule)
// ═══════════════════════════════════════════════════════════════════════════

/// 입력의 규칙 맵을 정규화한다. Dart PartyRecruitDeadlineRule의 기본값과 같다.
///  mode: 'beforeStart' | 'startDayTime' | 'prevDayTime' | 'customDateTime' | 'none'
function normalizeRecruitRule(raw, { defaultMode = 'beforeStart' } = {}) {
  const src = raw && typeof raw === 'object' ? raw : {};
  let mode = trimmed(src.mode) || defaultMode;
  // 예전 키 — partySchedule.js의 parseDeadlineRule과 같은 승격 규칙.
  if (mode === 'hoursBefore') mode = 'beforeStart';
  if (mode === 'sameDayTime') mode = 'startDayTime';
  const known = [
    'beforeStart',
    'startDayTime',
    'prevDayTime',
    'customDateTime',
    'none',
  ];
  if (!known.includes(mode)) mode = defaultMode;

  const rawMinutes = Number(src.minutes);
  const rawHours = Number(src.hours);
  let minutes = Number.isFinite(rawMinutes)
    ? Math.trunc(rawMinutes)
    : Number.isFinite(rawHours)
      ? Math.trunc(rawHours) * 60
      : 60;
  if (minutes < 0) minutes = 0;

  const at = toDate(src.atMs != null ? src.atMs : src.at);
  return {
    mode,
    minutes,
    // Dart 기본값은 18:00.
    time: parseHm(src.time) || { h: 18, m: 0 },
    atMs: at ? at.getTime() : null,
  };
}

/// 문서에 저장되는 모양 — Dart PartyRecruitDeadlineRule.toMap().
function recruitRuleFields(rule) {
  if (!rule) return null;
  const out = { mode: rule.mode };
  if (rule.mode === 'beforeStart') {
    out.minutes = rule.minutes;
    // 시간 단위만 읽던 예전 앱/서버를 위한 값(내림).
    out.hours = Math.trunc(rule.minutes / 60);
  }
  if (rule.mode === 'startDayTime' || rule.mode === 'prevDayTime') {
    out.time = formatHm(rule.time);
  }
  if (rule.mode === 'customDateTime' && rule.atMs != null) {
    out.atMs = rule.atMs;
  }
  return out;
}

/// 시작 시각에 규칙을 적용한 실제 시각. partySchedule.js의 resolveDeadline을
/// 그대로 쓴다 — 마감 판정을 두 번 구현하지 않기 위해서다.
function resolveRuleAt(rule, start, end) {
  if (!rule) return null;
  return resolveDeadline(
    {
      mode: rule.mode,
      minutes: rule.minutes,
      timeMin: rule.time ? rule.time.h * 60 + rule.time.m : null,
      atMs: rule.atMs,
    },
    kstMidnightOf(start),
    start,
    end || null
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// 참가비 (PartyPricing)
// ═══════════════════════════════════════════════════════════════════════════

/// 남/여 금액을 Dart PartyPricing.gendered와 **같은 규칙**으로 정규화한다.
///  · 음수는 0으로 자른다
///  · 둘 다 0 이하 → 무료
///  · 두 값이 같다 → same(동일 금액). same도 0 이하면 무료
function normalizePricing(raw) {
  const src = raw && typeof raw === 'object' ? raw : {};
  // 입력이 type을 명시하면 그 뜻대로 남/여 금액을 뽑고, 아니면 male/female을
  // 그대로 읽는다. 어느 쪽이든 아래 정규화를 똑같이 거치므로 결과는 같다.
  let male;
  let female;
  if (trimmed(src.type) === 'free') {
    male = 0;
    female = 0;
  } else if (trimmed(src.type) === 'same') {
    male = intOf(src.price, 0);
    female = male;
  } else {
    male = intOf(src.malePrice != null ? src.malePrice : src.male, 0);
    female = intOf(src.femalePrice != null ? src.femalePrice : src.female, 0);
  }
  if (male < 0) male = 0;
  if (female < 0) female = 0;

  if (male <= 0 && female <= 0) {
    return { type: 'free', price: 0, malePrice: 0, femalePrice: 0 };
  }
  if (male === female) {
    return { type: 'same', price: male, malePrice: null, femalePrice: null };
  }
  return { type: 'gendered', price: null, malePrice: male, femalePrice: female };
}

function isFreePricing(pricing) {
  return pricing.type === 'free';
}

/// 성별을 모를 때 대표로 보여줄 금액 — gendered면 **0보다 큰 값 중 더 낮은 쪽**.
function displayPriceOf(pricing) {
  if (pricing.type === 'free') return 0;
  if (pricing.type === 'same') return pricing.price || 0;
  const values = [pricing.malePrice, pricing.femalePrice].filter(
    (v) => typeof v === 'number' && v > 0
  );
  if (values.length === 0) return 0;
  return Math.min(...values);
}

function priceForGender(pricing, gender) {
  if (pricing.type === 'free') return 0;
  if (pricing.type === 'same') return pricing.price || 0;
  if (gender === 'male') {
    return pricing.malePrice != null ? pricing.malePrice : displayPriceOf(pricing);
  }
  if (gender === 'female') {
    return pricing.femalePrice != null
      ? pricing.femalePrice
      : displayPriceOf(pricing);
  }
  return displayPriceOf(pricing);
}

/// 문서에 저장되는 모양 — Dart PartyPricing.toMap().
/// maleFee/femaleFee는 레거시 이중 기록이다(읽는 자리가 아직 여럿이다).
function pricingFields(pricing) {
  const gendered = pricing.type === 'gendered';
  const free = pricing.type === 'free';
  return {
    pricingType: pricing.type,
    price: gendered ? null : displayPriceOf(pricing),
    malePrice: gendered ? pricing.malePrice : free ? 0 : null,
    femalePrice: gendered ? pricing.femalePrice : free ? 0 : null,
    maleFee: priceForGender(pricing, 'male'),
    femaleFee: priceForGender(pricing, 'female'),
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// 얼리버드 (PartyEarlyBird)
// ═══════════════════════════════════════════════════════════════════════════

/// 얼리버드 종료 규칙 — Dart PartyEarlyBirdDeadlineRule.
function normalizeEarlyBirdRule(raw) {
  const src = raw && typeof raw === 'object' ? raw : {};
  let mode = trimmed(src.mode) || 'daysBefore';
  if (!['daysBefore', 'hoursBefore', 'sameDayTime', 'absolute'].includes(mode)) {
    mode = 'daysBefore';
  }
  const days = Math.max(0, intOf(src.days, 3));
  const hours = Math.max(0, intOf(src.hours, 24));
  return {
    mode,
    days,
    hours,
    time: parseHm(src.time) || { h: 23, m: 59 },
  };
}

/// Dart PartyEarlyBirdDeadlineRule.toMap() — 쓰지 않는 칸은 아예 만들지 않는다.
function earlyBirdRuleFields(rule) {
  const out = { mode: rule.mode };
  if (rule.mode === 'daysBefore') out.days = rule.days;
  if (rule.mode === 'hoursBefore') out.hours = rule.hours;
  // usesTime — daysBefore / sameDayTime만 시각을 함께 고른다.
  if (rule.mode === 'daysBefore' || rule.mode === 'sameDayTime') {
    out.time = formatHm(rule.time);
  }
  return out;
}

/// 입력의 얼리버드를 정규화한다.
///   endType: 'fixedDate'(고정 종료 시각) | 'beforeStart'(시작 기준 상대 규칙)
///   endAt  : fixedDate에서만 쓰는 KST 벽시계 { date: 'YYYY-MM-DD', time: 'HH:mm' }
function normalizeEarlyBird(raw) {
  const src = raw && typeof raw === 'object' ? raw : {};
  const endType = trimmed(src.endType) === 'beforeStart' ? 'beforeStart' : 'fixedDate';

  let endAt = null;
  const rawEnd = src.endAt;
  if (rawEnd && typeof rawEnd === 'object' && !(rawEnd instanceof Date)) {
    const d = parseIsoDate(rawEnd.date);
    const t = parseHm(rawEnd.time);
    if (d && t) endAt = kstAt(d.y, d.m, d.d, t.h, t.m);
  } else {
    endAt = toDate(rawEnd);
  }

  const percentRaw = src.percent;
  return {
    enabled: src.enabled === true,
    percent: percentRaw == null ? null : intOf(percentRaw, 0),
    endType,
    endAt,
    beforeStartRule: normalizeEarlyBirdRule(src.beforeStartRule),
  };
}

const EARLY_BIRD_OFF = Object.freeze({
  enabled: false,
  percent: null,
  endType: 'fixedDate',
  endAt: null,
  beforeStartRule: Object.freeze({
    mode: 'daysBefore',
    days: 3,
    hours: 24,
    time: Object.freeze({ h: 23, m: 59 }),
  }),
});

/// 문서에 저장되는 모양 — Dart PartyEarlyBird.toMapFor(isRecurring:).
///
/// 종료 기준에 따라 **한쪽 방식만** 기록한다. 두 방식이 한 문서에 섞이면 어느
/// 쪽이 진짜인지 알 수 없어지므로 반대쪽은 명시적으로 null이다.
function earlyBirdFields(earlyBird, { isRecurring }) {
  // 정기 파티는 회차마다 날짜가 달라 고정 종료 시각을 쓸 수 없다.
  const type = isRecurring ? 'beforeStart' : earlyBird.endType;
  const useRule = type === 'beforeStart';
  const on = earlyBird.enabled && (useRule || earlyBird.endAt != null);
  return {
    earlyBirdEnabled: on,
    earlyBirdDiscountPercent: on ? earlyBird.percent : null,
    earlyBirdEndType: on ? type : null,
    earlyBirdEndAt: on && !useRule ? earlyBird.endAt : null,
    earlyBirdDeadlineRule:
      on && useRule ? earlyBirdRuleFields(earlyBird.beforeStartRule) : null,
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// 차수 (PartyRound)
// ═══════════════════════════════════════════════════════════════════════════

function normalizeRound(raw, index) {
  const src = raw && typeof raw === 'object' ? raw : {};
  const id = trimmed(src.id) || `round_${index + 2}`;
  return {
    id,
    label: trimmed(src.label),
    startTime: parseHm(src.startTime) || { h: 21, m: 0 },
    endTime: parseHm(src.endTime),
    // 차수 기본값 — Dart PartyRound의 기본 생성자와 같다(모집 시작은 제한 없음,
    // 마감은 시작 60분 전).
    openRule: normalizeRecruitRule(src.openRule, { defaultMode: 'none' }),
    closeRule: normalizeRecruitRule(src.closeRule, { defaultMode: 'beforeStart' }),
    minCapacity: Math.max(0, intOf(src.minCapacity, 0)),
    maxCapacity: Math.max(0, intOf(src.maxCapacity, 0)),
    maleCapacity: Math.max(0, intOf(src.maleCapacity, 0)),
    femaleCapacity: Math.max(0, intOf(src.femaleCapacity, 0)),
    maleFee: Math.max(0, intOf(src.maleFee, 0)),
    femaleFee: Math.max(0, intOf(src.femaleFee, 0)),
    earlyBird: normalizeEarlyBird(src.earlyBird),
  };
}

/// 남녀 정원을 따로 받는 모드에서는 합계가 곧 최대 인원이다(Dart separateTotal).
function roundSeparateTotal(round) {
  return round.maleCapacity > 0 || round.femaleCapacity > 0
    ? round.maleCapacity + round.femaleCapacity
    : round.maxCapacity;
}

/// 그 날짜에 이 차수를 적용한 실제 일정 — Dart PartyRound.resolveOn().
function resolveRoundOn(round, isoDate) {
  const p = parseIsoDate(isoDate);
  if (!p) return null;
  const start = kstAt(p.y, p.m, p.d, round.startTime.h, round.startTime.m);
  // 종료 시각이 없으면 2시간짜리로 본다.
  let end = round.endTime
    ? kstAt(p.y, p.m, p.d, round.endTime.h, round.endTime.m)
    : new Date(start.getTime() + 2 * 60 * 60 * 1000);
  // 자정을 넘기는 시간대(21:00~01:00)는 종료를 다음 날로 넘긴다.
  if (end.getTime() <= start.getTime()) end = new Date(end.getTime() + DAY_MS);

  return {
    start,
    end,
    recruitOpenAt: resolveRuleAt(round.openRule, start, end),
    recruitCloseAt: resolveRuleAt(round.closeRule, start, end),
  };
}

/// rounds 배열의 원소 하나 — Dart PartyRound.toMap().
function roundFields(round, { roundNumber, isoDate, perRound }) {
  const w = resolveRoundOn(round, isoDate);
  const out = {
    id: round.id,
    roundNumber,
    label: round.label || `${roundNumber}차`,
    // 'time'은 예전 이름 그대로 — 이 값을 읽는 화면/서버가 이미 여럿이다.
    time: w.start,
    endAt: w.end,
    startTime: formatHm(round.startTime),
    endTime: round.endTime ? formatHm(round.endTime) : null,
    recruitOpenAt: w.recruitOpenAt,
    recruitCloseAt: w.recruitCloseAt,
    recruitOpenRule: recruitRuleFields(round.openRule),
    recruitCloseRule: recruitRuleFields(round.closeRule),
  };
  if (perRound) {
    Object.assign(out, {
      minCapacity: round.minCapacity,
      maxCapacity: roundSeparateTotal(round),
      maleCapacity: round.maleCapacity,
      femaleCapacity: round.femaleCapacity,
      currentParticipants: 0,
      currentMaleCount: 0,
      currentFemaleCount: 0,
      maleFee: round.maleFee,
      femaleFee: round.femaleFee,
      // 차수는 날짜가 저마다 달라 늘 "시작 전" 규칙을 쓴다.
      ...earlyBirdFields(round.earlyBird, { isRecurring: true }),
    });
  }
  return out;
}

// ═══════════════════════════════════════════════════════════════════════════
// 차수 패키지 (PartyRoundPackage)
// ═══════════════════════════════════════════════════════════════════════════

function normalizeRoundPackage(raw, index) {
  const src = raw && typeof raw === 'object' ? raw : {};
  const numbers = Array.isArray(src.roundNumbers)
    ? Array.from(
        new Set(
          src.roundNumbers
            .map((n) => intOf(n, 0))
            .filter((n) => n > 0)
        )
      ).sort((a, b) => a - b)
    : [];
  return {
    id: trimmed(src.id) || `pkg_${index + 1}`,
    name: trimmed(src.name),
    roundNumbers: numbers,
    roundIds: stringList(src.roundIds),
    maleFee: Math.max(0, intOf(src.maleFee, 0)),
    femaleFee: Math.max(0, intOf(src.femaleFee, 0)),
    earlyBirdEnabled: src.earlyBirdEnabled === true,
    earlyBirdMaleFee: Math.max(0, intOf(src.earlyBirdMaleFee, 0)),
    earlyBirdFemaleFee: Math.max(0, intOf(src.earlyBirdFemaleFee, 0)),
    earlyBirdRule: normalizeEarlyBirdRule(src.earlyBirdDeadlineRule || src.earlyBirdRule),
  };
}

/// Dart PartyRoundPackage.displayName — 이름을 비우면 '1+2차'처럼 자동 생성.
function packageDisplayName(pkg) {
  if (pkg.name) return pkg.name;
  if (pkg.roundNumbers.length === 0) return '패키지';
  return `${pkg.roundNumbers.join('+')}차 패키지`;
}

/// roundPackages 배열의 원소 하나 — Dart PartyRoundPackage.toMap().
/// 얼리버드 종료 시각만 그 슬롯의 "첫 포함 차수 시작 시각"으로 계산된다.
function roundPackageFields(pkg, { firstRoundStart }) {
  const endAt =
    pkg.earlyBirdEnabled && firstRoundStart
      ? resolveEarlyBirdEnd(earlyBirdRuleFields(pkg.earlyBirdRule), firstRoundStart)
      : null;
  return {
    id: pkg.id,
    name: packageDisplayName(pkg),
    roundNumbers: pkg.roundNumbers,
    roundIds: pkg.roundIds,
    maleFee: pkg.maleFee,
    femaleFee: pkg.femaleFee,
    earlyBirdEnabled: pkg.earlyBirdEnabled,
    earlyBirdMaleFee: pkg.earlyBirdEnabled ? pkg.earlyBirdMaleFee : 0,
    earlyBirdFemaleFee: pkg.earlyBirdEnabled ? pkg.earlyBirdFemaleFee : 0,
    earlyBirdDeadlineRule: pkg.earlyBirdEnabled
      ? earlyBirdRuleFields(pkg.earlyBirdRule)
      : null,
    earlyBirdEndAt: endAt,
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// 일정 (PartySchedule)
// ═══════════════════════════════════════════════════════════════════════════

/// 일회성 슬롯 하나의 절대 시각. 종료가 시작보다 이르면 다음 날로 넘긴다.
function resolveSlotWindow(slot) {
  const p = parseIsoDate(slot.date);
  if (!p) return null;
  const start = kstAt(p.y, p.m, p.d, slot.startTime.h, slot.startTime.m);
  let end = null;
  if (slot.endTime) {
    end = kstAt(p.y, p.m, p.d, slot.endTime.h, slot.endTime.m);
    if (end.getTime() <= start.getTime()) end = new Date(end.getTime() + DAY_MS);
  }
  return { start, end, midnight: kstAt(p.y, p.m, p.d) };
}

/// Dart PartySingleSchedule.toMap().
function singleScheduleFields(slot, { deadlineAt, openAt }) {
  const w = resolveSlotWindow(slot);
  return {
    date: w.midnight,
    startTime: formatHm(slot.startTime),
    endTime: slot.endTime ? formatHm(slot.endTime) : null,
    registrationDeadline: deadlineAt || null,
    registrationOpen: openAt || null,
  };
}

/// Dart PartySchedule.buildSingleFields().
function buildSingleFields(slot, { deadlineRule, openRule, deadlineAt, openAt }) {
  return {
    scheduleType: 'single',
    singleSchedule: singleScheduleFields(slot, { deadlineAt, openAt }),
    recurringSchedule: null,
    recruitDeadlineRule: deadlineRule ? recruitRuleFields(deadlineRule) : null,
    recruitOpenRule: openRule ? recruitRuleFields(openRule) : null,
    recruitOpenAt: openAt || null,
  };
}

/// Dart PartyRecurringSchedule.toMap() — **켜진 요일만** 맵에 담는다.
function recurringScheduleFields(recurring) {
  const weekly = {};
  for (const key of WEEKDAY_KEYS_MON_FIRST) {
    const slot = recurring.weekly[key];
    if (!slot || !slot.enabled) continue;
    weekly[key] = {
      enabled: true,
      startTime: formatHm(slot.startTime),
      endTime: formatHm(slot.endTime),
    };
  }
  return {
    startDate: recurring.startDate,
    endDate: recurring.endDate,
    weeklySchedule: weekly,
    registrationOpen: recruitRuleFields(recurring.openRule),
    registrationDeadline: recruitRuleFields(recurring.deadlineRule),
  };
}

/// Dart PartySchedule.buildRecurringFields().
///
/// 정기 파티에는 recruitDeadlineAt을 저장하지 않는다 — 회차마다 마감이 새로
/// 열리는데 고정 Timestamp를 남기면 applyToParty가 첫 회차 마감 이후 모든
/// 신청을 영구히 막아버린다.
function buildRecurringFields(recurring, { firstOccurrence }) {
  const out = {
    scheduleType: 'recurring',
    recurringSchedule: recurringScheduleFields(recurring),
    singleSchedule: null,
    recruitDeadlineAt: null,
    recruitOpenAt:
      firstOccurrence && firstOccurrence.recruitOpenAt
        ? firstOccurrence.recruitOpenAt
        : null,
    // 일회성이던 문서를 정기로 고쳤을 때 옛 규칙이 남지 않도록 함께 지운다.
    recruitDeadlineRule: null,
    recruitOpenRule: null,
  };
  if (firstOccurrence) out.partyDateTime = firstOccurrence.start;
  return out;
}

/// 정기 일정 입력을 정규화한다. 요일 칸은 7개를 모두 들고 있되 enabled로 가른다.
function normalizeRecurring(raw) {
  const src = raw && typeof raw === 'object' ? raw : {};
  const startP = parseIsoDate(src.startDate);
  const endP = parseIsoDate(src.endDate);
  const weeklyRaw = src.weekly && typeof src.weekly === 'object' ? src.weekly : {};

  const weekly = {};
  for (const key of WEEKDAY_KEYS_MON_FIRST) {
    const slotRaw = weeklyRaw[key];
    if (!slotRaw || typeof slotRaw !== 'object') {
      weekly[key] = { enabled: false, startTime: { h: 19, m: 0 }, endTime: { h: 22, m: 0 } };
      continue;
    }
    const start = parseHm(slotRaw.startTime);
    const end = parseHm(slotRaw.endTime);
    weekly[key] = {
      // 시각이 덜 채워진 칸은 켜진 것으로 볼 수 없다.
      enabled: slotRaw.enabled === true && !!start && !!end,
      startTime: start || { h: 19, m: 0 },
      endTime: end || { h: 22, m: 0 },
    };
  }

  return {
    startDate: startP ? kstAt(startP.y, startP.m, startP.d) : null,
    endDate: endP ? kstAt(endP.y, endP.m, endP.d) : null,
    weekly,
    openRule: normalizeRecruitRule(src.openRule, { defaultMode: 'none' }),
    deadlineRule: normalizeRecruitRule(src.deadlineRule, { defaultMode: 'beforeStart' }),
  };
}

/// 정규화된 정기 일정의 "지금 기준 다음 회차". partySchedule.js의 계산을 그대로
/// 쓴다 — 저장될 문서를 만들어 넘겨서 판정을 한 벌만 유지한다.
function firstOccurrenceOf(recurring, now) {
  const parsed = parseRecurringSchedule(recurringScheduleFields(recurring));
  if (!parsed) return null;
  return nextOccurrence(parsed, now);
}

// ═══════════════════════════════════════════════════════════════════════════
// 입력 정규화
// ═══════════════════════════════════════════════════════════════════════════

/// 날짜 슬롯 목록 — 같은 날짜라도 시간대가 다르면 별개의 일정이다.
function normalizeSlots(raw) {
  if (!Array.isArray(raw)) return [];
  const out = [];
  for (const item of raw) {
    if (!item || typeof item !== 'object') continue;
    const date = parseIsoDate(item.date);
    const startTime = parseHm(item.startTime);
    if (!date || !startTime) continue;
    out.push({
      date: `${date.y}-${String(date.m).padStart(2, '0')}-${String(date.d).padStart(2, '0')}`,
      startTime,
      endTime: parseHm(item.endTime),
    });
  }
  return out;
}

/// 정원 — Dart _resolveCapacities()와 같은 규칙.
///  · unlimited(통합 정원) → 남/여 0, 최대는 입력값 그대로
///  · separate(남녀별 정원) → 성별 제한에 걸린 쪽은 0, 최대는 남+여 합계
///
/// 참가자 성비 공개 설정도 여기서 함께 받는다 — 정원·성별과 같은 층의 값이라
/// 입력에서도 같은 자리에 둔다.
function normalizeCapacity(raw) {
  const src = raw && typeof raw === 'object' ? raw : {};
  const genderLimit = ['all', 'male', 'female'].includes(trimmed(src.genderLimit))
    ? trimmed(src.genderLimit)
    : 'all';
  const genderCapacityMode =
    trimmed(src.genderCapacityMode) === 'separate' ? 'separate' : 'unlimited';
  const minCapacity = Math.max(0, intOf(src.minCapacity, 0));
  const minCapacityPolicy =
    trimmed(src.minCapacityPolicy) === 'autoCancel' ? 'autoCancel' : 'proceed';
  const genderMode = trimmed(src.genderMode) === 'balanced' ? 'balanced' : '';
  // 명시적으로 false일 때만 감춘다 — 안 보낸 입력(옛 웹 폼 포함)은 공개다
  // (inquiryEnabled와 같은 "기본값 ON" 규칙).
  const revealParticipantGenderRatio =
    src[PARTICIPANT_GENDER_VISIBILITY_FIELD] !== false;

  if (genderCapacityMode === 'unlimited') {
    return {
      genderLimit,
      genderCapacityMode,
      genderMode,
      maleCapacity: 0,
      femaleCapacity: 0,
      maxCapacity: Math.max(0, intOf(src.maxCapacity, 0)),
      minCapacity,
      minCapacityPolicy,
      revealParticipantGenderRatio,
    };
  }
  const male =
    genderLimit === 'all' || genderLimit === 'male'
      ? Math.max(0, intOf(src.maleCapacity, 0))
      : 0;
  const female =
    genderLimit === 'all' || genderLimit === 'female'
      ? Math.max(0, intOf(src.femaleCapacity, 0))
      : 0;
  return {
    genderLimit,
    genderCapacityMode,
    genderMode,
    maleCapacity: male,
    femaleCapacity: female,
    maxCapacity: male + female,
    minCapacity,
    minCapacityPolicy,
    revealParticipantGenderRatio,
  };
}

/// 결제 방식 — Dart PaymentPolicy.toMap()과 같은 모양. 설정이 없으면 null이고,
/// 그때는 필드를 아예 만들지 않아 서버가 기존 동작(수단 자유 선택)을 태운다.
function normalizePaymentPolicy(raw) {
  const src = raw && typeof raw === 'object' ? raw : null;
  if (!src) return null;
  const mode = trimmed(src.paymentMode || src.mode);
  if (!['prepaid', 'partial', 'onsite'].includes(mode)) return null;
  if (mode !== 'partial') return { paymentMode: mode };
  const upfrontType = trimmed(src.upfrontType);
  const out = { paymentMode: mode, upfrontType: upfrontType || null };
  if (upfrontType === 'percentage') out.upfrontPercent = intOf(src.upfrontPercent, 0);
  if (upfrontType === 'fixed') out.upfrontFixedAmount = intOf(src.upfrontFixedAmount, 0);
  return out;
}

function normalizeRefundTiers(raw) {
  if (!Array.isArray(raw)) return [];
  return raw
    .filter((t) => t && typeof t === 'object')
    .map((t) => ({
      daysBefore: intOf(t.daysBefore, 0),
      refundPercent: intOf(t.refundPercent, 0),
    }));
}

/// 등록 입력 전체를 정규화한다. **여기를 통과한 값만** 아래 조립 함수들이 본다.
function normalizeInput(raw) {
  const src = raw && typeof raw === 'object' ? raw : {};
  const scheduleSrc = src.schedule && typeof src.schedule === 'object' ? src.schedule : {};
  const isRecurring = trimmed(scheduleSrc.type) === 'recurring';
  const roundsSrc = src.rounds && typeof src.rounds === 'object' ? src.rounds : {};
  const placeSrc = src.place && typeof src.place === 'object' ? src.place : {};
  const ageSrc = src.age && typeof src.age === 'object' ? src.age : {};
  const taxonomySrc = src.taxonomy && typeof src.taxonomy === 'object' ? src.taxonomy : {};
  const mediaSrc = src.media && typeof src.media === 'object' ? src.media : {};

  const hasMultipleRounds = roundsSrc.enabled === true;
  const roundCapacityMode =
    trimmed(roundsSrc.capacityMode) === 'perRound' ? 'perRound' : 'unified';
  const roundEarlyBirdMode = ['none', 'uniform', 'perRound'].includes(
    trimmed(roundsSrc.earlyBirdMode)
  )
    ? trimmed(roundsSrc.earlyBirdMode)
    : 'none';

  return {
    title: trimmed(src.title),
    description: trimmed(src.description),
    partychuPerk: trimmed(src.partychuPerk),
    inquiryEnabled: src.inquiryEnabled !== false, // 기본값 ON(ListingInquiry)
    inquiryGuide: trimmed(src.inquiryGuide).slice(0, INQUIRY_GUIDE_MAX),
    dateTbd: src.dateTbd === true,

    place: {
      placeName: trimmed(placeSrc.placeName),
      location: trimmed(placeSrc.location || placeSrc.displayAddress),
      address: trimmed(placeSrc.address),
      roadAddress: trimmed(placeSrc.roadAddress),
      jibunAddress: trimmed(placeSrc.jibunAddress),
      detailAddress: trimmed(placeSrc.detailAddress),
      region: trimmed(placeSrc.region),
      district: trimmed(placeSrc.district),
      latitude: Number.isFinite(Number(placeSrc.latitude))
        ? Number(placeSrc.latitude)
        : null,
      longitude: Number.isFinite(Number(placeSrc.longitude))
        ? Number(placeSrc.longitude)
        : null,
    },

    schedule: {
      isRecurring,
      slots: isRecurring ? [] : normalizeSlots(scheduleSrc.slots),
      recurring: isRecurring ? normalizeRecurring(scheduleSrc.recurring) : null,
      deadlineRule: normalizeRecruitRule(scheduleSrc.deadlineRule, {
        defaultMode: 'none',
      }),
      openRule: normalizeRecruitRule(scheduleSrc.openRule, { defaultMode: 'none' }),
    },

    capacity: normalizeCapacity(src.capacity),
    pricing: normalizePricing(src.pricing),
    earlyBird: normalizeEarlyBird(src.earlyBird),
    refundTiers: normalizeRefundTiers(src.refundTiers),
    paymentPolicy: normalizePaymentPolicy(src.paymentPolicy),

    // 연령 제한 — 성별별 규칙 한 벌(partyAgeRestriction.js). 옛 스키마
    // (age.minBirthYear/maxBirthYear 남녀 공통)로 들어온 입력도 그 파일이
    // 흡수해 남녀 양쪽에 같은 값으로 채운다.
    age: normalizeAgeInput(ageSrc),

    taxonomy: {
      partyTypes: stringList(taxonomySrc.partyTypes, { limit: 5 }),
      vibes: stringList(taxonomySrc.vibes, { limit: 3 }),
      tags: stringList(taxonomySrc.tags, { limit: 6 }),
    },

    rounds: {
      enabled: hasMultipleRounds,
      capacityMode: roundCapacityMode,
      earlyBirdMode: roundEarlyBirdMode,
      round1MinCapacity: Math.max(0, intOf(roundsSrc.round1MinCapacity, 0)),
      extra: Array.isArray(roundsSrc.extra)
        ? roundsSrc.extra.map((r, i) => normalizeRound(r, i))
        : [],
      packages: Array.isArray(roundsSrc.packages)
        ? roundsSrc.packages.map((p, i) => normalizeRoundPackage(p, i))
        : [],
    },

    media: {
      images: stringList(mediaSrc.images),
      coverImageUrl: trimmed(mediaSrc.coverImageUrl) || null,
    },
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// 검증
// ═══════════════════════════════════════════════════════════════════════════

/// Dart PartyCapacityStatus.validate와 같은 규칙.
function validateCapacityPair(min, max) {
  if (min < 0) return '최소 모집 인원은 0명 이상이어야 합니다.';
  if (min > 0 && max > 0 && min > max) {
    return '최소 모집 인원은 최대 모집 인원보다 클 수 없습니다.';
  }
  return null;
}

/// 연령 제한 검증 — Dart PartyAgeRestriction 쪽 화면이 애초에 막는 값이지만,
/// createParty를 직접 부르면 얼마든지 뒤집힌 범위를 보낼 수 있다.
function validateAgeRestriction(age, genderLimit) {
  const eff = normalizedAgeFor(age, genderLimit);
  if (!eff.enabled) return null;
  for (const [gender, label] of [
    ['male', '남성'],
    ['female', '여성'],
  ]) {
    const l = eff[gender];
    if (!l.enabled) continue;
    if (
      l.minBirthYear !== null &&
      l.maxBirthYear !== null &&
      l.minBirthYear > l.maxBirthYear
    ) {
      return `${label} 연령 제한의 최소 나이가 최대 나이보다 클 수 없어요.`;
    }
  }
  return null;
}

/// 얼리버드 입력 검증 — Dart PartyEarlyBird.validate와 같은 규칙.
function validateEarlyBird(earlyBird, { isFree, isRecurring, now, occurrenceStart, recruitDeadline }) {
  if (!earlyBird.enabled) return null;
  if (isFree) return '무료 파티에는 얼리버드 할인을 적용할 수 없어요.';

  const percent = earlyBird.percent;
  if (percent == null || percent < 1 || percent > 99) {
    return '얼리버드 할인율은 1~99% 사이로 입력해주세요.';
  }

  const type = isRecurring ? 'beforeStart' : earlyBird.endType;
  if (type === 'fixedDate') {
    const endAt = earlyBird.endAt;
    if (!endAt) return '얼리버드 종료 날짜와 시간을 선택해주세요.';
    if (now && endAt.getTime() <= now.getTime()) {
      return '얼리버드 종료 시각이 이미 지났어요. 다시 선택해주세요.';
    }
    if (occurrenceStart && endAt.getTime() > occurrenceStart.getTime()) {
      return '얼리버드는 파티 시작 전에 끝나야 해요.';
    }
    if (recruitDeadline && endAt.getTime() > recruitDeadline.getTime()) {
      return '얼리버드는 모집 마감보다 늦게 끝날 수 없어요.';
    }
    return null;
  }

  // beforeStart — 규칙은 늘 완성돼 있으므로, 회차 정보를 알 때만 앞뒤를 본다.
  if (occurrenceStart) {
    const endAt = resolveEarlyBirdEnd(
      earlyBirdRuleFields(earlyBird.beforeStartRule),
      occurrenceStart
    );
    if (endAt && recruitDeadline && endAt.getTime() > recruitDeadline.getTime()) {
      return '얼리버드는 모집 마감보다 늦게 끝날 수 없어요.';
    }
  }
  return null;
}

/// 등록 입력 전체 검증. 문제가 없으면 빈 배열.
///
/// 반환 원소: { field, message } — field는 웹/앱이 어느 칸으로 안내할지 정하는
/// 열쇠이고, message는 그대로 사용자에게 보여주는 문구다.
function validateRegistration(input, { now = new Date() } = {}) {
  const errors = [];
  const push = (field, message) => errors.push({ field, message });

  if (!input.title) push('title', '파티명을 입력해주세요.');

  // ── 정원 ───────────────────────────────────────────────────────────────
  const cap = input.capacity;
  if (cap.maxCapacity <= 0) {
    push('capacity', '모집 인원을 입력해주세요.');
  }
  const capError = validateCapacityPair(cap.minCapacity, cap.maxCapacity);
  if (capError) push('capacity', capError);

  // ── 연령 제한 ──────────────────────────────────────────────────────────
  // 모집하는 성별의 제한만 본다 — 숨겨진 성별 값은 저장 전에 지워지므로
  // (ageFields) 그 값이 뒤집혀 있다고 등록을 막을 이유가 없다.
  const ageError = validateAgeRestriction(input.age, cap.genderLimit);
  if (ageError) push('age', ageError);

  // ── 참가비 ─────────────────────────────────────────────────────────────
  for (const [key, value] of [
    ['malePrice', input.pricing.malePrice],
    ['femalePrice', input.pricing.femalePrice],
    ['price', input.pricing.price],
  ]) {
    if (typeof value === 'number' && value % 1000 !== 0) {
      push('pricing', '참가비는 1,000원 단위로 입력해주세요. (무료면 0)');
      break;
    }
    void key;
  }

  // ── 환불 정책 ──────────────────────────────────────────────────────────
  // 무료 파티도 예외가 아니다(RefundPolicyRule.minTiers = 1).
  if (input.refundTiers.length < 1) {
    push('refundTiers', '환불 정책을 1개 이상 선택해주세요.');
  }

  // ── 일정 ───────────────────────────────────────────────────────────────
  let occurrenceStart = null;
  let occurrenceDeadline = null;
  if (input.schedule.isRecurring) {
    const rec = input.schedule.recurring;
    if (!rec || !rec.startDate) {
      push('schedule', '정기 파티의 운영 시작일을 설정해주세요.');
    } else if (!Object.values(rec.weekly).some((s) => s.enabled)) {
      push('schedule', '정기 파티의 운영 요일과 시간을 설정해주세요.');
    } else {
      const first = firstOccurrenceOf(rec, now);
      if (!first) {
        push('schedule', '운영 종료일이 지나 열릴 회차가 없어요. 기간을 다시 확인해주세요.');
      } else {
        occurrenceStart = first.start;
        occurrenceDeadline = first.deadline;
      }
    }
  } else if (input.schedule.slots.length === 0) {
    // 날짜 없이 사전등록(오픈예정)하는 경우만 허용한다.
    if (!input.dateTbd) {
      push('schedule', '파티 날짜와 시작 시간을 선택해주세요.');
    }
  } else {
    const w = resolveSlotWindow(input.schedule.slots[0]);
    occurrenceStart = w.start;
    occurrenceDeadline = resolveRuleAt(input.schedule.deadlineRule, w.start, w.end);
  }

  // ── 얼리버드 ───────────────────────────────────────────────────────────
  const ebError = validateEarlyBird(input.earlyBird, {
    isFree: isFreePricing(input.pricing),
    isRecurring: input.schedule.isRecurring,
    now,
    occurrenceStart,
    recruitDeadline: occurrenceDeadline,
  });
  if (ebError) push('earlyBird', ebError);

  // ── 차수 ───────────────────────────────────────────────────────────────
  if (input.rounds.enabled && occurrenceStart) {
    const perRound = input.rounds.capacityMode === 'perRound';
    const separateGender = cap.genderCapacityMode === 'separate';
    const isoDate = input.schedule.isRecurring
      ? isoDateOf(occurrenceStart)
      : input.schedule.slots[0].date;

    input.rounds.extra.forEach((round, i) => {
      const roundNumber = i + 2;
      const issues = validateRound(round, {
        roundNumber,
        isoDate,
        perRound,
        separateGender,
        isFree: isFreePricing(input.pricing),
      });
      for (const message of issues) push('rounds', message);
    });
  }

  return errors;
}

/// 차수 하나의 검증 — Dart PartyRound.validate와 같은 규칙. 문구까지 같다.
function validateRound(round, { roundNumber, isoDate, perRound, separateGender, isFree }) {
  const issues = [];
  const w = resolveRoundOn(round, isoDate);
  if (!w) return issues;

  if (!round.endTime) {
    issues.push(`${roundNumber}차 파티 종료 시간을 선택해주세요.`);
  }
  if (w.recruitOpenAt && w.recruitCloseAt && w.recruitOpenAt.getTime() >= w.recruitCloseAt.getTime()) {
    issues.push(`${roundNumber}차 모집 시작이 모집 마감보다 늦습니다. 다시 설정해주세요.`);
  }
  if (w.recruitCloseAt && w.recruitCloseAt.getTime() > w.end.getTime()) {
    issues.push(`${roundNumber}차 모집 마감은 파티 종료 전이어야 합니다.`);
  }

  if (perRound) {
    const capacityOk = separateGender
      ? round.maleCapacity > 0 || round.femaleCapacity > 0
      : round.maxCapacity > 0;
    if (!capacityOk) issues.push(`${roundNumber}차 모집 인원을 입력해주세요.`);

    const minError = validateCapacityPair(round.minCapacity, roundSeparateTotal(round));
    if (minError) issues.push(`${roundNumber}차 — ${minError}`);

    if (round.maleFee % 1000 !== 0 || round.femaleFee % 1000 !== 0) {
      issues.push(`${roundNumber}차 참가비를 1,000원 단위로 입력해주세요. (무료면 0)`);
    }
  }

  const ebError = validateEarlyBird(round.earlyBird, {
    isFree: perRound ? round.maleFee === 0 && round.femaleFee === 0 : isFree,
    isRecurring: true, // 차수는 날짜가 바뀌므로 늘 "시작 전" 규칙을 쓴다.
    now: null,
    occurrenceStart: w.start,
    recruitDeadline: w.recruitCloseAt,
  });
  if (ebError) issues.push(`${roundNumber}차 얼리버드 — ${ebError}`);

  return issues;
}

/// 절대 시각 → 그 시각이 속한 KST 달력 날짜의 'YYYY-MM-DD'.
function isoDateOf(date) {
  const shifted = new Date(date.getTime() + KST_OFFSET_MS);
  return (
    `${shifted.getUTCFullYear()}-` +
    `${String(shifted.getUTCMonth() + 1).padStart(2, '0')}-` +
    `${String(shifted.getUTCDate()).padStart(2, '0')}`
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// 문서 조립
// ═══════════════════════════════════════════════════════════════════════════

/// 문서 최상단에 남길 대표 얼리버드 — Dart _representativeEarlyBird.
///
/// 목록 카드의 얼리버드 뱃지는 차수를 모르고 문서 최상단만 읽는다. 차수별로
/// 켠 경우에도 "이 파티에 얼리버드가 있다"는 사실이 사라지지 않도록 켜져 있는
/// 첫 차수의 규칙을 대표로 남긴다(실제 결제 금액은 차수별 규칙으로 계산된다).
function representativeEarlyBird(input) {
  const { enabled: hasRounds, earlyBirdMode, extra } = input.rounds;
  if (!hasRounds) return input.earlyBird;
  if (earlyBirdMode === 'none') return EARLY_BIRD_OFF;
  if (earlyBirdMode === 'uniform') {
    return { ...input.earlyBird, endType: 'beforeStart' };
  }
  if (input.earlyBird.enabled) {
    return { ...input.earlyBird, endType: 'beforeStart' };
  }
  for (const r of extra) {
    if (r.earlyBird.enabled) return r.earlyBird;
  }
  return EARLY_BIRD_OFF;
}

/// 차수 하나에 적용할 얼리버드 — Dart _roundEarlyBirdOf.
function roundEarlyBirdOf(input, own) {
  if (!input.rounds.enabled) return own;
  if (input.rounds.earlyBirdMode === 'none') return EARLY_BIRD_OFF;
  if (input.rounds.earlyBirdMode === 'uniform') {
    return { ...input.earlyBird, endType: 'beforeStart' };
  }
  return own;
}

/// 그 날짜의 rounds 배열. 1차는 슬롯의 시작 시각·파티 전체 설정이 곧 내용이라
/// 여기서 PartyRound 하나로 모아 2차 이상과 **같은 모양**으로 만든다.
function buildRoundsFor(input, slot) {
  if (!input.rounds.enabled) return null;
  const cap = input.capacity;
  const perRound = input.rounds.capacityMode === 'perRound';

  const firstRound = {
    id: 'round_1',
    label: '1차',
    startTime: slot.startTime,
    endTime: slot.endTime,
    openRule: input.schedule.isRecurring
      ? input.schedule.recurring.openRule
      : input.schedule.openRule,
    closeRule: input.schedule.isRecurring
      ? input.schedule.recurring.deadlineRule
      : input.schedule.deadlineRule,
    // 1차 **차수**의 최소 인원 — 파티 전체 최소 모집 인원과 다른 값이다.
    minCapacity: input.rounds.round1MinCapacity,
    maxCapacity: cap.maxCapacity,
    maleCapacity: cap.maleCapacity,
    femaleCapacity: cap.femaleCapacity,
    maleFee: priceForGender(input.pricing, 'male'),
    femaleFee: priceForGender(input.pricing, 'female'),
    earlyBird: roundEarlyBirdOf(input, input.earlyBird),
  };

  const out = [
    roundFields(firstRound, { roundNumber: 1, isoDate: slot.date, perRound }),
  ];
  input.rounds.extra.forEach((round, i) => {
    out.push(
      roundFields(
        { ...round, earlyBird: roundEarlyBirdOf(input, round.earlyBird) },
        { roundNumber: i + 2, isoDate: slot.date, perRound }
      )
    );
  });
  return out;
}

/// 차수 패키지 배열. 포함 차수·금액은 슬롯과 무관하고, 얼리버드 종료 시각만
/// 그 슬롯의 "첫 포함 차수 시작 시각"으로 계산된다.
function buildRoundPackagesFor(input, slot) {
  const rounds = buildRoundsFor(input, slot) || [];
  const startOf = (roundNumber) => {
    const found = rounds.find((r) => r.roundNumber === roundNumber);
    return found ? found.time : null;
  };
  return input.rounds.packages.map((pkg) =>
    roundPackageFields(pkg, {
      firstRoundStart: pkg.roundNumbers.length > 0 ? startOf(pkg.roundNumbers[0]) : null,
    })
  );
}

/// perRound 모드에서는 라운드를 모르는 기존 코드(피드 카드 등)를 위해 상단 정원
/// 필드를 라운드 전체 합계로 채운다.
///
/// ⚠️ **최소 인원은 합산하지 않는다.** 정원은 자리 수라 더할 수 있지만, 최소
/// 모집 인원은 "이 파티가 열리려면 몇 명이 와야 하는가"라 더할 수 있는 값이
/// 아니다(1차·2차를 다 신청한 한 사람이 두 번 세진다).
function aggregateCapacity(input, primarySlot) {
  const cap = input.capacity;
  const base = {
    maxCapacity: cap.maxCapacity,
    maleCapacity: cap.maleCapacity,
    femaleCapacity: cap.femaleCapacity,
  };
  if (!input.rounds.enabled || input.rounds.capacityMode !== 'perRound' || !primarySlot) {
    return base;
  }
  const rounds = buildRoundsFor(input, primarySlot);
  if (!rounds) return base;
  return rounds.reduce(
    (acc, r) => ({
      maxCapacity: acc.maxCapacity + (r.maxCapacity || 0),
      maleCapacity: acc.maleCapacity + (r.maleCapacity || 0),
      femaleCapacity: acc.femaleCapacity + (r.femaleCapacity || 0),
    }),
    { maxCapacity: 0, maleCapacity: 0, femaleCapacity: 0 }
  );
}

/// 모든 날짜 문서가 **동일하게 공유하는** 필드.
///
/// 날짜 종속 필드(date/partyDateTime/recruitDeadlineAt/rounds)는 여기 없다 —
/// buildSlotFields가 슬롯마다 따로 계산한다.
function buildSharedFields(input, { primarySlot, businessVerified, now }) {
  const cap = input.capacity;
  const agg = aggregateCapacity(input, primarySlot);
  const isRecurring = input.schedule.isRecurring;
  const pricing = input.pricing;
  // 날짜가 없는 문서는 인증 호스트라도 열 수 없다.
  const datelessPreopen = !primarySlot;

  const fields = {
    title: input.title,
    location: input.place.location,
    address: input.place.address,
    roadAddress: input.place.roadAddress,
    jibunAddress: input.place.jibunAddress,
    placeName: input.place.placeName,
    detailAddress: input.place.detailAddress,
    region: input.place.region,
    district: input.place.district,

    // ── 성별 / 정원 ──────────────────────────────────────────────────────
    people: `0/${agg.maxCapacity}명`,
    genderLimit: cap.genderLimit,
    genderCapacityMode: cap.genderCapacityMode,
    genderMode: cap.genderMode,
    maleCapacity: agg.maleCapacity,
    femaleCapacity: agg.femaleCapacity,
    currentMaleCount: 0,
    currentFemaleCount: 0,
    // 참가자 현황 공개 — 신규 파티는 값을 그대로 적는다("필드 없음 = 공개"
    // 폴백은 이 설정이 생기기 전 파티만을 위한 장치다).
    [PARTICIPANT_GENDER_VISIBILITY_FIELD]: cap.revealParticipantGenderRatio,
    // 파티 전체 최소 모집 인원 — 차수 합계가 아니라 호스트가 정한 값 하나다.
    // 옛 필드(minCapacity)도 같은 값으로 함께 써서 예전 코드가 읽어도
    // 어긋나지 않게 한다.
    [PARTY_MIN_CAPACITY_FIELD]: cap.minCapacity,
    minCapacity: cap.minCapacity,
    maxCapacity: agg.maxCapacity,
    // 최소 인원을 안 정했으면 미달이라는 개념 자체가 없다.
    minCapacityPolicy: cap.minCapacity > 0 ? cap.minCapacityPolicy : 'proceed',
    maxParticipants: agg.maxCapacity,
    currentParticipants: 0,

    // ── 금액 ─────────────────────────────────────────────────────────────
    ...pricingFields(pricing),
    ...earlyBirdFields(representativeEarlyBird(input), { isRecurring }),
    refundPolicy: input.refundTiers.map((t) => ({
      daysBefore: t.daysBefore,
      refundPercent: t.refundPercent,
    })),

    // ── 조건 / 분류 ──────────────────────────────────────────────────────
    // 연령 제한은 **성별별**이다 — 성별 필드가 정본이고, 아직 갱신되지 않은
    // 구버전 앱을 위해 옛 공통 필드(minBirthYear/maxBirthYear)도 표현할 수
    // 있을 때만 함께 남긴다. 모집하지 않는 성별의 값은 여기서 지워진다
    // (partyAgeRestriction.js normalizedFor — 성별 모집을 바꿨을 때 숨겨진
    // 성별의 옛 제한이 되살아나지 않게 하는 자리다).
    ...ageFields(input.age, cap.genderLimit),
    // 유형을 고르지 않으면 화면별 기본 카테고리 — 파티 등록은 '기타'.
    category:
      input.taxonomy.partyTypes.length > 0
        ? partyTypeLabelOf(input.taxonomy.partyTypes[0])
        : '기타',
    partyTypes: input.taxonomy.partyTypes,
    vibes: input.taxonomy.vibes,
    tags: input.taxonomy.tags,

    // ── 내용 ─────────────────────────────────────────────────────────────
    description: input.description,
    [PARTYCHU_PERK_FIELD]: input.partychuPerk,
    [INQUIRY_FIELD]: input.inquiryEnabled,
    [INQUIRY_GUIDE_FIELD]: input.inquiryEnabled ? input.inquiryGuide : '',

    // ── 차수 ─────────────────────────────────────────────────────────────
    hasMultipleRounds: input.rounds.enabled,

    // ── 미디어 ───────────────────────────────────────────────────────────
    images: input.media.images,
    mainImageUrl: input.media.images.length > 0 ? input.media.images[0] : null,
    coverMediaType: 'image',
    coverImageUrl: input.media.coverImageUrl || (input.media.images[0] || null),
    coverThumbnailUrl: input.media.coverImageUrl || (input.media.images[0] || null),

    // ── 상태 ─────────────────────────────────────────────────────────────
    recruitStatus: '모집중',
    // 오픈 상태 — recruitStatus와 별개의 독립 필드다. 사업자 인증을 마치지
    // 않은 호스트는 'preopen'으로만 저장할 수 있다(firestore.rules가 같은
    // 판정을 한다).
    openState: businessVerified && !datelessPreopen ? 'open' : 'preopen',
    hostBusinessVerified: businessVerified,
    dateTbd: datelessPreopen,
    // 이 경로로 저장되는 문서는 항상 재등록 가능하다(옛 이름이 'isRecurring'일
    // 뿐 "매주 반복"이 아니다 — 반복 판정은 scheduleType이 한다).
    isRecurring: true,
    lastUsedAt: now,
    isActive: true,
    isDeleted: false,
    status: 'active',
  };

  // (연령 제한 필드는 위 ageFields()가 한 번에 만든다 — 선택 항목이라 고르지
  //  않으면 ageRestrictionEnabled: false 하나만 남는다.)

  if (input.rounds.enabled) {
    fields.roundCapacityMode = input.rounds.capacityMode;
    // 얼리버드 적용 방식은 **화면 복원용 표식**이다 — 금액 계산은 각 차수(또는
    // 문서 최상단)의 규칙만 읽는다.
    fields.roundEarlyBirdMode = input.rounds.earlyBirdMode;
  }

  // 결제 방식 — 유료 파티에서 호스트가 설정했을 때만 남긴다. 무료 파티나
  // 미설정은 필드를 아예 만들지 않아 서버가 기존 동작을 그대로 태운다.
  if (!isFreePricing(pricing) && input.paymentPolicy) {
    Object.assign(fields, input.paymentPolicy);
  }

  return fields;
}

/// 슬롯(날짜) 하나마다 달라지는 필드.
function buildSlotFields(input, slot, { now }) {
  const w = resolveSlotWindow(slot);
  const deadlineAt = resolveRuleAt(input.schedule.deadlineRule, w.start, w.end);
  const openAt = resolveRuleAt(input.schedule.openRule, w.start, w.end);
  const perRound = input.rounds.capacityMode === 'perRound';

  const fields = {
    date: `${formatPartyDate(slot.date)} ${formatPartyTime(slot.startTime)}`,
    partyDateTime: w.start,
  };
  if (deadlineAt) fields.recruitDeadlineAt = deadlineAt;

  if (input.rounds.enabled) {
    fields.rounds = buildRoundsFor(input, slot);
    if (perRound && input.rounds.packages.length > 0) {
      fields.roundPackages = buildRoundPackagesFor(input, slot);
    }
  }

  if (input.schedule.isRecurring) {
    Object.assign(
      fields,
      buildRecurringFields(input.schedule.recurring, {
        firstOccurrence: firstOccurrenceOf(input.schedule.recurring, now),
      })
    );
  } else {
    Object.assign(
      fields,
      buildSingleFields(slot, {
        deadlineRule: input.schedule.deadlineRule,
        openRule: input.schedule.openRule,
        deadlineAt,
        openAt,
      })
    );
  }
  return fields;
}

/// 등록 입력 하나 → 저장할 parties 문서들.
///
/// 반환: { seriesId, shared, docs: [{ dateSlotId, fields }] }
///
///  · 날짜를 여러 개 고르면 **날짜마다 문서 하나**가 만들어지고 같은 seriesId로
///    묶인다(문서 하나가 곧 일정 하나다).
///  · 정기 파티는 문서 1개다 — 회차는 recurringSchedule로 계산된다.
///  · 날짜 없이 사전등록하는 오픈예정 파티는 날짜 필드를 **아예 쓰지 않는다**
///    (빈 값으로 채우면 "날짜를 못 읽는 옛 문서"와 구별할 수 없다).
function buildPartyDocuments(rawInput, options = {}) {
  const {
    now = new Date(),
    hostId,
    hostUid,
    seriesId,
    businessVerified = false,
  } = options;

  const input = rawInput && rawInput.__normalized ? rawInput : normalizeInput(rawInput);

  // 정기 파티는 날짜 슬롯 대신 "첫 회차"를 기준 슬롯 하나로 만들어 쓴다 —
  // 정원/차수/얼리버드 등 날짜에 얽힌 계산을 그대로 재사용하기 위해서다.
  let slots = input.schedule.slots;
  if (input.schedule.isRecurring) {
    const first = firstOccurrenceOf(input.schedule.recurring, now);
    slots = first
      ? [
          {
            date: isoDateOf(first.start),
            startTime: hmOf(first.start),
            endTime: hmOf(first.end),
          },
        ]
      : [];
  }

  const primarySlot = slots.length > 0 ? slots[0] : null;
  const shared = buildSharedFields(input, { primarySlot, businessVerified, now });

  const base = {
    hostId,
    hostUid,
    applicants: [],
    approvedApplicants: [],
    rejectedApplicants: [],
    approved: true,
    createdAt: now,
    seriesId,
  };

  if (!primarySlot) {
    // 날짜 미정 사전등록 — 문서 하나, 날짜 필드 없음.
    return {
      seriesId,
      shared,
      docs: [{ dateSlotId: `slot_${now.getTime()}_0`, fields: { ...shared, ...base } }],
    };
  }

  const docs = slots.map((slot, i) => {
    const dateSlotId = `slot_${now.getTime()}_${i}`;
    return {
      dateSlotId,
      fields: {
        ...shared,
        ...buildSlotFields(input, slot, { now }),
        ...base,
        dateSlotId,
      },
    };
  });

  return { seriesId, shared, docs };
}

/// 절대 시각 → KST 벽시계 {h, m}.
function hmOf(date) {
  const shifted = new Date(date.getTime() + KST_OFFSET_MS);
  return { h: shifted.getUTCHours(), m: shifted.getUTCMinutes() };
}

module.exports = {
  // 입력 처리
  normalizeInput,
  validateRegistration,
  buildPartyDocuments,

  // 조각별 조립 — 셀프체크와 파리티 픽스처가 직접 부른다.
  normalizePricing,
  pricingFields,
  normalizeEarlyBird,
  earlyBirdFields,
  earlyBirdRuleFields,
  normalizeRecruitRule,
  recruitRuleFields,
  resolveRuleAt,
  normalizeRound,
  roundFields,
  resolveRoundOn,
  normalizeRoundPackage,
  roundPackageFields,
  normalizeRecurring,
  buildSingleFields,
  buildRecurringFields,
  firstOccurrenceOf,
  buildSharedFields,
  buildSlotFields,
  validateRound,

  // 헬퍼
  parseIsoDate,
  parseHm,
  formatHm,
  formatPartyDate,
  formatPartyTime,
  isoDateOf,
  kstAt,

  // 상수
  WEEKDAY_KEYS_MON_FIRST,
  PARTY_TYPE_LABELS,
  PARTY_TYPES,
  PARTY_VIBES,
  MAX_PARTY_TYPES,
  MAX_VIBES,
  MAX_TAGS,
  partyTypeLabelOf,
  PARTY_MIN_CAPACITY_FIELD,
  PARTICIPANT_GENDER_VISIBILITY_FIELD,
  PARTICIPANT_GENDER_VISIBILITY_DEFAULT,
  INQUIRY_FIELD,
  PARTYCHU_PERK_FIELD,
};

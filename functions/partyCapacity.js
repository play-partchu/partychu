// 파티 참가 정원/자격 검증 + 참가비 계산 공통 헬퍼 — index.js(applyToParty/
// cancelApplication)와 packageBookings.js(숙박+파티 패키지 예약)가 동일한
// 로직을 공유한다. 원래 index.js의 applyToParty/cancelApplication 트랜잭션
// 본문에 있던 코드를 그대로 함수로 뽑아낸 것으로, 동작은 바뀌지 않는다.
//
// ═══════════════════════════════════════════════════════════════════════════
// 정원 카운터의 소유권 — 이 파일 밖에서 직접 쓰지 않는다
// ═══════════════════════════════════════════════════════════════════════════
//
// 참가 인원 카운터를 **계산해서 쓰는 곳은 이 파일의 두 함수뿐이다.**
//
//   reserveApplicantSlot()  ← 자리를 잡을 때
//   releaseApplicantSlot()  ← 자리를 되돌릴 때 (취소·거절·입금만료·콤보취소)
//
// 호출부는 돌려받은 updateData를 transaction.update(partyRef, ...)에 그대로
// 넘기기만 한다. 새 취소 경로나 새 예약 경로가 생겨도 **여기를 거쳐야 한다** —
// 어느 한 곳이라도 카운터를 직접 조립하면 아래 라우팅이 갈라지고, 그 순간
// 회차 간 정원이 서로 새기 시작한다(예전에 실제로 그랬다).
//
// 대상 필드: currentParticipants · currentMaleCount · currentFemaleCount ·
//            people · applicants · approvedApplicants · rejectedApplicants ·
//            rounds[] 의 카운터 · occurrenceStats.*
//
// ── 어디에 쓰는가 (occurrenceId 유무로 갈린다) ─────────────────────────────
//
//                        │ 회차 없음(일회성·날짜별 문서) │ 회차 있음(정기 파티)
//   ─────────────────────┼──────────────────────────────┼────────────────────
//   전체 인원            │ 문서 최상단 스칼라            │ occurrenceStats.{회차}
//   차수별 인원          │ 최상단 rounds[]               │ occurrenceStats.{회차}.rounds
//   그 회차 신청자 명단  │ 최상단 applicants             │ occurrenceStats.{회차}.applicants
//   "살아 있는 신청 있음"│ 최상단 applicants             │ 최상단 applicants (양쪽 공용)
//
// **정기 파티에서 최상단 rounds[]와 스칼라 카운터는 더 이상 갱신하지 않는다.**
// 그 값들은 회차 구분이 없어서, 한 회차의 신청이 다른 회차의 자리를 차지하는
// 통로가 된다. 정기 파티가 그 필드를 새로 쓰는 코드가 생기면 8/15 신청이
// 8/22 정원을 갉아먹는 상태로 되돌아간다.
//
// 일회성 파티는 위 표의 왼쪽 열 그대로다 — 구조도 동작도 바뀐 것이 없고,
// 바꿀 이유도 없다(마이그레이션을 만들지 않기 위한 의도적 선택이다).
//
// ── 되돌릴 때 어느 칸인지 (roundCounterScope) ─────────────────────────────
//
// 신청 문서(콤보는 예약 문서)에 남는 `roundCounterScope`가 그 답이다:
//
//   'occurrence' → 차수 인원을 occurrenceStats.{회차}.rounds 에 올렸다
//   (없음)       → 최상단 rounds[] 에 올렸다 (회차별 차수 카운터 도입 이전 신청)
//
// reserveApplicantSlot이 이 값을 돌려주고, 호출부가 문서에 저장하고,
// releaseApplicantSlot이 그 값을 그대로 돌려받아 같은 칸을 되돌린다. 이 왕복이
// 끊기면 취소가 엉뚱한 칸을 건드린다 — 회차 칸의 존재 여부로 추측하면 안 되는
// 이유는 ROUND_SCOPE_OCCURRENCE 주석 참고.

const { HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const {
  isRecurringParty,
  checkRecurringRecruitOpen,
  earlyBirdEndAtFor,
  effectivePartyStartAt,
  kstMidnightOf,
  resolveEarlyBirdEnd,
  toDate,
} = require('./partySchedule');
// 최소 인원 미달로 **회차 하나만** 자동 취소된 경우의 표시. 파티 문서 전체는
// 여전히 '모집중'이라(다른 날짜 회차가 열려 있어야 하므로) 아래 recruitStatus
// 검사만으로는 걸러지지 않는다 — 회차 신청은 이 기록을 따로 봐야 한다.
const { isOccurrenceCancelled, occurrenceIdOf } = require('./partyMinCapacity');
const {
  parseAgeRestriction,
  effectiveLimitFor: ageEffectiveLimitFor,
  limitAllows: ageLimitAllows,
} = require('./partyAgeRestriction');
// 성별별 모집 상태 — 호스트가 남/여 모집을 따로 닫을 수 있다. 파티 문서
// 전체는 '모집중' 그대로라(다른 성별은 계속 받는다) 위 recruitStatus 검사만
// 으로는 걸러지지 않는다.
const {
  closedMessageFor: genderRecruitClosedMessage,
} = require('./partyGenderRecruit');

// 정기 파티는 위 두 값(모집 상태·성별 모집)을 **회차마다** 따로 둘 수 있다.
// 회차 칸이 없거나 회차를 모르는 신청은 문서 최상단 값으로 폴백하므로, 이
// 두 함수는 일회성·날짜 슬롯 파티에서 예전 판정과 완전히 같은 답을 낸다
// (partyOccurrenceRecruit.js).
const {
  occurrenceStatusOf,
  isGenderRecruitClosedAt,
} = require('./partyOccurrenceRecruit');

// 얼리버드 할인: 신청 확정 시점의 실제 적용 금액(appliedFee)을 **서버가**
// 계산한다. 클라이언트는 금액을 보내지 않으며, 보내더라도 쓰지 않는다.
//
// 종료 시각은 문서의 earlyBirdEndAt을 그대로 읽지 않고 earlyBirdEndAtFor()로
// 구한다 — 정기 파티는 회차마다 종료 시각이 새로 계산되기 때문이다(일회성은
// 예전처럼 저장된 earlyBirdEndAt 그대로).
// (lib/utils/early_bird.dart의 계산 로직과 동일하게 유지해야 함)
// 참가비 기본가 — 새 구조(pricingType/price/malePrice/femalePrice)를 우선
// 읽고, 없으면 기존 maleFee/femaleFee/fee로 폴백한다. 클라이언트
// lib/models/party_pricing.dart와 같은 규칙을 유지해야 한다.
function resolveBaseFee(data, gender) {
  const num = (v) => (v == null ? null : Number(v));

  switch (data.pricingType) {
    case 'free':
      return 0;
    case 'same': {
      const price = num(data.price) ?? num(data.maleFee) ?? num(data.femaleFee);
      return price ?? 0;
    }
    case 'gendered': {
      const male = num(data.malePrice) ?? num(data.maleFee);
      const female = num(data.femalePrice) ?? num(data.femaleFee);
      if (gender === 'male' && male != null) return male;
      if (gender === 'female' && female != null) return female;
      // 성별을 모르면 낮은 쪽(최소 참가비)을 적용한다 — 실제 신청은 성별
      // 인증이 끝난 사용자만 가능하므로 방어적 폴백이다.
      const values = [male, female].filter((v) => v != null && v > 0);
      return values.length ? Math.min(...values) : 0;
    }
    default:
      break;
  }

  // pricingType이 없는 기존 문서 — 예전 동작 그대로.
  if (gender === 'male' && data.maleFee != null) return Number(data.maleFee);
  if (gender === 'female' && data.femaleFee != null) return Number(data.femaleFee);
  if (data.maleFee != null) return Number(data.maleFee);
  if (data.femaleFee != null) return Number(data.femaleFee);
  if (data.fee != null) return Number(data.fee);
  // 플레이스+파티가 단일 price만 저장하던 문서.
  if (data.price != null) return Number(data.price);
  return 0;
}

// [occurrence]를 넘기면 그 회차 기준으로 얼리버드를 판정한다(사용자가 특정
// 회차를 골라 신청하는 경로). 없으면 "지금 기준 다음 회차".
function computeAppliedFee(data, gender, now = new Date(), occurrence = null) {
  const baseFee = resolveBaseFee(data, gender);

  if (baseFee <= 0) return baseFee;
  if (data.earlyBirdEnabled !== true) return baseFee;

  const endAt = earlyBirdEndAtFor(data, now, occurrence);
  // 종료 시각을 계산할 수 없으면(정기인데 남은 회차 없음/규칙 깨짐) 정상가.
  if (!endAt) return baseFee;
  if (endAt.getTime() <= now.getTime()) return baseFee; // 종료됨 → 정상가

  const pct = Number(data.earlyBirdDiscountPercent || 0);
  const discounted = Math.round(baseFee * (100 - pct) / 100);
  return discounted < 0 ? 0 : discounted;
}

// 다차수(1차/2차/3차) 파티의 "라운드별 정원" 모드에서, 선택한 라운드들의
// 참가비를 합산한다.
//
// 차수마다 얼리버드를 따로 켤 수 있으므로 할인도 **그 차수 자신의 시작
// 시각과 규칙**으로 계산한다(클라이언트 PartyRound와 같은 규칙).
//
// [data]를 넘기면 **차수에 값이 아예 없을 때** 문서 최상단 참가비·얼리버드로
// 폴백한다. 차수별 참가비를 저장하기 전에 만들어진 라운드 파티(1차 가격이
// 문서 최상단에만 있는 문서)에서 금액이 0원이 되지 않게 하기 위한 것이고,
// 새로 저장하는 문서는 차수마다 값을 갖고 있어 이 경로를 타지 않는다.
// 클라이언트 PartyRoundOffers._roundOffer와 **같은 규칙**이어야 한다.
function computeAppliedFeeForRounds(
  rounds,
  selectedRoundNumbers,
  gender,
  now = new Date(),
  data = null
) {
  const doc = data || {};
  return selectedRoundNumbers.reduce((sum, rn) => {
    const round = rounds.find((r) => r.roundNumber === rn);
    if (!round) return sum;
    const hasOwnFee = round.maleFee != null || round.femaleFee != null;
    const baseFee = hasOwnFee
      ? gender === 'male'
        ? Number(round.maleFee || 0)
        : Number(round.femaleFee || 0)
      : resolveBaseFee(doc, gender);
    // 얼리버드 필드가 아예 없는 차수는 문서 최상단 규칙을 **그 차수의 시작
    // 시각**에 적용한다 — 규칙만 사라져 정상가로 받는 일을 막는다.
    // (필드가 있고 false면 그 차수는 할인이 꺼진 것이다 — 폴백하지 않는다.)
    const source =
      round.earlyBirdEnabled != null
        ? round
        : {
            ...round,
            earlyBirdEnabled: doc.earlyBirdEnabled,
            earlyBirdDiscountPercent: doc.earlyBirdDiscountPercent,
            earlyBirdDeadlineRule: doc.earlyBirdDeadlineRule,
            // 규칙 없이 고정 종료 시각만 쓰던 문서도 그대로 살린다.
            earlyBirdEndAt: doc.earlyBirdEndAt,
          };
    return sum + applyRoundEarlyBird(source, baseFee, now);
  }, 0);
}

// ── 차수 패키지 ────────────────────────────────────────────────────────────
// parties.roundPackages: [{ id, name, roundNumbers[], maleFee, femaleFee,
//   earlyBirdEnabled, earlyBirdMaleFee, earlyBirdFemaleFee,
//   earlyBirdDeadlineRule, earlyBirdEndAt }]
// (클라이언트 lib/models/party_round_package.dart와 같은 스키마)
//
// 패키지는 **별도 판매 상품**이다 — 포함 차수의 참가비를 합산하지 않고 저장된
// 판매가를 그대로 쓴다. 정원은 따로 두지 않는다: 패키지 신청자는 포함된 각
// 차수의 정원을 1명씩 차지하므로, selectedRounds 경로(reserveApplicantSlot의
// perRound 분기)를 그대로 재사용한다.
function findRoundPackage(data, packageId) {
  if (!packageId) return null;
  const list = Array.isArray(data.roundPackages) ? data.roundPackages : [];
  const pkg = list.find((p) => p && p.id === packageId);
  if (!pkg) return null;
  const numbers = Array.isArray(pkg.roundNumbers)
    ? [...new Set(pkg.roundNumbers.map((n) => Number(n)))].sort((a, b) => a - b)
    : [];
  // 2개 미만이면 패키지가 아니다(등록 화면도 같은 기준으로 막는다).
  if (numbers.length < 2) return null;
  return { ...pkg, roundNumbers: numbers };
}

// 패키지 하나의 실제 결제 금액. 얼리버드는 할인율이 아니라 **얼리버드 판매가**를
// 그대로 쓴다(클라이언트 PartyRoundOffers와 같은 규칙).
function computePackageFee(pkg, rounds, gender, now = new Date()) {
  const feeOf = (male, female) => {
    const m = Number(male || 0);
    const f = Number(female || 0);
    if (gender === 'male') return m;
    if (gender === 'female') return f;
    // 성별을 모르면 낮은 쪽(최소 참가비) — resolveBaseFee와 같은 폴백이다.
    const values = [m, f].filter((v) => v > 0);
    return values.length ? Math.min(...values) : 0;
  };

  const baseFee = feeOf(pkg.maleFee, pkg.femaleFee);
  if (baseFee <= 0) return baseFee;
  if (pkg.earlyBirdEnabled !== true) return baseFee;

  // 종료 시각: 저장된 캐시가 있으면 그대로, 없으면 포함된 첫 차수의 시작
  // 시각에 규칙을 적용한다(차수 얼리버드와 같은 방식).
  const firstRound = rounds.find((r) => r.roundNumber === pkg.roundNumbers[0]);
  const firstStart = firstRound ? toDate(firstRound.time) : null;
  const endAt =
    toDate(pkg.earlyBirdEndAt) ||
    (firstStart ? resolveEarlyBirdEnd(pkg.earlyBirdDeadlineRule, firstStart) : null);
  if (!endAt || endAt.getTime() <= now.getTime()) return baseFee;

  const ebFee = feeOf(pkg.earlyBirdMaleFee, pkg.earlyBirdFemaleFee);
  return ebFee > 0 && ebFee < baseFee ? ebFee : baseFee;
}

// 차수 하나의 얼리버드 할인을 적용한 금액.
function applyRoundEarlyBird(round, baseFee, now) {
  if (baseFee <= 0) return baseFee;
  if (round.earlyBirdEnabled !== true) return baseFee;

  const start = toDate(round.time);
  if (!start) return baseFee;
  // 차수 얼리버드는 늘 "시작 전" 상대 규칙이다(차수마다 날짜가 다르므로).
  const endAt =
    resolveEarlyBirdEnd(round.earlyBirdDeadlineRule, start) ||
    toDate(round.earlyBirdEndAt);
  if (!endAt || endAt.getTime() <= now.getTime()) return baseFee;

  const pct = Number(round.earlyBirdDiscountPercent || 0);
  const discounted = Math.round((baseFee * (100 - pct)) / 100);
  return discounted < 0 ? 0 : discounted;
}

// 차수의 모집 창구가 [now]에 열려 있는지 — 클라이언트
// PartyRoundWindow.isRecruitingAt()과 같은 규칙이다.
//
// 차수별 모집 시작/마감이 없던 예전 문서는 창구 정보가 없으므로 여기서 막지
// 않는다(그때는 문서 전체의 recruitDeadlineAt이 그 역할을 했고, 그 검사는
// 아래에서 따로 한다).
// 차수 하나의 "전체 정원". 남녀무관 모드에서 정원 판정의 기준이 된다.
//
// 새 문서는 maxCapacity를 채워 저장하지만, 그 필드가 없던 예전 문서도 있어
// 남녀 정원의 합으로 폴백한다(둘 다 없으면 0 = 제한 없음).
function roundMaxCapacityOf(round) {
  const max = Number(round.maxCapacity || 0);
  if (max > 0) return max;
  return Number(round.maleCapacity || 0) + Number(round.femaleCapacity || 0);
}

// 차수 하나의 현재 인원. currentParticipants가 없던 예전 문서는 남녀
// 카운터의 합으로 읽는다(예전에는 그 합이 곧 전체 인원이었다).
function roundCurrentOf(round) {
  const cur = Number(round.currentParticipants || 0);
  if (cur > 0) return cur;
  return Number(round.currentMaleCount || 0) + Number(round.currentFemaleCount || 0);
}

// ── 차수 시각을 "이 회차의 날짜"로 다시 계산 ───────────────────────────────
//
// rounds[]의 time/endAt/recruitOpenAt/recruitCloseAt은 **등록 시점의 날짜
// 하나로 굳어 있는 캐시**다. 정기 파티는 회차마다 날짜가 다르고, 날짜만 바꿔
// 재등록한 문서도 있어서, 그 값을 그대로 판정에 쓰면 첫 회차가 지난 순간부터
// 모든 차수가 "이미 끝난 차수"가 된다 — 정기 파티에 문서 전체의
// recruitDeadlineAt을 저장하지 않는 것과 똑같은 이유이고, 차수도 같은 처리를
// 받아야 한다.
//
// 그래서 판정 직전에 이 회차의 날짜로 옮긴 **사본**을 만들어 쓴다. 저장된 네
// 시각을 모두 같은 일수만큼 옮기므로 시:분과 서로의 간격(자정을 넘겨 다음 날
// 새벽에 끝나는 2차, 시작 1시간 전 마감 등)은 그대로 유지된다. 등록 시 네
// 시각이 모두 같은 날짜 하나에서 계산되고 KST에는 서머타임이 없으므로, 이
// 결과는 클라이언트 PartyRound.resolveOn(회차 날짜)과 정확히 같다
// (lib/models/party_round_offer.dart의 _windowOf 참고 — 한쪽만 고치면 앱에는
//  '신청 가능'인데 서버는 '지금 신청받지 않습니다'로 막는 상태가 된다).
//
// **판정 전용이다.** 여기서 만든 사본을 문서에 다시 쓰면 안 된다 — 한 사람이
// 고른 회차의 날짜가 파티 원본에 박제된다.
function rebaseRoundSchedule(round, baseStart) {
  const start = toDate(round.time);
  if (!start || !baseStart) return round;
  const shift =
    kstMidnightOf(baseStart).getTime() - kstMidnightOf(start).getTime();
  if (shift === 0) return round;
  const moved = (value) => {
    const d = toDate(value);
    return d ? new Date(d.getTime() + shift) : value;
  };
  return {
    ...round,
    time: moved(round.time),
    endAt: moved(round.endAt),
    recruitOpenAt: moved(round.recruitOpenAt),
    recruitCloseAt: moved(round.recruitCloseAt),
    earlyBirdEndAt: moved(round.earlyBirdEndAt),
  };
}

function rebaseRounds(rounds, baseStart) {
  const list = Array.isArray(rounds) ? rounds : [];
  if (!baseStart) return list;
  return list.map((r) => rebaseRoundSchedule(r, baseStart));
}

// 차수 시각을 맞출 기준 날짜 — 고른 회차가 있으면 그 회차, 없으면 이 파티의
// 실제 시작 시각(정기: 지금 기준 다음 회차 / 일회성: 저장된 partyDateTime).
// 클라이언트 party_detail_screen.dart의 _roundBaseDate()와 같은 규칙이다.
// null이면(더 열릴 회차가 없는 정기 파티) 저장된 절대 시각을 그대로 쓴다.
function roundScheduleBaseOf(data, occurrence, now = new Date()) {
  if (occurrence && occurrence.start) return occurrence.start;
  return effectivePartyStartAt(data, now);
}

function isRoundRecruitOpen(round, now) {
  const openAt = toDate(round.recruitOpenAt);
  const closeAt = toDate(round.recruitCloseAt);
  if (openAt && now.getTime() < openAt.getTime()) return false;
  if (closeAt && now.getTime() >= closeAt.getTime()) return false;
  // 마감을 따로 두지 않았어도, 이미 시작한 차수는 더 받지 않는다.
  if (!closeAt) {
    const start = toDate(round.time);
    if (start && now.getTime() >= start.getTime()) return false;
  }
  return true;
}

// PartyChu는 환불률을 정하거나 권장하지 않는다 — 환불 규정은 전적으로 파티
// 등록/수정 시 호스트가 직접 입력한 refundPolicy 배열([{daysBefore, refundPercent}])을
// 그대로 따른다. 규정이 없거나(호스트 미설정) 해당 시점을 커버하는 구간이 없으면
// 환불 0%로 처리한다(임의로 유리하게/불리하게 추정하지 않음).
//
// 아직 실제 PG 환불 API가 연결되어 있지 않으므로, 여기서는 refundStatus를
// 'pending'으로 저장만 해두고 실제 환불 실행은 이후 PG 연동 시 이 필드를
// 구독/폴링하는 별도 처리로 연결하기 쉬운 구조로 남겨둔다.
//
// ## 환불 상한은 **실제로 받은 돈**이다 (paidAmount)
//
// 환불률은 명목 이용요금(appliedFee)에 적용하지만, 결과 금액은 실제로 결제된
// 금액을 절대 넘지 않는다. 이 상한이 없으면 아래가 전부 사고가 된다.
//
//   · 현장결제 예정으로 한 푼도 내지 않은 신청을 취소  → 참가비 × 환불%가 기록
//   · 예약금 6만원만 낸 20만원짜리 예약을 취소        → 20만원이 환불 대상
//
// paidAmount를 넘기지 않으면(null) 지금까지와 똑같이 동작한다 — 옛 호출부가
// 남아 있어도 금액이 갑자기 달라지지 않게 하기 위한 기본값이다.
function computeRefund(refundPolicy, appliedFee, partyDateTime, { paidAmount = null } = {}) {
  if (!appliedFee || appliedFee <= 0) {
    return { refundPercent: 0, refundAmount: 0, refundStatus: 'not_applicable', matchedTier: null, paidAmount: 0 };
  }
  // 받은 돈이 0원이면 환불할 것 자체가 없다. 'pending'으로 두면 나중에 PG
  // 환불 처리가 이 문서를 집어 들어 내지도 않은 돈을 돌려주려 한다.
  if (paidAmount != null && paidAmount <= 0) {
    return { refundPercent: 0, refundAmount: 0, refundStatus: 'not_applicable', matchedTier: null, paidAmount: 0 };
  }
  if (!Array.isArray(refundPolicy) || refundPolicy.length === 0) {
    return { refundPercent: 0, refundAmount: 0, refundStatus: 'pending', matchedTier: null };
  }
  // Timestamp/Date 어느 쪽이 와도 받는다 — 정기 파티는 저장된 Timestamp가
  // 아니라 계산된 "다음 회차"(Date)가 넘어오기 때문이다.
  const partyDate = toDate(partyDateTime);
  if (!partyDate) {
    return { refundPercent: 0, refundAmount: 0, refundStatus: 'pending', matchedTier: null };
  }

  const daysUntilParty = (partyDate.getTime() - Date.now()) / (1000 * 60 * 60 * 24);

  // daysBefore가 큰(더 관대한) 구간부터 확인해, 남은 일수가 그 구간의
  // daysBefore 이상이면 그 구간을 적용한다("N일 전"부터 적용되는 규정).
  const sorted = [...refundPolicy]
    .filter((t) => typeof t.daysBefore === 'number' && typeof t.refundPercent === 'number')
    .sort((a, b) => b.daysBefore - a.daysBefore);

  let matched = null;
  for (const tier of sorted) {
    if (daysUntilParty >= tier.daysBefore) {
      matched = tier;
      break;
    }
  }

  if (!matched) {
    return { refundPercent: 0, refundAmount: 0, refundStatus: 'pending', matchedTier: null };
  }

  const pct = Math.max(0, Math.min(100, matched.refundPercent));
  // 환불률은 명목 이용요금에 적용하고, 결과는 실결제액으로 자른다.
  // (예: 총액 20만 / 예약금 6만 결제 / 환불 50% → 10만이 아니라 6만이 상한)
  const policyAmount = Math.round((appliedFee * pct) / 100);
  const amount = paidAmount == null ? policyAmount : Math.min(policyAmount, paidAmount);
  return {
    refundPercent: pct,
    refundAmount: amount,
    refundStatus: amount > 0 ? 'pending' : 'not_applicable',
    matchedTier: matched,
    paidAmount: paidAmount == null ? null : paidAmount,
  };
}

// 파티 정원에 참가자 1명 자리를 "예약"한다 — 자격 검증(이미신청/모집상태/
// 마감일/연령제한/성별) + 정원 확인 + 카운터 증가분을 계산해서 돌려준다.
// 호출자는 이미 트랜잭션 안에서 partyRef를 읽어(partyData) 넘겨야 하고,
// 반환된 updateData로 transaction.update(partyRef, updateData)를 직접
// 호출해야 한다(이 함수 자체는 쓰기를 하지 않는 순수 계산 함수).
//
// applyToParty(정상 신청)와 createPendingPackageBooking(패키지 예약의 pending
// 단계 — 결제 전에 미리 자리를 선점) 양쪽에서 동일하게 쓴다.
// 정기 파티의 "회차별" 카운터가 들어가는 자리 —
//   occurrenceStats: { '2026-08-08': { currentParticipants, currentMaleCount,
//                                      currentFemaleCount, applicants: [uid] } }
// 파티 문서 최상단의 currentParticipants/applicants는 회차 구분 없이 누적되는
// 값이라, 정기 파티에서는 "이번 회차에 몇 명 왔는지"를 표현할 수 없다. 그래서
// 회차 id별 칸을 따로 두고 정원 판정도 그 칸을 기준으로 한다(최상단 필드는
// 회차를 모르는 기존 화면/집계를 위해 계속 같이 갱신한다).
function occurrenceStatOf(partyData, occurrenceId) {
  if (!occurrenceId) return null;
  const all = partyData.occurrenceStats;
  const stat = all && typeof all === 'object' ? all[occurrenceId] : null;
  return stat && typeof stat === 'object' ? stat : {};
}

/**
 * 신청 문서 ID.
 *
 * 회차가 없는 신청(일회성 파티·날짜별 문서로 나뉜 여러 날짜 게시글)은 예전
 * 그대로 uid 하나다 — 기존 문서를 옮기지 않고 그대로 읽고 쓸 수 있다.
 * 회차가 있는 정기 파티 신청만 회차까지 합쳐 유일해진다(8/15와 8/22가 각각
 * 별개의 신청 문서가 된다).
 *
 * **이 값을 파싱해서 uid나 occurrenceId를 되찾으려 하면 안 된다.** 이 서비스의
 * uid는 Firebase 자동생성(영숫자)만이 아니라 소셜 로그인 커스텀 토큰
 * (`kakao:123`, `naver:456` — socialAuth.js)도 있어서 구분자가 uid 안에
 * 들어갈 수 있다. 문서 ID는 **유일성 확보에만** 쓰고, uid·occurrenceId는
 * 언제나 문서 안의 필드에서 읽는다.
 *
 * 신청 문서 경로를 만드는 곳은 전부 이 함수를 거친다(applyToParty ·
 * cancelApplication · markPartyDepositSent · 콤보 5곳). 새 경로에서
 * `.doc(uid)`를 직접 쓰면 정기 파티에서 8/15 신청 문서를 8/22가 덮어쓴다.
 */
function applicationDocId(uid, occurrenceId) {
  return occurrenceId ? `${uid}_${occurrenceId}` : uid;
}

/**
 * 이 사람이 **다른 회차**에 아직 살아 있는 신청을 갖고 있는지.
 *
 * 회차 신청을 취소할 때 파티 문서 최상단의 applicants/approvedApplicants/
 * rejectedApplicants까지 지워버리면, 8/15를 취소했을 뿐인데 8/22 신청의 흔적이
 * 함께 사라진다. 그래서 남은 회차가 하나도 없을 때만 최상단 배열을 정리한다.
 */
/**
 * 회차별 **차수 카운터** 칸 — `occurrenceStats.{회차}.rounds`.
 *
 *   occurrenceStats: {
 *     '2026-08-15': {
 *       currentParticipants, currentMaleCount, currentFemaleCount, applicants: [],
 *       rounds: { '1': { currentParticipants, currentMaleCount, currentFemaleCount }, ... }
 *     }
 *   }
 *
 * **인원만 담고 정원·참가비·시간 규칙은 담지 않는다.** 그 정의는 문서 최상단
 * `rounds[]` 하나뿐이라, 호스트가 정원을 고치면 모든 회차에 그대로 반영되고
 * 회차 칸을 다시 쓸 일이 없다(정의를 복사해두면 회차마다 값이 갈라진다).
 *
 * 없으면 **0에서 시작한다** — 최상단 누적 카운터를 새 회차에 복사하면 안 된다.
 * 그 값은 지나간 회차들이 쌓아 올린 수라서, 복사하는 순간 아무도 신청하지 않은
 * 8/22가 이미 만석으로 보인다.
 *
 * 읽기 전용 헬퍼다 — **쓰기는 reserve/releaseApplicantSlot만 한다**(파일 상단
 * '정원 카운터의 소유권' 참고). 앱도 같은 규칙으로 읽기만 한다
 * (lib/models/party_round_offer.dart의 occurrenceRoundsOf).
 */
function occurrenceRoundsOf(partyData, occurrenceId) {
  const stat = occurrenceStatOf(partyData, occurrenceId);
  const rounds = stat && stat.rounds;
  return rounds && typeof rounds === 'object' ? rounds : {};
}

/** 회차 칸에서 차수 하나의 카운터를 읽는다(없으면 전부 0). */
function occurrenceRoundCounter(occRounds, roundNumber) {
  const cur = occRounds[String(roundNumber)];
  const src = cur && typeof cur === 'object' ? cur : {};
  return {
    currentParticipants: Number(src.currentParticipants || 0),
    currentMaleCount: Number(src.currentMaleCount || 0),
    currentFemaleCount: Number(src.currentFemaleCount || 0),
  };
}

/**
 * 이 신청의 차수 카운터가 **어디에** 기록됐는지.
 *
 * 회차별 차수 카운터를 도입하기 전에 만들어진 정기 파티 신청은 occurrenceId를
 * 갖고 있으면서도 차수 인원은 최상단 `rounds[]`에 올려뒀다. 취소할 때 어느 쪽을
 * 되돌려야 하는지는 **신청 문서에 남긴 이 표시**로만 정확히 알 수 있다 —
 * 회차 칸의 존재 여부로 추측하면, 다른 사람이 그 회차에 새로 신청해 칸이 생긴
 * 순간 옛 신청의 취소가 남의 자리를 반납해버린다.
 */
const ROUND_SCOPE_OCCURRENCE = 'occurrence';

function hasOtherOccurrenceApplication(partyData, uid, occurrenceId) {
  if (!occurrenceId) return false;
  const all = partyData.occurrenceStats;
  if (!all || typeof all !== 'object') return false;
  return Object.keys(all).some((id) => {
    if (id === occurrenceId) return false;
    const stat = all[id];
    const list = stat && Array.isArray(stat.applicants) ? stat.applicants : [];
    return list.includes(uid);
  });
}

function reserveApplicantSlot(
  partyData,
  { uid, gender, birthYear, selectedRounds, packageId, occurrence, occurrenceId }
) {
  const data = partyData;
  // 회차가 지정된 정기 파티는 정원·신청자 판정을 그 회차 칸으로 옮긴다.
  const occStat = occurrenceStatOf(data, occurrenceId);
  // 정원 판정에 쓸 현재값 — 회차가 있으면 회차 칸, 없으면 기존처럼 문서 최상단.
  const currentOf = (field) =>
    Number((occStat ? occStat[field] : data[field]) || 0);
  const occPath = occurrenceId ? `occurrenceStats.${occurrenceId}` : null;
  const hasMultipleRounds = data.hasMultipleRounds === true;
  const roundCapacityMode = data.roundCapacityMode || 'unified';
  let roundsArr = null;
  // 시간 판정·참가비 계산 전용 사본(회차 날짜로 옮긴 것). 정원 카운터를
  // 올려 문서에 다시 쓰는 것은 언제나 원본 roundsArr다 — rebaseRounds 주석 참고.
  let timedRounds = null;
  let effectiveSelectedRounds = null;
  // 패키지 신청이면 여기에 확정된 패키지가 담긴다(신청 문서에 기록한다).
  let appliedPackage = null;
  if (hasMultipleRounds) {
    roundsArr = Array.isArray(data.rounds) ? data.rounds : [];
    timedRounds = rebaseRounds(roundsArr, roundScheduleBaseOf(data, occurrence));

    // ── 패키지 신청 ────────────────────────────────────────────────────
    // 클라이언트가 보낸 차수 목록은 신뢰하지 않는다 — 패키지 id로 문서에
    // 저장된 정의를 찾아 **그 정의의 포함 차수**로 갈아끼운다. 그래야 조작된
    // 요청이 "패키지 가격으로 차수 3개"를 신청하는 일이 생기지 않는다.
    if (packageId) {
      if (roundCapacityMode !== 'perRound') {
        // 통합 정원 모드는 차수별 정원 카운터가 없어 "각 차수 1명씩"을 지킬
        // 수 없다 — 등록 화면도 같은 조건에서만 패키지를 만들 수 있다.
        throw new HttpsError(
          'failed-precondition',
          '이 파티는 차수 패키지를 사용할 수 없습니다.'
        );
      }
      appliedPackage = findRoundPackage(data, packageId);
      if (!appliedPackage) {
        throw new HttpsError('invalid-argument', '존재하지 않는 패키지입니다.');
      }
      const missing = appliedPackage.roundNumbers.filter(
        (n) => !roundsArr.some((r) => r.roundNumber === n)
      );
      if (missing.length > 0) {
        throw new HttpsError(
          'failed-precondition',
          '패키지에 포함된 차수가 변경되어 신청할 수 없습니다.'
        );
      }
    }

    const validRoundNumbers = new Set(roundsArr.map((r) => r.roundNumber));
    const requested = appliedPackage
      ? appliedPackage.roundNumbers
      : Array.isArray(selectedRounds) && selectedRounds.length > 0
        ? selectedRounds
        : [1]; // 방어적 기본값 — UI는 항상 선택값을 보내야 함
    const invalid = requested.filter((n) => !validRoundNumbers.has(n));
    if (invalid.length > 0) {
      throw new HttpsError('invalid-argument', '존재하지 않는 라운드가 포함되어 있습니다.');
    }
    effectiveSelectedRounds = [...new Set(requested)].sort((a, b) => a - b);

    // 차수마다 모집 시작/마감이 따로 있다 — 창구가 닫힌 차수는 여기서 막는다.
    // 클라이언트 UI가 이미 막지만, 조작된 요청도 통과하면 안 된다.
    const nowForRounds = new Date();
    const blocked = effectiveSelectedRounds
      .map((rn) => timedRounds.find((r) => r.roundNumber === rn))
      .filter((r) => r && !isRoundRecruitOpen(r, nowForRounds));
    if (blocked.length > 0) {
      const names = blocked
        .map((r) => r.label || `${r.roundNumber}차`)
        .join(', ');
      throw new HttpsError(
        'failed-precondition',
        `${names}는 지금 신청받지 않습니다.`
      );
    }
  }

  // 정기 파티에서 사용자가 특정 회차를 골라 신청했다면 **그 회차** 기준으로
  // 얼리버드를 판정한다(다음 주 회차를 미리 신청하는 게 정상 흐름).
  // 패키지는 개별 차수 합산이 아니라 **저장된 판매가 하나**로 계산한다.
  const appliedFee = appliedPackage
    ? computePackageFee(appliedPackage, timedRounds, gender)
    : hasMultipleRounds && roundCapacityMode === 'perRound'
      ? computeAppliedFeeForRounds(
          timedRounds,
          effectiveSelectedRounds,
          gender,
          new Date(),
          // 차수에 참가비·얼리버드가 없는 옛 문서는 문서 최상단 값으로 폴백한다.
          data
        )
      : computeAppliedFee(data, gender, new Date(), occurrence || null);

  // ── 중복 신청 차단 ────────────────────────────────────────────────────
  //
  // 판정 단위는 **신청 단위와 같아야 한다**.
  //  · 회차 신청(정기 파티): 그 회차 명단만 본다 — 8/15에 신청했어도 8/22는
  //    다시 신청할 수 있고, 8/15를 두 번 신청하는 것만 막힌다.
  //  · 회차가 없는 신청(일회성·날짜별 문서): 예전 그대로 문서 최상단 명단.
  //
  // 한 신청 안에서 "1차를 개별 신청한 뒤 1+2차 패키지를 또 신청"하는 겹침은
  // 신청 문서가 (uid, occurrenceId)당 하나뿐이라 여전히 만들어지지 않는다.
  //
  // 회차 개념이 없던 시절의 옛 신청(occurrenceId 없이 최상단 명단에만 있는
  // 건)은 어느 회차의 것인지 알 수 없으므로 새 회차 신청을 막지 않는다 —
  // 문서 ID도 서로 겹치지 않는다(applicationDocId 참고).
  const appliedList = occurrenceId
    ? (occStat && Array.isArray(occStat.applicants) ? occStat.applicants : [])
    : (data.applicants || []);
  if (appliedList.includes(uid)) {
    throw new HttpsError('already-exists', '이미신청');
  }

  // 오픈예정 파티는 신청·예약·결제를 받지 않는다. 필드가 없던 기존 파티는
  // 'open'으로 간주되므로 그대로 통과한다(partyOpenState.js 참고).
  if (data.openState === 'preopen') {
    throw new HttpsError('failed-precondition', '아직 오픈 전인 파티입니다.');
  }

  // 모집 상태 — 정기 파티는 **회차마다** 따로 닫을 수 있다
  // (partyOccurrenceRecruit.js). 회차 칸이 없거나 회차를 모르는 신청(일회성·
  // 날짜 슬롯 파티)은 문서의 recruitStatus로 폴백하므로 판정이 예전과 같다.
  //
  // 여기서 막는 것은 **그 회차**뿐이다 — 9/6이 마감이어도 9/13 신청은 그대로
  // 통과해야 한다(반복 파티가 통째로 닫히면 안 된다).
  if (occurrenceStatusOf(data, occurrenceId) !== '모집중') {
    throw new HttpsError('failed-precondition', '마감');
  }

  // 성별별 모집 마감 — '남성 모집마감 + 여성 모집중'이면 남성만 여기서 막히고
  // 여성은 그대로 통과한다. 이 검사가 서버의 유일한 강제 지점이므로, 콜러블을
  // 직접 불러도 여기서 막힌다(클라이언트 UI는 헛걸음을 줄일 뿐이다).
  //
  // 이것도 **회차 기준**이다 — 회차 칸이 없으면 문서 최상단 값을 그대로 본다.
  //
  // gender는 호출부가 users 문서(본인확인 정본)에서 읽어 넘긴 값이라
  // 클라이언트가 고를 수 없다. 성별을 모르는 신청자는 남녀 양쪽이 다 닫힌
  // 파티에서만 걸린다 — 한쪽만 닫힌 파티를 성별 미상이라는 이유로 막으면
  // 성별 인증 없이도 신청되던 기존 남녀무관 파티의 동작이 바뀐다.
  if (isGenderRecruitClosedAt(data, gender, occurrenceId)) {
    throw new HttpsError(
      'failed-precondition',
      genderRecruitClosedMessage(data, gender)
    );
  }

  if (data.recruitDeadlineAt && data.recruitDeadlineAt.toDate() < new Date()) {
    throw new HttpsError('failed-precondition', '마감');
  }

  // 모집 시작 시각이 아직 오지 않았으면 신청을 받지 않는다. 이 필드가 없던
  // 예전 문서는 "제한 없음"이라 그대로 통과한다.
  const recruitOpenAt = toDate(data.recruitOpenAt);
  if (recruitOpenAt && recruitOpenAt.getTime() > Date.now()) {
    throw new HttpsError('failed-precondition', '아직 모집 시작 전입니다.');
  }

  // 정기 파티(scheduleType: 'recurring')는 회차마다 마감이 새로 열리기 때문에
  // 고정 recruitDeadlineAt을 저장하지 않는다(저장하면 첫 회차 마감 이후 모든
  // 회차의 신청이 영구히 막힌다). 대신 지금 시점의 "다음 회차"를 서버에서
  // 직접 계산해 그 회차의 마감을 강제한다 — 클라이언트 UI가 버튼을 열어놨든
  // 조작된 요청이 들어오든 여기서 최종 차단된다.
  if (isRecurringParty(data)) {
    const now = new Date();
    // 최소 인원 미달로 자동 취소된 회차는 더 받지 않는다. 파티 문서 전체는
    // '모집중' 그대로라(다른 날짜 회차는 열려 있다) 위 검사에 걸리지 않는다.
    if (isOccurrenceCancelled(data, occurrenceId)) {
      throw new HttpsError(
        'failed-precondition',
        '최소 모집 인원 미달로 취소된 회차입니다. 다른 날짜를 골라주세요.'
      );
    }
    if (occurrence) {
      // 참가 회차를 직접 고른 신청 — "다음 회차"가 아니라 **그 회차**의
      // 시작/마감으로 판정한다(다음 주 회차를 미리 신청하는 게 정상 흐름).
      if (occurrence.start.getTime() <= now.getTime()) {
        throw new HttpsError('failed-precondition', '마감');
      }
      if (occurrence.deadline && occurrence.deadline.getTime() < now.getTime()) {
        throw new HttpsError('failed-precondition', '마감');
      }
      if (
        occurrence.recruitOpenAt &&
        occurrence.recruitOpenAt.getTime() > now.getTime()
      ) {
        throw new HttpsError('failed-precondition', '아직 모집 시작 전입니다.');
      }
    } else {
      const recruit = checkRecurringRecruitOpen(data, now);
      if (!recruit.open) {
        throw new HttpsError(
          'failed-precondition',
          recruit.reason === 'notYet' ? '아직 모집 시작 전입니다.' : '마감'
        );
      }
      // 회차를 안 보낸 옛 클라이언트는 "지금 기준 다음 회차"에 신청하는
      // 것이다 — 그 회차가 취소됐으면 여기서도 막아야 한다(위 취소 검사는
      // occurrenceId가 있을 때만 걸린다).
      if (
        recruit.occurrence &&
        isOccurrenceCancelled(data, occurrenceIdOf(recruit.occurrence.start))
      ) {
        throw new HttpsError(
          'failed-precondition',
          '최소 모집 인원 미달로 취소된 회차입니다. 다른 날짜를 골라주세요.'
        );
      }
    }
  }

  // ── 연령 제한 ────────────────────────────────────────────────────────
  // 연령 제한은 **성별별**이다(partyAgeRestriction.js) — 신청자는 자기 성별의
  // 범위만 통과하면 된다. gender/birthYear는 호출부가 users 문서(본인확인
  // 정본)에서 읽어 넘긴 값이라 클라이언트가 고를 수 없다. 이 검사가 서버의
  // 유일한 강제 지점이므로, 콜러블을 직접 불러도 여기서 막힌다.
  //
  // 성별 필드가 없는 기존 파티는 옛 공통 범위를 남녀 모두에게 적용한다 —
  // 그쪽 판정은 예전과 완전히 같다.
  const myAgeLimit = ageEffectiveLimitFor(parseAgeRestriction(data), gender);
  if (myAgeLimit === null) {
    // 성별별 제한이 걸린 파티인데 신청자 성별을 모른다 — 판정 불가.
    throw new HttpsError('failed-precondition', '미인증');
  }
  if (myAgeLimit.enabled) {
    if (birthYear == null) throw new HttpsError('failed-precondition', '연령미인증');
    if (!ageLimitAllows(myAgeLimit, birthYear)) {
      throw new HttpsError('failed-precondition', '연령제한');
    }
  }

  const genderCapacityMode = data.genderCapacityMode || 'unlimited';
  let updateData;

  if (hasMultipleRounds && roundCapacityMode === 'perRound') {
    // 차수별 정원 모드는 성별 정원 모드에 따라 판정 기준이 다르다.
    //  · separate(남녀별)  : 차수의 maleCapacity/femaleCapacity를 본다(기존 그대로).
    //  · unlimited(남녀무관): 성별을 보지 않고 차수의 maxCapacity만 본다.
    // 예전에는 unlimited에서도 남녀 정원을 봤는데, 그 모드는 차수에
    // maleCapacity/femaleCapacity를 0으로 저장하므로 **아무도 신청할 수 없었다**.
    const roundGenderSeparate = genderCapacityMode === 'separate';

    // 성별 인증은 남녀별 정원 모드에서만 필요하다(차수마다 남녀 정원이
    // 따로 있으므로). 남녀무관 모드는 성별과 무관하게 받는다.
    if (roundGenderSeparate && gender !== 'male' && gender !== 'female') {
      throw new HttpsError('failed-precondition', '미인증');
    }

    // Firestore 배열은 원소 하나만 원자적으로 증가시킬 수 없어서, 배열
    // 전체를 읽어(이미 트랜잭션에서 읽은 data.rounds) 메모리에서 선택된
    // 라운드들만 수정한 뒤 배열 통째로 다시 쓴다.
    const updatedRounds = roundsArr.map((r) => ({ ...r }));

    // 정기 파티는 **차수 정원도 회차별**이다 — 8/15 1차에 신청한 사람이
    // 8/22 1차 자리를 잡아먹으면 안 된다. 정원·참가비 정의는 최상단
    // rounds[]에서 읽고, 인원만 이 회차 칸에서 읽고 쓴다.
    const occRounds = occurrenceId
      ? { ...occurrenceRoundsOf(data, occurrenceId) }
      : null;
    // 판정에 쓸 "지금 이 차수의 인원" — 회차 신청이면 회차 칸, 아니면 최상단.
    const roundCountsOf = (round) =>
      occRounds
        ? occurrenceRoundCounter(occRounds, round.roundNumber)
        : {
            currentParticipants: roundCurrentOf(round),
            currentMaleCount: Number(round.currentMaleCount || 0),
            currentFemaleCount: Number(round.currentFemaleCount || 0),
          };

    // 1단계: 선택한 라운드 전부에 자리가 있는지 먼저 검증 — 하나라도
    // 마감이면 여기서 throw해 트랜잭션 전체를 취소한다(부분 신청 방지).
    for (const rn of effectiveSelectedRounds) {
      const round = updatedRounds.find((r) => r.roundNumber === rn);
      const counts = roundCountsOf(round);
      if (roundGenderSeparate) {
        const maleCapacity = Number(round.maleCapacity || 0);
        const femaleCapacity = Number(round.femaleCapacity || 0);
        if (gender === 'male' && counts.currentMaleCount >= maleCapacity) {
          throw new HttpsError('failed-precondition', '마감');
        }
        if (gender === 'female' && counts.currentFemaleCount >= femaleCapacity) {
          throw new HttpsError('failed-precondition', '마감');
        }
      } else {
        // 남녀무관 — 그 차수의 전체 인원만 본다. 최상단 unlimited 분기와
        // 같은 규칙으로, 정원이 0이면 "제한 없음"으로 본다.
        const max = roundMaxCapacityOf(round);
        if (max > 0 && counts.currentParticipants >= max) {
          throw new HttpsError('failed-precondition', '마감');
        }
      }
    }

    // 2단계: 검증을 통과했으니 선택한 라운드들의 카운터를 실제로 증가.
    for (const rn of effectiveSelectedRounds) {
      const round = updatedRounds.find((r) => r.roundNumber === rn);
      // 남녀 카운터를 건드리기 **전에** 현재 인원을 읽어둔다 — 예전 문서는
      // currentParticipants가 없어 남녀 합계로 폴백되므로, 먼저 증가시키면
      // 그 폴백값이 같이 올라가 2가 더해진다.
      const before = roundCountsOf(round);
      const next = {
        currentMaleCount:
          before.currentMaleCount + (gender === 'male' ? 1 : 0),
        currentFemaleCount:
          before.currentFemaleCount + (gender === 'female' ? 1 : 0),
      };
      next.currentParticipants = roundGenderSeparate
        ? next.currentMaleCount + next.currentFemaleCount
        // 성별을 모를 수 있으므로 남녀 합계로 되계산하면 안 된다 —
        // 전체 인원을 직접 +1 한다(releaseApplicantSlot이 똑같이 -1 한다).
        : before.currentParticipants + 1;

      if (occRounds) {
        occRounds[String(rn)] = next;
      } else {
        round.currentMaleCount = next.currentMaleCount;
        round.currentFemaleCount = next.currentFemaleCount;
        round.currentParticipants = next.currentParticipants;
      }
    }

    const aggMax = updatedRounds.reduce((s, r) => s + roundMaxCapacityOf(r), 0);

    if (occRounds) {
      // 회차 신청 — 최상단 rounds[]와 카운터는 **손대지 않는다**. 8/15 신청이
      // 8/22 차수 정원에 영향을 주던 통로가 여기였다.
      const occAgg = Object.values(occRounds).reduce(
        (s, r) => s + Number((r && r.currentParticipants) || 0),
        0,
      );
      updateData = {
        applicants: admin.firestore.FieldValue.arrayUnion(uid),
        [`${occPath}.applicants`]: admin.firestore.FieldValue.arrayUnion(uid),
        [`${occPath}.rounds`]: occRounds,
        [`${occPath}.currentParticipants`]: occAgg,
      };
    } else {
      // 라운드를 모르는 기존 코드(피드 카드 등)를 위해 상단 정원 필드는
      // 라운드 전체 합계로 갱신한다.
      const aggCurrent = updatedRounds.reduce(
        (s, r) => s + Number(r.currentParticipants || 0),
        0,
      );
      updateData = {
        rounds: updatedRounds,
        applicants: admin.firestore.FieldValue.arrayUnion(uid),
        maxParticipants: aggMax,
        maxCapacity: aggMax,
        currentParticipants: aggCurrent,
        people: `${aggCurrent}/${aggMax}명`,
      };
    }
  } else if (genderCapacityMode === 'unlimited') {
    const current = currentOf('currentParticipants');
    const max = Number(data.maxParticipants || data.maxCapacity || 0);
    const genderLimit = data.genderLimit || 'all';
    const currentMale = currentOf('currentMaleCount');
    const currentFemale = currentOf('currentFemaleCount');

    if (genderLimit === 'male' || genderLimit === 'female') {
      if (gender !== 'male' && gender !== 'female') {
        throw new HttpsError('failed-precondition', '미인증');
      }
      if (genderLimit !== gender) {
        throw new HttpsError('failed-precondition', '성별제한');
      }
    }

    if (max > 0 && current >= max) throw new HttpsError('failed-precondition', '마감');

    const newCount = current + 1;
    // 회차 신청은 **회차 칸이 정본**이다 — 최상단 스칼라 카운터를 특정 회차
    // 값으로 덮어쓰면, 목록·상세가 "마지막으로 건드린 회차의 인원"을 이 파티
    // 전체의 인원인 것처럼 보여주게 된다(정기 파티는 회차마다 인원이 따로다).
    // 최상단 applicants 배열만 "이 파티에 살아 있는 신청이 있는 사람" 집합으로
    // 계속 유지한다 — 파티 수정·삭제 차단 판정이 이 배열을 본다.
    updateData = { applicants: admin.firestore.FieldValue.arrayUnion(uid) };
    if (occPath) {
      updateData[`${occPath}.currentParticipants`] = newCount;
      updateData[`${occPath}.applicants`] =
        admin.firestore.FieldValue.arrayUnion(uid);
      if (genderLimit === 'male') {
        updateData[`${occPath}.currentMaleCount`] = currentMale + 1;
      }
      if (genderLimit === 'female') {
        updateData[`${occPath}.currentFemaleCount`] = currentFemale + 1;
      }
    } else {
      updateData.currentParticipants = newCount;
      updateData.people = `${newCount}/${max}명`;
      if (genderLimit === 'male') updateData.currentMaleCount = currentMale + 1;
      if (genderLimit === 'female') updateData.currentFemaleCount = currentFemale + 1;
    }
  } else {
    // 남녀별 정원 모드
    if (gender !== 'male' && gender !== 'female') {
      throw new HttpsError('failed-precondition', '미인증');
    }

    const maleCapacity = Number(data.maleCapacity || 0);
    const femaleCapacity = Number(data.femaleCapacity || 0);
    const currentMale = currentOf('currentMaleCount');
    const currentFemale = currentOf('currentFemaleCount');

    if (gender === 'male' && currentMale >= maleCapacity) {
      throw new HttpsError('failed-precondition', '마감');
    }
    if (gender === 'female' && currentFemale >= femaleCapacity) {
      throw new HttpsError('failed-precondition', '마감');
    }

    const newMale = gender === 'male' ? currentMale + 1 : currentMale;
    const newFemale = gender === 'female' ? currentFemale + 1 : currentFemale;
    const newTotal = newMale + newFemale;
    // 위 unlimited 분기와 같은 이유 — 회차 신청은 회차 칸만 갱신한다.
    updateData = { applicants: admin.firestore.FieldValue.arrayUnion(uid) };
    if (occPath) {
      updateData[`${occPath}.currentParticipants`] = newTotal;
      updateData[`${occPath}.currentMaleCount`] = newMale;
      updateData[`${occPath}.currentFemaleCount`] = newFemale;
      updateData[`${occPath}.applicants`] =
        admin.firestore.FieldValue.arrayUnion(uid);
    } else {
      updateData.currentParticipants = newTotal;
      updateData.people = `${newTotal}/${maleCapacity + femaleCapacity}명`;
      if (gender === 'male') updateData.currentMaleCount = newMale;
      if (gender === 'female') updateData.currentFemaleCount = newFemale;
    }
  }

  return {
    updateData,
    appliedFee,
    effectiveSelectedRounds,
    appliedPackage,
    // 차수 인원을 회차 칸에 기록했는지 — 신청 문서에 그대로 남겨야 취소가
    // 같은 칸을 되돌린다(ROUND_SCOPE_OCCURRENCE 주석 참고).
    roundCounterScope:
      occurrenceId && hasMultipleRounds && roundCapacityMode === 'perRound'
        ? ROUND_SCOPE_OCCURRENCE
        : null,
  };
}

// reserveApplicantSlot의 역연산 — 정원 카운터를 되돌린다. 호출자가
// transaction.update(partyRef, updateData)를 직접 호출해야 한다(순수 계산
// 함수). cancelApplication(정상 취소)과 createPendingPackageBooking의 pending
// 홀드가 결제 전에 만료/취소될 때(expireStalePackageBookings, 결제 취소) 양쪽에서
// 동일하게 쓴다.
function releaseApplicantSlot(
  partyData,
  { uid, gender, selectedRounds, occurrenceId, roundCounterScope },
) {
  const genderCapacityMode = partyData.genderCapacityMode || 'unlimited';
  const updateData = {};
  // 신청 때 어느 회차 칸을 늘렸는지는 신청 문서(occurrenceId)에 남아 있다 —
  // 그 칸을 그대로 되돌린다(회차를 모르는 예전 신청은 최상단 필드만 되돌림).
  const occStat = occurrenceStatOf(partyData, occurrenceId);
  const occPath = occurrenceId ? `occurrenceStats.${occurrenceId}` : null;
  if (occPath) {
    updateData[`${occPath}.applicants`] =
      admin.firestore.FieldValue.arrayRemove(uid);
  }
  // 최상단 명단은 "이 파티에 살아 있는 신청이 하나라도 있는 사람" 집합이다 —
  // **다른 회차 신청이 남아 있으면 건드리지 않는다.** 8/15를 취소했을 뿐인데
  // 8/22 신청까지 명단에서 사라지면, 파티 수정 차단·신청자 수·승인 상태가 한꺼번에
  // 틀어진다(회차별 신청의 핵심 격리 지점이다).
  if (!hasOtherOccurrenceApplication(partyData, uid, occurrenceId)) {
    updateData.applicants = admin.firestore.FieldValue.arrayRemove(uid);
    // approvedApplicants/rejectedApplicants는 승인 상태의 정본이 아니라
    // 레거시 배열이다(정본은 신청 문서의 status) — 남아 있던 값만 정리한다.
    updateData.approvedApplicants = admin.firestore.FieldValue.arrayRemove(uid);
    updateData.rejectedApplicants = admin.firestore.FieldValue.arrayRemove(uid);
  }
  const occCurrentOf = (field) => Math.max(0, Number((occStat || {})[field] || 0) - 1);

  const hasMultipleRounds = partyData.hasMultipleRounds === true;
  const roundCapacityMode = partyData.roundCapacityMode || 'unified';

  if (hasMultipleRounds && roundCapacityMode === 'perRound') {
    // reserveApplicantSlot의 라운드별 증가 로직을 그대로 역산한다.
    // 증가 방식이 성별 정원 모드에 따라 다르므로(남녀무관은 전체 인원을
    // 직접 +1) 감소도 같은 기준으로 나눠야 카운터가 어긋나지 않는다.
    const roundGenderSeparate = genderCapacityMode === 'separate';
    const roundsArr = Array.isArray(partyData.rounds) ? partyData.rounds : [];
    const updatedRounds = roundsArr.map((r) => ({ ...r }));
    const selected = Array.isArray(selectedRounds) ? selectedRounds : [];

    // 어느 쪽 카운터를 되돌릴지는 **신청 문서에 남긴 표시**로 정한다.
    // 회차별 차수 카운터를 도입하기 전의 정기 파티 신청은 occurrenceId를
    // 가지고 있으면서도 인원은 최상단 rounds[]에 올려뒀다 — 회차 칸의 존재
    // 여부로 추측하면, 그 회차에 새로 신청한 사람 때문에 칸이 생긴 순간
    // 옛 신청의 취소가 **남의 자리**를 반납해버린다.
    const useOccurrenceRounds =
      !!occPath && roundCounterScope === ROUND_SCOPE_OCCURRENCE;
    const occRounds = useOccurrenceRounds
      ? { ...occurrenceRoundsOf(partyData, occurrenceId) }
      : null;

    for (const rn of selected) {
      const round = updatedRounds.find((r) => r.roundNumber === rn);
      if (!round) continue; // 신청 이후 라운드가 사라진 경우(발생하지 않아야 함) 대비
      const before = occRounds
        ? occurrenceRoundCounter(occRounds, rn)
        : {
            currentParticipants: roundCurrentOf(round),
            currentMaleCount: Number(round.currentMaleCount || 0),
            currentFemaleCount: Number(round.currentFemaleCount || 0),
          };
      const next = {
        currentMaleCount: Math.max(
          0,
          before.currentMaleCount - (gender === 'male' ? 1 : 0),
        ),
        currentFemaleCount: Math.max(
          0,
          before.currentFemaleCount - (gender === 'female' ? 1 : 0),
        ),
      };
      next.currentParticipants = roundGenderSeparate
        ? next.currentMaleCount + next.currentFemaleCount
        : Math.max(0, before.currentParticipants - 1);

      if (occRounds) {
        occRounds[String(rn)] = next;
      } else {
        round.currentMaleCount = next.currentMaleCount;
        round.currentFemaleCount = next.currentFemaleCount;
        round.currentParticipants = next.currentParticipants;
      }
    }

    if (occRounds) {
      // 회차 신청 — 그 회차의 차수 칸만 되돌린다. 최상단 rounds[]는 다른
      // 회차(그리고 옛 신청)의 인원이 들어 있는 값이라 건드리면 안 된다.
      const occAgg = Object.values(occRounds).reduce(
        (s, r) => s + Number((r && r.currentParticipants) || 0),
        0,
      );
      updateData[`${occPath}.rounds`] = occRounds;
      updateData[`${occPath}.currentParticipants`] = occAgg;
    } else {
      const aggMax = updatedRounds.reduce((s, r) => s + roundMaxCapacityOf(r), 0);
      const aggCurrent = updatedRounds.reduce(
        (s, r) => s + Number(r.currentParticipants || 0),
        0,
      );
      updateData.rounds = updatedRounds;
      updateData.maxParticipants = aggMax;
      updateData.maxCapacity = aggMax;
      updateData.currentParticipants = aggCurrent;
      updateData.people = `${aggCurrent}/${aggMax}명`;
      // 옛 회차 신청(최상단 누적)이라도 회차 인원 집계는 되돌려둔다.
      if (occPath) {
        updateData[`${occPath}.currentParticipants`] =
          occCurrentOf('currentParticipants');
      }
    }
  } else if (genderCapacityMode === 'unlimited') {
    const genderLimit = partyData.genderLimit || 'all';
    // 회차 신청이면 회차 칸만 되돌린다 — reserve가 최상단 스칼라를 건드리지
    // 않았으므로 여기서 줄이면 있지도 않은 인원을 빼는 셈이 된다.
    if (occPath) {
      updateData[`${occPath}.currentParticipants`] =
        occCurrentOf('currentParticipants');
      if (genderLimit === 'male') {
        updateData[`${occPath}.currentMaleCount`] = occCurrentOf('currentMaleCount');
      }
      if (genderLimit === 'female') {
        updateData[`${occPath}.currentFemaleCount`] = occCurrentOf('currentFemaleCount');
      }
    } else {
      const current = Math.max(0, Number(partyData.currentParticipants || 0) - 1);
      const max = Number(partyData.maxParticipants || partyData.maxCapacity || 0);
      updateData.currentParticipants = current;
      updateData.people = `${current}/${max}명`;
      if (genderLimit === 'male') {
        updateData.currentMaleCount = Math.max(0, Number(partyData.currentMaleCount || 0) - 1);
      }
      if (genderLimit === 'female') {
        updateData.currentFemaleCount =
          Math.max(0, Number(partyData.currentFemaleCount || 0) - 1);
      }
    }
  } else {
    const maleCapacity = Number(partyData.maleCapacity || 0);
    const femaleCapacity = Number(partyData.femaleCapacity || 0);
    let currentMale = Number(partyData.currentMaleCount || 0);
    let currentFemale = Number(partyData.currentFemaleCount || 0);
    if (gender === 'male') currentMale = Math.max(0, currentMale - 1);
    if (gender === 'female') currentFemale = Math.max(0, currentFemale - 1);
    const newTotal = currentMale + currentFemale;
    // 위 unlimited 분기와 같은 이유 — 회차 신청은 회차 칸만 되돌린다.
    if (occPath) {
      const occMale =
        gender === 'male'
          ? occCurrentOf('currentMaleCount')
          : Number((occStat || {}).currentMaleCount || 0);
      const occFemale =
        gender === 'female'
          ? occCurrentOf('currentFemaleCount')
          : Number((occStat || {}).currentFemaleCount || 0);
      updateData[`${occPath}.currentMaleCount`] = occMale;
      updateData[`${occPath}.currentFemaleCount`] = occFemale;
      updateData[`${occPath}.currentParticipants`] = occMale + occFemale;
    } else {
      updateData.currentMaleCount = currentMale;
      updateData.currentFemaleCount = currentFemale;
      updateData.currentParticipants = newTotal;
      updateData.people = `${newTotal}/${maleCapacity + femaleCapacity}명`;
    }
  }

  return updateData;
}


// ── 환불 규정 스냅샷 ───────────────────────────────────────────────────
//
// 신청/예약이 만들어진 시점의 환불 규정을 그 문서에 그대로 박아둔다.
// 이게 없으면 취소 시점에 파티 문서의 **현재** refundPolicy를 읽게 되어,
// 호스트가 나중에 규정을 바꾸면 이미 신청을 마친 사람의 환불 조건까지
// 소급해서 바뀐다 — 참가자가 신청 전에 확인하고 동의한 조건과 달라진다.
// 금액 스냅샷(appliedFee/amounts)이 이미 같은 이유로 저장되고 있고,
// 이 값은 그 짝이다.
//
// 규정이 없거나(호스트 미설정) 형식이 깨진 항목은 걸러 **빈 배열**로
// 저장한다. null이 아니라 빈 배열인 것이 중요하다 — "스냅샷은 있고 내용이
// 없음"(환불 0%)과 "스냅샷 자체가 없는 옛 문서"(폴백 대상)를 구분하는
// 유일한 표식이기 때문이다.
function snapshotRefundPolicy(partyData) {
  const raw = partyData && partyData.refundPolicy;
  if (!Array.isArray(raw)) return [];
  return raw
    .filter(
      (t) =>
        t &&
        typeof t.daysBefore === 'number' &&
        typeof t.refundPercent === 'number',
    )
    .map((t) => ({ daysBefore: t.daysBefore, refundPercent: t.refundPercent }));
}

// 취소 시점에 어떤 규정을 적용할지 고른다.
//   · 신청/예약 문서에 스냅샷 배열이 있으면 **무조건 그것**을 쓴다
//     (호스트가 그 뒤에 규정을 바꿨어도 이미 접수된 건은 영향받지 않는다).
//   · 배열이 아예 없으면 스냅샷 도입 **전에** 만들어진 문서다 — 그때는
//     예전과 똑같이 파티의 현재 규정으로 폴백한다(마이그레이션 없이 호환).
function effectiveRefundPolicy(docData, partyData) {
  const snap = docData && docData.refundPolicy;
  if (Array.isArray(snap)) return snap;
  return (partyData && partyData.refundPolicy) || null;
}

module.exports = {
  resolveBaseFee,
  computeAppliedFee,
  computeAppliedFeeForRounds,
  computePackageFee,
  findRoundPackage,
  computeRefund,
  snapshotRefundPolicy,
  effectiveRefundPolicy,
  reserveApplicantSlot,
  releaseApplicantSlot,
  applicationDocId,
  occurrenceStatOf,
  occurrenceRoundsOf,
  ROUND_SCOPE_OCCURRENCE,
};

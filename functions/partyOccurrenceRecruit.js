// ── 정기 파티의 회차별 모집 상태 ──────────────────────────────────────────────
//
// 이 파일은 party_app/lib/models/party_occurrence_recruit.dart의 **거울**이다.
// 한쪽만 고치면 앱이 보여주는 상태와 서버가 실제로 허용하는 신청이 어긋난다.
//
// ── 왜 필요한가 ─────────────────────────────────────────────────────────────
//
// 날짜 슬롯 게시글은 날짜 1개 = parties 문서 1개라 recruitStatus/
// genderRecruitStatus가 이미 날짜마다 따로다. 그런데 **정기 파티**
// (scheduleType: 'recurring')는 문서 하나가 모든 회차를 담아서, 그 두 필드는
// 문서에 한 벌뿐이다 — 9/6만 마감하려 해도 8/30·9/13까지 닫혔다.
//
// ── 저장 형태 ───────────────────────────────────────────────────────────────
//
//   occurrenceRecruit: {
//     'YYYY-MM-DD': {
//       status: '모집중' | '마감' | '취소',
//       genderRecruitStatus: { male: 'open'|'closed', female: 'open'|'closed' },
//     },
//   }
//
// 회차 칸이 없으면(또는 회차를 모르면) **문서 최상단 값으로 폴백**한다. 그래서
// 이 기능 이전에 만들어진 파티와 일회성·날짜 슬롯 파티는 판정이 예전과 완전히
// 같다 — 마이그레이션이 없다.
//
// 두 키는 서로를 건드리지 않는다. 전체 상태를 '마감'으로 바꿔도 그 회차의 남/여
// 값은 남아 있고, 다시 '모집중'이 되면 그 값이 그대로 되살아난다.
//
// ── 다른 회차 칸과의 관계 ───────────────────────────────────────────────────
//
//   · occurrenceStats.{회차}        — 인원 카운터. 서버 reserve/release만 쓴다.
//   · occurrenceCancellations.{회차} — 최소 인원 미달 **자동** 취소 기록
//     (partyMinCapacity.js). 여기서는 읽지도 쓰지도 않는다 — 그 취소는
//     reserveApplicantSlot이 이미 따로 확인한다(isOccurrenceCancelled).
//
// 이 파일이 다루는 것은 **호스트가 직접 내린 상태** 하나뿐이다.

const { isClosedForGenderIn } = require('./partyGenderRecruit');

const FIELD = 'occurrenceRecruit';
const STATUS_KEY = 'status';
const GENDER_KEY = 'genderRecruitStatus';

const STATUS_OPEN = '모집중';
const STATUS_CLOSED = '마감';
const STATUS_CANCELLED = '취소';
const STATUSES = [STATUS_OPEN, STATUS_CLOSED, STATUS_CANCELLED];

/** [occurrenceId] 회차 칸. 없으면 null(= 문서 값을 따른다). */
function entryOf(data, occurrenceId) {
  if (!occurrenceId) return null;
  const all = data && data[FIELD];
  if (!all || typeof all !== 'object') return null;
  const entry = all[occurrenceId];
  return entry && typeof entry === 'object' ? entry : null;
}

/**
 * 이 회차의 전체 모집 상태 — 회차 칸이 없으면 문서의 recruitStatus.
 *
 * 저장된 값이 아는 문자열이 아니면 문서 값으로 폴백한다(잘못 쓰인 값 하나가
 * 회차를 영구히 잠그지 않게).
 */
function occurrenceStatusOf(data, occurrenceId) {
  const stored = entryOf(data, occurrenceId);
  const status = stored ? stored[STATUS_KEY] : null;
  if (typeof status === 'string' && STATUSES.includes(status)) return status;
  return (data && data.recruitStatus) || STATUS_OPEN;
}

/** 이 회차가 지금 신청을 받는 상태인가(성별은 따로 본다). */
function isOccurrenceRecruiting(data, occurrenceId) {
  return occurrenceStatusOf(data, occurrenceId) === STATUS_OPEN;
}

/** 이 회차의 성별 모집 칸 — 없으면 문서 최상단 값(폴백). */
function genderMapOf(data, occurrenceId) {
  const entry = entryOf(data, occurrenceId);
  const scoped = entry ? entry[GENDER_KEY] : null;
  if (scoped && typeof scoped === 'object') return scoped;
  const doc = data && data[GENDER_KEY];
  return doc && typeof doc === 'object' ? doc : null;
}

function isMaleClosedAt(data, occurrenceId) {
  return isClosedForGenderIn(genderMapOf(data, occurrenceId), 'male');
}

function isFemaleClosedAt(data, occurrenceId) {
  return isClosedForGenderIn(genderMapOf(data, occurrenceId), 'female');
}

/**
 * 이 성별에게 이 회차의 모집이 닫혀 있는가.
 *
 * 성별을 모르면 **양쪽이 다 닫힌 경우에만** 닫힘이다 — 문서 단위 판정
 * (partyGenderRecruit.isRecruitClosedFor)과 같은 규칙이라, 성별 인증 없이도
 * 신청되던 남녀무관 파티의 동작이 바뀌지 않는다.
 */
function isGenderRecruitClosedAt(data, gender, occurrenceId) {
  if (gender === 'male') return isMaleClosedAt(data, occurrenceId);
  if (gender === 'female') return isFemaleClosedAt(data, occurrenceId);
  return (
    isMaleClosedAt(data, occurrenceId) && isFemaleClosedAt(data, occurrenceId)
  );
}

module.exports = {
  FIELD,
  STATUS_KEY,
  GENDER_KEY,
  STATUS_OPEN,
  STATUS_CLOSED,
  STATUS_CANCELLED,
  entryOf,
  occurrenceStatusOf,
  isOccurrenceRecruiting,
  isMaleClosedAt,
  isFemaleClosedAt,
  isGenderRecruitClosedAt,
};

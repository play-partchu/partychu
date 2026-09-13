// ── 파티 성별별 모집 상태 ─────────────────────────────────────────────────────
//
// 이 파일은 party_app/lib/models/party_gender_recruit.dart의 **거울**이다.
// 한쪽만 고치면 앱이 보여주는 상태와 서버가 실제로 허용하는 신청이 어긋난다
// (앱에서는 '모집중'인데 눌러보면 거절되거나, 그 반대).
//
// ── 왜 recruitStatus에 값을 더하지 않는가 ──────────────────────────────────
//
// recruitStatus('모집중'/'마감'/'취소')는 앱과 서버 10여 곳에 문자열 그대로
// 박혀 있어서, 값을 하나 늘리면 한 군데만 놓쳐도 마감된 파티에 신청이 뚫린다
// (partyOpenState.js가 같은 이유로 독립 필드를 쓴다). 그래서 여기서도 독립
// 필드를 두고 기존 recruitStatus 로직은 그대로 둔다.
//
// ── 저장 형태 ───────────────────────────────────────────────────────────────
//
//   genderRecruitStatus: { male: 'open' | 'closed', female: 'open' | 'closed' }
//   (필드 없음 / 키 없음)  → 'open'. **기존 파티는 전부 무영향.**
//
// ── 판정 단위 ───────────────────────────────────────────────────────────────
//
// recruitStatus와 **완전히 같다** — 파티 문서 하나에 한 벌이다. 정기 파티
// (scheduleType: 'recurring')는 문서 하나가 모든 회차를 담으므로 이 설정도
// 모든 회차에 함께 걸린다(회차 하나만 닫는 수단은 occurrenceCancellations와
// 회차별 마감 시각으로 이미 있다). 날짜 슬롯을 여러 개 만든 게시글은 날짜마다
// 문서가 따로라 날짜별로 다르게 둘 수 있다.

const MALE = 'male';
const FEMALE = 'female';
const OPEN = 'open';
const CLOSED = 'closed';
const FIELD = 'genderRecruitStatus';

function statusMap(data) {
  const raw = data && data[FIELD];
  return raw && typeof raw === 'object' ? raw : null;
}

// 명시적으로 'closed'일 때만 닫힌 것으로 읽는다 — 값이 없거나 이상하면 열림.
//
// 회차별 모집 상태(partyOccurrenceRecruit.js)도 같은 모양의 맵을 회차 칸에
// 담으므로 **이 함수 하나로** 읽는다 — 규칙이 두 벌이 되면 문서 단위와 회차
// 단위의 하위호환 판정이 갈린다.
function isClosedForGenderIn(map, gender) {
  return !!map && map[gender] === CLOSED;
}

function isClosedForGender(data, gender) {
  return isClosedForGenderIn(statusMap(data), gender);
}

function isMaleClosed(data) {
  return isClosedForGender(data, MALE);
}

function isFemaleClosed(data) {
  return isClosedForGender(data, FEMALE);
}

/**
 * 이 성별에게 모집이 닫혀 있는가.
 *
 * 성별을 모르면(미인증) **양쪽이 다 닫힌 경우에만** 닫힘이다. 그때는 성별과
 * 무관하게 아무도 신청할 수 없으므로 판정에 성별이 필요 없다 — 반대로 한쪽만
 * 닫힌 파티를 성별 미상이라는 이유로 막으면, 성별을 모르는 상태가 곧 전면
 * 차단이 되어 기존 파티(성별 인증 없이도 신청되던 남녀무관 파티)의 동작이
 * 바뀐다.
 */
function isRecruitClosedFor(data, gender) {
  if (gender === MALE) return isMaleClosed(data);
  if (gender === FEMALE) return isFemaleClosed(data);
  return isMaleClosed(data) && isFemaleClosed(data);
}

/** 성별 설정만으로 파티 전체가 닫혔는가(성별 제한 파티는 받는 성별 하나만 본다). */
function isFullyClosed(data) {
  const limit = (data && data.genderLimit) || 'all';
  if (limit === MALE) return isMaleClosed(data);
  if (limit === FEMALE) return isFemaleClosed(data);
  return isMaleClosed(data) && isFemaleClosed(data);
}

/** 거절 문구 — 어느 성별이 닫혔는지 그대로 밝힌다. */
function closedMessageFor(data, gender) {
  if (gender === MALE) return '남성 모집이 마감되었습니다.';
  if (gender === FEMALE) return '여성 모집이 마감되었습니다.';
  return '마감';
}

module.exports = {
  FIELD,
  MALE,
  FEMALE,
  OPEN,
  CLOSED,
  isClosedForGenderIn,
  isMaleClosed,
  isFemaleClosed,
  isRecruitClosedFor,
  isFullyClosed,
  closedMessageFor,
};

// 취소 대상 신청 문서 고르기 — cancelApplication 하나가 쓰는 판정이다.
//
// 왜 파일로 떼어냈나: 회차별 신청이 생기면서 "어느 문서를 취소하는가"가 세
// 갈래로 갈렸다.
//   ① 회차를 지정한 요청         → applications/{uid}_{회차}
//   ② 회차가 붙기 전의 옛 신청   → applications/{uid}
//   ③ 회차를 못 보내는 구버전 앱 → 둘 중 무엇도 아닐 수 있다
//
// ③이 이 파일의 존재 이유다. 예전에는 ③을 무조건 applications/{uid}로 봤는데,
// 그 문서가 예전에 취소된 건이면 **살아 있는 회차 신청을 두고 '이미취소'로
// 거절**했다(실제로 운영에서 났다). 그렇다고 "살아 있는 신청 아무거나"
// 취소하면 8/22를 취소하려던 사람의 8/29 신청이 사라진다 — 그래서 **유일하게
// 특정될 때만** 처리하고, 여러 건이면 회차를 지정하라고 돌려보낸다.
//
// 판정이 한 글자만 틀려도 남의 회차 신청이 취소되므로 순수 함수로 두고
// partyApplicationTargets.selfcheck.js가 못 박는다.

/** 아직 끝나지 않은 신청 — accountWithdrawal.js/contentCleanup.js와 같은 값이어야 한다. */
// 세 곳이 어긋나면 "탈퇴는 막히는데 취소는 안 되는" 상태가 생긴다 —
// applicationBackcompat.selfcheck.js가 세 목록이 같은지 검사한다.
//
// **허용 목록**인 것이 중요하다. 모르는 상태(나중에 생길 값)를 살아 있는
// 신청으로 보고 자동으로 골라 취소하는 것보다, 고르지 않고 거절하는 편이 안전하다.
const LIVE_APPLICATION_STATUSES = ['applied', 'pending', 'approved'];

/// 자동으로 취소 대상으로 골라도 되는 신청인가.
function isLiveApplication(data) {
  return !!data && LIVE_APPLICATION_STATUSES.includes(data.status);
}

/// 이 사람의 신청 목록을 훑어봐야 하는 요청인가.
///
/// 회차를 지정한 요청은 대상이 이미 유일하므로 훑지 않는다. 회차를 지정하지
/// 않았어도 `applications/{uid}`가 살아 있으면 그게 곧 대상이라 훑지 않는다
/// (구버전 앱이 만든 신청은 언제나 그 문서다 — 기존 동작 그대로).
function needsCandidateLookup({ occurrenceId, scoped }) {
  if (occurrenceId) return false;
  return !scoped || !isLiveApplication(scoped.data);
}

const NOT_FOUND = {
  ok: false,
  code: 'not-found',
  message: '신청 내역을 찾을 수 없어요',
};

// 문구에 '회차를 지정'이 들어 있는지로 앱이 이 경우를 알아본다
// (party_detail_screen.dart의 _cancelFailure). 구버전 앱은 이 문장을 그대로
// 스낵바에 붙여 보여주므로, 그것만 읽어도 무엇을 해야 하는지 알 수 있어야 한다.
const AMBIGUOUS = {
  ok: false,
  code: 'failed-precondition',
  message:
    '취소할 회차를 지정해 주세요. 앱을 최신 버전으로 업데이트한 뒤 참가 날짜를 골라 취소해 주세요.',
};

/**
 * 취소할 신청 문서 하나를 고른다.
 *
 * 상태 검사(이미취소/이미참석/종료된파티)는 **여기서 하지 않는다** — 대상만
 * 고르고, 그 문서가 취소 가능한 상태인지는 호출부(cancelApplication)가 예전
 * 그대로 판정해 정확한 이유를 돌려준다.
 *
 * @param {object}                p
 * @param {string|null}           p.occurrenceId     클라이언트가 지정한 회차(구버전 앱은 null)
 * @param {{id,data}|null}        p.scoped           applications/{applicationDocId(uid, occurrenceId)}
 * @param {{id,data}|null}        p.legacy           applications/{uid} — 회차를 지정했을 때만 읽는다
 * @param {Array<{id,data}>|null} p.activeCandidates 이 사람의 이 파티 신청 전부([needsCandidateLookup]일 때만)
 * @returns {{ok:true, target:object}|{ok:false, code:string, message:string}}
 */
function resolveCancelTarget({ occurrenceId, scoped, legacy, activeCandidates }) {
  // ── ① 회차를 지정한 요청 — 대상은 그 회차 문서 하나뿐이다 ────────────
  if (occurrenceId) {
    if (scoped) return { ok: true, target: scoped };
    // 옛 문서 폴백은 "그 옛 신청이 정말 이 회차의 것"일 때만 쓴다.
    // 여기서만 'cancelled'만 걸러내는 것은 의도적이다(예전 규칙 그대로) —
    // 참석 처리된 옛 신청은 대상으로 잡아야 호출부가 '이미참석'이라는 정확한
    // 이유를 돌려준다.
    if (
      legacy &&
      legacy.data.status !== 'cancelled' &&
      (legacy.data.occurrenceId || occurrenceId) === occurrenceId
    ) {
      return { ok: true, target: legacy };
    }
    return NOT_FOUND;
  }

  // ── ② 회차를 지정하지 않은 요청(구버전 앱) ───────────────────────────
  // applications/{uid}가 살아 있으면 그게 대상이다 — 구버전 앱이 만든 신청은
  // 언제나 이 문서이므로, 이 경로는 예전과 100% 같게 동작한다(일회성 파티도
  // 문서가 이것 하나뿐이라 여기서 끝난다).
  if (scoped && isLiveApplication(scoped.data)) return { ok: true, target: scoped };

  // uid 문서로는 정할 수 없다 — 살아 있는 신청을 훑어 **유일할 때만** 쓴다.
  const candidates = (activeCandidates || []).filter((c) => isLiveApplication(c.data));
  if (candidates.length === 1) return { ok: true, target: candidates[0] };
  if (candidates.length > 1) return AMBIGUOUS;

  // 살아 있는 신청이 하나도 없다. uid 문서가 있으면 그것을 그대로 돌려줘
  // 호출부가 '이미취소'/'이미참석'처럼 **실제 상태**를 알려주게 한다.
  if (scoped) return { ok: true, target: scoped };
  return NOT_FOUND;
}

module.exports = {
  LIVE_APPLICATION_STATUSES,
  isLiveApplication,
  needsCandidateLookup,
  resolveCancelTarget,
  AMBIGUOUS_MESSAGE: AMBIGUOUS.message,
};

/**
 * 통합 신청자·예약자 관리(호스트)가 쓰는 **순수 판정들**.
 *
 * 화면은 파티 신청 · 방문예약 · 장소대여 · 숙박+파티 콤보 네 종류를 한 목록으로
 * 보여주는데, 파티 신청만 서버를 거친다(getHostApplicationInbox) — 나머지 셋은
 * 예약 문서에 신청자 이름이 이미 들어 있어 앱이 직접 읽지만, 파티 신청자의
 * 닉네임·실명은 users 문서에 있고 그건 본인·관리자만 읽을 수 있기 때문이다.
 *
 * 여기 있는 것은 Firestore를 모르는 함수들뿐이라 selfcheck로 그대로 확인된다
 * (hostInbox.selfcheck.js).
 */

/** 한 번에 내려주는 신청 건수 상한. 넘치면 화면이 "잘렸다"고 알려준다. */
const HOST_INBOX_LIMIT = 300;

/**
 * 호스트가 **아직 처리하지 않은** 파티 신청인지.
 *
 * 두 가지뿐이다.
 *   · 승인을 기다리는 건 — 승인제 파티의 `pending`
 *   · 입금 확인을 기다리는 건 — 참가자가 '입금했어요'를 눌러 `deposit_pending`
 *
 * 취소·거절은 처리가 끝난 것이므로 언제나 제외한다.
 *
 * `awaiting_deposit`(안내는 나갔지만 아직 입금 전)은 **넣지 않는다.** 호스트가
 * 지금 할 수 있는 일이 없고, 넣으면 배지 숫자가 "내가 해야 할 일"이 아니라
 * "진행 중인 건수"가 되어 영영 0이 되지 않는다. 파티별 신청자 화면의 입금확인
 * 목록은 그 상태도 함께 보여주는데(호스트가 통장에서 먼저 확인하는 경우가
 * 있다), 그건 "볼 수 있는 목록"이고 이건 "해야 할 일"이라 기준이 다르다.
 */
function isPartyApplicationUnhandled(appData) {
  const a = appData || {};
  const status = a.status || 'applied';
  if (status === 'cancelled' || status === 'rejected') return false;
  if (status === 'pending') return true;
  const payment = a.payment || null;
  return (
    !!payment &&
    payment.method === 'bank_transfer' &&
    payment.status === 'deposit_pending'
  );
}

/**
 * 이 파티 신청이 **숙박+파티 콤보 예약에서 파생된 것**인지.
 *
 * 콤보는 예약 문서(packageBookings)와 파티 신청 문서를 **함께** 만든다
 * (packageBookings.js — 자리가 확정되는 순간 신청 문서를 넣는다). 그래서 아무
 * 표시 없이 세면 예약 한 건이 두 번 나타난다.
 *
 *   · 알림 — 콤보는 이미 "새 숙박+파티 예약 신청"을 호스트에게 보낸다.
 *     파티 신청 트리거가 또 보내면 예약 한 건에 알림이 두 번 간다.
 *   · 통합 목록 — 예약 쪽을 '숙박+파티' 한 줄로 이미 보여주므로, 파티 신청으로
 *     또 세면 목록도 두 줄이고 미처리 숫자도 두 번 올라간다.
 *
 * 게스트 화면이 자기 신청 목록에서 같은 건을 걸러낼 때 쓰는 판별과 **같은
 * 값**이다(my_guest_hub_screen.dart의 `d['bundleBookingId'] != null`).
 */
function isComboGeneratedApplication(appData) {
  return !!(appData && appData.bundleBookingId);
}

/**
 * 이 신청이 **어느 날짜의 것인지** (밀리초, 없으면 null).
 *
 * 정기 파티는 회차마다 신청 문서가 따로 있고 각자 `occurrenceStartAt`을 들고
 * 있다. 파티 문서의 `partyDateTime`(등록 시점의 첫 회차 캐시)을 쓰면 8/22
 * 신청에 8/15가 찍히므로, 회차 값이 있으면 **반드시 그쪽이 먼저**다.
 */
function applicationStartAtMs(appData) {
  const a = appData || {};
  const value = a.occurrenceStartAt || a.partyDateTime || null;
  return value && typeof value.toMillis === 'function' ? value.toMillis() : null;
}

module.exports = {
  HOST_INBOX_LIMIT,
  isPartyApplicationUnhandled,
  isComboGeneratedApplication,
  applicationStartAtMs,
};

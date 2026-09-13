// 최소 모집 인원 미달 자동 취소 — 판정 로직과 알림 기록 작성.
//
// 클라이언트 lib/models/party_capacity_status.dart(PartyMinCapacity,
// PartyCapacityStatus)와 **같은 규칙**으로 최소/현재 인원을 읽는다. 한쪽만
// 고치면 앱에는 "확정"이 떠 있는데 서버가 취소해버리는 상태가 된다.

const admin = require('firebase-admin');
const {
  isRecurringParty,
  parseRecurringSchedule,
  occurrenceOnKstDay,
  kstMidnightOf,
  toDate,
} = require('./partySchedule');

/// 최소 인원 미달로 서버가 자동 취소했을 때 문서에 남기는 사유.
const MIN_CAPACITY_NOT_MET = 'minCapacityNotMet';

/// 회차 단위 취소 기록이 쌓이는 파티 문서의 맵 필드.
/// `occurrenceCancellations: { 'YYYY-MM-DD': { reason, cancelledAt, ... } }`
///
/// 인원 카운터가 사는 `occurrenceStats`와 **일부러 분리**했다. 그쪽은
/// reserve/releaseApplicantSlot만 쓰는 칸이라(partyCapacity.js 상단 '정원
/// 카운터의 소유권') 다른 목적의 쓰기를 섞으면 소유권이 흐려진다.
const OCCURRENCE_CANCELLATIONS = 'occurrenceCancellations';

const DAY_MS = 24 * 60 * 60 * 1000;
const KST_OFFSET_MS = 9 * 60 * 60 * 1000;

// 성비 맞춤(남녀 정원 분리) 파티는 참가자 수도 남녀 합계다 — 카드/상세와
// 같은 규칙(PartyCard.currentParticipants).
function currentParticipantsOf(data) {
  const num = (v) => Number(v || 0);
  if ((data.genderCapacityMode || 'unlimited') === 'separate') {
    return num(data.currentMaleCount) + num(data.currentFemaleCount);
  }
  return num(data.currentParticipants);
}

/**
 * 파티 **전체**(정기 파티는 회차 하나)의 최소 모집 인원.
 *
 * 정본은 `partyMinCapacity` 필드 하나다. 예전 등록/수정 화면은 차수별 정원
 * 모드에서 문서 최상단 `minCapacity`를 **차수 최소 인원의 합계**로 덮어썼는데
 * (1차 2명 + 2차 2명 → 4명), 차수 최소 인원과 파티 최소 모집 인원은 더할 수
 * 있는 값이 아니다 — 1차·2차를 모두 신청한 한 사람이 두 번 세진다.
 *
 * 새 필드가 없는 **옛 문서**의 폴백:
 *  · 차수별 정원 파티 → 저장된 값이 합계라 뜻을 알 수 없다. **0(제한 없음)**.
 *    추정해서 자동 취소를 돌리는 것보다 기능을 끄는 쪽이 안전하다.
 *  · 그 밖의 파티 → `minCapacity`가 호스트 입력 그대로라 신뢰할 수 있다.
 *
 * 클라이언트 PartyMinCapacity.of와 **같은 결과를 내야 한다.**
 */
function partyMinCapacityOf(data) {
  const explicit = data.partyMinCapacity;
  if (explicit !== undefined && explicit !== null) {
    return Math.max(0, Number(explicit) || 0);
  }
  if (isLegacySummedMin(data)) return 0;
  return Math.max(0, Number(data.minCapacity || 0));
}

/** 이 문서의 `minCapacity`가 차수 합계로 오염된 옛 문서인지. */
function isLegacySummedMin(data) {
  if (data.partyMinCapacity !== undefined && data.partyMinCapacity !== null) {
    return false;
  }
  return (
    data.hasMultipleRounds === true &&
    (data.roundCapacityMode || 'unified') === 'perRound'
  );
}

function autoCancelsBelowMin(data) {
  return (data.minCapacityPolicy || 'proceed') === 'autoCancel';
}

/**
 * "실제 참여 확정으로 인정되는" 신청 문서인지.
 *
 * 카운터(`currentParticipants`)를 쓰지 않고 신청 문서를 직접 세는 이유는,
 * 카운터가 **승인 대기(pending)까지 포함한 자리 예약 수**이기 때문이다.
 * 승인제 파티에서 호스트가 아직 아무도 승인하지 않았는데 "10명 모였다"로
 * 보고 취소를 건너뛰면, 미달인 채로 파티가 열린다.
 *
 * 통과: applied(즉시확정 파티의 접수 = 자리 확정) / approved(승인·입금확인).
 * 제외: pending(승인 대기) / cancelled / rejected / expired.
 *
 * 현장결제 예정처럼 아직 돈이 들어오지 않은 신청도 확정으로 센다 — 참가는
 * 확정됐고 결제 시점만 뒤인 것이라, 자리를 차지한 사람이 맞다.
 */
function isConfirmedApplication(appData) {
  const status = appData && appData.status;
  return status === 'applied' || status === 'approved';
}

/** 신청 문서 목록에서 [occurrenceId] 회차의 확정 인원. */
function confirmedCountOf(applications, occurrenceId = null) {
  return applications.filter((a) => {
    if (!isConfirmedApplication(a)) return false;
    if (!occurrenceId) return true;
    return (a.occurrenceId || null) === occurrenceId;
  }).length;
}

/** 이 회차가 이미 취소됐는지. */
function isOccurrenceCancelled(data, occurrenceId) {
  if (!occurrenceId) return false;
  const all = data && data[OCCURRENCE_CANCELLATIONS];
  return !!(all && typeof all === 'object' && all[occurrenceId]);
}

// ── 일회성 파티 ────────────────────────────────────────────────────────

/**
 * 이 **일회성** 파티가 자동 취소 판정 대상인지(인원 비교 직전까지).
 *
 * 조건:
 *  1. 자동 취소로 설정돼 있고 최소 인원이 정해져 있다
 *  2. 아직 '모집중'이고 이미 취소/삭제되지 않았다
 *  3. 모집 마감 시각을 지났다
 *
 * 인원 비교는 호출부가 신청 문서를 읽어 [confirmedCountOf]로 한다 — 문서에
 * 캐시된 카운터로는 승인 대기와 확정을 가를 수 없기 때문이다.
 * 정기 파티는 회차 단위라 [dueOccurrencesOf]가 따로 다룬다.
 */
function isAutoCancelCandidate(data, now = new Date()) {
  if (!autoCancelsBelowMin(data)) return false;
  if (partyMinCapacityOf(data) <= 0) return false;
  if (isRecurringParty(data)) return false;
  if (data.isDeleted === true || data.status === 'deleted') return false;
  if ((data.recruitStatus || '모집중') !== '모집중') return false;

  const deadline = toDate(data.recruitDeadlineAt);
  if (!deadline || deadline.getTime() > now.getTime()) return false;
  return true;
}

/**
 * 캐시된 카운터만으로 판정하는 예전 시그니처.
 * 신청 문서를 읽을 수 없는 곳(자체 검증)에서만 쓴다.
 */
function shouldAutoCancel(data, now = new Date()) {
  if (!isAutoCancelCandidate(data, now)) return false;
  return currentParticipantsOf(data) < partyMinCapacityOf(data);
}

/**
 * 자동 취소 시 **파티 문서 전체**에 쓸 필드(일회성 파티).
 *
 * `recruitStatus: '취소'`로 바뀌는 순간 기존 onPartyCancelledByHost 트리거가
 * 신청 전원을 취소 처리하고 전액 환불(refundStatus: 'pending')로 돌린다 —
 * 환불 파이프라인을 새로 만들지 않고 그대로 재사용한다.
 */
function autoCancelFields(data, participants = null) {
  return {
    recruitStatus: '취소',
    cancelReason: MIN_CAPACITY_NOT_MET,
    cancelledBySystem: true,
    autoCancelledAt: admin.firestore.FieldValue.serverTimestamp(),
    minCapacityAtCancel: partyMinCapacityOf(data),
    participantsAtCancel:
      participants == null ? currentParticipantsOf(data) : participants,
  };
}

// ── 정기 파티(회차 단위) ───────────────────────────────────────────────

/** 회차 시작 시각 → 'YYYY-MM-DD'(KST 달력 기준) 회차 id. */
function occurrenceIdOf(start) {
  const kst = new Date(start.getTime() + KST_OFFSET_MS);
  const y = kst.getUTCFullYear();
  const m = String(kst.getUTCMonth() + 1).padStart(2, '0');
  const d = String(kst.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

/**
 * 지금 판정해야 할 **회차**들 — 모집 마감이 지났고 아직 취소 기록이 없는 것.
 *
 * [lookbackDays]일 전까지만 훑는다. 마감을 한참 지난 옛 회차까지 거슬러
 * 올라가면, 기능을 켜기 전에 이미 지나간 회차들이 한꺼번에 취소된다.
 * 스케줄러가 10분마다 도는 것을 감안하면 며칠이면 충분하다.
 *
 * 회차 **시작 시각이 이미 지난** 회차는 제외한다 — 파티가 이미 열렸거나
 * 열리는 중인데 뒤늦게 취소하면 현장에 온 사람이 생긴다.
 */
function dueOccurrencesOf(data, now = new Date(), lookbackDays = 3) {
  if (!isRecurringParty(data)) return [];
  if (!autoCancelsBelowMin(data)) return [];
  if (partyMinCapacityOf(data) <= 0) return [];
  if (data.isDeleted === true || data.status === 'deleted') return [];
  // 파티 문서 자체가 취소/마감이면 회차를 따로 다룰 일이 없다.
  if ((data.recruitStatus || '모집중') !== '모집중') return [];

  const schedule = parseRecurringSchedule(data.recurringSchedule);
  if (!schedule) return [];

  const due = [];
  // 마감이 회차 당일보다 앞설 수도, 뒤설 수도 있어서 "마감이 지났는가"는
  // 회차마다 실제 값으로 본다. 앞으로 열릴 회차도 마감이 이미 지났을 수
  // 있으므로(예: 3일 전 마감) 오늘 이후도 함께 훑는다.
  const today = kstMidnightOf(now);
  for (let i = -lookbackDays; i <= lookbackDays; i++) {
    const kstMidnight = new Date(today.getTime() + i * DAY_MS);
    const occ = occurrenceOnKstDay(schedule, kstMidnight);
    if (!occ) continue;
    // 마감이 없는 회차는 "미달로 마감된 시점"이라는 것이 없다.
    if (!occ.deadline || occ.deadline.getTime() > now.getTime()) continue;
    // 이미 시작한 회차는 건드리지 않는다.
    if (occ.start.getTime() <= now.getTime()) continue;

    const occurrenceId = occurrenceIdOf(occ.start);
    if (isOccurrenceCancelled(data, occurrenceId)) continue;
    due.push({ occurrenceId, occurrence: occ });
  }
  return due;
}

/**
 * 한 회차를 취소했다고 파티 문서에 남길 필드(점 표기 경로 하나).
 *
 * **파티 문서 전체의 recruitStatus는 건드리지 않는다** — 다른 날짜 회차는
 * 그대로 열려 있어야 하기 때문이다. 그래서 onPartyCancelledByHost 트리거도
 * 깨어나지 않고, 이 회차 신청들의 취소·환불은 호출부가 직접 처리한다
 * (index.js의 자동 취소 작업).
 */
function occurrenceCancelFields(data, occurrenceId, participants) {
  return {
    [`${OCCURRENCE_CANCELLATIONS}.${occurrenceId}`]: {
      reason: MIN_CAPACITY_NOT_MET,
      cancelledBySystem: true,
      cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
      minCapacityAtCancel: partyMinCapacityOf(data),
      participantsAtCancel: participants,
    },
  };
}

// 알림 기록 한 건. `notifications` 컬렉션에 쌓아두면 인앱 알림함과 푸시
// 발송기(pushDispatch)가 이 문서를 읽어 보낸다.
function notificationDoc({
  uid,
  partyId,
  partyTitle,
  role,
  data,
  occurrenceId = null,
  participants = null,
}) {
  const min = partyMinCapacityOf(data);
  const current =
    participants == null ? currentParticipantsOf(data) : participants;
  const isHost = role === 'host';
  // 정기 파티는 "파티"가 아니라 "그 날짜 회차"가 취소된 것이다 — 문구가
  // 이것을 분명히 해야 다른 회차까지 없어진 줄 알고 문의가 들어오지 않는다.
  const subject = occurrenceId
    ? `'${partyTitle}' ${occurrenceId} 회차`
    : `'${partyTitle}'`;
  const tail = occurrenceId
    ? isHost
      ? ' 다른 날짜 회차는 그대로 열려 있어요.'
      : ' 다른 날짜 회차는 그대로 신청할 수 있어요.'
    : '';
  return {
    uid,
    type: 'partyAutoCancelledMinCapacity',
    partyId,
    ...(occurrenceId ? { occurrenceId } : {}),
    role,
    title: isHost
      ? occurrenceId
        ? '회차가 자동 취소됐어요'
        : '파티가 자동 취소됐어요'
      : occurrenceId
        ? '신청한 회차가 취소됐어요'
        : '신청한 파티가 취소됐어요',
    body: isHost
      ? `${subject}이(가) 최소 모집 인원(${min}명)에 못 미쳐(${current}명) 자동 취소됐어요.${tail}`
      : `${subject}이(가) 최소 모집 인원 미달로 취소됐어요. 결제한 참가비는 전액 환불 처리됩니다.${tail}`,
    read: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

module.exports = {
  MIN_CAPACITY_NOT_MET,
  OCCURRENCE_CANCELLATIONS,
  currentParticipantsOf,
  partyMinCapacityOf,
  isLegacySummedMin,
  autoCancelsBelowMin,
  isConfirmedApplication,
  confirmedCountOf,
  isOccurrenceCancelled,
  isAutoCancelCandidate,
  shouldAutoCancel,
  autoCancelFields,
  dueOccurrencesOf,
  occurrenceIdOf,
  occurrenceCancelFields,
  notificationDoc,
};

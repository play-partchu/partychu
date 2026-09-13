const flow = require('./depositFlow');

/**
 * 장소대여 예약(placeReservationGroups)의 **상태 규칙**.
 *
 * 결제 상태 전이 자체는 [depositFlow]가 전부 갖고 있고(파티 신청·플레이스
 * 방문예약과 완전히 같은 규칙), 여기에는 장소대여에만 있는 두 가지를 둔다.
 *
 *   ① 예약 진행 상태(status)와 결제 상태(payment.status)의 **조합이
 *      시간 슬롯을 어떻게 잡고 있어야 하는가** — [slotHoldOf]
 *   ② 승인 방식/응답 기한 같은 룸 설정 읽기 — [normalizeApprovalMode]
 *
 * 슬롯을 "언제까지 잡아두는가"가 장소대여의 핵심이다. 방문예약은 좌석 수를
 * 더하고 빼면 그만이지만, 장소대여는 그 시간을 **독점**하므로 잡아둔 채
 * 결제가 안 되면 그 시간이 통째로 죽는다. 그래서 살아있는 모든 구간에
 * 만료 시각(expiresAt)이 붙고, 겹침 판정은 "pending인데 기한이 지난 슬롯은
 * 없는 셈 친다"는 기존 규칙을 그대로 쓴다(placeReservations.js의 겹침 조회).
 *
 * 모든 함수는 순수하다 — Firestore를 모르므로 자체 검증에서 그대로 부른다.
 */

/** 예약 진행 상태 — 서버가 쓰는 문자열 전부. */
const STATUS = {
  /** 옛 포트원 결제 대기(10분). 무통장입금 흐름에서는 쓰지 않는다. */
  pending: 'pending',
  /** 승인제 룸의 승인 대기. */
  requested: 'requested',
  /** 자리 확정 — 돈은 아직 안 들어왔을 수 있다(payment.status가 따로 말한다). */
  confirmed: 'confirmed',
  rejected: 'rejected',
  cancelled: 'cancelled',
  expired: 'expired',
};

/** 아직 시간 슬롯을 잡고 있는 예약 — 취소·만료 처리의 대상. */
const LIVE_STATUSES = new Set([STATUS.pending, STATUS.requested, STATUS.confirmed]);

/** 승인 방식. 설정한 적 없는 기존 룸은 지금까지처럼 승인 없이 바로 확정된다. */
function normalizeApprovalMode(raw) {
  return raw === 'manual' ? 'manual' : 'auto';
}

/** 업주가 승인 요청에 응답해야 하는 기본 시간(시간 단위). */
const DEFAULT_APPROVAL_HOURS = 12;

function normalizeApprovalHours(raw) {
  const n = Number(raw);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : DEFAULT_APPROVAL_HOURS;
}

/**
 * 이 예약이 **실제로 이용을 시작하는 시각**(epoch ms).
 *
 * 입금기한·승인기한이 이 시각을 넘지 않게 자르는 데 쓴다 — 이용이 6시간
 * 뒤인데 입금기한이 24시간이면 기한이 뜻을 잃는다. 시간제는 구간이 여러
 * 개일 수 있으므로 **가장 이른 구간**이 기준이다.
 */
function useStartMs(midnightMs, windows) {
  if (!Array.isArray(windows) || windows.length === 0) return null;
  const start = windows.reduce((m, w) => Math.min(m, Number(w.start)), Infinity);
  if (!Number.isFinite(start)) return null;
  return midnightMs + start * 60000;
}

/** 이 예약이 이용을 끝내는 시각(epoch ms) — 목록 표시·정렬용. */
function useEndMs(midnightMs, windows) {
  if (!Array.isArray(windows) || windows.length === 0) return null;
  const end = windows.reduce((m, w) => Math.max(m, Number(w.end)), -Infinity);
  if (!Number.isFinite(end)) return null;
  return midnightMs + end * 60000;
}

/**
 * 지금 상태에서 **응답/입금 기한**이 언제인가 — 승인 대기 기한을 계산한다.
 * 이용 시작 시각이 먼저 오면 그때가 곧 마감이다.
 */
function approvalDeadlineMs(nowMs, approvalHours, useAtMs) {
  const base = nowMs + normalizeApprovalHours(approvalHours) * 3600000;
  if (useAtMs && useAtMs < base) return useAtMs;
  return base;
}

/**
 * 예약 상태 + 결제 상태 → **시간 슬롯 문서가 가져야 할 점유 상태**.
 *
 * 슬롯은 `status`(pending/confirmed/cancelled/expired)와 `expiresAt` 두 값만
 * 갖고, 겹침 판정은 "cancelled·expired는 없는 셈 / pending인데 기한이 지났으면
 * 없는 셈"으로 읽는다. 그래서 "언제까지 잡아두나"를 여기서 한 번만 정하면
 * 생성·승인·입금·확인 어느 단계에서든 같은 답이 나온다.
 *
 *   승인 대기            → pending, 업주 응답 기한까지
 *   확정 + 입금대기      → pending, 입금기한까지   (기한이 지나면 자리가 풀린다)
 *   확정 + 입금확인중    → confirmed, 기한 없음     (이미 입금했다고 알린 건이다)
 *   확정 + 결제완료/현장결제/무료 → confirmed, 기한 없음
 *
 * 입금확인중을 confirmed로 올리는 것이 중요하다 — 기한 직전에 '입금했어요'를
 * 누른 사람의 자리가 몇 초 뒤에 풀려 남에게 넘어가면 안 된다(자동 만료 대상에서
 * 빠지는 depositFlow.isExpirable과 같은 이유다).
 *
 * @returns {{status: string, expiresAtMs: number|null}|null}
 *   종료된 예약(취소·거절·만료)이면 null — 그건 해제 로직이 따로 처리한다.
 */
function slotHoldOf(status, payment, { respondByMs = null } = {}) {
  if (status === STATUS.requested) {
    return { status: 'pending', expiresAtMs: respondByMs };
  }
  if (status !== STATUS.confirmed) return null;

  const bank = flow.bankPaymentOf(payment);
  if (bank && bank.status === flow.STATUS.awaitingDeposit) {
    return {
      status: 'pending',
      expiresAtMs:
        typeof bank.depositDeadlineMs === 'number' ? bank.depositDeadlineMs : null,
    };
  }
  return { status: 'confirmed', expiresAtMs: null };
}

/**
 * 이 예약을 지금 취소할 수 있는지 — 취소 호출부가 공유하는 판정.
 * 이미 끝난 예약은 조용히 통과시킨다(재호출에 안전).
 */
function isLive(status) {
  return LIVE_STATUSES.has(status);
}

/**
 * 예약 문서를 [depositFlow]에 넘길 때 쓰는 문맥 — "이 건이 이미 취소됐나".
 * 파티 신청·방문예약이 각자 갖고 있는 것과 같은 얇은 껍데기다.
 */
function docContext(group) {
  return { cancelled: !isLive(group && group.status) };
}

module.exports = {
  STATUS,
  LIVE_STATUSES,
  DEFAULT_APPROVAL_HOURS,
  normalizeApprovalMode,
  normalizeApprovalHours,
  useStartMs,
  useEndMs,
  approvalDeadlineMs,
  slotHoldOf,
  isLive,
  docContext,
};

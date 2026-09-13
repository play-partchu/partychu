// ── 보존 기간 정책 ───────────────────────────────────────────────────────────
//
// 이 파일에 있는 것은 **기간뿐**이다. "무엇을 보존하는가"는 각 도메인 코드가
// 정하고, "얼마나 보존하는가"만 여기 한 곳에 모은다. 법무 검토가 끝나면 이
// 파일의 숫자만 바꾸면 되고, 도메인 코드는 건드리지 않는다.
//
// ── days: null 이 뜻하는 것 ─────────────────────────────────────────────────
//
// **null = 기간 미정이며, 미정인 동안에는 아무것도 파기하지 않는다.**
//
// 숫자를 지어내면 두 방향 모두 되돌릴 수 없는 사고가 된다 — 법정 기간보다 짧게
// 잡으면 분쟁이 붙었을 때 증거가 이미 없고, 길게 잡으면 그 순간부터 보존이
// 아니라 초과 보관이다. 그래서 확정 전까지는 "보류"가 유일하게 안전한 기본값이고,
// 이 파일을 읽는 쪽은 반드시 null을 "파기 금지"로 해석해야 한다
// (isExpired가 null이면 언제나 false를 돌려주는 이유다).
//
// ── 보존 성격을 나눠 두는 이유 ───────────────────────────────────────────────
//
// 탈퇴 회원을 운영에서 계속 보려고 남기는 것과, 분쟁·제재에 대비해 증거로
// 남기는 것은 근거도 기간도 다르다. 한 덩어리로 묶어 두면 나중에 어느 하나만
// 기간을 바꿀 수 없고, "왜 아직 들고 있느냐"에 답할 수도 없다.

/** 보존 성격 구분. 저장되는 값이 아니라 코드가 참조하는 키다. */
const RETENTION_CLASS = {
  /** 탈퇴 회원 관리 이력 — 관리자가 탈퇴 회원을 조회·식별하기 위한 최소 정보. */
  withdrawnMemberAdmin: 'withdrawnMemberAdmin',
  /** 분쟁·제재 증거 — 신고·제재·부정이용·노쇼처럼 다툼이 생겼을 때 근거가 되는 기록. */
  disputeEvidence: 'disputeEvidence',
  /** 재가입 추적 — 탈퇴 계정과 새 계정을 잇는 연결(identityLinks.previousUids). */
  identityRelink: 'identityRelink',
  /** 거래기록 — 전자상거래법상 보존 의무가 걸리는 주문·예약·결제·환불. */
  transactionRecord: 'transactionRecord',
};

/**
 * 성격별 보존 기간.
 *
 * `days`가 숫자면 그 기간이 지난 뒤 파기 대상이고, null이면 미정이라 파기하지
 * 않는다. `basis`는 어느 시각부터 세는지, `note`는 법무가 기간을 정할 때 필요한
 * 배경이다 — 숫자만 남기면 나중에 왜 이 값인지 아무도 모른다.
 */
const RETENTION_POLICY = {
  [RETENTION_CLASS.withdrawnMemberAdmin]: {
    label: '탈퇴 회원 관리 이력',
    days: null,
    basis: 'withdrawnAt',
    covers: [
      'users/{uid} 비석의 탈퇴 관리 필드',
      '  · withdrawalRequestedAt · withdrawnAt · withdrawnMemberType',
      '  · withdrawalReasonCode · withdrawnFromStatus',
    ],
    note:
      '법정 의무 보존이 아니라 운영 편의를 위한 보관이다. 근거가 약한 쪽이므로 '
      + '분쟁 증거보다 짧게 잡는 것이 자연스럽다.',
  },

  [RETENTION_CLASS.disputeEvidence]: {
    label: '분쟁·제재 증거',
    days: null,
    basis: 'occurredAt',
    covers: [
      'userActivityLogs (제재·노쇼·신고 처리 이력)',
      'reports (신고)',
      'users/{uid}.adminMemo (운영자 메모)',
      'chatRooms / messages (거래 다툼의 정황)',
    ],
    note:
      '소비자 불만·분쟁 처리 기록은 전자상거래법상 보존 의무가 있다. 다만 '
      + '어느 기록이 그 "분쟁 처리 기록"에 해당하는지는 법무 판단이 필요하다.',
  },

  [RETENTION_CLASS.identityRelink]: {
    label: '재가입 추적 연결',
    days: null,
    basis: 'releasedAt',
    covers: ['identityLinks/{ciHash}.previousUids'],
    note:
      '가장 민감한 항목이다. CI 해시는 그 자체로 개인을 특정하는 식별자이고, '
      + '이 연결이 살아 있는 동안은 "탈퇴해도 같은 사람임을 시스템이 계속 안다"는 뜻이다. '
      + '개인정보 최소수집 원칙과 정면으로 부딪히므로 기간을 가장 먼저 확정해야 한다.',
  },

  [RETENTION_CLASS.transactionRecord]: {
    label: '거래기록',
    days: null,
    basis: 'completedAt',
    covers: [
      'orders · placeProductOrders',
      'parties/{id}/applications (결제가 있었던 건)',
      'placeReservationGroups · placeVisitReservations · packageBookings',
      'refundRequests',
    ],
    note:
      '자료 종류에 따라 기간이 갈린다(계약·청약철회 / 대금결제·재화공급 / '
      + '소비자 불만·분쟁처리). 하나의 숫자로 뭉뚱그리면 안 되므로, 확정 시 '
      + '이 항목을 더 쪼개야 할 수 있다.',
  },
};

/** 이 성격의 보존 기간(일). 미정이면 null. */
function retentionDays(retentionClass) {
  const policy = RETENTION_POLICY[retentionClass];
  if (!policy) throw new Error(`알 수 없는 보존 성격: ${retentionClass}`);
  return policy.days;
}

/** 기간이 확정돼 파기를 실행해도 되는 성격인가. */
function isRetentionDefined(retentionClass) {
  return retentionDays(retentionClass) != null;
}

const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * 기준 시각으로부터의 파기 예정 시각. 기간 미정이면 null.
 *
 * @param {string} retentionClass RETENTION_CLASS 중 하나
 * @param {Date|number} since     보존 기산 시각
 * @returns {Date|null}
 */
function expiresAt(retentionClass, since) {
  const days = retentionDays(retentionClass);
  if (days == null) return null;
  const base = since instanceof Date ? since.getTime() : Number(since);
  if (!Number.isFinite(base)) return null;
  return new Date(base + days * DAY_MS);
}

/**
 * 지금 파기해도 되는가.
 *
 * **기간이 미정이면 언제나 false다.** 이 함수를 쓰는 쪽은 "만료됐다"가 확실할
 * 때만 지우게 되고, 정책이 비어 있는 동안에는 아무것도 지우지 않는다.
 */
function isExpired(retentionClass, since, now = Date.now()) {
  const at = expiresAt(retentionClass, since);
  if (at == null) return false;
  return at.getTime() <= (now instanceof Date ? now.getTime() : Number(now));
}

/** 운영자·법무에게 보여줄 현재 정책 요약. */
function describePolicy() {
  return Object.entries(RETENTION_POLICY).map(([key, p]) => ({
    retentionClass: key,
    label: p.label,
    days: p.days,
    decided: p.days != null,
    basis: p.basis,
    covers: p.covers,
    note: p.note,
  }));
}

module.exports = {
  RETENTION_CLASS,
  RETENTION_POLICY,
  retentionDays,
  isRetentionDefined,
  expiresAt,
  isExpired,
  describePolicy,
};

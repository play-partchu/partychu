const { HttpsError } = require('firebase-functions/v2/https');

/**
 * **호스트가 정하는 결제 정책** — 파티 / 플레이스 예약 / 장소대여·숙박이 함께 쓴다.
 * 앱의 lib/models/payment_policy.dart와 키가 1:1로 맞다.
 *
 * ─────────────────────────────────────────────────────────────────────────
 * ⚠ 이름 주의 — 이 파일의 `upfront`와 기존 `deposit`은 **완전히 다른 축**이다.
 *
 *   upfront (여기)      = 예약금. "총액 중 얼마를 미리 받는가"     ← 호스트 정책
 *   deposit (depositFlow) = 무통장입금. "어떤 수단으로 받는가"      ← 구매자 선택
 *
 * 그래서 `paymentMode: 'partial'`(예약금 방식)인 예약이
 * `payment.status: 'awaiting_deposit'`(무통장 입금대기)인 상태가 정상이다.
 * 두 개념을 한 이름으로 합치면 이 구간을 표현할 수 없어진다.
 *
 * **사용자 화면에는 upfront를 전부 '예약금'으로 표기한다** — `upfront`는 개발용
 * 이름일 뿐이므로 라벨에 노출하지 않는다.
 * ─────────────────────────────────────────────────────────────────────────
 *
 * ## 세 가지 결제 방식
 *
 *   prepaid  전액 선결제   지금 전액   / 현장 0원
 *   partial  예약금 결제   지금 예약금 / 현장 잔금
 *   onsite   현장 전액결제 지금 0원    / 현장 전액
 *
 * ## 정책이 없는 문서(legacy)
 *
 * 기존 파티·장소는 이 필드가 아예 없다. 그때는 **지금까지의 동작을 그대로
 * 유지한다** — 구매자가 무통장입금/현장결제를 자유롭게 고르고 금액은 전액이다.
 * 임의로 prepaid로 간주하면 현장결제로 신청하던 사용자가 갑자기 막힌다.
 *
 * ## 총액이 확정되지 않는 예약
 *
 * 플레이스 좌석 예약처럼 "자리만 잡고 음식은 현장에서 주문"하는 형태는 예약
 * 시점에 총액을 알 수 없다. 이때 `%` 예약금은 계산할 근거가 없으므로
 * `allowPercentage: false`로 막고, 잔금도 **숫자를 지어내지 않고 null**로 둔다
 * (화면은 "추가 이용금액은 현장에서 결제"라고만 쓴다).
 *
 * 모든 함수는 순수하다 — Firestore를 모르므로 자체 검증에서 그대로 부를 수 있다.
 */

/** 결제 방식. 문서에 저장되는 값. */
const MODE = {
  prepaid: 'prepaid',
  partial: 'partial',
  onsite: 'onsite',
};

const MODES = Object.values(MODE);

/** 예약금 산정 방식. `partial`일 때만 뜻이 있다. */
const UPFRONT_TYPE = {
  percentage: 'percentage',
  fixed: 'fixed',
};

const UPFRONT_TYPES = Object.values(UPFRONT_TYPE);

/**
 * 방식별로 허용되는 결제수단.
 *
 * PG 계약 전이라 실제로 열려 있는 수단은 무통장입금·현장결제뿐이다
 * ([paymentInfo.ENABLED_METHODS]). 그래서 "선결제"는 무통장입금을 뜻한다 —
 * PG가 붙으면 `card` 등을 아래 prepaid/partial 배열에 더하기만 하면 된다.
 *
 * legacy(정책 없음)는 지금처럼 **둘 다** 고를 수 있다.
 */
const METHODS_BY_MODE = {
  [MODE.prepaid]: ['bank_transfer'],
  [MODE.partial]: ['bank_transfer'],
  [MODE.onsite]: ['on_site'],
};

const LEGACY_METHODS = ['bank_transfer', 'on_site'];

/** 정책이 없을 때(legacy) 고를 수 있는 수단. */
function allowedMethodsFor(paymentMode) {
  if (!paymentMode) return [...LEGACY_METHODS];
  return [...(METHODS_BY_MODE[paymentMode] || LEGACY_METHODS)];
}

function toInt(v) {
  const n = Number(v);
  return Number.isFinite(n) ? Math.floor(n) : 0;
}

/**
 * 호스트가 보낸 정책 원본을 저장 가능한 형태로 정규화한다.
 *
 * @param {object|null|undefined} raw 호스트 설정(등록/수정 화면이 보낸 값)
 * @param {object} [opts]
 * @param {boolean} [opts.allowPercentage=true] 총액이 확정되는 도메인인지
 * @param {boolean} [opts.allowPrepaid=true]    전액 선결제를 허용하는 도메인인지
 * @returns {object|null} 정규화된 정책. 설정이 없으면 **null**(legacy 동작).
 */
/**
 * 문서에서 정책 필드만 골라낸다.
 *
 * ⚠ 정책은 문서 **최상단에 평평하게** 저장된다(`paymentMode`, `upfrontType`, …).
 *   중첩 맵(`paymentPolicy: {...}`)이 아니다 — 앱의 `PaymentPolicy.toMap()`을
 *   파티/룸 문서에 그대로 펼쳐 넣기 때문이고, 읽는 쪽(`PaymentPolicy.fromMap(d)`)도
 *   문서 전체를 받는다. 서버가 중첩으로 읽으면 정책이 **조용히 무시되어**
 *   예약금이 걸린 예약에서 전액이 청구된다.
 *
 * @returns {object|null} 정책 필드만 담은 객체. paymentMode가 없으면 null.
 */
function pickPolicyFields(doc) {
  if (!doc || typeof doc !== 'object') return null;
  if (typeof doc.paymentMode !== 'string') return null;
  return {
    paymentMode: doc.paymentMode,
    upfrontType: doc.upfrontType,
    upfrontPercent: doc.upfrontPercent,
    upfrontFixedAmount: doc.upfrontFixedAmount,
  };
}

function normalizePolicy(raw, { allowPercentage = true, allowPrepaid = true } = {}) {
  if (!raw || typeof raw !== 'object') return null;

  const mode = raw.paymentMode;
  if (!MODES.includes(mode)) return null;
  if (mode === MODE.prepaid && !allowPrepaid) {
    throw new HttpsError(
      'invalid-argument',
      '이 예약은 총 이용금액이 미리 확정되지 않아 전액 선결제를 쓸 수 없어요.',
    );
  }

  // prepaid·onsite는 예약금 항목 자체가 없다 — 남겨두면 나중에 방식을 바꿨을 때
  // 옛 값이 되살아나 잘못 계산된다.
  if (mode !== MODE.partial) {
    return { paymentMode: mode };
  }

  const type = UPFRONT_TYPES.includes(raw.upfrontType) ? raw.upfrontType : null;
  if (!type) {
    throw new HttpsError('invalid-argument', '예약금 방식을 선택해주세요.');
  }
  if (type === UPFRONT_TYPE.percentage && !allowPercentage) {
    throw new HttpsError(
      'invalid-argument',
      '총 이용금액이 미리 확정되지 않는 예약에는 비율 예약금을 쓸 수 없어요. 고정 예약금을 사용해주세요.',
    );
  }

  if (type === UPFRONT_TYPE.percentage) {
    const pct = toInt(raw.upfrontPercent);
    if (pct <= 0 || pct > 100) {
      throw new HttpsError('invalid-argument', '예약금 비율은 1~100% 사이로 입력해주세요.');
    }
    return { paymentMode: mode, upfrontType: type, upfrontPercent: pct };
  }

  const fixed = toInt(raw.upfrontFixedAmount);
  if (fixed <= 0) {
    throw new HttpsError('invalid-argument', '예약금 금액을 입력해주세요.');
  }
  return { paymentMode: mode, upfrontType: type, upfrontFixedAmount: fixed };
}

/**
 * 정책 + 최종 이용요금 → 실제 금액 분해.
 *
 * **비율 예약금은 반드시 "예약 당시 최종 이용요금"으로 계산한다** — 숙박일수·
 * 요일별 가격·옵션이 반영된 뒤의 금액이어야 하므로, 호출부는 자기 도메인의
 * 금액 계산을 모두 끝낸 값을 넘겨야 한다.
 *
 * @param {object|null} policy      normalizePolicy 결과
 * @param {number|null} totalAmount 최종 이용요금. 확정 불가면 null.
 * @returns {object} 아래 필드를 가진 분해 결과
 *   paymentMode      정책 없으면 null
 *   totalAmount      확정 불가면 null
 *   upfrontAmount    지금 받을 예약금(선결제면 전액, 현장결제면 0)
 *   remainingAmount  현장에서 받을 잔금. 총액 미확정이면 null
 *   paymentAmount    payment 맵에 실을 금액(buildPaymentInfo의 amount)
 */
function computeBreakdown(policy, totalAmount) {
  // ⚠ Number(null) === 0 이다 — null을 그대로 Number로 넘기면 "총액 미확정"이
  //   "0원"으로 둔갑해 잔금이 0으로 계산된다. null/undefined를 먼저 걸러낸다.
  const known =
    totalAmount != null &&
    Number.isFinite(Number(totalAmount)) &&
    Number(totalAmount) >= 0;
  const total = known ? Math.floor(Number(totalAmount)) : null;

  // legacy — 지금까지와 동일하게 "전액이 이 결제의 금액"이다.
  // 실제로 지금 내는지(무통장) 현장에서 내는지(현장결제)는 구매자가 고른
  // 수단이 정하고, 그건 payment.status가 이미 표현한다.
  if (!policy || !policy.paymentMode) {
    return {
      paymentMode: null,
      totalAmount: total,
      upfrontAmount: null,
      remainingAmount: null,
      paymentAmount: total ?? 0,
    };
  }

  const mode = policy.paymentMode;

  if (mode === MODE.prepaid) {
    return {
      paymentMode: mode,
      totalAmount: total,
      upfrontAmount: total ?? 0,
      remainingAmount: 0,
      paymentAmount: total ?? 0,
    };
  }

  if (mode === MODE.onsite) {
    return {
      paymentMode: mode,
      totalAmount: total,
      upfrontAmount: 0,
      // 현장결제는 총액 전부가 현장에서 나간다. 총액을 모르면 숫자를 지어내지 않는다.
      remainingAmount: total,
      // payment.amount는 "현장에서 받을 금액"으로 남긴다(기존 on_site 동작 그대로).
      paymentAmount: total ?? 0,
    };
  }

  // partial — 예약금 + 잔금
  let upfront;
  if (policy.upfrontType === UPFRONT_TYPE.percentage) {
    if (!known) {
      // normalizePolicy가 막아주지만, 옛 문서/수기 수정으로 여기 닿을 수 있다.
      throw new HttpsError(
        'failed-precondition',
        '총 이용금액을 알 수 없어 비율 예약금을 계산할 수 없어요.',
      );
    }
    upfront = Math.round((total * policy.upfrontPercent) / 100);
  } else {
    upfront = toInt(policy.upfrontFixedAmount);
  }

  // 예약금이 총액을 넘지 못하게 자른다 — 넘으면 잔금이 음수가 된다.
  if (known) upfront = Math.min(upfront, total);
  upfront = Math.max(0, upfront);

  return {
    paymentMode: mode,
    totalAmount: total,
    upfrontAmount: upfront,
    // 총액 미확정이면 잔금은 **모른다**. 0으로 적으면 "더 낼 돈이 없다"는
    // 거짓말이 되고, 총액으로 적으면 이중청구로 보인다.
    remainingAmount: known ? total - upfront : null,
    paymentAmount: upfront,
  };
}

/**
 * 예약 문서에 남길 **금액 스냅샷**.
 *
 * 호스트가 나중에 비율이나 가격을 바꿔도 이미 만들어진 예약의 금액은 변하면
 * 안 된다. 그래서 예약 생성 시점의 정책값까지 통째로 복사해 둔다 — 이후 어떤
 * 화면도 호스트 설정을 다시 읽어 재계산하지 않는다.
 */
function snapshotOf(policy, totalAmount) {
  const b = computeBreakdown(policy, totalAmount);
  const snap = {
    paymentMode: b.paymentMode,
    totalAmount: b.totalAmount,
    upfrontAmount: b.upfrontAmount,
    remainingAmount: b.remainingAmount,
  };
  if (policy && policy.paymentMode === MODE.partial) {
    snap.upfrontType = policy.upfrontType;
    if (policy.upfrontType === UPFRONT_TYPE.percentage) {
      snap.upfrontPercent = policy.upfrontPercent;
    } else {
      snap.upfrontFixedAmount = policy.upfrontFixedAmount;
    }
  }
  return snap;
}

/**
 * 구매자가 고른 결제수단이 호스트 정책에 맞는지 검사한다.
 *
 * 클라이언트가 정책을 무시하고 `on_site`를 보내면 예약금을 한 푼도 내지 않고
 * 자리를 잡을 수 있으므로, 서버가 반드시 다시 본다.
 */
function assertMethodAllowed(policy, method) {
  const mode = policy && policy.paymentMode;
  const allowed = allowedMethodsFor(mode);
  if (!method || !allowed.includes(method)) {
    if (mode === MODE.onsite) {
      throw new HttpsError('failed-precondition', '이 예약은 현장결제만 가능해요.');
    }
    if (mode === MODE.prepaid || mode === MODE.partial) {
      throw new HttpsError(
        'failed-precondition',
        mode === MODE.prepaid
          ? '이 예약은 전액 선결제만 가능해요.'
          : '이 예약은 예약금 결제만 가능해요.',
      );
    }
    throw new HttpsError('invalid-argument', '지원하지 않는 결제수단이에요.');
  }
}

/**
 * 클라이언트가 보낸 금액이 서버 계산과 일치하는지 검사한다(선택적).
 *
 * 금액은 원래 서버가 계산한 값만 쓰므로 이 함수가 없어도 위조는 불가능하다.
 * 다만 앱이 화면에 띄운 금액과 서버 계산이 어긋난 채로 결제가 진행되면
 * "60,000원이라더니 80,000원이 찍혔다"가 되므로, 앱이 자기가 계산한 값을
 * 함께 보내면 여기서 대조해 **다르면 진행을 막는다**.
 */
function assertClientAmountMatches(breakdown, claimed) {
  if (claimed == null || typeof claimed !== 'object') return;
  const pairs = [
    ['totalAmount', breakdown.totalAmount],
    ['upfrontAmount', breakdown.upfrontAmount],
    ['remainingAmount', breakdown.remainingAmount],
  ];
  for (const [key, server] of pairs) {
    if (claimed[key] == null) continue;
    if (server == null) continue;
    if (toInt(claimed[key]) !== toInt(server)) {
      throw new HttpsError(
        'failed-precondition',
        '금액이 변경되었어요. 화면을 새로고침한 뒤 다시 시도해주세요.',
      );
    }
  }
}

/**
 * 이 건에서 **실제로 결제된 금액** — 환불 상한의 기준이다.
 *
 * 결제가 확인되지 않았으면(입금대기·현장결제 예정 등) 0원이다. 돈이 들어오지
 * 않았는데 환불액을 계산하면 장부가 어긋난다.
 *
 * @param {object|null} payment       문서의 payment 맵
 * @param {object|null} amountSnapshot snapshotOf 결과(없으면 payment.amount)
 */
function paidAmountOf(payment, amountSnapshot = null) {
  if (!payment || payment.status !== 'paid') return 0;
  // 예약금 건은 payment.amount가 곧 예약금(=실제 받은 돈)이다.
  const fromPayment = toInt(payment.amount);
  if (fromPayment > 0) return fromPayment;
  if (amountSnapshot && amountSnapshot.upfrontAmount != null) {
    return toInt(amountSnapshot.upfrontAmount);
  }
  return 0;
}

module.exports = {
  MODE,
  MODES,
  UPFRONT_TYPE,
  UPFRONT_TYPES,
  METHODS_BY_MODE,
  LEGACY_METHODS,
  allowedMethodsFor,
  pickPolicyFields,
  normalizePolicy,
  computeBreakdown,
  snapshotOf,
  assertMethodAllowed,
  assertClientAmountMatches,
  paidAmountOf,
};

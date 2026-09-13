const { HttpsError } = require('firebase-functions/v2/https');

/**
 * 파티 신청·플레이스 방문예약·장소대여·파티샵 주문이 함께 쓰는 **결제 정보**
 * 서버 규칙. 앱의 lib/models/payment_method.dart · payment_status.dart와 키가
 * 1:1로 맞다.
 *
 * 핵심 원칙 두 가지.
 * 1. **수단은 클라이언트가 고르고, 상태는 서버가 정한다.** 앱이 보낸 status는
 *    통째로 버린다(그렇지 않으면 'paid'를 보내 결제한 척할 수 있다).
 * 2. PG 계약 전이라 열려 있는 수단은 무통장입금·현장결제뿐이다. 나머지 수단이
 *    들어오면 거절한다 — 준비중인 수단으로 주문이 생기면 안 된다.
 */

/** 지금 실제로 받을 수 있는 결제수단. PG가 붙으면 여기에 추가한다. */
const ENABLED_METHODS = ['bank_transfer', 'on_site'];

/** 앱이 '준비중'으로 보여주는 수단들 — 들어오면 명확히 거절한다. */
const PREPARING_METHODS = ['card', 'transfer', 'virtual_account', 'easy_pay'];

/** 수단 → 만들어질 결제 상태. 결제완료(paid)는 여기서 절대 나오지 않는다. */
const INITIAL_STATUS = {
  bank_transfer: 'awaiting_deposit', // 입금대기
  on_site: 'on_site_scheduled', // 현장결제 예정
};

const { DEPOSIT_WINDOW_MS, depositDeadlineMs, STATUS } = require('./depositFlow');
const { assertBankTransferPayable } = require('./payoutAccounts');

// 입금 계좌 상수(카카오뱅크 3333-…-파티츄)는 **없앴다**.
//
// 그 값은 파티츄 공용 계좌 자리표시자였는데, 실제로는 입금 확인을 호스트가
// 하고(partyDeposits.js 등) 돈도 호스트가 받는다 — 안내 계좌만 플랫폼 것으로
// 남아 있어 "누구에게 보낸 돈인지"가 코드마다 달랐다.
//
// 이제 무통장입금 계좌는 **그 콘텐츠 호스트의 인증된 수취계좌** 하나뿐이고
// (users/{uid}.payoutAccount), 호출부가 그 스냅샷을 넘긴다. 넘어오지 않으면
// 무통장입금 자체를 거절한다 — 폴백을 두면 계좌를 등록하지 않은 호스트의
// 파티에서 엉뚱한 계좌가 다시 안내된다.

/**
 * 클라이언트가 보낸 payload에서 문서에 저장할 payment 맵을 만든다.
 *
 * @param {object|undefined} raw  request.data.payment
 * @param {object} opts
 * @param {number} opts.amount    서버가 계산한 실제 금액(원). 0이면 결제 없음.
 * @param {number} [opts.nowMs]   기준 시각(테스트용).
 * @param {boolean} [opts.requireApproval]
 *   승인이 나야 입금을 요구하는 흐름인지(플레이스 방문예약의 **승인제** 매장).
 *   true면 무통장입금은 '승인대기'로 시작하고, 승인되는 순간 서버가
 *   '입금대기'로 바꾸며 기한을 시작한다([depositFlow.approvePatch]).
 *   PG 없이 선입금을 받으면 거절 시 계좌로 수동 환불해야 하므로 기본 정책이다.
 * @param {number|null} [opts.useAtMs]
 *   이용 시각(방문 시각 등). 입금기한이 이 시각을 넘지 않게 자른다.
 * @param {{bankName:string, accountNumber:string, accountHolder:string}|null}
 *   [opts.payoutAccount]
 *   이 콘텐츠 **호스트의 인증된 수취계좌** 스냅샷
 *   ([payoutAccounts.loadPayoutSnapshot]). 무통장입금이면 반드시 있어야 하고,
 *   없으면 여기서 거절한다. 인증되지 않은 계좌는 애초에 스냅샷이 나오지 않는다.
 * @returns {object|null} 저장할 payment 맵. 결제가 필요 없으면 null.
 */
function buildPaymentInfo(
  raw,
  {
    amount,
    nowMs = Date.now(),
    requireApproval = false,
    useAtMs = null,
    payoutAccount = null,
  },
) {
  // 무료면 결제 정보 자체를 남기지 않는다 — 빈 결제 상태가 목록에 뜨지 않게.
  if (!amount || amount <= 0) return null;

  if (!raw || typeof raw !== 'object') {
    throw new HttpsError('invalid-argument', '결제수단을 선택해주세요.');
  }

  const method = raw.method;
  if (PREPARING_METHODS.includes(method)) {
    throw new HttpsError('failed-precondition', '현재 준비 중인 결제수단입니다.');
  }
  if (!ENABLED_METHODS.includes(method)) {
    throw new HttpsError('invalid-argument', '지원하지 않는 결제수단이에요.');
  }

  // 상태는 서버가 수단에서 유도한다 — 클라이언트의 status는 읽지 않는다.
  // 승인제 매장의 무통장입금만 '승인대기'로 시작한다(현장결제는 승인 여부와
  // 무관하게 방문해서 내므로 그대로 '현장결제 예정').
  const status =
    requireApproval && method === 'bank_transfer'
      ? STATUS.awaitingApproval
      : INITIAL_STATUS[method];

  const info = {
    method,
    status,
    amount,
    createdAtMs: nowMs,
  };

  if (method === 'bank_transfer') {
    // 계좌부터 확인한다 — 받을 계좌가 없으면 입금자명도 기한도 의미가 없다.
    assertBankTransferPayable(method, payoutAccount);

    const name = typeof raw.depositorName === 'string' ? raw.depositorName.trim() : '';
    if (name) info.depositorName = name.slice(0, 40);
    // 기한은 서버 시각 기준으로 다시 계산한다(앱 시계를 믿지 않는다).
    // 승인제는 아직 입금을 요구하지 않으므로 기한도 승인 시점에 시작된다.
    if (status === 'awaiting_deposit') {
      info.depositDeadlineMs = depositDeadlineMs(nowMs, { notAfterMs: useAtMs });
    }
    // 안내한 계좌를 문서에 그대로 박아 둔다(스냅샷) — 호스트가 나중에 계좌를
    // 바꿔도 이미 안내받은 건은 그때 계좌를 그대로 보여줘야, 참가자가 자기
    // 이체내역과 대조할 수 있다.
    info.bankName = payoutAccount.bankName;
    info.accountNumber = payoutAccount.accountNumber;
    info.accountHolder = payoutAccount.accountHolder;
    // 이 계좌의 주인 — 환불 처리 주체가 누구인지 문서만 보고 알 수 있게 한다.
    if (payoutAccount.hostUid) info.payoutHostUid = payoutAccount.hostUid;
  }

  return info;
}

module.exports = {
  ENABLED_METHODS,
  PREPARING_METHODS,
  INITIAL_STATUS,
  DEPOSIT_WINDOW_MS,
  buildPaymentInfo,
};

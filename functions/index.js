const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule }         = require('firebase-functions/v2/scheduler');
const { onDocumentWritten, onDocumentCreated } = require('firebase-functions/v2/firestore');
const { defineSecret }       = require('firebase-functions/params');
const functionsV1 = require('firebase-functions/v1');
const admin  = require('firebase-admin');
const https  = require('https');
const crypto = require('crypto');
const {
  computeAppliedFee,
  computeAppliedFeeForRounds,
  computeRefund,
  snapshotRefundPolicy,
  effectiveRefundPolicy,
  reserveApplicantSlot,
  releaseApplicantSlot,
  applicationDocId,
} = require('./partyCapacity');
// "이 취소 요청은 어느 신청 문서를 말하는가" — 회차별 신청이 생기면서
// 세 갈래(회차 지정 / 옛 uid 문서 / 회차를 못 보내는 구버전 앱)로 갈린
// 판정이다. 규칙과 그 이유는 partyApplicationTargets.js 상단 주석에 있다.
const {
  needsCandidateLookup,
  resolveCancelTarget,
} = require('./partyApplicationTargets');
// 호스트 결제 정책(전액 선결제 / 예약금 / 현장결제)과 실결제액 계산.
// 여기의 'upfront'는 예약금이고, depositFlow의 'deposit'은 무통장입금이다 —
// 두 단어를 섞지 말 것(paymentPolicy.js 상단 주석 참고).
const paymentPolicy = require('./paymentPolicy');
// 정기 파티(scheduleType: 'recurring')의 "지금 기준 다음 회차" 계산 —
// 취소 가능 여부/환불처럼 시각에 걸린 판정에서는 저장된 partyDateTime(등록
// 시점의 첫 회차 캐시)이 아니라 이 값을 써야 한다. 규칙은 partySchedule.js 참고.
const {
  effectivePartyStartAt,
  isRecurringParty,
  occurrenceForId,
  // 만료 자동 삭제의 기준점 — "이 파티가 다시는 열리지 않는 때".
  finalPartyEndAt,
} = require('./partySchedule');
// 최소 모집 인원 미달 자동 취소 — 판정 규칙과 알림 문서 모양은
// partyMinCapacity.js 한 곳에 있다(클라이언트 PartyCapacityStatus와 동일 규칙).
const {
  isAutoCancelCandidate,
  partyMinCapacityOf,
  confirmedCountOf,
  autoCancelFields,
  dueOccurrencesOf,
  occurrenceCancelFields,
  notificationDoc,
  MIN_CAPACITY_NOT_MET,
} = require('./partyMinCapacity');
// "1명의 실사용자 = 파티츄 계정 1개" 정책 — NICE CI를 계정과 1:1로 묶는다.
// 구/신 인증 경로(niceIntcResult / niceAuthResult)가 같은 헬퍼를 쓰도록 해서
// 한쪽만 열려 있는 우회 경로가 생기지 않게 한다.
const { linkIdentityAndSaveVerification } = require('./identityLink');
// 휴대폰번호 표기 정규화 — 신 경로(niceAuth.js)와 **같은 함수**를 쓴다.
// 두 경로가 저장하는 모양이 갈라지면 관리자 화면이 계정마다 다른 형식을
// 그리게 되고, 나중에 번호로 조회하는 기능을 붙일 때 한쪽이 통째로 빠진다.
const { normalizeKoreanMobile } = require('./phoneNumber');
// 결제수단·결제상태는 네 도메인(파티 신청·방문예약·장소대여·파티샵)이 같은
// 규칙을 쓴다 — 수단은 클라이언트가 고르고 **상태는 서버가 정한다**.
const { buildPaymentInfo } = require('./paymentInfo');
// 호스트 수취계좌 — 무통장입금 안내 계좌는 이 값 하나에서만 나온다.
const { loadPayoutSnapshot } = require('./payoutAccounts');
// 게스트 환불계좌 — 무통장입금으로 신청하려면 **돌려받을 계좌**가 인증돼
// 있어야 한다. 위 수취계좌(호스트가 받을 계좌)와는 주인도 용도도 다르다.
// 신청자 문서는 applyToParty가 본인확인 게이트를 위해 이미 읽으므로
// loadRefundAccountOwner를 다시 부르지 않는다 — 판정 함수만 가져온다.
// 취소 흐름은 환불 요청에 박을 **인증된 계좌 스냅샷**을 여기서 뜬다.
const {
  assertRefundAccountVerified,
  loadVerifiedRefundSnapshot,
} = require('./refundAccountVerify');
// 승인제 파티의 사전질문 정의·답변 검증. 금지 개인정보 질문을 **실제로 막는**
// 판정도 여기 있다 — 파티 문서의 질문 필드는 규칙상 클라이언트가 못 쓰고
// setPartyApplicationForm만 쓸 수 있으므로 이 모듈이 유일한 관문이다.
const applicationQuestions = require('./applicationQuestions');
// 호스트에게 보여줄 신청자 신원(닉네임·실명·성별·생년월일) 조립 — 파티별
// 신청자 화면(getApplicants)과 통합 신청자 관리(getHostApplicationInbox)가
// 같은 규칙을 쓴다.
const { buildApplicantIdentity } = require('./applicantIdentity');
// 통합 신청자·예약자 관리의 판정들(미처리 여부·회차 날짜·건수 상한).
// Firestore를 모르는 순수 함수라 selfcheck로 그대로 확인된다.
const hostInbox = require('./hostInbox');
// 본인확인 게이트 — 거래성 요청은 앱 UI와 무관하게 서버가 직접 확인한다.
const { assertIdentityVerifiedData } = require('./identityGuard');
// 무통장입금 상태 머신 — 승인제는 승인이 나야 입금을 요구한다
// (awaiting_approval → 호스트 승인 → awaiting_deposit).
const depositFlow = require('./depositFlow');
// 참가자 환불계좌 — 호스트 수취계좌(users/{uid}.payoutAccount)·정산계좌
// (users/{uid}.settlementInfo) 어느 쪽과도 주인도 용도도 다른 별개 정보다.
// 세 계좌의 구분은 payoutAccounts.js / refundAccounts.js 상단 주석 참고.
// 계좌 값 자체는 **인증된 것 하나뿐**이라 클라이언트가 보낸 값을 정규화하던
// normalizeRefundAccount는 더 이상 쓰지 않는다(refundAccountVerify가 정본).
const {
  requiresRefundAccount,
  buildRefundRequest,
} = require('./refundAccounts');

admin.initializeApp();

// ── KST(Asia/Seoul, UTC+9, DST 없음) 날짜/시간 헬퍼 ──────────────────────────
// 통계 집계는 전부 한국 기준 날짜/요일/시간대를 써야 "오늘"/"저녁 시간대" 같은
// 지표가 실제 사용자 체감과 맞는다. Cloud Functions 런타임은 UTC로 동작하므로
// 매번 이 헬퍼로 변환한다.
const KST_OFFSET_MS = 9 * 60 * 60 * 1000;

function kstDateKey(date) {
  const kst = new Date(date.getTime() + KST_OFFSET_MS);
  const y = kst.getUTCFullYear();
  const m = String(kst.getUTCMonth() + 1).padStart(2, '0');
  const d = String(kst.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function kstParts(date) {
  const kst = new Date(date.getTime() + KST_OFFSET_MS);
  const utcDay = kst.getUTCDay(); // 0=일 ~ 6=토
  return {
    dateKey: kstDateKey(date),
    hour: kst.getUTCHours(),
    dayOfWeek: utcDay === 0 ? 7 : utcDay, // 1=월 ~ 7=일로 변환
  };
}

// NICE 통합인증 — 공식 REST API 가이드 기준 재구현 (기존 niceIntc* 로직과 분리)
Object.assign(exports, require('./niceAuth'));

// 카카오·네이버 로그인용 Firebase 커스텀 토큰 발급 — Firebase Auth가 두 제공자를
// 기본 지원하지 않아 서버가 소셜 액세스 토큰을 검증한 뒤 토큰을 만들어준다.
// 자세한 보안 원칙은 socialAuth.js 상단 주석 참고.
Object.assign(exports, require('./socialAuth'));

// 공유 링크(partychu.co.kr/party/{id}) 서버 렌더 랜딩 페이지 — OG 태그 등
// 자세한 설계 이유는 partyLandingPage.js 상단 주석 참고.
Object.assign(exports, require('./partyLandingPage'));

// 장소대여 예약(시간제/패키지) 생성·결제검증·취소·자동만료 — 자세한 설계
// 이유는 placeReservations.js 상단 주석 참고.
Object.assign(exports, require('./placeReservations'));

// 숙박+파티 패키지 통합 예약/결제 — packageBookingEnabled인 콤보에서만
// 쓰인다. 자세한 설계 이유는 packageBookings.js 상단 주석 참고.
Object.assign(exports, require('./packageBookings'));

// 플레이스(events) 무료 방문 예약 — 결제 없이 "몇 시에 몇 명 갈게요"를 신청하고
// 업주가 승인한다. 장소대여의 공간 예약(placeReservations)과는 별개 컬렉션·별개
// 기능이다. 자세한 설계 이유는 placeVisitReservations.js 상단 주석 참고.
Object.assign(exports, require('./placeVisitReservations'));

// 파티 신청의 무통장입금 흐름 — 참가자 '입금했어요' → 호스트 '입금 확인' →
// 확정, 기한이 지난 입금대기는 자동 정리. 결제 상태(payment.status)와 신청
// 상태(status)를 끝까지 분리해서 다룬다(자세한 설계는 partyDeposits.js 주석).
Object.assign(exports, require('./partyDeposits'));

// 플레이스 상품·이용권 주문(결제 검증 + QR 사용 처리) — 술집·바·카페와
// 공간대여·숙박이 같은 상품 구조를 공유한다. placeReservations와 동일한
// 4단 구조를 따르며, 자세한 설계 이유는 placeProductOrders.js 상단 주석 참고.
Object.assign(exports, require('./placeProductOrders'));

// 통합 QR 체크인 — 호스트에게 스캐너는 하나뿐이고, QR 종류(파티/예약/이용권)
// 판별과 권한 검증, 정보 조합을 전부 서버가 한다. 조회와 사용 처리를 분리해
// "스캔 = 소진"이 되지 않게 한다(자세한 설계는 checkInTokens.js 상단 주석).
Object.assign(exports, require('./checkInTokens'));

// QR 발급·무효화 트리거 — 파티는 신청이 확정될 때, 예약은 예약이 확정될 때
// 토큰이 생기고 취소·거절·만료되면 그 자리에서 죽는다. 콜러블마다 발급을
// 붙이지 않고 문서의 최종 상태만 보는 이유는 각 파일 상단 주석 참고.
// (파티 트리거는 현장 출석 통계도 함께 옮겨 왔다 — checkedInAt이 정본이다.)
Object.assign(exports, require('./partyCheckIn'));
Object.assign(exports, require('./reservationCheckIn'));

// 파티 참여 후기 — 작성 자격(checkedInAt)·작성 기간(그 게스트가 참여한 회차
// 종료 + 14일)을 전부 서버가 판정한다. 후기는 파티 하위가 아니라 독립 루트
// 컬렉션이라 파티 자동삭제(14일)에도 남는다 — 자세한 이유는 partyReviews.js
// 상단 주석 참고.
Object.assign(exports, require('./partyReviews'));
// 상품은 현장결제 주문만 결제 전에 QR을 갖는다 — checkInToken(조회용 식별자)과
// voucherCode(결제 후 이용권)의 역할이 어떻게 갈리는지는 productCheckIn.js 참고.
Object.assign(exports, require('./productCheckIn'));

// 파티샵 상품 주문 — 예전의 더미 결제 + 클라이언트 직접 'paid' 쓰기를
// 대체한다. 자세한 배경은 shopOrders.js 상단 주석 참고.
Object.assign(exports, require('./shopOrders'));

// 환불 요청 큐의 운영자 처리(송금 완료/반려) — 자동 송금이 없어 사람이 넘긴다.
// 접수는 cancelApplication이 하고, 상태 변경은 이 함수만 한다.
Object.assign(exports, require('./refundRequests'));

// 채팅 자동 안내 문구 발송 — 예전에는 게스트 기기가 호스트 uid를 senderId로
// 박아 직접 썼다. 그 구조 때문에 규칙이 senderId를 uid()로 못 박지 못했다.
// 이제 Admin SDK로만 만들어진다. 자세한 배경은 chatAutoMessages.js 상단 주석 참고.
Object.assign(exports, require('./chatAutoMessages'));

// 채팅방 **생성** — 문의 권한(inquiryEnabled)이나 실제 예약 관계를 서버가
// 직접 확인한 뒤에만 만든다. 규칙은 쿼리를 할 수 없어 예약 여부를 볼 수
// 없으므로 이 판정은 여기서만 가능하다(chatRooms.js 상단 주석 참고).
// __helpers는 셀프체크용이라 통째로 붙이지 않는다.
exports.createChatRoom = require('./chatRooms').createChatRoom;

// 닉네임 설정/변경 — 중복 방지가 트랜잭션으로만 성립하므로 서버 전용이다.
// (firestore.rules가 users.nickname과 nicknames 컬렉션을 클라이언트로부터
//  잠근다 — 앱에서만 검사하면 REST로 직접 써서 우회할 수 있다.)
exports.setNickname = require('./nicknames').setNickname;
exports.checkNicknameAvailable = require('./nicknames').checkNicknameAvailable;

// 사업자 인증(국세청 진위확인·상태조회)과 파티 오픈예정→모집중 전환.
// 두 모듈 모두 콜러블 외에 순수 헬퍼도 export하므로 Object.assign으로
// 통째로 붙이지 않는다(위 memberActivityHelpers 주석과 같은 이유).
exports.verifyBusinessRegistration =
  require('./businessVerification').verifyBusinessRegistration;

// 대표자 위임 — 본인 명의가 아닌 사업자를 대표자 승인으로 여는 경로.
//
// ⚠️ businessApprovalPage는 **로그인 없이** 열리는 웹 엔드포인트다(대표자는
//    파티츄 회원이 아닐 수 있다). 권한은 링크가 아니라 NICE 본인확인 결과가
//    준다 — businessDelegation.js의 evaluateApproval 12개 검사 참고.
//    NICE IP 화이트리스트를 통과해야 하므로 VPC 커넥터를 타고 나간다.
const businessDelegation = require('./businessDelegation');
exports.requestBusinessDelegation = businessDelegation.requestBusinessDelegation;
exports.getBusinessDelegationStatus = businessDelegation.getBusinessDelegationStatus;
exports.businessApprovalPage = businessDelegation.businessApprovalPage;

// 호스트 사전등록(FormHug 신청서 → 관리자 처리). 권한은 만들지 않는다 —
// 사업자 권한은 위 verifyBusinessRegistration / 대표자 위임 흐름이 그대로
// 정하고, 관리자 대표자 링크도 createDelegationRequest를 그대로 부른다.
// hostPreRegistration.js 상단 주석 참고.
const hostPreRegistration = require('./hostPreRegistration');
exports.hostPreRegistrationWebhook = hostPreRegistration.hostPreRegistrationWebhook;
exports.adminGetHostPreRegistration = hostPreRegistration.adminGetHostPreRegistration;
exports.adminUpdateHostPreRegistration = hostPreRegistration.adminUpdateHostPreRegistration;
exports.adminCreateBusinessDelegationForPreregistration =
  hostPreRegistration.adminCreateBusinessDelegationForPreregistration;
exports.adminHostPreRegistrationFormSetup = hostPreRegistration.adminHostPreRegistrationFormSetup;
exports.onBusinessDelegationWriteSyncPreRegistration =
  hostPreRegistration.onBusinessDelegationWriteSyncPreRegistration;

// 호스트 수취계좌 인증(팝빌 예금주조회) — 참가자가 무통장입금할 계좌가
// 실제 그 호스트의 계좌인지 확인한다. 인증 상태는 서버만 기록한다
// (클라이언트 쓰기는 firestore.rules가 막는다). payoutAccounts.js 참고.
exports.verifyPayoutAccount = require('./payoutAccounts').verifyPayoutAccount;
exports.getPayoutAccountStatus =
  require('./payoutAccounts').getPayoutAccountStatus;
// 게스트 환불계좌 인증 — 위 수취계좌와 **같은 엔진, 다른 필드**다
// (refundAccountVerify.js). 무통장입금으로 낸 돈을 돌려받을 본인 계좌라
// 사업자 명의 갈래 없이 언제나 본인 명의로만 인증된다.
exports.verifyRefundAccount =
  require('./refundAccountVerify').verifyRefundAccount;
exports.openPartyRecruiting =
  require('./partyOpenState').openPartyRecruiting;

// 파티 등록(웹) — 웹 홈페이지의 유일한 파티 쓰기 경로.
//
// 앱은 지금도 Firestore에 직접 쓰지만, 조립·검증 규칙 자체는
// partyRegistration.js 한 곳에 있고 골든 픽스처로 앱과 묶여 있다
// (docs/party-registration-parity.md). 그래서 앱과 웹이 각자 계산해 결과가
// 달라지는 일이 생기지 않는다.
exports.createParty = require('./createParty').createParty;

// 매장 이벤트 신청 — **서버가 정본**이다. firestore.rules가 신청 문서의
// 클라이언트 쓰기를 전부 막고(parties/{id}/applications와 같은 보호 패턴),
// 신청·취소는 이 콜러블만 한다. 종료된 이벤트 차단처럼 시간이 걸린 판정을
// rules로 흉내 내면 앱과 어긋나기 때문이다(placeEventApplications.js 상단 주석).
//
// onPlacePromotionDeleted는 이벤트가 지워질 때 남은 신청서를 치우는 트리거다 —
// 아무도 신청 문서를 지울 수 없으므로 이게 없으면 영영 고아로 남는다.
// 순수 헬퍼도 함께 내보내는 모듈이라 Object.assign으로 붙이지 않는다.
const placeEventApplications = require('./placeEventApplications');
exports.applyToPlaceEvent = placeEventApplications.applyToPlaceEvent;
exports.cancelPlaceEventApplication =
  placeEventApplications.cancelPlaceEventApplication;
exports.getPlaceEventApplicants =
  placeEventApplications.getPlaceEventApplicants;
exports.onPlacePromotionDeleted =
  placeEventApplications.onPlacePromotionDeleted;

// 파티 신청이 생기면 호스트에게 알림 한 건 — 예약 3종에는 원래 있고 파티에만
// 없던 알림이다. **applyToParty 트랜잭션이 아니라 문서 생성 트리거**로 받는
// 이유(재시도 중복 발송)는 partyApplicationNotifications.js 상단 주석 참고.
// 같은 모듈이 순수 헬퍼(notifyHostDepositSent)도 내보내므로 Object.assign으로
// 통째로 붙이지 않는다.
exports.onPartyApplicationCreated =
  require('./partyApplicationNotifications').onPartyApplicationCreated;

// 콘텐츠 삭제(파티·장소·플레이스·파티샵·파트너) — 앱의 모든 삭제 버튼이
// 거치는 단 하나의 경로다. 클라이언트는 규칙상 신청·예약·주문 컬렉션을 지울
// 수 없으므로 삭제는 반드시 여기를 통해야 한다. 자세한 배경은
// contentDelete.js 상단 주석 참고.
Object.assign(exports, require('./contentDelete'));

// 통합 회원 관리(활동 배지·userStats 확장·통합 활동 타임라인) — 자세한 설계
// 이유는 memberManagement.js 상단 주석 참고. 공용 헬퍼는 memberActivityHelpers.js
// 에서 직접 가져온다(partyCapacity.js와 동일하게 순수 헬퍼 모듈은 항상
// 구조분해로만 참조 — Object.assign(exports,...) 대상은 Cloud Functions만).
Object.assign(exports, require('./memberManagement'));
Object.assign(exports, require('./crmExportFunction'));

// 관리자 채팅 열람 — chatRooms/messages는 개인 간 대화라 규칙을 관리자에게
// 열지 않는다. 이 두 onCall(Admin SDK)만이 유일한 열람 통로이고, 열람할 때마다
// userActivityLogs에 감사 로그를 남긴다. 자세한 배경은 adminChatViewer.js 상단 주석.
Object.assign(exports, require('./adminChatViewer'));

// 관리자 판매 통계 — 신청/예약 문서를 **읽어 넘기기만** 하는 콜러블이다.
// 합계는 서버에서 내지 않는다: 매출 계산이 JS와 Dart 두 벌이 되면 한쪽만
// 고쳐졌을 때 호스트 화면과 관리자 화면의 금액이 갈리기 때문이다. 계산은
// packages/partychu_sales(Dart) 한 곳이 정본이다. adminSalesStats.js 상단 주석 참고.
Object.assign(exports, require('./adminSalesStats'));

// 푸시 토큰(기기) 등록/해제 — users/{uid}/devices 서브컬렉션은 규칙이
// 클라이언트 쓰기를 막아두었고, 계정 전환 시 "다른 사용자 밑에 남은 같은 토큰"을
// 지우려면 서버 권한이 필요하다. 자세한 배경은 pushTokens.js 상단 주석.
Object.assign(exports, require('./pushTokens'));

// 알림 문서/채팅 메시지를 실제 푸시로 바꾸는 트리거. 알림을 만드는 쪽에 발송
// 호출을 심지 않고 문서 생성 트리거로 받는 이유(트랜잭션 재시도 중복 발송)는
// pushDispatch.js 상단 주석 참고.
Object.assign(exports, require('./pushDispatch'));

// 관리자 업무 알림(adminNotifications) — 호스트 사전등록 신청이 접수되면
// 관리자 웹 상단 종에 뜨게 한다. 사용자 알림(notifications)과 컬렉션부터
// 분리한 이유, 기존 신청서에 소급 알림이 생기지 않게 막는 두 겹은
// adminNotifications.js 상단 주석 참고.
exports.onHostPreRegistrationWriteNotifyAdmin =
  require('./adminNotifications').onHostPreRegistrationWriteNotifyAdmin;

// 회원 탈퇴 — 신청(7일 대기) · 취소 · 상태 조회 · 만료분 자동 완전탈퇴.
// 완전 탈퇴는 순서가 고정이고(CI 링크 해제 → 개인정보 삭제 → … → Auth 삭제),
// 앱을 켜지 않아도 진행되도록 스케줄러가 돈다. 자세한 배경은 accountWithdrawal.js.
Object.assign(exports, require('./accountWithdrawal'));

// 안전한 미디어 업로드 경로 — 앱에 Cloudflare 자격증명을 두지 않기 위한 새
// 경로다. 서버가 "이 키 하나에, 이 크기·형식으로, 5분 안에"만 쓸 수 있는
// presigned PUT을 발급하고, 경로의 uid는 request.auth.uid를 정본으로 쓴다.
// 동영상은 Stream direct creator upload라 30초 제한이 서버 강제가 된다.
// 자세한 배경은 mediaUploads.js 상단 주석 참고.
//
// 이 모듈의 자격증명(버킷 스코프 R2 액세스 키 · Stream 전용 토큰)은 삭제·정리
// 경로도 **그대로 나눠 쓴다**([cloudflareCleanup.js]). 유출로 간주해 폐기된
// CLOUDFLARE_API_TOKEN을 읽는 코드는 이제 서버 어디에도 없다.
//
// ⚠️ 이 모듈은 Cloud Function이 아닌 순수 헬퍼도 내보내므로
//    Object.assign(exports, ...)으로 붙이면 안 된다 — 헬퍼까지 함수로
//    배포하려다 실패한다(contentCleanup.js와 같은 규칙).
const mediaUploads = require('./mediaUploads');
exports.createUploadUrl = mediaUploads.createUploadUrl;
exports.createVideoUploadUrl = mediaUploads.createVideoUploadUrl;
exports.deleteOwnUpload = mediaUploads.deleteOwnUpload;

const {
  logUserActivity,
  addActivityRole,
  bumpUserStats,
  bumpFavoriteReceivedCount,
  logScheduledFunctionError,
  isTestAccountUid,
} = require('./memberActivityHelpers');

// ── Cloudflare 미디어 삭제 헬퍼 ──────────────────────────────────────────────
// 사용자가 직접 누르는 삭제(contentDelete.js)와 아래 예약 삭제가 **같은 정리
// 코드**를 쓰도록 cloudflareCleanup.js로 뽑아냈다.
const {
  readCloudflareCreds,
  // 미디어 정리에 쓰는 시크릿 목록의 정본 — 여섯 개를 손으로 적지 않는다.
  // (CLOUDFLARE_API_TOKEN은 폐기됐다. 그 파일 상단 주석 참고.)
  MEDIA_CLEANUP_SECRETS,
} = require('./cloudflareCleanup');
// 콘텐츠 정리 규칙 — 사용자가 누르는 삭제(contentDelete.js)와 아래 만료
// 자동 삭제가 같은 함수를 쓴다. 순수 헬퍼 모듈이라 구조분해로만 참조한다.
const { cleanupContentDoc } = require('./contentCleanup');
// 이벤트가 "보이지 않게 된 시각" — 만료 판정의 기준점(앱의 goneAt과 같은 규칙).
const { promotionGoneAt } = require('./registrationLimits');

// ── 보관기간 ────────────────────────────────────────────────────────────────
//
// **등록물 네 종류와 임시저장이 전부 14일**이다. 값이 여러 곳에 흩어지면
// 한쪽만 바뀌어 화면 안내와 실제 삭제일이 어긋나므로 여기 하나로 둔다.
// 클라이언트 쪽 정본은 lib/utils/auto_delete_retention.dart의
// AutoDeleteRetention.window — 두 값은 **같아야 한다**(앱이 'D-3'이라고 써
// 놓고 서버가 이미 지운 상태가 되면 안 된다).
//
// 세는 **기준점**만 유형마다 다르다. 날짜가 있는 것은 실제 종료 시각, 날짜가
// 없는 상시 등록물은 호스트가 숨긴 시각이다.
//
//   파티(parties)             최종 종료 시각      deleteExpiredParties
//   이벤트(placePromotions)   종료일 / 숨긴 시각  deleteExpiredPromotions
//   플레이스(events)          숨긴 시각(hiddenAt) deleteExpiredEvents
//   장소대여(places)          숨긴 시각(hiddenAt) deleteExpiredPlaces
//   임시저장(drafts)          마지막 저장 시각    deleteExpiredDrafts
//
// 장소대여는 예전에 30일이었다 — 같은 성격의 등록물끼리 보관기간이 다르면
// 호스트가 어느 화면의 안내를 믿어야 할지 알 수 없어서 14일로 맞췄다.
const RETENTION_DAYS = 14;
const RETENTION_MS = RETENTION_DAYS * 24 * 60 * 60 * 1000;

// ── 만료 파티 자동 삭제 (매일 03:00 KST) ─────────────────────────────────────
//
// 기준: **최종 종료 시각**(finalPartyEndAt) + 14일 경과 & status != 'active'
//       · 일회성 — singleSchedule의 종료 시각(없으면 시작 시각 = partyDateTime)
//       · 정기   — 마지막 회차가 끝난 시각(운영 종료일 기준). 종료일이 없는
//                  무기한 정기 파티는 끝나는 때가 없어 대상이 아니다.
//
//       예전에는 partyDateTime(정기 파티에서는 **첫 회차 캐시**)에 30일을
//       더해 판정했다. 그래서 반년을 운영한 정기 파티는 마지막 회차가 끝나기도
//       전에 이미 "30일 경과" 조건을 만족해, 남은 회차가 없어지는 순간 사실상
//       곧바로 삭제 대상이 됐다. 이제 기준점이 마지막 회차 종료라 어떤 파티든
//       끝난 뒤 꼬박 14일이 보장된다.
//
// 처리: cleanupContentDoc(contentCleanup.js) — 사용자가 삭제 버튼을 눌렀을
//       때와 **완전히 같은 정리 로직**을 쓴다. 예전에는 여기서 파티 문서와
//       미디어만 지워서 applications 같은 연결 데이터가 고아로 남았다.
//       거래기록(결제된 신청서·패키지 예약)은 지우지 않고 삭제 표시와
//       스냅샷만 붙는다 — 매출·정산 집계는 그 신청 문서를 읽으므로(호스트
//       판매 통계 host_sales_service.dart) 파티가 사라져도 금액은 남는다.

exports.deleteExpiredParties = onSchedule(
  {
    schedule:  '0 3 * * *',
    timeZone:  'Asia/Seoul',
    region:    'asia-northeast3',
    secrets:   MEDIA_CLEANUP_SECRETS,
  },
  async () => {
    const db = admin.firestore();
    try {
      const cutoff = new Date(Date.now() - RETENTION_MS);
      const cutoffTs = admin.firestore.Timestamp.fromDate(cutoff);

      // 후보를 좁히는 쿼리는 그대로 partyDateTime을 본다 — 정기 파티에서
      // partyDateTime은 첫 회차 캐시라 **언제나 최종 종료보다 이르다.** 즉
      // "최종 종료 < 컷오프"이면 "partyDateTime < 컷오프"도 반드시 참이라,
      // 이 쿼리는 대상을 놓치지 않으면서 색인을 늘리지 않는다. 정확한 판정은
      // 아래 filter에서 finalPartyEndAt으로 한 번 더 한다.
      const snapshot = await db.collection('parties')
        .where('partyDateTime', '<', cutoffTs)
        .get();

      const creds = readCloudflareCreds('cleanup');

      const toDelete = snapshot.docs.filter((doc) => {
        const d = doc.data();
        // 재등록(status='active')이거나 이미 삭제된 문서는 건너뜀
        if (d.status === 'active' || d.isDeleted === true || d.status === 'deleted') {
          return false;
        }
        // 정기 파티는 저장된 partyDateTime이 "첫 회차" 캐시라 위 쿼리에
        // 걸리지만, 아직 열릴 회차가 남아 있으면 운영 중인 파티다 —
        // 지우면 안 된다(운영 종료일이 지난 정기 파티만 삭제 대상).
        if (isRecurringParty(d) && effectivePartyStartAt(d, new Date()) != null) {
          return false;
        }
        // 진짜 기준점 — 최종 종료 + 14일. 종료일 없는 무기한 정기 파티는
        // null이 나오고(끝나는 때가 없다), 그런 문서는 지우지 않는다.
        const finalEnd = finalPartyEndAt(d);
        if (finalEnd == null) return false;
        return finalEnd.getTime() < cutoff.getTime();
      });

      console.log(`[cleanup] 만료 후보 ${toDelete.length}개 / 전체 쿼리 ${snapshot.size}개`);

      // 파티 하나씩 공용 정리 로직으로 처리한다 — 연결 데이터 삭제 +
      // 거래기록 보존 + 미디어 삭제 + 본체 삭제가 여기 한 번에 들어 있다.
      // 한 건이 실패해도 나머지는 계속 진행한다(예약 작업이라 다음 실행에서
      // 다시 시도된다).
      let done = 0;
      let preserved = 0;
      for (const doc of toDelete) {
        try {
          const result = await cleanupContentDoc(
            db, 'party', doc.ref, doc.data(), creds, 'cleanup',
          );
          preserved += result.preserved;
          done++;
        } catch (e) {
          console.error(`[cleanup] 파티 정리 실패 (${doc.id}):`, e.message);
        }
      }

      console.log(
        `[cleanup] 완료 — ${done}/${toDelete.length}개 삭제, 거래기록 ${preserved}건 보존`,
      );
    } catch (e) {
      await logScheduledFunctionError(db, 'deleteExpiredParties', e);
      throw e; // Cloud Scheduler 재시도/실패 기록은 기존과 동일하게 유지
    }
  },
);

// ── 만료 임시저장 자동 삭제 (매일 03:20 KST) ─────────────────────────────────
//
// 기준: drafts.updatedAt + 14일 경과.
//
// `drafts/{uid}__{type}` 문서는 저장할 때마다 통째로 덮어써지고 updatedAt이
// 서버 시각으로 갱신된다(DraftService.saveDraft) — 그래서 "마지막 수정 기준
// 14일"이 별도 필드 없이 그대로 성립한다. 이어서 작성하다 다시 저장하면
// 기한도 함께 밀린다.
//
// **미디어는 지우지 않는다.** 임시저장 payload가 들고 있는 이미지 URL은
// `existingImageUrls` — 이미 등록된 파티/플레이스의 사진을 가리키는 값이라
// 여기서 지우면 **살아 있는 콘텐츠의 사진이 사라진다.** 새로 고른 사진은
// 업로드 전 로컬 경로(newFilePaths)로만 들어 있어 지울 원격 파일이 없다.
// 탈퇴 정리(accountWithdrawal.js의 PERSONAL_COLLECTIONS)도 drafts를 문서만
// 지운다 — 같은 규칙이다.
//
// 한 번에 지우는 양은 [SWEEP_LIMIT]로 묶는다. 이 정책이 생기기 전 문서에는
// 만료 개념이 없어 오래된 초안이 통째로 쌓여 있고, 첫 실행이 그걸 한 번에
// 쓸면 실패 시 어디까지 지웠는지도 모르는 큰 작업이 된다. 남은 건 다음 날
// 실행이 이어서 지운다(매일 도는 작업이라 며칠이면 정리된다).

const SWEEP_LIMIT = 500;

exports.deleteExpiredDrafts = onSchedule(
  {
    schedule: '20 3 * * *',
    timeZone: 'Asia/Seoul',
    region:   'asia-northeast3',
  },
  async () => {
    const db = admin.firestore();
    try {
      const cutoff = admin.firestore.Timestamp.fromDate(
        new Date(Date.now() - RETENTION_MS),
      );

      const snapshot = await db.collection('drafts')
        .where('updatedAt', '<', cutoff)
        .orderBy('updatedAt')
        .limit(SWEEP_LIMIT)
        .get();

      if (snapshot.empty) {
        console.log('[draftCleanup] 만료된 임시저장 없음');
        return;
      }

      let done = 0;
      for (let i = 0; i < snapshot.docs.length; i += 400) {
        const batch = db.batch();
        const slice = snapshot.docs.slice(i, i + 400);
        for (const doc of slice) batch.delete(doc.ref);
        await batch.commit();
        done += slice.length;
      }

      console.log(
        `[draftCleanup] 완료 — ${done}개 삭제`
        + (snapshot.size === SWEEP_LIMIT ? ' (상한에 걸림, 다음 실행에서 계속)' : ''),
      );
    } catch (e) {
      await logScheduledFunctionError(db, 'deleteExpiredDrafts', e);
      throw e;
    }
  },
);

// ── 최소 모집 인원 미달 자동 취소 (10분마다) ─────────────────────────────────
//
// 호스트가 "최소 인원 미달 시 자동 취소"를 골라 둔 파티만 대상이다. 모집
// 마감 시각을 지났는데도 **확정 인원**이 최소 모집 인원에 못 미치면 취소한다.
//
// 취소 단위가 두 가지다.
//
//  A. 일회성 파티 → 파티 문서 전체
//     1. recruitStatus:'취소' + cancelReason:'minCapacityNotMet'으로 바꾸고
//     2. 그 쓰기가 기존 onPartyCancelledByHost 트리거를 깨워 **신청 전원 취소 +
//        전액 환불(refundStatus:'pending')**로 돌린다 — 환불 경로를 새로 만들지
//        않고 호스트 취소와 똑같이 처리한다
//     3. 신청자와 호스트에게 보낼 알림을 notifications에 남긴다
//
//  B. 정기 파티 → **미달된 그 회차 하나만**
//     파티 문서의 recruitStatus는 건드리지 않는다(다른 날짜 회차는 그대로
//     열려 있어야 한다). 대신 occurrenceCancellations.{회차}에 취소를 기록하고,
//     그 회차 신청만 골라 A와 **같은 모양**으로 취소·환불 대상 처리한다.
//     신청을 막는 것은 이 기록을 보는 applyToParty 쪽이다(partyCapacity.js).
//
// "확정 인원"은 신청 문서를 직접 세어 구한다(status가 applied/approved인 것).
// 문서에 캐시된 currentParticipants는 승인 대기(pending)까지 포함한 **자리
// 예약 수**라, 승인제 파티에서 아무도 승인되지 않았는데 "다 모였다"로 보인다.
//
// 10분 주기라 마감 직후 최대 10분까지 취소가 늦어질 수 있다. 그 사이 신청이
// 들어와 최소 인원을 채우면 취소하지 않는다(조건을 실행 시점에 다시 본다).
//
// 주의: recruitStatus 등호 + recruitDeadlineAt 범위 조합이라 Firestore 복합
// 인덱스가 필요하다 — 첫 실행 로그의 링크로 만들면 된다.

/**
 * 살아 있는 신청(취소/거절이 아닌 것) 목록. 회차 취소는 이 중 그 회차 것만
 * 골라 처리하므로 status로만 좁혀 한 번에 읽는다.
 */
async function loadLiveApplications(partyRef) {
  const snap = await partyRef
    .collection('applications')
    .where('status', 'in', ['applied', 'approved'])
    .get();
  return snap.docs;
}

/**
 * 신청 한 건을 "시스템 취소 + 전액 환불 대상"으로 바꾸는 필드.
 *
 * onPartyCancelledByHost가 파티 전체 취소에서 쓰는 것과 **같은 모양**이다 —
 * 회차 취소만 다른 규칙을 쓰면 환불 화면·정산이 두 갈래가 된다. 환불률은
 * 100%지만 금액은 실제로 받은 돈을 넘지 않는다(현장결제 예정은 0원).
 */
function systemCancelApplicationFields(appData) {
  const paidAmount = paymentPolicy.paidAmountOf(appData.payment, appData.amounts);
  return {
    status: 'cancelled',
    cancelledBy: 'system',
    cancelReason: MIN_CAPACITY_NOT_MET,
    refundPercent: paidAmount > 0 ? 100 : 0,
    refundAmount: paidAmount,
    refundStatus: paidAmount > 0 ? 'pending' : 'not_applicable',
    appliedRefundTier: null,
    statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

/** 알림 수신자 모으기 — 신청자(문서 안 uid 필드) + 호스트. */
function autoCancelRecipients(applicationDocs, partyData) {
  const recipients = new Map();
  // 신청 문서 ID는 회차 신청이면 uid가 아니다(`{uid}_{회차}`) — 수신자는
  // 반드시 문서 안의 uid 필드로 잡는다(같은 사람이 여러 회차를 신청했어도
  // Map이라 알림은 한 번만 간다).
  applicationDocs.forEach((a) => recipients.set(a.data().uid || a.id, 'applicant'));
  const hostUid = partyData.hostUid || partyData.hostId || partyData.userId || partyData.createdBy;
  if (hostUid) recipients.set(hostUid, 'host');
  return recipients;
}

exports.autoCancelUnderfilledParties = onSchedule(
  {
    schedule: '*/10 * * * *',
    timeZone: 'Asia/Seoul',
    region: 'asia-northeast3',
  },
  async () => {
    const db = admin.firestore();
    let oneShotDone = 0;
    let occurrenceDone = 0;
    try {
      const now = new Date();

      // ── A. 일회성 파티 — 파티 문서 전체 취소 ───────────────────────────
      //
      // 마감이 지난 '모집중' 파티만 좁혀 읽는다. 자동 취소 여부·최소 인원은
      // 문서를 보고 판정한다(복합 인덱스를 더 늘리지 않기 위해).
      const snapshot = await db
        .collection('parties')
        .where('recruitStatus', '==', '모집중')
        .where('recruitDeadlineAt', '<=', admin.firestore.Timestamp.fromDate(now))
        .get();

      const candidates = snapshot.docs.filter((doc) =>
        isAutoCancelCandidate(doc.data(), now)
      );
      console.log(
        `[minCapacity] 일회성 후보 ${candidates.length}개 / 마감 지난 모집중 ${snapshot.size}개`
      );

      for (const doc of candidates) {
        try {
          const data = doc.data();
          const partyTitle = data.title || '파티';
          const min = partyMinCapacityOf(data);

          // 신청 문서를 먼저 읽는다 — 확정 인원이 최소를 채웠으면 취소하지
          // 않는다(마감 뒤 승인으로 채워진 경우가 여기서 걸린다).
          const applicationDocs = await loadLiveApplications(doc.ref);
          const confirmed = confirmedCountOf(applicationDocs.map((a) => a.data()));
          if (confirmed >= min) continue;

          // 파티 상태를 먼저 바꾼다 — 이 쓰기가 환불 트리거를 깨운다.
          await doc.ref.update(autoCancelFields(data, confirmed));

          const batch = db.batch();
          for (const [uid, role] of autoCancelRecipients(applicationDocs, data)) {
            batch.set(
              db.collection('notifications').doc(),
              notificationDoc({
                uid,
                partyId: doc.id,
                partyTitle,
                role,
                data,
                participants: confirmed,
              })
            );
          }
          await batch.commit();
          oneShotDone++;
        } catch (e) {
          console.error(`[minCapacity] 자동 취소 실패 (${doc.id}):`, e.message);
        }
      }

      // ── B. 정기 파티 — 미달된 회차만 취소 ──────────────────────────────
      //
      // 정기 파티는 recruitDeadlineAt을 저장하지 않는다(회차마다 마감이 새로
      // 열려서 고정 값을 둘 수 없다) — 위 A의 쿼리에 걸리지 않으므로 자동
      // 취소로 설정된 정기 파티만 따로 읽는다. minCapacityPolicy 등호 하나라
      // 단일 필드 인덱스로 충분하다.
      const recurringSnap = await db
        .collection('parties')
        .where('minCapacityPolicy', '==', 'autoCancel')
        .where('scheduleType', '==', 'recurring')
        .get();

      let dueTotal = 0;
      for (const doc of recurringSnap.docs) {
        const data = doc.data();
        const due = dueOccurrencesOf(data, now);
        if (due.length === 0) continue;
        dueTotal += due.length;

        const partyTitle = data.title || '파티';
        const min = partyMinCapacityOf(data);
        let applicationDocs;
        try {
          applicationDocs = await loadLiveApplications(doc.ref);
        } catch (e) {
          console.error(`[minCapacity] 신청 조회 실패 (${doc.id}):`, e.message);
          continue;
        }

        for (const { occurrenceId } of due) {
          try {
            const ofOccurrence = applicationDocs.filter(
              (a) => (a.data().occurrenceId || null) === occurrenceId
            );
            const confirmed = confirmedCountOf(
              ofOccurrence.map((a) => a.data()),
              occurrenceId
            );
            if (confirmed >= min) continue;

            const batch = db.batch();
            // 1) 회차 취소 기록 — 이 기록 하나가 "신청 불가"의 근거이자
            //    다음 실행에서 두 번 처리하지 않게 하는 표시다.
            batch.update(
              doc.ref,
              occurrenceCancelFields(data, occurrenceId, confirmed)
            );
            // 2) 그 회차 신청만 취소 + 환불 대상 — 파티 문서 전체 취소가
            //    아니라 onPartyCancelledByHost가 깨어나지 않으므로 여기서
            //    직접 한다(필드 모양은 그 트리거와 같다).
            for (const appDoc of ofOccurrence) {
              batch.update(appDoc.ref, systemCancelApplicationFields(appDoc.data()));
            }
            // 3) 알림 — 이 회차 신청자 + 호스트.
            for (const [uid, role] of autoCancelRecipients(ofOccurrence, data)) {
              batch.set(
                db.collection('notifications').doc(),
                notificationDoc({
                  uid,
                  partyId: doc.id,
                  partyTitle,
                  role,
                  data,
                  occurrenceId,
                  participants: confirmed,
                })
              );
            }
            await batch.commit();
            occurrenceDone++;
          } catch (e) {
            console.error(
              `[minCapacity] 회차 취소 실패 (${doc.id} / ${occurrenceId}):`,
              e.message
            );
          }
        }
      }

      console.log(
        `[minCapacity] 완료 — 일회성 ${oneShotDone}개, 회차 ${occurrenceDone}/${dueTotal}개 취소`
      );
    } catch (e) {
      await logScheduledFunctionError(db, 'autoCancelUnderfilledParties', e);
      throw e;
    }
  },
);

// ── 만료 장소 자동 삭제 (매일 03:00 KST) ─────────────────────────────────────
//
// 기준: isActive == false(숨김) & hiddenAt + 14일 경과([RETENTION_DAYS])
//       예전에는 30일이었다. 네 유형의 보관기간을 하나로 맞추면서 바뀌었고,
//       그때부터 앱 안내도 같은 상수를 읽는다(AutoDeleteRetention.window).
//       숨긴 뒤 14일 안에 다시 노출하면 hiddenAt이 지워져 대상에서 빠진다
//       (place_register_screen.dart의 수정 저장이 항상 그렇게 나간다).
// 처리: cleanupContentDoc(contentCleanup.js) — 파티와 마찬가지로 사용자가
//       삭제 버튼을 눌렀을 때와 같은 정리 로직을 쓴다. 예전에는 장소 문서와
//       하위 placeRooms만 지워서 예약 슬롯·상품·프로모션·채팅방·찜이 고아로
//       남았다. 예약·이용권 같은 거래기록은 지우지 않고 삭제 표시와 스냅샷만
//       붙는다.
// 색인: isActive==false + hiddenAt 범위 비교 조합에는 복합 색인
// `places (isActive ASC, hiddenAt ASC)`이 **반드시** 있어야 한다. 이게 없으면
// 쿼리가 FAILED_PRECONDITION으로 죽어서 만료 장소가 한 건도 정리되지 않는다
// (실제로 매일 03:00에 34일 연속 실패했다). 정의는 firestore.indexes.json에
// 있고, `firebase deploy --only firestore:indexes`로 배포해야 적용된다.

exports.deleteExpiredPlaces = onSchedule(
  {
    schedule:  '0 3 * * *',
    timeZone:  'Asia/Seoul',
    region:    'asia-northeast3',
    secrets:   MEDIA_CLEANUP_SECRETS,
  },
  async () => {
    const db = admin.firestore();
    try {
      const cutoff = new Date(Date.now() - RETENTION_MS);
      const cutoffTs = admin.firestore.Timestamp.fromDate(cutoff);

      const snapshot = await db.collection('places')
        .where('isActive', '==', false)
        .where('hiddenAt', '<', cutoffTs)
        .get();

      const creds = readCloudflareCreds('cleanup-place');

      console.log(`[cleanup-place] 만료 후보 ${snapshot.size}개`);

      // 한 건이 실패해도 나머지는 계속 진행한다(예약 작업이라 다음 실행에서
      // 다시 시도된다).
      let done = 0;
      let preserved = 0;
      const failed = [];
      for (const doc of snapshot.docs) {
        try {
          const result = await cleanupContentDoc(
            db, 'place', doc.ref, doc.data(), creds, 'cleanup-place',
          );
          preserved += result.preserved;
          done++;
        } catch (e) {
          console.error(`[cleanup-place] 장소 정리 실패 (${doc.id}):`, e.message);
          failed.push({ id: doc.id, message: e && e.message ? String(e.message) : String(e) });
        }
      }

      console.log(
        `[cleanup-place] 완료 — ${done}/${snapshot.size}개 삭제, 거래기록 ${preserved}건 보존`,
      );

      // 문서 단위 실패는 위에서 격리돼 나머지 정리를 막지 않지만, 그동안은
      // console.error로만 남아 관리자 '시스템 오류' 화면에 전혀 보이지 않았다.
      // 매 실행마다 조용히 같은 문서가 실패해도 아무도 모르는 상태였으므로,
      // 실패가 있었던 실행만 한 건으로 묶어 기록한다(문서당 한 건씩 남기면
      // 같은 장소가 매일 실패할 때 로그가 폭증한다).
      if (failed.length > 0) {
        await logScheduledFunctionError(
          db,
          'deleteExpiredPlaces',
          new Error(`장소 ${failed.length}/${snapshot.size}건 정리 실패 (나머지 ${done}건은 정상 삭제)`),
          { failed, candidates: snapshot.size, deleted: done },
        );
      }
    } catch (e) {
      await logScheduledFunctionError(db, 'deleteExpiredPlaces', e);
      throw e; // Cloud Scheduler 재시도/실패 기록은 기존과 동일하게 유지
    }
  },
);

// ── 만료 문서 정리 공용 루프 ─────────────────────────────────────────────────
//
// 아래 두 스케줄러(플레이스·이벤트)가 같은 모양으로 돈다: 후보를 모아 한 건씩
// cleanupContentDoc에 넘기고, 실패는 격리해 다음 실행에 맡기고, 실패가 있었던
// 실행만 관리자 오류 화면에 한 건으로 남긴다(문서마다 남기면 같은 문서가 매일
// 실패할 때 로그가 폭증한다). deleteExpiredPlaces가 이미 그 모양이라 그것을
// 그대로 함수로 뽑았다 — 새 정책을 새 방식으로 구현하지 않는다.
async function sweepExpired(db, { type, jobName, logTag, docs, creds }) {
  console.log(`[${logTag}] 만료 후보 ${docs.length}개`);

  let done = 0;
  let preserved = 0;
  const failed = [];
  for (const doc of docs) {
    try {
      const result = await cleanupContentDoc(
        db, type, doc.ref, doc.data(), creds, logTag,
      );
      preserved += result.preserved;
      done++;
    } catch (e) {
      const message = e && e.message ? String(e.message) : String(e);
      console.error(`[${logTag}] 정리 실패 (${doc.id}):`, message);
      failed.push({ id: doc.id, message });
    }
  }

  console.log(
    `[${logTag}] 완료 — ${done}/${docs.length}개 삭제, 거래기록 ${preserved}건 보존`,
  );

  if (failed.length > 0) {
    await logScheduledFunctionError(
      db,
      jobName,
      new Error(
        `${failed.length}/${docs.length}건 정리 실패 (나머지 ${done}건은 정상 삭제)`,
      ),
      { failed, candidates: docs.length, deleted: done },
    );
  }
  return { done, preserved };
}

// ── 만료 플레이스 자동 삭제 (매일 03:10 KST) ─────────────────────────────────
//
// 기준: isActive == false(숨김) & hiddenAt + 14일 경과 — 장소대여와 **같은
//       규칙**이다. 플레이스도 날짜가 없는 상시 등록물이라 "숨긴 시각"이
//       유일하게 말이 되는 기준점이다.
//
// ⚠️ hiddenAt이 **없는 숨김 문서는 지우지 않는다.** 이 필드를 쓰기 시작한 것이
//    이번이라, 그 전에 숨겨 둔 플레이스에는 값이 없다. updatedAt으로 대신
//    세면 "숨긴 지 하루 된 플레이스"가 곧바로 삭제될 수 있다(마지막 수정이
//    반년 전일 수 있으므로). 값이 없는 문서는 호스트가 한 번 저장하는 순간
//    (수정 저장이 isActive와 함께 hiddenAt을 기록한다) 대상이 된다.
//
// 색인: `events (isActive ASC, hiddenAt ASC)` — places 쪽과 같은 이유로
//       없으면 쿼리가 FAILED_PRECONDITION으로 죽는다.

exports.deleteExpiredEvents = onSchedule(
  {
    schedule: '10 3 * * *',
    timeZone: 'Asia/Seoul',
    region:   'asia-northeast3',
    secrets:  MEDIA_CLEANUP_SECRETS,
  },
  async () => {
    const db = admin.firestore();
    try {
      const cutoffTs = admin.firestore.Timestamp.fromDate(
        new Date(Date.now() - RETENTION_MS),
      );

      const snapshot = await db.collection('events')
        .where('isActive', '==', false)
        .where('hiddenAt', '<', cutoffTs)
        .get();

      const creds = readCloudflareCreds('cleanup-event');

      await sweepExpired(db, {
        type: 'event',
        jobName: 'deleteExpiredEvents',
        logTag: 'cleanup-event',
        docs: snapshot.docs,
        creds,
      });
    } catch (e) {
      await logScheduledFunctionError(db, 'deleteExpiredEvents', e);
      throw e;
    }
  },
);

// ── 만료 이벤트(placePromotions) 자동 삭제 (매일 03:15 KST) ──────────────────
//
// 기준: **손님에게 보이지 않게 된 시각** + 14일. 이벤트가 그렇게 되는 길은
//       둘이고, 둘 다 겪었다면 **먼저 일어난 쪽**이 기준이다.
//         · 기간 종료 — endAt이 가리키는 날의 끝(23:59:59)
//         · 호스트가 '종료'를 누름 — isVisible:false + hiddenAt
//       상시 진행(isAlways)이면서 노출 중인 이벤트는 끝나는 때가 없어 대상이
//       아니다. 판정은 앱의 [PlacePromotion.statusAt]과 같은 규칙을 쓴다
//       (registrationLimits.js의 isPromotionLive가 그 짝이다).
//
// ⚠️ hiddenAt이 없는 옛 숨김 이벤트는 지우지 않는다 — 플레이스와 같은 이유다.
//    기간이 끝난 이벤트는 endAt이 있으므로 옛 문서도 그대로 정리된다.
//
// 후보 쿼리가 둘인 이유: Firestore는 "기간이 끝났거나 숨겨졌거나"를 한 쿼리로
// 물어볼 수 없다. 둘을 따로 읽어 문서 id로 합친다.
//
// 색인: `placePromotions (isVisible ASC, hiddenAt ASC)`. endAt 단일 필드는
//       자동 색인으로 충분하다.

exports.deleteExpiredPromotions = onSchedule(
  {
    schedule: '15 3 * * *',
    timeZone: 'Asia/Seoul',
    region:   'asia-northeast3',
    secrets:  MEDIA_CLEANUP_SECRETS,
  },
  async () => {
    const db = admin.firestore();
    try {
      const now = Date.now();
      const cutoff = new Date(now - RETENTION_MS);
      const cutoffTs = admin.firestore.Timestamp.fromDate(cutoff);

      // ① 기간이 끝난 이벤트. endAt은 '날짜'라 그 날의 끝까지 진행 중이므로,
      //    쿼리는 하루 넉넉히 앞을 본 뒤 아래에서 정확히 다시 판정한다.
      const byEnd = await db.collection('placePromotions')
        .where('endAt', '<', cutoffTs)
        .get();

      // ② 호스트가 종료(숨김)한 이벤트.
      const byHidden = await db.collection('placePromotions')
        .where('isVisible', '==', false)
        .where('hiddenAt', '<', cutoffTs)
        .get();

      // 판정은 순수 함수 하나가 한다(registrationLimits.js의 promotionGoneAt) —
      // 앱의 PlacePromotion.goneAt과 짝이고, selfcheck로 묶여 있다.
      const nowDate = new Date(now);
      const candidates = new Map();
      for (const doc of [...byEnd.docs, ...byHidden.docs]) {
        if (candidates.has(doc.id)) continue;
        const goneAt = promotionGoneAt(doc.data() || {}, nowDate);
        if (goneAt == null) continue;                     // 아직 살아 있거나 기준점이 없다
        if (goneAt.getTime() >= cutoff.getTime()) continue; // 아직 14일이 안 지났다
        candidates.set(doc.id, doc);
      }

      const creds = readCloudflareCreds('cleanup-promotion');

      await sweepExpired(db, {
        type: 'promotion',
        jobName: 'deleteExpiredPromotions',
        logTag: 'cleanup-promotion',
        docs: [...candidates.values()],
        creds,
      });
    } catch (e) {
      await logScheduledFunctionError(db, 'deleteExpiredPromotions', e);
      throw e;
    }
  },
);

// ── 등록 개수 제한의 서버 강제 ───────────────────────────────────────────────
//
// 네 컬렉션의 onCreate 트리거 — 앱을 거치지 않고 만들어진 초과 등록물을
// 정리한다. 규칙(firestore.rules)으로는 문서를 셀 수 없어서 트리거가 맡는다
// (registrationLimitGuard.js 상단 주석에 그 판단이 전부 적혀 있다).
Object.assign(exports, require('./registrationLimitGuard'));

// ── Naver Geocoding ───────────────────────────────────────────────────────────

const NAVER_CLIENT_ID = 'tdehle93zg';
const naverClientSecret = defineSecret('NAVER_MAP_CLIENT_SECRET');

// 한글 행정구역 접미사 뒤에 숫자가 바로 붙으면 공백 삽입
// 예: 송정동406-22 → 송정동 406-22
//
// "로"/"길"은 뒤에 오는 숫자가 또 다른 "로/길"로 이어지는 복합 도로명일
// 때만(예: "강남대로65길", "테헤란로14길") 공백을 넣지 않는다 — 이걸 넣으면
// "강남대로 65길"처럼 존재하지 않는 주소로 잘못 쪼개진다. 반대로 "경포로463"
// 처럼 숫자 뒤에 더 이상 로/길이 붙지 않는(= 건물번호로 끝나는) 흔한 경우는
// 공백이 없으면 지오코딩 API가 주소를 찾지 못하므로 공백을 넣어야 한다.
// (?!\d*(로|길))로 "숫자 뒤에 또 로/길이 오는" 케이스만 제외한다.
function normalizeAddress(q) {
  let out = q.replace(/(동|읍|면|리|구|시|도)(\d)/g, '$1 $2');
  out = out.replace(/(로|길)(\d+)(?!\d*(로|길))/g, '$1 $2');
  return out;
}

// 공백+숫자 패턴 이전 부분만 추출 (지역명 간소화)
// 예: 송정동 406-22 → 송정동
function simplifyAddress(q) {
  const m = q.match(/^(.+?)\s+\d/);
  return m ? m[1].trim() : q;
}

// NCP Geocoding API 단일 요청
function geocodeSingle(query, clientId, clientSecret) {
  const path = `/map-geocode/v2/geocode?query=${encodeURIComponent(query)}&count=10`;
  const url  = `https://maps.apigw.ntruss.com${path}`;

  const maskedSecret = clientSecret
    ? clientSecret.slice(0, 4) + '***' + clientSecret.slice(-2)
    : '(empty)';

  console.log('[geocodeAddress] ── 요청 진단 ──────────────────────────');
  console.log('  URL   :', url);
  console.log('  query :', query);
  console.log('  clientId :', clientId);
  console.log('  hasSecret:', !!clientSecret);
  console.log('  secretLen:', clientSecret ? clientSecret.length : 0);
  console.log('  secret(masked):', maskedSecret);
  console.log('  headers: X-NCP-APIGW-API-KEY-ID =', clientId);
  console.log('  headers: X-NCP-APIGW-API-KEY    =', maskedSecret);
  console.log('─────────────────────────────────────────────────────');

  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'maps.apigw.ntruss.com',
      path,
      method: 'GET',
      headers: {
        'X-NCP-APIGW-API-KEY-ID': clientId,
        'X-NCP-APIGW-API-KEY':    clientSecret,
      },
    };
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        // 401/403은 전체 body 출력 (오류 메시지 확인)
        const isError = res.statusCode === 401 || res.statusCode === 403;
        const bodyLog = isError ? data : data.slice(0, 300);
        console.log(`[geocodeAddress] query="${query}" statusCode=${res.statusCode}`);
        console.log('[geocodeAddress] response body:', bodyLog);
        try {
          resolve({ statusCode: res.statusCode, body: JSON.parse(data) });
        } catch (_) {
          resolve({ statusCode: res.statusCode, body: { _raw: data } });
        }
      });
    });
    req.on('error', (error) => {
      console.error('[geocodeAddress] 네트워크 오류:', error.message);
      reject(error);
    });
    req.end();
  });
}

exports.geocodeAddress = onCall(
  { secrets: [naverClientSecret], region: 'asia-northeast3' },
  async (request) => {
    const query = request.data?.query;
    if (!query || typeof query !== 'string' || query.trim().length === 0) {
      throw new HttpsError('invalid-argument', '주소 검색어가 필요합니다.');
    }

    const rawQuery      = query.trim();
    const normalizedQuery = normalizeAddress(rawQuery);
    const simplifiedQuery = simplifyAddress(normalizedQuery);

    // 중복 제거 후 fallback 순서대로 시도
    const candidates = [...new Set([rawQuery, normalizedQuery, simplifiedQuery])];

    let clientSecret;
    try {
      clientSecret = naverClientSecret.value().trim(); // 공백·개행 제거
      console.log('[geocodeAddress] Secret 로드 성공, length =', clientSecret.length);
    } catch (e) {
      console.error('[geocodeAddress] Secret 로딩 실패:', e.message);
      throw new HttpsError('internal', `API 키 로딩 실패: ${e.message}`);
    }

    const attempts = [];
    let lastStatusCode = 0;
    let lastBody = null;

    for (const q of candidates) {
      let statusCode, body;
      try {
        ({ statusCode, body } = await geocodeSingle(q, NAVER_CLIENT_ID, clientSecret));
      } catch (err) {
        attempts.push({ query: q, statusCode: 0, count: 0, error: err.message });
        continue;
      }

      lastStatusCode = statusCode;
      lastBody = body;

      const count = body?.addresses?.length ?? 0;
      console.log(`[geocodeAddress] query="${q}" count=${count}`);
      attempts.push({ query: q, statusCode, count });

      // 인증 오류 → 더 시도해도 의미 없음
      if (statusCode === 401 || statusCode === 403) {
        return {
          status: 'AUTH_ERROR',
          statusCode,
          addresses: [],
          debug: { rawQuery, normalizedQuery, simplifiedQuery, attempts },
        };
      }

      if (statusCode === 200 && count > 0) {
        return {
          status: 'OK',
          statusCode,
          addresses: body.addresses,
          meta: body.meta,
          debug: { rawQuery, normalizedQuery, simplifiedQuery, attempts, successQuery: q },
        };
      }
    }

    // 모든 시도 결과 없음
    return {
      status: lastBody?.status ?? 'ZERO_RESULTS',
      statusCode: lastStatusCode,
      addresses: [],
      debug: { rawQuery, normalizedQuery, simplifiedQuery, attempts },
    };
  }
);

// ── 신청자 목록 조회 (파티장 전용) ───────────────────────────────────────────

exports.getApplicants = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');

    const { partyId, occurrenceId } = request.data;
    if (!partyId || typeof partyId !== 'string') {
      throw new HttpsError('invalid-argument', 'partyId가 필요합니다.');
    }
    // 정기 파티는 회차마다 신청이 따로다 — 회차를 지정하면 그 회차 신청만
    // 내려준다. 지정하지 않으면 예전처럼 전부 내려준다(회차 목록을 만들려면
    // 한 번은 전부 받아야 한다).
    if (occurrenceId !== undefined && occurrenceId !== null &&
        typeof occurrenceId !== 'string') {
      throw new HttpsError('invalid-argument', 'occurrenceId가 올바르지 않습니다.');
    }

    const db = admin.firestore();
    const partyDoc = await db.collection('parties').doc(partyId).get();
    if (!partyDoc.exists) throw new HttpsError('not-found', '파티를 찾을 수 없습니다.');
    if (partyDoc.data().hostId !== request.auth.uid) {
      throw new HttpsError('permission-denied', '파티장만 신청자 목록을 조회할 수 있습니다.');
    }

    // applications 서브컬렉션을 단일 출처로 삼는다 — 취소된 신청은 applicants
    // 배열에서는 제거되지만(정원 계산용) applications 문서는 상태와 함께
    // 그대로 남아있으므로, 취소 내역까지 포함한 전체 신청 이력은 이쪽에서만
    // 확인할 수 있다.
    const appsSnap = await db
      .collection('parties')
      .doc(partyId)
      .collection('applications')
      .orderBy('appliedAt', 'asc')
      .get();

    const applicants = await Promise.all(
      appsSnap.docs.map(async (doc) => {
        const a = doc.data();
        // 문서 ID는 회차 신청이면 uid가 아니다 — uid는 언제나 필드에서 읽는다
        // (doc.id 폴백은 uid 필드가 없던 아주 옛 문서용).
        const uid = a.uid || doc.id;
        const userDoc = await db.collection('users').doc(uid).get();

        // ── 호스트에게 보여줄 신원 ────────────────────────────────────────
        //
        // 조립 규칙은 applicantIdentity.js 한 곳에 있다 — 통합 신청자 관리
        // (getHostApplicationInbox)가 같은 정보를 내려주므로, 판정이 갈리면
        // 호스트가 보는 사실이 화면마다 달라진다.
        //
        // 규칙상 클라이언트는 남의 users 문서를 읽을 수 없다(users 읽기는 본인·
        // 관리자뿐). 그래서 호스트 화면이 쓸 표시 정보는 이 콜러블만 내려줄 수
        // 있고, 화면들은 uid를 그리면 안 된다. 실명이 나가도 되는 이유는 위에서
        // hostId !== auth.uid 를 permission-denied 로 막았기 때문이다.
        const { identity, name, gender } = buildApplicantIdentity(
          userDoc.exists ? userDoc.data() : null,
        );
        return {
          uid,
          identity,
          // 호스트가 승인·거절·입금확인을 **정확히 이 신청 한 건**에 걸 수
          // 있도록 문서 ID를 그대로 내려준다(클라이언트는 파싱하지 않고
          // 그대로 되돌려 보내기만 한다).
          applicationId: doc.id,
          occurrenceId: a.occurrenceId ?? null,
          occurrenceStartAt: a.occurrenceStartAt
            ? a.occurrenceStartAt.toDate().toISOString()
            : null,
          name,
          gender,
          status: a.status || 'applied',
          cancelledBy: a.cancelledBy || null,
          refundAmount: a.refundAmount ?? null,
          refundStatus: a.refundStatus ?? null,
          selectedRounds: a.selectedRounds ?? null,
          // 차수 패키지로 신청했는지 — 호스트 참가자 관리에서 "1+2차 통합권"
          // 처럼 한 덩어리로 보여준다(없으면 개별 차수 신청).
          applicationType: a.applicationType || 'round',
          packageName: a.packageName ?? null,
          appliedFee: a.appliedFee ?? null,
          // 결제 상태 — 호스트가 "누구 입금을 확인해야 하는지"를 이 목록
          // 하나로 처리할 수 있어야 한다(무료 파티는 null).
          payment: a.payment ?? null,
          // ── 사전질문 답변·제출 사진(승인제) ────────────────────────────
          // 이 콜러블은 맨 위에서 hostId !== auth.uid를 permission-denied로
          // 막으므로 **호스트 전용 통로**다. 참가자끼리 서로의 답변을 볼 수
          // 있는 경로는 없다(신청 문서 자체도 규칙상 본인·호스트·관리자만
          // 읽을 수 있다).
          //
          // 답변은 질문 문구를 담지 않으므로 스냅샷을 함께 내려보내야 화면이
          // "무엇에 대한 답인지"를 그릴 수 있다.
          answers: a.answers ?? null,
          questionsSnapshot: a.questionsSnapshot ?? null,
          photos: a.photos ?? null,
        };
      })
    );

    // 회차 목록은 **거르기 전** 전체에서 뽑는다 — 한 회차만 보고 있어도 다른
    // 회차 탭이 사라지면 안 된다. 지난 회차라도 신청이 있으면 여기 남는다.
    const occurrenceIds = [
      ...new Set(applicants.map((a) => a.occurrenceId).filter(Boolean)),
    ].sort();

    // 회차 필터는 메모리에서 건다. Firestore에서 where(occurrenceId) +
    // orderBy(appliedAt)을 함께 쓰려면 복합 인덱스가 필요한데, 신청 수는
    // 정원으로 묶여 있어 그만한 값을 하지 않는다.
    const filtered = occurrenceId
      ? applicants.filter((a) => a.occurrenceId === occurrenceId)
      : applicants;

    return { applicants: filtered, occurrenceIds };
  }
);

// ── 호스트: 내 파티로 들어온 신청 전체 (통합 신청자·예약자 관리용) ──────────
//
// getApplicants가 **파티 한 개**의 신청을 주는 것과 달리, 이쪽은 호스트가 가진
// 파티 전부의 신청을 한 번에 준다. 통합 화면이 파티마다 getApplicants를 부르면
// 파티 수만큼 왕복이 생기고, 목록이 다 차기 전에는 미처리 건수도 못 센다.
//
// **왜 클라이언트가 직접 못 읽고 콜러블이어야 하나**
//   규칙은 이미 collectionGroup('applications').where('hostId','==',uid) 를
//   허용한다(firestore.rules). 하지만 그렇게 읽으면 상태·날짜만 얻고 **신청자가
//   누구인지는 알 수 없다** — users 문서는 본인·관리자만 읽을 수 있어서, 닉네임/
//   실명은 호스트 전용 통로인 콜러블로만 내려갈 수 있다(getApplicants와 같은 이유).
//
// 새 컬렉션을 만들지 않는다. 여기서 하는 일은 **기존 신청 문서를 모아 읽는 것**
// 뿐이고, 상태를 바꾸는 것은 전부 기존 콜러블(decidePartyApplication ·
// confirmPartyDeposit)이 그대로 한다.
//
// hostId가 없던 시절의 옛 신청 문서는 이 쿼리에 잡히지 않는다. 그런 신청도
// 파티별 신청자 화면(getApplicants)에서는 그대로 보이므로 보정하지 않는다 —
// 통합 목록에서만 빠진다.
/** getAll은 한 번에 너무 많이 넘기지 않는다 — 100개씩 끊어 읽는다. */
async function getAllChunked(db, refs) {
  const out = [];
  for (let i = 0; i < refs.length; i += 100) {
    const chunk = refs.slice(i, i + 100);
    if (chunk.length === 0) continue;
    out.push(...(await db.getAll(...chunk)));
  }
  return out;
}

exports.getHostApplicationInbox = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    const uid = request.auth.uid;
    const db = admin.firestore();

    // hostId 한 조건으로만 거르고 정렬은 appliedAt에 건다 — 이 조합이
    // firestore.indexes.json의 applications 컬렉션 그룹 색인과 짝이다.
    // 한 건 더 받아서 "잘렸는지"를 판정한다(화면이 그 사실을 알려줘야 한다).
    const snap = await db
      .collectionGroup('applications')
      .where('hostId', '==', uid)
      .orderBy('appliedAt', 'desc')
      .limit(hostInbox.HOST_INBOX_LIMIT + 1)
      .get();

    // 숙박+파티 콤보에서 나온 신청은 뺀다. 콤보는 예약 문서와 파티 신청 문서를
    // 함께 만드는데(packageBookings.js), 통합 목록은 예약 쪽을 이미 '숙박+파티'
    // 한 줄로 보여준다 — 여기서 또 세면 예약 한 건이 두 줄로 뜨고 미처리
    // 숫자도 두 번 세어진다(게스트 화면이 쓰는 판별과 같은 값이다).
    const docs = snap.docs
      .filter((d) => !hostInbox.isComboGeneratedApplication(d.data()))
      .slice(0, hostInbox.HOST_INBOX_LIMIT);
    const truncated = snap.docs.length > hostInbox.HOST_INBOX_LIMIT;

    // 파티 제목은 신청 문서에 없다. 같은 파티의 신청이 여러 건이어도 파티
    // 문서는 한 번만 읽는다.
    const partyIds = [
      ...new Set(docs.map((d) => d.ref.parent.parent?.id).filter(Boolean)),
    ];
    const partySnaps = await getAllChunked(
      db,
      partyIds.map((id) => db.collection('parties').doc(id)),
    );
    const partyById = new Map(
      partySnaps.map((d) => [d.id, d.exists ? d.data() : null]),
    );

    // 신원도 마찬가지 — 같은 사람이 여러 회차를 신청했어도 users는 한 번만 읽는다.
    const applicantUids = [
      ...new Set(docs.map((d) => d.data().uid || d.id).filter(Boolean)),
    ];
    const userSnaps = await getAllChunked(
      db,
      applicantUids.map((id) => db.collection('users').doc(id)),
    );
    const identityByUid = new Map(
      userSnaps.map((d) => [
        d.id,
        buildApplicantIdentity(d.exists ? d.data() : null),
      ]),
    );

    const items = docs.map((doc) => {
      const a = doc.data();
      const partyId = doc.ref.parent.parent?.id || '';
      const party = partyById.get(partyId) || null;
      const applicantUid = a.uid || doc.id;
      const built = identityByUid.get(applicantUid) || buildApplicantIdentity(null);

      return {
        applicationId: doc.id,
        partyId,
        // 파티가 지워졌어도 결제가 있었던 신청 문서는 남는다(contentCleanup).
        partyTitle: party?.title || '',
        partyDeleted: party === null,
        uid: applicantUid,
        identity: built.identity,
        gender: built.gender,
        status: a.status || 'applied',
        occurrenceId: a.occurrenceId ?? null,
        // 회차 신청은 회차 시작 시각이 정본이다(hostInbox.js 주석 참고).
        startAtMs: hostInbox.applicationStartAtMs(a),
        appliedAtMs:
          a.appliedAt && typeof a.appliedAt.toMillis === 'function'
            ? a.appliedAt.toMillis()
            : null,
        payment: a.payment ?? null,
        applicationType: a.applicationType || 'round',
        packageName: a.packageName ?? null,
        appliedFee: a.appliedFee ?? null,
        // 미처리 판정은 **서버가 한 번만** 한다 — 목록의 뱃지와 필터가 같은
        // 값을 보게 하려면 판정이 한 곳이어야 한다.
        unhandled: hostInbox.isPartyApplicationUnhandled(a),
      };
    });

    return {
      items,
      unhandledCount: items.filter((i) => i.unhandled).length,
      truncated,
    };
  }
);

// ── 호스트: 승인 방식 + 사전질문 저장 ───────────────────────────────────────
//
// 파티 문서의 다른 필드는 앱이 Firestore에 직접 쓰지만, **승인 방식과 사전질문
// 두 필드만은 규칙에서 클라이언트 쓰기를 막고 이 콜러블로만 쓴다.**
//
// 이유는 하나다 — "개인정보를 요구하는 질문은 등록을 막는다"가 UI 검사만으로는
// 성립하지 않기 때문이다. 앱을 거치지 않고 Firestore에 직접 쓰면 그만이므로,
// 금지 판정이 실제 강제력을 가지려면 쓰기 경로 자체가 서버여야 한다.
// (openState → openPartyRecruiting과 같은 패턴이다.)
exports.setPartyApplicationForm = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');

    const { partyId, approvalMode, questions, requireApplicantPhotos } =
      request.data || {};
    if (!partyId || typeof partyId !== 'string') {
      throw new HttpsError('invalid-argument', 'partyId가 필요합니다.');
    }
    // 알 수 없는 값은 auto로 떨어뜨리지 않고 **거부**한다. 저장은 호스트의
    // 명시적 행동이므로, 오타를 조용히 즉시확정으로 바꿔버리면 호스트는
    // 승인제로 설정했다고 믿은 채 신청을 그대로 받게 된다(읽기 쪽의 관대한
    // 기본값과는 반대 방향의 판단이다 — applicationQuestions.js 주석 참고).
    if (
      approvalMode !== applicationQuestions.APPROVAL_AUTO &&
      approvalMode !== applicationQuestions.APPROVAL_MANUAL
    ) {
      throw new HttpsError('invalid-argument', '승인 방식이 올바르지 않습니다.');
    }

    const isManual = approvalMode === applicationQuestions.APPROVAL_MANUAL;
    // 즉시확정으로 되돌리면 질문 정의도 함께 비운다 — 남겨두면 나중에 다시
    // 승인제를 켰을 때 호스트가 기억하지 못하는 옛 질문이 되살아난다.
    const validated = isManual
      ? applicationQuestions.validateQuestions(questions)
      : { ok: true, questions: [] };
    if (!validated.ok) {
      throw new HttpsError(validated.code, validated.message);
    }

    const db = admin.firestore();
    const partyRef = db.collection('parties').doc(partyId);
    const snap = await partyRef.get();
    if (!snap.exists) throw new HttpsError('not-found', '파티를 찾을 수 없어요.');
    if (snap.data().hostId !== request.auth.uid) {
      throw new HttpsError('permission-denied', '이 파티의 호스트만 설정할 수 있어요.');
    }

    // 사진 요청은 승인제일 때만 의미가 있다 — 즉시확정으로 되돌리면 질문
    // 정의를 비우는 것과 같은 이유로 함께 끈다. 값이 안 오면 꺼짐이다
    // (필드가 없던 기존 파티와 같은 취급).
    const requirePhotos = isManual && requireApplicantPhotos === true;

    await partyRef.update({
      applicationApprovalMode: approvalMode,
      applicationQuestions: validated.questions,
      [applicationQuestions.REQUIRE_PHOTOS_FIELD]: requirePhotos,
      applicationFormUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      approvalMode,
      questions: validated.questions,
      requireApplicantPhotos: requirePhotos,
    };
  }
);

// ── 호스트: 신청 승인/거절 ──────────────────────────────────────────────────
//
// 승인 상태의 **정본은 신청 문서의 status**다. 예전에는 앱이 파티 문서의
// approvedApplicants/rejectedApplicants uid 배열을 직접 수정했는데, 그 배열은
// uid만 담아서 "8/15는 승인, 8/22는 거절"을 표현할 수 없다 — 회차별 신청이
// 생긴 이상 배열로는 상태를 붙들 수 없다.
//
// 입금 확인(confirmPartyDeposit)이 이미 status='approved'를 쓰므로 승인 경로가
// 하나로 합쳐진다. 레거시 배열은 새 결정에서 더 이상 쓰지 않는다(옛 데이터를
// 읽는 쪽을 위해 남아 있을 뿐이다).
exports.decidePartyApplication = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');

    const { partyId, applicationId, decision } = request.data || {};
    if (!partyId || typeof partyId !== 'string') {
      throw new HttpsError('invalid-argument', 'partyId가 필요합니다.');
    }
    if (!applicationId || typeof applicationId !== 'string') {
      throw new HttpsError('invalid-argument', 'applicationId가 필요합니다.');
    }
    if (decision !== 'approved' && decision !== 'rejected') {
      throw new HttpsError('invalid-argument', 'decision이 올바르지 않습니다.');
    }

    const uid = request.auth.uid;
    const db = admin.firestore();
    const partyRef = db.collection('parties').doc(partyId);
    const appRef = partyRef.collection('applications').doc(applicationId);

    await db.runTransaction(async (transaction) => {
      const [partySnap, appSnap] = await Promise.all([
        transaction.get(partyRef),
        transaction.get(appRef),
      ]);
      if (!partySnap.exists) throw new HttpsError('not-found', '파티를 찾을 수 없어요.');
      if (!appSnap.exists) throw new HttpsError('not-found', '신청 내역을 찾을 수 없어요.');
      if (partySnap.data().hostId !== uid) {
        throw new HttpsError('permission-denied', '이 파티의 호스트만 처리할 수 있어요.');
      }

      const appData = appSnap.data();
      // 취소·참석 처리가 끝난 건은 되돌리지 않는다 — 정원과 환불이 이미
      // 그 상태를 기준으로 정리됐기 때문이다.
      if (appData.status === 'cancelled') {
        throw new HttpsError('failed-precondition', '이미 취소된 신청이에요.');
      }
      if (appData.status === 'attended' || appData.status === 'no_show') {
        throw new HttpsError('failed-precondition', '이미 참석 처리가 끝난 신청이에요.');
      }

      // 이미 같은 결정이 내려진 건은 그대로 둔다 — 아래에서 정원을 되돌리므로,
      // 거절을 두 번 누르면 자리를 두 번 반납해 카운터가 음수로 새어나간다.
      if (appData.status === decision) {
        throw new HttpsError('failed-precondition', '이미 처리된 신청이에요.');
      }

      // ── 거절: 자리를 **즉시** 되돌린다 ────────────────────────────────
      // 예전에는 status만 바꾸고 정원을 그대로 뒀다. 즉시확정 파티에서는
      // 거절이 드문 사후 조치라 티가 안 났지만, 승인제에서는 거절 한 건마다
      // 정원이 영구히 잠긴다 — 20명 파티에서 20번 거절하면 아무도 못 든다.
      //
      // 되돌릴 칸은 **신청 문서에 남은 표시**로 정한다(occurrenceId·
      // roundCounterScope를 그대로 넘긴다). 여기서 값을 추론하면 취소가 남의
      // 자리를 반납한다 — partyCapacity.js의 ROUND_SCOPE_OCCURRENCE 주석 참고.
      if (decision === 'rejected') {
        const releaseData = releaseApplicantSlot(partySnap.data(), {
          uid: appData.uid,
          gender: appData.gender || null,
          selectedRounds: appData.selectedRounds || null,
          occurrenceId: appData.occurrenceId || null,
          roundCounterScope: appData.roundCounterScope || null,
        });
        transaction.update(partyRef, releaseData);
      }

      // ── 승인: 승인제 무통장입금이면 그때부터 입금기한이 시작된다 ──────
      // 승인 전에는 입금을 요구하지 않으므로(awaiting_approval) 기한도 없다.
      // 전이 규칙은 depositFlow 하나만 쓴다 — 도메인마다 다시 구현하지 않는다.
      // 기한은 파티 시작 시각을 넘지 않는다 — 정기 파티면 그 회차의 시작이다.
      const approvePatch =
        decision === 'approved'
          ? depositFlow.approvePatch(appData.payment, Date.now(), {
              notAfterMs: appData.occurrenceStartAt
                ? appData.occurrenceStartAt.toMillis()
                : appData.partyDateTime
                  ? appData.partyDateTime.toMillis()
                  : null,
            })
          : null;

      transaction.update(appRef, {
        status: decision,
        statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        ...(decision === 'approved'
          ? { confirmedAt: admin.firestore.FieldValue.serverTimestamp() }
          : { rejectedAt: admin.firestore.FieldValue.serverTimestamp() }),
        ...(approvePatch
          ? {
              'payment.status': approvePatch.status,
              'payment.depositDeadlineMs': approvePatch.depositDeadlineMs,
            }
          : {}),
      });
    });

    return { success: true, status: decision };
  }
);

// ── 파티 신청 (서버사이드 적격성 검증) ──────────────────────────────────────
//
// 보안 설계:
//   클라이언트 Firestore Transaction에서 서버로 이전.
//   gender·birthYear는 Admin SDK로 읽으므로 클라이언트가 위조 불가.
//   Firestore Security Rules의 신청자 경로(isApplicantUpdateOnly)는
//   이 함수 배포 후 제거 가능하나, 현재는 심층 방어(defense-in-depth)로 유지.
//
// 검증 순서:
//   1. 이미신청 → 2. 모집상태/마감일 → 3. 연령제한 → 4. 성별/정원 → 5. Firestore 업데이트
//
// 얼리버드 할인: 클라이언트가 보낸 금액은 절대 신뢰하지 않고, 서버에서
// earlyBirdEnabled/earlyBirdEndAt/earlyBirdDiscountPercent를 직접 읽어
// 신청 확정 시점의 실제 적용 금액(appliedFee)을 계산해 응답으로 돌려준다.
// (lib/utils/early_bird.dart의 계산 로직과 동일하게 유지해야 함)

// computeAppliedFee/computeAppliedFeeForRounds는 partyCapacity.js로 이동됨
// (packageBookings.js와 공유하기 위해) — 위 require 참고.

exports.applyToParty = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');

    // amounts는 앱이 화면에 띄운 금액(총액/예약금/잔금)이다. 금액의 정본은
    // 언제나 서버 계산이고, 이 값은 **대조용**으로만 쓴다 — 화면에 60,000원이라
    // 떠 있는데 서버가 80,000원을 청구하는 상황을 막는다.
    const {
      partyId, selectedRounds, packageId, occurrenceId, payment, amounts,
      // 승인제 파티의 사전질문 답변·제출 사진. 즉시확정 파티는 아예 오지 않고,
      // 와도 아래에서 질문 정의가 빈 배열이라 통째로 무시된다.
      answers, photos,
    } = request.data;
    if (!partyId || typeof partyId !== 'string') {
      throw new HttpsError('invalid-argument', 'partyId가 필요합니다.');
    }
    if (occurrenceId !== undefined && typeof occurrenceId !== 'string') {
      throw new HttpsError('invalid-argument', 'occurrenceId가 올바르지 않습니다.');
    }
    // 차수 패키지 신청 — 포함 차수와 금액은 서버가 파티 문서의 패키지 정의에서
    // 다시 읽는다(패키지가 있으면 클라이언트가 보낸 selectedRounds는 무시).
    if (
      packageId !== undefined &&
      (typeof packageId !== 'string' || packageId.length === 0)
    ) {
      throw new HttpsError('invalid-argument', 'packageId가 올바르지 않습니다.');
    }
    if (selectedRounds !== undefined) {
      const valid =
        Array.isArray(selectedRounds) &&
        selectedRounds.length > 0 &&
        selectedRounds.every((n) => Number.isInteger(n) && n > 0);
      if (!valid) {
        throw new HttpsError('invalid-argument', 'selectedRounds가 올바르지 않습니다.');
      }
    }

    const uid = request.auth.uid;
    const db = admin.firestore();

    // 사용자 인증 데이터: Admin SDK 읽기 → 클라이언트 위조 불가
    const userDoc = await db.collection('users').doc(uid).get();
    const userData = userDoc.exists ? userDoc.data() : {};
    // 본인확인 게이트 — 이미 읽은 문서로 바로 판정한다(identityGuard.js 참고).
    //
    // 성별·연령 제한이 걸린 파티는 gender/birthYear가 없다는 이유로 아래
    // reserveApplicantSlot에서 어차피 막히지만, **제한이 없는 파티는 그대로
    // 통과했다.** 회원 정책은 파티 설정과 무관하므로 여기서 못박는다.
    assertIdentityVerifiedData(userData);

    // 환불계좌 게이트 — **무통장입금으로 신청할 때만** 건다.
    //
    // 무통장입금은 PG를 거치지 않아 원결제 취소라는 경로가 없다. 취소·환불이
    // 생기면 돌려줄 방법이 계좌이체뿐이라, 낼 때 이미 **본인 명의로 인증된**
    // 환불계좌가 있어야 한다. 현장결제는 현장에서 현금으로 돌려주므로 이
    // 검증을 지나간다(`assertRefundAccountVerified`가 method로 가른다).
    //
    // 트랜잭션 **앞**에 둔다 — 사용자 문서는 위에서 이미 읽었고, 어차피
    // 거절할 요청으로 정원 칸을 잡았다 푸는 일을 만들지 않기 위해서다.
    // 앱도 신청 전에 같은 조건으로 안내하지만(헛걸음 방지), 최종 판정은
    // 여기다 — 구버전 앱이나 콜러블 직접 호출은 화면을 거치지 않는다.
    //
    // ⚠️ 이 검증은 **파티 신청에만** 걸려 있다. buildPaymentInfo는 방문예약·
    // 장소대여·파티샵·플레이스 상품·콤보가 함께 쓰는 공용 모듈이라, 거기에
    // 넣었으면 다섯 도메인이 한꺼번에 막혔을 것이다.
    assertRefundAccountVerified(payment && payment.method, userData);

    const gender = userData.gender || null;
    const birthYear = userData.birthYear != null ? Number(userData.birthYear) : null;

    let appliedFee = 0;

    await db.runTransaction(async (transaction) => {
      const partyRef = db.collection('parties').doc(partyId);
      const partySnapshot = await transaction.get(partyRef);
      if (!partySnapshot.exists) throw new HttpsError('not-found', '파티를 찾을 수 없어요');

      const data = partySnapshot.data();

      // ── 참가 회차 확정 ────────────────────────────────────────────────
      // 정기 파티는 "어느 회차에 가는지"가 신청의 일부다. 클라이언트가 보낸
      // occurrenceId를 그대로 믿지 않고, 서버가 저장된 recurringSchedule로
      // 그 날짜의 회차를 다시 계산해서 존재 여부까지 확인한다.
      // occurrenceId 없이 들어온 정기 파티 신청(구버전 앱)은 예전처럼 "지금
      // 기준 다음 회차"로 처리해 하위 호환을 유지한다.
      let occurrence = null;
      let effectiveOccurrenceId = null;
      if (isRecurringParty(data) && occurrenceId) {
        occurrence = occurrenceForId(data, occurrenceId);
        if (!occurrence) {
          throw new HttpsError('invalid-argument', '선택한 날짜에는 파티가 열리지 않아요.');
        }
        effectiveOccurrenceId = occurrenceId;
      }

      // ── 승인제 사전질문 ───────────────────────────────────────────────
      // 질문 정의는 **파티 문서에서 다시 읽는다** — 클라이언트가 보낸 정의를
      // 쓰면 필수 여부를 false로 바꿔 보내는 것만으로 필수 답변을 건너뛸 수
      // 있다. 즉시확정 파티는 questionsOf가 빈 배열이라 이 구간이 통째로
      // 무동작이고, 답변을 보내와도 저장되지 않는다(기존 흐름 무영향).
      const requireApproval = applicationQuestions.requiresApproval(data);
      const questionDefs = applicationQuestions.questionsOf(data);
      const answerResult = applicationQuestions.validateAnswers(questionDefs, answers);
      if (!answerResult.ok) {
        throw new HttpsError(answerResult.code, answerResult.message);
      }
      // ── 프로필 사진 ───────────────────────────────────────────────────
      // 예전에는 "승인제면 사진을 받는다"였다. 이제는 호스트가 켠 파티에서만
      // 받고, 켠 파티에서는 **최소 1장이 필수**다. 끈 파티는 사진을 아예
      // 저장하지 않는다 — 질문 정의가 없으면 답변을 버리는 것과 같은 규칙이다.
      const requirePhotos = applicationQuestions.requiresApplicantPhotos(data);
      const photoResult = requirePhotos
        ? applicationQuestions.validatePhotos(photos, { required: true })
        : { ok: true, photos: null };
      if (!photoResult.ok) {
        throw new HttpsError(photoResult.code, photoResult.message);
      }

      // 자격 검증(이미신청/모집상태/마감일/연령제한/성별) + 정원 확인 +
      // 카운터 증가분 계산은 partyCapacity.js의 reserveApplicantSlot으로
      // 추출돼 있다 — createPendingPackageBooking(숙박+파티 패키지 예약의
      // pending 단계)과 동일한 로직을 공유한다.
      //
      // 승인제라도 자리는 **신청 시점에 잡는다** — 승인을 기다리는 동안 자리가
      // 비어 있으면 정원을 넘겨 승인해버릴 수 있다. 거절하면 그 자리는
      // decidePartyApplication이 즉시 되돌린다.
      const {
        updateData,
        appliedFee: fee,
        effectiveSelectedRounds,
        appliedPackage,
        roundCounterScope,
      } = reserveApplicantSlot(data, {
        uid,
        gender,
        birthYear,
        selectedRounds,
        packageId,
        occurrence,
        occurrenceId: effectiveOccurrenceId,
      });
      appliedFee = fee;
      transaction.update(partyRef, updateData);

      // 신청 문서 ID — 회차가 있으면 회차까지 합쳐 유일해진다(8/15와 8/22가
      // 각각 별개의 신청 문서). 회차가 없으면 예전 그대로 uid 하나다.
      const applicationRef = partyRef
        .collection('applications')
        .doc(applicationDocId(uid, effectiveOccurrenceId));

      // 관리자 웹/향후 통계용 신청 상태 추적 — 기존 applicants 배열은 그대로 두고
      // 신청 1건당 문서 1개를 추가로 남긴다 (배열만으로는 승인/참석/취소/노쇼
      // 같은 개별 상태를 표현할 수 없어서 별도 서브컬렉션으로 분리).
      //
      // 지역·시간·카테고리는 파티 문서가 나중에 수정/삭제돼도 통계가 그대로
      // 유지되도록 신청 시점 스냅샷으로 함께 저장한다(파티 원본을 다시 조인해서
      // 읽지 않아도 통계 집계가 가능해야 하기 때문).
      //
      // 정기 파티는 문서의 partyDateTime이 "첫 회차" 캐시라 통계가 틀어진다 —
      // 이 사람이 실제로 신청한 회차(지금 기준 다음 회차)를 스냅샷으로 남긴다.
      // 일회성 파티는 저장값을 그대로 쓰므로 기존과 동일하다.
      // 회차를 직접 고른 신청이면 그 회차의 시작 시각이 곧 이 사람의 파티
      // 일시다 — "지금 기준 다음 회차"로 덮어쓰면 다음 주 회차를 미리 신청한
      // 사람의 기록이 이번 주 회차로 잘못 남는다.
      const partyDateTime = occurrence
        ? occurrence.start
        : effectivePartyStartAt(data, new Date());
      const kst = partyDateTime ? kstParts(partyDateTime) : null;
      const partyDateTimeField = partyDateTime
        ? admin.firestore.Timestamp.fromDate(partyDateTime)
        : data.partyDateTime || null;

      // 결제 정보 — 금액은 위에서 서버가 계산한 appliedFee를 기준으로 한다.
      // 참가비가 0원이면 null(결제 없음)이고, 유료인데 결제수단이 없거나
      // 준비중인 수단이면 여기서 신청 자체가 거절된다.
      //
      // 상태는 'applied'(신청 진행 상태)와 **별개**다 — 신청은 접수됐지만 돈은
      // 아직 안 들어온 구간(입금대기/현장결제 예정)을 이 맵이 표현한다.
      //
      // 호스트 결제 정책(전액 선결제 / 예약금 / 현장 전액결제)은 파티 문서에서
      // 다시 읽는다. 정책이 없는 기존 파티는 policy가 null이 되어 지금까지와
      // 똑같이 동작한다(구매자가 무통장입금·현장결제를 자유롭게 선택).
      //
      // 무료 파티는 정책 자체를 보지 않는다 — 받을 돈이 없으므로 예약금이라는
      // 개념이 성립하지 않는다.
      // 정책은 파티 문서 **최상단에 평평하게** 저장돼 있다(paymentMode 등) —
      // 앱이 PaymentPolicy.toMap()을 문서에 그대로 펼쳐 넣기 때문이다.
      const policy = appliedFee > 0
        ? paymentPolicy.normalizePolicy(paymentPolicy.pickPolicyFields(data))
        : null;
      const breakdown = paymentPolicy.computeBreakdown(policy, appliedFee);
      if (appliedFee > 0) {
        // 정책이 현장결제만 허용하는데 무통장입금을 보내는 식의 우회를 막는다.
        paymentPolicy.assertMethodAllowed(policy, payment && payment.method);
        // 앱이 보낸 금액이 서버 계산과 어긋나면 진행하지 않는다.
        paymentPolicy.assertClientAmountMatches(breakdown, amounts);
      }

      // 결제 맵의 금액은 **이번에 받을 금액**이다 — 예약금 방식이면 예약금만,
      // 전액 선결제/현장결제면 전액이다(현장결제는 '현장에서 받을 금액').
      // 승인제 무통장입금만 '승인대기'로 시작한다 — 승인 전에 입금을 받으면
      // 거절 시 계좌로 수동 환불해야 하는데 PG가 없어 자동 환불이 안 된다.
      // (현장결제는 승인과 무관하게 방문해서 내므로 그대로 '현장결제 예정'.)
      // 파라미터는 원래부터 있었고 파티만 안 넘기고 있었다 — paymentInfo.js 참고.
      const paymentInfo = buildPaymentInfo(payment, {
        amount: breakdown.paymentAmount,
        requireApproval,
        // 무통장입금 안내 계좌 = 이 파티 호스트의 인증된 수취계좌.
        // 없으면 buildPaymentInfo가 거절하고 트랜잭션 전체가 롤백된다.
        payoutAccount: await loadPayoutSnapshot(db, data.hostId || data.hostUid),
      });

      transaction.set(applicationRef, {
        uid,
        partyId,
        hostId: data.hostId || null,
        // 승인제만 'pending'이다. 즉시확정 파티는 예전 그대로 'applied'이며
        // 그 뜻도 그대로다("접수 = 자리 확정"). 두 값을 갈라 둔 덕에 목록·
        // 통계·탈퇴 차단이 "승인을 기다리는 중"과 "이미 확정"을 구분할 수 있다.
        status: requireApproval ? 'pending' : 'applied',
        gender,
        appliedFee,
        // ── 사전질문(승인제 전용) ──────────────────────────────────────
        // 답변은 질문 **id**로만 묶는다 — 문구를 답변마다 복사하지 않는다.
        // 대신 신청 1건당 질문 정의 한 벌을 스냅샷으로 남겨서, 호스트가
        // 나중에 질문을 고쳐도 이 사람이 무엇에 답한 것인지 남게 한다.
        ...(answerResult.answers ? { answers: answerResult.answers } : {}),
        ...(answerResult.snapshot ? { questionsSnapshot: answerResult.snapshot } : {}),
        // 제출 사진은 **참조만** 남는다. 파일은 Firebase Storage에 있고
        // 접근 권한은 storage.rules가 판정한다(호스트·관리자·본인만).
        ...(photoResult.photos ? { photos: photoResult.photos } : {}),
        // 금액 스냅샷 — 호스트가 나중에 참가비나 예약금 비율을 바꿔도 이미
        // 만들어진 이 신청의 금액은 절대 변하지 않는다. 취소·환불도 이 값만
        // 본다(호스트 설정을 다시 읽어 재계산하지 않는다).
        amounts: paymentPolicy.snapshotOf(policy, appliedFee),
        // 환불 규정 스냅샷 — 금액 스냅샷과 같은 이유다. 호스트가 나중에
        // 환불 규정을 바꿔도 이미 접수된 이 신청의 환불 조건은 그대로다
        // (취소는 이 값을 먼저 본다 — partyCapacity.effectiveRefundPolicy).
        refundPolicy: snapshotRefundPolicy(data),
        ...(paymentInfo ? { payment: paymentInfo } : {}),
        region: data.region || null,
        district: data.district || null,
        partyDateTime: partyDateTimeField,
        partyDate: kst?.dateKey || null,
        partyStartHour: kst?.hour ?? null,
        dayOfWeek: kst?.dayOfWeek ?? null,
        partyCategory: data.category || null,
        appliedAt: admin.firestore.FieldValue.serverTimestamp(),
        statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        confirmedAt: null,
        attendedAt: null,
        cancelledAt: null,
        ...(effectiveSelectedRounds ? { selectedRounds: effectiveSelectedRounds } : {}),
        // 차수 단건 신청과 패키지 신청을 구분하는 값 — 기존 신청 문서에는
        // 없으므로 읽는 쪽은 없으면 'round'로 본다(하위 호환).
        applicationType: appliedPackage ? 'package' : 'round',
        ...(appliedPackage
          ? {
              packageId: appliedPackage.id,
              packageName: appliedPackage.name || null,
              // 취소·집계가 되짚을 수 있게 포함 차수를 신청 시점 스냅샷으로
              // 남긴다(selectedRounds와 같은 값이지만, 패키지 정의가 나중에
              // 바뀌어도 이 신청이 무엇이었는지 남아야 한다).
              packageRoundNumbers: appliedPackage.roundNumbers,
              // 정상 판매가 — appliedFee(실제 결제 금액)와 비교하면 얼리버드가
              // 적용됐는지 그대로 드러난다.
              packageListFee:
                gender === 'female'
                  ? Number(appliedPackage.femaleFee || 0)
                  : Number(appliedPackage.maleFee || 0),
              packageEarlyBirdApplied:
                appliedPackage.earlyBirdEnabled === true &&
                appliedFee <
                  (gender === 'female'
                    ? Number(appliedPackage.femaleFee || 0)
                    : Number(appliedPackage.maleFee || 0)),
            }
          : {}),
        // 차수 인원을 회차 칸(occurrenceStats.{회차}.rounds)에 기록했는지.
        // 취소가 어느 칸을 되돌려야 하는지 이 값 하나로 결정된다 — 회차별
        // 차수 카운터 도입 **전에** 만들어진 신청에는 이 필드가 없고, 그런
        // 신청은 예전처럼 최상단 rounds[]를 되돌린다.
        //
        // reserveApplicantSlot이 돌려준 값을 **그대로** 저장하고, 취소·거절·
        // 입금만료는 이 필드를 **그대로** releaseApplicantSlot에 되돌려준다.
        // 중간에서 값을 지어내거나 추론하면 취소가 남의 자리를 반납한다
        // (partyCapacity.js의 ROUND_SCOPE_OCCURRENCE 주석 참고).
        ...(roundCounterScope ? { roundCounterScope } : {}),
        // 정기 파티: 이 신청이 어느 회차의 것인지. 취소/환불/집계가 모두 이
        // 값을 기준으로 그 회차를 되짚는다(회차별 카운터 키와 동일한 id).
        ...(effectiveOccurrenceId
          ? {
              occurrenceId: effectiveOccurrenceId,
              occurrenceStartAt: admin.firestore.Timestamp.fromDate(occurrence.start),
              occurrenceEndAt: admin.firestore.Timestamp.fromDate(occurrence.end),
            }
          : {}),
      });
    });

    return { success: true, appliedFee };
  }
);

// ── 참가자 자체 취소 (호스트가 설정한 파티별 환불 규정에 따라 자동 환불 계산) ──
//
// PartyChu는 환불률을 정하거나 권장하지 않는다 — 환불 규정은 전적으로 파티
// 등록/수정 시 호스트가 직접 입력한 refundPolicy 배열([{daysBefore, refundPercent}])을
// 그대로 따른다. 규정이 없거나(호스트 미설정) 해당 시점을 커버하는 구간이 없으면
// 환불 0%로 처리한다(임의로 유리하게/불리하게 추정하지 않음).
//
// 무료 파티(appliedFee<=0)는 환불 계산 없이 참가 취소만 처리한다.
//
// 아직 실제 PG 환불 API가 연결되어 있지 않으므로, 여기서는 refundStatus를
// 'pending'으로 저장만 해두고 실제 환불 실행은 이후 PG 연동 시 이 필드를
// 구독/폴링하는 별도 처리로 연결하기 쉬운 구조로 남겨둔다.

// computeRefund는 partyCapacity.js로 이동됨(packageBookings.js와 공유하기
// 위해) — 위 require 참고.

exports.cancelApplication = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');

    // 환불계좌는 **클라이언트에게 받지 않는다.**
    //
    // 예전에는 취소 화면이 은행·계좌번호를 자유 입력으로 받아 여기로 보냈다.
    // 그 값이 그대로 refundRequests에 박히고 users/{uid}.refundAccount까지
    // 덮어썼기 때문에, ① 본인 계좌가 아닌 곳으로 환불을 요청할 수 있었고
    // ② 인증해 둔 계좌가 자유 입력 값으로 조용히 교체됐다.
    //
    // 이제 정본은 **환불계좌 관리에서 본인 인증을 마친 계좌 하나뿐**이고,
    // 스냅샷은 서버가 그 값에서 뜬다(refundAccountVerify.verifiedSnapshotOf).
    // request.data.refundAccount는 **읽지 않는다** — 구버전 앱이 계속 보내도
    // 무시될 뿐이라 따로 거절하지 않는다.
    const { partyId, occurrenceId } = request.data;
    if (!partyId || typeof partyId !== 'string') {
      throw new HttpsError('invalid-argument', 'partyId가 필요합니다.');
    }
    if (occurrenceId !== undefined && occurrenceId !== null &&
        typeof occurrenceId !== 'string') {
      throw new HttpsError('invalid-argument', 'occurrenceId가 올바르지 않습니다.');
    }

    const uid = request.auth.uid;
    const db = admin.firestore();
    const partyRef = db.collection('parties').doc(partyId);
    // 취소는 **정확히 그 회차 한 건**만 대상으로 한다 — 8/15를 취소해도
    // 8/22 신청은 그대로 남아야 한다.
    //
    // 회차를 보낸 앱이면 그 회차 문서를, 회차 개념이 없던 옛 앱이거나 회차가
    // 없는 파티면 예전처럼 uid 문서를 본다. 회차를 보냈는데 그 문서가 없으면
    // 구조 변경 전에 신청한 옛 문서(id가 uid)일 수 있으므로 한 번 더 찾아본다.
    const applicationsRef = partyRef.collection('applications');
    const scopedRef = applicationsRef.doc(applicationDocId(uid, occurrenceId || null));
    const legacyRef = applicationsRef.doc(uid);

    let result;

    // 인증된 환불계좌 스냅샷 — 트랜잭션 **밖에서** 한 번 읽는다. 실제로 쓸지는
    // 아래에서 환불액을 계산해 봐야 알지만(requiresRefundAccount), 읽기 한
    // 번이라 조건부로 미룰 이유가 없고 트랜잭션 읽기 순서도 늘리지 않는다.
    const verifiedRefundAccount = await loadVerifiedRefundSnapshot(db, uid);

    await db.runTransaction(async (transaction) => {
      const [partySnap, scopedSnap, legacySnap] = await Promise.all([
        transaction.get(partyRef),
        transaction.get(scopedRef),
        occurrenceId ? transaction.get(legacyRef) : Promise.resolve(null),
      ]);
      if (!partySnap.exists) throw new HttpsError('not-found', '파티를 찾을 수 없어요');

      const asTarget = (snap) =>
        snap && snap.exists ? { id: snap.id, data: snap.data(), ref: snap.ref } : null;
      const scoped = asTarget(scopedSnap);

      // 회차를 못 보내는 **구버전 앱**인데 uid 문서로는 대상을 정할 수 없을
      // 때만, 이 사람의 이 파티 신청을 훑는다. 훑는다고 아무거나 취소하지는
      // 않는다 — 살아 있는 신청이 **정확히 하나**일 때만 그것을 취소하고,
      // 여러 회차가 살아 있으면 회차를 지정하라고 돌려보낸다
      // (partyApplicationTargets.resolveCancelTarget).
      //
      // uid 필드로 찾는다 — 문서 id 규칙(uid / uid_회차)에 기대면 회차 id에
      // 언더스코어가 들어가는 날 조용히 어긋난다. applyToParty가 신청 문서에
      // 언제나 uid를 남기므로 이 조회는 옛 문서까지 그대로 집는다.
      let activeCandidates = null;
      if (needsCandidateLookup({ occurrenceId: occurrenceId || null, scoped })) {
        const mine = await transaction.get(applicationsRef.where('uid', '==', uid));
        activeCandidates = mine.docs.map((d) => ({
          id: d.id,
          data: d.data(),
          ref: d.ref,
        }));
      }

      const resolved = resolveCancelTarget({
        occurrenceId: occurrenceId || null,
        scoped,
        legacy: asTarget(legacySnap),
        activeCandidates,
      });
      if (!resolved.ok) throw new HttpsError(resolved.code, resolved.message);
      const applicationRef = resolved.target.ref;

      const partyData = partySnap.data();
      const appData = resolved.target.data;

      if (appData.status === 'cancelled') {
        throw new HttpsError('failed-precondition', '이미취소');
      }
      if (appData.status === 'attended') {
        throw new HttpsError('failed-precondition', '이미참석');
      }
      // 거절된 신청은 취소할 것이 남아 있지 않다 — decidePartyApplication이
      // **거절 그 순간에 자리를 이미 반납**했다(releaseApplicantSlot). 여기서
      // 다시 취소를 받아주면 같은 자리를 두 번 되돌려 정원 카운터가 0 아래로
      // 새어나간다(20명 파티에서 거절-취소를 반복하면 정원이 무한히 늘어난다).
      if (appData.status === 'rejected') {
        throw new HttpsError('failed-precondition', '이미 거절된 신청입니다.');
      }

      // 정기 파티는 저장된 partyDateTime이 첫 회차(과거)라 그대로 쓰면 항상
      // '종료된파티'가 되어 참가자가 영영 취소할 수 없다 — 신청 문서에 남은
      // "내가 신청한 회차"를 우선 쓰고, 없으면(구버전 신청) 다음 회차 기준으로
      // 판정한다(일회성 파티는 저장값 그대로라 기존 동작과 동일).
      const appliedOccurrenceStart = appData.occurrenceStartAt
        ? appData.occurrenceStartAt.toDate()
        : null;
      const partyDateTime =
        appliedOccurrenceStart || effectivePartyStartAt(partyData, new Date());
      if (partyDateTime && partyDateTime.getTime() <= Date.now()) {
        throw new HttpsError('failed-precondition', '종료된파티');
      }

      const appliedFee = Number(appData.appliedFee || 0);
      // 환불 상한은 **실제로 받은 돈**이다. 현장결제 예정이거나 입금대기라
      // 아직 한 푼도 안 들어온 건은 환불 대상이 0원이고, 예약금만 낸 건은
      // 예약금이 상한이다(문서에 남은 금액 스냅샷 기준 — 호스트가 나중에
      // 정책을 바꿔도 이 값은 변하지 않는다).
      const paidAmount = paymentPolicy.paidAmountOf(appData.payment, appData.amounts);
      // 신청 시점 스냅샷이 있으면 그것으로 계산한다. 스냅샷이 없는 옛
      // 신청만 파티의 현재 규정으로 폴백한다(마이그레이션 없이 호환).
      const refund = computeRefund(
        effectiveRefundPolicy(appData, partyData),
        appliedFee,
        partyDateTime,
        { paidAmount },
      );

      // 정원/카운트 되돌리기 — reserveApplicantSlot의 증가 로직을 그대로
      // 역산하는 releaseApplicantSlot(partyCapacity.js)으로 추출돼 있다 —
      // 패키지 예약의 pending 취소/만료(cancelPackageBooking,
      // expireStalePackageBookings)와 동일한 로직을 공유한다.
      const gender = appData.gender;
      // 패키지 신청도 여기로 들어온다 — 신청 시점에 패키지의 포함 차수를
      // selectedRounds로 저장해 두므로, 포함된 모든 차수의 카운터가 정확히
      // 1씩 줄어든다(패키지 전용 취소 경로를 따로 두지 않는다).
      const updateData = releaseApplicantSlot(partyData, {
        uid,
        gender,
        selectedRounds: appData.selectedRounds,
        occurrenceId: appData.occurrenceId || null,
        // 신청 때 차수 인원을 어디에 올렸는지 — 그 칸을 그대로 되돌린다.
        roundCounterScope: appData.roundCounterScope || null,
      });

      // ── 환불계좌 ────────────────────────────────────────────────────────
      // 계좌이체 말고는 돈을 돌려줄 방법이 없는 건(무통장입금 + 입금 완료 +
      // 환불액 > 0)에서만 계좌를 요구한다. 그 외에는 계좌를 묻지도, 저장하지도
      // 않는다 — 필요 없는 계좌번호를 모으지 않는 것도 보안이다.
      //
      // 계좌는 **인증된 것 하나뿐**이다. 클라이언트가 보낸 값은 쓰지 않으므로
      // 임의의 계좌번호로 환불 요청을 만들 수 없다.
      const needsAccount = requiresRefundAccount(appData.payment, refund.refundAmount);
      const account = needsAccount ? verifiedRefundAccount : null;
      if (needsAccount && !account) {
        // 클라이언트가 이 코드를 보고 **환불계좌 인증 흐름**을 띄운다
        // (예전에는 계좌 자유 입력을 띄웠다 — 코드는 그대로 두고 뜻만 바뀌었다).
        throw new HttpsError(
          'failed-precondition',
          'REFUND_ACCOUNT_REQUIRED',
        );
      }

      transaction.update(partyRef, updateData);
      transaction.update(applicationRef, {
        status: 'cancelled',
        cancelledBy: 'user',
        refundPercent: refund.refundPercent,
        refundAmount: refund.refundAmount,
        refundStatus: refund.refundStatus,
        appliedRefundTier: refund.matchedTier,
        statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      if (account) {
        const refundHostId = partyData.hostId || partyData.hostUid || null;
        // ① 환불 요청 접수 — 계좌는 **이 시점의 사본**으로 박힌다. 사용자가
        //    나중에 마이페이지에서 환불계좌를 바꿔도 접수된 요청의 입금처는
        //    그대로다. 처리는 그 파티의 **호스트**가 한다(참가비를 호스트
        //    계좌로 직접 받았으므로) — 관리자는 감시·개입만 한다.
        transaction.set(
          db.collection('refundRequests').doc(),
          buildRefundRequest({
            requesterId: uid,
            domain: 'party',
            refId: partyId,
            applicationPath: applicationRef.path,
            refundAmount: refund.refundAmount,
            account,
            hostId: refundHostId,
            title: partyData.title || null,
          }),
        );

        // ② 호스트에게 알린다 — 돈을 돌려줄 사람이 호스트라서, 알림이 없으면
        //    참가자는 취소만 되고 환불은 아무도 시작하지 않은 채로 멈춘다.
        if (refundHostId) {
          transaction.set(db.collection('notifications').doc(), {
            uid: refundHostId,
            type: 'refund_requested',
            title: '환불해야 할 취소 건이 있어요',
            body: `${partyData.title || '파티'} · ${refund.refundAmount || 0}원\n`
              + '환불 요청 목록에서 참가자 계좌를 확인하고 보내주세요.',
            refId: partyId,
            read: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }

        // ③ users/{uid}.refundAccount는 **여기서 쓰지 않는다.**
        //
        //    예전에는 "다음 취소 때 다시 입력하지 않도록" 자유 입력 값을 여기
        //    저장했다. 이제 그 필드의 정본은 환불계좌 관리에서 본인 인증을
        //    마친 계좌뿐이고, 쓰는 곳도 verifyRefundAccount 하나다. 여기서
        //    다시 쓰면 인증 지문이 어긋나 인증이 조용히 풀린다.
      }

      result = { appliedFee, ...refund, refundRequested: account != null };
    });

    return { success: true, ...result };
  }
);

// ── 호스트가 파티 전체를 취소하면 모든 신청자에게 전액 환불 처리 ────────────
// (환불 규정과 무관하게 100% 환불 — 참가자 귀책이 아니라 호스트 귀책이므로
// 참가자가 불이익을 받지 않아야 한다는 원칙에 따른 예외 처리)
exports.onPartyCancelledByHost = onDocumentWritten(
  { document: 'parties/{partyId}', region: 'asia-northeast3' },
  async (event) => {
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.exists ? event.data.after.data() : null;
    if (!after) return;
    if (before?.recruitStatus === '취소' || after.recruitStatus !== '취소') return;

    const partyId = event.params.partyId;
    const db = admin.firestore();
    const applicationsSnap = await db
      .collection('parties')
      .doc(partyId)
      .collection('applications')
      .where('status', 'in', ['applied', 'approved'])
      .get();

    if (applicationsSnap.empty) return;

    // 최소 인원 미달로 서버가 자동 취소한 경우도 환불은 호스트 취소와 똑같이
    // 100%다 — 참가자 귀책이 아니기 때문. 다만 "누가 취소했는지"는 구분해
    // 남겨 신청 내역 화면이 사유를 정확히 안내할 수 있게 한다.
    const cancelledBy = after.cancelReason ? 'system' : 'host';
    const batch = db.batch();
    applicationsSnap.docs.forEach((doc) => {
      const appData = doc.data();
      // 호스트/시스템 취소는 환불률 100%지만, 환불 금액은 여기서도 실제로 받은
      // 돈을 넘지 않는다 — 현장결제 예정으로 아직 안 낸 참가자에게 참가비를
      // 환불 대상으로 잡으면 그대로 장부가 어긋난다.
      const paidAmount = paymentPolicy.paidAmountOf(appData.payment, appData.amounts);
      batch.update(doc.ref, {
        status: 'cancelled',
        cancelledBy,
        cancelReason: after.cancelReason ?? null,
        refundPercent: paidAmount > 0 ? 100 : 0,
        refundAmount: paidAmount,
        refundStatus: paidAmount > 0 ? 'pending' : 'not_applicable',
        appliedRefundTier: null,
        statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
    batch.update(db.collection('parties').doc(partyId), { applicants: [] });
    await batch.commit();
  }
);

// ── 신청 상태 변경 → 사용자 요약 통계 + 전역 집계 반영 ───────────────────────
//
// parties/{partyId}/applications/{uid} 문서의 status가 바뀔 때마다:
//   1. userStats/{uid} 카운터 증감(신청/승인/참여/취소/노쇼/거절 구분,
//      users/{uid}.stats.*는 이 기능 도입 전 임시로 썼던 것 — 이제부터는
//      userStats가 유일한 요약 통계 출처다. 원본 기록은 이 서브컬렉션,
//      요약은 userStats로 분리)
//   2. 지역·시간대 집계(regionCounts/hourCounts)는 신청 시점(최초 생성)에만
//      1회 반영 — 같은 건이 승인→참석으로 바뀔 때마다 중복 집계하지 않는다.
//   3. dailyStats(오늘)/regionStats/hourlyStats 전역 집계도 함께 증감한다.
// 신청서 생성(added)은 신청 카운터만 +1, 이후 상태 전환(modified)은 이전
// 상태 카운터를 -1, 새 상태 카운터를 +1 한다. 문서 삭제는 현재 없음.

// ⚠️ 'attended'는 **레거시**다. 그 상태를 쓰는 코드는 서버·앱 어디에도 없고,
// 실제 현장 출석의 정본은 신청 문서의 checkedInAt이다(partyCheckIn.js가 그
// 전이에서 totalAttended·dailyStats.attended 등을 증감한다). 표에서 빼지 않는
// 것은 그 상태로 남아 있는 옛 문서가 전이할 때 예전처럼 집계되게 하기
// 위해서다 — 새로 그 값을 쓰는 경로는 없다.
const STATUS_COUNTER_FIELD = {
  applied: 'totalApplications',
  approved: 'totalConfirmed',
  attended: 'totalAttended',
  cancelled: 'totalCancelled',
  rejected: 'totalRejected',
  no_show: 'totalNoShows',
};

const STATUS_TIMESTAMP_FIELD = {
  approved: 'confirmedAt',
  attended: 'attendedAt',
  cancelled: 'cancelledAt',
};

const DAILY_STATUS_FIELD = {
  applied: 'applications',
  approved: 'confirmed',
  attended: 'attended',
  cancelled: 'cancelled',
};

function argMaxKey(map) {
  if (!map) return null;
  let best = null;
  let bestVal = -Infinity;
  for (const [key, value] of Object.entries(map)) {
    if (typeof value === 'number' && value > bestVal) {
      best = key;
      bestVal = value;
    }
  }
  return best;
}

exports.onApplicationStatusWrite = onDocumentWritten(
  { document: 'parties/{partyId}/applications/{applicationId}', region: 'asia-northeast3' },
  async (event) => {
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.exists ? event.data.after.data() : null;
    if (!after) return; // 삭제는 다루지 않음

    // 문서 ID는 회차 신청이면 uid가 아니다(`{uid}_{occurrenceId}`) — 통계·
    // 활동로그가 엉뚱한 uid로 쌓이지 않도록 반드시 필드에서 읽는다.
    // 회차별 신청은 각각 한 건으로 집계된다(8/15·8/22 참가 = 2건).
    const uid = after.uid || event.params.applicationId;
    const prevStatus = before?.status;
    const newStatus = after.status;
    if (prevStatus === newStatus) return;

    const db = admin.firestore();
    const isTest = await isTestAccountUid(db, uid);
    const { dateKey } = kstParts(new Date());
    const regionKey = `${after.region || '기타'}_${after.district || '기타'}`;
    const hourKey = after.partyStartHour != null ? String(after.partyStartHour) : null;

    // 1) userStats 카운터 증감
    const userStatsPatch = {
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      lastParticipationAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (!before) {
      userStatsPatch[STATUS_COUNTER_FIELD.applied] = admin.firestore.FieldValue.increment(1);
    }
    if (before && prevStatus && prevStatus !== 'applied' && STATUS_COUNTER_FIELD[prevStatus]) {
      userStatsPatch[STATUS_COUNTER_FIELD[prevStatus]] = admin.firestore.FieldValue.increment(-1);
    }
    if (newStatus !== 'applied' && STATUS_COUNTER_FIELD[newStatus]) {
      userStatsPatch[STATUS_COUNTER_FIELD[newStatus]] = admin.firestore.FieldValue.increment(1);
    }
    // 2) 지역·시간대는 최초 신청 시점에만 집계
    if (!before) {
      userStatsPatch[`regionCounts.${regionKey}`] = admin.firestore.FieldValue.increment(1);
      if (hourKey != null) {
        userStatsPatch[`hourCounts.${hourKey}`] = admin.firestore.FieldValue.increment(1);
      }
    }

    const userStatsRef = db.collection('userStats').doc(uid);
    await userStatsRef.set(userStatsPatch, { merge: true });

    // 통합 회원 관리 — 최초 신청 시 게스트 활동 배지, 상태 전이마다 타임라인 로그.
    // 게스트 본인이 신청을 취소한 경우는 호스트가 파티 전체를 취소하는
    // party_cancelled(onPartyActivityLog)와 구분하기 위해 별도 이름을 쓴다.
    if (!before) {
      await addActivityRole(db, uid, 'guest_activity');
      // 관리자 웹 "승인/실제참여/취소/노쇼 수"(adminGetApplicationStatusCount)가
      // 테스트 계정 신청을 뺄 수 있도록 신청 문서 자체에도 표시해둔다.
      await event.data.after.ref.set({ isTestAccount: isTest }, { merge: true });
    }
    const APPLICATION_ACTIVITY_TYPE = {
      applied: 'party_applied',
      // 승인제 신청도 회원 타임라인에서는 똑같이 "파티에 신청함"이다 —
      // 여기서 빠지면 승인제 파티 신청만 활동 기록에 남지 않는다.
      pending: 'party_applied',
      approved: 'party_approved',
      attended: 'party_attended',
      cancelled: 'party_application_cancelled',
      rejected: 'party_rejected',
      no_show: 'party_no_show',
    };
    const applicationActivityType = APPLICATION_ACTIVITY_TYPE[newStatus];
    if (applicationActivityType) {
      await logUserActivity(db, {
        uid,
        activityType: applicationActivityType,
        refCollection: 'applications',
        refId: event.params.partyId,
      });
    }

    // 상태별 전이 시각(승인/참석/취소) 기록 — 기존 statusUpdatedAt(마지막 변경
    // 시각)과 별도로 각 단계가 "언제" 일어났는지 구분해서 볼 수 있게 한다.
    const timestampField = STATUS_TIMESTAMP_FIELD[newStatus];
    if (timestampField) {
      await event.data.after.ref.set(
        { [timestampField]: admin.firestore.FieldValue.serverTimestamp() },
        { merge: true }
      );
    }

    // 최초 신청 시점에만 favoriteRegion/mostUsedHour 재계산 — 방금 늘린
    // regionCounts/hourCounts를 다시 읽어 최댓값을 뽑는다.
    if (!before) {
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(userStatsRef);
        const data = snap.data() || {};
        const topRegion = argMaxKey(data.regionCounts);
        const topHour = argMaxKey(data.hourCounts);
        tx.set(
          userStatsRef,
          {
            favoriteRegion: topRegion,
            mostUsedHour: topHour != null ? Number(topHour) : null,
          },
          { merge: true }
        );
      });
    }

    // 3) 전역 집계 — dailyStats(오늘, 액션이 실제로 일어난 날짜 기준). 실제
    // 서비스 KPI에 테스트 계정 활동이 섞이지 않도록 여기서부터는 전부
    // isTestAccount인 회원의 액션은 건너뛴다(userStats 등 위쪽 "본인 기록"은
    // 관리자 웹에서 이미 테스트 계정으로 구분되므로 그대로 둔다).
    const dailyField = DAILY_STATUS_FIELD[newStatus];
    if (dailyField && !isTest) {
      await db
        .collection('dailyStats')
        .doc(dateKey)
        .set({ [dailyField]: admin.firestore.FieldValue.increment(1) }, { merge: true });
    }

    // regionStats/hourlyStats는 전 기간 누적 — "신청" 시점과 "참석" 시점에만 집계.
    // 'attended' 가지는 레거시다(위 STATUS_COUNTER_FIELD 주석 참고) — 실제
    // 현장 출석은 partyCheckIn.js가 checkedInAt 전이에서 같은 칸을 증감한다.
    if (!isTest && (newStatus === 'applied' || newStatus === 'attended')) {
      const regionField = newStatus === 'applied' ? 'totalApplications' : 'totalAttended';
      await db
        .collection('regionStats')
        .doc(regionKey)
        .set(
          {
            region1: after.region || null,
            region2: after.district || null,
            [regionField]: admin.firestore.FieldValue.increment(1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

      if (hourKey != null) {
        const hourField = newStatus === 'applied' ? 'applications' : 'attended';
        await db
          .collection('hourlyStats')
          .doc(hourKey)
          .set(
            { hour: after.partyStartHour, [hourField]: admin.firestore.FieldValue.increment(1) },
            { merge: true }
          );
      }
    }
  }
);

// ── 신규 가입 → users 문서에 가입일/이메일/검색·정렬용 기본값 채우기 ─────────
//
// users/{uid} 문서는 지금까지 NICE 본인확인을 완료해야만(또는 다른 화면에서
// 처음 write할 때) 생성됐고 createdAt/email 필드는 어디서도 기록되지 않았다.
// Firebase Auth 계정 생성 즉시 이 트리거가 실행되어 관리자 웹의 가입일·이메일
// 표시가 항상 가능하도록 최소 필드만 merge로 남긴다.
//
// nicknameLower/nameLower/emailLower/stats.*를 빈 문자열/0으로라도 항상
// 채워두는 이유 — Firestore는 정렬 대상 필드가 아예 없는 문서를 orderBy
// 결과에서 제외한다. 이 필드들을 아예 안 채우면 "이름순"/"실제 이용 횟수순"
// 정렬 시 아직 값이 없는 회원이 통째로 목록에서 빠져버린다.
exports.onUserCreated = functionsV1
  .region('asia-northeast3')
  .auth.user()
  .onCreate(async (user) => {
    const email = user.email || '';
    const db = admin.firestore();
    await db.collection('users').doc(user.uid).set(
      {
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        email: email || null,
        emailLower: email.toLowerCase(),
        nicknameLower: '',
        nameLower: '',
        accountStatus: 'active',
        // 통계 집계 시 isTestAccount == false 필터로 실사용자만 걸러낼 수
        // 있으려면(관리자 웹 대시보드) 이 필드가 모든 회원에게 항상 존재해야
        // 한다 — Firestore는 필드가 아예 없는 문서를 등호/부등호 필터에서
        // 제외하므로, 기존 회원은 별도 백필 스크립트로 false를 채웠다.
        isTestAccount: false,
      },
      { merge: true }
    );

    const { dateKey } = kstParts(new Date());
    await db
      .collection('dailyStats')
      .doc(dateKey)
      .set({ newUsers: admin.firestore.FieldValue.increment(1) }, { merge: true });

    await logUserActivity(db, { uid: user.uid, activityType: 'signup' });
  });

// ── nickname/name/email 변경 → 검색용 소문자 필드 자동 반영 ─────────────────
//
// 관리자 웹 회원 검색(닉네임/이름/이메일 prefix 검색)은 원본 필드가 아니라
// nicknameLower/nameLower/emailLower를 조회한다 — Firestore는 대소문자
// 구분 없는 검색을 지원하지 않으므로 소문자 사본을 별도로 유지해야 한다.
// 클라이언트가 이 파생 필드를 직접 쓰지 못하도록 firestore.rules에서 막아
// 두었고(Functions만 기록), 이 트리거가 유일한 반영 경로다.
//
// 무한 루프 방지: 계산한 소문자 값이 이미 저장된 값과 같으면 아무것도 쓰지
// 않는다 — 이 트리거 자신의 쓰기가 다시 이 트리거를 건드려도 두 번째
// 실행에서는 변경 사항이 없어 멈춘다.
exports.onUserFieldsWrite = onDocumentWritten(
  { document: 'users/{uid}', region: 'asia-northeast3' },
  async (event) => {
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.exists ? event.data.after.data() : null;
    if (!after) return; // 삭제는 다루지 않음

    // 본인인증 최초 완료 시점 — 통합 활동 타임라인용. patch가 없어도(닉네임/
    // 이름/이메일이 이번 쓰기에서 안 바뀌었어도) 항상 검사해야 한다.
    const wasVerified = (before?.identityVerified ?? before?.isVerified) === true;
    const isVerified = (after.identityVerified ?? after.isVerified) === true;
    if (!wasVerified && isVerified) {
      await logUserActivity(admin.firestore(), {
        uid: event.params.uid,
        activityType: 'identity_verified',
      });
    }

    const wantNicknameLower = String(after.nickname || '').toLowerCase();
    const wantNameLower = String(after.name || '').toLowerCase();
    const wantEmailLower = String(after.email || '').toLowerCase();

    const patch = {};
    if ((after.nicknameLower || '') !== wantNicknameLower) patch.nicknameLower = wantNicknameLower;
    if ((after.nameLower || '') !== wantNameLower) patch.nameLower = wantNameLower;
    if ((after.emailLower || '') !== wantEmailLower) patch.emailLower = wantEmailLower;
    if (Object.keys(patch).length === 0) return;

    await event.data.after.ref.set(patch, { merge: true });

    // 닉네임/이름이 실제로 바뀐 경우에만 userStats에도 스냅샷을 반영한다(관리자
    // 웹 "이용 통계" 사용자 목록이 매번 users 컬렉션과 조인하지 않아도 되도록).
    // userStats 문서가 아직 없는 사용자(신청/찜/조회 등 활동이 전혀 없는 상태)는
    // merge:true라 이 시점에 처음 만들어진다 — 닉네임을 설정했다는 건 최소한
    // 온보딩은 마쳤다는 뜻이라 사용자 목록에 나타나도 자연스럽다.
    if (patch.nicknameLower !== undefined || patch.nameLower !== undefined) {
      await admin.firestore().collection('userStats').doc(event.params.uid).set(
        {
          nickname: after.nickname || '',
          name: after.name || '',
        },
        { merge: true }
      );
    }
  }
);

// ── 찜 추가/삭제 → 회원 통계 반영 ────────────────────────────────────────────
//
// favorites 컬렉션은 문서 생성/삭제 자체가 곧 "찜 추가"/"찜 해제" 이벤트라
// 클라이언트에 별도 analyticsEvents 로깅을 추가하지 않고 이 트리거로 감지한다.
// totalFavorites는 해제해도 줄이지 않는다 — "찜 횟수"를 현재 찜한 개수가 아니라
// 누적 참여 행동(engagement) 지표로 다루기 위함.
exports.onFavoriteWrite = onDocumentWritten(
  { document: 'favorites/{favoriteId}', region: 'asia-northeast3' },
  async (event) => {
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.exists ? event.data.after.data() : null;
    const db = admin.firestore();
    const { dateKey } = kstParts(new Date());

    if (!before && after) {
      // 찜 추가
      await db
        .collection('userStats')
        .doc(after.userId)
        .set(
          {
            totalFavorites: admin.firestore.FieldValue.increment(1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      await db
        .collection('dailyStats')
        .doc(dateKey)
        .set({ favorites: admin.firestore.FieldValue.increment(1) }, { merge: true });

      // 찜을 받은 대상(파티/플레이스/샵/크루)의 등록자에게도 "받은 찜 수"를
      // 반영한다 — 통합 회원 관리 회원 상세의 "받은 찜 수" 통계용.
      await bumpFavoriteReceivedCount(db, after.type, after.itemId);

      await logUserActivity(db, {
        uid: after.userId,
        activityType: 'favorite_added',
        refCollection: 'favorites',
        refId: after.itemId,
        extra: { type: after.type },
      });
    } else if (before && !after) {
      // 찜 해제
      await logUserActivity(db, {
        uid: before.userId,
        activityType: 'favorite_removed',
        refCollection: 'favorites',
        refId: before.itemId,
        extra: { type: before.type },
      });
    }
    // totalFavorites/dailyStats.favorites는 해제 시 건드리지 않는다(위 설명 참고)
    // — 향후 "해제율" 같은 지표가 필요해지면 별도 카운터를 추가한다.
  }
);

// ── 파티/플레이스 등록 → 최초 등록 호스트 표시 ───────────────────────────────
// 관리자 웹 통합 회원 관리 목록의 "호스트만 보기" 필터가
// users.where('isHost','==',true)로 바로 조회할 수 있도록, 파티 또는
// 플레이스를 처음 만든 시점에 한 번만 users/{hostId}.isHost를 true로
// 세팅한다. firestore.rules가 이 필드를 클라이언트 쓰기로부터 막아두므로
// 반드시 이 트리거(Admin SDK)에서만 써야 한다.
async function markHostIfNeeded(hostId) {
  if (!hostId || typeof hostId !== 'string') return;
  const userRef = admin.firestore().collection('users').doc(hostId);
  const snap = await userRef.get();
  if (snap.exists && snap.data().isHost === true) return;
  await userRef.set(
    { isHost: true, hostSince: admin.firestore.FieldValue.serverTimestamp() },
    { merge: true }
  );
}

// ── 파티 등록 → 일별 등록 수 집계 + 호스트 표시 + 활동 배지/통계/로그 ────────
exports.onPartyCreated = onDocumentCreated(
  { document: 'parties/{partyId}', region: 'asia-northeast3' },
  async (event) => {
    const db = admin.firestore();
    const hostId = event.data?.data()?.hostId;
    const isTest = await isTestAccountUid(db, hostId);
    // 관리자 웹 대시보드가 '등록된 파티 수' 등을 컬렉션 카운트로 직접 세므로,
    // 문서 자체에 표시해둬야 테스트 계정이 만든 파티를 그 카운트에서 뺄 수 있다.
    await event.data.ref.set({ isTestAccount: isTest }, { merge: true });

    if (!isTest) {
      const { dateKey } = kstParts(new Date());
      await db
        .collection('dailyStats')
        .doc(dateKey)
        .set({ createdParties: admin.firestore.FieldValue.increment(1) }, { merge: true });
    }

    await markHostIfNeeded(hostId);
    if (hostId) {
      if (!isTest) {
        await bumpUserStats(db, hostId, {
          totalPartiesCreated: admin.firestore.FieldValue.increment(1),
        });
      }
      await addActivityRole(db, hostId, 'host_activity');
      await logUserActivity(db, {
        uid: hostId,
        activityType: 'party_created',
        refCollection: 'parties',
        refId: event.params.partyId,
      });
    }
  }
);

// ── 플레이스 등록 → 호스트 표시 + 활동 배지/통계/로그 ────────────────────────
// places/{placeId}에는 지금까지 생성 시점 트리거가 없었다 — 이 트리거가 처음.
exports.onPlaceCreated = onDocumentCreated(
  { document: 'places/{placeId}', region: 'asia-northeast3' },
  async (event) => {
    const db = admin.firestore();
    const hostId = event.data?.data()?.hostId;
    const isTest = await isTestAccountUid(db, hostId);
    // '장소 수' 대시보드 카드도 컬렉션 카운트라 문서 자체에 표시해둬야 한다.
    await event.data.ref.set({ isTestAccount: isTest }, { merge: true });

    await markHostIfNeeded(hostId);
    if (hostId) {
      if (!isTest) {
        await bumpUserStats(db, hostId, {
          totalPlacesCreated: admin.firestore.FieldValue.increment(1),
        });
      }
      await addActivityRole(db, hostId, 'place_operator');
      await logUserActivity(db, {
        uid: hostId,
        activityType: 'place_registered',
        refCollection: 'places',
        refId: event.params.placeId,
      });
    }
  }
);

// ── 행동 로그(analyticsEvents) → 사용자/전역 통계 반영 ───────────────────────
//
// Firestore 쓰기로 자연히 파생되지 않는 "화면을 봤다" 류의 순수 조회 이벤트만
// 클라이언트가 직접 남긴다(app_open/party_view/place_view — party_apply 등은
// applications/favorites 트리거가 이미 처리하므로 여기서 다루지 않음).
// hourBucket/dayOfWeek는 클라이언트 기기 시간을 신뢰하지 않고, 이 트리거가
// occurredAt(서버 타임스탬프)을 기준으로 한국 시간으로 다시 계산해 채운다.
const ANALYTICS_USER_STATS_FIELD = {
  app_open: 'totalAppOpens',
  party_view: 'totalPartyViews',
};

exports.onAnalyticsEventCreated = onDocumentCreated(
  { document: 'analyticsEvents/{eventId}', region: 'asia-northeast3' },
  async (event) => {
    const data = event.data.data();
    if (!data) return;

    const occurredAt = data.occurredAt && typeof data.occurredAt.toDate === 'function'
      ? data.occurredAt.toDate()
      : new Date();
    const { dateKey, hour, dayOfWeek } = kstParts(occurredAt);

    const db = admin.firestore();
    const isTest = await isTestAccountUid(db, data.userId);
    const patch = { hourBucket: hour, dayOfWeek };
    await event.data.ref.set(patch, { merge: true });

    const userStatsField = ANALYTICS_USER_STATS_FIELD[data.eventType];
    if (data.userId) {
      // lastActiveAt은 관리자 웹 "이용 통계 > 사용자별 목록"이 users 컬렉션과
      // 조인하지 않고도 최근 활동일을 바로 보여주도록 모든 이벤트에 반영한다.
      const userStatsPatch = { updatedAt: admin.firestore.FieldValue.serverTimestamp() };
      userStatsPatch.lastActiveAt = admin.firestore.FieldValue.serverTimestamp();
      if (userStatsField) {
        userStatsPatch[userStatsField] = admin.firestore.FieldValue.increment(1);
      }
      await db.collection('userStats').doc(data.userId).set(userStatsPatch, { merge: true });
    }

    // dailyStats/regionStats/hourlyStats는 실제 서비스 조회수 KPI라 테스트
    // 계정의 조회는 여기서부터 제외한다(위 userStats는 본인 기록이라 그대로 둠).
    if (data.eventType === 'party_view' && !isTest) {
      await db
        .collection('dailyStats')
        .doc(dateKey)
        .set({ partyViews: admin.firestore.FieldValue.increment(1) }, { merge: true });
      await db
        .collection('hourlyStats')
        .doc(String(hour))
        .set({ hour, partyViews: admin.firestore.FieldValue.increment(1) }, { merge: true });
    }

    if (!isTest && (data.eventType === 'party_view' || data.eventType === 'place_view') && (data.region1 || data.region2)) {
      const regionKey = `${data.region1 || '기타'}_${data.region2 || '기타'}`;
      await db
        .collection('regionStats')
        .doc(regionKey)
        .set(
          {
            region1: data.region1 || null,
            region2: data.region2 || null,
            totalViews: admin.firestore.FieldValue.increment(1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
    }

    // party_share는 지금까지 analyticsEvents에 기록만 되고 서버에서 아무
    // 처리도 안 하고 있었다 — 통합 활동 타임라인용 로그만 추가한다.
    if (data.eventType === 'party_share' && data.userId) {
      await logUserActivity(db, {
        uid: data.userId,
        activityType: 'party_shared',
        refCollection: 'parties',
        refId: data.partyId || null,
      });
    }
  }
);

// ── NICE 통합인증(ido/intc) 표준창 연동 ───────────────────────────────────────
//
// 보안 설계:
//   Client ID / Client Secret 은 Firebase Secret Manager에만 저장.
//   앱 코드·.env·Firestore·로그에 절대 노출되지 않음.
//   PBKDF2 유도 키(ticket 등)는 verificationSessions/{uid} 에만 보관 — 클라이언트 읽기 차단.
//   이름·생년월일·성별은 NICE 서버 검증값만 신뢰(클라이언트 입력 불수용).
//   KDF/무결성/복호화 로직은 NICE 공식 Node.js 샘플(NiceIntc_implmentation.js)과 동일하게 구현.
//
// 흐름:
//   1. niceIntcRequestUrl : access token 발급(24h 캐시) → 인증 URL 요청 → transaction_id 등 세션 저장
//   2. Flutter WebView    : auth_url 을 그대로 GET 로드 → 사용자가 표준창에서 본인확인
//   3. niceIntcResult     : return_url 로 전달된 web_transaction_id 수신 → 인증결과 조회
//                           → PBKDF2 키 유도 → 무결성 검증 → AES-256-GCM 복호화 → Firestore 저장

const NICE_RETURN_URL = 'https://partychu-30c24.web.app/nice/callback';
const NICE_CLOSE_URL  = 'https://partychu-30c24.web.app/nice/callback?closed=1';
const NICE_HOST       = 'auth.niceid.co.kr';

const niceClientId     = defineSecret('NICE_CLIENT_ID');
const niceClientSecret = defineSecret('NICE_CLIENT_SECRET');

// NICE 통합인증 API POST 요청 (HTTPS 443)
function httpsPostNiceIntc(path, bodyObj, extraHeaders) {
  const body = JSON.stringify(bodyObj);
  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        hostname: NICE_HOST,
        path,
        method:   'POST',
        headers: {
          'Content-Type':   'application/json',
          'Content-Length': Buffer.byteLength(body, 'utf8'),
          ...extraHeaders,
        },
      },
      (res) => {
        let data = '';
        res.on('data', (c) => { data += c; });
        res.on('end', () => {
          try   { resolve({ status: res.statusCode, body: JSON.parse(data) }); }
          catch { reject(new Error(`NICE 응답 파싱 오류: ${data.slice(0, 200)}`)); }
        });
      },
    );
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

// 요청고유번호 (20~50byte)
function niceReqNo() {
  const ts = new Date().toISOString().replace(/[-T:.Z]/g, '').slice(0, 14);
  return 'REQ' + ts + '/' + crypto.randomBytes(14).toString('hex').slice(0, 27);
}

// 접근 토큰 발급 (24시간 유효 — Firestore(niceIntcConfig/accessToken)에 캐시하여 재사용)
async function getNiceAccessToken(clientId, clientSecret) {
  const db       = admin.firestore();
  const tokenRef = db.collection('niceIntcConfig').doc('accessToken');
  const cached   = await tokenRef.get();

  if (cached.exists) {
    const d = cached.data();
    // 만료 10분 전까지는 재사용 (신규 요청마다 토큰을 새로 발급하지 않도록)
    if (d.expiresAt && d.expiresAt.toDate().getTime() - Date.now() > 10 * 60 * 1000) {
      console.log(`[NICE] 캐시된 토큰 재사용. expiresAt=${d.expiresAt.toDate().toISOString()}`);
      return { accessToken: d.accessToken, iterators: d.iterators, ticket: d.ticket };
    }
  }

  const authHeader = 'Basic ' +
    Buffer.from(`${clientId}:${clientSecret}`).toString('base64').replace(/=+$/, '');

  const { status, body } = await httpsPostNiceIntc(
    '/ido/intc/v1.0/auth/token',
    { grant_type: 'client_credentials', request_no: niceReqNo() },
    { Authorization: authHeader, 'X-Intc-DevLang': 'Linux/Node.js' },
  );

  console.log(`[NICE] auth/token 응답. httpStatus=${status}`
    + ` result_code=${body.result_code} result_message=${body.result_message}`);

  if (status !== 200 || body.result_code !== '0000') {
    console.error('[NICE] 토큰 발급 실패:', {
      httpStatus: status, result_code: body.result_code, result_message: body.result_message,
    });
    throw new HttpsError('internal', `NICE 토큰 발급 실패 (${body.result_code || status}) ${body.result_message || ''}`.trim());
  }

  await tokenRef.set({
    accessToken: body.access_token,
    iterators:   body.iterators,
    ticket:      body.ticket,
    expiresAt:   admin.firestore.Timestamp.fromMillis(body.expires_in),
    updatedAt:   admin.firestore.FieldValue.serverTimestamp(),
  });

  return { accessToken: body.access_token, iterators: body.iterators, ticket: body.ticket };
}

// PBKDF2 키 유도 (NICE 공식 Node.js 샘플과 동일)
// key = PBKDF2(password=ticket, salt=transactionId, iterations=iterators, keylen=64, sha256) → base64url
// 대칭키    = 그 base64url 문자열의 앞 32자
// 무결성 키 = 그 base64url 문자열의 48번째 문자부터 32자
function niceDeriveKeys(ticket, transactionId, iterators) {
  const raw = crypto.pbkdf2Sync(ticket, transactionId, iterators, 64, 'sha256');
  const b64 = raw.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  return { key: b64.substring(0, 32), hmacKey: b64.substring(48, 48 + 32) };
}

// HMAC-SHA256 무결성 값 (base64url) — enc_data 원문 문자열 기준
function niceIntegrityValue(encData, hmacKey) {
  const mac = crypto.createHmac('sha256', hmacKey).update(encData).digest('base64');
  return mac.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

// AES-256-GCM 복호화
// enc_data(base64url) = iv(16byte) + cipherText + authTag(16byte)
function niceDecrypt(encData, key) {
  const buf          = Buffer.from(encData.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
  const iv           = buf.subarray(0, 16);
  const cipherAndTag = buf.subarray(16);
  const tag          = cipherAndTag.subarray(cipherAndTag.length - 16);
  const cipherText   = cipherAndTag.subarray(0, cipherAndTag.length - 16);

  const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(tag);
  const plain = Buffer.concat([decipher.update(cipherText), decipher.final()]);
  return JSON.parse(plain.toString('utf8'));
}

// ── niceIntcRequestUrl : 접근 토큰 발급/재사용 → 인증 URL 요청 ────────────────

exports.niceIntcRequestUrl = onCall(
  {
    secrets: [niceClientId, niceClientSecret],
    region: 'asia-northeast3',
    // NICE IP 화이트리스트 통과용 — Cloud NAT 고정 IP를 거치도록 VPC 커넥터 경유
    vpcConnector: 'projects/partychu-30c24/locations/asia-northeast3/connectors/nice-connector',
    vpcConnectorEgressSettings: 'ALL_TRAFFIC',
  },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');

    const uid = request.auth.uid;
    const db  = admin.firestore();

    // 이미 본인확인 완료 여부 체크
    const userSnap = await db.collection('users').doc(uid).get();
    if (userSnap.exists && userSnap.data().identityVerified === true) {
      throw new HttpsError('already-exists', '이미 본인확인이 완료된 계정입니다.');
    }

    const clientId     = niceClientId.value().trim();
    const clientSecret = niceClientSecret.value().trim();

    const { accessToken, iterators, ticket } = await getNiceAccessToken(clientId, clientSecret);

    const reqNo = niceReqNo();
    console.log(`[NICE] auth/url 요청. uid=${uid} return_url=${NICE_RETURN_URL}`
      + ` close_url=${NICE_CLOSE_URL} method_type=GET reqNo=${reqNo}`);

    const { status, body } = await httpsPostNiceIntc(
      '/ido/intc/v1.0/auth/url',
      {
        return_url:  NICE_RETURN_URL,
        close_url:   NICE_CLOSE_URL,
        svc_types:   ['M'],               // 휴대폰 본인확인만 노출
        method_type: 'GET',
        exp_mods:    ['closeButtonOn'],
        request_no:  reqNo,
      },
      { Authorization: `Bearer ${accessToken}`, 'X-Intc-DevLang': 'Linux/Node.js' },
    );

    console.log(`[NICE] auth/url 응답. uid=${uid} httpStatus=${status}`
      + ` result_code=${body.result_code} result_message=${body.result_message}`);

    if (status !== 200 || body.result_code !== '0000') {
      console.error('[NICE] 인증URL 요청 실패:', {
        uid, httpStatus: status,
        result_code: body.result_code, result_message: body.result_message,
      });
      throw new HttpsError('internal', `NICE 인증URL 요청 실패 (${body.result_code || status}) ${body.result_message || ''}`.trim());
    }

    // NICE 응답의 request_no를 우선 사용 — 공식 샘플(NiceIntc_implmentation.js)도
    // auth/url 응답의 request_no로 재할당 후 auth/result에 사용함.
    // (NICE가 요청값을 그대로 에코하지 않고 변형/재발급할 수 있어, 요청 시 보낸
    //  reqNo를 그대로 재사용하면 auth/result 단계에서 request_no 불일치로
    //  "잘못된 정보 또는 처리중 오류" 실패가 발생할 수 있음)
    const effectiveReqNo = body.request_no || reqNo;
    if (body.request_no && body.request_no !== reqNo) {
      console.warn(`[NICE] auth/url 응답 request_no가 요청값과 다름. sent=${reqNo} received=${body.request_no}`);
    }

    // 복호화에 필요한 값(ticket/iterators/transactionId) 포함 세션 저장
    // — 클라이언트 읽기 차단 (Firestore Rules 참조)
    await db.collection('verificationSessions').doc(uid).set({
      provider:      'nice_intc',
      requestNo:     effectiveReqNo,
      transactionId: body.transaction_id,
      ticket,
      iterators,
      used:          false,
      createdAt:     admin.firestore.FieldValue.serverTimestamp(),
      expiresAt:     admin.firestore.Timestamp.fromDate(new Date(Date.now() + 10 * 60 * 1000)),
    });

    console.log(`[NICE] niceIntcRequestUrl 완료. uid=${uid} reqNo=${effectiveReqNo} transactionId=${body.transaction_id}`);
    return { authUrl: body.auth_url };
  },
);

// ── niceIntcResult : 인증결과 조회 → 무결성 검증·복호화·저장 ──────────────────

exports.niceIntcResult = onCall(
  {
    secrets: [niceClientId, niceClientSecret],
    region: 'asia-northeast3',
    // NICE IP 화이트리스트 통과용 — Cloud NAT 고정 IP를 거치도록 VPC 커넥터 경유
    vpcConnector: 'projects/partychu-30c24/locations/asia-northeast3/connectors/nice-connector',
    vpcConnectorEgressSettings: 'ALL_TRAFFIC',
  },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');

    const { webTransactionId } = request.data;
    if (!webTransactionId || typeof webTransactionId !== 'string') {
      throw new HttpsError('invalid-argument', 'webTransactionId가 필요합니다.');
    }

    const uid        = request.auth.uid;
    const db         = admin.firestore();
    const sessionRef = db.collection('verificationSessions').doc(uid);

    const sessionDoc = await sessionRef.get();
    if (!sessionDoc.exists) {
      throw new HttpsError('not-found', '인증 세션이 없습니다. 처음부터 다시 시도해주세요.');
    }
    const session = sessionDoc.data();

    if (session.provider !== 'nice_intc') {
      throw new HttpsError('failed-precondition', 'NICE 세션이 아닙니다.');
    }
    if (session.used) {
      throw new HttpsError('already-exists', '이미 사용된 인증 세션입니다. 다시 시도해주세요.');
    }
    if (session.expiresAt.toDate() < new Date()) {
      throw new HttpsError('deadline-exceeded', '인증 세션이 만료되었습니다. 다시 시도해주세요.');
    }

    // 재사용/경쟁 조건 방지 — 즉시 소비 처리
    await sessionRef.update({ used: true });

    const clientId     = niceClientId.value().trim();
    const clientSecret = niceClientSecret.value().trim();
    const { accessToken } = await getNiceAccessToken(clientId, clientSecret);

    console.log(`[NICE] auth/result 요청. uid=${uid} webTransactionId=${webTransactionId}`
      + ` transactionId=${session.transactionId} requestNo=${session.requestNo}`);

    const { status, body } = await httpsPostNiceIntc(
      '/ido/intc/v1.0/auth/result',
      {
        web_transaction_id: webTransactionId,
        transaction_id:     session.transactionId,
        request_no:         session.requestNo,
      },
      { Authorization: `Bearer ${accessToken}`, 'X-Intc-DevLang': 'Linux/Node.js' },
    );

    // NICE 응답의 result_code/result_message는 성공/실패 여부와 관계없이 항상 로그로 남김
    console.log(`[NICE] auth/result 응답. uid=${uid} httpStatus=${status}`
      + ` result_code=${body.result_code} result_message=${body.result_message}`);

    if (status !== 200 || body.result_code !== '0000') {
      console.error('[NICE] 인증결과 요청 실패:', {
        uid, httpStatus: status,
        result_code: body.result_code, result_message: body.result_message,
      });
      throw new HttpsError(
        'cancelled',
        `NICE 인증 실패 또는 취소 (${body.result_code || status}) ${body.result_message || ''}`.trim(),
      );
    }

    const { key, hmacKey } = niceDeriveKeys(session.ticket, session.transactionId, session.iterators);

    // 무결성 검증 — enc_data 위변조 여부 확인
    const expectedIntegrity = niceIntegrityValue(body.enc_data, hmacKey);
    if (expectedIntegrity !== body.integrity_value) {
      console.error('[NICE] 무결성 검증 실패:', {
        uid,
        transactionId: session.transactionId,
        expected: expectedIntegrity,
        received: body.integrity_value,
      });
      throw new HttpsError('invalid-argument', 'NICE 인증 결과 무결성 검증에 실패했습니다.');
    }

    let result;
    try {
      result = niceDecrypt(body.enc_data, key);
    } catch (e) {
      console.error('[NICE] 복호화 실패:', {
        uid,
        transactionId: session.transactionId,
        errorName: e.name,
        errorMessage: e.message,
        stack: e.stack,
      });
      throw new HttpsError('invalid-argument', 'NICE 인증 결과 복호화에 실패했습니다.');
    }

    // 인증 결과 파싱 (NICE 검증값만 신뢰, 클라이언트 입력 불수용)
    const name       = (result.name || '').trim();
    const birthdate  = result.birthdate || '';       // YYYYMMDD
    const birthYear  = birthdate.length >= 4 ? parseInt(birthdate.slice(0, 4), 10) : null;
    const birthMonth = birthdate.length >= 6 ? parseInt(birthdate.slice(4, 6), 10) : null;
    const birthDay   = birthdate.length >= 8 ? parseInt(birthdate.slice(6, 8), 10) : null;
    const gender     = result.gender === '1' ? 'male' : 'female'; // 1=남, 0=여
    const di         = result.di || '';   // 중복가입방지 정보
    const ci         = result.ci || '';   // 연계정보

    // 휴대폰 본인확인 결과의 가입자 번호. 신 경로(niceAuth.js)와 **같은 규칙**
    // 으로 정규화하고, 알아볼 수 없으면 필드를 쓰지 않는다.
    // ⚠ 번호 원문은 어떤 로그에도 남기지 않는다.
    const phoneNumber = normalizeKoreanMobile(result.mobile_no);
    if (!phoneNumber) {
      console.warn('[NICE] mobile_no를 국내 휴대폰 번호로 알아보지 못해'
        + ` phoneNumber를 저장하지 않습니다. uid=${uid} present=${!!result.mobile_no}`);
    }

    // "1명의 실사용자 = 파티츄 계정 1개" — CI가 이미 다른 계정에 연결돼 있으면
    // already-exists로 거부되고 users 문서는 전혀 갱신되지 않는다(identityLink.js).
    await linkIdentityAndSaveVerification(db, {
      uid,
      ci,
      provider: 'nice_intc',
      userPatch: {
        // NICE 인증 잠금 필드 — Admin SDK만 쓸 수 있음 (Firestore Rules 참조)
        name,
        gender,
        birthYear,
        birthMonth,
        birthDay,
        di,
        ci,
        // 알아보지 못한 번호는 필드 자체를 만들지 않는다(niceAuth.js와 동일).
        ...(phoneNumber ? { phoneNumber } : {}),
        identityVerified:     true,
        identityVerifiedAt:   admin.firestore.FieldValue.serverTimestamp(),
        isVerified:           true,     // Firestore Rules 하위 호환
        verifiedAt:           admin.firestore.FieldValue.serverTimestamp(),
        profileCompleted:     true,
        verificationProvider: 'nice_intc',
      },
    });

    console.log(`[NICE] niceIntcResult 완료. uid=${uid}`);
    return { success: true };
  },
);

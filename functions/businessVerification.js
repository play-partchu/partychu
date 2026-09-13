// ── 사업자 인증 (국세청 사업자등록정보 진위확인 및 상태조회) ────────────────
//
// 계정 단위 인증이다. 한 번 verified가 되면 콘텐츠를 등록할 때마다 다시
// 입력할 필요가 없고, 파티/플레이스 문서에는 사업자 원문 정보를 절대 쓰지
// 않는다(공개 문서이므로 hostBusinessVerified 불리언만 미러링한다).
//
// **정본은 users/{uid}.businessVerification 맵 하나뿐이다.** 사업자 정보를
// 읽는 모든 경로가 이 맵만 본다:
//   · isBusinessVerified()           → createParty.js · partyRegistration.js ·
//                                       partyOpenState.js (오픈·예약 권한)
//   · firestore.rules isBusinessVerified() → parties create
//   · party_app  BusinessVerification / admin_app BusinessInfo (화면 표시)
//   · accountWithdrawal.js memberTypeOf()  (맵 존재 여부로 회원 유형)
// 사업자번호를 따로 복사해 두는 곳은 정산화면의 settlementInfo.businessNumber
// 하나인데, 그것은 자기신고 값이라 인증을 마친 계정에서는 이 맵의 값으로
// 채우고 읽기 전용으로 잠근다(settlement_info_screen.dart).
//
// ── 사업자번호는 바뀔 수 있다 ─────────────────────────────────────────────
// 최초 등록으로 끝이 아니다. 법인 전환·업종 변경·폐업 후 재개업으로 번호
// 자체가 바뀌므로, 이미 verified인 계정도 새 정보로 다시 인증할 수 있다.
// 그 판정은 전부 resolveVerificationWrite 한 곳에 있다 — 핵심은 **새 정보가
// 국세청을 통과한 순간에만 교체**하고, 실패했다고 기존 인증을 날리지 않는
// 것이다(날리면 그 순간 오픈·예약 권한이 통째로 막힌다).
//
// 통과 조건(사용자 정책):
//   · 사업자등록번호 + 대표자명 + 개업일자가 국세청 등록정보와 일치할 것
//   · 계속사업자일 것(휴업·폐업이면 통과시키지 않는다)
// 참고 정보(앱에만 저장하고 국세청에는 **보내지 않는다**):
//   · 상호명, 사업장 주소 — 본점/지점/실제 개최 장소가 다를 수 있다.
//
// ── 두 축: "사업자가 진짜인가"와 "이 계정이 그 사업자를 쓸 수 있는가" ─────
//
// 국세청 진위확인이 답하는 것은 **사업자 정보가 실재하는가** 하나뿐이다.
// 사업자등록번호·대표자명·개업일자는 사업자등록증 사본 한 장에 전부 적혀
// 있으므로, 그 셋만 맞히면 통과하는 구조는 곧 "남의 사업자등록증을 주운
// 사람이 사업자 호스트가 된다"는 뜻이다. 그래서 판정을 두 축으로 나눈다.
//
//   status         국세청이 확인한 **사업자 정보의 진위**       (예전 그대로)
//   authorization  이 계정이 그 사업자를 **쓸 수 있는 권한**    (여기서 신설)
//
// 두 값은 **함께만 움직인다** — 같이 쓰거나 둘 다 안 쓴다. 그 불변식을
// 집행하는 곳은 [resolveVerificationWrite] 하나뿐이다(두 값을 따로 쓰는
// 경로를 만들면 "status는 verified인데 authorization은 옛 값"이 생긴다).
//
//   'self'                 NICE 본인확인 실명 == 국세청이 확인한 대표자명이고,
//                          사업자번호 점유까지 성공.
//   'delegated'            대표자가 NICE 본인확인 후 이 계정에 운영 권한을
//                          명시적으로 부여했다(businessDelegation.js).
//                          근거 문서 id가 delegationId에 함께 적힌다.
//   'pendingOwnerApproval' 사업자는 확인됐지만 이 계정의 권한은 아직 없다
//                          (대표자명 불일치 · 다른 계정이 이미 점유 중 ·
//                           위임이 취소됨).
//   'none'                 사업자 확인 자체가 성립하지 않았다(status != verified).
//
// ⚠️ **이름이 같다는 것은 동일인의 증명이 아니다.** 동명이인이 남의
//    사업자등록증 3항목을 알고 있으면 'self'를 그대로 통과한다. 국세청
//    진위확인 응답에는 대표자의 CI도 생년월일도 연락처도 없고(응답은
//    valid '01'/'02'와 납세자 상태뿐), NICE 응답에는 사업자 정보가 없다 —
//    두 API의 교집합이 **이름 문자열 하나뿐**이라 현재 계약 범위에서 더
//    좁힐 방법이 없다. 이 한계는 없앤 것이 아니라 **줄인 것**이다(지금까지는
//    이름조차 보지 않았다). 남은 위험은 대표자 위임 2단계에서 다룬다.
//
// ── 사업자번호 점유(businessOwnership) ──────────────────────────────────
// 같은 사업자번호를 여러 계정이 동시에 'self'로 가져가면 안 된다. 그런데
// "where로 훑어보고 없으면 쓴다"는 중복을 막지 못한다 — 두 사람이 동시에
// 조회하면 둘 다 '없음'을 보고 둘 다 쓴다(nicknames.js와 똑같은 함정).
// 그래서 사업자번호 하나당 문서 하나를 두고, 그 문서의 점유를 트랜잭션으로
// 경쟁시킨다. 문서 id가 곧 잠금이다.
//
//   businessOwnership/{sha256(businessNumber)}
//     = { holderUid, representativeCiHash, representativeVerificationLevel,
//         status: 'active'|'released', ... }
//
// ⚠️ **점유 문서에 위임받은 운영자를 적지 않는다.** holderUid는 "대표자 본인의
//    계정"이고, 위임 운영자는 businessDelegations가 따로 관리한다. 한 칸을
//    같이 쓰면 대표자 본인이 나중에 자기 계정으로 인증할 때 자기 사업자에서
//    막힌다 — 정확히 거꾸로다.
//
// ── representativeCiHash가 **증명하는 것과 증명하지 않는 것** ───────────
// 이 값은 "이 사업자의 대표자라고 주장하며 NICE 본인확인을 통과한 자연인"이다.
// **대표자임이 증명된 사람이 아니다.**
//
// 지금 이 값이 만들어지는 근거는 [REP_VERIFICATION_LEVEL.nameMatched] 하나뿐이다:
//   NICE 실명 문자열 == 국세청이 확인해 준 대표자명 문자열
// 사업자등록증 3항목을 아는 동명이인은 이 조건을 그대로 통과한다. 그러므로
//
//   ⚠️ **먼저 온 사람이 진짜라는 보장이 없다.** 동명이인이 사업자등록정보를
//      알고 있으면 그 사람의 CI가 먼저 박히고, **나중에 온 실제 대표자가
//      오히려 막힌다.** 이 역전이 이 설계의 알려진 위험이고, 그래서 충돌은
//      자동으로 풀지 않고 사람에게 넘긴다(needsManualReview).
//
// 그래서 이 핀이 실제로 해주는 일은 **충돌 감지**다:
//   최초 확인 이후, 서로 다른 CI가 같은 사업자의 대표자를 주장하면 그것을
//   자동으로 알아채고 멈춘다. 어느 쪽이 진짜인지는 이 값이 답하지 못한다.
//
// 등급을 따로 적어 두는 이유가 이것이다([REP_VERIFICATION_LEVEL]). 사업자와
// CI를 직접 결합해 검증하는 수단(NICE 사업자 대표자 확인, 사업자 공동인증서
// 등)이 붙으면 그때 'strongVerified'가 생기고, 그 등급만이 "대표자임이
// 증명됐다"고 말할 수 있다. **현재 계약 범위에는 그런 수단이 없다.**
//
// 문서 id를 해시로 쓰는 것은 **경로 위생**이지 기밀이 아니다(10자리 숫자는
// 어차피 전수 대입이 가능하다) — 사업자번호가 로그·에러·모니터링 경로에
// 그대로 찍히지 않게 하려는 것이다(identityLinks가 CI를 해시하는 이유와 같다).
// 클라이언트 읽기·쓰기는 firestore.rules에서 전면 차단한다.
//
// ⚠️ b_nm(상호명)·b_adr(주소)를 validate에 실으면 안 된다. 국세청 진위확인은
//    선택 항목도 **일치 조건에 포함**시켜서, 사업자등록증 그대로 입력해도
//    표기 차이 하나로 valid=02가 난다. 2026-08-21 같은 실입력값 실측:
//      ① b_no+start_dt+p_nm            → valid=01 (일치)
//      ② ① + b_nm                      → valid=02 "확인할 수 없습니다."
//      ③ ① + b_adr                     → valid=02 "확인할 수 없습니다."
//      ④ ① + b_nm + b_adr (당시 운영본) → valid=02 "확인할 수 없습니다."
//    ②·③가 각각 단독으로 02를 만든다 — 즉 두 항목 모두 실패 원인이었다.
//
// 보안:
//   · 서비스키는 Secret Manager(NTS_SERVICE_KEY)에만 둔다. 클라이언트는
//     국세청 API를 직접 부르지 않는다.
//   · 로그에는 사업자번호 앞 3자리만 남긴다. 대표자명·개업일자·주소는
//     어떤 경로로도 로그에 남기지 않는다(요청 원문 로깅 금지).
//   · 결과는 users/{uid}.businessVerification에만 저장한다 — 본인/관리자만
//     읽을 수 있고(firestore.rules users 규칙), 클라이언트 쓰기는 차단된다.

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');
const https = require('https');
const crypto = require('crypto');

// 본인확인 게이트의 정본 — 앱 루트 게이트는 화면만 막는다(구버전 앱·SDK
// 직접 호출은 이 콜러블에 곧장 닿는다).
const { assertIdentityVerifiedData } = require('./identityGuard');
// 이름 대조는 **수취계좌 인증이 쓰는 그 함수를 그대로 쓴다.** 예금주 대조와
// 대표자 대조가 서로 다른 정규화 규칙으로 갈리면 한쪽만 고쳐져 어긋난다
// (payoutAccounts.js의 normalizeHolderName: 공백 제거 후 완전 일치).
const { holderMatches } = require('./payoutAccounts');
// CI 해시도 마찬가지 — identityLinks가 쓰는 계산을 그대로 쓴다.
const { ciHashOfUserData } = require('./identityLink');

const ntsServiceKey = defineSecret('NTS_SERVICE_KEY');

const NTS_HOST = 'api.odcloud.kr';
const NTS_STATUS_PATH = '/api/nts-businessman/v1/status';
const NTS_VALIDATE_PATH = '/api/nts-businessman/v1/validate';
// 7초는 **관측된 실패값**이다 — 인스턴스가 새로 뜬 직후 첫 호출이 정확히
// 7초에서 'NTS API timeout'으로 끊겼다(2026-08-21 09:21:50 로그). 콜드 스타트의
// 첫 TLS 핸드셰이크까지 포함되는 구간이라 여유를 준다. 두 번 호출해도
// 콜러블 timeoutSeconds(60초) 안에 끝난다.
const NTS_HTTP_TIMEOUT_MS = 12000;

// 국세청(odcloud) 게이트웨이는 **같은 요청에도 간헐적으로 5xx를 돌려준다.**
// 2026-08-21 실측: 서비스키·본문·헤더가 동일한 status 호출 12회 중 11회가
// http=500 {"code":-999,"msg":"UNKNOWN"} 또는 http=503 {"code":-5,...}였고
// 1회만 200 OK였다. 우리 요청에는 문제가 없으므로(같은 요청이 성공도 한다)
// 짧은 간격으로 몇 번 더 두드려 본다.
//
// 12초 × 3회 + 대기 1.4초 ≈ 37초로, 콜러블 timeoutSeconds(60초) 안에 끝난다.
const NTS_RETRY_ATTEMPTS = 3;
const NTS_RETRY_DELAY_MS = 700;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// 하루 시도 제한 — 국세청 API는 일 호출량이 제한돼 있고, 대표자명을
// 바꿔가며 남의 사업자번호를 맞춰보는 시도도 막아야 한다.
const MAX_ATTEMPTS_PER_DAY = 10;

// ── 사업자 정보 변경 ────────────────────────────────────────────────────
//
// 사업자등록번호는 **한 번 등록하면 끝**이 아니다. 법인 전환·업종 변경·폐업
// 후 재개업으로 번호 자체가 바뀔 수 있어서, 이미 인증을 마친 계정도 새
// 사업자정보로 다시 인증할 수 있어야 한다.
//
// 이때 절대 깨뜨리면 안 되는 것: **새 정보 검증에 실패했다고 기존 인증을
// 날리지 않는다.** 기존 인증이 사라지면 그 순간 파티 오픈·예약 수령 권한이
// 통째로 막힌다(firestore.rules의 isBusinessVerified, createParty.js,
// partyOpenState.js가 전부 status == 'verified' 하나만 본다). 잘못된 번호를
// 한 번 눌러본 대가가 영업 중단이어서는 안 된다.
//
// 그래서 판정 규칙은 [resolveVerificationWrite]에 한 곳으로 모아 두고,
// 성공한 순간에만 원자적으로 교체한다.

// 국세청 진위확인의 **판정 대상 3항목**. 이 중 하나라도 달라지면 "같은
// 사업자 재확인"이 아니라 "다른 사업자로 바꾸려는 시도"다.
const CORE_FIELDS = ['businessNumber', 'representativeName', 'openingDate'];

// ── 권한 축(authorization) ──────────────────────────────────────────────
// 값의 뜻은 파일 상단 "두 축" 절에 있다.
const AUTHORIZATION = {
  none: 'none',
  self: 'self',
  delegated: 'delegated',
  pendingOwnerApproval: 'pendingOwnerApproval',
};

/// **권한이 실제로 열리는 authorization 값.**
///
/// ⚠️ **authorization이 없는 문서를 봐주는 예외는 두지 않는다.** 예외를 하나
///    두는 순간 "authorization을 안 쓰면 통과"가 되어 이 판정 전체가 무력해진다.
const AUTHORIZED_VALUES = new Set([AUTHORIZATION.self, AUTHORIZATION.delegated]);

/// 권한이 열리지 않은 이유 — 화면 문구와 운영 추적용.
const AUTH_REASON = {
  /// NICE 본인확인 실명과 국세청이 확인한 대표자명이 다르다(타인 명의).
  representativeMismatch: 'representativeMismatch',
  /// 이 사업자번호를 이미 다른 계정이 점유하고 있다.
  ownedByAnotherAccount: 'ownedByAnotherAccount',
  /// 이름은 같지만, **기존에 확인된 대표자 본인확인 정보와 일치하지 않는다.**
  ///
  /// ⚠️ "이 사람이 대표자가 아니다"라는 뜻이 아니다. 먼저 확인된 쪽이 진짜라는
  ///    보장이 없으므로(파일 상단 참고), 이것은 **충돌 감지**이지 판정이 아니다.
  ///    어느 쪽이 진짜인지는 사람이 봐야 한다.
  representativeCiMismatch: 'representativeCiMismatch',
  /// 대표자가 부여했던 위임을 취소했다(businessDelegation.js).
  delegationRevoked: 'delegationRevoked',
};

// ── 사업자번호 점유 문서 ────────────────────────────────────────────────
const BUSINESS_OWNERSHIP = 'businessOwnership';
const OWNERSHIP_STATUS = { active: 'active', released: 'released' };

/**
 * 대표자 CI를 **무엇으로 확인했는가** — 핀의 신뢰 강도.
 *
 * 파일 상단 "증명하는 것과 증명하지 않는 것" 절이 이 등급의 이유다. 핀은
 * 하나의 필드지만 그 값이 얼마나 믿을 만한지는 어떻게 얻었느냐에 따라
 * 완전히 다르고, 그것을 적어 두지 않으면 코드를 읽는 사람이 항상 최대치로
 * 오해한다(실제로 그렇게 썼다가 고쳤다).
 */
const REP_VERIFICATION_LEVEL = {
  /// **이름 문자열이 같았다는 것뿐이다.** NICE 실명 == 국세청 대표자명.
  /// 사업자등록증 3항목을 아는 동명이인은 이 등급을 그대로 만들어낸다.
  ///
  /// 지금 이 코드베이스가 만들어내는 등급은 **이것 하나뿐이다** — 본인 명의
  /// 자동승인(self)도, 대표자 승인(businessDelegation)도 모두 여기에 속한다.
  /// 둘 중 어느 쪽도 사업자와 CI를 직접 결합해 확인하지 않는다.
  nameMatched: 'nameMatched',

  /// 사업자와 CI를 **직접 결합해** 확인한 수단으로 얻은 등급.
  /// (NICE 사업자 대표자 확인 상품, 사업자 공동인증서 서명 등)
  ///
  /// ⚠️ **현재 계약 범위에는 그런 수단이 없어 아무도 이 값을 만들지 않는다.**
  ///    수단이 붙기 전까지 이 값이 문서에 나타나면 그것은 오염이다.
  strongVerified: 'strongVerified',
};

/**
 * 기존 핀을 새 확인 결과가 **자동으로 대체할 수 있는가** — 순수 함수.
 *
 * 지금은 어떤 실제 입력에도 false다. 두 경로(self·대표자 승인)가 모두
 * nameMatched를 만들고, **이름 대조끼리는 우열이 없기 때문이다** — 먼저
 * 온 쪽이 옳다는 근거도, 나중에 온 쪽이 옳다는 근거도 없다. 그래서 충돌은
 * 자동으로 풀지 않고 사람에게 넘긴다.
 *
 * 이 함수를 따로 둔 것은 그 판단을 **한 곳에 이름 붙여 두기 위해서**다.
 * 나중에 strongVerified를 만드는 수단이 붙으면 고칠 곳이 여기 하나다.
 */
function canSupersedePin(existingLevel, incomingLevel) {
  return existingLevel === REP_VERIFICATION_LEVEL.nameMatched
    && incomingLevel === REP_VERIFICATION_LEVEL.strongVerified;
}

// 사업자 교체 이력 보관 개수 — 감사용이라 최근 것만 남긴다.
const BUSINESS_HISTORY_LIMIT = 5;

// 아직 공공데이터포털 활용신청이 끝나지 않아 시크릿이 비어 있는 동안의
// 값들. portOne.js와 같은 센티널 패턴이지만 **결론이 정반대**다 — 결제는
// 키가 없을 때 통과시켜도 되지만(테스트 결제), 사업자 인증은 키가 없다고
// 통과시키면 인증 자체가 무의미해진다. 그래서 여기서는 절대 verified를
// 주지 않고 'pending'(심사 필요)으로만 남긴다.
const UNSET_KEY_SENTINELS = new Set(['', 'TEST_MODE', 'REPLACE_WITH_NTS_SERVICE_KEY']);

// ── 입력 정규화 ────────────────────────────────────────────────────────
function digitsOnly(v) {
  return String(v == null ? '' : v).replace(/[^0-9]/g, '');
}

function normalizeBusinessNumber(v) {
  const d = digitsOnly(v);
  return d.length === 10 ? d : null;
}

// 'yyyy-mm-dd', 'yyyy.mm.dd', 'yyyymmdd' 모두 받아 'yyyymmdd'로.
function normalizeOpeningDate(v) {
  const d = digitsOnly(v);
  if (d.length !== 8) return null;
  const y = Number(d.slice(0, 4));
  const m = Number(d.slice(4, 6));
  const day = Number(d.slice(6, 8));
  if (y < 1900 || y > 2200) return null;
  if (m < 1 || m > 12) return null;
  if (day < 1 || day > 31) return null;
  return d;
}

/// 국세청 진위확인 요청 본문 — **필수 3개만** 담는다.
///
/// 여기에 항목을 더 얹고 싶어지면 위 헤더의 실측표를 먼저 보라. 선택 항목은
/// "더 정확한 검증"이 아니라 "더 자주 실패하는 검증"이다.
function buildValidatePayload(bNo, startDt, pNm) {
  return { b_no: bNo, start_dt: startDt, p_nm: pNm };
}

// 로그용 — 앞 3자리만 남긴다. ('1234567890' → '123*******')
function maskBusinessNumber(bNo) {
  const d = digitsOnly(bNo);
  if (d.length !== 10) return '***';
  return `${d.slice(0, 3)}*******`;
}

// ── 국세청 응답 해석 (순수 함수 — 네트워크 없이 셀프체크 가능) ──────────
//
// statusData   : status API의 data[0] (없으면 null)
// validateData : validate API의 data[0] (없으면 null)
//
// 반환: { status, failReason, ntsStatusCode, ntsStatusLabel, taxType,
//         nameMatched, addressMatched }
//   status: 'verified' | 'failed' | 'suspended' | 'pending'
function evaluateNtsResult(statusData, validateData) {
  const base = {
    status: 'failed',
    failReason: 'unknown',
    ntsStatusCode: '',
    ntsStatusLabel: '',
    taxType: '',
    nameMatched: null,
    addressMatched: null,
  };

  if (!statusData) {
    return { ...base, failReason: 'apiUnavailable', status: 'pending' };
  }

  const sttCd = String(statusData.b_stt_cd || '').trim();
  const sttLabel = String(statusData.b_stt || '').trim();
  const taxType = String(statusData.tax_type || '').trim();

  // 등록되지 않은 사업자등록번호는 b_stt_cd가 빈 문자열로 온다
  // (tax_type에 "국세청에 등록되지 않은 사업자등록번호입니다."가 담긴다).
  if (!sttCd) {
    return { ...base, failReason: 'notRegistered', taxType };
  }

  const withStatus = {
    ...base,
    ntsStatusCode: sttCd,
    ntsStatusLabel: sttLabel,
    taxType,
  };

  // '01' 계속사업자 / '02' 휴업자 / '03' 폐업자
  if (sttCd === '02' || sttCd === '03') {
    return {
      ...withStatus,
      status: 'suspended',
      failReason: sttCd === '03' ? 'closed' : 'suspended',
    };
  }
  if (sttCd !== '01') {
    return { ...withStatus, failReason: 'unexpectedStatus' };
  }

  // 계속사업자 확인 후 진위확인 결과를 본다.
  if (!validateData) {
    return { ...withStatus, status: 'pending', failReason: 'apiUnavailable' };
  }

  // 참고 항목 — 국세청이 "일치/불일치"를 단정해주지 않으므로 실패 조건으로
  // 쓰지 않는다. valid_msg에 언급이 있으면 불일치로 기록만 해둔다.
  const validMsg = String(validateData.valid_msg || '');
  const mentions = (kw) => (validMsg.includes(kw) ? false : null);

  const valid = String(validateData.valid || '').trim();
  if (valid !== '01') {
    return {
      ...withStatus,
      failReason: 'mismatch',
      nameMatched: mentions('상호'),
      addressMatched: mentions('주소'),
    };
  }

  return {
    ...withStatus,
    status: 'verified',
    failReason: null,
    nameMatched: mentions('상호'),
    addressMatched: mentions('주소'),
  };
}

// ── 변경 판정 (순수 함수 — 네트워크 없이 셀프체크 가능) ─────────────────

/// 점유 문서 id. 해시는 경로 위생용이다(파일 상단 주석 참고).
function businessNumberHash(bNo) {
  return crypto.createHash('sha256').update(digitsOnly(bNo), 'utf8').digest('hex');
}

/**
 * **사업자 권한의 유일한 판정식** — status와 authorization을 둘 다 본다.
 *
 * 이 함수가 곧 [isBusinessVerified]의 본체이고, firestore.rules의
 * isBusinessVerified()가 같은 두 조건을 규칙 문법으로 다시 쓴다. 두 곳이
 * 갈리면 "앱은 되는데 규칙이 막는" 상태가 되므로 조건을 바꿀 때는 둘 다 본다.
 */
function isBusinessAuthorized(bv) {
  if (!bv || bv.status !== 'verified') return false;
  if (!AUTHORIZED_VALUES.has(bv.authorization)) return false;
  // 위임 권한은 **근거 문서를 가리켜야** 인정한다. delegationId가 비어 있는
  // 'delegated'는 어떤 정상 경로로도 만들어지지 않으므로(세 값을 함께 쓰는
  // 불변식), 그런 문서가 보이면 손상된 것으로 보고 권한을 주지 않는다.
  if (bv.authorization === AUTHORIZATION.delegated) {
    return typeof bv.delegationId === 'string' && bv.delegationId.length > 0;
  }
  return true;
}

/**
 * 이번 결과에 **어떤 권한을 줄지** 정한다 — 순수 함수(네트워크·Firestore 없음).
 *
 * 순서가 규칙이다. 사업자 자체가 확인되지 않았으면 권한을 따질 것이 없고,
 * 대표자명이 다르면 점유를 볼 이유가 없다(점유를 시도조차 하지 않는다 —
 * 남의 사업자번호를 선점하는 길이 열리면 안 된다).
 *
 * ── 대표자 CI 핀: 충돌 감지 ───────────────────────────────────────────
 * 이 사업자에 [representativeCiHash]가 이미 있으면(= 누군가 이 사업자의
 * 대표자라고 주장하며 NICE를 통과한 적이 있다), 이름이 같아도 **CI가 다르면
 * self를 주지 않는다.**
 *
 * ⚠️ 이것은 "먼저 온 사람이 진짜 대표자"라는 판정이 **아니다.** 핀의 등급이
 *    nameMatched뿐이라 먼저 온 쪽도 동명이인일 수 있다. 여기서 하는 일은
 *    **서로 다른 CI가 같은 사업자의 대표자를 주장한다는 충돌을 알아채고
 *    멈추는 것**뿐이고, 어느 쪽이 진짜인지는 사람이 정한다.
 *
 * 그래서 **자동으로 덮어쓰지도, 자동으로 권한을 주지도 않는다**
 * ([canSupersedePin]이 그 판단의 유일한 지점이다).
 *
 * @param {object}      outcome              국세청 판정([evaluateNtsResult])
 * @param {boolean}     nameMatchesIdentity  NICE 실명 == 입력한 대표자명
 * @param {string|null} ownershipHolderUid   이 번호를 지금 점유 중인 uid
 * @param {string|null} ownershipRepCiHash   이 사업자에 이미 박힌 대표자 CI 해시
 * @param {string}      ownershipRepLevel    그 핀의 확인 등급
 * @param {string|null} identityCiHash       요청한 계정의 CI 해시
 * @param {string}      uid                  요청한 계정
 * @returns {{authorization: string, authorizationReason: string|null, claimOwnership: boolean, delegationId: null}}
 */
function decideAuthorization({
  outcome,
  nameMatchesIdentity,
  ownershipHolderUid,
  ownershipRepCiHash = null,
  ownershipRepLevel = REP_VERIFICATION_LEVEL.nameMatched,
  identityCiHash = null,
  uid,
}) {
  const blocked = (reason) => ({
    authorization: AUTHORIZATION.pendingOwnerApproval,
    authorizationReason: reason,
    claimOwnership: false,
    delegationId: null,
  });

  if (!outcome || outcome.status !== 'verified') {
    return {
      authorization: AUTHORIZATION.none,
      authorizationReason: null,
      claimOwnership: false,
      delegationId: null,
    };
  }
  if (!nameMatchesIdentity) {
    return blocked(AUTH_REASON.representativeMismatch);
  }
  // ── 이 사업자에 이미 대표자 CI가 박혀 있는 경우 ─────────────────────
  //   같으면 → 계정이 달라도 같은 자연인이다(탈퇴 후 재가입 등). 통과시킨다.
  //            여기서 uid 점유까지 따지면 **본인이 자기 사업자에서 막힌다.**
  //   다르면 → 서로 다른 CI가 같은 사업자의 대표자를 주장하는 **충돌**이다.
  //            누가 진짜인지 여기서 정하지 않는다 — 자동 대체도, 자동 권한
  //            부여도 하지 않고 멈춘다.
  if (ownershipRepCiHash) {
    if (ownershipRepCiHash === identityCiHash) {
      return {
        authorization: AUTHORIZATION.self,
        authorizationReason: null,
        claimOwnership: true,
        delegationId: null,
      };
    }
    // 이번 확인도 이름 대조 등급이다 — 기존 핀과 우열을 가릴 근거가 없다.
    return canSupersedePin(ownershipRepLevel, REP_VERIFICATION_LEVEL.nameMatched)
      ? {
        authorization: AUTHORIZATION.self,
        authorizationReason: null,
        claimOwnership: true,
        delegationId: null,
      }
      : blocked(AUTH_REASON.representativeCiMismatch);
  }

  // CI를 아직 모르는 사업자 — 예전처럼 계정 점유로만 가른다.
  if (ownershipHolderUid && ownershipHolderUid !== uid) {
    return blocked(AUTH_REASON.ownedByAnotherAccount);
  }
  return {
    authorization: AUTHORIZATION.self,
    authorizationReason: null,
    claimOwnership: true,
    delegationId: null,
  };
}

/// 점유 문서에서 "지금 이 번호를 잡고 있는 uid"를 읽는다.
/// released는 아무도 잡고 있지 않은 것으로 본다(identityLink.isLinkBlocking과 같은 결).
function ownershipHolderOf(data) {
  if (!data || data.status !== OWNERSHIP_STATUS.active) return null;
  return data.holderUid || null;
}

/// 이 사업자의 대표자라고 **주장하며 본인확인을 통과한 자연인**(CI 해시).
/// 없으면 null. 대표자임이 증명된 사람이 아니다(파일 상단 주석).
///
/// holderUid와 달리 released 여부를 보지 않는다 — 계정 점유는 풀려도 "이
/// 사업자에 대해 누가 대표자라고 주장했는가"는 남아 있어야 나중에 들어오는
/// 다른 CI와의 충돌을 알아챌 수 있다.
function representativeCiHashOf(data) {
  return (data && data.representativeCiHash) || null;
}

/// 그 핀을 **무엇으로 확인했는가**([REP_VERIFICATION_LEVEL]).
///
/// 등급이 적혀 있지 않은 옛 문서는 nameMatched로 읽는다 — 모르는 것을
/// 강한 등급으로 승격시키지 않는다(fail-closed).
function representativeLevelOf(data) {
  const v = data && data.representativeVerificationLevel;
  return v === REP_VERIFICATION_LEVEL.strongVerified
    ? REP_VERIFICATION_LEVEL.strongVerified
    : REP_VERIFICATION_LEVEL.nameMatched;
}

/** 이번 입력이 기존 기록과 **다른 사업자**인가(판정 3항목 기준). */
function coreFieldsChanged(prev, input) {
  return CORE_FIELDS.some(
    (k) => String((prev && prev[k]) || '') !== String((input && input[k]) || ''),
  );
}

/**
 * 국세청 응답 + 입력값 + 권한 판정으로 만드는 평평한 인증 기록(교체용 전체 레코드).
 *
 * ⚠️ status·authorization·delegationId를 **한 함수에서 함께** 만든다. 권한을
 *    나중에 덧붙이는 형태로 두면 "status만 쓰고 authorization은 안 쓴" 경로가
 *    생기고, 그 순간 옛 'self'나 옛 위임 문서가 새 사업자에 그대로 얹힌다.
 */
function buildVerificationRecord(input, outcome, decision) {
  return {
    status: outcome.status,
    authorization: decision.authorization,
    authorizationReason: decision.authorizationReason,
    // 위임이 아닐 때는 반드시 null로 **지운다** — merge 저장이라 명시하지
    // 않으면 옛 위임 문서 id가 남고, 그 id가 권한의 근거로 읽힌다.
    delegationId: decision.delegationId || null,
    businessNumber: input.businessNumber,
    representativeName: input.representativeName,
    openingDate: input.openingDate,
    // 참고 정보 — 인증 통과 조건이 아니다.
    businessName: input.businessName,
    businessAddress: input.businessAddress,
    businessBaseAddress: input.businessBaseAddress,
    businessDetailAddress: input.businessDetailAddress,
    nameMatched: outcome.nameMatched,
    addressMatched: outcome.addressMatched,
    ntsStatusCode: outcome.ntsStatusCode,
    ntsStatusLabel: outcome.ntsStatusLabel,
    taxType: outcome.taxType,
    failReason: outcome.failReason,
  };
}

/** 교체되는 옛 사업자를 이력에 덧붙인다(최근 [BUSINESS_HISTORY_LIMIT]건만). */
function appendHistory(prev, replacedAt) {
  const existing = Array.isArray(prev.history) ? prev.history : [];
  return [
    ...existing,
    {
      businessNumber: prev.businessNumber || '',
      businessName: prev.businessName || '',
      representativeName: prev.representativeName || '',
      openingDate: prev.openingDate || '',
      // ⚠️ 배열 원소에는 serverTimestamp()를 쓸 수 없다 — 호출부가 확정된
      //    Timestamp(replacedAt)를 넘긴다.
      verifiedAt: prev.verifiedAt || null,
      replacedAt,
    },
  ].slice(-BUSINESS_HISTORY_LIMIT);
}

/**
 * 이번 시도의 결과를 `users.businessVerification`에 **어떻게 반영할지** 정한다.
 *
 * 반환 `{ record, mode, numberChanged }` — record는 `set(..., {merge:true})`에
 * 그대로 넘길 부분 맵이다(merge라 record에 없는 키는 보존된다).
 *
 * mode:
 *   'replaced'     새 정보로 교체(성공). 번호가 바뀌었으면 감사 기록도 남긴다.
 *   'keptVerified' 기존 인증을 **그대로 두고** 실패한 변경 시도만 pendingChange에 기록.
 *   'overwritten'  예전과 동일하게 덮어쓴다(최초 인증 경로 · 같은 번호 휴폐업 반영).
 *
 * 네 갈래를 이렇게 가른다:
 *
 * ⚠️ 지켜야 할 것은 "국세청을 통과한 기록"이 아니라 **지금 실제로 쓰이고 있는
 *    권한**이다. 그래서 기존 상태는 status가 아니라 [isBusinessAuthorized]로,
 *    이번 결과는 "verified"가 아니라 **"verified이면서 권한까지 열리는가"**로
 *    본다. 이 구분이 없으면 대표자명이 다른 사업자를 한 번 통과시켜 보는
 *    것만으로 멀쩡히 쓰던 기존 권한이 날아간다.
 *
 *  | 기존 권한 | 이번 결과                    | 처리        | 이유 |
 *  |-----------|------------------------------|-------------|------|
 *  | 무엇이든  | verified + **권한 열림**     | replaced    | 쓸 수 있게 된 순간에만 교체한다(원자적). |
 *  | 없음      | 실패/보류/권한없는 verified  | overwritten | 지킬 권한이 없다 — 예전 동작 그대로. |
 *  | 있음      | 실패 + **정보 변경**         | keptVerified| 새 번호가 틀렸다고 기존 영업을 끊을 수 없다. |
 *  | 있음      | 보류(API 장애·키없음)        | keptVerified| 국세청이 아무 결론도 내지 않았다 — 모름은 취소 사유가 아니다. |
 *  | 있음      | **권한없는 verified** + 정보 변경 | keptVerified| 남의 명의 사업자를 확인해 본 것뿐이다. 쓰던 권한을 뺏을 일이 아니다. |
 *  | 있음      | 실패 + **같은 정보**         | overwritten | 같은 번호가 휴·폐업/불일치로 나온 것은 국세청이 내린 결론이라 반영해야 한다. |
 *  | 있음      | **권한없는 verified** + 같은 정보 | overwritten | 같은 번호인데 권한이 사라졌다(점유 이전 등) — 반영해야 한다. |
 *
 * 마지막 두 줄이 이 함수의 존재 이유다 — "기존 권한을 지킨다"를 무조건으로
 * 만들면 폐업한 사업자가, 그리고 남에게 넘어간 사업자가 영원히 살아남는다.
 *
 * ⚠️ keptVerified 갈래는 record에 status도 authorization도 담지 않는다. 그래서
 *    merge 저장이 기존 두 값을 **함께** 보존한다 — 둘이 어긋날 수 없다.
 */
function resolveVerificationWrite({
  prev,
  outcome,
  decision,
  input,
  now,
  historyNow,
  todayKey,
  attemptsToday,
}) {
  const prevRecord = prev || {};
  const prevUsable = isBusinessAuthorized(prevRecord);
  // 이번 시도가 **실제로 쓸 수 있는 권한까지** 만들어내는가.
  const usableNow =
    outcome.status === 'verified' && AUTHORIZED_VALUES.has(decision.authorization);
  const changed = coreFieldsChanged(prevRecord, input);
  const numberChanged =
    String(prevRecord.businessNumber || '') !== input.businessNumber;
  // 하루 시도 제한은 어느 갈래로 가든 똑같이 센다.
  const attempt = { attemptDate: todayKey, attemptCount: attemptsToday + 1 };

  if (usableNow) {
    const record = {
      ...buildVerificationRecord(input, outcome, decision),
      ...attempt,
      lastCheckedAt: now,
      // 권한이 열린 시각. verifiedAt(사업자 확인 시각)과 일부러 나눠 둔다 —
      // 나중에 위임이 붙으면 "언제 확인됐나"와 "언제 쓸 수 있게 됐나"가
      // 서로 다른 사건이 된다.
      authorizedAt: now,
      // 지난 변경 시도의 흔적은 성공과 함께 지운다(merge라 명시하지 않으면 남는다).
      pendingChange: null,
      // verifiedAt은 "지금 이 사업자번호가 처음 통과한 시각"이다. 같은 번호를
      // 다시 확인한 것뿐이면 최초 인증일을 유지하고, 번호가 바뀌었으면 새
      // 사업자의 인증일이므로 지금으로 다시 잡는다.
      verifiedAt:
        !numberChanged && prevRecord.verifiedAt ? prevRecord.verifiedAt : now,
    };
    if (numberChanged && prevRecord.businessNumber) {
      record.previousBusinessNumber = prevRecord.businessNumber;
      record.previousVerifiedAt = prevRecord.verifiedAt || null;
      record.changedAt = now;
      record.changeCount = (prevRecord.changeCount || 0) + 1;
      record.history = appendHistory(prevRecord, historyNow);
    }
    return { record, mode: 'replaced', numberChanged };
  }

  // 'pending'은 "국세청이 답을 주지 못했다"는 뜻이다(API 장애·서비스키 미설정).
  // 불일치·휴폐업처럼 국세청이 내린 결론과 구분해야 한다.
  const inconclusive = outcome.status === 'pending';

  if (prevUsable && (changed || inconclusive)) {
    return {
      // ⚠️ 여기서는 기존 레코드의 어떤 필드도 건드리지 않는다 — status·
      //    businessNumber는 물론 lastCheckedAt도 그대로 둔다(그 값은 "인증된
      //    사업자를 마지막으로 확인한 시각"이라 다른 사업자 시도로 갱신하면
      //    관리자 화면이 거짓말을 한다). 시도 시각은 pendingChange 안에 남는다.
      record: {
        ...attempt,
        pendingChange: {
          status: outcome.status,
          // 이번 변경 시도가 왜 권한을 못 얻었는지 — 화면이 "인증 실패"와
          // "대표자 확인 필요"를 가르는 근거다.
          authorization: decision.authorization,
          authorizationReason: decision.authorizationReason,
          delegationId: decision.delegationId || null,
          failReason: outcome.failReason,
          businessNumber: input.businessNumber,
          representativeName: input.representativeName,
          openingDate: input.openingDate,
          businessName: input.businessName,
          businessAddress: input.businessAddress,
          businessBaseAddress: input.businessBaseAddress,
          businessDetailAddress: input.businessDetailAddress,
          ntsStatusLabel: outcome.ntsStatusLabel,
          taxType: outcome.taxType,
          attemptedAt: now,
        },
      },
      mode: 'keptVerified',
      numberChanged,
    };
  }

  const record = {
    ...buildVerificationRecord(input, outcome, decision),
    ...attempt,
    lastCheckedAt: now,
    pendingChange: null,
    // 권한이 열리지 않은 갈래다 — 옛 값이 남지 않도록 명시적으로 지운다.
    authorizedAt: null,
  };
  // verifiedAt은 "**지금 이 사업자번호가** 국세청을 통과한 시각"이다.
  if (!numberChanged && prevRecord.verifiedAt) {
    // 같은 번호가 휴·폐업/불일치로 나온 경우 — 최초 통과 시각은 이력으로
    // 남기되 status는 방금 결과를 따른다.
    record.verifiedAt = prevRecord.verifiedAt;
  } else if (outcome.status === 'verified') {
    // 사업자 자체는 확인됐는데 권한만 없는 경우(타인 명의)에도 확인 시각은
    // 남긴다 — "언제 국세청을 통과했나"는 권한과 무관한 사실이다.
    record.verifiedAt = now;
  } else if (prevRecord.verifiedAt) {
    // 번호가 바뀌어 옛 통과 시각이 무의미해졌다 — merge 저장이라 명시적으로
    // 지우지 않으면 **다른 사업자의 날짜**가 그대로 남는다.
    record.verifiedAt = null;
  }
  return { record, mode: 'overwritten', numberChanged };
}

// ── HTTP ───────────────────────────────────────────────────────────────
// 응답은 { statusCode, body, raw, elapsedMs }로 돌려준다.
//   · body     : JSON.parse 결과(파싱 실패면 null)
//   · raw      : 로그용 원문 **앞 300자**. 개인정보가 실릴 수 있는 validate
//                응답에는 쓰지 않는다([logNtsFailure]의 includeRaw 참고).
//   · elapsedMs: 요청~응답 실측. 타임아웃인지 게이트웨이 거절인지 가른다.
function postNts(path, serviceKey, payload) {
  const body = JSON.stringify(payload);
  const fullPath = `${path}?serviceKey=${encodeURIComponent(serviceKey)}`;
  const startedAt = Date.now();

  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        hostname: NTS_HOST,
        path: fullPath,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'application/json',
          'Content-Length': Buffer.byteLength(body),
        },
        timeout: NTS_HTTP_TIMEOUT_MS,
      },
      (res) => {
        let raw = '';
        res.on('data', (c) => { raw += c; });
        res.on('end', () => {
          let parsed = null;
          try {
            parsed = JSON.parse(raw);
          } catch (_) {
            parsed = null; // 게이트웨이가 HTML/XML 오류를 돌려준 경우
          }
          resolve({
            statusCode: res.statusCode,
            body: parsed,
            raw: raw.slice(0, 300),
            elapsedMs: Date.now() - startedAt,
          });
        });
      },
    );
    req.on('timeout', () => {
      req.destroy(
        new Error(`NTS API timeout (${NTS_HTTP_TIMEOUT_MS}ms elapsed=${Date.now() - startedAt}ms path=${path})`),
      );
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

/// 국세청 호출 실패를 **원인이 보이게** 남긴다.
///
/// 예전에는 `http=503` 하나만 찍혀서 "503이 왜 났는지"를 알 수 없었다.
/// 응답 본문의 status_code(국세청 결과 코드)와 소요시간까지 함께 남긴다.
///
/// ⚠️ [includeRaw]는 **status 호출에서만** 켠다. validate 응답에는
/// request_param으로 대표자명·개업일자·주소가 그대로 돌아오므로, 원문을
/// 로그에 남기면 이 파일 상단의 "요청 원문 로깅 금지" 원칙이 깨진다.
function logNtsFailure(tag, { uid, masked, res, includeRaw }) {
  const ntsCode = res && res.body ? res.body.status_code : undefined;
  const parts = [
    `[bizVerify] ${tag} 실패.`,
    `uid=${uid}`,
    `bNo=${masked}`,
    `http=${res ? res.statusCode : '-'}`,
    `ntsCode=${ntsCode === undefined ? '-' : ntsCode}`,
    `elapsedMs=${res ? res.elapsedMs : '-'}`,
  ];
  if (includeRaw && res && res.raw) parts.push(`body=${res.raw}`);
  console.error(parts.join(' '));
}

/// 5xx·네트워크 오류만 재시도한다.
///
/// 4xx(서비스키 오류·잘못된 요청)는 다시 보내도 같은 답이 오므로 그대로
/// 돌려준다 — 국세청 일 호출량을 헛되이 쓰지 않기 위해서다.
/// 마지막 시도까지 실패하면 마지막 응답을 그대로 돌려주고(호출부가 기존대로
/// 실패 처리), 예외로 끝났으면 그 예외를 그대로 올린다.
async function postNtsWithRetry(tag, path, serviceKey, payload, { uid, masked }) {
  let lastRes = null;
  for (let attempt = 1; attempt <= NTS_RETRY_ATTEMPTS; attempt += 1) {
    try {
      const res = await postNts(path, serviceKey, payload);
      if (res.statusCode < 500) return res; // 성공이든 4xx든 결론이 난 응답
      lastRes = res;
      logNtsFailure(`${tag} ${attempt}/${NTS_RETRY_ATTEMPTS}`, {
        uid,
        masked,
        res,
        includeRaw: tag === 'status API',
      });
    } catch (err) {
      console.error(
        `[bizVerify] ${tag} ${attempt}/${NTS_RETRY_ATTEMPTS} 예외. uid=${uid} bNo=${masked} `
        + `errName=${err && err.name} errCode=${(err && err.code) || '-'} msg=${err && err.message}`,
      );
      if (attempt === NTS_RETRY_ATTEMPTS) throw err;
      lastRes = null;
    }
    if (attempt < NTS_RETRY_ATTEMPTS) await sleep(NTS_RETRY_DELAY_MS);
  }
  return lastRes;
}

function resolveServiceKey() {
  let value = '';
  try {
    value = (ntsServiceKey.value() || '').trim();
  } catch (_) {
    value = '';
  }
  return UNSET_KEY_SENTINELS.has(value) ? null : value;
}

// ── 계정 쪽 전제 ───────────────────────────────────────────────────────

/**
 * users 문서 하나로 정해지는 **계정 쪽 전제**를 한자리에서 세운다.
 *
 * 두 가지를 함께 하는 이유: 본인확인 게이트와 이름 대조는 **같은 사실**의
 * 앞뒷면이다. 자동승인의 대조 기준이 `users.name`(NICE로 확인된 실명)인데,
 * 본인확인이 없으면 그 값이 비어 있거나 아무 문자열이나 들어 있을 수 있다.
 * 게이트를 다른 곳에 두면 "게이트는 통과했는데 대조 기준이 없는" 조합이
 * 만들어지고, 그때 비교는 조용히 빈 문자열끼리의 비교가 된다.
 *
 * ⚠️ 앱의 루트 게이트(party_app/lib/utils/root_gate.dart)는 **화면만** 막는다.
 *    구버전 앱과 SDK 직접 호출은 콜러블에 곧장 닿으므로, 서버가 users 문서를
 *    직접 읽어 판정하는 이 지점이 실질적인 관문이다(identityGuard.js 참고).
 *    요청 payload에 identityVerified 같은 값이 실려 와도 쳐다보지 않는다.
 *
 * @throws {HttpsError} 본인확인을 마치지 않은 계정
 */
function resolveIdentityBasis(userData, representativeName) {
  assertIdentityVerifiedData(userData);
  const data = userData || {};
  return {
    // ⚠️ 이름이 같다는 것이 동일인의 증명은 아니다(파일 상단 주석).
    nameMatchesIdentity: holderMatches(data.name, representativeName),
    ownerCiHash: ciHashOfUserData(data),
  };
}

// ── 저장 ───────────────────────────────────────────────────────────────

/**
 * 국세청 판정을 **users 문서와 사업자번호 점유에 함께** 반영한다.
 *
 * 둘을 한 트랜잭션에 묶는 것이 이 함수의 존재 이유다. 나뉘면 "권한은
 * self인데 점유는 실패한" 상태가 만들어질 수 있고, 그 상태가 바로 이
 * 단계가 막으려는 것(같은 사업자번호를 두 계정이 동시에 쓰는 것)이다.
 *
 * 트랜잭션 안에서 사용자 문서를 **다시 읽는다** — 국세청 호출에 수 초가
 * 걸리는 동안 다른 요청이 같은 문서를 바꿨을 수 있다. Firestore가 충돌로
 * 재시도하면 이 함수 전체가 새 값으로 다시 도는데, 판정이 전부 순수
 * 함수(decideAuthorization · resolveVerificationWrite)라 그래도 안전하다.
 *
 * 콜러블 밖으로 꺼내 둔 것은 **경쟁 상황을 테스트할 수 있게** 하기
 * 위해서다(businessVerification.selfcheck.js의 가짜 Firestore).
 *
 * @returns {Promise<{mode: string, numberChanged: boolean, decision: object}>}
 */
async function applyVerificationOutcome(db, {
  uid,
  outcome,
  input,
  nameMatchesIdentity,
  ownerCiHash,
  masked,
  todayKey,
}) {
  const bNo = input.businessNumber;
  const userRef = db.collection('users').doc(uid);
  const ownerRef = db.collection(BUSINESS_OWNERSHIP).doc(businessNumberHash(bNo));

  return db.runTransaction(async (tx) => {
    // ⚠️ Firestore 트랜잭션은 **모든 읽기를 쓰기보다 먼저** 끝내야 한다.
    const freshSnap = await tx.get(userRef);
    const freshUser = freshSnap.data() || {};
    const freshPrev = freshUser.businessVerification || {};

    // 점유 문서는 국세청을 통과했을 때만 읽는다 — 통과하지 못한 시도가 남의
    // 점유 문서를 들여다볼 이유가 없다.
    //
    // ⚠️ 이 읽기가 곧 잠금이다. 두 계정이 동시에 같은 번호를 잡으러 오면
    //    둘 다 '비어 있음'을 보지만, 먼저 커밋한 쪽만 성공하고 나머지는
    //    Firestore가 재시도시킨다 — 재시도에서는 문서가 보이므로
    //    decideAuthorization이 pendingOwnerApproval로 갈린다.
    const ownerSnap = outcome.status === 'verified' ? await tx.get(ownerRef) : null;
    const ownerData = ownerSnap && ownerSnap.exists ? ownerSnap.data() : null;
    const holderUid = ownershipHolderOf(ownerData);
    const ownershipRepCiHash = representativeCiHashOf(ownerData);
    const ownershipRepLevel = representativeLevelOf(ownerData);

    // 이 계정이 지금 잡고 있는 **다른** 번호 — 새 번호를 점유하면 놓아준다.
    const prevNo = normalizeBusinessNumber(freshPrev.businessNumber);
    const prevOwnerRef =
      prevNo && prevNo !== bNo
        ? db.collection(BUSINESS_OWNERSHIP).doc(businessNumberHash(prevNo))
        : null;
    const prevOwnerSnap = prevOwnerRef ? await tx.get(prevOwnerRef) : null;

    const decision = decideAuthorization({
      outcome,
      nameMatchesIdentity,
      ownershipHolderUid: holderUid,
      ownershipRepCiHash,
      ownershipRepLevel,
      identityCiHash: ownerCiHash,
      uid,
    });

    // 시도 횟수도 방금 읽은 값으로 다시 센다 — 트랜잭션 밖에서 읽은 값으로
    // 세면 동시 요청 하나가 통째로 사라진다.
    const attemptsNow =
      freshPrev.attemptDate === todayKey ? (freshPrev.attemptCount || 0) : 0;

    const now = admin.firestore.FieldValue.serverTimestamp();

    // 어떻게 반영할지는 전부 resolveVerificationWrite가 정한다 — 특히
    // "실패했는데 기존 권한을 지켜야 하는가"를 여기서 다시 판단하지 않는다.
    const resolved = resolveVerificationWrite({
      prev: freshPrev,
      outcome,
      decision,
      input,
      now,
      // 이력 배열 원소용 — 배열 안에는 serverTimestamp()를 넣을 수 없다.
      historyNow: admin.firestore.Timestamp.now(),
      todayKey,
      attemptsToday: attemptsNow,
    });

    tx.set(userRef, { businessVerification: resolved.record }, { merge: true });

    if (decision.claimOwnership) {
      // 점유 문서는 **merge 없이 통째로** 쓴다 — 남이 놓아준(released) 문서를
      // 이어받는 경우 releasedAt 같은 흔적이 남으면 안 된다
      // (identityLink.js가 링크 문서를 다시 쓰는 것과 같은 이유).
      const keepClaimedAt =
        ownerData && ownerData.holderUid === uid
          ? ownerData.claimedAt || null
          : null;
      tx.set(ownerRef, {
        // 원문 대신 마스킹만 남긴다 — 이 문서를 보는 사람에게 필요한 것은
        // "어느 번호인지 알아보는 것"이지 번호 자체가 아니다.
        businessNumberMasked: masked,
        holderUid: uid,
        holderRole: 'owner',
        // 이 계정이 대표자라고 주장했고 **이름 문자열이 일치했다**. 그 자연인을
        // 사업자에 적어 둔다 — 나중에 다른 CI가 같은 주장을 하면 충돌로
        // 알아채기 위해서다. 대표자 승인(businessDelegation.js)도 같은 칸을 쓴다.
        //
        // ⚠️ 등급을 반드시 함께 적는다. 이름 대조뿐이라는 사실이 값과 떨어지면
        //    읽는 쪽이 "확인된 대표자"로 오해한다.
        representativeCiHash: ownerCiHash || null,
        representativeVerificationLevel: REP_VERIFICATION_LEVEL.nameMatched,
        representativeSource: 'selfClaim',
        status: OWNERSHIP_STATUS.active,
        claimedAt: keepClaimedAt || now,
        updatedAt: now,
        releasedAt: null,
        releasedFromUid: null,
      });

      // 번호를 바꿔 다시 인증한 경우 옛 번호의 점유를 놓아준다 — 한 계정이
      // 여러 사업자번호를 잡고 있으면 실제로 쓰지 않는 번호까지 계속 잠가
      // 두게 되고, "누가 무엇을 쓰는지"도 흐려진다.
      //
      // 지우지 않고 released로 남기는 이유는 identityLinks와 같다 — 누가
      // 잡고 있었는지가 감사에 필요하다. 그리고 **남의 점유는 절대 건드리지
      // 않는다**(holderUid가 나일 때만).
      if (
        prevOwnerRef && prevOwnerSnap && prevOwnerSnap.exists
        && prevOwnerSnap.data().holderUid === uid
      ) {
        tx.set(prevOwnerRef, {
          status: OWNERSHIP_STATUS.released,
          releasedAt: now,
          releasedFromUid: uid,
          updatedAt: now,
        }, { merge: true });
      }
    }

    return {
      mode: resolved.mode,
      numberChanged: resolved.numberChanged,
      decision,
    };
  });
}

// ── 다른 모듈이 쓰는 공유 헬퍼 ─────────────────────────────────────────
//
// "이 계정이 사업자 권한을 가졌는가" — 예약/오픈 권한의 유일한 근거다.
//
// **status만으로는 부족하다.** status는 "사업자 정보가 진짜인가"일 뿐이고,
// 남의 사업자등록증으로도 거기까지는 통과한다. 이 계정이 그 사업자를 쓸 수
// 있는지는 authorization이 답한다(파일 상단 "두 축" 절).
//
// settlementInfo.hostType(사용자 자가선택)은 여기서 쳐다보지 않는다.
async function isBusinessVerified(db, uid) {
  if (!uid) return false;
  const snap = await db.collection('users').doc(uid).get();
  if (!snap.exists) return false;
  return isBusinessAuthorized(snap.data().businessVerification);
}

// ── 콜러블 ─────────────────────────────────────────────────────────────
exports.verifyBusinessRegistration = onCall(
  { secrets: [ntsServiceKey], region: 'asia-northeast3', timeoutSeconds: 60 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    }
    const uid = request.auth.uid;
    const db = admin.firestore();

    const input = request.data || {};
    const bNo = normalizeBusinessNumber(input.businessNumber);
    const startDt = normalizeOpeningDate(input.openingDate);
    const pNm = String(input.representativeName || '').trim();
    // 참고 항목 — 저장은 하되 통과 조건이 아니다.
    const bNm = String(input.businessName || '').trim();
    // bAdr은 **기본주소 + 상세주소를 합친 전체 주소 한 줄**이다(앱이 합쳐서
    // 보낸다). 옛 문서의 businessAddress와 같은 형태라 저장 자리는 예전
    // 그대로지만, 국세청에는 보내지 않는다(헤더의 실측표 참고).
    const bAdr = String(input.businessAddress || '').trim();
    // 같은 주소를 나눠서도 남긴다 — 정본은 어디까지나 bAdr이고, 이 둘은
    // 화면이 되살릴 때 쓰는 보조 값이다. 구버전 앱은 보내지 않으므로 빈
    // 문자열이 되고, 그때도 bAdr만으로 예전과 똑같이 동작한다.
    const bBaseAdr = String(input.businessBaseAddress || '').trim();
    const bDetailAdr = String(input.businessDetailAddress || '').trim();

    if (!bNo) {
      throw new HttpsError('invalid-argument', '사업자등록번호 10자리를 정확히 입력해주세요.');
    }
    if (!pNm) {
      throw new HttpsError('invalid-argument', '대표자명을 입력해주세요.');
    }
    if (!startDt) {
      throw new HttpsError('invalid-argument', '개업일자를 YYYYMMDD 형식으로 입력해주세요.');
    }

    const userRef = db.collection('users').doc(uid);

    // ── 게이트: 본인확인 ────────────────────────────────────────────────
    // 앱 루트 게이트는 화면만 막는다 — 구버전 앱과 SDK 직접 호출은 이 콜러블에
    // 곧장 닿는다. 그리고 여기서는 그것이 단순한 정책 위반이 아니다:
    // 자동승인의 대조 기준이 **NICE로 확인된 실명(users.name)**이므로,
    // 본인확인이 없으면 대조할 정본 자체가 없다. 미인증 계정을 통과시키면
    // 이름 대조가 빈 문자열끼리의 비교가 되어 판정이 무너진다.
    //
    // 읽은 문서는 그대로 아래에서 재사용한다 — 같은 문서를 두 번 읽지 않는다.
    //
    // 게이트와 이름 대조는 [resolveIdentityBasis] 한 곳에서 함께 정해진다
    // (그 함수 주석에 왜 나눌 수 없는지가 있다). 본인확인을 마치지 않은
    // 계정은 **국세청을 부르기도 전에** 여기서 끝난다.
    const before = (await userRef.get()).data() || {};
    const basis = resolveIdentityBasis(before, pNm);
    const prev = before.businessVerification || {};

    // 하루 시도 제한 — 이미 권한이 있어도 재검증은 굳이 막지 않지만(휴폐업
    // 재확인 용도), 횟수는 동일하게 센다.
    const todayKey = new Date().toISOString().slice(0, 10);
    const attemptsToday = prev.attemptDate === todayKey ? (prev.attemptCount || 0) : 0;
    if (attemptsToday >= MAX_ATTEMPTS_PER_DAY) {
      throw new HttpsError(
        'resource-exhausted',
        `하루 인증 시도 횟수(${MAX_ATTEMPTS_PER_DAY}회)를 초과했습니다. 내일 다시 시도해주세요.`,
      );
    }

    const serviceKey = resolveServiceKey();
    const masked = maskBusinessNumber(bNo);

    let outcome;
    if (!serviceKey) {
      // 키 미등록 구간 — 절대 통과시키지 않는다. 사용자에게는 "심사 필요"로
      // 보이고, 키를 등록한 뒤 다시 시도하면 그대로 실검증 경로를 탄다.
      console.warn(
        `[bizVerify] NTS_SERVICE_KEY 미설정 — 실검증을 건너뛰고 pending으로 남깁니다. `
        + `uid=${uid} bNo=${masked}`,
      );
      outcome = {
        status: 'pending',
        failReason: 'apiKeyMissing',
        ntsStatusCode: '',
        ntsStatusLabel: '',
        taxType: '',
        nameMatched: null,
        addressMatched: null,
      };
    } else {
      let statusData = null;
      let validateData = null;
      try {
        const statusRes = await postNtsWithRetry(
          'status API',
          NTS_STATUS_PATH,
          serviceKey,
          { b_no: [bNo] },
          { uid, masked },
        );
        if (statusRes.statusCode === 200 && statusRes.body && Array.isArray(statusRes.body.data)) {
          statusData = statusRes.body.data[0] || null;
          console.log(
            `[bizVerify] status 응답. uid=${uid} bNo=${masked} http=200 `
            + `ntsCode=${statusRes.body.status_code} sttCd=${(statusData && statusData.b_stt_cd) || '-'} `
            + `elapsedMs=${statusRes.elapsedMs}`,
          );
        } else {
          // 재시도까지 모두 실패 — 시도별 로그는 위에서 이미 남겼다.
          logNtsFailure('status API 최종', {
            uid,
            masked,
            res: statusRes,
            includeRaw: true,
          });
        }

        // 계속사업자일 때만 진위확인을 부른다 — 폐업자에게 굳이 2번째 호출을
        // 쓰지 않는다(일 호출량 절약).
        if (statusData && String(statusData.b_stt_cd || '').trim() === '01') {
          const validateRes = await postNtsWithRetry(
            'validate API',
            NTS_VALIDATE_PATH,
            serviceKey,
            { businesses: [buildValidatePayload(bNo, startDt, pNm)] },
            { uid, masked },
          );
          if (validateRes.statusCode === 200 && validateRes.body && Array.isArray(validateRes.body.data)) {
            validateData = validateRes.body.data[0] || null;
            // valid/valid_msg는 "무엇이 불일치인지"만 담고 입력값은 담지 않는다.
            console.log(
              `[bizVerify] validate 응답. uid=${uid} bNo=${masked} http=200 `
              + `ntsCode=${validateRes.body.status_code} valid=${(validateData && validateData.valid) || '-'} `
              + `validMsg=${(validateData && validateData.valid_msg) || '-'} elapsedMs=${validateRes.elapsedMs}`,
            );
          } else {
            // ⚠️ 원문 금지 — validate 응답은 request_param으로 입력값을 되돌려준다.
            logNtsFailure('validate API 최종', {
              uid,
              masked,
              res: validateRes,
              includeRaw: false,
            });
          }
        }
      } catch (err) {
        // err.message에는 우리가 만든 문자열만 들어간다(요청 본문은 포함하지
        // 않는다) — 개인정보가 로그에 새지 않도록 메시지만 남긴다.
        console.error(
          `[bizVerify] NTS 호출 오류. uid=${uid} bNo=${masked} `
          + `errName=${err && err.name} errCode=${(err && err.code) || '-'} msg=${err && err.message}`,
        );
      }

      outcome = evaluateNtsResult(statusData, validateData);
    }

    // 국세청 판정을 users 문서와 사업자번호 점유에 **한 트랜잭션으로** 반영한다.
    const { mode, numberChanged, decision } = await applyVerificationOutcome(db, {
      uid,
      outcome,
      input: {
        businessNumber: bNo,
        representativeName: pNm,
        openingDate: startDt,
        businessName: bNm,
        businessAddress: bAdr,
        businessBaseAddress: bBaseAdr,
        businessDetailAddress: bDetailAdr,
      },
      nameMatchesIdentity: basis.nameMatchesIdentity,
      ownerCiHash: basis.ownerCiHash,
      masked,
      todayKey,
    });

    // 로그에 이름은 남기지 않는다 — 권한 판정 결과(코드)만 남긴다.
    console.log(
      `[bizVerify] 결과 저장. uid=${uid} bNo=${masked} status=${outcome.status} `
      + `auth=${decision.authorization} authReason=${decision.authorizationReason || '-'} `
      + `reason=${outcome.failReason || '-'} sttCd=${outcome.ntsStatusCode || '-'} `
      + `mode=${mode} numberChanged=${numberChanged}`,
    );

    return {
      // ⚠️ status·authorization 모두 **이번 시도**의 판정이다. 계정의 실제
      //    상태와 다를 수 있다(keptExistingVerification이 true인 경우) —
      //    앱은 문서를 다시 읽어 확정한다.
      status: outcome.status,
      failReason: outcome.failReason,
      ntsStatusLabel: outcome.ntsStatusLabel,
      taxType: outcome.taxType,
      authorization: decision.authorization,
      authorizationReason: decision.authorizationReason,
      // 화면이 "기존 인증은 그대로 유지됐다"를 말할 수 있도록 알려준다.
      keptExistingVerification: mode === 'keptVerified',
      numberChanged,
    };
  },
);

module.exports.isBusinessVerified = isBusinessVerified;
module.exports.isBusinessAuthorized = isBusinessAuthorized;
module.exports.resolveIdentityBasis = resolveIdentityBasis;
module.exports.applyVerificationOutcome = applyVerificationOutcome;
module.exports.decideAuthorization = decideAuthorization;
module.exports.ownershipHolderOf = ownershipHolderOf;
module.exports.representativeCiHashOf = representativeCiHashOf;
module.exports.representativeLevelOf = representativeLevelOf;
module.exports.canSupersedePin = canSupersedePin;
module.exports.REP_VERIFICATION_LEVEL = REP_VERIFICATION_LEVEL;
module.exports.businessNumberHash = businessNumberHash;
module.exports.AUTHORIZATION = AUTHORIZATION;
module.exports.AUTHORIZED_VALUES = AUTHORIZED_VALUES;
module.exports.AUTH_REASON = AUTH_REASON;
module.exports.BUSINESS_OWNERSHIP = BUSINESS_OWNERSHIP;
module.exports.OWNERSHIP_STATUS = OWNERSHIP_STATUS;
module.exports.evaluateNtsResult = evaluateNtsResult;
module.exports.resolveVerificationWrite = resolveVerificationWrite;
module.exports.coreFieldsChanged = coreFieldsChanged;
module.exports.buildVerificationRecord = buildVerificationRecord;
module.exports.CORE_FIELDS = CORE_FIELDS;
module.exports.BUSINESS_HISTORY_LIMIT = BUSINESS_HISTORY_LIMIT;
module.exports.buildValidatePayload = buildValidatePayload;
module.exports.normalizeBusinessNumber = normalizeBusinessNumber;
module.exports.normalizeOpeningDate = normalizeOpeningDate;
module.exports.maskBusinessNumber = maskBusinessNumber;

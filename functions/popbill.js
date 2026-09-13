// ══════════════════════════════════════════════════════════════════════════
// 팝빌(링크허브) **예금주조회** 어댑터 — 외부 계좌 검증이 닿는 유일한 자리.
//
// 호스트 수취계좌 인증([payoutAccounts.js])이 "이 계좌의 예금주가 누구인가"를
// 물을 때만 쓴다. 호출은 **서버에서만** 한다 — 링크아이디·비밀키가 앱에 실리면
// 누구나 남의 계좌 예금주를 조회할 수 있다.
//
// ── 왜 파일 하나로 격리했나 ───────────────────────────────────────────────
// 외부 규격(엔드포인트·응답 필드명·기관코드)이 닿는 곳을 이 파일 하나로 가둬,
// 규격이 바뀌어도 나머지(상태 머신·저장·규칙·화면·결제 게이팅)는 손대지 않게
// 했다. 호출부가 기대하는 계약은 단 하나다 — **예금주 성명 문자열을 돌려주거나
// [PopbillError]를 던진다.**
//
// ── 연결 전 동작: 반드시 '실패' ───────────────────────────────────────────
// 키가 없으면 [NOT_CONFIGURED]로 **실패**한다. 절대 통과시키지 않는다.
// portOne.js에는 "시크릿 미설정이면 검증 없이 통과"하는 테스트 모드가 있지만,
// 그건 PG 계약 전 결제 흐름을 열어 두기 위한 것이고 여기서는 정반대다 —
// 검증되지 않은 계좌를 '인증 완료'로 만들면 참가자 돈이 그 계좌로 나간다.
//
// ── 상품 선택: 성명조회(CheckAccountInfo) ─────────────────────────────────
// 팝빌은 성명조회(기관코드+계좌번호 → 예금주 성명)와 실명조회(+실명번호,
// checkDepositorInfo)를 제공한다. 우리에게 필요한 것은 "입력한 예금주명이
// 맞는가"이고 그 대조는 서버가 직접 한다([payoutAccounts.holderMatches]).
// 실명조회는 생년월일·사업자번호를 더 받아 보관해야 해서 수집 범위만 넓어진다 —
// 쓰지 않는다.
//
// ── 인증 서명을 직접 만들지 않는다 ────────────────────────────────────────
// 링크허브 토큰 발급(HMAC-SHA256 서명)은 공식 SDK(`popbill` npm)가 한다.
// 서명 문자열 구성은 규격이 바뀌면 조용히 깨지는 종류의 코드라, 손으로 쓰지
// 않고 공급자가 관리하는 구현을 쓴다.
//
// ⚠️ 시크릿 값(LinkID·SecretKey·CorpNum)은 **어떤 경로로도 밖에 나가지 않는다.**
//    로그·에러 메시지·반환값 어디에도 담지 않는다. 계좌번호도 마찬가지다 —
//    이 파일은 계좌번호를 로그에 남기지 않고, 호출부가 마스킹해서 남긴다.
// ══════════════════════════════════════════════════════════════════════════

const popbillSdk = require('popbill');

const LOG = 'PopbillAccountCheck';

// ── 어느 팝빌 서버에 물을 것인가 ──────────────────────────────────────────
//
// 팝빌은 테스트/운영이 **같은 LinkID·SecretKey**를 쓰고 이 값 하나로 갈린다
// (test → popbill-test.linkhub.co.kr, production → popbill.linkhub.co.kr).
//
// 예전에는 `const IS_TEST = true` 한 줄이었다. 그 구조의 문제는 값이 아니라
// **틀리는 방향**이었다 — 운영에 그대로 올라가도 아무 신호가 없고 조회는
// 테스트 서버로 조용히 나간다. 인증에 "성공"해도 운영 계좌 기준으로는 아무것도
// 보증하지 못한 채 무통장입금이 열린다.
//
// 그래서 환경을 **명시적으로 정하게** 하고, 정해지지 않았으면 조회를 하지 않는다.

const POPBILL_ENV = {
  production: 'production',
  test: 'test',
};

/**
 * 이 저장소에서 **운영으로 취급하는 GCP 프로젝트 id**.
 *
 * 배포 대상이 곧 답이 되도록 소스에 적어 둔다 — `.env`류는 gitignore라
 * 새로 클론한 곳에서 조용히 비어 버릴 수 있고, 그 빈 값이 테스트 서버로
 * 이어지면 위에서 말한 사고가 그대로 재현된다.
 */
const PRODUCTION_PROJECT_IDS = new Set(['partychu-30c24']);

/**
 * 쓸 팝빌 환경을 정한다. 정할 수 없으면 **null**(= 조회 금지).
 *
 * 순서가 규칙이다.
 *   ① `POPBILL_ENV`가 있으면 그대로 따른다 — 에뮬레이터·self-check가 테스트
 *      환경을 **명시적으로 주입**하는 통로다. 오타는 받아 주지 않는다.
 *   ② 없으면 배포된 GCP 프로젝트로 정한다. 운영 프로젝트면 production이다.
 *   ③ 둘 다 아니면 null — 여기서 절대 test로 떨어지지 않는다.
 *
 * ⚠️ null을 "기본값 test"로 바꾸지 말 것. 그 한 줄이 이 함수를 만든 이유를
 *    통째로 없앤다(운영에서 설정이 빠지면 조용히 테스트 서버로 나간다).
 *    null은 [checkAccountName]에서 NOT_CONFIGURED가 되어 **인증이 실패한다** —
 *    시끄럽게 막히는 쪽이 조용히 통과하는 쪽보다 안전하다.
 */
function resolvePopbillEnv(env = process.env) {
  const raw = String((env && env.POPBILL_ENV) || '').trim().toLowerCase();
  if (raw === POPBILL_ENV.production) return POPBILL_ENV.production;
  if (raw === POPBILL_ENV.test) return POPBILL_ENV.test;
  if (raw) return null; // 오타는 추측하지 않는다.

  const projectId = String(
    (env && (env.GCLOUD_PROJECT || env.GOOGLE_CLOUD_PROJECT)) || '',
  ).trim();
  if (projectId && PRODUCTION_PROJECT_IDS.has(projectId)) {
    return POPBILL_ENV.production;
  }
  return null;
}

/** SDK에 넘길 `IsTest` — 운영이면 false다. */
function isTestEnv(envName) {
  return envName === POPBILL_ENV.test;
}

/** 키가 없어 조회 자체를 못 한 경우. 인증은 실패로 남는다. */
const NOT_CONFIGURED = 'popbill/not-configured';

/** 조회 서비스가 응답하지 않거나 오류를 준 경우. */
const UNAVAILABLE = 'popbill/unavailable';

/** 조회는 됐지만 계좌가 없거나 조회 불가한 경우. */
const ACCOUNT_NOT_FOUND = 'popbill/account-not-found';

class PopbillError extends Error {
  constructor(code, message) {
    super(message || code);
    this.code = code;
  }
}

/**
 * Secret Manager 파라미터에서 값을 꺼낸다. 미설정이면 빈 문자열.
 *
 * 배포 환경에 시크릿이 없으면 `.value()`가 던지므로 감싼다(portOne.js와 같은
 * 처리) — 시크릿 하나 때문에 함수 전체가 죽으면 안 된다.
 */
function secretValue(param) {
  try {
    return (param && param.value ? param.value() : String(param || '')).trim();
  } catch (_) {
    return '';
  }
}

/** 아직 실제 키가 들어오지 않은 상태를 나타내는 자리표시자들. */
const PLACEHOLDERS = new Set([
  '',
  'TEST_MODE',
  'REPLACE_WITH_POPBILL_LINK_ID',
  'REPLACE_WITH_POPBILL_SECRET_KEY',
  'REPLACE_WITH_POPBILL_CORP_NUM',
]);

/** 팝빌 연동에 필요한 값이 모두 들어와 있는가. */
function isConfigured({ linkId, secretKey, corpNum }) {
  return [linkId, secretKey, corpNum]
    .map(secretValue)
    .every((v) => !PLACEHOLDERS.has(v));
}

// ── 기관코드 ──────────────────────────────────────────────────────────────
//
// 우리가 저장하는 은행 코드는 금융결제원 표준 **3자리**다
// (payoutAccounts.BANK_NAMES / lib/models/bank_codes.dart). 팝빌 예금주조회는
// **4자리**를 요구하고, SDK가 길이 4가 아니면 호출 전에 거절한다.
//
// 대부분은 앞에 0을 채우면 그대로 맞지만, 팝빌 기관코드 표가 표준과 다른
// 기관이 있으면 아래 표에 한 줄씩 넣어 바로잡는다 — 변환 규칙을 고치지 말고
// 예외만 적는다(어느 은행이 예외인지가 그대로 드러난다).
const BANK_CODE_OVERRIDES = {
  // '045': '0045',  ← 예: 새마을금고가 다른 코드를 쓰면 이런 식으로 적는다
};

/** 저장된 3자리 코드를 팝빌 4자리 기관코드로. 변환할 수 없으면 빈 문자열. */
function toPopbillBankCode(bankCode) {
  const digits = String(bankCode == null ? '' : bankCode).replace(/[^0-9]/g, '');
  if (!digits) return '';
  const override = BANK_CODE_OVERRIDES[digits];
  if (override) return override;
  if (digits.length > 4) return '';
  return digits.padStart(4, '0');
}

// ── 응답 읽기 ─────────────────────────────────────────────────────────────
//
// **조회 실패는 예외로 오지 않는다.** 2026-08-24 테스트 환경에서 실제로 확인한
// 응답 구조는 이렇다(없는 계좌를 조회했을 때):
//
//   { bankCode, accountNumber, accountName, checkDate,
//     result, resultCode, resultMessage, checkDT }
//
// 즉 팝빌은 **200을 주면서** 성명 자리를 비우고 결과 코드로 사유를 말한다.
// 그래서 "예외 = 실패, 200 = 성공"으로 갈라서는 안 된다 — 200을 받고도 성명이
// 없으면 그건 **그 계좌의 예금주를 확인하지 못했다는 뜻**이다.
//
// 성명이 담기는 필드는 `accountName`이고, 나머지는 표기가 다를 경우를 대비한
// 후보다.
const NAME_FIELDS = ['accountName', 'AccountName', 'depositorName', 'holderName'];

/** 응답에 실린 결과 코드 계열 필드가 하나라도 있는가(= 팝빌이 준 정상 응답). */
const RESULT_FIELDS = ['resultCode', 'result', 'resultMessage'];

function holderNameOf(response) {
  if (!response || typeof response !== 'object') return '';
  for (const key of NAME_FIELDS) {
    const v = response[key];
    if (typeof v === 'string' && v.trim()) return v.trim();
  }
  return '';
}

/** 결과 코드를 로그용 문자열로. 계좌번호는 절대 담지 않는다. */
function resultSummaryOf(response) {
  if (!response || typeof response !== 'object') return '';
  return RESULT_FIELDS.filter((k) => response[k] !== undefined)
    .map((k) => `${k}=${response[k]}`)
    .join(' ');
}

/** 팝빌이 형식을 갖춰 답했는가 — 결과 코드 계열 필드로 판단한다. */
function looksLikePopbillResult(response) {
  if (!response || typeof response !== 'object') return false;
  return RESULT_FIELDS.some((k) => response[k] !== undefined);
}

/**
 * 성명 없는 정상 응답을 '계좌 문제'와 '서비스 문제'로 가른다.
 *
 * `result`는 HTTP 상태를 닮은 숫자다. 2026-08-24 테스트 환경에서 없는 계좌를
 * 조회했을 때 실제로 받은 값은 이랬다:
 *
 *   result=400  resultCode=S054  resultMessage=금융기관으로부터 거래가 제한된 계좌번호
 *
 * 그래서 4xx는 **그 계좌를 확인할 수 없다**(사용자가 계좌를 고쳐야 함), 5xx는
 * 서비스·기관 쪽 사정으로 본다(사용자는 나중에 다시 시도하면 됨). 둘 다 인증은
 * 되지 않고, 갈리는 것은 화면 문구뿐이다.
 *
 * 숫자를 못 읽으면 '확인하지 못했다'로 둔다 — 성명이 비어 있다는 사실 자체가
 * 이미 확인 실패이고, 그걸 일시 장애라고 말하면 사용자가 같은 계좌로 계속
 * 재시도하게 된다.
 */
function resultKindOf(response) {
  const raw = response && response.result;
  const n = typeof raw === 'number' ? raw : parseInt(String(raw || ''), 10);
  if (Number.isFinite(n) && n >= 500) return UNAVAILABLE;
  return ACCOUNT_NOT_FOUND;
}

// ── 오류 분류 ─────────────────────────────────────────────────────────────
//
// SDK는 실패를 `{ code: <number>, message: <string> }`로 넘긴다.
//
// 여기로 오는 것은 **호출 자체가 깨진 경우**다. "그런 계좌 없음"은 여기로 오지
// 않는다 — 그건 200 응답으로 오고 [resultKindOf]가 가른다(2026-08-24 실측).
//
//  · -99999999 — **SDK 자체 입력 검증** 실패(기관코드 길이·계좌번호 누락 등).
//    우리가 보낸 값이 조회할 수 없는 값이라는 뜻이므로 '조회 불가한 계좌'다.
//  · 그 밖의 전부 — 링크허브 인증 실패·잔액 부족·기관 점검·네트워크 등
//    **서비스 쪽 사정**이므로 일시 장애로 본다.
//
// 어느 쪽이든 인증은 되지 않는다(fail-closed). 아래 표는 나중에 "계좌 문제로
// 안내해야 할" 팝빌 오류 코드가 실제로 관찰되면 그때 한 줄씩 넣는 자리다 —
// 추측한 코드를 미리 적어 두지 않는다.
const SDK_VALIDATION_CODE = -99999999;
const ACCOUNT_ERROR_CODES = new Set([]);

// ── 링크허브 인증·연동 오류(-990100xx)는 '일시 장애'가 아니다 ─────────────
//
// 2026-08-30 운영에서 실제로 받은 값: `-99010016`.
// 그때 상황은 이랬다 — 시크릿에 들어 있는 링크아이디는 팝빌 **테스트베드**
// 계정인데, POPBILL_ENV가 비어 있어 조회가 **운영 서버**로 나갔다. 링크허브는
// 그 요청을 인증 단계에서 거절한다.
//
// 이 계열을 UNAVAILABLE로 두면 앱이 "잠시 후 다시 시도해주세요"를 띄운다.
// 그런데 이건 **재시도로 절대 풀리지 않는 설정 문제**라, 사용자는 멀쩡한 자기
// 계좌를 몇 번이고 다시 치게 되고 진짜 원인은 아무 데도 드러나지 않는다.
// (앱이 `not-found`를 계좌 오류처럼 보여주던 것과 정확히 같은 실수다.)
//
// 그래서 NOT_CONFIGURED로 가른다 — 사용자에게는 "계좌 문제가 아니다"라고
// 말하고, 운영에는 코드를 로그로 남긴다. 인증되지 않는다는 결과 자체는
// 어느 쪽이든 같다(fail-closed).
const LINKHUB_AUTH_CODE_MIN = -99010999;
const LINKHUB_AUTH_CODE_MAX = -99010000;

function isLinkhubAuthCode(code) {
  return (
    code !== null &&
    code >= LINKHUB_AUTH_CODE_MIN &&
    code <= LINKHUB_AUTH_CODE_MAX
  );
}

function classify(error) {
  const code = error && typeof error.code === 'number' ? error.code : null;
  if (code === SDK_VALIDATION_CODE) return ACCOUNT_NOT_FOUND;
  if (code !== null && ACCOUNT_ERROR_CODES.has(code)) return ACCOUNT_NOT_FOUND;
  if (isLinkhubAuthCode(code)) return NOT_CONFIGURED;
  return UNAVAILABLE;
}

// ── SDK 초기화 ────────────────────────────────────────────────────────────
//
// `popbill.config()`는 모듈 전역 설정이고 `AccountCheckService()`는 첫 호출에서
// 만든 인스턴스를 캐시한다 — **설정이 먼저, 서비스 생성이 나중**이어야 한다.
// 함수 인스턴스 안에서 시크릿은 바뀌지 않으므로 한 번만 만들고 재사용한다.
let cachedService = null;

/**
 * @param {string} envName [resolvePopbillEnv] 결과 — 호출부가 이미 null을
 *   걸러 낸 뒤에만 들어온다(여기서 기본값을 만들지 않는다).
 */
function serviceOf(linkId, secretKey, envName) {
  if (cachedService) return cachedService;
  popbillSdk.config({
    LinkID: linkId,
    SecretKey: secretKey,
    IsTest: isTestEnv(envName),
    // IP 제한은 팝빌 콘솔에서 관리한다(SDK 기본값을 그대로 명시).
    IPRestrictOnOff: true,
    UseStaticIP: false,
    UseLocalTimeYN: true,
  });
  cachedService = popbillSdk.AccountCheckService();
  console.log(`[${LOG}] 초기화. env=${envName}`);
  return cachedService;
}

/** 콜백 API를 프라미스로. 응답이 없으면 함수 타임아웃(30초) 전에 스스로 끊는다. */
const CALL_TIMEOUT_MS = 15000;

function callCheckAccountInfo(service, corpNum, bankCode, accountNumber) {
  return new Promise((resolve, reject) => {
    let settled = false;
    const finish = (fn) => (arg) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      fn(arg);
    };
    const timer = setTimeout(
      () =>
        finish(reject)(
          new PopbillError(UNAVAILABLE, '예금주조회 응답이 없습니다(시간 초과).'),
        ),
      CALL_TIMEOUT_MS,
    );
    try {
      service.checkAccountInfo(
        corpNum,
        bankCode,
        accountNumber,
        finish(resolve),
        finish(reject),
      );
    } catch (e) {
      // SDK가 콜백 대신 던지는 경우까지 같은 자리로 모은다.
      finish(reject)(e);
    }
  });
}

/**
 * 계좌의 예금주 성명을 조회한다.
 *
 * @returns {Promise<string>} 예금주 성명.
 * @throws {PopbillError} 조회하지 못했을 때(코드는 위 상수들).
 */
async function checkAccountName({
  bankCode,
  accountNumber,
  linkId,
  secretKey,
  corpNum,
}) {
  if (!isConfigured({ linkId, secretKey, corpNum })) {
    throw new PopbillError(
      NOT_CONFIGURED,
      '예금주조회 서비스가 아직 연결되지 않았습니다(팝빌 API Key 미발급).',
    );
  }

  // 어느 서버에 물을지 정해지지 않았으면 **묻지 않는다.**
  //
  // 여기서 test로 기본값을 주면, 운영에 설정이 빠진 채로 올라갔을 때 조회가
  // 테스트 서버로 조용히 나가고 그 결과가 '인증 완료'가 된다. 그 계좌로
  // 참가자 돈이 들어가므로, 막히는 쪽을 택한다(fail-closed).
  const envName = resolvePopbillEnv();
  if (!envName) {
    console.error(
      `[${LOG}] 팝빌 환경이 정해지지 않았습니다. POPBILL_ENV를 'production' 또는 `
        + `'test'로 설정하거나 운영 프로젝트에서 실행하세요.`,
    );
    throw new PopbillError(
      NOT_CONFIGURED,
      '예금주조회 서비스 설정이 올바르지 않습니다.',
    );
  }

  const popbillBankCode = toPopbillBankCode(bankCode);
  if (!popbillBankCode) {
    // 팝빌에 물어볼 수도 없는 값이다 — 왕복 없이 '조회 불가'로 끝낸다.
    console.warn(`[${LOG}] 기관코드 변환 실패. bank=${bankCode}`);
    throw new PopbillError(ACCOUNT_NOT_FOUND, '지원하지 않는 은행입니다.');
  }

  const digits = String(accountNumber == null ? '' : accountNumber).replace(
    /[^0-9]/g,
    '',
  );
  if (!digits) {
    throw new PopbillError(ACCOUNT_NOT_FOUND, '계좌번호가 올바르지 않습니다.');
  }

  const service = serviceOf(
    secretValue(linkId),
    secretValue(secretKey),
    envName,
  );

  let response;
  try {
    response = await callCheckAccountInfo(
      service,
      secretValue(corpNum),
      popbillBankCode,
      digits,
    );
  } catch (e) {
    if (e instanceof PopbillError) throw e;
    const kind = classify(e);
    // 팝빌이 준 message는 남기지 않는다 — 조회 대상(계좌번호)이 섞여 들어올 수
    // 있다. 코드만으로 충분히 추적된다.
    console.warn(
      `[${LOG}] 조회 실패. env=${envName} `
        + `bank=${popbillBankCode} popbillCode=${e && e.code} kind=${kind}`,
    );
    throw new PopbillError(kind, '예금주조회에 실패했습니다.');
  }

  const holderName = holderNameOf(response);
  if (holderName) return holderName;

  // 성명이 없다 — 두 경우를 갈라야 한다.
  //
  //  · 결과 코드가 실려 있다 → 팝빌이 형식을 갖춰 "확인해 주지 못했다"고 답한
  //    것이다. 없는 계좌·조회 불가 계좌가 여기로 온다(테스트 환경에서 실제로
  //    확인). 사용자에게는 "계좌를 확인할 수 없다"고 말해야 맞다.
  //  · 결과 코드조차 없다 → 응답 형식이 달라졌다는 신호다. '계좌 없음'으로
  //    조용히 넘기면 원인이 묻히므로 일시 장애로 올린다.
  //
  // 어느 쪽이든 인증은 되지 않는다(fail-closed). 갈리는 것은 화면 문구뿐이다.
  const summary = resultSummaryOf(response);
  if (looksLikePopbillResult(response)) {
    const kind = resultKindOf(response);
    console.warn(
      `[${LOG}] 예금주를 확인하지 못했습니다. bank=${popbillBankCode} `
        + `${summary} kind=${kind}`,
    );
    throw new PopbillError(kind, '예금주를 확인하지 못했습니다.');
  }

  console.warn(
    `[${LOG}] 응답 형식을 알 수 없습니다. bank=${popbillBankCode} `
      + `keys=${Object.keys(response || {}).join(',')}`,
  );
  throw new PopbillError(UNAVAILABLE, '예금주 성명을 읽지 못했습니다.');
}

/**
 * 조회 실패를 수취계좌 인증의 실패 사유로 옮긴다.
 *
 * 사유 코드는 [payoutAccounts.FAIL_REASON]이 정본이라 그 표를 받아서 쓴다 —
 * 여기에 같은 문자열을 또 적어 두면 한쪽만 바뀐다.
 */
function failReasonOf(error, FAIL_REASON) {
  switch (error && error.code) {
    case NOT_CONFIGURED:
      return FAIL_REASON.notConfigured;
    case ACCOUNT_NOT_FOUND:
      return FAIL_REASON.accountNotFound;
    default:
      return FAIL_REASON.apiUnavailable;
  }
}

module.exports = {
  NOT_CONFIGURED,
  UNAVAILABLE,
  ACCOUNT_NOT_FOUND,
  // `IS_TEST` 상수는 없앴다 — 환경은 [resolvePopbillEnv]가 정하고, 정해지지
  // 않으면 조회 자체를 하지 않는다. 테스트는 env를 **명시적으로 주입**한다.
  POPBILL_ENV,
  PRODUCTION_PROJECT_IDS,
  resolvePopbillEnv,
  isTestEnv,
  PopbillError,
  isConfigured,
  checkAccountName,
  failReasonOf,
  // 아래 셋은 self-check 전용 — 호출부는 checkAccountName만 쓴다.
  toPopbillBankCode,
  holderNameOf,
  looksLikePopbillResult,
  resultKindOf,
  classify,
};

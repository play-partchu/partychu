// ══════════════════════════════════════════════════════════════════════════
// NICE 통합인증(INTC) 공통 클라이언트 — **암호·통신 정본**
//
// niceAuth.js 안에만 있던 것을 그대로 꺼낸 모듈이다. 규칙·상수·바이트 처리를
// 하나도 바꾸지 않았다(추출 자체가 동작을 바꾸면 안 되는 리팩터링이었다).
//
// ── 왜 꺼냈나 ────────────────────────────────────────────────────────────
// NICE 본인확인을 쓰는 곳이 둘이 되었다.
//   ① 회원 본인확인      niceAuth.js          — 계정에 identity를 연결한다
//   ② 대표자 승인        businessDelegation.js — 권한만 확인한다(연결 없음)
// 두 흐름은 **목적도 저장처도 완전히 다르지만**, NICE와 말하는 방식은 같다.
// 이 파일을 복사했다면 PBKDF2 반복수·base64url 알파벳·GCM 태그 길이가 두 벌이
// 되고, 한쪽만 고쳐지는 순간 조용히 복호화가 깨진다.
//
// ⚠️ **이 모듈은 Firestore의 identity 관련 문서를 일절 건드리지 않는다.**
//    users·identityLinks·niceAuthSessions에 쓰는 것은 호출부의 책임이다.
//    유일한 예외가 아래 접근토큰 캐시인데, 그것은 이용기관 단위 값이라
//    사용자와 무관하다.
//
// ── 무엇을 공유하는가 ────────────────────────────────────────────────────
//   · 시크릿(NICE_CLIENT_ID / NICE_CLIENT_SECRET)
//   · VPC 커넥터 설정([NICE_FUNCTION_OPTIONS]) — NICE는 이용기관 Outbound IP
//     화이트리스트를 쓴다. 이 커넥터를 타지 않는 함수의 요청은 NICE가 거절한다.
//   · 접근토큰 캐시(niceAuthConfig/accessToken) — 24시간짜리 이용기관 토큰이라
//     목적이 달라도 같은 것을 쓴다. 목적마다 새로 발급받을 이유가 없다.
// ══════════════════════════════════════════════════════════════════════════

const { HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');
const https = require('https');
const crypto = require('crypto');

const NICE_HOST = 'auth.niceid.co.kr';

// NICE IP 화이트리스트 등록(이용기관 Outbound IP)을 통과하기 위한 VPC 커넥터.
// 문서 1.3: "NICE 통합 인증 서비스를 이용하기 위해서는 먼저 이용기관 서버의
// Outbound IP를 NICE 담당자에게 전달하여 권한 등록을 요청 해야 합니다."
//
// timeoutSeconds: 함수 자체 timeout을 늘려서 "오래 기다리게" 하지 않기 위해
// 명시적으로 짧게 고정한다. 아래 postNiceIntc의 개별 HTTP timeout(외부 NICE
// 요청 6~8초)이 항상 이보다 먼저 끝나도록 설계되어 있으므로, 이 값은 "정상
// 흐름에서는 절대 걸리지 않는 안전망"일 뿐이다.
const NICE_FUNCTION_OPTIONS = {
  region: 'asia-northeast3',
  vpcConnector: 'projects/partychu-30c24/locations/asia-northeast3/connectors/nice-connector',
  vpcConnectorEgressSettings: 'ALL_TRAFFIC',
  timeoutSeconds: 20,
};

// postNiceIntc에 부여할 외부 HTTP 요청 timeout(ms). NICE 서버가 응답하지
// 않거나 VPC 커넥터 구간에서 연결이 지연되는 경우, 이 시간이 지나면 즉시
// 요청을 중단하고 에러로 처리한다 — "무제한 대기"를 원천 차단.
const NICE_HTTP_TIMEOUT_MS = 7000;

const niceClientId     = defineSecret('NICE_CLIENT_ID');
const niceClientSecret = defineSecret('NICE_CLIENT_SECRET');

// ── Base64Url 인코딩 (문서 1.4: "Base64.getUrlEncoder().withoutPadding() 사용") ──
// 표준 Base64가 아니라 URL-safe 알파벳(+→-, /→_)이어야 함. 패딩(=) 제거.
function base64Url(input) {
  return Buffer.from(input, 'utf8')
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

// 요청고유번호 (20~50byte, 문서 2.1.1 request_no 스펙)
function niceRequestNo() {
  const ts = new Date().toISOString().replace(/[-T:.Z]/g, '').slice(0, 14);
  return 'REQ' + ts + crypto.randomBytes(16).toString('hex');
}

// NICE 통합인증 API POST 요청 (문서 2.1 공통 HTTP Header)
//
// timeoutMs: 소켓 유휴시간이 아니라 "요청 시작~응답 완료" 전체에 대한
// 하드 타임아웃으로 사용한다 (req.setTimeout은 유휴시간 기준이라 완전한
// 보장이 아니므로, 별도 타이머로 req.destroy()를 강제 호출한다).
// 타임아웃 시 reject되는 Error에는 isTimeout=true, elapsedMs가 채워진다.
function postNiceIntc(path, bodyObj, extraHeaders, timeoutMs = NICE_HTTP_TIMEOUT_MS) {
  const body = JSON.stringify(bodyObj);
  const startedAt = Date.now();

  return new Promise((resolve, reject) => {
    let settled = false;

    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      req.destroy();
      const err = new Error(`NICE 요청 타임아웃 (path=${path}, ${timeoutMs}ms 초과)`);
      err.isTimeout = true;
      err.elapsedMs = Date.now() - startedAt;
      reject(err);
    }, timeoutMs);

    const req = https.request(
      {
        hostname: NICE_HOST,
        path,
        method:   'POST',
        headers: {
          'Content-type':   'application/json',
          'Content-Length': Buffer.byteLength(body, 'utf8'),
          ...extraHeaders,
        },
      },
      (res) => {
        let data = '';
        res.on('data', (c) => { data += c; });
        res.on('end', () => {
          if (settled) return;
          settled = true;
          clearTimeout(timer);
          const elapsedMs = Date.now() - startedAt;
          try   { resolve({ status: res.statusCode, body: JSON.parse(data), elapsedMs }); }
          catch {
            const err = new Error(`NICE 응답 파싱 오류 (path=${path}): ${data.slice(0, 300)}`);
            err.elapsedMs = elapsedMs;
            reject(err);
          }
        });
      },
    );
    req.on('error', (err) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      err.elapsedMs = Date.now() - startedAt;
      reject(err);
    });
    req.write(body);
    req.end();
  });
}

// 저수준 네트워크 에러(postNiceIntc가 reject한 Error)를 클라이언트가 분기
// 처리할 수 있는 HttpsError로 변환한다. details.code에 담기는 값은 앱단
// 요구사항의 3가지 머신 코드(NICE_RESULT_PENDING/TIMEOUT/FAILED) 중
// TIMEOUT/FAILED를 구분한다. PENDING은 서버가 만들어내는 상태가 아니라
// "이번 시도가 예산 내에 끝나지 못함"을 클라이언트가 스스로 판단하는
// 상태이므로, 서버는 TIMEOUT/FAILED만 반환하면 된다.
function toNiceHttpsError(err) {
  if (err instanceof HttpsError) return err;
  if (err && err.isTimeout) {
    return new HttpsError(
      'deadline-exceeded',
      '인증 결과를 확인하는 중 시간이 초과되었습니다.',
      { code: 'NICE_RESULT_TIMEOUT' },
    );
  }
  return new HttpsError(
    'unavailable',
    '인증 결과 확인 중 오류가 발생했습니다.',
    { code: 'NICE_RESULT_FAILED' },
  );
}

// ── 1. 접근 토큰 발급 API (문서 2. API 명세서 §1) ─────────────────────────────
// 24시간 유효 — niceAuthConfig/accessToken에 캐시하여 재사용 (기존 niceIntcConfig와 분리)
async function getAccessToken(clientId, clientSecret) {
  const db       = admin.firestore();
  const tokenRef = db.collection('niceAuthConfig').doc('accessToken');
  const cached   = await tokenRef.get();

  if (cached.exists) {
    const d = cached.data();
    if (d.expiresAt && d.expiresAt.toDate().getTime() - Date.now() > 10 * 60 * 1000) {
      console.log(`[NiceAuth] 캐시된 접근토큰 재사용. expiresAt=${d.expiresAt.toDate().toISOString()}`);
      return { accessToken: d.accessToken, iterators: d.iterators, ticket: d.ticket };
    }
  }

  const requestNo = niceRequestNo();
  const authHeader = 'Basic ' + base64Url(`${clientId}:${clientSecret}`);

  console.log(`[NICE RESULT] token request started. requestNo=${requestNo}`);
  const tokenStartedAt = Date.now();

  let status, body;
  try {
    ({ status, body } = await postNiceIntc(
      '/ido/intc/v1.0/auth/token',
      { grant_type: 'client_credentials', request_no: requestNo },
      { Authorization: authHeader, 'X-Intc-DevLang': 'Linux/Node.js' },
    ));
  } catch (err) {
    console.error(`[NICE RESULT] timeout/error: token request failed after ${Date.now() - tokenStartedAt}ms`,
      { isTimeout: !!err.isTimeout, message: err.message });
    throw toNiceHttpsError(err);
  }

  console.log(`[NICE RESULT] token request completed: ${Date.now() - tokenStartedAt}ms`
    + ` httpStatus=${status} result_code=${body.result_code}`);

  if (status !== 200 || body.result_code !== '0000') {
    console.error('[NiceAuth] 접근토큰 발급 실패:', {
      httpStatus: status, result_code: body.result_code, result_message: body.result_message,
    });
    throw new HttpsError(
      'internal',
      `NICE 접근토큰 발급 실패 (${body.result_code || status}) ${body.result_message || ''}`.trim(),
      { code: 'NICE_RESULT_FAILED' },
    );
  }

  await tokenRef.set({
    accessToken: body.access_token,
    iterators:   body.iterators,
    ticket:      body.ticket,
    // 문서: expires_in은 "현재시간에서 24시간 이후의 epoch time base의 milliseconds" (절대시각, 초 단위 duration이 아님)
    expiresAt:   admin.firestore.Timestamp.fromMillis(body.expires_in),
    updatedAt:   admin.firestore.FieldValue.serverTimestamp(),
  });

  return { accessToken: body.access_token, iterators: body.iterators, ticket: body.ticket };
}

// ── 3.1 키 유도 함수 (문서 3.1 §[1][2]) ──────────────────────────────────────
// KDF = PBKDF2(password=ticket, salt=transaction_id, iterations=iterators, keylen=64bytes, sha256)
// → base64url 인코딩한 문자열의 앞 32byte = 대칭키, 48번째부터 32byte = 무결성 키
function deriveKeys(ticket, transactionId, iterators) {
  const raw = crypto.pbkdf2Sync(ticket, transactionId, iterators, 64, 'sha256');
  const b64 = raw.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  return { key: b64.substring(0, 32), hmacKey: b64.substring(48, 48 + 32) };
}

// ── 3.2 무결성 검증 (문서 3.2) ────────────────────────────────────────────────
// HMAC-SHA256(enc_data, hmacKey) → base64url 인코딩 결과가 integrity_value와 일치해야 함
function computeIntegrityValue(encData, hmacKey) {
  const mac = crypto.createHmac('sha256', hmacKey).update(encData).digest('base64');
  return mac.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

// ── 3.3 복호화 (문서 3.3) ──────────────────────────────────────────────────────
// enc_data(base64url) = iv(16byte) + cipherText + authTag(16byte)
// 알고리즘: AES/GCM/NoPadding, Key 256bit, Iv 16byte, 인증 태그 128bit
function decryptResult(encData, key) {
  const buf          = Buffer.from(encData.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
  const iv            = buf.subarray(0, 16);
  const cipherAndTag  = buf.subarray(16);
  const tag           = cipherAndTag.subarray(cipherAndTag.length - 16);
  const cipherText    = cipherAndTag.subarray(0, cipherAndTag.length - 16);

  const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(tag);
  const plain = Buffer.concat([decipher.update(cipherText), decipher.final()]);
  return JSON.parse(plain.toString('utf8'));
}

/**
 * NICE 인증 결과를 **검증하고 복호화한다** — 두 호출부가 똑같이 거쳐야 하는 관문.
 *
 * `auth/result` 응답(`body`)과 세션에 보관해 둔 `ticket`/`transactionId`/
 * `iterators`를 받아, 무결성 HMAC을 확인한 뒤 복호화 결과를 돌려준다.
 *
 * ⚠️ 무결성 검증을 건너뛰고 복호화만 하면 안 된다. GCM 태그가 위조를 잡아주긴
 *    하지만, NICE 문서가 요구하는 절차는 integrity_value 대조가 먼저다.
 *
 * @param {string} logTag  로그 접두사(호출부 구분용)
 * @returns 복호화된 인증 결과 객체
 *          (문서 4: name, birthdate, gender, national_info, ci, di / mobile_co, mobile_no)
 * @throws {HttpsError} 무결성 실패·복호화 실패
 */
function verifyAndDecrypt(body, { ticket, transactionId, iterators }, logTag = 'NiceIntc') {
  const { key, hmacKey } = deriveKeys(ticket, transactionId, iterators);

  const expectedIntegrity = computeIntegrityValue(body.enc_data, hmacKey);
  if (expectedIntegrity !== body.integrity_value) {
    console.error(`[${logTag}] 무결성 검증 실패:`, { transactionId });
    throw new HttpsError('invalid-argument', 'NICE 인증 결과 무결성 검증에 실패했습니다.',
      { code: 'NICE_RESULT_FAILED' });
  }

  try {
    return decryptResult(body.enc_data, key);
  } catch (e) {
    console.error(`[${logTag}] 복호화 실패:`, {
      transactionId, errorName: e.name, errorMessage: e.message,
    });
    throw new HttpsError('invalid-argument', 'NICE 인증 결과 복호화에 실패했습니다.',
      { code: 'NICE_RESULT_FAILED' });
  }
}

module.exports = {
  NICE_HOST,
  NICE_HTTP_TIMEOUT_MS,
  NICE_FUNCTION_OPTIONS,
  niceClientId,
  niceClientSecret,
  base64Url,
  niceRequestNo,
  postNiceIntc,
  toNiceHttpsError,
  getAccessToken,
  deriveKeys,
  computeIntegrityValue,
  decryptResult,
  verifyAndDecrypt,
};

// ── NICE 통합인증(INTC) — 공식 REST API 가이드 기준 재구현 ────────────────────
//
// 기존 niceIntcRequestUrl/niceIntcResult(index.js)와 완전히 분리된 별도 모듈.
// 기존 코드에 의존하지 않으며, Firestore 컬렉션/토큰 캐시도 별도로 사용한다.
// NICE 공식 문서(통합인증 API 개발 가이드 v1.0.0)의 요청/응답 스펙을 그대로 따른다.
//
// 흐름:
//   1. niceAuthRequestUrl : POST /ido/intc/v1.0/auth/token (접근토큰, 24h 캐시)
//                           → POST /ido/intc/v1.0/auth/url (인증 URL 요청)
//   2. 클라이언트 WebView   : auth_url을 GET으로 로드 → 사용자가 표준창에서 인증
//   3. niceAuthResult     : return_url로 전달된 web_transaction_id 수신
//                           → POST /ido/intc/v1.0/auth/result (인증결과 조회)
//                           → PBKDF2 키 유도 → HMAC-SHA256 무결성 검증
//                           → AES-256-GCM 복호화 → Firestore 저장
//
// 보안: client_id/client_secret은 Secret Manager에만 보관.
//       ticket/iterators는 niceAuthSessions/{uid}에만 저장 (클라이언트 읽기 차단).

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret }       = require('firebase-functions/params');
const admin  = require('firebase-admin');
const https  = require('https');
const crypto = require('crypto');

const NICE_HOST       = 'auth.niceid.co.kr';
const NICE_RETURN_URL = 'https://partychu-30c24.web.app/nice/callback';
const NICE_CLOSE_URL  = 'https://partychu-30c24.web.app/nice/callback?closed=1';

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

// ── 2. 인증 URL 요청 API (문서 2. API 명세서 §2) ──────────────────────────────
exports.niceAuthRequestUrl = onCall(
  { secrets: [niceClientId, niceClientSecret], ...NICE_FUNCTION_OPTIONS },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');

    const uid = request.auth.uid;
    const db  = admin.firestore();

    const userSnap = await db.collection('users').doc(uid).get();
    if (userSnap.exists && userSnap.data().identityVerified === true) {
      throw new HttpsError('already-exists', '이미 본인확인이 완료된 계정입니다.');
    }

    const clientId     = niceClientId.value().trim();
    const clientSecret = niceClientSecret.value().trim();

    const { accessToken, iterators, ticket } = await getAccessToken(clientId, clientSecret);

    const requestNo = niceRequestNo();
    const reqBody = {
      request_no:  requestNo,
      return_url:  NICE_RETURN_URL,
      close_url:   NICE_CLOSE_URL,
      svc_types:   ['M'],          // 계약된 인증 수단: 휴대폰 본인확인만 노출
      method_type: 'GET',
      exp_mods:    ['closeButtonOn'],
    };
    console.log(`[NiceAuth] auth/url 요청. uid=${uid} body=${JSON.stringify(reqBody)}`);

    const { status, body } = await postNiceIntc(
      '/ido/intc/v1.0/auth/url',
      reqBody,
      { Authorization: `Bearer ${accessToken}`, 'X-Intc-DevLang': 'Linux/Node.js' },
    );

    console.log(`[NiceAuth] auth/url 응답. uid=${uid} httpStatus=${status}`
      + ` result_code=${body.result_code} result_message=${body.result_message}`
      + ` request_no=${body.request_no} transaction_id=${body.transaction_id}`);

    if (status !== 200 || body.result_code !== '0000') {
      console.error('[NiceAuth] 인증URL 요청 실패:', {
        uid, httpStatus: status,
        result_code: body.result_code, result_message: body.result_message,
      });
      throw new HttpsError(
        'internal',
        `NICE 인증URL 요청 실패 (${body.result_code || status}) ${body.result_message || ''}`.trim(),
      );
    }

    // 문서 2.2: auth/url 응답의 request_no는 요청했던 값을 그대로 리턴함(에코).
    // 복호화에 필요한 ticket/iterators/transaction_id를 세션에 저장 — 클라이언트 읽기 차단.
    await db.collection('niceAuthSessions').doc(uid).set({
      requestNo:     requestNo,
      transactionId: body.transaction_id,
      ticket,
      iterators,
      used:          false,
      createdAt:     admin.firestore.FieldValue.serverTimestamp(),
      // 문서: transaction_id는 10분간 유효
      expiresAt:     admin.firestore.Timestamp.fromDate(new Date(Date.now() + 10 * 60 * 1000)),
    });

    console.log(`[NiceAuth] niceAuthRequestUrl 완료. uid=${uid} requestNo=${requestNo}`
      + ` transactionId=${body.transaction_id}`);

    return { authUrl: body.auth_url };
  },
);

// ── 3. 인증 결과 요청 API (문서 2. API 명세서 §3) ─────────────────────────────
//
// 앱에서 짧은 간격(0/1/2/3초)으로 최대 4회까지 이 함수를 재호출한다. 그래서
// 이 함수는 반드시 (a) 매 호출이 짧게(수 초 내) 끝나야 하고, (b) 첫 시도가
// 실패해도 다음 시도가 다시 시도할 수 있어야 한다. 이를 위해:
//   - niceAuthSessions.used는 "성공" 시점에만 true로 바꾼다(예전에는 호출
//     시작과 동시에 true로 바꿔서, 첫 시도가 timeout 나면 재시도가 전부
//     already-exists로 막혀버리는 버그가 있었다).
//   - 모든 외부 NICE HTTP 요청에 하드 timeout(NICE_HTTP_TIMEOUT_MS)을 걸어
//     "무한 대기"를 원천적으로 없앤다.
//   - 모든 코드 경로는 반드시 return 하거나 HttpsError를 throw한다.
exports.niceAuthResult = onCall(
  { secrets: [niceClientId, niceClientSecret], ...NICE_FUNCTION_OPTIONS },
  async (request) => {
    const fnStartedAt = Date.now();
    console.log('[NICE RESULT] function started');

    try {
      if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');

      const { webTransactionId } = request.data;
      if (!webTransactionId || typeof webTransactionId !== 'string') {
        throw new HttpsError('invalid-argument', 'webTransactionId가 필요합니다.');
      }

      const uid        = request.auth.uid;
      const db         = admin.firestore();
      const sessionRef = db.collection('niceAuthSessions').doc(uid);
      const userRef    = db.collection('users').doc(uid);

      const sessionDoc = await sessionRef.get();
      if (!sessionDoc.exists) {
        throw new HttpsError('not-found', '인증 세션이 없습니다. 처음부터 다시 시도해주세요.',
          { code: 'NICE_RESULT_FAILED' });
      }
      const session = sessionDoc.data();

      // 이미 성공 처리된 세션(정상 완료 후의 중복/지연 재시도) — 사용자
      // 입장에서는 이미 성공이므로 에러로 취급하지 않고 그대로 성공 응답.
      if (session.used) {
        console.log(`[NICE RESULT] function completed: ${Date.now() - fnStartedAt}ms (이미 완료된 세션, 성공 재응답)`);
        return { success: true };
      }
      if (session.expiresAt.toDate() < new Date()) {
        throw new HttpsError('deadline-exceeded', '인증 세션이 만료되었습니다. 처음부터 다시 시도해주세요.',
          { code: 'NICE_RESULT_FAILED' });
      }

      const clientId     = niceClientId.value().trim();
      const clientSecret = niceClientSecret.value().trim();
      // getAccessToken 내부에서 자체적으로 timeout 처리 및 로그를 남긴다
      // (보통은 24시간 캐시를 재사용하므로 이 경로에서 외부 HTTP 호출이
      // 발생하지 않는 경우가 대부분이다).
      const { accessToken } = await getAccessToken(clientId, clientSecret);

      const reqBody = {
        web_transaction_id: webTransactionId,
        transaction_id:     session.transactionId,
        request_no:         session.requestNo,
      };
      console.log(`[NICE RESULT] result API request started. uid=${uid}`);
      const resultStartedAt = Date.now();

      let status, body;
      try {
        ({ status, body } = await postNiceIntc(
          '/ido/intc/v1.0/auth/result',
          reqBody,
          { Authorization: `Bearer ${accessToken}`, 'X-Intc-DevLang': 'Linux/Node.js' },
        ));
      } catch (err) {
        console.error(`[NICE RESULT] timeout/error: result API failed after ${Date.now() - resultStartedAt}ms`,
          { uid, isTimeout: !!err.isTimeout, message: err.message });
        throw toNiceHttpsError(err);
      }

      console.log(`[NICE RESULT] result API response: ${Date.now() - resultStartedAt}ms`
        + ` uid=${uid} httpStatus=${status} result_code=${body.result_code}`);

      if (status !== 200 || body.result_code !== '0000') {
        console.error('[NiceAuth] 인증결과 요청 실패:', {
          uid, httpStatus: status,
          result_code: body.result_code, result_message: body.result_message,
        });
        throw new HttpsError(
          'cancelled',
          `NICE 인증 실패 또는 취소 (${body.result_code || status}) ${body.result_message || ''}`.trim(),
          { code: 'NICE_RESULT_FAILED' },
        );
      }

      const { key, hmacKey } = deriveKeys(session.ticket, session.transactionId, session.iterators);

      const expectedIntegrity = computeIntegrityValue(body.enc_data, hmacKey);
      if (expectedIntegrity !== body.integrity_value) {
        console.error('[NiceAuth] 무결성 검증 실패:', { uid, transactionId: session.transactionId });
        throw new HttpsError('invalid-argument', 'NICE 인증 결과 무결성 검증에 실패했습니다.',
          { code: 'NICE_RESULT_FAILED' });
      }

      let result;
      try {
        result = decryptResult(body.enc_data, key);
      } catch (e) {
        console.error('[NiceAuth] 복호화 실패:', {
          uid, transactionId: session.transactionId, errorName: e.name, errorMessage: e.message,
        });
        throw new HttpsError('invalid-argument', 'NICE 인증 결과 복호화에 실패했습니다.',
          { code: 'NICE_RESULT_FAILED' });
      }

      // 문서 4. 인증 결과 필드 (공통: name, birthdate, gender, national_info, ci, di / 휴대폰: mobile_co, mobile_no)
      const name       = (result.name || '').trim();
      const birthdate  = result.birthdate || ''; // yyyymmdd
      const birthYear  = birthdate.length >= 4 ? parseInt(birthdate.slice(0, 4), 10) : null;
      const birthMonth = birthdate.length >= 6 ? parseInt(birthdate.slice(4, 6), 10) : null;
      const birthDay   = birthdate.length >= 8 ? parseInt(birthdate.slice(6, 8), 10) : null;
      const gender     = result.gender === '1' ? 'male' : 'female'; // 문서: '1'=남자, '0'=여자
      const di         = result.di || '';
      const ci         = result.ci || '';

      await userRef.set({
        name,
        gender,
        birthYear,
        birthMonth,
        birthDay,
        di,
        ci,
        identityVerified:     true,
        identityVerifiedAt:   admin.firestore.FieldValue.serverTimestamp(),
        isVerified:           true,
        verifiedAt:           admin.firestore.FieldValue.serverTimestamp(),
        profileCompleted:     true,
        verificationProvider: 'nice_intc_v2',
      }, { merge: true });

      // 성공이 확정된 시점에만 세션을 소비 처리 — 그 이전의 어떤 실패/timeout
      // 재시도도 이 세션을 다시 사용할 수 있어야 하기 때문.
      await sessionRef.update({ used: true });

      console.log(`[NICE RESULT] function completed: ${Date.now() - fnStartedAt}ms uid=${uid}`);
      return { success: true };
    } catch (err) {
      const httpsErr = err instanceof HttpsError ? err : toNiceHttpsError(err);
      console.error(`[NICE RESULT] timeout/error: function failed after ${Date.now() - fnStartedAt}ms`
        + ` code=${httpsErr.code} message=${httpsErr.message}`);
      throw httpsErr;
    }
  },
);

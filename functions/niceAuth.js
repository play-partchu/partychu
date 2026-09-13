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
const admin  = require('firebase-admin');
// "1명의 실사용자 = 파티츄 계정 1개" 정책 — CI 중복 연결 차단 (identityLink.js)
const { linkIdentityAndSaveVerification } = require('./identityLink');
// 휴대폰번호 표기를 하나로 맞춘다. 구 경로(index.js의 niceIntcResult)도 같은
// 함수를 쓰므로 두 경로가 저장하는 모양이 갈라지지 않는다.
const { normalizeKoreanMobile } = require('./phoneNumber');
// NICE와 말하는 방식(시크릿·VPC·토큰 캐시·암호)은 전부 공용 모듈에 있다.
// ⚠️ 여기로 되가져와 복사하지 말 것 — 대표자 승인(businessDelegation.js)이
//    같은 함수를 쓰므로, 두 벌이 되는 순간 한쪽만 고쳐져 복호화가 깨진다.
const {
  NICE_FUNCTION_OPTIONS,
  niceClientId,
  niceClientSecret,
  niceRequestNo,
  postNiceIntc,
  toNiceHttpsError,
  getAccessToken,
  verifyAndDecrypt,
} = require('./niceIntcClient');

const NICE_RETURN_URL = 'https://partychu-30c24.web.app/nice/callback';
const NICE_CLOSE_URL  = 'https://partychu-30c24.web.app/nice/callback?closed=1';

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

      // 무결성 HMAC 대조 → AES-256-GCM 복호화. 두 단계 모두 공용 모듈이 하고,
      // 실패하면 여기까지 오지 않는다(HttpsError로 끝난다).
      const result = verifyAndDecrypt(body, session, 'NiceAuth');

      // 문서 4. 인증 결과 필드 (공통: name, birthdate, gender, national_info, ci, di / 휴대폰: mobile_co, mobile_no)
      const name       = (result.name || '').trim();
      const birthdate  = result.birthdate || ''; // yyyymmdd
      const birthYear  = birthdate.length >= 4 ? parseInt(birthdate.slice(0, 4), 10) : null;
      const birthMonth = birthdate.length >= 6 ? parseInt(birthdate.slice(4, 6), 10) : null;
      const birthDay   = birthdate.length >= 8 ? parseInt(birthdate.slice(6, 8), 10) : null;
      const gender     = result.gender === '1' ? 'male' : 'female'; // 문서: '1'=남자, '0'=여자
      const di         = result.di || '';
      const ci         = result.ci || '';

      // 휴대폰 본인확인(svc_types: ['M'])이라 결과에 가입자 번호가 함께 온다.
      // 알아볼 수 없는 모양이면 빈 문자열이고, 그때는 필드를 아예 쓰지 않는다
      // (phoneNumber.js 참고 — 반쯤 맞는 번호를 남기지 않는다).
      //
      // ⚠ 번호 원문은 어떤 로그에도 남기지 않는다. 아래 경고도 "값이 왔는지"와
      //   "정규화에 성공했는지"만 찍는다.
      const phoneNumber = normalizeKoreanMobile(result.mobile_no);
      if (!phoneNumber) {
        console.warn('[NiceAuth] mobile_no를 국내 휴대폰 번호로 알아보지 못해'
          + ` phoneNumber를 저장하지 않습니다. uid=${uid} present=${!!result.mobile_no}`);
      }

      // "1명의 실사용자 = 파티츄 계정 1개" — CI가 이미 다른 계정에 연결돼 있으면
      // 여기서 already-exists로 거부되고 users 문서는 전혀 갱신되지 않는다.
      // 연결 확인과 저장은 하나의 트랜잭션이라 두 기기에서 동시에 인증을
      // 마쳐도 중복 연결이 생기지 않는다(identityLink.js 참고).
      await linkIdentityAndSaveVerification(db, {
        uid,
        ci,
        provider: 'nice_intc_v2',
        userPatch: {
          name,
          gender,
          birthYear,
          birthMonth,
          birthDay,
          di,
          ci,
          // 알아보지 못한 번호는 필드 자체를 만들지 않는다 — 빈 문자열을 쓰면
          // 관리자 화면이 '-' 대신 빈 칸을 그리고, "저장은 됐는데 값이 없다"는
          // 헷갈리는 상태가 남는다.
          ...(phoneNumber ? { phoneNumber } : {}),
          identityVerified:     true,
          identityVerifiedAt:   admin.firestore.FieldValue.serverTimestamp(),
          isVerified:           true,
          verifiedAt:           admin.firestore.FieldValue.serverTimestamp(),
          profileCompleted:     true,
          verificationProvider: 'nice_intc_v2',
        },
      });

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

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');
const https = require('https');

// 카카오·네이버 로그인의 Firebase 커스텀 토큰 발급.
//
// Firebase Auth는 구글/애플 등만 기본 제공하고 카카오·네이버는 지원하지
// 않는다. 그래서 표준 방식대로 "앱이 소셜 SDK로 받은 액세스 토큰 →
// 서버가 그 토큰을 소셜 API로 검증 → 검증된 사용자 id로 Firebase 커스텀
// 토큰 발급 → 앱이 signInWithCustomToken" 흐름을 쓴다.
//
// ── 보안 원칙 ────────────────────────────────────────────────────────────────
//  1. 커스텀 토큰은 **Admin SDK로만** 만들 수 있다. 클라이언트에 어떤 관리자
//     키도 내려가지 않는다(앱은 소셜 액세스 토큰만 올려보낸다).
//  2. 클라이언트가 보낸 uid·이메일·이름은 **절대 믿지 않는다.** 전부 소셜
//     API 응답에서만 가져온다. 앱이 보내는 값은 액세스 토큰 하나뿐이다.
//  3. 카카오는 토큰이 **우리 앱에서 발급된 것인지**(app_id)까지 확인한다.
//     남의 카카오 앱에서 받은 토큰으로 우리 서비스에 들어오는 걸 막는다.
//  4. uid에 제공자 접두어를 붙인다(`kakao:123`, `naver:abc`) — 서로 다른
//     제공자의 동일한 id가 같은 계정으로 합쳐지는 사고를 구조적으로 막는다.
//
// 새 npm 의존성 없이 raw https 모듈만 쓴다(portOne.js와 같은 방식).

/// 카카오 앱 ID(숫자). 토큰이 우리 앱 것인지 검증하는 데 쓴다.
/// 비워두면 이 검증만 건너뛴다 — 값을 넣는 순간 자동으로 켜진다.
const kakaoAppId = defineSecret('KAKAO_APP_ID');

/** GET 요청 하나 — JSON 응답을 {statusCode, body}로 돌려준다. */
function getJson(hostname, path, headers) {
  return new Promise((resolve, reject) => {
    const req = https.request(
      { hostname, path, method: 'GET', headers },
      (res) => {
        let body = '';
        res.on('data', (c) => { body += c; });
        res.on('end', () => {
          try {
            resolve({ statusCode: res.statusCode, body: JSON.parse(body) });
          } catch (_) {
            resolve({ statusCode: res.statusCode, body: { _raw: body } });
          }
        });
      },
    );
    req.on('error', reject);
    req.setTimeout(10000, () => req.destroy(new Error('소셜 API 응답 시간 초과')));
    req.end();
  });
}

/** 시크릿 값을 안전하게 읽는다(미설정이면 빈 문자열). */
function secretValue(param) {
  try {
    return (param.value() || '').trim();
  } catch (_) {
    return '';
  }
}

/**
 * 카카오 앱 ID로 쓸 수 있는 값인지 — 숫자만으로 이뤄져야 한다.
 *
 * 시크릿에 자리표시자(`REPLACE_ME` 등)나 오타가 들어가면 모든 카카오 로그인이
 * `permission-denied`로 막혀버린다. 형식이 어긋난 값은 "미설정"으로 보고 앱
 * 검증만 건너뛰게 해서, 설정 실수가 전체 로그인 장애로 번지지 않게 한다
 * (portOne.js가 자리표시자 시크릿을 테스트 모드로 처리하는 것과 같은 방침).
 */
function isValidKakaoAppId(value) {
  return /^\d+$/.test(value);
}

/**
 * 검증된 소셜 프로필로 Firebase 사용자를 만들거나 갱신하고 커스텀 토큰을 준다.
 *
 * 이름·이메일·사진은 소셜에서 받은 값으로 **매번 갱신**한다 — 사용자가 카카오
 * 쪽에서 프로필을 바꾸면 다음 로그인 때 따라온다. 다만 이미 우리 쪽에서
 * 닉네임을 바꿨을 수 있으므로 Firestore `users` 문서는 건드리지 않는다
 * (그쪽은 onUserCreated와 앱이 관리한다).
 */
async function issueCustomToken({ uid, displayName, email, photoURL }) {
  const auth = admin.auth();
  const profile = {};
  if (displayName) profile.displayName = displayName;
  if (photoURL) profile.photoURL = photoURL;
  // 이메일은 소셜 계정마다 없을 수 있고, 이미 다른 계정이 쓰는 이메일이면
  // updateUser가 실패한다 — 로그인 자체를 막지 않도록 따로 처리한다.

  try {
    await auth.getUser(uid);
    if (Object.keys(profile).length > 0) {
      await auth.updateUser(uid, profile);
    }
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
    // 신규 가입 — 이 시점에 onUserCreated(auth 트리거)가 users 문서를 만든다.
    try {
      await auth.createUser({ uid, ...profile, ...(email ? { email } : {}) });
    } catch (createErr) {
      // 이메일 중복 등으로 실패하면 이메일 없이 한 번 더 시도한다.
      if (createErr.code === 'auth/email-already-exists') {
        await auth.createUser({ uid, ...profile });
      } else {
        throw createErr;
      }
    }
  }

  return auth.createCustomToken(uid);
}

/** 앱이 보낸 액세스 토큰을 꺼낸다(형식 검증 포함). */
function readAccessToken(request) {
  const token = request.data && request.data.token;
  if (!token || typeof token !== 'string' || token.length > 4096) {
    throw new HttpsError('invalid-argument', '액세스 토큰이 필요합니다.');
  }
  return token;
}

// ── 카카오 ───────────────────────────────────────────────────────────────────

exports.kakaoCustomToken = onCall(
  { region: 'asia-northeast3', secrets: [kakaoAppId] },
  async (request) => {
    const accessToken = readAccessToken(request);
    const authHeader = { Authorization: `Bearer ${accessToken}` };

    // 1) 토큰이 유효한지 + 어느 앱에서 발급됐는지 확인한다.
    const info = await getJson(
      'kapi.kakao.com', '/v1/user/access_token_info', authHeader,
    );
    if (info.statusCode !== 200) {
      console.warn('[kakaoCustomToken] 토큰 정보 조회 실패', info.statusCode, info.body);
      throw new HttpsError('unauthenticated', '카카오 토큰이 유효하지 않습니다.');
    }

    const expectedAppId = secretValue(kakaoAppId);
    if (isValidKakaoAppId(expectedAppId)) {
      // 남의 카카오 앱에서 받은 토큰으로 우리 서비스에 들어오는 걸 막는다.
      if (String(info.body.app_id) !== expectedAppId) {
        // 앱 ID 전체 값은 로그에 남기지 않는다 — 불일치 사실만 기록한다.
        console.error('[kakaoCustomToken] 다른 카카오 앱에서 발급된 토큰이라 거절했습니다.');
        throw new HttpsError('permission-denied', '이 앱에서 발급된 토큰이 아닙니다.');
      }
    } else if (expectedAppId) {
      console.warn(
        '[kakaoCustomToken] KAKAO_APP_ID 형식이 올바르지 않아(숫자가 아님) ' +
        '발급 앱 검증을 건너뜁니다. 시크릿 값을 확인해주세요.',
      );
    } else {
      console.warn(
        '[kakaoCustomToken] KAKAO_APP_ID 미설정 — 토큰의 발급 앱 검증을 건너뜁니다. ' +
        '시크릿을 등록하면 이 검증이 자동으로 켜집니다.',
      );
    }

    // 2) 프로필을 가져온다. 사용자 id는 반드시 **서버가 조회한 값**만 쓴다.
    const me = await getJson('kapi.kakao.com', '/v2/user/me', authHeader);
    if (me.statusCode !== 200 || !me.body || me.body.id == null) {
      console.warn('[kakaoCustomToken] 프로필 조회 실패', me.statusCode, me.body);
      throw new HttpsError('unauthenticated', '카카오 사용자 정보를 가져오지 못했습니다.');
    }

    const account = me.body.kakao_account || {};
    const profile = account.profile || {};
    // 이메일은 동의 항목이라 없을 수 있고, 미인증 이메일은 쓰지 않는다.
    const email = account.is_email_verified === true && account.email
      ? account.email
      : '';

    const customToken = await issueCustomToken({
      uid: `kakao:${me.body.id}`,
      displayName: profile.nickname || '',
      photoURL: profile.profile_image_url || '',
      email,
    });

    return { customToken };
  },
);

// ── 네이버 ───────────────────────────────────────────────────────────────────

exports.naverCustomToken = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    const accessToken = readAccessToken(request);

    // 네이버는 토큰 검증과 프로필 조회가 한 엔드포인트다. 여기서 돌려주는
    // `id`는 **애플리케이션(client_id)마다 다르게 발급되는 값**이라, 다른
    // 앱에서 받은 토큰을 들고 와도 우리 쪽 uid와 겹치지 않는다.
    const me = await getJson('openapi.naver.com', '/v1/nid/me', {
      Authorization: `Bearer ${accessToken}`,
    });

    if (me.statusCode !== 200 || !me.body || me.body.resultcode !== '00') {
      console.warn('[naverCustomToken] 프로필 조회 실패', me.statusCode, me.body);
      throw new HttpsError('unauthenticated', '네이버 토큰이 유효하지 않습니다.');
    }

    const r = me.body.response || {};
    if (!r.id) {
      throw new HttpsError('unauthenticated', '네이버 사용자 정보를 가져오지 못했습니다.');
    }

    const customToken = await issueCustomToken({
      uid: `naver:${r.id}`,
      displayName: r.nickname || r.name || '',
      photoURL: r.profile_image || '',
      email: r.email || '',
    });

    return { customToken };
  },
);

// 자기검증용 export — socialAuth.selfcheck.js가 쓴다.
module.exports.__test = {
  issueCustomToken,
  readAccessToken,
  secretValue,
  isValidKakaoAppId,
};

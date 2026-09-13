// ══════════════════════════════════════════════════════════════════════════
// 안전한 미디어 업로드 경로 — 앱에 Cloudflare 자격증명을 두지 않는다.
//
// ── 왜 필요한가 ─────────────────────────────────────────────────────────
// 예전(구경로) 앱은 `.env`에 담긴 계정 단위 CLOUDFLARE_API_TOKEN으로
// api.cloudflare.com을 **직접** 호출해 R2/Stream에 올리고 지웠다. 그 토큰은
// 배포된 APK/IPA 안에 평문으로 들어 있어 누구나 추출할 수 있었고, R2에는
// "이 토큰은 이 경로만"이라는 개념이 없다. 즉 토큰을 가진 사람은 남의
// 사진을 덮어쓰거나 버킷을 통째로 지울 수 있었다. 경로에 들어가는
// `party_images/{uid}/`의 uid도 클라이언트가 만든 문자열일 뿐이라 아무것도
// 보장하지 못했다.
//
// 이 모듈은 그 구조를 뒤집는다:
//   · 자격증명은 **서버에만** 있다.
//   · 경로의 uid는 **request.auth.uid가 정본**이다. 클라이언트가 uid나
//     key를 보내도 읽지 않는다.
//   · 서버는 "이 키 하나에, 이 크기·형식으로, 5분 안에"만 쓸 수 있는
//     일회성 허가(presigned PUT)를 발급한다. 바이트는 R2로 직행하므로
//     Functions를 통과하지 않는다(용량·비용·지연 문제 없음).
//   · 동영상은 Cloudflare Stream의 direct creator upload를 쓴다. 덤으로
//     30초 제한이 **서버 강제**가 된다(지금은 앱에만 있어 우회 가능하다).
//
// ── 지금은 이 경로가 유일하다 ───────────────────────────────────────────
// 앱은 이 세 콜러블만 쓴다(`CloudflareService`). 서버의 삭제·정리 경로
// (contentDelete.js · index.js의 예약 삭제 · accountWithdrawal.js ·
// registrationLimitGuard.js)도 **여기서 내보내는 자격증명과 헬퍼를 그대로
// 나눠 쓴다**([cloudflareCleanup.js]). 즉 CLOUDFLARE_API_TOKEN을 읽는 코드는
// 이제 하나도 남아 있지 않고, 그 시크릿은 폐기 대상이다.
//
// ── 자격증명 ────────────────────────────────────────────────────────────
// 유출된 것으로 간주해야 하는 기존 토큰을 **재사용하지 않는다.**
//
//   R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY
//     R2 대시보드에서 발급하는 S3 액세스 키. **버킷 하나로 스코프**할 수
//     있어(Object Read & Write) 계정 단위 API 토큰보다 훨씬 좁다.
//   R2_PUBLIC_BASE_URL
//     공개 읽기 주소(https://pub-xxxx.r2.dev). 업로드 결과 URL을 만들고,
//     삭제 요청이 우리 버킷을 가리키는지 확인하는 데 쓴다.
//   CLOUDFLARE_STREAM_API_TOKEN
//     Stream:Edit **전용** 새 토큰. R2 액세스 키로는 Stream API를 부를 수
//     없어서(자격증명 체계가 다르다) 별도로 둔다. 기존 통합 토큰과 달리
//     R2 권한이 없으므로, 이 토큰이 새더라도 사진은 안전하다.
//   CLOUDFLARE_ACCOUNT_ID / CLOUDFLARE_R2_BUCKET
//     비밀이 아니라 식별자다. 이미 시크릿으로 등록돼 있어 그대로 쓴다.
//
// 시크릿이 하나라도 없으면 **막는다(fail-closed).** 구경로로 조용히
// 되돌아가는 폴백은 두지 않는다 — 그러면 "안전한 경로"라는 말이 거짓이 된다.
// ══════════════════════════════════════════════════════════════════════════

const crypto = require('crypto');
const https = require('https');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');

const REGION = 'asia-northeast3';

// R2의 S3 호환 API는 리전 개념이 없어 서명에 항상 'auto'를 쓴다.
const S3_REGION = 'auto';
const S3_SERVICE = 's3';

// ── 시크릿 ────────────────────────────────────────────────────────────────
const r2AccessKeyId = defineSecret('R2_ACCESS_KEY_ID');
const r2SecretAccessKey = defineSecret('R2_SECRET_ACCESS_KEY');
const r2PublicBaseUrl = defineSecret('R2_PUBLIC_BASE_URL');
const cfAccountId = defineSecret('CLOUDFLARE_ACCOUNT_ID');
const cfR2Bucket = defineSecret('CLOUDFLARE_R2_BUCKET');
const cfStreamApiToken = defineSecret('CLOUDFLARE_STREAM_API_TOKEN');

// ── 정책 상수 ─────────────────────────────────────────────────────────────

/// presigned PUT 유효 시간(초). 짧을수록 좋다 — 유출돼도 이 시간 안에,
/// 그 키 하나에만 쓸 수 있다. 사진 한 장 올리는 데는 충분하다.
const PRESIGN_TTL_SECONDS = 300;

/// Stream direct upload URL 유효 시간(초). 사진보다 길게 잡는 이유는
/// 동영상은 압축 후 수십 MB를 올려야 해서다. Cloudflare가 허용하는 범위는
/// 2분~6시간이며 그 안에서 가장 짧은 쪽에 가깝게 둔다.
const STREAM_UPLOAD_TTL_SECONDS = 30 * 60;

/// 동영상 최대 길이(초). 지금은 앱(party_media_editor.dart)에만 있는 규칙이라
/// 콜러블을 직접 부르면 우회된다. 여기서 Cloudflare에 넘겨 **서버가 강제**한다.
const STREAM_MAX_DURATION_SECONDS = 30;

/// 허용하는 저장 폴더. 앱이 실제로 쓰는 두 곳뿐이다 — 넓히면 그만큼
/// "어디에 무엇이 있는지"를 서버가 보장하지 못하게 된다.
///
/// 폴더마다 확장자·용량 정책이 다르다. 상세 이미지는 캔바 상세페이지처럼
/// 세로로 긴 정지 이미지 한 장이라 형식을 좁게 잡고(gif·heic 제외), 일반
/// 이미지는 지금 앱이 올릴 수 있는 형식을 그대로 받는다(iOS heic 등).
const FOLDERS = {
  // 대표사진 · 상세페이지 블록 사진 · 플레이스/장소대여 · 프로필 · 피드백 …
  image: {
    folder: 'party_images',
    extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif', 'heic'],
    maxBytes: 20 * 1024 * 1024,
  },
  // 파티 상세 본문 전용 세로형 이미지 1장
  // (party_app/lib/models/party_detail_image.dart의 storageFolder와 같은 값)
  detailImage: {
    folder: 'party_images/detail',
    extensions: ['jpg', 'jpeg', 'png', 'webp'],
    maxBytes: 10 * 1024 * 1024,
  },
};

/// 폴더 문자열 → kind 역인덱스. 앱의 CloudflareService가 지금도 `folder`
/// 문자열을 넘기므로, 나중에 전환할 때 호출부를 안 고치도록 둘 다 받는다.
const FOLDER_TO_KIND = Object.fromEntries(
  Object.entries(FOLDERS).map(([kind, cfg]) => [cfg.folder, kind]),
);

/// 확장자 → 정본 MIME. 클라이언트가 contentType을 보내더라도 **이 표가
/// 정본**이고, 다르면 거부한다(확장자와 다른 타입으로 올려 브라우저가
/// 엉뚱하게 해석하게 만드는 것을 막는다).
const MIME_BY_EXT = {
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
  png: 'image/png',
  webp: 'image/webp',
  gif: 'image/gif',
  heic: 'image/heic',
};

// ══════════════════════════════════════════════════════════════════════════
// 순수 헬퍼 — selfcheck가 네트워크 없이 검증하는 부분이다.
// ══════════════════════════════════════════════════════════════════════════

/// 로그인하지 않았으면 막는다. **어떤 발급/삭제도 이 검사를 먼저 통과한다.**
function requireUid(request) {
  const uid = request && request.auth && request.auth.uid;
  if (typeof uid !== 'string' || uid.length === 0) {
    throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
  }
  return uid;
}

/// uid가 저장 경로의 한 조각으로 쓸 수 있는 모양인가.
///
/// Firebase Auth uid는 영숫자라 정상값은 항상 통과한다. 그런데도 확인하는
/// 이유는, 이 값이 그대로 오브젝트 키에 들어가기 때문이다 — 만약 어떤 경로로든
/// 슬래시나 `..`가 섞인 uid가 들어오면 다른 사용자 폴더를 가리키게 된다.
function isSafeUid(uid) {
  return typeof uid === 'string' &&
    uid.length > 0 &&
    uid.length <= 128 &&
    /^[A-Za-z0-9_-]+$/.test(uid);
}

/// 요청이 말하는 저장 위치를 whitelist로 해석한다.
///
/// `kind`('image' | 'detailImage')를 우선하고, 없으면 `folder` 문자열을
/// 역인덱스로 찾는다. **둘 다 표에 없으면 거부한다** — 임의 문자열을 그대로
/// 경로에 쓰지 않으므로 `../`나 남의 uid 폴더를 지정할 방법 자체가 없다.
function resolveFolder({ kind, folder }) {
  if (typeof kind === 'string' && Object.prototype.hasOwnProperty.call(FOLDERS, kind)) {
    return { kind, ...FOLDERS[kind] };
  }
  if (typeof folder === 'string' && Object.prototype.hasOwnProperty.call(FOLDER_TO_KIND, folder)) {
    const resolvedKind = FOLDER_TO_KIND[folder];
    return { kind: resolvedKind, ...FOLDERS[resolvedKind] };
  }
  throw new HttpsError(
    'invalid-argument',
    '허용되지 않는 저장 위치입니다.',
  );
}

/// 파일 확장자를 정규화하고 폴더 정책에 맞는지 확인한다.
function resolveExtension(target, rawExt) {
  if (typeof rawExt !== 'string') {
    throw new HttpsError('invalid-argument', '파일 형식이 필요합니다.');
  }
  // '.JPG' · 'photo.JPG' 어느 쪽으로 와도 마지막 조각만 본다.
  const ext = rawExt.trim().toLowerCase().replace(/^.*\./, '').replace(/^\./, '');
  if (!target.extensions.includes(ext)) {
    throw new HttpsError(
      'invalid-argument',
      `지원하지 않는 이미지 형식입니다. (${target.extensions.join(', ')})`,
    );
  }
  return ext;
}

/// 클라이언트가 contentType을 보냈다면 확장자에서 유도한 정본과 같아야 한다.
function resolveContentType(ext, rawContentType) {
  const canonical = MIME_BY_EXT[ext];
  if (!canonical) {
    throw new HttpsError('invalid-argument', '지원하지 않는 이미지 형식입니다.');
  }
  if (rawContentType === undefined || rawContentType === null || rawContentType === '') {
    return canonical;
  }
  if (typeof rawContentType !== 'string') {
    throw new HttpsError('invalid-argument', 'contentType이 올바르지 않습니다.');
  }
  // 'image/jpeg; charset=...' 같은 파라미터는 떼고 비교한다.
  const normalized = rawContentType.split(';')[0].trim().toLowerCase();
  // jpg/jpeg는 같은 타입이라 표에서 이미 하나로 모인다.
  if (normalized !== canonical) {
    throw new HttpsError(
      'invalid-argument',
      '파일 형식과 contentType이 서로 다릅니다.',
    );
  }
  return canonical;
}

/// 업로드 크기를 확인한다. presigned URL 서명에 이 값을 박아 넣으므로,
/// 발급받은 뒤 더 큰 파일을 올리려 하면 R2가 거부한다.
function resolveContentLength(target, rawLength) {
  if (typeof rawLength !== 'number' || !Number.isFinite(rawLength)) {
    throw new HttpsError('invalid-argument', '파일 크기가 필요합니다.');
  }
  if (!Number.isInteger(rawLength) || rawLength <= 0) {
    throw new HttpsError('invalid-argument', '파일 크기가 올바르지 않습니다.');
  }
  if (rawLength > target.maxBytes) {
    const mb = Math.floor(target.maxBytes / (1024 * 1024));
    throw new HttpsError(
      'invalid-argument',
      `파일이 너무 큽니다. 최대 ${mb}MB까지 올릴 수 있어요.`,
    );
  }
  return rawLength;
}

/// 저장할 오브젝트 키를 **서버가** 만든다.
///
/// 클라이언트가 보낸 key·path·uid는 어디에도 쓰이지 않는다. uid 자리는
/// 언제나 [uid](=request.auth.uid)다.
///
/// 뒤에 붙는 임의 문자열은 같은 밀리초에 두 번 발급받았을 때 키가 겹치는
/// 것을 막는다(구경로는 타임스탬프만 써서 이론상 겹칠 수 있었다).
function buildObjectKey({ uid, target, ext, nowMs, nonce }) {
  if (!isSafeUid(uid)) {
    throw new HttpsError('permission-denied', '사용자 식별자가 올바르지 않습니다.');
  }
  const suffix = nonce || crypto.randomBytes(6).toString('hex');
  return `${target.folder}/${uid}/${nowMs}-${suffix}.${ext}`;
}

/// 업로드 요청 전체를 검증하고 확정된 값만 돌려준다.
/// 여기서 통과한 값만 서명에 들어간다.
function validateUploadRequest({ uid, data, nowMs, nonce }) {
  const payload = data || {};
  // ⚠️ payload.uid / payload.key / payload.path는 **읽지 않는다.**
  //    보내와도 아래 어디에서도 참조하지 않으므로 조용히 무시된다.
  const target = resolveFolder(payload);
  const ext = resolveExtension(target, payload.ext);
  const contentType = resolveContentType(ext, payload.contentType);
  const contentLength = resolveContentLength(target, payload.contentLength);
  const key = buildObjectKey({ uid, target, ext, nowMs, nonce });
  return { kind: target.kind, key, ext, contentType, contentLength };
}

// ── SigV4 ─────────────────────────────────────────────────────────────────
//
// AWS SDK를 넣지 않고 직접 서명한다. functions/package.json에 SDK를 더하면
// 콜드 스타트와 배포 크기가 커지는데, 여기서 필요한 것은 SigV4 한 종류뿐이라
// node:crypto로 충분하다.

function sha256Hex(value) {
  return crypto.createHash('sha256').update(value, 'utf8').digest('hex');
}

function hmac(key, value) {
  return crypto.createHmac('sha256', key).update(value, 'utf8').digest();
}

function signingKey(secret, dateStamp) {
  const kDate = hmac(`AWS4${secret}`, dateStamp);
  const kRegion = hmac(kDate, S3_REGION);
  const kService = hmac(kRegion, S3_SERVICE);
  return hmac(kService, 'aws4_request');
}

/// RFC 3986 인코딩 — encodeURIComponent가 남기는 `!*'()`까지 인코딩한다.
/// 서명과 실제 요청의 경로가 한 글자라도 다르면 R2가 거부하므로 정확해야 한다.
function encodeRfc3986(value) {
  return encodeURIComponent(value).replace(
    /[!*'()]/g,
    (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`,
  );
}

/// 키의 슬래시는 경로 구분자로 남기고 각 조각만 인코딩한다.
function encodeKeyPath(key) {
  return key.split('/').map(encodeRfc3986).join('/');
}

/// `20260822T041530Z` / `20260822` 형태의 서명용 시각.
function amzDates(nowMs) {
  const iso = new Date(nowMs).toISOString().replace(/[:-]|\.\d{3}/g, '');
  return { amzDate: iso, dateStamp: iso.slice(0, 8) };
}

function canonicalQuery(params) {
  return Object.keys(params)
    .sort()
    .map((k) => `${encodeRfc3986(k)}=${encodeRfc3986(params[k])}`)
    .join('&');
}

/// 단일 오브젝트 PUT용 presigned URL.
///
/// **무엇이 서명에 묶이는가** — 이 네 가지가 URL 하나에 못박힌다:
///   · 메서드(PUT)와 경로(/{bucket}/{key})  → 다른 키에 재사용 불가
///   · content-type                          → 다른 형식으로 올리기 불가
///   · content-length                        → 더 큰 파일 올리기 불가
///   · X-Amz-Date + X-Amz-Expires            → 시간이 지나면 무효
/// 하나라도 다르게 보내면 서명이 안 맞아 R2가 403으로 거부한다.
function presignR2Put({
  accessKeyId,
  secretAccessKey,
  accountId,
  bucket,
  key,
  contentType,
  contentLength,
  expiresIn = PRESIGN_TTL_SECONDS,
  nowMs = Date.now(),
}) {
  const host = `${accountId}.r2.cloudflarestorage.com`;
  const { amzDate, dateStamp } = amzDates(nowMs);
  const scope = `${dateStamp}/${S3_REGION}/${S3_SERVICE}/aws4_request`;

  // content-length·content-type까지 서명 대상에 넣는다. 이것이 "이 URL로는
  // 이 크기·이 형식만 올릴 수 있다"를 만드는 부분이다.
  const signedHeaders = 'content-length;content-type;host';
  const canonicalHeaders =
    `content-length:${contentLength}\n` +
    `content-type:${contentType}\n` +
    `host:${host}\n`;

  const query = {
    'X-Amz-Algorithm': 'AWS4-HMAC-SHA256',
    'X-Amz-Credential': `${accessKeyId}/${scope}`,
    'X-Amz-Date': amzDate,
    'X-Amz-Expires': String(expiresIn),
    'X-Amz-SignedHeaders': signedHeaders,
  };

  const canonicalUri = `/${encodeRfc3986(bucket)}/${encodeKeyPath(key)}`;
  const canonicalRequest = [
    'PUT',
    canonicalUri,
    canonicalQuery(query),
    canonicalHeaders,
    signedHeaders,
    'UNSIGNED-PAYLOAD',
  ].join('\n');

  const stringToSign = [
    'AWS4-HMAC-SHA256',
    amzDate,
    scope,
    sha256Hex(canonicalRequest),
  ].join('\n');

  const signature = crypto
    .createHmac('sha256', signingKey(secretAccessKey, dateStamp))
    .update(stringToSign, 'utf8')
    .digest('hex');

  return {
    url:
      `https://${host}${canonicalUri}?${canonicalQuery(query)}` +
      `&X-Amz-Signature=${signature}`,
    expiresIn,
    // 클라이언트가 반드시 이대로 보내야 하는 헤더. 다르면 R2가 거부한다.
    requiredHeaders: { 'Content-Type': contentType, 'Content-Length': String(contentLength) },
  };
}

/// 헤더 인증 방식 SigV4 — 서버가 직접 보내는 DELETE에 쓴다(presign 불필요).
function signedR2Request({
  method,
  accessKeyId,
  secretAccessKey,
  accountId,
  bucket,
  key,
  nowMs = Date.now(),
}) {
  const host = `${accountId}.r2.cloudflarestorage.com`;
  const { amzDate, dateStamp } = amzDates(nowMs);
  const scope = `${dateStamp}/${S3_REGION}/${S3_SERVICE}/aws4_request`;
  const emptyPayloadHash = sha256Hex('');

  const signedHeaders = 'host;x-amz-content-sha256;x-amz-date';
  const canonicalHeaders =
    `host:${host}\n` +
    `x-amz-content-sha256:${emptyPayloadHash}\n` +
    `x-amz-date:${amzDate}\n`;

  const canonicalUri = `/${encodeRfc3986(bucket)}/${encodeKeyPath(key)}`;
  const canonicalRequest = [
    method,
    canonicalUri,
    '',
    canonicalHeaders,
    signedHeaders,
    emptyPayloadHash,
  ].join('\n');

  const stringToSign = [
    'AWS4-HMAC-SHA256',
    amzDate,
    scope,
    sha256Hex(canonicalRequest),
  ].join('\n');

  const signature = crypto
    .createHmac('sha256', signingKey(secretAccessKey, dateStamp))
    .update(stringToSign, 'utf8')
    .digest('hex');

  return {
    host,
    path: canonicalUri,
    headers: {
      Authorization:
        `AWS4-HMAC-SHA256 Credential=${accessKeyId}/${scope}, ` +
        `SignedHeaders=${signedHeaders}, Signature=${signature}`,
      'x-amz-content-sha256': emptyPayloadHash,
      'x-amz-date': amzDate,
    },
  };
}

// ── 소유권 판정 ───────────────────────────────────────────────────────────

/// 공개 URL이 **우리 버킷의, 이 사용자 소유** 오브젝트인지 확인하고 키를
/// 돌려준다. 하나라도 어긋나면 던진다.
///
/// 막는 것:
///   · 우리 공개 주소가 아닌 URL(다른 버킷·다른 도메인·임의 Cloudflare URL)
///   · 허용 폴더 밖의 키
///   · **다른 사용자 폴더의 키** — 여기가 이 함수의 존재 이유다
///   · `..`·빈 조각으로 경로를 빠져나가려는 시도
function parseOwnedR2Key({ url, publicBase, uid }) {
  if (typeof url !== 'string' || url.length === 0) {
    throw new HttpsError('invalid-argument', '삭제할 파일 주소가 필요합니다.');
  }
  if (!isSafeUid(uid)) {
    throw new HttpsError('permission-denied', '사용자 식별자가 올바르지 않습니다.');
  }

  const base = String(publicBase || '').replace(/\/+$/, '');
  if (base.length === 0) {
    throw new HttpsError('failed-precondition', '업로드 설정이 완료되지 않았습니다.');
  }

  // 접두사 비교는 경계까지 확인한다 — 'https://pub-a.r2.dev'로 시작한다고
  // 해서 'https://pub-attacker.r2.dev/...'를 통과시키면 안 된다.
  if (!url.startsWith(`${base}/`)) {
    throw new HttpsError('permission-denied', '이 파일을 삭제할 권한이 없습니다.');
  }

  // 쿼리/프래그먼트를 붙여 판정을 흐리지 못하게 잘라낸다.
  const rawKey = url.slice(base.length + 1).split(/[?#]/)[0];
  if (rawKey.length === 0) {
    throw new HttpsError('invalid-argument', '삭제할 파일 주소가 올바르지 않습니다.');
  }

  let key;
  try {
    key = decodeURIComponent(rawKey);
  } catch (_) {
    throw new HttpsError('invalid-argument', '삭제할 파일 주소가 올바르지 않습니다.');
  }

  const segments = key.split('/');
  if (segments.some((s) => s.length === 0 || s === '.' || s === '..')) {
    throw new HttpsError('permission-denied', '이 파일을 삭제할 권한이 없습니다.');
  }

  // 허용 폴더 중 이 키가 속한 곳을 찾는다. 'party_images/detail'이
  // 'party_images'보다 먼저 걸리도록 긴 것부터 본다.
  const folders = Object.values(FOLDERS)
    .map((f) => f.folder)
    .sort((a, b) => b.length - a.length);
  const folder = folders.find((f) => key.startsWith(`${f}/`));
  if (!folder) {
    throw new HttpsError('permission-denied', '이 파일을 삭제할 권한이 없습니다.');
  }

  // 폴더 바로 다음 조각이 소유자 uid여야 하고, 그 아래 파일명이 있어야 한다.
  const rest = key.slice(folder.length + 1).split('/');
  if (rest.length !== 2 || rest[1].length === 0) {
    throw new HttpsError('permission-denied', '이 파일을 삭제할 권한이 없습니다.');
  }
  if (rest[0] !== uid) {
    throw new HttpsError('permission-denied', '본인이 올린 파일만 삭제할 수 있습니다.');
  }

  return { key, folder };
}

/// Stream 동영상의 소유자를 판정한다.
///
/// 업로드할 때 `creator`에 uid를 박아두므로 그것이 정본이다. `meta.uid`도
/// 함께 본다(같은 값을 두 군데 남긴다 — 어느 한쪽이 비어도 판정이 된다).
///
/// **구경로로 올라간 동영상은 creator가 없다.** 그런 영상은 여기서 소유자를
/// 알 수 없으므로 삭제를 거부한다(fail-closed). 그 영상들은 지금처럼 앱의
/// 구경로와 서버의 콘텐츠 삭제가 계속 정리한다.
function isOwnStreamVideo(videoInfo, uid) {
  if (!videoInfo || !isSafeUid(uid)) return false;
  const creator = typeof videoInfo.creator === 'string' ? videoInfo.creator : '';
  const metaUid =
    videoInfo.meta && typeof videoInfo.meta.uid === 'string' ? videoInfo.meta.uid : '';
  if (creator.length === 0 && metaUid.length === 0) return false;
  if (creator.length > 0 && creator !== uid) return false;
  if (metaUid.length > 0 && metaUid !== uid) return false;
  return true;
}

/// Stream uid는 32자리 16진수다. 다른 모양이면 API를 부르기 전에 막는다.
function isStreamVideoUid(value) {
  return typeof value === 'string' && /^[a-f0-9]{32}$/.test(value);
}

/// Stream direct creator upload 요청 본문.
///
/// `maxDurationSeconds`가 이 함수의 핵심이다 — 30초를 넘는 영상은
/// Cloudflare가 업로드 자체를 거부하므로, 앱을 거치지 않고 콜러블을 직접
/// 불러도 긴 영상을 넣을 수 없다.
function buildDirectUploadBody({ uid, nowMs = Date.now() }) {
  if (!isSafeUid(uid)) {
    throw new HttpsError('permission-denied', '사용자 식별자가 올바르지 않습니다.');
  }
  return {
    maxDurationSeconds: STREAM_MAX_DURATION_SECONDS,
    // 업로드 URL 자체의 만료. 이 시각이 지나면 URL이 무효가 된다.
    expiry: new Date(nowMs + STREAM_UPLOAD_TTL_SECONDS * 1000).toISOString(),
    // 소유자 표시 — deleteOwnUpload가 이 값으로 본인 확인을 한다.
    creator: uid,
    meta: { uid },
    requireSignedURLs: false,
  };
}

/// 업로드가 끝난 뒤 앱이 쓰게 될 재생/썸네일 주소. 구경로가 응답에
/// playback이 없을 때 쓰던 폴백과 **같은 형식**이라, 앱을 전환해도 저장되는
/// 값의 모양이 바뀌지 않는다.
function streamPlaybackUrls(videoUid) {
  return {
    videoUrl: `https://videodelivery.net/${videoUid}/manifest/video.m3u8`,
    videoThumbnailUrl: `https://videodelivery.net/${videoUid}/thumbnails/thumbnail.jpg`,
  };
}

// ── 설정 읽기(fail-closed) ────────────────────────────────────────────────

/// 시크릿을 읽는다. 하나라도 비어 있으면 **던진다.** 구경로 토큰으로
/// 되돌아가는 폴백은 두지 않는다.
function readR2Config() {
  const missing = [];
  const read = (param, name) => {
    let value = '';
    try {
      value = String(param.value() || '').trim();
    } catch (_) {
      value = '';
    }
    if (value.length === 0) missing.push(name);
    return value;
  };

  const accessKeyId = read(r2AccessKeyId, 'R2_ACCESS_KEY_ID');
  const secretAccessKey = read(r2SecretAccessKey, 'R2_SECRET_ACCESS_KEY');
  const publicBase = read(r2PublicBaseUrl, 'R2_PUBLIC_BASE_URL');
  const accountId = read(cfAccountId, 'CLOUDFLARE_ACCOUNT_ID');
  const bucket = read(cfR2Bucket, 'CLOUDFLARE_R2_BUCKET');

  if (missing.length > 0) {
    // 어떤 키가 빠졌는지는 **로그에만** 남긴다. 값은 절대 찍지 않는다.
    console.error(`[mediaUploads] 시크릿 누락: ${missing.join(', ')}`);
    throw new HttpsError(
      'failed-precondition',
      '파일 업로드 설정이 완료되지 않았습니다. 잠시 후 다시 시도해주세요.',
    );
  }
  return {
    accessKeyId,
    secretAccessKey,
    publicBase: publicBase.replace(/\/+$/, ''),
    accountId,
    bucket,
  };
}

function readStreamConfig() {
  const missing = [];
  const read = (param, name) => {
    let value = '';
    try {
      value = String(param.value() || '').trim();
    } catch (_) {
      value = '';
    }
    if (value.length === 0) missing.push(name);
    return value;
  };

  const apiToken = read(cfStreamApiToken, 'CLOUDFLARE_STREAM_API_TOKEN');
  const accountId = read(cfAccountId, 'CLOUDFLARE_ACCOUNT_ID');

  if (missing.length > 0) {
    console.error(`[mediaUploads] 시크릿 누락: ${missing.join(', ')}`);
    throw new HttpsError(
      'failed-precondition',
      '동영상 업로드 설정이 완료되지 않았습니다. 잠시 후 다시 시도해주세요.',
    );
  }
  return { apiToken, accountId };
}

// ── HTTP ──────────────────────────────────────────────────────────────────

function httpRequest({ hostname, path, method, headers = {}, body = null }) {
  return new Promise((resolve, reject) => {
    const req = https.request({ hostname, path, method, headers }, (res) => {
      let raw = '';
      res.on('data', (c) => { raw += c; });
      res.on('end', () => resolve({ statusCode: res.statusCode, body: raw }));
    });
    req.on('error', reject);
    req.setTimeout(20000, () => req.destroy(new Error('timeout')));
    if (body !== null) req.write(body);
    req.end();
  });
}

// ══════════════════════════════════════════════════════════════════════════
// Cloud Functions
// ══════════════════════════════════════════════════════════════════════════

/// 사진 업로드 허가 발급.
///
/// 입력: { kind | folder, ext, contentType?, contentLength }
/// 출력: { uploadUrl, publicUrl, key, expiresIn, requiredHeaders }
///
/// 클라이언트가 uid·key·path를 보내도 **읽지 않는다.** 경로의 uid는 언제나
/// request.auth.uid다.
exports.createUploadUrl = onCall(
  {
    region: REGION,
    secrets: [r2AccessKeyId, r2SecretAccessKey, r2PublicBaseUrl, cfAccountId, cfR2Bucket],
  },
  async (request) => {
    const uid = requireUid(request);
    const config = readR2Config();
    const nowMs = Date.now();

    const { kind, key, contentType, contentLength } = validateUploadRequest({
      uid,
      data: request.data,
      nowMs,
    });

    const presigned = presignR2Put({
      accessKeyId: config.accessKeyId,
      secretAccessKey: config.secretAccessKey,
      accountId: config.accountId,
      bucket: config.bucket,
      key,
      contentType,
      contentLength,
      expiresIn: PRESIGN_TTL_SECONDS,
      nowMs,
    });

    console.log(`[mediaUploads] createUploadUrl uid=${uid} kind=${kind} key=${key}`);

    return {
      uploadUrl: presigned.url,
      publicUrl: `${config.publicBase}/${key}`,
      key,
      expiresIn: presigned.expiresIn,
      requiredHeaders: presigned.requiredHeaders,
    };
  },
);

/// 동영상 업로드 허가 발급(Cloudflare Stream direct creator upload).
///
/// 출력: { uploadUrl, videoUid, videoUrl, videoThumbnailUrl, expiresIn,
///         maxDurationSeconds }
exports.createVideoUploadUrl = onCall(
  { region: REGION, secrets: [cfStreamApiToken, cfAccountId] },
  async (request) => {
    const uid = requireUid(request);
    const { apiToken, accountId } = readStreamConfig();

    const body = JSON.stringify(buildDirectUploadBody({ uid, nowMs: Date.now() }));
    const res = await httpRequest({
      hostname: 'api.cloudflare.com',
      path: `/client/v4/accounts/${accountId}/stream/direct_upload`,
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiToken}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
      },
      body,
    });

    let parsed;
    try {
      parsed = JSON.parse(res.body);
    } catch (_) {
      parsed = null;
    }
    if (res.statusCode !== 200 || !parsed || parsed.success !== true) {
      // 응답 본문은 로그에만 — 사용자 문구에 넣지 않는다.
      console.error(
        `[mediaUploads] direct_upload 실패 status=${res.statusCode} ` +
        `body=${String(res.body).slice(0, 300)}`,
      );
      throw new HttpsError('internal', '동영상 업로드를 시작하지 못했습니다.');
    }

    const videoUid = parsed.result && parsed.result.uid;
    const uploadUrl = parsed.result && parsed.result.uploadURL;
    if (!isStreamVideoUid(videoUid) || typeof uploadUrl !== 'string') {
      console.error('[mediaUploads] direct_upload 응답 형식이 예상과 다릅니다.');
      throw new HttpsError('internal', '동영상 업로드를 시작하지 못했습니다.');
    }

    console.log(`[mediaUploads] createVideoUploadUrl uid=${uid} videoUid=${videoUid}`);

    return {
      uploadUrl,
      videoUid,
      ...streamPlaybackUrls(videoUid),
      expiresIn: STREAM_UPLOAD_TTL_SECONDS,
      maxDurationSeconds: STREAM_MAX_DURATION_SECONDS,
    };
  },
);

/// 본인이 올린 파일 하나를 지운다.
///
/// 입력: { url } (사진) 또는 { videoUid } (동영상)
///
/// 사진은 키의 uid 조각이, 동영상은 Stream의 creator가 request.auth.uid와
/// 같아야 한다. 다르면 거부한다. 관리자 예외도 두지 않는다 — 운영 삭제는
/// 이미 contentDelete.js가 Admin SDK로 따로 처리한다.
exports.deleteOwnUpload = onCall(
  {
    region: REGION,
    secrets: [
      r2AccessKeyId, r2SecretAccessKey, r2PublicBaseUrl, cfAccountId, cfR2Bucket,
      cfStreamApiToken,
    ],
  },
  async (request) => {
    const uid = requireUid(request);
    const data = request.data || {};

    // ── 동영상 ──────────────────────────────────────────────────────────
    if (data.videoUid !== undefined && data.videoUid !== null && data.videoUid !== '') {
      if (!isStreamVideoUid(data.videoUid)) {
        throw new HttpsError('invalid-argument', '동영상 식별자가 올바르지 않습니다.');
      }
      const { apiToken, accountId } = readStreamConfig();
      const videoUid = data.videoUid;

      const info = await httpRequest({
        hostname: 'api.cloudflare.com',
        path: `/client/v4/accounts/${accountId}/stream/${videoUid}`,
        method: 'GET',
        headers: { Authorization: `Bearer ${apiToken}` },
      });
      let parsed;
      try {
        parsed = JSON.parse(info.body);
      } catch (_) {
        parsed = null;
      }
      if (info.statusCode !== 200 || !parsed || parsed.success !== true) {
        console.error(
          `[mediaUploads] Stream 조회 실패 status=${info.statusCode} uid=${videoUid}`,
        );
        throw new HttpsError('not-found', '동영상을 찾을 수 없습니다.');
      }
      if (!isOwnStreamVideo(parsed.result, uid)) {
        console.warn(
          `[mediaUploads] 동영상 삭제 거부 uid=${uid} videoUid=${videoUid}`,
        );
        throw new HttpsError(
          'permission-denied',
          '본인이 올린 동영상만 삭제할 수 있습니다.',
        );
      }

      const del = await httpRequest({
        hostname: 'api.cloudflare.com',
        path: `/client/v4/accounts/${accountId}/stream/${videoUid}`,
        method: 'DELETE',
        headers: { Authorization: `Bearer ${apiToken}` },
      });
      if (del.statusCode !== 200 && del.statusCode !== 204) {
        console.error(
          `[mediaUploads] Stream 삭제 실패 status=${del.statusCode} uid=${videoUid}`,
        );
        throw new HttpsError('internal', '동영상을 삭제하지 못했습니다.');
      }
      console.log(`[mediaUploads] deleteOwnUpload(video) uid=${uid} videoUid=${videoUid}`);
      return { deleted: true, kind: 'video' };
    }

    // ── 사진 ────────────────────────────────────────────────────────────
    const config = readR2Config();
    const { key } = parseOwnedR2Key({
      url: data.url,
      publicBase: config.publicBase,
      uid,
    });

    const signed = signedR2Request({
      method: 'DELETE',
      accessKeyId: config.accessKeyId,
      secretAccessKey: config.secretAccessKey,
      accountId: config.accountId,
      bucket: config.bucket,
      key,
      nowMs: Date.now(),
    });

    const res = await httpRequest({
      hostname: signed.host,
      path: signed.path,
      method: 'DELETE',
      headers: signed.headers,
    });
    // 이미 없는 오브젝트(404)는 성공으로 본다 — 삭제의 목적은 "없는 상태"다.
    if (res.statusCode !== 204 && res.statusCode !== 200 && res.statusCode !== 404) {
      console.error(`[mediaUploads] R2 삭제 실패 status=${res.statusCode} key=${key}`);
      throw new HttpsError('internal', '파일을 삭제하지 못했습니다.');
    }

    console.log(`[mediaUploads] deleteOwnUpload(image) uid=${uid} key=${key}`);
    return { deleted: true, kind: 'image', key };
  },
);

// ── selfcheck / 다른 모듈용 순수 헬퍼 ─────────────────────────────────────
//
// ⚠️ 이 모듈은 Cloud Function이 아닌 것도 내보내므로 index.js에서
//    Object.assign(exports, require('./mediaUploads'))로 붙이면 안 된다.
//    반드시 이름으로 하나씩 참조한다(contentCleanup.js와 같은 규칙).
module.exports.FOLDERS = FOLDERS;
module.exports.FOLDER_TO_KIND = FOLDER_TO_KIND;
module.exports.MIME_BY_EXT = MIME_BY_EXT;
module.exports.PRESIGN_TTL_SECONDS = PRESIGN_TTL_SECONDS;
module.exports.STREAM_UPLOAD_TTL_SECONDS = STREAM_UPLOAD_TTL_SECONDS;
module.exports.STREAM_MAX_DURATION_SECONDS = STREAM_MAX_DURATION_SECONDS;
module.exports.requireUid = requireUid;
module.exports.isSafeUid = isSafeUid;
module.exports.resolveFolder = resolveFolder;
module.exports.resolveExtension = resolveExtension;
module.exports.resolveContentType = resolveContentType;
module.exports.resolveContentLength = resolveContentLength;
module.exports.buildObjectKey = buildObjectKey;
module.exports.validateUploadRequest = validateUploadRequest;
module.exports.presignR2Put = presignR2Put;
module.exports.signedR2Request = signedR2Request;
module.exports.parseOwnedR2Key = parseOwnedR2Key;
module.exports.isOwnStreamVideo = isOwnStreamVideo;
module.exports.isStreamVideoUid = isStreamVideoUid;
module.exports.buildDirectUploadBody = buildDirectUploadBody;
module.exports.streamPlaybackUrls = streamPlaybackUrls;
module.exports.encodeKeyPath = encodeKeyPath;
module.exports.canonicalQuery = canonicalQuery;
module.exports.amzDates = amzDates;
module.exports.sha256Hex = sha256Hex;
module.exports.signingKey = signingKey;
module.exports.readR2Config = readR2Config;
module.exports.readStreamConfig = readStreamConfig;
module.exports.httpRequest = httpRequest;

/// 이 모듈이 쓰는 시크릿 **파라미터 객체**들.
///
/// 값이 아니라 `defineSecret`이 돌려준 객체다 — 다른 모듈이 같은 이름으로 다시
/// 선언하지 않고 이것을 `secrets: [...]`에 그대로 펴 쓰라고 내보낸다
/// (`cloudflareCleanup.MEDIA_CLEANUP_SECRETS`). 이름이 두 곳에 적히면 한쪽만
/// 고쳐졌을 때 함수는 배포되지만 값이 안 실려 런타임에서야 드러난다.
module.exports.SECRET_PARAMS = {
  r2AccessKeyId,
  r2SecretAccessKey,
  r2PublicBaseUrl,
  cfAccountId,
  cfR2Bucket,
  cfStreamApiToken,
};

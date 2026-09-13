// ── Cloudflare 미디어 삭제 헬퍼 ──────────────────────────────────────────────
//
// 원래 index.js 안에만 있던 것을, 예약 삭제(deleteExpiredParties/Places)와
// 사용자가 직접 누르는 삭제(contentDelete.js)가 **같은 정리 코드**를 쓰도록
// 뽑아냈다. 미디어를 지우는 방식이 두 경로에서 갈라지면 한쪽만 고쳐지고
// 다른 쪽에는 고아 파일이 계속 쌓인다.
//
// 시크릿이 설정돼 있지 않으면 조용히 건너뛴다 — 미디어를 못 지웠다고 해서
// Firestore 삭제까지 실패시키면 사용자는 삭제 자체를 할 수 없게 된다.
//
// ── 자격증명이 바뀌었다 (CLOUDFLARE_API_TOKEN 폐기) ──────────────────────────
// 예전에는 계정 단위 통합 토큰 하나(CLOUDFLARE_API_TOKEN)로 Stream과 R2를 둘 다
// 지웠다. 그 토큰은 앱 `.env`에 평문으로 실려 배포됐던 것이라 유출로 간주해야
// 했고, 실제로 폐기돼 **운영에서 401로 실패하고 있었다**:
//
//   [contentDelete] Stream 삭제 실패 (…): HTTP 401 {"code":10000,"Authentication error"}
//   [contentDelete] R2 삭제 실패 (…): HTTP 401
//
// 삭제 헬퍼가 fail-open이라 Firestore 문서는 정상적으로 지워졌고, 아무도 모르게
// R2/Stream에 고아 파일만 쌓였다.
//
// 새 토큰을 다시 발급하는 대신 **업로드 경로가 이미 쓰고 있는 좁은 자격증명**을
// 그대로 나눠 쓴다([mediaUploads.js]):
//
//   R2     → R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY 로 SigV4 서명한 S3 DELETE
//            (버킷 하나로 스코프된 키다. `deleteOwnUpload`가 쓰는 그 경로·그 함수)
//   Stream → CLOUDFLARE_STREAM_API_TOKEN (Stream 전용. R2 권한이 아예 없다)
//
// 서명도 설정 읽기도 여기서 다시 구현하지 않는다 — `signedR2Request`,
// `readR2Config`, `readStreamConfig`를 그대로 가져다 쓴다. 두 벌이 되면 한쪽만
// 고쳐졌을 때 "업로드는 되는데 삭제만 조용히 실패"하는 상태가 된다.
//
// **정책은 하나도 바뀌지 않았다** — 무엇을 지우는지, 실패해도 Firestore 삭제를
// 막지 않는 fail-open, 호출부의 삭제 순서 전부 예전 그대로다. 바뀐 것은 같은
// DELETE를 어떤 자격증명으로 부르는가뿐이다.
// ─────────────────────────────────────────────────────────────────────────────

const https = require('https');

const {
  signedR2Request,
  readR2Config,
  readStreamConfig,
  SECRET_PARAMS,
} = require('./mediaUploads');

/// 이 헬퍼를 쓰는 함수가 `secrets:`에 그대로 펴 넣어야 하는 파라미터들.
///
/// 목록을 호출부마다 손으로 적으면 하나를 빠뜨렸을 때 배포는 성공하고 런타임에
/// 값만 비어 — 즉 **또 조용히 건너뛰는** 상태가 된다. 그래서 정본을 여기 하나만
/// 둔다. 여섯 모두 이미 존재하는 시크릿이고, 새로 만든 것은 없다.
const MEDIA_CLEANUP_SECRETS = [
  SECRET_PARAMS.r2AccessKeyId,
  SECRET_PARAMS.r2SecretAccessKey,
  SECRET_PARAMS.r2PublicBaseUrl,
  SECRET_PARAMS.cfAccountId,
  SECRET_PARAMS.cfR2Bucket,
  SECRET_PARAMS.cfStreamApiToken,
];

/// 상태 코드까지 돌려주는 요청 하나. 성공/실패 판정은 부르는 쪽이 한다 —
/// R2와 Stream이 "이미 없음"을 다르게 돌려주기 때문이다(각 함수 주석).
function httpsRequest({ hostname, path, method, headers = {} }) {
  return new Promise((resolve, reject) => {
    const req = https.request({ hostname, path, method, headers }, (res) => {
      let body = '';
      res.on('data', (c) => { body += c; });
      res.on('end', () => resolve({ statusCode: res.statusCode, body }));
    });
    req.on('error', reject);
    req.setTimeout(20000, () => req.destroy(new Error('timeout')));
    req.end();
  });
}

/// Bearer 토큰으로 지우는 DELETE — 지금 이걸 쓰는 것은 Stream 하나뿐이다.
/// 2xx가 아니면 던진다(호출부가 잡아 로그만 남기고 넘어간다).
function httpsDelete(hostname, path, token) {
  return httpsRequest({
    hostname,
    path,
    method: 'DELETE',
    headers: { Authorization: `Bearer ${token}` },
  }).then(({ statusCode, body }) => {
    if (statusCode === 200 || statusCode === 204) return;
    throw new Error(`HTTP ${statusCode}: ${String(body).slice(0, 200)}`);
  });
}

/// Stream 영상 하나 삭제 — [readStreamConfig]가 돌려준 설정을 그대로 받는다.
async function deleteStreamVideo(stream, uid) {
  await httpsDelete(
    'api.cloudflare.com',
    `/client/v4/accounts/${stream.accountId}/stream/${uid}`,
    stream.apiToken,
  );
}

/// R2 오브젝트 하나 삭제 — [readR2Config]가 돌려준 설정을 그대로 받는다.
///
/// 예전에는 api.cloudflare.com의 관리 API를 통합 토큰으로 불렀다. 지금은 버킷
/// 하나로 스코프된 S3 액세스 키로 R2의 S3 엔드포인트에 직접 서명해 보낸다 —
/// `deleteOwnUpload`(앱이 방금 올린 사진을 되돌릴 때)와 **같은 함수·같은 규칙**.
///
/// 404를 성공으로 보는 것도 그쪽과 같다. 삭제의 목적은 "없는 상태"이고, 이미
/// 지워진 키에 대고 매번 실패 로그를 남기면 진짜 실패가 그 속에 묻힌다.
async function deleteR2Object(r2, key) {
  const signed = signedR2Request({
    method: 'DELETE',
    accessKeyId: r2.accessKeyId,
    secretAccessKey: r2.secretAccessKey,
    accountId: r2.accountId,
    bucket: r2.bucket,
    key,
    nowMs: Date.now(),
  });
  const { statusCode, body } = await httpsRequest({
    hostname: signed.host,
    path: signed.path,
    method: 'DELETE',
    headers: signed.headers,
  });
  if (statusCode === 200 || statusCode === 204 || statusCode === 404) return;
  throw new Error(`HTTP ${statusCode}: ${String(body).slice(0, 200)}`);
}

/// 미디어 정리에 필요한 설정을 한 번에 읽는다. 둘 다 못 읽으면 null — 호출부는
/// null이면 미디어 정리를 건너뛰고 Firestore 삭제만 진행한다(예전과 같다).
///
/// **R2와 Stream을 따로 읽는 이유**: 한쪽 설정이 빠졌다고 다른 쪽까지 못 지울
/// 이유가 없다. 예전 구현도 r2Bucket만 비면 Stream은 계속 지웠다 — 그 갈래를
/// 그대로 유지한다.
///
/// [readR2Config]/[readStreamConfig]는 업로드 경로용이라 값이 없으면 **던진다**
/// (fail-closed — 새 경로가 구경로로 조용히 되돌아가지 못하게). 여기서는 그
/// 예외를 잡아 null로 바꾼다: 정리 경로의 정책은 예나 지금이나 fail-open이고,
/// 미디어를 못 지웠다고 사용자의 삭제 자체를 막으면 안 된다.
function readCloudflareCreds(logTag) {
  let r2 = null;
  let stream = null;
  try {
    r2 = readR2Config();
  } catch (_) {
    console.warn(`[${logTag}] R2 자격증명 미설정 — 사진 정리를 건너뜁니다.`);
  }
  try {
    stream = readStreamConfig();
  } catch (_) {
    console.warn(`[${logTag}] Stream 토큰 미설정 — 동영상 정리를 건너뜁니다.`);
  }
  if (!r2 && !stream) {
    console.warn(`[${logTag}] Cloudflare 시크릿 미설정 — Firestore만 삭제합니다.`);
    return null;
  }
  return { r2, stream };
}

/// 문서 하나가 들고 있는 사진·동영상을 모두 지운다.
///
/// [data]에서 [imageFields]에 해당하는 URL 배열과 videoUid/coverVideoUid를
/// 찾아 지운다. 개별 실패는 로그만 남기고 넘어간다 — 이미 지워졌거나 외부
/// URL인 경우가 흔한데, 그것 때문에 삭제 전체가 멈추면 안 된다.
async function deleteDocMedia(creds, data, logTag, imageFields) {
  if (!creds || !data) return;
  const { r2, stream } = creds;

  if (stream) {
    const videoUids = new Set(
      [data.videoUid, data.coverVideoUid].filter((v) => typeof v === 'string' && v),
    );
    for (const uid of videoUids) {
      try { await deleteStreamVideo(stream, uid); }
      catch (e) { console.error(`[${logTag}] Stream 삭제 실패 (${uid}):`, e.message); }
    }
  }

  if (!r2) return;
  const urls = new Set();
  for (const field of imageFields) {
    const value = data[field];
    if (Array.isArray(value)) {
      value.forEach((u) => { if (typeof u === 'string' && u) urls.add(u); });
    } else if (typeof value === 'string' && value) {
      urls.add(value);
    }
  }
  for (const url of urls) {
    try {
      const key = new URL(url).pathname.replace(/^\//, '');
      if (key) await deleteR2Object(r2, key);
    } catch (e) { console.error(`[${logTag}] R2 삭제 실패 (${url}):`, e.message); }
  }
}

module.exports = {
  MEDIA_CLEANUP_SECRETS,
  httpsRequest,
  httpsDelete,
  deleteStreamVideo,
  deleteR2Object,
  readCloudflareCreds,
  deleteDocMedia,
};

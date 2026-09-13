// 안전한 업로드 경로 자체 검증 — `node mediaUploads.selfcheck.js`.
//
// 이 경로가 지켜야 하는 약속은 하나다: **클라이언트가 무엇을 보내든, 자기
// 경로에 자기 파일만 쓰고 자기 파일만 지울 수 있다.** 앱 UI는 구버전 앱이나
// 콜러블 직접 호출로 통째로 우회되므로, 여기서 뚫리면 정책이 사라진다.
//
// 네트워크 없이 확인할 수 있도록 판정·서명 로직을 전부 순수 함수로 뽑아
// 두었다. 여기서 검증하는 것:
//
//   · 비로그인 차단
//   · uid 위조 불가 (클라이언트가 보낸 uid/key/path는 읽지도 않는다)
//   · 다른 사용자 경로 발급 불가
//   · folder whitelist
//   · 허용 확장자 / MIME 일치
//   · 용량 상한
//   · presigned URL이 다른 key·크기·형식에 재사용될 수 없음
//   · 만료 시간
//   · 남의 object 삭제 거부 / 자기 object 삭제 허용
//   · Stream 30초 제한
//   · 시크릿 누락 시 fail-closed

const assert = require('assert');
const crypto = require('crypto');

const M = require('./mediaUploads');

const cases = [];
const test = (name, fn) => cases.push([name, fn]);

/// HttpsError의 code는 'functions/permission-denied' 형태로 붙는다.
function expectThrows(fn, expectedCode) {
  try {
    fn();
  } catch (e) {
    if (expectedCode) {
      assert.ok(
        String(e.code).endsWith(expectedCode),
        `기대한 코드(${expectedCode})가 아니다: ${e.code} / ${e.message}`,
      );
    }
    return e;
  }
  throw new Error('막혔어야 하는데 통과했다');
}

const UID = 'alice0000000000000000000000';
const OTHER = 'mallory00000000000000000000';
const PUBLIC_BASE = 'https://pub-abc123.r2.dev';

const CREDS = {
  accessKeyId: 'AKIAEXAMPLE0000',
  secretAccessKey: 'secret-example-0000000000000000',
  accountId: 'acct123',
  bucket: 'partychu-images',
};

// 서명이 시각에 묶이므로 테스트는 고정 시각을 쓴다.
const NOW = Date.UTC(2026, 7, 22, 4, 15, 30);

// ══════════════════════════════════════════════════════════════════════════
// 비로그인 차단
// ══════════════════════════════════════════════════════════════════════════

test('비로그인 요청은 발급 자체가 막힌다', () => {
  expectThrows(() => M.requireUid({}), 'unauthenticated');
  expectThrows(() => M.requireUid({ auth: null }), 'unauthenticated');
  expectThrows(() => M.requireUid({ auth: {} }), 'unauthenticated');
  expectThrows(() => M.requireUid({ auth: { uid: '' } }), 'unauthenticated');
});

test('auth.uid가 있으면 그 값을 그대로 쓴다', () => {
  assert.strictEqual(M.requireUid({ auth: { uid: UID } }), UID);
});

test('data에 uid를 담아 보내도 인증 uid를 이긴다', () => {
  // 콜러블이 실제로 하는 것과 같은 순서: requireUid로 정본을 뽑고,
  // 그 값만 validateUploadRequest에 넘긴다.
  const request = {
    auth: { uid: UID },
    data: { uid: OTHER, kind: 'image', ext: 'jpg', contentLength: 1000 },
  };
  const uid = M.requireUid(request);
  const out = M.validateUploadRequest({
    uid,
    data: request.data,
    nowMs: NOW,
    nonce: 'aaaaaa',
  });
  assert.ok(
    out.key.startsWith(`party_images/${UID}/`),
    `인증 uid 경로여야 한다: ${out.key}`,
  );
  assert.ok(!out.key.includes(OTHER), '보내온 uid가 경로에 새면 안 된다');
});

// ══════════════════════════════════════════════════════════════════════════
// uid 위조 · 다른 사용자 경로
// ══════════════════════════════════════════════════════════════════════════

test('클라이언트가 key/path를 직접 지정해도 무시된다', () => {
  const out = M.validateUploadRequest({
    uid: UID,
    data: {
      kind: 'image',
      ext: 'png',
      contentLength: 500,
      key: `party_images/${OTHER}/pwned.png`,
      path: `party_images/${OTHER}/pwned.png`,
      objectKey: '../../etc/passwd',
    },
    nowMs: NOW,
    nonce: 'bbbbbb',
  });
  assert.strictEqual(out.key, `party_images/${UID}/${NOW}-bbbbbb.png`);
});

test('folder에 남의 uid를 붙여 보내면 거부된다', () => {
  for (const folder of [
    `party_images/${OTHER}`,
    'party_images/detail/../..',
    'party_images/',
    '/party_images',
    'party_images/detail/extra',
  ]) {
    expectThrows(
      () => M.resolveFolder({ folder }),
      'invalid-argument',
    );
  }
});

test('경로 탈출 문자가 섞인 folder는 거부된다', () => {
  for (const folder of ['../secrets', '..', 'party_images/..', 'a/../party_images']) {
    expectThrows(() => M.resolveFolder({ folder }), 'invalid-argument');
  }
});

test('경로에 쓸 수 없는 uid는 키를 만들지 않는다', () => {
  const target = M.FOLDERS.image;
  for (const bad of ['a/b', '..', '', 'a b', 'a/../b', 'x'.repeat(200), null, 42]) {
    expectThrows(
      () => M.buildObjectKey({ uid: bad, target, ext: 'jpg', nowMs: NOW, nonce: 'c' }),
      'permission-denied',
    );
  }
});

test('같은 밀리초에 두 번 발급해도 키가 겹치지 않는다', () => {
  const target = M.FOLDERS.image;
  const a = M.buildObjectKey({ uid: UID, target, ext: 'jpg', nowMs: NOW });
  const b = M.buildObjectKey({ uid: UID, target, ext: 'jpg', nowMs: NOW });
  assert.notStrictEqual(a, b, '난수 접미사가 붙어야 한다');
});

// ══════════════════════════════════════════════════════════════════════════
// folder whitelist
// ══════════════════════════════════════════════════════════════════════════

test('허용된 kind 두 가지만 통과한다', () => {
  assert.strictEqual(M.resolveFolder({ kind: 'image' }).folder, 'party_images');
  assert.strictEqual(
    M.resolveFolder({ kind: 'detailImage' }).folder,
    'party_images/detail',
  );
});

test('앱이 쓰는 folder 문자열도 같은 whitelist로 해석된다', () => {
  assert.strictEqual(M.resolveFolder({ folder: 'party_images' }).kind, 'image');
  assert.strictEqual(
    M.resolveFolder({ folder: 'party_images/detail' }).kind,
    'detailImage',
  );
});

test('표에 없는 kind/folder는 전부 거부된다', () => {
  for (const data of [
    {}, { kind: 'admin' }, { kind: '' }, { folder: 'uploads' },
    { folder: 'party_images/detail/detail' }, { kind: 'IMAGE' },
    { kind: 'toString' }, { folder: 'constructor' },
  ]) {
    expectThrows(() => M.resolveFolder(data), 'invalid-argument');
  }
});

test('프로토타입 상속 속성으로 whitelist를 뚫을 수 없다', () => {
  // hasOwnProperty로 확인하므로 'constructor'·'__proto__' 같은 이름이
  // 통과하지 않는다.
  expectThrows(() => M.resolveFolder({ kind: '__proto__' }), 'invalid-argument');
  expectThrows(() => M.resolveFolder({ kind: 'hasOwnProperty' }), 'invalid-argument');
});

// ══════════════════════════════════════════════════════════════════════════
// 확장자 / MIME
// ══════════════════════════════════════════════════════════════════════════

test('일반 이미지 폴더의 허용 확장자', () => {
  const target = M.FOLDERS.image;
  for (const ext of ['jpg', 'jpeg', 'png', 'webp', 'gif', 'heic']) {
    assert.strictEqual(M.resolveExtension(target, ext), ext);
  }
});

test('상세 이미지 폴더는 더 좁다 — gif·heic 불가', () => {
  const target = M.FOLDERS.detailImage;
  for (const ext of ['jpg', 'jpeg', 'png', 'webp']) {
    assert.strictEqual(M.resolveExtension(target, ext), ext);
  }
  for (const ext of ['gif', 'heic']) {
    expectThrows(() => M.resolveExtension(target, ext), 'invalid-argument');
  }
});

test('동영상·실행파일 확장자는 이미지 발급으로 통과하지 못한다', () => {
  const target = M.FOLDERS.image;
  for (const ext of ['mp4', 'mov', 'svg', 'html', 'js', 'php', 'exe', '']) {
    expectThrows(() => M.resolveExtension(target, ext), 'invalid-argument');
  }
});

test('대소문자·점·파일명 전체로 보내도 확장자만 정규화된다', () => {
  const target = M.FOLDERS.image;
  assert.strictEqual(M.resolveExtension(target, '.JPG'), 'jpg');
  assert.strictEqual(M.resolveExtension(target, 'PNG'), 'png');
  assert.strictEqual(M.resolveExtension(target, 'my.photo.WebP'), 'webp');
});

test('확장자 뒤에 경로를 붙여도 키에 새지 않는다', () => {
  const target = M.FOLDERS.image;
  // 'jpg/../../x' → 마지막 점 뒤만 남으므로 표에 없는 값이 되어 거부된다.
  expectThrows(() => M.resolveExtension(target, 'jpg/../../x'), 'invalid-argument');
});

test('contentType을 안 보내면 확장자에서 정본을 만든다', () => {
  assert.strictEqual(M.resolveContentType('jpg', undefined), 'image/jpeg');
  assert.strictEqual(M.resolveContentType('png', null), 'image/png');
  assert.strictEqual(M.resolveContentType('webp', ''), 'image/webp');
});

test('확장자와 다른 contentType은 거부된다', () => {
  expectThrows(() => M.resolveContentType('png', 'image/jpeg'), 'invalid-argument');
  expectThrows(() => M.resolveContentType('jpg', 'text/html'), 'invalid-argument');
  expectThrows(
    () => M.resolveContentType('png', 'application/octet-stream'),
    'invalid-argument',
  );
});

test('일치하는 contentType은 파라미터가 붙어 있어도 통과한다', () => {
  assert.strictEqual(
    M.resolveContentType('jpg', 'image/JPEG; charset=binary'),
    'image/jpeg',
  );
});

// ══════════════════════════════════════════════════════════════════════════
// 용량 상한
// ══════════════════════════════════════════════════════════════════════════

test('상세 이미지는 10MB, 일반 이미지는 20MB가 상한이다', () => {
  assert.strictEqual(M.FOLDERS.detailImage.maxBytes, 10 * 1024 * 1024);
  assert.strictEqual(M.FOLDERS.image.maxBytes, 20 * 1024 * 1024);
});

test('상한 이하는 통과, 1바이트만 넘어도 거부', () => {
  const target = M.FOLDERS.detailImage;
  assert.strictEqual(M.resolveContentLength(target, target.maxBytes), target.maxBytes);
  expectThrows(
    () => M.resolveContentLength(target, target.maxBytes + 1),
    'invalid-argument',
  );
});

test('0 · 음수 · 소수 · 문자열 · 누락은 거부된다', () => {
  const target = M.FOLDERS.image;
  for (const v of [0, -1, 1.5, '1000', null, undefined, NaN, Infinity]) {
    expectThrows(() => M.resolveContentLength(target, v), 'invalid-argument');
  }
});

test('상세 이미지 10MB 초과는 일반 폴더 상한과 무관하게 막힌다', () => {
  expectThrows(
    () => M.validateUploadRequest({
      uid: UID,
      data: { kind: 'detailImage', ext: 'jpg', contentLength: 15 * 1024 * 1024 },
      nowMs: NOW,
    }),
    'invalid-argument',
  );
});

// ══════════════════════════════════════════════════════════════════════════
// presigned URL — 재사용 불가 / 만료
// ══════════════════════════════════════════════════════════════════════════

/// URL이 스스로 담고 있는 경로·쿼리로 서명을 다시 계산한다.
/// 서명이 정말 "그 경로, 그 헤더"에 묶여 있는지 확인하는 독립 검산이다.
function recomputeSignature(urlString, { contentType, contentLength }) {
  const url = new URL(urlString);
  const query = {};
  for (const [k, v] of url.searchParams.entries()) {
    if (k !== 'X-Amz-Signature') query[k] = v;
  }
  const amzDate = query['X-Amz-Date'];
  const dateStamp = amzDate.slice(0, 8);
  const signedHeaders = query['X-Amz-SignedHeaders'];

  const canonicalHeaders =
    `content-length:${contentLength}\n` +
    `content-type:${contentType}\n` +
    `host:${url.host}\n`;

  const canonicalRequest = [
    'PUT',
    url.pathname,
    M.canonicalQuery(query),
    canonicalHeaders,
    signedHeaders,
    'UNSIGNED-PAYLOAD',
  ].join('\n');

  const stringToSign = [
    'AWS4-HMAC-SHA256',
    amzDate,
    `${dateStamp}/auto/s3/aws4_request`,
    M.sha256Hex(canonicalRequest),
  ].join('\n');

  return crypto
    .createHmac('sha256', M.signingKey(CREDS.secretAccessKey, dateStamp))
    .update(stringToSign, 'utf8')
    .digest('hex');
}

function presignFor(key, contentType = 'image/jpeg', contentLength = 12345) {
  return M.presignR2Put({
    ...CREDS,
    key,
    contentType,
    contentLength,
    nowMs: NOW,
  });
}

test('서명이 자기 URL로 검산된다(계산이 SigV4로 성립한다)', () => {
  const key = `party_images/${UID}/${NOW}-abc.jpg`;
  const out = presignFor(key);
  const actual = new URL(out.url).searchParams.get('X-Amz-Signature');
  assert.strictEqual(
    actual,
    recomputeSignature(out.url, { contentType: 'image/jpeg', contentLength: 12345 }),
  );
});

test('발급받은 URL을 다른 key로 바꿔치면 서명이 안 맞는다', () => {
  const mine = `party_images/${UID}/${NOW}-abc.jpg`;
  const victim = `party_images/${OTHER}/${NOW}-abc.jpg`;
  const out = presignFor(mine);

  const tampered = new URL(out.url);
  tampered.pathname = `/${CREDS.bucket}/${victim}`;

  const original = tampered.searchParams.get('X-Amz-Signature');
  const recomputed = recomputeSignature(tampered.toString(), {
    contentType: 'image/jpeg',
    contentLength: 12345,
  });
  assert.notStrictEqual(
    original,
    recomputed,
    '경로를 바꿨는데 서명이 그대로면 남의 경로에 쓸 수 있다',
  );
});

test('key마다 서명이 다르다 — 하나를 받아 다른 곳에 못 쓴다', () => {
  const a = presignFor(`party_images/${UID}/1-a.jpg`);
  const b = presignFor(`party_images/${UID}/1-b.jpg`);
  const sigA = new URL(a.url).searchParams.get('X-Amz-Signature');
  const sigB = new URL(b.url).searchParams.get('X-Amz-Signature');
  assert.notStrictEqual(sigA, sigB);
});

test('크기·형식이 서명에 묶여 있다 — 더 큰 파일/다른 타입으로 못 쓴다', () => {
  const key = `party_images/${UID}/1-a.jpg`;
  const base = presignFor(key, 'image/jpeg', 1000);
  const bigger = presignFor(key, 'image/jpeg', 99999999);
  const other = presignFor(key, 'image/png', 1000);

  const sig = (o) => new URL(o.url).searchParams.get('X-Amz-Signature');
  assert.notStrictEqual(sig(base), sig(bigger), '크기가 서명에 안 묶였다');
  assert.notStrictEqual(sig(base), sig(other), 'contentType이 서명에 안 묶였다');

  // 실제로 R2가 검사할 수 있도록 SignedHeaders에 둘 다 들어 있어야 한다.
  const signed = new URL(base.url).searchParams.get('X-Amz-SignedHeaders');
  assert.ok(signed.includes('content-length'), signed);
  assert.ok(signed.includes('content-type'), signed);
  assert.ok(signed.includes('host'), signed);
});

test('클라이언트가 반드시 보내야 하는 헤더를 함께 알려준다', () => {
  const out = presignFor(`party_images/${UID}/1-a.jpg`, 'image/png', 777);
  assert.strictEqual(out.requiredHeaders['Content-Type'], 'image/png');
  assert.strictEqual(out.requiredHeaders['Content-Length'], '777');
});

test('만료는 5분이고 URL에 그대로 박힌다', () => {
  assert.strictEqual(M.PRESIGN_TTL_SECONDS, 300);
  const out = presignFor(`party_images/${UID}/1-a.jpg`);
  const params = new URL(out.url).searchParams;
  assert.strictEqual(params.get('X-Amz-Expires'), '300');
  assert.strictEqual(out.expiresIn, 300);

  // 서명 시각도 함께 박혀 있어야 만료 판정이 성립한다.
  const { amzDate } = M.amzDates(NOW);
  assert.strictEqual(params.get('X-Amz-Date'), amzDate);
  assert.match(amzDate, /^\d{8}T\d{6}Z$/);
});

test('발급 시각이 다르면 서명도 다르다(재사용 창이 고정되지 않는다)', () => {
  const key = `party_images/${UID}/1-a.jpg`;
  const a = M.presignR2Put({ ...CREDS, key, contentType: 'image/jpeg', contentLength: 10, nowMs: NOW });
  const b = M.presignR2Put({ ...CREDS, key, contentType: 'image/jpeg', contentLength: 10, nowMs: NOW + 1000 });
  assert.notStrictEqual(a.url, b.url);
});

test('URL이 우리 계정의 S3 엔드포인트와 버킷을 가리킨다', () => {
  const key = `party_images/${UID}/1-a.jpg`;
  const url = new URL(presignFor(key).url);
  assert.strictEqual(url.host, `${CREDS.accountId}.r2.cloudflarestorage.com`);
  assert.strictEqual(url.pathname, `/${CREDS.bucket}/${key}`);
  // 비밀키는 URL 어디에도 나오면 안 된다.
  assert.ok(!url.toString().includes(CREDS.secretAccessKey), '비밀키가 URL에 샜다');
});

test('업로드 요청 → 서명까지 한 번에 통과하는 정상 경로', () => {
  const out = M.validateUploadRequest({
    uid: UID,
    data: {
      kind: 'detailImage',
      ext: 'png',
      contentType: 'image/png',
      contentLength: 3 * 1024 * 1024,
    },
    nowMs: NOW,
    nonce: 'deadbe',
  });
  assert.strictEqual(out.key, `party_images/detail/${UID}/${NOW}-deadbe.png`);
  assert.strictEqual(out.contentType, 'image/png');
  const presigned = M.presignR2Put({ ...CREDS, ...out, nowMs: NOW });
  assert.ok(presigned.url.includes(`/${CREDS.bucket}/party_images/detail/${UID}/`));
});

// ══════════════════════════════════════════════════════════════════════════
// 삭제 — 소유권
// ══════════════════════════════════════════════════════════════════════════

const ownUrl = `${PUBLIC_BASE}/party_images/${UID}/1700000000-aa.jpg`;
const ownDetailUrl = `${PUBLIC_BASE}/party_images/detail/${UID}/1700000000-aa.png`;
const otherUrl = `${PUBLIC_BASE}/party_images/${OTHER}/1700000000-aa.jpg`;

test('자기 object는 삭제할 수 있다', () => {
  assert.strictEqual(
    M.parseOwnedR2Key({ url: ownUrl, publicBase: PUBLIC_BASE, uid: UID }).key,
    `party_images/${UID}/1700000000-aa.jpg`,
  );
  assert.strictEqual(
    M.parseOwnedR2Key({ url: ownDetailUrl, publicBase: PUBLIC_BASE, uid: UID }).folder,
    'party_images/detail',
  );
});

test('공개 주소 끝에 슬래시가 있어도 같은 판정이다', () => {
  assert.ok(
    M.parseOwnedR2Key({ url: ownUrl, publicBase: `${PUBLIC_BASE}/`, uid: UID }).key,
  );
});

test('남의 object 삭제는 거부된다', () => {
  expectThrows(
    () => M.parseOwnedR2Key({ url: otherUrl, publicBase: PUBLIC_BASE, uid: UID }),
    'permission-denied',
  );
});

test('uid를 접두사로만 흉내낸 경로도 거부된다', () => {
  // 'alice...' 로 시작하지만 다른 uid인 경우 — 조각 전체가 같아야 한다.
  const lookalike = `${PUBLIC_BASE}/party_images/${UID}x/1-a.jpg`;
  expectThrows(
    () => M.parseOwnedR2Key({ url: lookalike, publicBase: PUBLIC_BASE, uid: UID }),
    'permission-denied',
  );
});

test('경로 탈출로 남의 폴더에 도달할 수 없다', () => {
  for (const key of [
    `party_images/${UID}/../${OTHER}/1-a.jpg`,
    `party_images/${UID}/..%2F..%2F${OTHER}%2F1-a.jpg`,
    `party_images/${UID}//1-a.jpg`,
    `party_images/${UID}/./1-a.jpg`,
    `party_images/${UID}/sub/1-a.jpg`,
    `party_images/${UID}`,
    `party_images/${UID}/`,
  ]) {
    expectThrows(
      () => M.parseOwnedR2Key({
        url: `${PUBLIC_BASE}/${key}`,
        publicBase: PUBLIC_BASE,
        uid: UID,
      }),
      'permission-denied',
    );
  }
});

test('허용 폴더 밖의 키는 자기 uid가 붙어 있어도 거부된다', () => {
  for (const key of [
    `secrets/${UID}/1-a.jpg`,
    `${UID}/1-a.jpg`,
    `party_imagesX/${UID}/1-a.jpg`,
  ]) {
    expectThrows(
      () => M.parseOwnedR2Key({
        url: `${PUBLIC_BASE}/${key}`,
        publicBase: PUBLIC_BASE,
        uid: UID,
      }),
      'permission-denied',
    );
  }
});

test('우리 버킷이 아닌 주소는 전부 거부된다 — 임의 Cloudflare URL 포함', () => {
  for (const url of [
    `https://pub-attacker.r2.dev/party_images/${UID}/1-a.jpg`,
    // 접두사만 같은 다른 호스트(경계 검사가 없으면 통과해버린다)
    `${PUBLIC_BASE}.evil.com/party_images/${UID}/1-a.jpg`,
    `https://api.cloudflare.com/client/v4/accounts/x/r2/buckets/y/objects/z`,
    `https://videodelivery.net/abcdef/manifest/video.m3u8`,
    `http://pub-abc123.r2.dev/party_images/${UID}/1-a.jpg`, // http
    `${PUBLIC_BASE}`,
    `${PUBLIC_BASE}/`,
    '',
    'not a url',
  ]) {
    expectThrows(
      () => M.parseOwnedR2Key({ url, publicBase: PUBLIC_BASE, uid: UID }),
      undefined,
    );
  }
});

test('쿼리/프래그먼트를 붙여 판정을 흐릴 수 없다', () => {
  // 자기 것 뒤에 쿼리가 붙으면 잘라내고 자기 키로 본다.
  assert.strictEqual(
    M.parseOwnedR2Key({
      url: `${ownUrl}?x=1#y`,
      publicBase: PUBLIC_BASE,
      uid: UID,
    }).key,
    `party_images/${UID}/1700000000-aa.jpg`,
  );
  // 남의 것에 쿼리를 붙여도 여전히 거부된다.
  expectThrows(
    () => M.parseOwnedR2Key({
      url: `${otherUrl}?ignore=${UID}`,
      publicBase: PUBLIC_BASE,
      uid: UID,
    }),
    'permission-denied',
  );
});

test('공개 주소 설정이 비어 있으면 삭제가 막힌다(fail-closed)', () => {
  expectThrows(
    () => M.parseOwnedR2Key({ url: ownUrl, publicBase: '', uid: UID }),
    'failed-precondition',
  );
});

// ══════════════════════════════════════════════════════════════════════════
// 삭제 — 동영상 소유권
// ══════════════════════════════════════════════════════════════════════════

test('자기 동영상(creator 일치)은 삭제할 수 있다', () => {
  assert.strictEqual(M.isOwnStreamVideo({ creator: UID }, UID), true);
  assert.strictEqual(M.isOwnStreamVideo({ meta: { uid: UID } }, UID), true);
  assert.strictEqual(
    M.isOwnStreamVideo({ creator: UID, meta: { uid: UID } }, UID),
    true,
  );
});

test('남의 동영상은 거부된다', () => {
  assert.strictEqual(M.isOwnStreamVideo({ creator: OTHER }, UID), false);
  assert.strictEqual(M.isOwnStreamVideo({ meta: { uid: OTHER } }, UID), false);
  // 한쪽만 맞아도 안 된다 — 둘 다 어긋나지 않아야 통과한다.
  assert.strictEqual(
    M.isOwnStreamVideo({ creator: UID, meta: { uid: OTHER } }, UID),
    false,
  );
});

test('소유자를 알 수 없는 동영상은 삭제하지 않는다(구경로 업로드분)', () => {
  assert.strictEqual(M.isOwnStreamVideo({}, UID), false);
  assert.strictEqual(M.isOwnStreamVideo({ creator: '' }, UID), false);
  assert.strictEqual(M.isOwnStreamVideo({ meta: {} }, UID), false);
  assert.strictEqual(M.isOwnStreamVideo(null, UID), false);
  assert.strictEqual(M.isOwnStreamVideo({ creator: UID }, ''), false);
});

test('Stream 식별자 모양이 아니면 API를 부르기 전에 막는다', () => {
  assert.strictEqual(M.isStreamVideoUid('a'.repeat(32)), true);
  for (const bad of [
    '', 'abc', 'A'.repeat(32), 'g'.repeat(32), 'a'.repeat(31), 'a'.repeat(33),
    '../../etc', null, 42,
  ]) {
    assert.strictEqual(M.isStreamVideoUid(bad), false, String(bad));
  }
});

// ══════════════════════════════════════════════════════════════════════════
// Stream 30초 제한
// ══════════════════════════════════════════════════════════════════════════

test('동영상 업로드 요청에 30초 제한이 서버에서 박힌다', () => {
  const body = M.buildDirectUploadBody({ uid: UID, nowMs: NOW });
  assert.strictEqual(body.maxDurationSeconds, 30);
  assert.strictEqual(M.STREAM_MAX_DURATION_SECONDS, 30);
});

test('동영상 업로드 요청에 소유자와 만료가 함께 들어간다', () => {
  const body = M.buildDirectUploadBody({ uid: UID, nowMs: NOW });
  assert.strictEqual(body.creator, UID);
  assert.strictEqual(body.meta.uid, UID);
  assert.strictEqual(body.requireSignedURLs, false);
  assert.strictEqual(
    body.expiry,
    new Date(NOW + M.STREAM_UPLOAD_TTL_SECONDS * 1000).toISOString(),
  );
  // Cloudflare가 허용하는 범위(2분~6시간) 안이어야 한다.
  assert.ok(M.STREAM_UPLOAD_TTL_SECONDS >= 120);
  assert.ok(M.STREAM_UPLOAD_TTL_SECONDS <= 6 * 3600);
});

test('경로에 쓸 수 없는 uid로는 동영상 업로드도 시작할 수 없다', () => {
  expectThrows(
    () => M.buildDirectUploadBody({ uid: 'a/b', nowMs: NOW }),
    'permission-denied',
  );
});

test('재생/썸네일 주소가 구경로와 같은 형식이다', () => {
  const uid = 'a'.repeat(32);
  const urls = M.streamPlaybackUrls(uid);
  assert.strictEqual(urls.videoUrl, `https://videodelivery.net/${uid}/manifest/video.m3u8`);
  assert.strictEqual(
    urls.videoThumbnailUrl,
    `https://videodelivery.net/${uid}/thumbnails/thumbnail.jpg`,
  );
});

// ══════════════════════════════════════════════════════════════════════════
// fail-closed — 시크릿이 없으면 아무것도 발급하지 않는다
// ══════════════════════════════════════════════════════════════════════════

const R2_SECRET_NAMES = [
  'R2_ACCESS_KEY_ID', 'R2_SECRET_ACCESS_KEY', 'R2_PUBLIC_BASE_URL',
  'CLOUDFLARE_ACCOUNT_ID', 'CLOUDFLARE_R2_BUCKET',
];
const STREAM_SECRET_NAMES = ['CLOUDFLARE_STREAM_API_TOKEN', 'CLOUDFLARE_ACCOUNT_ID'];

/// 시크릿 환경변수를 원하는 상태로 만들어 fn을 돌리고 반드시 원상복구한다.
function withSecrets(values, fn) {
  const names = [...new Set([...R2_SECRET_NAMES, ...STREAM_SECRET_NAMES])];
  const saved = {};
  for (const n of names) saved[n] = process.env[n];
  try {
    for (const n of names) delete process.env[n];
    for (const [k, v] of Object.entries(values)) process.env[k] = v;
    return fn();
  } finally {
    for (const n of names) {
      if (saved[n] === undefined) delete process.env[n];
      else process.env[n] = saved[n];
    }
  }
}

test('시크릿이 하나도 없으면 사진 발급이 막힌다', () => {
  withSecrets({}, () => {
    expectThrows(() => M.readR2Config(), 'failed-precondition');
  });
});

test('시크릿이 하나만 빠져도 막힌다 — 부분 설정으로 새지 않는다', () => {
  for (const omit of R2_SECRET_NAMES) {
    const values = {};
    for (const n of R2_SECRET_NAMES) if (n !== omit) values[n] = 'x';
    withSecrets(values, () => {
      expectThrows(() => M.readR2Config(), 'failed-precondition');
    });
  }
});

test('공백만 든 시크릿도 "없음"으로 본다', () => {
  const values = {};
  for (const n of R2_SECRET_NAMES) values[n] = 'x';
  values.R2_SECRET_ACCESS_KEY = '   ';
  withSecrets(values, () => {
    expectThrows(() => M.readR2Config(), 'failed-precondition');
  });
});

test('시크릿이 다 있으면 읽히고, 공개 주소 끝 슬래시는 정리된다', () => {
  const values = {};
  for (const n of R2_SECRET_NAMES) values[n] = 'x';
  values.R2_PUBLIC_BASE_URL = 'https://pub-abc.r2.dev/';
  withSecrets(values, () => {
    const cfg = M.readR2Config();
    assert.strictEqual(cfg.publicBase, 'https://pub-abc.r2.dev');
    assert.strictEqual(cfg.accessKeyId, 'x');
  });
});

test('Stream 토큰이 없으면 동영상 발급이 막힌다', () => {
  withSecrets({ CLOUDFLARE_ACCOUNT_ID: 'a' }, () => {
    expectThrows(() => M.readStreamConfig(), 'failed-precondition');
  });
});

test('설정이 없다고 구경로 토큰으로 되돌아가지 않는다', () => {
  // 기존 토큰만 있는 상태 — 새 경로는 그래도 막혀야 한다.
  withSecrets({ CLOUDFLARE_API_TOKEN: 'legacy-token', CLOUDFLARE_ACCOUNT_ID: 'a' }, () => {
    expectThrows(() => M.readR2Config(), 'failed-precondition');
    expectThrows(() => M.readStreamConfig(), 'failed-precondition');
  });
});

// ══════════════════════════════════════════════════════════════════════════
// 구경로와의 관계 — 이번 단계는 "추가만" 이다
// ══════════════════════════════════════════════════════════════════════════

test('구경로 토큰(CLOUDFLARE_API_TOKEN)을 참조하지 않는다', () => {
  const src = require('fs').readFileSync(require.resolve('./mediaUploads'), 'utf8');
  // 주석에서 이유를 설명하는 것은 허용하되, defineSecret으로 잡으면 안 된다.
  assert.ok(
    !/defineSecret\(\s*['"]CLOUDFLARE_API_TOKEN['"]\s*\)/.test(src),
    '새 경로가 유출된 것으로 간주되는 기존 토큰을 다시 쓰면 안 된다',
  );
  assert.ok(
    /defineSecret\(\s*['"]R2_ACCESS_KEY_ID['"]\s*\)/.test(src),
    '전용 R2 액세스 키를 써야 한다',
  );
  assert.ok(
    /defineSecret\(\s*['"]CLOUDFLARE_STREAM_API_TOKEN['"]\s*\)/.test(src),
    'Stream 전용 토큰을 따로 써야 한다',
  );
});

test('구경로(cloudflareCleanup·contentCleanup)는 그대로 남아 있다', () => {
  const cleanup = require('./cloudflareCleanup');
  assert.ok(typeof cleanup.deleteDocMedia === 'function');
  assert.ok(typeof cleanup.readCloudflareCreds === 'function');
  const cc = require('./contentCleanup');
  assert.ok(cc.TYPES && cc.TYPES.party, '콘텐츠 삭제 경로가 살아 있어야 한다');
});

test('저장 폴더가 앱의 상세 이미지 폴더와 정확히 같다', () => {
  // party_app/lib/models/party_detail_image.dart의 storageFolder와 어긋나면
  // 전환 후 상세 이미지가 다른 곳에 쌓인다.
  const fs = require('fs');
  // 실행 위치와 무관하게 찾도록 이 파일 기준으로 잡는다.
  const target = require('path').join(
    __dirname, '..', 'party_app', 'lib', 'models', 'party_detail_image.dart',
  );
  if (!fs.existsSync(target)) {
    console.log('    (앱 소스 없음 — 건너뜀)');
    return;
  }
  const src = fs.readFileSync(target, 'utf8');
  const m = /storageFolder\s*=\s*'([^']+)'/.exec(src);
  assert.ok(m, 'storageFolder를 찾지 못했다');
  assert.strictEqual(m[1], M.FOLDERS.detailImage.folder);
});

// ══════════════════════════════════════════════════════════════════════════

(async () => {
  let failed = 0;
  for (const [name, fn] of cases) {
    try {
      await fn();
      console.log(`  ✓ ${name}`);
    } catch (e) {
      failed += 1;
      console.error(`  ✗ ${name}\n    ${e.message}`);
    }
  }
  console.log(
    failed === 0
      ? `\n안전한 업로드 경로 ${cases.length}건 통과`
      : `\n${failed}건 실패`,
  );
  process.exit(failed === 0 ? 0 : 1);
})();

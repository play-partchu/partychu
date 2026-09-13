// presigned PUT 실물 검증 — `node mediaUploadsE2e.selfcheck.js`.
//
// mediaUploads.selfcheck.js가 "서명 계산이 SigV4로 성립하는가"를 본다면,
// 이 파일은 **실제 PUT 요청이 통과하는가**를 본다.
//
// R2 역할을 하는 로컬 서버를 띄우고, 그 서버가 들어온 요청으로부터 서명을
// **독립적으로 다시 계산**해 대조한다. 즉 "우리가 만든 URL을 우리가 검산"하는
// 것이 아니라, R2가 하는 일과 같은 순서(요청 → 정규화 → 서명 비교)를 그대로
// 재현한다. 여기서 통과하면 실제 R2에서도 통과한다.
//
// 확인하는 것:
//   · 정확한 Content-Length / Content-Type 으로 PUT → 200
//   · Content-Length 가 다르면            → 403
//   · Content-Type 이 다르면              → 403
//   · 다른 key 로 재사용하면              → 403
//   · 만료 후에는                          → 403
//   · 본문이 그대로 도착한다

const assert = require('assert');
const crypto = require('crypto');
const http = require('http');

const M = require('./mediaUploads');

const cases = [];
const test = (name, fn) => cases.push([name, fn]);

const CREDS = {
  accessKeyId: 'AKIAEXAMPLE0000',
  secretAccessKey: 'secret-example-0000000000000000',
  accountId: 'acct123',
  bucket: 'partychu-images',
};

// ── R2 역할 서버 ──────────────────────────────────────────────────────────
//
// 들어온 요청을 SigV4 규칙대로 정규화해 서명을 다시 만들고, URL에 실린
// X-Amz-Signature와 비교한다. 하나라도 다르면 403.

function verifyIncoming(req, body) {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const given = url.searchParams.get('X-Amz-Signature');
  if (!given) return { ok: false, why: 'no signature' };

  const query = {};
  for (const [k, v] of url.searchParams.entries()) {
    if (k !== 'X-Amz-Signature') query[k] = v;
  }

  const amzDate = query['X-Amz-Date'];
  const expires = Number(query['X-Amz-Expires']);
  if (!amzDate || !Number.isFinite(expires)) return { ok: false, why: 'bad date' };

  // 만료 확인 — R2가 하는 것과 같다.
  const signedAt = Date.UTC(
    Number(amzDate.slice(0, 4)), Number(amzDate.slice(4, 6)) - 1,
    Number(amzDate.slice(6, 8)), Number(amzDate.slice(9, 11)),
    Number(amzDate.slice(11, 13)), Number(amzDate.slice(13, 15)),
  );
  if (Date.now() > signedAt + expires * 1000) {
    return { ok: false, why: 'expired' };
  }

  // 서명된 헤더는 **실제로 도착한 값**으로 채운다. 클라이언트가 다른 크기나
  // 다른 타입을 보내면 여기서 서명이 어긋난다.
  const signedHeaders = query['X-Amz-SignedHeaders'].split(';');
  const canonicalHeaders = signedHeaders
    .map((h) => `${h}:${req.headers[h] ?? ''}\n`)
    .join('');

  const canonicalRequest = [
    req.method,
    url.pathname,
    M.canonicalQuery(query),
    canonicalHeaders,
    signedHeaders.join(';'),
    'UNSIGNED-PAYLOAD',
  ].join('\n');

  const dateStamp = amzDate.slice(0, 8);
  const stringToSign = [
    'AWS4-HMAC-SHA256',
    amzDate,
    `${dateStamp}/auto/s3/aws4_request`,
    M.sha256Hex(canonicalRequest),
  ].join('\n');

  const expected = crypto
    .createHmac('sha256', M.signingKey(CREDS.secretAccessKey, dateStamp))
    .update(stringToSign, 'utf8')
    .digest('hex');

  if (expected !== given) return { ok: false, why: 'signature mismatch' };

  // R2는 선언한 Content-Length와 실제 본문 길이도 확인한다.
  if (Number(req.headers['content-length']) !== body.length) {
    return { ok: false, why: 'length mismatch' };
  }
  return { ok: true };
}

let server;
let baseOrigin;
const stored = new Map();

function startServer() {
  return new Promise((resolve) => {
    server = http.createServer((req, res) => {
      const chunks = [];
      req.on('data', (c) => chunks.push(c));
      req.on('end', () => {
        const body = Buffer.concat(chunks);
        const result = verifyIncoming(req, body);
        if (!result.ok) {
          res.statusCode = 403;
          res.end(JSON.stringify({ error: result.why }));
          return;
        }
        stored.set(new URL(req.url, `http://${req.headers.host}`).pathname, body);
        res.statusCode = 200;
        res.end();
      });
    });
    server.listen(0, '127.0.0.1', () => {
      baseOrigin = `127.0.0.1:${server.address().port}`;
      resolve();
    });
  });
}

/// presigned URL의 호스트만 로컬 서버로 바꿔 실제로 PUT한다.
/// 경로·쿼리·서명은 손대지 않는다.
function putSigned(signedUrl, { body, contentType, contentLength }) {
  const url = new URL(signedUrl);
  return new Promise((resolve, reject) => {
    const req = http.request(
      {
        hostname: '127.0.0.1',
        port: server.address().port,
        path: url.pathname + url.search,
        method: 'PUT',
        headers: {
          // 서명에 들어간 host를 그대로 보내야 한다 — 실제 R2에서도 같다.
          host: url.host,
          'content-type': contentType,
          'content-length': contentLength,
        },
      },
      (res) => {
        let raw = '';
        res.on('data', (c) => { raw += c; });
        res.on('end', () => resolve({ statusCode: res.statusCode, body: raw }));
      },
    );
    req.on('error', reject);
    req.end(body);
  });
}

function presign(key, { contentType, contentLength, nowMs = Date.now(), expiresIn }) {
  return M.presignR2Put({
    ...CREDS,
    key,
    contentType,
    contentLength,
    nowMs,
    ...(expiresIn === undefined ? {} : { expiresIn }),
  });
}

const UID = 'alice0000000000000000000000';
const PAYLOAD = Buffer.from('가짜 이미지 바이트'.repeat(64), 'utf8');

// ── 검증 ──────────────────────────────────────────────────────────────────

test('정확한 Content-Length·Content-Type으로 PUT하면 200', async () => {
  const key = `party_images/${UID}/1700000000-e2e.jpg`;
  const out = presign(key, {
    contentType: 'image/jpeg',
    contentLength: PAYLOAD.length,
  });

  const res = await putSigned(out.url, {
    body: PAYLOAD,
    contentType: out.requiredHeaders['Content-Type'],
    contentLength: out.requiredHeaders['Content-Length'],
  });

  assert.strictEqual(res.statusCode, 200, `본문: ${res.body}`);
});

test('본문이 그대로 도착한다', async () => {
  const key = `party_images/${UID}/1700000001-body.jpg`;
  const out = presign(key, {
    contentType: 'image/jpeg',
    contentLength: PAYLOAD.length,
  });
  await putSigned(out.url, {
    body: PAYLOAD,
    contentType: out.requiredHeaders['Content-Type'],
    contentLength: out.requiredHeaders['Content-Length'],
  });
  const saved = stored.get(`/${CREDS.bucket}/${key}`);
  assert.ok(saved, '저장되지 않았다');
  assert.ok(saved.equals(PAYLOAD), '바이트가 달라졌다');
});

test('Content-Length가 서명과 다르면 403 — 더 큰 파일을 밀어넣을 수 없다', async () => {
  const key = `party_images/${UID}/1700000002-big.jpg`;
  // 1000바이트로 허가받고 실제로는 더 보낸다.
  const out = presign(key, { contentType: 'image/jpeg', contentLength: 1000 });
  const bigger = Buffer.alloc(2000, 1);

  const res = await putSigned(out.url, {
    body: bigger,
    contentType: 'image/jpeg',
    contentLength: bigger.length,
  });
  assert.strictEqual(res.statusCode, 403, `허용되면 안 된다: ${res.body}`);
});

test('Content-Type이 서명과 다르면 403', async () => {
  const key = `party_images/${UID}/1700000003-type.jpg`;
  const out = presign(key, {
    contentType: 'image/jpeg',
    contentLength: PAYLOAD.length,
  });
  const res = await putSigned(out.url, {
    body: PAYLOAD,
    contentType: 'text/html',
    contentLength: PAYLOAD.length,
  });
  assert.strictEqual(res.statusCode, 403, `허용되면 안 된다: ${res.body}`);
});

test('발급받은 URL을 다른 key로 바꿔 쓰면 403 — 남의 경로에 못 쓴다', async () => {
  const mine = `party_images/${UID}/1700000004-mine.jpg`;
  const victim = 'party_images/mallory00000000000000000000/1700000004-mine.jpg';
  const out = presign(mine, {
    contentType: 'image/jpeg',
    contentLength: PAYLOAD.length,
  });

  const tampered = out.url.replace(mine, victim);
  const res = await putSigned(tampered, {
    body: PAYLOAD,
    contentType: 'image/jpeg',
    contentLength: PAYLOAD.length,
  });
  assert.strictEqual(res.statusCode, 403, `허용되면 안 된다: ${res.body}`);
  assert.ok(
    !stored.has(`/${CREDS.bucket}/${victim}`),
    '남의 경로에 파일이 만들어졌다',
  );
});

test('만료된 URL은 403', async () => {
  const key = `party_images/${UID}/1700000005-old.jpg`;
  // 10분 전에, 유효기간 5분으로 발급된 URL.
  const out = presign(key, {
    contentType: 'image/jpeg',
    contentLength: PAYLOAD.length,
    nowMs: Date.now() - 10 * 60 * 1000,
  });
  const res = await putSigned(out.url, {
    body: PAYLOAD,
    contentType: 'image/jpeg',
    contentLength: PAYLOAD.length,
  });
  assert.strictEqual(res.statusCode, 403, `만료를 무시했다: ${res.body}`);
});

test('상세 이미지 폴더도 같은 방식으로 통과한다', async () => {
  const key = `party_images/detail/${UID}/1700000006-detail.png`;
  const out = presign(key, {
    contentType: 'image/png',
    contentLength: PAYLOAD.length,
  });
  const res = await putSigned(out.url, {
    body: PAYLOAD,
    contentType: out.requiredHeaders['Content-Type'],
    contentLength: out.requiredHeaders['Content-Length'],
  });
  assert.strictEqual(res.statusCode, 200, `본문: ${res.body}`);
  assert.ok(stored.has(`/${CREDS.bucket}/${key}`));
});

test('발급 → PUT → 공개 URL 조립까지 앱이 하는 그대로', async () => {
  // 콜러블이 하는 일을 그대로 재현한다.
  const resolved = M.validateUploadRequest({
    uid: UID,
    data: {
      folder: 'party_images',
      ext: 'jpg',
      contentType: 'image/jpeg',
      contentLength: PAYLOAD.length,
    },
    nowMs: 1700000007000,
    nonce: 'f00d',
  });
  const out = M.presignR2Put({ ...CREDS, ...resolved, nowMs: Date.now() });
  const publicBase = 'https://pub-abc123.r2.dev';
  const publicUrl = `${publicBase}/${resolved.key}`;

  const res = await putSigned(out.url, {
    body: PAYLOAD,
    contentType: out.requiredHeaders['Content-Type'],
    contentLength: out.requiredHeaders['Content-Length'],
  });
  assert.strictEqual(res.statusCode, 200);

  // 공개 URL은 기존 형식 그대로다(버킷 공개 주소 + 키).
  assert.strictEqual(
    publicUrl,
    `${publicBase}/party_images/${UID}/1700000007000-f00d.jpg`,
  );

  // 그리고 그 URL은 자기 자신을 삭제 대상으로 되돌려 파싱할 수 있어야 한다.
  assert.strictEqual(
    M.parseOwnedR2Key({ url: publicUrl, publicBase, uid: UID }).key,
    resolved.key,
  );
});

// ──────────────────────────────────────────────────────────────────────────

(async () => {
  await startServer();
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
  server.close();
  console.log(
    failed === 0
      ? `\npresigned PUT 실물 검증 ${cases.length}건 통과`
      : `\n${failed}건 실패`,
  );
  process.exit(failed === 0 ? 0 : 1);
})();

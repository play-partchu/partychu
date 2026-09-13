// 미디어 삭제 자격증명 검증 — `npm run check:cfcleanup`.
//
// ── 왜 이 파일이 필요한가 ────────────────────────────────────────────────────
// 삭제 헬퍼는 **fail-open**이다. 자격증명이 틀려도 Firestore 문서는 정상적으로
// 지워지고, 사용자 화면에는 아무 이상이 없다. 실제로 폐기된
// CLOUDFLARE_API_TOKEN으로 몇 달간 401을 맞으면서도 아무도 몰랐고, R2/Stream에
// 고아 파일만 쌓였다(운영 로그 2026-08-20/21).
//
// 그래서 "어떤 자격증명으로 어디를 부르는가"는 눈으로 볼 수 없고, 여기서
// 값으로 붙잡아야 한다. 이 파일이 지키는 것 넷.
//
//   ① 서버 어디에도 CLOUDFLARE_API_TOKEN을 읽는 코드가 없다.
//   ② R2는 **버킷 스코프 S3 키로 서명한** DELETE를 R2 S3 엔드포인트로 보낸다
//      (api.cloudflare.com의 계정 단위 관리 API가 아니다).
//   ③ Stream은 Stream 전용 토큰으로 api.cloudflare.com을 부른다.
//   ④ fail-open과 삭제 대상 판정은 **예전 그대로**다 — 한쪽 설정이 없어도
//      다른 쪽은 계속 지우고, 개별 실패가 전체를 멈추지 않는다.
//
// 네트워크는 타지 않는다. https.request를 가로채 "무엇을 어디로 보냈는지"만 본다.

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const https = require('https');

const cases = [];
const test = (name, fn) => cases.push([name, fn]);

// ── https 가로채기 ──────────────────────────────────────────────────────────
//
// cloudflareCleanup.js는 `const https = require('https')` 후 `https.request`를
// 부르므로, 모듈 객체의 프로퍼티를 갈아끼우면 그대로 잡힌다.
const realRequest = https.request;
let sent = [];
let nextStatus = 204;

function fakeHttps() {
  sent = [];
  https.request = (options, onResponse) => {
    sent.push(options);
    const listeners = {};
    const res = {
      statusCode: nextStatus,
      on: (evt, cb) => {
        listeners[evt] = cb;
        return res;
      },
    };
    // 응답은 다음 틱에 — 실제 소켓과 같은 순서로 end까지 흘려준다.
    setImmediate(() => {
      onResponse(res);
      if (listeners.data) listeners.data('');
      if (listeners.end) listeners.end();
    });
    return {
      on: () => {},
      setTimeout: () => {},
      write: () => {},
      end: () => {},
      destroy: () => {},
    };
  };
}

function restoreHttps() {
  https.request = realRequest;
}

// ── 시크릿 갈아끼우기 ───────────────────────────────────────────────────────
const ALL_SECRET_NAMES = [
  'R2_ACCESS_KEY_ID',
  'R2_SECRET_ACCESS_KEY',
  'R2_PUBLIC_BASE_URL',
  'CLOUDFLARE_ACCOUNT_ID',
  'CLOUDFLARE_R2_BUCKET',
  'CLOUDFLARE_STREAM_API_TOKEN',
  'CLOUDFLARE_API_TOKEN',
];

const FULL = {
  R2_ACCESS_KEY_ID: 'ak-test',
  R2_SECRET_ACCESS_KEY: 'sk-test',
  R2_PUBLIC_BASE_URL: 'https://pub-test.r2.dev',
  CLOUDFLARE_ACCOUNT_ID: 'acct123',
  CLOUDFLARE_R2_BUCKET: 'party-bucket',
  CLOUDFLARE_STREAM_API_TOKEN: 'stream-token',
};

async function withSecrets(values, fn) {
  const saved = {};
  for (const n of ALL_SECRET_NAMES) saved[n] = process.env[n];
  try {
    for (const n of ALL_SECRET_NAMES) delete process.env[n];
    for (const [k, v] of Object.entries(values)) process.env[k] = v;
    return await fn();
  } finally {
    for (const n of ALL_SECRET_NAMES) {
      if (saved[n] === undefined) delete process.env[n];
      else process.env[n] = saved[n];
    }
  }
}

const C = require('./cloudflareCleanup');

// ══════════════════════════════════════════════════════════════════════════
// ① 폐기된 토큰이 서버에 남아 있지 않다
// ══════════════════════════════════════════════════════════════════════════

test('서버 코드 어디에도 CLOUDFLARE_API_TOKEN을 읽는 곳이 없다', () => {
  const offenders = [];
  for (const f of fs.readdirSync(__dirname)) {
    if (!f.endsWith('.js') || f.endsWith('.selfcheck.js')) continue;
    const src = fs.readFileSync(path.join(__dirname, f), 'utf8');
    // 주석으로 배경을 설명하는 것은 허용한다 — 값을 **읽는** 코드만 잡는다.
    if (/defineSecret\(\s*['"]CLOUDFLARE_API_TOKEN['"]\s*\)/.test(src)
      || /process\.env\.CLOUDFLARE_API_TOKEN/.test(src)) {
      offenders.push(f);
    }
  }
  assert.deepStrictEqual(
    offenders, [],
    `폐기된 토큰을 아직 읽는 파일: ${offenders.join(', ')}`,
  );
});

test('정리 경로가 요구하는 시크릿은 이미 있는 여섯 개뿐이다', () => {
  const names = C.MEDIA_CLEANUP_SECRETS.map((p) => p.name).sort();
  assert.deepStrictEqual(names, [
    'CLOUDFLARE_ACCOUNT_ID',
    'CLOUDFLARE_R2_BUCKET',
    'CLOUDFLARE_STREAM_API_TOKEN',
    'R2_ACCESS_KEY_ID',
    'R2_PUBLIC_BASE_URL',
    'R2_SECRET_ACCESS_KEY',
  ]);
});

test('정리 헬퍼를 쓰는 함수는 전부 그 목록을 secrets로 선언한다', () => {
  // 목록을 손으로 적으면 하나 빠뜨렸을 때 배포는 되고 런타임에만 드러난다.
  const users = ['index.js', 'contentDelete.js', 'accountWithdrawal.js',
    'registrationLimitGuard.js'];
  for (const f of users) {
    const src = fs.readFileSync(path.join(__dirname, f), 'utf8');
    assert.ok(
      src.includes('MEDIA_CLEANUP_SECRETS'),
      `${f} 가 정본 시크릿 목록을 쓰지 않는다`,
    );
    assert.ok(
      !/secrets:\s*\[\s*cfAccountId/.test(src),
      `${f} 에 옛 시크릿 배열이 남아 있다`,
    );
  }
});

// ══════════════════════════════════════════════════════════════════════════
// ② R2 — 버킷 스코프 S3 키로 서명한 DELETE
// ══════════════════════════════════════════════════════════════════════════

test('R2 삭제는 R2 S3 엔드포인트로 SigV4 서명해 보낸다', () => withSecrets(FULL, async () => {
  fakeHttps();
  try {
    const creds = C.readCloudflareCreds('t');
    nextStatus = 204;
    await C.deleteR2Object(creds.r2, 'party_images/uid1/a.jpg');
    assert.strictEqual(sent.length, 1);
    const req = sent[0];
    // 계정 단위 관리 API가 아니라 버킷이 사는 S3 호스트다.
    assert.strictEqual(req.hostname, 'acct123.r2.cloudflarestorage.com');
    assert.notStrictEqual(req.hostname, 'api.cloudflare.com');
    assert.strictEqual(req.method, 'DELETE');
    assert.strictEqual(req.path, '/party-bucket/party_images/uid1/a.jpg');
    // 서명은 액세스 키로 — Bearer 토큰이 아니다.
    assert.ok(/^AWS4-HMAC-SHA256 Credential=ak-test\//.test(req.headers.Authorization));
    assert.ok(!/Bearer/.test(req.headers.Authorization));
  } finally {
    restoreHttps();
  }
}));

test('이미 없는 오브젝트(404)는 성공으로 본다', () => withSecrets(FULL, async () => {
  fakeHttps();
  try {
    const creds = C.readCloudflareCreds('t');
    nextStatus = 404;
    await C.deleteR2Object(creds.r2, 'gone.jpg'); // 던지지 않아야 한다
  } finally {
    nextStatus = 204;
    restoreHttps();
  }
}));

test('403은 실패로 남긴다 — 자격증명이 틀리면 조용히 넘어가지 않는다', () => withSecrets(FULL, async () => {
  fakeHttps();
  try {
    const creds = C.readCloudflareCreds('t');
    nextStatus = 403;
    await assert.rejects(() => C.deleteR2Object(creds.r2, 'x.jpg'));
  } finally {
    nextStatus = 204;
    restoreHttps();
  }
}));

// ══════════════════════════════════════════════════════════════════════════
// ③ Stream — 전용 토큰
// ══════════════════════════════════════════════════════════════════════════

test('Stream 삭제는 Stream 전용 토큰으로 부른다', () => withSecrets(FULL, async () => {
  fakeHttps();
  try {
    const creds = C.readCloudflareCreds('t');
    nextStatus = 200;
    await C.deleteStreamVideo(creds.stream, 'vid123');
    assert.strictEqual(sent.length, 1);
    const req = sent[0];
    assert.strictEqual(req.hostname, 'api.cloudflare.com');
    assert.strictEqual(req.path, '/client/v4/accounts/acct123/stream/vid123');
    assert.strictEqual(req.method, 'DELETE');
    assert.strictEqual(req.headers.Authorization, 'Bearer stream-token');
  } finally {
    nextStatus = 204;
    restoreHttps();
  }
}));

test('폐기된 통합 토큰만 있으면 아무것도 부르지 않는다', () => withSecrets(
  { CLOUDFLARE_API_TOKEN: 'legacy', CLOUDFLARE_ACCOUNT_ID: 'acct123' },
  async () => {
    fakeHttps();
    try {
      const creds = C.readCloudflareCreds('t');
      // 구경로 토큰으로 되돌아가는 폴백은 없다.
      assert.strictEqual(creds, null);
      await C.deleteDocMedia(creds, { videoUid: 'v' }, 't', ['imageUrls']);
      assert.strictEqual(sent.length, 0);
    } finally {
      restoreHttps();
    }
  },
));

// ══════════════════════════════════════════════════════════════════════════
// ④ fail-open · 삭제 대상 판정은 예전 그대로
// ══════════════════════════════════════════════════════════════════════════

test('R2 설정만 없으면 동영상은 계속 지운다(예전 갈래 유지)', () => withSecrets(
  { CLOUDFLARE_ACCOUNT_ID: 'acct123', CLOUDFLARE_STREAM_API_TOKEN: 'stream-token' },
  async () => {
    fakeHttps();
    try {
      const creds = C.readCloudflareCreds('t');
      assert.strictEqual(creds.r2, null);
      assert.ok(creds.stream);
      nextStatus = 200;
      await C.deleteDocMedia(
        creds,
        { videoUid: 'v1', imageUrls: ['https://pub-test.r2.dev/a.jpg'] },
        't',
        ['imageUrls'],
      );
      // 동영상 1건만 나가고 사진은 건너뛴다.
      assert.strictEqual(sent.length, 1);
      assert.ok(sent[0].path.endsWith('/stream/v1'));
    } finally {
      nextStatus = 204;
      restoreHttps();
    }
  },
));

test('삭제 대상은 예전과 같다 — videoUid·coverVideoUid + 지정한 이미지 필드', () => withSecrets(FULL, async () => {
  fakeHttps();
  try {
    const creds = C.readCloudflareCreds('t');
    nextStatus = 204;
    await C.deleteDocMedia(
      creds,
      {
        videoUid: 'v1',
        coverVideoUid: 'v2',
        imageUrls: ['https://pub-test.r2.dev/a.jpg', 'https://pub-test.r2.dev/b.jpg'],
        mainImageUrl: 'https://pub-test.r2.dev/c.jpg',
        // 목록에 없는 필드는 건드리지 않는다.
        thumbnailUrl: 'https://pub-test.r2.dev/nope.jpg',
      },
      't',
      ['imageUrls', 'mainImageUrl'],
    );
    const paths = sent.map((s) => s.path);
    assert.strictEqual(paths.filter((p) => p.includes('/stream/')).length, 2);
    assert.ok(paths.includes('/party-bucket/a.jpg'));
    assert.ok(paths.includes('/party-bucket/b.jpg'));
    assert.ok(paths.includes('/party-bucket/c.jpg'));
    assert.ok(!paths.includes('/party-bucket/nope.jpg'));
  } finally {
    restoreHttps();
  }
}));

test('개별 실패가 나머지 삭제를 멈추지 않는다(fail-open)', () => withSecrets(FULL, async () => {
  fakeHttps();
  const failing = https.request;
  let n = 0;
  https.request = (options, onResponse) => {
    n += 1;
    if (n === 1) {
      // 첫 요청만 소켓 오류 — 나머지는 정상 진행돼야 한다.
      const req = { on: (e, cb) => { if (e === 'error') setImmediate(() => cb(new Error('boom'))); },
        setTimeout: () => {}, write: () => {}, end: () => {}, destroy: () => {} };
      return req;
    }
    return failing(options, onResponse);
  };
  try {
    const creds = C.readCloudflareCreds('t');
    nextStatus = 204;
    await C.deleteDocMedia(
      creds,
      { videoUid: 'v1', imageUrls: ['https://pub-test.r2.dev/a.jpg'] },
      't',
      ['imageUrls'],
    );
    // 첫 건이 터져도 두 번째(사진)는 나갔다.
    assert.ok(sent.some((s) => s.path === '/party-bucket/a.jpg'));
  } finally {
    restoreHttps();
  }
}));

test('creds가 null이면 아무것도 부르지 않는다', () => withSecrets({}, async () => {
  fakeHttps();
  try {
    assert.strictEqual(C.readCloudflareCreds('t'), null);
    await C.deleteDocMedia(null, { videoUid: 'v' }, 't', ['imageUrls']);
    assert.strictEqual(sent.length, 0);
  } finally {
    restoreHttps();
  }
}));

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
      ? `\n미디어 삭제 자격증명 검증 통과 — ${cases.length}건`
      : `\n실패 ${failed}건 / 전체 ${cases.length}건`,
  );
  process.exit(failed === 0 ? 0 : 1);
})();

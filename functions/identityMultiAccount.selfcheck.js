// 본인확인 다중계정 예외 — serverConfig/identityMultiAccount 기반 동작 검증.
//
// 이 예외는 원래 배포된 identityLink.js 안에 CI 해시가 박혀 있었고 저장소에는
// 없었다. Functions를 배포하면 조용히 사라져 테스터가 IDENTITY_ALREADY_LINKED로
// 막히는 사고가 있었다. 지금은 목록이 Firestore에 있다 — 여기서는 **운영에
// 있던 그 동작과 같은지**와, 설정이 없을 때 기존 1인 1계정 정책으로 닫히는지를
// 본다.
//
// ⚠ 이 파일에는 실제 CI 해시가 없다. 테스트용 CI 문자열을 ciHash()로 직접
//   해시해서 쓴다 — 고정된 해시 상수를 적어두지 않는다.
//
// 실행: npm run check:identitymulti   (Firestore·네트워크 없이 가짜 db로 돈다)

const assert = require('assert');

const {
  ciHash,
  linkIdentityAndSaveVerification,
  parseMultiAccountAllowlist,
  loadMultiAccountAllowlist,
  isMultiAccountAllowed,
  resetMultiAccountCache,
  SERVER_CONFIG,
  MULTI_ACCOUNT_DOC,
  DUPLICATE_CODE,
} = require('./identityLink');

let passed = 0;
function check(name, fn) {
  try {
    const r = fn();
    if (r && typeof r.then === 'function') {
      return r.then(
        () => { console.log('✓', name); passed++; },
        (e) => { console.error('✗', name, '\n   ', e && e.message); process.exitCode = 1; },
      );
    }
    console.log('✓', name);
    passed++;
  } catch (e) {
    console.error('✗', name, '\n   ', e && e.message);
    process.exitCode = 1;
  }
  return Promise.resolve();
}

// ── 가짜 Firestore ─────────────────────────────────────────────────────────
//
// linkIdentityAndSaveVerification이 실제로 쓰는 것만 흉내 낸다:
// 설정 문서 get, identityLinks 문서, users 문서, users where ci == ..., 트랜잭션.

function makeDb({ config, links = {}, users = {}, configThrows = false } = {}) {
  const writes = [];
  const reads = [];

  const snap = (exists, data) => ({ exists, data: () => data });

  function docRef(collection, id) {
    return {
      path: `${collection}/${id}`,
      _collection: collection,
      _id: id,
      async get() {
        reads.push(`${collection}/${id}`);
        if (collection === SERVER_CONFIG && id === MULTI_ACCOUNT_DOC) {
          if (configThrows) throw new Error('permission-denied (테스트)');
          return snap(config !== undefined, config);
        }
        if (collection === 'identityLinks') {
          return snap(links[id] !== undefined, links[id]);
        }
        return snap(users[id] !== undefined, users[id]);
      },
    };
  }

  function collectionRef(name) {
    return {
      doc: (id) => docRef(name, id),
      where: (field, op, value) => ({
        limit: () => ({ _query: { name, field, op, value } }),
      }),
    };
  }

  return {
    writes,
    reads,
    collection: collectionRef,
    async runTransaction(fn) {
      const tx = {
        async get(refOrQuery) {
          if (refOrQuery && refOrQuery._query) {
            const { field, value } = refOrQuery._query;
            const docs = Object.entries(users)
              .filter(([, d]) => d && d[field] === value)
              .map(([id, d]) => ({ id, data: () => d }));
            return { docs };
          }
          return refOrQuery.get();
        },
        set(ref, data, options) {
          writes.push({ path: ref.path, data, merge: !!(options && options.merge) });
        },
      };
      return fn(tx);
    },
  };
}

/// 테스트용 CI — 해시는 매번 계산한다(상수로 박지 않는다).
const TESTER_CI = 'SELFCHECK-CI-TESTER';
const OTHER_CI = 'SELFCHECK-CI-OTHER';

function allowlistDoc(...cis) {
  return { enabled: true, allowedCiHashes: cis.map(ciHash) };
}

async function link(db, { uid, ci = TESTER_CI, provider = 'google' } = {}) {
  return linkIdentityAndSaveVerification(db, {
    uid, ci, provider, userPatch: { name: '테스터' },
  });
}

async function expectBlocked(db, opts) {
  let thrown = null;
  try {
    await link(db, opts);
  } catch (e) {
    thrown = e;
  }
  assert.ok(thrown, '차단되어야 하는데 통과했다');
  const code = thrown.details && thrown.details.code;
  assert.strictEqual(code, DUPLICATE_CODE, `중복 코드가 아니다: ${code}`);
  assert.strictEqual(db.writes.length, 0, '차단인데 쓰기가 발생했다');
}

// ── 1. 설정 파싱 (순수) ────────────────────────────────────────────────────

async function main() {
  console.log('\n[1] 설정 문서 파싱');

  await check('정상 문서에서 해시를 뽑는다', () => {
    const set = parseMultiAccountAllowlist(allowlistDoc(TESTER_CI));
    assert.strictEqual(set.size, 1);
    assert.ok(set.has(ciHash(TESTER_CI)));
  });

  await check('문서가 없거나 빈 값이면 빈 집합', () => {
    for (const v of [undefined, null, {}, { allowedCiHashes: [] }, 'nope', 42]) {
      assert.strictEqual(parseMultiAccountAllowlist(v).size, 0, `${JSON.stringify(v)}`);
    }
  });

  await check('enabled: false면 목록이 있어도 전부 차단', () => {
    const doc = { ...allowlistDoc(TESTER_CI), enabled: false };
    assert.strictEqual(parseMultiAccountAllowlist(doc).size, 0);
  });

  await check('sha256 hex 64자가 아닌 값은 버린다 (CI 원문 오입력 방지)', () => {
    const set = parseMultiAccountAllowlist({
      allowedCiHashes: [
        TESTER_CI,                 // CI 원문 — 버려야 한다
        'abc',                     // 너무 짧다
        'Z'.repeat(64),            // hex가 아니다
        123,                       // 문자열이 아니다
        ciHash(TESTER_CI).toUpperCase(), // 대문자는 살려서 소문자로
      ],
    });
    assert.strictEqual(set.size, 1);
    assert.ok(set.has(ciHash(TESTER_CI)));
  });

  console.log('\n[2] 설정 읽기 — 없거나 실패하면 차단(fail-closed)');

  await check('문서가 없으면 빈 집합 + 경고 1회', async () => {
    resetMultiAccountCache();
    const warned = [];
    const orig = console.warn;
    console.warn = (...a) => warned.push(a[0]);
    try {
      const db = makeDb({ config: undefined });
      const a = await loadMultiAccountAllowlist(db, { nowMs: 1 });
      const b = await loadMultiAccountAllowlist(db, { nowMs: 2 });
      assert.strictEqual(a.size, 0);
      assert.strictEqual(b.size, 0);
      assert.strictEqual(
        warned.filter((m) => String(m).includes('다중계정 예외 없음')).length, 1,
        '경고는 인스턴스당 한 번만',
      );
    } finally {
      console.warn = orig;
    }
  });

  await check('읽기가 실패해도 예외를 던지지 않고 차단으로 넘어간다', async () => {
    resetMultiAccountCache();
    const orig = console.warn;
    console.warn = () => {};
    try {
      const db = makeDb({ configThrows: true });
      const set = await loadMultiAccountAllowlist(db, { nowMs: 1 });
      assert.strictEqual(set.size, 0);
    } finally {
      console.warn = orig;
    }
  });

  await check('캐시가 도는 동안은 문서를 다시 읽지 않는다', async () => {
    resetMultiAccountCache();
    const db = makeDb({ config: allowlistDoc(TESTER_CI) });
    await loadMultiAccountAllowlist(db, { nowMs: 1000, cacheMs: 60000 });
    await loadMultiAccountAllowlist(db, { nowMs: 2000, cacheMs: 60000 });
    const configReads = db.reads.filter((p) => p === `${SERVER_CONFIG}/${MULTI_ACCOUNT_DOC}`);
    assert.strictEqual(configReads.length, 1);
  });

  await check('캐시가 만료되면 다시 읽는다 — 목록을 비우면 반영된다', async () => {
    resetMultiAccountCache();
    const db = makeDb({ config: allowlistDoc(TESTER_CI) });
    await loadMultiAccountAllowlist(db, { nowMs: 1000, cacheMs: 60000 });
    await loadMultiAccountAllowlist(db, { nowMs: 1000 + 60001, cacheMs: 60000 });
    const configReads = db.reads.filter((p) => p === `${SERVER_CONFIG}/${MULTI_ACCOUNT_DOC}`);
    assert.strictEqual(configReads.length, 2);
  });

  await check('허용 목록에 있어야만 예외 대상이다', async () => {
    resetMultiAccountCache();
    const db = makeDb({ config: allowlistDoc(TESTER_CI) });
    assert.strictEqual(await isMultiAccountAllowed(db, ciHash(TESTER_CI)), true);
    assert.strictEqual(await isMultiAccountAllowed(db, ciHash(OTHER_CI)), false);
  });

  console.log('\n[3] 기존 1인 1계정 정책 — 예외가 없으면 그대로다');

  await check('설정 없음 + 링크가 다른 계정에 있으면 차단', async () => {
    resetMultiAccountCache();
    const orig = console.warn; console.warn = () => {};
    try {
      const db = makeDb({
        config: undefined,
        links: { [ciHash(TESTER_CI)]: { uid: 'uidFirst', status: 'active' } },
      });
      await expectBlocked(db, { uid: 'uidSecond' });
    } finally { console.warn = orig; }
  });

  await check('설정 없음 + 같은 ci를 쓰는 기존 가입자가 있으면 차단', async () => {
    resetMultiAccountCache();
    const orig = console.warn; console.warn = () => {};
    try {
      const db = makeDb({
        config: undefined,
        users: { uidLegacy: { ci: TESTER_CI } },
      });
      await expectBlocked(db, { uid: 'uidSecond' });
    } finally { console.warn = orig; }
  });

  await check('목록에 없는 사람은 예외가 켜져 있어도 차단', async () => {
    resetMultiAccountCache();
    const orig = console.warn; console.warn = () => {};
    try {
      const db = makeDb({
        config: allowlistDoc(TESTER_CI),
        links: { [ciHash(OTHER_CI)]: { uid: 'uidFirst', status: 'active' } },
      });
      await expectBlocked(db, { uid: 'uidSecond', ci: OTHER_CI });
    } finally { console.warn = orig; }
  });

  await check('enabled: false면 목록에 있어도 차단', async () => {
    resetMultiAccountCache();
    const orig = console.warn; console.warn = () => {};
    try {
      const db = makeDb({
        config: { ...allowlistDoc(TESTER_CI), enabled: false },
        links: { [ciHash(TESTER_CI)]: { uid: 'uidFirst', status: 'active' } },
      });
      await expectBlocked(db, { uid: 'uidSecond' });
    } finally { console.warn = orig; }
  });

  await check('설정 읽기 실패 시에도 차단(fail-closed)', async () => {
    resetMultiAccountCache();
    const orig = console.warn; console.warn = () => {};
    try {
      const db = makeDb({
        configThrows: true,
        links: { [ciHash(TESTER_CI)]: { uid: 'uidFirst', status: 'active' } },
      });
      await expectBlocked(db, { uid: 'uidSecond' });
    } finally { console.warn = orig; }
  });

  console.log('\n[4] 예외 적용 — 운영에 있던 동작과 같은가');

  await check('링크가 다른 계정에 있어도 통과하고 링크가 넘어온다', async () => {
    resetMultiAccountCache();
    const orig = console.warn; console.warn = () => {};
    try {
      const db = makeDb({
        config: allowlistDoc(TESTER_CI),
        links: { [ciHash(TESTER_CI)]: { uid: 'uidFirst', status: 'active' } },
      });
      const out = await link(db, { uid: 'uidSecond', provider: 'naver' });
      assert.strictEqual(out.ciHash, ciHash(TESTER_CI));
      const linkWrite = db.writes.find((w) => w.path.startsWith('identityLinks/'));
      assert.ok(linkWrite, '링크 문서를 쓰지 않았다');
      assert.strictEqual(linkWrite.data.uid, 'uidSecond');
      assert.strictEqual(linkWrite.data.status, 'active');
      // 재가입 추적 — 직전 주인이 이력에 남아야 한다.
      assert.deepStrictEqual(linkWrite.data.previousUids, ['uidFirst']);
    } finally { console.warn = orig; }
  });

  await check('같은 ci를 쓰는 기존 가입자가 있어도 통과한다', async () => {
    resetMultiAccountCache();
    const orig = console.warn; console.warn = () => {};
    try {
      const db = makeDb({
        config: allowlistDoc(TESTER_CI),
        users: { uidLegacy: { ci: TESTER_CI } },
      });
      await link(db, { uid: 'uidSecond' });
      assert.ok(db.writes.some((w) => w.path.startsWith('identityLinks/')));
    } finally { console.warn = orig; }
  });

  await check('users 문서에 identityCiHash와 본인확인 결과를 함께 저장한다', async () => {
    resetMultiAccountCache();
    const orig = console.warn; console.warn = () => {};
    try {
      const db = makeDb({
        config: allowlistDoc(TESTER_CI),
        links: { [ciHash(TESTER_CI)]: { uid: 'uidFirst', status: 'active' } },
      });
      await link(db, { uid: 'uidSecond' });
      const userWrite = db.writes.find((w) => w.path === 'users/uidSecond');
      assert.ok(userWrite, 'users 문서를 쓰지 않았다');
      assert.strictEqual(userWrite.merge, true);
      assert.strictEqual(userWrite.data.identityCiHash, ciHash(TESTER_CI));
      assert.strictEqual(userWrite.data.name, '테스터');
    } finally { console.warn = orig; }
  });

  await check('막을 이유가 없으면 예외와 무관하게 평소처럼 통과한다', async () => {
    resetMultiAccountCache();
    const orig = console.warn; console.warn = () => {};
    try {
      const db = makeDb({ config: undefined });
      await link(db, { uid: 'uidFresh' });
      assert.ok(db.writes.some((w) => w.path === 'users/uidFresh'));
    } finally { console.warn = orig; }
  });

  console.log('\n[5] 로그 — CI 해시 원문을 남기지 않는다');

  await check('예외 적용 시 감사 로그를 남기되 해시는 넣지 않는다', async () => {
    resetMultiAccountCache();
    const lines = [];
    const orig = console.warn;
    console.warn = (...a) => lines.push(JSON.stringify(a));
    try {
      const db = makeDb({
        config: allowlistDoc(TESTER_CI),
        links: { [ciHash(TESTER_CI)]: { uid: 'uidFirst', status: 'active' } },
      });
      await link(db, { uid: 'uidSecond', provider: 'kakao' });
    } finally {
      console.warn = orig;
    }
    const audit = lines.find((l) => l.includes('다중계정 예외 적용'));
    assert.ok(audit, '감사 로그가 없다');
    assert.ok(audit.includes('uidSecond'), 'uid가 없어 역추적할 수 없다');
    for (const l of lines) {
      assert.ok(!l.includes(ciHash(TESTER_CI)), 'CI 해시가 로그에 남았다');
      assert.ok(!l.includes(TESTER_CI), 'CI 원문이 로그에 남았다');
    }
  });

  await check('차단 로그에도 CI 해시가 없다', async () => {
    resetMultiAccountCache();
    const lines = [];
    const orig = console.warn;
    console.warn = (...a) => lines.push(JSON.stringify(a));
    try {
      const db = makeDb({
        config: undefined,
        links: { [ciHash(TESTER_CI)]: { uid: 'uidFirst', status: 'active' } },
      });
      await link(db, { uid: 'uidSecond' }).catch(() => {});
    } finally {
      console.warn = orig;
    }
    for (const l of lines) {
      assert.ok(!l.includes(ciHash(TESTER_CI)), 'CI 해시가 로그에 남았다');
      assert.ok(!l.includes(TESTER_CI), 'CI 원문이 로그에 남았다');
    }
  });

  console.log('\n[6] 저장소에 민감값이 없다');

  await check('identityLink.js에 박힌 64자 hex 상수가 없다', () => {
    const src = require('fs').readFileSync(require('path').join(__dirname, 'identityLink.js'), 'utf8');
    const hex = src.match(/['"][0-9a-fA-F]{64}['"]/g);
    assert.strictEqual(hex, null, `해시로 보이는 상수가 있다: ${hex && hex.length}개`);
    assert.ok(!src.includes('TEST_MULTI_ACCOUNT_CI_HASHES'), '옛 하드코딩 상수가 남아 있다');
  });

  await check('이 셀프체크 파일에도 박힌 해시가 없다', () => {
    const src = require('fs').readFileSync(__filename, 'utf8');
    // 'Z'.repeat(64) 같은 표현은 hex가 아니므로 걸리지 않는다.
    const hex = src.match(/['"][0-9a-fA-F]{64}['"]/g);
    assert.strictEqual(hex, null, '해시로 보이는 상수가 있다');
  });

  console.log(`\n${passed}/${passed + (process.exitCode ? 1 : 0)} 통과`);
  if (!process.exitCode) console.log(`\n${passed}개 전부 통과`);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});

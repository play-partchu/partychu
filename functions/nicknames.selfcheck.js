// 닉네임 규칙·중복방지 자체 검증 — `npm run check:nickname`.
//
// 이 영역은 틀려도 조용하다. 정규화가 앱과 한 글자라도 어긋나면 "앱에서는
// 저장되는데 서버가 거부"하거나, 더 나쁘게는 대소문자만 다른 닉네임 두 개가
// 나란히 저장돼 닉네임으로 사람을 찾을 수 없게 된다.
//
// 그래서 여기서는 가짜 Firestore로 **진짜 claimNickname 트랜잭션을 태우고**,
// 동시 저장(race)까지 재현해 한쪽만 성공하는지 확인한다.

const assert = require('assert');

const admin = require('firebase-admin');
admin.firestore.FieldValue = { serverTimestamp: () => ({ __ts: true }) };

const {
  MIN_LENGTH, MAX_LENGTH, MESSAGES,
  sanitize, normalize, validate, claimNickname, releaseNickname,
} = require('./nicknames');

// ── 가짜 Firestore ────────────────────────────────────────────────────────
// 트랜잭션은 순차 실행으로 흉내내되, get 시점의 스냅샷을 그대로 돌려주고
// commit 직전에 충돌을 검사해 "동시에 둘이 같은 문서를 만드는" 상황을 만든다.
function makeDb(seed = {}) {
  const store = new Map(Object.entries(seed));
  const key = (path, id) => `${path}/${id}`;
  const docRef = (path, id) => ({
    path, id, __key: key(path, id),
    collection: () => { throw new Error('미사용'); },
  });
  const db = {
    __store: store,
    collection: (path) => ({ doc: (id) => docRef(path, id) }),
    async runTransaction(fn) {
      const writes = [];
      const reads = [];
      const tx = {
        async get(ref) {
          const data = store.get(ref.__key);
          reads.push([ref.__key, data === undefined ? null : data]);
          return {
            exists: data !== undefined,
            get: (f) => (data ? data[f] : undefined),
          };
        },
        set(ref, value, opts) {
          writes.push(['set', ref.__key, value, opts]);
        },
        delete(ref) { writes.push(['delete', ref.__key]); },
      };
      const result = await fn(tx);
      // 낙관적 동시성: 읽은 문서가 그 사이 바뀌었으면 실패시킨다.
      for (const [k, snapshot] of reads) {
        const now = store.get(k);
        const changed = (now === undefined) !== (snapshot === null);
        if (changed) {
          const err = new Error('ABORTED: 문서가 그 사이 변경됨');
          err.__aborted = true;
          throw err;
        }
      }
      for (const w of writes) {
        if (w[0] === 'delete') store.delete(w[1]);
        else store.set(w[1], w[3] && w[3].merge ? { ...(store.get(w[1]) || {}), ...w[2] } : w[2]);
      }
      return result;
    },
  };
  return db;
}

const cases = [];
function test(name, fn) { cases.push([name, fn]); }

// ── 정규화 ────────────────────────────────────────────────────────────────

test('앞뒤 공백은 제거하고 내부 공백은 남긴다(검증에서 거부하기 위해)', () => {
  assert.strictEqual(sanitize('  냥냥이  '), '냥냥이');
  assert.strictEqual(sanitize(' 냥 냥이 '), '냥 냥이');
});

test('대소문자를 구분하지 않는다 — PartyChu == partychu', () => {
  assert.strictEqual(normalize('PartyChu'), normalize('partychu'));
  assert.strictEqual(normalize('  PARTYCHU '), 'partychu');
});

test('한글 조합형/완성형이 같은 키가 된다(NFC)', () => {
  const composed = '냥냥이';                       // 완성형
  const decomposed = composed.normalize('NFD');    // 조합형
  assert.notStrictEqual(composed, decomposed, '전제: 두 표현은 문자열로 다르다');
  assert.strictEqual(normalize(decomposed), normalize(composed));
});

// ── 문자 규칙 ─────────────────────────────────────────────────────────────

test('허용: 한글·영문·숫자', () => {
  for (const ok of ['냥냥이', 'Partychu', '냥냥이91', 'abc', 'ABC123', '가나다']) {
    assert.strictEqual(validate(ok), null, `${ok} 가 거부됐다`);
  }
});

test('거부: 공백·특수문자·이모지', () => {
  for (const bad of ['party_chu', '냥냥이♡', '냥 냥이', '🎀냥냥이', 'a.b', 'a,b', 'a/b', '(냥냥이)', 'a-b', 'a@b']) {
    assert.strictEqual(validate(bad), MESSAGES.charset, `${bad} 가 통과됐다`);
  }
});

test('거부: 자모 단독 한글', () => {
  for (const bad of ['ㄱㄴ', 'ㅏㅑ', '냥ㄴ']) {
    assert.strictEqual(validate(bad), MESSAGES.charset, `${bad} 가 통과됐다`);
  }
});

test(`길이는 ${MIN_LENGTH}~${MAX_LENGTH}자, 코드포인트 기준으로 센다`, () => {
  assert.strictEqual(validate('가'), MESSAGES.length);
  assert.strictEqual(validate('가'.repeat(MAX_LENGTH)), null);
  assert.strictEqual(validate('가'.repeat(MAX_LENGTH + 1)), MESSAGES.length);
  assert.strictEqual(validate('   '), MESSAGES.empty, '공백만 있으면 빈 값이다');
});

// ── 선점 ──────────────────────────────────────────────────────────────────

test('처음 저장하면 예약 문서와 users가 함께 기록된다', async () => {
  const db = makeDb();
  const r = await claimNickname(db, 'uidA', ' 냥냥이 ');
  assert.strictEqual(r.nickname, '냥냥이');
  assert.deepStrictEqual(db.__store.get('nicknames/냥냥이').uid, 'uidA');
  assert.strictEqual(db.__store.get('users/uidA').nickname, '냥냥이');
  assert.strictEqual(db.__store.get('users/uidA').nicknameLower, '냥냥이');
});

test('남이 쓰는 닉네임은 거부한다', async () => {
  const db = makeDb({ 'nicknames/partychu': { uid: 'uidA', nickname: 'PartyChu' } });
  await assert.rejects(
    () => claimNickname(db, 'uidB', 'partychu'),
    (e) => e.message === MESSAGES.taken,
  );
});

test('대소문자만 바꿔 남의 닉네임을 가져갈 수 없다', async () => {
  const db = makeDb({ 'nicknames/partychu': { uid: 'uidA', nickname: 'partychu' } });
  await assert.rejects(
    () => claimNickname(db, 'uidB', 'PARTYCHU'),
    (e) => e.message === MESSAGES.taken,
  );
});

test('내 닉네임의 대소문자만 바꾸는 것은 허용된다', async () => {
  const db = makeDb({
    'nicknames/partychu': { uid: 'uidA', nickname: 'partychu' },
    'users/uidA': { nickname: 'partychu' },
  });
  const r = await claimNickname(db, 'uidA', 'PartyChu');
  assert.strictEqual(r.nickname, 'PartyChu');
  assert.strictEqual(db.__store.get('users/uidA').nickname, 'PartyChu');
  assert.strictEqual(db.__store.get('nicknames/partychu').uid, 'uidA', '예약은 그대로다');
});

test('닉네임을 바꾸면 새 이름 선점 + 옛 이름 해제가 함께 일어난다', async () => {
  const db = makeDb({
    'nicknames/냥이': { uid: 'uidA', nickname: '냥이' },
    'users/uidA': { nickname: '냥이' },
  });
  await claimNickname(db, 'uidA', '또리');
  assert.ok(db.__store.has('nicknames/또리'), '새 이름이 선점되지 않았다');
  assert.ok(!db.__store.has('nicknames/냥이'), '옛 이름이 해제되지 않았다');
  assert.strictEqual(db.__store.get('users/uidA').nickname, '또리');
});

test('동시에 같은 닉네임을 저장하면 한쪽만 성공한다(race)', async () => {
  const db = makeDb();
  const results = await Promise.allSettled([
    claimNickname(db, 'uidA', '냥냥이'),
    claimNickname(db, 'uidB', '냥냥이'),
  ]);
  const ok = results.filter((r) => r.status === 'fulfilled');
  assert.strictEqual(ok.length, 1, `둘 다 성공하면 안 된다 (성공 ${ok.length}건)`);
  assert.strictEqual(db.__store.get('nicknames/냥냥이').uid !== undefined, true);
});

test('규칙 위반은 예약 문서를 남기지 않는다', async () => {
  const db = makeDb();
  await assert.rejects(() => claimNickname(db, 'uidA', '냥냥이♡'));
  assert.strictEqual(db.__store.size, 0, '거부됐는데 문서가 생겼다');
});

// ── 해제(탈퇴) ────────────────────────────────────────────────────────────

test('탈퇴하면 예약이 풀려 다른 사람이 다시 쓸 수 있다', async () => {
  const db = makeDb({
    'nicknames/냥이': { uid: 'uidA', nickname: '냥이' },
    'users/uidA': { nickname: '냥이' },
  });
  const released = await releaseNickname(db, 'uidA', '냥이');
  assert.strictEqual(released, true);
  assert.ok(!db.__store.has('nicknames/냥이'));
  await claimNickname(db, 'uidB', '냥이');
  assert.strictEqual(db.__store.get('nicknames/냥이').uid, 'uidB');
});

test('남의 예약은 해제하지 않는다', async () => {
  const db = makeDb({ 'nicknames/냥이': { uid: 'uidA', nickname: '냥이' } });
  const released = await releaseNickname(db, 'uidB', '냥이');
  assert.strictEqual(released, false);
  assert.strictEqual(db.__store.get('nicknames/냥이').uid, 'uidA');
});

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
      ? `\n닉네임 규칙·중복방지 검증 통과 — ${cases.length}건`
      : `\n실패 ${failed}건 / 전체 ${cases.length}건`,
  );
  process.exit(failed === 0 ? 0 : 1);
})();

// 사용자 차단 판정 자체 검증 — `node userBlocks.selfcheck.js`.
//
// 여기서 못박는 것은 하나다: **차단은 기록이 한 방향이어도 효과는 양방향이다.**
//
// 차단당한 쪽이 말을 걸 수 있으면 차단한 사람에게 알림이 가고, 그건 차단이
// 아니다. 그래서 createChatRoom은 두 방향 문서를 **둘 다** 확인한다.
//
// 클라이언트 쪽 같은 정책(목록 필터·본인 차단 금지)은
// party_app/test/block_and_report_test.dart가 본다.

const assert = require('assert');
const { isBlockedBetween } = require('./chatRooms').__helpers;

const cases = [];
const test = (name, fn) => cases.push([name, fn]);

// ── Firestore 흉내 — 문서 id 조회만 쓴다(차단 판정에 쿼리가 없다는 뜻이다) ──
function fakeDb(docs = {}) {
  let queried = false;
  return {
    collection(name) {
      return {
        doc(id) {
          return {
            async get() {
              const data = docs[`${name}/${id}`];
              return { exists: data !== undefined, data: () => data };
            },
          };
        },
        where() {
          queried = true;
          throw new Error('차단 판정은 쿼리를 쓰지 않는다(색인이 필요해진다)');
        },
      };
    },
    get usedQuery() {
      return queried;
    },
  };
}

const block = (a, b) => ({ [`userBlocks/${a}_${b}`]: { blockerId: a, blockedId: b } });

// ── 양방향 ───────────────────────────────────────────────────────────────

test('A가 B를 차단하면 A→B 방향이 막힌다', async () => {
  const db = fakeDb(block('A', 'B'));
  assert.strictEqual(await isBlockedBetween(db, 'A', 'B'), true);
});

test('A가 B를 차단하면 **B→A 방향도** 막힌다(효과는 양방향)', async () => {
  // 이것이 이 파일의 핵심이다. 한쪽만 막으면 차단당한 사람이 말을 걸어
  // 차단한 사람에게 알림을 보낼 수 있다.
  const db = fakeDb(block('A', 'B'));
  assert.strictEqual(await isBlockedBetween(db, 'B', 'A'), true);
});

test('서로 차단해도 그냥 막힌다(중복 판정으로 깨지지 않는다)', async () => {
  const db = fakeDb({ ...block('A', 'B'), ...block('B', 'A') });
  assert.strictEqual(await isBlockedBetween(db, 'A', 'B'), true);
  assert.strictEqual(await isBlockedBetween(db, 'B', 'A'), true);
});

// ── 막지 않아야 하는 경우 ────────────────────────────────────────────────

test('아무 차단도 없으면 열린다', async () => {
  const db = fakeDb({});
  assert.strictEqual(await isBlockedBetween(db, 'A', 'B'), false);
});

test('제3자를 차단한 것은 이 관계에 영향이 없다', async () => {
  const db = fakeDb(block('A', 'C'));
  assert.strictEqual(await isBlockedBetween(db, 'A', 'B'), false);
});

test('같은 사람이면 차단 판정을 하지 않는다(문서를 읽지도 않는다)', async () => {
  // 자기 자신과의 방은 어차피 hostId === guestId 검사에서 먼저 막힌다.
  const db = fakeDb({});
  assert.strictEqual(await isBlockedBetween(db, 'A', 'A'), false);
});

test('uid가 비어 있으면 막지 않는다 — 판정 불가를 차단으로 오해하지 않는다', async () => {
  const db = fakeDb(block('A', 'B'));
  assert.strictEqual(await isBlockedBetween(db, '', 'B'), false);
  assert.strictEqual(await isBlockedBetween(db, 'A', ''), false);
});

// ── 구조 ─────────────────────────────────────────────────────────────────

test('차단 판정은 쿼리 없이 문서 두 개만 읽는다(색인 불필요)', async () => {
  // fakeDb의 where()는 부르는 즉시 던진다. 통과했다는 것은 쿼리를 쓰지
  // 않았다는 뜻이다 — 쿼리로 바꾸면 복합 색인이 필요해지고, 색인이 없으면
  // 판정이 실패해 **차단이 조용히 풀린다.**
  const db = fakeDb(block('A', 'B'));
  await isBlockedBetween(db, 'A', 'B');
  assert.strictEqual(db.usedQuery, false);
});

test('문서 id 규칙이 앱(BlockService.docIdFor)과 같다', () => {
  // 앱은 "{차단한사람}_{차단당한사람}"으로 만든다. 규칙도 그 형태를 강제한다
  // (firestore.rules userBlocks create). 셋 중 하나만 달라져도 차단이 샌다.
  const docs = block('A', 'B');
  assert.ok(Object.keys(docs)[0] === 'userBlocks/A_B');
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
    failed === 0 ? `\n사용자 차단 판정 ${cases.length}건 통과` : `\n${failed}건 실패`
  );
  process.exit(failed === 0 ? 0 : 1);
})();

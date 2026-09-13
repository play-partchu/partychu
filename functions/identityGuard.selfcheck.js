// 본인확인 게이트 자체 검증 — `node identityGuard.selfcheck.js`.
//
// 이 게이트 하나가 "본인확인을 마쳐야 회원 기능을 쓴다"는 정책의 **서버 쪽
// 마지막 방어선**이다. 앱 UI(루트 게이트)는 구버전 앱이나 콜러블 직접 호출로
// 통째로 우회되므로, 여기서 뚫리면 정책이 사라진다. 그래서 못박는 것은 세 가지다.
//
//   · 인증 근거는 서버 전용 필드 두 개뿐이다(identityVerified / isVerified)
//   · 판정할 수 없으면 통과시키지 않는다(fail-closed) — 문서 없음도 미인증이다
//   · 시각 필드(verifiedAt)는 인증으로 승격되지 않는다
//
// 클라이언트 쪽 같은 정책은 party_app/test/root_gate_test.dart가 본다.

const assert = require('assert');
const {
  isIdentityVerified,
  assertIdentityVerifiedData,
  assertIdentityVerified,
  IDENTITY_REQUIRED_CODE,
} = require('./identityGuard');

const cases = [];
const test = (name, fn) => cases.push([name, fn]);

/// HttpsError의 code는 'functions/failed-precondition' 형태로 붙는다.
function expectBlocked(fn) {
  try {
    fn();
  } catch (e) {
    assert.ok(
      String(e.code).endsWith(IDENTITY_REQUIRED_CODE),
      `기대한 코드가 아니다: ${e.code}`
    );
    return e;
  }
  throw new Error('막혔어야 하는데 통과했다');
}

// ── 통과해야 하는 것 ────────────────────────────────────────────────────

test('identityVerified: true는 인증이다', () => {
  assert.strictEqual(isIdentityVerified({ identityVerified: true }), true);
  assertIdentityVerifiedData({ identityVerified: true });
});

test('하위호환 isVerified: true도 인증이다', () => {
  assert.strictEqual(isIdentityVerified({ isVerified: true }), true);
  assertIdentityVerifiedData({ isVerified: true });
});

// ── 막아야 하는 것 ──────────────────────────────────────────────────────

test('두 필드가 모두 없으면 미인증이다', () => {
  assert.strictEqual(isIdentityVerified({ nickname: '냥냥이' }), false);
  expectBlocked(() => assertIdentityVerifiedData({ nickname: '냥냥이' }));
});

test('identityVerified: false는 미인증이다', () => {
  expectBlocked(() => assertIdentityVerifiedData({ identityVerified: false }));
});

test('users 문서 자체가 없으면 미인증이다 — 판정 실패를 통과로 바꾸지 않는다', () => {
  assert.strictEqual(isIdentityVerified(null), false);
  assert.strictEqual(isIdentityVerified(undefined), false);
  expectBlocked(() => assertIdentityVerifiedData(null));
});

test('verifiedAt만 있는 문서는 인증이 아니다', () => {
  // 2026-08-22 운영 전수 조회에서 이런 문서는 0건이었다. 그래도 못박아 두는
  // 이유는, 시각 필드를 인증으로 승격하면 "인증 기록은 남았지만 인증은
  // 해제된" 상태(탈퇴 후 재가입 등)를 인증으로 오판하기 때문이다.
  assert.strictEqual(isIdentityVerified({ verifiedAt: new Date() }), false);
  expectBlocked(() =>
    assertIdentityVerifiedData({ verifiedAt: new Date(), identityVerifiedAt: new Date() })
  );
});

test('불리언이 아닌 값은 인증으로 쳐주지 않는다', () => {
  // 문자열 'true', 1 같은 값이 어떤 경로로 들어와도 통과하지 않는다.
  assert.strictEqual(isIdentityVerified({ identityVerified: 'true' }), false);
  assert.strictEqual(isIdentityVerified({ identityVerified: 1 }), false);
  assert.strictEqual(isIdentityVerified({ isVerified: 'true' }), false);
});

test('요청 payload에 실린 인증 주장은 판정에 쓰이지 않는다', () => {
  // 게이트는 users 문서만 본다 — 아래 객체는 "클라이언트가 보낸 값"을 흉내낸
  // 것이고, 게이트 함수는 애초에 그런 값을 받는 자리가 없다.
  const userDataFromServer = { nickname: '냥냥이' };
  const requestDataFromClient = { identityVerified: true, isVerified: true };
  assert.strictEqual(isIdentityVerified(userDataFromServer), false);
  expectBlocked(() => assertIdentityVerifiedData(userDataFromServer));
  // 클라이언트 payload를 넘겨야만 통과한다는 사실 자체가, 호출부가 절대
  // 그렇게 쓰면 안 된다는 뜻이다(호출부는 전부 users 문서를 넘긴다).
  assert.strictEqual(isIdentityVerified(requestDataFromClient), true);
});

// ── 문서를 직접 읽는 형태 ───────────────────────────────────────────────

function fakeDb(docsByUid) {
  return {
    collection(name) {
      assert.strictEqual(name, 'users');
      return {
        doc(uid) {
          return {
            async get() {
              const data = docsByUid[uid];
              return { exists: data !== undefined, data: () => data };
            },
          };
        },
      };
    },
  };
}

test('assertIdentityVerified는 users/{uid}를 읽어 판정하고 스냅샷을 돌려준다', async () => {
  const db = fakeDb({ verified: { identityVerified: true, nickname: '냥냥이' } });
  const snap = await assertIdentityVerified(db, 'verified');
  assert.strictEqual(snap.data().nickname, '냥냥이');
});

test('assertIdentityVerified는 미인증 계정을 막는다', async () => {
  const db = fakeDb({ plain: { nickname: '냥냥이' } });
  await assert.rejects(
    () => assertIdentityVerified(db, 'plain'),
    (e) => String(e.code).endsWith(IDENTITY_REQUIRED_CODE)
  );
});

test('assertIdentityVerified는 문서가 없는 계정을 막는다', async () => {
  const db = fakeDb({});
  await assert.rejects(
    () => assertIdentityVerified(db, 'ghost'),
    (e) => String(e.code).endsWith(IDENTITY_REQUIRED_CODE)
  );
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
  console.log(failed === 0 ? `\n본인확인 게이트 ${cases.length}건 통과` : `\n${failed}건 실패`);
  process.exit(failed === 0 ? 0 : 1);
})();

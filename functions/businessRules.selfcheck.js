// 사업자 권한 규칙 검증 — `npm run check:bizrules`.
//
// 이 파일은 **두 층**이다.
//
//   ① 드리프트 검사 (항상 실행, 에뮬레이터 불필요)
//      firestore.rules와 서버 판정이 갈리지 않았는지 본문을 직접 읽어 확인한다.
//      같은 조건이 세 곳(서버 isBusinessAuthorized / 규칙 isBusinessVerified /
//      앱 BusinessVerification.isVerified)에 각자의 문법으로 적혀 있어서, 한
//      곳만 고치면 "앱은 열어줬는데 규칙이 막는" 상태가 조용히 만들어진다.
//      그 조용한 실패를 잡는 것이 이 층의 목적이다.
//
//   ② 에뮬레이터 검증 (Firestore 에뮬레이터가 있을 때만)
//      실제 규칙 엔진에 문서를 넣고 권한을 확인한다.
//      준비:  npm i -D @firebase/rules-unit-testing   (+ Java 필요)
//      실행:  firebase emulators:exec --only firestore \
//               "node businessRules.selfcheck.js"
//      없으면 ①만 돌고 **건너뛴 사실을 명시적으로 출력한다** — 조용히 통과한
//      것처럼 보이면 안 된다.

process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'selfcheck';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const RULES_PATH = path.join(__dirname, '..', 'firestore.rules');
const rules = fs.readFileSync(RULES_PATH, 'utf8');

const cases = [];
const test = (name, fn) => cases.push([name, fn]);

// ══════════════════════════════════════════════════════════════════════════
// ① 드리프트 검사 — 규칙 본문 ↔ 서버 판정
// ══════════════════════════════════════════════════════════════════════════

/// 규칙 파일에서 함수 하나의 본문을 꺼낸다.
function ruleFn(name) {
  const i = rules.indexOf(`function ${name}()`);
  assert.notStrictEqual(i, -1, `규칙에 ${name}()가 없다`);
  let depth = 0;
  for (let k = rules.indexOf('{', i); k < rules.length; k += 1) {
    if (rules[k] === '{') depth += 1;
    else if (rules[k] === '}') {
      depth -= 1;
      if (depth === 0) return rules.slice(i, k + 1);
    }
  }
  throw new Error(`${name}() 본문을 닫지 못했다`);
}

test('규칙: isBusinessVerified()가 status와 authorization을 **둘 다** 본다', () => {
  const body = ruleFn('isBusinessVerified');
  assert.ok(
    body.includes("'businessVerification', 'status'") && body.includes("== 'verified'"),
    'status 조건이 사라졌다',
  );
  assert.ok(
    body.includes("'businessVerification', 'authorization'"),
    'authorization 조건이 사라졌다 — status만으로 권한이 열린다',
  );
});

test('규칙: 권한이 열리는 값은 self와 delegated뿐이다', () => {
  const body = ruleFn('isBusinessVerified');
  const { AUTHORIZED_VALUES } = require('./businessVerification');
  for (const v of AUTHORIZED_VALUES) {
    assert.ok(body.includes(`== '${v}'`), `규칙에 '${v}'가 없다`);
  }
  // 서버가 허용하지 않는 값이 규칙에만 적혀 있으면 규칙이 더 넓다.
  for (const m of body.matchAll(/'businessVerification', 'authorization'\], ''\) == '([a-zA-Z]+)'/g)) {
    assert.ok(
      AUTHORIZED_VALUES.has(m[1]),
      `규칙이 서버보다 넓다 — '${m[1]}'는 서버가 허용하지 않는다`,
    );
  }
});

test('규칙: delegated는 근거 문서 id가 있어야 한다(서버와 같은 추가 조건)', () => {
  const body = ruleFn('isBusinessVerified');
  assert.ok(body.includes("'delegationId'"), 'delegationId 조건이 없다');
  assert.ok(body.includes('.size() > 0'), '빈 delegationId를 걸러내지 않는다');

  // 서버 쪽도 같은 조건인지 확인한다.
  const { isBusinessAuthorized } = require('./businessVerification');
  assert.strictEqual(
    isBusinessAuthorized({ status: 'verified', authorization: 'delegated' }),
    false,
  );
  assert.strictEqual(
    isBusinessAuthorized({ status: 'verified', authorization: 'delegated', delegationId: 'D' }),
    true,
  );
});

test('규칙: authorization이 없는 문서를 봐주는 예외가 없다', () => {
  const body = ruleFn('isBusinessVerified');
  // get(...)의 기본값이 '' 말고 다른 것이면 '없으면 통과'가 될 수 있다.
  for (const m of body.matchAll(/'businessVerification', 'authorization'\], ('[^']*')\)/g)) {
    assert.strictEqual(m[1], "''", `authorization 기본값이 ${m[1]}다 — 없는 문서가 통과한다`);
  }
});

test('규칙: 서버 전용 컬렉션 네 개가 전면 차단돼 있다', () => {
  // identityLinks(CI 링크) · businessOwnership(대표자 identity) ·
  // businessDelegations(운영권) · businessApprovalSessions(NICE 세션).
  // 하나라도 열리면 권한을 스스로 써넣거나 대표자 식별자를 조회할 수 있다.
  for (const c of [
    'identityLinks',
    'businessOwnership',
    'businessDelegations',
    'businessApprovalSessions',
  ]) {
    const i = rules.indexOf(`match /${c}/`);
    assert.notStrictEqual(i, -1, `${c} 규칙이 없다 — 기본 거부에 기대면 안 된다`);
    // 다음 match 블록 직전까지가 이 컬렉션의 규칙이다. `indexOf('}')`로 자르면
    // 경로의 `{ciHash}` 중괄호에 먼저 걸려 본문을 못 본다.
    const next = rules.indexOf('match /', i + 1);
    const block = rules.slice(i, next === -1 ? i + 400 : next);
    assert.ok(
      /allow read,\s*write:\s*if false;/.test(block),
      `${c}가 전면 차단돼 있지 않다: ${block.trim()}`,
    );
  }
});

test('규칙: businessVerification 맵 전체가 클라이언트 쓰기 금지 필드다', () => {
  // 이 잠금이 authorization·delegationId·delegationRequest(요청 쿼터)까지
  // 한꺼번에 덮는다. 새 필드를 이 맵 **바깥**에 만들면 잠금 밖이 된다.
  const create = rules.slice(rules.indexOf('allow create: if isSignedIn() && uid() == userId'));
  assert.ok(
    create.slice(0, 900).includes("'businessVerification'"),
    'create 잠금 목록에서 businessVerification이 빠졌다',
  );
  const change = rules.slice(rules.indexOf('function isVerificationFieldChange()'));
  assert.ok(
    change.slice(0, 900).includes("'businessVerification'"),
    'update 잠금 목록에서 businessVerification이 빠졌다',
  );
});

test('규칙: 사업자 권한이 필요한 경로가 그대로 남아 있다', () => {
  // 게이트를 고치다가 호출부가 빠지면 판정이 아무 데도 안 쓰인다.
  const uses = [...rules.matchAll(/isBusinessVerified\(\)/g)].length;
  assert.ok(uses >= 5, `isBusinessVerified() 사용처가 ${uses}곳뿐이다`);
  for (const c of ['match /places/', 'match /events/', 'match /parties/']) {
    assert.notStrictEqual(rules.indexOf(c), -1, `${c} 규칙이 사라졌다`);
  }
});

// ══════════════════════════════════════════════════════════════════════════
// ② 에뮬레이터 검증 — 실제 규칙 엔진
// ══════════════════════════════════════════════════════════════════════════

const ME = 'uidMe';

/// users 문서 한 장.
///
/// `authorization`에 `undefined`를 주면 그 **필드 자체가 없는** 문서가 된다 —
/// "필드를 안 쓰면 통과"가 되지 않는지 보는 케이스라 빈 문자열과 다르다.
/// `status`도 인자로 받는다: 권한 판정은 status와 authorization **두 축**이고,
/// 한 축만 흔들어 보면 나머지 축이 실제로 걸리는지 알 수 없다.
const bizDoc = (authorization, extra = {}, status = 'verified') => ({
  identityVerified: true,
  accountStatus: 'active',
  businessVerification: authorization === undefined
    ? { status, ...extra }
    : { status, authorization, ...extra },
});

async function emulatorSuite(record) {
  let testing;
  try {
    testing = require('@firebase/rules-unit-testing');
  } catch (_) {
    return 'skipped: @firebase/rules-unit-testing 미설치';
  }
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    return 'skipped: FIRESTORE_EMULATOR_HOST 없음 (firebase emulators:exec로 실행)';
  }

  const env = await testing.initializeTestEnvironment({
    projectId: 'partychu-rules-test',
    firestore: { rules },
  });

  // ── 도구 ─────────────────────────────────────────────────────────────

  /// 규칙을 끄고 users 문서를 통째로 갈아 끼운다(merge 아님 — 앞 케이스의
  /// authorization이 남아 다음 케이스를 조용히 통과시키면 안 된다).
  const seed = async (data) => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc(`users/${ME}`).set(data);
    });
  };
  const clearUser = async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc(`users/${ME}`).delete();
    });
  };

  let seq = 0;
  /// 이 계정이 그 컬렉션에 문서를 만들 수 있는가.
  ///
  /// 규칙 **평가 오류**(users 문서가 없어 get()이 null인 경우 등)도 여기서는
  /// false다 — 거부와 오류를 나누지 않는 이유는 둘 다 "만들 수 없다"라는 같은
  /// 결과이기 때문이다. 나뉘어야 하는 케이스는 아래에 따로 이름을 붙여 둔다.
  const canCreate = async (collection, data) => {
    seq += 1;
    const db = env.authenticatedContext(ME).firestore();
    try {
      await db.collection(collection).doc(`x_${seq}`).set(data);
      return true;
    } catch (_) {
      return false;
    }
  };
  const canPlace = () => canCreate('places', { hostId: ME, name: '테스트 공간' });
  const canEvent = () => canCreate('events', { hostId: ME, name: '테스트 이벤트' });
  const canParty = (extra) =>
    canCreate('parties', { hostId: ME, title: '테스트 파티', ...extra });

  // ── ① authorization 축 — 열리는 값과 막히는 값 ───────────────────────
  //
  // places·events를 **둘 다** 본다. 게이트는 세 컬렉션에 각자 적혀 있어서
  // 한 곳만 확인하면 나머지가 다른 조건을 쓰고 있어도 드러나지 않는다.

  await seed(bizDoc('self'));
  record('에뮬: self는 플레이스를 만들 수 있다', await canPlace() === true);
  record('에뮬: self는 이벤트를 만들 수 있다', await canEvent() === true);

  await seed(bizDoc('delegated', { delegationId: 'DLG1' }));
  record('에뮬: delegated + delegationId는 플레이스가 열린다', await canPlace() === true);
  record('에뮬: delegated + delegationId는 이벤트가 열린다', await canEvent() === true);

  await seed(bizDoc('delegated'));
  record('에뮬: delegationId 없는 delegated는 플레이스가 막힌다', await canPlace() === false);
  record('에뮬: delegationId 없는 delegated는 이벤트가 막힌다', await canEvent() === false);

  // 빈 문자열·비문자열 — 규칙의 `is string`과 `.size() > 0`이 실제로 거르는가.
  await seed(bizDoc('delegated', { delegationId: '' }));
  record('에뮬: 빈 문자열 delegationId는 플레이스가 막힌다', await canPlace() === false);
  record('에뮬: 빈 문자열 delegationId는 이벤트가 막힌다', await canEvent() === false);
  await seed(bizDoc('delegated', { delegationId: 123 }));
  record('에뮬: 문자열이 아닌 delegationId는 막힌다', await canPlace() === false);

  await seed(bizDoc('pendingOwnerApproval'));
  record('에뮬: pendingOwnerApproval은 플레이스가 막힌다', await canPlace() === false);
  record('에뮬: pendingOwnerApproval은 이벤트가 막힌다', await canEvent() === false);

  await seed(bizDoc(undefined));
  record('에뮬: authorization 없는 문서는 플레이스가 막힌다(legacy 예외 없음)',
    await canPlace() === false);
  record('에뮬: authorization 없는 문서는 이벤트가 막힌다(legacy 예외 없음)',
    await canEvent() === false);

  // ── ② status 축 — authorization이 self여도 status가 아니면 막힌다 ────
  //
  // 이 축이 빠지면 "authorization만 self면 통과"가 되어, 국세청 진위확인이라는
  // 나머지 한 축이 통째로 무의미해진다.

  for (const status of ['pending', 'rejected', 'pendingOwnerApproval', '']) {
    await seed(bizDoc('self', {}, status));
    const label = status === '' ? '빈 문자열' : status;
    record(`에뮬: status='${label}' + self는 플레이스가 막힌다`, await canPlace() === false);
    record(`에뮬: status='${label}' + self는 이벤트가 막힌다`, await canEvent() === false);
  }

  await seed({ identityVerified: true, accountStatus: 'active' });
  record('에뮬: businessVerification 맵이 아예 없으면 막힌다', await canPlace() === false);

  await clearUser();
  record('에뮬: users 문서가 없어도 평가 오류가 아니라 거부다', await canPlace() === false);

  // ── ③ parties 게이트 ─────────────────────────────────────────────────
  //
  // parties에는 조건이 둘 더 있다 — 미인증 호스트의 우회로(preopen)와 공개
  // 화면용 미러링 값(hostBusinessVerified). 그 둘이 같은 isBusinessVerified()를
  // 쓰는지 확인한다.
  //
  // ⚠️ 이 스위트는 appConfig/policy 문서를 **만들지 않는다** —
  //    individualPartyCreateEnabled()가 false인 상태를 전제로 한 판정이다
  //    (그 문서가 없는 것이 지금 운영 상태이기도 하다). 정책을 여는 쪽 판정은
  //    partyOpenState.selfcheck.js가 따로 본다.

  await seed(bizDoc('self'));
  record('에뮬: self는 open 파티를 만들 수 있다',
    await canParty({ openState: 'open', hostBusinessVerified: true }) === true);
  record('에뮬: 인증됐는데 hostBusinessVerified=false면 막힌다(공개 값 위조 금지)',
    await canParty({ openState: 'open', hostBusinessVerified: false }) === false);

  await seed(bizDoc('delegated', { delegationId: 'DLG1' }));
  record('에뮬: delegated도 self와 똑같이 open 파티를 만들 수 있다',
    await canParty({ openState: 'open', hostBusinessVerified: true }) === true);

  await seed(bizDoc('delegated'));
  record('에뮬: delegationId 없는 delegated는 open 파티가 막힌다',
    await canParty({ openState: 'open', hostBusinessVerified: true }) === false);
  record('에뮬: delegationId 없는 delegated는 hostBusinessVerified=true인 preopen도 막힌다',
    await canParty({ openState: 'preopen', hostBusinessVerified: true }) === false);
  record('에뮬: delegationId 없는 delegated는 개인 호스트와 같은 취급이다(정책 off)',
    await canParty({ openState: 'preopen', hostBusinessVerified: false }) === false);

  await seed(bizDoc('pendingOwnerApproval'));
  record('에뮬: pendingOwnerApproval은 open 파티가 막힌다',
    await canParty({ openState: 'open', hostBusinessVerified: true }) === false);

  // ── ④ 서버 전용 컬렉션 — 읽기·쓰기 모두 거부 ─────────────────────────

  await seed(bizDoc('self'));
  const db = env.authenticatedContext(ME).firestore();
  for (const c of ['identityLinks', 'businessOwnership', 'businessDelegations',
    'businessApprovalSessions']) {
    let readBlocked = false; let writeBlocked = false;
    try { await db.collection(c).doc('x').get(); } catch (_) { readBlocked = true; }
    try { await db.collection(c).doc('x').set({ a: 1 }); } catch (_) { writeBlocked = true; }
    record(`에뮬: ${c} 읽기 차단`, readBlocked);
    record(`에뮬: ${c} 쓰기 차단`, writeBlocked);
  }

  // ── ⑤ 클라이언트가 스스로 권한을 써넣을 수 있는가 ────────────────────
  //
  // 세 경로를 각각 본다. 맵을 통째로 merge / 필드 하나만 update / 문서를 처음
  // 만들 때 심기. 잠금은 맵 단위라, 셋 중 하나만 열려도 잠금이 뚫린다.

  let selfGrantBlocked = false;
  try {
    await db.doc(`users/${ME}`).set(
      { businessVerification: { status: 'verified', authorization: 'delegated', delegationId: 'X' } },
      { merge: true },
    );
  } catch (_) { selfGrantBlocked = true; }
  record('에뮬: 클라이언트가 스스로 delegated를 써넣지 못한다', selfGrantBlocked);

  await seed(bizDoc('delegated', { delegationId: 'DLG1' }));
  let fieldBlocked = false;
  try {
    await db.doc(`users/${ME}`).update({ 'businessVerification.delegationId': 'HACKED' });
  } catch (_) { fieldBlocked = true; }
  record('에뮬: delegationId 단일 필드 update도 막힌다', fieldBlocked);

  let authFieldBlocked = false;
  try {
    await db.doc(`users/${ME}`).update({ 'businessVerification.authorization': 'self' });
  } catch (_) { authFieldBlocked = true; }
  record('에뮬: authorization 단일 필드 update도 막힌다', authFieldBlocked);

  await clearUser();
  let createBlocked = false;
  try {
    await db.doc(`users/${ME}`).set({
      nickname: 'me',
      businessVerification: { status: 'verified', authorization: 'self' },
    });
  } catch (_) { createBlocked = true; }
  record('에뮬: users 문서를 만들 때 businessVerification을 심지 못한다', createBlocked);

  await env.cleanup();
  return null;
}
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

  let emulatorCount = 0;
  const record = (name, ok) => {
    emulatorCount += 1;
    if (ok) console.log(`  ✓ ${name}`);
    else { failed += 1; console.error(`  ✗ ${name}`); }
  };

  let skipReason = null;
  try {
    skipReason = await emulatorSuite(record);
  } catch (e) {
    failed += 1;
    console.error(`  ✗ 에뮬레이터 검증 중 오류\n    ${e.message}`);
  }

  if (skipReason) {
    console.log(`\n⚠️  에뮬레이터 검증을 건너뛰었습니다 — ${skipReason}`);
    console.log('    규칙을 배포하기 전에 반드시 아래로 한 번은 돌려야 합니다:');
    console.log('      npm i -D @firebase/rules-unit-testing');
    console.log('      firebase emulators:exec --only firestore "node businessRules.selfcheck.js"');
  }

  const total = cases.length + emulatorCount;
  console.log(
    failed === 0
      ? `\n사업자 권한 규칙 검증 통과 — ${total}건`
        + (skipReason ? ` (드리프트 ${cases.length}건만, 에뮬레이터 미실행)` : '')
      : `\n실패 ${failed}건 / 전체 ${total}건`,
  );
  process.exit(failed === 0 ? 0 : 1);
})();

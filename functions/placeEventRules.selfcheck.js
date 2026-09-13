// 이벤트(placePromotions) 저장 규칙 검증 — `npm run check:placeeventrules`.
//
// ── 이 컬렉션이 무엇인가 ──────────────────────────────────────────────────
//   · `events`          = **플레이스 본체**(매장·즐길거리). 이벤트가 아니다.
//   · `places`          = 공간대여·숙박 본체.
//   · `placePromotions` = 그 플레이스가 여는 **이벤트·혜택 한 건**. ← 여기.
//
// ── 이 파일이 못 박는 정책 ────────────────────────────────────────────────
// 이벤트 생성의 관문은 **부모 플레이스의 소유권 하나**다
// (`isVerifiedMember` + `hostId == uid` + `ownsSourcePlace`).
//
// ⚠️ **사업자 권한(isBusinessVerified)은 여기에 걸려 있지 않다. 의도된 것이다.**
//    사업자 인증은 `events`/`places`의 **신규 생성**에만 요구한다. 이미 만들어진
//    플레이스에 딸린 문서(룸·상품·이벤트)에 그 조건을 다시 달면, 정책 도입
//    이전에 등록한 플레이스의 주인이 자기 가게 이벤트를 손도 못 대게 된다
//    (firestore.rules의 ownsSourcePlace 주석과 같은 근거).
//
//    그래서 아래에는 "권한 축이 없는 verified도 자기 플레이스에는 이벤트를
//    만들 수 있다"가 **통과 케이스로** 들어 있다. 이걸 거부로 바꾸려면 그건
//    버그 수정이 아니라 정책 변경이고, 레거시 플레이스 주인을 어떻게 할지
//    먼저 정해야 한다.
//
// 두 층이다(businessRules.selfcheck.js와 같은 구성).
//   ① 드리프트 검사 — 규칙 본문에 사업자 게이트가 몰래 끼어들지 않았는지
//   ② 에뮬레이터 검증 — 실제 규칙 엔진
//      준비: npm i -D @firebase/rules-unit-testing   (+ Java 필요)
//      실행: firebase emulators:exec --only firestore \
//              "node placeEventRules.selfcheck.js"

process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'selfcheck';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const rules = fs.readFileSync(
  path.join(__dirname, '..', 'firestore.rules'),
  'utf8',
);

const cases = [];
const test = (name, fn) => cases.push([name, fn]);

// ══════════════════════════════════════════════════════════════════════════
// ① 드리프트 검사
// ══════════════════════════════════════════════════════════════════════════

function promotionBlock() {
  const i = rules.indexOf('match /placePromotions/');
  assert.notStrictEqual(i, -1, 'placePromotions 규칙 블록이 없다');
  const end = rules.indexOf('\n    }\n', i);
  const block = rules.slice(i, end);
  assert.ok(block.includes('allow delete'), '블록을 너무 일찍 잘랐다');
  return block;
}

function createClause() {
  const b = promotionBlock();
  const at = b.indexOf('allow create:');
  assert.notStrictEqual(at, -1, 'create 규칙이 없다');
  return b.slice(at, b.indexOf(';', at));
}

test('생성 관문이 부모 소유권을 실제로 확인한다', () => {
  const c = createClause();
  assert.ok(c.includes('ownsSourcePlace('), 'ownsSourcePlace가 빠졌다');
  assert.ok(c.includes('placeCollection'), 'placeCollection을 넘기지 않는다');
  assert.ok(c.includes('placeId'), 'placeId를 넘기지 않는다');
  assert.ok(c.includes('hostId == uid()'), 'hostId 확인이 빠졌다');
  assert.ok(c.includes('isVerifiedMember()'), '본인확인 관문이 빠졌다');
});

test('ownsSourcePlace가 부모 문서를 실제로 읽는다', () => {
  const i = rules.indexOf('function ownsSourcePlace(');
  assert.notStrictEqual(i, -1, 'ownsSourcePlace()가 없다');
  const body = rules.slice(i, rules.indexOf('\n    }', i));
  assert.ok(body.includes('exists('), '없는 부모(orphan)를 걸러내지 않는다');
  assert.ok(body.includes('.data.hostId == uid()'), '부모의 주인을 확인하지 않는다');
  assert.ok(
    body.includes("placeCollection == 'events'") &&
      body.includes("placeCollection == 'places'"),
    '부모 컬렉션 화이트리스트가 사라졌다 — 아무 컬렉션이나 부모가 된다',
  );
});

test('이벤트 생성에 사업자 게이트가 끼어들지 않았다', () => {
  // 위 헤더의 근거대로 **없는 것이 맞다.** 실수로 들어오면 레거시 플레이스
  // 주인이 자기 가게 이벤트를 못 만들게 되므로, 조용히 추가되는 것을 막는다.
  assert.ok(
    !createClause().includes('isBusinessVerified()'),
    '이벤트 생성에 사업자 인증이 걸렸다 — 정책 변경이라면 이 테스트부터 고칠 것',
  );
});

test('소속(hostId/placeId/placeCollection)은 수정으로 못 바꾼다', () => {
  const b = promotionBlock();
  const at = b.indexOf('allow update:');
  const clause = b.slice(at, b.indexOf(';', at));
  for (const f of ['hostId', 'placeId', 'placeCollection']) {
    assert.ok(
      clause.includes(`request.resource.data.${f} == resource.data.${f}`),
      `${f}를 바꿔 남의 장소로 옮겨 붙일 수 있다`,
    );
  }
});

// ══════════════════════════════════════════════════════════════════════════
// ② 에뮬레이터 검증
// ══════════════════════════════════════════════════════════════════════════

/// 사업자 권한 축이 다른 호스트들. **전부 자기 플레이스에는 이벤트를 만들 수
/// 있어야 한다** — 위 헤더의 정책 근거 참고.
const HOSTS = {
  self: { status: 'verified', authorization: 'self' },
  delegated: { status: 'verified', authorization: 'delegated', delegationId: 'D1' },
  // 권한 축이 기록되기 전에 인증을 마친 계정(운영에 실제로 있는 모양).
  legacy: { status: 'verified' },
  pendingApproval: { status: 'verified', authorization: 'pendingOwnerApproval' },
  // 사업자 인증 자체를 통과하지 못한 계정 — 그래도 **이미 가진** 플레이스의
  // 이벤트는 만들 수 있다(플레이스를 새로 만드는 것만 막힌다).
  notBusiness: { status: 'failed' },
};

const OTHER = 'host-other';

function promo(placeId, placeCollection, hostId, extra = {}) {
  return {
    placeId,
    placeCollection,
    hostId,
    title: '웰컴 드링크 1잔',
    benefit: '첫 방문 시 1잔 무료',
    priceText: '무료',
    conditions: '1인 1회',
    audience: '전체',
    reservationRequired: false,
    isVisible: true,
    sortOrder: 0,
    ...extra,
  };
}

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
    projectId: 'partychu-place-event-rules',
    firestore: { rules },
  });

  // ── 전제 심기 ─────────────────────────────────────────────────────────
  // 부모 플레이스는 규칙을 우회해 심는다 — 플레이스 **생성**에는 사업자 인증이
  // 필요해서, 규칙을 거쳐 만들면 이 검사의 관심사(이벤트 생성)와 섞인다.
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [key, bv] of Object.entries(HOSTS)) {
      await db.doc(`users/${key}`).set({
        identityVerified: true,
        accountStatus: 'active',
        businessVerification: bv,
      });
      await db.doc(`events/ev_${key}`).set({ hostId: key, name: '내 혼술바' });
      await db.doc(`places/pl_${key}`).set({ hostId: key, name: '내 파티룸' });
    }
    await db.doc(`users/${OTHER}`).set({
      identityVerified: true,
      accountStatus: 'active',
      businessVerification: { status: 'verified', authorization: 'self' },
    });
    await db.doc(`events/ev_other`).set({ hostId: OTHER, name: '남의 혼술바' });
    await db.doc(`places/pl_other`).set({ hostId: OTHER, name: '남의 파티룸' });

    // 본인확인을 마치지 않은 계정 · 탈퇴 대기 계정 — 둘 다 자기 플레이스가 있다.
    await db.doc('users/no-identity').set({
      identityVerified: false,
      accountStatus: 'active',
      businessVerification: { status: 'verified', authorization: 'self' },
    });
    await db.doc('events/ev_no-identity').set({ hostId: 'no-identity', name: '가게' });
    await db.doc('users/withdrawing').set({
      identityVerified: true,
      accountStatus: 'withdrawal_pending',
      businessVerification: { status: 'verified', authorization: 'self' },
    });
    await db.doc('events/ev_withdrawing').set({ hostId: 'withdrawing', name: '가게' });

    // 수정·삭제 시나리오용 기존 이벤트.
    await db.doc('placePromotions/p_mine').set(promo('ev_self', 'events', 'self'));
    await db.doc('placePromotions/p_theirs').set(promo('ev_other', 'events', OTHER));
  });

  let seq = 0;
  const create = async (uid, data) => {
    seq += 1;
    try {
      await env.authenticatedContext(uid).firestore()
        .doc(`placePromotions/n_${seq}`).set(data);
      return true;
    } catch (_) {
      return false;
    }
  };

  // ── 권한 축이 달라도 자기 플레이스면 만들 수 있다 ──────────────────────
  //
  // events(매장·즐길거리)와 places(공간대여·숙박) **두 부모 유형 모두** 본다.
  for (const key of Object.keys(HOSTS)) {
    const bv = HOSTS[key];
    const label = bv.authorization
      ? `${bv.status}+${bv.authorization}`
      : `${bv.status}+권한없음`;
    record(
      `에뮬: [${label}] 내 events 플레이스에 이벤트 생성 → 허용`,
      await create(key, promo(`ev_${key}`, 'events', key)) === true,
    );
    record(
      `에뮬: [${label}] 내 places 플레이스에 이벤트 생성 → 허용`,
      await create(key, promo(`pl_${key}`, 'places', key)) === true,
    );
  }

  // ── 소유권 — 여기가 실제 관문이다 ─────────────────────────────────────
  record(
    '에뮬: 남의 events 플레이스에는 만들지 못한다',
    await create('self', promo('ev_other', 'events', 'self')) === false,
  );
  record(
    '에뮬: 남의 places 플레이스에는 만들지 못한다',
    await create('self', promo('pl_other', 'places', 'self')) === false,
  );
  record(
    '에뮬: hostId를 남으로 적어도 만들지 못한다',
    await create('self', promo('ev_self', 'events', OTHER)) === false,
  );
  record(
    '에뮬: 없는 부모(orphan)에는 만들지 못한다',
    await create('self', promo('ev_does-not-exist', 'events', 'self')) === false,
  );
  record(
    '에뮬: 부모 컬렉션이 places/events가 아니면 만들지 못한다',
    await create('self', promo('ev_self', 'placeRooms', 'self')) === false,
  );
  record(
    '에뮬: 부모 컬렉션이 빈 문자열이면 만들지 못한다',
    await create('self', promo('ev_self', '', 'self')) === false,
  );
  record(
    '에뮬: placeId가 비면 만들지 못한다',
    await create('self', promo('', 'events', 'self')) === false,
  );

  // 필드가 **아예 없는** 경우 — 규칙이 `.get()` 없이 직접 참조하므로 평가
  // 오류가 되어 거부된다. 거부라는 결과는 같지만, 열려 있지 않은지 확인한다.
  const withoutField = (field) => {
    const d = promo('ev_self', 'events', 'self');
    delete d[field];
    return d;
  };
  record(
    '에뮬: placeId 필드가 없으면 만들지 못한다',
    await create('self', withoutField('placeId')) === false,
  );
  record(
    '에뮬: placeCollection 필드가 없으면 만들지 못한다',
    await create('self', withoutField('placeCollection')) === false,
  );
  record(
    '에뮬: hostId 필드가 없으면 만들지 못한다',
    await create('self', withoutField('hostId')) === false,
  );

  // ── 계정 상태 ─────────────────────────────────────────────────────────
  record(
    '에뮬: 본인확인을 마치지 않은 계정은 만들지 못한다',
    await create('no-identity', promo('ev_no-identity', 'events', 'no-identity')) === false,
  );
  record(
    '에뮬: 탈퇴 대기 계정은 만들지 못한다',
    await create('withdrawing', promo('ev_withdrawing', 'events', 'withdrawing')) === false,
  );

  let anonBlocked = false;
  try {
    await env.unauthenticatedContext().firestore()
      .doc('placePromotions/anon').set(promo('ev_self', 'events', 'self'));
  } catch (_) { anonBlocked = true; }
  record('에뮬: 비로그인은 만들지 못한다', anonBlocked);

  // ── 읽기 · 수정 · 삭제 ────────────────────────────────────────────────
  let publicRead = false;
  try {
    await env.unauthenticatedContext().firestore()
      .doc('placePromotions/p_mine').get();
    publicRead = true;
  } catch (_) {}
  record('에뮬: 이벤트는 비로그인도 읽는다(손님 화면)', publicRead);

  const selfDb = env.authenticatedContext('self').firestore();
  const tryIt = async (fn) => {
    try { await fn(); return true; } catch (_) { return false; }
  };
  record(
    '에뮬: 내 이벤트는 수정할 수 있다',
    await tryIt(() => selfDb.doc('placePromotions/p_mine').update({ title: '바꿈' })) === true,
  );
  record(
    '에뮬: 남의 이벤트는 수정하지 못한다',
    await tryIt(() => selfDb.doc('placePromotions/p_theirs').update({ title: '바꿈' })) === false,
  );
  record(
    '에뮬: 수정하면서 남의 플레이스로 옮겨 붙이지 못한다',
    await tryIt(() => selfDb.doc('placePromotions/p_mine').update({ placeId: 'ev_other' })) === false,
  );
  record(
    '에뮬: 수정하면서 hostId를 바꾸지 못한다',
    await tryIt(() => selfDb.doc('placePromotions/p_mine').update({ hostId: OTHER })) === false,
  );
  record(
    '에뮬: 남의 이벤트는 삭제하지 못한다',
    await tryIt(() => selfDb.doc('placePromotions/p_theirs').delete()) === false,
  );
  record(
    '에뮬: 내 이벤트는 삭제할 수 있다',
    await tryIt(() => selfDb.doc('placePromotions/p_mine').delete()) === true,
  );

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
    console.log('      npm i -D @firebase/rules-unit-testing');
    console.log('      firebase emulators:exec --only firestore "node placeEventRules.selfcheck.js"');
  }

  const total = cases.length + emulatorCount;
  console.log(
    failed === 0
      ? `\n이벤트 저장 규칙 검증 통과 — ${total}건`
        + (skipReason ? ` (드리프트 ${cases.length}건만, 에뮬레이터 미실행)` : '')
      : `\n실패 ${failed}건 / 전체 ${total}건`,
  );
  process.exit(failed === 0 ? 0 : 1);
})();

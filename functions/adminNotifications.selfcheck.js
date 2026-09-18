// 관리자 업무 알림 자체 검증 — `npm run check:adminnotif`.
//
// 여기서 못 박는 것.
//
// 1. **신규 신청 하나에 알림 하나.** 같은 신청서를 몇 번 다시 써도 알림은
//    늘지 않는다(결정적 id + 트랜잭션).
// 2. **기존 신청서에는 소급 알림이 생기지 않는다.** 이 기능을 켜기 전에
//    쌓여 있던 신청(운영 3건)을 수정·재저장해도 알림이 만들어지면 안 된다.
// 3. **내용 보완이 읽음을 지우지 않는다.** import가 끝나 업체명이 채워질 때
//    고치는 것은 title·body뿐이고 readBy는 그대로다.
// 4. **관리자가 여럿이어도 읽음이 서로 섞이지 않는다.** readBy는 배열이고,
//    규칙이 자기 uid만 넣도록 막는다.
// 5. **일반 사용자는 문서의 존재조차 알 수 없다.**
//
// 이 파일은 **두 층**이다(feedbackRules.selfcheck.js와 같은 구성).
//
//   ① 로직·드리프트 검사 (항상 실행, 에뮬레이터 불필요)
//   ② 에뮬레이터 규칙 검증 (Firestore 에뮬레이터가 있을 때만)
//      실행:  firebase emulators:exec --only firestore \
//               "node adminNotifications.selfcheck.js"
//      없으면 ①만 돌고 **건너뛴 사실을 명시적으로 출력한다.**

process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'selfcheck';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const rules = fs.readFileSync(path.join(ROOT, 'firestore.rules'), 'utf8');

const {
  ADMIN_NOTIFICATION_TYPE,
  NOTIFY_FROM_MS,
  buildHostPreRegistrationBody,
  buildHostPreRegistrationNotification,
  decide,
  notificationIdFor,
  shouldNotifyForCreate,
  toMillis,
} = require('./adminNotifications').__helpers;

const cases = [];
const test = (name, fn) => cases.push([name, fn]);

/** Firestore Timestamp 흉내 — 트리거가 실제로 받는 모양. */
const tsOf = (iso) => ({ toMillis: () => Date.parse(iso) });

/** 운영에 실제로 있는 과거 신청 3건의 접수 시각(읽기 전용 조회로 확인한 값). */
const EXISTING = [
  '2026-09-13T16:08:37.309Z',
  '2026-09-15T07:52:46.594Z',
  '2026-09-17T03:18:08.480Z',
];

// ══════════════════════════════════════════════════════════════════════════
// ① 로직 검사
// ══════════════════════════════════════════════════════════════════════════

test('신규 접수 → 알림을 만든다', () => {
  const d = { submittedAt: tsOf('2026-09-20T01:00:00Z'), storeName: '파티츄 홍대점' };
  assert.deepStrictEqual(
    decide({ beforeExists: false, afterExists: true, afterData: d }),
    { action: 'create', reason: 'new' },
  );
});

test('같은 신청서를 다시 써도(update) 알림을 새로 만들지 않는다', () => {
  const d = { submittedAt: tsOf('2026-09-20T01:00:00Z') };
  const out = decide({ beforeExists: true, afterExists: true, afterData: d });
  assert.strictEqual(out.action, 'enrich', '수정은 보완이어야 한다');
  assert.notStrictEqual(out.action, 'create');
});

test('문서 삭제는 아무것도 하지 않는다', () => {
  const out = decide({ beforeExists: true, afterExists: false, afterData: {} });
  assert.strictEqual(out.action, 'skip');
});

test('기능 도입 전 신청(운영 3건)은 새로 생성돼도 알림 대상이 아니다', () => {
  for (const iso of EXISTING) {
    const d = { submittedAt: tsOf(iso) };
    assert.strictEqual(
      shouldNotifyForCreate(d),
      false,
      `${iso}는 컷오프 이전이라 알리면 안 된다`,
    );
    assert.strictEqual(
      decide({ beforeExists: false, afterExists: true, afterData: d }).action,
      'skip',
    );
  }
});

test('기존 문서를 수정하면 create가 아니라 enrich다 — 신규로 오인하지 않는다', () => {
  // 운영 3건을 관리자가 처리(status 변경)하는 상황 그대로.
  for (const iso of EXISTING) {
    const out = decide({
      beforeExists: true,
      afterExists: true,
      afterData: { submittedAt: tsOf(iso), status: 'preregistered' },
    });
    assert.strictEqual(out.action, 'enrich');
  }
  // 그리고 enrich는 알림이 없으면 아무것도 만들지 않는다 — 그 보장은
  // 트리거 본체의 `if (!snap.exists) return 'noNotification'`이다.
  const src = fs.readFileSync(path.join(__dirname, 'adminNotifications.js'), 'utf8');
  assert.ok(
    /if \(!snap\.exists\) return 'noNotification'/.test(src),
    'enrich 경로가 알림을 새로 만들지 않는다는 보장이 코드에서 사라졌다',
  );
});

test('접수 시각을 읽을 수 없으면 알리지 않는다', () => {
  assert.strictEqual(shouldNotifyForCreate({}), false);
  assert.strictEqual(shouldNotifyForCreate({ submittedAt: null }), false);
});

test('createdAt만 있어도 컷오프를 판정한다', () => {
  assert.strictEqual(
    shouldNotifyForCreate({ createdAt: tsOf('2026-09-25T00:00:00Z') }),
    true,
  );
  assert.strictEqual(
    shouldNotifyForCreate({ createdAt: tsOf('2026-09-01T00:00:00Z') }),
    false,
  );
});

test('컷오프는 운영에 있는 마지막 과거 신청보다 뒤에 있다', () => {
  const newest = Math.max(...EXISTING.map(Date.parse));
  assert.ok(
    NOTIFY_FROM_MS > newest,
    `컷오프(${new Date(NOTIFY_FROM_MS).toISOString()})가 과거 신청을 덮지 못한다`,
  );
});

test('toMillis는 Timestamp·Date·number를 모두 읽는다', () => {
  assert.strictEqual(toMillis(tsOf('2026-09-20T00:00:00Z')), Date.parse('2026-09-20T00:00:00Z'));
  assert.strictEqual(toMillis(new Date(1700000000000)), 1700000000000);
  assert.strictEqual(toMillis(1700000000000), 1700000000000);
  assert.strictEqual(toMillis({ _seconds: 1700000000 }), 1700000000000);
  assert.strictEqual(toMillis(undefined), null);
});

test('알림 id는 신청서 id에서 결정적으로 나온다', () => {
  const a = notificationIdFor(ADMIN_NOTIFICATION_TYPE.hostPreRegistration, 'formhug_Sbyrul_9');
  const b = notificationIdFor(ADMIN_NOTIFICATION_TYPE.hostPreRegistration, 'formhug_Sbyrul_9');
  assert.strictEqual(a, b, '같은 신청서는 항상 같은 알림 문서를 가리켜야 한다');
  assert.notStrictEqual(
    a,
    notificationIdFor(ADMIN_NOTIFICATION_TYPE.hostPreRegistration, 'formhug_Sbyrul_10'),
  );
});

test('업체명이 없으면 업체명 없는 문구로 먼저 알린다', () => {
  assert.strictEqual(
    buildHostPreRegistrationBody({ importState: 'pending' }),
    '새로운 호스트 사전등록 신청이 들어왔습니다.',
  );
});

test('업체명이 채워지면 문구에 들어간다', () => {
  assert.strictEqual(
    buildHostPreRegistrationBody({ storeName: '파티츄 홍대점' }),
    '파티츄 홍대점에서 새로운 사전등록 신청이 들어왔습니다.',
  );
});

test('알림 본문에는 신청자 개인정보가 들어가지 않는다', () => {
  const n = buildHostPreRegistrationNotification('formhug_Sbyrul_9', {
    storeName: '파티츄 홍대점',
    hostName: '박효정',
    hostEmail: 'host@example.com',
    hostPhone: '01012345678',
    businessRegistrationNumber: '1234567890',
  });
  const blob = JSON.stringify(n);
  for (const secret of ['박효정', 'host@example.com', '01012345678', '1234567890']) {
    assert.ok(!blob.includes(secret), `알림에 ${secret}가 들어갔다`);
  }
});

test('알림은 갈 곳(refCollection·refId)을 항상 들고 있다', () => {
  const n = buildHostPreRegistrationNotification('formhug_Sbyrul_9', {});
  assert.strictEqual(n.refCollection, 'hostPreRegistrations');
  assert.strictEqual(n.refId, 'formhug_Sbyrul_9');
});

// ── 드리프트: 규칙 ↔ 코드 ──────────────────────────────────────────────────

/** adminNotifications의 match 블록 본문. */
function adminNotifBlock() {
  const i = rules.indexOf('match /adminNotifications/');
  assert.notStrictEqual(i, -1, 'adminNotifications 규칙 블록이 없다');
  const end = rules.indexOf('\n    }\n', i);
  assert.notStrictEqual(end, -1, '블록을 닫지 못했다');
  const block = rules.slice(i, end);
  assert.ok(block.includes('allow update'), '블록을 너무 일찍 잘랐다');
  return block;
}

test('규칙: 읽기는 관리자만', () => {
  assert.ok(/allow read: if isAdmin\(\);/.test(adminNotifBlock()));
});

test('규칙: 생성·삭제는 클라이언트가 못 한다', () => {
  assert.ok(/allow create, delete: if false;/.test(adminNotifBlock()));
});

test('규칙: update는 readBy 한 칸만 건드릴 수 있다', () => {
  const block = adminNotifBlock();
  assert.ok(block.includes("hasOnly(['readBy'])"), 'readBy 외 필드가 열려 있다');
});

test('규칙: 남의 uid를 빼거나 대신 넣을 수 없다', () => {
  const block = adminNotifBlock();
  assert.ok(
    block.includes('resource.data.readBy.hasOnly(request.resource.data.readBy)'),
    '이미 읽은 uid를 지울 수 있다',
  );
  assert.ok(
    block.includes('concat([uid()])'),
    '자기 uid 외의 값을 넣을 수 있다',
  );
});

test('사용자 알림(notifications)과 컬렉션이 분리돼 있다', () => {
  const src = fs.readFileSync(path.join(__dirname, 'adminNotifications.js'), 'utf8');
  assert.ok(
    !/collection\('notifications'\)/.test(src),
    '관리자 알림이 사용자 알림 컬렉션에 쓰고 있다 — FCM이 관리자 폰으로 나간다',
  );
  assert.ok(/const COLLECTION = 'adminNotifications'/.test(src));
});

test('index.js가 새 트리거를 실제로 내보낸다', () => {
  const index = fs.readFileSync(path.join(__dirname, 'index.js'), 'utf8');
  assert.ok(
    /exports\.onHostPreRegistrationWriteNotifyAdmin/.test(index),
    'index.js에 export가 없으면 배포해도 트리거가 생기지 않는다',
  );
});

// ══════════════════════════════════════════════════════════════════════════
// ② 에뮬레이터 규칙 검증
// ══════════════════════════════════════════════════════════════════════════

const ADMIN_A = 'uidAdminA';
const ADMIN_B = 'uidAdminB';
const USER = 'uidUser';
const NOTIF = 'host_pre_registration__formhug_Sbyrul_9';

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
    projectId: 'partychu-admin-notifications',
    firestore: { rules },
  });

  const seed = async (readBy = []) => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc(`users/${ADMIN_A}`).set({ accountStatus: 'active', role: 'admin' });
      await db.doc(`users/${ADMIN_B}`).set({ accountStatus: 'active', role: 'admin' });
      await db.doc(`users/${USER}`).set({ accountStatus: 'active', identityVerified: true });
      await db.doc(`adminNotifications/${NOTIF}`).set({
        type: 'host_pre_registration',
        title: '새로운 사전등록 신청',
        body: '파티츄 홍대점에서 새로운 사전등록 신청이 들어왔습니다.',
        refCollection: 'hostPreRegistrations',
        refId: 'formhug_Sbyrul_9',
        readBy,
        createdAt: new Date(),
      });
    });
  };

  const docFor = (uid) =>
    env.authenticatedContext(uid).firestore().doc(`adminNotifications/${NOTIF}`);

  const ok = async (name, fn) => {
    try {
      await testing.assertSucceeds(fn());
      record(name, true);
    } catch (e) {
      record(`${name}\n    ${e.message}`, false);
    }
  };
  const denied = async (name, fn) => {
    try {
      await testing.assertFails(fn());
      record(name, true);
    } catch (e) {
      record(`${name}\n    ${e.message}`, false);
    }
  };

  await seed();

  // ── 읽기 ──────────────────────────────────────────────────────────────
  await ok('관리자는 알림을 읽는다', () => docFor(ADMIN_A).get());
  await denied('일반 사용자는 알림을 읽지 못한다', () => docFor(USER).get());
  await denied('비로그인은 알림을 읽지 못한다', () =>
    env.unauthenticatedContext().firestore().doc(`adminNotifications/${NOTIF}`).get(),
  );
  await denied('일반 사용자는 목록도 못 읽는다', () =>
    env.authenticatedContext(USER).firestore().collection('adminNotifications').get(),
  );

  // ── 읽음 표시 ─────────────────────────────────────────────────────────
  // 규칙은 값의 최종 모양만 보므로, arrayUnion 대신 결과 배열을 그대로 써서
  // "무엇을 넣고 무엇을 뺐는지"가 케이스에 드러나게 한다.
  await ok('관리자는 자기 uid를 readBy에 넣는다', () =>
    docFor(ADMIN_A).update({ readBy: [ADMIN_A] }),
  );

  await seed([ADMIN_A]);
  await ok('다른 관리자도 자기 uid를 덧붙일 수 있다', () =>
    docFor(ADMIN_B).update({ readBy: [ADMIN_A, ADMIN_B] }),
  );

  await seed([ADMIN_A]);
  await denied('남이 읽은 표시를 지울 수 없다', () =>
    docFor(ADMIN_B).update({ readBy: [ADMIN_B] }),
  );

  await seed();
  await denied('남을 대신해 읽음 처리할 수 없다', () =>
    docFor(ADMIN_A).update({ readBy: [ADMIN_B] }),
  );

  await seed();
  await denied('일반 사용자는 읽음 처리도 못 한다', () =>
    docFor(USER).update({ readBy: [USER] }),
  );

  // ── 본문 보호 ─────────────────────────────────────────────────────────
  await seed();
  await denied('관리자도 알림 문구를 고칠 수 없다', () =>
    docFor(ADMIN_A).update({ title: '조작된 제목' }),
  );
  await denied('readBy와 함께여도 다른 칸은 못 고친다', () =>
    docFor(ADMIN_A).update({ readBy: [ADMIN_A], refId: 'formhug_Sbyrul_1' }),
  );
  await denied('관리자도 알림을 만들 수 없다', () =>
    env
      .authenticatedContext(ADMIN_A)
      .firestore()
      .doc('adminNotifications/fabricated')
      .set({ type: 'x', title: 'x', body: 'x', readBy: [] }),
  );
  await denied('관리자도 알림을 지울 수 없다', () => docFor(ADMIN_A).delete());

  await env.cleanup();
  return null;
}

// ══════════════════════════════════════════════════════════════════════════

(async () => {
  console.log('관리자 업무 알림 검증\n');
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
  const record = (name, okFlag) => {
    emulatorCount += 1;
    if (okFlag) console.log(`  ✓ ${name}`);
    else {
      failed += 1;
      console.error(`  ✗ ${name}`);
    }
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
    console.log('      firebase emulators:exec --only firestore "node adminNotifications.selfcheck.js"');
  }

  const total = cases.length + emulatorCount;
  console.log(
    failed === 0
      ? `\n관리자 업무 알림 검증 통과 — ${total}건`
        + (skipReason ? ` (로직 ${cases.length}건만, 에뮬레이터 미실행)` : '')
      : `\n실패 ${failed}건 / 전체 ${total}건`,
  );
  process.exit(failed === 0 ? 0 : 1);
})();

// 고객센터 문의 규칙 검증 — `npm run check:feedbackrules`.
//
// `feedbackRequests`는 개선 제안·버그 신고·고객센터 문의가 **한 컬렉션에
// 유형(type)으로만** 갈려 쌓이는 자리다. 그리고 고객센터 문의부터는 작성자가
// 직접 적은 **답변용 연락처**(contactEmail · contactPhone)가 문서 안에 들어
// 있다 — 목록 읽기가 한 번이라도 열리면 그 연락처가 통째로 새는 구조다.
//
// 이 파일은 **두 층**이다(businessRules.selfcheck.js와 같은 구성).
//
//   ① 드리프트 검사 (항상 실행, 에뮬레이터 불필요)
//      유형 목록이 세 곳에 각자의 문법으로 적혀 있다 —
//        · firestore.rules의 create 화이트리스트
//        · party_app/lib/models/feedback_request.dart의 FeedbackType
//        · admin_app/lib/screens/feedback_requests_screen.dart의 _typeLabels
//      한 곳만 고치면 "앱은 보내는데 규칙이 막는" 또는 "규칙은 받는데 관리자
//      화면이 영문 키를 그대로 띄우는" 상태가 조용히 만들어진다.
//
//   ② 에뮬레이터 검증 (Firestore 에뮬레이터가 있을 때만)
//      준비:  npm i -D @firebase/rules-unit-testing   (+ Java 필요)
//      실행:  firebase emulators:exec --only firestore \
//               "node feedbackRules.selfcheck.js"
//      없으면 ①만 돌고 **건너뛴 사실을 명시적으로 출력한다.**

process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'selfcheck';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const rules = fs.readFileSync(path.join(ROOT, 'firestore.rules'), 'utf8');
const modelDart = fs.readFileSync(
  path.join(ROOT, 'party_app', 'lib', 'models', 'feedback_request.dart'),
  'utf8',
);
const adminDart = fs.readFileSync(
  path.join(ROOT, 'admin_app', 'lib', 'screens', 'feedback_requests_screen.dart'),
  'utf8',
);

const cases = [];
const test = (name, fn) => cases.push([name, fn]);

// ══════════════════════════════════════════════════════════════════════════
// ① 드리프트 검사 — 규칙 ↔ 앱 모델 ↔ 관리자 화면
// ══════════════════════════════════════════════════════════════════════════

/// feedbackRequests의 match 블록 본문.
///
/// ⚠️ 반드시 이 블록 안에서만 찾아야 한다 — `type in [...]`은 블록 **바깥**의
///    feedbackContactOk()에도 있고(연락처 필수 유형), 파일 전체를 훑으면 그쪽이
///    먼저 걸려 화이트리스트를 두 개짜리로 잘못 읽는다.
function feedbackBlock() {
  const i = rules.indexOf('match /feedbackRequests/');
  assert.notStrictEqual(i, -1, 'feedbackRequests 규칙 블록이 없다');
  const end = rules.indexOf('\n    }\n', i);
  assert.notStrictEqual(end, -1, 'feedbackRequests 블록을 닫지 못했다');
  const block = rules.slice(i, end);
  assert.ok(block.includes('allow delete'), '블록을 너무 일찍 잘랐다');
  return block;
}

/// 규칙의 create 화이트리스트에 적힌 유형들.
function ruleTypes() {
  const m = feedbackBlock().match(
    /request\.resource\.data\.type in\s*\n?\s*\[([^\]]+)\]/,
  );
  assert.ok(m, '규칙에서 feedbackRequests의 type 화이트리스트를 찾지 못했다');
  return [...m[1].matchAll(/'([a-zA-Z]+)'/g)].map((x) => x[1]).sort();
}

/// party_app FeedbackType이 선언한 값들(상수 선언 자체에서 읽는다).
function modelTypes() {
  const body = modelDart.slice(
    modelDart.indexOf('class FeedbackType'),
    modelDart.indexOf('class FeedbackContact'),
  );
  assert.ok(body.length > 0, 'FeedbackType 클래스를 찾지 못했다');
  return [...body.matchAll(/static const \w+ = '([a-zA-Z]+)';/g)]
    .map((x) => x[1])
    .sort();
}

/// admin_app의 _typeLabels 키들.
function adminTypes() {
  const i = adminDart.indexOf('const _typeLabels');
  assert.notStrictEqual(i, -1, '관리자 화면에서 _typeLabels를 찾지 못했다');
  const block = adminDart.slice(i, adminDart.indexOf('};', i));
  return [...block.matchAll(/'([a-zA-Z]+)':/g)].map((x) => x[1]).sort();
}

test('유형 목록이 규칙·앱 모델·관리자 화면에서 같다', () => {
  const r = ruleTypes();
  assert.deepStrictEqual(modelTypes(), r, '앱 모델과 규칙의 유형이 어긋났다');
  assert.deepStrictEqual(adminTypes(), r, '관리자 화면과 규칙의 유형이 어긋났다');
});

test('옛 문서가 쓰던 유형이 화이트리스트에서 빠지지 않았다', () => {
  // improvement/bug/inquiry/other는 고객센터 문의 이전에 접수된 문서의 값이다.
  // 빠지면 그 유형의 재접수만 막히고, 관리자 화면에서 라벨도 잃는다.
  for (const t of ['improvement', 'bug', 'inquiry', 'other']) {
    assert.ok(ruleTypes().includes(t), `규칙에서 '${t}'가 사라졌다`);
  }
});

test('연락처 필수 유형이 앱과 규칙에서 같다', () => {
  // 앱: FeedbackType.contactRequired에 적힌 상수 이름 → 그 상수의 값.
  const m = modelDart.match(/contactRequired = \[([^\]]+)\]/);
  assert.ok(m, '모델에 contactRequired가 없다');
  const appList = [...m[1].matchAll(/([a-zA-Z]\w*)/g)]
    .map((x) => {
      const v = modelDart.match(
        new RegExp(`static const ${x[1]} = '([a-zA-Z]+)';`),
      );
      assert.ok(v, `FeedbackType.${x[1]} 상수를 찾지 못했다`);
      return v[1];
    })
    .sort();

  // 규칙: feedbackContactOk() 안의 필수 조건.
  const i = rules.indexOf('function feedbackContactOk()');
  assert.notStrictEqual(i, -1, 'feedbackContactOk()가 없다');
  const body = rules.slice(i, rules.indexOf('\n    }', i));
  const r = body.match(/request\.resource\.data\.type in \[([^\]]+)\]/);
  assert.ok(r, '규칙에 연락처 필수 유형 목록이 없다');
  const ruleList = [...r[1].matchAll(/'([a-zA-Z]+)'/g)].map((x) => x[1]).sort();

  assert.deepStrictEqual(
    appList,
    ruleList,
    '연락처를 필수로 받는 유형이 앱과 규칙에서 어긋났다',
  );
  // 필수 유형은 **구버전 앱이 만들 수 없는 값**이어야 한다. 옛 유형에 필수를
  // 걸면 규칙 배포 순간 스토어의 구버전 앱이 막힌다(파일 상단 주석).
  for (const t of ruleList) {
    assert.ok(
      !['improvement', 'bug', 'inquiry', 'other'].includes(t),
      `'${t}'는 구버전 앱도 보내는 유형이라 연락처를 필수로 걸면 안 된다`,
    );
  }
});

test('규칙이 연락처 두 필드의 타입을 본다', () => {
  const i = rules.indexOf('function feedbackContactOk()');
  assert.notStrictEqual(i, -1, 'feedbackContactOk()가 없다');
  const body = rules.slice(i, rules.indexOf('\n    }', i));
  assert.ok(
    body.includes("get('contactEmail', '') is string"),
    'contactEmail의 타입 검사가 없다',
  );
  assert.ok(
    body.includes("get('contactPhone', '') is string"),
    'contactPhone의 타입 검사가 없다',
  );
  assert.ok(body.includes('.size() > 0'), '빈 이메일을 걸러내지 않는다');
});

test('관리자 update 허용 필드에 연락처·원문이 없다', () => {
  // 여기에 contactEmail/content가 들어가는 순간 관리자가 문의를 위조할 수 있다.
  const m = feedbackBlock().match(/affectedKeys\(\)\.hasOnly\(\[([^\]]+)\]/);
  assert.ok(m, '관리자 update의 hasOnly 목록을 찾지 못했다');
  const allowed = [...m[1].matchAll(/'(\w+)'/g)].map((x) => x[1]).sort();
  assert.deepStrictEqual(allowed, ['adminMemo', 'status', 'updatedAt', 'userReply']);
});

test('읽기가 본인 또는 관리자로 좁혀져 있다', () => {
  const full = feedbackBlock();
  const block = full.slice(0, full.indexOf('allow create'));
  assert.ok(
    block.includes("resource.data.userId == uid()") && block.includes('isAdmin()'),
    '읽기 조건이 본인/관리자로 좁혀져 있지 않다 — 남의 연락처가 새어 나간다',
  );
  assert.ok(!/allow read:\s*if true/.test(block), '읽기가 전면 공개돼 있다');
});

test('앱 모델의 연락처 판정이 이메일·전화 둘 다 있다', () => {
  const body = modelDart.slice(modelDart.indexOf('class FeedbackContact'));
  assert.ok(body.includes('isValidEmail'), 'isValidEmail이 없다');
  assert.ok(body.includes('isValidPhoneOrEmpty'), 'isValidPhoneOrEmpty가 없다');
  // 전화번호는 선택 입력이다 — 빈 값을 유효로 보지 않으면 선택이 아니게 된다.
  assert.ok(
    /if \(v\.isEmpty\) return true;/.test(body),
    '빈 전화번호를 유효로 보지 않는다 — 선택 입력이 아니게 된다',
  );
});

// ══════════════════════════════════════════════════════════════════════════
// ② 에뮬레이터 검증 — 실제 규칙 엔진
// ══════════════════════════════════════════════════════════════════════════

const ME = 'uidMe';
const OTHER = 'uidOther';
const ADMIN = 'uidAdmin';

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
    projectId: 'partychu-feedback-rules',
    firestore: { rules },
  });

  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc(`users/${ME}`).set({ accountStatus: 'active', identityVerified: true });
    await db.doc(`users/${OTHER}`).set({ accountStatus: 'active', identityVerified: true });
    await db.doc(`users/${ADMIN}`).set({ accountStatus: 'active', role: 'admin' });
    // 남이 쓴 문의 — 연락처가 들어 있다. 이걸 못 읽는 것이 이 규칙의 요점이다.
    await db.doc('feedbackRequests/other1').set({
      userId: OTHER, type: 'payment', title: '결제 문의', content: '내용',
      contactEmail: 'other@example.com', contactPhone: '010-0000-0000',
      status: 'received', userReply: '', adminMemo: '',
    });
    // 고객센터 문의 도입 **이전** 문서 — 연락처 필드가 아예 없다.
    await db.doc('feedbackRequests/legacyMine').set({
      userId: ME, type: 'improvement', title: '옛 의견', content: '내용',
      status: 'received', userReply: '', adminMemo: '',
    });
  });

  let seq = 0;
  const asMe = () => env.authenticatedContext(ME).firestore();

  /// 이 payload로 문의를 만들 수 있는가.
  /// 값에 `undefined`를 주면 **그 필드가 아예 없는** 문서가 된다 — 구버전 앱을
  /// 흉내 내는 케이스라 빈 문자열과 구분해야 한다.
  const canCreate = async (patch, uid = ME) => {
    seq += 1;
    const doc = {
      userId: uid,
      type: 'inquiry',
      title: '제목',
      content: '내용',
      contactEmail: 'me@example.com',
      contactPhone: '010-1234-5678',
      status: 'received',
      userReply: '',
      adminMemo: '',
      ...patch,
    };
    for (const k of Object.keys(doc)) if (doc[k] === undefined) delete doc[k];
    try {
      await env.authenticatedContext(uid).firestore()
        .doc(`feedbackRequests/c_${seq}`).set(doc);
      return true;
    } catch (_) {
      return false;
    }
  };

  // ── 생성: 정상 경로 ───────────────────────────────────────────────────
  record('에뮬: 내 문의를 만들 수 있다(이용 문의 + 연락처)', await canCreate({}) === true);
  record('에뮬: 전화번호를 안 적어도 만들 수 있다(선택 입력)',
    await canCreate({ contactPhone: '' }) === true);
  for (const t of ['bug', 'inquiry', 'payment', 'host', 'other', 'improvement']) {
    record(`에뮬: 유형 '${t}'가 허용된다`, await canCreate({ type: t }) === true);
  }

  // ── 생성: 막혀야 하는 것 ──────────────────────────────────────────────
  record('에뮬: 남의 userId로는 만들 수 없다', await canCreate({ userId: OTHER }) === false);
  record('에뮬: status를 received가 아닌 값으로 시작할 수 없다',
    await canCreate({ status: 'answered' }) === false);
  record('에뮬: 접수하면서 답변을 미리 달 수 없다',
    await canCreate({ userReply: '이미 답변함' }) === false);
  record('에뮬: 접수하면서 관리자 메모를 달 수 없다',
    await canCreate({ adminMemo: '메모' }) === false);
  record('에뮬: 알 수 없는 유형은 거부된다',
    await canCreate({ type: 'refundDispute' }) === false);
  record('에뮬: contactEmail이 문자열이 아니면 거부된다',
    await canCreate({ contactEmail: 123 }) === false);
  record('에뮬: contactPhone이 문자열이 아니면 거부된다',
    await canCreate({ contactPhone: ['010'] }) === false);

  // ── 새 유형에서 연락처가 실제로 강제되는가 ────────────────────────────
  for (const t of ['payment', 'host']) {
    record(`에뮬: ${t}는 contactEmail이 비면 거부된다`,
      await canCreate({ type: t, contactEmail: '' }) === false);
    record(`에뮬: ${t}는 contactEmail 필드가 없으면 거부된다`,
      await canCreate({ type: t, contactEmail: undefined }) === false);
  }

  // ── 하위호환: 구버전 앱은 연락처 필드를 보내지 않는다 ─────────────────
  //
  // ⚠️ 이 두 건이 이 규칙 설계의 근거다. 규칙은 앱보다 먼저 배포되는데,
  //    전 유형에 연락처를 필수로 걸면 그 순간 스토어의 구버전 앱에서
  //    의견 보내기가 통째로 막힌다.
  for (const t of ['bug', 'improvement', 'inquiry', 'other']) {
    record(`에뮬: 구버전 앱의 '${t}'(연락처 필드 없음)가 그대로 통과한다`,
      await canCreate({ type: t, contactEmail: undefined, contactPhone: undefined }) === true);
  }

  // ── 읽기: 남의 연락처·내용은 보이지 않는다 ────────────────────────────
  const canRead = async (uid, id) => {
    try {
      await env.authenticatedContext(uid).firestore()
        .doc(`feedbackRequests/${id}`).get();
      return true;
    } catch (_) { return false; }
  };
  record('에뮬: 내 문의는 읽을 수 있다', await canRead(ME, 'legacyMine') === true);
  record('에뮬: 남의 문의는 읽을 수 없다(연락처·내용 보호)',
    await canRead(ME, 'other1') === false);

  const canQuery = async (uid, ownerUid) => {
    try {
      await env.authenticatedContext(uid).firestore()
        .collection('feedbackRequests').where('userId', '==', ownerUid).get();
      return true;
    } catch (_) { return false; }
  };
  record('에뮬: 내 문의 목록 쿼리는 된다', await canQuery(ME, ME) === true);
  record('에뮬: 남의 문의 목록 쿼리는 막힌다', await canQuery(ME, OTHER) === false);

  let listAllBlocked = false;
  try { await asMe().collection('feedbackRequests').get(); } catch (_) { listAllBlocked = true; }
  record('에뮬: 필터 없는 전체 목록 조회는 막힌다', listAllBlocked);

  // ── 작성자는 자기 글도 고치거나 지울 수 없다 ──────────────────────────
  const meBlocked = async (fn) => {
    try { await fn(); return false; } catch (_) { return true; }
  };
  record('에뮬: 작성자는 자기 문의를 수정할 수 없다',
    await meBlocked(() => asMe().doc('feedbackRequests/legacyMine').update({ content: '바꿈' })));
  record('에뮬: 작성자는 자기 문의를 삭제할 수 없다',
    await meBlocked(() => asMe().doc('feedbackRequests/legacyMine').delete()));
  record('에뮬: 작성자가 자기 문의를 처리완료로 바꿀 수 없다',
    await meBlocked(() => asMe().doc('feedbackRequests/legacyMine').update({ status: 'answered' })));

  // ── 관리자 — 기존 isAdmin() 판정 그대로 ───────────────────────────────
  const admin = env.authenticatedContext(ADMIN).firestore();
  record('에뮬: 관리자는 남의 문의를 읽을 수 있다', await canRead(ADMIN, 'other1') === true);

  let adminAllList = false;
  try { await admin.collection('feedbackRequests').get(); adminAllList = true; } catch (_) {}
  record('에뮬: 관리자는 전체 목록을 조회할 수 있다', adminAllList);

  let adminUpdateOk = false;
  try {
    await admin.doc('feedbackRequests/other1')
      .update({ status: 'reviewing', userReply: '답변', adminMemo: '메모' });
    adminUpdateOk = true;
  } catch (_) {}
  record('에뮬: 관리자는 상태·답변·메모를 고칠 수 있다', adminUpdateOk);

  const adminBlocked = async (patch) => {
    try { await admin.doc('feedbackRequests/other1').update(patch); return false; }
    catch (_) { return true; }
  };
  record('에뮬: 관리자도 연락처는 고칠 수 없다(위변조 방지)',
    await adminBlocked({ contactEmail: 'hijack@example.com' }));
  record('에뮬: 관리자도 문의 원문은 고칠 수 없다',
    await adminBlocked({ content: '바꿈' }));

  let adminDeleteOk = false;
  try { await admin.doc('feedbackRequests/other1').delete(); adminDeleteOk = true; } catch (_) {}
  record('에뮬: 관리자는 삭제할 수 있다', adminDeleteOk);

  // ── 비로그인 ──────────────────────────────────────────────────────────
  const anon = env.unauthenticatedContext().firestore();
  let anonReadBlocked = false;
  try { await anon.doc('feedbackRequests/legacyMine').get(); } catch (_) { anonReadBlocked = true; }
  record('에뮬: 비로그인은 아무 문의도 읽지 못한다', anonReadBlocked);

  let anonCreateBlocked = false;
  try {
    await anon.doc('feedbackRequests/anon1').set({
      userId: ME, type: 'inquiry', title: 't', content: 'c',
      contactEmail: 'a@b.co', contactPhone: '',
      status: 'received', userReply: '', adminMemo: '',
    });
  } catch (_) { anonCreateBlocked = true; }
  record('에뮬: 비로그인은 문의를 만들지 못한다', anonCreateBlocked);

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
    console.log('      firebase emulators:exec --only firestore "node feedbackRules.selfcheck.js"');
  }

  const total = cases.length + emulatorCount;
  console.log(
    failed === 0
      ? `\n고객센터 문의 규칙 검증 통과 — ${total}건`
        + (skipReason ? ` (드리프트 ${cases.length}건만, 에뮬레이터 미실행)` : '')
      : `\n실패 ${failed}건 / 전체 ${total}건`,
  );
  process.exit(failed === 0 ? 0 : 1);
})();

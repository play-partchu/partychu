// 매장 이벤트 신청 문서(placeEventApplications) **권한** 검증 —
// `npm run check:placeeventapps` (드리프트만)
// `npm run check:placeeventapps:emulator` (실제 규칙 엔진까지)
//
// ── 이 컬렉션의 권한 모델 ─────────────────────────────────────────────────
//   쓰기 : **아무도 못 한다.** Functions Admin SDK 전용
//          (parties/{partyId}/applications와 같은 보호 패턴)
//   읽기 : 신청한 본인 · 그 이벤트의 호스트 · 관리자
//
// 처음에는 클라이언트 create/update를 열고 위조만 막았다. 그런데 **종료된
// 이벤트를 막을 수 없었다** — 종료 판정은 `endAt`을 "그 날 23:59:59"로 접는
// 계산이고(PlacePromotion.statusAt), rules로 옮겨 적으면 하루의 경계에서 앱과
// 어긋난다. 판정을 서버로 모으면서 쓰기도 함께 닫았다.
//
// 그래서 아래 에뮬레이터 검증에서 **"정상적인 신청 write도 거부"**가 통과
// 케이스다. 신청이 실제로 만들어지는 경로는 콜러블이고, 그 판정은
// placeEventApplications.selfcheck.js가 본다. 이 파일이 보는 것은
// "앱이 서버를 건너뛸 수 있는가"와 "누가 무엇을 읽는가"다.
//
//   준비: npm i -D @firebase/rules-unit-testing   (+ Java 필요)
//   실행: firebase emulators:exec --only firestore \
//           "node placeEventApplicationRules.selfcheck.js"

process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'selfcheck';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const { COLLECTION } = require('./placeEventApplications');

const rules = fs.readFileSync(
  path.join(__dirname, '..', 'firestore.rules'),
  'utf8',
);

const cases = [];
const test = (name, fn) => cases.push([name, fn]);

// ══════════════════════════════════════════════════════════════════════════
// ① 드리프트 검사
// ══════════════════════════════════════════════════════════════════════════

function applicationBlock() {
  const i = rules.indexOf(`match /${COLLECTION}/`);
  assert.notStrictEqual(i, -1, `${COLLECTION} 규칙 블록이 없다`);
  const end = rules.indexOf('\n    }\n', i);
  const block = rules.slice(i, end);
  assert.ok(block.includes('allow'), '블록을 너무 일찍 잘랐다');
  return block;
}

test('컬렉션 이름이 파티 신청과 갈라져 있다', () => {
  // 이름을 공유하면 `/{path=**}/applications/{id}` 재귀 규칙과
  // collectionGroup('applications') 집계가 매장 이벤트 신청까지 파티 신청으로
  // 센다 — 탈퇴가 막히고 매출 통계에 빈 건이 섞인다.
  assert.strictEqual(COLLECTION, 'placeEventApplications');
  assert.ok(
    !COLLECTION.endsWith('/applications') && COLLECTION !== 'applications',
    '파티 신청 서브컬렉션과 이름이 겹친다',
  );
});

test('클라이언트 쓰기가 전면 차단되어 있다', () => {
  const b = applicationBlock();
  assert.ok(b.includes('allow write: if false'), '쓰기 차단이 사라졌다');
  // create/update/delete가 하나라도 다시 열리면 종료된 이벤트 차단이 통째로
  // 무력해진다 — 변조된 클라이언트가 서버 판정을 건너뛴다.
  for (const verb of ['create', 'update', 'delete']) {
    assert.ok(
      !b.includes(`allow ${verb}`),
      `allow ${verb}가 다시 열렸다 — 서버 판정을 건너뛸 수 있다`,
    );
  }
});

test('읽기는 본인 · 호스트 · 관리자뿐이다', () => {
  const b = applicationBlock();
  const at = b.indexOf('allow read:');
  assert.notStrictEqual(at, -1, 'read 규칙이 없다');
  const clause = b.slice(at, b.indexOf(';', at));
  assert.ok(clause.includes("resource.data.get('guestId', '') == uid()"));
  assert.ok(clause.includes("resource.data.get('hostId', '') == uid()"));
  assert.ok(clause.includes('isAdmin()'));
  assert.ok(!clause.includes('if true'), '신청 문서가 공개 읽기가 되었다');
});

test('원본 이벤트를 읽던 헬퍼가 남아 있지 않다', () => {
  // 클라이언트 create가 사라졌으므로 eventAcceptsApplication도 쓰이지 않는다.
  // 남아 있으면 "규칙이 아직 판정한다"는 착각을 준다.
  assert.ok(
    !rules.includes('function eventAcceptsApplication('),
    '죽은 헬퍼가 남아 있다',
  );
});

// ══════════════════════════════════════════════════════════════════════════
// ② 에뮬레이터 검증
// ══════════════════════════════════════════════════════════════════════════

const HOST = 'host-1';
const OTHER_HOST = 'host-2';
const GUEST = 'guest-1';
const OTHER_GUEST = 'guest-2';
const ADMIN = 'admin-1';

const EV = 'EV1'; // 신청을 받는 이벤트
const EV_NO_APPLY = 'EV2'; // 신청을 안 받는 이벤트
const EV_HIDDEN = 'EV3'; // 숨긴 이벤트
const EV_ENDED = 'EV4'; // 종료된 이벤트
const EV_OTHER = 'EV5'; // 남의 이벤트

function application(eventId, hostId, guestId, extra = {}) {
  return {
    eventId,
    placeId: 'PL1',
    placeCollection: 'events',
    hostId,
    guestId,
    eventTitle: '생일 이벤트',
    placeName: '혼술바',
    eventIsAlways: true,
    status: 'applied',
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
    projectId: 'partychu-place-event-applications',
    firestore: { rules },
  });

  // ── 전제 심기 ─────────────────────────────────────────────────────────
  // 신청 문서는 **규칙을 우회해** 심는다 — 실제로도 Admin SDK(콜러블)만
  // 만들 수 있는 문서라, 규칙을 거쳐 만들 방법 자체가 없다.
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const uid of [HOST, OTHER_HOST, GUEST, OTHER_GUEST]) {
      await db.doc(`users/${uid}`).set({
        identityVerified: true,
        accountStatus: 'active',
      });
    }
    await db.doc('users/no-identity').set({
      identityVerified: false,
      accountStatus: 'active',
    });
    await db.doc(`users/${ADMIN}`).set({
      identityVerified: true,
      accountStatus: 'active',
      role: 'admin',
    });

    const ev = (hostId, extra) => ({
      hostId,
      placeId: 'PL1',
      placeCollection: 'events',
      title: '생일 이벤트',
      isVisible: true,
      applyMode: 'apply',
      isAlways: true,
      ...extra,
    });
    await db.doc(`placePromotions/${EV}`).set(ev(HOST));
    await db.doc(`placePromotions/${EV_NO_APPLY}`).set(ev(HOST, { applyMode: 'none' }));
    await db.doc(`placePromotions/${EV_HIDDEN}`).set(ev(HOST, { isVisible: false }));
    await db.doc(`placePromotions/${EV_ENDED}`).set(
      ev(HOST, { isAlways: false, endAt: new Date('2020-01-02T00:00:00+09:00') }),
    );
    await db.doc(`placePromotions/${EV_OTHER}`).set(ev(OTHER_HOST));

    // 콜러블이 만들었다고 치는 신청 두 건 — 조회·수정 시나리오에 쓴다.
    await db.doc(`${COLLECTION}/${EV}_${GUEST}`).set(application(EV, HOST, GUEST));
    await db
      .doc(`${COLLECTION}/${EV}_${OTHER_GUEST}`)
      .set(application(EV, HOST, OTHER_GUEST));
    await db
      .doc(`${COLLECTION}/${EV_OTHER}_${GUEST}`)
      .set(application(EV_OTHER, OTHER_HOST, GUEST));
  });

  const ok = async (fn) => {
    try {
      await fn();
      return true;
    } catch (_) {
      return false;
    }
  };
  const as = (uid) => env.authenticatedContext(uid).firestore();
  const anon = () => env.unauthenticatedContext().firestore();
  const create = (db, docId, data) =>
    ok(() => db.doc(`${COLLECTION}/${docId}`).set(data));

  // ── 쓰기: 아무도 못 한다 ───────────────────────────────────────────────
  //
  // "정상적인 신청"조차 거부되는 것이 **의도**다 — 신청은 콜러블만 만든다.
  // 여기가 열리면 종료·숨김·applyMode 판정을 전부 건너뛸 수 있다.
  record(
    '에뮬: 흠잡을 데 없는 신청도 앱이 직접 쓰면 거부된다(서버가 정본)',
    (await create(as(GUEST), `${EV}_${GUEST}x`, application(EV, HOST, `${GUEST}x`))) === false,
  );
  record(
    '에뮬: 본인확인을 마친 게스트도 직접 쓰지 못한다',
    (await create(as(OTHER_GUEST), `${EV_NO_APPLY}_${OTHER_GUEST}`, application(EV_NO_APPLY, HOST, OTHER_GUEST))) === false,
  );
  record(
    '에뮬: 본인확인을 마치지 않은 계정도 당연히 못 쓴다',
    (await create(as('no-identity'), `${EV}_no-identity`, application(EV, HOST, 'no-identity'))) === false,
  );
  record(
    '에뮬: 비로그인은 못 쓴다',
    (await create(anon(), `${EV}_anon`, application(EV, HOST, 'anon'))) === false,
  );
  record(
    '에뮬: guestId를 남으로 위조해도 못 쓴다',
    (await create(as(GUEST), `${EV}_${OTHER_GUEST}z`, application(EV, HOST, OTHER_GUEST))) === false,
  );
  record(
    '에뮬: hostId를 내 uid로 위조해도 못 쓴다(조회 권한 자작 차단)',
    (await create(as(GUEST), `${EV}_${GUEST}y`, application(EV, GUEST, GUEST))) === false,
  );
  record(
    '에뮬: placeId를 위조해도 못 쓴다',
    (await create(as(GUEST), `${EV}_${GUEST}p`, application(EV, HOST, GUEST, { placeId: 'PL9' }))) === false,
  );
  record(
    '에뮬: 남의 eventId를 붙여도 못 쓴다',
    (await create(as(GUEST), `${EV_OTHER}_${GUEST}q`, application(EV_OTHER, OTHER_HOST, GUEST))) === false,
  );
  record(
    '에뮬: 숨긴 이벤트에 직접 쓰지 못한다',
    (await create(as(GUEST), `${EV_HIDDEN}_${GUEST}`, application(EV_HIDDEN, HOST, GUEST))) === false,
  );
  record(
    '에뮬: **종료된** 이벤트에 직접 쓰지 못한다',
    (await create(as(GUEST), `${EV_ENDED}_${GUEST}`, application(EV_ENDED, HOST, GUEST))) === false,
  );
  record(
    '에뮬: 호스트도 자기 이벤트에 신청을 직접 쓰지 못한다',
    (await create(as(HOST), `${EV}_${HOST}`, application(EV, HOST, HOST))) === false,
  );
  record(
    '에뮬: 관리자도 클라이언트로는 쓰지 못한다(Admin SDK 전용)',
    (await create(as(ADMIN), `${EV}_${ADMIN}`, application(EV, HOST, ADMIN))) === false,
  );

  // ── 수정 · 취소 · 삭제 ────────────────────────────────────────────────
  const mine = (uid, docId) => as(uid).doc(`${COLLECTION}/${docId}`);
  record(
    '에뮬: 내 신청도 앱이 직접 취소하지 못한다(콜러블만)',
    (await ok(() => mine(GUEST, `${EV}_${GUEST}`).update({ status: 'cancelled' }))) === false,
  );
  record(
    '에뮬: 남의 신청은 더욱 수정하지 못한다',
    (await ok(() => mine(GUEST, `${EV}_${OTHER_GUEST}`).update({ status: 'cancelled' }))) === false,
  );
  record(
    '에뮬: 수정으로 hostId를 바꾸지 못한다',
    (await ok(() => mine(GUEST, `${EV}_${GUEST}`).update({ hostId: GUEST }))) === false,
  );
  record(
    '에뮬: 게스트는 신청 문서를 지우지 못한다(취소 이력이 남아야 한다)',
    (await ok(() => mine(GUEST, `${EV}_${GUEST}`).delete())) === false,
  );
  record(
    '에뮬: 호스트도 신청 문서를 지우지 못한다',
    (await ok(() => mine(HOST, `${EV}_${GUEST}`).delete())) === false,
  );

  // ── 중복 방지 — 문서 id가 하나뿐이라는 성질 ────────────────────────────
  //
  // 서버가 두 번 써도(재시도·동시 호출) 문서는 하나다. 규칙이 아니라 **id
  // 형태**가 주는 성질이라, Admin SDK로 두 번 써서 확인한다.
  let dupCount = 0;
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const ref = db.doc(`${COLLECTION}/${EV}_dup-guest`);
    await ref.set(application(EV, HOST, 'dup-guest'));
    await ref.set(application(EV, HOST, 'dup-guest'));
    const snap = await db
      .collection(COLLECTION)
      .where('eventId', '==', EV)
      .where('guestId', '==', 'dup-guest')
      .get();
    dupCount = snap.size;
  });
  record('에뮬: 같은 사람이 두 번 신청해도 문서는 1개다', dupCount === 1);

  // ── 조회 ──────────────────────────────────────────────────────────────
  record(
    '에뮬: 게스트는 자기 신청을 읽는다',
    (await ok(() => mine(GUEST, `${EV}_${GUEST}`).get())) === true,
  );
  record(
    '에뮬: 게스트는 남의 신청을 읽지 못한다',
    (await ok(() => mine(GUEST, `${EV}_${OTHER_GUEST}`).get())) === false,
  );
  record(
    '에뮬: 비로그인은 신청을 읽지 못한다',
    (await ok(() => anon().doc(`${COLLECTION}/${EV}_${GUEST}`).get())) === false,
  );
  record(
    '에뮬: 호스트는 자기 이벤트 신청을 읽는다',
    (await ok(() => mine(HOST, `${EV}_${OTHER_GUEST}`).get())) === true,
  );
  record(
    '에뮬: 다른 호스트는 남의 이벤트 신청을 읽지 못한다',
    (await ok(() => mine(OTHER_HOST, `${EV}_${OTHER_GUEST}`).get())) === false,
  );
  record(
    '에뮬: 관리자는 읽을 수 있다(기존 정책 그대로)',
    (await ok(() => mine(ADMIN, `${EV}_${OTHER_GUEST}`).get())) === true,
  );

  // 목록 쿼리 — 앱이 실제로 거는 형태만 통과해야 한다.
  const list = (uid, q) => ok(() => q(as(uid).collection(COLLECTION)).get());
  record(
    '에뮬: 호스트는 hostId를 고정한 목록만 읽는다(관리 화면의 건수 쿼리)',
    (await list(HOST, (c) => c.where('hostId', '==', HOST).where('placeId', '==', 'PL1'))) === true,
  );
  record(
    '에뮬: hostId를 빼면 목록 조회가 막힌다',
    (await list(HOST, (c) => c.where('placeId', '==', 'PL1'))) === false,
  );
  record(
    '에뮬: 남의 hostId로는 목록을 읽지 못한다',
    (await list(OTHER_HOST, (c) => c.where('hostId', '==', HOST))) === false,
  );
  record(
    '에뮬: 게스트는 guestId를 고정한 내 신청 목록을 읽는다(신청 내역 화면)',
    (await list(GUEST, (c) => c.where('guestId', '==', GUEST))) === true,
  );
  record(
    '에뮬: 게스트가 남의 신청 목록을 조회하지 못한다',
    (await list(GUEST, (c) => c.where('guestId', '==', OTHER_GUEST))) === false,
  );
  record(
    '에뮬: 조건 없는 전체 조회는 막힌다',
    (await list(GUEST, (c) => c)) === false,
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
  const record = (name, okResult) => {
    emulatorCount += 1;
    if (okResult) console.log(`  ✓ ${name}`);
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
    console.log('      npm i -D @firebase/rules-unit-testing');
    console.log('      npm run check:placeeventapps:emulator');
  }

  const total = cases.length + emulatorCount;
  console.log(
    failed === 0
      ? `\n매장 이벤트 신청 권한 검증 통과 — ${total}건` +
          (skipReason ? ` (드리프트 ${cases.length}건만, 에뮬레이터 미실행)` : '')
      : `\n실패 ${failed}건 / 전체 ${total}건`,
  );
  process.exit(failed === 0 ? 0 : 1);
})();

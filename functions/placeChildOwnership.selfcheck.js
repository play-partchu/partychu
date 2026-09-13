'use strict';

// ─────────────────────────────────────────────────────────────────────────────
// placeRooms / placeProducts 소유 관문 — **에뮬레이터 행위 검증.**
//
// ⚠ 이 스크립트는 **배포 전 검증 대기 상태**다. 다른 selfcheck과 달리 순수
//   계산이 아니라 firestore.rules를 실제로 평가해야 하므로, Firestore
//   에뮬레이터와 @firebase/rules-unit-testing이 있어야 돌아간다. 규칙을 고쳤다면
//   배포 전에 반드시 이걸 통과시킨다 — 규칙은 컴파일만 되고 뜻이 뒤집혀도
//   조용히 배포된다.
//
//   준비:  npm i -D @firebase/rules-unit-testing
//   실행:  firebase emulators:exec --only firestore \
//            "node functions/placeChildOwnership.selfcheck.js"
//
//   에뮬레이터/의존성이 없으면 **실패가 아니라 '대기'로 끝난다**(exit 0 +
//   SKIPPED). CI에 얹을 때는 아래 REQUIRE_EMULATOR=1로 두어 건너뛰기를 금지한다.
//
// ── 무엇을 확인하나 ──────────────────────────────────────────────────────────
// 규칙 원문 구조는 party_app/test/place_child_docs_rules_test.dart가 항상 본다.
// 여기서는 **실제로 거부되는지**를 본다.
//
//   ownRoomCreate            자기 places 문서에 룸 생성        → 허용
//   foreignRoomCreate        남의 places 문서에 룸 생성        → 거부
//   missingParentRoomCreate  없는 placeId로 룸 생성(orphan)    → 거부
//   ownRoomUpdate/Delete     자기 플레이스의 룸 수정·삭제      → 허용
//   foreignRoomUpdate/Delete 남의 플레이스의 룸 수정·삭제      → 거부
//   movedRoomUpdate          룸의 placeId를 남의 것으로 변경   → 거부
//   ownProductCreate/Update  자기 플레이스의 상품 생성·수정    → 허용
//   foreignProductCreate     남의 플레이스에 상품 생성         → 거부
//   foreignProductDelete     남의 플레이스의 상품 삭제         → 거부
//   soldProductDelete        팔린 상품 삭제                    → 거부(기존 불변식)
//
// 부모 문서(places/events)는 Admin 권한(withSecurityRulesDisabled)으로 심는다 —
// 플레이스 생성 자체는 사업자 인증이 필요해서(events/places create의
// isBusinessVerified) 규칙을 거쳐 만들면 이 검사의 관심사와 섞인다.
// ─────────────────────────────────────────────────────────────────────────────

const REQUIRE_EMULATOR = process.env.REQUIRE_EMULATOR === '1';
const PROJECT_ID = 'partychu-rules-selfcheck';

const ME = 'host-me';
const OTHER = 'host-other';

/** 내 places 문서 / 남의 places 문서 / 남의 events 문서. */
const MY_PLACE = 'place-mine';
const THEIR_PLACE = 'place-theirs';
const THEIR_EVENT = 'event-theirs';
const MY_EVENT = 'event-mine';

function room(placeId, hostId) {
  return {
    placeId,
    hostId,
    roomName: '루프탑 A',
    capacityMin: 1,
    capacityMax: 8,
    pricePerHour: 20000,
    isActive: true,
  };
}

function product(placeId, placeCollection, hostId, extra) {
  return {
    placeId,
    placeCollection,
    hostId,
    name: '웰컴 드링크 이용권',
    price: 8000,
    soldCount: 0,
    sortOrder: 0,
    ...(extra || {}),
  };
}

async function main() {
  let testing;
  try {
    testing = require('@firebase/rules-unit-testing');
  } catch (_) {
    return skip('@firebase/rules-unit-testing이 설치돼 있지 않다');
  }
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    return skip('FIRESTORE_EMULATOR_HOST가 없다 — 에뮬레이터 밖에서 실행됐다');
  }

  const fs = require('fs');
  const path = require('path');
  const rules = fs.readFileSync(
    path.join(__dirname, '..', 'firestore.rules'),
    'utf8',
  );

  const env = await testing.initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules },
  });

  const results = [];
  const record = (name, ok, detail) => results.push({ name, ok, detail });

  /** 규칙을 우회해 전제 문서를 심는다. */
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    // 두 계정 모두 본인확인을 마친 회원이어야 isVerifiedMember를 통과한다.
    await db.doc(`users/${ME}`).set({
      identityVerified: true,
      accountStatus: 'active',
      // 권한은 status와 authorization 둘 다 있어야 열린다 — 규칙의
      // isBusinessVerified()가 두 값을 모두 본다(functions/businessVerification.js).
      businessVerification: { status: 'verified', authorization: 'self' },
    });
    await db.doc(`users/${OTHER}`).set({
      identityVerified: true,
      accountStatus: 'active',
      // 권한은 status와 authorization 둘 다 있어야 열린다 — 규칙의
      // isBusinessVerified()가 두 값을 모두 본다(functions/businessVerification.js).
      businessVerification: { status: 'verified', authorization: 'self' },
    });

    await db.doc(`places/${MY_PLACE}`).set({ hostId: ME, name: '내 파티룸' });
    await db.doc(`places/${THEIR_PLACE}`).set({ hostId: OTHER, name: '남의 파티룸' });
    await db.doc(`events/${MY_EVENT}`).set({ hostId: ME, name: '내 혼술바' });
    await db.doc(`events/${THEIR_EVENT}`).set({ hostId: OTHER, name: '남의 혼술바' });

    // 수정·삭제 시나리오용 기존 문서들.
    await db.doc('placeRooms/room-mine').set(room(MY_PLACE, ME));
    await db.doc('placeRooms/room-theirs').set(room(THEIR_PLACE, OTHER));
    await db.doc('placeProducts/product-mine').set(product(MY_PLACE, 'places', ME));
    await db.doc('placeProducts/product-theirs').set(
      product(THEIR_PLACE, 'places', OTHER),
    );
    await db.doc('placeProducts/product-sold').set(
      product(MY_PLACE, 'places', ME, { soldCount: 3 }),
    );
  });

  const meDb = env.authenticatedContext(ME).firestore();

  async function expectAllowed(name, promise) {
    try {
      await testing.assertSucceeds(promise);
      record(name, true);
    } catch (e) {
      record(name, false, `허용돼야 하는데 거부됐다: ${e.message}`);
    }
  }

  async function expectDenied(name, promise) {
    try {
      await testing.assertFails(promise);
      record(name, true);
    } catch (e) {
      record(name, false, `막혀야 하는데 통과했다: ${e.message}`);
    }
  }

  // ── 룸 생성 ───────────────────────────────────────────────────────────
  await expectAllowed(
    'ownRoomCreate',
    meDb.doc('placeRooms/new-own').set(room(MY_PLACE, ME)),
  );
  await expectDenied(
    'foreignRoomCreate',
    meDb.doc('placeRooms/new-foreign').set(room(THEIR_PLACE, ME)),
  );
  await expectDenied(
    'missingParentRoomCreate',
    meDb.doc('placeRooms/new-orphan').set(room('place-does-not-exist', ME)),
  );

  // ── 룸 수정·삭제 ──────────────────────────────────────────────────────
  await expectAllowed(
    'ownRoomUpdate',
    meDb.doc('placeRooms/room-mine').update({ roomName: '루프탑 B' }),
  );
  await expectDenied(
    'foreignRoomUpdate',
    meDb.doc('placeRooms/room-theirs').update({ roomName: '가로채기' }),
  );
  // 이미 붙인 룸을 남의 플레이스로 옮겨 붙이는 길도 막혀야 한다.
  await expectDenied(
    'movedRoomUpdate',
    meDb.doc('placeRooms/room-mine').update({ placeId: THEIR_PLACE }),
  );
  await expectDenied(
    'foreignRoomDelete',
    meDb.doc('placeRooms/room-theirs').delete(),
  );
  await expectAllowed(
    'ownRoomDelete',
    meDb.doc('placeRooms/room-mine').delete(),
  );

  // ── 상품 생성 ─────────────────────────────────────────────────────────
  await expectAllowed(
    'ownProductCreate',
    meDb.doc('placeProducts/new-own').set(product(MY_PLACE, 'places', ME)),
  );
  // 부모가 events인 쪽도 같은 관문을 지난다.
  await expectAllowed(
    'ownEventProductCreate',
    meDb.doc('placeProducts/new-own-event').set(product(MY_EVENT, 'events', ME)),
  );
  await expectDenied(
    'foreignProductCreate',
    meDb.doc('placeProducts/new-foreign').set(product(THEIR_PLACE, 'places', ME)),
  );
  await expectDenied(
    'foreignEventProductCreate',
    meDb
      .doc('placeProducts/new-foreign-event')
      .set(product(THEIR_EVENT, 'events', ME)),
  );
  await expectDenied(
    'missingParentProductCreate',
    meDb
      .doc('placeProducts/new-orphan')
      .set(product('place-does-not-exist', 'places', ME)),
  );

  // ── 상품 수정·삭제 ────────────────────────────────────────────────────
  await expectAllowed(
    'ownProductUpdate',
    meDb.doc('placeProducts/product-mine').update({ price: 9000 }),
  );
  await expectDenied(
    'foreignProductUpdate',
    meDb.doc('placeProducts/product-theirs').update({ price: 1 }),
  );
  await expectDenied(
    'movedProductUpdate',
    meDb.doc('placeProducts/product-mine').update({ placeId: THEIR_PLACE }),
  );
  await expectDenied(
    'foreignProductDelete',
    meDb.doc('placeProducts/product-theirs').delete(),
  );
  // 기존 불변식 — 팔린 상품은 주인도 못 지운다(발급된 이용권이 가리킨다).
  await expectDenied(
    'soldProductDelete',
    meDb.doc('placeProducts/product-sold').delete(),
  );
  await expectAllowed(
    'ownProductDelete',
    meDb.doc('placeProducts/product-mine').delete(),
  );

  await env.cleanup();

  const failed = results.filter((r) => !r.ok);
  for (const r of results) {
    console.log(`${r.ok ? '  ok' : 'FAIL'}  ${r.name}${r.detail ? ` — ${r.detail}` : ''}`);
  }
  if (failed.length > 0) {
    console.error(`\n${failed.length}/${results.length} 실패 — 규칙을 배포하지 말 것.`);
    process.exit(1);
  }
  console.log(`\n${results.length}/${results.length} 통과.`);
}

function skip(reason) {
  if (REQUIRE_EMULATOR) {
    console.error(`에뮬레이터 검증을 건너뛸 수 없다: ${reason}`);
    process.exit(1);
  }
  console.log(`SKIPPED — ${reason}`);
  console.log(
    '배포 전 실행: firebase emulators:exec --only firestore ' +
      '"node functions/placeChildOwnership.selfcheck.js"',
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

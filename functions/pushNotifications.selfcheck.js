// 푸시 알림(토큰 관리 · 발송 · 라우팅) 자체 검증 — `npm run check:push`.
//
// 푸시는 **틀려도 아무 화면에도 흔적이 남지 않는다.** 안 온 알림은 로그를 뒤지기
// 전까지 보이지 않고, 잘못 간 알림은 남의 기기에서만 보인다. 그래서 눈으로
// 확인할 수 없는 규칙들을 여기서 못 박는다.
//
//   1. 죽은 토큰만 지운다 — 일시적 오류로 지우면 멀쩡한 기기가 조용히 빠진다.
//   2. 한 기기에 같은 알림이 두 번 뜨지 않는다(계정 전환 잔여 토큰).
//   3. 발송 실패가 예외로 번지지 않는다 — 푸시 때문에 예약 처리가 되돌아가면 안 된다.
//   4. 알림 채널 id가 서버·매니페스트·앱 세 곳에서 같다(어긋나면 앱이 꺼져 있을
//      때 오는 알림만 없는 채널로 떨어져, 설정 스위치와 실제 알림이 따로 논다).

const assert = require('assert');
const fs = require('fs');
const path = require('path');

// pushSender는 admin.firestore()/admin.messaging()을 **호출 시점에** 부른다.
// 실제 앱을 띄우지 않고 그 자리에 가짜를 끼우기 위해 require보다 먼저 바꿔둔다.
// (단순 대입은 firebase-admin의 접근자가 기본 앱을 찾다가 죽으므로 defineProperty로 덮는다.)
const admin = require('firebase-admin');
let fakeDb = null;
let fakeMessaging = null;
Object.defineProperty(admin, 'firestore', {
  value: () => fakeDb,
  configurable: true,
});
Object.defineProperty(admin, 'messaging', {
  value: () => fakeMessaging,
  configurable: true,
});

const {
  sendPushToUsers,
  ANDROID_CHANNEL_ID,
  __helpers: sender,
} = require('./pushSender');
const { __helpers: tokens } = require('./pushTokens');
const { __helpers: dispatch } = require('./pushDispatch');

const { stringifyData, clip, collectDevices, DEAD_TOKEN_CODES } = sender;
const { isUsableToken, detachTokenFromOtherUsers } = tokens;
const { routeData } = dispatch;

const cases = [];
function test(name, fn) {
  cases.push([name, fn]);
}

/** 로그를 삼킨다 — 실패 경로 검증은 콘솔이 시끄러워지기 때문. */
function quiet(fn) {
  const [w, e, l] = [console.warn, console.error, console.log];
  console.warn = console.error = console.log = () => {};
  return Promise.resolve()
    .then(fn)
    .finally(() => {
      console.warn = w;
      console.error = e;
      console.log = l;
    });
}

const TOKEN = (n) => `tok_${'x'.repeat(30)}_${n}`;

/**
 * users/{uid}/devices 만 흉내 내는 최소 Firestore.
 * @param {object} byUid  { uid: [{ token, id? }] }
 */
function makeDb(byUid) {
  const deleted = [];
  const committed = [];
  const makeDoc = (uid, dev) => {
    const id = dev.id || dev.token;
    return {
      id,
      ref: { __uid: uid, __id: id },
      get: (field) => (field === 'token' ? dev.token : dev[field]),
    };
  };
  return {
    deleted,
    committed,
    collection: (name) => ({
      doc: (uid) => ({
        collection: () => ({
          get: async () => {
            if (name !== 'users') return { docs: [] };
            const list = byUid[uid] || [];
            return { docs: list.map((dev) => makeDoc(uid, dev)) };
          },
        }),
      }),
    }),
    collectionGroup: () => ({
      where: (_field, _op, token) => ({
        get: async () => {
          const docs = [];
          for (const [uid, list] of Object.entries(byUid)) {
            for (const dev of list) {
              if (dev.token !== token) continue;
              const doc = makeDoc(uid, dev);
              doc.get = (field) => (field === 'uid' ? uid : dev[field]);
              docs.push(doc);
            }
          }
          return { docs };
        },
      }),
    }),
    batch: () => {
      const ops = [];
      return {
        delete: (ref) => ops.push(ref),
        commit: async () => {
          committed.push(ops.length);
          deleted.push(...ops);
        },
      };
    },
  };
}

/** sendEachForMulticast만 흉내 내는 가짜 FCM. resultFor(token) → 에러코드 또는 null. */
function makeMessaging(resultFor) {
  const calls = [];
  return {
    calls,
    sendEachForMulticast: async (msg) => {
      calls.push(msg);
      return {
        responses: msg.tokens.map((t) => {
          const code = resultFor(t);
          return code ? { success: false, error: { code } } : { success: true };
        }),
      };
    },
  };
}

// ── 토큰 모양 ────────────────────────────────────────────────────────────────

test('토큰 — 정상 토큰은 통과한다', () => {
  assert.strictEqual(isUsableToken(TOKEN(1)), true);
});

test('토큰 — 문서 id로 쓸 수 없는 값은 막는다', () => {
  // '/'는 문서 경로를 쪼개고 '..'는 상위로 올라간다 — 둘 다 엉뚱한 문서를 만든다.
  assert.strictEqual(isUsableToken(`${TOKEN(1)}/evil`), false);
  assert.strictEqual(isUsableToken(`${TOKEN(1)}..x`), false);
  assert.strictEqual(isUsableToken('짧음'), false);
  assert.strictEqual(isUsableToken(''), false);
  assert.strictEqual(isUsableToken(null), false);
  assert.strictEqual(isUsableToken(123), false);
  assert.strictEqual(isUsableToken('a'.repeat(1001)), false);
});

// ── 계정 전환 잔여 토큰 정리 ─────────────────────────────────────────────────

test('계정 전환 — 같은 토큰이 남의 밑에 남아 있으면 지운다(내 것은 남긴다)', async () => {
  const t = TOKEN(1);
  const db = makeDb({ userA: [{ token: t }], userB: [{ token: t }] });
  const n = await detachTokenFromOtherUsers(db, t, 'userB');

  assert.strictEqual(n, 1, '남의 문서 1건이 정리돼야 한다');
  assert.deepStrictEqual(
    db.deleted.map((r) => r.__uid),
    ['userA'],
    '내(userB) 문서까지 지우면 방금 등록한 기기가 대상에서 빠진다',
  );
});

test('계정 전환 — 지울 게 없으면 배치를 커밋하지 않는다', async () => {
  const t = TOKEN(1);
  const db = makeDb({ userB: [{ token: t }] });
  assert.strictEqual(await detachTokenFromOtherUsers(db, t, 'userB'), 0);
  assert.deepStrictEqual(db.committed, [], '빈 배치 커밋은 쓰기 비용만 든다');
});

// ── 발송 페이로드 ────────────────────────────────────────────────────────────

test('데이터 — FCM data는 값이 전부 문자열이고 빈 값은 키째 빠진다', () => {
  assert.deepStrictEqual(
    stringifyData({ n: 3, ok: true, nil: null, undef: undefined, empty: '', s: 'x' }),
    { n: '3', ok: 'true', s: 'x' },
  );
  assert.deepStrictEqual(stringifyData(null), {});
});

test('문구 — 길면 우리가 먼저 자르고 공백은 한 칸으로 접는다', () => {
  assert.strictEqual(clip('  여러   줄\n텍스트 ', 100), '여러 줄 텍스트');
  const long = clip('가'.repeat(200), 60);
  assert.strictEqual(long.length, 60);
  assert.ok(long.endsWith('…'), '잘렸다는 표시가 있어야 한다');
  assert.strictEqual(clip(null, 10), '');
});

// ── 기기 수집 ────────────────────────────────────────────────────────────────

test('기기 — 같은 토큰은 한 번만 담는다(한 기기에 알림이 두 번 뜨지 않게)', async () => {
  const shared = TOKEN(1);
  const db = makeDb({
    userA: [{ token: shared }],
    userB: [{ token: shared }, { token: TOKEN(2) }],
  });
  const devices = await collectDevices(db, ['userA', 'userB', 'userA', null]);
  assert.deepStrictEqual(
    devices.map((d) => d.token).sort(),
    [shared, TOKEN(2)].sort(),
  );
});

test('기기 — 토큰 필드가 없으면 문서 id를 쓰고, 모양이 아니면 버린다', async () => {
  const db = makeDb({
    userA: [{ id: TOKEN(9), token: undefined }, { token: 'tooshort' }],
  });
  const devices = await collectDevices(db, ['userA']);
  assert.deepStrictEqual(devices.map((d) => d.token), [TOKEN(9)]);
});

test('기기 — 받는 사람이 없으면 조회 자체를 하지 않는다', async () => {
  assert.deepStrictEqual(await collectDevices(makeDb({}), []), []);
  assert.deepStrictEqual(await collectDevices(makeDb({}), [null, '']), []);
});

// ── 죽은 토큰 정리 ───────────────────────────────────────────────────────────

test('정리 — 등록 해제된 토큰만 지운다', async () => {
  const dead = TOKEN(1);
  const alive = TOKEN(2);
  fakeDb = makeDb({ userA: [{ token: dead }, { token: alive }] });
  fakeMessaging = makeMessaging((t) =>
    t === dead ? 'messaging/registration-token-not-registered' : null,
  );

  const res = await quiet(() => sendPushToUsers('userA', { title: 'ㅎ', body: 'ㅎ' }));

  assert.strictEqual(res.sent, 1);
  assert.strictEqual(res.failed, 1);
  assert.strictEqual(res.pruned, 1);
  assert.deepStrictEqual(fakeDb.deleted.map((r) => r.__id), [dead]);
});

test('정리 — 일시적 오류는 절대 지우지 않는다', async () => {
  fakeDb = makeDb({ userA: [{ token: TOKEN(1) }] });
  fakeMessaging = makeMessaging(() => 'messaging/server-unavailable');

  const res = await quiet(() => sendPushToUsers('userA', { title: 'ㅎ' }));

  assert.strictEqual(res.failed, 1);
  assert.strictEqual(res.pruned, 0, '지우면 멀쩡한 기기가 다음 알림부터 조용히 빠진다');
  assert.deepStrictEqual(fakeDb.deleted, []);
});

test('정리 — 지울 코드 목록에 되살아날 수 있는 오류가 섞이지 않았다', () => {
  for (const code of DEAD_TOKEN_CODES) {
    assert.ok(
      !/unavailable|internal|quota|timeout|unknown/i.test(code),
      `일시적 오류를 영구 실패로 다루고 있다: ${code}`,
    );
  }
});

// ── 발송 자체 ────────────────────────────────────────────────────────────────

test('발송 — 500개를 넘으면 나눠 보낸다(멀티캐스트 한도)', async () => {
  const list = Array.from({ length: 501 }, (_, i) => ({ token: TOKEN(i) }));
  fakeDb = makeDb({ userA: list });
  fakeMessaging = makeMessaging(() => null);

  const res = await quiet(() => sendPushToUsers('userA', { title: 'ㅎ' }));

  assert.deepStrictEqual(fakeMessaging.calls.map((c) => c.tokens.length), [500, 1]);
  assert.strictEqual(res.sent, 501);
});

test('발송 — 실패해도 예외를 던지지 않는다(본래 작업을 되돌리면 안 된다)', async () => {
  fakeDb = makeDb({ userA: [{ token: TOKEN(1) }] });
  fakeMessaging = {
    sendEachForMulticast: async () => {
      throw new Error('FCM 죽음');
    },
  };
  const res = await quiet(() => sendPushToUsers('userA', { title: 'ㅎ' }));
  assert.deepStrictEqual(res, { sent: 0, failed: 1, pruned: 0 });

  // 기기 조회가 통째로 실패해도 마찬가지다.
  fakeDb = {
    collection: () => ({
      doc: () => ({
        collection: () => ({
          get: async () => {
            throw new Error('DB 죽음');
          },
        }),
      }),
    }),
  };
  const res2 = await quiet(() => sendPushToUsers('userA', { title: 'ㅎ' }));
  assert.deepStrictEqual(res2, { sent: 0, failed: 0, pruned: 0 });
});

test('발송 — 보여줄 내용이 없으면 조회도 발송도 하지 않는다', async () => {
  fakeDb = null; // 건드리면 즉시 터진다
  fakeMessaging = null;
  assert.deepStrictEqual(await sendPushToUsers('userA', {}), {
    sent: 0,
    failed: 0,
    pruned: 0,
  });
});

test('발송 — 등록된 기기가 없으면 FCM을 부르지 않는다', async () => {
  fakeDb = makeDb({});
  fakeMessaging = makeMessaging(() => null);
  const res = await sendPushToUsers('userA', { title: 'ㅎ' });
  assert.deepStrictEqual(res, { sent: 0, failed: 0, pruned: 0 });
  assert.strictEqual(fakeMessaging.calls.length, 0);
});

test('발송 — 페이로드가 채널·소리를 갖추고 무음 백그라운드 푸시를 켜지 않는다', async () => {
  fakeDb = makeDb({ userA: [{ token: TOKEN(1) }] });
  fakeMessaging = makeMessaging(() => null);
  await quiet(() =>
    sendPushToUsers('userA', { title: '제목', body: '본문', data: { type: 'chat' } }),
  );

  const msg = fakeMessaging.calls[0];
  assert.strictEqual(msg.android.notification.channelId, ANDROID_CHANNEL_ID);
  assert.strictEqual(msg.android.priority, 'high');
  assert.deepStrictEqual(msg.data, { type: 'chat' });
  assert.strictEqual(
    'content-available' in msg.apns.payload.aps,
    false,
    'remote-notification 백그라운드 모드가 없는 앱에 켜면 APNs가 알림을 늦게 묶어 보낸다',
  );
});

// ── 채널 id 일치 ─────────────────────────────────────────────────────────────

test('채널 — 서버·매니페스트·앱이 같은 id를 쓴다', () => {
  const read = (p) => fs.readFileSync(path.join(__dirname, '..', p), 'utf8');

  const manifest = read('party_app/android/app/src/main/AndroidManifest.xml');
  const inManifest =
    /default_notification_channel_id"[\s\S]{0,120}?android:value="([^"]+)"/.exec(
      manifest,
    );
  assert.ok(inManifest, '매니페스트에 기본 알림 채널 선언이 없다');

  const service = read('party_app/lib/services/push_notification_service.dart');
  const inApp = /_channelId\s*=\s*'([^']+)'/.exec(service);
  assert.ok(inApp, '앱에서 채널 id 상수를 찾지 못했다');

  assert.strictEqual(inManifest[1], ANDROID_CHANNEL_ID);
  assert.strictEqual(inApp[1], ANDROID_CHANNEL_ID);
});

// ── 라우팅 ───────────────────────────────────────────────────────────────────

test('라우팅 — 알림 문서의 이동 정보가 그대로 푸시 data로 넘어간다', () => {
  const data = routeData('n1', {
    type: 'visit_reservation_approved',
    role: 'host',
    placeId: 'p1',
    placeCollection: 'events',
    refCollection: 'placeVisitReservations',
    refId: 'r1',
  });
  assert.deepStrictEqual(data, {
    notificationId: 'n1',
    type: 'visit_reservation_approved',
    role: 'host',
    partyId: '',
    placeId: 'p1',
    placeCollection: 'events',
    refCollection: 'placeVisitReservations',
    refId: 'r1',
  });
  // 값이 비어도 키는 남는다 — 뒤이어 stringifyData가 빈 값만 걷어낸다.
  assert.deepStrictEqual(stringifyData(routeData('n2', {})), { notificationId: 'n2' });
});

test('라우팅 — 앱이 읽는 키를 서버가 빠짐없이 실어 보낸다', () => {
  const route = fs.readFileSync(
    path.join(__dirname, '..', 'party_app/lib/utils/notification_route.dart'),
    'utf8',
  );
  const used = [...route.matchAll(/read\('([^']+)'\)/g)].map((m) => m[1]);
  assert.ok(used.length > 0, '앱의 라우팅 규칙에서 읽는 키를 찾지 못했다');

  const sent = new Set([
    ...Object.keys(routeData('x', {})),
    // 채팅은 알림 문서를 남기지 않아 pushDispatch가 직접 싣는 키들.
    'roomId',
    'otherName',
    'relatedTitle',
  ]);
  for (const key of new Set(used)) {
    assert.ok(sent.has(key), `앱이 읽는 '${key}'를 서버가 실어 보내지 않는다`);
  }
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
      ? `\n푸시 알림 규칙 검증 통과 — ${cases.length}건`
      : `\n실패 ${failed}건 / 전체 ${cases.length}건`,
  );
  process.exit(failed === 0 ? 0 : 1);
})();

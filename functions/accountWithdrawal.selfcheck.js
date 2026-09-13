// 회원 탈퇴 규칙 자체 검증 — `npm run check:withdrawal`.
//
// 탈퇴는 되돌릴 수 없고, 틀려도 조용하다. 특히 두 가지가 그렇다.
//
//   1. CI 링크 해제를 개인정보 삭제보다 먼저 하지 않으면 releaseIdentityLink가
//      'no-ci'로 아무 일도 하지 않고 끝난다. 예외도 안 나고 로그도 평소와 같아서
//      **30일 재가입 제한이 통째로 빠진 것을 아무도 모른다.**
//   2. 재가입 제한 30일은 신청일이 아니라 7일 대기가 끝난 완전 탈퇴 시점부터여야
//      한다. 신청 시점에 링크를 풀면 취소하고 돌아온 사용자의 CI가 이미 남에게
//      넘어가 있을 수 있다.
//
// 그래서 여기서는 가짜 Firestore를 만들어 **진짜 releaseIdentityLink를 태우고**,
// 연산 순서를 기록해 검사한다.

const assert = require('assert');

// admin.firestore()/admin.auth()를 require보다 먼저 가짜로 바꾼다.
const admin = require('firebase-admin');
let fakeDb = null;
const authDeleted = [];
Object.defineProperty(admin, 'firestore', { value: () => fakeDb, configurable: true });
Object.defineProperty(admin, 'auth', {
  value: () => ({
    deleteUser: async (uid) => {
      authDeleted.push({ uid, at: fakeDb.__ops.length });
    },
  }),
  configurable: true,
});

// FieldValue / Timestamp 는 네임스페이스 함수의 프로퍼티라 따로 붙여준다.
const DELETE = { __delete: true };
admin.firestore.FieldValue = {
  delete: () => DELETE,
  serverTimestamp: () => ({ __ts: true }),
  // 재가입 추적(identityLinks.previousUids)이 arrayUnion으로 쌓인다 — 흉내를
  // 빠뜨리면 그 필드가 통째로 검증에서 빠진다.
  arrayUnion: (...values) => ({ __arrayUnion: values }),
};
admin.firestore.Timestamp = {
  now: () => ({ toDate: () => new Date(FIXED_NOW), toMillis: () => FIXED_NOW }),
  fromDate: (d) => ({ toDate: () => d, toMillis: () => d.getTime() }),
};

const FIXED_NOW = Date.UTC(2026, 7, 18, 0, 0, 0);

const { __helpers } = require('./accountWithdrawal');
const {
  GRACE_DAYS,
  STATUS_PENDING,
  STATUS_WITHDRAWN,
  PERSONAL_FIELDS,
  PERSONAL_COLLECTIONS,
  needsSettlementReview,
  r2KeyFromUrl,
  completeWithdrawal,
  LIVE_APPLICATION_STATUSES,
  LIVE_RESERVATION_STATUSES,
  WITHDRAWAL_REASON_CODES,
  normalizeReasonCode,
  memberTypeOf,
} = __helpers;

const retention = require('./retentionPolicy');

const { RELEASE_COOLDOWN_DAYS } = require('./identityLink');

const cases = [];
function test(name, fn) {
  cases.push([name, fn]);
}

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

// ── 최소 Firestore 흉내 ──────────────────────────────────────────────────────
//
// 연산 순서를 __ops에 남긴다 — 이 검증의 핵심이 "무엇을 했는가"가 아니라
// "어떤 순서로 했는가"이기 때문이다.
function makeDb(seed = {}) {
  const store = new Map(Object.entries(seed));
  const ops = [];

  const apply = (path, data, merge) => {
    const prev = merge ? { ...(store.get(path) || {}) } : {};
    for (const [k, v] of Object.entries(data)) {
      if (v === DELETE) delete prev[k];
      else if (v && typeof v === 'object' && Array.isArray(v.__arrayUnion)) {
        const cur = Array.isArray(prev[k]) ? prev[k] : [];
        prev[k] = [...cur, ...v.__arrayUnion.filter((x) => !cur.includes(x))];
      } else if (v && typeof v === 'object' && !Array.isArray(v) && !v.__ts && !v.toDate) {
        prev[k] = { ...(prev[k] || {}), ...v };
      } else prev[k] = v;
    }
    store.set(path, prev);
  };

  const docRef = (path) => ({
    id: path.split('/').pop(),
    path,
    get: async () => {
      ops.push(['get', path]);
      const d = store.get(path);
      return {
        exists: d !== undefined,
        id: path.split('/').pop(),
        data: () => d,
        get: (f) => (d ? d[f] : undefined),
        ref: docRef(path),
      };
    },
    set: async (data, opt) => {
      ops.push(['set', path, Object.keys(data)]);
      apply(path, data, opt && opt.merge);
    },
    delete: async () => {
      ops.push(['delete', path]);
      store.delete(path);
    },
    collection: (sub) => collRef(`${path}/${sub}`),
  });

  const snapOf = (paths) => ({
    empty: paths.length === 0,
    size: paths.length,
    docs: paths.map((p) => ({
      id: p.split('/').pop(),
      ref: docRef(p),
      data: () => store.get(p),
      get: (f) => store.get(p)[f],
    })),
  });

  let autoId = 0;
  const collRef = (name) => ({
    doc: (id) => docRef(`${name}/${id}`),
    add: async (data) => {
      const path = `${name}/auto${(autoId += 1)}`;
      ops.push(['add', name]);
      store.set(path, data);
      return docRef(path);
    },
    get: async () => {
      ops.push(['list', name]);
      return snapOf([...store.keys()].filter((k) => k.startsWith(`${name}/`) && k.slice(name.length + 1).indexOf('/') < 0));
    },
    where: (field, op, val) => {
      const filter = (paths) =>
        paths.filter((p) => {
          const d = store.get(p) || {};
          if (op === 'array-contains') return Array.isArray(d[field]) && d[field].includes(val);
          return d[field] === val;
        });
      const self = {
        where: () => self,
        limit: () => self,
        get: async () => {
          ops.push(['query', name, field, val]);
          return snapOf(
            filter(
              [...store.keys()].filter(
                (k) => k.startsWith(`${name}/`) && k.slice(name.length + 1).indexOf('/') < 0,
              ),
            ),
          );
        },
      };
      return self;
    },
  });

  return {
    __ops: ops,
    __store: store,
    collection: collRef,
    collectionGroup: (name) => ({
      where: (field, op, val) => ({
        get: async () => {
          ops.push(['cgquery', name, field, val]);
          const paths = [...store.keys()].filter((k) => k.split('/').slice(-2)[0] === name);
          return snapOf(paths.filter((p) => (store.get(p) || {})[field] === val));
        },
      }),
    }),
    batch: () => {
      const pending = [];
      return {
        set: (ref, data, opt) => pending.push(['set', ref, data, opt]),
        delete: (ref) => pending.push(['delete', ref]),
        commit: async () => {
          for (const [kind, ref, data, opt] of pending) {
            if (kind === 'delete') { ops.push(['delete', ref.path]); store.delete(ref.path); }
            else { ops.push(['set', ref.path, Object.keys(data)]); apply(ref.path, data, opt && opt.merge); }
          }
        },
      };
    },
    runTransaction: async (fn) => {
      const tx = {
        get: async (ref) => ref.get(),
        set: async (ref, data, opt) => ref.set(data, opt),
      };
      return fn(tx);
    },
  };
}

const CI = 'CI_VALUE_1234567890';
const crypto = require('crypto');
const CI_HASH = crypto.createHash('sha256').update(CI, 'utf8').digest('hex');

function seedUser(extra = {}) {
  return {
    [`users/uidA`]: {
      uid: 'uidA',
      accountStatus: STATUS_PENDING,
      ci: CI,
      identityCiHash: CI_HASH,
      name: '홍길동',
      di: 'DI_VALUE',
      gender: 'M',
      birthYear: 1990,
      nickname: '길동',
      email: 'a@b.com',
      socialAccount: { provider: 'naver', email: 'a@naver.com', updatedAt: { __ts: true } },
      profileImageUrl: 'https://cdn.example.com/party_images/uidA/1.jpg',
      refundAccount: { bank: '국민', accountNumber: '1234' },
      settlementInfo: { bank: '국민', accountNumber: '5678' },
      businessNumber: '1234567890',
      ...extra,
    },
    [`identityLinks/${CI_HASH}`]: { uid: 'uidA', status: 'active' },
  };
}

// ── 기본 상수 ────────────────────────────────────────────────────────────────

test('대기 기간은 7일이다', () => {
  assert.strictEqual(GRACE_DAYS, 7);
});

test('재가입 제한은 30일이고 대기 기간과 별개다', () => {
  assert.strictEqual(RELEASE_COOLDOWN_DAYS, 30);
  assert.notStrictEqual(RELEASE_COOLDOWN_DAYS, GRACE_DAYS);
});

test('진행 중 상태값이 contentCleanup과 같다', () => {
  const cc = require('./contentCleanup');
  // contentCleanup은 상수를 내보내지 않으므로 소스에서 직접 읽어 비교한다 —
  // 두 곳이 갈라지면 콘텐츠 삭제는 막는데 탈퇴는 통과하는 상태가 된다.
  const src = require('fs').readFileSync(require.resolve('./contentCleanup'), 'utf8');
  const pick = (name) => {
    const m = new RegExp(`${name}\\s*=\\s*\\[([^\\]]*)\\]`).exec(src);
    return m[1].split(',').map((s) => s.trim().replace(/'/g, '')).filter(Boolean);
  };
  assert.deepStrictEqual(LIVE_APPLICATION_STATUSES, pick('LIVE_APPLICATION_STATUSES'));
  assert.deepStrictEqual(LIVE_RESERVATION_STATUSES, pick('LIVE_RESERVATION_STATUSES'));
  assert.ok(cc.TYPES, 'contentCleanup.TYPES가 있어야 한다');
});

// ── 삭제 대상 목록 ───────────────────────────────────────────────────────────

test('본인확인 원문이 전부 삭제 목록에 있다', () => {
  // phoneNumber는 NICE 휴대폰 본인확인 결과(mobile_no)로 실제 채워지는 값이다 —
  // 다른 본인확인 원문과 같은 취급이어야 한다(niceAuth.js · phoneNumber.js).
  for (const f of ['ci', 'di', 'identityCiHash', 'name', 'gender', 'birthYear', 'birthMonth', 'birthDay', 'phoneNumber']) {
    assert.ok(PERSONAL_FIELDS.includes(f), `${f}가 삭제 목록에 없다`);
  }
});

test('금융·사업자 프로필 정보가 삭제 목록에 있다', () => {
  for (const f of ['refundAccount', 'settlementInfo', 'businessNumber', 'businessName', 'businessAddress']) {
    assert.ok(PERSONAL_FIELDS.includes(f), `${f}가 삭제 목록에 없다`);
  }
});

test('로그인 계정 정보가 삭제 목록에 있다', () => {
  // socialAccount는 socialAuth.js가 로그인마다 소셜 계정 이메일을 기록하는 자리다.
  for (const f of ['email', 'signupProvider', 'socialAccount']) {
    assert.ok(PERSONAL_FIELDS.includes(f), `${f}가 삭제 목록에 없다`);
  }
});

test('보존해야 하는 것은 삭제 목록에 없다', () => {
  // uid는 5년 보존되는 거래기록이 참조하는 키이고, accountStatus/withdrawnAt은
  // 탈퇴 사실 자체의 증거다. 지우면 주인 없는 거래기록만 남는다.
  for (const f of ['uid', 'accountStatus', 'withdrawnAt', 'createdAt']) {
    assert.ok(!PERSONAL_FIELDS.includes(f), `${f}는 지우면 안 된다`);
  }
});

test('개인 데이터 컬렉션이 거래기록을 건드리지 않는다', () => {
  const names = PERSONAL_COLLECTIONS.map((c) => c.name);
  for (const legal of ['orders', 'applications', 'placeReservationGroups', 'refundRequests', 'packageBookings']) {
    assert.ok(!names.includes(legal), `${legal}은 법정 보존 대상이라 지우면 안 된다`);
  }
});

// ── 정산 보류 ────────────────────────────────────────────────────────────────

test('호스트였던 계정은 정산 확인 전까지 완료를 보류한다', () => {
  assert.strictEqual(needsSettlementReview({ isHost: true }), true);
  assert.strictEqual(needsSettlementReview({ activityRoles: ['host'] }), true);
});

test('정산 확인이 끝나면 보류하지 않는다', () => {
  assert.strictEqual(needsSettlementReview({ isHost: true, settlementClearedAt: {} }), false);
});

test('호스트가 아니면 보류하지 않는다', () => {
  assert.strictEqual(needsSettlementReview({ isHost: false }), false);
  assert.strictEqual(needsSettlementReview({}), false);
});

// ── R2 키 ────────────────────────────────────────────────────────────────────

test('업로드 URL에서 R2 키를 뽑는다', () => {
  assert.strictEqual(
    r2KeyFromUrl('https://cdn.example.com/party_images/uidA/1.jpg'),
    'party_images/uidA/1.jpg',
  );
  assert.strictEqual(r2KeyFromUrl('https://other.com/foo.jpg'), null);
  assert.strictEqual(r2KeyFromUrl(null), null);
});

// ── 완전 탈퇴 순서 (핵심) ────────────────────────────────────────────────────

test('CI 링크 해제가 개인정보 삭제보다 먼저 일어난다', async () => {
  fakeDb = makeDb(seedUser());
  await quiet(() => completeWithdrawal(fakeDb, 'uidA', null));

  const ops = fakeDb.__ops;
  const linkIdx = ops.findIndex(
    (o) => o[0] === 'set' && o[1] === `identityLinks/${CI_HASH}`,
  );
  const wipeIdx = ops.findIndex(
    (o) => o[0] === 'set' && o[1] === 'users/uidA' && o[2].includes('ci'),
  );

  assert.ok(linkIdx >= 0, 'identityLinks 갱신이 일어나야 한다');
  assert.ok(wipeIdx >= 0, '개인정보 삭제가 일어나야 한다');
  assert.ok(
    linkIdx < wipeIdx,
    `순서가 뒤집혔다 — link=${linkIdx} wipe=${wipeIdx}. 이러면 30일 제한이 조용히 빠진다.`,
  );
});

test('링크 해제가 실제로 released + reusableAt을 남긴다', async () => {
  fakeDb = makeDb(seedUser());
  await quiet(() => completeWithdrawal(fakeDb, 'uidA', null));

  const link = fakeDb.__store.get(`identityLinks/${CI_HASH}`);
  assert.strictEqual(link.status, 'released');
  assert.ok(link.reusableAt, 'reusableAt이 있어야 재가입 제한이 걸린다');

  const days = Math.round((link.reusableAt.toDate().getTime() - Date.now()) / 86400000);
  assert.ok(
    Math.abs(days - RELEASE_COOLDOWN_DAYS) <= 1,
    `재가입 제한이 ${days}일 — 완전 탈퇴 시점 기준 30일이어야 한다`,
  );
});

test('Auth 삭제가 가장 마지막이다', async () => {
  authDeleted.length = 0;
  fakeDb = makeDb(seedUser());
  await quiet(() => completeWithdrawal(fakeDb, 'uidA', null));

  assert.strictEqual(authDeleted.length, 1);
  const linkIdx = fakeDb.__ops.findIndex((o) => o[1] === `identityLinks/${CI_HASH}` && o[0] === 'set');
  assert.ok(
    authDeleted[0].at > linkIdx,
    'Auth를 먼저 지우면 이후 단계의 권한 근거가 사라진다',
  );
});

test('개인정보는 지우고 비석은 남긴다', async () => {
  fakeDb = makeDb(seedUser());
  await quiet(() => completeWithdrawal(fakeDb, 'uidA', null));

  const u = fakeDb.__store.get('users/uidA');
  assert.ok(u, 'users 문서 자체는 남아야 한다 — 거래기록이 uid를 참조한다');
  for (const f of ['ci', 'di', 'name', 'nickname', 'email', 'socialAccount', 'refundAccount', 'settlementInfo', 'businessNumber']) {
    assert.strictEqual(u[f], undefined, `${f}가 남아 있다`);
  }
  assert.strictEqual(u.accountStatus, STATUS_WITHDRAWN);
  assert.ok(u.withdrawnAt, '탈퇴 시각이 남아야 한다');
  assert.strictEqual(u.uid, 'uidA', 'uid는 남아야 한다');
});

test('완료된 비석에는 보류 표시가 남지 않는다', async () => {
  // 정산 확인으로 한 번 보류됐다가 나중에 완료된 계정을 재현한다.
  // 보류 표시는 "아직 완료하지 못한 이유"라서 완료 후에도 남아 있으면,
  // 이 문서를 보는 사람이 아직 정산을 기다리는 계정으로 잘못 읽는다.
  fakeDb = makeDb(seedUser({
    withdrawalHold: 'settlement',
    withdrawalHoldSince: { __ts: true },
  }));
  await quiet(() => completeWithdrawal(fakeDb, 'uidA', null));

  const u = fakeDb.__store.get('users/uidA');
  assert.strictEqual(u.withdrawalHold, undefined, 'withdrawalHold가 남아 있다');
  assert.strictEqual(u.withdrawalHoldSince, undefined, 'withdrawalHoldSince가 남아 있다');
  assert.strictEqual(u.accountStatus, STATUS_WITHDRAWN);
});

test('푸시 토큰이 전부 지워진다', async () => {
  const seed = seedUser();
  seed['users/uidA/devices/tokA'] = { uid: 'uidA', token: 'tokA' };
  seed['users/uidA/devices/tokB'] = { uid: 'uidA', token: 'tokB' };
  fakeDb = makeDb(seed);
  await quiet(() => completeWithdrawal(fakeDb, 'uidA', null));

  const left = [...fakeDb.__store.keys()].filter((k) => k.startsWith('users/uidA/devices/'));
  assert.deepStrictEqual(left, [], '남으면 탈퇴한 기기로 알림이 계속 간다');
});

test('개인 데이터는 지우고 거래기록은 남긴다', async () => {
  const seed = seedUser();
  seed['favorites/f1'] = { userId: 'uidA' };
  seed['drafts/d1'] = { userId: 'uidA' };
  seed['notifications/n1'] = { uid: 'uidA' };
  seed['orders/o1'] = { buyerId: 'uidA', buyerName: '홍길동', status: 'completed' };
  fakeDb = makeDb(seed);
  await quiet(() => completeWithdrawal(fakeDb, 'uidA', null));

  assert.strictEqual(fakeDb.__store.get('favorites/f1'), undefined);
  assert.strictEqual(fakeDb.__store.get('drafts/d1'), undefined);
  assert.strictEqual(fakeDb.__store.get('notifications/n1'), undefined);
  assert.ok(fakeDb.__store.get('orders/o1'), '주문은 5년 보존 대상이라 남아야 한다');
});

test('보존되는 거래기록의 이름은 익명화된다', async () => {
  const seed = seedUser();
  seed['orders/o1'] = { buyerId: 'uidA', buyerName: '홍길동', status: 'completed' };
  seed['chatRooms/r1'] = { participants: ['uidA', 'uidB'], participantNames: { uidA: '길동', uidB: '철수' } };
  fakeDb = makeDb(seed);
  await quiet(() => completeWithdrawal(fakeDb, 'uidA', null));

  assert.strictEqual(fakeDb.__store.get('orders/o1').buyerName, '탈퇴한 회원');
  const room = fakeDb.__store.get('chatRooms/r1');
  assert.strictEqual(room.participantNames.uidA, '탈퇴한 회원');
  assert.strictEqual(room.participantNames.uidB, '철수', '상대방 이름은 건드리면 안 된다');
  assert.deepStrictEqual(room.participants, ['uidA', 'uidB'], '방 접근 판정에 쓰이므로 uid는 남긴다');
});

test('한 단계가 실패해도 나머지는 계속 진행된다', async () => {
  fakeDb = makeDb(seedUser());
  // 링크 문서가 없는 상태 = releaseIdentityLink가 not-linked-to-uid로 끝난다.
  fakeDb.__store.delete(`identityLinks/${CI_HASH}`);
  const res = await quiet(() => completeWithdrawal(fakeDb, 'uidA', null));

  const u = fakeDb.__store.get('users/uidA');
  assert.strictEqual(u.ci, undefined, '앞 단계가 비어도 개인정보는 지워져야 한다');
  assert.strictEqual(u.accountStatus, STATUS_WITHDRAWN);
  assert.ok(res.steps.authDelete, '마지막 단계까지 도달해야 한다');
});

// ── 탈퇴 사유 코드 ───────────────────────────────────────────────────────────
//
// 사유를 두 갈래로 나눈 것이 이 기능의 핵심 선택이다. 코드만 uid에 붙이고
// 자유서술은 붙이지 않는다 — 자유서술은 무엇이 적힐지 통제할 수 없어서
// uid에 묶는 순간 수집 범위를 예측할 수 없는 개인정보가 된다.

test('허용된 사유 코드만 저장된다', () => {
  assert.strictEqual(normalizeReasonCode('privacy'), 'privacy');
  assert.strictEqual(normalizeReasonCode('no_longer_use'), 'no_longer_use');
});

test('알 수 없는 사유 코드는 버린다 — 신청 자체를 막지는 않는다', () => {
  assert.strictEqual(normalizeReasonCode('made_up_code'), null);
  assert.strictEqual(normalizeReasonCode(''), null);
  assert.strictEqual(normalizeReasonCode(null), null);
  assert.strictEqual(normalizeReasonCode(123), null);
});

test('사유 코드 목록에 기타가 있다 — 어떤 사유든 코드 하나로 떨어진다', () => {
  assert.ok(WITHDRAWAL_REASON_CODES.includes('other'));
  assert.ok(WITHDRAWAL_REASON_CODES.length >= 5, '선택지가 너무 적으면 전부 기타로 몰린다');
});

// ── 탈퇴 당시 회원 유형 ──────────────────────────────────────────────────────

test('사업자 인증 맵이 있으면 business로 굳힌다', () => {
  assert.strictEqual(memberTypeOf({ businessVerification: { status: 'verified' } }), 'business');
});

test('사업자 인증이 없으면 individual이다', () => {
  assert.strictEqual(memberTypeOf({}), 'individual');
  assert.strictEqual(memberTypeOf(null), 'individual');
  assert.strictEqual(memberTypeOf({ businessVerification: null }), 'individual');
});

test('회원 유형은 businessVerification이 지워지기 전에 굳어야 한다', async () => {
  fakeDb = makeDb(seedUser({ businessVerification: { status: 'verified' } }));
  await quiet(() => completeWithdrawal(fakeDb, 'uidA', null));

  const u = fakeDb.__store.get('users/uidA');
  assert.strictEqual(u.businessVerification, undefined, '사업자 원본은 지워져야 한다');
  assert.strictEqual(
    u.withdrawnMemberType, 'business',
    '유형을 미리 굳히지 않으면 탈퇴자가 전원 일반회원으로 보인다',
  );
});

// ── 탈퇴 회원 관리용 비석 ────────────────────────────────────────────────────

test('탈퇴 신청일은 완료 후에도 남는다', async () => {
  fakeDb = makeDb(seedUser({ withdrawalRequestedAt: { __ts: true } }));
  await quiet(() => completeWithdrawal(fakeDb, 'uidA', null));

  const u = fakeDb.__store.get('users/uidA');
  assert.ok(
    u.withdrawalRequestedAt,
    '신청일을 지우면 관리자 목록이 "언제 신청해 언제 끝났는지"를 되짚을 수 없다',
  );
  assert.ok(u.withdrawnAt, '완료일도 남아야 한다');
});

test('사유 코드와 탈퇴 직전 상태는 완료 후에도 남는다', async () => {
  fakeDb = makeDb(seedUser({
    withdrawalReasonCode: 'privacy',
    withdrawnFromStatus: 'restricted',
  }));
  await quiet(() => completeWithdrawal(fakeDb, 'uidA', null));

  const u = fakeDb.__store.get('users/uidA');
  assert.strictEqual(u.withdrawalReasonCode, 'privacy');
  assert.strictEqual(
    u.withdrawnFromStatus, 'restricted',
    '제재 중이던 회원이 탈퇴했다는 사실이 사라지면 안 된다',
  );
});

test('탈퇴 관리 필드가 개인정보 삭제 목록에 섞여 있지 않다', () => {
  for (const f of [
    'withdrawalRequestedAt', 'withdrawnAt', 'withdrawnMemberType',
    'withdrawalReasonCode', 'withdrawnFromStatus',
  ]) {
    assert.ok(!PERSONAL_FIELDS.includes(f), `${f}는 관리용이라 지우면 안 된다`);
  }
});

// ── 재가입 추적 ──────────────────────────────────────────────────────────────

test('탈퇴하면 그 uid가 재가입 추적 이력에 쌓인다', async () => {
  fakeDb = makeDb(seedUser());
  await quiet(() => completeWithdrawal(fakeDb, 'uidA', null));

  const link = fakeDb.__store.get(`identityLinks/${CI_HASH}`);
  assert.ok(link, '링크 문서는 남아야 한다 — 지우면 즉시 재가입으로 제재를 피한다');
  assert.deepStrictEqual(
    link.previousUids, ['uidA'],
    '탈퇴 시점이 uid와 CI를 잇는 마지막 기회다(직후 users.ci가 지워진다)',
  );
  assert.strictEqual(link.status, 'released');
});

test('같은 사람이 여러 번 탈퇴해도 이력이 중복되지 않는다', async () => {
  fakeDb = makeDb(seedUser());
  await quiet(() => completeWithdrawal(fakeDb, 'uidA', null));
  // 두 번째 호출은 링크가 이미 released라 실제로는 일어나지 않지만,
  // arrayUnion이 중복을 만들지 않는다는 성질 자체를 못 박는다.
  const link = fakeDb.__store.get(`identityLinks/${CI_HASH}`);
  assert.strictEqual(new Set(link.previousUids).size, link.previousUids.length);
});

test('재가입 추적 이력은 사건 기록과 다른 보존 정책을 쓴다', () => {
  const { RETENTION_CLASS, RETENTION_POLICY } = retention;
  assert.notStrictEqual(
    RETENTION_CLASS.identityRelink,
    RETENTION_CLASS.disputeEvidence,
    '재가입 연결과 분쟁 증거는 근거가 달라 기간을 따로 정해야 한다',
  );
  assert.ok(
    RETENTION_POLICY[RETENTION_CLASS.identityRelink].covers
      .some((c) => c.includes('previousUids')),
    '정책이 실제로 previousUids를 가리켜야 한다',
  );
});

// ── 사건 기록 보존 ───────────────────────────────────────────────────────────
//
// 신고·제재·분쟁·부정이용·노쇼·거래·예약·환불·채팅은 회원이 탈퇴해도 남아야
// 한다. 삭제 목록에 하나라도 섞이면 그 순간부터 추적이 끊기므로, 목록 쪽에서
// 못 박는다.

test('사건 기록 컬렉션은 삭제 목록에 없다', () => {
  const deleted = PERSONAL_COLLECTIONS.map((c) => c.name);
  const eventRecords = [
    'reports',            // 신고
    'userActivityLogs',   // 제재·노쇼·분쟁 처리 이력
    'chatRooms', 'messages', // 채팅
    'orders', 'placeProductOrders',
    'placeReservationGroups', 'placeVisitReservations', 'packageBookings',
    'refundRequests',
  ];
  for (const c of eventRecords) {
    assert.ok(!deleted.includes(c), `${c}는 사건 기록이라 탈퇴로 지우면 안 된다`);
  }
});

test('탈퇴가 지우는 것은 개인 편의 데이터뿐이다', () => {
  // 삭제 목록이 늘어날 때 사건 기록이 슬쩍 섞이는 것을 막는다.
  const allowed = new Set([
    'favorites', 'partyOpenAlerts', 'drafts',
    'notifications', 'niceAuthSessions', 'verificationSessions',
  ]);
  for (const c of PERSONAL_COLLECTIONS) {
    assert.ok(allowed.has(c.name), `${c.name}이 삭제 목록에 새로 들어왔다 — 사건 기록인지 확인 필요`);
  }
});

// ── 보존 기간 정책 ───────────────────────────────────────────────────────────

test('보존 성격이 네 갈래로 나뉘어 있다', () => {
  const { RETENTION_CLASS, RETENTION_POLICY } = retention;
  for (const k of ['withdrawnMemberAdmin', 'disputeEvidence', 'identityRelink', 'transactionRecord']) {
    assert.ok(RETENTION_CLASS[k], `${k} 구분이 없다`);
    assert.ok(RETENTION_POLICY[RETENTION_CLASS[k]], `${k} 정책이 없다`);
  }
});

test('기간이 미정이면 아무것도 파기하지 않는다', () => {
  const { RETENTION_CLASS, isExpired, expiresAt, isRetentionDefined } = retention;
  const longAgo = Date.UTC(2000, 0, 1);
  for (const k of Object.values(RETENTION_CLASS)) {
    if (isRetentionDefined(k)) continue;
    assert.strictEqual(expiresAt(k, longAgo), null, `${k}: 미정인데 만료 시각이 나온다`);
    assert.strictEqual(
      isExpired(k, longAgo), false,
      `${k}: 기간이 미정인데 파기 대상으로 판정된다 — 법정 기간보다 먼저 지우게 된다`,
    );
  }
});

test('기간을 정하면 그 숫자만으로 파기 판정이 바뀐다', () => {
  const { RETENTION_CLASS, RETENTION_POLICY, isExpired, expiresAt } = retention;
  const key = RETENTION_CLASS.withdrawnMemberAdmin;
  const original = RETENTION_POLICY[key].days;
  try {
    RETENTION_POLICY[key].days = 30;
    const since = Date.UTC(2026, 0, 1);
    assert.deepStrictEqual(expiresAt(key, since), new Date(since + 30 * 86400000));
    assert.strictEqual(isExpired(key, since, since + 29 * 86400000), false);
    assert.strictEqual(isExpired(key, since, since + 31 * 86400000), true);
  } finally {
    RETENTION_POLICY[key].days = original;
  }
});

test('알 수 없는 보존 성격을 물으면 조용히 넘어가지 않는다', () => {
  assert.throws(() => retention.retentionDays('made_up'), /알 수 없는 보존 성격/);
});

// ── 재가입 시 이력 이월 (이 기능에서 가장 깨지기 쉬운 지점) ──────────────────
//
// linkIdentityAndSaveVerification의 링크 쓰기는 **merge가 아니라 전체
// 덮어쓰기**다(released/reusableAt 흔적을 지우려고 일부러 그렇게 돼 있다).
// 그래서 previousUids를 손으로 이월하지 않으면, 같은 사람이 새 uid로 돌아온
// 바로 그 순간에 이력이 통째로 사라진다 — 하필 이력이 가장 필요한 시점이다.
// 조용히 깨지는 종류의 버그라 여기서 진짜 함수를 태워 확인한다.

const { linkIdentityAndSaveVerification } = require('./identityLink');

/** 유예 기간이 끝나 다른 계정이 가져갈 수 있는 상태의 링크. */
function seedReleasedLink(previousUids) {
  const past = FIXED_NOW - 24 * 60 * 60 * 1000;
  return {
    'users/uidB': { uid: 'uidB' },
    [`identityLinks/${CI_HASH}`]: {
      uid: 'uidA',
      status: 'released',
      previousUids,
      reusableAt: { toMillis: () => past, toDate: () => new Date(past) },
    },
  };
}

test('재가입해도 이전 계정 이력이 살아남는다', async () => {
  fakeDb = makeDb(seedReleasedLink(['uidA']));
  await quiet(() =>
    linkIdentityAndSaveVerification(fakeDb, {
      uid: 'uidB', ci: CI, userPatch: { name: '홍길동' }, provider: 'nice',
    }),
  );

  const link = fakeDb.__store.get(`identityLinks/${CI_HASH}`);
  assert.strictEqual(link.uid, 'uidB', 'CI는 새 계정으로 넘어가야 한다');
  assert.strictEqual(link.status, 'active');
  assert.ok(
    link.previousUids.includes('uidA'),
    '덮어쓰기가 이력을 지워버렸다 — 재가입 추적이 통째로 사라진다',
  );
});

test('재가입 후에도 released/reusableAt 흔적은 지워진다', async () => {
  // 이력 이월 때문에 원래 의도(흔적 제거)가 깨지지 않았는지 함께 본다.
  fakeDb = makeDb(seedReleasedLink(['uidA']));
  await quiet(() =>
    linkIdentityAndSaveVerification(fakeDb, {
      uid: 'uidB', ci: CI, userPatch: {}, provider: 'nice',
    }),
  );

  const link = fakeDb.__store.get(`identityLinks/${CI_HASH}`);
  assert.strictEqual(link.releasedAt, null);
  assert.strictEqual(link.reusableAt, null);
});

test('탈퇴를 반복해도 이력이 계속 누적된다', async () => {
  // uidA → uidB로 넘어간 뒤 uidB도 탈퇴하고 uidC가 가져가는 흐름.
  fakeDb = makeDb(seedReleasedLink(['uidA', 'uidB']));
  fakeDb.__store.set('users/uidC', { uid: 'uidC' });
  await quiet(() =>
    linkIdentityAndSaveVerification(fakeDb, {
      uid: 'uidC', ci: CI, userPatch: {}, provider: 'nice',
    }),
  );

  const link = fakeDb.__store.get(`identityLinks/${CI_HASH}`);
  assert.deepStrictEqual(
    [...link.previousUids].sort(), ['uidA', 'uidB'],
    '거쳐 간 계정이 모두 남아야 관리자가 전체 사슬을 볼 수 있다',
  );
  assert.strictEqual(link.uid, 'uidC');
});

test('탈퇴 경로를 타지 않고 넘어간 링크도 직전 주인을 이력에 넣는다', async () => {
  // 정책 도입 전 문서처럼 previousUids가 아예 없는 링크.
  fakeDb = makeDb(seedReleasedLink(undefined));
  await quiet(() =>
    linkIdentityAndSaveVerification(fakeDb, {
      uid: 'uidB', ci: CI, userPatch: {}, provider: 'nice',
    }),
  );

  const link = fakeDb.__store.get(`identityLinks/${CI_HASH}`);
  assert.deepStrictEqual(
    link.previousUids, ['uidA'],
    '이력 필드가 없던 옛 링크에서도 연결이 끊기면 안 된다',
  );
});

test('같은 계정이 본인확인을 다시 해도 자기 자신은 이력에 들어가지 않는다', async () => {
  fakeDb = makeDb({
    'users/uidA': { uid: 'uidA' },
    [`identityLinks/${CI_HASH}`]: { uid: 'uidA', status: 'active', previousUids: [] },
  });
  await quiet(() =>
    linkIdentityAndSaveVerification(fakeDb, {
      uid: 'uidA', ci: CI, userPatch: {}, provider: 'nice',
    }),
  );

  const link = fakeDb.__store.get(`identityLinks/${CI_HASH}`);
  assert.deepStrictEqual(link.previousUids, [], '재인증은 재가입이 아니다');
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
      ? `\n회원 탈퇴 규칙 검증 통과 — ${cases.length}건`
      : `\n실패 ${failed}건 / 전체 ${cases.length}건`,
  );
  process.exit(failed === 0 ? 0 : 1);
})();

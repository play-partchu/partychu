// 대표자 위임 자체 검증 — `npm run check:delegation`.
//
// 여기서 못 박는 것.
//
// 1. **승인 링크를 가진 것은 권한이 아니다.** 토큰은 "어느 요청인가"만 지시하고,
//    권한은 evaluateApproval의 12개 검사가 준다. 그 중 하나라도 통과하지 못하면
//    'delegated'는 어디에도 쓰이지 않는다.
// 2. **회원 본인확인과 절대 섞이지 않는다.** 대표자가 회원이든 아니든, 승인이
//    끝난 뒤 그 사람의 users·identityLinks 문서는 **한 글자도 바뀌지 않아야**
//    한다("1명의 실사용자 = 파티츄 계정 1개" 정책을 건드리면 안 된다).
// 3. **소유와 운영권은 다른 문서다.** 위임 승인은 businessOwnership.holderUid를
//    건드리지 않는다. 건드리면 대표자 본인이 나중에 자기 사업자에서 막힌다.
// 4. **승인이 남기는 대표자 CI는 '확인된 대표자'가 아니라 충돌 감지용이다.**
//    근거가 이름 대조뿐이라 먼저 온 쪽이 동명이인일 수도 있다. 그래서 다른
//    CI가 나타나면 **자동으로 풀지 않고 멈춘다**(needsManualReview).
// 5. **토큰은 1회성이다.** 승인·거절·만료·취소 뒤에는 같은 토큰이 죽는다.
// 6. **대상이 바뀌면 승인은 성립하지 않는다.** subjectFingerprint가 그 집행자다.
// 7. **취소는 링크 소지가 아니라 대표자 본인확인으로만 된다.**

process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'selfcheck';

const assert = require('assert');
const crypto = require('crypto');

// ── 가짜 Firestore가 쓰는 시각·센티널 — require보다 먼저 갈아끼운다 ──────
const admin = require('firebase-admin');
// 검사 대상 코드는 만료를 실제 시각(Date.now())으로 판정한다 — 고정된 과거
// 시각을 쓰면 세션이 만들자마자 만료된 것으로 읽힌다.
const CLOCK = Date.now();
admin.firestore.FieldValue = {
  serverTimestamp: () => ({ __ts: true }),
  increment: (n) => ({ __inc: n }),
  arrayUnion: (...v) => ({ __arrayUnion: v }),
};
admin.firestore.Timestamp = {
  now: () => ({ toMillis: () => CLOCK }),
  fromMillis: (ms) => ({ toMillis: () => ms }),
};

const D = require('./businessDelegation');
const {
  STATUS, REFUSAL, APPROVAL_PURPOSE,
  MAX_NICE_ATTEMPTS, MAX_ACTIVE_DELEGATES, MAX_REQUESTS_PER_DAY,
  hashToken, hashCi, subjectFingerprint, resolvePendingSubject,
  evaluateApproval, evaluateRevoke, delegatedDecision, revokedPatch,
  createDelegationRequest, completeApproval, completeRevoke,
  revokeDelegationsForGrantee, maskForDisplay, landingHtml,
} = D;
const {
  isBusinessAuthorized, businessNumberHash, BUSINESS_OWNERSHIP,
  REP_VERIFICATION_LEVEL, representativeLevelOf,
} = require('./businessVerification');
const { verifyAndDecrypt, deriveKeys } = require('./niceIntcClient');
const { IDENTITY_LINKS } = require('./identityLink');

const cases = [];
const test = (name, fn) => cases.push([name, fn]);

// ══════════════════════════════════════════════════════════════════════════
// 가짜 Firestore — 쿼리·배치·트랜잭션·재귀 merge까지
//
// businessVerification.selfcheck.js의 것과 같은 재귀 merge 규칙을 쓴다(얕은
// 병합으로 두면 중첩 맵인 businessVerification을 통째로 날려버린다).
// ══════════════════════════════════════════════════════════════════════════
function deepMerge(base, patch) {
  const isMap = (v) => v !== null && typeof v === 'object' && !Array.isArray(v)
    && !v.__ts && !v.__inc && !v.__arrayUnion && typeof v.toMillis !== 'function';
  const out = { ...(base || {}) };
  for (const [k, v] of Object.entries(patch)) {
    if (v && v.__inc !== undefined) out[k] = (out[k] || 0) + v.__inc;
    else if (isMap(v) && isMap(out[k])) out[k] = deepMerge(out[k], v);
    else out[k] = v;
  }
  return out;
}

function makeDb(seed = {}) {
  const store = new Map(Object.entries(seed));
  const snapOf = (key) => {
    const data = store.get(key);
    return {
      id: key.split('/').slice(1).join('/'),
      exists: data !== undefined,
      data: () => data,
      get: (f) => (data ? data[f] : undefined),
      ref: { __key: key },
    };
  };
  const matches = (row, [f, op, v]) => {
    const val = row[f];
    if (op === '==') return val === v;
    if (op === 'in') return Array.isArray(v) && v.includes(val);
    throw new Error('미지원 연산자: ' + op);
  };

  function query(path, filters = [], order = null, limit = 0) {
    return {
      where: (f, op, v) => query(path, [...filters, [f, op, v]], order, limit),
      orderBy: (f, dir) => query(path, filters, [f, dir], limit),
      limit: (n) => query(path, filters, order, n),
      async get() {
        let rows = [...store.entries()]
          .filter(([k]) => k.startsWith(path + '/'))
          .filter(([, v]) => filters.every((f) => matches(v, f)))
          .map(([k]) => snapOf(k));
        if (order) {
          const [f, dir] = order;
          rows.sort((a, b) => {
            const av = a.data()[f]; const bv = b.data()[f];
            const an = av && av.toMillis ? av.toMillis() : (av || 0);
            const bn = bv && bv.toMillis ? bv.toMillis() : (bv || 0);
            return dir === 'desc' ? bn - an : an - bn;
          });
        }
        if (limit) rows = rows.slice(0, limit);
        return { empty: rows.length === 0, size: rows.length, docs: rows };
      },
    };
  }

  let autoId = 0;
  const write = (key, value, opts) => {
    store.set(key, opts && opts.merge ? deepMerge(store.get(key), value) : value);
  };

  const db = {
    __store: store,
    collection(path) {
      const q = query(path);
      return {
        ...q,
        doc(id) {
          const key = `${path}/${id === undefined ? `auto${++autoId}` : id}`;
          return {
            id: key.slice(path.length + 1),
            __key: key,
            async get() { return snapOf(key); },
            async set(v, o) { write(key, v, o); },
          };
        },
      };
    },
    batch() {
      const ops = [];
      return {
        set: (ref, v, o) => ops.push([ref.__key, v, o]),
        async commit() { for (const [k, v, o] of ops) write(k, v, o); },
      };
    },
    async runTransaction(fn) {
      const writes = [];
      const tx = {
        async get(refOrQuery) {
          if (refOrQuery.__key) return snapOf(refOrQuery.__key);
          return refOrQuery.get();
        },
        set: (ref, v, o) => writes.push([ref.__key, v, o]),
      };
      const result = await fn(tx);
      for (const [k, v, o] of writes) write(k, v, o);
      return result;
    },
  };
  return db;
}

// ══════════════════════════════════════════════════════════════════════════
// 시나리오 재료
// ══════════════════════════════════════════════════════════════════════════
const BNO = '2222222222';
const BN_HASH = businessNumberHash(BNO);
const OWNER_KEY = `${BUSINESS_OWNERSHIP}/${BN_HASH}`;
const REP_NAME = '김영희';       // 국세청이 확인한 대표자
const GRANTEE = 'uidHost';       // 신청자(배우자·직원 등)
const REP_CI = 'CI_대표자_김영희';
const REP_CI_HASH = hashCi(REP_CI);

/// 대표자 승인을 기다리는 신청자 문서(최상위가 pendingOwnerApproval).
const pendingUser = (o = {}) => ({
  identityVerified: true,
  name: '홍길동',              // 신청자 실명 — 대표자와 다르다
  nickname: '길동호스트',
  identityCiHash: 'CI_신청자_홍길동',
  businessVerification: {
    status: 'verified',
    authorization: 'pendingOwnerApproval',
    authorizationReason: 'representativeMismatch',
    delegationId: null,
    businessNumber: BNO,
    representativeName: REP_NAME,
    openingDate: '20200105',
    businessName: 'B상호',
    businessAddress: 'B주소',
    businessBaseAddress: 'B주소',
    businessDetailAddress: '',
    ntsStatusLabel: '계속사업자',
    taxType: '일반',
    attemptDate: '2026-08-29',
    attemptCount: 1,
    ...o,
  },
});

const niceOf = (name, ci) => ({ name, ci, birthdate: '19850101', gender: '0', mobile_no: '01000000000' });

/// 요청 생성 → 세션 생성 → 승인까지 한 번에. 각 단계를 옵션으로 비튼다.
async function setup(opts = {}) {
  const db = makeDb({ [`users/${GRANTEE}`]: pendingUser(opts.bv) , ...(opts.seed || {}) });
  const req = await createDelegationRequest(db, GRANTEE, {
    now: admin.firestore.FieldValue.serverTimestamp(),
    todayKey: '2026-08-29',
  });
  const sid = 'SID_' + Math.random().toString(36).slice(2);
  await db.collection('businessApprovalSessions').doc(sid).set({
    purpose: opts.purpose || APPROVAL_PURPOSE,
    action: opts.action || 'approve',
    delegationId: opts.sessionDelegationId || req.delegationId,
    requestNo: 'REQ1',
    transactionId: 'TX1',
    ticket: 'TICKET',
    iterators: 1000,
    used: opts.sessionUsed === true,
    consentAt: opts.noConsent ? null : { __ts: true },
    createdAt: { __ts: true },
    expiresAt: admin.firestore.Timestamp.fromMillis(CLOCK + 10 * 60 * 1000),
  });
  return { db, req, sid };
}

const delegationOf = (db, id) => db.__store.get(`businessDelegations/${id}`);
const userBv = (db, uid = GRANTEE) => db.__store.get(`users/${uid}`).businessVerification;

// ══════════════════════════════════════════════════════════════════════════
// A. 보안 불변식 12개 — evaluateApproval (순수)
// ══════════════════════════════════════════════════════════════════════════
const SUBJECT = {
  source: 'current',
  input: {
    businessNumber: BNO, representativeName: REP_NAME, openingDate: '20200105',
    businessName: 'B상호', businessAddress: 'B주소',
    businessBaseAddress: 'B주소', businessDetailAddress: '',
    ntsStatusLabel: '계속사업자', taxType: '일반',
  },
};
const FP = subjectFingerprint({
  granteeUid: GRANTEE, businessNumber: BNO, openingDate: '20200105', representativeName: REP_NAME,
});
const baseArgs = () => ({
  delegation: {
    id: 'DLG1', status: STATUS.requested, attemptCount: 1,
    expiresAt: { toMillis: () => CLOCK + 1000 }, subjectFingerprint: FP,
  },
  session: {
    purpose: APPROVAL_PURPOSE, used: false, delegationId: 'DLG1',
    consentAt: {}, expiresAt: { toMillis: () => CLOCK + 1000 },
  },
  now: CLOCK,
  consent: true,
  niceName: REP_NAME,
  niceCiHash: REP_CI_HASH,
  subject: SUBJECT,
  subjectFingerprintNow: FP,
  granteeCiHash: 'CI_신청자_홍길동',
  ownershipRepCiHash: null,
  activeDelegateCount: 0,
});

test('불변식: 12개를 모두 통과하면 승인된다(기준선)', () => {
  assert.deepStrictEqual(evaluateApproval(baseArgs()), { ok: true, refusal: null });
});

test('불변식①-a 링크가 없으면 거절', () => {
  assert.strictEqual(evaluateApproval({ ...baseArgs(), delegation: null }).refusal, REFUSAL.linkInvalid);
});

test('불변식①-b 이미 처리된 요청의 토큰은 다시 쓸 수 없다', () => {
  for (const st of [STATUS.approved, STATUS.rejected, STATUS.expired, STATUS.revoked]) {
    const a = baseArgs();
    a.delegation = { ...a.delegation, status: st };
    assert.strictEqual(evaluateApproval(a).refusal, REFUSAL.linkUsed, st + '가 통과했다');
  }
});

test('불변식①-c 만료된 링크는 거절', () => {
  const a = baseArgs();
  a.delegation = { ...a.delegation, expiresAt: { toMillis: () => CLOCK - 1 } };
  assert.strictEqual(evaluateApproval(a).refusal, REFUSAL.linkExpired);
});

test('불변식①-d NICE 시도 상한을 넘으면 거절', () => {
  const a = baseArgs();
  a.delegation = { ...a.delegation, attemptCount: MAX_NICE_ATTEMPTS + 1 };
  assert.strictEqual(evaluateApproval(a).refusal, REFUSAL.tooManyAttempts);
});

test('불변식②-a 세션이 없으면 거절', () => {
  assert.strictEqual(evaluateApproval({ ...baseArgs(), session: null }).refusal, REFUSAL.sessionInvalid);
});

test('불변식②-b **세션 목적이 다르면 거절** — 회원 본인확인 세션이 새어 들어올 수 없다', () => {
  const a = baseArgs();
  a.session = { ...a.session, purpose: 'identity' };
  assert.strictEqual(evaluateApproval(a).refusal, REFUSAL.sessionPurpose);
  const b = baseArgs();
  b.session = { ...b.session, purpose: undefined };
  assert.strictEqual(evaluateApproval(b).refusal, REFUSAL.sessionPurpose);
});

test('불변식②-c 이미 쓴 세션·만료된 세션은 거절', () => {
  const a = baseArgs(); a.session = { ...a.session, used: true };
  assert.strictEqual(evaluateApproval(a).refusal, REFUSAL.sessionUsed);
  const b = baseArgs(); b.session = { ...b.session, expiresAt: { toMillis: () => CLOCK - 1 } };
  assert.strictEqual(evaluateApproval(b).refusal, REFUSAL.sessionExpired);
});

test('불변식②-d 다른 요청의 세션으로는 승인할 수 없다', () => {
  const a = baseArgs();
  a.session = { ...a.session, delegationId: 'DLG_OTHER' };
  assert.strictEqual(evaluateApproval(a).refusal, REFUSAL.sessionMismatch);
});

test('불변식③ 대표자의 명시적 동의가 없으면 거절', () => {
  const a = baseArgs(); a.consent = false;
  assert.strictEqual(evaluateApproval(a).refusal, REFUSAL.consentMissing);
  const b = baseArgs(); b.session = { ...b.session, consentAt: null };
  assert.strictEqual(evaluateApproval(b).refusal, REFUSAL.consentMissing);
});

test('불변식④ NICE 실명이 국세청 대표자명과 다르면 거절', () => {
  const a = baseArgs(); a.niceName = '박철수';
  assert.strictEqual(evaluateApproval(a).refusal, REFUSAL.representativeMismatch);
});

test('불변식④-b 공백 차이는 같은 사람으로 본다(payoutAccounts 정규화 재사용)', () => {
  const a = baseArgs(); a.niceName = ' 김 영희 ';
  assert.strictEqual(evaluateApproval(a).ok, true);
});

test('불변식⑤ 요청 생성 후 대상이 바뀌면 승인이 성립하지 않는다', () => {
  const a = baseArgs(); a.subjectFingerprintNow = 'DIFFERENT';
  assert.strictEqual(evaluateApproval(a).refusal, REFUSAL.subjectChanged);
  const b = baseArgs(); b.subject = null;
  assert.strictEqual(evaluateApproval(b).refusal, REFUSAL.subjectChanged);
});

test('불변식⑥ 자기 자신에게 주는 승인은 막는다', () => {
  const a = baseArgs(); a.granteeCiHash = REP_CI_HASH;
  assert.strictEqual(evaluateApproval(a).refusal, REFUSAL.selfApproval);
});

test('불변식⑦ 기존 대표자 CI와 다르면 거절(자동 대체·자동 승인 금지)', () => {
  const a = baseArgs(); a.ownershipRepCiHash = hashCi('CI_다른대표자');
  assert.strictEqual(evaluateApproval(a).refusal, REFUSAL.representativeCiMismatch);
  // 같은 사람이면 통과한다(두 번째 위임).
  const b = baseArgs(); b.ownershipRepCiHash = REP_CI_HASH;
  assert.strictEqual(evaluateApproval(b).ok, true);
});

test('불변식⑧ 활성 위임 상한을 넘으면 거절', () => {
  const a = baseArgs(); a.activeDelegateCount = MAX_ACTIVE_DELEGATES;
  assert.strictEqual(evaluateApproval(a).refusal, REFUSAL.delegateLimit);
});

test('불변식 순서: 링크가 죽었으면 세션·이름을 보지도 않는다', () => {
  const a = baseArgs();
  a.delegation = { ...a.delegation, status: STATUS.revoked };
  a.session = null;
  a.niceName = '엉뚱한사람';
  assert.strictEqual(evaluateApproval(a).refusal, REFUSAL.linkUsed);
});

// ══════════════════════════════════════════════════════════════════════════
// B. 대표자가 **비회원**인 경우 — 전 구간
// ══════════════════════════════════════════════════════════════════════════

test('비회원 대표자 승인: delegated + 근거 문서 + CI 핀까지 한 번에 선다', async () => {
  const { db, req, sid } = await setup();
  assert.strictEqual(delegationOf(db, req.delegationId).status, STATUS.requested);
  assert.strictEqual(isBusinessAuthorized(userBv(db)), false, '승인 전인데 권한이 있다');

  const out = await completeApproval(db, { sid, niceResult: niceOf(REP_NAME, REP_CI) });
  assert.strictEqual(out.ok, true, '거절됨: ' + out.refusal);

  const bv = userBv(db);
  assert.strictEqual(bv.authorization, 'delegated');
  assert.strictEqual(bv.delegationId, req.delegationId);
  assert.strictEqual(bv.status, 'verified');
  assert.strictEqual(bv.businessNumber, BNO);
  assert.strictEqual(isBusinessAuthorized(bv), true, '권한이 열리지 않았다');

  const d = delegationOf(db, req.delegationId);
  assert.strictEqual(d.status, STATUS.approved);
  assert.strictEqual(d.grantorCiHash, REP_CI_HASH);
  assert.strictEqual(d.grantorUid, null, '비회원인데 uid가 붙었다');
  assert.ok(d.manageTokenHash, '관리 링크가 발급되지 않았다');
  assert.strictEqual(d.requestTokenHash, null, '승인 링크가 살아 있다');

  // CI는 기록되고, holderUid는 **건드리지 않는다**.
  const owner = db.__store.get(OWNER_KEY);
  assert.strictEqual(owner.representativeCiHash, REP_CI_HASH);
  assert.strictEqual(owner.representativeSource, 'ownerApproval');
  assert.strictEqual(owner.holderUid, undefined, '위임이 대표자 자리를 차지했다');
  // ★ 대표자 승인도 **self와 같은 이름 대조 등급**이다. 이 흐름이 CI를
  //   준다고 해서 '대표자임이 증명됐다'가 되는 것이 아니다.
  assert.strictEqual(
    owner.representativeVerificationLevel,
    REP_VERIFICATION_LEVEL.nameMatched,
    '대표자 승인이 이름 대조보다 강한 등급으로 기록됐다',
  );
  assert.strictEqual(representativeLevelOf(owner), REP_VERIFICATION_LEVEL.nameMatched);
});

test('감사 데이터에 CI 원문·휴대폰·이름이 남지 않는다', async () => {
  const { db, req, sid } = await setup();
  await completeApproval(db, { sid, niceResult: niceOf(REP_NAME, REP_CI) });
  const dump = JSON.stringify(delegationOf(db, req.delegationId));
  assert.ok(!dump.includes(REP_CI), 'CI 원문이 남았다');
  assert.ok(!dump.includes('01000000000'), '휴대폰 번호가 남았다');
  assert.ok(!dump.includes(REP_NAME), '대표자 이름이 남았다');
  assert.ok(!dump.includes(BNO), '사업자번호 원문이 남았다');
});

test('토큰 원문은 문서에 저장되지 않는다 — 해시만 남는다', async () => {
  const { db, req } = await setup();
  const d = delegationOf(db, req.delegationId);
  assert.ok(!JSON.stringify(d).includes(req.token), '토큰 원문이 저장됐다');
  assert.strictEqual(d.requestTokenHash, hashToken(req.token));
  assert.strictEqual(req.token.length >= 43, true, '토큰이 256비트보다 짧다');
});

// ══════════════════════════════════════════════════════════════════════════
// C. 대표자가 **회원**인 경우 — 기존 계정/CI 연결을 건드리지 않는다
// ══════════════════════════════════════════════════════════════════════════

test('회원 대표자 승인: grantorUid는 남기되 그 사람의 계정·CI 연결은 그대로다', async () => {
  const linkKey = `${IDENTITY_LINKS}/${REP_CI_HASH}`;
  const repUserBefore = {
    identityVerified: true, name: REP_NAME, nickname: '영희',
    identityCiHash: REP_CI_HASH, ci: REP_CI,
    businessVerification: { status: 'verified', authorization: 'self', businessNumber: '3333333333' },
  };
  const linkBefore = { uid: 'uidRep', status: 'active', provider: 'nice_intc_v2', linkedAt: 1 };
  const { db, sid } = await setup({
    seed: { 'users/uidRep': { ...repUserBefore }, [linkKey]: { ...linkBefore } },
  });

  const out = await completeApproval(db, { sid, niceResult: niceOf(REP_NAME, REP_CI) });
  assert.strictEqual(out.ok, true, '거절됨: ' + out.refusal);

  const d = db.__store.get(`businessDelegations/${out.delegationId}`);
  assert.strictEqual(d.grantorUid, 'uidRep', '회원인데 감사용 uid가 안 붙었다');

  // ★ 핵심: 대표자 쪽 문서는 한 글자도 바뀌지 않아야 한다.
  assert.deepStrictEqual(db.__store.get('users/uidRep'), repUserBefore, '대표자 계정이 변경됐다');
  assert.deepStrictEqual(db.__store.get(linkKey), linkBefore, 'identityLinks가 변경됐다');
});

test('대표자의 CI 링크가 released면 grantorUid를 붙이지 않는다(승인 자체는 된다)', async () => {
  const linkKey = `${IDENTITY_LINKS}/${REP_CI_HASH}`;
  const { db, sid } = await setup({
    seed: { [linkKey]: { uid: 'uidGone', status: 'released' } },
  });
  const out = await completeApproval(db, { sid, niceResult: niceOf(REP_NAME, REP_CI) });
  assert.strictEqual(out.ok, true);
  assert.strictEqual(db.__store.get(`businessDelegations/${out.delegationId}`).grantorUid, null);
});

// ══════════════════════════════════════════════════════════════════════════
// D. 동명이인 + CI 핀
// ══════════════════════════════════════════════════════════════════════════

test('**역전 위험**: 동명이인이 먼저 확인을 마쳤으면 실제 대표자도 막힌다', async () => {
  // 이 설계의 알려진 한계다. 먼저 박힌 CI가 진짜라는 보장이 없으므로,
  // 실제 대표자가 뒤에 와도 자동으로는 통과시키지 않는다 — 대신 사람이
  // 볼 수 있게 needsManualReview로 남긴다.
  const { db, req, sid } = await setup({
    seed: {
      [OWNER_KEY]: {
        representativeCiHash: hashCi('CI_먼저온_동명이인'),
        representativeVerificationLevel: REP_VERIFICATION_LEVEL.nameMatched,
        status: 'active',
      },
    },
  });
  // 진짜 대표자(이름도 맞고 CI도 진짜)가 승인을 시도한다.
  const out = await completeApproval(db, { sid, niceResult: niceOf(REP_NAME, REP_CI) });
  assert.strictEqual(out.ok, false, '자동으로 통과시켰다');
  assert.strictEqual(out.refusal, REFUSAL.representativeCiMismatch);
  const d = delegationOf(db, req.delegationId);
  assert.strictEqual(d.needsManualReview, true, '사람이 볼 수 있게 남기지 않았다');
  // 먼저 박힌 값도 그대로다 — 어느 쪽도 자동으로 이기지 않는다.
  assert.strictEqual(db.__store.get(OWNER_KEY).representativeCiHash, hashCi('CI_먼저온_동명이인'));
});

test('동명이인: 이름은 같지만 다른 자연인은 두 번째 승인을 통과하지 못한다', async () => {
  const { db, sid } = await setup({
    seed: { [OWNER_KEY]: { representativeCiHash: hashCi('CI_진짜대표자'), status: 'active' } },
  });
  const out = await completeApproval(db, { sid, niceResult: niceOf(REP_NAME, '동명이인_CI') });
  assert.strictEqual(out.ok, false);
  assert.strictEqual(out.refusal, REFUSAL.representativeCiMismatch);
  assert.strictEqual(userBv(db).authorization, 'pendingOwnerApproval', '권한이 열렸다');
});

test('동명이인: 수동심사 필요 상태가 문서에 남는다(심사 절차는 다음 단계)', async () => {
  const { db, req, sid } = await setup({
    seed: { [OWNER_KEY]: { representativeCiHash: hashCi('CI_진짜대표자'), status: 'active' } },
  });
  await completeApproval(db, { sid, niceResult: niceOf(REP_NAME, '동명이인_CI') });
  const d = delegationOf(db, req.delegationId);
  assert.strictEqual(d.lastRefusal, REFUSAL.representativeCiMismatch);
  assert.strictEqual(d.needsManualReview, true);
  // 상태는 그대로 requested — 진짜 대표자는 같은 링크로 다시 시도할 수 있다.
  assert.strictEqual(d.status, STATUS.requested);
});

test('그 밖의 거절은 수동심사 대상이 아니다', async () => {
  const { db, req, sid } = await setup();
  await completeApproval(db, { sid, niceResult: niceOf('가로챈사람', 'CI_공격자') });
  const d = delegationOf(db, req.delegationId);
  assert.strictEqual(d.lastRefusal, REFUSAL.representativeMismatch);
  assert.strictEqual(d.needsManualReview, false);
});

test('동명이인: 기존 CI 핀을 **자동으로 덮어쓰지 않는다**(모순은 사람이 본다)', async () => {
  const pinned = hashCi('CI_진짜대표자');
  const { db, sid } = await setup({
    seed: { [OWNER_KEY]: { representativeCiHash: pinned, status: 'active' } },
  });
  await completeApproval(db, { sid, niceResult: niceOf(REP_NAME, '동명이인_CI') });
  assert.strictEqual(db.__store.get(OWNER_KEY).representativeCiHash, pinned, '핀이 덮어써졌다');
});

test('같은 대표자는 두 번째 계정에도 위임할 수 있다(1 대표자 + N 운영자)', async () => {
  // 첫 승인으로 CI 핀이 박힌 뒤, 같은 대표자가 다른 계정에 또 위임한다.
  const { db, sid } = await setup();
  await completeApproval(db, { sid, niceResult: niceOf(REP_NAME, REP_CI) });

  db.__store.set('users/uidHost2', pendingUser());
  const req2 = await createDelegationRequest(db, 'uidHost2', {
    now: { __ts: true }, todayKey: '2026-08-29',
  });
  await db.collection('businessApprovalSessions').doc('SID2').set({
    purpose: APPROVAL_PURPOSE, action: 'approve', delegationId: req2.delegationId,
    requestNo: 'R', transactionId: 'T', ticket: 'K', iterators: 1000,
    used: false, consentAt: {},
    expiresAt: admin.firestore.Timestamp.fromMillis(CLOCK + 600000),
  });
  const out2 = await completeApproval(db, { sid: 'SID2', niceResult: niceOf(REP_NAME, REP_CI) });
  assert.strictEqual(out2.ok, true, '거절됨: ' + out2.refusal);
  assert.strictEqual(isBusinessAuthorized(userBv(db, 'uidHost')), true, '첫 운영자 권한이 사라졌다');
  assert.strictEqual(isBusinessAuthorized(userBv(db, 'uidHost2')), true);
  // 점유 문서는 여전히 대표자 자리를 비워 둔다.
  assert.strictEqual(db.__store.get(OWNER_KEY).holderUid, undefined);
});

// ══════════════════════════════════════════════════════════════════════════
// E. 토큰 — 탈취 / 재사용 / 만료 / 시도 초과
// ══════════════════════════════════════════════════════════════════════════

test('토큰 탈취: 링크를 가로채도 대표자명으로 NICE를 통과하지 못하면 아무것도 못 한다', async () => {
  const { db, sid } = await setup();
  const out = await completeApproval(db, { sid, niceResult: niceOf('가로챈사람', 'CI_공격자') });
  assert.strictEqual(out.ok, false);
  assert.strictEqual(out.refusal, REFUSAL.representativeMismatch);
  assert.strictEqual(userBv(db).authorization, 'pendingOwnerApproval');
  assert.strictEqual(db.__store.get(OWNER_KEY), undefined, '실패했는데 CI 핀이 박혔다');
});

test('토큰 재사용: 승인이 끝나면 같은 세션으로 다시 승인할 수 없다', async () => {
  const { db, sid } = await setup();
  assert.strictEqual((await completeApproval(db, { sid, niceResult: niceOf(REP_NAME, REP_CI) })).ok, true);
  const again = await completeApproval(db, { sid, niceResult: niceOf(REP_NAME, REP_CI) });
  assert.strictEqual(again.ok, false);
  // 세션도 죽고 위임도 requested가 아니다 — 어느 쪽이 먼저 걸려도 거절이다.
  assert.ok([REFUSAL.linkUsed, REFUSAL.sessionUsed].includes(again.refusal), again.refusal);
});

test('토큰 재사용: 승인 후 requestTokenHash가 지워져 링크가 죽는다', async () => {
  const { db, req, sid } = await setup();
  await completeApproval(db, { sid, niceResult: niceOf(REP_NAME, REP_CI) });
  assert.strictEqual(delegationOf(db, req.delegationId).requestTokenHash, null);
});

test('만료: 유효기간이 지난 요청은 승인되지 않는다', async () => {
  const { db, req, sid } = await setup();
  // 72시간 뒤로 시계를 돌린다.
  db.__store.get(`businessDelegations/${req.delegationId}`).expiresAt = { toMillis: () => Date.now() - 1 };
  const out = await completeApproval(db, { sid, niceResult: niceOf(REP_NAME, REP_CI) });
  assert.strictEqual(out.refusal, REFUSAL.linkExpired);
});

test('시도 초과: NICE를 5회 넘게 시도하면 막힌다', async () => {
  const { db, req, sid } = await setup();
  delegationOf(db, req.delegationId).attemptCount = MAX_NICE_ATTEMPTS + 1;
  const out = await completeApproval(db, { sid, niceResult: niceOf(REP_NAME, REP_CI) });
  assert.strictEqual(out.refusal, REFUSAL.tooManyAttempts);
});

test('새 요청을 만들면 이전 링크가 죽는다(살아 있는 링크는 항상 하나)', async () => {
  const { db, req } = await setup();
  const req2 = await createDelegationRequest(db, GRANTEE, {
    now: { __ts: true }, todayKey: '2026-08-29',
  });
  assert.strictEqual(delegationOf(db, req.delegationId).status, STATUS.expired);
  assert.strictEqual(delegationOf(db, req.delegationId).expiredReason, 'superseded');
  assert.strictEqual(delegationOf(db, req2.delegationId).status, STATUS.requested);
  assert.notStrictEqual(req.token, req2.token);
});

test(`하루 요청 생성은 ${MAX_REQUESTS_PER_DAY}회로 제한된다`, async () => {
  const { db } = await setup(); // 1회 사용
  await createDelegationRequest(db, GRANTEE, { now: { __ts: true }, todayKey: '2026-08-29' });
  await createDelegationRequest(db, GRANTEE, { now: { __ts: true }, todayKey: '2026-08-29' });
  await assert.rejects(
    () => createDelegationRequest(db, GRANTEE, { now: { __ts: true }, todayKey: '2026-08-29' }),
    (e) => e.code === 'resource-exhausted',
  );
  // 날이 바뀌면 다시 된다.
  await createDelegationRequest(db, GRANTEE, { now: { __ts: true }, todayKey: '2026-08-30' });
});

test('요청 생성도 본인확인을 요구한다(신청자 쪽 게이트)', async () => {
  const db = makeDb({ 'users/uidX': { ...pendingUser(), identityVerified: false, isVerified: false } });
  await assert.rejects(
    () => createDelegationRequest(db, 'uidX', { now: { __ts: true }, todayKey: '2026-08-29' }),
    (e) => e.code === 'failed-precondition',
  );
});

test('대표자 승인이 필요한 사업자가 없으면 요청을 만들 수 없다', async () => {
  const db = makeDb({
    'users/uidY': {
      identityVerified: true, name: '홍길동',
      businessVerification: { status: 'verified', authorization: 'self', businessNumber: BNO },
    },
  });
  await assert.rejects(
    () => createDelegationRequest(db, 'uidY', { now: { __ts: true }, todayKey: '2026-08-29' }),
    (e) => e.code === 'failed-precondition',
  );
});

// ══════════════════════════════════════════════════════════════════════════
// F. 대상(subject) 변경
// ══════════════════════════════════════════════════════════════════════════

test('subject 변경: 요청 후 사업자번호를 바꾸면 기존 승인이 성립하지 않는다', async () => {
  const { db, sid } = await setup();
  userBv(db).businessNumber = '9999999999';
  const out = await completeApproval(db, { sid, niceResult: niceOf(REP_NAME, REP_CI) });
  assert.strictEqual(out.ok, false);
  assert.strictEqual(out.refusal, REFUSAL.subjectChanged);
});

test('subject 변경: 대표자명·개업일자를 바꿔도 마찬가지다', async () => {
  for (const patch of [{ representativeName: '김영희2' }, { openingDate: '20210101' }]) {
    const { db, sid } = await setup();
    Object.assign(userBv(db), patch);
    const out = await completeApproval(db, { sid, niceResult: niceOf(REP_NAME, REP_CI) });
    assert.strictEqual(out.ok, false, JSON.stringify(patch) + '가 통과했다');
  }
});

test('subject 변경: 신청자가 이미 본인 명의로 인증을 마쳤으면 승인 대상이 사라진다', async () => {
  const { db, sid } = await setup();
  Object.assign(userBv(db), { authorization: 'self', authorizationReason: null });
  const out = await completeApproval(db, { sid, niceResult: niceOf(REP_NAME, REP_CI) });
  assert.strictEqual(out.refusal, REFUSAL.subjectChanged);
});

test('대상 해석: 최상위와 pendingChange 중 대기 중인 쪽을 고른다', () => {
  const a = resolvePendingSubject({
    status: 'verified', authorization: 'self', businessNumber: '1111111111',
    pendingChange: {
      status: 'verified', authorization: 'pendingOwnerApproval', businessNumber: BNO,
      representativeName: REP_NAME, openingDate: '20200105',
    },
  });
  assert.strictEqual(a.source, 'pendingChange');
  assert.strictEqual(a.input.businessNumber, BNO);

  const b = resolvePendingSubject({
    status: 'verified', authorization: 'pendingOwnerApproval', businessNumber: BNO,
  });
  assert.strictEqual(b.source, 'current');

  assert.strictEqual(resolvePendingSubject({ status: 'verified', authorization: 'self' }), null);
  assert.strictEqual(resolvePendingSubject(null), null);
});

test('기존 self 사업자를 쓰던 사람도 위임으로 다른 사업자로 옮길 수 있다', async () => {
  // keptVerified 상태(A는 self, B는 pendingChange)에서 B를 승인받는다.
  const db = makeDb({
    [`users/${GRANTEE}`]: {
      identityVerified: true, name: '홍길동', nickname: '길동', identityCiHash: 'CI_신청자',
      businessVerification: {
        status: 'verified', authorization: 'self', businessNumber: '1111111111',
        representativeName: '홍길동', openingDate: '20190101',
        pendingChange: {
          status: 'verified', authorization: 'pendingOwnerApproval',
          businessNumber: BNO, representativeName: REP_NAME, openingDate: '20200105',
          businessName: 'B상호', businessAddress: 'B주소',
          businessBaseAddress: 'B주소', businessDetailAddress: '',
          ntsStatusLabel: '계속사업자', taxType: '일반',
        },
      },
    },
  });
  const req = await createDelegationRequest(db, GRANTEE, { now: { __ts: true }, todayKey: '2026-08-29' });
  await db.collection('businessApprovalSessions').doc('S').set({
    purpose: APPROVAL_PURPOSE, action: 'approve', delegationId: req.delegationId,
    requestNo: 'R', transactionId: 'T', ticket: 'K', iterators: 1000,
    used: false, consentAt: {},
    expiresAt: admin.firestore.Timestamp.fromMillis(CLOCK + 600000),
  });
  const out = await completeApproval(db, { sid: 'S', niceResult: niceOf(REP_NAME, REP_CI) });
  assert.strictEqual(out.ok, true, '거절됨: ' + out.refusal);

  const bv = userBv(db);
  assert.strictEqual(bv.businessNumber, BNO, 'B로 교체되지 않았다');
  assert.strictEqual(bv.authorization, 'delegated');
  assert.strictEqual(bv.pendingChange, null, '변경 시도 흔적이 남았다');
  assert.strictEqual(bv.previousBusinessNumber, '1111111111', '교체 이력이 없다');
});

// ══════════════════════════════════════════════════════════════════════════
// G. 취소
// ══════════════════════════════════════════════════════════════════════════

async function approvedFixture() {
  const { db, req, sid } = await setup();
  const out = await completeApproval(db, { sid, niceResult: niceOf(REP_NAME, REP_CI) });
  const rsid = 'RSID';
  await db.collection('businessApprovalSessions').doc(rsid).set({
    purpose: APPROVAL_PURPOSE, action: 'revoke', delegationId: req.delegationId,
    requestNo: 'R2', transactionId: 'T2', ticket: 'K', iterators: 1000,
    used: false, consentAt: {},
    expiresAt: admin.firestore.Timestamp.fromMillis(CLOCK + 600000),
  });
  return { db, req, rsid, manageToken: out.manageToken };
}

test('취소: 승인했던 대표자가 NICE를 다시 통과하면 권한이 즉시 닫힌다', async () => {
  const { db, req, rsid } = await approvedFixture();
  assert.strictEqual(isBusinessAuthorized(userBv(db)), true);

  const out = await completeRevoke(db, { sid: rsid, niceResult: niceOf(REP_NAME, REP_CI) });
  assert.strictEqual(out.ok, true, '거절됨: ' + out.refusal);

  const bv = userBv(db);
  assert.strictEqual(isBusinessAuthorized(bv), false, '권한이 남았다');
  assert.strictEqual(bv.authorization, 'pendingOwnerApproval');
  assert.strictEqual(bv.authorizationReason, 'delegationRevoked');
  assert.strictEqual(bv.delegationId, null);
  // 사업자 진위 자체는 건드리지 않는다.
  assert.strictEqual(bv.status, 'verified');
  assert.strictEqual(bv.businessNumber, BNO);
  assert.strictEqual(delegationOf(db, req.delegationId).status, STATUS.revoked);
  assert.strictEqual(delegationOf(db, req.delegationId).manageTokenHash, null);
});

test('취소: **관리 링크를 가진 것만으로는 취소되지 않는다** — 다른 사람은 못 끊는다', async () => {
  const { db, rsid } = await approvedFixture();
  const out = await completeRevoke(db, { sid: rsid, niceResult: niceOf(REP_NAME, 'CI_다른사람') });
  assert.strictEqual(out.ok, false);
  assert.strictEqual(out.refusal, REFUSAL.notGrantor, '동명이인이 남의 위임을 끊었다');
  assert.strictEqual(isBusinessAuthorized(userBv(db)), true, '권한이 끊겼다');
});

test('취소: 이름이 대표자와 다르면 CI를 논하기 전에 막힌다', async () => {
  const { db, rsid } = await approvedFixture();
  const out = await completeRevoke(db, { sid: rsid, niceResult: niceOf('엉뚱한이름', REP_CI) });
  assert.strictEqual(out.refusal, REFUSAL.representativeMismatch);
});

test('취소: 같은 관리 세션을 두 번 쓸 수 없다', async () => {
  const { db, rsid } = await approvedFixture();
  assert.strictEqual((await completeRevoke(db, { sid: rsid, niceResult: niceOf(REP_NAME, REP_CI) })).ok, true);
  const again = await completeRevoke(db, { sid: rsid, niceResult: niceOf(REP_NAME, REP_CI) });
  assert.strictEqual(again.ok, false);
});

test('취소: 그 사이 다른 근거로 권한을 얻었으면 건드리지 않는다', async () => {
  const { db, rsid } = await approvedFixture();
  // 신청자가 그 사이 본인 명의로 다시 인증했다.
  Object.assign(userBv(db), {
    authorization: 'self', delegationId: null, businessNumber: '1111111111',
    representativeName: '홍길동',
  });
  const out = await completeRevoke(db, { sid: rsid, niceResult: niceOf('홍길동', REP_CI) });
  // 이름 대조는 현재 사업자 기준이라 통과하고, 위임은 취소된다.
  assert.strictEqual(out.ok, true, '거절됨: ' + out.refusal);
  assert.strictEqual(userBv(db).authorization, 'self', '남의 근거로 열린 권한을 끊었다');
});

test('탈퇴: 신청자가 탈퇴하면 그 계정의 위임이 전부 끊긴다', async () => {
  const { db, req } = await approvedFixture();
  const r = await revokeDelegationsForGrantee(db, GRANTEE);
  assert.strictEqual(r.revoked, 1);
  const d = delegationOf(db, req.delegationId);
  assert.strictEqual(d.status, STATUS.revoked);
  assert.strictEqual(d.revokedBy, 'granteeWithdrawal');
  assert.strictEqual(d.manageTokenHash, null, '탈퇴 후에도 관리 링크가 살아 있다');
});

// ══════════════════════════════════════════════════════════════════════════
// H. 회귀 — 회원 본인확인 암호 경로
// ══════════════════════════════════════════════════════════════════════════

test('NICE 무결성: integrity_value가 다르면 복호화 자체를 하지 않는다', () => {
  const session = { ticket: 'TICKET', transactionId: 'TX', iterators: 2000 };
  const { key } = deriveKeys(session.ticket, session.transactionId, session.iterators);
  const iv = crypto.randomBytes(16);
  const c = crypto.createCipheriv('aes-256-gcm', key, iv);
  const ct = Buffer.concat([c.update(JSON.stringify({ name: REP_NAME, ci: REP_CI }), 'utf8'), c.final()]);
  const enc = Buffer.concat([iv, ct, c.getAuthTag()]).toString('base64url');

  // 위조된 integrity_value → HttpsError
  assert.throws(
    () => verifyAndDecrypt({ enc_data: enc, integrity_value: 'FORGED' }, session, 'test'),
    (e) => e.code === 'invalid-argument',
  );
  // 올바른 값이면 그대로 복호화된다(회원 본인확인과 같은 코드).
  const { computeIntegrityValue } = require('./niceIntcClient');
  const { hmacKey } = deriveKeys(session.ticket, session.transactionId, session.iterators);
  const ok = verifyAndDecrypt(
    { enc_data: enc, integrity_value: computeIntegrityValue(enc, hmacKey) }, session, 'test',
  );
  assert.strictEqual(ok.name, REP_NAME);
});

test('승인 페이지: 신청자 닉네임이 그대로 HTML에 박히지 않는다(XSS)', () => {
  // 닉네임은 nicknames.js가 한글·영문·숫자로 제한하지만, 승인 페이지는
  // 로그인 없이 열리는 외부 페이지라 방어를 규칙 하나에 기대지 않는다.
  const html = landingHtml({
    action: 'approve',
    delegation: { businessNumberMasked: '222-22-*****', __rawToken: 'TOK"><b>x' },
    granteeNickname: '<img src=x onerror=alert(1)>',
  });
  // 중요한 것은 "그 문자열이 없는가"가 아니라 **마크업으로 살아났는가**다.
  // 이스케이프된 텍스트에는 onerror 같은 단어가 그대로 남아 있어도 안전하다.
  assert.ok(!html.includes('<img'), '닉네임이 태그로 살아났다');
  assert.ok(html.includes('&lt;img src=x onerror=alert(1)&gt;'), '이스케이프 결과가 없다');
  // 토큰은 속성값 안에 들어간다 — 따옴표를 탈출하면 안 된다.
  assert.ok(!html.includes('value="TOK"><b>'), '토큰이 속성을 탈출했다');
  assert.ok(html.includes('TOK&quot;&gt;&lt;b&gt;x'), '토큰이 이스케이프되지 않았다');
});

test('승인 페이지: 검색엔진 색인과 referrer 유출을 막는다', () => {
  const html = landingHtml({
    action: 'approve',
    delegation: { businessNumberMasked: '222-22-*****', __rawToken: 'T' },
    granteeNickname: '길동',
  });
  assert.ok(html.includes('noindex'), '승인 링크가 색인될 수 있다');
  assert.ok(html.includes('no-referrer'), '토큰이 referrer로 새어 나갈 수 있다');
  // 관계(가족·배우자·직원)를 묻지 않는다.
  for (const w of ['가족', '배우자', '직원', '관계']) {
    assert.ok(!html.includes(w), '관계를 묻는 문구가 있다: ' + w);
  }
});

test('문구: CI 충돌 안내가 "대표자가 아니다"로 단정하지 않는다', () => {
  const msg = D.refusalMessage(REFUSAL.representativeCiMismatch);
  assert.ok(msg.includes('일치하지 않'), '사실(불일치)을 말하지 않는다');
  for (const bad of ['대표자가 아', '본인이 아', '허위', '도용']) {
    assert.ok(!msg.includes(bad), `단정하는 표현이 있다: ${bad}`);
  }
});

test('문구: 승인 페이지가 확인 범위(성함 일치)를 과장하지 않는다', () => {
  const html = landingHtml({
    action: 'approve',
    delegation: { businessNumberMasked: '222-22-*****', __rawToken: 'T' },
    granteeNickname: '길동',
  });
  assert.ok(html.includes('성함 일치'), '무엇까지 확인하는지 말하지 않는다');
  assert.ok(html.includes('동명이인'), '동명이인 한계를 알리지 않는다');
});

test('표시용 마스킹은 사업자번호 뒷자리를 드러내지 않는다', () => {
  assert.strictEqual(maskForDisplay('1234567890'), '123-45-*****');
  assert.strictEqual(maskForDisplay('123'), '***-**-*****');
  assert.ok(!maskForDisplay('1234567890').includes('67890'));
});

test('권한 판정 조각: 위임 결정은 점유를 가져가지 않는다', () => {
  const d = delegatedDecision('DLG1');
  assert.strictEqual(d.authorization, 'delegated');
  assert.strictEqual(d.claimOwnership, false, '위임이 대표자 자리를 차지한다');
  assert.strictEqual(d.delegationId, 'DLG1');
  const r = revokedPatch('<now>');
  assert.strictEqual(r.authorization, 'pendingOwnerApproval');
  assert.strictEqual(r.delegationId, null);
  assert.strictEqual(r.status, undefined, '취소가 사업자 진위까지 건드린다');
});

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
  console.log(
    failed === 0
      ? `\n대표자 위임 검증 통과 — ${cases.length}건`
      : `\n실패 ${failed}건 / 전체 ${cases.length}건`,
  );
  process.exit(failed === 0 ? 0 : 1);
})();

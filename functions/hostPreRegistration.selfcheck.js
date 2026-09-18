// 호스트 사전등록 자체 검증 — `npm run check:preregistration`.
//
// 여기서 못 박는 것.
//
// 1. **웹훅은 같은 항목을 한 번만 만든다.** FormHug 재전송이 몇 번 와도 문서와
//    '신청 접수' 이력은 하나다.
// 2. **키가 없거나 틀리면 아무것도 쓰지 않는다.** FormHug에는 서명이 없어 URL
//    key가 유일한 관문이다.
// 3. **필드 번호를 코드가 정하지 않는다.** 매핑이 없으면 일련번호만 남기고
//    값은 읽지 않는다.
// 4. **대표자 링크는 기존 createDelegationRequest가 만든다.** 72시간·하루 3회·
//    이전 링크 만료 규칙이 앱과 같은 카운터로 집행되고, 토큰 원문은 신청서·
//    이력 어디에도 남지 않는다.
// 5. **사전등록 상태는 호스트의 businessVerification을 따라갈 뿐이다.** 신청서의
//    사업자번호와 다른 사업자의 권한으로는 'verified'가 되지 않는다.
// 6. **이메일 일치는 연결 근거일 뿐 인증이 아니다.** 연결해도 호스트 문서의
//    identityVerified·businessVerification은 바뀌지 않는다.
// 7. 관리자 아닌 계정은 모든 관리자 경로에서 막힌다.
// 8. 로그에 이메일·전화번호·이름·링크가 나가지 않는다.

process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'selfcheck';
process.env.FORMHUG_WEBHOOK_KEY = 'webhook-key-for-selfcheck';
process.env.FORMHUG_API_TOKEN = '';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const admin = require('firebase-admin');
const CLOCK = Date.now();
const FieldValue = {
  serverTimestamp: () => ({ __ts: true }),
  increment: (n) => ({ __inc: n }),
  arrayUnion: (...v) => ({ __arrayUnion: v }),
};
const Timestamp = {
  now: () => ({ toMillis: () => CLOCK }),
  fromMillis: (ms) => ({ toMillis: () => ms }),
};
// ⚠️ admin.firestore는 **접근할 때마다 새 함수를 돌려주는 getter**다.
//    `admin.firestore.FieldValue = …`로 갈아끼우면 다음 접근에서 사라진다
//    (진짜 ServerTimestampTransform이 섞여 들어온다). getter 자체를 바꾼다.
//    핸들러를 통째로 부르는 검사는 currentDb에 가짜 DB를 꽂는다.
let currentDb = null;
Object.defineProperty(admin, 'firestore', {
  configurable: true,
  writable: true,
  value: Object.assign(() => {
    if (!currentDb) throw new Error('selfcheck: currentDb가 비어 있다');
    return currentDb;
  }, { FieldValue, Timestamp }),
});

const HP = require('./hostPreRegistration');
const H = HP.__test;
const D = require('./businessDelegation');
const { businessNumberHash } = require('./businessVerification');

const cases = [];
const test = (name, fn) => cases.push([name, fn]);

// ══════════════════════════════════════════════════════════════════════════
// 가짜 Firestore — businessDelegation.selfcheck.js와 같은 규칙에 하위 컬렉션·
// 점 경로 필드·삽입 순서 정렬을 더했다.
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
  const order = new Map([...store.keys()].map((k, i) => [k, i]));
  let seq = store.size;
  const getPath = (row, f) => f.split('.').reduce((o, k) => (o == null ? undefined : o[k]), row);
  const snapOf = (key) => {
    const data = store.get(key);
    return {
      id: key.split('/').pop(),
      exists: data !== undefined,
      data: () => data,
      ref: { __key: key },
    };
  };
  const matches = (row, [f, op, v]) => {
    const val = getPath(row, f);
    if (op === '==') return val === v;
    if (op === 'in') return Array.isArray(v) && v.includes(val);
    throw new Error('미지원 연산자: ' + op);
  };

  function query(p, filters = [], ord = null, limit = 0) {
    return {
      where: (f, op, v) => query(p, [...filters, [f, op, v]], ord, limit),
      orderBy: (f, dir) => query(p, filters, [f, dir], limit),
      limit: (n) => query(p, filters, ord, n),
      async get() {
        let rows = [...store.entries()]
          .filter(([k]) => k.startsWith(p + '/') && !k.slice(p.length + 1).includes('/'))
          .filter(([, v]) => filters.every((f) => matches(v, f)))
          .map(([k]) => snapOf(k));
        if (ord) {
          const [f, dir] = ord;
          const num = (s) => {
            const v = s.data()[f];
            return v && typeof v.toMillis === 'function' ? v.toMillis() : (typeof v === 'number' ? v : null);
          };
          rows.sort((a, b) => {
            const an = num(a); const bn = num(b);
            const cmp = an != null && bn != null && an !== bn
              ? an - bn
              : order.get(a.ref.__key) - order.get(b.ref.__key);
            return dir === 'desc' ? -cmp : cmp;
          });
        }
        if (limit) rows = rows.slice(0, limit);
        return { empty: rows.length === 0, size: rows.length, docs: rows };
      },
    };
  }

  let autoId = 0;
  const write = (key, value, opts) => {
    if (!order.has(key)) order.set(key, seq++);
    store.set(key, opts && opts.merge ? deepMerge(store.get(key), value) : value);
  };
  const docRef = (p, id) => {
    const key = `${p}/${id === undefined ? `auto${++autoId}` : id}`;
    return {
      id: key.split('/').pop(),
      __key: key,
      async get() { return snapOf(key); },
      async set(v, o) { write(key, v, o); },
      collection: (sub) => collectionRef(`${key}/${sub}`),
    };
  };
  const collectionRef = (p) => ({
    ...query(p),
    doc: (id) => docRef(p, id),
    async add(v) {
      const ref = docRef(p);
      write(ref.__key, v);
      return ref;
    },
  });

  return {
    __store: store,
    collection: (p) => collectionRef(p),
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
}

const rowsUnder = (db, prefix) => [...db.__store.entries()]
  .filter(([k]) => k.startsWith(prefix + '/') && !k.slice(prefix.length + 1).includes('/'))
  .map(([k, v]) => ({ id: k.split('/').pop(), ...v }));

async function captureLogs(fn) {
  const lines = [];
  const orig = { log: console.log, warn: console.warn, error: console.error };
  for (const k of Object.keys(orig)) console[k] = (...a) => lines.push(a.map(String).join(' '));
  try {
    await fn();
  } finally {
    Object.assign(console, orig);
  }
  return lines.join('\n');
}

const expectCode = (code) => (e) => {
  assert.strictEqual(e.code, code, `기대 ${code}, 실제 ${e.code}: ${e.message}`);
  return true;
};

// ══════════════════════════════════════════════════════════════════════════
// 재료 — 아래 라벨은 셀프체크용 가짜 폼이다(운영 매핑은 관리자가 저장한다).
// ══════════════════════════════════════════════════════════════════════════
const FORM = {
  name: '가짜 사전등록 폼',
  token: H.FORMHUG_FORM_TOKEN,
  fields: [
    { api_code: 'field_1', label: '업체명', type: 'short_text', required: true },
    { api_code: 'field_2', label: '사업자등록번호', type: 'short_text', required: true },
    { api_code: 'field_3', label: '호스트 신청자 이름', type: 'short_text', required: true },
    { api_code: 'field_4', label: '호스트 가입용 이메일', type: 'email', required: true },
    { api_code: 'field_5', label: '호스트 연락처', type: 'phone', required: true },
    {
      api_code: 'field_6', label: '호스트 신청자와 사업자 대표자가 동일한가요?', type: 'radio',
      choices: [{ api_code: 'c_yes', label: '예' }, { api_code: 'c_no', label: '아니오' }],
    },
    { api_code: 'field_7', label: '사업자 대표자 이름', type: 'short_text' },
    { api_code: 'field_8', label: '대표자 연락처', type: 'phone' },
    { api_code: 'field_9', label: '대표자 이메일', type: 'email' },
    {
      api_code: 'field_10', label: '사용 예정 기기', type: 'checkbox',
      choices: [
        { api_code: 'd_and', label: '갤럭시(Android)' },
        { api_code: 'd_ios', label: '아이폰(iOS)' },
        { api_code: 'd_both', label: '둘 다' },
      ],
    },
    { api_code: 'field_11', label: 'Google Play 계정 캡처', type: 'attachment' },
    {
      api_code: 'field_12', label: '개인정보 수집 동의', type: 'checkbox',
      choices: [{ api_code: 'a_ok', label: '동의합니다' }],
    },
    { api_code: 'field_13', label: '추가 메시지', type: 'paragraph_text' },
  ],
};
const SUMMARY = H.summarizeFormFields(FORM);
const CONFIG = H.validateConfig(H.suggestConfig(SUMMARY), SUMMARY);

const BNO = '2222222222';
const HOST_EMAIL = 'Host.Owner@Example.com';
const HOST_PHONE = '010-1234-5678';
const REP_NAME = '김영희';

const entryOf = (serial, o = {}) => ({
  serial_number: serial,
  token: `tok${serial}`,
  created_at: '2026-09-13T12:10:00Z',
  updated_at: '2026-09-13T12:10:00Z',
  field_1: '파티츄 라운지',
  field_2: '222-22-22222',
  field_3: '홍길동',
  field_4: HOST_EMAIL,
  field_5: HOST_PHONE,
  field_6: '아니오',
  field_7: REP_NAME,
  field_8: '010-9999-0000',
  field_9: 'rep@example.com',
  field_10: ['갤럭시(Android)'],
  field_11: [{ id: 'f1', name: 'play.png', url: 'https://files.formhug.ai/signed/play.png', file_size: 1024, content_type: 'image/png' }],
  field_12: ['동의합니다'],
  field_13: '잘 부탁드립니다',
  info_remote_ip: '203.0.113.42',
  info_user_agent: 'Mozilla/5.0',
  ...o,
});

/// 웹훅 안내 문서 예시 모양 — 바깥 data 봉투가 한 겹 더 있다(호환 유지).
const webhookBody = (serial, o = {}, eventType = 'entry_created') => ({
  data: {
    event_type: eventType,
    data: { form: H.FORMHUG_FORM_TOKEN, form_name: FORM.name, entry: entryOf(serial, o) },
  },
});

/// FormHug가 **실제로** 보내는 모양(샘플 payload API 문서·운영 수신 로그).
const actualBody = (serial, o = {}, eventType = 'entry_created') => ({
  event_type: eventType,
  data: { form: H.FORMHUG_FORM_TOKEN, form_name: FORM.name, entry: entryOf(serial, o) },
});

const pendingHost = (o = {}) => ({
  identityVerified: true,
  nickname: '길동호스트',
  email: HOST_EMAIL,
  emailLower: HOST_EMAIL.toLowerCase(),
  identityCiHash: 'CI_HASH_HOST',
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
    ...o,
  },
});

const PRE_ID = H.docIdFor(H.FORMHUG_FORM_TOKEN, 7);
const preDoc = (o = {}) => ({
  source: 'formhug',
  formToken: H.FORMHUG_FORM_TOKEN,
  serialNumber: 7,
  status: H.STATUS.preregistered,
  importState: 'ok',
  storeName: '파티츄 라운지',
  businessRegistrationNumber: BNO,
  hostName: '홍길동',
  hostEmail: HOST_EMAIL,
  hostEmailLower: HOST_EMAIL.toLowerCase(),
  hostPhone: '01012345678',
  sameAsRepresentative: false,
  representativeName: REP_NAME,
  hostUid: 'host1',
  delegationId: null,
  memo: '',
  ...o,
});

const baseSeed = (o = {}) => ({
  'users/admin1': { role: 'admin', nickname: '관리자' },
  'users/guest1': { role: '', nickname: '일반' },
  'users/host1': pendingHost(),
  [`${H.COLLECTION}/${PRE_ID}`]: preDoc(),
  ...o,
});

// ══════════════════════════════════════════════════════════════════════════
// 1. 웹훅 본문·키
// ══════════════════════════════════════════════════════════════════════════
test('문서에 적힌 웹훅 모양만 받는다', () => {
  const ok = H.parseWebhookBody(webhookBody(42));
  assert.strictEqual(ok.ok, true);
  assert.strictEqual(ok.eventType, 'entry_created');
  assert.strictEqual(ok.formToken, H.FORMHUG_FORM_TOKEN);
  assert.strictEqual(ok.serialNumber, 42);
  assert.strictEqual(H.parseWebhookBody(JSON.stringify(webhookBody(3))).serialNumber, 3);

  assert.strictEqual(H.parseWebhookBody(null).ok, false);
  assert.strictEqual(H.parseWebhookBody('not json').ok, false);
  assert.strictEqual(H.parseWebhookBody({ entry: { serial_number: 1 } }).ok, false);
  assert.strictEqual(H.parseWebhookBody({ data: { data: { entry: {} } } }).reason, 'noSerial');
  assert.strictEqual(H.parseWebhookBody({ data: { data: { entry: { serial_number: -1 } } } }).ok, false);
});

test('실제 FormHug 본문 {event_type, data:{form, entry}}도 받고, 두 모양의 결과가 같다', () => {
  const real = H.parseWebhookBody(actualBody(42));
  assert.strictEqual(real.ok, true, `실제 모양이 거부됐다: ${real.reason}`);
  assert.strictEqual(real.eventType, 'entry_created');
  assert.strictEqual(real.formToken, H.FORMHUG_FORM_TOKEN);
  assert.strictEqual(real.serialNumber, 42);
  assert.strictEqual(real.entry.field_1, '파티츄 라운지');
  assert.strictEqual(H.parseWebhookBody(JSON.stringify(actualBody(7, {}, 'entry_updated'))).eventType, 'entry_updated');
  assert.strictEqual(H.parseWebhookBody(Buffer.from(JSON.stringify(actualBody(8)))).serialNumber, 8);

  const doc = H.parseWebhookBody(webhookBody(42));
  for (const k of ['ok', 'eventType', 'formToken', 'serialNumber']) {
    assert.strictEqual(real[k], doc[k], `두 모양의 ${k}가 다르다`);
  }
  assert.deepStrictEqual(real.entry, doc.entry);

  // 운영 400의 재현: 실제 모양을 옛 파서 기준으로 보면 noData였다 — 이제는 통과한다.
  assert.strictEqual(H.parseWebhookBody({ event_type: 'entry_created', data: { form: 'x' } }).reason, 'noData');
  assert.strictEqual(H.parseWebhookBody({ event_type: 'entry_created', data: { form: 'x', entry: null } }).reason, 'noEntry');
  assert.strictEqual(H.parseWebhookBody({ event_type: 'entry_created', data: { form: 'x', entry: {} } }).reason, 'noSerial');
  assert.strictEqual(H.parseWebhookBody({ event_type: 'entry_created', data: 'str' }).reason, 'noEnvelope');
});

test('실제 모양으로 만든 신청을 문서 모양 재전송이 중복 생성하지 않는다(필드 매핑 동일)', async () => {
  const db = makeDb(configSeed());
  const formhug = { fetchEntry: async (t, s) => entryOf(s) };
  const first = await H.receiveEntry(db, { ...H.parseWebhookBody(actualBody(31)), formhug });
  assert.strictEqual(first.code, 'created');
  const again = await H.receiveEntry(db, { ...H.parseWebhookBody(webhookBody(31)), formhug });
  assert.strictEqual(again.code, 'duplicate');
  const docs = rowsUnder(db, H.COLLECTION);
  assert.strictEqual(docs.length, 1);
  assert.strictEqual(docs[0].storeName, '파티츄 라운지');
  assert.strictEqual(docs[0].businessRegistrationNumber, BNO);
  assert.strictEqual(docs[0].deviceType, 'android');
  assert.strictEqual(docs[0].sameAsRepresentative, false);
});

test('웹훅 키: 틀리거나 비어 있으면 거부, 시크릿이 비면 전부 거부', () => {
  assert.strictEqual(H.keyMatches('abc', 'abc'), true);
  assert.strictEqual(H.keyMatches('abd', 'abc'), false);
  assert.strictEqual(H.keyMatches('', 'abc'), false);
  assert.strictEqual(H.keyMatches(undefined, 'abc'), false);
  assert.strictEqual(H.keyMatches('', ''), false);
});

// ══════════════════════════════════════════════════════════════════════════
// 2. 매핑
// ══════════════════════════════════════════════════════════════════════════
test('라벨 제안은 가짜 폼의 모든 항목을 올바른 필드에 붙인다', () => {
  const s = H.suggestConfig(SUMMARY);
  assert.deepStrictEqual(s.fields, {
    businessRegistrationNumber: 'field_2',
    sameAsRepresentative: 'field_6',
    representativeEmail: 'field_9',
    representativePhone: 'field_8',
    representativeName: 'field_7',
    hostEmail: 'field_4',
    hostPhone: 'field_5',
    hostName: 'field_3',
    storeName: 'field_1',
    deviceType: 'field_10',
    googlePlayScreenshot: 'field_11',
    privacyConsent: 'field_12',
    additionalMessage: 'field_13',
  });
  assert.deepStrictEqual(s.choices.sameAsRepresentative, { c_yes: true, c_no: false });
  assert.deepStrictEqual(s.choices.deviceType, { d_and: 'android', d_ios: 'ios', d_both: 'both' });
});

test('매핑 저장 검증: 필수 누락·폼에 없는 필드·예/아니오 미지정은 거부', () => {
  assert.throws(() => H.validateConfig({ fields: { storeName: 'field_1' } }, SUMMARY), expectCode('invalid-argument'));
  const s = H.suggestConfig(SUMMARY);
  assert.throws(() => H.validateConfig({ ...s, fields: { ...s.fields, storeName: 'field_99' } }, SUMMARY),
    expectCode('invalid-argument'));
  assert.throws(() => H.validateConfig({ ...s, fields: { ...s.fields, hostName: 'field_1' } }, SUMMARY),
    expectCode('invalid-argument'));
  assert.throws(() => H.validateConfig({ ...s, choices: { ...s.choices, sameAsRepresentative: { c_yes: true } } }, SUMMARY),
    expectCode('invalid-argument'));
  assert.throws(() => H.validateConfig({ ...s, fields: { ...s.fields, bogus: 'field_1' } }, SUMMARY),
    expectCode('invalid-argument'));
  assert.deepStrictEqual(CONFIG.choiceLabels.deviceType, { d_and: '갤럭시(Android)', d_ios: '아이폰(iOS)', d_both: '둘 다' });
});

test('항목 → 신청서: 정규화·선택지(라벨/코드)·첨부·메타 미저장', () => {
  const { record, missingRequired } = H.mapEntry(entryOf(1), CONFIG);
  assert.strictEqual(record.storeName, '파티츄 라운지');
  assert.strictEqual(record.businessRegistrationNumber, BNO);
  assert.strictEqual(record.businessNumberValid, true);
  assert.strictEqual(record.hostEmailLower, HOST_EMAIL.toLowerCase());
  assert.strictEqual(record.hostPhone, '01012345678');
  assert.strictEqual(record.sameAsRepresentative, false);
  assert.strictEqual(record.deviceType, 'android');
  assert.deepStrictEqual(record.googlePlayScreenshot, { name: 'play.png', contentType: 'image/png', fileSize: 1024, count: 1 });
  assert.strictEqual(record.googlePlayScreenshotUrl, 'https://files.formhug.ai/signed/play.png');
  assert.strictEqual(record.privacyConsent, true);
  assert.deepStrictEqual(missingRequired, []);
  // 메타(IP·UA)는 담기지 않는다.
  assert.ok(!JSON.stringify(record).includes('203.0.113.42'));
  assert.ok(!JSON.stringify(record).includes('Mozilla'));

  const both = H.mapEntry(entryOf(2, { field_10: ['갤럭시(Android)', '아이폰(iOS)'], field_6: 'c_yes' }), CONFIG).record;
  assert.strictEqual(both.deviceType, 'both');
  assert.strictEqual(both.sameAsRepresentative, true);
  assert.strictEqual(H.mapEntry(entryOf(3, { field_10: 'd_ios' }), CONFIG).record.deviceType, 'ios');
  assert.strictEqual(H.mapEntry(entryOf(4, { field_10: [{ label: '둘 다' }] }), CONFIG).record.deviceType, 'both');
  assert.strictEqual(H.mapEntry(entryOf(5, { field_10: '갤럭시(Android), 아이폰(iOS)' }), CONFIG).record.deviceType, 'both');

  const insecure = H.mapEntry(entryOf(6, { field_11: [{ url: 'http://evil/x.png' }] }), CONFIG).record;
  assert.strictEqual(insecure.googlePlayScreenshotUrl, null);

  const missing = H.mapEntry(entryOf(7, { field_1: '', field_6: '모르겠음' }), CONFIG);
  assert.deepStrictEqual(missing.missingRequired.sort(), ['sameAsRepresentative', 'storeName']);

  // 매핑이 없으면 아무 값도 읽지 않는다.
  const none = H.mapEntry(entryOf(8), { fields: {} }).record;
  assert.strictEqual(none.storeName, '');
  assert.strictEqual(none.hostEmail, '');
});

// ══════════════════════════════════════════════════════════════════════════
// 3. 수신·중복 방지
// ══════════════════════════════════════════════════════════════════════════
const configSeed = () => ({ [`${H.CONFIG_COLLECTION}/${H.CONFIG_DOC}`]: { formToken: H.FORMHUG_FORM_TOKEN, ...CONFIG } });

test('재전송이 와도 문서·접수 이력은 하나다', async () => {
  const db = makeDb(configSeed());
  const parsed = H.parseWebhookBody(webhookBody(11));
  const apiCalls = [];
  const formhug = { fetchEntry: async (t, s) => { apiCalls.push(s); return entryOf(s); } };

  const first = await H.receiveEntry(db, { ...parsed, formhug });
  assert.strictEqual(first.code, 'created');
  const second = await H.receiveEntry(db, { ...parsed, formhug });
  assert.strictEqual(second.code, 'duplicate');
  const third = await H.receiveEntry(db, { ...parsed, formhug });
  assert.strictEqual(third.code, 'duplicate');

  const docs = rowsUnder(db, H.COLLECTION);
  assert.strictEqual(docs.length, 1);
  assert.strictEqual(docs[0].id, H.docIdFor(H.FORMHUG_FORM_TOKEN, 11));
  assert.strictEqual(docs[0].status, 'new');
  assert.strictEqual(docs[0].importState, 'ok');
  assert.strictEqual(docs[0].importSource, 'api');
  assert.strictEqual(docs[0].formEntryId, 'tok11');
  assert.strictEqual(docs[0].submittedAt.toMillis(), Date.parse('2026-09-13T12:10:00Z'));
  assert.strictEqual(rowsUnder(db, `${H.COLLECTION}/${docs[0].id}/${H.HISTORY}`).length, 1);
  assert.deepStrictEqual(apiCalls, [11]); // 중복 수신은 API도 다시 부르지 않는다
});

test('매핑이 없으면 일련번호만 남고, 매핑 후 같은 재전송이 가져오기를 다시 시도한다', async () => {
  const db = makeDb();
  const parsed = H.parseWebhookBody(webhookBody(12));
  const r = await H.receiveEntry(db, { ...parsed, formhug: null });
  assert.strictEqual(r.importState, 'needsFieldMap');
  const doc = rowsUnder(db, H.COLLECTION)[0];
  assert.strictEqual(doc.storeName, '');
  assert.strictEqual(doc.hostEmail, '');
  assert.strictEqual(doc.serialNumber, 12);

  await db.collection(H.CONFIG_COLLECTION).doc(H.CONFIG_DOC).set({ formToken: H.FORMHUG_FORM_TOKEN, ...CONFIG });
  const again = await H.receiveEntry(db, { ...parsed, formhug: null });
  assert.strictEqual(again.importState, 'ok');
  const after = rowsUnder(db, H.COLLECTION)[0];
  assert.strictEqual(after.storeName, '파티츄 라운지');
  assert.strictEqual(after.importSource, 'webhookPayload');
  assert.strictEqual(rowsUnder(db, `${H.COLLECTION}/${after.id}/${H.HISTORY}`).length, 1);
});

test('entry_updated는 신청서 필드만 갱신하고 관리 필드는 건드리지 않는다', async () => {
  const db = makeDb(configSeed());
  const formhug = { fetchEntry: async (t, s) => entryOf(s) };
  await H.receiveEntry(db, { ...H.parseWebhookBody(webhookBody(13)), formhug });
  const id = H.docIdFor(H.FORMHUG_FORM_TOKEN, 13);
  await db.collection(H.COLLECTION).doc(id).set({ status: 'preregistered', memo: '확인함', hostUid: 'host1' }, { merge: true });

  const changed = { fetchEntry: async (t, s) => entryOf(s, { field_1: '파티츄 라운지 2호점' }) };
  const r = await H.receiveEntry(db, { ...H.parseWebhookBody(webhookBody(13, {}, 'entry_updated')), formhug: changed });
  assert.strictEqual(r.code, 'updated');
  const doc = db.__store.get(`${H.COLLECTION}/${id}`);
  assert.strictEqual(doc.storeName, '파티츄 라운지 2호점');
  assert.strictEqual(doc.status, 'preregistered');
  assert.strictEqual(doc.memo, '확인함');
  assert.strictEqual(doc.hostUid, 'host1');
  const hist = rowsUnder(db, `${H.COLLECTION}/${id}/${H.HISTORY}`).map((h) => h.type);
  assert.deepStrictEqual(hist, ['received', 'form_updated']);
});

test('API 재조회 실패 시 웹훅 항목으로 대신 채운다', async () => {
  const db = makeDb(configSeed());
  const failing = { fetchEntry: async () => { const e = new Error('x'); e.httpStatus = 502; throw e; } };
  const r = await H.receiveEntry(db, { ...H.parseWebhookBody(webhookBody(14)), formhug: failing });
  assert.strictEqual(r.httpStatus, 200);
  const doc = rowsUnder(db, H.COLLECTION)[0];
  assert.strictEqual(doc.importSource, 'webhookPayload');
  assert.strictEqual(doc.hostPhone, '01012345678');
});

test('웹훅 핸들러: 키·형식·다른 폼·중복을 가르고 로그에 개인정보가 없다', async () => {
  const db = makeDb(configSeed());
  currentDb = db;
  const call = async (req) => {
    const res = {
      statusCode: 200, body: null,
      status(c) { this.statusCode = c; return this; },
      send(b) { this.body = b; return this; },
      json(b) { this.body = b; return this; },
      set() { return this; },
      setHeader() { return this; },
      getHeader() { return undefined; },
    };
    await HP.hostPreRegistrationWebhook({
      method: 'POST', headers: {}, header: () => undefined, get: () => undefined, ...req,
    }, res);
    return res;
  };
  let logs;
  try {
    logs = await captureLogs(async () => {
      assert.strictEqual((await call({ query: { key: 'wrong' }, body: webhookBody(21) })).statusCode, 401);
      assert.strictEqual((await call({ query: {}, body: webhookBody(21) })).statusCode, 401);
      assert.strictEqual(rowsUnder(db, H.COLLECTION).length, 0, '키가 틀리면 아무것도 쓰지 않는다');

      const key = process.env.FORMHUG_WEBHOOK_KEY;
      assert.strictEqual((await call({ query: { key }, body: { foo: 1 } })).statusCode, 400);
      assert.strictEqual((await call({ method: 'GET', query: { key }, body: webhookBody(21) })).statusCode, 405);
      const other = webhookBody(21);
      other.data.data.form = 'OtherForm';
      assert.strictEqual((await call({ query: { key }, body: other })).body.result, 'ignoredForm');
      const otherReal = actualBody(21);
      otherReal.data.form = 'OtherForm';
      assert.strictEqual((await call({ query: { key }, body: otherReal })).body.result, 'ignoredForm');
      assert.strictEqual(rowsUnder(db, H.COLLECTION).length, 0);

      // 실제 FormHug 모양으로 생성 → 문서 모양 재전송은 중복.
      const created = await call({ query: { key }, body: actualBody(21) });
      assert.strictEqual(created.statusCode, 200, '실제 모양은 400이면 안 된다');
      assert.strictEqual(created.body.result, 'created');
      assert.strictEqual((await call({ query: { key }, body: webhookBody(21) })).body.result, 'duplicate');
      assert.strictEqual(rowsUnder(db, H.COLLECTION).length, 1);
    });
  } finally {
    currentDb = null;
  }
  for (const secret of [HOST_EMAIL, HOST_EMAIL.toLowerCase(), '01012345678', HOST_PHONE, '홍길동', REP_NAME, '203.0.113.42']) {
    assert.ok(!logs.includes(secret), `로그에 개인정보가 섞였다: ${secret}`);
  }
});

// ══════════════════════════════════════════════════════════════════════════
// 4. 관리자 권한
// ══════════════════════════════════════════════════════════════════════════
test('관리자 판정은 users.role == admin 하나뿐이다', async () => {
  const db = makeDb(baseSeed());
  await assert.rejects(H.assertAdmin(db, null), expectCode('unauthenticated'));
  await assert.rejects(H.assertAdmin(db, { uid: 'guest1' }), expectCode('permission-denied'));
  await assert.rejects(H.assertAdmin(db, { uid: 'nobody' }), expectCode('permission-denied'));
  await assert.rejects(H.assertAdmin(db, { uid: 'host1', token: { admin: true, role: 'admin' } }),
    expectCode('permission-denied'));
  assert.strictEqual(await H.assertAdmin(db, { uid: 'admin1' }), 'admin1');
});

test('관리자 콜러블은 관리자 아닌 계정을 막는다(실제 export 경유)', async () => {
  const db = makeDb(baseSeed());
  currentDb = db;
  const before = JSON.stringify([...db.__store.entries()]);
  try {
    const callables = [
      [HP.adminUpdateHostPreRegistration, { id: PRE_ID, action: 'markPreregistered' }],
      [HP.adminCreateBusinessDelegationForPreregistration, { id: PRE_ID }],
      [HP.adminGetHostPreRegistration, { id: PRE_ID }],
      [HP.adminHostPreRegistrationFormSetup, { action: 'getFields' }],
    ];
    for (const [fn, data] of callables) {
      await assert.rejects(fn.run({ auth: { uid: 'guest1' }, data }), expectCode('permission-denied'));
      await assert.rejects(fn.run({ auth: null, data }), expectCode('unauthenticated'));
    }
  } finally {
    currentDb = null;
  }
  assert.strictEqual(JSON.stringify([...db.__store.entries()]), before, '거부된 호출은 아무것도 쓰지 않는다');
});

// ══════════════════════════════════════════════════════════════════════════
// 5. 관리자 처리
// ══════════════════════════════════════════════════════════════════════════
test('사전등록 완료: 상태·처리자·이력, 두 번은 안 된다', async () => {
  const db = makeDb(baseSeed({ [`${H.COLLECTION}/${PRE_ID}`]: preDoc({ status: 'reviewing', hostUid: null }) }));
  await H.updatePreRegistration(db, { id: PRE_ID, action: 'markPreregistered', actorUid: 'admin1' });
  const doc = db.__store.get(`${H.COLLECTION}/${PRE_ID}`);
  assert.strictEqual(doc.status, 'preregistered');
  assert.strictEqual(doc.processedBy, 'admin1');
  assert.ok(doc.processedAt && doc.processedAt.__ts);
  assert.ok(doc.updatedAt && doc.updatedAt.__ts);
  const hist = rowsUnder(db, `${H.COLLECTION}/${PRE_ID}/${H.HISTORY}`);
  assert.deepStrictEqual(hist.map((h) => [h.type, h.actorUid, h.actorType]), [['preregistered', 'admin1', 'admin']]);
  await assert.rejects(
    H.updatePreRegistration(db, { id: PRE_ID, action: 'markPreregistered', actorUid: 'admin1' }),
    expectCode('failed-precondition'),
  );
});

test('계정 연결: 이메일 일치만 바로, 불일치는 사유 필요, 인증 필드는 그대로', async () => {
  const seed = baseSeed({
    [`${H.COLLECTION}/${PRE_ID}`]: preDoc({ hostUid: null }),
    'users/other1': { nickname: '다른사람', email: 'other@example.com', emailLower: 'other@example.com', identityVerified: false },
  });
  const db = makeDb(seed);
  const hostBefore = JSON.stringify(db.__store.get('users/host1'));

  await assert.rejects(
    H.updatePreRegistration(db, { id: PRE_ID, action: 'linkHost', uid: 'other1', actorUid: 'admin1' }),
    expectCode('failed-precondition'),
  );
  await H.updatePreRegistration(db, { id: PRE_ID, action: 'linkHost', uid: 'host1', actorUid: 'admin1' });
  const doc = db.__store.get(`${H.COLLECTION}/${PRE_ID}`);
  assert.strictEqual(doc.hostUid, 'host1');
  assert.strictEqual(doc.hostLinkMethod, 'emailMatch');
  assert.strictEqual(JSON.stringify(db.__store.get('users/host1')), hostBefore, '호스트 문서는 한 글자도 바뀌지 않는다');
  const logs = rowsUnder(db, 'userActivityLogs');
  assert.ok(logs.some((l) => l.uid === 'host1' && l.activityType === 'admin_host_preregistration_linked' && l.actorType === 'admin'));

  // 해제 후 불일치 계정 — 사유가 있어야만.
  await H.updatePreRegistration(db, { id: PRE_ID, action: 'unlinkHost', actorUid: 'admin1' });
  await assert.rejects(
    H.updatePreRegistration(db, { id: PRE_ID, action: 'linkHost', uid: 'other1', allowEmailMismatch: true, reason: '', actorUid: 'admin1' }),
    expectCode('failed-precondition'),
  );
  await H.updatePreRegistration(db, {
    id: PRE_ID, action: 'linkHost', uid: 'other1', allowEmailMismatch: true, reason: '카카오 이메일로 가입 확인', actorUid: 'admin1',
  });
  assert.strictEqual(db.__store.get(`${H.COLLECTION}/${PRE_ID}`).hostLinkMethod, 'adminOverride');
});

test('한 계정은 반려되지 않은 신청 하나에만 연결된다', async () => {
  const OTHER = H.docIdFor(H.FORMHUG_FORM_TOKEN, 8);
  const db = makeDb(baseSeed({
    [`${H.COLLECTION}/${PRE_ID}`]: preDoc({ hostUid: 'host1' }),
    [`${H.COLLECTION}/${OTHER}`]: preDoc({ serialNumber: 8, hostUid: null }),
  }));
  await assert.rejects(
    H.updatePreRegistration(db, { id: OTHER, action: 'linkHost', uid: 'host1', actorUid: 'admin1' }),
    expectCode('failed-precondition'),
  );
});

test('반려는 사유가 필요하고, 링크 발송 처리는 유효한 링크가 있어야 한다', async () => {
  const db = makeDb(baseSeed());
  await assert.rejects(
    H.updatePreRegistration(db, { id: PRE_ID, action: 'markRepresentativeLinkSent', actorUid: 'admin1' }),
    expectCode('failed-precondition'),
  );
  await assert.rejects(
    H.updatePreRegistration(db, { id: PRE_ID, action: 'reject', reason: '  ', actorUid: 'admin1' }),
    expectCode('invalid-argument'),
  );
  await H.updatePreRegistration(db, { id: PRE_ID, action: 'reject', reason: '사업자 정보 불일치', actorUid: 'admin1' });
  assert.strictEqual(db.__store.get(`${H.COLLECTION}/${PRE_ID}`).status, 'rejected');
  await assert.rejects(
    H.updatePreRegistration(db, { id: PRE_ID, action: 'hack', actorUid: 'admin1' }),
    expectCode('invalid-argument'),
  );
});

test('이메일 후보는 가입 이메일·소셜 이메일로 찾되 후보만 돌려준다', async () => {
  const db = makeDb({
    'users/a': { email: HOST_EMAIL, emailLower: HOST_EMAIL.toLowerCase(), nickname: 'A', identityCiHash: 'SECRET_CI' },
    'users/b': { email: null, emailLower: '', socialAccount: { provider: 'naver', email: HOST_EMAIL.toLowerCase() }, nickname: 'B' },
    'users/c': { email: 'else@example.com', emailLower: 'else@example.com', nickname: 'C' },
  });
  const cands = await H.findHostCandidates(db, HOST_EMAIL.toLowerCase(), {
    getUserByEmail: async () => { const e = new Error('nf'); e.code = 'auth/user-not-found'; throw e; },
  });
  assert.deepStrictEqual(cands.map((c) => [c.uid, c.matchedBy]).sort(), [['a', ['accountEmail']], ['b', ['socialAccountEmail']]]);
  assert.ok(!JSON.stringify(cands).includes('SECRET_CI'));
});

// ══════════════════════════════════════════════════════════════════════════
// 6. 대표자 링크 — 기존 위임 로직 재사용
// ══════════════════════════════════════════════════════════════════════════
const tokenFromUrl = (url) => decodeURIComponent(new URL(url).searchParams.get('t'));

test('사전조건: 대표자 동일·계정 미연결·사업자 인증 전·번호 불일치는 링크를 만들지 않는다', async () => {
  const run = async (seedPatch, code) => {
    const db = makeDb(baseSeed(seedPatch));
    await assert.rejects(
      H.createDelegationForPreRegistration(db, { id: PRE_ID, actorUid: 'admin1', todayKey: '2026-09-13' }),
      expectCode(code),
    );
    assert.strictEqual(rowsUnder(db, D.DELEGATIONS).length, 0);
  };
  await run({ [`${H.COLLECTION}/${PRE_ID}`]: preDoc({ sameAsRepresentative: true }) }, 'failed-precondition');
  await run({ [`${H.COLLECTION}/${PRE_ID}`]: preDoc({ hostUid: null }) }, 'failed-precondition');
  await run({ [`${H.COLLECTION}/${PRE_ID}`]: preDoc({ representativeName: '' }) }, 'failed-precondition');
  await run({ [`${H.COLLECTION}/${PRE_ID}`]: preDoc({ status: 'rejected' }) }, 'failed-precondition');
  await run({ 'users/host1': { identityVerified: true, businessVerification: {} } }, 'failed-precondition');
  await run({ 'users/host1': pendingHost({ businessNumber: '3333333333' }) }, 'failed-precondition');
  await run({ 'users/host1': pendingHost({ authorization: 'self', authorizationReason: null }) }, 'failed-precondition');
  await assert.rejects(
    H.createDelegationForPreRegistration(makeDb(baseSeed()), { id: 'nope', actorUid: 'admin1' }),
    expectCode('not-found'),
  );
});

test('링크 생성: 기존 위임 문서 모양 그대로, 토큰은 해시만, 신청서·이력에 원문 없음', async () => {
  const db = makeDb(baseSeed());
  const out = await H.createDelegationForPreRegistration(db, { id: PRE_ID, actorUid: 'admin1', todayKey: '2026-09-13' });

  assert.ok(out.approvalUrl.startsWith('https://partychu-30c24.web.app/biz-approval?t='));
  const token = tokenFromUrl(out.approvalUrl);
  const delegations = rowsUnder(db, D.DELEGATIONS);
  assert.strictEqual(delegations.length, 1);
  const d = delegations[0];
  assert.strictEqual(d.id, out.delegationId);
  assert.strictEqual(d.granteeUid, 'host1');
  assert.strictEqual(d.status, 'requested');
  assert.strictEqual(d.requestTokenHash, D.hashToken(token));
  assert.strictEqual(d.businessNumberHash, businessNumberHash(BNO));
  assert.strictEqual(d.expiresAt.toMillis() - Date.now() <= D.REQUEST_TTL_MS, true);
  assert.ok(d.expiresAt.toMillis() - Date.now() > D.REQUEST_TTL_MS - 60 * 1000, '72시간 만료가 그대로다');

  const pre = db.__store.get(`${H.COLLECTION}/${PRE_ID}`);
  assert.strictEqual(pre.delegationId, out.delegationId);
  assert.strictEqual(pre.status, 'representativeVerificationRequired');

  const everythingButDelegations = JSON.stringify([...db.__store.entries()].filter(([k]) => !k.startsWith(D.DELEGATIONS)));
  assert.ok(!everythingButDelegations.includes(token), '토큰 원문이 어디에도 저장되지 않는다');
  assert.ok(!JSON.stringify(d).includes(token));
  assert.strictEqual(db.__store.get('users/host1').businessVerification.delegationRequest.count, 1);
  const hist = rowsUnder(db, `${H.COLLECTION}/${PRE_ID}/${H.HISTORY}`);
  assert.deepStrictEqual(hist.map((h) => h.type), ['representative_link_created']);
  assert.strictEqual(db.__store.get('users/host1').businessVerification.authorization, 'pendingOwnerApproval',
    '링크 생성은 권한을 열지 않는다');
});

test('대기중 링크가 있으면 중복 생성 금지, 재발급은 이전 링크를 죽이고 하루 3회 한도를 그대로 쓴다', async () => {
  const db = makeDb(baseSeed());
  const args = { id: PRE_ID, actorUid: 'admin1', todayKey: '2026-09-13' };
  const first = await H.createDelegationForPreRegistration(db, args);
  await assert.rejects(H.createDelegationForPreRegistration(db, args), expectCode('already-exists'));

  const second = await H.createDelegationForPreRegistration(db, { ...args, reissue: true });
  assert.notStrictEqual(second.delegationId, first.delegationId);
  const old = db.__store.get(`${D.DELEGATIONS}/${first.delegationId}`);
  assert.strictEqual(old.status, 'expired');
  assert.strictEqual(old.expiredReason, 'superseded');
  assert.strictEqual(db.__store.get(`${H.COLLECTION}/${PRE_ID}`).delegationId, second.delegationId);

  await H.createDelegationForPreRegistration(db, { ...args, reissue: true });
  await assert.rejects(H.createDelegationForPreRegistration(db, { ...args, reissue: true }), expectCode('resource-exhausted'));
  assert.strictEqual(db.__store.get('users/host1').businessVerification.delegationRequest.count, D.MAX_REQUESTS_PER_DAY);

  // 옛 토큰은 승인 페이지 조회에서 더는 requested가 아니다(1회용 규칙 그대로).
  const oldToken = tokenFromUrl(first.approvalUrl);
  const found = rowsUnder(db, D.DELEGATIONS).find((r) => r.requestTokenHash === D.hashToken(oldToken));
  assert.strictEqual(found.status, 'expired');
});

test('이미 승인된 위임이 있으면 만들지 않는다', async () => {
  const db = makeDb(baseSeed({
    [`${D.DELEGATIONS}/dApproved`]: {
      granteeUid: 'host1', businessNumberHash: businessNumberHash(BNO), status: 'approved',
      requestedAt: Timestamp.fromMillis(CLOCK - 1000), expiresAt: Timestamp.fromMillis(CLOCK - 500),
    },
  }));
  await assert.rejects(
    H.createDelegationForPreRegistration(db, { id: PRE_ID, actorUid: 'admin1', reissue: true, todayKey: '2026-09-13' }),
    expectCode('already-exists'),
  );
});

// ══════════════════════════════════════════════════════════════════════════
// 7. 상태 동기화
// ══════════════════════════════════════════════════════════════════════════
test('링크 표시 상태: 미생성·대기중·만료(시각 경과)·승인·취소', () => {
  const now = CLOCK;
  assert.strictEqual(H.linkStatusOf(null, now), 'none');
  assert.strictEqual(H.linkStatusOf({ status: 'requested', expiresAt: Timestamp.fromMillis(now + 1) }, now), 'requested');
  assert.strictEqual(H.linkStatusOf({ status: 'requested', expiresAt: Timestamp.fromMillis(now) }, now), 'expired');
  assert.strictEqual(H.linkStatusOf({ status: 'expired' }, now), 'expired');
  assert.strictEqual(H.linkStatusOf({ status: 'approved' }, now), 'approved');
  assert.strictEqual(H.linkStatusOf({ status: 'rejected' }, now), 'rejected');
  assert.strictEqual(H.linkStatusOf({ status: 'revoked' }, now), 'revoked');
});

test('동기화 판정: 같은 사업자의 권한만 반영하고 반려 건은 건드리지 않는다', () => {
  const pre = preDoc({ status: 'preregistered' });
  const now = CLOCK;
  const plan = (o) => H.planSync({ pre, nowMs: now, ...o });

  // 대표자 확인 필요로 앞당김
  assert.strictEqual(plan({ hostBv: pendingHost().businessVerification }).patch.status, 'representativeVerificationRequired');
  // 본인 명의 인증 완료
  const self = plan({ hostBv: { ...pendingHost().businessVerification, authorization: 'self' } });
  assert.strictEqual(self.patch.status, 'verified');
  assert.strictEqual(self.events[0].type, 'host_business_verified');
  // 위임 승인 완료
  const deleg = plan({ hostBv: { ...pendingHost().businessVerification, authorization: 'delegated', delegationId: 'd9' } });
  assert.strictEqual(deleg.patch.status, 'verified');
  assert.strictEqual(deleg.patch.delegationId, 'd9');
  assert.strictEqual(deleg.events[0].type, 'representative_approved');
  // delegationId 없는 delegated는 권한이 아니다
  assert.notStrictEqual(plan({ hostBv: { ...pendingHost().businessVerification, authorization: 'delegated', delegationId: '' } }).patch.status, 'verified');
  // 다른 사업자로 열린 권한은 반영하지 않는다
  assert.deepStrictEqual(plan({ hostBv: { ...pendingHost().businessVerification, businessNumber: '3333333333', authorization: 'self' } }).patch, {});
  // 반려·미연결은 무시
  assert.deepStrictEqual(H.planSync({ pre: { ...pre, status: 'rejected' }, hostBv: { ...pendingHost().businessVerification, authorization: 'self' }, nowMs: now }).patch, {});
  assert.deepStrictEqual(H.planSync({ pre: { ...pre, hostUid: null }, hostBv: { authorization: 'self' }, nowMs: now }).patch, {});
  // 권한이 풀리면 되돌린다
  const lost = H.planSync({ pre: { ...pre, status: 'verified' }, hostBv: { ...pendingHost().businessVerification, authorizationReason: 'delegationRevoked' }, nowMs: now });
  assert.strictEqual(lost.patch.status, 'representativeVerificationRequired');
  // 발송한 링크가 만료되면 재발급 필요로
  const expired = H.planSync({
    pre: { ...pre, status: 'representativeLinkSent', delegationId: 'd1' },
    hostBv: { status: 'verified', authorization: 'pendingOwnerApproval', businessNumber: '4444444444' },
    currentDelegation: { id: 'd1', status: 'requested', expiresAt: Timestamp.fromMillis(now - 1) },
    nowMs: now,
  });
  assert.strictEqual(expired.patch.status, 'representativeVerificationRequired');
  // 앞으로만 — 이미 발송 처리된 건을 대기 상태로 끌어내리지 않는다
  assert.deepStrictEqual(H.planSync({
    pre: { ...pre, status: 'representativeLinkSent', delegationId: 'd1' },
    hostBv: pendingHost().businessVerification,
    currentDelegation: { id: 'd1', status: 'requested', expiresAt: Timestamp.fromMillis(now + 1000) },
    nowMs: now,
  }).patch, {});
});

test('위임 승인 → applySync가 verified와 이력·활동 로그를 남긴다(호스트 앱 링크도 연결)', async () => {
  const db = makeDb(baseSeed());
  // 호스트가 앱에서 직접 만든 링크.
  const req = await D.createDelegationRequest(db, 'host1', { now: FieldValue.serverTimestamp(), todayKey: '2026-09-13' });
  let r = await H.applySync(db, PRE_ID);
  assert.strictEqual(r.pre.delegationId, req.delegationId);
  assert.strictEqual(r.pre.status, 'representativeVerificationRequired');

  // 대표자 승인이 끝난 상태를 흉내 낸다(승인 자체는 businessDelegation.selfcheck가 검증).
  await db.collection('users').doc('host1').set({
    businessVerification: { authorization: 'delegated', authorizationReason: null, delegationId: req.delegationId },
  }, { merge: true });
  await db.collection(D.DELEGATIONS).doc(req.delegationId).set({ status: 'approved' }, { merge: true });
  r = await H.applySync(db, PRE_ID);
  assert.strictEqual(r.pre.status, 'verified');
  const types = rowsUnder(db, `${H.COLLECTION}/${PRE_ID}/${H.HISTORY}`).map((h) => h.type);
  assert.deepStrictEqual(types, ['representative_link_detected', 'representative_verification_required', 'representative_approved']);
  assert.ok(rowsUnder(db, 'userActivityLogs').some((l) => l.activityType === 'host_preregistration_verified'));

  // 두 번째 동기화는 아무것도 쓰지 않는다.
  const count = db.__store.size;
  await H.applySync(db, PRE_ID);
  assert.strictEqual(db.__store.size, count);
});

// ══════════════════════════════════════════════════════════════════════════
// 8. 정적 검사 — 기존 흐름과 규칙
// ══════════════════════════════════════════════════════════════════════════
test('승인 페이지 세션 쿠키는 Hosting이 통과시키는 __session이다', () => {
  assert.strictEqual(D.SESSION_COOKIE, '__session');
  assert.strictEqual(D.approvalUrlOf('a b'), 'https://partychu-30c24.web.app/biz-approval?t=a%20b');
});

// firestore.release.rules(08-24 낡은 스냅샷)는 이번 배포에 쓰지 않으므로 검사하지 않는다.
// 운영 배포는 "운영 규칙 원문 + 이 블록"으로 만든 후보 파일로만 한다.
test('규칙: 사전등록 컬렉션은 관리자 읽기만, 클라이언트 쓰기 전면 차단', () => {
  for (const file of ['firestore.rules']) {
    const src = fs.readFileSync(path.join(__dirname, '..', file), 'utf8').replace(/\r/g, '');
    const block = (name) => {
      const i = src.indexOf(`match /${name}/`);
      assert.ok(i >= 0, `${file}: ${name} 블록이 없다`);
      return src.slice(i, src.indexOf('\n    }', i));
    };
    const pre = block('hostPreRegistrations');
    assert.ok(/allow read: if isAdmin\(\);/.test(pre), `${file}: 관리자 읽기`);
    assert.ok(/allow write: if false;/.test(pre), `${file}: 쓰기 차단`);
    assert.ok(/match \/history\/\{historyId\} \{\s*allow read: if isAdmin\(\);\s*allow write: if false;/.test(pre), `${file}: 이력`);
    assert.ok(!/allow (create|update|delete)/.test(pre), `${file}: 부분 쓰기 허용이 없어야 한다`);
    const cfg = block('hostPreRegistrationConfig');
    assert.ok(/allow read: if isAdmin\(\);\s*allow write: if false;/.test(cfg), `${file}: 설정`);
  }
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
      console.log(`  ✗ ${name}\n    ${e && e.stack ? e.stack.split('\n').slice(0, 4).join('\n    ') : e}`);
    }
  }
  console.log(`\n${cases.length - failed}/${cases.length} 통과`);
  process.exit(failed ? 1 : 0);
})();

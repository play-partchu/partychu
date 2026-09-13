// 심사·데모용 콘텐츠 일괄 변경 — **1회성 개발자 스크립트**.
//
// 배포되는 Cloud Function이 아니고, 앱에서 부를 수 있는 진입점도 없다.
// 로컬에서 `node scripts/demoContentRewrite.js` 로만 실행한다
// (createTestAccounts.js / backfillUserFields.js 와 같은 패턴).
//
// ── 무엇을 하나 ───────────────────────────────────────────────────────────
// 지정한 **한 사람의 uid가 hostId인 문서만** 골라, 표시 콘텐츠(이름·소개문구·
// 위치·이미지)를 파티츄 브랜드 기반의 가상 데모 콘텐츠로 바꾼다.
//
//   파티        parties
//   플레이스     events          ← ⚠️ 컬렉션 이름이 UI 이름과 뒤집혀 있다
//   장소대여     places          ← ⚠️
//   이벤트      placePromotions
//   부속        placeRooms · placeMenus · placeProducts
//
// ── 무엇을 하지 않나 ──────────────────────────────────────────────────────
//   · 문서를 **삭제하지 않는다.** PATCH(=update)만 쓴다. 문서를 새로 만들지도
//     않는다(PATCH에 `currentDocument.exists=true`를 걸어, 없는 문서에
//     실수로 쓰는 경로를 서버가 거부하게 한다).
//   · 다른 사람의 문서를 건드리지 않는다(모든 쿼리가 hostId == UID이고,
//     쓰기 직전에 문서를 다시 읽어 hostId를 재확인한다).
//   · firestore.rules · Firebase 인증 · 앱 로직을 바꾸지 않는다.
//     (REST는 Admin 권한으로 나가므로 규칙을 열 이유 자체가 없다.)
//   · 관계·운영 핵심 필드를 바꾸지 않는다 — hostId · createdAt · placeId ·
//     placeCollection · seriesId · 가격 · 정원 · 일정 · 상태값
//     ([FROZEN_FIELDS]가 물리적으로 막는다).
//   · 신청·예약·결제·채팅·후기(applications / reservations / packageBookings /
//     chatRooms / partyReviews …)를 건드리지 않는다. 거기 남은 옛 제목
//     스냅샷은 **과거 거래 기록**이므로 위조하지 않는다.
//   · 사업자 인증 원문(businessVerifications / businessOwnership)을 건드리지
//     않는다. 국세청 실제 판정이라 위조하지 않는다.
//   · 동영상을 새로 올리지 않는다. 1차 범위에서 동영상은 제외이고, 실제 업체
//     영상이 남지 않도록 videoUrl 계열 필드를 **제거해 사진 커버로 내린다**
//     (--keep-video 로 끌 수 있다).
//
// ── 실행 순서 ─────────────────────────────────────────────────────────────
//   0) node scripts/demoContentRewrite.js --whoami --email you@example.com
//        → uid 확인 + 도메인별 건수. 아무것도 쓰지 않는다.
//   1) node scripts/demoContentRewrite.js --uid <UID>
//        → 드라이런(기본). .demo-out/demo-plan.json 생성.
//   2) (수동) tool/demo_media/ 에 플랜이 알려준 파일명으로 이미지 배치
//   3) node scripts/demoContentRewrite.js --uid <UID> --with-media
//        → 이미지 매칭 검증(MISSING / EXTRA). 아직 쓰지 않는다.
//   4) node scripts/demoContentRewrite.js --uid <UID> --apply --backup-only
//        → 대상 문서 원문 전체를 .demo-out/backup-<ts>.json 으로 저장
//   5) node scripts/demoContentRewrite.js --uid <UID> --apply --media-only
//        → R2 업로드만. Firestore는 아직 그대로.
//   6) node scripts/demoContentRewrite.js --uid <UID> --apply
//        → 텍스트 + 새 이미지 URL을 문서에 반영(PATCH)
//   7) 앱/웹에서 **눈으로 확인**
//   8) node scripts/demoContentRewrite.js --uid <UID> --apply \
//        --cleanup-old-media --yes-really
//        → 그때서야 옛 R2 이미지 삭제(별도 명령, 기본 꺼짐)
//
//   되돌리기: node scripts/demoContentRestore.js --uid <UID> --apply
//
// ── 안전장치 ─────────────────────────────────────────────────────────────
//   · 기본이 드라이런. --apply 없이는 쓰기 코드에 진입하지 않는다.
//   · --uid 가 없으면 시작하지 않는다. 이메일·이름만으로는 절대 대상을
//     고르지 않는다(--whoami 는 uid를 **출력만** 한다).
//   · --uid 와 --email 을 함께 주면 서로 일치하는지 대조한다.
//   · 6단계는 4단계 백업 파일이 없으면 거부한다.
//
// ── 인증 ─────────────────────────────────────────────────────────────────
// 로컬 gcloud 사용자 토큰(`gcloud auth print-access-token`)을 그대로 쓴다.
// 서비스 계정 키 파일도, `gcloud auth application-default login` 도 필요 없다.
//
//   · Auth 조회(--whoami)  : firebase-admin + 커스텀 Credential
//   · Firestore 읽기·쓰기  : REST API 직접 호출
//     (firebase-admin의 Firestore 클라이언트는 커스텀 Credential을 받지 않는다
//      — backfillUserFields.js 가 REST를 쓰는 것과 같은 이유다.)
//
// 실행 전 준비:
//   gcloud auth login   (아직 로그인 안 했다면)

'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const https = require('https');
const { execSync } = require('child_process');
const admin = require('firebase-admin');

const D = require('./demoContent.data');

const PROJECT_ID = 'partychu-30c24';
const FS_BASE =
  `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

/// 산출물(플랜·백업·리포트) 폴더. **운영 데이터 원문이 들어가므로 절대
/// 커밋하지 않는다** — functions/.gitignore 에 등록되어 있다.
const OUT_DIR = path.join(__dirname, '.demo-out');

/// 사람이 준비한 데모 이미지 폴더.
/// 사람이 준비한 데모 이미지 폴더의 기본값. `--media-dir <경로>` 로 바꿀 수 있다
/// (압축을 풀면 하위 폴더가 한 겹 더 생기는 일이 잦다).
const DEFAULT_MEDIA_DIR = path.join(__dirname, '..', '..', 'tool', 'demo_media');

const MEDIA_EXTS = ['jpg', 'jpeg', 'png', 'webp'];

/// 어떤 경로로도 패치에 실려선 안 되는 필드. 조립이 끝난 뒤 [assertNoFrozen]이
/// 전수 검사하므로, 실수로 넣으면 쓰기 전에 즉시 죽는다.
const FROZEN_FIELDS = new Set([
  // 관계·소유
  'hostId', 'createdAt', 'placeId', 'placeCollection', 'seriesId', 'id',
  // 가격
  'price', 'pricePerHour', 'listPrice', 'salePrice', 'maleFee', 'femaleFee',
  'fee', 'entryFee', 'pricing', 'earlyBird', 'refundPolicy', 'refundTiers',
  'paymentPolicy', 'packages',
  // 정원
  'minCapacity', 'maxCapacity', 'capacityMin', 'capacityMax', 'maxParticipants',
  'currentParticipants', 'maleCapacity', 'femaleCapacity', 'currentMaleCount',
  'currentFemaleCount', 'people', 'totalStock', 'soldCount', 'perPersonLimit',
  // 일정
  'date', 'partyDateTime', 'recruitDeadlineAt', 'rounds', 'recurringSchedule',
  'singleSchedule', 'scheduleType', 'startAt', 'endAt', 'startDate', 'endDate',
  'startTime', 'endTime', 'openTime', 'closeTime', 'availableDays', 'weekdays',
  'saleStartAt', 'saleEndAt', 'useStartAt', 'useEndAt', 'isAlways',
  'bookingUnitMinutes', 'minBookingMinutes', 'maxBookingMinutes',
  'isOpen24Hours', 'reservationModes',
  // 상태
  'recruitStatus', 'openState', 'isActive', 'isVisible', 'hiddenAt',
  'hostBusinessVerified', 'dateTbd', 'statusMirror', 'manuallyStopped',
  'ageRestriction', 'genderLimit', 'genderMode', 'genderCapacityMode',
  'minCapacityPolicy', 'sortOrder', 'inquiryEnabled',
]);

/// partychuPerk 필드명 — 앱과 같은 값(party_app/lib/widgets/partychu_perk.dart).
const D_PERK = 'partychuPerk';

/// 패치에서 "이 필드를 지운다"를 뜻하는 표식. REST PATCH는 updateMask에는 있고
/// body에는 없는 필드를 삭제로 처리하므로, 조립 단계에서는 이 표식으로 들고
/// 다니다가 [buildPatchBody]에서 갈라진다.
const DELETE = Object.freeze({ __delete: true });
const isDelete = (v) => v === DELETE || (v && typeof v === 'object' && v.__delete === true);

/// 값이 없던 필드를 뜻하는 표식(복원용). demoContentRestore.js 와 같은 약속.
const ABSENT = '__ABSENT__';

// ── 인자 ───────────────────────────────────────────────────────────────────

function parseArgs(argv) {
  const out = { flags: new Set(), opts: {} };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (!a.startsWith('--')) continue;
    const eq = a.indexOf('=');
    if (eq > 0) {
      out.opts[a.slice(2, eq)] = a.slice(eq + 1);
    } else if (argv[i + 1] && !argv[i + 1].startsWith('--')) {
      out.opts[a.slice(2)] = argv[i + 1];
      i += 1;
    } else {
      out.flags.add(a.slice(2));
    }
  }
  return out;
}

const args = parseArgs(process.argv.slice(2));
const FLAG = (n) => args.flags.has(n);
const OPT = (n) => (args.opts[n] || '').trim();

const APPLY = FLAG('apply');
const KEEP_VIDEO = FLAG('keep-video');

const MEDIA_DIR = OPT('media-dir') ? path.resolve(OPT('media-dir')) : DEFAULT_MEDIA_DIR;

/// 갤러리 장수를 **준비된 파일 수에 맞춘다.**
///
/// 기본(꺼짐)은 문서에 지금 들어 있는 장수만큼만 슬롯을 만든다 — 파일이 모자라면
/// 그 자리에 **기존 사진이 그대로 남는다.** 실제 업체 사진을 지우는 것이 목적일
/// 때는 그게 위험하므로, 이 플래그를 켜면 배열을 준비된 파일 수로 다시 만든다
/// (남는 옛 URL은 배열에서 빠지고, 파일이 더 많으면 늘어난다).
const RESIZE_GALLERIES = FLAG('resize-galleries');

/// 이미지에는 손대지 않고 **글자만** 반영한다.
///
/// media-map.json 이 있어도 무시하므로, 새 이미지가 준비되기 전에 텍스트
/// 수정만 먼저 내보낼 때 쓴다(이미 붙어 있는 이미지 URL을 다시 쓰지도 않는다).
const TEXT_ONLY = FLAG('text-only');

/// 드라이런에서 **필드별 현재값 → 변경값**을 전부 찍는다.
const SHOW_DIFF = FLAG('diff');

// ── 인증 토큰 ──────────────────────────────────────────────────────────────

let _token = null;
let _tokenAt = 0;

function getAccessToken() {
  // 토큰은 1시간짜리다. 스크립트가 오래 돌 수 있으니 30분마다 새로 받는다.
  if (_token && Date.now() - _tokenAt < 30 * 60 * 1000) return _token;
  _token = execSync('gcloud auth print-access-token', { encoding: 'utf8' }).trim();
  _tokenAt = Date.now();
  return _token;
}

// firebase-admin은 **Auth 조회에만** 쓴다(커스텀 Credential로 동작한다).
admin.initializeApp({
  credential: {
    getAccessToken: async () => ({ access_token: getAccessToken(), expires_in: 3600 }),
  },
  projectId: PROJECT_ID,
});

// ── Firestore REST ─────────────────────────────────────────────────────────
//
// 필요한 것은 세 가지뿐이다: hostId로 훑기(runQuery) · 한 건 읽기(GET) ·
// 한 건 갱신(PATCH). 문서 생성·삭제 엔드포인트는 아예 부르지 않는다.

async function fsFetch(url, options = {}) {
  const res = await fetch(url, {
    ...options,
    headers: {
      Authorization: `Bearer ${getAccessToken()}`,
      'x-goog-user-project': PROJECT_ID,
      'Content-Type': 'application/json',
      ...(options.headers || {}),
    },
  });
  const text = await res.text();
  const body = text ? JSON.parse(text) : null;
  if (!res.ok) {
    const msg = body && body.error ? body.error.message : text;
    throw new Error(`${options.method || 'GET'} ${url.replace(FS_BASE, '')} → ${res.status}: ${msg}`);
  }
  return body;
}

// ── REST 타입 값 ↔ 순수 JS 코덱 ────────────────────────────────────────────
//
// Timestamp·GeoPoint·DocumentReference는 태그 붙은 객체로 옮긴다. 백업/복원이
// 왕복해도 타입이 사라지지 않게 하기 위해서다(demoContentRestore.js 가 같은
// 규칙으로 되돌린다).

function decodeValue(v) {
  if (v === null || v === undefined) return null;
  if ('nullValue' in v) return null;
  if ('stringValue' in v) return v.stringValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return Number(v.doubleValue);
  if ('timestampValue' in v) return { __t: 'ts', v: v.timestampValue };
  if ('geoPointValue' in v) {
    return { __t: 'geo', lat: v.geoPointValue.latitude || 0, lng: v.geoPointValue.longitude || 0 };
  }
  if ('referenceValue' in v) return { __t: 'ref', path: v.referenceValue };
  if ('bytesValue' in v) return { __t: 'bytes', b64: v.bytesValue };
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(decodeValue);
  if ('mapValue' in v) {
    const o = {};
    for (const [k, val] of Object.entries(v.mapValue.fields || {})) o[k] = decodeValue(val);
    return o;
  }
  throw new Error(`알 수 없는 Firestore 값: ${JSON.stringify(v)}`);
}

function decodeFields(fields) {
  const o = {};
  for (const [k, v] of Object.entries(fields || {})) o[k] = decodeValue(v);
  return o;
}

function encodeValue(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === 'string') return { stringValue: v };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') {
    if (!Number.isFinite(v)) throw new Error(`숫자가 아닌 값: ${v}`);
    // ⚠️ 정수/실수 구분이 그대로 저장 타입이 된다. 좌표(37.5570)는 실수로,
    //    개수는 정수로 나가야 앱의 `as num` 읽기가 예전과 같이 동작한다.
    return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  }
  if (Array.isArray(v)) return { arrayValue: { values: v.map(encodeValue) } };
  if (typeof v === 'object') {
    if (v.__t === 'ts') return { timestampValue: v.v };
    if (v.__t === 'geo') return { geoPointValue: { latitude: v.lat, longitude: v.lng } };
    if (v.__t === 'ref') return { referenceValue: v.path };
    if (v.__t === 'bytes') return { bytesValue: v.b64 };
    const fields = {};
    for (const [k, val] of Object.entries(v)) fields[k] = encodeValue(val);
    return { mapValue: { fields } };
  }
  throw new Error(`인코딩할 수 없는 값: ${typeof v}`);
}

const nowTs = () => ({ __t: 'ts', v: new Date().toISOString() });

/// hostId == uid 인 문서를 전부 가져온다. 단일 필드 동등 비교라 복합 인덱스가
/// 필요 없다.
async function restQueryByHost(collectionId, uid) {
  const body = await fsFetch(`${FS_BASE}:runQuery`, {
    method: 'POST',
    body: JSON.stringify({
      structuredQuery: {
        from: [{ collectionId }],
        where: {
          fieldFilter: { field: { fieldPath: 'hostId' }, op: 'EQUAL', value: { stringValue: uid } },
        },
      },
    }),
  });
  const out = [];
  for (const row of body || []) {
    if (!row.document) continue;
    out.push({
      id: row.document.name.split('/').pop(),
      data: decodeFields(row.document.fields),
    });
  }
  return out;
}

async function restGet(collectionId, docId) {
  try {
    const doc = await fsFetch(`${FS_BASE}/${collectionId}/${encodeURIComponent(docId)}`);
    return decodeFields(doc.fields);
  } catch (e) {
    if (/→ 404/.test(e.message)) return null;
    throw e;
  }
}

/// 패치 하나를 body(쓸 값)와 mask(건드릴 필드)로 가른다. mask에 있고 body에
/// 없는 필드는 서버가 **그 필드만** 지운다(문서는 남는다).
function buildPatchBody(patch) {
  const fields = {};
  const mask = [];
  for (const [k, v] of Object.entries(patch)) {
    mask.push(k);
    if (isDelete(v)) continue;
    fields[k] = encodeValue(v);
  }
  return { fields, mask };
}

async function restPatch(collectionId, docId, patch) {
  const { fields, mask } = buildPatchBody(patch);
  const params = mask.map((m) => `updateMask.fieldPaths=${encodeURIComponent(m)}`);
  // ⚠️ 없는 문서에 PATCH하면 Firestore는 **문서를 만든다.** 이 스크립트는
  //    무엇도 만들지 않아야 하므로, 존재 조건을 걸어 서버가 거부하게 한다.
  params.push('currentDocument.exists=true');
  const url = `${FS_BASE}/${collectionId}/${encodeURIComponent(docId)}?${params.join('&')}`;
  await fsFetch(url, { method: 'PATCH', body: JSON.stringify({ fields }) });
}

// ── 유틸 ───────────────────────────────────────────────────────────────────

const pad2 = (n) => String(n).padStart(2, '0');
const str = (v) => (typeof v === 'string' ? v : '');
const arr = (v) => (Array.isArray(v) ? v : []);

function ensureOutDir() {
  if (!fs.existsSync(OUT_DIR)) fs.mkdirSync(OUT_DIR, { recursive: true });
}

function stamp() {
  const d = new Date();
  return (
    `${d.getFullYear()}${pad2(d.getMonth() + 1)}${pad2(d.getDate())}` +
    `-${pad2(d.getHours())}${pad2(d.getMinutes())}${pad2(d.getSeconds())}`
  );
}

/// createdAt(없으면 문서 id)으로 안정 정렬 — 재실행해도 슬러그가 흔들리지 않는다.
function sortStable(docs) {
  const t = (d) => {
    const c = d.data.createdAt;
    return c && c.__t === 'ts' ? Date.parse(c.v) || 0 : 0;
  };
  return [...docs].sort((a, b) => {
    const ta = t(a);
    const tb = t(b);
    if (ta !== tb) return ta - tb;
    return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
  });
}

async function fetchByHost(collection, uid) {
  return sortStable(await restQueryByHost(collection, uid));
}

/// 패치에 얼려둔 필드가 섞이지 않았는지 최종 검사. 하나라도 걸리면 던진다.
function assertNoFrozen(collection, docId, patch) {
  for (const key of Object.keys(patch)) {
    if (FROZEN_FIELDS.has(key)) {
      throw new Error(
        `[치명] ${collection}/${docId} 패치에 변경 금지 필드가 들어 있다: ${key}`,
      );
    }
  }
}

// ── whoami ─────────────────────────────────────────────────────────────────

const COUNT_COLLECTIONS = [
  ['parties', '파티'],
  ['events', '플레이스'],
  ['places', '장소대여'],
  ['placePromotions', '이벤트'],
  ['placeRooms', '장소대여 룸'],
  ['placeMenus', '플레이스 메뉴'],
  ['placeProducts', '플레이스 상품'],
];

/// 이 스크립트가 다루지 않지만 같은 uid로 남아 있을 수 있는 것들 — 있으면
/// 알려만 준다(조용히 남기지 않는다).
const EXTRA_COLLECTIONS = [
  ['partyShops', '파티샵'],
  ['crews', '크루'],
  ['partyServices', '파트너 서비스'],
];

async function runWhoami() {
  const email = OPT('email');
  const uidOpt = OPT('uid');
  if (!email && !uidOpt) {
    console.error('--whoami 에는 --email 또는 --uid 가 필요하다.');
    process.exit(1);
  }

  let uid = uidOpt;
  let user;
  if (email) {
    user = await admin.auth().getUserByEmail(email);
    if (uidOpt && uidOpt !== user.uid) {
      console.error(`[중단] --uid(${uidOpt})와 --email(${email} → ${user.uid})이 다르다.`);
      process.exit(1);
    }
    uid = user.uid;
  } else {
    user = await admin.auth().getUser(uid);
  }

  console.log('');
  console.log('════════ whoami ════════');
  console.log(`uid       : ${uid}`);
  console.log(`email     : ${user.email || '(없음)'}`);
  console.log(`providers : ${(user.providerData || []).map((p) => p.providerId).join(', ') || '(없음)'}`);
  console.log(`가입      : ${user.metadata && user.metadata.creationTime}`);
  console.log('');
  console.log('hostId == 이 uid 인 문서 수');
  console.log('──────────────────────────────────────────────');
  for (const [col, label] of COUNT_COLLECTIONS) {
    const docs = await restQueryByHost(col, uid);
    console.log(`  ${w(label, 14)}${w(col, 18)}${String(docs.length).padStart(4)}건`);
  }
  console.log('  ── 이 스크립트가 다루지 않는 것(있으면 별도 처리 필요) ──');
  for (const [col, label] of EXTRA_COLLECTIONS) {
    const docs = await restQueryByHost(col, uid);
    console.log(`  ${w(label, 14)}${w(col, 18)}${String(docs.length).padStart(4)}건${docs.length > 0 ? '  ⚠️' : ''}`);
  }
  console.log('');
  console.log('아무것도 쓰지 않았다. 다음 단계:');
  console.log(`  node scripts/demoContentRewrite.js --uid ${uid}`);
  console.log('');
}

// ── 상세페이지 블록(detailBlocks) 다시 쓰기 ────────────────────────────────
//
// 구조(id·type·순서·크롭·비율)는 그대로 두고 **글자만** 갈아 끼운다. 원문에
// 실제 상호가 섞여 있을 수 있어 부분 치환이 아니라 통째로 다시 쓴다.
// 이미지 블록의 imageUrl은 여기서 건드리지 않는다 — 미디어 단계가 맡는다.

function rewriteDetailBlocks(blocks) {
  const pick = (list, i) => list[i % list.length];
  let textN = 0;
  return arr(blocks)
    .map((raw) => {
      if (!raw || typeof raw !== 'object') return raw;
      const b = { ...raw };
      switch (str(b.type)) {
        case 'heading':
          b.text = pick(D.BLOCK_TEXT.heading, textN++);
          break;
        case 'subheading':
          b.text = pick(D.BLOCK_TEXT.subheading, textN++);
          break;
        case 'paragraph':
          b.text = pick(D.BLOCK_TEXT.paragraph, textN++);
          break;
        case 'notice':
          b.text = pick(D.BLOCK_TEXT.notice, textN++);
          break;
        case 'checklist':
          b.title = D.BLOCK_CHECKLIST.title;
          b.items = [...D.BLOCK_CHECKLIST.items];
          break;
        case 'faq':
          b.title = D.BLOCK_FAQ.title;
          b.items = arr(b.items).map((it, i) => {
            const src = D.BLOCK_FAQ.items[i % D.BLOCK_FAQ.items.length];
            return { ...(it || {}), question: src.question, answer: src.answer };
          });
          break;
        case 'timeline':
          b.title = D.BLOCK_TIMELINE.title;
          b.items = arr(b.items).map((it, i) => {
            const src = D.BLOCK_TIMELINE.items[i % D.BLOCK_TIMELINE.items.length];
            return { ...(it || {}), time: src.time, title: src.title, description: src.description };
          });
          break;
        case 'infoCard':
          b.title = D.BLOCK_INFO_CARD.title;
          b.text = D.BLOCK_INFO_CARD.text;
          break;
        case 'image':
        case 'imageGroup':
          if (typeof b.caption === 'string') b.caption = D.BLOCK_IMAGE_CAPTION;
          break;
        case 'video':
          // 1차에서 동영상은 제외 — 블록 자체를 뺀다.
          b.__dropVideo = !KEEP_VIDEO;
          break;
        default:
          break;
      }
      return b;
    })
    .filter((b) => !(b && b.__dropVideo));
}

/// 블록에서 이미지 슬롯을 뽑는다 — 미디어 파일명 목록에 쓰인다.
function blockImageSlots(blocks) {
  const slots = [];
  arr(blocks).forEach((b, bi) => {
    if (!b || typeof b !== 'object') return;
    if (str(b.type) === 'image' && str(b.imageUrl)) {
      slots.push({ path: `detailBlocks.${bi}.imageUrl`, current: str(b.imageUrl) });
    }
    if (str(b.type) === 'imageGroup') {
      arr(b.items).forEach((it, ii) => {
        if (it && str(it.imageUrl)) {
          slots.push({ path: `detailBlocks.${bi}.items.${ii}.imageUrl`, current: str(it.imageUrl) });
        }
      });
    }
  });
  return slots;
}

// ── 동영상 제거 패치 ───────────────────────────────────────────────────────
//
// 실제 업체 영상이 남지 않게 필드를 지우고 커버를 사진으로 내린다.
// (updateMask에만 올라가고 body에는 빠지므로 **그 필드만** 사라진다.)

function videoStripPatch(data) {
  if (KEEP_VIDEO) return {};
  const patch = {};
  const has = (k) =>
    Object.prototype.hasOwnProperty.call(data, k) && data[k] !== null && data[k] !== '';
  for (const k of ['videoProvider', 'videoUid', 'videoUrl', 'videoThumbnailUrl',
                   'coverVideoUid', 'coverVideoUrl']) {
    if (has(k)) patch[k] = DELETE;
  }
  if (Object.keys(patch).length > 0 || str(data.coverMediaType) === 'video') {
    patch.coverMediaType = 'image';
  }
  return patch;
}

// ── 계획 수립 ──────────────────────────────────────────────────────────────

function mediaSlot(slug, role, index) {
  return `${slug}-${role}${index === undefined ? '' : `-${index}`}`;
}

async function buildPlan(uid) {
  const targets = [];

  // ── 파티(parties) — seriesId가 같으면 한 묶음: 같은 이름·같은 지역 ──────
  const parties = await fetchByHost('parties', uid);
  const groups = new Map();
  for (const p of parties) {
    const key = str(p.data.seriesId) || `__solo__${p.id}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(p);
  }

  let gi = 0;
  for (const [seriesKey, docs] of groups) {
    const slug = `party-${pad2(gi + 1)}`;
    const { name, region } = D.buildName('party', gi, slug);
    const loc = D.locationParts(region);
    const description = D.partyDescription({ name, region });

    // 묶음 안에서 갤러리 장수는 가장 많은 문서 기준 — 파일을 공유한다.
    const galleryMax = docs.reduce((mx, d) => {
      const n = arr(d.data.images).length || arr(d.data.imageUrls).length;
      return n > mx ? n : mx;
    }, 0);

    const files = [{ file: mediaSlot(slug, 'cover'), role: 'cover' }];
    for (let i = 1; i <= galleryMax; i += 1) {
      files.push({ file: mediaSlot(slug, 'gallery', i), role: 'gallery' });
    }

    for (const p of docs) {
      const d = p.data;
      const blocks = rewriteDetailBlocks(d.detailBlocks);

      const patch = {
        title: name,
        description,
        placeName: name,
        [D_PERK]: D.PARTYCHU_PERK,
        tags: D.PARTY_TAGS.slice(0, Math.max(arr(d.tags).length, 3)),
        // 유형·분위기 — 예전 값이 그대로 남아 새 제목과 어긋났다(보드게임
        // 나이트에 '선상 파티' 같은 식). 앱 허용 목록의 문자열만 쓴다.
        partyTypes: [...D.PARTY_TYPE_VIBES[slug].types],
        vibes: [...D.PARTY_TYPE_VIBES[slug].vibes],
        location: loc.location,
        address: loc.address,
        roadAddress: loc.roadAddress,
        jibunAddress: loc.jibunAddress,
        detailAddress: loc.detailAddress,
        latitude: loc.latitude,
        longitude: loc.longitude,
        region: loc.region,
        district: loc.district,
      };
      if (Object.prototype.hasOwnProperty.call(d, 'detailBlocks')) patch.detailBlocks = blocks;
      Object.assign(patch, videoStripPatch(d));
      assertNoFrozen('parties', p.id, patch);

      const media = [];
      const imgs = arr(d.images).length > 0 ? arr(d.images) : arr(d.imageUrls);
      // 대표 사진은 **조건 없이 항상** 새 파일로 연결한다.
      //
      // ⚠️ 예전에는 `coverImageUrl이 있거나 사진이 있을 때만` 걸었다. 그러면
      //    커버가 **동영상**이던 문서(coverImageUrl이 비어 있다)가 통째로 빠져서,
      //    업로드한 -cover 파일이 어디에도 붙지 않고 coverThumbnailUrl에는 옛
      //    Stream 썸네일이 그대로 남았다.
      media.push({
        file: mediaSlot(slug, 'cover'),
        field: 'coverImageUrl',
        current: str(d.coverImageUrl),
      });
      // 레거시 대표 사진 — 파티에도 이 필드가 있고, 찜 목록·호스트 허브 카드·
      // 상세 폴백이 아직 읽는다(my_favorites_screen.dart:573,
      // my_host_hub_screen.dart:3524, party_detail_screen.dart:2526). 여기를
      // 비워 두면 그 화면들에만 옛 실제 사진이 계속 뜬다.
      media.push({
        file: mediaSlot(slug, 'cover'),
        field: 'mainImageUrl',
        current: str(d.mainImageUrl),
      });
      imgs.forEach((u, i) => {
        media.push({ file: mediaSlot(slug, 'gallery', i + 1), field: `images[${i}]`, current: str(u) });
      });
      if (str(d.detailImageUrl)) {
        const f = mediaSlot(slug, 'detail');
        media.push({ file: f, field: 'detailImageUrl', current: str(d.detailImageUrl) });
        if (!files.some((x) => x.file === f)) files.push({ file: f, role: 'detail' });
      }
      blockImageSlots(blocks).forEach((s, i) => {
        const f = mediaSlot(slug, 'block', i + 1);
        media.push({ file: f, field: s.path, current: s.current });
        if (!files.some((x) => x.file === f)) files.push({ file: f, role: 'block' });
      });

      targets.push({
        collection: 'parties',
        docId: p.id,
        slug,
        seriesKey: seriesKey.startsWith('__solo__') ? '(단독)' : seriesKey,
        kind: '파티',
        beforeName: str(d.title),
        beforeExtra: str(d.placeName),
        afterName: name,
        region,
        patch,
        media,
        files,
        gallery: { field: 'images', name: (n) => mediaSlot(slug, 'gallery', n) },
        allImageUrls: [
          str(d.coverImageUrl), str(d.mainImageUrl), ...imgs.map(str), str(d.detailImageUrl),
          ...blockImageSlots(blocks).map((s) => s.current),
        ].filter(Boolean),
      });
    }
    gi += 1;
  }

  // ── 플레이스(events) ────────────────────────────────────────────────────
  //
  // 이벤트(placePromotions)가 부모의 지역을 물려받을 수 있도록 표를 남긴다.
  const placeById = new Map();
  (await fetchByHost('events', uid)).forEach((p, i) => {
    const d = p.data;
    const slug = `place-${pad2(i + 1)}`;
    const { name, region } = D.buildName('place', i, slug);
    const loc = D.locationParts(region);
    placeById.set(p.id, { region, name, slug });

    const patch = {
      name,
      description: D.placeDescription({ name, region }),
      [D_PERK]: D.PARTYCHU_PERK,
      address: loc.address,
      roadAddress: loc.roadAddress,
      jibunAddress: loc.jibunAddress,
      detailAddress: loc.detailAddress,
      location: loc.location,
      latitude: loc.latitude,
      longitude: loc.longitude,
    };
    Object.assign(patch, videoStripPatch(d));
    assertNoFrozen('events', p.id, patch);

    const media = [];
    const files = [{ file: mediaSlot(slug, 'cover'), role: 'cover' }];
    // 조건 없이 항상 — 파티와 같은 이유다(커버가 동영상이면 두 필드가 비어 있다).
    media.push({ file: mediaSlot(slug, 'cover'), field: 'mainImageUrl', current: str(d.mainImageUrl) });
    media.push({ file: mediaSlot(slug, 'cover'), field: 'coverImageUrl', current: str(d.coverImageUrl) });
    arr(d.introImageUrls).forEach((u, k) => {
      const f = mediaSlot(slug, 'gallery', k + 1);
      media.push({ file: f, field: `introImageUrls[${k}]`, current: str(u) });
      files.push({ file: f, role: 'gallery' });
    });

    targets.push({
      collection: 'events', docId: p.id, slug, kind: '플레이스',
      beforeName: str(d.name), beforeExtra: str(d.address), afterName: name,
      region, patch, media, files,
      gallery: { field: 'introImageUrls', name: (n) => mediaSlot(slug, 'gallery', n) },
      allImageUrls: [str(d.mainImageUrl), str(d.coverImageUrl), ...arr(d.introImageUrls).map(str)]
        .filter(Boolean),
    });
  });

  // ── 장소대여(places) ────────────────────────────────────────────────────
  const rentalById = new Map();
  (await fetchByHost('places', uid)).forEach((p, i) => {
    const d = p.data;
    const { name, region } = D.buildName('rental', i);
    const slug = `rental-${pad2(i + 1)}`;
    const loc = D.locationParts(region);
    rentalById.set(p.id, { region, name, slug });

    // ⚠️ 장소대여만 좌표 키가 lat/lng 다(나머지는 latitude/longitude).
    //    `address`에도 도로명이 들어간다(place_register_screen.dart:1164).
    const patch = {
      name,
      description: D.rentalDescription({ name, region }),
      address: loc.roadAddress,
      detailAddress: loc.detailAddress,
      lat: loc.latitude,
      lng: loc.longitude,
    };
    Object.assign(patch, videoStripPatch(d));
    assertNoFrozen('places', p.id, patch);

    const media = [];
    const files = [{ file: mediaSlot(slug, 'cover'), role: 'cover' }];
    // 조건 없이 항상 — 커버가 동영상이던 문서도 사진 커버를 받아야 한다.
    media.push({
      file: mediaSlot(slug, 'cover'),
      field: 'coverImageUrl',
      current: str(d.coverImageUrl),
    });
    arr(d.imageUrls).forEach((u, k) => {
      const f = mediaSlot(slug, 'gallery', k + 1);
      media.push({ file: f, field: `imageUrls[${k}]`, current: str(u) });
      files.push({ file: f, role: 'gallery' });
    });

    targets.push({
      collection: 'places', docId: p.id, slug, kind: '장소대여',
      beforeName: str(d.name), beforeExtra: str(d.address), afterName: name,
      region, patch, media, files,
      gallery: { field: 'imageUrls', name: (n) => mediaSlot(slug, 'gallery', n) },
      allImageUrls: [str(d.coverImageUrl), ...arr(d.imageUrls).map(str)].filter(Boolean),
    });
  });

  // ── 장소대여 룸(placeRooms) ─────────────────────────────────────────────
  (await fetchByHost('placeRooms', uid)).forEach((p, i) => {
    const d = p.data;
    const parent = rentalById.get(str(d.placeId));
    const region = parent ? parent.region : D.REGIONS[i % D.REGIONS.length];
    const roomName = D.ROOM_NAMES[i % D.ROOM_NAMES.length];
    const slug = `room-${pad2(i + 1)}`;

    const patch = {
      roomName,
      roomDescription: D.roomDescription({ roomName, region }),
    };
    // 옵션 이름에 상호가 섞였을 수 있어 프리셋으로 갈되 **가격은 그대로** 둔다.
    if (arr(d.options).length > 0) {
      patch.options = arr(d.options).map((o, k) => ({
        ...(o || {}),
        name: D.ROOM_OPTION_NAMES[k % D.ROOM_OPTION_NAMES.length],
      }));
    }
    assertNoFrozen('placeRooms', p.id, patch);

    const media = [];
    const files = [];
    arr(d.roomImages).forEach((u, k) => {
      const f = `${slug}-${k + 1}`;
      media.push({ file: f, field: `roomImages[${k}]`, current: str(u) });
      files.push({ file: f, role: 'room' });
    });

    targets.push({
      collection: 'placeRooms', docId: p.id, slug, kind: '룸',
      beforeName: str(d.roomName), beforeExtra: parent ? parent.slug : '(부모 없음)',
      afterName: roomName, region, patch, media, files,
      // 룸 사진은 `room-01-1` 처럼 'gallery' 없이 번호만 붙는다.
      gallery: { field: 'roomImages', name: (n) => `${slug}-${n}`, role: 'room' },
      allImageUrls: arr(d.roomImages).map(str).filter(Boolean),
    });
  });

  // ── 이벤트(placePromotions) ─────────────────────────────────────────────
  (await fetchByHost('placePromotions', uid)).forEach((p, i) => {
    const d = p.data;
    const slug = `event-${pad2(i + 1)}`;
    // ⚠️ 지역은 순번이 아니라 **부모 장소**를 따라간다. 이벤트 사진은 곧 부모
    //    매장 사진이라, 제목이 성수인데 부모가 홍대면 어떤 사진을 넣어도
    //    틀린다. placeCollection이 'events'면 플레이스, 'places'면 장소대여다.
    const parentMap = str(d.placeCollection) === 'places' ? rentalById : placeById;
    const parent = parentMap.get(str(d.placeId));
    const region = parent ? parent.region : D.REGIONS[i % D.REGIONS.length];
    const { name: title } = D.buildNameAt('event', i, region, slug);

    const patch = {
      title,
      description: D.promotionDescription({ title, region }),
      benefit: '웰컴 드링크 1잔 제공 (예시 혜택)',
      conditions: '앱에서 이벤트를 확인하고 방문 시 적용됩니다.',
      priceText: '',
      tags: D.PROMOTION_TAGS.slice(0, Math.max(arr(d.tags).length, 2)),
      audience: '누구나',
    };
    if (str(d.reservationGuide)) {
      patch.reservationGuide = '방문 전 앱에서 문의를 남겨 주세요. (예시 안내)';
    }
    if (str(d.sourcePartyTitle)) {
      patch.sourcePartyTitle = `파티츄 ${region.label} 소셜 나이트`;
    }
    Object.assign(patch, videoStripPatch(d));
    assertNoFrozen('placePromotions', p.id, patch);

    const media = [];
    const files = [{ file: mediaSlot(slug, 'cover'), role: 'cover' }];
    // 조건 없이 항상 — 커버가 동영상이던 이벤트도 사진 커버를 받아야 한다.
    media.push({ file: mediaSlot(slug, 'cover'), field: 'imageUrl', current: str(d.imageUrl) });
    media.push({ file: mediaSlot(slug, 'cover'), field: 'coverImageUrl', current: str(d.coverImageUrl) });
    arr(d.imageUrls).forEach((u, k) => {
      const f = mediaSlot(slug, 'gallery', k + 1);
      media.push({ file: f, field: `imageUrls[${k}]`, current: str(u) });
      files.push({ file: f, role: 'gallery' });
    });

    targets.push({
      collection: 'placePromotions', docId: p.id, slug, kind: '이벤트',
      parentName: parent ? parent.name : `(부모 없음: ${str(d.placeCollection)}/${str(d.placeId)})`,
      beforeName: str(d.title), beforeExtra: str(d.benefit), afterName: title,
      region, patch, media, files,
      gallery: { field: 'imageUrls', name: (n) => mediaSlot(slug, 'gallery', n) },
      allImageUrls: [str(d.imageUrl), str(d.coverImageUrl), ...arr(d.imageUrls).map(str)]
        .filter(Boolean),
    });
  });

  // ── 메뉴(placeMenus) ────────────────────────────────────────────────────
  (await fetchByHost('placeMenus', uid)).forEach((p, i) => {
    const d = p.data;
    const name = D.MENU_NAMES[i % D.MENU_NAMES.length];
    const slug = `menu-${pad2(i + 1)}`;
    const patch = { name, description: D.menuDescription() };
    assertNoFrozen('placeMenus', p.id, patch);
    const media = [];
    const files = [];
    if (str(d.imageUrl)) {
      media.push({ file: slug, field: 'imageUrl', current: str(d.imageUrl) });
      files.push({ file: slug, role: 'single' });
    }
    targets.push({
      collection: 'placeMenus', docId: p.id, slug, kind: '메뉴',
      beforeName: str(d.name), beforeExtra: '', afterName: name,
      region: null, patch, media, files,
      allImageUrls: [str(d.imageUrl)].filter(Boolean),
    });
  });

  // ── 상품·이용권(placeProducts) ──────────────────────────────────────────
  (await fetchByHost('placeProducts', uid)).forEach((p, i) => {
    const d = p.data;
    const name = D.PRODUCT_NAMES[i % D.PRODUCT_NAMES.length];
    const slug = `product-${pad2(i + 1)}`;
    const patch = {
      name,
      description: D.productDescription({ name }),
      useGuide: '현장에서 QR을 보여주시면 사용 처리됩니다. (예시 안내)',
    };
    assertNoFrozen('placeProducts', p.id, patch);
    const media = [];
    const files = [];
    if (str(d.imageUrl)) {
      media.push({ file: slug, field: 'imageUrl', current: str(d.imageUrl) });
      files.push({ file: slug, role: 'single' });
    }
    targets.push({
      collection: 'placeProducts', docId: p.id, slug, kind: '상품',
      beforeName: str(d.name), beforeExtra: '', afterName: name,
      region: null, patch, media, files,
      allImageUrls: [str(d.imageUrl)].filter(Boolean),
    });
  });

  return targets;
}

// ── 이미지 파일 매칭 ───────────────────────────────────────────────────────

function findMediaFile(base) {
  for (const ext of MEDIA_EXTS) {
    const p = path.join(MEDIA_DIR, `${base}.${ext}`);
    if (fs.existsSync(p)) return p;
  }
  return null;
}

/// 갤러리 슬롯 수를 **준비된 파일 수**에 맞춘다(--resize-galleries).
///
/// 기본 동작은 "문서에 있는 장수만큼만" 슬롯을 만들기 때문에, 파일이 모자라면
/// 그 자리에 실제 업체 사진이 그대로 남는다. 반대로 파일이 더 많으면 남는 파일이
/// 쓰이지 않는다. 이 함수는 배열을 준비된 파일 수로 다시 세워 둘 다 없앤다.
///
/// 파일이 **한 장도 없으면 손대지 않는다** — 갤러리를 통째로 비우는 일은
/// 하지 않는다.
function resizeGalleries(targets) {
  for (const t of targets) {
    if (!t.gallery) continue;
    const { field } = t.gallery;
    const prefix = `${field}[`;

    // 지금 문서의 갤러리 URL을 인덱스 순서대로 복원한다.
    const currentUrls = [];
    for (const m of t.media) {
      if (!m.field.startsWith(prefix)) continue;
      currentUrls[Number(m.field.slice(prefix.length, -1))] = m.current;
    }

    let n = 0;
    while (findMediaFile(t.gallery.name(n + 1))) n += 1;
    if (n === 0) continue;

    const role = t.gallery.role || 'gallery';
    t.media = t.media.filter((m) => !m.field.startsWith(prefix));
    t.files = t.files.filter((f) => f.role !== role);
    for (let i = 0; i < n; i += 1) {
      t.media.push({ file: t.gallery.name(i + 1), field: `${field}[${i}]`, current: currentUrls[i] || '' });
      t.files.push({ file: t.gallery.name(i + 1), role });
    }
    t.galleryResize = {
      field,
      count: n,
      was: currentUrls.length,
      // 배열에서 아예 빠지는 옛 URL — 문서에 남지 않으므로 "잔존"이 아니다.
      dropped: currentUrls.slice(n).filter(Boolean),
    };
  }
}

/// 이 문서에 **교체되지 않고 그대로 남는** 기존 이미지 URL.
/// 실제 업체 사진이 남는지 확인하는 유일한 지표라, 리포트의 핵심이다.
function leftoverImageUrls(t) {
  const covered = new Set();
  for (const m of t.media) {
    if (m.current && findMediaFile(m.file)) covered.add(m.current);
  }
  const dropped = new Set((t.galleryResize && t.galleryResize.dropped) || []);
  return (t.allImageUrls || []).filter((u) => !covered.has(u) && !dropped.has(u));
}

function requiredFiles(targets) {
  const set = new Map();
  for (const t of targets) {
    for (const f of t.files || []) {
      if (!set.has(f.file)) set.set(f.file, { file: f.file, role: f.role, kind: t.kind });
    }
  }
  return [...set.values()].sort((a, b) => (a.file < b.file ? -1 : 1));
}

// ── 리포트 ─────────────────────────────────────────────────────────────────

/// 한글은 터미널에서 2칸을 먹는다 — 표가 어긋나지 않게 폭을 세어 채운다.
function w(s, n) {
  const t = String(s);
  const width = [...t].reduce((acc, ch) => acc + (ch.codePointAt(0) > 0x1100 ? 2 : 1), 0);
  return t + ' '.repeat(Math.max(1, n - width));
}

function clip(s, n) {
  const t = String(s || '');
  let width = 0;
  let out = '';
  for (const ch of t) {
    const cw = ch.codePointAt(0) > 0x1100 ? 2 : 1;
    if (width + cw > n) return `${out}…`;
    out += ch;
    width += cw;
  }
  return out;
}

/// `--with-media` 리포트 — MATCHED / MISSING / EXTRA 와, 가장 중요한
/// "교체되지 않고 남는 기존 이미지" 감사.
function printMediaAudit(targets, files) {
  console.log('▌이미지 폴더');
  console.log(`  ${MEDIA_DIR}`);
  console.log(`  갤러리 장수 맞추기(--resize-galleries): ${RESIZE_GALLERIES ? '켜짐' : '꺼짐'}`);
  console.log('');

  const matched = [];
  const missing = [];
  for (const f of files) {
    const found = findMediaFile(f.file);
    (found ? matched : missing).push({ ...f, found });
  }

  const present = new Set(files.map((f) => f.file));
  const onDisk = fs.existsSync(MEDIA_DIR)
    ? fs.readdirSync(MEDIA_DIR).filter((n) => MEDIA_EXTS.includes(path.extname(n).slice(1).toLowerCase()))
    : [];
  const extras = onDisk.filter((n) => {
    const ext = path.extname(n).slice(1).toLowerCase();
    return !present.has(n.slice(0, -(ext.length + 1)));
  });

  console.log(`▌요약   MATCHED ${matched.length}   MISSING ${missing.length}   EXTRA ${extras.length}`);
  console.log(`        폴더에 있는 이미지 ${onDisk.length}개 / 플랜이 요구하는 슬롯 ${files.length}개`);
  console.log('');

  console.log(`▌MATCHED — ${matched.length}개 (업로드 후 이 슬롯에 연결된다)`);
  console.log(`  ${w('파일명', 30)}${w('용도', 10)}${w('대상', 12)}실제 파일`);
  console.log(`  ${'─'.repeat(96)}`);
  for (const f of matched) {
    console.log(`  ${w(f.file, 30)}${w(f.role, 10)}${w(f.kind, 12)}${path.basename(f.found)}`);
  }
  console.log('');

  console.log(`▌MISSING — ${missing.length}개 (파일 없음 → 그 자리 기존 이미지가 그대로 남는다)`);
  if (missing.length === 0) {
    console.log('  없음');
  } else {
    console.log(`  ${w('파일명', 30)}${w('용도', 10)}대상`);
    console.log(`  ${'─'.repeat(96)}`);
    for (const f of missing) console.log(`  ${w(f.file, 30)}${w(f.role, 10)}${f.kind}`);
  }
  console.log('');

  console.log(`▌EXTRA — ${extras.length}개 (폴더에 있지만 연결될 슬롯이 없다 → 업로드되지 않는다)`);
  if (extras.length === 0) {
    console.log('  없음');
  } else {
    for (const e of extras) console.log(`  ${e}`);
  }
  console.log('');

  // seriesId 공유 확인 — 같은 슬러그를 쓰는 파티 문서가 같은 파일을 받는가.
  const bySlug = new Map();
  for (const t of targets.filter((x) => x.collection === 'parties')) {
    if (!bySlug.has(t.slug)) bySlug.set(t.slug, []);
    bySlug.get(t.slug).push(t);
  }
  const shared = [...bySlug.entries()].filter(([, list]) => list.length > 1);
  console.log(`▌seriesId 공유 이미지 확인 — 문서 2건 이상인 묶음 ${shared.length}개`);
  if (shared.length === 0) {
    console.log('  없음(모든 파티가 단독 문서다).');
  } else {
    for (const [slug, list] of shared) {
      const wanted = [...new Set(list.flatMap((t) => t.media.map((m) => m.file)))].sort();
      const same = list.every(
        (t) => JSON.stringify(t.media.map((m) => m.file).sort()) ===
               JSON.stringify(list[0].media.map((m) => m.file).sort()),
      );
      console.log(`  ${slug}  문서 ${list.length}건  seriesId=${list[0].seriesKey}`);
      console.log(`     문서 ID : ${list.map((t) => t.docId).join(' , ')}`);
      console.log(`     파일 동일 여부: ${same ? 'OK — 같은 파일 집합을 받는다' : '⚠️ 문서마다 다르다'}`);
      for (const f of wanted) {
        const found = findMediaFile(f);
        console.log(`       ${w(f, 26)}${found ? `MATCHED  ${path.basename(found)}` : 'MISSING'}`);
      }
    }
  }
  console.log('');

  // 갤러리 장수 조정 내역
  const resized = targets.filter((t) => t.galleryResize && t.galleryResize.count !== t.galleryResize.was);
  if (resized.length > 0) {
    console.log(`▌갤러리 장수 조정 — ${resized.length}건`);
    console.log(`  ${w('슬러그', 11)}${w('컬렉션', 18)}${w('필드', 16)}변경`);
    console.log(`  ${'─'.repeat(96)}`);
    for (const t of resized) {
      const r = t.galleryResize;
      console.log(`  ${w(t.slug, 11)}${w(t.collection, 18)}${w(r.field, 16)}${r.was}장 → ${r.count}장`);
    }
    console.log('');
  }

  // ⚠️ 가장 중요한 표 — 실제 업체 사진이 남는지.
  const leftovers = targets
    .map((t) => ({ t, urls: leftoverImageUrls(t) }))
    .filter((x) => x.urls.length > 0);
  const total = leftovers.reduce((n, x) => n + x.urls.length, 0);

  console.log(`▌⚠️ 교체되지 않고 남는 기존 이미지 — ${total}장`);
  if (total === 0) {
    console.log('  없음. 이 문서들의 모든 이미지가 데모 이미지로 교체된다.');
  } else {
    console.log('  아래 URL은 지금 준비된 파일로 덮이지 않는다. 실제 업체 사진이면 심사에 그대로 나간다.');
    console.log('');
    for (const { t, urls } of leftovers) {
      console.log(`  ${w(t.slug, 11)}${w(t.collection, 18)}${t.docId}   ${urls.length}장`);
      for (const u of urls) console.log(`      ${u}`);
    }
  }
  console.log('');
}

/// 필드별 현재값 → 변경값 (--diff). 문서를 다시 읽어 **실제로 달라지는 필드만**
/// 찍는다. 값이 같은 필드는 표에 넣지 않는다 — 무엇이 바뀌는지가 흐려진다.
async function printDiff(targets) {
  const short = (v, n = 62) => {
    if (v === undefined) return '(없음)';
    if (isDelete(v)) return '(필드 삭제)';
    const s = typeof v === 'string' ? v : JSON.stringify(v);
    const oneLine = s.replace(/\n/g, ' ⏎ ');
    return clip(oneLine, n);
  };
  const same = (a, b) => JSON.stringify(a === undefined ? null : a) === JSON.stringify(b === undefined ? null : b);

  console.log('');
  console.log('══════════ 필드별 변경 예정 (현재값 → 변경값) ══════════');
  console.log(TEXT_ONLY ? '  --text-only: 이미지 필드는 계산에서 아예 빠진다.' : '');
  let changedDocs = 0;
  let changedFields = 0;

  for (const t of targets) {
    const current = await restGet(t.collection, t.docId);
    if (!current) { console.log(`  (문서 없음) ${t.collection}/${t.docId}`); continue; }

    const rows = [];
    for (const [k, v] of Object.entries(t.patch)) {
      if (isDelete(v)) {
        if (current[k] !== undefined && current[k] !== null && current[k] !== '') {
          rows.push([k, short(current[k]), '(필드 삭제)']);
        }
        continue;
      }
      if (same(current[k], v)) continue;
      rows.push([k, short(current[k]), short(v)]);
    }
    if (rows.length === 0) continue;

    changedDocs += 1;
    changedFields += rows.length;
    console.log('');
    console.log(`▌${t.slug}  ${t.kind}  ${t.collection}/${t.docId}`);
    if (t.parentName) console.log(`   부모: ${t.parentName}`);
    for (const [k, before, after] of rows) {
      console.log(`   ${w(k, 20)}`);
      console.log(`     현재  ${before}`);
      console.log(`     변경  ${after}`);
    }
  }

  console.log('');
  console.log(`▌변경되는 문서 ${changedDocs}건 / 필드 ${changedFields}개`);
  console.log('   (값이 이미 같은 필드는 위 목록에서 제외했다)');
  console.log('');
}

function printPlan(uid, targets, withMedia) {
  const byCollection = new Map();
  for (const t of targets) {
    if (!byCollection.has(t.collection)) byCollection.set(t.collection, []);
    byCollection.get(t.collection).push(t);
  }

  console.log('');
  console.log('══════════ DRY RUN — Firestore·R2에 아무것도 쓰지 않았다 ══════════');
  console.log(`uid : ${uid}`);
  console.log('');
  console.log('▌도메인별 대상 문서 수');
  console.log('──────────────────────────────────────────────');
  for (const [col, label] of COUNT_COLLECTIONS) {
    const n = (byCollection.get(col) || []).length;
    console.log(`  ${w(label, 14)}${w(col, 18)}${String(n).padStart(4)}건`);
  }
  console.log(`  ${w('합계', 14)}${w('', 18)}${String(targets.length).padStart(4)}건`);
  console.log('');

  for (const [col, label] of COUNT_COLLECTIONS) {
    const list = byCollection.get(col) || [];
    if (list.length === 0) continue;
    console.log(`▌${label} (${col})`);
    console.log(
      `  ${w('슬러그', 11)}${w('문서 ID', 23)}${w('현재 이름', 26)}${w('변경 예정 이름', 26)}${w('배정 지역', 16)}`,
    );
    console.log(`  ${'─'.repeat(96)}`);
    for (const t of list) {
      console.log(
        `  ${w(t.slug, 11)}${w(t.docId, 23)}${w(clip(t.beforeName || '(비어 있음)', 24), 26)}` +
          `${w(t.afterName, 26)}${w(t.region ? `${t.region.label} / ${t.region.district}` : '-', 16)}`,
      );
    }
    console.log('');
  }

  // 파티 시리즈 묶음
  const partyTargets = byCollection.get('parties') || [];
  if (partyTargets.length > 0) {
    const bySlug = new Map();
    for (const t of partyTargets) {
      if (!bySlug.has(t.slug)) bySlug.set(t.slug, []);
      bySlug.get(t.slug).push(t);
    }
    console.log('▌파티 seriesId 묶음 — 같은 슬러그 = 같은 이름 · 같은 지역 · 같은 이미지');
    console.log(`  ${w('슬러그', 11)}${w('이름', 26)}${w('지역', 10)}${w('문서', 7)}seriesId`);
    console.log(`  ${'─'.repeat(96)}`);
    for (const [slug, list] of bySlug) {
      console.log(
        `  ${w(slug, 11)}${w(list[0].afterName, 26)}${w(list[0].region.label, 10)}` +
          `${w(`${list.length}건`, 7)}${list[0].seriesKey}`,
      );
    }
    console.log('');
  }

  // 필요한 이미지
  const files = requiredFiles(targets);
  if (!withMedia) {
    console.log(`▌필요한 이미지 파일 — ${files.length}개`);
    console.log(`  폴더: ${MEDIA_DIR}`);
    console.log(`  확장자: ${MEDIA_EXTS.join(' | ')}`);
    console.log(`  ${w('파일명(확장자 제외)', 30)}${w('용도', 10)}대상`);
    console.log(`  ${'─'.repeat(96)}`);
    for (const f of files) console.log(`  ${w(f.file, 30)}${w(f.role, 10)}${f.kind}`);
    console.log('');
  } else {
    printMediaAudit(targets, files);
  }

  // 동영상 제거 예정
  const videoDocs = targets.filter((t) =>
    Object.entries(t.patch).some(([k, v]) => isDelete(v) && k.toLowerCase().includes('video')));
  if (videoDocs.length > 0) {
    console.log(`▌동영상 필드 제거 예정 — ${videoDocs.length}건`);
    console.log('  1차 범위에서 동영상은 제외다. videoUrl 계열을 지우고 사진 커버로 내린다.');
    console.log('  (--keep-video 를 주면 그대로 두지만, 실제 업체 영상이 남는다.)');
    for (const t of videoDocs) {
      const dropped = Object.entries(t.patch).filter(([, v]) => isDelete(v)).map(([k]) => k);
      console.log(`    ${w(t.slug, 11)}${w(t.collection, 18)}${w(t.docId, 23)}${dropped.join(', ')}`);
    }
    console.log('');
  }
}

function writePlanFiles(uid, targets) {
  ensureOutDir();
  const planPath = path.join(OUT_DIR, 'demo-plan.json');
  fs.writeFileSync(
    planPath,
    JSON.stringify(
      {
        generatedAt: new Date().toISOString(),
        projectId: PROJECT_ID,
        uid,
        keepVideo: KEEP_VIDEO,
        targets: targets.map((t) => ({
          collection: t.collection,
          docId: t.docId,
          slug: t.slug,
          kind: t.kind,
          seriesKey: t.seriesKey || null,
          beforeName: t.beforeName,
          afterName: t.afterName,
          region: t.region ? `${t.region.label} / ${t.region.district}` : null,
          patch: t.patch,
          media: t.media,
          files: (t.files || []).map((f) => f.file),
        })),
        requiredFiles: requiredFiles(targets),
      },
      null,
      2,
    ),
    'utf8',
  );
  console.log(`플랜 저장: ${path.relative(process.cwd(), planPath)}`);
}

// ── 백업 (4단계) ───────────────────────────────────────────────────────────

async function runBackup(uid, targets) {
  ensureOutDir();
  const file = path.join(OUT_DIR, `backup-${stamp()}.json`);
  const docs = [];
  for (const t of targets) {
    const data = await restGet(t.collection, t.docId);
    if (!data) continue;
    if (data.hostId !== uid) {
      throw new Error(`[중단] ${t.collection}/${t.docId} 의 hostId가 UID와 다르다.`);
    }
    docs.push({ collection: t.collection, docId: t.docId, slug: t.slug, data });
  }
  fs.writeFileSync(
    file,
    JSON.stringify({ createdAt: new Date().toISOString(), projectId: PROJECT_ID, uid, docs }, null, 2),
    'utf8',
  );
  console.log(`백업 저장: ${file}  (문서 ${docs.length}건)`);
  console.log('⚠️ 운영 데이터 원문이다 — 커밋하지 말 것(.gitignore 처리되어 있다).');
  return file;
}

function latestBackup() {
  if (!fs.existsSync(OUT_DIR)) return null;
  const files = fs.readdirSync(OUT_DIR).filter((n) => /^backup-.*\.json$/.test(n)).sort();
  return files.length === 0 ? null : path.join(OUT_DIR, files[files.length - 1]);
}

// ── R2 업로드 (5단계) ──────────────────────────────────────────────────────
//
// functions/mediaUploads.js 와 **같은 키 규칙·같은 버킷**을 쓴다:
//   party_images/{uid}/{epochMs}-{nonce}.{ext}
// 그래야 나중에 서버의 정리 로직(contentCleanup.js)이 그대로 동작한다.

function secret(name) {
  if (process.env[name]) return process.env[name].trim();
  try {
    return execSync(
      `gcloud secrets versions access latest --secret=${name} --project=${PROJECT_ID}`,
      { encoding: 'utf8' },
    ).trim();
  } catch (e) {
    throw new Error(`시크릿 ${name} 을 읽지 못했다: ${e.message}`);
  }
}

function r2Config() {
  return {
    accessKeyId: secret('R2_ACCESS_KEY_ID'),
    secretAccessKey: secret('R2_SECRET_ACCESS_KEY'),
    publicBase: secret('R2_PUBLIC_BASE_URL').replace(/\/+$/, ''),
    accountId: secret('CLOUDFLARE_ACCOUNT_ID'),
    bucket: secret('CLOUDFLARE_R2_BUCKET'),
  };
}

const sha256Hex = (v) => crypto.createHash('sha256').update(v).digest('hex');
const hmac = (k, v) => crypto.createHmac('sha256', k).update(v, 'utf8').digest();

function signingKey(secretKey, dateStamp) {
  return hmac(hmac(hmac(hmac(`AWS4${secretKey}`, dateStamp), 'auto'), 's3'), 'aws4_request');
}

const MIME = { jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', webp: 'image/webp' };

/// R2(S3 호환)로 한 건 보낸다. SigV4는 mediaUploads.js 와 같은 방식이다.
function r2Request(cfg, method, key, body, contentType) {
  const host = `${cfg.accountId}.r2.cloudflarestorage.com`;
  const amzDate = new Date().toISOString().replace(/[:-]|\.\d{3}/g, '');
  const dateStamp = amzDate.slice(0, 8);
  const payloadHash = sha256Hex(body || '');
  const canonicalUri = `/${cfg.bucket}/${key.split('/').map(encodeURIComponent).join('/')}`;

  const headerPairs = [];
  if (contentType) headerPairs.push(['content-type', contentType]);
  headerPairs.push(['host', host], ['x-amz-content-sha256', payloadHash], ['x-amz-date', amzDate]);
  headerPairs.sort((a, b) => (a[0] < b[0] ? -1 : 1));

  const canonicalHeaders = headerPairs.map(([k, v]) => `${k}:${v}\n`).join('');
  const signedHeaders = headerPairs.map(([k]) => k).join(';');
  const canonicalRequest =
    `${method}\n${canonicalUri}\n\n${canonicalHeaders}\n${signedHeaders}\n${payloadHash}`;
  const scope = `${dateStamp}/auto/s3/aws4_request`;
  const stringToSign = `AWS4-HMAC-SHA256\n${amzDate}\n${scope}\n${sha256Hex(canonicalRequest)}`;
  const signature = crypto
    .createHmac('sha256', signingKey(cfg.secretAccessKey, dateStamp))
    .update(stringToSign, 'utf8')
    .digest('hex');

  const headers = Object.fromEntries(headerPairs.filter(([k]) => k !== 'host'));
  headers.authorization =
    `AWS4-HMAC-SHA256 Credential=${cfg.accessKeyId}/${scope}, ` +
    `SignedHeaders=${signedHeaders}, Signature=${signature}`;
  if (body) headers['content-length'] = body.length;

  return new Promise((resolve, reject) => {
    const req = https.request({ method, host, path: canonicalUri, headers }, (res) => {
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) resolve();
        else reject(new Error(`R2 ${method} ${res.statusCode}: ${Buffer.concat(chunks).toString()}`));
      });
    });
    req.on('error', reject);
    if (body) req.end(body);
    else req.end();
  });
}

async function runMediaUpload(uid, targets) {
  const cfg = r2Config();
  const files = requiredFiles(targets);
  const map = {};
  let uploaded = 0;
  let skipped = 0;
  for (const f of files) {
    const local = findMediaFile(f.file);
    if (!local) {
      skipped += 1;
      console.log(`  SKIP    ${f.file} (파일 없음 — 기존 이미지 유지)`);
      continue;
    }
    const ext = path.extname(local).slice(1).toLowerCase();
    const body = fs.readFileSync(local);
    const key = `party_images/${uid}/${Date.now()}-${crypto.randomBytes(6).toString('hex')}.${ext}`;
    await r2Request(cfg, 'PUT', key, body, MIME[ext] || 'image/jpeg');
    map[f.file] = `${cfg.publicBase}/${key}`;
    uploaded += 1;
    console.log(`  UPLOAD  ${f.file} → ${map[f.file]}`);
  }
  ensureOutDir();
  const out = path.join(OUT_DIR, 'media-map.json');
  fs.writeFileSync(out, JSON.stringify({ uid, uploadedAt: new Date().toISOString(), map }, null, 2), 'utf8');
  console.log(`\n업로드 ${uploaded}개 / 건너뜀 ${skipped}개 — ${out}`);
  console.log('Firestore는 아직 그대로다. 다음: --apply');
}

function loadMediaMap() {
  const p = path.join(OUT_DIR, 'media-map.json');
  if (!fs.existsSync(p)) return {};
  return JSON.parse(fs.readFileSync(p, 'utf8')).map || {};
}

// ── 적용 (6단계) ───────────────────────────────────────────────────────────

/// 미디어 맵을 패치에 얹는다. 배열 원소 경로(`images[0]`)는 배열을 통째로 다시
/// 만들어 넣는다 — Firestore는 인덱스 단위 부분 갱신을 지원하지 않는다.
function applyMediaToPatch(target, current, mediaMap, urlRemap) {
  const patch = {};
  const arrays = new Map();
  for (const m of target.media) {
    const newUrl = mediaMap[m.file];
    if (!newUrl) continue;
    if (m.current) urlRemap.set(m.current, newUrl);

    const idx = m.field.match(/^([A-Za-z]+)\[(\d+)\]$/);
    if (idx) {
      const [, field, i] = idx;
      if (!arrays.has(field)) arrays.set(field, [...arr(current[field])]);
      arrays.get(field)[Number(i)] = newUrl;
      continue;
    }
    if (m.field.startsWith('detailBlocks.')) continue; // 아래에서 블록 배열째 처리
    patch[m.field] = newUrl;
  }
  for (const [field, list] of arrays) patch[field] = list;

  // --resize-galleries: 배열 길이를 준비된 파일 수에 맞춘다. 넘치는 옛 URL은
  // 배열에서 빠진다(문서·R2 파일은 그대로 남는다 — 8단계에서만 지운다).
  if (target.galleryResize && !TEXT_ONLY) {
    const { field, count } = target.galleryResize;
    const base = arrays.get(field) || [...arr(current[field])];
    patch[field] = base.slice(0, count);
  }

  // 파티는 images / imageUrls 두 배열을 같은 값으로 유지한다(앱과 동일).
  if (target.collection === 'parties' && patch.images) patch.imageUrls = patch.images;
  return patch;
}

/// URL을 키로 쓰는 크롭 맵을 새 URL로 옮긴다. 옮길 곳이 없는 키는 버린다
/// (앱이 값 없는 옛 문서를 중앙 정렬로 다루므로 화면이 깨지지 않는다).
function remapCrops(current, urlRemap) {
  const crops = current.basicCardPhotoCrops;
  if (!crops || typeof crops !== 'object' || urlRemap.size === 0) return null;
  const next = {};
  for (const [k, v] of Object.entries(crops)) {
    const nk = urlRemap.get(k);
    if (nk) next[nk] = v;
  }
  return next;
}

async function runApply(uid, targets) {
  const backup = latestBackup();
  if (!backup) {
    console.error('[중단] 백업이 없다. 먼저 실행할 것:');
    console.error(`  node scripts/demoContentRewrite.js --uid ${uid} --apply --backup-only`);
    process.exit(1);
  }
  const backupUid = JSON.parse(fs.readFileSync(backup, 'utf8')).uid;
  if (backupUid !== uid) {
    console.error(`[중단] 백업(${backup})의 uid가 다르다: ${backupUid}`);
    process.exit(1);
  }
  console.log(`백업 확인: ${backup}`);

  // --text-only 면 미디어 맵을 아예 읽지 않는다 — 이미지 필드는 손대지 않는다.
  const mediaMap = TEXT_ONLY ? {} : loadMediaMap();
  console.log(TEXT_ONLY
    ? '미디어 맵: 무시(--text-only) — 이미지 필드는 건드리지 않는다'
    : `미디어 맵: ${Object.keys(mediaMap).length}개`);
  if (!TEXT_ONLY && Object.keys(mediaMap).length === 0) {
    console.log('  (이미지 없이 텍스트·위치만 반영한다. 이미지는 나중에 다시 --apply 하면 된다.)');
  }
  console.log('');

  const applied = [];
  let skipped = 0;

  for (const t of targets) {
    const current = await restGet(t.collection, t.docId);
    if (!current) {
      console.log(`  SKIP ${t.collection}/${t.docId} — 문서 없음`);
      skipped += 1;
      continue;
    }

    // ⚠️ 쓰기 직전 소유자 재확인. 계획 수립 이후 바뀌었을 수 있다.
    if (current.hostId !== uid) {
      console.log(`  SKIP ${t.collection}/${t.docId} — hostId 불일치(${current.hostId})`);
      skipped += 1;
      continue;
    }

    const urlRemap = new Map();
    const patch = { ...t.patch, ...applyMediaToPatch(t, current, mediaMap, urlRemap) };

    // 상세 블록 안의 이미지 URL도 같은 맵으로 갈아 끼운다.
    if (Array.isArray(patch.detailBlocks) && urlRemap.size > 0) {
      patch.detailBlocks = patch.detailBlocks.map((b) => {
        if (!b || typeof b !== 'object') return b;
        const nb = { ...b };
        if (nb.imageUrl && urlRemap.has(nb.imageUrl)) nb.imageUrl = urlRemap.get(nb.imageUrl);
        if (Array.isArray(nb.items)) {
          nb.items = nb.items.map((it) =>
            it && it.imageUrl && urlRemap.has(it.imageUrl)
              ? { ...it, imageUrl: urlRemap.get(it.imageUrl) }
              : it);
        }
        return nb;
      });
    }

    // 커버 사진이 바뀌면 썸네일도 같은 사진으로 맞춘다 — 동영상을 걷어낸 뒤
    // 옛 영상 썸네일이 카드에 남는 것을 막는다.
    if (patch.coverImageUrl && !KEEP_VIDEO) patch.coverThumbnailUrl = patch.coverImageUrl;

    const crops = remapCrops(current, urlRemap);
    if (crops) patch.basicCardPhotoCrops = crops;

    patch.updatedAt = nowTs();
    assertNoFrozen(t.collection, t.docId, patch);

    // 되돌릴 값을 먼저 챙긴다(복원은 이 before만 쓴다).
    const before = {};
    for (const k of Object.keys(patch)) {
      before[k] = Object.prototype.hasOwnProperty.call(current, k) ? current[k] : ABSENT;
    }

    await restPatch(t.collection, t.docId, patch);
    applied.push({ collection: t.collection, docId: t.docId, slug: t.slug, before });
    console.log(`  OK   ${w(t.collection, 18)}${w(t.docId, 23)}${clip(t.beforeName || '(비어 있음)', 20)} → ${t.afterName}`);
  }

  ensureOutDir();
  const out = path.join(OUT_DIR, `applied-${stamp()}.json`);
  fs.writeFileSync(
    out,
    JSON.stringify({ appliedAt: new Date().toISOString(), uid, backup, applied }, null, 2),
    'utf8',
  );
  console.log(`\n적용 ${applied.length}건 / 건너뜀 ${skipped}건 — ${out}`);
  console.log('이제 앱에서 눈으로 확인할 것. 확인 전에는 옛 이미지를 지우지 않는다.');
}

// ── 옛 이미지 삭제 (8단계) ─────────────────────────────────────────────────

async function runCleanupOldMedia(uid, targets) {
  const mediaMap = loadMediaMap();
  if (Object.keys(mediaMap).length === 0) {
    console.error('[중단] media-map.json 이 없다. 지울 대상을 특정할 수 없다.');
    process.exit(1);
  }
  if (!FLAG('yes-really')) {
    console.error('[중단] 되돌릴 수 없는 삭제다.');
    console.error('        앱에서 새 이미지가 제대로 보이는 것을 확인했다면 --yes-really 를 함께 줄 것.');
    process.exit(1);
  }
  const cfg = r2Config();
  const olds = new Set();
  for (const t of targets) {
    for (const m of t.media) {
      if (mediaMap[m.file] && m.current && m.current !== mediaMap[m.file]) olds.add(m.current);
    }
  }
  console.log(`삭제 대상 옛 이미지 ${olds.size}개`);
  for (const url of olds) {
    if (!url.startsWith(`${cfg.publicBase}/`)) {
      console.log(`  SKIP   (다른 호스트) ${url}`);
      continue;
    }
    const key = url.slice(cfg.publicBase.length + 1);
    // ⚠️ 내 uid 폴더 밖은 절대 지우지 않는다.
    if (!key.startsWith(`party_images/${uid}/`) && !key.startsWith(`party_images/detail/${uid}/`)) {
      console.log(`  SKIP   (내 폴더가 아님) ${key}`);
      continue;
    }
    await r2Request(cfg, 'DELETE', key, null, null);
    console.log(`  DELETE ${key}`);
  }
  console.log('완료.');
}

// ── main ───────────────────────────────────────────────────────────────────

async function main() {
  if (FLAG('whoami')) {
    await runWhoami();
    return;
  }

  const uid = OPT('uid');
  if (!uid) {
    console.error('');
    console.error('[중단] --uid 가 없다. 이메일·이름만으로는 절대 대상을 고르지 않는다.');
    console.error('');
    console.error('  1) uid 확인 : node scripts/demoContentRewrite.js --whoami --email you@example.com');
    console.error('  2) 드라이런 : node scripts/demoContentRewrite.js --uid <UID>');
    console.error('');
    process.exit(1);
  }

  // --email 을 함께 줬으면 대조한다(오타 방어).
  const email = OPT('email');
  if (email) {
    const u = await admin.auth().getUserByEmail(email);
    if (u.uid !== uid) {
      console.error(`[중단] --uid(${uid}) 와 --email(${email} → ${u.uid}) 이 다르다.`);
      process.exit(1);
    }
  }

  const targets = await buildPlan(uid);
  if (RESIZE_GALLERIES) resizeGalleries(targets);

  if (!APPLY) {
    if (SHOW_DIFF) await printDiff(targets);
    else printPlan(uid, targets, FLAG('with-media'));
    writePlanFiles(uid, targets);
    console.log('');
    console.log('드라이런이라 Firestore·R2에 아무것도 쓰지 않았다.');
    console.log('');
    return;
  }

  if (FLAG('backup-only')) { await runBackup(uid, targets); return; }
  if (FLAG('media-only')) { await runMediaUpload(uid, targets); return; }
  if (FLAG('cleanup-old-media')) { await runCleanupOldMedia(uid, targets); return; }
  await runApply(uid, targets);
}

// demoContentRestore.js 가 REST 계층을 재사용한다 — 직접 실행할 때만 main().
module.exports = {
  PROJECT_ID,
  FS_BASE,
  OUT_DIR,
  ABSENT,
  DELETE,
  isDelete,
  getAccessToken,
  fsFetch,
  decodeValue,
  decodeFields,
  encodeValue,
  nowTs,
  restGet,
  restPatch,
  w,
  clip,
  // 부분 교체 스크립트가 같은 업로드 경로를 쓰도록 열어 둔다 — 키 규칙이
  // 갈라지면 나중에 정리(contentCleanup)가 못 찾는다.
  r2Config,
  r2Request,
  MIME,
};

if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((e) => {
      console.error('');
      console.error('실패:', e.message);
      if (process.env.DEBUG) console.error(e.stack);
      process.exit(1);
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// 관리자 판매 통계 — **문서를 읽어 넘기기만** 하는 콜러블.
//
// ⚠ 이 파일에는 매출 계산이 **하나도 없다.** 일부러 그렇게 두었다.
//
// 호스트 앱(party_app)의 판매 통계와 관리자 웹(admin_app)의 판매 통계는 같은
// 신청/예약 문서를 보고 **반드시 같은 숫자**를 내야 한다. 여기서 합계를 내면
// 계산이 JS와 Dart 두 벌이 되고, 한쪽만 고쳐지는 순간 "호스트 화면은 32만원인데
// 관리자는 29만원"이 된다. 그래서 서버는 **읽기만** 담당하고, 금액 정본 선택·
// 매출 포함 판정·일자별 집계는 전부 packages/partychu_sales(Dart) 한 곳에서만
// 일어난다. 관리자 웹은 아래가 내려준 맵을 그대로 `SalesEntryMapper.fromDocument`에
// 넣는다 — 호스트 앱이 `doc.data()`를 넣는 것과 같은 입력이다.
//
// **그래서 필드를 고를 때는 "매퍼가 읽는 것"을 기준으로 한다**(FIELDS 참고).
// 매퍼가 새 필드를 보게 되면 여기 목록에도 더해야 한다.
//
// ── 왜 콜러블인가 ───────────────────────────────────────────────────────────
// firestore.rules는 이 컬렉션들에 `isAdmin()` 읽기를 이미 허용하므로 관리자
// 웹이 직접 쿼리할 수도 있다. 그러지 않는 이유는 두 가지다.
//   ① 전체 통계는 **모든 호스트의 모든 예약**을 봐야 해서, 클라이언트 직접
//      조회로 두면 브라우저가 전 사용자 데이터를 통째로 내려받는다.
//   ② 파티명(parties)과 판매자 닉네임(users)을 붙이려면 문서를 더 읽어야 하는데,
//      users는 규칙상 본인·관리자만 읽을 수 있어 N+1이 그대로 노출된다.
// 서버에서 한 번에 묶어 내리면 왕복도 읽기도 줄고, 권한 검사도 한 곳이 된다.
//
// 권한은 기존 관리자 콜러블들과 **같은 근거**를 쓴다 — users/{uid}.role ==
// 'admin'(firestore.rules의 isAdmin()과 동일). 일반 사용자는 여기 닿지 못한다.
// ─────────────────────────────────────────────────────────────────────────────

const admin = require('firebase-admin');
const { onCall, HttpsError } = require('firebase-functions/v2/https');

const REGION = 'asia-northeast3';

/** 한 번에 내려주는 문서 수 상한. 넘으면 truncated로 알린다. */
const MAX_DOCS_PER_SOURCE = 5000;

/** 파티명을 붙일 때 한 번에 읽는 파티 문서 수 상한. */
const MAX_PARTY_LOOKUPS = 1000;

/**
 * 읽을 컬렉션과 **날짜 축 필드**.
 *
 * 날짜 축이 소스마다 다르다(신청은 appliedAt, 예약·주문은 createdAt). Dart
 * 매퍼도 같은 규칙을 쓴다(SalesEntryMapper._dateFieldOf) — 둘이 어긋나면
 * 기간 필터에 걸리는 문서와 집계되는 문서가 달라진다.
 */
const SOURCES = [
  { key: 'applications', dateField: 'appliedAt', group: true, sellerField: 'hostId' },
  { key: 'placeVisitReservations', dateField: 'createdAt', group: false, sellerField: 'hostId' },
  { key: 'placeProductOrders', dateField: 'createdAt', group: false, sellerField: 'hostId' },
  { key: 'placeReservationGroups', dateField: 'createdAt', group: false, sellerField: 'hostId' },
  { key: 'packageBookings', dateField: 'createdAt', group: false, sellerField: 'hostId' },
  // 파티샵 주문 — **판매자 필드가 이것만 sellerId다**(shopOrders.js가 주문에
  // `sellerId: shop.hostId`로 적는다). Dart 쪽 SalesSource.shopOrder.sellerField와
  // 같은 값이어야 한다 — 어긋나면 판매자 필터가 전부 걸러내 0건이 된다.
  { key: 'orders', dateField: 'createdAt', group: false, sellerField: 'sellerId' },
];

/**
 * 매퍼(packages/partychu_sales/lib/src/sales_entry_mapper.dart)가 읽는 필드
 * 전부의 합집합. 소스마다 갈라 적지 않고 한 벌로 두는 이유는, 매퍼가 어느
 * 필드를 어느 소스에서 읽는지를 **Dart 한 곳에서만** 정하게 하기 위해서다.
 *
 * 개인정보(requesterName/requesterPhone/uid 등)는 통계에 필요 없으므로 아예
 * 내려보내지 않는다 — 관리자라도 필요 없는 것은 받지 않는 편이 안전하다.
 * 파티샵 주문의 `buyerId`/`buyerName`/`sellerName`도 같은 이유로 빠져 있다.
 */
const FIELDS = [
  // 공통
  'hostId', 'status', 'payment', 'amounts', 'refundStatus', 'refundAmount',
  'placeName', 'partyTitle',
  // 파티 신청
  'appliedFee', 'appliedAt', 'source', 'partyId', 'applicationType',
  // 방문 예약
  'depositAmount', 'visitAt',
  // 상품 주문
  'totalPrice', 'quantity', 'productName', 'paidAt',
  // 장소대여·콤보
  'peopleCount', 'createdAt', 'useStartAt', 'packageName', 'roomName',
  // 파티샵 주문 — 금액 정본은 `amount`(= subtotal - couponDiscount)다.
  // `quantity`·`productName`·`createdAt`은 위 상품 주문 줄과 공유한다.
  'sellerId', 'amount', 'shopName', 'selectedOptionName',
];

/** 관리자 판정 — adminChatViewer.requireAdmin과 같은 근거(users/{uid}.role). */
async function requireAdmin(request) {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
  }
  const db = admin.firestore();
  const callerSnap = await db.collection('users').doc(request.auth.uid).get();
  if (callerSnap.data()?.role !== 'admin') {
    throw new HttpsError('permission-denied', '관리자만 사용할 수 있습니다.');
  }
  return { db, callerUid: request.auth.uid };
}

/**
 * Firestore 값을 **Dart 매퍼가 읽을 수 있는 모양**으로 바꾼다.
 *
 * Timestamp는 epoch ms로 편다 — 매퍼는 cloud_firestore를 모르고(관리자 웹은
 * 콜러블 응답만 본다), 콜러블 JSON에는 Timestamp를 실을 수도 없다. 매퍼의
 * `_dateOf`가 숫자를 ms로 읽으므로 호스트 앱이 넘기는 Timestamp와 같은 날짜가
 * 나온다.
 */
function plain(value) {
  if (value === null || value === undefined) return null;
  if (typeof value.toDate === 'function') return value.toDate().getTime();
  if (Array.isArray(value)) return value.map(plain);
  if (typeof value === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(value)) out[k] = plain(v);
    return out;
  }
  return value;
}

/** 문서 하나에서 FIELDS만 골라 평평하게 만든다. */
function pick(data) {
  const out = {};
  for (const f of FIELDS) {
    if (data[f] !== undefined) out[f] = plain(data[f]);
  }
  return out;
}

/**
 * 한 소스를 기간으로 좁혀 읽는다.
 *
 * 날짜 필드 **단일 범위 조건**만 건다 — Firestore가 모든 필드에 자동으로
 * 만들어 두는 단일 필드 색인(컬렉션 그룹 범위 포함)으로 돌아가므로 색인을
 * 새로 배포할 필요가 없다. 특정 판매자만 볼 때도 여기에 hostId 등호를 더하지
 * 않고 **메모리에서 거른다**: (hostId, createdAt) 복합 색인이 아직 없어서
 * 조건을 더하면 색인 배포가 필요해지기 때문이다.
 * (applications만 (hostId, appliedAt) 색인이 이미 있어 쿼리에서 좁힌다.)
 */
async function readSource(db, source, { sinceMs, untilMs, hostId }) {
  const base = source.group
    ? db.collectionGroup(source.key)
    : db.collection(source.key);

  let query = base;
  if (source.key === 'applications' && hostId) {
    query = query.where('hostId', '==', hostId);
  }
  query = query
    .where(source.dateField, '>=', admin.firestore.Timestamp.fromMillis(sinceMs))
    .where(source.dateField, '<', admin.firestore.Timestamp.fromMillis(untilMs))
    .limit(MAX_DOCS_PER_SOURCE + 1);

  const snap = await query.get();
  const truncated = snap.docs.length > MAX_DOCS_PER_SOURCE;
  const docs = truncated ? snap.docs.slice(0, MAX_DOCS_PER_SOURCE) : snap.docs;

  const rows = [];
  for (const doc of docs) {
    const data = doc.data();
    if (hostId && data[source.sellerField] !== hostId) continue;
    rows.push({
      collection: source.key,
      // 파티 신청은 문서 id가 신청자 uid라 파티가 다르면 겹친다 —
      // 호스트 앱과 같은 방식으로 partyId를 앞에 붙여 유일하게 만든다.
      id: source.key === 'applications'
        ? `${data.partyId || ''}_${doc.id}`
        : doc.id,
      data: pick(data),
    });
  }
  return { rows, truncated };
}

/**
 * 파티 신청 줄에 파티명을 붙인다. 신청 문서에는 파티명이 없기 때문
 * (partyCapacity.js가 partyId만 적는다). 읽기는 **신청 수가 아니라 파티 수**
 * 만큼만 늘어난다.
 */
async function attachPartyTitles(db, rows) {
  const ids = new Set();
  for (const r of rows) {
    if (r.collection !== 'applications') continue;
    // 콤보 신청은 매퍼가 버리므로 이름을 찾을 필요가 없다.
    if (r.data.source === 'combo') continue;
    if (r.data.partyId) ids.add(r.data.partyId);
  }
  if (ids.size === 0) return;

  const list = [...ids].slice(0, MAX_PARTY_LOOKUPS);
  const refs = list.map((id) => db.collection('parties').doc(id));
  const snaps = await db.getAll(...refs);
  const titles = new Map();
  snaps.forEach((s, i) => {
    const title = (s.exists && s.data().title) || '';
    titles.set(list[i], title.trim() || (s.exists ? '(이름 없는 파티)' : '(삭제된 파티)'));
  });

  for (const r of rows) {
    if (r.collection !== 'applications') continue;
    const t = titles.get(r.data.partyId);
    if (t) r.contentTitle = t;
  }
}

/**
 * 판매자 표에 붙일 닉네임/실명. users는 규칙상 관리자만 읽을 수 있어 여기서
 * 함께 내려준다(관리자 웹이 판매자마다 따로 읽지 않게).
 */
async function loadHostIdentities(db, rows) {
  // 판매자 uid가 든 필드는 소스마다 다르다(파티샵만 sellerId) — 줄의 컬렉션으로
  // 되짚어 고른다. hostId만 보면 파티샵 판매자가 이름 없이 표시된다.
  const sellerFieldOf = new Map(SOURCES.map((s) => [s.key, s.sellerField]));
  const ids = [
    ...new Set(
      rows
        .map((r) => r.data[sellerFieldOf.get(r.collection) || 'hostId'])
        .filter(Boolean),
    ),
  ];
  if (ids.length === 0) return {};

  const out = {};
  // getAll은 인자 개수 제한이 있어 넉넉히 잘라 나눠 부른다.
  const CHUNK = 300;
  for (let i = 0; i < ids.length; i += CHUNK) {
    const slice = ids.slice(i, i + CHUNK);
    const snaps = await db.getAll(
      ...slice.map((id) => db.collection('users').doc(id)),
    );
    snaps.forEach((s, j) => {
      const d = s.exists ? s.data() : null;
      out[slice[j]] = {
        nickname: (d && d.nickname) || null,
        name: (d && d.name) || null,
        // 테스트 계정은 관리자 화면에서 걸러 볼 수 있어야 한다.
        isTestAccount: !!(d && d.isTestAccount),
      };
    });
  }
  return out;
}

/**
 * 관리자 판매 통계 원자료.
 *
 * @param sinceMs  조회 시작(포함). 필수.
 * @param untilMs  조회 끝(**미포함**). 없으면 지금.
 * @param hostId   특정 판매자만. 없으면 전체.
 *
 * @returns { rows, hosts, truncated, truncatedSources }
 *   rows  : [{ collection, id, contentTitle?, data }] — 매퍼 입력 그대로
 *   hosts : { uid: { nickname, name, isTestAccount } }
 */
exports.adminGetSalesEntries = onCall({ region: REGION }, async (request) => {
  const { db } = await requireAdmin(request);

  const { sinceMs, untilMs, hostId } = request.data || {};
  if (typeof sinceMs !== 'number' || !Number.isFinite(sinceMs)) {
    throw new HttpsError('invalid-argument', 'sinceMs가 필요합니다.');
  }
  const until =
    typeof untilMs === 'number' && Number.isFinite(untilMs)
      ? untilMs
      : Date.now();
  if (until <= sinceMs) {
    throw new HttpsError('invalid-argument', '조회 기간이 올바르지 않습니다.');
  }
  if (hostId !== undefined && hostId !== null && typeof hostId !== 'string') {
    throw new HttpsError('invalid-argument', 'hostId가 올바르지 않습니다.');
  }

  const results = await Promise.all(
    SOURCES.map((s) =>
      readSource(db, s, { sinceMs, untilMs: until, hostId: hostId || null }),
    ),
  );

  const rows = results.flatMap((r) => r.rows);
  const truncatedSources = SOURCES.filter((_, i) => results[i].truncated).map(
    (s) => s.key,
  );

  await attachPartyTitles(db, rows);
  const hosts = await loadHostIdentities(db, rows);

  return {
    rows,
    hosts,
    truncated: truncatedSources.length > 0,
    truncatedSources,
  };
});

// 자기검증용 export — adminSalesStats.selfcheck.js가 쓴다.
// (다른 순수 헬퍼 모듈과 달리 이 파일은 콜러블을 export하므로, 테스트용 표면은
//  __test 하나로 모아 배포 대상과 섞이지 않게 한다 — socialAuth.js와 같은 방식.)
module.exports.__test = { SOURCES, FIELDS };

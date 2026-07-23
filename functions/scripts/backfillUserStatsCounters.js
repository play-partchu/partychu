// 1회성 백필 스크립트 — userStats의 활동 수치 카운터(등록한 파티/플레이스/
// 상품/크루, 예약·구매, 결제·환불 누적액, 신청·참여 수)를 원본 컬렉션에서
// 다시 세어 정확한 값으로 덮어쓴다. backfillMemberActivity.js와 동일한
// 스타일로 로컬에서 직접 실행한다(gcloud 로그인 계정의 자격증명을 그대로
// 사용, 배포되는 Cloud Function 아님).
//
// 왜 필요한가
//   memberManagement.js/index.js의 onPartyCreated 등 트리거는 2026-07-19에야
//   배포됐다(gcloud functions describe onPartyCreated 로 확인). 그 이전에
//   이미 파티/플레이스/상품/크루를 등록했거나 예약·신청 이력이 있던 회원은
//   트리거가 존재하지 않던 시점의 활동이라 userStats에 전혀 반영되지 않았고,
//   backfillMemberActivity.js는 isHost/hostSince/activityRoles/accountStatus만
//   채울 뿐 이 수치 카운터는 건드리지 않아 격차가 그대로 남아 있다(예:
//   uid ws3COMBLLXPlI4IyhLnwtGF1evS2 — 2026-07-17에 파티 3건을 만들었지만
//   userStats.totalPartiesCreated 필드 자체가 없음, 실제 확인함).
//
// 원칙
//   - 카운터는 increment가 아니라 "원본을 다시 센 값으로 SET"한다 — 트리거가
//     실시간으로 이미 정확히 반영해온 회원도 다시 실행하면 같은 값이 나오므로
//     몇 번을 다시 돌려도 안전하다(idempotent). increment를 쓰면 재실행마다
//     중복 가산되어 위험하다.
//   - updateMask로 이 스크립트가 다루는 필드만 지정해서 쓴다 — 다른 필드
//     (totalAppOpens, totalPartyViews, favoriteRegion 등 애널리틱스/신청
//     트리거가 채우는 값)는 절대 건드리지 않는다.
//   - 신청 상태 카운터(totalApplications/totalConfirmed/totalAttended/
//     totalCancelled/totalRejected/totalNoShows)는 상태 전이를 replay하지
//     않고 "현재 상태 스냅샷"만 센다 — index.js의 onApplicationStatusWrite를
//     보면 'applied' 카운터는 문서 생성 시 1회만 +1되고 이후 상태가 바뀌어도
//     감소하지 않지만, 그 외 상태 카운터는 이전 상태 -1 + 새 상태 +1이라
//     "현재 상태"만 카운트하면 실시간 트리거가 누적해온 값과 정확히 같다.
//
// 데이터 출처(전부 읽기 전용 조회)
//   - parties.hostId                              → totalPartiesCreated
//   - places.hostId                                → totalPlacesCreated
//   - partyShops/*/products.hostId (collectionGroup) → totalProductsRegistered
//   - crews.hostId                                 → totalCrewPostings
//   - orders.buyerId / .sellerId                   → totalProductPurchases / totalProductSales
//   - placeReservationGroups(status=='confirmed').requesterId/.hostId/.totalPrice
//       → totalPlaceReservationsAsGuest / totalPlaceReservationsAsHost / cumulativePaymentAmount
//   - packageBookings(status=='confirmed').requesterId/.hostId/.totalPrice
//       → totalPackageBookingsAsGuest / totalPackageBookingsAsHost / cumulativePaymentAmount
//   - packageBookings(status=='cancelled', refundAmount>0).hostId/.refundAmount
//       → cumulativeRefundAmount
//   - applications(collectionGroup).uid/.status    → totalApplications(전체 건수) /
//       totalConfirmed / totalAttended / totalCancelled / totalRejected / totalNoShows
//       (각 현재 status 건수)
//
// 실행 전 준비:
//   gcloud auth login   (아직 로그인 안 했다면 — 프로젝트 소유자/편집자 권한 필요)
//
// 실행:
//   cd functions
//   node scripts/backfillUserStatsCounters.js --dry-run   → 아무것도 쓰지 않고
//                                                             몇 명이 바뀔지만 미리 확인
//   node scripts/backfillUserStatsCounters.js [--uid=<uid>]  → 실제로 반영
//                                                             (--uid로 특정 회원 1명만 제한 가능)
//
// 이 파일은 작성만 되어 있고, 사용자 승인 전에는 실행하지 않는다.

const { execSync } = require('child_process');

const PROJECT_ID = 'partychu-30c24';
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;
const DRY_RUN = process.argv.includes('--dry-run');
const ONLY_UID = (process.argv.find((a) => a.startsWith('--uid=')) || '').split('=')[1] || null;
const PAGE_SIZE = 300;

function getAccessToken() {
  return execSync('gcloud auth print-access-token', { encoding: 'utf8' }).trim();
}

async function apiFetch(url, token, options = {}) {
  const res = await fetch(url, {
    ...options,
    headers: {
      Authorization: `Bearer ${token}`,
      'x-goog-user-project': PROJECT_ID,
      'Content-Type': 'application/json',
      ...(options.headers || {}),
    },
  });
  const body = await res.json();
  if (!res.ok) throw new Error(`${url} -> ${res.status}: ${JSON.stringify(body)}`);
  return body;
}

async function* iterateCollection(collectionId, { allDescendants = false, selectFields = [], token }) {
  let cursorName = null;
  while (true) {
    const structuredQuery = {
      from: [{ collectionId, allDescendants }],
      orderBy: [{ field: { fieldPath: '__name__' }, direction: 'ASCENDING' }],
      limit: PAGE_SIZE,
    };
    if (selectFields.length > 0) {
      structuredQuery.select = { fields: selectFields.map((f) => ({ fieldPath: f })) };
    }
    if (cursorName) {
      structuredQuery.startAt = { values: [{ referenceValue: cursorName }], before: false };
    }
    const body = await apiFetch(`${BASE}:runQuery`, token, {
      method: 'POST',
      body: JSON.stringify({ structuredQuery }),
    });
    const docs = (body || []).filter((r) => r.document).map((r) => r.document);
    if (docs.length === 0) break;
    for (const doc of docs) yield doc;
    if (docs.length < PAGE_SIZE) break;
    cursorName = docs[docs.length - 1].name;
  }
}

function fieldValue(doc, name) {
  const f = doc.fields?.[name];
  if (!f) return undefined;
  if ('stringValue' in f) return f.stringValue;
  if ('booleanValue' in f) return f.booleanValue;
  if ('timestampValue' in f) return f.timestampValue;
  if ('integerValue' in f) return Number(f.integerValue);
  if ('doubleValue' in f) return Number(f.doubleValue);
  return undefined;
}

// uid -> { field -> number } 누적용 헬퍼
function bump(map, uid, field, delta = 1) {
  if (!uid) return;
  if (!map.has(uid)) map.set(uid, {});
  const entry = map.get(uid);
  entry[field] = (entry[field] || 0) + delta;
}

// ── 이 스크립트가 다루는 필드만 updateMask로 지정해 정확한 값으로 SET ──────
async function applyCounterPatch(uid, counters, token) {
  const keys = Object.keys(counters);
  if (keys.length === 0) return;
  const fields = {};
  for (const key of keys) {
    const value = counters[key];
    fields[key] = Number.isInteger(value) ? { integerValue: String(value) } : { doubleValue: value };
  }
  fields.updatedAt = { timestampValue: new Date().toISOString() };
  const mask = [...keys, 'updatedAt'].map((k) => `updateMask.fieldPaths=${encodeURIComponent(k)}`).join('&');
  await apiFetch(`${BASE}/userStats/${uid}?${mask}`, token, {
    method: 'PATCH',
    body: JSON.stringify({ fields }),
  });
}

async function main() {
  const token = getAccessToken();
  console.log(DRY_RUN ? '=== DRY RUN — 실제로는 아무것도 쓰지 않습니다 ===' : '=== 실제 반영 모드 ===');
  if (ONLY_UID) console.log(`(--uid=${ONLY_UID} 로 이 회원 1명만 대상)`);

  const counters = new Map(); // uid -> { field -> number }

  console.log('[1/9] parties 스캔 중...');
  let n = 0;
  for await (const doc of iterateCollection('parties', { selectFields: ['hostId'], token })) {
    bump(counters, fieldValue(doc, 'hostId'), 'totalPartiesCreated');
    n++;
  }
  console.log(`  파티 ${n}건`);

  console.log('[2/9] places 스캔 중...');
  n = 0;
  for await (const doc of iterateCollection('places', { selectFields: ['hostId'], token })) {
    bump(counters, fieldValue(doc, 'hostId'), 'totalPlacesCreated');
    n++;
  }
  console.log(`  플레이스 ${n}건`);

  console.log('[3/9] partyShops/*/products 스캔 중...');
  n = 0;
  for await (const doc of iterateCollection('products', { allDescendants: true, selectFields: ['hostId'], token })) {
    bump(counters, fieldValue(doc, 'hostId'), 'totalProductsRegistered');
    n++;
  }
  console.log(`  상품 ${n}건`);

  console.log('[4/9] crews 스캔 중...');
  n = 0;
  for await (const doc of iterateCollection('crews', { selectFields: ['hostId'], token })) {
    bump(counters, fieldValue(doc, 'hostId'), 'totalCrewPostings');
    n++;
  }
  console.log(`  크루 공고 ${n}건`);

  console.log('[5/9] orders 스캔 중...');
  n = 0;
  for await (const doc of iterateCollection('orders', { selectFields: ['buyerId', 'sellerId'], token })) {
    bump(counters, fieldValue(doc, 'buyerId'), 'totalProductPurchases');
    bump(counters, fieldValue(doc, 'sellerId'), 'totalProductSales');
    n++;
  }
  console.log(`  주문 ${n}건`);

  console.log('[6/9] placeReservationGroups 스캔 중...');
  n = 0;
  let confirmedReservations = 0;
  for await (const doc of iterateCollection('placeReservationGroups', {
    selectFields: ['status', 'requesterId', 'hostId', 'totalPrice'],
    token,
  })) {
    n++;
    if (fieldValue(doc, 'status') !== 'confirmed') continue;
    confirmedReservations++;
    bump(counters, fieldValue(doc, 'requesterId'), 'totalPlaceReservationsAsGuest');
    const hostId = fieldValue(doc, 'hostId');
    bump(counters, hostId, 'totalPlaceReservationsAsHost');
    bump(counters, hostId, 'cumulativePaymentAmount', fieldValue(doc, 'totalPrice') || 0);
  }
  console.log(`  장소 예약 ${n}건 (confirmed ${confirmedReservations}건)`);

  console.log('[7/9] packageBookings 스캔 중...');
  n = 0;
  let confirmedBookings = 0;
  let cancelledWithRefund = 0;
  for await (const doc of iterateCollection('packageBookings', {
    selectFields: ['status', 'requesterId', 'hostId', 'totalPrice', 'refundAmount'],
    token,
  })) {
    n++;
    const status = fieldValue(doc, 'status');
    const hostId = fieldValue(doc, 'hostId');
    if (status === 'confirmed') {
      confirmedBookings++;
      bump(counters, fieldValue(doc, 'requesterId'), 'totalPackageBookingsAsGuest');
      bump(counters, hostId, 'totalPackageBookingsAsHost');
      bump(counters, hostId, 'cumulativePaymentAmount', fieldValue(doc, 'totalPrice') || 0);
    } else if (status === 'cancelled') {
      const refund = fieldValue(doc, 'refundAmount') || 0;
      if (refund > 0) {
        cancelledWithRefund++;
        bump(counters, hostId, 'cumulativeRefundAmount', refund);
      }
    }
  }
  console.log(`  패키지 예약 ${n}건 (confirmed ${confirmedBookings}건, 환불있는 취소 ${cancelledWithRefund}건)`);

  console.log('[8/9] applications(collectionGroup) 스캔 중...');
  n = 0;
  const STATUS_FIELD = {
    approved: 'totalConfirmed',
    attended: 'totalAttended',
    cancelled: 'totalCancelled',
    rejected: 'totalRejected',
    no_show: 'totalNoShows',
  };
  for await (const doc of iterateCollection('applications', {
    allDescendants: true,
    selectFields: ['uid', 'status'],
    token,
  })) {
    const uid = fieldValue(doc, 'uid');
    bump(counters, uid, 'totalApplications'); // 문서 존재 자체로 1건(생성 시 1회만 +1되는 것과 동일)
    const statusField = STATUS_FIELD[fieldValue(doc, 'status')];
    if (statusField) bump(counters, uid, statusField);
    n++;
  }
  console.log(`  신청 ${n}건`);

  console.log(`\n[9/9] 집계 결과: ${counters.size}명에게 반영할 카운터 있음`);

  let targets = [...counters.entries()];
  if (ONLY_UID) targets = targets.filter(([uid]) => uid === ONLY_UID);

  if (DRY_RUN) {
    console.log('\n--dry-run 모드라 실제로는 아무것도 쓰지 않았습니다.');
    const previewCount = Math.min(20, targets.length);
    console.log(`\n=== 반영 예정 미리보기(전체 ${targets.length}명 중 ${previewCount}명) ===`);
    for (const [uid, fields] of targets.slice(0, previewCount)) {
      console.log(`  - UID: ${uid} | ${JSON.stringify(fields)}`);
    }
    if (targets.length > previewCount) {
      console.log(`  ... 외 ${targets.length - previewCount}명 더 있음`);
    }
    console.log('\n실제로 반영하려면 --dry-run 없이 다시 실행하세요.');
    return;
  }

  console.log(`\n실제 반영을 시작합니다... (대상 ${targets.length}명)`);
  let done = 0;
  for (const [uid, fields] of targets) {
    await applyCounterPatch(uid, fields, token);
    done++;
    if (done % 25 === 0 || done === targets.length) {
      console.log(`  진행: ${done}/${targets.length}`);
    }
  }
  console.log(`\n완료: ${targets.length}명 반영`);
}

main().catch((err) => {
  console.error('백필 실패:', err);
  process.exit(1);
});

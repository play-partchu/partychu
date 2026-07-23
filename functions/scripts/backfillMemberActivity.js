// 1회성 백필 스크립트 — 통합 회원 관리 도입 전에 가입한 기존 회원에게
// isHost/hostSince/activityRoles/accountStatus를 채워 넣는다. 배포되는 Cloud
// Function이 아니라 로컬에서 직접 실행한다(backfillUserFields.js와 동일한
// 스타일 — gcloud 로그인 계정의 자격증명을 그대로 사용).
//
// 왜 필요한가
//   이 필드들은 앞으로는 functions/index.js + functions/memberManagement.js의
//   트리거가 실시간으로 채운다(파티/플레이스/상품/크루 등록, 파티 신청,
//   회원가입 시점). 하지만 그 트리거가 배포되기 "전"에 이미 파티를 등록했던
//   호스트나 이미 신청 이력이 있는 게스트는 activityRoles/isHost가 비어
//   있어서, 관리자 웹의 "활동 유형"/"계정 상태" 필터에 안 걸린다(필터
//   없이 보는 기본 목록에는 영향 없음 — 어디까지나 필터 대상에서만 빠짐).
//
// 원칙(전부 코드로 강제함)
//   - isHost / hostSince / accountStatus: 문서에 그 필드가 "이미 있으면"
//     절대 건드리지 않는다(값을 보지 않고 존재 여부만 확인 — 예를 들어
//     이용제한으로 accountStatus를 바꿔둔 회원을 다시 active로 되돌리는
//     사고를 원천 차단).
//   - activityRoles: Firestore의 arrayUnion(REST에서는 fieldTransforms의
//     appendMissingElements)을 써서 이미 값이 있어도 중복 없이 합집합으로만
//     추가한다 — 몇 번을 다시 실행해도 최종 결과가 같다(idempotent).
//   - 이 스크립트 자체도 여러 번 돌려도 안전하다: 이미 반영된 회원은 다음
//     실행 때 "변경 대상 없음"으로 자동 제외된다.
//
// 데이터 출처(전부 읽기 전용 조회, 원본 컬렉션은 건드리지 않음)
//   - parties.hostId          → activityRoles += 'host_activity', isHost 후보
//   - places.hostId           → activityRoles += 'place_operator', isHost 후보
//   - partyShops/*/products.hostId (collectionGroup) → activityRoles += 'shop_seller'
//   - crews.hostId (+crewType)→ activityRoles += 'crew_recruiting' | 'crew_seeking'
//   - applications.uid (collectionGroup, parties/*/applications) → activityRoles += 'guest_activity'
//   - hostSince 후보값은 위 파티/플레이스/상품/크루 문서 중 그 사람의
//     가장 이른 createdAt을 사용한다(실제 "최초 호스트 활동" 시점의 근사치).
//   - accountStatus는 이 스캔 결과와 무관하게 "필드가 아직 없는 모든 회원"에게
//     일괄로 'active' 기본값만 채운다(호스트든 게스트든 활동이 전혀 없는
//     회원이든 동일).
//
// 실행 전 준비:
//   gcloud auth login   (아직 로그인 안 했다면 — 프로젝트 소유자/편집자 권한 필요)
//
// 실행:
//   cd functions
//   node scripts/backfillMemberActivity.js --dry-run   → 아무것도 쓰지 않고 몇 명이
//                                                          바뀔지만 미리 확인
//   node scripts/backfillMemberActivity.js              → 실제로 반영
//
// 이 파일은 작성만 되어 있고, 사용자 승인 전에는 실행하지 않는다.

const { execSync } = require('child_process');

const PROJECT_ID = 'partychu-30c24';
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;
const DRY_RUN = process.argv.includes('--dry-run');
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

// ── 컬렉션(그룹)을 문서 이름(__name__) 커서로 페이지네이션하며 순회 ─────────
// select로 필요한 필드만 요청해 트래픽/비용을 최소화한다.
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
  return undefined;
}

function uidFromDocName(name) {
  const parts = name.split('/');
  return parts[parts.length - 1];
}

// ── 존재하는 필드는 절대 포함하지 않는 merge PATCH(isHost/hostSince/accountStatus 전용) ──
async function applyScalarPatch(uid, patchFields, token) {
  const keys = Object.keys(patchFields);
  if (keys.length === 0) return;
  const fields = {};
  for (const key of keys) {
    const value = patchFields[key];
    if (key === 'isHost') fields[key] = { booleanValue: value };
    else if (key === 'hostSince') fields[key] = { timestampValue: value };
    else fields[key] = { stringValue: String(value) }; // accountStatus
  }
  const mask = keys.map((k) => `updateMask.fieldPaths=${encodeURIComponent(k)}`).join('&');
  await apiFetch(`${BASE}/users/${uid}?${mask}`, token, {
    method: 'PATCH',
    body: JSON.stringify({ fields }),
  });
}

// ── activityRoles arrayUnion(REST: appendMissingElements) — 이미 있어도 중복 없이 추가 ──
async function applyActivityRolesUnion(uid, roles, token) {
  if (roles.length === 0) return;
  await apiFetch(`${BASE}:commit`, token, {
    method: 'POST',
    body: JSON.stringify({
      writes: [
        {
          transform: {
            document: `projects/${PROJECT_ID}/databases/(default)/documents/users/${uid}`,
            fieldTransforms: [
              {
                fieldPath: 'activityRoles',
                appendMissingElements: { values: roles.map((r) => ({ stringValue: r })) },
              },
            ],
          },
        },
      ],
    }),
  });
}

async function main() {
  const token = getAccessToken();
  console.log(DRY_RUN ? '=== DRY RUN — 실제로는 아무것도 쓰지 않습니다 ===' : '=== 실제 반영 모드 ===');

  // 1) 콘텐츠 컬렉션을 훑어 uid별 activityRoles 후보 + 가장 이른 활동 시각을 모은다.
  const roleMap = new Map(); // uid -> Set<role>
  const earliestMap = new Map(); // uid -> ISO timestamp 문자열(가장 이름)

  function addRole(uid, role, createdAtIso) {
    if (!uid) return;
    if (!roleMap.has(uid)) roleMap.set(uid, new Set());
    roleMap.get(uid).add(role);
    if (createdAtIso) {
      const cur = earliestMap.get(uid);
      if (!cur || createdAtIso < cur) earliestMap.set(uid, createdAtIso);
    }
  }

  console.log('[1/6] parties 스캔 중...');
  let partyCount = 0;
  for await (const doc of iterateCollection('parties', { selectFields: ['hostId', 'createdAt'], token })) {
    addRole(fieldValue(doc, 'hostId'), 'host_activity', fieldValue(doc, 'createdAt'));
    partyCount++;
  }
  console.log(`  파티 ${partyCount}건 확인`);

  console.log('[2/6] places 스캔 중...');
  let placeCount = 0;
  for await (const doc of iterateCollection('places', { selectFields: ['hostId', 'createdAt'], token })) {
    addRole(fieldValue(doc, 'hostId'), 'place_operator', fieldValue(doc, 'createdAt'));
    placeCount++;
  }
  console.log(`  플레이스 ${placeCount}건 확인`);

  console.log('[3/6] partyShops/*/products 스캔 중...');
  let productCount = 0;
  for await (const doc of iterateCollection('products', {
    allDescendants: true,
    selectFields: ['hostId', 'createdAt'],
    token,
  })) {
    addRole(fieldValue(doc, 'hostId'), 'shop_seller', fieldValue(doc, 'createdAt'));
    productCount++;
  }
  console.log(`  상품 ${productCount}건 확인`);

  console.log('[4/6] crews 스캔 중...');
  let crewCount = 0;
  for await (const doc of iterateCollection('crews', {
    selectFields: ['hostId', 'crewType', 'createdAt'],
    token,
  })) {
    const crewType = fieldValue(doc, 'crewType');
    addRole(fieldValue(doc, 'hostId'), crewType === '구인' ? 'crew_recruiting' : 'crew_seeking', fieldValue(doc, 'createdAt'));
    crewCount++;
  }
  console.log(`  크루 공고 ${crewCount}건 확인`);

  console.log('[5/6] applications(collectionGroup) 스캔 중...');
  let applicationCount = 0;
  for await (const doc of iterateCollection('applications', {
    allDescendants: true,
    selectFields: ['uid'],
    token,
  })) {
    addRole(fieldValue(doc, 'uid'), 'guest_activity', null);
    applicationCount++;
  }
  console.log(`  신청 ${applicationCount}건 확인`);

  console.log(`\n활동 이력이 확인된 회원(호스트/게스트 통틀어): ${roleMap.size}명`);

  // 2) users 전체를 훑으며 각자 실제로 필요한 patch를 계산한다 — 이미 필드가
  // 있으면 절대 건드리지 않는다.
  console.log('\n[6/6] users 컬렉션 확인 중...');
  let totalUsers = 0;
  let isHostToSet = 0;
  let hostSinceToSet = 0;
  let accountStatusToSet = 0;
  let activityRolesToUnion = 0;
  const plannedWrites = [];

  for await (const doc of iterateCollection('users', {
    // nickname/name은 dry-run 미리보기에서 UID만으로는 누군지 알아보기
    // 어려우니 검증용으로 함께 가져온다(실제 patch 대상 필드는 아님).
    selectFields: ['isHost', 'hostSince', 'accountStatus', 'nickname', 'name'],
    token,
  })) {
    totalUsers++;
    const uid = uidFromDocName(doc.name);
    const existingIsHost = fieldValue(doc, 'isHost');
    const existingHostSince = fieldValue(doc, 'hostSince');
    const existingAccountStatus = fieldValue(doc, 'accountStatus');
    const nickname = fieldValue(doc, 'nickname') || fieldValue(doc, 'name') || '(닉네임 없음)';
    const roles = roleMap.get(uid);
    const isHostCandidate = !!roles && (roles.has('host_activity') || roles.has('place_operator'));

    const patchFields = {};
    if (isHostCandidate && existingIsHost === undefined) {
      patchFields.isHost = true;
      isHostToSet++;
    }
    if (isHostCandidate && existingHostSince === undefined) {
      const earliest = earliestMap.get(uid);
      if (earliest) {
        patchFields.hostSince = earliest;
        hostSinceToSet++;
      }
    }
    if (existingAccountStatus === undefined) {
      patchFields.accountStatus = 'active';
      accountStatusToSet++;
    }

    const unionRoles = roles ? Array.from(roles) : [];
    if (unionRoles.length > 0) activityRolesToUnion++;

    if (Object.keys(patchFields).length > 0 || unionRoles.length > 0) {
      plannedWrites.push({ uid, nickname, patchFields, unionRoles });
    }

    if (totalUsers % 500 === 0) console.log(`  ...${totalUsers}명 확인`);
  }

  console.log('\n=== 요약 ===');
  console.log(`전체 users 문서 수: ${totalUsers}명`);
  console.log(`변경 대상 회원 수(아래 필드 중 하나라도 새로 채워짐): ${plannedWrites.length}명`);
  console.log(`  - isHost 새로 설정 예정: ${isHostToSet}명`);
  console.log(`  - hostSince 새로 설정 예정: ${hostSinceToSet}명`);
  console.log(`  - accountStatus('active') 새로 설정 예정: ${accountStatusToSet}명`);
  console.log(`  - activityRoles arrayUnion 적용 예정: ${activityRolesToUnion}명`);

  if (DRY_RUN) {
    console.log('\n--dry-run 모드라 실제로는 아무것도 쓰지 않았습니다.');
    if (plannedWrites.length > 0) {
      const previewCount = Math.min(20, plannedWrites.length);
      console.log(`\n=== 변경 대상 회원 미리보기(전체 ${plannedWrites.length}명 중 ${previewCount}명) ===`);
      for (const w of plannedWrites.slice(0, previewCount)) {
        const fieldSummary = [];
        for (const [key, value] of Object.entries(w.patchFields)) {
          fieldSummary.push(`${key}=${value}`);
        }
        if (w.unionRoles.length > 0) {
          fieldSummary.push(`activityRoles+=[${w.unionRoles.join(', ')}]`);
        }
        console.log(`  - UID: ${w.uid} | 닉네임: ${w.nickname}`);
        console.log(`      변경 예정 필드: ${fieldSummary.join(', ')}`);
      }
      if (plannedWrites.length > previewCount) {
        console.log(`  ... 외 ${plannedWrites.length - previewCount}명 더 있음(미리보기는 최대 20명까지만 표시)`);
      }
    }
    console.log('\n실제로 반영하려면 --dry-run 없이 다시 실행하세요.');
    return;
  }

  console.log('\n실제 반영을 시작합니다...');
  let done = 0;
  for (const w of plannedWrites) {
    await applyScalarPatch(w.uid, w.patchFields, token);
    await applyActivityRolesUnion(w.uid, w.unionRoles, token);
    done++;
    if (done % 25 === 0 || done === plannedWrites.length) {
      console.log(`  진행: ${done}/${plannedWrites.length}`);
    }
  }
  console.log(`\n완료: ${plannedWrites.length}명 반영`);
}

main().catch((err) => {
  console.error('백필 실패:', err);
  process.exit(1);
});

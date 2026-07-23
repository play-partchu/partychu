// 1회성 백필 스크립트 — 배포되는 Cloud Function이 아니라 로컬에서 직접 실행한다.
//
// 관리자 웹 회원 검색/정렬 기능(nicknameLower/nameLower/emailLower prefix
// 검색, stats.attendedCount 기준 정렬)이 기존 가입자에게도 적용되도록
// 한 번만 실행한다. 앞으로의 가입자·변경 건은 index.js의 onUserCreated /
// onUserFieldsWrite 트리거가 자동으로 채운다.
//
// Firestore는 정렬 대상 필드가 없는 문서를 orderBy 결과에서 통째로 제외하기
// 때문에, 값이 비어 있더라도 반드시 빈 문자열/0으로라도 채워 넣는다.
//
// 인증: firebase-admin의 Application Default Credentials 대신, 로컬에 이미
// 로그인된 gcloud 사용자 자격 증명(`gcloud auth print-access-token`)을 그대로
// 사용한다 — 이 계정이 프로젝트 소유자/편집자 권한을 이미 갖고 있어야 한다.
//
// 실행:
//   cd functions
//   node scripts/backfillSearchFields.js

const { execSync } = require('child_process');

const PROJECT_ID = 'partychu-30c24';
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

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

function fieldString(fields, key) {
  return fields?.[key]?.stringValue ?? '';
}

function fieldInt(fields, key) {
  const v = fields?.[key]?.integerValue;
  return v == null ? null : Number(v);
}

async function listAllUserDocs(token) {
  const docs = [];
  let pageToken;
  do {
    const url = new URL(`${BASE}/users`);
    url.searchParams.set('pageSize', '300');
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const body = await apiFetch(url.toString(), token);
    docs.push(...(body.documents || []));
    pageToken = body.nextPageToken;
  } while (pageToken);
  return docs;
}

const STAT_KEYS = ['applicationCount', 'approvedCount', 'attendedCount', 'cancelledCount', 'rejectedCount', 'noShowCount'];

function buildPatch(doc) {
  const fields = doc.fields || {};
  const patch = {};
  const maskPaths = [];

  const wantNicknameLower = fieldString(fields, 'nickname').toLowerCase();
  if (fieldString(fields, 'nicknameLower') !== wantNicknameLower) {
    patch.nicknameLower = { stringValue: wantNicknameLower };
    maskPaths.push('nicknameLower');
  }

  const wantNameLower = fieldString(fields, 'name').toLowerCase();
  if (fieldString(fields, 'nameLower') !== wantNameLower) {
    patch.nameLower = { stringValue: wantNameLower };
    maskPaths.push('nameLower');
  }

  const wantEmailLower = fieldString(fields, 'email').toLowerCase();
  if (fieldString(fields, 'emailLower') !== wantEmailLower) {
    patch.emailLower = { stringValue: wantEmailLower };
    maskPaths.push('emailLower');
  }

  const statsMap = fields.stats?.mapValue?.fields || null;
  const missingStat = STAT_KEYS.some((k) => statsMap?.[k] == null);
  if (missingStat) {
    const mergedStats = {};
    for (const k of STAT_KEYS) {
      const existing = statsMap?.[k]?.integerValue;
      mergedStats[k] = { integerValue: existing != null ? existing : '0' };
    }
    patch.stats = { mapValue: { fields: mergedStats } };
    maskPaths.push('stats');
  }

  return { patch, maskPaths };
}

async function backfill() {
  const token = getAccessToken();
  const docs = await listAllUserDocs(token);
  console.log(`users 문서 ${docs.length}건 확인`);

  let updated = 0;
  let skipped = 0;

  for (const doc of docs) {
    const uid = doc.name.split('/').pop();
    const { patch, maskPaths } = buildPatch(doc);
    if (maskPaths.length === 0) {
      skipped++;
      continue;
    }
    const mask = maskPaths.map((p) => `updateMask.fieldPaths=${p}`).join('&');
    await apiFetch(`${BASE}/users/${uid}?${mask}`, token, {
      method: 'PATCH',
      body: JSON.stringify({ fields: patch }),
    });
    updated++;
    console.log(`[backfill] ${uid} <- ${maskPaths.join(', ')}`);
  }

  console.log(`완료: ${updated}건 갱신, ${skipped}건 건너뜀(이미 값 있음)`);
}

backfill().catch((err) => {
  console.error('백필 실패:', err);
  process.exit(1);
});

// 1회성 백필 스크립트 — 배포되는 Cloud Function이 아니라 로컬에서 직접 실행한다.
//
// 지금까지 users/{uid} 문서는 createdAt/email 필드를 전혀 기록하지 않았다
// (신규 가입은 index.js의 onUserCreated 트리거가 앞으로 자동으로 채운다).
// 이 스크립트는 트리거 배포 이전에 이미 가입한 기존 계정들의 createdAt/email을
// Firebase Auth 메타데이터(creationTime/email) 기준으로 한 번만 채워 넣는다.
// 이미 값이 있는 필드는 덮어쓰지 않는다(merge, 기존 값 우선).
//
// 인증: firebase-admin의 Application Default Credentials 대신, 로컬에 이미
// 로그인된 gcloud 사용자 자격 증명(`gcloud auth print-access-token`)을 그대로
// 사용한다 — 이 계정이 프로젝트 소유자/편집자 권한을 이미 갖고 있어야 한다.
//
// 실행 전 준비:
//   gcloud auth login   (아직 로그인 안 했다면)
//
// 실행:
//   cd functions
//   node scripts/backfillUserFields.js

const { execSync } = require('child_process');

const PROJECT_ID = 'partychu-30c24';

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

async function listAllAuthUsers(token) {
  const users = [];
  let nextPageToken;
  do {
    const body = await apiFetch(
      `https://identitytoolkit.googleapis.com/v1/projects/${PROJECT_ID}/accounts:query`,
      token,
      {
        method: 'POST',
        body: JSON.stringify({ returnUserInfo: true, maxResults: 500, nextPageToken }),
      }
    );
    users.push(...(body.userInfo || []));
    nextPageToken = body.nextPageToken;
  } while (nextPageToken);
  return users;
}

async function getUserDoc(uid, token) {
  try {
    return await apiFetch(
      `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/users/${uid}`,
      token
    );
  } catch {
    return null; // 문서가 없으면 404 → merge 대상으로 취급
  }
}

async function patchUserDoc(uid, patch, token) {
  const fields = {};
  const maskPaths = [];
  if (patch.createdAt) {
    fields.createdAt = { timestampValue: patch.createdAt };
    maskPaths.push('createdAt');
  }
  if (patch.email) {
    fields.email = { stringValue: patch.email };
    maskPaths.push('email');
  }
  const mask = maskPaths.map((p) => `updateMask.fieldPaths=${p}`).join('&');
  await apiFetch(
    `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/users/${uid}?${mask}`,
    token,
    { method: 'PATCH', body: JSON.stringify({ fields }) }
  );
}

async function backfill() {
  const token = getAccessToken();
  const authUsers = await listAllAuthUsers(token);
  console.log(`Firebase Auth 계정 ${authUsers.length}명 확인`);

  let updated = 0;
  let skipped = 0;

  for (const user of authUsers) {
    const doc = await getUserDoc(user.localId, token);
    const existing = doc?.fields || {};

    const patch = {};
    if (!existing.createdAt && user.createdAt) {
      patch.createdAt = new Date(Number(user.createdAt)).toISOString();
    }
    if (!existing.email && user.email) {
      patch.email = user.email;
    }

    if (Object.keys(patch).length === 0) {
      skipped++;
      continue;
    }

    await patchUserDoc(user.localId, patch, token);
    updated++;
    console.log(`[backfill] ${user.localId} <- ${JSON.stringify(patch)}`);
  }

  console.log(`완료: ${updated}건 갱신, ${skipped}건 건너뜀(이미 값 있음 또는 변경 없음)`);
}

backfill().catch((err) => {
  console.error('백필 실패:', err);
  process.exit(1);
});

// 1회성 QA 테스트 계정 생성 스크립트 — 배포되는 Cloud Function이 아니라
// 로컬에서 직접 실행한다(backfillUserFields.js와 동일한 패턴).
//
// 하는 일:
//   1. Identity Platform 프로젝트 설정에서 Email/Password 로그인 provider를
//      활성화한다(REST — firebase-admin SDK는 이 설정을 노출하지 않음).
//      updateMask로 signIn.email만 건드리므로 이미 설정된 Google/커스텀토큰
//      (카카오·네이버) 로그인 설정에는 영향 없다.
//   2. host@test.com / guest@test.com Firebase Auth 계정을 생성(이미 있으면
//      비밀번호/표시이름만 갱신 — 재실행해도 안전).
//   3. NICE 본인인증을 마친 실제 계정과 동일한 shape로 users/{uid} 문서를
//      채운다(functions/index.js의 niceIntcResult 핸들러 참고) — 파티
//      생성/신청/승인/채팅 테스트가 온보딩 절차 없이 바로 가능하도록.
//
// 인증: ADC/서비스 계정 키 대신, 로컬에 이미 로그인된 gcloud 사용자
// 자격증명(`gcloud auth print-access-token`)을 firebase-admin의 커스텀
// Credential로 그대로 연결한다 — 이 계정이 프로젝트 소유자/편집자 권한을
// 이미 갖고 있어야 한다.
//
// 실행 전 준비:
//   gcloud auth login   (아직 로그인 안 했다면)
//
// 실행:
//   cd functions
//   node scripts/createTestAccounts.js

const { execSync } = require('child_process');
const admin = require('firebase-admin');

const PROJECT_ID = 'partychu-30c24';

function getAccessToken() {
  return execSync('gcloud auth print-access-token', { encoding: 'utf8' }).trim();
}

admin.initializeApp({
  // backfillUserFields.js와 동일한 방식 — 서비스 계정 키 파일 없이, 로컬
  // gcloud 사용자 토큰을 그대로 Bearer 토큰으로 재사용하는 커스텀 Credential.
  credential: {
    getAccessToken: async () => ({
      access_token: getAccessToken(),
      expires_in: 3600,
    }),
  },
  projectId: PROJECT_ID,
});

const TEST_ACCOUNTS = [
  {
    email: 'host@test.com',
    password: 'Host1234!@',
    displayName: '호스트테스트(TEST)',
    gender: 'male',
    birthYear: 1993,
  },
  {
    email: 'guest@test.com',
    password: 'Guest1234!@',
    displayName: '참가자테스트(TEST)',
    gender: 'female',
    birthYear: 1996,
  },
];

// ── 1. Email/Password provider 활성화 (Identity Platform REST — updateMask로
// signIn.email만 갱신, 다른 provider 설정은 건드리지 않는다) ─────────────────

async function enableEmailPasswordProvider() {
  const token = getAccessToken();
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/admin/v2/projects/${PROJECT_ID}/config?updateMask=signIn.email`,
    {
      method: 'PATCH',
      headers: {
        Authorization: `Bearer ${token}`,
        'x-goog-user-project': PROJECT_ID,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        signIn: { email: { enabled: true, passwordRequired: true } },
      }),
    },
  );
  const body = await res.json();
  if (!res.ok) {
    throw new Error(`Email/Password provider 활성화 실패: ${res.status} ${JSON.stringify(body)}`);
  }
  console.log('[createTestAccounts] Email/Password 로그인 활성화 완료:', body.signIn?.email);
}

// ── 2. Firebase Auth 계정 생성(재실행 안전 — 있으면 갱신만) ───────────────────

async function upsertAuthUser(account) {
  try {
    const existing = await admin.auth().getUserByEmail(account.email);
    await admin.auth().updateUser(existing.uid, {
      password: account.password,
      displayName: account.displayName,
      emailVerified: true,
      disabled: false,
    });
    console.log(`[createTestAccounts] 기존 계정 갱신 — ${account.email} (uid=${existing.uid})`);
    return existing.uid;
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
    const created = await admin.auth().createUser({
      email: account.email,
      password: account.password,
      displayName: account.displayName,
      emailVerified: true,
      disabled: false,
    });
    console.log(`[createTestAccounts] 신규 계정 생성 — ${account.email} (uid=${created.uid})`);
    return created.uid;
  }
}

// ── 3. Firestore users/{uid} 프로필 시드 — niceIntcResult 핸들러와 동일 shape ──
//
// admin.firestore()는 커스텀(비-ADC) Credential을 거부해서(firestore/invalid-
// credential) 쓸 수 없다 — backfillUserFields.js와 동일하게 REST로 직접 쓴다.

function fsValue(v) {
  if (typeof v === 'string') return { stringValue: v };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') return { integerValue: String(v) };
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  throw new Error(`지원하지 않는 Firestore 값 타입: ${typeof v}`);
}

async function seedUserProfile(uid, account) {
  const token = getAccessToken();
  const now = new Date();
  const patch = {
    name: account.displayName,
    nickname: account.displayName,
    gender: account.gender,
    birthYear: account.birthYear,
    identityVerified: true,
    identityVerifiedAt: now,
    isVerified: true, // Firestore Rules 하위 호환(niceIntcResult 핸들러와 동일)
    verifiedAt: now,
    profileCompleted: true,
    verificationProvider: 'test_seed',
    profileImageUrl: '',
    role: '',
    isTestAccount: true, // 일반 사용자와 구분하기 위한 표식(관리자 웹 필터링용)
  };

  const fields = {};
  const maskParams = [];
  for (const [key, value] of Object.entries(patch)) {
    fields[key] = fsValue(value);
    maskParams.push(`updateMask.fieldPaths=${key}`);
  }

  const res = await fetch(
    `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/users/${uid}?${maskParams.join('&')}`,
    {
      method: 'PATCH',
      headers: {
        Authorization: `Bearer ${token}`,
        'x-goog-user-project': PROJECT_ID,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ fields }),
    },
  );
  const body = await res.json();
  if (!res.ok) {
    throw new Error(`users/${uid} 프로필 시드 실패: ${res.status} ${JSON.stringify(body)}`);
  }
  console.log(`[createTestAccounts] users/${uid} 프로필 시드 완료`);
}

async function main() {
  await enableEmailPasswordProvider();
  for (const account of TEST_ACCOUNTS) {
    const uid = await upsertAuthUser(account);
    await seedUserProfile(uid, account);
  }
  console.log('[createTestAccounts] 완료 — host@test.com / guest@test.com 준비됨');
}

main().catch((err) => {
  console.error('[createTestAccounts] 실패:', err);
  process.exit(1);
});

// 1회성 계정 복구 스크립트 — 배포되는 Cloud Function이 아니라 로컬에서 직접
// 실행한다. backfillUserFields.js와 동일한 방식(gcloud 로그인 계정의 자격
// 증명으로 Identity Toolkit REST API 호출)으로 동작한다 — Firebase Admin SDK의
// `auth().updateUser(uid, {password})`도 내부적으로 이 API를 그대로 호출하므로
// 결과는 동일하다(별도 서비스 계정 키 파일 없이 실행하기 위해 REST를 쓴다).
//
// 용도: 비밀번호 재설정 메일을 받을 수 없는(이메일 접근 불가) 관리자 계정의
// 비밀번호를 임시 비밀번호로 직접 덮어쓴다. 정상 재설정 플로우를 우회하는
// 관리자 전용 복구 절차이므로, 로그인에 성공한 즉시 반드시 새 비밀번호로
// 바꾸도록 안내한다(임시 비밀번호가 이 대화/파일에 평문으로 남기 때문).
//
// 실행 전 준비:
//   gcloud auth login   (프로젝트 소유자/편집자 권한 필요)
//
// 실행:
//   cd functions
//   node scripts/resetAdminPassword.js
//   (이메일/비밀번호를 바꾸고 싶다면: node scripts/resetAdminPassword.js --email=... --password=...)

const { execSync } = require('child_process');

const PROJECT_ID = 'partychu-30c24';

function argValue(flag, fallback) {
  const arg = process.argv.find((a) => a.startsWith(`--${flag}=`));
  return arg ? arg.split('=').slice(1).join('=') : fallback;
}

const TARGET_EMAIL = argValue('email', 'admin@partychu.co.kr');
const TEMP_PASSWORD = argValue('password', 'Partychu!2026#');

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

async function findUserByEmail(email, token) {
  const body = await apiFetch(
    `https://identitytoolkit.googleapis.com/v1/projects/${PROJECT_ID}/accounts:lookup`,
    token,
    { method: 'POST', body: JSON.stringify({ email: [email] }) }
  );
  return (body.users || [])[0] || null;
}

async function setPassword(localId, password, token) {
  await apiFetch(
    `https://identitytoolkit.googleapis.com/v1/projects/${PROJECT_ID}/accounts:update`,
    token,
    { method: 'POST', body: JSON.stringify({ localId, password, returnSecureToken: false }) }
  );
}

async function main() {
  console.log(`대상 계정: ${TARGET_EMAIL}`);
  const token = getAccessToken();

  const user = await findUserByEmail(TARGET_EMAIL, token);
  if (!user) {
    console.error(`계정을 찾지 못했습니다: ${TARGET_EMAIL} (Firebase Auth에 이 이메일로 가입된 계정이 없습니다)`);
    process.exit(1);
  }
  console.log(`계정 확인됨 — uid: ${user.localId}`);

  await setPassword(user.localId, TEMP_PASSWORD, token);

  console.log('\n=== 완료 ===');
  console.log(`${TARGET_EMAIL} 비밀번호를 임시 비밀번호로 변경했습니다.`);
  console.log(`임시 비밀번호: ${TEMP_PASSWORD}`);
  console.log('\n로그인 직후 반드시 새 비밀번호로 다시 변경해주세요(이 임시 비밀번호는 이 대화/파일에 평문으로 남아 있습니다).');
}

main().catch((err) => {
  console.error('비밀번호 재설정 실패:', err.message);
  process.exit(1);
});

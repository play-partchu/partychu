// socialAuth.js 자체 검증 — 배포 전에 `npm run check:social`로 돌린다.
// functions에는 테스트 러너가 없으므로 node 기본 assert만 쓴다(의존성 0).
//
// 네트워크(카카오·네이버 API)와 Admin SDK는 여기서 부르지 않는다. 대신
// "클라이언트가 보낸 값을 어디까지 믿는가"라는 보안 경계와, uid 규칙처럼
// 한 번 정하면 바꾸기 어려운 계약을 고정한다.

const assert = require('assert');

// initializeApp은 index.js가 직접 호출한다 — 여기서 먼저 부르면 아래
// require('./index.js')에서 duplicate-app 오류가 난다.
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'selfcheck';

const socialAuth = require('./socialAuth');
const { readAccessToken, secretValue, isValidKakaoAppId } = socialAuth.__test;

// ── 1. 두 함수가 실제로 등록됐는지 ───────────────────────────────────────────
// 앱(login.dart)이 부르는 이름과 정확히 같아야 한다 — 이름이 어긋나면
// 클라이언트는 'not-found'만 받고 원인을 알 수 없다.
for (const name of ['kakaoCustomToken', 'naverCustomToken']) {
  assert.ok(socialAuth[name], `${name}이 export되지 않았다`);
}

// index.js를 통해서도 같은 이름으로 노출되는지(배포되는 실제 경로).
const index = require('./index.js');
for (const name of ['kakaoCustomToken', 'naverCustomToken']) {
  assert.ok(index[name], `index.js에서 ${name}이 노출되지 않았다`);
}

// ── 2. 액세스 토큰 입력 검증 ─────────────────────────────────────────────────

assert.strictEqual(
  readAccessToken({ data: { token: 'abc123' } }), 'abc123',
  '정상 토큰은 그대로 통과',
);

for (const bad of [
  { data: {} },
  { data: { token: '' } },
  { data: { token: 123 } },
  { data: { token: null } },
  { data: { token: { evil: true } } },
  {},
]) {
  assert.throws(
    () => readAccessToken(bad),
    /액세스 토큰이 필요합니다/,
    `잘못된 입력을 막아야 한다: ${JSON.stringify(bad)}`,
  );
}

// 비정상적으로 긴 토큰은 거절한다(메모리·로그 오염 방지).
assert.throws(
  () => readAccessToken({ data: { token: 'x'.repeat(4097) } }),
  /액세스 토큰이 필요합니다/,
  '길이 상한을 넘는 토큰은 거절',
);

// ── 3. 시크릿 미설정 시에도 터지지 않는다 ────────────────────────────────────
// 로컬/셀프체크 환경에는 시크릿이 없다. 값을 못 읽어도 예외 대신 빈 문자열을
// 돌려줘야, 카카오 앱 검증만 건너뛰고 로그인 자체는 계속 동작한다.
assert.strictEqual(
  secretValue({ value: () => { throw new Error('미설정'); } }), '',
  '시크릿 미설정 시 빈 문자열',
);
assert.strictEqual(secretValue({ value: () => null }), '', 'null이면 빈 문자열');
assert.strictEqual(secretValue({ value: () => '  12345  ' }), '12345', '공백 제거');

// 앱 ID 형식 검사 — 자리표시자나 오타가 들어가도 "전체 로그인 차단"으로
// 번지지 않고 검증만 건너뛰어야 한다.
assert.ok(isValidKakaoAppId('1234567'), '숫자 앱 ID는 유효');
for (const bad of ['', 'REPLACE_ME', 'abc', '123abc', '12 34', '-1', '1.5']) {
  assert.ok(!isValidKakaoAppId(bad), `잘못된 앱 ID 형식을 걸러야 한다: "${bad}"`);
}

// ── 4. uid 규칙이 소스에 그대로 남아 있는지 ──────────────────────────────────
// uid는 한 번 배포되면 바꿀 수 없다(바꾸면 기존 회원이 전부 새 계정이 된다).
// 제공자 접두어가 사라지는 변경을 배포 전에 잡는다.
const src = require('fs').readFileSync(__dirname + '/socialAuth.js', 'utf8');
assert.ok(src.includes('`kakao:${me.body.id}`'), '카카오 uid 접두어가 바뀌었다');
assert.ok(src.includes('`naver:${r.id}`'), '네이버 uid 접두어가 바뀌었다');

// ── 5. 클라이언트 값을 신뢰하지 않는지 ───────────────────────────────────────
// request.data에서 읽는 건 token 하나뿐이어야 한다. uid/email/name 같은 값을
// 클라이언트에서 받아 쓰기 시작하면 계정 도용이 가능해진다.
const dataReads = src.match(/request\.data(\.\w+|\s*&&\s*request\.data\.\w+)/g) || [];
for (const r of dataReads) {
  assert.ok(
    r.includes('token'),
    `클라이언트에서 token 외의 값을 읽고 있다: ${r}`,
  );
}

console.log('✅ socialAuth.selfcheck 통과');

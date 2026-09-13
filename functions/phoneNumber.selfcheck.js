// 휴대폰번호 정규화 자체 검증 — `node phoneNumber.selfcheck.js`.
//
// 이 정규화가 지켜야 하는 것은 세 가지다.
//
//   · 저장 모양이 **하나**다 — 신 경로(niceAuth.js)와 구 경로(index.js의
//     niceIntcResult)가 같은 함수를 쓰므로, 여기가 흔들리면 계정마다 다른
//     형식이 저장된다.
//   · 관리자 마스킹과 **모양이 맞는다** — admin_app의 Masking.phone이 숫자만
//     남긴 뒤 앞 3자리·뒤 4자리를 취하므로, 앞 3자리가 통신사 번호여야 한다.
//     (E.164로 저장하면 '821-****-5678'이 찍힌다 — 그래서 국내 형식이다.)
//   · 알아보지 못하면 **빈 문자열**이다 — 반쯤 맞는 값을 남기지 않는다.
//     호출부는 빈 문자열일 때 필드를 아예 쓰지 않는다.

const assert = require('assert');
const { normalizeKoreanMobile, KOREAN_MOBILE } = require('./phoneNumber');

const cases = [];
const test = (name, fn) => cases.push([name, fn]);

// ── 정규화해서 저장되는 것 ───────────────────────────────────────────────

test('NICE가 주는 숫자열은 그대로 통과한다', () => {
  assert.strictEqual(normalizeKoreanMobile('01012345678'), '01012345678');
});

test('하이픈·공백·괄호는 전부 버린다', () => {
  assert.strictEqual(normalizeKoreanMobile('010-1234-5678'), '01012345678');
  assert.strictEqual(normalizeKoreanMobile('010 1234 5678'), '01012345678');
  assert.strictEqual(normalizeKoreanMobile('(010) 1234-5678'), '01012345678');
});

test('010 외의 구 번호대도 받는다', () => {
  assert.strictEqual(normalizeKoreanMobile('011-234-5678'), '0112345678');
  assert.strictEqual(normalizeKoreanMobile('016-123-4567'), '0161234567');
  assert.strictEqual(normalizeKoreanMobile('019-9876-5432'), '01998765432');
});

test('국제 표기(+82)는 국내 표기로 되돌린다', () => {
  assert.strictEqual(normalizeKoreanMobile('+82-10-1234-5678'), '01012345678');
  assert.strictEqual(normalizeKoreanMobile('821012345678'), '01012345678');
});

test('국가번호 뒤에 0이 남아 있어도 0을 두 번 붙이지 않는다', () => {
  // '+82 010 1234 5678'처럼 오는 표기 — 그냥 0을 붙이면 '0010…'이 되어
  // 멀쩡한 번호가 버려진다.
  assert.strictEqual(normalizeKoreanMobile('+82 010 1234 5678'), '01012345678');
});

// ── 저장하지 않는 것(빈 문자열) ──────────────────────────────────────────

test('값이 없으면 빈 문자열이다', () => {
  assert.strictEqual(normalizeKoreanMobile(undefined), '');
  assert.strictEqual(normalizeKoreanMobile(null), '');
  assert.strictEqual(normalizeKoreanMobile(''), '');
  assert.strictEqual(normalizeKoreanMobile('   '), '');
});

test('휴대폰이 아닌 번호는 저장하지 않는다', () => {
  assert.strictEqual(normalizeKoreanMobile('02-123-4567'), '');   // 서울 유선
  assert.strictEqual(normalizeKoreanMobile('070-1234-5678'), ''); // 인터넷전화
  assert.strictEqual(normalizeKoreanMobile('1588-1588'), '');     // 대표번호
});

test('앞자리 0이 빠진 값은 추측해서 채우지 않는다', () => {
  // '1012345678'을 '01012345678'로 되살리는 것은 추측이다 — 그러느니 없는 게 낫다.
  assert.strictEqual(normalizeKoreanMobile('1012345678'), '');
});

test('자릿수가 어긋나면 저장하지 않는다', () => {
  assert.strictEqual(normalizeKoreanMobile('010123456'), '');      // 너무 짧다
  assert.strictEqual(normalizeKoreanMobile('010123456789'), '');   // 너무 길다
});

test('숫자가 아닌 값은 저장하지 않는다', () => {
  assert.strictEqual(normalizeKoreanMobile('연락처 없음'), '');
  assert.strictEqual(normalizeKoreanMobile({}), '');
  assert.strictEqual(normalizeKoreanMobile(['01012345678']), '');
});

// ── 불변식 ───────────────────────────────────────────────────────────────

test('돌려주는 값은 언제나 빈 문자열이거나 국내 휴대폰 형식이다', () => {
  const inputs = [
    '01012345678', '010-1234-5678', '+82 10 1234 5678', '821012345678',
    '02-123-4567', '1588-1588', '1012345678', '', null, undefined, 42, {},
    '010123456789', 'abc', '+8201012345678',
  ];
  for (const v of inputs) {
    const out = normalizeKoreanMobile(v);
    assert.ok(
      out === '' || KOREAN_MOBILE.test(out),
      `반쯤 정규화된 값이 새어나왔다: ${JSON.stringify(v)} → ${out}`
    );
  }
});

test('관리자 마스킹이 통신사 번호를 앞 3자리로 읽는다', () => {
  // admin_app/lib/utils/masking.dart의 Masking.phone과 같은 계산.
  const masked = (v) => {
    const d = v.replace(/[^0-9]/g, '');
    return `${d.slice(0, 3)}-****-${d.slice(-4)}`;
  };
  assert.strictEqual(masked(normalizeKoreanMobile('010-1234-5678')), '010-****-5678');
  // E.164로 저장했다면 여기서 '821-****-5678'이 나온다 — 그래서 국내 형식이다.
  assert.strictEqual(masked(normalizeKoreanMobile('+82-10-1234-5678')), '010-****-5678');
});

test('정규화는 멱등이다 — 이미 저장된 값을 다시 넣어도 그대로다', () => {
  const once = normalizeKoreanMobile('010-1234-5678');
  assert.strictEqual(normalizeKoreanMobile(once), once);
});

// ── 호출부 정합성 ────────────────────────────────────────────────────────

test('신·구 NICE 경로가 같은 정규화 함수를 쓴다', () => {
  // 한쪽만 고쳐져 저장 형식이 갈라지는 것을 막는다.
  const fs = require('fs');
  for (const file of ['./niceAuth', './index']) {
    const src = fs.readFileSync(require.resolve(file), 'utf8');
    assert.ok(
      src.includes("require('./phoneNumber')"),
      `${file}이 phoneNumber 정규화를 가져오지 않는다`
    );
    assert.ok(
      src.includes('normalizeKoreanMobile(result.mobile_no)'),
      `${file}이 mobile_no를 정규화해서 쓰지 않는다`
    );
  }
});

test('번호 원문이 문자열에 끼어드는 곳이 없다', () => {
  // 잡으려는 것은 "번호가 값 그대로 문자열이 되는 것"이다. 그래서 검사 대상은
  // 템플릿 보간(`${…}`)이고, 그 안에 번호가 들어간다면 반드시 불리언으로
  // 접혀 있어야 한다(`!!result.mobile_no`처럼 "값이 왔는지"만 남긴다).
  const fs = require('fs');
  const interpolation = /\$\{([^}]*)\}/g;
  for (const file of ['./niceAuth', './index', './phoneNumber']) {
    const src = fs.readFileSync(require.resolve(file), 'utf8');
    for (const [whole, inner] of src.matchAll(interpolation)) {
      if (!/\bphoneNumber\b|\bmobile_no\b/.test(inner)) continue;
      assert.ok(
        /^\s*(!!|Boolean\()/.test(inner),
        `${file}이 번호를 문자열에 그대로 넣는다: ${whole}`
      );
    }
  }
});

test('탈퇴 시 지우는 개인정보 목록에 phoneNumber가 있다', () => {
  const { __helpers } = require('./accountWithdrawal');
  assert.ok(
    __helpers.PERSONAL_FIELDS.includes('phoneNumber'),
    'phoneNumber가 탈퇴 삭제 목록에 없다'
  );
});

test('firestore.rules가 phoneNumber를 클라이언트 쓰기에서 잠근다', () => {
  const fs = require('fs');
  const rules = fs.readFileSync(`${__dirname}/../firestore.rules`, 'utf8');
  // create 차단 목록과 update 차단(isVerificationFieldChange) 양쪽에 있어야 한다.
  const hits = rules.split('\n').filter((l) => l.includes("'phoneNumber'")).length;
  assert.ok(hits >= 2, `phoneNumber 잠금이 부족하다(발견 ${hits}곳, 2곳 이상이어야 함)`);
});

// ── 실행 ─────────────────────────────────────────────────────────────────

let failed = 0;
for (const [name, fn] of cases) {
  try {
    fn();
    console.log(`  ✓ ${name}`);
  } catch (e) {
    failed++;
    console.error(`  ✗ ${name}\n    ${e.message}`);
  }
}
console.log(`\n${cases.length - failed}/${cases.length} 통과`);
process.exit(failed === 0 ? 0 : 1);

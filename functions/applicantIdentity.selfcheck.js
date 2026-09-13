// 신청자 신원 payload 자체 검증 — `node applicantIdentity.selfcheck.js`.
//
// 이 payload 하나가 호스트의 **입장 확인 근거**다(본인확인 완료 배지 + 실명).
// 그래서 두 가지를 못박는다.
//   · 본인확인을 마치지 않은 계정에는 실명·성별·생년월일이 실리지 않는다
//   · 확인 여부(`verified`)는 다른 필드로 추측하지 않고 그대로 내려간다
//
// 클라이언트 쪽 같은 규칙은 party_app/test/applicant_identity_test.dart가 본다.

const assert = require('assert');
const { buildApplicantIdentity } = require('./applicantIdentity');

const cases = [];
const test = (name, fn) => cases.push([name, fn]);

const verifiedUser = {
  identityVerified: true,
  nickname: '냥냥이',
  name: '홍길동',
  gender: 'female',
  birthYear: 1991,
  birthMonth: 3,
  birthDay: 7,
};

test('본인확인을 마친 계정은 실명과 확인 여부가 함께 나간다', () => {
  const { identity } = buildApplicantIdentity(verifiedUser);
  assert.strictEqual(identity.available, true);
  assert.strictEqual(identity.verified, true);
  assert.strictEqual(identity.name, '홍길동');
  assert.strictEqual(identity.gender, 'female');
  assert.strictEqual(identity.birthYear, 1991);
});

test('본인확인 전 계정에는 실명·성별·생년월일이 실리지 않는다', () => {
  const { identity } = buildApplicantIdentity({
    ...verifiedUser,
    identityVerified: false,
  });
  assert.strictEqual(identity.verified, false);
  assert.strictEqual(identity.name, '');
  assert.strictEqual(identity.gender, '');
  assert.strictEqual(identity.birthYear, null);
  assert.strictEqual(identity.birthMonth, null);
  assert.strictEqual(identity.birthDay, null);
  // 닉네임은 본인확인과 무관한 공개 정보라 그대로 나간다.
  assert.strictEqual(identity.nickname, '냥냥이');
});

test('확인 여부는 성별 유무로 추측되지 않는다', () => {
  // 본인확인은 마쳤는데 성별이 비어 있는 계정 — 예전 화면 판정('성별이 비면
  // 미확인')이 틀리는 자리다. payload는 사실을 그대로 말해야 한다.
  const { identity } = buildApplicantIdentity({
    identityVerified: true,
    nickname: '냥냥이',
    name: '홍길동',
  });
  assert.strictEqual(identity.verified, true);
  assert.strictEqual(identity.gender, '');
  assert.strictEqual(identity.name, '홍길동');
});

test('탈퇴·삭제된 계정은 available:false 하나로 끝난다', () => {
  for (const u of [null, { ...verifiedUser, accountStatus: 'withdrawn' }]) {
    const { identity } = buildApplicantIdentity(u);
    assert.strictEqual(identity.available, false);
    // 실명은 물론 확인 여부조차 나가지 않는다 — 말할 근거가 없다.
    assert.strictEqual(identity.verified, undefined);
    assert.strictEqual(identity.name, undefined);
  }
});

test('주민등록번호 같은 값은 payload에 아예 들어가지 않는다', () => {
  const { identity } = buildApplicantIdentity({
    ...verifiedUser,
    // users 문서에 무엇이 더 있든 payload는 정해진 키만 담는다.
    ci: 'CI_VALUE',
    di: 'DI_VALUE',
    phone: '010-0000-0000',
    residentNumber: '910307-1234567',
  });
  const allowed = [
    'available',
    'verified',
    'nickname',
    'name',
    'gender',
    'birthYear',
    'birthMonth',
    'birthDay',
  ];
  assert.deepStrictEqual(Object.keys(identity).sort(), [...allowed].sort());
});

let passed = 0;
for (const [name, fn] of cases) {
  try {
    fn();
    console.log(`  ok  ${name}`);
    passed++;
  } catch (e) {
    console.error(`  FAIL ${name}\n       ${e.message}`);
  }
}
console.log(`\n${passed}/${cases.length} passed`);
if (passed !== cases.length) process.exit(1);

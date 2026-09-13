// 파티 사전질문 규칙 자체 검증 — `npm run check:questions`.
//
// 여기서 못 박는 것은 네 가지다.
// 1. **기존 파티 무영향.** applicationApprovalMode가 없으면 무조건 'auto'이고
//    질문도 빈 배열이다. 이게 깨지면 운영 중인 파티 전체가 승인 대기로 바뀐다.
// 2. **금지 질문은 실제로 막힌다.** 안내 문구만 있고 통과되면 의미가 없다.
// 3. **정상 질문은 절대 막히지 않는다.** 오탐이 더 나쁘다 — "연락 가능한
//    시간대"가 막히면 호스트가 기능 자체를 못 쓴다.
// 4. **필수 답변 누락은 서버가 잡는다.** 클라이언트만 믿지 않는다.
// 5. **프로필 사진은 호스트가 요청한 파티에서만 필수다.** 필드가 없는 기존
//    승인제 파티는 예전처럼 사진 없이도 신청이 된다.

process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'selfcheck';

const assert = require('assert');
const {
  MAX_QUESTIONS,
  MAX_ANSWER_LENGTH,
  MAX_PHOTOS,
  REQUIRE_PHOTOS_FIELD,
  approvalModeOf,
  requiresApproval,
  requiresApplicantPhotos,
  questionsOf,
  scanQuestionText,
  validateQuestions,
  validateAnswers,
  validatePhotos,
} = require('./applicationQuestions');

const cases = [];
const test = (name, fn) => cases.push([name, fn]);

const MANUAL_PARTY = {
  applicationApprovalMode: 'manual',
  applicationQuestions: [
    { id: 'q1', text: '참여 이유가 무엇인가요?', required: true, order: 0 },
    { id: 'q2', text: '어떤 일을 하시나요?', required: false, order: 1 },
  ],
};

// ── 1. 기존 파티 무영향 ──────────────────────────────────────────────────────

test('applicationApprovalMode가 없으면 auto — 기존 운영 파티 보호', () => {
  assert.strictEqual(approvalModeOf({}), 'auto');
  assert.strictEqual(approvalModeOf({ title: '금요일 와인 파티' }), 'auto');
  assert.strictEqual(requiresApproval({}), false);
});

test('알 수 없는 값도 auto로 떨어진다 — 오타로 신청이 멈추면 안 된다', () => {
  assert.strictEqual(approvalModeOf({ applicationApprovalMode: 'MANUAL' }), 'auto');
  assert.strictEqual(approvalModeOf({ applicationApprovalMode: 'approval' }), 'auto');
  assert.strictEqual(approvalModeOf({ applicationApprovalMode: null }), 'auto');
});

test('즉시확정 파티는 질문 정의가 남아 있어도 질문이 없다', () => {
  const reverted = {
    applicationApprovalMode: 'auto',
    applicationQuestions: [{ id: 'q1', text: '참여 이유', required: true, order: 0 }],
  };
  assert.deepStrictEqual(questionsOf(reverted), []);
});

test('즉시확정 파티는 답변 검증 자체를 건너뛴다', () => {
  const r = validateAnswers(questionsOf({}), null);
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.answers, null);
  assert.strictEqual(r.snapshot, null);
});

test('승인제 파티는 질문을 order 순으로 읽는다', () => {
  const shuffled = {
    applicationApprovalMode: 'manual',
    applicationQuestions: [
      { id: 'b', text: '두번째', required: false, order: 1 },
      { id: 'a', text: '첫번째', required: true, order: 0 },
    ],
  };
  assert.deepStrictEqual(questionsOf(shuffled).map((q) => q.id), ['a', 'b']);
});

// ── 2. 금지 질문은 실제로 막힌다 ─────────────────────────────────────────────

const BANNED_SAMPLES = [
  '전화번호 적어주세요',
  '카톡 아이디 알려주세요',
  '주민번호 입력',
  '계좌번호 적어주세요',
  '휴대폰 번호 남겨주세요',
  '카카오톡 ID 공유해주세요',
  '인스타 아이디 알려주세요',
  '신분증 사진 첨부해주세요',
  '상세주소 기재해주세요',
  '연락처 남겨주세요',
  '카드번호 입력해주세요',
  '주민등록번호를 알려주세요',
  '운전면허 정보 적어주세요',
  '집주소 써주세요',
];

for (const sample of BANNED_SAMPLES) {
  test(`금지 질문 차단: "${sample}"`, () => {
    assert.strictEqual(scanQuestionText(sample).banned, true, `통과되면 안 됨: ${sample}`);
  });
}

test('띄어쓰기로 우회할 수 없다', () => {
  assert.strictEqual(scanQuestionText('주 민 등 록 번 호').banned, true);
  assert.strictEqual(scanQuestionText('카 톡  아 이 디').banned, true);
});

test('영문 대소문자로 우회할 수 없다', () => {
  assert.strictEqual(scanQuestionText('카톡 ID 알려주세요').banned, true);
  assert.strictEqual(scanQuestionText('인스타 Id 남겨주세요').banned, true);
});

test('금지 질문이 하나라도 있으면 저장 자체가 거부된다', () => {
  const r = validateQuestions([
    { id: 'q1', text: '참여 이유가 무엇인가요?', required: true },
    { id: 'q2', text: '전화번호 적어주세요', required: false },
  ]);
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.code, 'failed-precondition');
});

// ── 3. 정상 질문은 절대 막히지 않는다 (오탐 방지) ────────────────────────────

const ALLOWED_SAMPLES = [
  '연락 가능한 시간대가 언제인가요?',
  '어떤 일을 하시나요?',
  '참여 이유가 무엇인가요?',
  '파티에 몇 번 참여해보셨나요?',
  '술은 얼마나 드시나요?',
  '어느 지역에서 오시나요?',
  '자기소개를 간단히 부탁드려요',
  '이 파티를 어떻게 알게 되셨나요?',
  '기대하는 점이 있다면 적어주세요',
  '음식 알레르기가 있으신가요?',
  '함께 오는 일행이 있나요?',
  '지난 파티 후기를 남겨주세요',
];

for (const sample of ALLOWED_SAMPLES) {
  test(`정상 질문 통과: "${sample}"`, () => {
    assert.strictEqual(scanQuestionText(sample).banned, false, `막히면 안 됨: ${sample}`);
  });
}

test("'연락처'가 아닌 '연락'은 명사 목록에 없다 — 시간대 질문 보호", () => {
  assert.strictEqual(scanQuestionText('연락 가능한 시간을 적어주세요').banned, false);
});

test("'번호' 단독은 막지 않는다 — 참여 횟수 질문 보호", () => {
  assert.strictEqual(scanQuestionText('몇 번 참여하셨는지 적어주세요').banned, false);
});

test('민감 명사가 있어도 요구 동사가 없으면 통과한다', () => {
  assert.strictEqual(scanQuestionText('연락처 공개는 하지 않으셔도 돼요').banned, false);
  assert.strictEqual(scanQuestionText('주소지 기준 가까운 편인가요?').banned, false);
});

// ── 질문 저장 규칙 ───────────────────────────────────────────────────────────

test(`질문은 최대 ${MAX_QUESTIONS}개까지만`, () => {
  const six = Array.from({ length: MAX_QUESTIONS + 1 }, (_, i) => ({
    id: `q${i}`, text: `질문 ${i}`, required: false,
  }));
  assert.strictEqual(validateQuestions(six).ok, false);
  const five = six.slice(0, MAX_QUESTIONS);
  assert.strictEqual(validateQuestions(five).ok, true);
});

test('빈 질문은 저장되지 않는다', () => {
  assert.strictEqual(validateQuestions([{ id: 'q1', text: '   ', required: false }]).ok, false);
});

test('order는 서버가 배열 순서로 다시 매긴다', () => {
  const r = validateQuestions([
    { id: 'a', text: '첫번째', required: true, order: 99 },
    { id: 'b', text: '두번째', required: false, order: 3 },
  ]);
  assert.strictEqual(r.ok, true);
  assert.deepStrictEqual(r.questions.map((q) => q.order), [0, 1]);
});

test('기존 질문 id는 보존된다 — 접수된 답변이 미아가 되면 안 된다', () => {
  const r = validateQuestions([{ id: 'q1', text: '참여 이유', required: true }]);
  assert.strictEqual(r.questions[0].id, 'q1');
});

test('id가 겹치면 서버가 새로 붙인다', () => {
  const r = validateQuestions([
    { id: 'dup', text: '첫번째', required: false },
    { id: 'dup', text: '두번째', required: false },
  ]);
  assert.strictEqual(r.ok, true);
  assert.notStrictEqual(r.questions[0].id, r.questions[1].id);
});

test('질문 없음(빈 배열/null)도 정상이다', () => {
  assert.deepStrictEqual(validateQuestions([]).questions, []);
  assert.deepStrictEqual(validateQuestions(null).questions, []);
});

// ── 4. 답변 검증 ─────────────────────────────────────────────────────────────

test('필수 질문에 답이 없으면 서버가 막는다', () => {
  const defs = questionsOf(MANUAL_PARTY);
  const r = validateAnswers(defs, { q2: '개발자예요' });
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.code, 'invalid-argument');
});

test('필수 질문에 공백만 보내도 막는다', () => {
  const defs = questionsOf(MANUAL_PARTY);
  assert.strictEqual(validateAnswers(defs, { q1: '   ' }).ok, false);
});

test('선택 질문의 빈 답은 저장하지 않는다', () => {
  const defs = questionsOf(MANUAL_PARTY);
  const r = validateAnswers(defs, { q1: '분위기가 좋아 보여서요', q2: '' });
  assert.strictEqual(r.ok, true);
  assert.deepStrictEqual(Object.keys(r.answers), ['q1']);
});

test(`답변은 ${MAX_ANSWER_LENGTH}자까지`, () => {
  const defs = questionsOf(MANUAL_PARTY);
  const long = 'ㄱ'.repeat(MAX_ANSWER_LENGTH + 1);
  assert.strictEqual(validateAnswers(defs, { q1: long }).ok, false);
  const exact = 'ㄱ'.repeat(MAX_ANSWER_LENGTH);
  assert.strictEqual(validateAnswers(defs, { q1: exact }).ok, true);
});

test('정의에 없는 질문 id로 답이 오면 막는다 — 질문이 바뀐 상태', () => {
  const defs = questionsOf(MANUAL_PARTY);
  const r = validateAnswers(defs, { q1: '답변', qX: '유령 질문' });
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.code, 'failed-precondition');
});

test('질문 문구 스냅샷은 신청 1건당 한 번만 남는다', () => {
  const defs = questionsOf(MANUAL_PARTY);
  const r = validateAnswers(defs, { q1: '분위기가 좋아 보여서요' });
  assert.strictEqual(r.snapshot.length, 2);
  assert.deepStrictEqual(r.snapshot[0], {
    id: 'q1', text: '참여 이유가 무엇인가요?', required: true,
  });
  // 답변 쪽에는 문구가 복사되지 않는다.
  assert.deepStrictEqual(r.answers, { q1: '분위기가 좋아 보여서요' });
});

// ── 사진 검증 ────────────────────────────────────────────────────────────────

test(`사진은 최대 ${MAX_PHOTOS}장까지`, () => {
  const six = Array.from({ length: MAX_PHOTOS + 1 }, (_, i) => ({ id: `p${i}` }));
  assert.strictEqual(validatePhotos(six).ok, false);
  assert.strictEqual(validatePhotos(six.slice(0, MAX_PHOTOS)).ok, true);
});

test('사진 id에 경로 구분자를 넣을 수 없다 — 경로 조작 방지', () => {
  assert.strictEqual(validatePhotos([{ id: '../../secret' }]).ok, false);
  assert.strictEqual(validatePhotos([{ id: 'a/b' }]).ok, false);
  assert.strictEqual(validatePhotos([{ id: 'photo_1-ok' }]).ok, true);
});

test('사진 없음도 정상이다 — 요청하지 않은 파티에서는', () => {
  assert.strictEqual(validatePhotos(null).photos, null);
  assert.strictEqual(validatePhotos([]).photos, null);
});

// ── 프로필 사진 요청 옵션 ────────────────────────────────────────────────────

test('필드가 없는 기존 승인제 파티는 사진을 요구하지 않는다', () => {
  assert.strictEqual(requiresApplicantPhotos(MANUAL_PARTY), false);
  assert.strictEqual(requiresApplicantPhotos({}), false);
  assert.strictEqual(requiresApplicantPhotos(null), false);
});

test('호스트가 켠 승인제 파티만 사진을 요구한다', () => {
  const on = { ...MANUAL_PARTY, [REQUIRE_PHOTOS_FIELD]: true };
  assert.strictEqual(requiresApplicantPhotos(on), true);

  const off = { ...MANUAL_PARTY, [REQUIRE_PHOTOS_FIELD]: false };
  assert.strictEqual(requiresApplicantPhotos(off), false);
});

test('즉시확정 파티는 플래그가 남아 있어도 사진을 요구하지 않는다', () => {
  const auto = { applicationApprovalMode: 'auto', [REQUIRE_PHOTOS_FIELD]: true };
  assert.strictEqual(requiresApplicantPhotos(auto), false);
});

test('요청한 파티에서는 사진 0장이 거부된다', () => {
  const opt = { required: true };
  assert.strictEqual(validatePhotos(null, opt).ok, false);
  assert.strictEqual(validatePhotos(undefined, opt).ok, false);
  assert.strictEqual(validatePhotos([], opt).ok, false);
  // 중복만 들어와 전부 걸러져도 "안 낸 것"이다.
  assert.strictEqual(
    validatePhotos([{ id: 'same' }, { id: 'same' }], opt).photos.length,
    1,
  );
});

test('요청한 파티에서 1장·5장은 통과한다', () => {
  const opt = { required: true };
  assert.strictEqual(validatePhotos([{ id: 'p1' }], opt).ok, true);
  const five = Array.from({ length: MAX_PHOTOS }, (_, i) => ({ id: `p${i}` }));
  const r = validatePhotos(five, opt);
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.photos.length, MAX_PHOTOS);
  // 최대 장수 제한은 요청 여부와 무관하게 그대로다.
  assert.strictEqual(validatePhotos([...five, { id: 'p9' }], opt).ok, false);
});

let failed = 0;
for (const [name, fn] of cases) {
  try {
    fn();
    console.log(`  ✓ ${name}`);
  } catch (e) {
    failed += 1;
    console.error(`  ✗ ${name}\n    ${e.message}`);
  }
}
console.log(
  failed === 0
    ? `\n파티 사전질문 규칙 검증 통과 — ${cases.length}건`
    : `\n실패 ${failed}건 / 전체 ${cases.length}건`,
);
process.exit(failed === 0 ? 0 : 1);

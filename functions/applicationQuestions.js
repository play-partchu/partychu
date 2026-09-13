// ── 파티 사전질문(승인제) 정의·답변 검증 ────────────────────────────────────
//
// 승인제 파티에서 호스트가 만드는 질문과, 신청자가 내는 답변의 **정본 판정**을
// 여기 모아 둔다. 앱에도 같은 규칙이 있지만(lib/models/party_application_form.dart)
// 그쪽은 사용자가 저장 버튼을 누르기 전에 알려주기 위한 것이고, **막는 것은
// 언제나 여기**다 — 파티 문서는 setPartyApplicationForm 콜러블만 쓸 수 있고
// 그 콜러블이 이 모듈을 부른다.
//
// 모든 함수는 순수하다 — Firestore도 HttpsError도 모르므로 자체 검증에서
// 그대로 부를 수 있다. 호출부가 결과를 보고 HttpsError로 바꾼다.

/// 승인 방식 — 플레이스 룸 예약(RoomApprovalMode)과 같은 키를 쓴다.
/// 필드가 없는 **기존 파티는 전부 'auto'** 다. 이 기본값이 깨지면 운영 중인
/// 파티 전체가 갑자기 승인 대기로 바뀌므로 절대 바꾸지 않는다.
const APPROVAL_AUTO = 'auto';
const APPROVAL_MANUAL = 'manual';

const MAX_QUESTIONS = 5;
const MAX_QUESTION_LENGTH = 100;
const MAX_ANSWER_LENGTH = 500;
const MAX_PHOTOS = 5;

/// 승인 심사용 프로필 사진을 신청자에게 요청할지 담는 필드.
/// 앱(lib/models/party_application_form.dart)과 **같은 이름**이어야 한다.
const REQUIRE_PHOTOS_FIELD = 'requireApplicantPhotos';

/// 파티 문서에서 승인 방식을 읽는다. 알 수 없는 값도 'auto'로 떨어뜨린다 —
/// 오타 하나로 기존 파티의 신청이 멈추면 안 된다(openStateOf와 같은 방침).
function approvalModeOf(partyData) {
  const raw = partyData && partyData.applicationApprovalMode;
  return raw === APPROVAL_MANUAL ? APPROVAL_MANUAL : APPROVAL_AUTO;
}

/// 이 파티가 호스트 승인을 거쳐야 하는지.
function requiresApproval(partyData) {
  return approvalModeOf(partyData) === APPROVAL_MANUAL;
}

/// 이 파티가 신청자에게 프로필 사진을 요구하는지.
///
/// **필드가 없으면 false**다. 예전 승인제 파티에는 이 설정 자체가 없었고,
/// 그때도 사진은 없어도 신청이 됐다(여기서 최소 장수를 요구한 적이 없다).
/// 미설정을 true로 읽으면 운영 중인 파티의 신청이 갑자기 막힌다.
///
/// 승인제가 아니면 언제나 false다 — questionsOf와 같은 규칙이라, 승인제로
/// 만들었다가 되돌린 파티에 플래그가 남아 있어도 사진을 요구하지 않는다.
function requiresApplicantPhotos(partyData) {
  if (!requiresApproval(partyData)) return false;
  return !!(partyData && partyData[REQUIRE_PHOTOS_FIELD] === true);
}

/// 파티 문서에 저장된 질문 목록을 정규화해서 읽는다.
///
/// 승인제가 아니면 **언제나 빈 배열**이다 — 예전에 승인제로 만들었다가 즉시
/// 확정으로 되돌린 파티에 질문 정의가 남아 있어도 신청 화면에 뜨지 않는다.
function questionsOf(partyData) {
  if (!requiresApproval(partyData)) return [];
  const raw = partyData && partyData.applicationQuestions;
  if (!Array.isArray(raw)) return [];
  return raw
    .filter((q) => q && typeof q === 'object' && typeof q.id === 'string' && q.id)
    .map((q, i) => ({
      id: q.id,
      text: typeof q.text === 'string' ? q.text : '',
      required: q.required === true,
      order: Number.isInteger(q.order) ? q.order : i,
    }))
    .sort((a, b) => a.order - b.order)
    .slice(0, MAX_QUESTIONS);
}

// ── 금지 개인정보 질문 탐지 ──────────────────────────────────────────────────
//
// 오탐이 더 나쁘다. "연락 가능한 시간대", "어떤 일을 하시나요?", "참여 이유"
// 같은 정상 질문까지 막으면 호스트가 기능 자체를 못 쓴다. 그래서 2단으로
// 나눈다.
//
//   A. 단독 차단 — 그 단어가 나온 것만으로 개인정보 요구가 확실한 것.
//      ('주민등록번호'가 들어간 질문이 정상일 수는 없다)
//   B. 조합 차단 — 명사만으로는 정상일 수 있어서 **요구 동사와 함께**일 때만.
//      ('연락처'는 "연락처 공개 안 해도 되나요?"처럼 쓰일 수 있지만
//       '연락처 남겨주세요'는 명백하다)
//
// 판정 전에 공백을 모두 지운다 — '카톡 아이디'와 '카톡아이디'가 갈리면
// 띄어쓰기 하나로 우회된다.

/// 단독으로 차단하는 표현(공백 제거 기준).
const BANNED_ALONE = [
  // 신분 — 어떤 맥락에서도 파티 참여에 필요하지 않다.
  '주민등록번호', '주민번호', '신분증', '여권번호', '운전면허',
  // 금융
  '계좌번호', '카드번호', '카드정보', '카드번',
  // 메신저·SNS 아이디
  '카톡아이디', '카톡id', '카카오톡아이디', '카카오톡id', '카카오아이디',
  '오픈카톡', '오픈채팅방',
  '인스타아이디', '인스타id', '인스타그램아이디', '텔레그램아이디', '라인아이디',
  // 주소 — '어느 동네 사세요'(지역)와 달리 상세주소는 특정 개인을 짚는다.
  '상세주소', '집주소', '자택주소', '거주지주소', '우편번호',
];

/// 조합 차단용 명사. 이것만으로는 막지 않는다.
///
/// '연락'이 아니라 '연락처'인 점이 중요하다 — "연락 가능한 시간대"는 정상
/// 질문이고 반드시 통과해야 한다. 마찬가지로 '번호' 단독은 넣지 않는다
/// ("몇 번 참여하셨나요"가 걸린다).
const SENSITIVE_NOUNS = [
  '전화번호', '휴대폰', '휴대전화', '핸드폰', '폰번호', '연락처',
  '계좌', '카드', '아이디', '주소', '생년월일', '실명',
];

/// 조합 차단용 요구 동사.
const DEMAND_VERBS = [
  '적어', '써주', '써주세요', '알려', '입력', '기입', '기재', '남겨', '남기',
  '보내', '공유', '제출', '작성', '올려', '첨부',
];

/// 판정용 정규화 — 공백 제거 + 소문자화.
function normalizeForScan(text) {
  return String(text || '').replace(/\s+/g, '').toLowerCase();
}

/**
 * 질문 문구가 금지 개인정보를 요구하는지 판정한다.
 *
 * @returns {{banned: boolean, reason: string|null, matched: string|null}}
 */
function scanQuestionText(text) {
  const s = normalizeForScan(text);
  if (!s) return { banned: false, reason: null, matched: null };

  for (const word of BANNED_ALONE) {
    if (s.includes(word)) {
      return {
        banned: true,
        matched: word,
        reason: `'${word}'처럼 파티 참여에 불필요한 개인정보는 질문으로 만들 수 없어요.`,
      };
    }
  }

  const noun = SENSITIVE_NOUNS.find((n) => s.includes(n));
  if (noun) {
    const verb = DEMAND_VERBS.find((v) => s.includes(v));
    if (verb) {
      return {
        banned: true,
        matched: noun,
        reason: `'${noun}'를 요구하는 질문은 만들 수 없어요. 파티 참여에 꼭 필요한 내용만 물어주세요.`,
      };
    }
  }

  return { banned: false, reason: null, matched: null };
}

/**
 * 호스트가 저장하려는 질문 목록을 검증하고 **저장할 형태로** 돌려준다.
 *
 * 순서(order)는 클라이언트가 보낸 배열 순서로 서버가 다시 매긴다 — 클라이언트가
 * 보낸 order 값을 그대로 믿으면 중복·구멍이 생긴다.
 *
 * @returns {{ok: true, questions: Array}|{ok: false, code: string, message: string}}
 */
function validateQuestions(rawQuestions) {
  if (rawQuestions === undefined || rawQuestions === null) {
    return { ok: true, questions: [] };
  }
  if (!Array.isArray(rawQuestions)) {
    return { ok: false, code: 'invalid-argument', message: '사전질문 형식이 올바르지 않아요.' };
  }
  if (rawQuestions.length > MAX_QUESTIONS) {
    return {
      ok: false,
      code: 'invalid-argument',
      message: `사전질문은 최대 ${MAX_QUESTIONS}개까지 만들 수 있어요.`,
    };
  }

  const questions = [];
  const seenIds = new Set();
  for (let i = 0; i < rawQuestions.length; i += 1) {
    const q = rawQuestions[i];
    if (!q || typeof q !== 'object') {
      return { ok: false, code: 'invalid-argument', message: '사전질문 형식이 올바르지 않아요.' };
    }
    const text = typeof q.text === 'string' ? q.text.trim() : '';
    if (!text) {
      return { ok: false, code: 'invalid-argument', message: '내용이 비어 있는 질문이 있어요.' };
    }
    if (text.length > MAX_QUESTION_LENGTH) {
      return {
        ok: false,
        code: 'invalid-argument',
        message: `질문은 ${MAX_QUESTION_LENGTH}자까지 쓸 수 있어요.`,
      };
    }
    const scan = scanQuestionText(text);
    if (scan.banned) {
      return { ok: false, code: 'failed-precondition', message: scan.reason };
    }
    // id는 클라이언트가 만든 값을 쓰되, 없거나 겹치면 서버가 붙인다 —
    // 이미 접수된 신청의 answers가 질문 id로 묶여 있어서 **기존 id는 보존**해야
    // 한다(호스트가 순서만 바꿨는데 답변이 통째로 미아가 되면 안 된다).
    let id = typeof q.id === 'string' && q.id.trim() ? q.id.trim().slice(0, 40) : '';
    if (!id || seenIds.has(id)) id = `q${i + 1}_${Date.now().toString(36)}`;
    seenIds.add(id);
    questions.push({ id, text, required: q.required === true, order: i });
  }
  return { ok: true, questions };
}

/**
 * 신청자가 보낸 답변을 파티 문서의 질문 정의로 검증한다.
 *
 * 클라이언트가 보낸 질문 정의는 쓰지 않는다 — 인자로 받는 questions는 언제나
 * 서버가 파티 문서에서 다시 읽은 것이어야 한다.
 *
 * @returns {{ok: true, answers: Object, snapshot: Array}|{ok: false, code, message}}
 */
function validateAnswers(questions, rawAnswers) {
  const defs = Array.isArray(questions) ? questions : [];
  if (defs.length === 0) return { ok: true, answers: null, snapshot: null };

  const src = rawAnswers && typeof rawAnswers === 'object' && !Array.isArray(rawAnswers)
    ? rawAnswers
    : {};

  const known = new Set(defs.map((q) => q.id));
  for (const key of Object.keys(src)) {
    if (!known.has(key)) {
      // 질문이 수정돼서 사라진 id로 답이 오면 조용히 버리지 않고 막는다 —
      // 호스트가 방금 질문을 바꾼 상태일 수 있으므로 다시 불러오게 한다.
      return {
        ok: false,
        code: 'failed-precondition',
        message: '사전질문이 변경되었어요. 화면을 새로고침한 뒤 다시 신청해주세요.',
      };
    }
  }

  const answers = {};
  for (const q of defs) {
    const raw = src[q.id];
    const text = typeof raw === 'string' ? raw.trim() : '';
    if (!text) {
      if (q.required) {
        return {
          ok: false,
          code: 'invalid-argument',
          message: '필수 사전질문에 답변해주세요.',
        };
      }
      continue; // 선택 질문의 빈 답은 아예 저장하지 않는다.
    }
    if (text.length > MAX_ANSWER_LENGTH) {
      return {
        ok: false,
        code: 'invalid-argument',
        message: `답변은 ${MAX_ANSWER_LENGTH}자까지 쓸 수 있어요.`,
      };
    }
    answers[q.id] = text;
  }

  // 질문 문구는 **답변마다가 아니라 신청 1건당 한 번만** 스냅샷한다.
  // 호스트가 나중에 질문을 고쳐도 이 사람이 무엇에 답한 것인지 남아야 한다.
  const snapshot = defs.map((q) => ({ id: q.id, text: q.text, required: q.required }));
  return { ok: true, answers: Object.keys(answers).length > 0 ? answers : null, snapshot };
}

/**
 * 신청자가 보낸 사진 목록을 검증한다.
 *
 * 파일 자체는 Firebase Storage에 있고(권한은 storage.rules), 여기서는 신청
 * 문서에 남길 **참조만** 확인한다. 경로는 서버가 다시 만들어 붙이므로
 * 클라이언트가 보낸 path는 쓰지 않는다.
 *
 * @param {boolean} [options.required] 호스트가 사진을 요청한 파티면 true —
 *   그때만 **최소 1장**을 강제한다. 앱에서 버튼을 막는 것만으로는 성립하지
 *   않으므로(앱을 거치지 않고 콜러블을 부르면 그만) 여기가 실제 관문이다.
 */
function validatePhotos(rawPhotos, options) {
  const required = !!(options && options.required);
  const missing = {
    ok: false,
    code: 'invalid-argument',
    message: '승인 심사를 위해 프로필 사진을 1장 이상 올려주세요.',
  };
  if (rawPhotos === undefined || rawPhotos === null) {
    return required ? missing : { ok: true, photos: null };
  }
  if (!Array.isArray(rawPhotos)) {
    return { ok: false, code: 'invalid-argument', message: '사진 형식이 올바르지 않아요.' };
  }
  if (rawPhotos.length === 0) {
    return required ? missing : { ok: true, photos: null };
  }
  if (rawPhotos.length > MAX_PHOTOS) {
    return {
      ok: false,
      code: 'invalid-argument',
      message: `사진은 최대 ${MAX_PHOTOS}장까지 올릴 수 있어요.`,
    };
  }
  const photos = [];
  const seen = new Set();
  for (const p of rawPhotos) {
    const id = typeof p === 'string' ? p : p && typeof p.id === 'string' ? p.id : '';
    const clean = id.trim().slice(0, 60);
    // 경로 조작 방지 — id는 파일명 한 조각이며 구분자를 담을 수 없다.
    if (!clean || !/^[A-Za-z0-9_-]+$/.test(clean)) {
      return { ok: false, code: 'invalid-argument', message: '사진 정보가 올바르지 않아요.' };
    }
    if (seen.has(clean)) continue;
    seen.add(clean);
    photos.push({ id: clean });
  }
  // 중복 id만 들어와 전부 걸러진 경우도 "안 낸 것"이다.
  if (photos.length === 0 && required) return missing;
  return { ok: true, photos: photos.length > 0 ? photos : null };
}

module.exports = {
  APPROVAL_AUTO,
  APPROVAL_MANUAL,
  MAX_QUESTIONS,
  MAX_QUESTION_LENGTH,
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
};

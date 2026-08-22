// ══════════════════════════════════════════════════════════════════════════
// 닉네임 — **정규화·검증·중복방지의 정본**.
//
// 닉네임으로 사람을 찾을 수 있어야 하므로(관리자 회원 검색·향후 사용자 검색)
// 같은 닉네임을 두 계정이 쓸 수 없다. 그런데 "users에서 where nickname == 로
// 찾아보고 없으면 저장"은 **중복을 막지 못한다** — 두 사람이 동시에 조회하면
// 둘 다 "없음"을 보고 둘 다 저장한다. 그래서 닉네임 하나당 문서 하나를 두고
// (`nicknames/{normalized}`) 그 문서의 생성을 트랜잭션으로 경쟁시킨다. 문서 id가
// 곧 잠금이라 동시에 두 명이 같은 이름을 가져갈 수 없다.
//
// ── 클라이언트는 nickname을 직접 쓰지 못한다 ─────────────────────────────
// firestore.rules가 users.nickname / nicknameLower / nicknames 컬렉션을 전부
// 잠근다. 앱은 이 파일의 setNickname 콜러블만 부를 수 있다 — 앱에서만 검사하면
// 앱을 고치거나 REST로 직접 쓰는 것으로 특수문자·중복 닉네임이 그대로 들어온다.
//
// ── 정규화 규칙 (앱과 **글자 하나까지 같아야 한다**) ─────────────────────
//   1. 앞뒤 공백 제거(trim)
//   2. 유니코드 NFC 정규화 — 한글은 자모 조합형과 완성형이 눈에 똑같이 보이지만
//      코드포인트가 다르다. 정규화하지 않으면 '냥이'와 '냥이'가 다른 문서가 된다.
//   3. 중복 판정용 키는 여기에 소문자 변환까지 한 값 → PartyChu == partychu
//
// ── 허용 문자 ────────────────────────────────────────────────────────────
// 완성형 한글(가-힣) · 영문 · 숫자만. 공백·특수문자·이모지·자모 단독은 막는다.
// 자모 단독(ㄱ, ㅏ, ㅑㅑ 등)은 완성형 범위 밖이라 허용 정규식이 자연히 걸러낸다.
// ══════════════════════════════════════════════════════════════════════════

const admin = require('firebase-admin');
const { onCall, HttpsError } = require('firebase-functions/v2/https');

const REGION = 'asia-northeast3';

/// 닉네임 예약 문서가 사는 곳.
const COLLECTION = 'nicknames';

/// 길이 제한 — 기존 앱 정책(NicknameService)과 같은 값이다. 한쪽만 바꾸면
/// "앱에서는 저장되는데 서버가 거부하는" 상태가 된다.
const MIN_LENGTH = 2;
const MAX_LENGTH = 12;

/// 허용 문자: 완성형 한글 + 영문 + 숫자. 그 외 전부 거부.
const ALLOWED = /^[가-힣a-zA-Z0-9]+$/;

/// 사용자에게 그대로 보여주는 문구 — 앱과 같은 문장을 쓴다.
const MESSAGES = {
  empty: '닉네임을 입력해주세요.',
  length: `닉네임은 ${MIN_LENGTH}~${MAX_LENGTH}자로 입력해주세요.`,
  charset: '한글, 영문, 숫자만 사용할 수 있어요.',
  taken: '이미 사용 중인 닉네임이에요. 다른 닉네임을 입력해주세요.',
};

/**
 * 저장될 형태로 다듬는다 — 앞뒤 공백만 제거하고 NFC로 맞춘다.
 * **내부 공백은 지우지 않는다.** 지워서 통과시키면 사용자가 입력한 것과 다른
 * 닉네임이 저장된다(예전 sanitize는 연속 공백을 하나로 줄여 '냥 냥이'를
 * 그대로 통과시켰다) — 공백은 여기서 고치지 않고 검증에서 거부한다.
 */
function sanitize(raw) {
  return String(raw == null ? '' : raw).trim().normalize('NFC');
}

/**
 * 중복 판정용 키. 대소문자를 구분하지 않으므로 PartyChu와 partychu는 같다.
 * Firestore 문서 id로 그대로 쓴다.
 */
function normalize(raw) {
  return sanitize(raw).toLowerCase();
}

/**
 * 유효하면 null, 아니면 사용자에게 보여줄 메시지를 돌려준다.
 * 길이는 **코드포인트 기준**으로 센다 — 서로게이트 쌍이 2자로 세어지면
 * 이모지 하나가 2자가 되어 길이 규칙이 문자 수와 어긋난다.
 */
function validate(raw) {
  const v = sanitize(raw);
  if (!v) return MESSAGES.empty;
  const len = [...v].length;
  if (len < MIN_LENGTH || len > MAX_LENGTH) return MESSAGES.length;
  if (!ALLOWED.test(v)) return MESSAGES.charset;
  return null;
}

/**
 * 닉네임을 원자적으로 선점하고 users 문서를 갱신한다.
 *
 * 한 트랜잭션 안에서 세 가지를 함께 처리한다 — 중간에 끊기면 "예약은 됐는데
 * 프로필은 옛 이름"처럼 어긋난 상태가 남기 때문이다.
 *   ① 새 이름 예약 문서 생성(이미 남이 쓰고 있으면 여기서 실패)
 *   ② users/{uid}.nickname 갱신
 *   ③ 이전 이름 예약 해제
 *
 * @returns {Promise<{nickname: string, normalized: string, changed: boolean}>}
 */
async function claimNickname(db, uid, raw) {
  const error = validate(raw);
  if (error) throw new HttpsError('invalid-argument', error);

  const nickname = sanitize(raw);
  const normalized = normalize(raw);
  const userRef = db.collection('users').doc(uid);
  const nextRef = db.collection(COLLECTION).doc(normalized);

  return db.runTransaction(async (tx) => {
    // ⚠️ 트랜잭션 안의 읽기는 **쓰기보다 먼저** 모두 끝내야 한다(Firestore 제약).
    const [nextSnap, userSnap] = await Promise.all([tx.get(nextRef), tx.get(userRef)]);

    const owner = nextSnap.exists ? nextSnap.get('uid') : null;
    if (owner && owner !== uid) throw new HttpsError('already-exists', MESSAGES.taken);

    const prevNickname = userSnap.exists ? sanitize(userSnap.get('nickname') || '') : '';
    const prevNormalized = prevNickname ? normalize(prevNickname) : '';

    // 대소문자만 바꾸는 것도 변경이다('partychu' → 'PartyChu'). 예약 문서 id는
    // 같으므로 해제하지 않고 users 표시값만 갱신한다.
    if (prevNormalized === normalized && prevNickname === nickname) {
      return { nickname, normalized, changed: false };
    }

    tx.set(nextRef, {
      uid,
      nickname,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    // nicknameLower는 관리자 회원 검색이 쓰는 파생 필드다. 트리거가 뒤따라
    // 채우지만, 여기서 함께 써 두면 저장 직후 검색에도 바로 잡힌다.
    tx.set(
      userRef,
      { nickname, nicknameLower: normalized },
      { merge: true },
    );
    if (prevNormalized && prevNormalized !== normalized) {
      tx.delete(db.collection(COLLECTION).doc(prevNormalized));
    }
    return { nickname, normalized, changed: true };
  });
}

/**
 * 탈퇴·닉네임 삭제 시 예약을 푼다 — **탈퇴 후 재사용 가능** 정책.
 *
 * 남의 예약을 지우지 않도록 uid가 일치할 때만 지운다(옛 닉네임을 이미 다른
 * 사람이 가져간 뒤라면 그 사람의 예약을 건드리면 안 된다).
 */
async function releaseNickname(db, uid, rawNickname) {
  const normalized = normalize(rawNickname);
  if (!normalized) return false;
  const ref = db.collection(COLLECTION).doc(normalized);
  try {
    return await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists || snap.get('uid') !== uid) return false;
      tx.delete(ref);
      return true;
    });
  } catch (e) {
    // 예약 해제가 실패해도 탈퇴 자체를 막지 않는다 — 남는 것은 "아무도 못 쓰는
    // 이름" 하나뿐이고, 탈퇴가 중간에 멈추는 쪽이 훨씬 나쁘다.
    console.error(`[nicknames] 예약 해제 실패 (uid=${uid}, nickname=${rawNickname})`, e);
    return false;
  }
}

// ── 콜러블 ────────────────────────────────────────────────────────────────

const setNickname = onCall({ region: REGION }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요해요.');
  const raw = (request.data || {}).nickname;
  const result = await claimNickname(admin.firestore(), request.auth.uid, raw);
  return { success: true, nickname: result.nickname };
});

/// 입력 중 미리 확인하는 용도 — 저장은 하지 않는다.
/// 여기서 '사용 가능'이 나와도 저장 시점에 남이 먼저 가져갔을 수 있으므로,
/// 최종 판정은 언제나 [claimNickname]의 트랜잭션이다.
const checkNicknameAvailable = onCall({ region: REGION }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', '로그인이 필요해요.');
  const raw = (request.data || {}).nickname;
  const error = validate(raw);
  if (error) return { available: false, reason: error };
  const snap = await admin.firestore().collection(COLLECTION).doc(normalize(raw)).get();
  const owner = snap.exists ? snap.get('uid') : null;
  if (owner && owner !== request.auth.uid) {
    return { available: false, reason: MESSAGES.taken };
  }
  return { available: true, reason: null };
});

module.exports = {
  COLLECTION,
  MIN_LENGTH,
  MAX_LENGTH,
  MESSAGES,
  sanitize,
  normalize,
  validate,
  claimNickname,
  releaseNickname,
  setNickname,
  checkNicknameAvailable,
};

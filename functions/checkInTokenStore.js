/**
 * 통합 QR 체크인 **토큰 보관소** — 발급·무효화의 단 한 곳.
 *
 * ── 왜 별도 모듈인가 ────────────────────────────────────────────────────────
 * 토큰을 만드는 쪽(파티 승인·예약 확정 트리거)과 쓰는 쪽(호스트 스캐너 콜러블)이
 * 서로를 require하면 트리거가 콜러블 정의까지 끌고 들어온다. 규칙은 하나여야
 * 하지만 의존은 한 방향이어야 해서, "토큰을 어떻게 만들고 어떻게 죽이는가"만
 * 여기 둔다. checkInTokens.js(콜러블)와 트리거들이 **같은 이 파일**을 쓴다.
 *
 * ── 유효한 QR은 원본 1건당 언제나 최대 하나 ─────────────────────────────────
 * 트리거는 재실행된다. 같은 승인이 두 번 들어오면 토큰도 두 개가 되고, 그러면
 * 손님 화면에는 하나가 뜨는데 다른 하나도 여전히 서버에서 통과한다 — 취소한
 * QR로 입장하는 길이 열린다. 그래서 원본 경로마다 **포인터 문서**를 둔다.
 *
 *   checkInTokenIndex/{sha256(refPath)}   → { token, domain, refPath }
 *   checkInTokens/{token}                 → { domain, refPath, hostId, guestUid, active }
 *
 * 포인터 id가 refPath에서 결정되므로 조회에 색인도 쿼리도 필요 없고, 트랜잭션
 * 하나로 "이미 있으면 그대로, 없으면 새로"가 성립한다(멱등).
 *
 * ── 취소됐다가 다시 승인되면 새 토큰 ────────────────────────────────────────
 * 죽은 토큰을 되살리지 않는다. 되살리면 취소 기간에 퍼진 QR 캡처본이 다시
 * 살아나기 때문이다. 무효화된 토큰은 `active: false`로 **영구히** 죽고, 다시
 * 승인되면 새 난수가 발급되며 포인터가 그쪽을 가리킨다 — 어느 순간에도 살아
 * 있는 토큰은 0개 아니면 1개다.
 *
 * ── 토큰만 살아 있는 상황 ───────────────────────────────────────────────────
 * 무효화가 어떤 이유로 실패해도 안전해야 한다. 그래서 조회·사용 콜러블은
 * 토큰의 active만 믿지 않고 **원본 문서 상태를 매번 다시 검사**한다
 * (checkInRules의 차단 사유). 이 파일은 첫 번째 방어선일 뿐이다.
 */

const admin = require('firebase-admin');
const crypto = require('crypto');

/** 컬렉션 이름 — 저장값이라 변경 금지. */
const TOKENS = 'checkInTokens';
const TOKEN_INDEX = 'checkInTokenIndex';

/**
 * 원본 경로 → 포인터 문서 id.
 *
 * refPath를 그대로 문서 id로 쓸 수 없다(슬래시가 들어 있다). 해시를 쓰면
 * 길이도 문자도 고정되고, 무엇보다 **같은 원본이면 언제나 같은 id**라서
 * 트리거가 몇 번 재실행되든 같은 포인터를 집는다.
 */
function tokenIndexKey(refPath) {
  return crypto.createHash('sha256').update(String(refPath)).digest('hex');
}

/** QR에 실리는 난수. 추측할 수 없어야 하므로 crypto로 만든다. */
function newToken() {
  return crypto.randomBytes(24).toString('base64url');
}

/** 이 토큰 문서가 아직 살아 있는가 — 필드가 없던 옛 토큰은 살아 있는 것으로 본다. */
function isTokenActive(data) {
  return !!data && data.active !== false;
}

/**
 * 원본 1건의 QR을 발급한다. **여러 번 불러도 토큰은 하나다.**
 *
 * @returns {Promise<{token: string, created: boolean}>}
 *   created가 false면 이미 있던 토큰을 그대로 돌려준 것이다(아무것도 쓰지 않았다).
 */
async function issueCheckInToken(db, { domain, refPath, hostId, guestUid }) {
  if (!domain || !refPath) {
    throw new Error('issueCheckInToken: domain·refPath가 필요합니다.');
  }
  const indexRef = db.collection(TOKEN_INDEX).doc(tokenIndexKey(refPath));

  return db.runTransaction(async (tx) => {
    const idxSnap = await tx.get(indexRef);
    const current = idxSnap.exists ? String(idxSnap.data().token || '') : '';

    if (current) {
      const currentSnap = await tx.get(db.collection(TOKENS).doc(current));
      // 살아 있는 토큰이 이미 있으면 **아무것도 하지 않는다** — 여기서 다시
      // 쓰면 트리거가 자기 쓰기로 또 깨어나 끝나지 않는다.
      if (currentSnap.exists && isTokenActive(currentSnap.data())) {
        return { token: current, created: false };
      }
    }

    const token = newToken();
    tx.set(db.collection(TOKENS).doc(token), {
      domain,
      refPath,
      hostId: hostId || '',
      guestUid: guestUid || '',
      active: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    // 포인터는 **새 토큰**을 가리킨다. 이전 토큰 문서는 active:false로 남아
    // 있으므로(무효화 시점에 그렇게 됐다) 두 개가 동시에 유효할 수 없다.
    tx.set(indexRef, {
      token,
      domain,
      refPath,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { token, created: true };
  });
}

/**
 * 원본 1건의 QR을 **영구히** 무효화한다(취소·거절·만료).
 *
 * 토큰 문서를 지우지 않는 이유: 지우면 그 QR을 다시 찍었을 때 "없는 QR"이 되어
 * 손님도 호스트도 무슨 일이 있었는지 모른다. 죽은 채로 남겨 두면 조회가
 * "사용할 수 없는 QR"이라고 분명히 답할 수 있고 감사 기록도 남는다.
 *
 * @returns {Promise<{token: string, revoked: boolean}>}
 */
async function revokeCheckInTokenFor(db, refPath, reason = null) {
  const indexRef = db.collection(TOKEN_INDEX).doc(tokenIndexKey(refPath));

  return db.runTransaction(async (tx) => {
    const idxSnap = await tx.get(indexRef);
    if (!idxSnap.exists) return { token: '', revoked: false };
    const token = String(idxSnap.data().token || '');
    if (!token) return { token: '', revoked: false };

    const tokenRef = db.collection(TOKENS).doc(token);
    const snap = await tx.get(tokenRef);
    // 이미 죽었으면 그대로 둔다 — 다시 쓰면 트리거가 자기 쓰기로 또 깨어난다.
    if (!snap.exists || !isTokenActive(snap.data())) {
      return { token, revoked: false };
    }

    tx.update(tokenRef, {
      active: false,
      revokedAt: admin.firestore.FieldValue.serverTimestamp(),
      revokedReason: reason || null,
    });
    return { token, revoked: true };
  });
}

// ── 원본 문서에 QR을 붙였다 떼는 일 ────────────────────────────────────────

/**
 * 게스트 화면이 QR을 그리는 근거가 되는 필드.
 *
 * 게스트는 checkInTokens 컬렉션을 읽을 수 없다(firestore.rules) — 자기 QR을
 * 받는 유일한 경로가 **자기 신청·예약·주문 문서의 이 필드**다.
 */
const TOKEN_FIELD = 'checkInToken';

/**
 * 문서 하나의 QR을 지금 상태에 맞춘다 — 파티·예약·상품 트리거가 공유한다.
 *
 * ── 왜 공유하나 ─────────────────────────────────────────────────────────────
 * 세 트리거가 하는 일은 "발급할 것인가"라는 판단 하나만 다르고 나머지는 같다.
 * 그중 **값이 같으면 쓰지 않는다**는 한 줄이 특히 중요하다 — 트리거가 자기
 * 쓰기로 다시 깨어나 끝나지 않는 것을 막는 유일한 장치인데, 세 벌로 흩어져
 * 있으면 한 곳에서 빠져도 눈에 띄지 않는다.
 *
 * @param active  이 문서가 지금 유효한 QR을 가져야 하는가(도메인별 판정 결과)
 * @returns {Promise<{token: string|null, wrote: boolean}>}
 */
async function syncTokenField(
  db,
  { ref, after, refPath, domain, hostId, guestUid, active, revokeReason },
) {
  if (!active) {
    await revokeCheckInTokenFor(db, refPath, revokeReason || null);
    // 게스트 화면에서 QR을 즉시 걷는다. 서버는 어차피 원본 상태를 다시
    // 검사하지만, 취소된 건의 QR이 앱에 그대로 떠 있으면 손님이 현장까지
    // 가서야 막힌 것을 알게 된다.
    if (after && after[TOKEN_FIELD] != null) {
      await ref.set({ [TOKEN_FIELD]: null }, { merge: true });
      return { token: null, wrote: true };
    }
    return { token: null, wrote: false };
  }

  const { token } = await issueCheckInToken(db, {
    domain,
    refPath,
    hostId: hostId || '',
    guestUid: guestUid || '',
  });
  if (after && after[TOKEN_FIELD] === token) return { token, wrote: false };
  await ref.set({ [TOKEN_FIELD]: token }, { merge: true });
  return { token, wrote: true };
}

module.exports = {
  TOKENS,
  TOKEN_INDEX,
  TOKEN_FIELD,
  tokenIndexKey,
  newToken,
  isTokenActive,
  issueCheckInToken,
  revokeCheckInTokenFor,
  syncTokenField,
};

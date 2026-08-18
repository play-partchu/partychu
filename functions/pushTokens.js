const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

// ── 푸시 토큰(기기) 관리 ─────────────────────────────────────────────────────
//
// 토큰은 `users/{uid}/devices/{token}` 서브컬렉션에 **기기 하나당 문서 하나**로
// 둔다. users 문서에 fcmToken 필드 하나를 두는 방식은 쓰지 않는다 — 한 사람이
// 폰·태블릿을 같이 쓰면 나중에 로그인한 기기가 앞 기기의 토큰을 덮어써서
// 앞 기기는 그때부터 알림을 영영 못 받는다.
//
// 문서 id를 토큰 자체로 삼는 이유: 같은 기기가 등록을 두 번 보내도 문서가
// 하나로 합쳐진다(멱등). 토큰이 갱신되면 새 문서가 생기고, 옛 토큰 문서는
// 발송 실패 시 서버가 지운다(sendPushToUsers의 정리 로직).
//
// ── 계정 전환 시 오연결 방지 ────────────────────────────────────────────────
// 클라이언트가 devices에 직접 쓰지 못하게 규칙을 닫아두고(서버 전용), 등록을
// 이 onCall로만 받는다. 그래야 등록 시점에 **다른 사용자 밑에 남아 있는 같은
// 토큰 문서를 지울 수 있다** — 규칙만으로는 남의 문서를 지울 수 없으므로
// 클라이언트 직접 쓰기로는 이 정리가 불가능하다.
//
// 이게 없으면: A로 로그인 → 로그아웃 없이 앱 삭제/재설치 없이 B로 로그인 →
// 토큰은 그대로인데 A 밑에도 남아 있어 **B의 알림이 A에게도 간다.**

const REGION = 'asia-northeast3';

const PLATFORMS = new Set(['android', 'ios', 'web']);

/** 토큰 문자열이 문서 id로 쓸 수 있는 모양인지. */
function isUsableToken(token) {
  return (
    typeof token === 'string' &&
    token.length >= 20 &&
    token.length <= 1000 &&
    !token.includes('/') &&
    !token.includes('..')
  );
}

/**
 * 이 토큰이 **다른 사용자** 밑에 남아 있으면 전부 지운다.
 *
 * 컬렉션 그룹 조회라 자동 색인만으로는 돌지 않는다 — 단일 필드 자동 색인은
 * 컬렉션 범위(COLLECTION)만 만들어지기 때문에, devices.token에 COLLECTION_GROUP
 * 범위를 명시로 켜줘야 한다(firestore.indexes.json의 fieldOverrides).
 * 그게 없으면 등록 첫 호출부터 FAILED_PRECONDITION으로 죽는다.
 */
async function detachTokenFromOtherUsers(db, token, keepUid) {
  const snap = await db.collectionGroup('devices').where('token', '==', token).get();
  const stale = snap.docs.filter((d) => d.get('uid') !== keepUid);
  if (stale.length === 0) return 0;
  const batch = db.batch();
  for (const doc of stale) batch.delete(doc.ref);
  await batch.commit();
  return stale.length;
}

// ── 등록/갱신 ────────────────────────────────────────────────────────────────
exports.registerPushToken = onCall({ region: REGION }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
  }
  const uid = request.auth.uid;
  const { token, platform = 'android', deviceId = null, appVersion = null } =
    request.data || {};

  if (!isUsableToken(token)) {
    throw new HttpsError('invalid-argument', 'token이 올바르지 않습니다.');
  }
  if (!PLATFORMS.has(platform)) {
    throw new HttpsError('invalid-argument', 'platform 값이 올바르지 않습니다.');
  }

  const db = admin.firestore();
  const detached = await detachTokenFromOtherUsers(db, token, uid);

  const now = admin.firestore.FieldValue.serverTimestamp();
  const ref = db
    .collection('users').doc(uid)
    .collection('devices').doc(token);

  // 앱은 로그인 때뿐 아니라 **실행할 때마다** 등록을 보낸다(콜드 스타트 복구).
  // 문서 id가 토큰이라 중복 문서는 생기지 않지만, createdAt까지 매번 덮으면
  // "언제부터 쓰던 기기인가"가 사라져 늘 방금 등록한 것처럼 보인다. 그래서
  // 이미 있는 문서면 createdAt은 건드리지 않는다.
  const existing = await ref.get();

  await ref.set(
    {
      // uid를 문서 안에도 둔다 — 컬렉션 그룹 조회 결과에서 주인을 알아야
      // 위 detach가 "남의 것만" 골라 지울 수 있다.
      uid,
      token,
      platform,
      deviceId: deviceId || null,
      appVersion: appVersion || null,
      updatedAt: now,
      lastSeenAt: now,
      ...(existing.exists ? {} : { createdAt: now }),
    },
    { merge: true }
  );

  console.log(`[push] 토큰 등록 uid=${uid} platform=${platform} detached=${detached}`);
  return { success: true, detachedFromOtherUsers: detached };
});

// ── 해제(로그아웃) ───────────────────────────────────────────────────────────
// 로그아웃한 기기가 계속 알림을 받으면 안 된다. 앱은 이 호출 뒤에 반드시
// FirebaseMessaging.deleteToken()으로 토큰 자체도 버려서, 다음 계정이 같은
// 토큰을 물려받지 않게 한다(클라이언트 PushNotificationService 참고).
exports.unregisterPushToken = onCall({ region: REGION }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
  }
  const uid = request.auth.uid;
  const { token } = request.data || {};
  if (!isUsableToken(token)) {
    throw new HttpsError('invalid-argument', 'token이 올바르지 않습니다.');
  }

  const db = admin.firestore();
  await db
    .collection('users').doc(uid)
    .collection('devices').doc(token)
    .delete();

  console.log(`[push] 토큰 해제 uid=${uid}`);
  return { success: true };
});

module.exports.__helpers = { isUsableToken, detachTokenFromOtherUsers };

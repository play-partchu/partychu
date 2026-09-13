// 본인확인 게이트 — **서버 쪽 단일 판정 지점**.
//
// 파티츄의 회원 정책은 "가입/로그인 후 본인확인을 마쳐야 회원 기능을 쓸 수
// 있다"이다. 앱은 루트 게이트(party_app/lib/utils/root_gate.dart)로 미인증
// 계정을 서비스 화면에 들여보내지 않지만, **그것만으로는 정책이 성립하지
// 않는다.** 다음 경로는 앱 UI를 통째로 건너뛴다.
//
//   · 구버전 앱(루트 게이트가 없던 빌드)이 그대로 설치돼 있는 기기
//   · 앱을 거치지 않고 콜러블을 직접 호출하는 요청
//   · UI 회귀로 게이트가 다시 새는 경우
//
// 그래서 실제로 무언가를 만드는 서버 함수는 여기서 **직접 users/{uid}를 읽어**
// 판정한다. 클라이언트가 보낸 어떤 값도 근거로 쓰지 않는다 — 요청 payload에
// identityVerified 같은 필드가 실려 와도 무시한다.
//
// ── 무엇을 '인증됨'으로 보는가 ────────────────────────────────────────────
// `identityVerified == true` 또는 하위호환 `isVerified == true` 뿐이다.
// 두 필드 모두 firestore.rules에서 클라이언트 쓰기가 막혀 있어(users 규칙의
// 인증 잠금 필드 목록) Admin SDK(niceAuthResult / niceIntcResult)만 쓸 수 있다.
// 따라서 이 판정은 위조되지 않는다.
//
// `verifiedAt`은 **인증 근거로 쓰지 않는다.** 2026-08-22 운영 users 컬렉션
// 전수 조회(읽기 전용) 결과 `verifiedAt`만 있고 두 불리언이 없는 문서는 0건,
// `verifiedAt`은 항상 `identityVerified: true`와 함께만 존재했다. 즉 레거시
// 호환을 위해 시각 필드를 인증으로 승격할 이유가 없고, 승격하면 "시각은
// 남았지만 인증은 해제된" 상태(탈퇴 후 재가입 등)를 인증으로 오판한다.

const { HttpsError } = require('firebase-functions/v2/https');

/// 미인증 계정이 거래성 요청을 보냈을 때의 응답.
///
/// `unauthenticated`가 아니라 `failed-precondition`인 이유: 로그인은 정상이고
/// **선행 조건 하나가 빠진** 상태다. 앱은 이 코드를 재로그인 유도로 착각하면
/// 안 된다(정상 앱이라면 애초에 이 오류를 볼 일이 없다).
const IDENTITY_REQUIRED_CODE = 'failed-precondition';
const IDENTITY_REQUIRED_MESSAGE =
  '본인확인을 완료해야 이용할 수 있어요. 앱을 다시 실행하면 본인확인 화면으로 안내됩니다.';

/// users/{uid} 문서 데이터 하나로 내리는 판정. 문서가 없으면(=아직 아무것도
/// 없는 계정) 미인증이다 — 판정을 못 했을 때 통과시키지 않는다(fail-closed).
function isIdentityVerified(userData) {
  if (!userData) return false;
  return userData.identityVerified === true || userData.isVerified === true;
}

/// 이미 읽어 둔 users 문서로 검사한다 — 같은 문서를 두 번 읽지 않으려는
/// 호출부(예: applyToParty는 성별·생년을 이미 읽는다)를 위한 형태.
function assertIdentityVerifiedData(userData) {
  if (isIdentityVerified(userData)) return;
  throw new HttpsError(IDENTITY_REQUIRED_CODE, IDENTITY_REQUIRED_MESSAGE);
}

/// users 문서를 직접 읽어 검사하고, 읽은 스냅샷을 돌려준다(호출부가 이어서
/// 쓸 수 있게). 트랜잭션 **밖에서** 부르는 것을 전제로 한다 — 게이트는 다른
/// 어떤 읽기보다 먼저 끝나야 하고, 실패하면 트랜잭션을 시작할 이유가 없다.
async function assertIdentityVerified(db, uid) {
  const snap = await db.collection('users').doc(uid).get();
  assertIdentityVerifiedData(snap.exists ? snap.data() : null);
  return snap;
}

module.exports = {
  IDENTITY_REQUIRED_CODE,
  IDENTITY_REQUIRED_MESSAGE,
  isIdentityVerified,
  assertIdentityVerifiedData,
  assertIdentityVerified,
};

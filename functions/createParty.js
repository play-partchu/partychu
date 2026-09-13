// ── createParty — 웹 파티 등록의 유일한 쓰기 경로 ────────────────────────────
//
// 이 함수가 하는 일은 셋뿐이다.
//
//   1. **누가 부르는지** 확인한다 — 로그인 / 미탈퇴 / 본인확인 / 사업자 인증.
//   2. 입력을 partyRegistration.js에 넘겨 **검증하고 문서를 조립한다.**
//   3. 조립된 문서를 쓴다.
//
// 조립 규칙은 여기 없다. 그건 전부 partyRegistration.js에 있고, 앱이 저장하는
// 결과와 골든 픽스처로 묶여 있다(docs/party-registration-parity.md).
//
// ── 왜 콜러블인가 ───────────────────────────────────────────────────────────
//
// 앱은 지금 parties에 **직접 쓴다.** firestore.rules의 parties create가 검사하는
// 것은 hostId·openState·hostBusinessVerified 뿐이라, 참가비·정원·차수·일정·
// 얼리버드가 서로 맞는지는 아무도 보지 않는다. 웹까지 같은 방식으로 직접 쓰면
// 그 판정이 한 벌 더 늘어나고, 두 판정이 어긋나는 순간 "같은 입력인데 문서
// 모양이 다른 파티"가 만들어진다.
//
// 그래서 웹은 이 함수만 쓴다. 앱 등록 화면도 나중에 여기로 옮겨오면 조립 규칙이
// 하나만 남는다(지금은 앱을 건드리지 않는다 — 출시 일정에 영향을 주지 않기
// 위해서다).
//
// ── 클라이언트가 보낸 값 중 **믿지 않는 것** ────────────────────────────────
//
//   · hostId / hostUid          → request.auth.uid로 덮어쓴다
//   · openState                 → 사업자 인증 상태로 서버가 정한다
//   · hostBusinessVerified      → 서버가 users 문서를 직접 읽어 정한다
//   · 신청자/정원 카운터         → 항상 0에서 시작한다
//   · 승인 방식 / 사전질문       → 여기서 **아예 쓰지 않는다.**
//     firestore.rules가 그 필드의 클라이언트 쓰기를 막고 있고, "개인정보를
//     요구하는 질문은 등록을 막는다"는 판정이 setPartyApplicationForm에만
//     있기 때문이다. 승인제로 만들려면 등록 후 그 함수를 따로 부른다.

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

const {
  normalizeInput,
  validateRegistration,
  buildPartyDocuments,
} = require('./partyRegistration');
const { assertIdentityVerifiedData } = require('./identityGuard');
const { isBusinessVerified } = require('./businessVerification');
const {
  evaluatePartyCreatePermission,
  readIndividualHostPartyCreateEnabled,
  INDIVIDUAL_PARTY_CREATE_BLOCKED_MESSAGE,
} = require('./partyOpenState');
// 등록 개수 제한 — 앱·웹·트리거가 같은 규칙을 쓴다(registrationLimits.js).
const { canCreate, limitMessage } = require('./registrationLimits');

/// 한 번에 만들 수 있는 날짜 문서 수. 날짜 슬롯 하나가 문서 하나라, 상한이
/// 없으면 요청 하나로 수백 개를 만들 수 있다. 앱 등록 화면에서 실제로 고르는
/// 날짜 수를 넉넉히 덮는 값이다.
const MAX_SLOTS = 30;

/// 탈퇴 대기 계정은 새로 만드는 경로를 쓸 수 없다 — firestore.rules의
/// isWithdrawalPending과 **같은 판정**이다(accountStatus는 서버만 쓴다).
function isWithdrawalPending(userData) {
  return (userData && userData.accountStatus) === 'withdrawal_pending';
}

exports.createParty = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
    }
    const uid = request.auth.uid;
    const db = admin.firestore();

    // ── 1. 누가 부르는가 ───────────────────────────────────────────────────
    //
    // 앱 UI가 아니라 **서버가 직접 users 문서를 읽어** 판정한다. 요청 payload에
    // identityVerified 같은 값이 실려 와도 쳐다보지 않는다(identityGuard.js).
    const userSnap = await db.collection('users').doc(uid).get();
    const userData = userSnap.exists ? userSnap.data() : null;
    assertIdentityVerifiedData(userData);
    if (isWithdrawalPending(userData)) {
      throw new HttpsError(
        'failed-precondition',
        '탈퇴 대기 중인 계정은 파티를 등록할 수 없어요.'
      );
    }

    // 사업자 인증 여부 — 오픈 상태를 정하는 유일한 근거다.
    // 미인증(개인) 호스트가 만든 파티는 'preopen'으로만 저장되고, 실제 오픈은
    // openPartyRecruiting이 정책(individualHostOpeningEnabled)을 보고 판정한다.
    const businessVerified = await isBusinessVerified(db, uid);

    // 개인(사업자 미인증) 호스트의 **파티 생성 자체**가 열려 있는가.
    //
    // 지금은 준비 중이라 잠겨 있고, appConfig/policy의
    // individualHostPartyCreateEnabled를 true로 바꾸면 열린다(앱 재배포 불필요).
    // 앱도 같은 정책을 읽어 진입을 막지만(PartyCreateEligibility), 구버전 앱과
    // 직접 호출까지 상대하는 마지막 방어선은 여기와 firestore.rules다.
    //
    // 사업자면 정책 문서를 읽지도 않는다 — 개인 정책이 사업자 등록을 막을 수는
    // 없어야 하고, 그 문서를 못 읽는다고 사업자가 걸리면 안 된다.
    const createPermission = evaluatePartyCreatePermission({
      businessVerified,
      individualHostPartyCreateEnabled: businessVerified
        ? true
        : await readIndividualHostPartyCreateEnabled(db),
    });
    if (!createPermission.allowed) {
      throw new HttpsError(
        'permission-denied',
        INDIVIDUAL_PARTY_CREATE_BLOCKED_MESSAGE
      );
    }

    // 등록 개수 — 유형별 10개. 앱도 만들기 전에 같은 규칙으로 세지만
    // (registration_limits.dart), 웹은 이 함수가 유일한 쓰기 경로라 여기서
    // 막는다. 여기서 걸러 두면 초과 문서가 아예 만들어지지 않아
    // registrationLimitGuard가 뒤늦게 정리할 일도 없다.
    //
    // 세는 단위는 **게시글**이다 — 지금 만들려는 파티가 날짜 다섯 개짜리여도
    // 하나로 센다(registrationLimits.js 상단 주석).
    if (!(await canCreate(db, 'party', uid))) {
      throw new HttpsError('failed-precondition', limitMessage('party'));
    }

    // ── 2. 검증 ────────────────────────────────────────────────────────────
    const input = normalizeInput(request.data);

    const slotCount = input.schedule.isRecurring ? 1 : input.schedule.slots.length;
    if (slotCount > MAX_SLOTS) {
      throw new HttpsError(
        'invalid-argument',
        `날짜는 한 번에 ${MAX_SLOTS}개까지 등록할 수 있어요.`
      );
    }

    const now = new Date();
    const errors = validateRegistration(input, { now });
    if (errors.length > 0) {
      // 첫 문제를 메시지로 올리고, 전체 목록은 details로 넘긴다 — 웹 폼이
      // 항목마다 안내를 붙일 수 있도록.
      throw new HttpsError('invalid-argument', errors[0].message, {
        errors,
      });
    }

    // ── 3. 조립 · 저장 ─────────────────────────────────────────────────────
    //
    // 같은 제출에서 만들어지는 모든 날짜 문서가 공유하는 값. 새 문서 id를 미리
    // 하나 뽑아 쓴다(앱과 같은 방식).
    const seriesId = db.collection('parties').doc().id;

    const { docs } = buildPartyDocuments(input, {
      now,
      hostId: uid,
      hostUid: uid,
      seriesId,
      businessVerified,
    });

    if (docs.length === 0) {
      throw new HttpsError('invalid-argument', '저장할 일정이 없어요.');
    }

    const batch = db.batch();
    const partyIds = [];
    for (const doc of docs) {
      const ref = db.collection('parties').doc();
      partyIds.push(ref.id);
      batch.set(ref, {
        ...doc.fields,
        // 마지막 사용 시각만 서버 시계로 남긴다 — 앱과 같은 필드다.
        lastUsedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();

    return {
      success: true,
      seriesId,
      partyIds,
      // 웹이 "지금 바로 열렸는지 / 오픈예정으로 저장됐는지"를 안내할 수 있게.
      // 판정을 여기서 다시 하지 않는다 — 저장된 문서의 값을 그대로 돌려준다.
      openState: docs[0].fields.openState,
      businessVerified,
    };
  }
);

module.exports.MAX_SLOTS = MAX_SLOTS;
module.exports.isWithdrawalPending = isWithdrawalPending;

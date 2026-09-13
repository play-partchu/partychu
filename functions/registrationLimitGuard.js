// ══════════════════════════════════════════════════════════════════════════
// 등록 개수 제한의 **서버 강제** — 앱을 거치지 않은 생성까지 막는 마지막 문.
//
// ── 왜 규칙(firestore.rules)이 아니라 트리거인가 ─────────────────────────
// 보안 규칙은 **문서를 셀 수 없다.** 개수를 규칙에서 보려면 사용자 문서에
// 카운터를 두고 그 값을 읽어야 하는데, 이 카운터는 시간이 지나면 **아무도
// 쓰지 않아도 틀려진다** — 파티가 끝나고 이벤트 기간이 지나면 실제 개수는
// 줄지만 카운터는 그대로다. 그러면 자리가 비었는데도 등록이 막히는, 사용자가
// 스스로 풀 수 없는 상태가 된다(하루 한 번 도는 작업이 고쳐줄 때까지).
//
// 그래서 카운터를 만들지 않는다. 대신 문서가 만들어진 **직후** 실제 개수를
// 세고, 한도를 넘겼으면 방금 만들어진 그 문서를 정리한다. 판정 시점에 세므로
// 낡을 일이 없고, 새 필드도 마이그레이션도 필요 없다.
//
// ── 정상 경로에서는 여기까지 오지 않는다 ─────────────────────────────────
// 앱과 웹은 만들기 **전에** 같은 규칙으로 먼저 센다
// (registration_limits.dart / createParty). 여기 걸리는 것은 구버전 앱,
// SDK 직접 호출, 그리고 두 기기에서 동시에 저장한 경합뿐이다.
//
// ── 무엇을 지우는가 ──────────────────────────────────────────────────────
// 방금 만들어진 **그 문서 하나**뿐이다. 다른 문서는 절대 건드리지 않는다.
// 정리는 사용자가 삭제 버튼을 눌렀을 때와 같은 경로를 쓴다
// ([cleanupContentDoc]) — 미디어·하위 문서까지 같은 규칙으로 정리되고,
// 거래기록은 보존된다(갓 만들어진 문서라 실제로는 거의 없다).
//
// 다중 날짜 파티는 문서가 여럿이지만 트리거도 문서마다 한 번씩 돈다 —
// 각자 자기 문서를 정리하므로 그 게시글이 통째로 사라진다. 세는 단위는
// seriesId(게시글)이므로 "5개짜리 파티 하나"가 5개로 세지는 일은 없다.
// ══════════════════════════════════════════════════════════════════════════

const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

const {
  readCloudflareCreds,
  MEDIA_CLEANUP_SECRETS,
} = require('./cloudflareCleanup');
const { cleanupContentDoc } = require('./contentCleanup');
const {
  MAX_PER_TYPE,
  COLLECTIONS,
  LABELS,
  countActive,
  groupKeyOf,
} = require('./registrationLimits');
const { logScheduledFunctionError } = require('./memberActivityHelpers');

const OPTIONS = {
  region: 'asia-northeast3',
  secrets: MEDIA_CLEANUP_SECRETS,
};

/// 방금 만들어진 문서 하나를 검사하고, 한도를 넘겼으면 정리한다.
///
/// 정리 자체가 실패해도 예외를 밖으로 던지지 않는다 — 트리거가 재시도되며
/// 같은 문서를 반복해서 정리하려 드는 것보다, 기록을 남기고 다음에 사람이
/// 보는 편이 안전하다(초과 생성은 정상 경로에서 일어나지 않는다).
async function enforce(type, event) {
  const snap = event.data;
  if (!snap) return;
  const data = snap.data();
  const hostId = (data && (data.hostId || data.hostUid)) || '';
  if (!hostId) return;

  const db = admin.firestore();
  const key = groupKeyOf(type, snap.id, data);

  try {
    // 방금 만들어진 것(파티는 그 게시글 전체)을 빼고 센다 — 자기 자신 때문에
    // 한도를 넘긴 것처럼 보이면 열 번째 등록이 지워진다.
    const others = await countActive(db, type, hostId, { excludeKeys: [key] });
    if (others < MAX_PER_TYPE) return;

    // 이미 사라졌으면(사용자가 곧바로 지웠거나 같은 게시글의 다른 트리거가
    // 먼저 처리했으면) 할 일이 없다.
    const fresh = await snap.ref.get();
    if (!fresh.exists) return;

    const creds = readCloudflareCreds('limit-guard');
    await cleanupContentDoc(
      db, type, snap.ref, fresh.data(), creds, 'limit-guard',
    );

    console.warn(
      `[limit-guard] ${COLLECTIONS[type]}/${snap.id} 초과 생성 정리 — `
      + `host=${hostId} 기존 ${others}개(상한 ${MAX_PER_TYPE})`,
    );
    // 관리자 오류 화면에도 남긴다. 정상 앱에서는 일어나지 않는 일이라,
    // 쌓이기 시작하면 우회 경로가 생겼다는 신호다.
    await logScheduledFunctionError(
      db,
      'registrationLimitGuard',
      new Error(
        `${LABELS[type]} 등록 한도 초과 생성 정리 (host=${hostId}, `
        + `doc=${snap.id}, 기존 ${others}개)`,
      ),
      { type, hostId, docId: snap.id, existing: others, max: MAX_PER_TYPE },
    );
  } catch (e) {
    console.error(
      `[limit-guard] ${COLLECTIONS[type]}/${snap.id} 검사 실패:`,
      e && e.message ? e.message : e,
    );
  }
}

exports.enforcePartyLimit = onDocumentCreated(
  { ...OPTIONS, document: 'parties/{partyId}' },
  (event) => enforce('party', event),
);

exports.enforcePromotionLimit = onDocumentCreated(
  { ...OPTIONS, document: 'placePromotions/{promotionId}' },
  (event) => enforce('promotion', event),
);

exports.enforcePlaceListingLimit = onDocumentCreated(
  { ...OPTIONS, document: 'events/{eventId}' },
  (event) => enforce('event', event),
);

exports.enforceRentalListingLimit = onDocumentCreated(
  { ...OPTIONS, document: 'places/{placeId}' },
  (event) => enforce('place', event),
);

// ⚠️ [enforce]는 내보내지 않는다 — index.js가 이 모듈을 Object.assign으로
//    붙이므로, 여기 있는 값은 전부 배포될 함수로 취급된다(헬퍼를 내보내면
//    "함수가 아닌 export" 오류로 배포가 통째로 실패한다).

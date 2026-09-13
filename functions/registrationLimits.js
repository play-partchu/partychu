// ══════════════════════════════════════════════════════════════════════════
// 등록 개수 제한 — **유형별 각각 10개**의 정본.
//
// 한 사업자 계정이 동시에 운영할 수 있는 등록물 수를 유형마다 따로 센다.
// 합산이 아니다: 파티 10 + 이벤트 10 + 플레이스 10 + 장소대여 10까지 된다.
//
// ── 이름 주의 ────────────────────────────────────────────────────────────
// 이 저장소의 컬렉션 이름과 사람이 부르는 이름이 어긋나 있다. 여기서는
// contentCleanup.js의 어휘를 **그대로** 따른다(정리 로직과 짝이 맞아야 한다).
//
//   키          컬렉션              사람이 부르는 이름
//   party       parties             파티
//   promotion   placePromotions     이벤트 (매장 이벤트 · 공간 이벤트)
//   event       events              플레이스 (술집·바·카페)
//   place       places              장소대여 (공간대여·숙박)
//
// ── 무엇이 자리를 차지하는가 ─────────────────────────────────────────────
// **지금 살아 있는 것만** 센다 — 손님에게 보이거나, 곧 보일 것들이다.
//
//   파티        최종 종료 시각이 아직 안 지난 것(무기한 정기 파티 포함)
//   이벤트      진행 중 · 시작 전 (종료·숨김은 빠진다)
//   플레이스    isActive != false
//   장소대여    isActive != false
//
// 지난 파티·끝난 이벤트·숨긴 장소는 **자리를 차지하지 않는다.** 그것들은
// 어차피 14일 뒤 자동 삭제되는 대기열이고, 그 사이에 새 등록이 막히면
// 호스트는 지우는 방법을 찾아 헤매게 된다. 삭제된 것(isDeleted / status
// 'deleted')도 물론 빠진다.
//
// ── 파티는 문서가 아니라 '게시글' 단위다 ─────────────────────────────────
// 날짜를 여러 개 고른 일회성 파티는 **날짜마다 문서 하나**가 만들어지고, 그
// 문서들은 같은 `seriesId`를 공유한다(party_register_screen.dart / createParty).
// 사용자가 만든 것은 파티 하나이므로 seriesId로 묶어 하나로 센다. seriesId가
// 없는 옛 문서는 문서 자신을 한 건으로 본다.
//
// 정기 파티는 애초에 문서 하나(+ recurringSchedule)라 언제나 1이다.
//
// ── 수정은 늘어나지 않는다 ───────────────────────────────────────────────
// 세는 것은 "지금 있는 것"이지 "만든 횟수"가 아니다. 기존 문서를 수정하면
// 개수가 그대로이므로 한도에 걸리지 않는다.
//
// ── 클라이언트와 같은 규칙이어야 한다 ────────────────────────────────────
// 앱 쪽 정본은 party_app/lib/services/registration_limits.dart —
// [RegistrationLimits]. 두 곳의 상한(10)과 "무엇을 세는가"가 어긋나면 앱은
// 통과시키고 서버가 지우는(또는 그 반대) 상태가 된다.
// ══════════════════════════════════════════════════════════════════════════

const { finalPartyEndAt } = require('./partySchedule');

/// 유형별 상한. 네 유형이 같은 값을 쓴다 — 유형마다 다른 숫자를 두면
/// 안내 문구도 유형마다 갈라진다.
const MAX_PER_TYPE = 10;

/// 컬렉션 이름 — 위 표의 키 → 실제 컬렉션.
const COLLECTIONS = {
  party: 'parties',
  promotion: 'placePromotions',
  event: 'events',
  place: 'places',
};

/// 사용자에게 그대로 보여줄 이름.
const LABELS = {
  party: '파티',
  promotion: '이벤트',
  event: '플레이스',
  place: '장소대여',
};

/// 한도에 걸렸을 때의 안내 — 앱·웹·서버가 같은 문장을 쓴다.
function limitMessage(type) {
  const label = LABELS[type] || '등록물';
  return `${label}는 최대 ${MAX_PER_TYPE}개까지 등록할 수 있어요. `
    + '기존 등록물을 삭제하거나 종료한 뒤 다시 시도해주세요.';
}

function toDate(value) {
  if (!value) return null;
  if (typeof value.toDate === 'function') return value.toDate();
  if (value instanceof Date) return value;
  if (typeof value === 'number') return new Date(value);
  return null;
}

/// soft delete — 네 유형이 같은 두 필드를 쓴다.
function isDeleted(data) {
  return data.isDeleted === true || data.status === 'deleted';
}

// ── 유형별 "살아 있는가" 판정 ─────────────────────────────────────────────
//
// 각 판정은 문서 하나만 보는 순수 함수다(테스트가 Firestore 없이 돈다).

/// 파티 문서 하나가 아직 안 끝났는가.
///
/// [finalPartyEndAt]이 null이면 "끝나는 때가 없다"(종료일 없는 무기한 정기
/// 파티)는 뜻이라 살아 있는 것으로 본다 — deleteExpiredParties도 그런 파티는
/// 지우지 않는다. 두 판정이 어긋나면 "세지도 않는데 지워지지도 않는" 파티가
/// 생긴다.
function isPartyDocLive(data, now) {
  if (isDeleted(data)) return false;
  const end = finalPartyEndAt(data);
  if (end == null) return true;
  return end.getTime() >= now.getTime();
}

/// 이벤트(placePromotions) 한 건이 손님에게 보이거나 곧 보일 것인가.
///
/// 앱의 [PlacePromotion.statusAt]과 **같은 규칙**이다:
///   · isVisible == false            → 숨김(호스트가 '종료'를 눌렀다)
///   · isAlways                      → 상시 진행
///   · endAt이 지났으면              → 종료
///   · 그 외(시작 전 포함)           → 살아 있다
/// 종료 판정은 그 날의 끝(23:59:59)까지 본다 — 앱과 같은 하루 단위다.
function isPromotionLive(data, now) {
  if (isDeleted(data)) return false;
  if (data.isVisible === false) return false;
  if (data.isAlways === true) return true;
  const end = toDate(data.endAt);
  if (end == null) return true;
  const dayEnd = new Date(
    end.getFullYear(), end.getMonth(), end.getDate(), 23, 59, 59, 999,
  );
  return dayEnd.getTime() >= now.getTime();
}

/// 이벤트가 **손님에게 보이지 않게 된 시각** — 자동 삭제(14일)를 세는 기준점.
///
/// 그렇게 되는 길은 둘이고, 둘 다 겪었다면 **먼저 일어난 쪽**이 기준이다.
///   · 기간 종료 — endAt이 가리키는 날의 끝(23:59:59)
///   · 호스트가 '종료'를 누름 — hiddenAt
///
/// 아직 보이는 이벤트, 상시 진행(노출 중), 기준점을 모르는 옛 숨김 이벤트는
/// null이다 — **null이면 지우지 않는다.**
///
/// ⚠️ 앱의 [PlacePromotion.goneAt]과 같은 규칙이어야 한다. 앱이 'D-3'이라고
///    써 놓고 서버가 이미 지웠으면 안 된다.
function promotionGoneAt(data, now = new Date()) {
  if (!data) return null;
  if (data.isDeleted === true || data.status === 'deleted') return null;
  const stamps = [];

  const end = toDate(data.endAt);
  if (end && data.isAlways !== true) {
    const dayEnd = new Date(
      end.getFullYear(), end.getMonth(), end.getDate(), 23, 59, 59, 999,
    );
    if (dayEnd.getTime() < now.getTime()) stamps.push(dayEnd.getTime());
  }

  const hidden = toDate(data.hiddenAt);
  if (data.isVisible === false && hidden) stamps.push(hidden.getTime());

  if (stamps.length === 0) return null;
  return new Date(Math.min(...stamps));
}

/// 플레이스·장소대여는 날짜가 없는 상시 등록물이라 **숨김 여부**가 전부다.
/// 값이 없는 옛 문서는 노출 중으로 본다(목록 판정 ListingSources와 같다).
function isPlaceDocLive(data) {
  if (isDeleted(data)) return false;
  return data.isActive !== false;
}

/// 문서 하나가 그 유형의 한도에 자리를 차지하는가.
function isLive(type, data, now) {
  switch (type) {
    case 'party': return isPartyDocLive(data, now);
    case 'promotion': return isPromotionLive(data, now);
    case 'event':
    case 'place': return isPlaceDocLive(data);
    default: return false;
  }
}

/// 문서를 "사용자가 만든 것 하나" 단위로 묶는 열쇠.
///
/// 파티만 seriesId로 묶인다(위 주석). 나머지는 문서 하나가 곧 등록물 하나다.
function groupKeyOf(type, docId, data) {
  if (type !== 'party') return docId;
  const series = typeof data.seriesId === 'string' ? data.seriesId.trim() : '';
  return series.length > 0 ? series : docId;
}

/// 문서 목록에서 **지금 자리를 차지하는 등록물 수**를 센다.
///
/// [excludeKeys]는 판정에서 빼고 셀 열쇠들이다 — 방금 만들어진 문서가 자기
/// 자신 때문에 한도를 넘긴 것처럼 보이지 않게 할 때 쓴다.
function countLiveEntries(type, docs, { now = new Date(), excludeKeys = [] } = {}) {
  const skip = new Set(excludeKeys);
  const keys = new Set();
  for (const doc of docs) {
    const data = doc.data;
    if (!isLive(type, data, now)) continue;
    const key = groupKeyOf(type, doc.id, data);
    if (skip.has(key)) continue;
    keys.add(key);
  }
  return keys.size;
}

// ── Firestore를 실제로 읽는 자리 ─────────────────────────────────────────

/// 이 호스트가 지금 갖고 있는 [type] 등록물 수.
///
/// hostId 하나로만 거르고 나머지는 메모리에서 판정한다 — 상태 축이 유형마다
/// 다르고(종료 시각·isVisible·isActive) 색인을 넷이나 늘릴 만한 쿼리가 아니다.
/// 한 호스트의 문서는 상한이 10 언저리라 읽는 양도 작다.
async function countActive(db, type, hostId, { now = new Date(), excludeKeys = [] } = {}) {
  const collection = COLLECTIONS[type];
  if (!collection || !hostId) return 0;
  const snap = await db.collection(collection).where('hostId', '==', hostId).get();
  const docs = snap.docs.map((d) => ({ id: d.id, data: d.data() }));
  return countLiveEntries(type, docs, { now, excludeKeys });
}

/// 새로 하나 더 만들 수 있는가. (한도에 **닿으면** 더는 못 만든다.)
async function canCreate(db, type, hostId, options = {}) {
  const count = await countActive(db, type, hostId, options);
  return count < MAX_PER_TYPE;
}

module.exports = {
  MAX_PER_TYPE,
  COLLECTIONS,
  LABELS,
  limitMessage,
  isDeleted,
  isPartyDocLive,
  isPromotionLive,
  promotionGoneAt,
  isPlaceDocLive,
  isLive,
  groupKeyOf,
  countLiveEntries,
  countActive,
  canCreate,
};

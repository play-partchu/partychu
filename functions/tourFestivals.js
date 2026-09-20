// 한국관광공사 TourAPI 축제·행사 수집 — `KorService2/searchFestival2`.
//
// 공공 축제를 `publicEvents/{tour_<contentid>}`에 **서버만** 써 둔다. 사용자가
// 올린 이벤트(placePromotions)와는 컬렉션부터 다르다. placePromotions는
// 파티츄 장소에 매달린 문서이고, 만료 정리(deleteExpiredPromotions)와 등록
// 개수 제한 트리거가 붙어 있어 공공 데이터를 넣으면 안 된다.
//
// 지키는 약속
//   1. **중복이 생길 수 없다.** 문서 id가 원본 contentid로 정해진다
//      (tour_<contentid>). 몇 번을 다시 돌려도 같은 문서를 덮어쓴다.
//   2. **API가 실패하면 아무것도 바꾸지 않는다.** 모든 페이지를 먼저 받아
//      두고, 한 페이지라도 끝내 실패하면 쓰기 전에 멈춘다. 결과가 통째로
//      비었는데 기존 active 문서가 많으면 이것도 이상 응답으로 보고 멈춘다.
//   3. **바뀐 것만 쓴다.** 원본 modifiedtime과 본문 해시가 그대로이고 상태도
//      그대로면 쓰기 0건이다. 수정일만 바뀌고 우리가 저장하는 본문은 같으면
//      메타 필드만 고친다.
//   4. **원본의 종료·삭제를 따라간다.** 종료일이 지나면 ended. 응답에서
//      연속으로 [MISSING_RUNS_TO_REMOVE]번 빠지면 removed로 숨긴다. 한 번
//      빠진 것으로는 숨기지 않고, 페이지를 끝까지 못 받은 회차에서는 누락을
//      세지 않는다. 문서를 지우지는 않는다(실제 삭제는 별도 정리 작업의 몫).
//   5. **관리자 숨김(adminHidden)은 건드리지 않는다.** 이 모듈은 그 필드를
//      쓰지 않고, 읽어서 isVisible 계산에만 쓴다.
//
// ⚠️ 이 모듈은 Cloud Function 말고 순수 헬퍼도 내보낸다. index.js에서
//    Object.assign(exports, ...)으로 붙이면 헬퍼까지 함수로 배포하려다
//    실패한다. 연결할 때는 반드시
//      exports.syncTourFestivals = require('./tourFestivals').syncTourFestivals;
//    한 줄로만 붙인다(mediaUploads.js와 같은 규칙).
//
// 검증: `npm run check:tourfestivals` (실제 API·Firestore를 부르지 않는다).

const { onSchedule } = require('firebase-functions/v2/scheduler');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');
const https = require('https');
const crypto = require('crypto');

const { logScheduledFunctionError } = require('./memberActivityHelpers');

const tourApiServiceKey = defineSecret('TOUR_API_SERVICE_KEY');

// ── 설정 ────────────────────────────────────────────────────────────────
const COLLECTION = 'publicEvents';
const SOURCE = 'tourapi';
const DOC_ID_PREFIX = 'tour_';
// 저장 형태(매핑)를 바꾸면 올린다. 원본이 그대로여도 본문을 다시 쓴다.
const SCHEMA_VERSION = 1;

const TOUR_HOST = 'apis.data.go.kr';
const TOUR_SERVICE_PATH = '/B551011/KorService2';
const TOUR_FESTIVAL_PATH = `${TOUR_SERVICE_PATH}/searchFestival2`;
const MOBILE_APP = 'Partychu';
const PAGE_SIZE = 100;
// 100 × 60 = 6,000건. 전국 축제는 이보다 훨씬 적다. 넘으면 이상 응답으로
// 보고 이번 회차의 누락 판정을 하지 않는다.
const MAX_PAGES = 60;
// 조회 기준일(eventStartDate)은 **실행 당일 한국 날짜**다.
// 2026-09-19 실측: searchFestival2는 기준일에 이미 진행 중인 행사도 돌려준다
// (기준일 0721 조회에 시작일 20260101 항목 포함). 그래서 앞당겨 조회할 필요가
// 없고, 앞당기면 이미 끝난 행사만 더 받는다(60일 앞당긴 1페이지 100건 중 34건).
// 응답에 오는 것은 "종료일 ≥ 기준일"인 행사라고 보고 누락 판정도 이 기준을
// 쓴다([planUnseen]).

// businessVerification.js의 공공데이터포털 호출 기준을 따른다
// (콜드 스타트 첫 TLS 포함 12초, 5xx·네트워크 오류만 3회까지).
const TOUR_HTTP_TIMEOUT_MS = 12000;
const TOUR_RETRY_ATTEMPTS = 3;
const TOUR_RETRY_DELAY_MS = 700;

// ── 상세 보강(enrichment) ──
// 상세 API 4종(detailCommon2·detailIntro2·detailImage2·detailInfo2)은 **새
// 축제, 원본 modifiedtime이 detailFetchedModifiedTime과 달라진 축제, 보강
// 구성([DETAIL_SCHEMA_VERSION])이 예전인 축제만** 부른다 — 평소에는 바뀐 것만
// 다시 받아서 호출이 거의 없다.
//
// detailInfo2(2026-09-20 표본 80건): 행사소개는 overview와 22/22, 행사내용은
// program과 79/80 같았다. 같은 것은 버리고, Intro program이 빈 축제의
// 행사내용(사천에어쇼)·출연(서울뮤직페스티벌)·그 밖의 줄만 살린다([normalizeInfo]).
//
// ── 호출 한도 보호 — 일일 호출 예산 ──
// 공공데이터포털 데이터 페이지 기준 개발계정 일일 트래픽 1,000. 상세기능별
// 한도인지 서비스 전체 합산인지 공개 문서로 확인하지 못해 **합산 1,000으로
// 가정**한다. 건수로 자르지 않고 **호출 수로** 막는다:
//   · 오늘(한국 날짜) 이미 쓴 호출 수를 [USAGE_COLLECTION]/{YYYYMMDD}에 적어
//     두고(재시도까지 실제 HTTP 요청 수), 회차마다 읽는다.
//   · 이번 회차가 상세에 쓸 수 있는 호출 = 한도 − 예비분 − 오늘 이미 쓴 것
//     − 이번 회차 목록 조회. 예비분([TOUR_DAILY_RESERVE])은 수동 dry-run·점검
//     조회처럼 기록되지 않는 호출 몫이다.
//   · 축제 하나를 시작하기 전에 **최악의 경우**(4종 × 재시도 3회 = 12회)가
//     남은 예산 안에 들어가는지 본다. 들어가지 않으면 멈추고 나머지는 다음
//     날 이어서 받는다 — 어떤 재시도 조합에서도 예산을 넘지 않는다.
// 한도에 여유가 있으면 대상 전부를 한 회차에 받는다(건수 상한이 없다).
const DETAIL_COMMON_OP = 'detailCommon2';
const DETAIL_INTRO_OP = 'detailIntro2';
const DETAIL_IMAGE_OP = 'detailImage2';
const DETAIL_INFO_OP = 'detailInfo2';
const DETAIL_OPS = [DETAIL_COMMON_OP, DETAIL_INTRO_OP, DETAIL_IMAGE_OP, DETAIL_INFO_OP];
const TOUR_DAILY_CALL_LIMIT = 1000;
const TOUR_DAILY_RESERVE = 150;
const USAGE_COLLECTION = 'tourApiUsage';
// 보강 필드 구성을 바꾸면 올린다. 저장된 detailSchemaVersion이 이 값보다 낮은
// 문서는 원본이 그대로여도 상세를 **한 번** 다시 받는다(회차 상한 안에서,
// 한 번도 안 받은 문서·원본이 바뀐 문서 다음 순서로). 목록 본문의
// SCHEMA_VERSION과는 따로다 — 이것을 올려도 목록 본문·해시는 다시 쓰지 않는다.
//   1: overview·program·homepageUrl·organizer·host·contactName·feeText·
//      playTime·eventPlace·images (2026-09-19 배포, 필드 없음 = 1)
//   2: + ageLimit·spendTime·bookingInfo·bookingUrl·discountInfo·subEvent·
//      placeInfo·hostTel·festivalGrade (detailIntro2 축제 필드 전부)
//   3: + detailInfo2 — performers·extraInfo, 빈 program·overview 대체
const DETAIL_SCHEMA_VERSION = 3;
// 축제 보강이 이만큼 연달아 실패하면 키·게이트웨이 쪽 문제로 보고 이번
// 회차의 보강을 멈춘다(남은 호출량을 헛되이 쓰지 않는다).
const DETAIL_MAX_CONSECUTIVE_FAILURES = 3;
// 목록 동기화·쓰기 시간을 남기려고 보강에 쓰는 시간 상한(함수 제한 540초).
// 실측 축제당 약 0.3초(3종 100건 = 27초)라 예산 한도(약 200건)도 넉넉히 든다.
const DETAIL_TIME_BUDGET_MS = 360000;
// 축제 하나가 최악의 경우 쓰는 호출 수(4종 × 재시도 [TOUR_RETRY_ATTEMPTS]).
const DETAIL_WORST_CASE_CALLS = DETAIL_OPS.length * TOUR_RETRY_ATTEMPTS;
// detailInfo2의 그 밖의 줄 — 최대 개수.
const MAX_EXTRA_INFO = 10;
// 의미 없는 값 — 저장하지 않는다(앱도 한 번 더 거른다).
const MEANINGLESS_VALUES = new Set(['선택안함', '선택 안함', '없음', '해당없음', '해당 없음', '-', '--', '.', 'x', 'X', 'n/a', 'N/A']);
const DETAIL_IMAGE_ROWS = 20;
const MAX_IMAGES = 10;
// 호출량 초과·키 오류 — 다시 불러도 같은 답이라 즉시 보강을 멈춘다.
const DETAIL_FATAL_CODES = new Set([
  '20', '22', '30', '31', '32',
  'SERVICE_ACCESS_DENIED_ERROR',
  'LIMITED_NUMBER_OF_SERVICE_REQUESTS_EXCEEDS_ERROR',
  'SERVICE_KEY_IS_NOT_REGISTERED_ERROR',
  'DEADLINE_HAS_EXPIRED_ERROR',
  'UNREGISTERED_IP_ERROR',
]);

// Firestore 배치 한도는 500이다. 여유를 둔다.
const BATCH_SIZE = 400;
// 한 회차에 쓰는 최대 문서 수. 남은 건 다음 회차가 이어서 쓴다.
const MAX_WRITES_PER_RUN = 3000;
// getAll 한 번에 읽는 문서 수.
const READ_CHUNK = 100;

// 누락이 이만큼 연속되면 removed로 숨긴다.
const MISSING_RUNS_TO_REMOVE = 3;
// 한 회차에 active 문서의 이 비율 이상이 한꺼번에 빠지면 원본 쪽 이상으로
// 보고 누락을 세지 않는다.
const MAX_MISSING_RATIO = 0.3;
// 결과가 0건인데 active 문서가 이 수 이상이면 이상 응답으로 보고 멈춘다.
const EMPTY_RESULT_GUARD = 20;

const UNSET_KEY_SENTINELS = new Set(['', 'TEST_MODE', 'REPLACE_WITH_TOUR_API_SERVICE_KEY']);

const KST_OFFSET_MS = 9 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

// 대한민국 좌표 범위(독도·마라도 포함 여유). 밖이면 좌표 없음으로 본다.
const KOREA_BOUNDS = { minLat: 32.8, maxLat: 38.9, minLng: 124.0, maxLng: 132.0 };

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// ── 값 정리 ─────────────────────────────────────────────────────────────

/** 앞뒤 공백을 걷고, 비었으면 null. 숫자도 문자열로 받는다. */
function cleanText(v, maxLength = 500) {
  if (v === null || v === undefined) return null;
  if (typeof v !== 'string' && typeof v !== 'number') return null;
  const s = String(v).replace(/\s+/g, ' ').trim();
  if (!s) return null;
  return s.length > maxLength ? s.slice(0, maxLength) : s;
}

/** 숫자로만 된 코드. 아니면 null. */
function cleanCode(v) {
  const s = cleanText(v, 40);
  return s && /^\d+$/.test(s) ? s : null;
}

/** contentid → 문서 id. 숫자가 아니면 null(쓰지 않는다). */
function tourDocId(contentId) {
  const id = cleanCode(contentId);
  return id ? `${DOC_ID_PREFIX}${id}` : null;
}

/** 'YYYYMMDD' → { y, m, d } 또는 null. 달력에 없는 날짜(0231 등)도 null. */
function parseTourDate(v) {
  const s = cleanText(v, 20);
  if (!s || !/^\d{8}$/.test(s)) return null;
  const y = Number(s.slice(0, 4));
  const m = Number(s.slice(4, 6));
  const d = Number(s.slice(6, 8));
  if (y < 1900 || y > 2200 || m < 1 || m > 12 || d < 1) return null;
  const probe = new Date(Date.UTC(y, m - 1, d));
  if (probe.getUTCMonth() !== m - 1 || probe.getUTCDate() !== d) return null;
  return { y, m, d, key: s };
}

/** 한국 시각 그 날 00:00. */
function kstDayStart({ y, m, d }) {
  return new Date(Date.UTC(y, m - 1, d) - KST_OFFSET_MS);
}

/** 한국 시각 그 날 23:59:59.999. */
function kstDayEnd(date) {
  return new Date(kstDayStart(date).getTime() + DAY_MS - 1);
}

/** 'YYYYMMDDHHmmss'(한국 시각) → Date 또는 null. */
function parseTourDateTime(v) {
  const s = cleanText(v, 20);
  if (!s || !/^\d{14}$/.test(s)) return null;
  const date = parseTourDate(s.slice(0, 8));
  if (!date) return null;
  const hh = Number(s.slice(8, 10));
  const mm = Number(s.slice(10, 12));
  const ss = Number(s.slice(12, 14));
  if (hh > 23 || mm > 59 || ss > 59) return null;
  return new Date(
    Date.UTC(date.y, date.m - 1, date.d, hh, mm, ss) - KST_OFFSET_MS,
  );
}

/** Date → 한국 날짜 'YYYYMMDD'. */
function kstDateKey(date) {
  const k = new Date(date.getTime() + KST_OFFSET_MS);
  const y = k.getUTCFullYear();
  const m = String(k.getUTCMonth() + 1).padStart(2, '0');
  const d = String(k.getUTCDate()).padStart(2, '0');
  return `${y}${m}${d}`;
}

/** mapx(경도)·mapy(위도) → { lat, lng } 또는 null. 0·범위 밖·숫자 아님은 null. */
function parseCoordinates(mapx, mapy) {
  const xs = cleanText(mapx, 40);
  const ys = cleanText(mapy, 40);
  if (!xs || !ys) return null;
  const lng = Number(xs);
  const lat = Number(ys);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  if (lat < KOREA_BOUNDS.minLat || lat > KOREA_BOUNDS.maxLat) return null;
  if (lng < KOREA_BOUNDS.minLng || lng > KOREA_BOUNDS.maxLng) return null;
  return { lat: Math.round(lat * 1e7) / 1e7, lng: Math.round(lng * 1e7) / 1e7 };
}

/**
 * 법정동 지역 코드. v2 응답의 lDongRegnCd(시도 2자리, 예 '11')와
 * lDongSignguCd(시군구 3자리, 예 '200')를 받는다.
 *
 *   regionCode  : 시도 2자리 — '11'(서울)
 *   sigunguCode : 시도+시군구 5자리 — '11200'(성동구). 시군구 3자리만으로는
 *                 시도마다 겹쳐서('140'이 여러 시도에 있다) 단독으로 쓸 수 없다.
 *
 * 형식이 맞지 않으면 null. 시도가 없으면 시군구도 null이다.
 */
function regionCodes(lDongRegnCd, lDongSignguCd) {
  const regn = cleanCode(lDongRegnCd);
  const regionCode = regn && regn.length <= 2 ? regn.padStart(2, '0') : null;
  const signgu = cleanCode(lDongSignguCd);
  const sigunguCode = regionCode && signgu && signgu.length <= 3
    ? regionCode + signgu.padStart(3, '0')
    : null;
  return { regionCode, sigunguCode };
}

/**
 * 이미지 주소. http(s)만 받는다. 관광공사 이미지 서버는 https를 받으므로
 * http는 https로 올린다(웹 앱은 https라 http 이미지가 막힌다).
 */
function cleanImageUrl(v) {
  const s = cleanText(v, 1000);
  if (!s) return null;
  let url;
  try {
    url = new URL(s);
  } catch (_) {
    return null;
  }
  if (url.protocol !== 'http:' && url.protocol !== 'https:') return null;
  if (url.protocol === 'http:' && /(^|\.)visitkorea\.or\.kr$/i.test(url.hostname)) {
    url.protocol = 'https:';
  }
  return url.toString();
}

/** Firestore Timestamp·Date·밀리초 → Date 또는 null. */
function asDate(v) {
  if (!v) return null;
  if (v instanceof Date) return Number.isNaN(v.getTime()) ? null : v;
  if (typeof v.toDate === 'function') return v.toDate();
  if (typeof v === 'number') return new Date(v);
  return null;
}

// ── 원본 한 건 → 문서 본문 ──────────────────────────────────────────────

/**
 * searchFestival2 항목 하나를 저장할 본문으로 바꾼다.
 *
 * 반환: `{ id, body, sourceModifiedTime }`, 쓰면 안 되는 항목은 `{ skip: 이유 }`.
 * body에는 **원본에서 온 값만** 담는다. 상태·동기화 필드는 [planUpsert]가
 * 붙인다. 그래야 해시가 원본 내용 변화만 따라간다.
 */
function normalizeFestival(item) {
  if (!item || typeof item !== 'object') return { skip: 'not-object' };
  const id = tourDocId(item.contentid);
  if (!id) return { skip: 'bad-contentid' };
  const title = cleanText(item.title, 200);
  if (!title) return { skip: 'no-title', id };

  const start = parseTourDate(item.eventstartdate);
  let end = parseTourDate(item.eventenddate);
  if (!start && !end) return { skip: 'no-dates', id };
  // 한쪽만 있으면 하루짜리 행사로 본다.
  const startDate = start || end;
  if (!end) end = startDate;
  if (end.key < startDate.key) return { skip: 'end-before-start', id };

  const body = {
    source: SOURCE,
    sourceId: id.slice(DOC_ID_PREFIX.length),
    sourceType: 'festival',
    contentTypeId: cleanCode(item.contenttypeid),
    title,
    address: cleanText(item.addr1, 300),
    addressDetail: cleanText(item.addr2, 300),
    zipcode: cleanText(item.zipcode, 20),
    tel: cleanText(item.tel, 100),
    // 지역은 법정동 코드가 정본이다. v2에서 areacode·sigungucode는 비어서
    // 온다(2026-09-19 실측 100건 중 0건). [regionCodes] 참고.
    ...regionCodes(item.lDongRegnCd, item.lDongSignguCd),
    categoryCodes: [item.lclsSystm1, item.lclsSystm2, item.lclsSystm3]
      .map((v) => cleanText(v, 40))
      .filter(Boolean),
    location: parseCoordinates(item.mapx, item.mapy),
    startDate: startDate.key,
    endDate: end.key,
    startAt: kstDayStart(startDate),
    endAt: kstDayEnd(end),
    imageUrl: cleanImageUrl(item.firstimage),
    thumbnailUrl: cleanImageUrl(item.firstimage2),
    // 공공누리 유형 코드(Type1·Type3). 앱이 출처 표시 방식을 고를 때 쓴다.
    copyrightType: cleanText(item.cpyrhtDivCd, 20),
    attribution: '한국관광공사',
    sourceCreatedTime: cleanText(item.createdtime, 20),
  };

  return {
    id,
    body,
    sourceModifiedTime: cleanText(item.modifiedtime, 20),
  };
}

// ── 상세 응답 → 보강 필드 ───────────────────────────────────────────────
//
// 보강 필드는 목록 본문(body)과 **따로** 산다. 해시([contentHash])에 들어가지
// 않으므로 보강을 붙이거나 바꿔도 목록 본문 쓰기 판정은 그대로다.
// SCHEMA_VERSION을 올리지 않는 이유가 이것이다(올리면 해시가 전부 바뀌어
// 정상 문서 295건의 목록 본문을 다시 쓴다). 보강 대상은 detailFetchedModifiedTime이
// 없는 문서로 따로 가린다([needsDetail]).

const HTML_ENTITIES = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', '#39': "'" };

/**
 * 여러 줄 본문. `<br>`·`</p>`는 줄바꿈으로, 나머지 태그는 걷고, 흔한 엔티티를
 * 푼다. 줄 안의 공백은 하나로, 빈 줄은 최대 한 줄로 줄인다. 비었으면 null.
 */
function cleanMultiline(v, maxLength = 5000) {
  if (v === null || v === undefined) return null;
  if (typeof v !== 'string' && typeof v !== 'number') return null;
  const s = String(v)
    .replace(/\r\n?/g, '\n')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/p\s*>/gi, '\n')
    .replace(/<[^>]*>/g, '')
    .replace(/&(amp|lt|gt|quot|apos|nbsp|#39);/g, (_, e) => HTML_ENTITIES[e])
    .split('\n')
    .map((line) => line.replace(/[ \t\f\v ]+/g, ' ').trim())
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
  if (!s) return null;
  return s.length > maxLength ? s.slice(0, maxLength) : s;
}

/** '선택안함'·'-' 같은 자리표시 값이면 null. */
function meaningful(v) {
  if (v === null || v === undefined) return null;
  return MEANINGLESS_VALUES.has(String(v).trim()) ? null : v;
}

/** 한 줄 텍스트 — 태그를 걷은 뒤 [cleanText]. */
function cleanPlain(v, maxLength = 500) {
  const s = cleanMultiline(v, 100000);
  return s ? cleanText(s, maxLength) : null;
}

/**
 * 홈페이지 주소. 순수 URL(2026-09-19 실측)이든 `<a href="…">…</a>`든 첫
 * http(s) 주소를 꺼낸다. 외부 사이트라 http를 https로 올리지 않는다.
 */
function cleanWebUrl(v) {
  if (typeof v !== 'string') return null;
  const decoded = v.replace(/&amp;/g, '&');
  const m = decoded.match(/href\s*=\s*["']?(https?:\/\/[^"'\s>]+)/i)
    || decoded.match(/https?:\/\/[^\s"'<>]+/i);
  if (!m) return null;
  const candidate = (m[1] || m[0]).replace(/[),.]+$/, '');
  let url;
  try {
    url = new URL(candidate);
  } catch (_) {
    return null;
  }
  if (url.protocol !== 'http:' && url.protocol !== 'https:') return null;
  const out = url.toString();
  return out.length > 1000 ? null : out;
}

/**
 * 대표 이미지(목록의 firstimage) + detailImage2 originimgurl. 공식 주소만 쓴다
 * (주소를 바꿔 끼워 더 큰 원본을 만들지 않는다). 중복을 걷고 [MAX_IMAGES]장까지.
 */
function mergeImages(firstImageUrl, detailImages) {
  const out = [];
  const seen = new Set();
  const add = (u) => {
    const url = cleanImageUrl(u);
    if (!url || seen.has(url) || out.length >= MAX_IMAGES) return;
    seen.add(url);
    out.push(url);
  };
  add(firstImageUrl);
  for (const img of detailImages || []) add(img && img.originimgurl);
  return out;
}

/**
 * 예매 정보. 원문(태그를 걷은 글자)은 [text]로 늘 보존하고, 그 안에 안전한
 * http(s) 주소가 있을 때만 [url]을 준다(앱은 url이 있을 때만 링크 버튼을
 * 만든다). '인터파크, 현장판매'처럼 글자뿐이면 url은 null이다.
 */
function bookingFields(v) {
  const text = meaningful(cleanMultiline(v, 1000));
  return { text, url: text ? cleanWebUrl(v) : null };
}

/** 비교용 — 태그·엔티티·공백을 걷은 글자. */
function comparable(v) {
  return String(v || '')
    .replace(/<[^>]*>/g, '')
    .replace(/&[a-z#0-9]+;/gi, '')
    .replace(/\s+/g, '');
}

/** 두 글이 사실상 같은가(같거나 한쪽이 다른 쪽을 통째로 품는다). */
function sameText(a, b) {
  const x = comparable(a);
  const y = comparable(b);
  if (!x || !y) return false;
  return x === y || x.includes(y) || y.includes(x);
}

const INFO_INTRO_NAMES = new Set(['행사소개', '축제소개', '소개']);
const INFO_CONTENT_NAMES = new Set(['행사내용', '축제내용', '프로그램']);
const INFO_PERFORMER_NAMES = new Set(['출연', '출연진', '출연자', '출연 가수', '라인업']);

/**
 * detailInfo2 줄들(infoname·infotext·serialnum) → 쓸 것만.
 *
 *   · 행사소개 — [overview]가 비었을 때만 대신 쓴다(아니면 같은 내용이라 버린다)
 *   · 행사내용 — [program]이 비었을 때만 대신 쓴다. program과 **다른** 내용이면
 *                버리지 않고 extraInfo로 남긴다
 *   · 출연·출연진 — performers(여러 줄이면 이어 붙인다)
 *   · 그 밖의 줄 — extraInfo [{ title, text }] (소개·프로그램과 같은 글이면 버림)
 *
 * 2026-09-20 표본 80건의 이름은 행사소개(80)·행사내용(80)·출연(1)뿐이었다.
 * 처음 보는 이름도 그대로 extraInfo에 담아 앱이 제목으로 보여준다.
 */
function normalizeInfo(rows, { overview, program }) {
  const sorted = [...(rows || [])]
    .filter((r) => r && typeof r === 'object')
    .sort((a, b) => (Number(a.serialnum) || 0) - (Number(b.serialnum) || 0));
  let overviewFallback = null;
  let programFallback = null;
  const performers = [];
  const extra = [];
  for (const row of sorted) {
    const name = cleanPlain(row.infoname, 60);
    const text = meaningful(cleanMultiline(row.infotext, 3000));
    if (!name || !text) continue;
    if (INFO_INTRO_NAMES.has(name)) {
      if (!overview && !overviewFallback) overviewFallback = text;
      continue;
    }
    if (INFO_CONTENT_NAMES.has(name)) {
      if (!program) {
        if (!programFallback) programFallback = text;
      } else if (!sameText(program, text)) {
        extra.push({ title: name, text });
      }
      continue;
    }
    if (INFO_PERFORMER_NAMES.has(name)) {
      performers.push(text);
      continue;
    }
    extra.push({ title: name, text });
  }
  const main = [overview || overviewFallback, program || programFallback];
  const extraInfo = [];
  for (const e of extra) {
    if (extraInfo.length >= MAX_EXTRA_INFO) break;
    if (main.some((m) => sameText(m, e.text))) continue;
    if (extraInfo.some((x) => sameText(x.text, e.text))) continue;
    extraInfo.push(e);
  }
  return {
    overviewFallback,
    programFallback,
    performers: performers.length ? performers.join('\n').slice(0, 3000) : null,
    extraInfo,
  };
}

/**
 * 상세 3종 응답 → 보강 필드. 없는 값은 null로 둔다(원본에서 지워진 값이
 * 남지 않게 덮어쓴다). 호출부가 [detailFetchedModifiedTime]을 붙인다.
 *
 * 2026-09-20 표본 80건 실측(detailIntro2): agelimit 19, spendtimefestival 2,
 * sponsor2tel 1건에 값이 있었고 bookingplace·discountinfofestival·subevent·
 * placeinfo·festivalgrade·eventhomepage는 0건이었다. 0건인 필드도 같은
 * 응답에 이미 들어 있어 호출이 늘지 않으므로 nullable로 받아 둔다.
 * sponsor1tel은 목록의 tel과 80/80 같아서, progresstype·festivaltype은
 * '선택안함'뿐이라 받지 않는다.
 */
function normalizeDetail({ common, intro, images, info }, { firstImageUrl }) {
  const c = common || {};
  const i = intro || {};
  const booking = bookingFields(i.bookingplace);
  const overview = meaningful(cleanMultiline(c.overview, 5000));
  const program = meaningful(cleanMultiline(i.program, 5000));
  const extra = normalizeInfo(info, { overview, program });
  return {
    overview: overview || extra.overviewFallback,
    program: program || extra.programFallback,
    performers: extra.performers,
    extraInfo: extra.extraInfo,
    homepageUrl: cleanWebUrl(c.homepage) || cleanWebUrl(i.eventhomepage),
    organizer: cleanPlain(i.sponsor1, 200),
    host: cleanPlain(i.sponsor2, 200),
    contactName: cleanPlain(c.telname, 200),
    feeText: cleanMultiline(i.usetimefestival, 1000),
    playTime: cleanMultiline(i.playtime, 500),
    eventPlace: cleanPlain(i.eventplace, 300),
    images: mergeImages(firstImageUrl, images),
    ageLimit: meaningful(cleanPlain(i.agelimit, 200)),
    spendTime: meaningful(cleanPlain(i.spendtimefestival, 200)),
    bookingInfo: booking.text,
    bookingUrl: booking.url,
    discountInfo: meaningful(cleanMultiline(i.discountinfofestival, 1000)),
    subEvent: meaningful(cleanMultiline(i.subevent, 2000)),
    placeInfo: meaningful(cleanMultiline(i.placeinfo, 1000)),
    hostTel: meaningful(cleanPlain(i.sponsor2tel, 100)),
    festivalGrade: meaningful(cleanPlain(i.festivalgrade, 100)),
  };
}

/** 저장된 보강의 구성 버전. 받은 적이 없으면 0, 버전 필드가 없으면 1(첫 배포분). */
function storedDetailVersion(existing) {
  if (!existing || !Object.prototype.hasOwnProperty.call(existing, 'detailFetchedModifiedTime')) return 0;
  const v = Number(existing.detailSchemaVersion);
  return Number.isFinite(v) && v >= 1 ? v : 1;
}

/**
 * 이 축제의 상세를 (다시) 받아야 하는가. 새 문서이거나, 받은 적이 없거나,
 * 받았을 때의 원본 modifiedtime과 지금 값이 다르거나, 보강 구성이 예전
 * 버전([DETAIL_SCHEMA_VERSION] 미만)이면 true.
 */
function needsDetail(existing, sourceModifiedTime) {
  if (!existing) return true;
  if (!Object.prototype.hasOwnProperty.call(existing, 'detailFetchedModifiedTime')) return true;
  if ((existing.detailFetchedModifiedTime || null) !== (sourceModifiedTime || null)) return true;
  return storedDetailVersion(existing) < DETAIL_SCHEMA_VERSION;
}

/** 본문 해시 — Date는 ISO 문자열로, 키 순서를 고정해서 잰다. */
function contentHash(body) {
  const stable = (v) => {
    if (v instanceof Date) return v.toISOString();
    if (Array.isArray(v)) return v.map(stable);
    if (v && typeof v === 'object') {
      const out = {};
      for (const k of Object.keys(v).sort()) out[k] = stable(v[k]);
      return out;
    }
    return v === undefined ? null : v;
  };
  return crypto
    .createHash('sha256')
    .update(JSON.stringify(stable({ v: SCHEMA_VERSION, body })))
    .digest('hex');
}

/** 종료일이 지났으면 ended, 아니면 active. */
function statusFor(endAt, now) {
  const end = asDate(endAt);
  return end && end.getTime() < now.getTime() ? 'ended' : 'active';
}

function visibleFor(status, existing) {
  return status === 'active' && !(existing && existing.adminHidden === true);
}

// ── 쓰기 계획 ───────────────────────────────────────────────────────────
//
// 계획은 `{ id, kind, data }` 목록이다. kind:
//   create — 새 문서(set)
//   update — 본문이 바뀌었다(set merge, 본문 + 메타)
//   meta   — 본문은 같고 수정일·상태·누락 카운트만 바뀌었다(set merge)
//   none   — 쓸 것 없음(목록에 넣지 않는다)

/** 이번 회차에 받은 항목 하나를 기존 문서와 비교한다. */
function planUpsert(existing, normalized, { now, runId }) {
  const { id, body, sourceModifiedTime } = normalized;
  const hash = contentHash(body);
  const status = statusFor(body.endAt, now);

  if (!existing) {
    return {
      id,
      kind: 'create',
      data: {
        ...body,
        sourceModifiedTime,
        contentHash: hash,
        schemaVersion: SCHEMA_VERSION,
        status,
        isVisible: visibleFor(status, null),
        missingCount: 0,
        createdAt: now,
        updatedAt: now,
        lastSyncedAt: now,
        lastSyncRunId: runId,
      },
    };
  }

  const bodyChanged = existing.contentHash !== hash;
  const isVisible = visibleFor(status, existing);
  const metaChanged =
    (existing.sourceModifiedTime || null) !== (sourceModifiedTime || null)
    || existing.status !== status
    || existing.isVisible !== isVisible
    || (existing.missingCount || 0) !== 0;

  if (!bodyChanged && !metaChanged) return { id, kind: 'none' };

  const meta = {
    sourceModifiedTime,
    status,
    isVisible,
    missingCount: 0,
    lastSyncedAt: now,
    lastSyncRunId: runId,
  };
  if (!bodyChanged) return { id, kind: 'meta', data: meta };
  return {
    id,
    kind: 'update',
    data: {
      ...body,
      ...meta,
      contentHash: hash,
      schemaVersion: SCHEMA_VERSION,
      updatedAt: now,
    },
  };
}

/**
 * 이번 회차 응답에 없던 active 문서의 다음 상태.
 *
 *   · 종료일이 지났으면 → ended (누락과 상관없이)
 *   · [countMissing]이 false(페이지를 끝까지 못 받음·이상 비율)면 → 그대로
 *   · 종료일이 기준일보다 앞선 문서는 응답에 없는 게 정상이라 → 그대로
 *     (위의 ended 판정과 사실상 같지만, 한국 날짜 문자열로 한 번 더 막는다)
 *   · 종료일을 모르는 문서는 판정 근거가 없어 → 그대로
 *   · 아니면(종료일 ≥ 기준일인 active 행사 = 응답에 **와야 하는** 행사)
 *     누락 +1, [MISSING_RUNS_TO_REMOVE]에 닿으면 removed(숨김)
 *
 * 시작일은 보지 않는다. API가 진행 중인 행사도 돌려주므로 오래전에 시작한
 * 장기 축제도 응답에 와야 정상이다.
 */
function planUnseen(existing, id, { now, runId, queryStartDate, countMissing }) {
  const status = statusFor(existing.endAt, now);
  if (status === 'ended') {
    if (existing.status === 'ended' && existing.isVisible === false) {
      return { id, kind: 'none' };
    }
    return {
      id,
      kind: 'meta',
      data: { status: 'ended', isVisible: false, lastSyncRunId: runId },
    };
  }
  if (!countMissing) return { id, kind: 'none' };
  const endDate = parseTourDate(existing.endDate);
  if (!endDate || endDate.key < queryStartDate) return { id, kind: 'none' };

  const missingCount = (existing.missingCount || 0) + 1;
  if (missingCount >= MISSING_RUNS_TO_REMOVE) {
    return {
      id,
      kind: 'meta',
      data: {
        status: 'removed',
        isVisible: false,
        missingCount,
        removedAt: now,
        lastSyncRunId: runId,
      },
    };
  }
  return { id, kind: 'meta', data: { missingCount, lastSyncRunId: runId } };
}

/** 쓰기 목록을 [size]개씩 자른다. */
function chunk(list, size) {
  const out = [];
  for (let i = 0; i < list.length; i += size) out.push(list.slice(i, i + size));
  return out;
}

// ── TourAPI 호출 ────────────────────────────────────────────────────────

/**
 * 공공데이터포털은 서비스키를 두 가지로 준다. 디코딩 키(원문)는 인코딩해서
 * 붙이고, 인코딩 키(이미 %xx가 든 값)는 그대로 붙인다. 두 번 인코딩하면
 * SERVICE_KEY_IS_NOT_REGISTERED_ERROR가 난다.
 */
function encodeServiceKey(key) {
  return /%[0-9A-Fa-f]{2}/.test(key) ? key : encodeURIComponent(key);
}

/** 요청 쿼리. 서비스키를 뺀 쪽이 로그용이다(키는 로그에 남기지 않는다). */
function buildFestivalQuery({ pageNo, eventStartDate, numOfRows = PAGE_SIZE }) {
  const params = new URLSearchParams({
    MobileOS: 'ETC',
    MobileApp: MOBILE_APP,
    _type: 'json',
    arrange: 'A',
    numOfRows: String(numOfRows),
    pageNo: String(pageNo),
    eventStartDate,
  });
  return params.toString();
}

function buildFestivalPath(serviceKey, query) {
  return `${TOUR_FESTIVAL_PATH}?serviceKey=${encodeServiceKey(serviceKey)}&${query}`;
}

/** 상세 API 쿼리. 서비스키는 빠져 있다(로그용). */
function buildDetailQuery(operation, { contentId, contentTypeId }) {
  const params = {
    MobileOS: 'ETC',
    MobileApp: MOBILE_APP,
    _type: 'json',
    contentId: String(contentId),
  };
  // Intro·Info는 contentTypeId가 필수다(없으면 결과코드 11 NO_MANDATORY_REQUEST_PARAMETERS).
  if (operation === DETAIL_INTRO_OP || operation === DETAIL_INFO_OP) {
    params.contentTypeId = String(contentTypeId || '15');
  }
  if (operation === DETAIL_IMAGE_OP) {
    params.imageYN = 'Y';
    params.numOfRows = String(DETAIL_IMAGE_ROWS);
    params.pageNo = '1';
  }
  return new URLSearchParams(params).toString();
}

function buildDetailPath(serviceKey, operation, query) {
  return `${TOUR_SERVICE_PATH}/${operation}?serviceKey=${encodeServiceKey(serviceKey)}&${query}`;
}

/**
 * 응답 본문 → `{ ok: true, items, totalCount, pageNo, numOfRows }` 또는
 * `{ ok: false, code, message }`.
 *
 * 공공데이터포털 게이트웨이 오류(키 미등록·호출량 초과)는 200이어도 XML로
 * 온다. 결과가 없으면 items가 빈 문자열로, 한 건이면 배열이 아닌 객체로 온다.
 */
function parseFestivalResponse(raw) {
  let parsed = null;
  try {
    parsed = JSON.parse(raw);
  } catch (_) {
    const text = String(raw || '');
    const code =
      (text.match(/<returnReasonCode>\s*([^<\s]+)\s*</) || [])[1]
      || (text.match(/<resultCode>\s*([^<\s]+)\s*</) || [])[1]
      || 'NOT_JSON';
    const message =
      (text.match(/<returnAuthMsg>\s*([^<]+?)\s*</) || [])[1]
      || (text.match(/<resultMsg>\s*([^<]+?)\s*</) || [])[1]
      || 'non-JSON response';
    return { ok: false, code, message };
  }
  const response = parsed && parsed.response;
  const header = response && response.header;
  if (!header) {
    return {
      ok: false,
      code: String((parsed && (parsed.resultCode || parsed.code)) || 'NO_HEADER'),
      message: String((parsed && (parsed.resultMsg || parsed.message)) || 'missing response.header'),
    };
  }
  const resultCode = String(header.resultCode || '');
  if (resultCode !== '0000' && resultCode !== '00') {
    return { ok: false, code: resultCode || 'NO_CODE', message: String(header.resultMsg || '') };
  }
  const body = response.body || {};
  const rawItems = body.items && typeof body.items === 'object' ? body.items.item : null;
  let items;
  if (Array.isArray(rawItems)) items = rawItems;
  else if (rawItems && typeof rawItems === 'object') items = [rawItems];
  else items = [];
  const totalCount = Number(body.totalCount);
  return {
    ok: true,
    items,
    totalCount: Number.isFinite(totalCount) && totalCount >= 0 ? totalCount : null,
    pageNo: Number(body.pageNo) || null,
    numOfRows: Number(body.numOfRows) || null,
  };
}

/** GET 한 번. `{ statusCode, raw, elapsedMs }`. */
function httpsGet(path) {
  const startedAt = Date.now();
  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        hostname: TOUR_HOST,
        path,
        method: 'GET',
        headers: { Accept: 'application/json' },
        timeout: TOUR_HTTP_TIMEOUT_MS,
      },
      (res) => {
        let raw = '';
        res.setEncoding('utf8');
        res.on('data', (c) => { raw += c; });
        res.on('end', () => {
          resolve({ statusCode: res.statusCode, raw, elapsedMs: Date.now() - startedAt });
        });
      },
    );
    req.on('timeout', () => {
      // 경로에는 서비스키가 들어 있으므로 메시지에 싣지 않는다.
      req.destroy(new Error(`TourAPI timeout (${TOUR_HTTP_TIMEOUT_MS}ms elapsed=${Date.now() - startedAt}ms)`));
    });
    req.on('error', reject);
    req.end();
  });
}

/**
 * 한 페이지를 받는다. 5xx·네트워크 오류만 재시도하고, 4xx·결과코드 오류는
 * 다시 보내도 같은 답이라 바로 실패로 끝낸다(일 호출량 보호).
 * 끝내 못 받으면 예외를 던진다. 호출부는 쓰기 전에 멈춘다.
 */
async function fetchFestivalPage({ serviceKey, pageNo, eventStartDate }, deps = {}) {
  const query = buildFestivalQuery({ pageNo, eventStartDate });
  const path = buildFestivalPath(serviceKey, query);
  return fetchTourJson({ path, query, label: `page=${pageNo}` }, deps);
}

/**
 * 상세 API 한 번. 목록과 같은 재시도 규칙이다. 실패하면 예외를 던지고,
 * 호출량 초과·키 오류처럼 다시 불러도 소용없는 실패에는 `fatal: true`를
 * 붙인다(호출부가 이번 회차 보강을 멈춘다).
 */
async function fetchDetail({ serviceKey, operation, contentId, contentTypeId }, deps = {}) {
  const query = buildDetailQuery(operation, { contentId, contentTypeId });
  const path = buildDetailPath(serviceKey, operation, query);
  return fetchTourJson({ path, query, label: `${operation} contentId=${contentId}` }, deps);
}

/** 공통 GET + 파싱 + 재시도. [label]은 로그·오류 메시지용(키 없음). */
async function fetchTourJson({ path, query, label }, deps = {}) {
  const get = deps.httpGet || httpsGet;
  const wait = deps.sleep || sleep;
  const attempts = deps.attempts || TOUR_RETRY_ATTEMPTS;
  let lastError = null;
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    let res = null;
    try {
      res = await get(path);
    } catch (err) {
      lastError = new Error(
        `TourAPI 네트워크 오류 ${label} ${attempt}/${attempts}: ${err && err.message}`,
      );
      console.warn(`[tourFestivals] ${lastError.message}`);
    }
    if (res) {
      if (res.statusCode >= 500) {
        lastError = new Error(
          `TourAPI http=${res.statusCode} ${label} ${attempt}/${attempts} elapsedMs=${res.elapsedMs}`,
        );
        console.warn(`[tourFestivals] ${lastError.message}`);
      } else if (res.statusCode >= 400) {
        const err = new Error(`TourAPI http=${res.statusCode} ${label} (재시도 안 함) query=${query}`);
        err.fatal = true;
        throw err;
      } else {
        const parsed = parseFestivalResponse(res.raw);
        if (!parsed.ok) {
          const err = new Error(
            `TourAPI 결과 오류 code=${parsed.code} msg=${parsed.message} ${label} query=${query}`,
          );
          err.code = parsed.code;
          err.fatal = DETAIL_FATAL_CODES.has(String(parsed.code));
          throw err;
        }
        return parsed;
      }
    }
    if (attempt < attempts) await wait(TOUR_RETRY_DELAY_MS);
  }
  throw lastError || new Error(`TourAPI ${label} 실패`);
}

/**
 * 모든 페이지를 받아 contentid로 중복을 걷는다.
 *
 * 반환: `{ items, totalCount, pages, complete }`.
 * complete는 totalCount만큼 다 받았고 페이지 한도에 걸리지 않았을 때만 true다.
 * complete가 아니면 호출부는 누락을 세지 않는다. 한 페이지라도 실패하면
 * 예외가 그대로 올라간다.
 */
async function fetchAllFestivals({ eventStartDate, fetchPage, maxPages = MAX_PAGES }) {
  const byId = new Map();
  let totalCount = null;
  let rawCount = 0;
  let pages = 0;
  let hitPageLimit = false;

  for (let pageNo = 1; ; pageNo += 1) {
    if (pageNo > maxPages) {
      hitPageLimit = true;
      break;
    }
    const page = await fetchPage({ pageNo, eventStartDate });
    pages += 1;
    if (page.totalCount !== null && page.totalCount !== undefined) totalCount = page.totalCount;
    for (const item of page.items) {
      rawCount += 1;
      const key = cleanCode(item && item.contentid);
      // 이상한 contentid도 일단 모아 두고, 건너뛸지는 normalizeFestival이 정한다.
      byId.set(key || `__bad_${rawCount}`, item);
    }
    if (page.items.length === 0) break;
    if (totalCount !== null && rawCount >= totalCount) break;
    if (page.items.length < PAGE_SIZE) break;
  }

  const complete =
    !hitPageLimit && totalCount !== null && rawCount >= totalCount;
  return { items: [...byId.values()], totalCount, rawCount, pages, complete };
}

// ── Firestore 어댑터 ────────────────────────────────────────────────────
//
// 동기화 본체는 이 세 메서드만 쓴다. selfcheck는 메모리 가짜로 바꿔 끼운다.

function firestoreStore(db) {
  const col = db.collection(COLLECTION);
  return {
    /** 원본이 tourapi이고 active인 문서 전부 → Map(id → data). */
    async loadActive() {
      const snap = await col.where('source', '==', SOURCE).where('status', '==', 'active').get();
      const out = new Map();
      snap.forEach((doc) => out.set(doc.id, doc.data()));
      return out;
    },
    /** 지정한 id들 → Map(id → data). 없는 문서는 빠진다. */
    async loadByIds(ids) {
      const out = new Map();
      for (const part of chunk(ids, READ_CHUNK)) {
        const snaps = await db.getAll(...part.map((id) => col.doc(id)));
        for (const s of snaps) if (s.exists) out.set(s.id, s.data());
      }
      return out;
    },
    /** 오늘(한국 날짜 [dayKey]) 이미 쓴 TourAPI 호출 수. 기록이 없으면 0. */
    async loadUsage(dayKey) {
      const snap = await db.collection(USAGE_COLLECTION).doc(dayKey).get();
      const n = snap.exists ? Number(snap.get('calls')) : 0;
      return Number.isFinite(n) && n > 0 ? n : 0;
    },
    /** 이번 회차가 쓴 호출 수를 오늘 기록에 더한다(여러 회차가 겹쳐도 안전). */
    async addUsage(dayKey, calls) {
      if (!(calls > 0)) return;
      await db.collection(USAGE_COLLECTION).doc(dayKey).set({
        calls: admin.firestore.FieldValue.increment(calls),
        limit: TOUR_DAILY_CALL_LIMIT,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    },
    /** 계획 목록을 배치로 나눠 쓴다. create는 set, 나머지는 merge. */
    async commit(plans) {
      let written = 0;
      for (const part of chunk(plans, BATCH_SIZE)) {
        const batch = db.batch();
        for (const p of part) {
          const ref = col.doc(p.id);
          if (p.kind === 'create') batch.set(ref, p.data);
          else batch.set(ref, p.data, { merge: true });
        }
        await batch.commit();
        written += part.length;
      }
      return written;
    },
  };
}

// ── 동기화 한 회차 ──────────────────────────────────────────────────────

// ── 상세 보강 ──────────────────────────────────────────────────────────

/**
 * 한 축제의 상세 4종. 넷 다 받아야 성공이다 — 하나라도 실패하면 이 축제는
 * 아무것도 쓰지 않고(기존 보강 값 보존, detailFetchedModifiedTime 그대로)
 * 다음 회차에 다시 시도된다.
 *
 * 반환: `{ ok: true, detail }` 또는 `{ ok: false, reason, fatal }`.
 */
async function fetchFestivalDetail(target, fetchDetailOp, calls) {
  const { contentId, contentTypeId } = target;
  const call = async (operation) => {
    calls[operation] = (calls[operation] || 0) + 1;
    return fetchDetailOp({ operation, contentId, contentTypeId });
  };
  const sameContent = (it) => !it || it.contentid === undefined
    || cleanCode(it.contentid) === String(contentId);
  try {
    const common = await call(DETAIL_COMMON_OP);
    // 공통정보가 비면 원본 쪽에서 내려간 콘텐츠일 수 있다 — 쓰지 않고 다음에.
    if (!common.items.length) return { ok: false, reason: 'common-empty', fatal: false };
    if (!sameContent(common.items[0])) return { ok: false, reason: 'common-mismatch', fatal: false };
    const intro = await call(DETAIL_INTRO_OP);
    if (!intro.items.length) return { ok: false, reason: 'intro-empty', fatal: false };
    if (!sameContent(intro.items[0])) return { ok: false, reason: 'intro-mismatch', fatal: false };
    // 사진은 없을 수 있다(대표 이미지만 남는다).
    const image = await call(DETAIL_IMAGE_OP);
    const images = image.items.filter(sameContent);
    // 부가정보도 없을 수 있다(없으면 대체·출연·추가 정보가 비어 있을 뿐).
    const info = await call(DETAIL_INFO_OP);
    const infoRows = info.items.filter(sameContent);
    return {
      ok: true,
      detail: normalizeDetail(
        { common: common.items[0], intro: intro.items[0], images, info: infoRows },
        { firstImageUrl: target.firstImageUrl },
      ),
    };
  } catch (err) {
    return {
      ok: false,
      reason: err && err.code ? `code-${err.code}` : 'request-failed',
      fatal: !!(err && err.fatal),
      message: err && err.message,
    };
  }
}

/**
 * 보강 대상 고르기. 이번 회차에 **active로 남을** 축제 중 [needsDetail]인 것.
 * 종료된 축제는 부르지 않는다. 순서: 새 문서 → 한 번도 안 받은 문서 →
 * 원본이 바뀐 문서 → 보강 구성만 예전인 문서, 그 안에서는 시작일이 이른 순
 * (진행 중·임박한 축제 먼저).
 */
function selectDetailTargets(normalized, existingOf, now) {
  const rank = (existing, sourceModifiedTime) => {
    if (!existing) return 0;
    if (storedDetailVersion(existing) === 0) return 1;
    if ((existing.detailFetchedModifiedTime || null) !== (sourceModifiedTime || null)) return 2;
    return 3;
  };
  return normalized
    .filter((n) => statusFor(n.body.endAt, now) === 'active')
    .filter((n) => needsDetail(existingOf(n.id), n.sourceModifiedTime))
    .map((n) => ({
      id: n.id,
      contentId: n.body.sourceId,
      contentTypeId: n.body.contentTypeId,
      firstImageUrl: n.body.imageUrl,
      sourceModifiedTime: n.sourceModifiedTime || null,
      startDate: n.body.startDate,
      rank: rank(existingOf(n.id), n.sourceModifiedTime || null),
    }))
    .sort((a, b) => a.rank - b.rank
      || a.startDate.localeCompare(b.startDate)
      || a.id.localeCompare(b.id));
}

/** 상세 호출 수 초기값 — 4종 모두 0. */
function emptyDetailCalls() {
  return Object.fromEntries(DETAIL_OPS.map((op) => [op, 0]));
}

/**
 * 대상을 차례로 보강한다. 멈추는 경우:
 *   · 호출 예산 — 다음 축제의 최악의 호출 수([DETAIL_WORST_CASE_CALLS])가
 *     남은 예산([budgetLeft])에 들어가지 않을 때
 *   · [limit]건(기본은 끝없음 — dry-run 표본만 줄인다)
 *   · 치명 오류(호출량·키), 연속 실패, 시간 상한
 * 이미 받은 것은 그대로 쓰이고, 목록 동기화는 이 결과와 상관없이 진행된다.
 *
 * 반환: `{ results: Map(id → 보강 필드), stats }`.
 */
async function enrichDetails(targets, {
  fetchDetailOp,
  limit = Infinity,
  budgetLeft = () => Infinity,
  clock = Date.now,
}) {
  const results = new Map();
  const calls = emptyDetailCalls();
  const failures = {};
  let attempted = 0;
  let succeeded = 0;
  let consecutive = 0;
  let stoppedBy = null;
  const startedAt = clock();

  for (const target of targets) {
    if (attempted >= limit) {
      stoppedBy = 'limit';
      break;
    }
    if (budgetLeft() < DETAIL_WORST_CASE_CALLS) {
      stoppedBy = 'call-budget';
      break;
    }
    if (clock() - startedAt > DETAIL_TIME_BUDGET_MS) {
      stoppedBy = 'time-budget';
      break;
    }
    attempted += 1;
    const r = await fetchFestivalDetail(target, fetchDetailOp, calls);
    if (r.ok) {
      succeeded += 1;
      consecutive = 0;
      results.set(target.id, {
        ...r.detail,
        detailFetchedModifiedTime: target.sourceModifiedTime,
        detailSchemaVersion: DETAIL_SCHEMA_VERSION,
      });
      continue;
    }
    failures[r.reason] = (failures[r.reason] || 0) + 1;
    consecutive += 1;
    console.warn(`[tourFestivals] 상세 보강 실패 ${target.id} ${r.reason}${r.message ? ` ${r.message}` : ''}`);
    if (r.fatal) {
      stoppedBy = `fatal:${r.reason}`;
      break;
    }
    if (consecutive >= DETAIL_MAX_CONSECUTIVE_FAILURES) {
      stoppedBy = 'consecutive-failures';
      break;
    }
  }

  return {
    results,
    stats: {
      targets: targets.length,
      limit,
      attempted,
      succeeded,
      failed: attempted - succeeded,
      failures,
      calls,
      totalCalls: DETAIL_OPS.reduce((sum, op) => sum + calls[op], 0),
      stoppedBy,
      remaining: targets.length - succeeded,
    },
  };
}

/**
 * 보강 결과를 쓰기 계획에 합친다. 같은 문서에 목록 계획이 있으면 그 data에
 * 얹고(create는 set이라 함께 들어가야 한다), 없으면 보강만 merge로 쓴다.
 * 목록 본문·해시·상태 필드는 건드리지 않는다.
 */
function mergeDetailPlans(plans, detailResults) {
  const listed = new Set(plans.map((p) => p.id));
  const out = plans.map((p) => (
    detailResults.has(p.id) ? { ...p, data: { ...p.data, ...detailResults.get(p.id) } } : p
  ));
  for (const [docId, detail] of detailResults) {
    if (!listed.has(docId)) out.push({ id: docId, kind: 'detail', data: { ...detail } });
  }
  return out;
}

/**
 * 한 회차. 순서가 곧 안전장치다.
 *   1. 기존 active 문서를 읽는다.
 *   2. API 전 페이지를 받는다. 실패하면 여기서 예외, 쓰기 0건.
 *   3. 이상 응답(빈 결과인데 기존이 많음)이면 멈춘다, 쓰기 0건.
 *   4. 계획을 세운다(받은 항목 upsert, 안 보인 active 문서 ended/누락).
 *   5. 상세 보강 — [fetchDetail]이 있을 때만. 대상 축제별로 상세 4종을 받아
 *      계획에 얹는다. 보강이 실패해도 목록 계획은 그대로 쓴다(예외를 올리지
 *      않는다). 오늘 남은 호출 예산 안에서 대상을 최대한 받는다.
 *   6. 한도만큼만 배치로 쓴다.
 *   7. 이번 회차의 호출 수를 오늘 기록에 더한다(실패로 끝나도 — finally).
 *
 * 호출 수는 [attemptCounter]({ n })가 있으면 그 값(실제 HTTP 요청, 재시도
 * 포함)을, 없으면 목록·상세 호출 횟수를 센다(selfcheck).
 *
 * [dryRun]이 true면 6·7단계를 건너뛴다 — store.commit·addUsage를 **부르지
 * 않는다**. 계획과 통계만 돌려주므로 운영에 쓰기 전 점검에 쓴다
 * (scripts/tourFestivalsDryRun.js). dry-run의 상세 호출 수는 [detailLimit]로
 * 따로 줄인다(0이면 상세를 부르지 않고 대상과 예산만 센다).
 */
async function syncTourFestivalsOnce({
  store,
  fetchPage,
  fetchDetail: fetchDetailOp = null,
  detailLimit = Infinity,
  attemptCounter = null,
  clock,
  now = new Date(),
  runId,
  maxPages,
  dryRun = false,
}) {
  const id = runId || `tour-${now.toISOString()}`;
  const queryStartDate = kstDateKey(now);
  const usageDay = queryStartDate;

  let logicalCalls = 0;
  const callsSoFar = () => (attemptCounter ? attemptCounter.n : logicalCalls);
  const countedPage = async (args) => {
    logicalCalls += 1;
    return fetchPage(args);
  };
  const countedDetail = fetchDetailOp
    ? async (args) => {
      logicalCalls += 1;
      return fetchDetailOp(args);
    }
    : null;

  const usedBefore = typeof store.loadUsage === 'function' ? await store.loadUsage(usageDay) : 0;
  try {
    return await syncBody();
  } finally {
    if (!dryRun && typeof store.addUsage === 'function') {
      try {
        await store.addUsage(usageDay, callsSoFar());
      } catch (e) {
        console.warn(`[tourFestivals] 호출 수 기록 실패: ${e && e.message}`);
      }
    }
  }

  async function syncBody() {
    const active = await store.loadActive();
    const fetched = await fetchAllFestivals({ eventStartDate: queryStartDate, fetchPage: countedPage, maxPages });

    if (fetched.rawCount === 0 && active.size >= EMPTY_RESULT_GUARD) {
      throw new Error(
        `TourAPI 결과가 0건인데 active 문서가 ${active.size}건이다. 이상 응답으로 보고 아무것도 바꾸지 않는다.`,
      );
    }

    const skipped = {};
    const normalized = [];
    for (const item of fetched.items) {
      const n = normalizeFestival(item);
      if (n.skip) {
        skipped[n.skip] = (skipped[n.skip] || 0) + 1;
        continue;
      }
      normalized.push(n);
    }

    const seen = new Set(normalized.map((n) => n.id));
    const needLookup = normalized.map((n) => n.id).filter((docId) => !active.has(docId));
    const others = needLookup.length ? await store.loadByIds(needLookup) : new Map();

    const plans = [];
    for (const n of normalized) {
      const existing = active.get(n.id) || others.get(n.id) || null;
      const plan = planUpsert(existing, n, { now, runId: id });
      if (plan.kind !== 'none') plans.push(plan);
    }

    const unseen = [...active.entries()].filter(([docId]) => !seen.has(docId));
    const missingRatio = active.size ? unseen.length / active.size : 0;
    const countMissing = fetched.complete && missingRatio <= MAX_MISSING_RATIO;
    for (const [docId, existing] of unseen) {
      const plan = planUnseen(existing, docId, { now, runId: id, queryStartDate, countMissing });
      if (plan.kind !== 'none') plans.push(plan);
    }

    // 5. 상세 보강. 목록 계획(plans)은 이미 정해졌고, 보강은 거기에 얹기만 한다.
    const existingOf = (docId) => active.get(docId) || others.get(docId) || null;
    const detailTargets = selectDetailTargets(normalized, existingOf, now);
    const listPlanCount = plans.length;
    const listCalls = callsSoFar();
    // 오늘 상세에 쓸 수 있는 호출 = 한도 − 예비분 − 오늘 이미 쓴 것 − 이번 목록 조회.
    const detailBudget = Math.max(0, TOUR_DAILY_CALL_LIMIT - TOUR_DAILY_RESERVE - usedBefore - listCalls);
    const budgetLeft = () => detailBudget - (callsSoFar() - listCalls);
    // 재시도가 없을 때 이 예산으로 받을 수 있는 축제 수(첫 축제는 최악의 경우가
    // 들어가야 시작하고, 이후는 실제로 쓴 만큼 줄어든다).
    const fundable = detailBudget >= DETAIL_WORST_CASE_CALLS
      ? Math.floor((detailBudget - DETAIL_WORST_CASE_CALLS) / DETAIL_OPS.length) + 1
      : 0;
    let detail = {
      results: new Map(),
      stats: {
        targets: detailTargets.length,
        limit: 0,
        attempted: 0,
        succeeded: 0,
        failed: 0,
        failures: {},
        calls: emptyDetailCalls(),
        totalCalls: 0,
        stoppedBy: fetchDetailOp ? null : 'disabled',
        remaining: detailTargets.length,
      },
    };
    if (countedDetail && detailTargets.length && detailLimit > 0) {
      detail = await enrichDetails(detailTargets, {
        fetchDetailOp: countedDetail,
        limit: detailLimit,
        budgetLeft,
        clock,
      });
    }
    const allPlans = mergeDetailPlans(plans, detail.results);

    const toWrite = allPlans.slice(0, MAX_WRITES_PER_RUN);
    const written = !dryRun && toWrite.length ? await store.commit(toWrite) : 0;

    const count = (kind) => toWrite.filter((p) => p.kind === kind).length;
    const planned = (pred) => plans.filter(pred).length;
    const detailPlannedThisRun = Math.min(detailTargets.length, fundable);
    // 받은 유효 항목의 상태·품질 분포. 한도(MAX_WRITES_PER_RUN)와 무관한 전체 기준이다.
    const expectedStatus = { active: 0, ended: 0 };
    let noLocation = 0;
    let noImage = 0;
    for (const n of normalized) {
      expectedStatus[statusFor(n.body.endAt, now)] += 1;
      if (!n.body.location) noLocation += 1;
      if (!n.body.imageUrl) noImage += 1;
    }
    const stats = {
      duplicateContentIds: fetched.rawCount - fetched.items.length,
      valid: normalized.length,
      invalid: fetched.items.length - normalized.length,
      expectedActive: expectedStatus.active,
      expectedEnded: expectedStatus.ended,
      noLocation,
      noImage,
      existingActiveDocs: active.size,
      existingMatched: normalized.filter((n) => active.has(n.id) || others.has(n.id)).length,
      unseenActiveDocs: unseen.length,
      plannedCreate: planned((p) => p.kind === 'create'),
      plannedUpdate: planned((p) => p.kind === 'update'),
      plannedMeta: planned((p) => p.kind === 'meta'),
      plannedEnded: planned((p) => p.data && p.data.status === 'ended' && p.kind !== 'create'),
      plannedRemoved: planned((p) => p.data && p.data.status === 'removed'),
    };
    const summary = {
      dryRun: !!dryRun,
      runId: id,
      queryStartDate,
      pages: fetched.pages,
      totalCount: fetched.totalCount,
      fetched: fetched.rawCount,
      unique: fetched.items.length,
      skipped,
      complete: fetched.complete,
      countMissing,
      created: count('create'),
      updated: count('update'),
      meta: count('meta'),
      written,
      deferred: allPlans.length - toWrite.length,
      wouldWrite: toWrite.length,
      stats,
      detail: {
        ...detail.stats,
        // 목록 계획만의 쓰기 수(보강이 없던 예전과 같은 값이어야 한다).
        listPlans: listPlanCount,
        // 보강 결과가 얹힌 목록 계획 / 보강만 쓰는 문서.
        mergedIntoListPlans: allPlans.filter((p) => p.kind !== 'detail' && detail.results.has(p.id)).length,
        detailOnlyWrites: allPlans.filter((p) => p.kind === 'detail').length,
        // 오늘 호출 예산과, 재시도가 없을 때 그 안에서 받을 수 있는 축제 수.
        budget: {
          day: usageDay,
          dailyLimit: TOUR_DAILY_CALL_LIMIT,
          reserve: TOUR_DAILY_RESERVE,
          usedBefore,
          listCalls,
          detailBudget,
          worstCasePerFestival: DETAIL_WORST_CASE_CALLS,
          fundableFestivals: fundable,
          callsThisRun: callsSoFar(),
        },
        plannedThisRun: detailPlannedThisRun,
        plannedCallsThisRun: {
          ...Object.fromEntries(DETAIL_OPS.map((op) => [op, detailPlannedThisRun])),
          total: detailPlannedThisRun * DETAIL_OPS.length,
        },
        runsToClearBacklog: fundable ? Math.ceil(detailTargets.length / fundable) : null,
        // 대상이 된 까닭별 건수(순서도 이 순서다).
        targetsByReason: {
          newDoc: detailTargets.filter((x) => x.rank === 0).length,
          neverFetched: detailTargets.filter((x) => x.rank === 1).length,
          sourceChanged: detailTargets.filter((x) => x.rank === 2).length,
          schemaOutdated: detailTargets.filter((x) => x.rank === 3).length,
        },
      },
    };
    if (dryRun) {
      // 점검용: 계획 종류별로 어떤 필드를 쓰게 되는지, 받아 본 보강 결과 요약.
      const keysByKind = {};
      for (const p of toWrite) {
        const set = keysByKind[p.kind] || (keysByKind[p.kind] = new Set());
        Object.keys(p.data).forEach((k) => set.add(k));
      }
      summary.writeKeysByKind = Object.fromEntries(
        Object.entries(keysByKind).map(([k, v]) => [k, [...v].sort()]),
      );
      const titleOf = new Map(normalized.map((n) => [n.id, n.body.title]));
      summary.detailPreview = [...detail.results].map(([docId, d]) => ({
        id: docId,
        title: titleOf.get(docId) || null,
        overviewChars: d.overview ? d.overview.length : 0,
        programChars: d.program ? d.program.length : 0,
        homepageUrl: !!d.homepageUrl,
        organizer: !!d.organizer,
        host: !!d.host,
        contactName: !!d.contactName,
        feeText: !!d.feeText,
        playTime: !!d.playTime,
        eventPlace: !!d.eventPlace,
        images: d.images.length,
        ageLimit: d.ageLimit,
        spendTime: d.spendTime,
        bookingInfo: d.bookingInfo,
        bookingUrl: d.bookingUrl,
        discountInfo: d.discountInfo,
        subEvent: d.subEvent ? d.subEvent.length : 0,
        placeInfo: d.placeInfo ? d.placeInfo.length : 0,
        hostTel: !!d.hostTel,
        festivalGrade: d.festivalGrade,
        performers: d.performers,
        extraInfo: d.extraInfo,
      }));
    }
    return summary;
  }
}

function resolveServiceKey() {
  let value = '';
  try {
    value = (tourApiServiceKey.value() || '').trim();
  } catch (_) {
    value = '';
  }
  return UNSET_KEY_SENTINELS.has(value) ? null : value;
}

// ── 예약 실행 ───────────────────────────────────────────────────────────
// 매일 04:30(KST). 새벽 정리 작업들(03:00대)과 겹치지 않게 둔다.
exports.syncTourFestivals = onSchedule(
  {
    schedule: '30 4 * * *',
    timeZone: 'Asia/Seoul',
    region: 'asia-northeast3',
    secrets: [tourApiServiceKey],
    timeoutSeconds: 540,
    memory: '512MiB',
  },
  async () => {
    const db = admin.firestore();
    try {
      const serviceKey = resolveServiceKey();
      if (!serviceKey) {
        throw new Error('TOUR_API_SERVICE_KEY가 설정되지 않았다. 동기화를 건너뛴다.');
      }
      // 재시도까지 실제 HTTP 요청 수를 센다 — 일일 트래픽은 요청 수로 깎인다.
      const attemptCounter = { n: 0 };
      const deps = {
        httpGet: (path) => {
          attemptCounter.n += 1;
          return httpsGet(path);
        },
      };
      const summary = await syncTourFestivalsOnce({
        store: firestoreStore(db),
        fetchPage: (args) => fetchFestivalPage({ serviceKey, ...args }, deps),
        fetchDetail: (args) => fetchDetail({ serviceKey, ...args }, deps),
        attemptCounter,
        now: new Date(),
      });
      console.log(`[tourFestivals] 완료 ${JSON.stringify(summary)}`);
    } catch (e) {
      await logScheduledFunctionError(db, 'syncTourFestivals', e);
      throw e;
    }
  },
);

// 순수 헬퍼(selfcheck용). Cloud Function은 syncTourFestivals 하나뿐이다.
Object.assign(exports, {
  COLLECTION,
  SOURCE,
  SCHEMA_VERSION,
  PAGE_SIZE,
  MAX_WRITES_PER_RUN,
  BATCH_SIZE,
  MISSING_RUNS_TO_REMOVE,
  EMPTY_RESULT_GUARD,
  DETAIL_SCHEMA_VERSION,
  DETAIL_OPS,
  DETAIL_INFO_OP,
  DETAIL_WORST_CASE_CALLS,
  TOUR_DAILY_CALL_LIMIT,
  TOUR_DAILY_RESERVE,
  TOUR_RETRY_ATTEMPTS,
  USAGE_COLLECTION,
  MAX_EXTRA_INFO,
  DETAIL_MAX_CONSECUTIVE_FAILURES,
  DETAIL_TIME_BUDGET_MS,
  MAX_IMAGES,
  DETAIL_COMMON_OP,
  DETAIL_INTRO_OP,
  DETAIL_IMAGE_OP,
  cleanText,
  cleanMultiline,
  cleanWebUrl,
  mergeImages,
  normalizeDetail,
  needsDetail,
  storedDetailVersion,
  bookingFields,
  meaningful,
  normalizeInfo,
  sameText,
  httpsGet,
  selectDetailTargets,
  enrichDetails,
  mergeDetailPlans,
  buildDetailQuery,
  buildDetailPath,
  fetchDetail,
  tourDocId,
  parseTourDate,
  parseTourDateTime,
  kstDayStart,
  kstDayEnd,
  kstDateKey,
  parseCoordinates,
  regionCodes,
  cleanImageUrl,
  normalizeFestival,
  contentHash,
  statusFor,
  planUpsert,
  planUnseen,
  chunk,
  encodeServiceKey,
  buildFestivalQuery,
  buildFestivalPath,
  parseFestivalResponse,
  fetchFestivalPage,
  fetchAllFestivals,
  firestoreStore,
  syncTourFestivalsOnce,
});

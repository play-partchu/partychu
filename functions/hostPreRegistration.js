// ══════════════════════════════════════════════════════════════════════════
// 호스트 사전등록 — FormHug 신청서 → 관리자 처리 → 기존 사업자 인증/대표자 위임
//
// ── 이 파일이 새로 만드는 것과 만들지 않는 것 ──────────────────────────────
// 새로 만드는 것은 **신청서 원장(hostPreRegistrations)과 그 처리 기록**뿐이다.
// 권한은 하나도 만들지 않는다.
//
//   · 사업자 진위·권한   users/{uid}.businessVerification
//                        (verifyBusinessRegistration — businessVerification.js)
//   · 대표자 승인        businessDelegations / businessApprovalSessions /
//                        businessApprovalPage (businessDelegation.js)
//
// 관리자가 대표자 링크를 만들 때도 createDelegationRequest를 **그대로** 부른다.
// 72시간·1회용·하루 3회·사업자당 10개 한도, 토큰 해시만 저장하는 규칙이 전부
// 그 함수 안에 있으므로, 여기서 우회하거나 다시 구현할 것이 없다.
//
// ⚠️ **사전등록 상태는 권한의 근거가 아니다.** status가 'verified'여도 그것은
//    "호스트 문서의 businessVerification이 이 신청서의 사업자로 권한이 열린 것을
//    관리자 화면이 확인했다"는 표시일 뿐이다. 규칙·함수는 이 컬렉션을 보지 않는다.
//
// ── 이메일은 본인확인이 아니다 ─────────────────────────────────────────
// 신청서의 hostEmail은 신청자가 적은 값이다. 같은 이메일의 회원을 **후보로
// 보여줄 뿐** 자동으로 연결하지 않고, 연결해도 identityVerified·
// businessVerification에는 한 글자도 쓰지 않는다. 호스트는 앱에서 직접
// NICE 본인확인과 사업자 인증을 거쳐야 한다.
//
// ── FormHug ──────────────────────────────────────────────────────────────
// 계약(샘플 payload API 문서 + 운영 수신 로그로 확인):
//   POST application/json
//   { event_type, data: { form, form_name, entry: { serial_number,
//     field_1 … field_N, created_at, updated_at, info_* } } }
//   웹훅 안내 문서(https://formhug.ai/docs/integrations/webhooks.md)의 예시는
//   이것을 data로 한 번 더 감싸 적었다 — 파서는 두 모양을 모두 받는다.
//   2xx가 아니면 FormHug가 재전송한다.
//
//   · 서명·시크릿 헤더가 **없다**(웹훅 생성 API에 url·trigger_events만 있다).
//     그래서 웹훅 URL의 key 쿼리를 Firebase Secret과 비교해 막는다.
//   · 필드 키는 field_N(api_code)이고 **라벨은 실리지 않는다.** 어느 칸이
//     업체명인지는 폼 정의(GET /api/v1/forms/{token})를 관리자가 확인하고
//     저장한 매핑(hostPreRegistrationConfig/formhug)으로만 정한다 — 코드에
//     field_3 같은 번호를 박지 않는다.
//   · 첨부파일 url은 **24시간 서명 링크**다. 저장해 둔 링크는 곧 죽으므로
//     관리자가 상세를 열 때 API로 항목을 다시 읽어 새 링크를 받는다.
//
// ── 저장하지 않는 것 ─────────────────────────────────────────────────────
// 원본 payload, info_remote_ip·user agent 같은 메타, 매핑되지 않은 칸의 값,
// 토큰류. 매핑이 없을 때 들어온 신청은 **일련번호만** 남겨 두고, 매핑을
// 저장한 뒤 API로 다시 가져온다.
// ══════════════════════════════════════════════════════════════════════════

const { onCall, onRequest, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');
const crypto = require('crypto');

const { logUserActivity } = require('./memberActivityHelpers');
const { toMillis } = require('./payoutAccounts');
const {
  AUTHORIZATION,
  businessNumberHash,
  isBusinessAuthorized,
  normalizeBusinessNumber,
} = require('./businessVerification');
const delegationModule = require('./businessDelegation');

const REGION = 'asia-northeast3';

// ── 컬렉션 ──────────────────────────────────────────────────────────────
const COLLECTION = 'hostPreRegistrations';
const HISTORY = 'history';
const CONFIG_COLLECTION = 'hostPreRegistrationConfig';
const CONFIG_DOC = 'formhug';

// ── FormHug ─────────────────────────────────────────────────────────────
const FORMHUG_API_BASE = 'https://formhug.ai/api/v1';
/// 공개 폼 https://formhug.ai/f/Sbyrul 의 토큰.
const FORMHUG_FORM_TOKEN = 'Sbyrul';
const FORMHUG_FORM_URL = `https://formhug.ai/f/${FORMHUG_FORM_TOKEN}`;
const HANDLED_EVENTS = new Set(['entry_created', 'entry_updated']);
const FETCH_TIMEOUT_MS = 8000;
/// 서명 링크 유효기간은 24시간 — 여유를 두고 20시간이 지나면 새로 받는다.
const ATTACHMENT_URL_REFRESH_MS = 20 * 60 * 60 * 1000;

/// 웹훅 URL의 ?key= 값. FormHug에는 서명 기능이 없어 이것이 유일한 인증이다.
const formhugWebhookKey = defineSecret('FORMHUG_WEBHOOK_KEY');
/// FormHug Personal Access Token(form:read, entry:read). 폼 정의·항목 재조회용.
const formhugApiToken = defineSecret('FORMHUG_API_TOKEN');

// ── 상태 ────────────────────────────────────────────────────────────────
const STATUS = {
  new: 'new',
  reviewing: 'reviewing',
  preregistered: 'preregistered',
  hostLinkSent: 'hostLinkSent',
  representativeVerificationRequired: 'representativeVerificationRequired',
  representativeLinkSent: 'representativeLinkSent',
  verified: 'verified',
  rejected: 'rejected',
};

/// 진행 순서. 자동 동기화는 **앞으로만** 옮긴다(권한 해제 감지는 예외).
const STATUS_RANK = {
  new: 0,
  reviewing: 1,
  preregistered: 2,
  hostLinkSent: 3,
  representativeVerificationRequired: 4,
  representativeLinkSent: 5,
  verified: 6,
};

const DEVICE = { android: 'android', ios: 'ios', both: 'both' };

/// 관리자 화면 "대표자 인증 링크 상태"가 쓰는 표시값.
const LINK_STATUS = {
  none: 'none',
  requested: 'requested',
  approved: 'approved',
  rejected: 'rejected',
  expired: 'expired',
  revoked: 'revoked',
};

/// 신청서 칸 ↔ FormHug 필드 매핑 대상. kind가 값 해석 방식을 정한다.
const MAPPABLE_FIELDS = [
  { key: 'storeName', label: '업체명', kind: 'text', required: true },
  { key: 'businessRegistrationNumber', label: '사업자등록번호', kind: 'businessNumber', required: true },
  { key: 'hostName', label: '호스트 이름', kind: 'text', required: true },
  { key: 'hostEmail', label: '호스트 가입 이메일', kind: 'email', required: true },
  { key: 'hostPhone', label: '호스트 연락처', kind: 'phone', required: true },
  { key: 'sameAsRepresentative', label: '대표자와 동일 여부', kind: 'choiceBool', required: true },
  { key: 'representativeName', label: '대표자 이름', kind: 'text', required: false },
  { key: 'representativePhone', label: '대표자 연락처', kind: 'phone', required: false },
  { key: 'representativeEmail', label: '대표자 이메일', kind: 'email', required: false },
  { key: 'deviceType', label: '사용 기기', kind: 'choiceDevice', required: true },
  { key: 'googlePlayScreenshot', label: 'Google Play 계정 캡처', kind: 'attachment', required: false },
  { key: 'privacyConsent', label: '개인정보 수집 동의', kind: 'consent', required: false },
  { key: 'additionalMessage', label: '추가 메시지', kind: 'longText', required: false },
];
const MAPPABLE_KEYS = new Set(MAPPABLE_FIELDS.map((f) => f.key));

// ══════════════════════════════════════════════════════════════════════════
// 순수 헬퍼
// ══════════════════════════════════════════════════════════════════════════

const digitsOnly = (v) => String(v == null ? '' : v).replace(/[^0-9]/g, '');

/// 제어문자를 걷어낸 한 줄 텍스트. 객체·배열이 오면 사람이 읽을 값만 꺼낸다.
function cleanText(v, max = 200) {
  if (v == null) return '';
  if (Array.isArray(v)) {
    return cleanText(v.map((x) => cleanText(x, max)).filter(Boolean).join(', '), max);
  }
  if (typeof v === 'object') {
    return cleanText(v.label ?? v.value ?? v.text ?? '', max);
  }
  return String(v).replace(/[ -]/g, ' ').trim().slice(0, max);
}

function normalizeLabel(v) {
  return String(v == null ? '' : v).replace(/\s+/g, '').toLowerCase();
}

/// 비밀값 비교 — 길이가 달라도 시간이 새지 않게 해시끼리 비교한다.
function keyMatches(provided, expected) {
  const e = String(expected || '');
  if (!e) return false; // 시크릿이 비어 있으면 아무도 통과시키지 않는다
  const a = crypto.createHash('sha256').update(String(provided || ''), 'utf8').digest();
  const b = crypto.createHash('sha256').update(e, 'utf8').digest();
  return crypto.timingSafeEqual(a, b);
}

function docIdFor(formToken, serialNumber) {
  return `formhug_${formToken}_${serialNumber}`;
}

/// FormHug 웹훅 본문 — **문서에 적힌 두 모양만** 받는다.
///
///   실제 본문(샘플 payload API 문서, 운영 수신 로그로 확인):
///     { event_type, data: { form, form_name, entry } }
///   웹훅 안내 문서 예시(API 응답 봉투 data까지 옮겨 적은 모양):
///     { data: { event_type, data: { form, form_name, entry } } }
///
/// 2026-09-13 FormHug Test가 앞의 모양으로 와서 뒤의 모양만 받던 파서가
/// reason=noData로 400을 냈다. 두 모양 모두 같은 {eventType, form, entry}로 모은다.
function parseWebhookBody(body) {
  let b = body;
  if (Buffer.isBuffer(b)) b = b.toString('utf8');
  if (typeof b === 'string') {
    try { b = JSON.parse(b); } catch (_) { return { ok: false, reason: 'notJson' }; }
  }
  if (!b || typeof b !== 'object') return { ok: false, reason: 'notObject' };
  const envelope = b.data;
  if (!envelope || typeof envelope !== 'object') return { ok: false, reason: 'noEnvelope' };

  let inner;
  let eventType;
  if (Object.prototype.hasOwnProperty.call(envelope, 'entry')) {
    // 실제 본문 — data가 곧 { form, form_name, entry }이고 event_type은 최상위.
    inner = envelope;
    eventType = b.event_type;
  } else if (envelope.data && typeof envelope.data === 'object') {
    // 안내 문서 예시 — 한 겹 더 감싸져 있다.
    inner = envelope.data;
    eventType = envelope.event_type;
  } else {
    return { ok: false, reason: 'noData' };
  }
  const entry = inner.entry;
  if (!entry || typeof entry !== 'object') return { ok: false, reason: 'noEntry' };
  const serialNumber = Number(entry.serial_number);
  if (!Number.isSafeInteger(serialNumber) || serialNumber <= 0) {
    return { ok: false, reason: 'noSerial' };
  }
  return {
    ok: true,
    eventType: String(eventType || ''),
    formToken: String(inner.form || ''),
    serialNumber,
    entry,
  };
}

/// 선택형 값에서 비교할 문자열들을 꺼낸다. 항목 값이 선택지 라벨인지 api_code인지
/// 문서에 적혀 있지 않으므로 둘 다 받아서 설정의 선택지와 대조한다.
function choiceTokens(v) {
  const list = Array.isArray(v) ? v : (v == null || v === '' ? [] : [v]);
  const out = [];
  for (const item of list) {
    if (item == null) continue;
    if (typeof item === 'object') {
      for (const k of ['api_code', 'value', 'label', 'text']) {
        if (item[k] != null && String(item[k]).trim()) out.push(String(item[k]).trim());
      }
    } else if (String(item).trim()) {
      out.push(String(item).trim());
    }
  }
  return out;
}

/// 항목 값 → 설정에 저장된 선택지 의미값 목록.
///   mapping: { <choiceApiCode>: 의미값 }
///   labels:  { <choiceApiCode>: 선택지 라벨 }
function resolveChoices(value, mapping, labels) {
  const map = mapping || {};
  const byLabel = new Map();
  for (const [code, label] of Object.entries(labels || {})) {
    byLabel.set(normalizeLabel(label), code);
  }
  const lookup = (token) => {
    if (Object.prototype.hasOwnProperty.call(map, token)) return token;
    return byLabel.get(normalizeLabel(token)) || null;
  };

  const found = [];
  const tokens = choiceTokens(value);
  for (const token of tokens) {
    let code = lookup(token);
    // 여러 선택을 "A, B" 한 문자열로 보내는 경우만 나눠 본다(라벨 자체에
    // 쉼표가 있을 수 있어 통째 대조가 먼저다).
    if (!code && token.includes(',')) {
      for (const part of token.split(',')) {
        const c = lookup(part.trim());
        if (c && !found.includes(map[c])) found.push(map[c]);
      }
      continue;
    }
    if (code && !found.includes(map[code])) found.push(map[code]);
  }
  return found;
}

function deviceFrom(values) {
  const set = new Set(values);
  if (set.has(DEVICE.both) || (set.has(DEVICE.android) && set.has(DEVICE.ios))) return DEVICE.both;
  if (set.has(DEVICE.android)) return DEVICE.android;
  if (set.has(DEVICE.ios)) return DEVICE.ios;
  return null;
}

function isHttpsUrl(u) {
  try {
    return new URL(String(u)).protocol === 'https:';
  } catch (_) {
    return false;
  }
}

/// 첨부 칸 값(FormHug 문서: [{id, name, url, file_size, content_type}]) → 첫 이미지.
/// 파일 내용은 읽지도 파싱하지도 않는다.
function attachmentFrom(v) {
  const list = Array.isArray(v) ? v : (v && typeof v === 'object' ? [v] : []);
  const files = list.filter((f) => f && typeof f === 'object' && isHttpsUrl(f.url));
  if (files.length === 0) return { meta: null, url: null };
  const f = files[0];
  return {
    meta: {
      name: cleanText(f.name, 120),
      contentType: cleanText(f.content_type, 60),
      fileSize: Number.isFinite(Number(f.file_size)) ? Number(f.file_size) : null,
      count: files.length,
    },
    url: String(f.url),
  };
}

/**
 * FormHug 항목 + 관리자가 저장한 매핑 → 신청서 필드.
 *
 * 매핑되지 않은 칸은 **읽지 않는다**(값이 저장될 길 자체가 없다).
 * @returns {{record: object, missingRequired: string[]}}
 */
function mapEntry(entry, config) {
  const fields = (config && config.fields) || {};
  const choices = (config && config.choices) || {};
  const choiceLabels = (config && config.choiceLabels) || {};
  const e = entry || {};
  const raw = (key) => (fields[key] ? e[fields[key]] : undefined);

  const bnRaw = cleanText(raw('businessRegistrationNumber'), 40);
  const bn = normalizeBusinessNumber(bnRaw);
  const hostEmail = cleanText(raw('hostEmail'), 200);
  const sameValues = resolveChoices(
    raw('sameAsRepresentative'), choices.sameAsRepresentative, choiceLabels.sameAsRepresentative,
  );
  const deviceValues = resolveChoices(
    raw('deviceType'), choices.deviceType, choiceLabels.deviceType,
  );
  const shot = attachmentFrom(raw('googlePlayScreenshot'));

  let privacyConsent = null;
  if (fields.privacyConsent) {
    const v = raw('privacyConsent');
    privacyConsent = v === true || choiceTokens(v).length > 0;
  }

  const record = {
    storeName: cleanText(raw('storeName'), 120),
    businessRegistrationNumber: bn || bnRaw,
    businessNumberValid: !!bn,
    hostName: cleanText(raw('hostName'), 60),
    hostEmail,
    hostEmailLower: hostEmail.toLowerCase(),
    hostPhone: digitsOnly(cleanText(raw('hostPhone'), 40)).slice(0, 20),
    sameAsRepresentative: sameValues.length === 1 ? sameValues[0] === true : null,
    representativeName: cleanText(raw('representativeName'), 60),
    representativePhone: digitsOnly(cleanText(raw('representativePhone'), 40)).slice(0, 20),
    representativeEmail: cleanText(raw('representativeEmail'), 200),
    deviceType: deviceFrom(deviceValues),
    googlePlayScreenshot: shot.meta,
    googlePlayScreenshotUrl: shot.url,
    privacyConsent,
    additionalMessage: cleanText(raw('additionalMessage'), 2000),
  };

  const missingRequired = [];
  for (const f of MAPPABLE_FIELDS) {
    if (!f.required) continue;
    const v = record[f.key];
    if (v === null || v === undefined || v === '') missingRequired.push(f.key);
  }
  return { record, missingRequired };
}

/// FormHug 폼 정의 → 관리자 화면에 보여줄 최소 모양(항목 값은 없다).
function summarizeFormFields(form) {
  const fields = Array.isArray(form && form.fields) ? form.fields : [];
  return fields
    .filter((f) => f && typeof f.api_code === 'string' && f.api_code)
    .map((f) => ({
      apiCode: f.api_code,
      label: cleanText(f.label, 200),
      type: cleanText(f.type, 40),
      required: f.required === true,
      choices: Array.isArray(f.choices)
        ? f.choices
          .filter((c) => c && typeof c.api_code === 'string')
          .map((c) => ({ apiCode: c.api_code, label: cleanText(c.label, 200) }))
        : [],
    }));
}

/**
 * 라벨을 보고 매핑을 **제안만** 한다. 저장은 관리자가 확인한 뒤에만 된다 —
 * 폼 라벨은 언제든 바뀔 수 있어 자동 확정하지 않는다.
 */
function suggestConfig(summaryFields) {
  const has = (l, ...ws) => ws.some((w) => l.includes(w));
  const isRep = (l) => has(l, '대표');
  const rules = [
    ['businessRegistrationNumber', (l) => has(l, '사업자') && has(l, '번호')],
    ['sameAsRepresentative', (l, f) => f.choices.length > 0 && has(l, '동일', '같')],
    ['representativeEmail', (l) => isRep(l) && has(l, '이메일', '메일', 'email')],
    ['representativePhone', (l) => isRep(l) && has(l, '연락', '전화', '휴대')],
    ['representativeName', (l) => isRep(l) && has(l, '이름', '성명', '명')],
    ['hostEmail', (l) => !isRep(l) && has(l, '이메일', '메일', 'email')],
    ['hostPhone', (l) => !isRep(l) && has(l, '연락', '전화', '휴대')],
    ['hostName', (l) => !isRep(l) && has(l, '이름', '성명')],
    ['storeName', (l) => has(l, '업체', '상호', '매장', '가게', '스토어') && !has(l, '번호')],
    ['deviceType', (l, f) => f.choices.length > 0 && has(l, '기기', '디바이스', '단말', '기종')],
    ['googlePlayScreenshot', (l, f) => has(f.type, 'attach', 'file', 'image', 'upload')
      || has(l, '캡처', '캡쳐', '스크린샷', 'googleplay', '구글플레이')],
    ['privacyConsent', (l) => has(l, '개인정보')],
    ['additionalMessage', (l) => has(l, '메시지', '문의', '요청', '남기')],
  ];

  const fields = {};
  const used = new Set();
  for (const [key, test] of rules) {
    const f = summaryFields.find((sf) => !used.has(sf.apiCode)
      && test(normalizeLabel(sf.label), { ...sf, type: normalizeLabel(sf.type) }));
    if (f) {
      fields[key] = f.apiCode;
      used.add(f.apiCode);
    }
  }

  const choices = { sameAsRepresentative: {}, deviceType: {} };
  const byCode = new Map(summaryFields.map((f) => [f.apiCode, f]));
  for (const c of (byCode.get(fields.sameAsRepresentative) || { choices: [] }).choices) {
    const l = normalizeLabel(c.label);
    if (has(l, '아니', '다름', '다릅', '다른', 'no')) choices.sameAsRepresentative[c.apiCode] = false;
    else if (has(l, '예', '네', '동일', '같', 'yes')) choices.sameAsRepresentative[c.apiCode] = true;
  }
  for (const c of (byCode.get(fields.deviceType) || { choices: [] }).choices) {
    const l = normalizeLabel(c.label);
    if (has(l, '둘', '모두', '전부', 'both')) choices.deviceType[c.apiCode] = DEVICE.both;
    else if (has(l, 'android', '안드로이드', '갤럭시', 'galaxy')) choices.deviceType[c.apiCode] = DEVICE.android;
    else if (has(l, 'ios', '아이폰', 'iphone')) choices.deviceType[c.apiCode] = DEVICE.ios;
  }
  return { fields, choices };
}

/**
 * 관리자가 보낸 매핑을 폼 정의와 대조해 저장할 모양으로 만든다.
 * 폼에 없는 api_code, 의미를 알 수 없는 값은 받지 않는다.
 */
function validateConfig(input, summaryFields) {
  const byCode = new Map(summaryFields.map((f) => [f.apiCode, f]));
  const src = input || {};
  const fields = {};
  for (const [key, code] of Object.entries(src.fields || {})) {
    if (!MAPPABLE_KEYS.has(key)) throw new HttpsError('invalid-argument', `알 수 없는 항목: ${key}`);
    if (code == null || code === '') continue;
    if (!byCode.has(code)) throw new HttpsError('invalid-argument', `폼에 없는 필드입니다: ${code}`);
    fields[key] = code;
  }
  for (const f of MAPPABLE_FIELDS) {
    if (f.required && !fields[f.key]) {
      throw new HttpsError('invalid-argument', `필수 항목의 필드를 선택해주세요: ${f.label}`);
    }
  }
  const codes = Object.values(fields);
  if (new Set(codes).size !== codes.length) {
    throw new HttpsError('invalid-argument', '같은 폼 필드를 두 항목에 연결할 수 없습니다.');
  }

  const choices = { sameAsRepresentative: {}, deviceType: {} };
  const choiceLabels = { sameAsRepresentative: {}, deviceType: {} };
  const pick = (key, allowed) => {
    const field = byCode.get(fields[key]);
    const valid = new Map(field.choices.map((c) => [c.apiCode, c.label]));
    for (const [code, val] of Object.entries((src.choices || {})[key] || {})) {
      if (!valid.has(code)) throw new HttpsError('invalid-argument', `선택지가 폼에 없습니다: ${code}`);
      if (!allowed.includes(val)) throw new HttpsError('invalid-argument', `선택지 의미가 올바르지 않습니다: ${code}`);
      choices[key][code] = val;
    }
    for (const [code, label] of valid) choiceLabels[key][code] = label;
  };
  pick('sameAsRepresentative', [true, false]);
  pick('deviceType', Object.values(DEVICE));

  const sameVals = Object.values(choices.sameAsRepresentative);
  if (!sameVals.includes(true) || !sameVals.includes(false)) {
    throw new HttpsError('invalid-argument', '"대표자와 동일" 선택지에서 예/아니오를 모두 지정해주세요.');
  }
  if (Object.keys(choices.deviceType).length === 0) {
    throw new HttpsError('invalid-argument', '사용 기기 선택지의 의미를 지정해주세요.');
  }
  return { fields, choices, choiceLabels };
}

/// 대표자 링크 표시 상태. requested라도 만료 시각이 지났으면 만료로 본다
/// (위임 문서 자체는 스케줄러가 없어 requested로 남아 있다).
function linkStatusOf(delegation, nowMs) {
  if (!delegation) return LINK_STATUS.none;
  const s = delegation.status;
  if (s === 'requested') {
    return (toMillis(delegation.expiresAt) ?? 0) <= nowMs ? LINK_STATUS.expired : LINK_STATUS.requested;
  }
  if (Object.values(LINK_STATUS).includes(s)) return s;
  return LINK_STATUS.none;
}

/**
 * **자동 상태 동기화 판정** — 순수 함수.
 *
 * 근거는 호스트의 businessVerification(서버만 쓰는 값)과 위임 문서다.
 * 신청서가 가리키는 사업자번호와 **같은 사업자일 때만** 반영한다.
 *
 * @returns {{patch: object, events: {type: string, message: string}[]}}
 */
function planSync({ pre, hostBv, currentDelegation, latestDelegation, nowMs }) {
  const none = { patch: {}, events: [] };
  if (!pre || pre.status === STATUS.rejected || !pre.hostUid) return none;
  const bn = normalizeBusinessNumber(pre.businessRegistrationNumber);
  if (!bn) return none;

  const patch = {};
  const events = [];
  const status = pre.status;
  const rank = STATUS_RANK[status] ?? 0;
  const bv = hostBv || {};

  // 호스트가 앱에서 직접 만든 대표자 링크도 이 신청서에 붙인다(같은 사업자만).
  if (latestDelegation
    && latestDelegation.id !== pre.delegationId
    && latestDelegation.businessNumberHash === businessNumberHash(bn)
    && latestDelegation.status === 'requested'
    && linkStatusOf(latestDelegation, nowMs) === LINK_STATUS.requested) {
    patch.delegationId = latestDelegation.id;
    events.push({ type: 'representative_link_detected', message: '호스트가 생성한 대표자 인증 링크 연결' });
  }

  const sameBusiness = normalizeBusinessNumber(bv.businessNumber) === bn;
  const authorized = isBusinessAuthorized(bv) && sameBusiness;
  const pending = delegationModule.resolvePendingSubject(bv);
  const pendingForThis = !!pending && normalizeBusinessNumber(pending.input.businessNumber) === bn;

  if (authorized) {
    if (status !== STATUS.verified) {
      patch.status = STATUS.verified;
      if (bv.authorization === AUTHORIZATION.delegated) {
        patch.delegationId = bv.delegationId;
        events.push({ type: 'representative_approved', message: '대표자 승인 완료 — 호스트 사업자 권한 열림(위임)' });
      } else {
        events.push({ type: 'host_business_verified', message: '호스트 본인확인·사업자 인증 완료(본인 명의)' });
      }
    }
    return { patch, events };
  }

  if (status === STATUS.verified) {
    patch.status = pendingForThis ? STATUS.representativeVerificationRequired : STATUS.preregistered;
    events.push({ type: 'authorization_lost', message: '호스트의 사업자 사용 권한이 해제된 것을 확인' });
    return { patch, events };
  }

  if (pendingForThis && rank < STATUS_RANK.representativeVerificationRequired) {
    patch.status = STATUS.representativeVerificationRequired;
    events.push({ type: 'representative_verification_required', message: '호스트 사업자 인증 결과: 대표자 확인 필요' });
    return { patch, events };
  }

  if (status === STATUS.representativeLinkSent) {
    const ls = linkStatusOf(currentDelegation, nowMs);
    if (ls === LINK_STATUS.expired || ls === LINK_STATUS.revoked || ls === LINK_STATUS.rejected
      || ls === LINK_STATUS.none) {
      patch.status = STATUS.representativeVerificationRequired;
      events.push({ type: 'representative_link_closed', message: '대표자 인증 링크가 만료·취소되어 재발급 필요' });
    }
  }
  return { patch, events };
}

// ══════════════════════════════════════════════════════════════════════════
// Firestore
// ══════════════════════════════════════════════════════════════════════════

const preRef = (db, id) => db.collection(COLLECTION).doc(id);
const configRef = (db) => db.collection(CONFIG_COLLECTION).doc(CONFIG_DOC);
const ts = () => admin.firestore.FieldValue.serverTimestamp();

/// 처리 이력 한 줄. at은 문서 시각, 내용에 개인정보·토큰을 넣지 않는다.
function historyEntry(type, message, { actorUid = null, actorType = 'system' } = {}) {
  return { type, message, actorUid, actorType, at: ts() };
}

function writeHistory(writer, db, id, entry) {
  writer.set(preRef(db, id).collection(HISTORY).doc(), entry);
}

async function loadConfig(db) {
  const snap = await configRef(db).get();
  if (!snap.exists) return null;
  const d = snap.data();
  return d && d.fields ? d : null;
}

async function formhugGet(path, apiToken, fetchImpl = fetch) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), FETCH_TIMEOUT_MS);
  try {
    const r = await fetchImpl(`${FORMHUG_API_BASE}${path}`, {
      headers: { Authorization: `Bearer ${apiToken}`, Accept: 'application/json' },
      signal: ctrl.signal,
    });
    if (!r.ok) {
      const err = new Error(`FormHug API HTTP ${r.status}`);
      err.httpStatus = r.status;
      throw err;
    }
    const j = await r.json();
    return j && j.data;
  } finally {
    clearTimeout(timer);
  }
}

const defaultFormhug = (apiToken) => ({
  fetchEntry: (formToken, serial) =>
    formhugGet(`/forms/${encodeURIComponent(formToken)}/entries/${serial}`, apiToken),
  fetchForm: (formToken) => formhugGet(`/forms/${encodeURIComponent(formToken)}`, apiToken),
});

function blankRecord() {
  return {
    storeName: '',
    businessRegistrationNumber: '',
    businessNumberValid: false,
    hostName: '',
    hostEmail: '',
    hostEmailLower: '',
    hostPhone: '',
    sameAsRepresentative: null,
    representativeName: '',
    representativePhone: '',
    representativeEmail: '',
    deviceType: null,
    googlePlayScreenshot: null,
    googlePlayScreenshotUrl: null,
    privacyConsent: null,
    additionalMessage: '',
  };
}

/**
 * 항목 하나를 가져와 신청서 필드에 반영한다. 관리 필드(status·hostUid·memo…)는
 * 건드리지 않는다.
 *
 * 우선순위: API 재조회(정본) → 실패 시 웹훅에 실려 온 항목.
 */
async function importInto(db, id, { formToken, serialNumber, payloadEntry, formhug, config }) {
  if (!config) {
    await preRef(db, id).set({ importState: 'needsFieldMap', updatedAt: ts() }, { merge: true });
    return { importState: 'needsFieldMap' };
  }

  let entry = null;
  let importSource = 'api';
  let fetchError = null;
  if (formhug) {
    try {
      entry = await formhug.fetchEntry(formToken, serialNumber);
    } catch (e) {
      fetchError = e;
    }
  }
  if (!entry && payloadEntry) {
    entry = payloadEntry;
    importSource = 'webhookPayload';
  }
  if (!entry) {
    await preRef(db, id).set({
      importState: 'fetchFailed',
      lastImportErrorStatus: (fetchError && fetchError.httpStatus) || null,
      updatedAt: ts(),
    }, { merge: true });
    return { importState: 'fetchFailed', error: fetchError };
  }

  const { record, missingRequired } = mapEntry(entry, config);
  await preRef(db, id).set({
    ...record,
    formEntryId: typeof entry.token === 'string' ? entry.token : null,
    googlePlayScreenshotUrlFetchedAt: record.googlePlayScreenshotUrl ? ts() : null,
    missingRequired,
    importState: 'ok',
    importSource,
    importedAt: ts(),
    lastImportErrorStatus: null,
    updatedAt: ts(),
  }, { merge: true });
  return { importState: 'ok', missingRequired };
}

/**
 * 웹훅 수신 — **같은 항목은 한 번만 만든다.**
 *
 * 문서 id가 폼 토큰+일련번호에서 결정되므로 재전송이 몇 번 와도 문서는 하나다.
 * 이미 들어온 entry_created는 아무것도 하지 않는다(가져오기가 실패해 있던 건만
 * 다시 시도한다). entry_updated는 신청서 필드만 다시 가져온다.
 *
 * @returns {{httpStatus: number, code: string, id?: string}}
 */
async function receiveEntry(db, { eventType, formToken, serialNumber, entry, formhug, now = Date.now() }) {
  const id = docIdFor(formToken, serialNumber);
  const ref = preRef(db, id);

  const createdAtMs = Date.parse(String((entry && entry.created_at) || ''));
  const submittedAt = Number.isFinite(createdAtMs)
    ? admin.firestore.Timestamp.fromMillis(createdAtMs)
    : admin.firestore.Timestamp.fromMillis(now);

  const created = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (snap.exists) return { created: false, data: snap.data() };
    tx.set(ref, {
      source: 'formhug',
      formToken,
      serialNumber,
      formEntryId: null,
      submittedAt,
      status: STATUS.new,
      importState: 'pending',
      ...blankRecord(),
      googlePlayScreenshotUrlFetchedAt: null,
      missingRequired: [],
      hostUid: null,
      delegationId: null,
      memo: '',
      rejectReason: null,
      createdAt: ts(),
      updatedAt: ts(),
      processedAt: null,
      processedBy: null,
    });
    writeHistory(tx, db, id, historyEntry('received', `신청 접수 (FormHug #${serialNumber})`, { actorType: 'applicant' }));
    return { created: true, data: null };
  });

  if (!created.created) {
    const retryImport = created.data.importState !== 'ok';
    if (eventType === 'entry_created' && !retryImport) {
      return { httpStatus: 200, code: 'duplicate', id };
    }
  }

  const config = await loadConfig(db);
  const out = await importInto(db, id, { formToken, serialNumber, payloadEntry: entry, formhug, config });

  if (!created.created && eventType === 'entry_updated' && out.importState === 'ok') {
    await ref.collection(HISTORY).doc().set(historyEntry('form_updated', '신청서 수정 내용 반영', { actorType: 'applicant' }));
  }

  if (out.importState === 'fetchFailed') return { httpStatus: 503, code: 'fetchFailed', id };
  return { httpStatus: 200, code: created.created ? 'created' : 'updated', id, importState: out.importState };
}

async function latestDelegationOf(db, uid) {
  const snap = await db
    .collection(delegationModule.DELEGATIONS)
    .where('granteeUid', '==', uid)
    .orderBy('requestedAt', 'desc')
    .limit(1)
    .get();
  if (snap.empty) return null;
  return { id: snap.docs[0].id, ...snap.docs[0].data() };
}

async function delegationById(db, id) {
  if (!id) return null;
  const snap = await db.collection(delegationModule.DELEGATIONS).doc(id).get();
  return snap.exists ? { id: snap.id, ...snap.data() } : null;
}

/// 호스트 문서·위임 문서를 읽고 planSync 결과를 기록한다. 바뀐 것이 없으면 쓰지 않는다.
async function applySync(db, id, { nowMs = Date.now() } = {}) {
  const snap = await preRef(db, id).get();
  if (!snap.exists) return null;
  const pre = { id, ...snap.data() };
  if (!pre.hostUid) return { pre, hostData: null, currentDelegation: null };

  const hostSnap = await db.collection('users').doc(pre.hostUid).get();
  const hostData = hostSnap.exists ? hostSnap.data() : null;
  const [currentDelegation, latestDelegation] = await Promise.all([
    delegationById(db, pre.delegationId),
    latestDelegationOf(db, pre.hostUid),
  ]);

  const plan = planSync({
    pre,
    hostBv: hostData && hostData.businessVerification,
    currentDelegation,
    latestDelegation,
    nowMs,
  });
  if (Object.keys(plan.patch).length === 0) {
    return { pre, hostData, currentDelegation };
  }

  const batch = db.batch();
  batch.set(preRef(db, id), { ...plan.patch, updatedAt: ts() }, { merge: true });
  for (const ev of plan.events) writeHistory(batch, db, id, historyEntry(ev.type, ev.message));
  await batch.commit();

  if (plan.patch.status === STATUS.verified) {
    await logUserActivity(db, {
      uid: pre.hostUid,
      activityType: 'host_preregistration_verified',
      refCollection: COLLECTION,
      refId: id,
    });
  }
  const nextDelegationId = plan.patch.delegationId !== undefined ? plan.patch.delegationId : pre.delegationId;
  return {
    pre: { ...pre, ...plan.patch },
    hostData,
    currentDelegation: nextDelegationId === pre.delegationId
      ? currentDelegation
      : await delegationById(db, nextDelegationId),
  };
}

// ── 관리자 ───────────────────────────────────────────────────────────────

async function assertAdmin(db, auth) {
  if (!auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
  const snap = await db.collection('users').doc(auth.uid).get();
  if (!snap.exists || snap.data().role !== 'admin') {
    throw new HttpsError('permission-denied', '관리자만 사용할 수 있습니다.');
  }
  return auth.uid;
}

async function getPreOrThrow(db, id) {
  if (!id || typeof id !== 'string') throw new HttpsError('invalid-argument', '신청서 id가 필요합니다.');
  const snap = await preRef(db, id).get();
  if (!snap.exists) throw new HttpsError('not-found', '신청서를 찾을 수 없습니다.');
  return { id, ...snap.data() };
}

/// 이 신청서의 이메일로 가입한 회원 후보. **후보일 뿐 연결 근거가 아니다.**
async function findHostCandidates(db, emailLower, { getUserByEmail } = {}) {
  if (!emailLower || !emailLower.includes('@')) return [];
  const matched = new Map(); // uid → Set(matchedBy)
  const add = (uid, how) => {
    if (!matched.has(uid)) matched.set(uid, new Set());
    matched.get(uid).add(how);
  };

  const byEmail = await db.collection('users').where('emailLower', '==', emailLower).limit(5).get();
  byEmail.docs.forEach((d) => add(d.id, 'accountEmail'));
  const bySocial = await db.collection('users').where('socialAccount.email', '==', emailLower).limit(5).get();
  bySocial.docs.forEach((d) => add(d.id, 'socialAccountEmail'));
  if (getUserByEmail) {
    try {
      const u = await getUserByEmail(emailLower);
      if (u && u.uid) add(u.uid, 'authEmail');
    } catch (_) {
      // 없는 이메일이면 auth/user-not-found — 후보가 없을 뿐이다.
    }
  }

  const out = [];
  for (const [uid, how] of matched) {
    const s = await db.collection('users').doc(uid).get();
    if (!s.exists) continue;
    out.push({ ...hostSummary(uid, s.data(), null), matchedBy: [...how] });
  }
  return out;
}

/// 관리자에게 돌려줄 호스트 요약. CI·전화번호·토큰은 담지 않는다.
function hostSummary(uid, d, preBusinessNumber) {
  const bv = (d && d.businessVerification) || {};
  const bn = normalizeBusinessNumber(preBusinessNumber);
  const pending = delegationModule.resolvePendingSubject(bv);
  return {
    uid,
    nickname: (d && d.nickname) || '',
    email: (d && d.email) || '',
    signupProvider: (d && d.signupProvider) || '',
    identityVerified: !!(d && (d.identityVerified === true || d.isVerified === true)),
    accountStatus: (d && d.accountStatus) || 'active',
    createdAtMs: toMillis(d && d.createdAt),
    business: {
      status: bv.status || '',
      authorization: bv.authorization || '',
      authorizationReason: bv.authorizationReason || '',
      businessNumberMatches: !!bn && normalizeBusinessNumber(bv.businessNumber) === bn,
      authorizedForThis: !!bn && isBusinessAuthorized(bv) && normalizeBusinessNumber(bv.businessNumber) === bn,
      pendingOwnerApprovalForThis: !!bn && !!pending
        && normalizeBusinessNumber(pending.input.businessNumber) === bn,
      verifiedRepresentativeName: pending ? pending.input.representativeName
        : (bv.status === 'verified' ? (bv.representativeName || '') : ''),
    },
  };
}

function emailOwnedBy(userData, authEmail, emailLower) {
  const d = userData || {};
  const cands = [
    d.emailLower,
    d.email,
    d.socialAccount && d.socialAccount.email,
    authEmail,
  ].filter((v) => typeof v === 'string').map((v) => v.trim().toLowerCase());
  return !!emailLower && cands.includes(emailLower);
}

const ADMIN_ACTIONS = new Set([
  'markPreregistered', 'markHostLinkSent', 'markRepresentativeLinkSent',
  'reject', 'reopen', 'saveMemo', 'linkHost', 'unlinkHost',
]);

/**
 * 관리자 처리 — 상태 전이는 전부 여기 한 곳을 거친다.
 * @returns {{status: string}}
 */
async function updatePreRegistration(db, {
  id, action, actorUid, memo, reason, uid, allowEmailMismatch, authLookup, nowMs = Date.now(),
}) {
  if (!ADMIN_ACTIONS.has(action)) throw new HttpsError('invalid-argument', '알 수 없는 처리입니다.');
  const actor = { actorUid, actorType: 'admin' };
  const ref = preRef(db, id);

  // 연결 대상 확인은 트랜잭션 밖에서 먼저(Auth 조회는 트랜잭션에 넣을 수 없다).
  let linkTarget = null;
  if (action === 'linkHost') {
    if (!uid || typeof uid !== 'string') throw new HttpsError('invalid-argument', '연결할 회원 uid가 필요합니다.');
    const userSnap = await db.collection('users').doc(uid).get();
    if (!userSnap.exists) throw new HttpsError('not-found', '회원을 찾을 수 없습니다.');
    let authEmail = null;
    if (authLookup) {
      try { authEmail = (await authLookup(uid)).email || null; } catch (_) { authEmail = null; }
    }
    linkTarget = { data: userSnap.data(), authEmail };
  }

  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError('not-found', '신청서를 찾을 수 없습니다.');
    const pre = snap.data();
    const status = pre.status;
    const patch = { updatedAt: ts() };
    const events = [];
    const bad = (msg) => { throw new HttpsError('failed-precondition', msg); };

    switch (action) {
      case 'markPreregistered':
        if (![STATUS.new, STATUS.reviewing].includes(status)) bad('신규·확인중 신청만 사전등록 완료로 바꿀 수 있습니다.');
        patch.status = STATUS.preregistered;
        patch.processedAt = ts();
        patch.processedBy = actorUid;
        events.push(['preregistered', '사전등록 완료']);
        break;

      case 'markHostLinkSent':
        if (![STATUS.reviewing, STATUS.preregistered].includes(status)) {
          bad('사전등록 완료 이후, 호스트 인증 전 단계에서만 안내 발송을 기록할 수 있습니다.');
        }
        patch.status = STATUS.hostLinkSent;
        events.push(['host_link_sent', '호스트 본인확인·사업자 인증 안내 발송 처리']);
        break;

      case 'markRepresentativeLinkSent': {
        if (status === STATUS.verified || status === STATUS.rejected) bad('완료·반려된 신청입니다.');
        if (!pre.delegationId) bad('먼저 대표자 인증 링크를 생성해주세요.');
        const dSnap = await tx.get(db.collection(delegationModule.DELEGATIONS).doc(pre.delegationId));
        const d = dSnap.exists ? dSnap.data() : null;
        if (linkStatusOf(d, nowMs) !== LINK_STATUS.requested) bad('유효한(대기중) 대표자 링크가 없습니다. 재발급 후 발송해주세요.');
        patch.status = STATUS.representativeLinkSent;
        events.push(['representative_link_sent', '대표자 인증 링크 발송 처리']);
        break;
      }

      case 'reject': {
        if (status === STATUS.verified) bad('인증 완료된 신청은 반려할 수 없습니다.');
        const r = cleanText(reason, 300);
        if (!r) throw new HttpsError('invalid-argument', '반려 사유를 입력해주세요.');
        patch.status = STATUS.rejected;
        patch.rejectReason = r;
        patch.processedAt = ts();
        patch.processedBy = actorUid;
        events.push(['rejected', `반려 — ${r}`]);
        break;
      }

      case 'reopen':
        if (status !== STATUS.rejected) bad('반려된 신청만 다시 열 수 있습니다.');
        patch.status = STATUS.reviewing;
        patch.rejectReason = null;
        events.push(['reopened', '반려 취소 — 다시 확인중']);
        break;

      case 'saveMemo':
        patch.memo = String(memo == null ? '' : memo).slice(0, 2000);
        events.push(['memo_updated', '관리자 메모 수정']);
        break;

      case 'linkHost': {
        if (status === STATUS.rejected) bad('반려된 신청에는 계정을 연결할 수 없습니다.');
        if (pre.hostUid === uid) bad('이미 이 계정이 연결돼 있습니다.');
        if (pre.hostUid) bad('다른 계정이 연결돼 있습니다. 먼저 연결을 해제해주세요.');
        if (linkTarget.data.accountStatus === 'withdrawn') bad('탈퇴한 계정은 연결할 수 없습니다.');
        const matched = emailOwnedBy(linkTarget.data, linkTarget.authEmail, pre.hostEmailLower);
        const overrideReason = cleanText(reason, 300);
        if (!matched && !(allowEmailMismatch === true && overrideReason)) {
          bad('신청서 이메일과 계정 이메일이 다릅니다. 확인 후 사유를 적어 연결해주세요.');
        }
        const dup = await tx.get(db.collection(COLLECTION).where('hostUid', '==', uid).limit(5));
        const other = dup.docs.find((d) => d.id !== id && d.data().status !== STATUS.rejected);
        if (other) bad('이 계정은 이미 다른 사전등록 신청에 연결돼 있습니다.');
        patch.hostUid = uid;
        patch.hostLinkedAt = ts();
        patch.hostLinkedBy = actorUid;
        patch.hostLinkMethod = matched ? 'emailMatch' : 'adminOverride';
        events.push(['host_linked', matched
          ? '호스트 계정 연결(이메일 일치 확인)'
          : `호스트 계정 연결(이메일 불일치 — 관리자 확인: ${overrideReason})`]);
        break;
      }

      case 'unlinkHost':
        if (!pre.hostUid) bad('연결된 계정이 없습니다.');
        if (status === STATUS.verified) bad('인증 완료된 신청은 연결을 해제할 수 없습니다.');
        patch.hostUid = null;
        patch.delegationId = null;
        patch.hostLinkedAt = null;
        patch.hostLinkedBy = null;
        patch.hostLinkMethod = null;
        if ((STATUS_RANK[status] ?? 0) > STATUS_RANK.preregistered) patch.status = STATUS.preregistered;
        events.push(['host_unlinked', '호스트 계정 연결 해제']);
        break;

      default:
        break;
    }

    tx.set(ref, patch, { merge: true });
    for (const [type, message] of events) writeHistory(tx, db, id, historyEntry(type, message, actor));
    return { status: patch.status || status, prevHostUid: pre.hostUid || null };
  });

  if (action === 'linkHost') {
    await logUserActivity(db, {
      uid,
      activityType: 'admin_host_preregistration_linked',
      refCollection: COLLECTION,
      refId: id,
      actorType: 'admin',
      actorUid,
    });
  }
  return result;
}

/**
 * **관리자가 대표자 인증 링크를 만든다 — 기존 createDelegationRequest 그대로.**
 *
 * 이 함수가 더하는 것은 "사전등록 건 기준의 사전조건"뿐이다. 토큰 생성·해시
 * 저장·72시간 만료·하루 3회·이전 링크 만료·사업자당 10개 한도는 전부 그 함수가
 * 집행하고, 그 한도는 호스트가 앱에서 만든 요청과 **같은 카운터**를 쓴다.
 *
 * 토큰 원문은 반환값으로 한 번만 나가고 신청서·이력·로그 어디에도 남지 않는다.
 */
async function createDelegationForPreRegistration(db, {
  id, reissue = false, actorUid, nowMs = Date.now(), todayKey = new Date().toISOString().slice(0, 10),
}) {
  const pre = await getPreOrThrow(db, id);
  const bad = (msg) => { throw new HttpsError('failed-precondition', msg); };

  if (pre.status === STATUS.rejected) bad('반려된 신청입니다.');
  if (pre.status === STATUS.verified) bad('이미 인증이 완료된 신청입니다.');
  if (pre.sameAsRepresentative !== false) {
    bad('호스트와 대표자가 같은 신청은 대표자 링크가 필요 없습니다. 호스트가 앱에서 본인확인·사업자 인증을 진행하면 됩니다.');
  }
  if (!pre.hostUid) bad('먼저 호스트 계정을 연결해주세요.');
  const bn = normalizeBusinessNumber(pre.businessRegistrationNumber);
  if (!bn) bad('신청서의 사업자등록번호가 올바르지 않습니다.');
  if (!cleanText(pre.representativeName)) bad('신청서에 대표자 이름이 없습니다.');

  const hostSnap = await db.collection('users').doc(pre.hostUid).get();
  const bv = (hostSnap.exists && hostSnap.data().businessVerification) || {};
  if (isBusinessAuthorized(bv) && normalizeBusinessNumber(bv.businessNumber) === bn) {
    bad('호스트에게 이미 이 사업자 권한이 열려 있습니다.');
  }
  const subject = delegationModule.resolvePendingSubject(bv);
  if (!subject) {
    bad('호스트가 앱에서 사업자 인증을 먼저 진행해야 합니다(결과가 "대표자 확인 필요"여야 링크를 만들 수 있어요).');
  }
  if (normalizeBusinessNumber(subject.input.businessNumber) !== bn) {
    bad('호스트가 앱에서 인증한 사업자번호가 신청서의 사업자번호와 다릅니다.');
  }

  // 활성 위임 중복 확인 — (granteeUid, status) 기존 색인.
  const active = await db
    .collection(delegationModule.DELEGATIONS)
    .where('granteeUid', '==', pre.hostUid)
    .where('status', 'in', ['requested', 'approved'])
    .get();
  const bnHash = businessNumberHash(bn);
  for (const doc of active.docs) {
    const d = doc.data();
    if (d.status === 'approved' && d.businessNumberHash === bnHash) {
      throw new HttpsError('already-exists', '이 사업자에 대해 이미 승인된 위임이 있습니다.');
    }
    if (d.status === 'requested' && linkStatusOf(d, nowMs) === LINK_STATUS.requested && !reissue) {
      throw new HttpsError('already-exists', '대기 중인 대표자 링크가 있습니다. 링크를 잃어버렸다면 재발급을 사용해주세요.');
    }
  }

  // ⚠️ 복제하지 않는다 — 앱 콜러블과 같은 함수, 같은 한도.
  const result = await delegationModule.createDelegationRequest(db, pre.hostUid, {
    now: ts(),
    todayKey,
  });

  const rank = STATUS_RANK[pre.status] ?? 0;
  const nextStatus = rank <= STATUS_RANK.representativeLinkSent
    ? STATUS.representativeVerificationRequired
    : pre.status;
  const expires = new Date(result.expiresAtMs + 9 * 60 * 60 * 1000).toISOString()
    .slice(0, 16).replace('T', ' ');

  const batch = db.batch();
  batch.set(preRef(db, id), {
    delegationId: result.delegationId,
    delegationRequestedAt: ts(),
    status: nextStatus,
    updatedAt: ts(),
  }, { merge: true });
  writeHistory(batch, db, id, historyEntry(
    reissue ? 'representative_link_reissued' : 'representative_link_created',
    `대표자 인증 링크 ${reissue ? '재발급' : '생성'} (만료 ${expires} KST)`,
    { actorUid, actorType: 'admin' },
  ));
  await batch.commit();

  await logUserActivity(db, {
    uid: pre.hostUid,
    activityType: 'admin_business_delegation_link_created',
    refCollection: delegationModule.DELEGATIONS,
    refId: result.delegationId,
    actorType: 'admin',
    actorUid,
  });

  return {
    delegationId: result.delegationId,
    approvalUrl: delegationModule.approvalUrlOf(result.token),
    expiresAtMs: result.expiresAtMs,
    businessNumberMasked: result.businessNumberMasked,
  };
}

function serializePre(pre) {
  const out = {};
  for (const [k, v] of Object.entries(pre)) {
    const ms = v && typeof v === 'object' && !Array.isArray(v) ? toMillis(v) : null;
    out[k] = ms != null ? ms : v;
  }
  return out;
}

// ══════════════════════════════════════════════════════════════════════════
// Cloud Functions
// ══════════════════════════════════════════════════════════════════════════

/// FormHug 웹훅. URL: https://asia-northeast3-partychu-30c24.cloudfunctions.net/hostPreRegistrationWebhook?key=<FORMHUG_WEBHOOK_KEY>
exports.hostPreRegistrationWebhook = onRequest(
  { region: REGION, secrets: [formhugWebhookKey, formhugApiToken], timeoutSeconds: 30, invoker: 'public' },
  async (req, res) => {
    if (req.method !== 'POST') return res.status(405).send('method not allowed');
    if (!keyMatches(req.query.key, formhugWebhookKey.value().trim())) {
      console.warn('[hostPreReg] 웹훅 키 불일치');
      return res.status(401).send('unauthorized');
    }
    const parsed = parseWebhookBody(req.body);
    if (!parsed.ok) {
      console.warn(`[hostPreReg] 웹훅 형식 오류 reason=${parsed.reason}`);
      return res.status(400).send('bad request');
    }
    if (parsed.formToken !== FORMHUG_FORM_TOKEN) {
      console.warn('[hostPreReg] 다른 폼의 웹훅 — 무시');
      return res.status(200).json({ ok: true, result: 'ignoredForm' });
    }
    if (!HANDLED_EVENTS.has(parsed.eventType)) {
      return res.status(200).json({ ok: true, result: 'ignoredEvent' });
    }

    try {
      const apiToken = formhugApiToken.value().trim();
      const out = await receiveEntry(admin.firestore(), {
        ...parsed,
        formhug: apiToken ? defaultFormhug(apiToken) : null,
      });
      // 개인정보 없이 식별자만 남긴다.
      console.log(`[hostPreReg] 웹훅 처리 event=${parsed.eventType} serial=${parsed.serialNumber}`
        + ` result=${out.code} import=${out.importState || '-'}`);
      return res.status(out.httpStatus).json({ ok: out.httpStatus < 300, result: out.code });
    } catch (e) {
      console.error(`[hostPreReg] 웹훅 처리 실패 serial=${parsed.serialNumber} code=${e.code || ''}`);
      return res.status(500).json({ ok: false });
    }
  },
);

/// 상세 조회 + 자동 동기화 + 첨부 링크 갱신 + 호스트 후보.
exports.adminGetHostPreRegistration = onCall(
  { region: REGION, secrets: [formhugApiToken] },
  async (request) => {
    const db = admin.firestore();
    const actorUid = await assertAdmin(db, request.auth);
    const id = request.data && request.data.id;
    let pre = await getPreOrThrow(db, id);

    // 처음 연 신청은 "관리자 확인"으로 넘긴다.
    if (pre.status === STATUS.new) {
      const batch = db.batch();
      batch.set(preRef(db, id), { status: STATUS.reviewing, updatedAt: ts() }, { merge: true });
      writeHistory(batch, db, id, historyEntry('admin_viewed', '관리자 확인', { actorUid, actorType: 'admin' }));
      await batch.commit();
    }

    const synced = await applySync(db, id);
    pre = await getPreOrThrow(db, id);

    // 24시간 서명 링크 갱신 — 항목을 다시 읽어 첨부 링크만 바꾼다.
    const apiToken = formhugApiToken.value().trim();
    const fetchedAt = toMillis(pre.googlePlayScreenshotUrlFetchedAt) || 0;
    if (pre.googlePlayScreenshot && apiToken && pre.serialNumber
      && Date.now() - fetchedAt > ATTACHMENT_URL_REFRESH_MS) {
      try {
        const config = await loadConfig(db);
        const entry = await defaultFormhug(apiToken).fetchEntry(pre.formToken, pre.serialNumber);
        const { record } = mapEntry(entry, config);
        await preRef(db, id).set({
          googlePlayScreenshot: record.googlePlayScreenshot,
          googlePlayScreenshotUrl: record.googlePlayScreenshotUrl,
          googlePlayScreenshotUrlFetchedAt: ts(),
        }, { merge: true });
        pre.googlePlayScreenshot = record.googlePlayScreenshot;
        pre.googlePlayScreenshotUrl = record.googlePlayScreenshotUrl;
        pre.googlePlayScreenshotUrlFetchedAt = { toMillis: () => Date.now() };
      } catch (e) {
        console.warn(`[hostPreReg] 첨부 링크 갱신 실패 id=${id} status=${e.httpStatus || ''}`);
      }
    }

    const hostData = synced && synced.hostData;
    const delegation = synced && synced.currentDelegation;
    const histSnap = await preRef(db, id).collection(HISTORY).orderBy('at', 'asc').limit(200).get();

    return {
      preRegistration: serializePre(pre),
      host: pre.hostUid && hostData ? hostSummary(pre.hostUid, hostData, pre.businessRegistrationNumber) : null,
      candidates: pre.hostUid
        ? []
        : await findHostCandidates(db, pre.hostEmailLower, {
          getUserByEmail: (email) => admin.auth().getUserByEmail(email),
        }),
      delegation: delegation
        ? {
          id: delegation.id,
          linkStatus: linkStatusOf(delegation, Date.now()),
          businessNumberMasked: delegation.businessNumberMasked || '',
          requestedAtMs: toMillis(delegation.requestedAt),
          expiresAtMs: toMillis(delegation.expiresAt),
          approvedAtMs: toMillis(delegation.approvedAt),
          attemptCount: delegation.attemptCount || 0,
          needsManualReview: delegation.needsManualReview === true,
        }
        : null,
      history: histSnap.docs.map((d) => serializePre({ id: d.id, ...d.data() })),
      formUrl: FORMHUG_FORM_URL,
    };
  },
);

/// 관리자 처리(상태·메모·계정 연결).
exports.adminUpdateHostPreRegistration = onCall(
  { region: REGION },
  async (request) => {
    const db = admin.firestore();
    const actorUid = await assertAdmin(db, request.auth);
    const data = request.data || {};
    await getPreOrThrow(db, data.id);
    const result = await updatePreRegistration(db, {
      id: data.id,
      action: data.action,
      actorUid,
      memo: data.memo,
      reason: data.reason,
      uid: data.uid,
      allowEmailMismatch: data.allowEmailMismatch === true,
      authLookup: (uid) => admin.auth().getUser(uid),
    });
    if (['linkHost', 'markPreregistered', 'markHostLinkSent', 'reopen'].includes(data.action)) {
      await applySync(db, data.id);
    }
    console.log(`[hostPreReg] 관리자 처리 id=${data.id} action=${data.action} status=${result.status}`);
    return { success: true };
  },
);

/// 관리자 전용 대표자 링크 생성/재발급 — 내부는 기존 createDelegationRequest.
exports.adminCreateBusinessDelegationForPreregistration = onCall(
  { region: REGION },
  async (request) => {
    const db = admin.firestore();
    const actorUid = await assertAdmin(db, request.auth);
    const data = request.data || {};
    const out = await createDelegationForPreRegistration(db, {
      id: data.id,
      reissue: data.reissue === true,
      actorUid,
    });
    // ⚠️ 링크(토큰 원문)는 로그에 남기지 않는다.
    console.log(`[hostPreReg] 대표자 링크 ${data.reissue === true ? '재발급' : '생성'}`
      + ` id=${data.id} delegationId=${out.delegationId}`);
    return out;
  },
);

/// FormHug 폼 필드 연결(매핑) — 조회·저장·다시 가져오기.
exports.adminHostPreRegistrationFormSetup = onCall(
  { region: REGION, secrets: [formhugApiToken], timeoutSeconds: 120 },
  async (request) => {
    const db = admin.firestore();
    const actorUid = await assertAdmin(db, request.auth);
    const data = request.data || {};
    const apiToken = formhugApiToken.value().trim();
    if (!apiToken) {
      throw new HttpsError('failed-precondition', 'FORMHUG_API_TOKEN 시크릿이 설정되지 않았습니다.');
    }
    const formhug = defaultFormhug(apiToken);

    const loadFields = async () => {
      try {
        const form = await formhug.fetchForm(FORMHUG_FORM_TOKEN);
        return { name: cleanText(form && form.name, 200), fields: summarizeFormFields(form) };
      } catch (e) {
        throw new HttpsError('unavailable', `FormHug 폼 정의를 읽지 못했습니다(HTTP ${e.httpStatus || '-'}).`);
      }
    };

    const reimportIds = async (ids) => {
      const config = await loadConfig(db);
      let ok = 0;
      let failed = 0;
      for (const pid of ids) {
        const s = await preRef(db, pid).get();
        if (!s.exists) continue;
        const p = s.data();
        const out = await importInto(db, pid, {
          formToken: p.formToken, serialNumber: p.serialNumber, payloadEntry: null, formhug, config,
        });
        if (out.importState === 'ok') {
          ok += 1;
          await preRef(db, pid).collection(HISTORY).doc().set(
            historyEntry('form_reimported', 'FormHug에서 신청서 다시 가져오기', { actorUid, actorType: 'admin' }),
          );
        } else {
          failed += 1;
        }
      }
      return { ok, failed };
    };

    switch (data.action) {
      case 'getFields': {
        const form = await loadFields();
        const config = await loadConfig(db);
        return {
          formToken: FORMHUG_FORM_TOKEN,
          formName: form.name,
          fields: form.fields,
          mappable: MAPPABLE_FIELDS,
          config: config ? { fields: config.fields, choices: config.choices } : null,
          suggestion: suggestConfig(form.fields),
        };
      }
      case 'saveConfig': {
        const form = await loadFields();
        const valid = validateConfig(data.config, form.fields);
        await configRef(db).set({
          formToken: FORMHUG_FORM_TOKEN,
          ...valid,
          updatedAt: ts(),
          updatedBy: actorUid,
        });
        const pending = await db.collection(COLLECTION)
          .where('importState', 'in', ['needsFieldMap', 'fetchFailed', 'pending'])
          .limit(50)
          .get();
        const r = await reimportIds(pending.docs.map((d) => d.id));
        console.log(`[hostPreReg] 필드 연결 저장 reimport ok=${r.ok} failed=${r.failed}`);
        return { saved: true, reimported: r };
      }
      case 'reimport': {
        await getPreOrThrow(db, data.id);
        const r = await reimportIds([data.id]);
        if (r.ok !== 1) throw new HttpsError('unavailable', '다시 가져오지 못했습니다. 필드 연결과 FormHug 토큰을 확인해주세요.');
        return { reimported: r };
      }
      default:
        throw new HttpsError('invalid-argument', '알 수 없는 요청입니다.');
    }
  },
);

/// 위임 문서가 바뀌면(생성·승인·취소·만료) 그 호스트의 사전등록 상태를 맞춘다.
/// 위임 문서는 드물게 쓰이므로 users 전체에 트리거를 거는 대신 여기에 건다.
/// 호스트 본인 명의 인증(self)은 관리자가 상세를 열 때 같은 applySync로 반영된다.
exports.onBusinessDelegationWriteSyncPreRegistration = onDocumentWritten(
  { document: 'businessDelegations/{delegationId}', region: REGION },
  async (event) => {
    const before = event.data && event.data.before && event.data.before.exists
      ? event.data.before.data() : null;
    const after = event.data && event.data.after && event.data.after.exists
      ? event.data.after.data() : null;
    if (!after || !after.granteeUid) return;
    // NICE 시도 횟수만 오른 쓰기 등은 상태에 영향이 없다.
    if (before && before.status === after.status) return;

    const db = admin.firestore();
    const snap = await db.collection(COLLECTION).where('hostUid', '==', after.granteeUid).limit(10).get();
    for (const doc of snap.docs) {
      if (doc.data().status === STATUS.rejected) continue;
      try {
        await applySync(db, doc.id);
      } catch (e) {
        console.error(`[hostPreReg] 위임 동기화 실패 id=${doc.id} code=${e.code || ''}`);
      }
    }
  },
);

// ── 셀프체크용 ──────────────────────────────────────────────────────────
module.exports.__test = {
  COLLECTION,
  HISTORY,
  CONFIG_COLLECTION,
  CONFIG_DOC,
  FORMHUG_FORM_TOKEN,
  STATUS,
  LINK_STATUS,
  DEVICE,
  MAPPABLE_FIELDS,
  keyMatches,
  docIdFor,
  parseWebhookBody,
  resolveChoices,
  mapEntry,
  summarizeFormFields,
  suggestConfig,
  validateConfig,
  linkStatusOf,
  planSync,
  receiveEntry,
  applySync,
  assertAdmin,
  findHostCandidates,
  updatePreRegistration,
  createDelegationForPreRegistration,
};

// ── 파티 연령 제한 — 성별별 규칙 한 벌 ───────────────────────────────────────
//
// 이 파일은 party_app/lib/models/party_age_restriction.dart의 **거울**이다.
// 한쪽만 고치면 앱과 서버가 서로 다른 파티 문서를 만들거나(등록) 서로 다른
// 신청 자격 판정을 하게 된다(신청). 규칙을 바꿀 때는 반드시 둘 다 고치고
// party_registration_parity_test.dart / partyAgeRestriction.selfcheck.js를
// 함께 돌린다.
//
// ── 저장 필드 ─────────────────────────────────────────────────────────────
//
// 정본(신규 파티):
//   ageRestrictionEnabled                                    ← 마스터 스위치
//   maleAgeRestrictionEnabled   / maleMinBirthYear   / maleMaxBirthYear
//   femaleAgeRestrictionEnabled / femaleMinBirthYear / femaleMaxBirthYear
//
// 하위호환(기존 파티):
//   minBirthYear / maxBirthYear  ← 남녀 **공통** 범위였다.
//
// 성별 필드가 하나도 없는 문서는 기존 파티다 — 공통 범위를 남녀 모두에게
// 똑같이 적용한다. 그래야 이 변경으로 기존 파티의 연령 제한이 사라지지 않는다.
//
// ── 출생연도 방향 ─────────────────────────────────────────────────────────
//
// 출생연도가 **이를수록**(작을수록) 나이가 많다. 그래서
//   minBirthYear = 허용되는 가장 이른 출생연도 = 나이 **상한**
//   maxBirthYear = 허용되는 가장 늦은 출생연도 = 나이 **하한**
// 이다. 경계는 포함이다(min/max 나이 당사자는 신청 가능).

const ENABLED_FIELD = 'ageRestrictionEnabled';
const MALE_ENABLED_FIELD = 'maleAgeRestrictionEnabled';
const MALE_MIN_FIELD = 'maleMinBirthYear';
const MALE_MAX_FIELD = 'maleMaxBirthYear';
const FEMALE_ENABLED_FIELD = 'femaleAgeRestrictionEnabled';
const FEMALE_MIN_FIELD = 'femaleMinBirthYear';
const FEMALE_MAX_FIELD = 'femaleMaxBirthYear';
const LEGACY_MIN_FIELD = 'minBirthYear';
const LEGACY_MAX_FIELD = 'maxBirthYear';

const AGE_FIELDS = [
  ENABLED_FIELD,
  MALE_ENABLED_FIELD,
  MALE_MIN_FIELD,
  MALE_MAX_FIELD,
  FEMALE_ENABLED_FIELD,
  FEMALE_MIN_FIELD,
  FEMALE_MAX_FIELD,
  LEGACY_MIN_FIELD,
  LEGACY_MAX_FIELD,
];

function intOrNull(raw) {
  if (raw === null || raw === undefined || raw === '') return null;
  const n = Number(raw);
  return Number.isFinite(n) ? Math.trunc(n) : null;
}

function has(obj, key) {
  return obj != null && Object.prototype.hasOwnProperty.call(obj, key);
}

function limit(enabled, minBirthYear, maxBirthYear) {
  return {
    enabled: enabled === true,
    minBirthYear: intOrNull(minBirthYear),
    maxBirthYear: intOrNull(maxBirthYear),
  };
}

const OFF_LIMIT = Object.freeze(limit(false, null, null));

/// 이 파티가 실제로 모집하는 성별들.
function applicableGenders(genderLimit) {
  if (genderLimit === 'male') return ['male'];
  if (genderLimit === 'female') return ['female'];
  return ['male', 'female'];
}

/// 파티 **문서**에서 읽는다(Dart PartyAgeRestriction.fromMap과 같은 규칙).
///
/// 돌려주는 값: { enabled, perGender, male, female }
///   · perGender — 성별 필드에서 온 값인가. 성별을 모르는 신청자를 어떻게
///     판정할지가 갈린다([allowsApplicant] 참고).
function parseAgeRestriction(data) {
  const src = data && typeof data === 'object' ? data : {};
  const enabled = src[ENABLED_FIELD] === true;
  const perGender = has(src, MALE_ENABLED_FIELD) || has(src, FEMALE_ENABLED_FIELD);

  if (!perGender) {
    const legacy = limit(enabled, src[LEGACY_MIN_FIELD], src[LEGACY_MAX_FIELD]);
    return { enabled, perGender: false, male: legacy, female: legacy };
  }
  return {
    enabled,
    perGender: true,
    male: limit(src[MALE_ENABLED_FIELD] === true, src[MALE_MIN_FIELD], src[MALE_MAX_FIELD]),
    female: limit(
      src[FEMALE_ENABLED_FIELD] === true,
      src[FEMALE_MIN_FIELD],
      src[FEMALE_MAX_FIELD]
    ),
  };
}

function hasAnyLimit(age) {
  return age.enabled === true && (age.male.enabled || age.female.enabled);
}

function limitFor(age, gender) {
  if (!age.enabled) return OFF_LIMIT;
  if (gender === 'male') return age.male;
  if (gender === 'female') return age.female;
  return OFF_LIMIT;
}

/// 출생연도 하나가 그 성별 범위 안인가.
function limitAllows(l, birthYear) {
  if (!l.enabled) return true;
  if (birthYear === null || birthYear === undefined) return false;
  const y = Number(birthYear);
  if (!Number.isFinite(y)) return false;
  if (l.minBirthYear !== null && y < l.minBirthYear) return false;
  if (l.maxBirthYear !== null && y > l.maxBirthYear) return false;
  return true;
}

/// 이 신청자에게 **실제로 적용되는 제한 하나**.
///
///   · 제한이 없는 파티          → 꺼진 제한(누구나 통과)
///   · 성별을 아는 신청자        → 그 성별의 제한
///   · 성별을 모르는데 성별별 제한 → **null(판정 불가)**. 성별을 안 보낸 호출로
///     성별별 제한을 우회할 수 없어야 한다.
///   · 성별을 모르는데 옛 공통 파티 → 공통 범위(예전과 똑같이 생년만으로 판정)
function effectiveLimitFor(age, gender) {
  if (!hasAnyLimit(age)) return OFF_LIMIT;
  const known = gender === 'male' || gender === 'female';
  if (!known) return age.perGender ? null : age.male;
  return limitFor(age, gender);
}

/// 신청 자격 — **자기 성별의 제한만** 본다.
function allowsApplicant(age, gender, birthYear) {
  const mine = effectiveLimitFor(age, gender);
  if (mine === null) return false;
  return limitAllows(mine, birthYear);
}

/// 파티 문서 + 신청자(성별/생년) → 신청 가능 여부. 호출부가 쓰는 얼굴.
function documentAllowsApplicant(data, gender, birthYear) {
  return allowsApplicant(parseAgeRestriction(data), gender, birthYear);
}

// ═══════════════════════════════════════════════════════════════════════════
// 등록 입력 정규화 / 문서 필드 조립
// ═══════════════════════════════════════════════════════════════════════════

/// createParty 입력의 `age` 블록을 정규화한다.
///
/// 새 스키마:
///   age: { enabled, male: {enabled,minBirthYear,maxBirthYear}, female: {...} }
///
/// 옛 스키마(웹 폼 구버전·기존 호출자):
///   age: { enabled, minBirthYear, maxBirthYear }   ← 남녀 공통
///
/// 성별 블록이 하나도 없으면 옛 스키마로 보고 공통 값을 남녀 양쪽에 똑같이
/// 넣는다 — 갱신되지 않은 호출자가 보낸 파티의 연령 제한이 조용히 사라지면
/// 안 되기 때문이다.
function normalizeAgeInput(raw) {
  const src = raw && typeof raw === 'object' ? raw : {};
  const enabled = src.enabled === true;
  const hasPerGender =
    (src.male && typeof src.male === 'object') ||
    (src.female && typeof src.female === 'object');

  if (!hasPerGender) {
    const legacy = limit(enabled, src.minBirthYear, src.maxBirthYear);
    return { enabled, male: { ...legacy }, female: { ...legacy } };
  }
  const readGender = (g) => {
    const gs = src[g] && typeof src[g] === 'object' ? src[g] : {};
    return limit(gs.enabled === true, gs.minBirthYear, gs.maxBirthYear);
  };
  return { enabled, male: readGender('male'), female: readGender('female') };
}

/// 성별 모집 설정에 맞춰 **모집하지 않는 성별의 제한을 지운다.**
///
/// 호스트가 "여성만 모집"으로 바꾸면 남성 칸은 화면에서 사라지는데, 그때
/// 예전에 골라 둔 남성 제한이 문서에 남아 있으면 나중에 '남녀 모두'로 되돌릴
/// 때 아무도 손대지 않은 값이 갑자기 적용된다. 정원(maleCapacity/
/// femaleCapacity)이 같은 규칙으로 0이 되는 것과 같은 처리다.
///
/// 마스터 스위치가 켜져 있어도 남은 제한이 하나도 없으면 꺼진 것으로 본다.
function normalizedFor(age, genderLimit) {
  if (!age.enabled) return { enabled: false, perGender: true, male: OFF_LIMIT, female: OFF_LIMIT };
  const m = genderLimit === 'female' ? OFF_LIMIT : age.male;
  const f = genderLimit === 'male' ? OFF_LIMIT : age.female;
  if (!m.enabled && !f.enabled) {
    return { enabled: false, perGender: true, male: OFF_LIMIT, female: OFF_LIMIT };
  }
  return {
    enabled: true,
    perGender: true,
    male: m.enabled ? m : OFF_LIMIT,
    female: f.enabled ? f : OFF_LIMIT,
  };
}

/// 구버전 앱을 위한 **공통 필드** 값 — 모집하는 모든 성별이 제한을 가질 때만
/// 만들고, 그 범위들의 합집합(가장 넓은 범위)을 쓴다. 한쪽이 제한 없음이면
/// 공통 범위로 표현할 수 없으므로 null을 돌려 필드를 아예 쓰지 않는다.
function legacyRangeFor(age, genderLimit) {
  const limits = applicableGenders(genderLimit).map((g) => limitFor(age, g));
  if (limits.length === 0 || limits.some((l) => !l.enabled)) return null;
  let min = null;
  for (const l of limits) {
    if (l.minBirthYear === null) {
      min = null;
      break;
    }
    min = min === null || l.minBirthYear < min ? l.minBirthYear : min;
  }
  let max = null;
  for (const l of limits) {
    if (l.maxBirthYear === null) {
      max = null;
      break;
    }
    max = max === null || l.maxBirthYear > max ? l.maxBirthYear : max;
  }
  if (min === null && max === null) return null;
  return { min, max };
}

/// 파티 문서에 쓸 연령 필드(Dart PartyAgeRestriction.toFields와 같은 결과).
///
/// 제한이 없으면 `ageRestrictionEnabled: false` 하나만 쓴다 — 읽는 쪽이 모두
/// 이 스위치를 먼저 보므로 예전 값이 남아 있어도 적용되지 않는다.
function ageFields(age, genderLimit) {
  const eff = normalizedFor(age, genderLimit);
  if (!hasAnyLimit(eff)) return { [ENABLED_FIELD]: false };

  const out = {
    [ENABLED_FIELD]: true,
    [MALE_ENABLED_FIELD]: eff.male.enabled,
    [FEMALE_ENABLED_FIELD]: eff.female.enabled,
  };
  if (eff.male.enabled) {
    if (eff.male.minBirthYear !== null) out[MALE_MIN_FIELD] = eff.male.minBirthYear;
    if (eff.male.maxBirthYear !== null) out[MALE_MAX_FIELD] = eff.male.maxBirthYear;
  }
  if (eff.female.enabled) {
    if (eff.female.minBirthYear !== null) out[FEMALE_MIN_FIELD] = eff.female.minBirthYear;
    if (eff.female.maxBirthYear !== null) out[FEMALE_MAX_FIELD] = eff.female.maxBirthYear;
  }
  const legacy = legacyRangeFor(eff, genderLimit);
  if (legacy) {
    if (legacy.min !== null) out[LEGACY_MIN_FIELD] = legacy.min;
    if (legacy.max !== null) out[LEGACY_MAX_FIELD] = legacy.max;
  }
  return out;
}

module.exports = {
  AGE_FIELDS,
  ENABLED_FIELD,
  MALE_ENABLED_FIELD,
  MALE_MIN_FIELD,
  MALE_MAX_FIELD,
  FEMALE_ENABLED_FIELD,
  FEMALE_MIN_FIELD,
  FEMALE_MAX_FIELD,
  LEGACY_MIN_FIELD,
  LEGACY_MAX_FIELD,
  applicableGenders,
  parseAgeRestriction,
  normalizeAgeInput,
  normalizedFor,
  legacyRangeFor,
  ageFields,
  hasAnyLimit,
  limitFor,
  effectiveLimitFor,
  limitAllows,
  allowsApplicant,
  documentAllowsApplicant,
};

/// 파티 연령 제한 — **성별마다 따로** 정한다.
///
/// ## 왜 성별별인가
/// 예전에는 파티 하나에 공통 범위(`minBirthYear`/`maxBirthYear`) 하나뿐이라
/// "남성 25~35 / 여성 23~32"처럼 흔한 모집 조건을 표현할 수 없었다. 이제
/// 남성·여성이 각자 자기 범위(그리고 "이 성별은 제한 없음")를 갖는다.
///
/// ## 저장 필드
/// 정본(신규 파티):
///   · `ageRestrictionEnabled`        — 마스터 스위치
///   · `maleAgeRestrictionEnabled`    / `maleMinBirthYear`   / `maleMaxBirthYear`
///   · `femaleAgeRestrictionEnabled`  / `femaleMinBirthYear` / `femaleMaxBirthYear`
///
/// 하위호환(기존 파티):
///   · `minBirthYear` / `maxBirthYear` — 남녀 **공통** 범위였다. 성별 필드가
///     하나도 없는 문서는 이 값을 남녀 모두에게 똑같이 적용한다. 기존 파티의
///     연령 제한이 이 변경으로 사라지면 안 되기 때문이다.
///
/// 신규 파티도 공통 필드를 **함께** 남긴다(가능할 때만 — [legacyRangeFor]).
/// 아직 갱신되지 않은 구버전 앱이 상세/필터에서 그 값을 읽기 때문이다. 판정의
/// 정본은 어디까지나 성별 필드이고, 서버가 그 기준으로 강제한다.
///
/// ## 출생연도 ↔ 나이
/// 저장은 출생연도, 화면은 나이다. 출생연도가 **이를수록**(작을수록) 나이가
/// 많다 — 그래서 [GenderAgeLimit.minBirthYear]가 나이 **상한**,
/// [GenderAgeLimit.maxBirthYear]가 나이 **하한**에 대응한다.
library;

import 'package:party_app/utils/age_range_utils.dart';

int? _intOrNull(dynamic raw) => raw is num ? raw.toInt() : null;

/// 한 성별의 연령 제한. [enabled]가 false면 그 성별은 제한 없음이다.
///
/// 경계는 **포함**이다(min/max 나이 당사자는 신청 가능). 한쪽이 null이면 그
/// 방향은 열려 있다(예: 최소 나이만 정하고 상한은 없음).
class GenderAgeLimit {
  final bool enabled;

  /// 허용되는 가장 이른 출생연도 = **나이 상한**. null이면 상한 없음.
  final int? minBirthYear;

  /// 허용되는 가장 늦은 출생연도 = **나이 하한**. null이면 하한 없음.
  final int? maxBirthYear;

  const GenderAgeLimit({
    this.enabled = false,
    this.minBirthYear,
    this.maxBirthYear,
  });

  static const GenderAgeLimit off = GenderAgeLimit();

  /// 나이(만)로 만든다 — 화면에서 고른 값을 그대로 받는 생성자.
  factory GenderAgeLimit.fromAges({required int minAge, required int maxAge}) =>
      GenderAgeLimit(
        enabled: true,
        minBirthYear: birthYearFromAge(maxAge),
        maxBirthYear: birthYearFromAge(minAge),
      );

  /// 나이 하한(만). 정하지 않았으면 null.
  int? get minAge =>
      maxBirthYear == null ? null : ageFromBirthYear(maxBirthYear!);

  /// 나이 상한(만). 정하지 않았으면 null.
  int? get maxAge =>
      minBirthYear == null ? null : ageFromBirthYear(minBirthYear!);

  /// [birthYear]가 이 범위 안인가. 제한이 꺼져 있으면 항상 true.
  ///
  /// 제한이 켜져 있는데 출생연도를 모르면 **false** — 본인확인으로 생년이
  /// 저장되지 않은 계정은 연령 조건을 만족한다고 볼 근거가 없다.
  bool allows(int? birthYear) {
    if (!enabled) return true;
    if (birthYear == null) return false;
    final min = minBirthYear;
    final max = maxBirthYear;
    if (min != null && birthYear < min) return false;
    if (max != null && birthYear > max) return false;
    return true;
  }

  /// '25~35세' / '25세 이상' / '35세 이하' / '제한 없음'.
  String get ageLabel {
    if (!enabled) return '제한 없음';
    final lo = minAge;
    final hi = maxAge;
    if (lo != null && hi != null) return '$lo~$hi세';
    if (lo != null) return '$lo세 이상';
    if (hi != null) return '$hi세 이하';
    return '제한 없음';
  }

  GenderAgeLimit copyWith({
    bool? enabled,
    int? minBirthYear,
    int? maxBirthYear,
  }) => GenderAgeLimit(
    enabled: enabled ?? this.enabled,
    minBirthYear: minBirthYear ?? this.minBirthYear,
    maxBirthYear: maxBirthYear ?? this.maxBirthYear,
  );

  @override
  bool operator ==(Object other) =>
      other is GenderAgeLimit &&
      other.enabled == enabled &&
      other.minBirthYear == minBirthYear &&
      other.maxBirthYear == maxBirthYear;

  @override
  int get hashCode => Object.hash(enabled, minBirthYear, maxBirthYear);

  @override
  String toString() =>
      'GenderAgeLimit(enabled: $enabled, min: $minBirthYear, max: $maxBirthYear)';
}

class PartyAgeRestriction {
  /// 마스터 스위치. false면 성별 값이 무엇이든 제한 없음이다 — 호스트가 연령
  /// 제한을 껐다 켰다 해도 예전 값이 되살아나지 않게 하는 유일한 기준.
  final bool enabled;

  final GenderAgeLimit male;
  final GenderAgeLimit female;

  /// 이 값이 **성별별 필드에서** 왔는가(= 신규 스키마 문서인가).
  ///
  /// 판정에 쓴다: 성별별 제한은 신청자 성별을 모르면 판정할 수 없으므로 막지만,
  /// 공통 필드만 있는 기존 파티는 예전처럼 성별 없이도 범위만으로 판정한다 —
  /// 그래야 이 변경으로 기존 파티의 동작이 달라지지 않는다.
  final bool perGender;

  const PartyAgeRestriction({
    this.enabled = false,
    this.male = GenderAgeLimit.off,
    this.female = GenderAgeLimit.off,
    this.perGender = false,
  });

  static const PartyAgeRestriction off = PartyAgeRestriction();

  // ── 필드 이름 ─────────────────────────────────────────────────────────
  static const String enabledField = 'ageRestrictionEnabled';
  static const String maleEnabledField = 'maleAgeRestrictionEnabled';
  static const String maleMinField = 'maleMinBirthYear';
  static const String maleMaxField = 'maleMaxBirthYear';
  static const String femaleEnabledField = 'femaleAgeRestrictionEnabled';
  static const String femaleMinField = 'femaleMinBirthYear';
  static const String femaleMaxField = 'femaleMaxBirthYear';

  /// 기존 파티의 남녀 공통 필드.
  static const String legacyMinField = 'minBirthYear';
  static const String legacyMaxField = 'maxBirthYear';

  /// 파티 문서(또는 임시저장 map)에서 읽는다.
  ///
  /// 성별 필드가 **하나도 없으면** 기존 파티다 — 공통 범위를 남녀 모두에게
  /// 똑같이 적용한다.
  factory PartyAgeRestriction.fromMap(Map<String, dynamic>? data) {
    if (data == null) return off;
    final enabled = data[enabledField] == true;
    final hasPerGender =
        data.containsKey(maleEnabledField) ||
        data.containsKey(femaleEnabledField);

    if (!hasPerGender) {
      final legacy = GenderAgeLimit(
        enabled: enabled,
        minBirthYear: _intOrNull(data[legacyMinField]),
        maxBirthYear: _intOrNull(data[legacyMaxField]),
      );
      return PartyAgeRestriction(
        enabled: enabled,
        male: legacy,
        female: legacy,
        perGender: false,
      );
    }

    return PartyAgeRestriction(
      enabled: enabled,
      male: GenderAgeLimit(
        enabled: data[maleEnabledField] == true,
        minBirthYear: _intOrNull(data[maleMinField]),
        maxBirthYear: _intOrNull(data[maleMaxField]),
      ),
      female: GenderAgeLimit(
        enabled: data[femaleEnabledField] == true,
        minBirthYear: _intOrNull(data[femaleMinField]),
        maxBirthYear: _intOrNull(data[femaleMaxField]),
      ),
      perGender: true,
    );
  }

  /// 실제로 걸려 있는 제한이 하나라도 있는가.
  bool get hasAnyLimit => enabled && (male.enabled || female.enabled);

  GenderAgeLimit limitFor(String? gender) {
    if (!enabled) return GenderAgeLimit.off;
    if (gender == 'male') return male;
    if (gender == 'female') return female;
    return GenderAgeLimit.off;
  }

  /// 신청 자격 — **자기 성별의 제한만** 본다.
  ///
  /// 성별을 모를 때:
  ///   · 성별별 제한이 걸린 파티([perGender])는 판정 불가 → false.
  ///   · 공통 필드만 있는 기존 파티는 예전과 똑같이 범위만으로 판정한다.
  bool allows(String? gender, int? birthYear) {
    if (!hasAnyLimit) return true;
    final known = gender == 'male' || gender == 'female';
    if (!known) {
      if (perGender) return false;
      return male.allows(birthYear);
    }
    return limitFor(gender).allows(birthYear);
  }

  /// 이 파티가 출생연도 [groupMin]~[groupMax] 구간에 **열려 있는가**.
  ///
  /// 목록·지도의 연령대(10년 단위) 필터가 쓴다. 그 필터는 "내가 신청할 수
  /// 있는가"가 아니라 "이 파티가 그 연령대를 받는가"를 묻는 것이므로,
  /// 모집하는 성별 중 **하나라도** 구간과 겹치면 통과다(제한이 없는 성별이
  /// 하나라도 있으면 모든 연령대에 열려 있다). 사용자 자기 기준 판정은
  /// `checkPartyEligibility`의 '내가 참여 가능한 파티' 필터가 한다.
  bool opensToBirthYearRange(
    int groupMin,
    int groupMax, {
    String genderLimit = 'all',
  }) {
    final eff = normalizedFor(genderLimit);
    if (!eff.hasAnyLimit) return true;
    for (final g in applicableGenders(genderLimit)) {
      final l = eff.limitFor(g);
      if (!l.enabled) return true;
      final lo = l.minBirthYear ?? -100000000;
      final hi = l.maxBirthYear ?? 100000000;
      if (lo <= groupMax && hi >= groupMin) return true;
    }
    return false;
  }

  /// 성별 모집 설정([genderLimit])에 맞춰 **모집하지 않는 성별의 제한을
  /// 지운다.**
  ///
  /// 호스트가 "여성만 모집"으로 바꾸면 남성 칸은 화면에서 사라지는데, 그때
  /// 예전에 골라 둔 남성 제한이 문서에 남아 있으면 나중에 다시 '남녀 모두'로
  /// 되돌렸을 때 아무도 손대지 않은 값이 갑자기 적용된다. 저장 직전에 여기서
  /// 한 번 정리해 그런 유령 값을 없앤다 — 정원(maleCapacity/femaleCapacity)이
  /// 같은 규칙으로 0이 되는 것과 같은 처리다.
  ///
  /// 마스터 스위치가 켜져 있어도 남은 제한이 하나도 없으면 **꺼진 것으로**
  /// 본다(빈 제한이 걸린 척하는 문서를 만들지 않는다).
  PartyAgeRestriction normalizedFor(String genderLimit) {
    if (!enabled) return off;
    final m = genderLimit == 'female' ? GenderAgeLimit.off : male;
    final f = genderLimit == 'male' ? GenderAgeLimit.off : female;
    if (!m.enabled && !f.enabled) return off;
    return PartyAgeRestriction(
      enabled: true,
      male: m.enabled ? m : GenderAgeLimit.off,
      female: f.enabled ? f : GenderAgeLimit.off,
      perGender: true,
    );
  }

  /// 이 파티가 실제로 모집하는 성별들.
  static List<String> applicableGenders(String genderLimit) =>
      switch (genderLimit) {
        'male' => const ['male'],
        'female' => const ['female'],
        _ => const ['male', 'female'],
      };

  /// 구버전 앱을 위한 **공통 필드** 값 — 모집하는 모든 성별이 제한을 가질
  /// 때만 만들고, 그 범위들의 합집합(가장 넓은 범위)을 쓴다.
  ///
  /// 한쪽 성별이 제한 없음이면 공통 범위로 표현할 방법이 없다 → null을 돌려
  /// 필드를 아예 쓰지 않는다. 그 문서를 읽는 구버전 앱은 "연령 제한은 켜져
  /// 있지만 범위 값이 없다"고 보고 아무도 막지 않는데, 실제 차단은 서버가
  /// 하므로 안전하다(구버전이 잘못 막아 정상 신청자를 잃는 쪽이 더 나쁘다).
  ({int? min, int? max})? legacyRangeFor(String genderLimit) {
    final limits = [
      for (final g in applicableGenders(genderLimit)) limitFor(g),
    ];
    if (limits.isEmpty || limits.any((l) => !l.enabled)) return null;
    int? min;
    int? max;
    for (final l in limits) {
      final v = l.minBirthYear;
      if (v == null) {
        min = null;
        break;
      }
      min = (min == null || v < min) ? v : min;
    }
    for (final l in limits) {
      final v = l.maxBirthYear;
      if (v == null) {
        max = null;
        break;
      }
      max = (max == null || v > max) ? v : max;
    }
    if (min == null && max == null) return null;
    return (min: min, max: max);
  }

  /// 파티 문서에 쓸 필드. [genderLimit]에 맞춰 정리한 뒤 만든다.
  ///
  /// 제한이 없으면 `ageRestrictionEnabled: false` **하나만** 쓴다 — 예전 값이
  /// 남아 있어도 읽는 쪽이 모두 이 스위치를 먼저 보므로 적용되지 않는다.
  Map<String, dynamic> toFields({required String genderLimit}) {
    final eff = normalizedFor(genderLimit);
    if (!eff.hasAnyLimit) return <String, dynamic>{enabledField: false};

    final out = <String, dynamic>{
      enabledField: true,
      maleEnabledField: eff.male.enabled,
      femaleEnabledField: eff.female.enabled,
    };
    if (eff.male.enabled) {
      if (eff.male.minBirthYear != null) {
        out[maleMinField] = eff.male.minBirthYear;
      }
      if (eff.male.maxBirthYear != null) {
        out[maleMaxField] = eff.male.maxBirthYear;
      }
    }
    if (eff.female.enabled) {
      if (eff.female.minBirthYear != null) {
        out[femaleMinField] = eff.female.minBirthYear;
      }
      if (eff.female.maxBirthYear != null) {
        out[femaleMaxField] = eff.female.maxBirthYear;
      }
    }
    final legacy = eff.legacyRangeFor(genderLimit);
    if (legacy != null) {
      if (legacy.min != null) out[legacyMinField] = legacy.min;
      if (legacy.max != null) out[legacyMaxField] = legacy.max;
    }
    return out;
  }

  /// 상세·요약에 쓰는 한 줄 — '남성 25~35세 · 여성 23~32세'.
  ///
  /// 남녀 제한이 완전히 같아도 합치지 않고 그대로 둘 다 보여준다("25~35세"
  /// 하나만 보이면 그게 내 성별에도 적용되는 값인지 알 수 없다). 모집하지
  /// 않는 성별은 아예 빼고, 제한이 없는 성별은 '제한 없음'으로 적는다.
  String summaryLabel({String genderLimit = 'all'}) {
    final eff = normalizedFor(genderLimit);
    if (!eff.hasAnyLimit) return '';
    final parts = <String>[
      for (final g in applicableGenders(genderLimit))
        '${g == 'male' ? '남성' : '여성'} ${eff.limitFor(g).ageLabel}',
    ];
    return parts.join(' · ');
  }

  PartyAgeRestriction copyWith({
    bool? enabled,
    GenderAgeLimit? male,
    GenderAgeLimit? female,
  }) => PartyAgeRestriction(
    enabled: enabled ?? this.enabled,
    male: male ?? this.male,
    female: female ?? this.female,
    perGender: perGender,
  );

  @override
  bool operator ==(Object other) =>
      other is PartyAgeRestriction &&
      other.enabled == enabled &&
      other.male == male &&
      other.female == female;

  @override
  int get hashCode => Object.hash(enabled, male, female);

  @override
  String toString() =>
      'PartyAgeRestriction(enabled: $enabled, male: $male, female: $female)';
}

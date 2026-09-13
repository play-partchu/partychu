// 앱 ↔ 서버 파티 등록 **파리티** 테스트.
//
// functions/fixtures/party_registration_cases.json 하나를 두 곳이 읽는다.
//
//   · functions/partyRegistration.selfcheck.js — 서버 공용 모듈이 그 값을 내는가
//   · 이 파일                                   — 앱 모델이 같은 값을 내는가
//
// 두 검증이 모두 초록일 때만 "웹으로 등록한 파티와 앱으로 등록한 파티의 문서
// 모양이 같다"고 말할 수 있다. 한쪽 규칙만 고치면 여기가 깨진다 — 그게 이
// 테스트의 존재 이유다.
//
// 픽스처를 다시 만들려면(케이스를 더했을 때 등):
//   cd functions && node partyRegistration.selfcheck.js --write
// 그리고 **반드시 이 테스트를 다시 돌려서** 앱이 같은 값을 내는지 확인한다.
//
// ── 시간대 ────────────────────────────────────────────────────────────────
//
// 앱의 일정 계산은 기기 로컬 시간(한국 사용자 = KST) 기준이고, 픽스처의 기대값도
// KST로 만들어졌다. 그래서 이 테스트는 로컬 시간대가 +9가 아니면 건너뛴다 —
// 다른 시간대에서 실패하는 것은 코드가 아니라 실행 환경의 문제라, 그걸 실패로
// 보고하면 진짜 드리프트가 묻힌다.

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/party_age_restriction.dart';
import 'package:party_app/models/party_capacity_status.dart';
import 'package:party_app/models/party_early_bird.dart';
import 'package:party_app/models/party_early_bird_schedule.dart';
import 'package:party_app/models/participant_gender_visibility.dart';
import 'package:party_app/models/party_pricing.dart';
import 'package:party_app/models/party_registration_data.dart';
import 'package:party_app/models/party_round.dart';
import 'package:party_app/models/party_round_package.dart';
import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/models/payment_policy.dart';
import 'package:party_app/utils/refund_policy.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 픽스처 읽기 / 값 정규화
// ═══════════════════════════════════════════════════════════════════════════

/// 픽스처 파일 — 이 테스트 파일 기준 상대 경로로 찾는다(작업 디렉터리가
/// party_app이든 리포지토리 루트든 같은 파일을 가리키도록).
File _fixtureFile() {
  const relative = 'fixtures/party_registration_cases.json';
  for (final base in ['../functions', 'functions', '../../functions']) {
    final f = File('$base/$relative');
    if (f.existsSync()) return f;
  }
  throw StateError(
    'party_registration_cases.json 을 찾지 못했습니다. '
    'functions 디렉터리에서 `node partyRegistration.selfcheck.js --write` 를 '
    '먼저 실행하세요.',
  );
}

/// Dart가 만든 값을 픽스처와 같은 모양으로 바꾼다.
///
/// · Timestamp/DateTime → {'__date': UTC ISO}
/// · Map/List는 재귀
/// · null은 **그대로 남긴다** — "반대쪽 방식은 명시적으로 null"이라는 규칙이
///   문서 모양의 일부다.
dynamic encode(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) {
    return {'__date': value.toDate().toUtc().toIso8601String()};
  }
  if (value is DateTime) {
    return {'__date': value.toUtc().toIso8601String()};
  }
  if (value is Map) {
    final out = <String, dynamic>{};
    value.forEach((k, v) => out['$k'] = encode(v));
    return out;
  }
  if (value is List) return value.map(encode).toList();
  if (value is Set) return value.map(encode).toList();
  return value;
}

/// 픽스처에서 읽은 기대값도 같은 모양으로 맞춘다(JSON에는 이미 __date로 들어
/// 있으므로 실질적으로는 그대로 통과한다).
dynamic normalizeExpected(dynamic value) => value;

// ── 입력 파서 ──────────────────────────────────────────────────────────────

TimeOfDay? _hm(dynamic raw) {
  if (raw is! String) return null;
  final parts = raw.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return TimeOfDay(hour: h, minute: m);
}

DateTime? _isoDate(dynamic raw) {
  if (raw is! String) return null;
  final parts = raw.split('-');
  if (parts.length != 3) return null;
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

int? _int(dynamic raw) => raw is num ? raw.toInt() : null;

/// 픽스처의 연령 입력 → [PartyAgeRestriction].
///
/// 서버 partyAgeRestriction.js의 normalizeAgeInput과 **같은 규칙**이다 —
/// 성별 블록이 하나도 없으면 옛 공통 스키마로 보고 남녀 양쪽에 같은 값을
/// 넣는다. 여기가 갈리면 앱과 웹이 같은 입력으로 다른 파티를 만든다.
PartyAgeRestriction _ageRestriction(dynamic raw) {
  if (raw is! Map) return PartyAgeRestriction.off;
  final src = Map<String, dynamic>.from(raw);
  final enabled = src['enabled'] == true;
  final hasPerGender = src['male'] is Map || src['female'] is Map;

  if (!hasPerGender) {
    final legacy = GenderAgeLimit(
      enabled: enabled,
      minBirthYear: _int(src['minBirthYear']),
      maxBirthYear: _int(src['maxBirthYear']),
    );
    return PartyAgeRestriction(enabled: enabled, male: legacy, female: legacy);
  }

  GenderAgeLimit read(String gender) {
    final g = src[gender] is Map
        ? Map<String, dynamic>.from(src[gender] as Map)
        : const <String, dynamic>{};
    return GenderAgeLimit(
      enabled: g['enabled'] == true,
      minBirthYear: _int(g['minBirthYear']),
      maxBirthYear: _int(g['maxBirthYear']),
    );
  }

  return PartyAgeRestriction(
    enabled: enabled,
    male: read('male'),
    female: read('female'),
    perGender: true,
  );
}

/// 픽스처의 모집 규칙 입력 → Dart 규칙. 저장 포맷과 같은 키를 쓰므로
/// PartyRecruitDeadlineRule.fromMap을 그대로 태운다.
PartyRecruitDeadlineRule _recruitRule(dynamic raw) {
  if (raw is! Map) return const PartyRecruitDeadlineRule();
  return PartyRecruitDeadlineRule.fromMap(Map<String, dynamic>.from(raw));
}

/// 픽스처의 얼리버드 규칙 입력 → Dart 규칙.
PartyEarlyBirdDeadlineRule _earlyBirdRule(dynamic raw) {
  if (raw is! Map) return const PartyEarlyBirdDeadlineRule();
  final m = Map<String, dynamic>.from(raw);
  return PartyEarlyBirdDeadlineRule(
    mode: EarlyBirdDeadlineMode.fromKey(m['mode'] as String?),
    days: _int(m['days']) ?? 3,
    hours: _int(m['hours']) ?? 24,
    time: _hm(m['time']) ?? const TimeOfDay(hour: 23, minute: 59),
  );
}

/// 픽스처의 얼리버드 입력 → Dart 모델.
PartyEarlyBird _earlyBird(dynamic raw) {
  if (raw is! Map) return const PartyEarlyBird.off();
  final m = Map<String, dynamic>.from(raw);
  final endRaw = m['endAt'];
  DateTime? endDate;
  TimeOfDay? endTime;
  if (endRaw is Map) {
    endDate = _isoDate(endRaw['date']);
    endTime = _hm(endRaw['time']);
  }
  return PartyEarlyBird(
    enabled: m['enabled'] == true,
    percent: _int(m['percent']),
    endType: PartyEarlyBirdEndType.fromKey(m['endType'] as String?),
    endDate: endDate,
    endTime: endTime,
    beforeStartRule: _earlyBirdRule(m['beforeStartRule']),
  );
}

/// 픽스처의 참가비 입력 → Dart 모델. 서버 normalizePricing과 같은 갈래다.
PartyPricing _pricing(dynamic raw) {
  final m = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  final type = m['type'] as String?;
  if (type == 'free') return const PartyPricing.free();
  if (type == 'same') return PartyPricing.same(_int(m['price']) ?? 0);
  return PartyPricing.gendered(
    male: _int(m['malePrice']) ?? _int(m['male']) ?? 0,
    female: _int(m['femalePrice']) ?? _int(m['female']) ?? 0,
  );
}

/// 픽스처의 차수 입력 → Dart 모델.
PartyRound _round(dynamic raw, int index) {
  final m = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  return PartyRound(
    id: (m['id'] as String?)?.trim().isNotEmpty == true
        ? m['id'] as String
        : 'round_${index + 2}',
    label: (m['label'] as String?)?.trim() ?? '',
    startTime: _hm(m['startTime']) ?? const TimeOfDay(hour: 21, minute: 0),
    endTime: _hm(m['endTime']),
    openRule: m['openRule'] is Map
        ? _recruitRule(m['openRule'])
        : PartyRecruitDeadlineRule.noDeadline,
    closeRule: m['closeRule'] is Map
        ? _recruitRule(m['closeRule'])
        : const PartyRecruitDeadlineRule(),
    minCapacity: _int(m['minCapacity']) ?? 0,
    maxCapacity: _int(m['maxCapacity']) ?? 0,
    maleCapacity: _int(m['maleCapacity']) ?? 0,
    femaleCapacity: _int(m['femaleCapacity']) ?? 0,
    maleFee: _int(m['maleFee']) ?? 0,
    femaleFee: _int(m['femaleFee']) ?? 0,
    earlyBird: _earlyBird(m['earlyBird']),
  );
}

/// 픽스처의 정기 일정 입력 → Dart 모델.
PartyRecurringSchedule _recurring(dynamic raw) {
  final m = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  final weeklyRaw = m['weekly'] is Map
      ? Map<String, dynamic>.from(m['weekly'] as Map)
      : <String, dynamic>{};
  final weekly = <String, PartyWeeklySlot>{};
  for (final key in kPartyWeekdayKeys) {
    final slot = weeklyRaw[key];
    if (slot is! Map) {
      weekly[key] = const PartyWeeklySlot.disabled();
      continue;
    }
    final s = Map<String, dynamic>.from(slot);
    final start = _hm(s['startTime']);
    final end = _hm(s['endTime']);
    weekly[key] = PartyWeeklySlot(
      // 시각이 덜 채워진 칸은 켜진 것으로 볼 수 없다(서버와 같은 규칙).
      enabled: s['enabled'] == true && start != null && end != null,
      startTime: start ?? const TimeOfDay(hour: 19, minute: 0),
      endTime: end ?? const TimeOfDay(hour: 22, minute: 0),
    );
  }
  return PartyRecurringSchedule(
    startDate: _isoDate(m['startDate']) ?? DateTime(2000),
    endDate: _isoDate(m['endDate']),
    weekly: weekly,
    openRule: m['openRule'] is Map
        ? _recruitRule(m['openRule'])
        : PartyRecruitDeadlineRule.noDeadline,
    deadlineRule: m['deadlineRule'] is Map
        ? _recruitRule(m['deadlineRule'])
        : const PartyRecruitDeadlineRule(),
  );
}

// ═══════════════════════════════════════════════════════════════════════════

void main() {
  final offset = DateTime.now().timeZoneOffset;
  final isKst = offset == const Duration(hours: 9);

  final fixture =
      jsonDecode(_fixtureFile().readAsStringSync()) as Map<String, dynamic>;
  final now = DateTime.parse(fixture['now'] as String).toLocal();

  List<Map<String, dynamic>> cases(String section) => (fixture[section] as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  /// 케이스 하나를 그룹으로 등록한다. 이름을 그대로 테스트 이름에 쓰므로
  /// 실패했을 때 픽스처의 어느 줄인지 바로 찾을 수 있다.
  ///
  /// **비교에서 빼는 필드는 없다.** 예전에는 모집 시작 규칙만 예외로 뒀는데,
  /// 그건 앱 안의 두 등록 화면이 서로 다른 값을 저장하던 상태를 덮어두는
  /// 장치였다. 그 차이를 앱·서버 양쪽에서 고친 뒤 예외를 없앴다.
  /// 예외를 다시 만들고 싶어지면 그전에 "앱과 서버가 이 필드에서 정말 달라야
  /// 하는가"를 먼저 답해야 한다 — 대개는 고쳐야 할 버그다.
  void parity(String section, dynamic Function(Map<String, dynamic> c) actual) {
    group(section, () {
      for (final c in cases(section)) {
        test(c['name'] as String, () {
          expect(
            encode(actual(c)),
            normalizeExpected(c['expected']),
            reason:
                '앱과 서버의 저장 결과가 갈라졌습니다. 규칙을 한쪽만 고치지 않았는지 '
                '확인하고, 의도한 변경이면 functions에서 '
                '`node partyRegistration.selfcheck.js --write` 로 픽스처를 다시 '
                '만드세요.',
          );
        });
      }
    }, skip: isKst ? false : '로컬 시간대가 KST(+9)가 아니라 건너뜁니다 (현재 $offset).');
  }

  // ── 참가비 ───────────────────────────────────────────────────────────────
  parity('pricing', (c) => _pricing(c['input']).toMap());

  // ── 모집 시작/마감 규칙 ──────────────────────────────────────────────────
  parity('recruitRule', (c) => _recruitRule(c['input']).toMap());

  // ── 얼리버드 ─────────────────────────────────────────────────────────────
  parity(
    'earlyBird',
    (c) =>
        _earlyBird(c['input']).toMapFor(isRecurring: c['isRecurring'] == true),
  );

  // ── 일회성 일정 ──────────────────────────────────────────────────────────
  parity('singleSchedule', (c) {
    final slotRaw = Map<String, dynamic>.from(c['slot'] as Map);
    final date = _isoDate(slotRaw['date'])!;
    final startTime = _hm(slotRaw['startTime'])!;
    final endTime = _hm(slotRaw['endTime']);
    final deadlineRule = _recruitRule(c['deadlineRule']);
    final openRule = _recruitRule(c['openRule']);

    final bare = PartySingleSchedule(
      date: date,
      startTime: startTime,
      endTime: endTime,
    );
    return PartySchedule.buildSingleFields(
      PartySingleSchedule(
        date: date,
        startTime: startTime,
        endTime: endTime,
        registrationDeadline: deadlineRule.resolve(
          bare.start,
          occurrenceEnd: bare.end,
        ),
        registrationOpen: openRule.resolve(bare.start, occurrenceEnd: bare.end),
      ),
      deadlineRule: deadlineRule,
      openRule: openRule,
    );
  });

  // ── 정기 일정 ────────────────────────────────────────────────────────────
  parity(
    'recurringSchedule',
    (c) => PartySchedule.buildRecurringFields(_recurring(c['input']), now: now),
  );

  // ── 차수 ─────────────────────────────────────────────────────────────────
  parity('round', (c) {
    final roundNumber = c['roundNumber'] as int;
    return _round(c['input'], roundNumber - 2).toMap(
      roundNumber: roundNumber,
      partyDate: _isoDate(c['isoDate'])!,
      perRound: c['perRound'] == true,
    );
  });

  // ── 차수 패키지 ──────────────────────────────────────────────────────────
  parity('roundPackage', (c) {
    final m = Map<String, dynamic>.from(c['input'] as Map);
    final pkg = PartyRoundPackage(
      id: m['id'] as String? ?? 'pkg_1',
      name: (m['name'] as String?)?.trim() ?? '',
      roundNumbers:
          (m['roundNumbers'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [],
      roundIds:
          (m['roundIds'] as List?)?.whereType<String>().toList() ?? const [],
      maleFee: _int(m['maleFee']) ?? 0,
      femaleFee: _int(m['femaleFee']) ?? 0,
      earlyBirdEnabled: m['earlyBirdEnabled'] == true,
      earlyBirdMaleFee: _int(m['earlyBirdMaleFee']) ?? 0,
      earlyBirdFemaleFee: _int(m['earlyBirdFemaleFee']) ?? 0,
      earlyBirdRule: _earlyBirdRule(m['earlyBirdDeadlineRule']),
    );
    return pkg.toMap(
      firstRoundStart: DateTime.parse(c['firstRoundStart'] as String).toLocal(),
    );
  });

  // ── 등록 공통 필드(PartyRegistrationData) ────────────────────────────────
  //
  // 앱과 서버가 맞대볼 수 있는 **가장 넓은 면**이다. 문서 전체 조립(슬롯
  // 팬아웃·차수 합계)은 앱 쪽 대응 코드가 등록 화면의 로컬 클로저라 여기서
  // 부를 수 없다 — 그 층은 서버 셀프체크만 덮는다.
  parity('registrationData', (c) {
    final m = Map<String, dynamic>.from(c['input'] as Map);
    final scheduleRaw = Map<String, dynamic>.from(m['schedule'] as Map);
    final isRecurring = scheduleRaw['type'] == 'recurring';
    final capRaw = Map<String, dynamic>.from(m['capacity'] as Map);
    final taxRaw = Map<String, dynamic>.from(m['taxonomy'] as Map);

    final genderLimit = capRaw['genderLimit'] as String? ?? 'all';
    final genderCapacityMode =
        capRaw['genderCapacityMode'] as String? ?? 'unlimited';
    // 서버 normalizeCapacity와 같은 규칙 — 통합 정원이면 남/여는 0이고,
    // 남녀별 정원이면 최대는 합계다.
    final int maleCapacity;
    final int femaleCapacity;
    final int maxCapacity;
    if (genderCapacityMode == 'unlimited') {
      maleCapacity = 0;
      femaleCapacity = 0;
      maxCapacity = _int(capRaw['maxCapacity']) ?? 0;
    } else {
      maleCapacity = (genderLimit == 'all' || genderLimit == 'male')
          ? (_int(capRaw['maleCapacity']) ?? 0)
          : 0;
      femaleCapacity = (genderLimit == 'all' || genderLimit == 'female')
          ? (_int(capRaw['femaleCapacity']) ?? 0)
          : 0;
      maxCapacity = maleCapacity + femaleCapacity;
    }

    PartySingleSchedule? single;
    PartyRecruitDeadlineRule? deadlineRule;
    PartyRecruitDeadlineRule? openRule;
    PartyRecurringSchedule? recurring;
    if (isRecurring) {
      recurring = _recurring(scheduleRaw['recurring']);
    } else {
      final slots = (scheduleRaw['slots'] as List?) ?? const [];
      if (slots.isNotEmpty) {
        final slot = Map<String, dynamic>.from(slots.first as Map);
        final date = _isoDate(slot['date'])!;
        final startTime = _hm(slot['startTime'])!;
        final endTime = _hm(slot['endTime']);
        deadlineRule = scheduleRaw['deadlineRule'] is Map
            ? _recruitRule(scheduleRaw['deadlineRule'])
            : PartyRecruitDeadlineRule.noDeadline;
        openRule = scheduleRaw['openRule'] is Map
            ? _recruitRule(scheduleRaw['openRule'])
            : PartyRecruitDeadlineRule.noDeadline;
        final bare = PartySingleSchedule(
          date: date,
          startTime: startTime,
          endTime: endTime,
        );
        single = PartySingleSchedule(
          date: date,
          startTime: startTime,
          endTime: endTime,
          registrationDeadline: deadlineRule.resolve(
            bare.start,
            occurrenceEnd: bare.end,
          ),
          registrationOpen: openRule.resolve(
            bare.start,
            occurrenceEnd: bare.end,
          ),
        );
      }
    }

    final minCapacity = _int(capRaw['minCapacity']) ?? 0;

    return PartyRegistrationData(
      scheduleType: isRecurring
          ? PartyScheduleType.recurring
          : PartyScheduleType.single,
      recurringSchedule: recurring,
      singleSchedule: single,
      deadlineRule: deadlineRule,
      openRule: openRule,
      genderLimit: genderLimit,
      genderCapacityMode: genderCapacityMode,
      genderMode: capRaw['genderMode'] as String? ?? '',
      maleCapacity: maleCapacity,
      femaleCapacity: femaleCapacity,
      minCapacity: minCapacity,
      maxCapacity: maxCapacity,
      minCapacityPolicy: (capRaw['minCapacityPolicy'] == 'autoCancel')
          ? PartyMinCapacityPolicy.autoCancel
          : PartyMinCapacityPolicy.proceed,
      // 참가자 성비 공개 — 서버 normalizeCapacity와 같은 규칙: **명시적으로
      // false일 때만** 감추고, 값을 안 보낸 입력은 공개다. 여기서 기본값에
      // 기대지 않고 픽스처 값을 그대로 넘겨야, 끈 케이스가 실제로 검사된다.
      revealParticipantGenderRatio:
          capRaw[ParticipantGenderVisibility.field] != false,
      pricing: _pricing(m['pricing']),
      earlyBird: _earlyBird(m['earlyBird']),
      refundTiers: ((m['refundTiers'] as List?) ?? const [])
          .map((e) => RefundTier.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      paymentPolicy: PaymentPolicy.fromMap(
        m['paymentPolicy'] is Map
            ? Map<String, dynamic>.from(m['paymentPolicy'] as Map)
            : null,
      ),
      ageRestriction: _ageRestriction(m['age']),
      partyTypes: ((taxRaw['partyTypes'] as List?) ?? const [])
          .cast<String>()
          .toSet(),
      vibes: ((taxRaw['vibes'] as List?) ?? const []).cast<String>().toSet(),
      tags: ((taxRaw['tags'] as List?) ?? const []).cast<String>().toList(),
      description: m['description'] as String? ?? '',
    ).toFirestore();
  });

  test('픽스처가 비어 있지 않다', () {
    for (final section in const [
      'pricing',
      'recruitRule',
      'earlyBird',
      'singleSchedule',
      'recurringSchedule',
      'round',
      'roundPackage',
      'registrationData',
    ]) {
      expect(
        cases(section),
        isNotEmpty,
        reason: '$section 케이스가 없습니다 — 픽스처가 잘못 만들어졌습니다.',
      );
    }
  });
}

// 성별별 연령 제한 — 앱 쪽 규칙 전부.
//
// 서버 쪽 같은 규칙은 functions/partyAgeRestriction.selfcheck.js가 본다.
// 두 파일이 같은 시나리오를 다루는 것은 의도적이다 — 한쪽만 고치면
// "화면에는 신청 가능인데 서버가 거절하는" 파티가 생긴다.
//
// 나이 ↔ 출생연도 변환은 `DateTime.now().year`를 쓰므로(연 단위 근사),
// 이 파일은 나이를 그대로 쓰고 `birthYearFromAge`로 변환한다 — 해가 바뀌어도
// 기대값이 흔들리지 않는다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/party_age_restriction.dart';
import 'package:party_app/models/party_pricing.dart';
import 'package:party_app/models/party_registration_data.dart';
import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/utils/age_range_utils.dart';
import 'package:party_app/utils/party_eligibility.dart';
import 'package:party_app/utils/refund_policy.dart';

/// 남성 25~35세.
final _male = GenderAgeLimit.fromAges(minAge: 25, maxAge: 35);

/// 여성 23~32세.
final _female = GenderAgeLimit.fromAges(minAge: 23, maxAge: 32);

int _birth(int age) => birthYearFromAge(age);

/// 파티 문서 한 벌 — 연령 필드만 시나리오마다 다르다.
Map<String, dynamic> _party(
  PartyAgeRestriction age, {
  String genderLimit = 'all',
}) => <String, dynamic>{
  'genderLimit': genderLimit,
  'genderCapacityMode': 'unlimited',
  'maxCapacity': 30,
  'currentParticipants': 0,
  ...age.toFields(genderLimit: genderLimit),
};

/// 등록 화면이 실제로 저장하는 경로(PartyRegistrationData)를 그대로 태운다.
Map<String, dynamic> _registered(
  PartyAgeRestriction age, {
  String genderLimit = 'all',
}) => PartyRegistrationData(
  scheduleType: PartyScheduleType.single,
  singleSchedule: PartySingleSchedule(
    date: DateTime(2099, 10, 2),
    startTime: const TimeOfDay(hour: 19, minute: 0),
  ),
  genderLimit: genderLimit,
  maxCapacity: 20,
  pricing: const PartyPricing.free(),
  refundTiers: [RefundTier(daysBefore: 1, refundPercent: 100)],
  ageRestriction: age,
).toFirestore();

void main() {
  group('저장 필드 — 성별별 정본 + 구버전용 공통 필드', () {
    test('남녀 동일 제한 — 성별 필드와 공통 필드가 같은 값으로 남는다', () {
      final f = PartyAgeRestriction(
        enabled: true,
        male: _male,
        female: _male,
        perGender: true,
      ).toFields(genderLimit: 'all');

      expect(f['ageRestrictionEnabled'], isTrue);
      expect(f['maleAgeRestrictionEnabled'], isTrue);
      expect(f['femaleAgeRestrictionEnabled'], isTrue);
      expect(f['maleMinBirthYear'], _birth(35));
      expect(f['maleMaxBirthYear'], _birth(25));
      expect(f['femaleMinBirthYear'], _birth(35));
      expect(f['femaleMaxBirthYear'], _birth(25));
      expect(f['minBirthYear'], _birth(35));
      expect(f['maxBirthYear'], _birth(25));
    });

    test('남녀 서로 다른 제한 — 공통 필드는 합집합(가장 넓은 범위)', () {
      final f = PartyAgeRestriction(
        enabled: true,
        male: _male,
        female: _female,
        perGender: true,
      ).toFields(genderLimit: 'all');

      expect(f['maleMinBirthYear'], _birth(35));
      expect(f['maleMaxBirthYear'], _birth(25));
      expect(f['femaleMinBirthYear'], _birth(32));
      expect(f['femaleMaxBirthYear'], _birth(23));
      // 23~35세를 아우르는 범위 하나.
      expect(f['minBirthYear'], _birth(35));
      expect(f['maxBirthYear'], _birth(23));
    });

    test('남성만 제한 — 여성 필드도 공통 필드도 만들지 않는다', () {
      final f = PartyAgeRestriction(
        enabled: true,
        male: _male,
        perGender: true,
      ).toFields(genderLimit: 'all');

      expect(f['maleAgeRestrictionEnabled'], isTrue);
      expect(f['femaleAgeRestrictionEnabled'], isFalse);
      expect(f.containsKey('femaleMinBirthYear'), isFalse);
      // 한쪽이 제한 없음이면 공통 범위로 표현할 수 없다.
      expect(f.containsKey('minBirthYear'), isFalse);
      expect(f.containsKey('maxBirthYear'), isFalse);
    });

    test('여성만 제한 — 남성 필드도 공통 필드도 만들지 않는다', () {
      final f = PartyAgeRestriction(
        enabled: true,
        female: _female,
        perGender: true,
      ).toFields(genderLimit: 'all');

      expect(f['maleAgeRestrictionEnabled'], isFalse);
      expect(f['femaleAgeRestrictionEnabled'], isTrue);
      expect(f.containsKey('maleMinBirthYear'), isFalse);
      expect(f.containsKey('minBirthYear'), isFalse);
    });

    test('마스터 스위치만 켜고 성별 제한이 없으면 꺼진 것으로 저장된다', () {
      final f = const PartyAgeRestriction(
        enabled: true,
        perGender: true,
      ).toFields(genderLimit: 'all');
      expect(f, {'ageRestrictionEnabled': false});
    });

    test('마스터 스위치를 끄면 성별 값이 남아 있어도 저장하지 않는다', () {
      final f = PartyAgeRestriction(
        enabled: false,
        male: _male,
        female: _female,
        perGender: true,
      ).toFields(genderLimit: 'all');
      expect(f, {'ageRestrictionEnabled': false});
    });
  });

  group('성별 모집 설정과의 연동 — 숨겨진 성별의 옛 값은 적용되지 않는다', () {
    test('여성만 모집 — 남성 제한이 지워진다', () {
      final f = PartyAgeRestriction(
        enabled: true,
        male: _male,
        female: _female,
        perGender: true,
      ).toFields(genderLimit: 'female');

      expect(f['maleAgeRestrictionEnabled'], isFalse);
      expect(f.containsKey('maleMinBirthYear'), isFalse);
      // 모집하는 성별이 여성뿐이라 공통 범위는 여성 범위 그대로다.
      expect(f['minBirthYear'], _birth(32));
      expect(f['maxBirthYear'], _birth(23));
    });

    test('남성만 모집 — 여성 제한이 지워진다', () {
      final f = PartyAgeRestriction(
        enabled: true,
        male: _male,
        female: _female,
        perGender: true,
      ).toFields(genderLimit: 'male');

      expect(f['femaleAgeRestrictionEnabled'], isFalse);
      expect(f.containsKey('femaleMinBirthYear'), isFalse);
      expect(f['minBirthYear'], _birth(35));
      expect(f['maxBirthYear'], _birth(25));
    });

    test('여성만 모집인데 여성은 제한 없음 — 남성 제한이 되살아나지 않는다', () {
      final f = PartyAgeRestriction(
        enabled: true,
        male: _male,
        perGender: true,
      ).toFields(genderLimit: 'female');
      expect(f, {'ageRestrictionEnabled': false});
    });

    test('성별 모집을 바꾼 뒤 저장한 문서로는 지워진 성별이 통과한다', () {
      // 화면 상태에는 남성 제한이 남아 있지만 여성만 모집으로 저장했다.
      final party = _party(
        PartyAgeRestriction(
          enabled: true,
          male: _male,
          female: _female,
          perGender: true,
        ),
        genderLimit: 'female',
      );
      // (성별 제한 자체는 genderLimit이 막는다 — 여기서는 연령 판정만 본다.)
      final age = PartyAgeRestriction.fromMap(party);
      expect(age.allows('male', _birth(70)), isTrue);
      expect(age.allows('female', _birth(70)), isFalse);
    });
  });

  group('신청 자격 — 자기 성별의 제한만 본다', () {
    late Map<String, dynamic> party;

    setUp(() {
      party = _party(
        PartyAgeRestriction(
          enabled: true,
          male: _male, // 25~35
          female: _female, // 23~32
          perGender: true,
        ),
      );
    });

    test('24세 남성 → 신청 불가', () {
      expect(
        checkPartyEligibility(party, 'male', _birth(24)),
        PartyEligibility.ageLimited,
      );
    });

    test('24세 여성 → 신청 가능', () {
      expect(
        checkPartyEligibility(party, 'female', _birth(24)),
        PartyEligibility.eligible,
      );
    });

    test('36세 남성 → 신청 불가', () {
      expect(
        checkPartyEligibility(party, 'male', _birth(36)),
        PartyEligibility.ageLimited,
      );
    });

    test('33세 여성 → 신청 불가', () {
      expect(
        checkPartyEligibility(party, 'female', _birth(33)),
        PartyEligibility.ageLimited,
      );
    });

    test('경계 나이(min/max)는 포함이다', () {
      for (final age in [25, 30, 35]) {
        expect(
          checkPartyEligibility(party, 'male', _birth(age)),
          PartyEligibility.eligible,
          reason: '$age세 남성',
        );
      }
      for (final age in [23, 28, 32]) {
        expect(
          checkPartyEligibility(party, 'female', _birth(age)),
          PartyEligibility.eligible,
          reason: '$age세 여성',
        );
      }
    });

    test('성별을 모르면(로그인 전 등) 판정 불가로 막는다', () {
      expect(
        checkPartyEligibility(party, null, _birth(30)),
        PartyEligibility.ageLimited,
      );
    });

    test('생년을 모르면 막는다', () {
      expect(
        checkPartyEligibility(party, 'male', null),
        PartyEligibility.ageLimited,
      );
    });
  });

  group('한쪽만 제한한 파티', () {
    test('남성만 제한 — 여성은 나이와 무관하게 신청 가능', () {
      final party = _party(
        PartyAgeRestriction(enabled: true, male: _male, perGender: true),
      );
      expect(
        checkPartyEligibility(party, 'female', _birth(55)),
        PartyEligibility.eligible,
      );
      expect(
        checkPartyEligibility(party, 'male', _birth(55)),
        PartyEligibility.ageLimited,
      );
      expect(
        checkPartyEligibility(party, 'male', _birth(30)),
        PartyEligibility.eligible,
      );
    });

    test('여성만 제한 — 남성은 나이와 무관하게 신청 가능', () {
      final party = _party(
        PartyAgeRestriction(enabled: true, female: _female, perGender: true),
      );
      expect(
        checkPartyEligibility(party, 'male', _birth(55)),
        PartyEligibility.eligible,
      );
      expect(
        checkPartyEligibility(party, 'female', _birth(55)),
        PartyEligibility.ageLimited,
      );
    });

    test('제한 없는 성별은 생년을 몰라도 통과한다', () {
      final party = _party(
        PartyAgeRestriction(enabled: true, male: _male, perGender: true),
      );
      expect(
        checkPartyEligibility(party, 'female', null),
        PartyEligibility.eligible,
      );
    });
  });

  group('기존 파티 하위호환 — 공통 연령 필드', () {
    final legacy = <String, dynamic>{
      'genderLimit': 'all',
      'ageRestrictionEnabled': true,
      'minBirthYear': 1990,
      'maxBirthYear': 2000,
    };

    test('공통 범위가 남녀 모두에게 그대로 적용된다', () {
      final age = PartyAgeRestriction.fromMap(legacy);
      expect(age.perGender, isFalse);
      expect(age.male.minBirthYear, 1990);
      expect(age.female.maxBirthYear, 2000);
      expect(age.allows('male', 1995), isTrue);
      expect(age.allows('female', 1995), isTrue);
      expect(age.allows('male', 2002), isFalse);
      expect(age.allows('female', 1989), isFalse);
    });

    test('기존 파티는 성별을 몰라도 예전처럼 범위만으로 판정한다', () {
      // 이 변경으로 기존 파티의 동작이 달라지면 안 된다.
      expect(
        checkPartyEligibility(legacy, null, 1995),
        PartyEligibility.eligible,
      );
      expect(
        checkPartyEligibility(legacy, null, 2002),
        PartyEligibility.ageLimited,
      );
    });

    test('연령 제한이 없던 기존 파티는 그대로 열려 있다', () {
      final open = <String, dynamic>{'ageRestrictionEnabled': false};
      expect(
        checkPartyEligibility(open, null, null),
        PartyEligibility.eligible,
      );
    });
  });

  group('등록 → 저장 → 수정 → 복원', () {
    test('등록 화면 경로(PartyRegistrationData)도 성별별 필드를 남긴다', () {
      final doc = _registered(
        PartyAgeRestriction(
          enabled: true,
          male: _male,
          female: _female,
          perGender: true,
        ),
      );
      expect(doc['maleMinBirthYear'], _birth(35));
      expect(doc['femaleMaxBirthYear'], _birth(23));
      expect(doc['minBirthYear'], _birth(35));
      expect(doc['maxBirthYear'], _birth(23));
    });

    test('저장한 문서를 다시 읽으면 같은 값이 돌아온다', () {
      final original = PartyAgeRestriction(
        enabled: true,
        male: _male,
        female: _female,
        perGender: true,
      );
      final doc = _registered(original);
      final restored = PartyAgeRestriction.fromMap(doc);

      expect(restored.perGender, isTrue);
      expect(restored.male, _male);
      expect(restored.female, _female);
      // 수정 화면에서 그대로 다시 저장해도 문서가 달라지지 않는다.
      expect(
        restored.toFields(genderLimit: 'all'),
        original.toFields(genderLimit: 'all'),
      );
    });

    test('한쪽만 제한한 파티도 왕복에서 모양이 유지된다', () {
      final original = PartyAgeRestriction(
        enabled: true,
        male: _male,
        perGender: true,
      );
      final restored = PartyAgeRestriction.fromMap(_registered(original));
      expect(restored.male.enabled, isTrue);
      expect(restored.female.enabled, isFalse);
      expect(
        restored.toFields(genderLimit: 'all'),
        original.toFields(genderLimit: 'all'),
      );
    });

    test('기존 파티를 수정하면 성별별 정본으로 승격되고 값은 그대로다', () {
      final restored = PartyAgeRestriction.fromMap(<String, dynamic>{
        'ageRestrictionEnabled': true,
        'minBirthYear': 1990,
        'maxBirthYear': 2000,
      });
      final resaved = restored.toFields(genderLimit: 'all');
      expect(resaved['maleMinBirthYear'], 1990);
      expect(resaved['femaleMaxBirthYear'], 2000);
      // 구버전 앱이 읽는 공통 필드도 같은 값으로 남는다.
      expect(resaved['minBirthYear'], 1990);
      expect(resaved['maxBirthYear'], 2000);
      // 값이 살아 있으므로 수정 후에도 신청 판정이 같다.
      expect(restored.allows('male', 1995), isTrue);
      expect(restored.allows('male', 2002), isFalse);
    });
  });

  group('상세 표시 — 성별을 구분해서 보여준다', () {
    test('남녀 다른 제한', () {
      final label = PartyAgeRestriction(
        enabled: true,
        male: _male,
        female: _female,
        perGender: true,
      ).summaryLabel();
      expect(label, '남성 25~35세 · 여성 23~32세');
    });

    test('남녀 제한이 같아도 나눠서 보여준다', () {
      final label = PartyAgeRestriction(
        enabled: true,
        male: _male,
        female: _male,
        perGender: true,
      ).summaryLabel();
      expect(label, '남성 25~35세 · 여성 25~35세');
    });

    test('한쪽만 제한이면 다른 성별은 제한 없음으로', () {
      final label = PartyAgeRestriction(
        enabled: true,
        male: _male,
        perGender: true,
      ).summaryLabel();
      expect(label, '남성 25~35세 · 여성 제한 없음');
    });

    test('여성만 모집하는 파티는 여성 줄만 보여준다', () {
      final label = PartyAgeRestriction(
        enabled: true,
        male: _male,
        female: _female,
        perGender: true,
      ).summaryLabel(genderLimit: 'female');
      expect(label, '여성 23~32세');
    });

    test('기존 파티도 남성/여성으로 나눠 보여준다', () {
      final label = PartyAgeRestriction.fromMap(<String, dynamic>{
        'ageRestrictionEnabled': true,
        'minBirthYear': _birth(35),
        'maxBirthYear': _birth(25),
      }).summaryLabel();
      expect(label, '남성 25~35세 · 여성 25~35세');
    });

    test('제한이 없으면 빈 문자열 — 상세에서 줄 자체가 빠진다', () {
      expect(PartyAgeRestriction.off.summaryLabel(), '');
    });
  });

  group('연령대 필터 — 모집하는 성별 중 하나라도 겹치면 열려 있다', () {
    final age = PartyAgeRestriction(
      enabled: true,
      male: _male, // 25~35
      female: _female, // 23~32
      perGender: true,
    );

    test('20대는 남녀 어느 쪽과도 겹친다', () {
      expect(age.opensToBirthYearRange(_birth(29), _birth(20)), isTrue);
    });

    test('50대는 어느 쪽과도 겹치지 않는다', () {
      expect(age.opensToBirthYearRange(_birth(59), _birth(50)), isFalse);
    });

    test('남성만 제한이면 여성이 제한 없어 모든 연령대에 열려 있다', () {
      final maleOnly = PartyAgeRestriction(
        enabled: true,
        male: _male,
        perGender: true,
      );
      expect(maleOnly.opensToBirthYearRange(_birth(59), _birth(50)), isTrue);
    });

    test('남성만 모집 파티는 남성 범위만 본다', () {
      expect(
        age.opensToBirthYearRange(_birth(24), _birth(23), genderLimit: 'male'),
        isFalse,
      );
      expect(
        age.opensToBirthYearRange(
          _birth(24),
          _birth(23),
          genderLimit: 'female',
        ),
        isTrue,
      );
    });

    test('연령 제한이 없으면 모든 연령대에 열려 있다', () {
      expect(
        PartyAgeRestriction.off.opensToBirthYearRange(_birth(59), _birth(50)),
        isTrue,
      );
    });
  });

  group('등록 입력 검증', () {
    PartyRegistrationData data(
      PartyAgeRestriction age, {
      String genderLimit = 'all',
    }) => PartyRegistrationData(
      scheduleType: PartyScheduleType.single,
      singleSchedule: PartySingleSchedule(
        date: DateTime(2099, 10, 2),
        startTime: const TimeOfDay(hour: 19, minute: 0),
      ),
      genderLimit: genderLimit,
      maxCapacity: 20,
      pricing: const PartyPricing.free(),
      refundTiers: [RefundTier(daysBefore: 1, refundPercent: 100)],
      ageRestriction: age,
    );

    test('뒤집힌 범위는 거절된다', () {
      final flipped = PartyAgeRestriction(
        enabled: true,
        male: GenderAgeLimit(
          enabled: true,
          minBirthYear: _birth(25),
          maxBirthYear: _birth(35),
        ),
        perGender: true,
      );
      expect(data(flipped).validate(), contains('남성'));
    });

    test('모집하지 않는 성별의 뒤집힌 범위는 등록을 막지 않는다', () {
      final flippedMale = PartyAgeRestriction(
        enabled: true,
        male: GenderAgeLimit(
          enabled: true,
          minBirthYear: _birth(25),
          maxBirthYear: _birth(35),
        ),
        female: _female,
        perGender: true,
      );
      expect(data(flippedMale, genderLimit: 'female').validate(), isNull);
    });

    test('정상 범위는 통과한다', () {
      final ok = PartyAgeRestriction(
        enabled: true,
        male: _male,
        female: _female,
        perGender: true,
      );
      expect(data(ok).validate(), isNull);
    });
  });
}

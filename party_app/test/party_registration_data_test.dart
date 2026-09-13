import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/models/party_early_bird.dart';
import 'package:party_app/models/party_pricing.dart';
import 'package:party_app/models/party_age_restriction.dart';
import 'package:party_app/models/party_registration_data.dart';
import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/utils/refund_policy.dart';

/// 두 등록 화면(파티 등록 / 플레이스+파티 등록)이 공유하는 파티 필드 묶음.
void main() {
  final now = DateTime(2026, 8, 1, 12, 0);

  PartyRecurringSchedule weekdaySchedule({DateTime? start, DateTime? end}) {
    var s = PartyRecurringSchedule(
      startDate: start ?? DateTime(2026, 8, 1),
      endDate: end,
      weekly: {
        for (final k in kPartyWeekdayKeys) k: const PartyWeeklySlot.disabled(),
      },
    );
    return s = s.applyTimesTo(
      kPartyWeekdayKeysWeekday,
      const PartyWeeklySlot(
        enabled: true,
        startTime: TimeOfDay(hour: 19, minute: 0),
        endTime: TimeOfDay(hour: 22, minute: 0),
      ),
    );
  }

  PartyRegistrationData single({
    PartyPricing? pricing,
    PartyEarlyBird earlyBird = const PartyEarlyBird.off(),
    int maxCapacity = 20,
    Set<String>? types,
    String fallbackCategory = '기타',
  }) {
    return PartyRegistrationData(
      scheduleType: PartyScheduleType.single,
      singleSchedule: PartySingleSchedule(
        date: DateTime(2026, 8, 15),
        startTime: const TimeOfDay(hour: 20, minute: 0),
        endTime: const TimeOfDay(hour: 2, minute: 0),
      ),
      maxCapacity: maxCapacity,
      pricing: pricing ?? PartyPricing.same(30000),
      earlyBird: earlyBird,
      partyTypes: types,
      fallbackCategory: fallbackCategory,
    );
  }

  group('toFirestore — 공통 필드', () {
    test('정원/성별 필드가 모두 채워진다', () {
      final map = PartyRegistrationData(
        scheduleType: PartyScheduleType.single,
        singleSchedule: PartySingleSchedule(
          date: DateTime(2026, 8, 15),
          startTime: const TimeOfDay(hour: 20, minute: 0),
        ),
        genderLimit: 'female',
        genderCapacityMode: 'separate',
        genderMode: 'balanced',
        maleCapacity: 0,
        femaleCapacity: 15,
        maxCapacity: 15,
        pricing: PartyPricing.same(20000),
      ).toFirestore();

      expect(map['genderLimit'], 'female');
      expect(map['genderCapacityMode'], 'separate');
      expect(map['genderMode'], 'balanced');
      expect(map['femaleCapacity'], 15);
      expect(map['maxCapacity'], 15);
      expect(map['maxParticipants'], 15);
      expect(map['people'], '0/15명');
      // 신규 문서의 참가자 카운터는 항상 0에서 시작한다.
      expect(map['currentParticipants'], 0);
      expect(map['currentMaleCount'], 0);
      expect(map['currentFemaleCount'], 0);
    });

    test('참가비·얼리버드·환불규정이 함께 직렬화된다', () {
      final map = single(
        pricing: PartyPricing.gendered(male: 35000, female: 25000),
        earlyBird: PartyEarlyBird(
          enabled: true,
          percent: 10,
          endDate: DateTime(2026, 8, 10),
          endTime: const TimeOfDay(hour: 18, minute: 0),
        ),
      ).toFirestore();

      expect(map['pricingType'], 'gendered');
      expect(map['malePrice'], 35000);
      expect(map['maleFee'], 35000); // 레거시 이중 기록
      expect(map['earlyBirdEnabled'], isTrue);
      expect(map['earlyBirdDiscountPercent'], 10);
      expect(map['refundPolicy'], isEmpty);
    });

    test('환불 규정이 있으면 단계별로 저장된다', () {
      final map = PartyRegistrationData(
        scheduleType: PartyScheduleType.single,
        singleSchedule: PartySingleSchedule(
          date: DateTime(2026, 8, 15),
          startTime: const TimeOfDay(hour: 20, minute: 0),
        ),
        maxCapacity: 10,
        pricing: PartyPricing.same(10000),
        refundTiers: [RefundTier(daysBefore: 7, refundPercent: 100)],
      ).toFirestore();
      expect((map['refundPolicy'] as List).length, 1);
    });

    test('연령 제한이 꺼져 있으면 나이 필드를 쓰지 않는다', () {
      final off = single().toFirestore();
      expect(off['ageRestrictionEnabled'], isFalse);
      expect(off.containsKey('minBirthYear'), isFalse);
      expect(off.containsKey('maleMinBirthYear'), isFalse);
      expect(off.containsKey('maleAgeRestrictionEnabled'), isFalse);

      final on = PartyRegistrationData(
        scheduleType: PartyScheduleType.single,
        singleSchedule: PartySingleSchedule(
          date: DateTime(2026, 8, 15),
          startTime: const TimeOfDay(hour: 20, minute: 0),
        ),
        maxCapacity: 10,
        pricing: const PartyPricing.free(),
        ageRestriction: const PartyAgeRestriction(
          enabled: true,
          male: GenderAgeLimit(
            enabled: true,
            minBirthYear: 1990,
            maxBirthYear: 2000,
          ),
          female: GenderAgeLimit(
            enabled: true,
            minBirthYear: 1990,
            maxBirthYear: 2000,
          ),
          perGender: true,
        ),
      ).toFirestore();
      // 성별 필드가 정본이고, 구버전 앱을 위한 옛 공통 필드도 함께 남는다.
      expect(on['maleMinBirthYear'], 1990);
      expect(on['maleMaxBirthYear'], 2000);
      expect(on['femaleMinBirthYear'], 1990);
      expect(on['femaleMaxBirthYear'], 2000);
      expect(on['minBirthYear'], 1990);
      expect(on['maxBirthYear'], 2000);
    });

    test('category — 유형을 고르면 첫 유형, 아니면 화면별 기본값', () {
      expect(
        single(fallbackCategory: '플레이스+파티').toFirestore()['category'],
        '플레이스+파티',
      );
      expect(single().toFirestore()['category'], '기타');
      expect(
        single(types: {'와인 파티'}).toFirestore()['category'],
        contains('와인'),
      );
    });

    test('일회성 파티는 singleSchedule을, 정기 파티는 recurringSchedule을 쓴다', () {
      final s = single().toFirestore();
      expect(s['scheduleType'], 'single');
      expect(s['singleSchedule'], isNotNull);
      expect(s['recurringSchedule'], isNull);

      final r = PartyRegistrationData(
        scheduleType: PartyScheduleType.recurring,
        recurringSchedule: weekdaySchedule(),
        maxCapacity: 20,
        pricing: const PartyPricing.free(),
      ).toFirestore();
      expect(r['scheduleType'], 'recurring');
      expect(r['recurringSchedule'], isNotNull);
      expect(r['singleSchedule'], isNull);
      // 정기 파티는 고정 마감을 남기지 않는다(회차마다 계산).
      expect(r['recruitDeadlineAt'], isNull);
    });

    test('일정이 없으면 일정 필드를 아예 쓰지 않는다', () {
      // 파티 등록 화면은 날짜 슬롯마다 문서를 나누므로 일정 필드를 자기가
      // 채운다 — 이 모델이 덮어쓰면 안 된다.
      final map = PartyRegistrationData(
        scheduleType: PartyScheduleType.single,
        maxCapacity: 10,
        pricing: const PartyPricing.free(),
      ).toFirestore();
      expect(map.containsKey('scheduleType'), isFalse);
      expect(map.containsKey('singleSchedule'), isFalse);
    });
  });

  group('validate', () {
    test('정상 입력은 통과', () {
      expect(single().validate(now: now), isNull);
    });

    test('모집 인원이 0이면 막는다', () {
      expect(single(maxCapacity: 0).validate(now: now), '모집 인원을 입력해주세요.');
    });

    test('일회성인데 일정이 없으면 막는다', () {
      final d = PartyRegistrationData(
        scheduleType: PartyScheduleType.single,
        maxCapacity: 10,
        pricing: const PartyPricing.free(),
      );
      expect(d.validate(now: now), '파티 날짜와 시작 시간을 선택해주세요.');
    });

    test('정기인데 요일을 고르지 않으면 막는다', () {
      final d = PartyRegistrationData(
        scheduleType: PartyScheduleType.recurring,
        recurringSchedule: PartyRecurringSchedule.empty(from: now),
        maxCapacity: 10,
        pricing: const PartyPricing.free(),
      );
      expect(d.validate(now: now), contains('운영 요일'));
    });

    test('운영 종료일이 지난 정기 파티는 막는다', () {
      final d = PartyRegistrationData(
        scheduleType: PartyScheduleType.recurring,
        recurringSchedule: weekdaySchedule(
          start: DateTime(2026, 7, 1),
          end: DateTime(2026, 7, 20),
        ),
        maxCapacity: 10,
        pricing: const PartyPricing.free(),
      );
      expect(d.validate(now: now), contains('열릴 회차가 없어요'));
    });

    test('무료 파티에 얼리버드를 켜면 막는다', () {
      final d = single(
        pricing: const PartyPricing.free(),
        earlyBird: PartyEarlyBird(
          enabled: true,
          percent: 10,
          endDate: DateTime(2026, 8, 10),
          endTime: const TimeOfDay(hour: 18, minute: 0),
        ),
      );
      expect(d.validate(now: now), '무료 파티는 얼리버드 할인을 사용할 수 없습니다.');
    });
  });
}

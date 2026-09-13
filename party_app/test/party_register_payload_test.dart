import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/party_detail_block.dart';
import 'package:party_app/models/party_early_bird.dart';
import 'package:party_app/models/party_early_bird_schedule.dart';
import 'package:party_app/models/party_pricing.dart';
import 'package:party_app/models/party_age_restriction.dart';
import 'package:party_app/models/party_registration_data.dart';
import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/utils/firestore_payload.dart';
import 'package:party_app/utils/refund_policy.dart';
import 'package:party_app/widgets/partychu_perk.dart';

// ══════════════════════════════════════════════════════════════════════════
// 일반 파티 등록 payload 회귀 테스트
//
// 실제 기기에서 "등록 중 문제가 발생했습니다"만 뜨고 끝나던 상황을 재현한다.
// 그 문구는 RegisterValidation이 **분류하지 못한 평범한 Dart 예외**에만
// 붙으므로(FirebaseException이면 에러 코드가, 업로드 실패면 다른 문구가 붙는다),
// 원인은 네트워크가 아니라 payload 조립 단계에 있었다.
//
// 재현 상태(사용자 보고 그대로):
//   연령대 미선택 · 사진 1장 · 참가비 + 얼리버드 · 환불 규정 ·
//   유형/분위기 · 상세 소개 · partychuPerk 빈 값
// ══════════════════════════════════════════════════════════════════════════

/// 화면이 조립하는 것과 같은 순서로 파티 문서 payload를 만든다.
/// (party_register_screen.dart `_submit`의 sharedFields + buildSlotDateFields)
Map<String, dynamic> buildPartyPayload({
  required PartyScheduleType scheduleType,
  PartyRecurringSchedule? recurringSchedule,
  required PartySingleSchedule singleSchedule,
  required bool ageRestrictionEnabled,
  required List<String> imageUrls,
  required String partychuPerk,
}) {
  final isRecurring = scheduleType == PartyScheduleType.recurring;
  return <String, dynamic>{
    'title': '금요일 와인 모임',
    'location': '서울 마포구 연남동 123-4',
    'address': '서울 마포구 연남동 123-4',
    'roadAddress': '서울 마포구 성미산로 100',
    'jibunAddress': '서울 마포구 연남동 123-4',
    'placeName': '연남 와인바',
    'latitude': 37.5622,
    'longitude': 126.9256,
    'seriesId': 'series-1',
    ...PartyRegistrationData(
      scheduleType: scheduleType,
      recurringSchedule: isRecurring ? recurringSchedule : null,
      genderLimit: 'all',
      genderCapacityMode: 'unlimited',
      genderMode: '',
      maxCapacity: 12,
      pricing: PartyPricing.gendered(male: 30000, female: 20000),
      earlyBird: const PartyEarlyBird(
        enabled: true,
        percent: 20,
        endType: PartyEarlyBirdEndType.beforeStart,
        beforeStartRule: PartyEarlyBirdDeadlineRule(),
      ),
      refundTiers: [
        RefundTier(daysBefore: 7, refundPercent: 100),
        RefundTier(daysBefore: 3, refundPercent: 50),
      ],
      // ── 재현 포인트 ① 연령대 미선택 ──────────────────────────────────
      ageRestriction: ageRestrictionEnabled
          ? const PartyAgeRestriction(
              enabled: true,
              male: GenderAgeLimit(
                enabled: true,
                minBirthYear: 1991,
                maxBirthYear: 2001,
              ),
              female: GenderAgeLimit(
                enabled: true,
                minBirthYear: 1991,
                maxBirthYear: 2001,
              ),
              perGender: true,
            )
          : PartyAgeRestriction.off,
      partyTypes: const {'wine'},
      vibes: const {'🍺 술 중심'},
      tags: const ['연남동'],
      description: '와인 좋아하는 사람들끼리 편하게 모여요.',
    ).toFirestore(),
    'hasMultipleRounds': false,
    // ── 재현 포인트 ② partychuPerk 빈 값 ────────────────────────────────
    kPartychuPerkField: partychuPerk,
    'region': '서울',
    'district': '마포구',
    // ── 재현 포인트 ③ 사진 1장 ──────────────────────────────────────────
    'images': imageUrls,
    'detailAddress': '2층',
    'detailBlocks': PartyDetailBlock.listToMaps(const []),
    'detailTheme': 'partychu',
    'detailDecorationIntensity': 'standard',
    'detailDecorationVariantSeed': 0,
    'detailDescriptionMode': 'auto',
    'autoDescriptionStyle': const <String, dynamic>{
      'theme': 'partychu',
      'intensity': 'standard',
      'variantSeed': 0,
      'paragraphStyles': <Map<String, dynamic>>[],
    },
    'recruitStatus': '모집중',
    'isRecurring': true,
    'isActive': true,
    'isDeleted': false,
    'status': 'active',
    'mainImageUrl': imageUrls.isNotEmpty ? imageUrls.first : null,
    'coverMediaType': 'image',
    'coverImageUrl': imageUrls.isNotEmpty ? imageUrls.first : null,
    'coverVideoUid': null,
    'coverVideoUrl': null,
    'coverThumbnailUrl': imageUrls.isNotEmpty ? imageUrls.first : null,
    'basicCardVideoFocalX': 0.5,
    'basicCardVideoFocalY': 0.5,
    'basicCardVideoScale': 1.0,
    'basicCardPhotoCrops': const <String, Map<String, double>>{},
    // 날짜 종속 필드 — 화면의 buildSlotDateFields와 같은 값.
    'date': '8월 15일 (금) 오후 8:00',
    'partyDateTime': Timestamp.fromDate(singleSchedule.start),
    if (isRecurring && recurringSchedule != null)
      ...PartySchedule.buildRecurringFields(recurringSchedule)
    else
      ...PartySchedule.buildSingleFields(singleSchedule),
    'hostId': 'host-1',
    'hostUid': 'host-1',
    'applicants': <String>[],
    'approvedApplicants': <String>[],
    'approved': true,
    'createdAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
  };
}

PartySingleSchedule _schedule() => PartySingleSchedule(
  date: DateTime(2026, 8, 15),
  startTime: const TimeOfDay(hour: 20, minute: 0),
  endTime: const TimeOfDay(hour: 23, minute: 0),
  registrationDeadline: DateTime(2026, 8, 14, 23, 59),
);

void main() {
  group('일반 파티 등록 payload — 연령대 미선택 / 사진 1장 / 얼리버드', () {
    late Map<String, dynamic> payload;

    setUp(() {
      payload = buildPartyPayload(
        scheduleType: PartyScheduleType.single,
        singleSchedule: _schedule(),
        ageRestrictionEnabled: false,
        imageUrls: const ['https://cdn.example.com/a.jpg'],
        partychuPerk: '',
      );
    });

    test('연령대는 선택 항목이라 payload 조립이 예외 없이 끝난다', () {
      // 저장 직전 검사까지 통과해야 한다 — 여기서 던지면 실제 화면에서도
      // Firestore까지 못 간다.
      expect(
        () => FirestorePayload.assertSafe(payload, tag: 'party-register'),
        returnsNormally,
      );
    });

    test('연령대 미선택이면 출생연도 필드를 아예 쓰지 않는다', () {
      // 읽는 쪽(party_eligibility 등)이 모두 ageRestrictionEnabled를 먼저
      // 보므로, 키가 없어도 "연령 제한 없음"으로 올바르게 동작한다.
      expect(payload['ageRestrictionEnabled'], isFalse);
      expect(payload.containsKey('minBirthYear'), isFalse);
      expect(payload.containsKey('maxBirthYear'), isFalse);
    });

    test('partychuPerk 빈 값은 null이 아니라 빈 문자열 String으로 들어간다', () {
      final value = payload[kPartychuPerkField];
      expect(value, isA<String>());
      expect(value, '');
    });

    test('사진 1장이어도 대표 이미지 계산에서 RangeError가 나지 않는다', () {
      expect(payload['images'], ['https://cdn.example.com/a.jpg']);
      expect(payload['mainImageUrl'], 'https://cdn.example.com/a.jpg');
      expect(payload['coverImageUrl'], 'https://cdn.example.com/a.jpg');
    });

    test('Set·enum은 저장 가능한 List·String으로 직렬화된다', () {
      expect(payload['partyTypes'], isA<List<String>>());
      expect(payload['vibes'], isA<List<String>>());
      expect(payload['pricingType'], isA<String>());
      expect(payload['scheduleType'], 'single');
    });

    test('환불 규정은 Map 리스트로 직렬화된다', () {
      final tiers = payload['refundPolicy'] as List;
      expect(tiers, hasLength(2));
      expect(tiers.first, isA<Map<String, dynamic>>());
    });

    test('일반 파티 payload에는 콤보 전용 필드가 하나도 들어가지 않는다', () {
      for (final key in const [
        'bundleId',
        'isCombo',
        'linkedPlaceId',
        'linkedEventId',
        'linkedPartyId',
        'comboPlaceType',
      ]) {
        expect(payload.containsKey(key), isFalse, reason: '$key 가 섞였다');
      }
    });
  });

  group('정기(매주 반복) 파티 — 일정 객체 누락 회귀', () {
    test('일정 객체 없이 정기 유형만 넘겨도 예외를 던지지 않는다', () {
      // 예전에는 toFirestore()가 `recurringSchedule!`를 그대로 써서
      // "Null check operator used on a null value"(_TypeError)가 났고,
      // 그 예외가 분류되지 않아 화면에는 "등록 중 문제가 발생했습니다"만 떴다.
      late Map<String, dynamic> map;
      expect(
        () => map = PartyRegistrationData(
          scheduleType: PartyScheduleType.recurring,
          maxCapacity: 10,
          pricing: PartyPricing.same(20000),
        ).toFirestore(),
        returnsNormally,
      );
      // 일정 객체가 없으면 일정 필드는 쓰지 않는다(호출부가 채운다) —
      // 나머지 공통 필드는 정상적으로 조립된다.
      expect(map.containsKey('scheduleType'), isFalse);
      expect(map['maxCapacity'], 10);
    });

    test('일정 객체를 넘기면 회차 계산 필드가 채워진다', () {
      final schedule = PartyRecurringSchedule(
        startDate: DateTime(2026, 8, 1),
        weekly: {
          for (final key in kPartyWeekdayKeys)
            key: key == 'friday'
                ? const PartyWeeklySlot(
                    enabled: true,
                    startTime: TimeOfDay(hour: 20, minute: 0),
                    endTime: TimeOfDay(hour: 23, minute: 0),
                  )
                : const PartyWeeklySlot.disabled(),
        },
      );
      final payload = buildPartyPayload(
        scheduleType: PartyScheduleType.recurring,
        recurringSchedule: schedule,
        singleSchedule: _schedule(),
        ageRestrictionEnabled: false,
        imageUrls: const ['https://cdn.example.com/a.jpg'],
        partychuPerk: '',
      );
      expect(payload['scheduleType'], 'recurring');
      expect(payload['recurringSchedule'], isA<Map<String, dynamic>>());
      expect(
        () => FirestorePayload.assertSafe(payload, tag: 'party-register'),
        returnsNormally,
      );
    });
  });

  group('FirestorePayload — 저장 불가 타입 검사', () {
    test('Set / enum / DateTime / Map<dynamic,dynamic>을 저장 가능한 형태로 바꾼다', () {
      final normalized = FirestorePayload.normalize({
        'tags': {'a', 'b'},
        'mode': PartyScheduleType.recurring,
        'at': DateTime(2026, 8, 15, 20),
        'nested': <dynamic, dynamic>{1: 'one'},
        'list': [
          {
            'inner': {'x'},
          },
        ],
      });
      expect(normalized['tags'], ['a', 'b']);
      expect(normalized['mode'], 'recurring');
      expect(normalized['at'], isA<Timestamp>());
      expect(normalized['nested'], {'1': 'one'});
      expect((normalized['list'] as List).first, {
        'inner': ['x'],
      });
      expect(FirestorePayload.describeIssues(normalized), isEmpty);
    });

    test('컨트롤러·위젯이 섞이면 필드 경로와 타입을 달아 예외를 던진다', () {
      final controller = TextEditingController(text: 'x');
      addTearDown(controller.dispose);

      expect(
        () => FirestorePayload.assertSafe({
          'title': '정상',
          'perkCtrl': controller,
          'blocks': [
            {'w': const SizedBox()},
          ],
        }, tag: 'party-register'),
        throwsA(
          isA<FirestorePayloadException>()
              .having((e) => e.issues, 'issues', hasLength(2))
              .having(
                (e) => e.issues.join(),
                'issues 내용',
                allOf(
                  contains('perkCtrl'),
                  contains('TextEditingController'),
                  contains('blocks[0].w'),
                ),
              ),
        ),
      );
    });

    test('정상 payload는 로그용 JSON으로 그대로 직렬화된다', () {
      final json = FirestorePayload.sanitizeForLogJson(
        buildPartyPayload(
          scheduleType: PartyScheduleType.single,
          singleSchedule: _schedule(),
          ageRestrictionEnabled: false,
          imageUrls: const ['https://cdn.example.com/a.jpg'],
          partychuPerk: '',
        ),
      );
      expect(json, contains('"title":"금요일 와인 모임"'));
      expect(json, contains('Timestamp('));
      expect(json, isNot(contains('직렬화 실패')));
    });
  });
}

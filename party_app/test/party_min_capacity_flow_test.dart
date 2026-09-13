import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/models/party_capacity_status.dart';
import 'package:party_app/models/party_registration_data.dart';
import 'package:party_app/models/party_pricing.dart';
import 'package:party_app/models/party_round.dart';
import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/widgets/party_card_widget.dart';

/// 파티 **전체** 최소 모집 인원과 **차수별** 최소 인원이 끝까지 갈라져 있는지를
/// 저장 → 복원 흐름 그대로 확인한다.
///
/// 단위 규칙은 party_capacity_status_test.dart가 본다. 여기서는 실제로 문서에
/// 쓰이는 값(PartyRegistrationData.toFirestore + PartyRound.toMap)과 그것을
/// 다시 읽는 값(PartyMinCapacity.of, PartyCard.capacityStatus)을 이어서 본다 —
/// 두 값이 어디선가 합쳐지면 여기서 걸린다.
///
/// 서버 쪽 같은 규칙은 functions/partyMinCapacity.selfcheck.js가 본다.
void main() {
  // 등록 화면이 저장하는 것과 같은 모양의 파티 문서를 만든다.
  Map<String, dynamic> registeredParty({
    required int partyMin,
    required List<int> roundMins,
    int roundCapacityEach = 10,
    bool isRecurring = false,
    PartyMinCapacityPolicy policy = PartyMinCapacityPolicy.proceed,
  }) {
    final rounds = [
      for (var i = 0; i < roundMins.length; i++)
        PartyRound(
          id: 'round_${i + 1}',
          label: '${i + 1}차',
          startTime: const TimeOfDay(hour: 19, minute: 0),
          minCapacity: roundMins[i],
          maxCapacity: roundCapacityEach,
          maleFee: 30000,
          femaleFee: 30000,
        ).toMap(
          roundNumber: i + 1,
          partyDate: DateTime(2026, 9, 4),
          perRound: true,
        ),
    ];
    // 정원은 자리 수라 합산이 옳다 — 등록 화면의 aggMaxCapacity와 같은 규칙.
    final totalCapacity = roundCapacityEach * roundMins.length;
    return {
      ...PartyRegistrationData(
        scheduleType: isRecurring
            ? PartyScheduleType.recurring
            : PartyScheduleType.single,
        genderLimit: 'all',
        genderCapacityMode: 'unlimited',
        genderMode: '',
        maleCapacity: 0,
        femaleCapacity: 0,
        minCapacity: partyMin,
        maxCapacity: totalCapacity,
        minCapacityPolicy: policy,
        pricing: PartyPricing.gendered(male: 30000, female: 30000),
      ).toFirestore(),
      'hasMultipleRounds': true,
      'roundCapacityMode': 'perRound',
      'rounds': rounds,
    };
  }

  group('① 차수 최소 인원은 파티 최소 모집 인원으로 합산되지 않는다', () {
    test('1차 2명 + 2차 2명인데 파티 최소를 안 정하면 0이다 (예전엔 4)', () {
      final doc = registeredParty(partyMin: 0, roundMins: [2, 2]);

      expect(
        doc[PartyMinCapacity.field],
        0,
        reason: '호스트가 파티 최소 모집 인원을 정하지 않았다',
      );
      expect(doc['minCapacity'], 0, reason: '옛 필드에도 합계가 들어가면 안 된다');
      expect(PartyMinCapacity.of(doc), 0);
      // 상세 화면이 그리는 값 — '최소 모집: 4명'이 떠서는 안 된다.
      expect(PartyCard.capacityStatus(doc).minLabel, isNull);
      // 차수 값 자체는 그대로 살아 있다.
      expect(doc['rounds'][0]['minCapacity'], 2);
      expect(doc['rounds'][1]['minCapacity'], 2);
    });

    test('차수가 몇 개든 파티 최소는 호스트가 정한 값 그대로다', () {
      final doc = registeredParty(partyMin: 6, roundMins: [2, 3, 4]);
      expect(PartyMinCapacity.of(doc), 6, reason: '2+3+4=9가 되면 안 된다');
      expect(PartyCard.capacityStatus(doc).minLabel, '최소 모집: 6명');
    });
  });

  group('② 파티 6명 / 1차 2명 / 2차 3명 — 세 값이 각각 저장·복원된다', () {
    final doc = registeredParty(partyMin: 6, roundMins: [2, 3]);

    test('저장된 문서에 세 값이 서로 다른 자리에 남는다', () {
      expect(doc[PartyMinCapacity.field], 6);
      expect(doc['rounds'][0]['minCapacity'], 2);
      expect(doc['rounds'][1]['minCapacity'], 3);
    });

    test('수정 화면이 읽는 경로로 되읽어도 그대로다', () {
      // 수정/재등록 화면의 복원 경로와 같은 함수들.
      expect(PartyMinCapacity.of(doc), 6);
      final restored = [
        for (final raw in doc['rounds'] as List)
          PartyRound.fromMap(Map<String, dynamic>.from(raw as Map)),
      ];
      expect(restored[0]?.minCapacity, 2);
      expect(restored[1]?.minCapacity, 3);
      // 되읽은 차수를 다시 저장해도 값이 흐르지 않는다(왕복 안정).
      final again = restored[1]!.toMap(
        roundNumber: 2,
        partyDate: DateTime(2026, 9, 4),
        perRound: true,
      );
      expect(again['minCapacity'], 3);
    });

    test('파티 최소를 고쳐도 차수 값은 따라 움직이지 않는다', () {
      final edited = {...doc, PartyMinCapacity.field: 8, 'minCapacity': 8};
      expect(PartyMinCapacity.of(edited), 8);
      expect(edited['rounds'][0]['minCapacity'], 2);
      expect(edited['rounds'][1]['minCapacity'], 3);
    });
  });

  group('③ 정기 파티 — 미달 회차만 취소되고 다른 회차는 그대로', () {
    // 서버가 남기는 회차 취소 기록(functions/partyMinCapacity.js의
    // occurrenceCancelFields)을 그대로 옮긴 문서.
    Map<String, dynamic> recurringWithCancelledA() => {
      ...registeredParty(
        partyMin: 6,
        roundMins: [2, 3],
        isRecurring: true,
        policy: PartyMinCapacityPolicy.autoCancel,
      ),
      'scheduleType': 'recurring',
      'recurringSchedule': {
        'startDate': '2026-08-01T00:00:00+09:00',
        'weeklySchedule': {
          'friday': {'startTime': '19:00', 'endTime': '22:00'},
          'saturday': {'startTime': '19:00', 'endTime': '22:00'},
        },
        'registrationDeadline': {'mode': 'beforeStart', 'minutes': 60},
      },
      'occurrenceStats': {
        '2026-09-04': {'currentParticipants': 2, 'applicants': []},
        '2026-09-05': {'currentParticipants': 6, 'applicants': []},
      },
      'occurrenceCancellations': {
        '2026-09-04': {
          'reason': PartyCancelReason.minCapacityNotMet,
          'cancelledBySystem': true,
          'minCapacityAtCancel': 6,
          'participantsAtCancel': 2,
        },
      },
    };

    test('A회차는 취소로 읽히고 B회차는 취소가 아니다', () {
      final doc = recurringWithCancelledA();
      expect(
        PartyCard.occurrenceCancellation(doc, occurrenceId: '2026-09-04'),
        isNotNull,
      );
      expect(
        PartyCard.occurrenceCancellation(doc, occurrenceId: '2026-09-05'),
        isNull,
      );
    });

    test('파티 문서 전체는 여전히 모집중이다 — B회차가 살아 있어야 한다', () {
      final doc = recurringWithCancelledA();
      expect(doc['recruitStatus'], isNot('취소'));
      expect(PartyCancelReason.labelOf(doc), isNull);
    });

    test('두 회차의 모집 현황은 서로 섞이지 않고 기준선만 같다', () {
      final doc = recurringWithCancelledA();
      final a = PartyCard.capacityStatus(doc, occurrenceId: '2026-09-04');
      final b = PartyCard.capacityStatus(doc, occurrenceId: '2026-09-05');
      expect(a.current, 2);
      expect(b.current, 6);
      // 최소 모집 인원은 파티에 하나 — 회차마다 다시 정하지 않는다.
      expect(a.min, 6);
      expect(b.min, 6);
      expect(a.minReached, isFalse);
      expect(b.minReached, isTrue);
    });
  });

  group('⑨ 새 필드가 없는 옛 라운드 파티는 0으로 떨어진다', () {
    test('차수별 정원 파티의 minCapacity(합계)는 쓰지 않는다', () {
      // 이번 변경 전에 저장된 문서 — 1차 2명 + 2차 2명이 4로 합쳐져 있다.
      final legacy = {
        'minCapacity': 4,
        'maxCapacity': 20,
        'currentParticipants': 2,
        'hasMultipleRounds': true,
        'roundCapacityMode': 'perRound',
      };
      expect(PartyMinCapacity.of(legacy), 0);
      expect(PartyCard.capacityStatus(legacy).minLabel, isNull);
      expect(PartyCard.capacityStatus(legacy).minReached, isFalse);
    });

    test('차수가 없거나 통합 정원인 옛 문서는 그대로 믿는다', () {
      expect(PartyMinCapacity.of({'minCapacity': 10}), 10);
      expect(
        PartyMinCapacity.of({
          'minCapacity': 10,
          'hasMultipleRounds': true,
          'roundCapacityMode': 'unified',
        }),
        10,
      );
    });

    test('한 번 다시 저장하면 새 필드가 붙어 폴백을 벗어난다', () {
      final resaved = registeredParty(partyMin: 6, roundMins: [2, 2]);
      expect(PartyMinCapacity.isLegacySummed(resaved), isFalse);
      expect(PartyMinCapacity.of(resaved), 6);
    });
  });

  group('자동 취소 스위치', () {
    test('최소 인원을 정하지 않으면 자동 취소는 저장되지 않는다', () {
      final doc = registeredParty(
        partyMin: 0,
        roundMins: [2, 2],
        policy: PartyMinCapacityPolicy.autoCancel,
      );
      expect(doc['minCapacityPolicy'], PartyMinCapacityPolicy.proceed.key);
      expect(PartyCard.autoCancelsBelowMin(doc), isFalse);
    });

    test('정기 파티도 자동 취소를 저장할 수 있다 (회차 단위로 동작)', () {
      final doc = registeredParty(
        partyMin: 6,
        roundMins: [2, 3],
        isRecurring: true,
        policy: PartyMinCapacityPolicy.autoCancel,
      );
      expect(doc['minCapacityPolicy'], PartyMinCapacityPolicy.autoCancel.key);
      expect(PartyCard.autoCancelsBelowMin(doc), isTrue);
    });

    test('자동 취소를 끄면 미달이어도 정상 진행으로 남는다', () {
      final doc = registeredParty(
        partyMin: 6,
        roundMins: [2, 3],
        policy: PartyMinCapacityPolicy.proceed,
      );
      expect(PartyCard.autoCancelsBelowMin(doc), isFalse);
      expect(PartyCard.capacityStatus(doc).minReached, isFalse);
    });
  });
}

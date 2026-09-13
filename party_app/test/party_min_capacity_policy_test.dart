import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/models/party_capacity_status.dart';
import 'package:party_app/models/party_pricing.dart';
import 'package:party_app/models/party_registration_data.dart';
import 'package:party_app/models/party_schedule.dart';

PartyRegistrationData _data({
  required bool recurring,
  int minCapacity = 10,
  PartyMinCapacityPolicy policy = PartyMinCapacityPolicy.autoCancel,
}) {
  final weekly = <String, PartyWeeklySlot>{
    for (final k in kPartyWeekdayKeys) k: const PartyWeeklySlot.disabled(),
    'monday': const PartyWeeklySlot(
      enabled: true,
      startTime: TimeOfDay(hour: 19, minute: 0),
      endTime: TimeOfDay(hour: 22, minute: 0),
    ),
  };
  return PartyRegistrationData(
    scheduleType: recurring
        ? PartyScheduleType.recurring
        : PartyScheduleType.single,
    recurringSchedule: recurring
        ? PartyRecurringSchedule(
            startDate: DateTime(2026, 8, 1),
            weekly: weekly,
          )
        : null,
    singleSchedule: recurring
        ? null
        : PartySingleSchedule(
            date: DateTime(2026, 8, 10),
            startTime: const TimeOfDay(hour: 19, minute: 0),
          ),
    minCapacity: minCapacity,
    maxCapacity: 20,
    minCapacityPolicy: policy,
    pricing: PartyPricing.same(20000),
  );
}

void main() {
  group('최소 인원 미달 처리 저장값', () {
    test('일회성 파티는 고른 값(자동 취소)이 그대로 저장된다', () {
      final m = _data(recurring: false).toFirestore();
      expect(m['minCapacity'], 10);
      expect(m['minCapacityPolicy'], 'autoCancel');
    });

    test('정기 파티도 고른 값(자동 취소)이 그대로 저장된다', () {
      // 예전에는 정기 파티를 proceed로 강제했다 — 서버의 자동 취소 작업이
      // 정기 파티를 통째로 건너뛰어서, autoCancel로 저장하면 "설정했는데
      // 동작 안 함"이 됐기 때문이다.
      //
      // 지금은 서버가 **회차 단위**로 판정한다(functions/partyMinCapacity.js의
      // dueOccurrencesOf — isAutoCancelCandidate는 여전히 정기를 제외하고,
      // 그 대신 미달된 회차 하나만 취소한다. 다른 날짜 회차는 그대로 열린다).
      // 그래서 정기 파티도 이 값을 실제로 쓰며, 강제로 덮으면 호스트가 켠
      // 설정이 사라진다.
      final m = _data(recurring: true).toFirestore();
      expect(m['minCapacity'], 10);
      expect(m['minCapacityPolicy'], 'autoCancel');
    });

    test('최소 인원을 안 정하면 일회성도 proceed로 굳는다', () {
      final m = _data(recurring: false, minCapacity: 0).toFirestore();
      expect(m['minCapacityPolicy'], 'proceed');
    });

    test('최소가 최대보다 크면 저장 전에 막힌다', () {
      final error = _data(recurring: false, minCapacity: 21).validate();
      expect(error, isNotNull);
      expect(error, contains('최소 모집 인원'));
    });

    test('최소 ≤ 최대면 통과', () {
      expect(_data(recurring: false, minCapacity: 20).validate(), isNull);
    });
  });
}

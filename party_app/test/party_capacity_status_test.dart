import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/models/party_capacity_status.dart';

void main() {
  group('모집 현황 표시', () {
    test('현황 문구는 8 / 20명', () {
      const s = PartyCapacityStatus(current: 8, min: 10, max: 20);
      expect(s.countLabel, '8 / 20명');
      expect(s.minLabel, '최소 모집: 10명');
    });

    test('최대가 없으면 현재 인원만 보여준다', () {
      const s = PartyCapacityStatus(current: 8);
      expect(s.countLabel, '8명');
      expect(s.minLabel, isNull);
      expect(s.progress, isNull);
    });

    test('최소까지 남은 인원을 세어준다', () {
      const s = PartyCapacityStatus(current: 8, min: 10, max: 20);
      expect(s.minReached, isFalse);
      expect(s.remainingToMin, 2);
    });

    test('최소를 채우면 확정 — 남은 인원은 0', () {
      const s = PartyCapacityStatus(current: 10, min: 10, max: 20);
      expect(s.minReached, isTrue);
      expect(s.remainingToMin, 0);
    });

    test('최소를 넘겨도 확정 상태를 유지한다', () {
      const s = PartyCapacityStatus(current: 15, min: 10, max: 20);
      expect(s.minReached, isTrue);
      expect(s.isFull, isFalse);
    });

    test('최대를 채우면 정원 마감', () {
      const s = PartyCapacityStatus(current: 20, min: 10, max: 20);
      expect(s.isFull, isTrue);
      expect(s.minReached, isTrue);
    });

    test('최소를 안 정하면 확정 개념이 없다', () {
      const s = PartyCapacityStatus(current: 8, max: 20);
      expect(s.hasMin, isFalse);
      expect(s.minReached, isFalse);
      expect(s.remainingToMin, 0);
      expect(s.minMarker, isNull);
    });

    test('진행 막대와 최소선 위치', () {
      const s = PartyCapacityStatus(current: 8, min: 10, max: 20);
      expect(s.progress, 0.4);
      expect(s.minMarker, 0.5);
    });

    test('최대를 넘겨 신청돼도 막대는 1을 넘지 않는다', () {
      const s = PartyCapacityStatus(current: 25, min: 10, max: 20);
      expect(s.progress, 1.0);
    });
  });

  group('검증', () {
    test('최소가 최대보다 크면 막는다', () {
      expect(PartyCapacityStatus.validate(min: 21, max: 20), isNotNull);
    });

    test('최소와 최대가 같으면 통과', () {
      expect(PartyCapacityStatus.validate(min: 20, max: 20), isNull);
    });

    test('최소가 최대보다 작으면 통과', () {
      expect(PartyCapacityStatus.validate(min: 10, max: 20), isNull);
    });

    test('최소를 안 정하면(0) 최대와 무관하게 통과', () {
      expect(PartyCapacityStatus.validate(min: 0, max: 20), isNull);
      expect(PartyCapacityStatus.validate(min: 0, max: 0), isNull);
    });

    test('음수는 막는다', () {
      expect(PartyCapacityStatus.validate(min: -1, max: 20), isNotNull);
    });
  });

  group('문서에서 읽기', () {
    test('일반 파티 — currentParticipants를 그대로 쓴다', () {
      final s = PartyCapacityStatus.fromMap({
        'currentParticipants': 8,
        'minCapacity': 10,
        'maxCapacity': 20,
      });
      expect(s.current, 8);
      expect(s.min, 10);
      expect(s.max, 20);
    });

    test('성비 맞춤 파티 — 남녀 신청자를 합산한다', () {
      final s = PartyCapacityStatus.fromMap({
        'currentMaleCount': 4,
        'currentFemaleCount': 3,
        'minCapacity': 10,
        'maxCapacity': 20,
      });
      expect(s.current, 7);
    });

    test('maxCapacity가 없는 예전 문서는 maxParticipants로 폴백', () {
      final s = PartyCapacityStatus.fromMap({
        'currentParticipants': 3,
        'maxParticipants': 12,
      });
      expect(s.max, 12);
      expect(s.hasMin, isFalse);
    });

    test('회차별 인원은 밖에서 넘겨 덮어쓸 수 있다', () {
      final s = PartyCapacityStatus.fromMap({
        'currentParticipants': 30,
        'minCapacity': 5,
        'maxCapacity': 20,
      }, currentOverride: 6);
      expect(s.current, 6);
      expect(s.minReached, isTrue);
    });
  });

  // 여기서 확인하는 규칙은 서버(functions/partyMinCapacity.js의
  // partyMinCapacityOf, functions/partyMinCapacity.selfcheck.js)와 같은
  // 결과여야 한다 — 한쪽만 고치면 앱에는 '확정'이 떠 있는데 서버가 취소한다.
  group('파티 전체 최소 모집 인원', () {
    test('새 필드가 있으면 그 값이 정본이다', () {
      expect(PartyMinCapacity.of({'partyMinCapacity': 6, 'minCapacity': 4}), 6);
      // 0도 "제한 없음으로 정했다"는 뜻이라 옛 필드로 넘어가지 않는다.
      expect(PartyMinCapacity.of({'partyMinCapacity': 0, 'minCapacity': 4}), 0);
    });

    test('차수 없는 옛 문서는 minCapacity를 그대로 믿는다', () {
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

    test('차수별 정원 옛 문서의 minCapacity는 차수 합계라 0으로 본다', () {
      // 1차 최소 2명 + 2차 최소 2명 → minCapacity 4로 저장돼 있던 문서.
      // 그 4는 "이 파티가 열리려면 4명"이라는 뜻이 아니므로 쓰지 않는다.
      final legacy = {
        'minCapacity': 4,
        'hasMultipleRounds': true,
        'roundCapacityMode': 'perRound',
      };
      expect(PartyMinCapacity.of(legacy), 0);
      expect(PartyMinCapacity.isLegacySummed(legacy), isTrue);
      // 다시 저장돼 새 필드가 붙으면 더 이상 오염된 문서가 아니다.
      expect(PartyMinCapacity.of({...legacy, 'partyMinCapacity': 6}), 6);
      expect(
        PartyMinCapacity.isLegacySummed({...legacy, 'partyMinCapacity': 6}),
        isFalse,
      );
    });

    test('폴백이 0이면 확정 배지도 뜨지 않는다', () {
      final s = PartyCapacityStatus.fromMap({
        'currentParticipants': 8,
        'maxCapacity': 20,
        'minCapacity': 4,
        'hasMultipleRounds': true,
        'roundCapacityMode': 'perRound',
      });
      expect(s.min, 0);
      expect(s.hasMin, isFalse);
      expect(s.minReached, isFalse);
      expect(s.minLabel, isNull);
    });

    test('새 필드를 쓰면 모집 현황 문구가 그 값으로 나온다', () {
      // 정원 20명 파티에 최소 모집 6명 — 차수 값이 무엇이든 6명이다.
      final s = PartyCapacityStatus.fromMap({
        'currentParticipants': 2,
        'maxCapacity': 20,
        'partyMinCapacity': 6,
        'minCapacity': 4, // 옛 필드에 남아 있는 차수 합계
        'hasMultipleRounds': true,
        'roundCapacityMode': 'perRound',
      });
      expect(s.minLabel, '최소 모집: 6명');
      expect(s.remainingToMin, 4);
    });
  });

  group('미달 처리 옵션', () {
    test('기본값은 정상 진행', () {
      expect(
        PartyMinCapacityPolicy.fromKey(null),
        PartyMinCapacityPolicy.proceed,
      );
      expect(
        PartyMinCapacityPolicy.fromKey('알 수 없는 값'),
        PartyMinCapacityPolicy.proceed,
      );
    });

    test('자동 취소를 골랐는지 알 수 있다', () {
      final policy = PartyMinCapacityPolicy.fromKey('autoCancel');
      expect(policy, PartyMinCapacityPolicy.autoCancel);
      expect(policy.isAutoCancel, isTrue);
      expect(PartyMinCapacityPolicy.proceed.isAutoCancel, isFalse);
    });
  });

  group('취소 사유 안내', () {
    test('최소 인원 미달 자동 취소는 안내 문구가 있다', () {
      expect(
        PartyCancelReason.labelOf({'cancelReason': 'minCapacityNotMet'}),
        '최소 모집 인원 미달로 취소된 파티',
      );
    });

    test('호스트가 직접 취소했으면(사유 없음) 문구가 없다', () {
      expect(PartyCancelReason.labelOf({}), isNull);
      expect(PartyCancelReason.labelOf({'cancelReason': 'etc'}), isNull);
    });
  });
}

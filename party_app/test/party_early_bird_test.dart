import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/models/party_early_bird.dart';

void main() {
  final now = DateTime(2026, 8, 1, 12, 0);
  final future = DateTime(2026, 8, 15);
  final past = DateTime(2026, 7, 1);

  PartyEarlyBird on({
    int? percent = 10,
    DateTime? date,
    TimeOfDay? time = const TimeOfDay(hour: 18, minute: 0),
  }) => PartyEarlyBird(
    enabled: true,
    percent: percent,
    endDate: date ?? future,
    endTime: time,
  );

  group('검증', () {
    test('꺼져 있으면 통과', () {
      expect(
        const PartyEarlyBird.off().validate(isFree: true, now: now),
        isNull,
      );
    });

    test('정상 입력은 통과', () {
      expect(on().validate(isFree: false, now: now), isNull);
    });

    test('할인율 범위', () {
      for (final pct in [null, 0, 100]) {
        expect(
          on(percent: pct).validate(isFree: false, now: now),
          '얼리버드 할인율은 1~99% 사이로 입력해주세요.',
          reason: 'percent=$pct',
        );
      }
      expect(on(percent: 1).validate(isFree: false, now: now), isNull);
      expect(on(percent: 99).validate(isFree: false, now: now), isNull);
    });

    test('종료 시각이 비면 안내', () {
      expect(
        on(time: null).validate(isFree: false, now: now),
        '얼리버드 종료일과 시간을 선택해주세요.',
      );
    });

    test('종료 시각이 과거면 안내', () {
      expect(
        on(date: past).validate(isFree: false, now: now),
        '얼리버드 종료 시각은 현재 시간 이후여야 합니다.',
      );
    });

    test('무료 파티는 사용할 수 없다', () {
      expect(
        on().validate(isFree: true, now: now),
        '무료 파티는 얼리버드 할인을 사용할 수 없습니다.',
      );
    });
  });

  group('직렬화', () {
    test('켜져 있고 종료 시각이 완성되면 기록된다', () {
      final map = on().toMap();
      expect(map['earlyBirdEnabled'], isTrue);
      expect(map['earlyBirdDiscountPercent'], 10);
      expect(
        (map['earlyBirdEndAt'] as Timestamp).toDate(),
        DateTime(2026, 8, 15, 18, 0),
      );
    });

    test('종료 시각이 없으면 꺼진 것으로 기록된다', () {
      final map = on(time: null).toMap();
      expect(map['earlyBirdEnabled'], isFalse);
      expect(map['earlyBirdDiscountPercent'], isNull);
      expect(map['earlyBirdEndAt'], isNull);
    });

    test('fromMap — 아직 유효한 할인은 복원된다', () {
      final restored = PartyEarlyBird.fromMap({
        'earlyBirdEnabled': true,
        'earlyBirdDiscountPercent': 15,
        'earlyBirdEndAt': Timestamp.fromDate(DateTime(2026, 8, 15, 20, 0)),
      }, now: now);
      expect(restored.enabled, isTrue);
      expect(restored.percent, 15);
      expect(restored.endDate, DateTime(2026, 8, 15));
      expect(restored.endTime, const TimeOfDay(hour: 20, minute: 0));
    });

    test('fromMap — 이미 지난 할인은 꺼진 상태로 복원된다', () {
      final restored = PartyEarlyBird.fromMap({
        'earlyBirdEnabled': true,
        'earlyBirdDiscountPercent': 15,
        'earlyBirdEndAt': Timestamp.fromDate(past),
      }, now: now);
      expect(restored.enabled, isFalse);
    });

    test('임시저장 왕복', () {
      final back = PartyEarlyBird.fromDraftMap(on(percent: 25).toDraftMap());
      expect(back.enabled, isTrue);
      expect(back.percent, 25);
      expect(back.endDate, future);
      expect(back.endTime, const TimeOfDay(hour: 18, minute: 0));
    });

    test('임시저장은 지난 시각도 작성 중 값 그대로 복원한다', () {
      final back = PartyEarlyBird.fromDraftMap(on(date: past).toDraftMap());
      expect(back.enabled, isTrue);
      expect(back.endDate, past);
    });
  });

  test('요약 문구', () {
    expect(on().summary, '얼리버드 10% · 8월 15일 18:00까지');
    expect(const PartyEarlyBird.off().summary, isNull);
    expect(on(time: null).summary, isNull);
  });
}

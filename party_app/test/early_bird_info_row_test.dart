// 얼리버드 안내 — 별도 카드가 아니라 **기본 정보 카드의 맨 아래 정보행**.
//
// 예전에는 참가비 아래에 네모 박스(PartyChuCard.compact)가 따로 떠 있었다.
// 정기 일정·모집 마감과 같은 성격의 정보인데 다른 덩어리처럼 읽혀서, 같은
// 정보행 스타일로 카드 안에 합쳤다.
//
// 옮긴 것은 **자리뿐**이다. 그래서 여기서 보는 것은 셋이다.
//  1. 행에 들어가는 값이 정본 문구(EarlyBird.statusLabel)에서 나오는가
//     — 라벨 칸과 겹치는 '얼리버드'만 덜어낼 뿐, 새 문구를 만들지 않는다.
//  2. 행이 보이는 조건이 예전 카드와 같은가(할인 중 / 다음 회차 예정 / 숨김).
//  3. 상세 화면에 별도 얼리버드 카드가 남아 있지 않은가.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/party_early_bird_schedule.dart';
import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/utils/early_bird.dart';

void main() {
  // 2026-08-22(토) 오전 10시.
  final now = DateTime(2026, 8, 22, 10);

  const rule = PartyEarlyBirdDeadlineRule(
    mode: EarlyBirdDeadlineMode.daysBefore,
    days: 3,
    time: TimeOfDay(hour: 23, minute: 59),
  );

  /// 매일 19:00 열리는 정기 파티 + 얼리버드 20%('파티 시작 3일 전까지').
  Map<String, dynamic> recurringParty({bool earlyBird = true}) => {
    'scheduleType': 'recurring',
    'recurringSchedule': PartyRecurringSchedule(
      startDate: DateTime(2026, 7, 1),
      weekly: {
        for (final k in kPartyWeekdayKeys)
          k: const PartyWeeklySlot(
            enabled: true,
            startTime: TimeOfDay(hour: 19, minute: 0),
            endTime: TimeOfDay(hour: 23, minute: 0),
          ),
      },
    ).toMap(),
    'price': 20000,
    'earlyBirdEnabled': earlyBird,
    'earlyBirdDiscountPercent': 20,
    kEarlyBirdRuleField: rule.toMap(),
  };

  /// 단일 날짜 파티 + 같은 얼리버드 규칙('파티 시작 3일 전 23:59까지').
  Map<String, dynamic> singleParty({required DateTime start}) => {
    'startDateTime': start.toIso8601String(),
    'price': 20000,
    'earlyBirdEnabled': true,
    'earlyBirdDiscountPercent': 20,
    kEarlyBirdRuleField: rule.toMap(),
  };

  /// 상세 화면이 행을 그릴지 정하는 식 — party_detail_screen.dart와 같다.
  bool rowVisible(Map<String, dynamic> data, {DateTime? occurrenceStart}) =>
      EarlyBird.isActive(data, now: now, occurrenceStart: occurrenceStart) ||
      EarlyBird.firstDiscountedOccurrenceStart(data, now: now) != null;

  /// 행에 들어갈 값 — 화면과 같은 조합.
  String rowText(Map<String, dynamic> data, {DateTime? occurrenceStart}) =>
      earlyBirdInfoRowText(
        EarlyBird.statusLabel(data, now: now, occurrenceStart: occurrenceStart),
      );

  group('행 문구는 정본에서 나온다', () {
    test('라벨과 겹치는 앞머리만 덜어낸다', () {
      expect(earlyBirdInfoRowText('얼리버드 D-2'), 'D-2');
      expect(earlyBirdInfoRowText('얼리버드 오늘 23:59 마감'), '오늘 23:59 마감');
      expect(earlyBirdInfoRowText('얼리버드 마감'), '마감');
      expect(
        earlyBirdInfoRowText('8월 24일(월) 회차부터 얼리버드 할인'),
        '8월 24일(월) 회차부터 할인',
      );
    });

    test('얼리버드를 안 쓰면 빈 값이다', () {
      expect(earlyBirdInfoRowText(''), '');
    });

    test('행 값에는 라벨과 겹치는 얼리버드가 남지 않는다', () {
      final data = recurringParty();
      expect(EarlyBird.statusLabel(data, now: now), isNotEmpty);
      final text = rowText(data);
      expect(text, isNotEmpty);
      expect(text.contains('얼리버드'), isFalse, reason: text);
    });
  });

  group('보이는 조건은 예전 카드 그대로', () {
    test('지금 할인 중이면 D-Day 문구가 뜬다', () {
      // 8/26 회차는 3일 전(8/23 23:59)까지 할인 → 지금(8/22) 유효하다.
      final data = recurringParty();
      final start = DateTime(2026, 8, 26, 19);
      expect(
        EarlyBird.isActive(data, now: now, occurrenceStart: start),
        isTrue,
      );
      expect(rowVisible(data, occurrenceStart: start), isTrue);
      expect(rowText(data, occurrenceStart: start), startsWith('D-'));
    });

    test('이번 회차는 끝났어도 뒤 회차가 남았으면 그 날짜를 알려준다', () {
      // 다음 회차(8/22 19:00)는 얼리버드가 이미 끝났다(8/19 23:59).
      final data = recurringParty();
      final thisOccurrence = DateTime(2026, 8, 22, 19);
      expect(
        EarlyBird.isActive(data, now: now, occurrenceStart: thisOccurrence),
        isFalse,
      );
      expect(rowVisible(data, occurrenceStart: thisOccurrence), isTrue);

      final text = rowText(data, occurrenceStart: thisOccurrence);
      expect(text, contains('회차부터 할인'));
      expect(text, isNot(contains('얼리버드')), reason: '라벨 칸과 겹치면 안 된다');
    });

    test('얼리버드를 안 쓰는 파티는 행 자체가 없다', () {
      final data = recurringParty(earlyBird: false);
      expect(rowVisible(data), isFalse);
      expect(rowText(data), '');
    });

    test('완전히 끝난 단일 날짜 파티는 행 자체가 없다', () {
      // 8/23 회차의 얼리버드는 8/20 23:59에 끝났다.
      final data = singleParty(start: DateTime(2026, 8, 23, 19));
      expect(rowVisible(data), isFalse, reason: '예전 카드도 이 경우 숨겼다');
    });
  });

  group('단일 날짜 파티도 같은 행을 쓴다', () {
    test('할인 중이면 D-Day 문구가 뜬다', () {
      // 9/5 회차 → 얼리버드는 9/2 23:59까지. 오늘(8/22) 기준 D-11.
      final data = singleParty(start: DateTime(2026, 9, 5, 19));
      expect(PartySchedule.isRecurring(data), isFalse);
      expect(rowVisible(data), isTrue);
      expect(rowText(data), 'D-11');
    });
  });

  group('별도 얼리버드 카드가 남아 있지 않다', () {
    final src = File('lib/screens/party_detail_screen.dart').readAsStringSync();

    test('상세 화면에 얼리버드 전용 카드 위젯이 없다', () {
      expect(src.contains('_earlyBirdInfo'), isFalse);
      // 정보행으로 그리는 자리는 그대로 있어야 한다.
      expect(src.contains('earlyBirdRowText'), isTrue);
      expect(src.contains('earlyBirdInfoRowText('), isTrue);
    });

    test('판정은 여전히 EarlyBird가 한다 — 화면이 다시 계산하지 않는다', () {
      expect(src.contains('EarlyBird.isActive('), isTrue);
      expect(src.contains('EarlyBird.firstDiscountedOccurrenceStart('), isTrue);
      expect(src.contains('EarlyBird.statusLabel('), isTrue);
    });
  });
}

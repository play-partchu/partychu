// 반복 파티 상세의 '정기 일정' 줄 — **반복 규칙만** 말하고 개별 날짜는 풀지 않는다.
//
// 예전에는 상세에 '예정 일정'으로 실제 회차 날짜를 칩으로 전부 늘어놓았다
// (8월 22일 / 8월 23일 / 8월 24일 …). 상세는 "언제마다 열리는지"만 알려주고,
// 실제 참가 날짜와 차수는 '신청하기'를 눌러 열리는 신청 플로우의 달력에서만
// 고르는 것이 맞다.
//
// 그래서 여기서 보는 것은 셋이다.
//  1. 저장된 반복 설정에서 계산한 규칙 문구가 정확한가(매일 / 매주 화·목 …).
//  2. 회차가 아무리 많아도 줄 수가 늘지 않는가(= 날짜를 풀지 않는가).
//  3. 상세 화면 어디에도 개별 날짜 칩을 그리는 코드가 남아 있지 않은가.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/party_schedule.dart';

void main() {
  const slot20to22 = PartyWeeklySlot(
    enabled: true,
    startTime: TimeOfDay(hour: 20, minute: 0),
    endTime: TimeOfDay(hour: 22, minute: 0),
  );

  PartyWeeklySlot slot(int startHour, int endHour) => PartyWeeklySlot(
    enabled: true,
    startTime: TimeOfDay(hour: startHour, minute: 0),
    endTime: TimeOfDay(hour: endHour, minute: 0),
  );

  /// 켜진 요일과 시간대로 반복 설정을 만든다.
  PartyRecurringSchedule schedule(
    Map<String, PartyWeeklySlot> weekly, {
    DateTime? endDate,
  }) => PartyRecurringSchedule(
    startDate: DateTime(2026, 8, 1),
    endDate: endDate,
    weekly: weekly,
  );

  /// 파티 문서 형태 — 상세 화면이 읽는 것과 같은 경로를 탄다.
  Map<String, dynamic> partyDoc(PartyRecurringSchedule s) => {
    'scheduleType': 'recurring',
    'recurringSchedule': s.toMap(),
  };

  group('반복 규칙 문구', () {
    test('매일 반복', () {
      final s = schedule({for (final k in kPartyWeekdayKeys) k: slot20to22});
      expect(s.detailLines, ['매일 20:00~22:00']);
    });

    test('특정 요일 하나 — 매주 토요일', () {
      final s = schedule({'saturday': slot(19, 21)});
      expect(s.detailLines, ['매주 토요일 19:00~21:00']);
    });

    test('복수 요일 — 매주 화·목', () {
      final s = schedule({'tuesday': slot20to22, 'thursday': slot20to22});
      expect(s.detailLines, ['매주 화·목 20:00~22:00']);
    });

    test('복수 요일 — 매주 월·수·금', () {
      final s = schedule({
        'monday': slot(18, 20),
        'wednesday': slot(18, 20),
        'friday': slot(18, 20),
      });
      expect(s.detailLines, ['매주 월·수·금 18:00~20:00']);
    });

    test('주말 반복 — 뭉뚱그리지 않고 저장된 실제 요일로', () {
      final s = schedule({'saturday': slot(19, 21), 'sunday': slot(19, 21)});
      expect(s.detailLines, ['매주 토·일 19:00~21:00']);
    });

    test('평일 반복도 저장된 실제 요일로', () {
      final s = schedule({
        for (final k in kPartyWeekdayKeysWeekday) k: slot20to22,
      });
      expect(s.detailLines, ['매주 월·화·수·목·금 20:00~22:00']);
    });

    test('요일마다 시간이 다르면 시간대별로 한 줄씩', () {
      final s = schedule({
        for (final k in kPartyWeekdayKeysWeekday) k: slot(20, 22),
        for (final k in kPartyWeekdayKeysWeekend) k: slot(19, 23),
      });
      expect(s.detailLines, ['매주 월·화·수·목·금 20:00~22:00', '매주 토·일 19:00~23:00']);
    });

    test('종료일은 규칙 요약에만 붙는다 — 날짜를 나열하지 않는다', () {
      final s = schedule({
        'tuesday': slot20to22,
        'thursday': slot20to22,
      }, endDate: DateTime(2026, 9, 30));
      expect(s.detailLines, ['매주 화·목 20:00~22:00 · 9월 30일까지']);
    });

    test('켜진 요일이 없으면 아무 줄도 없다', () {
      expect(schedule(const {}).detailLines, isEmpty);
    });
  });

  group('개별 날짜를 풀지 않는다', () {
    test('매일 열려 회차가 수십 개여도 정기 일정은 한 줄이다', () {
      final s = schedule({for (final k in kPartyWeekdayKeys) k: slot20to22});
      final data = partyDoc(s);
      final now = DateTime(2026, 8, 22, 10);

      // 회차 계산은 그대로 살아 있다 — 신청 플로우의 달력이 이 목록을 쓴다.
      final occurrences = PartySchedule.selectableOccurrences(data, now: now);
      expect(occurrences.length, greaterThan(20), reason: '회차 생성 로직은 손대지 않았다');

      // 그런데 상세에 그리는 줄은 시간대 종류 수(1줄)뿐이다.
      final lines = PartySchedule.detailLines(data);
      expect(lines.length, 1);
      expect(lines.single, '매일 20:00~22:00');
    });

    test('규칙 문구에 개별 회차 날짜가 섞이지 않는다', () {
      final s = schedule({'tuesday': slot20to22, 'thursday': slot20to22});
      final data = partyDoc(s);
      final now = DateTime(2026, 8, 22, 10);

      final label = PartySchedule.detailLines(data).join('\n');
      for (final occ in PartySchedule.selectableOccurrences(data, now: now)) {
        expect(
          label.contains('${occ.start.month}월 ${occ.start.day}일'),
          isFalse,
          reason: '회차 날짜(${occ.id})가 규칙 문구에 나왔다: $label',
        );
      }
    });
  });

  group('단일 날짜 파티는 그대로', () {
    final single = <String, dynamic>{
      'startDateTime': DateTime(2026, 9, 5, 20).toIso8601String(),
    };

    test('반복 파티가 아니라 정기 일정 줄 자체가 없다', () {
      expect(PartySchedule.isRecurring(single), isFalse);
      expect(PartySchedule.detailLines(single), isEmpty);
    });

    test('실제 날짜·시간은 예전처럼 그대로 읽힌다', () {
      expect(PartySchedule.startAt(single), DateTime(2026, 9, 5, 20));
    });
  });

  group('상세 화면에 날짜 칩이 남아 있지 않다', () {
    final detail = File('lib/screens/party_detail_screen.dart');

    test('예정 일정 칩 위젯은 코드베이스에서 사라졌다', () {
      expect(
        File('lib/widgets/party_upcoming_schedule.dart').existsSync(),
        isFalse,
      );
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        expect(
          entity.readAsStringSync().contains('PartyUpcomingSchedule'),
          isFalse,
          reason: entity.path,
        );
      }
    });

    test('상세 화면은 회차 목록을 화면에 나열하지 않는다', () {
      final src = detail.readAsStringSync();
      // selectableOccurrences는 남아 있어야 한다 — 신청 달력과 버튼 활성 판정이
      // 쓰는 계산이다. 다만 그 결과를 위젯 목록으로 펼치는 자리는 없어야 한다.
      expect(src.contains('selectableOccurrences'), isTrue);
      for (final banned in ['PartyUpcomingSchedule', '예정 일정', '전체 일정 보기']) {
        expect(src.contains(banned), isFalse, reason: banned);
      }
    });
  });
}

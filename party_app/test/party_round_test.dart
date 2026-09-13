import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/models/party_early_bird.dart';
import 'package:party_app/models/party_early_bird_schedule.dart';
import 'package:party_app/models/party_round.dart';
import 'package:party_app/models/party_schedule.dart';

/// 2026-08-10은 월요일.
final _date = DateTime(2026, 8, 10);

PartyRound _round({
  TimeOfDay startTime = const TimeOfDay(hour: 21, minute: 0),
  TimeOfDay? endTime = const TimeOfDay(hour: 23, minute: 0),
  PartyRecruitDeadlineRule openRule = PartyRecruitDeadlineRule.noDeadline,
  PartyRecruitDeadlineRule closeRule = const PartyRecruitDeadlineRule(),
  int minCapacity = 0,
  int maxCapacity = 10,
  int maleFee = 20000,
  int femaleFee = 20000,
  PartyEarlyBird earlyBird = const PartyEarlyBird.off(),
}) => PartyRound(
  id: 'r1',
  startTime: startTime,
  endTime: endTime,
  openRule: openRule,
  closeRule: closeRule,
  minCapacity: minCapacity,
  maxCapacity: maxCapacity,
  maleFee: maleFee,
  femaleFee: femaleFee,
  earlyBird: earlyBird,
);

void main() {
  group('차수 일정 계산', () {
    test('시작·종료가 그 날짜에 붙는다', () {
      final w = _round().resolveOn(_date);
      expect(w.start, DateTime(2026, 8, 10, 21, 0));
      expect(w.end, DateTime(2026, 8, 10, 23, 0));
    });

    test('자정을 넘기는 차수는 종료가 다음 날로 넘어간다', () {
      final w = _round(
        startTime: const TimeOfDay(hour: 23, minute: 0),
        endTime: const TimeOfDay(hour: 2, minute: 0),
      ).resolveOn(_date);
      expect(w.start, DateTime(2026, 8, 10, 23, 0));
      expect(w.end, DateTime(2026, 8, 11, 2, 0));
    });

    test('모집 창구도 그 차수의 시작 시각을 기준으로 계산된다', () {
      final w = _round(
        openRule: const PartyRecruitDeadlineRule(
          mode: PartyDeadlineMode.prevDayTime,
          dayTime: TimeOfDay(hour: 20, minute: 0),
        ),
        closeRule: const PartyRecruitDeadlineRule(
          mode: PartyDeadlineMode.beforeStart,
          minutesBefore: 90,
        ),
      ).resolveOn(_date);
      expect(w.recruitOpenAt, DateTime(2026, 8, 9, 20, 0));
      expect(w.recruitCloseAt, DateTime(2026, 8, 10, 19, 30));
    });

    test('차수마다 모집 창구가 독립적으로 잡힌다', () {
      // 1차 19:00 시작 / 2차 22:00 시작 — 각자 자기 시작 1시간 전에 마감.
      const rule = PartyRecruitDeadlineRule(
        mode: PartyDeadlineMode.beforeStart,
        minutesBefore: 60,
      );
      final first = _round(
        startTime: const TimeOfDay(hour: 19, minute: 0),
        endTime: const TimeOfDay(hour: 21, minute: 30),
        closeRule: rule,
      ).resolveOn(_date);
      final second = _round(
        startTime: const TimeOfDay(hour: 22, minute: 0),
        endTime: const TimeOfDay(hour: 1, minute: 0),
        closeRule: rule,
      ).resolveOn(_date);
      expect(first.recruitCloseAt, DateTime(2026, 8, 10, 18, 0));
      expect(second.recruitCloseAt, DateTime(2026, 8, 10, 21, 0));
      expect(second.end, DateTime(2026, 8, 11, 1, 0));
    });
  });

  group('차수 상태', () {
    final window = _round(
      openRule: const PartyRecruitDeadlineRule(
        mode: PartyDeadlineMode.prevDayTime,
        dayTime: TimeOfDay(hour: 20, minute: 0),
      ),
      closeRule: const PartyRecruitDeadlineRule(
        mode: PartyDeadlineMode.beforeStart,
        minutesBefore: 60,
      ),
    ).resolveOn(_date);

    test('모집 시작 전 → 모집 예정', () {
      expect(
        window.statusAt(DateTime(2026, 8, 9, 19, 0)),
        PartyRoundStatus.upcoming,
      );
    });

    test('모집 창구 안 → 모집 중', () {
      expect(
        window.statusAt(DateTime(2026, 8, 10, 12, 0)),
        PartyRoundStatus.open,
      );
    });

    test('마감 뒤 시작 전 → 모집 마감', () {
      expect(
        window.statusAt(DateTime(2026, 8, 10, 20, 30)),
        PartyRoundStatus.closed,
      );
    });

    test('시작 뒤 종료 전 → 진행 중', () {
      expect(
        window.statusAt(DateTime(2026, 8, 10, 22, 0)),
        PartyRoundStatus.ongoing,
      );
    });

    test('종료 뒤 → 종료', () {
      expect(
        window.statusAt(DateTime(2026, 8, 11, 0, 0)),
        PartyRoundStatus.ended,
      );
    });

    test('마감을 안 잡으면 시작 시각까지 모집한다', () {
      final w = _round(
        closeRule: PartyRecruitDeadlineRule.noDeadline,
      ).resolveOn(_date);
      expect(w.isRecruitingAt(DateTime(2026, 8, 10, 20, 59)), isTrue);
      expect(w.isRecruitingAt(DateTime(2026, 8, 10, 21, 0)), isFalse);
    });

    test('시작 후 모집을 허용하면 그 사실을 알린다', () {
      final w = _round(
        closeRule: PartyRecruitDeadlineRule(
          mode: PartyDeadlineMode.customDateTime,
          customAt: DateTime(2026, 8, 10, 22, 0),
        ),
      ).resolveOn(_date);
      expect(w.acceptsAfterStart, isTrue);
      // 시작 뒤여도 마감 전이면 여전히 '모집 중'이다.
      expect(w.statusAt(DateTime(2026, 8, 10, 21, 30)), PartyRoundStatus.open);
    });
  });

  group('검증', () {
    List<PartyRoundIssue> issuesOf(PartyRound r, {bool perRound = true}) =>
        r.validate(
          roundNumber: 2,
          perRound: perRound,
          separateGender: false,
          partyDate: _date,
          isFree: false,
        );

    test('문제가 없으면 빈 목록', () {
      expect(issuesOf(_round()), isEmpty);
    });

    test('종료 시간을 안 고르면 잡아낸다', () {
      final issues = issuesOf(_round(endTime: null));
      expect(issues.any((e) => e.field == PartyRoundField.schedule), isTrue);
    });

    test('모집 시작이 모집 마감보다 늦으면 잡아낸다', () {
      final issues = issuesOf(
        _round(
          // 모집 시작 = 시작 30분 전, 모집 마감 = 시작 2시간 전 → 순서가 뒤집힘.
          openRule: const PartyRecruitDeadlineRule(
            mode: PartyDeadlineMode.beforeStart,
            minutesBefore: 30,
          ),
          closeRule: const PartyRecruitDeadlineRule(
            mode: PartyDeadlineMode.beforeStart,
            minutesBefore: 120,
          ),
        ),
      );
      expect(issues.any((e) => e.field == PartyRoundField.recruit), isTrue);
    });

    test('모집 마감이 파티 종료 뒤면 잡아낸다', () {
      final issues = issuesOf(
        _round(
          closeRule: PartyRecruitDeadlineRule(
            mode: PartyDeadlineMode.customDateTime,
            // 23:00 종료인데 다음 날 새벽으로 잡았다.
            customAt: DateTime(2026, 8, 11, 2, 0),
          ),
        ),
      );
      // resolve()가 종료로 당겨주므로 '종료 뒤'로는 저장되지 않지만,
      // 시작 이후 마감이라는 사실 자체는 상태/안내로 드러난다.
      expect(issues.where((e) => e.field == PartyRoundField.recruit), isEmpty);
      final w = _round(
        closeRule: PartyRecruitDeadlineRule(
          mode: PartyDeadlineMode.customDateTime,
          customAt: DateTime(2026, 8, 11, 2, 0),
        ),
      ).resolveOn(_date);
      expect(w.recruitCloseAt, w.end);
    });

    test('차수 최소 인원이 최대를 넘으면 잡아낸다', () {
      final issues = issuesOf(
        PartyRound(
          id: 'r1',
          endTime: const TimeOfDay(hour: 23, minute: 0),
          minCapacity: 12,
          maxCapacity: 10,
          maleFee: 20000,
          femaleFee: 20000,
        ),
      );
      expect(issues.any((e) => e.field == PartyRoundField.capacity), isTrue);
    });

    test('차수 최소 인원이 최대와 같으면 통과', () {
      final issues = issuesOf(
        PartyRound(
          id: 'r1',
          endTime: const TimeOfDay(hour: 23, minute: 0),
          minCapacity: 10,
          maxCapacity: 10,
          maleFee: 20000,
          femaleFee: 20000,
        ),
      );
      expect(issues, isEmpty);
    });

    test('정원이 비면 잡아내고, 통합 모드에서는 검사하지 않는다', () {
      final empty = _round(maxCapacity: 0);
      expect(
        issuesOf(empty).any((e) => e.field == PartyRoundField.capacity),
        isTrue,
      );
      expect(
        issuesOf(
          empty,
          perRound: false,
        ).any((e) => e.field == PartyRoundField.capacity),
        isFalse,
      );
    });

    test('참가비가 1,000원 단위가 아니면 잡아낸다', () {
      final issues = issuesOf(_round(maleFee: 15500));
      expect(issues.any((e) => e.field == PartyRoundField.fee), isTrue);
    });
  });

  group('1차 설정 복사', () {
    test('시간·가격·인원·모집 규칙·얼리버드를 그대로 가져오고 id/이름은 지킨다', () {
      final source = _round(
        startTime: const TimeOfDay(hour: 19, minute: 0),
        endTime: const TimeOfDay(hour: 21, minute: 0),
        minCapacity: 6,
        maxCapacity: 12,
        maleFee: 30000,
        femaleFee: 25000,
        closeRule: const PartyRecruitDeadlineRule(
          mode: PartyDeadlineMode.prevDayTime,
          dayTime: TimeOfDay(hour: 18, minute: 0),
        ),
      );
      final target = PartyRound(id: 'r2', label: '2차');
      final copied = target.copyingSettingsFrom(source);

      expect(copied.id, 'r2');
      expect(copied.label, '2차');
      expect(copied.startTime, const TimeOfDay(hour: 19, minute: 0));
      expect(copied.minCapacity, 6);
      expect(copied.maxCapacity, 12);
      expect(copied.maleFee, 30000);
      expect(copied.femaleFee, 25000);
      expect(copied.closeRule.mode, PartyDeadlineMode.prevDayTime);
    });
  });

  group('직렬화', () {
    test('문서 맵에는 절대 시각과 규칙이 함께 들어간다', () {
      final round = _round(
        openRule: const PartyRecruitDeadlineRule(
          mode: PartyDeadlineMode.beforeStart,
          minutesBefore: 3 * 24 * 60,
        ),
        closeRule: const PartyRecruitDeadlineRule(
          mode: PartyDeadlineMode.beforeStart,
          minutesBefore: 90,
        ),
      );
      final map = round.toMap(roundNumber: 2, partyDate: _date, perRound: true);

      expect(map['roundNumber'], 2);
      expect(map['label'], '2차');
      expect(map['startTime'], '21:00');
      expect(map['endTime'], '23:00');
      expect(map['maxCapacity'], 10);
      expect(map['minCapacity'], 0);
      expect((map['recruitOpenRule'] as Map)['mode'], 'beforeStart');
      expect((map['recruitCloseRule'] as Map)['minutes'], 90);

      // 절대 시각도 함께(서버·목록이 그대로 읽는다).
      expect(map['time'], isNotNull);
      expect(map['recruitCloseAt'], isNotNull);
    });

    test('통합 정원 모드에서는 정원·참가비를 문서에 넣지 않는다', () {
      final map = _round().toMap(
        roundNumber: 2,
        partyDate: _date,
        perRound: false,
      );
      expect(map.containsKey('maxCapacity'), isFalse);
      expect(map.containsKey('maleFee'), isFalse);
      // 일정과 모집 창구는 통합 모드에서도 차수마다 따로다.
      expect(map['recruitCloseAt'], isNotNull);
    });

    test('문서 맵 → PartyRound 왕복', () {
      final round = _round(
        earlyBird: const PartyEarlyBird(
          enabled: true,
          percent: 15,
          endType: PartyEarlyBirdEndType.beforeStart,
          beforeStartRule: PartyEarlyBirdDeadlineRule(
            mode: EarlyBirdDeadlineMode.hoursBefore,
            hours: 6,
          ),
        ),
      );
      final back = PartyRound.fromMap(
        round.toMap(roundNumber: 2, partyDate: _date, perRound: true),
      )!;

      expect(back.startTime, round.startTime);
      expect(back.endTime, round.endTime);
      expect(back.closeRule, round.closeRule);
      expect(back.maxCapacity, round.maxCapacity);
      expect(back.maleFee, round.maleFee);
      expect(back.earlyBird.enabled, isTrue);
      expect(back.earlyBird.percent, 15);
    });

    test('임시저장 맵 → PartyRound 왕복', () {
      final round = _round(
        openRule: const PartyRecruitDeadlineRule(
          mode: PartyDeadlineMode.startDayTime,
          dayTime: TimeOfDay(hour: 10, minute: 0),
        ),
      );
      final back = PartyRound.fromMap(round.toDraftMap())!;
      expect(back.openRule, round.openRule);
      expect(back.closeRule, round.closeRule);
      expect(back.startTime, round.startTime);
      expect(back.maleFee, round.maleFee);
    });

    test('차수별 마감이 없던 예전 문서도 읽힌다', () {
      // 'time'(Timestamp) 하나만 있던 시절의 원소.
      final back = PartyRound.fromMap({
        'roundNumber': 2,
        'label': '2차',
        'time': Timestamp.fromDate(DateTime(2026, 8, 10, 22, 0)),
        'maxCapacity': 8,
        'maleFee': 10000,
        'femaleFee': 10000,
      })!;
      expect(back.startTime, const TimeOfDay(hour: 22, minute: 0));
      expect(back.maxCapacity, 8);
      // 창구 정보가 없으니 "제한 없음"으로 되살린다.
      expect(back.openRule.isNone, isTrue);
      expect(back.closeRule.isNone, isTrue);
    });
  });
}

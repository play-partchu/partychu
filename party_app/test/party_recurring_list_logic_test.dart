import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/widgets/party_card_widget.dart';

/// 목록/카드/마감 로직이 정기 파티에서도 올바르게 동작하는지 — 화면들이
/// 공통으로 거쳐가는 PartyCard의 정적 헬퍼를 직접 검증한다.
///
/// **모든 검증은 고정된 기준 시각([kNow])을 넘겨서 한다.** 예전에는 실제
/// 현재 시각을 썼는데, 그러면 "매일 19:00~22:00 파티가 모집중인가" 같은
/// 검증이 테스트를 돌리는 시각에 따라 뒤집혔다(저녁에 돌리면 오늘 회차가
/// 이미 시작해 모집마감). 기준 시각을 정기 파티 시작 전인 **오전 9시**로
/// 고정해 언제 실행해도 결과가 같게 만든다.
void main() {
  /// 모든 테스트가 공유하는 기준 시각 — 2026-08-01 오전 9:00.
  final kNow = DateTime(2026, 8, 1, 9, 0);

  DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  PartyRecurringSchedule everyDay({
    required TimeOfDay start,
    required TimeOfDay end,
    DateTime? startDate,
    DateTime? endDate,
    PartyRecruitDeadlineRule deadline = const PartyRecruitDeadlineRule(
      mode: PartyDeadlineMode.none,
    ),
  }) {
    return PartyRecurringSchedule(
      startDate: startDate ?? dayOf(kNow).subtract(const Duration(days: 7)),
      endDate: endDate,
      weekly: {
        for (final k in kPartyWeekdayKeys)
          k: PartyWeeklySlot(enabled: true, startTime: start, endTime: end),
      },
      deadlineRule: deadline,
    );
  }

  Map<String, dynamic> docOf(PartyRecurringSchedule s) => {
    'title': '매주 열리는 파티',
    'recruitStatus': '모집중',
    'scheduleType': 'recurring',
    'recurringSchedule': s.toMap(),
    // 등록 시점의 첫 회차가 캐시로 남아 있어도(=오래된 값) 계산 결과가
    // 그 값에 끌려가지 않아야 한다.
    'partyDateTime': Timestamp.fromDate(
      kNow.subtract(const Duration(days: 30)),
    ),
  };

  test('정기 파티는 저장된 오래된 partyDateTime 대신 다음 회차를 쓴다', () {
    final data = docOf(
      everyDay(
        start: const TimeOfDay(hour: 23, minute: 0),
        end: const TimeOfDay(hour: 23, minute: 59),
      ),
    );
    final dt = PartyCard.parsePartyDateTime(data, now: kNow)!;
    // 오래된 캐시(30일 전)가 아니라 기준 시각 이후의 회차여야 한다.
    expect(dt.isAfter(kNow), isTrue);
    expect(dt.hour, 23);
    // 기준 시각이 오전이므로 다음 회차는 "오늘 밤".
    expect(dayOf(dt), dayOf(kNow));
  });

  test('정기 파티는 회차가 남아 있는 한 목록에 계속 보인다', () {
    final data = docOf(
      everyDay(
        start: const TimeOfDay(hour: 19, minute: 0),
        end: const TimeOfDay(hour: 22, minute: 0),
      ),
    );
    expect(PartyCard.isVisibleInList(data, now: kNow), isTrue);
    expect(PartyCard.effectiveStatus(data, now: kNow), '모집중');
  });

  test('오늘 회차가 이미 끝난 밤이라도 내일 회차가 있으면 목록에 남는다', () {
    // 기준 시각을 같은 날 23:30으로 옮긴다 — 19:00~22:00 회차는 끝났지만
    // 매일 열리는 파티라 다음 회차(내일 19:00)가 남아 있다. 예전 테스트가
    // 저녁에만 깨졌던 바로 그 경계를 명시적으로 고정해둔다.
    final lateNight = DateTime(2026, 8, 1, 23, 30);
    final data = docOf(
      everyDay(
        start: const TimeOfDay(hour: 19, minute: 0),
        end: const TimeOfDay(hour: 22, minute: 0),
      ),
    );
    final next = PartyCard.parsePartyDateTime(data, now: lateNight)!;
    expect(dayOf(next), dayOf(lateNight).add(const Duration(days: 1)));
    expect(PartyCard.isVisibleInList(data, now: lateNight), isTrue);
    expect(PartyCard.effectiveStatus(data, now: lateNight), '모집중');
  });

  test('운영 종료일이 지난 정기 파티는 목록에서 내려가고 모집마감이 된다', () {
    final yesterday = dayOf(kNow).subtract(const Duration(days: 1));
    final data = docOf(
      everyDay(
        start: const TimeOfDay(hour: 19, minute: 0),
        end: const TimeOfDay(hour: 22, minute: 0),
        startDate: yesterday.subtract(const Duration(days: 30)),
        endDate: yesterday,
      ),
    );
    expect(PartyCard.parsePartyDateTime(data, now: kNow), isNull);
    expect(PartyCard.isVisibleInList(data, now: kNow), isFalse);
    expect(PartyCard.effectiveStatus(data, now: kNow), '모집마감');
  });

  test('정기 파티의 마감 시각은 다음 회차 기준으로 계산된다', () {
    final data = docOf(
      everyDay(
        start: const TimeOfDay(hour: 23, minute: 0),
        end: const TimeOfDay(hour: 23, minute: 59),
        deadline: const PartyRecruitDeadlineRule(
          mode: PartyDeadlineMode.beforeStart,
          minutesBefore: 60,
        ),
      ),
    );
    final start = PartyCard.parsePartyDateTime(data, now: kNow)!;
    final deadline = PartyCard.recruitDeadlineAt(data, now: kNow)!;
    expect(deadline, start.subtract(const Duration(hours: 1)));
  });

  test('호스트가 상태를 직접 바꾸면 그 값이 우선한다', () {
    final data = docOf(
      everyDay(
        start: const TimeOfDay(hour: 19, minute: 0),
        end: const TimeOfDay(hour: 22, minute: 0),
      ),
    )..['recruitStatus'] = '모집완료';
    expect(PartyCard.effectiveStatus(data, now: kNow), '모집완료');
  });

  group('기존 일회성 파티(회귀 방지)', () {
    test('지난 파티는 그대로 목록에서 빠진다', () {
      final data = {
        'recruitStatus': '모집중',
        'partyDateTime': Timestamp.fromDate(
          kNow.subtract(const Duration(days: 2)),
        ),
      };
      expect(PartyCard.isVisibleInList(data, now: kNow), isFalse);
      expect(PartyCard.effectiveStatus(data, now: kNow), '모집마감');
    });

    test('앞으로 열릴 파티는 그대로 보이고 마감 시각도 저장값을 쓴다', () {
      final start = kNow.add(const Duration(days: 2));
      final deadline = start.subtract(const Duration(hours: 3));
      final data = {
        'recruitStatus': '모집중',
        'scheduleType': 'single',
        'partyDateTime': Timestamp.fromDate(start),
        'recruitDeadlineAt': Timestamp.fromDate(deadline),
      };
      expect(PartyCard.isVisibleInList(data, now: kNow), isTrue);
      expect(PartyCard.effectiveStatus(data, now: kNow), '모집중');
      expect(
        PartyCard.recruitDeadlineAt(data, now: kNow)!.millisecondsSinceEpoch,
        deadline.millisecondsSinceEpoch,
      );
    });

    test('일정 필드가 아예 없는 옛 문서도 죽지 않는다', () {
      expect(PartyCard.parsePartyDateTime({}, now: kNow), isNull);
      expect(PartyCard.isVisibleInList({}, now: kNow), isTrue);
      expect(PartyCard.recruitDeadlineAt({}, now: kNow), isNull);
    });
  });
}

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/day_time_match.dart';
import 'package:party_app/models/place_event_time.dart';
import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/models/place_weekly_hours.dart';

/// 매장 이벤트의 **날짜·시간 판정 계약**.
///
/// 이 판정이 틀리면 화면에서는 "이벤트가 원래 없는 것"처럼 보인다 — 사라진
/// 것인지 없는 것인지 눈으로 구분할 수 없으므로 여기서 못 박는다.

/// 이벤트 하나 — **저장된 문서에서 읽는 경로 그대로** 만든다.
/// 생성자를 직접 부르면 파싱 단계를 건너뛰어, 실제로는 안 읽히는 값으로도
/// 테스트가 통과해 버린다.
PlacePromotion promo({
  bool isAlways = false,
  DateTime? startAt,
  DateTime? endAt,
  List<int> weekdays = const [],
  String? startTime,
  String? endTime,
}) => PlacePromotion.fromMap('p1', {
  'placeId': 'place1',
  'placeCollection': 'events',
  'hostId': 'host1',
  'title': '테스트 이벤트',
  'isAlways': isAlways,
  if (startAt != null) 'startAt': startAt,
  if (endAt != null) 'endAt': endAt,
  'weekdays': weekdays,
  if (startTime != null) 'startTime': startTime,
  if (endTime != null) 'endTime': endTime,
});

/// 18:00~02:00 영업하는 매장(매일).
PlaceWeeklyHours nightHours() => PlaceWeeklyHours.fromMap({
  for (final d in PlaceWeeklyHours.weekdays)
    d: {'open': '18:00', 'close': '02:00', 'isClosed': false},
});

void main() {
  group('영업중(전시간) — 시간을 둘 다 안 정한 상태가 곧 그 뜻이다', () {
    test('시간을 안 적으면 영업중(전시간)이다', () {
      expect(PlaceEventTime.isBusinessHours(promo()), isTrue);
      expect(
        PlaceEventTime.timeLabelOf(promo()),
        PlaceEventTime.businessHoursLabel,
      );
    });

    test('시간을 적으면 그 시간이 문구가 된다', () {
      final p = promo(startTime: '22:00', endTime: '02:00');
      expect(PlaceEventTime.isBusinessHours(p), isFalse);
      expect(PlaceEventTime.timeLabelOf(p), '22:00 ~ 02:00');
    });

    test('24시간 영업이라는 뜻이 아니다 — 매장 영업시간을 그대로 따른다', () {
      final p = promo();
      final hours = nightHours(); // 18:00 ~ 02:00
      // 영업 중인 23:00에는 걸린다.
      expect(
        PlaceEventTime.matchesTime(
          p,
          start: const TimeOfDay(hour: 23, minute: 0),
          end: null,
          hours: hours,
        ),
        isTrue,
      );
      // 문을 닫은 15:00에는 안 걸린다 — 여기서 통과하면 '24시간'이 돼 버린다.
      expect(
        PlaceEventTime.matchesTime(
          p,
          start: const TimeOfDay(hour: 15, minute: 0),
          end: null,
          hours: hours,
        ),
        isFalse,
      );
    });

    test('영업시간을 모르는 매장은 시간 조건이 걸리면 빠진다 — 추측하지 않는다', () {
      expect(
        PlaceEventTime.matchesTime(
          promo(),
          start: const TimeOfDay(hour: 23, minute: 0),
          end: null,
          hours: null,
        ),
        isFalse,
      );
    });

    test('시간 조건이 없으면 영업시간을 몰라도 그대로 보인다', () {
      expect(
        PlaceEventTime.matchesTime(promo(), start: null, end: null),
        isTrue,
      );
    });
  });

  group('시간 검색 — 그 시각에 적용 중인 이벤트만', () {
    final a = promo(startTime: '18:00', endTime: '21:00');
    final b = promo(startTime: '22:00', endTime: '02:00');

    test('23:00 검색 → B만 걸린다', () {
      const at23 = TimeOfDay(hour: 23, minute: 0);
      expect(PlaceEventTime.matchesTime(a, start: at23, end: null), isFalse);
      expect(PlaceEventTime.matchesTime(b, start: at23, end: null), isTrue);
    });

    test('19:00 검색 → A만 걸린다', () {
      const at19 = TimeOfDay(hour: 19, minute: 0);
      expect(PlaceEventTime.matchesTime(a, start: at19, end: null), isTrue);
      expect(PlaceEventTime.matchesTime(b, start: at19, end: null), isFalse);
    });

    test('자정 넘김 — 22:00~02:00은 다음 날 01:00에도 적용 중이다', () {
      const at1 = TimeOfDay(hour: 1, minute: 0);
      expect(PlaceEventTime.matchesTime(b, start: at1, end: null), isTrue);
      // 02:00에는 이미 끝났다(끝은 열린 구간).
      expect(
        PlaceEventTime.matchesTime(
          b,
          start: const TimeOfDay(hour: 2, minute: 0),
          end: null,
        ),
        isFalse,
      );
    });

    test('구간 검색은 겹치기만 하면 걸린다 — 통째로 들어갈 필요는 없다', () {
      // 20:00~23:00 구간은 A(18~21)와도 B(22~02)와도 겹친다.
      const from = TimeOfDay(hour: 20, minute: 0);
      const to = TimeOfDay(hour: 23, minute: 0);
      expect(PlaceEventTime.matchesTime(a, start: from, end: to), isTrue);
      expect(PlaceEventTime.matchesTime(b, start: from, end: to), isTrue);
    });

    test('자정을 넘긴 구간 검색(23:00~03:00)도 B를 잡는다', () {
      expect(
        PlaceEventTime.matchesTime(
          b,
          start: const TimeOfDay(hour: 23, minute: 0),
          end: const TimeOfDay(hour: 3, minute: 0),
        ),
        isTrue,
      );
      expect(
        PlaceEventTime.matchesTime(
          a,
          start: const TimeOfDay(hour: 23, minute: 0),
          end: const TimeOfDay(hour: 3, minute: 0),
        ),
        isFalse,
      );
    });
  });

  group('날짜 검색 — 실제 진행 중인 날짜 기준', () {
    final p = promo(
      startAt: DateTime(2026, 9, 1),
      endAt: DateTime(2026, 9, 10),
    );

    test('기간 안(9/5)에는 걸리고 기간 밖(9/15)에는 안 걸린다', () {
      expect(PlaceEventTime.runsOn(p, DateTime(2026, 9, 5)), isTrue);
      expect(PlaceEventTime.runsOn(p, DateTime(2026, 9, 15)), isFalse);
    });

    test('시작일·종료일은 양끝을 포함한다', () {
      expect(PlaceEventTime.runsOn(p, DateTime(2026, 9, 1)), isTrue);
      expect(PlaceEventTime.runsOn(p, DateTime(2026, 9, 10, 23, 59)), isTrue);
      expect(PlaceEventTime.runsOn(p, DateTime(2026, 8, 31)), isFalse);
    });

    test('여러 날을 고르면 하루라도 진행 중이면 통과다', () {
      expect(
        PlaceEventTime.matchesDates(p, [
          DateTime(2026, 9, 15),
          DateTime(2026, 9, 5),
        ]),
        isTrue,
      );
      expect(
        PlaceEventTime.matchesDates(p, [
          DateTime(2026, 9, 15),
          DateTime(2026, 9, 20),
        ]),
        isFalse,
      );
    });

    test('진행 요일을 정했으면 그 요일만 걸린다', () {
      // 2026-09-04는 금요일, 09-05는 토요일.
      final friOnly = promo(weekdays: [DateTime.friday]);
      expect(PlaceEventTime.runsOn(friOnly, DateTime(2026, 9, 4)), isTrue);
      expect(PlaceEventTime.runsOn(friOnly, DateTime(2026, 9, 5)), isFalse);
    });

    test('날짜를 안 고르면 날짜로는 거르지 않는다', () {
      expect(PlaceEventTime.matchesDates(p, const []), isTrue);
    });
  });

  group('날짜 + 시간 동시 검색 — 두 조건을 함께 만족해야 한다', () {
    final p = promo(
      startAt: DateTime(2026, 9, 1),
      endAt: DateTime(2026, 9, 10),
      startTime: '22:00',
      endTime: '02:00',
    );

    test('기간 안 + 적용 시각 → 걸린다', () {
      expect(
        PlaceEventTime.matches(
          p,
          dates: [DateTime(2026, 9, 5)],
          start: const TimeOfDay(hour: 23, minute: 0),
        ),
        isTrue,
      );
    });

    test('기간 안이지만 시간이 안 맞으면 빠진다', () {
      expect(
        PlaceEventTime.matches(
          p,
          dates: [DateTime(2026, 9, 5)],
          start: const TimeOfDay(hour: 19, minute: 0),
        ),
        isFalse,
      );
    });

    test('시간은 맞지만 기간 밖이면 빠진다', () {
      expect(
        PlaceEventTime.matches(
          p,
          dates: [DateTime(2026, 9, 15)],
          start: const TimeOfDay(hour: 23, minute: 0),
        ),
        isFalse,
      );
    });

    test('영업중(전시간) 이벤트는 고른 날짜의 영업시간으로 판정한다', () {
      final always = promo(
        startAt: DateTime(2026, 9, 1),
        endAt: DateTime(2026, 9, 10),
      );
      final hours = nightHours(); // 18:00 ~ 02:00
      expect(
        PlaceEventTime.matches(
          always,
          dates: [DateTime(2026, 9, 5)],
          start: const TimeOfDay(hour: 23, minute: 0),
          hours: hours,
        ),
        isTrue,
      );
      expect(
        PlaceEventTime.matches(
          always,
          dates: [DateTime(2026, 9, 5)],
          start: const TimeOfDay(hour: 15, minute: 0),
          hours: hours,
        ),
        isFalse,
      );
    });
  });

  group('기존 데이터 하위호환', () {
    test('옛 상시 진행 이벤트는 어느 날짜에도 진행 중이다', () {
      final always = promo(isAlways: true);
      expect(PlaceEventTime.runsOn(always, DateTime(2026, 1, 1)), isTrue);
      expect(PlaceEventTime.runsOn(always, DateTime(2030, 12, 31)), isTrue);
    });

    test('상시 진행이어도 진행 요일은 그대로 걸린다', () {
      final friAlways = promo(isAlways: true, weekdays: [DateTime.friday]);
      expect(PlaceEventTime.runsOn(friAlways, DateTime(2026, 9, 4)), isTrue);
      expect(PlaceEventTime.runsOn(friAlways, DateTime(2026, 9, 5)), isFalse);
    });

    test('시간을 안 적어 둔 옛 이벤트가 영업중(전시간)으로 읽힌다', () {
      // 마이그레이션 없이 뜻이 생긴다 — 이것이 새 필드를 안 만든 이유다.
      final legacy = promo(isAlways: true);
      expect(PlaceEventTime.isBusinessHours(legacy), isTrue);
      expect(
        PlaceEventTime.matchesTime(
          legacy,
          start: const TimeOfDay(hour: 23, minute: 0),
          end: null,
          hours: nightHours(),
        ),
        isTrue,
      );
    });

    test('한쪽 시간만 적은 옛 이벤트도 판정된다', () {
      final fromOnly = promo(startTime: '22:00');
      expect(
        PlaceEventTime.matchesTime(
          fromOnly,
          start: const TimeOfDay(hour: 23, minute: 0),
          end: null,
        ),
        isTrue,
      );
      final toOnly = promo(endTime: '02:00');
      expect(
        PlaceEventTime.matchesTime(
          toOnly,
          start: const TimeOfDay(hour: 1, minute: 0),
          end: null,
        ),
        isTrue,
      );
    });

    test('형식이 아닌 옛 문자열은 시간으로 추측하지 않는다', () {
      // '밤 10시부터' 같은 자유기재는 구간을 만들 수 없다 → 시간 조건이
      // 걸리면 빠진다. 임의의 시각으로 넘겨짚어 결과에 끼워 넣지 않는다.
      final garbage = promo(startTime: '밤 10시부터');
      expect(PlaceEventTime.intervalsOf(garbage), isEmpty);
      expect(
        PlaceEventTime.matchesTime(
          garbage,
          start: const TimeOfDay(hour: 22, minute: 0),
          end: null,
        ),
        isFalse,
      );
      // 그래도 시간 조건이 없으면 목록에는 그대로 보인다.
      expect(
        PlaceEventTime.matchesTime(garbage, start: null, end: null),
        isTrue,
      );
    });
  });

  group('구간 좌표 — 자정 넘김은 1440을 넘는 값으로 표현된다', () {
    test('22:00~02:00 → 1320~1560', () {
      expect(DayInterval.fromHhmm('22:00', '02:00'), DayInterval(1320, 1560));
    });

    test('18:00~21:00 → 1080~1260', () {
      expect(DayInterval.fromHhmm('18:00', '21:00'), DayInterval(1080, 1260));
    });

    test('형식이 아니면 null', () {
      expect(DayInterval.fromHhmm('밤 10시', '02:00'), isNull);
      expect(DayInterval.parseHhmm('25:00'), isNull);
      expect(DayInterval.parseHhmm(''), isNull);
    });
  });
}

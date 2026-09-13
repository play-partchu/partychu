import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/day_time_match.dart';
import 'package:party_app/models/event_feed.dart';
import 'package:party_app/models/party_time_filter.dart';

/// 이벤트 탭의 날짜·시간 필터가 **줄째로 사라지지 않는지**, 그리고 파티 쪽
/// 판정이 그대로인지.
///
/// 화면 조립(main_screen)은 Firestore에 붙어 있어 위젯 테스트로 세우기 어렵다.
/// 대신 "무엇을 보여줄지 정하는 값"([EventFeedFilter])과 "판정 규칙"을 여기서
/// 못 박는다 — 줄이 사라지던 원인이 바로 이 값 하나였다.
void main() {
  group('이벤트 칸에서도 날짜·시간 줄은 남고, 인원만 빠진다', () {
    test('이벤트만 보는 칸은 파티를 안 보여준다 — 인원 버튼의 조건이 이 값이다', () {
      expect(EventFeedFilter.event.showsParties, isFalse);
      expect(EventFeedFilter.event.showsEvents, isTrue);
    });

    test('전체·파티 칸은 파티를 보여준다 — 인원 버튼이 그대로 선다', () {
      expect(EventFeedFilter.all.showsParties, isTrue);
      expect(EventFeedFilter.party.showsParties, isTrue);
    });

    test('세 칸 모두 이벤트 또는 파티 중 하나는 보여준다', () {
      // 어느 칸에서도 날짜·시간 줄이 뜻을 잃지 않는다는 뜻이다.
      for (final f in EventFeedFilter.values) {
        expect(
          f.showsParties || f.showsEvents,
          isTrue,
          reason: '${f.label} 칸이 아무것도 안 보여준다',
        );
      }
    });
  });

  group('파티 시간 판정 회귀 — 규칙을 공용으로 옮겼을 뿐이다', () {
    test('조건이 없으면 언제나 통과', () {
      expect(PartyTimeFilter.matches(const [], null, null), isTrue);
      expect(PartyTimeFilter.isActive(null, null), isFalse);
      expect(
        PartyTimeFilter.isActive(const TimeOfDay(hour: 9, minute: 0), null),
        isTrue,
      );
    });

    test('진행 시간을 못 읽은 파티는 조건이 걸리면 빠진다', () {
      expect(
        PartyTimeFilter.matches(
          const [],
          const TimeOfDay(hour: 19, minute: 0),
          null,
        ),
        isFalse,
      );
    });

    test('지정 시간 — 그 시각에 진행 중이면 걸린다', () {
      // 18:00~21:00 회차.
      const occ = [DayInterval(1080, 1260)];
      expect(
        PartyTimeFilter.matches(
          occ,
          const TimeOfDay(hour: 19, minute: 0),
          null,
        ),
        isTrue,
      );
      expect(
        PartyTimeFilter.matches(
          occ,
          const TimeOfDay(hour: 22, minute: 0),
          null,
        ),
        isFalse,
      );
    });

    test('지정 구간 — 겹치기만 하면 걸린다', () {
      const occ = [DayInterval(1080, 1260)]; // 18:00~21:00
      expect(
        PartyTimeFilter.matches(
          occ,
          const TimeOfDay(hour: 20, minute: 0),
          const TimeOfDay(hour: 23, minute: 0),
        ),
        isTrue,
      );
    });

    test('자정을 넘긴 파티 회차도 새벽 조건에 걸린다', () {
      const occ = [DayInterval(1320, 1560)]; // 22:00~02:00
      expect(
        PartyTimeFilter.matches(occ, const TimeOfDay(hour: 1, minute: 0), null),
        isTrue,
      );
    });

    test('여러 회차는 OR — 하나라도 맞으면 걸린다', () {
      const occs = [DayInterval(1080, 1260), DayInterval(1320, 1560)];
      expect(
        PartyTimeFilter.matches(
          occs,
          const TimeOfDay(hour: 23, minute: 0),
          null,
        ),
        isTrue,
      );
    });
  });

  group('파티와 이벤트가 같은 규칙을 쓴다', () {
    test('PartyTimeFilter.matches는 DayTimeMatch.matches와 같은 답을 낸다', () {
      const intervals = [DayInterval(1320, 1560)];
      for (final h in [0, 1, 2, 19, 22, 23]) {
        final t = TimeOfDay(hour: h, minute: 0);
        expect(
          PartyTimeFilter.matches(intervals, t, null),
          DayTimeMatch.matches(intervals, t, null),
          reason: '$h시에서 두 판정이 갈렸다',
        );
      }
    });
  });
}

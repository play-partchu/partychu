// 신청 플로우의 참가 회차 상태 — 상세 화면의 일정 표시와 **분리**됐는지 고정한다.
//
// 예전에는 상세 화면에 '참가 날짜' 선택 행이 있고, 거기서 고른 값이 그대로
// 신청 대상이 됐다. 그러면 '신청하기'를 눌러 들어간 플로우가 그 값 때문에 날짜
// 단계를 건너뛰거나, 반대로 상세에서 안 골랐으면 플로우에서 또 고르게 되어 같은
// 선택을 두 번 하는 화면이 됐다.
//
// 그래서 이 테스트가 보는 것은 셋이다.
//  1. 신청 대상은 플로우 안에서만 정해진다(상세에는 이 값을 만드는 길이 없다).
//  2. 플로우에 들어올 때마다 다시 묻는다 — 달력이 매번 정확히 한 번 뜬다.
//  3. 직전에 고른 날은 달력의 **초기값으로만** 되살아난다.

import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/apply_occurrence_state.dart';
import 'package:party_app/models/party_schedule.dart';

void main() {
  PartyOccurrence occ(int month, int day) => PartyOccurrence(
    start: DateTime(2026, month, day, 20),
    end: DateTime(2026, month, day, 23),
    deadline: DateTime(2026, month, day, 18),
  );

  /// 신청 플로우의 ② 단계가 달력을 띄우는 조건 — party_detail_screen의
  /// `if (isRecurring && _applyOccurrence.selected == null)`과 같은 식이다.
  bool asksForDate({
    required bool isRecurring,
    required ApplyOccurrenceState s,
  }) => isRecurring && s.selected == null;

  test('처음에는 신청 대상도 기억도 없다', () {
    final s = ApplyOccurrenceState();
    expect(s.selected, isNull);
    expect(s.calendarInitialId, isNull);
  });

  test('달력에서 고른 회차만 신청 대상이 된다', () {
    final s = ApplyOccurrenceState();
    final picked = occ(9, 5);
    s.select(picked);

    expect(s.selected, same(picked));
    expect(s.calendarInitialId, picked.id);
  });

  group('신청하기를 누를 때만 달력이 뜬다', () {
    test('반복 파티 — 흐름에 들어오면 아직 안 고른 상태라 달력을 묻는다', () {
      final s = ApplyOccurrenceState();
      s.beginFlow();
      expect(asksForDate(isRecurring: true, s: s), isTrue);
    });

    test('날짜를 고른 뒤에는 다시 묻지 않는다 — 날짜 → 차수가 한 번씩', () {
      final s = ApplyOccurrenceState();
      s.beginFlow();
      expect(asksForDate(isRecurring: true, s: s), isTrue);

      s.select(occ(9, 5));
      // ③ 차수 단계로 넘어가는 시점 — 날짜를 또 묻지 않는다.
      expect(asksForDate(isRecurring: true, s: s), isFalse);
    });

    test('신청을 마친 뒤 다시 들어와도 달력이 한 번 더 뜬다', () {
      final s = ApplyOccurrenceState();
      s.beginFlow();
      s.select(occ(9, 5));

      // 두 번째 '신청하기' — 지난번 선택이 남아 단계를 건너뛰면 안 된다.
      s.beginFlow();
      expect(s.selected, isNull);
      expect(asksForDate(isRecurring: true, s: s), isTrue);
    });

    test('단일 날짜 파티는 날짜 단계 자체가 없다', () {
      final s = ApplyOccurrenceState();
      s.beginFlow();
      // 회차가 없는 파티라 ②를 건너뛰고 곧바로 다음 단계로 간다.
      expect(asksForDate(isRecurring: false, s: s), isFalse);
    });
  });

  group('직전 선택은 표시 초기값으로만 남는다', () {
    test('차수에서 ←로 돌아오면 대상은 비고 달력은 그날을 켜 둔다', () {
      final s = ApplyOccurrenceState();
      s.beginFlow();
      s.select(occ(9, 12));

      s.clear(); // ③에서 ←
      expect(s.selected, isNull, reason: '신청 대상은 비워야 다시 묻는다');
      expect(s.calendarInitialId, occ(9, 12).id, reason: '달력은 그날을 켜 둔다');
    });

    test('흐름을 새로 시작해도 기억은 남고 신청 대상은 아니다', () {
      final s = ApplyOccurrenceState();
      s.beginFlow();
      s.select(occ(9, 12));

      s.beginFlow();
      expect(s.selected, isNull);
      expect(s.calendarInitialId, occ(9, 12).id);
    });

    test('다른 날로 바꾸면 기억도 그 날로 옮겨간다', () {
      final s = ApplyOccurrenceState();
      s.select(occ(9, 5));
      s.select(occ(9, 19));

      expect(s.calendarInitialId, occ(9, 19).id);
      s.clear();
      expect(s.calendarInitialId, occ(9, 19).id);
    });
  });
}

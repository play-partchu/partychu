import 'package:flutter/material.dart' show TimeOfDay;

/// 하루 안의 **구간 겹침 판정** — 파티와 매장 이벤트가 함께 쓰는 순수 계산.
///
/// ## 왜 따로 꺼냈는가
///
/// 이 계산은 원래 [PartyTimeFilter] 안에 있었다. 매장 이벤트에도 똑같은 판정이
/// 필요해졌는데(22:00~02:00 이벤트가 23:00 검색에 걸려야 한다), 같은 규칙을 두
/// 번 적으면 한쪽만 고쳐져 "파티는 걸리는데 이벤트는 안 걸리는" 시각이 생긴다.
/// 그래서 **자정을 넘기는 구간을 어떻게 볼 것인가**라는 규칙 하나만 여기 두고,
/// 파티도 이벤트도 각자 자기 데이터에서 구간을 만들어 이 함수에 넘긴다.
///
/// 파티 쪽 동작은 **한 줄도 바뀌지 않았다** — [PartyTimeFilter.matches]가 그대로
/// 이 함수를 부른다(옮기기만 했다).
///
/// ## 좌표계
///
/// 구간은 **자정 기준 분(minute)**이다. 자정을 넘기면 [DayInterval.to]가 1440을
/// 넘는다(22:00~02:00 → 1320~1560). 장소대여 판정([PlaceAvailability])·서버가
/// 이미 쓰는 좌표계와 같다.
///
/// ## 두 가지 물음
///
/// - **지정 시간**(시작만 고름) → 그 시각에 **진행 중인가**.
/// - **지정 구간**(둘 다 고름) → 그 구간과 **겹치는가**.
///   구간 안에 통째로 들어와야 하는 것이 아니다.
class DayTimeMatch {
  DayTimeMatch._();

  static const int minutesPerDay = 1440;

  /// 하루는 돌아온다 — 구간을 하루 앞뒤로도 밀어 보며 견준다.
  ///
  /// 이 한 줄이 자정 넘김 판정의 전부다. 22:00~02:00 이벤트는 1320~1560으로
  /// 들어오는데, 사용자가 01:00(60분)을 물으면 그대로는 안 걸린다. 구간을
  /// +1440 민 -120~120 위에서 보면 60이 그 안에 들어온다 — 즉 "어제 밤에 시작한
  /// 그 이벤트가 지금도 진행 중"이라는 뜻이다.
  static const List<int> _shifts = [-minutesPerDay, 0, minutesPerDay];

  static int minutesOf(TimeOfDay t) => t.hour * 60 + t.minute;

  /// 시간 조건이 걸려 있는지 — 한쪽만 골라도 조건이다.
  static bool isActive(TimeOfDay? start, TimeOfDay? end) =>
      start != null || end != null;

  /// [intervals] 중 **하나라도** 조건에 걸리면 true(구간이 여럿이면 OR).
  ///
  /// 조건이 없으면 언제나 true다. 구간을 하나도 만들지 못했으면(진행 시간을
  /// 읽을 수 없는 문서) 조건이 걸린 동안 빠진다 — 모르는 것을 아는 척해서
  /// 결과에 끼워 넣지 않는다는 뜻이고, 파티가 예전부터 하던 태도 그대로다.
  static bool matches(
    List<DayInterval> intervals,
    TimeOfDay? start,
    TimeOfDay? end,
  ) {
    if (!isActive(start, end)) return true;
    if (intervals.isEmpty) return false;

    // 지정 시간 — 시작만 고른 경우.
    if (start != null && end == null) {
      final t = minutesOf(start);
      return intervals.any((i) => containsCyclic(i, t));
    }

    // 지정 구간 — 끝만 고른 경우는 '자정부터 그 시각까지'로 본다.
    final from = start == null ? 0 : minutesOf(start);
    var to = minutesOf(end!);
    if (to <= from) to += minutesPerDay; // 자정을 넘긴 구간(22:00 ~ 02:00)
    return intervals.any((i) => overlapsCyclic(i, from, to));
  }

  /// 그 시각이 구간 안에 있는가 — 끝은 열린 구간이다(02:00 종료 이벤트는
  /// 02:00에는 이미 끝났다).
  static bool containsCyclic(DayInterval i, int t) =>
      _shifts.any((k) => i.from + k <= t && t < i.to + k);

  /// 두 구간이 겹치는가 — 맞닿기만 한 것은 겹침이 아니다.
  static bool overlapsCyclic(DayInterval i, int from, int to) =>
      _shifts.any((k) => i.from + k < to && from < i.to + k);
}

/// 자정 기준 분으로 나타낸 구간 하나. [to]는 자정을 넘기면 1440을 넘는다.
///
/// 레코드(`({int from, int to})`)가 아니라 이름 있는 타입인 이유는 두 축이
/// 섞이는 것을 막기 위해서다 — 여기 들어오는 값은 언제나 **분**이고,
/// 시각(DateTime)이나 시:분(TimeOfDay)이 아니다.
class DayInterval {
  const DayInterval(this.from, this.to);

  final int from;
  final int to;

  /// 'HH:mm' 두 개로 구간 하나. 종료가 시작보다 이르거나 같으면 **자정을
  /// 넘긴 것**으로 보고 다음 날로 넘긴다(22:00 ~ 02:00 → 1320 ~ 1560).
  ///
  /// 파티 회차([PartyOccurrence])·룸 패키지([PlaceAvailability])가 쓰는 규칙과
  /// 같다 — "끝이 시작보다 이르면 다음 날"은 이 앱 전체의 한 가지 약속이다.
  static DayInterval? fromHhmm(String? start, String? end) {
    final from = parseHhmm(start);
    final to = parseHhmm(end);
    if (from == null || to == null) return null;
    return DayInterval(from, to <= from ? to + DayTimeMatch.minutesPerDay : to);
  }

  /// 'HH:mm' → 자정 기준 분. 형식이 아니면 null(추측하지 않는다).
  static int? parseHhmm(String? hhmm) {
    final s = (hhmm ?? '').trim();
    if (s.isEmpty) return null;
    final parts = s.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return h * 60 + m;
  }

  @override
  bool operator ==(Object other) =>
      other is DayInterval && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => 'DayInterval($from, $to)';
}

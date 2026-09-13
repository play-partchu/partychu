import 'package:flutter/material.dart';

/// 요일 하나의 운영시간 — 영업 시작·종료, 정기 휴무, 24시간 영업, 브레이크 타임.
///
/// 시간 값([open]/[close]/[breakStart]/[breakEnd])은 휴무·24시간을 켜도 지우지
/// 않는다. 그래서 휴무를 다시 끄면 전에 넣어 둔 시간이 그대로 돌아온다.
@immutable
class PlaceDayHours {
  final TimeOfDay open;
  final TimeOfDay close;

  /// 정기 휴무일. 켜면 영업시간·브레이크 타임 입력이 모두 잠긴다.
  final bool isClosed;

  /// 이 요일만 24시간 영업. [isClosed]와 동시에 켤 수 없다.
  final bool is24Hours;

  /// 브레이크 타임 사용 여부. 휴무일에는 켜져 있어도 무시된다
  /// ([hasEffectiveBreak] 참고) — 값 자체는 남겨 둬야 휴무를 풀었을 때 복원된다.
  final bool hasBreakTime;
  final TimeOfDay breakStart;
  final TimeOfDay breakEnd;

  static const defaultBreakStart = TimeOfDay(hour: 15, minute: 0);
  static const defaultBreakEnd = TimeOfDay(hour: 17, minute: 0);

  const PlaceDayHours({
    required this.open,
    required this.close,
    this.isClosed = false,
    this.is24Hours = false,
    this.hasBreakTime = false,
    this.breakStart = defaultBreakStart,
    this.breakEnd = defaultBreakEnd,
  });

  PlaceDayHours copyWith({
    TimeOfDay? open,
    TimeOfDay? close,
    bool? isClosed,
    bool? is24Hours,
    bool? hasBreakTime,
    TimeOfDay? breakStart,
    TimeOfDay? breakEnd,
  }) => PlaceDayHours(
    open: open ?? this.open,
    close: close ?? this.close,
    isClosed: isClosed ?? this.isClosed,
    is24Hours: is24Hours ?? this.is24Hours,
    hasBreakTime: hasBreakTime ?? this.hasBreakTime,
    breakStart: breakStart ?? this.breakStart,
    breakEnd: breakEnd ?? this.breakEnd,
  );

  /// 휴무와 24시간 영업은 동시에 켤 수 없다 — 켜는 쪽이 반대쪽을 끈다.
  PlaceDayHours withClosed(bool value) =>
      copyWith(isClosed: value, is24Hours: value ? false : is24Hours);

  PlaceDayHours with24Hours(bool value) =>
      copyWith(is24Hours: value, isClosed: value ? false : isClosed);

  /// 실제로 브레이크 타임이 걸리는지 — 휴무일에는 설정할 수 없다.
  bool get hasEffectiveBreak => hasBreakTime && !isClosed;

  /// 하루를 "여는 시각부터 몇 분"으로 편 길이. 자정을 넘겨 닫는 가게
  /// (20:00~02:00)를 음수 없이 다루기 위한 것이다. 24시간이거나 여닫는 시각이
  /// 같으면 1440분.
  int get businessMinutes {
    if (is24Hours) return _minutesPerDay;
    final span = _offsetFrom(open, close);
    return span == 0 ? _minutesPerDay : span;
  }

  /// 브레이크 타임 계산의 기준 시각 — 24시간 영업은 자정부터 잰다.
  TimeOfDay get _breakBase =>
      is24Hours ? const TimeOfDay(hour: 0, minute: 0) : open;

  /// 브레이크 타임이 영업시간 안에 있고 시작이 종료보다 빠른지.
  bool get isBreakValid {
    final start = _offsetFrom(_breakBase, breakStart);
    final end = _offsetFrom(_breakBase, breakEnd);
    return start < end && end <= businessMinutes;
  }

  /// 화면에 그대로 띄우는 오류 문구. 문제가 없으면 null.
  String? get breakError {
    if (!hasEffectiveBreak || isBreakValid) return null;
    final start = _offsetFrom(_breakBase, breakStart);
    final end = _offsetFrom(_breakBase, breakEnd);
    if (start >= end) return '브레이크 타임 시작 시간은 종료 시간보다 빨라야 해요.';
    return '브레이크 타임은 영업시간 안에 있어야 해요.';
  }

  /// 브레이크 타임을 처음 켤 때 넣어 줄 기본값 — 기본 15:00~17:00이 영업시간
  /// 밖이면 영업시간을 삼등분한 가운데 토막으로 대신한다.
  PlaceDayHours withBreakEnabled(bool value) {
    if (!value) return copyWith(hasBreakTime: false);
    final seeded = copyWith(hasBreakTime: true);
    if (seeded.isBreakValid) return seeded;
    final span = businessMinutes;
    final base = _breakBase;
    return seeded.copyWith(
      breakStart: _shift(base, span ~/ 3),
      breakEnd: _shift(base, span * 2 ~/ 3),
    );
  }

  /// 이 요일이 [date]에 실제로 열려 있는 구간. 휴무면 null.
  ({DateTime start, DateTime end})? windowOn(DateTime date) {
    if (isClosed) return null;
    final midnight = DateTime(date.year, date.month, date.day);
    if (is24Hours) {
      return (start: midnight, end: midnight.add(const Duration(days: 1)));
    }
    final start = midnight.add(Duration(minutes: _minutesOf(open)));
    return (start: start, end: start.add(Duration(minutes: businessMinutes)));
  }

  /// 이 요일이 [date]에 쉬는 브레이크 타임 구간. 없거나 잘못된 값이면 null.
  ({DateTime start, DateTime end})? breakWindowOn(DateTime date) {
    if (!hasEffectiveBreak || !isBreakValid) return null;
    final window = windowOn(date);
    if (window == null) return null;
    final base = is24Hours
        ? DateTime(date.year, date.month, date.day)
        : window.start;
    final start = base.add(
      Duration(minutes: _offsetFrom(_breakBase, breakStart)),
    );
    final end = base.add(Duration(minutes: _offsetFrom(_breakBase, breakEnd)));
    return (start: start, end: end);
  }

  Map<String, dynamic> toMap() => {
    'open': PlaceWeeklyHours.formatTime(open),
    'close': PlaceWeeklyHours.formatTime(close),
    'isClosed': isClosed,
    'is24Hours': is24Hours,
    // 휴무일에는 브레이크 타임이 없는 것으로 저장한다 — 문서만 읽는 쪽이
    // 휴무일에 브레이크를 보여주는 일이 없도록.
    'hasBreakTime': hasEffectiveBreak,
    'breakStart': PlaceWeeklyHours.formatTime(breakStart),
    'breakEnd': PlaceWeeklyHours.formatTime(breakEnd),
  };

  /// 예전 문서에는 [isClosed]·[is24Hours]·[hasBreakTime]이 아예 없다 —
  /// 없으면 "영업일 / 24시간 아님 / 브레이크 없음"으로 읽는다.
  static PlaceDayHours? fromMap(Map? raw) {
    if (raw == null) return null;
    final open = _parseTime(raw['open'] ?? raw['openTime']);
    final close = _parseTime(raw['close'] ?? raw['closeTime']);
    if (open == null || close == null) return null;
    return PlaceDayHours(
      open: open,
      close: close,
      isClosed: raw['isClosed'] == true,
      is24Hours: raw['is24Hours'] == true,
      hasBreakTime: raw['hasBreakTime'] == true || raw['hasBreak'] == true,
      breakStart:
          _parseTime(raw['breakStart'] ?? raw['breakStartTime']) ??
          defaultBreakStart,
      breakEnd:
          _parseTime(raw['breakEnd'] ?? raw['breakEndTime']) ?? defaultBreakEnd,
    );
  }

  static const _minutesPerDay = 24 * 60;

  static int _minutesOf(TimeOfDay t) => t.hour * 60 + t.minute;

  /// [base]부터 [t]까지 앞으로 흐른 분 — 자정을 넘기면 하루를 더한다.
  static int _offsetFrom(TimeOfDay base, TimeOfDay t) {
    final diff = _minutesOf(t) - _minutesOf(base);
    return diff < 0 ? diff + _minutesPerDay : diff;
  }

  static TimeOfDay _shift(TimeOfDay base, int minutes) {
    final total = (_minutesOf(base) + minutes) % _minutesPerDay;
    return TimeOfDay(hour: total ~/ 60, minute: total % 60);
  }

  static TimeOfDay? _parseTime(dynamic value) {
    if (value is TimeOfDay) return value;
    if (value is String && value.contains(':')) {
      final parts = value.split(':');
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h != null && m != null) {
        // '24:00'으로 저장된 값도 자정으로 읽는다.
        return TimeOfDay(hour: h % 24, minute: m);
      }
    }
    return null;
  }
}

/// 지금 이 시각의 영업 상태 — 상세 화면 배지가 쓴다.
enum PlaceHoursStatus {
  /// 오늘이 정기 휴무일.
  closedToday,

  /// 영업시간이지만 지금은 브레이크 타임.
  onBreak,

  /// 영업 중.
  open,

  /// 오늘 영업일이지만 지금은 영업시간 밖.
  closedNow;

  String get label => switch (this) {
    closedToday => '오늘 휴무',
    onBreak => '브레이크 타임',
    open => '영업 중',
    closedNow => '영업 종료',
  };
}

class PlaceWeeklyHours {
  PlaceWeeklyHours._(this._hours);

  static const List<String> weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  /// 평일/주말 공통 시간을 한 번에 적용할 때 쓰는 묶음.
  static const List<String> weekdayOnly = ['월', '화', '수', '목', '금'];
  static const List<String> weekendOnly = ['토', '일'];

  /// '월' → '월요일'. 상세 화면 목록에 쓴다.
  static String fullDayName(String day) => '$day요일';

  final Map<String, PlaceDayHours> _hours;

  static String formatTime(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  /// [DateTime.weekday](월=1 … 일=7)를 이 클래스의 요일 키로.
  static String weekdayKeyOf(DateTime date) => weekdays[date.weekday - 1];

  factory PlaceWeeklyHours.defaultPreset() {
    final hours = <String, PlaceDayHours>{};
    for (final day in weekdays) {
      final weekend = day == '토' || day == '일';
      hours[day] = PlaceDayHours(
        open: TimeOfDay(hour: weekend ? 9 : 8, minute: 0),
        close: TimeOfDay(hour: weekend ? 15 : 22, minute: 0),
      );
    }
    return PlaceWeeklyHours._(hours);
  }

  factory PlaceWeeklyHours.fromMap(Map<String, dynamic>? map) {
    final base = PlaceWeeklyHours.defaultPreset();
    if (map == null || map.isEmpty) return base;

    final hours = <String, PlaceDayHours>{};
    for (final day in weekdays) {
      final raw = map[day];
      final parsed = raw is Map ? PlaceDayHours.fromMap(raw) : null;
      hours[day] = parsed ?? base.get(day)!;
    }
    return PlaceWeeklyHours._(hours);
  }

  PlaceDayHours? get(String day) => _hours[day];

  void setDay(String day, PlaceDayHours value) => _hours[day] = value;

  /// 한 요일만 그 자리에서 고친다 — `update('월', (d) => d.withClosed(true))`.
  void update(String day, PlaceDayHours Function(PlaceDayHours) change) {
    final current = _hours[day];
    if (current != null) _hours[day] = change(current);
  }

  /// 영업 시작·종료만 바꾸는 예전 시그니처. 휴무·24시간·브레이크는 건드리지
  /// 않으므로 기존 호출부가 그대로 동작한다.
  void set(String day, TimeOfDay open, TimeOfDay close, {bool? isClosed}) {
    final current = _hours[day];
    _hours[day] = current == null
        ? PlaceDayHours(open: open, close: close, isClosed: isClosed ?? false)
        : current.copyWith(
            open: open,
            close: close,
            isClosed: isClosed ?? current.isClosed,
          );
  }

  /// 기준 값 하나를 여러 요일에 그대로 복사한다 — 휴무·24시간·영업시간·
  /// 브레이크 타임까지 전부 함께 들어간다('평일 동일 적용').
  void applyToDays(Iterable<String> days, PlaceDayHours template) {
    for (final day in days) {
      _hours[day] = template;
    }
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{};
    for (final day in weekdays) {
      final value = _hours[day];
      if (value == null) continue;
      map[day] = value.toMap();
    }
    return map;
  }

  PlaceDayHours get first => _hours[weekdays.first]!;

  List<String> get daysWithEntries => _hours.keys.toList();

  /// 요일별 시간표에 휴무나 브레이크 타임이 하나라도 들어 있는지 —
  /// 상세 화면이 요일 목록을 펼쳐 보여줄지 판단할 때 쓴다.
  bool get hasClosedOrBreakDay =>
      _hours.values.any((d) => d.isClosed || d.hasEffectiveBreak);

  /// 브레이크 타임이 영업시간을 벗어난 요일의 안내 문구. 없으면 null —
  /// 저장 전에 막을 때 쓴다.
  String? get validationError {
    for (final day in weekdays) {
      final error = _hours[day]?.breakError;
      if (error != null) return '$day요일 $error';
    }
    return null;
  }

  /// 플레이스 문서에서 요일별 영업시간을 읽는다 — **두 이름을 모두 본다.**
  ///
  /// 등록 화면이 예전부터 `placeWeeklyHours`와 `weeklyOperatingHours` 두 이름으로
  /// 같은 값을 저장해 왔다. 한쪽만 읽으면 그 이름으로 저장된 가게가 통째로
  /// "영업시간을 모르는 곳"이 된다. 목록·상세·이벤트 필터가 전부 이 함수
  /// 하나를 거치게 해서 판정이 갈라지지 않게 한다.
  static PlaceWeeklyHours? fromPlaceDoc(Map<String, dynamic> data) {
    final raw =
        (data['placeWeeklyHours'] as Map?) ??
        (data['weeklyOperatingHours'] as Map?);
    if (raw == null || raw.isEmpty) return null;
    return PlaceWeeklyHours.fromMap(Map<String, dynamic>.from(raw));
  }

  /// [date] 주변(어제·오늘·내일)의 **실제 영업 구간들** — 브레이크 타임은 잘라낸다.
  ///
  /// 앞뒤 날을 함께 보는 이유가 이 함수의 전부다: 22:00에 열어 다음 날 02:00에
  /// 닫는 가게는 "오늘 01:00"에도 영업 중인데, 그 구간은 **어제 요일**에 적혀
  /// 있다. 오늘 것만 보면 그 가게가 새벽 조건에서 통째로 빠진다.
  ///
  /// 돌려주는 구간은 맞닿은 것끼리 이어 붙인 상태다([mergeAdjacent]) — 요일마다
  /// 24시간으로 등록한 가게가 자정에서 끊겨 "전체 영업" 조건을 못 넘기는 일을
  /// 막는다.
  List<({DateTime start, DateTime end})> openSegmentsAround(DateTime date) {
    final segments = <({DateTime start, DateTime end})>[];
    for (final offset in const [-1, 0, 1]) {
      final day = date.add(Duration(days: offset));
      final dayHours = get(weekdayKeyOf(day));
      if (dayHours == null) continue;
      final open = dayHours.windowOn(day);
      if (open == null) continue;
      // 브레이크 타임은 문을 닫는 시간이라 영업 구간에서 잘라낸다.
      final rest = dayHours.breakWindowOn(day);
      if (rest == null) {
        segments.add(open);
        continue;
      }
      if (open.start.isBefore(rest.start)) {
        segments.add((start: open.start, end: rest.start));
      }
      if (rest.end.isBefore(open.end)) {
        segments.add((start: rest.end, end: open.end));
      }
    }
    return mergeAdjacent(segments);
  }

  /// 겹치거나 맞닿은 구간을 하나로 합친다.
  static List<({DateTime start, DateTime end})> mergeAdjacent(
    List<({DateTime start, DateTime end})> segments,
  ) {
    final sorted = List.of(segments)
      ..sort((a, b) => a.start.compareTo(b.start));
    final merged = <({DateTime start, DateTime end})>[];
    for (final s in sorted) {
      if (merged.isNotEmpty && !s.start.isAfter(merged.last.end)) {
        final last = merged.removeLast();
        merged.add((
          start: last.start,
          end: s.end.isAfter(last.end) ? s.end : last.end,
        ));
      } else {
        merged.add(s);
      }
    }
    return merged;
  }

  /// [now] 기준 영업 상태. 자정을 넘겨 닫는 가게 때문에 **어제** 요일이 아직
  /// 이어지고 있는지도 함께 본다.
  PlaceHoursStatus statusAt(DateTime now) {
    final today = _hours[weekdayKeyOf(now)];
    if (today != null && today.isClosed) return PlaceHoursStatus.closedToday;

    final midnight = DateTime(now.year, now.month, now.day);
    for (final dayOffset in [0, -1]) {
      final date = midnight.add(Duration(days: dayOffset));
      final day = _hours[weekdayKeyOf(date)];
      final window = day?.windowOn(date);
      if (day == null || window == null) continue;
      if (now.isBefore(window.start) || !now.isBefore(window.end)) continue;
      final breakWindow = day.breakWindowOn(date);
      if (breakWindow != null &&
          !now.isBefore(breakWindow.start) &&
          now.isBefore(breakWindow.end)) {
        return PlaceHoursStatus.onBreak;
      }
      return PlaceHoursStatus.open;
    }
    return PlaceHoursStatus.closedNow;
  }
}

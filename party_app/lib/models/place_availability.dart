import 'package:flutter/material.dart';

import 'package:party_app/models/place_weekly_hours.dart';
import 'package:party_app/models/reservation_modes.dart';

/// 장소대여 "그 시간에 실제로 쓸 수 있는가" 판정 — **순수 계산만** 담당한다.
///
/// Firestore 조회는 [PlaceAvailabilityService]가 맡고, 여기서는 이미 읽어온
/// 문서(장소/룸/예약 슬롯)만 가지고 판정한다. 목록 상세검색과 예약 화면이
/// 서로 다른 기준을 쓰지 않도록, 판정 규칙은 **이 파일 하나에만** 둔다.
///
/// 쓰는 기존 데이터(새로 만든 필드는 하나도 없다):
/// - 장소 문서: `placeWeeklyHours`/`weeklyOperatingHours`(요일별 운영시간·정기
///   휴무·브레이크 타임), `isOpen24Hours`, `openTime`/`closeTime`
/// - 룸 문서(placeRooms): `reservationModes`, `openTime`/`closeTime`,
///   `isOpen24Hours`, `availableDays`(이용 가능 요일), `packages`(시작·종료·요일),
///   숙박 설정([StayConfig]), `minBookingMinutes`, `isActive`
/// - 예약 슬롯(places/{id}/reservationSlots): `roomId`/`startAt`/`endAt`/
///   `status`/`expiresAt` — 겹침 판정 규칙은 서버(roomAvailability.js)와 동일
///
/// 시간은 전부 **요청 날짜 자정 기준 분(minute)** 좌표로 다룬다. 자정을 넘기는
/// 이용(20일 22:00~21일 02:00)은 1440을 넘는 값으로 자연스럽게 표현된다 —
/// 예약 화면·서버가 이미 쓰고 있는 좌표계와 같다.
class PlaceAvailability {
  PlaceAvailability._();

  static const int minutesPerDay = 1440;

  /// 시간을 안 고른 경우, 그날 이 정도는 비어 있어야 "이용 가능"으로 본다 —
  /// 룸에 최소 예약 시간이 설정돼 있으면 그 값을 쓴다.
  static const int _defaultMinBookingMinutes = 60;

  /// 장소 하나가 요청 구간에 이용 가능한지.
  ///
  /// 룸이 있는 장소는 **룸 하나라도** 가능하면 가능으로 본다(예약은 룸 단위로
  /// 잡히므로, 한 룸이 찼다고 장소 전체가 막히는 게 아니다). 룸이 없는 옛
  /// 스키마 장소는 장소 문서 자체를 예약 단위로 쓴다.
  ///
  /// 여러 룸이 가능하면 **가장 잘 맞는 룸**(요청 전체를 덮는 룸 > 이용 가능
  /// 시간이 긴 룸)의 결과를 돌려준다 — 카드에 보여줄 "실제 이용 가능한 시간"이
  /// 룸마다 다르기 때문이다.
  static PlaceAvailabilityMatch placeMatch({
    required Map<String, dynamic> place,
    required List<Map<String, dynamic>> rooms,
    required List<PlaceBookedRange> booked,
    required PlaceAvailabilityRequest request,
  }) {
    if (rooms.isEmpty) {
      return unitMatch(
        unit: place,
        place: place,
        booked: booked.where((b) => b.roomId == null).toList(),
        request: request,
      );
    }
    // 룸을 두고 전부 비활성으로 내린 장소는 지금 받을 수 있는 예약이 없다.
    var best = PlaceAvailabilityMatch.none;
    for (final room in rooms.where((r) => r['isActive'] != false)) {
      final match = unitMatch(
        unit: room,
        place: place,
        booked: booked.where((b) => b.roomId == room['id']).toList(),
        request: request,
      );
      if (match.isBetterThan(best)) best = match;
      if (best.coversAll) break; // 더 좋을 수 없다
    }
    return best;
  }

  /// 예약 단위(룸 하나, 옛 스키마면 장소 자체) 판정.
  static PlaceAvailabilityMatch unitMatch({
    required Map<String, dynamic> unit,
    required Map<String, dynamic> place,
    required List<PlaceBookedRange> booked,
    required PlaceAvailabilityRequest request,
  }) {
    final free = freeIntervals(
      unit: unit,
      place: place,
      booked: booked,
      request: request,
    );
    if (free.isEmpty) return PlaceAvailabilityMatch.none;

    final start = request.startMinutes;
    final end = request.endMinutes;
    if (start == null || end == null) {
      // 날짜만 고른 경우 — 그날 안에 최소 예약 시간만큼 연속으로 비어 있으면 통과.
      final minMinutes = _minBookingMinutes(unit);
      for (final i in free) {
        final s = i.start < 0 ? 0 : i.start;
        final e = i.end > minutesPerDay ? minutesPerDay : i.end;
        if (e - s >= minMinutes) {
          return const PlaceAvailabilityMatch(
            available: true,
            coversAll: false,
          );
        }
      }
      return PlaceAvailabilityMatch.none;
    }

    // ① 요청 구간 **전체**가 하나로 이어져 비어 있는가 — '전체 시간 가능'의
    //    기준이자, '일부 시간 가능'에서도 가장 좋은 결과다.
    if (free.any((i) => i.start <= start && i.end >= end)) {
      return PlaceAvailabilityMatch(
        available: true,
        coversAll: true,
        slices: [PlaceInterval(start, end)],
      );
    }
    if (request.mode == PlaceAvailabilityMode.full) {
      return PlaceAvailabilityMatch.none;
    }

    // ② 일부 시간 가능 — 요청 범위와 겹치는 빈 구간을 잘라내되, 실제로
    //    예약할 수 있는 길이(최소 이용시간·예약 단위) 이상인 것만 남긴다.
    //    몇 분만 겹치는 장소가 결과에 섞이지 않게 하려는 것.
    final threshold = _minUsableMinutes(unit);
    final slices = <PlaceInterval>[];
    for (final i in free) {
      final s = i.start < start ? start : i.start;
      final e = i.end > end ? end : i.end;
      if (e - s >= threshold) slices.add(PlaceInterval(s, e));
    }
    if (slices.isEmpty) return PlaceAvailabilityMatch.none;
    return PlaceAvailabilityMatch(
      available: true,
      coversAll: false,
      slices: slices,
    );
  }

  /// 이 단위가 요청 날짜에 실제로 비어 있는 구간들(운영시간 − 브레이크 −
  /// 기존 예약). 예약 화면에서 "고를 수 있는 시간대"를 그릴 때도 그대로 쓸 수
  /// 있도록 공개해 둔다.
  static List<PlaceInterval> freeIntervals({
    required Map<String, dynamic> unit,
    required Map<String, dynamic> place,
    required List<PlaceBookedRange> booked,
    required PlaceAvailabilityRequest request,
  }) {
    final usable = usableIntervals(unit: unit, place: place, request: request);
    if (usable.isEmpty) return const [];
    return _subtract(
      usable,
      _merge(booked.map((b) => PlaceInterval(b.startMinutes, b.endMinutes))),
    );
  }

  /// 예약이 없다고 가정했을 때 이 단위를 쓸 수 있는 구간들 — 운영시간·정기
  /// 휴무·이용 가능 요일·브레이크 타임·예약 방식(시간제/패키지/숙박)을 모두
  /// 반영한 결과.
  static List<PlaceInterval> usableIntervals({
    required Map<String, dynamic> unit,
    required Map<String, dynamic> place,
    required PlaceAvailabilityRequest request,
  }) {
    final weekly = _weeklyHoursOf(place);
    // 룸이 실제로 받는 방식 — 목록 필터(placeReservationModes)와 같은 판정이라
    // "목록엔 숙박으로 떴는데 이용 가능 시간이 안 잡히는" 장소가 생기지 않는다.
    final modes = roomReservationModes(unit);
    final result = <PlaceInterval>[];

    // 자정을 넘기는 요청은 다음 날 운영시간도 함께 봐야 한다.
    for (var dayOffset = 0; dayOffset < request.spanDays; dayOffset++) {
      final date = request.date.add(Duration(days: dayOffset));
      final base = dayOffset * minutesPerDay;
      final dayKey = PlaceWeeklyHours.weekdayKeyOf(date);
      final dayHours = weekly?.get(dayKey);

      // 장소 정기 휴무일 — 그날은 어떤 방식으로도 이용할 수 없다.
      if (dayHours != null && dayHours.isClosed) continue;
      // 룸의 이용 가능 요일 — 비어 있으면 제한 없음.
      final availableDays =
          (unit['availableDays'] as List?)?.cast<String>() ?? const <String>[];
      if (availableDays.isNotEmpty && !availableDays.contains(dayKey)) continue;

      if (modes.contains(ReservationMode.hourly)) {
        final window = _hourlyWindow(unit, place, dayHours);
        if (window != null) {
          // 브레이크 타임은 시간제 이용에만 걸린다(숙박 손님은 그 시간에도
          // 방을 쓰고 있으므로).
          final breakWindow = _breakInterval(dayHours);
          final pieces = breakWindow == null
              ? [window]
              : _subtract([window], [breakWindow]);
          result.addAll(pieces.map((i) => i.shift(base)));
        }
      }

      if (modes.contains(ReservationMode.package)) {
        for (final pkg in _activePackages(unit)) {
          final days =
              (pkg['days'] as List?)?.cast<String>() ?? const <String>[];
          if (days.isNotEmpty && !days.contains(dayKey)) continue;
          final start = parseHhmm(pkg['startTime'] as String?);
          var end = parseHhmm(pkg['endTime'] as String?);
          if (end <= start) end += minutesPerDay; // 올나잇 등 익일까지
          result.add(PlaceInterval(start, end).shift(base));
        }
      }

      if (modes.contains(ReservationMode.stay)) {
        // 숙박은 체크인 시각부터 다음 날 체크아웃 시각까지를 점유한다 —
        // 서버(roomAvailability.js computeWindows)와 같은 계산.
        final stay = StayConfig.fromMap(unit);
        result.add(
          PlaceInterval(
            stay.checkInMinutes,
            minutesPerDay + stay.checkOutMinutes,
          ).shift(base),
        );
      }
    }

    return _merge(result);
  }

  // ── 운영시간 ────────────────────────────────────────────────────────────

  /// 시간제 이용의 하루 운영 구간. 룸 자체 설정이 가장 구체적이므로 먼저 보고
  /// (서버 loadReservationConfig와 같은 우선순위), 없으면 장소의 요일별
  /// 운영시간, 그것도 없으면 장소 대표 운영시간을 쓴다.
  static PlaceInterval? _hourlyWindow(
    Map<String, dynamic> unit,
    Map<String, dynamic> place,
    PlaceDayHours? dayHours,
  ) {
    final unitWindow = _windowFromOpenClose(unit);
    if (unitWindow != null) return unitWindow;

    if (dayHours != null) {
      if (dayHours.is24Hours) return const PlaceInterval(0, minutesPerDay);
      final open = _minutesOfTime(dayHours.open);
      return PlaceInterval(open, open + dayHours.businessMinutes);
    }

    final placeWindow = _windowFromOpenClose(place);
    if (placeWindow != null) return placeWindow;

    // 서버 기본값(openHour 9 / closeHour 23)과 같은 값으로 맞춘다.
    final openHour = (place['openHour'] as num?)?.toInt() ?? 9;
    final closeHour = (place['closeHour'] as num?)?.toInt() ?? 23;
    return PlaceInterval(openHour * 60, closeHour * 60);
  }

  static PlaceInterval? _windowFromOpenClose(Map<String, dynamic> d) {
    if (d['isOpen24Hours'] == true)
      return const PlaceInterval(0, minutesPerDay);
    final openRaw = d['openTime'] as String?;
    final closeRaw = d['closeTime'] as String?;
    if (openRaw == null ||
        closeRaw == null ||
        !openRaw.contains(':') ||
        !closeRaw.contains(':')) {
      return null;
    }
    final open = parseHhmm(openRaw);
    var close = parseHhmm(closeRaw);
    // 여닫는 시각이 같거나 종료가 더 이르면 자정을 넘겨 닫는다는 뜻
    // (20:00~02:00). 24:00은 parseHhmm가 1440으로 읽어 그대로 하루가 된다.
    if (close <= open) close += minutesPerDay;
    return PlaceInterval(open, close);
  }

  static PlaceInterval? _breakInterval(PlaceDayHours? dayHours) {
    if (dayHours == null || !dayHours.hasEffectiveBreak) return null;
    // 기준 날짜는 아무 날이나 써도 된다 — 자정 기준 분 좌표만 뽑아 쓴다.
    final date = DateTime(2000, 1, 1);
    final window = dayHours.breakWindowOn(date);
    if (window == null) return null;
    final midnight = DateTime(date.year, date.month, date.day);
    return PlaceInterval(
      window.start.difference(midnight).inMinutes,
      window.end.difference(midnight).inMinutes,
    );
  }

  static PlaceWeeklyHours? _weeklyHoursOf(Map<String, dynamic> place) {
    // 등록 화면이 두 이름으로 같은 값을 저장해 왔다(place_detail_screen과 동일).
    final raw =
        (place['placeWeeklyHours'] as Map?) ??
        (place['weeklyOperatingHours'] as Map?);
    if (raw == null || raw.isEmpty) return null;
    return PlaceWeeklyHours.fromMap(Map<String, dynamic>.from(raw));
  }

  static List<Map<String, dynamic>> _activePackages(Map<String, dynamic> unit) {
    final raw = (unit['packages'] as List?) ?? const [];
    return raw
        .map((p) => Map<String, dynamic>.from(p as Map))
        .where((p) => p['isActive'] != false)
        .toList();
  }

  static int _minBookingMinutes(Map<String, dynamic> unit) {
    final v = (unit['minBookingMinutes'] as num?)?.toInt();
    if (v != null && v > 0) return v;
    final hours = (unit['minHours'] as num?)?.toInt();
    if (hours != null && hours > 0) return hours * 60;
    return _defaultMinBookingMinutes;
  }

  /// '일부 시간이라도 가능'에서 한 토막이 결과에 낄 자격 — 실제로 예약할 수
  /// 있는 길이여야 한다. 최소 이용시간과 예약 단위 중 **더 긴 쪽**을 쓴다
  /// (2시간 단위로만 받는 곳에서 30분 토막을 "가능"이라 보여주면 안 된다).
  static int _minUsableMinutes(Map<String, dynamic> unit) {
    final unitMinutes = (unit['bookingUnitMinutes'] as num?)?.toInt() ?? 0;
    final minBooking = _minBookingMinutes(unit);
    return unitMinutes > minBooking ? unitMinutes : minBooking;
  }

  /// 자정 기준 분 → '19:00'. 다음 날로 넘어간 값은 '익일 01:00'으로,
  /// 정확히 자정에 끝나는 종료 시각은 '24:00'으로 읽는다.
  static String formatMinutes(int minutes, {bool asEnd = false}) {
    if (asEnd && minutes == minutesPerDay) return '24:00';
    final day = minutes ~/ minutesPerDay;
    final inDay = minutes % minutesPerDay;
    final label =
        '${(inDay ~/ 60).toString().padLeft(2, '0')}:'
        '${(inDay % 60).toString().padLeft(2, '0')}';
    return day >= 1 ? '익일 $label' : label;
  }

  static int _minutesOfTime(TimeOfDay t) => t.hour * 60 + t.minute;

  // ── 구간 계산 ───────────────────────────────────────────────────────────

  /// 겹치거나 맞닿은 구간을 하나로 합친다 — 24시간 운영 장소에서 하루치
  /// 구간 두 개가 자정에서 끊겨 보이는 일을 막는다.
  static List<PlaceInterval> _merge(Iterable<PlaceInterval> intervals) {
    final list = intervals.where((i) => i.end > i.start).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final merged = <PlaceInterval>[];
    for (final i in list) {
      if (merged.isNotEmpty && i.start <= merged.last.end) {
        final last = merged.removeLast();
        merged.add(
          PlaceInterval(last.start, i.end > last.end ? i.end : last.end),
        );
      } else {
        merged.add(i);
      }
    }
    return merged;
  }

  /// [from]에서 [remove] 구간들을 잘라낸 나머지.
  static List<PlaceInterval> _subtract(
    List<PlaceInterval> from,
    List<PlaceInterval> remove,
  ) {
    var result = _merge(from);
    for (final cut in _merge(remove)) {
      final next = <PlaceInterval>[];
      for (final i in result) {
        if (cut.end <= i.start || cut.start >= i.end) {
          next.add(i);
          continue;
        }
        if (cut.start > i.start) next.add(PlaceInterval(i.start, cut.start));
        if (cut.end < i.end) next.add(PlaceInterval(cut.end, i.end));
      }
      result = next;
    }
    return result;
  }
}

/// 고른 시간 범위를 어떻게 만족해야 하는지.
enum PlaceAvailabilityMode {
  /// 고른 범위 **전체**를 연속으로 이용할 수 있어야 한다(기본값).
  full('full', '전체 시간 가능', '고른 시간 전체를 연속으로 이용할 수 있는 장소만'),

  /// 고른 범위 안에 이용 가능한 구간이 하나라도 있으면 된다. 다만 실제로
  /// 예약할 수 있는 길이(최소 이용시간·예약 단위) 이상이어야 한다.
  partial('partial', '일부 시간이라도 가능', '고른 시간 중 일부라도 이용할 수 있는 장소까지');

  const PlaceAvailabilityMode(this.key, this.label, this.description);

  final String key;
  final String label;
  final String description;

  static PlaceAvailabilityMode fromKey(String? key) =>
      values.firstWhere((m) => m.key == key, orElse: () => full);
}

/// 한 장소(정확히는 가장 잘 맞는 룸)의 판정 결과.
@immutable
class PlaceAvailabilityMatch {
  /// 검색 결과에 넣어도 되는지.
  final bool available;

  /// 고른 시간 범위 전체를 연속으로 쓸 수 있는지.
  final bool coversAll;

  /// 고른 범위 안에서 실제로 쓸 수 있는 구간들(자정 기준 분). 날짜만 고른
  /// 경우에는 비어 있다.
  final List<PlaceInterval> slices;

  const PlaceAvailabilityMatch({
    required this.available,
    required this.coversAll,
    this.slices = const [],
  });

  static const none = PlaceAvailabilityMatch(
    available: false,
    coversAll: false,
  );

  int get totalMinutes => slices.fold(0, (sum, i) => sum + i.length);

  /// 룸이 여러 개일 때 어느 결과를 보여줄지 — 전체를 덮는 쪽이 우선이고,
  /// 그다음은 이용 가능한 시간이 긴 쪽.
  bool isBetterThan(PlaceAvailabilityMatch other) {
    if (available != other.available) return available;
    if (coversAll != other.coversAll) return coversAll;
    return totalMinutes > other.totalMinutes;
  }

  /// 카드에 그대로 쓰는 문구 — '19:00~23:00 이용 가능' /
  /// '19:00~21:00 · 22:00~23:00 가능'. 보여줄 게 없으면 null.
  String? get label {
    if (!available || slices.isEmpty) return null;
    final parts = slices
        .map(
          (i) =>
              '${PlaceAvailability.formatMinutes(i.start)}~'
              '${PlaceAvailability.formatMinutes(i.end, asEnd: true)}',
        )
        .toList();
    return parts.length == 1
        ? '${parts.first} 이용 가능'
        : '${parts.join(' · ')} 가능';
  }
}

/// 자정 기준 분 좌표의 반열린 구간 `[start, end)`.
@immutable
class PlaceInterval {
  final int start;
  final int end;

  const PlaceInterval(this.start, this.end);

  PlaceInterval shift(int minutes) =>
      PlaceInterval(start + minutes, end + minutes);

  int get length => end - start;

  @override
  String toString() => '[$start,$end)';
}

/// 이미 잡혀 있는 예약 한 건 — 요청 날짜 자정 기준 분 좌표.
/// 전날 시작한 예약은 [startMinutes]가 음수, 다음 날로 넘어가는 예약은
/// [endMinutes]가 1440을 넘는다.
@immutable
class PlaceBookedRange {
  /// 옛 스키마(룸 없는 장소)의 예약은 null.
  final String? roomId;
  final int startMinutes;
  final int endMinutes;

  const PlaceBookedRange({
    required this.roomId,
    required this.startMinutes,
    required this.endMinutes,
  });
}

/// "이 날짜(+시간)에 쓰고 싶다"는 요청.
@immutable
class PlaceAvailabilityRequest {
  /// 이용 날짜(자정으로 정규화).
  final DateTime date;

  /// 자정 기준 분. 둘 다 null이면 날짜만 고른 것.
  final int? startMinutes;

  /// 자정 기준 분. 종료가 시작보다 이르면 다음 날로 보고 1440을 더해 둔다.
  final int? endMinutes;

  /// 고른 시간 범위를 전부 써야 하는지, 일부만 써도 되는지.
  /// 시간을 안 골랐으면 의미가 없다.
  final PlaceAvailabilityMode mode;

  const PlaceAvailabilityRequest({
    required this.date,
    this.startMinutes,
    this.endMinutes,
    this.mode = PlaceAvailabilityMode.full,
  });

  /// 화면에서 고른 값(TimeOfDay)으로 만든다. 종료가 시작보다 이르거나 같으면
  /// 자정을 넘긴 이용으로 해석한다(22:00~02:00 → 1320~1560).
  factory PlaceAvailabilityRequest.from({
    required DateTime date,
    TimeOfDay? start,
    TimeOfDay? end,
    PlaceAvailabilityMode mode = PlaceAvailabilityMode.full,
  }) {
    final day = DateTime(date.year, date.month, date.day);
    if (start == null || end == null) {
      return PlaceAvailabilityRequest(date: day);
    }
    final s = start.hour * 60 + start.minute;
    var e = end.hour * 60 + end.minute;
    if (e <= s) e += PlaceAvailability.minutesPerDay;
    return PlaceAvailabilityRequest(
      date: day,
      startMinutes: s,
      endMinutes: e,
      mode: mode,
    );
  }

  bool get hasTimeRange => startMinutes != null && endMinutes != null;

  /// 자정을 넘기는 요청인지.
  bool get crossesMidnight =>
      (endMinutes ?? 0) > PlaceAvailability.minutesPerDay;

  /// 판정에 필요한 날짜 수(운영시간을 며칠치 펼쳐야 하는지).
  int get spanDays => crossesMidnight ? 2 : 1;

  /// 'YYYY-MM-DD' — 조회 범위는 날짜로만 정해지므로 예약 슬롯 캐시 키에 쓴다.
  String get dateKey =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  /// 판정 결과 캐시 키 등에 쓰는 짧은 서명(조건이 다르면 결과도 다르다).
  String get signature {
    final d = dateKey;
    return hasTimeRange ? '$d|$startMinutes-$endMinutes|${mode.key}' : d;
  }
}

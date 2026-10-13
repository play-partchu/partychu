import 'package:flutter/material.dart' show TimeOfDay;

import 'package:party_app/models/day_time_match.dart';

/// 🚚 **이동형 플레이스의 영업 일정** — 푸드트럭·이동식 팝업처럼 장소가 매번
/// 바뀌는 업체가 "언제 어디서 여는가"를 담는다.
///
/// ── 한 날에 한 곳 ───────────────────────────────────────────────────────
/// 이 구조의 **불변식**이다. 한 업체는 하루에 **한 장소**에서 영업하고,
/// 날짜에 따라 그 장소가 달라진다.
///
///     월: 홍대 · 화: 강남 · 수: 여의도 · 목: 휴무
///
/// 그래서 [regular]는 요일을 키로 가진 **맵**이고([Map]), 예외는 날짜마다
/// 슬롯 **하나**([ScheduleException.slot])다. 타입이 이미 막고 있으므로 "같은
/// 날 두 곳"이 들어올 길이 없다 — 해석 쪽에서 하나를 골라 버리는 방식이면
/// 호스트가 등록한 장소가 조용히 사라진다.
///
/// 해석 결과도 언제나 **하나거나 없음**이다([openingOn] · [openingFor]).
///
/// ── 무엇이 아닌가 ───────────────────────────────────────────────────────
/// ⚠️ **실시간 GPS 위치가 아니다.** 여기 들어오는 좌표는 업주가 미리 등록한
///    **영업 예정 장소**다(타입 이름이 [ScheduledStop]인 이유). 지금 실제로
///    트럭이 어디 있는지는 이 앱이 모르고, 알려고도 하지 않는다.
///
/// ⚠️ 기존 고정형 장소를 대체하지 않는다. `events` 문서에 [isMobileFieldName]이
///    없으면 고정형이고, 읽는 쪽은 예전과 **똑같이** `latitude`/`longitude`를
///    쓴다. 마이그레이션은 0건이다.
///
/// ── 왜 `PlaceWeeklyHours`를 쓰지 않는가 ─────────────────────────────────
/// `PlaceWeeklyHours`는 요일마다 **영업시간**만 담는다 — 장소가 하나로 고정된
/// 가게의 구조다. 이동형은 요일마다 **장소까지** 달라지므로 별도 구조가
/// 필요하다. 다만 **자정 넘김 판정은 기존 정본([DayTimeMatch])을 그대로
/// 쓴다** — 규칙을 두 번 적으면 "파티는 걸리는데 푸드트럭은 안 걸리는" 시각이
/// 생긴다.
///
/// ── 서브컬렉션으로 옮길 수 있게 갈라 뒀다 ──────────────────────────────
/// 해석 로직은 Firestore를 모르고 [regular]·[exceptions]만 읽는다. 예외가
/// 많아져 서브컬렉션으로 빼야 할 때는 **불러오는 쪽만** 바꾸고
/// [withExceptions]로 끼워 넣으면 된다.
class MobilePlaceSchedule {
  const MobilePlaceSchedule({
    this.regular = const {},
    this.closedWeekdays = const {},
    this.exceptions = const [],
  });

  /// `events` 문서에서 이 일정이 들어가는 필드 이름.
  static const String fieldName = 'mobileSchedule';

  /// "장소가 매번 바뀌시나요?"의 답이 저장되는 필드. **없으면 고정형**이다.
  static const String isMobileFieldName = 'isMobilePlace';

  /// 저장 형식 판. 2 = 요일 맵 + 예외 단일 슬롯(한 날에 한 곳).
  static const int formatVersion = 2;

  /// 지도·목록이 **읽는** 예외 일정 보관 창. 이보다 오래된 예외는
  /// [exceptionsBeyondRetention]으로 따로 셀 수 있다.
  ///
  /// ⚠️ 이 창을 넘긴 예외를 **지우지는 않는다**([prunedBeyondRetention]은
  ///    만들어만 두고 저장 경로에서 부르지 않는다).
  static const Duration retention = Duration(days: 90);

  /// 정기 영업 — **요일당 하나**. 키는 1=월 … 7=일([DateTime.weekday]와 같은
  /// 좌표). 없는 요일은 일정이 없다는 뜻이다.
  final Map<int, ScheduleSlot> regular;

  /// 명시적 휴무 요일.
  ///
  /// 슬롯이 없는 요일도 결과적으로 쉬는 것과 같다. 이 집합을 따로 두는 이유는
  /// **"아직 안 정함"과 "쉽니다"를 화면이 구분**해 보여 줄 수 있게 하려는
  /// 것뿐이고, 판정에서는 둘이 같다.
  final Set<int> closedWeekdays;

  /// 특정 날짜의 예외 — [regular]보다 **항상 우선**한다. 날짜당 하나다
  /// ([upsertException]이 지킨다).
  final List<ScheduleException> exceptions;

  // ── 불러오기 / 저장 ──────────────────────────────────────────────────

  static MobilePlaceSchedule fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return const MobilePlaceSchedule();
    return MobilePlaceSchedule(
      regular: _regularFrom(raw['regular']),
      closedWeekdays: _weekdaysFrom(raw['closedWeekdays']),
      exceptions: (raw['exceptions'] is List
              ? raw['exceptions'] as List
              : const [])
          .map(ScheduleException.fromMap)
          .whereType<ScheduleException>()
          .toList(growable: false),
    );
  }

  /// `events` 문서 전체에서 읽는다. [isMobileFieldName]이 true가 아니면
  /// **고정형**이므로 null을 돌려준다 — 옛 문서에 일정이 생기지 않는다.
  static MobilePlaceSchedule? ofPlace(Map<String, dynamic> data) {
    if (data[isMobileFieldName] != true) return null;
    final raw = data[fieldName];
    return fromMap(raw is Map ? raw.cast<String, dynamic>() : null);
  }

  Map<String, dynamic> toMap() => {
    'version': formatVersion,
    'regular': {
      for (final entry in _sortedRegular) '${entry.key}': entry.value.toMap(),
    },
    'closedWeekdays': closedWeekdays.toList()..sort(),
    'exceptions': [for (final e in exceptions) e.toMap()],
  };

  bool get isEmpty => regular.isEmpty && exceptions.isEmpty;

  /// 요일 순서대로 — 화면이 월→일로 그릴 때와 저장 순서가 같아진다.
  List<MapEntry<int, ScheduleSlot>> get _sortedRegular =>
      regular.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

  MobilePlaceSchedule copyWith({
    Map<int, ScheduleSlot>? regular,
    Set<int>? closedWeekdays,
    List<ScheduleException>? exceptions,
  }) => MobilePlaceSchedule(
    regular: regular ?? this.regular,
    closedWeekdays: closedWeekdays ?? this.closedWeekdays,
    exceptions: exceptions ?? this.exceptions,
  );

  /// 예외 목록만 갈아 끼운다 — 서브컬렉션으로 옮길 때 쓰는 자리.
  MobilePlaceSchedule withExceptions(List<ScheduleException> next) =>
      copyWith(exceptions: next);

  // ── 정기 일정 편집 ───────────────────────────────────────────────────

  /// 그 요일의 장소를 **바꾼다**(없으면 넣는다). 요일당 하나이므로 "추가"가
  /// 아니라 "변경"이다 — 장소를 넣으면 그 요일의 휴무도 함께 풀린다.
  MobilePlaceSchedule withRegular(int weekday, ScheduleSlot slot) => copyWith(
    regular: {...regular, weekday: slot},
    closedWeekdays: {...closedWeekdays}..remove(weekday),
  );

  /// 그 요일의 정기 일정을 지운다.
  MobilePlaceSchedule withoutRegular(int weekday) =>
      copyWith(regular: {...regular}..remove(weekday));

  /// 그 요일의 휴무를 켜고 끈다. **등록해 둔 장소는 지우지 않는다** — 끄면
  /// 그대로 살아난다.
  MobilePlaceSchedule withClosedWeekday(int weekday, bool closed) => copyWith(
    closedWeekdays: closed
        ? {...closedWeekdays, weekday}
        : ({...closedWeekdays}..remove(weekday)),
  );

  // ── 예외 편집 ────────────────────────────────────────────────────────

  /// 그 날짜의 예외. 등록 화면은 **날짜당 하나**만 만들지만, 손으로 넣은
  /// 문서처럼 여러 건이 들어 있으면 마지막 것을 보여 준다.
  ScheduleException? exceptionFor(DateTime date) {
    final key = ScheduleException.dateKeyOf(date);
    ScheduleException? found;
    for (final e in exceptions) {
      if (e.dateKey == key) found = e;
    }
    return found;
  }

  /// 예외를 **날짜 기준으로** 갈아 끼운다 — 같은 날짜에 중복이 쌓이지 않는다.
  MobilePlaceSchedule upsertException(ScheduleException next) => copyWith(
    exceptions: [
      for (final e in exceptions)
        if (e.dateKey != next.dateKey) e,
      next,
    ],
  );

  /// 🚚 **"오늘 여기서 영업해요!"** — 그 날 하루만 장소를 바꾼다.
  ///
  /// [regular]를 **건드리지 않는다.** 예외 한 건을 갈아 끼운 새 일정을
  /// 돌려주므로, 다음 주 같은 요일은 원래 장소 그대로다. 같은 날짜를 몇 번
  /// 눌러도 예외가 쌓이지 않는다([upsertException]).
  MobilePlaceSchedule withTodayStop(
    DateTime date, {
    required ScheduledStop stop,
    required String startTime,
    required String endTime,
    String? id,
  }) {
    final key = ScheduleException.dateKeyOf(date);
    return upsertException(
      ScheduleException(
        id: id ?? 'today-$key',
        dateKey: key,
        mode: ScheduleExceptionMode.replaceDay,
        slot: ScheduleSlot(stop: stop, startTime: startTime, endTime: endTime),
      ),
    );
  }

  /// 그 날짜의 예외를 지운다 — 정기 일정으로 되돌린다.
  MobilePlaceSchedule withoutExceptionOn(DateTime date) {
    final key = ScheduleException.dateKeyOf(date);
    return copyWith(
      exceptions: [
        for (final e in exceptions)
          if (e.dateKey != key) e,
      ],
    );
  }

  /// 오늘(포함) 이후의 예외만, 날짜순 — 등록 화면이 보여 주는 목록이다.
  List<ScheduleException> upcomingExceptions(DateTime now) {
    final today = _dayOf(now);
    return exceptions.where((e) {
          final d = e.date;
          return d != null && !d.isBefore(today);
        }).toList()
      ..sort((a, b) => a.dateKey.compareTo(b.dateKey));
  }

  /// 목록에서 감춘 **지난 예외**의 개수.
  int pastExceptionCount(DateTime now) {
    final today = _dayOf(now);
    return exceptions.where((e) {
      final d = e.date;
      return d != null && d.isBefore(today);
    }).length;
  }

  // ── 해석 — 한 날에 하나거나 없음 ────────────────────────────────────

  /// 그 날짜에 **시작하는** 영업. 없으면 null.
  ///
  /// 우선순위는 단순하다:
  ///   1. 그 날짜에 `closed` 예외가 있으면 → **쉰다**(null).
  ///   2. `replaceDay` 예외가 있으면 → 그 장소. 정기는 무시된다.
  ///   3. 그 밖에는 → 그 요일의 정기 장소(휴무 요일이면 null).
  ///
  /// 한 날짜에 예외가 여러 건 들어 있어도 **순서와 무관하게** 같은 답이
  /// 나온다(`closed`가 가장 강하다 — 업주가 쉰다고 한 날에 손님을 보내지
  /// 않는다).
  PlaceOpening? openingOn(DateTime date) {
    final key = ScheduleException.dateKeyOf(date);
    final onDate = exceptions.where((e) => e.dateKey == key);

    if (onDate.any((e) => e.mode == ScheduleExceptionMode.closed)) return null;

    // `replaceDay`가 있으면 그 날은 **정기 일정을 쓰지 않는다** — 장소가 아직
    // 비어 있어도 그렇다. 호스트가 "이 날은 다른 곳"이라고 표시했는데 정기
    // 장소를 보여 주면 손님을 **없는 자리로 보낸다.** 핀이 없는 것보다 나쁘다
    // (미완성 예외는 [validationErrors]가 저장 전에 짚어 준다).
    final replacing = onDate.where(
      (e) => e.mode == ScheduleExceptionMode.replaceDay,
    );
    if (replacing.isNotEmpty) {
      for (final e in replacing) {
        final opening = e.slot?.openingOn(
          date,
          source: PlaceOpeningSource.exception,
        );
        if (opening != null) return opening;
      }
      return null;
    }

    if (closedWeekdays.contains(date.weekday)) return null;
    return regular[date.weekday]?.openingOn(
      date,
      source: PlaceOpeningSource.regular,
    );
  }

  /// 지도·목록의 진입점 — 고른 **날짜와 시간**에 영업하는 자리. 없으면 null.
  ///
  /// · 시간을 고르지 않으면 그 날짜에 영업 일정이 있으면 통과다.
  /// · 시간을 고르면 **영업 여부를 가리는 게이트**다 — 시간이 장소를 고르는
  ///   것이 아니다(한 날에 한 곳이므로 고를 것이 없다).
  /// · 전날 밤에 시작해 이 날 새벽까지 가는 영업도 함께 본다(22:00~02:00인
  ///   트럭이 "익일 01:00" 조건에 걸려야 한다). 그 날짜 자신의 일정이 있으면
  ///   **그쪽이 우선**이라, 결과는 언제나 하나다.
  PlaceOpening? openingFor({
    required DateTime date,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
  }) {
    final day = _dayOf(date);
    final dayEnd = day.add(const Duration(days: 1));
    final hasTime = DayTimeMatch.isActive(startTime, endTime);

    bool accepts(PlaceOpening o) => hasTime
        ? DayTimeMatch.matches([o.intervalFrom(day)], startTime, endTime)
        // 날짜만 고른 경우 — 그 날짜에 **걸쳐 있는** 영업만.
        : o.start.isBefore(dayEnd) && o.end.isAfter(day);

    return _firstAccepted(day, accepts);
  }

  /// 목록 탭의 날짜·시간 판정 — 고정형과 **같은 의미**로 묻는다.
  ///
  /// 고정형 플레이스는 `main_screen`이 영업 구간과 고른 구간을 견주어
  /// 판정한다(시각 하나 / 일부 겹침 / 전체 포함). 이동형도 같은 규칙으로
  /// 답해야 목록과 지도, 고정형과 이동형이 서로 다른 말을 하지 않는다.
  /// 그 비교를 화면에 복사하지 않고 여기 둔다.
  ///
  /// · [moment]만 있으면 그 시각에 영업 중인가.
  /// · 구간이 있으면 [requireFullWindow]에 따라 **전체 포함** 또는 **일부 겹침**.
  /// · 둘 다 없으면 그 날짜에 영업 일정이 있는가([openingFor]와 같다).
  PlaceOpening? openingMatching({
    required DateTime date,
    DateTime? moment,
    DateTime? windowStart,
    DateTime? windowEnd,
    bool requireFullWindow = false,
  }) {
    if (moment == null && (windowStart == null || windowEnd == null)) {
      return openingFor(date: date);
    }
    final day = _dayOf(date);
    return _firstAccepted(day, (opening) {
      if (moment != null) return opening.containsMoment(moment);
      return requireFullWindow
          // 고른 구간이 영업 구간 **안에 통째로** 들어가야 한다.
          ? !opening.start.isAfter(windowStart!) &&
                !opening.end.isBefore(windowEnd!)
          // 일부라도 겹치면 통과(맞닿기만 한 것은 겹침이 아니다).
          : opening.start.isBefore(windowEnd!) &&
                opening.end.isAfter(windowStart!);
    });
  }

  /// [day]와 **전날**의 영업 중 조건을 만족하는 첫 건.
  ///
  /// 그 날짜 자신의 일정이 먼저다. 없을 때만 전날 밤 영업을 본다.
  ///
  /// ⚠️ 전날 건은 **자정을 넘겨 이 날까지 이어지는 것만** 본다.
  ///
  /// [DayTimeMatch]는 구간을 ±1440 밀어 가며 견주므로(자정 넘김 판정의 핵심),
  /// 그 성질을 그대로 두면 전날 11:00~20:00 영업이 **다음 날 12:00 조건에도
  /// 걸린다.** 수요일에 여는 트럭이 목요일(휴무) 검색에 뜨는 사고가 그것이다.
  /// 여기서 끊는다.
  PlaceOpening? _firstAccepted(
    DateTime day,
    bool Function(PlaceOpening) accepts,
  ) {
    for (final offset in const [0, -1]) {
      final opening = openingOn(day.add(Duration(days: offset)));
      if (opening == null) continue;
      if (offset != 0 && !opening.end.isAfter(day)) continue;
      if (accepts(opening)) return opening;
    }
    return null;
  }

  /// 그 날짜의 **영업 상태** — 상세 화면이 "오늘 여기서 영업 중 / 영업 전 /
  /// 영업 종료 / 휴무"를 가리는 데 쓴다.
  ///
  /// 판정은 [openingOn] 하나에 기댄다 — 상태를 세는 규칙을 화면에 두면 지도와
  /// 상세가 다른 말을 하게 된다.
  ///
  /// 미래 날짜는 자연히 [MobileOpeningStatus.beforeOpen](아직 안 열었다),
  /// 지난 날짜는 [MobileOpeningStatus.afterClose]가 된다 — 상태를 더 만들지
  /// 않아도 뜻이 맞는다.
  ({MobileOpeningStatus status, PlaceOpening? opening}) statusOn(
    DateTime date, {
    DateTime? now,
  }) {
    final opening = openingOn(date);
    if (opening == null) {
      return (status: MobileOpeningStatus.closed, opening: null);
    }
    final moment = now ?? DateTime.now();
    if (opening.containsMoment(moment)) {
      return (status: MobileOpeningStatus.open, opening: opening);
    }
    return (
      status: moment.isBefore(opening.start)
          ? MobileOpeningStatus.beforeOpen
          : MobileOpeningStatus.afterClose,
      opening: opening,
    );
  }

  /// [from]부터 [days]일간의 날짜별 일정 — 상세 화면의 "날짜별 영업 장소".
  ///
  /// **과거는 넣지 않는다**([from]을 오늘로 주면 오늘부터다). 휴무·일정 없는
  /// 날은 `opening`이 null이라, 화면이 "없는 영업을 있는 것처럼" 그릴 수
  /// 없다.
  List<({DateTime date, PlaceOpening? opening})> upcomingDays(
    DateTime from, {
    int days = 14,
  }) {
    final start = _dayOf(from);
    return [
      for (var i = 0; i < days; i++)
        if (start.add(Duration(days: i)) case final date)
          (date: date, opening: openingOn(date)),
    ];
  }

  /// 그 **순간** 영업 중인 곳. 없으면 null — 아무 데나 핀을 찍지 않는다.
  PlaceOpening? openingAt(DateTime moment) {
    for (final offset in const [0, -1]) {
      final day = _dayOf(moment).add(Duration(days: offset));
      final opening = openingOn(day);
      if (opening != null && opening.containsMoment(moment)) return opening;
    }
    return null;
  }

  /// [moment] 이후 **다음 영업 예정**. 상세 화면의 "다음 영업"에 쓴다.
  PlaceOpening? nextOpeningAfter(DateTime moment, {int withinDays = 14}) {
    final day = _dayOf(moment);
    for (var offset = 0; offset <= withinDays; offset++) {
      final opening = openingOn(day.add(Duration(days: offset)));
      if (opening != null && opening.start.isAfter(moment)) return opening;
    }
    return null;
  }

  // ── 보관 기간 ────────────────────────────────────────────────────────

  /// [retention] 안에 드는 예외(지도·목록이 읽는 것).
  List<ScheduleException> exceptionsWithin(DateTime now) {
    final from = _dayOf(now).subtract(retention);
    return exceptions
        .where((e) => !(e.date?.isBefore(from) ?? false))
        .toList(growable: false);
  }

  /// [retention]을 넘긴 예외 — **지우지 않고 세기만** 한다.
  List<ScheduleException> exceptionsBeyondRetention(DateTime now) {
    final from = _dayOf(now).subtract(retention);
    return exceptions
        .where((e) => e.date?.isBefore(from) ?? false)
        .toList(growable: false);
  }

  /// 보관 기간을 넘긴 예외를 **덜어낸** 사본. 정책이 정해지면 저장 직전에
  /// 부른다 — 지금은 어디서도 부르지 않는다.
  MobilePlaceSchedule prunedBeyondRetention(DateTime now) =>
      copyWith(exceptions: exceptionsWithin(now));

  // ── 검증 ─────────────────────────────────────────────────────────────

  /// 저장해도 되는 상태인가.
  ///
  /// "같은 요일 시간 겹침" 검사는 **없앴다** — 요일당 슬롯이 하나라서 겹칠
  /// 수가 없다. 구조가 막는 것을 경고로 또 지키면, 둘 중 하나가 낡는다.
  List<String> validationErrors() {
    final errors = <String>[];
    if (regular.isEmpty && exceptions.isEmpty) {
      errors.add('영업 일정을 최소 한 건 등록해주세요.');
    }
    for (final entry in _sortedRegular) {
      final label = _weekdayLabel(entry.key);
      if (entry.value.interval == null) {
        errors.add('$label요일 영업시간을 확인해주세요.');
      }
      if (!entry.value.stop.hasCoordinates) {
        errors.add('$label요일 장소의 위치를 지정해주세요.');
      }
    }
    for (final e in exceptions) {
      if (e.date == null) {
        errors.add('예외 일정의 날짜 형식을 확인해주세요.');
        continue;
      }
      if (e.mode == ScheduleExceptionMode.closed) continue;
      final slot = e.slot;
      if (slot == null) {
        errors.add('${e.dateKey} 예외 일정에 장소를 추가해주세요.');
        continue;
      }
      if (slot.interval == null || !slot.stop.hasCoordinates) {
        errors.add('${e.dateKey} 예외 일정의 장소와 시간을 확인해주세요.');
      }
    }
    return errors;
  }

  // ── 내부 ─────────────────────────────────────────────────────────────

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  static const List<String> _weekdayLabels = [
    '월',
    '화',
    '수',
    '목',
    '금',
    '토',
    '일',
  ];

  static String _weekdayLabel(int weekday) =>
      weekday >= 1 && weekday <= 7 ? _weekdayLabels[weekday - 1] : '?';

  static Set<int> _weekdaysFrom(dynamic raw) => (raw is List ? raw : const [])
      .map((v) => v is num ? v.toInt() : int.tryParse('$v'))
      .whereType<int>()
      .where((d) => d >= 1 && d <= 7)
      .toSet();

  /// 요일 맵을 읽는다.
  ///
  /// **읽기 호환**: 예전 형식은 `[{weekday, stop, startTime, endTime}, …]`
  /// 목록이었고 같은 요일이 여럿 올 수 있었다. 그런 문서를 만나면 그 요일의
  /// **첫 번째**만 쓴다 — 한 날에 한 곳이 불변식이므로, 둘을 다 살릴 방법이
  /// 없다(임시저장으로 남아 있을 수 있어 조용히 깨지지 않게 받아 준다).
  static Map<int, ScheduleSlot> _regularFrom(dynamic raw) {
    final result = <int, ScheduleSlot>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        final weekday = entry.key is num
            ? (entry.key as num).toInt()
            : int.tryParse('${entry.key}');
        if (weekday == null || weekday < 1 || weekday > 7) continue;
        final slot = ScheduleSlot.fromMap(entry.value);
        if (slot != null) result[weekday] = slot;
      }
      return result;
    }
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final weekday = (item['weekday'] as num?)?.toInt();
        if (weekday == null || weekday < 1 || weekday > 7) continue;
        if (result.containsKey(weekday)) continue; // 첫 번째만.
        final slot = ScheduleSlot.fromMap(item);
        if (slot != null) result[weekday] = slot;
      }
    }
    return result;
  }
}

/// 영업 예정 **장소 한 곳**. `events` 문서의 주소 필드와 같은 이름을 쓴다.
///
/// ⚠️ 실시간 위치가 아니라 **업주가 등록한 예정 장소**다(이름이 `Scheduled`로
///    시작하는 이유). 좌표를 직접 들고 있으므로, 나중에 지도에서 핀을 끌어
///    조정하는 기능을 붙일 때도 이 구조는 그대로 쓴다.
class ScheduledStop {
  const ScheduledStop({
    this.placeName = '',
    this.address = '',
    this.roadAddress = '',
    this.detailAddress = '',
    required this.latitude,
    required this.longitude,
  });

  final String placeName;
  final String address;
  final String roadAddress;
  final String detailAddress;
  final double latitude;
  final double longitude;

  /// 좌표가 실제로 들어 있는가 — 0은 "없음"이다(`MapListing.from`과 같은 규칙).
  bool get hasCoordinates => latitude != 0 && longitude != 0;

  /// 화면에 보여 줄 한 줄 — 장소 이름이 있으면 그걸, 없으면 주소를 쓴다.
  String get displayName => placeName.isNotEmpty
      ? placeName
      : (roadAddress.isNotEmpty ? roadAddress : address);

  static ScheduledStop? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    return ScheduledStop(
      placeName: raw['placeName'] as String? ?? '',
      address: raw['address'] as String? ?? '',
      roadAddress: raw['roadAddress'] as String? ?? '',
      detailAddress: raw['detailAddress'] as String? ?? '',
      latitude: (raw['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (raw['longitude'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    'placeName': placeName,
    'address': address,
    'roadAddress': roadAddress,
    'detailAddress': detailAddress,
    'latitude': latitude,
    'longitude': longitude,
  };

  @override
  bool operator ==(Object other) =>
      other is ScheduledStop &&
      other.placeName == placeName &&
      other.address == address &&
      other.roadAddress == roadAddress &&
      other.detailAddress == detailAddress &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(
    placeName,
    address,
    roadAddress,
    detailAddress,
    latitude,
    longitude,
  );
}

/// 장소 하나 + 시간 **한 구간**.
///
/// 하루를 여러 구간으로 쪼개지 않는다(브레이크 타임 없음). 필요해지면
/// [ScheduleSlot]에 구간을 더하는 쪽으로 늘리고, "한 날에 한 장소"는 그대로
/// 둔다 — 장소가 늘어나는 것과 시간이 쪼개지는 것은 다른 축이다.
class ScheduleSlot {
  const ScheduleSlot({
    required this.stop,
    required this.startTime,
    required this.endTime,
  });

  final ScheduledStop stop;

  /// `'HH:mm'`. 종료가 시작보다 이르거나 같으면 **자정을 넘긴 것**으로 본다
  /// ([DayInterval.fromHhmm] — 앱 전체의 한 가지 약속).
  final String startTime;
  final String endTime;

  DayInterval? get interval => DayInterval.fromHhmm(startTime, endTime);

  /// 이 슬롯을 [date] 위에 얹어 **실제 시각이 박힌** 영업 한 건으로 만든다.
  /// 좌표나 시간이 온전하지 않으면 null — 영업으로 세지 않는다.
  PlaceOpening? openingOn(DateTime date, {required PlaceOpeningSource source}) {
    final i = interval;
    if (i == null || !stop.hasCoordinates) return null;
    final day = DateTime(date.year, date.month, date.day);
    return PlaceOpening(
      stop: stop,
      start: day.add(Duration(minutes: i.from)),
      end: day.add(Duration(minutes: i.to)),
      source: source,
    );
  }

  ScheduleSlot copyWith({
    ScheduledStop? stop,
    String? startTime,
    String? endTime,
  }) => ScheduleSlot(
    stop: stop ?? this.stop,
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
  );

  static ScheduleSlot? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final stop = ScheduledStop.fromMap(raw['stop'] ?? raw['location']);
    final start = raw['startTime'] as String?;
    final end = raw['endTime'] as String?;
    if (stop == null || start == null || end == null) return null;
    return ScheduleSlot(stop: stop, startTime: start, endTime: end);
  }

  Map<String, dynamic> toMap() => {
    'stop': stop.toMap(),
    'startTime': startTime,
    'endTime': endTime,
  };
}

/// 예외 일정의 종류 — **둘뿐**이다.
///
/// 한 날에 한 곳이므로 "정기에 더한다"(옛 `addSlot`)는 뜻이 설 자리가 없다.
/// 장소를 바꾸는 것은 [replaceDay], 쉬는 것은 [closed]로 전부 표현된다.
enum ScheduleExceptionMode {
  /// 그 날은 **다른 곳에서** 영업한다 — 정기 일정은 무시된다.
  replaceDay,

  /// 그 날은 **쉰다**.
  closed;

  /// 저장값을 모드로. **읽기 호환**: 예전 `'addSlot'`은 [replaceDay]로 받는다
  /// (그 날의 장소는 하나이므로, 더하는 것과 바꾸는 것이 같은 결과가 된다).
  static ScheduleExceptionMode? parse(String? raw) {
    if (raw == 'addSlot') return replaceDay;
    for (final m in values) {
      if (m.name == raw) return m;
    }
    return null;
  }
}

/// 특정 날짜의 예외 — 정기 일정보다 **항상 우선**한다. 장소는 **하나**다.
class ScheduleException {
  const ScheduleException({
    required this.id,
    required this.dateKey,
    required this.mode,
    this.slot,
  });

  final String id;

  /// `'YYYY-MM-DD'`. 문자열로 두는 이유는 **시간대에 흔들리지 않게** 하려는
  /// 것이다 — Timestamp로 두면 UTC 변환에서 하루가 밀린다.
  final String dateKey;

  final ScheduleExceptionMode mode;

  /// [ScheduleExceptionMode.closed]면 null이어도 된다.
  final ScheduleSlot? slot;

  static String dateKeyOf(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// 형식이 아니면 null — 추측하지 않는다.
  DateTime? get date {
    final parts = dateKey.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    final parsed = DateTime(y, m, d);
    // 2026-02-30처럼 넘치는 날짜를 걸러낸다.
    if (parsed.month != m || parsed.day != d) return null;
    return parsed;
  }

  ScheduleException copyWith({
    ScheduleExceptionMode? mode,
    ScheduleSlot? slot,
    bool clearSlot = false,
  }) => ScheduleException(
    id: id,
    dateKey: dateKey,
    mode: mode ?? this.mode,
    slot: clearSlot ? null : (slot ?? this.slot),
  );

  /// **읽기 호환**: 예전 형식은 `slots: [...]` 목록이었다. 그런 문서를 만나면
  /// **첫 번째**만 쓴다(한 날에 한 곳이 불변식이다).
  static ScheduleException? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final dateKey = raw['date'] as String? ?? raw['dateKey'] as String?;
    final mode = ScheduleExceptionMode.parse(raw['mode'] as String?);
    if (dateKey == null || mode == null) return null;
    final legacy = raw['slots'];
    final slot =
        ScheduleSlot.fromMap(raw['slot']) ??
        (legacy is List && legacy.isNotEmpty
            ? ScheduleSlot.fromMap(legacy.first)
            : null);
    return ScheduleException(
      id: raw['id'] as String? ?? '',
      dateKey: dateKey,
      mode: mode,
      slot: slot,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'date': dateKey,
    'mode': mode.name,
    'slot': ?slot?.toMap(),
  };
}

/// 이 영업이 정기에서 온 것인지, 예외에서 온 것인지.
enum PlaceOpeningSource { regular, exception }

/// 그 날짜의 영업 상태 — 상세 화면의 표시 한 줄을 가른다
/// ([MobilePlaceSchedule.statusOn]).
///
/// [closed]는 **휴무와 "그 날 일정이 없음"을 함께** 뜻한다. 둘은 사용자에게
/// 같은 말이고(그 날은 못 간다), 가르려면 화면이 `closedWeekdays`까지 알아야
/// 해서 판정이 두 곳으로 번진다.
enum MobileOpeningStatus {
  /// 지금 영업 중.
  open,

  /// 아직 열지 않았다(오늘 나중, 또는 다음 날짜).
  beforeOpen,

  /// 오늘 영업이 끝났다(또는 지난 날짜).
  afterClose,

  /// 그 날은 영업하지 않는다(휴무이거나 일정이 없다).
  closed,
}

/// **해석이 끝난 영업 한 건** — 실제 시각과 좌표가 박혀 있다.
///
/// 지도는 이 값의 [stop] 좌표로 핀을 찍고, 상세 화면은 [start]·[end]로
/// "오늘 여기서 영업해요"를 쓴다.
class PlaceOpening {
  const PlaceOpening({
    required this.stop,
    required this.start,
    required this.end,
    required this.source,
  });

  final ScheduledStop stop;

  /// 절대 시각. [end]는 자정을 넘기면 다음 날이다.
  final DateTime start;
  final DateTime end;

  final PlaceOpeningSource source;

  /// 예외에서 온 영업인가 — "오늘만 여기" 표시에 쓴다.
  bool get isException => source == PlaceOpeningSource.exception;

  bool containsMoment(DateTime moment) =>
      !start.isAfter(moment) && end.isAfter(moment);

  /// [DayTimeMatch]에 넘길 구간 — [anchor] 자정 기준 분으로 환산한다.
  DayInterval intervalFrom(DateTime anchor) {
    final day = DateTime(anchor.year, anchor.month, anchor.day);
    return DayInterval(
      start.difference(day).inMinutes,
      end.difference(day).inMinutes,
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// 게시글(파티 문서) 하나의 "일정 유형".
///
/// 호스트 계정 전체의 운영 방식이 아니라 **그 게시글 한 건**의 일정 방식이다.
/// 같은 호스트가 정기 파티 게시글과 일회성 이벤트 게시글을 동시에 운영할 수
/// 있으며, 두 게시글은 서로 완전히 독립된 Firestore 문서다.
///
/// 기존(이 필드가 없던) 문서는 모두 [single]로 취급한다 — 하위 호환.
enum PartyScheduleType {
  single('single', '날짜 직접 선택', '원하는 날짜와 시간대를 여러 개 추가해요'),
  recurring('recurring', '매주 반복', '요일과 시간을 정하면 종료일까지 계속 반복돼요');

  const PartyScheduleType(this.key, this.label, this.description);

  /// Firestore `scheduleType` 필드에 저장되는 값.
  final String key;
  final String label;
  final String description;

  static PartyScheduleType fromKey(String? key) =>
      key == recurring.key ? recurring : single;
}

/// 정기 파티의 요일 키 — Firestore `weeklySchedule` 맵의 키로 그대로 쓴다.
/// 순서는 DateTime.weekday(월=1 … 일=7)와 1:1로 맞춘다.
const List<String> kPartyWeekdayKeys = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];

const Map<String, String> kPartyWeekdayLabels = {
  'monday': '월',
  'tuesday': '화',
  'wednesday': '수',
  'thursday': '목',
  'friday': '금',
  'saturday': '토',
  'sunday': '일',
};

/// 평일/주말 묶음 적용에 쓰는 그룹.
const List<String> kPartyWeekdayKeysWeekday = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
];
const List<String> kPartyWeekdayKeysWeekend = ['saturday', 'sunday'];

String partyWeekdayKeyOf(DateTime date) => kPartyWeekdayKeys[date.weekday - 1];

/// 요일 하나만 반복할 때 쓰는 긴 이름('매주 토요일').
const Map<String, String> kPartyWeekdayFullLabels = {
  'monday': '월요일',
  'tuesday': '화요일',
  'wednesday': '수요일',
  'thursday': '목요일',
  'friday': '금요일',
  'saturday': '토요일',
  'sunday': '일요일',
};

String formatScheduleTime(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// '오후 8:00' — 카드/상세의 좁은 칸에 쓰는 사람이 읽는 시각 표기.
/// (파티 카드의 시간 표기와 같은 규칙이다.)
String formatKoreanTimeOfDay(TimeOfDay t) {
  final ampm = t.hour < 12 ? '오전' : '오후';
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$ampm $h:${t.minute.toString().padLeft(2, '0')}';
}

TimeOfDay? parseScheduleTime(dynamic value) {
  if (value is TimeOfDay) return value;
  if (value is String && value.contains(':')) {
    final parts = value.split(':');
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h != null && m != null && h >= 0 && h <= 23 && m >= 0 && m <= 59) {
      return TimeOfDay(hour: h, minute: m);
    }
  }
  return null;
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime? _toDate(dynamic value) {
  if (value is Timestamp) return value.toDate().toLocal();
  if (value is DateTime) return value;
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  return null;
}

/// 같은 규칙([PartyRecruitDeadlineRule])이 "모집 시작"과 "모집 마감" 양쪽에
/// 쓰인다 — 계산은 똑같고 화면에 쓰는 말만 다르다. 어느 쪽을 편집 중인지 이
/// 값으로만 넘겨받아, 두 영역의 용어를 여기 한 곳에서 갈라 준다. 예전에는
/// 편집기가 어느 쪽이든 '마감'이라고 적어서, 모집 시작을 정하는데 "마감 날짜"가
/// 보이던 문제가 있었다.
enum PartyRecruitRuleKind {
  /// 언제부터 신청을 받을지 — 모집 시작.
  open,

  /// 언제 신청을 닫을지 — 모집 마감.
  close;

  bool get isOpen => this == open;

  /// 미리보기 끝에 붙는 말 — '8월 10일 (월) 오후 6:00 모집 마감'.
  String get term => isOpen ? '모집 시작' : '모집 마감';

  /// '직접 지정'에서 쓰는 두 입력칸 제목.
  String get dateFieldLabel => isOpen ? '모집 시작 날짜' : '모집 마감 날짜';
  String get timeFieldLabel => isOpen ? '모집 시작 시간' : '모집 마감 시각';

  /// 시각 하나만 고르는 방식(파티 시작일/전날 지정 시각)의 칸 제목·피커 제목.
  ///
  /// **어느 날의 시각인지는 칸 제목에 넣지 않는다** — 위에서 고른 방식 이름
  /// ('파티 시작일 지정 시각' / '파티 전날 지정 시각')이 이미 말해 준다. 예전에는
  /// 여기에도 '시작 날짜'를 붙여서, 모집 마감을 정하는 화면 한 곳에 '시작'이 세
  /// 번 나오고 무엇을 정하는 중인지 오히려 흐려졌다. 전날 방식만 하루 차이를
  /// 놓치기 쉬워 예외로 '파티 전날'을 남긴다.
  String dayTimeFieldLabel({required bool prevDay}) => isOpen
      ? (prevDay ? '파티 전날 모집 시작 시각' : '모집 시작 시각')
      : (prevDay ? '파티 전날 모집 마감 시각' : '모집 마감 시각');

  /// '파티 시작 전' 방식에서 "몇 시간 몇 분 전"을 고르는 휠 시트 제목.
  String get beforeStartPickerTitle =>
      isOpen ? '파티 시작 전 모집 시작' : '파티 시작 전 모집 마감';
}

/// 모집 마감 기준.
///
/// 회차마다 마감 시각이 달라지는 정기 파티 때문에 "고정 시각"이 아니라 규칙으로
/// 저장하고, 회차 시작 시각에 적용해 그때그때 계산한다. 날짜를 직접 고르는
/// 일회성 파티도 **같은 규칙**을 쓴다 — 날짜마다 자기 시작 시각에 규칙을
/// 적용하므로, 날짜가 여러 개여도 마감이 하나씩 따로 계산된다.
///
/// 예전 이름이던 `hoursBefore`/`sameDayTime`은 기준이 모호했다. 밤에 시작해
/// 다음 날 새벽에 끝나는 파티에서 "당일"이 시작 날짜인지 종료 날짜인지 알 수
/// 없었기 때문이다. 지금은 기준 날짜를 이름에 못박는다.
enum PartyDeadlineMode {
  /// 파티 시작 전 시간으로 마감 — 파티 시작 시각에서 N분 전(분 단위로 저장한다).
  beforeStart('beforeStart'),

  /// 파티가 **시작하는 날**의 지정 시각에 마감(예: 8/10 20:00 시작 → 8/10 18:00).
  /// 지정 시각이 파티 시작보다 뒤면 파티 시작 시각으로 당긴다([resolve] 참고).
  startDayTime('startDayTime'),

  /// 파티 **전날**의 지정 시각에 마감(예: 8/10 시작 → 8/9 18:00).
  prevDayTime('prevDayTime'),

  /// 직접 고른 날짜·시간에 마감. 시작 이후~종료 전으로도 잡을 수 있다
  /// (= 파티가 시작된 뒤에도 신청을 받는다).
  customDateTime('customDateTime'),

  /// 제한 없음 — 모집 마감 없이 회차 시작 전까지 계속 모집.
  none('none');

  const PartyDeadlineMode(this.key);

  /// Firestore/임시저장에 남는 값.
  final String key;

  /// 고른 방식의 뜻을 한 문장으로 푼 말 — 칩 이름만으로는 "그래서 언제
  /// 닫히는데?"가 남으므로 칩 아래에 이 문장을 함께 보여준다.
  ///
  /// 기준은 언제나 **파티 시작**이고, 결과는 **모집 마감**이라고 쓴다(모집
  /// 시작을 편집할 때만 [kind]로 뒷말을 갈아 끼운다). 예전에는 '시작 날짜의
  /// 지정 시각에 마감'처럼 무엇의 시작인지 안 밝혀서, 파티 시작인지 모집
  /// 시작인지 읽는 사람이 짚어야 했다.
  String labelFor(PartyRecruitRuleKind kind) => switch (this) {
    beforeStart =>
      kind.isOpen
          ? '파티 시작 전 지정한 시간부터 모집을 시작합니다.'
          : '파티 시작 전 지정한 시간에 모집이 자동으로 마감됩니다.',
    startDayTime =>
      kind.isOpen
          ? '파티가 시작하는 날, 지정한 시각부터 모집을 시작합니다.'
          : '파티가 시작하는 날, 지정한 시각에 모집이 자동으로 마감됩니다.',
    prevDayTime =>
      kind.isOpen
          ? '파티 전날 지정한 시각부터 모집을 시작합니다.'
          : '파티 전날 지정한 시각에 모집이 자동으로 마감됩니다.',
    customDateTime =>
      kind.isOpen ? '직접 고른 날짜·시각부터 모집을 시작합니다.' : '직접 고른 날짜·시각에 모집이 마감됩니다.',
    none => kind.isOpen ? '따로 정하지 않고 바로 모집을 시작합니다.' : '모집 마감 시각을 따로 정하지 않습니다.',
  };

  /// 좁은 칩에 들어가는 짧은 이름 — 기준이 되는 시점(파티 시작/전날)만 남긴다.
  ///
  /// 모집 시작·모집 마감 어느 쪽을 편집하든 **같은 이름**을 쓴다. 칩은 "무엇을
  /// 기준으로 잡을지"만 고르는 것이고, 그 기준이 시작인지 마감인지는 카드 제목
  /// ('모집 시작 기준' / '모집 마감 기준')과 아래 [labelFor] 문장이 말해 준다.
  String get shortLabel => switch (this) {
    beforeStart => '파티 시작 전',
    startDayTime => '파티 시작일 지정 시각',
    prevDayTime => '파티 전날 지정 시각',
    customDateTime => '직접 지정',
    none => '제한 없음',
  };

  /// 예전 키(`hoursBefore`/`sameDayTime`)로 저장된 문서·임시저장도 그대로 읽는다.
  static PartyDeadlineMode fromKey(String? key) {
    switch (key) {
      case 'hoursBefore':
        return beforeStart;
      case 'sameDayTime':
        return startDayTime;
    }
    for (final m in PartyDeadlineMode.values) {
      if (m.key == key) return m;
    }
    return beforeStart;
  }
}

/// '파티 시작 1시간 30분 전'처럼 사람이 읽는 길이 — 무엇의 시작인지 헷갈리지
/// 않게 '파티'를 앞에 붙인다. 0 이하면 '파티 시작 시각'.
String formatMinutesBeforeStart(int minutes) {
  if (minutes <= 0) return '파티 시작 시각';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h > 0 && m > 0) return '파티 시작 $h시간 $m분 전';
  if (h > 0) return '파티 시작 $h시간 전';
  return '파티 시작 $m분 전';
}

/// '8월 10일 (월) 오후 9:01' — 계산된 마감 일시를 보여줄 때 쓰는 표기.
String formatPartyDeadlineAt(DateTime at) {
  const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
  return '${at.month}월 ${at.day}일 (${weekdays[at.weekday - 1]}) '
      '${formatKoreanTimeOfDay(TimeOfDay(hour: at.hour, minute: at.minute))}';
}

@immutable
class PartyRecruitDeadlineRule {
  final PartyDeadlineMode mode;

  /// [PartyDeadlineMode.beforeStart]에서 쓰는 "시작 몇 분 전".
  /// 계산이 단순하도록 시간/분을 섞지 않고 **전체 분**으로만 들고 있는다
  /// (1시간 30분 전 = 90).
  final int minutesBefore;

  /// [PartyDeadlineMode.startDayTime]·[PartyDeadlineMode.prevDayTime]에서 쓰는 시각.
  final TimeOfDay dayTime;

  /// [PartyDeadlineMode.customDateTime]에서 쓰는 절대 시각.
  final DateTime? customAt;

  const PartyRecruitDeadlineRule({
    this.mode = PartyDeadlineMode.beforeStart,
    this.minutesBefore = 60,
    this.dayTime = const TimeOfDay(hour: 18, minute: 0),
    this.customAt,
  });

  /// 마감 없이 계속 모집 — 날짜 직접 선택 방식의 기본값이다(예전에는 마감
  /// 시간을 아예 안 고르면 마감이 없었다).
  static const noDeadline = PartyRecruitDeadlineRule(
    mode: PartyDeadlineMode.none,
  );

  /// 규칙이 생기기 전 임시저장/문서가 갖고 있던 "마감 시각" 하나를 규칙으로
  /// 되살린다 — 그 값은 늘 "각 날짜 당일 그 시각"이라는 뜻이었다.
  static PartyRecruitDeadlineRule fromLegacyDayTime(TimeOfDay? time) {
    if (time == null) return noDeadline;
    return PartyRecruitDeadlineRule(
      mode: PartyDeadlineMode.startDayTime,
      dayTime: time,
    );
  }

  bool get isNone => mode == PartyDeadlineMode.none;

  PartyRecruitDeadlineRule copyWith({
    PartyDeadlineMode? mode,
    int? minutesBefore,
    TimeOfDay? dayTime,
    DateTime? customAt,
  }) {
    return PartyRecruitDeadlineRule(
      mode: mode ?? this.mode,
      minutesBefore: minutesBefore ?? this.minutesBefore,
      dayTime: dayTime ?? this.dayTime,
      customAt: customAt ?? this.customAt,
    );
  }

  /// 회차 시작 시각 [occurrenceStart]에 규칙을 적용한 실제 마감 시각.
  ///
  /// 시작을 기준으로 계산하는 방식([startDayTime])이 시작보다 뒤로 나오면
  /// 시작 시각으로 당긴다 — 실수로 "시작 후에도 신청 가능"이 되지 않도록.
  /// 시작 이후 마감은 [customDateTime]으로만, 즉 호스트가 안내를 보고 직접
  /// 확인했을 때만 만들어진다. 그 경우에도 회차 종료([occurrenceEnd])는
  /// 넘지 못한다.
  DateTime? resolve(DateTime occurrenceStart, {DateTime? occurrenceEnd}) {
    switch (mode) {
      case PartyDeadlineMode.none:
        return null;
      case PartyDeadlineMode.beforeStart:
        return occurrenceStart.subtract(Duration(minutes: minutesBefore));
      case PartyDeadlineMode.startDayTime:
        final at = DateTime(
          occurrenceStart.year,
          occurrenceStart.month,
          occurrenceStart.day,
          dayTime.hour,
          dayTime.minute,
        );
        return at.isAfter(occurrenceStart) ? occurrenceStart : at;
      case PartyDeadlineMode.prevDayTime:
        // day - 1은 Dart가 월/연을 알아서 넘겨준다(8/1 → 7/31).
        return DateTime(
          occurrenceStart.year,
          occurrenceStart.month,
          occurrenceStart.day - 1,
          dayTime.hour,
          dayTime.minute,
        );
      case PartyDeadlineMode.customDateTime:
        final at = customAt;
        if (at == null) return null;
        if (occurrenceEnd != null && at.isAfter(occurrenceEnd)) {
          return occurrenceEnd;
        }
        return at;
    }
  }

  /// 이 규칙이 시작 이후 마감인지 — 안내 문구/확인 절차를 띄울지 판단한다.
  bool startsBeforeDeadline(DateTime occurrenceStart) {
    final at = resolve(occurrenceStart);
    return at != null && at.isAfter(occurrenceStart);
  }

  String get label => switch (mode) {
    PartyDeadlineMode.none => '제한 없음',
    PartyDeadlineMode.beforeStart => formatMinutesBeforeStart(minutesBefore),
    PartyDeadlineMode.startDayTime =>
      '파티 시작일 ${formatKoreanTimeOfDay(dayTime)}',
    PartyDeadlineMode.prevDayTime => '파티 전날 ${formatKoreanTimeOfDay(dayTime)}',
    PartyDeadlineMode.customDateTime =>
      customAt == null ? '직접 지정' : formatPartyDeadlineAt(customAt!),
  };

  Map<String, dynamic> toMap() => {
    'mode': mode.key,
    if (mode == PartyDeadlineMode.beforeStart) ...{
      'minutes': minutesBefore,
      // 시간 단위만 읽던 예전 앱/서버를 위한 값(내림). 새 코드는 'minutes'를 본다.
      'hours': minutesBefore ~/ 60,
    },
    if (mode == PartyDeadlineMode.startDayTime ||
        mode == PartyDeadlineMode.prevDayTime)
      'time': formatScheduleTime(dayTime),
    // Timestamp 대신 밀리초 정수 — Firestore와 임시저장(JSON) 양쪽에 같은
    // 모양으로 들어간다.
    if (mode == PartyDeadlineMode.customDateTime && customAt != null)
      'atMs': customAt!.millisecondsSinceEpoch,
  };

  static PartyRecruitDeadlineRule fromMap(Map<String, dynamic>? map) {
    if (map == null) return const PartyRecruitDeadlineRule();
    final rawMinutes = (map['minutes'] as num?)?.toInt();
    // 예전 문서는 시간 단위('hours')만 갖고 있다.
    final legacyHours = (map['hours'] as num?)?.toInt();
    final minutes = rawMinutes ?? ((legacyHours ?? 1) * 60);
    final atMs = (map['atMs'] as num?)?.toInt();
    return PartyRecruitDeadlineRule(
      mode: PartyDeadlineMode.fromKey(map['mode'] as String?),
      minutesBefore: minutes < 0 ? 0 : minutes,
      dayTime:
          parseScheduleTime(map['time']) ??
          const TimeOfDay(hour: 18, minute: 0),
      customAt: atMs != null
          ? DateTime.fromMillisecondsSinceEpoch(atMs)
          : _toDate(map['at']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PartyRecruitDeadlineRule &&
      other.mode == mode &&
      other.minutesBefore == minutesBefore &&
      other.dayTime == dayTime &&
      other.customAt == customAt;

  @override
  int get hashCode => Object.hash(mode, minutesBefore, dayTime, customAt);
}

/// 정기 파티의 요일 한 칸.
@immutable
class PartyWeeklySlot {
  final bool enabled;
  final TimeOfDay startTime;
  final TimeOfDay endTime;

  const PartyWeeklySlot({
    required this.enabled,
    required this.startTime,
    required this.endTime,
  });

  const PartyWeeklySlot.disabled()
    : enabled = false,
      startTime = const TimeOfDay(hour: 19, minute: 0),
      endTime = const TimeOfDay(hour: 22, minute: 0);

  PartyWeeklySlot copyWith({
    bool? enabled,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
  }) {
    return PartyWeeklySlot(
      enabled: enabled ?? this.enabled,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
    );
  }

  /// 종료가 시작보다 이르거나 같으면 자정을 넘긴 것으로 본다
  /// (예: 19:00~03:00 → 다음 날 오전 3시 종료).
  bool get crossesMidnight =>
      endTime.hour * 60 + endTime.minute <=
      startTime.hour * 60 + startTime.minute;

  Map<String, dynamic> toMap() => {
    'enabled': enabled,
    'startTime': formatScheduleTime(startTime),
    'endTime': formatScheduleTime(endTime),
  };

  static PartyWeeklySlot? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final start = parseScheduleTime(raw['startTime']);
    final end = parseScheduleTime(raw['endTime']);
    if (start == null || end == null) return null;
    return PartyWeeklySlot(
      // enabled 키가 없는 문서는 "칸이 있으면 켜진 것"으로 해석한다.
      enabled: raw['enabled'] as bool? ?? true,
      startTime: start,
      endTime: end,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PartyWeeklySlot &&
      other.enabled == enabled &&
      other.startTime == startTime &&
      other.endTime == endTime;

  @override
  int get hashCode => Object.hash(enabled, startTime, endTime);
}

/// 파티 한 회차 — 정기/일회성 상관없이 "실제로 열리는 한 번"을 나타낸다.
@immutable
class PartyOccurrence {
  final DateTime start;

  /// 자정을 넘기는 시간대(19:00~03:00)는 이미 다음 날로 보정된 값이다.
  final DateTime end;

  /// 이 회차의 모집 마감 시각. 마감 규칙이 없으면 null.
  final DateTime? deadline;

  /// 이 회차의 모집 시작 시각. 제한이 없으면 null.
  final DateTime? recruitOpenAt;

  const PartyOccurrence({
    required this.start,
    required this.end,
    this.deadline,
    this.recruitOpenAt,
  });

  /// [now]에 이 회차 신청을 받을 수 있는지 — 모집 시작 전이거나 마감 뒤면 false.
  bool isRecruitingAt(DateTime now) {
    if (recruitOpenAt != null && now.isBefore(recruitOpenAt!)) return false;
    if (deadline != null && !now.isBefore(deadline!)) return false;
    return true;
  }

  bool get crossesMidnight => end.day != start.day;

  /// 이 회차를 가리키는 안정적인 식별자 — 회차는 하루에 하나뿐이라
  /// 시작 날짜(YYYY-MM-DD)만으로 유일하다. 신청 문서에 저장되고, 서버가
  /// 같은 규칙으로 다시 계산해 검증한다(functions/partySchedule.js).
  String get id =>
      '${start.year.toString().padLeft(4, '0')}-'
      '${start.month.toString().padLeft(2, '0')}-'
      '${start.day.toString().padLeft(2, '0')}';
}

/// 정기 파티 일정 — 매주 지정된 요일/시간에 반복된다.
@immutable
class PartyRecurringSchedule {
  /// 정기 운영 시작일(날짜만 의미 있음).
  final DateTime startDate;

  /// 운영 종료일. null이면 "종료일 없음"(무기한).
  final DateTime? endDate;

  /// 요일별 운영 시간. 키는 [kPartyWeekdayKeys].
  final Map<String, PartyWeeklySlot> weekly;

  /// 모집 **시작** 규칙. [PartyDeadlineMode.none]이면 제한 없음(바로 모집).
  final PartyRecruitDeadlineRule openRule;

  /// 모집 **마감** 규칙.
  final PartyRecruitDeadlineRule deadlineRule;

  const PartyRecurringSchedule({
    required this.startDate,
    this.endDate,
    required this.weekly,
    this.openRule = PartyRecruitDeadlineRule.noDeadline,
    this.deadlineRule = const PartyRecruitDeadlineRule(),
  });

  /// 아무 요일도 켜지지 않은 기본값 — 오늘부터 시작, 종료일 없음.
  factory PartyRecurringSchedule.empty({DateTime? from}) {
    final base = _dateOnly(from ?? DateTime.now());
    return PartyRecurringSchedule(
      startDate: base,
      weekly: {
        for (final key in kPartyWeekdayKeys)
          key: const PartyWeeklySlot.disabled(),
      },
    );
  }

  List<String> get enabledDayKeys =>
      kPartyWeekdayKeys.where((k) => weekly[k]?.enabled == true).toList();

  bool get hasEnabledDay => enabledDayKeys.isNotEmpty;

  PartyWeeklySlot slotFor(String key) =>
      weekly[key] ?? const PartyWeeklySlot.disabled();

  PartyRecurringSchedule copyWith({
    DateTime? startDate,
    DateTime? endDate,
    bool clearEndDate = false,
    Map<String, PartyWeeklySlot>? weekly,
    PartyRecruitDeadlineRule? openRule,
    PartyRecruitDeadlineRule? deadlineRule,
  }) {
    return PartyRecurringSchedule(
      startDate: startDate ?? this.startDate,
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      weekly: weekly ?? this.weekly,
      openRule: openRule ?? this.openRule,
      deadlineRule: deadlineRule ?? this.deadlineRule,
    );
  }

  PartyRecurringSchedule withSlot(String key, PartyWeeklySlot slot) {
    return copyWith(weekly: {...weekly, key: slot});
  }

  /// [days]에 [source]의 시간대를 그대로 복사한다(평일/주말 묶어 설정).
  /// 복사 후에도 각 요일을 개별로 다시 수정할 수 있다.
  PartyRecurringSchedule applyTimesTo(
    Iterable<String> days,
    PartyWeeklySlot source,
  ) {
    final next = {...weekly};
    for (final key in days) {
      final current = next[key] ?? const PartyWeeklySlot.disabled();
      next[key] = current.copyWith(
        enabled: true,
        startTime: source.startTime,
        endTime: source.endTime,
      );
    }
    return copyWith(weekly: next);
  }

  /// [day](날짜)에 이 정기 일정의 회차가 있으면 반환한다. 요일이 꺼져 있거나
  /// 운영 기간(startDate~endDate) 밖이면 null.
  PartyOccurrence? occurrenceOn(DateTime day) {
    final d = _dateOnly(day);
    if (d.isBefore(_dateOnly(startDate))) return null;
    if (endDate != null && d.isAfter(_dateOnly(endDate!))) return null;
    final slot = weekly[partyWeekdayKeyOf(d)];
    if (slot == null || !slot.enabled) return null;

    final start = DateTime(
      d.year,
      d.month,
      d.day,
      slot.startTime.hour,
      slot.startTime.minute,
    );
    var end = DateTime(
      d.year,
      d.month,
      d.day,
      slot.endTime.hour,
      slot.endTime.minute,
    );
    // 자정을 넘기는 시간대(19:00~03:00)는 종료를 다음 날로 넘긴다.
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));

    return PartyOccurrence(
      start: start,
      end: end,
      deadline: deadlineRule.resolve(start, occurrenceEnd: end),
      recruitOpenAt: openRule.resolve(start, occurrenceEnd: end),
    );
  }

  /// [from] 시점에 아직 끝나지 않은 가장 가까운 회차.
  ///
  /// 진행 중인 회차(예: 어제 19시 시작, 오늘 새벽 3시 종료)도 "다음 회차"로
  /// 본다 — 그래서 하루 전부터 훑는다. 종료일이 지나 남은 회차가 없으면 null.
  PartyOccurrence? nextOccurrence(DateTime from) {
    if (!hasEnabledDay) return null;
    var cursor = _dateOnly(from).subtract(const Duration(days: 1));
    // 운영 시작일이 아직 한참 뒤면(예: 다음 달부터 시작) 그 앞을 훑어봐야
    // 회차가 없다 — 시작일부터 훑어야 "첫 회차"를 찾을 수 있다.
    final startDay = _dateOnly(startDate);
    if (cursor.isBefore(startDay)) cursor = startDay;
    final limit = endDate != null ? _dateOnly(endDate!) : null;
    // 요일이 하나라도 켜져 있으면 8일 안에 반드시 하나가 잡힌다.
    for (var i = 0; i < 9; i++) {
      if (limit != null && cursor.isAfter(limit)) return null;
      final occ = occurrenceOn(cursor);
      if (occ != null && occ.end.isAfter(from)) return occ;
      cursor = cursor.add(const Duration(days: 1));
    }
    return null;
  }

  /// 운영 종료일 이전의 **마지막 회차** — 이 정기 파티가 다시는 열리지 않게
  /// 되는 지점이다. 종료일부터 하루씩 거슬러 올라가며 켜진 요일을 처음
  /// 만나는 날이 마지막 회차다(요일이 하나라도 켜져 있으면 8일 안에 만난다).
  ///
  /// 종료일이 없으면(무기한) null — 끝나는 때가 없다.
  PartyOccurrence? lastOccurrence() {
    final end = endDate;
    if (end == null || !hasEnabledDay) return null;
    var cursor = _dateOnly(end);
    final startDay = _dateOnly(startDate);
    for (var i = 0; i < 9; i++) {
      if (cursor.isBefore(startDay)) return null;
      final occ = occurrenceOn(cursor);
      if (occ != null) return occ;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return null;
  }

  /// [from] 기준으로 아직 모집 마감되지 않은 가장 가까운 회차.
  /// (마감이 지난 이번 회차 대신 그 다음 회차를 찾는다.)
  PartyOccurrence? nextOpenOccurrence(DateTime from) {
    var cursor = from;
    for (var i = 0; i < 10; i++) {
      final occ = nextOccurrence(cursor);
      if (occ == null) return null;
      if (occ.deadline == null || occ.deadline!.isAfter(from)) return occ;
      // 이번 회차는 마감 — 그 회차가 끝난 직후부터 다시 찾는다.
      cursor = occ.end.add(const Duration(minutes: 1));
    }
    return null;
  }

  /// [from]~[to](양끝 포함, 날짜 단위) 사이의 모든 회차.
  List<PartyOccurrence> occurrencesBetween(DateTime from, DateTime to) {
    final result = <PartyOccurrence>[];
    var cursor = _dateOnly(from);
    final last = _dateOnly(to);
    // 무한 루프 방지 — 최대 약 2년치.
    var guard = 0;
    while (!cursor.isAfter(last) && guard < 800) {
      guard++;
      final occ = occurrenceOn(cursor);
      if (occ != null) result.add(occ);
      cursor = cursor.add(const Duration(days: 1));
    }
    return result;
  }

  // ── 사람이 읽는 일정 요약 ────────────────────────────────────────────
  // 상단 좁은 칸(짧게)과 아래 상세 영역(자세히)이 **같은 요일 묶음 규칙**을
  // 공유한다 — 라벨 규칙이 두 벌로 갈라지지 않도록 여기 한 곳에만 둔다.

  /// 요일 키 묶음을 최대한 짧은 라벨로 만든다.
  ///
  /// [compact]는 상단 좁은 칸용(월~금을 '평일'로 줄임)이고, false면 아래
  /// 상세 줄용('월~금')이다. 그 외 규칙은 두 곳이 같다:
  /// 7일=매일 / 토·일=매주 주말 / 이어진 3일 이상=목~일 / 하루=매주 토요일 /
  /// 나머지=월·수·금.
  static String daysLabelFor(Iterable<String> keys, {bool compact = true}) {
    final ordered = kPartyWeekdayKeys.where(keys.contains).toList();
    if (ordered.isEmpty) return '';
    if (ordered.length == 7) return '매일';
    if (_sameDays(ordered, kPartyWeekdayKeysWeekend)) return '매주 주말';
    if (_sameDays(ordered, kPartyWeekdayKeysWeekday)) {
      return compact ? '평일' : '월~금';
    }
    if (ordered.length == 1) {
      return '매주 ${kPartyWeekdayFullLabels[ordered.first]}';
    }
    // 월~일 순서로 끊김 없이 이어지는 3일 이상이면 '목~일'처럼 범위로.
    final indexes = ordered.map(kPartyWeekdayKeys.indexOf).toList();
    final contiguous = indexes.last - indexes.first == indexes.length - 1;
    if (contiguous && ordered.length >= 3) {
      return '${kPartyWeekdayLabels[ordered.first]}~${kPartyWeekdayLabels[ordered.last]}';
    }
    return ordered.map((k) => kPartyWeekdayLabels[k]!).join('·');
  }

  static bool _sameDays(List<String> a, List<String> b) =>
      a.length == b.length && a.every(b.contains);

  /// 반복 **규칙**을 말하는 요일 문구 — 저장된 요일에서 그대로 계산한다.
  ///
  /// 일곱 요일이 다 켜져 있으면 '매일', 하나뿐이면 '매주 토요일'처럼 요일
  /// 전체 이름, 여럿이면 '매주 화·목'처럼 저장된 요일을 그대로 나열한다.
  ///
  /// 목록 카드용 [daysLabelFor]와 달리 '평일'·'매주 주말'로 뭉뚱그리거나
  /// '목~일'로 범위를 만들지 않는다 — 상세는 **어느 요일에 열리는지**를 있는
  /// 그대로 보여줘야 하기 때문이다(주말 반복도 '매주 토·일'로 적힌다).
  static String ruleDaysLabelFor(Iterable<String> keys) {
    final ordered = kPartyWeekdayKeys.where(keys.contains).toList();
    if (ordered.isEmpty) return '';
    if (ordered.length == kPartyWeekdayKeys.length) return '매일';
    if (ordered.length == 1) {
      return '매주 ${kPartyWeekdayFullLabels[ordered.first]}';
    }
    return '매주 ${ordered.map((k) => kPartyWeekdayLabels[k]!).join('·')}';
  }

  /// 켜진 요일들의 **시작 시각이 모두 같으면** 그 시각, 하나라도 다르면 null.
  TimeOfDay? get commonStartTime {
    final keys = enabledDayKeys;
    if (keys.isEmpty) return null;
    final first = slotFor(keys.first).startTime;
    for (final key in keys.skip(1)) {
      final t = slotFor(key).startTime;
      if (t.hour != first.hour || t.minute != first.minute) return null;
    }
    return first;
  }

  /// 상단 '일정' 칸에 들어갈 두 줄 — 요일 묶음 + 시작 시각.
  ///
  /// 요일마다 시작 시각이 다르면 좁은 칸에 다 넣을 수 없으므로 대표 문구만
  /// 내보내고, 전체 시간표는 아래 [detailLines]가 보여준다.
  ({String days, String time}) get compactSummary {
    if (!hasEnabledDay) return (days: '', time: '');
    final start = commonStartTime;
    if (start == null) return (days: '요일별 운영', time: '시간 확인');
    return (
      days: daysLabelFor(enabledDayKeys),
      time: formatKoreanTimeOfDay(start),
    );
  }

  /// 목록 카드 한 줄 — '매일 오후 8:00' / '매주 주말 오후 7:00'.
  String get cardSummaryLabel {
    final s = compactSummary;
    if (s.days.isEmpty) return '';
    return '${s.days} ${s.time}';
  }

  /// 상세 화면 '정기 일정' 행에 그대로 들어가는 **반복 규칙 요약**.
  ///
  /// 개별 날짜(8월 22일 / 8월 23일 …)는 **절대 풀지 않는다.** 상세는 "언제마다
  /// 열리는지"만 말하고, 실제 참가 날짜는 신청 플로우의 달력에서만 고른다
  /// (party_detail_screen.dart의 _pickOccurrence). 그래서 이 목록의 길이는
  /// 회차 수와 무관하게 **시간대 종류 수**만큼이다 — 매일 열리는 파티도 한 줄이다.
  ///
  /// 예) ['매일 20:00~22:00'] / ['매주 화·목 20:00~22:00'] /
  ///     ['매주 토요일 19:00~21:00'] / ['매주 월·수·금 18:00~20:00']
  ///
  /// 요일마다 시간대가 다르면 같은 시간대끼리 묶어 한 줄씩 나뉜다.
  /// 종료일이 있으면 마지막 줄 끝에 '· 9월 30일까지'가 붙는다(날짜를 나열하는
  /// 것이 아니라 규칙이 언제까지 유효한지를 적는 것이다).
  List<String> get detailLines {
    final groups = <String, List<String>>{};
    for (final key in enabledDayKeys) {
      final slot = slotFor(key);
      final range =
          '${formatScheduleTime(slot.startTime)}~${formatScheduleTime(slot.endTime)}';
      groups.putIfAbsent(range, () => []).add(key);
    }
    final lines = [
      for (final entry in groups.entries)
        '${ruleDaysLabelFor(entry.value)} ${entry.key}',
    ];
    final end = endDate;
    if (lines.isEmpty || end == null) return lines;
    lines[lines.length - 1] = '${lines.last} · ${end.month}월 ${end.day}일까지';
    return lines;
  }

  /// '매주 월·화·수 19:00~22:00' 같은 한 줄 요약. 요일마다 시간이 다르면
  /// 시간대별로 묶어서 보여준다.
  String get summaryLabel {
    final enabled = enabledDayKeys;
    if (enabled.isEmpty) return '';
    final groups = <String, List<String>>{};
    for (final key in enabled) {
      final slot = slotFor(key);
      final range =
          '${formatScheduleTime(slot.startTime)}~${formatScheduleTime(slot.endTime)}';
      groups.putIfAbsent(range, () => []).add(kPartyWeekdayLabels[key]!);
    }
    return groups.entries
        .map((e) => '매주 ${e.value.join('·')} ${e.key}')
        .join(', ');
  }

  Map<String, dynamic> toMap() => {
    'startDate': Timestamp.fromDate(_dateOnly(startDate)),
    'endDate': endDate == null ? null : Timestamp.fromDate(_dateOnly(endDate!)),
    'weeklySchedule': {
      for (final key in kPartyWeekdayKeys)
        if (weekly[key]?.enabled == true) key: weekly[key]!.toMap(),
    },
    'registrationOpen': openRule.toMap(),
    'registrationDeadline': deadlineRule.toMap(),
  };

  /// 임시저장(Draft)용 — Timestamp 대신 밀리초 정수를 쓴다.
  Map<String, dynamic> toDraftMap() => {
    'startDateMs': _dateOnly(startDate).millisecondsSinceEpoch,
    'endDateMs': endDate == null
        ? null
        : _dateOnly(endDate!).millisecondsSinceEpoch,
    'weeklySchedule': {
      for (final key in kPartyWeekdayKeys) key: slotFor(key).toMap(),
    },
    'registrationOpen': openRule.toMap(),
    'registrationDeadline': deadlineRule.toMap(),
  };

  static PartyRecurringSchedule? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final start =
        _toDate(map['startDate']) ??
        (map['startDateMs'] is num
            ? DateTime.fromMillisecondsSinceEpoch(
                (map['startDateMs'] as num).toInt(),
              )
            : null);
    if (start == null) return null;
    final end =
        _toDate(map['endDate']) ??
        (map['endDateMs'] is num
            ? DateTime.fromMillisecondsSinceEpoch(
                (map['endDateMs'] as num).toInt(),
              )
            : null);

    final rawWeekly = map['weeklySchedule'];
    final weekly = <String, PartyWeeklySlot>{
      for (final key in kPartyWeekdayKeys)
        key: const PartyWeeklySlot.disabled(),
    };
    if (rawWeekly is Map) {
      for (final key in kPartyWeekdayKeys) {
        final slot = PartyWeeklySlot.fromMap(rawWeekly[key]);
        if (slot != null) weekly[key] = slot;
      }
    }

    final rawDeadline = map['registrationDeadline'];
    final rawOpen = map['registrationOpen'];
    return PartyRecurringSchedule(
      startDate: _dateOnly(start),
      endDate: end == null ? null : _dateOnly(end),
      weekly: weekly,
      // 모집 시작 규칙이 없던 예전 문서는 "제한 없음"(바로 모집)이었다.
      openRule: rawOpen is Map
          ? PartyRecruitDeadlineRule.fromMap(Map<String, dynamic>.from(rawOpen))
          : PartyRecruitDeadlineRule.noDeadline,
      deadlineRule: PartyRecruitDeadlineRule.fromMap(
        rawDeadline is Map ? Map<String, dynamic>.from(rawDeadline) : null,
      ),
    );
  }
}

/// 일회성 파티의 일정. 기존(레거시) 문서에는 이 맵이 없고 `partyDateTime`·
/// `recruitDeadlineAt`만 있으므로, 읽기는 항상 [PartySchedule]을 통해 한다.
@immutable
class PartySingleSchedule {
  final DateTime date;
  final TimeOfDay startTime;
  final TimeOfDay? endTime;
  final DateTime? registrationDeadline;

  /// 모집 시작 시각. null이면 제한 없음(바로 모집).
  final DateTime? registrationOpen;

  const PartySingleSchedule({
    required this.date,
    required this.startTime,
    this.endTime,
    this.registrationDeadline,
    this.registrationOpen,
  });

  DateTime get start => DateTime(
    date.year,
    date.month,
    date.day,
    startTime.hour,
    startTime.minute,
  );

  /// 자정을 넘기는 시간대(20:00~02:00)는 종료를 다음 날로 넘긴다.
  DateTime? get end {
    if (endTime == null) return null;
    var e = DateTime(
      date.year,
      date.month,
      date.day,
      endTime!.hour,
      endTime!.minute,
    );
    if (!e.isAfter(start)) e = e.add(const Duration(days: 1));
    return e;
  }

  Map<String, dynamic> toMap() => {
    'date': Timestamp.fromDate(_dateOnly(date)),
    'startTime': formatScheduleTime(startTime),
    'endTime': endTime == null ? null : formatScheduleTime(endTime!),
    'registrationDeadline': registrationDeadline == null
        ? null
        : Timestamp.fromDate(registrationDeadline!),
    'registrationOpen': registrationOpen == null
        ? null
        : Timestamp.fromDate(registrationOpen!),
  };

  static PartySingleSchedule? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final date = _toDate(map['date']);
    final start = parseScheduleTime(map['startTime']);
    if (date == null || start == null) return null;
    return PartySingleSchedule(
      date: _dateOnly(date),
      startTime: start,
      endTime: parseScheduleTime(map['endTime']),
      registrationDeadline: _toDate(map['registrationDeadline']),
      registrationOpen: _toDate(map['registrationOpen']),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 날짜 직접 선택 — 슬롯 목록
// ─────────────────────────────────────────────────────────────────────────────

int _slotIdCounter = 0;

/// 슬롯 하나를 화면에서 추적하기 위한 임시 id — Firestore에는 저장하지 않는다.
String newPartyDateSlotId() =>
    'slot_${DateTime.now().microsecondsSinceEpoch}_${_slotIdCounter++}';

String partyIsoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// "날짜 직접 선택" 방식에서 추가한 일정 한 건 — 날짜 + 시작/종료 시각.
///
/// 같은 날짜라도 시간대가 다르면 서로 다른 일정이다(8/7 15:00~18:00 과
/// 8/7 20:00~23:00 은 별개). 저장할 때는 슬롯마다 파티 문서를 하나씩 만들고
/// 같은 `seriesId`로 묶는다 — 문서 하나가 곧 일정 하나다.
@immutable
class PartyDateSlot {
  /// 리스트 위젯 키/추적용 안정 식별자. Firestore에는 저장하지 않는다.
  final String id;
  final DateTime date;
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;

  const PartyDateSlot({
    required this.id,
    required this.date,
    this.startTime,
    this.endTime,
  });

  PartyDateSlot copyWith({
    DateTime? date,
    TimeOfDay? startTime,
    bool clearStartTime = false,
    TimeOfDay? endTime,
    bool clearEndTime = false,
  }) {
    return PartyDateSlot(
      id: id,
      date: date ?? this.date,
      startTime: clearStartTime ? null : (startTime ?? this.startTime),
      endTime: clearEndTime ? null : (endTime ?? this.endTime),
    );
  }

  /// 중복 판정 키 — 날짜·시작·종료가 모두 같으면 같은 일정으로 본다.
  String get dedupeKey =>
      '${partyIsoDate(date)}|'
      '${startTime == null ? '' : formatScheduleTime(startTime!)}|'
      '${endTime == null ? '' : formatScheduleTime(endTime!)}';

  bool get isComplete => startTime != null;

  DateTime get start => DateTime(
    date.year,
    date.month,
    date.day,
    startTime?.hour ?? 0,
    startTime?.minute ?? 0,
  );

  /// 이 슬롯 하나를 문서에 저장할 형태로 — 문서마다 자기 일정만 담는다.
  PartySingleSchedule toSingleSchedule({
    DateTime? registrationDeadline,
    DateTime? registrationOpen,
  }) => PartySingleSchedule(
    date: _dateOnly(date),
    startTime: startTime ?? const TimeOfDay(hour: 0, minute: 0),
    endTime: endTime,
    registrationDeadline: registrationDeadline,
    registrationOpen: registrationOpen,
  );

  /// 임시저장(Draft)용 — Timestamp를 못 쓰므로 밀리초/문자열로 담는다.
  Map<String, dynamic> toDraftMap() => {
    'dateMs': _dateOnly(date).millisecondsSinceEpoch,
    'startTime': startTime == null ? null : formatScheduleTime(startTime!),
    'endTime': endTime == null ? null : formatScheduleTime(endTime!),
  };

  static PartyDateSlot? fromDraftMap(dynamic raw) {
    if (raw is! Map) return null;
    final ms = (raw['dateMs'] as num?)?.toInt();
    final date = ms != null
        ? DateTime.fromMillisecondsSinceEpoch(ms)
        : _toDate(raw['date']);
    if (date == null) return null;
    return PartyDateSlot(
      id: newPartyDateSlotId(),
      date: _dateOnly(date),
      startTime: parseScheduleTime(raw['startTime']),
      endTime: parseScheduleTime(raw['endTime']),
    );
  }
}

/// 등록/수정 화면이 들고 다니는 "파티 일정 입력값" 전체.
///
/// 일정 방식(날짜 직접 선택 / 매주 반복)과 그에 딸린 입력을 한 덩어리로 묶어,
/// 일반 파티 등록·플레이스+파티·숙박+파티가 **같은 값**을 주고받게 한다.
/// 화면은 이 값을 [PartyScheduleSection]에 넘기고 바뀐 값을 돌려받기만 한다.
@immutable
class PartyScheduleDraft {
  final PartyScheduleType type;

  /// 날짜 직접 선택 방식의 일정 목록.
  final List<PartyDateSlot> slots;

  /// 직접 선택 방식에서 **각 날짜에** 적용할 모집 시작 규칙.
  /// [PartyDeadlineMode.none]이면 제한 없음(등록 즉시 모집 시작).
  final PartyRecruitDeadlineRule openRule;

  /// 직접 선택 방식에서 **각 날짜에** 적용할 모집 마감 규칙.
  /// 날짜마다 자기 시작 시각에 규칙을 적용하므로 날짜별로 마감이 따로 잡힌다.
  /// (매주 반복 방식은 [recurring]이 자기 규칙을 들고 있다.)
  final PartyRecruitDeadlineRule deadlineRule;

  /// 매주 반복 방식의 규칙.
  final PartyRecurringSchedule recurring;

  const PartyScheduleDraft({
    this.type = PartyScheduleType.single,
    this.slots = const [],
    this.openRule = PartyRecruitDeadlineRule.noDeadline,
    this.deadlineRule = PartyRecruitDeadlineRule.noDeadline,
    required this.recurring,
  });

  factory PartyScheduleDraft.empty({DateTime? from}) =>
      PartyScheduleDraft(recurring: PartyRecurringSchedule.empty(from: from));

  bool get isRecurring => type == PartyScheduleType.recurring;

  PartyScheduleDraft copyWith({
    PartyScheduleType? type,
    List<PartyDateSlot>? slots,
    PartyRecruitDeadlineRule? openRule,
    PartyRecruitDeadlineRule? deadlineRule,
    PartyRecurringSchedule? recurring,
  }) {
    return PartyScheduleDraft(
      type: type ?? this.type,
      slots: slots ?? this.slots,
      openRule: openRule ?? this.openRule,
      deadlineRule: deadlineRule ?? this.deadlineRule,
      recurring: recurring ?? this.recurring,
    );
  }

  /// 지금 고른 방식에 맞는 모집 시작 규칙.
  PartyRecruitDeadlineRule get activeOpenRule =>
      isRecurring ? recurring.openRule : openRule;

  /// 지금 고른 방식에 맞는 모집 마감 규칙.
  PartyRecruitDeadlineRule get activeDeadlineRule =>
      isRecurring ? recurring.deadlineRule : deadlineRule;

  /// 입력이 덜 됐으면 사용자에게 보여줄 문구, 다 됐으면 null.
  String? get errorText {
    if (isRecurring) {
      if (!recurring.hasEnabledDay) return '운영 요일을 하나 이상 선택해줘';
      return null;
    }
    if (slots.isEmpty) return '파티 날짜와 시작 시간을 선택해줘';
    final missing = slots.indexWhere((s) => !s.isComplete);
    if (missing >= 0) return '${missing + 1}번째 날짜의 시작 시간을 선택해줘';
    return null;
  }

  bool get isValid => errorText == null;

  /// 요약 행에 보여줄 한 줄. 아직 입력이 없으면 null(= 안내 문구 표시).
  String? get summaryLabel {
    if (isRecurring) {
      final label = recurring.summaryLabel;
      return label.isEmpty ? null : label;
    }
    if (slots.isEmpty) return null;
    final first = slots.first;
    var s = formatPartyScheduleDate(first.date);
    if (first.startTime != null) {
      s += ' ${formatScheduleTime(first.startTime!)}';
      if (first.endTime != null) s += '~${formatScheduleTime(first.endTime!)}';
    }
    if (slots.length > 1) s += ' 외 ${slots.length - 1}건';
    return s;
  }

  // ── 임시저장 ────────────────────────────────────────────────────────────
  // 등록 화면 세 곳이 같은 키를 쓴다 — 어느 화면에서 임시저장했든 같은
  // 구조로 복원된다.

  Map<String, dynamic> toDraftMap() => {
    'scheduleType': type.key,
    'dateSlots': [for (final s in slots) s.toDraftMap()],
    'recruitOpenRule': openRule.toMap(),
    'recruitDeadlineRule': deadlineRule.toMap(),
    'recurringSchedule': recurring.toDraftMap(),
  };

  static PartyScheduleDraft fromDraftMap(Map<String, dynamic> p) {
    return PartyScheduleDraft(
      type: PartyScheduleType.fromKey(p['scheduleType'] as String?),
      slots: [
        for (final raw in (p['dateSlots'] as List?) ?? const [])
          ?PartyDateSlot.fromDraftMap(raw),
      ],
      openRule: p['recruitOpenRule'] is Map
          ? PartyRecruitDeadlineRule.fromMap(
              Map<String, dynamic>.from(p['recruitOpenRule'] as Map),
            )
          : PartyRecruitDeadlineRule.noDeadline,
      deadlineRule: _draftDeadlineRule(p),
      recurring:
          PartyRecurringSchedule.fromMap(
            p['recurringSchedule'] is Map
                ? Map<String, dynamic>.from(p['recurringSchedule'] as Map)
                : null,
          ) ??
          PartyRecurringSchedule.empty(),
    );
  }

  /// 임시저장에서 마감 규칙을 되살린다.
  /// 규칙이 생기기 전 임시저장은 시각 하나('18:00')만 갖고 있었고, 그 값은
  /// "각 날짜 당일 그 시각"이라는 뜻이었다 → [PartyDeadlineMode.startDayTime].
  static PartyRecruitDeadlineRule _draftDeadlineRule(Map<String, dynamic> p) {
    final raw = p['recruitDeadlineRule'];
    if (raw is Map) {
      return PartyRecruitDeadlineRule.fromMap(Map<String, dynamic>.from(raw));
    }
    return PartyRecruitDeadlineRule.fromLegacyDayTime(
      parseScheduleTime(p['recruitDeadlineTime']),
    );
  }

  /// 기존 파티 문서에서 복원 — 수정/복사 등록 화면이 쓴다.
  ///
  /// 정기 파티는 규칙을 그대로, 일회성 파티는 그 문서의 날짜 한 건을 슬롯
  /// 하나로 되살린다(여러 날짜로 등록했더라도 문서 하나에는 자기 일정만
  /// 들어 있다 — 나머지 날짜는 `seriesId`로 묶인 형제 문서들이다).
  static PartyScheduleDraft fromPartyData(Map<String, dynamic> data) {
    final type = PartySchedule.typeOf(data);
    if (type == PartyScheduleType.recurring) {
      return PartyScheduleDraft(
        type: type,
        recurring:
            PartySchedule.recurringOf(data) ?? PartyRecurringSchedule.empty(),
      );
    }
    final occ = PartySchedule.nextOccurrence(data);
    return PartyScheduleDraft(
      slots: occ == null
          ? const []
          : [
              PartyDateSlot(
                // 문서에 남아 있는 슬롯 식별자를 그대로 되살린다 — 수정
                // 저장이 "이 슬롯 = 이 문서"를 알아보는 열쇠라, 새로 발급하면
                // 같은 날짜가 새 문서로 다시 만들어진다(레거시 문서는 없으니
                // 그때만 새로 발급한다).
                id: (data['dateSlotId'] as String?)?.trim().isNotEmpty == true
                    ? data['dateSlotId'] as String
                    : newPartyDateSlotId(),
                date: _dateOnly(occ.start),
                startTime: TimeOfDay.fromDateTime(occ.start),
                endTime: occ.end.isAfter(occ.start)
                    ? TimeOfDay.fromDateTime(occ.end)
                    : null,
              ),
            ],
      deadlineRule: PartySchedule.singleDeadlineRuleOf(data, occurrence: occ),
      openRule: PartySchedule.singleOpenRuleOf(data),
      recurring: PartyRecurringSchedule.empty(),
    );
  }
}

/// '2026년 8월 7일 (금)' — 일정 목록/요약이 함께 쓰는 날짜 표기.
String formatPartyScheduleDate(DateTime? d) {
  if (d == null) return '';
  const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
  return '${d.year}년 ${d.month}월 ${d.day}일 (${weekdays[d.weekday - 1]})';
}

/// Firestore 파티 문서(Map)에서 일정을 읽는 진입점.
///
/// 목록/카드/상세/신청/마감 로직은 전부 이 클래스를 통해 "다음 회차"를 묻는다.
/// 일회성 파티면 기존 `partyDateTime`/`recruitDeadlineAt` 동작 그대로이고,
/// 정기 파티면 지금 시점 기준으로 계산된 다음 회차가 돌아온다.
class PartySchedule {
  PartySchedule._();

  /// 이 파티의 일정 유형 — **반복 여부를 판정하는 유일한 기준**이다.
  ///
  /// 문서 최상단의 `isRecurring` 불리언과 헷갈리지 말 것. 그 필드는 "매주
  /// 반복"이 아니라 **"재등록(같은 파티를 다시 열기) 가능"** 을 뜻하는 옛
  /// 이름이고, 등록 화면이 일회성 파티에도 true를 박아 넣는다(반대로 일부
  /// 콤보 등록 경로는 정기 파티에 false를 박는다). 그 필드로 반복을 판정하면
  /// 정기 파티가 일회성으로 읽혀 회차·정원·취소가 통째로 어긋난다.
  ///
  /// `scheduleType`이 없던 시절의 문서는 `recurringSchedule`의 존재로
  /// 판정한다 — 서버 functions/partySchedule.js의 isRecurringParty와 **같은
  /// 규칙**이어야 한다(한쪽만 고치면 앱과 서버가 다른 회차를 본다).
  static PartyScheduleType typeOf(Map<String, dynamic> data) {
    final key = data['scheduleType'] as String?;
    if (key == null || key.isEmpty) {
      final raw = data['recurringSchedule'];
      if (raw is Map && raw.isNotEmpty) return PartyScheduleType.recurring;
    }
    return PartyScheduleType.fromKey(key);
  }

  static bool isRecurring(Map<String, dynamic> data) =>
      typeOf(data) == PartyScheduleType.recurring;

  static PartyRecurringSchedule? recurringOf(Map<String, dynamic> data) {
    final raw = data['recurringSchedule'];
    if (raw is! Map) return null;
    return PartyRecurringSchedule.fromMap(Map<String, dynamic>.from(raw));
  }

  /// 레거시 문서까지 포함해 "이 파티의 시작 시각"을 읽는다(일회성 전용).
  static DateTime? _legacyStart(Map<String, dynamic> data) {
    final single = PartySingleSchedule.fromMap(
      data['singleSchedule'] is Map
          ? Map<String, dynamic>.from(data['singleSchedule'] as Map)
          : null,
    );
    if (single != null) return single.start;
    final ts = data['partyDateTime'];
    if (ts is Timestamp) return ts.toDate().toLocal();
    final sdt = data['startDateTime'];
    if (sdt is Timestamp) return sdt.toDate().toLocal();
    if (sdt is String && sdt.isNotEmpty)
      return DateTime.tryParse(sdt)?.toLocal();
    final s = data['date'] as String?;
    if (s != null && s.isNotEmpty) return DateTime.tryParse(s)?.toLocal();
    return null;
  }

  /// 지금(또는 [now]) 기준으로 아직 끝나지 않은 가장 가까운 회차.
  /// 일회성 파티는 그 파티 자신(이미 끝났어도 그대로) 한 건을 돌려준다.
  static PartyOccurrence? nextOccurrence(
    Map<String, dynamic> data, {
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    if (isRecurring(data)) {
      return recurringOf(data)?.nextOccurrence(at);
    }
    final single = PartySingleSchedule.fromMap(
      data['singleSchedule'] is Map
          ? Map<String, dynamic>.from(data['singleSchedule'] as Map)
          : null,
    );
    if (single != null) {
      return PartyOccurrence(
        start: single.start,
        end: single.end ?? single.start,
        deadline: single.registrationDeadline,
        recruitOpenAt: single.registrationOpen,
      );
    }
    final start = _legacyStart(data);
    if (start == null) return null;
    final dl = data['recruitDeadlineAt'];
    return PartyOccurrence(
      start: start,
      end: start,
      deadline: dl is Timestamp ? dl.toDate().toLocal() : null,
    );
  }

  /// 이 파티가 **완전히 끝나는 시각** — 보관기간(자동 삭제) 계산의 기준점.
  ///
  /// [startAt]이 "다음에 열릴 때"라면 이건 "다시는 열리지 않는 때"다.
  ///   · 정기 파티 — 마지막 회차의 종료 시각. 종료일이 없으면(무기한) null이다.
  ///   · 일회성 파티 — 종료 시각(안 적었으면 시작 시각. 레거시 문서는
  ///     `partyDateTime`).
  ///
  /// ⚠️ 서버 functions/partySchedule.js의 finalPartyEndAt과 **같은 규칙**이어야
  ///    한다 — 앱이 보여주는 '자동삭제 D-3'과 서버가 실제로 지우는 날이
  ///    어긋나면 안 된다(삭제 주체는 서버다).
  static DateTime? finalEndAt(Map<String, dynamic> data) {
    if (isRecurring(data)) {
      return recurringOf(data)?.lastOccurrence()?.end;
    }
    final single = PartySingleSchedule.fromMap(
      data['singleSchedule'] is Map
          ? Map<String, dynamic>.from(data['singleSchedule'] as Map)
          : null,
    );
    if (single != null) return single.end ?? single.start;
    return _legacyStart(data);
  }

  /// 카드·목록·정렬이 쓰는 "이 파티의 대표 시작 시각".
  /// 정기 파티는 다음 회차, 일회성은 그 파티의 시작 시각.
  /// 정기 파티의 운영 종료일이 지났으면 null(= 더 열리지 않음).
  static DateTime? startAt(Map<String, dynamic> data, {DateTime? now}) =>
      nextOccurrence(data, now: now)?.start;

  /// 다음 회차의 모집 마감 시각.
  static DateTime? deadlineAt(Map<String, dynamic> data, {DateTime? now}) =>
      nextOccurrence(data, now: now)?.deadline;

  /// [day]에 이 파티의 회차가 열리는지 — 날짜 필터/달력 점 표시에 쓴다.
  static bool occursOnDay(Map<String, dynamic> data, DateTime day) =>
      startOnDay(data, day) != null;

  /// [day]에 열리는 회차의 **시작 시각**. 그날 회차가 없으면 null.
  ///
  /// [occursOnDay]와 같은 판정이되 "열리는가" 대신 "몇 시에 열리는가"를
  /// 돌려준다 — 목록 카드가 날짜 필터에 맞는 회차 하나를 그릴 때 쓴다
  /// (요일마다 시작 시각이 다른 정기 파티도 그날의 실제 시각이 나온다).
  static DateTime? startOnDay(Map<String, dynamic> data, DateTime day) {
    if (isRecurring(data)) return recurringOf(data)?.occurrenceOn(day)?.start;
    final start = _legacyStart(data);
    if (start == null) return null;
    final sameDay =
        start.year == day.year &&
        start.month == day.month &&
        start.day == day.day;
    return sameDay ? start : null;
  }

  /// 목록에 보일 날짜들 — 정기 파티는 [horizonDays] 안의 모든 회차 날짜,
  /// 일회성은 그 하루. 메인 화면 달력의 점 표시에 쓴다.
  static List<DateTime> occurrenceDays(
    Map<String, dynamic> data, {
    DateTime? now,
    int horizonDays = 120,
  }) {
    final at = now ?? DateTime.now();
    if (isRecurring(data)) {
      final schedule = recurringOf(data);
      if (schedule == null) return const [];
      return schedule
          .occurrencesBetween(at, at.add(Duration(days: horizonDays)))
          .map((o) => DateTime(o.start.year, o.start.month, o.start.day))
          .toList();
    }
    final start = _legacyStart(data);
    if (start == null) return const [];
    return [DateTime(start.year, start.month, start.day)];
  }

  /// 상세/카드에 보여줄 일정 한 줄 요약.
  static String summaryLabel(Map<String, dynamic> data) {
    if (!isRecurring(data)) return '';
    return recurringOf(data)?.summaryLabel ?? '';
  }

  /// 상단 좁은 칸('일정')용 두 줄 요약. 일회성 파티면 빈 값.
  static ({String days, String time}) compactSummary(
    Map<String, dynamic> data,
  ) {
    if (!isRecurring(data)) return (days: '', time: '');
    return recurringOf(data)?.compactSummary ?? (days: '', time: '');
  }

  /// 목록 카드용 한 줄 요약('매일 오후 8:00'). 일회성 파티면 빈 값.
  static String cardSummaryLabel(Map<String, dynamic> data) {
    if (!isRecurring(data)) return '';
    return recurringOf(data)?.cardSummaryLabel ?? '';
  }

  /// 정기 일정 영역용 전체 시간표(여러 줄). 일회성 파티면 빈 목록.
  static List<String> detailLines(Map<String, dynamic> data) {
    if (!isRecurring(data)) return const [];
    return recurringOf(data)?.detailLines ?? const [];
  }

  /// 참가 날짜 선택에 쓸 "지금부터 신청 가능한 회차들".
  ///
  /// 아직 시작하지 않았고 모집 마감도 지나지 않은 회차만 [horizonDays] 안에서
  /// 모은다. 일회성 파티는 그 파티 한 건(아직 신청 가능하면)을 돌려준다 —
  /// 정기/일회성을 같은 화면에서 똑같이 다룰 수 있게 하기 위함이다.
  static List<PartyOccurrence> selectableOccurrences(
    Map<String, dynamic> data, {
    DateTime? now,
    int horizonDays = 60,
  }) {
    final at = now ?? DateTime.now();
    if (!isRecurring(data)) {
      final occ = nextOccurrence(data, now: at);
      if (occ == null || !occ.start.isAfter(at)) return const [];
      return [occ];
    }
    final schedule = recurringOf(data);
    if (schedule == null) return const [];
    return schedule
        .occurrencesBetween(at, at.add(Duration(days: horizonDays)))
        .where(
          (o) =>
              o.start.isAfter(at) &&
              (o.deadline == null || o.deadline!.isAfter(at)),
        )
        .toList();
  }

  /// [id]([PartyOccurrence.id], 'YYYY-MM-DD')에 해당하는 회차.
  static PartyOccurrence? occurrenceById(
    Map<String, dynamic> data,
    String id, {
    DateTime? now,
  }) {
    final day = DateTime.tryParse(id);
    if (day == null) return null;
    if (isRecurring(data)) return recurringOf(data)?.occurrenceOn(day);
    final occ = nextOccurrence(data, now: now);
    return occ != null && occ.id == id ? occ : null;
  }

  /// 등록 시 Firestore에 함께 저장할 일정 필드 묶음.
  ///
  /// 신규 `scheduleType`/`singleSchedule`/`recurringSchedule`과 함께, 기존
  /// 목록·정렬·서버 함수가 그대로 읽는 레거시 필드(`partyDateTime`,
  /// `recruitDeadlineAt`, `date`)도 같이 채운다 — 정기 파티는 "첫 회차"가
  /// 그 값이 된다.
  ///
  /// 정기 파티에는 `recruitDeadlineAt`을 저장하지 않는다. 회차마다 마감이
  /// 새로 열리는데 고정 Timestamp를 남기면 서버(applyToParty)가 첫 회차
  /// 마감 이후 모든 신청을 영구히 막아버리기 때문이다 — 마감 판정은
  /// [deadlineAt]으로 회차마다 계산한다.
  static Map<String, dynamic> buildRecurringFields(
    PartyRecurringSchedule schedule, {
    DateTime? now,
  }) {
    final first = schedule.nextOccurrence(now ?? DateTime.now());
    return {
      'scheduleType': PartyScheduleType.recurring.key,
      'recurringSchedule': schedule.toMap(),
      'singleSchedule': null,
      if (first != null) 'partyDateTime': Timestamp.fromDate(first.start),
      'recruitDeadlineAt': null,
      // 모집 시작도 회차마다 다시 계산한다 — 다음 회차 값만 캐시로 남긴다.
      'recruitOpenAt': first?.recruitOpenAt == null
          ? null
          : Timestamp.fromDate(first!.recruitOpenAt!),
      // 일회성이던 문서를 정기로 고쳤을 때 옛 규칙이 남지 않도록 함께 지운다
      // (정기 파티의 모집 규칙은 recurringSchedule 안에 들어 있다).
      'recruitDeadlineRule': null,
      'recruitOpenRule': null,
    };
  }

  /// 일회성 파티의 일정 필드 묶음.
  ///
  /// 마감은 **계산된 절대 시각**(`singleSchedule.registrationDeadline`,
  /// `recruitDeadlineAt`)과 **규칙**(`recruitDeadlineRule`)을 함께 남긴다.
  /// 절대 시각은 목록·서버 판정이 그대로 읽고, 규칙은 수정/재등록 화면이
  /// "무엇을 골랐었는지"를 되살리는 데 쓴다(날짜가 바뀌면 규칙으로 다시
  /// 계산된다). 규칙을 안 넘기면 옛 규칙이 남지 않도록 null로 덮는다.
  static Map<String, dynamic> buildSingleFields(
    PartySingleSchedule schedule, {
    PartyRecruitDeadlineRule? deadlineRule,
    PartyRecruitDeadlineRule? openRule,
  }) {
    return {
      'scheduleType': PartyScheduleType.single.key,
      'singleSchedule': schedule.toMap(),
      'recurringSchedule': null,
      'recruitDeadlineRule': deadlineRule?.toMap(),
      'recruitOpenRule': openRule?.toMap(),
      'recruitOpenAt': schedule.registrationOpen == null
          ? null
          : Timestamp.fromDate(schedule.registrationOpen!),
    };
  }

  /// 일회성 파티 문서에서 모집 마감 **규칙**을 되살린다.
  ///
  /// 규칙이 저장돼 있으면 그대로 쓰고, 규칙이 생기기 전 문서는 저장된 절대
  /// 마감 시각을 시작 시각과 견줘 가장 가까운 규칙으로 되돌린다 — 재등록처럼
  /// 날짜가 바뀌는 흐름에서 마감이 옛 날짜에 묶여 버리지 않게 하려는 것이다.
  /// 일회성 파티 문서에서 모집 **시작** 규칙을 되살린다.
  /// 규칙이 없던 문서는 제한 없음(바로 모집)이었다.
  static PartyRecruitDeadlineRule singleOpenRuleOf(Map<String, dynamic> data) {
    final raw = data['recruitOpenRule'];
    if (raw is Map) {
      return PartyRecruitDeadlineRule.fromMap(Map<String, dynamic>.from(raw));
    }
    return PartyRecruitDeadlineRule.noDeadline;
  }

  static PartyRecruitDeadlineRule singleDeadlineRuleOf(
    Map<String, dynamic> data, {
    PartyOccurrence? occurrence,
  }) {
    final raw = data['recruitDeadlineRule'];
    if (raw is Map) {
      return PartyRecruitDeadlineRule.fromMap(Map<String, dynamic>.from(raw));
    }
    final occ = occurrence ?? nextOccurrence(data);
    final deadline = occ?.deadline;
    if (occ == null || deadline == null) {
      return PartyRecruitDeadlineRule.noDeadline;
    }
    final startDay = _dateOnly(occ.start);
    final deadlineDay = _dateOnly(deadline);
    final time = TimeOfDay(hour: deadline.hour, minute: deadline.minute);
    if (deadlineDay == startDay) {
      return PartyRecruitDeadlineRule(
        mode: PartyDeadlineMode.startDayTime,
        dayTime: time,
      );
    }
    if (deadlineDay == startDay.subtract(const Duration(days: 1))) {
      return PartyRecruitDeadlineRule(
        mode: PartyDeadlineMode.prevDayTime,
        dayTime: time,
      );
    }
    return PartyRecruitDeadlineRule(
      mode: PartyDeadlineMode.customDateTime,
      customAt: deadline,
    );
  }
}

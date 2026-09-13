import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:party_app/models/party_schedule.dart';

/// 얼리버드 종료 기준 — 등록 화면의 [ 날짜 직접 선택 ] [ 파티 시작 전 ] 토글.
enum PartyEarlyBirdEndType {
  /// 특정 날짜·시각에 종료(기존 방식).
  fixedDate('fixedDate', '날짜 직접 선택'),

  /// 파티(회차) 시작 시각 기준 N일/N시간 전에 종료.
  beforeStart('beforeStart', '파티 시작 전');

  const PartyEarlyBirdEndType(this.key, this.label);
  final String key;
  final String label;

  static PartyEarlyBirdEndType fromKey(String? key) =>
      key == beforeStart.key ? beforeStart : fixedDate;
}

/// 파티 문서에서 얼리버드 종료 기준을 읽는 필드 이름.
const String kEarlyBirdEndTypeField = 'earlyBirdEndType';

/// 얼리버드 할인 **종료 시각을 정하는 방식**.
///
/// 일회성 파티는 예전처럼 특정 날짜·시각을 직접 고르지만([absolute]),
/// 정기 파티는 회차마다 날짜가 달라 고정 시각을 쓸 수 없다 — 회차 시작
/// 시각을 기준으로 매번 새로 계산하는 상대 규칙을 쓴다.
///
/// 모집 마감 규칙([PartyDeadlineMode])과 같은 패턴이며, 서버
/// `functions/partySchedule.js`의 `resolveEarlyBirdEnd`가 **동일한 규칙**을
/// 다시 구현한다. 한쪽만 고치면 "앱에는 얼리버드 가격이 보이는데 서버는
/// 정상가로 결제"하는 최악의 상태가 되므로 반드시 함께 고쳐야 한다.
enum EarlyBirdDeadlineMode {
  /// 지정한 날짜·시각에 종료 — 일회성 파티 전용(기존 방식).
  absolute('absolute'),

  /// 각 회차 시작 N일 전 지정 시각에 종료(예: 3일 전 23:59).
  daysBefore('daysBefore'),

  /// 각 회차 시작 N시간 전에 종료(예: 24시간 전).
  hoursBefore('hoursBefore'),

  /// 각 회차 당일 지정 시각에 종료(예: 당일 18:00).
  sameDayTime('sameDayTime');

  const EarlyBirdDeadlineMode(this.key);
  final String key;

  /// 정기 파티에서 고를 수 있는 방식만.
  static const List<EarlyBirdDeadlineMode> recurringModes = [
    daysBefore,
    hoursBefore,
    sameDayTime,
  ];

  static EarlyBirdDeadlineMode fromKey(String? key) {
    for (final m in EarlyBirdDeadlineMode.values) {
      if (m.key == key) return m;
    }
    return absolute;
  }
}

/// 정기 파티의 얼리버드 종료 규칙 — 회차 시작 시각에 적용해 그때그때 계산한다.
@immutable
class PartyEarlyBirdDeadlineRule {
  final EarlyBirdDeadlineMode mode;

  /// [EarlyBirdDeadlineMode.daysBefore]에서 쓰는 "며칠 전". 0이면 당일.
  final int days;

  /// [EarlyBirdDeadlineMode.hoursBefore]에서 쓰는 "몇 시간 전".
  final int hours;

  /// [EarlyBirdDeadlineMode.daysBefore]/[EarlyBirdDeadlineMode.sameDayTime]에서
  /// 쓰는 종료 시각.
  final TimeOfDay time;

  const PartyEarlyBirdDeadlineRule({
    this.mode = EarlyBirdDeadlineMode.daysBefore,
    this.days = 3,
    this.hours = 24,
    this.time = const TimeOfDay(hour: 23, minute: 59),
  });

  PartyEarlyBirdDeadlineRule copyWith({
    EarlyBirdDeadlineMode? mode,
    int? days,
    int? hours,
    TimeOfDay? time,
  }) => PartyEarlyBirdDeadlineRule(
    mode: mode ?? this.mode,
    days: days ?? this.days,
    hours: hours ?? this.hours,
    time: time ?? this.time,
  );

  /// 회차 시작 시각 [occurrenceStart]에 규칙을 적용한 실제 얼리버드 종료 시각.
  ///
  /// - `daysBefore` : 시작 **날짜**에서 N일을 뺀 날의 [time] (0일 전 = 당일)
  /// - `hoursBefore`: 시작 시각에서 N시간을 뺀 시각
  /// - `sameDayTime`: 시작 **당일**의 [time]
  ///
  /// 어떤 방식이든 결과가 회차 시작 시각을 넘으면 시작 시각으로 당긴다 —
  /// 파티가 이미 시작한 뒤에 얼리버드가 살아 있으면 안 된다.
  ///
  /// 자정을 넘겨 끝나는 파티(19:00~03:00)도 기준은 **시작 시각(19:00)**이다.
  /// 이 함수는 종료 시각을 아예 보지 않으므로 자동으로 그렇게 동작한다.
  DateTime resolve(DateTime occurrenceStart) {
    final at = switch (mode) {
      EarlyBirdDeadlineMode.absolute => occurrenceStart,
      EarlyBirdDeadlineMode.daysBefore => DateTime(
        occurrenceStart.year,
        occurrenceStart.month,
        occurrenceStart.day,
        time.hour,
        time.minute,
      ).subtract(Duration(days: days < 0 ? 0 : days)),
      EarlyBirdDeadlineMode.hoursBefore => occurrenceStart.subtract(
        Duration(hours: hours < 0 ? 0 : hours),
      ),
      EarlyBirdDeadlineMode.sameDayTime => DateTime(
        occurrenceStart.year,
        occurrenceStart.month,
        occurrenceStart.day,
        time.hour,
        time.minute,
      ),
    };
    return at.isAfter(occurrenceStart) ? occurrenceStart : at;
  }

  /// 등록 화면에 보여줄 규칙 라벨 — '파티 시작 3일 전'.
  String get label => switch (mode) {
    EarlyBirdDeadlineMode.absolute => '종료일 직접 지정',
    EarlyBirdDeadlineMode.daysBefore => days == 0 ? '파티 당일' : '파티 시작 $days일 전',
    EarlyBirdDeadlineMode.hoursBefore => '파티 시작 $hours시간 전',
    EarlyBirdDeadlineMode.sameDayTime => '파티 당일',
  };

  /// 종료 시각을 함께 고르는 방식인지(시간 선택칸을 보여줄지).
  bool get usesTime =>
      mode == EarlyBirdDeadlineMode.daysBefore ||
      mode == EarlyBirdDeadlineMode.sameDayTime;

  /// 등록 화면 미리보기 문구.
  ///
  /// 정기 파티는 회차마다 적용되므로 '각 회차', 일회성·여러 날짜 파티는
  /// 문서마다(=날짜마다) 적용되므로 '파티 시작'으로 읽는다.
  /// 예) '파티 시작 3일 전 오후 11:59까지 얼리버드 가격이 적용됩니다.'
  String previewLabelFor({required bool isRecurring}) {
    final subject = isRecurring ? '각 회차' : '파티';
    switch (mode) {
      case EarlyBirdDeadlineMode.absolute:
        return '';
      case EarlyBirdDeadlineMode.daysBefore:
        final when = days == 0 ? '$subject 당일' : '$subject 시작 $days일 전';
        return '$when ${formatKoreanTimeOfDay(time)}까지 얼리버드 가격이 적용됩니다.';
      case EarlyBirdDeadlineMode.hoursBefore:
        return '$subject 시작 $hours시간 전까지 얼리버드 가격이 적용됩니다.';
      case EarlyBirdDeadlineMode.sameDayTime:
        return '$subject 당일 ${formatKoreanTimeOfDay(time)}까지 얼리버드 가격이 적용됩니다.';
    }
  }

  /// 정기 파티 기준 미리보기(하위호환 게터).
  String get previewLabel => previewLabelFor(isRecurring: true);

  Map<String, dynamic> toMap() => {
    'mode': mode.key,
    if (mode == EarlyBirdDeadlineMode.daysBefore) 'days': days,
    if (mode == EarlyBirdDeadlineMode.hoursBefore) 'hours': hours,
    if (usesTime) 'time': formatScheduleTime(time),
  };

  static PartyEarlyBirdDeadlineRule? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final mode = EarlyBirdDeadlineMode.fromKey(map['mode'] as String?);
    if (mode == EarlyBirdDeadlineMode.absolute) return null;
    return PartyEarlyBirdDeadlineRule(
      mode: mode,
      days: (map['days'] as num?)?.toInt() ?? 3,
      hours: (map['hours'] as num?)?.toInt() ?? 24,
      time:
          parseScheduleTime(map['time']) ??
          const TimeOfDay(hour: 23, minute: 59),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PartyEarlyBirdDeadlineRule &&
      other.mode == mode &&
      other.days == days &&
      other.hours == hours &&
      other.time == time;

  @override
  int get hashCode => Object.hash(mode, days, hours, time);
}

/// 파티 문서에서 얼리버드 종료 규칙을 읽는 필드 이름.
const String kEarlyBirdRuleField = 'earlyBirdDeadlineRule';

/// 파티 문서에 저장된 얼리버드 종료 규칙(있으면).
PartyEarlyBirdDeadlineRule? earlyBirdRuleOf(Map<String, dynamic> data) {
  final raw = data[kEarlyBirdRuleField];
  return raw is Map
      ? PartyEarlyBirdDeadlineRule.fromMap(Map<String, dynamic>.from(raw))
      : null;
}

/// 파티 문서 하나의 **적용 대상 시작 시각 기준** 얼리버드 종료 시각.
///
/// - 종료 기준이 "파티 시작 전"이면 시작 시각에서 규칙만큼 뺀 시각이다.
///   - 정기 파티: [occurrenceStart]를 주면 그 회차, 없으면 [now] 기준 다음
///     회차의 시작 시각. 남은 회차가 없으면 null — 얼리버드도 적용하지 않는다.
///   - 일회성·여러 날짜 파티: 그 **문서 자신의** 시작 시각. 날짜를 여러 개
///     골라 등록하면 문서가 날짜마다 하나씩 생기므로, 각 문서가 자기 날짜를
///     기준으로 알아서 계산된다.
///   - 자정을 넘겨 끝나는 파티도 기준은 시작 시각이다(규칙이 종료 시각을
///     보지 않는다).
/// - 종료 기준이 "날짜 직접 선택"이면 저장된 `earlyBirdEndAt` 그대로.
///
/// 종료 기준 필드가 없는 예전 문서는 규칙 유무로 판별하고, 정기 파티인데
/// 규칙이 없으면 `earlyBirdEndAt`으로 폴백한다 — 예전에 정기 파티에 고정
/// 종료 시각을 넣어둔 문서가 갑자기 얼리버드를 잃지 않게 하기 위해서다.
DateTime? resolveEarlyBirdEndAt(
  Map<String, dynamic> data, {
  DateTime? now,
  DateTime? occurrenceStart,
}) {
  DateTime? absolute() {
    final ts = data['earlyBirdEndAt'];
    return ts is Timestamp ? ts.toDate().toLocal() : null;
  }

  final rule = earlyBirdRuleOf(data);
  final endType = data[kEarlyBirdEndTypeField] is String
      ? PartyEarlyBirdEndType.fromKey(data[kEarlyBirdEndTypeField] as String)
      // 예전 문서: 규칙이 있으면 상대 기준, 없으면 고정 날짜.
      : (rule != null
            ? PartyEarlyBirdEndType.beforeStart
            : PartyEarlyBirdEndType.fixedDate);

  if (endType == PartyEarlyBirdEndType.fixedDate || rule == null) {
    // 정기 파티는 고정 시각을 쓸 수 없지만, 규칙이 없는 예전 문서는 폴백한다.
    return absolute();
  }

  final start = occurrenceStart ?? PartySchedule.startAt(data, now: now);
  if (start == null) return null; // 남은 회차 없음 → 얼리버드 없음
  return rule.resolve(start);
}

/// 상세 기본 정보 카드의 '얼리버드' 행에 들어갈 값.
///
/// 문구를 새로 만들지 않는다 — `EarlyBird.statusLabel`이 돌려준 **정본**에서
/// 행 라벨('얼리버드')과 겹치는 앞머리만 덜어낼 뿐이다. 얼리버드가 언제 열리고
/// 닫히는지, 얼마가 되는지 판정하는 일은 그대로 EarlyBird가 한다.
///
///  · '얼리버드 D-2'                        → 'D-2'
///  · '얼리버드 오늘 23:59 마감'             → '오늘 23:59 마감'
///  · '8월 24일(월) 회차부터 얼리버드 할인'  → '8월 24일(월) 회차부터 할인'
///  · '얼리버드 마감'                        → '마감'
String earlyBirdInfoRowText(String statusLabel) =>
    statusLabel.replaceFirst('얼리버드 ', '').trim();

/// 상세페이지용 종료 기준 문구 — '파티 시작 3일 전까지 얼리버드'.
/// 고정 날짜 방식이거나 얼리버드가 없으면 빈 문자열.
String earlyBirdEndRuleLabel(Map<String, dynamic> data) {
  if (data['earlyBirdEnabled'] != true) return '';
  final rule = earlyBirdRuleOf(data);
  if (rule == null) return '';
  final endType = data[kEarlyBirdEndTypeField] is String
      ? PartyEarlyBirdEndType.fromKey(data[kEarlyBirdEndTypeField] as String)
      : PartyEarlyBirdEndType.beforeStart;
  if (endType != PartyEarlyBirdEndType.beforeStart) return '';
  return '${rule.label}까지 얼리버드';
}

/// 차수 얼리버드 종료 기준 선택지 — 라운드 카드(차수별 설정)와 라운드 설정
/// 영역(모든 차수 동일)이 **같은 목록**을 쓴다. 두 곳이 각자 목록을 들고
/// 있으면 한쪽에만 항목이 늘어나 "차수별로는 고를 수 있는데 공통으로는 없는"
/// 상태가 된다.
const List<PartyEarlyBirdDeadlineRule> kRoundEarlyBirdRuleOptions = [
  PartyEarlyBirdDeadlineRule(mode: EarlyBirdDeadlineMode.hoursBefore, hours: 1),
  PartyEarlyBirdDeadlineRule(mode: EarlyBirdDeadlineMode.hoursBefore, hours: 3),
  PartyEarlyBirdDeadlineRule(mode: EarlyBirdDeadlineMode.hoursBefore, hours: 6),
  PartyEarlyBirdDeadlineRule(
    mode: EarlyBirdDeadlineMode.hoursBefore,
    hours: 24,
  ),
  PartyEarlyBirdDeadlineRule(
    mode: EarlyBirdDeadlineMode.daysBefore,
    days: 3,
    time: TimeOfDay(hour: 23, minute: 59),
  ),
  PartyEarlyBirdDeadlineRule(
    mode: EarlyBirdDeadlineMode.daysBefore,
    days: 7,
    time: TimeOfDay(hour: 23, minute: 59),
  ),
];

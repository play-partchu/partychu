import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:party_app/models/party_early_bird_schedule.dart';
import 'package:party_app/models/party_schedule.dart' show formatScheduleTime;

/// 얼리버드 할인 — 등록 화면들이 공유하는 모델.
///
/// 종료 기준은 두 가지 중 하나다([PartyEarlyBirdEndType]).
///
/// 1. **날짜 직접 선택**(`fixedDate`) — 특정 날짜·시각에 종료. 기존 방식.
/// ```
/// earlyBirdEnabled: true,
/// earlyBirdDiscountPercent: 10,
/// earlyBirdEndType: 'fixedDate',
/// earlyBirdEndAt: Timestamp,
/// ```
/// 2. **파티 시작 전**(`beforeStart`) — 시작 시각 기준 상대 규칙. 회차/날짜마다
///    종료 시각이 자동으로 새로 계산된다.
/// ```
/// earlyBirdEndType: 'beforeStart',
/// earlyBirdDeadlineRule: { mode: 'daysBefore', days: 3, time: '23:59' },
/// ```
/// (요청서의 `beforeStartValue`/`beforeStartUnit`은 이 규칙의
/// `days`/`hours` + `mode`가 그대로 담당한다 — 필드를 새로 만들면 같은 값의
/// 출처가 둘이 되므로 기존 규칙 하나로 통일했다.)
///
/// 두 방식이 한 문서에 섞이지 않도록 반대쪽 필드는 명시적으로 null로 쓴다.
/// `earlyBirdEndType`이 없는 예전 문서는 규칙 유무로 판별한다 — 규칙이 있으면
/// `beforeStart`, 없으면 `fixedDate`(하위 호환).
///
/// 정기 파티는 회차마다 날짜가 달라 고정 시각을 쓸 수 없으므로 항상
/// `beforeStart`다.
///
/// 실제 할인 적용 계산은 클라이언트 [EarlyBird](lib/utils/early_bird.dart)와
/// 서버 `computeAppliedFee`가 이 필드들을 읽어서 한다 — 이 클래스는 등록
/// 화면의 입력 상태와 검증·직렬화만 담당한다.
@immutable
class PartyEarlyBird {
  final bool enabled;

  /// 할인율(%). 1~99만 유효하다.
  final int? percent;

  /// 종료 기준.
  final PartyEarlyBirdEndType endType;

  /// 할인 종료 시각(날짜 + 시간) — [PartyEarlyBirdEndType.fixedDate]에서만 쓴다.
  final DateTime? endDate;
  final TimeOfDay? endTime;

  /// 시작 시각 기준 상대 규칙 — [PartyEarlyBirdEndType.beforeStart]에서만 쓴다.
  /// 일회성·여러 날짜 파티는 그 문서 자신의 시작 시각에, 정기 파티는 각 회차
  /// 시작 시각에 적용된다.
  final PartyEarlyBirdDeadlineRule beforeStartRule;

  const PartyEarlyBird({
    this.enabled = false,
    this.percent,
    this.endType = PartyEarlyBirdEndType.fixedDate,
    this.endDate,
    this.endTime,
    this.beforeStartRule = const PartyEarlyBirdDeadlineRule(),
  });

  const PartyEarlyBird.off() : this();

  PartyEarlyBird copyWith({
    bool? enabled,
    int? percent,
    bool clearPercent = false,
    PartyEarlyBirdEndType? endType,
    DateTime? endDate,
    TimeOfDay? endTime,
    PartyEarlyBirdDeadlineRule? beforeStartRule,
  }) {
    return PartyEarlyBird(
      enabled: enabled ?? this.enabled,
      percent: clearPercent ? null : (percent ?? this.percent),
      endType: endType ?? this.endType,
      endDate: endDate ?? this.endDate,
      endTime: endTime ?? this.endTime,
      beforeStartRule: beforeStartRule ?? this.beforeStartRule,
    );
  }

  /// 정기 파티는 고정 종료 시각을 쓸 수 없으므로 항상 상대 규칙이다.
  PartyEarlyBirdEndType effectiveEndTypeFor({required bool isRecurring}) =>
      isRecurring ? PartyEarlyBirdEndType.beforeStart : endType;

  /// 날짜+시간을 합친 종료 시각. 둘 중 하나라도 없으면 null.
  DateTime? get endAt {
    if (endDate == null || endTime == null) return null;
    return DateTime(
      endDate!.year,
      endDate!.month,
      endDate!.day,
      endTime!.hour,
      endTime!.minute,
    );
  }

  /// 실제로 저장될 수 있는 상태인지.
  ///
  /// "날짜 직접 선택"은 종료 시각이 완성돼야 하고, "파티 시작 전"은 규칙이
  /// 항상 완성돼 있으므로 켜져 있기만 하면 된다.
  bool isEffectiveFor({required bool isRecurring}) {
    if (!enabled) return false;
    return effectiveEndTypeFor(isRecurring: isRecurring) ==
            PartyEarlyBirdEndType.beforeStart ||
        endAt != null;
  }

  /// 일회성 기준 하위호환 게터(기존 호출부 유지).
  bool get isEffective => isEffectiveFor(isRecurring: false);

  /// 입력값 검증. 문제가 없으면 null, 있으면 사용자에게 보여줄 문구를 돌려준다.
  ///
  /// [isFree]는 참가비가 0원인지 — 무료 파티에는 할인이 의미가 없다.
  /// [occurrenceStart]/[recruitDeadline]을 주면 "얼리버드가 모집 마감보다
  /// 늦게 끝나는" 설정을 저장 단계에서 막는다.
  String? validate({
    required bool isFree,
    bool isRecurring = false,
    DateTime? now,
    DateTime? occurrenceStart,
    DateTime? recruitDeadline,
  }) {
    if (!enabled) return null;
    if (percent == null || percent! < 1 || percent! > 99) {
      return '얼리버드 할인율은 1~99% 사이로 입력해주세요.';
    }
    if (isFree) return '무료 파티는 얼리버드 할인을 사용할 수 없습니다.';

    final type = effectiveEndTypeFor(isRecurring: isRecurring);
    if (type == PartyEarlyBirdEndType.fixedDate) {
      final at = endAt;
      if (at == null) return '얼리버드 종료일과 시간을 선택해주세요.';
      if (!at.isAfter(now ?? DateTime.now())) {
        return '얼리버드 종료 시각은 현재 시간 이후여야 합니다.';
      }
    } else {
      if (beforeStartRule.mode == EarlyBirdDeadlineMode.daysBefore &&
          beforeStartRule.days < 0) {
        return '얼리버드 종료 기준일은 0일 이상이어야 합니다.';
      }
      if (beforeStartRule.mode == EarlyBirdDeadlineMode.hoursBefore &&
          beforeStartRule.hours < 1) {
        return '얼리버드 종료 기준 시간은 1시간 이상이어야 합니다.';
      }
    }

    // 얼리버드가 모집 마감보다 늦게 끝나면 "신청도 못 하는데 할인만 살아 있는"
    // 상태가 된다 — 저장 단계에서 막는다.
    if (occurrenceStart != null && recruitDeadline != null) {
      final ebEnd = type == PartyEarlyBirdEndType.beforeStart
          ? beforeStartRule.resolve(occurrenceStart)
          : endAt;
      if (ebEnd != null && ebEnd.isAfter(recruitDeadline)) {
        return '얼리버드 종료가 모집 마감보다 늦습니다. 종료 기준을 앞당겨주세요.';
      }
    }
    return null;
  }

  /// 요약 문구 — 꺼져 있으면 null.
  /// 날짜 직접 선택: '얼리버드 10% · 8월 15일 20:00까지'
  /// 파티 시작 전  : '얼리버드 10% · 파티 시작 3일 전 23:59까지'
  String? summaryFor({required bool isRecurring}) {
    if (!isEffectiveFor(isRecurring: isRecurring)) return null;
    if (effectiveEndTypeFor(isRecurring: isRecurring) ==
        PartyEarlyBirdEndType.beforeStart) {
      final r = beforeStartRule;
      final when = r.usesTime
          ? '${r.label} ${formatScheduleTime(r.time)}'
          : r.label;
      return '얼리버드 $percent% · $when까지';
    }
    final at = endAt!;
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    return '얼리버드 $percent% · ${at.month}월 ${at.day}일 $hh:$mm까지';
  }

  String? get summary => summaryFor(isRecurring: false);

  /// 문서에 저장할 필드. 종료 기준에 따라 **한쪽 방식만** 기록한다 —
  /// 두 방식이 한 문서에 섞이면 어느 쪽이 진짜인지 알 수 없어진다.
  Map<String, dynamic> toMapFor({required bool isRecurring}) {
    final on = isEffectiveFor(isRecurring: isRecurring);
    final type = effectiveEndTypeFor(isRecurring: isRecurring);
    final useRule = type == PartyEarlyBirdEndType.beforeStart;
    return {
      'earlyBirdEnabled': on,
      'earlyBirdDiscountPercent': on ? percent : null,
      kEarlyBirdEndTypeField: on ? type.key : null,
      // 날짜 직접 선택: 고정 종료 시각 / 파티 시작 전: 규칙.
      // 반대쪽은 명시적으로 null.
      'earlyBirdEndAt': on && !useRule ? Timestamp.fromDate(endAt!) : null,
      kEarlyBirdRuleField: on && useRule ? beforeStartRule.toMap() : null,
    };
  }

  Map<String, dynamic> toMap() => toMapFor(isRecurring: false);

  Map<String, dynamic> toDraftMap() => {
    'earlyBirdEnabled': enabled,
    'earlyBirdPercent': percent,
    'earlyBirdEndType': endType.key,
    'earlyBirdEndDateMs': endDate?.millisecondsSinceEpoch,
    'earlyBirdEndTime': endTime == null
        ? null
        : {'h': endTime!.hour, 'm': endTime!.minute},
    'earlyBirdRecurringRule': beforeStartRule.toMap(),
  };

  /// 저장된 문서에서 복원(수정 화면 등).
  ///
  /// "날짜 직접 선택"은 종료 시각이 이미 지난 할인을 꺼진 상태로 돌려준다 —
  /// 재등록 시 지난 할인이 그대로 켜져 있으면 안 되기 때문이다. "파티 시작 전"
  /// 은 파티/회차마다 다시 열리므로 "지났다"는 개념이 없어 그대로 살린다.
  static PartyEarlyBird fromMap(Map<String, dynamic>? map, {DateTime? now}) {
    if (map == null) return const PartyEarlyBird.off();
    if (map['earlyBirdEnabled'] != true) return const PartyEarlyBird.off();
    final percent = (map['earlyBirdDiscountPercent'] as num?)?.toInt() ?? 10;

    final ruleRaw = map[kEarlyBirdRuleField];
    final rule = ruleRaw is Map
        ? PartyEarlyBirdDeadlineRule.fromMap(Map<String, dynamic>.from(ruleRaw))
        : null;
    // endType이 없는 예전 문서는 규칙 유무로 판별한다(하위 호환).
    final type = map[kEarlyBirdEndTypeField] is String
        ? PartyEarlyBirdEndType.fromKey(map[kEarlyBirdEndTypeField] as String)
        : (rule != null
              ? PartyEarlyBirdEndType.beforeStart
              : PartyEarlyBirdEndType.fixedDate);

    if (type == PartyEarlyBirdEndType.beforeStart && rule != null) {
      return PartyEarlyBird(
        enabled: true,
        percent: percent,
        endType: PartyEarlyBirdEndType.beforeStart,
        beforeStartRule: rule,
      );
    }

    final ts = map['earlyBirdEndAt'];
    final at = ts is Timestamp ? ts.toDate() : null;
    if (at == null || !at.isAfter(now ?? DateTime.now())) {
      return const PartyEarlyBird.off();
    }
    return PartyEarlyBird(
      enabled: true,
      percent: percent,
      endDate: DateTime(at.year, at.month, at.day),
      endTime: TimeOfDay(hour: at.hour, minute: at.minute),
    );
  }

  /// 임시저장 복원 — 시간이 지났는지는 따지지 않는다(작성 중이던 값 그대로).
  static PartyEarlyBird fromDraftMap(Map<String, dynamic>? map) {
    if (map == null) return const PartyEarlyBird.off();
    final ms = (map['earlyBirdEndDateMs'] as num?)?.toInt();
    final rawTime = map['earlyBirdEndTime'];
    final ruleRaw = map['earlyBirdRecurringRule'];
    return PartyEarlyBird(
      enabled: map['earlyBirdEnabled'] as bool? ?? false,
      percent: (map['earlyBirdPercent'] as num?)?.toInt(),
      // 종료 기준이 없던 예전 임시저장은 날짜 직접 선택으로 복원된다.
      endType: PartyEarlyBirdEndType.fromKey(
        map['earlyBirdEndType'] as String?,
      ),
      endDate: ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
      endTime: rawTime is Map
          ? TimeOfDay(
              hour: (rawTime['h'] as num?)?.toInt() ?? 0,
              minute: (rawTime['m'] as num?)?.toInt() ?? 0,
            )
          : null,
      beforeStartRule:
          (ruleRaw is Map
              ? PartyEarlyBirdDeadlineRule.fromMap(
                  Map<String, dynamic>.from(ruleRaw),
                )
              : null) ??
          const PartyEarlyBirdDeadlineRule(),
    );
  }

  /// "이 파티를 기반으로 이벤트 등록"처럼 정기 → 일회성으로 복사할 때 쓴다.
  ///
  /// "파티 시작 전" 기준은 일회성에서도 그대로 쓸 수 있으므로 유지하고,
  /// "날짜 직접 선택"이었다면 종료 시각만 비워 새로 고르게 한다.
  PartyEarlyBird toOneOffTemplate() => PartyEarlyBird(
    enabled: enabled,
    percent: percent,
    endType: endType,
    beforeStartRule: beforeStartRule,
    // endDate/endTime 의도적으로 비움 — 새로 지정해야 저장된다.
  );

  @override
  bool operator ==(Object other) =>
      other is PartyEarlyBird &&
      other.enabled == enabled &&
      other.percent == percent &&
      other.endType == endType &&
      other.endDate == endDate &&
      other.endTime == endTime &&
      other.beforeStartRule == beforeStartRule;

  @override
  int get hashCode =>
      Object.hash(enabled, percent, endType, endDate, endTime, beforeStartRule);
}

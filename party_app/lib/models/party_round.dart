import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:party_app/models/party_capacity_status.dart';
import 'package:party_app/models/party_early_bird.dart';
import 'package:party_app/models/party_schedule.dart';

/// 차수(라운드) 한 건의 상태 — 카드에 뱃지로 그대로 보여준다.
enum PartyRoundStatus {
  /// 모집 시작 시각이 아직 오지 않음.
  upcoming('모집 예정'),

  /// 지금 신청받는 중.
  open('모집 중'),

  /// 모집이 닫혔고 아직 시작 전.
  closed('모집 마감'),

  /// 시작했고 아직 안 끝남.
  ongoing('진행 중'),

  /// 종료 시각을 지남.
  ended('종료');

  const PartyRoundStatus(this.label);
  final String label;
}

/// 차수 하나를 어떤 날짜에 적용했을 때 실제로 잡히는 일정 — 모집 창구와
/// 파티 시간이 모두 절대 시각으로 계산돼 있다.
@immutable
class PartyRoundWindow {
  final DateTime start;
  final DateTime end;

  /// 모집 시작 시각. null이면 "언제든 신청 가능"(제한 없음).
  final DateTime? recruitOpenAt;

  /// 모집 마감 시각. null이면 마감 없이 계속 모집(화면 문구는 '제한 없음').
  final DateTime? recruitCloseAt;

  const PartyRoundWindow({
    required this.start,
    required this.end,
    this.recruitOpenAt,
    this.recruitCloseAt,
  });

  /// 파티가 시작된 뒤에도 신청을 받는 설정인지 — 안내 문구를 띄울지 판단한다.
  bool get acceptsAfterStart =>
      recruitCloseAt != null && recruitCloseAt!.isAfter(start);

  /// [now] 시점에 신청을 받을 수 있는지.
  bool isRecruitingAt(DateTime now) {
    if (recruitOpenAt != null && now.isBefore(recruitOpenAt!)) return false;
    if (recruitCloseAt != null && !now.isBefore(recruitCloseAt!)) return false;
    // 마감을 따로 두지 않았으면 시작 시각까지 받는다.
    if (recruitCloseAt == null && !now.isBefore(start)) return false;
    return true;
  }

  PartyRoundStatus statusAt(DateTime now) {
    if (!now.isBefore(end)) return PartyRoundStatus.ended;
    if (isRecruitingAt(now)) return PartyRoundStatus.open;
    if (!now.isBefore(start)) return PartyRoundStatus.ongoing;
    if (recruitOpenAt != null && now.isBefore(recruitOpenAt!)) {
      return PartyRoundStatus.upcoming;
    }
    return PartyRoundStatus.closed;
  }
}

/// 차수(라운드) 한 건.
///
/// 예전에는 2차 이상이 "시작 시각"만 갖고 있어서, 실제 운영에 필요한 모집
/// 시작·마감을 차수별로 따로 둘 수 없었다(문서 전체에 마감이 하나뿐이었다).
/// 지금은 차수마다 모집 창구·일정·정원·참가비·얼리버드를 전부 자기가 들고
/// 있어 독립적으로 운영된다.
///
/// 시각은 **날짜가 아니라 시각(TimeOfDay)과 규칙**으로 담는다 — 날짜를 여러 개
/// 고른 파티(슬롯마다 문서 하나)와 정기 파티(회차마다 날짜가 다름)에서 같은
/// 차수 구성을 그대로 재사용해야 하기 때문이다. 실제 절대 시각은
/// [resolveOn]이 그 날짜에 맞춰 계산한다.
@immutable
class PartyRound {
  final String id;

  /// 비워두면 'N차'로 저장된다.
  final String label;

  /// 이 차수의 파티 시작 시각.
  final TimeOfDay startTime;

  /// 이 차수의 파티 종료 시각. 시작보다 이르거나 같으면 다음 날로 넘긴다.
  final TimeOfDay? endTime;

  /// 모집 시작 규칙. [PartyDeadlineMode.none]이면 제한 없음(바로 모집 시작).
  final PartyRecruitDeadlineRule openRule;

  /// 모집 마감 규칙.
  final PartyRecruitDeadlineRule closeRule;

  /// 최소 모집 인원. 0이면 정하지 않은 것.
  final int minCapacity;

  final int maxCapacity;
  final int maleCapacity;
  final int femaleCapacity;
  final int maleFee;
  final int femaleFee;

  /// 차수별 얼리버드. 차수마다 날짜가 다르므로 종료 기준은 늘 "시작 전" 규칙을
  /// 쓴다([PartyEarlyBirdEndType.beforeStart]).
  final PartyEarlyBird earlyBird;

  const PartyRound({
    required this.id,
    this.label = '',
    this.startTime = const TimeOfDay(hour: 21, minute: 0),
    this.endTime,
    this.openRule = PartyRecruitDeadlineRule.noDeadline,
    this.closeRule = const PartyRecruitDeadlineRule(),
    this.minCapacity = 0,
    this.maxCapacity = 0,
    this.maleCapacity = 0,
    this.femaleCapacity = 0,
    this.maleFee = 0,
    this.femaleFee = 0,
    this.earlyBird = const PartyEarlyBird.off(),
  });

  static int _idCounter = 0;

  /// 화면에서 카드를 추적하기 위한 임시 id — Firestore에도 함께 저장해 수정
  /// 저장에서 "이 카드 = 이 차수"를 알아본다.
  static String newId() =>
      'round_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';

  PartyRound copyWith({
    String? id,
    String? label,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    bool clearEndTime = false,
    PartyRecruitDeadlineRule? openRule,
    PartyRecruitDeadlineRule? closeRule,
    int? minCapacity,
    int? maxCapacity,
    int? maleCapacity,
    int? femaleCapacity,
    int? maleFee,
    int? femaleFee,
    PartyEarlyBird? earlyBird,
  }) {
    return PartyRound(
      id: id ?? this.id,
      label: label ?? this.label,
      startTime: startTime ?? this.startTime,
      endTime: clearEndTime ? null : (endTime ?? this.endTime),
      openRule: openRule ?? this.openRule,
      closeRule: closeRule ?? this.closeRule,
      minCapacity: minCapacity ?? this.minCapacity,
      maxCapacity: maxCapacity ?? this.maxCapacity,
      maleCapacity: maleCapacity ?? this.maleCapacity,
      femaleCapacity: femaleCapacity ?? this.femaleCapacity,
      maleFee: maleFee ?? this.maleFee,
      femaleFee: femaleFee ?? this.femaleFee,
      earlyBird: earlyBird ?? this.earlyBird,
    );
  }

  /// 다른 차수의 설정을 그대로 복사한다(시간·가격·인원·모집 규칙·얼리버드).
  /// id와 이름은 이 차수 것을 지킨다 — 복사한 뒤 개별로 다시 고칠 수 있다.
  PartyRound copyingSettingsFrom(PartyRound other) => PartyRound(
    id: id,
    label: label,
    startTime: other.startTime,
    endTime: other.endTime,
    openRule: other.openRule,
    closeRule: other.closeRule,
    minCapacity: other.minCapacity,
    maxCapacity: other.maxCapacity,
    maleCapacity: other.maleCapacity,
    femaleCapacity: other.femaleCapacity,
    maleFee: other.maleFee,
    femaleFee: other.femaleFee,
    earlyBird: other.earlyBird,
  );

  String labelFor(int roundNumber) =>
      label.trim().isEmpty ? '$roundNumber차' : label.trim();

  /// [partyDate](그 날짜 슬롯/회차의 날짜)에 이 차수를 적용한 실제 일정.
  PartyRoundWindow resolveOn(DateTime partyDate) {
    final start = DateTime(
      partyDate.year,
      partyDate.month,
      partyDate.day,
      startTime.hour,
      startTime.minute,
    );
    final e = endTime;
    var end = e == null
        ? start.add(const Duration(hours: 2))
        : DateTime(
            partyDate.year,
            partyDate.month,
            partyDate.day,
            e.hour,
            e.minute,
          );
    // 자정을 넘기는 시간대(21:00~01:00)는 종료를 다음 날로 넘긴다.
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));

    return PartyRoundWindow(
      start: start,
      end: end,
      recruitOpenAt: openRule.resolve(start, occurrenceEnd: end),
      recruitCloseAt: closeRule.resolve(start, occurrenceEnd: end),
    );
  }

  /// 입력이 덜 됐거나 앞뒤가 맞지 않으면 그 목록을 돌려준다.
  /// [perRound]가 false면 정원·참가비는 1차 값을 따르므로 검사하지 않는다.
  List<PartyRoundIssue> validate({
    required int roundNumber,
    required bool perRound,
    required bool separateGender,
    required DateTime partyDate,
    required bool isFree,
  }) {
    final issues = <PartyRoundIssue>[];
    final w = resolveOn(partyDate);

    if (endTime == null) {
      issues.add(
        PartyRoundIssue(
          field: PartyRoundField.schedule,
          message: '$roundNumber차 파티 종료 시간을 선택해주세요.',
        ),
      );
    }
    // 모집 시작 < 모집 마감.
    final openAt = w.recruitOpenAt;
    final closeAt = w.recruitCloseAt;
    if (openAt != null && closeAt != null && !openAt.isBefore(closeAt)) {
      issues.add(
        PartyRoundIssue(
          field: PartyRoundField.recruit,
          message: '$roundNumber차 모집 시작이 모집 마감보다 늦습니다. 다시 설정해주세요.',
        ),
      );
    }
    // 모집 마감이 종료 뒤로 넘어가면 "이미 끝난 파티를 모집"하는 꼴이 된다.
    if (closeAt != null && closeAt.isAfter(w.end)) {
      issues.add(
        PartyRoundIssue(
          field: PartyRoundField.recruit,
          message: '$roundNumber차 모집 마감은 파티 종료 전이어야 합니다.',
        ),
      );
    }

    if (perRound) {
      final capacityOk = separateGender
          ? (maleCapacity > 0 || femaleCapacity > 0)
          : maxCapacity > 0;
      if (!capacityOk) {
        issues.add(
          PartyRoundIssue(
            field: PartyRoundField.capacity,
            message: '$roundNumber차 모집 인원을 입력해주세요.',
          ),
        );
      }
      // 최소 ≤ 최대. 남녀를 따로 받으면 합계가 최대다.
      final minError = PartyCapacityStatus.validate(
        min: minCapacity,
        max: separateTotal,
      );
      if (minError != null) {
        issues.add(
          PartyRoundIssue(
            field: PartyRoundField.capacity,
            message: '$roundNumber차 — $minError',
          ),
        );
      }
      if (maleFee % 1000 != 0 || femaleFee % 1000 != 0) {
        issues.add(
          PartyRoundIssue(
            field: PartyRoundField.fee,
            message: '$roundNumber차 참가비를 1,000원 단위로 입력해주세요. (무료면 0)',
          ),
        );
      }
    }

    final ebError = earlyBird.validate(
      isFree: perRound ? (maleFee == 0 && femaleFee == 0) : isFree,
      isRecurring: true, // 차수는 날짜가 바뀌므로 늘 "시작 전" 규칙을 쓴다.
      occurrenceStart: w.start,
      recruitDeadline: closeAt,
    );
    if (ebError != null) {
      issues.add(
        PartyRoundIssue(
          field: PartyRoundField.earlyBird,
          message: '$roundNumber차 얼리버드 — $ebError',
        ),
      );
    }
    return issues;
  }

  /// Firestore `parties.rounds` 배열 원소.
  ///
  /// 절대 시각(`time`/`endAt`/`recruitOpenAt`/`recruitCloseAt`)과 **규칙**을
  /// 함께 남긴다. 절대 시각은 앱·서버가 그대로 읽어 판정하고, 규칙은
  /// 수정·재등록에서 날짜가 바뀌었을 때 다시 계산하는 데 쓴다.
  Map<String, dynamic> toMap({
    required int roundNumber,
    required DateTime partyDate,
    required bool perRound,
  }) {
    final w = resolveOn(partyDate);
    return {
      'id': id,
      'roundNumber': roundNumber,
      'label': labelFor(roundNumber),
      // 'time'은 예전 이름 그대로 — 이 값을 읽는 화면/서버가 이미 여럿이다.
      'time': Timestamp.fromDate(w.start),
      'endAt': Timestamp.fromDate(w.end),
      'startTime': formatScheduleTime(startTime),
      'endTime': endTime == null ? null : formatScheduleTime(endTime!),
      'recruitOpenAt': w.recruitOpenAt == null
          ? null
          : Timestamp.fromDate(w.recruitOpenAt!),
      'recruitCloseAt': w.recruitCloseAt == null
          ? null
          : Timestamp.fromDate(w.recruitCloseAt!),
      'recruitOpenRule': openRule.toMap(),
      'recruitCloseRule': closeRule.toMap(),
      if (perRound) ...{
        'minCapacity': minCapacity,
        'maxCapacity': separateTotal,
        'maleCapacity': maleCapacity,
        'femaleCapacity': femaleCapacity,
        'currentParticipants': 0,
        'currentMaleCount': 0,
        'currentFemaleCount': 0,
        'maleFee': maleFee,
        'femaleFee': femaleFee,
        ...earlyBird.toMapFor(isRecurring: true),
      },
    };
  }

  /// 남녀 정원을 따로 받는 모드에서는 합계가 곧 최대 인원이다.
  int get separateTotal => (maleCapacity > 0 || femaleCapacity > 0)
      ? maleCapacity + femaleCapacity
      : maxCapacity;

  /// 임시저장용 — Timestamp를 쓸 수 없어 시각/규칙만 담는다(날짜는 일정에서
  /// 따로 복원되므로 여기 넣지 않는다).
  Map<String, dynamic> toDraftMap() => {
    'id': id,
    'label': label,
    'startTime': formatScheduleTime(startTime),
    'endTime': endTime == null ? null : formatScheduleTime(endTime!),
    'recruitOpenRule': openRule.toMap(),
    'recruitCloseRule': closeRule.toMap(),
    'minCapacity': minCapacity,
    'maxCapacity': maxCapacity,
    'maleCapacity': maleCapacity,
    'femaleCapacity': femaleCapacity,
    'maleFee': maleFee,
    'femaleFee': femaleFee,
    'earlyBird': earlyBird.toDraftMap(),
  };

  /// 저장된 문서/임시저장에서 복원. 두 포맷을 한 곳에서 읽는다 —
  /// 문서는 절대 시각과 규칙을, 임시저장은 시각과 규칙만 갖고 있다.
  static PartyRound? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);

    // 시각: 새 문서는 'startTime'(HH:mm), 예전 문서는 'time'(Timestamp)만 있다.
    final startTime =
        parseScheduleTime(m['startTime']) ?? _timeOfTimestamp(m['time']);
    if (startTime == null) return null;
    final endTime =
        parseScheduleTime(m['endTime']) ?? _timeOfTimestamp(m['endAt']);

    final openRaw = m['recruitOpenRule'];
    final closeRaw = m['recruitCloseRule'];
    return PartyRound(
      id: (m['id'] as String?)?.trim().isNotEmpty == true
          ? m['id'] as String
          : newId(),
      label: m['label'] as String? ?? '',
      startTime: startTime,
      endTime: endTime,
      openRule: openRaw is Map
          ? PartyRecruitDeadlineRule.fromMap(Map<String, dynamic>.from(openRaw))
          : PartyRecruitDeadlineRule.noDeadline,
      closeRule: closeRaw is Map
          ? PartyRecruitDeadlineRule.fromMap(
              Map<String, dynamic>.from(closeRaw),
            )
          // 차수별 마감이 없던 예전 문서는 "마감 없음"으로 되살린다 — 문서
          // 전체 마감(recruitDeadlineAt)이 그 역할을 하고 있었다.
          : PartyRecruitDeadlineRule.noDeadline,
      minCapacity: (m['minCapacity'] as num?)?.toInt() ?? 0,
      maxCapacity: (m['maxCapacity'] as num?)?.toInt() ?? 0,
      maleCapacity: (m['maleCapacity'] as num?)?.toInt() ?? 0,
      femaleCapacity: (m['femaleCapacity'] as num?)?.toInt() ?? 0,
      maleFee: (m['maleFee'] as num?)?.toInt() ?? 0,
      femaleFee: (m['femaleFee'] as num?)?.toInt() ?? 0,
      earlyBird: _earlyBirdOf(m),
    );
  }

  /// 얼리버드는 문서('earlyBird*' 평면 키)와 임시저장('earlyBird' 맵) 모양이
  /// 달라 둘 다 받아준다.
  static PartyEarlyBird _earlyBirdOf(Map<String, dynamic> m) {
    final draft = m['earlyBird'];
    if (draft is Map) {
      return PartyEarlyBird.fromDraftMap(Map<String, dynamic>.from(draft));
    }
    if (m.containsKey('earlyBirdEnabled')) return PartyEarlyBird.fromMap(m);
    return const PartyEarlyBird.off();
  }

  static TimeOfDay? _timeOfTimestamp(dynamic raw) {
    if (raw is Timestamp) {
      final d = raw.toDate();
      return TimeOfDay(hour: d.hour, minute: d.minute);
    }
    return null;
  }
}

/// 라운드 카드에서 문제가 난 칸.
enum PartyRoundField { schedule, recruit, capacity, fee, earlyBird }

@immutable
class PartyRoundIssue {
  final PartyRoundField field;
  final String message;

  const PartyRoundIssue({required this.field, required this.message});
}

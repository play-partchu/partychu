import 'package:flutter/foundation.dart';

/// 최소 모집 인원에 못 미친 채 모집이 마감됐을 때 어떻게 할지.
enum PartyMinCapacityPolicy {
  /// 그대로 진행한다(기본값) — 예전 파티는 전부 이 동작이었다.
  proceed(
    'proceed',
    '정상 진행',
    '최소 인원에 못 미쳐도 파티를 그대로 열어요.',
    '최소 인원에 못 미쳐도 그 회차를 그대로 열어요.',
  ),

  /// 모집 마감 시점에 최소 인원 미달이면 파티를 자동으로 취소한다.
  /// 정기 파티는 **미달된 그 회차 하나만** 취소된다.
  autoCancel(
    'autoCancel',
    '자동 취소',
    '모집 마감 때 최소 인원에 못 미치면 파티가 자동 취소되고 전액 환불돼요.',
    '회차 모집 마감 때 최소 인원에 못 미치면 그 회차만 자동 취소되고 전액 환불돼요. '
        '다른 날짜 회차는 그대로 열려요.',
  );

  const PartyMinCapacityPolicy(
    this.key,
    this.label,
    this.description,
    this.recurringDescription,
  );

  /// Firestore `minCapacityPolicy` 필드에 저장되는 값.
  final String key;
  final String label;
  final String description;

  /// 정기 파티용 설명 — 취소 단위가 파티 문서 전체가 아니라 회차 하나다.
  final String recurringDescription;

  bool get isAutoCancel => this == PartyMinCapacityPolicy.autoCancel;

  /// 값이 없던 예전 문서는 전부 '정상 진행'이다.
  static PartyMinCapacityPolicy fromKey(String? key) {
    for (final p in PartyMinCapacityPolicy.values) {
      if (p.key == key) return p;
    }
    return proceed;
  }
}

/// 파티 **전체**(= 한 회차)의 최소 모집 인원을 읽는 **유일한 통로**.
///
/// ── 왜 필드를 새로 만들었나 ─────────────────────────────────────────────
/// 예전 등록·수정 화면은 차수별 정원 모드('perRound')일 때 문서 최상단
/// `minCapacity`를 **차수 최소 인원의 합계**로 덮어썼다. 1차 2명·2차 2명으로
/// 등록한 파티가 상세에서 "최소 모집: 4명"으로 보인 원인이 이것이다.
///
/// 차수 최소 인원은 "그 차수를 열려면 몇 명이 필요한가"이고, 파티 최소 모집
/// 인원은 "이 회차를 열려면 몇 명이 필요한가"라서 서로 더할 수 있는 값이
/// 아니다(같은 사람이 1차·2차를 모두 신청하면 합계는 사람 수를 두 번 센다).
///
/// 그래서 호스트가 직접 정한 값만 담는 [field]를 새로 두고, 이 함수만
/// 읽는다. 앱과 서버(functions/partyMinCapacity.js)가 **같은 규칙**을 쓴다 —
/// 한쪽만 고치면 앱에는 '확정'이 떠 있는데 서버가 취소해버린다.
class PartyMinCapacity {
  PartyMinCapacity._();

  /// 호스트가 정한 파티 전체 최소 모집 인원. 이 필드가 있으면 그 값이 정본이다.
  static const String field = 'partyMinCapacity';

  /// 새 필드가 없는 **기존 문서**의 폴백.
  ///
  ///  · 차수별 정원 파티(`hasMultipleRounds && roundCapacityMode == 'perRound'`)
  ///    → `minCapacity`가 차수 합계라 뜻을 알 수 없다. **0(제한 없음)**으로 본다.
  ///    임의로 나누거나 최댓값을 골라 추정하지 않는다 — 틀린 숫자로 '확정'을
  ///    띄우거나 자동 취소를 돌리는 것보다, 기능을 끄는 쪽이 안전하다.
  ///  · 그 밖의 파티(차수 없음 / '모든 차수 동일')
  ///    → `minCapacity`는 호스트가 칸에 적은 값 그대로라 신뢰할 수 있다.
  static int of(Map<String, dynamic> data) {
    final explicit = (data[field] as num?)?.toInt();
    if (explicit != null) return explicit < 0 ? 0 : explicit;
    if (isLegacySummed(data)) return 0;
    final legacy = (data['minCapacity'] as num?)?.toInt() ?? 0;
    return legacy < 0 ? 0 : legacy;
  }

  /// 이 문서의 `minCapacity`가 **차수 합계로 오염된** 옛 문서인지.
  /// 새 필드가 이미 있으면(다시 저장된 문서) 오염 여부를 따질 필요가 없다.
  static bool isLegacySummed(Map<String, dynamic> data) {
    if (data[field] != null) return false;
    return data['hasMultipleRounds'] == true &&
        (data['roundCapacityMode'] as String? ?? 'unified') == 'perRound';
  }
}

/// 파티 문서가 `recruitStatus: '취소'`가 된 이유. 사람이 읽는 안내 문구를
/// 화면마다 따로 쓰지 않도록 여기 한 곳에 둔다.
class PartyCancelReason {
  PartyCancelReason._();

  /// 최소 모집 인원 미달로 서버가 자동 취소한 파티.
  static const minCapacityNotMet = 'minCapacityNotMet';

  static const _labels = {minCapacityNotMet: '최소 모집 인원 미달로 취소된 파티'};

  /// 안내 문구. 모르는 사유(또는 호스트가 직접 취소)면 null.
  static String? labelOf(Map<String, dynamic> data) =>
      _labels[data['cancelReason'] as String?];
}

/// 파티(또는 한 회차/차수) 하나의 모집 현황.
///
/// '8 / 20명', '최소 모집: 10명', 최소 달성·파티 확정 배지를 카드·상세·차수
/// 카드가 **같은 규칙**으로 그리도록 계산을 여기 모았다. 최소 관련 값
/// ([min]·[minReached]·[remainingToMin] 등)은 계산은 그대로 하되, 실제로
/// 화면에 내보내는 곳은 상세 화면뿐이다 — 목록 카드는 [countLabel]만 쓴다.
@immutable
class PartyCapacityStatus {
  /// 지금까지 신청한 인원.
  final int current;

  /// 최소 모집 인원. 0이면 설정하지 않은 것.
  final int min;

  /// 최대 모집 인원. 0이면 제한 없음.
  final int max;

  const PartyCapacityStatus({
    required this.current,
    this.min = 0,
    this.max = 0,
  });

  bool get hasMin => min > 0;

  /// 최소 인원을 채웠는지 — 채우는 순간 파티가 "확정"된다.
  bool get minReached => hasMin && current >= min;

  bool get isFull => max > 0 && current >= max;

  /// 최소 인원까지 남은 사람 수. 이미 채웠거나 최소가 없으면 0.
  int get remainingToMin => minReached || !hasMin ? 0 : min - current;

  /// '8 / 20명' — 최대가 없으면 '8명'.
  String get countLabel => max > 0 ? '$current / $max명' : '$current명';

  /// '최소 모집: 10명'. 최소를 안 정했으면 null.
  String? get minLabel => hasMin ? '최소 모집: $min명' : null;

  /// 진행 막대에 쓸 0~1 비율. 최대가 없으면 null.
  double? get progress =>
      max > 0 ? (current / max).clamp(0.0, 1.0).toDouble() : null;

  /// 최소 인원선의 위치(0~1) — 진행 막대 위에 눈금으로 그린다.
  double? get minMarker =>
      (hasMin && max > 0) ? (min / max).clamp(0.0, 1.0).toDouble() : null;

  /// **파티 문서**에서 읽는다.
  ///
  /// 최소 인원은 반드시 [PartyMinCapacity.of]를 거친다 — 차수 맵을 그대로
  /// 넘기면 안 된다(차수의 `minCapacity`는 뜻이 다른 값이고, 차수 카드는
  /// [PartyRound]가 자기 값으로 직접 상태를 만든다).
  ///
  /// [currentOverride]는 정기 파티의 회차별 신청자 수처럼 문서 최상단이 아닌
  /// 곳에서 현재 인원을 읽어야 할 때 쓴다.
  factory PartyCapacityStatus.fromMap(
    Map<String, dynamic> data, {
    int? currentOverride,
  }) {
    int intOf(String key) => (data[key] as num?)?.toInt() ?? 0;
    // 남녀 정원을 따로 받는 파티는 참가자 수도 남녀 합계다.
    final current =
        currentOverride ??
        (intOf('currentParticipants') != 0
            ? intOf('currentParticipants')
            : intOf('currentMaleCount') + intOf('currentFemaleCount'));
    return PartyCapacityStatus(
      current: current,
      min: PartyMinCapacity.of(data),
      max: intOf('maxCapacity') != 0
          ? intOf('maxCapacity')
          : intOf('maxParticipants'),
    );
  }

  /// 입력 검증 — 문제가 없으면 null.
  static String? validate({required int min, required int max}) {
    if (min < 0) return '최소 모집 인원은 0명 이상이어야 합니다.';
    if (min > 0 && max > 0 && min > max) {
      return '최소 모집 인원은 최대 모집 인원보다 클 수 없습니다.';
    }
    return null;
  }
}

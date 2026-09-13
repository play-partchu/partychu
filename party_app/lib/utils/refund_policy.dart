import 'package:flutter/foundation.dart' show UniqueKey;

/// 파티 참가 취소 시 환불 규정 — PartyChu는 환불률을 정하거나 권장하지 않는다.
/// 호스트가 파티 등록/수정 화면에서 직접 구간(파티 시작 며칠 전부터 몇 % 환불)을
/// 등록하며, 참가자는 결제 전(파티 상세 화면)에 이 규정을 그대로 확인할 수 있고,
/// 취소 시 이 규정을 기준으로 환불 예정 금액이 자동 계산된다.
class RefundTier {
  /// 이 구간을 구분하기 위한 안정적인 식별자 — 에디터에서 순서를 바꾸거나
  /// 목록을 다시 그릴 때도 같은 구간이 같은 위젯/포커스를 유지하도록 한다.
  final Object id;
  int daysBefore;
  int refundPercent;

  RefundTier({
    required this.daysBefore,
    required this.refundPercent,
    Object? id,
  }) : id = id ?? UniqueKey();

  Map<String, dynamic> toMap() => {
    'daysBefore': daysBefore,
    'refundPercent': refundPercent,
  };

  static RefundTier fromMap(Map<String, dynamic> m) => RefundTier(
    daysBefore: (m['daysBefore'] as num?)?.toInt() ?? 0,
    refundPercent: (m['refundPercent'] as num?)?.toInt() ?? 0,
  );

  /// Firestore에서 읽은 raw 값(List? / dynamic)을 안전하게 파싱한다.
  static List<RefundTier> listFromDynamic(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((m) => RefundTier.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  static List<Map<String, dynamic>> listToMaps(List<RefundTier> tiers) =>
      tiers.map((t) => t.toMap()).toList();
}

/// 환불 정책의 **공통 규칙** — 최소 1개.
///
/// 환불 정책을 등록/수정하는 화면은 파티(등록·수정), 파티+숙박 콤보의 파티/룸,
/// 플레이스+파티 콤보의 파티, 장소·장소대여 등록/수정의 룸([RoomCard])까지
/// 여럿이다. 화면마다 "구간이 비었는지"를 따로 적으면 한 곳만 고쳐지고 나머지는
/// 예전 규칙으로 남는다 — 그래서 판정도 문구도 여기 하나만 쓴다.
///
/// **결제가 없는 유형도 예외가 아니다.** 무료 파티·무료 예약이라도 정책상
/// 명시적인 예외가 없어 같은 규칙을 그대로 적용한다(환불 계산 자체는
/// [computeRefundPreview]가 appliedFee 0을 이미 따로 다룬다 — 이 규칙은
/// "등록 시 정책을 반드시 적어 두게 한다"는 별개의 이야기다).
///
/// 옛 문서(구간 없이 저장된 파티·룸)는 **열람·수정 화면 진입까지 그대로**
/// 허용한다. 막는 것은 저장 시점 하나뿐이다 — 그래야 다른 내용을 고치러 들어온
/// 호스트가 화면조차 열지 못하는 일이 없다.
class RefundPolicyRule {
  RefundPolicyRule._();

  /// 있어야 하는 최소 구간 수.
  static const int minTiers = 1;

  /// 비었을 때 보여주는 안내 — 스낵바·배너·입력칸 아래 문구가 모두 이 문장이다.
  static const String requiredMessage = '환불 정책을 1개 이상 선택해주세요.';

  /// 요약 행에 붙는 필수 표시용 제목.
  static const String sectionTitle = '환불 규정';

  /// 구간이 충분한가 — 저장을 허용해도 되는 상태.
  static bool isSatisfied(List<RefundTier> tiers) => tiers.length >= minTiers;

  /// 구간이 모자란가 — 화면에 오류를 켜야 하는 상태.
  static bool isMissing(List<RefundTier> tiers) => !isSatisfied(tiers);

  /// 저장 전 검증 — 통과하면 null, 아니면 [requiredMessage].
  static String? validate(List<RefundTier> tiers) =>
      isSatisfied(tiers) ? null : requiredMessage;

  /// 요약 행 문구 — 아직 없으면 null이라 각 화면이 "필수 항목이에요"를 그린다.
  static String? summaryLabel(List<RefundTier> tiers) =>
      isMissing(tiers) ? null : '${tiers.length}단계 환불 규정 설정됨';
}

/// 취소 시점 기준으로 계산된 환불 미리보기 — 참가자 취소 확인창과, 실제 취소
/// Cloud Function 응답 표시에 공통으로 쓴다.
class RefundPreview {
  final int refundPercent;
  final int refundAmount;
  final int nonRefundableAmount;
  final RefundTier? matchedTier;
  // 호스트가 환불 규정을 아예 등록하지 않은 경우 — 0%(환불 불가)와 구분해서
  // 안내 문구를 다르게 보여주기 위한 플래그.
  final bool policyMissing;

  const RefundPreview({
    required this.refundPercent,
    required this.refundAmount,
    required this.nonRefundableAmount,
    required this.matchedTier,
    required this.policyMissing,
  });
}

/// Cloud Functions(functions/index.js의 computeRefund)와 반드시 동일한
/// 알고리즘을 유지해야 한다 — 여기서는 취소 전 미리보기 용도(참고용)로만
/// 쓰이고, 실제 환불 금액은 서버에서 다시 계산해 저장한다.
RefundPreview computeRefundPreview({
  required List<RefundTier> refundPolicy,
  required int appliedFee,
  required DateTime? partyDateTime,
}) {
  if (appliedFee <= 0) {
    return const RefundPreview(
      refundPercent: 0,
      refundAmount: 0,
      nonRefundableAmount: 0,
      matchedTier: null,
      policyMissing: false,
    );
  }
  if (refundPolicy.isEmpty || partyDateTime == null) {
    return RefundPreview(
      refundPercent: 0,
      refundAmount: 0,
      nonRefundableAmount: appliedFee,
      matchedTier: null,
      policyMissing: true,
    );
  }

  final daysUntilParty =
      partyDateTime.difference(DateTime.now()).inMilliseconds /
      (1000 * 60 * 60 * 24);

  // daysBefore가 큰(더 관대한) 구간부터 확인해, 남은 일수가 그 구간의
  // daysBefore 이상이면 그 구간을 적용한다("N일 전"부터 적용되는 규정).
  final sorted = [...refundPolicy]
    ..sort((a, b) => b.daysBefore.compareTo(a.daysBefore));
  RefundTier? matched;
  for (final tier in sorted) {
    if (daysUntilParty >= tier.daysBefore) {
      matched = tier;
      break;
    }
  }

  if (matched == null) {
    return RefundPreview(
      refundPercent: 0,
      refundAmount: 0,
      nonRefundableAmount: appliedFee,
      matchedTier: null,
      policyMissing: false,
    );
  }

  final pct = matched.refundPercent.clamp(0, 100);
  final amount = (appliedFee * pct / 100).round();
  return RefundPreview(
    refundPercent: pct,
    refundAmount: amount,
    nonRefundableAmount: appliedFee - amount,
    matchedTier: matched,
    policyMissing: false,
  );
}

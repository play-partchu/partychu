/// 호스트가 정하는 **결제 방식** — 파티 / 플레이스 예약 / 장소대여·숙박이
/// 함께 쓰는 단일 모델. 서버 `functions/paymentPolicy.js`와 키가 1:1로 맞다.
///
/// ─────────────────────────────────────────────────────────────────────────
/// ⚠ 이름 주의 — `upfront`와 기존 `deposit`은 **완전히 다른 축**이다.
///
///   upfront (여기)        = 예약금. "총액 중 얼마를 미리 받는가"  ← 호스트 정책
///   deposit ([PaymentStatus]) = 무통장입금. "어떤 수단으로 받는가" ← 구매자 선택
///
/// 그래서 `PaymentMode.partial`(예약금 방식)인 예약이
/// `PaymentStatus.awaitingDeposit`(무통장 입금대기)인 상태가 정상이다.
///
/// **화면에는 `upfront`를 전부 '예약금'으로 표기한다** — 개발용 이름이므로
/// 라벨·문구에 그대로 노출하지 않는다.
/// ─────────────────────────────────────────────────────────────────────────
///
/// ## 기존 데이터
/// 예전 파티·장소 문서에는 이 필드가 아예 없다. 그때 [PaymentPolicy.fromMap]은
/// **null**을 돌려주고, 화면과 서버는 지금까지의 동작을 그대로 유지한다
/// (구매자가 무통장입금·현장결제를 자유롭게 고르고 금액은 전액).
/// 임의로 '전액 선결제'로 간주하지 않는다 — 현장결제로 신청하던 사용자가
/// 갑자기 막히기 때문이다.
library;

import 'payment_method.dart';

/// 결제 방식. 문서에 저장되는 값(`paymentMode`).
enum PaymentMode {
  /// 전액 선결제 — 예약 시 이용요금 100%.
  prepaid('prepaid', '전액 선결제'),

  /// 예약금 결제 — 예약금 선결제 + 잔금 현장결제.
  partial('partial', '예약금 결제'),

  /// 현장 전액결제 — 앱 결제 없이 현장에서 전액.
  onsite('onsite', '현장 전액결제');

  const PaymentMode(this.key, this.label);

  final String key;

  /// 사용자·호스트에게 보이는 이름. `partial`은 '예약금'으로만 부른다.
  final String label;

  static PaymentMode? fromKey(String? key) {
    if (key == null) return null;
    for (final m in values) {
      if (m.key == key) return m;
    }
    return null;
  }
}

/// 예약금 산정 방식. [PaymentMode.partial]일 때만 뜻이 있다.
enum UpfrontType {
  /// 이용요금의 % — **총액이 확정되는 예약에서만** 쓸 수 있다.
  percentage('percentage', '이용금액의 %'),

  /// 고정 금액.
  fixed('fixed', '고정 예약금');

  const UpfrontType(this.key, this.label);

  final String key;
  final String label;

  static UpfrontType? fromKey(String? key) {
    if (key == null) return null;
    for (final t in values) {
      if (t.key == key) return t;
    }
    return null;
  }
}

/// 호스트 설정값 한 덩어리. 등록·수정 화면이 이 객체 하나만 주고받는다.
class PaymentPolicy {
  final PaymentMode mode;

  /// [PaymentMode.partial]일 때만 값이 있다.
  final UpfrontType? upfrontType;

  /// 비율 예약금(1~100). [UpfrontType.percentage]일 때만.
  final int? upfrontPercent;

  /// 고정 예약금(원). [UpfrontType.fixed]일 때만.
  final int? upfrontFixedAmount;

  const PaymentPolicy({
    required this.mode,
    this.upfrontType,
    this.upfrontPercent,
    this.upfrontFixedAmount,
  });

  /// 아무 설정도 없던 문서의 기본 진입점 — 호스트가 처음 화면을 열었을 때
  /// 무엇을 선택된 상태로 보여줄지. 기존 동작(전액)에 가장 가까운 전액 선결제.
  static const PaymentPolicy initial = PaymentPolicy(mode: PaymentMode.prepaid);

  bool get isPartial => mode == PaymentMode.partial;

  /// 이 방식에서 고를 수 있는 결제수단 — 서버 `METHODS_BY_MODE`와 **같은 규칙**이다.
  ///
  /// PG 계약 전이라 선결제는 곧 무통장입금을 뜻한다. PG가 붙으면 서버의
  /// `METHODS_BY_MODE`와 여기에 카드 등을 함께 추가하면 된다.
  List<PaymentMethod> get allowedMethods => switch (mode) {
    PaymentMode.prepaid => const [PaymentMethod.bankTransfer],
    PaymentMode.partial => const [PaymentMethod.bankTransfer],
    PaymentMode.onsite => const [PaymentMethod.onSite],
  };

  /// 이 정책으로 지금 저장해도 되는지 — 화면의 저장 버튼 활성화에 쓴다.
  bool get isComplete {
    if (!isPartial) return true;
    if (upfrontType == UpfrontType.percentage) {
      final p = upfrontPercent ?? 0;
      return p >= 1 && p <= 100;
    }
    if (upfrontType == UpfrontType.fixed) return (upfrontFixedAmount ?? 0) > 0;
    return false;
  }

  /// 미완성일 때 입력칸 아래 띄울 안내. 완성이면 null.
  String? get validationMessage {
    if (isComplete) return null;
    if (upfrontType == null) return '예약금 방식을 선택해주세요.';
    if (upfrontType == UpfrontType.percentage) {
      return '예약금 비율은 1~100% 사이로 입력해주세요.';
    }
    return '예약금 금액을 입력해주세요.';
  }

  PaymentPolicy copyWith({
    PaymentMode? mode,
    UpfrontType? upfrontType,
    int? upfrontPercent,
    int? upfrontFixedAmount,
  }) => PaymentPolicy(
    mode: mode ?? this.mode,
    upfrontType: upfrontType ?? this.upfrontType,
    upfrontPercent: upfrontPercent ?? this.upfrontPercent,
    upfrontFixedAmount: upfrontFixedAmount ?? this.upfrontFixedAmount,
  );

  /// 저장 형태. prepaid·onsite에는 예약금 항목을 **남기지 않는다** — 남겨두면
  /// 나중에 방식을 되돌렸을 때 옛 값이 되살아나 잘못 계산된다(서버
  /// `normalizePolicy`도 같은 규칙이다).
  Map<String, dynamic> toMap() {
    if (!isPartial) return {'paymentMode': mode.key};
    return {
      'paymentMode': mode.key,
      'upfrontType': upfrontType?.key,
      if (upfrontType == UpfrontType.percentage)
        'upfrontPercent': upfrontPercent,
      if (upfrontType == UpfrontType.fixed)
        'upfrontFixedAmount': upfrontFixedAmount,
    };
  }

  /// 설정이 없는 기존 문서면 **null**. 호출부는 null을 "지금까지의 동작"으로
  /// 다뤄야 한다(임의의 기본값을 채워 넣지 않는다).
  static PaymentPolicy? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final mode = PaymentMode.fromKey(map['paymentMode'] as String?);
    if (mode == null) return null;
    if (mode != PaymentMode.partial) return PaymentPolicy(mode: mode);
    return PaymentPolicy(
      mode: mode,
      upfrontType: UpfrontType.fromKey(map['upfrontType'] as String?),
      upfrontPercent: (map['upfrontPercent'] as num?)?.toInt(),
      upfrontFixedAmount: (map['upfrontFixedAmount'] as num?)?.toInt(),
    );
  }
}

/// 정책 + 최종 이용요금 → 사용자에게 보여줄 금액 분해.
///
/// **서버 `computeBreakdown`과 같은 규칙**이다. 앱 쪽 계산은 어디까지나
/// 미리보기이고 정본은 서버가 다시 계산한 값이지만, 두 계산이 어긋나면
/// "60,000원이라더니 80,000원이 찍혔다"가 되므로 규칙을 똑같이 유지한다.
class PaymentBreakdown {
  /// 설정이 없는 기존 문서면 null.
  final PaymentMode? mode;

  /// 최종 이용요금. 총액이 확정되지 않는 예약이면 null.
  final int? totalAmount;

  /// 지금 결제할 예약금. 전액 선결제면 총액, 현장 전액결제면 0.
  final int? upfrontAmount;

  /// 현장에서 결제할 잔금. **총액 미확정이면 null**(0이 아니다).
  final int? remainingAmount;

  const PaymentBreakdown({
    this.mode,
    this.totalAmount,
    this.upfrontAmount,
    this.remainingAmount,
  });

  /// 총액을 모르는 예약인지 — 화면은 이때 잔금 숫자를 쓰지 않고
  /// "추가 이용금액은 현장에서 결제"라고만 안내한다.
  bool get totalUnknown => totalAmount == null;

  /// 지금 실제로 돈을 내는지. 현장 전액결제면 false.
  bool get chargesNow => (upfrontAmount ?? 0) > 0;

  static PaymentBreakdown of(PaymentPolicy? policy, int? totalAmount) {
    // ⚠ 총액 미확정(null)과 0원을 구분한다 — null을 0으로 다루면 잔금이
    //   0으로 계산돼 "더 낼 돈이 없다"는 거짓 안내가 된다.
    final known = totalAmount != null;
    final total = known ? totalAmount : null;

    // 설정 없음(legacy) — 예약금 개념이 없으므로 지어내지 않는다.
    if (policy == null) {
      return PaymentBreakdown(totalAmount: total);
    }

    switch (policy.mode) {
      case PaymentMode.prepaid:
        return PaymentBreakdown(
          mode: policy.mode,
          totalAmount: total,
          upfrontAmount: total ?? 0,
          remainingAmount: 0,
        );
      case PaymentMode.onsite:
        return PaymentBreakdown(
          mode: policy.mode,
          totalAmount: total,
          upfrontAmount: 0,
          remainingAmount: total,
        );
      case PaymentMode.partial:
        int upfront;
        if (policy.upfrontType == UpfrontType.percentage) {
          // 총액을 모르면 비율을 계산할 근거가 없다 — 호스트 설정 화면이
          // 애초에 이 조합을 막지만, 옛 데이터가 닿으면 0으로 둔다.
          if (!known) return PaymentBreakdown(mode: policy.mode);
          upfront = ((total! * (policy.upfrontPercent ?? 0)) / 100).round();
        } else {
          upfront = policy.upfrontFixedAmount ?? 0;
        }
        if (known) upfront = upfront > total! ? total : upfront;
        if (upfront < 0) upfront = 0;
        return PaymentBreakdown(
          mode: policy.mode,
          totalAmount: total,
          upfrontAmount: upfront,
          remainingAmount: known ? total! - upfront : null,
        );
    }
  }

  /// 서버가 예약 문서에 남긴 금액 스냅샷(`amounts`)을 그대로 읽는다.
  ///
  /// **예약 내역 화면은 반드시 이 경로를 쓴다** — 호스트 설정을 다시 읽어
  /// 재계산하면 호스트가 비율을 바꾼 순간 과거 예약의 금액까지 바뀐다.
  static PaymentBreakdown fromSnapshot(Map<String, dynamic>? map) {
    if (map == null) return const PaymentBreakdown();
    return PaymentBreakdown(
      mode: PaymentMode.fromKey(map['paymentMode'] as String?),
      totalAmount: (map['totalAmount'] as num?)?.toInt(),
      upfrontAmount: (map['upfrontAmount'] as num?)?.toInt(),
      remainingAmount: (map['remainingAmount'] as num?)?.toInt(),
    );
  }

  /// 서버에 대조용으로 보낼 값 — 서버가 자기 계산과 다르면 진행을 막는다.
  Map<String, dynamic> toClaim() => {
    if (totalAmount != null) 'totalAmount': totalAmount,
    if (upfrontAmount != null) 'upfrontAmount': upfrontAmount,
    if (remainingAmount != null) 'remainingAmount': remainingAmount,
  };
}

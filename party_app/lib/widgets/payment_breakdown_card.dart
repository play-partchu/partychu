import 'package:flutter/material.dart';

import 'package:party_app/models/payment_policy.dart';
import 'package:party_app/utils/format_utils.dart';
import 'package:party_app/widgets/early_bird_price_line.dart';

/// 사용자가 **지금 얼마를 내고 나중에 얼마를 내는지**를 한눈에 보여주는 공용
/// 카드 — 파티 신청, 장소대여·숙박 예약, 플레이스 좌석 예약이 함께 쓴다.
///
/// 화면마다 따로 그리면 "여기서는 잔금이 보이는데 저기서는 안 보인다" 같은
/// 차이가 곧 생기므로 한 위젯으로 모은다([DepositPanel]과 같은 이유).
///
/// ## 총액을 모르는 예약
/// [PaymentBreakdown.totalUnknown]이면 **잔금을 숫자로 쓰지 않는다.** 좌석만
/// 잡고 음식은 현장에서 주문하는 형태라, 없는 총액을 계산해 보여주면 그대로
/// 거짓 안내가 된다 — "추가 이용금액은 현장에서 결제"라고만 적는다.
///
/// ## 개발용 이름을 노출하지 않는다
/// 내부적으로는 `upfront`지만 화면에는 언제나 **'예약금'**으로만 쓴다.
class PaymentBreakdownCard extends StatelessWidget {
  final PaymentBreakdown breakdown;

  /// '총 이용요금'을 도메인 말로 바꾼다 — 파티는 '참가비'.
  final String totalLabel;

  final Color accent;

  /// 할인 **전** 총액. 있으면 총액 줄을 "정상가(취소선) → 할인가"로 그린다.
  /// null이면 지금까지처럼 총액 하나만 적는다.
  ///
  /// 판정은 호출부가 한다 — 이 카드는 넘어온 두 금액을 그리기만 한다.
  final int? originalTotal;

  /// 할인 이름 배지 문구 — 파티 신청은 '얼리버드'.
  final String? discountLabel;

  const PaymentBreakdownCard({
    super.key,
    required this.breakdown,
    this.totalLabel = '총 이용요금',
    this.accent = const Color(0xFFFF6FA0),
    this.originalTotal,
    this.discountLabel,
  });

  /// 결제 버튼에 쓸 문구 — "예약금 60,000원 결제" / "200,000원 결제" /
  /// "예약 신청"(현장 전액결제).
  static String payButtonLabel(
    PaymentBreakdown b, {
    String onsiteLabel = '예약 신청',
  }) {
    if (b.mode == PaymentMode.onsite) return onsiteLabel;
    final now = b.upfrontAmount;
    if (now == null) {
      // 설정이 없는 기존 문서 — 지금까지처럼 총액만 말한다.
      final total = b.totalAmount;
      return total == null || total <= 0 ? '신청하기' : '${formatWon(total)} 결제';
    }
    if (now <= 0) return onsiteLabel;
    if (b.mode == PaymentMode.partial) return '예약금 ${formatWon(now)} 결제';
    return '${formatWon(now)} 결제';
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      ),
    );
  }

  List<Widget> _rows() {
    final b = breakdown;

    switch (b.mode) {
      // 설정이 없는 기존 문서 — 총액 한 줄만(지금까지의 화면과 같다).
      case null:
        if (b.totalAmount == null) return const [];
        return [_totalRow(b.totalAmount!, strong: true)];

      case PaymentMode.prepaid:
        return [
          if (b.totalAmount != null) _totalRow(b.totalAmount!),
          _row('지금 결제', formatWon(b.upfrontAmount ?? 0), strong: true),
        ];

      case PaymentMode.onsite:
        return [
          _row('지금 결제', formatWon(0), strong: true),
          if (b.totalAmount != null)
            _row('현장에서 결제할 금액', formatWon(b.totalAmount!))
          else
            _row('현장 결제', '이용한 만큼', muted: true),
        ];

      case PaymentMode.partial:
        // 총액을 아는 예약 — 세 줄을 모두 정확히 보여준다.
        if (!b.totalUnknown) {
          return [
            _totalRow(b.totalAmount!),
            _row('지금 결제할 예약금', formatWon(b.upfrontAmount ?? 0), strong: true),
            _row('현장 결제 잔금', formatWon(b.remainingAmount ?? 0)),
          ];
        }
        // 총액을 모르는 예약 — 잔금 숫자를 지어내지 않는다.
        return [
          _row('예약금', formatWon(b.upfrontAmount ?? 0), strong: true),
          _row('추가 이용금액', '현장에서 결제', muted: true),
        ];
    }
  }

  /// 총액 줄 — 할인이 있으면 정상가를 취소선으로 함께 보여준다.
  ///
  /// '지금 결제'·'현장 결제 잔금' 같은 다른 줄은 그대로다. 할인은 총액에
  /// 걸리는 것이고, 예약금/잔금은 이미 할인된 총액에서 갈라져 나온 값이라
  /// 거기에 또 취소선을 붙이면 두 번 할인된 것처럼 읽힌다.
  Widget _totalRow(int total, {bool strong = false}) {
    if (!EarlyBirdPriceLine.worthShowing(originalTotal, total)) {
      return _row(totalLabel, formatWon(total), strong: strong);
    }
    return _row(
      totalLabel,
      formatWon(total),
      strong: strong,
      valueWidget: EarlyBirdPriceLine(
        originalAmount: originalTotal!,
        discountedAmount: total,
        label: discountLabel ?? '할인',
        valueFontSize: strong ? 16 : 13.5,
      ),
    );
  }

  Widget _row(
    String label,
    String value, {
    bool strong = false,
    bool muted = false,
    Widget? valueWidget,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: muted ? Colors.black45 : Colors.black87,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (valueWidget != null)
            Flexible(child: valueWidget)
          else
            Text(
              value,
              style: TextStyle(
                fontSize: strong ? 16 : 13.5,
                fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                color: strong
                    ? accent
                    : (muted ? Colors.black45 : Colors.black87),
              ),
            ),
        ],
      ),
    );
  }
}

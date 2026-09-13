import 'package:flutter/material.dart';

import 'package:party_app/utils/format_utils.dart' as fmt;
import 'package:party_app/widgets/partychu_ui.dart';

/// 얼리버드가 적용된 금액을 "정상가 → 할인가"로 보여주는 한 줄.
///
/// 신청 흐름에서 할인된 금액만 덩그러니 보이면(예: 16,000원) 사용자가 그게
/// 할인가인지 알 수 없다. 정상가를 취소선으로 함께 보여줘야 얼리버드가
/// 적용됐다는 사실이 화면에서 드러난다.
///
/// ## 여기서 할인 여부를 계산하지 않는다
///
/// 이 위젯은 **이미 정해진 두 금액을 그리기만 한다.** 얼리버드 적용 여부와
/// 금액은 회차 기준 정본([EarlyBird.isActive] / [EarlyBird.effectivePrice],
/// 차수·패키지는 [PartyRoundOffer.effectiveFee])이 정하고, 호출부가 그 결과를
/// 넘긴다 — 표시용으로 다시 계산하면 예전처럼 "화면 따로, 결제 따로"가 된다.
///
/// 결제수단 화면의 주문 정보와 금액 분해 카드가 **같은 위젯**을 쓴다.
class EarlyBirdPriceLine extends StatelessWidget {
  /// 할인 전 정상가.
  final int originalAmount;

  /// 실제로 낼 금액.
  final int discountedAmount;

  /// 할인 이름 배지 — 기본 '얼리버드'.
  final String label;

  /// 최종 금액 글자 크기 — 자리마다 강조 정도가 달라 호출부가 정한다.
  final double valueFontSize;

  const EarlyBirdPriceLine({
    super.key,
    required this.originalAmount,
    required this.discountedAmount,
    this.label = '얼리버드',
    this.valueFontSize = 16,
  });

  /// 이 줄을 그릴 만한 상태인지 — 정상가가 실제로 더 비쌀 때만 의미가 있다.
  /// (얼리버드가 켜져 있어도 할인율 0%면 두 금액이 같아 보여줄 게 없다.)
  static bool worthShowing(int? originalAmount, int discountedAmount) =>
      originalAmount != null && originalAmount > discountedAmount;

  @override
  Widget build(BuildContext context) {
    // 좁은 폭에서 세 조각이 한 줄을 넘기면 오른쪽 정렬을 유지한 채 아래로
    // 접힌다 — 잘라내거나 숨기지 않는다.
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 2,
      children: [
        Text(
          fmt.formatWon(originalAmount),
          style: const TextStyle(
            fontSize: 12,
            color: Colors.black38,
            decoration: TextDecoration.lineThrough,
            decorationColor: Colors.black38,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: PartyChuColors.primary,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        Text(
          fmt.formatWon(discountedAmount),
          style: TextStyle(
            fontSize: valueFontSize,
            fontWeight: FontWeight.w800,
            color: PartyChuColors.primary,
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

/// 결제 화면 맨 위에 뜨는 **주문 정보**.
///
/// 결제수단을 고르는 방식은 네 도메인이 똑같지만, "무엇에 대한 결제인가"는
/// 도메인마다 다르다(파티는 참가일·인원, 파티샵은 상품·수량 …). 그래서 화면은
/// 이 요약 하나만 받고, 무엇을 담을지는 각 도메인이 [PaymentOrderSummary.party]
/// 같은 만들기 함수로 정한다 — 결제 화면에는 도메인 분기가 없다.
class PaymentOrderSummary {
  /// 어떤 종류의 결제인지 — 화면 제목과 버튼 문구가 이걸 따른다.
  final PaymentDomain domain;

  /// 큰 제목 — 파티명 / 매장명 / 장소명 / 상품명.
  final String title;

  /// 제목 아래 줄들 — (항목, 값). 도메인마다 다른 부분이 전부 여기 담긴다.
  final List<({String label, String value})> lines;

  /// 최종 결제 금액(원). 0이면 '무료'로 표시한다.
  final int amount;

  /// 할인 **전** 금액(원). null이면 할인이 없는 것이고 화면은 [amount] 하나만
  /// 그린다(기존 동작).
  ///
  /// 값은 호출부가 정본 로직으로 계산해 넘긴다 — 이 모델은 판정하지 않는다.
  final int? originalAmount;

  /// 할인 이름 배지 문구 — 파티 신청은 '얼리버드'.
  final String? discountLabel;

  /// 금액 줄에 붙는 이름 — '참가비' / '결제금액' / '주문금액'.
  final String amountLabel;

  const PaymentOrderSummary({
    required this.domain,
    required this.title,
    required this.lines,
    required this.amount,
    this.amountLabel = '결제금액',
    this.originalAmount,
    this.discountLabel,
  });

  /// 정상가를 취소선으로 함께 보여줄 상태인지.
  bool get hasDiscount =>
      originalAmount != null && originalAmount! > amount && amount > 0;

  /// 파티 신청 — 파티명 / 참가일 / 인원 / 참가비.
  factory PaymentOrderSummary.party({
    required String partyName,
    required String dateText,
    required String peopleText,
    required int fee,
    int? originalFee,
    String? discountLabel,
  }) => PaymentOrderSummary(
    domain: PaymentDomain.partyApplication,
    title: partyName,
    lines: [(label: '참가일', value: dateText), (label: '인원', value: peopleText)],
    amount: fee,
    amountLabel: '참가비',
    originalAmount: originalFee,
    discountLabel: discountLabel,
  );

  /// 플레이스 방문 예약 — 매장명 / 방문일시 / 인원.
  factory PaymentOrderSummary.placeVisit({
    required String placeName,
    required String visitText,
    required String peopleText,
    int amount = 0,
  }) => PaymentOrderSummary(
    domain: PaymentDomain.placeVisit,
    title: placeName,
    lines: [
      (label: '방문일시', value: visitText),
      (label: '인원', value: peopleText),
    ],
    amount: amount,
  );

  /// 장소대여 — 장소명 / 이용일시 / 룸·상품 / 결제금액.
  factory PaymentOrderSummary.placeRental({
    required String placeName,
    required String useText,
    required String roomText,
    required int amount,
  }) => PaymentOrderSummary(
    domain: PaymentDomain.placeRental,
    title: placeName,
    lines: [(label: '이용일시', value: useText), (label: '룸·상품', value: roomText)],
    amount: amount,
  );

  /// 파티샵 주문 — 상품명 / 수량 / 주문금액.
  factory PaymentOrderSummary.shopOrder({
    required String productName,
    required int quantity,
    required int amount,
    String? optionText,
  }) => PaymentOrderSummary(
    domain: PaymentDomain.shopOrder,
    title: productName,
    lines: [
      (label: '수량', value: '$quantity개'),
      if (optionText != null && optionText.isNotEmpty)
        (label: '옵션', value: optionText),
    ],
    amount: amount,
    amountLabel: '주문금액',
  );
}

/// 결제가 붙는 네 갈래 — 화면 문구만 갈라진다.
enum PaymentDomain {
  partyApplication(
    title: '파티 신청',
    actionLabel: '신청하기',
    // 무통장입금은 입금 확인, 현장결제는 방문 결제가 끝나야 확정이다.
    resultNoun: '신청',
    icon: Icons.celebration_rounded,
  ),
  placeVisit(
    title: '방문 예약',
    actionLabel: '예약 신청하기',
    resultNoun: '예약',
    icon: Icons.storefront_rounded,
  ),
  placeRental(
    title: '장소대여 예약',
    actionLabel: '예약하기',
    resultNoun: '예약',
    icon: Icons.meeting_room_rounded,
  ),
  shopOrder(
    title: '파티샵 주문',
    actionLabel: '주문하기',
    resultNoun: '주문',
    icon: Icons.shopping_bag_rounded,
  );

  const PaymentDomain({
    required this.title,
    required this.actionLabel,
    required this.resultNoun,
    required this.icon,
  });

  final String title;

  /// 하단 버튼 문구.
  final String actionLabel;

  /// 안내 문장에 끼워 넣는 말 — '입금이 확인되면 **신청**이 확정돼요'.
  final String resultNoun;

  final IconData icon;
}

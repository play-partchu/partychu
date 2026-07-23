/// 앱 전체 금액 표시 형식 통일 — 화면마다 제각각 있던 콤마 포맷팅을 여기
/// 하나로 모은다. 1만원 미만은 기존처럼 천 단위 콤마("9,000원"), 1만원
/// 이상은 "만원" 단위로 줄여 표시한다 — 정수배면 소수점 없이("2만원"),
/// 아니면 소수 첫째 자리까지("1.5만원").
String _formatManwon(int value) {
  if (value < 10000) {
    return '${value.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}원';
  }
  final man = value / 10000;
  final manStr = man == man.roundToDouble()
      ? man.toInt().toString()
      : man.toStringAsFixed(1);
  return '$manStr만원';
}

/// 가격/참가비 등 "0이면 무료"인 금액 표시용.
String formatPrice(int price) {
  if (price == 0) return '무료';
  return _formatManwon(price);
}

/// 환불액/급여 등 0원이 "무료"가 아니라 말 그대로 0원을 의미하는 금액 표시용.
String formatAmount(int amount) => _formatManwon(amount);

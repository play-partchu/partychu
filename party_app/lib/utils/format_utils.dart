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

/// **정확한 원 단위** 표시("143,500원").
///
/// [formatPrice]/[formatAmount]는 1만원 이상을 "14.4만원"처럼 줄여 쓰기 때문에
/// 실제 청구 금액을 보여주는 자리에는 쓸 수 없다 — 예약금·잔금·결제 금액처럼
/// **사용자가 그 숫자를 그대로 결제하는 곳**에서는 반올림된 값을 보여주면
/// 안 된다. 목록의 요약 표시는 기존 함수를 계속 쓴다.
String formatWon(int amount) {
  final sign = amount < 0 ? '-' : '';
  final digits = amount.abs().toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
  return '$sign$digits원';
}

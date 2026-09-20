/// 민감정보 마스킹 — 해제 버튼은 두지 않는다.
///
/// **회원의 전화번호는 예외다.** 회원 관리 목록과 회원 상세는 회원 확인·CS
/// 처리에 번호가 필요해서 전체를 보여 준다([adminPhoneNumber],
/// `phone_display.dart`). 여기 [phone]은 그 밖의 화면(사전등록 신청자 등)이
/// 계속 쓴다.
class Masking {
  Masking._();

  /// 010-****-5678 형태로 앞 3자리·뒤 4자리만 남기고 마스킹.
  ///
  /// 회원 관리·회원 상세에는 쓰지 않는다 — 위 주석 참고.
  static String phone(String? value) {
    if (value == null || value.isEmpty) return '-';
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 7) return '*' * digits.length;
    final head = digits.substring(0, 3);
    final tail = digits.substring(digits.length - 4);
    return '$head-****-$tail';
  }

  /// CI/DI(본인확인 연계 토큰) — 앞 4자만 남기고 나머지는 마스킹.
  static String token(String? value) {
    if (value == null || value.isEmpty) return '-';
    if (value.length <= 4) return '*' * value.length;
    return '${value.substring(0, 4)}${'*' * (value.length - 4)}';
  }
}

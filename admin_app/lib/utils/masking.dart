/// 민감정보 마스킹 — 관리자 화면에서도 항상 마스킹된 형태로만 노출한다
/// (해제 버튼 없음).
class Masking {
  Masking._();

  /// 010-****-5678 형태로 앞 3자리·뒤 4자리만 남기고 마스킹.
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

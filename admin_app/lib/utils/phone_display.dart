// 관리자 화면의 전화번호 표기 — **마스킹하지 않는다.**
//
// ── 왜 여기만 전체 번호인가 ───────────────────────────────────────────────
//
// 회원 확인과 CS 처리에 번호가 필요하다. 010-****-4423으로는 같은 뒷자리를 쓰는
// 두 사람을 가릴 수도, 전화를 걸 수도 없다.
//
// 노출 범위는 이 앱 자체가 이미 제한하고 있다 — admin_app은 로그인한 계정의
// `users/{uid}.role == 'admin'`을 확인해야 화면이 뜨고(`AdminAuthGate`),
// 그 전에 Firestore 규칙이 남의 users 문서 읽기를 `isAdmin()`으로 막는다
// (firestore.rules). 관리자가 아니면 번호는커녕 회원 문서 자체가 오지 않는다.
//
// 일반 사용자용 앱(party_app)은 이 파일을 쓰지 않는다 — 별도 프로젝트이고,
// 거기 표시 정책은 그대로다.
//
// ── 저장값은 건드리지 않는다 ─────────────────────────────────────────────
//
// 표시만 바꾼다. DB의 `users/{uid}.phoneNumber`는 읽기만 하고, 마이그레이션도
// 정규화 쓰기도 하지 않는다.

/// 관리자 화면에 보여 줄 전화번호 — 전체 번호를 읽기 좋게 끊어서.
///
/// 값이 없으면 `-`. 저장된 형태가 제각각이라(숫자만, 하이픈 포함, `+82`)
/// 숫자만 남긴 뒤 자릿수에 맞춰 끊는다. 아는 모양이 아니면 **원문을 그대로**
/// 돌려준다 — 억지로 끊어서 없는 번호처럼 보이게 하지 않는다.
String adminPhoneNumber(String? value) {
  if (value == null || value.trim().isEmpty) return '-';
  final raw = value.trim();

  // 국제 표기(+82 10 1234 5678)는 국내 표기로 돌린다. 82 뒤의 0이 빠져 있으면
  // 채운다 — 그게 +82 표기의 규칙이다.
  var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (raw.startsWith('+82') && digits.startsWith('82')) {
    final rest = digits.substring(2);
    digits = rest.startsWith('0') ? rest : '0$rest';
  }

  return _hyphenate(digits) ?? raw;
}

/// 국내 번호 끊기 규칙. 아는 모양이 아니면 null.
String? _hyphenate(String digits) {
  String cut(int a, int b) =>
      '${digits.substring(0, a)}-${digits.substring(a, a + b)}-${digits.substring(a + b)}';

  // 서울 지역번호만 두 자리다.
  if (digits.startsWith('02')) {
    if (digits.length == 10) return cut(2, 4); // 02-1234-5678
    if (digits.length == 9) return cut(2, 3); // 02-123-4567
    return null;
  }
  // 휴대전화·그 외 지역번호·대표번호(1544 등)는 전부 앞 3자리.
  if (digits.length == 11) return cut(3, 4); // 010-1234-5678
  if (digits.length == 10) return cut(3, 3); // 011-123-4567 / 031-123-4567
  if (digits.length == 8) return '${digits.substring(0, 4)}-${digits.substring(4)}';
  return null;
}

/// 간단한 욕설/비속어 필터 — 닉네임 등 사용자 표시 텍스트에 재사용한다.
/// 완벽한 검열이 목적이 아니라 흔한 욕설/혐오 표현을 1차로 걸러내는
/// 최소한의 목록이다. 필요하면 [_bannedWords]에 항목을 추가하면 된다.
class ProfanityFilter {
  ProfanityFilter._();

  static const List<String> _bannedWords = [
    '시발',
    '씨발',
    '씨팔',
    '시팔',
    'ㅅㅂ',
    'ㅆㅂ',
    '병신',
    'ㅂㅅ',
    '개새끼',
    '새끼',
    '좆',
    '지랄',
    'ㅈㄹ',
    '미친놈',
    '미친년',
    '개새',
    '창녀',
    '걸레',
    'fuck',
    'shit',
    'bitch',
    'asshole',
  ];

  /// 대소문자/공백을 무시하고 금칙어 포함 여부를 검사한다.
  static bool containsProfanity(String text) {
    final normalized = text.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    return _bannedWords.any((w) => normalized.contains(w));
  }
}

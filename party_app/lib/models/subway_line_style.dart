import 'package:flutter/material.dart';

/// 노선 이름 → 표시용 색·짧은 라벨.
///
/// 데이터 파일에는 색을 넣지 않는다 — 공공데이터마다 색 표기가 없거나 제각각이라
/// 여기 **코드 상수 하나**로 관리하는 편이 어긋나지 않는다. 목록에 없는 노선은
/// 회색으로 떨어지고, 표시는 그대로 된다(새 지역 데이터를 넣어도 깨지지 않는다).
///
/// 색은 각 운영기관이 공표한 노선색을 옮긴 값이다. 실제와 다른 것이 보이면 이
/// 표만 고치면 된다.
class SubwayLineStyle {
  const SubwayLineStyle._();

  static const Color _fallback = Color(0xFF6B7280);

  /// 노선 이름(데이터 파일에 적힌 그대로)으로 찾는다. 접미사 '선'이 있든 없든,
  /// 공백이 있든 없든 같은 노선으로 본다.
  static Color colorOf(String lineName) {
    final key = _normalize(lineName);
    return _colors[key] ?? _fallback;
  }

  /// 원형 배지 안에 넣을 짧은 라벨.
  ///
  /// 'N호선'은 숫자만('2'), 그 밖의 이름은 '선'을 떼고 앞 두 글자('신분', '경의')
  /// 를 쓴다 — 작은 원 안에 들어가야 해서 길면 읽히지 않는다.
  static String shortLabelOf(String lineName) {
    final numbered = RegExp(r'^(\d+)\s*호선$').firstMatch(lineName.trim());
    if (numbered != null) return numbered.group(1)!;
    final stripped = lineName.trim().replaceAll(RegExp(r'선$'), '');
    if (stripped.isEmpty) return '?';
    return stripped.characters.take(2).toString();
  }

  static String _normalize(String s) => s.replaceAll(' ', '').trim();

  static const Map<String, Color> _colors = {
    // 수도권 — 서울교통공사·코레일 노선색
    '1호선': Color(0xFF0052A4),
    '2호선': Color(0xFF00A84D),
    '3호선': Color(0xFFEF7C1C),
    '4호선': Color(0xFF00A5DE),
    '5호선': Color(0xFF996CAC),
    '6호선': Color(0xFFCD7C2F),
    '7호선': Color(0xFF747F00),
    '8호선': Color(0xFFE6186C),
    '9호선': Color(0xFFBDB092),
    '경의중앙선': Color(0xFF77C4A3),
    '공항철도': Color(0xFF0090D2),
    '경춘선': Color(0xFF178C72),
    '수인분당선': Color(0xFFFABE00),
    '분당선': Color(0xFFFABE00),
    '신분당선': Color(0xFFD31145),
    '경강선': Color(0xFF003DA5),
    '서해선': Color(0xFF8FC31F),
    // 아래 노선들은 데이터에 한국철도 노선명으로 들어오지만, 수도권 전철에서는
    // 1·3·4호선 운행계통으로 표시된다 — 같은 색을 쓴다.
    '경부선': Color(0xFF0052A4),
    '경인선': Color(0xFF0052A4),
    '경원선': Color(0xFF0052A4),
    '장항선': Color(0xFF0052A4),
    '일산선': Color(0xFFEF7C1C),
    '안산과천선': Color(0xFF00A5DE),
    '진접선': Color(0xFF00A5DE),
    '김포골드라인': Color(0xFFA17800),
    '용인경전철': Color(0xFF509F22),
    '의정부경전철': Color(0xFFFDA600),
    '우이신설선': Color(0xFFB7C452),
    '신림선': Color(0xFF6789CA),
    '인천1호선': Color(0xFF7CA8D5),
    '인천2호선': Color(0xFFF5A200),
    // 부산·대구·광주·대전 — 지역 데이터를 넣을 때 함께 쓰인다.
    '부산1호선': Color(0xFFF06A00),
    '부산2호선': Color(0xFF81BF48),
    '부산3호선': Color(0xFFBB8C00),
    '부산4호선': Color(0xFF217DCB),
    '동해선': Color(0xFF0E8ECC),
    '대구1호선': Color(0xFFD93F5C),
    '대구2호선': Color(0xFF00A5A8),
    '대구3호선': Color(0xFFFFB100),
    '광주1호선': Color(0xFF009088),
    '대전1호선': Color(0xFF007448),
  };
}

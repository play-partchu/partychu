// 마이페이지 '관심 목록' 한 줄 메뉴 — **글자만** 바뀌었는지 확인한다.
//
// 요청은 문구 하나(찜! / 관심 목록)와 '찜!'만 핑크 강조였다. 이런 변경에서
// 실제로 사고가 나는 자리는 글자가 아니라 그 옆이다 — 발바닥 아이콘이 다른
// 이모지/아이콘으로 바뀌거나, 색·크기가 흔들리거나, 이동 경로가 갈리는 것.
// 마이페이지는 Firebase에 붙는 화면이라 위젯으로 띄울 수 없어, 이 프로젝트의
// 다른 화면 테스트와 같은 방식으로 소스를 잠근다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src = File('lib/screens/my_page_screen.dart').readAsStringSync();
  final menu = src.substring(
    src.indexOf('Widget _buildFavoritesMenuItem'),
    src.indexOf('// (채팅 메뉴는 삭제됐다'),
  );

  group('관심 목록 메뉴', () {
    test("문구는 '찜! / 관심 목록' 두 조각이다", () {
      expect(menu, contains("TextSpan(text: '찜!'"));
      expect(menu, contains("TextSpan(text: ' / 관심 목록')"));
      // 한 덩어리 문자열로 되돌아가면 조각별 색을 줄 수 없다.
      expect(menu.contains("label: '"), isFalse);
    });

    test("'찜!'만 핑크, 나머지 조각엔 색을 주지 않는다(기존 검정 상속)", () {
      expect(
        menu,
        contains("TextSpan(text: '찜!', style: TextStyle(color: pink))"),
      );
      expect(menu, contains("TextSpan(text: ' / 관심 목록')"));
    });

    test('발바닥 아이콘과 핑크는 그대로다 — 아이콘은 글자와 같은 색을 쓴다', () {
      expect(menu, contains('icon: Icons.pets'));
      expect(menu, contains('const pink = Color(0xFFFF6FA0)'));
      expect(menu, contains('color: pink'));
    });

    test('이동 경로는 그대로 관심목록 화면이다', () {
      expect(menu, contains('MyFavoritesScreen()'));
    });

    test('아이콘 크기·행 배치는 공용 한 줄 메뉴가 그대로 갖는다', () {
      // 아이콘 22 / 간격 10 / 오른쪽 화살표 — _menuItem 한 곳에만 있다.
      expect(src, contains('Icon(icon, color: color, size: 22)'));
      expect(src, contains('const SizedBox(width: 10)'));
      expect(src, contains('Icon(Icons.chevron_right, color: Colors.black45)'));
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/screens/main_screen.dart';

/// 홈 상단 낮/밤 전환 버튼 — 아이콘이 가리키는 방향.
///
/// 아이콘 하나뿐인 버튼이라 그림이 곧 그 버튼의 뜻이다. 지금 모드를 그리면
/// 이미 아는 사실을 되풀이할 뿐이고, 누르면 무엇이 되는지는 어디에도 없다.
/// 그래서 **누르면 될 모드**를 그린다 — 낮에는 🌙, 밤에는 ☀️.
///
/// 뒤집힌 채로 되돌아가기 쉬운 종류의 규칙이라(둘 다 "그럴듯해" 보인다)
/// 방향을 여기서 못박는다. 전환 로직과 저장 구조는 이 테스트의 관심사가
/// 아니다 — 아이콘과 문구만 본다.
void main() {
  group('아이콘은 누르면 될 모드를 가리킨다', () {
    test('낮 모드에서는 달 — 누르면 밤이 된다', () {
      expect(dayNightToggleIcon(false), Icons.nightlight_round);
    });

    test('밤 모드에서는 해 — 누르면 낮이 된다', () {
      expect(dayNightToggleIcon(true), Icons.wb_sunny_rounded);
    });

    test('지금 모드를 그리던 예전 방향으로 돌아가지 않는다', () {
      expect(dayNightToggleIcon(false), isNot(Icons.wb_sunny_rounded));
      expect(dayNightToggleIcon(true), isNot(Icons.nightlight_round));
    });
  });

  group('툴팁·접근성 문구도 같은 방향이다', () {
    // 그림과 말이 어긋나면 화면을 읽어 주는 쪽에서만 반대로 안내된다.
    test('낮 모드에서는 밤으로 전환한다고 말한다', () {
      expect(dayNightToggleTooltip(false), '밤 모드로 전환');
    });

    test('밤 모드에서는 낮으로 전환한다고 말한다', () {
      expect(dayNightToggleTooltip(true), '낮 모드로 전환');
    });
  });
}

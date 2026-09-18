import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// 파티샵 결제하기(_onPay)는 **로그인을 가장 먼저** 본다.
//
// 비로그인 사용자에게 "배송/수령 방식을 선택해주세요"가 먼저 나오면 결제
// 버튼이 반응하지 않는 것처럼 보인다. 상품 시트는 Firestore에 붙은 private
// 위젯이라 여기서는 결제 처리 함수의 **검사 순서**를 소스로 고정한다.
void main() {
  final src = File(
    'lib/screens/party_shop_detail_screen.dart',
  ).readAsStringSync();
  final start = src.indexOf('Future<void> _onPay() async {');
  final end = src.indexOf('// ── 결제수단', start);
  final body = src.substring(start, end);

  test('결제 처리 함수를 찾는다', () {
    expect(start, greaterThan(0));
    expect(end, greaterThan(start));
  });

  test('로그인 확인이 옵션·수령 방식·날짜 검사보다 먼저다', () {
    final login = body.indexOf('if (!UserSession.isLoggedIn)');
    expect(login, greaterThan(0));
    for (final later in [
      '옵션을 선택해주세요.',
      '배송/수령 방식을 선택해주세요.',
      '수령 날짜를 선택해주세요.',
    ]) {
      expect(body.indexOf(later), greaterThan(login), reason: later);
    }
  });

  test('비로그인이면 안내 후 실제 로그인 화면을 띄우고 멈춘다', () {
    final login = body.indexOf('if (!UserSession.isLoggedIn)');
    final block = body.substring(login, body.indexOf('return;', login));
    expect(block, contains('로그인이 필요합니다'));
    expect(block, contains('LoginPage()'));
  });

  test('결제 쪽에 로그인 검사가 두 번 남지 않는다', () {
    expect(RegExp(r'UserSession\.userId\.isEmpty').hasMatch(body), isFalse);
  });
}

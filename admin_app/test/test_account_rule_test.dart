// 회원 관리가 "테스트 계정"을 판정하는 규칙 — 이번 누락 사고의 핵심이다.
//
// 예전에는 서버 쿼리에서 `isTestAccount == false`로 걸렀다. Firestore의 등호
// 필터는 **필드가 없는 문서를 매칭하지 않으므로**, 그 필드가 생기기 전에
// 만들어진 정상 회원이 회원 관리 목록에서 통째로 사라진다. `!=`로 바꿔도
// 마찬가지다(Firestore의 != 도 필드 없는 문서를 제외한다).
//
// 그래서 서버에서는 거르지 않고, 받아온 페이지에서 이 규칙으로 제외한다:
// **명시적으로 true인 것만 테스트 계정.**

import 'package:flutter_test/flutter_test.dart';

import 'package:partychu_admin/services/admin_firestore_service.dart';

void main() {
  test('명시적으로 true면 테스트 계정', () {
    expect(AdminFirestoreService.isTestAccountDoc({'isTestAccount': true}), isTrue);
  });

  test('명시적으로 false면 정상 회원', () {
    expect(AdminFirestoreService.isTestAccountDoc({'isTestAccount': false}), isFalse);
  });

  // 이 한 줄이 이번 수정의 전부다 — 필드가 없다는 이유로 목록에서 빠지면 안 된다.
  test('필드 자체가 없으면 정상 회원으로 본다', () {
    expect(AdminFirestoreService.isTestAccountDoc({}), isFalse);
    expect(
      AdminFirestoreService.isTestAccountDoc({'email': 'a@b.com', 'nickname': '냥이'}),
      isFalse,
    );
  });

  test('null이 들어 있어도 정상 회원', () {
    expect(AdminFirestoreService.isTestAccountDoc({'isTestAccount': null}), isFalse);
  });

  // 타입이 어긋난 값(문자열 'true' 등)을 참으로 읽으면 정상 회원이 사라진다.
  test('불리언이 아닌 값은 테스트 계정으로 치지 않는다', () {
    expect(AdminFirestoreService.isTestAccountDoc({'isTestAccount': 'true'}), isFalse);
    expect(AdminFirestoreService.isTestAccountDoc({'isTestAccount': 1}), isFalse);
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/listing_inquiry.dart';

/// 문의 대상 표는 **앱과 서버 두 곳에** 있다.
///
///   · 앱   — [InquiryTarget] (relatedType ↔ 원본 컬렉션)
///   · 서버 — functions/chatRooms.js의 `LISTING_COLLECTIONS`
///
/// 앱은 relatedType만 보내고, 어느 컬렉션을 뒤질지는 서버가 정한다. 그래서 앱에
/// 종류를 하나 늘려도 **서버 표에 같은 값이 없으면 문의가 통째로 막힌다** —
/// createChatRoom이 'relatedType이 올바르지 않습니다'(invalid-argument)로 거절하고,
/// 화면에는 "문의 채팅을 열지 못했어요"만 뜬다. 실제로 매장 이벤트(✨) 문의가
/// 이 상태였다.
///
/// 여기서는 두 표가 **글자 그대로 같은 짝**인지만 본다. 소스가 맞아도 서버에
/// 배포되지 않았으면 여전히 막히므로, 이 테스트는 배포까지 보장하지 않는다 —
/// 배포는 운영 함수를 직접 호출해 확인해야 한다.
void main() {
  /// functions/chatRooms.js의 `LISTING_COLLECTIONS` 블록을 읽어
  /// `{relatedType: [컬렉션…]}`으로 되돌린다(주석은 버린다).
  Map<String, List<String>> serverTable() {
    final src = File('../functions/chatRooms.js').readAsStringSync();
    final start = src.indexOf('const LISTING_COLLECTIONS = {');
    expect(start, greaterThan(-1), reason: 'LISTING_COLLECTIONS를 찾지 못했다');
    final end = src.indexOf('};', start);
    final body = src.substring(start, end);
    final table = <String, List<String>>{};
    final entry = RegExp(r"^\s*(\w+)\s*:\s*\[([^\]]*)\]", multiLine: true);
    for (final m in entry.allMatches(body)) {
      table[m.group(1)!] = RegExp(r"'([^']+)'")
          .allMatches(m.group(2)!)
          .map((c) => c.group(1)!)
          .toList();
    }
    return table;
  }

  test('앱이 보내는 relatedType은 전부 서버 표에 있다', () {
    final table = serverTable();
    for (final target in InquiryTarget.values) {
      expect(
        table.containsKey(target.relatedType),
        isTrue,
        reason:
            '$target의 relatedType "${target.relatedType}"이 서버 표에 없다 — '
            '이 상태로 배포되면 문의가 invalid-argument로 거절된다',
      );
    }
  });

  test('앱이 적어 둔 원본 컬렉션이 서버가 뒤지는 곳에 들어 있다', () {
    final table = serverTable();
    for (final target in InquiryTarget.values) {
      expect(
        table[target.relatedType],
        contains(target.collection),
        reason:
            '$target은 ${target.collection}에 있는데 서버는 '
            '${table[target.relatedType]}만 뒤진다 — 문의가 not-found가 된다',
      );
    }
  });

  test('매장 이벤트는 플레이스와 다른 relatedType을 쓴다', () {
    // 한 플레이스에 이벤트가 여러 개 달린다. 같은 값을 쓰면 서버가
    // placePromotions를 아예 찾지 못하고(‘place’는 events·places만 본다),
    // 호스트 채팅 목록에서도 어느 이벤트 이야기인지 갈리지 않는다.
    expect(InquiryTarget.event.relatedType, 'event');
    expect(InquiryTarget.event.collection, 'placePromotions');
    expect(
      InquiryTarget.event.relatedType,
      isNot(InquiryTarget.place.relatedType),
    );
    expect(serverTable()['event'], ['placePromotions']);
  });
}

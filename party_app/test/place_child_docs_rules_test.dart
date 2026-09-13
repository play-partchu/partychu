// 플레이스에 딸린 문서(`placeRooms` · `placeProducts`)의 **소유 관문**.
//
// ── 무엇이 구멍이었나 ───────────────────────────────────────────────────────
// 두 컬렉션의 create는 오래도록 `hostId == uid()`만 봤다. 그래서
//   · 자기 uid를 hostId에 넣고 **남의 placeId**를 적으면, 그 사람 플레이스
//     상세에 내 룸·상품이 그대로 붙었다(상세 화면의 룸/상품 쿼리는 placeId로만
//     조회하고 hostId 필터가 없다).
//   · 존재하지 않는 placeId로 **부모 없는 orphan 문서**도 만들 수 있었다.
// update·delete도 문서의 hostId만 봐서, 한 번 붙인 문서를 계속 다룰 수 있었다.
//
// `placePromotions`는 이미 같은 문제를 `ownsSourcePlace`(부모 문서를 실제로
// 읽어 hostId 확인)로 막고 있었다 — 두 컬렉션에도 같은 원칙을 적용했고,
// 중복을 줄이려고 `ownsPlace(placeId)`(= places 전용 축약)를 함께 뒀다.
//
// ── 이 파일이 보는 것 ───────────────────────────────────────────────────────
// 규칙 **원문의 구조**다. "자기 것은 되고 남의 것은 안 된다"를 실제로 평가하는
// 것은 Firestore 에뮬레이터의 몫이라, 그 행위 검증은
// `functions/placeChildOwnership.selfcheck.js`가 따로 들고 있다(에뮬레이터가
// 있어야 돌아간다 — **배포 전 검증 대기 상태**).
//
// 여기서는 에뮬레이터 없이도 항상 도는 안전망을 둔다: 세 연산 모두가 소유
// 관문을 지나는지, 소속(placeId)을 바꿔 옮겨 붙이는 길이 막혔는지, 그리고
// 기존 호스트의 관리가 깨지지 않도록 관리자 경로가 남아 있는지.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late final String rules = File('../firestore.rules').readAsStringSync();

  /// `match /<collection>/{...} { ... }` 한 덩어리.
  String blockOf(String collection) {
    final start = rules.indexOf('match /$collection/{');
    expect(start, isNot(-1), reason: '$collection 규칙을 찾지 못했다');
    final end = rules.indexOf('\n    }', start);
    expect(end, isNot(-1), reason: '$collection 규칙의 끝을 찾지 못했다');
    return rules.substring(start, end);
  }

  /// 한 덩어리 안에서 `allow <op>:` 한 줄(여러 줄이면 `;`까지)을 꺼낸다.
  String clauseOf(String block, String op) {
    final at = block.indexOf('allow $op');
    expect(at, isNot(-1), reason: '"allow $op" 규칙이 없다');
    return block.substring(at, block.indexOf(';', at));
  }

  // ── 공용 헬퍼 ───────────────────────────────────────────────────────────

  group('ownsPlace 헬퍼', () {
    test('부모 문서를 실제로 읽어 hostId까지 확인한다', () {
      // 세 가지가 모두 있어야 관문이 성립한다.
      //   exists()  — 없는 placeId(orphan)를 막는다
      //   get().data.hostId == uid() — 남의 플레이스를 막는다
      expect(rules, contains('function ownsSourcePlace(placeCollection, placeId)'));
      final at = rules.indexOf('function ownsSourcePlace(');
      final body = rules.substring(at, rules.indexOf('\n    }', at));
      expect(body, contains('exists('));
      expect(body, contains('.data.hostId == uid()'));
      expect(body, contains("placeId.size() > 0"));
    });

    // 중복 규칙을 줄이려고 둔 축약 — placeRooms는 언제나 places에 붙는다.
    test('places 전용 축약이 같은 판정을 재사용한다', () {
      expect(rules, contains('function ownsPlace(placeId)'));
      final at = rules.indexOf('function ownsPlace(placeId)');
      final body = rules.substring(at, rules.indexOf('\n    }', at));
      expect(
        body,
        contains("ownsSourcePlace('places', placeId)"),
        reason: '판정을 따로 적으면 두 곳이 어긋난다',
      );
    });
  });

  // ── placeRooms ─────────────────────────────────────────────────────────

  group('placeRooms', () {
    late final String block = blockOf('placeRooms');

    test('create — 부모 플레이스의 주인만', () {
      final create = clauseOf(block, 'create');
      expect(create, contains('ownsPlace('));
      // 본인 hostId 조건도 그대로 남아야 한다 — 남의 이름으로 만드는 것도 막는다.
      expect(create, contains('request.resource.data.hostId == uid()'));
    });

    test('update — 부모 주인 또는 관리자만, 소속·소유자는 못 바꾼다', () {
      final update = clauseOf(block, 'update');
      expect(update, contains('ownsPlace('));
      // 관리자 경로는 남긴다(신고 대응 — 관리자는 남의 플레이스 주인이 아니다).
      expect(update, contains('isAdmin()'));
      // 만든 뒤 남의 플레이스로 옮겨 붙이는 우회를 막는다.
      expect(
        update,
        contains("request.resource.data.get('placeId', '')"),
        reason: 'placeId를 고정하지 않으면 옮겨 붙일 수 있다',
      );
      expect(update, contains("request.resource.data.get('hostId', '')"));
    });

    test('delete — 부모 주인 또는 관리자만', () {
      final del = clauseOf(block, 'delete');
      expect(del, contains('ownsPlace('));
      expect(del, contains('isAdmin()'));
    });

    // 읽기는 공개 그대로다 — 손님이 장소 상세에서 룸을 봐야 한다.
    test('읽기는 공개 그대로다', () {
      expect(block, contains('allow read: if true;'));
    });

    // 문서의 hostId만 보던 옛 조건이 남아 있으면 구멍이 그대로다.
    test('hostId만 보던 옛 조건이 남아 있지 않다', () {
      expect(
        clauseOf(block, 'update'),
        isNot(contains('resource.data.hostId == uid()')),
      );
      expect(
        clauseOf(block, 'delete'),
        isNot(contains('resource.data.hostId == uid()')),
      );
    });
  });

  // ── placeProducts ──────────────────────────────────────────────────────

  group('placeProducts', () {
    late final String block = blockOf('placeProducts');

    // 상품은 부모가 events일 수도 places일 수도 있어 두 인자짜리를 그대로 쓴다.
    test('create — 부모 플레이스의 주인만, soldCount는 0에서 시작', () {
      final create = clauseOf(block, 'create');
      expect(create, contains('ownsSourcePlace('));
      expect(create, contains("request.resource.data.get('placeCollection'"));
      expect(create, contains('request.resource.data.hostId == uid()'));
      // 기존 불변식이 함께 살아 있어야 한다.
      expect(create, contains('request.resource.data.soldCount == 0'));
    });

    test('update — 부모 주인/관리자만, 소속·판매수량·소유자는 못 바꾼다', () {
      final update = clauseOf(block, 'update');
      expect(update, contains('ownsSourcePlace('));
      expect(update, contains('isAdmin()'));
      expect(
        update,
        contains(
          'request.resource.data.soldCount == resource.data.soldCount',
        ),
        reason: '판매 수량을 되돌릴 수 있으면 재고를 무한히 만들 수 있다',
      );
      expect(
        update,
        contains('request.resource.data.hostId == resource.data.hostId'),
      );
      expect(update, contains("request.resource.data.get('placeId', '')"));
      expect(
        update,
        contains("request.resource.data.get('placeCollection', 'events')"),
      );
    });

    test('delete — 부모 주인/관리자만, 팔린 상품은 못 지운다', () {
      final del = clauseOf(block, 'delete');
      expect(del, contains('ownsSourcePlace('));
      expect(del, contains('isAdmin()'));
      expect(
        del,
        contains('resource.data.soldCount == 0'),
        reason: '발급된 이용권이 가리킬 상품이 사라지면 QR 검증이 불가능해진다',
      );
    });

    test('hostId만 보던 옛 조건이 남아 있지 않다', () {
      expect(
        clauseOf(block, 'update'),
        isNot(contains('(resource.data.hostId == uid() || isAdmin())')),
      );
      expect(
        clauseOf(block, 'delete'),
        isNot(contains('(resource.data.hostId == uid() || isAdmin())')),
      );
    });
  });

  // ── 같은 원칙을 쓰는 이웃 ───────────────────────────────────────────────

  group('placePromotions', () {
    // 이 컬렉션이 원래 갖고 있던 원칙을 두 컬렉션이 물려받았다. 이쪽이 헬퍼를
    // 놓치면 세 컬렉션의 기준이 다시 갈라진다.
    test('같은 헬퍼를 계속 쓴다', () {
      final block = blockOf('placePromotions');
      expect(clauseOf(block, 'create'), contains('ownsSourcePlace('));
    });
  });

  // ── 에뮬레이터 검증 대기 상태 ───────────────────────────────────────────
  //
  // 규칙 원문 검사는 "조건이 걸려 있다"까지만 말한다. 실제로 남의 플레이스에
  // 붙는 쓰기가 거부되는지는 에뮬레이터에서 확인해야 하고, 그 시나리오는
  // 아래 파일이 들고 있다. **배포 전에 반드시 돌린다.**

  group('에뮬레이터 행위 검증', () {
    test('시나리오 파일이 저장소에 있다', () {
      final file = File('../functions/placeChildOwnership.selfcheck.js');
      expect(
        file.existsSync(),
        isTrue,
        reason: '에뮬레이터 검증 시나리오가 사라졌다 — 규칙 변경이 무검증으로 배포된다',
      );
      final src = file.readAsStringSync();
      // 사용자가 요구한 다섯 갈래가 모두 들어 있는지.
      for (final scenario in [
        'ownRoomCreate',
        'foreignRoomCreate',
        'missingParentRoomCreate',
        'ownProductUpdate',
        'foreignProductDelete',
      ]) {
        expect(
          src,
          contains(scenario),
          reason: '에뮬레이터 시나리오 "$scenario"가 빠졌다',
        );
      }
    });
  });
}

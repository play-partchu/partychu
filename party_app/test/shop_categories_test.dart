// 🛍️ 파티샵 상품 카테고리 — **목록 하나가 정본**이라는 것을 붙잡는다.
//
// 이 파일이 지키는 것 셋.
//   ① 하위호환 — 예전에 있던 값은 글자 하나 안 바뀌고 그대로 남아 있다.
//      이 배열의 문자열이 곧 저장값이라, 하나라도 바뀌면 그 값으로 등록된
//      상품이 검색·필터에서 조용히 사라진다.
//   ② 새 칸 — '케이크/디저트'가 있고, 케이터링 앞에 선다.
//   ③ 사본 없음 — 등록·수정·상세검색·안내 화면이 전부 [ListingConstants]
//      하나를 읽는다(손으로 적은 목록이 어디에도 없다).
//
// ①②는 값으로, ③은 소스 가드로 확인한다 — 화면은 Firebase 없이 그릴 수 없다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/models/made_to_order.dart';

String _src(String path) => File(path).readAsStringSync();

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

void main() {
  const cats = ListingConstants.shopCategories;

  // ── ① 하위호환 ─────────────────────────────────────────────────────────
  group('기존 카테고리 값은 그대로다', () {
    // 2026-08-31 '케이크/디저트'를 넣기 **전에** 있던 여덟 칸.
    // 저장된 상품이 가리키는 문자열이므로 글자를 고치거나 빼면 안 된다.
    const legacy = [
      '의상/코스튬',
      '파티소품',
      '풍선/데코',
      '폭죽/불꽃',
      '케이터링/음료',
      '조명/음향',
      '기프트/답례품',
      '기타',
    ];

    test('여덟 칸이 하나도 빠지지 않았다', () {
      for (final c in legacy) {
        expect(cats.contains(c), isTrue, reason: c);
      }
    });

    test('기본 카테고리(첫 칸)는 바뀌지 않았다', () {
      // 새 상품이 아무것도 안 고르면 이 값으로 저장된다.
      expect(cats.first, '의상/코스튬');
    });

    test('같은 값이 두 번 들어 있지 않다', () {
      expect(cats.toSet().length, cats.length);
    });
  });

  // ── ② 새 칸 ────────────────────────────────────────────────────────────
  group('🍰 케이크/디저트', () {
    test('목록에 있다', () {
      expect(cats.contains('케이크/디저트'), isTrue);
    });

    test("'케이터링/음료' 바로 앞에 선다", () {
      expect(cats.indexOf('케이크/디저트') + 1, cats.indexOf('케이터링/음료'));
    });

    test('최종 순서가 그대로다', () {
      expect(cats, const [
        '의상/코스튬',
        '파티소품',
        '풍선/데코',
        '케이크/디저트',
        '케이터링/음료',
        '조명/음향',
        '기프트/답례품',
        '폭죽/불꽃',
        '기타',
      ]);
    });

    test('🛠 주문제작과는 다른 축이라 함께 쓸 수 있다', () {
      // 카테고리는 무엇을 파는가, 주문제작은 재고를 세는가 — 서로 모른다.
      final cake = {
        'name': '레터링 케이크',
        'category': '케이크/디저트',
        'stock': 0,
        kMadeToOrderField: true,
      };
      expect(isMadeToOrderProduct(cake), isTrue);
      expect(cats.contains(cake['category']), isTrue);
      // 주문제작이라 재고 0이어도 품절이 아니다.
      expect(
        shopProductInStock(
          stock: cake['stock'] as int,
          madeToOrder: isMadeToOrderProduct(cake),
        ),
        isTrue,
      );
      // 케이크라고 자동으로 주문제작이 되지는 않는다 — 호스트가 켜는 값이다.
      expect(
        isMadeToOrderProduct({'category': '케이크/디저트', 'stock': 5}),
        isFalse,
      );
    });
  });

  // ── ③ 사본 없음 ────────────────────────────────────────────────────────
  group('모든 화면이 같은 목록 하나를 읽는다', () {
    // 상품 등록(두 입구) · 상세검색 · 등록 유형 안내.
    const consumers = {
      'lib/screens/party_market_register_screen.dart':
          'ListingConstants.shopCategories.map(',
      'lib/screens/party_shop_product_register_screen.dart':
          'ListingConstants.shopCategories.map(',
      'lib/widgets/shop_detail_search_sheet.dart':
          'ListingConstants.shopCategories,',
      'lib/screens/register_type_screen.dart':
          "ListingConstants.shopCategories.join(' · ')",
    };

    for (final e in consumers.entries) {
      test('${e.key.split('/').last} — 정본을 읽는다', () {
        expect(_flat(_src(e.key)).contains(e.value), isTrue);
      });
    }

    test('두 등록 입구의 기본값도 정본에서 나온다', () {
      for (final path in [
        'lib/screens/party_market_register_screen.dart',
        'lib/screens/party_shop_product_register_screen.dart',
      ]) {
        expect(
          _flat(_src(path)).contains('ListingConstants.shopCategories.first'),
          isTrue,
          reason: path,
        );
      }
    });

    test('카테고리 목록을 손으로 적어 둔 사본이 없다', () {
      // 새 칸을 여기에만 넣었는데 어딘가 사본이 있으면 그 화면만 옛 목록을
      // 보여준다. 정본 파일 말고 다른 곳에 '케이터링/음료'가 나오면 사본이다.
      final copies = <String>[];
      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final normalized = file.path.replaceAll(r'\', '/');
        if (normalized.endsWith('lib/models/listing_constants.dart')) continue;
        if (file.readAsStringSync().contains("'케이터링/음료'")) {
          copies.add(normalized);
        }
      }
      expect(copies, isEmpty, reason: copies.join(', '));
    });
  });
}

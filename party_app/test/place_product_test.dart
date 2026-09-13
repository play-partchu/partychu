import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/models/place_product.dart';

/// 플레이스 공통 상품 모델 — 판매 상태 계산, 직렬화 왕복, 유형 명세 검증.
void main() {
  PlaceProduct base({
    int totalStock = 0,
    int soldCount = 0,
    DateTime? saleStartAt,
    DateTime? saleEndAt,
    DateTime? useStartAt,
    DateTime? useEndAt,
    bool manuallyStopped = false,
    int listPrice = 0,
    int salePrice = 0,
  }) =>
      PlaceProduct.empty(
        placeId: 'p1',
        placeCollection: 'events',
        hostId: 'host1',
        sortOrder: 0,
      ).copyWith(
        name: '웰컴드링크',
        totalStock: totalStock,
        soldCount: soldCount,
        saleStartAt: saleStartAt,
        saleEndAt: saleEndAt,
        useStartAt: useStartAt,
        useEndAt: useEndAt,
        manuallyStopped: manuallyStopped,
        listPrice: listPrice,
        salePrice: salePrice,
      );

  final now = DateTime(2026, 8, 4, 12);

  group('판매 상태', () {
    test('기간·재고 제한이 없으면 판매 중', () {
      expect(base().statusAt(now), PlaceProductStatus.onSale);
    });

    test('판매 시작 전이면 판매 예정', () {
      final p = base(saleStartAt: now.add(const Duration(days: 1)));
      expect(p.statusAt(now), PlaceProductStatus.scheduled);
    });

    test('판매 종료 후면 판매 종료', () {
      final p = base(saleEndAt: now.subtract(const Duration(hours: 1)));
      expect(p.statusAt(now), PlaceProductStatus.ended);
    });

    test('수량을 다 팔면 품절', () {
      expect(
        base(totalStock: 10, soldCount: 10).statusAt(now),
        PlaceProductStatus.soldOut,
      );
    });

    test('수량 0(무제한)이면 많이 팔려도 품절이 아니다', () {
      expect(
        base(totalStock: 0, soldCount: 999).statusAt(now),
        PlaceProductStatus.onSale,
      );
      expect(base(totalStock: 0, soldCount: 999).remainingStock, isNull);
    });

    test('수동 중지가 기간·재고보다 우선한다', () {
      final p = base(
        manuallyStopped: true,
        saleStartAt: now.subtract(const Duration(days: 1)),
        saleEndAt: now.add(const Duration(days: 1)),
      );
      expect(p.statusAt(now), PlaceProductStatus.stopped);
    });

    test('판매 기간이 끝났으면 품절보다 판매 종료로 읽는다', () {
      final p = base(
        totalStock: 5,
        soldCount: 5,
        saleEndAt: now.subtract(const Duration(hours: 1)),
      );
      expect(p.statusAt(now), PlaceProductStatus.ended);
    });

    test('판매 중일 때만 구매 버튼이 열린다', () {
      expect(PlaceProductStatus.onSale.isBuyable, isTrue);
      for (final s in PlaceProductStatus.values.where(
        (s) => s != PlaceProductStatus.onSale,
      )) {
        expect(s.isBuyable, isFalse, reason: '${s.label}은 구매할 수 없어야 한다');
      }
    });
  });

  group('가격·이용 기간', () {
    test('정상가가 판매가보다 크면 할인율을 계산한다', () {
      expect(base(listPrice: 10000, salePrice: 7000).discountPercent, 30);
    });

    test('정상가가 없거나 할인이 아니면 할인율 0', () {
      expect(base(listPrice: 0, salePrice: 7000).discountPercent, 0);
      expect(base(listPrice: 7000, salePrice: 7000).discountPercent, 0);
      expect(base(listPrice: 5000, salePrice: 7000).discountPercent, 0);
    });

    test('이용 기간을 안 정했으면 언제든 사용 가능', () {
      expect(base().isUsableOn(now), isTrue);
    });

    test('이용 기간의 마지막 날 당일도 사용 가능', () {
      final p = base(
        useStartAt: DateTime(2026, 8, 1),
        useEndAt: DateTime(2026, 8, 4),
      );
      expect(p.isUsableOn(DateTime(2026, 8, 4, 23)), isTrue);
      expect(p.isUsableOn(DateTime(2026, 8, 5)), isFalse);
      expect(p.isUsableOn(DateTime(2026, 7, 31)), isFalse);
    });
  });

  group('직렬화', () {
    test('toMap → fromMap 왕복이 값을 보존한다', () {
      final p =
          base(
            totalStock: 20,
            soldCount: 3,
            listPrice: 12000,
            salePrice: 9000,
            saleStartAt: DateTime(2026, 8, 1, 10),
            useEndAt: DateTime(2026, 9, 30),
          ).copyWith(
            type: PlaceProductType.drinkVoucher,
            saleChannel: PlaceProductSaleChannel.both,
            useQrCheck: true,
            perPersonLimit: 2,
            typeData: {'drinkName': '생맥주', 'servingCount': 1},
          );

      final back = PlaceProduct.fromMap('id1', p.toMap(now: now));

      expect(back.id, 'id1');
      expect(back.type, PlaceProductType.drinkVoucher);
      expect(back.saleChannel, PlaceProductSaleChannel.both);
      expect(back.name, '웰컴드링크');
      expect(back.listPrice, 12000);
      expect(back.salePrice, 9000);
      expect(back.totalStock, 20);
      expect(back.soldCount, 3);
      expect(back.perPersonLimit, 2);
      expect(back.useQrCheck, isTrue);
      expect(back.saleStartAt, DateTime(2026, 8, 1, 10));
      expect(back.useEndAt, DateTime(2026, 9, 30));
      expect(back.typeData['drinkName'], '생맥주');
    });

    test('statusMirror는 계산된 상태를 그대로 미러링한다', () {
      final p = base(manuallyStopped: true);
      expect(p.toMap(now: now)['statusMirror'], PlaceProductStatus.stopped.key);
    });

    test('빈 문서를 읽어도 터지지 않고 기본값이 채워진다', () {
      final p = PlaceProduct.fromMap('x', const {});
      expect(p.type, PlaceProductType.etc);
      expect(p.saleChannel, PlaceProductSaleChannel.standalone);
      expect(p.placeCollection, 'events');
      expect(p.statusAt(now), PlaceProductStatus.onSale);
    });

    test('모르는 유형 키는 기타 상품으로 떨어진다(옛 앱 하위호환)', () {
      final p = PlaceProduct.fromMap('x', const {'type': '__future_type__'});
      expect(p.type, PlaceProductType.etc);
    });

    test('임시저장 미러의 밀리초 날짜도 읽는다', () {
      final ms = DateTime(2026, 8, 1).millisecondsSinceEpoch;
      final p = PlaceProduct.fromMap('x', {'saleStartAt': ms});
      expect(p.saleStartAt, DateTime(2026, 8, 1));
    });
  });

  group('유형 명세', () {
    test('13종 전부 선언돼 있고 key가 겹치지 않는다', () {
      expect(PlaceProductType.values.length, 13);
      final keys = PlaceProductType.values.map((t) => t.key).toSet();
      expect(keys.length, 13);
    });

    test('기타를 뺀 모든 유형에 부가 입력 항목이 정의돼 있다', () {
      for (final t in PlaceProductType.values) {
        expect(
          fieldsForProductType(t),
          isNotEmpty,
          reason: '${t.label}의 입력 항목이 비어 있다',
        );
      }
    });

    test('유형 안에서 필드 key가 겹치지 않는다', () {
      for (final t in PlaceProductType.values) {
        final keys = fieldsForProductType(t).map((f) => f.key).toList();
        expect(keys.toSet().length, keys.length, reason: '${t.label}에 중복 key');
      }
    });

    test('날짜 지정 상품만 서버 일시 검증 대상이다', () {
      expect(PlaceProductType.seatReservation.isDateBound, isTrue);
      expect(PlaceProductType.ticket.isDateBound, isTrue);
      expect(PlaceProductType.membership.isDateBound, isFalse);
      expect(PlaceProductType.stamp.isDateBound, isFalse);
    });

    test('판매 방식이 단독/부가 허용 여부를 바르게 가른다', () {
      expect(PlaceProductSaleChannel.standalone.allowsStandalone, isTrue);
      expect(PlaceProductSaleChannel.standalone.allowsAddon, isFalse);
      expect(
        PlaceProductSaleChannel.reservationAddon.allowsStandalone,
        isFalse,
      );
      expect(PlaceProductSaleChannel.reservationAddon.allowsAddon, isTrue);
      expect(PlaceProductSaleChannel.both.allowsStandalone, isTrue);
      expect(PlaceProductSaleChannel.both.allowsAddon, isTrue);
    });
  });

  group('주문 상태', () {
    test('사용 가능 상태에서만 QR 사용 처리를 받는다', () {
      expect(PlaceProductOrderStatus.usable.isRedeemable, isTrue);
      for (final s in PlaceProductOrderStatus.values.where(
        (s) => s != PlaceProductOrderStatus.usable,
      )) {
        expect(s.isRedeemable, isFalse, reason: '${s.label}은 사용 처리 불가여야 한다');
      }
    });

    test('결제 완료·사용 가능만 살아 있는 이용권으로 본다', () {
      expect(PlaceProductOrderStatus.paid.isAlive, isTrue);
      expect(PlaceProductOrderStatus.usable.isAlive, isTrue);
      expect(PlaceProductOrderStatus.used.isAlive, isFalse);
      expect(PlaceProductOrderStatus.refunded.isAlive, isFalse);
      expect(PlaceProductOrderStatus.expired.isAlive, isFalse);
    });

    test('7종 상태가 모두 선언돼 있다', () {
      expect(PlaceProductOrderStatus.values.length, 7);
    });
  });
  group('임시저장 왕복', () {
    test('toDraftMap은 JSON으로 인코딩된다(Timestamp가 섞이지 않는다)', () {
      final p = base(
        saleStartAt: DateTime(2026, 8, 1),
        useEndAt: DateTime(2026, 9, 30),
      ).copyWith(typeData: {'drinkName': '생맥주'});
      // Timestamp가 남아 있으면 여기서 던진다 — 임시저장은 JSON 문자열이다.
      expect(() => jsonEncode(p.toDraftMap()), returnsNormally);
    });

    test('목록 저장 → 복원이 값과 순서를 보존한다', () {
      final list = [
        base(listPrice: 10000, salePrice: 8000).copyWith(
          name: '웰컴드링크',
          type: PlaceProductType.drinkVoucher,
          sortOrder: 0,
          typeData: {'drinkName': '생맥주', 'servingCount': 2},
        ),
        base().copyWith(
          name: '조식 이용권',
          type: PlaceProductType.foodVoucher,
          saleChannel: PlaceProductSaleChannel.reservationAddon,
          sortOrder: 1,
          useQrCheck: true,
        ),
      ];

      // 실제 임시저장 경로와 같게 JSON 문자열을 거쳐 되돌린다.
      final revived = PlaceProduct.listFromDraft(
        jsonDecode(jsonEncode(PlaceProduct.listToDraft(list))),
      );

      expect(revived.length, 2);
      expect(revived[0].name, '웰컴드링크');
      expect(revived[0].type, PlaceProductType.drinkVoucher);
      expect(revived[0].salePrice, 8000);
      expect(revived[0].typeData['servingCount'], 2);
      expect(revived[1].name, '조식 이용권');
      expect(revived[1].saleChannel, PlaceProductSaleChannel.reservationAddon);
      expect(revived[1].useQrCheck, isTrue);
      expect(revived[1].sortOrder, 1);
    });

    test('형식이 어긋난 임시저장은 조용히 건너뛴다', () {
      expect(PlaceProduct.listFromDraft(null), isEmpty);
      expect(PlaceProduct.listFromDraft('망가진 값'), isEmpty);
      expect(PlaceProduct.listFromDraft([1, 'x']), isEmpty);
    });

    test('날짜가 밀리초로 저장되고 그대로 복원된다', () {
      final p = base(saleStartAt: DateTime(2026, 8, 1, 9, 30));
      final map = p.toDraftMap();
      expect(map['saleStartAt'], isA<int>());
      expect(
        PlaceProduct.fromMap('x', map).saleStartAt,
        DateTime(2026, 8, 1, 9, 30),
      );
    });
  });
}

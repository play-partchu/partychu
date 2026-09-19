// 장소대여 룸(옵션)의 **가격 문의** — 숫자 0원이 아니라 '가격 문의'로 보이고,
// 기존 룸(필드 없음)은 예전과 똑같이 숫자 요금으로 읽힌다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/place_sort_mode.dart';
import 'package:party_app/models/reservation_modes.dart';
import 'package:party_app/models/room_price_type.dart';
import 'package:party_app/widgets/place_card_widget.dart';
import 'package:party_app/widgets/place_form/room_card.dart';

void main() {
  group('RoomPriceType — 없으면 fixed', () {
    test('필드가 없는 기존 룸·장소는 fixed', () {
      expect(RoomPriceType.of({'pricePerHour': 50000}), RoomPriceType.fixed);
      expect(RoomPriceType.of(null), RoomPriceType.fixed);
      expect(RoomPriceType.of({'priceType': '???'}), RoomPriceType.fixed);
      expect(isInquiryRoom({'pricePerHour': 50000}), isFalse);
    });

    test("'inquiry'만 가격 문의", () {
      expect(isInquiryRoom({'priceType': 'inquiry'}), isTrue);
      expect(isInquiryPlace({'priceType': 'inquiry'}), isTrue);
      expect(isInquiryRoom({'priceType': 'fixed'}), isFalse);
    });
  });

  group('placePriceSummary — 문의 룸은 대표가 후보가 아니다', () {
    test('기존 룸만 있으면 예전과 같다', () {
      final s = placePriceSummary([
        {'pricePerHour': 50000},
        {'pricePerHour': 30000},
      ]);
      expect(s.price, 30000);
      expect(s.unit, 'hour');
    });

    test('문의 룸의 남은 숫자는 무시한다', () {
      final s = placePriceSummary([
        {'pricePerHour': 50000},
        {'pricePerHour': 1000, 'priceType': 'inquiry'},
      ]);
      expect(s.price, 50000);
    });

    test('문의 룸뿐이면 대표가 0', () {
      expect(
        placePriceSummary([
          {'pricePerHour': 0, 'priceType': 'inquiry'},
        ]).price,
        0,
      );
    });
  });

  group('장소대여 카드 요금 줄', () {
    PlaceCardInfo info(Map<String, dynamic> d) =>
        PlaceCardInfo.from(d, source: PlaceCardSource.rental, tag: 'test');

    test("문의 장소는 '무료'가 아니라 '가격 문의'", () {
      expect(
        info({
          'name': 'x',
          'pricePerHour': 0,
          'priceType': 'inquiry',
        }).priceLabel,
        kInquiryPriceLabel,
      );
    });

    test('필드 없는 0원 장소는 기존 그대로(로그인 전 잠금)', () {
      // 로그인하지 않은 테스트 환경 — 기존 카드는 금액 대신 잠금 문구다.
      expect(info({'name': 'x', 'pricePerHour': 0}).priceLabel, '🔒 로그인 필요');
    });
  });

  test('금액순 정렬에서 문의 장소는 맨 뒤', () {
    final docs = [
      {'id': 'inq', 'pricePerHour': 0, 'priceType': 'inquiry'},
      {'id': 'b', 'pricePerHour': 30000},
      {'id': 'a', 'pricePerHour': 10000},
    ];
    List<String> order(PlaceSortMode m) => ([
      ...docs,
    ]..sort(placeSortComparator(m)!)).map((d) => d['id'] as String).toList();
    expect(order(PlaceSortMode.hourPriceLow), ['a', 'b', 'inq']);
    expect(order(PlaceSortMode.hourPriceHigh), ['b', 'a', 'inq']);
  });

  group('룸 등록 카드 — [가격 입력] / [가격 문의]', () {
    Future<GlobalKey<RoomCardState>> pump(
      WidgetTester tester,
      Map<String, dynamic> data,
    ) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final key = GlobalKey<RoomCardState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RoomCard(
                key: key,
                index: 0,
                onRemove: () {},
                roomId: 'room1',
                initialData: data,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return key;
    }

    const refund = [
      {'daysBefore': 7, 'refundPercent': 100},
    ];

    testWidgets('가격 입력(기존)은 시간당 가격이 여전히 필수', (tester) async {
      final key = await pump(tester, {
        'roomName': '룸',
        'capacityMin': 1,
        'capacityMax': 10,
        'refundPolicy': refund,
      });
      await tester.enterText(find.byType(TextField).at(0), '룸');
      // 시간당 가격 칸을 비운다.
      key.currentState!.applyFromData({'price': '', 'capacityMax': '10'});
      await tester.pump();
      expect(key.currentState!.validate(), isFalse);
    });

    testWidgets('가격 문의는 숫자 요금 없이 저장되고 priceType이 남는다', (tester) async {
      final key = await pump(tester, {
        'roomName': '클럽 통대관',
        'capacityMin': 1,
        'capacityMax': 100,
        'pricePerHour': 0,
        'priceType': 'inquiry',
        'refundPolicy': refund,
      });
      expect(key.currentState!.validate(), isTrue);
      expect(key.currentState!.getDraftData()['priceType'], 'inquiry');
    });

    testWidgets('가격 문의를 고르면 시간당 가격 입력칸이 사라진다', (tester) async {
      final key = await pump(tester, {
        'roomName': '룸',
        'capacityMin': 1,
        'capacityMax': 10,
      });
      // 환불 규정이 없어 저장이 막히면서 카드가 펼쳐진다.
      expect(key.currentState!.validate(), isFalse);
      await tester.pumpAndSettle();
      expect(find.text('시간당 가격 (원) *'), findsOneWidget);

      await tester.tap(find.text('가격 문의'));
      await tester.pumpAndSettle();
      expect(find.text('시간당 가격 (원) *'), findsNothing);
      expect(key.currentState!.getDraftData()['priceType'], 'inquiry');
    });
  });
}

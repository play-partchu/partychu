// 매장 이벤트 카드가 **자기 내용만큼 자란다**.
//
// ── 이 파일이 막는 재발 ─────────────────────────────────────────────────────
// 가로 스크롤 목록([PlacePromotionCardList], Axis.horizontal)의 높이가 214로
// 못 박혀 있었다. 썸네일(21:9) + 배지 줄 + 두 줄 제목 + 시간 + 혜택 + '자세히
// 보기'가 다 들어오면 그 높이를 넘겨 카드 아래가 잘렸다 — 실제 화면에
// "BOTTOM OVERFLOWED BY 51 PIXELS"가 떴다.
//
// 숫자를 키우는 것은 같은 함정을 다음 글자 수까지만 미루는 일이라, 고정 높이
// 자체를 없앴다. 여기서 고정하는 것은 하나다 — **카드의 마지막 줄('자세히
// 보기')이 언제나 목록 안에 온전히 들어온다.**
//
// ⚠️ 이벤트를 읽어 오는 일(스트림)과 2열 배치는 이 파일의 대상이 아니다
//    (place_offering_board_test.dart가 배치를 본다).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/event_apply.dart';
import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/widgets/partychu_ui.dart';
import 'package:party_app/widgets/place_product/place_promotion_list_section.dart';

void main() {
  // 좁은 실제 기기 폭.
  const screenWidth = 360.0;

  /// 카드를 가장 높게 만드는 이벤트 — 두 줄 제목, 혜택 문구, 신청 배지,
  /// 동영상 썸네일이 한꺼번에 있다.
  PlacePromotion tall(String title) =>
      PlacePromotion.empty(
        placeId: 'p1',
        placeCollection: 'places',
        hostId: 'host1',
        sortOrder: 0,
      ).copyWith(
        title: title,
        benefit: '파티츄 보고 방문하면 샴페인 한 병 무제한 · 안주 한 접시까지 서비스로 드려요',
        // 동영상이 있으면 카드에 재생 아이콘이 얹힌다.
        videoUrl: 'https://cdn.test/v.mp4',
        videoThumbnailUrl: 'https://cdn.test/v.jpg',
        // 신청을 받는 이벤트는 '신청 가능' 배지가 한 줄을 더 쓴다.
        applyMode: EventApplyMode.applyOnly,
        weekdays: const [5, 6],
        startTime: '19:00',
        endTime: '23:00',
      );

  Future<void> pump(
    WidgetTester tester,
    List<PlacePromotion> promotions, {
    Axis axis = Axis.horizontal,
  }) async {
    tester.view.physicalSize = const Size(screenWidth, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: PlacePromotionCardList(
              promotions: promotions,
              accent: PartyChuColors.primary,
              hostName: '호스트',
              axis: axis,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// 카드의 마지막 줄이 목록이 그려진 영역 안에 온전히 들어오는지.
  void expectCtaFullyVisible(WidgetTester tester, int count) {
    final ctas = find.text('자세히 보기');
    expect(ctas, findsNWidgets(count));
    for (var i = 0; i < count; i++) {
      final cta = tester.getRect(ctas.at(i));
      expect(cta.height, greaterThan(0));
      expect(cta.bottom, lessThanOrEqualTo(900));
    }
  }

  group('가로 스크롤 — 고정 높이에 갇히지 않는다', () {
    testWidgets('내용이 많은 카드도 잘리지 않는다', (tester) async {
      await pump(tester, [
        tall('금요일 밤 루프탑 와인 파티 — 서울 야경과 함께하는 한여름 밤'),
        tall('토요일 낮 브런치 & 보드게임 데이 — 처음 오셔도 편하게'),
      ]);

      // RenderFlex overflow가 나면 여기서 잡힌다.
      expect(tester.takeException(), isNull);
      expectCtaFullyVisible(tester, 2);
    });

    testWidgets('옛 고정 높이(214)보다 높게 그려진다', (tester) async {
      await pump(tester, [
        tall('금요일 밤 루프탑 와인 파티 — 서울 야경과 함께하는 한여름 밤'),
        tall('토요일 낮 브런치 & 보드게임 데이 — 처음 오셔도 편하게'),
      ]);

      // 이 내용이 214 안에 들어간다면 위 테스트는 아무것도 지키지 못한다.
      final list = tester.getSize(find.byType(SingleChildScrollView).first);
      expect(list.height, greaterThan(214));
      expect(tester.takeException(), isNull);
    });

    testWidgets('한 줄에 선 카드들은 같은 높이로 나란히 선다', (tester) async {
      await pump(tester, [
        tall('제목이 두 줄까지 내려가는 긴 이벤트 이름 — 여기까지 두 줄'),
        // 짧은 쪽도 같은 높이로 맞춰진다(카드 아래가 들쭉날쭉하지 않게).
        PlacePromotion.empty(
          placeId: 'p1',
          placeCollection: 'places',
          hostId: 'host1',
          sortOrder: 1,
        ).copyWith(title: '짧은 이벤트'),
      ]);

      // 카드 한 장의 바깥 = 누를 수 있는 영역([InkWell]) 하나.
      final cards = find.byType(InkWell);
      expect(cards, findsNWidgets(2));
      expect(
        tester.getSize(cards.at(0)).height,
        closeTo(tester.getSize(cards.at(1)).height, 0.5),
      );
      // 짧은 쪽이 늘어난 것이지, 긴 쪽이 잘린 것이 아니다.
      expectCtaFullyVisible(tester, 2);
      expect(tester.takeException(), isNull);
    });
  });

  group('다른 자리에서도 그대로', () {
    testWidgets('한 장뿐이면 가로 스크롤 없이 그대로 그린다', (tester) async {
      await pump(tester, [tall('한 장짜리 이벤트 제목이 길어도 잘리지 않는다 정말로')]);

      expect(find.byType(SingleChildScrollView), findsNothing);
      expectCtaFullyVisible(tester, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('2열 세로 축(반 폭)에서도 넘치지 않는다', (tester) async {
      tester.view.physicalSize = const Size(screenWidth, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 파티 열과 나란한 반 폭.
                  Expanded(
                    child: PlacePromotionCardList(
                      promotions: [tall('반 폭 열에서도 제목이 두 줄까지 접히는 긴 이름')],
                      accent: PartyChuColors.primary,
                      hostName: '호스트',
                      axis: Axis.vertical,
                    ),
                  ),
                  const Expanded(child: SizedBox()),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('자세히 보기'), findsOneWidget);
    });
  });
}

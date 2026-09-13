import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/host_offering.dart';
import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/widgets/linked_party_card.dart';
import 'package:party_app/widgets/offering_card_shell.dart';
import 'package:party_app/widgets/partychu_ui.dart';
import 'package:party_app/widgets/place_offering_board.dart';
import 'package:party_app/widgets/place_product/place_promotion_list_section.dart';

/// 플레이스 상세의 🎉 파티 | ✨ 이벤트 영역 — **좌우 2열 배치**.
///
/// 탭이 아니라 두 열이 동시에 서는 구조라, 여기서 지키는 것은 세 가지다.
///  1. 폭은 **언제나 반반**이다 — 한쪽만 있어도 그 열이 전체 폭으로 커지지
///     않는다(같은 파티가 매장 사정에 따라 다른 크기로 보이지 않게)
///  2. 좁은 실제 모바일 폭에서 카드가 넘치거나 잘리지 않는다
///  3. 파티는 파티츄 핑크, 이벤트는 샴페인 골드 — 두 열이 테두리로 갈린다
///
/// 조회(Firestore)는 이 테스트의 관심사가 아니다. 배치와 카드만 본다.
void main() {
  // 좁은 실제 기기 폭. 상세 본문 좌우 여백 20씩을 빼면 320이 남는다.
  const screenWidth = 360.0;
  const contentWidth = 320.0;

  final party = <String, dynamic>{
    'title': '금요일 밤 와인 모임 함께해요',
    'recruitStatus': '모집중',
    'maleFee': 20000,
    'femaleFee': 20000,
  };

  PlacePromotion promo(String title) =>
      PlacePromotion.empty(
        placeId: 'p1',
        placeCollection: 'events',
        hostId: 'host1',
        sortOrder: 0,
      ).copyWith(
        title: title,
        benefit: '파티츄 보고 방문 시 샴페인 무제한',
        imageUrls: const ['https://cdn.example.com/event.jpg'],
      );

  // 열 폭을 재려면 열 자체를 집어야 한다 — find.byType(Expanded)로 재면
  // 카드 **안쪽**의 Expanded(제목 줄 등)까지 걸려 엉뚱한 값이 섞인다.
  const partyKey = ValueKey('party-column');
  const eventKey = ValueKey('event-column');

  Widget partyColumn(int count) => KeyedSubtree(
    key: partyKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < count; i++)
          LinkedPartyCard(partyId: 'party$i', party: party),
      ],
    ),
  );

  Widget eventColumn(int count) => KeyedSubtree(
    key: eventKey,
    child: PlacePromotionCardList(
      promotions: [for (var i = 0; i < count; i++) promo('이벤트 제목 $i')],
      accent: PartyChuColors.primary,
      hostName: '호스트',
      axis: Axis.vertical,
    ),
  );

  Future<void> pump(
    WidgetTester tester, {
    Widget? partyChild,
    Widget? eventChild,
    // 펼친 열은 화면보다 길어진다 — 더보기/접기 줄을 누르려면 뷰가 그만큼
    // 길어야 한다(스크롤 위치를 따로 맞추지 않기 위해).
    double height = 900,
  }) async {
    tester.view.physicalSize = Size(screenWidth, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              // 상세 본문과 같은 좌우 여백.
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: OfferingColumns(party: partyChild, event: eventChild),
            ),
          ),
        ),
      ),
    );
  }

  /// 실제로 그려진 열의 폭 — 놓아 준 열만 골라 잰다.
  List<double> columnWidths(WidgetTester tester) => [
    for (final key in [partyKey, eventKey])
      if (find.byKey(key).evaluate().isNotEmpty)
        tester.getSize(find.byKey(key)).width,
  ];

  group('폭 배분', () {
    testWidgets('파티1 + 이벤트1 — 좌우 정확히 반반', (tester) async {
      await pump(
        tester,
        partyChild: partyColumn(1),
        eventChild: eventColumn(1),
      );

      final widths = columnWidths(tester);
      expect(widths.length, 2);
      // 사이 간격을 뺀 나머지를 정확히 절반씩.
      const half = (contentWidth - kOfferingColumnGap) / 2;
      expect(widths[0], half);
      expect(widths[1], half);
      expect(widths[0], widths[1]);
      expect(tester.takeException(), isNull);
    });

    // 한쪽만 있어도 폭은 그대로다. 예전에는 그 열이 전체 폭을 썼는데, 그러면
    // 이벤트가 하나 등록되는 순간 같은 파티 카드가 절반으로 줄어든다.
    const half = (contentWidth - kOfferingColumnGap) / 2;

    testWidgets('파티만 있어도 반 폭 — 전체 너비로 커지지 않는다', (tester) async {
      await pump(tester, partyChild: partyColumn(1));

      expect(columnWidths(tester), [half]);
      expect(find.byType(LinkedPartyCard), findsOneWidget);
      // 카드도 그 열 폭 그대로다.
      expect(tester.getSize(find.byType(LinkedPartyCard)).width, half);
      expect(tester.takeException(), isNull);
    });

    testWidgets('이벤트만 있어도 반 폭 — 전체 너비로 커지지 않는다', (tester) async {
      await pump(tester, eventChild: eventColumn(1));

      expect(columnWidths(tester), [half]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('한쪽만 있을 때와 둘 다 있을 때의 카드 폭이 같다', (tester) async {
      await pump(tester, partyChild: partyColumn(1));
      final alone = tester.getSize(find.byType(LinkedPartyCard)).width;

      await pump(
        tester,
        partyChild: partyColumn(1),
        eventChild: eventColumn(1),
      );
      final together = tester.getSize(find.byType(LinkedPartyCard)).width;

      expect(alone, together);
    });

    testWidgets('둘 다 없으면 아무것도 그리지 않는다', (tester) async {
      await pump(tester);

      expect(tester.getSize(find.byType(OfferingColumns)).height, 0);
      expect(find.byType(Expanded), findsNothing);
    });
  });

  group('여러 개', () {
    testWidgets('각 열에서 아래로 이어지고, 개수가 달라도 빈 카드를 만들지 않는다', (tester) async {
      await pump(
        tester,
        partyChild: partyColumn(3),
        eventChild: eventColumn(2),
      );

      // 파티 3장 · 이벤트 2장 — 짧은 쪽을 채우지 않는다.
      expect(find.byType(LinkedPartyCard), findsNWidgets(3));
      expect(find.textContaining('이벤트 제목'), findsNWidgets(2));
      // 세로로 쌓이므로 반 폭 열 안에 가로 스크롤이 생기지 않는다.
      expect(find.byType(ListView), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('좁은 폭에서 넘치지 않는다', () {
    // 반 폭 열은 이 화면에서 155dp뿐이다. 카드 안쪽은 130dp 안팎이라,
    // 전체 폭을 전제로 만든 요소가 그대로 들어오면 RenderFlex overflow가 난다.
    testWidgets('파티·이벤트 카드 모두 넘침 없이 그려진다', (tester) async {
      await pump(
        tester,
        partyChild: partyColumn(2),
        eventChild: eventColumn(2),
      );

      expect(tester.takeException(), isNull);
      // 카드가 자기 열 밖으로 나가지 않는다.
      const half = (contentWidth - kOfferingColumnGap) / 2;
      for (final card in find.byType(LinkedPartyCard).evaluate()) {
        expect(tester.getSize(find.byWidget(card.widget)).width, half);
      }
    });

    testWidgets('두 카드의 CTA가 같은 부품·같은 자리다', (tester) async {
      await pump(
        tester,
        partyChild: partyColumn(1),
        eventChild: eventColumn(1),
      );

      // 파티 카드와 이벤트 카드가 같은 '자세히 보기 >' 줄로 끝난다.
      expect(find.byType(OfferingCardMoreLink), findsNWidgets(2));
      expect(find.text('자세히 보기'), findsNWidgets(2));
      // 좁은 칸에서도 줄바꿈 대신 한 줄로 남는다.
      for (final label in tester.widgetList<Text>(find.text('자세히 보기'))) {
        expect(label.maxLines, 1);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('두 카드의 사진 자리가 같은 비율이다', (tester) async {
      await pump(
        tester,
        partyChild: partyColumn(1),
        eventChild: eventColumn(1),
      );

      // 파티 카드와 이벤트 카드가 같은 높이의 사진 자리를 쓴다 — 나란히 선 두
      // 카드의 크기 균형(반 폭 열에서는 이벤트도 기본 카드 비율을 쓴다).
      final boxes = find.byType(AspectRatio);
      expect(boxes, findsNWidgets(2));
      final ratios = tester
          .widgetList<AspectRatio>(boxes)
          .map((a) => a.aspectRatio)
          .toSet();
      expect(ratios.length, 1);
      // 실제로 그려진 높이까지 같다.
      final heights = tester
          .widgetList<AspectRatio>(boxes)
          .map((w) => tester.getSize(find.byWidget(w)).height)
          .toSet();
      expect(heights.length, 1);
    });
  });

  // ── 더보기/접기 ───────────────────────────────────────────────────────────
  // 열 하나는 처음에 두 장까지만 펼쳐 두고, 나머지는 그 열 아래 '더보기'로
  // 접어 둔다. 여기서 세우는 열은 실제 화면([PlaceOfferingBoard])이 만드는 것과
  // 같은 조합이다 — 머리(전체 개수) + 앞에서 몇 장을 그릴지 묻는 builder.

  /// 실제 화면과 같은 방식으로 만든 🎉 파티 열.
  Widget partyBoardColumn(int total) => KeyedSubtree(
    key: partyKey,
    child: OfferingColumn(
      offering: HostOffering.party,
      total: total,
      accent: PartyChuColors.primary,
      builder: (visible) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < visible; i++)
            LinkedPartyCard(partyId: 'party$i', party: party),
        ],
      ),
    ),
  );

  /// 실제 화면과 같은 방식으로 만든 ✨ 이벤트 열.
  Widget eventBoardColumn(int total) {
    final all = [for (var i = 0; i < total; i++) promo('이벤트 제목 $i')];
    return KeyedSubtree(
      key: eventKey,
      child: OfferingColumn(
        offering: HostOffering.placeEvent,
        total: total,
        accent: PartyChuColors.primary,
        builder: (visible) => PlacePromotionCardList(
          promotions: all.take(visible).toList(),
          accent: PartyChuColors.primary,
          hostName: '호스트',
          axis: Axis.vertical,
        ),
      ),
    );
  }

  int partyCards(WidgetTester tester) =>
      find.byType(LinkedPartyCard).evaluate().length;
  int eventCards(WidgetTester tester) =>
      find.textContaining('이벤트 제목').evaluate().length;

  group('열마다 처음엔 두 장까지', () {
    testWidgets('1개 — 그대로 한 장, 더보기 없음', (tester) async {
      await pump(tester, partyChild: partyBoardColumn(1));

      expect(partyCards(tester), 1);
      expect(find.textContaining('더보기'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('2개 — 두 장 다 보이고 더보기 없음', (tester) async {
      await pump(tester, partyChild: partyBoardColumn(2));

      expect(partyCards(tester), 2);
      expect(find.textContaining('더보기'), findsNothing);
    });

    testWidgets('3개 — 두 장 + "파티 1개 더보기"', (tester) async {
      await pump(tester, partyChild: partyBoardColumn(3));

      expect(partyCards(tester), 2);
      expect(find.text('파티 1개 더보기'), findsOneWidget);
    });

    testWidgets('5개 — 두 장 + "파티 3개 더보기"(남은 실제 개수)', (tester) async {
      await pump(tester, partyChild: partyBoardColumn(5));

      expect(partyCards(tester), 2);
      expect(find.text('파티 3개 더보기'), findsOneWidget);
    });

    testWidgets('이벤트도 같은 규칙 — 5개면 두 장 + "이벤트 3개 더보기"', (tester) async {
      await pump(tester, eventChild: eventBoardColumn(5));

      expect(eventCards(tester), 2);
      expect(find.text('이벤트 3개 더보기'), findsOneWidget);
    });

    testWidgets('접혀 있어도 머리의 숫자는 전체 개수다', (tester) async {
      await pump(
        tester,
        partyChild: partyBoardColumn(7),
        eventChild: eventBoardColumn(5),
      );

      expect(find.text('(7)'), findsOneWidget);
      expect(find.text('(5)'), findsOneWidget);
      // 보이는 카드는 각각 두 장뿐이다.
      expect(partyCards(tester), 2);
      expect(eventCards(tester), 2);
    });
  });

  group('더보기 / 접기', () {
    testWidgets('더보기를 누르면 그 열이 전부 펼쳐지고, 접기로 돌아온다', (tester) async {
      await pump(tester, eventChild: eventBoardColumn(5), height: 3000);

      await tester.tap(find.text('이벤트 3개 더보기'));
      await tester.pumpAndSettle();

      expect(eventCards(tester), 5);
      expect(find.textContaining('더보기'), findsNothing);
      expect(find.text('접기'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('접기'));
      await tester.pumpAndSettle();

      expect(eventCards(tester), 2);
      expect(find.text('이벤트 3개 더보기'), findsOneWidget);
    });

    testWidgets('파티를 펼쳐도 이벤트 열은 그대로 접혀 있다', (tester) async {
      await pump(
        tester,
        partyChild: partyBoardColumn(5),
        eventChild: eventBoardColumn(5),
        height: 3000,
      );

      await tester.tap(find.text('파티 3개 더보기'));
      await tester.pumpAndSettle();

      expect(partyCards(tester), 5);
      expect(eventCards(tester), 2);
      expect(find.text('이벤트 3개 더보기'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('이벤트를 펼쳐도 파티 열은 그대로 접혀 있다', (tester) async {
      await pump(
        tester,
        partyChild: partyBoardColumn(5),
        eventChild: eventBoardColumn(5),
        height: 3000,
      );

      await tester.tap(find.text('이벤트 3개 더보기'));
      await tester.pumpAndSettle();

      expect(eventCards(tester), 5);
      expect(partyCards(tester), 2);
      expect(find.text('파티 3개 더보기'), findsOneWidget);
    });
  });

  group('접기가 폭을 건드리지 않는다', () {
    const half = (contentWidth - kOfferingColumnGap) / 2;

    testWidgets('파티만 5개여도 반 폭 — 펼쳐도 그대로', (tester) async {
      await pump(tester, partyChild: partyBoardColumn(5), height: 3000);

      expect(tester.getSize(find.byKey(partyKey)).width, half);
      await tester.tap(find.text('파티 3개 더보기'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(partyKey)).width, half);
      expect(tester.takeException(), isNull);
    });

    testWidgets('이벤트만 5개여도 반 폭 — 오른쪽 자리 그대로', (tester) async {
      await pump(tester, eventChild: eventBoardColumn(5), height: 3000);

      expect(tester.getSize(find.byKey(eventKey)).width, half);
      // 왼쪽 절반은 비어 있고 이벤트 열은 오른쪽에 선다.
      expect(
        tester.getTopLeft(find.byKey(eventKey)).dx,
        20 + half + kOfferingColumnGap,
      );
    });

    testWidgets('둘 다 있으면 50:50 그대로', (tester) async {
      await pump(
        tester,
        partyChild: partyBoardColumn(5),
        eventChild: eventBoardColumn(5),
      );

      expect(tester.getSize(find.byKey(partyKey)).width, half);
      expect(tester.getSize(find.byKey(eventKey)).width, half);
      expect(tester.takeException(), isNull);
    });
  });

  group('테두리로 두 열이 갈린다', () {
    testWidgets('파티는 파티츄 핑크, 이벤트는 샴페인 골드', (tester) async {
      await pump(
        tester,
        partyChild: partyColumn(1),
        eventChild: eventColumn(1),
      );

      final borders = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.border)
          .whereType<Border>()
          .map((b) => b.top.color)
          .toSet();

      expect(borders, contains(PartyChuColors.border));
      expect(borders, contains(PartyChuColors.eventGold));
    });
  });
}

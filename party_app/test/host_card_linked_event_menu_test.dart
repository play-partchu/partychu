// 마이 > 파티츄 호스트의 플레이스 / 공간대여 카드 아래 관리 메뉴 —
// `🎉 연결 파티 N개` 옆에 선 `✨ 연결 이벤트 N개`.
//
// 여기서 지키는 것은 네 가지다.
//  1. 개수의 정본은 이벤트 문서의 **소속 필드**(placeId + placeCollection)다.
//     플레이스(events)와 공간대여(places)의 이벤트가 서로 섞이지 않는다.
//  2. 세는 범위는 **호스트 관리 화면과 같다** — 숨김·종료도 포함한 전부.
//     (파티 개수도 "삭제되지 않은 연결 전부"라 의미가 같은 자리다.)
//  3. 0개면 '연결 이벤트 0개'라고 세지 않는다 — 그 자리에는 지금 할 수 있는
//     일('이벤트 추가')을 적는다.
//  4. 좁은 화면(360dp)에서 두 칸이 넘치지 않는다.
//
// 이벤트의 **소속은 만든 뒤 바꿀 수 없다**(firestore.rules가 placeId /
// placeCollection / hostId 변경을 거부한다). 그래서 파티에 있는 '기존 이벤트
// 연결'·'연결 해제'에 해당하는 동작이 이벤트에는 존재하지 않는다 — 모델에도
// 그 길이 없다는 것을 아래 마지막 그룹이 지킨다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/services/place_event_entry.dart';
import 'package:party_app/services/place_promotion_service.dart';
import 'package:party_app/widgets/host/host_card_link_menus.dart';

void main() {
  PlacePromotion promo(String id, String placeId, String placeCollection) =>
      PlacePromotion.empty(
        placeId: placeId,
        placeCollection: placeCollection,
        hostId: 'host1',
        sortOrder: 0,
      ).copyWith(id: id, title: '이벤트 $id');

  EventPlaceTarget target(String collection) => const EventPlaceTarget(
    placeId: 'p1',
    placeCollection: 'events',
    hostId: 'host1',
    placeName: '내잔 혼술바',
  ).let(collection);

  group('개수 라벨', () {
    test('아직 못 셌으면 숫자를 비워 둔다', () {
      expect(linkedEventMenuLabel(null), '연결 이벤트');
    });

    test('0개면 개수를 말하지 않는다 — 할 수 있는 일을 적는다', () {
      expect(linkedEventMenuLabel(0), '이벤트 추가');
      expect(linkedEventMenuLabel(0), isNot(contains('0개')));
    });

    test('1개 이상이면 파티와 같은 모양으로 센다', () {
      expect(linkedEventMenuLabel(1), '연결 이벤트 1개');
      expect(linkedEventMenuLabel(2), '연결 이벤트 2개');
      expect(linkedEventMenuLabel(12), '연결 이벤트 12개');
    });
  });

  group('플레이스(events)와 공간대여(places)가 섞이지 않는다', () {
    // 조회는 placeId 하나로 하지만, 소속은 문서가 이미 갖고 있는
    // placeCollection으로 가른다(새 필드를 만들지 않는다).
    final mixed = [
      promo('e1', 'p1', 'events'),
      promo('e2', 'p1', 'events'),
      promo('r1', 'p1', 'places'),
    ];

    test('플레이스 카드는 events 이벤트만 센다', () {
      final only = PlacePromotionService.belongingTo(
        mixed,
        placeCollection: 'events',
      );
      expect(only.map((p) => p.id), ['e1', 'e2']);
    });

    test('공간대여 카드는 places 이벤트만 센다', () {
      final only = PlacePromotionService.belongingTo(
        mixed,
        placeCollection: 'places',
      );
      expect(only.map((p) => p.id), ['r1']);
    });

    test('한 건도 없으면 0', () {
      expect(
        PlacePromotionService.belongingTo(
          const <PlacePromotion>[],
          placeCollection: 'events',
        ),
        isEmpty,
      );
    });

    test('소속을 안 적은 옛 문서는 플레이스(events)로 읽힌다 — 기존 fromMap 기본값', () {
      final legacy = PlacePromotion.fromMap('old', {'placeId': 'p1'});
      expect(legacy.placeCollection, 'events');
      expect(
        PlacePromotionService.belongingTo([
          legacy,
        ], placeCollection: 'events').length,
        1,
      );
    });
  });

  group('세는 범위는 관리 화면과 같다 — 숨김·종료도 포함', () {
    test('숨긴 이벤트도 센다', () {
      final hidden = promo('e1', 'p1', 'events').copyWith(isVisible: false);
      expect(hidden.statusAt(DateTime.now()), PromotionStatus.hidden);
      expect(
        PlacePromotionService.belongingTo([
          hidden,
        ], placeCollection: 'events').length,
        1,
      );
    });

    test('기간이 끝난 이벤트도 센다', () {
      final ended = promo(
        'e1',
        'p1',
        'events',
      ).copyWith(startAt: DateTime(2020, 1, 1), endAt: DateTime(2020, 1, 2));
      expect(ended.statusAt(DateTime.now()), PromotionStatus.ended);
      expect(
        PlacePromotionService.belongingTo([
          ended,
        ], placeCollection: 'events').length,
        1,
      );
    });
  });

  group('메뉴 위젯', () {
    Future<void> pumpMenu(
      WidgetTester tester, {
      required int count,
      String collection = 'events',
      double width = 360,
    }) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Expanded(
                  // 실제 카드와 같은 조합 — 파티 칸과 이벤트 칸이 한 줄에
                  // 나란히 서고, 모자라면 아랫줄로 접힌다(Wrap).
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      HostCardMenuAction(
                        emoji: '🎉',
                        label: '연결 파티 1개',
                        accent: const Color(0xFFFF6FA0),
                        onTap: () {},
                      ),
                      LinkedEventMenu(
                        target: target(collection),
                        countLoader: () async => count,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('연결 파티와 연결 이벤트가 함께 보인다', (tester) async {
      await pumpMenu(tester, count: 2);

      expect(find.text('연결 파티 1개'), findsOneWidget);
      expect(find.text('연결 이벤트 2개'), findsOneWidget);
      expect(find.text('🎉'), findsOneWidget);
      expect(find.text('✨'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('0개면 "이벤트 추가"로 보인다', (tester) async {
      await pumpMenu(tester, count: 0);

      expect(find.text('이벤트 추가'), findsOneWidget);
      expect(find.textContaining('연결 이벤트 0개'), findsNothing);
    });

    testWidgets('360dp에서 넘치지 않는다', (tester) async {
      await pumpMenu(tester, count: 12);

      expect(tester.takeException(), isNull);
    });

    testWidgets('320dp(더 좁은 폰)에서도 넘치지 않는다', (tester) async {
      await pumpMenu(tester, count: 12, width: 320);

      expect(tester.takeException(), isNull);
    });

    testWidgets('강조색은 공간 유형 정본에서 온다 — 플레이스 핑크 / 공간대여 보라', (tester) async {
      // 예전에 두 카드가 각각 적어 두던 값과 같은 색이어야 한다.
      expect(target('events').accent, const Color(0xFFFF6FA0));
      expect(target('places').accent, const Color(0xFF7C5CBF));
    });
  });

  group('이벤트에는 소속을 옮기는 길이 없다', () {
    // '기존 이벤트 연결'·'연결 해제'가 UI에 없는 이유는 화면 사정이 아니라
    // 모델과 rules가 그렇기 때문이다. copyWith가 소속 세 필드를 아예 받지
    // 않는다는 것이 그 사실의 코드 쪽 증거다.
    test('copyWith로는 placeId/placeCollection/hostId를 바꿀 수 없다', () {
      final p = promo('e1', 'p1', 'events');
      final edited = p.copyWith(title: '제목만 바꿈', isVisible: false);

      expect(edited.title, '제목만 바꿈');
      expect(edited.placeId, 'p1');
      expect(edited.placeCollection, 'events');
      expect(edited.hostId, 'host1');
    });
  });
}

/// 테스트에서 컬렉션만 바꿔 같은 대상을 만들기 위한 작은 도우미.
extension on EventPlaceTarget {
  EventPlaceTarget let(String collection) => EventPlaceTarget(
    placeId: placeId,
    placeCollection: collection,
    hostId: hostId,
    placeName: placeName,
    address: address,
  );
}

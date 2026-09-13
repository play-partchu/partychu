// 마이페이지 → 파티샵 메뉴 노출 — **누가 무엇을 보는가**만 확인한다.
//
// 이 기능이 실제로 깨지는 자리는 둘이다.
//   1. 판정 — "파티샵 판매자"를 역할(호스트/사업자)로 잘못 재면, 파티나
//      플레이스만 운영하는 사람에게 영원히 빈 '판매' 탭이 열린다. 반대로
//      운영 중지(폐점)한 샵 주인의 메뉴를 지워 버리면 다시 열 길이 없다.
//   2. 노출 — 판정이 맞아도 화면이 탭을 그대로 그리면 의미가 없다.
//      판매자가 아닌 사람에게 '내 파티샵'·'판매'는 비활성이 아니라 **없어야**
//      한다.
// 그래서 판정([PartyShopOwnershipService.hasLiveShop])과 화면([ShopHubView])을
// 각각 건다. 목록 내용(주문·샵 카드)은 여기서 보지 않는다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/screens/my_host_hub_screen.dart';
import 'package:party_app/services/party_shop_ownership_service.dart';
import 'package:party_app/utils/user_session.dart';

/// 등록된 파티샵 문서 한 건(판정에 쓰이는 필드만).
Map<String, dynamic> shop({bool? isActive, bool? isDeleted, String? status}) =>
    <String, dynamic>{
      'name': '테스트 파티샵',
      'hostId': 'u1',
      'isActive': ?isActive,
      'isDeleted': ?isDeleted,
      'status': ?status,
    };

void main() {
  group('판매자 판정은 실제 보유한 파티샵 문서로만 한다', () {
    test('일반 사용자 — 파티샵 문서가 없으면 판매자가 아니다', () {
      expect(PartyShopOwnershipService.hasLiveShop(const []), isFalse);
    });

    test('파티·플레이스 호스트지만 파티샵 없음 — 역시 판매자가 아니다', () {
      // 파티/플레이스/장소대여는 parties·events·places 컬렉션이라
      // partyShops 조회 결과는 그대로 0건이다. 판정에 쓰는 입력이 이
      // 컬렉션 하나뿐이라는 것이 이 케이스의 전부다.
      expect(PartyShopOwnershipService.hasLiveShop(const []), isFalse);
    });

    test('파티샵 판매자 — 운영 중인 샵이 있으면 판매자다', () {
      expect(
        PartyShopOwnershipService.hasLiveShop([shop(isActive: true)]),
        isTrue,
      );
    });

    test('운영 중지(폐점)한 샵도 보유는 보유다 — 재개·지난 판매내역 때문', () {
      expect(
        PartyShopOwnershipService.hasLiveShop([shop(isActive: false)]),
        isTrue,
      );
    });

    test('삭제 흔적이 남은 문서는 보유로 세지 않는다', () {
      // 파티샵 삭제는 서버가 문서를 아예 지우므로 보통은 0건이 된다.
      // soft-delete 표시가 남는 경우까지 같은 결론이어야 한다.
      expect(
        PartyShopOwnershipService.hasLiveShop([shop(isDeleted: true)]),
        isFalse,
      );
      expect(
        PartyShopOwnershipService.hasLiveShop([shop(status: 'deleted')]),
        isFalse,
      );
    });

    test('삭제된 샵 하나가 섞여 있어도 살아 있는 샵이 있으면 판매자다', () {
      expect(
        PartyShopOwnershipService.hasLiveShop([
          shop(isDeleted: true),
          shop(isActive: false),
        ]),
        isTrue,
      );
    });
  });

  group('허브 화면은 판정 결과대로만 메뉴를 그린다', () {
    setUp(() => UserSession.userId = ''); // 목록이 Firestore를 건드리지 않도록

    Future<void> pump(WidgetTester tester, {required bool isSeller}) =>
        tester.pumpWidget(MaterialApp(home: ShopHubView(isSeller: isSeller)));

    testWidgets('판매자 — 내 파티샵 · 구매 · 판매 세 메뉴', (tester) async {
      await pump(tester, isSeller: true);

      expect(find.byType(TabBar), findsOneWidget);
      expect(find.widgetWithText(Tab, '내 파티샵'), findsOneWidget);
      expect(find.widgetWithText(Tab, '구매'), findsOneWidget);
      expect(find.widgetWithText(Tab, '판매'), findsOneWidget);
    });

    testWidgets('판매자가 아니면 구매 목록만 — 탭 자체가 없다', (tester) async {
      await pump(tester, isSeller: false);

      // 비활성 탭으로도 남기지 않는다.
      expect(find.byType(TabBar), findsNothing);
      expect(find.byType(Tab), findsNothing);
      expect(find.text('내 파티샵'), findsNothing);
      expect(find.text('판매'), findsNothing);

      // 구매 목록은 그대로 열린다(구매 이력 0건이어도 화면은 있다).
      expect(find.text('🛍️ 파티샵 구매 목록'), findsOneWidget);
    });
  });
}

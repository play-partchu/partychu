// 파티츄 호스트의 상단 카테고리 — 🎪 이벤트는 **파티와 같은 급의 탭**이다.
//
// 매장 이벤트는 파티의 하위 항목이 아니다(컬렉션부터 `placePromotions`로
// 따로다). 예전에는 파티 탭 맨 위의 진입 줄로 들어가서, 이벤트가 파티에 딸린
// 것처럼 읽히고 목록·상태도 파티 탭 안에서 찾게 됐다.
//
// 이 파일이 지키는 것:
//   · 호스트 탭은 다섯이고(파티츄·이벤트·플레이스·공간대여·파티크루), 좁은
//     화면에서 글자가 두 줄로 깨지지 않는다.
//   · 게스트 허브는 넷 그대로다 — 이벤트는 호스트가 등록하는 것이다.
//   · 이벤트 탭은 **기존 관리 화면과 같은 목록 위젯·같은 데이터 소스**를 쓴다
//     (새 쿼리·새 관리 시스템을 만들지 않았다).
//   · 파티 탭에는 파티만 남는다.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/screens/my_guest_hub_screen.dart' show MyHubTabBar;

String _src(String path) => File(path).readAsStringSync();

/// 탭 바 하나만 띄운다 — 허브 화면 전체는 Firebase가 있어야 그려진다.
Future<TabBar> _pumpTabBar(
  WidgetTester tester, {
  required bool includeStoreEvent,
  required int length,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: DefaultTabController(
        length: length,
        child: Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(46),
                child: MyHubTabBar(
                  controller: DefaultTabController.of(context),
                  includeStoreEvent: includeStoreEvent,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.widget<TabBar>(find.byType(TabBar));
}

void main() {
  group('호스트 탭 바 — 다섯 칸', () {
    testWidgets('파티츄 · 이벤트 · 플레이스 · 공간대여 · 파티크루', (tester) async {
      final bar = await _pumpTabBar(
        tester,
        includeStoreEvent: true,
        length: 5,
      );
      expect(bar.tabs.length, 5);
      expect(find.text('파티츄'), findsOneWidget);
      expect(find.text('🎪 이벤트'), findsOneWidget);
      expect(find.text('📍 플레이스'), findsOneWidget);
      expect(find.text('🏠 공간대여'), findsOneWidget);
      expect(find.text('🤝 파티크루'), findsOneWidget);
    });

    testWidgets('좁은 화면에서 글자를 줄이지 않고 가로 스크롤로 푼다', (tester) async {
      final bar = await _pumpTabBar(
        tester,
        includeStoreEvent: true,
        length: 5,
      );
      expect(bar.isScrollable, isTrue);
      // 넘침(두 줄 깨짐·잘림)이 없어야 한다 — 있으면 예외로 잡힌다.
      expect(tester.takeException(), isNull);
      // 글자 크기는 네 칸일 때와 같다(줄여서 우겨넣지 않았다).
      expect((bar.labelStyle as TextStyle).fontSize, 12.5);
    });

    testWidgets('이벤트 칸은 파티츄 **바로 옆**이다 — 파티의 하위가 아니다', (tester) async {
      final bar = await _pumpTabBar(
        tester,
        includeStoreEvent: true,
        length: 5,
      );
      final second = bar.tabs[1] as Tab;
      expect(second.text, '🎪 이벤트');
    });
  });

  group('게스트 탭 바는 그대로 넷', () {
    testWidgets('이벤트 칸이 없고 가로 스크롤도 아니다', (tester) async {
      final bar = await _pumpTabBar(
        tester,
        includeStoreEvent: false,
        length: 4,
      );
      expect(bar.tabs.length, 4);
      expect(bar.isScrollable, isFalse);
      expect(find.text('🎪 이벤트'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('호스트 허브 구성', () {
    final hub = _src('lib/screens/my_host_hub_screen.dart');

    test('탭 컨트롤러가 다섯 칸이고 이벤트 탭이 두 번째다', () {
      expect(hub.contains('length: 5,'), isTrue);
      expect(hub.contains('includeStoreEvent: true'), isTrue);
      final party = hub.indexOf('_MyPartyList(),');
      final event = hub.indexOf('_MyStoreEventTab(),');
      final place = hub.indexOf("title: '플레이스 운영'");
      expect(party, greaterThan(0));
      expect(event, greaterThan(party));
      expect(place, greaterThan(event));
    });

    test('파티 탭에서 매장 이벤트 관리 배너가 사라졌다', () {
      expect(hub.contains('_eventManageEntry'), isFalse);
      expect(hub.contains('PlaceEventEntry.startManage'), isFalse);
      // 진입점 자체도 함께 정리됐다(쓰지 않는 문을 남기지 않는다).
      expect(
        _src('lib/services/place_event_entry.dart').contains('startManage'),
        isFalse,
      );
    });

    test('파티 탭에는 파티만 남는다', () {
      // 파티 목록 클래스 본문만 자른다 — 뒤따르는 이벤트 탭의 주석까지 걸리지
      // 않게 섹션 머리말을 경계로 쓴다.
      final gate = hub.substring(
        hub.indexOf('class _MyPartyListState'),
        hub.indexOf('// 🎪 이벤트 탭'),
      );
      // 파티 목록과 환불 처리 줄(전 도메인 공통)만 있고, 이벤트 목록은 없다.
      expect(gate.contains('PlaceEventManageList'), isFalse);
      expect(gate.contains("Tab(text: '진행 중인 파티')"), isTrue);
      expect(gate.contains("Tab(text: '지난 파티')"), isTrue);
    });

    test('이벤트 탭은 기존 목록 위젯과 기존 진입점을 그대로 쓴다', () {
      final tab = hub.substring(
        hub.indexOf('class _MyStoreEventTabState'),
        hub.indexOf('class _PartyTabList'),
      );
      // 목록·수정·삭제·상태 변경·신청자 수 = 관리 화면과 같은 위젯.
      expect(tab.contains('PlaceEventManageList('), isTrue);
      // 등록은 공용 진입점 하나.
      expect(tab.contains('PlaceEventEntry.startRegister('), isTrue);
      // 내 플레이스 목록도 기존 것.
      expect(tab.contains('PlaceEventEntry.myPlaces()'), isTrue);
      // 새 쿼리를 만들지 않았다 — 이 탭은 Firestore를 직접 부르지 않는다.
      expect(tab.contains("collection('placePromotions')"), isFalse);
      expect(tab.contains('FirebaseFirestore'), isFalse);
    });

    test('파티 → 이벤트 만들기 연결은 그대로 남아 있다', () {
      // 파티 카드의 '이 파티를 기반으로 이벤트 등록'은 **생성 진입**이라 유지.
      expect(hub.contains('PlaceEventEntry.startRegister('), isTrue);
      expect(hub.contains('PartyEventSource.resolve('), isTrue);
    });
  });

  group('관리 화면과 이벤트 탭은 같은 목록을 쓴다', () {
    final manage = _src('lib/screens/place_event_manage_screen.dart');

    test('목록 본체가 위젯 하나로 뽑혀 있다', () {
      expect(manage.contains('class PlaceEventManageList extends StatelessWidget'), isTrue);
      expect(manage.contains('class PlaceEventManageScreen extends StatelessWidget'), isTrue);
      // 화면은 그 목록을 그대로 쓴다(두 벌로 갈라지지 않는다).
      expect(manage.contains('final list = PlaceEventManageList('), isTrue);
    });

    test('데이터 소스가 예전 그대로다', () {
      expect(manage.contains('PlacePromotionService.watchForPlace(placeId)'), isTrue);
      expect(
        manage.contains('PlaceEventApplicationService.watchAppliedCountsForPlace('),
        isTrue,
      );
      expect(manage.contains('PlacePromotionService.setVisible('), isTrue);
      expect(manage.contains('PlacePromotionService.deleteById('), isTrue);
      expect(manage.contains('PlaceEventApplicantsScreen('), isTrue);
    });

    test('진행 중 · 진행 예정 · 종료 묶음이 그대로다', () {
      expect(manage.contains("'진행 중'"), isTrue);
      expect(manage.contains("'진행 예정'"), isTrue);
      expect(manage.contains("'종료 · 숨김'"), isTrue);
    });
  });
}

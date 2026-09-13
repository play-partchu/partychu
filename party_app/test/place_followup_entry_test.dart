// 플레이스를 새로 등록한 직후 — "이 플레이스에서 파티나 매장 이벤트를 여시나요?"
//
// ── 다시 묻지 않는다 ─────────────────────────────────────────────────────────
// 여기까지 온 사람은 **이미 플레이스를 정했다**(방금 만들었다). 그래서
// 파티 등록하기를 고르면 "내 플레이스 / 새 파티"를 다시 묻지 않고 방금 만든
// 플레이스가 prelink된 폼으로 곧장 가고, 🎪 매장 이벤트도 "어느 플레이스에서
// 진행하나요?"를 건너뛴다.
//
// 그 "다시 묻지 않음"이 이 파일이 지키는 것이다 — 선택 화면이 한 번 더 끼면
// 방금 고른 것을 또 고르게 된다.
//
// 파티 등록하기는 새 파티를 만드는 길이라 다른 입구와 **같은 관문**을 지난다
// ([PartyCreateEligibility]) — 그것도 여기서 확인한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:party_app/models/host_offering.dart';
import 'package:party_app/screens/party_register_entry_choice_screen.dart';
import 'package:party_app/screens/party_register_screen.dart';
import 'package:party_app/screens/place_event_edit_screen.dart';
import 'package:party_app/services/party_create_eligibility.dart';
import 'package:party_app/services/place_event_entry.dart';
import 'package:party_app/services/place_followup_entry.dart';
import 'package:party_app/services/place_party_link_service.dart';
import 'package:party_app/utils/user_session.dart';

const _me = 'host-me';

/// 방금 저장한 플레이스 문서 — 등록 화면이 그대로 넘기는 모양이다.
const _placeDoc = <String, dynamic>{
  'hostId': _me,
  'name': 'OO 혼술바',
  'address': '서울 마포구 와우산로 1',
  'roadAddress': '서울 마포구 와우산로 1',
  'latitude': 37.55,
  'longitude': 126.92,
  'id': 'E1',
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UserSession.userId = _me;
    // 플레이스를 만들 수 있었던 계정이므로 사업자다.
    PartyCreateEligibility.debugSetSource(businessVerified: () async => true);
  });

  tearDown(() {
    PartyCreateEligibility.debugResetSource();
    PlaceEventEntry.debugResetSource();
    UserSession.userId = '';
  });

  /// 저장이 끝난 자리에서 후속 질문을 띄운다.
  Future<void> showFollowup(
    WidgetTester tester, {
    String collection = 'events',
  }) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => PlaceFollowupEntry.show(
                  context,
                  placeId: 'E1',
                  placeCollection: collection,
                  placeData: _placeDoc,
                  placeName: 'OO 혼술바',
                ),
                child: const Text('저장'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
  }

  group('후속 질문', () {
    testWidgets('세 갈래를 주고, 어느 플레이스인지 보여준다', (tester) async {
      await showFollowup(tester);

      expect(find.text('이 플레이스에서 파티나 매장 이벤트를 여시나요?'), findsOneWidget);
      expect(find.text(HostOffering.party.label), findsOneWidget);
      expect(find.text(HostOffering.placeEvent.label), findsOneWidget);
      expect(find.text('나중에 할게요'), findsOneWidget);
      // 다시 고르게 하지 않는 대신, 무엇이 골라져 있는지는 보여야 한다.
      expect(find.text('OO 혼술바'), findsOneWidget);
    });

    testWidgets("'나중에 할게요'는 아무 데도 보내지 않는다", (tester) async {
      await showFollowup(tester);

      await tester.tap(find.text('나중에 할게요'));
      await tester.pumpAndSettle();

      expect(find.text('이 플레이스에서 파티나 매장 이벤트를 여시나요?'), findsNothing);
      expect(find.byType(PartyRegisterScreen), findsNothing);
      expect(find.byType(PlaceEventEditScreen), findsNothing);
    });
  });

  group('파티 등록하기', () {
    testWidgets('방금 만든 플레이스가 prelink된 폼으로 곧장 간다', (tester) async {
      await showFollowup(tester);

      await tester.tap(find.text(HostOffering.party.label));
      await tester.pumpAndSettle();

      // "내 플레이스 / 새 파티"를 다시 묻지 않는다.
      expect(
        find.byType(PartyRegisterEntryChoiceScreen),
        findsNothing,
        reason: '방금 고른 플레이스를 또 고르게 한다',
      );
      expect(find.text('어떤 파티인가요?'), findsNothing);

      final form = tester.widget<PartyRegisterScreen>(
        find.byType(PartyRegisterScreen),
      );
      expect(form.prelink?.targetId, 'E1');
      expect(form.prelink?.target, PartyLinkTarget.place);
    });

    testWidgets('공간대여로 등록했으면 그쪽 연결 대상으로 간다', (tester) async {
      await showFollowup(tester, collection: 'places');

      await tester.tap(find.text(HostOffering.party.label));
      await tester.pumpAndSettle();

      final form = tester.widget<PartyRegisterScreen>(
        find.byType(PartyRegisterScreen),
      );
      expect(form.prelink?.target, PartyLinkTarget.rental);
    });

    // 새 파티를 만드는 길은 어디서 들어오든 같은 관문을 지난다.
    testWidgets('자격이 없으면 폼 대신 안내가 뜬다', (tester) async {
      PartyCreateEligibility.debugSetSource(
        businessVerified: () async => false,
        individualEnabled: () async => false,
      );
      await showFollowup(tester);

      await tester.tap(find.text(HostOffering.party.label));
      await tester.pumpAndSettle();

      expect(find.byType(PartyRegisterScreen), findsNothing);
      expect(find.text('개인 파티 등록은 준비 중이에요'), findsOneWidget);
    });
  });

  group('이벤트 등록하기', () {
    testWidgets('방금 만든 플레이스가 미리 골라진 폼으로 곧장 간다', (tester) async {
      // 목록 조회가 끼면 안 된다 — target을 주면 조회 자체를 하지 않는다.
      var loaded = false;
      PlaceEventEntry.debugSetSource(
        uid: _me,
        loader: (_) async {
          loaded = true;
          return const [];
        },
      );
      await showFollowup(tester);

      await tester.tap(find.text(HostOffering.placeEvent.label));
      await tester.pumpAndSettle();

      expect(
        find.text('어느 플레이스에서 진행하나요?'),
        findsNothing,
        reason: '방금 만든 플레이스를 또 고르게 한다',
      );
      expect(
        loaded,
        isFalse,
        reason: 'target을 줬는데도 내 플레이스를 다시 읽었다',
      );
      expect(find.byType(PlaceEventEditScreen), findsOneWidget);
      // 폼 머리말이 어느 플레이스의 이벤트인지 말한다.
      expect(find.text('OO 혼술바'), findsWidgets);
      expect(find.text('이 장소의 매장 이벤트'), findsOneWidget);
    });

    // 플레이스가 하나도 없다는 안내가 뜨면 안 된다 — 방금 하나 만들었다.
    testWidgets('플레이스를 먼저 등록하라고 하지 않는다', (tester) async {
      PlaceEventEntry.debugSetSource(uid: _me, loader: (_) async => const []);
      await showFollowup(tester);

      await tester.tap(find.text(HostOffering.placeEvent.label));
      await tester.pumpAndSettle();

      expect(find.text('플레이스를 먼저 등록해주세요'), findsNothing);
    });
  });
}

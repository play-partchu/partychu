// 파티 **수정** 화면의 공간 연결 — 등록과 같은 연결 모델을 이해하는가.
//
// 고친 사고: 등록에서 장소대여(`places`)를 골라 만든 파티는 `linkedPlaceId`를
// 갖는다. 그런데 수정 화면은 (1) `linkedEventId`만 읽어 "연결 안 됨"으로
// 보여줬고, (2) `linkedPlaceId`가 있으면 무조건 "함께 등록된 콤보"로 판정해
// 장소 연결 변경을 아예 막았다. 그 결과 등록에서 방금 만든 파티를 수정
// 화면에서 손댈 수 없었다.
//
// 여기서는 화면을 실제로 띄워 (요약 문구 / 시트에 뜨는 선택지)를 본다.
// Firestore 쓰기가 필요한 부분(연결이 실제로 어느 필드에 커밋되는지)은
// test/place_party_link_payload_test.dart가 payload로 직접 검증한다.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:party_app/screens/party_edit_screen.dart';
import 'package:party_app/services/party_bundle_service.dart';
import 'package:party_app/services/place_party_link_service.dart';
import 'package:party_app/utils/user_session.dart';

const String _me = 'host-me';

/// 수정 화면이 열 수 있을 만큼만 채운 파티 문서.
Map<String, dynamic> _party({
  String? linkedEventId,
  String? linkedPlaceId,
  String? snapshotName,
  bool isCombo = false,
  String? bundleId,
}) => <String, dynamic>{
  'hostId': _me,
  'title': '금요일 와인 번개',
  'location': '서울 마포구 와우산로 1',
  'address': '서울 마포구 와우산로 1',
  'placeName': '직접 입력한 가게',
  'currentParticipants': 0,
  if (linkedEventId != null) 'linkedEventId': linkedEventId,
  if (linkedPlaceId != null) 'linkedPlaceId': linkedPlaceId,
  if (isCombo) 'isCombo': true,
  if (bundleId != null) 'bundleId': bundleId,
  if (snapshotName != null)
    PlacePartyLink.snapshotField: <String, dynamic>{'name': snapshotName},
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UserSession.userId = _me;
  });

  tearDown(() => UserSession.userId = '');

  /// Firebase 앱이 없는 테스트 환경에서 화면이 배경으로 던지는 조회 예외를
  /// 흘려보낸다. 이 검사가 보는 것은 **연결 상태를 어떻게 읽고 그리는가**이지
  /// 조회 성공 여부가 아니다 — 연결 판정은 이미 넘겨받은 파티 문서만으로 끝난다.
  void drainFirebaseErrors(WidgetTester tester) {
    while (tester.takeException() != null) {}
  }

  Future<void> pumpEdit(WidgetTester tester, Map<String, dynamic> data) async {
    tester.view.physicalSize = const Size(420, 4800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: PartyEditScreen(docId: 'party-1', data: data)),
    );
    drainFirebaseErrors(tester);
    await tester.pumpAndSettle();
    drainFirebaseErrors(tester);
  }

  /// 장소 설정 줄을 눌러 시트를 연다.
  Future<void> openLocationSheet(WidgetTester tester) async {
    await tester.tap(find.text('장소 설정').last);
    await tester.pumpAndSettle();
    drainFirebaseErrors(tester);
  }

  // ══ 표시 ══════════════════════════════════════════════════════════════
  group('연결된 공간이 종류에 맞게 표시된다', () {
    testWidgets('linkedEventId 파티 — 플레이스로 보인다', (tester) async {
      await pumpEdit(
        tester,
        _party(linkedEventId: 'E1', snapshotName: 'OO 혼술바'),
      );
      expect(find.text('플레이스 · OO 혼술바'), findsOneWidget);
    });

    testWidgets('linkedPlaceId 파티 — 공간대여로 보인다(예전엔 연결 안 됨으로 보였다)', (
      tester,
    ) async {
      await pumpEdit(
        tester,
        _party(linkedPlaceId: 'P1', snapshotName: 'OO 파티룸'),
      );
      expect(find.text('공간대여 · OO 파티룸'), findsOneWidget);
      expect(find.textContaining('직접 입력'), findsNothing);
    });

    testWidgets('연결이 없으면 직접 입력한 장소로 보인다 — 기존 그대로', (tester) async {
      await pumpEdit(tester, _party());
      expect(find.textContaining('직접 입력 ·'), findsOneWidget);
    });
  });

  // ══ 시트 ══════════════════════════════════════════════════════════════
  group('연결 변경 시트', () {
    testWidgets('플레이스 연결 — 보기/변경/해제가 뜬다', (tester) async {
      await pumpEdit(
        tester,
        _party(linkedEventId: 'E1', snapshotName: 'OO 혼술바'),
      );
      await openLocationSheet(tester);

      expect(find.text('연결된 플레이스 보기'), findsOneWidget);
      expect(find.text('다른 공간으로 변경'), findsOneWidget);
      expect(find.text('연결 해제'), findsOneWidget);
    });

    testWidgets('장소대여 연결 — 같은 선택지가 공간대여 이름으로 뜬다', (tester) async {
      await pumpEdit(
        tester,
        _party(linkedPlaceId: 'P1', snapshotName: 'OO 파티룸'),
      );
      await openLocationSheet(tester);

      expect(
        find.text('연결된 공간대여 보기'),
        findsOneWidget,
        reason: '문구를 플레이스로 굳히면 다른 것을 보고 있다고 오해합니다.',
      );
      expect(find.text('다른 공간으로 변경'), findsOneWidget);
      expect(
        find.text('연결 해제'),
        findsOneWidget,
        reason: '해제는 두 종류 모두에서 되어야 합니다.',
      );
    });

    testWidgets('연결이 없으면 내 공간에서 선택할 수 있다', (tester) async {
      await pumpEdit(tester, _party());
      await openLocationSheet(tester);

      expect(find.text('내 공간에서 선택'), findsOneWidget);
      expect(find.text('직접 입력한 장소 유지'), findsOneWidget);
    });
  });

  // ══ 콤보 잠금 ═════════════════════════════════════════════════════════
  group('콤보 잠금은 통합 등록 흔적으로만 판정한다', () {
    test('linkedPlaceId만 있는 파티는 콤보가 아니다', () {
      expect(
        PartyBundleService.isBundledRegistration(_party(linkedPlaceId: 'P1')),
        isFalse,
        reason: '이제 일반 등록에서도 장소대여를 골라 이 필드가 채워집니다.',
      );
    });

    test('isCombo / bundleId가 있으면 콤보다', () {
      expect(
        PartyBundleService.isBundledRegistration(
          _party(linkedPlaceId: 'P1', isCombo: true),
        ),
        isTrue,
      );
      expect(
        PartyBundleService.isBundledRegistration(
          _party(linkedEventId: 'E1', bundleId: 'B1'),
        ),
        isTrue,
      );
    });

    testWidgets('콤보로 등록된 파티는 여전히 장소 연결을 바꿀 수 없다', (tester) async {
      await pumpEdit(
        tester,
        _party(linkedPlaceId: 'P1', isCombo: true, bundleId: 'B1'),
      );
      await openLocationSheet(tester);

      expect(find.text('다른 공간으로 변경'), findsNothing);
      expect(find.textContaining('장소 연결은 변경할 수 없습니다'), findsOneWidget);
    });

    testWidgets('장소대여에 사후 연결된 일반 파티는 잠기지 않는다', (tester) async {
      await pumpEdit(tester, _party(linkedPlaceId: 'P1'));
      await openLocationSheet(tester);

      expect(
        find.text('다른 공간으로 변경'),
        findsOneWidget,
        reason: '등록에서 장소대여를 골라 만든 파티를 수정에서 손댈 수 있어야 합니다.',
      );
      expect(find.textContaining('장소 연결은 변경할 수 없습니다'), findsNothing);
    });
  });

  // ══ 소유자 가드 ═══════════════════════════════════════════════════════
  group('타인 소유 공간으로는 옮길 수 없다', () {
    // 두 검사 모두 Firestore를 만지기 **전에** 걸리는 가드다.
    test('연결 — 남의 공간이면 StateError', () {
      expect(
        () => PlacePartyLink.linkParties(
          targetId: 'E9',
          place: const {'hostId': 'host-other', 'name': '남의 카페'},
          partyIds: const ['party-1'],
          hostId: _me,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('재연결 — 남의 공간이면 읽기도 하지 않고 StateError', () {
      expect(
        () => PlacePartyLink.relinkParty(
          partyId: 'party-1',
          fromTarget: PartyLinkTarget.place,
          fromTargetId: 'E1',
          toTarget: PartyLinkTarget.rental,
          toTargetId: 'P9',
          toPlace: const {'hostId': 'host-other', 'name': '남의 파티룸'},
          hostId: _me,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('목록에도 남의 공간은 오르지 않는다', () {
      final spaces = PlacePartyLink.spacesFrom(
        hostId: _me,
        docsByTarget: {
          PartyLinkTarget.place: [
            (
              id: 'E9',
              data: <String, dynamic>{'hostId': 'host-other', 'name': '남의 카페'},
            ),
          ],
          PartyLinkTarget.rental: [
            (
              id: 'P9',
              data: <String, dynamic>{
                'hostId': 'host-other',
                'name': '남의 파티룸',
              },
            ),
          ],
        },
      );
      expect(spaces, isEmpty);
    });
  });

  // ══ 진입 선택은 수정에 없다 ═══════════════════════════════════════════
  group('수정 화면에는 등록 진입 선택이 끼지 않는다', () {
    final src = File('lib/screens/party_edit_screen.dart').readAsStringSync();

    test('선택 화면·진입 창구·연결 preset 생성자를 쓰지 않는다', () {
      for (final banned in [
        'PartyRegisterEntryChoiceScreen',
        'openPartyRegisterEntry',
        'partyRegisterEntryScreen',
        'PartyRegisterScreen.withSpace',
        'LinkedSpaceBanner',
      ]) {
        expect(
          src.contains(banned),
          isFalse,
          reason: '수정은 "무엇을 만들지"가 이미 정해진 화면입니다 — $banned이 끼면 안 됩니다.',
        );
      }
    });

    testWidgets('수정 화면을 열어도 연결/독립 선택지가 보이지 않는다', (tester) async {
      await pumpEdit(tester, _party(linkedPlaceId: 'P1'));
      expect(find.text('내 플레이스에서 여는 파티'), findsNothing);
      expect(find.text('독립적인 파티 만들기'), findsNothing);
    });
  });
}

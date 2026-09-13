// 파티 등록 진입 — "내 공간에서 여는 파티인가"를 먼저 묻는 흐름.
//
// 이 검사가 지키는 약속은 두 갈래다.
//
//  1. **공간이 없는 호스트의 동작은 하나도 바뀌지 않는다.** 선택 화면이 끼지
//     않고, 등록 폼에 연결 배너도 뜨지 않는다.
//  2. **연결은 기존 필드에만 쓴다.** 플레이스는 `linkedEventId`(events),
//     장소대여는 `linkedPlaceId`(places) — 새 연결 체계를 만들지 않았다는
//     사실을 값으로 확인한다.
//
// Firebase는 초기화하지 않는다. 노출 조건([partyRegisterEntryScreen])과 소유자
// 필터([PlacePartyLink.spacesFrom])를 조회에서 떼어 순수 함수로 두었기 때문에
// 앱 없이 그대로 돌릴 수 있고, 화면 검사는 목록을 주입해서 띄운다.
// 저장 뒤 연결 커밋(linkParties)은 Firestore 쓰기라 여기서 다루지 않는다 —
// 대신 그 경로에 실려 나가는 값(_linkTarget)이 맞는지를 임시저장 payload와
// 소스로 확인한다.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:party_app/screens/party_register_entry_choice_screen.dart';
import 'package:party_app/screens/party_register_screen.dart';
import 'package:party_app/screens/place_party_link_screen.dart'
    show MySpaceTile;
import 'package:party_app/services/place_party_link_service.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/party_form/party_place_link_section.dart';

import 'support/field_finders.dart';

const String _me = 'host-me';
const String _other = 'host-other';

/// 소유자 필터에 넣을 문서 한 건.
({String id, Map<String, dynamic> data}) _doc(
  String id, {
  required String hostId,
  required String name,
  bool isDeleted = false,
}) => (
  id: id,
  data: <String, dynamic>{
    'hostId': hostId,
    'name': name,
    'location': '서울 마포구 어딘가',
    'isDeleted': isDeleted,
  },
);

/// 선택 화면·등록 폼에 그대로 넣을 수 있는 연결 대상.
PartyPrelinkTarget _space(
  PartyLinkTarget target,
  String id,
  String name,
) => PartyPrelinkTarget(
  target: target,
  targetId: id,
  data: <String, dynamic>{
    'hostId': _me,
    'name': name,
    'address': '서울 마포구 와우산로 1',
    'roadAddress': '서울 마포구 와우산로 1',
    'location': '서울 마포구 와우산로 1',
    'latitude': 37.55,
    'longitude': 126.92,
  },
);

final _bar = _space(PartyLinkTarget.place, 'e1', 'OO 혼술바');
final _room = _space(PartyLinkTarget.rental, 'p1', 'OO 파티룸');

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UserSession.userId = _me;
  });

  tearDown(() => UserSession.userId = '');

  /// 등록 폼은 길다 — 기본 800×600에서는 아래쪽 항목이 아예 만들어지지 않는다.
  void useTallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(420, 4800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// 화면을 띄워 파티명을 넣고 임시저장한 뒤, 기록된 payload를 돌려준다.
  /// 임시저장은 Firestore가 없어도 로컬 미러에 남는다(draft_service의 안전망).
  Future<Map<String, dynamic>> savedDraftPayload(
    WidgetTester tester,
    Widget screen,
  ) async {
    useTallScreen(tester);
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pumpAndSettle();
    await tester.enterText(fieldWithHint(kPartyTitleHint), '연결 진입 검사용 파티');
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '임시저장'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('draft_party');
    expect(raw, isNotNull, reason: '임시저장 로컬 미러가 기록되어야 합니다.');
    return (jsonDecode(raw!) as Map<String, dynamic>)['payload']
        as Map<String, dynamic>;
  }

  // ══ 노출 조건 ═════════════════════════════════════════════════════════
  group('선택 화면 노출 조건', () {
    test('공간 0개 — 선택 화면 없이 곧장 기존 파티 등록 폼', () {
      final screen = partyRegisterEntryScreen(const []);
      expect(
        screen,
        isA<PartyRegisterScreen>(),
        reason: '공간이 없으면 진입이 지금까지와 완전히 같아야 합니다.',
      );
      // 그리고 그 폼은 연결이 미리 정해지지 않은 **평범한 새 등록**이다.
      final form = screen as PartyRegisterScreen;
      expect(form.initialSpace, isNull);
      expect(form.prelink, isNull);
    });

    test('플레이스(events)만 있어도 선택 화면이 뜬다', () {
      expect(
        partyRegisterEntryScreen([_bar]),
        isA<PartyRegisterEntryChoiceScreen>(),
      );
    });

    test('장소대여(places)만 있어도 선택 화면이 뜬다', () {
      expect(
        partyRegisterEntryScreen([_room]),
        isA<PartyRegisterEntryChoiceScreen>(),
      );
    });
  });

  // ══ 소유자 필터 ═══════════════════════════════════════════════════════
  group('내 공간만 목록에 오른다', () {
    List<PartyPrelinkTarget> spaces({
      List<({String id, Map<String, dynamic> data})> events = const [],
      List<({String id, Map<String, dynamic> data})> places = const [],
    }) => PlacePartyLink.spacesFrom(
      hostId: _me,
      docsByTarget: {
        PartyLinkTarget.place: events,
        PartyLinkTarget.rental: places,
      },
    );

    test('타인 소유 플레이스·장소대여는 한 건도 노출되지 않는다', () {
      final result = spaces(
        events: [
          _doc('e1', hostId: _me, name: '내 혼술바'),
          _doc('e2', hostId: _other, name: '남의 카페'),
        ],
        places: [
          _doc('p1', hostId: _other, name: '남의 파티룸'),
          _doc('p2', hostId: _me, name: '내 파티룸'),
        ],
      );

      expect(result.map((s) => s.targetId), ['e1', 'p2']);
      expect(
        result.every((s) => s.data['hostId'] == _me),
        isTrue,
        reason: '남의 공간이 한 줄이라도 새면 고른 뒤 연결만 조용히 실패합니다.',
      );
    });

    test('삭제된 공간도 빠진다', () {
      final result = spaces(
        events: [_doc('e1', hostId: _me, name: '닫은 가게', isDeleted: true)],
      );
      expect(result, isEmpty);
    });

    test('둘 다 있으면 둘 다 고를 수 있다 — 플레이스 먼저, 그다음 장소대여', () {
      final result = spaces(
        events: [_doc('e1', hostId: _me, name: '내 혼술바')],
        places: [_doc('p1', hostId: _me, name: '내 파티룸')],
      );
      expect(result.map((s) => s.target), [
        PartyLinkTarget.place,
        PartyLinkTarget.rental,
      ]);
    });

    test('로그인하지 않았으면 빈 목록', () {
      expect(
        PlacePartyLink.spacesFrom(
          hostId: '',
          docsByTarget: {
            PartyLinkTarget.place: [_doc('e1', hostId: _me, name: '내 혼술바')],
          },
        ),
        isEmpty,
      );
    });
  });

  // ══ 선택 화면 ═════════════════════════════════════════════════════════
  group('선택 화면', () {
    testWidgets('선택지 두 개가 설명과 함께 보인다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: PartyRegisterEntryChoiceScreen(spaces: [_bar])),
      );
      await tester.pumpAndSettle();

      expect(find.text('내 플레이스에서 여는 파티'), findsOneWidget);
      expect(find.text('등록한 플레이스 또는 대여 공간에서 여는 파티예요.'), findsOneWidget);
      expect(find.text('독립적인 파티 만들기'), findsOneWidget);
      expect(find.text('내 플레이스와 연결하지 않고 다른 장소에서 여는 파티예요.'), findsOneWidget);
    });

    testWidgets('공간이 하나뿐이어도 자동 연결하지 않고 목록을 한 번 보여준다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: PartyRegisterEntryChoiceScreen(spaces: [_bar])),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('내 플레이스에서 여는 파티'));
      await tester.pumpAndSettle();

      expect(find.byType(MySpaceTile), findsOneWidget);
      expect(find.text('OO 혼술바'), findsOneWidget);
    });

    testWidgets('플레이스와 장소대여가 종류 라벨과 함께 한 목록에 보인다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PartyRegisterEntryChoiceScreen(spaces: [_bar, _room]),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('내 플레이스에서 여는 파티'));
      await tester.pumpAndSettle();

      expect(find.byType(MySpaceTile), findsNWidgets(2));
      expect(find.text('OO 혼술바'), findsOneWidget);
      expect(find.text('OO 파티룸'), findsOneWidget);
      // 라벨·이모지는 지도/메인 탭과 같은 값을 쓴다(새 기호를 만들지 않는다).
      expect(
        find.text(PartyLinkTarget.place.listingKind.label),
        findsOneWidget,
      );
      expect(
        find.text(PartyLinkTarget.rental.listingKind.label),
        findsOneWidget,
      );
    });
  });

  // ══ 연결 필드 ═════════════════════════════════════════════════════════
  group('연결 대상은 기존 필드로만 저장된다', () {
    test('종류별 연결 필드는 이미 쓰이던 두 개가 전부다', () {
      expect(PartyLinkTarget.place.linkField, 'linkedEventId');
      expect(PartyLinkTarget.place.collection, 'events');
      expect(PartyLinkTarget.rental.linkField, 'linkedPlaceId');
      expect(PartyLinkTarget.rental.collection, 'places');
      expect(
        PartyLinkTarget.values.length,
        2,
        reason: '연결 대상이 늘면 저장 필드도 함께 늘어난다 — 의도한 변경일 때만 이 줄을 고칠 것.',
      );
    });

    testWidgets('플레이스를 골라 들어오면 linkedEventId로 담긴다', (tester) async {
      final payload = await savedDraftPayload(
        tester,
        PartyRegisterScreen.withSpace(space: _bar),
      );
      expect(payload['linkedEventId'], 'e1');
      expect(payload['linkTarget'], PartyLinkTarget.place.name);
    });

    testWidgets('장소대여를 골라 들어오면 같은 값이 linkedPlaceId 쪽으로 간다', (tester) async {
      final payload = await savedDraftPayload(
        tester,
        PartyRegisterScreen.withSpace(space: _room),
      );
      expect(payload['linkedEventId'], 'p1');
      expect(
        payload['linkTarget'],
        PartyLinkTarget.rental.name,
        reason: '종류를 잃으면 places 문서 id가 linkedEventId(events)로 쓰인다.',
      );
      // 그 종류가 실제로 가리키는 필드 — 저장 경로가 쓰는 값과 같은 곳.
      expect(
        PartyLinkTarget.values
            .firstWhere((t) => t.name == payload['linkTarget'])
            .linkField,
        'linkedPlaceId',
      );
    });

    testWidgets('독립적인 파티는 연결 필드가 비어 있다', (tester) async {
      final payload = await savedDraftPayload(
        tester,
        const PartyRegisterScreen(),
      );
      expect(payload['linkedEventId'], isNull);
    });

    testWidgets('고른 공간의 주소·좌표가 폼의 장소로 들어온다', (tester) async {
      // 연결해 놓고 주소만 다른 곳을 가리키면 지도와 목록이 어긋난다.
      final payload = await savedDraftPayload(
        tester,
        PartyRegisterScreen.withSpace(space: _bar),
      );
      final place = payload['place'] as Map<String, dynamic>;
      expect(place['address'], '서울 마포구 와우산로 1');
      expect(place['placeName'], 'OO 혼술바');
      expect(place['latitude'], 37.55);
      expect(payload['region'], isNotEmpty);
    });
  });

  // ══ 상단 배너 ═════════════════════════════════════════════════════════
  group('등록 폼 상단의 연결 표시', () {
    testWidgets('연결이 있으면 대상과 변경 버튼이 보인다', (tester) async {
      useTallScreen(tester);
      await tester.pumpWidget(
        MaterialApp(home: PartyRegisterScreen.withSpace(space: _room)),
      );
      await tester.pumpAndSettle();

      final banner = find.byType(LinkedSpaceBanner);
      expect(banner, findsOneWidget);
      expect(
        tester.widget<LinkedSpaceBanner>(banner).target,
        PartyLinkTarget.rental,
      );
      // 배너 안에서만 찾는다 — 장소 아래의 연결 줄도 같은 문구를 쓴다.
      for (final text in ['연결된 ${PartyLinkTarget.rental.noun}', 'OO 파티룸', '변경']) {
        expect(
          find.descendant(of: banner, matching: find.text(text)),
          findsOneWidget,
        );
      }
    });

    testWidgets('연결이 없으면 배너 자체가 없다 — 기존 등록 화면 그대로', (tester) async {
      useTallScreen(tester);
      await tester.pumpWidget(const MaterialApp(home: PartyRegisterScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(LinkedSpaceBanner), findsNothing);
    });
  });

  // ══ 수정 화면 ═════════════════════════════════════════════════════════
  group('수정 화면에는 진입 선택이 끼지 않는다', () {
    final editSrc = File('lib/screens/party_edit_screen.dart').readAsStringSync();

    test('선택 화면·진입 창구·연결 preset 생성자를 쓰지 않는다', () {
      for (final banned in [
        'PartyRegisterEntryChoiceScreen',
        'openPartyRegisterEntry',
        'partyRegisterEntryScreen',
        'PartyRegisterScreen.withSpace',
        'LinkedSpaceBanner',
      ]) {
        expect(
          editSrc.contains(banned),
          isFalse,
          reason: '수정 화면은 "무엇을 만들지"가 이미 정해진 화면입니다 — $banned이 끼면 안 됩니다.',
        );
      }
    });

    test('수정도 등록과 같은 공간 목록을 쓴다 — events 전용 분기를 따로 두지 않는다', () {
      // 등록에서 장소대여에 붙일 수 있게 된 이상, 수정만 events로 좁혀두면
      // 그렇게 만든 파티를 여기서 손댈 수 없다. 자세한 동작 검사는
      // test/party_edit_space_link_test.dart에 있다.
      expect(
        editSrc.contains('targets: PartyLinkTarget.values.toSet()'),
        isTrue,
        reason: '수정도 등록과 같은 시트(pickMyPlace)에 같은 종류 범위를 넘겨야 합니다.',
      );
      expect(
        editSrc.contains("collection('events')"),
        isFalse,
        reason: '연결 문서 조회가 events로 굳어 있으면 장소대여 연결이 늘 실패합니다.',
      );
    });
  });
}

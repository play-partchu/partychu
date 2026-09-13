// 플레이스+파티(콤보) **신규 등록 경로가 사라졌는지**, 그리고 그 자리를
// 무엇이 대신하는지.
//
// ── 무엇을 없앴나 ───────────────────────────────────────────────────────────
// 플레이스와 파티를 한 폼에서 함께 만드는 등록 방식 자체를 최종 UX에서 뺐다.
// 없앤 것은 **새로 만드는 길**뿐이다:
//   · 등록 유형 화면의 '🍷 플레이스+파티 등록' 카드와 그 '?' 도움말
//   · 등록 유형 안내 시트(AppBar '?')의 콤보 항목
//   · 콤보 등록 화면 셸과 두 폼, 그 전용 공통 폼/위젯
//   · 콤보 전용 임시저장 두 종류(생성·이어쓰기 모두)
//
// ── 무엇을 남겼나 ───────────────────────────────────────────────────────────
// **이미 만들어진 콤보 문서는 그대로 살아 있다.** 목록 배지·묶음 조회·예약·
// 취소가 전부 `isCombo`/`bundleId`/`comboPlaceType`을 읽어 동작하므로, 그
// 판정 코드는 하나도 건드리지 않았다. 이 파일이 그 두 가지를 함께 못박는다 —
// "새로 못 만든다"와 "옛 문서는 그대로 읽힌다"는 서로 다른 요구다.
//
// ── 무엇이 대신하나 ─────────────────────────────────────────────────────────
// 플레이스를 먼저 등록하고, 저장 직후 "이 플레이스에서 파티나 이벤트를
// 여시나요?"([PlaceFollowupEntry])가 **방금 만든 플레이스를 그대로 물고**
// 파티·이벤트 등록으로 이어준다. 어느 플레이스인지 다시 묻지 않으므로 콤보가
// 주던 "한 번에 끝난다"는 이점이 유지된다.
//
// Firestore는 건드리지 않는다 — 상단 사업자 인증 안내는 로그아웃이면 아무것도
// 그리지 않는다(register_type_help_copy_test.dart와 같은 전제).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:party_app/models/combo_place_type.dart';
import 'package:party_app/models/draft_type.dart';
import 'package:party_app/models/host_offering.dart';
import 'package:party_app/screens/register_type_screen.dart';
import 'package:party_app/services/party_bundle_service.dart';
import 'package:party_app/services/place_followup_entry.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/party_card_widget.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UserSession.userId = '';
  });

  Future<void> pumpRegisterType(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: RegisterTypeScreen()));
    await tester.pump(const Duration(milliseconds: 300));
  }

  // ── 1. 등록 유형 화면 ───────────────────────────────────────────────────

  group('등록 유형 화면', () {
    testWidgets('콤보 카드가 없다', (tester) async {
      await pumpRegisterType(tester);

      expect(find.text('플레이스+파티 등록'), findsNothing);
      expect(
        find.text('매장·즐길거리나 공간대여·숙박을 운영하며 파티도 함께 열어요'),
        findsNothing,
      );
      expect(find.text('🍷'), findsNothing, reason: '콤보 카드 이모지가 남아 있다');
    });

    // 최종 등록 유형은 플레이스 / 파티 / 매장 이벤트 셋이다(+ 파티샵 ·
    // 파티크루는 플레이스 계열이 아닌 별도 등록물이라 그대로 둔다).
    //
    // 파티와 매장 이벤트는 등록 메인에서 '🎉 이벤트 / 파티' **한 칸**으로
    // 들어가고, 둘 중 무엇인지는 그 다음 선택 화면에서 고른다
    // ([HostOfferingChoice] — register_event_entry_test.dart가 그쪽을 지킨다).
    // 여기서 지키는 것은 **등록 유형이 늘거나 줄지 않았다**는 것뿐이다.
    testWidgets('플레이스 계열 등록 유형은 셋뿐이다', (tester) async {
      await pumpRegisterType(tester);

      for (final title in ['이벤트 / 파티', '플레이스 등록']) {
        expect(find.text(title), findsOneWidget, reason: '"$title" 카드가 없다');
      }
      // 없어진 옛 카드 이름들도 함께 막아 둔다 — 되살아나면 여기서 걸린다.
      for (final gone in ['플레이스+파티 등록', '숙박+파티 등록', '파티 장소 등록']) {
        expect(find.text(gone), findsNothing, reason: '"$gone" 카드가 되살아났다');
      }

      // 두 유형은 그 칸 너머에 그대로 있다 — 없어진 것이 아니라 옮겨졌다.
      await tester.tap(find.text('이벤트 / 파티'));
      await tester.pumpAndSettle();
      for (final title in [
        HostOffering.party.label,
        HostOffering.placeEvent.label,
      ]) {
        expect(find.text(title), findsOneWidget, reason: '"$title" 카드가 없다');
      }
    });

    testWidgets('등록 유형 안내 시트에도 콤보 항목이 없다', (tester) async {
      await pumpRegisterType(tester);

      await tester.tap(find.byTooltip('등록 유형 안내'));
      await tester.pumpAndSettle();

      expect(find.text('플레이스+파티 등록'), findsNothing);
      expect(find.textContaining('플레이스와 파티를 지금 한 번에 등록해요'), findsNothing);
      expect(find.textContaining('파티나 이벤트도 함께'), findsNothing);
    });

    // 콤보 카드에만 있던 '?'가 사라졌는지 — 카드가 없으면 도움말도 열 수 없다.
    testWidgets('콤보 도움말 시트를 여는 길이 없다', (tester) async {
      await pumpRegisterType(tester);

      expect(
        find.widgetWithText(GestureDetector, '플레이스+파티 등록'),
        findsNothing,
      );
      expect(find.text('🍷 플레이스+파티 등록'), findsNothing);
    });
  });

  // ── 2. 신규 진입로가 코드에 남아 있지 않다 ──────────────────────────────
  //
  // 화면에서 카드만 지우고 클래스가 남아 있으면, 다른 진입점이 다시 그것을
  // 열 수 있다. 파일 단위로 못박는다.

  group('콤보 신규 등록 경로', () {
    const removedFiles = [
      'lib/screens/combo_register_screen.dart',
      'lib/screens/place_party_combo_register_screen.dart',
      'lib/screens/party_place_combo_register_screen.dart',
      'lib/models/combo_common_form.dart',
      'lib/widgets/combo_form/combo_common_info_section.dart',
    ];

    test('콤보 전용 등록 화면·폼 파일이 없다', () {
      final alive = removedFiles.where((p) => File(p).existsSync()).toList();
      expect(
        alive,
        isEmpty,
        reason: '콤보 신규 등록 파일이 되살아났다:\n${alive.join('\n')}',
      );
    });

    test('lib 어디에서도 콤보 등록 화면을 열지 않는다', () {
      const symbols = [
        'ComboRegisterScreen',
        'PlacePartyComboRegisterScreen',
        'PartyPlaceComboRegisterScreen',
        'ComboCommonForm',
      ];
      final offenders = <String>[];
      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          // 주석은 뺀다 — 왜 없앴는지 적어 두는 것이 이 변경의 핵심이다.
          final trimmed = line.trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
          for (final s in symbols) {
            if (line.contains(s)) offenders.add('${file.path}:${i + 1} — $s');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: '콤보 신규 등록 경로가 되살아났다:\n${offenders.join('\n')}',
      );
    });
  });

  // ── 3. 콤보 임시저장 ────────────────────────────────────────────────────
  //
  // 새로 만들 수도, 이어 쓸 수도 없어야 한다. 다만 운영에 남아 있는 옛 문서를
  // **지우지는 않는다** — 목록에 올라오지 않을 뿐이다.

  group('콤보 임시저장', () {
    test('콤보 임시저장 종류가 없다', () {
      expect(
        DraftType.values.map((t) => t.key).toList(),
        isNot(anyOf(contains('place_party_combo'), contains('stay_party_combo'))),
      );
    });

    // 남아 있는 옛 문서는 fromKey가 null을 돌려주어 목록에서 조용히 빠진다
    // (DraftService.watchAllDrafts가 null을 건너뛴다). 그러니 "이어서 작성"에
    // 나타나지도, 엉뚱한 폼으로 열리지도 않는다.
    test('남아 있는 옛 콤보 임시저장은 어떤 유형으로도 해석되지 않는다', () {
      expect(DraftType.fromKey('place_party_combo'), isNull);
      expect(DraftType.fromKey('stay_party_combo'), isNull);
    });

    test('임시저장 이어쓰기가 콤보 화면을 열지 않는다', () {
      final src = File('lib/screens/drafts_list_screen.dart').readAsStringSync();
      expect(src.contains('ComboRegisterScreen'), isFalse);
      expect(src.contains('stayPartyCombo'), isFalse);
      expect(src.contains('placePartyCombo'), isFalse);
    });

    // 공간 유형 → 임시저장 종류는 이제 1:1이다. 콤보용 종류가 다시 붙으면
    // 등록 화면이 어느 임시저장을 쓸지 갈라진다.
    test('공간 유형이 가리키는 임시저장은 단독 등록용 하나뿐이다', () {
      expect(ComboPlaceType.venue.soloDraftType, DraftType.event);
      expect(ComboPlaceType.stay.soloDraftType, DraftType.place);
    });
  });

  // ── 4. 이미 만들어진 콤보 문서는 그대로 읽힌다 ──────────────────────────
  //
  // 등록 경로를 없앴다고 **판정 코드까지** 없애면, 운영에 남아 있는 콤보
  // 파티/플레이스가 목록에서 배지를 잃고, 묶음 조회가 끊겨 예약·취소 안내가
  // 달라진다. 여기가 그 회귀를 잡는다.

  group('기존 콤보 문서 호환', () {
    test('숙박 콤보 파티를 여전히 숙박 콤보로 읽는다', () {
      expect(
        ComboPlaceType.ofPartyDoc({
          'isCombo': true,
          'comboPlaceType': 'stay',
        }),
        ComboPlaceType.stay,
      );
      // comboPlaceType이 없던 더 옛 문서는 연결 필드로 가른다.
      expect(
        ComboPlaceType.ofPartyDoc({'isCombo': true, 'linkedPlaceId': 'P1'}),
        ComboPlaceType.stay,
      );
      expect(
        ComboPlaceType.ofPartyDoc({'isCombo': true, 'linkedEventId': 'E1'}),
        ComboPlaceType.venue,
      );
    });

    test('콤보가 아닌 문서는 그대로 콤보가 아니다', () {
      expect(ComboPlaceType.ofPartyDoc(const {}), isNull);
      expect(ComboPlaceType.ofPartyDoc({'linkedPlaceId': 'P1'}), isNull);
    });

    test('목록 카드의 숙박 콤보 배지 판정이 살아 있다', () {
      expect(
        PartyCard.isStayPartyCombo({'isCombo': true, 'comboPlaceType': 'stay'}),
        isTrue,
      );
      // 매장 콤보에 숙박 배지가 붙으면 안 된다.
      expect(
        PartyCard.isStayPartyCombo({'isCombo': true, 'comboPlaceType': 'venue'}),
        isFalse,
      );
    });

    // 묶음 조회는 예약·취소 안내("숙박 예약과 파티 참가가 함께 취소돼요")와
    // 수정 화면의 형제 파티 목록이 함께 쓴다.
    test('묶음 판정이 살아 있다', () {
      expect(
        PartyBundleService.isBundledRegistration({'isCombo': true}),
        isTrue,
      );
      expect(
        PartyBundleService.isBundledRegistration({'bundleId': 'B1'}),
        isTrue,
      );
      // 사후 연결된 일반 파티는 묶음이 아니다 — 예전과 같은 기준.
      expect(
        PartyBundleService.isBundledRegistration({'linkedPlaceId': 'P1'}),
        isFalse,
      );
    });
  });

  // ── 5. 콤보를 대신하는 후속 흐름 ────────────────────────────────────────

  group('플레이스 등록 후 후속 흐름', () {
    // 두 등록 화면 모두에서 떠야 한다 — 한쪽만 부르면 그 유형으로 등록한
    // 사장님만 콤보의 대체 경로를 못 받는다.
    test('두 플레이스 등록 화면이 모두 후속 질문을 띄운다', () {
      for (final path in [
        'lib/screens/event_register_screen.dart',
        'lib/screens/place_register_screen.dart',
      ]) {
        expect(
          File(path).readAsStringSync(),
          contains('PlaceFollowupEntry.show('),
          reason: '$path가 등록 직후 후속 질문을 띄우지 않는다',
        );
      }
    });

    testWidgets('파티·이벤트 등록으로 이어지는 두 선택지를 준다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => PlaceFollowupEntry.show(
                    context,
                    placeId: 'P1',
                    placeCollection: 'places',
                    placeData: const {'hostId': 'host-me', 'name': 'OO 파티룸'},
                    placeName: 'OO 파티룸',
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

      expect(find.text('이 플레이스에서 파티나 매장 이벤트를 여시나요?'), findsOneWidget);
      // 선택 카드는 등록 화면과 **같은 위젯**이다([HostOfferingChoice]) —
      // 이름도 판단 기준도 두 자리에서 같은 문장이다.
      expect(find.text(HostOffering.party.label), findsOneWidget);
      expect(find.text(HostOffering.placeEvent.label), findsOneWidget);
      expect(find.text(HostOffering.criterionHeadline), findsOneWidget);
      expect(find.text('나중에 할게요'), findsOneWidget);
      // 어느 플레이스에 붙는지 이름으로 못박아 준다 — 다시 고르게 하지 않는
      // 대신, 무엇이 골라져 있는지는 보여야 한다(콤보를 대신하는 핵심).
      expect(find.text('OO 파티룸'), findsOneWidget);
    });

    testWidgets("'나중에 할게요'는 아무 데도 보내지 않는다", (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => PlaceFollowupEntry.show(
                    context,
                    placeId: 'E1',
                    placeCollection: 'events',
                    placeData: const {'hostId': 'host-me', 'name': 'OO 혼술바'},
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
      await tester.tap(find.text('나중에 할게요'));
      await tester.pumpAndSettle();

      expect(find.text('이 플레이스에서 파티나 이벤트를 여시나요?'), findsNothing);
      expect(find.text('저장'), findsOneWidget);
    });
  });
}

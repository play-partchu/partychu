// 공간 유형 선택("어떤 공간인가요?")이 **두 유형의 폼에서 완전히 같은지**.
//
//   · 매장·즐길거리  → EventRegisterScreen (`events`)
//   · 공간대여·숙박  → PlaceRegisterScreen (`places` + `placeRooms`)
//
// 진입은 통합 셸([PlaceEntryRegisterScreen]) 하나지만 폼은 둘로 갈라져 있다.
// 예전에 "파티 장소 등록"이 별도 카드로 있던 시절처럼, 한쪽 화면에서만
// 선택지를 고치면 같은 질문에 화면마다 다른 답이 나온다.
//
// (플레이스와 파티를 한 폼에서 함께 만들던 콤보 등록 화면 둘도 예전에는 이
//  선택기를 함께 썼다 — 그 등록 방식이 없어지면서 대조 대상에서 빠졌다.)
//
// 그래서 세 가지를 고정한다.
//  1) 선택 UI가 **같은 위젯**([SpaceTypeSelector])으로 그려진다 —
//     화면마다 자기 선택기를 따로 만들면 여기서 걸린다.
//  2) 화면에 실제로 그려진 **글자가 완전히 같다** — 문구를 한 화면에만
//     하드코딩해 두면 여기서 걸린다.
//  3) **분기 조건**(유형 → 컬렉션 / 임시저장 종류)이 하나의 정본에서 나온다.
//
// Firebase는 초기화하지 않는다 — 등록 화면은 검증을 통과하기 전까지 Firebase를
// 만지지 않으므로 앱 없이 그대로 그려진다(register_screens_missing_field_jump
// _test.dart와 같은 전제).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:party_app/models/combo_place_type.dart';
import 'package:party_app/models/draft_type.dart';
import 'package:party_app/models/place_taxonomy.dart';
import 'package:party_app/screens/event_register_screen.dart';
import 'package:party_app/screens/place_entry_register_screen.dart';
import 'package:party_app/screens/place_register_screen.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/place_scope_notice.dart';
import 'package:party_app/widgets/space_type_selector.dart';

// 아주 긴 화면으로 띄운다 — ListView는 화면에 들어오는 만큼만 만들기 때문에,
// 보통 크기로는 폼 위쪽 몇 개만 존재하게 되어 "선택기가 없다"로 잘못 읽힌다
// (등록 폼 위젯 테스트가 공통으로 쓰는 방식).
const Size _screen = Size(420, 3600);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UserSession.userId = 'test-user';
  });
  tearDown(() => UserSession.userId = '');

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = _screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: screen));
    // pumpAndSettle을 쓰지 않는다 — 등록 화면에는 계속 도는 애니메이션이
    // 있어 영영 멈추지 않는다. 정해진 수만큼 프레임을 흘려보낸다.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// 화면에 그려진 [SpaceTypeSelector] 하나가 담고 있는 모든 글자.
  /// 순서까지 포함해 비교하므로 "같은 말이 다른 자리에 있는" 경우도 걸린다.
  List<String> selectorTexts(WidgetTester tester) {
    final selector = find.byType(SpaceTypeSelector);
    expect(
      selector,
      findsOneWidget,
      reason: '이 화면이 공용 공간 유형 선택기를 쓰지 않는다',
    );
    return tester
        .widgetList<Text>(
          find.descendant(of: selector, matching: find.byType(Text)),
        )
        .map((t) => t.data ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  // ── 1. 정본 하나에서 나온다 ─────────────────────────────────────────
  group('공간 유형의 정본', () {
    test('선택지는 ComboPlaceType 두 개뿐이다', () {
      expect(ComboPlaceType.values, [
        ComboPlaceType.venue,
        ComboPlaceType.stay,
      ]);
    });

    test('분기 조건 — 유형이 곧 저장 컬렉션이다', () {
      expect(ComboPlaceType.venue.placeCollection, 'events');
      expect(ComboPlaceType.stay.placeCollection, 'places');
    });

    // 유형이 둘뿐이므로 "매장·즐길거리"는 홈 플레이스 대분류를 **전부** 받는
    // 그릇이다. 예시가 술집·카페로 좁으면 클럽·놀거리·체험 사장님이 이 유형을
    // 자기 것이 아니라고 지나치고, 그러면 등록할 자리가 아예 없어진다.
    // 대분류가 늘거나 이름이 바뀌면 여기서 걸린다.
    test('매장·즐길거리 예시가 홈 플레이스 대분류를 모두 포괄한다', () {
      // 대분류 저장값 → 예시 문구에 반드시 나와야 하는 말.
      // 저장값과 부르는 이름이 다른 것들이 있어(맛집=푸드) 표로 둔다.
      const wordOf = <String, String>{
        '맛집': '음식점',
        '다이닝·파인다이닝': '다이닝',
        '카페·디저트': '카페',
        '술집': '술집',
        '혼술바': '혼술바',
        'BAR': 'BAR',
        '클럽': '클럽',
        '라이브·공연': '라이브',
        '놀거리': '놀거리',
        '체험·클래스': '체험·클래스',
      };

      expect(
        wordOf.keys.toSet(),
        PlaceTaxonomy.all.map((c) => c.label).toSet(),
        reason: '홈 대분류가 바뀌었다 — 매장·즐길거리 예시 문구도 함께 고쳐야 한다',
      );
      for (final e in wordOf.entries) {
        expect(
          ComboPlaceType.venue.examples,
          contains(e.value),
          reason: '대분류 "${e.key}"가 매장·즐길거리 예시에서 빠졌다',
        );
      }
    });

    test('공간대여·숙박 예시는 대관 공간과 숙박을 모두 든다', () {
      for (final word in ['파티룸', '스튜디오', '대관 공간', '호텔', '게스트하우스']) {
        expect(ComboPlaceType.stay.examples, contains(word));
      }
    });

    test('유형마다 임시저장 종류가 하나씩이다', () {
      // **예전에 쓰던 두 종류를 그대로** 쓴다 — 합치기 전에 저장해둔
      // 임시저장이 새 화면에서도 열려야 한다.
      expect(ComboPlaceType.venue.soloDraftType, DraftType.event);
      expect(ComboPlaceType.stay.soloDraftType, DraftType.place);
    });

    // 플레이스와 파티를 한 폼에서 함께 만들던 콤보 등록이 없어지면서 그
    // 임시저장 종류도 사라졌다. 같은 key가 되살아나면 운영에 남아 있는 옛
    // 콤보 임시저장이 엉뚱한 폼으로 복원된다.
    test('콤보 임시저장 종류는 되살아나지 않는다', () {
      expect(
        DraftType.values.map((t) => t.key),
        isNot(contains('place_party_combo')),
      );
      expect(
        DraftType.values.map((t) => t.key),
        isNot(contains('stay_party_combo')),
      );
      expect(DraftType.fromKey('place_party_combo'), isNull);
      expect(DraftType.fromKey('stay_party_combo'), isNull);
    });

    test('임시저장 종류로 유형을 되찾을 수 있다', () {
      for (final t in ComboPlaceType.values) {
        expect(ComboPlaceType.fromDraftType(t.soloDraftType), t);
      }
    });

    testWidgets('선택기는 두 선택지의 이름·배지·예시를 모두 보여준다', (tester) async {
      await pumpScreen(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: SpaceTypeSelector(
              value: ComboPlaceType.venue,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('어떤 공간인가요?'), findsOneWidget);
      for (final t in ComboPlaceType.values) {
        expect(find.text(t.label), findsOneWidget);
        expect(find.text(t.kindLabel), findsOneWidget);
        expect(find.text(t.examples), findsOneWidget);
      }
    });
  });

  // ── 2. 두 유형의 폼이 선택 UI를 글자까지 같게 그린다 ────────────────
  group('매장·즐길거리 ↔ 공간대여·숙박', () {
    testWidgets('두 폼의 선택 UI 문구가 완전히 같다', (tester) async {
      await pumpScreen(
        tester,
        EventRegisterScreen(onSpaceTypeChanged: (_) {}),
      );
      final venue = selectorTexts(tester);
      // 실제로 그 유형이 선택된 채로 열리는지도 함께 본다.
      expect(
        tester.widget<SpaceTypeSelector>(find.byType(SpaceTypeSelector)).value,
        ComboPlaceType.venue,
      );

      await pumpScreen(
        tester,
        PlaceRegisterScreen(onSpaceTypeChanged: (_) {}),
      );
      final stay = selectorTexts(tester);
      expect(
        tester.widget<SpaceTypeSelector>(find.byType(SpaceTypeSelector)).value,
        ComboPlaceType.stay,
      );

      // 어느 유형으로 열든 선택지·문구는 같다 — 다른 것은 "지금 어느 쪽이
      // 골라져 있나"뿐이다.
      expect(stay, venue);
    });

    testWidgets('두 화면이 모두 같은 선택기 위젯을 쓴다', (tester) async {
      for (final screen in <Widget>[
        EventRegisterScreen(onSpaceTypeChanged: (_) {}),
        PlaceRegisterScreen(onSpaceTypeChanged: (_) {}),
      ]) {
        await pumpScreen(tester, screen);
        expect(
          find.byType(SpaceTypeSelector),
          findsOneWidget,
          reason: '${screen.runtimeType}가 공용 선택기를 쓰지 않는다',
        );
      }
    });
  });

  // ── 3. 선택기가 나오지 않아야 하는 자리 ─────────────────────────────
  group('선택기를 그리지 않는 경우', () {
    testWidgets('셸을 거치지 않고 연 단독 등록 화면에는 없다', (tester) async {
      // 유형을 바꿔 봐야 알려줄 셸이 없다 — 선택지를 보여주면 눌러도
      // 아무 일도 일어나지 않는 버튼이 된다.
      await pumpScreen(tester, const EventRegisterScreen());
      expect(find.byType(SpaceTypeSelector), findsNothing);

      await pumpScreen(tester, const PlaceRegisterScreen());
      expect(find.byType(SpaceTypeSelector), findsNothing);
    });

    // 수정 화면은 진입 즉시 Firestore를 읽으므로 여기서 띄울 수 없다.
    // 대신 선택기를 그리는 **유일한 조건**을 생성자에서 확인한다 —
    // onSpaceTypeChanged가 null이면 화면은 선택기를 만들지 않는다.
    test('수정 생성자는 유형 전환을 아예 받지 않는다 — 만들어진 문서의 컬렉션은 못 바꾼다', () {
      const eventEdit = EventRegisterScreen.edit(
        eventId: 'e1',
        sourceData: {},
      );
      const placeEdit = PlaceRegisterScreen.edit(
        docId: 'p1',
        sourceData: {},
      );
      expect(eventEdit.onSpaceTypeChanged, isNull);
      expect(placeEdit.onSpaceTypeChanged, isNull);
      expect(eventEdit.mode.isEdit, isTrue);
      expect(placeEdit.mode.isEdit, isTrue);
    });
  });

  // ── 4. 임시저장은 합치기 전 그대로 이어진다 ─────────────────────────
  //
  // 두 카드를 하나로 합치면서 가장 쉽게 깨지는 곳이다 — 셸이 새 임시저장
  // 종류를 만들어 버리면, 옛 "파티 장소 등록"에서 쓰다 만 글(`draft_place`)이
  // 통째로 사라진 것처럼 보인다.
  group('통합 진입 화면의 임시저장', () {
    testWidgets('장소대여 임시저장만 있으면 "공간대여·숙박"으로 열린다', (tester) async {
      SharedPreferences.setMockInitialValues({
        'draft_place': jsonEncode({
          'type': 'place',
          'title': '양평 파티룸',
          'payload': {'name': '양평 파티룸'},
          'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
          'schemaVersion': 1,
        }),
      });

      await pumpScreen(tester, const PlaceEntryRegisterScreen());

      expect(find.byType(PlaceRegisterScreen), findsOneWidget);
      expect(
        tester.widget<SpaceTypeSelector>(find.byType(SpaceTypeSelector)).value,
        ComboPlaceType.stay,
      );
    });

    testWidgets('"이어서 작성"으로 열면 옛 draft_place 내용이 그대로 복원된다', (tester) async {
      SharedPreferences.setMockInitialValues({
        'draft_place': jsonEncode({
          'type': 'place',
          'title': '양평 파티룸',
          'payload': {'name': '양평 파티룸'},
          'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
          'schemaVersion': 1,
        }),
      });

      await pumpScreen(
        tester,
        const PlaceEntryRegisterScreen(
          initialType: ComboPlaceType.stay,
          autoRestoreDraft: true,
        ),
      );

      // 복구 여부를 묻지 않고 곧바로 들어와야 한다.
      expect(find.text('작성 중인 내용이 있습니다'), findsNothing);
      expect(find.text('양평 파티룸'), findsWidgets);
    });

    testWidgets('임시저장이 없으면 기본은 "매장·즐길거리"다', (tester) async {
      await pumpScreen(tester, const PlaceEntryRegisterScreen());

      expect(find.byType(EventRegisterScreen), findsOneWidget);
      expect(
        tester.widget<SpaceTypeSelector>(find.byType(SpaceTypeSelector)).value,
        ComboPlaceType.venue,
      );
    });
  });

  // ── 5. 상단 안내 ────────────────────────────────────────────────────
  group('플레이스 등록 상단 안내', () {
    testWidgets('두 유형의 폼이 같은 안내 위젯을 쓴다', (tester) async {
      for (final screen in <Widget>[
        const EventRegisterScreen(),
        const PlaceRegisterScreen(),
      ]) {
        await pumpScreen(tester, screen);
        expect(
          find.byType(PlaceScopeNotice),
          findsOneWidget,
          reason: '${screen.runtimeType}에 상단 안내가 없다',
        );
        for (final line in PlaceScopeNotice.lines) {
          expect(find.text(line.text), findsOneWidget);
        }
      }
    });

    testWidgets('안내는 두 가지를 말한다 — 어떤 공간까지 되는지, 파티는 나중에 붙여도 되는지', (
      tester,
    ) async {
      final all = PlaceScopeNotice.lines.map((l) => l.text).join('\n');
      // 방문형·예약형 양쪽이 모두 언급돼야 한다. 방문형 쪽은 술집·카페만
      // 들면 클럽·놀거리·체험 사장님이 지나치므로, 먹고 마시는 곳 밖의
      // 대분류까지 이름이 나와야 한다.
      expect(all, contains('음식점'));
      expect(all, contains('카페'));
      expect(all, contains('술집'));
      expect(all, contains('클럽'));
      expect(all, contains('라이브'));
      expect(all, contains('놀거리'));
      expect(all, contains('체험'));
      expect(all, contains('공간대여·숙박'));
      // 플레이스만 먼저 올려도 된다는 것 + 등록한 뒤에 연결할 수 있다는 것.
      // 이 두 가지가 "플레이스 등록"이 "플레이스+파티 등록"과 갈리는 지점이다.
      expect(all, contains('먼저 등록'));
      expect(all, contains('등록 후'));
      expect(all, contains('연결'));
    });

    // 수정 화면(Firestore를 읽어야 뜬다)은 여기서 띄우지 않는다 — 안내는
    // `if (!_isEdit)` 한 줄로만 갈리고, 그 조건은 위 그룹에서 mode로 고정했다.
  });
}

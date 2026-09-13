// 등록 유형 화면의 **도움말 문구**가 실제 서비스 범위와 맞는지.
//
// 플레이스 대분류는 푸드·카페·술집·혼술바·BAR·클럽·라이브·놀거리·체험/클래스
// 아홉인데, 도움말은 오래도록 "혼술바·술집·카페 등 매장"이라고만 말해 왔다.
// 클럽·라이브·놀거리·체험 사장님에게는 이 등록이 자기 것으로 읽히지 않는다 —
// 문구 하나가 등록 자체를 막는 자리라, 좁은 표현이 되돌아오면 여기서 걸린다.
//
// 안내 문구만 본다. 저장 스키마(`events`/`places`/`placeRooms`)나 예약 분기는
// 이 검사의 대상이 아니다.
//
// Firestore는 건드리지 않는다 — 상단 사업자 인증 안내는 로그아웃이면 아무것도
// 그리지 않는다(다른 등록 화면 위젯 테스트와 같은 전제).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:party_app/models/combo_place_type.dart';
import 'package:party_app/screens/place_entry_register_screen.dart';
import 'package:party_app/screens/register_type_screen.dart';
import 'package:party_app/utils/user_session.dart';

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

  group('등록 유형 안내(AppBar ?)', () {
    testWidgets('플레이스 계열 카드 설명이 좁은 표현으로 돌아가지 않는다', (tester) async {
      await pumpRegisterType(tester);

      await tester.tap(find.byTooltip('등록 유형 안내'));
      await tester.pumpAndSettle();

      // 예시 칩에 먹고 마시는 곳 밖의 대분류가 함께 있어야 한다.
      for (final chip in ['클럽·댄스', '라이브', '놀거리', '체험/클래스']) {
        expect(
          find.text(chip),
          findsWidgets,
          reason: '등록 유형 안내에 "$chip" 예시가 없다',
        );
      }
      expect(find.textContaining('술집·바·카페'), findsNothing);
    });

    // 플레이스와 파티를 한 폼에서 함께 만들던 "플레이스+파티 등록"은
    // 없어졌다. 안내가 그 카드를 계속 설명하면, 사장님은 등록 화면에
    // 없는 유형을 찾게 된다.
    testWidgets('플레이스+파티 등록 항목이 없다', (tester) async {
      await pumpRegisterType(tester);

      await tester.tap(find.byTooltip('등록 유형 안내'));
      await tester.pumpAndSettle();

      expect(find.text('플레이스+파티 등록'), findsNothing);
      expect(find.textContaining('플레이스와 파티를 지금 한 번에 등록해요'), findsNothing);
    });

    // 콤보가 하던 일("파티도 함께 여는 사장님")은 플레이스 등록 뒤의 후속
    // 흐름이 대신한다 — 안내가 그 다음 단계를 말해야 사장님이 "여기가
    // 내 자리"라고 알아본다.
    testWidgets('플레이스 등록이 파티·이벤트로 이어진다고 말한다', (tester) async {
      await pumpRegisterType(tester);

      await tester.tap(find.byTooltip('등록 유형 안내'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          '등록을 마치면 이 플레이스에서 여는 파티·이벤트를 바로 이어서 '
          '등록할 수 있어요. 나중에 추가하거나 고쳐도 돼요.',
        ),
        findsOneWidget,
      );
    });

    // 🎪 매장 이벤트만 **전제 조건**이 있다(내 플레이스가 1개 이상). 그 사실이
    // 안내에 없으면, 눌러 보고 나서야 순서를 알게 된다.
    testWidgets('매장 이벤트는 기존 플레이스가 있어야 한다고 말한다', (tester) async {
      await pumpRegisterType(tester);

      await tester.tap(find.byTooltip('등록 유형 안내'));
      await tester.pumpAndSettle();

      expect(find.text('매장 이벤트'), findsWidgets);
      expect(find.textContaining('이미 등록해 둔 플레이스에서 진행하는'), findsOneWidget);
      expect(
        find.textContaining('플레이스가 있어야 등록할 수 있어요.'),
        findsOneWidget,
        reason: '매장 이벤트의 전제 조건이 안내에 없다',
      );
    });

    // 🎪와 🎉가 무엇으로 갈리는지 — 콘텐츠 종류도, 신청 여부도 아니라
    // **누가 여는가**다. 매장 이벤트에는 생일 이벤트처럼 사전 신청을 받는
    // 것도 있어서, 신청 여부로 가르면 그것이 갈 곳을 잃는다([HostOffering]).
    testWidgets('매장 이벤트와 파티의 구분 기준을 말한다', (tester) async {
      await pumpRegisterType(tester);

      await tester.tap(find.byTooltip('등록 유형 안내'));
      await tester.pumpAndSettle();

      expect(find.textContaining('매장에서 진행하는 이벤트·혜택'), findsWidgets);
      expect(find.textContaining('참가자를 모집하고 신청을 받는 행사'), findsWidgets);
      expect(
        find.textContaining('신청 없이'),
        findsNothing,
        reason: '매장 이벤트를 "신청 없는 행사"로 정의하면 안 된다',
      );
      // 같은 DJ 공연이라도 모집을 받으면 파티라는 예시.
      expect(find.textContaining('"30명 모집"이면 파티'), findsOneWidget);
    });
  });

  // ── 플레이스 등록 '?' ───────────────────────────────────────────────────
  // 예전에는 이 도움말이 없어진 "플레이스+파티 등록" 카드에만 있었다. 콤보를
  // 빼면서 그 역할까지 이 카드 하나가 맡는다 — 공간만 올리든 파티까지 열든
  // 시작하는 자리는 여기다.
  group('플레이스 등록 도움말', () {
    /// '플레이스 등록' 카드 제목 옆의 '?'. AppBar에도 같은 아이콘이 있으므로
    /// **이 카드 안에 있는 것**만 골라 잡는다.
    Future<void> openPlaceHelp(WidgetTester tester) async {
      final help = find.descendant(
        of: find.widgetWithText(GestureDetector, '플레이스 등록').first,
        matching: find.byIcon(Icons.question_mark_rounded),
      );
      expect(help, findsOneWidget, reason: '플레이스 등록 카드에 도움말 버튼이 없다');
      await tester.ensureVisible(help);
      await tester.pump();
      await tester.tap(help);
      await tester.pumpAndSettle();
    }

    // '?'는 카드 전체가 눌리는 영역 안에 있다. 탭이 카드로 새어 나가면
    // 도움말을 읽으려던 사람이 등록 화면으로 끌려간다.
    testWidgets("'?' 탭이 등록 화면으로 넘어가지 않는다", (tester) async {
      await pumpRegisterType(tester);
      await openPlaceHelp(tester);

      expect(
        find.byType(PlaceEntryRegisterScreen),
        findsNothing,
        reason: "'?' 탭이 카드로 새어 나가 등록 화면이 열렸다",
      );
      // 대신 도움말만 떠 있어야 한다.
      expect(find.text('🥂 플레이스 등록'), findsOneWidget);
    });

    testWidgets('두 공간 유형을 정본 이름 그대로 든다', (tester) async {
      await pumpRegisterType(tester);
      await openPlaceHelp(tester);

      // 이름·이모지는 ComboPlaceType 정본에서 온다 — 등록 화면의 유형 선택
      // 카드와 말이 갈라지지 않게.
      expect(
        find.text(
          '${ComboPlaceType.venue.emoji} ${ComboPlaceType.venue.label}',
        ),
        findsOneWidget,
      );
      expect(
        find.text('${ComboPlaceType.stay.emoji} ${ComboPlaceType.stay.label}'),
        findsOneWidget,
      );
    });

    testWidgets('예시가 ComboPlaceType 정본과 어긋나지 않는다', (tester) async {
      await pumpRegisterType(tester);
      await openPlaceHelp(tester);

      expect(
        find.textContaining(ComboPlaceType.venue.examples),
        findsOneWidget,
        reason: '방문형 예시가 정본과 다르다',
      );
      expect(
        find.textContaining(ComboPlaceType.stay.examples),
        findsOneWidget,
        reason: '예약형 예시가 정본과 다르다',
      );
      // 정본 목록에 실제로 들어 있어야 할 업종들 — 좁은 표현으로 되돌아가면
      // 그 업종 사장님이 이 등록을 지나친다.
      for (final word in [
        '음식점',
        '카페',
        '술집',
        '혼술바',
        'BAR',
        '클럽',
        '라이브',
        '놀거리',
        '체험·클래스',
        '파티룸',
        '대관 공간',
        '호텔',
        '모텔',
        '펜션',
        '게스트하우스',
      ]) {
        expect(
          find.textContaining(word),
          findsWidgets,
          reason: '플레이스 등록 도움말에 "$word"가 없다',
        );
      }
    });

    testWidgets('방문형·예약형이 각자 무엇을 등록하는지 말한다', (tester) async {
      await pumpRegisterType(tester);
      await openPlaceHelp(tester);

      expect(
        find.textContaining('사람들이 방문해서 즐기는 플레이스를 등록할 수 있어요.'),
        findsOneWidget,
      );
      expect(find.textContaining('예약형 공간도 등록할 수 있어요.'), findsOneWidget);
    });

    // 없어진 콤보 등록이 하던 일을 이 카드가 이어받았다 — 파티를 함께 여는
    // 사장님에게 "여기가 내 자리"이자 "그 다음이 있다"를 말해야 한다.
    testWidgets('별도 안내 두 줄로 끝나고, 파티·이벤트로 이어진다고 말한다', (tester) async {
      await pumpRegisterType(tester);
      await openPlaceHelp(tester);

      expect(
        find.text('등록을 마치면 이 플레이스에서 여는 파티·이벤트를 바로 이어서 등록할 수 있어요.'),
        findsOneWidget,
      );
      expect(
        find.text('등록 후에도 새로운 파티·이벤트를 추가로 연결하거나 기존 연결을 수정할 수 있어요.'),
        findsOneWidget,
      );
    });

    // 콤보 등록은 없어졌다 — 도움말이 "지금 한 번에 등록한다"고 말하면
    // 사장님은 이 폼에서 파티까지 입력하려다 못 찾는다.
    testWidgets('없어진 콤보 등록을 설명하지 않는다', (tester) async {
      await pumpRegisterType(tester);
      await openPlaceHelp(tester);

      expect(find.textContaining('파티나 이벤트도 진행하시나요'), findsNothing);
      expect(find.textContaining('한 번에 등록'), findsNothing);
      expect(find.textContaining('파티도 함께 운영'), findsNothing);
    });
  });
}

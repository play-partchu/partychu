import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:party_app/screens/event_register_screen.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/partychu_perk.dart';
import 'package:party_app/widgets/partychu_perk_plaque.dart';
import 'package:party_app/widgets/party_card_widget.dart';
import 'package:party_app/widgets/place_card_widget.dart';

// "파티츄 전용 혜택" — 등록 화면의 안내 카드/입력칸과 상세페이지 노출 카드.

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UserSession.userId = 'test-user';
  });
  tearDown(() => UserSession.userId = '');

  group('문서에서 혜택 읽기', () {
    test('값이 있으면 그대로, 없거나 공백뿐이면 null', () {
      expect(partychuPerkFrom({kPartychuPerkField: '생맥주 1잔 무료'}), '생맥주 1잔 무료');
      // 예전 문서에는 필드 자체가 없다.
      expect(partychuPerkFrom({}), isNull);
      expect(partychuPerkFrom(null), isNull);
      // 혜택 없이 등록하면 빈 문자열로 저장된다 — 카드가 뜨면 안 된다.
      expect(partychuPerkFrom({kPartychuPerkField: '   '}), isNull);
      // 다른 타입이 들어와도 죽지 않는다.
      expect(partychuPerkFrom({kPartychuPerkField: 123}), isNull);
    });
  });

  // ── 목록 카드 명판 ──────────────────────────────────────────────────────
  // 예전에는 목록 카드에 '🎁 파티츄 전용 혜택' **글자 배지**가 붙었다. 카드마다
  // 제목 위 한 줄을 통째로 먹어서 없앴고, 지금은 partychu_perk_plaque.dart의
  // 로즈골드 명판을 카드 위에 덧그린다(레이아웃에 관여하지 않는다).
  //
  // 그래서 이 그룹은 **글자를 찾지 않는다** — 명판이 조건에 맞게 들고 나는지만
  // 본다. 명판 그림·크기·모서리 위치는 카드 종류마다 다르고 앞으로도 바뀔 수
  // 있으므로 건드리지 않는다.
  group('목록 카드 명판', () {
    Map<String, dynamic> partyDoc({String? perk}) => {
      'title': '금요일 밤 파티',
      'recruitStatus': '모집중',
      'partyDateTime': Timestamp.fromDate(
        DateTime.now().add(const Duration(days: 3)),
      ),
      if (perk != null) kPartychuPerkField: perk,
    };

    Map<String, dynamic> placeDoc({String? perk}) => {
      'name': '연남동 혼술바',
      'type': '바',
      'address': '서울 마포구 연남동',
      if (perk != null) kPartychuPerkField: perk,
    };

    /// 명판은 그림 한 장을 [PartychuPerkPlaquePainter]가 직접 그린다 — 글자가
    /// 아니라 텍스트로는 찾을 수 없다. **그리는 주체**로 잡으면 명판 그림이나
    /// 크기·자리가 바뀌어도 이 검사는 그대로 산다.
    final plaque = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is PartychuPerkPlaquePainter,
      description: '파티츄 혜택 명판',
    );

    /// 카드를 띄우고 [checks]를 돌린 뒤 **화면에서 내리는 것까지** 이 안에서
    /// 끝낸다.
    ///
    /// 카드 안의 찜 버튼([FavoriteStarButton])은 Firebase를 요구한다 — 앱이
    /// 없는 테스트 환경에서는 그 서브트리만 에러 위젯이 되고 나머지(명판
    /// 포함)는 정상 렌더링되지만, dispose에서도 예외를 던진다. 카드를 내리는
    /// 시점을 테스트 안으로 끌어와야 그 예외까지 여기서 소비할 수 있다
    /// (테스트가 끝난 뒤 정리 단계에서 터지면 잡을 방법이 없다).
    ///
    /// 명판 그림 에셋을 못 읽는 경우도 같은 방식으로 흘려보낸다 — 그림이
    /// 없어도 CustomPaint는 트리에 그대로 있어서 검증에는 영향이 없다.
    Future<void> withCard(
      WidgetTester tester,
      Widget card,
      void Function() checks,
    ) async {
      tester.view.physicalSize = const Size(420, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: card)),
        ),
      );
      await tester.pump();
      while (tester.takeException() != null) {}

      checks();

      await tester.pumpWidget(const SizedBox.shrink());
      while (tester.takeException() != null) {}
    }

    // 목록 카드는 종류가 여러 개라(파티 3종 + 플레이스 2종) 하나만 붙이면
    // 누락이 생긴다 — 전부 같은 규칙으로 검증한다.
    //
    // 파티 작은 카드는 [PartyCardBase]가 아니라 이를 감싸는 [PartyCard]다 —
    // 명판을 붙이는 카드 껍데기(ListCardShell.decorationOverlay)가 바깥에
    // 있어서, 속만 띄우면 명판이 있을 수 없다.
    final cards = <String, Widget Function({String? perk})>{
      'PartyCard(작은 카드·지도·찜)': ({perk}) =>
          PartyCard(party: partyDoc(perk: perk), docId: 'p1'),
      'PartyStandardCard(기본 카드)': ({perk}) => PartyStandardCard(
        party: partyDoc(perk: perk),
        docId: 'p1',
      ),
      // 얼리버드가 켜져 있으면 명판 대신 얼리버드 테두리가 그려진다 — 위
      // partyDoc에는 얼리버드 필드가 없으므로 명판 쪽으로 간다.
      'PartyCompactCard(컴팩트 카드)': ({perk}) => PartyCompactCard(
        party: partyDoc(perk: perk),
        docId: 'p1',
      ),
      'PlaceCompactCard(플레이스 작은 카드)': ({perk}) => PlaceCompactCard(
        place: placeDoc(perk: perk),
        placeId: 'pl1',
        source: PlaceCardSource.place,
      ),
      'PlaceStandardCard(플레이스 기본 카드)': ({perk}) => PlaceStandardCard(
        place: placeDoc(perk: perk),
        placeId: 'pl1',
        source: PlaceCardSource.rental,
      ),
    };

    for (final entry in cards.entries) {
      testWidgets('${entry.key} — 혜택이 있으면 명판이 붙는다', (tester) async {
        await withCard(tester, entry.value(perk: '생맥주 1잔 무료'), () {
          expect(plaque, findsOneWidget);
          // 목록에는 혜택 "내용"을 노출하지 않는다 — 명판만 붙고 문구는 상세에서.
          expect(find.text('생맥주 1잔 무료'), findsNothing);
          // 없앤 글자 배지가 되살아나면 카드마다 한 줄을 다시 먹는다.
          expect(find.textContaining('파티츄 전용 혜택'), findsNothing);
        });
      });

      testWidgets('${entry.key} — 혜택이 없으면 명판이 없다', (tester) async {
        await withCard(tester, entry.value(), () {
          expect(plaque, findsNothing);
        });
      });
    }

    // 두 플레이스 카드가 명판을 붙일지 말지는 **같은 값 하나**([PlaceCardInfo.
    // hasPartychuPerk])로 정해진다 — 한쪽 카드에서만 명판이 빠지는 일이 없다.
    for (final source in PlaceCardSource.values) {
      test('PlaceCardInfo($source) — 혜택 유무가 명판 조건으로 그대로 넘어간다', () {
        PlaceCardInfo info(Map<String, dynamic> data) =>
            PlaceCardInfo.from(data, source: source, tag: 'test');

        expect(info(placeDoc(perk: '생맥주 1잔 무료')).hasPartychuPerk, isTrue);
        expect(info(placeDoc()).hasPartychuPerk, isFalse);
        // 공백뿐인 값은 혜택이 없는 것과 같다(partychuPerkFrom과 같은 기준).
        expect(info(placeDoc(perk: '   ')).hasPartychuPerk, isFalse);
      });

      // 혜택은 배지 목록이 아니라 카드 껍데기(decorationOverlay)가 맡는다.
      // 배지로 되돌아오면 없앴던 한 줄이 카드마다 다시 생긴다.
      test('placeCardBadges($source) — 혜택은 배지 목록에 들어가지 않는다', () {
        final withPerk = placeCardBadges(
          PlaceCardInfo.from(
            placeDoc(perk: '생맥주 1잔 무료'),
            source: source,
            tag: 'test',
          ),
        );
        final without = placeCardBadges(
          PlaceCardInfo.from(placeDoc(), source: source, tag: 'test'),
        );

        expect(withPerk.length, without.length);
      });
    }
  });

  group('상세페이지 카드', () {
    testWidgets('혜택이 있으면 제목과 문구가 크게 보인다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PartychuPerkCard(perk: '파티츄 보고 왔다고 하시면 생맥주 1잔 무료!'),
          ),
        ),
      );

      expect(find.text('파티츄 전용 혜택'), findsOneWidget);
      expect(find.text('파티츄 보고 왔다고 하시면 생맥주 1잔 무료!'), findsOneWidget);
    });

    testWidgets('혜택이 없으면 아무것도 그리지 않는다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PartychuPerkCard(perk: null))),
      );

      expect(find.text('파티츄 전용 혜택'), findsNothing);
    });
  });

  testWidgets('등록 화면에 안내 카드와 입력칸이 있고, 입력하면 임시저장에 남는다', (tester) async {
    tester.view.physicalSize = const Size(420, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: EventRegisterScreen()));
    await tester.pumpAndSettle();

    // 폼 맨 아래 섹션이라 ListView가 아직 안 그렸을 수 있다 — 스크롤해서 찾는다.
    final title = find.text('🌟 파티츄 오픈 이벤트!');
    await tester.scrollUntilVisible(
      title,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(title, findsOneWidget);

    // 입력칸은 문구 정본(hintText)으로 찾는다 — 여기 문자열을 따로 적으면
    // 정본이 바뀔 때 이 테스트만 조용히 옛 문구에 묶인다.
    final field = find.widgetWithText(
      TextFormField,
      PartychuPerkAudience.store.hintText,
    );
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, '웰컴드링크 제공');
    await tester.pump();

    final saveBtn = find.widgetWithText(TextButton, '임시저장');
    await tester.ensureVisible(saveBtn);
    await tester.pumpAndSettle();
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('draft_event');
    expect(raw, isNotNull, reason: '임시저장이 기록되지 않았습니다.');
    expect(raw, contains('웰컴드링크 제공'));
  });

  // ── 오픈 이벤트 안내 문구 ────────────────────────────────────────────────
  // 등록 화면들(파티 / 플레이스)이 이 섹션 하나를 쓴다. 문구 정본이
  // [partychu_perk.dart]에만 있어야 화면들이 같이 바뀌므로, 여기서는
  // **위젯이 그리는 것**을 상수와 대조한다.
  group('🌟 파티츄 오픈 이벤트 안내', () {
    Future<void> pumpSection(
      WidgetTester tester,
      PartychuPerkAudience audience,
    ) async {
      tester.view.physicalSize = const Size(420, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PartychuPerkSection(
                controller: TextEditingController(),
                audience: audience,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// 굵게 그려진 줄인지 — 그냥 보이기만 해서는 안 되는 자리들이다.
    TextStyle styleOf(WidgetTester tester, String text) =>
        tester.widget<Text>(find.text(text)).style!;

    for (final audience in PartychuPerkAudience.values) {
      testWidgets('[$audience] 비용 두 줄이 굵게 그대로 보인다', (tester) async {
        await pumpSection(tester, audience);

        expect(find.text('🌟 파티츄 오픈 이벤트!'), findsOneWidget);

        expect(find.text(kPartychuOpenEventNoCharge), findsOneWidget);
        expect(
          styleOf(tester, kPartychuOpenEventNoCharge).fontWeight,
          FontWeight.bold,
        );

        // 둘째 줄은 강조 조각이 섞인 Text.rich라 textSpan으로 찾는다.
        final adLine = find.byWidgetPredicate(
          (w) =>
              w is Text &&
              w.textSpan?.toPlainText() == kPartychuOpenEventAdCoverage,
        );
        expect(adLine, findsOneWidget);
      });

      testWidgets('[$audience] 혜택을 권하는 줄이 굵게 있다', (tester) async {
        await pumpSection(tester, audience);

        expect(find.text(audience.pitch), findsOneWidget);
        expect(styleOf(tester, audience.pitch).fontWeight, FontWeight.bold);

        // 예시 설명은 굵지 않은 일반 본문이어야 한다 — 전부 굵으면 강조가
        // 아무 데도 걸리지 않는다.
        expect(find.text(audience.pitchDetail), findsOneWidget);
        final detail = styleOf(tester, audience.pitchDetail).fontWeight;
        expect(detail, anyOf(isNull, FontWeight.normal));
      });

      // 값을 아끼는 문구라 지나치기 쉬운 자리 — 사장님이 읽어야 할 단 하나가
      // "전액 부담합니다"다. 문장 전체를 굵게만 두면 여기가 묻힌다.
      testWidgets('[$audience] "전액 부담합니다"가 한 단계 더 강조된다', (tester) async {
        await pumpSection(tester, audience);

        final adLine = find.byWidgetPredicate(
          (w) =>
              w is Text &&
              w.textSpan?.toPlainText() == kPartychuOpenEventAdCoverage,
        );
        final span = tester.widget<Text>(adLine).textSpan! as TextSpan;
        expect(span.style?.fontWeight, FontWeight.bold);

        final parts = span.children!.cast<TextSpan>();
        final emphasis = parts.singleWhere(
          (s) => s.text == kPartychuOpenEventAdEmphasis,
          orElse: () => const TextSpan(),
        );
        expect(
          emphasis.style,
          isNotNull,
          reason: '"$kPartychuOpenEventAdEmphasis"가 따로 떼어져 있지 않다',
        );
        // 문장의 나머지(0xFF2D3748)와 확실히 다른 강조색·더 굵은 무게.
        expect(emphasis.style!.color, const Color(0xFFFF6FA0));
        expect(
          emphasis.style!.fontWeight!.value,
          greaterThan(FontWeight.bold.value),
        );
      });

      // 옛 카피가 한 줄이라도 남으면 "0원"과 "받지 않습니다"가 같은 화면에서
      // 섞여 읽힌다.
      testWidgets('[$audience] 0원·아낀 비용·기존 홍보비 카피는 남아 있지 않다', (tester) async {
        await pumpSection(tester, audience);

        for (final gone in [
          '0원입니다',
          '아낀 비용',
          '유료 광고를 직접 운영',
          '홍보 효과가 생깁니다',
          '기존 홍보비',
        ]) {
          expect(
            find.textContaining(gone),
            findsNothing,
            reason: '옛 카피 "$gone"이 남아 있다',
          );
        }
      });
    }

    // 매장/파티는 같은 필드를 쓰지만 읽는 사람이 다르다. 비용 두 줄은 정책이라
    // 같아야 하고, 권유 문구는 각자의 말이어야 한다.
    test('비용 두 줄은 유형과 무관하고, 권유 문구만 갈린다', () {
      expect(
        PartychuPerkAudience.store.pitch,
        isNot(PartychuPerkAudience.party.pitch),
      );
      expect(PartychuPerkAudience.store.pitch, contains('매장'));
      expect(PartychuPerkAudience.party.pitch, contains('파티'));
      // 개인 호스트에게 "매장"이라고 하면 무엇을 적어야 하는지 알 수 없다.
      expect(PartychuPerkAudience.party.pitch, isNot(contains('매장')));
      expect(PartychuPerkAudience.party.pitchDetail, isNot(contains('매장')));
    });
  });
}

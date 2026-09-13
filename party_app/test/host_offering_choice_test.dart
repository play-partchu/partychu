import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/host_offering.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/models/place_event_taxonomy.dart';
import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/widgets/host_offering_choice.dart';

/// 🎪 매장 이벤트 / 🎉 파티 — **개념과 등록 진입의 통합**.
///
/// 고정하는 것은 셋이다.
///   ① 두 개념의 정의가 한 곳에만 있고, 서로 절대 섞이지 않는다([HostOffering]).
///   ② 선택 화면이 "무엇을 하는 행사인지"가 아니라 **누가 여는지**로 고르게 한다.
///   ③ 고른 뒤 가는 곳은 각자의 기존 등록 시스템이다(합치지 않는다).
void main() {
  group('두 개념의 정본', () {
    test('이모지가 겹치지 않는다 — 한 글자로 갈린다', () {
      expect(HostOffering.placeEvent.emoji, '✨');
      expect(HostOffering.party.emoji, '🎉');
      expect(HostOffering.placeEvent.emoji, isNot(HostOffering.party.emoji));
    });

    test('이름과 한 줄 정의', () {
      expect(HostOffering.placeEvent.label, '매장 이벤트');
      expect(HostOffering.party.label, '파티');
      expect(HostOffering.placeEvent.meaning, contains('매장이 주체가 되어'));
      expect(HostOffering.party.meaning, contains('참가자를 모집하고 신청을 받아'));
    });

    test('게스트가 품는 질문이 서로 다르다', () {
      expect(HostOffering.placeEvent.guestQuestion, '이 매장에서 지금 뭐 하지?');
      expect(HostOffering.party.guestQuestion, '내가 참가할 모임이 뭐 있지?');
    });

    test('판단 기준은 콘텐츠 종류가 아니라 주체다', () {
      expect(HostOffering.criterionHeadline, contains('매장이 여는 행사인지'));
      expect(HostOffering.placeEvent.criterion, '매장에서 진행하는 이벤트·혜택');
      expect(HostOffering.party.criterion, '참가자를 모집하거나 티켓을 판매하는 행사');
    });

    // 매장 이벤트에는 한 달간 주류 할인·1+1처럼 그냥 방문하면 되는 것도,
    // 생일 이벤트처럼 사전 신청을 받는 것도 있다. "신청 없이"로 못박아 두면
    // 신청을 받는 매장 이벤트가 갈 곳을 잃고 파티로 잘못 등록된다.
    test('매장 이벤트를 "신청 없는 행사"로 정의하지 않는다', () {
      for (final copy in [
        HostOffering.placeEvent.criterion,
        HostOffering.placeEvent.meaning,
        HostOffering.placeEvent.registerDescription,
        HostOffering.criterionHeadline,
        // 파티 진입에서 건너오라고 묻는 줄 — 여기가 "신청 모집 없이"면
        // 사전 신청을 받는 매장 이벤트가 '아니오'로 떨어져 파티로 흘러간다.
        HostOffering.toPlaceEventPrompt,
      ]) {
        for (final banned in ['신청 없이', '모집 없이', '신청 모집 없이', '별도 참가 모집']) {
          expect(copy, isNot(contains(banned)), reason: '$copy ← "$banned"');
        }
      }
    });

    // 한 문장을 자리마다 다시 쓰면 그 순간 정의가 갈린다 — 카드 부제와
    // 건너오라는 물음은 같은 낱값 하나에서 나온다.
    test('한 줄 정의는 낱값 하나에서 나온다', () {
      expect(HostOffering.placeEvent.criterion, kPlaceEventCriterion);
      expect(HostOffering.toPlaceEventPrompt, startsWith(kPlaceEventCriterion));
    });

    test('서로를 가리키는 물음은 목적지가 정한다', () {
      // 매장 이벤트 폼에 걸리는 줄 — "모집할 거면 파티로".
      expect(HostOffering.party.crossPrompt, HostOffering.toPartyPrompt);
      // 파티 진입에 걸리는 줄 — "매장이 여는 행사면 매장 이벤트로".
      expect(
        HostOffering.placeEvent.crossPrompt,
        HostOffering.toPlaceEventPrompt,
      );
      expect(HostOffering.placeEvent.other, HostOffering.party);
      expect(HostOffering.party.other, HostOffering.placeEvent);
    });

    test('플레이스 쪽 표기가 전부 이 정본을 따른다 — 파티 이모지를 쓰지 않는다', () {
      // 탐색 축(🎪 이벤트 칸)
      expect(PlaceEventTaxonomy.categoryEmoji, HostOffering.placeEvent.emoji);
      expect(PlaceEventTaxonomy.categoryLabel, HostOffering.placeEvent.label);
      // 카드 배지(작은 자리 — 축약은 허용, 이모지는 그대로)
      expect(
        ListingConstants.placeThemeTagEmojis[ListingConstants.placeEventTag],
        HostOffering.placeEvent.emoji,
      );
      // 매장 이벤트 안의 갈래
      expect(PromotionType.event.emoji, HostOffering.placeEvent.emoji);
      for (final t in PromotionType.values) {
        expect(
          t.emoji,
          isNot(HostOffering.party.emoji),
          reason: '${t.key}: 매장 이벤트의 갈래가 파티로 읽히면 안 된다',
        );
      }
    });

    test('저장값은 하나도 건드리지 않는다 — 표기만 바꿨다', () {
      // themeTags에 들어가는 문자열과 프로모션 유형 키는 그대로다.
      expect(ListingConstants.placeEventTag, '이벤트');
      expect(PromotionType.event.key, 'event');
      expect(PlaceEventTaxonomy.kindsField, 'eventKinds');
    });
  });

  group('등록 선택 UI', () {
    Future<List<HostOffering>> pumpChoice(
      WidgetTester tester, {
      HostOffering? loading,
      Map<HostOffering, VoidCallback>? onHelp,
    }) async {
      final picked = <HostOffering>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HostOfferingChoice(
                loading: loading,
                onHelp: onHelp,
                onSelect: picked.add,
              ),
            ),
          ),
        ),
      );
      return picked;
    }

    testWidgets('두 카드가 한 자리에 있고, 무엇으로 고르는지 먼저 말한다', (tester) async {
      await pumpChoice(tester);

      expect(find.text(HostOffering.choiceTitle), findsOneWidget);
      expect(find.text(HostOffering.criterionHeadline), findsOneWidget);
      for (final kind in HostOffering.values) {
        expect(find.text(kind.label), findsOneWidget, reason: kind.name);
        expect(find.text(kind.criterion), findsOneWidget, reason: kind.name);
        expect(
          find.text(kind.registerDescription),
          findsOneWidget,
          reason: kind.name,
        );
      }
    });

    // 판단 기준은 카드 부제가 이미 말한다 — 같은 말을 예시로 한 번 더 하면
    // 3초 안에 고르라던 화면이 읽을거리가 된다. 예시 묶음이 되살아나면
    // 여기서 걸린다.
    testWidgets('예시 묶음을 덧붙이지 않는다', (tester) async {
      await pumpChoice(tester);
      expect(find.textContaining('예를 들어'), findsNothing);
      expect(find.textContaining('30명을 모집'), findsNothing);
      expect(find.textContaining('→ '), findsNothing);
    });

    testWidgets('카드를 누르면 그 종류가 그대로 호출부로 간다', (tester) async {
      final picked = await pumpChoice(tester);

      await tester.tap(find.text(HostOffering.placeEvent.label));
      await tester.pumpAndSettle();
      expect(picked, [HostOffering.placeEvent]);

      await tester.tap(find.text(HostOffering.party.label));
      await tester.pumpAndSettle();
      expect(picked, [HostOffering.placeEvent, HostOffering.party]);
    });

    testWidgets('확인 중인 카드는 다시 눌리지 않는다', (tester) async {
      final picked = await pumpChoice(tester, loading: HostOffering.party);

      // 로딩 중인 카드의 부제는 '확인 중...'으로 바뀐다.
      // (pumpAndSettle을 쓰지 않는다 — 진행 표시가 끝없이 돌아 멈추지 않는다.)
      expect(find.text('확인 중...'), findsOneWidget);
      await tester.tap(find.text(HostOffering.party.label));
      await tester.pump();
      expect(picked, isEmpty);

      // 다른 카드는 그대로 눌린다.
      await tester.tap(find.text(HostOffering.placeEvent.label));
      await tester.pump();
      expect(picked, [HostOffering.placeEvent]);
    });

    testWidgets("'?' 도움말은 준 카드에만 생기고, 등록으로 넘어가지 않는다", (tester) async {
      var helps = 0;
      final picked = await pumpChoice(
        tester,
        onHelp: {HostOffering.placeEvent: () => helps++},
      );

      expect(find.byIcon(Icons.question_mark_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.question_mark_rounded));
      await tester.pumpAndSettle();
      expect(helps, 1);
      expect(picked, isEmpty, reason: '도움말 탭이 카드 탭으로 새지 않는다');
    });
  });

  group('반대쪽으로 건너가는 안내', () {
    testWidgets('매장 이벤트 폼에는 파티로 가는 줄이 걸린다', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HostOfferingCrossLink(
              to: HostOffering.party,
              onTap: () => taps++,
            ),
          ),
        ),
      );

      expect(find.text(HostOffering.toPartyPrompt), findsOneWidget);
      expect(find.text('${HostOffering.party.display} 만들기'), findsOneWidget);
      await tester.tap(find.text('${HostOffering.party.display} 만들기'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('파티 진입에는 매장 이벤트로 가는 줄이 걸린다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HostOfferingCrossLink(
              to: HostOffering.placeEvent,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text(HostOffering.toPlaceEventPrompt), findsOneWidget);
      expect(
        find.text('${HostOffering.placeEvent.display} 만들기'),
        findsOneWidget,
      );
    });
  });
}

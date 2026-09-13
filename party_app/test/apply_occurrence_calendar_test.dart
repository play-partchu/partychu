// 신청 흐름의 참가 날짜 선택 — 세로 목록 대신 **월간 달력**.
//
// 매일 열리는 파티는 회차가 수십 개라 목록으로는 원하는 날짜를 찾기 어렵고,
// 화·목처럼 요일 주기도 보이지 않았다.
//
// 달력은 일정을 스스로 계산하지 않는다 — `PartySchedule.selectableOccurrences`가
// 만든 목록(실제로 존재하고, 아직 오지 않았고, 모집이 열려 있는 회차)에 든 날만
// 살아 있다. 그래서 여기 테스트도 그 목록을 주입해 UI만 검증한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/widgets/early_bird_price_line.dart';
import 'package:party_app/widgets/occurrence_picker.dart';
import 'package:party_app/widgets/partychu_ui.dart';

/// 예전 얼리버드 점은 5x5 원이었다 — 그런 상자가 하나도 없어야 한다.
Finder _tinyDots() => find.byWidgetPredicate((w) {
  if (w is! Container) return false;
  final c = w.constraints;
  return c != null && c.maxWidth == 5 && c.maxHeight == 5;
});

void main() {
  // 2026-08-21(금) 오전 10시 기준, 매일 20:00~23:00 열리는 파티.
  final now = DateTime(2026, 8, 21, 10, 0);

  PartyOccurrence occ(int month, int day, {DateTime? deadline}) =>
      PartyOccurrence(
        start: DateTime(2026, month, day, 20),
        end: DateTime(2026, month, day, 23),
        deadline: deadline ?? DateTime(2026, month, day, 18),
      );

  /// 오늘(8/21)부터 9/10까지 매일 열린다 — 8월·9월 두 달에 걸친다.
  List<PartyOccurrence> dailyOccurrences() => [
    for (var d = 21; d <= 31; d++) occ(8, d),
    for (var d = 1; d <= 10; d++) occ(9, d),
  ];

  /// 얼리버드는 8/24 회차부터 적용된다고 정본이 판정한 상황.
  bool earlyBirdFrom24(PartyOccurrence o) =>
      !o.start.isBefore(DateTime(2026, 8, 24));

  OccurrenceDaySummary summaryOf(PartyOccurrence o) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return OccurrenceDaySummary(
      title:
          '${o.start.month}월 ${o.start.day}일(${weekdays[o.start.weekday - 1]})',
      timeText: '오후 8:00',
      deadlineText: '모집 마감 오후 6:00',
      earlyBird: earlyBirdFrom24(o)
          ? (regular: 20000, discounted: 16000)
          : null,
    );
  }

  /// 시트를 띄우고, 시트가 돌려준 회차를 담아 두는 상자를 돌려준다.
  Future<List<PartyOccurrence?>> openSheet(
    WidgetTester tester, {
    required List<PartyOccurrence> occurrences,
    String? selectedId,
    bool canGoBack = false,
  }) async {
    // 시트 전체(달력 + 요약 + 버튼)가 한 화면에 들어오게 한다 — 기본
    // 800x600에서는 아래쪽 버튼이 잘려 탭이 빗나간다.
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final result = <PartyOccurrence?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result.add(
                  await showApplyOccurrenceCalendar(
                    context: context,
                    occurrences: occurrences,
                    selectedId: selectedId,
                    canGoBack: canGoBack,
                    summaryOf: summaryOf,
                    now: now,
                  ),
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    return result;
  }

  /// 달력 칸 하나 — 같은 숫자가 요약/버튼에 없도록 InkWell 안에서만 찾는다.
  Finder dayCell(String day) =>
      find.descendant(of: find.byType(InkWell), matching: find.text(day));

  group('달력이 열린다', () {
    testWidgets('오늘이 든 달(2026년 8월)로 열리고, 오늘은 테두리로 구분된다', (tester) async {
      await openSheet(tester, occurrences: dailyOccurrences());

      expect(find.text('2026년 8월'), findsOneWidget);
      expect(find.text('참가할 날짜를 선택해주세요'), findsOneWidget);

      // 오늘(21일) — 채움이 아니라 테두리. 선택(채움)과 구별된다.
      final todayBox = tester.widget<Container>(
        find
            .ancestor(of: dayCell('21'), matching: find.byType(Container))
            .first,
      );
      final deco = todayBox.decoration! as BoxDecoration;
      expect(deco.color, isNull, reason: '오늘은 채우지 않는다');
      expect(deco.border, isNotNull, reason: '오늘은 테두리로 표시한다');
    });

    testWidgets('신청 가능한 날만 눌린다 — 지난 날짜는 비활성', (tester) async {
      await openSheet(tester, occurrences: dailyOccurrences());

      // 8/20은 오늘 이전이라 selectableOccurrences에 없다 → 흐리게, 못 누름.
      final past = tester.widget<Text>(dayCell('20'));
      expect(past.style!.color, Colors.black26);

      final open = tester.widget<Text>(dayCell('25'));
      expect(open.style!.color, isNot(Colors.black26));
    });
  });

  group('★ 8월 → 9월 이동 → 날짜 선택 → 신청', () {
    testWidgets('다음 달로 넘어가 9월 회차를 고를 수 있다', (tester) async {
      final result = await openSheet(tester, occurrences: dailyOccurrences());

      await tester.tap(find.byTooltip('다음 달'));
      await tester.pumpAndSettle();
      expect(find.text('2026년 9월'), findsOneWidget);

      await tester.tap(dayCell('3'));
      await tester.pumpAndSettle();
      expect(find.text('9월 3일(목)'), findsOneWidget);

      await tester.tap(find.text('이 날짜로 신청하기'));
      await tester.pumpAndSettle();

      expect(result.single!.id, '2026-09-03');
    });

    testWidgets('이전 달로 되돌아올 수 있고, 첫 달에서는 이전 화살표가 막힌다', (tester) async {
      await openSheet(tester, occurrences: dailyOccurrences());

      // byTooltip은 Tooltip 위젯을 찾으므로 버튼 자체는 아이콘으로 집는다.
      VoidCallback? arrow(IconData icon) => tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, icon))
          .onPressed;

      // 회차가 있는 첫 달(8월)에서는 이전 달로 갈 수 없다.
      expect(arrow(Icons.chevron_left_rounded), isNull);

      await tester.tap(find.byTooltip('다음 달'));
      await tester.pumpAndSettle();
      expect(arrow(Icons.chevron_left_rounded), isNotNull);
      // 마지막 달(9월)에서는 다음 달로 갈 수 없다.
      expect(arrow(Icons.chevron_right_rounded), isNull);

      await tester.tap(find.byTooltip('이전 달'));
      await tester.pumpAndSettle();
      expect(find.text('2026년 8월'), findsOneWidget);
    });
  });

  group('선택한 날짜 요약', () {
    testWidgets('날짜를 고르면 시간·모집 마감이 뜨고, 핑크로 채워진다', (tester) async {
      await openSheet(tester, occurrences: dailyOccurrences());

      // 고르기 전에는 안내만.
      expect(find.text('8월 25일(화)'), findsNothing);
      expect(find.textContaining('날짜를 누르면'), findsOneWidget);

      await tester.tap(dayCell('25'));
      await tester.pumpAndSettle();

      expect(find.text('8월 25일(화)'), findsOneWidget);
      expect(find.text('오후 8:00 · 모집 마감 오후 6:00'), findsOneWidget);

      final box = tester.widget<Container>(
        find
            .ancestor(of: dayCell('25'), matching: find.byType(Container))
            .first,
      );
      expect(
        (box.decoration! as BoxDecoration).color,
        PartyChuColors.primary,
        reason: '고른 날은 파티츄 핑크로 채운다',
      );
    });

    testWidgets('얼리버드는 날짜를 고른 뒤에만, 정상가와 함께 뜬다', (tester) async {
      await openSheet(tester, occurrences: dailyOccurrences());

      // 고르기 전에는 금액 자체가 없다.
      expect(find.text('16,000원'), findsNothing);
      expect(find.text('얼리버드'), findsNothing);

      // 8/23은 얼리버드 적용 전 — 골라도 아무 말이 없다.
      await tester.tap(dayCell('23'));
      await tester.pumpAndSettle();
      expect(find.text('얼리버드'), findsNothing);
      expect(find.text('16,000원'), findsNothing);

      // 8/25는 적용 회차 — 정상가(취소선)와 할인가가 함께 뜬다.
      await tester.tap(dayCell('25'));
      await tester.pumpAndSettle();
      expect(find.byType(EarlyBirdPriceLine), findsOneWidget);
      expect(find.text('얼리버드'), findsOneWidget);
      expect(find.text('20,000원'), findsOneWidget);
      expect(find.text('16,000원'), findsOneWidget);
    });

    // ── 달력이 얼리버드를 미리 알려주지 않는다 ────────────────────────────
    //
    // 예전에는 얼리버드 날짜 아래에 분홍 점을 찍고 아래에 범례를 뒀다. 그러면
    // 고르기도 전에 할인 날짜가 전부 드러난다. 아래 두 테스트가 그 표시가
    // 되살아나는 것을 막는다.
    testWidgets('달력에는 얼리버드 점도 범례도 없다', (tester) async {
      await openSheet(tester, occurrences: dailyOccurrences());

      expect(find.byType(OccurrenceMonthCalendar), findsOneWidget);
      expect(find.text('얼리버드 할인이 적용되는 날'), findsNothing);
      // 예전 점은 5x5 원이었다 — 그 크기의 상자가 하나도 없어야 한다.
      expect(_tinyDots(), findsNothing);
    });

    testWidgets('다른 달로 넘어가도 사전 표시가 없고, 숫자 스타일이 같다', (tester) async {
      await openSheet(tester, occurrences: dailyOccurrences());

      // 9월은 회차 전체(9/1~9/10)가 얼리버드 구간이다 — 예전이라면 점이
      // 열 개 찍혔을 달이다.
      await tester.tap(find.byTooltip('다음 달'));
      await tester.pumpAndSettle();
      expect(find.text('2026년 9월'), findsOneWidget);
      expect(_tinyDots(), findsNothing);
      expect(find.text('얼리버드 할인이 적용되는 날'), findsNothing);

      // 얼리버드 날(9/2)과 일반 날의 숫자 스타일이 같아야 한다. 8월에 있는
      // 일반 회차(8/22)와 같은 열(토요일)끼리 비교해 요일 색 차이를 배제한다.
      final septStyle = tester.widget<Text>(dayCell('5')).style!; // 9/5 토
      await tester.tap(find.byTooltip('이전 달'));
      await tester.pumpAndSettle();
      final augStyle = tester.widget<Text>(dayCell('22')).style!; // 8/22 토
      expect(septStyle.color, augStyle.color);
      expect(septStyle.fontWeight, augStyle.fontWeight);
      expect(septStyle.fontSize, augStyle.fontSize);
    });
  });

  group('★ 다음 단계 → 뒤로 → 다른 날짜 재선택', () {
    testWidgets('←가 있으면 아무것도 돌려주지 않고 닫힌다(앞 단계로)', (tester) async {
      final result = await openSheet(
        tester,
        occurrences: dailyOccurrences(),
        canGoBack: true,
      );

      await tester.tap(find.byTooltip('참가할 일정 다시 고르기'));
      await tester.pumpAndSettle();

      expect(result.single, isNull, reason: '닫으면 회차가 바뀌면 안 된다');
    });

    testWidgets('되돌아오면 직전에 고른 날이 그대로 살아 있고, 다른 날로 바꿀 수 있다', (tester) async {
      // 다음 단계에서 ←로 돌아온 상황 — 호출부가 직전 선택을 넘겨준다.
      final result = await openSheet(
        tester,
        occurrences: dailyOccurrences(),
        selectedId: '2026-08-25',
      );

      // 그 날이 이미 골라진 채로 열린다(요약도 함께).
      expect(find.text('8월 25일(화)'), findsOneWidget);
      final box = tester.widget<Container>(
        find
            .ancestor(of: dayCell('25'), matching: find.byType(Container))
            .first,
      );
      expect((box.decoration! as BoxDecoration).color, PartyChuColors.primary);

      // 다른 날로 다시 고른다.
      await tester.tap(dayCell('28'));
      await tester.pumpAndSettle();
      expect(find.text('8월 28일(금)'), findsOneWidget);
      expect(find.text('8월 25일(화)'), findsNothing);

      await tester.tap(find.text('이 날짜로 신청하기'));
      await tester.pumpAndSettle();
      expect(result.single!.id, '2026-08-28');
    });
  });

  group('고르기 전에는 다음 단계로 갈 수 없다', () {
    testWidgets('날짜를 고르기 전 신청 버튼은 비활성', (tester) async {
      await openSheet(tester, occurrences: dailyOccurrences());

      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, '이 날짜로 신청하기'),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(dayCell('26'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, '이 날짜로 신청하기'),
            )
            .onPressed,
        isNotNull,
      );
    });
  });
}

// 플레이스 빠른 필터(날짜·시간·인원) 조작 중 **한 프레임도** 예외가 나면 안 된다.
//
// 증상: 시간을 고르거나 지우면 0.x초 동안 빨간 오류 화면이 깜빡였다.
// 원인: 아이콘 버튼이 `width: 38`을 고정한 채 AnimatedContainer로 애니메이션
// 하는데, 시간을 고른 순간 라벨('00–05')이 곧바로 붙는다. 애니메이션이 아직
// 폭을 38로 잡고 있는 동안 아이콘+간격+글자가 들어가지 못해
// `RenderFlex overflowed` 예외가 애니메이션 내내(160ms) 반복됐다.
// 고침: 고정폭 대신 `constraints: BoxConstraints(minWidth: 38)`.
//
// 애니메이션이 끝난 뒤가 아니라 **중간 프레임**을 하나씩 넘겨야 잡히는
// 예외라, 여기서는 pumpAndSettle에 의존하지 않고 프레임을 직접 돌린다.
//
// ── 지금 구조 ────────────────────────────────────────────────────────────
// 날짜·시간·인원은 이제 **버튼 하나**([QuickConditionGroupButton])로 묶여 있고,
// 누르면 셋이 함께 아래로 펼쳐진다. 그래서 여기서는 "그 버튼을 한 번 열고
// 세 줄을 오가며 고른다" — 고를 때마다 접히지 않는 것도 함께 확인한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/capacity_filter.dart';
import 'package:party_app/models/event_filter.dart';
import 'package:party_app/widgets/main/place_quick_time_bar.dart';

void main() {
  /// 조작 중 올라온 첫 예외를 잡아 둔다.
  FlutterErrorDetails? first;
  void Function(FlutterErrorDetails)? prev;

  setUp(() {
    first = null;
    prev = FlutterError.onError;
    FlutterError.onError = (d) => first ??= d;
  });

  tearDown(() => FlutterError.onError = prev);

  void assertClean(String step) {
    if (first == null) return;
    fail(
      '[$step] 예외가 났다\n'
      '${first!.exception}\n'
      '${first!.stack}',
    );
  }

  group('빨간 오류 화면이 한 프레임도 뜨지 않는다', () {
    late EventFilter filter;

    Future<void> pumpBar(WidgetTester tester) async {
      filter = EventFilter();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaceQuickTimeBar(filter: filter, onChanged: () {}),
          ),
        ),
      );
    }

    /// 버튼 폭 애니메이션(160ms)이 **끝날 때까지 프레임을 하나씩** 넘긴다.
    /// pumpAndSettle과 달리 중간 프레임의 레이아웃 예외를 확실히 통과시킨다.
    Future<void> settleFrames(WidgetTester tester) async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    /// 선택지가 열려 있는가 — 세 줄의 이름표 중 하나가 보이면 열린 것이다.
    bool isOpen() => find.text('시간').evaluate().isNotEmpty;

    /// 방문 조건 버튼을 눌러 **셋을 함께** 펼친다. 이미 열려 있으면 그대로 둔다
    /// (다시 누르면 접히기 때문).
    Future<void> openPane(WidgetTester tester) async {
      if (isOpen()) return;
      await tester.tap(find.byIcon(Icons.calendar_today_rounded));
      await settleFrames(tester);
    }

    /// 칩 하나를 누른다. '전체'는 시간 줄과 인원 줄에 하나씩 있으므로(각자
    /// "시간 무관" / "인원 무관"이라는 뜻이다) 어느 줄의 것인지 [last]로 가른다 —
    /// 트리 순서가 날짜 → 시간 → 인원이라 시간이 앞, 인원이 뒤다.
    Future<void> tapChip(
      WidgetTester tester,
      String label, {
      bool last = true,
    }) async {
      final chip = find.text(label);
      await tester.tap(last ? chip.last : chip.first);
      await settleFrames(tester);
    }

    /// 인원 스테퍼 시트 — 펼친 뒤 '직접'을 눌러 연다.
    Future<void> pickCapacity(WidgetTester tester, String people) async {
      await openPane(tester);
      await tapChip(tester, '직접');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), people);
      await tester.pumpAndSettle();
      await tester.tap(find.text('$people명 적용'));
      await settleFrames(tester);
    }

    testWidgets('셋이 함께 열리고, 하나를 골라도 접히지 않는다', (tester) async {
      await pumpBar(tester);
      await openPane(tester);
      // 날짜·시간·인원 세 줄이 한 번에 보인다.
      for (final section in ['날짜', '시간', '인원']) {
        expect(find.text(section), findsOneWidget, reason: section);
      }
      // 시간을 골라도 인원 줄이 사라지지 않는다 — 셋을 함께 보러 열었으므로
      // 하나 고를 때마다 접히면 다시 열어야 한다.
      await tapChip(tester, '24시간');
      expect(isOpen(), isTrue);
      expect(find.text('인원'), findsOneWidget);
      // 버튼을 다시 누르면 함께 접힌다.
      await tester.tap(find.byIcon(Icons.calendar_today_rounded));
      await settleFrames(tester);
      expect(isOpen(), isFalse);
      assertClean('열고 고르고 접기');
    });

    testWidgets('시간 선택 → 삭제', (tester) async {
      await pumpBar(tester);
      await openPane(tester);
      for (var i = 0; i < 3; i++) {
        await tapChip(tester, '심야 00~05시');
        expect(filter.hasTimeCondition, isTrue);
        await tapChip(tester, '전체', last: false);
        expect(filter.hasTimeCondition, isFalse);
      }
      assertClean('시간 선택 → 삭제');
    });

    testWidgets('시간 선택 → 다른 시간으로 변경', (tester) async {
      await pumpBar(tester);
      await openPane(tester);
      for (var i = 0; i < 3; i++) {
        await tapChip(tester, '심야 00~05시');
        await tapChip(tester, '24시간');
        expect(filter.hasTimeCondition, isTrue);
      }
      assertClean('시간 변경');
    });

    testWidgets('날짜 + 시간 선택 → 시간만 삭제', (tester) async {
      await pumpBar(tester);
      await openPane(tester);
      // 날짜를 걸어 둔 채로 시간만 따로 걸었다 지운다(칩 이름은 '오늘(월)'처럼
      // 요일이 붙으므로 정본 표기를 그대로 쓴다).
      await tapChip(tester, EventFilter.dayLabel(DateTime.now()));
      expect(filter.visitDates, isNotEmpty);
      await tapChip(tester, '24시간');
      await tapChip(tester, '전체', last: false);

      expect(filter.hasTimeCondition, isFalse);
      // 날짜는 그대로 — 셋은 서로 독립이다.
      expect(filter.visitDates, isNotEmpty);
      assertClean('날짜 + 시간 → 시간만 삭제');
    });

    testWidgets('날짜 + 시간 + 인원 선택 → 시간만 삭제', (tester) async {
      await pumpBar(tester);
      // 인원은 구간에 없는 숫자라 스테퍼 시트에서 직접 적어 고른다.
      await pickCapacity(tester, '8');
      expect(filter.minCapacity, 8);
      // 구간에 없는 인원은 '직접' 칩이 그 값을 그대로 말한다.
      expect(find.text(CapacityFilter.label(8)), findsOneWidget);

      await tapChip(tester, '24시간');
      await tapChip(tester, '전체', last: false);

      // 시간만 빠지고 인원은 그대로 — 결과 조건이 바뀌지 않았다.
      expect(filter.hasTimeCondition, isFalse);
      expect(filter.minCapacity, 8);
      assertClean('날짜 + 시간 + 인원 → 시간만 삭제');
    });

    testWidgets('시간 필터 전체 초기화를 반복해도 깨끗하다', (tester) async {
      await pumpBar(tester);
      await openPane(tester);
      for (var i = 0; i < 5; i++) {
        await tapChip(tester, i.isEven ? '24시간' : '심야 00~05시');
        await tapChip(tester, '전체', last: false);
      }
      expect(filter.hasTimeCondition, isFalse);
      assertClean('전체 초기화 반복');
    });

    testWidgets('인원 구간 칩 → 해제도 같은 줄에서 끝난다', (tester) async {
      await pumpBar(tester);
      await openPane(tester);
      for (final preset in CapacityFilter.presets) {
        await tapChip(tester, preset.label);
        expect(filter.minCapacity, preset.people, reason: preset.label);
      }
      // '전체'는 시간 줄에도 있으므로 인원 줄의 것(마지막)을 누른다.
      await tapChip(tester, '전체');
      expect(filter.minCapacity, isNull);
      assertClean('인원 구간 → 해제');
    });

    testWidgets('인원 직접 입력 → 해제도 같은 경로다(라벨이 붙었다 사라진다)', (tester) async {
      await pumpBar(tester);
      for (var i = 0; i < 3; i++) {
        // 세 자리 인원 — 칩 라벨이 가장 길어지는 경우다(폭 애니메이션 중
        // overflow가 나기 가장 쉬운 조건).
        await pickCapacity(tester, '120');
        expect(filter.minCapacity, 120);

        // 값을 고른 뒤에는 그 칩이 '직접'이 아니라 고른 인원을 말한다.
        await tapChip(tester, CapacityFilter.label(120));
        await tester.pumpAndSettle();
        await tester.tap(find.text('인원 무관'));
        await settleFrames(tester);
      }
      expect(filter.minCapacity, isNull);
      assertClean('인원 직접 입력 → 해제');
    });
  });
}

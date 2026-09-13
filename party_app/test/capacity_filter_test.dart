// 인원(최대 수용 인원) 필터.
//
// 정본은 [CapacityFilter] 하나이고 플레이스(events)·장소대여(places) 두 탭이
// 같은 함수를 쓴다. 수용 인원 필드도 새로 만들지 않고 장소대여 등록 화면이
// 이미 집계해 저장하는 `capacityMax`를 그대로 읽는다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/capacity_filter.dart';
import 'package:party_app/models/event_filter.dart';
import 'package:party_app/models/place_filter.dart';
import 'package:party_app/widgets/main/capacity_picker_sheet.dart';
import 'package:party_app/widgets/main/quick_filter_icon_button.dart';

void main() {
  /// [capacityMax]가 null이면 그 필드가 **아예 없는** 문서 — 플레이스(events)와
  /// 인원을 적지 않은 장소대여 문서가 이 모양이다.
  Map<String, dynamic> place(int? capacityMax) => {
    'name': '테스트 장소',
    'capacityMax': ?capacityMax,
  };

  group('★ 요청하신 예시 — 8명 선택', () {
    test('최대 5명인 곳은 제외된다', () {
      expect(CapacityFilter.matches(place(5), 8), isFalse);
    });

    test('최대 10명·20명인 곳은 표시된다', () {
      expect(CapacityFilter.matches(place(10), 8), isTrue);
      expect(CapacityFilter.matches(place(20), 8), isTrue);
    });

    test('경계 — 최대 8명은 포함된다(>=)', () {
      expect(CapacityFilter.matches(place(8), 8), isTrue);
      expect(CapacityFilter.matches(place(7), 8), isFalse);
    });
  });

  group('인원 값이 없는 장소는 숨기지 않는다', () {
    test('capacityMax가 없는 문서는 걸러지지 않는다', () {
      // 플레이스(events)는 등록 화면이 인원을 묻지 않아 이 필드가 아예 없다.
      expect(CapacityFilter.matches(place(null), 8), isTrue);
    });

    test('capacityMax가 0인 문서도 걸러지지 않는다 — 0은 "0명"이 아니라 "모름"', () {
      // 장소대여는 룸에 인원을 적지 않으면 집계값이 0으로 저장된다.
      expect(CapacityFilter.matches(place(0), 20), isTrue);
    });

    test('조건을 걸지 않으면(null) 모두 통과', () {
      for (final c in [null, 0, 5, 100]) {
        expect(CapacityFilter.matches(place(c), null), isTrue);
      }
    });
  });

  group('수용 인원을 읽는 순서는 목록 카드와 같다', () {
    test('capacityMax → capacity → maxCapacity 순으로 읽는다', () {
      expect(CapacityFilter.capacityOf({'capacityMax': 30}), 30);
      expect(CapacityFilter.capacityOf({'capacity': 12}), 12);
      expect(CapacityFilter.capacityOf({'maxCapacity': 7}), 7);
      // 새 필드가 있으면 구 필드보다 앞선다.
      expect(
        CapacityFilter.capacityOf({'capacityMax': 30, 'maxCapacity': 7}),
        30,
      );
      expect(CapacityFilter.capacityOf({}), 0);
    });

    test('구 스키마(maxCapacity)만 있는 장소도 정확히 걸러진다', () {
      expect(CapacityFilter.matches({'maxCapacity': 4}, 8), isFalse);
      expect(CapacityFilter.matches({'maxCapacity': 12}, 8), isTrue);
    });
  });

  group('표기', () {
    test('어떤 숫자든 같은 방식으로 적는다', () {
      expect(CapacityFilter.label(1), '1명');
      expect(CapacityFilter.label(7), '7명');
      expect(CapacityFilter.label(20), '20명');
      expect(CapacityFilter.label(27), '27명');
    });
  });

  group('입력 다듬기', () {
    test('범위를 벗어나면 끝값으로 당긴다', () {
      expect(CapacityFilter.clamp(0), CapacityFilter.minPeople);
      expect(CapacityFilter.clamp(-5), CapacityFilter.minPeople);
      expect(CapacityFilter.clamp(7), 7);
      expect(CapacityFilter.clamp(99999), CapacityFilter.maxPeople);
    });

    test('0·음수·빈 값·글자는 인원이 아니다', () {
      for (final raw in ['', ' ', '0', '-3', 'abc', '1.5']) {
        expect(CapacityFilter.parse(raw), isNull, reason: raw);
      }
    });

    test('숫자는 그대로, 상한을 넘으면 상한으로', () {
      expect(CapacityFilter.parse('1'), 1);
      expect(CapacityFilter.parse('7'), 7);
      expect(CapacityFilter.parse(' 13 '), 13);
      expect(CapacityFilter.parse('27'), 27);
      expect(CapacityFilter.parse('99999'), CapacityFilter.maxPeople);
    });

    test('상한은 실제 데이터보다 넉넉하다', () {
      // 판정이 `수용 인원 >= 고른 인원`이라 상한이 낮으면 대형 공간을 찾는
      // 사람이 막힌다.
      expect(CapacityFilter.maxPeople, greaterThanOrEqualTo(500));
    });
  });

  group('두 탭이 같은 조건을 갖는다', () {
    // MapEntry는 ==를 재정의하지 않아 contains()가 identity로 비교한다 —
    // 키/값으로 직접 본다.
    bool hasChip(List<MapEntry<String, String>> entries, String label) =>
        entries.any((e) => e.key == 'minCapacity' && e.value == label);

    test('플레이스 — 인원만 골라도 필터가 걸린 상태다', () {
      final f = EventFilter();
      expect(f.isActive, isFalse);
      f.minCapacity = 8;
      expect(f.isActive, isTrue);
      expect(hasChip(f.selectedEntries, '👥 8명'), isTrue);
      expect(f.copy().minCapacity, 8);
      f.removeValue('minCapacity', '👥 8명');
      expect(f.minCapacity, isNull);
      expect(f.isActive, isFalse);
    });

    test('장소대여 — 같은 방식으로 걸리고 풀린다', () {
      final f = PlaceFilter();
      expect(f.isActive, isFalse);
      f.minCapacity = 20;
      expect(f.isActive, isTrue);
      expect(hasChip(f.selectedEntries, '👥 20명'), isTrue);
      expect(f.copy().minCapacity, 20);
      f.removeValue('minCapacity', '👥 20명');
      expect(f.minCapacity, isNull);
    });

    test('날짜·시간과 함께 걸어도 서로를 지우지 않는다 (AND로 남는다)', () {
      final f = EventFilter(
        visitDate: DateTime(2026, 8, 25),
        startTime: const TimeOfDay(hour: 20, minute: 0),
        endTime: const TimeOfDay(hour: 23, minute: 0),
        minCapacity: 8,
      );
      expect(f.visitDates, isNotEmpty);
      expect(f.hasTimeRange, isTrue);
      expect(f.minCapacity, 8);

      // 인원만 풀어도 날짜·시간은 그대로.
      f.removeValue('minCapacity', '👥 8명');
      expect(f.minCapacity, isNull);
      expect(f.visitDates, isNotEmpty);
      expect(f.hasTimeRange, isTrue);

      // 반대로 시간만 풀어도 인원은 그대로.
      f.minCapacity = 10;
      f.removeValue('visitTime', '');
      expect(f.hasTimeCondition, isFalse);
      expect(f.minCapacity, 10);
    });

    test('장소대여도 날짜/시간과 독립이다', () {
      final f = PlaceFilter(
        useDate: DateTime(2026, 8, 25),
        startTime: const TimeOfDay(hour: 20, minute: 0),
        endTime: const TimeOfDay(hour: 23, minute: 0),
        minCapacity: 8,
      );
      f.removeValue('minCapacity', '👥 8명');
      expect(f.minCapacity, isNull);
      expect(f.useDate, isNotNull);
      expect(f.hasTimeRange, isTrue);
    });
  });

  group('버튼 표기', () {
    testWidgets('미선택이면 아이콘만, 고르면 인원이 적힌다', (tester) async {
      Future<void> pump(int? value) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: QuickFilterIconButton(
                icon: Icons.people_alt_rounded,
                label: value == null ? null : CapacityFilter.label(value),
                active: value != null,
                onTap: () {},
              ),
            ),
          ),
        );
      }

      await pump(null);
      expect(find.byIcon(Icons.people_alt_rounded), findsOneWidget);
      expect(find.textContaining('명'), findsNothing);

      await pump(5);
      expect(find.byIcon(Icons.people_alt_rounded), findsOneWidget);
      expect(find.text('5명'), findsOneWidget);
    });
  });

  group('선택 시트 — −/숫자/+ 스테퍼', () {
    /// 시트를 띄우고, 시트가 돌려준 값을 담을 상자를 준다.
    Future<List<int?>> open(WidgetTester tester, {int? initial}) async {
      final result = <int?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async => result.add(
                  await showCapacityPickerSheet(context, selected: initial),
                ),
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

    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pumpAndSettle();
    }

    Future<void> apply(WidgetTester tester) async {
      await tester.tap(find.textContaining('적용'));
      await tester.pumpAndSettle();
    }

    testWidgets('★ 고정 버튼에 없던 숫자도 직접 넣어 고를 수 있다', (tester) async {
      for (final n in [1, 7, 13, 27]) {
        final result = await open(tester);
        await type(tester, '$n');
        await apply(tester);
        expect(result.single, n, reason: '$n명');
      }
    });

    testWidgets('★ 시트에서 고른 숫자가 그대로 필터가 된다', (tester) async {
      // 시트가 돌려준 값을 필터에 넣고, 그 값으로 실제 장소를 걸러 본다.
      for (final n in [1, 7, 13, 27]) {
        final result = await open(tester);
        await type(tester, '$n');
        await apply(tester);

        final filter = EventFilter()..minCapacity = result.single;
        expect(filter.minCapacity, n);
        expect(
          filter.selectedEntries.any(
            (e) => e.key == 'minCapacity' && e.value == '👥 $n명',
          ),
          isTrue,
        );

        // 수용 인원 >= 고른 인원인 곳만 남는다.
        // (n이 1이면 한 칸 아래가 0인데, 0은 "0명 수용"이 아니라 "모름"이라
        //  일부러 통과시키는 값이므로 이 비교에서 뺀다.)
        if (n - 1 >= CapacityFilter.minPeople) {
          expect(
            CapacityFilter.matches(place(n - 1), filter.minCapacity),
            isFalse,
            reason: '$n명인데 ${n - 1}명짜리가 남았다',
          );
        }
        expect(CapacityFilter.matches(place(n), filter.minCapacity), isTrue);
        expect(
          CapacityFilter.matches(place(n + 50), filter.minCapacity),
          isTrue,
        );
        // 인원 정보가 없는 곳은 여전히 숨기지 않는다.
        expect(CapacityFilter.matches(place(null), filter.minCapacity), isTrue);
      }
    });

    testWidgets('+ / − 로 한 칸씩 움직인다', (tester) async {
      final result = await open(tester, initial: 7);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.remove_rounded));
      await tester.pumpAndSettle();
      await apply(tester);
      expect(result.single, 8);
    });

    testWidgets('최소 1명 아래로는 내려가지 않는다', (tester) async {
      final result = await open(tester, initial: 1);
      // − 는 비활성이라 눌러도 값이 그대로다.
      await tester.tap(find.byIcon(Icons.remove_rounded));
      await tester.pumpAndSettle();
      await apply(tester);
      expect(result.single, CapacityFilter.minPeople);
    });

    testWidgets('길게 눌러도 끝값을 넘지 않고 타이머가 남지 않는다', (tester) async {
      final result = await open(tester, initial: 3);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.remove_rounded)),
      );
      // 길게 누른 채로 충분히 오래 — 1명에서 멈춰야 한다.
      await tester.pump(const Duration(milliseconds: 600));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      await apply(tester);
      expect(result.single, CapacityFilter.minPeople);
    });

    testWidgets('0·빈 값이면 적용할 수 없다', (tester) async {
      await open(tester, initial: 5);

      await type(tester, '0');
      expect(
        tester
            .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '적용'))
            .onPressed,
        isNull,
      );
      expect(find.text('1명 이상 숫자로 적어주세요.'), findsOneWidget);

      await type(tester, '');
      expect(
        tester
            .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '적용'))
            .onPressed,
        isNull,
      );

      // 유효한 값을 넣으면 다시 눌린다.
      await type(tester, '9');
      expect(find.text('9명 적용'), findsOneWidget);
    });

    testWidgets('숫자만 입력된다 — 글자·기호는 걸러진다', (tester) async {
      await open(tester);
      await type(tester, 'a1b2-c');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '12',
      );
    });

    testWidgets('"인원 무관"을 고르면 조건이 풀린다(null)', (tester) async {
      final result = await open(tester, initial: 8);
      await tester.tap(find.text('인원 무관'));
      await tester.pumpAndSettle();
      expect(result.single, isNull);
    });

    testWidgets('그냥 닫으면 기존 값이 그대로 남는다', (tester) async {
      final result = await open(tester, initial: 8);
      await type(tester, '30');
      Navigator.of(tester.element(find.byType(TextField))).pop();
      await tester.pumpAndSettle();
      expect(result.single, 8, reason: '적용하지 않고 닫으면 바뀌면 안 된다');
    });

    testWidgets('인원 정보가 없는 곳을 함께 보여준다는 안내가 있다', (tester) async {
      await open(tester);
      expect(find.text('인원 정보가 없는 곳은 숨기지 않고 함께 보여드려요.'), findsOneWidget);
    });
  });
}

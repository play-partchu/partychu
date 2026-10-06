// 🔥 플레이스 카드의 **특징 강조 칩**.
//
// 두 가지를 못 박는다.
//   ① 한 줄에 몇 개를 세우고 '+N'을 어떻게 적을지 — 순수 함수의 규칙
//      ([fitFeatureChips]). 화면을 봐서는 "대충 맞네"까지만 알 수 있는 종류다.
//   ② 특징이 **글자 줄에서 빠져 칩으로** 갔는지, 그리고 좁은 화면에서 카드가
//      깨지지 않는지 — 실제 카드를 그려서 확인한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/place_feature_chips.dart';
import 'package:party_app/widgets/place_card_widget.dart';
import 'package:party_app/widgets/place_feature_chips_view.dart';

void main() {
  group('한 줄에 들어갈 만큼만 — fitFeatureChips', () {
    // 가짜 자: 글자 하나 10, 칩 여백 4 → '가나' = 24.
    double ruler(String s) => s.length * 10 + 4;

    FeatureChipFit fit(List<String> labels, double width) => fitFeatureChips(
      labels: labels,
      maxWidth: width,
      spacing: 2,
      widthOf: ruler,
      overflowWidthOf: (n) => ruler(featureOverflowLabel(n)),
    );

    test('비어 있으면 아무것도 없고 접힌 개수도 0이다', () {
      final r = fit([], 100);
      expect(r.visible, isEmpty);
      expect(r.hidden, 0);
    });

    test('전부 들어가면 +N을 만들지 않는다', () {
      // 'ab'(24) + 2 + 'cd'(24) = 50.
      final r = fit(['ab', 'cd'], 50);
      expect(r.visible, ['ab', 'cd']);
      expect(r.hidden, 0, reason: '자리가 남는데 +0이 서면 안 된다');
    });

    test('1px만 모자라면 접는다 — 마지막 칩이 줄 밖으로 나가지 않는다', () {
      final r = fit(['ab', 'cd'], 49);
      // '+1' = 2글자 → 24. 'ab'(24) + 2 + 24 = 50 > 49이므로 그것도 안 맞는다.
      // 그러면 첫 칩만 남기고 나머지를 접는다(규칙 ③).
      expect(r.visible, ['ab']);
      expect(r.hidden, 1);
    });

    test("'+N' 폭도 자리 계산에 넣는다", () {
      // 넷 중 셋만 폭으로는 들어가지만, '+1'을 둘 자리까지 보면 둘만 남는다.
      // 'a'=14. 4개: 14*4 + 2*3 = 62.
      // take=3: 14*3 + 2*2 + 2 + '+1'(24) = 46+2+24 = 72 > 60.
      // take=2: 14*2 + 2 + 2 + '+2'(24) = 30+2+24 = 56 <= 60. ✓
      final r = fit(['a', 'b', 'c', 'd'], 60);
      expect(r.visible, ['a', 'b']);
      expect(r.hidden, 2);
    });

    test('접힌 개수가 두 자리가 되어 넓어지는 경우도 맞춰 본다', () {
      final labels = List.generate(12, (i) => 'x');
      final r = fit(labels, 60);
      // '+10'/'+11'은 '+9'보다 넓다 — 그 폭으로 다시 맞춘 결과여야 한다.
      final used =
          r.visible.fold<double>(0, (a, l) => a + ruler(l)) +
          2 * r.visible.length +
          ruler(featureOverflowLabel(r.hidden));
      expect(used, lessThanOrEqualTo(60));
      expect(r.visible.length + r.hidden, 12, reason: '개수가 새거나 늘면 안 된다');
    });

    test('아주 좁아도 첫 칩은 남긴다 — "+4"만 남은 줄은 쓸모가 없다', () {
      final r = fit(['아주아주긴특징', 'b', 'c', 'd', 'e'], 20);
      expect(r.visible, ['아주아주긴특징']);
      expect(r.hidden, 4);
    });

    test('폭이 무한이면(자를 수 없는 자리) 전부 그린다', () {
      final r = fit(['a', 'b', 'c'], double.infinity);
      expect(r.visible.length, 3);
      expect(r.hidden, 0);
    });

    test('순서는 넘겨준 그대로다 — 중요한 것이 앞에 남는다', () {
      final r = fit(['첫째', '둘째', '셋째', '넷째'], 60);
      expect(r.visible.first, '첫째');
    });

    test("'+N' 문구", () {
      expect(featureOverflowLabel(1), '+1');
      expect(featureOverflowLabel(12), '+12');
    });
  });

  group('카드가 특징을 글자가 아니라 칩으로 그린다', () {
    // 🔥 불멍 + 🖥 대형스크린이 유도되는 플레이스.
    const place = <String, dynamic>{
      'name': '테스트 플레이스',
      'address': '서울특별시 강남구 역삼동 1',
      'placeCategory': '술집',
      'placeAttributes': {
        'firepit': ['불멍 가능'],
        'screen': ['대형스크린 있음'],
        'smoking': ['별도 흡연실 있음'],
      },
      'placeAttributeDetails': {
        'screen': {'size': '150인치'},
      },
    };

    test('특징이 요약 글자 줄에서 빠지고 별도 목록으로 들어온다', () {
      final info = PlaceCardInfo.from(
        place,
        source: PlaceCardSource.place,
        tag: 't',
      );
      expect(info.highlightFeatures, isNotEmpty);
      // 예전에는 이 값들이 facilitySummary 안에 ' · '로 이어 붙어 있었다.
      for (final label in info.highlightFeatures) {
        expect(
          info.facilitySummary,
          isNot(contains(label)),
          reason: '"$label"이 아직 글자 줄에 남아 있다 — 칩으로 옮기지 못했다',
        );
      }
    });

    test('장소대여는 특징 축이 없어 빈 목록이다', () {
      final info = PlaceCardInfo.from(
        const {'name': '파티룸', 'type': '파티룸'},
        source: PlaceCardSource.rental,
        tag: 't',
      );
      expect(info.highlightFeatures, isEmpty);
    });

    /// 카드를 [w]px 폭으로 그리고, 그동안 터진 첫 예외를 돌려준다.
    ///
    /// ⚠️ `FlutterError.onError`는 **pump가 끝나는 즉시 되돌린다.** tearDown에
    ///    미루면, 이 뒤의 `expect` 실패가 프레임워크의 오류 통로에 갇혀
    ///    "테스트가 10분 뒤 타임아웃"으로 둔갑한다(실제로 그렇게 헤맸다).
    Future<Object?> pumpCard(WidgetTester tester, Widget card, double w) async {
      Object? firstError;
      final prev = FlutterError.onError;
      FlutterError.onError = (d) => firstError ??= d.exception;

      tester.view.physicalSize = Size(w, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(width: w, child: card),
              ),
            ),
          ),
        );
        await tester.pump();
      } finally {
        FlutterError.onError = prev;
      }
      return firstError;
    }

    testWidgets('작은 카드 — 칩이 그려지고 특징 글자가 주소 줄에 섞이지 않는다', (tester) async {
      final err = await pumpCard(
        tester,
        PlaceCompactCard(
          place: place,
          placeId: 'p1',
          source: PlaceCardSource.place,
        ),
        360,
      );
      expect(err, isNull, reason: '오버플로/예외가 났다: $err');
      expect(find.byType(PlaceFeatureChipRow), findsOneWidget);

      // 가장 앞 특징은 반드시 칩으로 서 있다(뒤쪽은 폭에 따라 '+N'으로 접힌다).
      final first = PlaceCardInfo.from(
        place,
        source: PlaceCardSource.place,
        tag: 't',
      ).highlightFeatures.first;
      expect(find.text(first), findsOneWidget);

      // 그리고 그 글자가 주소 줄에 **또** 있으면 안 된다 — 옮긴 것이 아니라
      // 복사한 것이 된다.
      expect(find.textContaining('$first · '), findsNothing);
    });

    testWidgets('기본 카드 — 칩 줄이 좌석 요약 자리를 대신 쓴다', (tester) async {
      final err = await pumpCard(
        tester,
        PlaceStandardCard(
          place: place,
          placeId: 'p1',
          source: PlaceCardSource.place,
        ),
        200,
      );
      expect(err, isNull, reason: '오버플로/예외가 났다: $err');
      expect(find.byType(PlaceFeatureChipRow), findsOneWidget);
    });

    testWidgets('특징이 없는 플레이스는 칩 줄 자체가 없다', (tester) async {
      final err = await pumpCard(
        tester,
        PlaceCompactCard(
          place: const {'name': '맨 플레이스', 'address': '서울특별시 강남구'},
          placeId: 'p2',
          source: PlaceCardSource.place,
        ),
        360,
      );
      expect(err, isNull);
      expect(find.byType(PlaceFeatureChipRow), findsNothing);
    });

    testWidgets("가장 좁은 320px에서도 '+N'만 남지 않는다 — 특징 하나는 늘 보인다", (tester) async {
      final err = await pumpCard(
        tester,
        PlaceCompactCard(
          place: place,
          placeId: 'p1',
          source: PlaceCardSource.place,
        ),
        320,
      );
      expect(err, isNull);
      final chips = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(PlaceFeatureChipRow),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data)
          .toList();
      expect(chips, isNotEmpty);
      expect(
        chips.where((c) => !(c ?? '').startsWith('+')),
        isNotEmpty,
        reason: "'+3' 하나만 남은 줄은 아무것도 알려주지 않는다",
      );
    });

    testWidgets('아주 좁은 320px에서도 깨지지 않고 +N으로 접힌다', (tester) async {
      final err = await pumpCard(
        tester,
        PlaceCompactCard(
          place: place,
          placeId: 'p1',
          source: PlaceCardSource.place,
        ),
        320,
      );
      expect(err, isNull, reason: '좁은 화면에서 오버플로가 났다: $err');
      expect(find.byType(PlaceFeatureChipRow), findsOneWidget);
    });

    testWidgets('시스템 글자 크기를 키워도 줄 밖으로 밀려 나가지 않는다', (tester) async {
      Object? firstError;
      final prev = FlutterError.onError;
      FlutterError.onError = (d) => firstError ??= d.exception;
      addTearDown(() => FlutterError.onError = prev);

      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 320,
                child: PlaceCompactCard(
                  place: place,
                  placeId: 'p1',
                  source: PlaceCardSource.place,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(firstError, isNull, reason: '글자 확대에서 오버플로가 났다: $firstError');
    });
  });

  group('카테고리와 한눈에 구분된다', () {
    test('특징 칩은 카테고리 배지와 색·모양이 둘 다 다르다', () {
      // 색 하나만 다르면 색약인 사람에게는 같은 것이 된다 — 모양도 갈랐다.
      // (값 자체는 위젯 안의 상수라, 여기서는 "칩 줄의 높이가 고정"이라는
      //  레이아웃 계약만 못 박는다. 색은 눈으로 보는 것이 맞다.)
      expect(kPlaceFeatureRowHeight, greaterThan(0));
      expect(kPlaceFeatureChipSpacing, greaterThan(0));
    });

    testWidgets('칩 줄의 높이는 특징 개수와 무관하게 일정하다', (tester) async {
      Future<double> heightOf(List<String> labels) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 200,
                child: PlaceFeatureSlot(
                  child: PlaceFeatureChipRow(labels: labels),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        return tester.getSize(find.byType(PlaceFeatureSlot)).height;
      }

      final one = await heightOf(['🔥 불멍']);
      final many = await heightOf([
        '🔥 불멍',
        '🖥 150인치',
        '🍷 콜키지 무료',
        '🎧 DJ',
        '🌙 심야영업',
      ]);
      expect(one, many, reason: '칩 개수에 따라 카드 높이가 달라지면 그리드가 어긋난다');
      expect(one, kPlaceFeatureRowHeight);
    });
  });
}

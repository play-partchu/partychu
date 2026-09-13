// 지도 종류 필터 칩 — 하단 시트 머리줄로 옮긴 뒤의 동작 잠금.
//
// 자리와 개수 표시는 시트 머리줄로 옮기며 정해진 그대로이고, **선택 규칙만**
// 바뀌었다 — 전체에서 개별을 누르면 그 하나만 남고, 그다음부터 다중선택
// 토글이다(nextMapKindSelection). 마지막 하나는 여전히 해제되지 않는다.
//
// map_screen 자체는 네이버 지도·Firestore가 필요해 위젯 테스트로 띄울 수 없다 —
// 그래서 칩 줄만 따로 검증한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/map_listing.dart';
import 'package:party_app/widgets/map_kind_filter_bar.dart';
import 'package:party_app/widgets/partychu_ui.dart';

/// 시트 머리줄과 같은 모양으로 띄운다 — Expanded 안의 칩 줄 + 오른쪽 상세필터.
///
/// 돌려주는 [Tapped]에 onChanged로 올라온 값이 담긴다(탭은 pump 이후에
/// 일어나므로 값을 함수 반환값으로 받을 수 없다). 콜백이 오지 않았으면
/// [Tapped.value]는 null로 남는다 — '누른 것만 무시'를 그대로 확인할 수 있다.
Future<Tapped> pumpBar(
  WidgetTester tester, {
  required Set<MapListingKind> selected,
  Map<MapListingKind, int> counts = const {},
  double width = 400,
}) async {
  final tapped = Tapped();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: MapKindFilterBar(
                      selected: selected,
                      counts: counts,
                      padding: const EdgeInsets.only(right: 8),
                      onChanged: (next) => tapped.value = next,
                    ),
                  ),
                  const Icon(Icons.tune),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return tapped;
}

/// onChanged로 올라온 마지막 값. 콜백이 없었으면 null.
class Tapped {
  Set<MapListingKind>? value;
}

/// 칩의 배경색.
Color? chipFill(WidgetTester tester, String label) {
  final chip = tester.widget<Container>(
    find.ancestor(of: find.text(label), matching: find.byType(Container)).first,
  );
  return (chip.decoration as BoxDecoration).color;
}

/// 칩 테두리 색.
Color? chipBorder(WidgetTester tester, String label) {
  final chip = tester.widget<Container>(
    find.ancestor(of: find.text(label), matching: find.byType(Container)).first,
  );
  return (chip.decoration as BoxDecoration).border?.top.color;
}

/// 칩 이름의 글자색.
Color? labelColor(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label)).style?.color;

const all = {MapListingKind.party, MapListingKind.place, MapListingKind.rental};

void main() {
  group('칩 구성', () {
    testWidgets('전체·파티·플레이스·장소대여 네 칩이 한 줄에 나온다', (tester) async {
      await pumpBar(tester, selected: all);

      expect(find.text('전체'), findsOneWidget);
      expect(find.text('파티'), findsOneWidget);
      expect(find.text('플레이스'), findsOneWidget);
      expect(find.text('장소대여'), findsOneWidget);
      // 이모지는 라벨과 따로 그린다(크기를 따로 줄이기 위해).
      expect(find.text('🎉'), findsOneWidget);
      expect(find.text('📍'), findsOneWidget);
      expect(find.text('🏠'), findsOneWidget);
    });

    testWidgets('가로 스크롤이 없다 — 드래그해야 나오는 칩은 없다', (tester) async {
      await pumpBar(tester, selected: all);

      expect(find.byType(ListView), findsNothing);
      expect(find.byType(Scrollable), findsNothing);
    });

    // 좁은 폭에서도 **넘치지 않고 넷 다 보인다**가 이 변경의 핵심이다.
    // 위젯 테스트는 오버플로가 나면 그 자체로 실패하므로, 폭만 좁혀서 띄우고
    // 네 라벨이 모두 화면 안에 있는지 본다.
    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      testWidgets('${width.toInt()}px에서 네 칩이 모두 화면 안에 들어온다', (tester) async {
        await pumpBar(
          tester,
          selected: all,
          width: width,
          counts: const {
            MapListingKind.party: 5,
            MapListingKind.place: 1,
            MapListingKind.rental: 0,
          },
        );

        for (final label in ['전체', '파티', '플레이스', '장소대여']) {
          final finder = find.text(label);
          expect(finder, findsOneWidget, reason: '$label 칩이 없다');
          final rect = tester.getRect(finder);
          expect(rect.width, greaterThan(0), reason: '$label 이 잘렸다');
        }
      });
    }

    testWidgets('칩 폭은 이름 길이에 비례한다 — 짧은 칩이 자리를 낭비하지 않는다', (tester) async {
      await pumpBar(tester, selected: all, width: 390);

      double chipWidth(String label) => tester
          .getRect(
            find
                .ancestor(
                  of: find.text(label),
                  matching: find.byType(Container),
                )
                .first,
          )
          .width;

      // 4자('플레이스')는 2자('파티')보다 넓고, 이모지가 없는 '전체'가 가장 좁다.
      final total = chipWidth('전체');
      final party = chipWidth('파티');
      final place = chipWidth('플레이스');
      final rental = chipWidth('장소대여');

      expect(total, lessThan(party), reason: '이모지가 없는 전체가 더 좁아야 한다');
      expect(party, lessThan(place), reason: '2자가 4자보다 좁아야 한다');
      // 글자 수가 같은 두 칩은 같은 폭.
      expect((place - rental).abs(), lessThan(0.5));
    });

    // 폭을 똑같이 4등분하면 '전체'(2자)는 여백만 남고 '장소대여'(4자)만 글자가
    // 눌려, 같은 줄에서 칩마다 글자 크기가 달라 보인다. 내용 길이에 비례해
    // 나눠 주므로 **네 칩의 글자 크기가 같아야** 한다.
    for (final width in [320.0, 360.0, 390.0]) {
      testWidgets('${width.toInt()}px에서 네 칩의 글자 크기가 서로 같다', (tester) async {
        await pumpBar(
          tester,
          selected: all,
          width: width,
          counts: const {
            MapListingKind.party: 5,
            MapListingKind.place: 1,
            MapListingKind.rental: 0,
          },
        );

        // 렌더된 폭 ÷ 글자 수 = 글자 하나의 실제 폭. 축소가 걸려도 네 칩이
        // 같은 비율이어야 한다.
        double perChar(String label) =>
            tester.getRect(find.text(label)).width / label.length;

        final sizes = [
          for (final l in ['전체', '파티', '플레이스', '장소대여']) perChar(l),
        ];
        for (final s in sizes) {
          expect(
            (s - sizes.first).abs() / sizes.first,
            lessThan(0.12),
            reason: '칩마다 글자 크기가 다르다: $sizes',
          );
        }
      });
    }

    testWidgets('360px 이상에서는 축소 없이 원래 글자 크기로 나온다', (tester) async {
      await pumpBar(
        tester,
        selected: all,
        width: 360,
        counts: const {
          MapListingKind.party: 5,
          MapListingKind.place: 1,
          MapListingKind.rental: 0,
        },
      );

      // 테스트 폰트는 한 글자가 정확히 1em이라 폭으로 실제 글자 크기를 잰다.
      final perChar = tester.getRect(find.text('장소대여')).width / 4;
      expect(perChar, greaterThanOrEqualTo(11.9), reason: '축소가 걸렸다');
    });

    testWidgets('상세필터 버튼은 칩 줄 오른쪽에 그대로 남는다', (tester) async {
      await pumpBar(tester, selected: all);

      final barRight = tester.getBottomRight(find.byType(MapKindFilterBar)).dx;
      final iconLeft = tester.getTopLeft(find.byIcon(Icons.tune)).dx;
      expect(iconLeft, greaterThanOrEqualTo(barRight));
    });
  });

  group('개수 표시 — 사라진 제목이 들고 있던 숫자', () {
    testWidgets('종류별 개수가 칩에 붙고, 전체는 합계다', (tester) async {
      await pumpBar(
        tester,
        selected: all,
        counts: const {
          MapListingKind.party: 4,
          MapListingKind.place: 2,
          MapListingKind.rental: 1,
        },
      );

      expect(find.text('4'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('7'), findsOneWidget); // 전체
    });

    testWidgets('꺼 둔 종류에도 개수가 보인다 — 켤 이유가 보여야 한다', (tester) async {
      await pumpBar(
        tester,
        selected: const {MapListingKind.party},
        counts: const {
          MapListingKind.party: 4,
          MapListingKind.place: 2,
          MapListingKind.rental: 1,
        },
      );

      expect(find.text('2'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('개수를 넘기지 않으면 숫자를 그리지 않는다', (tester) async {
      await pumpBar(tester, selected: all);

      expect(find.text('0'), findsNothing);
      expect(find.text('3'), findsNothing);
    });
  });

  // 예전에는 종류마다 고유색(파티=핑크, 플레이스=보라, 장소대여=초록,
  // 전체=검정)이라 한 줄에 네 색이 서 있었다. 이제 색은 **선택 여부 하나만**
  // 말한다 — 종류는 이모지와 이름이 구분한다.
  group('색 — 네 칩이 모두 파티츄 핑크 한 벌을 쓴다', () {
    const labels = ['전체', '파티', '플레이스', '장소대여'];

    testWidgets('켜진 칩은 진한 핑크 배경 + 흰 글자', (tester) async {
      await pumpBar(tester, selected: all);

      for (final l in labels) {
        expect(chipFill(tester, l), PartyChuColors.primary, reason: l);
        expect(chipBorder(tester, l), PartyChuColors.primary, reason: l);
        expect(labelColor(tester, l), Colors.white, reason: l);
      }
    });

    testWidgets('꺼진 칩은 흰 배경 + 연한 핑크 테두리 + 핑크 글자', (tester) async {
      // 파티만 켜면 나머지 셋(전체 포함)이 꺼진 모습이 된다.
      await pumpBar(tester, selected: const {MapListingKind.party});

      for (final l in ['전체', '플레이스', '장소대여']) {
        expect(chipFill(tester, l), Colors.white, reason: l);
        expect(chipBorder(tester, l), PartyChuColors.border, reason: l);
        expect(labelColor(tester, l), PartyChuColors.primary, reason: l);
      }
    });

    testWidgets('종류별 고유색(보라·초록·검정)은 더 이상 쓰지 않는다', (tester) async {
      await pumpBar(tester, selected: all);

      // 지도 마커가 쓰는 종류별 색은 칩 어디에도 나오면 안 된다.
      for (final kind in MapListingKind.values) {
        for (final l in labels) {
          expect(chipFill(tester, l), isNot(kind.color), reason: '$l / $kind');
          expect(
            chipBorder(tester, l),
            isNot(kind.color),
            reason: '$l / $kind',
          );
        }
      }
      // '전체'가 쓰던 검정 계열도 사라졌다.
      expect(chipFill(tester, '전체'), isNot(const Color(0xFF3A2E39)));
    });

    testWidgets('카운트 글자색은 칩 글자색을 옅힌 같은 색이다', (tester) async {
      await pumpBar(
        tester,
        selected: const {MapListingKind.party},
        counts: const {
          MapListingKind.party: 5,
          MapListingKind.place: 1,
          MapListingKind.rental: 0,
        },
      );

      Color? countColor(String text) =>
          tester.widget<Text>(find.text(text)).style?.color;

      // 켜진 파티 칩(흰 글자) / 꺼진 플레이스 칩(핑크 글자).
      expect(countColor('5'), Colors.white.withValues(alpha: 0.7));
      expect(countColor('1'), PartyChuColors.primary.withValues(alpha: 0.7));
    });
  });

  // 전체 상태에서 개별 칩을 누르면 **그 하나만** 남는다. 예전에는 여기서도
  // 토글이라 누른 종류가 오히려 빠졌다 — "파티를 보고 싶다"는 뜻과 정반대였다.
  group('선택 로직 — 전체에서 누르면 단독, 그다음부터 다중선택', () {
    testWidgets('기본값은 전체 — 셋 다 켜져 있으면 전체에 불이 들어온다', (tester) async {
      await pumpBar(tester, selected: all);

      expect(chipFill(tester, '전체'), PartyChuColors.primary);
    });

    // 세 종류 모두 같은 규칙을 받는다.
    for (final (label, kind) in const [
      ('파티', MapListingKind.party),
      ('플레이스', MapListingKind.place),
      ('장소대여', MapListingKind.rental),
    ]) {
      testWidgets('전체에서 $label 을 누르면 $label 만 남는다', (tester) async {
        final r = await pumpBar(tester, selected: all);
        await tester.tap(find.text(label));
        await tester.pump();

        expect(r.value, {kind});
      });
    }

    testWidgets('단독 → 복수선택: 꺼져 있던 종류를 누르면 더해진다', (tester) async {
      final r = await pumpBar(tester, selected: const {MapListingKind.party});
      await tester.tap(find.text('플레이스'));
      await tester.pump();

      expect(r.value, {MapListingKind.party, MapListingKind.place});
    });

    testWidgets('복수 → 하나 해제: 켜져 있던 종류를 누르면 빠진다', (tester) async {
      final r = await pumpBar(
        tester,
        selected: const {MapListingKind.party, MapListingKind.place},
      );
      await tester.tap(find.text('파티'));
      await tester.pump();

      expect(r.value, {MapListingKind.place});
    });

    testWidgets('둘 켠 상태에서 나머지 하나를 누르면 셋이 되고, 그것이 곧 전체다', (tester) async {
      final r = await pumpBar(
        tester,
        selected: const {MapListingKind.party, MapListingKind.place},
      );
      await tester.tap(find.text('장소대여'));
      await tester.pump();

      expect(r.value, all);

      // 그 값을 그대로 다시 그리면 '전체' 칩에 불이 들어온다.
      await pumpBar(tester, selected: r.value!);
      expect(chipFill(tester, '전체'), PartyChuColors.primary);
    });

    testWidgets('마지막 하나는 해제되지 않는다 — 누른 것만 무시', (tester) async {
      final r = await pumpBar(tester, selected: const {MapListingKind.party});
      await tester.tap(find.text('파티'));
      await tester.pump();

      expect(r.value, isNull, reason: '콜백 자체가 오지 않아야 한다');
    });

    testWidgets('전체가 아닐 때 전체를 누르면 셋 다 켜진다', (tester) async {
      final r = await pumpBar(tester, selected: const {MapListingKind.party});
      await tester.tap(find.text('전체'));
      await tester.pump();

      expect(r.value, all);
    });

    testWidgets('이미 전체면 전체를 눌러도 아무 일이 없다', (tester) async {
      final r = await pumpBar(tester, selected: all);
      await tester.tap(find.text('전체'));
      await tester.pump();

      expect(r.value, isNull);
    });

    // 규칙만 따로 — 위젯을 띄우지 않고 상태 전이를 직접 확인한다.
    test('nextMapKindSelection: 전체 → 단독 → 복수 → 해제', () {
      var s = all;
      s = nextMapKindSelection(s, MapListingKind.party);
      expect(s, {MapListingKind.party});

      s = nextMapKindSelection(s, MapListingKind.place);
      expect(s, {MapListingKind.party, MapListingKind.place});

      s = nextMapKindSelection(s, MapListingKind.party);
      expect(s, {MapListingKind.place});

      // 마지막 하나 — 받은 집합을 그대로 돌려준다(호출부가 '변화 없음'으로 읽는다).
      final last = nextMapKindSelection(s, MapListingKind.place);
      expect(identical(last, s), isTrue);
    });
  });

  // 숫자는 **선택과 무관한 종류별 개수**다. 칩을 눌러도 숫자가 아니라 켜짐
  // 여부만 바뀐다 — 요청 예시의 '전체 6 → 파티 5만 활성 → 파티 5 + 플레이스 1'.
  group('선택이 바뀌어도 숫자는 종류별 개수 그대로', () {
    const counts = {
      MapListingKind.party: 5,
      MapListingKind.place: 1,
      MapListingKind.rental: 0,
    };

    testWidgets('전체 6 → 파티 단독 → 파티+플레이스', (tester) async {
      // pumpBar는 띄울 때마다 새 [Tapped]를 준다 — 부모가 선택을 적용해 다시
      // 그린 화면은 콜백도 새것이라, 그 화면의 탭은 그 화면 것으로 받는다.
      final atAll = await pumpBar(tester, selected: all, counts: counts);
      expect(find.text('6'), findsOneWidget); // 전체 = 합계

      await tester.tap(find.text('파티'));
      await tester.pump();
      expect(atAll.value, {MapListingKind.party});

      // 파티만 켠 화면 — 숫자는 그대로고, 켜진 칩만 파티다.
      final atParty = await pumpBar(
        tester,
        selected: atAll.value!,
        counts: counts,
      );
      expect(chipFill(tester, '파티'), PartyChuColors.primary);
      expect(chipFill(tester, '플레이스'), Colors.white);
      expect(chipFill(tester, '전체'), Colors.white);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);

      await tester.tap(find.text('플레이스'));
      await tester.pump();
      expect(atParty.value, {MapListingKind.party, MapListingKind.place});

      await pumpBar(tester, selected: atParty.value!, counts: counts);
      expect(chipFill(tester, '파티'), PartyChuColors.primary);
      expect(chipFill(tester, '플레이스'), PartyChuColors.primary);
      expect(chipFill(tester, '장소대여'), Colors.white);
      expect(chipFill(tester, '전체'), Colors.white);
      // 숫자는 선택과 무관하다 — 켠 뒤에도 종류별 개수 그대로.
      expect(find.text('5'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
    });
  });
}

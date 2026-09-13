import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/models/place_facility_options.dart';
import 'package:party_app/widgets/place_form/place_facility_options_section.dart';

const _seating = 'seatingTypes';
const _convenience = 'seatingConveniences';

PlaceFacilityOptions _withPicks(List<(String, String)> picks) {
  var options = PlaceFacilityOptions.empty();
  for (final (group, label) in picks) {
    options = options.toggle(group, label);
  }
  return options;
}

void main() {
  group('선택/해제', () {
    test('토글로 켜고 끈다', () {
      var o = PlaceFacilityOptions.empty();
      expect(o.isEmpty, isTrue);

      o = o.toggle(_seating, '개별룸');
      expect(o.isSelected(_seating, '개별룸'), isTrue);
      expect(o.isEmpty, isFalse);
      expect(o.selectedCount, 1);

      o = o.toggle(_seating, '개별룸');
      expect(o.isSelected(_seating, '개별룸'), isFalse);
      expect(o.isEmpty, isTrue);
    });

    test('선택을 해제하면 그 좌석의 인원 값도 함께 지워진다', () {
      var o = PlaceFacilityOptions.empty()
          .toggle(_seating, '개별룸')
          .withCapacity(_seating, '개별룸', 35);
      expect(o.capacityOf(_seating, '개별룸'), 35);

      o = o.toggle(_seating, '개별룸');
      expect(o.capacityOf(_seating, '개별룸'), isNull);
    });

    test('인원에 0이나 null을 넣으면 미입력으로 지운다', () {
      var o = PlaceFacilityOptions.empty()
          .toggle(_seating, '단체석')
          .withCapacity(_seating, '단체석', 80);
      expect(o.capacityOf(_seating, '단체석'), 80);

      o = o.withCapacity(_seating, '단체석', 0);
      expect(o.capacityOf(_seating, '단체석'), isNull);

      o = o
          .withCapacity(_seating, '단체석', 12)
          .withCapacity(_seating, '단체석', null);
      expect(o.capacityOf(_seating, '단체석'), isNull);
    });

    test('불변 — 원본은 그대로 남는다', () {
      final base = PlaceFacilityOptions.empty().toggle(_seating, '카운터석');
      final next = base.toggle(_seating, '단체석');
      expect(base.selectedCount, 1);
      expect(next.selectedCount, 2);
    });
  });

  group('요약(접힌 헤더·목록 카드)', () {
    test('카탈로그 순서대로 최대 3개 — 좌석 유형이 편의 옵션보다 앞', () {
      // 고른 순서가 아니라 카탈로그(칩이 놓인) 순서를 따른다 — 저장·복원을
      // 거쳐도 요약 문구가 흔들리지 않게 하기 위함이다.
      final o = _withPicks([
        (_convenience, '1인 방문 가능'),
        (_seating, '카운터석'),
        (_seating, '단체석'),
      ]);
      expect(o.summaryText(), '단체석 · 카운터석 · 1인 방문 가능');
    });

    test('선택이 없으면 빈 문자열', () {
      expect(PlaceFacilityOptions.empty().summaryText(), '');
    });

    test('3개를 넘으면 잘라낸다', () {
      final o = _withPicks([
        (_seating, '개별룸'),
        (_seating, '단체석'),
        (_seating, '카운터석'),
        (_seating, '바 테이블'),
        (_convenience, '합석 가능'),
      ]);
      expect(o.summaryLabels().length, 3);
      expect(o.selectedCount, 5);
      expect(o.summaryText(max: 2), '개별룸 · 단체석');
    });
  });

  group('직렬화', () {
    test('toMap/fromMap 왕복 — 선택 순서와 무관하게 카탈로그 순서로 저장', () {
      final o = _withPicks([
        (_seating, '단체석'),
        (_seating, '개별룸'),
        (_convenience, '1인 방문 가능'),
      ]).withCapacity(_seating, '개별룸', 35).withCapacity(_seating, '단체석', 80);

      final map = o.toMap();
      expect(map[_seating]['selected'], ['개별룸', '단체석']);
      expect(map[_seating]['capacities'], {'개별룸': 35, '단체석': 80});
      expect(map[_convenience]['selected'], ['1인 방문 가능']);
      // 편의 옵션 그룹은 인원 입력을 지원하지 않으므로 capacities가 없다.
      expect(map[_convenience].containsKey('capacities'), isFalse);

      final back = PlaceFacilityOptions.fromMap(map);
      expect(back.selected(_seating), {'개별룸', '단체석'});
      expect(back.capacityOf(_seating, '개별룸'), 35);
      expect(back.isSelected(_convenience, '1인 방문 가능'), isTrue);
    });

    test('선택이 없는 그룹은 저장하지 않는다', () {
      final o = PlaceFacilityOptions.empty().toggle(_seating, '야외석');
      expect(o.toMap().keys, [_seating]);
      expect(PlaceFacilityOptions.empty().toMap(), isEmpty);
    });

    test('선택하지 않은 좌석에 남은 인원 값은 저장에서 걸러진다', () {
      final o = PlaceFacilityOptions.empty()
          .toggle(_seating, '개별룸')
          .withCapacity(_seating, '개별룸', 35)
          .withCapacity(_seating, '단체석', 99); // 고르지 않은 좌석
      final caps = o.toMap()[_seating]['capacities'] as Map;
      expect(caps, {'개별룸': 35});
    });

    test('빈 맵/null도 안전하게 복원된다', () {
      expect(PlaceFacilityOptions.fromMap(null).isEmpty, isTrue);
      expect(PlaceFacilityOptions.fromMap({}).isEmpty, isTrue);
      expect(
        PlaceFacilityOptions.fromMap({'seatingTypes': 'x'}).isEmpty,
        isTrue,
      );
    });

    test('앞으로 추가될 그룹(앱이 모르는 키)도 값이 보존된다', () {
      // 신버전이 저장한 흡연실 정보를 구버전 앱이 읽어도 잃어버리지 않아야 한다.
      final restored = PlaceFacilityOptions.fromMap({
        'smoking': {
          'selected': ['실내 흡연실'],
        },
      });
      expect(restored.selected('smoking'), {'실내 흡연실'});
      expect(restored.isEmpty, isFalse);
    });

    test('임시저장 맵도 같은 형태를 쓴다', () {
      final o = _withPicks([(_seating, '1인석')]);
      expect(
        PlaceFacilityOptions.fromDraftMap(o.toDraftMap()).selected(_seating),
        {'1인석'},
      );
      expect(PlaceFacilityOptions.fromDraftMap(null).isEmpty, isTrue);
    });
  });

  group('카탈로그', () {
    test('요청한 좌석·공간 유형 9개가 모두 있다', () {
      expect(
        PlaceFacilityCatalog.seatingTypes.options.map((o) => o.label).toList(),
        [
          '개별룸',
          '단체석',
          '카운터석',
          '바 테이블',
          '일반 테이블',
          '스탠딩 공간',
          '2인석',
          '1인석',
          '야외석',
        ],
      );
    });

    test('요청한 이용 편의 옵션 5개가 모두 있다', () {
      expect(
        PlaceFacilityCatalog.seatingConveniences.options
            .map((o) => o.label)
            .toList(),
        ['1인 방문 가능', '혼자 앉기 편한 좌석', '합석 가능', '단체 이용 가능', '전체 대관 가능'],
      );
    });

    test('좌석 유형만 인원 입력을 지원한다', () {
      expect(PlaceFacilityCatalog.seatingTypes.supportsCapacity, isTrue);
      expect(
        PlaceFacilityCatalog.seatingConveniences.supportsCapacity,
        isFalse,
      );
    });

    test('모르는 라벨의 이모지는 기본값으로 떨어진다', () {
      expect(PlaceFacilityCatalog.emojiFor('개별룸'), '🚪');
      expect(PlaceFacilityCatalog.emojiFor('없는 항목'), '•');
    });
  });

  group('접히는 섹션 위젯', () {
    Future<void> pump(
      WidgetTester tester,
      PlaceFacilityOptions value,
      ValueChanged<PlaceFacilityOptions> onChanged,
    ) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PlaceFacilityOptionsSection(
                emoji: '🪑',
                title: '좌석·공간',
                emptyHint: '좌석 및 공간 정보를 설정해주세요.',
                groups: PlaceFacilityCatalog.seatingSection,
                value: value,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('기본은 접힌 상태 — 요약과 "자세히 설정"만 보인다', (tester) async {
      await pump(tester, _withPicks([(_seating, '카운터석')]), (_) {});

      expect(find.text('🪑 좌석·공간'), findsOneWidget);
      expect(find.text('카운터석'), findsOneWidget); // 요약 줄
      expect(find.text('자세히 설정'), findsOneWidget);
      // 상세 설정(칩/소제목)은 아직 화면에 없다.
      expect(find.text('좌석·공간 유형'), findsNothing);
    });

    testWidgets('선택이 없으면 안내 문구를 보여준다', (tester) async {
      await pump(tester, PlaceFacilityOptions.empty(), (_) {});
      expect(find.text('좌석 및 공간 정보를 설정해주세요.'), findsOneWidget);
    });

    testWidgets('탭하면 펼쳐지고 칩이 나타난다', (tester) async {
      await pump(tester, PlaceFacilityOptions.empty(), (_) {});

      await tester.tap(find.text('자세히 설정'));
      await tester.pumpAndSettle();

      expect(find.text('좌석·공간 유형'), findsOneWidget);
      expect(find.text('이용 편의 옵션'), findsOneWidget);
      expect(find.text('🚪 개별룸'), findsOneWidget);
      expect(find.text('🙋 1인 방문 가능'), findsOneWidget);
      expect(find.text('접기'), findsOneWidget);
    });

    testWidgets('칩을 누르면 선택이 콜백으로 전달된다', (tester) async {
      PlaceFacilityOptions? changed;
      await pump(tester, PlaceFacilityOptions.empty(), (v) => changed = v);

      await tester.tap(find.text('자세히 설정'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('🚪 개별룸'));
      await tester.pump();

      expect(changed!.isSelected(_seating, '개별룸'), isTrue);
    });

    testWidgets('인원 입력칸은 선택한 좌석에만 나타난다', (tester) async {
      await pump(tester, _withPicks([(_seating, '개별룸')]), (_) {});
      await tester.tap(find.text('자세히 설정'));
      await tester.pumpAndSettle();

      expect(find.text('좌석별 최대 이용 인원 (선택)'), findsOneWidget);
      // 선택한 '개별룸' 한 줄만 인원칸을 갖는다.
      expect(find.widgetWithText(Row, '🚪 개별룸'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('인원을 입력하면 숫자로 저장된다', (tester) async {
      PlaceFacilityOptions? changed;
      await pump(tester, _withPicks([(_seating, '개별룸')]), (v) => changed = v);
      await tester.tap(find.text('자세히 설정'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '35');
      await tester.pump();

      expect(changed!.capacityOf(_seating, '개별룸'), 35);
    });
  });
}

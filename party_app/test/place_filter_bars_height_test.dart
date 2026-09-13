import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/event_filter.dart';
import 'package:party_app/models/place_taxonomy.dart';
import 'package:party_app/widgets/main/place_category_explorer.dart';
import 'package:party_app/widgets/main/place_quick_feature_bar.dart';
import 'package:party_app/widgets/main/place_quick_time_bar.dart';
import 'package:party_app/widgets/main/search_entry_sheet.dart';
import 'package:party_app/utils/place_view_mode.dart';
import 'package:party_app/widgets/view_mode_switch.dart';

/// 플레이스 탭 머리(카테고리 격자 + **상단 컨트롤 한 줄**)가 모바일 실화면에서
/// **목록을 얼마나 밀어내는지** 고정한다.
///
/// 개편으로 1단이 특징 태그 4개에서 대분류 9개로 늘었고, 그 아래에는 한때
/// 필터 줄이 둘이었다(가로스크롤 빠른필터 + 방문 조건·보기 방식). 셋이
/// 연달아 붙으므로 한 칸만 커져도 정작 봐야 할 플레이스 카드가 접힌 화면 밖으로
/// 밀린다.
///
/// 지금은 그 둘을 **한 줄**로 합쳤다:
///
///     [📅 🕐 👥]  [✨ 편의·서비스 ▾]        [보기 방식] [🔍]
///
/// 여기서 지키는 약속 셋:
///  ① 머리(격자 + 한 줄)가 화면의 1/3을 넘지 않는다.
///  ② 그 줄은 **한 줄 고정**이다 — 조건을 몇 개 켜도 세로로 자라지 않고
///     가로로도 넘치지 않는다(오버플로 예외가 곧 실패다).
///  ③ 조건을 켜도 목록 시작 위치가 그대로다 — 고른 조건을 '× 칩'으로 아래에
///     쌓지 않기로 한 원칙이 살아 있는지.
void main() {
  // 가장 좁은 흔한 기기(iPhone SE / 소형 안드로이드) 기준.
  const screen = Size(360, 640);

  /// 머리를 main_screen과 같은 순서·같은 여백·같은 부품으로 쌓는다.
  Widget harness({required EventFilter filter}) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: PlaceCategoryExplorer(
                key: const Key('nav'),
                filter: filter,
                night: true,
                onSelectShop: () {},
                onChanged: () {},
              ),
            ),
            // 상단 컨트롤 한 줄 — 왼쪽부터 방문 조건 · 편의·서비스 ·
            // 보기 방식 · 돋보기. main_screen의 _buildEventPage와 같은 배치다.
            PlaceQuickTimeBar(
              key: const Key('controls'),
              filter: filter,
              onChanged: () {},
              night: true,
              middle: PlaceAmenityButton(
                filter: filter,
                onChanged: () {},
                night: true,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ViewModeMenuButton(
                    currentIcon: PlaceViewMode.standard.icon,
                    label: '보기 방식 · ${PlaceViewMode.standard.label}',
                    options: [
                      for (final mode in PlaceViewMode.values)
                        ViewModeOption(
                          icon: mode.icon,
                          label: mode.label,
                          selected: mode == PlaceViewMode.standard,
                          onTap: () {},
                        ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  SearchEntryIconButton(onTap: () {}, active: false),
                ],
              ),
            ),
            const Expanded(child: SizedBox(key: Key('list'))),
          ],
        ),
      ),
    );
  }

  FlutterErrorDetails? firstError;
  void Function(FlutterErrorDetails)? prevOnError;

  setUp(() {
    firstError = null;
    prevOnError = FlutterError.onError;
    FlutterError.onError = (d) => firstError ??= d;
  });
  tearDown(() => FlutterError.onError = prevOnError);

  Future<void> pump(WidgetTester tester, EventFilter filter) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness(filter: filter));
    await tester.pumpAndSettle();
  }

  testWidgets('머리가 360×640에서 화면의 3분의 1을 넘지 않는다', (tester) async {
    await pump(tester, EventFilter());

    final nav = tester.getSize(find.byKey(const Key('nav'))).height;
    final controls = tester.getSize(find.byKey(const Key('controls'))).height;
    final list = tester.getSize(find.byKey(const Key('list'))).height;

    final header = screen.height - list;
    expect(
      header,
      lessThan(screen.height / 3),
      reason:
          '머리가 화면의 1/3을 넘으면 카드가 한 장도 온전히 안 보인다 '
          '(대분류 $nav · 컨트롤 $controls = 합계 $header)',
    );
    // 목록이 실제로 카드 두 장 이상 들어갈 만큼 남는지도 함께 본다.
    expect(list, greaterThan(420));
    expect(firstError, isNull, reason: '오버플로/예외가 났다: ${firstError?.exception}');
  });

  testWidgets('상단 컨트롤은 한 줄 고정 — 조건을 켜도 세로로 자라지 않는다', (tester) async {
    await pump(tester, EventFilter());
    final before = tester.getSize(find.byKey(const Key('controls'))).height;

    // 16칸을 전부 켜도 줄 수가 늘면 안 된다 — 편의·서비스 버튼은 개수만
    // 이름에 적고('✨ 편의·서비스 16'), 폭이 모자라면 글자를 …로 줄인다.
    final filter = EventFilter();
    for (final f in [
      '핫플',
      '무제한',
      '콜키지프리',
      '프라이빗',
      '대형스크린',
      '놀거리',
      '생일혜택',
      'DJ',
      '라이브',
      '심야영업',
      '금연',
      '흡연공간',
      '반려동물',
      '주차',
      '불멍',
      '수영장',
    ]) {
      filter.toggleFeature(f);
    }
    // 방문 조건 셋까지 함께 걸어도 마찬가지다 — 셋은 버튼 하나 안의 아이콘
    // 색으로만 나타나므로 줄 폭이 늘지 않는다.
    filter.visitDates = {EventFilter.dayOf(DateTime.now())};
    filter.setVisitRange(
      const TimeOfDay(hour: 20, minute: 30),
      const TimeOfDay(hour: 2, minute: 0),
    );
    filter.minCapacity = 120;
    await pump(tester, filter);

    expect(tester.getSize(find.byKey(const Key('controls'))).height, before);
    expect(firstError, isNull, reason: '오버플로/예외가 났다: ${firstError?.exception}');
  });

  testWidgets('가장 좁은 320px에서도 한 줄이 넘치지 않는다', (tester) async {
    // 좁은 화면일수록 편의·서비스 버튼이 먼저 줄어든다 — 나머지 셋은 폭이
    // 고정이라 밀려나거나 잘리면 안 된다.
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final filter = EventFilter();
    filter.minCapacity = 120;
    await tester.pumpWidget(harness(filter: filter));
    await tester.pumpAndSettle();

    final controls = tester.getRect(find.byKey(const Key('controls')));
    expect(controls.width, lessThanOrEqualTo(320));
    // 돋보기는 언제나 줄 맨 오른쪽에 남아 있다.
    expect(find.byType(SearchEntryIconButton), findsOneWidget);
    expect(firstError, isNull, reason: '오버플로/예외가 났다: ${firstError?.exception}');
  });

  testWidgets('조건을 켜도 목록 시작 위치가 내려가지 않는다', (tester) async {
    await pump(tester, EventFilter());
    final before = tester.getSize(find.byKey(const Key('list'))).height;

    // 특징 · 속성 · 지역 · 가격 · 날짜까지 겹쳐 걸어도, 고른 조건을 아래에
    // '× 칩'으로 쌓지 않으므로 목록 높이는 **정확히 그대로**여야 한다.
    // (예전에는 여기서 칩 줄이 생겨 카드가 통째로 아래로 밀렸다.)
    final filter = EventFilter(
      regions: {'서울 강남구'},
      features: {'DJ', '심야영업'},
      attributes: {
        'musicGenres': {'HIPHOP', 'EDM'},
      },
      priceRanges: {'3~5만원'},
      visitDate: DateTime(2026, 9, 1),
    );
    await pump(tester, filter);

    expect(tester.getSize(find.byKey(const Key('list'))).height, before);
    expect(firstError, isNull, reason: '오버플로/예외가 났다: ${firstError?.exception}');
  });

  testWidgets('대분류를 고르면 소분류가 **같은 자리**에 온다 — 아래에 줄이 늘지 않는다', (tester) async {
    await pump(tester, EventFilter());
    final navBefore = tester.getSize(find.byKey(const Key('nav'))).height;
    final listBefore = tester.getSize(find.byKey(const Key('list'))).height;

    await pump(tester, EventFilter(categories: {PlaceTaxonomy.club.label}));

    // 소분류 층은 1줄이라 2줄짜리 대분류 층보다 오히려 낮다 — 목록은
    // 내려가는 게 아니라 올라온다.
    expect(
      tester.getSize(find.byKey(const Key('nav'))).height,
      lessThanOrEqualTo(navBefore),
    );
    expect(
      tester.getSize(find.byKey(const Key('list'))).height,
      greaterThanOrEqualTo(listBefore),
    );
    // 클럽의 하위 탐색은 **음악 장르**다(소분류 '힙합클럽'과 중복 저장하지
    // 않기 위해). 다른 대분류의 소분류는 보이지 않는다.
    expect(find.text('힙합·R&B'), findsOneWidget);
    expect(find.text('힙합클럽'), findsNothing);
    expect(find.text('한식'), findsNothing);
    expect(firstError, isNull, reason: '오버플로/예외가 났다: ${firstError?.exception}');
  });

  /// 대분류 칸의 이름 글자가 **그 칸 안에** 실제로 들어가는지.
  ///
  /// 긴 이름은 [PlaceCategoryGrid]가 `FittedBox(scaleDown)`로 줄여 그린다.
  /// 그래서 "짧은 표기를 쓴다"가 아니라 **줄여서라도 칸을 넘지 않는다**가
  /// 이 격자의 약속이다. 그 방어선이 사라지면(FittedBox를 걷어내거나 칸이
  /// 좁아지면) 글자가 옆 칸까지 번지거나 오버플로가 난다.
  ///
  /// 재는 것은 그려진 자리다 — [WidgetTester.getRect]는 조상 변환까지 반영한
  /// 화면 좌표를 주므로, 축소된 뒤의 실제 폭이 나온다.
  ///
  /// 헛도는 검사가 아니다: 320px에서 칸은 43.8px인데 가장 긴 '체험/클래스'의
  /// 본래 폭은 70.5px이라, FittedBox가 37.8px로 줄여야만 통과한다. 그 방어선을
  /// 걷어내면 여기서 바로 걸린다.
  void expectLabelsFitTheirCells(WidgetTester tester) {
    for (final c in PlaceTaxonomy.selectable) {
      final label = find.text(c.shortLabel);
      final cell = find.ancestor(
        of: label,
        matching: find.byType(AnimatedContainer),
      );
      expect(cell, findsOneWidget, reason: '${c.shortLabel} 칸을 찾지 못했다');

      final drawn = tester.getRect(label);
      final box = tester.getRect(cell);
      expect(
        drawn.width,
        lessThanOrEqualTo(box.width),
        reason:
            '"${c.shortLabel}"이 칸(${box.width.toStringAsFixed(1)}px)보다 '
            '넓게(${drawn.width.toStringAsFixed(1)}px) 그려졌다 — 옆 칸까지 번진다',
      );
      expect(
        drawn.left >= box.left - 0.5 && drawn.right <= box.right + 0.5,
        isTrue,
        reason: '"${c.shortLabel}"이 제 칸 밖으로 삐져나왔다 ($drawn ⊄ $box)',
      );
    }
  }

  testWidgets('대분류 칸은 정본 표기를 쓰고, 그 글자가 칸 안에 들어간다', (tester) async {
    await pump(tester, EventFilter());

    // ── 무엇을 그리는가 ────────────────────────────────────────────────
    // 바에 적히는 글자는 언제나 정본의 [PlaceCategory.shortLabel]이다
    // (place_category_explorer.dart가 그 값으로 칸을 만든다). 문자열을 여기
    // 다시 적지 않는다 — 예전에는 '체험'이라고 박아 두었다가, 정본이
    // '체험/클래스'로 부르기로 바꾼 뒤에도 테스트만 옛 표기에 묶여 있었다.
    for (final c in PlaceTaxonomy.selectable) {
      expect(
        find.text(c.shortLabel),
        findsOneWidget,
        reason: '${c.label} 칸이 정본 표기("${c.shortLabel}")로 안 보인다',
      );
    }

    // 은퇴한 대분류는 칸을 갖지 않는다 — 바가 세 줄로 자라면 머리가 화면의
    // 1/3을 먹는다(맨 위 검사). 대신 그 가게들은 살아 있는 대분류에서 함께
    // 뜬다([PlaceTaxonomy.matchesAnyCategory]의 은퇴 다리가 맡는다).
    for (final c in PlaceTaxonomy.all.where((c) => c.retired)) {
      expect(
        find.text(c.shortLabel),
        findsNothing,
        reason: '은퇴한 ${c.label}이 카테고리 바에 아직 서 있다',
      );
    }

    // 표기는 화면용일 뿐이고 **필터가 쓰는 값은 언제나 저장값**이다.
    // 그래서 저장값이 표기와 다른 대분류는 저장값이 화면에 새어 나오면 안 된다.
    for (final c in PlaceTaxonomy.selectable) {
      if (c.label == c.shortLabel) continue;
      expect(
        find.text(c.label),
        findsNothing,
        reason: '${c.label} 칸에 표기 대신 저장값이 그대로 그려졌다',
      );
    }

    // 저장값 자체는 배포 후 바꾸면 안 되는 값이다(바꾸면 이미 등록된 문서가
    // 필터에서 사라진다) — 표기를 손볼 때 함께 흔들리지 않았는지 못 박아 둔다.
    expect(PlaceTaxonomy.restaurant.label, '맛집');
    expect(PlaceTaxonomy.cafe.label, '카페·디저트');
    expect(PlaceTaxonomy.live.label, '라이브·공연');
    expect(PlaceTaxonomy.experience.label, '체험·클래스');

    // 혼술바는 BAR의 소분류가 아니라 독립 칸이다.
    expect(find.text(PlaceTaxonomy.soloBar.shortLabel), findsOneWidget);

    // ── 그 글자가 칸에 들어가는가 (이 검사의 본론) ──────────────────────
    expectLabelsFitTheirCells(tester);
    expect(firstError, isNull, reason: '오버플로/예외가 났다: ${firstError?.exception}');
  });

  testWidgets('가장 좁은 320px에서도 오버플로 없이 칸 안에 들어간다', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness(filter: EventFilter()));
    await tester.pumpAndSettle();

    // 칸이 가장 좁아지는 자리다 — 긴 이름이 여기서 버티면 어디서든 버틴다.
    expectLabelsFitTheirCells(tester);
    expect(firstError, isNull, reason: '오버플로/예외가 났다: ${firstError?.exception}');
  });
}

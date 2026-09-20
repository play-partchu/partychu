// 지도 홈 — (1) '전체'로 처음 들어왔을 때 🎊 공공 축제가 올라가는가,
// (2) 상단 빠른 필터 한 줄(카테고리 6 + 🕐 + ₩)과 ₩ 가격 필터.
//
// 회귀: 홈도 지도 화면과 같은 파티츄 세 종류로 시작해서, 카테고리를 한 번도
// 누르지 않은 '전체' 상태에서는 공공 축제 구독 조건(종류에 festival 포함)이
// 성립하지 않았다. '전체'를 다시 눌러도 선택이 그대로라 바뀌지 않았다.
//
// NaverMap은 위젯 테스트에서 띄우지 않는다 — 종류 결정은 순수 함수로, 화면
// 연결은 소스로, 버튼은 위젯 하나로 확인한다.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/models/date_time_filter_label.dart';
import 'package:party_app/models/map_home_category.dart';
import 'package:party_app/models/map_listing.dart';
import 'package:party_app/models/party_filter.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/models/listing_price_match.dart';
import 'package:party_app/models/map_quick_filter_row.dart';
import 'package:party_app/widgets/map_price_filter_sheet.dart';
import 'package:party_app/widgets/map_quick_filter_button.dart';

int _index(String label) =>
    mapHomeCategories.indexWhere((c) => c.label == label);

const _festival = MapListingKind.festival;

void main() {
  final src = File('lib/screens/map_screen.dart').readAsStringSync();
  final flat = src.replaceAll(RegExp(r'\s+'), ' ');

  group('🎊 공공 축제가 올라가는 칸', () {
    test('홈은 처음부터 전체(파티·플레이스·장소대여·공공 축제)로 시작한다', () {
      expect(mapInitialKinds(home: true), {
        MapListingKind.party,
        MapListingKind.place,
        MapListingKind.rental,
        _festival,
      });
    });

    test('지도 화면(목록 시트)은 예전처럼 파티츄 세 종류로 시작한다', () {
      expect(mapInitialKinds(home: false), MapListingKind.listingKinds.toSet());
      expect(mapInitialKinds(home: false).contains(_festival), isFalse);
    });

    test('전체 — 아무 칸도 안 켰을 때와 전체를 눌렀을 때 모두 공공 축제 포함', () {
      expect(mapHomeKindsFor(const {}).contains(_festival), isTrue);
      expect(mapHomeKindsFor(const {}), mapInitialKinds(home: true));
    });

    test('이벤트 — 플레이스·장소대여(이벤트 하는 곳) + 공공 축제', () {
      final i = _index('이벤트');
      expect(mapHomeKindsFor({i}), {
        MapListingKind.place,
        MapListingKind.rental,
        _festival,
      });
      expect(mapHomeCategories[i].eventOnly, isTrue);
    });

    test('파티·플레이스·장소대여 칸에는 공공 축제가 없다(기존 그대로)', () {
      expect(mapHomeKindsFor({_index('파티')}), {MapListingKind.party});
      expect(mapHomeKindsFor({_index('플레이스')}), {MapListingKind.place});
      expect(mapHomeKindsFor({_index('장소대여')}), {MapListingKind.rental});
      expect(
        mapHomeKindsFor({_index('파티'), _index('플레이스'), _index('장소대여')})
            .contains(_festival),
        isFalse,
      );
      // 여러 칸을 켜면 합집합 — 이벤트가 끼면 공공 축제도 들어간다.
      expect(
        mapHomeKindsFor({_index('파티'), _index('이벤트')}).contains(_festival),
        isTrue,
      );
    });

    test('화면 연결(소스) — 처음 종류·칸 선택이 위 함수를 쓰고, 구독 조건은 종류 포함 여부', () {
      expect(
        flat.contains(
          'late Set<MapListingKind> _kinds = mapInitialKinds(home: widget.home);',
        ),
        isTrue,
      );
      expect(flat.contains('_kinds = mapHomeKindsFor(_homeSelected);'), isTrue);
      expect(
        flat.contains(
          'final want = _home && !kIsWeb && _kinds.contains(MapListingKind.festival);',
        ),
        isTrue,
      );
      // 구독은 _recomputeVisible에서 맞춘다 — 첫 스냅샷이 들어오는 순간 걸린다.
      final recompute = flat.substring(flat.indexOf('void _recomputeVisible() {'));
      expect(
        recompute.indexOf('_syncPublicEventSub();'),
        lessThan(recompute.indexOf('_mapItems = [')),
      );
      // 예전의 '세 종류로 시작'이 남아 있지 않다.
      expect(
        flat.contains('Set<MapListingKind> _kinds = MapListingKind.listingKinds.toSet();'),
        isFalse,
      );
    });
  });

  group('🕐·₩ 빠른 버튼', () {
    Widget host(Widget child) =>
        MaterialApp(home: Scaffold(body: Center(child: child)));

    testWidgets('기본은 아이콘만 — 글자 없음, 카테고리 칩과 같은 높이', (tester) async {
      await tester.pumpWidget(
        host(
          MapQuickFilterButton(
            icon: Icons.schedule_rounded,
            active: false,
            height: 40,
            onTap: () {},
          ),
        ),
      );
      expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
      expect(find.byType(Text), findsNothing);
      expect(tester.getSize(find.byType(MapQuickFilterButton)).height, 40);
    });

    testWidgets('₩는 글자 기호로 그린다', (tester) async {
      await tester.pumpWidget(
        host(
          MapQuickFilterButton(
            icon: Icons.payments_outlined,
            glyph: '₩',
            active: false,
            onTap: () {},
          ),
        ),
      );
      expect(find.text('₩'), findsOneWidget);
      expect(find.byIcon(Icons.payments_outlined), findsNothing);
    });

    testWidgets('적용 중이면 분홍으로 채운다(꺼져 있으면 흰 바탕)', (tester) async {
      Color background(WidgetTester t) =>
          (t
                      .widget<Container>(
                        find.descendant(
                          of: find.byType(MapQuickFilterButton),
                          matching: find.byType(Container),
                        ),
                      )
                      .decoration!
                  as BoxDecoration)
              .color!;

      await tester.pumpWidget(
        host(
          MapQuickFilterButton(
            icon: Icons.schedule_rounded,
            active: false,
            onTap: () {},
          ),
        ),
      );
      expect(background(tester), Colors.white);

      await tester.pumpWidget(
        host(
          MapQuickFilterButton(
            icon: Icons.schedule_rounded,
            active: true,
            onTap: () {},
          ),
        ),
      );
      expect(background(tester), const Color(0xFFFF6FA0));
    });

test('적용 중 판단 — 🕐는 기존 표기 함수, ₩는 고른 칸이 있는가', () {
      // 🕐: 날짜·시간 칸 중 하나라도 걸리면 적용 중(목록 탭과 같은 칸).
      bool dateActive(PartyFilter f) => dateTimeFilterLabel(f) != null;
      expect(dateActive(PartyFilter()), isFalse);
      expect(dateActive(PartyFilter()..selectedDates = {DateTime(2026, 9, 25)}), isTrue);
      expect(
        dateActive(PartyFilter()..timeOfDayStart = const TimeOfDay(hour: 19, minute: 0)),
        isTrue,
      );
      expect(dateActive(PartyFilter()..dateOptions.add('이번주말')), isTrue);
      // ₩: 종류가 무엇이든 칸이 하나라도 있으면 적용 중.
      expect(MapPriceSelection.none.isActive, isFalse);
      expect(const MapPriceSelection(placeRanges: {'1만원 이하'}).isActive, isTrue);
      expect(const MapPriceSelection(rentalRanges: {'3~5만원'}).isActive, isTrue);
    });

    testWidgets('짧은 값을 주면 아이콘 옆에 붙고, 누르면 onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          MapQuickFilterButton(
            icon: Icons.schedule_rounded,
            active: true,
            label: '19:00',
            onTap: () => taps++,
          ),
        ),
      );
      expect(find.text('19:00'), findsOneWidget);
      await tester.tap(find.byType(MapQuickFilterButton));
      expect(taps, 1);
    });
  });

  group('한 줄 배치(폭 계산)', () {
    // 실제 글자 폭 대신 재현 가능한 값으로 계산만 본다(폭 계산은 순수 함수).
    // 전체·특징·파티·이벤트(28~44) + 플레이스·장소대여(56) + 🕐·₩(0).
    const texts = [28.0, 28.0, 28.0, 42.0, 56.0, 56.0, 0.0, 0.0];
    const icons = [0.0, 15.0, 0.0, 0.0, 0.0, 0.0, 17.0, 17.0];
    const gap = 2.0;
    const sidePad = 3.0;
    const basePad = 7.0;
    const minPad = 2.0;

    ({double used, QuickRowLayout layout}) run(double screenWidth) {
      final available = screenWidth - sidePad * 2 - gap * (texts.length - 1);
      final layout = quickRowLayout(
        texts: texts,
        icons: icons,
        available: available,
        basePad: basePad,
        minPad: minPad,
      );
      final used =
          layout.widths.fold<double>(0, (a, b) => a + b) +
          gap * (texts.length - 1) +
          sidePad * 2;
      return (used: used, layout: layout);
    }

    test('작은 폭(320)부터 큰 폭(430)까지 여덟 칸이 한 줄에 든다', () {
      for (final width in [320.0, 360.0, 375.0, 390.0, 412.0, 430.0]) {
        final r = run(width);
        expect(r.layout.scroll, isFalse, reason: '${width}dp에서 가로 스크롤');
        expect(
          r.used,
          lessThanOrEqualTo(width + 0.01),
          reason: '${width}dp에서 줄을 넘침(${r.used})',
        );
      }
    });

    test('넉넉하면 기본 여백 그대로, 남는 폭을 나눠 갖지 않는다', () {
      final r = run(430);
      expect(r.layout.pad, basePad);
      expect(r.layout.scale, 1);
      // 각 칸은 자기 콘텐츠 + 여백만. 남는 폭은 오른쪽에 남는다.
      expect(r.layout.widths.first, texts[0] + basePad * 2);
      expect(r.used, lessThan(430));
    });

    test('좁아지면 여백부터 줄이고, 그다음에 글자를 줄인다', () {
      // 최소 여백으로 딱 들어가는 폭(= 콘텐츠 + 최소 여백 + 간격·좌우 여백).
      final tight = run(345);
      expect(tight.layout.pad, lessThan(basePad));
      expect(tight.layout.pad, greaterThanOrEqualTo(minPad));
      expect(tight.layout.scale, 1, reason: '여백으로 해결되면 글자는 그대로');

      final tighter = run(315);
      expect(tighter.layout.pad, minPad);
      expect(tighter.layout.scale, lessThan(1));
      expect(tighter.layout.scale, greaterThanOrEqualTo(0.85));
      expect(tighter.layout.scroll, isFalse);
    });

    test('아주 좁으면 마지막 수단으로만 가로 스크롤', () {
      final r = run(200);
      expect(r.layout.scroll, isTrue);
      expect(r.layout.scale, 0.85, reason: '글자를 더 줄이지는 않는다');
    });

    test('아이콘 폭은 글자 배율에서 빠진다(아이콘은 안 줄인다)', () {
      final r = run(300);
      final s = r.layout.scale;
      expect(r.layout.widths[6], closeTo(icons[6] + minPad * 2, 0.001));
      expect(r.layout.widths[1], closeTo(texts[1] * s + icons[1] + minPad * 2, 0.001));
    });
  });


  testWidgets('실제 글자 폭으로 재도 여덟 칸이 한 줄에 든다(320~430dp)', (tester) async {
    // 칩 글자를 실제로 재서(테스트 폰트) 화면과 같은 치수로 계산한다.
    late TextDirection direction;
    late TextScaler scaler;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            direction = Directionality.of(context);
            scaler = MediaQuery.textScalerOf(context);
            return const SizedBox();
          },
        ),
      ),
    );
    double measure(String text) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(
            fontSize: kQuickChipFontSize,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final w = painter.width;
      painter.dispose();
      return w + 1;
    }

    const labels = ['전체', '특징', '파티', '이벤트', '플레이스', '장소대여'];
    final texts = [...labels.map(measure), 0.0, 0.0];
    final icons = [
      0.0,
      kQuickChipIconSize + kQuickChipIconGap, // ✨ 특징
      0.0, 0.0, 0.0, 0.0,
      MapQuickFilterButton.iconSize, // 🕐
      MapQuickFilterButton.iconSize, // ₩
    ];

    for (final width in [320.0, 360.0, 375.0, 390.0, 412.0, 430.0]) {
      final available =
          width - kQuickRowSidePad * 2 - kQuickChipGap * (texts.length - 1);
      final layout = quickRowLayout(
        texts: texts,
        icons: icons,
        available: available,
        basePad: kQuickChipBasePad,
        minPad: kQuickChipMinPad,
      );
      final used =
          layout.widths.fold<double>(0, (a, b) => a + b) +
          kQuickChipGap * (texts.length - 1) +
          kQuickRowSidePad * 2;
      expect(layout.scroll, isFalse, reason: '${width}dp에서 가로 스크롤');
      expect(used, lessThanOrEqualTo(width + 0.01), reason: '${width}dp 넘침');
      // 글자는 거의 줄이지 않는다(줄여도 15% 안쪽).
      expect(layout.scale, greaterThanOrEqualTo(0.85));
    }
  });

  group('₩ 가격 빠른 필터', () {
    test('짧은 표기 — 한 칸은 줄여 적고, 여러 칸은 개수', () {
      expect(mapPriceFilterLabel(MapPriceSelection.none), isNull);
      expect(
        mapPriceFilterLabel(const MapPriceSelection(partyFees: {'무료'})),
        '무료',
      );
      expect(
        mapPriceFilterLabel(const MapPriceSelection(partyFees: {'3~5만원'})),
        '3~5만',
      );
      expect(
        mapPriceFilterLabel(const MapPriceSelection(rentalRanges: {'20만원 이상'})),
        '20만+',
      );
      expect(
        mapPriceFilterLabel(
          const MapPriceSelection(partyFees: {'무료'}, placeRanges: {'1만원 이하'}),
        ),
        '가격 2',
      );
      expect(
        const MapPriceSelection(partyFees: {'무료'}).isActive,
        isTrue,
      );
      expect(MapPriceSelection.none.isActive, isFalse);
    });

    test('판정 — 파티 참가비는 최소 금액 기준(목록과 같은 칸)', () {
      bool m(Map<String, dynamic> d, Set<String> r) => partyFeeMatches(d, r);
      expect(m({'pricingType': 'free'}, {'무료'}), isTrue);
      expect(m({'pricingType': 'free'}, {'1만원 이하'}), isFalse);
      expect(m({'pricingType': 'same', 'price': 20000}, {'1~3만원'}), isTrue);
      expect(m({'pricingType': 'same', 'price': 20000}, {'무료'}), isFalse);
      // 성별가는 낮은 쪽이 기준.
      expect(
        m({
          'pricingType': 'gendered',
          'malePrice': 40000,
          'femalePrice': 20000,
        }, {'1~3만원'}),
        isTrue,
      );
      // 조건이 없으면 모두 통과.
      expect(m({'pricingType': 'same', 'price': 999999}, {}), isTrue);
    });

    test('판정 — 장소대여는 시간당 요금, **가격 문의는 어느 칸에도 안 든다**', () {
      const ranges = {'3만원 이하', '20만원 이상'};
      expect(rentalPriceMatches({'pricePerHour': 20000}, ranges), isTrue);
      expect(rentalPriceMatches({'pricePerHour': 300000}, ranges), isTrue);
      expect(rentalPriceMatches({'pricePerHour': 50000}, ranges), isFalse);
      // 가격 문의 — 0원으로 읽어 '3만원 이하'에 넣으면 안 된다.
      expect(
        rentalPriceMatches({
          'priceType': 'inquiry',
          'pricePerHour': 0,
        }, ranges),
        isFalse,
      );
      expect(
        rentalPriceMatches({'priceType': 'inquiry', 'pricePerHour': 20000}, ranges),
        isFalse,
      );
      // 조건이 없으면 가격 문의도 그대로 남는다.
      expect(rentalPriceMatches({'priceType': 'inquiry'}, {}), isTrue);
      // 0원(무료) 공간은 예전처럼 어느 칸에도 들지 않는다.
      expect(rentalPriceMatches({'pricePerHour': 0}, ranges), isFalse);
    });

    test('판정 — 플레이스는 등록 때 고른 라벨 그대로 비교', () {
      expect(eventPriceMatches({'priceRange': '1~3만원'}, {'1~3만원'}), isTrue);
      expect(eventPriceMatches({'priceRange': '무료'}, {'1~3만원'}), isFalse);
      expect(eventPriceMatches({}, {'무료'}), isFalse, reason: '라벨 없는 문서');
      expect(eventPriceMatches({}, {}), isTrue);
    });

    test('칸 목록은 기존 목록 탭 것과 같다(새 체계를 만들지 않았다)', () {
      expect(partyFeeRanges.first, '무료');
      expect(partyFeeRanges.length, 7);
      expect(ListingConstants.placePriceRanges.contains('3만원 이하'), isTrue);
      expect(ListingConstants.eventPriceRanges.contains('무료'), isTrue);
      // 상세검색 시트의 참가비 칸도 같은 상수를 쓴다.
      final sheet = File('lib/widgets/detail_search_sheet.dart').readAsStringSync();
      expect(sheet.contains('static const _feeRanges = partyFeeRanges;'), isTrue);
      // 목록 탭의 판정도 같은 함수로 위임한다.
      final main = File('lib/screens/main_screen.dart')
          .readAsStringSync()
          .replaceAll(RegExp(r'\s+'), ' ');
      expect(
        main.contains('bool _matchesFeeRange(int fee, String range) => partyFeeInRange(fee, range);'),
        isTrue,
      );
      expect(
        main.contains('bool _matchesPlacePriceRange(int price, String range) => rentalPriceInRange(price, range);'),
        isTrue,
      );
    });

    testWidgets('시트 — 지금 지도에 올라온 종류의 칸만, 적용하면 고른 값을 돌려준다', (tester) async {
      MapPriceSelection? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showMapPriceFilterSheet(
                    context,
                    initial: MapPriceSelection.none,
                    kinds: {MapListingKind.party, MapListingKind.rental},
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

      expect(find.byKey(const ValueKey('mapPriceParty')), findsOneWidget);
      expect(find.byKey(const ValueKey('mapPriceRental')), findsOneWidget);
      expect(find.byKey(const ValueKey('mapPricePlace')), findsNothing);
      expect(find.textContaining('가격 문의'), findsOneWidget, reason: '가격 문의 안내');

      await tester.tap(find.text('3~5만원').first);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('mapPriceApply')));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.count, 1);
      expect(result!.all, {'3~5만원'});
    });

    testWidgets('시트 — 초기화하면 고른 칸이 비워진다', (tester) async {
      MapPriceSelection? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showMapPriceFilterSheet(
                    context,
                    initial: const MapPriceSelection(partyFees: {'무료'}),
                    kinds: {MapListingKind.party},
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
      await tester.tap(find.byKey(const ValueKey('mapPriceReset')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('mapPriceApply')));
      await tester.pumpAndSettle();
      expect(result!.isEmpty, isTrue);
    });

    test('화면 연결(소스) — 기존 칸에 그대로 넣고, 마커까지 다시 센다', () {
      // 고른 값은 새 상태가 아니라 기존 필터 칸으로 들어간다.
      final start = flat.indexOf('Future<void> _openPriceFilter() async {');
      expect(start, isNonNegative);
      final open = flat.substring(start, start + 500);
      expect(open.contains('_filter.feeRanges ..clear() ..addAll(picked.partyFees);'), isTrue);
      expect(open.contains('_placeDiscovery.priceRanges ..clear() ..addAll(picked.placeRanges);'), isTrue);
      expect(open.contains('_rentalDiscovery.priceRanges ..clear() ..addAll(picked.rentalRanges);'), isTrue);
      expect(open.contains('_recomputeVisible();'), isTrue);
      expect(open.contains('_syncMarkers();'), isTrue);
      // 지도 판정도 공용 함수를 쓴다.
      expect(flat.contains('!eventPriceMatches(item.data, _placeDiscovery.priceRanges)'), isTrue);
      expect(flat.contains('!rentalPriceMatches(item.data, _rentalDiscovery.priceRanges)'), isTrue);
      expect(flat.contains('if (!partyFeeMatches(p, _filter.feeRanges)) return false;'), isTrue);
      // 지도에는 참가비 switch 복사본이 남아 있지 않다.
      expect(flat.contains('_matchesFeeRange'), isFalse);
    });

    test('화면 연결(소스) — 여덟 칸이 한 줄, 떠 있던 버튼은 없다', () {
      expect(flat.contains("key: const ValueKey('mapHomeDateTimeButton')"), isTrue);
      expect(flat.contains("key: const ValueKey('mapHomePriceButton')"), isTrue);
      expect(flat.contains('onTap: _openPriceFilter'), isTrue);
      expect(flat.contains('_buildHomeDateTimeButton'), isFalse, reason: '떠 있던 버튼 제거');
      // 폭은 실제 가용 폭으로 계산한다(기기 폭 하드코딩 없음).
      expect(flat.contains('LayoutBuilder('), isTrue);
      expect(flat.contains('constraints.maxWidth - _chipSidePad * 2 - _chipGap * (count - 1)'), isTrue);
      expect(flat.contains('quickRowLayout('), isTrue);
      // 값 글자는 자리가 남을 때만.
      expect(flat.contains('if (wantLabels && (layout.scale < 1 || layout.scroll)) { showLabels = false;'), isTrue);
      // 🕐 판은 줄 아래에서 그대로 열린다.
      expect(flat.contains('if (_dateTimePaneOpen) Padding('), isTrue);
    });
  });
}

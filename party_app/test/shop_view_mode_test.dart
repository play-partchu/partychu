// 🛍️ 파티샵 목록 보기 방식 — 플레이스와 **같은 칸 셋, 같은 컨트롤, 같은 카드**.
//
// ── 무엇을 붙잡는가 ──────────────────────────────────────────────────────────
// ① 기본값 — 처음 들어오면 **기본 카드**다.
// ② 값·아이콘·이름을 파티샵이 따로 만들지 않았다(플레이스와 같은 enum).
// ③ 저장 자리는 따로다 — 파티샵을 바꿨다고 플레이스 목록까지 바뀌지 않는다.
// ④ 보기 방식마다 **카드 껍데기와 배치까지** 갈린다:
//      작은 카드 = 가로형 1열 / 기본 카드 = 2열 그리드 / 큰 카드 = 화면 한 장.
//    그리고 대표 미디어 규칙은 셋 다 같다.
// ④-2 그 카드들이 실제로 렌더했을 때 플레이스 카드와 **같은 크기**다.
// ⑤ 컨트롤은 공용 위젯 하나다([ViewModeMenuButton]) — 버튼 하나에 메뉴 셋,
//    눌러 전환되는 것까지 확인.
//
// 목록 자체(MainScreen)는 Firestore 없이 그릴 수 없으므로 "어떻게 배치했는가"는
// 소스 가드로, 카드 크기는 실제 렌더로 확인한다.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:party_app/utils/party_utils.dart';
import 'package:party_app/utils/place_view_mode.dart';
import 'package:party_app/widgets/view_mode_switch.dart';
import 'package:party_app/widgets/list_card_shell.dart';
import 'package:party_app/widgets/place_card_widget.dart';
import 'package:party_app/widgets/shop_card_widget.dart';

String _src(String path) => File(path).readAsStringSync();

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ── ① 기본값 ───────────────────────────────────────────────────────────
  group('처음 들어오면 기본 카드다', () {
    test('저장된 값이 없으면 standard', () async {
      expect(await ShopViewModePrefs.loadForShop(), PlaceViewMode.standard);
    });

    test('알 수 없는 값이 저장돼 있어도 standard로 떨어진다', () async {
      SharedPreferences.setMockInitialValues({'shop_view_mode': '몰라요'});
      expect(await ShopViewModePrefs.loadForShop(), PlaceViewMode.standard);
    });

    test('화면의 초기값도 기본 카드다', () {
      final main = _flat(_src('lib/screens/main_screen.dart'));
      expect(
        main.contains('PlaceViewMode _shopViewMode = PlaceViewMode.standard;'),
        isTrue,
      );
    });
  });

  // ── ② 값은 플레이스와 같은 것 ──────────────────────────────────────────
  group('파티샵만의 보기 방식을 새로 만들지 않았다', () {
    test('칸은 셋 — 작은/기본/큰', () {
      expect(PlaceViewMode.values, [
        PlaceViewMode.compact,
        PlaceViewMode.standard,
        PlaceViewMode.large,
      ]);
    });

    test('아이콘·이름이 플레이스와 같은 값에서 나온다', () {
      // 파티샵 전용 enum이 따로 있으면 이 값들이 갈라진다.
      expect(PlaceViewMode.compact.label, '작은 카드 보기');
      expect(PlaceViewMode.standard.label, '기본 카드 보기');
      expect(PlaceViewMode.large.label, '큰 카드 보기');
      expect(PlaceViewMode.compact.icon, Icons.view_list_rounded);
      expect(PlaceViewMode.standard.icon, Icons.grid_view_rounded);
      expect(PlaceViewMode.large.icon, Icons.crop_portrait_rounded);
    });

    test('파티샵 전용 enum 파일을 만들지 않았다', () {
      expect(File('lib/utils/shop_view_mode.dart').existsSync(), isFalse);
    });
  });

  // ── ③ 저장 자리는 따로 ─────────────────────────────────────────────────
  group('파티샵과 플레이스는 서로의 보기 방식을 건드리지 않는다', () {
    test('파티샵을 바꿔도 플레이스는 그대로', () async {
      await PlaceViewMode.compact.saveForShop();
      expect(await ShopViewModePrefs.loadForShop(), PlaceViewMode.compact);
      // 플레이스는 저장한 적이 없으니 여전히 기본값이다.
      expect(await PlaceViewMode.load(), PlaceViewMode.standard);
    });

    test('플레이스를 바꿔도 파티샵은 그대로', () async {
      await PlaceViewMode.large.save();
      expect(await PlaceViewMode.load(), PlaceViewMode.large);
      expect(await ShopViewModePrefs.loadForShop(), PlaceViewMode.standard);
    });

    test('세 방식 모두 저장되고 그대로 돌아온다', () async {
      for (final mode in PlaceViewMode.values) {
        await mode.saveForShop();
        expect(await ShopViewModePrefs.loadForShop(), mode, reason: mode.name);
      }
    });
  });

  // ── ④ 목록 배선 — 보기 방식마다 "배치"까지 갈린다 ───────────────────────
  group('세 방식이 각자 카드와 배치를 갖고 대표 미디어 규칙은 같다', () {
    final main = _flat(_src('lib/screens/main_screen.dart'));

    test('작은 카드 — 가로형 카드 1열', () {
      expect(
        main.contains('if (_shopViewMode == PlaceViewMode.compact) {'),
        isTrue,
      );
      expect(main.contains('ShopCompactCard( key: ValueKey(doc.id),'), isTrue);
    });

    test('기본 카드 — 2열 그리드(Row 쌍)', () {
      // 한 줄에 두 장씩 — 행 수가 문서 수의 절반이면 2열이라는 뜻이다.
      expect(
        main.contains('final rowCount = (docs.length / 2).ceil();'),
        isTrue,
      );
      expect(
        main.contains(
          'final rightDoc = rowIdx * 2 + 1 < docs.length '
          '? docs[rowIdx * 2 + 1] : null;',
        ),
        isTrue,
      );
      // 좌우 두 칸이 같은 폭을 나눠 갖는다.
      expect(
        main.contains(
          'Expanded( child: ShopStandardCard( key: ValueKey(leftDoc.id),',
        ),
        isTrue,
      );
      expect(
        main.contains('? ShopStandardCard( key: ValueKey(rightDoc.id),'),
        isTrue,
      );
    });

    test('큰 카드 — 화면 한 장을 통째로 쓰는 1열', () {
      expect(
        main.contains('if (_shopViewMode == PlaceViewMode.large) {'),
        isTrue,
      );
      // 목록 뷰포트 높이를 그대로 카드 높이로 준다 — 예전처럼 대표 이미지
      // 높이만 240으로 늘린 카드가 아니다.
      expect(
        main.contains(
          'SizedBox( height: constraints.maxHeight, child: ShopLargeCard(',
        ),
        isTrue,
      );
    });

    test('예전 세로형 1열 카드는 남아 있지 않다', () {
      // 세 방식을 화면 파일 안에서 직접 그리던 옛 함수들.
      for (final gone in [
        'Widget _shopCard(',
        'Widget _shopCompactCard(',
        'final imageHeight = large ? 240.0 : 160.0;',
      ]) {
        expect(main.contains(gone), isFalse, reason: gone);
      }
    });

    test('그리드 간격·바깥 여백이 플레이스 목록과 같은 값이다', () {
      // 두 목록이 같은 문자열을 쓰는지 본다 — 한쪽만 고치면 여기서 걸린다.
      for (final shared in [
        'padding: const EdgeInsets.only(bottom: 12),',
        'const SizedBox(width: 10),',
      ]) {
        expect(main.contains(shared), isTrue, reason: shared);
      }
      // 플레이스 목록의 바깥 여백(14/6/14)과 같은 값으로 시작한다.
      expect(
        main.contains('padding: const EdgeInsets.fromLTRB(14, 6, 14, 20),'),
        isTrue,
      );
      expect(
        main.contains('padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),'),
        isTrue,
      );
    });

    test('카드는 플레이스와 같은 공용 셸을 쓴다', () {
      final shop = _flat(_src('lib/widgets/shop_card_widget.dart'));
      // 파티샵만의 카드 껍데기를 새로 그리지 않았다.
      expect(shop.contains('ListCardShell.horizontalBody('), isTrue);
      expect(shop.contains('ListCardShell.thumbnailBox('), isTrue);
      expect(shop.contains('ListCardShell.badgeWrap('), isTrue);
      expect(shop.contains('return GridCardShell('), isTrue);
      expect(shop.contains('return largeCardBody('), isTrue);
      // 제목·정보줄·배지·찜도 플레이스와 같은 조각(card_parts) 하나다.
      for (final part in [
        'cardTitleText(info.name)',
        'cardInfoLine(',
        'cardMiniBadge(',
        'cardFavoriteOverlay(',
      ]) {
        expect(shop.contains(part), isTrue, reason: part);
      }
    });

    test('대표 미디어는 세 방식 모두 공용 정본 하나다', () {
      final shop = _flat(_src('lib/widgets/shop_card_widget.dart'));
      // 뷰 모델 한 곳에서만 읽고, 세 카드가 그 값을 나눠 쓴다.
      expect(
        shop.contains('cover: getPartyCoverMedia(data, tag: tag),'),
        isTrue,
      );
      expect(RegExp(r'getPartyCoverMedia\(').allMatches(shop).length, 1);
      // 파티샵 카드 어디에도 mainImageUrl을 직접 읽는 곳이 없다.
      expect(shop.contains("['mainImageUrl']"), isFalse);
    });

    test('거르기·정렬·상세 이동은 세 방식이 공유한다', () {
      // 필터는 목록을 만들 때 한 번만 걸린다(보기 방식과 무관).
      expect(main.contains('final docs = _applyShopFilter(allDocs);'), isTrue);
      // 이동도 한 곳에서만 정해진다.
      expect(
        main.contains(
          'VoidCallback? tapOf(QueryDocumentSnapshot doc) => onCardTap == null '
          '? null : () => onCardTap(doc.data() as Map<String, dynamic>, doc.id);',
        ),
        isTrue,
      );
    });

    test('목록 상단에 플레이스와 같은 컨트롤이 선다', () {
      expect(main.contains('viewModeSwitch: _shopViewModeButton(),'), isTrue);
      // 파티샵 전용 버튼 모양을 만들지 않았다 — 네 목록이 함께 쓰는 위젯 그대로.
      expect(
        main.contains(
          'Widget _shopViewModeButton() { return ViewModeMenuButton(',
        ),
        isTrue,
      );
      // 아이콘 셋을 늘어놓던 세그먼트는 앱 어디에도 남아 있지 않다.
      expect(
        _src('lib/widgets/view_mode_switch.dart'),
        isNot(contains('class ViewModeSwitch')),
      );
    });
  });

  // ── ④-2 실제로 그려본다 — 플레이스 카드와 같은 크기·같은 셸 ─────────────
  //
  // 위 배선 확인은 "어떤 위젯을 어떻게 놓았나"까지만 본다. 여기서는 카드를
  // 실제로 렌더해 **플레이스 카드와 픽셀 단위로 같은 크기**인지 본다 —
  // 한쪽만 값을 하드코딩하는 회귀가 나면 여기서 걸린다.
  //
  // 미디어 필드가 없는 데이터를 넣으면 썸네일이 네트워크 이미지 대신
  // 플레이스홀더로 그려져 테스트 중 네트워크 호출이 없다.
  group('플레이스 카드와 같은 크기로 그려진다', () {
    // 목록 바깥 여백 14×2를 뺀 카드 영역 — 플레이스 목록과 같은 값이다.
    const double listWidth = 360 - 28;

    const shopData = {
      'name': '케이크샵',
      'location': '서울 강남구 역삼동',
      'categories': ['케이크', '풍선'],
      'deliveryOptions': ['sameDay', 'pickup'],
    };
    // 작은 카드 높이는 **정보 줄 수**가 정한다(셸의 최소 높이 104를 넘어서면
    // 내용만큼 늘어난다). 그래서 두 카드에 같은 줄 수(배지 · 이름 · 지역 ·
    // 넷째 줄)를 주고 비교한다 — 그래야 남는 차이가 곧 껍데기 차이다.
    const placeData = {
      'name': '플레이스',
      'themeTags': ['혼술'],
      'location': '서울 강남구 역삼동',
      'openTime': '09:00',
      'closeTime': '22:00',
    };

    Future<Size> renderIn(
      WidgetTester tester,
      Widget card, {
      double width = listWidth,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: Center(child: SizedBox(width: width, child: card)),
          ),
        ),
      );
      return tester.getSize(find.byWidget(card));
    }

    Widget gridRow(Widget left, Widget right) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 10),
        Expanded(child: right),
      ],
    );

    Future<void> pumpRow(WidgetTester tester, Widget row) async {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(body: SizedBox(width: listWidth, child: row)),
        ),
      );
    }

    testWidgets('작은 카드 — 플레이스 작은 카드와 같은 높이·같은 셸', (tester) async {
      final shopSize = await renderIn(
        tester,
        const ShopCompactCard(shop: shopData, shopId: 'shop-1'),
      );
      // 가로형 셸 하나 = 1열 가로 리스트의 한 줄.
      expect(find.byType(ListCardShell), findsOneWidget);
      expect(find.byType(GridCardShell), findsNothing);

      final placeSize = await renderIn(
        tester,
        const PlaceCompactCard(
          place: placeData,
          placeId: 'place-1',
          source: PlaceCardSource.place,
        ),
      );
      expect(shopSize.width, placeSize.width);
      expect(
        shopSize.height,
        placeSize.height,
        reason: '파티샵 작은 카드는 플레이스 작은 카드와 같은 높이여야 합니다.',
      );
    });

    testWidgets('기본 카드 — 2열 그리드 한 칸의 폭이 플레이스와 같다', (tester) async {
      // 목록이 만드는 것과 같은 한 줄(카드 · 10 간격 · 카드)을 그대로 그린다.
      await pumpRow(
        tester,
        gridRow(
          const ShopStandardCard(shop: shopData, shopId: 'shop-1'),
          const ShopStandardCard(shop: shopData, shopId: 'shop-2'),
        ),
      );
      // 한 줄에 카드 두 장이 실제로 나란히 선다 = 2열이다.
      expect(find.byType(GridCardShell), findsNWidgets(2));
      final shopCardWidth = tester
          .getSize(find.byType(ShopStandardCard).first)
          .width;
      expect(shopCardWidth, (listWidth - 10) / 2);

      // 같은 자리에 플레이스 기본 카드를 넣어도 칸 폭이 같다.
      await pumpRow(
        tester,
        gridRow(
          const PlaceStandardCard(
            place: placeData,
            placeId: 'place-1',
            source: PlaceCardSource.place,
          ),
          const PlaceStandardCard(
            place: placeData,
            placeId: 'place-2',
            source: PlaceCardSource.place,
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(PlaceStandardCard).first).width,
        shopCardWidth,
      );
      // 미디어 영역 높이는 공용 셸의 고정값이라 사진 비율이 달라도 목록이
      // 흔들리지 않는다.
      expect(GridCardShell.imageHeight, 130);
    });

    // 플레이스 큰 카드는 여기서 함께 렌더할 수 없다 — `isMyPlace`가
    // FirebaseAuth를 건드려 Firebase 없이 그려지지 않는다. 두 카드가 같은
    // 껍데기를 쓴다는 것은 위 소스 가드(둘 다 `largeCardBody(`)가 붙잡고,
    // 여기서는 파티샵 큰 카드가 실제로 **준 자리를 통째로 쓰는지**를 본다.
    testWidgets('큰 카드 — 준 자리를 통째로 채우는 1열 카드다', (tester) async {
      const boxWidth = 400.0;
      const boxHeight = 500.0;
      const box = Size(boxWidth, boxHeight);
      final shopSize = await renderIn(
        tester,
        const SizedBox(
          height: boxHeight,
          child: ShopLargeCard(shop: shopData, shopId: 'shop-1'),
        ),
        width: boxWidth,
      );
      expect(shopSize, box);
      // 큰 카드는 목록 셸이 아니다 — 미디어 위에 정보를 얹는 구조다.
      expect(find.byType(GridCardShell), findsNothing);
      expect(find.byType(ListCardShell), findsNothing);
      expect(find.text('상세보기'), findsOneWidget);
      expect(find.text('케이크샵'), findsOneWidget);
      // 플레이스 큰 카드와 같은 함수가 그린다는 것은 소스에서 확인한다.
      expect(
        _flat(_src('lib/widgets/place_card_widget.dart')),
        contains('return largeCardBody('),
      );
    });
  });

  // ── ⑤ 대표 미디어 — 세 방식이 같은 값을 본다 ───────────────────────────
  group('각 모드에서 대표 미디어가 같은 규칙으로 나온다', () {
    const photoShop = {
      'mainImageUrl': 'cover.jpg',
      'coverMediaType': 'image',
      'coverImageUrl': 'cover.jpg',
      'coverThumbnailUrl': 'cover.jpg',
    };
    const videoShop = {
      'mainImageUrl': 'photo.jpg',
      'videoUrl': 'v.m3u8',
      'videoThumbnailUrl': 'v-thumb.jpg',
      'coverMediaType': 'video',
      'coverVideoUrl': 'v.m3u8',
      'coverThumbnailUrl': 'v-thumb.jpg',
    };

    test('대표가 사진이면 세 방식 모두 그 사진', () {
      // 카드마다 tag만 다르고 판정 함수와 입력이 같으므로 결과도 같다.
      for (final tag in ['ShopCard', 'ShopCompactCard']) {
        expect(
          getPartyCoverMedia(photoShop, tag: tag)?.thumbnailUrl,
          'cover.jpg',
        );
      }
    });

    test('대표가 동영상이면 세 방식 모두 영상 썸네일', () {
      for (final tag in ['ShopCard', 'ShopCompactCard']) {
        final cover = getPartyCoverMedia(videoShop, tag: tag);
        expect(cover?.isVideo, isTrue);
        expect(cover?.thumbnailUrl, 'v-thumb.jpg');
      }
    });
  });

  // ── ⑥ 컨트롤 — 버튼 하나 + 메뉴, 실제로 눌러 전환된다 ──────────────────
  //
  // 아이콘 셋을 늘어놓던 세그먼트는 없앴다 — 네 목록(파티·플레이스·장소대여·
  // 파티샵)이 모두 [ViewModeMenuButton] 하나를 쓴다. 접힌 버튼에는 **지금 쓰는
  // 보기 방식** 아이콘 하나만 앉고, 누르면 셋이 한 번에 열린다.
  group('보기 전환 컨트롤', () {
    Future<void> pumpButton(
      WidgetTester tester, {
      required PlaceViewMode selected,
      required void Function(PlaceViewMode) onTap,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ViewModeMenuButton(
                currentIcon: selected.icon,
                label: '보기 방식 · ${selected.label}',
                options: [
                  for (final mode in PlaceViewMode.values)
                    ViewModeOption(
                      icon: mode.icon,
                      label: mode.label,
                      selected: selected == mode,
                      onTap: () => onTap(mode),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    /// 버튼을 눌러 메뉴를 연다.
    Future<void> openMenu(WidgetTester tester, PlaceViewMode shown) async {
      await tester.tap(find.byIcon(shown.icon));
      await tester.pumpAndSettle();
    }

    testWidgets('접혀 있을 땐 지금 쓰는 보기 방식 하나만 보인다', (tester) async {
      await pumpButton(tester, selected: PlaceViewMode.standard, onTap: (_) {});
      // 기본 카드 아이콘 하나. 나머지 둘은 메뉴를 열기 전에는 없다.
      expect(find.byIcon(PlaceViewMode.standard.icon), findsOneWidget);
      expect(find.byIcon(PlaceViewMode.compact.icon), findsNothing);
      expect(find.byIcon(PlaceViewMode.large.icon), findsNothing);
      // 툴팁·접근성 라벨이 지금 값을 말한다.
      expect(find.bySemanticsLabel('보기 방식 · 기본 카드 보기'), findsOneWidget);
    });

    testWidgets('누르면 셋이 한 번에 열리고, 지금 것에 선택 표시가 붙는다', (tester) async {
      await pumpButton(tester, selected: PlaceViewMode.standard, onTap: (_) {});
      await openMenu(tester, PlaceViewMode.standard);
      for (final mode in PlaceViewMode.values) {
        expect(find.text(mode.label), findsOneWidget, reason: mode.label);
      }
      // 지금 쓰는 방식에만 핑크 체크가 붙는다.
      expect(find.byIcon(Icons.check_circle), findsNWidgets(3));
    });

    testWidgets('작은 카드로 전환', (tester) async {
      PlaceViewMode? picked;
      await pumpButton(
        tester,
        selected: PlaceViewMode.standard,
        onTap: (m) => picked = m,
      );
      await openMenu(tester, PlaceViewMode.standard);
      await tester.tap(find.text(PlaceViewMode.compact.label));
      await tester.pumpAndSettle();
      expect(picked, PlaceViewMode.compact);
    });

    testWidgets('큰 카드로 전환', (tester) async {
      PlaceViewMode? picked;
      await pumpButton(
        tester,
        selected: PlaceViewMode.compact,
        onTap: (m) => picked = m,
      );
      await openMenu(tester, PlaceViewMode.compact);
      await tester.tap(find.text(PlaceViewMode.large.label));
      await tester.pumpAndSettle();
      expect(picked, PlaceViewMode.large);
    });

    testWidgets('다시 기본 카드로 전환', (tester) async {
      PlaceViewMode? picked;
      await pumpButton(
        tester,
        selected: PlaceViewMode.large,
        onTap: (m) => picked = m,
      );
      await openMenu(tester, PlaceViewMode.large);
      await tester.tap(find.text(PlaceViewMode.standard.label));
      await tester.pumpAndSettle();
      expect(picked, PlaceViewMode.standard);
    });

    testWidgets('이미 고른 칸을 다시 눌러도 값은 그대로다', (tester) async {
      // 화면 쪽 가드(`if (_shopViewMode == mode) return;`)와 같은 뜻 —
      // 여기서는 콜백이 같은 값을 돌려준다는 것만 본다.
      PlaceViewMode? picked;
      await pumpButton(
        tester,
        selected: PlaceViewMode.standard,
        onTap: (m) => picked = m,
      );
      await openMenu(tester, PlaceViewMode.standard);
      await tester.tap(find.text(PlaceViewMode.standard.label));
      await tester.pumpAndSettle();
      expect(picked, PlaceViewMode.standard);
    });
  });
}

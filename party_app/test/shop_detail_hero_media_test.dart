// 🛍️ 파티샵 상세 **상단 대표 미디어** — 파티추 상세와 같은 위젯·같은 규칙.
//
// ── 무엇이 문제였나 ──────────────────────────────────────────────────────────
// 파티샵 상세만 아직 옛 구조였다: `SliverAppBar(expandedHeight: 260)` +
// `FlexibleSpaceBar` 안에 사진을 넣는 방식. 박스 높이가 260으로 **고정**이라
// 360×260(가로로 긴 상자) 안에 3:4 세로 사진을 contain으로 넣으면 사진은
// 195×260으로 줄고 좌우 165px이 블러 배경으로 남는다 — 첨부 화면의 그 빈칸이
// 정확히 이것이다.
//
// 파티추 상세(그리고 매장·장소대여 상세)는 [MediaGallery]를 쓴다. 이쪽은
// **지금 페이지 사진의 원본 비율로 박스 높이를 정한다**(화면폭 ÷ 비율).
// 그래서 세로 사진이면 상자가 세로로 길어지고, 사진이 폭을 꽉 채운다.
//
// ── 무엇을 붙잡는가 ──────────────────────────────────────────────────────────
// ① 세로/가로/정사각 사진 각각에서 박스가 **화면 폭을 꽉 채우고**, 높이가
//    원본 비율을 따라간다(= 좌우 빈칸이 생기지 않는다).
// ② 좁은 화면(360)에서 오버플로가 없다.
// ③ 파티샵 상세가 실제로 그 위젯을 파티추 상세와 **같은 인자**로 부른다.
// ④ 고정 높이 헤더(260 + FlexibleSpaceBar)는 사라졌다.
//
// ①은 실제 렌더로, ③④는 소스 가드로 본다(상세 화면은 Firestore 없이 그릴 수
// 없다). 원본 비율을 알려면 이미지가 실제로 디코드돼 있어야 하므로, 테스트용
// 단색 이미지를 이미지 캐시에 미리 심어 네트워크 없이 같은 경로를 태운다.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/widgets/media_gallery.dart';

String _src(String path) => File(path).readAsStringSync();

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

/// 지정한 크기의 단색 이미지 하나 — 원본 비율만 있으면 되므로 내용은 상관없다.
Future<ui.Image> _image(int width, int height) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFFFF6FA0),
  );
  return recorder.endRecording().toImage(width, height);
}

/// [url]을 요청하면 [width]×[height] 이미지가 나오도록 이미지 캐시에 심는다.
///
/// [NetworkImage]는 url·scale이 같으면 같은 키라, 미리 넣어 두면 위젯이
/// 부르는 `resolve`가 네트워크를 타지 않고 이 항목을 그대로 받는다 —
/// [MediaGallery]가 비율을 읽는 경로(`ImageStreamListener`)는 실제와 똑같다.
void _stubImage(String url, ui.Image image) {
  imageCache.putIfAbsent(
    NetworkImage(url),
    () => OneFrameImageStreamCompleter(
      Future.value(ImageInfo(image: image, scale: 1)),
    ),
  );
}

void main() {
  // 좁은 흔한 기기 폭. 높이는 넉넉히 둔다 — MediaGallery는 화면 높이의 75%를
  // 상한으로 두므로, 상한에 걸리지 않는 자리에서 비율 규칙 자체를 본다.
  const width = 360.0;
  const height = 800.0;

  // imageCache는 바인딩이 선 뒤에야 있다 — main 본문에서 곧바로 만지면
  // "Binding has not yet been initialized"로 파일이 통째로 로드에 실패한다.
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(imageCache.clear);

  Future<Size> pumpGallery(
    WidgetTester tester, {
    required List<String> images,
  }) async {
    tester.view.physicalSize = const Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: MediaGallery(images: images)),
        ),
      ),
    );
    // 캐시에 심어 둔 이미지는 다음 프레임에 리스너로 전달된다.
    await tester.pump();
    await tester.pump();
    return tester.getSize(find.byType(MediaGallery));
  }

  group('원본 비율대로 높이가 정해진다 — 좌우 빈칸이 생기지 않는다', () {
    testWidgets('세로 사진 (3:4) — 폭을 꽉 채우고 세로로 길어진다', (tester) async {
      const url = 'https://example.com/portrait.jpg';
      late Size size;
      await tester.runAsync(() async => _stubImage(url, await _image(300, 400)));
      size = await pumpGallery(tester, images: const [url]);

      // 폭은 언제나 화면 전부 — 세로 사진이라고 가운데로 좁아지지 않는다.
      expect(size.width, width);
      // 높이 = 폭 ÷ 비율 = 360 ÷ 0.75 = 480. 옛 고정 헤더(260)라면 이 값이
      // 나올 수 없고, 남는 165px이 좌우 블러로 갔다.
      expect(size.height, closeTo(width / 0.75, 0.5));
    });

    testWidgets('가로 사진 (4:3) — 높이가 그만큼 낮아진다', (tester) async {
      const url = 'https://example.com/landscape.jpg';
      await tester.runAsync(() async => _stubImage(url, await _image(400, 300)));
      final size = await pumpGallery(tester, images: const [url]);

      expect(size.width, width);
      expect(size.height, closeTo(width / (4 / 3), 0.5));
    });

    testWidgets('정사각 사진 (1:1) — 정확히 정사각 박스', (tester) async {
      const url = 'https://example.com/square.jpg';
      await tester.runAsync(() async => _stubImage(url, await _image(400, 400)));
      final size = await pumpGallery(tester, images: const [url]);

      expect(size.width, width);
      expect(size.height, closeTo(width, 0.5));
    });

    testWidgets('360px에서 오버플로가 없다', (tester) async {
      const url = 'https://example.com/portrait.jpg';
      final errors = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (d) => errors.add(d.exceptionAsString());
      try {
        await tester.runAsync(
          () async => _stubImage(url, await _image(300, 400)),
        );
        await pumpGallery(tester, images: const [url]);
      } finally {
        FlutterError.onError = previous;
      }
      tester.takeException();
      expect(
        errors.where((e) => e.contains('OVERFLOW')),
        isEmpty,
        reason: '오버플로가 났다: $errors',
      );
    });

    testWidgets('여러 장이면 파티추 상세와 같은 페이지 넘기기·인디케이터가 붙는다', (tester) async {
      const a = 'https://example.com/a.jpg';
      const b = 'https://example.com/b.jpg';
      await tester.runAsync(() async {
        _stubImage(a, await _image(300, 400));
        _stubImage(b, await _image(400, 300));
      });
      await pumpGallery(tester, images: const [a, b]);

      expect(find.byType(PageView), findsOneWidget);
      // 우측 상단 카운터 — 시트를 새로 그리지 않고 공용 위젯이 붙여 준다.
      expect(find.text('1 / 2'), findsOneWidget);
    });
  });

  // ── 배선 — 파티샵 상세가 그 위젯을 파티추 상세와 같은 인자로 부른다 ──────
  group('파티샵 상세 상단이 공용 미디어 위젯을 쓴다', () {
    final shop = _flat(_src('lib/screens/party_shop_detail_screen.dart'));
    final party = _flat(_src('lib/screens/party_detail_screen.dart'));
    final event = _flat(_src('lib/screens/event_detail_screen.dart'));

    test('MediaGallery를 쓴다 — 파티샵 전용 대표 미디어 위젯을 새로 만들지 않았다', () {
      expect(shop.contains('MediaGallery( images: allImgUrls,'), isTrue);
      // 파티추 상세와 같은 표시 기준(원본 비율 · 배경 톤 · 카운터 색).
      for (final arg in [
        'videoFit: BoxFit.contain,',
        'counterAccentColor: const Color(0xFFFF6FA0),',
      ]) {
        expect(shop.contains(arg), isTrue, reason: arg);
        expect(party.contains(arg), isTrue, reason: '파티 상세: $arg');
      }
      // 매장 상세와는 여백 톤까지 같다(두 화면의 배경색이 같다).
      expect(
        shop.contains('videoBackgroundColor: const Color(0xFFFFF4F8),'),
        isTrue,
      );
      expect(
        event.contains('videoBackgroundColor: const Color(0xFFFFF4F8),'),
        isTrue,
      );
    });

    test('대표 미디어 판정·순서는 파티샵의 기존 정본 그대로다', () {
      // 무엇이 대표인가 — 앱 공용 정본 하나.
      expect(
        shop.contains("getPartyCoverMedia(shopData, tag: 'PartyShopDetail')"),
        isTrue,
      );
      // 대표가 동영상이면 맨 앞, 사진이면 그 사진을 맨 앞으로 — 매장 상세와
      // 같은 네 줄이다.
      expect(shop.contains('videoFirst: videoIsCover,'), isTrue);
      expect(
        shop.contains('final idx = allImgUrls.indexOf(cover!.imageUrl!);'),
        isTrue,
      );
      expect(event.contains('final idx = allImgUrls.indexOf(cover!.imageUrl!);'), isTrue);
      // 저장 필드는 예전 그대로 읽는다.
      expect(shop.contains("shopData['mainImageUrl']"), isTrue);
      expect(shop.contains("shopData['introImageUrls']"), isTrue);
    });

    test('고정 높이 헤더(260 + FlexibleSpaceBar)는 사라졌다', () {
      for (final gone in [
        'expandedHeight: (allImgUrls.isNotEmpty || hasVideo) ? 260 : 120,',
        'flexibleSpace: FlexibleSpaceBar(',
      ]) {
        expect(shop.contains(gone), isFalse, reason: gone);
      }
    });

    test('동영상 분기를 이미지 전용으로 새로 만들지 않았다', () {
      // 대표 미디어의 동영상은 MediaGallery가 그린다 — 상세 화면에 남은
      // 캐러셀(_ImageCarousel)은 상품 시트 전용이고 동영상을 모른다.
      expect(shop.contains('class _ImageCarousel extends StatefulWidget'), isTrue);
      expect(shop.contains('GalleryVideoItem('), isFalse);
      expect(shop.contains('_ImageCarousel({required this.imageUrls});'), isTrue);
      // 상품 시트의 호출부는 그대로다(이번 작업 대상 아님).
      expect(shop.contains('_ImageCarousel(imageUrls: imgUrls)'), isTrue);
    });
  });
}

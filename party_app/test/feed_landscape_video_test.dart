import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/widgets/feed_landscape_video.dart';

// 실제 VideoPlayer 대신 크기를 잴 수 있는 자리표시 — 가운데/배경이 몇 번,
// 어떤 크기로 그려졌는지만 본다.
Widget _fakePlayer() =>
    const ColoredBox(key: ValueKey('fake-player'), color: Color(0xFF00FF00));

Future<void> _pump(
  WidgetTester tester, {
  required double aspectRatio,
  Size screen = const Size(390, 844),
  bool? forceWeb,
  Widget? webBackdrop,
}) async {
  tester.view.physicalSize = screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: FeedLandscapeVideo(
        aspectRatio: aspectRatio,
        player: _fakePlayer,
        forceWeb: forceWeb,
        webBackdrop: webBackdrop,
      ),
    ),
  );
}

void main() {
  group('isLandscapeVideoSize — 실제 영상 크기로만 판정', () {
    test('가로가 더 길면 가로형', () {
      expect(isLandscapeVideoSize(const Size(1920, 1080)), isTrue);
      expect(isLandscapeVideoSize(const Size(1280, 720)), isTrue);
    });

    test('세로형·정사각형은 기존 방식', () {
      expect(isLandscapeVideoSize(const Size(1080, 1920)), isFalse);
      expect(isLandscapeVideoSize(const Size(1080, 1080)), isFalse);
    });

    test('아직 크기를 모르면(0) 가로로 추정하지 않는다', () {
      expect(isLandscapeVideoSize(Size.zero), isFalse);
      expect(isLandscapeVideoSize(const Size(1920, 0)), isFalse);
    });
  });

  group('FeedLandscapeVideo', () {
    for (final screen in const [
      Size(360, 740),
      Size(390, 844),
      Size(412, 915),
      Size(430, 932),
    ]) {
      testWidgets('${screen.width.toInt()}폭: 가운데 영상은 화면 폭 전체, 16:9 그대로', (
        tester,
      ) async {
        await _pump(tester, aspectRatio: 16 / 9, screen: screen);
        final fg = tester.getRect(
          find.byKey(const ValueKey('landscape-foreground')),
        );
        // 좌우 잘림 없음 — 화면 폭에 딱 맞는다.
        expect(fg.width, closeTo(screen.width, 0.01));
        // 찌그러짐 없음 — 원본 비율 그대로.
        expect(fg.width / fg.height, closeTo(16 / 9, 0.001));
        // 가운데 정렬 — 위/아래 여백이 같다.
        expect(fg.top, closeTo(screen.height - fg.bottom, 0.01));
        expect(fg.top, greaterThan(0));
      });
    }

    testWidgets('배경은 같은 영상을 cover로 키워 블러 + 어둡게', (tester) async {
      await _pump(tester, aspectRatio: 16 / 9);
      // 같은 영상 화면이 두 번(배경·가운데) — 같은 컨트롤러에서 나온다.
      expect(find.byKey(const ValueKey('fake-player')), findsNWidgets(2));

      final blur = tester.widget<ImageFiltered>(
        find.byKey(const ValueKey('landscape-backdrop')),
      );
      expect(blur.imageFilter, isA<ImageFilter>());

      // 배경 영상은 화면 높이를 꽉 채운다(cover).
      final players = tester.getRect(
        find.byKey(const ValueKey('fake-player')).first,
      );
      expect(players.height, closeTo(844, 0.01));

      final dim = tester
          .widgetList<ColoredBox>(find.byType(ColoredBox))
          .where(
            (b) =>
                b.color == Colors.black.withValues(alpha: landscapeBackdropDim),
          );
      expect(dim, hasLength(1));
    });

    testWidgets('웹은 영상을 두 번 붙이지 않고 썸네일을 배경으로', (tester) async {
      await _pump(
        tester,
        aspectRatio: 16 / 9,
        forceWeb: true,
        webBackdrop: const SizedBox(key: ValueKey('thumb')),
      );
      expect(find.byKey(const ValueKey('fake-player')), findsOneWidget);
      expect(find.byKey(const ValueKey('thumb')), findsOneWidget);
    });

    testWidgets('웹에 썸네일도 없으면 검은 배경 + 가운데 영상만', (tester) async {
      await _pump(tester, aspectRatio: 16 / 9, forceWeb: true);
      expect(find.byKey(const ValueKey('fake-player')), findsOneWidget);
      expect(find.byKey(const ValueKey('landscape-backdrop')), findsNothing);
    });
  });

  test('세로 영상 분기는 큰 카드에서도 기존 표시(CroppedMedia)를 탄다', () {
    // VideoThumbnail은 isLandscapeVideoSize가 true일 때만 FeedLandscapeVideo로
    // 간다 — 세로·정사각은 이 판정이 false라 예전 CroppedMedia 경로 그대로다.
    expect(isLandscapeVideoSize(const Size(720, 1280)), isFalse);
  });
}

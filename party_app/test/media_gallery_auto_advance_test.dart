// 상세 화면 갤러리의 사진·영상 자동 넘김(MediaGallery.autoAdvance).
//
// 큰 화면 보기와 같은 규칙이다 — 영상이 있으면 영상이 첫 칸, 사진은 4초씩,
// 마지막 다음은 첫 칸으로 순환한다. 켜지 않은 화면은 예전 그대로다.
//
// 위젯 테스트의 NetworkImage는 실제 요청을 시도하다 실패한다. 자동 넘김은
// 실패한 사진도 "불러오기 끝"으로 보고 넘기므로(멈춰 있지 않게) 여기서는
// 그 경로로 시간을 잰다. 이미지 오류 자체는 이 테스트의 관심사가 아니다.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'package:video_player/video_player.dart';

import 'package:party_app/widgets/media_auto_advance.dart';
import 'package:party_app/widgets/media_gallery.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

/// 이미지 로드 실패 오류는 삼키고 화면만 진행시킨다.
Future<void> _pump(WidgetTester tester, [Duration? d]) async {
  final previous = FlutterError.onError;
  FlutterError.onError = (_) {};
  try {
    await tester.pump(d);
  } finally {
    FlutterError.onError = previous;
  }
}

/// 네트워크 이미지 실패가 실제 시간 속에서 도착하게 한다.
Future<void> _settleImages(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await _pump(tester);
  }
}

void main() {
  setUpAll(() {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  testWidgets('사진만: 4초마다 다음, 마지막 다음은 첫 사진', (tester) async {
    final previous = FlutterError.onError;
    FlutterError.onError = (_) {};
    await tester.pumpWidget(
      _host(const MediaGallery(images: ['a', 'b', 'c'], autoAdvance: true)),
    );
    FlutterError.onError = previous;
    await _settleImages(tester);
    await _pump(tester);
    expect(find.text('1 / 3'), findsOneWidget);

    await _pump(tester, const Duration(milliseconds: 4100));
    await _pump(tester, const Duration(milliseconds: 500));
    expect(find.text('2 / 3'), findsOneWidget);

    await _pump(tester, const Duration(milliseconds: 4100));
    await _pump(tester, const Duration(milliseconds: 500));
    expect(find.text('3 / 3'), findsOneWidget);

    // 마지막 사진 다음은 첫 사진이다.
    await _pump(tester, const Duration(milliseconds: 4100));
    await _pump(tester, const Duration(milliseconds: 500));
    expect(find.text('1 / 3'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('첫 사진에서 오른쪽으로 넘기면 마지막 사진', (tester) async {
    final previous = FlutterError.onError;
    FlutterError.onError = (_) {};
    await tester.pumpWidget(
      _host(const MediaGallery(images: ['a', 'b', 'c'], autoAdvance: true)),
    );
    FlutterError.onError = previous;
    await _pump(tester);
    await tester.fling(find.byType(PageView), const Offset(300, 0), 1000);
    for (var i = 0; i < 10; i++) {
      await _pump(tester, const Duration(milliseconds: 100));
    }
    expect(find.text('3 / 3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('자동 넘김을 켜면 영상이 대표가 아니어도 첫 칸이다', (tester) async {
    final previous = FlutterError.onError;
    FlutterError.onError = (_) {};
    await tester.pumpWidget(
      _host(
        const MediaGallery(
          images: ['a', 'b'],
          videoUrl: 'https://example.com/v.m3u8',
          autoAdvance: true,
        ),
      ),
    );
    FlutterError.onError = previous;
    await _pump(tester);
    expect(find.text('1 / 3'), findsOneWidget);
    // 첫 칸이 영상 페이지다(카운터에 재생 아이콘이 붙는다).
    expect(find.byType(GalleryVideoItem), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
    // 테스트에는 영상 플레이어가 없어 재시도 끝에 실패한다 — 그 대기 타이머를
    // 다 흘려보낸 뒤 정리한다(실패한 영상은 멈추지 않고 다음 칸으로 넘어간다).
    for (var i = 0; i < 40; i++) {
      await _pump(tester, const Duration(seconds: 1));
    }
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, const Duration(seconds: 30));
  });

  testWidgets('사진 10장 — 끝까지 진행하고 마지막 뒤 1번으로 돌아온다', (tester) async {
    // 공공 축제 상세가 실제로 이 모양이다(대표 + detailImage2 최대 10장).
    final images = [for (var i = 0; i < 10; i++) 'p$i'];
    final previous = FlutterError.onError;
    FlutterError.onError = (_) {};
    await tester.pumpWidget(
      _host(MediaGallery(images: images, autoAdvance: true)),
    );
    FlutterError.onError = previous;
    await _settleImages(tester);
    await _pump(tester);
    expect(find.text('1 / 10'), findsOneWidget);

    for (var page = 2; page <= 10; page++) {
      await _pump(tester, const Duration(milliseconds: 4100));
      await _pump(tester, const Duration(milliseconds: 500));
      expect(find.text('$page / 10'), findsOneWidget, reason: '$page번째로 진행');
    }
    // 마지막(10) 다음은 1번이다 — 끝에서 멈추지 않는다.
    await _pump(tester, const Duration(milliseconds: 4100));
    await _pump(tester, const Duration(milliseconds: 500));
    expect(find.text('1 / 10'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('손으로 넘기면 그 사진부터 4초를 다시 센다', (tester) async {
    final previous = FlutterError.onError;
    FlutterError.onError = (_) {};
    await tester.pumpWidget(
      _host(const MediaGallery(images: ['a', 'b', 'c'], autoAdvance: true)),
    );
    FlutterError.onError = previous;
    await _settleImages(tester);
    await _pump(tester);

    // 3초쯤 기다렸다가(자동으로 넘어가기 전에) 손으로 다음 장으로 넘긴다.
    await _pump(tester, const Duration(milliseconds: 3000));
    expect(find.text('1 / 3'), findsOneWidget);
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    for (var i = 0; i < 10; i++) {
      await _pump(tester, const Duration(milliseconds: 100));
    }
    expect(find.text('2 / 3'), findsOneWidget);

    // 넘긴 직후부터 다시 4초다 — 남아 있던 1초로 곧장 넘어가면 안 된다.
    await _pump(tester, const Duration(milliseconds: 3000));
    expect(find.text('2 / 3'), findsOneWidget, reason: '4초가 새로 시작해야 한다');

    await _pump(tester, const Duration(milliseconds: 1500));
    await _pump(tester, const Duration(milliseconds: 500));
    expect(find.text('3 / 3'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('사진 1장 — 넘길 것이 없어 자동 넘김이 돌지 않는다', (tester) async {
    final previous = FlutterError.onError;
    FlutterError.onError = (_) {};
    await tester.pumpWidget(
      _host(const MediaGallery(images: ['only'], autoAdvance: true)),
    );
    FlutterError.onError = previous;
    await _settleImages(tester);
    await _pump(tester);

    // 장수 표시와 점은 두 장부터 붙는다 — 한 장이면 아예 없다.
    expect(find.textContaining(' / '), findsNothing);
    // 한참 둬도 아무 일도 일어나지 않는다(페이지 애니메이션도 없다).
    await _pump(tester, const Duration(seconds: 10));
    expect(find.textContaining(' / '), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('자동 넘김을 켜지 않으면 예전처럼 영상이 마지막', (tester) async {
    final previous = FlutterError.onError;
    FlutterError.onError = (_) {};
    await tester.pumpWidget(
      _host(
        const MediaGallery(
          images: ['a', 'b'],
          videoUrl: 'https://example.com/v.m3u8',
        ),
      ),
    );
    FlutterError.onError = previous;
    await _pump(tester);
    expect(find.byType(GalleryVideoItem), findsNothing);
    expect(find.byIcon(Icons.play_circle_outline), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  group('순서 규칙(순수)', () {
    test('영상이 있으면 영상 → 사진1 → 사진2 …', () {
      final seq = autoMediaSequence(
        images: ['p1', 'p2', 'p3'],
        videoUrl: 'v.m3u8',
      );
      expect(seq.first.isVideo, isTrue);
      expect(seq.map((m) => m.url).toList(), ['v.m3u8', 'p1', 'p2', 'p3']);
    });

    test('사진만 있으면 사진 순서 그대로', () {
      final seq = autoMediaSequence(images: ['p1', 'p2']);
      expect(seq.every((m) => !m.isVideo), isTrue);
      expect(seq.map((m) => m.url).toList(), ['p1', 'p2']);
    });

    test('마지막 사진 다음은 다시 첫 칸(영상이 있으면 영상)', () {
      // 영상 1 + 사진 3 = 4칸. 마지막(3) 다음은 0번 = 영상이다.
      expect(nextMediaIndex(3, 4), 0);
      expect(nextMediaIndex(0, 4), 1);
      // 사진만 10장이어도 같다.
      expect(nextMediaIndex(9, 10), 0);
    });

    test('영상은 끝까지 재생됐을 때만 다음으로 — 반복 재생은 아니다', () {
      expect(
        videoPlaybackFinished(
          const VideoPlayerValue(duration: Duration(seconds: 3))
              .copyWith(isInitialized: true, isCompleted: true),
        ),
        isTrue,
      );
      expect(
        videoPlaybackFinished(
          const VideoPlayerValue(duration: Duration(seconds: 3))
              .copyWith(isInitialized: true, isCompleted: true, isLooping: true),
        ),
        isFalse,
      );
    });

    test('사진 한 장은 4초', () {
      expect(photoDuration, const Duration(seconds: 4));
    });
  });

  group('상세 화면 연결 — 갤러리가 있는 화면은 모두 켜져 있다', () {
    // 한 화면만 빠뜨려도 그 화면에서만 사진이 멈춘다. 실제로 공공 축제 상세가
    // 그랬다 — 공용 갤러리를 쓰면서 autoAdvance만 켜지 않았다.
    const screens = {
      '파티 상세': 'lib/screens/party_detail_screen.dart',
      '플레이스 상세': 'lib/screens/event_detail_screen.dart',
      '장소대여 상세': 'lib/screens/place_detail_screen.dart',
      '이벤트 상세 시트': 'lib/widgets/place_product/place_promotion_detail_sheet.dart',
      '공공 축제 상세': 'lib/screens/public_event_detail_screen.dart',
      '파티샵 상세': 'lib/screens/party_shop_detail_screen.dart',
    };

    for (final e in screens.entries) {
      test('${e.key} — MediaGallery에 autoAdvance: true', () {
        final src = File(e.value).readAsStringSync();
        expect(
          src.contains('MediaGallery('),
          isTrue,
          reason: '${e.value}가 공용 갤러리를 쓰지 않는다',
        );
        expect(
          src.contains('autoAdvance: true'),
          isTrue,
          reason: '${e.value}에 자동 넘김이 꺼져 있다',
        );
      });
    }

    test('공공 축제 상세는 별도 갤러리를 만들지 않았다', () {
      final src = File(
        'lib/screens/public_event_detail_screen.dart',
      ).readAsStringSync();
      expect(src.contains('PageView'), isFalse);
      expect(src.contains('PageController'), isFalse);
      expect(src.contains('Timer('), isFalse);
    });
  });
}

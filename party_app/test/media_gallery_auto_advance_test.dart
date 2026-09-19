// 상세 화면 갤러리의 사진·영상 자동 넘김(MediaGallery.autoAdvance).
//
// 큰 화면 보기와 같은 규칙이다 — 영상이 있으면 영상이 첫 칸, 사진은 4초씩,
// 마지막 다음은 첫 칸으로 순환한다. 켜지 않은 화면은 예전 그대로다.
//
// 위젯 테스트의 NetworkImage는 실제 요청을 시도하다 실패한다. 자동 넘김은
// 실패한 사진도 "불러오기 끝"으로 보고 넘기므로(멈춰 있지 않게) 여기서는
// 그 경로로 시간을 잰다. 이미지 오류 자체는 이 테스트의 관심사가 아니다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';

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
}

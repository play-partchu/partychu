// 전체화면 사진 뷰어 — 여러 장 넘겨 보기가 붙은 뒤의 동작 잠금.
//
// 이 뷰어는 호스트 승인제 신청자 상세의 '제출 사진'에서 열리고, 파티 상세
// 이미지·플레이스 메뉴판도 같은 위젯을 쓴다. 한 장짜리로 열던 기존 호출부가
// 예전 그대로 동작하는지도 여기서 함께 본다.
//
// 위젯 테스트에는 네트워크가 없어 Image.network가 실패하지만(errorBuilder가
// 받는다), 확인하려는 것은 **넘기기·번호·확대 잠금**이라 그림과 무관하다.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/screens/full_screen_image_viewer.dart';

const _urls = [
  'https://example.com/a.jpg',
  'https://example.com/b.jpg',
  'https://example.com/c.jpg',
];

Future<void> pumpGallery(
  WidgetTester tester, {
  List<String> urls = _urls,
  int initialIndex = 0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: FullScreenImageViewer.gallery(
        imageUrls: urls,
        initialIndex: initialIndex,
      ),
    ),
  );
  await tester.pump();
}

/// 지금 PageView가 쓰는 physics — 확대 중 페이지 잠금을 확인한다.
ScrollPhysics? pagePhysics(WidgetTester tester) =>
    tester.widget<PageView>(find.byType(PageView)).physics;

/// 두 손가락 핀치 — 화면 가운데를 기준으로 [from]만큼 벌어져 있던 손가락을
/// [to]만큼으로 벌리거나 좁힌다(to > from이면 확대).
Future<void> pinch(
  WidgetTester tester, {
  required double from,
  required double to,
}) async {
  final center = tester.getCenter(find.byType(PageView));
  final left = await tester.startGesture(center - Offset(from / 2, 0));
  final right = await tester.startGesture(center + Offset(from / 2, 0));
  // 한 번에 벌리지 않고 나눠 움직인다 — 실제 손가락처럼 여러 번 업데이트가
  // 들어와야 인식기 상태 전이가 실제와 같아진다.
  const steps = 5;
  for (var i = 1; i <= steps; i++) {
    final gap = from + (to - from) * i / steps;
    await left.moveTo(center - Offset(gap / 2, 0));
    await right.moveTo(center + Offset(gap / 2, 0));
    await tester.pump();
  }
  await left.up();
  await right.up();
  await tester.pumpAndSettle();
}

/// 더블탭 — 두 탭 사이 간격을 더블탭 인식 시간 안에 둔다.
Future<void> doubleTap(WidgetTester tester) async {
  await tester.tap(find.byType(PageView));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(find.byType(PageView));
  await tester.pumpAndSettle();
}

/// 플랫폼을 지정해 도는 위젯 테스트.
///
/// setUp/tearDown으로 [debugDefaultTargetPlatformOverride]를 건드리면
/// "foundation debug 변수가 바뀐 채로 테스트가 끝났다"며 프레임워크가 막는다 —
/// 그 검사가 tearDown보다 **먼저** 돌기 때문이다. 그래서 본문 안에서 되돌린다.
void gestureTest(
  String description,
  TargetPlatform platform,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

/// 첫 번째 InteractiveViewer의 확대 컨트롤러.
TransformationController zoomController(WidgetTester tester) => tester
    .widget<InteractiveViewer>(find.byType(InteractiveViewer).first)
    .transformationController!;

void main() {
  group('여러 장 넘겨 보기', () {
    testWidgets('사진 수만큼 페이지가 있고 번호가 뜬다', (tester) async {
      await pumpGallery(tester);

      expect(find.byType(PageView), findsOneWidget);
      expect(
        tester
            .widget<PageView>(find.byType(PageView))
            .childrenDelegate
            .estimatedChildCount,
        3,
      );
      expect(find.text('1 / 3'), findsOneWidget);
    });

    testWidgets('탭한 사진부터 열린다', (tester) async {
      await pumpGallery(tester, initialIndex: 2);

      expect(find.text('3 / 3'), findsOneWidget);
    });

    testWidgets('좌우로 넘기면 번호가 따라 바뀐다', (tester) async {
      await pumpGallery(tester);

      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);

      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('3 / 3'), findsOneWidget);

      // 되돌아가기.
      await tester.fling(find.byType(PageView), const Offset(400, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
    });

    testWidgets('범위를 벗어난 initialIndex는 마지막 장으로 잘린다', (tester) async {
      await pumpGallery(tester, initialIndex: 99);

      expect(find.text('3 / 3'), findsOneWidget);
    });
  });

  group('한 장짜리 — 기존 호출부', () {
    testWidgets('예전 생성자가 그대로 동작하고 번호는 뜨지 않는다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FullScreenImageViewer(imageUrl: 'https://example.com/only.jpg'),
        ),
      );
      await tester.pump();

      expect(find.byType(PageView), findsOneWidget);
      expect(find.textContaining(' / '), findsNothing);
    });

    // 한 장일 때는 넘길 것이 없으니 확대 제스처를 재울 이유도 없다 —
    // 핀치 확대가 이 기능을 붙이기 전과 똑같이 동작해야 한다(파티 상세
    // 이미지·플레이스 메뉴판이 이 경로로 연다).
    testWidgets('한 장이면 확대 제스처를 재우지 않는다 — 핀치가 그대로 산다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FullScreenImageViewer(imageUrl: 'https://example.com/only.jpg'),
        ),
      );
      await tester.pump();

      final ignore = tester.widget<IgnorePointer>(
        find
            .ancestor(
              of: find.byType(InteractiveViewer),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      expect(ignore.ignoring, isFalse);
    });
  });

  group('여러 장일 때의 제스처 주인', () {
    testWidgets('축소 상태에서는 확대 제스처를 재운다 — 스와이프가 먼저다', (tester) async {
      await pumpGallery(tester);

      final ignore = tester.widget<IgnorePointer>(
        find
            .ancestor(
              of: find.byType(InteractiveViewer).first,
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      expect(ignore.ignoring, isTrue);
    });

    testWidgets('확대하면 다시 InteractiveViewer가 주인이 된다', (tester) async {
      await pumpGallery(tester);

      zoomController(tester).value = Matrix4.identity()
        ..scaleByDouble(2.0, 2.0, 2.0, 1.0);
      await tester.pump();

      final ignore = tester.widget<IgnorePointer>(
        find
            .ancestor(
              of: find.byType(InteractiveViewer).first,
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      expect(ignore.ignoring, isFalse);
    });
  });

  group('확대·이동', () {
    testWidgets('원본 비율을 지킨다 — 잘라내지 않는다', (tester) async {
      await pumpGallery(tester);

      final image = tester.widget<Image>(find.byType(Image).first);
      expect(image.fit, BoxFit.contain);
    });

    testWidgets('확대·드래그 이동이 가능하다(InteractiveViewer)', (tester) async {
      await pumpGallery(tester);

      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer).first,
      );
      expect(viewer.maxScale, greaterThan(1.0));
      // panEnabled 기본값이 true라 확대 후 끌어서 이동할 수 있다.
      expect(viewer.panEnabled, isTrue);
    });

    testWidgets('더블탭으로 확대되고, 다시 더블탭하면 돌아온다', (tester) async {
      await pumpGallery(tester);
      expect(zoomController(tester).value.getMaxScaleOnAxis(), 1.0);

      await tester.tap(find.byType(PageView));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(PageView));
      await tester.pumpAndSettle();
      expect(
        zoomController(tester).value.getMaxScaleOnAxis(),
        greaterThan(1.0),
      );

      await tester.tap(find.byType(PageView));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(PageView));
      await tester.pumpAndSettle();
      expect(zoomController(tester).value.getMaxScaleOnAxis(), 1.0);
    });

    testWidgets('확대 중에는 페이지가 넘어가지 않는다', (tester) async {
      await pumpGallery(tester);

      expect(pagePhysics(tester), isA<PageScrollPhysics>());

      // 2배로 확대.
      zoomController(tester).value = Matrix4.identity()
        ..scaleByDouble(2.0, 2.0, 2.0, 1.0);
      await tester.pump();
      expect(pagePhysics(tester), isA<NeverScrollableScrollPhysics>());

      // 옆으로 밀어도 그대로 1번 장이다.
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);

      // 확대를 풀면 다시 넘길 수 있다.
      zoomController(tester).value = Matrix4.identity();
      await tester.pump();
      expect(pagePhysics(tester), isA<PageScrollPhysics>());
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
    });

    testWidgets('확대해 둔 장을 떠나면 그 장의 확대가 풀린다', (tester) async {
      await pumpGallery(tester);

      zoomController(tester).value = Matrix4.identity()
        ..scaleByDouble(2.0, 2.0, 2.0, 1.0);
      await tester.pump();

      // 확대 중에는 드래그가 잠겨 있으므로 컨트롤러로 넘긴다.
      tester.widget<PageView>(find.byType(PageView)).controller!.jumpToPage(1);
      await tester.pumpAndSettle();

      expect(find.text('2 / 3'), findsOneWidget);
      // 새 장은 원래 크기라 다시 스와이프할 수 있다.
      expect(pagePhysics(tester), isA<PageScrollPhysics>());
    });
  });

  // 1× 상태에서 손가락 개수로 주인이 갈리는 부분 — 이 기능의 핵심이다.
  // Android/iOS는 제스처 인식 상수(터치 슬롭 등)가 달라서 두 플랫폼 모두에서
  // 확인한다.
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    group('제스처 충돌 — ${platform.name}', () {
      gestureTest('1×: 한 손가락 스와이프는 다음 사진으로 넘어간다', platform, (tester) async {
        await pumpGallery(tester);

        await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
        await tester.pumpAndSettle();

        expect(find.text('2 / 3'), findsOneWidget);
        // 넘기기만 했지 확대되면 안 된다.
        expect(zoomController(tester).value.getMaxScaleOnAxis(), 1.0);
      });

      gestureTest('1×: 두 손가락 핀치는 즉시 확대된다 — 페이지는 그대로', platform, (tester) async {
        await pumpGallery(tester);

        await pinch(tester, from: 60, to: 240);

        expect(
          zoomController(tester).value.getMaxScaleOnAxis(),
          greaterThan(1.0),
          reason: '1×에서 핀치가 확대로 이어지지 않았다',
        );
        expect(find.text('1 / 3'), findsOneWidget, reason: '핀치가 페이지를 넘겼다');
      });

      gestureTest('1×: 핀치로 축소하면 1× 밑으로 내려가지 않는다', platform, (tester) async {
        await pumpGallery(tester);

        await pinch(tester, from: 240, to: 60);

        expect(zoomController(tester).value.getMaxScaleOnAxis(), 1.0);
      });

      gestureTest('확대 후: 좌우로 끌어도 페이지가 넘어가지 않는다', platform, (tester) async {
        await pumpGallery(tester);
        await pinch(tester, from: 60, to: 240);
        expect(
          zoomController(tester).value.getMaxScaleOnAxis(),
          greaterThan(1.0),
        );

        await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
        await tester.pumpAndSettle();

        expect(find.text('1 / 3'), findsOneWidget, reason: '확대 중에 페이지가 넘어갔다');
      });

      gestureTest('확대 후: 한 손가락 드래그는 사진을 옮긴다(pan)', platform, (tester) async {
        await pumpGallery(tester);
        await pinch(tester, from: 60, to: 240);

        final before = zoomController(tester).value.entry(0, 3);
        await tester.drag(find.byType(PageView), const Offset(-60, 0));
        await tester.pumpAndSettle();
        final after = zoomController(tester).value.entry(0, 3);

        expect(after, lessThan(before), reason: '확대 상태에서 끌었는데 사진이 안 움직였다');
      });

      gestureTest('다시 1×로 돌아오면 스와이프가 복구된다', platform, (tester) async {
        await pumpGallery(tester);
        await pinch(tester, from: 60, to: 240);
        expect(pagePhysics(tester), isA<NeverScrollableScrollPhysics>());

        // 더블탭으로 원래 크기로 되돌린다.
        await doubleTap(tester);
        expect(zoomController(tester).value.getMaxScaleOnAxis(), 1.0);
        expect(pagePhysics(tester), isA<PageScrollPhysics>());

        await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
        await tester.pumpAndSettle();
        expect(find.text('2 / 3'), findsOneWidget);
      });

      gestureTest('더블탭 확대/축소는 그대로 동작한다', platform, (tester) async {
        await pumpGallery(tester);

        await doubleTap(tester);
        expect(
          zoomController(tester).value.getMaxScaleOnAxis(),
          greaterThan(1.0),
        );

        await doubleTap(tester);
        expect(zoomController(tester).value.getMaxScaleOnAxis(), 1.0);
      });

      // 기존 호출부(파티 상세 이미지·플레이스 메뉴판) 보호 — 한 장짜리는
      // 재우는 장치가 아예 끼지 않으므로 핀치가 예전 그대로여야 한다.
      gestureTest('한 장짜리는 1×에서도 핀치가 그대로 확대된다', platform, (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: FullScreenImageViewer(
              imageUrl: 'https://example.com/only.jpg',
            ),
          ),
        );
        await tester.pump();

        await pinch(tester, from: 60, to: 240);

        expect(
          zoomController(tester).value.getMaxScaleOnAxis(),
          greaterThan(1.0),
        );
      });
    });
  }

  group('닫기', () {
    testWidgets('뒤로가기 버튼으로 이전 화면에 돌아간다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const FullScreenImageViewer.gallery(imageUrls: _urls),
                    ),
                  ),
                  child: const Text('열기'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      // 뷰어가 닫히고 원래 화면이 그대로 남는다.
      expect(find.text('1 / 3'), findsNothing);
      expect(find.text('열기'), findsOneWidget);
    });
  });
}

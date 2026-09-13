// MediaGallery의 페이지 인덱스 계산 — 사진 0개·1개·여러 개, 동영상 유무의
// 모든 조합에서 인덱스가 범위를 벗어나지 않아야 한다.
//
// 회귀 대상: 이벤트 상세(placePromotions)가 `videoFirst: true`를 항상 넘기는데
// 동영상이 없는 이벤트에서 첫 페이지가 images[-1]을 읽어
//   RangeError (length): Invalid value: Only valid value is 0: -1
// 로 죽었다. `videoFirst`는 "앞세우고 싶다"는 뜻일 뿐이고, 실제로 자리를
// 차지하는 조건은 "앞세울 동영상이 있는가"다.
//
// 위젯 테스트의 NetworkImage는 실제 요청을 시도하다 400을 받는다. 그것은 이
// 테스트의 관심사가 아니므로, "예외가 없다"가 아니라 **"인덱스 오류가 없다"**를
// 본다 — 이미지 로딩 실패를 스텁으로 가리면 정작 인덱스 오류까지 함께 가려질
// 수 있어 일부러 그렇게 하지 않는다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/widgets/media_gallery.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

/// 한 프레임에서 터진 **모든** 오류를 모은다.
///
/// `tester.takeException()`은 하나만 꺼내 오므로, 네트워크 이미지 로드 실패가
/// 먼저 끼면 정작 보려는 RangeError가 뒤에 가려 테스트가 조용히 통과해 버린다
/// (실제로 이 테스트를 그렇게 썼다가 옛 버그를 못 잡았다). FlutterError를
/// 직접 가로채 전부 모은 뒤 인덱스 오류만 골라 본다.
Future<List<String>> pumpAndCollectErrors(
  WidgetTester tester,
  Widget widget,
) async {
  final errors = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) => errors.add(details.exceptionAsString());
  try {
    await tester.pumpWidget(widget);
  } finally {
    FlutterError.onError = previous;
  }
  // 남아 있는 예외를 비워 테스트 종료 시 재보고되지 않게 한다.
  tester.takeException();
  return errors;
}

/// 모인 오류 중 인덱스 범위 오류가 있으면 실패시킨다.
/// 네트워크 이미지 로드 실패는 이 테스트의 관심사가 아니라 무시한다.
void expectNoRangeError(List<String> errors) {
  final ranges = errors.where((e) => e.contains('RangeError')).toList();
  expect(ranges, isEmpty, reason: '인덱스 범위 오류가 났다: $ranges');
}

void main() {
  group('MediaGallery — 미디어 조합', () {
    testWidgets('사진 1장 + 동영상 없음 + videoFirst → 인덱스 오류 없음 (회귀)', (
      tester,
    ) async {
      final errors = await pumpAndCollectErrors(
        tester,
        _host(
          const MediaGallery(
            images: ['https://example.com/a.jpg'],
            videoFirst: true,
          ),
        ),
      );
      expectNoRangeError(errors);
      // 사진 1장 = 1페이지. 동영상 자리를 비워 두면 안 된다.
      final pageView = tester.widget<PageView>(find.byType(PageView));
      expect(pageView.childrenDelegate.estimatedChildCount, 1);
    });

    testWidgets('사진 여러 장 + 동영상 없음 + videoFirst → 인덱스 오류 없음', (tester) async {
      final errors = await pumpAndCollectErrors(
        tester,
        _host(
          const MediaGallery(
            images: [
              'https://example.com/a.jpg',
              'https://example.com/b.jpg',
              'https://example.com/c.jpg',
            ],
            videoFirst: true,
          ),
        ),
      );
      expectNoRangeError(errors);
      final pageView = tester.widget<PageView>(find.byType(PageView));
      expect(pageView.childrenDelegate.estimatedChildCount, 3);
    });

    testWidgets('미디어가 하나도 없으면 자리를 비운다', (tester) async {
      final errors = await pumpAndCollectErrors(
        tester,
        _host(const MediaGallery(images: [], videoFirst: true)),
      );
      expectNoRangeError(errors);
      // 빈 분홍 상자가 아니라 아무것도 그리지 않는다.
      expect(find.byType(PageView), findsNothing);
    });

    testWidgets('동영상만 있고 사진이 없어도 인덱스 오류 없음', (tester) async {
      final errors = await pumpAndCollectErrors(
        tester,
        _host(
          const MediaGallery(
            images: [],
            videoUrl: 'https://example.com/v.m3u8',
            videoFirst: true,
          ),
        ),
      );
      expectNoRangeError(errors);
      final pageView = tester.widget<PageView>(find.byType(PageView));
      expect(pageView.childrenDelegate.estimatedChildCount, 1);
    });

    testWidgets('사진 + 동영상이 함께 있으면 동영상이 첫 페이지를 차지한다', (tester) async {
      final errors = await pumpAndCollectErrors(
        tester,
        _host(
          const MediaGallery(
            images: ['https://example.com/a.jpg'],
            videoUrl: 'https://example.com/v.m3u8',
            videoFirst: true,
          ),
        ),
      );
      expectNoRangeError(errors);
      final pageView = tester.widget<PageView>(find.byType(PageView));
      expect(pageView.childrenDelegate.estimatedChildCount, 2);
    });

    testWidgets('videoFirst가 false면 동영상이 마지막 페이지다', (tester) async {
      final errors = await pumpAndCollectErrors(
        tester,
        _host(
          const MediaGallery(
            images: ['https://example.com/a.jpg', 'https://example.com/b.jpg'],
            videoUrl: 'https://example.com/v.m3u8',
          ),
        ),
      );
      expectNoRangeError(errors);
      final pageView = tester.widget<PageView>(find.byType(PageView));
      expect(pageView.childrenDelegate.estimatedChildCount, 3);
    });
  });
}

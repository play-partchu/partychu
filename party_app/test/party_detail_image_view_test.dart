import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/party_detail_image.dart';
import 'package:party_app/widgets/party_detail_image_view.dart';

// ══════════════════════════════════════════════════════════════════════════
// 상세 이미지 렌더링 규칙 검증
//
// 요구사항이 "잘리지 않고 처음부터 끝까지 전부 보인다"이므로, 눈으로
// 확인하기 어려운 대신 위젯 트리에 드러나는 값으로 못 박는다:
//   · 고정 높이(SizedBox height)로 자르지 않는다
//   · BoxFit.cover가 아니다
//   · AspectRatio가 원본 비율 그대로다
//   · cacheWidth가 디코드 상한 정책을 따른다
//   · fullBleed면 부모 여백을 넘어 화면 가로폭 전체로 그린다
//
// Image.network는 테스트 환경에서 로드에 실패하지만(errorBuilder가 받는다),
// 위젯 자체의 속성은 첫 프레임에 그대로 검사할 수 있다.
// ══════════════════════════════════════════════════════════════════════════

/// 테스트 화면 폭 — flutter_test 기본 서피스(800×600).
const double kSurfaceWidth = 800;

Future<Image> pumpView(
  WidgetTester tester,
  Widget view, {
  double outerPadding = 0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(outerPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [view],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return tester.widget<Image>(find.byType(Image));
}

void main() {
  const tall = PartyDetailImage(
    url: 'https://pub-x.r2.dev/party_images/detail/u1/1.png',
    width: 860,
    height: 5000,
  );

  group('원본 비율 유지 · 잘라내지 않음', () {
    testWidgets('AspectRatio가 원본 비율 그대로 잡힌다', (tester) async {
      await pumpView(tester, const PartyDetailImageView(image: tall));

      final aspect = tester.widget<AspectRatio>(find.byType(AspectRatio));
      expect(aspect.aspectRatio, closeTo(860 / 5000, 1e-9));
    });

    testWidgets('세로가 화면보다 훨씬 길어진다 — 고정 높이로 자르지 않는다', (tester) async {
      await pumpView(tester, const PartyDetailImageView(image: tall));

      final size = tester.getSize(find.byType(AspectRatio));
      expect(size.width, kSurfaceWidth);
      expect(
        size.height,
        closeTo(kSurfaceWidth * 5000 / 860, 0.5),
        reason: '가로폭에 맞춘 뒤 세로는 비율대로 길어져야 한다',
      );
      expect(size.height, greaterThan(600), reason: '화면 높이를 넘어가는 것이 정상 동작이다');
    });

    testWidgets('BoxFit.cover가 아니다 — 잘라먹지 않는다', (tester) async {
      final image = await pumpView(
        tester,
        const PartyDetailImageView(image: tall),
      );
      expect(image.fit, isNot(BoxFit.cover));
      expect(image.fit, BoxFit.contain);
    });

    testWidgets('가로는 항상 부모 폭을 채운다', (tester) async {
      final image = await pumpView(
        tester,
        const PartyDetailImageView(image: tall),
      );
      expect(image.width, double.infinity);
    });

    testWidgets('원본 크기를 모르면 폭에 맞추고 세로는 이미지가 정한다', (tester) async {
      final image = await pumpView(
        tester,
        const PartyDetailImageView(
          image: PartyDetailImage(url: 'https://pub-x.r2.dev/legacy.png'),
        ),
      );
      // 비율을 모르니 자리를 미리 잡을 수 없다 — AspectRatio를 쓰지 않는다.
      expect(find.byType(AspectRatio), findsNothing);
      expect(image.fit, BoxFit.fitWidth);
    });
  });

  group('디코드 상한', () {
    testWidgets('cacheWidth가 정책 계산값과 일치한다', (tester) async {
      final image = await pumpView(
        tester,
        const PartyDetailImageView(image: tall),
      );
      final dpr = tester.view.devicePixelRatio;
      expect(
        image.image,
        isA<ResizeImage>(),
        reason: 'cacheWidth를 주면 Flutter가 ResizeImage로 감싼다',
      );
      final resize = image.image as ResizeImage;
      expect(
        resize.width,
        PartyDetailImage.decodeWidthFor(
          viewWidth: kSurfaceWidth,
          devicePixelRatio: dpr,
          imageWidth: 860,
          imageHeight: 5000,
        ),
      );
    });

    testWidgets('세로 20000px짜리도 상한 안에서 디코드된다', (tester) async {
      final image = await pumpView(
        tester,
        const PartyDetailImageView(
          image: PartyDetailImage(
            url: 'https://pub-x.r2.dev/verylong.png',
            width: 1080,
            height: 20000,
          ),
        ),
      );
      final resize = image.image as ResizeImage;
      final decodeWidth = resize.width!;
      final decodeHeight = decodeWidth * 20000 / 1080;

      expect(decodeWidth, lessThan(1080), reason: '원본 그대로면 RGBA 약 86MB');
      expect(
        decodeHeight,
        lessThanOrEqualTo(PartyDetailImage.maxDecodeHeight + 1),
      );
      expect(
        decodeWidth * decodeHeight,
        lessThanOrEqualTo(PartyDetailImage.maxDecodePixels + 1),
      );
    });
  });

  group('가로폭 100%(fullBleed)', () {
    testWidgets('부모의 좌우 여백을 넘어 화면 끝까지 그린다', (tester) async {
      await pumpView(
        tester,
        const PartyDetailImageView(
          image: tall,
          fullBleed: true,
          horizontalPadding: 40,
        ),
        outerPadding: 20,
      );

      // 본문은 여백 20씩 들어가 760이지만, 이미지는 800(화면 전체)이어야 한다.
      final imageWidth = tester.getSize(find.byType(AspectRatio)).width;
      expect(imageWidth, kSurfaceWidth);

      final rect = tester.getRect(find.byType(AspectRatio));
      expect(rect.left, closeTo(0, 0.01), reason: '화면 왼쪽 끝에 닿아야 한다');
      expect(
        rect.right,
        closeTo(kSurfaceWidth, 0.01),
        reason: '화면 오른쪽 끝에 닿아야 한다',
      );
    });

    testWidgets('fullBleed가 아니면 본문 폭 그대로', (tester) async {
      await pumpView(
        tester,
        const PartyDetailImageView(image: tall),
        outerPadding: 20,
      );
      final rect = tester.getRect(find.byType(AspectRatio));
      expect(rect.left, closeTo(20, 0.01));
      expect(rect.width, closeTo(kSurfaceWidth - 40, 0.01));
    });

    testWidgets('원본 크기를 모르면 fullBleed를 조용히 포기한다(세로를 계산할 수 없다)', (tester) async {
      await pumpView(
        tester,
        const PartyDetailImageView(
          image: PartyDetailImage(url: 'https://pub-x.r2.dev/legacy.png'),
          fullBleed: true,
          horizontalPadding: 40,
        ),
        outerPadding: 20,
      );
      expect(find.byType(OverflowBox), findsNothing);
      final rect = tester.getRect(find.byType(Image));
      expect(rect.width, closeTo(kSurfaceWidth - 40, 0.01));
    });
  });

  group('없거나 깨진 이미지', () {
    testWidgets('URL이 비어 있으면 아무것도 그리지 않는다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PartyDetailImageView(image: PartyDetailImage(url: '')),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('이미지 자체가 없으면 아무것도 그리지 않는다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PartyDetailImageView())),
      );
      await tester.pump();
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('로드에 실패하면 안내를 보여주고 화면은 살아 있다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PartyDetailImageView(image: tall),
            ),
          ),
        ),
      );
      // 테스트 환경의 HttpClient는 모든 요청에 400을 돌려준다 —
      // errorBuilder가 받아야 예외로 화면이 죽지 않는다.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      expect(find.text('상세 이미지를 불러올 수 없어요'), findsOneWidget);
    });
  });
}

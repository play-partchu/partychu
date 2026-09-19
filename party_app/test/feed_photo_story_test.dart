import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/utils/party_utils.dart';
import 'package:party_app/widgets/feed_photo_story.dart';
import 'package:party_app/widgets/fullscreen_card_feed.dart';

// 1×1 투명 PNG — 네트워크 없이 실제로 디코드되는 이미지.
final Uint8List _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// 'bad'가 들어간 URL은 디코드에 실패하는 이미지.
ImageProvider _provider(String url) => MemoryImage(
  url.contains('bad') ? Uint8List.fromList(const [1, 2, 3, 4]) : _png,
  // 같은 바이트여도 URL마다 다른 이미지로 캐시되게 scale을 조금씩 바꾼다.
  scale: 1 + url.hashCode % 97 / 1000,
);

class _Pager {
  final current = ValueNotifier<int>(0);
  int nextCalls = 0;
  int previousCalls = 0;
  bool hasNext = true;
  bool hasPrevious = true;
}

Future<_Pager> _pump(
  WidgetTester tester,
  List<String> urls, {
  _Pager? pager,
  int index = 0,
}) async {
  final p = pager ?? _Pager();
  await tester.pumpWidget(
    MaterialApp(
      home: FeedPager(
        index: index,
        current: p.current,
        next: () {
          p.nextCalls++;
          return p.hasNext;
        },
        previous: () {
          p.previousCalls++;
          return p.hasPrevious;
        },
        child: FeedPhotoStory(
          urls: urls,
          placeholder: const Text('placeholder'),
          imageProviderForTest: _provider,
        ),
      ),
    ),
  );
  return p;
}

/// 실제 이미지 디코드는 가짜 시간 밖에서 끝난다.
Future<void> _decode(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
  }
}

double _bar(WidgetTester tester, int i) => tester
    .widget<LinearProgressIndicator>(find.byKey(ValueKey('story-bar-$i')))
    .value!;

void main() {
  group('feedPhotoStoryUrls', () {
    test('대표사진 → 갤러리 순, 중복 URL은 한 번만', () {
      final data = {
        'coverMediaType': 'image',
        'coverImageUrl': 'a',
        'mainImageUrl': 'a',
        'images': ['b', 'a', ' c ', ''],
        'imageUrls': ['c', 'd'],
      };
      expect(feedPhotoStoryUrls(data, getPartyCoverMedia(data)), ['a', 'b', 'c', 'd']);
    });

    test('대표가 동영상이면 사진 모드가 아니다', () {
      final data = {
        'coverMediaType': 'video',
        'coverVideoUrl': 'v.m3u8',
        'images': ['a'],
      };
      expect(feedPhotoStoryUrls(data, getPartyCoverMedia(data)), isEmpty);
    });

    test('대표는 사진이어도 동영상이 등록돼 있으면 기존 방식 그대로', () {
      final data = {
        'coverMediaType': 'image',
        'coverImageUrl': 'a',
        'coverVideoUrl': 'v.m3u8',
      };
      expect(feedPhotoStoryUrls(data, getPartyCoverMedia(data)), isEmpty);
      final legacy = {'mainImageUrl': 'a', 'videoUrl': 'v.mp4'};
      expect(feedPhotoStoryUrls(legacy, getPartyCoverMedia(legacy)), isEmpty);
    });

    test('플레이스처럼 imageUrls만 있어도 된다', () {
      final data = {
        'imageUrls': ['x', 'y'],
      };
      expect(feedPhotoStoryUrls(data, getPartyCoverMedia(data)), ['x', 'y']);
    });
  });

  group('feedMediaItems — 영상이 있으면 항상 영상이 첫 칸', () {
    test('대표가 사진이어도 영상이 맨 앞, 그 뒤로 사진들', () {
      final data = {
        'coverMediaType': 'image',
        'coverImageUrl': 'a',
        'images': ['a', 'b', 'c'],
        'videoUrl': 'v.m3u8',
        'videoThumbnailUrl': 't.jpg',
      };
      final items = feedMediaItems(data, getPartyCoverMedia(data));
      expect(items.map((i) => i.url), ['v.m3u8', 'a', 'b', 'c']);
      expect(items.first.isVideo, isTrue);
      expect(items.first.thumbnailUrl, 't.jpg');
      expect(items.skip(1).every((i) => !i.isVideo), isTrue);
    });

    test('대표가 영상이어도 같은 순서', () {
      final data = {
        'coverMediaType': 'video',
        'coverVideoUrl': 'v.m3u8',
        'imageUrls': ['x', 'y'],
      };
      final items = feedMediaItems(data, getPartyCoverMedia(data));
      expect(items.first.isVideo, isTrue);
      expect(items.skip(1).map((i) => i.url), ['x', 'y']);
    });

    test('영상이 없으면 사진들만, 사진이 없으면 영상 하나', () {
      final photos = {
        'imageUrls': ['x', 'y'],
      };
      expect(
        feedMediaItems(photos, getPartyCoverMedia(photos)).map((i) => i.url),
        ['x', 'y'],
      );
      final videoOnly = {'videoUrl': 'v.mp4'};
      final items = feedMediaItems(videoOnly, getPartyCoverMedia(videoOnly));
      expect(items.length, 1);
      expect(items.single.isVideo, isTrue);
    });

    test('다음 칸 — 마지막 다음은 첫 칸', () {
      expect(nextMediaIndex(0, 4), 1);
      expect(nextMediaIndex(3, 4), 0);
      expect(nextMediaIndex(0, 1), 0);
    });
  });

  group('FeedPhotoStory', () {
    testWidgets('사진이 표시되기 전에는 4초가 흐르지 않는다', (tester) async {
      final p = await _pump(tester, ['one']);
      await tester.pump(const Duration(seconds: 6));
      expect(_bar(tester, 0), 0);
      expect(p.nextCalls, 0);

      await _decode(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(_bar(tester, 0), closeTo(0.5, 0.02));
    });

    testWidgets('사진 1장: 4초 뒤 다음 콘텐츠로 가지 않고 같은 사진을 다시', (tester) async {
      final p = await _pump(tester, ['one']);
      await _decode(tester);
      await tester.pump(const Duration(milliseconds: 3900));
      expect(_bar(tester, 0), greaterThan(0.9));
      await tester.pump(const Duration(milliseconds: 200));
      await _decode(tester);
      expect(p.nextCalls, 0);
      expect(_bar(tester, 0), lessThan(0.1));
      await tester.pump(photoFadeDuration);
    });

    testWidgets('여러 장: 4초마다 다음 사진, 마지막이 끝나면 첫 사진으로', (tester) async {
      final p = await _pump(tester, ['one', 'two', 'three']);
      await _decode(tester);
      expect(find.byType(LinearProgressIndicator), findsNWidgets(3));

      await tester.pump(const Duration(milliseconds: 4050));
      await _decode(tester);
      expect(_bar(tester, 0), 1);
      expect(_bar(tester, 1), lessThan(0.1));

      await tester.pump(const Duration(milliseconds: 4050));
      await _decode(tester);
      expect(_bar(tester, 1), 1);
      expect(p.nextCalls, 0);

      await tester.pump(const Duration(milliseconds: 4100));
      await _decode(tester);
      // 다음 콘텐츠로 넘어가지 않고 첫 사진부터 다시 차오른다.
      expect(p.nextCalls, 0);
      expect(_bar(tester, 0), lessThan(0.1));
      expect(_bar(tester, 1), 0);
      expect(_bar(tester, 2), 0);
      await tester.pump(photoFadeDuration);
    });

    testWidgets('누르고 있는 동안 멈추고, 떼면 남은 시간부터', (tester) async {
      final p = await _pump(tester, ['one', 'two']);
      await _decode(tester);
      await tester.pump(const Duration(seconds: 1));

      final g = await tester.startGesture(tester.getCenter(find.byType(FeedPhotoStory)));
      await tester.pump(const Duration(milliseconds: 200));
      final held = _bar(tester, 0);
      await tester.pump(const Duration(seconds: 5));
      expect(_bar(tester, 0), closeTo(held, 0.001));
      expect(p.nextCalls, 0);

      await g.up();
      await tester.pump();
      // 길게 누른 뒤 뗀 것은 넘김이 아니다 — 여전히 첫 사진.
      expect(_bar(tester, 1), 0);
      await tester.pump(const Duration(seconds: 1));
      expect(_bar(tester, 0), greaterThan(held));
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('오른쪽 탭 = 다음, 왼쪽 탭 = 이전 — 끝에서는 반대쪽 끝으로 순환', (tester) async {
      final p = await _pump(tester, ['one', 'two']);
      await _decode(tester);
      final rect = tester.getRect(find.byType(FeedPhotoStory));

      await tester.tapAt(Offset(rect.right - 20, rect.center.dy));
      await _decode(tester);
      expect(_bar(tester, 0), 1);

      await tester.tapAt(Offset(rect.left + 20, rect.center.dy));
      await _decode(tester);
      expect(_bar(tester, 0), lessThan(0.1));
      expect(p.previousCalls, 0);

      // 첫 사진에서 왼쪽 탭 = 마지막 사진(이전 콘텐츠로 가지 않는다).
      await tester.tapAt(Offset(rect.left + 20, rect.center.dy));
      await _decode(tester);
      expect(p.previousCalls, 0);
      expect(_bar(tester, 0), 1);

      // 마지막 사진에서 오른쪽 탭 = 첫 사진(다음 콘텐츠로 가지 않는다).
      await tester.tapAt(Offset(rect.right - 20, rect.center.dy));
      await _decode(tester);
      expect(p.nextCalls, 0);
      expect(_bar(tester, 0), lessThan(0.1));
      await tester.pump(photoFadeDuration);
    });

    testWidgets('좌우 스와이프로도 넘긴다', (tester) async {
      await _pump(tester, ['one', 'two']);
      await _decode(tester);
      await tester.fling(
        find.byType(FeedPhotoStory),
        const Offset(-200, 0),
        800,
      );
      await _decode(tester);
      expect(_bar(tester, 0), 1);
      await tester.fling(
        find.byType(FeedPhotoStory),
        const Offset(200, 0),
        800,
      );
      await _decode(tester);
      expect(_bar(tester, 0), lessThan(0.1));
      await tester.pump(photoFadeDuration);
    });

    testWidgets('깨진 사진은 건너뛴다', (tester) async {
      await _pump(tester, ['bad-1', 'one', 'bad-2', 'two']);
      await _decode(tester);
      // 첫 장이 깨져 빠지고, 정상 사진 'one'부터 4초가 흐른다.
      expect(find.byType(LinearProgressIndicator), findsNWidgets(3));
      await tester.pump(const Duration(seconds: 2));
      expect(_bar(tester, 0), closeTo(0.5, 0.05));

      // 다음 차례의 깨진 사진도 건너뛰고 'two'로 간다.
      await tester.pump(const Duration(milliseconds: 2050));
      await _decode(tester);
      await _decode(tester);
      expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
      expect(_bar(tester, 0), 1);
      await tester.pump(const Duration(seconds: 2));
      expect(_bar(tester, 1), closeTo(0.5, 0.05));
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('다른 콘텐츠가 현재 페이지면 멈추고 처음으로 되돌린다', (tester) async {
      final pager = _Pager()..current.value = 1;
      await _pump(tester, ['one', 'two'], pager: pager);
      await _decode(tester);
      await tester.pump(const Duration(seconds: 5));
      expect(_bar(tester, 0), 0);
      expect(pager.nextCalls, 0);

      pager.current.value = 0;
      await _decode(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(_bar(tester, 0), closeTo(0.5, 0.05));

      pager.current.value = 1;
      await tester.pump();
      expect(_bar(tester, 0), 0);
      await tester.pump(const Duration(seconds: 10));
      expect(_bar(tester, 0), 0);
      expect(pager.nextCalls, 0);
    });
  });
}

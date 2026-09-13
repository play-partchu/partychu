import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/utils/party_utils.dart';

void main() {
  group('getPartyCoverMedia', () {
    test('테스트1: 사진 1장 + 동영상 1개, 사진을 대표로 선택', () {
      final party = <String, dynamic>{
        'title': '테스트 파티',
        'images': ['https://example.com/photo1.jpg'],
        'videoUrl': 'https://videodelivery.net/abc123/manifest/video.m3u8',
        'videoUid': 'abc123',
        'videoThumbnailUrl':
            'https://videodelivery.net/abc123/thumbnails/thumbnail.jpg',
        // 등록 화면에서 "사진"을 대표로 선택하면 저장되는 필드
        'coverMediaType': 'image',
        'coverImageUrl': 'https://example.com/photo1.jpg',
        'coverVideoUid': null,
        'coverVideoUrl': null,
        'coverThumbnailUrl': 'https://example.com/photo1.jpg',
      };

      final cover = getPartyCoverMedia(party);

      expect(cover, isNotNull);
      expect(cover!.type, 'image');
      expect(cover.isVideo, isFalse);
      expect(cover.imageUrl, 'https://example.com/photo1.jpg');
      expect(cover.videoUrl, isNull);
      print(
        '[TEST1] type=${cover.type} imageUrl=${cover.imageUrl} '
        'videoUrl=${cover.videoUrl} thumbnailUrl=${cover.thumbnailUrl}',
      );
    });

    test('테스트2: 사진 1장 + 동영상 1개, 동영상을 대표로 선택', () {
      final party = <String, dynamic>{
        'title': '테스트 파티',
        'images': ['https://example.com/photo1.jpg'],
        'videoUrl': 'https://videodelivery.net/abc123/manifest/video.m3u8',
        'videoUid': 'abc123',
        'videoThumbnailUrl':
            'https://videodelivery.net/abc123/thumbnails/thumbnail.jpg',
        // 등록 화면에서 "동영상"을 대표로 선택하면 저장되는 필드
        'coverMediaType': 'video',
        'coverImageUrl': null,
        'coverVideoUid': 'abc123',
        'coverVideoUrl': 'https://videodelivery.net/abc123/manifest/video.m3u8',
        'coverThumbnailUrl':
            'https://videodelivery.net/abc123/thumbnails/thumbnail.jpg',
      };

      final cover = getPartyCoverMedia(party);

      expect(cover, isNotNull);
      expect(cover!.type, 'video');
      expect(cover.isVideo, isTrue);
      expect(
        cover.videoUrl,
        'https://videodelivery.net/abc123/manifest/video.m3u8',
      );
      expect(cover.videoUid, 'abc123');
      expect(
        cover.thumbnailUrl,
        'https://videodelivery.net/abc123/thumbnails/thumbnail.jpg',
      );
      print(
        '[TEST2] type=${cover.type} videoUrl=${cover.videoUrl} '
        'videoUid=${cover.videoUid} thumbnailUrl=${cover.thumbnailUrl}',
      );
    });

    test('하위호환: coverMediaType 없고 이미지+동영상 둘 다 있는 기존 데이터 → 이미지 우선', () {
      final party = <String, dynamic>{
        'title': '레거시 파티',
        'images': ['https://example.com/photo1.jpg'],
        'videoUrl': 'https://videodelivery.net/legacy/manifest/video.m3u8',
        'videoThumbnailUrl':
            'https://videodelivery.net/legacy/thumbnails/thumbnail.jpg',
        // coverMediaType 필드 자체가 없음(기존 데이터)
      };

      final cover = getPartyCoverMedia(party);

      expect(cover, isNotNull);
      expect(cover!.type, 'image');
      expect(cover.imageUrl, 'https://example.com/photo1.jpg');
    });

    test(
      '하위호환: coverMediaType 없고 동영상만 있는 기존 데이터 → 동영상이 대표(기존 isVideoOnly 유지)',
      () {
        final party = <String, dynamic>{
          'title': '레거시 영상전용 파티',
          'videoUrl': 'https://videodelivery.net/legacy/manifest/video.m3u8',
          'videoUid': 'legacy',
          'videoThumbnailUrl':
              'https://videodelivery.net/legacy/thumbnails/thumbnail.jpg',
        };

        final cover = getPartyCoverMedia(party);

        expect(cover, isNotNull);
        expect(cover!.type, 'video');
        expect(
          cover.videoUrl,
          'https://videodelivery.net/legacy/manifest/video.m3u8',
        );
      },
    );
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import 'package:party_app/services/cloudflare_service.dart';
import 'package:party_app/services/media_upload_service.dart';
import 'package:party_app/utils/register_validation.dart';

/// 플레이스+파티 등록의 "사진 업로드 중 문제가 발생했습니다"를 재현/방지하는
/// 테스트. 업로드 자체는 주입한 가짜 함수로 대체해 네트워크 없이 검증한다.
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('media_upload_test'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// 내용이 있는 진짜 임시 파일을 만든다(존재/크기 검사를 통과해야 하므로).
  XFile makeFile(String name, {String content = 'x'}) {
    final f = File('${tmp.path}${Platform.pathSeparator}$name')
      ..writeAsStringSync(content);
    return XFile(f.path);
  }

  // 업로드 호출을 기록하는 가짜 업로더.
  late List<String> imageCalls;
  late List<String> videoCalls;

  Future<String> fakeUploadImage(XFile f) async {
    imageCalls.add(f.path);
    return 'https://cdn.test/img${imageCalls.length}.jpg';
  }

  Future<Map<String, String>> fakeUploadVideo(XFile f) async {
    videoCalls.add(f.path);
    return {
      'videoUid': 'uid-123',
      'videoUrl': 'https://cdn.test/v.m3u8',
      'videoThumbnailUrl': 'https://cdn.test/v.jpg',
    };
  }

  setUp(() {
    imageCalls = [];
    videoCalls = [];
  });

  group('정상 업로드', () {
    test('사진 1장만 고른 경우', () async {
      final result = await MediaUploadService.uploadNewMedia(
        media: [makeFile('a.jpg')],
        uploadImage: fakeUploadImage,
        uploadVideo: fakeUploadVideo,
      );

      expect(result.imageUrls, ['https://cdn.test/img1.jpg']);
      expect(result.hasVideo, isFalse);
      expect(imageCalls, hasLength(1));
      expect(videoCalls, isEmpty);
    });

    test('사진 여러 장 — 고른 순서가 그대로 유지된다', () async {
      final files = [makeFile('a.jpg'), makeFile('b.png'), makeFile('c.jpeg')];

      final result = await MediaUploadService.uploadNewMedia(
        media: files,
        uploadImage: fakeUploadImage,
        uploadVideo: fakeUploadVideo,
      );

      expect(result.imageUrls, [
        'https://cdn.test/img1.jpg',
        'https://cdn.test/img2.jpg',
        'https://cdn.test/img3.jpg',
      ]);
      expect(imageCalls, files.map((f) => f.path).toList());
    });

    test('영상 포함 — 영상은 Stream으로, 사진은 R2로 나뉜다', () async {
      final photo = makeFile('a.jpg');
      final video = makeFile('clip.mp4');

      final result = await MediaUploadService.uploadNewMedia(
        media: [photo, video],
        uploadImage: fakeUploadImage,
        uploadVideo: fakeUploadVideo,
      );

      expect(result.imageUrls, hasLength(1));
      expect(result.videoUid, 'uid-123');
      expect(result.videoUrl, 'https://cdn.test/v.m3u8');
      expect(result.videoThumbnailUrl, 'https://cdn.test/v.jpg');
      // 영상이 사진 업로더로 새어 들어가면 안 된다.
      expect(imageCalls, [photo.path]);
      expect(videoCalls, [video.path]);
    });

    test('.mov 도 영상으로 취급한다', () async {
      await MediaUploadService.uploadNewMedia(
        media: [makeFile('clip.MOV')],
        uploadImage: fakeUploadImage,
        uploadVideo: fakeUploadVideo,
      );
      expect(videoCalls, hasLength(1));
      expect(imageCalls, isEmpty);
    });

    test('신규 파일이 없으면 업로드를 아예 하지 않는다(기존 URL 재업로드 방지)', () async {
      final result = await MediaUploadService.uploadNewMedia(
        media: const [],
        uploadImage: fakeUploadImage,
        uploadVideo: fakeUploadVideo,
      );

      expect(result.imageUrls, isEmpty);
      expect(result.hasVideo, isFalse);
      expect(imageCalls, isEmpty);
      expect(videoCalls, isEmpty);
    });
  });

  group('업로드 전 파일 검사', () {
    test('존재하지 않는 임시파일 — 업로드를 시도하지 않고 실패한다', () async {
      // 임시저장을 복원한 뒤 OS가 캐시를 비운 상황.
      final gone = XFile('${tmp.path}${Platform.pathSeparator}gone.jpg');

      await expectLater(
        MediaUploadService.uploadNewMedia(
          media: [gone],
          uploadImage: fakeUploadImage,
          uploadVideo: fakeUploadVideo,
        ),
        throwsA(
          isA<MediaUploadException>()
              .having(
                (e) => e.reason,
                'reason',
                MediaUploadFailureReason.missingFile,
              )
              .having((e) => e.index, 'index', 0)
              .having((e) => e.isFileProblem, 'isFileProblem', isTrue),
        ),
      );
      // 없는 파일을 네트워크까지 들고 가지 않는다.
      expect(imageCalls, isEmpty);
    });

    test('0바이트 파일도 걸러낸다', () async {
      await expectLater(
        MediaUploadService.uploadNewMedia(
          media: [makeFile('empty.jpg', content: '')],
          uploadImage: fakeUploadImage,
          uploadVideo: fakeUploadVideo,
        ),
        throwsA(
          isA<MediaUploadException>().having(
            (e) => e.reason,
            'reason',
            MediaUploadFailureReason.emptyFile,
          ),
        ),
      );
      expect(imageCalls, isEmpty);
    });

    test('빈 경로 / content:// URI는 파일로 열 수 없으므로 걸러낸다', () async {
      for (final bad in ['', 'content://media/external/images/media/42']) {
        await expectLater(
          MediaUploadService.uploadNewMedia(
            media: [XFile(bad)],
            uploadImage: fakeUploadImage,
            uploadVideo: fakeUploadVideo,
          ),
          throwsA(
            isA<MediaUploadException>().having(
              (e) => e.reason,
              'reason',
              MediaUploadFailureReason.invalidPath,
            ),
          ),
          reason: bad,
        );
      }
      expect(imageCalls, isEmpty);
    });

    test('앞 파일이 성공한 뒤 실패하면 롤백 대상을 함께 돌려준다', () async {
      final ok = makeFile('a.jpg');
      final gone = XFile('${tmp.path}${Platform.pathSeparator}gone.jpg');

      await expectLater(
        MediaUploadService.uploadNewMedia(
          media: [ok, gone],
          uploadImage: fakeUploadImage,
          uploadVideo: fakeUploadVideo,
        ),
        throwsA(
          isA<MediaUploadException>().having((e) => e.index, 'index', 1).having(
            (e) => e.uploadedImageUrls,
            'uploadedImageUrls',
            ['https://cdn.test/img1.jpg'],
          ),
        ),
      );
    });
  });

  group('업로드 실패 갈래', () {
    test('Cloudflare 인증 실패는 auth로 분류된다(사진 잘못이 아니다)', () async {
      await expectLater(
        MediaUploadService.uploadNewMedia(
          media: [makeFile('a.jpg')],
          uploadImage: (_) async => throw const CloudflareUploadException(
            kind: 'r2',
            statusCode: 403,
            detail:
                '{"success":false,"errors":[{"code":10000,'
                '"message":"Authentication error"}]}',
          ),
          uploadVideo: fakeUploadVideo,
        ),
        throwsA(
          isA<MediaUploadException>()
              .having((e) => e.reason, 'reason', MediaUploadFailureReason.auth)
              .having((e) => e.isFileProblem, 'isFileProblem', isFalse),
        ),
      );
    });

    test('토큰 무효(code 1000)도 auth로 분류된다', () {
      const e = CloudflareUploadException(
        kind: 'r2',
        statusCode: 400,
        detail:
            '{"success":false,"errors":[{"code":1000,'
            '"message":"Invalid API Token"}]}',
      );
      expect(e.isAuthFailure, isTrue);
      expect(MediaUploadService.classify(e), MediaUploadFailureReason.auth);
    });

    test('5xx는 network로 분류된다', () {
      const e = CloudflareUploadException(
        kind: 'r2',
        statusCode: 503,
        detail: 'service unavailable',
      );
      expect(MediaUploadService.classify(e), MediaUploadFailureReason.network);
    });

    test('파일 읽기 실패는 unreadableFile로 분류된다', () {
      expect(
        MediaUploadService.classify(
          const FileSystemException('cannot read', '/x.jpg'),
        ),
        MediaUploadFailureReason.unreadableFile,
      );
    });
  });

  group('사용자 안내 문구', () {
    MediaUploadException withReason(MediaUploadFailureReason r) =>
        MediaUploadException(index: 0, path: '/x.jpg', reason: r);

    test('파일이 문제면 해당 사진을 지우라고 안내한다', () {
      for (final r in [
        MediaUploadFailureReason.missingFile,
        MediaUploadFailureReason.emptyFile,
        MediaUploadFailureReason.invalidPath,
        MediaUploadFailureReason.unreadableFile,
      ]) {
        expect(
          RegisterValidation.failureMessage(withReason(r), stage: '사진 업로드'),
          '선택한 사진 중 업로드할 수 없는 파일이 있습니다. 해당 사진을 삭제한 뒤 다시 추가해주세요.',
          reason: r.name,
        );
      }
    });

    test('인증 실패면 사진을 지우라고 하지 않는다', () {
      final msg = RegisterValidation.failureMessage(
        withReason(MediaUploadFailureReason.auth),
        stage: '사진 업로드',
      );
      expect(msg, RegisterValidation.uploadServiceAuthMessage);
      expect(msg.contains('삭제'), isFalse);
    });

    test('네트워크 실패면 연결 확인을 안내한다', () {
      expect(
        RegisterValidation.failureMessage(
          withReason(MediaUploadFailureReason.network),
        ),
        contains('네트워크'),
      );
    });

    test('원본 Cloudflare 인증 예외도 같은 문구로 안내한다', () {
      expect(
        RegisterValidation.failureMessage(
          const CloudflareUploadException(
            kind: 'r2',
            statusCode: 403,
            detail: 'Authentication error',
          ),
          stage: '사진 업로드',
        ),
        RegisterValidation.uploadServiceAuthMessage,
      );
    });

    test('어떤 문구에도 기술 정보(경로/상태코드)가 새지 않는다', () {
      final msg = RegisterValidation.failureMessage(
        const MediaUploadException(
          index: 2,
          path: '/data/user/0/cache/secret.jpg',
          reason: MediaUploadFailureReason.missingFile,
        ),
        stage: '사진 업로드',
      );
      expect(msg.contains('/data/user'), isFalse);
      expect(msg.contains('missingFile'), isFalse);
    });
  });
}

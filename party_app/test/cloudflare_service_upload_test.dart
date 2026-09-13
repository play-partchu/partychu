import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import 'package:party_app/models/party_detail_image.dart';
import 'package:party_app/services/cloudflare_service.dart';
import 'package:party_app/services/media_upload_service.dart';
import 'package:party_app/utils/register_validation.dart';
import 'package:party_app/utils/user_session.dart';

// ══════════════════════════════════════════════════════════════════════════
// CloudflareService — 안전한 업로드 경로 전환 검증
//
// 이 파일은 "앱이 무엇을 서버에 보내고, 받은 허가를 어떻게 쓰는가"를 본다.
// 프리사인 서명이 수학적으로 맞는지는 서버 쪽(functions/mediaUploads.selfcheck.js)
// 이 검증하므로, 여기서는 **앱이 서버가 시킨 대로 정확히 보내는지**가 관심사다.
//
// R2 역할은 진짜 로컬 HttpServer가 맡는다 — MockClient로는 "실제로 소켓에
// 어떤 헤더가 실려 나가는지"를 볼 수 없기 때문이다. Content-Length가 서명과
// 1바이트라도 다르면 운영에서 403이 나는데, 그것을 잡으려면 실물 요청이어야
// 한다.
// ══════════════════════════════════════════════════════════════════════════

/// 로컬에서 R2 / Stream direct upload 역할을 하는 가짜 서버.
class FakeCloudflare {
  late HttpServer _server;

  /// 도착한 요청 기록 — 테스트가 헤더·본문을 그대로 확인한다.
  final List<
    ({String method, String path, Map<String, String> headers, List<int> body})
  >
  received = [];

  /// Stream 업로드가 "30초 초과"로 거부되는 상황을 재현할지.
  bool rejectVideoAsTooLong = false;

  /// R2가 서명 불일치로 거부하는 상황을 재현할지.
  bool rejectPutAsForbidden = false;

  String get origin => 'http://${_server.address.host}:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) async {
      final body = <int>[];
      await for (final chunk in request) {
        body.addAll(chunk);
      }
      final headers = <String, String>{};
      request.headers.forEach((name, values) {
        headers[name.toLowerCase()] = values.join(',');
      });
      received.add((
        method: request.method,
        path: request.uri.path,
        headers: headers,
        body: body,
      ));

      if (request.uri.path.startsWith('/r2/')) {
        if (rejectPutAsForbidden) {
          request.response.statusCode = 403;
          request.response.write('{"error":"SignatureDoesNotMatch"}');
        } else {
          request.response.statusCode = 200;
        }
      } else if (request.uri.path.startsWith('/stream/')) {
        if (rejectVideoAsTooLong) {
          request.response.statusCode = 400;
          request.response.write(
            jsonEncode({
              'success': false,
              'errors': [
                {
                  'code': 10004,
                  'message':
                      'The video duration exceeds the maximum duration allowed '
                      '(maxDurationSeconds).',
                },
              ],
            }),
          );
        } else {
          request.response.statusCode = 200;
        }
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
  }

  Future<void> stop() => _server.close(force: true);
}

/// 서버(functions/mediaUploads.js)가 실제로 돌려주는 모양 그대로의 응답을
/// 만든다. 필드 이름이 어긋나면 여기서 먼저 드러난다.
Map<String, dynamic> uploadGrant({
  required String origin,
  required String key,
  required String contentType,
  required int contentLength,
  String publicBase = 'https://pub-abc123.r2.dev',
}) => {
  'uploadUrl': '$origin/r2/$key?X-Amz-Signature=deadbeef',
  'publicUrl': '$publicBase/$key',
  'key': key,
  'expiresIn': 300,
  'requiredHeaders': {
    'Content-Type': contentType,
    'Content-Length': '$contentLength',
  },
};

Map<String, dynamic> videoGrant({
  required String origin,
  String videoUid = 'abcdef0123456789abcdef0123456789',
}) => {
  'uploadUrl': '$origin/stream/direct/$videoUid',
  'videoUid': videoUid,
  'videoUrl': 'https://videodelivery.net/$videoUid/manifest/video.m3u8',
  'videoThumbnailUrl':
      'https://videodelivery.net/$videoUid/thumbnails/thumbnail.jpg',
  'expiresIn': 1800,
  'maxDurationSeconds': 30,
};

void main() {
  late FakeCloudflare cf;
  late Directory tmp;

  /// 콜러블에 도착한 (이름, 데이터) 기록.
  late List<({String name, Map<String, dynamic> data})> calls;

  /// 각 콜러블 이름에 대한 응답(또는 던질 예외).
  late Map<String, Object Function(Map<String, dynamic> data)> responders;

  // 업로더가 받는 것은 XFile 하나다(앱은 파일 경로, 웹은 blob) — 테스트도
  // 실제 파일을 만든 뒤 XFile로 감싸 같은 입구로 넣는다.
  Future<XFile> writeFile(String name, int bytes) async {
    final f = File('${tmp.path}/$name');
    await f.writeAsBytes(List<int>.generate(bytes, (i) => (i * 7) % 256));
    return XFile(f.path);
  }

  setUp(() async {
    UserSession.userId = 'alice';

    cf = FakeCloudflare();
    await cf.start();
    tmp = await Directory.systemTemp.createTemp('cf_upload_test');

    calls = [];
    responders = {};

    CloudflareService.debugSetTransport(
      callable: (name, data) async {
        calls.add((name: name, data: data));
        final responder = responders[name];
        if (responder == null) {
          throw StateError('예상하지 못한 콜러블 호출: $name');
        }
        final result = responder(data);
        if (result is Exception) throw result;
        return result as Map<String, dynamic>;
      },
    );
  });

  tearDown(() async {
    CloudflareService.debugResetTransport();
    UserSession.userId = '';
    await cf.stop();
    await tmp.delete(recursive: true);
  });

  // ══════════════════════════════════════════════════════════════════════
  // 사진 업로드
  // ══════════════════════════════════════════════════════════════════════

  group('uploadImage — presigned PUT', () {
    test('허가 발급 → 정확한 헤더로 PUT → 기존과 같은 publicUrl 반환', () async {
      final file = await writeFile('cover.jpg', 4096);
      responders['createUploadUrl'] = (data) => uploadGrant(
        origin: cf.origin,
        key: 'party_images/alice/1700000000-ab12.jpg',
        contentType: 'image/jpeg',
        contentLength: data['contentLength'] as int,
      );

      final url = await CloudflareService.uploadImage(file);

      // ① 허가를 먼저 받는다
      expect(calls, hasLength(1));
      expect(calls.single.name, 'createUploadUrl');

      // ② PUT이 실제로 도착했고, 메서드·헤더·본문이 서명과 일치한다
      expect(cf.received, hasLength(1));
      final put = cf.received.single;
      expect(put.method, 'PUT');
      expect(put.path, '/r2/party_images/alice/1700000000-ab12.jpg');
      expect(
        put.headers['content-length'],
        '4096',
        reason: '서명에 박힌 크기와 다르면 R2가 403으로 거부한다',
      );
      expect(put.headers['content-type'], 'image/jpeg');
      expect(put.body, await file.readAsBytes());

      // ③ 반환값은 예전과 같은 공개 URL 형식
      expect(
        url,
        'https://pub-abc123.r2.dev/party_images/alice/1700000000-ab12.jpg',
      );
    });

    test('uid·key를 보내지 않는다 — 경로는 서버가 auth.uid로 정한다', () async {
      final file = await writeFile('a.jpg', 100);
      responders['createUploadUrl'] = (data) => uploadGrant(
        origin: cf.origin,
        key: 'party_images/alice/1-a.jpg',
        contentType: 'image/jpeg',
        contentLength: data['contentLength'] as int,
      );

      await CloudflareService.uploadImage(file);

      final sent = calls.single.data;
      for (final forbidden in ['uid', 'userId', 'key', 'path', 'objectKey']) {
        expect(
          sent.containsKey(forbidden),
          isFalse,
          reason: '$forbidden 을 보내면 서버가 무시하더라도 앱이 경로를 정하는 것처럼 보인다',
        );
      }
      expect(sent.keys.toSet(), {
        'folder',
        'ext',
        'contentType',
        'contentLength',
      });
    });

    test('보내는 크기·형식이 실제 파일과 일치한다', () async {
      final file = await writeFile('b.png', 12345);
      responders['createUploadUrl'] = (data) => uploadGrant(
        origin: cf.origin,
        key: 'party_images/alice/1-b.png',
        contentType: 'image/png',
        contentLength: data['contentLength'] as int,
      );

      await CloudflareService.uploadImage(file);

      expect(calls.single.data['contentLength'], 12345);
      expect(calls.single.data['ext'], 'png');
      expect(calls.single.data['contentType'], 'image/png');
    });

    test('앱은 CLOUDFLARE_API_TOKEN을 쓰지 않는다 — Authorization 헤더가 없다', () async {
      // dotenv를 아예 로드하지 않는다 — 그래도 업로드가 되어야 한다는 것이
      // "앱에 자격증명이 없다"의 뜻이다(예전 구현은 여기서 이미 실패했다).
      final file = await writeFile('c.jpg', 64);
      responders['createUploadUrl'] = (data) => uploadGrant(
        origin: cf.origin,
        key: 'party_images/alice/1-c.jpg',
        contentType: 'image/jpeg',
        contentLength: data['contentLength'] as int,
      );

      await CloudflareService.uploadImage(file);

      final put = cf.received.single;
      expect(put.headers.containsKey('authorization'), isFalse);
      expect(
        put.headers.values.join(' '),
        isNot(contains('should-never-be-used')),
      );
    });

    test('서버가 준 requiredHeaders를 그대로 쓴다(임의로 만들지 않는다)', () async {
      final file = await writeFile('d.webp', 200);
      responders['createUploadUrl'] = (data) => {
        ...uploadGrant(
          origin: cf.origin,
          key: 'party_images/alice/1-d.webp',
          contentType: 'image/webp',
          contentLength: data['contentLength'] as int,
        ),
        'requiredHeaders': {
          'Content-Type': 'image/webp',
          'Content-Length': '200',
          'X-Extra-Signed': 'yes',
        },
      };

      await CloudflareService.uploadImage(file);
      expect(cf.received.single.headers['x-extra-signed'], 'yes');
    });

    test('선언한 크기와 실제 바이트가 다르면 보내기 전에 막는다', () async {
      final file = await writeFile('e.jpg', 500);
      responders['createUploadUrl'] = (_) => uploadGrant(
        origin: cf.origin,
        key: 'party_images/alice/1-e.jpg',
        contentType: 'image/jpeg',
        contentLength: 999, // 서명은 999인데 실제는 500
      );

      await expectLater(
        CloudflareService.uploadImage(file),
        throwsA(isA<CloudflareUploadException>()),
      );
      expect(cf.received, isEmpty, reason: '틀린 요청을 아예 보내지 않아야 한다');
    });

    test('R2가 거부하면 상태 코드를 담아 던진다', () async {
      cf.rejectPutAsForbidden = true;
      final file = await writeFile('f.jpg', 128);
      responders['createUploadUrl'] = (data) => uploadGrant(
        origin: cf.origin,
        key: 'party_images/alice/1-f.jpg',
        contentType: 'image/jpeg',
        contentLength: data['contentLength'] as int,
      );

      await expectLater(
        CloudflareService.uploadImage(file),
        throwsA(
          isA<CloudflareUploadException>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.isAuthFailure, 'isAuthFailure', isTrue),
        ),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // 호출부별 회귀 — 모든 업로드 지점이 같은 메서드를 거친다
  // ══════════════════════════════════════════════════════════════════════

  group('회귀 — 업로드 지점별로 폴더·형식이 그대로다', () {
    // (설명, 파일명, 넘기는 folder, 기대 MIME)
    final sites = <(String, String, String?, String)>[
      ('파티 대표사진', 'cover.jpg', null, 'image/jpeg'),
      ('파티 상세 이미지', 'detail.png', PartyDetailImage.storageFolder, 'image/png'),
      ('프로필 사진', 'profile.jpg', null, 'image/jpeg'),
      ('플레이스/장소대여 이미지', 'place.jpeg', null, 'image/jpeg'),
      ('장소대여 룸 사진', 'room.webp', null, 'image/webp'),
      ('상세 블록 이미지', 'block.png', null, 'image/png'),
      ('파티샵/상품 이미지', 'product.jpg', null, 'image/jpeg'),
      ('피드백 첨부', 'feedback.png', null, 'image/png'),
      ('iOS 원본 사진(heic)', 'ios.heic', null, 'image/heic'),
    ];

    for (final (label, name, folder, mime) in sites) {
      test('$label — folder=${folder ?? '(기본)'} mime=$mime', () async {
        final file = await writeFile(name, 321);
        final expectedFolder = folder ?? 'party_images';
        responders['createUploadUrl'] = (data) => uploadGrant(
          origin: cf.origin,
          key: '$expectedFolder/alice/1-x.${name.split('.').last}',
          contentType: data['contentType'] as String,
          contentLength: data['contentLength'] as int,
        );

        final url = folder == null
            ? await CloudflareService.uploadImage(file)
            : await CloudflareService.uploadImage(file, folder: folder);

        expect(calls.single.data['folder'], expectedFolder);
        expect(calls.single.data['contentType'], mime);
        expect(cf.received.single.headers['content-type'], mime);
        expect(url, startsWith('https://pub-abc123.r2.dev/$expectedFolder/'));
      });
    }

    test('상세 이미지 폴더는 대표사진 폴더와 다르다', () async {
      expect(PartyDetailImage.storageFolder, isNot('party_images'));
      expect(PartyDetailImage.storageFolder, startsWith('party_images/'));
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // 동영상
  // ══════════════════════════════════════════════════════════════════════

  group('uploadVideo — Stream direct upload', () {
    test('30초 이하: 허가 → 업로드 → 예전과 같은 3개 값 반환', () async {
      final file = await writeFile('clip.mp4', 2048);
      responders['createVideoUploadUrl'] = (_) => videoGrant(origin: cf.origin);

      final result = await CloudflareService.uploadVideo(file);

      expect(calls.single.name, 'createVideoUploadUrl');
      expect(calls.single.data, isEmpty, reason: '앱이 정할 것이 없다');

      final post = cf.received.single;
      expect(post.method, 'POST');
      expect(post.path, contains('/stream/direct/'));
      expect(post.headers['content-type'], contains('multipart/form-data'));
      expect(post.headers.containsKey('authorization'), isFalse);

      // Firestore에 저장되는 세 값의 모양이 예전과 같아야 한다.
      expect(result.keys.toSet(), {
        'videoUid',
        'videoUrl',
        'videoThumbnailUrl',
      });
      expect(result['videoUid'], 'abcdef0123456789abcdef0123456789');
      expect(
        result['videoUrl'],
        'https://videodelivery.net/abcdef0123456789abcdef0123456789/manifest/video.m3u8',
      );
      expect(
        result['videoThumbnailUrl'],
        'https://videodelivery.net/abcdef0123456789abcdef0123456789/thumbnails/thumbnail.jpg',
      );
    });

    test('30초 초과: 서버(Cloudflare)가 거부하고 앱이 이유를 안내한다', () async {
      cf.rejectVideoAsTooLong = true;
      final file = await writeFile('long.mp4', 4096);
      responders['createVideoUploadUrl'] = (_) => videoGrant(origin: cf.origin);

      try {
        await CloudflareService.uploadVideo(file);
        fail('30초를 넘으면 거부돼야 한다');
      } on CloudflareUploadException catch (e) {
        expect(e.kind, 'stream');
        expect(e.statusCode, 400);
        expect(e.userMessage, contains('30초'));
        // 사용자에게 보이는 문구까지 그대로 이어진다.
        expect(RegisterValidation.failureMessage(e), contains('30초'));
      }
    });

    test('길이 제한은 서버가 정한다 — 앱은 제한값을 보내지 않는다', () async {
      final file = await writeFile('clip2.mp4', 64);
      responders['createVideoUploadUrl'] = (_) => videoGrant(origin: cf.origin);
      await CloudflareService.uploadVideo(file);
      expect(calls.single.data.containsKey('maxDurationSeconds'), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // 삭제
  // ══════════════════════════════════════════════════════════════════════

  group('deleteImage', () {
    test('deleteOwnUpload에 URL만 넘긴다', () async {
      responders['deleteOwnUpload'] = (_) => {'deleted': true, 'kind': 'image'};
      await CloudflareService.deleteImage(
        'https://pub-abc123.r2.dev/party_images/alice/1-a.jpg',
      );
      expect(calls.single.name, 'deleteOwnUpload');
      expect(calls.single.data, {
        'url': 'https://pub-abc123.r2.dev/party_images/alice/1-a.jpg',
      });
    });

    test('남의 파일/우리 것이 아닌 URL은 서버가 거부하고 조용히 넘어간다', () async {
      responders['deleteOwnUpload'] = (_) => FirebaseFunctionsException(
        code: 'permission-denied',
        message: '본인이 올린 파일만 삭제할 수 있습니다.',
      );
      // 정리 경로라 예외를 던지면 안 된다(예전 구현도 조용히 무시했다).
      await CloudflareService.deleteImage('https://example.com/foreign.jpg');
      expect(calls, hasLength(1));
    });

    test('빈 URL은 서버를 부르지도 않는다', () async {
      await CloudflareService.deleteImage('');
      await CloudflareService.deleteImage('   ');
      expect(calls, isEmpty);
    });
  });

  group('deleteVideo', () {
    test('새 영상: deleteOwnUpload로 지우고 구경로를 부르지 않는다', () async {
      responders['deleteOwnUpload'] = (_) => {'deleted': true, 'kind': 'video'};
      await CloudflareService.deleteVideo(videoUid: 'a' * 32);

      expect(calls.single.name, 'deleteOwnUpload');
      expect(calls.single.data, {'videoUid': 'a' * 32});
      expect(cf.received, isEmpty);
    });

    test('URL만 있어도 uid를 뽑아 넘긴다(하위 호환)', () async {
      responders['deleteOwnUpload'] = (_) => {'deleted': true};
      await CloudflareService.deleteVideo(
        videoUrl: 'https://videodelivery.net/${'b' * 32}/manifest/video.m3u8',
      );
      expect(calls.single.data, {'videoUid': 'b' * 32});
    });

    test('옛 영상(소유자 불명)은 어떤 Cloudflare API도 직접 부르지 않는다', () async {
      // 예전에는 여기서 .env 토큰으로 Stream API를 직접 호출하는 폴백이
      // 돌았다. 그 폴백을 제거했으므로, 이제는 조용히 끝나야 한다 —
      // 옛 영상 정리는 전부 서버(contentCleanup.js)의 몫이다.
      final direct = <http.Request>[];
      CloudflareService.debugSetTransport(
        callable: (name, data) async {
          calls.add((name: name, data: data));
          throw FirebaseFunctionsException(
            code: 'permission-denied',
            message: '본인이 올린 동영상만 삭제할 수 있습니다.',
          );
        },
        client: MockClient((request) async {
          direct.add(request);
          return http.Response('{"success":true}', 200);
        }),
      );

      await CloudflareService.deleteVideo(videoUid: 'c' * 32);

      expect(calls.single.name, 'deleteOwnUpload');
      expect(
        direct,
        isEmpty,
        reason: '앱이 api.cloudflare.com을 직접 부르는 경로가 남아 있으면 안 된다',
      );
    });

    test('어떤 실패에서도 옛 토큰 경로로 새지 않는다', () async {
      for (final code in [
        'permission-denied',
        'not-found',
        'unavailable',
        'internal',
        'unauthenticated',
        'failed-precondition',
      ]) {
        final direct = <http.Request>[];
        CloudflareService.debugSetTransport(
          callable: (_, _) async =>
              throw FirebaseFunctionsException(code: code, message: 'x'),
          client: MockClient((request) async {
            direct.add(request);
            return http.Response('', 200);
          }),
        );
        // 예외를 밖으로 던지지도 않는다(정리 경로다).
        await CloudflareService.deleteVideo(videoUid: 'e' * 32);
        expect(direct, isEmpty, reason: 'code=$code 에서 직접 호출이 일어났다');
      }
    });

    test('uid를 알 수 없으면 아무것도 하지 않는다', () async {
      await CloudflareService.deleteVideo();
      await CloudflareService.deleteVideo(
        videoUrl: 'https://example.com/x.mp4',
      );
      expect(calls, isEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // 실패 분류 — 기존 안내 문구 갈래가 그대로 살아 있다
  // ══════════════════════════════════════════════════════════════════════

  group('실패 갈래', () {
    Future<Object> uploadFailure(FirebaseFunctionsException error) async {
      final file = await writeFile('x.jpg', 10);
      responders['createUploadUrl'] = (_) => error;
      try {
        await CloudflareService.uploadImage(file);
        fail('던져야 한다');
      } catch (e) {
        return e;
      }
    }

    test('로그인 만료·권한 없음·서버 설정 누락 → 사진을 지우라고 하지 않는다', () async {
      for (final code in [
        'unauthenticated',
        'permission-denied',
        'failed-precondition',
      ]) {
        final e = await uploadFailure(
          FirebaseFunctionsException(code: code, message: 'x'),
        );
        expect(e, isA<CloudflareUploadException>());
        expect((e as CloudflareUploadException).isAuthFailure, isTrue);
        expect(MediaUploadService.classify(e), MediaUploadFailureReason.auth);
        expect(
          RegisterValidation.failureMessage(e),
          RegisterValidation.uploadServiceAuthMessage,
        );
      }
    });

    test('일시적 서버 오류 → 네트워크 안내', () async {
      for (final code in ['unavailable', 'deadline-exceeded', 'internal']) {
        final e = await uploadFailure(
          FirebaseFunctionsException(code: code, message: 'x'),
        );
        expect((e as CloudflareUploadException).isServerFailure, isTrue);
        expect(
          MediaUploadService.classify(e),
          MediaUploadFailureReason.network,
        );
      }
    });

    test('용량·형식 거부 → 서버 문구를 그대로 보여준다', () async {
      final e = await uploadFailure(
        FirebaseFunctionsException(
          code: 'invalid-argument',
          message: '파일이 너무 큽니다. 최대 10MB까지 올릴 수 있어요.',
        ),
      );
      expect((e as CloudflareUploadException).userMessage, isNotNull);
      expect(
        RegisterValidation.failureMessage(e, stage: '업로드'),
        '파일이 너무 큽니다. 최대 10MB까지 올릴 수 있어요.',
      );
    });

    test('공용 업로더를 거쳐도 서버 문구가 살아남는다', () async {
      // 등록 화면들은 MediaUploadService로 감싸서 올린다 — 그 경로에서도
      // 사용자가 같은 안내를 봐야 한다.
      final file = await writeFile('y.jpg', 10);
      responders['createUploadUrl'] = (_) => FirebaseFunctionsException(
        code: 'invalid-argument',
        message: '지원하지 않는 이미지 형식입니다.',
      );
      try {
        await MediaUploadService.uploadNewMedia(
          media: [XFile(file.path)],
          logTag: 'test',
          uploadImage: CloudflareService.uploadImage,
        );
        fail('던져야 한다');
      } catch (e) {
        expect(
          RegisterValidation.failureMessage(e, stage: '업로드'),
          '지원하지 않는 이미지 형식입니다.',
        );
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // 준비 상태
  // ══════════════════════════════════════════════════════════════════════

  group('준비 상태 · 자격증명 부재', () {
    test('로그인했으면 업로드할 수 있다 — .env를 로드하지 않아도 된다', () {
      UserSession.userId = 'alice';
      expect(CloudflareService.isConfigured, isTrue);
    });

    test('로그아웃 상태면 막는다(콜러블이 로그인을 요구한다)', () {
      UserSession.userId = '';
      expect(CloudflareService.isConfigured, isFalse);
    });

    test('소스에 Cloudflare 자격증명을 읽는 코드가 한 줄도 없다', () {
      final src = File(
        'lib/services/cloudflare_service.dart',
      ).readAsStringSync();
      // 주석은 이력 설명을 위해 남아 있을 수 있으므로 코드 줄만 본다.
      final codeLines = src
          .split(RegExp(r'\r?\n'))
          .where((l) => !l.trimLeft().startsWith('//'))
          .join(' | ');
      expect(codeLines, isNot(contains('dotenv')));
      for (final key in [
        'CLOUDFLARE_ACCOUNT_ID',
        'CLOUDFLARE_API_TOKEN',
        'CLOUDFLARE_R2_BUCKET',
        'CLOUDFLARE_R2_PUBLIC_URL',
      ]) {
        expect(codeLines, isNot(contains(key)), reason: '$key 를 아직 읽는다');
      }
      // 옛 폴백이 되살아나지 않았는지 — 앱이 Cloudflare API를 직접 부르는
      // 코드가 남아 있으면 안 된다.
      expect(codeLines, isNot(contains('api.cloudflare.com')));
    });

    test('앱 전체(lib/)에도 Cloudflare 키를 읽는 코드가 없다', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsStringSync().split(RegExp(r'\r?\n'));
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final trimmed = line.trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
          if (line.contains("dotenv.env['CLOUDFLARE")) {
            offenders.add('${entity.path}:${i + 1}');
          }
        }
      }
      expect(offenders, isEmpty, reason: '남은 곳: ${offenders.join(', ')}');
    });
  });
}

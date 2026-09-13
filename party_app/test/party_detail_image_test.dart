import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:party_app/models/party_detail_image.dart';
import 'package:party_app/utils/image_dimensions.dart';
import 'package:party_app/utils/party_utils.dart';
import 'package:party_app/widgets/party_form/party_detail_image_section.dart';

// ══════════════════════════════════════════════════════════════════════════
// 파티 상세 이미지(detailImageUrl) 검증
//
// 이 기능이 지켜야 하는 것은 두 가지다:
//   1. 상세 이미지는 **대표 사진/동영상과 완전히 분리**된다 — images 배열,
//      대표 판정(coverMediaType/coverImageUrl), 갤러리 순서에 어떤 영향도
//      주지 않는다.
//   2. 아무리 긴 이미지라도 **메모리/GPU 텍스처 한계 안에서** 디코드된다.
//      화면 폭만 보고 cacheWidth를 정하면 세로 20000px짜리에서 그대로
//      터진다.
// ══════════════════════════════════════════════════════════════════════════

/// 지정한 크기의 실제 PNG 파일을 만든다 — probeImageFile이 헤더를 제대로
/// 읽는지 확인하려면 진짜 인코딩된 이미지가 필요하다.
Future<XFile> writePng(Directory dir, String name, int w, int h) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF112233),
  );
  final image = await recorder.endRecording().toImage(w, h);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  return XFile(file.path);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── 저장 형식 ─────────────────────────────────────────────────────────
  group('PartyDetailImage 직렬화', () {
    test('필드가 없는 기존 파티는 null — 상세에 아무것도 그리지 않는다', () {
      expect(PartyDetailImage.fromData(<String, dynamic>{}), isNull);
    });

    test('빈 문자열/공백도 "없음"으로 본다', () {
      expect(
        PartyDetailImage.fromData({PartyDetailImage.urlField: ''}),
        isNull,
      );
      expect(
        PartyDetailImage.fromData({PartyDetailImage.urlField: '   '}),
        isNull,
      );
    });

    test('URL + 원본 크기를 그대로 읽는다', () {
      final image = PartyDetailImage.fromData({
        PartyDetailImage.urlField: 'https://pub-x.r2.dev/a/b.jpg',
        PartyDetailImage.widthField: 860,
        PartyDetailImage.heightField: 5000,
      })!;
      expect(image.url, 'https://pub-x.r2.dev/a/b.jpg');
      expect(image.width, 860);
      expect(image.height, 5000);
      expect(image.aspectRatio, closeTo(860 / 5000, 1e-9));
    });

    test('크기가 0/음수/누락이면 비율은 null — 렌더러가 폴백을 쓴다', () {
      final image = PartyDetailImage.fromData({
        PartyDetailImage.urlField: 'https://pub-x.r2.dev/a/b.jpg',
        PartyDetailImage.widthField: 0,
      })!;
      expect(image.width, isNull);
      expect(image.height, isNull);
      expect(image.aspectRatio, isNull);
    });

    test('삭제 시 세 필드를 모두 비운다 — 키를 빼면 update가 옛 URL을 남긴다', () {
      final fields = PartyDetailImage.toFirestore(null);
      expect(fields[PartyDetailImage.urlField], '');
      expect(fields.containsKey(PartyDetailImage.widthField), isTrue);
      expect(fields[PartyDetailImage.widthField], isNull);
      expect(fields.containsKey(PartyDetailImage.heightField), isTrue);
      expect(fields[PartyDetailImage.heightField], isNull);

      // 그 결과를 다시 읽으면 "없음"이어야 순환이 닫힌다.
      expect(
        PartyDetailImage.fromData(Map<String, dynamic>.from(fields)),
        isNull,
      );
    });

    test('저장 → 읽기 왕복에서 값이 보존된다', () {
      const original = PartyDetailImage(
        url: 'https://pub-x.r2.dev/party_images/detail/u1/1.png',
        width: 1080,
        height: 9000,
      );
      final restored = PartyDetailImage.fromData(
        Map<String, dynamic>.from(PartyDetailImage.toFirestore(original)),
      )!;
      expect(restored.url, original.url);
      expect(restored.width, original.width);
      expect(restored.height, original.height);
    });
  });

  // ── 받아들이는 파일 ───────────────────────────────────────────────────
  group('허용 확장자', () {
    test('JPG · JPEG · PNG · WebP만 받는다(대소문자 무관)', () {
      for (final path in ['a.jpg', 'a.JPEG', 'b.png', 'c.WEBP']) {
        expect(
          PartyDetailImage.hasAllowedExtension(path),
          isTrue,
          reason: '$path 는 허용돼야 한다',
        );
      }
    });

    test('동영상은 확장자 단계에서 막힌다', () {
      for (final path in ['clip.mp4', 'clip.MOV', 'clip.m3u8']) {
        expect(
          PartyDetailImage.hasAllowedExtension(path),
          isFalse,
          reason: '$path 는 상세 이미지가 될 수 없다',
        );
      }
    });

    test('gif · heic · 확장자 없음도 막는다', () {
      for (final path in ['a.gif', 'a.heic', 'noext', 'trailingdot.']) {
        expect(PartyDetailImage.hasAllowedExtension(path), isFalse);
      }
    });

    test('용량 상한은 10MB', () {
      expect(PartyDetailImage.maxFileBytes, 10 * 1024 * 1024);
      expect(PartyDetailImage.maxFileMegabytes, 10);
    });
  });

  // ── 메모리/텍스처 상한 ────────────────────────────────────────────────
  group('decodeWidthFor — 초장문 이미지 디코드 상한', () {
    // 흔한 캔바 상세페이지 크기. 여기까지는 손대지 않아야 글자가 안 뭉개진다.
    test('원본보다 크게 디코드하지 않는다(확대 없음)', () {
      final w = PartyDetailImage.decodeWidthFor(
        viewWidth: 390,
        devicePixelRatio: 3,
        imageWidth: 860,
        imageHeight: 5000,
      );
      expect(w, 860, reason: '860×5000은 원본 그대로 디코드돼야 한다');
    });

    test('작은 이미지도 화면 폭까지 늘리지 않는다', () {
      final w = PartyDetailImage.decodeWidthFor(
        viewWidth: 390,
        devicePixelRatio: 3,
        imageWidth: 400,
        imageHeight: 600,
      );
      expect(w, 400);
    });

    test('세로 20000px짜리는 크게 줄어든다 — 화면 폭만 봤다면 안 줄었을 것', () {
      const imageWidth = 1080.0;
      const imageHeight = 20000.0;
      final w = PartyDetailImage.decodeWidthFor(
        viewWidth: 390,
        devicePixelRatio: 3,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );
      expect(
        w,
        lessThan(imageWidth),
        reason: '원본 그대로면 RGBA 약 86MB — 저사양 기기에서 OOM이다',
      );
      final decodedHeight = w / (imageWidth / imageHeight);
      expect(
        decodedHeight,
        lessThanOrEqualTo(PartyDetailImage.maxDecodeHeight + 1),
        reason: 'GPU 텍스처 한 변 한계를 넘으면 그림이 아예 안 그려질 수 있다',
      );
    });

    test('크기를 모르면 보수적인 폭으로 떨어진다', () {
      final w = PartyDetailImage.decodeWidthFor(
        viewWidth: 390,
        devicePixelRatio: 4,
        imageWidth: null,
        imageHeight: null,
      );
      expect(w, PartyDetailImage.fallbackDecodeWidth);
    });

    test('아주 넓은 화면에서도 가로 상한을 넘지 않는다', () {
      final w = PartyDetailImage.decodeWidthFor(
        viewWidth: 2000,
        devicePixelRatio: 3,
        imageWidth: 8000,
        imageHeight: 8000,
      );
      expect(w, lessThanOrEqualTo(PartyDetailImage.maxDecodeWidth));
    });

    // 개별 사례가 아니라 **불변식**으로 확인한다 — 나중에 상수를 조정해도
    // 이 세 가지가 깨지면 안 된다.
    test('불변식: 어떤 비율에서도 총 픽셀·세로·원본 폭 상한을 지킨다', () {
      const widths = [400.0, 860.0, 1080.0, 2160.0, 4000.0];
      const heights = [300.0, 1200.0, 5000.0, 20000.0, 60000.0];
      for (final iw in widths) {
        for (final ih in heights) {
          for (final dpr in [1.0, 2.0, 3.0, 4.0]) {
            final w = PartyDetailImage.decodeWidthFor(
              viewWidth: 390,
              devicePixelRatio: dpr,
              imageWidth: iw,
              imageHeight: ih,
            );
            final label = '${iw.toInt()}x${ih.toInt()} @${dpr}x -> $w';

            expect(w, greaterThanOrEqualTo(1), reason: label);
            expect(w, lessThanOrEqualTo(iw.ceil()), reason: '확대 금지 — $label');

            final decodedHeight = w * ih / iw;
            expect(
              decodedHeight,
              lessThanOrEqualTo(PartyDetailImage.maxDecodeHeight + 1),
              reason: '세로 상한 — $label',
            );
            expect(
              w * decodedHeight,
              lessThanOrEqualTo(PartyDetailImage.maxDecodePixels + 1),
              reason: '총 픽셀 상한 — $label',
            );
          }
        }
      }
    });

    test('상한이 유효한 값으로 설정돼 있다', () {
      expect(PartyDetailImage.maxDecodeWidth, greaterThan(0));
      expect(PartyDetailImage.maxDecodeHeight, greaterThan(0));
      expect(PartyDetailImage.maxDecodePixels, greaterThan(0));
      // 텍스처 한 변 한계는 실기기 대다수가 지원하는 8192 이하여야 한다.
      expect(PartyDetailImage.maxDecodeHeight, lessThanOrEqualTo(8192));
    });
  });

  // ── 등록/수정 화면이 들고 다니는 상태 ─────────────────────────────────
  group('PartyDetailImageDraft', () {
    test('빈 상태', () {
      expect(PartyDetailImageDraft.empty.isEmpty, isTrue);
      expect(PartyDetailImageDraft.empty.hasNewFile, isFalse);
      expect(PartyDetailImageDraft.empty.resolve(), isNull);
    });

    test('파티 문서에서 복원 — 수정/재등록이 같은 값을 얻는다', () {
      final draft = PartyDetailImageDraft.fromPartyData({
        PartyDetailImage.urlField: 'https://pub-x.r2.dev/a.png',
        PartyDetailImage.widthField: 800,
        PartyDetailImage.heightField: 6400,
      });
      expect(draft.uploadedUrl, 'https://pub-x.r2.dev/a.png');
      expect(draft.width, 800);
      expect(draft.height, 6400);
      expect(draft.hasNewFile, isFalse);
    });

    test('수정 없이 저장하면 기존 URL이 그대로 남는다', () {
      final draft = PartyDetailImageDraft.fromPartyData({
        PartyDetailImage.urlField: 'https://pub-x.r2.dev/old.png',
        PartyDetailImage.widthField: 800,
        PartyDetailImage.heightField: 6400,
      });
      // 새 파일이 없으므로 업로드도 없고 newUploadedUrl도 없다.
      final resolved = draft.resolve();
      expect(resolved!.url, 'https://pub-x.r2.dev/old.png');
      expect(resolved.width, 800);
    });

    test('교체하면 새로 올린 URL이 이긴다', () {
      const draft = PartyDetailImageDraft(
        uploadedUrl: 'https://pub-x.r2.dev/old.png',
        width: 900,
        height: 7000,
      );
      final resolved = draft.resolve(
        newUploadedUrl: 'https://pub-x.r2.dev/new.png',
      );
      expect(resolved!.url, 'https://pub-x.r2.dev/new.png');
      // 크기는 새로 고른 파일의 것(draft가 이미 들고 있다).
      expect(resolved.width, 900);
      expect(resolved.height, 7000);
    });

    test('삭제하면 저장값이 null — 문서에서 지워진다', () {
      expect(PartyDetailImageDraft.empty.resolve(), isNull);
      final fields = PartyDetailImage.toFirestore(
        PartyDetailImageDraft.empty.resolve(),
      );
      expect(fields[PartyDetailImage.urlField], '');
    });

    test('저장 후에는 로컬 파일을 놓아 같은 파일을 두 번 올리지 않는다', () {
      final draft = PartyDetailImageDraft(
        uploadedUrl: 'https://pub-x.r2.dev/old.png',
        newFile: XFile('/tmp/new.png'),
        width: 900,
        height: 7000,
      );
      expect(draft.hasNewFile, isTrue);

      final settled = draft.settled(
        newUploadedUrl: 'https://pub-x.r2.dev/new.png',
      );
      expect(settled.hasNewFile, isFalse);
      expect(settled.uploadedUrl, 'https://pub-x.r2.dev/new.png');
      expect(settled.width, 900);

      // 다시 저장해도 올릴 것이 없다.
      expect(settled.resolve()!.url, 'https://pub-x.r2.dev/new.png');
    });

    test('삭제 뒤 저장하면 settled도 빈 상태로 남는다', () {
      expect(PartyDetailImageDraft.empty.settled().isEmpty, isTrue);
    });

    test('지문은 교체·삭제를 구분한다 — 수정 화면 이탈 방지용', () {
      const a = PartyDetailImageDraft(uploadedUrl: 'u1');
      final b = PartyDetailImageDraft(
        uploadedUrl: 'u1',
        newFile: XFile('/tmp/x.png'),
      );
      expect(a.signature, isNot(b.signature));
      expect(a.signature, isNot(PartyDetailImageDraft.empty.signature));
    });

    test('임시저장 왕복 — URL과 로컬 파일 경로가 모두 살아남는다', () async {
      final dir = await Directory.systemTemp.createTemp('detail_draft');
      addTearDown(() => dir.delete(recursive: true));
      final png = await writePng(dir, 'pick.png', 40, 200);

      final draft = PartyDetailImageDraft(
        uploadedUrl: 'https://pub-x.r2.dev/old.png',
        newFile: XFile(png.path),
        width: 40,
        height: 200,
      );
      final restored = PartyDetailImageDraft.fromDraftMap(draft.toDraftMap());
      expect(restored.uploadedUrl, 'https://pub-x.r2.dev/old.png');
      expect(restored.newFile?.path, png.path);
      expect(restored.width, 40);
      expect(restored.height, 200);
    });

    test('임시저장 사이에 파일이 사라지면 경로를 버리고 알린다', () {
      var missing = false;
      final restored = PartyDetailImageDraft.fromDraftMap(
        const PartyDetailImageDraft(
          uploadedUrl: 'https://pub-x.r2.dev/old.png',
        ).toDraftMap()..['newFilePath'] = '/definitely/not/here-9182.png',
        missingFile: () => missing = true,
      );
      expect(missing, isTrue);
      expect(restored.newFile, isNull);
      // 이미 올라가 있던 URL은 남는다 — 파일이 사라졌다고 이미지를 잃으면 안 된다.
      expect(restored.uploadedUrl, 'https://pub-x.r2.dev/old.png');
    });

    test('임시저장에 아무것도 없으면 빈 상태', () {
      expect(PartyDetailImageDraft.fromDraftMap(null).isEmpty, isTrue);
      expect(PartyDetailImageDraft.fromDraftMap('쓰레기').isEmpty, isTrue);
      expect(
        PartyDetailImageDraft.fromDraftMap(<String, dynamic>{}).isEmpty,
        isTrue,
      );
    });
  });

  // ── 업로드 전 파일 검사 ───────────────────────────────────────────────
  group('probeImageFile — 업로드 전 디코딩 검사', () {
    test('정상 이미지는 원본 픽셀 크기를 돌려준다', () async {
      final dir = await Directory.systemTemp.createTemp('detail_probe');
      addTearDown(() => dir.delete(recursive: true));

      final file = await writePng(dir, 'tall.png', 120, 900);
      final probe = await probeImageFile(file);
      expect(probe, isNotNull);
      expect(probe!.width, 120);
      expect(probe.height, 900);
    });

    test('손상된 파일은 null — 업로드에 태우지 않는다', () async {
      final dir = await Directory.systemTemp.createTemp('detail_probe_bad');
      addTearDown(() => dir.delete(recursive: true));

      final broken = File('${dir.path}/broken.png');
      await broken.writeAsBytes(
        Uint8List.fromList(List<int>.generate(512, (i) => i % 256)),
      );
      expect(await probeImageFile(XFile(broken.path)), isNull);
    });

    test('없는 파일은 null', () async {
      expect(await probeImageFile(XFile('/nope/missing-8241.png')), isNull);
    });

    test('0바이트 파일은 null', () async {
      final dir = await Directory.systemTemp.createTemp('detail_probe_empty');
      addTearDown(() => dir.delete(recursive: true));
      final empty = File('${dir.path}/empty.png');
      await empty.writeAsBytes(Uint8List(0));
      expect(await probeImageFile(XFile(empty.path)), isNull);
    });
  });

  // ── 대표 미디어 회귀 ──────────────────────────────────────────────────
  //
  // 상세 이미지가 들어와도 카드 썸네일·상단 갤러리가 흔들리지 않아야 한다.
  // 아래는 party_cover_media_test.dart와 같은 진입점(getPartyCoverMedia)에
  // **상세 이미지 필드만 더해** 결과가 완전히 동일한지 확인한다.
  group('대표 사진/동영상 회귀 — 상세 이미지가 끼어들지 않는다', () {
    Map<String, dynamic> baseParty() => <String, dynamic>{
      'title': '테스트 파티',
      'images': [
        'https://example.com/photo1.jpg',
        'https://example.com/photo2.jpg',
      ],
      'videoUrl': 'https://videodelivery.net/abc123/manifest/video.m3u8',
      'videoUid': 'abc123',
      'videoThumbnailUrl':
          'https://videodelivery.net/abc123/thumbnails/thumbnail.jpg',
      'coverMediaType': 'image',
      'coverImageUrl': 'https://example.com/photo1.jpg',
      'coverThumbnailUrl': 'https://example.com/photo1.jpg',
    };

    test('대표가 사진일 때 — 상세 이미지 유무로 결과가 갈리지 않는다', () {
      final without = getPartyCoverMedia(baseParty())!;
      final with_ = getPartyCoverMedia(
        baseParty()..addAll(
          PartyDetailImage.toFirestore(
            const PartyDetailImage(
              url: 'https://pub-x.r2.dev/party_images/detail/u1/1.png',
              width: 860,
              height: 5000,
            ),
          ),
        ),
      )!;

      expect(with_.type, without.type);
      expect(with_.imageUrl, without.imageUrl);
      expect(with_.videoUrl, without.videoUrl);
      expect(with_.videoUid, without.videoUid);
      expect(with_.thumbnailUrl, without.thumbnailUrl);
      expect(with_.isVideo, isFalse);
    });

    test('대표가 동영상일 때도 동일하다', () {
      Map<String, dynamic> videoCover() => baseParty()
        ..['coverMediaType'] = 'video'
        ..['coverImageUrl'] = null
        ..['coverVideoUid'] = 'abc123'
        ..['coverVideoUrl'] =
            'https://videodelivery.net/abc123/manifest/video.m3u8'
        ..['coverThumbnailUrl'] =
            'https://videodelivery.net/abc123/thumbnails/thumbnail.jpg';

      final without = getPartyCoverMedia(videoCover())!;
      final with_ = getPartyCoverMedia(
        videoCover()..addAll(
          PartyDetailImage.toFirestore(
            const PartyDetailImage(
              url: 'https://pub-x.r2.dev/party_images/detail/u1/1.png',
              width: 860,
              height: 5000,
            ),
          ),
        ),
      )!;

      expect(with_.type, 'video');
      expect(with_.type, without.type);
      expect(with_.videoUrl, without.videoUrl);
      expect(with_.videoUid, without.videoUid);
      expect(with_.thumbnailUrl, without.thumbnailUrl);
    });

    test('상세 이미지 URL이 images 배열이나 대표 필드에 절대 들어가지 않는다', () {
      const detailUrl = 'https://pub-x.r2.dev/party_images/detail/u1/1.png';
      final party = baseParty()
        ..addAll(
          PartyDetailImage.toFirestore(
            const PartyDetailImage(url: detailUrl, width: 860, height: 5000),
          ),
        );

      final images = (party['images'] as List).cast<String>();
      expect(images, hasLength(2), reason: '사진 장수가 늘면 안 된다');
      expect(images.contains(detailUrl), isFalse);
      expect(
        images.first,
        'https://example.com/photo1.jpg',
        reason: '대표 사진은 여전히 index 0이어야 한다',
      );
      expect(party['coverImageUrl'], isNot(detailUrl));
      expect(party['coverThumbnailUrl'], isNot(detailUrl));
      expect(party['mainImageUrl'], isNot(detailUrl));
    });

    test('상세 이미지는 별도 필드 하나로만 산다', () {
      final fields = PartyDetailImage.toFirestore(
        const PartyDetailImage(url: 'https://pub-x.r2.dev/d.png'),
      );
      // 대표 미디어 계열 필드를 하나도 건드리지 않는다.
      const coverFields = [
        'images',
        'imageUrls',
        'mainImageUrl',
        'coverImageUrl',
        'coverMediaType',
        'coverVideoUid',
        'coverVideoUrl',
        'coverThumbnailUrl',
        'videoUrl',
        'videoUid',
        'videoThumbnailUrl',
        'basicCardPhotoCrops',
        'basicCardVideoFocalX',
      ];
      for (final f in coverFields) {
        expect(fields.containsKey(f), isFalse, reason: '$f 를 건드리면 안 된다');
      }
      expect(fields.keys.toSet(), {
        PartyDetailImage.urlField,
        PartyDetailImage.widthField,
        PartyDetailImage.heightField,
      });
    });

    test('저장 위치가 대표 사진 폴더와 겹치지 않는다', () {
      expect(PartyDetailImage.storageFolder, 'party_images/detail');
      expect(
        PartyDetailImage.storageFolder.startsWith('party_images/'),
        isTrue,
      );
      expect(PartyDetailImage.storageFolder, isNot('party_images'));
    });
  });

  // 서버 미디어 정리(functions/contentCleanup.js)가 이 필드를 알고 있어야
  // 파티를 지울 때 R2 원본까지 함께 사라진다. 파일명을 그대로 문자열로
  // 비교해, 한쪽만 바꾸면 여기서 걸리게 한다.
  group('서버 정리 연동', () {
    test('필드명이 서버 imageFields 목록에 들어 있다', () {
      final cleanup = File('../functions/contentCleanup.js');
      if (!cleanup.existsSync()) {
        markTestSkipped('functions/contentCleanup.js 없음 — 앱 단독 체크아웃');
        return;
      }
      final src = cleanup.readAsStringSync();
      final partyBlock = src.substring(
        src.indexOf('party: {'),
        src.indexOf('place: {'),
      );
      expect(
        partyBlock.contains("'${PartyDetailImage.urlField}'"),
        isTrue,
        reason:
            'contentCleanup.js의 party.imageFields에 '
            '${PartyDetailImage.urlField}가 없으면 파티를 지워도 '
            '상세 이미지만 R2에 남는다',
      );
    });
  });

  // 상수가 서로 모순되지 않는지 — sqrt 계산이 성립하는 범위인지 확인.
  test('디코드 상한 상수끼리 모순이 없다', () {
    expect(
      math.sqrt(PartyDetailImage.maxDecodePixels),
      greaterThan(PartyDetailImage.maxDecodeWidth.toDouble()),
      reason:
          '정사각형 이미지가 총 픽셀 상한 때문에 가로 상한보다 더 줄면, '
          '가로 상한이 사실상 무의미해진다',
    );
  });
}

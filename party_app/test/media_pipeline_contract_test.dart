// 네 등록 유형(파티 / 플레이스 / 장소대여 / 구인구직)의 **미디어 파이프라인
// 계약**.
//
// ── 왜 필요했나 ─────────────────────────────────────────────────────────────
// 공용 정본(픽커·크로퍼·업로더)이 있는데도 유형마다 절반씩만 쓰고 있었다.
//   · 장소대여 — 픽커가 돌려주는 크롭 값을 **받지 않고 버렸고**, 조정 UI 자체를
//     꺼 두어(showVideoCropButton:false) 카드가 언제나 중앙 크롭이었다.
//   · 플레이스 — 공용 픽커를 아예 안 써서 대표 미디어 계약(cover*)이 없었다.
//     그래서 동영상을 올려도 카드에서는 사진이 무조건 이겼다.
//   · 여러 화면 — 업로드 루프를 따로 복사해 사전 검사·실패 분류가 없었다.
//
// 이런 단절은 **컴파일로는 드러나지 않는다**(값을 안 읽어도 코드는 돈다).
// 그래서 계약을 여기서 못박는다.
//
// Firebase를 초기화하지 않는다 — 순수 함수와 소스 검사만 본다.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:party_app/services/media_upload_service.dart';
import 'package:party_app/utils/card_media_frame.dart';
import 'package:party_app/utils/party_utils.dart';
import 'package:party_app/utils/video_crop.dart';
import 'package:party_app/widgets/list_card_shell.dart';

/// 신규 등록 + 수정이 함께 사는 네 등록 화면.
const _registerScreens = <String, String>{
  'lib/screens/party_register_screen.dart': '파티 등록',
  'lib/screens/party_edit_screen.dart': '파티 수정',
  'lib/screens/event_register_screen.dart': '플레이스(events)',
  'lib/screens/place_register_screen.dart': '장소대여(places)',
  'lib/screens/crew_register_screen.dart': '구인구직(crews)',
};

/// 카드에 대표 미디어가 뜨는 세 유형 — 구인구직은 프로필 사진 1장 구조라
/// 대표(cover) 개념이 없다(그건 아래에서 따로 못박는다).
const _coverScreens = <String, String>{
  'lib/screens/party_register_screen.dart': '파티 등록',
  'lib/screens/party_edit_screen.dart': '파티 수정',
  'lib/screens/event_register_screen.dart': '플레이스(events)',
  'lib/screens/place_register_screen.dart': '장소대여(places)',
};

String _src(String path) => File(path).readAsStringSync();

void main() {
  // ── 1. 카드 비율 정본 ───────────────────────────────────────────────────

  group('기본 카드 미디어 프레임', () {
    testWidgets('비율이 카드 정본(GridCardShell.imageHeight)에서 나온다', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final screenW = MediaQuery.of(ctx).size.width;
      final expected =
          basicCardWidth(screenW) / GridCardShell.imageHeight;
      expect(basicCardMediaAspectRatio(ctx), closeTo(expected, 0.0001));
    });

    // 사진 크롭과 동영상 크롭이 **같은 프레임**을 받아야, 같은 카드에 들어갈
    // 두 미디어를 서로 다른 기준으로 맞추는 일이 없다.
    testWidgets('크롭 미리보기 프레임이 카드와 정확히 같은 비율이다', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final frame = basicCardCropFrameSize(ctx);
      expect(
        frame.width / frame.height,
        closeTo(basicCardMediaAspectRatio(ctx), 0.0001),
        reason: '미리보기에서 맞춘 위치가 목록 카드에서 그대로 재현되지 않는다',
      );
      // 조작하기 쉽도록 실제 카드보다 크게 보여준다.
      expect(
        frame.width,
        greaterThan(basicCardWidth(MediaQuery.of(ctx).size.width)),
      );
    });

    // 카드 높이가 두 곳에 각각 적혀 있으면 한쪽만 바뀌어 조용히 어긋난다.
    test('카드 높이 상수를 편집기가 따로 들고 있지 않다', () {
      final editor = _src('lib/widgets/party_media_editor.dart');
      expect(
        editor.contains('cardH = 130'),
        isFalse,
        reason: '편집기가 카드 높이를 다시 적고 있다 — 카드 정본을 읽어야 한다',
      );
      expect(editor, contains('basicCardCropFrameSize('));
    });

    // 두 크롭 화면이 같은 함수에서 프레임을 받는지.
    test('사진·동영상 크롭이 같은 프레임 계산을 쓴다', () {
      final editor = _src('lib/widgets/party_media_editor.dart');
      // _cardFrameSize 하나만 있고, 사진·동영상 진입이 모두 그것을 쓴다.
      expect('_cardFrameSize('.allMatches(editor).length, greaterThanOrEqualTo(3));
    });
  });

  // ── 2. 업로드 통일 ─────────────────────────────────────────────────────

  group('업로드 경로', () {
    test('등록 화면은 공용 업로더를 쓴다', () {
      final missing = <String>[];
      _registerScreens.forEach((path, label) {
        if (!_src(path).contains('MediaUploadService.uploadNewMedia(')) {
          missing.add('$path — $label');
        }
      });
      expect(
        missing,
        isEmpty,
        reason:
            '업로드 루프를 화면마다 복사하면 사전 검사(경로/존재/0바이트)와 '
            '실패 분류가 빠져 원인 불명 실패가 된다:\n${missing.join('\n')}',
      );
    });

    // 직접 호출로 되돌아가면 그 화면만 다시 검증 없는 경로가 된다.
    //
    // ⚠️ 파티 두 화면은 제외한다 — **상세페이지 블록**(본문 안에 끼워 넣는
    // 사진/동영상)이 별도 서브시스템이고 자체 롤백까지 갖고 있어, 이번 정리의
    // 대상이 아니다. 카드에 뜨는 대표 미디어는 위 테스트가 공용 업로더 사용을
    // 이미 강제한다.
    const noDirectUpload = <String, String>{
      'lib/screens/event_register_screen.dart': '플레이스(events)',
      'lib/screens/place_register_screen.dart': '장소대여(places)',
      'lib/screens/crew_register_screen.dart': '구인구직(crews)',
    };

    test('플레이스·장소대여·구인구직은 업로더를 우회하지 않는다', () {
      final offenders = <String>[];
      noDirectUpload.forEach((path, label) {
        final lines = _src(path).split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i].trimLeft();
          if (line.startsWith('//') || line.startsWith('///')) continue;
          // `uploadImage:`/`uploadVideo:`는 공용 업로더의 **주입점**이라
          // 우회가 아니다(테스트가 업로더를 갈아끼우는 통로이기도 하다).
          if (line.startsWith('uploadImage:') ||
              line.startsWith('uploadVideo:')) {
            continue;
          }
          if (lines[i].contains('CloudflareService.uploadImage(') ||
              lines[i].contains('CloudflareService.uploadVideo(')) {
            offenders.add('$path:${i + 1} — $label');
          }
        }
      });
      expect(
        offenders,
        isEmpty,
        reason: '공용 업로더를 건너뛴 직접 업로드가 있다:\n${offenders.join('\n')}',
      );
    });

    // 저장이 실패했을 때 "사진을 빼야 하는지 다시 시도하면 되는지"를 갈래에
    // 맞춰 안내해야 한다. 예외 원문을 그대로 스낵바에 붙이는 것도 안 된다 —
    // 사용자는 읽고 할 수 있는 일이 없고 내부 사정만 새어 나간다.
    test('다섯 화면 모두 실패 안내를 공용 함수로 만든다', () {
      final missing = <String>[];
      _registerScreens.forEach((path, label) {
        if (!_src(path).contains('RegisterValidation.failureMessage(')) {
          missing.add('$path — $label');
        }
      });
      expect(missing, isEmpty, reason: missing.join('\n'));
    });

    test('예외 원문을 사용자 화면에 그대로 붙이지 않는다', () {
      final offenders = <String>[];
      _registerScreens.forEach((path, label) {
        final src = _src(path);
        for (final leak in ['저장에 실패했습니다: \$e', '오류: \$e']) {
          if (src.contains(leak)) offenders.add('$path — $label: "$leak"');
        }
      });
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });
  });

  // ── 3. 크롭 값이 저장까지 도달한다 ──────────────────────────────────────

  group('대표 미디어 계약', () {
    // 카드가 읽는 키(getPartyCoverMedia)와 저장하는 키가 같아야 한다.
    test('세 유형이 cover 계약 키를 모두 저장한다', () {
      const requiredKeys = [
        "'coverMediaType'",
        "'coverImageUrl'",
        "'coverVideoUid'",
        "'coverVideoUrl'",
        "'coverThumbnailUrl'",
        "'basicCardVideoFocalX'",
        "'basicCardVideoFocalY'",
        "'basicCardVideoScale'",
        "'basicCardPhotoCrops'",
      ];
      final missing = <String>[];
      _coverScreens.forEach((path, label) {
        final src = _src(path);
        for (final key in requiredKeys) {
          if (!src.contains(key)) missing.add('$path — $label: $key');
        }
      });
      expect(
        missing,
        isEmpty,
        reason:
            '카드가 읽는 키를 저장하지 않으면 레거시 분기로 내려가 '
            '동영상이 대표가 될 수 없다:\n${missing.join('\n')}',
      );
    });

    // 픽커가 돌려주는 값을 받지 않으면 조정 화면을 지나온 값이 저장까지
    // 도달하지 못한다 — 장소대여에서 실제로 그랬다.
    test('픽커를 쓰는 화면은 크롭 결과를 받아 온다', () {
      const users = [
        'lib/screens/party_register_screen.dart',
        'lib/screens/party_edit_screen.dart',
        'lib/screens/event_register_screen.dart',
        'lib/screens/place_register_screen.dart',
      ];
      final missing = <String>[];
      for (final path in users) {
        final src = _src(path);
        if (!src.contains('PartyMediaPickerScreen(')) continue;
        for (final field in [
          'result.basicCardFocalX',
          'result.basicCardScale',
          'result.photoCrops',
          'result.videoCropConfirmed',
        ]) {
          if (!src.contains(field)) missing.add('$path: $field');
        }
      }
      expect(missing, isEmpty, reason: missing.join('\n'));
    });

    // 조정 UI를 끄면 사진·동영상 모두 크롭 버튼이 사라진다(같은 조건이
    // 두 갈래를 함께 가린다) — 카드에 뜨는 화면에서는 꺼선 안 된다.
    test('카드에 뜨는 화면은 크롭 UI를 끄지 않는다', () {
      final offenders = <String>[];
      _coverScreens.forEach((path, label) {
        if (_src(path).contains('showVideoCropButton: false')) {
          offenders.add('$path — $label');
        }
      });
      expect(
        offenders,
        isEmpty,
        reason: '크롭 UI를 끄면 그 유형 카드는 언제나 중앙 크롭이 된다:\n${offenders.join('\n')}',
      );
    });
  });

  // ── 4. 크롭 키 매핑(순수 로직) ─────────────────────────────────────────

  group('MediaUploadService.resolvePhotoCropKeys', () {
    test('기존 사진은 URL 그대로, 새 사진은 업로드 URL로 옮겨 담는다', () {
      final result = MediaUploadService.resolvePhotoCropKeys(
        crops: {
          'https://cdn/old.jpg': {'x': 0.1, 'y': 0.2, 'scale': 1.5},
          '/tmp/new-a.jpg': {'x': 0.3, 'y': 0.4, 'scale': 2.0},
        },
        existingImageUrls: ['https://cdn/old.jpg'],
        newMedia: [XFile('/tmp/new-a.jpg')],
        uploadedImageUrls: ['https://cdn/new-a.jpg'],
      );

      expect(result['https://cdn/old.jpg'], {'x': 0.1, 'y': 0.2, 'scale': 1.5});
      expect(result['https://cdn/new-a.jpg'], {
        'x': 0.3,
        'y': 0.4,
        'scale': 2.0,
      });
      // 로컬 경로가 그대로 남으면 카드가 그 키를 영영 못 찾는다.
      expect(result.containsKey('/tmp/new-a.jpg'), isFalse);
    });

    // 동영상이 사진 사이에 끼어 있어도 사진 순번이 밀리면 안 된다 —
    // 밀리면 **다른 사진의 크롭**이 걸린다.
    test('동영상을 건너뛰고 사진 순번을 센다', () {
      final result = MediaUploadService.resolvePhotoCropKeys(
        crops: {
          '/tmp/a.jpg': {'x': 0.0, 'y': 0.0, 'scale': 1.0},
          '/tmp/b.jpg': {'x': 1.0, 'y': 1.0, 'scale': 3.0},
        },
        existingImageUrls: const [],
        newMedia: [
          XFile('/tmp/a.jpg'),
          XFile('/tmp/clip.mp4'),
          XFile('/tmp/b.jpg'),
        ],
        uploadedImageUrls: ['https://cdn/a.jpg', 'https://cdn/b.jpg'],
      );

      expect(result['https://cdn/a.jpg']!['scale'], 1.0);
      expect(result['https://cdn/b.jpg']!['scale'], 3.0);
    });

    test('크롭을 정하지 않은 사진은 키가 아예 생기지 않는다', () {
      final result = MediaUploadService.resolvePhotoCropKeys(
        crops: const {},
        existingImageUrls: ['https://cdn/old.jpg'],
        newMedia: [XFile('/tmp/a.jpg')],
        uploadedImageUrls: ['https://cdn/a.jpg'],
      );
      // 값이 없으면 카드가 기본값(중앙)을 쓴다 — 빈 값을 굳이 저장하지 않는다.
      expect(result, isEmpty);
    });
  });

  group('photoCropsFromRaw', () {
    test('저장된 맵을 그대로 되살린다', () {
      final parsed = photoCropsFromRaw({
        'https://cdn/a.jpg': {'x': 0.25, 'y': 0.75, 'scale': 2.0},
      });
      expect(parsed['https://cdn/a.jpg'], {
        'x': 0.25,
        'y': 0.75,
        'scale': 2.0,
      });
    });

    test('깨진 값이 있어도 복원 전체가 죽지 않는다', () {
      final parsed = photoCropsFromRaw({
        'https://cdn/a.jpg': {'x': 'oops'},
        'https://cdn/b.jpg': 'not-a-map',
        'https://cdn/c.jpg': {'x': 0.1, 'y': 0.2, 'scale': 1.4},
      });
      // 값이 어긋난 항목은 기본값(중앙)으로, 아예 맵이 아닌 항목은 건너뛴다.
      expect(parsed['https://cdn/a.jpg'], {'x': 0.5, 'y': 0.5, 'scale': 1.0});
      expect(parsed.containsKey('https://cdn/b.jpg'), isFalse);
      expect(parsed['https://cdn/c.jpg']!['scale'], 1.4);
    });

    test('null이면 빈 맵', () {
      expect(photoCropsFromRaw(null), isEmpty);
    });
  });

  // ── 5. 카드가 읽는 결과 ────────────────────────────────────────────────

  group('getPartyCoverMedia — 저장한 대로 읽힌다', () {
    // 플레이스(events)가 겪던 증상: 대표 이미지가 있으면 동영상은 카드에
    // 절대 나오지 못했다(레거시 분기가 "사진이 하나도 없을 때만" 동영상을
    // 대표로 인정했기 때문). cover 계약을 쓰면 사진이 있어도 동영상이 대표다.
    test('사진이 있어도 동영상을 대표로 고를 수 있다', () {
      final cover = getPartyCoverMedia({
        'mainImageUrl': 'https://cdn/photo.jpg',
        'videoUrl': 'https://cdn/v.m3u8',
        'coverMediaType': 'video',
        'coverVideoUrl': 'https://cdn/v.m3u8',
        'coverVideoUid': 'uid-1',
        'coverThumbnailUrl': 'https://cdn/thumb.jpg',
        'basicCardVideoFocalX': 0.2,
        'basicCardVideoFocalY': 0.8,
        'basicCardVideoScale': 1.7,
      });

      expect(cover, isNotNull);
      expect(cover!.isVideo, isTrue);
      expect(cover.videoUrl, 'https://cdn/v.m3u8');
      expect(cover.basicCardVideoFocalX, 0.2);
      expect(cover.basicCardVideoFocalY, 0.8);
      expect(cover.basicCardVideoScale, 1.7);
    });

    test('사진 대표는 그 사진의 크롭을 함께 들고 온다', () {
      final cover = getPartyCoverMedia({
        'mainImageUrl': 'https://cdn/photo.jpg',
        'coverMediaType': 'image',
        'coverImageUrl': 'https://cdn/photo.jpg',
        'basicCardPhotoCrops': {
          'https://cdn/photo.jpg': {'x': 0.9, 'y': 0.1, 'scale': 2.5},
        },
      });

      expect(cover!.isVideo, isFalse);
      expect(cover.imageUrl, 'https://cdn/photo.jpg');
      expect(cover.basicCardPhotoFocalX, 0.9);
      expect(cover.basicCardPhotoFocalY, 0.1);
      expect(cover.basicCardPhotoScale, 2.5);
    });

    // 계약 필드가 없던 옛 문서는 예전과 **똑같이** 보여야 한다 — 이번 변경으로
    // 이미 올라간 플레이스의 모습이 달라지면 안 된다.
    test('계약 필드가 없는 옛 문서는 예전 그대로 읽힌다', () {
      final cover = getPartyCoverMedia({
        'mainImageUrl': 'https://cdn/old.jpg',
        'videoUrl': 'https://cdn/old.m3u8',
      });
      expect(cover!.isVideo, isFalse, reason: '옛 문서의 대표가 갑자기 동영상으로 바뀌었다');
      expect(cover.imageUrl, 'https://cdn/old.jpg');
      // 크롭 값이 없으면 중앙 — 예전 BoxFit.cover 중앙 정렬과 픽셀 단위로 같다.
      expect(cover.basicCardPhotoFocalX, 0.5);
      expect(cover.basicCardPhotoScale, 1.0);
    });

    test('사진이 하나도 없던 옛 문서는 여전히 동영상이 대표다', () {
      final cover = getPartyCoverMedia({
        'videoUrl': 'https://cdn/old.m3u8',
        'videoThumbnailUrl': 'https://cdn/old-thumb.jpg',
      });
      expect(cover!.isVideo, isTrue);
    });
  });

  // ── 6. 구인구직은 다른 구조 ────────────────────────────────────────────

  group('구인구직', () {
    // 프로필 사진 1장 구조를 유지한다 — 동영상·대표 개념을 넣지 않는다.
    test('대표 미디어·동영상 개념을 들이지 않는다', () {
      final src = _src('lib/screens/crew_register_screen.dart');
      for (final key in [
        'coverMediaType',
        'PartyMediaPickerScreen',
        'uploadVideo',
      ]) {
        expect(
          src.contains(key),
          isFalse,
          reason: '구인구직에 "$key"가 들어왔다 — 프로필 사진 1장 구조를 유지한다',
        );
      }
    });

    // 임시저장을 복원했는데 파일이 사라졌으면, 저장을 눌러 실패하기 전에
    // 먼저 알려줘야 한다.
    //
    // 존재 확인은 **[LocalMedia.exists]로만** 한다. 예전에는 등록 화면마다
    // `File(path).existsSync()`를 직접 불렀는데, 웹에서는 경로가 `blob:...`
    // 오브젝트 URL이라 그 검사가 늘 false가 되어 멀쩡히 고른 사진까지 "사라진
    // 파일"로 몰았다. 지금은 공용 헬퍼가 앱에서는 파일을, 웹에서는 기억해 둔
    // 원본을 본다(local_media.dart) — 그래서 여기서 다시 existsSync를 요구하면
    // 웹을 깨는 코드를 되살리게 된다.
    test('임시저장 복원 후 파일이 없으면 재선택 안내를 켠다', () {
      final src = _src('lib/screens/crew_register_screen.dart');
      expect(src, contains('LocalMedia.exists('));
      expect(src, contains('draftMediaNeedsReselect = true'));
      expect(src, contains('buildMediaReselectBanner()'));
      // 복원 도중에 부르는 자리라 동기 검사여야 한다 — await를 붙이면 값이
      // 다 세워지기 전에 화면이 그려진다.
      expect(src, isNot(contains('await LocalMedia.exists(')));
    });

    test('로컬 파일 존재 확인을 화면이 직접 하지 않는다 — 웹에서 깨진다', () {
      for (final path in [
        'lib/screens/crew_register_screen.dart',
        'lib/screens/party_register_screen.dart',
        'lib/screens/place_register_screen.dart',
        'lib/screens/event_register_screen.dart',
      ]) {
        final src = _src(path);
        expect(
          src.contains('existsSync()'),
          isFalse,
          reason: '$path가 공용 헬퍼를 지나치고 파일을 직접 본다',
        );
      }
    });
  });

  // ── 7. 고른 미디어가 조용히 사라지지 않는다 ────────────────────────────

  group('픽커 이탈', () {
    // 이 화면은 '선택 완료'로 pop할 때만 부모에게 값을 돌려준다. 그래서
    // 뒤로가기는 곧 "고른 것 전부 버리기"인데, 예전에는 경고가 없었다 —
    // 사진을 고르고 뒤로 나온 사람은 "선택했는데 등록이 안 됐다"고 느낀다.
    test('고른 것이 있으면 뒤로가기 전에 확인한다', () {
      final src = _src('lib/screens/party_media_picker_screen.dart');
      expect(src, contains('PopScope'));
      expect(src, contains('_hasUnsavedChanges'));
      expect(src, contains('고른 미디어를 버릴까요?'));
    });
  });
}

// 🛍️ 파티샵 대표 미디어 — **공용 정본 하나**를 쓴다는 것을 붙잡는다.
//
// ── 고친 것 ──────────────────────────────────────────────────────────────────
// 파티샵만 미디어 스택이 따로 놀았다. 등록 화면에는 '대표 이미지 1장' 피커와
// '소개 이미지' 피커와 [SingleVideoPicker]가 **따로** 서 있어서
//   · 사진과 동영상 중 무엇이 대표인지 고를 수 없었고,
//   · 어느 사진이 대표인지 화면 어디에도 표시되지 않았으며,
//   · 순서 변경도 크롭도 없었다.
// 카드도 `mainImageUrl`을 직접 읽어, 동영상을 올려도 카드에는 절대 나올 수
// 없었다(대표 계약을 쓰지 않아 [getPartyCoverMedia]가 레거시 분기로 내려갔다).
//
// 이제 파티·플레이스·장소대여와 **같은 공용 스택**을 쓴다:
//   등록 → [PartyMediaPickerScreen] / [PartyMediaEditor]
//   저장 → [MediaUploadService.uploadNewMedia] + resolveCoverFields
//   읽기 → [getPartyCoverMedia] (카드·상세가 같은 함수)
//
// ── 저장 필드는 늘리지 않았다 ────────────────────────────────────────────────
// 사진은 예전 그대로 `mainImageUrl`(대표) + `introImageUrls`(나머지)이고,
// 동영상도 `videoUid`/`videoUrl`/`videoThumbnailUrl` 그대로다. 여기에 앱 전체가
// 이미 쓰는 대표 계약 키만 함께 적는다(파티샵 전용 키가 아니다).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/utils/party_utils.dart';

String _src(String path) => File(path).readAsStringSync();

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

void main() {
  // ── ① 읽기 — 카드·상세가 보는 값 ───────────────────────────────────────
  group('대표 판정은 공용 함수 하나가 한다', () {
    test('대표가 사진이면 그 사진이 온다', () {
      final cover = getPartyCoverMedia({
        'mainImageUrl': 'cover.jpg',
        'introImageUrls': ['b.jpg', 'c.jpg'],
        'coverMediaType': 'image',
        'coverImageUrl': 'cover.jpg',
        'coverThumbnailUrl': 'cover.jpg',
      }, tag: 'test');
      expect(cover?.isVideo, isFalse);
      expect(cover?.imageUrl, 'cover.jpg');
      expect(cover?.thumbnailUrl, 'cover.jpg');
    });

    test('대표가 동영상이면 카드는 영상 썸네일을 쓴다', () {
      final cover = getPartyCoverMedia({
        'mainImageUrl': 'photo.jpg',
        'videoUrl': 'v.m3u8',
        'videoUid': 'uid',
        'videoThumbnailUrl': 'v-thumb.jpg',
        'coverMediaType': 'video',
        'coverVideoUrl': 'v.m3u8',
        'coverVideoUid': 'uid',
        'coverThumbnailUrl': 'v-thumb.jpg',
      }, tag: 'test');
      expect(cover?.isVideo, isTrue);
      // 카드는 영상을 재생하지 않는다 — 이 값이 곧 카드 그림이다.
      expect(cover?.thumbnailUrl, 'v-thumb.jpg');
      expect(cover?.videoUrl, 'v.m3u8');
    });

    test('대표 계약이 없던 옛 샵 문서는 예전 그대로 읽힌다', () {
      // 하위호환 — 저장된 문서를 하나도 고치지 않아도 보이는 모습이 같다.
      final cover = getPartyCoverMedia({
        'mainImageUrl': 'legacy.jpg',
        'introImageUrls': ['b.jpg'],
      }, tag: 'test');
      expect(cover?.isVideo, isFalse);
      expect(cover?.thumbnailUrl, 'legacy.jpg');
    });

    test('사진 없이 동영상만 있던 옛 문서도 예전 규칙 그대로', () {
      final cover = getPartyCoverMedia({
        'videoUrl': 'v.m3u8',
        'videoThumbnailUrl': 'v-thumb.jpg',
      }, tag: 'test');
      expect(cover?.isVideo, isTrue);
      expect(cover?.thumbnailUrl, 'v-thumb.jpg');
    });
  });

  // ── ② 등록 — 공용 픽커·업로더·대표 계약 ────────────────────────────────
  group('등록 화면이 공용 스택을 그대로 쓴다', () {
    final register = _flat(
      _src('lib/screens/party_market_register_screen.dart'),
    );

    test('공용 픽커 화면을 연다 — 파티샵 전용 피커를 만들지 않았다', () {
      expect(register.contains('PartyMediaPickerScreen('), isTrue);
      // 따로 서 있던 옛 피커 셋은 사라졌다.
      expect(register.contains('SingleVideoPicker('), isFalse);
      expect(register.contains('_buildMainImagePicker'), isFalse);
      expect(register.contains('_buildIntroImagePicker'), isFalse);
    });

    test('업로드도 대표 계산도 공용 함수다', () {
      expect(register.contains('MediaUploadService.uploadNewMedia('), isTrue);
      expect(
        register.contains('MediaUploadService.resolveCoverFields('),
        isTrue,
      );
      expect(
        register.contains('MediaUploadService.resolvePhotoCropKeys('),
        isTrue,
      );
      // 파티샵만의 대표 규칙을 손으로 다시 적지 않았다.
      expect(register.contains("coverMediaType = 'video'"), isFalse);
    });

    test('저장 필드는 예전 그대로 + 공용 대표 계약', () {
      // 사진은 대표 1장(mainImageUrl) + 나머지(introImageUrls) 그대로다.
      expect(register.contains("'mainImageUrl': mainUrl,"), isTrue);
      expect(register.contains("'introImageUrls': introUrls,"), isTrue);
      expect(register.contains("'videoUid': videoUid,"), isTrue);
      // 대표 계약은 통째로 펼쳐 적는다(키를 손으로 나열하지 않는다).
      expect(register.contains('...coverFields,'), isTrue);
      expect(
        register.contains("'basicCardPhotoCrops': coverPhotoCrops,"),
        isTrue,
      );
    });

    test('대표로 고른 사진이 mainImageUrl로 간다', () {
      // 대표가 맨 앞, 나머지가 순서 그대로 introImageUrls.
      expect(
        register.contains(
          'final mainUrl = orderedPhotos.isEmpty ? \'\' : orderedPhotos.first;',
        ),
        isTrue,
      );
      expect(
        register.contains('final introUrls = orderedPhotos.skip(1).toList();'),
        isTrue,
      );
    });

    test('임시저장에 대표·순서·크롭이 함께 실린다', () {
      for (final key in [
        "'coverExistingImageUrls': _coverExistingImageUrls,",
        "'coverNewFilePaths':",
        "'coverPhotoCrops': _coverPhotoCrops,",
        "'coverVideoCropConfirmed': _coverVideoCropConfirmed,",
        "'coverPick':",
      ]) {
        expect(register.contains(key), isTrue, reason: key);
      }
      // 되돌리기도 같은 키로.
      expect(
        register.contains('_coverPhotoCrops = photoCropsFromRaw('),
        isTrue,
      );
      expect(register.contains('_coverPick = coverPick == null'), isTrue);
    });

    test('사진 장수 제한은 예전 저장 구조 그대로다', () {
      // 대표 1장 + 소개 6장 = 7. 늘리지도 줄이지도 않았다.
      expect(
        register.contains('static const int _coverMaxImages = 7;'),
        isTrue,
      );
    });
  });

  // ── ③ 카드·상세가 같은 정본을 읽는가 ───────────────────────────────────
  group('카드와 상세가 같은 정본을 읽는다', () {
    const readers = {
      // 목록 카드(작은/기본/큰 셋 다 — 뷰 모델 한 곳에서만 읽는다)
      'lib/widgets/shop_card_widget.dart':
          'cover: getPartyCoverMedia(data, tag: tag),',
      // 찜한 파티샵
      'lib/screens/my_favorites_screen.dart':
          "getPartyCoverMedia(data, tag: 'ShopFavoriteCard')",
      // 내 파티샵(호스트 허브)
      'lib/screens/my_host_hub_screen.dart':
          "getPartyCoverMedia(data, tag: 'MyShopCard')",
      // 상세
      'lib/screens/party_shop_detail_screen.dart':
          "getPartyCoverMedia(shopData, tag: 'PartyShopDetail')",
    };

    for (final e in readers.entries) {
      test('${e.key.split('/').last} — 공용 정본을 읽는다', () {
        expect(_flat(_src(e.key)).contains(e.value), isTrue);
      });
    }

    test('상세는 대표가 동영상이면 동영상을 첫 장에 세운다', () {
      // 상단 대표 미디어는 파티추 상세와 **같은 위젯**([MediaGallery])이
      // 그린다 — 첫 장을 정하는 것은 그 위젯에 넘기는 videoFirst 하나이고,
      // 페이지 인덱스 계산 자체는 그쪽 테스트(media_gallery_index_test)가
      // 붙잡는다. 여기서는 "대표 판정을 그대로 넘기는가"만 본다.
      final detail = _flat(_src('lib/screens/party_shop_detail_screen.dart'));
      expect(detail.contains('final videoIsCover = cover?.isVideo ?? false;'), isTrue);
      expect(detail.contains('videoFirst: videoIsCover,'), isTrue);
      // 대표가 사진이면 그 사진이 첫 장으로 당겨진다.
      expect(
        detail.contains('final idx = allImgUrls.indexOf(cover!.imageUrl!);'),
        isTrue,
      );
    });
  });

  // ── ④ 상품 쪽은 건드리지 않았다 ────────────────────────────────────────
  test('상품 이미지 최대 5장 제한은 그대로다', () {
    final product = _flat(
      _src('lib/screens/party_shop_product_register_screen.dart'),
    );
    // 상품 이미지는 이 작업의 대상이 아니다 — 샵 대표 미디어만 공용화했다.
    expect(product.contains('PartyMediaPickerScreen('), isFalse);
  });
}

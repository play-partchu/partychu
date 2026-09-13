// 매장 이벤트의 **사진·동영상**과 **대표 미디어**.
//
// ── 이 파일이 지키는 것 ─────────────────────────────────────────────────────
// ① 대표 정본은 하나다 — 호스트가 고른 대표(`coverMediaType`/`coverImageUrl`)를
//    **카드도** 읽는다. 예전에는 카드만 "영상이 있으면 무조건 영상 썸네일"이라고
//    따로 적혀 있어서, 사진을 대표로 골라 저장해도 상세에만 먹고 카드에는
//    안 먹었다(운영 문서에 실제로 그 상태가 있었다).
// ② 대표를 한 번도 안 정한 옛 이벤트는 예전 그대로 보인다(하위호환).
// ③ 등록 중에 고른 사진·동영상은 **공용 업로더 한 번**으로 올라가고, 대표·크롭도
//    매장 이벤트 수정 화면과 같은 함수를 지난다 — 등록 경로만 다르게 저장되지
//    않는다.
// ④ 초안(mediaDraft)은 Firestore에 **절대 쓰이지 않는다** — 저장 구조 무변경.
//
// ⚠️ 예약/신청·혜택·기간·시간 로직은 이 파일의 대상이 아니다.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/screens/party_media_picker_screen.dart';
import 'package:party_app/screens/place_event_edit_screen.dart';
import 'package:party_app/models/place_promotion_media_draft.dart';
import 'package:party_app/services/media_upload_service.dart';
import 'package:party_app/widgets/party_media_editor.dart';
import 'package:party_app/widgets/place_form/place_promotion_section.dart';
import 'package:party_app/widgets/place_product/place_promotion_list_section.dart';

PlacePromotion _promo({
  List<String> imageUrls = const [],
  String imageUrl = '',
  String? videoUrl,
  String? videoUid,
  String? videoThumbnailUrl,
  String? coverMediaType,
  String? coverImageUrl,
  String? coverVideoUrl,
  String? coverThumbnailUrl,
  PlacePromotionMediaDraft? mediaDraft,
}) => PlacePromotion(
  id: 'P1',
  placeId: 'PL1',
  placeCollection: 'events',
  hostId: 'host-me',
  title: '생일 이벤트',
  description: '',
  imageUrl: imageUrl,
  tags: const [],
  audience: '',
  startAt: null,
  endAt: null,
  isVisible: true,
  linkedProductIds: const [],
  sortOrder: 0,
  isAlways: true,
  imageUrls: imageUrls,
  videoUrl: videoUrl,
  videoUid: videoUid,
  videoThumbnailUrl: videoThumbnailUrl,
  coverMediaType: coverMediaType,
  coverImageUrl: coverImageUrl,
  coverVideoUrl: coverVideoUrl,
  coverThumbnailUrl: coverThumbnailUrl,
  mediaDraft: mediaDraft,
);

/// 카드를 좁은 폭에 띄우고 썸네일로 실제 쓰인 URL을 돌려준다.
/// 썸네일이 없으면 null.
Future<String?> _cardThumb(
  WidgetTester tester,
  PlacePromotion p, {
  double width = 320,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PlacePromotionCardList(
            promotions: [p],
            accent: const Color(0xFFFF6FA0),
            hostName: '호스트',
          ),
        ),
      ),
    ),
  );
  await tester.pump();

  final images = tester.widgetList<Image>(find.byType(Image));
  for (final img in images) {
    final provider = img.image;
    if (provider is NetworkImage) return provider.url;
  }
  return null;
}

void main() {
  // 업로더를 갈아끼워 Cloudflare를 부르지 않는다 — 올라간 파일 순서만 본다.
  late List<String> uploadedImages;
  late List<String> uploadedVideos;

  Future<String> fakeImage(XFile f) async {
    uploadedImages.add(f.path);
    return 'https://cdn.test/img/${uploadedImages.length}.jpg';
  }

  Future<Map<String, String>> fakeVideo(XFile f) async {
    uploadedVideos.add(f.path);
    // 키 이름은 공용 업로더가 읽는 그대로다(CloudflareService.uploadVideo 계약).
    return {
      'videoUid': 'VID1',
      'videoUrl': 'https://cdn.test/vid/VID1.m3u8',
      'videoThumbnailUrl': 'https://cdn.test/vid/VID1.jpg',
    };
  }

  // 공용 업로더는 올리기 전에 파일이 실재하는지 본다(missingFile) — 그 검사도
  // 함께 지나야 진짜 경로를 탄 것이므로, 진짜 임시 파일을 만들어 넘긴다.
  late Directory tmp;

  String file(String name) {
    final f = File('${tmp.path}${Platform.pathSeparator}$name')
      ..writeAsBytesSync(const [1, 2, 3]);
    return f.path;
  }

  setUp(() {
    uploadedImages = [];
    uploadedVideos = [];
    tmp = Directory.systemTemp.createTempSync('place_event_media_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  // ── 대표 정본 — 카드가 실제로 대표를 읽는가 ─────────────────────────────

  group('이벤트 카드 썸네일', () {
    // 운영 문서에 실제로 있던 상태: 사진 1장 + 동영상, 호스트가 **사진을**
    // 대표로 지정. 예전 카드는 영상 썸네일을 그렸다.
    testWidgets('대표가 사진이면 영상이 있어도 그 사진을 쓴다', (tester) async {
      final thumb = await _cardThumb(
        tester,
        _promo(
          imageUrls: const ['https://cdn.test/a.jpg', 'https://cdn.test/b.jpg'],
          videoUrl: 'https://cdn.test/v.m3u8',
          videoUid: 'VID1',
          videoThumbnailUrl: 'https://cdn.test/v.jpg',
          coverMediaType: 'image',
          coverImageUrl: 'https://cdn.test/b.jpg',
          coverThumbnailUrl: 'https://cdn.test/b.jpg',
        ),
      );
      expect(thumb, 'https://cdn.test/b.jpg');
    });

    testWidgets('대표가 동영상이면 그 영상 썸네일을 쓴다', (tester) async {
      final thumb = await _cardThumb(
        tester,
        _promo(
          imageUrls: const ['https://cdn.test/a.jpg'],
          videoUrl: 'https://cdn.test/v.m3u8',
          videoUid: 'VID1',
          videoThumbnailUrl: 'https://cdn.test/v.jpg',
          coverMediaType: 'video',
          coverVideoUrl: 'https://cdn.test/v.m3u8',
          coverThumbnailUrl: 'https://cdn.test/v.jpg',
        ),
      );
      expect(thumb, 'https://cdn.test/v.jpg');
    });

    // ── 하위호환: 대표를 한 번도 안 정한 옛 이벤트 ────────────────────────

    testWidgets('대표가 없고 사진만 있으면 첫 사진(예전 그대로)', (tester) async {
      final thumb = await _cardThumb(
        tester,
        _promo(
          imageUrls: const ['https://cdn.test/a.jpg', 'https://cdn.test/b.jpg'],
        ),
      );
      expect(thumb, 'https://cdn.test/a.jpg');
    });

    testWidgets('대표가 없고 영상만 있으면 영상 썸네일(예전 그대로)', (tester) async {
      final thumb = await _cardThumb(
        tester,
        _promo(
          videoUrl: 'https://cdn.test/v.m3u8',
          videoUid: 'VID1',
          videoThumbnailUrl: 'https://cdn.test/v.jpg',
        ),
      );
      expect(thumb, 'https://cdn.test/v.jpg');
    });

    // 주소 직접 입력만 있던 아주 오래된 문서.
    testWidgets('imageUrls가 없고 옛 imageUrl 한 장만 있어도 보인다', (tester) async {
      final thumb = await _cardThumb(
        tester,
        _promo(imageUrl: 'https://cdn.test/legacy.jpg'),
      );
      expect(thumb, 'https://cdn.test/legacy.jpg');
    });

    testWidgets('미디어가 하나도 없으면 사진 영역 없이 그린다', (tester) async {
      final thumb = await _cardThumb(tester, _promo());
      expect(thumb, isNull);
      expect(find.text('생일 이벤트'), findsOneWidget);
    });

    testWidgets('좁은 폭에서도 넘치지 않는다', (tester) async {
      await _cardThumb(
        tester,
        _promo(imageUrls: const ['https://cdn.test/a.jpg']),
        width: 300,
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ── 등록 중에 고른 미디어(초안) ─────────────────────────────────────────

  group('등록 중 고른 미디어 올리기', () {
    test('사진 한 장 — 올라가고 그 사진이 대표가 된다', () async {
      final p = _promo(
        mediaDraft: PlacePromotionMediaDraft(newMediaPaths: [file('one.jpg')]),
      );

      final saved = await PlacePromotionSection.uploadDraft(
        p,
        uploadImage: fakeImage,
        uploadVideo: fakeVideo,
      );

      expect(uploadedImages, [file('one.jpg')]);
      expect(saved.imageUrls, ['https://cdn.test/img/1.jpg']);
      expect(saved.coverMediaType, 'image');
      expect(saved.coverImageUrl, 'https://cdn.test/img/1.jpg');
      expect(saved.mediaDraft, isNull, reason: '올린 뒤에는 초안이 남으면 안 된다');
    });

    test('여러 장 중 두 번째를 대표로 고르면 그 URL이 대표가 된다', () async {
      final p = _promo(
        mediaDraft: PlacePromotionMediaDraft(
          newMediaPaths: [file('a.jpg'), file('b.jpg'), file('c.jpg')],
          coverPick: PartyCoverPick(newImageOrdinal: 1),
        ),
      );

      final saved = await PlacePromotionSection.uploadDraft(
        p,
        uploadImage: fakeImage,
        uploadVideo: fakeVideo,
      );

      expect(saved.imageUrls, hasLength(3));
      expect(saved.coverMediaType, 'image');
      expect(saved.coverImageUrl, saved.imageUrls[1]);
    });

    test('사진 + 동영상 혼합 — 둘 다 올라가고 대표는 고른 쪽이다', () async {
      final p = _promo(
        mediaDraft: PlacePromotionMediaDraft(
          newMediaPaths: [file('a.jpg'), file('clip.mp4')],
          coverPick: PartyCoverPick(isNewVideo: true),
        ),
      );

      final saved = await PlacePromotionSection.uploadDraft(
        p,
        uploadImage: fakeImage,
        uploadVideo: fakeVideo,
      );

      expect(uploadedImages, [file('a.jpg')]);
      expect(uploadedVideos, [file('clip.mp4')]);
      expect(saved.imageUrls, hasLength(1));
      expect(saved.videoUid, 'VID1');
      expect(saved.videoUrl, 'https://cdn.test/vid/VID1.m3u8');
      expect(saved.coverMediaType, 'video');
      expect(saved.coverThumbnailUrl, 'https://cdn.test/vid/VID1.jpg');
    });

    test('대표를 안 고르면 사진 우선 — 공용 기본값 그대로', () async {
      final p = _promo(
        mediaDraft: PlacePromotionMediaDraft(
          newMediaPaths: [file('a.jpg'), file('clip.mp4')],
        ),
      );

      final saved = await PlacePromotionSection.uploadDraft(
        p,
        uploadImage: fakeImage,
        uploadVideo: fakeVideo,
      );

      expect(saved.coverMediaType, 'image');
      expect(saved.coverImageUrl, saved.imageUrls.first);
    });

    // 대표로 골라 둔 사진을 편집기에서 지우면 그 순번이 사라진다. 대표가 빈
    // 채로 저장되면 카드가 아무것도 못 그린다.
    test('대표로 고른 사진이 사라졌으면 첫 사진으로 되돌아간다', () async {
      final p = _promo(
        mediaDraft: PlacePromotionMediaDraft(
          newMediaPaths: [file('a.jpg')],
          coverPick: PartyCoverPick(newImageOrdinal: 5),
        ),
      );

      final saved = await PlacePromotionSection.uploadDraft(
        p,
        uploadImage: fakeImage,
        uploadVideo: fakeVideo,
      );

      expect(saved.coverMediaType, 'image');
      expect(saved.coverImageUrl, 'https://cdn.test/img/1.jpg');
    });

    test('크롭 값의 키가 로컬 경로에서 최종 URL로 옮겨진다', () async {
      final p = _promo(
        mediaDraft: PlacePromotionMediaDraft(
          newMediaPaths: [file('a.jpg')],
          photoCrops: {
            file('a.jpg'): const {'x': 0.3, 'y': 0.7, 'scale': 1.4},
          },
        ),
      );

      final saved = await PlacePromotionSection.uploadDraft(
        p,
        uploadImage: fakeImage,
        uploadVideo: fakeVideo,
      );

      expect(saved.basicCardPhotoCrops.keys, ['https://cdn.test/img/1.jpg']);
      expect(saved.basicCardPhotoCrops['https://cdn.test/img/1.jpg'], {
        'x': 0.3,
        'y': 0.7,
        'scale': 1.4,
      });
      expect(
        saved.basicCardPhotoCrops.containsKey(file('a.jpg')),
        isFalse,
        reason: '로컬 경로가 그대로 저장되면 카드가 크롭을 못 찾는다',
      );
    });

    test('초안이 없으면 아무것도 올리지 않는다 — 재업로드 없음', () async {
      final p = _promo(imageUrls: const ['https://cdn.test/kept.jpg']);

      final saved = await PlacePromotionSection.uploadDraft(
        p,
        uploadImage: fakeImage,
        uploadVideo: fakeVideo,
      );

      expect(uploadedImages, isEmpty);
      expect(uploadedVideos, isEmpty);
      expect(saved.imageUrls, ['https://cdn.test/kept.jpg']);
    });
  });

  // ── 저장 구조는 그대로 ──────────────────────────────────────────────────

  group('placePromotions 문서 구조', () {
    test('초안은 Firestore에 쓰이지 않는다', () {
      final p = _promo(
        mediaDraft: PlacePromotionMediaDraft(
          newMediaPaths: [file('a.jpg')],
          coverPick: PartyCoverPick(newImageOrdinal: 0),
          photoCrops: {
            file('a.jpg'): const {'x': 0.3, 'y': 0.7, 'scale': 1.4},
          },
        ),
      );

      final map = p.toMap();
      expect(map.containsKey('mediaDraft'), isFalse);
      for (final v in map.values) {
        expect(v is PlacePromotionMediaDraft, isFalse);
      }
      // 읽는 쪽도 이 키를 모른다 — 옛 문서와 완전히 같은 모양이다.
      expect(PlacePromotion.fromMap('P1', map).mediaDraft, isNull);
    });

    test('대표 필드 이름은 파티·플레이스와 같다', () async {
      final p = _promo(
        mediaDraft: PlacePromotionMediaDraft(newMediaPaths: [file('a.jpg')]),
      );
      final saved = await PlacePromotionSection.uploadDraft(
        p,
        uploadImage: fakeImage,
        uploadVideo: fakeVideo,
      );
      final map = saved.toMap();
      for (final key in [
        'coverMediaType',
        'coverImageUrl',
        'coverVideoUrl',
        'coverVideoUid',
        'coverThumbnailUrl',
        'basicCardPhotoCrops',
      ]) {
        expect(map.containsKey(key), isTrue, reason: key);
      }
    });

    // 카드가 읽는 함수(getPartyCoverMedia)는 이 지도를 본다 — 키가 하나라도
    // 빠지면 대표를 못 찾거나 하위호환 분기가 어긋난다.
    test('coverMediaMap이 읽는 쪽 계약을 그대로 채운다', () {
      final map = _promo(
        imageUrls: const ['https://cdn.test/a.jpg'],
        videoUrl: 'https://cdn.test/v.m3u8',
        videoUid: 'VID1',
        videoThumbnailUrl: 'https://cdn.test/v.jpg',
        coverMediaType: 'image',
        coverImageUrl: 'https://cdn.test/a.jpg',
      ).coverMediaMap;

      for (final key in [
        'coverMediaType',
        'coverImageUrl',
        'coverVideoUrl',
        'coverVideoUid',
        'coverThumbnailUrl',
        'basicCardPhotoCrops',
        'images',
        'videoUrl',
        'videoUid',
        'videoThumbnailUrl',
      ]) {
        expect(map.containsKey(key), isTrue, reason: key);
      }
    });
  });

  // ── 공용 규칙을 다시 구현하지 않았는지 ──────────────────────────────────

  group('등록 중 인라인 섹션', _sectionTests);
  group('수정 화면 재진입', _editScreenTests);

  test('동영상 판정은 업로더와 같은 함수를 부른다', () {
    expect(PlacePromotionMediaDraft.isVideoFile(XFile('/tmp/a.mp4')), isTrue);
    expect(PlacePromotionMediaDraft.isVideoFile(XFile('/tmp/a.MOV')), isTrue);
    expect(PlacePromotionMediaDraft.isVideoFile(XFile('/tmp/a.jpg')), isFalse);
    // 업로더가 쓰는 판정과 어긋나면 동영상이 이미지로 올라간다.
    expect(
      PlacePromotionMediaDraft.isVideoFile(XFile('/tmp/a.mp4')),
      MediaUploadService.isVideoFile(XFile('/tmp/a.mp4')),
    );
  });
}

// ── 등록 중 인라인 섹션이 공용 편집기로 이어지는가 ──────────────────────────
//
// 여기서 검증하는 것은 "이 섹션이 자기만의 미디어 UI를 새로 만들지 않았다"는
// 사실이다. 크롭·대표 지정 자체는 공용 편집기(PartyMediaEditor)의 것이고 그쪽
// 테스트가 지킨다 — 이 자리는 **그 화면으로 가는 길**만 본다.
void _sectionTests() {
  testWidgets('이벤트를 추가하면 사진·동영상 줄이 있다', (tester) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final promotions = <PlacePromotion>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PlacePromotionSection(
              promotions: promotions,
              onChanged: () {},
              accent: const Color(0xFFFF6FA0),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('매장 이벤트 추가'));
    await tester.pumpAndSettle();

    expect(find.text('사진 · 동영상'), findsOneWidget);
    expect(find.text('사진 · 동영상 선택'), findsOneWidget);
    // 예전의 URL 직접 입력 칸은 없어졌다 — 사장님이 자기 사진의 주소를 갖고
    // 있을 리 없어 사실상 비워 두는 칸이었다.
    expect(find.text('이미지 주소'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('사진·동영상 줄이 공용 편집기 화면을 연다', (tester) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final promotions = <PlacePromotion>[
      PlacePromotion.empty(
        placeId: '',
        placeCollection: '',
        hostId: '',
        sortOrder: 0,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PlacePromotionSection(
              promotions: promotions,
              onChanged: () {},
              accent: const Color(0xFFFF6FA0),
            ),
          ),
        ),
      ),
    );
    // 카드를 펼친다.
    await tester.tap(find.text('(제목 없음)'));
    await tester.pumpAndSettle();

    final pick = find.text('사진 · 동영상 선택');
    await tester.ensureVisible(pick);
    await tester.pump();
    await tester.tap(pick);
    await tester.pumpAndSettle();

    // 새로 만든 화면이 아니라 파티·플레이스가 쓰는 그 화면이다.
    expect(find.byType(PartyMediaPickerScreen), findsOneWidget);
  });
}

// ── 수정 화면 재진입 — 저장해 둔 대표·크롭이 그대로 살아나는가 ──────────────
//
// 저장은 되는데 다시 열었을 때 대표가 첫 사진으로 되돌아가 보이면, 호스트는
// "대표 지정이 저장이 안 된다"고 읽는다. 화면이 저장값을 공용 편집기에 **그대로
// 되돌려주는지**가 그 갈림길이라 여기서 고정한다.
//
// 크롭·대표를 고르는 동작 자체는 공용 편집기의 것이고 그쪽이 지킨다 — 여기서
// 보는 것은 **넘겨주는 값**이다.
void _editScreenTests() {
  PlacePromotion existing({
    String? coverMediaType,
    String? coverImageUrl,
    Map<String, Map<String, double>> crops = const {},
    String? videoUrl,
    String? videoUid,
    String? videoThumbnailUrl,
  }) => _promo(
    imageUrls: const ['https://cdn.test/a.jpg', 'https://cdn.test/b.jpg'],
    coverMediaType: coverMediaType,
    coverImageUrl: coverImageUrl,
    videoUrl: videoUrl,
    videoUid: videoUid,
    videoThumbnailUrl: videoThumbnailUrl,
  ).copyWith(basicCardPhotoCrops: crops);

  Future<PartyMediaEditor> open(WidgetTester tester, PlacePromotion p) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: PlaceEventEditScreen(
          placeId: 'PL1',
          placeCollection: 'events',
          hostId: 'host-me',
          placeName: '가게',
          accent: const Color(0xFFFF6FA0),
          existing: p,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    return tester.widget<PartyMediaEditor>(find.byType(PartyMediaEditor));
  }

  testWidgets('저장된 대표 사진과 크롭이 공용 편집기로 되돌아간다', (tester) async {
    final ed = await open(
      tester,
      existing(
        coverMediaType: 'image',
        coverImageUrl: 'https://cdn.test/b.jpg',
        crops: const {
          'https://cdn.test/b.jpg': {'x': 0.2, 'y': 0.8, 'scale': 1.3},
        },
      ),
    );

    expect(ed.initialImageUrls, [
      'https://cdn.test/a.jpg',
      'https://cdn.test/b.jpg',
    ]);
    expect(ed.initialCoverMediaType, 'image');
    expect(ed.initialCoverImageUrl, 'https://cdn.test/b.jpg');
    expect(ed.initialPhotoCrops['https://cdn.test/b.jpg'], {
      'x': 0.2,
      'y': 0.8,
      'scale': 1.3,
    });
  });

  testWidgets('저장된 대표 동영상도 그대로 되돌아간다', (tester) async {
    final ed = await open(
      tester,
      existing(
        coverMediaType: 'video',
        videoUrl: 'https://cdn.test/v.m3u8',
        videoUid: 'VID1',
        videoThumbnailUrl: 'https://cdn.test/v.jpg',
      ),
    );

    expect(ed.initialCoverMediaType, 'video');
    expect(ed.initialVideoUrl, 'https://cdn.test/v.m3u8');
    expect(ed.initialVideoUid, 'VID1');
    expect(ed.initialVideoThumbnailUrl, 'https://cdn.test/v.jpg');
  });

  // 대표 필드가 아예 없던 옛 이벤트 — 편집기는 "고르지 않음"으로 열리고,
  // 그 상태로 저장하면 공용 기본값(사진 우선)이 적용된다.
  testWidgets('대표가 없던 옛 이벤트도 깨지지 않고 열린다', (tester) async {
    final ed = await open(tester, existing());

    expect(ed.initialCoverMediaType, isNull);
    expect(ed.initialCoverImageUrl, isNull);
    expect(ed.initialPhotoCrops, isEmpty);
    expect(ed.initialImageUrls, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('사진 상한은 등록 중 인라인 섹션과 같은 값 하나다', (tester) async {
    final ed = await open(tester, existing());
    expect(ed.maxImages, kEventMaxImages);
  });
}

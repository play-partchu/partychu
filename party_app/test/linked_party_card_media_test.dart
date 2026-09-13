// 플레이스·공간대여 상세의 🎉 파티 카드 — **대표사진을 기본 카드와 똑같이**
// 보여준다.
//
// 지키는 것은 세 가지다.
//  1. 대표 미디어 선택·크롭·동영상 처리는 기본 카드와 **같은 함수 하나**
//     ([partyBasicCardMedia])를 지난다 — 등록 화면에서 맞춘 썸네일 위치가
//     목록 카드와 이 카드에서 같은 자리로 보이려면 계산이 하나여야 한다.
//  2. 사진 상자의 비율도 기본 카드 비율([basicCardMediaAspectRatio])이다.
//     크롭 값이 그 비율을 전제로 저장돼 있어서, 다른 비율에 넣으면 사용자가
//     맞춘 자리와 다르게 잘린다.
//  3. 사진이 세로로 길어도 카드는 길어지지 않는다(썸네일 카드지 갤러리가 아니다).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/utils/card_media_frame.dart';
import 'package:party_app/utils/video_crop.dart';
import 'package:party_app/widgets/linked_party_card.dart';
import 'package:party_app/widgets/party_card_widget.dart';

void main() {
  const url = 'https://cdn.example.com/cover.jpg';
  const otherUrl = 'https://cdn.example.com/second.jpg';

  Map<String, dynamic> partyWithPhoto({
    double x = 0.5,
    double y = 0.5,
    double scale = 1.0,
  }) => {
    'title': '금요일 밤 와인 모임',
    'coverMediaType': 'image',
    'coverImageUrl': url,
    // 대표로 고르지 않은 사진 — 대표 지정이 있으면 이쪽이 뽑히면 안 된다.
    'images': [otherUrl],
    'basicCardPhotoCrops': {
      url: {'x': x, 'y': y, 'scale': scale},
    },
    'pricingType': 'same',
    'price': 20000,
    'startDateTime': DateTime(2030, 5, 5, 19).toIso8601String(),
  };

  Future<void> pumpCard(
    WidgetTester tester,
    Map<String, dynamic> party, {
    double width = 155,
  }) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              // 상세의 반 폭 열과 같은 폭.
              width: width,
              child: LinkedPartyCard(partyId: 'p1', party: party),
            ),
          ),
        ),
      ),
    );
  }

  group('대표사진 정본은 기본 카드와 같은 함수 하나다', () {
    test('등록자가 고른 대표사진(coverMediaType=image)이 뽑힌다', () {
      final media = partyBasicCardMedia(partyWithPhoto()) as CroppedMedia;
      final image = media.child as Image;
      expect((image.image as NetworkImage).url, url);
    });

    test('기본 카드 전용 크롭(basicCardPhotoCrops)이 그대로 반영된다', () {
      final media =
          partyBasicCardMedia(partyWithPhoto(x: 0.2, y: 0.8, scale: 1.6))
              as CroppedMedia;

      expect(media.cropX, 0.2);
      expect(media.cropY, 0.8);
      expect(media.cropScale, 1.6);
      // 자식 이미지의 정렬까지 맞아야 실제로 그 지점이 보인다 — alignment를
      // 중앙으로 두면 확대가 없을 때(scale 1.0) 크롭 값이 아무 효과도 못 낸다.
      final image = media.child as Image;
      expect(image.alignment, videoCropAlignment(0.2, 0.8));
      expect(image.fit, BoxFit.cover);
    });

    test('크롭을 지정한 적 없으면 중앙·확대 없음 — 예전 렌더링 그대로', () {
      final media =
          partyBasicCardMedia({
                'title': '크롭 없는 파티',
                'coverMediaType': 'image',
                'coverImageUrl': url,
              })
              as CroppedMedia;

      expect(media.cropX, 0.5);
      expect(media.cropY, 0.5);
      expect(media.cropScale, 1.0);
    });

    test('대표가 동영상이면 기본 카드 전용 초점으로 VideoThumbnail', () {
      final media =
          partyBasicCardMedia({
                'title': '영상 파티',
                'coverMediaType': 'video',
                'coverVideoUrl': 'https://cdn.example.com/v.m3u8',
                'coverThumbnailUrl': 'https://cdn.example.com/v.jpg',
                // 작은/큰 카드용 값은 기본 카드가 쓰지 않는다.
                'videoCropX': 0.1,
                'videoCropY': 0.1,
                'basicCardVideoFocalX': 0.3,
                'basicCardVideoFocalY': 0.7,
                'basicCardVideoScale': 1.4,
              })
              as VideoThumbnail;

      expect(media.videoUrl, 'https://cdn.example.com/v.m3u8');
      expect(media.thumbnailUrl, 'https://cdn.example.com/v.jpg');
      expect(media.cropX, 0.3);
      expect(media.cropY, 0.7);
      expect(media.cropScale, 1.4);
    });

    test('사진도 동영상도 없으면 폴백 자리', () {
      expect(
        partyBasicCardMedia({'title': '사진 없는 파티'}),
        isA<PartyCardMediaPlaceholder>(),
      );
    });
  });

  group('카드에서도 같은 사진이 같은 자리로 보인다', () {
    testWidgets('카드가 그리는 미디어는 기본 카드와 같은 크롭 값을 쓴다', (tester) async {
      await pumpCard(tester, partyWithPhoto(x: 0.2, y: 0.8, scale: 1.6));

      final media = tester.widget<CroppedMedia>(find.byType(CroppedMedia));
      expect(media.cropX, 0.2);
      expect(media.cropY, 0.8);
      expect(media.cropScale, 1.6);
      expect(tester.takeException(), isNull);
    });

    testWidgets('사진 상자 비율이 기본 카드 비율과 같다', (tester) async {
      await pumpCard(tester, partyWithPhoto());

      final box = tester.widget<AspectRatio>(find.byType(AspectRatio));
      // 기본 카드 비율 = 카드폭 / 미디어 높이(130). 크롭 편집 화면이 쓰는 것과
      // 같은 함수라, 여기서 어긋나면 사용자가 맞춘 자리와 달라진다.
      expect(box.aspectRatio, basicCardWidth(360) / 130);
    });

    testWidgets('세로로 긴 사진이어도 카드가 길어지지 않는다', (tester) async {
      await pumpCard(tester, partyWithPhoto());

      // 사진 자리는 카드 폭이 정한 비율만큼만 차지한다 — 원본 비율로 늘어나는
      // 갤러리형(MediaGallery)이 아니다.
      final mediaHeight = tester.getSize(find.byType(AspectRatio)).height;
      // 카드 폭(155)에서 좌우 테두리 1씩을 뺀 안쪽 폭이 사진 자리의 폭이다.
      expect(
        mediaHeight,
        closeTo((155 - 2) / (basicCardWidth(360) / 130), 0.5),
      );
      // 사진이 카드 절반을 크게 넘기지 않는다.
      final cardHeight = tester.getSize(find.byType(LinkedPartyCard)).height;
      expect(mediaHeight, lessThan(cardHeight * 0.62));
    });

    testWidgets('사진이 없어도 카드가 깨지지 않는다', (tester) async {
      await pumpCard(tester, {
        'title': '사진 없는 파티',
        'pricingType': 'same',
        'price': 10000,
      });

      expect(find.byType(PartyCardMediaPlaceholder), findsOneWidget);
      expect(find.text('사진 없는 파티'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

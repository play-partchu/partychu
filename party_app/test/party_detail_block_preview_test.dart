import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/models/party_detail_block.dart';
import 'package:party_app/models/party_detail_theme_key.dart';
import 'package:party_app/widgets/party_detail_block_preview.dart';
import 'package:party_app/widgets/party_detail_theme.dart';
import 'package:visibility_detector/visibility_detector.dart';

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));
}

void main() {
  setUpAll(() {
    // VisibilityDetector의 기본 500ms 지연 타이머가 테스트 종료 시 pending 상태로
    // 남아 '!timersPending' 불변식을 위반하지 않도록 즉시 갱신되게 한다.
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  testWidgets('큰 제목/소제목/일반 글/구분선/주의사항을 렌더링한다', (tester) async {
    final blocks = [
      const PartyDetailBlock(id: '1', type: PartyDetailBlockType.heading, text: '큰 제목'),
      const PartyDetailBlock(id: '2', type: PartyDetailBlockType.subheading, text: '소제목'),
      const PartyDetailBlock(id: '3', type: PartyDetailBlockType.paragraph, text: '본문 내용'),
      const PartyDetailBlock(id: '4', type: PartyDetailBlockType.divider),
      const PartyDetailBlock(id: '5', type: PartyDetailBlockType.notice, text: '주의사항'),
    ];

    await tester.pumpWidget(_wrap(PartyDetailBlockPreview(blocks: blocks)));

    expect(find.text('큰 제목'), findsOneWidget);
    expect(find.text('소제목'), findsOneWidget);
    expect(find.text('본문 내용'), findsOneWidget);
    expect(find.text('주의사항'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('알 수 없는 type이 섞여 있어도 크래시 없이 나머지만 표시한다', (tester) async {
    final blocks = [
      const PartyDetailBlock(id: '1', type: PartyDetailBlockType.heading, text: '제목'),
      PartyDetailBlock.fromMap({'id': '2', 'type': 'faceRecognition', 'videoUrl': 'x'}),
      const PartyDetailBlock(id: '3', type: PartyDetailBlockType.paragraph, text: '본문'),
    ];

    await tester.pumpWidget(_wrap(PartyDetailBlockPreview(blocks: blocks)));

    expect(tester.takeException(), isNull);
    expect(find.text('제목'), findsOneWidget);
    expect(find.text('본문'), findsOneWidget);
  });

  testWidgets('빈 텍스트/이미지 블록은 생략되고 나머지는 정상 표시된다', (tester) async {
    final blocks = [
      const PartyDetailBlock(id: '1', type: PartyDetailBlockType.heading, text: ''),
      const PartyDetailBlock(id: '2', type: PartyDetailBlockType.image, imageUrl: ''),
      const PartyDetailBlock(id: '3', type: PartyDetailBlockType.paragraph, text: '본문만 남음'),
    ];

    await tester.pumpWidget(_wrap(PartyDetailBlockPreview(blocks: blocks)));

    expect(tester.takeException(), isNull);
    expect(find.text('본문만 남음'), findsOneWidget);
  });

  testWidgets('빈 리스트면 아무것도 렌더링하지 않는다', (tester) async {
    await tester.pumpWidget(_wrap(const PartyDetailBlockPreview(blocks: [])));

    expect(tester.takeException(), isNull);
    expect(find.byType(PartyDetailBlockPreview), findsOneWidget);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('사진 블록을 탭하면 onImageTap 콜백이 해당 블록과 함께 호출된다', (tester) async {
    PartyDetailBlock? tapped;
    const block = PartyDetailBlock(
      id: 'img1',
      type: PartyDetailBlockType.image,
      imageUrl: 'https://example.com/a.jpg',
      imageWidth: 100,
      imageHeight: 100,
    );

    await tester.pumpWidget(
      _wrap(
        PartyDetailBlockPreview(
          blocks: const [block],
          onImageTap: (b) => tapped = b,
        ),
      ),
    );
    await tester.tap(find.byType(GestureDetector));

    expect(tapped?.id, 'img1');
  });

  testWidgets('onImageTap이 없으면 사진 블록에 탭 제스처가 붙지 않는다', (tester) async {
    const block = PartyDetailBlock(
      id: 'img1',
      type: PartyDetailBlockType.image,
      imageUrl: 'https://example.com/a.jpg',
    );

    await tester.pumpWidget(_wrap(const PartyDetailBlockPreview(blocks: [block])));

    expect(find.byType(GestureDetector), findsNothing);
  });

  // "사진만 보기"(4단계)는 별도 위젯을 새로 만들지 않고, detailBlocks를
  // image 타입만 걸러서 PartyDetailBlockPreview에 그대로 넘기는 방식으로
  // 구현했다 — 아래는 그 필터링된 입력이 기대대로 동작하는지 검증한다.
  group('사진만 보기(이미지로 필터링된 리스트 입력)', () {
    List<PartyDetailBlock> imagesOnlyOf(List<PartyDetailBlock> blocks) {
      return blocks.where((b) => b.type == PartyDetailBlockType.image).toList();
    }

    testWidgets('이미지 블록 수만큼만 표시되고 다른 블록은 전혀 그려지지 않는다', (tester) async {
      final allBlocks = [
        const PartyDetailBlock(id: '1', type: PartyDetailBlockType.heading, text: '제목'),
        const PartyDetailBlock(id: '2', type: PartyDetailBlockType.image, imageUrl: 'https://example.com/a.jpg'),
        const PartyDetailBlock(id: '3', type: PartyDetailBlockType.divider),
        const PartyDetailBlock(id: '4', type: PartyDetailBlockType.notice, text: '주의'),
        const PartyDetailBlock(id: '5', type: PartyDetailBlockType.image, imageUrl: 'https://example.com/b.jpg'),
      ];

      await tester.pumpWidget(_wrap(PartyDetailBlockPreview(blocks: imagesOnlyOf(allBlocks))));

      // Image.network가 이미지 블록 수(2개)만큼만 생성됐는지 확인.
      expect(find.byType(Image), findsNWidgets(2));
      expect(find.byWidgetPredicate((w) => w is Text && w.data == '제목'), findsNothing);
      expect(find.byWidgetPredicate((w) => w is Text && w.data == '주의'), findsNothing);
    });

    testWidgets('원본 detailBlocks 배열 순서를 그대로 유지한다', (tester) async {
      final allBlocks = [
        const PartyDetailBlock(
          id: '1',
          type: PartyDetailBlockType.image,
          imageUrl: 'https://example.com/first.jpg',
          imageWidth: 100,
          imageHeight: 100,
        ),
        const PartyDetailBlock(id: '2', type: PartyDetailBlockType.paragraph, text: '중간 텍스트'),
        const PartyDetailBlock(
          id: '3',
          type: PartyDetailBlockType.image,
          imageUrl: 'https://example.com/second.jpg',
          imageWidth: 100,
          imageHeight: 100,
        ),
      ];

      await tester.pumpWidget(_wrap(PartyDetailBlockPreview(blocks: imagesOnlyOf(allBlocks))));

      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(images, hasLength(2));
      final firstDy = tester.getTopLeft(find.byType(Image).first).dy;
      final secondDy = tester.getTopLeft(find.byType(Image).last).dy;
      expect(firstDy, lessThan(secondDy));
    });

    testWidgets('필터링 후에도 이미지 탭 콜백이 정상 동작한다', (tester) async {
      PartyDetailBlock? tapped;
      final allBlocks = [
        const PartyDetailBlock(id: '1', type: PartyDetailBlockType.heading, text: '숨겨질 제목'),
        const PartyDetailBlock(id: 'img1', type: PartyDetailBlockType.image, imageUrl: 'https://example.com/a.jpg'),
      ];

      await tester.pumpWidget(
        _wrap(
          PartyDetailBlockPreview(
            blocks: imagesOnlyOf(allBlocks),
            onImageTap: (b) => tapped = b,
          ),
        ),
      );
      await tester.tap(find.byType(GestureDetector));

      expect(tapped?.id, 'img1');
    });

    testWidgets('이미지 블록이 하나도 없으면 아무것도 그리지 않는다', (tester) async {
      final allBlocks = [
        const PartyDetailBlock(id: '1', type: PartyDetailBlockType.heading, text: '제목'),
        const PartyDetailBlock(id: '2', type: PartyDetailBlockType.paragraph, text: '본문'),
      ];

      await tester.pumpWidget(_wrap(PartyDetailBlockPreview(blocks: imagesOnlyOf(allBlocks))));

      expect(tester.takeException(), isNull);
      expect(find.byType(Image), findsNothing);
    });
  });

  group('5단계 확장 블록 — 디자인 보기', () {
    testWidgets('체크리스트: 제목 + 항목마다 체크 아이콘을 표시한다', (tester) async {
      const block = PartyDetailBlock(
        id: '1',
        type: PartyDetailBlockType.checklist,
        checklist: PartyDetailChecklistPayload(title: '이런 점이 좋아요', items: ['웰컴드링크 제공', '주차 가능']),
      );

      await tester.pumpWidget(_wrap(const PartyDetailBlockPreview(blocks: [block])));

      expect(find.text('이런 점이 좋아요'), findsOneWidget);
      expect(find.text('웰컴드링크 제공'), findsOneWidget);
      expect(find.text('주차 가능'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
    });

    testWidgets('FAQ: 기본은 접혀 있고 탭하면 답변이 펼쳐진다', (tester) async {
      const block = PartyDetailBlock(
        id: '1',
        type: PartyDetailBlockType.faq,
        faq: PartyDetailFaqPayload(
          items: [PartyDetailFaqItem(id: 'q1', question: '혼자 가도 되나요?', answer: '네, 혼자 오시는 분이 많습니다.')],
        ),
      );

      await tester.pumpWidget(_wrap(const PartyDetailBlockPreview(blocks: [block])));

      expect(find.text('혼자 가도 되나요?'), findsOneWidget);
      expect(find.text('네, 혼자 오시는 분이 많습니다.'), findsNothing);

      await tester.tap(find.text('혼자 가도 되나요?'));
      await tester.pump();

      expect(find.text('네, 혼자 오시는 분이 많습니다.'), findsOneWidget);
    });

    testWidgets('FAQ 아코디언을 열고 닫아도 예외가 발생하지 않는다', (tester) async {
      const block = PartyDetailBlock(
        id: '1',
        type: PartyDetailBlockType.faq,
        faq: PartyDetailFaqPayload(items: [PartyDetailFaqItem(id: 'q1', question: '혼자 가도 되나요?', answer: '네')]),
      );
      await tester.pumpWidget(_wrap(const PartyDetailBlockPreview(blocks: [block])));

      await tester.tap(find.text('혼자 가도 되나요?'));
      await tester.pump();
      await tester.tap(find.text('혼자 가도 되나요?'));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('타임라인: 항목이 시간 순서 그대로 표시된다', (tester) async {
      const block = PartyDetailBlock(
        id: '1',
        type: PartyDetailBlockType.timeline,
        timeline: PartyDetailTimelinePayload(
          items: [
            PartyDetailTimelineItem(id: 'a', time: '19:00', title: '입장', description: ''),
            PartyDetailTimelineItem(id: 'b', time: '20:00', title: 'BBQ 파티', description: ''),
          ],
        ),
      );

      await tester.pumpWidget(_wrap(const PartyDetailBlockPreview(blocks: [block])));

      final firstDy = tester.getTopLeft(find.text('입장')).dy;
      final secondDy = tester.getTopLeft(find.text('BBQ 파티')).dy;
      expect(firstDy, lessThan(secondDy));
    });

    testWidgets('정보 카드: 제목/본문/아이콘을 함께 표시한다', (tester) async {
      const block = PartyDetailBlock(
        id: '1',
        type: PartyDetailBlockType.infoCard,
        infoCard: PartyDetailInfoCardPayload(title: '준비물', text: '신분증을 반드시 지참해주세요.', icon: 'badge'),
      );

      await tester.pumpWidget(_wrap(const PartyDetailBlockPreview(blocks: [block])));

      expect(find.text('준비물'), findsOneWidget);
      expect(find.text('신분증을 반드시 지참해주세요.'), findsOneWidget);
      expect(find.byIcon(partyDetailInfoCardIconData('badge')), findsOneWidget);
    });

    testWidgets('동영상: URL도 로컬 파일도 없으면 아무것도 그리지 않는다', (tester) async {
      const block = PartyDetailBlock(
        id: '1',
        type: PartyDetailBlockType.video,
        video: PartyDetailVideoPayload(videoUrl: ''),
      );

      await tester.pumpWidget(_wrap(const PartyDetailBlockPreview(blocks: [block])));

      expect(tester.takeException(), isNull);
      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('동영상: URL이 있으면 탭 가능한 재생 영역과 캡션이 함께 표시된다(재생은 트리거하지 않음)', (tester) async {
      const block = PartyDetailBlock(
        id: '1',
        type: PartyDetailBlockType.video,
        video: PartyDetailVideoPayload(videoUrl: 'https://example.com/v.m3u8', caption: '입장 영상'),
      );

      await tester.pumpWidget(_wrap(const PartyDetailBlockPreview(blocks: [block])));

      expect(find.byType(GestureDetector), findsOneWidget);
      expect(find.text('입장 영상'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('알 수 없는 타입과 5종 확장 블록이 섞여 있어도 크래시 없이 함께 표시된다', (tester) async {
      final blocks = [
        const PartyDetailBlock(id: '1', type: PartyDetailBlockType.heading, text: '제목'),
        PartyDetailBlock.fromMap({'id': '2', 'type': 'faceRecognition'}),
        const PartyDetailBlock(
          id: '3',
          type: PartyDetailBlockType.checklist,
          checklist: PartyDetailChecklistPayload(items: ['항목1']),
        ),
      ];

      await tester.pumpWidget(_wrap(PartyDetailBlockPreview(blocks: blocks)));

      expect(tester.takeException(), isNull);
      expect(find.text('제목'), findsOneWidget);
      expect(find.text('항목1'), findsOneWidget);
    });
  });

  group('6단계 디자인 테마', () {
    testWidgets('기본값(theme 미지정)은 PartyChu 테마 색상을 쓴다', (tester) async {
      const block = PartyDetailBlock(id: '1', type: PartyDetailBlockType.subheading, text: '소제목');
      await tester.pumpWidget(_wrap(const PartyDetailBlockPreview(blocks: [block])));

      final text = tester.widget<Text>(find.text('소제목'));
      expect(text.style?.color, PartyDetailThemeRegistry.fromKey(PartyDetailThemeKey.partychu).subheadingColor);
    });

    testWidgets('테마를 바꾸면 소제목/카드 등 색상이 해당 테마 팔레트로 바뀐다', (tester) async {
      const block = PartyDetailBlock(id: '1', type: PartyDetailBlockType.subheading, text: '소제목');
      await tester.pumpWidget(
        _wrap(const PartyDetailBlockPreview(blocks: [block], theme: PartyDetailThemeKey.premiumDark)),
      );

      final palette = PartyDetailThemeRegistry.fromKey(PartyDetailThemeKey.premiumDark);
      final text = tester.widget<Text>(find.text('소제목'));
      expect(text.style?.color, palette.subheadingColor);
      // PartyChu 기본과는 다른 색이어야 실제로 테마가 반영된 것.
      expect(
        palette.subheadingColor,
        isNot(equals(PartyDetailThemeRegistry.fromKey(PartyDetailThemeKey.partychu).subheadingColor)),
      );
    });

    testWidgets('블록 패널 배경이 선택된 테마의 sectionBackground를 쓴다', (tester) async {
      const block = PartyDetailBlock(id: '1', type: PartyDetailBlockType.paragraph, text: '본문');
      await tester.pumpWidget(
        _wrap(const PartyDetailBlockPreview(blocks: [block], theme: PartyDetailThemeKey.clubNeon)),
      );

      final palette = PartyDetailThemeRegistry.fromKey(PartyDetailThemeKey.clubNeon);
      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, palette.sectionBackground);
    });

    testWidgets('5개 테마 모두 11종 블록이 크래시 없이 렌더링된다', (tester) async {
      final blocks = [
        const PartyDetailBlock(id: '1', type: PartyDetailBlockType.heading, text: '제목'),
        const PartyDetailBlock(id: '2', type: PartyDetailBlockType.subheading, text: '소제목'),
        const PartyDetailBlock(id: '3', type: PartyDetailBlockType.paragraph, text: '본문'),
        const PartyDetailBlock(id: '4', type: PartyDetailBlockType.divider),
        const PartyDetailBlock(id: '5', type: PartyDetailBlockType.notice, text: '주의'),
        const PartyDetailBlock(
          id: '6',
          type: PartyDetailBlockType.checklist,
          checklist: PartyDetailChecklistPayload(items: ['항목']),
        ),
        const PartyDetailBlock(
          id: '7',
          type: PartyDetailBlockType.faq,
          faq: PartyDetailFaqPayload(items: [PartyDetailFaqItem(id: 'q', question: 'Q', answer: 'A')]),
        ),
        const PartyDetailBlock(
          id: '8',
          type: PartyDetailBlockType.timeline,
          timeline: PartyDetailTimelinePayload(
            items: [PartyDetailTimelineItem(id: 't', time: '19:00', title: '입장', description: '')],
          ),
        ),
        const PartyDetailBlock(
          id: '9',
          type: PartyDetailBlockType.infoCard,
          infoCard: PartyDetailInfoCardPayload(title: '준비물', text: '지참', icon: 'badge'),
        ),
        const PartyDetailBlock(id: '10', type: PartyDetailBlockType.image, imageUrl: 'https://example.com/a.jpg'),
        const PartyDetailBlock(id: '11', type: PartyDetailBlockType.video, video: PartyDetailVideoPayload(videoUrl: 'https://example.com/v.m3u8')),
      ];

      for (final theme in PartyDetailThemeKey.values) {
        await tester.pumpWidget(_wrap(PartyDetailBlockPreview(blocks: blocks, theme: theme)));
        expect(tester.takeException(), isNull, reason: '$theme 테마에서 렌더링 실패');
      }
    });
  });
}

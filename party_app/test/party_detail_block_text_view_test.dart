import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/models/party_detail_block.dart';
import 'package:party_app/models/party_detail_theme_key.dart';
import 'package:party_app/widgets/party_detail_block_text_view.dart';
import 'package:party_app/widgets/party_detail_theme.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

// PartyDetailBlockTextView는 SelectableText를 쓰므로(find.text는 기본적으로
// SelectableText 내부의 RichText까지 뒤지지 않는다) 위젯 프레디케이트로 직접 찾는다.
Finder _findSelectable(String text) {
  return find.byWidgetPredicate((w) => w is SelectableText && w.data == text);
}

// 타임라인 항목은 SelectableText.rich(TextSpan)로 그려져 data가 아니라
// textSpan에 값이 있으므로, 부분 문자열 포함 여부로 찾는다.
Finder _findSelectableContaining(String substring) {
  return find.byWidgetPredicate(
    (w) =>
        w is SelectableText &&
        (w.textSpan?.toPlainText() ?? '').contains(substring),
  );
}

void main() {
  testWidgets('heading/subheading/paragraph/notice 텍스트를 표시한다', (tester) async {
    final blocks = [
      const PartyDetailBlock(
        id: '1',
        type: PartyDetailBlockType.heading,
        text: '큰 제목',
      ),
      const PartyDetailBlock(
        id: '2',
        type: PartyDetailBlockType.subheading,
        text: '소제목',
      ),
      const PartyDetailBlock(
        id: '3',
        type: PartyDetailBlockType.paragraph,
        text: '본문 내용',
      ),
      const PartyDetailBlock(
        id: '4',
        type: PartyDetailBlockType.notice,
        text: '주의사항',
      ),
    ];

    await tester.pumpWidget(_wrap(PartyDetailBlockTextView(blocks: blocks)));

    expect(_findSelectable('큰 제목'), findsOneWidget);
    expect(_findSelectable('소제목'), findsOneWidget);
    expect(_findSelectable('본문 내용'), findsOneWidget);
    expect(_findSelectable('주의사항'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('사진 블록은 표시하지 않고 Image 위젯을 만들지 않는다', (tester) async {
    final blocks = [
      const PartyDetailBlock(
        id: '1',
        type: PartyDetailBlockType.heading,
        text: '제목',
      ),
      const PartyDetailBlock(
        id: '2',
        type: PartyDetailBlockType.image,
        imageUrl: 'https://example.com/a.jpg',
      ),
      const PartyDetailBlock(
        id: '3',
        type: PartyDetailBlockType.paragraph,
        text: '본문',
      ),
    ];

    await tester.pumpWidget(_wrap(PartyDetailBlockTextView(blocks: blocks)));

    expect(find.byType(Image), findsNothing);
    expect(_findSelectable('제목'), findsOneWidget);
    expect(_findSelectable('본문'), findsOneWidget);
  });

  testWidgets('알 수 없는 type과 빈 텍스트 블록은 조용히 생략된다', (tester) async {
    final blocks = [
      const PartyDetailBlock(
        id: '1',
        type: PartyDetailBlockType.heading,
        text: '',
      ),
      PartyDetailBlock.fromMap({'id': '2', 'type': 'faceRecognition'}),
      const PartyDetailBlock(
        id: '3',
        type: PartyDetailBlockType.paragraph,
        text: '남는 본문',
      ),
    ];

    await tester.pumpWidget(_wrap(PartyDetailBlockTextView(blocks: blocks)));

    expect(tester.takeException(), isNull);
    expect(_findSelectable('남는 본문'), findsOneWidget);
  });

  testWidgets('블록 순서가 원본 detailBlocks 배열 순서와 동일하게 유지된다', (tester) async {
    final blocks = [
      const PartyDetailBlock(
        id: '1',
        type: PartyDetailBlockType.heading,
        text: '첫번째',
      ),
      const PartyDetailBlock(
        id: '2',
        type: PartyDetailBlockType.paragraph,
        text: '두번째',
      ),
    ];

    await tester.pumpWidget(_wrap(PartyDetailBlockTextView(blocks: blocks)));

    final firstDy = tester.getTopLeft(_findSelectable('첫번째')).dy;
    final secondDy = tester.getTopLeft(_findSelectable('두번째')).dy;
    expect(firstDy, lessThan(secondDy));
  });

  testWidgets('빈 리스트면 아무것도 표시하지 않는다', (tester) async {
    await tester.pumpWidget(_wrap(const PartyDetailBlockTextView(blocks: [])));

    expect(tester.takeException(), isNull);
    expect(find.byType(SelectableText), findsNothing);
  });

  testWidgets('긴 글과 이모지가 포함된 문단도 예외 없이 표시된다', (tester) async {
    const longText =
        '이 파티는 신논현역에서 도보 7분 거리에 있습니다 🎉 외부 음식 반입은 어려우니 미리 참고해주세요 😊 '
        '오시는 길이 헷갈리면 언제든 문의해주세요!';
    final blocks = [
      const PartyDetailBlock(
        id: '1',
        type: PartyDetailBlockType.paragraph,
        text: longText,
      ),
    ];

    await tester.pumpWidget(_wrap(PartyDetailBlockTextView(blocks: blocks)));

    expect(tester.takeException(), isNull);
    expect(_findSelectable(longText), findsOneWidget);
  });

  group('5단계 확장 블록 — 글만 보기', () {
    testWidgets('체크리스트: 제목 + 항목마다 ✓ 접두어가 붙은 텍스트로 표시된다', (tester) async {
      const block = PartyDetailBlock(
        id: '1',
        type: PartyDetailBlockType.checklist,
        checklist: PartyDetailChecklistPayload(
          title: '이런 점이 좋아요',
          items: ['웰컴드링크 제공'],
        ),
      );

      await tester.pumpWidget(
        _wrap(const PartyDetailBlockTextView(blocks: [block])),
      );

      expect(_findSelectable('이런 점이 좋아요'), findsOneWidget);
      expect(_findSelectable('✓ 웰컴드링크 제공'), findsOneWidget);
    });

    testWidgets('FAQ: 아코디언 없이 질문과 답변이 모두 펼쳐져 표시된다', (tester) async {
      const block = PartyDetailBlock(
        id: '1',
        type: PartyDetailBlockType.faq,
        faq: PartyDetailFaqPayload(
          items: [
            PartyDetailFaqItem(
              id: 'q1',
              question: '혼자 가도 되나요?',
              answer: '네, 많습니다.',
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        _wrap(const PartyDetailBlockTextView(blocks: [block])),
      );

      expect(_findSelectable('Q. 혼자 가도 되나요?'), findsOneWidget);
      expect(_findSelectable('A. 네, 많습니다.'), findsOneWidget);
    });

    testWidgets('타임라인: 시간·제목이 순서대로 텍스트로 표시된다', (tester) async {
      const block = PartyDetailBlock(
        id: '1',
        type: PartyDetailBlockType.timeline,
        timeline: PartyDetailTimelinePayload(
          items: [
            PartyDetailTimelineItem(
              id: 'a',
              time: '19:00',
              title: '입장',
              description: '',
            ),
            PartyDetailTimelineItem(
              id: 'b',
              time: '20:00',
              title: 'BBQ 파티',
              description: '',
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        _wrap(const PartyDetailBlockTextView(blocks: [block])),
      );

      expect(_findSelectableContaining('19:00'), findsOneWidget);
      expect(_findSelectableContaining('입장'), findsOneWidget);
      final firstDy = tester.getTopLeft(_findSelectableContaining('입장')).dy;
      final secondDy = tester
          .getTopLeft(_findSelectableContaining('BBQ 파티'))
          .dy;
      expect(firstDy, lessThan(secondDy));
    });

    testWidgets('정보 카드: 제목과 본문만 표시된다', (tester) async {
      const block = PartyDetailBlock(
        id: '1',
        type: PartyDetailBlockType.infoCard,
        infoCard: PartyDetailInfoCardPayload(
          title: '준비물',
          text: '신분증을 지참해주세요.',
          icon: 'badge',
        ),
      );

      await tester.pumpWidget(
        _wrap(const PartyDetailBlockTextView(blocks: [block])),
      );

      expect(_findSelectable('준비물'), findsOneWidget);
      expect(_findSelectable('신분증을 지참해주세요.'), findsOneWidget);
    });

    testWidgets('동영상: 자체는 숨기고 캡션만 텍스트로 표시된다', (tester) async {
      const block = PartyDetailBlock(
        id: '1',
        type: PartyDetailBlockType.video,
        video: PartyDetailVideoPayload(
          videoUrl: 'https://example.com/v.m3u8',
          caption: '입장 영상',
        ),
      );

      await tester.pumpWidget(
        _wrap(const PartyDetailBlockTextView(blocks: [block])),
      );

      expect(_findSelectable('입장 영상'), findsOneWidget);
      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('캡션 없는 동영상 블록은 아무것도 표시하지 않는다', (tester) async {
      const block = PartyDetailBlock(
        id: '1',
        type: PartyDetailBlockType.video,
        video: PartyDetailVideoPayload(videoUrl: 'https://example.com/v.m3u8'),
      );

      await tester.pumpWidget(
        _wrap(const PartyDetailBlockTextView(blocks: [block])),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(SelectableText), findsNothing);
    });
  });

  group('6단계 디자인 테마 — 글만 보기는 영향을 최소화한다', () {
    testWidgets('소제목 색상만 선택된 테마의 포인트 컬러를 따른다', (tester) async {
      const block = PartyDetailBlock(
        id: '1',
        type: PartyDetailBlockType.subheading,
        text: '소제목',
      );
      await tester.pumpWidget(
        _wrap(
          const PartyDetailBlockTextView(
            blocks: [block],
            theme: PartyDetailThemeKey.clubNeon,
          ),
        ),
      );

      final widget = tester.widget<SelectableText>(_findSelectable('소제목'));
      expect(
        widget.style?.color,
        PartyDetailThemeRegistry.fromKey(PartyDetailThemeKey.clubNeon).primary,
      );
    });

    testWidgets('본문(paragraph) 색상은 다크/네온 테마를 골라도 고정된 진한 색을 유지한다', (
      tester,
    ) async {
      const block = PartyDetailBlock(
        id: '1',
        type: PartyDetailBlockType.paragraph,
        text: '본문 내용',
      );
      await tester.pumpWidget(
        _wrap(
          const PartyDetailBlockTextView(
            blocks: [block],
            theme: PartyDetailThemeKey.premiumDark,
          ),
        ),
      );

      final widget = tester.widget<SelectableText>(_findSelectable('본문 내용'));
      // 프리미엄 다크 테마의 sectionBackground(어두운 색)는 이 화면에 전혀
      // 쓰이지 않고, 본문은 항상 고정된 어두운 글자색을 유지해야 한다.
      expect(widget.style?.color, Colors.black87);
    });

    testWidgets('배경에 어떤 Container 색상도 어두운 테마 sectionBackground를 쓰지 않는다', (
      tester,
    ) async {
      const block = PartyDetailBlock(
        id: '1',
        type: PartyDetailBlockType.paragraph,
        text: '본문',
      );
      await tester.pumpWidget(
        _wrap(
          const PartyDetailBlockTextView(
            blocks: [block],
            theme: PartyDetailThemeKey.clubNeon,
          ),
        ),
      );

      final neonBg = PartyDetailThemeRegistry.fromKey(
        PartyDetailThemeKey.clubNeon,
      ).sectionBackground;
      final containers = tester.widgetList<Container>(find.byType(Container));
      for (final c in containers) {
        final decoration = c.decoration;
        if (decoration is BoxDecoration) {
          expect(decoration.color, isNot(equals(neonBg)));
        }
      }
    });
  });
}

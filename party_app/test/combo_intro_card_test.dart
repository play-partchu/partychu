import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/widgets/combo_intro_card.dart';

// 콤보 등록 화면(숙박+파티 / 플레이스+파티) 상단 안내 카드 검증.
//
// 두 가지를 본다:
//  1) 접힘/펼침 — 기본은 요약만, "자세히 보기"를 누르면 설명이 나오고 버튼이
//     "접기"로 바뀌며, 다시 누르면 사라진다.
//  2) 요약 줄 수 — "기본 상태에서 두 줄 정도"가 목표다. 일반적인 폭(430dp)
//     에서는 두 줄 안에 들어와야 하고, 가장 좁은 축(360dp)에서도 세 줄을
//     넘거나 "..."로 잘리면 안 된다. 실제 문구를 넣고 RenderParagraph의
//     줄 수와 오버플로 여부를 직접 읽는다.

const _kSummaryStay = '게스트하우스·펜션 등에서 숙박과 파티를 함께 운영하시나요?';
const _kSummaryPlace = '🍻 혼술바·술집·카페 등 매장을 운영하면서 파티도 함께 진행하시나요?';

/// 실제로 몇 줄로 그려졌는지 — 글자 상자들의 서로 다른 top 값 개수로 센다.
int _lineCount(RenderParagraph paragraph, String text) {
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  );
  return boxes.map((b) => b.top.round()).toSet().length;
}

Widget _host(Widget child, {double width = 360}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          // 등록 화면 ListView의 좌우 패딩(16)까지 흉내 낸 실제 사용 폭.
          child: SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('기본은 요약만 보이고, 자세히 보기를 누르면 설명이 펼쳐진다', (tester) async {
    await tester.pumpWidget(_host(const ComboIntroCard(
      summary: _kSummaryStay,
      sections: [
        ComboIntroSection(lines: [
          '🛏️ 객실과 파티 정보를 한 번에 등록할 수 있어요.',
          '🎉 숙박 이용객에게 진행되는 파티를 함께 소개할 수 있어요.',
          '🔗 숙박 상세페이지와 파티 상세페이지가 서로 연결돼요.',
        ]),
      ],
    )));

    expect(find.text(_kSummaryStay), findsOneWidget);
    expect(find.text('자세히 보기'), findsOneWidget);
    expect(find.text('접기'), findsNothing);
    // 접힌 상태에서는 상세 문구가 화면에 그려지지 않는다.
    expect(find.text('🔗 숙박 상세페이지와 파티 상세페이지가 서로 연결돼요.'), findsNothing);

    await tester.tap(find.text('자세히 보기'));
    await tester.pumpAndSettle();

    expect(find.text('🛏️ 객실과 파티 정보를 한 번에 등록할 수 있어요.'), findsOneWidget);
    expect(find.text('🔗 숙박 상세페이지와 파티 상세페이지가 서로 연결돼요.'), findsOneWidget);
    expect(find.text('접기'), findsOneWidget);
    expect(find.text('자세히 보기'), findsNothing);

    await tester.tap(find.text('접기'));
    await tester.pumpAndSettle();

    expect(find.text('🔗 숙박 상세페이지와 파티 상세페이지가 서로 연결돼요.'), findsNothing);
    expect(find.text('자세히 보기'), findsOneWidget);
  });

  testWidgets('플레이스+파티는 소제목 두 개가 함께 펼쳐진다', (tester) async {
    await tester.pumpWidget(_host(const ComboIntroCard(
      summary: _kSummaryPlace,
      sections: [
        ComboIntroSection(
          heading: '플레이스+파티 등록은 이런 분들을 위한 기능입니다.',
          lines: ['🍺 혼술바, 술집, 카페 등 매장을 운영하면서 파티도 함께 진행하는 사장님'],
        ),
        ComboIntroSection(
          heading: '이렇게 등록하면',
          lines: ['🏪 매장 정보와 파티를 한 번에 등록할 수 있어요.'],
        ),
      ],
    )));

    await tester.tap(find.text('자세히 보기'));
    await tester.pumpAndSettle();

    expect(find.text('플레이스+파티 등록은 이런 분들을 위한 기능입니다.'), findsOneWidget);
    expect(find.text('이렇게 등록하면'), findsOneWidget);
  });

  for (final (name, summary) in [
    ('숙박+파티', _kSummaryStay),
    ('플레이스+파티', _kSummaryPlace),
  ]) {
    // 폭 → 허용 줄 수. 430dp(요즘 폰)에서는 두 줄, 360dp(가장 좁은 축)에서도
    // 세 줄까지만 쓰고 잘리지는 않아야 한다.
    for (final (width, maxLines) in [(430.0, 2), (360.0, 3)]) {
      testWidgets('$name 요약이 ${width.toInt()}dp에서 $maxLines줄 안에 잘리지 않고 들어간다',
          (tester) async {
        await tester.pumpWidget(_host(
          ComboIntroCard(
            summary: summary,
            sections: const [
              ComboIntroSection(lines: ['펼침 내용']),
            ],
          ),
          width: width,
        ));

        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.byType(ComboIntroCard),
            matching: find.text(summary),
          ),
        );
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: '요약이 "..."로 잘렸습니다: $summary',
        );
        expect(
          _lineCount(paragraph, summary),
          lessThanOrEqualTo(maxLines),
          reason: '요약이 $maxLines줄을 넘었습니다: $summary',
        );
      });
    }
  }
}

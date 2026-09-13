// 얼리버드 안내 카드 — **내용 높이에 맞는 컴팩트 카드**인지 고정한다.
//
// 기본 [PartyChuCard]는 사방 26 여백에 맞춰진 카드라(환불 규정처럼 본문이
// 여러 줄인 곳 기준), 한두 줄짜리 얼리버드 안내에서는 글자보다 여백이 더 커
// 세로로 과하게 보였다. 테두리·그림자·핑크 톤은 그대로 두고 여백만 줄인다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/widgets/partychu_ui.dart';

void main() {
  const cardKey = Key('card');

  Future<double> heightOf(WidgetTester tester, Widget card) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 360, child: card),
          ),
        ),
      ),
    );
    return tester.getRect(find.byKey(cardKey)).height;
  }

  // 실제 안내와 같은 한 줄짜리 내용.
  Widget oneLine() => const Row(
    children: [
      Icon(Icons.autorenew, size: 16),
      SizedBox(width: 6),
      Expanded(
        child: Text(
          '8월 24일(월) 회차부터 얼리버드 할인 · 이번 회차 얼리버드는 마감됐어요',
          style: TextStyle(fontSize: 13),
        ),
      ),
    ],
  );

  group('컴팩트 카드', () {
    testWidgets('같은 내용이면 기본 카드보다 세로로 짧다', (tester) async {
      final compact = await heightOf(
        tester,
        PartyChuCard.compact(key: cardKey, child: oneLine()),
      );
      final normal = await heightOf(
        tester,
        PartyChuCard(key: cardKey, child: oneLine()),
      );

      expect(compact, lessThan(normal));
      // 상하 26 → 12로 줄였으니 정확히 28만큼 짧다.
      expect(normal - compact, 28.0);
    });

    testWidgets('높이는 내용이 정한다 — 두 줄이면 그만큼만 커진다', (tester) async {
      final short = await heightOf(
        tester,
        PartyChuCard.compact(
          key: cardKey,
          child: const Text('한 줄', style: TextStyle(fontSize: 13)),
        ),
      );
      final tall = await heightOf(
        tester,
        PartyChuCard.compact(
          key: cardKey,
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('한 줄', style: TextStyle(fontSize: 13)),
              Text('두 줄', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
      );

      // 여백은 그대로고 글자 한 줄만큼만 늘어난다 — 고정 높이가 아니다.
      expect(tall, greaterThan(short));
      expect(tall - short, lessThan(30));
      // 한 줄짜리 카드 높이 = 컴팩트 상하 여백 + 글자 한 줄.
      expect(short - PartyChuCard.compactPadding.vertical, lessThan(30));
    });

    testWidgets('여백만 줄었을 뿐 핑크 테두리·톤은 기본 카드와 같다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PartyChuCard.compact(key: cardKey, child: oneLine()),
          ),
        ),
      );
      final compactBox =
          tester
                  .widget<Container>(
                    find.descendant(
                      of: find.byKey(cardKey),
                      matching: find.byType(Container),
                    ),
                  )
                  .decoration!
              as BoxDecoration;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PartyChuCard(key: cardKey, child: oneLine()),
          ),
        ),
      );
      final normalBox =
          tester
                  .widget<Container>(
                    find.descendant(
                      of: find.byKey(cardKey),
                      matching: find.byType(Container),
                    ),
                  )
                  .decoration!
              as BoxDecoration;

      expect(compactBox.border, normalBox.border);
      expect(compactBox.color, normalBox.color);
      expect(compactBox.boxShadow, normalBox.boxShadow);
    });

    testWidgets('안내 문구는 그대로 남는다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PartyChuCard.compact(key: cardKey, child: oneLine()),
          ),
        ),
      );
      expect(
        find.text('8월 24일(월) 회차부터 얼리버드 할인 · 이번 회차 얼리버드는 마감됐어요'),
        findsOneWidget,
      );
    });
  });
}

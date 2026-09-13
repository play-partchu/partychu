// 파티 상세 — '이 파티가 열리는 플레이스' 카드의 **가로 폭**만 본다.
//
// 이 카드는 상세 본문 Column(crossAxisAlignment.start) 안에 놓인다. 거기서는
// 자식에게 느슨한 폭 제약이 내려오므로, 폭을 스스로 잡지 않는 카드는 내용
// 크기(제목 Row가 mainAxisSize.min)에 맞춰 짧게 끝난다 — 그래서 환불 규정
// 카드와 좌우 끝이 어긋나 있었다. 환불 규정 카드는 안에 mainAxisSize.max인
// Row가 있어 결과적으로 폭을 꽉 채우고 있었다(의도한 규칙이라기보다 부수효과).
//
// 그래서 두 축을 나눠 확인한다.
//   1. 레이아웃 — 같은 본문 Column 안에서 `width: double.infinity`로 폭을
//      잡은 카드와, 환불 규정과 같은 구조(PartyChuCard + 폭을 채우는 Row)의
//      카드가 **좁은 화면에서도 좌우 끝이 정확히 같은가**.
//   2. 소스 — 실제 `_linkedEventInfo`가 그 규칙을 쓰고 있고, 좌우 여백을
//      따로 두지 않는가(좌우 여백은 페이지 Padding(all 20)의 몫이다).
//      상세 화면은 Firestore를 읽는 State 안의 private 메서드라 위젯으로는
//      띄울 수 없어, 이 파일의 다른 상세 테스트와 같은 방식으로 잠근다.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/widgets/partychu_ui.dart';

/// 상세 본문과 같은 골격 — Padding(all 20) + Column(start).
Widget detailBody({required List<Widget> children}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    ),
  ),
);

/// '이 파티가 열리는 플레이스' 카드와 같은 폭 규칙·여백을 가진 카드.
/// (색·모서리 등 디자인은 이 테스트의 관심사가 아니라 생략한다.)
Widget placeCard() => Container(
  key: const Key('place'),
  width: double.infinity,
  margin: const EdgeInsets.only(top: 24, bottom: 12),
  padding: const EdgeInsets.all(16),
  child: const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // 제목 줄이 mainAxisSize.min이라 폭을 넓혀 주지 못한다 — 이 카드가
      // 짧게 끝났던 원인.
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wine_bar_outlined, size: 16),
          Text('이 파티가 열리는 플레이스'),
        ],
      ),
      Text('플레이스명'),
      Text('위치 : 서울 마포구'),
      Text('플레이스 상세 보기 →'),
    ],
  ),
);

/// 환불 규정 카드와 같은 구조 — PartyChuCard + 폭을 채우는 제목 Row.
Widget refundCard() => Padding(
  padding: const EdgeInsets.only(top: 16),
  child: PartyChuCard(
    key: const Key('refund'),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.assignment_return_outlined, size: 20),
            SizedBox(width: 8),
            Text('환불 규정'),
          ],
        ),
        Text('파티 시작 7일 전까지 100% 환불'),
      ],
    ),
  ),
);

void main() {
  group('플레이스 카드는 다른 섹션 카드와 좌우 끝이 같다', () {
    for (final width in <double>[320, 360, 412]) {
      testWidgets('화면 폭 ${width.toInt()}에서 좌우 끝이 정확히 일치', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          detailBody(children: [placeCard(), refundCard()]),
        );

        final place = tester.getRect(find.byKey(const Key('place')));
        final refund = tester.getRect(find.byKey(const Key('refund')));

        expect(place.left, refund.left);
        expect(place.right, refund.right);
        // 좌우 여백은 페이지 Padding(all 20)이 낸다 — 카드가 임의 숫자로
        // 자기 여백을 따로 두지 않는다는 뜻이다.
        expect(place.left, 20);
        expect(place.right, width - 20);
      });
    }

    testWidgets('폭을 스스로 잡지 않으면 어긋난다 — 이 테스트가 잡는 회귀', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        detailBody(
          children: [
            Container(
              key: const Key('place'),
              padding: const EdgeInsets.all(16),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [Text('이 파티가 열리는 플레이스')],
              ),
            ),
            refundCard(),
          ],
        ),
      );

      final place = tester.getRect(find.byKey(const Key('place')));
      final refund = tester.getRect(find.byKey(const Key('refund')));
      expect(place.right, lessThan(refund.right));
    });
  });

  group('상세 화면이 그 규칙을 실제로 쓴다', () {
    final src = File('lib/screens/party_detail_screen.dart').readAsStringSync();
    final card = src.substring(src.indexOf('Widget _linkedEventInfo'));

    test('카드 Container가 width: double.infinity로 폭을 잡는다', () {
      final decl = card.substring(
        0,
        card.indexOf('padding: const EdgeInsets.all(16)'),
      );
      expect(decl, contains('width: double.infinity'));
    });

    test('좌우 여백을 따로 두지 않는다 — 세로 여백만 갖는다', () {
      expect(
        card,
        contains('margin: const EdgeInsets.only(top: 24, bottom: 12)'),
      );
    });
  });
}

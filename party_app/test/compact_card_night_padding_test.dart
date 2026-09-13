import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/widgets/party_card_widget.dart';

// 작은 카드(PartyCompactCard)에서 사진 위아래에 있던 흰색 카드 여백(상하 2dp
// 패딩)이 낮/밤 모드 모두 0인지를, 위젯 트리에서 썸네일을 감싼 Container의
// 실제 padding 값을 읽어 검증한다. (rawRgba toImage 캡처는 headless 테스트
// 환경에서 래스터라이저가 없어 멈추므로, 렌더링 대신 레이아웃 값으로 검증한다.)
//
// 미디어 필드가 없는 파티를 넣으면 썸네일이 네트워크 이미지 대신 플레이스홀더로
// 그려져 네트워크 호출이 없다.

Future<EdgeInsets> _thumbPadding(WidgetTester tester) async {
  final party = <String, dynamic>{
    'title': '작은 카드 테스트 파티',
    'recruitStatus': '모집중',
  };
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: SizedBox(
            width: 360,
            child: PartyCompactCard(party: party, docId: 'test-doc'),
          ),
        ),
      ),
    ),
  );

  // 썸네일(104×104 SizedBox)을 직접 감싼 padding Container를 찾는다:
  // Container(padding: fromLTRB(0, 0, 12, 0))가 카드의 상하 여백을 결정한다.
  final paddingWidget = tester.widgetList<Padding>(find.byType(Padding));
  final match = paddingWidget.firstWhere((p) {
    final e = p.padding.resolve(TextDirection.ltr);
    return e.left == 0 && e.right == 12;
  });
  return match.padding.resolve(TextDirection.ltr);
}

void main() {
  testWidgets('작은 카드: 썸네일 상하 패딩이 0이라 사진 위아래 흰 여백이 없다', (tester) async {
    final pad = await _thumbPadding(tester);
    expect(pad.top, 0, reason: '사진 위 흰 여백이 없어야 합니다.');
    expect(pad.bottom, 0, reason: '사진 아래 흰 여백이 없어야 합니다.');
  });
}

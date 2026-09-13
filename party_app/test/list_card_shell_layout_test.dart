// 가로형 목록 카드(플레이스·장소대여 작은 카드 / 지도 '이 근처 파티' 카드)에서
// **사진 아래에 빈 공간이 남지 않는지**만 픽셀로 확인한다.
//
// 예전 구조(104×104 고정 썸네일을 Row에 그냥 나란히 두기)에서는 정보 열이
// 104보다 길어지는 순간 카드만 늘어나고 사진은 104에 머물러 아래쪽에 흰
// 여백이 생겼다. 그 회귀를 잡는 테스트다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/widgets/list_card_shell.dart';

const _thumbKey = Key('thumb');
const _bodyKey = Key('body');

Future<void> _pump(WidgetTester tester, {required double infoHeight}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 360,
            child: KeyedSubtree(
              key: _bodyKey,
              child: ListCardShell.horizontalBody(
                thumbnail: ListCardShell.thumbnailBox(
                  child: Container(key: _thumbKey, color: Colors.pink),
                ),
                info: ListCardShell.infoColumn([
                  SizedBox(height: infoHeight, width: 10),
                ]),
                trailing: ListCardShell.trailingStat(
                  icon: Icons.people_outline,
                  value: '12/100',
                  unit: '명',
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('정보 열이 길어져도 사진이 카드 아래까지 꽉 찬다 — 하단 여백 0', (tester) async {
    // 배지가 두 줄로 접히고 줄이 하나 더 붙은 상황(= 정보 열이 104를 넘김).
    await _pump(tester, infoHeight: 160);

    final body = tester.getRect(find.byKey(_bodyKey));
    final thumb = tester.getRect(find.byKey(_thumbKey));

    expect(
      body.height,
      greaterThan(ListCardShell.imgSize),
      reason: '이 경우 카드가 썸네일보다 커야 테스트가 의미 있다',
    );
    expect(thumb.bottom - body.bottom, 0.0, reason: '사진 아래 여백이 남았다');
    expect(thumb.top - body.top, 0.0, reason: '사진 위 여백이 남았다');
    expect(thumb.height, body.height, reason: '사진이 카드 높이를 꽉 채우지 않는다');
    expect(thumb.width, ListCardShell.imgSize, reason: '썸네일 폭은 그대로 104');
  });

  testWidgets('정보 열이 짧으면 예전과 같은 104 정사각 썸네일이다', (tester) async {
    await _pump(tester, infoHeight: 20);

    final body = tester.getRect(find.byKey(_bodyKey));
    final thumb = tester.getRect(find.byKey(_thumbKey));

    expect(body.height, ListCardShell.imgSize);
    expect(thumb.height, ListCardShell.imgSize);
    expect(thumb.width, ListCardShell.imgSize);
    expect(thumb.bottom - body.bottom, 0.0);
  });
}

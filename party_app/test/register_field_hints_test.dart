// 등록 화면 입력칸을 찾는 힌트 상수가 **지금 화면 문구와 같은지** 지킨다.
//
// support/field_finders.dart의 상수는 제품 문구를 옮겨 적은 값이다. 화면
// 문구만 바뀌고 상수가 남으면 `fieldWithHint`가 아무 칸도 못 찾고, 실패는
// 그 상수를 쓰는 테스트마다 `Bad state: No element`로 흩어진다 — 실제로
// 플레이스 제목 힌트가 바뀌었을 때 세 파일 9건이 그렇게 깨졌고, 원인이
// "테스트 상수 한 줄"이라는 게 스택트레이스에 전혀 드러나지 않았다.
//
// 여기서는 상수마다 그 문구가 해당 화면 소스에 실제로 있는지만 본다.
// 문구를 바꾸는 것은 자유고, 바꿀 때 이 상수도 같이 고치라는 알림이다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/field_finders.dart';

void main() {
  const owners = <String, ({String hint, String path})>{
    'kEventNameHint': (
      hint: kEventNameHint,
      path: 'lib/screens/event_register_screen.dart',
    ),
    'kPlaceNameHint': (
      hint: kPlaceNameHint,
      path: 'lib/screens/place_register_screen.dart',
    ),
    'kMarketNameHint': (
      hint: kMarketNameHint,
      path: 'lib/screens/party_market_register_screen.dart',
    ),
    'kPartyTitleHint': (
      hint: kPartyTitleHint,
      path: 'lib/screens/party_register_screen.dart',
    ),
    'kRoomNameHint': (
      hint: kRoomNameHint,
      path: 'lib/widgets/place_form/room_card.dart',
    ),
    'kCrewRecruitTitleHint': (
      hint: kCrewRecruitTitleHint,
      path: 'lib/screens/crew_register_screen.dart',
    ),
    'kCrewSeekTitleHint': (
      hint: kCrewSeekTitleHint,
      path: 'lib/screens/crew_register_screen.dart',
    ),
  };

  owners.forEach((name, owner) {
    test('$name 문구가 ${owner.path.split('/').last}에 그대로 있다', () {
      final src = File(owner.path).readAsStringSync();
      expect(
        src.contains(owner.hint),
        isTrue,
        reason:
            '$name("${owner.hint}")이 ${owner.path}에 없다. 화면 문구를 바꿨다면 '
            'test/support/field_finders.dart의 상수도 같이 고쳐야 한다 — '
            '그대로 두면 그 상수를 쓰는 테스트가 엉뚱한 곳에서 깨진다.',
      );
    });
  });
}

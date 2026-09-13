import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/widgets/list_card_shell.dart';
import 'package:party_app/widgets/party_card_widget.dart';
import 'package:party_app/widgets/place_card_widget.dart';

// 플레이스 목록 카드가 파티 카드와 "정확히 같은 크기"인지 검증한다.
//
//  · 작은 화면(PlaceCompactCard)  ↔ 지도 '이 근처 파티' 카드(PartyCard)
//  · 기본 화면(PlaceStandardCard) ↔ 파티 목록 기본 카드(PartyStandardCard)
//
// 두 카드가 각각 같은 셸(ListCardShell / GridCardShell)을 쓰므로 크기가
// 어긋날 수 없지만, 나중에 한쪽만 직접 값을 하드코딩하는 회귀를 막기 위해
// 실제 렌더된 박스 크기로 비교해 둔다.
//
// 미디어 필드가 없는 데이터를 넣으면 썸네일이 네트워크 이미지 대신
// 플레이스홀더로 그려져 테스트 중 네트워크 호출이 없다.

const double _kCardWidth = 360;

Future<Size> _renderSize(WidgetTester tester, Widget card) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: SizedBox(width: _kCardWidth, child: card),
        ),
      ),
    ),
  );
  return tester.getSize(find.byWidget(card));
}

void main() {
  testWidgets('작은 화면 카드는 지도 "이 근처 파티" 카드와 같은 높이·썸네일 크기다', (tester) async {
    final partySize = await _renderSize(
      tester,
      PartyCard(
        party: const {'title': '파티', 'recruitStatus': '모집중'},
        docId: 'party-1',
      ),
    );
    final placeSize = await _renderSize(
      tester,
      PlaceCompactCard(
        place: const {
          'name': '플레이스',
          'themeTags': ['혼술'],
        },
        placeId: 'place-1',
        source: PlaceCardSource.place,
      ),
    );
    final rentalSize = await _renderSize(
      tester,
      PlaceCompactCard(
        place: const {'name': '장소', 'type': '파티룸', 'capacityMax': 20},
        placeId: 'rental-1',
        source: PlaceCardSource.rental,
      ),
    );

    expect(placeSize.width, partySize.width);
    expect(
      placeSize.height,
      partySize.height,
      reason: '플레이스 작은 화면 카드는 지도 카드와 같은 높이여야 합니다.',
    );
    expect(
      rentalSize.height,
      partySize.height,
      reason: '장소대여 작은 화면 카드도 같은 높이여야 합니다.',
    );
    // 썸네일은 두 카드 모두 공용 셸의 정사각 크기를 쓴다.
    expect(PartyCardBase.imgSize, ListCardShell.imgSize);
  });

  testWidgets('기본 화면 카드는 파티 기본 카드와 같은 폭·이미지 높이를 쓴다', (tester) async {
    final partySize = await _renderSize(
      tester,
      PartyStandardCard(
        party: const {'title': '파티', 'recruitStatus': '모집중'},
        docId: 'party-1',
      ),
    );
    final placeSize = await _renderSize(
      tester,
      PlaceStandardCard(
        place: const {
          'name': '플레이스',
          'themeTags': ['혼술'],
        },
        placeId: 'place-1',
        source: PlaceCardSource.place,
      ),
    );

    expect(placeSize.width, partySize.width);
    // 미디어 영역 높이가 고정(130)이라 사진 비율이 달라도 목록이 흔들리지 않는다.
    expect(GridCardShell.imageHeight, 130);
  });

  test('플레이스(events)는 요금 필드가 없어 요금 줄을 그리지 않는다', () {
    final place = PlaceCardInfo.from(
      {
        'name': '혼술바',
        'themeTags': ['혼술'],
        'location': '서울 강남구 역삼동',
      },
      source: PlaceCardSource.place,
      tag: 'test',
    );
    // 0원("무료")과 "가격 개념 자체가 없음"은 반드시 구분돼야 한다.
    expect(place.pricePerHour, isNull);
    expect(place.priceLabel, isNull);
    expect(place.capacityMax, 0);
    expect(place.type, '혼술'); // 테마 태그가 유형 자리에 온다(이모지 없으면 태그 그대로)

    // 장소대여는 가격 필드가 없어도 0원 = "무료"로 표시한다(기존 동작 유지).
    final rental = PlaceCardInfo.from(
      {'name': '파티룸', 'type': '파티룸'},
      source: PlaceCardSource.rental,
      tag: 'test',
    );
    expect(rental.pricePerHour, 0);
    expect(rental.priceLabel, isNotNull);
  });

  test('운영시간 라벨 — 24시간/일반/미입력', () {
    expect(placeHoursLabel({'isOpen24Hours': true}), '24시간 운영');
    expect(
      placeHoursLabel({'openTime': '09:00', 'closeTime': '22:00'}),
      '오전 9:00 ~ 오후 10:00',
    );
    // 구 스키마(openHour/closeHour)도 그대로 읽는다.
    expect(
      placeHoursLabel({'openHour': 8, 'closeHour': 20}),
      '오전 8:00 ~ 오후 8:00',
    );
    expect(placeHoursLabel({}), '');
  });
}

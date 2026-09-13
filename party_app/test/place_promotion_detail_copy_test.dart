// 매장 이벤트 상세 시트의 **머리 한 줄** — "이게 무엇인지".
//
// 사진·일정·혜택이 붙어 있는 자리라 파티 모집글로 오해하기 딱 좋다. 그래서
// 시트 맨 위에 `✨ 매장 이벤트 · <한 줄 정의>`가 붙는다([HostOffering]).
//
// ── 이 파일이 막는 재발 ─────────────────────────────────────────────────────
// 예전 정의는 "신청 없이 방문해서 즐기는 행사"였다. 그러다 보니 **예약이
// 필요한 이벤트**에서는 아래 '예약 필요' 안내와 정면으로 부딪혔고, 그걸
// 피하려고 예약 필요일 때만 뒷말을 통째로 숨기는 예외 분기가 있었다.
//
// 정의를 주체(매장이 연다)로 바꾼 지금은 부딪히지 않는다 — 예약을 받는 매장
// 이벤트도 매장 이벤트다. 그래서 **예약 여부와 상관없이 같은 줄**을 쓴다.
// 문구 충돌을 피하려고 UI를 숨기는 분기가 되살아나면 여기서 걸린다.
//
// ⚠️ '예약 필요' 안내 자체와 참여 방법·상세 데이터는 이 파일의 대상이 아니다.
//    여기서 보는 것은 머리 한 줄뿐이다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/host_offering.dart';
import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/widgets/place_product/place_promotion_detail_sheet.dart';

PlacePromotion _promotion({required bool reservationRequired}) =>
    PlacePromotion(
      id: 'P1',
      placeId: 'PL1',
      placeCollection: 'events',
      hostId: 'host-me',
      title: '생일 이벤트',
      description: '생일 당일 방문 시 케이크를 드려요.',
      imageUrl: '',
      tags: const [],
      audience: '',
      startAt: null,
      endAt: null,
      isVisible: true,
      linkedProductIds: const [],
      sortOrder: 0,
      isAlways: true,
      reservationRequired: reservationRequired,
    );

Future<void> _open(WidgetTester tester, PlacePromotion p) async {
  tester.view.physicalSize = const Size(420, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showPlacePromotionDetailSheet(
              context,
              promotion: p,
              accent: const Color(0xFFFF6FA0),
            ),
            child: const Text('열기'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
}

void main() {
  /// 시트 맨 위에 붙는 줄 — 정본에서 그대로 만든다.
  final headline =
      '${HostOffering.placeEvent.display} · '
      '${HostOffering.placeEvent.criterion}';

  testWidgets('예약이 필요 없는 이벤트 — 한 줄 정의가 붙는다', (tester) async {
    await _open(tester, _promotion(reservationRequired: false));
    expect(find.text(headline), findsOneWidget);
  });

  // 예전에는 이 경우에만 뒷말이 사라졌다.
  testWidgets('예약이 필요한 이벤트에서도 같은 줄을 그대로 쓴다', (tester) async {
    await _open(tester, _promotion(reservationRequired: true));

    expect(
      find.text(headline),
      findsOneWidget,
      reason: '예약 필요라는 이유로 한 줄 정의를 숨기면 안 된다',
    );
    expect(
      find.text(HostOffering.placeEvent.display),
      findsNothing,
      reason: '이모지+이름만 남은 축약형이 되살아났다',
    );
    // 예약 안내 자체는 그대로 있어야 한다 — 이 정리는 문구 충돌만 없앤 것이지
    // 예약 표시를 건드린 것이 아니다(표시는 뒤에 아이콘에서 📅 + 한 줄로
    // 바뀌었고, 내용은 place_event_reservation_notice_test.dart가 본다).
    expect(find.text('사전 예약이 필요한 이벤트예요'), findsOneWidget);
  });

  testWidgets('머리 줄이 매장 이벤트를 "신청 없는 행사"로 말하지 않는다', (tester) async {
    await _open(tester, _promotion(reservationRequired: true));

    for (final banned in ['신청 없이', '모집 없이', '별도 참가 모집']) {
      expect(find.textContaining(banned), findsNothing, reason: banned);
    }
  });
}

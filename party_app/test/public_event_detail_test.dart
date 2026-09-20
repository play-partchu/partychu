// 🎊 공공 축제 상세 — 카드를 누르면 공공 축제 전용 상세로 가고, 운영 문서에
// 있는 필드만 보여주며, 값이 없는 줄은 자리째 빠진다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:party_app/models/event_feed.dart';
import 'package:party_app/models/public_event.dart';
import 'package:party_app/screens/event_detail_screen.dart';
import 'package:party_app/screens/place_detail_screen.dart';
import 'package:party_app/screens/public_event_detail_screen.dart';
import 'package:party_app/widgets/public_event_card.dart';

PublicEvent festival({
  String? address = '서울특별시 강동구 올림픽로 875 (암사동)',
  String? addressDetail,
  String? tel = '02-3425-5250',
}) => PublicEvent(
  id: 'tour_1307813',
  source: 'tourapi',
  sourceId: '1307813',
  title: '강동선사문화축제',
  startAt: DateTime(2026, 10, 16),
  endAt: DateTime(2026, 10, 18, 23, 59, 59),
  startDate: '20261016',
  endDate: '20261018',
  attribution: '한국관광공사',
  status: 'active',
  isVisible: true,
  address: address,
  addressDetail: addressDetail,
  tel: tel,
  lat: 37.5590614,
  lng: 127.1306007,
  // 이미지는 비워 둔다 — 테스트에서 네트워크 이미지를 받지 않게.
);

Widget host(Widget child) => MaterialApp(
  home: Scaffold(body: ListView(children: [child])),
);

void main() {
  // 갤러리 자동 넘김이 켜져 있어 화면 노출 감지가 붙는다 — 기본 간격(0.5초)이
  // 타이머로 남으면 위젯을 내린 뒤에도 테스트가 실패한다.
  setUpAll(() {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  testWidgets('카드를 누르면 공공 축제 상세로 간다(매장/공간 상세가 아니다)', (
    tester,
  ) async {
    final e = festival(addressDetail: '암사동 선사유적지 일대');
    await tester.pumpWidget(
      host(
        PublicEventCompactCard(
          event: e,
          badge: EventFeedKind.publicFestival.badge,
        ),
      ),
    );
    expect(find.text('🎊 공공 축제'), findsOneWidget);
    expect(find.text('출처: 한국관광공사'), findsOneWidget);

    await tester.tap(find.text('강동선사문화축제'));
    await tester.pumpAndSettle();

    expect(find.byType(PublicEventDetailScreen), findsOneWidget);
    expect(find.byType(EventDetailScreen), findsNothing);
    expect(find.byType(PlaceDetailScreen), findsNothing);
    // 목록의 객체가 그대로 넘어왔다.
    final screen = tester.widget<PublicEventDetailScreen>(
      find.byType(PublicEventDetailScreen),
    );
    expect(identical(screen.event, e), isTrue);

    // 앱바 제목 + 본문 제목.
    expect(find.text('강동선사문화축제'), findsNWidgets(2));
    expect(find.text('🎊 공공 축제'), findsOneWidget);
    expect(find.text('2026년 10월 16일 (금) ~ 10월 18일 (일)'), findsOneWidget);
    expect(
      find.text('서울특별시 강동구 올림픽로 875 (암사동) 암사동 선사유적지 일대'),
      findsOneWidget,
    );
    expect(find.text('02-3425-5250'), findsOneWidget);
    expect(find.text('출처: 한국관광공사'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('publicEventImagePlaceholder')),
      findsOneWidget,
    );
    // 파티츄 자체 행사 기능은 없다. ('문의'는 행사 정보의 문의처 줄로만 나온다
    // — 전화번호가 있는 보강 전 문서도 그 줄에 번호가 보인다.)
    expect(find.textContaining('신청'), findsNothing);
    expect(find.textContaining('문의하기'), findsNothing);
    expect(find.byIcon(Icons.favorite_border), findsNothing);

    // 뒤로가기 — 목록으로 돌아온다.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(PublicEventDetailScreen), findsNothing);
    expect(find.byType(PublicEventCompactCard), findsOneWidget);
  });

  testWidgets('값이 없는 줄은 자리째 빠진다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PublicEventDetailScreen(
          event: festival(address: null, tel: null),
        ),
      ),
    );
    expect(find.byIcon(Icons.location_on_outlined), findsNothing);
    expect(find.byIcon(Icons.phone_outlined), findsNothing);
    expect(find.byIcon(Icons.event), findsOneWidget);
    expect(find.text('출처: 한국관광공사'), findsOneWidget);
  });

  test('주소 + 상세주소 합치기', () {
    expect(publicEventFullAddress('서울 강동구', null), '서울 강동구');
    expect(publicEventFullAddress('서울 강동구', '  '), '서울 강동구');
    expect(publicEventFullAddress('서울 강동구', '암사동 일대'), '서울 강동구 암사동 일대');
    // 이미 주소에 들어 있으면 두 번 붙이지 않는다.
    expect(publicEventFullAddress('서울 강동구 (암사동)', '(암사동)'), '서울 강동구 (암사동)');
    expect(publicEventFullAddress(null, '상세만'), '상세만');
    expect(publicEventFullAddress(null, null), '');
  });

  test('상세 기간 — 하루짜리·해 넘김', () {
    PublicEvent withDates(String s, String e) => PublicEvent(
      id: 'x',
      source: 'tourapi',
      sourceId: 'x',
      title: 't',
      startAt: DateTime(2026),
      endAt: DateTime(2027),
      startDate: s,
      endDate: e,
      attribution: '한국관광공사',
      status: 'active',
      isVisible: true,
    );
    expect(
      publicEventDetailPeriod(withDates('20260920', '20260920')),
      '2026년 9월 20일 (일)',
    );
    expect(
      publicEventDetailPeriod(withDates('20261228', '20270103')),
      '2026년 12월 28일 (월) ~ 2027년 1월 3일 (일)',
    );
    expect(publicEventDetailPeriod(withDates('', '')), '');
  });
}

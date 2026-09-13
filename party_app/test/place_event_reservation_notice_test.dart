// 매장 이벤트의 **사전 예약 필요**.
//
// ── 이 설정이 하는 일과 하지 않는 일 ────────────────────────────────────────
// 하는 일  : 게스트에게 "미리 예약해야 한다"고 알리고, 호스트가 적어 둔 예약
//            방법을 그대로 보여준다.
// 하지 않는 일: 예약 문서·예약 화면·결제를 만들지 않는다. 그래서 이 이벤트에서
//            예약을 잡는 길은 **문의뿐**이고, 그 길이 사라지면 손님은 안내만
//            읽고 아무 데도 갈 수 없다 — 이 파일이 막는 것이 그 상태다.
//
// 신청과는 서로 모른다. 사전 예약을 켠다고 신청이 켜지지 않고, 그 반대도 아니다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/event_apply.dart';
import 'package:party_app/models/listing_inquiry.dart';
import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/screens/place_event_edit_screen.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/guest_inquiry_section.dart';
import 'package:party_app/widgets/place_product/place_promotion_detail_sheet.dart';

PlacePromotion _promo(Map<String, dynamic> d) =>
    PlacePromotion.fromMap('EV1', {'hostId': 'host1', 'title': '와인 시음회', ...d});

void main() {
  group('저장 — 기존 필드는 그대로, 안내 문구 하나만 는다', () {
    test('필드가 없던 옛 이벤트도 그대로 읽힌다', () {
      final old = _promo(const {'reservationRequired': true});

      expect(old.reservationRequired, isTrue);
      expect(old.reservationGuide, '');
      // 안내가 없으면 상세는 제목만 보여준다(빈 줄을 만들지 않는다).
    });

    test('쓴 문구를 그대로 다시 읽어 온다', () {
      final saved = _promo(const {
        'reservationRequired': true,
      }).copyWith(reservationGuide: '방문 전 문의하기를 눌러 희망 날짜와 인원을 알려주세요.');
      final reread = PlacePromotion.fromMap('EV1', saved.toMap());

      expect(reread.reservationRequired, isTrue);
      expect(reread.reservationGuide, saved.reservationGuide);
    });

    test('사전 예약을 끄면 안내 문구도 함께 지운다', () {
      // 꺼 둔 채 남겨 두면 나중에 다시 켰을 때 예전 문구가 되살아난다.
      final off = _promo(const {}).copyWith(reservationGuide: '옛 안내');
      expect(off.toMap()['reservationGuide'], '');
    });

    test('긴 문구는 다른 안내문과 같은 상한에서 자른다', () {
      final long = 'ㄱ' * (ListingInquiry.maxGuideLength + 50);
      final p = _promo({'reservationRequired': true, 'reservationGuide': long});

      expect(p.reservationGuide.length, ListingInquiry.maxGuideLength);
    });
  });

  group('문의 버튼 — 사전 예약이 켜지면 접지 않는다', () {
    test("신청 방식이 '신청하기'만이어도 문의가 함께 보인다", () {
      // 예약을 물어볼 길이 여기밖에 없다.
      final p = _promo({
        'reservationRequired': true,
        ListingInquiry.field: true,
        EventApplyMode.field: EventApplyMode.applyOnly.key,
      });

      expect(p.showsInquiryButton, isTrue);
      // 신청은 신청대로 그대로다 — 한쪽이 다른 쪽을 대체하지 않는다.
      expect(p.applyMode, EventApplyMode.applyOnly);
      expect(p.showsApplyButtonAt(DateTime(2026, 8, 30)), isTrue);
    });

    test('사전 예약이 문의를 **켜지는** 못한다', () {
      // 호스트가 끈 문의를 다른 설정이 몰래 켜지 않는다는 약속은 그대로다.
      final p = _promo({
        'reservationRequired': true,
        ListingInquiry.field: false,
      });

      expect(p.showsInquiryButton, isFalse);
    });

    test('사전 예약이 꺼져 있으면 예전 규칙 그대로다', () {
      final applyOnly = _promo({
        ListingInquiry.field: true,
        EventApplyMode.field: EventApplyMode.applyOnly.key,
      });
      expect(applyOnly.showsInquiryButton, isFalse);

      final both = _promo({
        ListingInquiry.field: true,
        EventApplyMode.field: EventApplyMode.inquiryAndApply.key,
      });
      expect(both.showsInquiryButton, isTrue);
    });

    test('사전 예약은 신청을 켜지 않는다', () {
      final p = _promo(const {'reservationRequired': true});

      expect(p.applyMode, EventApplyMode.none);
      expect(p.showsApplyButtonAt(DateTime(2026, 8, 30)), isFalse);
    });
  });

  group('게스트 상세 — 안내와 문의가 함께 보인다', () {
    Future<void> open(WidgetTester tester, PlacePromotion promotion) async {
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showPlacePromotionDetailSheet(
                  ctx,
                  promotion: promotion,
                  accent: const Color(0xFFFF6FA0),
                  hostName: '호스트',
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

    testWidgets('제목과 호스트가 적은 예약 방법이 함께 뜬다', (tester) async {
      // 로그아웃 상태로 본다 — 신청 버튼은 로그인 전에도 그려지고, 로그인
      // 상태에서는 내 신청을 물으러 Firestore로 나간다(테스트 환경엔 없다).
      UserSession.userId = '';
      await open(
        tester,
        _promo({
          'reservationRequired': true,
          'reservationGuide': '방문 전 문의하기를 눌러 희망 날짜와 인원을 알려주세요.',
          ListingInquiry.field: true,
          EventApplyMode.field: EventApplyMode.applyOnly.key,
        }),
      );

      expect(find.text('사전 예약이 필요한 이벤트예요'), findsOneWidget);
      expect(find.text('방문 전 문의하기를 눌러 희망 날짜와 인원을 알려주세요.'), findsOneWidget);
      // 예약을 물어볼 길 — 신청 방식이 '신청하기'만이어도 문의가 남는다.
      expect(find.textContaining('문의'), findsWidgets);
      expect(find.text('신청하기'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('안내 문구가 없으면 제목만 보여준다', (tester) async {
      // 로그아웃 상태로 본다 — 신청 버튼은 로그인 전에도 그려지고, 로그인
      // 상태에서는 내 신청을 물으러 Firestore로 나간다(테스트 환경엔 없다).
      UserSession.userId = '';
      await open(
        tester,
        _promo({'reservationRequired': true, ListingInquiry.field: true}),
      );

      expect(find.text('사전 예약이 필요한 이벤트예요'), findsOneWidget);
      expect(find.text('문의하기'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('사전 예약이 꺼진 이벤트에는 안내가 없다', (tester) async {
      // 로그아웃 상태로 본다 — 신청 버튼은 로그인 전에도 그려지고, 로그인
      // 상태에서는 내 신청을 물으러 Firestore로 나간다(테스트 환경엔 없다).
      UserSession.userId = '';
      await open(tester, _promo({ListingInquiry.field: true}));

      expect(find.text('사전 예약이 필요한 이벤트예요'), findsNothing);
    });
  });

  group('호스트 화면 — 잠긴 문의 스위치', () {
    testWidgets('잠기면 끌 수 없고, 왜 잠겼는지 말해 준다', (tester) async {
      var enabled = true;
      var changed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GuestInquirySection(
                enabled: enabled,
                onChanged: (v) {
                  changed += 1;
                  enabled = v;
                },
                lockedNote: '사전 예약 안내를 위해 문의 받기가 함께 켜져 있어요.',
              ),
            ),
          ),
        ),
      );

      expect(find.text('사전 예약 안내를 위해 문의 받기가 함께 켜져 있어요.'), findsOneWidget);
      final sw = tester.widget<Switch>(find.byType(Switch));
      expect(sw.onChanged, isNull, reason: '잠겼는데 눌리면 고장으로 읽힌다');
      await tester.tap(find.byType(Switch), warnIfMissed: false);
      await tester.pump();
      expect(changed, 0);
    });

    testWidgets('잠기지 않은 화면은 예전 그대로 켜고 끈다', (tester) async {
      var changed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GuestInquirySection(
                enabled: true,
                onChanged: (_) => changed += 1,
              ),
            ),
          ),
        ),
      );

      expect(find.textContaining('함께 켜져 있어요'), findsNothing);
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(changed, 1);
    });
  });

  // 등록·수정은 같은 폼 하나라, 여기가 통과하면 두 경우 모두 통과한다.
  group('호스트 화면 — 사전 예약을 켜면 문의도 함께 켜진다', () {
    Future<void> open(WidgetTester tester, {PlacePromotion? existing}) async {
      tester.view.physicalSize = const Size(400, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: PlaceEventEditScreen(
            placeId: 'PL1',
            placeCollection: 'events',
            hostId: 'host-me',
            placeName: '가게',
            accent: const Color(0xFFFF6FA0),
            existing: existing,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> toggle(WidgetTester tester, String title) async {
      final sw = find.widgetWithText(SwitchListTile, title);
      await tester.ensureVisible(sw);
      await tester.pump();
      await tester.tap(sw);
      await tester.pumpAndSettle();
    }

    testWidgets('이름과 안내 문구가 바뀌었다', (tester) async {
      await open(tester);

      expect(find.text('사전 예약 필요'), findsOneWidget);
      expect(find.text('예약 필요'), findsNothing);
      expect(find.text('이 이벤트 이용 전에 매장/장소 예약이 필요한 경우 켜주세요.'), findsOneWidget);
      // 이 스위치가 예약 기능을 만들지 않는다는 사실을 화면에서 밝힌다.
      expect(find.textContaining('별도의 예약 기능을 생성하지 않고'), findsOneWidget);
    });

    testWidgets('켜면 예약 안내 칸이 나오고 문의 스위치가 잠긴다', (tester) async {
      await open(tester);

      // 켜기 전 — 안내 칸은 없고 문의는 자유롭게 끌 수 있다.
      expect(find.text('예약 안내'), findsNothing);
      expect(
        tester.widget<Switch>(find.byType(Switch).last).onChanged,
        isNotNull,
      );

      await toggle(tester, '사전 예약 필요');

      expect(find.text('예약 안내'), findsOneWidget);
      expect(find.text('사전 예약 안내를 위해 문의 받기가 함께 켜져 있어요.'), findsOneWidget);
      // 문의 스위치는 켜진 채 잠긴다 — 예약을 물어볼 유일한 길이라서다.
      final inquirySwitch = tester.widget<Switch>(find.byType(Switch).last);
      expect(inquirySwitch.value, isTrue);
      expect(inquirySwitch.onChanged, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('사전 예약을 켜도 신청 받기는 그대로 꺼져 있다', (tester) async {
      await open(tester);
      await toggle(tester, '사전 예약 필요');

      // 신청 문서와 예약 문의는 서로 다른 기능이다 — 하나가 다른 하나를 켜지
      // 않는다.
      final applySwitch = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, '신청 받기'),
      );
      expect(applySwitch.value, isFalse);
      expect(find.text('신청 방식'), findsNothing);
    });

    testWidgets('문의를 꺼 둔 옛 이벤트도 켜진 채로 열린다', (tester) async {
      // 잠겼다고 말하면서 OFF를 보여주면 그 잠금이 거짓말이 된다.
      await open(
        tester,
        existing: PlacePromotion.fromMap('EV1', {
          'hostId': 'host-me',
          'title': '와인 시음회',
          'reservationRequired': true,
          ListingInquiry.field: false,
        }),
      );

      final inquirySwitch = tester.widget<Switch>(find.byType(Switch).last);
      expect(inquirySwitch.value, isTrue);
      expect(inquirySwitch.onChanged, isNull);
    });
  });
}

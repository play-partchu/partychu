// 매장 이벤트의 **신청 받기**.
//
// ── 이 파일이 막는 재발 ─────────────────────────────────────────────────────
// 예전에는 매장 이벤트를 "신청 없이 방문해서 즐기는 행사"로 못박고, 신청을
// 받고 싶으면 🎉 파티로 보냈다. 그런데 신청 여부는 두 개념을 가르는 기준이
// 아니다 — 생일 이벤트처럼 **매장이 여는 행사인데 사전 신청을 받는 것**이
// 얼마든지 있고, 그 이벤트는 갈 곳이 없었다.
//
// 여기서 고정하는 것:
//   ① 필드가 없는 옛 이벤트는 신청 안 받음 — 게스트 화면이 예전과 똑같다
//   ② 신청 방식이 문의 버튼을 **좁히기만** 한다(호스트가 끈 문의를 켜지 못한다)
//   ③ 종료·숨김 이벤트에는 신청 CTA가 없다 — **시작 전에는 받는다**
//   ④ 신청과 문의는 **서로 다른 것**이다(신청은 문서, 문의는 채팅)
//   ⑤ 저장 필드는 applyMode 하나, 문서 나머지는 그대로
//
// ⚠️ 정원·승인·참가비는 이 파일의 대상이 아니다 — 매장 이벤트에는 그 축이
//    없다. 신청 데이터 자체(컬렉션·문서 id·중복 방지·취소)는
//    place_event_application_test.dart가 본다.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'package:party_app/models/event_apply.dart';
import 'package:party_app/models/host_offering.dart';
import 'package:party_app/models/listing_inquiry.dart';
import 'package:party_app/models/place_event_application.dart';
import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/screens/place_event_edit_screen.dart';
import 'package:party_app/widgets/place_product/place_promotion_detail_sheet.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/event_apply_button.dart';

import 'package:party_app/widgets/place_product/place_promotion_list_section.dart';

final _now = DateTime(2026, 8, 30, 12);

PlacePromotion _promo({
  EventApplyMode applyMode = EventApplyMode.none,
  bool inquiryEnabled = true,
  bool isVisible = true,
  bool isAlways = true,
  DateTime? startAt,
  DateTime? endAt,
  String hostId = 'host-me',
}) => PlacePromotion(
  id: 'P1',
  placeId: 'PL1',
  placeCollection: 'events',
  hostId: hostId,
  title: '생일 이벤트',
  description: '',
  imageUrl: '',
  tags: const [],
  audience: '',
  startAt: startAt,
  endAt: endAt,
  isVisible: isVisible,
  linkedProductIds: const [],
  sortOrder: 0,
  isAlways: isAlways,
  imageUrls: const ['https://cdn.test/a.jpg'],
  inquiryEnabled: inquiryEnabled,
  applyMode: applyMode,
);

void main() {
  // 상세 시트의 사진·영상 갤러리가 자동 넘김용 VisibilityDetector를 쓴다 —
  // 기본 500ms 지연 타이머가 테스트 끝에 남지 않게 즉시 갱신한다.
  setUpAll(() {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });
  setUp(() {
    // 로그아웃 상태가 기본 — "내 글에는 버튼을 안 그린다" 분기를 타지 않는다.
    UserSession.userId = '';
  });
  tearDown(() => UserSession.userId = '');

  // ── 하위호환 ────────────────────────────────────────────────────────────

  group('필드가 없는 옛 이벤트', () {
    test('신청 안 받음으로 읽힌다', () {
      expect(EventApplyMode.fromKey(null), EventApplyMode.none);
      expect(EventApplyMode.fromKey(''), EventApplyMode.none);
      // 서버에 새 값이 생겨도 모르는 값은 신청을 열지 않는다(fail-closed).
      expect(EventApplyMode.fromKey('someday'), EventApplyMode.none);
    });

    test('applyMode 키가 아예 없는 문서도 그대로 읽힌다', () {
      final p = PlacePromotion.fromMap('P1', {
        'title': '옛 이벤트',
        'isVisible': true,
        'isAlways': true,
      });
      expect(p.applyMode, EventApplyMode.none);
      expect(p.showsApplyButtonAt(_now), isFalse);
    });

    test('문의 버튼은 예전 규칙 그대로다 — 신청 필드가 좁히지 않는다', () {
      expect(_promo(inquiryEnabled: true).showsInquiryButton, isTrue);
      expect(_promo(inquiryEnabled: false).showsInquiryButton, isFalse);
    });
  });

  // ── 신청 방식이 두 버튼을 어떻게 정하는가 ───────────────────────────────

  group('신청 방식', () {
    test('신청하기 — 신청만 보이고 문의는 접힌다', () {
      final p = _promo(applyMode: EventApplyMode.applyOnly);
      expect(p.showsApplyButtonAt(_now), isTrue);
      expect(p.showsInquiryButton, isFalse);
    });

    test('문의 및 신청하기 — 둘 다 보인다', () {
      final p = _promo(applyMode: EventApplyMode.inquiryAndApply);
      expect(p.showsApplyButtonAt(_now), isTrue);
      expect(p.showsInquiryButton, isTrue);
    });

    // 문의의 정본은 끝까지 ListingInquiry다. 신청 방식이 그것을 **넓히지
    // 못한다** — 여기가 뚫리면 호스트가 꺼 둔 문의가 몰래 열린다.
    test('문의를 끈 이벤트는 "문의 및 신청하기"여도 문의가 안 열린다', () {
      final p = _promo(
        applyMode: EventApplyMode.inquiryAndApply,
        inquiryEnabled: false,
      );
      expect(p.showsInquiryButton, isFalse);
      expect(p.showsApplyButtonAt(_now), isTrue);
    });

    test('신청 안 받음 — 신청 버튼이 없다', () {
      expect(_promo().showsApplyButtonAt(_now), isFalse);
    });
  });

  // ── 신청할 수 없는 상태 ─────────────────────────────────────────────────

  group('신청 CTA가 뜨면 안 되는 상태', () {
    test('종료된 이벤트', () {
      final p = _promo(
        applyMode: EventApplyMode.applyOnly,
        isAlways: false,
        startAt: DateTime(2026, 8, 1),
        endAt: DateTime(2026, 8, 10),
      );
      expect(p.statusAt(_now), PromotionStatus.ended);
      expect(p.showsApplyButtonAt(_now), isFalse);
    });

    test('숨긴 이벤트', () {
      final p = _promo(applyMode: EventApplyMode.applyOnly, isVisible: false);
      expect(p.showsApplyButtonAt(_now), isFalse);
    });

    test('시작 전 이벤트는 미리 신청받을 수 있다', () {
      final p = _promo(
        applyMode: EventApplyMode.applyOnly,
        isAlways: false,
        startAt: DateTime(2026, 9, 20),
        endAt: DateTime(2026, 9, 30),
      );
      expect(p.statusAt(_now), PromotionStatus.scheduled);
      expect(p.showsApplyButtonAt(_now), isTrue);
    });

    test('내 이벤트에는 신청 버튼을 두지 않는다', () {
      UserSession.userId = 'host-me';
      final p = _promo(applyMode: EventApplyMode.applyOnly);
      expect(EventApplyButton.shouldShow(p, now: _now), isFalse);
    });
  });

  // ── 게스트 화면 ─────────────────────────────────────────────────────────

  Future<void> pumpCard(WidgetTester tester, PlacePromotion p) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PlacePromotionCardList(
              promotions: [p],
              accent: const Color(0xFFFF6FA0),
              hostName: '호스트',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('카드', () {
    testWidgets('신청 가능한 이벤트는 카드에서 알 수 있다', (tester) async {
      await pumpCard(tester, _promo(applyMode: EventApplyMode.applyOnly));
      expect(find.text('신청 가능'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('신청을 안 받으면 배지가 없다', (tester) async {
      await pumpCard(tester, _promo());
      expect(find.text('신청 가능'), findsNothing);
    });

    testWidgets('종료된 이벤트는 신청 배지가 없다', (tester) async {
      await pumpCard(
        tester,
        _promo(
          applyMode: EventApplyMode.applyOnly,
          isAlways: false,
          startAt: DateTime(2020, 1, 1),
          endAt: DateTime(2020, 1, 2),
        ),
      );
      expect(find.text('신청 가능'), findsNothing);
    });
  });

  // ── 문의와 신청은 서로 다른 것이다 ──────────────────────────────────────

  group('신청 흐름', () {
    // 예전에는 신청하기가 이벤트 채팅방을 열고 "[신청] …" 한 줄을 보내는 것으로
    // 끝났다. 그러면 신청 데이터가 어디에도 남지 않아, 호스트는 채팅 목록을
    // 눈으로 세야 하고 게스트는 자기가 신청했는지 알 수 없었다.
    //
    // 이제 신청은 자기 문서를 만든다. 문의는 예전 그대로 채팅이다.
    test('문의는 여전히 이벤트 채팅으로 간다', () {
      expect(InquiryTarget.event.relatedType, 'event');
      expect(InquiryTarget.event.collection, 'placePromotions');
    });

    test('신청은 채팅이 아니라 자기 컬렉션에 남는다', () {
      expect(
        PlaceEventApplication.collection,
        isNot(InquiryTarget.event.collection),
      );
      expect(PlaceEventApplication.collection, 'placeEventApplications');
    });

    // 신청 버튼이 채팅 여는 함수를 다시 부르기 시작하면 예전 구조로 돌아간다.
    // 파일에 그 흔적이 남지 않게 못 박는다.
    test('신청 버튼에 채팅으로 보내는 경로가 남아 있지 않다', () {
      final src = File(
        'lib/widgets/event_apply_button.dart',
      ).readAsStringSync();
      // 주석에는 "예전에 이랬다"는 기록이 남아 있어도 된다 — 실제로 부르는
      // 이름만 본다.
      final code = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('///'))
          .join('\n');
      expect(code, isNot(contains('openListingChat')));
      expect(code, isNot(contains('ChatService')));
      expect(code, isNot(contains('openingMessage')));
      expect(code, contains('PlaceEventApplicationService'));
    });
  });

  // ── 저장 구조 ───────────────────────────────────────────────────────────

  group('placePromotions 문서', () {
    test('신청 설정은 applyMode 한 필드로 저장된다', () {
      final map = _promo(applyMode: EventApplyMode.inquiryAndApply).toMap();
      expect(map[EventApplyMode.field], 'inquiry_and_apply');
      // 문의는 여전히 세 도메인 공용 필드 하나다 — 여기에 복제하지 않았다.
      expect(map[ListingInquiry.field], isTrue);
    });

    test('저장한 값이 그대로 되읽힌다', () {
      for (final m in EventApplyMode.values) {
        final saved = _promo(applyMode: m).toMap();
        expect(PlacePromotion.fromMap('P1', saved).applyMode, m, reason: m.key);
      }
    });

    test('키는 문서에 그대로 남는 값이라 바뀌면 안 된다', () {
      expect(EventApplyMode.none.key, 'none');
      expect(EventApplyMode.applyOnly.key, 'apply');
      expect(EventApplyMode.inquiryAndApply.key, 'inquiry_and_apply');
      expect(EventApplyMode.field, 'applyMode');
    });
  });

  group('등록·수정 폼', _formTests);
  group('게스트 상세 시트', _detailSheetTests);

  // ── 문구 ────────────────────────────────────────────────────────────────

  group('안내 문구', () {
    // "신청을 받을 예정인가요? → 파티"는 신청을 받는 호스트를 전부 파티로
    // 보낸다. 이제 매장 이벤트도 신청을 받으므로 가르는 말이 달라야 한다.
    test('파티로 보내는 물음이 신청 여부로 가르지 않는다', () {
      expect(HostOffering.toPartyPrompt, contains('참가자 모집이 중심'));
      expect(HostOffering.toPartyPrompt, isNot(contains('신청을 받을 예정')));
    });

    test('등록 폼 머리말이 신청받는 이벤트도 여기라고 말한다', () {
      expect(HostOffering.placeEventFormSubtitle, contains('사전 신청'));
      expect(HostOffering.placeEventFormSubtitle, contains('자유롭게 방문'));
    });

    test('매장 이벤트를 "신청 없는 행사"로 정의하는 문구가 없다', () {
      for (final copy in [
        HostOffering.placeEvent.criterion,
        HostOffering.placeEvent.meaning,
        HostOffering.placeEvent.registerDescription,
        HostOffering.placeEventFormSubtitle,
        HostOffering.criterionHeadline,
        HostOffering.toPartyPrompt,
        HostOffering.toPlaceEventPrompt,
      ]) {
        for (final banned in ['신청 없이', '모집 없이', '신청 모집 없이']) {
          expect(copy, isNot(contains(banned)), reason: '$copy ← "$banned"');
        }
      }
    });
  });
}

// ── 등록/수정 화면 ──────────────────────────────────────────────────────────
//
// 신규 등록과 수정이 **같은 폼 하나**라, 여기가 통과하면 두 경우 모두 통과한다
// ([PlaceEventEditScreen]은 existing 유무로만 갈린다).
void _formTests() {
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

  testWidgets('신규 등록 — 신청 받기가 꺼진 채로 열린다', (tester) async {
    await open(tester);

    expect(find.text('신청 받기'), findsOneWidget);
    // 꺼져 있으면 방식 선택은 나오지 않는다.
    expect(find.text('신청 방식'), findsNothing);
    expect(find.text(EventApplyMode.applyOnly.label), findsNothing);
  });

  testWidgets('신청 받기를 켜면 방식 두 가지를 고를 수 있다', (tester) async {
    await open(tester);

    final sw = find.widgetWithText(SwitchListTile, '신청 받기');
    await tester.ensureVisible(sw);
    await tester.pump();
    await tester.tap(sw);
    await tester.pumpAndSettle();

    expect(find.text('신청 방식'), findsOneWidget);
    expect(find.text(EventApplyMode.applyOnly.label), findsOneWidget);
    expect(find.text(EventApplyMode.inquiryAndApply.label), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('수정 진입 — 저장해 둔 방식이 그대로 켜져 있다', (tester) async {
    await open(
      tester,
      existing: _promo(applyMode: EventApplyMode.inquiryAndApply),
    );

    expect(find.text('신청 방식'), findsOneWidget);
    final tile = tester.widget<RadioListTile<EventApplyMode>>(
      find.widgetWithText(
        RadioListTile<EventApplyMode>,
        EventApplyMode.inquiryAndApply.label,
      ),
    );
    // ignore: deprecated_member_use
    expect(tile.groupValue, EventApplyMode.inquiryAndApply);
  });

  testWidgets('폼 머리말이 신청받는 이벤트도 여기라고 말한다', (tester) async {
    await open(tester);
    expect(find.text(HostOffering.placeEventFormSubtitle), findsOneWidget);
    expect(
      find.text(
        '${HostOffering.placeEvent.emoji} ${HostOffering.placeEvent.criterion}',
      ),
      findsOneWidget,
    );
    // 파티로 보내는 줄이 신청 여부로 가르지 않는다.
    expect(find.text(HostOffering.toPartyPrompt), findsOneWidget);
  });

  // 문의를 끈 채 '문의 및 신청하기'를 고르면 화면이 그 사실을 말해 준다 —
  // 저장한 뒤 "왜 문의 버튼이 없지?"로 돌아오지 않게.
  testWidgets('문의가 꺼져 있으면 그 사실을 폼에서 알려 준다', (tester) async {
    await open(
      tester,
      existing: _promo(
        applyMode: EventApplyMode.inquiryAndApply,
        inquiryEnabled: false,
      ),
    );
    expect(find.textContaining('지금은 신청하기만 보여요'), findsOneWidget);
  });
}

// ── 게스트 상세 시트 ────────────────────────────────────────────────────────
void _detailSheetTests() {
  Future<void> open(WidgetTester tester, PlacePromotion p) async {
    tester.view.physicalSize = const Size(400, 1600);
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

  testWidgets('신청하기 — 신청 버튼만 뜬다', (tester) async {
    await open(tester, _promo(applyMode: EventApplyMode.applyOnly));
    expect(find.text('신청하기'), findsOneWidget);
    expect(find.text('채팅 문의'), findsNothing);
    expect(find.text('문의하기'), findsNothing);
  });

  testWidgets('문의 및 신청하기 — 둘 다 뜬다', (tester) async {
    await open(tester, _promo(applyMode: EventApplyMode.inquiryAndApply));
    expect(find.text('신청하기'), findsOneWidget);
    // 신청이 주 CTA라 문의는 흑백('채팅 문의')으로 물러선다.
    expect(find.text('채팅 문의'), findsOneWidget);
  });

  testWidgets('신청 안 받음 — 예전처럼 문의만 뜬다', (tester) async {
    await open(tester, _promo());
    expect(find.text('신청하기'), findsNothing);
    expect(find.text('문의하기'), findsOneWidget);
  });

  testWidgets('종료된 이벤트에는 신청 CTA가 없다', (tester) async {
    await open(
      tester,
      _promo(
        applyMode: EventApplyMode.applyOnly,
        isAlways: false,
        startAt: DateTime(2020, 1, 1),
        endAt: DateTime(2020, 1, 2),
      ),
    );
    expect(find.text('신청하기'), findsNothing);
  });

  testWidgets('좁은 폭에서 두 버튼이 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(320, 1600);
    await open(tester, _promo(applyMode: EventApplyMode.inquiryAndApply));
    expect(tester.takeException(), isNull);
  });
}

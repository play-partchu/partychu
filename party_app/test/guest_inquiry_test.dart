import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/listing_inquiry.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/guest_inquiry_button.dart';
import 'package:party_app/widgets/guest_inquiry_section.dart';

/// 게스트 문의 받기 — 파티·플레이스·장소대여가 **하나의 기준**을 쓴다는 것과,
/// 켰을 때/껐을 때 상세 페이지가 무엇을 보여주는지를 못박는다.
///
/// 서버 쪽 같은 정책(문의를 닫은 게시글에 새 문의 방을 못 만든다 / 기존 방은
/// 그대로 열려 있다)은 firestore.rules 시뮬레이션이 따로 본다.
void main() {
  group('ListingInquiry — 세 도메인이 공유하는 기준', () {
    test('필드가 없으면 켜진 것으로 읽는다', () {
      // 이 기능이 생기기 전에 등록된 문서가 조용히 "문의를 받지 않는 파티"가
      // 되면 안 된다.
      expect(ListingInquiry.isEnabled(const {}), isTrue);
      expect(ListingInquiry.isEnabled(null), isTrue);
      expect(ListingInquiry.defaultEnabled, isTrue);
    });

    test('저장된 값을 그대로 읽는다', () {
      expect(ListingInquiry.isEnabled(const {'inquiryEnabled': true}), isTrue);
      expect(
        ListingInquiry.isEnabled(const {'inquiryEnabled': false}),
        isFalse,
      );
    });

    test('불리언이 아닌 값은 기본값으로 되돌린다', () {
      expect(
        ListingInquiry.isEnabled(const {'inquiryEnabled': 'false'}),
        isTrue,
      );
      expect(ListingInquiry.isEnabled(const {'inquiryEnabled': 0}), isTrue);
    });

    test('세 도메인이 같은 필드 이름으로 저장한다', () {
      expect(ListingInquiry.field, 'inquiryEnabled');
      expect(ListingInquiry.guideField, 'inquiryGuide');
      // 켜고 끄는 값과 안내문은 **항상 함께** 나간다 — 한쪽만 쓰면 다음 저장에
      // 서로 다른 시점의 값이 섞인다.
      expect(ListingInquiry.toMap(true, '주차는 건물 뒤편에 해주세요'), {
        'inquiryEnabled': true,
        'inquiryGuide': '주차는 건물 뒤편에 해주세요',
      });
    });

    // 껐을 때 안내문을 남겨 두면, 나중에 다시 켰을 때 예전 안내가 아무 예고
    // 없이 되살아난다. 그래서 OFF는 안내문을 **빈 문자열로 지운다**.
    test('문의를 끄면 안내문도 함께 지워진다', () {
      expect(ListingInquiry.toMap(false, '아직 남아 있는 안내'), {
        'inquiryEnabled': false,
        'inquiryGuide': '',
      });
      expect(ListingInquiry.toMap(false), {
        'inquiryEnabled': false,
        'inquiryGuide': '',
      });
    });

    test('안내문은 앞뒤 공백을 털고 상한에서 자른다', () {
      expect(
        ListingInquiry.toMap(true, '  띄어쓰기  ')[ListingInquiry.guideField],
        '띄어쓰기',
      );
      final long = 'ㄱ' * (ListingInquiry.maxGuideLength + 50);
      expect(
        (ListingInquiry.toMap(true, long)[ListingInquiry.guideField] as String)
            .length,
        ListingInquiry.maxGuideLength,
      );
      // 읽는 쪽도 같은 상한을 쓴다 — 다른 경로로 들어온 긴 값에도 화면이
      // 무너지지 않아야 한다.
      expect(
        ListingInquiry.guideOf({ListingInquiry.guideField: long}).length,
        ListingInquiry.maxGuideLength,
      );
    });

    test('문의 방은 예약 방과 같은 relatedType을 쓴다 — 대화가 갈라지지 않게', () {
      // 플레이스(events)와 장소대여(places)는 컬렉션이 다르지만 채팅
      // relatedType은 둘 다 'place'다(기존 예약·이용권 채팅과 같은 값).
      expect(InquiryTarget.party.relatedType, 'party');
      expect(InquiryTarget.place.relatedType, 'place');
      expect(InquiryTarget.rental.relatedType, 'place');
      // 원본 컬렉션은 서로 다르다. 앱이 이 값을 서버로 보내지는 않지만
      // (컬렉션은 서버가 relatedType으로 정한다), 두 표가 어긋나면 안 된다 —
      // functions/chatRooms.js의 LISTING_COLLECTIONS와 같은 짝이다.
      expect(InquiryTarget.party.collection, 'parties');
      expect(InquiryTarget.place.collection, 'events');
      expect(InquiryTarget.rental.collection, 'places');
    });

    test('inquiryEnabled는 외부 링크 권한을 건드리지 않는다', () {
      // 향후 월정액으로 열릴 externalLinkEnabled와 **완전히 별개**여야 한다.
      // 문의를 껐다고 링크 권한이 생기는 구조가 되면 이 저장 맵에 링크 관련
      // 필드가 섞여 들어올 텐데, 그 순간 이 테스트가 깨진다.
      //
      // 여기서 보는 것은 "키가 몇 개냐"가 아니라 **문의에 속한 두 키 말고는
      // 아무것도 나가지 않는다**는 것이다(안내문 기능이 붙으면서 키가 하나
      // 늘었듯, 문의 자신의 필드는 앞으로도 늘 수 있다).
      for (final map in [
        ListingInquiry.toMap(false),
        ListingInquiry.toMap(true, '안내문'),
      ]) {
        expect(map.keys.toSet(), {
          ListingInquiry.field,
          ListingInquiry.guideField,
        });
        for (final key in map.keys) {
          expect(
            key.toLowerCase(),
            isNot(contains('link')),
            reason: '링크 권한 필드가 문의 저장 맵에 섞여 들어왔다: $key',
          );
        }
      }
    });
  });

  group('호스트 설정 카드', () {
    Future<void> pumpSection(
      WidgetTester tester, {
      required bool enabled,
      required ValueChanged<bool> onChanged,
    }) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GuestInquirySection(
                enabled: enabled,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('두 안내가 함께 보인다 — 권장 문구와 설명 문구', (tester) async {
      await pumpSection(tester, enabled: true, onChanged: (_) {});

      expect(find.text('게스트 문의 받기'), findsOneWidget);
      expect(find.text('문의를 열어두면 더 많은 게스트와 연결될 수 있어요'), findsOneWidget);
      expect(find.text('문의부터 신청까지 파티츄에서 한 번에'), findsOneWidget);
    });

    testWidgets('보장할 수 없는 표현은 쓰지 않는다', (tester) async {
      await pumpSection(tester, enabled: true, onChanged: (_) {});

      // '신청률이 올라갑니다'·'노출이 증가합니다' 같은 말은 사실상 약속이 된다.
      // 문구를 고칠 때 이 선을 넘지 않도록 붙잡아 두는 테스트다.
      for (final banned in ['신청률', '노출이 증가', '올라갑니다', '보장']) {
        expect(
          find.textContaining(banned),
          findsNothing,
          reason: '보장할 수 없는 표현이 들어갔다: $banned',
        );
      }
    });

    testWidgets('켜고 끌 수 있고, 꺼지면 ON 권장과 결과 안내가 붙는다', (tester) async {
      var value = true;
      await pumpSection(tester, enabled: value, onChanged: (v) => value = v);

      // 켜져 있을 때는 권장 배지를 띄우지 않는다 — 이미 켠 호스트에게는 잔소리다.
      expect(find.text('ON 권장'), findsNothing);

      await tester.tap(find.byType(Switch));
      expect(value, isFalse, reason: '스위치가 호출부로 값을 돌려줘야 한다');

      // 꺼진 상태로 다시 그리면 권장 배지와 "무슨 일이 벌어지는지"가 함께 뜬다.
      await pumpSection(tester, enabled: false, onChanged: (_) {});
      expect(find.text('ON 권장'), findsOneWidget);
      expect(find.textContaining('문의하기 버튼이 나오지 않고'), findsOneWidget);
      expect(find.textContaining('이미 주고받은 문의 대화는 그대로'), findsOneWidget);
    });
  });

  group('상세 페이지의 문의하기', () {
    Future<void> pumpButton(
      WidgetTester tester, {
      required bool enabled,
      InquiryTarget target = InquiryTarget.party,
      String hostId = 'host1',
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GuestInquiryButton(
              enabled: enabled,
              target: target,
              listingId: 'p1',
              hostId: hostId,
              hostName: '호스트',
              listingTitle: '테스트 파티',
            ),
          ),
        ),
      );
    }

    testWidgets('ON이면 문의하기 버튼이 뜬다', (tester) async {
      await pumpButton(tester, enabled: true);

      expect(find.text('문의하기'), findsOneWidget);
      expect(find.textContaining('운영하지 않는'), findsNothing);
    });

    // 예전에는 OFF일 때 "호스트가 문의 채팅을 운영하지 않는 파티입니다" 안내
    // 박스를 대신 띄웠다. 지금은 **자리를 통째로 비운다** — 하단 CTA에서 이
    // 칸이 비어야 신청·예약 버튼이 전체 폭을 쓴다(GuestInquiryButton 주석).
    // 게스트 입장에서 "문의를 안 받는다"는 사실은 버튼이 없는 것으로 이미
    // 드러나고, 안내 박스는 눌 것도 없는 자리를 한 칸 차지할 뿐이었다.
    testWidgets('OFF면 자리를 통째로 비운다 — 안내 박스를 대신 두지 않는다', (tester) async {
      await pumpButton(tester, enabled: false);

      expect(find.text('문의하기'), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.textContaining('운영하지 않는'), findsNothing);
      // 높이 0 — 하단 CTA가 이 칸을 남겨 두지 않는다.
      expect(tester.getSize(find.byType(GuestInquiryButton)).height, 0);
    });

    testWidgets('세 대상 모두 OFF면 아무것도 그리지 않는다', (tester) async {
      for (final target in InquiryTarget.values) {
        await pumpButton(tester, enabled: false, target: target);
        expect(
          tester.getSize(find.byType(GuestInquiryButton)).height,
          0,
          reason: '$target에서 OFF인데 자리가 남았다',
        );
      }
    });

    // 자리를 비울지 말지는 호출부가 **버튼을 만들기 전에** 알아야 한다 —
    // 세 상세 화면이 이 함수로 미리 갈라 주 CTA 폭을 정한다. 위젯만 고치고
    // 이 판정이 어긋나면, 버튼은 안 보이는데 빈 칸만 남는다.
    test('shouldShow가 호출부의 판정과 같은 답을 준다', () {
      expect(
        GuestInquiryButton.shouldShow(enabled: false, hostId: 'host1'),
        isFalse,
      );
      expect(
        GuestInquiryButton.shouldShow(enabled: true, hostId: 'host1'),
        isTrue,
      );
    });

    // 내 게시글에는 문의 버튼을 두지 않는다 — 자기 자신과의 채팅방이 생긴다.
    testWidgets('내 게시글에는 ON이어도 그리지 않는다', (tester) async {
      UserSession.userId = 'host1';
      addTearDown(() => UserSession.userId = '');

      expect(
        GuestInquiryButton.shouldShow(enabled: true, hostId: 'host1'),
        isFalse,
      );
      await pumpButton(tester, enabled: true);
      expect(find.text('문의하기'), findsNothing);
      expect(tester.getSize(find.byType(GuestInquiryButton)).height, 0);
    });

    // 호스트를 모르는 게시글에서 눌렀을 때 — 예전에는 여기서 **말없이
    // 돌아가서**, 사용자에게는 눌러도 아무 일도 안 일어나는 버튼이 됐다.
    // 서버도 이 경우 방을 열지 못하므로(createChatRoom failed-precondition),
    // 왜 안 되는지는 화면에서 읽혀야 한다.
    testWidgets('호스트를 모르면 조용히 넘어가지 않고 이유를 알린다', (tester) async {
      UserSession.userId = 'guest1';
      addTearDown(() => UserSession.userId = '');

      await pumpButton(tester, enabled: true, hostId: '');
      await tester.tap(find.text('문의하기'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('호스트 정보를 찾을 수 없어'), findsOneWidget);
    });
  });

  // 무엇이 실패했든 "잠시 후 다시 시도해주세요" 한 줄이던 시절, 매장 이벤트
  // 문의는 서버가 invalid-argument로 또박또박 거절하고 있었는데도 화면에서는
  // 원인을 알 수 없었다(서버 로그를 뒤져야 나왔다).
  group('실패 문구 — 원인을 삼키지 않는다', () {
    test('서버가 사람 말로 돌려준 이유는 그대로 보여준다', () {
      expect(
        GuestInquiryButton.failureMessageFor(
          code: 'failed-precondition',
          message: '호스트가 문의 채팅을 운영하지 않아요.',
        ),
        '호스트가 문의 채팅을 운영하지 않아요.',
      );
      expect(
        GuestInquiryButton.failureMessageFor(
          code: 'not-found',
          message: '대상을 찾을 수 없어요.',
        ),
        '대상을 찾을 수 없어요.',
      );
    });

    test('그 밖의 실패는 재시도 안내에 오류 코드를 붙인다', () {
      // 매장 이벤트 문의가 막혀 있던 바로 그 코드다 — 서버 표에 relatedType이
      // 없으면 createChatRoom이 이걸 돌려준다.
      expect(
        GuestInquiryButton.failureMessageFor(
          code: 'invalid-argument',
          message: 'relatedType이 올바르지 않습니다.',
        ),
        contains('(invalid-argument)'),
      );
      expect(
        GuestInquiryButton.failureMessageFor(
          code: 'internal',
          message: null,
        ),
        contains('(internal)'),
      );
    });

    test('콜러블 예외가 아니면 코드 없이 재시도만 안내한다', () {
      final text = GuestInquiryButton.failureMessageFor(
        code: null,
        message: null,
      );
      expect(text, isNot(contains('(')));
      expect(text, contains('다시 시도'));
    });
  });
  // 눌렀는데 화면이 조용하면, 서버가 제대로 일하고 있어도 사용자에게는
  // **고장 난 버튼**이다. 매장 이벤트 문의가 그랬다 — 운영 로그에서 방은
  // 첫 탭에 이미 만들어졌는데(createChatRoom 200), 뒤이은 자동 안내 예약이
  // 콜드 스타트로 11.4초 걸리는 동안 아무 표시가 없어 같은 탭이 6초에 열 번
  // 찍혀 있었다.
  group('누른 뒤 화면이 조용하지 않다', () {
    testWidgets('누르는 즉시 진행 표시를 띄우고, 끝나면 걷는다', (tester) async {
      UserSession.userId = 'guest1';
      addTearDown(() => UserSession.userId = '');

      // 화면에 무엇이 오갔는지 — 진행 표시는 네트워크가 답하기 전에 올라가고
      // 답한 뒤 내려가므로, 테스트가 프레임을 그릴 틈 없이 지나갈 수 있다.
      // 그래서 "보였는가" 대신 **올렸다가 내렸는가**를 본다.
      final events = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [_RouteLog(events)],
          home: const Scaffold(
            body: GuestInquiryButton(
              enabled: true,
              target: InquiryTarget.event,
              listingId: 'EV1',
              hostId: 'host1',
              hostName: '호스트',
              listingTitle: '생일 이벤트',
            ),
          ),
        ),
      );
      await tester.tap(find.text('문의하기'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // 첫 push가 진행 표시고, 그 뒤 remove로 걷힌다. 아무것도 올리지 않고
      // 조용히 기다리던 예전 모습이면 events는 실패 안내 하나뿐이다.
      expect(events.first, 'push', reason: '누른 직후 아무것도 올리지 않았다');
      expect(events.contains('remove'), isTrue, reason: '진행 표시가 남았다');
      tester.takeException();
    });

    testWidgets('네트워크가 실패하면 막을 걷고 이유를 알린다', (tester) async {
      UserSession.userId = 'guest1';
      addTearDown(() => UserSession.userId = '');

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GuestInquiryButton(
              enabled: true,
              target: InquiryTarget.event,
              listingId: 'EV1',
              hostId: 'host1',
              hostName: '호스트',
              listingTitle: '생일 이벤트',
            ),
          ),
        ),
      );
      await tester.tap(find.text('문의하기'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // 테스트 환경에는 Firebase가 없어 방 열기가 실패한다 — 그때 진행 표시가
      // 남아 화면을 덮고 있으면 그것이야말로 "먹통"이다.
      expect(find.text('채팅방을 여는 중…'), findsNothing);
      expect(find.textContaining('다시 시도'), findsOneWidget);
      tester.takeException();
    });
  });

  // 채팅방 진입은 **방이 열렸는지**에만 걸린다. 자동 안내 예약(인사말 준비)은
  // 곁가지인데, 예전에는 그 응답을 기다린 뒤에야 화면을 넘겨서 콜드 스타트
  // 11.4초가 그대로 사용자 대기가 됐다.
  group('채팅방 진입은 자동 안내 예약을 기다리지 않는다', () {
    final source = File(
      'lib/widgets/guest_inquiry_button.dart',
    ).readAsStringSync();

    test('예약 호출은 값을 돌려주지 않는다 — 기다릴 수가 없다', () {
      // void면 await할 대상 자체가 없다. Future로 되돌아가면 여기서 걸린다.
      expect(
        RegExp(r'void\s+_scheduleAutoMessageInBackground').hasMatch(source),
        isTrue,
        reason: '예약을 기다릴 수 있는 모양으로 되돌아갔다',
      );
      expect(source, contains('unawaited('));
      expect(source, isNot(contains('await _scheduleAutoMessage')));
      expect(source, isNot(contains('await ChatService.scheduleAutoMessage')));
    });

    test('방이 열린 뒤 예약을 거치지 않고 채팅방으로 간다', () {
      final room = source.indexOf('ChatService.getOrCreateRoom(');
      final schedule = source.indexOf('_scheduleAutoMessageInBackground(');
      final push = source.indexOf('ChatRoomScreen(');
      expect(room, greaterThan(0));
      expect(schedule, greaterThan(room));
      expect(push, greaterThan(schedule));
      // 예약과 입장 사이에 기다림이 끼어 있지 않다.
      expect(
        source.substring(schedule, push),
        isNot(contains('await ChatService.scheduleAutoMessage')),
      );
    });
  });

  // 예약할 안내가 아예 없는 종류에는 호출조차 하지 않는다 — 왕복 한 번이
  // 통째로 헛걸음이고, 그 헛걸음이 사용자를 기다리게 하던 원인이었다.
  group('자동 안내가 없는 종류는 부르지 않는다', () {
    test('클라이언트 표가 서버 SUPPORTED_TYPES와 같다', () {
      final server = File(
        '../functions/chatAutoMessages.js',
      ).readAsStringSync();
      final match = RegExp(
        r'const SUPPORTED_TYPES = new Set\(\[([^\]]*)\]\)',
      ).firstMatch(server);
      expect(match, isNotNull, reason: '서버의 SUPPORTED_TYPES를 찾지 못했다');
      final serverTypes = match!
          .group(1)!
          .split(',')
          .map((s) => s.trim().replaceAll(RegExp("['\"]"), ''))
          .where((s) => s.isNotEmpty)
          .toSet();

      // 어긋나면 둘 중 하나다 — 헛호출을 다시 하거나, 붙어야 할 안내를 빼먹거나.
      expect(kAutoMessageRelatedTypes, serverTypes);
    });

    test('매장 이벤트·파티 문의는 예약 대상이 아니다', () {
      expect(
        kAutoMessageRelatedTypes.contains(InquiryTarget.event.relatedType),
        isFalse,
      );
      expect(
        kAutoMessageRelatedTypes.contains(InquiryTarget.party.relatedType),
        isFalse,
      );
      // 플레이스·장소대여는 표 안이라 그대로 부른다(이용일이 없으면 서버가
      // 예약하지 않을 뿐이고, 그 판단은 서버 몫이다).
      expect(
        kAutoMessageRelatedTypes.contains(InquiryTarget.place.relatedType),
        isTrue,
      );
      expect(
        kAutoMessageRelatedTypes.contains(InquiryTarget.rental.relatedType),
        isTrue,
      );
    });
  });
}

/// 라우트가 올라가고 내려간 순서만 적는 관찰자.
class _RouteLog extends NavigatorObserver {
  _RouteLog(this.events);

  final List<String> events;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previous) =>
      events.add('push');

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previous) =>
      events.add('remove');

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previous) =>
      events.add('pop');
}

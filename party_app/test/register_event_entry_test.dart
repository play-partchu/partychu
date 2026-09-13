// 등록 화면의 "🎪 매장 이벤트" — 카드 자리부터 진입 조건까지.
//
// 이벤트는 독립 콘텐츠가 아니라 **내 플레이스가 여는 행사 한 건**이다
// (`placePromotions` 문서가 원본 플레이스에 붙는다 — place_event_entry.dart
// 상단 주석). 그래서 이 화면의 다른 카드와 달리 **전제 조건**이 있고, 그
// 조건을 어느 입구에서 확인하느냐가 이 파일이 지키는 것이다.
//
// 지키는 불변식:
//   · 등록 메인에는 '🎉 이벤트 / 파티' **한 칸**만 있다 — 🎪 매장 이벤트와
//     🎉 파티는 그 칸을 눌러 들어간 선택 화면
//     ([RegisterOfferingChoiceScreen])에서 나란히 고른다(둘 사이에 다른 등록
//     유형이 끼지 않는다).
//   · 제목 옆 '?'는 도움말만 연다 — 카드의 등록 이동이 함께 일어나지 않는다.
//   · 내 플레이스가 0개면 **폼으로 보내지 않는다**. 폼은 원본 플레이스가
//     있어야만 저장되므로, 들여보내면 다 쓰고 나서야 막힌다.
//   · '플레이스 등록하기'는 **통합 진입점**([PlaceEntryRegisterScreen])으로
//     간다 — 옛 단독 등록 화면을 직접 열면 공간 유형 선택이 통째로 사라진다.
//   · 남의 플레이스는 선택지에 없다.
//   · 등록 화면과 마이 > 파티츄 호스트가 **같은 함수** 하나를 탄다.
//
// Firestore는 건드리지 않는다 — 내 플레이스 조회는 [PlaceEventEntry]의 테스트
// 주입점으로 갈아끼우고(이 프로젝트에는 Firestore 페이크가 없다), 등록 화면
// 상단의 사업자 인증 안내는 로그아웃 상태면 아무것도 그리지 않는다
// (register_type_help_copy_test.dart와 같은 전제).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:party_app/screens/place_entry_register_screen.dart';
import 'package:party_app/screens/place_event_edit_screen.dart';
import 'package:party_app/screens/register_offering_choice_screen.dart';
import 'package:party_app/screens/register_type_screen.dart';
import 'package:party_app/models/business_verification.dart';
import 'package:party_app/models/host_offering.dart';
import 'package:party_app/services/place_create_eligibility.dart';
import 'package:party_app/services/place_event_entry.dart';
import 'package:party_app/utils/user_session.dart';

const String _me = 'host-me';
const String _other = 'host-other';

EventPlaceTarget _venue(
  String id,
  String name, {
  String hostId = _me,
  String address = '서울 마포구 와우산로 1',
}) => EventPlaceTarget(
  placeId: id,
  placeCollection: 'events',
  hostId: hostId,
  placeName: name,
  address: address,
);

EventPlaceTarget _stay(String id, String name, {String hostId = _me}) =>
    EventPlaceTarget(
      placeId: id,
      placeCollection: 'places',
      hostId: hostId,
      placeName: name,
      address: '서울 강남구 테헤란로 2',
    );

void main() {
  setUp(() {
    dotenv.testLoad(fileInput: '');
    SharedPreferences.setMockInitialValues({});
    // 등록 화면 상단의 사업자 인증 안내가 Firestore를 건드리지 않게 비워 둔다.
    UserSession.userId = '';
    // 이 파일이 지키는 것은 **이벤트 등록 진입**이다. 안내 시트의 '플레이스
    // 등록하기'가 지나는 사업자 관문([PlaceCreateEligibility])은 그쪽 테스트
    // (place_create_eligibility_test.dart)가 따로 지키므로, 여기서는 인증을
    // 마친 계정으로 고정해 진입 흐름만 본다.
    // ⚠️ 진위(status)만으로는 관문을 통과하지 못한다 — 권한(authorization)까지
    //    있어야 한다. 여기서 status만 주면 이 파일 전체가 '사업자 인증 필요'
    //    시트에 막혀 정작 보려던 진입 흐름을 못 본다.
    PlaceCreateEligibility.debugSetSource(
      () async => const BusinessVerification(
        status: BusinessVerificationStatus.verified,
        authorization: BusinessAuthorization.self,
      ),
    );
  });

  tearDown(() {
    PlaceEventEntry.debugResetSource();
    PlaceCreateEligibility.debugResetSource();
    UserSession.userId = '';
  });

  /// 내 플레이스 조회를 [places]로 고정한다. uid도 함께 주입해 FirebaseAuth를
  /// 건드리지 않는다.
  void usePlaces(List<EventPlaceTarget> places) {
    PlaceEventEntry.debugSetSource(uid: _me, loader: (_) async => places);
  }

  Future<void> pumpRegisterType(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: RegisterTypeScreen()));
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// 등록 메인의 '🎉 이벤트 / 파티' 칸을 눌러 **선택 화면**까지 들어간다 —
  /// 🎪/🎉 두 카드가 사는 곳은 이제 여기다.
  Future<void> pumpOfferingChoice(WidgetTester tester) async {
    await pumpRegisterType(tester);
    await tester.tap(find.text('이벤트 / 파티'));
    await tester.pumpAndSettle();
    expect(
      find.byType(RegisterOfferingChoiceScreen),
      findsOneWidget,
      reason: '등록 메인의 이벤트/파티 칸이 선택 화면을 열지 않았다',
    );
  }

  /// 등록 흐름이 도는 동안에는 [WidgetTester.pumpAndSettle]을 쓸 수 없다 —
  /// 카드가 '확인 중...' 스피너를 흐름이 끝날 때까지 돌리기 때문에 영영
  /// 잠잠해지지 않는다(파티 등록 카드도 같은 동작이다). 그래서 시트 애니메이션
  /// 길이만큼 프레임을 손으로 진행시킨다.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// 카드 전체를 누른다 — 제목이 아니라 **설명 줄**을 누른다. 제목 옆에는
  /// '?'가 붙어 있어서, 제목을 겨냥하면 무엇을 눌렀는지가 흐려진다.
  Future<void> tapEventCard(WidgetTester tester) async {
    final desc = find.text(HostOffering.placeEvent.registerDescription);
    await tester.ensureVisible(desc);
    await tester.pump();
    await tester.tap(desc);
    await settle(tester);
  }

  /// '🎪 매장 이벤트' 카드 제목 옆의 '?'. AppBar와 다른 카드에도 같은 아이콘이
  /// 있으므로 **이 카드 제목 줄 안에 있는 것**만 골라 잡는다.
  Future<void> openEventHelp(WidgetTester tester) async {
    final help = find.descendant(
      of: find.widgetWithText(Row, HostOffering.placeEvent.label).last,
      matching: find.byIcon(Icons.question_mark_rounded),
    );
    expect(help, findsOneWidget, reason: '매장 이벤트 카드에 도움말 버튼이 없다');
    await tester.ensureVisible(help);
    await tester.pump();
    await tester.tap(help);
    await tester.pumpAndSettle();
  }

  group('등록 화면 — 매장 이벤트 카드', () {
    // 등록 메인에는 행사 입구가 **한 칸**이다. 🎪와 🎉를 큰 카드 두 장으로
    // 나란히 두면, 둘을 가르는 단 하나의 기준(모집 여부)이 플레이스·파티샵과
    // 같은 무게의 "다섯 중 고르기"로 읽힌다.
    testWidgets('메인에는 이벤트/파티 한 칸만 있고 유형은 여기서 고르지 않는다', (tester) async {
      await pumpRegisterType(tester);

      expect(find.text('이벤트 / 파티'), findsOneWidget);
      expect(find.text('매장 행사부터 참가자 모집 파티까지'), findsOneWidget);
      // 유형을 고르는 카드는 메인에 없다 — 다음 화면에 있다.
      expect(find.text(HostOffering.placeEvent.label), findsNothing);
      expect(find.text(HostOffering.party.label), findsNothing);
      // 나머지 등록 유형은 그대로다("플레이스+파티 등록"은 예전에 없어졌다 —
      // combo_register_removed_test.dart).
      for (final t in ['플레이스 등록', '파티샵 등록', '파티크루 글 등록']) {
        expect(find.text(t), findsOneWidget, reason: '"$t" 카드가 사라졌다');
      }
    });

    // 🎪 매장 이벤트와 🎉 파티는 **한 자리에서 고른다**([HostOfferingChoice]) —
    // 둘 사이에 다른 등록 유형이 끼면 "무엇을 만들까요?"라는 한 질문이 아니라
    // 서로 상관없는 카드 둘로 읽힌다.
    testWidgets('선택 화면에서 둘만 나란히 붙어 있다', (tester) async {
      await pumpOfferingChoice(tester);

      final eventY = tester
          .getTopLeft(find.text(HostOffering.placeEvent.label))
          .dy;
      final partyY = tester.getTopLeft(find.text(HostOffering.party.label)).dy;
      expect(eventY, isNot(partyY));

      // 다른 등록 유형은 이 화면에 아예 없다 — 사이에 낄 수가 없다.
      for (final other in ['플레이스 등록', '파티샵 등록', '파티크루 글 등록']) {
        expect(
          find.text(other),
          findsNothing,
          reason: '매장 이벤트와 파티 사이에 "$other"가 끼어 있다',
        );
      }
    });

    testWidgets('설명은 무엇을 올리는 자리인지 한 줄로 말한다', (tester) async {
      await pumpOfferingChoice(tester);
      expect(
        find.text(HostOffering.placeEvent.registerDescription),
        findsOneWidget,
      );
      // 무엇으로 고르는지(모집 여부)가 카드보다 먼저 읽힌다.
      expect(find.text(HostOffering.criterionHeadline), findsOneWidget);
      expect(find.text(HostOffering.placeEvent.criterion), findsOneWidget);
    });
  });

  group("이벤트 등록 '?' 도움말", () {
    testWidgets("'?' 탭이 등록 이동을 함께 일으키지 않는다", (tester) async {
      // 플레이스가 없는 상태로 둔다 — 탭이 카드로 새어 나갔다면 "플레이스를
      // 먼저 등록해주세요" 안내가 함께 떠서 바로 드러난다.
      usePlaces(const []);
      await pumpOfferingChoice(tester);
      await openEventHelp(tester);

      expect(
        find.text(HostOffering.placeEvent.display),
        findsWidgets,
        reason: '도움말이 열리지 않았다',
      );
      expect(
        find.text('플레이스를 먼저 등록해주세요'),
        findsNothing,
        reason: "'?' 탭이 카드로 새어 나가 등록 흐름이 함께 시작됐다",
      );
      expect(find.byType(PlaceEventEditScreen), findsNothing);
      expect(find.byType(PlaceEntryRegisterScreen), findsNothing);
    });

    testWidgets('무엇을 등록하는지와 무엇과 연결되는지를 말한다', (tester) async {
      await pumpOfferingChoice(tester);
      await openEventHelp(tester);

      expect(
        find.textContaining('주류 할인·1+1·생일 이벤트'),
        findsWidgets,
        reason: '어떤 행사를 올릴 수 있는지가 없다',
      );
      // 갈리는 기준(누가 여는가)도 도움말에서 같은 문장으로 말한다.
      // (선택 카드 위에도 같은 문장이 있으므로 findsWidgets다.)
      expect(find.textContaining(HostOffering.criterionHeadline), findsWidgets);
      expect(find.textContaining('참가자를 모집하고 신청을 받는다면'), findsOneWidget);
      expect(find.text('매장 이벤트는 등록된 플레이스와 연결해서 등록합니다.'), findsOneWidget);
      expect(find.textContaining('아직 플레이스가 없다면'), findsOneWidget);
      expect(
        find.text('플레이스를 먼저 등록해두면 이후 새로운 매장 이벤트를 추가하거나 기존 연결을 수정할 수 있어요.'),
        findsOneWidget,
      );
    });
  });

  group('진입 조건 — 플레이스가 0개', () {
    testWidgets('폼으로 보내지 않고 먼저 등록하라고 안내한다', (tester) async {
      usePlaces(const []);
      await pumpOfferingChoice(tester);
      await tapEventCard(tester);

      expect(find.text('플레이스를 먼저 등록해주세요'), findsOneWidget);
      expect(
        find.textContaining('매장 이벤트는 등록된 플레이스와 연결해서 등록할 수 있어요.'),
        findsOneWidget,
      );
      expect(find.text('플레이스 등록하기'), findsOneWidget);
      expect(find.text('나중에'), findsOneWidget);
      expect(
        find.byType(PlaceEventEditScreen),
        findsNothing,
        reason: '플레이스가 없는데 이벤트 폼이 열렸다 — 다 쓰고 나서야 막힌다',
      );
    });

    testWidgets("'플레이스 등록하기'는 통합 진입점으로 보낸다", (tester) async {
      usePlaces(const []);
      await pumpOfferingChoice(tester);
      await tapEventCard(tester);

      await tester.tap(find.text('플레이스 등록하기'));
      await settle(tester);

      expect(
        find.byType(PlaceEntryRegisterScreen),
        findsOneWidget,
        reason: '옛 단독 등록 화면을 직접 열면 공간 유형 선택이 사라진다',
      );
      // 안내 시트는 닫힌 채로 남아야 한다 — 등록을 마치고 돌아왔을 때
      // "먼저 등록해주세요"가 다시 덮고 있으면 안 된다.
      expect(find.text('플레이스를 먼저 등록해주세요'), findsNothing);
    });

    testWidgets("'나중에'는 아무 데도 보내지 않는다", (tester) async {
      usePlaces(const []);
      await pumpOfferingChoice(tester);
      await tapEventCard(tester);

      await tester.tap(find.text('나중에'));
      await settle(tester);

      expect(find.text('플레이스를 먼저 등록해주세요'), findsNothing);
      expect(find.byType(PlaceEntryRegisterScreen), findsNothing);
      expect(find.byType(PlaceEventEditScreen), findsNothing);
      // 고르던 자리에 그대로 남는다 — 등록 메인까지 튕겨 나가지 않는다.
      expect(find.byType(RegisterOfferingChoiceScreen), findsOneWidget);
    });
  });

  group('진입 조건 — 플레이스가 1개', () {
    testWidgets('이벤트 폼이 열리고, 어느 플레이스인지 폼에 보인다', (tester) async {
      usePlaces([_venue('E1', 'OO 혼술바')]);
      await pumpOfferingChoice(tester);
      await tapEventCard(tester);

      expect(find.byType(PlaceEventEditScreen), findsOneWidget);
      // 1개뿐이어도 몰래 붙이지 않는다 — 폼 머리말이 연결된 플레이스를 말한다.
      expect(find.text('OO 혼술바'), findsWidgets);
      expect(find.text('이 장소의 매장 이벤트'), findsOneWidget);
      // 고를 것이 하나뿐이면 굳이 묻지 않는다.
      expect(find.text('어느 플레이스에서 진행하나요?'), findsNothing);
    });
  });

  group('진입 조건 — 플레이스가 여러 개', () {
    testWidgets('어디서 진행하는지 먼저 묻고, 고른 플레이스로 폼이 열린다', (tester) async {
      usePlaces([_venue('E1', 'OO 혼술바'), _stay('P1', 'OO 라이브홀')]);
      await pumpOfferingChoice(tester);
      await tapEventCard(tester);

      expect(find.text('어느 플레이스에서 진행하나요?'), findsOneWidget);
      expect(find.text('OO 혼술바'), findsOneWidget);
      expect(find.text('OO 라이브홀'), findsOneWidget);
      expect(
        find.byType(PlaceEventEditScreen),
        findsNothing,
        reason: '고르기 전에 폼이 열렸다',
      );

      await tester.tap(find.text('OO 라이브홀'));
      await settle(tester);

      expect(find.byType(PlaceEventEditScreen), findsOneWidget);
      expect(find.text('OO 라이브홀'), findsWidgets);
      expect(find.text('OO 혼술바'), findsNothing);
    });

    testWidgets('남의 플레이스는 선택지에 없다', (tester) async {
      usePlaces([
        _venue('E1', 'OO 혼술바'),
        _stay('P1', 'OO 라이브홀'),
        _venue('E9', '남의 가게', hostId: _other),
      ]);
      await pumpOfferingChoice(tester);
      await tapEventCard(tester);

      expect(find.text('어느 플레이스에서 진행하나요?'), findsOneWidget);
      expect(
        find.text('남의 가게'),
        findsNothing,
        reason: '남의 플레이스가 선택지에 섞였다 — rules가 막기 전에 여기서 막혀야 한다',
      );
    });

    testWidgets('내 것이 하나뿐이면 남의 것을 세지 않고 그대로 진입한다', (tester) async {
      usePlaces([
        _venue('E1', 'OO 혼술바'),
        _venue('E9', '남의 가게', hostId: _other),
      ]);
      await pumpOfferingChoice(tester);
      await tapEventCard(tester);

      expect(find.text('어느 플레이스에서 진행하나요?'), findsNothing);
      expect(find.byType(PlaceEventEditScreen), findsOneWidget);
      expect(find.text('OO 혼술바'), findsWidgets);
    });

    testWidgets('내 것이 하나도 없으면 남의 것이 있어도 안내로 끝난다', (tester) async {
      usePlaces([_venue('E9', '남의 가게', hostId: _other)]);
      await pumpOfferingChoice(tester);
      await tapEventCard(tester);

      expect(find.text('플레이스를 먼저 등록해주세요'), findsOneWidget);
      expect(find.byType(PlaceEventEditScreen), findsNothing);
    });
  });

  group('내 플레이스 목록', () {
    test('로그인 전에는 조회 자체를 하지 않는다', () async {
      var called = false;
      PlaceEventEntry.debugSetSource(
        uid: '',
        loader: (_) async {
          called = true;
          return const [];
        },
      );

      expect(await PlaceEventEntry.myPlaces(), isEmpty);
      expect(called, isFalse);
    });

    test('hostId가 나인 것만, 이름순으로 준다', () async {
      usePlaces([
        _stay('P1', 'ㄴ 라이브홀'),
        _venue('E9', '남의 가게', hostId: _other),
        _venue('E1', 'ㄱ 혼술바'),
      ]);

      final mine = await PlaceEventEntry.myPlaces();
      expect(mine.map((p) => p.placeName).toList(), ['ㄱ 혼술바', 'ㄴ 라이브홀']);
    });

    test('연결 필드는 원본 문서의 것을 그대로 들고 간다', () {
      final target = EventPlaceTarget.fromDoc(
        id: 'E1',
        collection: 'events',
        data: const {
          'hostId': _me,
          'name': 'OO 혼술바',
          'roadAddress': '서울 마포구 와우산로 1',
        },
      );

      expect(target.placeId, 'E1');
      expect(target.placeCollection, 'events');
      expect(target.hostId, _me);
      expect(target.address, '서울 마포구 와우산로 1');
      // 강조색·이모지는 공간 유형 정본에서 온다 — 마이 > 파티츄 호스트의
      // 플레이스 카드가 쓰던 색과 같은 값이라 화면마다 얼굴이 달라지지 않는다.
      expect(target.accent, const Color(0xFFFF6FA0));
      expect(target.emoji, '🏪');
      expect(
        EventPlaceTarget.fromDoc(
          id: 'P1',
          collection: 'places',
          data: const {'hostId': _me, 'name': 'OO 파티룸'},
        ).accent,
        const Color(0xFF7C5CBF),
      );
    });

    test('이름이 비어 있어도 무엇인지 알 수 있게 종류 이름으로 채운다', () {
      expect(
        EventPlaceTarget.fromDoc(
          id: 'E1',
          collection: 'events',
          data: const {'hostId': _me},
        ).placeName,
        '플레이스',
      );
      expect(
        EventPlaceTarget.fromDoc(
          id: 'P1',
          collection: 'places',
          data: const {'hostId': _me},
        ).placeName,
        '공간대여',
      );
    });
  });

  // ── 입구가 하나임을 구조로 지킨다 ────────────────────────────────────────
  // 등록 화면과 마이 > 파티츄 호스트가 각자 이벤트 화면을 열면 한쪽만 고쳐져
  // 두 입구가 다르게 동작한다(플레이스 확인을 한쪽만 하는 식으로). 그래서
  // 이벤트 화면을 **만드는** 자리를 파일 단위로 묶어 둔다.
  group('전수 가드 — 이벤트 화면을 여는 길은 하나뿐', () {
    /// 이벤트 화면을 직접 생성해도 되는 파일: 선언 두 곳과 공용 진입점.
    const allowed = {
      'place_event_edit_screen.dart',
      'place_event_manage_screen.dart',
      'place_event_entry.dart',
    };

    List<File> libFiles() => Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    test('탐지 방식이 살아 있다', () {
      final hits = libFiles().where(
        (f) => f.readAsStringSync().contains('PlaceEventEditScreen('),
      );
      expect(hits, isNotEmpty, reason: '탐지 방식이 깨졌다 — 아래 검사가 무의미해진다');
    });

    test('공용 진입점 밖에서는 이벤트 화면을 직접 만들지 않는다', () {
      final offenders = <String>[];
      for (final f in libFiles()) {
        final name = f.uri.pathSegments.last;
        if (allowed.contains(name)) continue;
        final src = f.readAsStringSync();
        if (src.contains('PlaceEventEditScreen(') ||
            src.contains('PlaceEventManageScreen(')) {
          offenders.add(f.path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            '이벤트 화면을 직접 여는 곳이 있다. 화면마다 진입 흐름을 따로 적지 말고\n'
            'PlaceEventEntry.startRegister / PlaceEventEntry.openManage를 쓰자:\n'
            '${offenders.join('\n')}',
      );
    });

    test('마이 > 파티츄 호스트도 같은 공용 진입점을 쓴다', () {
      final src = File(
        'lib/screens/my_host_hub_screen.dart',
      ).readAsStringSync();
      expect(
        src.contains('PlaceEventEntry.startRegister('),
        isTrue,
        reason:
            '"이 파티를 기반으로 이벤트 등록"과 이벤트 탭의 등록이 공용 진입점을 쓰지 않는다',
      );
      // **관리**는 이제 상단 🎪 이벤트 탭에서 목록으로 한다 — 화면을 여는 대신
      // 관리 화면과 같은 목록 위젯([PlaceEventManageList])을 그 자리에 편다.
      // 그래서 이 파일이 openManage를 요구하지 않는다. 지켜야 할 것은 그대로다:
      // 이벤트 화면을 **직접 만들지 않는 것**(위 전수 가드)과, 목록을 두 벌로
      // 만들지 않는 것.
      expect(
        src.contains('PlaceEventManageList('),
        isTrue,
        reason: '이벤트 탭이 관리 화면과 같은 목록 위젯을 쓰지 않는다',
      );
    });

    test('등록 화면도 같은 공용 진입점을 쓴다', () {
      // 등록 메인의 '🎉 이벤트 / 파티' 칸이 여는 선택 화면이 진입을 들고 있다.
      final src = File(
        'lib/screens/register_offering_choice_screen.dart',
      ).readAsStringSync();
      expect(src.contains('PlaceEventEntry.startRegister('), isTrue);
    });
  });
}

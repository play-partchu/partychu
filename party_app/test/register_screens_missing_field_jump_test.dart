// 등록 화면 **전부**가 같은 방식으로 "누락 항목 → 그 입력칸"까지 데려가는지.
//
// 고친 사고: 공용 구조([RegisterFieldCheck] / [RegisterValidation.goTo])는
// 있었지만 그것을 실제로 연결한 화면은 플레이스+파티 하나뿐이었다. 나머지
// 화면은 컨트롤러를 넘기지 않아, 화면 밖이라 아직 만들어지지 않은 섹션
// (ListView는 보이는 만큼만 만든다)을 누르면 넘길 context가 없어 **아무 일도
// 일어나지 않았다**. 접힌 카드 안에 있는 항목도 마찬가지였다.
//
// 그래서 화면마다 **화면 아래쪽에 있는 필수 항목** 하나를 골라, 배너의 그 줄을
// 눌렀을 때 (1) 위젯이 실제로 만들어지고 (2) 뷰포트 안으로 들어오는지를
// 좌표로 확인한다. 어느 앵커로 갔는지는 공용 강조 요청
// ([RegisterValidation.highlightRequest])이 알려주므로 화면 내부를 들여다볼
// 필요가 없다 — 화면이 늘어도 이 검사는 그대로 쓸 수 있다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:party_app/models/place_area.dart';
import 'package:party_app/screens/crew_register_screen.dart';
import 'package:party_app/screens/event_register_screen.dart';
import 'package:party_app/screens/party_market_register_screen.dart';
import 'package:party_app/screens/party_register_screen.dart';
import 'package:party_app/screens/party_shop_product_register_screen.dart';
import 'package:party_app/screens/place_register_screen.dart';
import 'package:party_app/utils/register_validation.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/party_form/register_missing_fields_banner.dart';

const Size _screen = Size(390, 844);

// Firebase는 초기화하지 않는다 — 이 검사는 **입력 검증과 화면 이동**만 본다.
// 등록 화면들도 검증을 통과하기 전에는 Firebase를 만지지 않으므로(만지면
// 그 자체가 버그다) 앱 없이 그대로 돌아간다. 검증을 통과한 뒤의 저장 경로는
// 여기서 다루지 않는다.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UserSession.userId = 'test-user';
    RegisterValidation.clearHighlight();
  });
  tearDown(() {
    UserSession.userId = '';
    RegisterValidation.clearHighlight();
  });

  // ── 도구 ────────────────────────────────────────────────────────────
  //
  // pumpAndSettle을 쓰지 않는다 — 오류가 난 요약 행은 경고등처럼 **계속**
  // 깜빡이므로(SectionSummaryRow.blinkOnError) 영영 멈추지 않는다. 대신
  // 프레임을 정해진 수만큼 흘려보낸다(스윕 + 400ms 스크롤 애니메이션을 덮는다).
  Future<void> settle(WidgetTester tester, {int frames = 90}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = _screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: screen));
    await settle(tester, frames: 20);
  }

  /// 지금 [target]을 **실제로 누를 수 있는지**.
  ///
  /// "찾았다"만으로는 모자란다 — 스크롤 목록의 맨 위는 AppBar 뒤에, 맨 아래는
  /// 스낵바 뒤에 깔려서, 그 자리에서 누르면 탭이 엉뚱한 위젯에 먹힌다
  /// ("이동 요청이 서지 않았다"로만 보이던 실패가 이것이었다). 그래서 히트
  /// 테스트까지 통과하는지를 본다.
  bool reachable(WidgetTester tester, Finder target) {
    try {
      return tester.any(target.hitTestable());
    } catch (_) {
      // 아직 레이아웃 전이면 좌표 자체가 없다 — 누를 수 없다.
      return false;
    }
  }

  /// [target]이 누를 수 있는 자리에 올 때까지 본문을 끌어 올린다/내린다.
  /// (tester.scrollUntilVisible은 내부에서 pumpAndSettle을 불러 쓸 수 없다.)
  Future<void> dragUntilVisible(
    WidgetTester tester,
    Finder target, {
    double step = -260,
    int maxDrags = 40,
  }) async {
    // 먼저 준 방향으로, 못 찾으면 반대 방향으로 훑는다.
    for (final dy in [step, -step]) {
      for (var i = 0; i < maxDrags; i++) {
        if (reachable(tester, target)) {
          // 관성이 남아 있으면 탭이 "스크롤 멈춤"으로 먹힌다 — 먼저 재운다.
          await settle(tester, frames: 20);
          if (reachable(tester, target)) return;
          continue;
        }
        // 본문 한가운데를 끈다 — Scrollable을 finder로 고르면 입력칸 안의
        // 스크롤(EditableText)이나 가로 목록이 먼저 잡힐 수 있다.
        await tester.dragFrom(const Offset(195, 420), Offset(0, dy));
        await tester.pump(const Duration(milliseconds: 30));
      }
    }
  }

  /// 제출 버튼을 눌러 검증을 돌린다 — 여기서 배너가 만들어진다.
  Future<void> submit(WidgetTester tester, String label) async {
    // 같은 문구가 AppBar 제목에도 있을 수 있다 — 버튼 안쪽으로 좁힌다.
    final button = find.descendant(
      of: find.byType(ElevatedButton),
      matching: find.text(label),
    );
    await dragUntilVisible(tester, button);
    expect(reachable(tester, button), isTrue, reason: '제출 버튼($label)을 찾지 못했다');
    await tester.tap(button.hitTestable());
    await settle(tester);
  }

  /// 배너의 한 줄을 눌러 그 입력칸으로 간다. 같은 문구가 입력칸 아래 빨간
  /// 안내로도 떠 있을 수 있어, **배너 안쪽**으로 범위를 좁혀 찾는다.
  Future<void> tapBannerLine(WidgetTester tester, String message) async {
    final line = find.descendant(
      of: find.byType(RegisterMissingFieldsBanner),
      matching: find.text(message),
    );
    // 제출 직후 화면은 첫 누락 항목으로 내려가 있다 — 배너는 폼 맨 위다.
    await dragUntilVisible(tester, line, step: 260);
    expect(reachable(tester, line), isTrue, reason: '배너에 "$message" 줄이 없다');
    RegisterValidation.clearHighlight();
    await tester.tap(line.hitTestable());
    await settle(tester);
  }

  /// 이동이 **실제로** 끝났는지 — 앵커 위젯이 만들어졌고 화면 안에 있다.
  void expectArrived(WidgetTester tester, {required String what}) {
    final request = RegisterValidation.highlightRequest.value;
    expect(request, isNotNull, reason: '$what: 이동 요청 자체가 서지 않았다');
    final key = request!.anchorKey;
    expect(key, isA<GlobalKey>(), reason: '$what: 앵커가 GlobalKey가 아니다');
    expect(
      (key as GlobalKey).currentContext,
      isNotNull,
      reason: '$what: 화면 밖이라 위젯이 만들어지지 않았다(탭이 무시된 것과 같다)',
    );
    final rect = tester.getRect(find.byKey(key));
    expect(rect.top, greaterThanOrEqualTo(-1.0), reason: '$what: 화면 위로 벗어났다');
    expect(rect.top, lessThan(_screen.height), reason: '$what: 화면 아래로 벗어났다');
  }

  /// 강조가 저절로 꺼질 때까지 흘려보낸다 — 남겨 두면 뒷정리에서 걸린다.
  Future<void> drainHighlight(WidgetTester tester) async {
    await tester.pump(RegisterValidation.highlightDuration);
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// 화면 하나에 대한 표준 검사: 빈 입력 → 제출 → 배너의 [message] 줄 탭 →
  /// 그 입력칸까지 실제로 이동.
  Future<void> checkJump(
    WidgetTester tester, {
    required Widget screen,
    required String submitLabel,
    required String message,
  }) async {
    await pumpScreen(tester, screen);
    await submit(tester, submitLabel);
    await tapBannerLine(tester, message);
    expectArrived(tester, what: message);
    await drainHighlight(tester);
  }

  // ── 화면별 검사 ─────────────────────────────────────────────────────
  //
  // 고른 항목은 모두 **폼 아래쪽**에 있어, 처음 화면에는 만들어지지도 않은
  // 것들이다(숙박+파티는 거기다 접힌 아코디언 안에 있다).

  testWidgets('파티 등록 — 아래쪽 "상세 소개"까지 이동한다', (tester) async {
    await checkJump(
      tester,
      screen: const PartyRegisterScreen(),
      submitLabel: '파티 등록하기',
      message: '파티 소개를 입력해주세요.',
    );
  });

  testWidgets('플레이스 등록 — 아래쪽 "공간 평수"까지 이동한다', (tester) async {
    await checkJump(
      tester,
      screen: const EventRegisterScreen(),
      submitLabel: '플레이스 등록하기',
      message: PlaceArea.requiredMessage,
    );
  });

  testWidgets('장소대여 등록 — 아래쪽 "룸/공간"까지 이동한다', (tester) async {
    await checkJump(
      tester,
      screen: const PlaceRegisterScreen(),
      submitLabel: '장소 등록하기',
      message: '룸/공간을 최소 1개 추가해주세요.',
    );
  });

  testWidgets('파티크루 글 등록 — 아래쪽 "상세 내용"까지 이동한다', (tester) async {
    await checkJump(
      tester,
      screen: const CrewRegisterScreen(),
      submitLabel: '구인 글 등록하기',
      message: '내용을 입력해주세요.',
    );
  });

  testWidgets('파티샵 등록 — 배너의 줄을 눌러 "샵 이름"으로 이동한다', (tester) async {
    await checkJump(
      tester,
      screen: const PartyMarketRegisterScreen(),
      submitLabel: '파티샵 등록하기',
      message: '샵 이름을 입력해주세요.',
    );
  });

  testWidgets('파티샵 상품 등록 — 배너의 줄을 눌러 "상품명"으로 이동한다', (tester) async {
    await checkJump(
      tester,
      screen: const PartyShopProductRegisterScreen(
        shopId: 'test-shop',
        shopName: '테스트 샵',
      ),
      submitLabel: '상품 등록',
      message: '상품명을 입력해주세요.',
    );
  });
}

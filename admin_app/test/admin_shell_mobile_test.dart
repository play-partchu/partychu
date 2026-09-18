// 관리자 셸(사이드바 ↔ Drawer)이 폭에 따라 바뀌는지 확인한다.
//
// ⚠ 이 파일은 **웹 플랫폼에서만** 돈다 — AdminShell이 대시보드를 거쳐
// crm_export_service.dart(dart:html)를 끌고 오기 때문이다. 실행:
//
//   flutter test --platform chrome test/admin_shell_mobile_test.dart
//
// 운영도 웹(그리고 Android WebView)이므로 검증 환경이 실제와 같다.
@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partychu_admin/services/admin_notification_service.dart';
import 'package:partychu_admin/shell/admin_shell.dart';
import 'package:partychu_admin/theme/admin_theme.dart';

import 'support/firebase_render_harness.dart';
import 'support/layout_fixtures.dart';

Future<void> _pumpShell(WidgetTester tester, double width, {double height = 800}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AdminTheme.data,
      home: AdminShell(adminEmail: 'admin@partychu.co.kr', onSignOut: () {}),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    AdminNotificationService.debugUidOverride = 'uidAdminA';
    await installFakeFirebase(
      collections: {
        ...fakeCollections,
        'adminNotifications': fakeAdminNotifications,
      },
      callables: {'adminGetHostPreRegistration': (_) => detailPayload()},
    );
  });

  tearDown(() => AdminNotificationService.debugUidOverride = null);

  testWidgets('360px에서는 사이드바가 화면을 차지하지 않고 햄버거가 나온다', (tester) async {
    await _pumpShell(tester, 360);

    expect(find.byIcon(Icons.menu), findsOneWidget);
    // 접힌 상태에서는 메뉴 라벨이 본문 옆에 상주하지 않는다.
    expect(find.text('호스트 사전등록'), findsNothing);
  });

  testWidgets('360px에서 햄버거를 누르면 Drawer로 메뉴가 열리고, 고르면 닫힌다', (tester) async {
    await _pumpShell(tester, 360);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);
    expect(find.text('호스트 사전등록'), findsOneWidget);

    await tester.tap(find.text('호스트 사전등록'));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
    expect(find.byType(DataTable), findsOneWidget);
  });

  testWidgets('1440px에서는 사이드바가 그대로 남는다(PC 디자인 무변경)', (tester) async {
    await _pumpShell(tester, 1440, height: 900);

    expect(find.byIcon(Icons.menu), findsNothing);
    expect(find.text('호스트 사전등록'), findsWidgets);
    expect(find.text('로그아웃'), findsOneWidget);
  });

  // ── 알림센터 통합 ─────────────────────────────────────────────────────────

  testWidgets('상단 종이 PC·모바일 양쪽 상단바에 그려진다', (tester) async {
    await _pumpShell(tester, 1440, height: 900);
    expect(find.byTooltip('알림'), findsOneWidget);
    expect(find.text('1'), findsOneWidget, reason: '안 읽음 숫자 배지');

    await _pumpShell(tester, 360);
    expect(find.byTooltip('알림'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('알림을 누르면 그 사전등록 상세가 열린다', (tester) async {
    await _pumpShell(tester, 1440, height: 900);

    await tester.tap(find.byTooltip('알림'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('파티츄 홍대점에서 새로운 사전등록 신청이 들어왔습니다.'));
    await tester.pumpAndSettle();

    // 목록이 아니라 **상세**가 열려야 한다 — 신청자 정보와 처리 상태가 보인다.
    expect(find.text('사전등록 상세'), findsOneWidget);
    expect(find.textContaining('FormHug #1024'), findsOneWidget);
  });

  testWidgets("'전체 알림 보기'는 전체 알림 화면으로 간다", (tester) async {
    await _pumpShell(tester, 1440, height: 900);

    await tester.tap(find.byTooltip('알림'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('전체 알림 보기'));
    await tester.pumpAndSettle();

    expect(
      find.text('운영자가 처리해야 할 일이 생기면 여기에 쌓입니다 — 최신순.'),
      findsOneWidget,
    );
  });
}

// 호스트 사전등록 화면이 모바일 폭에서 **실제로 그려지는지** 확인한다.
//
// Flutter는 가로로 넘치는 레이아웃을 만나면 노랑·검정 줄무늬를 그리며
// "A RenderFlex overflowed by N pixels" 예외를 낸다. 위젯 테스트에서는 그
// 예외가 곧 실패이므로, 화면을 360×800으로 띄워 한 번 그려보는 것만으로
// 가로 넘침을 잡아낼 수 있다.
//
// 검증 폭: 360 / 390 / 412 / 430 (요청받은 기기 폭).
// 셸(사이드바 → Drawer)은 dart:html을 끌고 오는 화면을 포함하므로
// admin_shell_mobile_test.dart에서 웹 플랫폼으로 따로 돌린다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partychu_admin/screens/admin_notifications_screen.dart';
import 'package:partychu_admin/screens/host_pre_registration_detail_screen.dart';
import 'package:partychu_admin/screens/host_pre_registrations_screen.dart';
import 'package:partychu_admin/services/admin_notification_service.dart';
import 'package:partychu_admin/theme/admin_theme.dart';
import 'package:partychu_admin/widgets/admin_notification_bell.dart';

import 'support/firebase_render_harness.dart';
import 'support/layout_fixtures.dart';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await installFakeFirebase(
      collections: {
        ...fakeCollections,
        'adminNotifications': fakeAdminNotifications,
      },
      callables: {'adminGetHostPreRegistration': (_) => detailPayload()},
    );
  });

  group('호스트 사전등록 목록', () {
    for (final w in deviceWidths) {
      testWidgets('${w.toInt()}px에서 넘침 없이 그려진다', (tester) async {
        await pumpAdminPage(
          tester,
          HostPreRegistrationsScreen(onOpen: (_) {}),
          width: w,
        );

        // 빈 화면이 통과하지 않도록 — 실제 데이터가 표로 그려졌는지 본다.
        expect(find.byType(DataTable), findsOneWidget);
        expect(find.text(longStoreName), findsOneWidget);
        expectHorizontalScrollOnlyAroundTables();
      });
    }
  });

  group('호스트 사전등록 상세', () {
    for (final w in deviceWidths) {
      testWidgets('${w.toInt()}px에서 넘침 없이 그려진다', (tester) async {
        await pumpAdminPage(
          tester,
          HostPreRegistrationDetailScreen(
            id: 'pre_1',
            onBack: () {},
            onOpenMember: (_) {},
          ),
          width: w,
        );

        expect(find.text('사전등록 상세'), findsOneWidget);
        expect(find.textContaining('FormHug #1024'), findsOneWidget);
        expectHorizontalScrollOnlyAroundTables();
      });
    }
  });

  group('알림센터', () {
    for (final w in deviceWidths) {
      testWidgets('${w.toInt()}px에서 전체 알림 화면이 넘침 없이 그려진다', (tester) async {
        AdminNotificationService.debugUidOverride = 'uidAdminA';
        addTearDown(() => AdminNotificationService.debugUidOverride = null);

        await pumpAdminPage(
          tester,
          AdminNotificationsScreen(onOpen: (_) {}),
          width: w,
        );

        expect(find.text('파티츄 홍대점에서 새로운 사전등록 신청이 들어왔습니다.'), findsOneWidget);
        expectHorizontalScrollOnlyAroundTables();
      });
    }

    for (final w in deviceWidths) {
      testWidgets('${w.toInt()}px에서 종 + 배지 + 바텀시트가 넘침 없이 열린다', (tester) async {
        AdminNotificationService.debugUidOverride = 'uidAdminA';
        addTearDown(() => AdminNotificationService.debugUidOverride = null);

        tester.view.physicalSize = Size(w, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            home: Scaffold(
              appBar: AppBar(
                title: const Text('PartyChu Admin'),
                actions: [
                  AdminNotificationBell(onOpen: (_) {}, onOpenAll: () {}),
                ],
              ),
              body: const SizedBox.shrink(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 안 읽음 숫자 배지.
        expect(find.text('1'), findsOneWidget);

        await tester.tap(find.byTooltip('알림'));
        await tester.pumpAndSettle();

        // 모바일 폭이므로 바텀시트로 열려야 한다(팝오버 380px은 360px 화면을
        // 넘는다).
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(find.text('전체 알림 보기'), findsOneWidget);
        expectHorizontalScrollOnlyAroundTables();
      });
    }
  });

  testWidgets('1440px 데스크톱에서도 그대로 그려진다(기존 디자인 회귀 확인)', (tester) async {
    await pumpAdminPage(
      tester,
      HostPreRegistrationsScreen(onOpen: (_) {}),
      width: 1440,
      height: 900,
      mobile: false,
    );

    expect(find.byType(DataTable), findsOneWidget);
    // 넓은 화면에서는 제목과 버튼이 한 줄에 그대로 남는다.
    expect(find.text('호스트 사전등록'), findsOneWidget);
    expect(find.text('신청폼 열기'), findsOneWidget);
  });
}

/// 테마까지 실제와 같게 씌워 띄운다. 셸의 본문 여백(모바일 16 / PC 28)을
/// 그대로 흉내 내, 화면이 받는 폭이 운영과 같아지게 한다.
Future<void> pumpAdminPage(
  WidgetTester tester,
  Widget screen, {
  required double width,
  double height = 800,
  bool mobile = true,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AdminTheme.data,
      home: Scaffold(
        backgroundColor: AdminTheme.pageBg,
        body: Padding(
          padding: EdgeInsets.all(mobile ? 16 : 28),
          child: screen,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

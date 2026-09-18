// 관리자 알림센터 — 모델·라우팅(순수 로직)과 종/목록(실제 렌더링).
//
// 서버 쪽(알림이 언제 만들어지는지, 소급 방지, readBy 보존)은
// functions/adminNotifications.selfcheck.js가 본다. 여기서는 **관리자가 보는
// 것과 누를 때 일어나는 일**을 본다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partychu_admin/models/admin_notification.dart';
import 'package:partychu_admin/services/admin_notification_service.dart';
import 'package:partychu_admin/theme/admin_theme.dart';
import 'package:partychu_admin/utils/admin_notification_route.dart';
import 'package:partychu_admin/widgets/admin_notification_bell.dart';

import 'support/firebase_render_harness.dart';
import 'support/layout_fixtures.dart';

const _adminA = 'uidAdminA';
const _adminB = 'uidAdminB';

AdminNotification _notif({
  String id = 'host_pre_registration__formhug_Sbyrul_9',
  String type = 'host_pre_registration',
  String refCollection = 'hostPreRegistrations',
  String refId = 'formhug_Sbyrul_9',
  List<String> readBy = const [],
}) =>
    AdminNotification(
      id: id,
      type: type,
      title: '새로운 사전등록 신청',
      body: '파티츄 홍대점에서 새로운 사전등록 신청이 들어왔습니다.',
      refCollection: refCollection,
      refId: refId,
      readBy: readBy,
      createdAt: DateTime.now(),
    );

void main() {
  group('읽음 판정', () {
    test('readBy에 내 uid가 있으면 읽은 것이다', () {
      expect(_notif(readBy: [_adminA]).isReadBy(_adminA), isTrue);
    });

    test('다른 관리자가 읽어도 나에게는 안 읽음으로 남는다', () {
      final n = _notif(readBy: [_adminA]);
      expect(n.isReadBy(_adminA), isTrue);
      expect(n.isReadBy(_adminB), isFalse,
          reason: '한 사람의 읽음이 다른 사람의 안 읽음을 지우면 안 된다');
    });

    test('로그인 전(uid 빈 값)에는 읽음으로 치지 않는다', () {
      expect(_notif(readBy: const ['']).isReadBy(''), isFalse);
    });
  });

  group('라우팅', () {
    test('사전등록 알림은 호스트 사전등록 메뉴의 그 신청서를 가리킨다', () {
      final target = adminNotificationTarget(_notif());
      expect(target, isNotNull);
      expect(target!.menuLabel, '호스트 사전등록');
      expect(target.documentId, 'formhug_Sbyrul_9');
    });

    test('refId가 없으면 갈 곳이 없다', () {
      expect(adminNotificationTarget(_notif(refId: '')), isNull);
    });

    test('아직 붙이지 않은 종류는 갈 곳이 없다(예외로 죽지 않는다)', () {
      expect(
        adminNotificationTarget(_notif(refCollection: 'reports', refId: 'r1')),
        isNull,
      );
    });

    test('종류 딱지는 알 수 없는 값이어도 사람이 읽을 수 있다', () {
      expect(_notif().typeLabel, '호스트 사전등록');
      expect(_notif(type: 'something_new').typeLabel, '알림');
    });
  });

  group('시간 표기', () {
    final now = DateTime(2026, 9, 18, 12, 0);
    test('방금 전', () {
      expect(adminNotificationTimeAgo(now.subtract(const Duration(seconds: 20)), now: now), '방금 전');
    });
    test('분/시간/일', () {
      expect(adminNotificationTimeAgo(now.subtract(const Duration(minutes: 5)), now: now), '5분 전');
      expect(adminNotificationTimeAgo(now.subtract(const Duration(hours: 3)), now: now), '3시간 전');
      expect(adminNotificationTimeAgo(now.subtract(const Duration(days: 2)), now: now), '2일 전');
    });
    test('시각이 없으면 빈 문자열', () {
      expect(adminNotificationTimeAgo(null), '');
    });
  });

  group('종 + 목록 렌더링', () {
    late FakeFirestoreStore store;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      AdminNotificationService.debugUidOverride = _adminA;
      store = await installFakeFirebase(
        collections: {
          ...fakeCollections,
          'adminNotifications': fakeAdminNotifications,
        },
        callables: {'adminGetHostPreRegistration': (_) => detailPayload()},
      );
    });

    tearDown(() => AdminNotificationService.debugUidOverride = null);

    Future<void> pumpBell(
      WidgetTester tester, {
      double width = 1440,
      void Function(AdminNotification)? onOpen,
      VoidCallback? onOpenAll,
    }) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(
            appBar: AppBar(
              actions: [
                AdminNotificationBell(
                  onOpen: onOpen ?? (_) {},
                  onOpenAll: onOpenAll ?? () {},
                ),
              ],
            ),
            body: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('안 읽은 알림 수가 배지에 숫자로 뜬다', (tester) async {
      await pumpBell(tester);
      // fixtures: 2건 중 1건은 adminA가 이미 읽었다.
      expect(find.text('1'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
    });

    testWidgets('다른 관리자에게는 안 읽음이 더 많이 보인다', (tester) async {
      AdminNotificationService.debugUidOverride = _adminB;
      await pumpBell(tester);
      expect(find.text('2'), findsOneWidget,
          reason: 'A가 읽은 것이 B의 안 읽음을 줄이면 안 된다');
    });

    testWidgets('모두 읽으면 숫자 배지가 사라진다', (tester) async {
      store.markReadBy('adminNotifications', 'host_pre_registration__formhug_Sbyrul_9', _adminA);
      await pumpBell(tester);
      expect(find.text('1'), findsNothing);
      expect(find.text('2'), findsNothing);
    });

    testWidgets('PC에서는 종 아래 팝오버로 최근 알림이 열린다', (tester) async {
      await pumpBell(tester, width: 1440);
      await tester.tap(find.byTooltip('알림'));
      await tester.pumpAndSettle();

      expect(find.text('파티츄 홍대점에서 새로운 사전등록 신청이 들어왔습니다.'), findsOneWidget);
      expect(find.text('호스트 사전등록'), findsWidgets);
      expect(find.text('전체 알림 보기'), findsOneWidget);
      expect(find.text('모두 읽음'), findsOneWidget);
    });

    testWidgets('모바일에서는 바텀시트로 열린다', (tester) async {
      await pumpBell(tester, width: 360);
      await tester.tap(find.byTooltip('알림'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('파티츄 홍대점에서 새로운 사전등록 신청이 들어왔습니다.'), findsOneWidget);
    });

    testWidgets('알림을 누르면 그 알림이 그대로 전달된다', (tester) async {
      AdminNotification? opened;
      await pumpBell(tester, onOpen: (n) => opened = n);
      await tester.tap(find.byTooltip('알림'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('파티츄 홍대점에서 새로운 사전등록 신청이 들어왔습니다.'));
      await tester.pumpAndSettle();

      expect(opened, isNotNull);
      expect(opened!.refCollection, 'hostPreRegistrations');
      expect(opened!.refId, 'formhug_Sbyrul_9');
    });

    testWidgets('전체 알림 보기를 누르면 콜백이 온다', (tester) async {
      var all = 0;
      await pumpBell(tester, onOpenAll: () => all++);
      await tester.tap(find.byTooltip('알림'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('전체 알림 보기'));
      await tester.pumpAndSettle();
      expect(all, 1);
    });

    testWidgets('모두 읽음은 안 읽은 알림에만 쓰기를 보낸다', (tester) async {
      await pumpBell(tester);
      await tester.tap(find.byTooltip('알림'));
      await tester.pumpAndSettle();

      store.writes.clear();
      await tester.tap(find.text('모두 읽음'));
      await tester.pumpAndSettle();

      expect(store.writes.length, 1,
          reason: '이미 읽은 알림에까지 쓰기를 보내면 안 된다');
      expect(store.writes.single.$1,
          'adminNotifications/host_pre_registration__formhug_Sbyrul_9');
      expect(store.writes.single.$2.keys, contains('readBy'));
    });

    testWidgets('이미 읽은 알림을 눌러도 쓰기를 보내지 않는다', (tester) async {
      // 두 건 모두 읽은 상태로 만든다.
      store.markReadBy('adminNotifications', 'host_pre_registration__formhug_Sbyrul_9', _adminA);
      await pumpBell(tester);
      await tester.tap(find.byTooltip('알림'));
      await tester.pumpAndSettle();

      store.writes.clear();
      // '모두 읽음'은 비활성이어야 한다.
      final button = tester.widget<TextButton>(
        find.ancestor(of: find.text('모두 읽음'), matching: find.byType(TextButton)),
      );
      expect(button.onPressed, isNull);
      expect(store.writes, isEmpty);
    });
  });
}

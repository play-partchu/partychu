// 관리자 화면의 전화번호 — 회원 관리 목록·회원 상세는 전체 번호를 보여 준다.
//
// 표기 규칙은 순수 함수로 보고, 화면에서는 마스킹(****)이 남아 있지 않은지와
// 실제 번호가 그려지는지를 본다.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partychu_admin/screens/member_detail_screen.dart';
import 'package:partychu_admin/screens/members_screen.dart';
import 'package:partychu_admin/services/person_identity_service.dart';
import 'package:partychu_admin/theme/admin_theme.dart';
import 'package:partychu_admin/utils/masking.dart';
import 'package:partychu_admin/utils/phone_display.dart';

import 'support/firebase_render_harness.dart';

final FakeCollections _collections = {
  'users': [
    (
      'uidCall',
      {
        'name': '홍길동',
        'nickname': '길동',
        'phoneNumber': '01012344423',
        'identityVerified': true,
        'createdAt': Timestamp.fromDate(DateTime(2026, 9, 1)),
        'isTestAccount': false,
        'accountStatus': 'active',
      },
    ),
  ],
};

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AdminTheme.data,
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(28), child: screen),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('관리자 전화번호 표기', () {
    test('휴대전화 11자리는 010-1234-4423', () {
      expect(adminPhoneNumber('01012344423'), '010-1234-4423');
      expect(adminPhoneNumber('010-1234-4423'), '010-1234-4423');
      expect(adminPhoneNumber('010 1234 4423'), '010-1234-4423');
    });

    test('국제 표기(+82)는 국내 표기로', () {
      expect(adminPhoneNumber('+821012344423'), '010-1234-4423');
      expect(adminPhoneNumber('+82 10-1234-4423'), '010-1234-4423');
      // 0이 붙은 채로 온 것도 그대로 살린다.
      expect(adminPhoneNumber('+8201012344423'), '010-1234-4423');
    });

    test('옛 휴대전화·지역번호·대표번호', () {
      expect(adminPhoneNumber('0111234567'), '011-123-4567'); // 10자리
      expect(adminPhoneNumber('0212345678'), '02-1234-5678'); // 서울 10자리
      expect(adminPhoneNumber('021234567'), '02-123-4567'); // 서울 9자리
      expect(adminPhoneNumber('0311234567'), '031-123-4567');
      expect(adminPhoneNumber('15441234'), '1544-1234');
    });

    test('값이 없으면 -', () {
      expect(adminPhoneNumber(null), '-');
      expect(adminPhoneNumber(''), '-');
      expect(adminPhoneNumber('   '), '-');
    });

    test('아는 모양이 아니면 원문 그대로 — 억지로 끊지 않는다', () {
      expect(adminPhoneNumber('12345'), '12345');
      expect(adminPhoneNumber('내선 1234번'), '내선 1234번');
    });

    test('어떤 경우에도 마스킹 문자를 넣지 않는다', () {
      for (final v in ['01012344423', '+821012344423', '0212345678', '12345']) {
        expect(adminPhoneNumber(v), isNot(contains('*')));
      }
    });

    test('일반 마스킹 함수는 그대로 남아 있다', () {
      // 사전등록 신청자 화면 등 관리자 회원 관리 밖에서 계속 쓴다.
      expect(Masking.phone('01012344423'), '010-****-4423');
    });
  });

  group('화면', () {
    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      PersonIdentityService.resetCache();
      final store = await installFakeFirebase(
        collections: _collections,
        callables: {
          'adminGetUserApplications': (_) => {'applications': <Object>[]},
          'adminGetAccountLinkHistory': (_) => {
            'linked': false,
            'isRejoined': false,
            'currentUid': null,
            'previous': <Object>[],
          },
        },
      );
      store.equalityFiltered.add('users');
    });

    testWidgets('회원 관리 목록에 전체 번호가 보인다', (tester) async {
      await _pump(tester, MembersScreen(onOpenMember: (_) {}));

      expect(find.text('010-1234-4423'), findsOneWidget);
      expect(find.textContaining('****'), findsNothing);
    });

    testWidgets('회원 상세에도 전체 번호가 보인다', (tester) async {
      await _pump(tester, MemberDetailScreen(uid: 'uidCall', onBack: () {}));

      expect(find.text('010-1234-4423'), findsWidgets);
      expect(find.textContaining('010-****'), findsNothing);
    });
  });
}

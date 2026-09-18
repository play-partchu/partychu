// 회원 관리 목록·회원 상세가 **실제 회원 1명 = 한 줄**로 그려지는지.
//
// 순수 규칙은 person_identity_test.dart가 본다. 여기서는 실제 화면을 가짜
// Firestore 위에 띄워 머리줄 숫자·행 수·'계정 N개'·보유 계정 섹션을 본다.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partychu_admin/screens/member_detail_screen.dart';
import 'package:partychu_admin/screens/members_screen.dart';
import 'package:partychu_admin/services/person_identity_service.dart';
import 'package:partychu_admin/theme/admin_theme.dart';

import 'support/firebase_render_harness.dart';
import 'support/layout_fixtures.dart';

const _hash = 'HASH_PARK';

Timestamp _ts(int y, int m, int d) => Timestamp.fromDate(DateTime(y, m, d));

Map<String, dynamic> _park(String provider, String email, Timestamp createdAt) => {
      'name': '박테스트',
      'nickname': '박$provider',
      'identityVerified': true,
      'identityCiHash': _hash,
      'ci': 'CI_PARK',
      'signupProvider': provider,
      'email': email,
      'createdAt': createdAt,
      'lastLoginAt': createdAt,
      'isTestAccount': false,
      'accountStatus': 'active',
    };

/// 박테스트 1명이 계정 3개, 김·이는 본인확인 전 단독, 테스트 계정 1개.
final FakeCollections _collections = {
  'users': [
    ('uidGoogle', _park('google', 'park@gmail.com', _ts(2026, 8, 1))),
    ('uidKim', {
      'name': '김단독',
      'nickname': '김',
      'createdAt': _ts(2026, 8, 2),
      'isTestAccount': false,
      'accountStatus': 'active',
    }),
    ('naver:abc', _park('naver', 'park@naver.com', _ts(2026, 9, 1))),
    ('uidLee', {
      'name': '이단독',
      'nickname': '이',
      'createdAt': _ts(2026, 9, 2),
      'isTestAccount': false,
      'accountStatus': 'active',
    }),
    ('uidApple', _park('apple', 'relay@privaterelay.appleid.com', _ts(2026, 9, 12))),
    ('uidTest', {
      'name': '테스트',
      'nickname': 'QA',
      'createdAt': _ts(2026, 9, 3),
      'isTestAccount': true,
      'accountStatus': 'active',
    }),
  ],
};

Future<void> _pump(WidgetTester tester, Widget screen, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AdminTheme.data,
    home: Scaffold(
      body: Padding(padding: EdgeInsets.all(width < 900 ? 16 : 28), child: screen),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  late FakeFirestoreStore store;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    PersonIdentityService.resetCache();
    store = await installFakeFirebase(
      collections: _collections,
      callables: {
        'adminGetUserApplications': (_) => {'applications': <Object>[]},
        'adminGetAccountLinkHistory': (_) =>
            {'linked': false, 'isRejoined': false, 'currentUid': null, 'previous': <Object>[]},
      },
    );
    // 개수 집계(isTestAccount == true 빼기)와 동일인 조회(identityCiHash ==)가
    // 조건대로 걸러져야 숫자를 검증할 수 있다.
    store.equalityFiltered.add('users');
  });

  group('회원 관리 목록', () {
    for (final w in [...deviceWidths, 1440.0]) {
      testWidgets('${w.toInt()}px — 한 사람은 한 줄, 머리줄은 실제 회원 수', (tester) async {
        await _pump(tester, MembersScreen(onOpenMember: (_) {}), w);

        // 실사용 계정 5개(테스트 1개 제외) 중 박테스트의 계정 3개가 1명 → 3명.
        expect(find.text('전체 3명 (계정 5개)'), findsOneWidget);
        expect(find.text('박테스트'), findsOneWidget, reason: '같은 사람은 한 줄');
        expect(find.text('김단독'), findsOneWidget);
        expect(find.text('이단독'), findsOneWidget);
        expect(find.text('계정 3개'), findsOneWidget);
        expect(find.text('구글 · 네이버 · Apple'), findsOneWidget);
        expect(find.textContaining('동일인 계정 2개 합침'), findsOneWidget);
        expect(find.textContaining(_hash), findsNothing);
        expect(find.textContaining('CI_PARK'), findsNothing);
        if (w < 900) expectHorizontalScrollOnlyAroundTables();
      });
    }

    testWidgets('CI가 없는 계정끼리는 이름이 같아도 합치지 않는다', (tester) async {
      store.reset({
        'users': [
          ('a', {'name': '홍길동', 'birthYear': 1991, 'createdAt': _ts(2026, 9, 1), 'isTestAccount': false}),
          ('b', {'name': '홍길동', 'birthYear': 1991, 'createdAt': _ts(2026, 9, 2), 'isTestAccount': false}),
        ],
      });
      store.equalityFiltered.add('users');
      await _pump(tester, MembersScreen(onOpenMember: (_) {}), 390);

      expect(find.text('전체 2명'), findsOneWidget);
      expect(find.text('홍길동'), findsNWidgets(2));
      expect(find.textContaining(RegExp(r'계정 \d+개')), findsNothing);
    });
  });

  group('회원 상세 — 보유 계정', () {
    for (final w in [...deviceWidths, 1440.0]) {
      testWidgets('${w.toInt()}px — 같은 사람의 계정을 모두 보여 준다', (tester) async {
        final opened = <String>[];
        await _pump(
          tester,
          MemberDetailScreen(uid: 'naver:abc', onBack: () {}, onOpenMember: opened.add),
          w,
        );

        expect(find.text('보유 계정'), findsOneWidget);
        expect(find.text('실제 회원 1명'), findsOneWidget);
        expect(find.text('계정 3개'), findsOneWidget);
        expect(find.text('park@gmail.com'), findsWidgets);
        expect(find.text('park@naver.com'), findsWidgets);
        expect(find.text('relay@privaterelay.appleid.com'), findsWidgets);
        expect(find.text('uidGoogle'), findsOneWidget);
        expect(find.text('uidApple'), findsOneWidget);
        expect(find.text('지금 보는 계정'), findsOneWidget);
        expect(find.textContaining(_hash), findsNothing);
        expect(find.textContaining('CI_PARK'), findsNothing);
        if (w < 900) expectHorizontalScrollOnlyAroundTables();

        // 다른 계정의 줄(이메일)을 누르면 그 계정 상세로 간다.
        final appleRow = find.text('relay@privaterelay.appleid.com').last;
        await tester.ensureVisible(appleRow);
        await tester.pumpAndSettle();
        await tester.tap(appleRow);
        await tester.pumpAndSettle();
        expect(opened, ['uidApple']);
      });
    }

    testWidgets('본인확인 전 계정은 자기 자신만, 근거 없음 안내와 함께', (tester) async {
      await _pump(tester, MemberDetailScreen(uid: 'uidKim', onBack: () {}), 390);

      expect(find.text('계정 1개'), findsOneWidget);
      expect(find.textContaining('판별할 수 없습니다'), findsOneWidget);
    });
  });
}

// 동일인(실제 회원 1명) 묶음 — 판별 규칙·집계·목록 접기·보유 계정 카드.
//
// 판별 규칙은 서버 functions/identityLink.js의 ciHashOfUserData와 같아야 한다.
// 아래 기대 해시는 Node의 crypto로 계산한 값이다 — Dart 구현이 서버와 다른
// 해시를 내면 이 테스트가 먼저 깨진다.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partychu_admin/services/admin_firestore_service.dart';
import 'package:partychu_admin/theme/admin_theme.dart';
import 'package:partychu_admin/utils/person_identity.dart';
import 'package:partychu_admin/widgets/person_accounts_card.dart';

import 'support/layout_fixtures.dart';

const _ci = 'TEST_CI_가나다==';
// node -e 'crypto.createHash("sha256").update("TEST_CI_가나다==","utf8").digest("hex")'
const _ciHash = 'd28130d6f0c2fd43f8af0910126301d225ea8ae8d18b32e44d50d1ed3d2c9ea9';

Timestamp _ts(int y, int m, int d) => Timestamp.fromDate(DateTime(y, m, d));

/// 운영에서 실제로 본 모양 — 한 사람이 Apple·구글·네이버 계정 셋을 가졌다.
Map<String, Map<String, dynamic>> _park() => {
      'uidApple': {
        'name': '박테스트',
        'identityVerified': true,
        'identityCiHash': _ciHash,
        'ci': _ci,
        'signupProvider': 'apple',
        'email': 'relay@privaterelay.appleid.com',
        'createdAt': _ts(2026, 9, 12),
        'lastLoginAt': _ts(2026, 9, 17),
        'isTestAccount': false,
      },
      'uidGoogle': {
        'name': '박테스트',
        'identityVerified': true,
        'identityCiHash': _ciHash,
        'ci': _ci,
        'signupProvider': 'google',
        'email': 'park@gmail.com',
        'createdAt': _ts(2026, 8, 1),
        'isTestAccount': false,
      },
      'naver:abc123': {
        'name': '박테스트',
        'identityVerified': true,
        'identityCiHash': _ciHash,
        'ci': _ci,
        'socialAccount': {'provider': 'naver', 'email': 'park@naver.com'},
        'createdAt': _ts(2026, 9, 1),
        'isTestAccount': false,
      },
    };

void main() {
  group('동일인 키', () {
    test('identityCiHash가 있으면 그 값이다', () {
      expect(personKeyOf({'identityCiHash': 'H', 'ci': _ci}), 'H');
    });

    test('해시 필드가 없는 옛 회원은 CI 원문의 sha256 — 서버와 같은 값', () {
      expect(personKeyOf({'ci': _ci}), _ciHash);
    });

    test('옛 회원(원문만)과 새 회원(해시)은 같은 사람으로 묶인다', () {
      final groups = groupAccountsByPerson([
        ('old', {'ci': _ci, 'identityVerified': true}),
        ('new', {'identityCiHash': _ciHash, 'ci': _ci, 'identityVerified': true}),
      ]);
      expect(groups, hasLength(1));
      expect(groups.single.accountCount, 2);
    });

    test('CI가 없으면 키가 없다(빈 문자열·공백 포함)', () {
      expect(personKeyOf({}), isNull);
      expect(personKeyOf({'ci': '   ', 'identityCiHash': ''}), isNull);
    });

    test('이름·생년월일·전화번호가 같아도 CI가 없으면 합치지 않는다', () {
      final same = {
        'name': '홍길동',
        'birthYear': 1991,
        'birthMonth': 3,
        'birthDay': 15,
        'phoneNumber': '01012345678',
        'identityVerified': true,
      };
      final groups = groupAccountsByPerson([('a', {...same}), ('b', {...same})]);
      expect(groups, hasLength(2));
      expect(groups.every((g) => g.key == null && g.accountCount == 1), isTrue);
    });

    test('CI가 다르면 이름이 같아도 다른 사람이다', () {
      final groups = groupAccountsByPerson([
        ('a', {'name': '홍길동', 'identityCiHash': 'H1'}),
        ('b', {'name': '홍길동', 'identityCiHash': 'H2'}),
      ]);
      expect(groups, hasLength(2));
    });
  });

  group('계정 요약', () {
    test('세 계정이 한 사람으로, 가입 순서대로 묶인다', () {
      final groups = groupAccountsByPerson(_park().entries.map((e) => (e.key, e.value)));
      expect(groups, hasLength(1));
      final p = groups.single;
      expect(p.accounts.map((a) => a.uid), ['uidGoogle', 'naver:abc123', 'uidApple']);
      expect(p.providersLabel, '구글 · 네이버 · Apple');
    });

    test('로그인 수단 — socialAccount가 signupProvider보다 먼저다', () {
      final a = MemberAccount.fromUserDoc('u', {
        'signupProvider': 'google',
        'socialAccount': {'provider': 'kakao', 'email': 'k@kakao.com'},
        'email': 'g@gmail.com',
      });
      expect(a.provider, 'kakao');
      expect(a.email, 'k@kakao.com', reason: '로그인 수단의 이메일을 보여 준다');
    });

    test('필드가 없으면 카카오·네이버 uid 접두사로 판단한다', () {
      expect(MemberAccount.fromUserDoc('kakao:1', {}).provider, 'kakao');
      expect(MemberAccount.fromUserDoc('naver:1', {}).provider, 'naver');
      expect(MemberAccount.fromUserDoc('abc', {}).provider, isNull);
      expect(MemberAccount.fromUserDoc('abc', {}).providerLabel, '알 수 없음');
    });
  });

  group('사람 수 집계', () {
    test('계정 수 − 같은 사람의 두 번째 이후 계정 = 사람 수', () {
      final docs = [
        ..._park().values, // 1명, 3계정
        {'identityCiHash': 'OTHER'}, // 1명
        {'ci': 'LEGACY'}, {'ci': 'LEGACY'}, // 옛 회원 1명, 2계정
        {'identityVerified': true}, // CI 없음 — 단독
        {'identityVerified': true}, // CI 없음 — 단독
      ];
      final duplicates = duplicateAccountCount(docs);
      expect(duplicates, 3);
      expect(docs.length - duplicates, 5, reason: '운영에서 본 11계정→5명 모양과 같은 구조');
    });

    test('조건 안에 한 계정만 있는 사람은 빠지지 않는다', () {
      // 호출부가 조건을 통과한 계정만 넘긴다 — 여기선 구글 계정 하나만.
      final onlyGoogle = _park().values.where((d) => d['signupProvider'] == 'google');
      expect(duplicateAccountCount(onlyGoogle), 0);
    });
  });

  group('목록 접기', () {
    List<(String, Map<String, dynamic>)> page() => [
          ('uidGoogle', _park()['uidGoogle']!),
          ('solo', {'name': '김단독'}),
          ('uidApple', _park()['uidApple']!),
        ];

    Map<String, PersonGroup> people() => {
          for (final g in groupAccountsByPerson(_park().entries.map((e) => (e.key, e.value))))
            g.key!: g,
        };

    test('같은 페이지의 같은 사람은 먼저 나온 한 줄만 남는다', () {
      final r = collapsePageByPerson(page(), read: (d) => d, peopleByKey: people());
      expect(r.rows.map((d) => d.$1), ['uidGoogle', 'solo']);
      expect(r.collapsed, 1);
      expect(r.groups[r.rows.first]!.accountCount, 3, reason: '페이지 밖 네이버 계정까지 센다');
      expect(r.groups.containsKey(r.rows[1]), isFalse, reason: 'CI 없는 계정엔 묶음이 없다');
    });

    test('앞 페이지에서 이미 보여 준 사람은 이 페이지에서 감춘다', () {
      final r = collapsePageByPerson(
        page(),
        read: (d) => d,
        peopleByKey: people(),
        alreadyShownKeys: {_ciHash},
      );
      expect(r.rows.map((d) => d.$1), ['solo']);
      expect(r.collapsed, 2);
    });

    test('묶음 정보를 못 불러와도 같은 페이지 안에서는 묶인다', () {
      final r = collapsePageByPerson(page(), read: (d) => d, peopleByKey: const {});
      expect(r.rows, hasLength(2));
      expect(r.groups[r.rows.first]!.accountCount, 1);
    });
  });

  group('필터 조건 복제', () {
    final d = {
      'identityVerified': true,
      'gender': 'male',
      'signupProvider': 'google',
      'accountStatus': 'active',
      'activityRoles': ['host_activity'],
      'birthYear': 1991,
      'createdAt': _ts(2026, 9, 1),
      'lastLoginAt': _ts(2026, 9, 17),
    };

    test('등호 조건', () {
      expect(AdminFirestoreService.matchesUsersFilter(d, gender: 'male'), isTrue);
      expect(AdminFirestoreService.matchesUsersFilter(d, gender: 'female'), isFalse);
      expect(AdminFirestoreService.matchesUsersFilter(d, identityVerified: false), isFalse);
      expect(AdminFirestoreService.matchesUsersFilter(d, activityRole: 'host_activity'), isTrue);
      expect(AdminFirestoreService.matchesUsersFilter(d, activityRole: 'shop_seller'), isFalse);
      expect(AdminFirestoreService.matchesUsersFilter(d, signupProvider: 'naver'), isFalse);
    });

    test('범위 조건', () {
      expect(
        AdminFirestoreService.matchesUsersFilter(d,
            joinedFrom: DateTime(2026, 8, 1), joinedTo: DateTime(2026, 9, 30)),
        isTrue,
      );
      expect(AdminFirestoreService.matchesUsersFilter(d, joinedFrom: DateTime(2026, 9, 2)), isFalse);
      expect(
        AdminFirestoreService.matchesUsersFilter(d, lastLoginSince: DateTime(2026, 9, 18)),
        isFalse,
      );
    });

    test('정렬 필드가 없는 문서는 목록에 없으므로 세지 않는다', () {
      expect(
        AdminFirestoreService.matchesUsersFilter(d, sortField: MemberSortField.lastActiveAt),
        isFalse,
      );
      expect(AdminFirestoreService.matchesUsersFilter(d), isTrue);
    });
  });

  group('보유 계정 카드', () {
    PersonGroup park() =>
        groupAccountsByPerson(_park().entries.map((e) => (e.key, e.value))).single;

    Future<void> pumpCard(WidgetTester tester, double width, {ValueChanged<String>? onOpen}) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AdminTheme.data,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: PersonAccountsCard(
              person: park(),
              currentUid: 'uidGoogle',
              displayName: '박테스트',
              onOpenAccount: onOpen,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    for (final w in deviceWidths) {
      testWidgets('${w.toInt()}px에서 넘침 없이 모든 계정을 보여 준다', (tester) async {
        await pumpCard(tester, w);

        expect(find.text('실제 회원 1명'), findsOneWidget);
        expect(find.text('계정 3개'), findsOneWidget);
        for (final label in ['구글', '네이버', 'Apple']) {
          expect(find.text(label), findsOneWidget);
        }
        expect(find.text('park@gmail.com'), findsOneWidget);
        expect(find.text('park@naver.com'), findsOneWidget);
        expect(find.text('uidApple'), findsOneWidget);
        expect(find.text('naver:abc123'), findsOneWidget);
        expect(find.text('지금 보는 계정'), findsOneWidget);
        expectHorizontalScrollOnlyAroundTables();
      });
    }

    testWidgets('1440px에서도 그대로 그려진다', (tester) async {
      await pumpCard(tester, 1440);
      expect(find.text('계정 3개'), findsOneWidget);
    });

    testWidgets('CI 원문과 해시는 화면에 나오지 않는다', (tester) async {
      await pumpCard(tester, 390);
      expect(find.textContaining(_ci), findsNothing);
      expect(find.textContaining(_ciHash.substring(0, 12)), findsNothing);
    });

    testWidgets('다른 계정을 누르면 그 계정으로 가고, 지금 계정은 눌리지 않는다', (tester) async {
      final opened = <String>[];
      await pumpCard(tester, 390, onOpen: opened.add);

      await tester.tap(find.text('park@naver.com'));
      await tester.pumpAndSettle();
      expect(opened, ['naver:abc123']);

      await tester.tap(find.text('park@gmail.com'));
      await tester.pumpAndSettle();
      expect(opened, ['naver:abc123'], reason: '지금 보는 계정은 다시 열지 않는다');
    });
  });
}

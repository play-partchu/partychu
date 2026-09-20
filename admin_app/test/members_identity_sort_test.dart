// 회원 관리 목록의 '본인확인' 열 — 배지 표기와 머리 클릭 정렬.
//
// 순수 규칙(무엇을 인증완료로 보는가, 어떤 순서로 세우는가)은 아래 group으로
// 따로 보고, 실제 화면에서는 줄 순서가 정말 바뀌는지와 상단 필터·검색 같은
// 기존 기능이 그대로 남아 있는지를 본다.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partychu_admin/screens/members_screen.dart';
import 'package:partychu_admin/services/person_identity_service.dart';
import 'package:partychu_admin/theme/admin_theme.dart';
import 'package:partychu_admin/utils/member_identity_sort.dart';

import 'support/firebase_render_harness.dart';

Timestamp _ts(int y, int m, int d) => Timestamp.fromDate(DateTime(y, m, d));

Map<String, dynamic> _member(
  String name, {
  bool? identityVerified,
  bool? isVerified,
  required int day,
}) => {
  'name': name,
  // 이름과 다르게 둔다 — 같으면 줄 위치를 찾을 때 두 칸이 함께 잡힌다.
  'nickname': '$name의닉',
  'identityVerified': ?identityVerified,
  'isVerified': ?isVerified,
  'createdAt': _ts(2026, 9, day),
  'isTestAccount': false,
  'accountStatus': 'active',
};

/// 인증 여부가 번갈아 나오게 둔다 — 그래야 정렬이 실제로 순서를 바꾸는지
/// 보인다. 대역 쿼리는 orderBy를 무시하므로 이 선언 순서가 곧 '정렬 전' 순서다.
final FakeCollections _collections = {
  'users': [
    ('uidA', _member('가미인증', day: 1)),
    ('uidB', _member('나인증', identityVerified: true, day: 2)),
    ('uidC', _member('다미인증', identityVerified: false, day: 3)),
    // 옛 필드만 가진 계정 — 운영에 실제로 있다. '인증완료'로 세어야 한다.
    ('uidD', _member('라옛인증', isVerified: true, day: 4)),
  ],
};

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AdminTheme.data,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(28),
          child: MembersScreen(onOpenMember: (_) {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 표에 그려진 이름을 **위에서 아래 순서대로**.
List<String> _rowOrder(WidgetTester tester) {
  const names = ['가미인증', '나인증', '다미인증', '라옛인증'];
  final found = <(double, String)>[
    for (final n in names)
      if (tester.any(find.text(n))) (tester.getTopLeft(find.text(n)).dy, n),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final e in found) e.$2];
}

Finder get _identityHeader =>
    find.descendant(of: find.byType(DataTable), matching: find.text('본인확인'));

void main() {
  group('본인확인 판정 — 새 필드를 만들지 않는다', () {
    test('identityVerified가 정본, 없으면 옛 isVerified로 폴백', () {
      expect(isIdentityVerifiedDoc({'identityVerified': true}), isTrue);
      expect(isIdentityVerifiedDoc({'identityVerified': false}), isFalse);
      expect(isIdentityVerifiedDoc({'isVerified': true}), isTrue);
      expect(isIdentityVerifiedDoc({}), isFalse);
    });

    test('두 필드가 어긋나면 지금 쓰는 identityVerified가 이긴다', () {
      expect(
        isIdentityVerifiedDoc({'identityVerified': false, 'isVerified': true}),
        isFalse,
      );
    });
  });

  group('정렬 규칙', () {
    // (이름, 인증여부) — 인증·미인증이 섞여 있고 같은 상태가 여럿이다.
    const items = [('a', false), ('b', true), ('c', false), ('d', true)];
    List<String> sorted(IdentitySortOrder order) => [
      for (final e in sortByIdentityVerified(
        items,
        verified: (e) => e.$2,
        order: order,
      ))
        e.$1,
    ];

    test('완료 먼저 / 미완료 먼저 두 방향', () {
      expect(sorted(IdentitySortOrder.verifiedFirst), ['b', 'd', 'a', 'c']);
      expect(sorted(IdentitySortOrder.unverifiedFirst), ['a', 'c', 'b', 'd']);
    });

    test('정렬 안 함이면 받은 순서 그대로', () {
      expect(sorted(IdentitySortOrder.none), ['a', 'b', 'c', 'd']);
    });

    test('같은 상태끼리는 들어온 순서를 지킨다(안정 정렬)', () {
      // 상단 정렬 드롭다운이 정한 '최근 가입순' 같은 순서가 묶음 안에 남아야 한다.
      final many = [for (var i = 0; i < 40; i++) ('n$i', i.isEven)];
      final result = [
        for (final e in sortByIdentityVerified(
          many,
          verified: (e) => e.$2,
          order: IdentitySortOrder.verifiedFirst,
        ))
          e.$1,
      ];
      expect(result.take(20), [for (var i = 0; i < 40; i += 2) 'n$i']);
      expect(result.skip(20), [for (var i = 1; i < 40; i += 2) 'n$i']);
    });

    test('머리를 세 번 누르면 원래 상태로 돌아온다', () {
      var order = IdentitySortOrder.verifiedFirst;
      order = order.next;
      expect(order, IdentitySortOrder.unverifiedFirst);
      order = order.next;
      expect(order, IdentitySortOrder.none);
      order = order.next;
      expect(order, IdentitySortOrder.verifiedFirst);
    });

    test('화살표 방향 — 미인증 먼저일 때만 오름차순', () {
      expect(IdentitySortOrder.unverifiedFirst.ascending, isTrue);
      expect(IdentitySortOrder.verifiedFirst.ascending, isFalse);
    });
  });

  group('회원 관리 화면', () {
    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      PersonIdentityService.resetCache();
      final store = await installFakeFirebase(collections: _collections);
      store.equalityFiltered.add('users');
    });

    testWidgets('배지로 인증완료 / 미인증을 보여 준다', (tester) async {
      await _pump(tester);

      expect(find.text('인증완료'), findsNWidgets(2));
      expect(find.text('미인증'), findsNWidgets(2));
      // 예전 문구는 남아 있지 않다.
      expect(find.text('완료'), findsNothing);
      expect(find.text('미완료'), findsNothing);
    });

    testWidgets('첫 진입은 본인확인 완료 회원이 위', (tester) async {
      await _pump(tester);

      expect(_rowOrder(tester), ['나인증', '라옛인증', '가미인증', '다미인증']);
    });

    testWidgets('머리를 누르면 미인증 먼저 → 다시 누르면 원래 순서', (tester) async {
      await _pump(tester);

      await tester.tap(_identityHeader);
      await tester.pumpAndSettle();
      expect(_rowOrder(tester), ['가미인증', '다미인증', '나인증', '라옛인증']);

      await tester.tap(_identityHeader);
      await tester.pumpAndSettle();
      // 정렬 안 함 — 목록이 받아 온 순서 그대로.
      expect(_rowOrder(tester), ['가미인증', '나인증', '다미인증', '라옛인증']);

      await tester.tap(_identityHeader);
      await tester.pumpAndSettle();
      expect(_rowOrder(tester), ['나인증', '라옛인증', '가미인증', '다미인증']);
    });

    testWidgets('정렬해도 줄이 사라지거나 늘지 않는다', (tester) async {
      await _pump(tester);

      expect(_rowOrder(tester).length, 4);
      await tester.tap(_identityHeader);
      await tester.pumpAndSettle();
      expect(_rowOrder(tester).length, 4);
      expect(find.text('전체 4명'), findsOneWidget);
    });

    testWidgets('상단 본인확인 필터와 다른 필터는 그대로 있다', (tester) async {
      await _pump(tester);

      // 상단 필터는 Text.rich('이름 값')이라 라벨 조각으로 찾는다.
      expect(find.textContaining('본인확인'), findsWidgets);
      expect(find.byType(DropdownButton<bool?>), findsOneWidget);
      expect(find.text('닉네임 · 이름 · 이메일 · UID 검색'), findsOneWidget);
      expect(find.text('테스트 계정 보기'), findsOneWidget);
      expect(find.textContaining('페이지당'), findsWidgets);
    });
  });
}

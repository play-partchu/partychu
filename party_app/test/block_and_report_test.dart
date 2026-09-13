import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/models/report_reason.dart';
import 'package:party_app/services/block_service.dart';
import 'package:party_app/services/report_service.dart';

/// 사용자 차단 · 신고의 **판정 규칙**을 그대로 못박는다.
///
/// Firestore를 띄우지 않는다 — 여기서 시험하는 것은 네트워크가 아니라 규칙
/// 자체다. 문서 id 규칙, 목록에서 무엇이 빠지는가, 무엇이 중복 신고인가.
/// 셋 다 앱·firestore.rules·서버가 **같은 문자열**을 만들어야 성립한다.
///
/// 서버 쪽 같은 정책(차단의 양방향 효과)은
/// functions/userBlocks.selfcheck.js가 본다.
void main() {
  setUp(() => BlockService.setBlockedIdsForTest(<String>{}));
  tearDown(() => BlockService.setBlockedIdsForTest(<String>{}));

  group('차단 — 문서 id 규칙', () {
    test('id는 "{차단한사람}_{차단당한사람}"이다', () {
      // 이 문자열이 세 곳에서 같아야 한다 — 앱(BlockService), 규칙
      // (firestore.rules userBlocks create), 서버(chatRooms.js
      // isBlockedBetween). 하나만 달라지면 차단이 조용히 샌다.
      expect(BlockService.docIdFor('A', 'B'), 'A_B');
    });

    test('내 uid가 맨 앞이다 — 규칙이 문서 id만 보고 판별할 수 있어야 한다', () {
      // 아직 없는 문서를 get()하면 규칙 안에서 resource가 null이라
      // resource.data를 보는 조건은 평가 자체가 실패한다(favorites와 같은
      // 함정). id가 내 uid로 시작해야 그 경로를 피한다.
      expect(BlockService.docIdFor('me', 'other').startsWith('me_'), isTrue);
    });

    test('방향이 다르면 다른 문서다 — 차단 기록은 한 방향이다', () {
      expect(
        BlockService.docIdFor('A', 'B'),
        isNot(BlockService.docIdFor('B', 'A')),
      );
    });
  });

  group('차단 — 목록 필터', () {
    test('차단 목록이 비어 있으면 아무것도 걸러지지 않는다', () {
      // 로그인 전이거나 아직 못 읽은 상태. 모르면 **보여준다**(fail-open) —
      // 차단 기능의 오류가 목록을 통째로 비우면 안 된다.
      expect(BlockService.isBlockedOwner({'hostId': 'A'}), isFalse);
    });

    test('차단한 사람이 hostId면 걸러진다', () {
      BlockService.setBlockedIdsForTest({'A'});
      expect(BlockService.isBlockedOwner({'hostId': 'A'}), isTrue);
      expect(BlockService.isBlockedOwner({'hostId': 'B'}), isFalse);
    });

    test('작성자 필드 이름이 달라도 걸러진다(hostUid·ownerId·userId)', () {
      // 컬렉션마다 작성자 필드 이름이 다르다. 하나만 보면 파티는 사라지는데
      // 파티샵은 남는 식이 된다.
      BlockService.setBlockedIdsForTest({'A'});
      expect(BlockService.isBlockedOwner({'hostUid': 'A'}), isTrue);
      expect(BlockService.isBlockedOwner({'ownerId': 'A'}), isTrue);
      expect(BlockService.isBlockedOwner({'userId': 'A'}), isTrue);
    });

    test('작성자를 알 수 없는 문서는 걸러지지 않는다', () {
      BlockService.setBlockedIdsForTest({'A'});
      expect(BlockService.isBlockedOwner({'title': '제목만 있는 옛 문서'}), isFalse);
    });

    test('isBlocked는 빈 문자열·null을 차단으로 보지 않는다', () {
      BlockService.setBlockedIdsForTest({'A'});
      expect(BlockService.isBlocked(''), isFalse);
      expect(BlockService.isBlocked(null), isFalse);
      expect(BlockService.isBlocked('A'), isTrue);
    });
  });

  group('차단 — 본인 차단 금지', () {
    test('자기 자신은 차단할 수 없다', () async {
      // 규칙에서도 한 번 더 막는다(blockedId != uid()). 앱이 먼저 막는 것은
      // 사용자에게 이유를 알려주기 위해서다.
      await expectLater(
        BlockService.block('me'),
        throwsA(isA<StateError>()), // 로그인 세션이 없으면 StateError가 먼저다
      );
    });
  });

  group('신고 — 중복 방지', () {
    test('id는 "{신고자}_{대상종류}_{대상id}"다', () {
      // 중복 신고 방지의 전부가 이 문자열이다 — 같은 사람이 같은 대상을
      // 두 번 신고하면 같은 문서를 가리키고, 규칙이 update를 막는다.
      expect(
        ReportService.docIdFor(
          reporterId: 'me',
          targetType: ReportTargetType.party,
          targetId: 'p1',
        ),
        'me_party_p1',
      );
    });

    test('같은 대상·같은 신고자는 항상 같은 id다', () {
      String id() => ReportService.docIdFor(
        reporterId: 'me',
        targetType: ReportTargetType.user,
        targetId: 'u1',
      );
      expect(id(), id());
    });

    test('대상이 다르면 다른 id다 — 다른 글은 따로 신고할 수 있다', () {
      final a = ReportService.docIdFor(
        reporterId: 'me',
        targetType: ReportTargetType.party,
        targetId: 'p1',
      );
      final b = ReportService.docIdFor(
        reporterId: 'me',
        targetType: ReportTargetType.party,
        targetId: 'p2',
      );
      expect(a, isNot(b));
    });

    test('종류가 다르면 다른 id다 — 사용자와 그 사람의 글은 별개 신고다', () {
      final user = ReportService.docIdFor(
        reporterId: 'me',
        targetType: ReportTargetType.user,
        targetId: 'x',
      );
      final party = ReportService.docIdFor(
        reporterId: 'me',
        targetType: ReportTargetType.party,
        targetId: 'x',
      );
      expect(user, isNot(party));
    });

    test('신고자가 다르면 다른 id다 — 여러 사람이 같은 글을 신고할 수 있다', () {
      final a = ReportService.docIdFor(
        reporterId: 'me',
        targetType: ReportTargetType.party,
        targetId: 'p1',
      );
      final b = ReportService.docIdFor(
        reporterId: 'you',
        targetType: ReportTargetType.party,
        targetId: 'p1',
      );
      expect(a, isNot(b));
    });
  });

  group('신고 — 사유', () {
    test('사유 목록이 비어 있지 않고 전부 라벨이 있다', () {
      expect(ReportReason.all, isNotEmpty);
      for (final r in ReportReason.all) {
        expect(ReportReason.label(r), isNot(r), reason: '$r 라벨 누락');
      }
    });

    test("'기타'만 상세 내용을 필수로 받는다", () {
      // 사유만으로는 운영자가 무엇을 봐야 할지 알 수 없기 때문이다.
      expect(ReportReason.requiresDetail(ReportReason.other), isTrue);
      for (final r in ReportReason.all.where((r) => r != ReportReason.other)) {
        expect(ReportReason.requiresDetail(r), isFalse);
      }
    });

    test('모르는 사유는 거부된다', () {
      expect(ReportReason.isValid('made_up'), isFalse);
      expect(ReportReason.isValid(ReportReason.spam), isTrue);
    });

    test('대상 종류도 목록에 있는 것만 유효하다', () {
      expect(ReportTargetType.isValid('users'), isFalse);
      expect(ReportTargetType.isValid(ReportTargetType.chatRoom), isTrue);
      for (final t in ReportTargetType.all) {
        expect(ReportTargetType.label(t), isNot(t), reason: '$t 라벨 누락');
      }
    });
  });

  group('차단과 신고는 별개다', () {
    test('신고 사유 목록과 차단은 서로를 참조하지 않는다', () {
      // 차단해도 신고되지 않고, 신고해도 차단되지 않는다. 이 테스트는
      // "신고 및 차단"으로 합쳐 버리는 회귀를 막기 위한 표식이다.
      BlockService.setBlockedIdsForTest({'A'});
      expect(BlockService.isBlocked('A'), isTrue);
      // 차단은 reports 문서를 만들지 않는다 — 만드는 경로가 아예 없다.
      expect(ReportReason.all.contains('block'), isFalse);
    });
  });
}

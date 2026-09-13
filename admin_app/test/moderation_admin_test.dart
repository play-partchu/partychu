// 신고·차단 운영 화면이 지켜야 할 것 — **프라이버시 불변식**과 **키 일치**.
//
// 이 두 가지는 화면을 눈으로 봐서는 깨진 것을 알 수 없다.
//
//   · 프라이버시: 관리자 화면이 차단을 쓰거나 지우는 코드를 갖게 되면
//     "조회 전용"이라는 약속이 조용히 사라진다. 앱 쪽 규칙(차단당한 사실을
//     상대가 알 수 없다)은 그대로인데 운영이 그 관계를 바꾸기 시작하면
//     정책이 두 갈래가 된다.
//
//   · 키 일치: 신고 사유·대상 유형·처리상태 문자열은 앱(party_app)이 문서에
//     **그대로 저장한 값**이다. 관리자에서 키를 새로 만들거나 오타를 내면
//     필터가 조용히 0건이 되고, 배지에 영문 키가 그대로 뜬다.
//
// 화면 위젯을 띄우지 않고 소스를 읽어 확인한다 — 여기서 시험하는 것이 UI가
// 아니라 "무엇이 코드에 있고 없는가"이기 때문이다.
//
// ⚠️ 헬퍼 안에서는 expect/fail을 쓰지 않는다. group 본문(테스트 밖)에서 부르면
// OutsideTestException으로 파일 로드 자체가 실패한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 저장소 안의 파일을 읽는다. 테스트는 admin_app/을 작업 디렉터리로 돈다.
String _read(String relative) {
  final f = File(relative);
  if (!f.existsSync()) {
    throw StateError('파일을 찾지 못했습니다: ${f.absolute.path}');
  }
  return f.readAsStringSync();
}

/// 소스에서 `const _xxxLabels = { 'key': ... }` 꼴의 키를 뽑는다.
Set<String> _mapKeys(String source, String mapName) {
  final start = source.indexOf('const $mapName = {');
  if (start < 0) throw StateError('$mapName 을 찾지 못했습니다');
  final end = source.indexOf('};', start);
  final body = source.substring(start, end);
  return RegExp("'([A-Za-z_]+)':")
      .allMatches(body)
      .map((m) => m.group(1)!)
      .toSet();
}

/// party_app의 모델에서 `static const name = 'value';` 값을 뽑는다.
Set<String> _dartConstValues(String source, {required String className}) {
  final start = source.indexOf('class $className {');
  if (start < 0) throw StateError('$className 을 찾지 못했습니다');
  final end = source.indexOf('\n}', start);
  final body = source.substring(start, end);
  return RegExp(r"static const \w+ = '([A-Za-z_]+)';")
      .allMatches(body)
      .map((m) => m.group(1)!)
      .toSet();
}

void main() {
  final reportsScreen = _read('lib/screens/reports_screen.dart');
  final blocksScreen = _read('lib/screens/blocked_relations_screen.dart');
  final adminService = _read('lib/services/admin_firestore_service.dart');
  final appReasons = _read('../party_app/lib/models/report_reason.dart');

  group('차단 내역 — 조회 전용(프라이버시 불변식)', () {
    test('관리자 화면에 차단을 만들거나 지우는 코드가 없다', () {
      // 관리자가 남의 차단을 대신 풀면, 사용자가 자기 화면을 위해 건 결정을
      // 운영이 뒤집는 것이 된다. 삭제도 이번 범위가 아니다.
      for (final forbidden in ['.delete(', '.set(', '.update(', 'FieldValue']) {
        expect(
          blocksScreen.contains(forbidden),
          isFalse,
          reason: '차단 화면에 쓰기 코드가 생겼습니다: $forbidden',
        );
      }
    });

    test('관리자 서비스의 userBlocks 경로는 조회 하나뿐이다', () {
      final blockLines = adminService
          .split('\n')
          .where((l) => l.contains("'userBlocks'"))
          .toList();
      expect(blockLines.length, 1, reason: 'userBlocks를 만지는 곳이 늘었습니다');
      expect(blockLines.single.contains('collection'), isTrue);
      // 쿼리 정의 한 줄이어야 한다 — 문서 하나를 집어 쓰기로 이어지지 않는다.
      expect(blockLines.single.contains('.doc('), isFalse);
    });

    test('차단 조회는 최신순 정렬이다', () {
      expect(
        adminService.contains(
          "_db.collection('userBlocks').orderBy('createdAt', descending: true)",
        ),
        isTrue,
      );
    });
  });

  group('신고 — 처리상태', () {
    test('요구된 네 가지 상태를 정확히 제공한다', () {
      // 접수됨 / 검토중 / 처리완료 / 기각.
      expect(_mapKeys(reportsScreen, '_statusLabels'), {
        'received',
        'reviewing',
        'resolved',
        'rejected',
      });
    });

    test("앱이 만드는 초기 상태 'received'가 목록에 있다", () {
      // 없으면 앱이 접수한 신고가 상태 배지에서 영문 키로 보인다.
      expect(
        _mapKeys(reportsScreen, '_statusLabels').contains('received'),
        isTrue,
      );
    });

    test('종료 상태로 바꿀 때만 처리 시각을 남긴다', () {
      expect(
        adminService.contains(
          "final closing = status == 'resolved' || status == 'rejected';",
        ),
        isTrue,
      );
    });

    test('신고 수정은 상태·메모·시각만 건드린다 — 대상 문서는 손대지 않는다', () {
      // firestore.rules의 reports update가 허용하는 필드 집합과 같아야 한다.
      // 여기에 다른 컬렉션 쓰기가 끼면 "신고 = 자동 제재"가 된다.
      final start = adminService.indexOf('static Future<void> updateReport(');
      expect(start, isNot(-1));
      final body = adminService.substring(start, start + 900);
      expect(body.contains("collection('reports')"), isTrue);
      for (final other in [
        "collection('parties')",
        "collection('users')",
        "collection('userBlocks')",
      ]) {
        expect(body.contains(other), isFalse, reason: '신고 처리가 $other 를 건드립니다');
      }
    });
  });

  group('신고 — 앱과 키가 같다', () {
    test('사유 키가 앱의 ReportReason과 정확히 같다', () {
      expect(
        _mapKeys(reportsScreen, '_reasonLabels'),
        _dartConstValues(appReasons, className: 'ReportReason'),
      );
    });

    test('대상 유형 키가 앱의 ReportTargetType과 정확히 같다', () {
      expect(
        _mapKeys(reportsScreen, '_targetTypeLabels'),
        _dartConstValues(appReasons, className: 'ReportTargetType'),
      );
    });
  });

  group('새 컬렉션을 만들지 않았다', () {
    test('신고·차단은 reports와 userBlocks를 그대로 쓴다', () {
      final collections = RegExp(r"collection\('(\w+)'\)")
          .allMatches(adminService)
          .map((m) => m.group(1)!)
          .toSet();
      expect(collections.contains('reports'), isTrue);
      expect(collections.contains('userBlocks'), isTrue);
      for (final invented in [
        'blocks',
        'userReports',
        'blockedUsers',
        'moderation',
      ]) {
        expect(
          collections.contains(invented),
          isFalse,
          reason: '새 컬렉션이 생겼습니다: $invented',
        );
      }
    });
  });
}

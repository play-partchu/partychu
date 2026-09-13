// 마이페이지 프로필 머리 — 닉네임 아래에 **UID를 찍지 않는다**.
//
// 예전에는 닉네임과 '본인인증 완료' 배지 사이에 Firebase UID가 그대로
// 있었다(`참가자테스트(TEST)` / `lekxmk…kb62` / `본인인증 완료`). 사용자에게는
// 뜻 없는 문자열인데 프로필 맨 위에 있어서 문의 글·스크린샷에 함께 옮겨 다녔다.
//
// ⚠️ 이건 **표시만** 끄는 변경이다. [UserSession.userId] 자체는 그대로 살아
//    있어야 한다 — Firestore 조회·본인인증·신청/예약/문의가 전부 그 값을
//    쓴다. 그래서 이 파일은 "화면에서 안 그린다"와 "값은 그대로다"를 함께
//    지킨다(한쪽만 지키면 UID를 지우는 방향으로 고쳐질 수 있다).
//
// 화면은 Firebase 없이 그릴 수 없어서 소스 가드로 확인한다
// — account_ux_test.dart와 같은 방식이다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String path) => File(path).readAsStringSync();

void main() {
  final myPage = _src('lib/screens/my_page_screen.dart');

  /// 프로필 머리(_buildProfileHeader)만 잘라낸다 — 아래쪽 메뉴들이 쓰는
  /// UserSession.userId(로그인 여부 판정 등)까지 싸잡아 금지하면 안 된다.
  final header = myPage.substring(
    myPage.indexOf('Widget _buildProfileHeader()'),
    myPage.indexOf('Future<void> _editNickname()'),
  );

  group('프로필 머리에 UID를 그리지 않는다', () {
    test('닉네임 아래 줄에서 userId를 텍스트로 쓰지 않는다', () {
      // 예전 코드: Text(loggedIn ? UserSession.userId : '로그인 후 …')
      expect(header.contains('UserSession.userId :'), isFalse);
      expect(header.contains('? UserSession.userId'), isFalse);
      expect(header.contains('Text(UserSession.userId'), isFalse);
      expect(header.contains(r'${UserSession.userId}'), isFalse);
    });

    test('로그인 판정에는 여전히 userId를 쓴다 — 값을 지운 게 아니다', () {
      expect(
        header.contains('final loggedIn = UserSession.userId.isNotEmpty;'),
        isTrue,
      );
      // 내부 식별자는 앱 전체가 계속 쓴다(조회·인증·신청·예약·문의).
      expect('UserSession.userId'.allMatches(myPage).length, greaterThan(1));
    });

    test('닉네임 다음은 본인인증 배지다 — 사이에 다른 줄이 없다', () {
      final nickname = header.indexOf('UserSession.nickname');
      // 배지 자체의 시작 — 로그인 계정에서 닉네임 다음에 오는 유일한 것.
      final badge = header.indexOf('if (loggedIn) ...[');
      expect(nickname, greaterThan(-1));
      expect(badge, greaterThan(nickname));
      // 그 사이에 남은 Text 위젯이 없어야 한다(UID 줄이 되살아난 경우를 잡는다).
      // 닉네임 줄의 나머지(연필 아이콘까지)만 있고, 새 Text는 없어야 한다.
      final between = header.substring(nickname, badge);
      expect(between.contains('Text('), isFalse);
    });

    test('간격은 한 칸으로 정리했다 — 지운 줄의 여백이 남지 않는다', () {
      // 예전: 닉네임 → SizedBox(2) → UID → SizedBox(6) → 배지.
      // 지금: 닉네임 → SizedBox(6) → 배지.
      // 줄바꿈·들여쓰기는 서식이라 지운다(CRLF·포매터에 흔들리지 않게).
      final flat = header.replaceAll(RegExp(r'\s+'), ' ');
      expect(
        flat.contains('if (loggedIn) ...[ const SizedBox(height: 6), Container('),
        isTrue,
      );
    });

    test('로그인 전 안내 문구는 그대로 남는다', () {
      // 이 줄까지 지우면 로그인 전 프로필에 '로그인 필요' 한 줄만 남는다.
      expect(header.contains("'로그인 후 프로필을 설정할 수 있어요'"), isTrue);
    });
  });

  test('일반 사용자 화면 어디에도 UID를 그리는 자리가 없다', () {
    // 관리자 화면(lib/admin)은 예외다 — 거기서는 UID가 실제로 일하는 값이다.
    final userFacing = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.replaceAll(r'\', '/').contains('lib/admin/'));

    final offenders = <String>[];
    for (final file in userFacing) {
      final src = file.readAsStringSync();
      for (final pattern in [
        RegExp(r'Text\(\s*UserSession\.userId'),
        RegExp(r'Text\(\s*[^)\n]{0,40}\buid\b\s*[,)]'),
        RegExp(r"'[^'\n]*UID[^'\n]*\$\{?\w*(uid|[Uu]serId)"),
      ]) {
        if (pattern.hasMatch(src)) offenders.add(file.path);
      }
    }
    expect(offenders, isEmpty);
  });
}

// 🍎 Apple App Review 심사용 로그인 경로.
//
// 여기서 지키는 것은 **입구의 범위**다. 이 경로는 심사관을 들여보내기 위한
// 것이고, 조금만 넓어지면 "아무 이메일로나 로그인되는 앱"이 된다 — 소셜
// 로그인만으로 1인 1계정을 지키던 구조에 우회로가 생긴다.
//
// 그리고 **비밀번호가 앱에 남지 않는지**를 소스로 확인한다. 예전에 Debug
// 시트가 심사 계정 비밀번호를 문자열로 들고 있었다.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/utils/app_review_login.dart';
import 'package:party_app/utils/root_gate.dart';
import 'package:party_app/utils/user_session.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('플랫폼 — iOS에서만 열린다', () {
    final original = debugDefaultTargetPlatformOverride;
    tearDown(() => debugDefaultTargetPlatformOverride = original);

    test('iOS면 열린다', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(AppReviewLogin.isAvailable, isTrue);
    });

    test('Android·macOS·Windows에서는 닫혀 있다 — 기존 동작 그대로다', () {
      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(
          AppReviewLogin.isAvailable,
          isFalse,
          reason: '$platform에 심사용 입구가 생겼다',
        );
      }
    });

    test('kIsWeb이 판정에 들어 있다 — 웹에는 열리지 않는다', () {
      // 웹 테스트는 VM에서 kIsWeb을 바꿀 수 없어 소스로 확인한다.
      final src = _read('lib/utils/app_review_login.dart');
      expect(src, contains('!kIsWeb'));
      expect(src, contains('TargetPlatform.iOS'));
    });
  });

  group('허용 계정만 통과한다', () {
    test('심사용 두 계정은 통과', () {
      expect(AppReviewLogin.isAllowedEmail('host@test.com'), isTrue);
      expect(AppReviewLogin.isAllowedEmail('guest@test.com'), isTrue);
    });

    test('공백·대문자는 받아 준다 — 키보드가 첫 글자를 올려도 막히지 않게', () {
      expect(AppReviewLogin.isAllowedEmail('  host@test.com  '), isTrue);
      expect(AppReviewLogin.isAllowedEmail('Host@Test.com'), isTrue);
      expect(AppReviewLogin.isAllowedEmail('GUEST@TEST.COM'), isTrue);
      expect(AppReviewLogin.normalizeEmail(' Host@Test.com '), 'host@test.com');
    });

    test('그 밖의 주소는 전부 거부 — 일반 이메일 로그인이 아니다', () {
      for (final email in [
        'someone@test.com',
        'host@test.com.attacker.io',
        'attacker.io/host@test.com',
        'host@example.com',
        'admin@test.com',
        'host+1@test.com',
        'host@test.co',
        '',
        '   ',
        'host',
      ]) {
        expect(
          AppReviewLogin.isAllowedEmail(email),
          isFalse,
          reason: '"$email"이 심사용 입구를 통과했다',
        );
      }
    });

    test('허용 목록은 딱 둘이다 — 조용히 늘어나면 여기서 걸린다', () {
      expect(AppReviewLogin.allowedEmails, {'host@test.com', 'guest@test.com'});
    });
  });

  group('비밀번호가 앱에 남지 않는다', () {
    test('심사용 코드에 비밀번호 필드·상수가 없다', () {
      final src = _read('lib/utils/app_review_login.dart');
      expect(src.contains('password'), isFalse);
      // 허용 목록은 **주소**만 담는다.
      expect(src, contains('allowedEmails'));
    });

    test('로그인 화면이 비밀번호를 미리 채우지 않는다', () {
      final src = _read('lib/login.dart');
      // 예전 Debug 시트가 들고 있던 값들. 어떤 형태로든 다시 들어오면 막는다.
      expect(
        RegExp(r"passwordCtrl\.text\s*=\s*'").hasMatch(src),
        isFalse,
        reason: '비밀번호를 코드에서 입력칸에 채우고 있다 — 바이너리에 문자열로 남는다',
      );
      expect(
        src.contains('TextEditingController(text: '),
        isTrue,
        reason: '이메일 미리채움은 그대로 있어야 한다',
      );
    });

    test('계정 생성 스크립트도 환경변수로만 받는다', () {
      final src = _read('../functions/scripts/createTestAccounts.js');
      expect(src, contains('TEST_HOST_PASSWORD'));
      expect(src, contains('TEST_GUEST_PASSWORD'));
      // 값이 없으면 멈춘다(빈 비밀번호로 심사 계정을 덮어쓰지 않는다).
      expect(src, contains('passwordOf'));
      expect(
        RegExp(r"password:\s*'").hasMatch(src),
        isFalse,
        reason: '스크립트에 비밀번호가 다시 박혔다',
      );
    });
  });

  group('본인확인 판정은 손대지 않았다', () {
    // 심사용 계정이 메인으로 들어가는 것은 **Firestore 문서가 실제로 인증
    // 완료이기 때문**이어야 한다. 클라이언트가 상태를 참으로 만드는 길이
    // 생기면 1인 1계정 구조가 무너진다.

    test('인증 완료 계정은 메인으로 — 심사용 계정이 NICE 화면에 걸리지 않는다', () {
      expect(
        resolveRootGateScreen(
          isLoggedIn: true,
          accountStatus: 'active',
          identityStatus: IdentityStatus.verified,
          allowUnverifiedMember: false,
        ),
        RootGateScreen.main,
      );
    });

    test('미인증 계정은 이 경로로 들어와도 여전히 본인확인 화면이다', () {
      expect(
        resolveRootGateScreen(
          isLoggedIn: true,
          accountStatus: 'active',
          identityStatus: IdentityStatus.unverified,
          allowUnverifiedMember: false,
        ),
        RootGateScreen.identityVerification,
      );
    });

    test('심사용 코드가 본인확인 상태를 건드리지 않는다', () {
      final src = _read('lib/utils/app_review_login.dart');
      for (final token in [
        'identityVerified',
        'isVerified',
        'identityStatus',
        'accountStatus',
      ]) {
        // **대입**만 잡는다 — 주석의 `identityVerified == true`는 설명이라
        // 괜찮고, 값을 바꾸는 코드가 있으면 안 된다.
        expect(
          RegExp('$token\\s*=(?!=)').hasMatch(src),
          isFalse,
          reason: '심사용 코드가 $token에 값을 쓰고 있다',
        );
      }
      // 세션·게이트를 아예 import하지 않는다 — 손댈 수단 자체가 없다.
      expect(src.contains("import 'package:party_app/utils/"), isFalse);
    });

    test('루트 게이트의 우회 스위치는 Android Debug 전용 그대로다', () {
      final src = _read('lib/utils/root_gate.dart');
      expect(
        src,
        contains(
          'kDebugMode && !kIsWeb && defaultTargetPlatform == TargetPlatform.android',
        ),
        reason: 'socialLoginTestMode의 범위가 바뀌었다 — iOS 운영에 미인증 통과가 열린다',
      );
      // 심사용 입구가 이 스위치를 건드리지 않는다.
      expect(src.contains('AppReviewLogin'), isFalse);
    });
  });

  group('기존 로그인 수단은 그대로다', () {
    final src = _read('lib/login.dart');

    test('Apple·Google·카카오·네이버 진입점이 모두 남아 있다', () {
      for (final entry in [
        'signInWithApple',
        'signInWithGoogle',
        'signInWithKakao',
        'signInWithNaver',
      ]) {
        expect(src, contains(entry), reason: '$entry이 사라졌다');
      }
    });

    test('Apple 버튼은 여전히 AppleSignIn.isAvailable로만 열린다', () {
      expect(src, contains('if (AppleSignIn.isAvailable) ...['));
      expect(src, contains("label: 'Apple로 계속하기'"));
    });

    test('심사용 입구는 플랫폼으로만 가린다 — kDebugMode 안에 들어가면 안 된다', () {
      // 들여쓰기를 지운 뒤, 심사용 블록이 Debug 블록 **앞**에 독립해 있는지 본다.
      final flat = src.replaceAll(RegExp(r'[ \t]+'), ' ');
      final review = flat.indexOf('if (AppReviewLogin.isAvailable) ...[');
      final debug = flat.indexOf('if (kDebugMode) ...[');
      expect(review, greaterThan(-1), reason: '심사용 입구가 없다');
      expect(debug, greaterThan(-1), reason: 'Debug 입구가 사라졌다');
      expect(
        review,
        lessThan(debug),
        reason: '심사용 입구가 Debug 블록 안으로 들어갔다 — Release에서 사라진다',
      );
    });

    test('심사용 로그인도 소셜과 같은 성공 경로를 탄다', () {
      // 별도 경로를 새로 만들면 푸시 등록·recordLogin·게이트 재평가가 빠진다.
      expect(src, contains('Future<void> signInForAppReview('));
      expect(src, contains('await signInWithEmail('));
      expect(src, contains('AppReviewLogin.isAllowedEmail(email)'));
    });

    test('심사용 경로는 signupProvider를 쓰지 않는다 — 규칙 허용값이 아니다', () {
      // firestore.rules의 signupProvider는 google·kakao·naver·apple만 받는다.
      final rules = _read('../firestore.rules');
      expect(rules.contains("'email'"), isFalse);
      // signInWithEmail은 provider 없이 _onLoginSuccess를 부른다.
      expect(src, contains('await _onLoginSuccess(context);'));
    });
  });
}

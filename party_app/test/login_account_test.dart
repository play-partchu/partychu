import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/utils/login_account.dart';

// 마이페이지 "로그인 계정" 판정 — Sign in with Apple 추가와 기존 제공자 회귀.
void main() {
  group('Apple', () {
    test('providerData에 apple.com이 있으면 Apple — 가리기 이메일도 그대로 보여준다', () {
      final a = resolveLoginAccount(
        uid: 'firebaseUid1',
        providerIds: const ['apple.com'],
        authEmail: 'abc123@privaterelay.appleid.com',
      );
      expect(a?.provider, LoginProvider.apple);
      expect(a?.email, 'abc123@privaterelay.appleid.com');
    });

    test('재로그인에서 Apple이 이메일·이름을 주지 않아도 저장된 users.email로 판정된다', () {
      final a = resolveLoginAccount(
        uid: 'firebaseUid1',
        providerIds: const ['apple.com'],
        storedEmail: 'abc123@privaterelay.appleid.com',
      );
      expect(a?.provider, LoginProvider.apple);
      expect(a?.email, 'abc123@privaterelay.appleid.com');
    });

    test('이메일이 전혀 없으면 "Apple 계정으로 로그인됨"', () {
      final a = resolveLoginAccount(uid: 'u', providerIds: const ['apple.com']);
      expect(a?.hasEmail, isFalse);
      expect(a?.signedInText, 'Apple 계정으로 로그인됨');
    });

    test('providerData가 비어 있으면 signupProvider apple로 폴백한다', () {
      final a = resolveLoginAccount(uid: 'u', signupProvider: 'apple');
      expect(a?.provider, LoginProvider.apple);
    });

    test('다른 제공자의 socialAccount 이메일은 Apple 계정에 섞이지 않는다', () {
      final a = resolveLoginAccount(
        uid: 'u',
        providerIds: const ['apple.com'],
        authEmail: 'me@icloud.com',
        socialAccountProvider: 'naver',
        socialAccountEmail: 'other@naver.com',
      );
      expect(a?.email, 'me@icloud.com');
    });
  });

  group('기존 제공자 판정은 그대로다', () {
    test('카카오 uid 접두어 + socialAccount 이메일 우선', () {
      final a = resolveLoginAccount(
        uid: 'kakao:123',
        authEmail: 'old@kakao.com',
        socialAccountProvider: 'kakao',
        socialAccountEmail: 'new@kakao.com',
      );
      expect(a?.provider, LoginProvider.kakao);
      expect(a?.email, 'new@kakao.com');
    });

    test('네이버 uid 접두어', () {
      final a = resolveLoginAccount(uid: 'naver:abc', storedEmail: 'n@naver.com');
      expect(a?.provider, LoginProvider.naver);
      expect(a?.email, 'n@naver.com');
    });

    test('google.com providerData', () {
      final a = resolveLoginAccount(
        uid: 'g1',
        providerIds: const ['google.com'],
        authEmail: 'g@gmail.com',
      );
      expect(a?.provider, LoginProvider.google);
      expect(a?.email, 'g@gmail.com');
    });

    test('signupProvider 폴백(google·kakao·naver)', () {
      expect(resolveLoginAccount(uid: 'u', signupProvider: 'google')?.provider, LoginProvider.google);
      expect(resolveLoginAccount(uid: 'u', signupProvider: 'kakao')?.provider, LoginProvider.kakao);
      expect(resolveLoginAccount(uid: 'u', signupProvider: 'naver')?.provider, LoginProvider.naver);
    });

    test('password는 이메일, 알 수 없으면 null', () {
      expect(resolveLoginAccount(uid: 'u', providerIds: const ['password'])?.provider, LoginProvider.email);
      expect(resolveLoginAccount(uid: 'u'), isNull);
      expect(resolveLoginAccount(uid: ''), isNull);
    });
  });
}

import 'dart:async';

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/utils/register_validation.dart';
import 'package:party_app/widgets/party_form/register_missing_fields_banner.dart';

void main() {
  group('실패 원인 구분', () {
    test('권한 오류는 재로그인을 안내한다', () {
      final msg = RegisterValidation.failureMessage(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
        stage: '등록 정보 저장',
      );
      expect(msg, contains('로그인'));
      // 예외 원문/코드가 그대로 노출되면 안 된다.
      expect(msg.contains('permission-denied'), isFalse);
    });

    test('인증 만료', () {
      expect(
        RegisterValidation.failureMessage(
          FirebaseException(plugin: 'cloud_firestore', code: 'unauthenticated'),
        ),
        contains('로그인이 만료'),
      );
    });

    test('네트워크 계열은 연결 확인을 안내한다', () {
      for (final code in ['unavailable', 'deadline-exceeded']) {
        expect(
          RegisterValidation.failureMessage(
            FirebaseException(plugin: 'cloud_firestore', code: code),
          ),
          contains('네트워크'),
          reason: code,
        );
      }
      expect(
        RegisterValidation.failureMessage(TimeoutException('x')),
        contains('네트워크'),
      );
    });

    test('분류되지 않은 Firebase 오류는 코드만 덧붙인다', () {
      final msg = RegisterValidation.failureMessage(
        FirebaseException(
          plugin: 'cloud_firestore',
          code: 'invalid-argument',
          message: 'Invalid data. Unsupported field value',
        ),
        stage: '등록 정보 저장',
      );
      expect(msg, contains('등록 정보 저장 중'));
      expect(msg, contains('(invalid-argument)'));
      // 서버 메시지 원문은 포함하지 않는다.
      expect(msg.contains('Unsupported field value'), isFalse);
    });

    test('알 수 없는 예외 — 단계가 있으면 단계를, 없으면 기본 문구를 쓴다', () {
      expect(
        RegisterValidation.failureMessage(Exception('boom'), stage: '사진 업로드'),
        '사진 업로드 중 문제가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
      expect(
        RegisterValidation.failureMessage(Exception('boom')),
        RegisterValidation.submitFailedMessage,
      );
    });
  });

  group('누락 항목 목록', () {
    test('비어 있는 항목의 문구만 모은다', () {
      expect(
        RegisterValidation.missingMessages(const [
          RegisterFieldCheck(missing: true, message: '주소를 입력해주세요.'),
          RegisterFieldCheck(missing: false, message: '채워짐'),
          RegisterFieldCheck(missing: true, message: '대표 사진을 설정해주세요.'),
        ]),
        ['주소를 입력해주세요.', '대표 사진을 설정해주세요.'],
      );
    });
  });

  group('누락 항목 배너', () {
    testWidgets('목록이 비면 아무것도 그리지 않는다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: RegisterMissingFieldsBanner(fields: [])),
        ),
      );
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('빠진 항목을 모두 보여준다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RegisterMissingFieldsBanner(
              fields: [
                RegisterFieldCheck(missing: true, message: '주소를 입력해주세요.'),
                RegisterFieldCheck(missing: true, message: '대표 사진을 설정해주세요.'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('아직 입력하지 않은 필수 항목이 2개 있어요'), findsOneWidget);
      expect(find.text('주소를 입력해주세요.'), findsOneWidget);
      expect(find.text('대표 사진을 설정해주세요.'), findsOneWidget);
    });

    testWidgets('1개일 때는 개수를 붙이지 않는다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RegisterMissingFieldsBanner(
              fields: [
                RegisterFieldCheck(missing: true, message: '주소를 입력해주세요.'),
              ],
            ),
          ),
        ),
      );
      expect(find.text('아직 입력하지 않은 필수 항목이 있어요'), findsOneWidget);
    });
  });
}

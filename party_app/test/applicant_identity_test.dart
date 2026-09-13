import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/utils/applicant_identity.dart';

/// 호스트가 **입장 확인의 근거**로 삼는 두 값 — 본인확인 완료 여부와 실명.
///
/// 배지가 틀리면 호스트가 신분증을 대조할 이유 자체가 흔들리므로, 서버 응답을
/// 그대로 받아들이는 경로와 옛 응답 폴백을 함께 못박아 둔다.
/// 서버 쪽 판정은 functions/applicantIdentity.js의 `verified`다.
void main() {
  Map<Object?, Object?> payload({
    bool? verified,
    String name = '',
    String gender = '',
    int? birthYear,
    String nickname = '냥냥이',
  }) => {
    'available': true,
    if (verified != null) 'verified': verified,
    'nickname': nickname,
    'name': name,
    'gender': gender,
    'birthYear': birthYear,
  };

  group('본인확인 완료 여부', () {
    test('서버가 내려준 verified를 그대로 쓴다', () {
      final v = ApplicantIdentity.fromMap(
        payload(verified: true, name: '홍길동', gender: 'male', birthYear: 1991),
      );
      expect(v.verified, isTrue);

      final u = ApplicantIdentity.fromMap(payload(verified: false));
      expect(u.verified, isFalse);
    });

    test('본인확인은 했는데 성별이 비어 있어도 완료로 읽는다', () {
      // 예전 판정('성별이 비면 미확인')이 틀리는 자리 — 이 사람에게 '미확인'
      // 배지를 붙이면 호스트가 멀쩡한 신청자의 입장을 막게 된다.
      final v = ApplicantIdentity.fromMap(payload(verified: true, name: '홍길동'));
      expect(v.verified, isTrue);
      expect(v.verifiedName, '홍길동');
    });

    test('verified가 없는 옛 응답은 실려 온 값으로 물러선다', () {
      // 배포가 어긋난 사이 멀쩡한 신청자가 전부 '미확인'으로 보이면 안 된다.
      expect(ApplicantIdentity.fromMap(payload(name: '홍길동')).verified, isTrue);
      expect(
        ApplicantIdentity.fromMap(payload(gender: 'female')).verified,
        isTrue,
      );
      expect(
        ApplicantIdentity.fromMap(payload(birthYear: 1991)).verified,
        isTrue,
      );
      // 실명·성별·생년이 모두 비면 본인확인 전이다.
      expect(ApplicantIdentity.fromMap(payload()).verified, isFalse);
    });

    test('탈퇴·정보 없음은 확인 여부를 말하지 않는다', () {
      expect(ApplicantIdentity.withdrawn.verified, isFalse);
      expect(ApplicantIdentity.unknown.verified, isFalse);
      expect(ApplicantIdentity.fromMap({'available': false}).verified, isFalse);
    });
  });

  group('입장 확인용 실명', () {
    test('본인확인을 마쳤고 실명이 있으면 그 값', () {
      final v = ApplicantIdentity.fromMap(payload(verified: true, name: '홍길동'));
      expect(v.verifiedName, '홍길동');
    });

    test('본인확인 전이면 null — 줄 자체가 빠진다', () {
      expect(
        ApplicantIdentity.fromMap(payload(verified: false)).verifiedName,
        isNull,
      );
    });

    test('확인은 했지만 실명이 비어 있으면 null', () {
      expect(
        ApplicantIdentity.fromMap(payload(verified: true)).verifiedName,
        isNull,
      );
    });

    test('탈퇴한 계정은 null', () {
      expect(ApplicantIdentity.withdrawn.verifiedName, isNull);
    });
  });

  group('노출 범위', () {
    test('생년월일 전체는 어떤 표시 문구에도 들어가지 않는다', () {
      final v = ApplicantIdentity.fromMap({
        'available': true,
        'verified': true,
        'nickname': '냥냥이',
        'name': '홍길동',
        'gender': 'female',
        'birthYear': 1991,
        'birthMonth': 3,
        'birthDay': 7,
      });
      final label = v.displayLabel(DateTime(2026, 8, 22));
      // 연도 뒤 두 자리와 만 나이까지만 — 월·일은 나이 계산에만 쓰인다.
      expect(label, '여성 · 냥냥이(홍길동) · 91년생 (35세)');
      expect(label.contains('3월'), isFalse);
      expect(label.contains('1991'), isFalse);
      expect(v.personLabel, '냥냥이(홍길동)');
      expect(v.verifiedName, '홍길동');
    });
  });
}

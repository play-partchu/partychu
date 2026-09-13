// 통합 QR 체크인의 **공용 결과**가 서버 응답에서 제대로 만들어지는지.
//
// 화면이 하나뿐이므로 이 변환이 틀리면 세 유형이 전부 틀린다. 특히
//   · 나이는 서버가 보내지 않는다(생년월일로 화면이 계산한다)
//   · 권한 없음/없는 QR 응답에는 아무 정보도 없어야 한다
// 두 가지는 개인정보와 직결되므로 못 박아 둔다.

import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/check_in_result.dart';
import 'package:party_app/utils/applicant_identity.dart';

Map<Object?, Object?> serverGuest({bool verified = true}) => {
  'available': true,
  'verified': verified,
  'nickname': '파티러',
  'name': verified ? '박파티' : '',
  'gender': verified ? 'male' : '',
  'birthYear': verified ? 1991 : null,
  'birthMonth': verified ? 3 : null,
  'birthDay': verified ? 2 : null,
};

void main() {
  group('유형 판별', () {
    test('서버 저장값 그대로 읽는다', () {
      expect(CheckInDomain.fromKey('party'), CheckInDomain.party);
      expect(
        CheckInDomain.fromKey('place_reservation'),
        CheckInDomain.reservation,
      );
      expect(CheckInDomain.fromKey('product_voucher'), CheckInDomain.voucher);
    });

    test('모르는 값·null은 unknown으로 물러선다 — 앱이 서버보다 오래된 경우', () {
      expect(CheckInDomain.fromKey('something_new'), CheckInDomain.unknown);
      expect(CheckInDomain.fromKey(null), CheckInDomain.unknown);
    });

    test('상태를 모르면 잠그는 쪽으로 물러선다', () {
      expect(CheckInStatus.fromKey('ready'), CheckInStatus.ready);
      expect(CheckInStatus.fromKey('done'), CheckInStatus.done);
      expect(
        CheckInStatus.fromKey(null),
        CheckInStatus.blocked,
        reason: '모르면 열지 말고 막아야 한다',
      );
    });
  });

  group('파티', () {
    final r = CheckInResult.fromMap({
      'ok': true,
      'domain': 'party',
      'checkInStatus': 'ready',
      'blockReason': null,
      'guest': serverGuest(),
      'title': '루프탑 파티',
      'subtitle': '강남구 역삼동',
      'atMs': DateTime(2026, 8, 30, 19).millisecondsSinceEpoch,
      'people': 1,
      'paymentMethod': 'bank_transfer',
      'paymentStatus': 'paid',
      'paymentAmount': 30000,
      'detail': {'applicationStatus': 'approved'},
    });

    test('상단 축이 그대로 채워진다', () {
      expect(r.ok, isTrue);
      expect(r.domain, CheckInDomain.party);
      expect(r.status, CheckInStatus.ready);
      expect(r.title, '루프탑 파티');
      expect(r.at, DateTime(2026, 8, 30, 19));
      expect(r.people, 1);
      expect(r.paymentMethod, 'bank_transfer');
      expect(r.detail['applicationStatus'], 'approved');
    });

    test('나이는 서버 값이 아니라 생년월일로 계산한다', () {
      final g = r.guest!;
      // 서버 응답에 age가 없어도 화면이 만 나이를 만든다.
      expect(g.ageAt(DateTime(2026, 8, 30)), 35);
      // 생일 전이면 한 살 적다 — 저장값이었다면 이 구분이 불가능하다.
      expect(g.ageAt(DateTime(2026, 3, 1)), 34);
    });

    test('호스트 전용 실명 정본을 그대로 쓴다', () {
      expect(r.guest!.verified, isTrue);
      expect(r.guest!.verifiedName, '박파티');
      expect(r.guest!.personLabel, '파티러(박파티)');
    });

    test('본인확인 전이면 실명이 없다 — 서버가 애초에 비워 보낸다', () {
      final unverified = CheckInResult.fromMap({
        'domain': 'party',
        'guest': serverGuest(verified: false),
      });
      expect(unverified.guest!.verified, isFalse);
      expect(unverified.guest!.verifiedName, isNull);
      expect(unverified.guest!.ageAt(DateTime(2026, 8, 30)), isNull);
    });
  });

  group('예약', () {
    test('숙박은 시작·종료가 함께 온다', () {
      final r = CheckInResult.fromMap({
        'ok': true,
        'domain': 'place_reservation',
        'checkInStatus': 'ready',
        'guest': serverGuest(),
        'title': '한강뷰 파티룸',
        'subtitle': '디럭스룸',
        'atMs': DateTime(2026, 8, 30, 16).millisecondsSinceEpoch,
        'endAtMs': DateTime(2026, 8, 31, 11).millisecondsSinceEpoch,
        'people': 4,
        'detail': {'nights': 1},
      });
      expect(r.at, DateTime(2026, 8, 30, 16));
      expect(r.endAt, DateTime(2026, 8, 31, 11));
      expect(r.people, 4);
      expect(r.detail['nights'], 1);
    });
  });

  group('이용권', () {
    test('현장결제 대기는 막히되 결제 확인 버튼이 열린다', () {
      final r = CheckInResult.fromMap({
        'ok': false,
        'domain': 'product_voucher',
        'checkInStatus': 'blocked',
        'blockReason': '현장 결제가 아직 확인되지 않았어요.',
        'guest': serverGuest(),
        'title': '루프탑 바',
        'subtitle': '입장권',
        'quantity': 2,
        'paymentMethod': 'on_site',
        'paymentStatus': 'on_site_scheduled',
        'paymentAmount': 40000,
        'canConfirmPayment': true,
      });
      expect(r.ok, isFalse, reason: '결제 전에는 사용 처리를 열면 안 된다');
      expect(r.status, CheckInStatus.blocked);
      expect(r.canConfirmPayment, isTrue);
      expect(r.quantity, 2);
      expect(r.paymentAmount, 40000);
    });

    test('이미 사용한 이용권은 처리 시각을 함께 보여준다', () {
      final usedAt = DateTime(2026, 8, 28, 19, 32);
      final r = CheckInResult.fromMap({
        'ok': false,
        'domain': 'product_voucher',
        'checkInStatus': 'done',
        'blockReason': '이미 사용한 이용권이에요.',
        'guest': serverGuest(),
        'title': '루프탑 바',
        'checkedInAtMs': usedAt.millisecondsSinceEpoch,
      });
      expect(r.status, CheckInStatus.done);
      expect(r.ok, isFalse);
      expect(r.checkedInAt, usedAt);
      expect(r.blockReason, '이미 사용한 이용권이에요.');
    });
  });

  group('권한 없음 · 없는 QR', () {
    test('아무 정보도 실려 오지 않는다', () {
      final r = CheckInResult.fromMap({
        'ok': false,
        'domain': null,
        'checkInStatus': 'blocked',
        'blockReason': '이 QR을 확인할 권한이 없어요.',
        'guest': null,
      });
      expect(r.ok, isFalse);
      expect(r.guest, isNull);
      expect(r.title, isEmpty);
      expect(r.isEmpty, isTrue);
      expect(r.domain, CheckInDomain.unknown);
      expect(r.blockReason, '이 QR을 확인할 권한이 없어요.');
    });

    test('탈퇴한 회원은 uid가 아니라 안내 문구로 그려진다', () {
      final r = CheckInResult.fromMap({
        'domain': 'party',
        'guest': {'available': false},
      });
      expect(r.guest!.state, ApplicantIdentityState.withdrawn);
      expect(r.guest!.personLabel, ApplicantIdentity.withdrawnLabel);
    });
  });
}

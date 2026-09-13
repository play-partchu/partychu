// 마이페이지 '환불 계좌 관리' 줄의 **상태 표시**.
//
// 사업자 인증·입금받을 계좌와 같은 모양('인증 완료 · 카카오뱅크 ****1234')을
// 쓰되, 그 문구는 화면이 만들어 내는 것이 아니라 **저장된 값의 판정 결과**여야
// 한다. 그래서 이 파일이 지키는 것은 두 가지다.
//
//   ① 인증 완료 판정 — [RefundAccountService.stateOfUserDoc]가 서버
//      (refundAccountVerify.statusOf)와 같은 조건을 본다.
//   ② 마스킹 — 계좌번호는 뒤 네 자리만, 수취계좌와 **같은 함수**로.
//
// 화면 자체(StreamBuilder)는 Firestore 없이 그릴 수 없으므로, 줄을 만드는
// 규칙이 화면 안으로 다시 새어 들어가지 않았는지는 소스로 확인한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/bank_codes.dart';
import 'package:party_app/models/payout_account.dart';
import 'package:party_app/services/refund_account_service.dart';

/// 인증까지 마친 계좌가 들어 있는 users 문서.
Map<String, dynamic> _verifiedDoc({
  String bankCode = '090',
  String bankName = '카카오뱅크',
  String accountNumber = '3333019991234',
  String accountHolder = '홍길동',
  String status = 'verified',
}) => {
  'refundAccount': {
    'bankCode': bankCode,
    'bankName': bankName,
    'accountNumber': accountNumber,
    'accountHolder': accountHolder,
  },
  'refundAccountVerification': {
    'status': status,
    'accountFingerprint': 'server-side-hash',
  },
};

void main() {
  group('인증 완료 판정', () {
    test('계좌 + verified + 기관코드가 모두 있으면 인증 완료', () {
      final state = RefundAccountService.stateOfUserDoc(_verifiedDoc());
      expect(state.isVerified, isTrue);
      expect(state.status, RefundAccountStatus.verified);
      expect(state.account!.bankName, '카카오뱅크');
    });

    test('인증 기록이 없으면 인증 완료가 아니다 — 계좌만 있는 상태', () {
      final doc = _verifiedDoc()..remove('refundAccountVerification');
      final state = RefundAccountService.stateOfUserDoc(doc);
      expect(state.isVerified, isFalse);
      expect(state.status, RefundAccountStatus.required);
      // 계좌 자체는 읽힌다 — 화면이 "인증 필요"를 말할 수 있어야 한다.
      expect(state.account, isNotNull);
    });

    test('인증에 실패한 계좌는 인증 완료가 아니다', () {
      final doc = _verifiedDoc(status: 'required');
      doc['refundAccountVerification']['failReason'] = 'holderMismatch';
      final state = RefundAccountService.stateOfUserDoc(doc);
      expect(state.isVerified, isFalse);
      expect(state.failReason, 'holderMismatch');
    });

    test('기관코드 없이 저장된 옛 계좌는 인증 완료로 치지 않는다', () {
      // 자유 입력 시절 계좌 — 성명조회를 거친 적이 없다. 서버도 같은 판정이다
      // (refundAccountVerify.normalizeVerifiedRefundAccount → null → none).
      final doc = _verifiedDoc(bankCode: '');
      final state = RefundAccountService.stateOfUserDoc(doc);
      expect(state.isVerified, isFalse);
      expect(state.status, RefundAccountStatus.required);
    });

    test('계좌가 아예 없으면 빈 상태', () {
      expect(RefundAccountService.stateOfUserDoc(null).isVerified, isFalse);
      expect(RefundAccountService.stateOfUserDoc({}).account, isNull);
      // 필드가 덜 찬 계좌도 계좌로 치지 않는다(예금주 누락).
      final partial = {
        'refundAccount': {'bankCode': '090', 'bankName': '카카오뱅크', 'accountNumber': '3333'},
        'refundAccountVerification': {'status': 'verified'},
      };
      expect(RefundAccountService.stateOfUserDoc(partial).account, isNull);
    });
  });

  group('요약 마스킹', () {
    test('뒤 네 자리만 남긴다 — 전체 번호는 요약에 나오지 않는다', () {
      final state = RefundAccountService.stateOfUserDoc(_verifiedDoc());
      expect(state.account!.maskedSummary, '카카오뱅크 ****1234');
      expect(state.account!.maskedSummary, isNot(contains('3333019991234')));
    });

    test('수취계좌와 같은 함수·같은 모양이다', () {
      final payout = PayoutAccount.fromUserDoc({
        'payoutAccount': {
          'bankCode': '090',
          'accountNumber': '3333019991234',
          'accountHolder': '홍길동',
        },
        'payoutAccountVerification': {'status': 'verified'},
      });
      final refund = RefundAccountService.stateOfUserDoc(_verifiedDoc()).account!;
      expect(refund.maskedSummary, payout.maskedSummary);
    });

    test('하이픈이 섞여 저장된 옛 계좌도 숫자 기준으로 자른다', () {
      final state = RefundAccountService.stateOfUserDoc(
        _verifiedDoc(accountNumber: '110-123-456789', bankName: '신한은행'),
      );
      expect(state.account!.maskedSummary, '신한은행 ****6789');
    });

    test('네 자리보다 짧으면 있는 만큼만, 번호가 없으면 기관명만', () {
      expect(
        BankCodes.maskedSummary(bankName: '신한은행', accountNumber: '789'),
        '신한은행 ****789',
      );
      expect(
        BankCodes.maskedSummary(bankName: '신한은행', accountNumber: ''),
        '신한은행',
      );
      expect(BankCodes.maskedSummary(), '');
    });
  });

  group('마이페이지 줄', () {
    final src = File('lib/screens/my_page_screen.dart').readAsStringSync();

    test('저장된 상태를 구독해서 그린다 — 인증 완료를 하드코딩하지 않는다', () {
      expect(src.contains('RefundAccountService.watch()'), isTrue);
      expect(src.contains("'인증 완료 · \${account.maskedSummary}'"), isTrue);
      // 화면이 직접 판정 규칙을 다시 적지 않는다.
      expect(src.contains("refundAccountVerification"), isFalse);
    });

    test('아직 인증 전이면 기존 안내 문구를 유지한다', () {
      expect(src.contains("'무통장입금 취소 시 환불받을 계좌'"), isTrue);
    });

    test('다른 인증 항목과 같은 초록색을 쓴다', () {
      // 사업자 인증·입금받을 계좌와 같은 값(0xFF047857)이 세 곳에 있다.
      expect('Color(0xFF047857)'.allMatches(src).length, greaterThanOrEqualTo(6));
    });
  });
}

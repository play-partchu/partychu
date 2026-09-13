// 계좌 세 가지가 **말로도 코드로도 섞이지 않는지** 확인한다.
//
//   payoutAccount   참가자 → 호스트   '입금받을 계좌'   ← 지금 돈이 오가는 계좌
//   settlementInfo  파티츄 → 호스트   '정산 계좌'       ← 향후 플랫폼 정산용
//   refundAccount   호스트 → 참가자   '환불받을 계좌'
//
// 이 셋은 주인도 방향도 다른데 이름이 비슷해서, 한 번 섞이면 "어느 계좌로 돈이
// 가는지"를 코드에서 되짚을 수 없게 된다. 실제로 그런 일이 있었다 —
//   · 참가자에게 안내되던 계좌가 플랫폼 공용 상수였고(지금은 제거),
//   · 장소 등록 폼의 '호스트 정산 계좌' 섹션이 정산계좌 화면으로 보냈으며,
//   · 등록 직후 팝업이 정산계좌를 재촉했다(직수취 구조에선 관계가 없다).
// 그래서 세 축을 각각 잠근다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/payout_account.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  group('등록 직후 안내는 수취계좌 하나뿐이다', () {
    final registers = [
      'lib/screens/party_register_screen.dart',
      'lib/screens/event_register_screen.dart',
      'lib/screens/place_register_screen.dart',
    ];

    test('세 등록 화면 모두 수취계좌 안내를 부른다', () {
      for (final path in registers) {
        expect(
          read(path),
          contains('promptPayoutAccountAfterRegister('),
          reason: path,
        );
      }
    });

    test('정산계좌 재촉 팝업은 코드베이스에서 사라졌다', () {
      expect(
        File('lib/widgets/settlement_account_prompt.dart').existsSync(),
        isFalse,
      );
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        expect(
          entity.readAsStringSync().contains(
            'promptSettlementAccountIfMissing',
          ),
          isFalse,
          reason: entity.path,
        );
      }
    });

    test('정산계좌 화면과 데이터는 그대로 남아 있다', () {
      // 없앤 것은 "등록 직후 강제 팝업"이지 기능이 아니다.
      expect(
        File('lib/screens/settlement_info_screen.dart').existsSync(),
        isTrue,
      );
      expect(
        read('lib/screens/settlement_info_screen.dart'),
        contains('settlementInfo'),
      );
      // 마이페이지에서 여전히 들어갈 수 있다.
      expect(
        read('lib/screens/my_page_screen.dart'),
        contains('SettlementInfoScreen()'),
      );
    });

    test('받을 돈이 없으면 아무것도 띄우지 않는다 — 판정 자리가 남아 있다', () {
      final prompt = read('lib/widgets/payout_account_prompt.dart');
      expect(prompt, contains('if (!usesBankTransfer) return;'));
      // 이미 인증된 계좌면 다시 묻지 않는다.
      expect(prompt, contains('if (account.isVerified'));
    });
  });

  group('세 계좌의 문구가 뒤섞이지 않는다', () {
    test('마이페이지 세 줄이 각각 다른 용도로 적혀 있다', () {
      final src = read('lib/screens/my_page_screen.dart');
      expect(src, contains("Text('입금받을 계좌')"));
      expect(src, contains("Text('정산 계좌 관리')"));
      expect(src, contains("Text('환불 계좌 관리')"));
      // 정산 줄은 참가비 계좌와 다르다는 것을 부제목에서 못 박는다.
      expect(src, contains('참가비 입금 계좌와 다름'));
    });

    test('장소 등록 폼은 수취계좌로 보낸다 — 정산계좌가 아니다', () {
      final src = read('lib/screens/place_register_screen.dart');
      expect(src, contains("title: '입금받을 계좌'"));
      expect(src, contains('PayoutAccountScreen()'));
      expect(
        src.contains("label: const Text('정산 계좌 관리로 이동')"),
        isFalse,
        reason: '이 폼에서 정산계좌로 보내면 두 계좌가 다시 섞인다',
      );
    });

    test('정산계좌 화면은 "참가비 정산"이라고 말하지 않는다', () {
      // 참가비는 파티츄를 거치지 않는다 — 그렇게 적으면 사실과 다르다.
      final src = read('lib/screens/settlement_info_screen.dart');
      expect(src.contains('입력하신 계좌로 파티 참가비 정산이 진행됩니다'), isFalse);
      expect(src, contains('입금받을 계좌'));
    });

    test('탈퇴 안내에 수취계좌도 적혀 있다 — 서버가 실제로 지운다', () {
      expect(
        read('lib/screens/account_withdrawal_screen.dart'),
        contains('입금받을 계좌'),
      );
      expect(
        read('../functions/accountWithdrawal.js'),
        contains("'payoutAccount', 'payoutAccountVerification'"),
      );
    });
  });

  group('수취계좌 상태 표기', () {
    test('세 상태의 이름이 화면 문구 그대로다', () {
      expect(PayoutAccountStatus.none.label, '미등록');
      expect(PayoutAccountStatus.required.label, '인증 필요');
      expect(PayoutAccountStatus.verified.label, '인증 완료');
    });

    test('계좌만 있고 인증 기록이 없으면 인증 필요', () {
      final account = PayoutAccount.fromUserDoc({
        'payoutAccount': {
          'bankCode': '004',
          'accountNumber': '12345678901234',
          'accountHolder': '홍길동',
        },
      });
      expect(account.status, PayoutAccountStatus.required);
      expect(account.isVerified, isFalse);
      expect(account.bankName, '국민은행');
      // 본인 화면 요약도 뒤 4자리만 쓴다.
      expect(account.maskedSummary, '국민은행 ****1234');
    });

    test('서버가 인증 완료로 적어 둔 계좌만 인증으로 읽는다', () {
      final account = PayoutAccount.fromUserDoc({
        'payoutAccount': {
          'bankCode': '088',
          'accountNumber': '110123456789',
          'accountHolder': '홍길동',
        },
        'payoutAccountVerification': {'status': 'verified'},
      });
      expect(account.isVerified, isTrue);
    });

    test('계좌가 없으면 미등록', () {
      expect(PayoutAccount.fromUserDoc(null).status, PayoutAccountStatus.none);
      expect(PayoutAccount.fromUserDoc({}).status, PayoutAccountStatus.none);
    });

    test('팝빌 연동 전에는 실패로 남는다 — 임의 성공 처리가 없다', () {
      // 서버 어댑터가 키 없이 통과시키면 검증되지 않은 계좌로 돈이 나간다.
      final popbill = read('../functions/popbill.js');
      expect(popbill, contains('NOT_CONFIGURED'));
      expect(
        popbill.contains('return { ok: true'),
        isFalse,
        reason: 'portOne.js식 테스트 모드 통과가 들어오면 안 된다',
      );
      // 실패 사유는 사용자에게 "준비 중"으로만 보인다(성공으로 보이지 않는다).
      expect(PayoutAccountFailReason.notConfigured.message, contains('준비 중'));
    });
  });
}

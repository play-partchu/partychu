// 계좌 세 종류의 UX 회귀 방지 — 정산계좌 숨김 · 환불계좌 인증 실패 안내 ·
// 무통장입금 계좌 노출.
//
// 이 파일이 붙잡는 것은 **계좌를 섞지 않는 것**이다. 돈의 방향이 다 다르다:
//   · 정산계좌(settlementInfo) 파티츄 → 호스트  — 지금은 메뉴를 감춰 둔다
//   · 입금계좌(payoutAccount)   게스트 → 호스트  — 주문 문서의 스냅샷을 보여준다
//   · 환불계좌(refundAccount)   호스트 → 게스트  — 취소 시점 사본을 호스트가 본다
//
// 화면 안에 갇힌 규칙(진입점 유무 등)은 소스 가드로 확인한다 — 그 자리들은
// Firebase 없이는 그릴 수 없고, 사라졌는지 여부만 지키면 충분하다.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/payment_method.dart';
import 'package:party_app/models/payment_status.dart';
import 'package:party_app/services/refund_account_service.dart';
import 'package:party_app/widgets/deposit_panel.dart';

String _src(String path) => File(path).readAsStringSync();

PaymentInfo _bankTransfer({
  PaymentStatus status = PaymentStatus.awaitingDeposit,
  bool withAccount = true,
  int amount = 30000,
}) => PaymentInfo.fromMap({
  'method': PaymentMethod.bankTransfer.key,
  'status': status.key,
  'amount': amount,
  'depositDeadlineMs': DateTime(2026, 8, 31, 18).millisecondsSinceEpoch,
  if (withAccount) ...{
    'bankName': '신한은행',
    'accountNumber': '110123456789',
    'accountHolder': '홍길동',
  },
})!;

void main() {
  // ── 1. 정산계좌 관리 숨김 ───────────────────────────────────────────────
  group('정산 계좌 관리는 사용자 화면에서 감춰져 있다', () {
    final myPage = _src('lib/screens/my_page_screen.dart');

    test('진입 줄이 꺼진 플래그 뒤에 있다', () {
      expect(myPage.contains('const bool _showSettlementAccountMenu = false;'), isTrue);
      expect(myPage.contains('if (_showSettlementAccountMenu) ...['), isTrue);
    });

    test('화면과 데이터는 지우지 않았다 — 되돌릴 수 있다', () {
      // 진입만 감췄을 뿐 화면은 그대로 있어야 한다(정산이 열리면 플래그만 켠다).
      expect(myPage.contains('SettlementInfoScreen()'), isTrue);
      expect(File('lib/screens/settlement_info_screen.dart').existsSync(), isTrue);
      expect(
        _src('lib/screens/settlement_info_screen.dart').contains('settlementInfo'),
        isTrue,
      );
    });

    test('다른 계좌 메뉴 둘은 그대로 열려 있다', () {
      // 입금받을 계좌(게스트 → 호스트)와 환불 계좌(호스트 → 게스트)는 지금
      // 실제로 돈이 오가는 자리라 정산계좌처럼 통째로 끄면 안 된다.
      //
      // (입금받을 계좌 줄은 사업자 인증을 마친 계정에만 보인다 —
      //  my_page_host_menu_gate_test.dart. 그건 이 플래그와 무관한 조건부
      //  노출이고, 줄 자체는 여기 그대로 살아 있어야 한다.)
      expect(myPage.contains("title: const Text('입금받을 계좌')"), isTrue);
      expect(myPage.contains("title: const Text('환불 계좌 관리')"), isTrue);
      // 감춤 플래그는 정산계좌 한 줄에만 걸려 있다.
      expect('_showSettlementAccountMenu'.allMatches(myPage).length, 3);
    });
  });

  // ── 2. 환불계좌 인증 실패 안내 ──────────────────────────────────────────
  group('환불계좌 인증 실패 사유', () {
    test('사유마다 다른 문구를 준다 — 하나로 뭉개지 않는다', () {
      final messages = {
        for (final r in [
          'accountNotFound',
          'holderMismatch',
          'identityMismatch',
          'apiUnavailable',
          'notConfigured',
        ])
          r: refundAccountFailMessage(r),
      };
      expect(messages.values.toSet().length, messages.length);
      expect(messages['accountNotFound'], contains('계좌번호'));
      expect(messages['holderMismatch'], contains('예금주'));
      expect(messages['identityMismatch'], contains('본인 명의'));
    });

    test('일시 장애만 "다시 시도"라고 말한다', () {
      // apiUnavailable은 재시도로 풀린다. notConfigured(설정 문제)는 아무리
      // 다시 눌러도 풀리지 않으므로 재시도를 권하면 안 된다 — 계좌가 잘못된
      // 것이 아니라는 사실을 알려주는 쪽이다.
      expect(refundAccountFailMessage('apiUnavailable'), contains('다시 시도'));
      final notConfigured = refundAccountFailMessage('notConfigured');
      expect(notConfigured, isNot(contains('다시 시도')));
      expect(notConfigured, contains('계좌 문제가 아니'));
    });

    test('모르는 사유도 계좌 확인을 권하는 문구로 떨어진다', () {
      expect(refundAccountFailMessage(null), isNotEmpty);
      expect(refundAccountFailMessage('무엇인지 모르는 값'), isNotEmpty);
    });
  });

  group('환불계좌 인증 호출 규격', () {
    final service = _src('lib/services/refund_account_service.dart');
    final screen = _src('lib/screens/refund_account_screen.dart');

    test('콜러블 이름과 리전이 서버 배포 대상과 같다', () {
      // functions/refundAccountVerify.js — onCall({ region: 'asia-northeast3' }),
      // functions/index.js — exports.verifyRefundAccount.
      expect(service.contains("_verifyCallable = 'verifyRefundAccount'"), isTrue);
      expect(service.contains("_region = 'asia-northeast3'"), isTrue);
      expect(
        _src('../functions/index.js').contains('exports.verifyRefundAccount'),
        isTrue,
      );
      expect(
        _src('../functions/refundAccountVerify.js').contains("region: 'asia-northeast3'"),
        isTrue,
      );
    });

    test('엔드포인트 없음과 일반 인증 실패를 계속 구분한다', () {
      // 이 구분이 사라지면 배포 누락이 "계좌가 잘못됐다"로 보이게 된다.
      expect(service.contains("_endpointMissingCodes = {'not-found', 'unimplemented'}"), isTrue);
      expect(service.contains('RefundAccountVerifyUnavailable'), isTrue);
      expect(screen.contains('on RefundAccountVerifyUnavailable catch'), isTrue);
      expect(screen.contains('on FirebaseFunctionsException catch'), isTrue);
    });

    test('인증 결과는 서버 문서를 다시 읽어 반영한다 — 앱이 만들지 않는다', () {
      // verified를 앱이 스스로 쓰는 경로가 있으면 안 된다.
      expect(service.contains('return fetchState();'), isTrue);
      expect(service.contains("'refundAccountVerification':"), isFalse);
      expect(screen.contains('setState(() => _state = state)'), isTrue);
    });

    test('입력이 비면 서버를 부르지 않는다', () {
      // 폼 검증을 통과해야만 verify로 간다(세 칸 모두 validator가 있다).
      expect(screen.contains('if (!_formKey.currentState!.validate()) return;'), isTrue);
      expect(screen.contains("'금융기관을 선택해주세요.'"), isTrue);
      expect(screen.contains("'계좌번호를 입력해주세요.'"), isTrue);
      expect(screen.contains("'예금주를 입력해주세요.'"), isTrue);
    });

    test('팝빌 환경이 명시돼 있다 — 비면 운영 서버로 나가 인증이 통째로 막힌다', () {
      // 2026-08-30 운영 실패의 원인이다(테스트베드 키 + 운영 엔드포인트 →
      // popbillCode=-99010016).
      expect(_src('../functions/.env').contains('POPBILL_ENV='), isTrue);
    });
  });

  // ── 3. 무통장입금 게스트 안내 ───────────────────────────────────────────
  group('무통장입금 계좌 안내', () {
    testWidgets('입금대기 건은 계좌·예금주·금액·기한을 보여준다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: DepositPanel(payment: _bankTransfer()))),
      );
      expect(find.textContaining('신한은행'), findsOneWidget);
      expect(find.textContaining('110123456789'), findsOneWidget);
      expect(find.textContaining('홍길동'), findsOneWidget);
      expect(find.text('30,000원'), findsOneWidget);
      expect(find.text('복사'), findsOneWidget);
    });

    testWidgets('복사를 누르면 계좌가 클립보드로 가고 안내가 뜬다', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: DepositPanel(payment: _bankTransfer()))),
      );
      await tester.tap(find.text('복사'));
      await tester.pump();
      expect(copied.single, contains('110123456789'));
      expect(find.text('계좌번호를 복사했어요.'), findsOneWidget);
    });

    testWidgets('현장결제에는 계좌를 보여주지 않는다', (tester) async {
      final onSite = PaymentInfo.fromMap({
        'method': PaymentMethod.onSite.key,
        'status': PaymentStatus.onSiteScheduled.key,
        'amount': 30000,
      })!;
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: DepositPanel(payment: onSite))),
      );
      expect(find.text('복사'), findsNothing);
      expect(find.textContaining('신한은행'), findsNothing);
    });

    testWidgets('입금이 끝난 건에도 계좌를 다시 띄우지 않는다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DepositPanel(payment: _bankTransfer(status: PaymentStatus.paid)),
          ),
        ),
      );
      expect(find.text('복사'), findsNothing);
    });

    testWidgets('계좌 스냅샷이 없는 옛 건은 엉뚱한 계좌 대신 안내를 띄운다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DepositPanel(payment: _bankTransfer(withAccount: false))),
        ),
      );
      expect(find.textContaining('입금 계좌를 불러오지 못했어요'), findsOneWidget);
      expect(find.text('복사'), findsNothing);
    });

    test('계좌는 주문 문서의 스냅샷이다 — 호스트가 계좌를 바꿔도 안 바뀐다', () {
      // 서버가 생성 시점에 인증된 수취계좌를 문서에 박는다. 도메인마다 그
      // 스냅샷을 넘기는지 확인한다(하나라도 빠지면 그 도메인만 계좌가 없다).
      final paymentInfo = _src('../functions/paymentInfo.js');
      expect(paymentInfo.contains('info.bankName = payoutAccount.bankName'), isTrue);
      for (final f in const [
        '../functions/index.js', // 파티 신청(applyToParty)
        '../functions/placeVisitReservations.js', // 플레이스 방문예약
        '../functions/placeReservations.js', // 장소대여
        '../functions/packageBookings.js', // 패키지·콤보
        '../functions/placeProductOrders.js', // 플레이스 상품
        '../functions/shopOrders.js', // 파티샵 주문
      ]) {
        expect(
          _src(f).contains('payoutAccount: await loadPayoutSnapshot('),
          isTrue,
          reason: '$f 가 입금계좌 스냅샷을 넘기지 않는다',
        );
      }
    });

    test('게스트가 나중에 다시 볼 수 있는 자리마다 같은 위젯이 붙어 있다', () {
      for (final f in const [
        'lib/screens/my_guest_hub_screen.dart', // 파티 신청
        'lib/widgets/visit_reservation_card.dart', // 방문예약
        'lib/widgets/place_rental_reservation_card.dart', // 장소대여·패키지
        'lib/widgets/voucher_card.dart', // 플레이스 상품 이용권
        'lib/widgets/shop_order_list.dart', // 파티샵 주문
      ]) {
        expect(_src(f).contains('DepositPanel('), isTrue, reason: '$f 에 입금 안내가 없다');
      }
    });
  });

  // ── 4. 호스트가 보는 환불계좌 ───────────────────────────────────────────
  group('호스트 환불 처리', () {
    final refundScreen = _src('lib/screens/host_refund_requests_screen.dart');

    test('환불 화면이 계좌와 복사 버튼을 들고 있다', () {
      expect(refundScreen.contains("_account['bankName']"), isTrue);
      expect(refundScreen.contains("_account['accountNumber']"), isTrue);
      expect(refundScreen.contains("_account['accountHolder']"), isTrue);
      expect(refundScreen.contains('Clipboard.setData'), isTrue);
      expect(refundScreen.contains("'계좌번호를 복사했어요.'"), isTrue);
    });

    test('계좌는 취소 시점 사본이다 — users 문서를 앱이 직접 읽지 않는다', () {
      // 서버가 인증된 계좌에서 떠 refundRequests에 박아 둔 값(A가 아니라 C).
      expect(refundScreen.contains("_d['account']"), isTrue);
      expect(refundScreen.contains("collection('users')"), isFalse);
      expect(
        _src('../functions/refundRequests.js').contains('loadVerifiedRefundSnapshot'),
        isTrue,
      );
    });

    test('내 건만 읽는다 — 다른 호스트의 게스트 계좌는 보이지 않는다', () {
      final service = _src('lib/services/host_refund_service.dart');
      expect(service.contains("where('hostId', isEqualTo: uid)"), isTrue);
      // 규칙도 같은 조건을 건다(클라이언트 권한을 넓히지 않았다).
      expect(
        _src('../firestore.rules').contains('refundRequests'),
        isTrue,
      );
    });

    test('호스트 허브에서 처리할 건이 있을 때만 진입 줄이 뜬다', () {
      final hub = _src('lib/screens/my_host_hub_screen.dart');
      expect(hub.contains('HostRefundService.watchPendingCount()'), isTrue);
      expect(hub.contains('HostRefundRequestsScreen()'), isTrue);
      expect(hub.contains('if (pending <= 0) return const SizedBox.shrink();'), isTrue);
    });

    test('신청자 목록 카드에는 환불계좌를 펼쳐 두지 않는다', () {
      // 민감정보는 실제로 환불이 필요한 자리에서만 보여준다.
      final applicants = _src('lib/screens/party_applicants_screen.dart');
      expect(applicants.contains('accountNumber'), isFalse);
      expect(applicants.contains('refundAccount'), isFalse);
    });
  });
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:party_app/models/payout_account.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/utils/user_session.dart';

/// 호스트 **수취계좌** — 등록·인증은 전부 서버 콜러블을 지난다.
///
/// 앱은 계좌를 Firestore에 직접 쓰지 않는다(규칙이 막는다). 계좌 원문까지
/// 서버 전용인 이유는 [PayoutAccount] 주석 참고 — 요약하면 "인증은 내 계좌로
/// 받고 저장은 남의 계좌로" 하는 우회를 원천 차단하기 위해서다.
class PayoutAccountService {
  PayoutAccountService._();

  static const _region = 'asia-northeast3';

  static DocumentReference<Map<String, dynamic>> get _userRef =>
      FirebaseFirestore.instance.collection('users').doc(UserSession.userId);

  /// 내 수취계좌 상태 — 마이페이지·등록 화면이 구독한다.
  static Stream<PayoutAccount> watch() {
    if (UserSession.userId.isEmpty) {
      return Stream.value(PayoutAccount.none);
    }
    return _userRef
        .snapshots()
        .map((s) => PayoutAccount.fromUserDoc(s.data()))
        .handleError(
          (Object e, StackTrace st) =>
              logFirestoreStreamError('PayoutAccountService.watch', e, st),
        );
  }

  /// 한 번만 읽기 — 등록 진입 시 "계좌부터 등록해주세요" 판단용.
  static Future<PayoutAccount> fetch() async {
    if (UserSession.userId.isEmpty) return PayoutAccount.none;
    try {
      final snap = await _userRef.get();
      return PayoutAccount.fromUserDoc(snap.data());
    } catch (e, st) {
      logFirestoreStreamError('PayoutAccountService.fetch', e, st);
      return PayoutAccount.none;
    }
  }

  /// 계좌 인증 요청 — 은행이 알고 있는 예금주와 대조한다.
  ///
  /// 성공·실패 모두 **서버가** 결과를 기록하므로, 호출 후에는 [watch]/[fetch]가
  /// 새 상태를 돌려준다. 앱은 결과를 저장하지 않는다.
  ///
  /// 실패 사유는 [PayoutAccount.failReason]으로 읽는다. 이 함수 자체가 던지는
  /// 것은 입력값 오류·네트워크 오류처럼 **조회를 시작하지도 못한** 경우뿐이다.
  static Future<PayoutAccount> verify({
    required String bankCode,
    required String accountNumber,
    required String accountHolder,
    PayoutAccountType accountType = PayoutAccountType.personal,
  }) async {
    final callable = FirebaseFunctions.instanceFor(
      region: _region,
    ).httpsCallable('verifyPayoutAccount');
    await callable.call<Map<String, dynamic>>({
      'bankCode': bankCode,
      'accountNumber': accountNumber,
      'accountHolder': accountHolder,
      'accountType': accountType.key,
    });
    // 반환값을 그대로 쓰지 않고 문서를 다시 읽는다 — 화면이 보는 값과 서버에
    // 저장된 값이 어긋날 여지를 없앤다.
    return fetch();
  }

  /// 이 호스트가 무통장입금을 받을 수 있는가(= 인증된 수취계좌가 있는가).
  ///
  /// 참가자 앱이 결제수단 목록에서 무통장입금을 뺄지 정할 때 쓴다. 계좌 값은
  /// 오지 않는다 — 참가자가 계좌를 보는 시점은 신청·예약·주문이 실제로 만들어진
  /// 뒤이고, 그때는 자기 문서에 박힌 스냅샷을 읽는다.
  ///
  /// 조회에 실패하면 **false**를 돌려준다. 무통장입금을 열어 두었다가 서버가
  /// 거절하면 사용자는 결제수단을 고르고 나서야 막히지만, 닫아 두면 다른
  /// 수단으로 그대로 진행할 수 있다.
  static Future<bool> hostCanReceiveBankTransfer(String hostId) async {
    if (hostId.trim().isEmpty) return false;
    final cached = _hostCache[hostId];
    if (cached != null) return cached;
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: _region,
      ).httpsCallable('getPayoutAccountStatus');
      final res = await callable.call<Map<String, dynamic>>({'hostId': hostId});
      final ok = res.data['canReceiveBankTransfer'] == true;
      _hostCache[hostId] = ok;
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// 화면을 여닫을 때마다 같은 호스트를 다시 묻지 않도록 하는 짧은 기억.
  /// (호스트가 계좌를 인증하면 참가자 앱은 다음 실행부터 반영된다 — 결제
  /// 직전 판정은 언제나 서버가 다시 한다.)
  static final Map<String, bool> _hostCache = {};
}

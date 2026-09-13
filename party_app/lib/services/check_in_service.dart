import 'package:cloud_functions/cloud_functions.dart';

import 'package:party_app/models/check_in_result.dart';

/// 통합 QR 체크인의 **유일한 창구**.
///
/// 화면은 Firestore를 직접 뒤지지 않는다 — QR 종류 판별·호스트 권한 검증·
/// 정보 조합을 서버 콜러블 하나가 하고([functions/checkInTokens.js]) 여기서는
/// 그 결과를 [CheckInResult]로 옮기기만 한다.
///
/// **조회와 사용 처리는 다른 함수다.** [resolve]는 몇 번을 불러도 아무것도
/// 바꾸지 않고, 상태가 바뀌는 것은 [consume] 하나뿐이다 — 다른 날짜 QR을
/// 잘못 찍었을 때 그 자리에서 소진되면 안 된다.
class CheckInService {
  CheckInService._();

  static final _fn = FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  /// QR을 읽어 **정보만** 가져온다. 상태는 바뀌지 않는다.
  static Future<CheckInResult> resolve(String token) async {
    final res = await _fn
        .httpsCallable('resolveCheckInToken')
        .call<Map<Object?, Object?>>({'token': token});
    return CheckInResult.fromMap(res.data);
  }

  /// 호스트가 확인 버튼을 눌렀을 때만 부른다 — 여기서 체크인/사용 처리가 된다.
  ///
  /// 막힌 건은 서버가 [FirebaseFunctionsException]으로 사유를 돌려준다.
  static Future<void> consume(String token) async {
    await _fn.httpsCallable('consumeCheckIn').call<Object?>({'token': token});
  }

  /// 현장결제·입금을 **이 화면에서** 확인한다 — 확인하는 순간 이용권이
  /// 발급되고 체크인이 열린다. 판정과 발급은 판매 화면과 같은 서버 함수를
  /// 쓴다(functions/voucherIssue.js).
  static Future<void> confirmPayment(String token) async {
    await _fn.httpsCallable('confirmCheckInPayment').call<Object?>({
      'token': token,
    });
  }

  /// 잘못 찍은 체크인을 **그날 안에** 되돌린다(파티·예약만).
  ///
  /// 이용권은 되돌릴 수 없다 — 이미 내준 상품을 다시 쓸 수 있게 되고 재고·
  /// 매출과 얽힌다. 서버가 그 경우 사유를 돌려준다.
  static Future<void> revoke(String token) async {
    await _fn.httpsCallable('revokeCheckIn').call<Object?>({'token': token});
  }
}

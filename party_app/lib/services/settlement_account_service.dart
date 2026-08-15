import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:party_app/utils/user_session.dart';

/// 호스트 **정산계좌** 하나만 다루는 서비스.
///
/// ── 이 앱의 계좌는 세 가지이고, 서로 절대 섞지 않는다 ─────────────────────
///   1. 참가자가 **입금하는** 계좌  = 파티츄 법인 계좌
///      (PartychuBankAccount / functions/paymentInfo.js의 BANK_ACCOUNT)
///   2. 파티츄가 **호스트에게 정산하는** 계좌 = 여기서 다루는 정산계좌
///   3. 파티츄가 **참가자에게 환불하는** 계좌 = 참가자 환불계좌
///      (RefundAccountService — 참가자 본인 소유 정보라 완전히 별개다)
///
/// 정산계좌는 **호스트 계정 하나에 하나**다(users/{uid}.settlementInfo).
/// 예전에는 장소 등록 폼 안에서 places/{id}.payoutAccount로도 따로 받았는데,
/// 그 문서는 누구나 읽을 수 있어(rules의 places read: if true) 계좌번호가
/// 공개로 노출됐다. 그래서 등록 폼의 계좌 입력을 없애고 이 한 곳으로 모았다.
class SettlementAccountService {
  SettlementAccountService._();

  static final _db = FirebaseFirestore.instance;

  /// 정산계좌로 인정하는 최소 조건 — 은행·계좌번호·예금주가 모두 채워져 있을 것.
  ///
  /// `settlementAgreed`(수집·이용 동의)는 저장 화면이 이미 강제하므로 여기서
  /// 다시 보지 않는다. 동의 없이 저장된 문서가 있더라도 계좌 자체가 있으면
  /// "등록됨"으로 보고 재촉하지 않는다 — 재촉의 목적은 계좌 확보다.
  static bool isValid(Map<String, dynamic>? info) {
    if (info == null) return false;
    String v(String k) => (info[k] as String? ?? '').trim();
    return v('bankName').isNotEmpty &&
        v('accountNumber').isNotEmpty &&
        v('accountHolder').isNotEmpty;
  }

  /// 지금 로그인한 호스트에게 쓸 수 있는 정산계좌가 있는지.
  ///
  /// 조회에 실패하면 **true**를 돌려준다 — 네트워크 오류 때문에 등록을 막
  /// 끝낸 호스트에게 "계좌를 등록하라"는 창을 잘못 띄우는 쪽이, 조용히
  /// 넘어가는 쪽보다 나쁘다.
  static Future<bool> hasAccount() async {
    final uid = UserSession.userId;
    if (uid.isEmpty) return true;
    try {
      final snap = await _db.collection('users').doc(uid).get();
      final info = snap.data()?['settlementInfo'] as Map<String, dynamic>?;
      return isValid(info);
    } catch (_) {
      return true;
    }
  }
}

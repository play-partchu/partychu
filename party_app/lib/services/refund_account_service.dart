import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:party_app/utils/user_session.dart';

/// 참가자 **환불계좌** — 무통장입금으로 낸 돈을 돌려받을 본인 계좌.
///
/// ⚠ 호스트 정산계좌(users/{uid}.settlementInfo)와 **다른 필드, 다른 용도**다.
///   - 정산계좌: 파티츄 → 호스트 (호스트가 받을 돈)
///   - 환불계좌: 파티츄 → 참가자 (참가자가 돌려받을 돈)
///   한 사람이 호스트이면서 참가자일 수 있으므로 절대 같은 필드에 두지 않는다.
///
/// 저장 위치는 본인 문서(users/{uid}.refundAccount)이고 규칙상 본인·관리자만
/// 읽는다. 실제 환불 요청이 접수될 때는 서버가 **그 시점의 사본**을
/// refundRequests에 따로 박아두므로, 나중에 여기를 고쳐도 접수된 건은 안 바뀐다.
class RefundAccount {
  final String bankName;
  final String accountNumber;
  final String accountHolder;

  const RefundAccount({
    required this.bankName,
    required this.accountNumber,
    required this.accountHolder,
  });

  bool get isComplete =>
      bankName.trim().isNotEmpty &&
      accountNumber.trim().isNotEmpty &&
      accountHolder.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
    'bankName': bankName.trim(),
    'accountNumber': accountNumber.trim(),
    'accountHolder': accountHolder.trim(),
  };

  static RefundAccount? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final a = RefundAccount(
      bankName: (map['bankName'] as String? ?? '').trim(),
      accountNumber: (map['accountNumber'] as String? ?? '').trim(),
      accountHolder: (map['accountHolder'] as String? ?? '').trim(),
    );
    return a.isComplete ? a : null;
  }
}

class RefundAccountService {
  RefundAccountService._();

  static final _db = FirebaseFirestore.instance;

  /// 이전에 등록해 둔 환불계좌 — 입력 화면의 기본값으로 쓴다.
  /// 매번 처음부터 치게 하지 않는 것이 목적이다.
  static Future<RefundAccount?> load() async {
    final uid = UserSession.userId;
    if (uid.isEmpty) return null;
    try {
      final snap = await _db.collection('users').doc(uid).get();
      return RefundAccount.fromMap(
        snap.data()?['refundAccount'] as Map<String, dynamic>?,
      );
    } catch (_) {
      return null;
    }
  }

  /// 마이페이지에서 직접 고칠 때 쓴다.
  ///
  /// 취소 흐름에서는 이 함수를 부르지 않는다 — 그쪽은 서버가 환불 요청을
  /// 접수하면서 같은 값을 함께 저장하므로, 앱이 또 쓰면 두 번 쓰는 셈이다.
  static Future<void> save(RefundAccount account) async {
    final uid = UserSession.userId;
    if (uid.isEmpty) return;
    await _db.collection('users').doc(uid).set({
      'refundAccount': {
        ...account.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));
  }
}

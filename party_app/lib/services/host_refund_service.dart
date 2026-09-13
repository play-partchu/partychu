import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:party_app/utils/user_session.dart';

/// 호스트가 처리하는 **환불 요청** — 목록 조회와 완료/반려 표시.
///
/// 참가자가 무통장입금한 참가비는 파티츄가 아니라 **호스트 계좌로 바로**
/// 들어간다(users/{uid}.payoutAccount). 그래서 돌려주는 것도 호스트다:
///
///   참가자 취소 → 환불 요청 접수 → 호스트에게 알림
///   → 여기서 참가자 계좌 확인 → 호스트가 **직접 송금**
///   → '보냈어요'로 표시 → 참가자 화면도 환불 완료
///
/// ⚠ 시스템은 실제 이체를 확인할 수 없다. '완료'는 **호스트가 보냈다고 표시한
///   것**이며, 서버 문서에도 그렇게 기록된다(completionMethod: marked_manually).
///   자동 송금·PG 환불처럼 표현하면 안 된다.
class HostRefundService {
  HostRefundService._();

  static const _region = 'asia-northeast3';

  /// 상태 키 — 서버 refundAccounts.js의 REFUND_REQUEST_STATUS와 1:1.
  static const String statusRequested = 'requested';
  static const String statusCompleted = 'completed';
  static const String statusRejected = 'rejected';

  /// 내가 호스트로서 처리해야 할(그리고 처리했던) 환불 요청들.
  ///
  /// 규칙이 hostId == 나인 문서만 읽게 열려 있다(firestore.rules) — 참가자
  /// 계좌 사본이 들어 있는 문서라 그 이상은 절대 보이지 않는다.
  static Stream<QuerySnapshot<Map<String, dynamic>>> watchForHost() {
    final uid = UserSession.userId;
    if (uid.isEmpty) {
      return const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    }
    return FirebaseFirestore.instance
        .collection('refundRequests')
        .where('hostId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots();
  }

  /// 아직 처리하지 않은 건수 — 마이페이지 진입점 배지에 쓴다.
  static Stream<int> watchPendingCount() {
    final uid = UserSession.userId;
    if (uid.isEmpty) return Stream.value(0);
    return FirebaseFirestore.instance
        .collection('refundRequests')
        .where('hostId', isEqualTo: uid)
        .where('status', isEqualTo: statusRequested)
        .snapshots()
        .map((s) => s.docs.length)
        .handleError((Object e, StackTrace st) {});
  }

  /// 송금을 마쳤다고 표시하거나(=완료), 사유를 적어 반려한다.
  ///
  /// 실제 상태 변경은 서버만 한다 — 클라이언트는 이 컬렉션에 쓸 수 없고,
  /// 서버가 "이 건의 호스트인가"를 다시 확인한다.
  static Future<void> complete({
    required String requestId,
    bool reject = false,
    String? memo,
  }) async {
    final callable = FirebaseFunctions.instanceFor(
      region: _region,
    ).httpsCallable('completeRefundRequest');
    await callable.call<Map<String, dynamic>>({
      'requestId': requestId,
      'reject': reject,
      'memo': ?memo,
    });
  }
}

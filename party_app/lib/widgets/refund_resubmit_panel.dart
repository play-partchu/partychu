import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/refund_account_sheet.dart';

/// 반려된 환불 요청을 **참가자가 다시 내는** 자리.
///
/// 취소된 신청 카드 아래에 붙는다. 반려는 참가자가 행동해야 끝나는 상태라,
/// 알림만 보내고 화면에 아무 것도 없으면 참가자는 무엇을 해야 할지 모른다.
///
/// ── 언제 버튼이 뜨는가 ──────────────────────────────────────────────────
///   신청 문서 refundStatus == 'pending'  (아직 돌려받지 못했다)
///   AND 내 최신 환불 요청 status == 'rejected'
/// 그 외에는 버튼을 그리지 않는다:
///   - requested  → '환불 확인 중' 문구만 (이미 큐에 있으니 또 낼 수 없다)
///   - completed  → 아무것도 없음 (재제출 절대 금지)
///
/// ── 남의 요청 ──────────────────────────────────────────────────────────
/// 쿼리를 requesterId == 나로 못 박는다. 규칙도 본인 것만 읽게 되어 있어
/// 남의 요청은 애초에 조회되지 않고, 서버도 재제출을 거절한다.
///
/// ⚠ 계좌번호는 로그·analytics·오류 문구에 남기지 않는다 — 실패해도 서버가
///   준 사람이 읽을 메시지만 그대로 보여준다.
class RefundResubmitPanel extends StatefulWidget {
  /// 환불 요청이 가리키는 원본 id(파티 id).
  final String refId;

  /// 신청 문서의 refundStatus — 'pending'일 때만 의미가 있다.
  final String? refundStatus;

  const RefundResubmitPanel({
    super.key,
    required this.refId,
    required this.refundStatus,
  });

  @override
  State<RefundResubmitPanel> createState() => _RefundResubmitPanelState();
}

class _RefundResubmitPanelState extends State<RefundResubmitPanel> {
  bool _sending = false;

  Future<void> _resubmit(String requestId) async {
    // 인증된 환불계좌를 마스킹해 보여주고 확인만 받는다. 계좌를 바꿔야 하면
    // 시트의 '환불계좌 변경'이 계좌 관리 화면으로 보내 **다시 인증**하게 한다
    // — 반려 사유가 계좌 문제였을 때 밟는 길이 이것이다.
    final ready = await confirmRefundAccount(
      context,
      refundAmount: 0, // 금액은 서버가 앞 요청에서 그대로 가져온다.
      formatAmount: (_) => '환불금',
    );
    if (!ready || !mounted) return;

    setState(() => _sending = true);
    try {
      // 계좌는 보내지 않는다 — 서버가 인증된 계좌에서 스냅샷을 직접 뜬다.
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('resubmitRefundRequest')
          .call({'requestId': requestId});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('환불 정보를 다시 제출했어요. 확인 후 처리해드릴게요.')),
      );
      // 버튼은 스트림이 새 요청(requested)을 받는 순간 사라진다 — 별도로
      // 감추지 않는다(서버 상태가 곧 화면 상태다).
    } catch (e) {
      if (!mounted) return;
      // 서버가 이미 사람이 읽을 한국어로 돌려준다. 계좌 정보는 넣지 않는다.
      final msg = e is FirebaseFunctionsException
          ? (e.message ?? '다시 제출하지 못했어요.')
          : '다시 제출하지 못했어요.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 돌려받을 돈이 아직 남아 있는 건에서만 본다.
    if (widget.refundStatus != 'pending') return const SizedBox.shrink();
    final uid = UserSession.userId;
    if (uid.isEmpty || widget.refId.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // requesterId를 조건에 넣어야 규칙(본인 것만 read)을 통과한다.
      // 두 equality 필터라 복합 색인이 필요 없다.
      stream: FirebaseFirestore.instance
          .collection('refundRequests')
          .where('refId', isEqualTo: widget.refId)
          .where('requesterId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }
        // 가장 최근 요청 하나만 본다 — 재제출하면 새 문서가 생기므로 이력이
        // 여러 건 쌓인다. 정렬은 색인을 피해 클라이언트에서 한다.
        final docs = snap.data!.docs.toList()
          ..sort((a, b) {
            final at = a.data()['createdAt'] as Timestamp?;
            final bt = b.data()['createdAt'] as Timestamp?;
            if (at == null && bt == null) return 0;
            if (at == null) return 1;
            if (bt == null) return -1;
            return bt.compareTo(at);
          });
        final latest = docs.first;
        final d = latest.data();
        final status = d['status'] as String?;

        // 이미 큐에 들어가 있으면 상태만 알린다(재제출 금지).
        if (status == 'requested') {
          return const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              '💸 환불 확인 중 — 입금까지 조금만 기다려주세요.',
              style: TextStyle(fontSize: 11.5, color: Colors.black54),
            ),
          );
        }
        // 완료된 건은 이 패널이 관여하지 않는다.
        if (status != 'rejected') return const SizedBox.shrink();

        final reason = (d['rejectedReason'] as String? ?? '').trim();
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3F6),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFF5C2D2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '환불 요청이 반려됐어요',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFE2568A),
                      ),
                    ),
                    if (reason.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '사유: $reason',
                        style: const TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 34,
                child: ElevatedButton(
                  onPressed: _sending ? null : () => _resubmit(latest.id),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE2568A),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    _sending ? '제출 중…' : '환불 정보 다시 제출',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

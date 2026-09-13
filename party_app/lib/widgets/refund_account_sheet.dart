import 'package:flutter/material.dart';

import 'package:party_app/screens/refund_account_screen.dart';
import 'package:party_app/services/refund_account_service.dart';
import 'package:party_app/widgets/refund_account_prompt.dart';
import 'package:party_app/widgets/web_frame.dart';

/// 환불받을 계좌를 **확인받는** 시트 — 입력받지 않는다.
///
/// 무통장입금으로 실제 입금까지 끝난 건을 취소할 때, 그리고 반려된 요청을 다시
/// 낼 때 쓴다 — 계좌이체로 돌려줄 돈이 없는 경우에는 부르지 않는다.
///
/// ── 왜 자유 입력을 없앴나 ────────────────────────────────────────────────
/// 예전에는 여기서 은행명·계좌번호를 그 자리에서 쳐서 보냈고, 그 값이 그대로
/// 환불 요청에 박히고 users/{uid}.refundAccount까지 덮어썼다. 그래서
///   ① 본인 계좌가 아닌 곳으로 환불을 요청할 수 있었고,
///   ② 환불계좌 관리에서 인증해 둔 계좌가 조용히 교체됐다.
/// 이제 환불계좌의 정본은 **본인 인증을 마친 계좌 하나뿐**이다. 이 시트는 그
/// 계좌를 마스킹해 보여주고 "이 계좌로 받겠다"는 확인만 받는다. 바꾸려면
/// 계좌 관리 화면에서 **다시 인증**해야 한다.
///
/// 인증된 계좌가 없으면 시트 대신 인증 안내를 띄우고
/// ([ensureRefundAccountVerified]), 인증을 마치면 그대로 이어진다.
///
/// 돌려주는 값이 true가 아니면 사용자가 그만둔 것이므로 **환불 요청도 하지
/// 않는다**. 계좌 값 자체는 돌려주지 않는다 — 스냅샷은 서버가 인증된 계좌에서
/// 직접 뜬다(functions/refundAccountVerify.verifiedSnapshotOf).
Future<bool> confirmRefundAccount(
  BuildContext context, {
  required int refundAmount,
  required String Function(int) formatAmount,
}) async {
  // 인증이 안 돼 있으면 여기서 먼저 받는다 — 취소 흐름과 재제출 흐름이 같은
  // 안내를 쓴다.
  if (!await ensureRefundAccountVerified(context)) return false;
  if (!context.mounted) return false;

  final state = await RefundAccountService.fetchState();
  final account = state.account;
  if (!state.isVerified || account == null || !context.mounted) return false;

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) => _RefundAccountConfirm(
      account: account,
      refundAmount: refundAmount,
      formatAmount: formatAmount,
    ),
  );
  return result == true;
}

class _RefundAccountConfirm extends StatefulWidget {
  final RefundAccount account;
  final int refundAmount;
  final String Function(int) formatAmount;

  const _RefundAccountConfirm({
    required this.account,
    required this.refundAmount,
    required this.formatAmount,
  });

  @override
  State<_RefundAccountConfirm> createState() => _RefundAccountConfirmState();
}

class _RefundAccountConfirmState extends State<_RefundAccountConfirm> {
  late RefundAccount _account = widget.account;

  /// '환불계좌 변경' — 계좌 관리 화면에서 **다시 인증**하고 돌아온다.
  ///
  /// 돌아온 뒤 상태를 다시 읽는다. 인증을 마치지 않았다면 화면에는 이전
  /// 계좌가 그대로 남는다(바뀐 것이 없으므로 정확한 표시다).
  Future<void> _change() async {
    await Navigator.push(
      context,
      webFramedRoute((_) => const RefundAccountScreen()),
    );
    if (!mounted) return;
    final after = await RefundAccountService.fetchState();
    if (!mounted) return;
    final next = after.account;
    if (after.isVerified && next != null) setState(() => _account = next);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        18,
        20,
        18 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            '환불 계좌 확인',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            '환불 예정 금액 ${widget.formatAmount(widget.refundAmount)}',
            style: const TextStyle(fontSize: 13.5, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF0F5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.verified_rounded,
                      size: 18,
                      color: Color(0xFFFF6FA0),
                    ),
                    const SizedBox(width: 8),
                    // 계좌번호는 뒤 네 자리만 — 전체를 다시 그리지 않는다.
                    Text(
                      _account.maskedLabel,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  '이 계좌로 환불받아요.',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _change,
              icon: const Icon(Icons.edit_outlined, size: 16),
              style: TextButton.styleFrom(foregroundColor: Colors.black54),
              label: const Text('환불계좌 변경'),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '계좌를 바꾸면 본인 명의인지 다시 확인해요. '
            '이미 접수된 환불 요청은 요청 당시 계좌로 처리돼요.',
            style: TextStyle(fontSize: 12, height: 1.5, color: Colors.black38),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black54,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('그만두기'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6FA0),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '이 계좌로 환불받기',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

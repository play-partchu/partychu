import 'package:flutter/material.dart';

import 'package:party_app/screens/refund_account_screen.dart';
import 'package:party_app/services/refund_account_service.dart';
import 'package:party_app/widgets/web_frame.dart';

/// 무통장입금으로 신청하려면 **인증된 환불계좌**가 있어야 한다 — 없으면
/// 안내하고 계좌 화면으로 보낸다.
///
/// ── 왜 낼 때 미리 받아 두나 ──────────────────────────────────────────────
/// 무통장입금은 PG를 거치지 않아 원결제 취소라는 경로가 없다. 취소·환불이
/// 생기면 돌려줄 방법이 계좌이체뿐인데, 그때 가서 계좌를 물으면 "돈은 냈는데
/// 돌려받을 길이 막힌" 상태가 먼저 생긴다.
///
/// ── 호스트 수취계좌와 다른 것 ────────────────────────────────────────────
/// [ensurePayoutAccountVerified]는 **호스트가 받을** 계좌를 확인하고, 여기는
/// **게스트가 돌려받을** 계좌를 확인한다. 필드도 상태도 완전히 따로다
/// (payoutAccount ↔ refundAccount). 같은 사람이 호스트이면서 게스트일 수
/// 있으므로 한쪽 인증이 다른 쪽을 대신하지 않는다.
///
/// ── 현장결제에는 부르지 않는다 ───────────────────────────────────────────
/// 호출부가 무통장입금을 고른 경우에만 부른다. 현장에서 낸 돈은 현장에서
/// 현금으로 돌려주므로 계좌가 필요 없다.
///
/// 이미 인증돼 있으면 **아무것도 띄우지 않고** 곧바로 true를 돌려준다.
///
/// 계좌 화면에 다녀오면 상태를 **다시 확인해서** 돌려준다 — 거기서 인증을
/// 마쳤다면 원래 흐름이 그대로 이어지고, 안 했다면 false라 신청이 멈춘다.
Future<bool> ensureRefundAccountVerified(BuildContext context) async {
  final state = await RefundAccountService.fetchState();
  if (state.isVerified) return true;
  if (!context.mounted) return false;

  final goVerify = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        '환불계좌를 등록해주세요',
        style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
      ),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '무통장입금으로 신청하려면 환불받을 계좌를 미리 인증해야 해요.',
            style: TextStyle(fontSize: 13.5, height: 1.5),
          ),
          SizedBox(height: 8),
          Text(
            '취소·환불이 필요한 경우 인증된 계좌로 환불받을 수 있어요.',
            style: TextStyle(fontSize: 12.5, height: 1.5, color: Colors.black45),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          style: TextButton.styleFrom(foregroundColor: Colors.black45),
          child: const Text('나중에 하기'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFFF6FA0),
          ),
          child: const Text('환불계좌 인증하기'),
        ),
      ],
    ),
  );

  if (goVerify != true || !context.mounted) return false;

  await Navigator.push(
    context,
    webFramedRoute((_) => const RefundAccountScreen()),
  );
  if (!context.mounted) return false;
  // 다녀온 뒤의 상태가 정본이다 — 화면에서 인증을 마쳤을 수 있다.
  final after = await RefundAccountService.fetchState();
  return after.isVerified;
}

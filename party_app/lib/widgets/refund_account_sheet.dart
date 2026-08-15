import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:party_app/services/refund_account_service.dart';

/// 환불받을 **참가자 본인 계좌**를 입력받는 시트.
///
/// 무통장입금으로 실제 입금까지 끝난 건을 취소할 때만 뜬다 — 무료 신청이나
/// 현장결제 취소처럼 계좌이체로 돌려줄 돈이 없는 경우에는 부르지 않는다.
///
/// 이전에 등록한 계좌가 있으면 **미리 채워서** 보여주고 그대로 확인만 하면
/// 되게 한다(매번 새로 치게 하지 않는다). 물론 고칠 수 있다.
///
/// 돌려주는 값이 null이면 사용자가 취소한 것이므로 **환불 요청도 하지 않는다**.
Future<RefundAccount?> showRefundAccountSheet(
  BuildContext context, {
  required int refundAmount,
  required String Function(int) formatAmount,
}) async {
  final saved = await RefundAccountService.load();
  if (!context.mounted) return null;

  final bankCtrl = TextEditingController(text: saved?.bankName ?? '');
  final numberCtrl = TextEditingController(text: saved?.accountNumber ?? '');
  final holderCtrl = TextEditingController(text: saved?.accountHolder ?? '');
  final formKey = GlobalKey<FormState>();

  final result = await showModalBottomSheet<RefundAccount>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        18,
        20,
        MediaQuery.of(ctx).viewInsets.bottom + 20,
      ),
      child: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '환불받을 계좌',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              '${formatAmount(refundAmount)}을 돌려드릴 계좌예요.\n'
              '본인 명의 계좌를 입력해주세요.',
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Colors.black54,
              ),
            ),
            if (saved != null) ...[
              const SizedBox(height: 8),
              const Text(
                '이전에 등록한 계좌를 불러왔어요. 그대로 쓰거나 고칠 수 있어요.',
                style: TextStyle(fontSize: 12, color: Color(0xFFE2568A)),
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: bankCtrl,
              decoration: const InputDecoration(
                labelText: '은행명',
                hintText: '예: 카카오뱅크',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? '은행명을 입력해주세요.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: numberCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '계좌번호',
                hintText: '숫자만 입력',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? '계좌번호를 입력해주세요.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: holderCtrl,
              decoration: const InputDecoration(
                labelText: '예금주',
                hintText: '예금주 이름',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? '예금주를 입력해주세요.' : null,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  if (!formKey.currentState!.validate()) return;
                  Navigator.pop(
                    ctx,
                    RefundAccount(
                      bankName: bankCtrl.text,
                      accountNumber: numberCtrl.text,
                      accountHolder: holderCtrl.text,
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE2568A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                child: const Text('이 계좌로 환불 요청'),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                style: TextButton.styleFrom(foregroundColor: Colors.black45),
                child: const Text('돌아가기'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  bankCtrl.dispose();
  numberCtrl.dispose();
  holderCtrl.dispose();
  return result;
}

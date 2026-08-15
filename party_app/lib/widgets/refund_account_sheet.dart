import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:party_app/services/refund_account_service.dart';

/// 환불받을 **참가자 본인 계좌**를 입력받는 시트.
///
/// 무통장입금으로 실제 입금까지 끝난 건을 취소할 때, 그리고 반려된 요청을
/// 다시 낼 때 쓴다 — 계좌이체로 돌려줄 돈이 없는 경우에는 부르지 않는다.
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

  return showModalBottomSheet<RefundAccount>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) => _RefundAccountForm(
      saved: saved,
      refundAmount: refundAmount,
      formatAmount: formatAmount,
    ),
  );
}

/// 시트 내용.
///
/// ⚠ 컨트롤러는 **이 위젯이 소유하고 스스로 dispose한다.** 예전에는 시트를
///   띄운 함수가 `showModalBottomSheet`가 반환된 직후 dispose했는데, 그때는
///   닫히는 애니메이션이 아직 남아 있어 TextField가 컨트롤러를 붙들고 있다 —
///   `_dependents.isEmpty` assertion으로 화면이 통째로 죽었다. 프레임워크가
///   위젯 수명에 맞춰 정리하도록 맡기면 그 창이 아예 없어진다.
class _RefundAccountForm extends StatefulWidget {
  final RefundAccount? saved;
  final int refundAmount;
  final String Function(int) formatAmount;

  const _RefundAccountForm({
    required this.saved,
    required this.refundAmount,
    required this.formatAmount,
  });

  @override
  State<_RefundAccountForm> createState() => _RefundAccountFormState();
}

class _RefundAccountFormState extends State<_RefundAccountForm> {
  final _formKey = GlobalKey<FormState>();
  late final _bankCtrl = TextEditingController(
    text: widget.saved?.bankName ?? '',
  );
  late final _numberCtrl = TextEditingController(
    text: widget.saved?.accountNumber ?? '',
  );
  late final _holderCtrl = TextEditingController(
    text: widget.saved?.accountHolder ?? '',
  );

  @override
  void dispose() {
    _bankCtrl.dispose();
    _numberCtrl.dispose();
    _holderCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        18,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
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
              '${widget.formatAmount(widget.refundAmount)}을 돌려드릴 계좌예요.\n'
              '본인 명의 계좌를 입력해주세요.',
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Colors.black54,
              ),
            ),
            if (widget.saved != null) ...[
              const SizedBox(height: 8),
              const Text(
                '이전에 등록한 계좌를 불러왔어요. 그대로 쓰거나 고칠 수 있어요.',
                style: TextStyle(fontSize: 12, color: Color(0xFFE2568A)),
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _bankCtrl,
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
              controller: _numberCtrl,
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
              controller: _holderCtrl,
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
                  if (!_formKey.currentState!.validate()) return;
                  Navigator.pop(
                    context,
                    RefundAccount(
                      bankName: _bankCtrl.text,
                      accountNumber: _numberCtrl.text,
                      accountHolder: _holderCtrl.text,
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
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(foregroundColor: Colors.black45),
                child: const Text('돌아가기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

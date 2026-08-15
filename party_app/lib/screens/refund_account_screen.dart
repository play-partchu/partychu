import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:party_app/services/refund_account_service.dart';

/// 참가자 **환불계좌 관리** — 내가 환불받을 계좌.
///
/// ⚠ 호스트 정산계좌(SettlementInfoScreen)와 **다른 화면, 다른 데이터**다.
///   - 정산계좌: 내가 호스트로서 **받을** 정산 대금 → users/{uid}.settlementInfo
///   - 환불계좌: 내가 참가자로서 **돌려받을** 환불금 → users/{uid}.refundAccount
///   한 사람이 둘 다일 수 있으므로 화면도 필드도 합치지 않는다.
///
/// 여기서 계좌를 바꿔도 **이미 접수된 환불 요청은 바뀌지 않는다** — 요청 시점의
/// 계좌가 refundRequests에 사본으로 박혀 있기 때문이다(운영자가 이미 그 계좌로
/// 보냈을 수 있다).
class RefundAccountScreen extends StatefulWidget {
  const RefundAccountScreen({super.key});

  @override
  State<RefundAccountScreen> createState() => _RefundAccountScreenState();
}

class _RefundAccountScreenState extends State<RefundAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _bankCtrl = TextEditingController();
  final _numberCtrl = TextEditingController();
  final _holderCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bankCtrl.dispose();
    _numberCtrl.dispose();
    _holderCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final saved = await RefundAccountService.load();
    if (!mounted) return;
    setState(() {
      if (saved != null) {
        _bankCtrl.text = saved.bankName;
        _numberCtrl.text = saved.accountNumber;
        _holderCtrl.text = saved.accountHolder;
      }
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await RefundAccountService.save(
        RefundAccount(
          bankName: _bankCtrl.text,
          accountNumber: _numberCtrl.text,
          accountHolder: _holderCtrl.text,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('환불계좌가 저장되었습니다.')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('저장에 실패했어요: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('환불 계좌 관리'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '무통장입금으로 결제한 신청을 취소하면 이 계좌로 환불해 드려요.\n'
                      '본인 명의 계좌를 입력해주세요.',
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.6,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 20),
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
                    const SizedBox(height: 14),
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
                    const SizedBox(height: 14),
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
                    const SizedBox(height: 12),
                    const Text(
                      '이미 접수된 환불 요청은 요청 당시 계좌로 처리돼요. '
                      '여기서 계좌를 바꿔도 그 건은 바뀌지 않아요.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: Colors.black38,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6FA0),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _saving ? '저장 중…' : '저장',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

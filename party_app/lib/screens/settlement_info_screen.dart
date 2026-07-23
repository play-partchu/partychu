import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:party_app/utils/user_session.dart';

class SettlementInfoScreen extends StatefulWidget {
  const SettlementInfoScreen({super.key});

  @override
  State<SettlementInfoScreen> createState() => _SettlementInfoScreenState();
}

class _SettlementInfoScreenState extends State<SettlementInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _accountNumberCtrl = TextEditingController();
  final _accountHolderCtrl = TextEditingController();
  final _businessNumberCtrl = TextEditingController();

  String? _bankName;
  String _hostType = 'individual';
  bool _agreed = false;
  bool _isLoading = true;
  bool _isSaving = false;

  static const _banks = [
    '국민은행', '신한은행', '우리은행', '하나은행', '기업은행',
    '농협은행', 'SC제일은행', '씨티은행', '카카오뱅크', '케이뱅크', '토스뱅크',
    '수협은행', '광주은행', '대구은행', '부산은행', '전북은행', '제주은행',
    '새마을금고', '신협',
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  @override
  void dispose() {
    _accountNumberCtrl.dispose();
    _accountHolderCtrl.dispose();
    _businessNumberCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSavedData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(UserSession.userId)
          .get();
      if (doc.exists) {
        final info = doc.data()?['settlementInfo'] as Map<String, dynamic>?;
        if (info != null && mounted) {
          setState(() {
            _bankName = info['bankName'] as String?;
            _accountNumberCtrl.text = info['accountNumber'] as String? ?? '';
            _accountHolderCtrl.text = info['accountHolder'] as String? ?? '';
            _hostType = info['hostType'] as String? ?? 'individual';
            _businessNumberCtrl.text = info['businessNumber'] as String? ?? '';
            _agreed = info['settlementAgreed'] as bool? ?? false;
          });
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('계좌정보 수집·이용 동의가 필요합니다.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(UserSession.userId)
          .set({
        'settlementInfo': {
          'bankName': _bankName ?? '',
          'accountNumber': _accountNumberCtrl.text.trim(),
          'accountHolder': _accountHolderCtrl.text.trim(),
          'hostType': _hostType,
          'businessNumber':
              _hostType == 'business' ? _businessNumberCtrl.text.trim() : '',
          'settlementAgreed': _agreed,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('정산 정보가 저장되었습니다.')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('저장 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        title: const Text('정산 계좌 관리', style: TextStyle(fontFamily: 'SeoulHangang', fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _noticeBox(),
            const SizedBox(height: 16),
            _sectionCard(
              title: '호스트 유형',
              child: Row(
                children: [
                  Expanded(child: _typeButton('개인', 'individual')),
                  const SizedBox(width: 12),
                  Expanded(child: _typeButton('사업자', 'business')),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              title: '계좌 정보',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('은행명'),
                  DropdownButtonFormField<String>(
                    initialValue: _bankName,
                    hint: const Text('은행 선택'),
                    items: _banks
                        .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                        .toList(),
                    onChanged: (v) => setState(() => _bankName = v),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? '은행을 선택해주세요' : null,
                    decoration: _inputDecoration(''),
                  ),
                  const SizedBox(height: 16),
                  _label('계좌번호'),
                  TextFormField(
                    controller: _accountNumberCtrl,
                    keyboardType: TextInputType.number,
                    decoration: _inputDecoration('숫자만 입력 (예: 12345678901234)'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '계좌번호를 입력해주세요' : null,
                  ),
                  const SizedBox(height: 16),
                  _label('예금주명'),
                  TextFormField(
                    controller: _accountHolderCtrl,
                    decoration: _inputDecoration('계좌 소유자 이름'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '예금주명을 입력해주세요' : null,
                  ),
                ],
              ),
            ),
            if (_hostType == 'business') ...[
              const SizedBox(height: 16),
              _sectionCard(
                title: '사업자 정보',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('사업자등록번호'),
                    TextFormField(
                      controller: _businessNumberCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _inputDecoration('예: 123-45-67890'),
                      validator: (v) => (_hostType == 'business' &&
                              (v == null || v.trim().isEmpty))
                          ? '사업자등록번호를 입력해주세요'
                          : null,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            _agreementBox(),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('저장하기'),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _noticeBox() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB8C8F0)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  size: 16, color: Color(0xFF3B5BDB)),
              SizedBox(width: 6),
              Text('정산 계좌 안내',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF3B5BDB))),
            ],
          ),
          SizedBox(height: 8),
          Text(
            '입력하신 계좌로 파티 참가비 정산이 진행됩니다.\n실제 송금은 정산 시스템 연동 후 적용됩니다.',
            style: TextStyle(
                fontSize: 12, color: Color(0xFF3B5BDB), height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _agreementBox() {
    return GestureDetector(
      onTap: () => setState(() => _agreed = !_agreed),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _agreed ? Colors.black54 : Colors.grey.shade200,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Checkbox(
              value: _agreed,
              activeColor: Colors.black,
              onChanged: (v) => setState(() => _agreed = v ?? false),
            ),
            const Expanded(
              child: Text(
                '정산을 위해 계좌정보를 수집·이용하는 것에 동의합니다.',
                style: TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _typeButton(String label, String value) {
    final selected = _hostType == value;
    return GestureDetector(
      onTap: () => setState(() => _hostType = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? Colors.black : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : Colors.black54,
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint.isEmpty ? null : hint,
        filled: true,
        fillColor: const Color(0xFFF7F7FA),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
      );
}

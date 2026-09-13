import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:party_app/models/business_verification.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/screens/business_verification_screen.dart';

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

  /// 사업자 인증의 **정본**([BusinessVerification]) — 이 화면이 직접 고쳐
  /// 쓰는 값이 아니라, 사업자번호를 어디서 가져올지 정하는 근거다.
  ///
  /// 인증을 마친 계정에서는 `settlementInfo.businessNumber`를 사용자가 따로
  /// 타이핑하게 두지 않는다. 예전에는 자유 입력이라 사업자 정보를 변경한 뒤
  /// 이 값만 옛 번호로 남아, 정산 화면과 사업자 인증 화면이 서로 다른 번호를
  /// 보여줄 수 있었다(정본은 언제나 businessVerification이다).
  BusinessVerification _verification = BusinessVerification.none;

  String? _bankName;
  String _hostType = 'individual';
  bool _agreed = false;
  bool _isLoading = true;
  bool _isSaving = false;

  static const _banks = [
    '국민은행',
    '신한은행',
    '우리은행',
    '하나은행',
    '기업은행',
    '농협은행',
    'SC제일은행',
    '씨티은행',
    '카카오뱅크',
    '케이뱅크',
    '토스뱅크',
    '수협은행',
    '광주은행',
    '대구은행',
    '부산은행',
    '전북은행',
    '제주은행',
    '새마을금고',
    '신협',
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
        // 인증 정본을 함께 읽는다 — 같은 문서라 추가 조회가 아니다.
        final v = BusinessVerification.fromUserDoc(doc.data());
        if (mounted) {
          setState(() {
            _verification = v;
            // 인증된 사업자번호가 있으면 그것으로 맞춘다(자유 입력값이 옛
            // 번호로 남아 화면마다 다른 번호를 보여주지 않게).
            if (v.isVerified && v.businessNumber.isNotEmpty) {
              _businessNumberCtrl.text = v.formattedBusinessNumber;
            }
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('계좌정보 수집·이용 동의가 필요합니다.')));
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
              // 인증을 마쳤으면 정본(businessVerification)의 번호를 그대로 쓴다 —
              // 사업자 정보를 변경해도 이 값이 옛 번호로 남지 않는다.
              'businessNumber': _hostType != 'business'
                  ? ''
                  : _verification.isVerified &&
                        _verification.businessNumber.isNotEmpty
                  ? _verification.formattedBusinessNumber
                  : _businessNumberCtrl.text.trim(),
              'settlementAgreed': _agreed,
              'updatedAt': FieldValue.serverTimestamp(),
            },
          }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('정산 정보가 저장되었습니다.')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('저장 실패: $e')));
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
        title: const Text(
          '정산 계좌 관리',
          style: TextStyle(
            fontFamily: 'SeoulHangang',
            fontWeight: FontWeight.w500,
            shadows: [
              Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
              Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
            ],
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _noticeBox(),
            const SizedBox(height: 16),
            // ⚠️ 이 유형은 **정산 서류 구분용**이다. 사용자가 직접 고르는 값이라
            // 예약·모집 오픈 권한의 근거로 쓰지 않는다 — 그 권한은 국세청
            // 진위확인을 통과한 businessVerification.status == 'verified'만
            // 판정한다(models/business_verification.dart 참고).
            _sectionCard(
              title: '호스트 유형',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: _typeButton('개인', 'individual')),
                      const SizedBox(width: 12),
                      Expanded(child: _typeButton('사업자', 'business')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '여기서 고른 유형은 정산 서류 구분에만 쓰여요. '
                    '파티를 바로 오픈하고 신청·결제를 받으려면 사업자 인증을 따로 마쳐야 해요.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: Colors.black45,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const BusinessVerificationScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.badge_outlined, size: 18),
                      label: const Text('사업자 인증하러 가기'),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        foregroundColor: const Color(0xFF4F46E5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              // 세 계좌가 뒤섞이지 않게 제목에도 용도를 적는다
              // (입금받을 계좌 / 정산 계좌 / 환불받을 계좌).
              title: '정산 계좌 정보',
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
                    // 사업자 인증을 마쳤으면 **읽기 전용**이다 — 정본은
                    // businessVerification이고, 여기서 따로 고칠 수 있게 두면
                    // 사업자 정보를 변경한 뒤 두 화면이 다른 번호를 보여준다.
                    // 번호를 바꾸려면 사업자 인증 화면에서 재인증해야 한다.
                    TextFormField(
                      controller: _businessNumberCtrl,
                      keyboardType: TextInputType.number,
                      readOnly: _verification.isVerified,
                      decoration: _inputDecoration('예: 123-45-67890'),
                      validator: (v) =>
                          (_hostType == 'business' &&
                              (v == null || v.trim().isEmpty))
                          ? '사업자등록번호를 입력해주세요'
                          : null,
                    ),
                    if (_verification.isVerified) ...[
                      const SizedBox(height: 8),
                      const Text(
                        '사업자 인증을 마친 번호예요. 사업자등록번호가 바뀌었다면 '
                        '사업자 인증 화면에서 새 정보로 다시 인증해주세요.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: Colors.black45,
                        ),
                      ),
                    ],
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
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
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
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 16,
                color: Color(0xFF3B5BDB),
              ),
              SizedBox(width: 6),
              Text(
                '정산 계좌 안내',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF3B5BDB),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            '이 계좌는 향후 파티츄가 호스트에게 보낼 정산 대금용이에요.\n'
            '지금은 참가비·예약금이 파티츄를 거치지 않고 호스트의 '
            '"입금받을 계좌"로 바로 들어가요 — 참가비를 받으려면 그 계좌를 '
            '따로 등록·인증해주세요.',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF3B5BDB),
              height: 1.5,
            ),
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
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
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
    child: Text(
      text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint.isEmpty ? null : hint,
    filled: true,
    fillColor: const Color(0xFFF7F7FA),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  );
}

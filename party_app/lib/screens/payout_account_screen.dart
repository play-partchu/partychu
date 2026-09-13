import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:party_app/models/bank_codes.dart';
import 'package:party_app/models/payout_account.dart';
import 'package:party_app/services/payout_account_service.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/partychu_ui.dart';

/// 호스트 **입금받을 계좌**(수취계좌) 관리.
///
/// 참가자가 무통장입금으로 보내는 돈은 파티츄가 아니라 **호스트가 직접** 받는다.
/// 그래서 이 화면에서 인증한 계좌가 곧 참가자에게 안내되는 계좌다.
///
/// ── 왜 저장이 아니라 '인증'인가 ───────────────────────────────────────────
/// 여기 적은 계좌는 그대로 남의 송금 대상이 된다. 오타 하나면 참가자 돈이 모르는
/// 사람에게 가고, 되돌릴 방법이 없다. 그래서 저장 버튼이 아니라 **인증 버튼**만
/// 둔다 — 은행에 예금주를 물어보고, 그 이름이 입력값·본인확인 실명과 모두 맞을
/// 때만 등록된다(판정과 기록은 전부 서버가 한다).
///
/// ── 정산계좌와 다른 계좌다 ────────────────────────────────────────────────
/// 정산계좌(SettlementInfoScreen)는 **향후 파티츄가 호스트에게 보낼** 계좌라
/// 지금 돈이 흐르지 않는다. 다만 같은 계좌를 쓰는 호스트가 대부분이라, 두 번
/// 입력하지 않도록 "정산 계좌와 동일한 계좌 사용"으로 값을 복사해 온다
/// (복사는 입력칸만 채우고, 인증은 그대로 다시 받는다).
class PayoutAccountScreen extends StatefulWidget {
  const PayoutAccountScreen({super.key});

  @override
  State<PayoutAccountScreen> createState() => _PayoutAccountScreenState();
}

class _PayoutAccountScreenState extends State<PayoutAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _accountNumberCtrl = TextEditingController();
  final _accountHolderCtrl = TextEditingController();

  String? _bankCode;
  bool _loading = true;
  bool _verifying = false;

  /// 마지막으로 확인한 상태 — 인증 직후 결과 안내에 쓴다.
  PayoutAccount _account = PayoutAccount.none;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _accountNumberCtrl.dispose();
    _accountHolderCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final account = await PayoutAccountService.fetch();
    if (!mounted) return;
    setState(() {
      _account = account;
      _bankCode = account.bankCode;
      _accountNumberCtrl.text = account.accountNumber ?? '';
      _accountHolderCtrl.text = account.accountHolder ?? '';
      _loading = false;
    });
  }

  /// 정산계좌 값을 입력칸으로 복사한다 — **인증은 그대로 다시 받는다.**
  /// (정산계좌는 검증 없이 사용자가 직접 저장한 값이라, 그대로 인증 완료로
  ///  넘길 수 없다.)
  Future<void> _copyFromSettlement() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(UserSession.userId)
          .get();
      final info = snap.data()?['settlementInfo'] as Map<String, dynamic>?;
      final bankCode = BankCodes.codeOf(info?['bankName'] as String?);
      final number = (info?['accountNumber'] as String? ?? '').trim();
      final holder = (info?['accountHolder'] as String? ?? '').trim();
      if (!mounted) return;
      if (number.isEmpty || holder.isEmpty) {
        _msg('정산 계좌에 저장된 계좌가 없어요.');
        return;
      }
      setState(() {
        if (bankCode != null) _bankCode = bankCode;
        _accountNumberCtrl.text = number;
        _accountHolderCtrl.text = holder;
      });
      _msg(
        bankCode == null
            ? '계좌를 가져왔어요. 금융기관만 다시 골라주세요.'
            : '정산 계좌를 가져왔어요. 인증을 진행해주세요.',
      );
    } catch (_) {
      if (mounted) _msg('정산 계좌를 불러오지 못했어요.');
    }
  }

  /// 등록할 계좌의 명의 — 인증 규칙이 여기서 갈린다.
  ///
  /// 개인계좌를 골라도 사업자 인증 상태에는 아무 영향이 없다. 이 값은
  /// "게스트가 입금할 계좌의 명의"만 정한다.
  PayoutAccountType _accountType = PayoutAccountType.personal;

  /// 인증 완료 후 30일 동안은 계좌를 바꿀 수 없다.
  ///
  /// 판정의 정본은 서버다(`functions/payoutAccounts.js`의 lockedUntilOf).
  /// 앱이 먼저 막는 것은 안내를 위해서지 방어가 아니다 — 앱을 우회해
  /// 콜러블을 직접 불러도 서버가 같은 자리에서 거절한다.
  bool get _locked => _account.isChangeLocked;

  /// 인증 직전 한 번 더 묻는다.
  ///
  /// 되돌릴 수 없는 선택이기 때문이다 — 인증에 성공하면 그 계좌가 30일
  /// 동안 고정되고, 그동안 게스트의 입금 안내에 그대로 실린다.
  Future<bool> _confirmVerify() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '이 계좌를 인증할까요?',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        content: Text(
          '인증이 완료되면 ${PayoutAccount.lockDays}일 동안 수취계좌를 변경할 수 없어요. '
          '금융기관, 계좌번호, 예금주명을 다시 한번 확인해주세요.',
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('다시 확인'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: PartyChuColors.primary,
            ),
            child: const Text('인증하기'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _verify() async {
    // 연타 방지 — 버튼도 막지만, 여기서 한 번 더 막아야 다이얼로그가
    // 겹쳐 뜨지 않는다.
    if (_verifying) return;
    if (_locked) {
      _msg(_account.changeLockedMessage);
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (_bankCode == null) {
      _msg('금융기관을 선택해주세요.');
      return;
    }
    if (!await _confirmVerify()) return;
    if (!mounted) return;
    setState(() => _verifying = true);
    try {
      final result = await PayoutAccountService.verify(
        bankCode: _bankCode!,
        accountNumber: _accountNumberCtrl.text.trim(),
        accountHolder: _accountHolderCtrl.text.trim(),
        accountType: _accountType,
      );
      if (!mounted) return;
      setState(() => _account = result);
      _msg(
        result.isVerified
            ? '계좌 인증이 완료됐어요.'
            : result.failReason?.message ?? '인증하지 못했어요. 다시 시도해주세요.',
      );
    } on FirebaseFunctionsException catch (e) {
      // 서버가 이유를 말해 준 경우는 **그대로 보여준다.**
      //
      // 예전에는 여기까지 전부 '잠시 후 다시 시도해주세요'로 뭉갰다. 그런데
      // invalid-argument처럼 다시 시도해도 절대 풀리지 않는 오류까지 일시
      // 장애처럼 보이게 만들어서, 2026-08-25 미래에셋증권 인증 실패 때
      // 서버 로그를 뒤지기 전까지 원인이 전혀 드러나지 않았다.
      //
      // 다만 아무 message나 띄우지는 않는다 — 서버가 사람에게 보여주려고 쓴
      // 문구인 코드만 통과시키고, internal·unknown 같은 내부 오류는 원문
      // 대신 일반 안내로 덮는다.
      debugPrint('[payoutAccount] verify 실패 code=${e.code}');
      const userFacing = {
        'invalid-argument',
        'failed-precondition',
        'permission-denied',
        'unauthenticated',
        'not-found',
        'resource-exhausted',
      };
      final message = (e.message ?? '').trim();
      if (mounted) {
        _msg(
          userFacing.contains(e.code) && message.isNotEmpty
              ? message
              : '인증 요청에 실패했어요. 잠시 후 다시 시도해주세요.',
        );
      }
    } catch (e) {
      if (mounted) _msg('인증 요청에 실패했어요. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  void _msg(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text(
          '💳 무통장입금 수취계좌',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: PartyChuColors.primary),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StatusCard(account: _account),
                    const SizedBox(height: 14),
                    _card(
                      title: '계좌 정보',
                      subtitle:
                          '게스트가 파티 · 예약 신청 후 무통장입금을 선택했을 때 '
                          '실제 입금 안내에 표시되는 계좌예요. '
                          '정확한 계좌를 등록하고 인증해주세요.\n'
                          '인증이 완료된 계좌만 게스트의 무통장입금 계좌로 사용할 수 있어요.',
                      children: [
                        _label('계좌 유형'),
                        _AccountTypePicker(
                          value: _accountType,
                          enabled: !_verifying && !_locked,
                          onChanged: (t) => setState(() => _accountType = t),
                        ),
                        const SizedBox(height: 14),
                        _label('금융기관'),
                        // 은행과 증권사를 한 목록에 담되 머리글로 갈라 둔다.
                        // 증권 계좌(CMA 등)도 팝빌 성명조회 지원기관이라 수취
                        // 계좌로 인증된다 — 목록에서 빼면 실제로는 쓸 수 있는
                        // 계좌를 등록하지 못한다. 머리글은 enabled: false라
                        // 골라지지 않고, 값도 실제 기관코드와 겹치지 않는다.
                        DropdownButtonFormField<String>(
                          initialValue: _bankCode,
                          isExpanded: true,
                          decoration: _dec('금융기관을 선택해주세요'),
                          items: [
                            _groupHeader('bank', '은행'),
                            for (final entry in BankCodes.bankNames.entries)
                              DropdownMenuItem(
                                value: entry.key,
                                child: Text(entry.value),
                              ),
                            _groupHeader('securities', '증권'),
                            for (final entry
                                in BankCodes.securitiesNames.entries)
                              DropdownMenuItem(
                                value: entry.key,
                                child: Text(entry.value),
                              ),
                          ],
                          onChanged: _verifying || _locked
                              ? null
                              : (v) => setState(() => _bankCode = v),
                          validator: (v) =>
                              (v == null || v.isEmpty) ? '금융기관을 선택해주세요' : null,
                        ),
                        const SizedBox(height: 14),
                        _label('계좌번호'),
                        TextFormField(
                          controller: _accountNumberCtrl,
                          enabled: !_verifying && !_locked,
                          keyboardType: TextInputType.number,
                          // 하이픈을 넣어도 서버가 숫자만 남기지만, 애초에
                          // 숫자만 받으면 오타를 줄일 수 있다.
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: _dec('- 없이 숫자만'),
                          validator: (v) {
                            final digits = (v ?? '').trim();
                            if (digits.isEmpty) return '계좌번호를 입력해주세요';
                            if (digits.length < 6) return '계좌번호를 다시 확인해주세요';
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        _label('예금주명'),
                        TextFormField(
                          controller: _accountHolderCtrl,
                          enabled: !_verifying && !_locked,
                          decoration: _dec('통장에 적힌 이름 그대로'),
                          validator: (v) =>
                              (v ?? '').trim().isEmpty ? '예금주명을 입력해주세요' : null,
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _verifying || _locked
                                ? null
                                : _copyFromSettlement,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              foregroundColor: PartyChuColors.primary,
                            ),
                            icon: const Icon(Icons.copy_all_outlined, size: 16),
                            label: const Text(
                              '정산 계좌와 동일한 계좌 사용',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    // 인증 버튼 **바로 위**에 항상 둔다. 인증을 누르기 전에
                    // 30일 고정을 알고 있어야 하기 때문이다.
                    _LockNotice(account: _account),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        // 잠금 중에도 눌리게 둔다 — 눌렀을 때 왜 안 되는지
                        // 알려주는 편이, 아무 반응 없는 버튼보다 낫다.
                        onPressed: _verifying ? null : _verify,
                        style: FilledButton.styleFrom(
                          backgroundColor: PartyChuColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _verifying
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _locked ? '계좌 변경 잠금 중' : '계좌 인증하기',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '· 예금주 조회로 실제 계좌인지 확인해요.\n'
                      '· 인증이 끝난 계좌만 참가자에게 안내돼요.\n'
                      '· 계좌를 바꾸면 인증을 다시 받아야 해요. 이미 안내된 신청 건은 '
                      '그때 안내한 계좌가 그대로 유지돼요.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.6,
                        color: Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text.rich(
      TextSpan(
        text: t,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        children: const [
          TextSpan(
            text: ' *',
            style: TextStyle(
              color: Color(0xFFE5484D),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );

  /// 금융기관 목록의 구분 머리글. 고를 수 없는 항목이라 값은 실제
  /// 기관코드와 절대 겹치지 않는 문자열을 쓴다.
  DropdownMenuItem<String> _groupHeader(String key, String title) =>
      DropdownMenuItem<String>(
        value: '__group_$key',
        enabled: false,
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.black38,
          ),
        ),
      );

  InputDecoration _dec(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.black26, fontSize: 14),
    filled: true,
    fillColor: const Color(0xFFF9FAFB),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: PartyChuColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: PartyChuColors.border),
    ),
  );

  Widget _card({
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: PartyChuColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: Colors.black45,
            ),
          ),
        ],
        const SizedBox(height: 14),
        ...children,
      ],
    ),
  );
}

/// 지금 상태 — 미등록 / 인증 필요 / 인증 완료를 색과 문구로 분명히 가른다.
///
/// '인증 필요'는 그냥 "안 됐다"가 아니라 **왜 안 됐는지**까지 보여준다. 이유를
/// 모르면 같은 계좌를 몇 번이고 다시 넣게 된다.
/// 계좌 유형 고르기 — 대표자 개인계좌 / 사업자 · 법인 계좌.
///
/// 사업자 호스트라고 사업자 명의 계좌를 강제하지 않는다. 대표자 개인계좌로
/// 받겠다고 골라도 사업자 인증 상태·자격에는 아무 영향이 없다 — 이 선택은
/// **게스트가 입금할 계좌의 명의가 무엇인지**만 정한다.
class _AccountTypePicker extends StatelessWidget {
  const _AccountTypePicker({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final PayoutAccountType value;
  final bool enabled;
  final ValueChanged<PayoutAccountType> onChanged;

  static const _hints = {
    PayoutAccountType.personal: '예금주가 본인 이름인 계좌',
    PayoutAccountType.business: '예금주가 상호 · 법인명인 계좌 (사업자 인증 필요)',
  };

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final type in PayoutAccountType.values) ...[
        GestureDetector(
          onTap: enabled ? () => onChanged(type) : null,
          behavior: HitTestBehavior.opaque,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: value == type ? const Color(0xFFFFF0F5) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: value == type
                    ? PartyChuColors.primary
                    : const Color(0xFFE8EBF2),
                width: value == type ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  value == type
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: value == type
                      ? PartyChuColors.primary
                      : Colors.black26,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        type.label,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _hints[type] ?? '',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Colors.black45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ],
  );
}

/// 인증 버튼 바로 위에 붙는 30일 고정 안내.
///
/// 인증 **전에** 보여야 의미가 있는 안내라 상태와 무관하게 항상 그린다.
/// 이미 잠긴 계좌라면 언제 풀리는지까지 함께 알려준다 — 그걸 모르면
/// 호스트는 잠긴 이유가 아니라 "고장"으로 받아들인다.
class _LockNotice extends StatelessWidget {
  const _LockNotice({required this.account});

  final PayoutAccount account;

  @override
  Widget build(BuildContext context) {
    final locked = account.isChangeLocked;
    final releaseDate = account.changeAllowedDateText;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: locked ? const Color(0xFFF3F4F6) : const Color(0xFFFFF8E6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: locked ? const Color(0xFFE5E7EB) : const Color(0xFFFFE0A3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (locked && releaseDate != null) ...[
            Text(
              '🔒 계좌 변경 가능일: $releaseDate',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF374151),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              account.changeLockedMessage,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: Color(0xFF6B7280),
              ),
            ),
          ] else
            Text(
              '⚠️ 계좌 인증 완료 후 ${PayoutAccount.lockDays}일 동안 수취계좌를 '
              '변경할 수 없어요. 실제로 게스트의 무통장입금 안내에 사용될 '
              '계좌인지 꼭 확인해주세요.',
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF8A5A00),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.account});

  final PayoutAccount account;

  @override
  Widget build(BuildContext context) {
    final verified = account.isVerified;
    final none = account.status == PayoutAccountStatus.none;
    final color = verified
        ? const Color(0xFF047857)
        : (none ? Colors.black54 : const Color(0xFFB45309));
    final background = verified
        ? const Color(0xFFECFDF5)
        : (none ? const Color(0xFFF3F4F6) : const Color(0xFFFFFBEB));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                verified
                    ? Icons.verified_outlined
                    : (none
                          ? Icons.account_balance_outlined
                          : Icons.error_outline),
                size: 20,
                color: color,
              ),
              const SizedBox(width: 8),
              Text(
                verified ? '계좌 인증 완료' : account.status.label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(switch (account.status) {
            PayoutAccountStatus.verified =>
              // 본인 화면이라 전체를 보여줘도 되지만, 확인용으로는 뒤 4자리면
              // 충분하다 — 어깨너머로 새는 것까지 줄인다.
              '${account.maskedSummary} · ${account.accountHolder ?? ''}'
                  ' · ${account.accountType.label}\n'
                  '게스트의 무통장입금 안내에 사용됩니다.',
            PayoutAccountStatus.required =>
              account.failReason?.message ?? '계좌 인증이 필요해요. 아래에서 인증을 진행해주세요.',
            PayoutAccountStatus.none => '계좌를 등록하고 인증하면 참가자가 무통장입금으로 신청할 수 있어요.',
          }, style: TextStyle(fontSize: 12.5, height: 1.5, color: color)),
        ],
      ),
    );
  }
}

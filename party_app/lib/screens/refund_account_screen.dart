import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:party_app/models/bank_codes.dart';
import 'package:party_app/services/refund_account_service.dart';

/// 참가자 **환불계좌 관리** — 내가 환불받을 계좌.
///
/// ⚠ 호스트 정산계좌(SettlementInfoScreen)·수취계좌(PayoutAccountScreen)와
///   **다른 화면, 다른 데이터**다.
///   - 정산계좌: 내가 호스트로서 **받을** 정산 대금 → users/{uid}.settlementInfo
///   - 수취계좌: 내가 호스트로서 참가비를 **받을** 계좌 → users/{uid}.payoutAccount
///   - 환불계좌: 내가 참가자로서 **돌려받을** 환불금 → users/{uid}.refundAccount
///   한 사람이 셋 다일 수 있으므로 화면도 필드도 합치지 않는다.
///
/// ── 이제 저장이 아니라 인증이다 ──────────────────────────────────────────
/// 예전에는 은행명을 자유 입력으로 받아 그대로 저장했다. 무통장입금 신청은
/// 취소되면 계좌이체로만 환불할 수 있는데(PG 없음), 그 계좌가 본인 것인지
/// 아무도 확인하지 않아 남의 계좌를 적어 둘 수 있었다. 이제 호스트 수취계좌와
/// **같은 성명조회 엔진**으로 본인 명의를 확인한다
/// (functions/refundAccountVerify.js). 그래서 금융기관도 자유 입력이 아니라
/// 목록에서 고른다 — 성명조회는 기관코드로 하기 때문이다.
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
  final _numberCtrl = TextEditingController();
  final _holderCtrl = TextEditingController();

  String? _bankCode;
  bool _loading = true;
  bool _verifying = false;
  RefundAccountState _state = RefundAccountState.empty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _numberCtrl.dispose();
    _holderCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final state = await RefundAccountService.fetchState();
    if (!mounted) return;
    setState(() {
      _state = state;
      final saved = state.account;
      if (saved != null) {
        _numberCtrl.text = saved.accountNumber;
        _holderCtrl.text = saved.accountHolder;
        // 기관코드가 없던 옛 계좌는 은행명으로 코드를 되찾아 본다 — 찾으면
        // 목록이 그 기관으로 선택된 채 열려 다시 고르지 않아도 된다.
        _bankCode = saved.bankCode.isNotEmpty
            ? saved.bankCode
            : BankCodes.codeOf(saved.bankName);
      }
      _loading = false;
    });
  }

  Future<void> _verify() async {
    if (!_formKey.currentState!.validate()) return;
    final code = _bankCode;
    if (code == null) return;
    setState(() => _verifying = true);
    try {
      final state = await RefundAccountService.verify(
        bankCode: code,
        bankName: BankCodes.nameOf(code) ?? '',
        accountNumber: _numberCtrl.text,
        accountHolder: _holderCtrl.text,
      );
      if (!mounted) return;
      setState(() => _state = state);
      // 실패 문구는 서버가 적어 둔 사유([RefundAccountState.failReason])를
      // 그대로 옮긴다 — 표는 서비스가 들고 있다(화면 안에 두면 검증할 수 없다).
      _snack(
        state.isVerified
            ? '환불계좌 인증이 완료됐어요.'
            : refundAccountFailMessage(state.failReason),
      );
      // 인증에 성공했을 때만 화면을 닫는다 — 실패했는데 닫히면 무엇을
      // 고쳐야 하는지 볼 수가 없다. 신청 흐름에서 들어왔다면 이 pop이
      // 곧바로 결제 단계로 돌려보낸다.
      if (state.isVerified) Navigator.pop(context, true);
    } on RefundAccountVerifyUnavailable catch (e) {
      // 콜러블이 그 이름·리전에 아예 없다 — **인증 실패가 아니라 장애다.**
      //
      // 이 갈래를 따로 두는 이유: 여기로 오는 오류는 사용자의 계좌와 아무
      // 상관이 없다. 계좌 실패 문구와 섞어 놓으면 멀쩡한 계좌를 몇 번이고
      // 다시 치게 만들고, 서버가 안 올라갔다는 사실은 아무 데도 남지 않는다.
      // (실제로 이 화면에서 'NOT_FOUND'가 그대로 노출됐던 원인이다.)
      //
      // 그래서 ⑴ 사용자에게는 "네 잘못이 아니고 지금은 될 수 없다"를 분명히
      // 말하고, ⑵ 다시 시도하라고 하지 않으며, ⑶ 어떤 함수가 어느 리전에서
      // 빠졌는지는 로그로 남긴다.
      debugPrint(
        '[refundAccount] 콜러블 없음 — 배포 필요. '
        'function=${e.functionName} region=${e.region} code=${e.code}',
      );
      if (!mounted) return;
      _snack('계좌 확인 기능이 아직 열리지 않았어요. 입력하신 계좌 문제가 아니니 잠시 뒤 다시 확인해주세요.');
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      // 서버가 사람에게 보여주려고 쓴 문구만 통과시킨다. internal·unknown
      // 같은 내부 오류의 원문은 사용자에게 뜻이 없으므로 덮는다.
      debugPrint('[refundAccount] verify 실패 code=${e.code}');
      const userFacing = {
        'invalid-argument',
        'failed-precondition',
        'permission-denied',
        'unauthenticated',
        'already-exists',
        'resource-exhausted',
      };
      final message = (e.message ?? '').trim();
      _snack(
        userFacing.contains(e.code) && message.isNotEmpty
            ? message
            : '인증에 실패했어요. 잠시 후 다시 시도해주세요.',
      );
    } catch (_) {
      if (!mounted) return;
      _snack('인증에 실패했어요. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

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
                    if (_state.isVerified) _verifiedBadge(),
                    const Text(
                      '무통장입금으로 결제한 신청을 취소하면 이 계좌로 환불해 드려요.\n'
                      '본인 명의 계좌만 인증할 수 있어요.',
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.6,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // 성명조회는 기관코드로 하므로 자유 입력이 아니라 목록이다
                    // (수취계좌 화면과 같은 표 — BankCodes).
                    DropdownButtonFormField<String>(
                      initialValue: _bankCode,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '금융기관',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        _groupHeader('bank', '은행'),
                        for (final entry in BankCodes.bankNames.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        _groupHeader('securities', '증권'),
                        for (final entry in BankCodes.securitiesNames.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                      ],
                      onChanged: _verifying
                          ? null
                          : (v) => setState(() => _bankCode = v),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? '금융기관을 선택해주세요.' : null,
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
                        onPressed: _verifying ? null : _verify,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6FA0),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _verifying ? '확인 중…' : '환불계좌 인증하기',
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

  Widget _verifiedBadge() => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF0F5),
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Row(
      children: [
        Icon(Icons.verified_rounded, size: 18, color: Color(0xFFFF6FA0)),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            '인증 완료된 계좌예요. 계좌를 바꾸면 다시 인증해야 해요.',
            style: TextStyle(fontSize: 12.5, color: Color(0xFFFF6FA0)),
          ),
        ),
      ],
    ),
  );

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
}

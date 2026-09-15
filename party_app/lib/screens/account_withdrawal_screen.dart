import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:party_app/services/account_withdrawal_service.dart';
import 'package:party_app/utils/apple_sign_in.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/web_frame.dart';

/// 회원 탈퇴 신청 화면.
///
/// 되돌릴 수 없는 동작이라 확인을 두 번 받는다(동의 체크 → 문구 직접 입력).
/// 다만 "무섭게 만들기"가 목적이 아니라 **오탭으로 계정이 사라지지 않게** 하는
/// 것이 목적이라, 정말 하려는 사람이 헤매지 않도록 단계는 한 화면에 모았다.
///
/// 진행 중인 거래가 있으면 신청 자체가 막힌다. 그때 "탈퇴할 수 없습니다"로
/// 끝내지 않고 무엇이 몇 건 남았는지 그대로 보여준다 — 사용자가 다음에 무엇을
/// 해야 하는지 알 수 없으면 결국 고객센터로 오게 된다.
class AccountWithdrawalScreen extends StatefulWidget {
  const AccountWithdrawalScreen({super.key});

  @override
  State<AccountWithdrawalScreen> createState() =>
      _AccountWithdrawalScreenState();
}

class _AccountWithdrawalScreenState extends State<AccountWithdrawalScreen> {
  static const _confirmPhrase = '탈퇴합니다';

  WithdrawalStatus? _status;
  String? _loadError;
  bool _agreed = false;
  bool _submitting = false;
  final _confirmCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  String? _reasonCode;

  /// 서버가 받아주는 사유 코드 — accountWithdrawal.js의 WITHDRAWAL_REASON_CODES와
  /// 같은 값이어야 한다. 목록에 없는 코드는 서버가 조용히 버린다(신청은 통과).
  static const _reasonOptions = <String, String>{
    'no_longer_use': '더 이상 이용하지 않아요',
    'few_listings': '원하는 파티·장소가 없어요',
    'privacy': '개인정보가 걱정돼요',
    'bad_experience': '이용 중 불쾌한 경험이 있었어요',
    'app_issue': '앱이 불편하거나 오류가 있어요',
    'price': '비용이 부담돼요',
    'switch_account': '다른 계정으로 옮길 거예요',
    'other': '기타',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _confirmCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _status = null;
      _loadError = null;
    });
    try {
      final s = await AccountWithdrawalService.fetchStatus();
      if (mounted) setState(() => _status = s);
    } catch (e) {
      if (mounted) {
        setState(() => _loadError = '탈퇴 가능 여부를 확인하지 못했어요. 잠시 후 다시 시도해주세요.');
      }
    }
  }

  Future<void> _submit() async {
    final s = _status;
    if (s == null || _submitting) return;

    setState(() => _submitting = true);
    try {
      // Apple로 가입한 계정은 탈퇴 신청 **전에** Apple 토큰을 폐기한다
      // (App Review 5.1.1(v)). 폐기에 실패하면 신청을 보내지 않는다 — 계정만
      // 탈퇴 처리되고 Apple 쪽 연결이 남는 상태를 만들지 않기 위해서다.
      // Google·카카오·네이버 계정은 이 블록을 통째로 건너뛴다.
      if (AppleSignIn.usesApple(FirebaseAuth.instance.currentUser)) {
        // 화면을 연 뒤 새 거래가 생겼으면 토큰부터 폐기하지 않도록 먼저 다시 본다.
        final latest = await AccountWithdrawalService.fetchStatus();
        if (!mounted) return;
        if (!latest.canRequest) {
          setState(() => _status = latest);
          return;
        }
        if (!await _revokeAppleToken()) return;
        if (!mounted) return;
      }

      final result = await AccountWithdrawalService.request(
        reason: _reasonCtrl.text,
        reasonCode: _reasonCode,
      );
      if (!mounted) return;

      if (result.blockers.isNotEmpty) {
        // 화면을 연 뒤에 새 예약이 생겼을 수 있다. (_submitting 해제는 finally에서)
        setState(() => _status = result);
        return;
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text('탈퇴 신청이 접수되었어요'),
          content: Text(
            '${result.graceDays}일 뒤 탈퇴가 완료됩니다.\n'
            '그 전까지는 마이페이지에서 언제든 취소할 수 있어요.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      // 로그아웃시키지 않는다. 대기 중에도 사용자는 로그인한 상태로 남아 남은
      // 기간을 보고 직접 취소할 수 있어야 한다 — 여기서 세션을 끊으면 취소하려고
      // 다시 로그인해야 하고, 그 사이 무슨 일이 벌어지는지 알 방법이 없다.
      // 세션 상태만 바꾸면 루트 게이트가 스스로 대기 화면으로 바꿔 그린다.
      UserSession.applyWithdrawalRequested(result.scheduledAt);
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('탈퇴 신청에 실패했어요. 잠시 후 다시 시도해주세요.')),
      );
    } finally {
      // 성공 경로에서는 이 화면이 곧 사라지지만, 실패·차단 어느 쪽으로 빠지든
      // 버튼이 스피너로 굳지 않도록 한 곳에서 확실히 푼다.
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Apple 계정 탈퇴 전 토큰 폐기 — 재인증으로 새 authorization code를 받아
  /// `revokeTokenWithAuthorizationCode`를 부른다. 성공해야만 true.
  ///
  /// 실패·취소를 무시하고 탈퇴를 이어가지 않는다. 사용자에게 다시 시도하라고
  /// 안내하고 신청은 보내지 않는다.
  Future<bool> _revokeAppleToken() async {
    final messenger = ScaffoldMessenger.of(context);
    void notify(String message) =>
        messenger.showSnackBar(SnackBar(content: Text(message)));

    // Apple 로그인은 iOS에만 있다 — 다른 기기에서는 재인증 창을 띄울 수 없다.
    if (!AppleSignIn.isAvailable) {
      notify('Apple로 가입한 계정은 iPhone의 파티츄 앱에서 탈퇴를 진행해주세요.');
      return false;
    }

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Apple 계정 확인이 필요해요'),
        content: const Text(
          'Apple로 가입한 계정은 탈퇴 전에 Apple 계정 연결을 해제합니다.\n'
          '다음 화면에서 Apple 계정을 한 번 더 확인해주세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('계속'),
          ),
        ],
      ),
    );
    if (proceed != true) return false;

    try {
      await AppleSignIn.revokeForAccountDeletion();
      return true;
    } catch (e) {
      debugPrint(
        '[Withdrawal] Apple 토큰 폐기 실패: '
        '${e is FirebaseAuthException ? e.code : e.runtimeType}',
      );
      notify(
        AppleSignIn.isCancellation(e)
            ? 'Apple 계정 확인이 취소되어 탈퇴를 진행하지 않았어요.'
            : 'Apple 계정 연결 해제에 실패해 탈퇴를 진행하지 않았어요. 잠시 후 다시 시도해주세요.',
      );
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('회원 탈퇴', style: TextStyle(color: Colors.black87)),
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: _loadError != null
          ? _ErrorView(message: _loadError!, onRetry: _load)
          : _status == null
          ? const Center(child: CircularProgressIndicator())
          : _body(_status!),
    );
  }

  Widget _body(WithdrawalStatus s) {
    if (s.blockers.isNotEmpty) return _BlockerView(blockers: s.blockers);

    final canSubmit =
        _agreed && _confirmCtrl.text.trim() == _confirmPhrase && !_submitting;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        _NoticeCard(graceDays: s.graceDays),
        const SizedBox(height: 20),
        const _SectionTitle('탈퇴하면 이렇게 됩니다'),
        const SizedBox(height: 10),
        const _Bullet('닉네임·이메일·프로필 사진, 본인확인 정보(이름·생년월일·성별)가 삭제됩니다.'),
        const _Bullet('입금받을 계좌·환불 계좌·정산 계좌·사업자 정보가 삭제됩니다.'),
        const _Bullet('찜, 임시저장, 알림 신청, 푸시 알림 설정이 삭제됩니다.'),
        const _Bullet('올리신 사진과 영상이 삭제됩니다.'),
        const SizedBox(height: 18),
        const _SectionTitle('법에 따라 남는 것'),
        const SizedBox(height: 10),
        const _Bullet('결제·예약·주문 기록은 5년간 보관됩니다(전자상거래법).'),
        const _Bullet('환불·신고·문의 기록은 3년간 보관됩니다.'),
        const _Bullet('접속 기록은 3개월간 보관됩니다.'),
        const _Bullet('남는 기록에서 이름은 "탈퇴한 회원"으로 바뀝니다.'),
        const SizedBox(height: 18),
        const _SectionTitle('재가입 제한'),
        const SizedBox(height: 10),
        const _Bullet('탈퇴가 완료된 날부터 30일간은 같은 본인인증으로 다시 가입할 수 없습니다.'),
        const SizedBox(height: 24),

        const _SectionTitle('탈퇴 사유 (선택)'),
        const SizedBox(height: 8),
        // 선택형 사유는 계정에 코드로 남아 운영이 이탈 원인을 본다. 아래
        // 자유서술은 계정과 분리해 따로 쌓이므로(서버가 uid를 붙이지 않는다)
        // 여기에 적은 내용이 탈퇴 후에도 내 계정에 남지는 않는다.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in _reasonOptions.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: _reasonCode == e.key,
                onSelected: (sel) =>
                    setState(() => _reasonCode = sel ? e.key : null),
                selectedColor: const Color(0xFFFFE3EE),
                labelStyle: TextStyle(
                  fontSize: 13,
                  color: _reasonCode == e.key
                      ? const Color(0xFFC2185B)
                      : Colors.black87,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: _reasonCode == e.key
                        ? const Color(0xFFFF6FA0)
                        : Colors.grey.shade300,
                  ),
                ),
                backgroundColor: Colors.white,
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _reasonCtrl,
          maxLines: 3,
          maxLength: 500,
          decoration: InputDecoration(
            hintText: '개선에 참고할게요. 적지 않으셔도 됩니다.',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
          ),
        ),
        const SizedBox(height: 8),

        CheckboxListTile(
          value: _agreed,
          onChanged: (v) => setState(() => _agreed = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          activeColor: const Color(0xFFFF6FA0),
          title: const Text(
            '위 내용을 모두 확인했으며, 탈퇴에 동의합니다.',
            style: TextStyle(fontSize: 14),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '확인을 위해 아래에 "$_confirmPhrase"라고 입력해주세요.',
          style: const TextStyle(fontSize: 13, color: Colors.black54),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _confirmCtrl,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: _confirmPhrase,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 52,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              disabledBackgroundColor: Colors.grey.shade300,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: canSubmit ? _submit : null,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('탈퇴 신청하기', style: TextStyle(fontSize: 16)),
          ),
        ),
      ],
    );
  }
}

/// 대기 기간 안내 — 화면에서 가장 먼저 읽혀야 하는 내용이다.
class _NoticeCard extends StatelessWidget {
  final int graceDays;
  const _NoticeCard({required this.graceDays});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFCC80)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFE65100), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '탈퇴 신청 후 $graceDays일간 탈퇴 대기 상태가 유지되며, 기간 내 탈퇴를 '
              '취소할 수 있습니다. $graceDays일이 지나면 계정 및 즉시 삭제 대상 '
              '개인정보는 복구할 수 없습니다.',
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Color(0xFF5D4037),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlockerView extends StatelessWidget {
  final List<WithdrawalBlocker> blockers;
  const _BlockerView({required this.blockers});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '먼저 정리할 것이 있어요',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                '진행 중인 거래가 남아 있으면 탈퇴할 수 없습니다. '
                '취소·환불이 끝난 뒤 다시 시도해주세요.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.black54,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              ...blockers.map(
                (b) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.remove_circle_outline,
                        size: 18,
                        color: Color(0xFFD32F2F),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          b.message,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
  );
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 7, right: 8),
          child: SizedBox(
            width: 4,
            height: 4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black38,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    ),
  );
}

/// 마이페이지에서 탈퇴 화면으로 보내는 진입점.
Route<void> accountWithdrawalRoute() =>
    webFramedRoute((_) => const AccountWithdrawalScreen());

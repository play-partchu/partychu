import 'package:flutter/material.dart';

import 'package:party_app/services/account_withdrawal_service.dart';
import 'package:party_app/utils/user_session.dart';

/// 탈퇴 대기 중인 계정이 로그인했을 때 대신 보이는 화면.
///
/// 대기 중에는 서비스를 쓸 수 없다. 그 상태로 메인 화면을 열어두면 버튼마다
/// 실패하는 앱이 되고, 사용자는 왜 안 되는지 모른다. 그래서 아예 이 화면으로
/// 대체하고, 여기서 할 수 있는 일 두 가지(취소·로그아웃)만 남긴다.
///
/// 완전 탈퇴는 서버 스케줄러가 처리하므로 이 화면을 열어두지 않아도 진행된다.
class WithdrawalPendingScreen extends StatefulWidget {
  final WithdrawalStatus status;

  /// 취소에 성공해 계정이 복구됐을 때 호출된다(앱을 정상 화면으로 되돌리는 몫은
  /// 부르는 쪽에 있다 — 이 화면은 자기 자신을 어떻게 치울지 모른다).
  final VoidCallback onRestored;

  const WithdrawalPendingScreen({
    super.key,
    required this.status,
    required this.onRestored,
  });

  @override
  State<WithdrawalPendingScreen> createState() =>
      _WithdrawalPendingScreenState();
}

class _WithdrawalPendingScreenState extends State<WithdrawalPendingScreen> {
  bool _busy = false;

  Future<void> _cancel() async {
    if (_busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('탈퇴를 취소할까요?'),
        content: const Text('계정이 원래대로 복구되고 바로 다시 이용할 수 있어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('닫기', style: TextStyle(color: Colors.black45)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '탈퇴 취소하기',
              style: TextStyle(color: Color(0xFFFF6FA0)),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await AccountWithdrawalService.cancel();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('탈퇴가 취소되었어요. 계정이 복구되었습니다.')));
      // 서버가 active로 돌려놨다는 사실을 세션에 먼저 반영한다. 이걸 빠뜨리면
      // onRestored()로 부모를 다시 그려도 부모가 읽는 상태가 그대로라 같은
      // 대기 화면이 다시 올라오고, 사용자는 앱을 껐다 켜야만 빠져나올 수 있었다.
      UserSession.applyWithdrawalCancelled();
      widget.onRestored();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('탈퇴 취소에 실패했어요. 잠시 후 다시 시도해주세요.')),
      );
    } finally {
      // 성공하면 이 화면 자체가 트리에서 빠지므로 mounted가 이미 false다.
      // 실패·예외 어느 쪽으로 빠지든 버튼이 스피너로 굳지 않게 한 곳에서 푼다.
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await UserSession.signOut();
      if (mounted) widget.onRestored();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.status;
    final days = s.daysLeft;
    // 정산 확인 때문에 완료가 미뤄진 경우 — 사용자는 "7일이 지났는데 왜 그대로냐"를
    // 알 수 없으므로 이유를 말해준다.
    final onHold = s.hold != null && days == 0;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F8),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.hourglass_top,
                  size: 56,
                  color: Color(0xFFE65100),
                ),
                const SizedBox(height: 20),
                const Text(
                  '탈퇴 대기 중입니다',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  onHold
                      ? '정산 확인이 끝나면 탈퇴가 완료됩니다.\n확인에는 영업일이 걸릴 수 있어요.'
                      : days > 0
                      ? '$days일 뒤 탈퇴가 완료됩니다.\n그 전까지는 언제든 취소할 수 있어요.'
                      : '곧 탈퇴가 완료됩니다.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.6,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: const Text(
                    '탈퇴 대기 중에는 파티 신청·예약·채팅·등록 등 서비스를 이용할 수 '
                    '없습니다. 탈퇴가 완료되면 계정과 개인정보는 복구할 수 없습니다.',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6FA0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _busy ? null : _cancel,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            '탈퇴 취소하고 계속 이용하기',
                            style: TextStyle(fontSize: 16),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _busy ? null : _signOut,
                  child: const Text(
                    '로그아웃',
                    style: TextStyle(color: Colors.black45),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

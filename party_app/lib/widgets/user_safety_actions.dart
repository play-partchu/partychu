import 'package:flutter/material.dart';
import 'package:party_app/models/report_reason.dart';
import 'package:party_app/services/block_service.dart';
import 'package:party_app/services/report_service.dart';
import 'package:party_app/utils/user_session.dart';

/// 신고·차단 진입 — 앱 전체가 **이 파일 하나**를 쓴다.
///
/// 파티 상세, 플레이스 상세, 채팅방 등 부르는 자리는 여럿이지만 문구·확인
/// 절차·사유 목록은 하나여야 한다. 화면마다 따로 만들면 "여기서는 차단이
/// 되는데 저기서는 안 된다"가 생긴다.
///
/// ── 신고와 차단을 한 줄씩 나란히, 그러나 명확히 구분해서 보여준다 ────────
///   · 신고 = 운영자에게 알린다. 상대 화면은 그대로다.
///   · 차단 = 내 화면에서 안 보이게 한다. 운영자에게 가지 않는다.
/// 둘을 묶어 "신고 및 차단" 한 버튼으로 만들지 않는다 — 사용자가 무엇을 했는지
/// 모르게 되고, Google Play가 요구하는 것도 각각의 기능이다.
const _pink = Color(0xFFFF6FA0);

/// 신고/차단 메뉴를 띄운다.
///
/// [targetUserId]가 비어 있으면 차단 항목은 나오지 않는다(누구를 차단할지
/// 모르는 상태 — 예: 작성자 uid가 없는 옛 문서).
Future<void> showUserSafetySheet(
  BuildContext context, {
  required String targetType,
  required String targetId,
  String targetUserId = '',
  String targetUserName = '',
  String targetTitle = '',
}) async {
  final me = UserSession.userId;
  if (me.isEmpty) {
    _toast(context, '로그인 후 이용할 수 있어요.');
    return;
  }
  // 본인 것에는 신고·차단이 뜨지 않는다.
  final isMine =
      (targetUserId.isNotEmpty && targetUserId == me) ||
      (targetType == ReportTargetType.user && targetId == me);
  if (isMine) {
    _toast(context, '내 게시물이나 계정은 신고·차단할 수 없어요.');
    return;
  }

  final canBlock = targetUserId.isNotEmpty && targetUserId != me;
  final alreadyBlocked =
      canBlock && await BlockService.isBlockedFromServer(targetUserId);
  if (!context.mounted) return;

  final name = targetUserName.isNotEmpty ? targetUserName : '이 사용자';

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.flag_outlined, color: _pink),
            title: const Text('신고하기', style: TextStyle(fontSize: 14.5)),
            subtitle: const Text(
              '운영자가 확인합니다. 상대에게 알려지지 않아요.',
              style: TextStyle(fontSize: 12, color: Colors.black45),
            ),
            onTap: () {
              Navigator.pop(ctx);
              showReportSheet(
                context,
                targetType: targetType,
                targetId: targetId,
                targetUserId: targetUserId,
                targetTitle: targetTitle,
              );
            },
          ),
          if (canBlock)
            ListTile(
              leading: Icon(
                alreadyBlocked ? Icons.lock_open : Icons.block,
                color: alreadyBlocked ? Colors.black45 : _pink,
              ),
              title: Text(
                alreadyBlocked ? '차단 해제' : '$name 차단하기',
                style: const TextStyle(fontSize: 14.5),
              ),
              subtitle: Text(
                alreadyBlocked
                    ? '다시 이 사용자의 글과 대화가 보입니다.'
                    : '이 사용자의 글과 대화가 보이지 않게 됩니다.',
                style: const TextStyle(fontSize: 12, color: Colors.black45),
              ),
              onTap: () {
                Navigator.pop(ctx);
                if (alreadyBlocked) {
                  confirmUnblock(context, targetUserId, targetUserName);
                } else {
                  confirmBlock(context, targetUserId, targetUserName);
                }
              },
            ),
          ListTile(
            leading: const Icon(Icons.close, color: Colors.black45),
            title: const Text(
              '취소',
              style: TextStyle(fontSize: 14.5, color: Colors.black54),
            ),
            onTap: () => Navigator.pop(ctx),
          ),
          const SizedBox(height: 4),
        ],
      ),
    ),
  );
}

// ── 차단 ─────────────────────────────────────────────────────────────────

/// 차단 전 확인 다이얼로그 → 확인하면 차단한다.
///
/// **무엇이 일어나는지 그대로 적는다.** 특히 "상대는 알 수 없다"를 명시한다 —
/// 차단이 상대에게 통보되는 줄 알면 아무도 쓰지 못한다.
Future<bool> confirmBlock(
  BuildContext context,
  String targetUserId,
  String targetUserName,
) async {
  final name = targetUserName.isNotEmpty ? targetUserName : '이 사용자';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('$name님을 차단할까요?', style: const TextStyle(fontSize: 16)),
      content: const Text(
        '차단하면 이런 일이 생겨요.\n\n'
        '· 이 사용자가 올린 파티·플레이스·장소대여·파티샵·파티크루가 목록에서 보이지 않아요.\n'
        '· 이 사용자와 새로 1:1 채팅을 시작할 수 없어요(양쪽 모두).\n'
        '· 기존 대화는 목록에서 숨겨져요.\n\n'
        '상대방에게는 차단 사실이 알려지지 않아요. '
        '차단은 마이페이지 > 차단한 사용자에서 언제든 해제할 수 있어요.',
        style: TextStyle(fontSize: 13.5, height: 1.55),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('취소', style: TextStyle(color: Colors.black54)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('차단', style: TextStyle(color: _pink)),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;

  try {
    await BlockService.block(targetUserId, targetName: targetUserName);
    if (context.mounted) _toast(context, '$name님을 차단했어요.');
    return true;
  } catch (_) {
    // 실패했으면 차단된 척하지 않는다.
    if (context.mounted) _toast(context, '차단하지 못했어요. 잠시 후 다시 시도해주세요.');
    return false;
  }
}

/// 차단 해제 확인 → 해제한다.
Future<bool> confirmUnblock(
  BuildContext context,
  String targetUserId,
  String targetUserName,
) async {
  final name = targetUserName.isNotEmpty ? targetUserName : '이 사용자';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('$name님 차단을 해제할까요?', style: const TextStyle(fontSize: 16)),
      content: const Text(
        '이 사용자의 글과 대화가 다시 보이고, 서로 채팅을 시작할 수 있게 됩니다.',
        style: TextStyle(fontSize: 13.5, height: 1.55),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('취소', style: TextStyle(color: Colors.black54)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('차단 해제', style: TextStyle(color: _pink)),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;

  try {
    await BlockService.unblock(targetUserId);
    if (context.mounted) _toast(context, '차단을 해제했어요.');
    return true;
  } catch (_) {
    if (context.mounted) _toast(context, '차단을 해제하지 못했어요. 잠시 후 다시 시도해주세요.');
    return false;
  }
}

// ── 신고 ─────────────────────────────────────────────────────────────────

/// 신고 사유 선택 + 상세 입력 시트.
Future<void> showReportSheet(
  BuildContext context, {
  required String targetType,
  required String targetId,
  String targetUserId = '',
  String targetTitle = '',
}) async {
  if (UserSession.userId.isEmpty) {
    _toast(context, '로그인 후 이용할 수 있어요.');
    return;
  }

  final already = await ReportService.alreadyReported(
    targetType: targetType,
    targetId: targetId,
  );
  if (!context.mounted) return;
  if (already) {
    _toast(context, '이미 신고한 대상이에요. 운영자가 확인하고 있습니다.');
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ReportSheet(
      targetType: targetType,
      targetId: targetId,
      targetUserId: targetUserId,
      targetTitle: targetTitle,
    ),
  );
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({
    required this.targetType,
    required this.targetId,
    required this.targetUserId,
    required this.targetTitle,
  });

  final String targetType;
  final String targetId;
  final String targetUserId;
  final String targetTitle;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  String? _reason;
  final _detailCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _detailCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    final r = _reason;
    if (r == null || _submitting) return false;
    if (ReportReason.requiresDetail(r) && _detailCtrl.text.trim().isEmpty) {
      return false;
    }
    return true;
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null) return;
    setState(() => _submitting = true);
    try {
      final result = await ReportService.submit(
        targetType: widget.targetType,
        targetId: widget.targetId,
        targetUserId: widget.targetUserId.isEmpty ? null : widget.targetUserId,
        targetTitle: widget.targetTitle,
        reason: reason,
        detail: _detailCtrl.text,
      );
      if (!mounted) return;
      Navigator.pop(context);
      _toast(
        context,
        result == ReportSubmitResult.alreadyReported
            ? '이미 신고한 대상이에요. 운영자가 확인하고 있습니다.'
            : '신고가 접수되었어요. 운영자가 확인 후 조치합니다.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _toast(context, '신고를 접수하지 못했어요. 잠시 후 다시 시도해주세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${ReportTargetType.label(widget.targetType)} 신고',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '신고 내용은 운영자만 확인하며, 상대방에게 알려지지 않아요.\n'
                '신고만으로 글이 지워지거나 계정이 정지되지는 않습니다.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.black45,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                '신고 사유',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              ...ReportReason.all.map(
                (r) => InkWell(
                  onTap: _submitting ? null : () => setState(() => _reason = r),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(
                      children: [
                        Icon(
                          _reason == r
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 20,
                          color: _reason == r ? _pink : Colors.black26,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            ReportReason.label(r),
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _detailCtrl,
                enabled: !_submitting,
                maxLines: 4,
                maxLength: 1000,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText:
                      _reason != null && ReportReason.requiresDetail(_reason!)
                      ? '상세 내용 (필수)'
                      : '상세 내용 (선택)',
                  hintText: ReportReason.hint(_reason ?? ''),
                  hintStyle: const TextStyle(
                    fontSize: 13,
                    color: Colors.black26,
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _canSubmit ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _pink,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('신고하기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// 상세 화면 상단 바에 놓는 신고·차단 진입 버튼.
///
/// 파티·플레이스·장소대여·파티샵·파티크루 상세가 전부 이 하나를 쓴다 —
/// 화면마다 아이콘과 문구가 달라지지 않게 하려는 것이다.
///
/// 내 글에서는 **아무것도 그리지 않는다**(본인 신고·차단 불가). 작성자 uid를
/// 모르는 옛 문서에서는 신고만 가능하고 차단 항목은 나오지 않는다.
class SafetyMenuButton extends StatelessWidget {
  const SafetyMenuButton({
    super.key,
    required this.targetType,
    required this.targetId,
    this.targetUserId = '',
    this.targetUserName = '',
    this.targetTitle = '',
  });

  final String targetType;
  final String targetId;
  final String targetUserId;
  final String targetUserName;
  final String targetTitle;

  @override
  Widget build(BuildContext context) {
    final me = UserSession.userId;
    if (me.isEmpty || targetId.isEmpty) return const SizedBox.shrink();
    if (targetUserId.isNotEmpty && targetUserId == me) {
      return const SizedBox.shrink();
    }
    return IconButton(
      tooltip: '신고 · 차단',
      icon: const Icon(Icons.more_vert),
      onPressed: () => showUserSafetySheet(
        context,
        targetType: targetType,
        targetId: targetId,
        targetUserId: targetUserId,
        targetUserName: targetUserName,
        targetTitle: targetTitle,
      ),
    );
  }
}

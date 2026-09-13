import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:party_app/services/host_refund_service.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/utils/format_utils.dart';
import 'package:party_app/widgets/auth_rebuilder.dart';
import 'package:party_app/widgets/partychu_ui.dart';

/// 호스트의 **환불 요청 처리** 화면.
///
/// 참가비를 호스트 계좌로 직접 받았으므로 환불도 호스트가 보낸다. 이 화면이
/// 하는 일은 셋뿐이다.
///   1. 돌려줄 건과 금액을 보여준다
///   2. 참가자가 등록한 환불계좌를 보여준다(복사)
///   3. 보냈다고 **표시**한다
///
/// ⚠ 3번은 송금 증명이 아니다. 시스템은 이체를 확인할 수 없고, 문서에도
///   "호스트가 보냈다고 표시함"으로 남는다. 그래서 버튼 문구도 '환불 완료'가
///   아니라 '송금했어요'다 — 자동 송금처럼 읽히면 분쟁 때 서로 다른 것을
///   가리키게 된다.
class HostRefundRequestsScreen extends StatelessWidget {
  const HostRefundRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text(
          '환불 요청',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
      body: AuthRebuilder(
        builder: (context) =>
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: HostRefundService.watchForHost(),
              builder: (context, snap) {
                if (snap.hasError) {
                  logFirestoreStreamError(
                    'HostRefundRequests',
                    snap.error,
                    snap.stackTrace,
                  );
                  return const Center(
                    child: Text(
                      '환불 요청을 불러오지 못했어요.',
                      style: TextStyle(fontSize: 13.5, color: Colors.black45),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: PartyChuColors.primary,
                    ),
                  );
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const PawEmptyState(
                    title: '처리할 환불이 없어요',
                    subtitle: '참가자가 취소해 돌려줄 돈이 생기면 여기에 표시돼요.',
                    icon: Icons.receipt_long_outlined,
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  itemCount: docs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _RefundCard(doc: docs[i]),
                );
              },
            ),
      ),
    );
  }
}

class _RefundCard extends StatefulWidget {
  const _RefundCard({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  State<_RefundCard> createState() => _RefundCardState();
}

class _RefundCardState extends State<_RefundCard> {
  bool _sending = false;

  Map<String, dynamic> get _d => widget.doc.data();

  Map<String, dynamic> get _account =>
      (_d['account'] as Map<String, dynamic>?) ?? const {};

  String get _status => _d['status'] as String? ?? '';

  bool get _pending => _status == HostRefundService.statusRequested;

  /// 접수된 지 오래됐는데 아직 안 보낸 건 — 참가자는 그동안 돈 없이 기다린다.
  bool get _overdue {
    if (!_pending) return false;
    final created = _d['createdAt'];
    if (created is! Timestamp) return false;
    return DateTime.now().difference(created.toDate()).inDays >= 3;
  }

  Future<void> _markSent() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          '송금을 마치셨나요?',
          style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
        ),
        content: Text(
          '아래 계좌로 ${formatWon(_amount)}을 보냈다고 표시해요.\n'
          '참가자에게는 "보냈다고 확인됨"으로 안내되고, 되돌릴 수 없어요.\n\n'
          '${_accountLine()}',
          style: const TextStyle(fontSize: 13.5, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: Colors.black45),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: PartyChuColors.primary,
            ),
            child: const Text('송금했어요'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(reject: false);
  }

  Future<void> _reject() async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          '환불 요청을 반려할까요?',
          style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '사유가 참가자에게 그대로 전달돼요. 참가자는 계좌를 고쳐 다시 낼 수 있어요.',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '반려 사유 (필수)',
                hintText: '예: 예금주가 신청자 본인과 달라요',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(foregroundColor: Colors.black45),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE5484D),
            ),
            child: const Text('반려'),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;
    await _run(reject: true, memo: reason);
  }

  Future<void> _run({required bool reject, String? memo}) async {
    setState(() => _sending = true);
    try {
      await HostRefundService.complete(
        requestId: widget.doc.id,
        reject: reject,
        memo: memo,
      );
      if (!mounted) return;
      _msg(reject ? '반려했어요.' : '송금 완료로 표시했어요.');
    } catch (e) {
      if (mounted) _msg('처리하지 못했어요. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _msg(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );

  int get _amount => (_d['refundAmount'] as num?)?.toInt() ?? 0;

  String _accountLine() =>
      '${_account['bankName'] ?? '-'} ${_account['accountNumber'] ?? '-'} '
      '(${_account['accountHolder'] ?? '-'})';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _overdue ? const Color(0xFFE5484D) : PartyChuColors.border,
          width: _overdue ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _statusChip(),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _d['title'] as String? ?? '취소된 신청',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '돌려줄 금액 ${formatWon(_amount)}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFFE2568A),
            ),
          ),
          const SizedBox(height: 8),
          // 참가자 계좌는 **송금하려면 전체가 필요하다** — 여기서 마스킹하면
          // 이체를 할 수 없다. 대신 이 화면은 해당 건의 호스트에게만 열린다
          // (firestore.rules) 그리고 로그·분석에는 절대 남기지 않는다.
          Row(
            children: [
              Expanded(
                child: Text(
                  _accountLine(),
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: Colors.black87,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () async {
                  await Clipboard.setData(
                    ClipboardData(
                      text:
                          '${_account['bankName'] ?? ''} '
                          '${(_account['accountNumber'] as String? ?? '').replaceAll('-', '')}',
                    ),
                  );
                  if (!context.mounted) return;
                  _msg('계좌번호를 복사했어요.');
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    '복사',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFE2568A),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_overdue) ...[
            const SizedBox(height: 8),
            const Text(
              '접수된 지 3일이 넘었어요. 참가자가 기다리고 있어요.',
              style: TextStyle(fontSize: 12, color: Color(0xFFE5484D)),
            ),
          ],
          if (_status == HostRefundService.statusRejected &&
              (_d['rejectedReason'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '반려 사유: ${_d['rejectedReason']}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
          if (_pending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _sending ? null : _reject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE5484D),
                      side: const BorderSide(color: Color(0xFFE5484D)),
                    ),
                    child: const Text('반려'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _sending ? null : _markSent,
                    style: FilledButton.styleFrom(
                      backgroundColor: PartyChuColors.primary,
                    ),
                    child: Text(_sending ? '처리 중...' : '송금했어요'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusChip() {
    final (label, color) = switch (_status) {
      HostRefundService.statusCompleted => ('송금 표시함', const Color(0xFF047857)),
      HostRefundService.statusRejected => ('반려', Colors.black45),
      _ => ('보내야 함', const Color(0xFFE2568A)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../theme/admin_theme.dart';

/// 환불 요청 **감시·개입** 화면.
///
/// 참가비는 파티츄가 아니라 **호스트가 직접** 받으므로(users/{uid}.payoutAccount)
/// 환불도 그 호스트가 자기 계좌에서 보낸다. 기본 처리자는 호스트이고, 이 화면은
/// 전체 큐를 보면서 오래 방치된 건에 운영자가 끼어들기 위한 자리다.
///
/// 자동 송금(PG 환불 API)은 아직 없다. 그래서 '완료'는 누가 눌렀든 송금 증명이
/// 아니라 **보냈다고 표시한 것**이다(completionMethod: marked_manually).
///
/// ⚠ 문서를 직접 수정하지 않는다. 완료 처리는 반드시 서버 함수
///   completeRefundRequest를 부른다 — 규칙상 클라이언트는 refundRequests에
///   아무것도 쓸 수 없고(firestore.rules), 중복 처리 차단도 서버 트랜잭션이
///   최종 판정한다.
///
/// ⚠ 계좌번호는 송금에 필요하므로 화면에는 그대로 보여주지만,
///   **로그·analytics·오류 메시지에는 절대 남기지 않는다**(_mask 참고).
class RefundRequestsScreen extends StatefulWidget {
  const RefundRequestsScreen({super.key});

  @override
  State<RefundRequestsScreen> createState() => _RefundRequestsScreenState();
}

class _RefundRequestsScreenState extends State<RefundRequestsScreen> {
  /// 처리 중인 요청 id — 같은 건을 두 번 누르지 못하게 막는 UI측 방어.
  final _busy = <String>{};

  Query<Map<String, dynamic>> get _query => FirebaseFirestore.instance
      .collection('refundRequests')
      .where('status', isEqualTo: 'requested');

  static String _fmtDate(dynamic v) {
    if (v is Timestamp) {
      return DateFormat('yyyy.MM.dd HH:mm').format(v.toDate());
    }
    return '-';
  }

  static String _won(dynamic v) {
    final n = (v is num) ? v.toInt() : 0;
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '$b원';
  }

  /// 로그·오류 문구에 쓸 마스킹 값 — 원문 계좌번호를 남기지 않기 위한 것.
  static String _mask(String? account) {
    final a = (account ?? '').trim();
    if (a.length <= 4) return '****';
    return '${a.substring(0, 2)}****${a.substring(a.length - 2)}';
  }

  Future<void> _complete(
    String id,
    Map<String, dynamic> data, {
    required bool reject,
  }) async {
    final account = data['account'] as Map<String, dynamic>?;
    final label = reject ? '반려' : '환불 완료';
    // 반려 사유는 **필수**다 — 참가자는 이 문구만 보고 무엇을 고쳐 다시
    // 내야 할지 판단한다. 서버도 빈 사유를 거절한다.
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('$label 처리'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ⚠ 환불금은 원래 **호스트가** 자기 계좌에서 보낸다(참가비를
                //    호스트가 직접 받았으므로 — functions/payoutAccounts.js).
                //    관리자 처리는 장기 미처리·연락두절 같은 **개입**이므로,
                //    누르기 전에 실제 송금 주체를 분명히 확인시킨다.
                Text(
                  reject
                      ? '이 환불 요청을 반려할까요?\n'
                            '신청자에게 사유가 그대로 전달되고, 계좌를 고쳐 다시 낼 수 있습니다.'
                      : '관리자 개입으로 완료 처리합니다.\n'
                            '환불금은 호스트가 보내는 것이 원칙입니다 — '
                            '실제 송금이 끝났는지 확인한 뒤에만 누르세요.\n'
                            '완료 처리하면 되돌릴 수 없습니다.',
                  style: const TextStyle(height: 1.5),
                ),
                const SizedBox(height: 12),
                Text(
                  '${_won(data['refundAmount'])}  ·  '
                  '${account?['bankName'] ?? '-'} '
                  '${account?['accountNumber'] ?? '-'} '
                  '(${account?['accountHolder'] ?? '-'})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (reject) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: reasonCtrl,
                    autofocus: true,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: '반려 사유 (필수)',
                      hintText: '예: 예금주가 신청자 본인과 달라요',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: (reject && reasonCtrl.text.trim().isEmpty)
                  ? null
                  : () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: reject ? Colors.grey : AdminTheme.accent,
                foregroundColor: Colors.white,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (ok != true) return;

    setState(() => _busy.add(id));
    try {
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('completeRefundRequest')
          .call({'requestId': id, 'reject': reject, 'memo': reason});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$label 처리했습니다. (${_mask(account?['accountNumber'] as String?)})',
          ),
        ),
      );
      setState(() {}); // 목록 갱신 — 처리된 건은 requested 필터에서 빠진다.
    } catch (e) {
      if (!mounted) return;
      // 오류 문구에도 계좌 원문을 넣지 않는다.
      final msg = e is FirebaseFunctionsException ? (e.message ?? '$e') : '$e';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('처리 실패: $msg')));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '환불 요청',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 12),
            const Text(
              '무통장입금 취소 건 — 송금 주체는 호스트, 여기서는 감시·개입만 (처리 대기)',
              style: TextStyle(fontSize: 12.5, color: AdminTheme.textSecondary),
            ),
            const Spacer(),
            IconButton(
              onPressed: () => setState(() {}),
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: '새로고침',
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _query.snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('목록을 불러오지 못했어요: ${snap.error}'));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return const Center(
                  child: Text(
                    '처리할 환불 요청이 없습니다.',
                    style: TextStyle(color: AdminTheme.textSecondary),
                  ),
                );
              }
              // 요청 시각 오름차순(오래된 것 먼저) — 색인 없이 클라이언트 정렬.
              final sorted = docs.toList()
                ..sort((a, b) {
                  final at = a.data()['createdAt'] as Timestamp?;
                  final bt = b.data()['createdAt'] as Timestamp?;
                  if (at == null || bt == null) return 0;
                  return at.compareTo(bt);
                });
              return ListView.separated(
                itemCount: sorted.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _card(sorted[i]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _card(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final account = d['account'] as Map<String, dynamic>?;
    final busy = _busy.contains(doc.id);
    final number = (account?['accountNumber'] as String?) ?? '-';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AdminTheme.cardBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _won(d['refundAmount']),
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: AdminTheme.accent,
                ),
              ),
              const SizedBox(width: 14),
              Text(
                '요청 ${_fmtDate(d['createdAt'])}',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AdminTheme.textSecondary,
                ),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => _complete(doc.id, d, reject: true),
                child: const Text('반려'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: busy
                    ? null
                    : () => _complete(doc.id, d, reject: false),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminTheme.accent,
                  foregroundColor: Colors.white,
                ),
                child: Text(busy ? '처리 중…' : '환불 완료 처리'),
              ),
            ],
          ),
          const Divider(height: 24),
          _row('신청자 uid', d['requesterId'] as String? ?? '-'),
          _row(
            '대상',
            '${d['domain'] ?? '-'} · ${d['title'] ?? d['refId'] ?? '-'}',
          ),
          _row('원 신청 경로', d['applicationPath'] as String? ?? '-'),
          _row('환불 사유', d['reason'] as String? ?? '참가자 취소(환불 규정 적용)'),
          const SizedBox(height: 6),
          // 송금에 필요한 정보 — 복사 가능하게 둔다.
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  '${account?['bankName'] ?? '-'}  $number  '
                  '(${account?['accountHolder'] ?? '-'})',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: number));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('환불받을 계좌번호를 복사했습니다.')),
                  );
                },
                icon: const Icon(Icons.copy, size: 15),
                // 세 계좌(입금받을·정산·환불받을)가 뒤섞이지 않게 용도를 적는다.
                label: const Text('환불 계좌 복사'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              color: AdminTheme.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(value, style: const TextStyle(fontSize: 13)),
        ),
      ],
    ),
  );
}

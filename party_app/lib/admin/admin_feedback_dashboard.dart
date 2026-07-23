import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:party_app/models/feedback_request.dart';
import 'package:party_app/admin/csv_export/csv_export.dart';

/// PartyChu 관리자 웹 — 의견함 대시보드.
/// 파티/사용자 신고, 환불/결제 분쟁 등과는 무관한 feedbackRequests 전용 화면.
class AdminFeedbackDashboard extends StatefulWidget {
  final VoidCallback onSignOut;
  const AdminFeedbackDashboard({super.key, required this.onSignOut});

  @override
  State<AdminFeedbackDashboard> createState() => _AdminFeedbackDashboardState();
}

class _AdminFeedbackDashboardState extends State<AdminFeedbackDashboard> {
  String _typeFilter = 'all';
  String _statusFilter = 'all';
  String _search = '';
  bool _newestFirst = true;
  FeedbackRequest? _selected;

  List<FeedbackRequest> _applyFilters(List<FeedbackRequest> items) {
    var result = items.where((f) {
      if (_typeFilter != 'all' && f.type != _typeFilter) return false;
      if (_statusFilter != 'all' && f.status != _statusFilter) return false;
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        if (!f.title.toLowerCase().contains(q) && !f.content.toLowerCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
    result.sort((a, b) {
      final at = a.createdAt ?? DateTime(1970);
      final bt = b.createdAt ?? DateTime(1970);
      return _newestFirst ? bt.compareTo(at) : at.compareTo(bt);
    });
    return result;
  }

  void _downloadCsv(List<FeedbackRequest> items) {
    final rows = <List<String>>[
      ['유형', '제목', '상태', '작성자UID', '접수일', '내용', '사용자답변', '관리자메모'],
      ...items.map((f) => [
            FeedbackType.label(f.type),
            f.title,
            FeedbackStatus.label(f.status),
            f.userId,
            f.createdAt?.toIso8601String() ?? '',
            f.content,
            f.userReply,
            f.adminMemo,
          ]),
    ];
    final csv = rows.map((r) => r.map(_csvEscape).join(',')).join('\r\n');
    downloadCsv('partychu_feedback_${DateTime.now().millisecondsSinceEpoch}.csv', csv);
  }

  String _csvEscape(String v) {
    final needsQuote = v.contains(',') || v.contains('"') || v.contains('\n');
    final escaped = v.replaceAll('"', '""');
    return needsQuote ? '"$escaped"' : escaped;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FA),
      appBar: AppBar(
        title: const Text('PartyChu 관리자 · 의견 보내기',
            style: TextStyle(fontFamily: 'SeoulHangang', fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '로그아웃',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              widget.onSignOut();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('feedbackRequests').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFFFF6FA0)));
          }
          if (snapshot.hasError) {
            return Center(child: Text('오류: ${snapshot.error}'));
          }
          final all = (snapshot.data?.docs ?? []).map(FeedbackRequest.fromDoc).toList();
          final newCount = all.where((f) => f.status == FeedbackStatus.received).length;
          final filtered = _applyFilters(all);

          // 선택된 항목이 최신 스냅샷에 반영되도록 갱신
          if (_selected != null) {
            final updated = all.where((f) => f.id == _selected!.id);
            _selected = updated.isNotEmpty ? updated.first : null;
          }

          return LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 980;
            final listPane = _buildListPane(filtered, newCount, wide);
            if (!wide) return listPane;
            return Row(
              children: [
                SizedBox(width: 460, child: listPane),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _selected == null
                      ? const Center(
                          child: Text('왼쪽에서 의견을 선택하세요',
                              style: TextStyle(color: Colors.black38)))
                      : _DetailPanel(
                          key: ValueKey(_selected!.id),
                          item: _selected!,
                        ),
                ),
              ],
            );
          });
        },
      ),
    );
  }

  Widget _buildListPane(List<FeedbackRequest> filtered, int newCount, bool wide) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                if (newCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6FA0),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('신규 의견 $newCount건',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  )
                else
                  const Text('신규 의견 없음', style: TextStyle(color: Colors.black38, fontSize: 12)),
                const Spacer(),
                Text('총 ${filtered.length}건', style: const TextStyle(color: Colors.black45, fontSize: 12)),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: filtered.isEmpty ? null : () => _downloadCsv(filtered),
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('CSV 다운로드'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF6FA0),
                    side: const BorderSide(color: Color(0xFFFF6FA0)),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  hintText: '제목·내용 검색',
                  prefixIcon: Icon(Icons.search, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _search = v.trim()),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _dropdown('유형', _typeFilter, {
                  'all': '전체',
                  for (final t in FeedbackType.all) t: FeedbackType.label(t),
                }, (v) => setState(() => _typeFilter = v)),
                _dropdown('상태', _statusFilter, {
                  'all': '전체',
                  for (final s in FeedbackStatus.all) s: FeedbackStatus.label(s),
                }, (v) => setState(() => _statusFilter = v)),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _newestFirst = !_newestFirst),
                  icon: Icon(_newestFirst ? Icons.arrow_downward : Icons.arrow_upward, size: 16),
                  label: Text(_newestFirst ? '최신순' : '오래된순'),
                ),
              ]),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('조건에 맞는 의견이 없습니다.', style: TextStyle(color: Colors.black38)))
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final item = filtered[i];
                    final isSelected = _selected?.id == item.id;
                    return _FeedbackRow(
                      item: item,
                      selected: isSelected,
                      onTap: () {
                        if (wide) {
                          setState(() => _selected = item);
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => Scaffold(
                              appBar: AppBar(
                                title: const Text('의견 상세',
                                    style: TextStyle(fontFamily: 'SeoulHangang', fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])),
                              ),
                              body: _DetailPanel(item: item),
                            )),
                          );
                        }
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _dropdown(String label, String value, Map<String, String> options, ValueChanged<String> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE0E0E0)), borderRadius: BorderRadius.circular(8)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          items: options.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text('$label: ${e.value}')))
              .toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      ),
    );
  }
}

class _FeedbackRow extends StatelessWidget {
  final FeedbackRequest item;
  final bool selected;
  final VoidCallback onTap;
  const _FeedbackRow({required this.item, required this.selected, required this.onTap});

  Color _statusColor(String status) => switch (status) {
        FeedbackStatus.received => const Color(0xFF757575),
        FeedbackStatus.reviewing => const Color(0xFF1A73E8),
        FeedbackStatus.planned => const Color(0xFF7C5CBF),
        FeedbackStatus.answered => const Color(0xFF2E7D32),
        FeedbackStatus.hold => const Color(0xFFE06B00),
        _ => Colors.black45,
      };

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(item.status);
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? const Color(0xFFFFF0F5) : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFFFF0F5), borderRadius: BorderRadius.circular(20)),
                child: Text(FeedbackType.label(item.type),
                    style: const TextStyle(fontSize: 10, color: Color(0xFFFF6FA0), fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Text(FeedbackStatus.label(item.status),
                    style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
              ),
              const Spacer(),
              Text(
                item.createdAt == null
                    ? ''
                    : '${item.createdAt!.year}.${item.createdAt!.month.toString().padLeft(2, '0')}.${item.createdAt!.day.toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 11, color: Colors.black38),
              ),
            ]),
            const SizedBox(height: 6),
            Text(item.title,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _DetailPanel extends StatefulWidget {
  final FeedbackRequest item;
  const _DetailPanel({super.key, required this.item});

  @override
  State<_DetailPanel> createState() => _DetailPanelState();
}

class _DetailPanelState extends State<_DetailPanel> {
  late String _status;
  late final TextEditingController _replyCtrl;
  late final TextEditingController _memoCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _status = widget.item.status;
    _replyCtrl = TextEditingController(text: widget.item.userReply);
    _memoCtrl = TextEditingController(text: widget.item.adminMemo);
  }

  @override
  void didUpdateWidget(covariant _DetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _status = widget.item.status;
      _replyCtrl.text = widget.item.userReply;
      _memoCtrl.text = widget.item.adminMemo;
    }
  }

  @override
  void dispose() {
    _replyCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('feedbackRequests').doc(widget.item.id).update({
        'status': _status,
        'userReply': _replyCtrl.text.trim(),
        'adminMemo': _memoCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('저장되었습니다.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('저장 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('접수일: ${item.createdAt ?? ''}', style: const TextStyle(fontSize: 12, color: Colors.black45)),
            const SizedBox(height: 16),
            _sectionLabel('내용'),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE8EBF2))),
              child: Text(item.content, style: const TextStyle(fontSize: 14, height: 1.6)),
            ),
            if (item.imageUrls.isNotEmpty) ...[
              const SizedBox(height: 16),
              _sectionLabel('첨부 이미지'),
              Wrap(
                spacing: 10, runSpacing: 10,
                children: item.imageUrls.map((url) => ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(url, width: 140, height: 140, fit: BoxFit.cover),
                )).toList(),
              ),
            ],
            const SizedBox(height: 16),
            _sectionLabel('사용자 정보'),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE8EBF2))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('작성자 UID: ${item.userId}', style: const TextStyle(fontSize: 13)),
                  if (item.type == FeedbackType.bug) ...[
                    const SizedBox(height: 6),
                    Text('앱 버전: ${item.appVersion ?? '-'}', style: const TextStyle(fontSize: 13)),
                    Text('플랫폼: ${item.platform ?? '-'}', style: const TextStyle(fontSize: 13)),
                    Text('OS: ${item.osVersion ?? '-'}', style: const TextStyle(fontSize: 13)),
                    Text('기기: ${item.deviceInfo ?? '-'}', style: const TextStyle(fontSize: 13)),
                    if ((item.relatedScreen ?? '').isNotEmpty)
                      Text('오류 화면: ${item.relatedScreen}', style: const TextStyle(fontSize: 13)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            _sectionLabel('처리 상태'),
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _status,
                items: FeedbackStatus.all
                    .map((s) => DropdownMenuItem(value: s, child: Text(FeedbackStatus.label(s))))
                    .toList(),
                onChanged: (v) { if (v != null) setState(() => _status = v); },
              ),
            ),
            const SizedBox(height: 20),
            _sectionLabel('사용자에게 보여줄 답변'),
            TextField(
              controller: _replyCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: '사용자가 "내 의견 내역"에서 확인할 답변을 입력하세요.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            _sectionLabel('관리자 내부 메모 (사용자에게 노출되지 않음)'),
            TextField(
              controller: _memoCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: '내부 확인용 메모',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 46,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6FA0),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('저장'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black54)),
      );
}

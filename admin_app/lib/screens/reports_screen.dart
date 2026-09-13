import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/admin_firestore_service.dart';
import '../theme/admin_theme.dart';
import 'members_screen.dart' show OpenMember;

// 사용자·콘텐츠 신고를 보는 화면 — Firestore `reports`.
//
// 앱의 신고 진입(파티·플레이스·장소대여·파티샵·파티크루 상세와 채팅방의 ⋮
// 메뉴)이 만드는 문서가 그대로 여기로 온다. 새 컬렉션을 만들지 않았다.
//
// '의견·버그 신고'(feedbackRequests) 메뉴와는 **다른 데이터**다 — 그쪽은
// 사용자가 운영진에게 보내는 문의고, 이쪽은 다른 사용자/게시물에 대한 신고다.
//
// ── 여기서 할 수 있는 일은 상태 변경뿐이다 ────────────────────────────────
// 신고를 받았다고 글이 지워지거나 계정이 정지되는 경로는 만들지 않는다.
// 신고가 곧 처벌이 되면 신고 자체가 공격 수단이 되기 때문이다. 조치는
// 사람이 판단해 다른 화면(회원 관리 등)에서 따로 한다.

/// 앱 모델(party_app의 ReportReason)과 **같은 키**를 쓴다.
/// 여기서 새 키를 만들면 앱이 만든 문서와 어긋난다 — 추가만 한다.
const _reasonLabels = {
  'spam': '스팸 · 광고',
  'harassment': '욕설 · 괴롭힘',
  'sexual_content': '음란물 · 부적절',
  'fraud': '사기 · 금전 피해',
  'impersonation': '사칭 · 명의 도용',
  'illegal': '불법 정보 · 범죄',
  'other': '기타',
};

/// 앱 모델(party_app의 ReportTargetType)과 같은 키.
const _targetTypeLabels = {
  'user': '사용자',
  'party': '파티',
  'event': '플레이스',
  'place': '장소대여',
  'shop': '파티샵',
  'crew': '파티크루',
  'chatRoom': '채팅',
};

/// 처리상태 — 앱이 만드는 초기값은 'received' 하나뿐이고, 나머지는 관리자만
/// 쓴다(firestore.rules: update는 isAdmin()에 status/adminMemo/updatedAt/
/// resolvedAt만 허용).
const _statusLabels = {
  'received': '접수됨',
  'reviewing': '검토중',
  'resolved': '처리완료',
  'rejected': '기각',
};

const _statusColors = {
  'received': Color(0xFFE2568A),
  'reviewing': Color(0xFF9B5CFF),
  'resolved': Color(0xFF17924E),
  'rejected': Color(0xFF8C7A87),
};

class ReportsScreen extends StatefulWidget {
  final OpenMember onOpenMember;

  const ReportsScreen({super.key, required this.onOpenMember});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String? _statusFilter;
  String? _targetTypeFilter;
  final _searchCtrl = TextEditingController();
  String _search = '';

  /// 열어 둔 신고. null이면 목록.
  String? _openedId;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];

  /// 신고자·피신고자 표시용 users 문서 — 신고 문서에는 UID만 있다.
  Map<String, Map<String, dynamic>> _users = {};

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snap = await AdminFirestoreService.reportsQuery().limit(300).get();
      // 신고자와 피신고자 **양쪽**을 한 번에 붙인다 — 목록에서 두 사람을 모두
      // 이름으로 봐야 누가 누구를 신고했는지가 한눈에 들어온다.
      final uids = <String>{};
      for (final d in snap.docs) {
        final data = d.data();
        final reporter = data['reporterId'] as String? ?? '';
        final target = data['targetUserId'] as String? ?? '';
        if (reporter.isNotEmpty) uids.add(reporter);
        if (target.isNotEmpty) uids.add(target);
        // 사용자 신고는 targetId 자체가 상대 uid다(targetUserId가 비어 있는
        // 옛 문서도 여기서 함께 채워진다).
        if (data['targetType'] == 'user') {
          final t = data['targetId'] as String? ?? '';
          if (t.isNotEmpty) uids.add(t);
        }
      }
      final users = await AdminFirestoreService.fetchUsersForUids(
        uids.toList(),
      );
      if (!mounted) return;
      setState(() {
        _docs = snap.docs;
        _users = users;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// 피신고자 uid — 콘텐츠 신고는 targetUserId, 사용자 신고는 targetId.
  static String targetUidOf(Map<String, dynamic> d) {
    final explicit = d['targetUserId'] as String? ?? '';
    if (explicit.isNotEmpty) return explicit;
    if (d['targetType'] == 'user') return d['targetId'] as String? ?? '';
    return '';
  }

  /// 화면에 그릴 목록 — 필터·검색은 **여기서** 건다.
  ///
  /// 서버에 걸지 않는 이유는 feedbackRequestsQuery와 같다(그 조합에 필요한
  /// 복합 색인이 없다). 이미 받아 둔 목록에서 걸러 낼 뿐이라 필터를 바꿔도
  /// 서버를 다시 부르지 않는다.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _filtered => _docs
      .where(
        (d) => _statusFilter == null || d.data()['status'] == _statusFilter,
      )
      .where(
        (d) =>
            _targetTypeFilter == null ||
            d.data()['targetType'] == _targetTypeFilter,
      )
      .where((d) => _matchesSearch(d.data()))
      .toList();

  /// 신고자·피신고자의 닉네임·이름·이메일·UID 중 하나라도 걸리면 통과.
  bool _matchesSearch(Map<String, dynamic> d) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return true;
    final reporter = d['reporterId'] as String? ?? '';
    final target = targetUidOf(d);
    for (final uid in [reporter, target]) {
      if (uid.isEmpty) continue;
      if (uid.toLowerCase().contains(q)) return true;
      final u = _users[uid];
      if (u == null) continue;
      for (final f in ['nickname', 'name', 'email']) {
        final v = (u[f] as String? ?? '').toLowerCase();
        if (v.isNotEmpty && v.contains(q)) return true;
      }
    }
    // 신고 대상 제목으로도 찾을 수 있게 한다(같은 글에 여러 신고가 붙는다).
    final title = (d['targetTitle'] as String? ?? '').toLowerCase();
    return title.isNotEmpty && title.contains(q);
  }

  /// 닉네임 — 없으면 '(알 수 없음)'. **UID를 닉네임 자리에 넣지 않는다**
  /// (회원 목록·의견 화면과 같은 원칙).
  String _nicknameOf(String uid) {
    if (uid.isEmpty) return '-';
    final nickname = _users[uid]?['nickname'] as String?;
    if (nickname != null && nickname.isNotEmpty) return nickname;
    return _users.containsKey(uid) ? '(닉네임 없음)' : '(알 수 없음)';
  }

  String _emailOf(String uid) {
    if (uid.isEmpty) return '-';
    final email = _users[uid]?['email'] as String?;
    return (email == null || email.isEmpty) ? '-' : email;
  }

  @override
  Widget build(BuildContext context) {
    final opened = _openedId;
    if (opened != null) {
      final matches = _docs.where((d) => d.id == opened);
      if (matches.isNotEmpty) {
        final doc = matches.first;
        final d = doc.data();
        return _ReportDetail(
          doc: doc,
          reporterNickname: _nicknameOf(d['reporterId'] as String? ?? ''),
          reporterEmail: _emailOf(d['reporterId'] as String? ?? ''),
          targetUid: targetUidOf(d),
          targetNickname: _nicknameOf(targetUidOf(d)),
          targetEmail: _emailOf(targetUidOf(d)),
          onBack: () => setState(() => _openedId = null),
          onOpenMember: widget.onOpenMember,
          onSaved: () async {
            await _load();
            if (mounted) setState(() => _openedId = null);
          },
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '신고 관리',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 12),
            if (!_loading)
              Text(
                '${_filtered.length}건',
                style: const TextStyle(
                  fontSize: 13,
                  color: AdminTheme.textSecondary,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          '앱에서 접수된 사용자·게시물 신고입니다. 상태 변경만 가능하며, 신고 처리로 글이 삭제되거나 계정이 정지되지 않습니다.',
          style: TextStyle(fontSize: 12, color: AdminTheme.textSecondary),
        ),
        const SizedBox(height: 16),
        _toolbar(),
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AdminTheme.cardBorder),
            ),
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AdminTheme.accent),
                  )
                : _error != null
                ? Center(child: Text('불러오지 못했습니다: $_error'))
                : _filtered.isEmpty
                ? const Center(
                    child: Text(
                      '접수된 신고가 없습니다.',
                      style: TextStyle(color: AdminTheme.textSecondary),
                    ),
                  )
                : _table(),
          ),
        ),
      ],
    );
  }

  Widget _toolbar() => Wrap(
    spacing: 10,
    runSpacing: 10,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      SizedBox(
        width: 260,
        child: TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _search = v),
          decoration: InputDecoration(
            isDense: true,
            hintText: '닉네임 · 이름 · 이메일 · UID · 대상 제목',
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: _search.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _search = '');
                    },
                  ),
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      DropdownButton<String?>(
        value: _statusFilter,
        hint: const Text('처리상태'),
        items: [
          const DropdownMenuItem(value: null, child: Text('상태 전체')),
          for (final e in _statusLabels.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) => setState(() => _statusFilter = v),
      ),
      DropdownButton<String?>(
        value: _targetTypeFilter,
        hint: const Text('대상 유형'),
        items: [
          const DropdownMenuItem(value: null, child: Text('대상 전체')),
          for (final e in _targetTypeLabels.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) => setState(() => _targetTypeFilter = v),
      ),
      if (_statusFilter != null ||
          _targetTypeFilter != null ||
          _search.isNotEmpty)
        TextButton(
          onPressed: () {
            _searchCtrl.clear();
            setState(() {
              _statusFilter = null;
              _targetTypeFilter = null;
              _search = '';
            });
          },
          child: const Text('필터 초기화'),
        ),
      TextButton.icon(
        onPressed: _load,
        icon: const Icon(Icons.refresh, size: 18),
        label: const Text('새로고침'),
      ),
    ],
  );

  Widget _table() => _ReportsScrollableTable(
    child: DataTable(
      dataRowMinHeight: 46,
      dataRowMaxHeight: 62,
      columns: const [
        DataColumn(label: Text('신고일')),
        DataColumn(label: Text('대상 유형')),
        DataColumn(label: Text('신고자')),
        DataColumn(label: Text('신고자 UID')),
        DataColumn(label: Text('피신고자')),
        DataColumn(label: Text('피신고자 UID')),
        DataColumn(label: Text('대상 제목')),
        DataColumn(label: Text('사유')),
        DataColumn(label: Text('상세 내용')),
        DataColumn(label: Text('처리상태')),
      ],
      rows: [for (final doc in _filtered) _row(doc)],
    ),
  );

  DataRow _row(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final reporter = d['reporterId'] as String? ?? '';
    final target = targetUidOf(d);
    final createdAt = (d['createdAt'] as Timestamp?)?.toDate();
    final detail = (d['detail'] as String? ?? '').replaceAll('\n', ' ');
    final title = d['targetTitle'] as String? ?? '';

    return DataRow(
      onSelectChanged: (_) => setState(() => _openedId = doc.id),
      cells: [
        DataCell(
          Text(
            createdAt == null
                ? '-'
                : DateFormat('yyyy.MM.dd HH:mm').format(createdAt),
          ),
        ),
        DataCell(_TargetTypeBadge(type: d['targetType'] as String?)),
        DataCell(Text(_nicknameOf(reporter))),
        DataCell(
          SelectableText(
            reporter.isEmpty ? '-' : reporter,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        DataCell(Text(_nicknameOf(target))),
        DataCell(
          SelectableText(
            target.isEmpty ? '-' : target,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        DataCell(
          SizedBox(
            width: 200,
            child: Text(
              title.isEmpty ? '-' : title,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(
          Text(
            _reasonLabels[d['reason']] ?? (d['reason'] as String? ?? '-'),
            style: const TextStyle(fontSize: 12.5),
          ),
        ),
        DataCell(
          SizedBox(
            width: 260,
            child: Text(
              detail.isEmpty ? '-' : detail,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AdminTheme.textSecondary),
            ),
          ),
        ),
        DataCell(_StatusBadge(status: d['status'] as String?)),
      ],
    );
  }
}

/// 신고 전문 + 처리상태 변경.
class _ReportDetail extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String reporterNickname;
  final String reporterEmail;
  final String targetUid;
  final String targetNickname;
  final String targetEmail;
  final VoidCallback onBack;
  final OpenMember onOpenMember;
  final Future<void> Function() onSaved;

  const _ReportDetail({
    required this.doc,
    required this.reporterNickname,
    required this.reporterEmail,
    required this.targetUid,
    required this.targetNickname,
    required this.targetEmail,
    required this.onBack,
    required this.onOpenMember,
    required this.onSaved,
  });

  @override
  State<_ReportDetail> createState() => _ReportDetailState();
}

class _ReportDetailState extends State<_ReportDetail> {
  late String _status = widget.doc.data()['status'] as String? ?? 'received';
  late final _memoCtrl = TextEditingController(
    text: widget.doc.data()['adminMemo'] as String? ?? '',
  );
  bool _saving = false;

  @override
  void dispose() {
    _memoCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await AdminFirestoreService.updateReport(
        widget.doc.id,
        status: _status,
        adminMemo: _memoCtrl.text.trim(),
      );
      await widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('저장하지 못했습니다: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.doc.data();
    final reporter = d['reporterId'] as String? ?? '';
    final createdAt = (d['createdAt'] as Timestamp?)?.toDate();
    final updatedAt = (d['updatedAt'] as Timestamp?)?.toDate();
    final resolvedAt = (d['resolvedAt'] as Timestamp?)?.toDate();
    final detail = d['detail'] as String? ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back),
              tooltip: '목록으로',
            ),
            const Text(
              '신고 상세',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 12),
            _StatusBadge(status: d['status'] as String?),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AdminTheme.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _kv('신고 일시', _fmt(createdAt)),
                  _kv(
                    '대상 유형',
                    _targetTypeLabels[d['targetType']] ??
                        (d['targetType'] as String? ?? '-'),
                  ),
                  _kv('대상 제목', d['targetTitle'] as String? ?? '-'),
                  _kv('대상 문서 ID', d['targetId'] as String? ?? '-', mono: true),
                  const Divider(height: 28),

                  _person(
                    '신고자',
                    reporter,
                    widget.reporterNickname,
                    widget.reporterEmail,
                  ),
                  const SizedBox(height: 10),
                  _person(
                    '피신고자',
                    widget.targetUid,
                    widget.targetNickname,
                    widget.targetEmail,
                  ),
                  const Divider(height: 28),

                  _kv(
                    '신고 사유',
                    _reasonLabels[d['reason']] ??
                        (d['reason'] as String? ?? '-'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '상세 내용',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AdminTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9F9FB),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AdminTheme.cardBorder),
                    ),
                    child: SelectableText(
                      detail.isEmpty ? '(상세 내용 없음)' : detail,
                      style: const TextStyle(fontSize: 13.5, height: 1.6),
                    ),
                  ),
                  const Divider(height: 28),

                  const Text(
                    '처리',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '상태 변경은 이 신고 문서에만 적용됩니다 — 대상 글이나 피신고자 계정은 바뀌지 않습니다.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AdminTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final e in _statusLabels.entries)
                        ChoiceChip(
                          label: Text(e.value),
                          selected: _status == e.key,
                          onSelected: _saving
                              ? null
                              : (_) => setState(() => _status = e.key),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _memoCtrl,
                    enabled: !_saving,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: '운영 메모 (관리자만 봅니다)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('저장'),
                      ),
                      const SizedBox(width: 16),
                      if (updatedAt != null)
                        Text(
                          '최근 수정 ${_fmt(updatedAt)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AdminTheme.textSecondary,
                          ),
                        ),
                      if (resolvedAt != null) ...[
                        const SizedBox(width: 12),
                        Text(
                          '처리 ${_fmt(resolvedAt)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AdminTheme.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _fmt(DateTime? dt) =>
      dt == null ? '-' : DateFormat('yyyy.MM.dd HH:mm').format(dt);

  Widget _kv(String k, String v, {bool mono = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            k,
            style: const TextStyle(
              fontSize: 12.5,
              color: AdminTheme.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            v,
            style: TextStyle(
              fontSize: 13.5,
              fontFamily: mono ? 'monospace' : null,
            ),
          ),
        ),
      ],
    ),
  );

  /// 신고자·피신고자 한 줄 — 회원 상세로 바로 넘어갈 수 있게 한다.
  Widget _person(String role, String uid, String nickname, String email) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF9F9FB),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AdminTheme.cardBorder),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 70,
              child: Text(
                role,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: AdminTheme.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nickname, style: const TextStyle(fontSize: 13.5)),
                  const SizedBox(height: 2),
                  SelectableText(
                    '$email  ·  ${uid.isEmpty ? '-' : uid}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AdminTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (uid.isNotEmpty)
              TextButton(
                onPressed: () => widget.onOpenMember(uid),
                child: const Text('회원 상세'),
              ),
          ],
        ),
      );
}

class _TargetTypeBadge extends StatelessWidget {
  final String? type;
  const _TargetTypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    // 사용자 신고는 게시물 신고와 성격이 달라 색으로 구분한다.
    final isUser = type == 'user';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isUser ? const Color(0xFFFFE9EF) : const Color(0xFFF0EEFB),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _targetTypeLabels[type] ?? (type ?? '-'),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.bold,
          color: isUser ? const Color(0xFFE2568A) : const Color(0xFF6B5AC7),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String? status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _statusColors[status] ?? AdminTheme.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _statusLabels[status] ?? (status ?? '-'),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

/// 회원 관리·의견 화면과 같은 스크롤 처리(각 화면이 private 위젯을 공유하지
/// 못해 같은 모양을 한 벌 더 둔다 — feedback_requests_screen.dart와 동일).
class _ReportsScrollableTable extends StatefulWidget {
  final Widget child;
  const _ReportsScrollableTable({required this.child});

  @override
  State<_ReportsScrollableTable> createState() =>
      _ReportsScrollableTableState();
}

class _ReportsScrollableTableState extends State<_ReportsScrollableTable> {
  final _horizontal = ScrollController();
  final _vertical = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: _vertical,
    thumbVisibility: true,
    child: Scrollbar(
      controller: _horizontal,
      thumbVisibility: true,
      notificationPredicate: (n) => n.depth == 1,
      child: SingleChildScrollView(
        controller: _vertical,
        child: SingleChildScrollView(
          controller: _horizontal,
          scrollDirection: Axis.horizontal,
          child: widget.child,
        ),
      ),
    ),
  );
}

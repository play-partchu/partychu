import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/admin_firestore_service.dart';
import '../theme/admin_theme.dart';
import 'members_screen.dart' show OpenMember;

// 사용자 차단 내역 — Firestore `userBlocks`.
//
// 앱에서 사용자가 직접 건 차단이 그대로 여기로 온다. 새 컬렉션을 만들지
// 않았고, 문서 id는 "{차단한사람}_{차단당한사람}"이다.
//
// ── 이 화면은 전체 차단 관계를 볼 수 있는 유일한 자리다 ────────────────────
// 규칙의 list 조건이 `resource.data.blockerId == uid() || isAdmin()`이라,
// **일반 사용자는 자기가 건 차단만** 조회할 수 있다. "누가 나를 차단했는지"를
// 알아낼 수 있는 쿼리는 앱에도 서버에도 없고, 이 화면이 그 예외인 관리자
// 경로다(firestore.rules의 userBlocks 주석 참고).
//
// ── 조회만 한다 ──────────────────────────────────────────────────────────
// 관리자가 남의 차단을 풀거나 새로 거는 버튼은 두지 않는다. 차단은 그 사람이
// 자기 화면을 위해 건 것이고, 운영이 대신 판단할 일이 아니다. 차단 데이터
// 삭제도 이번 범위가 아니다.

class BlockedRelationsScreen extends StatefulWidget {
  final OpenMember onOpenMember;

  const BlockedRelationsScreen({super.key, required this.onOpenMember});

  @override
  State<BlockedRelationsScreen> createState() => _BlockedRelationsScreenState();
}

class _BlockedRelationsScreenState extends State<BlockedRelationsScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];

  /// 차단한 사람·차단당한 사람 표시용 users 문서 — 문서에는 UID만 있다.
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
      final snap = await AdminFirestoreService.userBlocksQuery()
          .limit(300)
          .get();
      final uids = <String>{};
      for (final d in snap.docs) {
        final data = d.data();
        final a = data['blockerId'] as String? ?? '';
        final b = data['blockedId'] as String? ?? '';
        if (a.isNotEmpty) uids.add(a);
        if (b.isNotEmpty) uids.add(b);
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

  /// 검색은 화면에서 건다 — 차단한 쪽·당한 쪽 어느 이름으로도 찾을 수 있어야
  /// "이 사람이 누구를 차단했나"와 "이 사람은 누구에게 차단당했나"를 같은
  /// 검색창으로 볼 수 있다.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _filtered =>
      _docs.where((d) => _matchesSearch(d.data())).toList();

  bool _matchesSearch(Map<String, dynamic> d) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return true;
    for (final uid in [
      d['blockerId'] as String? ?? '',
      d['blockedId'] as String? ?? '',
    ]) {
      if (uid.isEmpty) continue;
      if (uid.toLowerCase().contains(q)) return true;
      final u = _users[uid];
      if (u == null) continue;
      for (final f in ['nickname', 'name', 'email']) {
        final v = (u[f] as String? ?? '').toLowerCase();
        if (v.isNotEmpty && v.contains(q)) return true;
      }
    }
    return false;
  }

  /// 닉네임 — 없으면 '(알 수 없음)'. **UID를 닉네임 자리에 넣지 않는다.**
  ///
  /// 차단 문서에는 차단 당시의 표시용 이름(`blockedName`)도 함께 저장돼 있어
  /// 계정이 지워졌을 때의 마지막 단서로 쓴다.
  String _nicknameOf(String uid, {String? fallback}) {
    if (uid.isEmpty) return '-';
    final nickname = _users[uid]?['nickname'] as String?;
    if (nickname != null && nickname.isNotEmpty) return nickname;
    if (_users.containsKey(uid)) return '(닉네임 없음)';
    final saved = (fallback ?? '').trim();
    return saved.isEmpty ? '(알 수 없음)' : '$saved (차단 당시 이름)';
  }

  String _emailOf(String uid) {
    if (uid.isEmpty) return '-';
    final email = _users[uid]?['email'] as String?;
    return (email == null || email.isEmpty) ? '-' : email;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '차단 내역',
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
          '사용자가 직접 건 차단입니다. 조회 전용이며, 상대방에게는 차단 사실이 알려지지 않습니다.',
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
                      '차단 내역이 없습니다.',
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
            hintText: '닉네임 · 이름 · 이메일 · UID',
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
      if (_search.isNotEmpty)
        TextButton(
          onPressed: () {
            _searchCtrl.clear();
            setState(() => _search = '');
          },
          child: const Text('검색 초기화'),
        ),
      TextButton.icon(
        onPressed: _load,
        icon: const Icon(Icons.refresh, size: 18),
        label: const Text('새로고침'),
      ),
    ],
  );

  Widget _table() => _BlocksScrollableTable(
    child: DataTable(
      dataRowMinHeight: 46,
      dataRowMaxHeight: 62,
      columns: const [
        DataColumn(label: Text('차단 일시')),
        DataColumn(label: Text('차단한 사람')),
        DataColumn(label: Text('이메일')),
        DataColumn(label: Text('UID')),
        DataColumn(label: Text('차단당한 사람')),
        DataColumn(label: Text('이메일')),
        DataColumn(label: Text('UID')),
        DataColumn(label: Text('회원 상세')),
      ],
      rows: [for (final doc in _filtered) _row(doc)],
    ),
  );

  DataRow _row(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final blocker = d['blockerId'] as String? ?? '';
    final blocked = d['blockedId'] as String? ?? '';
    final createdAt = (d['createdAt'] as Timestamp?)?.toDate();

    return DataRow(
      cells: [
        DataCell(
          Text(
            createdAt == null
                ? '-'
                : DateFormat('yyyy.MM.dd HH:mm').format(createdAt),
          ),
        ),
        DataCell(Text(_nicknameOf(blocker))),
        DataCell(
          SelectableText(
            _emailOf(blocker),
            style: const TextStyle(fontSize: 12.5),
          ),
        ),
        DataCell(
          SelectableText(
            blocker.isEmpty ? '-' : blocker,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        DataCell(
          Text(_nicknameOf(blocked, fallback: d['blockedName'] as String?)),
        ),
        DataCell(
          SelectableText(
            _emailOf(blocked),
            style: const TextStyle(fontSize: 12.5),
          ),
        ),
        DataCell(
          SelectableText(
            blocked.isEmpty ? '-' : blocked,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (blocker.isNotEmpty)
                TextButton(
                  onPressed: () => widget.onOpenMember(blocker),
                  child: const Text('차단한 사람', style: TextStyle(fontSize: 12)),
                ),
              if (blocked.isNotEmpty)
                TextButton(
                  onPressed: () => widget.onOpenMember(blocked),
                  child: const Text('차단당한 사람', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 회원 관리·의견 화면과 같은 스크롤 처리(각 화면이 private 위젯을 공유하지
/// 못해 같은 모양을 한 벌 더 둔다 — feedback_requests_screen.dart와 동일).
class _BlocksScrollableTable extends StatefulWidget {
  final Widget child;
  const _BlocksScrollableTable({required this.child});

  @override
  State<_BlocksScrollableTable> createState() => _BlocksScrollableTableState();
}

class _BlocksScrollableTableState extends State<_BlocksScrollableTable> {
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

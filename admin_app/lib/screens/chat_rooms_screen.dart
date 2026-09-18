import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/admin_chat_service.dart';
import '../theme/admin_theme.dart';
import '../utils/responsive.dart';

/// 채팅 관리 — 전체 채팅방 목록(최근 메시지순).
///
/// ⚠️ Firestore를 직접 읽지 않는다. chatRooms는 개인 간 대화라 규칙에 관리자
/// 예외가 없고(firestore.rules 참고), 열람은 Admin SDK onCall
/// (adminListChatRooms/adminGetChatRoom)만 거친다 — 그래야 열람 기록이 남는다.
class ChatRoomsScreen extends StatefulWidget {
  const ChatRoomsScreen({super.key, required this.onOpenRoom});

  final void Function(String roomId) onOpenRoom;

  @override
  State<ChatRoomsScreen> createState() => _ChatRoomsScreenState();
}

class _ChatRoomsScreenState extends State<ChatRoomsScreen> {
  final _searchCtrl = TextEditingController();

  ChatKind _kind = ChatKind.all;
  ChatSearchField _searchField = ChatSearchField.uid;
  String _appliedSearch = '';
  ChatSearchField? _appliedField;

  final _rooms = <AdminChatRoom>[];

  /// _pageCursors[i] = i번째 페이지를 여는 데 쓴 커서(0페이지는 항상 null).
  /// 서버가 커서 기반이라 "이전" 버튼은 이 이력을 되짚는 것으로만 만들 수 있다.
  final _pageCursors = <String?>[null];
  String? _nextCursor;
  bool _truncated = false;
  bool _loading = false;
  String? _error;
  int _pageIndex = 0;

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

  Future<void> _load({String? cursorId}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await AdminChatService.listRooms(
        kind: _kind,
        searchField: _appliedSearch.isEmpty ? null : _appliedField,
        searchValue: _appliedSearch,
        cursorId: cursorId,
      );
      if (!mounted) return;
      setState(() {
        _rooms
          ..clear()
          ..addAll(page.rooms);
        _nextCursor = page.nextCursor;
        _truncated = page.truncated;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e is FirebaseFunctionsException ? (e.message ?? '$e') : '$e';
      setState(() {
        _loading = false;
        _error = msg;
      });
    }
  }

  /// 조건이 바뀌면 페이지 이력을 버리고 첫 페이지부터 다시 센다.
  void _restart() {
    _pageCursors
      ..clear()
      ..add(null);
    _pageIndex = 0;
    _load();
  }

  void _applySearch() {
    _appliedSearch = _searchCtrl.text.trim();
    _appliedField = _searchField;
    _restart();
  }

  void _resetAll() {
    _searchCtrl.clear();
    _appliedSearch = '';
    _appliedField = null;
    _kind = ChatKind.all;
    _restart();
  }

  static String _fmt(DateTime? v) =>
      v == null ? '-' : DateFormat('yyyy.MM.dd HH:mm').format(v);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '채팅 관리',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                '사용자 간 1:1 대화 — 읽기 전용. 상세를 열면 열람 기록이 남습니다.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AdminTheme.textSecondary,
                ),
              ),
            ),
            IconButton(
              onPressed: _loading ? null : () => _load(),
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: '새로고침',
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildToolbar(),
        const SizedBox(height: 8),
        // 패키지/이용권을 필터로 두지 않은 이유 — 없는 구분을 있는 척하지 않는다.
        const Text(
          '※ 플레이스 방문예약·장소대여·패키지·이용권 문의는 앱에서 대상 글마다 방 하나를 함께 쓰므로, '
          '방 문서만으로는 패키지/이용권 건인지 구분되지 않습니다. 원본 글 기준으로 '
          '플레이스(술집·바·카페)와 장소대여/숙박까지만 나눕니다.',
          style: TextStyle(fontSize: 11.5, color: AdminTheme.textSecondary),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AdminTheme.cardBorder),
              borderRadius: BorderRadius.circular(10),
            ),
            child: _buildBody(),
          ),
        ),
        _buildPagination(),
      ],
    );
  }

  Widget _buildToolbar() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DropdownButton<ChatSearchField>(
          value: _searchField,
          items: [
            for (final f in ChatSearchField.values)
              DropdownMenuItem(value: f, child: Text(f.label)),
          ],
          onChanged: (v) => setState(() => _searchField = v ?? _searchField),
        ),
        SizedBox(
          width: context.fluid(300),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: '${_searchField.label} 검색',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
            ),
            onSubmitted: (_) => _applySearch(),
          ),
        ),
        ElevatedButton(onPressed: _applySearch, child: const Text('검색')),
        const SizedBox(width: 8),
        DropdownButton<ChatKind>(
          value: _kind,
          items: [
            for (final k in ChatKind.values)
              DropdownMenuItem(value: k, child: Text(k.label)),
          ],
          onChanged: (v) {
            if (v == null) return;
            _kind = v;
            _restart();
          },
        ),
        if (_appliedSearch.isNotEmpty || _kind != ChatKind.all)
          TextButton.icon(
            onPressed: _resetAll,
            icon: const Icon(Icons.close, size: 16),
            label: const Text('초기화'),
          ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40, color: Colors.black26),
              const SizedBox(height: 10),
              Text(
                '채팅방 목록을 불러오지 못했습니다.\n$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AdminTheme.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => _load(),
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      );
    }
    if (_rooms.isEmpty) {
      return Center(
        child: Text(
          _appliedSearch.isEmpty ? '채팅방이 없습니다.' : '검색 결과가 없습니다.',
          style: const TextStyle(color: AdminTheme.textSecondary),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_truncated)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: AdminTheme.accentLight,
            child: const Text(
              '조회 범위 상한에 걸려 일부만 표시했습니다. 검색 조건을 좁히면 더 정확히 볼 수 있습니다.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        Expanded(child: _buildTable()),
      ],
    );
  }

  Widget _buildTable() {
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('채팅 유형')),
            DataColumn(label: Text('연결 대상')),
            DataColumn(label: Text('대상 ID')),
            DataColumn(label: Text('게스트')),
            DataColumn(label: Text('호스트')),
            DataColumn(label: Text('최근 메시지')),
            DataColumn(label: Text('최근 메시지 시각')),
            DataColumn(label: Text('생성일')),
            DataColumn(label: Text('메시지')),
            DataColumn(label: Text('채팅방 ID')),
            DataColumn(label: Text('')),
          ],
          rows: [
            for (final r in _rooms)
              DataRow(
                // 행 어디를 눌러도 상세로 들어간다(회원 목록과 같은 방식).
                //
                // 예전에는 맨 끝 '대화 보기' 버튼 하나만 눌렸다. 이 표는 컬럼이
                // 11개라 가로 스크롤을 끝까지 밀기 전에는 그 버튼이 화면 밖에
                // 있어서, 방 이름을 눌러본 사람에게는 "클릭이 아예 안 되는
                // 화면"으로 보였다.
                onSelectChanged: (_) => widget.onOpenRoom(r.roomId),
                cells: [
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _chip(r.kind.label),
                        if (!r.sourceExists) ...[
                          const SizedBox(width: 4),
                          const Tooltip(
                            message: '원본 글이 삭제된 채팅방입니다.',
                            child: Icon(
                              Icons.link_off,
                              size: 14,
                              color: Colors.black38,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 180,
                      child: Text(
                        (r.relatedTitle?.isNotEmpty ?? false)
                            ? r.relatedTitle!
                            : '-',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  DataCell(_mono(r.relatedId ?? '-')),
                  DataCell(_person(r.guestLabel, r.guestId, r.guest)),
                  DataCell(_person(r.hostLabel, r.hostId, r.host)),
                  DataCell(
                    SizedBox(
                      width: 220,
                      child: Text(
                        r.lastMessage.isEmpty ? '(대화 없음)' : r.lastMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: r.lastMessage.isEmpty
                              ? AdminTheme.textSecondary
                              : null,
                        ),
                      ),
                    ),
                  ),
                  DataCell(Text(_fmt(r.lastMessageAt))),
                  DataCell(Text(_fmt(r.createdAt))),
                  DataCell(Text(r.messageCount?.toString() ?? '-')),
                  DataCell(
                    Tooltip(
                      message: r.idScheme == 'deterministic'
                          ? '결정적 id — {게스트uid}_{종류}_{대상id}'
                          : '기존(임의 id) 채팅방 — 그대로 조회됩니다',
                      child: _mono(r.roomId),
                    ),
                  ),
                  DataCell(
                    TextButton(
                      onPressed: () => widget.onOpenRoom(r.roomId),
                      child: const Text('대화 보기'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: AdminTheme.accentLight,
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AdminTheme.accent,
      ),
    ),
  );

  /// ⚠️ 목록의 칸은 **절대 SelectableText를 쓰지 않는다.**
  ///
  /// SelectableText는 자기 영역의 탭을 드래그-선택 제스처로 먹어버려서, 그 칸
  /// 위에서는 DataRow.onSelectChanged가 아예 발화하지 않는다. 예전에는 대상 ID·
  /// 게스트·호스트·채팅방 ID 네 칸이 SelectableText라 행 가로폭의 절반 가까이가
  /// "눌러도 아무 일도 안 나는" 죽은 영역이었다 — 하필 관리자가 가장 많이 누르는
  /// uid/이메일 자리였다(회원 목록은 전부 Text라 이 문제가 없었다).
  ///
  /// 값 복사가 필요하면 상세 화면에서 한다 — 거기서는 행 클릭이 없어 SelectableText를
  /// 그대로 쓴다. 목록은 "훑고 들어가는" 화면, 상세는 "값을 가져가는" 화면이다.
  Widget _mono(String v) => SizedBox(
    width: 190,
    child: Text(
      v,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
    ),
  );

  /// 닉네임을 앞에, uid/이메일을 아래에 — uid만 덩그러니 두지 않는다.
  Widget _person(String label, String? uid, ChatUserBrief? brief) => SizedBox(
    width: 170,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (brief == null && (uid?.isNotEmpty ?? false))
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Tooltip(
                  message: '회원 문서를 찾을 수 없습니다(탈퇴 등).',
                  child: Icon(
                    Icons.person_off_outlined,
                    size: 13,
                    color: Colors.black38,
                  ),
                ),
              ),
            if (brief?.isTestAccount == true)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text(
                  'TEST',
                  style: TextStyle(fontSize: 9, color: Colors.black38),
                ),
              ),
          ],
        ),
        // 위 _mono 주석과 같은 이유로 Text다 — SelectableText면 이 칸에서
        // 행 클릭이 죽는다.
        Text(
          uid?.isNotEmpty == true ? uid! : '-',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 10.5,
            fontFamily: 'monospace',
            color: AdminTheme.textSecondary,
          ),
        ),
        if (brief?.email?.isNotEmpty ?? false)
          Text(
            brief!.email!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.5,
              color: AdminTheme.textSecondary,
            ),
          ),
      ],
    ),
  );

  Widget _buildPagination() {
    final canPrev = _pageIndex > 0 && !_loading;
    final canNext = _nextCursor != null && !_loading;
    if (!canPrev && !canNext) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton.icon(
            onPressed: canPrev
                ? () {
                    _pageIndex -= 1;
                    _load(cursorId: _pageCursors[_pageIndex]);
                  }
                : null,
            icon: const Icon(Icons.chevron_left, size: 18),
            label: const Text('이전'),
          ),
          Text(
            '${_pageIndex + 1} 페이지',
            style: const TextStyle(
              fontSize: 12.5,
              color: AdminTheme.textSecondary,
            ),
          ),
          TextButton.icon(
            onPressed: canNext
                ? () {
                    final cursor = _nextCursor;
                    _pageIndex += 1;
                    if (_pageCursors.length <= _pageIndex) {
                      _pageCursors.add(cursor);
                    } else {
                      _pageCursors[_pageIndex] = cursor;
                    }
                    _load(cursorId: cursor);
                  }
                : null,
            icon: const Icon(Icons.chevron_right, size: 18),
            label: const Text('다음'),
          ),
        ],
      ),
    );
  }
}

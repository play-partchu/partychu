import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/admin_chat_service.dart';
import '../theme/admin_theme.dart';
import '../utils/responsive.dart';

/// 채팅방 상세 — **관리자용 읽기 전용 대화 기록**.
///
/// 사용자 앱의 채팅 화면(chat_room_screen.dart)을 복사하지 않는다. 저 화면은
/// 말풍선·입력창·자동 안내 발송 같은 "대화에 참여하는" 장치가 목적이고,
/// 여기서 필요한 건 정반대다 — 누가 언제 무엇을 보냈는지 그대로 읽는 기록지.
/// 그래서 입력창도, 전송도, 어떤 쓰기 경로도 없다.
///
///   관리자 = 열람 가능 / 관리자 = 일반 채팅 참여자는 아님
///
/// 운영 메시지가 필요해지면 이 화면에 입력창을 붙이는 게 아니라 별도의 관리자
/// 시스템 메시지 기능으로 만들어야 한다(사용자 이름으로 대신 쓰는 일이 생기면
/// senderId를 uid()로 못 박아 둔 firestore.rules의 전제가 무너진다).
class ChatRoomDetailScreen extends StatefulWidget {
  const ChatRoomDetailScreen({
    super.key,
    required this.roomId,
    required this.onBack,
  });

  final String roomId;
  final VoidCallback onBack;

  @override
  State<ChatRoomDetailScreen> createState() => _ChatRoomDetailScreenState();
}

class _ChatRoomDetailScreenState extends State<ChatRoomDetailScreen> {
  AdminChatRoom? _room;
  final _messages = <AdminChatMessage>[];
  String? _nextCursor;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await AdminChatService.getRoom(widget.roomId);
      if (!mounted) return;
      setState(() {
        _room = detail.room;
        _messages
          ..clear()
          ..addAll(detail.messages);
        _hasMore = detail.hasMore;
        _nextCursor = detail.nextCursor;
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

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final detail = await AdminChatService.getRoom(
        widget.roomId,
        cursorId: cursor,
      );
      if (!mounted) return;
      setState(() {
        _messages.addAll(detail.messages);
        _hasMore = detail.hasMore;
        _nextCursor = detail.nextCursor;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      final msg = e is FirebaseFunctionsException ? (e.message ?? '$e') : '$e';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('이어 불러오지 못했습니다: $msg')));
    }
  }

  // 한국어 요일은 손으로 붙인다 — 이 앱은 intl 로케일 데이터를
  // (initializeDateFormatting) 초기화하지 않아서 DateFormat(..., 'ko')를 쓰면
  // 런타임에 터진다. 사용자 앱도 같은 이유로 요일 배열을 그대로 쓴다.
  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];
  static final _dateFmt = DateFormat('yyyy.MM.dd');
  static final _timeFmt = DateFormat('HH:mm');
  static final _fullFmt = DateFormat('yyyy.MM.dd HH:mm');

  static String _dayLabel(DateTime d) =>
      '${_dateFmt.format(d)} (${_weekdays[d.weekday - 1]})';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back, size: 20),
              tooltip: '목록으로',
            ),
            const SizedBox(width: 4),
            const Text(
              '채팅 상세',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF1F6),
                borderRadius: BorderRadius.circular(5),
              ),
              child: const Text(
                '읽기 전용 · 열람 기록 남음',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AdminTheme.textSecondary,
                ),
              ),
            ),
            const Spacer(),
            IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: '새로고침',
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40, color: Colors.black26),
            const SizedBox(height: 10),
            Text(
              '대화를 불러오지 못했습니다.\n$_error',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AdminTheme.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('다시 시도')),
          ],
        ),
      );
    }

    final room = _room!;
    // 좁은 화면에서는 방 정보(320) + 대화를 좌우로 두면 대화가 짓눌린다 —
    // 방 정보를 위로 올리고 대화가 남은 높이를 쓰게 한다.
    if (context.isMobileLayout) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 180, child: _buildRoomCard(room)),
          const SizedBox(height: 12),
          Expanded(child: _buildTranscript(room)),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 320, child: _buildRoomCard(room)),
        const SizedBox(width: 20),
        Expanded(child: _buildTranscript(room)),
      ],
    );
  }

  Widget _buildRoomCard(AdminChatRoom room) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AdminTheme.cardBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(18),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              room.kind.label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AdminTheme.accent,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              (room.relatedTitle?.isNotEmpty ?? false) ? room.relatedTitle! : '-',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const Divider(height: 24),
            _row('채팅방 ID', room.roomId),
            _row(
              'ID 방식',
              room.idScheme == 'deterministic'
                  ? '결정적 id ({게스트uid}_{종류}_{대상id})'
                  : '기존 임의 id (그대로 조회됨)',
            ),
            _row('연결 대상 ID', room.relatedId ?? '-'),
            _row('relatedType', room.relatedType ?? '-'),
            _row('원본 글', room.sourceExists ? '존재' : '삭제됨/찾을 수 없음'),
            const Divider(height: 24),
            _personBlock('게스트', room.guestLabel, room.guestId, room.guest, room.guestNameInRoom),
            const SizedBox(height: 12),
            _personBlock('호스트', room.hostLabel, room.hostId, room.host, room.hostNameInRoom),
            const Divider(height: 24),
            _row('채팅방 생성일', _fmtFull(room.createdAt)),
            _row('최근 메시지 시각', _fmtFull(room.lastMessageAt)),
            _row('메시지 개수', room.messageCount?.toString() ?? '-'),
            const SizedBox(height: 14),
            const Text(
              '신고 상태: 채팅 신고 기능이 아직 앱에 없어 표시할 값이 없습니다.',
              style: TextStyle(fontSize: 11.5, color: AdminTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _personBlock(
    String role,
    String label,
    String? uid,
    ChatUserBrief? brief,
    String? nameInRoom,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              role,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AdminTheme.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        SelectableText(
          uid?.isNotEmpty == true ? uid! : '-',
          style: const TextStyle(
            fontSize: 11,
            fontFamily: 'monospace',
            color: AdminTheme.textSecondary,
          ),
        ),
        if (brief?.email?.isNotEmpty ?? false)
          Text(
            brief!.email!,
            style: const TextStyle(
              fontSize: 11.5,
              color: AdminTheme.textSecondary,
            ),
          ),
        if (brief == null && (uid?.isNotEmpty ?? false))
          const Text(
            '회원 문서 없음(탈퇴 등)',
            style: TextStyle(fontSize: 11, color: Colors.black38),
          ),
        // 방에 박제된 이름과 지금 닉네임이 다르면 둘 다 보여준다 — "그때 이
        // 이름으로 보였다"를 알 수 있어야 대화 내용과 어긋나지 않는다.
        if ((nameInRoom?.isNotEmpty ?? false) &&
            nameInRoom != (brief?.nickname ?? ''))
          Text(
            '방 생성 당시 이름: $nameInRoom',
            style: const TextStyle(fontSize: 11, color: Colors.black38),
          ),
      ],
    );
  }

  Widget _buildTranscript(AdminChatRoom room) {
    // 대화가 0건이어도 상세는 정상으로 열린다 — 방은 "채팅하기"를 누른 순간
    // 만들어지고 메시지는 그 뒤에 쌓이므로, 열자마자 아무 말도 없는 방이
    // 오히려 흔하다. 목록 로딩 실패와 헷갈리지 않게 빈 상태를 또렷하게 쓴다.
    if (_messages.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AdminTheme.cardBorder),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.forum_outlined, size: 40, color: Colors.black26),
              const SizedBox(height: 12),
              const Text(
                '대화 내역이 없습니다.',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AdminTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '채팅방은 ${_fmtFull(room.createdAt)}에 열렸지만\n'
                '아직 주고받은 메시지가 없습니다.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AdminTheme.textSecondary,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 날짜가 바뀌는 자리에 날짜 머리글을 끼운다(시간순 그대로 — 정렬하지 않는다).
    final items = <Widget>[];
    String? lastDay;
    for (final m in _messages) {
      final at = m.createdAt;
      final day = at == null ? null : _dayLabel(at);
      if (day != lastDay) {
        items.add(_dayHeader(day ?? '시각 없음'));
        lastDay = day;
      }
      items.add(_messageTile(m));
    }
    if (_hasMore) {
      items.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Center(
            child: OutlinedButton(
              onPressed: _loadingMore ? null : _loadMore,
              child: Text(_loadingMore ? '불러오는 중…' : '다음 메시지 더 보기'),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AdminTheme.cardBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      child: ListView(children: items),
    );
  }

  Widget _dayHeader(String label) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 10),
    child: Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.bold,
            color: AdminTheme.textSecondary,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(child: Divider(height: 1)),
      ],
    ),
  );

  Widget _messageTile(AdminChatMessage m) {
    // 말풍선을 쓰지 않는다 — 좌우 배치는 "내가 누구인가"를 전제로 하는데,
    // 관리자는 어느 쪽도 아니다. 발신자를 머리글로 붙인 기록지 형태로 둔다.
    final roleColor = switch (m.role) {
      'host' => const Color(0xFF3E6BE0),
      'guest' => const Color(0xFFD9448A),
      _ => AdminTheme.textSecondary,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '[${m.roleLabel} ${m.senderLabel}]',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: roleColor,
                ),
              ),
              const SizedBox(width: 8),
              if (m.isAuto) _tag('자동 안내', const Color(0xFF8A6BD9)),
              if (m.isSystem) _tag('시스템/외부 발신', Colors.black54),
              if (m.isDeleted) _tag('삭제됨', const Color(0xFFB4232B)),
              if (m.extraFields != null) _tag('추가 필드', Colors.orange),
            ],
          ),
          const SizedBox(height: 3),
          // 지워진 말의 원문은 **관리자에게도 보여주지 않는다.** 가리는 게
          // 아니라 서버에 남아 있지 않다(원문 자리는 빈 문자열이다). 레코드는
          // 그대로라 '있었다가 지워졌다'는 사실과 시각·삭제자는 아래에 남는다.
          SelectableText(
            m.isDeleted
                ? '(삭제된 메시지)'
                : (m.text.isEmpty ? '(내용 없음)' : m.text),
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              fontStyle: m.isDeleted ? FontStyle.italic : FontStyle.normal,
              color: m.isDeleted || m.text.isEmpty
                  ? AdminTheme.textSecondary
                  : null,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Text(
                m.createdAt == null ? '시각 없음' : _timeFmt.format(m.createdAt!),
                style: const TextStyle(fontSize: 11, color: Colors.black38),
              ),
              const SizedBox(width: 10),
              SelectableText(
                'senderId: ${m.senderId ?? '-'}',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontFamily: 'monospace',
                  color: Colors.black38,
                ),
              ),
            ],
          ),
          // 알 수 없는 필드는 조용히 버리지 않고 그대로 보여준다. 사용자가 지운
          // 말의 deletedAt·deletedBy가 지금 이 자리로 올라온다 — 원문은 없고
          // 삭제 시각과 삭제한 uid만 남는다.
          if (m.extraFields != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SelectableText(
                m.extraFields!.entries
                    .map((e) => '${e.key}: ${e.value}')
                    .join('  ·  '),
                style: const TextStyle(fontSize: 11, color: Colors.orange),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tag(String label, Color color) => Container(
    margin: const EdgeInsets.only(right: 6),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
    ),
  );

  static String _fmtFull(DateTime? v) => v == null ? '-' : _fullFmt.format(v);

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AdminTheme.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(value, style: const TextStyle(fontSize: 12.5)),
        ),
      ],
    ),
  );
}

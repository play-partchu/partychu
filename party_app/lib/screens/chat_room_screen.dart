import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:party_app/models/report_reason.dart';
import 'package:party_app/services/block_service.dart';
import 'package:party_app/services/chat_service.dart';
import 'package:party_app/services/push_notification_service.dart';
import 'package:party_app/services/push_permission_gate.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/user_safety_actions.dart';

class ChatRoomScreen extends StatefulWidget {
  final String roomId;
  final String otherName;
  final String relatedTitle;

  const ChatRoomScreen({
    super.key,
    required this.roomId,
    required this.otherName,
    required this.relatedTitle,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;

  /// 읽음 표시를 갱신하려고 방 문서를 지켜본다.
  StreamSubscription? _roomSub;

  /// 마지막으로 읽음 표시를 보낸 시점의 lastMessageAt.
  /// 같은 메시지에 대해 두 번 쓰지 않게 한다(쓰기가 실패해도 여기서 멈춘다 —
  /// 규칙이 아직 안 올라간 환경에서 무한 재시도가 나지 않는다).
  DateTime? _markedUpTo;

  /// 대화 상대의 uid — 방 문서의 participants에서 읽는다.
  ///
  /// 생성자로 받지 않는 이유: 이 화면을 여는 자리가 여럿이라(채팅 목록,
  /// 신청 목록, 푸시 알림 …) 인자를 하나 늘리면 호출부를 전부 고쳐야 한다.
  /// 어차피 방 문서는 읽음 표시 때문에 이미 구독하고 있다.
  String _otherUid = '';

  @override
  void initState() {
    super.initState();
    // 입장 시 자동발송 대기 메시지 체크 — 서버가 발송하고, 결과는 메시지
    // 스트림으로 알아서 들어온다. 실패해도 대화 자체는 열려야 하므로 삼킨다
    // (다음 입장 때 다시 시도된다).
    ChatService.flushPendingAutoMessages(widget.roomId).catchError((_) {});

    // 이 방을 보고 있는 동안에는 이 방의 푸시를 그리지 않는다 — 지금 읽고 있는
    // 메시지가 알림으로 또 뜨는 건 잡음이다. 서버는 누가 방을 열어뒀는지 알 수
    // 없어 그냥 보내므로, 걸러내는 건 앱의 몫이다.
    PushNotificationService.activeChatRoomId = widget.roomId;

    // 채팅방에 들어온 지금이 "알림이 왜 필요한지" 가장 잘 이해되는 자리다 —
    // 상대의 답장을 기다리는 시점이기 때문. 첫 프레임 뒤로 미루는 이유는
    // initState 시점의 context로는 bottom sheet를 띄울 수 없어서다.
    //
    // 이미 허용했거나 최근에 '나중에'를 누른 사람에게는 아무것도 뜨지 않는다
    // (PushPermissionGate가 판단한다).
    //
    // 부르는 자리는 **진입 직후 한 번**뿐이다 — 뒤로가기(pop)나 dispose는
    // 안내의 트리거가 아니다. 나가려는 사람 앞에 시트를 세우면 화면을 빠져
    // 나갈 수 없는 것처럼 느껴진다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      PushPermissionGate.ensure(context, PushPromptReason.chat);
    });

    // 방을 보고 있는 동안은 **들어오는 즉시** 읽은 것으로 친다 — 들어올 때
    // 한 번만 처리하면, 열어둔 채로 받은 메시지가 나간 뒤에 안 읽음으로 남는다.
    //
    // 내가 보낸 메시지에는 아무 쓰기도 하지 않는다(isRoomUnread가 lastSenderId를
    // 먼저 보고 false를 준다). 그래서 대화 한 번에 늘어나는 쓰기는 **상대가
    // 말했을 때 한 번**뿐이다.
    _roomSub = ChatService.roomStream(widget.roomId).listen(
      (snap) {
        final d = snap.data();
        if (d == null) return;
        final uid = UserSession.userId;
        final others =
            (d['participants'] as List?)
                ?.whereType<String>()
                .where((p) => p != uid)
                .toList() ??
            const <String>[];
        final other = others.isEmpty ? '' : others.first;
        if (other != _otherUid && mounted) {
          setState(() => _otherUid = other);
        }
        if (!ChatService.isRoomUnread(d, uid)) return;
        final lastAt = (d['lastMessageAt'] as Timestamp?)?.toDate();
        if (lastAt == null) return;
        if (_markedUpTo != null && !lastAt.isAfter(_markedUpTo!)) return;
        _markedUpTo = lastAt;
        // 읽음 표시가 실패해도 대화는 그대로 보여야 한다 — 배지가 남을 뿐이다.
        ChatService.markRoomRead(widget.roomId, uid).catchError((_) {});
      },
      onError: (_) {
        // 방 문서를 못 읽어도 메시지 목록은 자기 스트림으로 계속 그려진다.
      },
    );
  }

  @override
  void dispose() {
    // 방을 나가면 다시 알림을 받아야 한다. 다른 방이 이미 열려 있다면(알림을
    // 눌러 새 방으로 이동한 직후 이 방이 정리되는 경우) 그 방의 표시를 지우지
    // 않도록 내 방일 때만 되돌린다.
    if (PushNotificationService.activeChatRoomId == widget.roomId) {
      PushNotificationService.activeChatRoomId = null;
    }
    _roomSub?.cancel();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── 내가 보낸 메시지 삭제 ────────────────────────────────────────
  //
  // 길게 누르는 자리는 **내 말풍선**뿐이다(자동 안내와 이미 지운 말은 제외).
  // 다만 그건 화면의 편의일 뿐이고, 남의 말을 지울 수 없게 막는 것은
  // firestore.rules의 messages update다 — messageId를 바꿔치기해도 통하지 않는다.
  Future<void> _confirmDeleteMessage(
    String messageId, {
    required bool isLastMessage,
  }) async {
    final choice = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: Color(0xFFFF6FA0),
              ),
              title: const Text('삭제', style: TextStyle(fontSize: 14.5)),
              onTap: () => Navigator.pop(ctx, true),
            ),
            ListTile(
              leading: const Icon(Icons.close, color: Colors.black45),
              title: const Text(
                '취소',
                style: TextStyle(fontSize: 14.5, color: Colors.black54),
              ),
              onTap: () => Navigator.pop(ctx, false),
            ),
          ],
        ),
      ),
    );
    if (choice != true || !mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('메시지를 삭제할까요?', style: TextStyle(fontSize: 16)),
        content: const Text(
          '삭제하면 상대방에게도 내용이 보이지 않고 '
          '"삭제된 메시지입니다."로 바뀝니다. 되돌릴 수 없어요.',
          style: TextStyle(fontSize: 13.5, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소', style: TextStyle(color: Colors.black54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제', style: TextStyle(color: Color(0xFFFF6FA0))),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await ChatService.deleteMessage(
        roomId: widget.roomId,
        messageId: messageId,
        uid: UserSession.userId,
        isLastMessage: isLastMessage,
      );
    } catch (_) {
      // 지우지 못했으면 말풍선은 그대로 남는다 — 지운 척하지 않는다.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('메시지를 삭제하지 못했어요. 잠시 후 다시 시도해주세요.')),
      );
    }
  }

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    // 차단한 상대에게는 보내지 않는다. 입력창도 잠겨 있지만 판정은 여기다.
    if (_otherUid.isNotEmpty && BlockService.isBlocked(_otherUid)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('차단한 사용자에게는 메시지를 보낼 수 없어요.')),
      );
      return;
    }
    setState(() => _sending = true);
    _textCtrl.clear();
    try {
      await ChatService.sendMessage(
        roomId: widget.roomId,
        senderId: UserSession.userId,
        senderName: UserSession.displayName,
        text: text,
      );
      _scrollToBottom();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _fmtTime(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final p = h < 12 ? '오전' : '오후';
    final hh = h % 12 == 0 ? 12 : h % 12;
    return '$p $hh:$m';
  }

  String _fmtDate(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    return '${dt.year}년 ${dt.month}월 ${dt.day}일 (${days[dt.weekday - 1]})';
  }

  @override
  Widget build(BuildContext context) {
    final uid = UserSession.userId;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F8),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.otherName,
              style: const TextStyle(
                fontFamily: 'SeoulHangang',
                fontSize: 16,
                fontWeight: FontWeight.w500,
                shadows: [
                  Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
                  Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
                  Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
                  Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
                ],
              ),
            ),
            if (widget.relatedTitle.isNotEmpty)
              Text(
                widget.relatedTitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.black45,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          // 신고·차단 진입. 대화 상대를 알아낸 뒤에만 보여준다(방 문서를
          // 아직 못 읽었으면 누구를 대상으로 할지 알 수 없다).
          if (_otherUid.isNotEmpty && _otherUid != uid)
            IconButton(
              icon: const Icon(Icons.more_vert),
              tooltip: '신고 · 차단',
              onPressed: () => showUserSafetySheet(
                context,
                targetType: ReportTargetType.chatRoom,
                targetId: widget.roomId,
                targetUserId: _otherUid,
                targetUserName: widget.otherName,
                targetTitle: widget.relatedTitle,
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // 차단한 상대의 방은 목록에서 숨지만, 알림이나 예전 라우트로 여기까지
          // 들어올 수 있다. 그때 아무 표시 없이 평소처럼 보이면 "차단했는데
          // 그대로네"가 된다 — 상태를 그대로 알려주고 입력만 닫는다.
          // (이미 주고받은 말을 지우지는 않는다.)
          ValueListenableBuilder<Set<String>>(
            valueListenable: BlockService.blockedIds,
            builder: (context, blocked, _) {
              if (_otherUid.isEmpty || !blocked.contains(_otherUid)) {
                return const SizedBox.shrink();
              }
              return Container(
                width: double.infinity,
                color: const Color(0xFFFFE3EE),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.block, size: 16, color: Color(0xFFFF6FA0)),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '차단한 사용자예요. 메시지를 보낼 수 없어요.',
                        style: TextStyle(fontSize: 12.5, color: Colors.black87),
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          confirmUnblock(context, _otherUid, widget.otherName),
                      child: const Text(
                        '차단 해제',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFFFF6FA0),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          // ── 메시지 목록 ────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: ChatService.messagesStream(widget.roomId),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFF6FA0)),
                  );
                }

                final docs = snap.data?.docs ?? [];
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _scrollToBottom(),
                );

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('💬', style: TextStyle(fontSize: 40)),
                        const SizedBox(height: 12),
                        Text(
                          '${widget.otherName}와 대화를 시작해보세요.',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                Timestamp? prevDate;
                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final d = docs[i].data() as Map<String, dynamic>;
                    final senderId = d['senderId'] as String? ?? '';
                    final name = d['senderName'] as String? ?? '';
                    final text = d['text'] as String? ?? '';
                    final isAuto = d['isAuto'] as bool? ?? false;
                    final ts = d['createdAt'] as Timestamp?;
                    final isMe = senderId == uid;
                    // 지워진 말은 원문 자리에 안내 문구만 그린다. 원문은 문서에
                    // 남아 있지 않다(ChatService.deleteMessage가 비운다) — 화면이
                    // 가리는 게 아니라 실제로 없다.
                    final isDeleted = ChatService.isMessageDeleted(d);
                    // 목록 미리보기까지 바꿔야 하는지 — 마지막 말인지로 정한다
                    // (스트림이 createdAt 오름차순이라 맨 끝이 마지막 말이다).
                    final isLast = i == docs.length - 1;

                    // 날짜 구분선
                    Widget? dateDivider;
                    if (ts != null) {
                      final cur = Timestamp.fromDate(
                        DateTime(
                          ts.toDate().year,
                          ts.toDate().month,
                          ts.toDate().day,
                        ),
                      );
                      if (prevDate == null || prevDate!.compareTo(cur) != 0) {
                        dateDivider = _DateDivider(label: _fmtDate(ts));
                        prevDate = cur;
                      }
                    }

                    return Column(
                      children: [
                        if (dateDivider case final d?) d,
                        // 자동 발송 메시지
                        if (isAuto)
                          _AutoMessage(text: text, time: _fmtTime(ts))
                        else
                          _Bubble(
                            isMe: isMe,
                            name: name,
                            text: text,
                            time: _fmtTime(ts),
                            isDeleted: isDeleted,
                            // 내 말이면서 아직 안 지운 것만 메뉴가 열린다.
                            // 지워진 말에는 아무 동작도 걸지 않는다.
                            onLongPress: isMe && !isDeleted
                                ? () => _confirmDeleteMessage(
                                    docs[i].id,
                                    isLastMessage: isLast,
                                  )
                                : null,
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),

          // ── 입력창 ─────────────────────────────────────────────────
          ValueListenableBuilder<Set<String>>(
            valueListenable: BlockService.blockedIds,
            builder: (context, blocked, _) => _InputBar(
              controller: _textCtrl,
              sending: _sending,
              blocked: _otherUid.isNotEmpty && blocked.contains(_otherUid),
              onSend: _send,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 날짜 구분선 ──────────────────────────────────────────────────────
class _DateDivider extends StatelessWidget {
  final String label;
  const _DateDivider({required this.label});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.black38),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    ),
  );
}

// ── 자동 발송 메시지 ──────────────────────────────────────────────────
class _AutoMessage extends StatelessWidget {
  final String text;
  final String time;
  const _AutoMessage({required this.text, required this.time});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9E6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE08A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.notifications_outlined,
                size: 13,
                color: Color(0xFFE89200),
              ),
              SizedBox(width: 4),
              Text(
                '자동 안내 메시지',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE89200),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black87,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.bottomRight,
            child: Text(
              time,
              style: const TextStyle(fontSize: 10, color: Colors.black38),
            ),
          ),
        ],
      ),
    ),
  );
}

// ── 말풍선 ───────────────────────────────────────────────────────────
class _Bubble extends StatelessWidget {
  final bool isMe;
  final String name;
  final String text;
  final String time;

  /// 지워진 말 — 원문 대신 안내 문구를 그리고, 아무 동작도 걸지 않는다.
  final bool isDeleted;

  /// 길게 누르기. 내가 보낸, 아직 안 지운 말에만 들어온다(그 밖에는 null이라
  /// 눌러도 아무 일도 일어나지 않는다).
  final VoidCallback? onLongPress;

  const _Bubble({
    required this.isMe,
    required this.name,
    required this.text,
    required this.time,
    this.isDeleted = false,
    this.onLongPress,
  });

  Widget _body() => GestureDetector(
    onLongPress: onLongPress,
    child: _BubbleBody(isMe: isMe, text: text, isDeleted: isDeleted),
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: isMe
          ? [
              // 내 메시지: 시간 왼쪽, 말풍선 오른쪽
              Text(
                time,
                style: const TextStyle(fontSize: 10, color: Colors.black38),
              ),
              const SizedBox(width: 6),
              _body(),
            ]
          : [
              // 상대 메시지: 이름 위, 말풍선 왼쪽, 시간 오른쪽
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.black45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _body(),
                      const SizedBox(width: 6),
                      Text(
                        time,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.black38,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
    ),
  );
}

class _BubbleBody extends StatelessWidget {
  final bool isMe;
  final String text;
  final bool isDeleted;
  const _BubbleBody({
    required this.isMe,
    required this.text,
    this.isDeleted = false,
  });

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxWidth: MediaQuery.of(context).size.width * 0.65,
    ),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFFFF6FA0) : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isMe ? 16 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 16),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      // 지워진 말의 원문은 문서에 남아 있지 않다 — 여기서 가리는 것이
      // 아니라, 서버에 빈 문자열만 있어 그릴 원문 자체가 없다.
      child: Text(
        isDeleted ? ChatService.deletedMessageText : text,
        style: TextStyle(
          fontSize: 14,
          fontStyle: isDeleted ? FontStyle.italic : FontStyle.normal,
          color: isDeleted
              ? (isMe ? Colors.white70 : Colors.black38)
              : (isMe ? Colors.white : Colors.black87),
          height: 1.4,
        ),
      ),
    ),
  );
}

// ── 하단 입력바 ──────────────────────────────────────────────────────
class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;

  /// 차단한 상대인가 — 입력을 잠그고 안내 문구로 바꾼다.
  /// 실제로 보내지 않는 것은 [_ChatRoomScreenState._send]가 막는다.
  final bool blocked;
  final VoidCallback onSend;
  const _InputBar({
    required this.controller,
    required this.sending,
    required this.blocked,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !blocked,
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: blocked ? '차단한 사용자예요.' : '메시지를 입력하세요...',
                hintStyle: const TextStyle(color: Colors.black38, fontSize: 14),
                filled: true,
                fillColor: const Color(0xFFF7F7FA),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: (sending || blocked) ? null : onSend,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: sending ? Colors.grey.shade300 : const Color(0xFFFF6FA0),
                shape: BoxShape.circle,
              ),
              child: sending
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
            ),
          ),
        ],
      ),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:party_app/services/chat_service.dart';
import 'package:party_app/utils/user_session.dart';

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
  final _textCtrl   = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending     = false;

  @override
  void initState() {
    super.initState();
    // 입장 시 자동발송 대기 메시지 체크 — 서버가 발송하고, 결과는 메시지
    // 스트림으로 알아서 들어온다. 실패해도 대화 자체는 열려야 하므로 삼킨다
    // (다음 입장 때 다시 시도된다).
    ChatService.flushPendingAutoMessages(widget.roomId).catchError((_) {});
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _textCtrl.clear();
    try {
      await ChatService.sendMessage(
        roomId:     widget.roomId,
        senderId:   UserSession.userId,
        senderName: UserSession.displayName,
        text:       text,
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
    final h  = dt.hour;
    final m  = dt.minute.toString().padLeft(2, '0');
    final p  = h < 12 ? '오전' : '오후';
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
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.otherName,
              style: const TextStyle(
                  fontFamily: 'SeoulHangang',
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  shadows: [
                    Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
                    Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
                    Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
                    Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
                  ])),
          if (widget.relatedTitle.isNotEmpty)
            Text(widget.relatedTitle,
                style: const TextStyle(
                    fontSize: 11, color: Colors.black45,
                    fontWeight: FontWeight.normal)),
        ]),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Column(children: [
        // ── 메시지 목록 ────────────────────────────────────────────
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: ChatService.messagesStream(widget.roomId),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFFFF6FA0)));
              }

              final docs = snap.data?.docs ?? [];
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _scrollToBottom());

              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('💬',
                          style: TextStyle(fontSize: 40)),
                      const SizedBox(height: 12),
                      Text('${widget.otherName}와 대화를 시작해보세요.',
                          style: const TextStyle(
                              fontSize: 13, color: Colors.black45)),
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
                  final d        = docs[i].data() as Map<String, dynamic>;
                  final senderId = d['senderId']   as String? ?? '';
                  final name     = d['senderName'] as String? ?? '';
                  final text     = d['text']       as String? ?? '';
                  final isAuto   = d['isAuto']     as bool?   ?? false;
                  final ts       = d['createdAt']  as Timestamp?;
                  final isMe     = senderId == uid;

                  // 날짜 구분선
                  Widget? dateDivider;
                  if (ts != null) {
                    final cur = Timestamp.fromDate(DateTime(
                        ts.toDate().year,
                        ts.toDate().month,
                        ts.toDate().day));
                    if (prevDate == null ||
                        prevDate!.compareTo(cur) != 0) {
                      dateDivider = _DateDivider(label: _fmtDate(ts));
                      prevDate    = cur;
                    }
                  }

                  return Column(children: [
                    if (dateDivider case final d?) d,
                    // 자동 발송 메시지
                    if (isAuto)
                      _AutoMessage(text: text, time: _fmtTime(ts))
                    else
                      _Bubble(
                          isMe:   isMe,
                          name:   name,
                          text:   text,
                          time:   _fmtTime(ts)),
                  ]);
                },
              );
            },
          ),
        ),

        // ── 입력창 ─────────────────────────────────────────────────
        _InputBar(
          controller: _textCtrl,
          sending:    _sending,
          onSend:     _send,
        ),
      ]),
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
        child: Row(children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(label,
                style: const TextStyle(
                    fontSize: 11, color: Colors.black38)),
          ),
          const Expanded(child: Divider()),
        ]),
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
            const Row(children: [
              Icon(Icons.notifications_outlined,
                  size: 13, color: Color(0xFFE89200)),
              SizedBox(width: 4),
              Text('자동 안내 메시지',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFE89200))),
            ]),
            const SizedBox(height: 6),
            Text(text,
                style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black87,
                    height: 1.5)),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(time,
                  style: const TextStyle(
                      fontSize: 10, color: Colors.black38)),
            ),
          ]),
        ),
      );
}

// ── 말풍선 ───────────────────────────────────────────────────────────
class _Bubble extends StatelessWidget {
  final bool   isMe;
  final String name;
  final String text;
  final String time;
  const _Bubble({
    required this.isMe,
    required this.name,
    required this.text,
    required this.time,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          mainAxisAlignment:
              isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: isMe
              ? [
                  // 내 메시지: 시간 왼쪽, 말풍선 오른쪽
                  Text(time,
                      style: const TextStyle(
                          fontSize: 10, color: Colors.black38)),
                  const SizedBox(width: 6),
                  _BubbleBody(isMe: true, text: text),
                ]
              : [
                  // 상대 메시지: 이름 위, 말풍선 왼쪽, 시간 오른쪽
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(name,
                        style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black45,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                      _BubbleBody(isMe: false, text: text),
                      const SizedBox(width: 6),
                      Text(time,
                          style: const TextStyle(
                              fontSize: 10, color: Colors.black38)),
                    ]),
                  ]),
                ],
        ),
      );
}

class _BubbleBody extends StatelessWidget {
  final bool   isMe;
  final String text;
  const _BubbleBody({required this.isMe, required this.text});

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.65),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isMe ? const Color(0xFFFF6FA0) : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft:     const Radius.circular(16),
              topRight:    const Radius.circular(16),
              bottomLeft:  Radius.circular(isMe ? 16 : 4),
              bottomRight: Radius.circular(isMe ? 4  : 16),
            ),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x12000000),
                  blurRadius: 4,
                  offset: Offset(0, 2)),
            ],
          ),
          child: Text(text,
              style: TextStyle(
                  fontSize: 14,
                  color: isMe ? Colors.white : Colors.black87,
                  height: 1.4)),
        ),
      );
}

// ── 하단 입력바 ──────────────────────────────────────────────────────
class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: controller,
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: '메시지를 입력하세요...',
                  hintStyle: const TextStyle(
                      color: Colors.black38, fontSize: 14),
                  filled: true,
                  fillColor: const Color(0xFFF7F7FA),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: sending ? null : onSend,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: sending
                      ? Colors.grey.shade300
                      : const Color(0xFFFF6FA0),
                  shape: BoxShape.circle,
                ),
                child: sending
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded,
                        color: Colors.white, size: 20),
              ),
            ),
          ]),
        ),
      );
}

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:party_app/services/chat_service.dart';
import 'package:party_app/screens/chat_room_screen.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/auth_rebuilder.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 로그인 화면에서 로그인을 마치고 돌아왔을 때 뒤로 갔다 다시 들어오지
    // 않아도 즉시 로그인 상태가 반영되도록 AuthRebuilder로 감싼다.
    return AuthRebuilder(builder: _build);
  }

  Widget _build(BuildContext context) {
    final uid = UserSession.userId;
    if (uid.isEmpty) {
      return const Scaffold(
        backgroundColor: Color(0xFFFFF4F8),
        body: Center(
          child: Text('로그인이 필요합니다.',
              style: TextStyle(fontSize: 15, color: Colors.black45)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F8),
      appBar: AppBar(
        title: const Text('채팅',
            style: TextStyle(
              fontFamily: 'SeoulHangang',
              fontSize: 18,
              fontWeight: FontWeight.w500,
              shadows: [
                Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
                Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
                Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
                Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
              ],
            )),
        centerTitle: false,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: ChatService.roomsStream(uid),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(
                    color: Color(0xFFFF6FA0)));
          }

          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('💬',
                      style: TextStyle(fontSize: 56)),
                  const SizedBox(height: 16),
                  const Text('아직 채팅이 없습니다.',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black54)),
                  const SizedBox(height: 8),
                  const Text('파티샵, 파티장소, 파티크루 글에서\n채팅하기 버튼을 눌러보세요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.black38,
                          height: 1.6)),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: docs.length,
            separatorBuilder: (_, idx) =>
                const Divider(height: 1, indent: 72),
            itemBuilder: (_, i) {
              final d        = docs[i].data() as Map<String, dynamic>;
              final roomId   = docs[i].id;
              final names    = (d['participantNames'] as Map<String, dynamic>?) ?? {};
              // 상대방 이름 = 내가 아닌 쪽
              final otherId  = (d['hostId'] as String?) == uid
                  ? (d['guestId']  as String? ?? '')
                  : (d['hostId']   as String? ?? '');
              final otherName = names[otherId] as String? ?? '상대방';
              final title    = d['relatedTitle']  as String? ?? '';
              final type     = d['relatedType']   as String? ?? '';
              final last     = d['lastMessage']   as String? ?? '';
              final lastAt   = d['lastMessageAt'] as Timestamp?;

              final typeLabel = switch (type) {
                'shop'  => '파티샵',
                'place' => '파티장소',
                'crew'  => '파티크루',
                _       => '채팅',
              };

              String timeStr = '';
              if (lastAt != null) {
                final dt  = lastAt.toDate();
                final now = DateTime.now();
                if (now.difference(dt).inDays == 0) {
                  final h = dt.hour;
                  final m = dt.minute.toString().padLeft(2, '0');
                  final p = h < 12 ? '오전' : '오후';
                  final hh = h % 12 == 0 ? 12 : h % 12;
                  timeStr = '$p $hh:$m';
                } else if (now.difference(dt).inDays < 7) {
                  const days = ['월', '화', '수', '목', '금', '토', '일'];
                  timeStr = '${days[dt.weekday - 1]}요일';
                } else {
                  timeStr = '${dt.month}/${dt.day}';
                }
              }

              return InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatRoomScreen(
                      roomId:     roomId,
                      otherName:  otherName,
                      relatedTitle: title,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(children: [
                    // 아바타
                    Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFE0EE),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          otherName.isNotEmpty
                              ? otherName.substring(0, 1)
                              : '?',
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFFF6FA0)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Row(children: [
                          Expanded(
                            child: Text(otherName,
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                          Text(timeStr,
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.black38)),
                        ]),
                        const SizedBox(height: 2),
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF0F5),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(typeLabel,
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFFFF6FA0),
                                    fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              title.isNotEmpty ? title : '',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.black45),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ]),
                        if (last.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(last,
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.black54),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ]),
                    ),
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

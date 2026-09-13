import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:party_app/services/block_service.dart';
import 'package:party_app/services/chat_service.dart';
import 'package:party_app/screens/chat_room_screen.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/auth_rebuilder.dart';
import 'package:party_app/widgets/web_frame.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  /// '다시 시도' — 값이 바뀌면 StreamBuilder가 스트림을 새로 만든다.
  /// 거부된 Firestore 리스너는 스스로 재시도하지 않아서 다시 구독하는 것
  /// 말고는 복구할 방법이 없다.
  int _retry = 0;

  @override
  Widget build(BuildContext context) {
    // 로그인 화면에서 로그인을 마치고 돌아왔을 때 뒤로 갔다 다시 들어오지
    // 않아도 즉시 로그인 상태가 반영되도록 AuthRebuilder로 감싼다.
    return AuthRebuilder(builder: _build);
  }

  /// 채팅방 삭제 — **내 목록에서만** 지운다.
  ///
  /// 방 문서도 지난 메시지도 그대로 남는다(관리자 채팅 관리에서 기록이
  /// 사라지면 안 된다). 상대의 목록도 건드리지 않는다. 상대가 다시 말을 걸면
  /// 이 방은 내 목록에 되살아난다 — [ChatService.deleteRoomForMe] 주석 참고.
  Future<void> _confirmDeleteRoom(
    String roomId,
    String otherName,
    String uid,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('채팅방을 삭제할까요?', style: TextStyle(fontSize: 16)),
        content: Text(
          '$otherName님과의 대화가 내 목록에서만 사라집니다. '
          '상대방의 채팅방은 그대로 남고, 새 메시지가 오면 다시 나타나요.',
          style: const TextStyle(fontSize: 13.5, height: 1.5),
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
      await ChatService.deleteRoomForMe(roomId, uid);
    } catch (e, st) {
      // 지우지 못했으면 목록은 그대로 남는다 — 조용히 사라진 척하지 않는다.
      logFirestoreStreamError('ChatList.deleteRoom', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('채팅방을 삭제하지 못했어요. 잠시 후 다시 시도해주세요.')),
      );
    }
  }

  Widget _build(BuildContext context) {
    final uid = UserSession.userId;
    if (uid.isEmpty) {
      return const Scaffold(
        backgroundColor: Color(0xFFFFF4F8),
        body: Center(
          child: Text(
            '로그인이 필요합니다.',
            style: TextStyle(fontSize: 15, color: Colors.black45),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F8),
      appBar: AppBar(
        title: const Text(
          '채팅',
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
          ),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: ValueListenableBuilder<Set<String>>(
        valueListenable: BlockService.blockedIds,
        builder: (context, blockedIds, _) =>
            StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
              key: ValueKey(_retry),
              stream: ChatService.roomsStream(uid),
              builder: (context, snap) {
                // 오류를 **먼저** 본다 — 예전에는 `snap.data?.docs ?? []`로 받아서
                // 조회가 죽어도 "아직 채팅이 없습니다"가 떴다. 실제로 chatRooms에는
                // 규칙이 아예 없어 늘 PERMISSION_DENIED였고, 그 화면 때문에 채팅
                // 기능이 통째로 막혀 있다는 사실이 겉으로 드러나지 않았다.
                if (snap.hasError) {
                  logFirestoreStreamError(
                    'ChatList',
                    snap.error,
                    snap.stackTrace,
                  );
                  return _ChatListError(
                    onRetry: () => setState(() => _retry++),
                  );
                }
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFF6FA0)),
                  );
                }

                // 차단한 상대와의 방은 목록에서 숨긴다. 방 문서도 지난 메시지도
                // 그대로 남는다 — 차단은 삭제가 아니고, 해제하면 다시 보여야 한다
                // (상대 목록도 건드리지 않는다).
                final docs =
                    (snap.data ??
                            const <
                              QueryDocumentSnapshot<Map<String, dynamic>>
                            >[])
                        .where((doc) {
                          final d = doc.data();
                          final other = (d['hostId'] as String?) == uid
                              ? (d['guestId'] as String? ?? '')
                              : (d['hostId'] as String? ?? '');
                          return !blockedIds.contains(other);
                        })
                        .toList();
                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('💬', style: TextStyle(fontSize: 56)),
                        const SizedBox(height: 16),
                        const Text(
                          '아직 채팅이 없습니다.',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '파티샵, 파티장소, 파티크루 글에서\n채팅하기 버튼을 눌러보세요.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.black38,
                            height: 1.6,
                          ),
                        ),
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
                    // roomsStream이 이미 Map 타입으로 좁혀 돌려준다(캐스팅 불필요).
                    final d = docs[i].data();
                    final roomId = docs[i].id;
                    final names =
                        (d['participantNames'] as Map<String, dynamic>?) ?? {};
                    // 상대방 이름 = 내가 아닌 쪽
                    final otherId = (d['hostId'] as String?) == uid
                        ? (d['guestId'] as String? ?? '')
                        : (d['hostId'] as String? ?? '');
                    final otherName = names[otherId] as String? ?? '상대방';
                    final title = d['relatedTitle'] as String? ?? '';
                    final type = d['relatedType'] as String? ?? '';
                    final last = d['lastMessage'] as String? ?? '';
                    final lastAt = d['lastMessageAt'] as Timestamp?;
                    // 하단 채팅 탭 배지와 **같은 판정**을 쓴다 — 숫자와 줄 표시가
                    // 어긋나지 않는다(ChatService.isRoomUnread).
                    final unread = ChatService.isRoomUnread(d, uid);

                    final typeLabel = switch (type) {
                      'party' => '파티',
                      'shop' => '파티샵',
                      'place' => '파티장소',
                      'crew' => '파티크루',
                      // 이벤트 문의 — relatedTitle에 이벤트 제목이 들어 있어
                      // "이벤트 · OO 이벤트 문의"처럼 대상이 그대로 보인다.
                      'event' => '이벤트',
                      _ => '채팅',
                    };

                    String timeStr = '';
                    if (lastAt != null) {
                      final dt = lastAt.toDate();
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
                      // 길게 누르면 이 방을 내 목록에서 지운다(확인창을 먼저 띄운다).
                      onLongPress: () =>
                          _confirmDeleteRoom(roomId, otherName, uid),
                      onTap: () => Navigator.push(
                        context,
                        webFramedRoute(
                          (_) => ChatRoomScreen(
                            roomId: roomId,
                            otherName: otherName,
                            relatedTitle: title,
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
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
                                    color: Color(0xFFFF6FA0),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          otherName,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                        timeStr,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.black38,
                                        ),
                                      ),
                                      if (unread) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFFF6FA0),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFF0F5),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          typeLabel,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Color(0xFFFF6FA0),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          title.isNotEmpty ? title : '',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.black45,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (last.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      last,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: unread
                                            ? Colors.black87
                                            : Colors.black54,
                                        fontWeight: unread
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
      ),
    );
  }
}

/// 채팅 목록 조회 실패 — "아직 채팅이 없습니다"와 절대 같은 화면을 쓰지 않는다.
/// 대화가 멀쩡히 있는데 없다고 말하면 사용자는 상대의 답을 영영 놓친다.
class _ChatListError extends StatelessWidget {
  const _ChatListError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.black26),
          const SizedBox(height: 12),
          const Text(
            '채팅 목록을 불러오지 못했어요.\n주고받은 대화는 그대로 남아 있어요.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black45, height: 1.5),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('다시 시도'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFF6FA0),
              side: const BorderSide(color: Color(0xFFFFC2D6)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

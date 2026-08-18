import 'package:flutter/material.dart';

import 'package:party_app/services/notification_service.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/utils/notification_route.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/partychu_ui.dart';
import 'package:party_app/widgets/web_frame.dart';

const _kAccent = Color(0xFFFF6FA0);

/// 알림함 — 서버가 남긴 알림을 사용자가 실제로 보는 곳.
///
/// 같은 알림이 푸시로도 나가지만(functions/pushDispatch.js), 푸시는 놓치거나
/// 권한을 꺼둘 수 있어 **놓친 소식을 다시 볼 수 있는 곳**이 이 화면이다.
/// 눌렀을 때 열리는 화면은 푸시로 눌렀을 때와 같다(notification_route.dart).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String get _uid => UserSession.userId;

  /// '다시 시도' — 값이 바뀌면 StreamBuilder가 스트림을 새로 만든다.
  int _retry = 0;

  @override
  void initState() {
    super.initState();
    // 목록을 열면 읽음 처리 — 배지가 계속 남아 있지 않도록.
    NotificationService.markAllRead(_uid);
  }

  String _timeAgo(DateTime? at) {
    if (at == null) return '';
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return '방금';
    if (diff.inHours < 1) return '${diff.inMinutes}분 전';
    if (diff.inDays < 1) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return '${at.month}월 ${at.day}일';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          '알림',
          style: TextStyle(
            fontFamily: 'SeoulHangang',
            fontWeight: FontWeight.w500,
            fontSize: 16,
            shadows: [
              Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
              Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
            ],
          ),
        ),
      ),
      body: StreamBuilder<List<AppNotification>>(
        key: ValueKey(_retry),
        stream: NotificationService.watch(_uid),
        builder: (context, snapshot) {
          // 오류를 **먼저** 본다 — 예전에는 `snapshot.data ?? []`로 받아서
          // 조회가 죽어도 "아직 알림이 없어요"가 떴다. 알림은 파티 자동 취소
          // 같은 소식이 들어오는 곳이라, 못 읽은 걸 없다고 말하면 사용자가
          // 그 소식을 영영 놓친다. 거부된 리스너는 스스로 재시도하지 않으므로
          // 다시 구독할 수단('다시 시도')도 함께 준다.
          if (snapshot.hasError) {
            logFirestoreStreamError(
              'NotificationsScreen',
              snapshot.error,
              snapshot.stackTrace,
            );
            return _NotificationsError(
              onRetry: () => setState(() => _retry++),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _kAccent),
            );
          }
          final items = snapshot.data ?? const <AppNotification>[];
          if (items.isEmpty) {
            return const PawEmptyState(
              title: '아직 알림이 없어요',
              subtitle: '파티 소식이 생기면 여기로 알려드릴게요 💌',
              icon: Icons.notifications_none_rounded,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _tile(items[i]),
          );
        },
      ),
    );
  }

  /// 알림을 눌렀을 때 열 화면. 갈 곳이 없으면 null이라 탭 자체가 막힌다.
  ///
  /// 규칙 자체는 notification_route.dart에 있다 — 같은 알림을 푸시로 눌렀을
  /// 때도 똑같은 화면이 열려야 하기 때문이다.
  Widget? _targetOf(AppNotification n) => notificationTarget({
    'type': n.type,
    'role': n.role,
    'partyId': n.partyId,
  });

  Widget _tile(AppNotification n) {
    // 취소 안내는 붉은 톤으로 — 확인하지 않고 지나치면 안 되는 소식이다.
    final isCancel = n.type == 'partyAutoCancelledMinCapacity';
    // 방문 예약 알림은 예약 목록으로 보낸다 — 업주에게 온 알림이면 승인 화면,
    // 이용자에게 온 알림이면 내 방문 예약.
    final isVisit = n.type.startsWith('visit_reservation');
    final target = _targetOf(n);
    return InkWell(
      onTap: target == null
          ? null
          : () {
              NotificationService.markRead(n.id);
              Navigator.push(context, webFramedRoute((_) => target));
            },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: n.read ? const Color(0xFFE8EBF2) : _kAccent,
            width: n.read ? 1 : 1.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isCancel ? Icons.event_busy_rounded : Icons.notifications_rounded,
              size: 20,
              color: isCancel ? const Color(0xFFE53935) : _kAccent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          n.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: n.read
                                ? FontWeight.w600
                                : FontWeight.w800,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _timeAgo(n.createdAt),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black38,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    n.body,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Colors.black54,
                      height: 1.45,
                    ),
                  ),
                  if (target != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      isVisit ? '예약 보러 가기 ›' : '파티 보러 가기 ›',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _kAccent,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 알림 조회 실패 — "알림이 없어요"와 절대 같은 화면을 쓰지 않는다.
class _NotificationsError extends StatelessWidget {
  const _NotificationsError({required this.onRetry});

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
                '알림을 불러오지 못했어요.\n안 읽은 소식이 있을 수 있어요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black45, height: 1.5),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('다시 시도'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kAccent,
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

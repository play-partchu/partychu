import 'package:flutter/material.dart';

import 'package:party_app/screens/host_inbox_screen.dart';
import 'package:party_app/screens/my_visit_reservations_screen.dart';
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

  // ⚠️ 화면을 열었다고 **자동으로 모두 읽음 처리하지 않는다.**
  //
  // 예전에는 initState에서 markAllRead(uid)를 불렀다. 그러면 목록이 그려지기도
  // 전에 모든 알림이 읽음이 되어, "안 읽은 알림"이라는 상태가 사용자 눈에는
  // 한 번도 보이지 않았다 — 강조도, 읽음 표시도, 종 배지도 전부 뜻을 잃는다
  // (열자마자 배지가 사라지므로 무엇이 새 소식이었는지 알 수 없다).
  //
  // 이제 읽음은 **사용자의 행동**으로만 바뀐다:
  //   · 알림(또는 CTA)을 누른다 → 그 한 건만 읽음
  //   · 앱바의 '모두 읽음'을 누른다 → 안 읽은 것 전부 읽음
  // 판정의 정본은 예전 그대로 `notifications` 문서의 `read` 필드 하나다.

  /// 읽음 처리 실패를 조용히 삼키지 않는다 — 화면에는 읽음으로 보이는데
  /// 서버에는 안 남으면, 종 배지만 계속 켜져 있고 이유를 알 수 없다.
  /// (Firestore는 쓰기를 로컬에 먼저 반영했다가 실패하면 되돌리므로, 실패하면
  /// 타일도 저절로 '안 읽음'으로 돌아온다 — 안내만 덧붙이면 된다.)
  void _warnReadFailed(Object error) {
    logFirestoreStreamError('NotificationMarkRead', error, null);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('읽음 처리를 저장하지 못했어요. 잠시 후 다시 시도해주세요.')),
    );
  }

  /// 알림 한 건을 열면서 읽음 처리한다.
  ///
  /// 갈 곳이 없는 알림([target]이 null)이라도 **읽음 처리는 한다** — 그러지
  /// 않으면 그 알림은 영영 안 읽음으로 남아 종 배지가 내려가지 않는다.
  ///
  /// 이미 읽은 알림에는 쓰기를 보내지 않는다(같은 값을 다시 쓰는 요청).
  void _openNotification(AppNotification n, Widget? target) {
    if (!n.read) {
      // 반환된 Future를 기다리지 않는다 — Firestore가 로컬에 즉시 반영하므로
      // 목록 스트림이 그 자리에서 '읽음'으로 다시 그려진다(화면 이동과
      // 무관하게).
      NotificationService.markRead(n.id).catchError(_warnReadFailed);
    }
    if (target == null) return;
    Navigator.push(context, webFramedRoute((_) => target));
  }

  Future<void> _markAllRead() async {
    try {
      await NotificationService.markAllRead(_uid);
    } catch (e) {
      _warnReadFailed(e);
    }
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
        actions: [_markAllReadAction()],
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
            return _NotificationsError(onRetry: () => setState(() => _retry++));
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

  /// 앱바의 '모두 읽음' — 안 읽은 알림이 하나라도 있을 때만 나타난다.
  ///
  /// 안 읽음 개수는 종 배지와 **같은 스트림**([NotificationService.watchUnreadCount])
  /// 을 본다 — 화면마다 따로 세면 "배지는 켜져 있는데 버튼은 없는" 상태가
  /// 생긴다. 개수를 못 읽었을 때(오류)는 버튼을 숨기지 않고 그대로 둔다:
  /// 눌러서 정리할 길까지 막을 이유가 없다.
  Widget _markAllReadAction() {
    return StreamBuilder<int>(
      stream: NotificationService.watchUnreadCount(_uid),
      builder: (context, snapshot) {
        final unread = snapshot.hasError || (snapshot.data ?? 0) > 0;
        if (!unread) return const SizedBox.shrink();
        return TextButton(
          onPressed: _markAllRead,
          style: TextButton.styleFrom(
            foregroundColor: _kAccent,
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          child: const Text(
            '모두 읽음',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        );
      },
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

  /// 제목 줄 오른쪽 끝의 상태·시각 — 읽은 알림에는 **'읽음'을 글자로** 적는다.
  ///
  /// 색이나 굵기 차이만으로는 "이걸 내가 봤던가"에 답이 안 된다(옆에 비교할
  /// 안 읽은 알림이 없으면 더욱). 그래서 읽음은 표시가 아니라 **말**로 적고,
  /// 안 읽음은 굳이 적지 않는다 — 점·굵은 제목·연한 핑크 배경이 이미 "새
  /// 소식"이라고 말하고 있어서 '안읽음'까지 적으면 같은 말이 두 번이 된다.
  ///
  /// 세로로 한 줄을 더 쓰지 않도록 시각과 한 줄에 이어 붙인다('읽음 · 1일 전').
  Widget _metaLine(AppNotification n) {
    final time = _timeAgo(n.createdAt);
    const timeStyle = TextStyle(fontSize: 11, color: Colors.black38);
    if (!n.read) return Text(time, style: timeStyle);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 시각보다 한 톤 진하게 — 회색이되 흐려서 안 보이면 뜻이 없다.
        const Text(
          '읽음',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF8E939B),
          ),
        ),
        // createdAt이 없는 문서(서버 타임스탬프가 아직 안 박힌 순간)에는
        // 가운뎃점만 덩그러니 남지 않게 시각 쪽을 통째로 뺀다.
        if (time.isNotEmpty) Text(' · $time', style: timeStyle),
      ],
    );
  }

  Widget _tile(AppNotification n) {
    // 취소 안내는 붉은 톤으로 — 확인하지 않고 지나치면 안 되는 소식이다.
    final isCancel = n.type == 'partyAutoCancelledMinCapacity';
    final target = _targetOf(n);
    // 안내 문구는 **실제로 열리는 화면**을 보고 정한다 — 종류로 다시 판정하면
    // notification_route.dart의 규칙과 어긋나 "파티 보러 가기"를 눌렀는데
    // 신청 관리가 열리는 일이 생긴다.
    final ctaLabel = switch (target) {
      HostInboxScreen() => '신청 관리하러 가기 ›',
      MyVisitReservationsScreen() => '예약 보러 가기 ›',
      _ => '파티 보러 가기 ›',
    };
    // 갈 곳이 없는 알림도 누를 수 있어야 한다 — 눌러서 읽음 처리는 되고,
    // 이동만 하지 않는다. (예전에는 onTap 자체가 null이라 그 알림은 영영
    // 안 읽음으로 남아 종 배지가 내려가지 않았다.)
    return InkWell(
      onTap: () => _openNotification(n, target),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          // 안 읽은 알림만 연한 핑크로 깔아 "새 소식"이 훑어보다 바로 눈에
          // 들어오게 한다. 읽은 알림은 흰 카드 그대로다.
          color: n.read ? Colors.white : const Color(0xFFFFF3F7),
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
                  // 제목 줄 하나에 전부 담는다 — 읽음 표시 때문에 줄이
                  // 늘어나면 목록이 훑기 어려워진다.
                  //   안 읽음 : ● 새 파티 신청이 들어왔어요      1일 전
                  //   읽음   :   새 파티 신청이 들어왔어요  읽음 · 1일 전
                  Row(
                    children: [
                      // 안 읽은 알림에만 핑크 점 — 굵은 제목·연한 핑크 배경과
                      // 함께 "아직 안 본 것"을 세 가지로 겹쳐 알린다.
                      if (!n.read) ...[
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: _kAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
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
                      _metaLine(n),
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
                    // CTA도 카드 전체와 **같은 처리**를 부른다 — 눌러서 이동한
                    // 곳만 읽음이 안 되는 일이 없도록 입구를 하나로 둔다.
                    InkWell(
                      onTap: () => _openNotification(n, target),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          ctaLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _kAccent,
                          ),
                        ),
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

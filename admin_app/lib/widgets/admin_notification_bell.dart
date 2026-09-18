import 'package:flutter/material.dart';

import '../models/admin_notification.dart';
import '../services/admin_notification_service.dart';
import '../theme/admin_theme.dart';
import '../utils/responsive.dart';

/// 상단바의 종 아이콘 — 안 읽은 알림 수를 빨간 배지로 띄우고, 누르면 최근
/// 알림 목록을 연다.
///
/// PC는 종 바로 아래 팝오버, 모바일은 화면 너비를 쓰는 바텀시트다. 두 경우
/// 모두 같은 목록 위젯([AdminNotificationList])을 쓴다 — 목록을 두 벌 만들면
/// 한쪽만 고치는 일이 반드시 생긴다.
class AdminNotificationBell extends StatelessWidget {
  /// 알림을 눌렀을 때. 셸이 화면 전환을 맡는다.
  final void Function(AdminNotification) onOpen;

  /// '전체 알림 보기'.
  final VoidCallback onOpenAll;

  const AdminNotificationBell({
    super.key,
    required this.onOpen,
    required this.onOpenAll,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AdminNotification>>(
      stream: AdminNotificationService.watch(
        limit: AdminNotificationService.recentLimit,
      ),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <AdminNotification>[];
        final uid = AdminNotificationService.currentUid;
        // 개수를 못 읽었을 때 0으로 떨어뜨리면 "안 읽은 알림이 없다"는 거짓
        // 정보가 된다. 사용자 앱 종과 같은 태도로, 실패하면 점을 남겨 눌러
        // 확인하게 한다.
        final failed = snapshot.hasError;
        final unread = items.where((n) => !n.isReadBy(uid)).length;

        return _BellButton(
          unread: unread,
          failed: failed,
          onTap: () => _openPanel(context, items),
        );
      },
    );
  }

  void _openPanel(BuildContext context, List<AdminNotification> items) {
    if (context.isMobileLayout) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (sheetContext) => SafeArea(
          child: ConstrainedBox(
            // 화면의 3/4까지만 — 목록이 길어도 시트가 화면을 다 덮지 않는다.
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.75,
            ),
            child: AdminNotificationList(
              onOpen: (n) {
                Navigator.pop(sheetContext);
                onOpen(n);
              },
              onOpenAll: () {
                Navigator.pop(sheetContext);
                onOpenAll();
              },
            ),
          ),
        ),
      );
      return;
    }

    // PC — 종 아래에 붙는 팝오버.
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);

    showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (dialogContext) => Stack(
        children: [
          Positioned(
            // 종의 오른쪽 끝에 맞춰 왼쪽으로 펼친다. 화면 왼쪽으로 넘어가지
            // 않도록 12px 아래로는 내려가지 않게 잡는다.
            top: topLeft.dy + box.size.height + 8,
            right: (overlay.size.width - (topLeft.dx + box.size.width))
                .clamp(12.0, overlay.size.width - 12.0),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: 380,
                height: 460,
                child: AdminNotificationList(
                  onOpen: (n) {
                    Navigator.pop(dialogContext);
                    onOpen(n);
                  },
                  onOpenAll: () {
                    Navigator.pop(dialogContext);
                    onOpenAll();
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BellButton extends StatelessWidget {
  final int unread;
  final bool failed;
  final VoidCallback onTap;
  const _BellButton({
    required this.unread,
    required this.failed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final showBadge = failed || unread > 0;
    return IconButton(
      tooltip: failed ? '알림 상태를 불러오지 못했어요' : '알림',
      onPressed: onTap,
      icon: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          const Icon(Icons.notifications_none_rounded, size: 22),
          if (showBadge)
            Positioned(
              top: -4,
              right: -6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                constraints: const BoxConstraints(minWidth: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE5484D),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: Colors.white, width: 1.2),
                ),
                child: Text(
                  // 세 자리가 넘어가면 배지가 종을 덮는다.
                  failed ? '!' : (unread > 99 ? '99+' : '$unread'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    height: 1.3,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 알림 목록 본문 — 종 팝오버·바텀시트·전체 화면이 모두 이걸 쓴다.
class AdminNotificationList extends StatelessWidget {
  final void Function(AdminNotification) onOpen;

  /// '전체 알림 보기'. 전체 화면에서는 null을 넘겨 버튼을 감춘다.
  final VoidCallback? onOpenAll;

  /// 전체 화면은 더 많이 받는다.
  final int limit;

  const AdminNotificationList({
    super.key,
    required this.onOpen,
    this.onOpenAll,
    this.limit = AdminNotificationService.recentLimit,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AdminNotification>>(
      stream: AdminNotificationService.watch(limit: limit),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <AdminNotification>[];
        final uid = AdminNotificationService.currentUid;
        final hasUnread = items.any((n) => !n.isReadBy(uid));

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, hasUnread: hasUnread, items: items),
            const Divider(height: 1, color: AdminTheme.cardBorder),
            Flexible(
              child: _body(context, snapshot: snapshot, items: items, uid: uid),
            ),
            if (onOpenAll != null) ...[
              const Divider(height: 1, color: AdminTheme.cardBorder),
              TextButton(
                onPressed: onOpenAll,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('전체 알림 보기'),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _header(
    BuildContext context, {
    required bool hasUnread,
    required List<AdminNotification> items,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              '알림',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
          TextButton(
            // 안 읽은 게 없으면 누를 이유가 없다 — 비활성으로 그 사실을 보인다.
            onPressed: hasUnread
                ? () => AdminNotificationService.markAllRead(items)
                : null,
            child: const Text('모두 읽음'),
          ),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context, {
    required AsyncSnapshot<List<AdminNotification>> snapshot,
    required List<AdminNotification> items,
    required String uid,
  }) {
    if (snapshot.hasError) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          '알림을 불러오지 못했습니다.\n관리자 권한과 네트워크를 확인해주세요.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AdminTheme.textSecondary),
        ),
      );
    }
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: CircularProgressIndicator(color: AdminTheme.accent),
        ),
      );
    }
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          '아직 알림이 없습니다.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AdminTheme.textSecondary),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: items.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: AdminTheme.cardBorder),
      itemBuilder: (context, i) => AdminNotificationTile(
        notification: items[i],
        isRead: items[i].isReadBy(uid),
        onTap: () => onOpen(items[i]),
      ),
    );
  }
}

/// 알림 한 줄 — 종류 딱지 · 제목 · 내용 · 시간 · 읽음 여부.
class AdminNotificationTile extends StatelessWidget {
  final AdminNotification notification;
  final bool isRead;
  final VoidCallback onTap;

  const AdminNotificationTile({
    super.key,
    required this.notification,
    required this.isRead,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final n = notification;
    return InkWell(
      onTap: onTap,
      child: Container(
        // 안 읽은 줄만 옅게 강조한다 — 읽고 나면 색이 빠져 무엇이 새 소식인지
        // 눈으로 구분된다.
        color: isRead ? null : AdminTheme.accentLight.withValues(alpha: 0.45),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 5, right: 10),
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: isRead ? Colors.transparent : AdminTheme.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _TypeChip(label: n.typeLabel),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          adminNotificationTimeAgo(n.createdAt),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AdminTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    n.title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: isRead ? FontWeight.w500 : FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    n.body,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AdminTheme.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  const _TypeChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFE0E7FF),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFF3730A3),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

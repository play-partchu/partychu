import 'package:flutter/material.dart';

import '../models/admin_notification.dart';
import '../services/admin_notification_service.dart';
import '../theme/admin_theme.dart';
import '../widgets/admin_notification_bell.dart';

/// 전체 알림 화면 — 상단 종의 '전체 알림 보기'가 여는 곳.
///
/// 목록 자체는 종 팝오버와 **같은 위젯**([AdminNotificationList])을 쓴다.
/// 받는 개수만 늘리고 '전체 보기' 버튼을 감춘다.
class AdminNotificationsScreen extends StatelessWidget {
  /// 알림을 눌렀을 때. 셸이 화면 전환을 맡는다.
  final void Function(AdminNotification) onOpen;

  const AdminNotificationsScreen({super.key, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('알림', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text(
          '운영자가 처리해야 할 일이 생기면 여기에 쌓입니다 — 최신순.',
          style: TextStyle(fontSize: 12.5, color: AdminTheme.textSecondary),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AdminTheme.cardBorder),
            ),
            clipBehavior: Clip.antiAlias,
            child: AdminNotificationList(
              onOpen: onOpen,
              limit: AdminNotificationService.allLimit,
            ),
          ),
        ),
      ],
    );
  }
}

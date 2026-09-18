import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/blocked_relations_screen.dart';
import '../screens/chat_room_detail_screen.dart';
import '../screens/chat_rooms_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/feedback_requests_screen.dart';
import '../screens/host_pre_registration_detail_screen.dart';
import '../screens/host_pre_registrations_screen.dart';
import '../screens/member_detail_screen.dart';
import '../screens/members_screen.dart';
import '../screens/refund_requests_screen.dart';
import '../screens/reports_screen.dart';
import '../screens/sales_stats_screen.dart';
import '../screens/system_errors_screen.dart';
import '../screens/usage_stats_screen.dart';
import '../screens/verified_users_screen.dart';
import '../models/admin_notification.dart';
import '../screens/admin_notifications_screen.dart';
import '../services/admin_notification_service.dart';
import '../theme/admin_theme.dart';
import '../utils/admin_notification_route.dart';
import '../utils/responsive.dart';
import '../widgets/admin_notification_bell.dart';

class _MenuItem {
  final String label;
  final IconData icon;

  /// 사이드바에서만 감춘다. 순서·번호(_buildContent의 case)는 그대로 둬서
  /// 다시 켤 때 이 값만 false로 돌리면 된다.
  final bool hidden;
  const _MenuItem(this.label, this.icon, {this.hidden = false});
}

// "회원 관리"가 통합 회원 목록이다 — 호스트/게스트는 별도 메뉴가 아니라
// 그 화면 안의 활동 유형 필터로 구분한다(members_screen.dart 참고).
const _menuItems = [
  _MenuItem('대시보드', Icons.dashboard_outlined),
  _MenuItem('회원 관리', Icons.people_outline),
  // FormHug 사전등록 신청서(hostPreRegistrations). 사업자 권한은 여기서 만들지
  // 않는다 — 기존 사업자 인증·대표자 위임 흐름을 그대로 쓴다.
  _MenuItem('호스트 사전등록', Icons.storefront_outlined),
  _MenuItem('본인확인 목록', Icons.verified_user_outlined),
  _MenuItem('이용 통계', Icons.insights_outlined),
  // 판매 통계 — 매출 계산은 packages/partychu_sales(호스트 앱과 공용)가 정본이고,
  // 읽기는 관리자 전용 콜러블 adminGetSalesEntries 하나만 쓴다.
  //
  // ⚠ 임시 숨김(2026-09-13): adminGetSalesEntries가 운영에 아직 배포되지 않아
  //   메뉴를 열면 오류가 난다. 함수 배포 후 hidden을 지우면 그대로 돌아온다.
  _MenuItem('판매 통계', Icons.payments_outlined, hidden: true),
  _MenuItem('환불 요청', Icons.account_balance_wallet_outlined),
  _MenuItem('채팅 관리', Icons.forum_outlined),
  // 앱 '의견 보내기'(feedbackRequests) — 개선 제안·버그 신고·이용 문의가
  // 한 컬렉션에 유형으로 갈려 들어온다. 바로 아래 '시스템 오류'와는 다른
  // 데이터다(그쪽은 스케줄 함수 실패 로그).
  _MenuItem('의견·버그 신고', Icons.bug_report_outlined),
  // 사용자·게시물 신고(reports). 바로 위 '의견·버그 신고'와는 **다른
  // 데이터**다 — 그쪽은 운영진에게 보내는 문의고, 이쪽은 다른 사용자를
  // 신고한 것이다.
  _MenuItem('신고 관리', Icons.flag_outlined),
  // 사용자가 직접 건 차단(userBlocks). 조회 전용이다.
  _MenuItem('차단 내역', Icons.block),
  _MenuItem('시스템 오류', Icons.error_outline),
  // 관리자 업무 알림 전체 목록(adminNotifications). 상단 종의 '전체 알림 보기'가
  // 여는 곳이기도 하다.
  //
  // ⚠ **맨 뒤에 붙였다.** 중간에 끼우면 _buildContent의 case 번호가 전부 밀린다
  //   (바로 아래 주석 참고). 새 메뉴는 앞으로도 끝에 붙이는 편이 안전하다.
  _MenuItem('알림', Icons.notifications_none_rounded),
];

/// 좌측 사이드바 + 상단바(관리자 이메일/로그아웃) + 중앙 컨텐츠.
/// 별도 라우팅 패키지 없이 선택된 메뉴 인덱스로 컨텐츠를 전환한다(사용자 앱
/// 전체의 컨벤션과 동일).
///
/// 폭이 [AdminBreakpoints.sidebar] 미만이면 사이드바가 화면을 차지하지 않도록
/// Drawer로 접고, 상단바의 햄버거 버튼으로 연다. 넓은 화면은 기존과 똑같다 —
/// 사이드바 + 본문 Row 구조와 여백이 그대로다.
class AdminShell extends StatefulWidget {
  final String adminEmail;
  final VoidCallback onSignOut;
  const AdminShell({
    super.key,
    required this.adminEmail,
    required this.onSignOut,
  });

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  /// Drawer를 코드에서 열고 닫기 위한 키(모바일 폭에서만 쓰인다).
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selected = 0;
  // 회원 목록 → 상세로 진입했을 때 사이드바는 "회원 관리"를 유지한 채
  // 컨텐츠 영역만 상세 화면으로 바꾼다.
  String? _selectedMemberUid;
  // 채팅 목록 → 대화 상세도 같은 방식(사이드바는 "채팅 관리" 유지).
  String? _selectedChatRoomId;
  // 사전등록 목록 → 신청 상세도 같은 방식(사이드바는 "호스트 사전등록" 유지).
  String? _selectedPreRegistrationId;

  void _select(int i) {
    setState(() {
      _selected = i;
      _selectedMemberUid = null;
      _selectedChatRoomId = null;
      _selectedPreRegistrationId = null;
    });
  }

  /// 알림 한 건을 열면서 읽음 처리한다.
  ///
  /// 갈 곳이 없는 알림이라도 **읽음 처리는 한다** — 그러지 않으면 그 알림은
  /// 영영 안 읽음으로 남아 배지가 내려가지 않는다(사용자 앱 알림함과 같은 규칙).
  ///
  /// 이동은 기존 상태(_selected / _selectedPreRegistrationId)를 그대로 쓴다 —
  /// 알림 전용 이동 경로를 새로 만들지 않는다.
  void _openNotification(AdminNotification n) {
    if (!n.isReadBy(AdminNotificationService.currentUid)) {
      // Future를 기다리지 않는다 — Firestore가 로컬에 즉시 반영하므로 배지가
      // 그 자리에서 내려가고, 실패하면 저절로 되돌아온다.
      AdminNotificationService.markRead(n.id).catchError((Object e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('읽음 처리를 저장하지 못했습니다.')),
        );
      });
    }

    final target = adminNotificationTarget(n);
    if (target == null) return;
    final index = _menuItems.indexWhere((m) => m.label == target.menuLabel);
    if (index < 0) return;

    setState(() {
      _selected = index;
      _selectedMemberUid = null;
      _selectedChatRoomId = null;
      // 지금은 사전등록만 문서 단위로 연다. 종류가 늘면 target.menuLabel에
      // 따라 해당 화면의 선택 상태를 채우면 된다.
      _selectedPreRegistrationId =
          target.menuLabel == '호스트 사전등록' ? target.documentId : null;
    });
  }

  /// 상단 종의 '전체 알림 보기'.
  void _openAllNotifications() {
    final index = _menuItems.indexWhere((m) => m.label == '알림');
    if (index >= 0) _select(index);
  }

  void _openMember(String uid) {
    setState(() {
      _selected = 1;
      _selectedMemberUid = uid;
    });
  }

  void _backToMemberList() {
    setState(() => _selectedMemberUid = null);
  }

  void _openChatRoom(String roomId) {
    setState(() => _selectedChatRoomId = roomId);
  }

  void _backToChatList() {
    setState(() => _selectedChatRoomId = null);
  }

  Widget _buildContent() {
    switch (_selected) {
      case 0:
        return const DashboardScreen();
      case 1:
        return _selectedMemberUid == null
            ? MembersScreen(onOpenMember: _openMember)
            : MemberDetailScreen(
                uid: _selectedMemberUid!,
                onBack: _backToMemberList,
              );
      case 2:
        return _selectedPreRegistrationId == null
            ? HostPreRegistrationsScreen(
                onOpen: (id) => setState(() => _selectedPreRegistrationId = id),
              )
            : HostPreRegistrationDetailScreen(
                id: _selectedPreRegistrationId!,
                onBack: () => setState(() => _selectedPreRegistrationId = null),
                onOpenMember: _openMember,
              );
      case 3:
        return VerifiedUsersScreen(onOpenMember: _openMember);
      // ⚠ 아래 번호는 _menuItems의 순서와 1:1이다 — 메뉴를 중간에 끼워 넣으면
      // 여기 번호도 함께 밀어야 한다('판매 통계'를 4번에 넣으면서 5~8을 밀었고,
      // '호스트 사전등록'을 2번에 넣으면서 3~11을 밀었다).
      case 4:
        return UsageStatsScreen(onOpenMember: _openMember);
      case 5:
        return SalesStatsScreen(onOpenMember: _openMember);
      case 6:
        return const RefundRequestsScreen();
      case 7:
        return _selectedChatRoomId == null
            ? ChatRoomsScreen(onOpenRoom: _openChatRoom)
            : ChatRoomDetailScreen(
                roomId: _selectedChatRoomId!,
                onBack: _backToChatList,
              );
      case 8:
        return FeedbackRequestsScreen(onOpenMember: _openMember);
      case 9:
        return ReportsScreen(onOpenMember: _openMember);
      case 10:
        return BlockedRelationsScreen(onOpenMember: _openMember);
      case 11:
        return const SystemErrorsScreen();
      case 12:
        return AdminNotificationsScreen(onOpen: _openNotification);
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = context.isMobileLayout;

    // 상단바 + 본문. 모바일에서는 사이드바가 Row에서 빠지므로 본문이 화면
    // 폭을 100% 쓴다.
    final content = Column(
      children: [
        _TopBar(
          adminEmail: widget.adminEmail,
          compact: isMobile,
          onMenu: isMobile ? () => _scaffoldKey.currentState?.openDrawer() : null,
          bell: AdminNotificationBell(
            onOpen: _openNotification,
            onOpenAll: _openAllNotifications,
          ),
          onSignOut: () async {
            await FirebaseAuth.instance.signOut();
            widget.onSignOut();
          },
        ),
        Expanded(
          child: Container(
            color: AdminTheme.pageBg,
            padding: EdgeInsets.all(
              isMobile
                  ? AdminBreakpoints.pagePaddingNarrow
                  : AdminBreakpoints.pagePaddingWide,
            ),
            child: _buildContent(),
          ),
        ),
      ],
    );

    return Scaffold(
      key: _scaffoldKey,
      drawer: isMobile
          ? Drawer(
              width: AdminBreakpoints.sidebarWidth,
              backgroundColor: AdminTheme.sidebarBg,
              child: SafeArea(
                child: _Sidebar(
                  selected: _selected,
                  // Drawer가 폭을 정하므로 사이드바는 스스로 폭을 잡지 않는다.
                  width: null,
                  onSelect: (i) {
                    _select(i);
                    _scaffoldKey.currentState?.closeDrawer();
                  },
                ),
              ),
            )
          : null,
      body: isMobile
          ? content
          : Row(
              children: [
                _Sidebar(selected: _selected, onSelect: _select),
                Expanded(child: content),
              ],
            ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;

  /// 데스크톱 Row에서는 고정 폭(232)을 쓰고, Drawer 안에서는 Drawer가 폭을
  /// 정하므로 null을 넘긴다.
  final double? width;
  const _Sidebar({
    required this.selected,
    required this.onSelect,
    this.width = AdminBreakpoints.sidebarWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      color: AdminTheme.sidebarBg,
      // 화면이 낮거나(가로 모드 휴대폰) 메뉴가 늘어나도 잘리지 않도록
      // 목록 자체를 스크롤 가능하게 둔다.
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'PartyChu Admin',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 28),
          for (var i = 0; i < _menuItems.length; i++)
            if (!_menuItems[i].hidden)
              _SidebarTile(
                item: _menuItems[i],
                isSelected: selected == i,
                onTap: () => onSelect(i),
              ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  final _MenuItem item;
  final bool isSelected;
  final VoidCallback onTap;
  const _SidebarTile({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AdminTheme.accent.withValues(alpha: 0.18) : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              item.icon,
              size: 19,
              color: isSelected ? AdminTheme.accent : AdminTheme.sidebarText,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected ? Colors.white : AdminTheme.sidebarText,
                  fontSize: 13.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String adminEmail;
  final VoidCallback onSignOut;

  /// 모바일 폭에서 Drawer를 여는 햄버거 버튼. 데스크톱에서는 null이라
  /// 버튼 자체가 그려지지 않는다(기존 상단바와 동일).
  final VoidCallback? onMenu;
  final bool compact;

  /// 알림 종. 상단바는 자리만 내주고 상태는 종 위젯이 스스로 구독한다.
  final Widget? bell;
  const _TopBar({
    required this.adminEmail,
    required this.onSignOut,
    this.onMenu,
    this.compact = false,
    this.bell,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: EdgeInsets.only(
        left: onMenu == null ? 24 : 4,
        right: compact ? 4 : 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AdminTheme.cardBorder)),
      ),
      child: Row(
        children: [
          if (onMenu != null) ...[
            IconButton(
              tooltip: '메뉴',
              onPressed: onMenu,
              icon: const Icon(Icons.menu),
            ),
            const Text(
              'PartyChu Admin',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ],
          // 오른쪽 묶음은 남는 폭 안에서만 그린다 — 이메일이 길어도 말줄임으로
          // 접히고 화면 밖으로 밀려나지 않는다.
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // 종은 고정 폭이라 먼저 자리를 잡고, 남는 폭을 이메일이
                // 말줄임으로 나눠 쓴다 — 좁은 화면에서도 밀려나지 않는다.
                ?bell,
                if (!compact) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.person_outline,
                      size: 18, color: AdminTheme.textSecondary),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    adminEmail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AdminTheme.textSecondary,
                    ),
                  ),
                ),
                SizedBox(width: compact ? 2 : 16),
                if (compact)
                  IconButton(
                    tooltip: '로그아웃',
                    onPressed: onSignOut,
                    icon: const Icon(Icons.logout, size: 18),
                  )
                else
                  TextButton.icon(
                    onPressed: onSignOut,
                    icon: const Icon(Icons.logout, size: 16),
                    label: const Text('로그아웃'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

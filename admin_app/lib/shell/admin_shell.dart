import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/dashboard_screen.dart';
import '../screens/member_detail_screen.dart';
import '../screens/members_screen.dart';
import '../screens/system_errors_screen.dart';
import '../screens/usage_stats_screen.dart';
import '../screens/verified_users_screen.dart';
import '../theme/admin_theme.dart';

class _MenuItem {
  final String label;
  final IconData icon;
  const _MenuItem(this.label, this.icon);
}

// "회원 관리"가 통합 회원 목록이다 — 호스트/게스트는 별도 메뉴가 아니라
// 그 화면 안의 활동 유형 필터로 구분한다(members_screen.dart 참고).
const _menuItems = [
  _MenuItem('대시보드', Icons.dashboard_outlined),
  _MenuItem('회원 관리', Icons.people_outline),
  _MenuItem('본인확인 목록', Icons.verified_user_outlined),
  _MenuItem('이용 통계', Icons.insights_outlined),
  _MenuItem('시스템 오류', Icons.error_outline),
];

/// 좌측 고정 사이드바 + 상단바(관리자 이메일/로그아웃) + 중앙 컨텐츠.
/// PC 화면을 우선한 데스크톱 레이아웃 — 별도 라우팅 패키지 없이 선택된
/// 메뉴 인덱스로 컨텐츠를 전환한다(사용자 앱 전체의 컨벤션과 동일).
class AdminShell extends StatefulWidget {
  final String adminEmail;
  final VoidCallback onSignOut;
  const AdminShell({super.key, required this.adminEmail, required this.onSignOut});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _selected = 0;
  // 회원 목록 → 상세로 진입했을 때 사이드바는 "회원 관리"를 유지한 채
  // 컨텐츠 영역만 상세 화면으로 바꾼다.
  String? _selectedMemberUid;

  void _openMember(String uid) {
    setState(() {
      _selected = 1;
      _selectedMemberUid = uid;
    });
  }

  void _backToMemberList() {
    setState(() => _selectedMemberUid = null);
  }

  Widget _buildContent() {
    switch (_selected) {
      case 0:
        return const DashboardScreen();
      case 1:
        return _selectedMemberUid == null
            ? MembersScreen(onOpenMember: _openMember)
            : MemberDetailScreen(uid: _selectedMemberUid!, onBack: _backToMemberList);
      case 2:
        return VerifiedUsersScreen(onOpenMember: _openMember);
      case 3:
        return UsageStatsScreen(onOpenMember: _openMember);
      case 4:
        return const SystemErrorsScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _Sidebar(
            selected: _selected,
            onSelect: (i) => setState(() {
              _selected = i;
              _selectedMemberUid = null;
            }),
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(adminEmail: widget.adminEmail, onSignOut: () async {
                  await FirebaseAuth.instance.signOut();
                  widget.onSignOut();
                }),
                Expanded(
                  child: Container(
                    color: AdminTheme.pageBg,
                    padding: const EdgeInsets.all(28),
                    child: _buildContent(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;
  const _Sidebar({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 232,
      color: AdminTheme.sidebarBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'PartyChu Admin',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 28),
          for (var i = 0; i < _menuItems.length; i++)
            _SidebarTile(
              item: _menuItems[i],
              isSelected: selected == i,
              onTap: () => onSelect(i),
            ),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  final _MenuItem item;
  final bool isSelected;
  final VoidCallback onTap;
  const _SidebarTile({required this.item, required this.isSelected, required this.onTap});

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
            Icon(item.icon, size: 19, color: isSelected ? AdminTheme.accent : AdminTheme.sidebarText),
            const SizedBox(width: 12),
            Text(
              item.label,
              style: TextStyle(
                color: isSelected ? Colors.white : AdminTheme.sidebarText,
                fontSize: 13.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
  const _TopBar({required this.adminEmail, required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AdminTheme.cardBorder)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Icon(Icons.person_outline, size: 18, color: AdminTheme.textSecondary),
          const SizedBox(width: 6),
          Text(adminEmail, style: const TextStyle(fontSize: 13, color: AdminTheme.textSecondary)),
          const SizedBox(width: 16),
          TextButton.icon(
            onPressed: onSignOut,
            icon: const Icon(Icons.logout, size: 16),
            label: const Text('로그아웃'),
          ),
        ],
      ),
    );
  }
}

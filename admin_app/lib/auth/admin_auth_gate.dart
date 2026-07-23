import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../shell/admin_shell.dart';
import '../theme/admin_theme.dart';
import 'admin_login_screen.dart';

/// 로그인 여부 + users/{uid}.role == 'admin' 여부를 확인하는 게이트.
/// 실제 데이터 접근 통제는 Firestore Rules의 isAdmin()이 담당하고, 이 게이트는
/// 관리자가 아닌 사용자에게 빈 화면 대신 명확한 차단 메시지를 보여주는 역할만 한다.
class AdminAuthGate extends StatefulWidget {
  const AdminAuthGate({super.key});

  @override
  State<AdminAuthGate> createState() => _AdminAuthGateState();
}

class _AdminAuthGateState extends State<AdminAuthGate> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _LoadingScaffold();
        }
        final user = snap.data;
        if (user == null) {
          return AdminLoginScreen(onLoginSuccess: () => setState(() {}));
        }
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const _LoadingScaffold();
            }
            final role = userSnap.data?.data()?['role'] as String?;
            if (role != 'admin') {
              return _NotAdminScreen(onSignOut: () => setState(() {}));
            }
            return AdminShell(adminEmail: user.email ?? '', onSignOut: () => setState(() {}));
          },
        );
      },
    );
  }
}

class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AdminTheme.pageBg,
      body: Center(child: CircularProgressIndicator(color: AdminTheme.accent)),
    );
  }
}

class _NotAdminScreen extends StatelessWidget {
  final VoidCallback onSignOut;
  const _NotAdminScreen({required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminTheme.pageBg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 48, color: Colors.black38),
            const SizedBox(height: 16),
            const Text('관리자 권한이 없는 계정입니다.',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                onSignOut();
              },
              child: const Text('로그아웃'),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:party_app/admin/admin_login_screen.dart';
import 'package:party_app/admin/admin_feedback_dashboard.dart';

/// PartyChu 관리자 웹 앱 진입점.
/// 일반 모바일 앱(main.dart의 MyApp)과 완전히 분리된 별도 위젯 트리 —
/// 로그인 + role=='admin' 확인을 통과해야 대시보드에 접근할 수 있다.
/// (Firestore Rules에서도 동일하게 isAdmin()을 강제하므로, 이 게이트는
///  UX 편의를 위한 것일 뿐 실제 데이터 접근 통제는 Rules가 담당한다)
class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PartyChu Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFFFF6FA0),
        useMaterial3: true,
      ),
      home: const _AdminAuthGate(),
    );
  }
}

class _AdminAuthGate extends StatefulWidget {
  const _AdminAuthGate();

  @override
  State<_AdminAuthGate> createState() => _AdminAuthGateState();
}

class _NotAdminScreen extends StatelessWidget {
  final VoidCallback onSignOut;
  const _NotAdminScreen({required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F8),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 48, color: Colors.black38),
            const SizedBox(height: 16),
            const Text(
              '관리자 권한이 없는 계정입니다.',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                onSignOut();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6FA0),
                foregroundColor: Colors.white,
              ),
              child: const Text('로그아웃'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminAuthGateState extends State<_AdminAuthGate> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6FA0)),
            ),
          );
        }
        final user = snap.data;
        if (user == null) {
          return AdminLoginScreen(onLoginSuccess: () => setState(() {}));
        }
        // 로그인은 되어 있으나 role 확인이 필요 — FutureBuilder로 한 번 더 체크
        // (AdminLoginScreen에서 이미 확인하지만, 새로고침으로 세션이 복원된
        //  경우를 위해 여기서도 재확인한다)
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get(),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(color: Color(0xFFFF6FA0)),
                ),
              );
            }
            final role = userSnap.data?.data()?['role'] as String?;
            if (role != 'admin') {
              return _NotAdminScreen(onSignOut: () => setState(() {}));
            }
            return AdminFeedbackDashboard(onSignOut: () => setState(() {}));
          },
        );
      },
    );
  }
}

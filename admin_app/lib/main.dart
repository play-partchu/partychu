import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'auth/admin_auth_gate.dart';
import 'firebase_options.dart';
import 'theme/admin_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PartyChu Admin',
      debugShowCheckedModeBanner: false,
      theme: AdminTheme.data,
      home: const AdminAuthGate(),
    );
  }
}

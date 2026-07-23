import 'package:flutter/material.dart';

import '../theme/admin_theme.dart';

/// 대시보드 숫자 카드 — 차트 대신 숫자와 라벨 위주로 정보 밀도를 우선한다.
class StatCard extends StatelessWidget {
  final String label;
  final Future<int> future;
  final String? caption;

  const StatCard({super.key, required this.label, required this.future, this.caption});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5, color: AdminTheme.textSecondary)),
          const SizedBox(height: 10),
          FutureBuilder<int>(
            future: future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AdminTheme.accent),
                );
              }
              if (snap.hasError) {
                return const Text('오류', style: TextStyle(color: Colors.redAccent, fontSize: 13));
              }
              return Text(
                '${snap.data ?? 0}',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AdminTheme.textPrimary),
              );
            },
          ),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(caption!, style: const TextStyle(fontSize: 11, color: AdminTheme.textSecondary)),
          ],
        ],
      ),
    );
  }
}

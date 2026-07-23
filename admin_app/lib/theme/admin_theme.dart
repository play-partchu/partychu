import 'package:flutter/material.dart';

/// 관리자 웹 전용 테마 — 사용자 앱의 핑크(#FF6FA0)는 포인트로만 쓰고,
/// 바탕은 데이터 밀도가 높은 표/목록을 읽기 편한 중립 톤으로 둔다.
class AdminTheme {
  AdminTheme._();

  static const accent = Color(0xFFFF6FA0);
  static const accentLight = Color(0xFFFFE4ED);
  static const sidebarBg = Color(0xFF1F2430);
  static const sidebarText = Color(0xFFB7BDCC);
  static const pageBg = Color(0xFFF5F6FA);
  static const cardBorder = Color(0xFFE4E7EF);
  static const textPrimary = Color(0xFF1F2430);
  static const textSecondary = Color(0xFF6B7280);

  static ThemeData get data => ThemeData(
        useMaterial3: true,
        colorSchemeSeed: accent,
        scaffoldBackgroundColor: pageBg,
        textTheme: const TextTheme(bodyMedium: TextStyle(color: textPrimary)),
        dataTableTheme: const DataTableThemeData(
          headingRowColor: WidgetStatePropertyAll(Color(0xFFF9FAFC)),
          dataRowMinHeight: 48,
          dataRowMaxHeight: 56,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: cardBorder),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: cardBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: cardBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: accent, width: 1.4),
          ),
        ),
      );
}

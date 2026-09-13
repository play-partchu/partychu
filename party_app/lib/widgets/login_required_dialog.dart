import 'package:flutter/material.dart';

/// 비로그인 상태에서 로그인이 필요한 동작(찜 등)을 시도했을 때 띄우는 안내
/// 다이얼로그. "로그인하기"를 누르면 true, "취소"를 누르면 false를 반환한다.
/// 실제 로그인 화면으로의 이동/재시도는 호출부에서 처리한다 —
/// 이 다이얼로그는 안내와 사용자 선택만 담당한다.
Future<bool> showLoginRequiredDialog(
  BuildContext context, {
  String message = '로그인이 필요합니다.',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text(
        '로그인이 필요해요',
        style: TextStyle(
          fontFamily: 'SeoulHangang',
          fontSize: 16,
          fontWeight: FontWeight.w500,
          shadows: [
            Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
            Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
            Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
            Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
          ],
        ),
      ),
      content: Text(
        message,
        style: const TextStyle(fontSize: 14, color: Colors.black87),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF6FA0),
            foregroundColor: Colors.white,
          ),
          child: const Text('로그인하기'),
        ),
      ],
    ),
  );
  return result ?? false;
}

import 'package:flutter/material.dart';

/// 알림 권한을 요청하기 **전에** 보여주는 파티츄 자체 안내.
///
/// OS 권한 팝업은 사용자당 사실상 한 번뿐이다 — 한 번 거부되면 Android 13+
/// 에서는 두 번째 거부부터 "다시 묻지 않음"으로 굳어 앱에서 다시 띄울 수
/// 없다. 그래서 팝업을 바로 소모하지 않고, **왜 필요한지 납득한 사람만**
/// OS 팝업으로 넘긴다.
///
/// 여기서 '나중에'를 눌러도 OS 팝업은 뜨지 않으므로 권한은 아직 살아 있다 —
/// 다음 기회(다른 진입점)에 다시 물어볼 수 있다.
class PushPermissionSheet extends StatelessWidget {
  const PushPermissionSheet({
    super.key,
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  /// 사용자가 '알림 켜기'를 눌렀으면 true.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => PushPermissionSheet(title: title, message: message),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFE0EE),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.notifications_active_outlined,
                  size: 30,
                  color: Color(0xFFFF6FA0),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                color: Colors.black54,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6FA0),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                '알림 켜기',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(
                '나중에',
                style: TextStyle(fontSize: 13.5, color: Colors.black45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 시스템 설정에서 알림이 꺼져 있을 때 보여주는 안내.
///
/// 이 상태에서는 OS 팝업을 다시 띄울 수 없으므로 **설정앱으로 보내는 것 말고는
/// 방법이 없다.** 팝업을 반복해서 시도하면 아무 일도 일어나지 않아 사용자는
/// "버튼이 고장났다"고 느낀다.
class PushBlockedSheet extends StatelessWidget {
  const PushBlockedSheet({super.key, required this.message});

  final String message;

  /// 사용자가 '설정에서 알림 켜기'를 눌렀으면 true.
  static Future<bool> show(BuildContext context, {required String message}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => PushBlockedSheet(message: message),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Color(0xFFF1F2F5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.notifications_off_outlined,
                  size: 30,
                  color: Colors.black38,
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '기기 알림이 꺼져 있어요',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                color: Colors.black54,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6FA0),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                '설정에서 알림 켜기',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(
                '닫기',
                style: TextStyle(fontSize: 13.5, color: Colors.black45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

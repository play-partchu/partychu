// ─────────────────────────────────────────────────────────────────────────────
// 지난 파티 · 지난 이벤트 목록에 들어갈 때 뜨는 **자동 삭제 안내**.
//
// 끝난 등록물은 종료일로부터 14일 뒤에 서버가 실제로 지운다
// ([AutoDeleteRetention.window] / functions의 deleteExpiredParties ·
// deleteExpiredPromotions). 목록에 남아 있는 동안 호스트는 그것이 "보관 중"인지
// "곧 사라지는 것"인지 알 수 없어서, 지난 목록을 **여는 순간** 한 번 말한다.
//
// ── 파티와 이벤트를 따로 기억하지 않는다 ─────────────────────────────────────
// 문구가 같고(보관기간도 같다) 하려는 말도 하나다 — "끝난 것은 14일 뒤 사라진다".
// 유형별로 따로 기억하면 같은 안내를 이틀 사이에 두 번 보게 된다. 그래서 유예도
// 하나로 묶는다.
//
// ── 유예는 계정마다 따로 ─────────────────────────────────────────────────────
// 열쇠에 uid가 들어간다. 한 기기를 여럿이 쓰는 경우(호스트 계정 + 개인 계정)
// 한 사람이 누른 '3일간 보지 않기'가 다른 사람에게까지 적용되면 안 된다.
// 로그인 전에는 지난 목록 자체가 없으므로 uid가 빈 경우는 그냥 띄운다.
//
// 저장은 [SharedPreferences] — 알림 권한 안내(PushPermissionGate)가 쓰는 것과
// 같은 방식이다. 서버에 둘 값이 아니다(기기별 UX 설정).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:party_app/utils/auto_delete_retention.dart';
import 'package:party_app/utils/user_session.dart';

/// 안내가 말하는 대상 — 문구의 한 낱말만 갈린다.
enum PastContentKind {
  party('파티'),
  event('이벤트');

  const PastContentKind(this.label);

  final String label;
}

class PastContentRetentionNotice {
  PastContentRetentionNotice._();

  /// '3일간 다시 보지 않기'의 유예 — 72시간.
  static const Duration snooze = Duration(days: 3);

  static const String _keyPrefix = 'past_content_retention_snoozed_until_';

  static String _keyFor(String uid) => '$_keyPrefix$uid';

  /// 같은 진입에서 두 번 뜨지 않게 하는 잠금. 탭을 빠르게 오가면 안내가
  /// 겹쳐 쌓일 수 있다(PushPermissionGate가 같은 이유로 쓰는 장치).
  static bool _showing = false;

  /// 지금 안내를 띄워야 하는가 — 유예 중이면 false.
  @visibleForTesting
  static Future<bool> shouldShow({DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final until = prefs.getInt(_keyFor(UserSession.userId)) ?? 0;
      return (now ?? DateTime.now()).millisecondsSinceEpoch >= until;
    } catch (_) {
      // 설정을 못 읽으면 띄운다 — 안내가 한 번 더 뜨는 쪽이,
      // 삭제 예정을 아무도 모르는 쪽보다 낫다.
      return true;
    }
  }

  /// 지금부터 [snooze] 동안 띄우지 않는다.
  @visibleForTesting
  static Future<void> snoozeNow({DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final until = (now ?? DateTime.now()).add(snooze);
      await prefs.setInt(
        _keyFor(UserSession.userId),
        until.millisecondsSinceEpoch,
      );
    } catch (_) {
      // 저장에 실패하면 다음에 다시 뜬다 — 그뿐이다.
    }
  }

  /// 지난 목록에 들어왔을 때 부른다. 유예 중이면 아무 일도 하지 않는다.
  ///
  /// 화면을 막지 않는다(await 하지 않아도 된다) — 목록은 그대로 그려지고
  /// 안내만 그 위에 뜬다.
  static Future<void> maybeShow(
    BuildContext context,
    PastContentKind kind,
  ) async {
    if (_showing) return;
    if (!await shouldShow()) return;
    if (!context.mounted) return;

    _showing = true;
    try {
      final days = AutoDeleteRetention.window.inDays;
      final again = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            '자동 삭제 안내',
            style: TextStyle(
              fontFamily: 'SeoulHangang',
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
            // 보관기간 숫자는 [AutoDeleteRetention.window] 하나가 정본이다 —
            // 문구에 직접 적으면 정책이 바뀔 때 안내만 옛날 값으로 남는다.
            '종료된 ${kind.label}는 종료일로부터 $days일 후 자동으로 삭제돼요.\n'
            '계속 운영하시려면 삭제되기 전에 진행 중 상태로 바꾸거나 '
            '다시 등록해주세요.\n\n'
            '결제·정산 기록은 ${kind.label}가 삭제돼도 그대로 남아요.',
            style: const TextStyle(height: 1.5),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(
                '3일간 다시 보지 않기',
                style: TextStyle(color: Colors.black45),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                '확인',
                style: TextStyle(color: Color(0xFFFF6FA0)),
              ),
            ),
          ],
        ),
      );
      // 다이얼로그를 그냥 닫은 경우(null)는 '확인'과 같게 본다 — 유예는
      // 사용자가 **명시적으로 고를 때만** 걸린다.
      if (again == false) await snoozeNow();
    } finally {
      _showing = false;
    }
  }
}

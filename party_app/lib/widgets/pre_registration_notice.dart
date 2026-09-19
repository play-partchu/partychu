// ─────────────────────────────────────────────────────────────────────────────
// 앱을 켜고 메인 화면에 들어왔을 때 뜨는 **사전등록 기간 안내**.
//
// ── 언제 뜨는가 ──────────────────────────────────────────────────────────────
// [MainScreen]이 첫 프레임을 그린 뒤 부른다. MainScreen은 루트 게이트
// (utils/root_gate.dart)를 통과해야만 만들어지므로, 본인확인·탈퇴 대기 화면
// 위에는 뜨지 않는다. 비로그인 둘러보기에도 뜬다 — 안내는 기기 단위다.
//
// 업데이트 안내([AppUpdateGate])가 먼저다. 그 확인과 다이얼로그가 끝난 뒤에
// 띄워 두 팝업이 겹쳐 쌓이지 않게 한다(필수 업데이트면 아예 뜨지 않는다).
//
// 앱 실행 한 번에 한 번만 — 루트 게이트를 오가며 MainScreen이 다시 만들어져도
// 같은 실행 안에서 또 뜨지 않는다.
//
// ── 오늘은 그만 보기 ─────────────────────────────────────────────────────────
// 누른 날의 **기기 로컬 날짜**(yyyy-MM-dd)를 [SharedPreferences]에 남긴다.
// 저장된 날짜가 오늘이면 띄우지 않고, 날짜가 바뀌면 다시 뜬다. 서버에 둘 값이
// 아니다(기기별 UX 설정 — [PastContentRetentionNotice]와 같은 방식).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:party_app/widgets/app_update_gate.dart';
import 'package:party_app/widgets/partychu_ui.dart';

class PreRegistrationNotice {
  PreRegistrationNotice._();

  static const String _hiddenDateKey = 'pre_registration_notice_hidden_date';

  /// 이번 실행에서 이미 띄웠는가.
  static bool _shownThisLaunch = false;

  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// 오늘 띄워야 하는가 — '오늘은 그만 보기'를 오늘 눌렀으면 false.
  @visibleForTesting
  static Future<bool> shouldShow({DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_hiddenDateKey) != _dayKey(now ?? DateTime.now());
    } catch (_) {
      // 설정을 못 읽으면 띄운다 — 한 번 더 보는 쪽이 낫다.
      return true;
    }
  }

  /// 오늘 하루 띄우지 않는다.
  @visibleForTesting
  static Future<void> hideToday({DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_hiddenDateKey, _dayKey(now ?? DateTime.now()));
    } catch (_) {
      // 저장에 실패하면 다음 실행 때 다시 뜬다 — 그뿐이다.
    }
  }

  @visibleForTesting
  static void resetForTest() => _shownThisLaunch = false;

  /// 메인 화면 진입 시 부른다. 조건이 안 맞으면 아무 일도 하지 않는다.
  /// 화면을 막지 않으므로 await 하지 않아도 된다.
  static Future<void> maybeShow(BuildContext context) async {
    if (_shownThisLaunch) return;
    _shownThisLaunch = true;

    await AppUpdateGate.settled;
    if (!await shouldShow()) return;
    if (!context.mounted) return;

    final hide = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => const _PreRegistrationDialog(),
    );
    // 바깥을 눌러 닫은 경우(null)는 '확인'과 같게 본다 — 하루 숨김은
    // 사용자가 명시적으로 고를 때만 걸린다.
    if (hide == true) await hideToday();
  }
}

class _PreRegistrationDialog extends StatelessWidget {
  const _PreRegistrationDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: PartyChuColors.primary.withValues(alpha: 0.13),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.celebration_rounded,
                  size: 32,
                  color: PartyChuColors.primary,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '파티츄 사전등록 기간입니다!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: PartyChuColors.heading,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '현재 등록하신 매장과 콘텐츠는 사전등록 기간 동안 다른 호스트에게 '
                '공개되지 않으며, 정식 오픈에 맞춰 공개될 예정입니다.\n\n'
                '등록 중 필요한 옵션이나 불편한 점이 있다면 스크린샷과 함께 '
                '마이 > 고객센터 문의로 보내주세요. 확인 후 빠르게 반영하겠습니다.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.6,
                  color: PartyChuColors.subtleText,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: FilledButton.styleFrom(
                    backgroundColor: PartyChuColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    '확인',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(
                  foregroundColor: PartyChuColors.muted,
                ),
                child: const Text(
                  '오늘은 그만 보기',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

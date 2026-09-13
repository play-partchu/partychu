import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:party_app/services/push_notification_service.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/push_permission_sheet.dart';

/// 알림 권한을 물어보는 **맥락**. 문구가 달라지고, 조르기 규칙도 달라진다.
enum PushPromptReason {
  /// 채팅 최초 진입 — 답장을 놓치는 게 가장 아까운 자리다.
  chat,

  /// 예약·파티 신청을 막 마친 직후 — 승인/입금 안내를 놓치면 안 되는 자리다.
  booking,

  /// 마이페이지 > 알림 설정 — 사용자가 스스로 켜러 온 자리.
  settings,
}

extension _ReasonCopy on PushPromptReason {
  String get title => switch (this) {
    PushPromptReason.chat => '답장을 놓치지 않도록 알림을 켤까요?',
    PushPromptReason.booking => '예약 소식을 바로 받아보시겠어요?',
    PushPromptReason.settings => '알림을 켤까요?',
  };

  String get message => switch (this) {
    PushPromptReason.chat => '채팅 메시지와 예약 알림을 놓치지 않도록\n알림을 허용해주세요.',
    PushPromptReason.booking => '승인·입금 확인·일정 시작 같은 중요한 소식을\n제때 알려드릴게요.',
    PushPromptReason.settings => '채팅 메시지와 예약 알림을 놓치지 않도록\n알림을 허용해주세요.',
  };

  String get blockedMessage => switch (this) {
    PushPromptReason.chat => '기기 설정에서 파티츄 알림이 꺼져 있어\n새 메시지를 알려드릴 수 없어요.',
    PushPromptReason.booking => '기기 설정에서 파티츄 알림이 꺼져 있어\n예약 소식을 알려드릴 수 없어요.',
    PushPromptReason.settings => '앱 안에서 알림을 켜도 기기 설정이 꺼져 있으면\n알림이 오지 않아요.',
  };

  /// 사용자가 '나중에'를 눌렀을 때 다시 묻기까지 기다리는 기간.
  /// 설정 화면은 사용자가 스스로 온 자리라 조르기 규칙을 적용하지 않는다.
  Duration? get snooze => switch (this) {
    PushPromptReason.chat => const Duration(days: 7),
    PushPromptReason.booking => const Duration(days: 3),
    PushPromptReason.settings => null,
  };
}

/// "알림이 왜 필요한지 아는 시점"에만 권한을 요청하기 위한 관문.
///
/// ── 이 관문이 지키는 것 ────────────────────────────────────────────────
/// 1. 앱 첫 실행/로그인 직후에는 **절대 묻지 않는다.** 맥락 없는 팝업은 그냥
///    거부로 소모되고, 그 뒤로는 앱에서 다시 띄울 수 없다.
/// 2. 이미 차단된(blocked) 상태에서는 OS 팝업을 시도조차 하지 않는다 —
///    팝업이 뜨지 않아 사용자에게는 "눌러도 아무 일이 없는 버튼"이 된다.
///    대신 설정앱으로 보낸다.
/// 3. '나중에'를 누른 사람에게 매번 다시 묻지 않는다(진입점별 유예 기간).
/// 4. **안내는 화면에 한 번에 하나만, 지금 보고 있는 화면 위에만 뜬다.**
///    이 두 가지가 없으면 시트가 겹쳐 쌓여 "닫아도 계속 다시 뜨는" 화면이
///    된다 — 아래 [_prompting]·[_shownThisRun] 주석 참고.
class PushPermissionGate {
  PushPermissionGate._();

  static const _snoozeKeyPrefix = 'push_prompt_snoozed_until_';

  /// 진입점을 가리지 않는 공통 유예. 진입점별 유예만 두면 채팅에서 '나중에'를
  /// 누른 사람이 곧바로 파티를 신청했을 때 **같은 안내가 몇 초 만에 다시**
  /// 뜬다 — 거절 의사를 방금 밝힌 사람에게 자리만 바꿔 또 묻는 꼴이다.
  /// 진입점별 유예(7일·3일)는 그대로 두고, 그보다 짧은 이 유예를 함께 건다.
  static const _quietKey = 'push_prompt_quiet_until';
  static const _quietPeriod = Duration(hours: 24);

  /// 지금 안내가 하나 떠 있는가.
  ///
  /// 진입점이 여럿이고 모두 `await` 없이(화면을 막지 않으려고) 부르기 때문에,
  /// 두 진입이 겹치는 순간이 실제로 있다 — 채팅방에 들어간 직후 알림을 눌러
  /// 다른 방으로 이동하거나, 신청 직후 안내와 채팅 진입 안내가 맞물리는 경우다.
  /// 그러면 시트가 **라우트로 겹겹이 쌓이고**, 사용자는 뒤로가기로 한 겹을
  /// 걷어낼 때마다 아래에 있던 시트가 다시 올라오는 걸 본다 — "뒤로가기를
  /// 누르면 바텀시트가 계속 다시 나타나 화면을 빠져나갈 수 없다"의 정체다.
  /// 그래서 안내는 **동시에 하나만** 띄운다.
  static bool _prompting = false;

  /// 이번 실행에서 이미 안내를 보여준 진입점.
  ///
  /// 유예는 SharedPreferences에 쓰이므로 기록이 남기까지 시차가 있고,
  /// blocked 분기는 애초에 유예를 걸 자리가 아니었다(설정앱에서 켜고 오면
  /// 사라질 상태라고 보고 아무 기록도 남기지 않았다). 그 탓에 같은 실행 안에서
  /// 화면을 드나들 때마다 같은 안내가 다시 떴다. 저장소와 무관하게 **앱을 켠
  /// 동안 진입점당 한 번**으로 묶는다. 사용자가 직접 누른 경우(force)는 예외다.
  static final _shownThisRun = <PushPromptReason>{};

  static Future<bool> _isSnoozed(PushPromptReason reason) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;

    if (now < (prefs.getInt(_quietKey) ?? 0)) return true;

    final snooze = reason.snooze;
    if (snooze == null) return false;
    final until = prefs.getInt('$_snoozeKeyPrefix${reason.name}') ?? 0;
    return now < until;
  }

  static Future<void> _snooze(PushPromptReason reason) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();

    // 공통 유예는 설정 화면에서 물러난 경우에도 건다. 사용자가 방금 거절했다는
    // 사실 자체는 진입점과 무관하기 때문이다.
    await prefs.setInt(_quietKey, now.add(_quietPeriod).millisecondsSinceEpoch);

    final snooze = reason.snooze;
    if (snooze == null) return;
    await prefs.setInt(
      '$_snoozeKeyPrefix${reason.name}',
      now.add(snooze).millisecondsSinceEpoch,
    );
  }

  /// 안내를 띄워도 되는 자리인가 — **부른 화면이 지금 맨 위에 있을 때만.**
  ///
  /// 권한 상태를 읽는 동안(비동기) 사용자는 이미 다른 화면으로 넘어갔을 수
  /// 있다. 그때 시트를 띄우면 사용자가 보지도 않은 라우트 위에 얹혀 있다가
  /// **뒤로가기로 그 화면에 돌아오는 순간 튀어나온다.** 화면이 아직 살아있는지
  /// (mounted)만 보면 이 경우를 못 걸러낸다.
  static bool _isVisible(BuildContext context) {
    if (!context.mounted) return false;
    final route = ModalRoute.of(context);
    // 라우트를 못 찾으면(테스트용 트리 등) 막지 않는다 — 판단 근거가 없을 뿐
    // 화면이 가려졌다는 뜻은 아니다.
    return route == null || route.isCurrent;
  }

  /// 권한이 없으면 맥락에 맞는 안내를 띄우고, 동의하면 OS 팝업까지 이어간다.
  ///
  /// [force]가 true면 유예 기간과 '이번 실행 1회' 제한을 무시한다(사용자가
  /// 직접 '알림 켜기'를 누른 설정 화면에서 쓴다).
  ///
  /// 반환값은 **최종적으로 알림을 받을 수 있는 상태인지**다.
  static Future<bool> ensure(
    BuildContext context,
    PushPromptReason reason, {
    bool force = false,
  }) async {
    // 로그인하지 않았으면 등록할 계정이 없다 — 물어봐야 의미가 없다.
    if (UserSession.userId.isEmpty) return false;

    // 웹에서는 푸시를 등록하지 않는다([PushNotificationService]의 진입점들이
    // 전부 kIsWeb에서 곧장 빠져나온다). 안내만 띄우면 브라우저 알림 권한을
    // 받아도 갈 곳이 없으므로 여기서 끝낸다.
    if (kIsWeb) return false;

    // 상태는 **언제나 OS에 직접 묻는다.** 앱이 들고 있는 값으로 판단하면,
    // 설정앱에서 방금 알림을 켜고 돌아온 사람에게 "알림을 켤까요?"를 다시
    // 띄우게 된다(currentState는 permission_handler + FCM 설정을 그때그때
    // 읽는다 — 캐시가 없다).
    var state = await PushNotificationService.currentState();
    if (state.isGranted) {
      // 이미 허용된 상태인데 토큰이 아직 없을 수 있다(권한만 먼저 켠 경우).
      await PushNotificationService.registerForUser();
      return true;
    }

    // 안내가 이미 하나 떠 있으면 두 번째는 띄우지 않는다(겹쳐 쌓이면 하나를
    // 닫아도 아래에서 또 나온다).
    if (_prompting) return false;
    if (!force && _shownThisRun.contains(reason)) return false;
    if (!force && await _isSnoozed(reason)) return false;
    if (!context.mounted || !_isVisible(context)) return false;

    _prompting = true;
    _shownThisRun.add(reason);
    try {
      // ── 시스템에서 꺼둔 경우: 팝업 대신 설정앱으로 ────────────────────
      if (state.needsSettings) {
        final go = await PushBlockedSheet.show(
          context,
          message: reason.blockedMessage,
        );
        // 닫았든 설정앱으로 갔든 유예를 건다. 예전에는 이 분기만 아무 기록도
        // 남기지 않아, 기기 알림이 꺼진 사용자는 **채팅방에 들어갈 때마다**
        // 같은 안내를 다시 봤다. 설정에서 켜고 오면 위 isGranted에서 걸러지므로
        // 유예가 걸려도 켠 사람에게 손해가 없다.
        await _snooze(reason);
        if (go) await PushNotificationService.openSettings();
        return false;
      }

      // ── 사전 안내 → OS 팝업 ──────────────────────────────────────────
      final agreed = await PushPermissionSheet.show(
        context,
        title: reason.title,
        message: reason.message,
      );
      // '나중에'(또는 시트를 그냥 닫음) — 시트만 닫고 끝낸다. 여기서 아무것도
      // 더 띄우지 않으므로 사용자는 곧바로 화면을 계속 쓸 수 있다.
      if (!agreed) {
        await _snooze(reason);
        return false;
      }

      state = await PushNotificationService.requestPermission();
      // 허용 여부는 OS 팝업의 반환값이 아니라 **권한 상태를 다시 읽어** 판단한다
      // (requestPermission이 currentState를 다시 읽어 돌려준다). 허용됐다면
      // 여기서 끝 — 시트는 이미 닫혔고 다시 띄우지 않는다.
      if (state.isGranted) {
        await PushNotificationService.registerForUser();
        return true;
      }

      // 여기서 거부됐다면 다음 기회를 위해 유예만 걸어둔다. Android 13+ 는
      // 두 번째 거부부터 blocked로 굳으므로, 그 뒤로는 위 needsSettings 분기가
      // 받아 설정앱으로 안내한다.
      await _snooze(reason);
      return false;
    } finally {
      _prompting = false;
    }
  }
}

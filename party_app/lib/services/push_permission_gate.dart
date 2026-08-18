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
    PushPromptReason.chat =>
      '채팅 메시지와 예약 알림을 놓치지 않도록\n알림을 허용해주세요.',
    PushPromptReason.booking =>
      '승인·입금 확인·일정 시작 같은 중요한 소식을\n제때 알려드릴게요.',
    PushPromptReason.settings =>
      '채팅 메시지와 예약 알림을 놓치지 않도록\n알림을 허용해주세요.',
  };

  String get blockedMessage => switch (this) {
    PushPromptReason.chat =>
      '기기 설정에서 파티츄 알림이 꺼져 있어\n새 메시지를 알려드릴 수 없어요.',
    PushPromptReason.booking =>
      '기기 설정에서 파티츄 알림이 꺼져 있어\n예약 소식을 알려드릴 수 없어요.',
    PushPromptReason.settings =>
      '앱 안에서 알림을 켜도 기기 설정이 꺼져 있으면\n알림이 오지 않아요.',
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
class PushPermissionGate {
  PushPermissionGate._();

  static const _snoozeKeyPrefix = 'push_prompt_snoozed_until_';

  /// 진입점을 가리지 않는 공통 유예. 진입점별 유예만 두면 채팅에서 '나중에'를
  /// 누른 사람이 곧바로 파티를 신청했을 때 **같은 안내가 몇 초 만에 다시**
  /// 뜬다 — 거절 의사를 방금 밝힌 사람에게 자리만 바꿔 또 묻는 꼴이다.
  /// 진입점별 유예(7일·3일)는 그대로 두고, 그보다 짧은 이 유예를 함께 건다.
  static const _quietKey = 'push_prompt_quiet_until';
  static const _quietPeriod = Duration(hours: 24);

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
    await prefs.setInt(
      _quietKey,
      now.add(_quietPeriod).millisecondsSinceEpoch,
    );

    final snooze = reason.snooze;
    if (snooze == null) return;
    await prefs.setInt(
      '$_snoozeKeyPrefix${reason.name}',
      now.add(snooze).millisecondsSinceEpoch,
    );
  }

  /// 권한이 없으면 맥락에 맞는 안내를 띄우고, 동의하면 OS 팝업까지 이어간다.
  ///
  /// [force]가 true면 유예 기간을 무시한다(사용자가 직접 '알림 켜기'를 누른
  /// 설정 화면에서 쓴다).
  ///
  /// 반환값은 **최종적으로 알림을 받을 수 있는 상태인지**다.
  static Future<bool> ensure(
    BuildContext context,
    PushPromptReason reason, {
    bool force = false,
  }) async {
    // 로그인하지 않았으면 등록할 계정이 없다 — 물어봐야 의미가 없다.
    if (UserSession.userId.isEmpty) return false;

    var state = await PushNotificationService.currentState();
    if (state.isGranted) {
      // 이미 허용된 상태인데 토큰이 아직 없을 수 있다(권한만 먼저 켠 경우).
      await PushNotificationService.registerForUser();
      return true;
    }

    if (!context.mounted) return false;

    // ── 시스템에서 꺼둔 경우: 팝업 대신 설정앱으로 ──────────────────────
    if (state.needsSettings) {
      final go = await PushBlockedSheet.show(
        context,
        message: reason.blockedMessage,
      );
      if (go) await PushNotificationService.openSettings();
      return false;
    }

    if (!force && await _isSnoozed(reason)) return false;
    if (!context.mounted) return false;

    // ── 사전 안내 → OS 팝업 ────────────────────────────────────────────
    final agreed = await PushPermissionSheet.show(
      context,
      title: reason.title,
      message: reason.message,
    );
    if (!agreed) {
      await _snooze(reason);
      return false;
    }

    state = await PushNotificationService.requestPermission();
    if (state.isGranted) {
      await PushNotificationService.registerForUser();
      return true;
    }

    // 여기서 거부됐다면 다음 기회를 위해 유예만 걸어둔다. Android 13+ 는
    // 두 번째 거부부터 blocked로 굳으므로, 그 뒤로는 위 needsSettings 분기가
    // 받아 설정앱으로 안내한다.
    await _snooze(reason);
    return false;
  }
}

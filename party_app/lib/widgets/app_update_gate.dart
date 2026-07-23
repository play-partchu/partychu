import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:party_app/services/app_update_service.dart';

const _kDismissedVersionPrefsKey = 'app_update_dismissed_version';

/// 앱 실행 시 한 번, 최신 버전을 확인해 필요하면 업데이트 안내/강제 다이얼로그를
/// 띄우는 래퍼. 로그인 여부와 무관하게(로그인 화면이든 메인 화면이든) 항상
/// 동작해야 하므로 MaterialApp의 home 최상단에서 감싼다.
class AppUpdateGate extends StatefulWidget {
  final Widget child;
  const AppUpdateGate({super.key, required this.child});

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runCheck());
  }

  Future<void> _runCheck() async {
    final info = await AppUpdateService.check();
    if (!mounted) return;

    if (info.status == AppUpdateStatus.force) {
      _showDialog(info, dismissible: false);
      return;
    }

    if (info.status == AppUpdateStatus.optional) {
      final prefs = await SharedPreferences.getInstance();
      final dismissedVersion = prefs.getString(_kDismissedVersionPrefsKey);
      // 이미 "나중에"로 넘긴 버전이면, latestVersion이 그 사이에 더 올라가지
      // 않은 한 매번 재실행 때마다 다시 띄우지 않는다.
      if (dismissedVersion == info.latestVersion) return;
      if (!mounted) return;
      _showDialog(info, dismissible: true);
    }
  }

  void _showDialog(AppUpdateInfo info, {required bool dismissible}) {
    showDialog<void>(
      context: context,
      barrierDismissible: dismissible,
      builder: (dialogContext) => PopScope(
        canPop: dismissible,
        child: _UpdateDialogContent(info: info, dismissible: dismissible),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 다이얼로그 본문을 별도 StatefulWidget으로 분리한 이유:
/// "지금 업데이트"/"업데이트" 버튼을 누른 동안 로딩 표시 + 중복 탭 방지가
/// 필요하고, storeUrl이 비어있거나(앱 출시 전) 스토어를 열지 못하는 경우
/// 오류/무한 로딩 대신 안내 메시지로 명확히 종료되어야 하기 때문이다.
class _UpdateDialogContent extends StatefulWidget {
  final AppUpdateInfo info;
  final bool dismissible;
  const _UpdateDialogContent({required this.info, required this.dismissible});

  @override
  State<_UpdateDialogContent> createState() => _UpdateDialogContentState();
}

class _UpdateDialogContentState extends State<_UpdateDialogContent> {
  bool _opening = false;

  Future<void> _handleUpdateTap() async {
    if (_opening) return; // 중복 탭 방지
    setState(() => _opening = true);

    final storeUrl = widget.info.storeUrl.trim();
    var opened = false;
    String? failureMessage;

    if (storeUrl.isEmpty) {
      failureMessage = '아직 업데이트 링크가 준비되지 않았습니다.\n잠시 후 다시 시도해주세요.';
    } else {
      final uri = Uri.tryParse(storeUrl);
      if (uri == null) {
        failureMessage = '업데이트 링크가 올바르지 않습니다.\n잠시 후 다시 시도해주세요.';
      } else {
        try {
          // launchUrl 자체가 멈춰있는 극단적인 경우에도 무한 로딩으로 남지
          // 않도록 타임아웃을 둔다.
          opened = await launchUrl(uri, mode: LaunchMode.externalApplication)
              .timeout(const Duration(seconds: 5));
          if (!opened) {
            failureMessage = '스토어 페이지를 열 수 없습니다.\n잠시 후 다시 시도해주세요.';
          }
        } catch (_) {
          failureMessage = '스토어 페이지를 여는 중 오류가 발생했습니다.\n잠시 후 다시 시도해주세요.';
        }
      }
    }

    if (!mounted) return;
    setState(() => _opening = false);

    if (!opened && failureMessage != null) {
      _showInfoDialog(failureMessage);
    }
  }

  void _showInfoDialog(String message) {
    showDialog<void>(
      context: context,
      builder: (infoContext) => AlertDialog(
        title: const Text('안내', style: TextStyle(fontFamily: 'SeoulHangang', fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(infoContext),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Future<void> _dismiss() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDismissedVersionPrefsKey, widget.info.latestVersion);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final dismissible = widget.dismissible;
    final info = widget.info;

    return AlertDialog(
      title: Text(
        dismissible ? '업데이트 안내' : '필수 업데이트',
        style: const TextStyle(fontFamily: 'SeoulHangang', fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))]),
      ),
      content: Text(
        dismissible
            ? info.message
            : '${info.message}\n\n계속 이용하려면 최신 버전으로 업데이트해주세요.',
      ),
      actions: [
        if (dismissible)
          TextButton(
            onPressed: _opening ? null : _dismiss,
            child: const Text('나중에'),
          ),
        ElevatedButton(
          onPressed: _opening ? null : _handleUpdateTap,
          child: _opening
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(dismissible ? '업데이트' : '지금 업데이트'),
        ),
      ],
    );
  }
}

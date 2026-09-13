import 'package:flutter/material.dart';
// TEMP(테스트용): NICE 공식 문서 기준 재구현 검증 중 — 검증 완료 후
// nice_verification_screen.dart의 NiceVerificationScreen으로 되돌리거나
// 이 화면으로 정식 교체할지 결정할 것.
import 'package:party_app/screens/nice_auth_verification_screen.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/web_frame.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 본인확인 게이트 화면 한 쌍 — "인증이 필요한 상태"와 "확인하지 못한 상태".
//
// 둘 다 **루트 게이트(main.dart의 _AuthGate)가 첫 화면으로 직접 띄운다.**
// 다른 화면 위에 push되는 일이 없으므로 이 화면들에는 '닫기'가 없고, 닫는
// 코드도 없다. 인증을 마치면 세션이 바뀌고 → 게이트가 스스로 다시 평가해 →
// 서비스 화면으로 넘어간다. 화면이 자기를 pop하지 않는 것이 핵심이다.
//
// 예전에는 이 화면을 `Navigator.push`로 띄웠고, 그래서 안드로이드 뒤로가기와
// iOS 스와이프로 그냥 닫혔다(그 아래에 이미 MainScreen이 있었다). 지금은 닫을
// 대상 자체가 없다 — 미인증 계정에게는 MainScreen이 애초에 만들어지지 않는다.
//
// 빠져나가는 길은 **로그아웃 하나뿐**이다. 로그아웃하면 비로그인이 되고,
// 비로그인은 게이트를 그대로 통과한다(공유 링크로 들어온 사람이 파티를 볼 수
// 있어야 하므로 — root_gate.dart 참고).
// ─────────────────────────────────────────────────────────────────────────────

/// 게이트가 "본인확인 필요"로 판정했을 때의 화면.
class IdentityVerificationScreen extends StatefulWidget {
  const IdentityVerificationScreen({super.key});

  @override
  State<IdentityVerificationScreen> createState() =>
      _IdentityVerificationScreenState();
}

class _IdentityVerificationScreenState
    extends State<IdentityVerificationScreen> {
  bool _isLoading = false;
  String _statusMessage = '';

  /// 본인확인을 마쳤는지 서버에 다시 물어본다.
  ///
  /// 성공하면 세션의 [UserSession.identityStatus]가 바뀌고, 그 변화를 루트
  /// 게이트가 받아 서비스 화면으로 넘어간다 — 이 화면은 아무것도 닫지 않는다.
  Future<bool> _refreshSession() async {
    final verified = await UserSession.resolveIdentityVerified(force: true);
    return verified == true;
  }

  /// "이미 본인확인했어요" — 다른 기기·이전 세션에서 마쳤을 수 있다.
  ///
  /// 뒤로가기로 빠져나가는 길이 사라진 지금, **잘못 뜬 화면에서 스스로
  /// 빠져나오는 유일한 길**이라 그만큼 분명해야 한다.
  Future<void> _recheck() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '';
    });
    final verified = await _refreshSession();
    if (!mounted || verified) return; // 인증됐으면 게이트가 화면을 바꾼다.
    setState(() {
      _isLoading = false;
      _statusMessage =
          '이 계정은 아직 본인확인 기록이 없어요.\n'
          '다른 방법(구글·카카오·네이버)으로 가입한 계정에서 인증하셨다면, '
          '그 계정으로 로그인하면 인증 상태가 그대로 유지됩니다.';
    });
  }

  Future<void> _startVerification() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '';
    });

    final result = await Navigator.push<bool>(
      context,
      webFramedRoute((_) => const NiceAuthVerificationScreen()),
    );

    if (!mounted) return;

    if (result == true) {
      // 인증 성공 — 세션만 새로 읽으면 게이트가 서비스 화면으로 넘긴다.
      final verified = await _refreshSession();
      if (!mounted || verified) return;
      // 인증은 끝났는데 세션 반영이 안 된 드문 경우(읽기 실패). 갇히지 않도록
      // 다시 시도할 수 있다고 알려준다.
      setState(() {
        _isLoading = false;
        _statusMessage =
            '인증은 끝났지만 상태를 불러오지 못했어요. '
            '아래 \'이미 본인확인했어요\'를 눌러주세요.';
      });
      return;
    }

    setState(() {
      _isLoading = false;
      _statusMessage = '본인확인이 취소되었거나 실패했습니다. 다시 시도해주세요.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return _IdentityGateScaffold(
      icon: Icons.verified_user_outlined,
      title: '본인확인이 필요해요',
      description: '파티츄는 안전한 파티 문화를 위해\n모든 회원에게 본인확인을 요구합니다.',
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFE4ED),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PolicyRow(icon: Icons.badge_outlined, text: '이름·성별은 파티장에게만 공개됩니다'),
            SizedBox(height: 8),
            _PolicyRow(
              icon: Icons.phone_disabled_outlined,
              text: '연락처는 다른 사람에게 절대 공개되지 않습니다',
            ),
            SizedBox(height: 8),
            _PolicyRow(
              icon: Icons.security_outlined,
              text: '개인정보는 암호화되어 안전하게 보관됩니다',
            ),
          ],
        ),
      ),
      isLoading: _isLoading,
      primaryLabel: '본인확인 시작',
      onPrimary: _startVerification,
      secondaryLabel: '이미 본인확인했어요 · 다시 확인',
      onSecondary: _recheck,
      statusMessage: _statusMessage,
    );
  }
}

/// 게이트가 **본인확인 여부를 확인하지 못했을 때**의 화면.
///
/// 왜 그냥 들여보내지 않는가: 확인 실패를 통과로 처리하면, 네트워크를 끊는
/// 것만으로 미인증 계정이 서비스 화면에 들어온다. 본인확인이 필수 정책인 이상
/// "모르겠으면 통과"는 정책이 없는 것과 같다.
///
/// 왜 가두지 않는가: 그 실패의 대부분은 **이미 인증을 마친 사용자**에게
/// 일어나는 일시적인 오류다(지하철, 비행기 모드, 서버 순단). 그래서 이 화면은
/// 막다른 길이 아니라 **재시도**와 **로그아웃** 두 갈래를 준다.
class IdentityCheckFailedScreen extends StatefulWidget {
  const IdentityCheckFailedScreen({super.key});

  @override
  State<IdentityCheckFailedScreen> createState() =>
      _IdentityCheckFailedScreenState();
}

class _IdentityCheckFailedScreenState extends State<IdentityCheckFailedScreen> {
  bool _isLoading = false;
  String _statusMessage = '';

  Future<void> _retry() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '';
    });
    // 결과가 무엇이든(인증됨/미인증) 세션이 정해지면 게이트가 화면을 바꾼다.
    // 이 화면이 그대로 남아 있다는 것은 곧 "또 확인하지 못했다"는 뜻이다.
    await UserSession.resolveIdentityVerified(force: true);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _statusMessage = '아직 확인하지 못했어요. 네트워크 상태를 확인하고 다시 눌러주세요.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return _IdentityGateScaffold(
      icon: Icons.wifi_tethering_off_rounded,
      title: '본인확인 상태를 확인하지 못했어요',
      description:
          '네트워크가 불안정하면 잠시 이럴 수 있어요.\n'
          '연결을 확인한 뒤 다시 시도해주세요.',
      isLoading: _isLoading,
      primaryLabel: '다시 시도',
      onPrimary: _retry,
      statusMessage: _statusMessage,
    );
  }
}

/// 두 게이트 화면이 공유하는 껍데기 — **뒤로가기 차단**과 로그아웃이 여기 있다.
///
/// 화면마다 따로 적으면 한쪽만 고쳐진다. 게이트를 닫을 수 없다는 성질은 두
/// 화면의 공통 성질이므로 한 자리에 둔다.
class _IdentityGateScaffold extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Widget? body;
  final bool isLoading;
  final String primaryLabel;
  final Future<void> Function() onPrimary;
  final String? secondaryLabel;
  final Future<void> Function()? onSecondary;
  final String statusMessage;

  const _IdentityGateScaffold({
    required this.icon,
    required this.title,
    required this.description,
    required this.isLoading,
    required this.primaryLabel,
    required this.onPrimary,
    required this.statusMessage,
    this.body,
    this.secondaryLabel,
    this.onSecondary,
  });

  Future<void> _confirmSignOut(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('로그아웃할까요?'),
        content: const Text(
          '본인확인을 마치기 전까지는 회원 기능을 쓸 수 없어요.\n'
          '로그아웃해도 둘러보기는 그대로 하실 수 있습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // 세션이 비면 게이트가 비로그인으로 판정해 서비스 화면으로 돌아간다.
    await UserSession.signOut();
  }

  @override
  Widget build(BuildContext context) {
    // canPop: false — 안드로이드 뒤로가기·iOS 스와이프·팝 제스처를 전부 막는다.
    // 이 화면 아래에는 애초에 아무 화면도 없지만(루트다), 게이트가 열리기 전에
    // 앱을 빠져나가는 다른 경로가 생기지 않도록 명시적으로 못박는다.
    //
    // 다만 **아무 일도 일어나지 않으면 고장으로 읽힌다.** 뒤로가기는 "나가고
    // 싶다"는 뜻이므로, 막는 대신 유일한 출구가 어디인지 알려준다.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('본인확인을 마쳐야 이용할 수 있어요. 나가시려면 아래 \'로그아웃\'을 눌러주세요.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFFFF4F8),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 72, color: const Color(0xFFFF6FA0)),
                const SizedBox(height: 24),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.black54,
                    height: 1.6,
                  ),
                ),
                if (body != null) ...[const SizedBox(height: 24), body!],
                const SizedBox(height: 40),
                if (isLoading)
                  const CircularProgressIndicator(color: Color(0xFFFF6FA0))
                else
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: onPrimary,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6FA0),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      child: Text(primaryLabel),
                    ),
                  ),
                if (!isLoading && secondaryLabel != null)
                  TextButton(
                    onPressed: onSecondary,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFFF6FA0),
                    ),
                    child: Text(
                      secondaryLabel!,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (statusMessage.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    statusMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.black45,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ],
                // 게이트에서 빠져나가는 **유일한 길**. 눈에 띄지 않으면 사용자는
                // 갇혔다고 느끼므로 두 화면 모두에 항상 둔다.
                if (!isLoading) ...[
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () => _confirmSignOut(context),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.black45,
                    ),
                    child: const Text(
                      '로그아웃',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PolicyRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _PolicyRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: const Color(0xFFFF6FA0)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
        ),
      ],
    );
  }
}

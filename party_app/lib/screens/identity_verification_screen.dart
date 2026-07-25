import 'package:flutter/material.dart';
// TEMP(테스트용): NICE 공식 문서 기준 재구현 검증 중 — 검증 완료 후
// nice_verification_screen.dart의 NiceVerificationScreen으로 되돌리거나
// 이 화면으로 정식 교체할지 결정할 것.
import 'package:party_app/screens/nice_auth_verification_screen.dart';
import 'package:party_app/widgets/web_frame.dart';

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
      // 본인확인 성공 — 이 화면을 닫아 호출자에게 제어 반환
      Navigator.of(context).pop();
    } else {
      setState(() {
        _isLoading = false;
        _statusMessage = '본인확인이 취소되었거나 실패했습니다. 다시 시도해주세요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F8),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.verified_user_outlined,
                size: 72,
                color: Color(0xFFFF6FA0),
              ),
              const SizedBox(height: 24),
              const Text(
                '본인확인이 필요해요',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                '파티츄는 안전한 파티 문화를 위해\n모든 회원에게 본인확인을 요구합니다.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 15, color: Colors.black54, height: 1.6),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE4ED),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PolicyRow(
                      icon: Icons.badge_outlined,
                      text: '이름·성별은 파티장에게만 공개됩니다',
                    ),
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
              const SizedBox(height: 40),
              if (_isLoading)
                const CircularProgressIndicator(color: Color(0xFFFF6FA0))
              else
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _startVerification,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6FA0),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      textStyle: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    child: const Text('본인확인 시작'),
                  ),
                ),
              if (_statusMessage.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: Colors.black45, fontSize: 13),
                ),
              ],
            ],
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

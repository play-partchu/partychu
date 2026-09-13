import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'package:party_app/models/business_verification.dart';
import 'package:party_app/screens/feedback_compose_screen.dart';
import 'package:party_app/services/business_delegation_service.dart';
import 'package:party_app/widgets/partychu_ui.dart';
import 'package:party_app/widgets/web_frame.dart';

/// 사업자 인증 화면의 **대표자 승인 받기** 칸.
///
/// `authorization == pendingOwnerApproval`일 때만 뜬다. 하는 일은 두 가지뿐이다.
///   ① 서버에 승인 요청을 만들어 일회성 링크를 받는다
///   ② 그 링크를 대표자에게 전달하도록 돕는다(시스템 공유 / 복사)
///
/// ⚠️ **판정은 하나도 하지 않는다.** 승인 여부는 대표자가 NICE 본인확인을
///    마친 뒤 서버가 정한다. 이 화면에서 링크를 만들었다는 것만으로는 아무
///    권한도 생기지 않는다.
///
/// ⚠️ 링크는 **한 번만** 내려온다(서버는 원문을 저장하지 않고 해시만 갖는다).
///    그래서 받은 직후 화면에 그대로 남겨 두고, 잃어버리면 새로 요청하게 한다.
///
/// 카카오톡 전용 공유는 붙이지 않았다 — 기존 공유 시트는 파티 데이터 모양에
/// 맞춰진 것이라 그대로 쓸 수 없고, 이 단계에 새 의존성을 들일 이유가 없다.
/// 시스템 공유 시트에 카카오톡이 이미 들어 있다.
class OwnerApprovalPanel extends StatefulWidget {
  const OwnerApprovalPanel({
    super.key,
    required this.verification,
    this.onRefresh,
  });

  final BusinessVerification verification;

  /// 사업자 인증 상태를 **서버에서 다시 읽어 달라**는 요청(화면이 넘겨준다).
  ///
  /// 승인은 대표자 기기에서 끝나므로 이 화면은 그 순간을 알 수 없다. 앱을
  /// 벗어났다 돌아오면 화면이 알아서 다시 읽지만, 앱 안에 머문 채 승인을
  /// 기다리는 사람에게도 확인할 수단이 있어야 한다.
  final Future<void> Function()? onRefresh;

  @override
  State<OwnerApprovalPanel> createState() => _OwnerApprovalPanelState();
}

class _OwnerApprovalPanelState extends State<OwnerApprovalPanel> {
  bool _busy = false;

  /// 승인 여부를 다시 읽어 오는 중.
  bool _checking = false;

  /// 이번에 발급받은 링크. 서버가 다시 내려주지 않으므로 화면이 들고 있는다.
  DelegationRequest? _issued;

  /// 서버가 알려주는 진행 상태(링크는 포함되지 않는다).
  DelegationStatusInfo _status = DelegationStatusInfo.none;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final s = await BusinessDelegationService.status();
    if (mounted) setState(() => _status = s);
  }

  /// 승인이 끝났는지 서버에서 다시 읽는다.
  ///
  /// 아직이면 그렇다고 말해 준다 — 아무 반응이 없으면 사용자는 버튼이 고장난
  /// 줄 알고 계속 누른다. 승인이 끝났으면 화면이 통째로 완료 상태로 바뀌므로
  /// 여기서 따로 알릴 것이 없다.
  Future<void> _checkApproval() async {
    final refresh = widget.onRefresh;
    if (refresh == null || _checking) return;
    setState(() => _checking = true);
    try {
      await refresh();
      if (!mounted) return;
      await _loadStatus();
      if (mounted && widget.verification.needsOwnerApproval) {
        _snack('아직 대표자 확인이 완료되지 않았어요.');
      }
    } catch (_) {
      _snack('확인하지 못했어요. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _request() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await BusinessDelegationService.request();
      if (!mounted) return;
      setState(() => _issued = r);
      await _loadStatus();
    } on FirebaseFunctionsException catch (e) {
      // 서버가 한국어 안내 문구로 던진다.
      _snack(e.message ?? '승인 요청을 만들지 못했어요. 잠시 후 다시 시도해주세요.');
    } catch (_) {
      _snack('승인 요청을 만들지 못했어요. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _shareText(String url) =>
      '[파티츄] 사업장 운영 권한 승인 요청\n\n'
      '아래 링크에서 대표자 본인확인을 하시면 승인이 완료됩니다.\n$url';

  Future<void> _share(String url) async {
    try {
      await SharePlus.instance.share(ShareParams(text: _shareText(url)));
    } catch (_) {
      _snack('공유에 실패했어요. 링크를 복사해서 전달해주세요.');
    }
  }

  Future<void> _copy(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    _snack('승인 링크를 복사했어요.');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final issued = _issued;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PartyChuColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '대표자에게 승인받기',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            '사업자등록증상 대표자가 직접 본인확인을 하고 승인하면 이 계정으로 '
            '해당 사업장을 운영할 수 있어요. 가족·직원 등 관계를 증명하실 필요는 없어요.',
            style: TextStyle(fontSize: 12, height: 1.5, color: Colors.black45),
          ),
          if (issued == null && _status.isWaiting) ...[
            const SizedBox(height: 12),
            _notice(
              '이미 보낸 승인 요청이 대표자 확인을 기다리고 있어요. '
              '링크를 다시 만들면 이전 링크는 사용할 수 없게 돼요.',
            ),
          ],
          if (issued != null) ...[
            const SizedBox(height: 14),
            _linkBox(issued),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton.icon(
              onPressed: _busy ? null : _request,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.link_rounded, size: 18),
              label: Text(
                issued == null ? '대표자에게 승인 링크 보내기' : '새 승인 링크 보내기',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF6FA0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          if (widget.onRefresh != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: OutlinedButton.icon(
                onPressed: _checking ? null : _checkApproval,
                icon: _checking
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('승인됐는지 확인하기'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFB4436A),
                  side: const BorderSide(color: Color(0xFFFFD6E4)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
          // 막다른 길을 만들지 않는다 — 대표자가 연락이 닿지 않거나 본인확인을
          // 할 수 없는 경우가 실제로 있다. 그때 사람이 처리할 수 있는 창구를
          // 같은 칸 안에 둔다(기존 고객센터 화면을 그대로 쓴다).
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '대표자 확인이 어려운 경우',
                style: TextStyle(fontSize: 12, color: Colors.black45),
              ),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  webFramedRoute((_) => const FeedbackComposeScreen()),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  '고객센터 문의',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFFF6FA0),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _linkBox(DelegationRequest r) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD6E4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '대표자에게 아래 승인 링크를 전달해주세요.',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFFB4436A),
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            r.approvalUrl,
            style: const TextStyle(fontSize: 12, height: 1.5, color: Colors.black87),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _share(r.approvalUrl),
                  icon: const Icon(Icons.ios_share_rounded, size: 16),
                  label: const Text('공유'),
                  style: _smallButton,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _copy(r.approvalUrl),
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('링크 복사'),
                  style: _smallButton,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '· 사업자등록번호 ${r.businessNumberMasked}\n'
            '${_expiryLine(r.expiresAt)}'
            '· 링크는 이 화면에서만 확인할 수 있어요. 잃어버리면 새로 만들어주세요.\n'
            '· 링크를 가진 것만으로는 권한이 생기지 않아요. 대표자 본인확인을 통과해야 해요.',
            style: const TextStyle(fontSize: 11, height: 1.7, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  static String _expiryLine(DateTime? at) {
    if (at == null) return '';
    final d = at.toLocal();
    final t =
        '${d.month}월 ${d.day}일 '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '· $t까지 유효해요.\n';
  }

  Widget _notice(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFFFFBEB),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFFDE68A)),
    ),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, height: 1.5, color: Color(0xFFB45309)),
    ),
  );

  static final ButtonStyle _smallButton = OutlinedButton.styleFrom(
    foregroundColor: const Color(0xFFB4436A),
    side: const BorderSide(color: Color(0xFFFFD6E4)),
    minimumSize: const Size(0, 40),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
  );
}

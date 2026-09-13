import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'package:party_app/login.dart';
import 'package:party_app/models/event_apply.dart';
import 'package:party_app/models/place_event_application.dart';
import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/services/place_event_application_service.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/login_required_dialog.dart';
import 'package:party_app/widgets/web_frame.dart';

/// 매장 이벤트의 **신청하기** — 호스트가 신청을 받기로 한 이벤트에만 뜬다
/// ([EventApplyMode]).
///
/// ── 신청은 채팅이 아니라 데이터다 ───────────────────────────────────────────
/// 예전에는 이 버튼이 이벤트 채팅방을 열고 "[신청] … 신청합니다." 한 줄을
/// 보내는 것으로 끝났다. 그러면 **신청이 어디에도 남지 않는다** — 호스트는
/// 채팅 목록을 눈으로 세야 하고, 게스트는 자기가 신청했는지 알 수 없고,
/// 문의와 신청이 같은 방에서 섞인다.
///
/// 지금은 신청이 자기 문서를 만든다([PlaceEventApplication]). 문의는 예전
/// 그대로 채팅이고([GuestInquiryButton]), 둘은 서로를 모른다 — 신청한다고
/// 채팅방이 생기지 않고, 문의한다고 신청이 되지 않는다.
///
/// ── 파티 신청을 옮겨 온 것이 아니다 ─────────────────────────────────────────
/// 파티 신청(`applyToParty`)에는 정원·승인·참가비·성별가·결제·환불이 달려 있고
/// 그 전부를 서버 트랜잭션이 관리한다. 매장 이벤트에는 그 축이 하나도 없으므로
/// 여기에는 **신청했다/물렀다** 두 상태뿐이다. 중복 신청은 문서 id가 막고
/// ([PlaceEventApplication.docIdFor]), 위조는 서버가 막는다.
///
/// ── 이 버튼은 서버에 "신청해줘"라고 말할 뿐이다 ─────────────────────────────
/// 신청·취소를 앱이 직접 쓰지 않는다. firestore.rules가 신청 문서의 클라이언트
/// 쓰기를 전면 차단하고, 콜러블(applyToPlaceEvent / cancelPlaceEventApplication)
/// 이 이벤트 원본을 읽어 판정한다 — 특히 **종료 여부**는 서버만 안다
/// ([PlaceEventApplicationService] 상단 주석). 아래 [shouldShow]는 화면을 위한
/// 힌트일 뿐, 막는 힘은 없다.
class EventApplyButton extends StatefulWidget {
  const EventApplyButton({
    super.key,
    required this.promotion,
    required this.accent,
    this.compact = false,
    this.now,
  });

  final PlacePromotion promotion;

  final Color accent;

  /// 하단 CTA에서 문의 버튼과 나란히 놓일 때 true — 폭을 부모가 정한다.
  final bool compact;

  /// 종료 판정 기준 시각. 테스트만 넘긴다.
  final DateTime? now;

  /// 이 이벤트에 신청 버튼을 그려야 하는가.
  ///
  /// 하단 CTA가 "문의 + 신청" 두 칸인지 한 칸인지를 **버튼을 만들기 전에**
  /// 알아야 해서 밖으로 뺐다([GuestInquiryButton.shouldShow]와 같은 이유).
  ///
  /// ⚠️ **시작 전(scheduled) 이벤트는 신청을 받는다.** 오히려 그때가 미리
  ///    신청을 받는 기간이다 — 판정은 [PlacePromotion.showsApplyButtonAt]에
  ///    있고, 종료·숨김만 막는다.
  static bool shouldShow(PlacePromotion p, {DateTime? now}) {
    // 종료·숨김 이벤트에는 받을 수 없는 신청을 받는 자리를 남기지 않는다.
    if (!p.showsApplyButtonAt(now ?? DateTime.now())) return false;
    // 내 이벤트에는 신청 버튼을 두지 않는다 — 호스트가 자기 이벤트의 신청자가
    // 될 수는 없다(서버도 hostId == uid인 신청을 거부한다).
    if (UserSession.isLoggedIn && UserSession.userId == p.hostId) return false;
    return true;
  }

  @override
  State<EventApplyButton> createState() => _EventApplyButtonState();
}

class _EventApplyButtonState extends State<EventApplyButton> {
  /// 서버로 요청이 가 있는 동안 true — 같은 버튼이 두 번 눌리지 않게 한다.
  bool _busy = false;

  String get _guestId => UserSession.userId;

  @override
  Widget build(BuildContext context) {
    if (!EventApplyButton.shouldShow(widget.promotion, now: widget.now)) {
      return const SizedBox.shrink();
    }

    // 로그인 전에는 서버에 물어볼 신청이 없다 — 버튼만 그려 두고, 누르면
    // 로그인으로 안내한다(문의하기와 같은 흐름).
    if (!UserSession.isLoggedIn) return _wrap(_applyButton(applied: false));

    return StreamBuilder<PlaceEventApplication?>(
      stream: PlaceEventApplicationService.watchMine(
        eventId: widget.promotion.id,
        guestId: _guestId,
      ),
      builder: (context, snap) {
        // 아직 못 읽었으면 **신청 전으로 보여준다.** 여기서 로딩 스피너를 돌리면
        // 시트를 열 때마다 CTA 자리가 깜빡인다. 잘못 눌러도 이미 신청한 건이면
        // 서비스가 아무 일도 하지 않는다(같은 문서라 두 건이 될 수 없다).
        final applied = snap.data?.isApplied ?? false;
        return _wrap(_applyButton(applied: applied));
      },
    );
  }

  Widget _wrap(Widget button) => widget.compact
      ? button
      : Padding(padding: const EdgeInsets.only(top: 12), child: button);

  Widget _applyButton({required bool applied}) {
    final onPressed = _busy
        ? null
        : applied
        ? _confirmCancel
        : _apply;

    // 신청 전 — 색이 있는 주 CTA.
    if (!applied) {
      return SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: widget.accent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: _label('신청하기'),
        ),
      );
    }

    // 신청 후 — 더 누를 일이 없는 자리라 색을 뺀다. 누르면 취소를 묻는다.
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: widget.accent,
          side: BorderSide(color: widget.accent.withValues(alpha: 0.55)),
          backgroundColor: widget.accent.withValues(alpha: 0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: _label('신청 완료', icon: Icons.check_rounded),
      ),
    );
  }

  Widget _label(String text, {IconData? icon}) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 17), const SizedBox(width: 5)],
        Text(
          text,
          maxLines: 1,
          softWrap: false,
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
        ),
      ],
    ),
  );

  // ── 동작 ────────────────────────────────────────────────────────────────

  Future<void> _apply() async {
    if (!UserSession.isLoggedIn) {
      final shouldLogin = await showLoginRequiredDialog(
        context,
        message: '신청하려면 로그인이 필요합니다.',
      );
      if (!shouldLogin || !mounted) return;
      await Navigator.push(context, webFramedRoute((_) => LoginPage()));
      return;
    }
    setState(() => _busy = true);
    try {
      await PlaceEventApplicationService.apply(widget.promotion.id);
      if (!mounted) return;
      _notify('신청을 보냈어요. 호스트가 확인할 거예요.');
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      // 서버가 사람 말로 돌려준 이유는 **그대로** 보여준다 — "이미 종료된
      // 이벤트예요"처럼, 왜 막혔는지가 곧 사용자가 알아야 할 전부다
      // (GuestInquiryButton이 지키는 것과 같은 원칙).
      _notify(e.message ?? '신청하지 못했어요. 잠시 후 다시 시도해주세요.');
    } catch (_) {
      if (!mounted) return;
      _notify('신청하지 못했어요. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmCancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('신청을 취소할까요?'),
        content: Text(
          '${widget.promotion.title} 신청을 취소합니다.\n다시 신청할 수 있어요.',
          style: const TextStyle(fontSize: 13.5, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('그대로 두기'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('신청 취소'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await PlaceEventApplicationService.cancel(widget.promotion.id);
      if (!mounted) return;
      _notify('신청을 취소했어요.');
    } catch (_) {
      if (!mounted) return;
      _notify('취소하지 못했어요. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 결과를 **보이는 자리에** 알린다 — 이 버튼은 상세 바텀시트 안에 있어서
  /// 스낵바가 시트에 가려진다([GuestInquiryButton]과 같은 이유).
  void _notify(String message) {
    final route = ModalRoute.of(context);
    final coveredByPopup = route != null && !route.opaque;
    if (coveredByPopup) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(message, style: const TextStyle(fontSize: 14.5)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

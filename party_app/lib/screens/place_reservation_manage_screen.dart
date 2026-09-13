import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'package:party_app/models/place_rental_reservation.dart';
import 'package:party_app/services/place_rental_reservation_service.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/deposit_panel.dart';
import 'package:party_app/widgets/partychu_ui.dart';
import 'package:party_app/widgets/place_rental_reservation_card.dart';

/// 업주용 **장소대여 예약 관리** — 내 장소로 들어온 숙박·시간제·패키지 예약을
/// 승인·거절하고 입금을 확인한다.
///
/// 방문 예약 관리([VisitReservationManageScreen])와 같은 구조다: 탭은 처리
/// 순서 그대로(승인 대기 → 확정 → 지난·취소)이고, 자동승인 룸만 쓰는 업주는
/// 첫 탭이 늘 비어 있는 게 정상이다. 입금 확인은 '확정' 탭의 카드에서 바로
/// 누른다 — 승인과 입금은 다른 축이라 화면을 나누지 않는다.
class PlaceReservationManageScreen extends StatefulWidget {
  /// 이 장소의 예약만 보여준다 — 삭제가 막혔을 때 "어느 예약 때문인지"로
  /// 곧장 데려오려고 둔 것이다(delete_content_action.dart). null이면 예전처럼
  /// 내 장소 전체를 본다.
  final String? focusPlaceId;

  /// 걸러보는 중임을 알리는 배너에 쓸 이름. 예약 문서의 placeName은 예약
  /// 시점의 **스냅샷**이라 상호를 바꾸면 옛 이름이 남는다 — 그래서 배너는
  /// 예약이 아니라 호출한 쪽이 아는 현재 이름을 쓴다.
  final String? focusPlaceName;

  const PlaceReservationManageScreen({
    super.key,
    this.focusPlaceId,
    this.focusPlaceName,
  });

  @override
  State<PlaceReservationManageScreen> createState() =>
      _PlaceReservationManageScreenState();
}

class _PlaceReservationManageScreenState
    extends State<PlaceReservationManageScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 3,
    vsync: this,
  );

  /// 장소 필터가 켜져 있는지 — 배너의 '전체 보기'로 끌 수 있다.
  late bool _focused = (widget.focusPlaceId ?? '').isNotEmpty;

  /// 필터를 켜고 들어왔을 때 어느 탭을 먼저 열지는 **데이터가 정한다** —
  /// 막고 있는 예약이 '승인 대기'인지 '확정'인지 미리 알 수 없어서, 목록이
  /// 처음 도착했을 때 해당 건이 있는 탭으로 옮긴다. 한 번만 한다(사용자가
  /// 직접 탭을 옮긴 뒤 되돌려 놓으면 안 되므로).
  bool _tabSettled = false;

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 필터가 켜져 있으면 이 장소 예약만 남긴다.
  bool _inFocus(PlaceRentalReservation r) =>
      !_focused || r.placeId == widget.focusPlaceId;

  /// 처음 도착한 목록을 보고, 걸린 예약이 있는 탭을 연다.
  void _settleTab(List<PlaceRentalReservation> all) {
    if (_tabSettled || !_focused) return;
    _tabSettled = true;
    const order = [_Filter.requested, _Filter.confirmed, _Filter.done];
    final target = order.indexWhere(
      (f) => all.where(_inFocus).any(f.matches),
    );
    if (target <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tabController.animateTo(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = UserSession.userId;
    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text(
          '장소대여 예약 관리',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: PartyChuColors.primary,
          unselectedLabelColor: Colors.black45,
          indicatorColor: PartyChuColors.primary,
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          tabs: const [
            Tab(text: '승인 대기'),
            Tab(text: '확정'),
            Tab(text: '지난·취소'),
          ],
        ),
      ),
      body: uid.isEmpty
          ? const Center(
              child: Text(
                '로그인 후 이용할 수 있어요.',
                style: TextStyle(fontSize: 13.5, color: Colors.black45),
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _list(uid, _Filter.requested),
                _list(uid, _Filter.confirmed),
                _list(uid, _Filter.done),
              ],
            ),
    );
  }

  /// "이 장소만 보는 중" 배너 — 어디서 걸러진 목록인지 모른 채 "예약이 없다"를
  /// 보면 더 헷갈리므로, 필터가 켜져 있으면 항상 함께 보여주고 끄는 길을 준다.
  Widget _focusBanner() {
    final name = (widget.focusPlaceName ?? '').trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF3C2C8)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.filter_alt_rounded,
            size: 17,
            color: PartyChuColors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name.isEmpty ? '이 장소의 예약만 보는 중' : '$name 예약만 보는 중',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _focused = false),
            style: TextButton.styleFrom(
              foregroundColor: Colors.black54,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('전체 보기'),
          ),
        ],
      ),
    );
  }

  /// 장소대여 단독 예약과 숙박+파티 콤보 예약을 **한 목록으로** 보여준다.
  ///
  /// 두 컬렉션이지만 업주 입장에서는 "내 장소로 들어온 예약" 하나다 — 승인과
  /// 입금 확인 창구가 갈리면 한쪽을 놓친다. 스트림을 겹쳐 읽고 합친 뒤 정렬만
  /// 다시 한다(둘 다 hostId 단일 조건이라 복합 색인이 필요 없다).
  Widget _list(String uid, _Filter filter) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: PlaceRentalReservationService.hostReservations(uid).snapshots(),
      builder: (context, rentalSnap) =>
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: PlaceRentalReservationService.hostPackageBookings(
              uid,
            ).snapshots(),
            builder: (context, packageSnap) =>
                _body(filter, rentalSnap, packageSnap),
          ),
    );
  }

  Widget _body(
    _Filter filter,
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> rentalSnap,
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> packageSnap,
  ) {
    {
      final snap = rentalSnap.hasError ? rentalSnap : packageSnap;
      if (rentalSnap.connectionState == ConnectionState.waiting ||
          packageSnap.connectionState == ConnectionState.waiting) {
        return const Center(
          child: CircularProgressIndicator(color: PartyChuColors.primary),
        );
      }
      if (snap.hasError) {
        logFirestoreStreamError(
          'PlaceReservationManage',
          snap.error,
          snap.stackTrace,
        );
        return const Center(
          child: Text(
            '예약을 불러오지 못했어요.',
            style: TextStyle(fontSize: 13.5, color: Colors.black45),
          ),
        );
      }
      final all = [
        ...(rentalSnap.data?.docs ?? []).map(
          (d) => PlaceRentalReservation.fromDoc(d),
        ),
        ...(packageSnap.data?.docs ?? []).map(
          (d) =>
              PlaceRentalReservation.fromDoc(d, source: RentalSource.package),
        ),
      ];
      _settleTab(all);
      final items = PlaceRentalReservationService.sortByCreatedAtDesc(
        all.where(_inFocus).where(filter.matches),
      );

      if (items.isEmpty) {
        return Column(
          children: [
            if (_focused) _focusBanner(),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    _focused ? '이 장소에는 ${filter.emptyText}' : filter.emptyText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: Colors.black45,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (_focused) ...[_focusBanner(), const SizedBox(height: 12)],
          for (final r in items)
            PlaceRentalReservationCard(
              reservation: r,
              asHost: true,
              onApprove: () => _decide(r, approve: true),
              onReject: () => _decide(r, approve: false),
              onCancel: r.status == PlaceRentalStatus.confirmed
                  ? () => _cancel(r)
                  : null,
              onConfirmDeposit: () => _confirmDeposit(r),
            ),
        ],
      );
    }
  }

  /// 업주의 '입금 확인' — 결제만 완료로 바꾸고 예약 상태(확정)는 그대로 둔다.
  /// 목록이 실시간 구독이라 확인하면 카드가 바로 '결제완료'로 바뀐다.
  Future<void> _confirmDeposit(PlaceRentalReservation r) async {
    final depositor = r.payment?.depositorName;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('입금을 확인했나요?'),
        content: Text(
          '${r.requesterName} · ${r.useLabel}\n'
          '${depositor == null || depositor.isEmpty ? '' : '입금자 $depositor\n'}'
          '통장 내역과 대조한 뒤 확인해주세요.',
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('입금 확인'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await PlaceRentalReservationService.confirmDeposit(r);
      if (!mounted) return;
      _msg('입금을 확인했어요.');
    } catch (e) {
      if (!mounted) return;
      _msg(depositErrorMessage(e, '입금 확인에 실패했어요.'));
    }
  }

  Future<void> _decide(
    PlaceRentalReservation r, {
    required bool approve,
  }) async {
    String message = '';
    if (!approve) {
      // 거절은 이유를 함께 보내야 이용자가 다음 행동을 정할 수 있다.
      final ctrl = TextEditingController();
      final ok = await _messageDialog(
        title: '예약을 거절할까요?',
        subtitle: '${r.requesterName} · ${r.useLabel}',
        hint: '거절 사유 (선택) — 예약자에게 그대로 전달돼요',
        confirmLabel: '거절',
        controller: ctrl,
      );
      if (ok != true) return;
      message = ctrl.text.trim();
    }

    try {
      await PlaceRentalReservationService.decide(
        reservation: r,
        approve: approve,
        hostMessage: message,
      );
      if (!mounted) return;
      _msg(approve ? '예약을 승인했어요. 입금 안내가 나갔어요.' : '예약을 거절했어요.');
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      _msg(e.message ?? '처리하지 못했어요. 잠시 후 다시 시도해주세요.');
    } catch (_) {
      if (!mounted) return;
      _msg('처리하지 못했어요. 잠시 후 다시 시도해주세요.');
    }
  }

  Future<void> _cancel(PlaceRentalReservation r) async {
    final ctrl = TextEditingController();
    final ok = await _messageDialog(
      title: '확정된 예약을 취소할까요?',
      subtitle:
          '${r.requesterName} · ${r.useLabel}'
          // 콤보는 파티 참가까지 함께 풀린다 — 취소 전에 반드시 알려준다.
          '${r.isCombo ? '\n숙박 예약과 파티 참가가 함께 취소돼요.' : ''}',
      hint: '취소 사유 (선택) — 예약자에게 그대로 전달돼요',
      confirmLabel: '예약 취소',
      controller: ctrl,
    );
    if (ok != true) return;
    try {
      await PlaceRentalReservationService.cancel(
        reservation: r,
        message: ctrl.text.trim(),
      );
      if (!mounted) return;
      _msg('예약을 취소했어요.');
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      _msg(e.message ?? '취소하지 못했어요. 잠시 후 다시 시도해주세요.');
    } catch (_) {
      if (!mounted) return;
      _msg('취소하지 못했어요. 잠시 후 다시 시도해주세요.');
    }
  }

  /// 거절·취소가 함께 쓰는 사유 입력 다이얼로그.
  Future<bool?> _messageDialog({
    required String title,
    required String subtitle,
    required String hint,
    required String confirmLabel,
    required TextEditingController controller,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              subtitle,
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLength: 100,
              style: const TextStyle(fontSize: 13.5),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(fontSize: 12.5),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('닫기'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              confirmLabel,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _msg(String text) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
  );
}

/// 탭 하나가 무엇을 보여주는지.
enum _Filter {
  requested,
  confirmed,
  done;

  bool matches(PlaceRentalReservation r) => switch (this) {
    _Filter.requested => r.status == PlaceRentalStatus.requested,
    // 옛 포트원 결제 대기(pending)도 확정 탭에서 함께 본다 — 업주 입장에서는
    // "들어와 있는 예약"이고, 10분 뒤 자동으로 사라진다.
    _Filter.confirmed =>
      r.status == PlaceRentalStatus.confirmed ||
          r.status == PlaceRentalStatus.pending,
    _Filter.done => !r.status.isLive,
  };

  String get emptyText => switch (this) {
    _Filter.requested => '승인을 기다리는 예약이 없어요.',
    _Filter.confirmed => '확정된 예약이 없어요.',
    _Filter.done => '지난 예약이 없어요.',
  };
}

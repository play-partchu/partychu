import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'package:party_app/models/place_visit_reservation.dart';
import 'package:party_app/services/place_visit_reservation_service.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/deposit_panel.dart';
import 'package:party_app/widgets/partychu_ui.dart';
import 'package:party_app/widgets/visit_reservation_card.dart';

/// 업주용 **방문 예약 관리** — 내 플레이스로 들어온 무료 방문 예약을 승인·거절한다.
///
/// 탭은 처리 순서 그대로다: 승인 대기 → 확정 → 지난·취소. 승인 대기가 첫 탭인
/// 이유는 이 화면에 들어오는 대부분의 목적이 "기다리는 신청 처리"이기 때문이고,
/// 자동 승인 매장은 이 탭이 늘 비어 있는 게 정상이다.
///
/// 승인·거절·취소는 전부 Cloud Functions 콜러블을 거친다(클라이언트가 상태를
/// 직접 못 바꾼다 — firestore.rules).
class VisitReservationManageScreen extends StatefulWidget {
  const VisitReservationManageScreen({super.key});

  @override
  State<VisitReservationManageScreen> createState() =>
      _VisitReservationManageScreenState();
}

class _VisitReservationManageScreenState
    extends State<VisitReservationManageScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 3,
    vsync: this,
  );

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
          '방문 예약 관리',
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
                _list(uid, _Filter.approved),
                _list(uid, _Filter.done),
              ],
            ),
    );
  }

  Widget _list(String uid, _Filter filter) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: PlaceVisitReservationService.hostReservations(uid).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: PartyChuColors.primary),
          );
        }
        if (snap.hasError) {
          logFirestoreStreamError(
            'VisitReservationManage',
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
        final all = (snap.data?.docs ?? [])
            .map(PlaceVisitReservation.fromDoc)
            .where(filter.matches)
            .toList();
        final items = PlaceVisitReservationService.sortByVisitAtDesc(all);

        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                filter.emptyText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: Colors.black45,
                ),
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            for (final r in items)
              VisitReservationCard(
                reservation: r,
                asHost: true,
                onApprove: () => _decide(r, approve: true),
                onReject: () => _decide(r, approve: false),
                onCancel: r.status == VisitReservationStatus.approved
                    ? () => _cancel(r)
                    : null,
                onConfirmDeposit: () => _confirmDeposit(r),
              ),
          ],
        );
      },
    );
  }

  /// 업주의 '입금 확인' — 결제만 완료로 바꾸고 예약 상태(승인 여부)는 그대로
  /// 둔다. 목록이 실시간 구독이라 확인하면 카드가 바로 '결제완료'로 바뀐다.
  Future<void> _confirmDeposit(PlaceVisitReservation r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('입금을 확인했나요?'),
        content: Text(
          '${r.requesterName} · ${r.summaryLabel}\n'
          '${r.payment?.depositorName == null || r.payment!.depositorName!.isEmpty ? '' : '입금자 ${r.payment!.depositorName}\n'}'
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
      await PlaceVisitReservationService.confirmDeposit(r.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('입금을 확인했어요.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(depositErrorMessage(e, '입금 확인에 실패했어요.'))),
      );
    }
  }

  Future<void> _decide(PlaceVisitReservation r, {required bool approve}) async {
    String message = '';
    if (!approve) {
      // 거절은 이유를 함께 보내야 이용자가 다음 행동을 정할 수 있다.
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text('예약을 거절할까요?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${r.requesterName} · ${r.summaryLabel}',
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLength: 100,
                style: const TextStyle(fontSize: 13.5),
                decoration: const InputDecoration(
                  hintText: '거절 사유 (선택) — 예약자에게 그대로 전달돼요',
                  hintStyle: TextStyle(fontSize: 12.5),
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
              child: const Text('거절', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
      if (ok != true) return;
      message = ctrl.text.trim();
    }

    try {
      await PlaceVisitReservationService.decide(
        reservationId: r.id,
        approve: approve,
        hostMessage: message,
      );
      if (!mounted) return;
      _msg(approve ? '예약을 승인했어요.' : '예약을 거절했어요.');
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      _msg(e.message ?? '처리하지 못했어요. 잠시 후 다시 시도해주세요.');
    } catch (_) {
      if (!mounted) return;
      _msg('처리하지 못했어요. 잠시 후 다시 시도해주세요.');
    }
  }

  Future<void> _cancel(PlaceVisitReservation r) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('확정된 예약을 취소할까요?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${r.requesterName} · ${r.summaryLabel}',
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLength: 100,
              style: const TextStyle(fontSize: 13.5),
              decoration: const InputDecoration(
                hintText: '취소 사유 (선택) — 예약자에게 그대로 전달돼요',
                hintStyle: TextStyle(fontSize: 12.5),
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
            child: const Text('예약 취소', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await PlaceVisitReservationService.cancel(
        reservationId: r.id,
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

  void _msg(String text) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
  );
}

/// 탭 하나가 무엇을 보여주는지.
enum _Filter {
  requested,
  approved,
  done;

  bool matches(PlaceVisitReservation r) => switch (this) {
    _Filter.requested => r.status == VisitReservationStatus.requested,
    _Filter.approved => r.status == VisitReservationStatus.approved,
    _Filter.done => !r.status.isLive,
  };

  String get emptyText => switch (this) {
    _Filter.requested => '승인을 기다리는 예약이 없어요.',
    _Filter.approved => '확정된 예약이 없어요.',
    _Filter.done => '지난 예약이 없어요.',
  };
}

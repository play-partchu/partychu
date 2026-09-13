import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'package:party_app/models/place_visit_reservation.dart';
import 'package:party_app/services/place_visit_reservation_service.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/partychu_ui.dart';
import 'package:party_app/widgets/visit_reservation_card.dart';

/// 내가 신청한 **플레이스 방문 예약** 목록.
///
/// ⚠️ 평소 진입 경로는 이 화면이 아니다 — 마이페이지는 게스트 허브
/// ([MyGuestHubScreen])의 플레이스 탭으로 들어가고, 그쪽이 방문 예약·이용권을
/// 함께 보여준다. 이 화면은 **알림 딥링크 전용**으로 남아 있다
/// (notifications_screen.dart의 `visit_reservation*` 알림이 곧바로 이 목록을
/// 연다 — 허브를 거치면 어느 탭을 봐야 하는지 사용자가 다시 찾아야 한다).
/// 목록·카드·취소 흐름은 허브와 같은 서비스·위젯을 쓴다.
///
/// requesterId 단일 조건 조회 후 클라이언트 정렬(복합 색인 회피).
class MyVisitReservationsScreen extends StatefulWidget {
  const MyVisitReservationsScreen({super.key});

  @override
  State<MyVisitReservationsScreen> createState() =>
      _MyVisitReservationsScreenState();
}

class _MyVisitReservationsScreenState extends State<MyVisitReservationsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 2,
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
          '내 플레이스 예약',
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
            Tab(text: '진행중'),
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
              children: [_list(uid, live: true), _list(uid, live: false)],
            ),
    );
  }

  Widget _list(String uid, {required bool live}) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: PlaceVisitReservationService.myReservations(uid).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: PartyChuColors.primary),
          );
        }
        if (snap.hasError) {
          logFirestoreStreamError(
            'MyVisitReservations',
            snap.error,
            snap.stackTrace,
          );
          return const Center(
            child: Text(
              '내 플레이스 예약을 불러오지 못했어요.',
              style: TextStyle(fontSize: 13.5, color: Colors.black45),
            ),
          );
        }
        final all = (snap.data?.docs ?? [])
            .map(PlaceVisitReservation.fromDoc)
            .where((r) => r.status.isLive == live)
            .toList();
        final items = PlaceVisitReservationService.sortByVisitAtDesc(all);

        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                live
                    ? '진행 중인 플레이스 예약이 없어요.\n플레이스 상세에서 "방문 예약하기"로 신청할 수 있어요.'
                    : '지난 플레이스 예약이 없어요.',
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
                onCancel: r.canCancel(DateTime.now()) ? () => _cancel(r) : null,
                // 예약금이 걸린 무통장입금 예약에서만 카드 안에 버튼이 뜬다.
                onMarkDepositSent: () =>
                    PlaceVisitReservationService.markDepositSent(r.id),
              ),
          ],
        );
      },
    );
  }

  Future<void> _cancel(PlaceVisitReservation r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('예약을 취소할까요?'),
        content: Text(
          '${r.placeName}\n${r.summaryLabel}',
          style: const TextStyle(fontSize: 13.5, height: 1.5),
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
      await PlaceVisitReservationService.cancel(reservationId: r.id);
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

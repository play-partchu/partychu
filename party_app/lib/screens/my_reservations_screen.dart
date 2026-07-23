import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/utils/format_utils.dart';
import 'package:party_app/utils/user_session.dart';

/// 이용자의 장소대여 예약 목록 — my_page_screen.dart의 _MyPlaceList와 동일한
/// 패턴(탭 2개, hostId 대신 requesterId로 필터, orderBy 없이 클라이언트 정렬로
/// 복합 색인 회피). placeReservationGroups 컬렉션이 예약 1건(시간제/패키지/
/// 하루단위 공통)의 단일 진실 소스다.
class MyReservationsScreen extends StatefulWidget {
  const MyReservationsScreen({super.key});

  @override
  State<MyReservationsScreen> createState() => _MyReservationsScreenState();
}

class _MyReservationsScreenState extends State<MyReservationsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userId = UserSession.userId;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        title: const Text('내 예약', style: TextStyle(fontFamily: 'SeoulHangang', fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])),
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFFFF6FA0),
          unselectedLabelColor: Colors.black45,
          indicatorColor: const Color(0xFFFF6FA0),
          indicatorWeight: 2,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          tabs: const [
            Tab(text: '진행중'),
            Tab(text: '취소·만료'),
          ],
        ),
      ),
      body: userId.isEmpty
          ? const Center(
              child: Text('로그인 후 이용 가능합니다.', style: TextStyle(color: Colors.black45)),
            )
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('placeReservationGroups')
                  .where('requesterId', isEqualTo: userId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  logFirestoreStreamError(
                    'MyReservationsScreen',
                    snapshot.error,
                    snapshot.stackTrace,
                  );
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        '예약 목록을 불러오지 못했어요.\n잠시 후 다시 시도해주세요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black45),
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFF6FA0)),
                  );
                }

                final docs = List<QueryDocumentSnapshot>.from(snapshot.data!.docs)
                  ..sort((a, b) {
                    final aTime = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
                    final bTime = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
                    if (aTime == null && bTime == null) return 0;
                    if (aTime == null) return 1;
                    if (bTime == null) return -1;
                    return bTime.compareTo(aTime);
                  });

                final active = <QueryDocumentSnapshot>[];
                final closed = <QueryDocumentSnapshot>[];
                for (final doc in docs) {
                  final status = (doc.data() as Map<String, dynamic>)['status'] as String?;
                  if (status == 'cancelled' || status == 'expired') {
                    closed.add(doc);
                  } else {
                    active.add(doc);
                  }
                }

                return TabBarView(
                  controller: _tabController,
                  children: [
                    _ReservationList(
                      docs: active,
                      emptyMessage: '진행중인 예약이 없어요',
                    ),
                    _ReservationList(
                      docs: closed,
                      emptyMessage: '취소·만료된 예약이 없어요',
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _ReservationList extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;
  final String emptyMessage;

  const _ReservationList({required this.docs, required this.emptyMessage});

  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty) {
      return Center(
        child: Text(emptyMessage, style: const TextStyle(color: Colors.black38)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: docs.length,
      itemBuilder: (_, i) =>
          _ReservationCard(doc: docs[i], data: docs[i].data() as Map<String, dynamic>),
    );
  }
}

class _ReservationCard extends StatefulWidget {
  final QueryDocumentSnapshot doc;
  final Map<String, dynamic> data;

  const _ReservationCard({required this.doc, required this.data});

  @override
  State<_ReservationCard> createState() => _ReservationCardState();
}

class _ReservationCardState extends State<_ReservationCard> {
  bool _cancelling = false;

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return '결제 대기';
      case 'confirmed':
        return '예약 확정';
      case 'cancelled':
        return '취소됨';
      case 'expired':
        return '만료됨';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'confirmed':
        return const Color(0xFF2E7D32);
      case 'pending':
        return const Color(0xFFE65100);
      default:
        return Colors.black38;
    }
  }

  String _fmtPrice(int price) => formatPrice(price);

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('예약을 취소할까요?', style: TextStyle(fontFamily: 'SeoulHangang', fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])),
        content: const Text('취소하면 되돌릴 수 없어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('아니요', style: TextStyle(color: Colors.black45)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('취소하기', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _cancelling = true);
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('cancelReservation');
      await callable.call<Map<Object?, Object?>>({'groupId': widget.doc.id});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('예약이 취소됐어요.'), behavior: SnackBarBehavior.floating),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('취소 중 오류가 발생했습니다. 다시 시도해주세요.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final status = d['status'] as String? ?? 'pending';
    final placeName = d['placeName'] as String? ?? '장소';
    final roomName = d['roomName'] as String?;
    final bookingType = d['bookingType'] as String? ?? 'hourly';
    final packageName = d['packageName'] as String?;
    final date = d['date'] as String? ?? '';
    final totalPrice = (d['totalPrice'] as num?)?.toInt() ?? 0;
    final peopleCount = (d['peopleCount'] as num?)?.toInt() ?? 1;
    final canCancel = status == 'pending' || status == 'confirmed';

    final subtitle = bookingType == 'package' && packageName != null
        ? packageName
        : bookingType == 'daily'
        ? '하루 단위 대여'
        : '시간제 예약';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  placeName,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor(status).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _statusLabel(status),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _statusColor(status),
                  ),
                ),
              ),
            ],
          ),
          if (roomName != null) ...[
            const SizedBox(height: 2),
            Text(roomName, style: const TextStyle(fontSize: 12, color: Colors.black45)),
          ],
          const SizedBox(height: 8),
          Text(
            '$date · $subtitle · $peopleCount명',
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 6),
          Text(
            _fmtPrice(totalPrice),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFFFF6FA0),
            ),
          ),
          if (canCancel) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: _cancelling ? null : _cancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: _cancelling
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent),
                      )
                    : const Text('예약 취소', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

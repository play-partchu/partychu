import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/utils/format_utils.dart';
import 'package:party_app/utils/user_session.dart';

/// 내 "숙박+파티 패키지" 예약 목록 — my_reservations_screen.dart와 동일한
/// 패턴(진행중/취소·만료 탭, requesterId로 필터, 클라이언트 정렬)이지만
/// packageBookings 컬렉션 하나만 본다. 방 예약 + 파티 신청이 이 화면에서는
/// 항상 카드 1개로 합쳐져 표시된다(개별 "내 예약"/"참가한 파티" 목록에는
/// 패키지로 생성된 항목이 나타나지 않도록 걸러져 있다 — place_detail_screen.dart
/// 콤보 CTA, my_page_screen.dart _MyJoinedPartyList의 bundleBookingId 필터 참고).
class MyPackageBookingsScreen extends StatefulWidget {
  const MyPackageBookingsScreen({super.key});

  @override
  State<MyPackageBookingsScreen> createState() => _MyPackageBookingsScreenState();
}

class _MyPackageBookingsScreenState extends State<MyPackageBookingsScreen>
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
        title: const Text('숙박+파티 패키지'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF7C5CBF),
          unselectedLabelColor: Colors.black45,
          indicatorColor: const Color(0xFF7C5CBF),
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
                  .collection('packageBookings')
                  .where('requesterId', isEqualTo: userId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  logFirestoreStreamError(
                    'MyPackageBookingsScreen',
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
                    child: CircularProgressIndicator(color: Color(0xFF7C5CBF)),
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
                    _PackageBookingList(docs: active, emptyMessage: '진행중인 패키지 예약이 없어요'),
                    _PackageBookingList(docs: closed, emptyMessage: '취소·만료된 패키지 예약이 없어요'),
                  ],
                );
              },
            ),
    );
  }
}

class _PackageBookingList extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;
  final String emptyMessage;

  const _PackageBookingList({required this.docs, required this.emptyMessage});

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
          _PackageBookingCard(doc: docs[i], data: docs[i].data() as Map<String, dynamic>),
    );
  }
}

class _PackageBookingCard extends StatefulWidget {
  final QueryDocumentSnapshot doc;
  final Map<String, dynamic> data;

  const _PackageBookingCard({required this.doc, required this.data});

  @override
  State<_PackageBookingCard> createState() => _PackageBookingCardState();
}

class _PackageBookingCardState extends State<_PackageBookingCard> {
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

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('패키지 예약을 취소할까요?'),
        content: const Text('숙박 예약과 파티 참가가 함께 취소돼요. 취소하면 되돌릴 수 없어요.'),
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
          .httpsCallable('cancelPackageBooking');
      final result = await callable.call<Map<Object?, Object?>>({
        'bundleBookingId': widget.doc.id,
      });
      final refundAmount = (result.data['refundAmount'] as num?)?.toInt() ?? 0;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            refundAmount > 0
                ? '패키지 예약이 취소됐어요. 환불 예정 금액 ${formatPrice(refundAmount)}'
                : '패키지 예약이 취소됐어요.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
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
    final placeName = d['placeName'] as String? ?? '숙박';
    final roomName = d['roomName'] as String?;
    final partyTitle = d['partyTitle'] as String? ?? '파티';
    final date = d['date'] as String? ?? '';
    final totalPrice = (d['totalPrice'] as num?)?.toInt() ?? 0;
    final peopleCount = (d['peopleCount'] as num?)?.toInt() ?? 1;
    final canCancel = status == 'pending' || status == 'confirmed';

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
              const Text('📦', style: TextStyle(fontSize: 15)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$placeName${roomName != null ? ' · $roomName' : ''}',
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
          const SizedBox(height: 4),
          Text('🎉 $partyTitle', style: const TextStyle(fontSize: 12, color: Colors.black45)),
          const SizedBox(height: 8),
          Text(
            '$date · $peopleCount명',
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 6),
          Text(
            formatPrice(totalPrice),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF7C5CBF),
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

// ─────────────────────────────────────────────────────────────────────────────
// 🎀 파티츄 게스트 — 내 신청 · 예약 · 참여
//
// 예전 마이페이지는 "내 파티 신청 / 내 장소대여 예약 / 내 플레이스 예약 /
// 내 패키지 예약 / 내 이용권"을 각각 별도 메뉴로 첫 화면에 늘어놓았다. 종류가
// 늘어날수록 첫 화면만 길어지고, 정작 "내가 뭘 신청했더라"는 질문에는 메뉴를
// 하나씩 열어봐야 답할 수 있었다.
//
// 이 화면은 그 진입점들을 **참가자 역할 하나**로 합친다. 위쪽 탭은 메인 화면과
// 같은 축(파티츄 · 플레이스 · 공간대여 · 파티크루)이고, 그 아래 알약 필터가
// 진행중/완료/취소를 가른다. '전체'는 두지 않는다 — 참가자가 이 화면을 여는
// 이유는 거의 언제나 "지금 살아 있는 내 신청"이라, 끝난 건과 취소된 건까지
// 섞인 목록이 첫 화면이면 그것부터 걷어내야 한다.
//
// ⚠️ 조회 로직은 새로 만들지 않았다 — 각 도메인의 기존 서비스·모델·카드
// 위젯을 그대로 쓴다(MyReservationsScreen · MyVisitReservationsScreen ·
// MyPackageBookingsScreen · MyVouchersScreen과 **같은 스트림, 같은 카드**).
// 여기서 하는 일은 "어느 탭에 놓고 어떤 상태로 거를지"뿐이다.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'package:party_app/models/check_in_pass.dart';
import 'package:party_app/models/party_capacity_status.dart';
import 'package:party_app/models/payment_status.dart';
import 'package:party_app/models/place_event_application.dart';
import 'package:party_app/models/place_product.dart';
import 'package:party_app/models/place_rental_reservation.dart';
import 'package:party_app/models/place_visit_reservation.dart';
import 'package:party_app/screens/chat_list_screen.dart';
import 'package:party_app/screens/my_favorites_screen.dart';
import 'package:party_app/screens/party_detail_screen.dart';
import 'package:party_app/services/place_event_application_service.dart';
import 'package:party_app/services/place_product_service.dart';
import 'package:party_app/services/place_promotion_service.dart';
import 'package:party_app/services/place_rental_reservation_service.dart';
import 'package:party_app/services/place_visit_reservation_service.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/utils/format_utils.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/applicant_photo_protection.dart';
import 'package:party_app/widgets/auth_rebuilder.dart';
import 'package:party_app/widgets/check_in_qr_card.dart';
import 'package:party_app/widgets/deposit_panel.dart';
import 'package:party_app/widgets/refund_resubmit_panel.dart';
import 'package:party_app/widgets/party_card_widget.dart';
import 'package:party_app/widgets/place_event_application_card.dart';
import 'package:party_app/widgets/place_product/place_promotion_detail_sheet.dart';
import 'package:party_app/widgets/place_rental_reservation_card.dart';
import 'package:party_app/widgets/party_review_section.dart';
import 'package:party_app/widgets/visit_reservation_card.dart';
import 'package:party_app/widgets/voucher_card.dart';
import 'package:party_app/widgets/web_frame.dart';

const Color _kBg = Color(0xFFFFF4F8);
const Color _kAccent = Color(0xFFFF6FA0);

/// 게스트/호스트 화면이 공유하는 상태 축.
///
/// 도메인마다 상태 enum이 다르지만(파티 신청 status · PlaceRentalStatus ·
/// VisitReservationStatus · PlaceProductOrderStatus) 사용자가 묻는 것은 늘
/// 셋 중 하나다: 아직 남아 있나 / 끝났나 / 취소됐나. 그 셋으로만 접는다.
enum GuestStatusFilter {
  ongoing('진행중'),
  done('완료'),
  cancelled('취소');

  const GuestStatusFilter(this.label);

  final String label;

  bool matches(GuestStatusFilter actual) => this == actual;
}

// ── 도메인별 상태 → GuestStatusFilter 접기 ──────────────────────────────
// 각 함수는 "그 도메인에서 이미 쓰던 판정"만 옮겨 담는다. 새 규칙을 만들지
// 않으므로 기존 목록 화면과 분류가 어긋나지 않는다.

/// 파티 신청 — applications/{id}. 취소는 status, 완료 여부는 신청 시점에
/// 스냅샷으로 남은 partyDateTime으로 가른다(_MyJoinedPartyList와 같은 규칙).
GuestStatusFilter guestStatusOfApplication(
  Map<String, dynamic> d,
  DateTime now,
) {
  if ((d['status'] as String? ?? 'applied') == 'cancelled') {
    return GuestStatusFilter.cancelled;
  }
  final ts = d['partyDateTime'];
  final dt = ts is Timestamp ? ts.toDate() : null;
  return dt != null && dt.isBefore(now)
      ? GuestStatusFilter.done
      : GuestStatusFilter.ongoing;
}

/// 매장 이벤트 신청 — placeEventApplications/{eventId}_{uid}.
///
/// 취소는 status가 말해 주고, 완료 여부는 신청 시점에 서버가 베껴 둔 이벤트
/// 종료일로 가른다. **판정은 [PlacePromotion.statusAt]의 종료 조건과 같다** —
/// 상시 진행이면 날짜로 끝나지 않고, 종료일이 있으면 **그 날 하루는 살아
/// 있다**(그 날 23:59:59를 지나야 끝난 것이다).
GuestStatusFilter guestStatusOfPlaceEventApplication(
  PlaceEventApplication a,
  DateTime now,
) {
  if (!a.isApplied) return GuestStatusFilter.cancelled;
  if (a.eventIsAlways) return GuestStatusFilter.ongoing;
  final end = a.eventEndAt;
  if (end == null) return GuestStatusFilter.ongoing;
  final dayEnd = DateTime(end.year, end.month, end.day, 23, 59, 59);
  return now.isAfter(dayEnd)
      ? GuestStatusFilter.done
      : GuestStatusFilter.ongoing;
}

/// 장소대여·패키지 예약 — 거절/취소는 취소, 만료는 완료, 살아 있는 예약은
/// 이용 종료 시각이 지났으면 완료다.
GuestStatusFilter guestStatusOfRental(PlaceRentalReservation r, DateTime now) {
  switch (r.status) {
    case PlaceRentalStatus.rejected:
    case PlaceRentalStatus.cancelled:
      return GuestStatusFilter.cancelled;
    case PlaceRentalStatus.expired:
      return GuestStatusFilter.done;
    default:
      final end = r.useEndAt;
      return end != null && end.isBefore(now)
          ? GuestStatusFilter.done
          : GuestStatusFilter.ongoing;
  }
}

/// 플레이스 방문 예약 — 거절·취소는 취소, 기한 만료는 완료, 방문 시각이
/// 지난 확정 건도 완료다.
GuestStatusFilter guestStatusOfVisit(PlaceVisitReservation r, DateTime now) {
  switch (r.status) {
    case VisitReservationStatus.rejected:
    case VisitReservationStatus.cancelledByGuest:
    case VisitReservationStatus.cancelledByHost:
      return GuestStatusFilter.cancelled;
    case VisitReservationStatus.expired:
      return GuestStatusFilter.done;
    default:
      return r.visitAt.isBefore(now)
          ? GuestStatusFilter.done
          : GuestStatusFilter.ongoing;
  }
}

/// 이용권 주문 — 사용 완료·기간 만료는 완료, 취소·환불은 취소.
GuestStatusFilter guestStatusOfOrder(PlaceProductOrder o) {
  switch (o.status) {
    case PlaceProductOrderStatus.cancelled:
    case PlaceProductOrderStatus.refunded:
      return GuestStatusFilter.cancelled;
    case PlaceProductOrderStatus.used:
    case PlaceProductOrderStatus.expired:
      return GuestStatusFilter.done;
    default:
      return GuestStatusFilter.ongoing;
  }
}

// ═════════════════════════════════════════════════════════════════════════
// 화면
// ═════════════════════════════════════════════════════════════════════════

class MyGuestHubScreen extends StatefulWidget {
  const MyGuestHubScreen({super.key});

  @override
  State<MyGuestHubScreen> createState() => _MyGuestHubScreenState();
}

class _MyGuestHubScreenState extends State<MyGuestHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 4,
    vsync: this,
  );
  // 첫 진입 기본값은 **진행중**이다. 필터 막대는 네 탭 위에 하나로 얹혀
  // 있으므로 이 값 하나가 곧 모든 탭의 첫 화면이 된다(탭을 옮겨도 사용자가
  // 고른 상태는 그대로 따라간다 — 예전과 같은 동작이다).
  GuestStatusFilter _status = GuestStatusFilter.ongoing;

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text(
          '🎀 파티츄 게스트',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 메인 화면과 같은 카테고리 축 — 사용자가 이미 익힌 순서를
              // 그대로 쓴다(파티츄 · 플레이스 · 장소대여 · 파티크루).
              MyHubTabBar(controller: _tabController),
              GuestStatusFilterBar(
                value: _status,
                onChanged: (v) => setState(() => _status = v),
              ),
            ],
          ),
        ),
      ),
      body: AuthRebuilder(
        builder: (context) => UserSession.userId.isEmpty
            ? const _LoginNotice()
            : TabBarView(
                controller: _tabController,
                children: [
                  _PartyApplicationsTab(status: _status),
                  _PlaceGuestTab(status: _status),
                  _RentalGuestTab(status: _status),
                  const _CrewGuestTab(),
                ],
              ),
      ),
    );
  }
}

/// 게스트/호스트 허브가 함께 쓰는 카테고리 탭 — 두 화면의 축이 어긋나면
/// "게스트에선 3번째가 공간대여인데 호스트에선 아니네"가 되어 버린다.
class MyHubTabBar extends StatelessWidget {
  const MyHubTabBar({
    super.key,
    required this.controller,
    this.includeStoreEvent = false,
  });

  final TabController controller;

  /// 🎪 **이벤트** 칸을 파티츄 옆에 함께 둘지.
  ///
  /// 호스트 허브에서만 true다 — 매장 이벤트는 **호스트가 등록하는 것**이라
  /// 게스트 허브에는 관리할 대상이 없다(게스트가 낸 이벤트 신청은 플레이스
  /// 탭에 있다). 이벤트는 파티의 하위 항목이 아니므로 파티츄 탭 안이 아니라
  /// 같은 급의 칸을 갖는다.
  ///
  /// 칸이 다섯이면 390px 폭에서 글자가 두 줄로 깨진다. 그래서 그때만 가로
  /// 스크롤로 바꾼다 — 글자 크기를 줄이면 나머지 화면과 톤이 어긋난다.
  final bool includeStoreEvent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: TabBar(
        controller: controller,
        isScrollable: includeStoreEvent,
        tabAlignment: includeStoreEvent ? TabAlignment.center : null,
        labelColor: _kAccent,
        unselectedLabelColor: Colors.black45,
        labelStyle: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
        ),
        labelPadding: EdgeInsets.symmetric(
          horizontal: includeStoreEvent ? 10 : 2,
        ),
        indicatorColor: _kAccent,
        indicatorWeight: 2.5,
        dividerColor: const Color(0xFFFFE4ED),
        tabs: [
          const Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.pets, size: 14, color: Color(0xFFFFACD2)),
                SizedBox(width: 4),
                Text('파티츄'),
              ],
            ),
          ),
          if (includeStoreEvent) const Tab(text: '🎪 이벤트'),
          const Tab(text: '📍 플레이스'),
          const Tab(text: '🏠 공간대여'),
          const Tab(text: '🤝 파티크루'),
        ],
      ),
    );
  }
}

/// 진행중 / 완료 / 취소 알약 필터 — 셋이 가로폭을 균등하게 나눈다.
class GuestStatusFilterBar extends StatelessWidget {
  const GuestStatusFilterBar({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final GuestStatusFilter value;
  final ValueChanged<GuestStatusFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Row(
        children: [
          for (final f in GuestStatusFilter.values) ...[
            if (f != GuestStatusFilter.values.first) const SizedBox(width: 6),
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(f),
                child: Container(
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: f == value ? _kAccent : const Color(0xFFF6F7FA),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    f.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: f == value
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: f == value ? Colors.white : Colors.black54,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LoginNotice extends StatelessWidget {
  const _LoginNotice();

  @override
  Widget build(BuildContext context) => const Center(
    child: Text(
      '로그인 후 이용할 수 있어요.',
      style: TextStyle(fontSize: 13.5, color: Colors.black45),
    ),
  );
}

/// 목록이 비었을 때 — 필터 때문인지 정말 없는지 구분해서 적는다.
class HubEmptyState extends StatelessWidget {
  const HubEmptyState({super.key, required this.message, this.icon});

  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? Icons.inbox_outlined, size: 52, color: Colors.black26),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              height: 1.6,
              color: Colors.black45,
            ),
          ),
        ],
      ),
    ),
  );
}

class HubErrorState extends StatelessWidget {
  const HubErrorState({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.black26),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black45),
          ),
        ],
      ),
    ),
  );
}

/// 구획 하나가 로딩 중이거나 실패했을 때 그 자리에만 남기는 한 줄.
///
/// 곁들이 구획(이용권) 때문에 탭 전체를 스피너나 오류 화면으로 덮지 않기 위한
/// 것이다. **빈 목록으로 위장하지 않는 것**이 핵심 — 조회가 실패했는데 아무
/// 것도 안 그리면 사용자는 "이용권이 없다"는 거짓 정보를 읽는다.
class HubSectionNotice extends StatelessWidget {
  const HubSectionNotice({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 6, bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFF6F7FA),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      message,
      style: const TextStyle(fontSize: 12.5, color: Colors.black45),
    ),
  );
}

/// 한 탭 안에 성격이 다른 목록이 둘 이상 올 때 붙는 구획 제목
/// (예: 플레이스 탭의 "방문 예약"과 "이용권").
class HubSectionHeader extends StatelessWidget {
  const HubSectionHeader({super.key, required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
    child: Row(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
        const SizedBox(width: 6),
        Text(
          '$count',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: _kAccent,
          ),
        ),
      ],
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════
// 1) 파티츄 — 내가 신청한 파티
//
// parties/{id}/applications/{uid} 컬렉션 그룹이 단일 출처다(기존
// _MyJoinedPartyList와 **같은 쿼리**). 숙박+파티 패키지로 만들어진 신청은
// 공간대여 탭의 패키지 예약 카드에 한 장으로 합쳐 나오므로 여기서 뺀다.
// ═════════════════════════════════════════════════════════════════════════

class _PartyApplicationsTab extends StatelessWidget {
  const _PartyApplicationsTab({required this.status});

  final GuestStatusFilter status;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collectionGroup('applications')
          .where('uid', isEqualTo: UserSession.userId)
          .snapshots(),
      builder: (context, snapshot) {
        // 에러를 먼저 본다 — 권한/색인 문제로 스트림이 죽으면 hasData는 영원히
        // false라 스피너만 도는 무한 로딩이 된다(기존 목록과 같은 방어).
        if (snapshot.hasError) {
          logFirestoreStreamError(
            'GuestPartyApplications',
            snapshot.error,
            snapshot.stackTrace,
          );
          return const HubErrorState(
            message: '내 파티 신청을 불러오지 못했어요.\n잠시 후 다시 시도해주세요.',
          );
        }
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: _kAccent),
          );
        }

        final now = DateTime.now();
        final items =
            <({QueryDocumentSnapshot doc, GuestStatusFilter state})>[];
        for (final doc in snapshot.data!.docs) {
          final d = doc.data() as Map<String, dynamic>;
          if (d['bundleBookingId'] != null) continue;
          final state = guestStatusOfApplication(d, now);
          if (!status.matches(state)) continue;
          items.add((doc: doc, state: state));
        }

        // 진행중 → 완료 → 취소 순으로 묶고, 묶음 안에서 진행중은 가까운
        // 날짜순, 지난 것들은 최근순이다(기존 세 탭의 정렬 규칙 그대로).
        //
        // ⚠️ 정렬 방향을 `a.state`로만 고르면 안 된다 — compare(a,b)와
        // compare(b,a)가 서로 다른 기준을 쓰게 되어(a는 진행중, b는 완료인
        // 경우) 비교 함수의 대칭성이 깨지고, 상태가 섞인 목록에서 정렬 결과가
        // 들쭉날쭉해진다. 묶음을 먼저 가르고 방향은 **그 묶음** 기준으로
        // 정한다(지금은 필터가 늘 한 상태로 좁히지만, 이 방어는 남겨 둔다).
        int bucketOf(GuestStatusFilter s) => switch (s) {
          GuestStatusFilter.ongoing => 0,
          GuestStatusFilter.done => 1,
          GuestStatusFilter.cancelled => 2,
        };
        items.sort((a, b) {
          final ba = bucketOf(a.state);
          final bb = bucketOf(b.state);
          if (ba != bb) return ba.compareTo(bb);
          final da = _dateOf(a.doc);
          final db = _dateOf(b.doc);
          if (da == null && db == null) return 0;
          if (da == null) return 1;
          if (db == null) return -1;
          return ba == 0 ? da.compareTo(db) : db.compareTo(da);
        });

        if (items.isEmpty) {
          return HubEmptyState(
            icon: Icons.event_available_outlined,
            message: status == GuestStatusFilter.ongoing
                ? '신청한 파티가 없어요.\n마음에 드는 파티에 참가 신청해보세요!'
                : '${status.label} 상태인 파티 신청이 없어요.',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final doc = items[i].doc;
            final appData = doc.data() as Map<String, dynamic>;
            final partyId =
                appData['partyId'] as String? ??
                doc.reference.parent.parent?.id ??
                '';
            return _MyParticipationCard(
              key: ValueKey(doc.id),
              partyId: partyId,
              appData: appData,
              showCancelInfo: items[i].state == GuestStatusFilter.cancelled,
            );
          },
        );
      },
    );
  }

  static DateTime? _dateOf(QueryDocumentSnapshot doc) {
    final ts = (doc.data() as Map<String, dynamic>)['partyDateTime'];
    return ts is Timestamp ? ts.toDate() : null;
  }
}

// ═════════════════════════════════════════════════════════════════════════
// 2) 플레이스 — 무료 방문 예약 + 그 플레이스에서 산 이용권
//
// MyVisitReservationsScreen · MyVouchersScreen이 쓰던 스트림과 카드를 그대로
// 쓴다. 이용권은 주문 문서의 placeCollection으로 갈라, 'events'(플레이스)는
// 여기에, 'places'(공간대여)는 다음 탭에 놓는다.
// ═════════════════════════════════════════════════════════════════════════

class _PlaceGuestTab extends StatefulWidget {
  const _PlaceGuestTab({required this.status});

  final GuestStatusFilter status;

  @override
  State<_PlaceGuestTab> createState() => _PlaceGuestTabState();
}

class _PlaceGuestTabState extends State<_PlaceGuestTab> {
  @override
  Widget build(BuildContext context) {
    final uid = UserSession.userId;
    final now = DateTime.now();

    // 🎪 매장 이벤트 신청은 **곁들이 구획**이라 이 스트림이 실패해도 탭을 막지
    // 않는다(이용권과 같은 취급 — 방문 예약이 이 탭의 본체다).
    return StreamBuilder<List<PlaceEventApplication>>(
      stream: PlaceEventApplicationService.watchMyApplications(uid),
      builder: (context, eventSnap) {
        if (eventSnap.hasError) {
          logFirestoreStreamError(
            'GuestPlaceEventApplications',
            eventSnap.error,
            eventSnap.stackTrace,
          );
        }
        return _body(
          context,
          now,
          eventSnap.data ?? const <PlaceEventApplication>[],
          eventSnap.hasError,
        );
      },
    );
  }

  Widget _body(
    BuildContext context,
    DateTime now,
    List<PlaceEventApplication> myEvents,
    bool eventsFailed,
  ) {
    final uid = UserSession.userId;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: PlaceVisitReservationService.myReservations(uid).snapshots(),
      builder: (context, visitSnap) {
        return StreamBuilder<List<PlaceProductOrder>>(
          stream: PlaceProductService.watchMyOrders(),
          builder: (context, orderSnap) {
            // 방문 예약이 이 탭의 본체다 — 이게 실패하면 탭 전체가 오류다.
            if (visitSnap.hasError) {
              logFirestoreStreamError(
                'GuestPlaceVisits',
                visitSnap.error,
                visitSnap.stackTrace,
              );
              return const HubErrorState(message: '내 플레이스 예약을 불러오지 못했어요.');
            }
            if (visitSnap.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: _kAccent),
              );
            }

            final visits = PlaceVisitReservationService.sortByVisitAtDesc(
              (visitSnap.data?.docs ?? [])
                  .map(PlaceVisitReservation.fromDoc)
                  .where(
                    (r) => widget.status.matches(guestStatusOfVisit(r, now)),
                  )
                  .toList(),
            );
            // ⚠️ 이용권은 **곁들이 구획**이라 실패해도 탭을 막지 않는다.
            //
            // 예전엔 `!orderSnap.hasData`면 스피너를 돌렸는데, 스트림이 에러로
            // 끝나면 hasData는 영원히 false다 — 방문 예약이 멀쩡히 있는데도
            // 탭 전체가 무한 스피너가 된다. 실패는 감추지 않고 그 자리에만
            // 적고(빈 목록으로 위장하지 않는다), 나머지는 그대로 보여준다.
            final vouchers = orderSnap.hasData
                ? _visibleOrders(
                    orderSnap.data!,
                    rentalSide: false,
                    status: widget.status,
                  )
                : const <PlaceProductOrder>[];
            final voucherFailed = orderSnap.hasError;
            if (voucherFailed) {
              logFirestoreStreamError(
                'GuestPlaceVouchers',
                orderSnap.error,
                orderSnap.stackTrace,
              );
            }
            final voucherLoading = !orderSnap.hasData && !voucherFailed;

            // 🎪 매장 이벤트 신청 — 이용권과 같은 **곁들이 구획**이라 실패해도
            // 탭을 막지 않는다(방문 예약이 이 탭의 본체다).
            final events = myEvents
                .where(
                  (a) => widget.status.matches(
                    guestStatusOfPlaceEventApplication(a, now),
                  ),
                )
                .toList();

            if (visits.isEmpty &&
                vouchers.isEmpty &&
                events.isEmpty &&
                !voucherFailed &&
                !voucherLoading) {
              return HubEmptyState(
                icon: Icons.storefront_outlined,
                message: widget.status == GuestStatusFilter.ongoing
                    ? '플레이스 예약·이용권이 없어요.\n플레이스 상세에서 방문 예약하거나\n좌석권·입장권을 살 수 있어요.'
                    : '${widget.status.label} 상태인 플레이스 내역이 없어요.',
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                if (visits.isNotEmpty) ...[
                  HubSectionHeader(title: '🗓️ 방문 예약', count: visits.length),
                  for (final r in visits)
                    VisitReservationCard(
                      reservation: r,
                      onCancel: r.canCancel(now) ? () => _cancelVisit(r) : null,
                      onMarkDepositSent: () =>
                          PlaceVisitReservationService.markDepositSent(r.id),
                    ),
                ],
                if (voucherFailed)
                  const HubSectionNotice(message: '🎫 이용권을 불러오지 못했어요.')
                else if (voucherLoading)
                  const HubSectionNotice(message: '🎫 이용권을 불러오는 중...')
                else if (vouchers.isNotEmpty) ...[
                  HubSectionHeader(title: '🎫 이용권', count: vouchers.length),
                  for (final o in vouchers) VoucherCard(order: o),
                ],
                if (eventsFailed)
                  const HubSectionNotice(message: '🎪 매장 이벤트 신청을 불러오지 못했어요.')
                else if (events.isNotEmpty) ...[
                  HubSectionHeader(
                    title: '🎪 매장 이벤트 신청',
                    count: events.length,
                  ),
                  for (final a in events)
                    PlaceEventApplicationCard(
                      application: a,
                      accent: _kAccent,
                      onOpen: () => _openEvent(a),
                      // 취소는 살아 있는 신청에만 — 이미 무른 건은 눌러도 할
                      // 일이 없다.
                      onCancel: a.isApplied ? () => _cancelEvent(a) : null,
                    ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  /// 신청한 이벤트의 상세 시트를 연다.
  ///
  /// 목록은 신청 문서의 스냅샷만으로 그리지만, 상세는 **원본 이벤트**를 보여야
  /// 한다(사진·설명·문의 버튼이 전부 거기 있다). 그래서 이 순간에만 이벤트
  /// 문서를 한 번 읽는다 — placePromotions는 공개 읽기라 권한 문제가 없다.
  Future<void> _openEvent(PlaceEventApplication a) async {
    final promotion = await PlacePromotionService.fetch(a.eventId);
    if (!mounted) return;
    if (promotion == null) {
      // 이벤트가 지워지면 그 신청도 서버가 함께 지우므로(onPlacePromotionDeleted)
      // 보통은 여기 오지 않는다. 정리가 아직 안 닿은 잠깐 사이일 수 있다.
      _msg(context, '이벤트를 찾을 수 없어요. 호스트가 내렸을 수 있어요.');
      return;
    }
    showPlacePromotionDetailSheet(
      context,
      promotion: promotion,
      accent: _kAccent,
    );
  }

  Future<void> _cancelEvent(PlaceEventApplication a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('신청을 취소할까요?'),
        content: Text(
          '${a.eventTitle}\n다시 신청할 수 있어요.',
          style: const TextStyle(fontSize: 13.5, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('닫기'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('신청 취소', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await PlaceEventApplicationService.cancel(a.eventId);
      if (!mounted) return;
      _msg(context, '신청을 취소했어요.');
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      _msg(context, e.message ?? '취소하지 못했어요. 잠시 후 다시 시도해주세요.');
    } catch (_) {
      if (!mounted) return;
      _msg(context, '취소하지 못했어요. 잠시 후 다시 시도해주세요.');
    }
  }

  Future<void> _cancelVisit(PlaceVisitReservation r) async {
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
      _msg(context, '예약을 취소했어요.');
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      _msg(context, e.message ?? '취소하지 못했어요. 잠시 후 다시 시도해주세요.');
    } catch (_) {
      if (!mounted) return;
      _msg(context, '취소하지 못했어요. 잠시 후 다시 시도해주세요.');
    }
  }
}

/// 결제 정보가 없는 결제 대기 주문은 감춘다 — 옛 포트원 결제창을 닫은 흔적일
/// 뿐이고 서버가 곧 만료 처리한다(MyVouchersScreen과 같은 규칙).
///
/// [rentalSide]가 true면 공간대여(`places`) 주문만, false면 **그 밖의 전부**를
/// 돌려준다. "events면 플레이스"가 아니라 "places가 아니면 플레이스"로 가르는
/// 이유는 어느 한쪽에도 안 걸리는 값이 생겼을 때 주문이 두 탭 모두에서
/// 사라지지 않게 하기 위해서다 — 안 보이는 이용권은 그대로 기한이 지나버린다.
List<PlaceProductOrder> _visibleOrders(
  List<PlaceProductOrder> all, {
  required bool rentalSide,
  required GuestStatusFilter status,
}) => all
    .where(
      (o) =>
          (o.placeCollection == 'places') == rentalSide &&
          (o.status != PlaceProductOrderStatus.paymentPending ||
              o.payment != null) &&
          status.matches(guestStatusOfOrder(o)),
    )
    .toList();

void _msg(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );

// ═════════════════════════════════════════════════════════════════════════
// 3) 공간대여 — 장소대여 예약 + 숙박·파티 패키지 예약 + 장소에서 산 이용권
//
// 앞의 둘은 컬렉션만 다르고(placeReservationGroups / packageBookings) 카드와
// 결제 흐름이 완전히 같다 — MyReservationsScreen · MyPackageBookingsScreen이
// 쓰던 것과 **같은 스트림, 같은 PlaceRentalReservationCard**다.
// ═════════════════════════════════════════════════════════════════════════

class _RentalGuestTab extends StatefulWidget {
  const _RentalGuestTab({required this.status});

  final GuestStatusFilter status;

  @override
  State<_RentalGuestTab> createState() => _RentalGuestTabState();
}

class _RentalGuestTabState extends State<_RentalGuestTab> {
  @override
  Widget build(BuildContext context) {
    final uid = UserSession.userId;
    final now = DateTime.now();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: PlaceRentalReservationService.myReservations(uid).snapshots(),
      builder: (context, rentalSnap) =>
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection(RentalSource.package.collection)
                .where('requesterId', isEqualTo: uid)
                .snapshots(),
            builder: (context, packageSnap) =>
                StreamBuilder<List<PlaceProductOrder>>(
                  stream: PlaceProductService.watchMyOrders(),
                  builder: (context, orderSnap) {
                    final failed = rentalSnap.hasError
                        ? rentalSnap
                        : (packageSnap.hasError ? packageSnap : null);
                    if (failed != null) {
                      logFirestoreStreamError(
                        'GuestRentals',
                        failed.error,
                        failed.stackTrace,
                      );
                      return const HubErrorState(
                        message: '내 공간대여 예약을 불러오지 못했어요.',
                      );
                    }
                    if (!rentalSnap.hasData || !packageSnap.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(color: _kAccent),
                      );
                    }

                    final rentals =
                        PlaceRentalReservationService.sortByCreatedAtDesc(
                              rentalSnap.data!.docs.map(
                                PlaceRentalReservation.fromDoc,
                              ),
                            )
                            .where(
                              (r) => widget.status.matches(
                                guestStatusOfRental(r, now),
                              ),
                            )
                            .toList();

                    final packages =
                        PlaceRentalReservationService.sortByCreatedAtDesc(
                              packageSnap.data!.docs.map(
                                (d) => PlaceRentalReservation.fromDoc(
                                  d,
                                  source: RentalSource.package,
                                ),
                              ),
                            )
                            .where(
                              (r) => widget.status.matches(
                                guestStatusOfRental(r, now),
                              ),
                            )
                            .toList();

                    // 플레이스 탭과 같은 이유로 이용권 실패는 탭을 막지 않는다 —
                    // 예약이 멀쩡히 있는데 이용권 조회 하나 때문에 무한 스피너가
                    // 되면 안 된다(실패는 그 자리에만 적는다).
                    final vouchers = orderSnap.hasData
                        ? _visibleOrders(
                            orderSnap.data!,
                            rentalSide: true,
                            status: widget.status,
                          )
                        : const <PlaceProductOrder>[];
                    final voucherFailed = orderSnap.hasError;
                    if (voucherFailed) {
                      logFirestoreStreamError(
                        'GuestRentalVouchers',
                        orderSnap.error,
                        orderSnap.stackTrace,
                      );
                    }
                    final voucherLoading = !orderSnap.hasData && !voucherFailed;

                    if (rentals.isEmpty &&
                        packages.isEmpty &&
                        vouchers.isEmpty &&
                        !voucherFailed &&
                        !voucherLoading) {
                      return HubEmptyState(
                        icon: Icons.meeting_room_outlined,
                        message: widget.status == GuestStatusFilter.ongoing
                            ? '공간대여 예약이 없어요.\n장소대여 상세에서 룸을 예약할 수 있어요.'
                            : '${widget.status.label} 상태인 공간대여 내역이 없어요.',
                      );
                    }

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                      children: [
                        if (rentals.isNotEmpty) ...[
                          HubSectionHeader(
                            title: '🏠 장소대여 예약',
                            count: rentals.length,
                          ),
                          for (final r in rentals)
                            PlaceRentalReservationCard(
                              reservation: r,
                              onMarkDepositSent: () =>
                                  PlaceRentalReservationService.markDepositSent(
                                    r,
                                  ),
                              onCancel: () =>
                                  _cancelRental(r, isPackage: false),
                            ),
                        ],
                        if (packages.isNotEmpty) ...[
                          HubSectionHeader(
                            title: '🎁 숙박+파티 패키지',
                            count: packages.length,
                          ),
                          for (final r in packages)
                            PlaceRentalReservationCard(
                              reservation: r,
                              onMarkDepositSent: () =>
                                  PlaceRentalReservationService.markDepositSent(
                                    r,
                                  ),
                              onCancel: () => _cancelRental(r, isPackage: true),
                            ),
                        ],
                        if (voucherFailed)
                          const HubSectionNotice(message: '🎫 이용권을 불러오지 못했어요.')
                        else if (voucherLoading)
                          const HubSectionNotice(message: '🎫 이용권을 불러오는 중...')
                        else if (vouchers.isNotEmpty) ...[
                          HubSectionHeader(
                            title: '🎫 이용권',
                            count: vouchers.length,
                          ),
                          for (final o in vouchers) VoucherCard(order: o),
                        ],
                      ],
                    );
                  },
                ),
          ),
    );
  }

  /// 취소 확인 문구만 패키지 여부로 갈린다 — 패키지는 파티 참가까지 함께
  /// 풀리므로 그 사실을 반드시 먼저 알린다(MyPackageBookingsScreen과 동일).
  Future<void> _cancelRental(
    PlaceRentalReservation r, {
    required bool isPackage,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(isPackage ? '패키지 예약을 취소할까요?' : '예약을 취소할까요?'),
        content: Text(
          isPackage
              ? '숙박 예약과 파티 참가가 함께 취소돼요. 취소하면 되돌릴 수 없어요.'
              : '${r.placeName} · ${r.useLabel}\n취소하면 되돌릴 수 없어요.',
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('아니요', style: TextStyle(color: Colors.black45)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '취소하기',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final refundAmount = await PlaceRentalReservationService.cancel(
        reservation: r,
      );
      if (!mounted) return;
      _msg(
        context,
        refundAmount > 0
            ? '예약이 취소됐어요. 환불 예정 금액 ${formatPrice(refundAmount)}'
            : '예약이 취소됐어요.',
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      _msg(context, e.message ?? '취소 중 오류가 발생했습니다. 다시 시도해주세요.');
    } catch (_) {
      if (!mounted) return;
      _msg(context, '취소 중 오류가 발생했습니다. 다시 시도해주세요.');
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════
// 4) 파티크루 — 참가자 쪽에 "신청" 데이터가 없는 유일한 카테고리
//
// 구인·구직 글은 신청서를 남기지 않는다(crews 컬렉션에 applications 같은
// 하위 컬렉션이 없다). 지원·문의는 전부 채팅으로 이뤄지고, 나중에 다시 보려면
// 찜(관심 목록)을 쓴다. 그래서 여기서는 억지로 목록을 만들어내지 않고 실제
// 흐름이 있는 두 곳으로 보낸다 — 나중에 지원 데이터가 생기면 이 탭이 그
// 목록으로 바뀌는 자리다.
// ═════════════════════════════════════════════════════════════════════════

class _CrewGuestTab extends StatelessWidget {
  const _CrewGuestTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      children: [
        const Center(child: Text('🤝', style: TextStyle(fontSize: 52))),
        const SizedBox(height: 16),
        const Text(
          '파티크루는 신청서 대신 채팅으로 연결돼요',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          '구인·구직 글에서 "채팅하기"로 문의한 내역은 채팅에,\n'
          '나중에 다시 볼 글은 관심 목록에 담겨 있어요.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, height: 1.7, color: Colors.black45),
        ),
        const SizedBox(height: 22),
        _CrewShortcut(
          icon: Icons.chat_bubble_outline,
          label: '채팅으로 이동',
          onTap: () => Navigator.push(
            context,
            webFramedRoute((_) => const ChatListScreen()),
          ),
        ),
        const SizedBox(height: 10),
        _CrewShortcut(
          icon: Icons.pets,
          label: '관심 목록에서 찜한 파트너 보기',
          onTap: () => Navigator.push(
            context,
            webFramedRoute((_) => const MyFavoritesScreen()),
          ),
        ),
      ],
    );
  }
}

class _CrewShortcut extends StatelessWidget {
  const _CrewShortcut({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Icon(icon, size: 20, color: _kAccent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.black45),
          ],
        ),
      ),
    ),
  );
}

// 참가자 관점 파티 카드 — parties/{partyId} 문서를 실시간 구독해 항상 최신
// 상태(제목/사진/모집 상태 등)로 보여준다. 신청서 자체(applications 문서)는
// 신청 시점 스냅샷이라 최신 파티 정보 렌더링에는 쓰지 않고, 취소 탭에서만
// 취소 주체/환불 정보를 보여주는 데 사용한다.
class _MyParticipationCard extends StatelessWidget {
  final String partyId;
  final Map<String, dynamic> appData;
  final bool showCancelInfo;

  const _MyParticipationCard({
    super.key,
    required this.partyId,
    required this.appData,
    this.showCancelInfo = false,
  });

  static String _fmt(int v) => formatAmount(v);

  /// '📅 8월 15일(금) 회차' — 정기 파티는 같은 파티를 회차마다 신청할 수 있어
  /// 목록에 같은 파티 카드가 여러 장 뜬다. 어느 회차인지 적지 않으면 무엇이
  /// 다른 카드인지 알 수 없다(일회성 파티는 회차가 없어 그리지 않는다).
  Widget? _occurrenceRow() {
    final startAt = appData['occurrenceStartAt'];
    final occurrenceId = appData['occurrenceId'] as String?;
    if (occurrenceId == null) return null;
    const week = ['월', '화', '수', '목', '금', '토', '일'];
    final dt = startAt is Timestamp ? startAt.toDate() : null;
    final label = dt == null
        ? occurrenceId
        : '${dt.month}월 ${dt.day}일(${week[dt.weekday - 1]})';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Text(
        '📅 $label 회차',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF4ECBA7),
        ),
      ),
    );
  }

  /// '🎫 1+2차 통합권 · 1차 + 2차 · 4.5만원' / '1차 · 3만원' — 다차수 파티에서만
  /// 그린다(차수가 없는 파티는 보여줄 게 없어 null).
  Widget? _appliedScopeRow() {
    final rounds = (appData['selectedRounds'] as List?)
        ?.map((e) => (e as num?)?.toInt())
        .whereType<int>()
        .toList();
    if (rounds == null || rounds.isEmpty) return null;
    final isPackage = (appData['applicationType'] as String?) == 'package';
    final fee = (appData['appliedFee'] as num?)?.toInt();
    final roundLabel = rounds.map((n) => '$n차').join(isPackage ? ' + ' : ', ');
    final text = [
      if (isPackage)
        '🎫 ${appData['packageName'] as String? ?? '차수 패키지'} ($roundLabel)'
      else
        roundLabel,
      if (fee != null) formatPrice(fee),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isPackage ? FontWeight.w700 : FontWeight.w600,
          color: const Color(0xFFFF6FA0),
        ),
      ),
    );
  }

  /// 사진을 낸 신청이면 보호 안내를 신청 내역에서도 다시 보여준다.
  ///
  /// 낼 때 한 번 읽고 마는 것으로는 부족하다 — "내가 낸 사진이 지금 어떻게
  /// 보호되고 있는지"는 낸 뒤에 더 궁금해진다. 사진을 내지 않은 신청에는
  /// 뜨지 않는다(보호할 것이 없다).
  Widget? _photoProtectionRow() {
    final photos = appData['photos'];
    if (photos is! List || photos.isEmpty) return null;
    return const ApplicantPhotoGuestNotice(
      margin: EdgeInsets.fromLTRB(14, 0, 14, 10),
    );
  }

  /// '💳 입금대기 · 무통장입금 — 입금이 확인되면 확정돼요' 한 줄 + 무통장입금
  /// 이면 계좌·기한과 '입금했어요' 버튼까지.
  ///
  /// 신청 진행 상태(applied/approved …)와 **결제 상태는 다른 축**이라, 신청이
  /// 접수됐다고 결제가 끝난 것처럼 보이지 않게 따로 적는다. 무료 파티나 결제
  /// 정보가 없는 옛 신청에는 아무것도 그리지 않는다.
  Widget? _paymentRow() {
    final payment = PaymentInfo.fromMap(
      (appData['payment'] as Map?)?.cast<String, dynamic>(),
    );
    if (payment == null) return null;
    // 결제 상태 줄·계좌 안내·'입금했어요' 버튼은 방문예약과 **같은 위젯**을
    // 쓴다 — 부르는 서버 함수만 도메인마다 다르다.
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: DepositPanel(
        payment: payment,
        sentMessage: '입금 확인을 요청했어요. 호스트가 확인하면 확정돼요.',
        onMarkSent: () async {
          await FirebaseFunctions.instanceFor(
            region: 'asia-northeast3',
          ).httpsCallable('markPartyDepositSent').call({
            'partyId': partyId,
            // 정기 파티는 회차마다 신청·결제가 따로다 — 이 카드가 가리키는
            // 회차의 입금만 알린다(다른 회차 건은 그대로 둔다).
            'occurrenceId': ?(appData['occurrenceId'] as String?),
          });
        },
      ),
    );
  }

  /// 입장 QR — 신청이 확정되면 서버가 발급하고, 취소·거절·만료되면 그 자리에서
  /// 걷어간다(functions/partyCheckIn.js). 그래서 화면은 토큰이 있는지만 보고
  /// 유효성은 판단하지 않는다 — 실제 통과 여부는 호스트가 스캔하는 순간 서버가
  /// 원본 신청 문서를 다시 읽어 정한다.
  Widget? _qrRow(Map<String, dynamic> partyData) {
    final token = appData['checkInToken'] as String?;
    if (token == null || token.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: CheckInQrButton(
        pass: CheckInPass.fromPartyApplication(
          app: appData,
          party: partyData,
          // 호스트가 신분증과 대조하는 값이라 닉네임이 아니라 실명이다.
          personName: UserSession.name,
        ),
        label: '입장 QR 보기',
      ),
    );
  }

  Widget _cancelInfoRow() {
    final cancelledBy = appData['cancelledBy'] as String?;
    final refundAmount = (appData['refundAmount'] as num?)?.toInt();
    final refundStatus = appData['refundStatus'] as String?;
    // 서버가 자동 취소한 경우(cancelledBy: 'system')는 사유까지 밝힌다 —
    // 그냥 '취소됨'만 보이면 참가자가 이유를 알 수 없다.
    final autoLabel = PartyCancelReason.labelOf(appData);
    final byHostOrSystem = cancelledBy == 'host' || cancelledBy == 'system';
    final byLabel = autoLabel != null
        ? '최소 모집 인원 미달로 파티가 취소됐어요'
        : cancelledBy == 'host'
        ? '호스트가 파티를 취소했어요'
        : cancelledBy == 'system'
        ? '파티가 취소됐어요'
        : '내가 신청을 취소했어요';

    String refundLabel;
    if (refundStatus == 'not_applicable' || refundAmount == null) {
      refundLabel = '환불 없음';
    } else if (refundStatus == 'pending') {
      refundLabel = '환불 예정 ${_fmt(refundAmount)}';
    } else {
      refundLabel = '환불 ${_fmt(refundAmount)}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              byHostOrSystem ? Icons.info_outline : Icons.cancel_outlined,
              size: 14,
              color: Colors.black45,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                byLabel,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
            Text(
              refundLabel,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFFFF6FA0),
              ),
            ),
          ],
        ),
        // 환불이 반려된 건이면 사유와 '다시 제출' 버튼이 여기 붙는다.
        // 노출 조건 판단과 서버 호출은 전부 위젯 안에 있다.
        RefundResubmitPanel(refId: partyId, refundStatus: refundStatus),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (partyId.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('parties')
          .doc(partyId)
          .snapshots(),
      builder: (context, snapshot) {
        final partyData = snapshot.data?.data() as Map<String, dynamic>?;
        if (partyData == null) {
          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE8EBF2)),
            ),
            child: const Text(
              '파티 정보를 불러올 수 없어요 (삭제되었을 수 있어요)',
              style: TextStyle(fontSize: 13, color: Colors.black45),
            ),
          );
        }

        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            webFramedRoute((_) => PartyDetailScreen(docId: partyId)),
          ),
          child: Container(
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE8EBF2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: PartyCardBase(data: partyData),
                ),
                // 어느 회차 신청인지 — 정기 파티는 같은 파티 카드가 회차마다
                // 한 장씩 뜬다(8/15 참가·8/22 참가는 각각 별개의 신청이다).
                ?_occurrenceRow(),
                // 내가 무엇을 신청했는지 — 다차수 파티는 파티 카드만으로는
                // "1차만인지 패키지인지" 알 수 없다. 신청 시점 스냅샷을 그대로
                // 쓰므로 파티가 나중에 수정돼도 내가 산 것이 그대로 남는다.
                ?_appliedScopeRow(),
                // 제출 사진 보호 안내 — 사진을 낸 신청에만 붙는다.
                ?_photoProtectionRow(),
                // 입장 QR — 확정된 신청에만 뜬다(취소된 신청에는 QR 자체가
                // 없어졌으므로 아래 취소 안내만 남는다).
                ?_qrRow(partyData),
                // 결제 상태 — 신청은 접수됐지만 돈이 아직 안 들어온 구간
                // (입금대기/현장결제 예정)을 여기서 분명히 보여준다. 취소된
                // 신청에는 뜨지 않는다(취소 안내가 대신 뜬다).
                if (!showCancelInfo) ?_paymentRow(),
                // 💬 참여 후기 — 참여를 마친 건에만 붙는다. 자격·기한 판정은
                // 서버가 하고(functions/partyReviews.js), 이 줄은 남은 기간과
                // 버튼만 보여준다. 취소된 신청에는 뜨지 않는다.
                if (!showCancelInfo)
                  PartyReviewRow(partyId: partyId, appData: appData),
                if (showCancelInfo) ...[
                  const Divider(height: 1, color: Color(0xFFE8EBF2)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    child: _cancelInfoRow(),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

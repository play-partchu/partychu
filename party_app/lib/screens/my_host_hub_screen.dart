// ─────────────────────────────────────────────────────────────────────────────
// 👑 파티츄 호스트 — 내 등록 · 운영 · 예약관리
//
// 예전 마이페이지는 "운영 / 내 장소 / 내 파티샵 / 내 파트너 / 내 플레이스"
// 카드 다섯 개와 "장소대여 예약 관리(업주) / 방문 예약 관리(업주)" 메뉴를
// 첫 화면에 함께 늘어놓았다. 등록물과 그 등록물로 들어온 예약이 서로 다른
// 층에 흩어져 있어, 예약을 처리하려면 어느 메뉴인지부터 골라야 했다.
//
// 이 화면은 그것을 **호스트 역할 하나**로 합친다. 탭 축은 게스트 허브·메인
// 화면과 같고(파티츄 · 플레이스 · 공간대여 · 파티크루), 업주용 예약 관리는
// 해당 카테고리 탭 맨 위의 진입 줄로 들어갔다.
//
// ⚠️ 아래 목록/카드 위젯들은 my_page_screen.dart에서 **그대로 옮겨온 것**이다
// (쿼리·정렬·상태 분기·삭제 흐름 전부 동일). 새로 만든 것은 이 파일 위쪽의
// 허브 골격뿐이다.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'package:party_app/models/crew_area.dart';
import 'package:party_app/models/party_capacity_status.dart';
import 'package:party_app/models/party_gender_recruit.dart';
import 'package:party_app/models/party_occurrence_recruit.dart';
import 'package:party_app/models/payment_status.dart';
import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/models/region_data.dart';
import 'package:party_app/screens/crew_register_screen.dart';
import 'package:party_app/screens/host_refund_requests_screen.dart';
import 'package:party_app/screens/event_edit_screen.dart';
import 'package:party_app/screens/my_guest_hub_screen.dart' show MyHubTabBar;
import 'package:party_app/screens/party_edit_screen.dart';
import 'package:party_app/screens/party_register_screen.dart';
import 'package:party_app/screens/party_shop_manage_screen.dart';
import 'package:party_app/screens/place_edit_screen.dart';
// 이벤트 탭이 쓰는 **목록 본체** — 매장 이벤트 관리 화면과 같은 위젯이다.
import 'package:party_app/screens/place_event_manage_screen.dart'
    show PlaceEventManageList;
import 'package:party_app/services/party_create_eligibility.dart';
import 'package:party_app/services/place_event_entry.dart';
import 'package:party_app/screens/place_party_link_screen.dart';
import 'package:party_app/screens/place_reservation_manage_screen.dart';
import 'package:party_app/screens/place_sales_dashboard_screen.dart';
import 'package:party_app/screens/visit_reservation_manage_screen.dart';
import 'package:party_app/widgets/gender_recruit_status_field.dart';
import 'package:party_app/widgets/host/host_card_link_menus.dart';
import 'package:party_app/screens/check_in_scan_screen.dart';
import 'package:party_app/services/content_delete_service.dart'
    show DeletableContent;
import 'package:party_app/services/host_refund_service.dart';
import 'package:party_app/services/party_event_source.dart';
import 'package:party_app/services/party_shop_ownership_service.dart';
import 'package:party_app/services/place_party_link_service.dart';
import 'package:party_app/utils/applicant_identity.dart';
import 'package:party_app/utils/auto_delete_retention.dart';
import 'package:party_app/widgets/past_content_retention_notice.dart';
import 'package:party_app/utils/early_bird.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/utils/party_utils.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/application_result_dialogs.dart';
import 'package:party_app/widgets/auth_rebuilder.dart';
import 'package:party_app/widgets/delete_content_action.dart';
import 'package:party_app/widgets/occurrence_picker.dart';
import 'package:party_app/widgets/party_card_widget.dart';
import 'package:party_app/widgets/party_identity_notice.dart';
import 'package:party_app/widgets/shop_order_list.dart';
import 'package:party_app/widgets/web_frame.dart';

const Color _kBg = Color(0xFFFFF4F8);
const Color _kAccent = Color(0xFFFF6FA0);

class MyHostHubScreen extends StatefulWidget {
  const MyHostHubScreen({super.key});

  @override
  State<MyHostHubScreen> createState() => _MyHostHubScreenState();
}

class _MyHostHubScreenState extends State<MyHostHubScreen>
    with SingleTickerProviderStateMixin {
  /// 파티츄 · 이벤트 · 플레이스 · 공간대여 · 파티크루 — **다섯 개 동급**이다.
  ///
  /// 🎪 매장 이벤트는 파티의 하위 항목이 아니다(컬렉션도 `placePromotions`로
  /// 따로다). 예전에는 파티 탭 맨 위의 진입 줄로 들어갔는데, 그러면 이벤트가
  /// 파티에 딸린 것처럼 읽히고 목록·상태도 파티 탭 안에서 찾게 된다.
  late final TabController _tabController = TabController(
    length: 5,
    vsync: this,
  );

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
          '👑 파티츄 호스트',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: MyHubTabBar(
            controller: _tabController,
            // 칸이 다섯이라 가로 스크롤로 둔다(글자를 줄이거나 두 줄로 깨지
            // 않게 — MyHubTabBar 주석 참고). 게스트 허브는 그대로 넷이다.
            includeStoreEvent: true,
          ),
        ),
      ),
      body: AuthRebuilder(
        builder: (context) => TabBarView(
          controller: _tabController,
          children: const [
            // 탭마다 **한 종류만** 다룬다: 파티 탭에는 파티, 이벤트 탭에는
            // 매장 이벤트, 플레이스/공간대여 탭에는 각 등록물.
            //
            // 파티는 신청자 관리가 각 파티 카드 안에 있어(카드의 "신청자"
            // 버튼) 예약 관리 같은 줄이 필요 없다.
            _MyPartyList(),
            _MyStoreEventTab(),
            _HostTabWithOps(
              title: '플레이스 운영',
              reservationIcon: Icons.how_to_reg_outlined,
              reservationLabel: '예약 관리',
              reservationDescription: '내 플레이스로 들어온 방문 예약 승인·거절',
              reservationTarget: VisitReservationManageScreen(),
              placeCollection: 'events',
              accent: _kAccent,
              child: _MyEventList(),
            ),
            _HostTabWithOps(
              title: '공간대여 운영',
              reservationIcon: Icons.meeting_room_outlined,
              reservationLabel: '예약 관리',
              reservationDescription: '숙박·시간제·패키지 예약 승인과 입금 확인',
              reservationTarget: PlaceReservationManageScreen(),
              placeCollection: 'places',
              accent: Color(0xFF7C5CBF),
              child: _MyPlaceList(),
            ),
            _MyCrewList(),
          ],
        ),
      ),
    );
  }
}

/// 등록물 목록 위에 얹는 **운영 도구 그룹**.
///
/// 도구가 두 종류로 갈린다는 게 이 위젯의 전부다.
///
///  · **내 것 전체**(hostId) 단위 — 예약 관리. 화면 자체가 내 장소/플레이스로
///    들어온 예약을 통째로 조회하므로(PlaceReservationManageScreen ·
///    VisitReservationManageScreen) 곧바로 열면 된다. 카드마다 넣으면 같은
///    화면으로 가는 버튼이 등록물 수만큼 늘어난다.
///
///  · **한 곳(placeId)** 단위 — 판매 통계·이용권 QR 스캔. 둘 다 placeId를
///    받으므로 "어느 곳인지" 없이는 열 수 없다. 그래서 여기서는 등록물이 두 개
///    이상일 때만 선택 시트를 띄우고, 하나뿐이면 바로 연다(대부분의 업주가
///    한 곳만 운영한다 — 그 경우 탭이 하나도 늘지 않는다).
///
/// 두 도구는 `placeProducts`를 쓰는 플레이스(`events`)와 공간대여(`places`)
/// **양쪽 모두**에 있다 — 상품 문서가 `placeCollection`으로만 갈리기 때문이다
/// (event_register_screen · place_register_screen의 AppBar 액션과 같은 기능을
/// 여기로도 낸 것이고, 그 진입은 그대로 남겨 둔다).
class _HostTabWithOps extends StatelessWidget {
  const _HostTabWithOps({
    required this.title,
    required this.reservationIcon,
    required this.reservationLabel,
    required this.reservationDescription,
    required this.reservationTarget,
    required this.placeCollection,
    required this.accent,
    required this.child,
  });

  final String title;
  final IconData reservationIcon;
  final String reservationLabel;
  final String reservationDescription;
  final Widget reservationTarget;

  /// 'events'(플레이스) | 'places'(공간대여) — 선택 시트가 읽을 컬렉션.
  final String placeCollection;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.black45,
                ),
              ),
              const SizedBox(height: 8),
              // 예약 관리는 이 그룹에서 가장 자주 쓰는 도구라 한 줄을 통째로 쓴다.
              _OpsRow(
                icon: reservationIcon,
                label: reservationLabel,
                description: reservationDescription,
                accent: accent,
                onTap: () => Navigator.push(
                  context,
                  webFramedRoute((_) => reservationTarget),
                ),
              ),
              const SizedBox(height: 8),
              // 곳 단위 도구 둘은 작은 칩으로 나란히 — 카드를 새로 늘리지 않는다.
              Row(
                children: [
                  Expanded(
                    child: _OpsChip(
                      icon: Icons.insert_chart_outlined,
                      label: '판매 통계',
                      accent: accent,
                      onTap: () => _openForPlace(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _OpsChip(
                      icon: Icons.qr_code_scanner,
                      label: 'QR 체크인',
                      accent: accent,
                      onTap: () => _openCheckIn(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  /// QR 체크인 — **플레이스를 고르지 않는다.**
  ///
  /// 파티 참가권은 어느 플레이스에도 속하지 않으므로 "어느 매장인가"를 먼저
  /// 묻는 순간 통합 스캐너가 성립하지 않는다. 대신 서버가 QR마다 원본 문서의
  /// hostId로 권한을 본다(functions/checkInTokens.js).
  void _openCheckIn(BuildContext context) {
    Navigator.push(context, webFramedRoute((_) => const CheckInScanScreen()));
  }

  /// 곳 단위 도구를 연다 — 등록물이 없으면 안내, 하나면 바로, 여럿이면 선택.
  Future<void> _openForPlace(BuildContext context) async {
    final uid = UserSession.userId;
    if (uid.isEmpty) return;

    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
    try {
      // 목록과 같은 단일 조건 쿼리 — 복합 색인이 필요 없다.
      final snap = await FirebaseFirestore.instance
          .collection(placeCollection)
          .where('hostId', isEqualTo: uid)
          .get();
      docs = snap.docs;
    } catch (e, st) {
      logFirestoreStreamError('HostOpsPlacePicker($placeCollection)', e, st);
      if (!context.mounted) return;
      _snack(context, '목록을 불러오지 못했어요. 잠시 후 다시 시도해주세요.');
      return;
    }

    if (!context.mounted) return;
    if (docs.isEmpty) {
      _snack(
        context,
        placeCollection == 'places'
            ? '등록한 장소가 없어요. 장소를 먼저 등록해주세요.'
            : '등록한 플레이스가 없어요. 플레이스를 먼저 등록해주세요.',
      );
      return;
    }

    final picked = docs.length == 1
        ? docs.first
        : await _pickPlace(context, docs);
    if (picked == null || !context.mounted) return;

    final name = picked.data()['name'] as String? ?? '내 플레이스';
    Navigator.push(
      context,
      webFramedRoute(
        (_) => PlaceSalesDashboardScreen(
          placeId: picked.id,
          placeName: name,
          accent: accent,
        ),
      ),
    );
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _pickPlace(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return showModalBottomSheet<QueryDocumentSnapshot<Map<String, dynamic>>>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            const Text(
              '어느 곳의 운영 도구를 열까요?',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: docs.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 16, endIndent: 16),
                itemBuilder: (_, i) {
                  final d = docs[i].data();
                  final rawAddress =
                      d['address'] as String? ?? d['location'] as String? ?? '';
                  return ListTile(
                    title: Text(
                      d['name'] as String? ?? '(이름 없음)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: rawAddress.isEmpty
                        ? null
                        : Text(
                            RegionData.shortDistrictDong(rawAddress),
                            style: const TextStyle(fontSize: 12),
                          ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Colors.black45,
                    ),
                    onTap: () => Navigator.pop(ctx, docs[i]),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static void _snack(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
      );
}

/// 등록물 목록이 조회에 실패했을 때의 화면.
///
/// 이 분기가 없으면 스트림이 에러로 끝나도 hasData는 영원히 false라 화면이
/// **영구 스피너**가 된다 — 등록한 게 없어서 비어 있는 건지, 조회가 죽은
/// 건지 사용자가 구분할 수 없다(실제로 파티크루 목록이 그 상태였다).
class _HostListError extends StatelessWidget {
  const _HostListError({required this.message});

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

/// 최신 등록순 — 서버 orderBy 대신 여기서 정렬해 복합 색인을 없앤다.
///
/// `where('hostId') + orderBy('createdAt')`는 컬렉션마다 복합 색인을 요구하고,
/// 색인이 없으면 스트림이 통째로 FAILED_PRECONDITION으로 죽는다. 목록 하나당
/// 문서 수가 많아야 수십 개라 클라이언트 정렬로 충분하다.
List<QueryDocumentSnapshot> _sortedByCreatedAtDesc(
  List<QueryDocumentSnapshot> docs,
) {
  final sorted = List<QueryDocumentSnapshot>.from(docs);
  sorted.sort((a, b) {
    final at = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
    final bt = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
    if (at == null && bt == null) return 0;
    if (at == null) return 1;
    if (bt == null) return -1;
    return bt.compareTo(at);
  });
  return sorted;
}

/// 운영 그룹의 큰 줄 — 아이콘 + 제목 + 설명 + 화살표.
class _OpsRow extends StatelessWidget {
  const _OpsRow({
    required this.icon,
    required this.label,
    required this.description,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accent.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(icon, size: 20, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Colors.black45,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20, color: Colors.black45),
            ],
          ),
        ),
      ),
    );
  }
}

/// 운영 그룹의 작은 칩 — 곳 단위 도구(판매 통계 · QR 스캔)용.
class _OpsChip extends StatelessWidget {
  const _OpsChip({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF6F7FA),
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// 🛍️ 파티샵 — 위 네 카테고리와 성격이 달라 탭에 넣지 않는다.
//
// 파티샵은 "등록해서 예약을 받는" 것이 아니라 **상품을 팔고 사는** 마켓이라
// 구매(내가 산 것)와 판매(내 샵으로 들어온 주문)라는 다른 축을 갖는다. 그
// 축을 카테고리 탭에 억지로 끼우면 게스트/호스트 어느 쪽에 넣어도 반쪽만
// 담긴다. 그래서 내 파티샵(운영) · 구매 · 판매를 한 화면에 모아 둔다.
//
// ── 누구에게 무엇을 보여주는가 ────────────────────────────────────────
// 구매는 누구나 하지만 판매는 **파티샵을 실제로 등록한 사람만** 한다. 그래서
// 화면을 두 모양으로 나눈다.
//   · 파티샵 보유 → [내 파티샵 · 구매 · 판매] 세 탭
//   · 그 외(비로그인·일반 사용자·파티/플레이스/장소대여 호스트) → 탭 없이
//     구매 목록 하나
// 판매자가 아닌 사람에게 '내 파티샵'과 '판매'는 **비활성이 아니라 아예 없다**
// — 영원히 빈 목록일 탭을 남겨 둘 이유가 없다. 판정은 역할이 아니라 실제
// `partyShops` 문서 보유 여부로 하며, 그 규칙은
// [PartyShopOwnershipService]에 한 곳으로 모아 두었다.
// ═════════════════════════════════════════════════════════════════════════

class MyShopHubScreen extends StatefulWidget {
  const MyShopHubScreen({super.key});

  @override
  State<MyShopHubScreen> createState() => _MyShopHubScreenState();
}

class _MyShopHubScreenState extends State<MyShopHubScreen> {
  @override
  Widget build(BuildContext context) {
    // 로그인/로그아웃이 즉시 반영되도록 AuthRebuilder가 가장 바깥이다 —
    // 판매자 판정 스트림도 로그인한 uid로 다시 걸려야 한다.
    return AuthRebuilder(
      builder: (context) => StreamBuilder<bool>(
        stream: PartyShopOwnershipService.watch(),
        // 직전에 알던 값이 있으면 첫 프레임부터 같은 모양으로 그린다 —
        // 판매자가 열 때마다 탭이 뒤늦게 붙는 깜빡임을 막는다. 모르면
        // 구매 목록만(= 판매자가 아닌 쪽)으로 시작한다.
        initialData: PartyShopOwnershipService.cached(),
        builder: (context, snap) => ShopHubView(isSeller: snap.data == true),
      ),
    );
  }
}

/// 파티샵 허브의 **화면 본체** — 판매자 여부만 받아 그린다.
///
/// 판정([PartyShopOwnershipService])과 화면을 나눠 둔 이유는, "판매자에게만
/// 보인다"가 조건문 한 줄에 묻히면 다음에 탭을 하나 더 붙일 때 슬그머니
/// 어긋나기 때문이다. 여기는 받은 값대로 그리기만 하고, 무엇이 판매자인지는
/// 서비스 한 곳에서만 정한다(테스트도 두 축을 따로 건다).
class ShopHubView extends StatelessWidget {
  const ShopHubView({super.key, required this.isSeller});

  /// 파티샵을 실제로 보유했는가 — true일 때만 '내 파티샵'·'판매'가 존재한다.
  final bool isSeller;

  @override
  Widget build(BuildContext context) => isSeller ? _seller() : _buyer();

  /// 파티샵을 보유한 판매자 — 내 파티샵 · 구매 · 판매.
  Widget _seller() {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: _kBg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: Colors.black87,
          title: const Text(
            '🛍️ 파티샵',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          bottom: const TabBar(
            labelColor: _kAccent,
            unselectedLabelColor: Colors.black45,
            indicatorColor: _kAccent,
            labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            unselectedLabelStyle: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            tabs: [
              Tab(text: '내 파티샵'),
              Tab(text: '구매'),
              Tab(text: '판매'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _MyShopList(),
            ShopOrderList(asSeller: false),
            ShopOrderList(asSeller: true),
          ],
        ),
      ),
    );
  }

  /// 파티샵이 없는 사용자 — 구매 목록 하나. 탭바 자체를 만들지 않는다(비활성
  /// 탭으로 남겨 두면 "언젠가 열리는 메뉴"처럼 보인다). 구매 이력이 0건이어도
  /// 이 화면은 그대로 열리고 빈 목록 안내가 뜬다.
  Widget _buyer() {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text(
          '🛍️ 파티샵 구매 목록',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
      body: const ShopOrderList(asSeller: false),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 내 파티 탭
// ─────────────────────────────────────────────────────────────────────────────

class _MyPartyList extends StatefulWidget {
  const _MyPartyList();

  @override
  State<_MyPartyList> createState() => _MyPartyListState();
}

class _MyPartyListState extends State<_MyPartyList>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // '지난 파티' 탭으로 넘어가는 순간 자동 삭제 안내를 한 번 띄운다
    // ([PastContentRetentionNotice] — 3일 유예는 그쪽이 기억한다).
    // 탭 애니메이션 도중에도 리스너가 불리므로 전환이 끝난 뒤에만 본다.
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    if (_tabController.index != 1) return;
    PastContentRetentionNotice.maybeShow(context, PastContentKind.party);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  // 정기 파티는 "다음 회차"가 이 파티의 날짜다 — 남은 회차가 있는 동안은
  // 진행 중 탭에 머무르고, 운영 종료일이 지나면 지난 파티로 내려간다.
  static DateTime? _parseDate(Map<String, dynamic> d) =>
      PartyCard.parsePartyDateTime(d);

  /// 💸 **환불 처리** 진입 — 게스트의 환불계좌를 확인하는 유일한 자리.
  ///
  /// 무통장입금 참가비는 파티츄가 아니라 호스트 계좌로 바로 들어가므로,
  /// 돌려주는 것도 호스트가 자기 계좌에서 손으로 보낸다. 그때 필요한
  /// **참가자 환불계좌**는 취소 시점에 서버가 요청 문서에 박아 둔 사본이고
  /// ([HostRefundRequestsScreen]이 그 값을 보여주고 복사까지 한다), 이 화면은
  /// 규칙상 `hostId == 나`인 요청만 읽는다 — 남의 게스트 계좌는 보이지 않는다.
  ///
  /// 여기 문을 내는 이유: 지금까지 이 화면은 마이페이지의 조건부 한 줄
  /// (처리할 건이 있을 때만)로만 들어갈 수 있었다. 정작 취소·환불을 다루는
  /// 자리는 호스트 허브라, 계좌를 보려면 화면을 나갔다 다시 들어와야 했다.
  ///
  /// 처리할 건이 **없으면 그리지 않는다** — 상시 노출하면 참가자 계좌를 보는
  /// 문이 늘 열려 있는 셈이 되고, 대부분의 날에는 빈 화면으로 가는 줄이 된다.
  Widget _refundEntry(BuildContext context) => StreamBuilder<int>(
    stream: HostRefundService.watchPendingCount(),
    builder: (context, snap) {
      final pending = snap.data ?? 0;
      if (pending <= 0) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: _OpsRow(
          icon: Icons.assignment_return_outlined,
          label: '환불 처리 $pending건',
          description: '참가자 환불계좌 확인 · 송금 후 완료 표시',
          accent: const Color(0xFFE2568A),
          onTap: () => Navigator.push(
            context,
            webFramedRoute((_) => const HostRefundRequestsScreen()),
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    // 로그인 화면에서 로그인을 마치고 돌아왔을 때 뒤로 갔다 다시 들어오지
    // 않아도 즉시 로그인 상태가 반영되도록 AuthRebuilder로 감싼다.
    return AuthRebuilder(builder: _buildLoggedGate);
  }

  Widget _buildLoggedGate(BuildContext context) {
    final userId = UserSession.userId;

    if (userId.isEmpty) {
      return const Center(
        child: Text('로그인 후 이용 가능합니다.', style: TextStyle(color: Colors.black45)),
      );
    }

    return Column(
      children: [
        _refundEntry(context),
        TabBar(
          controller: _tabController,
          labelColor: const Color(0xFFFF6FA0),
          unselectedLabelColor: Colors.black45,
          indicatorColor: const Color(0xFFFF6FA0),
          indicatorWeight: 2,
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          tabs: const [
            Tab(text: '진행 중인 파티'),
            Tab(text: '지난 파티'),
          ],
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('parties')
                .where('hostId', isEqualTo: userId)
                .snapshots(),
            builder: (context, snapshot) {
              // 참가 목록과 같은 이유로 에러를 먼저 본다 — 이 화면의 쿼리는
              // 색인이 필요 없지만, 에러 분기가 없으면 어떤 이유로든 스트림이
              // 실패했을 때 무한 로딩으로 보이는 건 똑같다.
              if (snapshot.hasError) {
                logFirestoreStreamError(
                  'MyPartyList',
                  snapshot.error,
                  snapshot.stackTrace,
                );
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 48,
                          color: Colors.black26,
                        ),
                        SizedBox(height: 12),
                        Text(
                          '내 파티 목록을 불러오지 못했어요.\n잠시 후 다시 시도해주세요.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black45),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFFFF6FA0)),
                );
              }

              final now = DateTime.now();
              final activeDocs = <QueryDocumentSnapshot>[];
              final pastDocs = <QueryDocumentSnapshot>[];

              for (final doc in snapshot.data!.docs) {
                final d = doc.data() as Map<String, dynamic>;
                // 삭제된 파티는 표시하지 않음 (hard delete 이후 남은 soft-delete 문서 방어)
                if (d['isDeleted'] == true || d['status'] == 'deleted') {
                  continue;
                }
                final dt = _parseDate(d);
                // 정기 파티는 남은 회차가 없으면(운영 종료일 경과) 지난 파티다.
                // 그 외 날짜를 못 읽는 문서는 기존대로 진행 중에 남긴다.
                final recurringEnded =
                    dt == null && PartySchedule.isRecurring(d);
                if (!recurringEnded && (dt == null || !dt.isBefore(now))) {
                  activeDocs.add(doc);
                } else {
                  pastDocs.add(doc);
                }
              }

              // 진행 중: 가까운 날짜순
              activeDocs.sort((a, b) {
                final da = _parseDate(a.data() as Map<String, dynamic>);
                final db = _parseDate(b.data() as Map<String, dynamic>);
                if (da == null && db == null) return 0;
                if (da == null) return 1;
                if (db == null) return -1;
                return da.compareTo(db);
              });

              // 지난 파티: 최근 종료순
              pastDocs.sort((a, b) {
                final da = _parseDate(a.data() as Map<String, dynamic>);
                final db = _parseDate(b.data() as Map<String, dynamic>);
                if (da == null && db == null) return 0;
                if (da == null) return 1;
                if (db == null) return -1;
                return db.compareTo(da);
              });

              return TabBarView(
                controller: _tabController,
                // 바깥 카테고리 탭(파티츄/플레이스/공간대여/파티크루)도 좌우
                // 드래그로 전환되는 TabBarView라, 이 안쪽 상태 탭까지 드래그를
                // 받으면 같은 제스처를 둘이 경합해 안쪽이 이겨버린다 — 그러면
                // 카테고리를 드래그로 넘길 수 없다. 안쪽은 탭(클릭) 전환만
                // 두고 드래그는 항상 바깥 카테고리 전용으로 남긴다
                // (main_screen.dart의 파티크루 구인/구직 탭과 같은 처리).
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _PartyTabList(
                    docs: activeDocs,
                    emptyIcon: Icons.event_available_outlined,
                    emptyMessage: '진행 중인 파티가 없어요',
                  ),
                  _PartyTabList(
                    docs: pastDocs,
                    emptyIcon: Icons.event_busy_outlined,
                    emptyMessage: '지난 파티가 없어요',
                    isPast: true,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 🎪 이벤트 탭 — 내가 등록한 매장 이벤트(placePromotions) 전부
// ─────────────────────────────────────────────────────────────────────────────

/// 파티츄 호스트의 **이벤트 탭**.
///
/// 파티와 같은 급의 칸이다 — 매장 이벤트는 파티의 하위 항목이 아니라 내
/// 플레이스가 여는 별개의 콘텐츠이고, 저장 컬렉션도 `placePromotions`로 따로다.
///
/// ── 여기서 새로 만드는 것은 없다 ──────────────────────────────────────────
/// 목록·상태 배지·수정·종료/다시 노출·삭제·신청자 수는 전부
/// [PlaceEventManageList]가 그대로 한다(관리 화면이 쓰는 바로 그 위젯이다).
/// 어느 플레이스의 이벤트인지 고르는 순서와 등록 폼도 등록 화면과 같은
/// [PlaceEventEntry] 하나를 지난다. 이 탭이 더하는 것은 **내 플레이스를 모아
/// 이어 붙이는 것**뿐이고, 그 목록조차 기존 [PlaceEventEntry.myPlaces]다.
///
/// 이벤트를 호스트 단위로 한 번에 읽는 쿼리는 만들지 않았다 — `placePromotions`
/// 에는 hostId 색인이 없고, 플레이스마다 이미 있는 `watchForPlace` 스트림을
/// 그대로 쓰면 색인도 규칙도 건드릴 일이 없다(플레이스는 대개 한두 곳이다).
class _MyStoreEventTab extends StatefulWidget {
  const _MyStoreEventTab();

  @override
  State<_MyStoreEventTab> createState() => _MyStoreEventTabState();
}

class _MyStoreEventTabState extends State<_MyStoreEventTab> {
  /// 이벤트를 붙일 수 있는 내 플레이스(매장·즐길거리 + 공간대여·숙박).
  ///
  /// 이벤트 자체는 아래 [PlaceEventManageList]가 실시간으로 듣는다 — 여기서
  /// 다시 읽는 것은 "플레이스가 늘었나"뿐이라 Future 한 번이면 충분하다.
  late Future<List<EventPlaceTarget>> _places = PlaceEventEntry.myPlaces();

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() => _places = PlaceEventEntry.myPlaces());
  }

  /// 이벤트 등록 — 플레이스가 없으면 안내, 하나면 그대로, 여럿이면 고르게
  /// 하는 순서까지 전부 공용 진입점이 한다.
  Future<void> _register() async {
    await PlaceEventEntry.startRegister(context);
    // 등록하면서 플레이스를 새로 만들고 왔을 수 있다.
    await _reload();
  }

  @override
  Widget build(BuildContext context) =>
      AuthRebuilder(builder: _buildLoggedGate);

  Widget _buildLoggedGate(BuildContext context) {
    if (UserSession.userId.isEmpty) {
      return const Center(
        child: Text('로그인 후 이용 가능합니다.', style: TextStyle(color: Colors.black45)),
      );
    }

    return FutureBuilder<List<EventPlaceTarget>>(
      future: _places,
      builder: (context, snap) {
        if (snap.hasError) {
          return const _HostListError(
            message: '이벤트를 불러오지 못했어요.\n잠시 후 다시 시도해주세요.',
          );
        }
        if (!snap.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: _kAccent),
          );
        }
        final places = snap.data!;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: _OpsRow(
                icon: Icons.add_circle_outline,
                label: '매장 이벤트 등록',
                description: '공연·DJ·시음처럼 매장에서 여는 소식을 올려요',
                accent: _kAccent,
                onTap: _register,
              ),
            ),
            Expanded(
              child: places.isEmpty
                  ? _needPlace()
                  : RefreshIndicator(
                      onRefresh: _reload,
                      color: _kAccent,
                      // 플레이스마다 목록 하나. 스크롤은 바깥이 맡고 안쪽은
                      // 펼치기만 한다(shrinkWrap).
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [
                          for (final p in places)
                            PlaceEventManageList(
                              key: ValueKey(
                                '${p.placeCollection}/${p.placeId}',
                              ),
                              placeId: p.placeId,
                              placeCollection: p.placeCollection,
                              hostId: p.hostId,
                              placeName: p.placeName,
                              accent: p.accent,
                              shrinkWrap: true,
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  /// 플레이스가 없으면 이벤트를 만들 수도, 관리할 수도 없다 — 폼으로 보내지
  /// 않고 무엇이 먼저인지만 말한다(등록 버튼을 누르면 공용 안내 시트가 뜬다).
  Widget _needPlace() => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('✨', style: TextStyle(fontSize: 34)),
          const SizedBox(height: 12),
          const Text(
            '아직 등록한 플레이스가 없어요',
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            '매장 이벤트는 내 플레이스가 여는 행사예요.\n'
            '플레이스를 먼저 등록하면 여기서 이벤트를 관리할 수 있어요.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.black45,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _register,
            style: TextButton.styleFrom(foregroundColor: _kAccent),
            child: const Text(
              '이벤트 등록 시작하기',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ),
  );
}

class _PartyTabList extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;
  final IconData emptyIcon;
  final String emptyMessage;
  final bool isPast;

  const _PartyTabList({
    required this.docs,
    required this.emptyIcon,
    required this.emptyMessage,
    this.isPast = false,
  });

  // 지난 파티 탭 상단에 항상 표시되는 안내 배너.
  //
  // 보관기간은 [AutoDeleteRetention.window] 하나가 정본이다 — 문구에 숫자를
  // 직접 적으면 정책이 바뀔 때 안내만 옛날 값으로 남는다(실제로 30일이던
  // 시절의 문구가 그랬다).
  static Widget _pastWarningBanner() => Container(
    margin: const EdgeInsets.fromLTRB(0, 0, 0, 12),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF3E0),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFFFCC80)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          size: 16,
          color: Color(0xFFE65100),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '지난 파티는 마지막 회차가 끝난 날로부터 '
            '${AutoDeleteRetention.window.inDays}일간 보관되며, '
            '지나면 자동으로 삭제됩니다. '
            '결제·정산 기록은 파티가 삭제돼도 그대로 남아요.',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFFBF360C),
              height: 1.5,
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty) {
      return Column(
        children: [
          if (isPast)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _pastWarningBanner(),
            ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(emptyIcon, size: 56, color: Colors.black26),
                  const SizedBox(height: 12),
                  Text(
                    emptyMessage,
                    style: const TextStyle(color: Colors.black45),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // 배너를 index 0으로, 파티 카드를 index 1~N으로 처리
    final itemCount = isPast ? docs.length + 1 : docs.length;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: itemCount,
      itemBuilder: (_, i) {
        if (isPast && i == 0) return _pastWarningBanner();
        final cardIndex = isPast ? i - 1 : i;
        final doc = docs[cardIndex];
        final data = doc.data() as Map<String, dynamic>;
        return _MyPartyCard(
          key: ValueKey(doc.id),
          docId: doc.id,
          data: data,
          isPast: isPast,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 내 장소 탭
// ─────────────────────────────────────────────────────────────────────────────

class _MyPlaceList extends StatefulWidget {
  const _MyPlaceList();

  @override
  State<_MyPlaceList> createState() => _MyPlaceListState();
}

class _MyPlaceListState extends State<_MyPlaceList>
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
    // 로그인 화면에서 로그인을 마치고 돌아왔을 때 뒤로 갔다 다시 들어오지
    // 않아도 즉시 로그인 상태가 반영되도록 AuthRebuilder로 감싼다.
    return AuthRebuilder(builder: _buildLoggedGate);
  }

  Widget _buildLoggedGate(BuildContext context) {
    final userId = UserSession.userId;

    if (userId.isEmpty) {
      return const Center(
        child: Text('로그인 후 이용 가능합니다.', style: TextStyle(color: Colors.black45)),
      );
    }

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF7C5CBF),
          unselectedLabelColor: Colors.black45,
          indicatorColor: const Color(0xFF7C5CBF),
          indicatorWeight: 2,
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          tabs: const [
            Tab(text: '진행중'),
            Tab(text: '숨김'),
          ],
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            // ⚠️ orderBy('createdAt')를 where('hostId')와 함께 쓰면 복합
            // 색인이 필요한데, 색인이 없으면 이 스트림은 에러로 끝난다 —
            // 마이페이지 "내 장소 N개" 카운트(같은 파일 위쪽)는 orderBy 없이
            // hostId 조건만 쓰기 때문에 이 색인 문제의 영향을 받지 않고
            // 항상 성공하므로, 두 값이 달라 보이는 원인 중 하나였다. 정렬은
            // 서버가 아니라 데이터를 받은 뒤 클라이언트에서 직접 하는 걸로
            // 바꿔 복합 색인 자체가 필요 없게 만든다(파티 목록과 동일한 패턴).
            stream: FirebaseFirestore.instance
                .collection('places')
                .where('hostId', isEqualTo: userId)
                .snapshots(),
            builder: (context, snapshot) {
              debugPrint(
                '[MyPlaceList] connectionState=${snapshot.connectionState} '
                'hasData=${snapshot.hasData} hasError=${snapshot.hasError} '
                'error=${snapshot.error} '
                'docs.length=${snapshot.data?.docs.length}',
              );

              if (snapshot.hasError) {
                logFirestoreStreamError(
                  'MyPlaceList',
                  snapshot.error,
                  snapshot.stackTrace,
                );
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 48,
                          color: Colors.black26,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '내 장소 목록을 불러오지 못했어요.\n잠시 후 다시 시도해주세요.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black45),
                        ),
                      ],
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
                  final aTime =
                      (a.data() as Map<String, dynamic>)['createdAt']
                          as Timestamp?;
                  final bTime =
                      (b.data() as Map<String, dynamic>)['createdAt']
                          as Timestamp?;
                  if (aTime == null && bTime == null) return 0;
                  if (aTime == null) return 1;
                  if (bTime == null) return -1;
                  return bTime.compareTo(aTime);
                });

              final activeDocs = <QueryDocumentSnapshot>[];
              final hiddenDocs = <QueryDocumentSnapshot>[];

              for (final doc in docs) {
                final d = doc.data() as Map<String, dynamic>;
                // isActive == false 만 숨김; null 또는 true → 진행중
                if (d['isActive'] == false) {
                  hiddenDocs.add(doc);
                } else {
                  activeDocs.add(doc);
                }
              }

              return TabBarView(
                controller: _tabController,
                // 바깥 카테고리 탭(파티츄/플레이스/공간대여/파티크루)도 좌우
                // 드래그로 전환되는 TabBarView라, 이 안쪽 상태 탭까지 드래그를
                // 받으면 같은 제스처를 둘이 경합해 안쪽이 이겨버린다 — 그러면
                // 카테고리를 드래그로 넘길 수 없다. 안쪽은 탭(클릭) 전환만
                // 두고 드래그는 항상 바깥 카테고리 전용으로 남긴다
                // (main_screen.dart의 파티크루 구인/구직 탭과 같은 처리).
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _PlaceTabList(
                    docs: activeDocs,
                    emptyIcon: Icons.store_mall_directory_outlined,
                    emptyMessage: '진행중인 장소가 없어요',
                  ),
                  _PlaceTabList(
                    docs: hiddenDocs,
                    emptyIcon: Icons.store_outlined,
                    emptyMessage: '숨긴 장소가 없어요',
                    isHidden: true,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PlaceTabList extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;
  final IconData emptyIcon;
  final String emptyMessage;
  final bool isHidden;

  const _PlaceTabList({
    required this.docs,
    required this.emptyIcon,
    required this.emptyMessage,
    this.isHidden = false,
  });

  // 숨김 탭 상단에 항상 표시되는 안내 배너 — 파티의 "지난 파티" 배너와 같은
  // 문구 규칙이고, 보관기간도 이제 **같은 상수**를 읽는다
  // ([AutoDeleteRetention.window], 14일). 예전에는 여기만 30일이라 호스트가
  // 화면마다 다른 기간을 읽었다.
  static Widget _hiddenWarningBanner() => Container(
    margin: const EdgeInsets.fromLTRB(0, 0, 0, 12),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF3E0),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFFFCC80)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          size: 16,
          color: Color(0xFFE65100),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '숨긴 장소는 숨김 처리일로부터 '
            '${AutoDeleteRetention.window.inDays}일간 보관되며, '
            '지나면 자동으로 삭제됩니다. 다시 노출하면 삭제되지 않아요.',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFFBF360C),
              height: 1.5,
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty) {
      return Column(
        children: [
          if (isHidden)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _hiddenWarningBanner(),
            ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(emptyIcon, size: 56, color: Colors.black26),
                  const SizedBox(height: 12),
                  Text(
                    emptyMessage,
                    style: const TextStyle(color: Colors.black45),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // 배너를 index 0으로, 장소 카드를 index 1~N으로 처리
    final itemCount = isHidden ? docs.length + 1 : docs.length;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: itemCount,
      itemBuilder: (_, i) {
        if (isHidden && i == 0) return _hiddenWarningBanner();
        final cardIndex = isHidden ? i - 1 : i;
        final doc = docs[cardIndex];
        final data = doc.data() as Map<String, dynamic>;
        return _MyPlaceCard(docId: doc.id, data: data, isHidden: isHidden);
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 파티 카드
// ─────────────────────────────────────────────────────────────────────────────

class _MyPartyCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final bool isPast;

  const _MyPartyCard({
    super.key,
    required this.docId,
    required this.data,
    this.isPast = false,
  });

  /// 모집 상태 변경 시트 — **전체 상태**(모집중/마감/취소)와 **성별별
  /// 모집**(남성 모집 / 여성 모집)을 한 자리에서 정한다.
  ///
  /// 두 값의 관계는 파티 수정 화면과 완전히 같다([GenderRecruitStatusField]):
  /// 전체 상태가 먼저이고, 성별 스위치는 전체가 '모집중'일 때만 뜻이 있다.
  /// 그래서 전체를 마감/취소로 고르면 성별 스위치는 잠긴다.
  ///
  /// ## 회차가 여럿인 정기 파티는 **날짜부터 고른다**
  ///
  /// 정기 파티는 문서 하나가 모든 회차를 담아서, 예전에는 여기서 고른 값이
  /// 모든 회차에 함께 걸렸다(9/6만 마감하려 해도 8/30·9/13까지 닫혔다).
  /// 지금은 실제 회차 날짜만 살아 있는 달력에서 여러 날을 고르고
  /// ([showHostOccurrenceStatusPicker]), 고른 회차에만 값을 적는다
  /// ([PartyOccurrenceRecruit]).
  ///
  /// 날짜가 하나뿐인 파티(일회성·날짜 슬롯 게시글·회차가 하나 남은 정기 파티)는
  /// 달력 단계를 건너뛰고 예전처럼 곧바로 상태를 고친다.
  Future<void> _changeStatus(BuildContext context) async {
    const statuses = ['모집중', '마감', '취소'];

    // ── 1단계: 어느 회차에 적용할지 ──────────────────────────────────────
    //
    // 비어 있으면 예전 그대로 **문서 전체**에 적용한다(일회성 파티와 날짜
    // 슬롯 게시글 — 그쪽은 날짜마다 문서가 따로라 이 카드 자체가 그 날짜다).
    var targetIds = <String>[];
    if (PartyOccurrenceRecruit.supports(data)) {
      final days = PartySchedule.occurrenceDays(data);
      if (days.length >= 2) {
        final pickedDates = await showHostOccurrenceStatusPicker(
          context: context,
          days: days,
          // 처음에는 아무것도 고르지 않는다 — 눌러서 고른 날짜에만 적용된다는
          // 것이 이 화면의 약속이라, 미리 골라 두면 실수로 다른 날까지 바뀐다.
          initialIds: const {},
          statusLabelOf: (id) =>
              PartyOccurrenceRecruit.shortLabelOf(data, occurrenceId: id),
        );
        if (pickedDates == null || pickedDates.isEmpty) return;
        targetIds = pickedDates.toList()..sort();
      } else if (days.length == 1) {
        // 남은 회차가 하나뿐 — 달력을 한 단계 더 보여줄 이유가 없다.
        targetIds = [occurrenceIdOf(days.first)];
      }
    }

    // 달력을 거쳐 왔으면 그 사이에 화면이 사라졌을 수 있다.
    if (!context.mounted) return;

    // ── 2단계: 그 회차(들)의 현재 값 ─────────────────────────────────────
    //
    // 여러 날을 골랐고 값이 서로 다르면 null(= 혼합)이다. 혼합일 때 아무
    // 값이나 켜 두면 "저장을 누르는 순간 안 고른 날까지 그 값이 되는" 화면이
    // 되므로, **호스트가 실제로 바꾼 항목만** 저장한다(아래 touched).
    final scoped = targetIds.isNotEmpty;
    final current = scoped
        ? PartyOccurrenceRecruit.commonStatusOf(data, targetIds)
        : data['recruitStatus'] as String? ?? '모집중';
    final currentMaleClosed = scoped
        ? PartyOccurrenceRecruit.commonMaleClosedOf(data, targetIds)
        : PartyGenderRecruit.isMaleClosed(data);
    final currentFemaleClosed = scoped
        ? PartyOccurrenceRecruit.commonFemaleClosedOf(data, targetIds)
        : PartyGenderRecruit.isFemaleClosed(data);
    final currentMaleOpen = currentMaleClosed == null
        ? null
        : !currentMaleClosed;
    final currentFemaleOpen = currentFemaleClosed == null
        ? null
        : !currentFemaleClosed;
    final scopeLabel = !scoped
        ? null
        : targetIds.length == 1
        ? occurrenceLabel(targetIds.first)
        : '${occurrenceLabel(targetIds.first)} 외 ${targetIds.length - 1}일';

    final picked =
        await showModalBottomSheet<
          ({String? status, bool? male, bool? female})
        >(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (sheetContext) {
            // null = 고른 날짜들의 값이 서로 다름(혼합). 호스트가 손대기
            // 전까지 그대로 두고, **손댄 항목만** 저장한다.
            var status = current;
            var maleOpen = currentMaleOpen;
            var femaleOpen = currentFemaleOpen;
            final mixed =
                current == null ||
                currentMaleOpen == null ||
                currentFemaleOpen == null;
            return StatefulBuilder(
              builder: (_, setSheetState) => SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '모집 상태 변경',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      // 어느 날짜에 적용되는지 — 회차를 고른 경우에만.
                      if (scopeLabel != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '$scopeLabel에 적용돼요',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFFF6FA0),
                            ),
                          ),
                        ),
                      if (mixed)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            '고른 날짜의 상태가 서로 달라요. 바꾼 항목만 모든 날짜에 적용됩니다.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      ...statuses.map(
                        (s) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(s == '마감' ? '마감 (전체 모집마감)' : s),
                          leading: Icon(
                            s == status
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: s == status ? Colors.black : Colors.black38,
                          ),
                          onTap: () => setSheetState(() => status = s),
                        ),
                      ),
                      const Divider(height: 20),
                      GenderRecruitStatusField(
                        // 혼합이면 켜 둔 것처럼 보이지 않게 **꺼짐**에서
                        // 시작하지 않는다 — 호스트가 누른 값만 저장되므로,
                        // 여기 보이는 초기 모양은 저장 결과에 영향을 주지
                        // 않는다(위 안내 문구가 그 사실을 알린다).
                        maleOpen: maleOpen ?? true,
                        femaleOpen: femaleOpen ?? true,
                        genderLimit: data['genderLimit'] as String? ?? 'all',
                        // 전체 상태가 마감/취소면 성별 설정은 뜻이 없다.
                        // 혼합(null)일 때는 잠그지 않는다 — 성별 값은 전체
                        // 상태와 따로 저장돼 그대로 살아 있기 때문이다.
                        enabled: status == null || status == '모집중',
                        disabledNote: '전체 $status 상태라 성별 설정은 적용되지 않아요.',
                        onChanged: (v) => setSheetState(() {
                          maleOpen = v.maleOpen;
                          femaleOpen = v.femaleOpen;
                        }),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: () => Navigator.pop(sheetContext, (
                          status: status,
                          male: maleOpen,
                          female: femaleOpen,
                        )),
                        child: const Text('저장'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );

    if (picked == null) return;
    // 바뀐 것만 저장한다 — 혼합이었던 항목을 건드리지 않았으면 그대로 둔다.
    final nextStatus = picked.status == current ? null : picked.status;
    final nextMaleClosed = picked.male == currentMaleOpen || picked.male == null
        ? null
        : !picked.male!;
    final nextFemaleClosed =
        picked.female == currentFemaleOpen || picked.female == null
        ? null
        : !picked.female!;
    if (nextStatus == null &&
        nextMaleClosed == null &&
        nextFemaleClosed == null) {
      return;
    }

    final parties = FirebaseFirestore.instance.collection('parties');
    if (scoped) {
      // 회차별 — 고른 날짜의 칸만 점 표기 경로로 고친다. 다른 회차도, 문서
      // 최상단 값도 건드리지 않는다([PartyOccurrenceRecruit.updateFields]).
      await parties
          .doc(docId)
          .update(
            PartyOccurrenceRecruit.updateFields(
              occurrenceIds: targetIds,
              status: nextStatus,
              maleClosed: nextMaleClosed,
              femaleClosed: nextFemaleClosed,
            ),
          );
      return;
    }

    // 날짜가 하나뿐인 파티 — 예전 그대로 문서 최상단 값을 고친다.
    //
    // 남·여 모두 모집중이면 성별 필드를 남기지 않는다(null) — 기본값과 같은
    // 상태를 문서에 적어두지 않아야 이 기능을 안 쓰는 파티가 예전 그대로
    // 유지된다. 성별을 아예 건드리지 않았으면 그 키는 넣지도 않는다.
    final touchedGender = nextMaleClosed != null || nextFemaleClosed != null;
    await parties.doc(docId).update({
      if (nextStatus != null) 'recruitStatus': nextStatus,
      if (touchedGender)
        PartyGenderRecruit.field: PartyGenderRecruit.toField(
          maleClosed: nextMaleClosed ?? (currentMaleClosed ?? false),
          femaleClosed: nextFemaleClosed ?? (currentFemaleClosed ?? false),
        ),
    });
  }

  /// 호스트의 승인/거절 — 서버가 **신청 문서의 status**를 바꾼다.
  ///
  /// 예전에는 앱이 파티 문서의 approvedApplicants/rejectedApplicants uid 배열을
  /// 직접 고쳤는데, 그 배열은 uid만 담아서 "8/15는 승인, 8/22는 거절"을 표현할
  /// 수 없다. 회차별 신청이 생긴 이상 승인 상태는 신청 문서에만 담긴다
  /// (입금 확인 경로도 이미 status를 쓰므로 정본이 하나로 합쳐진다).
  Future<bool> _decide(
    BuildContext context, {
    required String applicationId,
    required String decision,
  }) async {
    try {
      await FirebaseFunctions.instanceFor(
        region: 'asia-northeast3',
      ).httpsCallable('decidePartyApplication').call({
        'partyId': docId,
        'applicationId': applicationId,
        'decision': decision,
      });
      return true;
    } catch (e) {
      if (!context.mounted) return false;
      final msg =
          e is FirebaseFunctionsException && (e.message ?? '').isNotEmpty
          ? e.message!
          : '처리에 실패했어요.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return false;
    }
  }

  /// 승인/거절을 보내고, **성공했을 때만** 시트를 닫고 완료 팝업을 띄운다.
  ///
  /// 순서가 곧 이 화면의 UX다 — 서버 성공 → 시트 닫기 → 팝업. 시트 위에 팝업을
  /// 겹치면 뒤에서 목록이 실시간으로 바뀌는 모습까지 함께 보여, 정작 "처리가
  /// 끝났다"는 결과가 묻힌다. 파티별 신청자 목록(`party_applicants_screen`)도
  /// 같은 순서라, 어디서 승인하든 호스트가 보는 흐름이 같다.
  ///
  /// **실패하면 시트를 닫지 않는다** — 그 자리에서 곧바로 다시 시도할 수 있어야
  /// 한다. 오류 안내는 [_decide]가 이미 띄웠다.
  ///
  /// 팝업을 [hubContext](시트 **바깥**, 허브 목록)로 띄우는 이유는 시트 안
  /// 컨텍스트가 닫히는 순간 죽어서 그 위에 아무것도 세울 수 없기 때문이다.
  ///
  /// 진행 중 표시를 [onBusy]로 되돌려주는 이유는 이 시트가 `StatefulBuilder`로
  /// 그려져서, 상태를 여기(카드 위젯)에 둘 수 없기 때문이다.
  Future<void> _decideAndReport(
    BuildContext sheetContext, {
    required BuildContext hubContext,
    required String applicationId,
    required String decision,
    required String personLabel,
    required PaymentStatus? paymentStatus,
    required void Function(bool busy) onBusy,
  }) async {
    onBusy(true);
    final ok = await _decide(
      sheetContext,
      applicationId: applicationId,
      decision: decision,
    );
    if (!sheetContext.mounted) return;
    if (!ok) {
      // 버튼을 다시 열어 준다. 성공했을 때는 시트가 닫히므로 풀 것도 없다.
      onBusy(false);
      return;
    }

    Navigator.of(sheetContext).pop();
    if (!hubContext.mounted) return;
    await showApplicationDecisionResult(
      hubContext,
      personLabel: personLabel,
      decision: decision,
      paymentStatus: paymentStatus,
    );
  }

  /// 신청자 uid → 화면에 그릴 신원.
  ///
  /// 신청 문서에는 uid만 있고, 규칙상 클라이언트는 남의 `users/{uid}`를 읽을 수
  /// 없다(users 읽기는 본인·관리자뿐). 그래서 닉네임·성별·생년월일은 호스트
  /// 권한을 확인하는 `getApplicants` 콜러블에서만 받아올 수 있다.
  ///
  /// 실패하면 빈 map을 돌려준다 — 그때도 **uid를 대신 그리지 않는다**.
  Future<Map<String, ApplicantIdentity>> _loadApplicantIdentities() async {
    try {
      final result =
          await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
              .httpsCallable('getApplicants')
              .call<Map<Object?, Object?>>({'partyId': docId});
      final list = (result.data['applicants'] as List<Object?>?) ?? [];
      final map = <String, ApplicantIdentity>{};
      for (final item in list) {
        final m = item as Map<Object?, Object?>;
        final uid = m['uid'] as String?;
        if (uid == null || uid.isEmpty) continue;
        map[uid] = ApplicantIdentity.fromMap(
          m['identity'] as Map<Object?, Object?>?,
        );
      }
      return map;
    } catch (e) {
      debugPrint('[HostHub] 신청자 신원 조회 실패: $e');
      return const {};
    }
  }

  void _showApplicants(BuildContext context) {
    // 완료 팝업을 세울 자리 — 시트 **바깥**이다. 시트 안 컨텍스트는
    // 닫히는 순간 죽어서 팝업을 띄울 수 없다.
    final hubContext = context;
    // applicants/approvedApplicants/rejectedApplicants 배열은 취소된 신청자를
    // 제거하므로(정원 계산용) 취소 내역까지 보여주려면 applications
    // 서브컬렉션을 실시간 구독해야 한다 — 승인/거절 상태는 기존 그대로 배열
    // 기반으로 판단하고, 취소 여부만 이 서브컬렉션의 status로 판단한다.
    //
    // 표시용 신원만 콜러블로 한 번 받아 온다. 승인/거절이 즉시 반영되는 것은
    // 위 실시간 구독이 그대로 담당하고, 닉네임·성별·생년월일은 시트를 열어 둔
    // 사이에 바뀔 값이 아니라 한 번이면 충분하다.
    final identitiesFuture = _loadApplicantIdentities();
    // 지금 보고 있는 회차. 시트가 열려 있는 동안만 유지하면 되므로 여기 클로저에
    // 둔다(단일 날짜 파티면 끝까지 null이고 선택 UI도 뜨지 않는다).
    String? selectedOccurrence;
    var selectionInitialised = false;
    // 지금 서버로 가 있는 신청들 — 그 줄의 승인/거절 버튼을 잠근다.
    final deciding = <String>{};
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollCtrl) => StatefulBuilder(
          builder: (context, setSheetState) =>
              FutureBuilder<Map<String, ApplicantIdentity>>(
                future: identitiesFuture,
                builder: (context, idSnap) {
                  final identities =
                      idSnap.data ?? const <String, ApplicantIdentity>{};
                  final identitiesLoading =
                      idSnap.connectionState != ConnectionState.done;
                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('parties')
                        .doc(docId)
                        .collection('applications')
                        .orderBy('appliedAt')
                        .snapshots(),
                    builder: (context, snapshot) {
                      final allDocs = snapshot.data?.docs ?? [];
                      String? occurrenceOf(QueryDocumentSnapshot d) =>
                          (d.data() as Map<String, dynamic>)['occurrenceId']
                              as String?;

                      // 회차 목록은 **거르기 전** 전체에서 만든다 — 한 회차를 보고
                      // 있어도 다른 회차 칩이 사라지면 안 된다.
                      final occurrenceIds = buildOccurrenceIds(
                        partyData: data,
                        fromApplications: allDocs.map(occurrenceOf),
                      );
                      // 첫 프레임에 기본 회차(오늘 이후 가장 가까운 회차)를 정한다.
                      // 한 번만 정하고 그 뒤로는 사용자가 고른 값을 지킨다.
                      if (!selectionInitialised && occurrenceIds.isNotEmpty) {
                        selectedOccurrence = defaultOccurrenceId(occurrenceIds);
                        selectionInitialised = true;
                      }
                      final counts = <String, int>{};
                      for (final d in allDocs) {
                        final id = occurrenceOf(d);
                        final m = d.data() as Map<String, dynamic>;
                        if (id == null || m['status'] == 'cancelled') continue;
                        counts[id] = (counts[id] ?? 0) + 1;
                      }

                      // 다른 날짜 신청이 섞이지 않게 여기서 한 번만 거른다 — 아래
                      // 목록·건수·승인/거절은 모두 이 목록만 본다.
                      final appDocs = selectedOccurrence == null
                          ? allDocs
                          : allDocs
                                .where(
                                  (d) => occurrenceOf(d) == selectedOccurrence,
                                )
                                .toList();

                      final approved = List<String>.from(
                        data['approvedApplicants'] ?? [],
                      );
                      final rejected = List<String>.from(
                        data['rejectedApplicants'] ?? [],
                      );
                      final activeCount = appDocs
                          .where(
                            (d) =>
                                (d.data() as Map<String, dynamic>)['status'] !=
                                'cancelled',
                          )
                          .length;
                      // 클로저에 잡힌 변수는 null 승격이 안 된다 — 한 번 받아 둔다.
                      final shownOccurrence = selectedOccurrence;

                      return Column(
                        children: [
                          const SizedBox(height: 12),
                          Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '신청자 목록 ($activeCount명)',
                            style: const TextStyle(
                              fontFamily: 'SeoulHangang',
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              shadows: [
                                Shadow(
                                  color: Colors.black87,
                                  offset: Offset(0.3, 0),
                                ),
                                Shadow(
                                  color: Colors.black87,
                                  offset: Offset(-0.3, 0),
                                ),
                                Shadow(
                                  color: Colors.black87,
                                  offset: Offset(0, 0.3),
                                ),
                                Shadow(
                                  color: Colors.black87,
                                  offset: Offset(0, -0.3),
                                ),
                              ],
                            ),
                          ),
                          // 반복 파티는 날짜를 먼저 못 박는다 — 지금 보고 있는 날짜와
                          // 그 날짜 신청자 수를 띄우고, 누르면 날짜별 목록이 열린다.
                          // (예전의 가로 스크롤 칩은 화면 밖 날짜가 안 보였다.)
                          if (occurrenceIds.isNotEmpty &&
                              shownOccurrence != null)
                            OccurrenceHeaderButton(
                              occurrenceId: shownOccurrence,
                              count: activeCount,
                              onTap: () async {
                                final picked = await showOccurrenceSheet(
                                  context: context,
                                  occurrenceIds: occurrenceIds,
                                  selected: shownOccurrence,
                                  counts: counts,
                                );
                                // 그냥 닫으면 보던 날짜를 그대로 둔다.
                                if (picked != null) {
                                  setSheetState(
                                    () => selectedOccurrence = picked,
                                  );
                                }
                              },
                            ),
                          const Divider(),
                          Expanded(
                            child: !snapshot.hasData
                                ? const Center(
                                    child: CircularProgressIndicator(
                                      color: Color(0xFFFF6FA0),
                                    ),
                                  )
                                : appDocs.isEmpty
                                ? const Center(
                                    child: Text(
                                      '신청자가 없습니다',
                                      style: TextStyle(color: Colors.black45),
                                    ),
                                  )
                                : ListView.separated(
                                    controller: scrollCtrl,
                                    itemCount: appDocs.length,
                                    separatorBuilder: (_, i) =>
                                        const Divider(height: 1),
                                    itemBuilder: (ctx, i) {
                                      final appDoc = appDocs[i];
                                      final appData =
                                          appDoc.data() as Map<String, dynamic>;
                                      // 문서 ID는 회차 신청이면 uid가 아니다 — uid는
                                      // 언제나 필드에서 읽는다(서버 applicationDocId).
                                      final uid =
                                          appData['uid'] as String? ??
                                          appDoc.id;
                                      final status =
                                          appData['status'] as String? ??
                                          'applied';
                                      final isCancelled = status == 'cancelled';
                                      // 승인/거절의 **정본은 신청 문서의 status**다.
                                      // approvedApplicants/rejectedApplicants uid 배열은
                                      // 회차를 구분할 수 없어(8/15 승인·8/22 거절을 표현
                                      // 못 한다) 옛 데이터를 읽는 폴백으로만 남긴다.
                                      final isApproved =
                                          !isCancelled &&
                                          (status == 'approved' ||
                                              (status == 'applied' &&
                                                  approved.contains(uid)));
                                      final isRejected =
                                          !isCancelled &&
                                          (status == 'rejected' ||
                                              (status == 'applied' &&
                                                  rejected.contains(uid)));
                                      final cancelledBy =
                                          appData['cancelledBy'] as String?;

                                      // 표시는 언제나 신원 기준이다 — uid는 승인·거절을
                                      // 어느 신청에 걸지 고르는 데만 쓰고 화면에 그리지
                                      // 않는다. 아직 못 받아왔거나 조회에 실패했으면
                                      // uid로 대신 채우지 말고 그렇다고 말한다.
                                      final identity = identities[uid];
                                      final label =
                                          identity?.displayLabel() ??
                                          (identitiesLoading
                                              ? '신청자 정보를 불러오는 중…'
                                              : ApplicantIdentity.unknownLabel);
                                      final initial =
                                          (identity?.nickname.isNotEmpty ??
                                              false)
                                          ? identity!.nickname.characters.first
                                          : '?';

                                      // 처리 중에는 두 버튼 다 잠근다 — 승인과 거절이
                                      // 잇달아 눌리면 두 번째는 오류로 돌아와, 방금
                                      // 잘 끝난 처리가 실패한 것처럼 보인다.
                                      final busy = deciding.contains(appDoc.id);
                                      void decide(String decision) =>
                                          _decideAndReport(
                                            context,
                                            hubContext: hubContext,
                                            applicationId: appDoc.id,
                                            decision: decision,
                                            personLabel:
                                                identity?.personLabel ??
                                                ApplicantIdentity.unknownLabel,
                                            // 승인 뒤에 입금 확인이 남았는지는 결제
                                            // 상태가 정한다(완료 문구가 갈린다).
                                            paymentStatus:
                                                PaymentStatus.fromKey(
                                                  (appData['payment']
                                                          as Map?)?['status']
                                                      as String?,
                                                ),
                                            onBusy: (b) => setSheetState(
                                              () => b
                                                  ? deciding.add(appDoc.id)
                                                  : deciding.remove(appDoc.id),
                                            ),
                                          );

                                      return Opacity(
                                        opacity: isCancelled ? 0.55 : 1.0,
                                        child: ListTile(
                                          leading: CircleAvatar(
                                            backgroundColor: const Color(
                                              0xFFDDD5FF,
                                            ),
                                            child: Text(
                                              initial,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          // 회차 날짜는 붙이지 않는다 — 위 회차 선택
                                          // 줄이 지금 어느 날짜를 보고 있는지 말해준다.
                                          title: Text(
                                            label,
                                            // 한 줄이면 '여성 · 냥냥이 · 91년생
                                            // (35세)'의 생년·나이가 잘려 나간다 —
                                            // 호스트가 봐야 하는 정보라 두 줄까지 준다.
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: isCancelled
                                                ? const TextStyle(
                                                    decoration: TextDecoration
                                                        .lineThrough,
                                                  )
                                                : null,
                                          ),
                                          // 상태 한 줄 + **본인확인 실명** 한 줄.
                                          // 실명은 입장 확인 때 신분증과 대조하는
                                          // 값이라, 파티별 신청자 목록과 같은 모양으로
                                          // 여기서도 보여준다(두 화면이 다른 사실을
                                          // 말하면 현장에서 근거로 쓸 수 없다).
                                          subtitle: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (isCancelled)
                                                Text(
                                                  // 서버 자동 취소는 사유까지 밝힌다.
                                                  PartyCancelReason.labelOf(
                                                            appData,
                                                          ) !=
                                                          null
                                                      ? '취소됨 (최소 모집 인원 미달)'
                                                      : cancelledBy == 'host'
                                                      ? '취소됨 (호스트가 파티 취소)'
                                                      : cancelledBy == 'system'
                                                      ? '취소됨 (파티 취소)'
                                                      : '취소됨 (참가자 직접 취소)',
                                                  style: const TextStyle(
                                                    color: Colors.black45,
                                                  ),
                                                )
                                              else if (isApproved)
                                                const Text(
                                                  '승인됨',
                                                  style: TextStyle(
                                                    color: Colors.green,
                                                  ),
                                                )
                                              else if (isRejected)
                                                const Text(
                                                  '거절됨',
                                                  style: TextStyle(
                                                    color: Colors.red,
                                                  ),
                                                )
                                              else
                                                const Text(
                                                  '대기 중',
                                                  style: TextStyle(
                                                    color: Colors.orange,
                                                  ),
                                                ),
                                              // 취소된 신청은 입장할 일이 없다.
                                              if (!isCancelled &&
                                                  identity?.verifiedName !=
                                                      null) ...[
                                                const SizedBox(height: 3),
                                                VerifiedNameLine(
                                                  verifiedName:
                                                      identity!.verifiedName,
                                                ),
                                              ],
                                            ],
                                          ),
                                          trailing: isCancelled
                                              ? null
                                              : Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    if (!isApproved)
                                                      IconButton(
                                                        icon: const Icon(
                                                          Icons
                                                              .check_circle_outline,
                                                          color: Colors.green,
                                                        ),
                                                        tooltip: '승인',
                                                        onPressed: busy
                                                            ? null
                                                            : () => decide(
                                                                'approved',
                                                              ),
                                                      ),
                                                    if (!isRejected)
                                                      IconButton(
                                                        icon: const Icon(
                                                          Icons.cancel_outlined,
                                                          color: Colors.red,
                                                        ),
                                                        tooltip: '거절',
                                                        onPressed: busy
                                                            ? null
                                                            : () => decide(
                                                                'rejected',
                                                              ),
                                                      ),
                                                  ],
                                                ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
        ),
      ),
    );
  }

  /// partyDateTime 기준으로 자동 삭제까지 남은 날 수 (0 = 오늘 삭제 예정)
  // 얼리버드 설정이 전혀 없으면 표시하지 않고, 설정된 적 있다면 진행중/종료 상태를 보여줌.
  Widget _earlyBirdStatusRow(Map<String, dynamic> d) {
    if (d['earlyBirdEnabled'] != true) return const SizedBox.shrink();
    final end = EarlyBird.endAt(d);
    if (end == null) return const SizedBox.shrink();

    final active = EarlyBird.isActive(d);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: active ? const Color(0xFFFFF0F5) : const Color(0xFFF3F4F6),
      child: active
          ? Row(
              children: [
                PartyCard.earlyBirdBadge(EarlyBird.discountPercent(d)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '종료: ${EarlyBird.formatEndAt(end)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFD94F7A),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            )
          : const Text(
              '얼리버드 종료',
              style: TextStyle(fontSize: 12, color: Colors.black45),
            ),
    );
  }

  /// 자동 삭제를 세는 **기준점** — 이 파티가 다시는 열리지 않는 시각.
  ///
  /// 판정은 [PartySchedule.finalEndAt] 하나가 한다(정기 파티는 마지막 회차
  /// 종료, 일회성은 종료 시각). 예전에는 여기서 정기 파티의 운영 종료일
  /// **날짜**를 그대로 쓰고 일회성은 partyDateTime을 읽는 계산을 따로 들고
  /// 있었는데, 그러면 서버가 지우는 기준과 화면이 세는 기준이 갈린다 —
  /// 서버도 같은 규칙(functions/partySchedule.js finalPartyEndAt)을 쓴다.
  ///
  /// 기준점을 못 읽으면 null이고, 그런 카드는 배지를 아예 달지 않는다.
  /// 모르는 채로 날짜를 지어내면 "D-30" 같은 거짓 안내가 된다.
  static DateTime? _deletionBase(Map<String, dynamic> d) =>
      PartySchedule.finalEndAt(d);

  @override
  Widget build(BuildContext context) {
    final applicants = List<String>.from(data['applicants'] ?? []);
    // '자동삭제 D-12' / '오늘 자동삭제' / '삭제 예정' — 음수 D-day는 나오지
    // 않는다(삭제는 하루 한 번 도는 작업이라 기한이 지나고도 몇 시간 남아
    // 있는 구간이 정상이다). 문구 규칙은 [AutoDeleteRetention].
    final deletionBase = isPast ? _deletionBase(data) : null;
    final autoDeleteLabel = AutoDeleteRetention.label(deletionBase);
    final deleteSoon = AutoDeleteRetention.isUrgent(deletionBase);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EBF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 메인 카드와 동일한 이미지+정보 행 ──────────────────────
          Padding(
            padding: const EdgeInsets.all(10),
            child: PartyCardBase(data: data),
          ),
          _earlyBirdStatusRow(data),
          const Divider(height: 1, color: Color(0xFFE8EBF2)),
          // ── 마이페이지 전용 관리 버튼 ───────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 10),
            child: Row(
              children: [
                if (isPast) ...[
                  // 지난 파티: 재등록 버튼
                  _actionBtn(
                    icon: Icons.replay_rounded,
                    label: '재등록',
                    color: const Color(0xFF7C5CBF),
                    // 재등록은 **파티 등록 화면(정본)** 을 재등록 모드로 연다 —
                    // 입력 항목·섹션 순서·검증·차수·패키지가 등록과 100% 같다.
                    // 저장은 새 파티 문서로 나가고 이 지난 파티는 기록으로 남는다.
                    //
                    // 새 문서를 만드는 길이라 등록 화면과 **같은 관문**을
                    // 지난다 — 지난 파티가 남아 있다고 자격이 생기지는 않는다
                    // (기존 파티의 조회·수정·관리는 그대로다).
                    onTap: () async {
                      if (!await PartyCreateEligibility.ensure(context)) return;
                      if (!context.mounted) return;
                      await Navigator.push(
                        context,
                        webFramedRoute(
                          (_) => PartyRegisterScreen.reregister(
                            data: data,
                            docId: docId,
                          ),
                        ),
                      );
                    },
                  ),
                  // 자동 삭제 카운트다운 배지 — 기준점을 못 읽는 파티에는
                  // 아예 붙지 않는다(위 [_deletionBase] 주석 참고).
                  if (autoDeleteLabel != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: deleteSoon
                            ? const Color(0xFFFFEBEE)
                            : const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.timer_outlined,
                            size: 11,
                            color: deleteSoon
                                ? Colors.redAccent
                                : const Color(0xFFE65100),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            autoDeleteLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: deleteSoon
                                  ? Colors.redAccent
                                  : const Color(0xFFE65100),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ] else ...[
                  // 진행 중인 파티: 기존 버튼
                  _actionBtn(
                    icon: Icons.edit_outlined,
                    label: '수정',
                    onTap: () => Navigator.push(
                      context,
                      webFramedRoute(
                        (_) => PartyEditScreen(docId: docId, data: data),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _actionBtn(
                    icon: Icons.people_alt_outlined,
                    label: '신청자 (${applicants.length})',
                    onTap: () => _showApplicants(context),
                  ),
                  const SizedBox(width: 8),
                  _actionBtn(
                    icon: Icons.swap_horiz_rounded,
                    label: '상태 변경',
                    onTap: () => _changeStatus(context),
                  ),
                ],
                const Spacer(),
                // 삭제는 앱 전체가 하나의 공용 흐름을 쓴다 — 확인 문구·범위
                // 선택·권한 검사·연결 데이터 정리가 재등록/수정 화면과 완전히
                // 같다(delete_content_action.dart).
                DeleteContentIconButton(
                  type: DeletableContent.party,
                  id: docId,
                  seriesId: data['seriesId'] as String? ?? docId,
                ),
              ],
            ),
          ),
          // 연결된 플레이스/장소가 있는 파티에만 보인다 — 이벤트는 가게에
          // 붙는 것이라 붙일 곳이 없으면 누를 이유도 없다.
          if (!isPast && PartyEventSource.hasLinkedPlace(data))
            _eventRegisterRow(context),
        ],
      ),
    );
  }

  /// "이 파티를 기반으로 이벤트 등록".
  ///
  /// ⚠️ 예전에는 이 버튼이 **파티 등록 화면(재등록 모드)**을 열었다. 그러면
  /// 만들어지는 것은 또 하나의 파티라, 손님은 파티 목록에서 같은 내용을 두 번
  /// 보고 "플레이스 > 이벤트"에는 끝내 뜨지 않았다. 버튼 문구가 말하는 것과
  /// 실제로 만들어지는 것이 달랐던 셈이다.
  ///
  /// 지금은 파티에 연결된 **가게의 이벤트**(placePromotions)를 만든다.
  ///
  ///   · 원본 파티 문서는 읽기만 한다 — 한 글자도 바꾸지 않는다.
  ///   · parties에는 아무것도 쓰지 않는다 — 파티 목록에 새 카드가 생기지 않는다.
  ///   · 등록이 끝나면 이벤트·혜택 관리 화면으로 이어 준다(수정·종료가 거기 있다).
  Widget _eventRegisterRow(BuildContext context) {
    final schedule = PartySchedule.summaryLabel(data);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (schedule.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                schedule,
                style: const TextStyle(fontSize: 11.5, color: Colors.black45),
              ),
            ),
          GestureDetector(
            onTap: () => _openEventRegister(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0F5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFFFF6FA0).withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_awesome, size: 14, color: Color(0xFFFF6FA0)),
                  SizedBox(width: 6),
                  Text(
                    '이 파티를 기반으로 매장 이벤트 등록',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFFFF6FA0),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 파티에 연결된 가게를 찾아 이벤트 등록 화면을 연다.
  ///
  /// hostId는 **가게 문서에서 읽은 값**을 그대로 넘긴다 — 파티에 적힌 값을
  /// 믿지 않는다. 최종 방어선은 rules(placePromotions의 ownsSourcePlace)이고,
  /// 여기서는 화면을 열기 전에 미리 걸러 헛걸음을 줄인다.
  Future<void> _openEventRegister(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);

    void say(String msg) => messenger.showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );

    PartyEventSource? source;
    try {
      source = await PartyEventSource.resolve(partyId: docId, party: data);
    } catch (_) {
      say('플레이스 정보를 불러오지 못했어요. 잠시 후 다시 시도해주세요.');
      return;
    }
    if (source == null) {
      say('이 파티에 연결된 플레이스가 없어요. 파티에 플레이스를 먼저 연결해주세요.');
      return;
    }
    if (source.hostId != UserSession.userId) {
      say('이 플레이스의 호스트만 이벤트를 등록할 수 있어요.');
      return;
    }
    if (!context.mounted) return;

    // 붙일 플레이스가 이미 정해진 경우다 — 확인·선택 단계는 건너뛰지만
    // 폼을 열고 저장 뒤 관리 화면으로 잇는 뒷길은 등록 화면의 "이벤트 등록"과
    // 똑같이 [PlaceEventEntry]가 맡는다.
    await PlaceEventEntry.startRegister(
      context,
      target: EventPlaceTarget(
        placeId: source.placeId,
        placeCollection: source.placeCollection,
        hostId: source.hostId,
        placeName: source.placeName,
        address: source.address,
      ),
      initialTitle: source.titleDraft,
      sourcePartyId: source.sourcePartyId,
      sourcePartyTitle: source.sourcePartyTitle,
      requirePeriod: true,
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final fg = color ?? Colors.black54;
    final bg = color != null
        ? color.withValues(alpha: 0.12)
        : const Color(0xFFEEF0F4);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: fg,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 장소 카드
// ─────────────────────────────────────────────────────────────────────────────

class _MyPlaceCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final bool isHidden;

  const _MyPlaceCard({
    required this.docId,
    required this.data,
    this.isHidden = false,
  });

  // "진행중" 탭에서 숨기기 — isActive:false + hiddenAt 기록(보관기간 시작).
  Future<void> _hide(BuildContext context) async {
    try {
      await FirebaseFirestore.instance.collection('places').doc(docId).update({
        'isActive': false,
        'hiddenAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '장소를 숨겼습니다. '
              '${AutoDeleteRetention.window.inDays}일 안에 다시 노출하지 않으면 자동 삭제돼요.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('변경 실패: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// 숨긴 시각(hiddenAt) — 자동 삭제를 세는 기준점. 값이 없는 옛 문서는 null이고
  /// 그런 문서는 서버도 지우지 않는다(안내도 하지 않는다).
  static DateTime? _hiddenAt(Map<String, dynamic> d) {
    final ts = d['hiddenAt'];
    return ts is Timestamp ? ts.toDate() : null;
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final fg = color ?? Colors.black54;
    final bg = color != null
        ? color.withValues(alpha: 0.12)
        : const Color(0xFFEEF0F4);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: fg,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String? ?? '장소';
    final rawAddress = data['address'] as String? ?? '';
    final address = rawAddress.isEmpty
        ? ''
        : RegionData.shortDistrictDong(rawAddress);
    final cover = getPartyCoverMedia(data, tag: 'MyPlaceCard');
    final thumbnailUrl = cover?.thumbnailUrl;
    final isActive = data['isActive'] != false; // null → 진행중으로 간주
    // 자동 삭제 안내 — 문구·남은 날 계산은 지난 파티·임시저장과 같은 정본을
    // 쓴다([AutoDeleteRetention], 14일). 예전에는 이 카드만 30일을 따로 셌다.
    // hiddenAt이 없는 옛 문서는 null이라 배지 자체를 그리지 않는다 — 서버도
    // 그런 문서는 지우지 않으므로 남은 날을 말할 수 없다.
    final hiddenAt = isHidden ? _hiddenAt(data) : null;
    final autoDeleteLabel = AutoDeleteRetention.label(hiddenAt);
    final deleteSoon = AutoDeleteRetention.isUrgent(hiddenAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 대표 이미지
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: SizedBox(
              height: 120,
              width: double.infinity,
              child: thumbnailUrl != null && thumbnailUrl.isNotEmpty
                  ? Image.network(
                      thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, e, st) =>
                          Container(color: const Color(0xFFFFE0EE)),
                    )
                  : Container(
                      color: const Color(0xFFF3EFFA),
                      child: const Icon(
                        Icons.home_outlined,
                        size: 48,
                        color: Color(0xFF7C5CBF),
                      ),
                    ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // 상태 뱃지
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isActive
                            ? const Color(0xFFF0FFF4)
                            : const Color(0xFFF5F5F7),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isActive
                              ? const Color(0xFFB3E6C8)
                              : const Color(0xFFDDDDDD),
                        ),
                      ),
                      child: Text(
                        isActive ? '진행중' : '숨김',
                        style: TextStyle(
                          fontSize: 11,
                          color: isActive
                              ? const Color(0xFF2E7D32)
                              : Colors.black45,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (address.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    address,
                    style: const TextStyle(fontSize: 12, color: Colors.black45),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 10),
                // ── 관리 버튼 ────────────────────────────────────────
                Row(
                  children: [
                    if (isHidden) ...[
                      // 숨김: 재등록(=수정 화면 재사용) 버튼
                      _actionBtn(
                        icon: Icons.replay_rounded,
                        label: '재등록',
                        color: const Color(0xFF7C5CBF),
                        onTap: () => Navigator.push(
                          context,
                          webFramedRoute(
                            (_) => PlaceEditScreen(docId: docId, data: data),
                          ),
                        ),
                      ),
                      // 자동 삭제 카운트다운 배지 — 기준점을 아는 문서에만
                      // 붙는다(hiddenAt이 없는 옛 숨김 문서는 아무 말 안 함).
                      if (autoDeleteLabel != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: deleteSoon
                                ? const Color(0xFFFFEBEE)
                                : const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.timer_outlined,
                                size: 11,
                                color: deleteSoon
                                    ? Colors.redAccent
                                    : const Color(0xFFE65100),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                autoDeleteLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: deleteSoon
                                      ? Colors.redAccent
                                      : const Color(0xFFE65100),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ] else ...[
                      // 진행중: 수정 + 숨기기 버튼
                      _actionBtn(
                        icon: Icons.edit_outlined,
                        label: '수정',
                        onTap: () => Navigator.push(
                          context,
                          webFramedRoute(
                            (_) => PlaceEditScreen(docId: docId, data: data),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _actionBtn(
                        icon: Icons.visibility_off_outlined,
                        label: '숨기기',
                        color: Colors.orange,
                        onTap: () => _hide(context),
                      ),
                    ],
                    const Spacer(),
                    // 파티와 동일한 공용 삭제 흐름.
                    DeleteContentIconButton(
                      type: DeletableContent.place,
                      id: docId,
                    ),
                  ],
                ),
                // ── 관리 메뉴 한 줄 ──────────────────────────────────
                //
                // 플레이스 카드와 **같은 위젯·같은 배치**다. 둘 다 "등록물을
                // 통째로 다시 수정하지 않고 부속 화면에서 끝내는" 기능이라
                // 같은 급으로 보여야 한다.
                //
                // 파티 연결도 플레이스와 완전히 같은 구조를 쓴다 — 파티 문서의
                // `linkedPlaceId`가 정본이고, "숙박+파티" 콤보로 함께 등록된
                // 파티도 같은 필드라 이 목록에 그대로 잡힌다(자세한 배경은
                // place_party_link_service.dart 상단 주석).
                //
                // 이벤트도 같은 줄에서 센다 — `✨ 연결 이벤트 N개`를 누르면
                // 기존 이벤트 관리 화면이 열린다(상단 🎪 이벤트 탭이 여는 것과
                // **같은 화면**이라 관리 방법이 두 갈래로 갈리지 않는다).
                const SizedBox(height: 2),
                _HostCardMenuRow(
                  targetId: docId,
                  data: data,
                  target: PartyLinkTarget.rental,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 내 파티샵 탭 — _MyPlaceList와 동일한 패턴(hostId 필터, 운영중/운영중지).
// ─────────────────────────────────────────────────────────────────────────────

class _MyShopList extends StatefulWidget {
  const _MyShopList();

  @override
  State<_MyShopList> createState() => _MyShopListState();
}

class _MyShopListState extends State<_MyShopList>
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
    // 로그인 화면에서 로그인을 마치고 돌아왔을 때 뒤로 갔다 다시 들어오지
    // 않아도 즉시 로그인 상태가 반영되도록 AuthRebuilder로 감싼다.
    return AuthRebuilder(builder: _buildLoggedGate);
  }

  Widget _buildLoggedGate(BuildContext context) {
    final userId = UserSession.userId;

    if (userId.isEmpty) {
      return const Center(
        child: Text('로그인 후 이용 가능합니다.', style: TextStyle(color: Colors.black45)),
      );
    }

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF1A73E8),
          unselectedLabelColor: Colors.black45,
          indicatorColor: const Color(0xFF1A73E8),
          indicatorWeight: 2,
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          tabs: const [
            Tab(text: '운영 중'),
            Tab(text: '운영 중지'),
          ],
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            // 파티크루 목록과 같은 이유로 orderBy를 뺐다 — partyShops에도
            // hostId+createdAt 복합 색인이 없어서(isActive+createdAt만 있다)
            // 이 스트림 역시 영구 스피너가 될 수 있었다. 정렬은 클라이언트에서.
            stream: FirebaseFirestore.instance
                .collection('partyShops')
                .where('hostId', isEqualTo: userId)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                logFirestoreStreamError(
                  'MyShopList',
                  snapshot.error,
                  snapshot.stackTrace,
                );
                return const _HostListError(
                  message: '내 파티샵 목록을 불러오지 못했어요.\n잠시 후 다시 시도해주세요.',
                );
              }
              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFF1A73E8)),
                );
              }

              final activeDocs = <QueryDocumentSnapshot>[];
              final inactiveDocs = <QueryDocumentSnapshot>[];

              for (final doc in _sortedByCreatedAtDesc(snapshot.data!.docs)) {
                final d = doc.data() as Map<String, dynamic>;
                if (d['isActive'] == false) {
                  inactiveDocs.add(doc);
                } else {
                  activeDocs.add(doc);
                }
              }

              return TabBarView(
                controller: _tabController,
                // 바깥 카테고리 탭(파티츄/플레이스/공간대여/파티크루)도 좌우
                // 드래그로 전환되는 TabBarView라, 이 안쪽 상태 탭까지 드래그를
                // 받으면 같은 제스처를 둘이 경합해 안쪽이 이겨버린다 — 그러면
                // 카테고리를 드래그로 넘길 수 없다. 안쪽은 탭(클릭) 전환만
                // 두고 드래그는 항상 바깥 카테고리 전용으로 남긴다
                // (main_screen.dart의 파티크루 구인/구직 탭과 같은 처리).
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _ShopTabList(
                    docs: activeDocs,
                    emptyIcon: Icons.storefront_outlined,
                    emptyMessage: '운영 중인 파티샵이 없어요',
                  ),
                  _ShopTabList(
                    docs: inactiveDocs,
                    emptyIcon: Icons.store_outlined,
                    emptyMessage: '운영 중지된 파티샵이 없어요',
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ShopTabList extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;
  final IconData emptyIcon;
  final String emptyMessage;

  const _ShopTabList({
    required this.docs,
    required this.emptyIcon,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(emptyIcon, size: 56, color: Colors.black26),
            const SizedBox(height: 12),
            Text(emptyMessage, style: const TextStyle(color: Colors.black45)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: docs.length,
      itemBuilder: (_, i) {
        final doc = docs[i];
        final data = doc.data() as Map<String, dynamic>;
        return _MyShopCard(shopId: doc.id, data: data);
      },
    );
  }
}

class _MyShopCard extends StatelessWidget {
  final String shopId;
  final Map<String, dynamic> data;

  const _MyShopCard({required this.shopId, required this.data});

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String? ?? '파티샵';
    final rawLocation = data['location'] as String? ?? '';
    final location = rawLocation.isEmpty
        ? ''
        : RegionData.shortDistrictDong(rawLocation);
    // 대표 미디어 — 앱 전체가 쓰는 공용 정본 하나로 읽는다
    // ([getPartyCoverMedia]). 대표가 사진이면 그 사진이, 동영상이면 그
    // 영상의 정지 썸네일이 온다(카드는 영상을 재생하지 않는다). 대표 계약이
    // 없던 옛 문서는 그 함수의 레거시 분기가 예전처럼 `mainImageUrl`을
    // 돌려주므로 보이는 모습이 달라지지 않는다.
    final mainImgUrl =
        getPartyCoverMedia(data, tag: 'MyShopCard')?.thumbnailUrl ?? '';
    final isActive = data['isActive'] != false;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        webFramedRoute(
          (_) => PartyShopManageScreen(shopId: shopId, shopData: data),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x10000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(16),
              ),
              child: SizedBox(
                width: 90,
                height: 90,
                child: mainImgUrl.isNotEmpty
                    ? Image.network(
                        mainImgUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, e, st) =>
                            Container(color: const Color(0xFFFFE0EE)),
                      )
                    : Container(
                        color: const Color(0xFFFFE0EE),
                        child: const Icon(
                          Icons.store_outlined,
                          size: 32,
                          color: Color(0xFFFF6FA0),
                        ),
                      ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isActive
                                ? const Color(0xFFF0FFF4)
                                : const Color(0xFFF5F5F7),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isActive
                                  ? const Color(0xFFB3E6C8)
                                  : const Color(0xFFDDDDDD),
                            ),
                          ),
                          child: Text(
                            isActive ? '운영 중' : '운영 중지',
                            style: TextStyle(
                              fontSize: 11,
                              color: isActive
                                  ? const Color(0xFF2E7D32)
                                  : Colors.black45,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        location,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black45,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // 파티·장소·파트너와 동일한 공용 삭제 흐름.
            DeleteContentIconButton(
              type: DeletableContent.partyShop,
              id: shopId,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 내 플레이스 탭 — _MyShopList와 동일한 패턴(hostId 필터, 노출 중/숨김).
// 파티샵과 달리 별도 관리 화면이 없어 탭하면 바로 EventEditScreen으로 이동한다.
// ─────────────────────────────────────────────────────────────────────────────

class _MyEventList extends StatefulWidget {
  const _MyEventList();

  @override
  State<_MyEventList> createState() => _MyEventListState();
}

class _MyEventListState extends State<_MyEventList>
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
    // 로그인 화면에서 로그인을 마치고 돌아왔을 때 뒤로 갔다 다시 들어오지
    // 않아도 즉시 로그인 상태가 반영되도록 AuthRebuilder로 감싼다.
    return AuthRebuilder(builder: _buildLoggedGate);
  }

  Widget _buildLoggedGate(BuildContext context) {
    final userId = UserSession.userId;

    if (userId.isEmpty) {
      return const Center(
        child: Text('로그인 후 이용 가능합니다.', style: TextStyle(color: Colors.black45)),
      );
    }

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          labelColor: const Color(0xFFFF6FA0),
          unselectedLabelColor: Colors.black45,
          indicatorColor: const Color(0xFFFF6FA0),
          indicatorWeight: 2,
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          tabs: const [
            Tab(text: '노출 중'),
            Tab(text: '숨김'),
          ],
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('events')
                .where('hostId', isEqualTo: userId)
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              // ⚠ 예전에는 오류 분기가 없어 `hasData == false`인 상태로 멈췄고,
              //   복합 인덱스가 빠졌을 때 화면이 **영구 스피너**로 남았다
              //   (events: hostId + createdAt DESC). 인덱스를 추가해 원인은
              //   없앴지만, 다른 이유로 스트림이 실패해도 사용자가 상황을 알 수
              //   있도록 '내 장소'와 같은 오류 화면을 둔다.
              if (snapshot.hasError) {
                logFirestoreStreamError(
                  'MyEventList',
                  snapshot.error,
                  snapshot.stackTrace,
                );
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 48,
                          color: Colors.black26,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '내 플레이스 목록을 불러오지 못했어요.\n잠시 후 다시 시도해주세요.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black45),
                        ),
                        const SizedBox(height: 14),
                        // 스트림 자체는 자동 재시도되지만, 사용자가 직접 다시
                        // 시킬 방법이 없으면 "멈춘 화면"으로 느껴진다.
                        OutlinedButton.icon(
                          onPressed: () => setState(() {}),
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('다시 시도'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFFF6FA0),
                            side: const BorderSide(color: Color(0xFFFFC2D6)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFFFF6FA0)),
                );
              }

              final activeDocs = <QueryDocumentSnapshot>[];
              final inactiveDocs = <QueryDocumentSnapshot>[];

              for (final doc in snapshot.data!.docs) {
                final d = doc.data() as Map<String, dynamic>;
                if (d['isActive'] == false) {
                  inactiveDocs.add(doc);
                } else {
                  activeDocs.add(doc);
                }
              }

              return TabBarView(
                controller: _tabController,
                // 바깥 카테고리 탭(파티츄/플레이스/공간대여/파티크루)도 좌우
                // 드래그로 전환되는 TabBarView라, 이 안쪽 상태 탭까지 드래그를
                // 받으면 같은 제스처를 둘이 경합해 안쪽이 이겨버린다 — 그러면
                // 카테고리를 드래그로 넘길 수 없다. 안쪽은 탭(클릭) 전환만
                // 두고 드래그는 항상 바깥 카테고리 전용으로 남긴다
                // (main_screen.dart의 파티크루 구인/구직 탭과 같은 처리).
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _EventTabList(
                    docs: activeDocs,
                    emptyIcon: Icons.celebration_outlined,
                    emptyMessage: '노출 중인 플레이스가 없어요',
                  ),
                  _EventTabList(
                    docs: inactiveDocs,
                    emptyIcon: Icons.visibility_off_outlined,
                    emptyMessage: '숨긴 플레이스가 없어요',
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EventTabList extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;
  final IconData emptyIcon;
  final String emptyMessage;

  const _EventTabList({
    required this.docs,
    required this.emptyIcon,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(emptyIcon, size: 56, color: Colors.black26),
            const SizedBox(height: 12),
            Text(emptyMessage, style: const TextStyle(color: Colors.black45)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: docs.length,
      itemBuilder: (_, i) {
        final doc = docs[i];
        final data = doc.data() as Map<String, dynamic>;
        return _MyEventCard(eventId: doc.id, data: data);
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 호스트 카드의 관리 메뉴 — 플레이스(events) 카드와 공간대여(places) 카드가
// **같은 위젯을 쓴다.** 두 카드가 제공하는 기능이 같은데 버튼을 따로 만들면
// 크기·여백이 미세하게 어긋나 서로 다른 급의 기능처럼 보인다.
// ─────────────────────────────────────────────────────────────────────────────

/// 카드 아래 관리 메뉴 한 줄 — `🎉 연결 파티 N개`와 `✨ 연결 이벤트 N개`.
///
/// 두 칸은 **가로로 나란히** 서고, 자리가 모자라면 아랫줄로 접힌다([Wrap]) —
/// 360dp 폰에서 두 칸이 한 줄에 다 들어가지 않아도 글자가 잘리거나 넘치지
/// 않는다. 칸 자체는 둘 다 [HostCardMenuAction] 하나로 그린다.
///
/// **정본은 각자 그대로다** — 파티는 `parties`의 연결 필드, 이벤트는
/// `placePromotions`의 소속 필드(자세한 배경은 host_card_link_menus.dart 상단).
class _HostCardMenuRow extends StatelessWidget {
  const _HostCardMenuRow({
    required this.targetId,
    required this.data,
    required this.target,
  });

  /// 대상 문서 id — events/{id} 또는 places/{id}.
  final String targetId;
  final Map<String, dynamic> data;
  final PartyLinkTarget target;

  @override
  Widget build(BuildContext context) {
    // 이벤트 흐름의 정본 값 묶음 — 원본 장소 문서에서 읽은
    // placeId/placeCollection/hostId 그대로다([EventPlaceTarget]).
    final eventTarget = EventPlaceTarget.fromDoc(
      id: targetId,
      collection: target.collection,
      data: data,
    );
    // 강조색도 공간 유형 정본에서 온다 — 예전에 두 카드가 각각 적어 두던
    // 값(플레이스 0xFFFF6FA0 / 공간대여 0xFF7C5CBF)과 같은 색이다.
    final accent = eventTarget.accent;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _LinkedPartyMenu(
          targetId: targetId,
          data: data,
          target: target,
          accent: accent,
        ),
        // ✨ 연결 이벤트 — 이 장소의 `placePromotions`를 세고, 누르면 기존
        // 이벤트 관리 화면을 연다(새 관리 UI를 만들지 않는다).
        LinkedEventMenu(target: eventTarget),
      ],
    );
  }
}

/// `🎉 연결 파티 N개` 메뉴 — 개수를 세어 보여주고, 누르면 파티 연결 관리
/// 화면을 연다. 돌아오면 개수를 다시 센다.
///
/// 개수를 여기서 들고 있는 이유: 카드 자체는 개수를 쓰지 않는데 그것 때문에
/// 카드 전체가 상태를 갖게 되면, 플레이스·공간대여 두 카드가 똑같은 상태
/// 관리 코드를 각자 갖게 된다.
class _LinkedPartyMenu extends StatefulWidget {
  /// 대상 문서 id — events/{id} 또는 places/{id}.
  final String targetId;

  /// 대상 문서 데이터(연결 시 파티에 복사할 장소 정보의 출처).
  final Map<String, dynamic> data;

  final PartyLinkTarget target;
  final Color accent;

  const _LinkedPartyMenu({
    required this.targetId,
    required this.data,
    required this.target,
    required this.accent,
  });

  @override
  State<_LinkedPartyMenu> createState() => _LinkedPartyMenuState();
}

class _LinkedPartyMenuState extends State<_LinkedPartyMenu> {
  /// 연결된 파티 수 — 아직 못 읽었으면 null.
  int? _count;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final count = await PlacePartyLink.countLinkedParties(
        widget.targetId,
        target: widget.target,
      );
      if (!mounted) return;
      setState(() => _count = count);
    } catch (_) {
      // 개수는 보조 정보라 실패해도 메뉴 자체는 그대로 보여준다.
    }
  }

  Future<void> _open() async {
    await Navigator.push(
      context,
      webFramedRoute(
        (_) => PlacePartyLinkScreen(
          targetId: widget.targetId,
          place: widget.data,
          target: widget.target,
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return HostCardMenuAction(
      emoji: '🎉',
      // 아직 못 셌으면 숫자를 비워 둔다 — '확인 중...' 같은 긴 문구를 넣으면
      // 그 사이 줄이 밀린다.
      label: _count == null ? '연결 파티' : '연결 파티 $_count개',
      accent: widget.accent,
      onTap: _open,
    );
  }
}

class _MyEventCard extends StatelessWidget {
  final String eventId;
  final Map<String, dynamic> data;

  const _MyEventCard({required this.eventId, required this.data});

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String? ?? '플레이스';
    final rawLocation = data['location'] as String? ?? '';
    final location = rawLocation.isEmpty
        ? ''
        : RegionData.shortDistrictDong(rawLocation);
    final mainImgUrl = data['mainImageUrl'] as String? ?? '';
    final isActive = data['isActive'] != false;
    // 숨긴 시각 — 자동 삭제(14일)의 기준점. 노출 중이면 볼 필요가 없다.
    final rawHiddenAt = data['hiddenAt'];
    final hiddenAt = !isActive && rawHiddenAt is Timestamp
        ? rawHiddenAt.toDate()
        : null;
    final autoDeleteLabel = AutoDeleteRetention.label(hiddenAt);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        webFramedRoute((_) => EventEditScreen(eventId: eventId, data: data)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x10000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(16),
              ),
              child: SizedBox(
                width: 90,
                height: 90,
                child: mainImgUrl.isNotEmpty
                    ? Image.network(
                        mainImgUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, e, st) =>
                            Container(color: const Color(0xFFFFE0EE)),
                      )
                    : Container(
                        color: const Color(0xFFFFE0EE),
                        child: const Icon(
                          Icons.celebration_outlined,
                          size: 32,
                          color: Color(0xFFFF6FA0),
                        ),
                      ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isActive
                                ? const Color(0xFFF0FFF4)
                                : const Color(0xFFF5F5F7),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isActive
                                  ? const Color(0xFFB3E6C8)
                                  : const Color(0xFFDDDDDD),
                            ),
                          ),
                          child: Text(
                            isActive ? '노출 중' : '숨김',
                            style: TextStyle(
                              fontSize: 11,
                              color: isActive
                                  ? const Color(0xFF2E7D32)
                                  : Colors.black45,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        location,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black45,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    // 숨긴 플레이스의 자동 삭제 예정 — 장소대여 카드·지난
                    // 파티와 같은 정본을 쓴다([AutoDeleteRetention], 14일).
                    // hiddenAt이 없는 옛 문서는 null이라 아무 말도 하지 않는다
                    // (서버도 그런 문서는 지우지 않는다).
                    if (autoDeleteLabel != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        autoDeleteLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AutoDeleteRetention.isUrgent(hiddenAt)
                              ? Colors.redAccent
                              : const Color(0xFFE65100),
                        ),
                      ),
                    ],
                    // ── 관리 메뉴 한 줄 ──────────────────────────────
                    //
                    // 위쪽은 플레이스가 무엇인지(썸네일·노출 상태·이름·지역),
                    // 여기부터는 무엇을 할 수 있는지다.
                    //
                    // 연결 파티 개수는 parties.linkedEventId 기준으로 센다
                    // (플레이스 문서의 보조 배열이 아니라). 연결/해제를 마치고
                    // 돌아오면 다시 센다.
                    //
                    // 이벤트도 같은 줄에서 센다 — `✨ 연결 이벤트 N개`를 누르면
                    // 기존 이벤트 관리 화면이 열린다(상단 🎪 이벤트 탭이 여는
                    // 것과 **같은 화면**이라 관리 방법이 두 갈래로 갈리지 않는다).
                    // 이벤트 개수의 정본은 placePromotions의 소속 필드다.
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _HostCardMenuRow(
                            targetId: eventId,
                            data: data,
                            target: PartyLinkTarget.place,
                          ),
                        ),
                        // 다른 콘텐츠와 동일한 공용 삭제 흐름 — 자리도 기능도
                        // 그대로 카드 오른쪽 끝이다.
                        DeleteContentIconButton(
                          type: DeletableContent.event,
                          id: eventId,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 내 파트너(크루) 탭 — crews는 name/imageUrls가 없는 구인·구직 게시물
// 스키마라 title/role/regions로 표시한다. 상세 화면은 아직 없고, 여기서
// 모집 상태 토글(isActive) · 수정 · 삭제를 제공한다.
//
// 수정은 파티크루 **등록 화면(정본)** 을 수정 모드로 연다
// (CrewRegisterScreen.edit) — 별도 수정 화면을 만들어 두 벌이 갈라지는 일을
// 처음부터 막기 위해서다. 모집 상태는 이 카드의 토글이 계속 담당한다.
// ─────────────────────────────────────────────────────────────────────────────

class _MyCrewList extends StatefulWidget {
  const _MyCrewList();

  @override
  State<_MyCrewList> createState() => _MyCrewListState();
}

class _MyCrewListState extends State<_MyCrewList>
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
    // 로그인 화면에서 로그인을 마치고 돌아왔을 때 뒤로 갔다 다시 들어오지
    // 않아도 즉시 로그인 상태가 반영되도록 AuthRebuilder로 감싼다.
    return AuthRebuilder(builder: _buildLoggedGate);
  }

  Widget _buildLoggedGate(BuildContext context) {
    final userId = UserSession.userId;

    if (userId.isEmpty) {
      return const Center(
        child: Text('로그인 후 이용 가능합니다.', style: TextStyle(color: Colors.black45)),
      );
    }

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          labelColor: const Color(0xFFFF9A56),
          unselectedLabelColor: Colors.black45,
          indicatorColor: const Color(0xFFFF9A56),
          indicatorWeight: 2,
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          tabs: const [
            Tab(text: '모집 중'),
            Tab(text: '마감'),
          ],
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            // ⚠️ orderBy('createdAt')를 where('hostId')와 함께 쓰면 복합 색인이
            // 필요한데 crews에는 그 색인이 없다 — 실제로 이 스트림은 늘
            // FAILED_PRECONDITION으로 죽었고, 아래에 오류 분기도 없어서
            // hasData가 영원히 false인 **영구 스피너**로 보였다(등록한 글이
            // 있든 없든 똑같이). 색인을 새로 배포하는 대신 정렬을 클라이언트로
            // 옮겨 복합 색인 자체를 없앤다 — 내 장소/내 파티 목록과 같은 패턴.
            stream: FirebaseFirestore.instance
                .collection('crews')
                .where('hostId', isEqualTo: userId)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                logFirestoreStreamError(
                  'MyCrewList',
                  snapshot.error,
                  snapshot.stackTrace,
                );
                return const _HostListError(
                  message: '내 파티크루 글을 불러오지 못했어요.\n잠시 후 다시 시도해주세요.',
                );
              }
              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFFFF9A56)),
                );
              }

              final activeDocs = <QueryDocumentSnapshot>[];
              final inactiveDocs = <QueryDocumentSnapshot>[];

              for (final doc in _sortedByCreatedAtDesc(snapshot.data!.docs)) {
                final d = doc.data() as Map<String, dynamic>;
                if (d['isActive'] == false) {
                  inactiveDocs.add(doc);
                } else {
                  activeDocs.add(doc);
                }
              }

              return TabBarView(
                controller: _tabController,
                // 바깥 카테고리 탭(파티츄/플레이스/공간대여/파티크루)도 좌우
                // 드래그로 전환되는 TabBarView라, 이 안쪽 상태 탭까지 드래그를
                // 받으면 같은 제스처를 둘이 경합해 안쪽이 이겨버린다 — 그러면
                // 카테고리를 드래그로 넘길 수 없다. 안쪽은 탭(클릭) 전환만
                // 두고 드래그는 항상 바깥 카테고리 전용으로 남긴다
                // (main_screen.dart의 파티크루 구인/구직 탭과 같은 처리).
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _CrewTabList(docs: activeDocs, emptyMessage: '모집 중인 글이 없어요'),
                  _CrewTabList(docs: inactiveDocs, emptyMessage: '마감된 글이 없어요'),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CrewTabList extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;
  final String emptyMessage;

  const _CrewTabList({required this.docs, required this.emptyMessage});

  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎤', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(emptyMessage, style: const TextStyle(color: Colors.black45)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: docs.length,
      itemBuilder: (_, i) {
        final doc = docs[i];
        final data = doc.data() as Map<String, dynamic>;
        return _MyCrewCard(docId: doc.id, data: data);
      },
    );
  }
}

class _MyCrewCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;

  const _MyCrewCard({required this.docId, required this.data});

  Future<void> _toggleActive(BuildContext context) async {
    final current = data['isActive'] as bool?;
    final next = current == false;
    try {
      await FirebaseFirestore.instance.collection('crews').doc(docId).update({
        'isActive': next,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next ? '모집 중으로 변경되었습니다' : '마감으로 변경되었습니다'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('변경 실패: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final crewType = data['crewType'] as String? ?? '';
    final title = data['title'] as String? ?? '';
    final role = data['role'] as String? ?? '';
    // "서울 강남구 · 부산 전체" — 광역만 저장돼 있던 옛 글은 "서울 전체"로 읽힌다.
    final region = CrewArea.labelOfCrewData(data);
    final isActive = data['isActive'] != false;
    final isHiring = crewType == '구인';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0FFF6FA0),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isHiring
                      ? const Color(0xFFFFF0F5)
                      : const Color(0xFFF3EFFA),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  crewType,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isHiring
                        ? const Color(0xFFFF6FA0)
                        : const Color(0xFF7C5CBF),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFFF0FFF4)
                      : const Color(0xFFF5F5F7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isActive
                        ? const Color(0xFFB3E6C8)
                        : const Color(0xFFDDDDDD),
                  ),
                ),
                child: Text(
                  isActive ? '모집 중' : '마감',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isActive ? const Color(0xFF2E7D32) : Colors.black45,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (role.isNotEmpty || region.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              [role, region].where((s) => s.isNotEmpty).join(' · '),
              style: const TextStyle(fontSize: 12, color: Colors.black45),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(
            children: [
              GestureDetector(
                onTap: () => _toggleActive(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isActive
                            ? Icons.pause_circle_outline
                            : Icons.play_circle_outline,
                        size: 14,
                        color: isActive
                            ? Colors.orange
                            : const Color(0xFF2E7D32),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isActive ? '마감으로 변경' : '모집 재개',
                        style: TextStyle(
                          fontSize: 12,
                          color: isActive
                              ? Colors.orange
                              : const Color(0xFF2E7D32),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 수정 — 파티크루 등록 화면(정본)을 수정 모드로 연다. 입력
              // 항목·검증이 등록과 100% 같고, 저장만 기존 문서 update로 나간다.
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  webFramedRoute(
                    (_) =>
                        CrewRegisterScreen.edit(docId: docId, sourceData: data),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.edit_outlined,
                        size: 14,
                        color: Color(0xFFFF9A56),
                      ),
                      SizedBox(width: 4),
                      Text(
                        '수정',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFFFF9A56),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              // 파티·장소와 동일한 공용 삭제 흐름.
              DeleteContentIconButton(type: DeletableContent.crew, id: docId),
            ],
          ),
        ],
      ),
    );
  }
}

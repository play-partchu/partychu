import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:party_app/models/region_data.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/auth_rebuilder.dart';
import 'package:party_app/widgets/nickname_edit_dialog.dart';
import 'package:party_app/screens/party_edit_screen.dart';
import 'package:party_app/screens/party_register_screen.dart';
import 'package:party_app/screens/place_edit_screen.dart';
import 'package:party_app/utils/party_utils.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/utils/format_utils.dart';
import 'package:party_app/screens/settlement_info_screen.dart';
import 'package:party_app/screens/feedback_compose_screen.dart';
import 'package:party_app/screens/my_feedback_list_screen.dart';
import 'package:party_app/services/cloudflare_service.dart';
import 'package:party_app/utils/early_bird.dart';
import 'package:party_app/widgets/party_card_widget.dart';
import 'package:party_app/screens/party_shop_manage_screen.dart';
import 'package:party_app/screens/my_favorites_screen.dart';
import 'package:party_app/screens/party_detail_screen.dart';
import 'package:party_app/screens/my_package_bookings_screen.dart';
import 'package:party_app/screens/my_reservations_screen.dart';
import 'package:party_app/screens/event_edit_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 마이페이지 메인
// ─────────────────────────────────────────────────────────────────────────────

class MyPageScreen extends StatefulWidget {
  const MyPageScreen({super.key});

  @override
  State<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends State<MyPageScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        title: const Text(
          '마이페이지',
          style: TextStyle(fontFamily: 'SeoulHangang', fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))]),
        ),
      ),
      // 사용 빈도 순으로 위에서부터: 프로필 → 내 콘텐츠(가장 크게) →
      // 관심 목록 → 관리(설정성 메뉴, 작게) → 로그아웃. 예전엔 정산계좌관리
      // 등 관리 메뉴가 파티/장소 탭보다 먼저·크게 보여 시선이 분산됐었다.
      // 로그인 화면에서 로그인을 마치고 돌아왔을 때 뒤로 갔다 다시 들어오지
      // 않아도 프로필/내 콘텐츠가 즉시 로그인 상태를 반영하도록
      // AuthRebuilder로 감싼다.
      body: AuthRebuilder(
        builder: (context) => ListView(
          children: [
            _buildProfileHeader(),
            const SizedBox(height: 10),
            _buildMyContentGrid(context),
            const SizedBox(height: 10),
            _buildFavoritesMenuItem(context),
            const SizedBox(height: 10),
            _buildReservationsMenuItem(context),
            const SizedBox(height: 10),
            _buildPackageBookingsMenuItem(context),
            const SizedBox(height: 14),
            _buildManageSection(context),
            const SizedBox(height: 10),
            _buildLogoutSection(context),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── 내 콘텐츠 — 왼쪽에 "운영"(호스트) / "참가"(참가자) 카드 2개를 위아래로
  // 배치하고, 오른쪽 3개(장소/파티샵/파트너)는 그대로 세로 나열한다. 예전엔
  // "내 파티" 하나에 호스트·참가자 기능이 섞여 있었는데, 역할을 명확히
  // 구분해달라는 요청에 따라 카드를 분리했다 — 전체 레이아웃 크기(236)는
  // 그대로 유지해 다른 카드들과의 균형은 그대로 둔다.
  Widget _buildMyContentGrid(BuildContext context) {
    final userId = UserSession.userId;

    final hostPartyCard = _MyContentMediumCard(
      emoji: '🎉',
      label: '운영',
      description: '운영자가 관리하는 파티',
      accent: const Color(0xFFFF6FA0),
      countStream: userId.isEmpty
          ? const Stream.empty()
          : FirebaseFirestore.instance
                .collection('parties')
                .where('hostId', isEqualTo: userId)
                .snapshots()
                .map(
                  (s) => s.docs.where((d) {
                    final data = d.data();
                    return data['isDeleted'] != true &&
                        data['status'] != 'deleted';
                  }).length,
                ),
      onTap: () => _openContentScreen(context, '운영', const _MyPartyList()),
    );

    // 참가 이력은 parties/{id}/applications/{uid} 서브컬렉션이 단일
    // 출처다 — 취소된 신청도 status로 구분해 그대로 남아있으므로 여기서는
    // 취소 제외 건수만 뱃지로 보여준다(취소 내역은 카드 진입 후 탭에서 확인).
    final joinedPartyCard = _MyContentMediumCard(
      emoji: '🙋',
      label: '참가',
      description: '참가자로 신청한 파티',
      accent: const Color(0xFF3D5AFE),
      countStream: userId.isEmpty
          ? const Stream.empty()
          : FirebaseFirestore.instance
                .collectionGroup('applications')
                .where('uid', isEqualTo: userId)
                .snapshots()
                .map(
                  (s) => s.docs
                      .where(
                        (d) =>
                            (d.data()['status'] as String? ?? 'applied') !=
                                'cancelled' &&
                            // 숙박+파티 패키지 신청은 "숙박+파티 패키지"
                            // 카드에서 별도로 집계한다.
                            d.data()['bundleBookingId'] == null,
                      )
                      .length,
                ),
      onTap: () =>
          _openContentScreen(context, '참가', const _MyJoinedPartyList()),
    );

    final sideCards = [
      _MyContentSmallCard(
        emoji: '🏠',
        label: '내 장소',
        accent: const Color(0xFF7C5CBF),
        countStream: userId.isEmpty
            ? const Stream.empty()
            : FirebaseFirestore.instance
                  .collection('places')
                  .where('hostId', isEqualTo: userId)
                  .snapshots()
                  .map((s) => s.docs.length),
        onTap: () => _openContentScreen(context, '내 장소', const _MyPlaceList()),
      ),
      _MyContentSmallCard(
        emoji: '🛍️',
        label: '내 파티샵',
        accent: const Color(0xFF1A73E8),
        countStream: userId.isEmpty
            ? const Stream.empty()
            : FirebaseFirestore.instance
                  .collection('partyShops')
                  .where('hostId', isEqualTo: userId)
                  .snapshots()
                  .map((s) => s.docs.length),
        onTap: () => _openContentScreen(context, '내 파티샵', const _MyShopList()),
      ),
      _MyContentSmallCard(
        emoji: '🤝',
        label: '내 파트너',
        accent: const Color(0xFFFF9A56),
        countStream: userId.isEmpty
            ? const Stream.empty()
            : FirebaseFirestore.instance
                  .collection('crews')
                  .where('hostId', isEqualTo: userId)
                  .snapshots()
                  .map((s) => s.docs.length),
        onTap: () => _openContentScreen(context, '내 파트너', const _MyCrewList()),
      ),
      _MyContentSmallCard(
        emoji: '📍',
        label: '내 플레이스',
        accent: const Color(0xFFFF6FA0),
        countStream: userId.isEmpty
            ? const Stream.empty()
            : FirebaseFirestore.instance
                  .collection('events')
                  .where('hostId', isEqualTo: userId)
                  .snapshots()
                  .map((s) => s.docs.length),
        onTap: () => _openContentScreen(context, '내 플레이스', const _MyEventList()),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 앱 전체의 태블릿/데스크톱 기준(Responsive, 700px)과는 별개로,
          // 이 영역만 화면분할 등으로 매우 좁아졌을 때(폰 한 대 기준으로는
          // 거의 걸리지 않음) 오버플로를 막기 위한 로컬 기준이다 — 일반
          // 스마트폰 폭에서는 항상 "운영/참가 + 오른쪽 3개" 레이아웃 유지.
          // 이 constraints.maxWidth는 좌우 16px 패딩이 이미 빠진 값이라,
          // 임계값을 기기 폭 그대로로 잡으면(예 360) iPhone 12/13/14(390)처럼
          // 흔한 기기까지 세로 스택으로 떨어진다. 실제로 화면분할 등 매우
          // 좁을 때만 걸리도록 낮게 잡는다.
          final isNarrow = constraints.maxWidth < 300;

          if (isNarrow) {
            return Column(
              children: [
                SizedBox(height: 70, child: hostPartyCard),
                const SizedBox(height: 10),
                SizedBox(height: 70, child: joinedPartyCard),
                for (final card in sideCards) ...[
                  const SizedBox(height: 10),
                  card,
                ],
              ],
            );
          }

          return SizedBox(
            height: 236,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    children: [
                      Expanded(child: hostPartyCard),
                      const SizedBox(height: 10),
                      Expanded(child: joinedPartyCard),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 4,
                  child: Column(
                    children: [
                      for (var i = 0; i < sideCards.length; i++) ...[
                        if (i != 0) const SizedBox(height: 10),
                        Expanded(child: sideCards[i]),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openContentScreen(BuildContext context, String title, Widget body) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: const Color(0xFFFFF4F8),
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            foregroundColor: Colors.black,
            title: Text(
              title,
              style: const TextStyle(fontFamily: 'SeoulHangang', fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))]),
            ),
          ),
          body: body,
        ),
      ),
    );
  }

  // ── 관심(찜) 목록 — 그리드 다음으로 눈에 띄는 두 번째 우선순위 ───────
  Widget _buildFavoritesMenuItem(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyFavoritesScreen()),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                const Icon(Icons.pets, color: Color(0xFFFF6FA0), size: 22),
                const SizedBox(width: 10),
                const Text(
                  '관심 목록',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                const Icon(Icons.chevron_right, color: Colors.black45),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReservationsMenuItem(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyReservationsScreen()),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                const Icon(Icons.event_available_outlined,
                    color: Color(0xFF7C5CBF), size: 22),
                const SizedBox(width: 10),
                const Text(
                  '내 예약',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                const Icon(Icons.chevron_right, color: Colors.black45),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPackageBookingsMenuItem(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyPackageBookingsScreen()),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                const Icon(Icons.card_giftcard, color: Color(0xFFD94F7A), size: 22),
                const SizedBox(width: 10),
                const Text(
                  '숙박+파티 패키지',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                const Icon(Icons.chevron_right, color: Colors.black45),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 관리(설정성 메뉴) — 우선순위를 낮춰 ListTile 크기로 축소 ─────────
  Widget _buildManageSection(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text(
              '관리',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.black45,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(
              Icons.account_balance_wallet_outlined,
              color: Colors.black87,
            ),
            title: const Text('정산 계좌 관리'),
            subtitle: const Text(
              '파티 수익 입금 계좌 설정',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.black45),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettlementInfoScreen()),
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(
              Icons.chat_bubble_outline,
              color: Colors.black87,
            ),
            title: const Text('의견 보내기'),
            subtitle: const Text(
              '서비스 개선 의견 · 버그 · 문의 보내기',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.black45),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FeedbackComposeScreen()),
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.history_outlined, color: Colors.black87),
            title: const Text('내 의견 내역'),
            subtitle: const Text(
              '보낸 의견의 처리 상태 확인',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.black45),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MyFeedbackListScreen()),
            ),
          ),
          if (kDebugMode) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(
                Icons.delete_sweep_outlined,
                color: Colors.red,
              ),
              title: const Text(
                '[DEV] 전체 파티 삭제',
                style: TextStyle(color: Colors.red),
              ),
              subtitle: const Text(
                'Firestore parties 컬렉션 전체 삭제',
                style: TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.red),
              onTap: () => _deleteAllParties(context),
            ),
          ],
        ],
      ),
    );
  }

  // ── 로그아웃 — 가장 낮은 우선순위, 맨 아래 ───────────────────────────
  Widget _buildLogoutSection(BuildContext context) {
    return Container(
      color: Colors.white,
      child: ListTile(
        leading: const Icon(Icons.logout, color: Colors.black54),
        title: const Text('로그아웃'),
        onTap: () => _confirmLogout(context),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('로그아웃', style: TextStyle(fontFamily: 'SeoulHangang', fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])),
        content: const Text('로그아웃 하시겠어요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('로그아웃', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await UserSession.signOut();
    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _deleteAllParties(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('[DEV] 전체 파티 삭제', style: TextStyle(fontFamily: 'SeoulHangang', fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])),
        content: const Text('Firestore의 모든 파티 데이터를 삭제합니다.\n이 작업은 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('전체 삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('parties')
          .get();
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${snapshot.docs.length}개 파티가 삭제되었습니다')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
      }
    }
  }

  Widget _buildProfileHeader() {
    final verified = UserSession.identityVerified;
    final loggedIn = UserSession.userId.isNotEmpty;
    final hasNickname = UserSession.hasNickname;
    final hasPhoto = UserSession.profileImageUrl.isNotEmpty;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Row(
        children: [
          GestureDetector(
            onTap: loggedIn ? _openProfileImageSheet : null,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: const Color(0xFFDDD5FF),
                  backgroundImage: hasPhoto
                      ? NetworkImage(UserSession.profileImageUrl)
                      : null,
                  child: !hasPhoto
                      ? const Icon(Icons.person, size: 30, color: Colors.white)
                      : null,
                ),
                if (loggedIn)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6FA0),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        size: 11,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: loggedIn ? _editNickname : null,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          !loggedIn
                              ? '로그인 필요'
                              : (hasNickname
                                    ? UserSession.nickname
                                    : '닉네임을 설정해주세요'),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: hasNickname
                                ? Colors.black87
                                : Colors.black38,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (loggedIn) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.edit_outlined,
                          size: 14,
                          color: Colors.black38,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  loggedIn ? UserSession.userId : '로그인 후 프로필을 설정할 수 있어요',
                  style: const TextStyle(fontSize: 12, color: Colors.black45),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                if (loggedIn)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: verified
                          ? const Color(0xFFE8F5E9)
                          : const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          verified
                              ? Icons.verified_user
                              : Icons.warning_amber_rounded,
                          size: 12,
                          color: verified
                              ? const Color(0xFF388E3C)
                              : const Color(0xFFF57C00),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          verified ? '본인인증 완료' : '본인인증 필요',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: verified
                                ? const Color(0xFF388E3C)
                                : const Color(0xFFF57C00),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 닉네임 변경 ───────────────────────────────────────────────────
  Future<void> _editNickname() async {
    final saved = await showNicknameEditDialog(context);
    if (saved && mounted) setState(() {});
  }

  // ── 프로필 사진 선택/삭제 BottomSheet ────────────────────────────────
  Future<void> _openProfileImageSheet() async {
    final hasPhoto = UserSession.profileImageUrl.isNotEmpty;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.photo_camera_outlined,
                color: Colors.black87,
              ),
              title: const Text('카메라로 촬영'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_outlined,
                color: Colors.black87,
              ),
              title: const Text('앨범에서 선택'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('사진 삭제', style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            ListTile(
              leading: const Icon(Icons.close, color: Colors.black54),
              title: const Text('취소'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'camera') {
      await _pickAndCropProfileImage(ImageSource.camera);
    } else if (action == 'gallery') {
      await _pickAndCropProfileImage(ImageSource.gallery);
    } else if (action == 'delete') {
      await _deleteProfileImage();
    }
  }

  // 카메라 촬영/앨범 선택 모두 이 경로를 거친다 — 사진을 고른 즉시 업로드하지
  // 않고 원형 크롭 편집(_cropProfileImage) → 결과 미리보기 확인
  // (_confirmCroppedPreview)을 먼저 거친 뒤에만 업로드한다. 각 단계에서
  // 사용자가 취소하면(권한 거부 포함) 조용히 중단되고 아무 것도 저장되지 않는다.
  Future<void> _pickAndCropProfileImage(ImageSource source) async {
    XFile? picked;
    try {
      picked = await ImagePicker().pickImage(source: source, imageQuality: 90);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              source == ImageSource.camera
                  ? '카메라를 사용할 수 없어요. 권한을 확인해주세요.'
                  : '사진에 접근할 수 없어요. 권한을 확인해주세요.',
            ),
          ),
        );
      }
      return;
    }
    if (picked == null || !mounted) return; // 사용자가 촬영/선택을 취소함

    final cropped = await _cropProfileImage(picked.path);
    if (cropped == null || !mounted) return; // 크롭 화면에서 취소함
    final croppedFile = File(cropped.path);

    final confirmed = await _confirmCroppedPreview(croppedFile);
    if (!confirmed || !mounted) return; // 미리보기에서 다시 선택을 고름

    await _uploadProfileImage(croppedFile);
  }

  // 실제 프로필에 보일 크기(원형) 기준으로 확대/축소·드래그 이동·중앙 맞춤이
  // 가능한 편집 화면을 띄운다. 원형 가이드 밖은 자동으로 어둡게 표시되고,
  // 취소/적용 버튼은 네이티브 크롭 화면(UCrop/TOCropViewController)이
  // 기본 제공한다. 원본 파일(sourcePath)은 건드리지 않고, 크롭 결과만
  // 새 임시 파일로 반환된다.
  Future<CroppedFile?> _cropProfileImage(String sourcePath) {
    return ImageCropper().cropImage(
      sourcePath: sourcePath,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 90,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: '프로필 사진 편집',
          toolbarColor: const Color(0xFFFF6FA0),
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: const Color(0xFFFF6FA0),
          statusBarLight: false,
          cropStyle: CropStyle.circle,
          lockAspectRatio: true,
          hideBottomControls: true,
          initAspectRatio: CropAspectRatioPreset.square,
          aspectRatioPresets: const [CropAspectRatioPreset.square],
        ),
        IOSUiSettings(
          title: '프로필 사진 편집',
          cropStyle: CropStyle.circle,
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          aspectRatioPickerButtonHidden: true,
          rotateButtonsHidden: true,
          doneButtonTitle: '적용',
          cancelButtonTitle: '취소',
        ),
      ],
    );
  }

  // 크롭 결과를 실제 프로필과 동일하게 원형으로 미리 보여주고, 이 사진으로
  // 저장할지 다시 고를지 마지막으로 확인한다.
  Future<bool> _confirmCroppedPreview(File file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text(
          '프로필 사진 확인',
          style: TextStyle(
            fontFamily: 'SeoulHangang',
            fontSize: 16,
            fontWeight: FontWeight.w500,
            shadows: [
              Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
              Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
            ],
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipOval(
              child: Image.file(
                file,
                width: 140,
                height: 140,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '이 사진으로 프로필을 설정할까요?',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('다시 선택'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6FA0),
              foregroundColor: Colors.white,
            ),
            child: const Text('적용'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  // 업로드/저장 로직은 기존 그대로 — Cloudflare에 업로드하고 Firestore/
  // UserSession을 갱신한 뒤 이전 사진을 정리한다. 이제 원본이 아니라
  // 크롭된 결과 파일만 전달받아 업로드한다.
  Future<void> _uploadProfileImage(File file) async {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF6FA0)),
      ),
    );
    try {
      final oldUrl = UserSession.profileImageUrl;
      final url = await CloudflareService.uploadImage(file);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(UserSession.userId)
          .set({'profileImageUrl': url}, SetOptions(merge: true));
      UserSession.profileImageUrl = url;
      if (oldUrl.isNotEmpty) {
        unawaited(CloudflareService.deleteImage(oldUrl).catchError((_) {}));
      }
      if (mounted) {
        Navigator.pop(context); // 로딩 닫기
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // 로딩 닫기
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('사진 업로드에 실패했어요: $e')));
      }
    }
  }

  Future<void> _deleteProfileImage() async {
    final url = UserSession.profileImageUrl;
    if (url.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(UserSession.userId)
          .set({
            'profileImageUrl': FieldValue.delete(),
          }, SetOptions(merge: true));
      unawaited(CloudflareService.deleteImage(url).catchError((_) {}));
      UserSession.profileImageUrl = '';
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('사진 삭제에 실패했어요: $e')));
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 내 콘텐츠 그리드 카드 — 아이콘(이모지) + 제목 + 등록 개수, 탭 애니메이션은
// Material/InkWell의 기본 리플로 처리한다.
// ─────────────────────────────────────────────────────────────────────────────

// "운영"/"참가" 카드 — 예전엔 "내 파티" 하나가 이 자리를 세로 방향으로
// 크게 차지했지만, 호스트/참가자 역할을 나눈 뒤로는 같은 자리를 위아래로
// 나눠 쓰는 가로형 카드다. 이모지+제목+설명을 왼쪽에, 개수를 오른쪽에 둬
// 낮은 높이에서도 갑갑해 보이지 않게 한다.
class _MyContentMediumCard extends StatelessWidget {
  final String emoji;
  final String label;
  final String description;
  final Color accent;
  final Stream<int> countStream;
  final VoidCallback onTap;

  const _MyContentMediumCard({
    required this.emoji,
    required this.label,
    required this.description,
    required this.accent,
    required this.countStream,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: 0.2)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [accent.withValues(alpha: 0.10), Colors.white],
            ),
          ),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 30)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black45,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              StreamBuilder<int>(
                stream: countStream,
                builder: (context, snapshot) {
                  final count = snapshot.data ?? 0;
                  return Text(
                    '$count개',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 내 장소 / 내 파티샵 / 내 파트너 — 오른쪽에 세로로 나열되는 작은 ListTile
// 형태 카드. 부모(Row의 Expanded 또는 좁은 화면의 Column)가 높이를 결정하므로
// 이 위젯 자체는 고정 높이를 갖지 않는다.
class _MyContentSmallCard extends StatelessWidget {
  final String emoji;
  final String label;
  final Color accent;
  final Stream<int> countStream;
  final VoidCallback onTap;

  const _MyContentSmallCard({
    required this.emoji,
    required this.label,
    required this.accent,
    required this.countStream,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              StreamBuilder<int>(
                stream: countStream,
                builder: (context, snapshot) {
                  final count = snapshot.data ?? 0;
                  return Text(
                    '$count개',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
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
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  static DateTime? _parseDate(Map<String, dynamic> d) {
    final ts = d['partyDateTime'];
    if (ts is Timestamp) return ts.toDate().toLocal();
    final sdt = d['startDateTime'];
    if (sdt is Timestamp) return sdt.toDate().toLocal();
    if (sdt is String && sdt.isNotEmpty) {
      return DateTime.tryParse(sdt)?.toLocal();
    }
    final s = d['date'] as String?;
    if (s != null && s.isNotEmpty) return DateTime.tryParse(s)?.toLocal();
    return null;
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
                if (dt == null || !dt.isBefore(now)) {
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

  // 지난 파티 탭 상단에 항상 표시되는 안내 배너
  static Widget _pastWarningBanner() => Container(
    margin: const EdgeInsets.fromLTRB(0, 0, 0, 12),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF3E0),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFFFCC80)),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFE65100)),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            '지난 파티는 종료일로부터 30일간 보관되며, '
            '30일이 지나면 자동으로 삭제됩니다.',
            style: TextStyle(
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
// 참가 탭 — 참여 예정 / 참여 완료 / 참여 취소
//
// parties/{partyId}/applications/{uid} 서브컬렉션이 단일 출처다(applyToParty가
// 신청 시점에 남기고, cancelApplication/onPartyCancelledByHost가 취소 시
// status를 갱신한다). collectionGroup 쿼리로 내 uid가 걸린 신청서를 전부
// 가져온 뒤, status와 신청 시점에 스냅샷으로 남은 partyDateTime으로 3개
// 탭에 나눠 담는다 — 파티 문서를 다시 조인하지 않아도 분류가 가능하다.
// ─────────────────────────────────────────────────────────────────────────────

class _MyJoinedPartyList extends StatefulWidget {
  const _MyJoinedPartyList();

  @override
  State<_MyJoinedPartyList> createState() => _MyJoinedPartyListState();
}

class _MyJoinedPartyListState extends State<_MyJoinedPartyList>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  static DateTime? _tsToDate(dynamic ts) =>
      ts is Timestamp ? ts.toDate() : null;

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
          labelColor: const Color(0xFF3D5AFE),
          unselectedLabelColor: Colors.black45,
          indicatorColor: const Color(0xFF3D5AFE),
          indicatorWeight: 2,
          labelStyle: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
          tabs: const [
            Tab(text: '참여 예정'),
            Tab(text: '참여 완료'),
            Tab(text: '참여 취소'),
          ],
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collectionGroup('applications')
                .where('uid', isEqualTo: userId)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFFFF6FA0)),
                );
              }

              final now = DateTime.now();
              final upcoming = <QueryDocumentSnapshot>[];
              final completed = <QueryDocumentSnapshot>[];
              final cancelled = <QueryDocumentSnapshot>[];

              for (final doc in snapshot.data!.docs) {
                final d = doc.data() as Map<String, dynamic>;
                // 숙박+파티 패키지로 생성된 신청은 여기(개별 참가 목록)가
                // 아니라 "숙박+파티 패키지" 목록에 하나로 표시된다.
                if (d['bundleBookingId'] != null) continue;
                final status = d['status'] as String? ?? 'applied';
                if (status == 'cancelled') {
                  cancelled.add(doc);
                  continue;
                }
                final dt = _tsToDate(d['partyDateTime']);
                if (dt == null || !dt.isBefore(now)) {
                  upcoming.add(doc);
                } else {
                  completed.add(doc);
                }
              }

              // 참여 예정: 가까운 날짜순
              upcoming.sort((a, b) {
                final da = _tsToDate(
                  (a.data() as Map<String, dynamic>)['partyDateTime'],
                );
                final db = _tsToDate(
                  (b.data() as Map<String, dynamic>)['partyDateTime'],
                );
                if (da == null && db == null) return 0;
                if (da == null) return 1;
                if (db == null) return -1;
                return da.compareTo(db);
              });
              // 참여 완료: 최근 종료순
              completed.sort((a, b) {
                final da = _tsToDate(
                  (a.data() as Map<String, dynamic>)['partyDateTime'],
                );
                final db = _tsToDate(
                  (b.data() as Map<String, dynamic>)['partyDateTime'],
                );
                if (da == null && db == null) return 0;
                if (da == null) return 1;
                if (db == null) return -1;
                return db.compareTo(da);
              });
              // 참여 취소: 최근 취소순
              cancelled.sort((a, b) {
                final da = _tsToDate(
                  (a.data() as Map<String, dynamic>)['statusUpdatedAt'],
                );
                final db = _tsToDate(
                  (b.data() as Map<String, dynamic>)['statusUpdatedAt'],
                );
                if (da == null && db == null) return 0;
                if (da == null) return 1;
                if (db == null) return -1;
                return db.compareTo(da);
              });

              return TabBarView(
                controller: _tabController,
                children: [
                  _JoinedPartyTabList(
                    apps: upcoming,
                    emptyIcon: Icons.event_available_outlined,
                    emptyMessage: '참여 예정인 파티가 없어요',
                  ),
                  _JoinedPartyTabList(
                    apps: completed,
                    emptyIcon: Icons.event_busy_outlined,
                    emptyMessage: '참여 완료한 파티가 없어요',
                  ),
                  _JoinedPartyTabList(
                    apps: cancelled,
                    emptyIcon: Icons.event_note_outlined,
                    emptyMessage: '취소한 참여 내역이 없어요',
                    showCancelInfo: true,
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

class _JoinedPartyTabList extends StatelessWidget {
  final List<QueryDocumentSnapshot> apps;
  final IconData emptyIcon;
  final String emptyMessage;
  final bool showCancelInfo;

  const _JoinedPartyTabList({
    required this.apps,
    required this.emptyIcon,
    required this.emptyMessage,
    this.showCancelInfo = false,
  });

  @override
  Widget build(BuildContext context) {
    if (apps.isEmpty) {
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
      itemCount: apps.length,
      itemBuilder: (_, i) {
        final doc = apps[i];
        final appData = doc.data() as Map<String, dynamic>;
        final partyId =
            appData['partyId'] as String? ??
            doc.reference.parent.parent?.id ??
            '';
        return _MyParticipationCard(
          key: ValueKey(doc.id),
          partyId: partyId,
          appData: appData,
          showCancelInfo: showCancelInfo,
        );
      },
    );
  }
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

  Widget _cancelInfoRow() {
    final cancelledBy = appData['cancelledBy'] as String?;
    final refundAmount = (appData['refundAmount'] as num?)?.toInt();
    final refundStatus = appData['refundStatus'] as String?;
    final byLabel = cancelledBy == 'host' ? '호스트가 파티를 취소했어요' : '내가 신청을 취소했어요';

    String refundLabel;
    if (refundStatus == 'not_applicable' || refundAmount == null) {
      refundLabel = '환불 없음';
    } else if (refundStatus == 'pending') {
      refundLabel = '환불 예정 ${_fmt(refundAmount)}';
    } else {
      refundLabel = '환불 ${_fmt(refundAmount)}';
    }

    return Row(
      children: [
        Icon(
          cancelledBy == 'host' ? Icons.info_outline : Icons.cancel_outlined,
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
            MaterialPageRoute(
              builder: (_) => PartyDetailScreen(docId: partyId),
            ),
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

              final docs = List<QueryDocumentSnapshot>.from(
                snapshot.data!.docs,
              )..sort((a, b) {
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

  // 숨김 탭 상단에 항상 표시되는 안내 배너 — 파티의 "지난 파티" 배너와 동일한
  // 문구 규칙(30일 보관 + 자동 삭제).
  static Widget _hiddenWarningBanner() => Container(
    margin: const EdgeInsets.fromLTRB(0, 0, 0, 12),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF3E0),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFFFCC80)),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFE65100)),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            '숨긴 장소는 숨김 처리일로부터 30일간 보관되며, '
            '30일이 지나면 자동으로 삭제됩니다.',
            style: TextStyle(
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

  Future<void> _deleteParty(BuildContext context) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final partyHostUid =
        data['hostUid'] as String? ?? data['hostId'] as String? ?? '';
    if (currentUid.isEmpty || partyHostUid != currentUid) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('작성자만 삭제할 수 있습니다.')));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('파티 삭제', style: TextStyle(fontFamily: 'SeoulHangang', fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])),
        content: const Text('정말 삭제하시겠어요? 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // R2 이미지 삭제
    final images = List<String>.from(data['images'] as List? ?? []);
    for (final url in images) {
      try {
        await CloudflareService.deleteImage(url);
      } catch (_) {}
    }

    // Cloudflare Stream 동영상 삭제
    final videoUid = data['videoUid'] as String?;
    final videoUrl = data['videoUrl'] as String?;
    if ((videoUid?.isNotEmpty ?? false) || (videoUrl?.isNotEmpty ?? false)) {
      try {
        await CloudflareService.deleteVideo(
          videoUid: videoUid,
          videoUrl: videoUrl,
        );
      } catch (_) {}
    }

    // hard delete — Firestore에서 문서 완전 제거
    await FirebaseFirestore.instance.collection('parties').doc(docId).delete();

    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('파티가 삭제되었습니다')));
    }
  }

  Future<void> _changeStatus(BuildContext context) async {
    const statuses = ['모집중', '마감', '취소'];
    final current = data['recruitStatus'] as String? ?? '모집중';

    final selected = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                '모집 상태 변경',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            ...statuses.map(
              (s) => ListTile(
                title: Text(s),
                leading: Icon(
                  s == current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: s == current ? Colors.black : Colors.black38,
                ),
                onTap: () => Navigator.pop(context, s),
              ),
            ),
          ],
        ),
      ),
    );

    if (selected == null || selected == current) return;
    await FirebaseFirestore.instance.collection('parties').doc(docId).update({
      'recruitStatus': selected,
    });
  }

  void _showApplicants(BuildContext context) {
    // applicants/approvedApplicants/rejectedApplicants 배열은 취소된 신청자를
    // 제거하므로(정원 계산용) 취소 내역까지 보여주려면 applications
    // 서브컬렉션을 실시간 구독해야 한다 — 승인/거절 상태는 기존 그대로 배열
    // 기반으로 판단하고, 취소 여부만 이 서브컬렉션의 status로 판단한다.
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
        builder: (ctx, scrollCtrl) => StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('parties')
              .doc(docId)
              .collection('applications')
              .orderBy('appliedAt')
              .snapshots(),
          builder: (context, snapshot) {
            final appDocs = snapshot.data?.docs ?? [];
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
                      Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
                      Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
                      Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
                      Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
                    ],
                  ),
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
                          separatorBuilder: (_, i) => const Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            final appDoc = appDocs[i];
                            final appData =
                                appDoc.data() as Map<String, dynamic>;
                            final uid = appDoc.id;
                            final isCancelled =
                                appData['status'] == 'cancelled';
                            final isApproved =
                                !isCancelled && approved.contains(uid);
                            final isRejected =
                                !isCancelled && rejected.contains(uid);
                            final cancelledBy =
                                appData['cancelledBy'] as String?;

                            return Opacity(
                              opacity: isCancelled ? 0.55 : 1.0,
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xFFDDD5FF),
                                  child: Text(
                                    uid.isNotEmpty ? uid[0].toUpperCase() : '?',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  uid,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: isCancelled
                                      ? const TextStyle(
                                          decoration:
                                              TextDecoration.lineThrough,
                                        )
                                      : null,
                                ),
                                subtitle: isCancelled
                                    ? Text(
                                        cancelledBy == 'host'
                                            ? '취소됨 (호스트가 파티 취소)'
                                            : '취소됨 (참가자 직접 취소)',
                                        style: const TextStyle(
                                          color: Colors.black45,
                                        ),
                                      )
                                    : isApproved
                                    ? const Text(
                                        '승인됨',
                                        style: TextStyle(color: Colors.green),
                                      )
                                    : isRejected
                                    ? const Text(
                                        '거절됨',
                                        style: TextStyle(color: Colors.red),
                                      )
                                    : const Text(
                                        '대기 중',
                                        style: TextStyle(color: Colors.orange),
                                      ),
                                trailing: isCancelled
                                    ? null
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (!isApproved)
                                            IconButton(
                                              icon: const Icon(
                                                Icons.check_circle_outline,
                                                color: Colors.green,
                                              ),
                                              tooltip: '승인',
                                              onPressed: () async {
                                                await FirebaseFirestore.instance
                                                    .collection('parties')
                                                    .doc(docId)
                                                    .update({
                                                      'approvedApplicants':
                                                          FieldValue.arrayUnion(
                                                            [uid],
                                                          ),
                                                      'rejectedApplicants':
                                                          FieldValue.arrayRemove(
                                                            [uid],
                                                          ),
                                                    });
                                              },
                                            ),
                                          if (!isRejected)
                                            IconButton(
                                              icon: const Icon(
                                                Icons.cancel_outlined,
                                                color: Colors.red,
                                              ),
                                              tooltip: '거절',
                                              onPressed: () async {
                                                await FirebaseFirestore.instance
                                                    .collection('parties')
                                                    .doc(docId)
                                                    .update({
                                                      'rejectedApplicants':
                                                          FieldValue.arrayUnion(
                                                            [uid],
                                                          ),
                                                      'approvedApplicants':
                                                          FieldValue.arrayRemove(
                                                            [uid],
                                                          ),
                                                    });
                                              },
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

  static int _daysUntilDeletion(Map<String, dynamic> d) {
    final ts = d['partyDateTime'];
    if (ts is! Timestamp) return 30;
    final remaining = ts
        .toDate()
        .add(const Duration(days: 30))
        .difference(DateTime.now())
        .inDays;
    return remaining < 0 ? 0 : remaining;
  }

  @override
  Widget build(BuildContext context) {
    final applicants = List<String>.from(data['applicants'] ?? []);
    final daysLeft = isPast ? _daysUntilDeletion(data) : 0;

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
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PartyRegisterScreen(
                          prefillData: data,
                          existingDocId: docId,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 자동 삭제 카운트다운 배지
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: daysLeft <= 3
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
                          color: daysLeft <= 3
                              ? Colors.redAccent
                              : const Color(0xFFE65100),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          daysLeft == 0 ? '오늘 삭제 예정' : '자동 삭제까지 $daysLeft일',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: daysLeft <= 3
                                ? Colors.redAccent
                                : const Color(0xFFE65100),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // 진행 중인 파티: 기존 버튼
                  _actionBtn(
                    icon: Icons.edit_outlined,
                    label: '수정',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            PartyEditScreen(docId: docId, data: data),
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
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                  ),
                  tooltip: '삭제',
                  onPressed: () => _deleteParty(context),
                ),
              ],
            ),
          ),
        ],
      ),
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

  // "진행중" 탭에서 숨기기 — isActive:false + hiddenAt 기록(30일 보관 시작).
  Future<void> _hide(BuildContext context) async {
    try {
      await FirebaseFirestore.instance.collection('places').doc(docId).update({
        'isActive': false,
        'hiddenAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('장소를 숨겼습니다. 30일 안에 재등록하지 않으면 자동 삭제돼요.'),
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

  // 숨김 처리일(hiddenAt) 기준으로 자동 삭제까지 남은 날 수 (0 = 오늘 삭제 예정)
  static int _daysUntilDeletion(Map<String, dynamic> d) {
    final ts = d['hiddenAt'];
    if (ts is! Timestamp) return 30;
    final remaining = ts
        .toDate()
        .add(const Duration(days: 30))
        .difference(DateTime.now())
        .inDays;
    return remaining < 0 ? 0 : remaining;
  }

  Future<void> _deletePlace(BuildContext context) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final hostId = data['hostId'] as String? ?? '';
    if (currentUid.isEmpty || hostId != currentUid) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('작성자만 삭제할 수 있습니다.')));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('장소 삭제', style: TextStyle(fontFamily: 'SeoulHangang', fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])),
        content: const Text('정말 삭제하시겠어요? 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // 장소 사진/동영상 정리
    final images = (data['imageUrls'] as List?)?.cast<String>() ?? [];
    for (final url in images) {
      try {
        await CloudflareService.deleteImage(url);
      } catch (_) {}
    }
    final videoUid = data['videoUid'] as String?;
    final videoUrl = data['videoUrl'] as String?;
    if ((videoUid?.isNotEmpty ?? false) || (videoUrl?.isNotEmpty ?? false)) {
      try {
        await CloudflareService.deleteVideo(
          videoUid: videoUid,
          videoUrl: videoUrl,
        );
      } catch (_) {}
    }

    // 룸 문서 + 룸 사진 정리
    final roomsSnap = await FirebaseFirestore.instance
        .collection('placeRooms')
        .where('placeId', isEqualTo: docId)
        .get();
    for (final roomDoc in roomsSnap.docs) {
      final roomImages =
          (roomDoc.data()['roomImages'] as List?)?.cast<String>() ?? [];
      for (final url in roomImages) {
        try {
          await CloudflareService.deleteImage(url);
        } catch (_) {}
      }
      await roomDoc.reference.delete();
    }

    // hard delete — Firestore에서 장소 문서 완전 제거
    await FirebaseFirestore.instance.collection('places').doc(docId).delete();

    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('장소가 삭제되었습니다')));
    }
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
    final daysLeft = isHidden ? _daysUntilDeletion(data) : 0;

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
                          MaterialPageRoute(
                            builder: (_) =>
                                PlaceEditScreen(docId: docId, data: data),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 자동 삭제 카운트다운 배지
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: daysLeft <= 3
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
                              color: daysLeft <= 3
                                  ? Colors.redAccent
                                  : const Color(0xFFE65100),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              daysLeft == 0 ? '오늘 삭제 예정' : '자동 삭제까지 $daysLeft일',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: daysLeft <= 3
                                    ? Colors.redAccent
                                    : const Color(0xFFE65100),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      // 진행중: 수정 + 숨기기 버튼
                      _actionBtn(
                        icon: Icons.edit_outlined,
                        label: '수정',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                PlaceEditScreen(docId: docId, data: data),
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
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                      ),
                      tooltip: '삭제',
                      onPressed: () => _deletePlace(context),
                    ),
                  ],
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
            stream: FirebaseFirestore.instance
                .collection('partyShops')
                .where('hostId', isEqualTo: userId)
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFF1A73E8)),
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
    final mainImgUrl = data['mainImageUrl'] as String? ?? '';
    final isActive = data['isActive'] != false;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PartyShopManageScreen(shopId: shopId, shopData: data),
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

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EventEditScreen(eventId: eventId, data: data),
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
// 스키마라 title/role/regions로 표시한다. 상세/수정 화면이 따로 없어
// 모집 상태 토글(isActive)과 삭제만 제공한다.
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
            stream: FirebaseFirestore.instance
                .collection('crews')
                .where('hostId', isEqualTo: userId)
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFFFF9A56)),
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

  Future<void> _delete(BuildContext context) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final hostId = data['hostId'] as String? ?? '';
    if (currentUid.isEmpty || hostId != currentUid) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('작성자만 삭제할 수 있습니다.')));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('글 삭제', style: TextStyle(fontFamily: 'SeoulHangang', fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])),
        content: const Text('정말 삭제하시겠어요? 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await FirebaseFirestore.instance.collection('crews').doc(docId).delete();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('삭제되었습니다')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final crewType = data['crewType'] as String? ?? '';
    final title = data['title'] as String? ?? '';
    final role = data['role'] as String? ?? '';
    final regionsRaw = data['regions'];
    final region = (regionsRaw is List && regionsRaw.isNotEmpty)
        ? regionsRaw.cast<String>().join(' · ')
        : (data['region'] as String? ?? '');
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
              const Spacer(),
              GestureDetector(
                onTap: () => _delete(context),
                child: const Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: Colors.black38,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

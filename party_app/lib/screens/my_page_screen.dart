import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:party_app/utils/local_media.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/auth_rebuilder.dart';
import 'package:party_app/services/notification_service.dart';
import 'package:party_app/widgets/nickname_edit_dialog.dart';
import 'package:party_app/screens/notifications_screen.dart';
import 'package:party_app/screens/my_guest_hub_screen.dart';
import 'package:party_app/screens/my_host_hub_screen.dart';
import 'package:party_app/screens/host_inbox_screen.dart';
import 'package:party_app/screens/host_sales_stats_screen.dart';
import 'package:party_app/services/host_inbox_service.dart';
import 'package:party_app/services/cloudflare_service.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/screens/refund_account_screen.dart';
import 'package:party_app/screens/settlement_info_screen.dart';
import 'package:party_app/screens/business_verification_screen.dart';
import 'package:party_app/models/business_verification.dart';
import 'package:party_app/services/business_verification_service.dart';
import 'package:party_app/models/payout_account.dart';
import 'package:party_app/screens/host_refund_requests_screen.dart';
import 'package:party_app/services/host_refund_service.dart';
import 'package:party_app/screens/payout_account_screen.dart';
import 'package:party_app/services/payout_account_service.dart';
import 'package:party_app/services/refund_account_service.dart';
import 'package:party_app/services/party_shop_ownership_service.dart';
import 'package:party_app/services/push_notification_service.dart';
import 'package:party_app/services/push_permission_gate.dart';
import 'package:party_app/screens/feedback_compose_screen.dart';
import 'package:party_app/screens/my_feedback_list_screen.dart';
import 'package:party_app/screens/blocked_users_screen.dart';
import 'package:party_app/screens/my_favorites_screen.dart';
import 'package:party_app/screens/drafts_list_screen.dart';
import 'package:party_app/screens/account_withdrawal_screen.dart';
import 'package:party_app/widgets/web_frame.dart';

/// 프로필 사진 크롭 결과의 형식 — **세 값은 한 벌이다.**
///
/// [ImageCropper.cropImage]에 넘기는 compressFormat을 바꾸면 파일명·MIME도 함께
/// 바꿔야 한다. 웹에서 크롭 결과는 이름도 확장자도 없는 blob 오브젝트 URL
/// (`web.URL.createObjectURL`)로 돌아오기 때문에, 업로더가 형식을 알 수 있는
/// 유일한 근거가 이 두 값이다. 앱에서는 결과가 확장자 붙은 임시 파일 경로라
/// 이 값들이 없어도 됐다(그래서 웹에서만 문제가 됐다).
const kProfileCropFormat = ImageCompressFormat.jpg;
const kProfileCropFileName = 'profile_cropped.jpg';
const kProfileCropMimeType = 'image/jpeg';

// ─────────────────────────────────────────────────────────────────────────────
// 마이페이지 메인 — **허브 역할만** 한다.
//
// 예전 첫 화면은 등록물 카드 5개(운영/내 장소/내 파티샵/내 파트너/내 플레이스)와
// 신청·예약·업주 관리 메뉴 7줄을 한꺼번에 늘어놓았다. 기능이 하나 늘 때마다
// 줄이 하나 늘어 첫 화면만 길어졌고, "내가 신청한 것"과 "내가 운영하는 것"이
// 같은 층에 섞여 있어 시선이 분산됐다.
//
// 지금은 역할 두 개로만 나눈다.
//   🎀 파티츄 게스트 → [MyGuestHubScreen]  내 신청 · 예약 · 참여
//   👑 파티츄 호스트 → [MyHostHubScreen]   내 등록 · 운영 · 예약관리
// 실제 목록과 관리 기능은 전부 그 두 화면 **안쪽**에 있고, 여기에는 종류별
// 진입점을 다시 늘어놓지 않는다(그게 이 화면이 복잡해졌던 원인이다).
//
// 파티샵만 예외로 보조 메뉴에 남는다 — 구매/판매 축이라 위 4개 카테고리
// 어디에도 반쪽만 들어가기 때문이다([MyShopHubScreen]의 주석 참고).
// ─────────────────────────────────────────────────────────────────────────────

class MyPageScreen extends StatefulWidget {
  const MyPageScreen({super.key});

  @override
  State<MyPageScreen> createState() => _MyPageScreenState();
}

/// 마이페이지에 **'정산 계좌 관리'를 보일지.**
///
/// 계좌는 셋이고 방향이 다 다르다(payoutAccounts.js 상단 참고):
///   · 입금받을 계좌(payoutAccount)   참가자 → 호스트 — 지금 실제로 돈이 오간다
///   · 정산 계좌(settlementInfo)      파티츄 → 호스트 — **아직 정산이 없다**
///   · 환불 계좌(refundAccount)       호스트 → 참가자
///
/// 가운데 하나만 감춘다. 플랫폼 정산이 시작되면 이 값을 true로 바꾸는 것으로
/// 끝난다 — 화면(SettlementInfoScreen)도, 저장된 users/{uid}.settlementInfo도,
/// 서버 정산 로직도 **그대로 살아 있다.**
const bool _showSettlementAccountMenu = false;

class _MyPageScreenState extends State<MyPageScreen> {
  /// 알림함에 다녀오면 미처리 배지를 다시 세기 위한 손잡이.
  ///
  /// 호스트 알림을 누르면 알림함이 통합 관리 화면을 **알림함 위에** 띄운다 —
  /// 거기서 승인하고 마이페이지로 돌아와도 이 위젯은 다시 만들어지지 않아
  /// 배지가 처리 전 숫자 그대로 남는다(관리 메뉴로 직접 들어간 경우는
  /// [_HostEntrySectionState._open]이 이미 다시 센다).
  final GlobalKey<_HostEntrySectionState> _hostSectionKey = GlobalKey();

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
          style: TextStyle(
            fontFamily: 'SeoulHangang',
            fontWeight: FontWeight.w500,
            shadows: [
              Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
              Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
            ],
          ),
        ),
        actions: [
          _NotificationBellButton(
            onReturn: () => _hostSectionKey.currentState?.refresh(),
          ),
        ],
      ),
      // 로그인 화면에서 로그인을 마치고 돌아왔을 때 뒤로 갔다 다시 들어오지
      // 않아도 프로필이 즉시 로그인 상태를 반영하도록 AuthRebuilder로 감싼다.
      body: AuthRebuilder(
        builder: (context) => ListView(
          children: [
            _buildProfileHeader(),
            const SizedBox(height: 14),
            _buildRoleCards(context),
            const SizedBox(height: 12),
            _buildFavoritesMenuItem(context),
            // 채팅 진입점은 하단 '채팅' 탭 하나로 통일했다 — 같은 기능으로 가는
            // 길이 두 개면 어느 쪽이 최신인지 알기 어렵고, 하단 탭이 이미
            // 항상 보이는 자리에 있다.
            const SizedBox(height: 16),
            _buildManageSection(context),
            const SizedBox(height: 10),
            _buildLogoutSection(context),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── 핵심 진입점 두 개 ────────────────────────────────────────────────
  // 같은 규격의 카드 2장. 게스트 카드에는 여전히 숫자를 붙이지 않는다 — 숫자를
  // 다는 순간 "무엇의 개수인지"를 설명해야 하고, 그러면 예전처럼 첫 화면이
  // 종류별 요약판으로 돌아간다.
  //
  // 호스트 카드만 예외다. 여기 붙는 숫자는 "구경거리 개수"가 아니라 **남이
  // 기다리고 있는 건수**다 — 승인 대기 중인 신청과 입금 확인이 필요한 건.
  // 호스트가 모르고 지나가면 신청자가 며칠씩 답을 못 받으므로, 이것만은 첫
  // 화면에서 보여야 한다(그 판정은 HostInboxService 한 곳에 있다).
  Widget _buildRoleCards(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _RoleEntryCard(
            emoji: '🎀',
            title: '파티츄 게스트',
            subtitle: '내 신청 · 예약 · 참여',
            description: '파티츄 · 플레이스 · 공간대여 · 파티크루에서\n내가 신청하고 예약한 내역',
            accent: const Color(0xFFFF6FA0),
            onTap: () => Navigator.push(
              context,
              webFramedRoute((_) => const MyGuestHubScreen()),
            ),
          ),
          // 호스트 진입(카드 + 관리 · 통계 두 줄)은 **사업자 인증을 마친
          // 계정에만** 보인다([_BusinessVerifiedOnly]).
          _BusinessVerifiedOnly(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _HostEntrySection(key: _hostSectionKey),
            ),
          ),
        ],
      ),
    );
  }

  // ── 관심(찜) 목록 ────────────────────────────────────────────────────
  //
  // 문구가 '찜! / 관심 목록' 두 겹인 이유 — 사용자가 실제로 쓰는 말('찜')을
  // 앞에 세우되, 눌러서 들어가는 화면 이름('관심 목록')도 그대로 남겨 어디로
  // 가는지 읽히게 한다. 강조는 '찜!'에만 걸고 나머지는 기존 글자색 그대로다.
  //
  // 핑크는 발바닥 아이콘에 넘기는 [color]를 그대로 쓴다 — 같은 값을 두 곳에
  // 따로 적어 두면 한쪽만 바뀌어 아이콘과 글자 색이 어긋난다.
  Widget _buildFavoritesMenuItem(BuildContext context) {
    const pink = Color(0xFFFF6FA0);
    return _menuItem(
      context,
      icon: Icons.pets,
      color: pink,
      label: const TextSpan(
        children: [
          TextSpan(
            text: '찜!',
            style: TextStyle(color: pink),
          ),
          // 색을 주지 않은 조각은 아래 Text.rich의 기본 스타일(기존 검정)을
          // 그대로 물려받는다.
          TextSpan(text: ' / 관심 목록'),
        ],
      ),
      onTap: () => Navigator.push(
        context,
        webFramedRoute((_) => const MyFavoritesScreen()),
      ),
    );
  }

  // (채팅 메뉴는 삭제됐다 — 진입점은 하단 '채팅' 탭 하나로 통일했다.)

  /// 한 줄 메뉴 — 관심 목록이 쓴다.
  ///
  /// [label]은 조각 색을 달리할 수 있게 [InlineSpan]으로 받는다(글자 크기·
  /// 굵기·행 배치는 아래 기본 스타일 한 곳에서만 정한다).
  Widget _menuItem(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required InlineSpan label,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 10),
                Text.rich(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
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

  // ── 보조 메뉴 — 결제·정산과 설정성 항목. 우선순위가 낮아 ListTile 크기 ──
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
              '결제 · 설정',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.black45,
              ),
            ),
          ),
          // 파티샵은 구매(내가 산 것)와 판매(내 샵 주문)가 한 몸이라 게스트/
          // 호스트 어느 쪽 탭에도 반쪽만 들어간다 — 그래서 별도 진입이다.
          //
          // 진입 줄 자체는 **누구에게나** 보인다 — 구매는 누구나 하고, 구매
          // 이력이 0건이어도 주문을 확인할 자리는 있어야 하기 때문이다.
          // 안쪽에서 '내 파티샵'·'판매'까지 보여줄지는 실제 파티샵 보유
          // 여부로 갈리며([MyShopHubScreen] 참고), 여기서는 그 판정을 부제목
          // 문구에만 반영한다 — 파티샵이 없는 사람에게 "내 파티샵 운영"이라고
          // 적어 두면 들어가서 없는 메뉴를 찾게 된다.
          StreamBuilder<bool>(
            stream: PartyShopOwnershipService.watch(),
            initialData: PartyShopOwnershipService.cached(),
            builder: (context, snap) {
              final isSeller = snap.data == true;
              return ListTile(
                leading: const Icon(
                  Icons.storefront_outlined,
                  color: Colors.black87,
                ),
                title: const Text('파티샵'),
                subtitle: Text(
                  isSeller ? '내 파티샵 운영 · 구매/판매 주문' : '내가 구매한 파티샵 주문',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: Colors.black45,
                ),
                onTap: () => Navigator.push(
                  context,
                  webFramedRoute((_) => const MyShopHubScreen()),
                ),
              );
            },
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          // 사업자 인증 — 예약·모집 오픈 권한의 근거다. 상태(인증 완료/심사
          // 필요/인증 실패/휴·폐업 확인 필요)를 부제목에 그대로 띄워서,
          // 들어가 보지 않고도 지금 무엇이 막혀 있는지 알 수 있게 한다.
          StreamBuilder<BusinessVerification>(
            stream: BusinessVerificationService.watch(),
            builder: (context, snap) {
              final v = snap.data ?? BusinessVerification.none;
              return ListTile(
                leading: Icon(
                  v.isVerified ? Icons.verified_outlined : Icons.badge_outlined,
                  color: v.isVerified
                      ? const Color(0xFF047857)
                      : Colors.black87,
                ),
                title: const Text('사업자 인증 정보'),
                subtitle: Text(
                  v.isVerified
                      ? '인증 완료 · ${v.formattedBusinessNumber}'
                      // 진위는 확인됐는데 권한만 없는 상태 — `status.label`을
                      // 그대로 쓰면 "인증 완료 · 인증하면 …"이라는 한 줄짜리
                      // 모순이 된다. 남은 단계는 headline이 말한다.
                      : v.verifiedWithoutAuthorization
                      ? '${v.headline} · 눌러서 남은 단계를 확인해주세요'
                      : '${v.status.label} · 인증하면 파티를 바로 오픈할 수 있어요',
                  style: TextStyle(
                    fontSize: 12,
                    color: v.isVerified ? const Color(0xFF047857) : null,
                  ),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: Colors.black45,
                ),
                onTap: () => Navigator.push(
                  context,
                  webFramedRoute((_) => const BusinessVerificationScreen()),
                ),
              );
            },
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          // ── 계좌 세 줄 ────────────────────────────────────────────────
          // 이름이 비슷해 헷갈리기 쉬워서 **돈의 방향**으로 갈라 둔다.
          //   · 입금받을 계좌 : 참가자 → 나 (지금 실제로 돈이 오가는 계좌)
          //   · 정산 계좌     : 파티츄 → 나 (플랫폼 정산이 생길 때 쓸 계좌)
          //   · 환불 계좌     : 호스트 → 나 (내가 참가자로서 돌려받을 계좌)
          //
          // 이 중 '입금받을 계좌'는 참가비를 **받는 쪽**의 계좌라 호스트에게만
          // 쓸모가 있다 — 그래서 위 호스트 진입과 같은 조건(사업자 인증 완료)
          // 으로 가린다. 나머지 두 줄은 참가자도 쓰므로 그대로 둔다.
          _BusinessVerifiedOnly(
            child: StreamBuilder<PayoutAccount>(
              stream: PayoutAccountService.watch(),
              builder: (context, snap) {
                final account = snap.data ?? PayoutAccount.none;
                final verified = account.isVerified;
                return ListTile(
                  leading: Icon(
                    verified
                        ? Icons.account_balance
                        : Icons.account_balance_outlined,
                    color: verified ? const Color(0xFF047857) : Colors.black87,
                  ),
                  title: const Text('입금받을 계좌'),
                  subtitle: Text(
                    verified
                        ? '인증 완료 · ${account.maskedSummary}'
                        : '${account.status.label} · 인증해야 무통장입금을 받을 수 있어요',
                    style: TextStyle(
                      fontSize: 12,
                      color: verified ? const Color(0xFF047857) : null,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.black45,
                  ),
                  onTap: () => Navigator.push(
                    context,
                    webFramedRoute((_) => const PayoutAccountScreen()),
                  ),
                );
              },
            ),
          ),
          // 환불 요청 — **처리할 게 있을 때만** 뜬다. 참가비를 호스트가 직접
          // 받으므로 돌려주는 것도 호스트다. 상시 노출하면 참가자에게도 늘
          // 보이는 빈 메뉴가 되어 버린다.
          StreamBuilder<int>(
            stream: HostRefundService.watchPendingCount(),
            builder: (context, snap) {
              final pending = snap.data ?? 0;
              if (pending <= 0) return const SizedBox.shrink();
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(
                      Icons.assignment_return_outlined,
                      color: Color(0xFFE2568A),
                    ),
                    title: const Text('환불 요청'),
                    subtitle: Text(
                      '보내야 할 환불 $pending건 · 참가자가 기다리고 있어요',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFE2568A),
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Colors.black45,
                    ),
                    onTap: () => Navigator.push(
                      context,
                      webFramedRoute((_) => const HostRefundRequestsScreen()),
                    ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                ],
              );
            },
          ),
          // 정산 계좌 관리 — **지금은 감춰 둔다**([_showSettlementAccountMenu]).
          //
          // 플랫폼 정산(파티츄 → 호스트)이 아직 실제로 일어나지 않는데 메뉴만
          // 열려 있어, 호스트가 '입금받을 계좌'(참가자 → 나)와 헷갈려 여기에
          // 계좌를 적어 두고 무통장입금을 못 받는 일이 생긴다.
          //
          // 화면·데이터·서버 로직은 **하나도 지우지 않았다** —
          // SettlementInfoScreen도 users/{uid}.settlementInfo도 그대로다.
          // 정산이 열리면 아래 상수만 true로 되돌리면 원래대로 보인다.
          if (_showSettlementAccountMenu) ...[
            ListTile(
              leading: const Icon(
                Icons.account_balance_wallet_outlined,
                color: Colors.black87,
              ),
              title: const Text('정산 계좌 관리'),
              subtitle: const Text(
                '플랫폼 정산 대금을 받을 계좌 (참가비 입금 계좌와 다름)',
                style: TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.black45),
              onTap: () => Navigator.push(
                context,
                webFramedRoute((_) => const SettlementInfoScreen()),
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
          ],
          // 환불 계좌도 인증을 거치는 항목이라 **위 두 줄과 같은 방식으로**
          // 상태를 보여준다(사업자 인증 · 입금받을 계좌). 인증을 마쳤는데 이
          // 줄만 안내 문구 그대로면, 등록이 된 건지 아닌지 들어가 봐야만 안다.
          //
          // 판정은 서버가 적어 둔 값을 읽을 뿐이다
          // ([RefundAccountService.stateOfUserDoc]) — 화면이 '인증 완료'를
          // 스스로 만들지 않는다. 계좌번호는 뒤 네 자리만 남긴다(수취계좌와
          // 같은 [BankCodes.maskedSummary]).
          StreamBuilder<RefundAccountState>(
            stream: RefundAccountService.watch(),
            builder: (context, snap) {
              final state = snap.data ?? RefundAccountState.empty;
              final account = state.account;
              final verified = state.isVerified && account != null;
              return ListTile(
                leading: Icon(
                  verified
                      ? Icons.account_balance
                      : Icons.account_balance_wallet_outlined,
                  color: verified ? const Color(0xFF047857) : Colors.black87,
                ),
                title: const Text('환불 계좌 관리'),
                subtitle: Text(
                  // 인증 전(미등록·인증 필요)에는 예전 안내 문구 그대로 —
                  // 무엇에 쓰는 계좌인지부터 알려주는 게 먼저다.
                  verified
                      ? '인증 완료 · ${account.maskedSummary}'
                      : '무통장입금 취소 시 환불받을 계좌',
                  style: TextStyle(
                    fontSize: 12,
                    color: verified ? const Color(0xFF047857) : null,
                  ),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: Colors.black45,
                ),
                onTap: () => Navigator.push(
                  context,
                  webFramedRoute((_) => const RefundAccountScreen()),
                ),
              );
            },
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.drafts_outlined, color: Colors.black87),
            title: const Text('임시저장'),
            subtitle: const Text(
              '작성 중이던 등록 내용 이어서 작성',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.black45),
            onTap: () => Navigator.push(
              context,
              webFramedRoute((_) => const DraftsListScreen()),
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          const _PushNotificationTile(),
          const Divider(height: 1, indent: 16, endIndent: 16),
          // 차단을 **거는** 자리는 여럿(파티·플레이스 상세, 채팅방)이지만
          // **푸는** 자리는 여기 하나다 — 차단하면 그 사람의 글이 목록에서
          // 사라져서, 원래 화면으로 돌아가 해제할 방법이 없기 때문이다.
          ListTile(
            leading: const Icon(Icons.block, color: Colors.black87),
            title: const Text('차단한 사용자'),
            subtitle: const Text(
              '차단 목록 확인 · 차단 해제',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.black45),
            onTap: () => Navigator.push(
              context,
              webFramedRoute((_) => const BlockedUsersScreen()),
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(
              Icons.chat_bubble_outline,
              color: Colors.black87,
            ),
            title: const Text('고객센터 문의'),
            // 결제·환불은 고객센터가 처리하지 않는다(호스트가 직접 처리) —
            // 여기서 광고하면 그걸 하러 들어와 안내문만 보고 나가게 된다.
            subtitle: const Text(
              '이용 문의 · 버그 신고 · 사업자 문의 · 개선 제안',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.black45),
            onTap: () => Navigator.push(
              context,
              webFramedRoute((_) => const FeedbackComposeScreen()),
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
              webFramedRoute((_) => const MyFeedbackListScreen()),
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          // 회원 탈퇴 — 되돌릴 수 없는 항목이라 섹션에서 시각적으로 가장 약한
          // 자리(맨 아래)에 두고, 아이콘·글자색도 다른 항목보다 낮춘다. 다만
          // 찾을 수 없게 숨기지는 않는다 — 앱 안에서 스스로 탈퇴할 수 있어야
          // 한다(Google Play 계정 삭제 정책).
          ListTile(
            leading: Icon(
              Icons.person_remove_outlined,
              color: Colors.grey.shade500,
            ),
            title: Text('회원 탈퇴', style: TextStyle(color: Colors.grey.shade600)),
            subtitle: Text(
              '탈퇴 신청 후 7일간 취소할 수 있어요',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
            onTap: () {
              if (UserSession.userId.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('로그인 후 이용할 수 있어요.')),
                );
                return;
              }
              Navigator.push(context, accountWithdrawalRoute());
            },
          ),
          // 웹에서만 노출 — 모바일 앱은 스토어 소개 화면이 이 역할을 대신하므로
          // 마이페이지에 중복 노출할 필요가 없다.
          if (kIsWeb) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.black87),
              title: const Text('서비스 소개'),
              subtitle: const Text(
                '파티츄 소개 · 이용 방법 살펴보기',
                style: TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.black45),
              onTap: () =>
                  launchUrl(Uri.parse('/'), webOnlyWindowName: '_blank'),
            ),
          ],
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
        title: const Text(
          '로그아웃',
          style: TextStyle(
            fontFamily: 'SeoulHangang',
            fontWeight: FontWeight.w500,
            shadows: [
              Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
              Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
            ],
          ),
        ),
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
        title: const Text(
          '[DEV] 전체 파티 삭제',
          style: TextStyle(
            fontFamily: 'SeoulHangang',
            fontWeight: FontWeight.w500,
            shadows: [
              Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
              Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
            ],
          ),
        ),
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
                // 닉네임 아래에는 **사람이 읽을 수 있는 것만** 둔다.
                //
                // 예전에는 이 자리에 Firebase UID가 그대로 찍혔다. 사용자에게는
                // 뜻 없는 문자열인데 프로필 맨 위에 있어서, 문의 글이나
                // 스크린샷에 아무 이유 없이 함께 옮겨 다녔다.
                //
                // ⚠️ 값은 그대로다 — [UserSession.userId]는 Firestore 조회·
                //    본인인증·신청/예약·문의가 전부 쓰는 내부 식별자다.
                //    여기서 **그리지만 않는다**.
                if (loggedIn) ...[
                  const SizedBox(height: 6),
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
                ] else ...[
                  // 로그인 전에는 배지 대신 안내 한 줄 — 이 자리를 비워 두면
                  // 닉네임 자리에 뜬 '로그인 필요'만 남아 무엇을 하라는
                  // 말인지 알기 어렵다.
                  const SizedBox(height: 2),
                  const Text(
                    '로그인 후 프로필을 설정할 수 있어요',
                    style: TextStyle(fontSize: 12, color: Colors.black45),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
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

    final CroppedFile? cropped;
    try {
      cropped = await _cropProfileImage(picked.path);
    } catch (e) {
      // 여기서 잡지 않으면 예외가 조용히 사라지고 화면만 되돌아온다 —
      // 웹에서 실제로 그 증상만 보였고 원인을 찾기 어려웠다.
      debugPrint('[MyPage] 프로필 사진 크롭 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('사진을 편집하지 못했어요. 다시 시도해주세요.')),
        );
      }
      return;
    }
    if (cropped == null || !mounted) return; // 크롭 화면에서 취소함

    // 크롭 결과를 XFile로 감싼다.
    //
    // **이름과 MIME을 명시하는 것이 핵심이다.** 앱에서는 `cropped.path`가 확장자
    // 붙은 임시 파일 경로라 그냥 감싸도 됐지만, 웹에서는 `blob:.../uuid` 라
    // 이름도 확장자도 없다. 그대로 두면 업로더가 형식을 몰라
    // ([LocalMedia.extensionOf]가 빈 문자열) 업로드 허가를 받지 못한다.
    // 앱의 XFile은 이름을 경로에서 얻으므로 이 인자들이 동작을 바꾸지 않는다.
    final croppedFile = XFile(
      cropped.path,
      name: kProfileCropFileName,
      mimeType: kProfileCropMimeType,
    );

    final confirmed = await _confirmCroppedPreview(croppedFile);
    if (!confirmed || !mounted) return; // 미리보기에서 다시 선택을 고름

    await _uploadProfileImage(croppedFile);
  }

  // 실제 프로필에 보일 크기(원형) 기준으로 확대/축소·드래그 이동·중앙 맞춤이
  // 가능한 편집 화면을 띄운다. 원형 가이드 밖은 자동으로 어둡게 표시되고,
  // 취소/적용 버튼은 네이티브 크롭 화면(UCrop/TOCropViewController)이
  // 기본 제공한다. 원본 파일(sourcePath)은 건드리지 않고, 크롭 결과만
  // 새 임시 파일로 반환된다.
  //
  // ── uiSettings에 세 플랫폼이 함께 들어 있는 이유 ─────────────────────────
  // 플러그인은 **자기 플랫폼의 설정만 골라 쓰고 나머지는 무시한다.** 목록에
  // 셋을 다 넣어도 안드로이드/iOS 동작은 예전과 완전히 같다.
  //
  // 반대로 웹 구현(image_cropper_for_web)은 목록에 [WebUiSettings]가 없으면
  // `must provide WebUiSettings to run on Web` 을 **던진다.** 그래서 웹에서는
  // 사진을 골라도 크롭 화면이 뜨지 않고 조용히 되돌아가기만 했다.
  //
  // 비율(1:1)·형식·품질은 아래 공통 인자가 정하므로 플랫폼별로 갈리지 않는다.
  // 웹에는 원형 마스크(cropStyle)가 없지만 저장 결과가 1:1 정사각인 것은 같고,
  // 화면에는 앱과 마찬가지로 ClipOval로 둥글게 보인다.
  Future<CroppedFile?> _cropProfileImage(String sourcePath) {
    return ImageCropper().cropImage(
      sourcePath: sourcePath,
      compressFormat: kProfileCropFormat,
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
        // 웹 전용 — 앱에서는 무시된다. 문구는 네이티브 화면과 같은 말로 맞춘다.
        WebUiSettings(
          context: context,
          presentStyle: WebPresentStyle.dialog,
          translations: const WebTranslations(
            title: '프로필 사진 편집',
            rotateLeftTooltip: '왼쪽으로 회전',
            rotateRightTooltip: '오른쪽으로 회전',
            cancelButton: '취소',
            cropButton: '적용',
          ),
        ),
      ],
    );
  }

  // 크롭 결과를 실제 프로필과 동일하게 원형으로 미리 보여주고, 이 사진으로
  // 저장할지 다시 고를지 마지막으로 확인한다.
  Future<bool> _confirmCroppedPreview(XFile file) async {
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
              child: LocalMedia.image(
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
  Future<void> _uploadProfileImage(XFile file) async {
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
// 역할 진입 카드 — 게스트/호스트 두 장이 **완전히 같은 규격**이다.
//
// 예전 그리드는 카드마다 크기·강조가 달라(큰 카드 2 + 작은 카드 4) 무엇이
// 더 중요한지가 흐려졌다. 지금은 두 장이 똑같고, 톤은 기존 핑크/파스텔을
// 유지하되 그라데이션 대신 옅은 배경색 + 얇은 테두리 한 겹만 쓴다.
// ─────────────────────────────────────────────────────────────────────────────
/// 마이페이지의 **알림 설정** 한 줄.
///
/// 다른 진입점(채팅·예약 직후)은 맥락이 생겼을 때 알아서 묻지만, 그 자리에서
/// '나중에'를 눌렀거나 시스템 설정에서 꺼버린 사람에게는 **스스로 켜러 올 자리**
/// 가 있어야 한다. 그게 없으면 한 번 거절한 사용자는 알림을 다시 켤 방법이 앱
/// 안에 아예 없다(OS 팝업은 다시 뜨지 않는다).
///
/// 그래서 여기서만 [PushPermissionGate.ensure]를 `force: true`로 부른다 —
/// 유예 기간은 조르지 않기 위한 장치지, 사용자가 직접 누른 버튼까지 막으라는
/// 뜻은 아니기 때문이다.
class _PushNotificationTile extends StatefulWidget {
  const _PushNotificationTile();

  @override
  State<_PushNotificationTile> createState() => _PushNotificationTileState();
}

class _PushNotificationTileState extends State<_PushNotificationTile>
    with WidgetsBindingObserver {
  PushPermissionState? _state;

  @override
  void initState() {
    super.initState();
    // 설정앱에서 알림을 켜고 돌아오면 앱은 resume만 받고 화면은 그대로다.
    // 다시 읽지 않으면 방금 켠 사용자에게 계속 '꺼짐'이라고 보여주게 된다.
    WidgetsBinding.instance.addObserver(this);
    _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  Future<void> _reload() async {
    final next = await PushNotificationService.currentState();
    if (mounted) setState(() => _state = next);
  }

  ({String text, Color color}) get _status => switch (_state) {
    null => (text: '확인 중…', color: Colors.black45),
    PushPermissionState.granted => (
      text: '켜짐 · 채팅 · 예약 소식을 받고 있어요',
      color: const Color(0xFF047857),
    ),
    PushPermissionState.blocked => (
      text: '꺼짐 · 기기 설정에서 켜야 알림이 와요',
      color: const Color(0xFFB45309),
    ),
    _ => (text: '꺼짐 · 눌러서 알림을 켤 수 있어요', color: Colors.black54),
  };

  @override
  Widget build(BuildContext context) {
    final on = _state?.isGranted ?? false;
    final status = _status;

    return ListTile(
      leading: Icon(
        on
            ? Icons.notifications_active_outlined
            : Icons.notifications_off_outlined,
        color: on ? const Color(0xFF047857) : Colors.black87,
      ),
      title: const Text('알림 설정'),
      subtitle: Text(
        status.text,
        style: TextStyle(fontSize: 12, color: status.color),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.black45),
      onTap: () async {
        if (UserSession.userId.isEmpty) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('로그인 후 알림을 설정할 수 있어요.')));
          return;
        }
        // 이미 켜져 있으면 물어볼 게 없다 — 끄러 온 사람도 있으니 설정앱으로
        // 보낸다(앱 안에서 OS 권한을 끌 수는 없다).
        if (on) {
          await PushNotificationService.openSettings();
        } else {
          await PushPermissionGate.ensure(
            context,
            PushPromptReason.settings,
            force: true,
          );
        }
        await _reload();
      },
    );
  }
}

/// 사업자 인증을 마친 계정에만 [child]를 그린다 — 마이페이지의 **호스트 전용
/// 항목** 게이트.
///
/// 가리는 것: 👑 파티츄 호스트 카드 · 신청자 · 예약자 관리 · 판매 통계 ·
/// 입금받을 계좌. 넷 다 "참가비를 받는 쪽"의 도구라, 참가자 계정에 보이면
/// 들어가서 텅 빈 목록이나 쓸 데 없는 계좌 등록 화면을 만나게 된다.
///
/// ── 판정 기준 ─────────────────────────────────────────────────────────
/// 기준은 **사업자 인증 완료 하나**다([BusinessVerification.isVerified]).
///   · 본인인증(NICE) 완료 여부는 보지 않는다 — 참가자도 다 하는 인증이다.
///   · 실제 등록물(파티·플레이스·공간대여·크루)이 있는지도 보지 않는다.
///     아직 아무것도 등록하지 않은 호스트가 **처음 등록하러 들어올 자리**가
///     사라지면, 인증을 마치고도 갈 곳이 없어진다.
///   · 새 필드를 만들지 않는다 — 등록 자격 판정과 **같은 값**을 읽는다
///     ([PartyCreateEligibility]·[PlaceCreateEligibility]). 여기서 status만
///     보면 "메뉴는 열렸는데 등록은 막히는" 모순이 생긴다.
///
/// ── 깜빡임 ────────────────────────────────────────────────────────────
/// 첫 스냅샷이 오기 전에는 **숨긴 채로 시작한다**(`snap.data`가 null). 인증
/// 상태를 모를 때 일단 보여줬다가 지우면, 참가자 화면에서 호스트 메뉴가
/// 한 프레임 번쩍인 뒤 사라진다 — 못 본 사람에겐 사라진 이유가 없다.
class _BusinessVerifiedOnly extends StatelessWidget {
  const _BusinessVerifiedOnly({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<BusinessVerification>(
      stream: BusinessVerificationService.watch(),
      builder: (context, snap) {
        final verified = snap.data?.isVerified ?? false;
        if (!verified) return const SizedBox.shrink();
        return child;
      },
    );
  }
}

/// 👑 호스트 카드 + 그 아래 '신청자 · 예약자 관리' 한 줄.
///
/// 둘을 한 위젯으로 묶은 이유는 **같은 숫자를 두 번 세지 않기 위해서**다.
/// 미처리 건수는 콜러블 한 번 + 예약 스트림 셋을 합쳐 나오는 값이라
/// ([HostInboxService.watch]) 카드와 메뉴가 각자 구독하면 그 일이 두 번 일어나고,
/// 갱신 시점이 어긋나면 카드에는 3, 메뉴에는 2가 떠 있는 순간이 생긴다.
class _HostEntrySection extends StatefulWidget {
  const _HostEntrySection({super.key});

  @override
  State<_HostEntrySection> createState() => _HostEntrySectionState();
}

class _HostEntrySectionState extends State<_HostEntrySection> {
  static const _accent = Color(0xFF7C5CBF);

  /// 파티 신청은 콜러블이라 스스로 갱신되지 않는다 — 관리 화면에 다녀오면
  /// 스트림을 다시 만들어 방금 처리한 건이 숫자에서 빠지게 한다.
  late Stream<HostInboxSnapshot> _stream = HostInboxService.watch(
    UserSession.userId,
  );

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, webFramedRoute((_) => screen));
    refresh();
  }

  /// 미처리 건수를 다시 센다 — 관리 화면에서 돌아왔을 때, 그리고 알림함을
  /// 거쳐 통합 관리 화면에 다녀왔을 때(마이페이지가 그때는 다시 만들어지지
  /// 않는다) 양쪽에서 부른다.
  void refresh() {
    if (!mounted) return;
    setState(() => _stream = HostInboxService.watch(UserSession.userId));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<HostInboxSnapshot>(
      stream: _stream,
      builder: (context, snap) {
        // 아직 못 셌으면 0으로 그린다 — 숫자를 못 세는 것과 "처리할 게 없는
        // 것"이 화면에서 같아 보여도, 잘못된 숫자를 띄우는 것보다는 낫다.
        final count = snap.data?.unhandledCount ?? 0;
        return Column(
          children: [
            _RoleEntryCard(
              emoji: '👑',
              title: '파티츄 호스트',
              subtitle: '내 등록 · 운영 · 예약관리',
              description: '내가 등록한 파티·플레이스·공간·크루와\n들어온 신청·예약 관리',
              accent: _accent,
              badgeCount: count,
              onTap: () => _open(const MyHostHubScreen()),
            ),
            const SizedBox(height: 8),
            _HostMenuRow(
              icon: Icons.how_to_reg_outlined,
              label: '신청자 · 예약자 관리',
              accent: _accent,
              badgeCount: count,
              onTap: () => _open(
                HostInboxScreen(
                  // 숫자를 보고 눌렀으면 그 숫자가 가리키는 목록이 먼저 보여야
                  // 한다. 처리할 게 없을 때만 전체로 연다.
                  initialFilter: count > 0
                      ? HostInboxFilter.needsAction
                      : HostInboxFilter.all,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 판매 통계는 관리 메뉴 **바로 아래**다. 위 줄이 "지금 처리할 것",
            // 이 줄이 "지금까지 들어온 것"이라 같은 호스트 흐름의 앞뒤가 된다.
            // 배지를 달지 않는 이유는 숫자가 할 일을 뜻하지 않기 때문이다.
            _HostMenuRow(
              icon: Icons.insert_chart_outlined,
              label: '판매 통계',
              accent: _accent,
              onTap: () => _open(const HostSalesStatsScreen()),
            ),
          ],
        );
      },
    );
  }
}

/// 호스트 카드 바로 아래 붙는 메뉴 한 줄 — '신청자 · 예약자 관리'와
/// '판매 통계'가 같은 규격을 쓴다.
///
/// [badgeCount]는 **남이 기다리고 있는 건수**일 때만 넘긴다. 0이면 알약을
/// 그리지 않는다 — '0'을 띄우면 "처리할 게 0건"을 매번 읽게 되어 소음이 된다.
/// 판매 통계처럼 숫자가 할 일을 뜻하지 않는 줄은 배지 없이 쓴다.
class _HostMenuRow extends StatelessWidget {
  const _HostMenuRow({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: accent, size: 21),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              if (badgeCount > 0)
                _UnhandledBadge(count: badgeCount, color: accent),
              const Spacer(),
              const Icon(Icons.chevron_right, color: Colors.black45),
            ],
          ),
        ),
      ),
    );
  }
}

/// 미처리 건수 알약. 0이면 부르는 쪽이 아예 그리지 않는다 —
/// '0'을 띄우면 "처리할 게 0건"을 매번 읽게 되어 배지가 소음이 된다.
class _UnhandledBadge extends StatelessWidget {
  const _UnhandledBadge({required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        // 세 자리를 넘어가면 줄 너비를 먹는다. 정확한 숫자가 중요한 구간이
        // 아니라 "많다"만 전해지면 된다.
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _RoleEntryCard extends StatelessWidget {
  const _RoleEntryCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.accent,
    required this.onTap,
    this.badgeCount = 0,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final String description;
  final Color accent;
  final VoidCallback onTap;

  /// 제목 옆에 붙는 미처리 건수. 0이면 그리지 않는다(게스트 카드는 언제나 0).
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withValues(alpha: 0.22)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: accent.withValues(alpha: 0.18)),
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 24)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                          ),
                        ),
                        if (badgeCount > 0) ...[
                          const SizedBox(width: 7),
                          _UnhandledBadge(count: badgeCount, color: accent),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.5,
                        color: Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: accent.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 마이페이지 우상단 알림 버튼 — 안 읽은 알림이 있으면 빨간 점이 붙는다.
///
/// 서버가 남긴 알림(최소 모집 인원 미달 자동 취소 등)을 사용자가 실제로 볼 수
/// 있는 진입점이다. 푸시(FCM)가 아직 없어서 이 경로가 유일하다.
class _NotificationBellButton extends StatelessWidget {
  const _NotificationBellButton({this.onReturn});

  /// 알림함에서 돌아왔을 때 부른다 — 호스트 알림을 눌러 통합 관리 화면까지
  /// 다녀오면 미처리 건수가 바뀌어 있을 수 있다.
  final VoidCallback? onReturn;

  @override
  Widget build(BuildContext context) {
    if (!UserSession.isLoggedIn) return const SizedBox.shrink();
    return StreamBuilder<int>(
      stream: NotificationService.watchUnreadCount(UserSession.userId),
      builder: (context, snapshot) {
        // 개수를 못 읽었을 때 0으로 떨어뜨리면 **"안 읽은 알림이 없다"는 거짓
        // 정보**가 된다(배지가 사라지므로). 숫자 대신 물음표 배지를 띄워
        // "확인이 필요하다"는 것만 알리고, 원인은 콘솔 로그로 남긴다 —
        // 눌러서 들어가면 알림함이 오류와 '다시 시도'를 제대로 보여준다.
        final failed = snapshot.hasError;
        if (failed) {
          logFirestoreStreamError(
            'NotificationUnreadCount',
            snapshot.error,
            snapshot.stackTrace,
          );
        }
        final unread = snapshot.data ?? 0;
        return IconButton(
          tooltip: failed ? '알림 개수를 불러오지 못했어요' : '알림',
          onPressed: () async {
            await Navigator.push(
              context,
              webFramedRoute((_) => const NotificationsScreen()),
            );
            onReturn?.call();
          },
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications_none_rounded),
              if (failed)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    constraints: const BoxConstraints(minWidth: 15),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: const Text(
                      '?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                  ),
                )
              else if (unread > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    constraints: const BoxConstraints(minWidth: 15),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6FA0),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

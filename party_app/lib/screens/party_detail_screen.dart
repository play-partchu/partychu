import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:video_player/video_player.dart';
import 'package:party_app/utils/age_range_utils.dart';
import 'package:party_app/utils/auto_description_classifier.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/utils/party_detail_view_mode.dart';
import 'package:party_app/utils/party_eligibility.dart';
import 'package:party_app/models/region_data.dart';
import 'package:party_app/models/party_constants.dart';
import 'package:party_app/utils/early_bird.dart';
import 'package:party_app/utils/feed_video_manager.dart';
import 'package:party_app/utils/party_utils.dart';
import 'package:party_app/utils/favorites_service.dart';
import 'package:party_app/utils/format_utils.dart';
import 'package:party_app/utils/refund_policy.dart';
import 'package:party_app/widgets/favorite_star_button.dart';
import 'package:party_app/widgets/media_gallery.dart';
import 'package:party_app/widgets/nickname_edit_dialog.dart';
import 'package:party_app/widgets/party_auto_keyword_badges.dart';
import 'package:party_app/widgets/party_card_widget.dart';
import 'package:party_app/widgets/party_detail_block_preview.dart';
import 'package:party_app/widgets/party_detail_block_text_view.dart';
import 'package:party_app/widgets/party_detail_theme.dart';
import 'package:party_app/widgets/partychu_icon_button.dart';
import 'package:party_app/widgets/partychu_ui.dart';
import 'package:party_app/widgets/refund_policy_editor.dart';
import 'package:party_app/login.dart';
import 'package:party_app/models/party_detail_block.dart';
import 'package:party_app/models/party_auto_description_style.dart';
import 'package:party_app/models/party_detail_decoration_intensity.dart';
import 'package:party_app/models/party_detail_theme_key.dart';
import 'package:party_app/screens/full_screen_image_viewer.dart';
import 'package:party_app/screens/package_booking_screen.dart';
import 'package:party_app/screens/party_applicants_screen.dart';
import 'package:party_app/screens/party_reregister_screen.dart';
import 'package:party_app/screens/place_detail_screen.dart';
import 'package:party_app/screens/event_detail_screen.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/services/analytics_service.dart';
import 'package:party_app/services/push_permission_gate.dart';
import 'package:party_app/widgets/share_bottom_sheet.dart';
import 'package:party_app/widgets/web_frame.dart';

class PartyDetailScreen extends StatefulWidget {
  final String docId;

  const PartyDetailScreen({super.key, required this.docId});

  @override
  State<PartyDetailScreen> createState() => _PartyDetailScreenState();
}

class _PartyDetailScreenState extends State<PartyDetailScreen> {
  @override
  void initState() {
    super.initState();
    // 화면이 다시 빌드될 때(StreamBuilder 갱신 등)마다 중복 기록되지 않도록
    // initState에서 한 번만 로깅한다 — build()는 파티 문서가 갱신될 때마다
    // 다시 호출되므로 거기서 로깅하면 조회수가 과도하게 잡힌다.
    AnalyticsService.logEvent(
      AnalyticsEventType.partyView,
      partyId: widget.docId,
    );
    // 로그인 화면에서 로그인을 마치고 이 화면으로 돌아왔을 때(또는 이
    // 화면을 띄운 채로 다른 경로에서 로그인/로그아웃이 일어났을 때) 뒤로
    // 갔다 다시 들어오지 않아도 신청 버튼 등이 즉시 로그인 상태를
    // 반영하도록 UserSession 변경을 구독한다.
    UserSession.revision.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    UserSession.revision.removeListener(_onAuthChanged);
    super.dispose();
  }

  /// 라운드 선택 다이얼로그를 띄운다. 사용자가 취소하거나 선택 없이 닫으면
  /// null을 돌려줘 호출부가 신청 자체를 진행하지 않게 한다.
  Future<List<int>?> _pickRounds(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final rounds = ((data['rounds'] as List?) ?? [])
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    if (rounds.isEmpty) return null;
    return showDialog<List<int>>(
      context: context,
      builder: (_) => _RoundSelectionDialog(rounds: rounds),
    );
  }

  Future<void> _apply(
    BuildContext context, {
    List<int>? selectedRounds,
  }) async {
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-northeast3',
      ).httpsCallable('applyToParty');
      final result = await callable.call({
        'partyId': widget.docId,
        if (selectedRounds != null) 'selectedRounds': selectedRounds,
      });

      if (context.mounted) {
        // 서버가 신청 확정 시점에 계산한 실제 적용 금액(얼리버드 반영)을 그대로 안내.
        final resultData = Map<String, dynamic>.from(result.data as Map);
        final appliedFee = (resultData['appliedFee'] as num?)?.toInt() ?? 0;
        final msg = appliedFee > 0
            ? '신청이 완료되었습니다! (참가비 ${_formatFee(appliedFee)})'
            : '신청이 완료되었습니다!';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));

        // 신청을 막 마친 지금이 알림을 권하기 좋은 자리다 — 승인·입금 확인·
        // 시작 1시간 전 안내가 전부 이 신청에 딸려 오기 때문. 스낵바가 먼저
        // 보이도록 한 프레임 뒤로 미룬다.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          PushPermissionGate.ensure(context, PushPromptReason.booking);
        });
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_applyErrorMessage(e))));
      }
    }
  }

  // 참가자 자체 취소 — 실제 결제 금액(appliedFee)은 파티 문서가 아니라
  // parties/{id}/applications/{uid} 서브컬렉션에 신청 시점 스냅샷으로
  // 저장돼 있다(얼리버드 할인 등으로 파티의 현재 참가비와 다를 수 있음).
  // 미리보기는 클라이언트에서 계산하지만, 실제 환불 금액/상태는 서버
  // (cancelApplication)가 다시 계산해 저장한 값을 최종으로 신뢰한다.
  Future<void> _confirmAndCancelApplication(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final userId = UserSession.userId;
    if (userId.isEmpty) return;

    int appliedFee = 0;
    try {
      final appSnap = await FirebaseFirestore.instance
          .collection('parties')
          .doc(widget.docId)
          .collection('applications')
          .doc(userId)
          .get();
      appliedFee = (appSnap.data()?['appliedFee'] as num?)?.toInt() ?? 0;
    } catch (_) {
      // 조회 실패 시에도 취소 자체는 진행할 수 있게 0원으로 폴백(서버가 재계산).
    }

    final refundPolicy = RefundTier.listFromDynamic(data['refundPolicy']);
    final partyDateTime = PartyCard.parsePartyDateTime(data);
    final preview = computeRefundPreview(
      refundPolicy: refundPolicy,
      appliedFee: appliedFee,
      partyDateTime: partyDateTime,
    );

    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _CancelApplicationDialog(appliedFee: appliedFee, preview: preview),
    );
    if (confirmed != true || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF6FA0)),
      ),
    );

    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-northeast3',
      ).httpsCallable('cancelApplication');
      final result = await callable.call({'partyId': widget.docId});
      if (context.mounted) {
        Navigator.pop(context); // 로딩 닫기
        final resultData = Map<String, dynamic>.from(result.data as Map);
        final refundAmount = (resultData['refundAmount'] as num?)?.toInt() ?? 0;
        final msg = refundAmount > 0
            ? '신청이 취소되었어요. 환불 예정 금액 ${_formatFee(refundAmount)}'
            : '신청이 취소되었어요.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // 로딩 닫기
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('취소 처리에 실패했어요: $e')));
      }
    }
  }

  // 닉네임을 아직 설정하지 않았으면(null/빈 값/"기본닉네임") 참여를 진행하지
  // 않고 먼저 닉네임 설정 다이얼로그를 띄운다. 저장에 성공하면 true를 돌려줘
  // 호출부가 원래 하려던 신청을 곧바로 이어서 실행할 수 있게 한다(재클릭 불필요).
  Future<bool> _requireNickname(BuildContext context) async {
    if (UserSession.hasNickname) return true;
    final saved = await showNicknameEditDialog(
      context,
      title: '닉네임을 먼저 설정해주세요',
      description: '파티에 참여하려면 닉네임이 필요해요.',
    );
    return saved && UserSession.hasNickname;
  }

  String _applyErrorMessage(Object e) {
    final msg = e.toString();
    if (msg.contains('미인증')) return '본인인증 후 신청할 수 있습니다.';
    if (msg.contains('성별제한')) return '해당 성별만 신청할 수 있습니다.';
    if (msg.contains('연령미인증')) return '출생연도 인증 후 신청할 수 있습니다.';
    if (msg.contains('연령제한')) return '이 파티는 설정된 연령 제한에 해당하지 않아 신청할 수 없습니다.';
    if (msg.contains('마감')) return '마감되었습니다';
    if (msg.contains('이미신청')) return '이미 신청하셨습니다';
    return '신청에 실패했습니다';
  }

  /// 남자/여자 정원이 모두 찼는지(또는 전체 정원이 찼는지) 계산
  bool _isFull(Map<String, dynamic> data) {
    final mode = data['genderCapacityMode'] as String? ?? 'unlimited';
    if (mode == 'separate') {
      final maleCapacity = (data['maleCapacity'] as int?) ?? 0;
      final femaleCapacity = (data['femaleCapacity'] as int?) ?? 0;
      final currentMale = (data['currentMaleCount'] as int?) ?? 0;
      final currentFemale = (data['currentFemaleCount'] as int?) ?? 0;
      final maleFull = maleCapacity <= 0 || currentMale >= maleCapacity;
      final femaleFull = femaleCapacity <= 0 || currentFemale >= femaleCapacity;
      return maleFull && femaleFull;
    }
    final current = (data['currentParticipants'] as int?) ?? 0;
    final max =
        (data['maxParticipants'] as int?) ?? (data['maxCapacity'] as int? ?? 0);
    return max > 0 && current >= max;
  }

  // 남녀 참가비가 다르면 본인인증된 본인 성별 참가비만, 미인증이면 안내
  // 문구만 보여준다(남녀 가격이 같아도 '참가비' 한 줄로 통일해 표시).
  // 아이콘은 호출부(요약 카드의 _StatTile)가 그리므로 여기서는 값(메인)과
  // 얼리버드 할인율 같은 보조 정보를 한 쌍(record)으로 돌려준다.
  ({Widget main, Widget? sub}) _feeTileContent(Map<String, dynamic> data) {
    final maleFee = (data['maleFee'] as num?)?.toInt();
    final femaleFee = (data['femaleFee'] as num?)?.toInt();
    final legacyFee = (data['fee'] as num?)?.toInt();
    final earlyBirdOn = EarlyBird.isActive(data);
    // 얼리버드 문구는 핑크 알약 배지 안에 넣고, 폭이 좁은 칸에서도 항상
    // 한 줄로 보이도록 FittedBox로 필요하면 살짝 축소한다.
    final earlyBirdSub = earlyBirdOn
        ? FittedBox(
            fit: BoxFit.scaleDown,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: PartyChuColors.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '얼리버드 ${EarlyBird.discountPercent(data)}%',
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          )
        : null;

    // 참가비는 로그인 사용자에게만 공개되는 정보다 — 무료 파티(표시할 참가비
    // 자체가 없는 경우)는 기존처럼 아무것도 보여주지 않되, 참가비가 있는
    // 파티는 본인인증 여부와 무관하게 로그인 전이면 잠금 안내만 보여준다.
    final hasFeeData =
        maleFee != null ||
        femaleFee != null ||
        (legacyFee != null && legacyFee > 0);
    if (hasFeeData && !UserSession.isLoggedIn) {
      return (
        main: const Text(
          '로그인 후 확인',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: PartyChuColors.muted,
          ),
        ),
        sub: null,
      );
    }

    if (maleFee != null || femaleFee != null) {
      if (!UserSession.identityVerified || UserSession.gender.isEmpty) {
        return (
          main: const Text(
            '본인인증 후 확인',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: PartyChuColors.muted,
            ),
          ),
          sub: null,
        );
      }
      final isMale = UserSession.gender == 'male';
      final ownFee = isMale ? maleFee : femaleFee;
      if (ownFee == null) {
        return (
          main: const Text('-', textAlign: TextAlign.center, style: _tileValueStyle),
          sub: null,
        );
      }
      return (main: _priceRich(data, ownFee, earlyBirdOn), sub: earlyBirdSub);
    }
    if (legacyFee != null && legacyFee > 0) {
      return (main: _priceRich(data, legacyFee, earlyBirdOn), sub: earlyBirdSub);
    }
    return (
      main: const Text('무료', textAlign: TextAlign.center, style: _tileValueStyle),
      sub: null,
    );
  }

  // 참가비가 있는 파티만 환불 규정을 보여준다 — 무료 파티는 취소해도 환불
  // 자체가 없으므로(참가 취소만 처리) 규정을 안내할 필요가 없다.
  Widget _refundPolicyInfo(Map<String, dynamic> data) {
    final maleFee = (data['maleFee'] as num?)?.toInt();
    final femaleFee = (data['femaleFee'] as num?)?.toInt();
    final legacyFee = (data['fee'] as num?)?.toInt();
    final baseFee = maleFee ?? femaleFee ?? legacyFee ?? 0;
    if (baseFee <= 0) return const SizedBox.shrink();

    final tiers = RefundTier.listFromDynamic(data['refundPolicy']);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: PartyChuCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.assignment_return_outlined,
                  size: 20,
                  color: Color(0xFFFF8A80),
                ),
                const SizedBox(width: 8),
                _sectionTitle('환불 규정'),
              ],
            ),
            const SizedBox(height: 12),
            RefundPolicyView(tiers: tiers),
          ],
        ),
      ),
    );
  }

  /// 요약 카드의 참가비 한 줄 값 — 얼리버드 중이면 할인 적용가를, 아니면
  /// 정가를 굵게 표시한다. 할인율/원가 대비 정보는 옆의 보조 줄
  /// ("얼리버드 10%")이 맡으므로 여기서는 한 줄에 들어가는 최종 금액만
  /// 보여준다(취소선 표기는 카드 폭이 좁아지며 줄바꿈을 유발해 제외).
  Widget _priceRich(
    Map<String, dynamic> data,
    int fee,
    bool earlyBirdOn,
  ) {
    final displayFee = earlyBirdOn && fee > 0
        ? EarlyBird.effectivePrice(fee, data)
        : fee;
    return Text(
      _formatFee(displayFee),
      textAlign: TextAlign.center,
      style: _tileValueStyle,
    );
  }

  /// 얼리버드 진행 중일 때만 표시되는 배지 + 종료시각 + 남은시간 카드.
  /// "숙박+파티" 콤보로 등록된 파티(`linkedPlaceId` 있음)에서만 렌더링되는
  /// "숙박 정보 함께보기" 카드 — 연결된 `places/{id}` 문서를 1회 조회해
  /// 숙박유형/체크인·체크아웃/대표가격을 보여주고, 장소 상세로 이동하는
  /// 버튼을 제공한다. 필드가 없는(일반) 파티는 아무것도 그리지 않는다.
  Widget _linkedPlaceInfo(Map<String, dynamic> data) {
    final linkedPlaceId = data['linkedPlaceId'] as String?;
    if (linkedPlaceId == null || linkedPlaceId.isEmpty) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('places')
          .doc(linkedPlaceId)
          .get(),
      builder: (context, snapshot) {
        final placeData = snapshot.data?.data();
        if (placeData == null) return const SizedBox.shrink();
        final checkIn = placeData['accommodationCheckInTime'] as String?;
        final checkOut = placeData['accommodationCheckOutTime'] as String?;
        final price = (placeData['pricePerHour'] as num?)?.toInt() ?? 0;
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: PartyChuCard(
            child: SizedBox(
              width: double.infinity,
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.hotel_outlined, size: 16, color: Color(0xFF7C5CBF)),
                    SizedBox(width: 6),
                    Text(
                      '숙박 정보 함께보기',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF7C5CBF),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (placeData['type'] != null)
                  Text('숙박 유형 : ${placeData['type']}',
                      style: const TextStyle(fontSize: 12, color: Colors.black54)),
                if (checkIn != null && checkOut != null)
                  Text('체크인 $checkIn · 체크아웃 $checkOut',
                      style: const TextStyle(fontSize: 12, color: Colors.black54)),
                if (price > 0)
                  Text('숙박 가격 ${formatPrice(price)}~',
                      style: const TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    webFramedRoute((_) => PlaceDetailScreen(
                        placeId: linkedPlaceId,
                        data: placeData,
                      ),
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: const Color(0xFF7C5CBF),
                  ),
                  child: const Text('숙박 상세 보기 →', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                if (placeData['packageBookingEnabled'] == true) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        webFramedRoute((_) => PackageBookingScreen(
                            placeId: linkedPlaceId,
                            partyId: widget.docId,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.card_giftcard, size: 18),
                      label: const Text('📦 패키지로 예약하기'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7C5CBF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// "플레이스+파티" 콤보로 등록된 파티(`linkedEventId` 있음)에서만 렌더링되는
  /// "플레이스 정보 함께보기" 카드 — 연결된 `events/{id}` 문서를 1회 조회해
  /// 특징 태그/위치를 보여주고, 플레이스 상세로 이동하는 버튼을 제공한다.
  /// `linkedPlaceId`(숙박+파티 콤보, `places` 컬렉션 하드코딩)와는 다른
  /// 필드/컬렉션이라 별도 위젯으로 분리한다 — 필드가 없는(일반) 파티는
  /// 아무것도 그리지 않는다.
  Widget _linkedEventInfo(Map<String, dynamic> data) {
    final linkedEventId = data['linkedEventId'] as String?;
    if (linkedEventId == null || linkedEventId.isEmpty) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('events')
          .doc(linkedEventId)
          .get(),
      builder: (context, snapshot) {
        final eventData = snapshot.data?.data();
        if (eventData == null) return const SizedBox.shrink();
        final themeTags =
            (eventData['themeTags'] as List?)?.cast<String>() ?? const [];
        final location = eventData['location'] as String? ?? '';
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF0F5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFFD6E4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.wine_bar_outlined, size: 16, color: Color(0xFFFF6FA0)),
                  SizedBox(width: 6),
                  Text(
                    '플레이스 정보 함께보기',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF6FA0),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (themeTags.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final tag in themeTags)
                      Text(
                        '${ListingConstants.placeThemeTagEmojis[tag] ?? ''} $tag',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                  ],
                ),
              if (location.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('위치 : $location',
                      style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  webFramedRoute((_) => EventDetailScreen(
                      eventId: linkedEventId,
                      eventData: eventData,
                    ),
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: const Color(0xFFFF6FA0),
                ),
                child: const Text('플레이스 상세 보기 →',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _earlyBirdInfo(Map<String, dynamic> data) {
    if (!EarlyBird.isActive(data)) return const SizedBox.shrink();
    final end = EarlyBird.endAt(data);
    if (end == null) return const SizedBox.shrink();
    final pct = EarlyBird.discountPercent(data);
    final remaining = EarlyBird.remainingLabel(data);
    final dDay = EarlyBird.dDayLabel(data);

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: PartyChuCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PartyCard.earlyBirdBadge(pct),
                const SizedBox(width: 8),
                const Icon(Icons.schedule_outlined, size: 14, color: Color(0xFF64B5F6)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${EarlyBird.formatEndAt(end)}까지',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFD94F7A),
                    ),
                  ),
                ),
              ],
            ),
            if (remaining.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '종료까지 $remaining 남음${dDay.isNotEmpty ? ' ($dDay)' : ''}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatFee(int fee) => formatPrice(fee);

  // 요약 카드 4칸 공통 타이포 — 값(Value)이 가장 먼저 눈에 들어오도록
  // 라벨보다 훨씬 크고 굵게, 보조 설명은 라벨보다 살짝 크되 값보다는
  // 작게 둔다(모두 가운데 정렬).
  static const _tileValueStyle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    color: Colors.black,
  );
  static const _tileSubStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: Color(0xFF8A8A8A),
  );

  static const _weekdayKo = ['월', '화', '수', '목', '금', '토', '일'];

  /// 날짜 값(main)은 "MM.DD (요일)"로 직접 포맷한다(예: "09.28 (일)") —
  /// partyDateTime을 실제로 파싱해 요일을 계산하므로 항상 정확하다.
  /// 보조(시간) 줄은 기존 그대로 data['date'] 문자열의 공백 이후 부분을
  /// 그대로 사용한다(시간 포맷 로직은 건드리지 않음).
  ({String main, String? sub}) _splitDate(Map<String, dynamic> data) {
    final raw = (data['date'] as String?)?.trim() ?? '';
    final spaceIdx = raw.indexOf(' ');
    final sub = spaceIdx > 0 ? raw.substring(spaceIdx + 1).trim() : null;

    final dt = PartyCard.parsePartyDateTime(data);
    if (dt == null) {
      // 파싱 실패 시에만 기존 문자열 첫 토큰으로 안전하게 대체.
      if (raw.isEmpty) return (main: '-', sub: null);
      return (main: spaceIdx > 0 ? raw.substring(0, spaceIdx) : raw, sub: sub);
    }
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final wd = _weekdayKo[dt.weekday - 1];
    return (main: '$mm.$dd($wd)', sub: sub);
  }

  /// 참여 인원 요약 카드 값: unlimited면 메인에 "X/Y명"을, 보조 줄에는
  /// 성별 제한(genderLimit) 여부에 따라 "남녀무관"/"남자만"/"여자만"을
  /// 보여준다. separate면 메인에 남녀 합산 "X/Y명"을, 보조 줄에
  /// "남 A / 여 B"(현재 신청자 수)를 보여준다. 아이콘은 호출부의
  /// _StatTile이 그린다.
  ({Widget main, Widget? sub}) _peopleTileContent(Map<String, dynamic> data) {
    const mainStyle = _tileValueStyle;
    const subStyle = _tileSubStyle;
    final mode = data['genderCapacityMode'] as String? ?? 'unlimited';
    if (mode == 'separate') {
      final maleCapacity = (data['maleCapacity'] as int?) ?? 0;
      final femaleCapacity = (data['femaleCapacity'] as int?) ?? 0;
      final currentMale = (data['currentMaleCount'] as int?) ?? 0;
      final currentFemale = (data['currentFemaleCount'] as int?) ?? 0;
      final totalMax = maleCapacity + femaleCapacity;
      final totalCurrent = currentMale + currentFemale;
      return (
        main: Text(
          totalMax > 0 ? '$totalCurrent/$totalMax명' : '$totalCurrent명',
          textAlign: TextAlign.center,
          style: mainStyle,
        ),
        sub: Text(
          '남 $currentMale / 여 $currentFemale',
          textAlign: TextAlign.center,
          style: subStyle,
        ),
      );
    }
    final current = (data['currentParticipants'] as int?) ?? 0;
    final max =
        (data['maxParticipants'] as int?) ?? (data['maxCapacity'] as int? ?? 0);
    final genderLimit = data['genderLimit'] as String? ?? 'all';
    final genderLimitLabel = switch (genderLimit) {
      'male' => '남자만',
      'female' => '여자만',
      _ => '남녀무관',
    };
    return (
      main: Text(
        max > 0 ? '$current/$max명' : (data['people'] as String? ?? '-'),
        textAlign: TextAlign.center,
        style: mainStyle,
      ),
      sub: Text(genderLimitLabel, textAlign: TextAlign.center, style: subStyle),
    );
  }

  /// "한눈에 보기" 카드의 4칸(날짜/장소/참여 인원/참가비) — 실제 데이터
  /// 길이에 맞춰 줄바꿈되도록 maxLines/ellipsis를 강제하지 않는다(짧은
  /// 값은 1줄, 긴 주소·날짜는 2줄 이상으로 자연스럽게 늘어남). 4칸은
  /// 항상 동일한 폭(Expanded, flex 균등)으로 나란히 배치한다.
  /// IntrinsicHeight가 그 중 가장 긴 칸 높이에 맞춰 전체 행(과 세로
  /// 구분선)을 자동으로 늘려준다 — 고정 height가 없으므로 카드 높이도
  /// 내용에 맞춰 늘어난다.
  Widget _summaryStatsRow(Map<String, dynamic> data, String address) {
    final peopleContent = _peopleTileContent(data);
    final feeContent = _feeTileContent(data);
    final dateParts = _splitDate(data);
    final locationLines = RegionData.partyLocationLines(data);
    const divider = VerticalDivider(
      width: 14,
      thickness: 1,
      color: PartyChuColors.border,
    );
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _StatTile(
              icon: Icons.calendar_month_rounded,
              color: const Color(0xFFFF6FAF),
              label: '날짜',
              // "MM.DD(요일)"이 좁은 칸에서도 항상 한 줄로 다 보이도록
              // FittedBox로 필요한 만큼만 폰트를 줄인다(늘리지는 않음).
              value: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(dateParts.main, maxLines: 1, softWrap: false),
              ),
              sub: dateParts.sub == null
                  ? null
                  : Text(
                      dateParts.sub!,
                      textAlign: TextAlign.center,
                      style: _tileSubStyle,
                    ),
            ),
          ),
          divider,
          Expanded(
            child: _StatTile(
              icon: Icons.location_on_rounded,
              color: const Color(0xFFB06CFF),
              label: '장소',
              // 동/시·구 이름도 한 줄씩만 — 각각 FittedBox로 한 줄 안에
              // 맞춘다.
              value: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(locationLines.dong, maxLines: 1, softWrap: false),
              ),
              sub: locationLines.cityDistrict.isEmpty
                  ? null
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        locationLines.cityDistrict,
                        maxLines: 1,
                        softWrap: false,
                        style: _tileSubStyle,
                      ),
                    ),
            ),
          ),
          divider,
          Expanded(
            child: _StatTile(
              icon: Icons.groups_2_rounded,
              color: const Color(0xFF4ECBA7),
              label: '참여 인원',
              value: peopleContent.main,
              sub: peopleContent.sub,
            ),
          ),
          divider,
          Expanded(
            child: _StatTile(
              icon: Icons.sell_rounded,
              color: const Color(0xFFFF5FA2),
              label: '참가비',
              value: feeContent.main,
              sub: feeContent.sub,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 파티추 테마(핑크+화이트)에 맞춰 차가운 회색 톤 대신 은은한 핑크
      // 배경톤으로 통일한다.
      backgroundColor: const Color(0xFFFFF7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF5F8),
        elevation: 0,
        foregroundColor: const Color(0xFF3A2E39),
        centerTitle: true,
        title: const Text('모임 상세', style: TextStyle(fontFamily: 'SeoulHangang', fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('parties')
            .doc(widget.docId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.data() as Map<String, dynamic>?;
          if (data == null) {
            return const Center(child: Text('데이터를 찾을 수 없습니다'));
          }

          final applicants = List<String>.from(data['applicants'] ?? []);
          final userId = UserSession.userId;
          final currentUid = FirebaseAuth.instance.currentUser?.uid ?? userId;
          final isFull = _isFull(data);
          final alreadyApplied =
              userId.isNotEmpty && applicants.contains(userId);
          final isHost =
              currentUid.isNotEmpty &&
              (data['hostUid'] == currentUid || data['hostId'] == currentUid);
          final isRecurring = data['isRecurring'] as bool? ?? false;
          final lastUsedAt = data['lastUsedAt'] as Timestamp?;
          final recurringExpired =
              lastUsedAt != null &&
              lastUsedAt.toDate().isBefore(
                DateTime.now().subtract(const Duration(days: 30)),
              );
          // 로그인 전에는 성별/연령을 알 수 없어 checkPartyEligibility가
          // "연령 제한"/"성별 제한"으로 잘못 판정한다(null을 조건 미충족으로
          // 취급하기 때문) — 로그인하지 않은 상태에서는 이 결과를 신청 버튼
          // 비활성화/문구에 쓰지 않고, 대신 로그인부터 유도한다.
          final loggedOut = userId.isEmpty;
          final eligibility = checkPartyEligibility(
            data,
            UserSession.gender,
            UserSession.birthYear,
          );

          final mainImageUrl = data['mainImageUrl'] as String?;
          final imageUrlsList = List<String>.from(
            data['imageUrls'] as List? ?? [],
          );
          final imagesList = List<String>.from(data['images'] as List? ?? []);
          // 갤러리는 images 우선, 없으면 imageUrls 사용
          final images = imagesList.isNotEmpty ? imagesList : imageUrlsList;
          debugPrint(
            '[Detail] "${data['title']}": mainImageUrl=$mainImageUrl, imageUrls=$imageUrlsList, images=$imagesList',
          );
          final videoUrl = data['videoUrl'] as String?;
          final videoThumbnailUrl = data['videoThumbnailUrl'] as String?;
          // 사진만 등록된 파티(동영상 없음)에 Spotify 미리듣기가 걸려 있으면
          // 상세페이지 진입 시 자동재생한다.
          final spotifyPreviewUrl = (videoUrl == null || videoUrl.isEmpty)
              ? PartyCard.spotifyPreviewUrl(data)
              : null;

          // 대표 미디어 — 등록/수정 시 이미 images 배열의 맨 앞(index 0)으로
          // 재정렬해 저장하므로 갤러리는 항상 index 0부터 연다. 재정렬 전에
          // 저장된 과거 데이터도 방어적으로 여기서 한 번 더 맞춰준다(대표
          // 사진이 index 0이 아니면 이 화면에서만 맨 앞으로 옮기고, Firestore에
          // 다시 쓰지는 않는다).
          final cover = getPartyCoverMedia(data, tag: 'DetailHero');
          final videoIsCover = cover?.isVideo ?? false;
          if (!videoIsCover && cover?.imageUrl != null) {
            final idx = images.indexOf(cover!.imageUrl!);
            if (idx > 0) {
              images
                ..removeAt(idx)
                ..insert(0, cover.imageUrl!);
            }
          }
          const galleryInitialPage = 0;

          final lat = (data['latitude'] as num?)?.toDouble() ?? 0.0;
          final lng = (data['longitude'] as num?)?.toDouble() ?? 0.0;
          final hasLocation = lat != 0.0 && lng != 0.0;

          final roadAddress = data['roadAddress'] as String? ?? '';
          final address = roadAddress.isNotEmpty
              ? roadAddress
              : (data['address'] as String?)?.isNotEmpty == true
              ? data['address'] as String
              : data['location'] as String? ?? '';
          final detailAddress = data['detailAddress'] as String? ?? '';

          final recruitStatus = data['recruitStatus'] as String? ?? '모집중';
          final recruitDeadlineAt = data['recruitDeadlineAt'] as Timestamp?;
          final deadlinePassed =
              recruitDeadlineAt != null &&
              recruitDeadlineAt.toDate().isBefore(DateTime.now());
          // 이미 신청한 상태에서 취소 가능 여부 — 파티가 아직 시작 전이고,
          // 호스트가 파티 자체를 취소하지 않은 경우에만 참가자가 직접 취소할 수 있다.
          final partyStartedAt = PartyCard.parsePartyDateTime(data);
          final partyStarted =
              partyStartedAt != null && partyStartedAt.isBefore(DateTime.now());
          final canCancelApplication =
              alreadyApplied && !partyStarted && recruitStatus == '모집중';
          final ageRestrictionEnabled =
              data['ageRestrictionEnabled'] as bool? ?? false;
          final minBirthYear = (data['minBirthYear'] as num?)?.toInt();
          final maxBirthYear = (data['maxBirthYear'] as num?)?.toInt();

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── 미디어 갤러리 (이미지 + 동영상 통합) + 공유·찜 오버레이 ──
                      // 대표 미디어가 사진이든 동영상이든 같은 위치에 뜨도록
                      // MediaGallery 바깥에서 한 번만 오버레이한다(내부 점
                      // 인디케이터는 bottom:12라 bottom:16 오버레이와 겹치지
                      // 않고, 동영상 진행바는 bottom:0이라 역시 안 겹친다).
                      Stack(
                        children: [
                          if (images.isNotEmpty ||
                              (videoUrl != null && videoUrl.isNotEmpty))
                            MediaGallery(
                              images: images,
                              videoUrl: videoUrl,
                              videoThumbnailUrl: videoThumbnailUrl,
                              initialPage: galleryInitialPage,
                              videoFirst: videoIsCover,
                              // 원본 비율 그대로 보여주고(잘리지 않음), 비율
                              // 차이로 남는 여백은 화면 배경(Scaffold
                              // backgroundColor)과 같은 연핑크로 — 다른
                              // 화면(장소대여 상세 등)은 기본값(cover+그라데이션)
                              // 그대로라 영향 없다.
                              videoFit: BoxFit.contain,
                              videoBackgroundColor: const Color(0xFFFFF7FA),
                              // 우측 상단 "1/2" 카운터도 파티추 핑크 톤으로.
                              counterAccentColor: const Color(0xFFFF6FA0),
                            )
                          else
                            Container(
                              width: double.infinity,
                              height: 220,
                              color: const Color(0xFFE9ECF5),
                              child: const Icon(
                                Icons.image_outlined,
                                size: 60,
                                color: Colors.grey,
                              ),
                            ),
                          // bottom:20 — 진행 바(VideoSeekBar, GalleryVideoItem
                          // 내부 bottom:48)보다 아래, 화면 맨 아래 가장자리에
                          // 가깝게 둔다. 순서를 "진행 바 → 스피커·공유·찜
                          // 버튼"으로 바꾸면서 값만 진행 바와 맞바꿨다(겹치지
                          // 않도록 이미 맞춰둔 간격 28px은 그대로 유지).
                          Positioned(
                            right: 16,
                            bottom: 20,
                            child: Row(
                              children: [
                                ShareIconButton(
                                  onTap: () => showPartyShareSheet(
                                    context,
                                    partyId: widget.docId,
                                    partyData: data,
                                  ),
                                  size: 20,
                                  color: PartyChuColors.primary,
                                ),
                                const SizedBox(width: 10),
                                FavoriteStarButton(
                                  itemType: FavoriteType.party,
                                  itemId: widget.docId,
                                  size: 20,
                                  glow: false,
                                ),
                              ],
                            ),
                          ),
                          // 대표 미디어가 동영상일 때만 음소거 버튼을 영상
                          // 왼쪽 아래에 오버레이한다(사진만 있으면 음소거할
                          // 대상이 없으므로 숨김). 공유/찜 버튼과는 반대쪽
                          // 모서리에 둬서 서로 겹치지 않는다. bottom 값은
                          // 위 공유/찜 버튼과 동일하게 맞춰 진행 바 아래에 둔다.
                          if (videoUrl != null && videoUrl.isNotEmpty)
                            const Positioned(
                              left: 16,
                              bottom: 20,
                              child: MuteToggleIconButton(size: 20),
                            ),
                          // Spotify 미리듣기 자동재생 — 화면에 보이는 위젯은
                          // 없고(소리는 전역 버튼 GlobalMuteFab으로만 제어),
                          // 재생 생명주기만 담당한다.
                          if (spotifyPreviewUrl != null)
                            Positioned(
                              left: 16,
                              bottom: 20,
                              child: _SpotifyPreviewAudio(
                                previewUrl: spotifyPreviewUrl,
                              ),
                            ),
                        ],
                      ),

                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 파티 유형 칩 + 모집 상태 배지 — 모집중일 때는
                            // 배지를 아예 그리지 않는다(Wrap 자식에서 빼야
                            // spacing만큼의 빈 간격도 남지 않는다).
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ..._partyTypeChips(data),
                                if (deadlinePassed || recruitStatus != '모집중')
                                  _statusBadge(
                                    deadlinePassed ? '모집마감' : recruitStatus,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // 제목 — 장식 없이 굵은 텍스트만(미니멀 톤).
                            Text(
                              data['title'] as String? ?? '',
                              style: const TextStyle(
                                fontFamily: PartyChuTitleFont.family,
                                fontSize: 22,
                                fontWeight: PartyChuTitleFont.medium,
                                height: 1.3,
                                color: PartyChuColors.heading,
                                shadows: [
                                  Shadow(color: PartyChuColors.heading, offset: Offset(0.3, 0)),
                                  Shadow(color: PartyChuColors.heading, offset: Offset(-0.3, 0)),
                                  Shadow(color: PartyChuColors.heading, offset: Offset(0, 0.3)),
                                  Shadow(color: PartyChuColors.heading, offset: Offset(0, -0.3)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            // 파티 핵심 정보 요약 카드 — 세로 목록 대신
                            // 날짜·장소·참여 인원·참가비를 한 줄(1x4)로
                            // 나란히 보여주고, 나이 제한/모집마감처럼 부가
                            // 정보는 카드 하단의 보조 줄로 분리한다.
                            PartyChuCard(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 22,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _summaryStatsRow(data, address),
                                  if (address.isNotEmpty ||
                                      recruitDeadlineAt != null ||
                                      (ageRestrictionEnabled &&
                                          minBirthYear != null &&
                                          maxBirthYear != null)) ...[
                                    const SizedBox(height: 18),
                                    const Divider(
                                      height: 1,
                                      color: PartyChuColors.border,
                                    ),
                                    const SizedBox(height: 14),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (address.isNotEmpty) ...[
                                          Builder(builder: (context) {
                                            final fullAddress = detailAddress.isNotEmpty
                                                ? '${RegionData.shortenRegionPrefix(address)} $detailAddress'
                                                : RegionData.shortenRegionPrefix(address);
                                            return _miniInfoRow(
                                              Icons.location_on_rounded,
                                              '상세 주소',
                                              fullAddress,
                                              color: const Color(0xFFB06CFF),
                                              showChevron: false,
                                              trailing: _CopyAddressButton(address: fullAddress),
                                            );
                                          }),
                                          const SizedBox(height: 12),
                                        ],
                                        if (recruitDeadlineAt != null) ...[
                                          _miniInfoRow(
                                            Icons.schedule_rounded,
                                            '모집 마감',
                                            _formatDeadline(recruitDeadlineAt.toDate()),
                                            color: const Color(0xFF64B5F6),
                                            trailing: Text(
                                              _dDayLabel(recruitDeadlineAt.toDate()),
                                              style: const TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFFFF5C93),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                        ],
                                        if (ageRestrictionEnabled &&
                                            minBirthYear != null &&
                                            maxBirthYear != null)
                                          _miniInfoRow(
                                            Icons.verified_user_rounded,
                                            '나이 제한',
                                            '${ageFromBirthYear(maxBirthYear)}세 ~ ${ageFromBirthYear(minBirthYear)}세',
                                            color: const Color(0xFFB06CFF),
                                            showChevron: false,
                                          ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            // 얼리버드 · 연동 숙소 · 환불 규정 — 각각 독립된
                            // 둥근 카드로 분리(있을 때만 렌더링).
                            _earlyBirdInfo(data),
                            _linkedPlaceInfo(data),
                            _linkedEventInfo(data),
                            _refundPolicyInfo(data),

                            const SizedBox(height: 24),

                            // 상세 설명 방식 — "간편 자동 꾸미기" 또는 "직접
                            // 상세페이지 만들기" 중 선택된 한쪽만 보여준다
                            // (둘 다 저장돼 있어도 렌더링은 하나만).
                            // detailDescriptionMode가 아예 없는(이 기능
                            // 이전에 등록된) 파티는 오늘과 완전히 동일하게
                            // 보이도록, detailBlocks 유무로만 판단해 기존
                            // 두 갈래(블록 섹션/평문 description) 로직을
                            // 그대로 유지한다 — 새로 "자동 꾸미기"로 보이는
                            // 회귀가 생기지 않는다.
                            ...() {
                              final modeRaw = data['detailDescriptionMode'] as String?;
                              final detailBlocks = PartyDetailBlock.listFromDynamic(
                                data['detailBlocks'],
                              );

                              final isBlocksMode = modeRaw == 'blocks' ||
                                  (modeRaw == null && detailBlocks.isNotEmpty);
                              if (isBlocksMode) {
                                if (detailBlocks.isEmpty) return <Widget>[];
                                final detailTheme = partyDetailThemeKeyFromString(
                                  data['detailTheme'] as String?,
                                );
                                final detailDecorationIntensity =
                                    partyDetailDecorationIntensityFromString(
                                  data['detailDecorationIntensity'] as String?,
                                );
                                final detailDecorationVariantSeed =
                                    (data['detailDecorationVariantSeed'] as num?)?.toInt() ?? 0;
                                return [
                                  _DetailBlockSection(
                                    blocks: detailBlocks,
                                    theme: detailTheme,
                                    intensity: detailDecorationIntensity,
                                    variantSeed: detailDecorationVariantSeed,
                                    partyId: widget.docId,
                                    onImageTap: (block) {
                                      final url = block.imageUrl;
                                      if (url == null || url.isEmpty) return;
                                      Navigator.push(
                                        context,
                                        webFramedRoute((_) => FullScreenImageViewer(imageUrl: url),
                                        ),
                                      );
                                    },
                                  ),
                                ];
                              }

                              if (modeRaw == 'auto') {
                                final description = (data['description'] as String?)?.trim() ?? '';
                                if (description.isEmpty) return <Widget>[];
                                final style = PartyAutoDescriptionStyle.fromMap(
                                  data['autoDescriptionStyle'] as Map<String, dynamic>?,
                                );
                                // 새 렌더러를 만들지 않고, 소개글 원문을
                                // classifyDescriptionToBlocks로 자동 분석해
                                // (날짜/장소/가격/주의/마감/배너/리스트/본문
                                // 카드) 블록형 상세페이지와 동일한
                                // PartyDetailBlockPreview에 그대로 넣는다.
                                // 원문(description)은 여기서 전혀 가공하지
                                // 않는다 — 분류·이모지는 매번 다시 계산되는
                                // 렌더링 전용 파생물일 뿐 저장되지 않는다.
                                final isRich =
                                    style.intensity == PartyDetailDecorationIntensity.rich;
                                final keywords = isRich
                                    ? extractAutoDescriptionKeywords(description)
                                    : const <({String emoji, String label})>[];
                                final detailPalette = PartyDetailThemeRegistry.fromKey(style.theme);
                                return [
                                  if (keywords.isNotEmpty) ...[
                                    PartyAutoKeywordBadges(
                                      keywords: keywords,
                                      palette: detailPalette,
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  PartyDetailBlockPreview(
                                    blocks: classifyDescriptionToBlocks(
                                      description,
                                      variantSeed: style.variantSeed,
                                      paragraphStyles: style.paragraphStyles,
                                      rich: isRich,
                                    ),
                                    theme: style.theme,
                                    intensity: style.intensity,
                                    variantSeed: style.variantSeed,
                                    partyId: widget.docId,
                                    richAutoDecorations: isRich,
                                  ),
                                ];
                              }

                              // modeRaw == null && detailBlocks.isEmpty —
                              // 레거시 파티, 평문 소개도 카드 안에 담아
                              // 다른 섹션들과 톤을 맞춘다(내용/로직은 동일).
                              return [
                                PartyChuCard(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _sectionTitle('모임 소개'),
                                      const SizedBox(height: 12),
                                      Text(
                                        (data['description'] as String?)
                                                    ?.isNotEmpty ==
                                                true
                                            ? data['description'] as String
                                            : '등록된 설명이 없습니다.',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          color: PartyChuColors.muted,
                                          height: 1.7,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ];
                            }(),

                            // 분위기
                            ...() {
                              final vibes =
                                  (data['vibes'] as List?)?.cast<String>() ??
                                  [];
                              if (vibes.isEmpty) return <Widget>[];
                              return [
                                const SizedBox(height: 24),
                                _sectionTitle('분위기'),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: vibes
                                      .map(
                                        (v) => Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF3EFFA),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            border: Border.all(
                                              color: const Color(0xFFCFC0E8),
                                            ),
                                          ),
                                          child: Text(
                                            v,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: Color(0xFF7C5CBF),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ];
                            }(),

                            // 태그
                            ...() {
                              final tags =
                                  (data['tags'] as List?)?.cast<String>() ?? [];
                              if (tags.isEmpty) return <Widget>[];
                              return [
                                const SizedBox(height: 24),
                                _sectionTitle('태그'),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: tags
                                      .map(
                                        (t) => Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF7F8FC),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            border: Border.all(
                                              color: const Color(0xFFDDE1EC),
                                            ),
                                          ),
                                          child: Text(
                                            '#$t',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: Colors.black54,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ];
                            }(),

                            // ── 위치 지도 ─────────────────────────────
                            if (hasLocation) ...[
                              const SizedBox(height: 24),
                              _sectionTitle('위치'),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(26),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.04),
                                      blurRadius: 16,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: SizedBox(
                                    height: 200,
                                    child: _PartyLocationMap(
                                      key: ValueKey('map_${lat}_$lng'),
                                      latitude: lat,
                                      longitude: lng,
                                    ),
                                  ),
                                ),
                              ),
                              if (address.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text.rich(
                                  TextSpan(
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: PartyChuColors.muted,
                                    ),
                                    children: [
                                      TextSpan(text: address),
                                      if (detailAddress.isNotEmpty) ...[
                                        const TextSpan(text: ' '),
                                        TextSpan(
                                          text: detailAddress,
                                          style: const TextStyle(fontSize: 13.5),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ],

                            const SizedBox(height: 100),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 파티장: 신청자 목록 + 재등록 버튼 — 메인 CTA답게 좌우 여백을
              // 넉넉히 두고, 은은한 핑크 그림자 + 양옆 반짝이 장식을 더한다.
              if (isHost)
                Container(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    16,
                    20,
                    16 + MediaQuery.of(context).padding.bottom,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: const Border(
                      top: BorderSide(color: PartyChuColors.border),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: PartyChuColors.primary.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 앱 공통 PartyChuPrimaryButton — 발바닥 배지/반짝이
                      // 장식 없이 그라데이션 버튼만 미니멀하게 사용한다.
                      PartyChuPrimaryButton(
                        label: '신청자 목록 (${List.from(data['applicants'] ?? []).length}명)',
                        showBadge: false,
                        showSparkle: false,
                        onTap: () {
                          Navigator.push(
                            context,
                            webFramedRoute((_) => PartyApplicantsScreen(
                                partyId: widget.docId,
                                partyTitle: data['title'] as String? ?? '',
                                rounds: (data['rounds'] as List?)
                                    ?.map((r) => Map<String, dynamic>.from(r as Map))
                                    .toList(),
                              ),
                            ),
                          );
                        },
                      ),
                      if (isRecurring) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: OutlinedButton.icon(
                            onPressed: recurringExpired
                                ? null
                                : () => Navigator.push(
                                    context,
                                    webFramedRoute((_) => PartyReRegisterScreen(
                                        sourceData: data,
                                        sourcePartyId: widget.docId,
                                      ),
                                    ),
                                  ),
                            icon: const Icon(Icons.repeat, size: 18),
                            label: Text(
                              recurringExpired ? '재등록 기간 만료 (1개월 초과)' : '재등록',
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: recurringExpired
                                  ? Colors.black38
                                  : const Color(0xFFFF6FA0),
                              side: BorderSide(
                                color: recurringExpired
                                    ? Colors.black12
                                    : const Color(0xFFFF6FA0),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

              // 일반 사용자: 신청 버튼
              if (!isHost)
                Container(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    12 + MediaQuery.of(context).padding.bottom,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: const Border(
                      top: BorderSide(color: PartyChuColors.border),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: PartyChuColors.primary.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!loggedOut &&
                          eligibility != PartyEligibility.eligible &&
                          !alreadyApplied)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.lock_outline,
                                size: 14,
                                color: Color(0xFF7B5EA7),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  eligibilityReason(eligibility),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF7B5EA7),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: canCancelApplication
                            ? OutlinedButton(
                                onPressed: () =>
                                    _confirmAndCancelApplication(context, data),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                child: const Text('신청 취소'),
                              )
                            : ElevatedButton(
                                onPressed:
                                    (isFull ||
                                        alreadyApplied ||
                                        recruitStatus != '모집중' ||
                                        deadlinePassed ||
                                        (!loggedOut &&
                                            eligibility !=
                                                PartyEligibility.eligible))
                                    ? null
                                    : () async {
                                        if (userId.isEmpty) {
                                          // await 없이 push만 하면 로그인
                                          // 완료 후 돌아왔을 때 이 tap
                                          // 핸들러는 이미 끝나버려서 로그인
                                          // 여부를 다시 확인할 기회가
                                          // 없었다 — UserSession.revision을
                                          // 구독 중이라 화면 자체는 곧바로
                                          // 갱신되지만, 여기서도 await해
                                          // 화면이 돌아온 시점을 명확히
                                          // 한다.
                                          await Navigator.push(
                                            context,
                                            webFramedRoute((_) => LoginPage(),
                                            ),
                                          );
                                          return;
                                        }
                                        if (!await _requireNickname(context))
                                          return;
                                        if (!context.mounted) return;
                                        List<int>? selectedRounds;
                                        if (data['hasMultipleRounds'] ==
                                            true) {
                                          selectedRounds = await _pickRounds(
                                            context,
                                            data,
                                          );
                                          if (selectedRounds == null ||
                                              selectedRounds.isEmpty) {
                                            return;
                                          }
                                        }
                                        if (!context.mounted) return;
                                        _apply(
                                          context,
                                          selectedRounds: selectedRounds,
                                        );
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: Colors.grey.shade300,
                                  disabledForegroundColor: Colors.grey,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                child: Text(
                                  deadlinePassed
                                      ? '모집마감'
                                      : recruitStatus != '모집중'
                                      ? recruitStatus
                                      : isFull
                                      ? '모집 마감'
                                      : alreadyApplied
                                      ? '신청 완료'
                                      : loggedOut
                                      ? '로그인 후 참가 확인'
                                      : eligibility != PartyEligibility.eligible
                                      ? eligibilityLabel(eligibility)
                                      : '신청하기',
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// 모든 섹션 제목에 공통으로 쓰는 스타일 — FontSize 22 / FontWeight.w700로
  /// 통일한다("한눈에 보기"/"환불 규정"/"모임 소개"/"분위기"/"태그"/"위치" 전부 동일).
  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: PartyChuTitleFont.family,
        fontSize: 19,
        fontWeight: PartyChuTitleFont.medium,
        color: PartyChuColors.heading,
        shadows: [
          Shadow(color: PartyChuColors.heading, offset: Offset(0.3, 0)),
          Shadow(color: PartyChuColors.heading, offset: Offset(-0.3, 0)),
          Shadow(color: PartyChuColors.heading, offset: Offset(0, 0.3)),
          Shadow(color: PartyChuColors.heading, offset: Offset(0, -0.3)),
        ],
      ),
    );
  }

  /// 요약 카드 하단의 보조 정보 한 줄(상세주소/모집마감/나이 제한) — 아이콘
  /// + 제목(회색) + 내용(검정) + 오른쪽 chevron 구조로 통일한다. 내용은
  /// 말줄임 없이 전체 표시(주소처럼 길면 자연스럽게 줄바꿈)하고, 왼쪽
  /// 정렬로 읽기 쉽게 둔다. chevron은 순수 장식(탭 동작 없음) — 기존
  /// 기능은 그대로 유지한다.
  Widget _miniInfoRow(
    IconData icon,
    String title,
    String content, {
    required Color color,
    bool showChevron = true,
    // 모집마감 행의 D-Day 배지처럼, 내용 오른쪽 끝에 고정으로 붙이는 보조
    // 위젯 — content는 Expanded라 아무리 길어져도 이 trailing은 밀려나지
    // 않고 항상 제자리에 남는다.
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF8A8A8A),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            content,
            textAlign: TextAlign.left,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing,
        ],
        if (showChevron) ...[
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, size: 17, color: Color(0xFFBFBFBF)),
        ],
      ],
    );
  }

  /// 모집마감일까지 남은 일수 — 시간이 아니라 "달력 날짜" 기준으로
  /// 계산한다(오늘이면 D-Day, 지났으면 마감, 남았으면 D-N).
  String _dDayLabel(DateTime deadline) {
    final now = DateTime.now();
    final deadlineDay = DateTime(deadline.year, deadline.month, deadline.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = deadlineDay.difference(today).inDays;
    if (diff < 0) return '마감';
    if (diff == 0) return 'D-Day';
    return 'D-$diff';
  }

  /// BBQ 파티/페스티벌 등 파티 유형 칩 — 연핑크 배경의 둥근 필로 통일한다.
  List<Widget> _partyTypeChips(Map<String, dynamic> data) {
    final types = (data['partyTypes'] as List?)?.cast<String>() ?? [];
    final fallback = data['category'] as String? ?? '';
    final labels = types.isNotEmpty
        ? types
        : (fallback.isNotEmpty ? [fallback] : []);
    return labels.map((t) => _PartyChip(PartyConstants.labelFor(t))).toList();
  }

  /// 모집 상태 배지 — 모집중일 때는 호출부에서 아예 그리지 않고(위
  /// _partyTypeChips 옆 Wrap 참고), 모집마감(및 취소 등 그 외 상태)일 때만
  /// 기존 디자인 그대로 보여준다. 기본 Material 아웃라인 칩 대신 부드러운
  /// 핑크 배경의 필 배지로.
  Widget _statusBadge(String status) {
    final Color bg;
    final Color fg;
    final IconData icon;
    if (status == '마감' || status == '모집마감') {
      bg = const Color(0xFFFFE9EE);
      fg = const Color(0xFFE2568A);
      icon = Icons.lock_clock_rounded;
    } else {
      bg = const Color(0xFFF2F2F5);
      fg = const Color(0xFF8C8C99);
      icon = Icons.info_outline_rounded;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            status,
            style: TextStyle(
              fontSize: 12.5,
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDeadline(DateTime dt) {
    final h = dt.hour;
    final period = h < 12 ? '오전' : '오후';
    final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$period ${hour12.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// 참가 취소 최종 확인창 — 적용된 환불 규정/환불 예정 금액/환불되지 않는
// 금액을 취소 전에 반드시 확인시킨다.
/// 다차수(1차/2차/3차) 파티에서 신청 전 참여할 라운드를 고르는 다이얼로그.
/// 여러 개 중복 선택 가능, 최소 1개는 선택해야 "확인"이 활성화된다.
/// perRound 정원 모드에서 이미 꽉 찬 라운드는 체크박스를 비활성화한다.
class _RoundSelectionDialog extends StatefulWidget {
  final List<Map<String, dynamic>> rounds;

  const _RoundSelectionDialog({required this.rounds});

  @override
  State<_RoundSelectionDialog> createState() => _RoundSelectionDialogState();
}

class _RoundSelectionDialogState extends State<_RoundSelectionDialog> {
  final Set<int> _selected = {};

  bool _isRoundFull(Map<String, dynamic> round) {
    final maxCapacity = (round['maxCapacity'] as num?)?.toInt();
    if (maxCapacity == null) return false; // 통합 정원 모드 — 라운드 자체엔 정원 정보 없음
    final maleCapacity = (round['maleCapacity'] as num?)?.toInt() ?? 0;
    final femaleCapacity = (round['femaleCapacity'] as num?)?.toInt() ?? 0;
    if (maleCapacity <= 0 && femaleCapacity <= 0) {
      final current = (round['currentParticipants'] as num?)?.toInt() ?? 0;
      return maxCapacity > 0 && current >= maxCapacity;
    }
    final currentMale = (round['currentMaleCount'] as num?)?.toInt() ?? 0;
    final currentFemale = (round['currentFemaleCount'] as num?)?.toInt() ?? 0;
    final maleFull = maleCapacity <= 0 || currentMale >= maleCapacity;
    final femaleFull = femaleCapacity <= 0 || currentFemale >= femaleCapacity;
    return maleFull && femaleFull;
  }

  String _fmtTime(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = h < 12 ? '오전' : '오후';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$period $h12:$m';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        '참여할 라운드를 선택해주세요',
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
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '여러 개 선택할 수 있어요.',
              style: TextStyle(fontSize: 12, color: Colors.black45),
            ),
            const SizedBox(height: 4),
            ...widget.rounds.map((r) {
              final roundNumber = (r['roundNumber'] as num?)?.toInt() ?? 0;
              final label = r['label'] as String? ?? '$roundNumber차';
              final ts = r['time'];
              final time = ts is Timestamp ? ts.toDate() : null;
              final full = _isRoundFull(r);
              return CheckboxListTile(
                value: _selected.contains(roundNumber),
                enabled: !full,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                activeColor: const Color(0xFFFF6FA0),
                title: Text(
                  full ? '$label (마감)' : label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: full ? Colors.black38 : Colors.black87,
                  ),
                ),
                subtitle: time != null ? Text(_fmtTime(time)) : null,
                onChanged: full
                    ? null
                    : (v) => setState(() {
                        if (v == true) {
                          _selected.add(roundNumber);
                        } else {
                          _selected.remove(roundNumber);
                        }
                      }),
              );
            }),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, _selected.toList()..sort()),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF6FA0),
            foregroundColor: Colors.white,
          ),
          child: const Text('확인'),
        ),
      ],
    );
  }
}

class _CancelApplicationDialog extends StatelessWidget {
  final int appliedFee;
  final RefundPreview preview;

  const _CancelApplicationDialog({
    required this.appliedFee,
    required this.preview,
  });

  static String _fmt(int v) => formatAmount(v);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        '참가 신청을 취소하시겠습니까?',
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (appliedFee > 0) ...[
            _row(
              '적용된 환불 규정',
              preview.policyMissing
                  ? '호스트가 환불 규정을 등록하지 않았어요'
                  : preview.matchedTier != null
                  ? '파티 시작 ${preview.matchedTier!.daysBefore}일 전부터 '
                        '${preview.matchedTier!.refundPercent}% 환불'
                  : '해당하는 환불 구간이 없어요',
            ),
            const SizedBox(height: 8),
            _row(
              '환불 예정 금액',
              _fmt(preview.refundAmount),
              valueColor: const Color(0xFFFF6FA0),
            ),
            const SizedBox(height: 4),
            _row('환불되지 않는 금액', _fmt(preview.nonRefundableAmount)),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
          ] else
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                '무료 파티라 환불 없이 참가 취소만 처리돼요.',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ),
          const Text(
            '취소하면 되돌릴 수 없어요.',
            style: TextStyle(fontSize: 12, color: Colors.black45),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('돌아가기'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: const Text('신청 취소'),
        ),
      ],
    );
  }

  Widget _row(String label, String value, {Color? valueColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: Colors.black54),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: valueColor ?? Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}

// ── 블록형 상세페이지 — 상세페이지/글만보기 전환 ───────────────────────────
// 토글 상태를 이 작은 서브트리 안에만 둬서, 전환할 때마다 부모의
// StreamBuilder(파티 문서 구독)가 다시 빌드되지 않게 한다 — 그래야 화면
// 전체가 다시 로딩되지 않고 스크롤 위치도 튀지 않는다. 선택되지 않은
// 렌더러는 아예 빌드하지 않으므로(둘 다 숨겨서 유지하지 않음), 글만 보기가
// 아니면 사진 블록의 Image.network가 생성되지 않는다.
class _DetailBlockSection extends StatefulWidget {
  final List<PartyDetailBlock> blocks;
  final PartyDetailThemeKey theme;
  final PartyDetailDecorationIntensity intensity;

  /// "디자인 새로고침"으로 호스트가 고른 배경/구분 장식 변형 — 필드가 없는
  /// 기존 파티는 0(항상 지금까지와 동일한 배치).
  final int variantSeed;
  final void Function(PartyDetailBlock block) onImageTap;
  final String partyId;

  const _DetailBlockSection({
    required this.blocks,
    required this.theme,
    required this.intensity,
    this.variantSeed = 0,
    required this.onImageTap,
    required this.partyId,
  });

  @override
  State<_DetailBlockSection> createState() => _DetailBlockSectionState();
}

class _DetailBlockSectionState extends State<_DetailBlockSection> {
  // 초기 임시 기본값 — SharedPreferences 로딩이 끝나기 전까지는 이 값으로
  // 그린다(디자인 보기가 항상 유효한 선택이므로 깜빡임 없이 자연스럽다).
  PartyDetailViewMode _mode = PartyDetailViewMode.designed;

  @override
  void initState() {
    super.initState();
    // SharedPreferences는 initState에서 한 번만 불러온다(build()에서 반복
    // 호출하지 않음). 로딩이 끝나기 전에는 위 임시 기본값(designed)이 그대로
    // 화면에 남아 있어 깜빡임이 없다.
    PartyDetailViewMode.load().then((loaded) {
      if (!mounted) return;
      if (loaded == _mode) return; // 같은 값이면 불필요한 setState 생략
      setState(() => _mode = loaded);
    });
  }

  void _select(PartyDetailViewMode mode) {
    if (_mode == mode) return;
    setState(() => _mode = mode); // 먼저 즉시 화면에 반영
    unawaited(mode.save()); // 저장은 비동기로 — 실패해도 화면 동작에는 영향 없음
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailBlockViewToggle(
          currentMode: _mode,
          theme: widget.theme,
          onChanged: _select,
        ),
        const SizedBox(height: 16),
        switch (_mode) {
          PartyDetailViewMode.designed => PartyDetailBlockPreview(
              blocks: widget.blocks,
              theme: widget.theme,
              intensity: widget.intensity,
              variantSeed: widget.variantSeed,
              onImageTap: widget.onImageTap,
              partyId: widget.partyId,
            ),
          PartyDetailViewMode.textOnly => PartyDetailBlockTextView(
              blocks: widget.blocks,
              theme: widget.theme,
              partyId: widget.partyId,
            ),
        },
      ],
    );
  }
}

/// "[ 상세페이지 ] [ 글만보기 ]" 세그먼트 토글. 선택 상태를 배경색뿐 아니라
/// 글자 굵기로도 구분해(색만으로 구분하지 않음) 접근성을 확보한다. 선택된
/// 파티의 [theme]에 맞춰 강조색/트랙 배경을 그대로 반영한다.
class _DetailBlockViewToggle extends StatelessWidget {
  final PartyDetailViewMode currentMode;
  final PartyDetailThemeKey theme;
  final ValueChanged<PartyDetailViewMode> onChanged;

  const _DetailBlockViewToggle({
    required this.currentMode,
    required this.theme,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final palette = PartyDetailThemeRegistry.fromKey(theme);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.tabTrackBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(child: _segment(palette, PartyDetailViewMode.designed)),
          Expanded(child: _segment(palette, PartyDetailViewMode.textOnly)),
        ],
      ),
    );
  }

  Widget _segment(PartyDetailThemeData palette, PartyDetailViewMode segmentMode) {
    final selected = currentMode == segmentMode;
    final segment = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(
        color: selected ? palette.selectedTabBackground : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: Text(
        segmentMode.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          fontWeight: selected ? FontWeight.bold : FontWeight.w500,
          color: selected ? palette.selectedTabForeground : palette.unselectedTabForeground,
        ),
      ),
    );

    return GestureDetector(
      onTap: () => onChanged(segmentMode),
      behavior: HitTestBehavior.opaque,
      child: segment,
    );
  }
}

// ── 사진 파티 상세페이지의 Spotify 미리듣기 자동재생 ─────────────────────
// 목록 카드(VideoThumbnail)와 같은 FeedVideoManager(단일재생·글로벌 음소거
// 상태 공유)를 그대로 재사용한다. 상세페이지는 그 자체가 화면에 "보이는"
// 상태이므로 별도 가시성 감지 없이 진입 즉시 재생을 시작하고, 화면을
// 벗어나면(dispose) 즉시 정지·해제한다. 화면에 그리는 위젯은 없다(소리
// on/off는 전역 버튼 GlobalMuteFab 하나로만 제어).
class _SpotifyPreviewAudio extends StatefulWidget {
  final String previewUrl;
  const _SpotifyPreviewAudio({required this.previewUrl});

  @override
  State<_SpotifyPreviewAudio> createState() => _SpotifyPreviewAudioState();
}

class _SpotifyPreviewAudioState extends State<_SpotifyPreviewAudio> {
  final Object _playToken = Object();
  VideoPlayerController? _ctrl;
  bool _muted = true;

  @override
  void initState() {
    super.initState();
    FeedVideoManager.instance.mutedNotifier.addListener(_onGlobalMuteChanged);
    _init();
  }

  void _onGlobalMuteChanged() {
    final m = FeedVideoManager.instance.muted;
    if (m == _muted) return;
    setState(() => _muted = m);
    _ctrl?.setVolume(m ? 0 : 1);
  }

  Future<void> _init() async {
    _muted = FeedVideoManager.instance.muted;
    unawaited(FeedVideoManager.instance.loadMutePreference());

    try {
      final ctrl = VideoPlayerController.networkUrl(
        Uri.parse(widget.previewUrl),
      );
      await ctrl.initialize();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      ctrl.setLooping(true);
      ctrl.setVolume(_muted ? 0 : 1);
      _ctrl = ctrl;
      FeedVideoManager.instance.requestPlay(_playToken, _pauseSelf);
      ctrl.play();
    } catch (_) {
      // 미리듣기 로드 실패는 조용히 무시 — 상세페이지 자체는 정상 표시.
    }
  }

  void _pauseSelf() => _ctrl?.pause();

  @override
  void dispose() {
    FeedVideoManager.instance.mutedNotifier.removeListener(
      _onGlobalMuteChanged,
    );
    FeedVideoManager.instance.release(_playToken);
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// ── 위치 지도 ────────────────────────────────────────────────────────────
class _PartyLocationMap extends StatefulWidget {
  final double latitude;
  final double longitude;

  const _PartyLocationMap({
    super.key,
    required this.latitude,
    required this.longitude,
  });

  @override
  State<_PartyLocationMap> createState() => _PartyLocationMapState();
}

class _PartyLocationMapState extends State<_PartyLocationMap> {
  @override
  Widget build(BuildContext context) {
    return NaverMap(
      options: NaverMapViewOptions(
        initialCameraPosition: NCameraPosition(
          target: NLatLng(widget.latitude, widget.longitude),
          zoom: 15,
        ),
        scrollGesturesEnable: true,
        zoomGesturesEnable: true,
        tiltGesturesEnable: false,
        rotationGesturesEnable: false,
      ),
      onMapReady: (controller) async {
        await controller.addOverlay(
          NMarker(
            id: 'party_location',
            position: NLatLng(widget.latitude, widget.longitude),
          ),
        );
      },
    );
  }
}

// ── 요약 카드 대시보드 타일 ─────────────────────────────────────────────
// 날짜·장소·참여 인원·참가비를 2x2로 배치하는 "한눈에 보기" 카드에서
// 각 칸을 그리는 공통 조각. 핑크 원형 배지 안의 아이콘 + 위에 라벨,
// 아래에 값이라는 동일한 구조를 4칸 모두에 재사용해 대시보드다운 통일감을
// 준다.
class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final Widget value;
  final Widget? sub;

  const _StatTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.sub,
  });

  @override
  Widget build(BuildContext context) {
    // 아이콘 → 라벨 → 값 → 보조 정보 순으로 세로 중앙 정렬한다. 배경 원
    // 없이 아이콘 자체만 파스텔 컬러로 그리고(미니멀), 값/보조 정보는
    // 가운데 정렬만 하고 maxLines/ellipsis는 강제하지 않는다 — 실제
    // 데이터가 길면 그만큼 줄바꿈되고, 그 높이만큼 부모(IntrinsicHeight
    // Row)와 카드 전체가 자동으로 늘어난다.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 21, color: color),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF8A8A8A),
          ),
        ),
        const SizedBox(height: 4),
        DefaultTextStyle.merge(
          textAlign: TextAlign.center,
          style: _PartyDetailScreenState._tileValueStyle,
          child: value,
        ),
        if (sub != null) ...[
          const SizedBox(height: 3),
          sub!,
        ],
      ],
    );
  }
}

// 파티 유형(BBQ 파티/페스티벌 등) 칩 — "White Pearl Gloss Tag + Thin Double
// Pink Border". 로고의 흰색 글로스·핑크 테두리를 축소해서 옮긴 느낌으로,
// 강한 네온 핑크 테두리·핑크 글씨·넓은 Glow 대신 얇은 이중 테두리(바깥
// 연핑크 1px + 안쪽 반투명 흰색 1px)와 은은한 상단 광택만 쓴다.
class _PartyChip extends StatelessWidget {
  final String label;
  const _PartyChip(this.label);

  static const double _height = 37;
  static const double _emojiBoxWidth = 20;

  @override
  Widget build(BuildContext context) {
    // 라벨은 "🎭 코스프레"처럼 "이모지 + 공백 + 텍스트"로 저장돼 있다 —
    // 첫 공백 기준으로 나눠 이모지만 같은 폭의 SizedBox에 넣어야 이모지마다
    // 다른 원래 크기·무게에 상관없이 칩 정렬이 흔들리지 않는다.
    final spaceIdx = label.indexOf(' ');
    final emoji = spaceIdx > 0 ? label.substring(0, spaceIdx) : '';
    final text = spaceIdx > 0 ? label.substring(spaceIdx + 1) : label;

    return Container(
      height: _height,
      // 바깥쪽 연핑크 1px 링 — 안쪽 흰 캡슐을 1px 마진만큼 띄워서 그
      // 틈으로 이 색이 얇게 비치게 한다(굵은 Border 대신).
      decoration: BoxDecoration(
        color: PartyChuColors.border,
        borderRadius: BorderRadius.circular(_height / 2),
      ),
      child: Container(
        margin: const EdgeInsets.all(1),
        padding: const EdgeInsets.symmetric(horizontal: 15),
        decoration: BoxDecoration(
          // 안쪽 반투명 흰색 1px 링.
          border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1),
          color: Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(_height / 2 - 1),
          boxShadow: [
            // 아래쪽으로만 아주 약한 연핑크 그림자 — 살짝 떠 있는 정도만.
            BoxShadow(
              color: PartyChuColors.primaryLight.withValues(alpha: 0.13),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_height / 2 - 2),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 은은한 흰색 Gloss — 칩 상단부에만 살짝 얹어 유광 느낌.
              Positioned.fill(
                child: IgnorePointer(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: FractionallySizedBox(
                      heightFactor: 0.55,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(alpha: 0.9),
                              Colors.white.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (emoji.isNotEmpty) ...[
                    SizedBox(
                      width: _emojiBoxWidth,
                      child: Center(
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 17, height: 1),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(text, style: _labelStyle),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Pretendard/시스템 기본 폰트(제목용 SeoulHangang은 태그처럼 작은
  // 글자에서는 가독성이 떨어져 쓰지 않는다) + 진한 자주빛으로 확실히
  // 읽히게 한다.
  static const _labelStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: Color(0xFF66364D),
  );
}

// 상세 주소 옆 복사 버튼 — 누르면 실제로 클립보드에 주소를 복사하고
// 스낵바로 확인해준다.
class _CopyAddressButton extends StatelessWidget {
  final String address;
  const _CopyAddressButton({required this.address});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: address));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('주소가 복사되었습니다.'), duration: Duration(seconds: 2)),
        );
      },
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 2),
        child: Icon(Icons.copy_rounded, size: 15, color: Color(0xFFB06CFF)),
      ),
    );
  }
}

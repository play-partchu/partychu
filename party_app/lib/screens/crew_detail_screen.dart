import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:party_app/login.dart';
import 'package:party_app/models/crew_area.dart';
import 'package:party_app/screens/chat_room_screen.dart';
import 'package:party_app/screens/crew_register_screen.dart';
import 'package:party_app/services/chat_service.dart';
import 'package:party_app/utils/favorites_service.dart';
import 'package:party_app/models/report_reason.dart';
import 'package:party_app/widgets/user_safety_actions.dart';
import 'package:party_app/utils/format_utils.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/favorite_star_button.dart';
import 'package:party_app/widgets/login_required_dialog.dart';
import 'package:party_app/widgets/place_address_row.dart';
import 'package:party_app/widgets/web_frame.dart';

// ══════════════════════════════════════════════════════════════════
// 파티크루 상세 (구인/구직 공용)
//
// 목록 카드는 제목·역할·급여 정도만 보여주고 정작 본문(content)·모집 인원·
// 조건·주소는 어디에서도 볼 수 없었다(카드에 onTap 자체가 없었다). 구인/구직
// 문서 구조가 대부분 같으므로 화면을 둘로 나누지 않고, 유형에 따라 보이는
// 블록만 갈라 쓴다.
//   · 구직 전용: 프로필 사진(profileImageUrl)
//   · 구인 전용: 활동 주소(address/roadAddress/…), 자동 안내 문구(autoMessage)
// ══════════════════════════════════════════════════════════════════
class CrewDetailScreen extends StatelessWidget {
  final String docId;

  /// 목록 카드가 이미 들고 있던 문서 값 — 상세를 여는 첫 프레임부터 내용을
  /// 그려서 빈 화면이 깜빡이지 않게 한다. 실제 표시는 아래 스트림이 최신 값을
  /// 받는 즉시 그쪽으로 넘어간다(작성자가 수정하면 바로 반영된다).
  final Map<String, dynamic>? initialData;

  const CrewDetailScreen({super.key, required this.docId, this.initialData});

  static const _pink = Color(0xFFFF6FA0);
  static const _purple = Color(0xFF7C5CBF);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('crews')
          .doc(docId)
          .snapshots(),
      builder: (context, snap) {
        final live = snap.data?.data();
        // 문서가 삭제됐으면(존재하지 않음) 넘겨받은 값으로 계속 보여주지 않는다.
        final deleted = snap.hasData && snap.data?.exists == false;
        final data = live ?? (deleted ? null : initialData);

        if (data == null) {
          return Scaffold(
            backgroundColor: Colors.white,
            appBar: _appBar(context, null),
            body: Center(
              child: Text(
                deleted ? '삭제된 글이에요.' : '글을 불러오지 못했어요.',
                style: const TextStyle(fontSize: 14, color: Colors.black45),
              ),
            ),
          );
        }
        return Scaffold(
          backgroundColor: const Color(0xFFFAFAFC),
          appBar: _appBar(context, data),
          body: _body(context, data),
          bottomNavigationBar: _bottomBar(context, data),
        );
      },
    );
  }

  // ── 상단 바 ──────────────────────────────────────────────────────
  PreferredSizeWidget _appBar(BuildContext context, Map<String, dynamic>? d) {
    final isOwner =
        d != null &&
        UserSession.userId.isNotEmpty &&
        d['hostId'] == UserSession.userId;
    return AppBar(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black87,
      elevation: 0,
      title: const Text(
        '파티크루',
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
      actions: [
        // 신고·차단 — 내 글에서는 위젯이 스스로 아무것도 그리지 않는다.
        SafetyMenuButton(
          targetType: ReportTargetType.crew,
          targetId: docId,
          targetUserId: d?['hostId'] as String? ?? '',
          targetUserName: d?['hostName'] as String? ?? '',
          targetTitle: d?['title'] as String? ?? '',
        ),
        // 작성자에게만 보이는 수정 진입점 — 마이페이지와 같은 등록 화면(정본)의
        // 수정 모드를 그대로 연다.
        if (isOwner)
          IconButton(
            tooltip: '글 수정',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.push(
              context,
              webFramedRoute(
                (_) => CrewRegisterScreen.edit(docId: docId, sourceData: d),
              ),
            ),
          ),
        if (d != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FavoriteStarButton(
              itemType: FavoriteType.crew,
              itemId: docId,
              size: 22,
            ),
          ),
      ],
    );
  }

  // ── 본문 ─────────────────────────────────────────────────────────
  Widget _body(BuildContext context, Map<String, dynamic> d) {
    final crewType = d['crewType'] as String? ?? '';
    final isHiring = crewType == '구인';
    final accent = isHiring ? _pink : _purple;
    final title = d['title'] as String? ?? '';
    final content = d['content'] as String? ?? '';
    final hostName = d['hostName'] as String? ?? '';
    final isActive = d['isActive'] != false;
    final profileUrl = d['profileImageUrl'] as String? ?? '';

    final rolesRaw = d['roles'];
    final role = (rolesRaw is List && rolesRaw.isNotEmpty)
        ? rolesRaw.cast<String>().join(' · ')
        : (d['role'] as String? ?? '');
    // "서울 강남구 · 부산 전체" — 광역만 저장돼 있던 옛 글은 "서울 전체"로 읽힌다.
    final region = CrewArea.labelOfCrewData(d);

    final recruitCount = (d['recruitCount'] as num?)?.toInt() ?? 0;
    final beginner = d['beginnerFriendly'] as bool? ?? false;
    final experienced = d['experiencedPreferred'] as bool? ?? false;

    final address = PlaceAddressRow.joinAddress(
      (d['roadAddress'] as String?)?.isNotEmpty == true
          ? d['roadAddress'] as String
          : d['address'] as String? ?? '',
      d['detailAddress'] as String?,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _card(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 프로필 사진은 구직 글에만 저장된다 — 없으면 자리 자체를
              // 비워 제목이 왼쪽 끝에서 시작하게 한다.
              if (profileUrl.isNotEmpty) ...[
                crewProfileAvatar(profileUrl, size: 64),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _badge(
                          crewType,
                          accent,
                          isHiring
                              ? const Color(0xFFFFF0F5)
                              : const Color(0xFFF3EFFA),
                        ),
                        _badge(
                          isActive ? '모집 중' : '마감',
                          isActive ? const Color(0xFF2E7D32) : Colors.black45,
                          isActive
                              ? const Color(0xFFF0FFF4)
                              : const Color(0xFFF5F5F7),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'SeoulHangang',
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        shadows: [
                          Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
                          Shadow(
                            color: Colors.black87,
                            offset: Offset(-0.3, 0),
                          ),
                          Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
                          Shadow(
                            color: Colors.black87,
                            offset: Offset(0, -0.3),
                          ),
                        ],
                      ),
                    ),
                    if (hostName.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        hostName,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black45,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow(Icons.event_outlined, '모집 기간', crewPeriodLabel(d)),
              if (crewTimeLabel(d) != null)
                _infoRow(Icons.access_time, '활동 시간', crewTimeLabel(d)!),
              if (role.isNotEmpty) _infoRow(Icons.work_outline, '역할', role),
              if (region.isNotEmpty)
                _infoRow(Icons.location_on_outlined, '지역', region),
              _infoRow(
                Icons.payments_outlined,
                '급여',
                crewPayLabel(d),
                valueColor: _pink,
              ),
              if (recruitCount > 0)
                _infoRow(Icons.groups_outlined, '모집 인원', '$recruitCount명'),
              if (beginner || experienced)
                _infoRow(
                  Icons.verified_outlined,
                  '조건',
                  [
                    if (beginner) '초보 환영',
                    if (experienced) '경력자 우대',
                  ].join(' · '),
                ),
            ],
          ),
        ),
        if (content.isNotEmpty) ...[
          const SizedBox(height: 12),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '상세 내용',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  content,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.7,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
        // 주소는 구인 글에만 저장된다(구직은 지역만 고른다).
        if (address.isNotEmpty) ...[
          const SizedBox(height: 12),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '활동 장소',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                PlaceAddressRow(
                  address: address,
                  latitude: (d['latitude'] as num?)?.toDouble(),
                  longitude: (d['longitude'] as num?)?.toDouble(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── 하단 문의 바 ─────────────────────────────────────────────────
  Widget? _bottomBar(BuildContext context, Map<String, dynamic> d) {
    final hostId = d['hostId'] as String? ?? '';
    if (hostId.isEmpty) return null;
    // 내 글에는 문의 버튼을 띄우지 않는다(자기 자신과의 채팅방이 생긴다).
    if (hostId == UserSession.userId) return null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          height: 50,
          child: ElevatedButton.icon(
            onPressed: () => _openChat(context, d),
            style: ElevatedButton.styleFrom(
              backgroundColor: _pink,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            label: const Text(
              '문의하기',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openChat(BuildContext context, Map<String, dynamic> d) async {
    if (UserSession.userId.isEmpty) {
      final shouldLogin = await showLoginRequiredDialog(
        context,
        message: '문의하려면 로그인이 필요합니다.',
      );
      if (!shouldLogin || !context.mounted) return;
      await Navigator.push(context, webFramedRoute((_) => LoginPage()));
      return;
    }

    final hostId = d['hostId'] as String? ?? '';
    final hostName = d['hostName'] as String? ?? '작성자';
    final title = d['title'] as String? ?? '파티크루';
    try {
      final roomId = await ChatService.getOrCreateRoom(
        hostId: hostId,
        hostName: hostName,
        guestId: UserSession.userId,
        guestName: UserSession.displayName,
        relatedType: 'crew',
        relatedId: docId,
        relatedTitle: title,
      );

      // 구인 글의 자동 안내 문구 — 파티샵/장소와 같은 방식으로 예약해 두면
      // 채팅방에 들어가는 순간 작성자 이름으로 먼저 발송된다.
      //
      // 문구가 있는지, 이미 말이 오간 방인지(그런 방에 또 예약하면 문의 버튼을
      // 누를 때마다 같은 안내가 쌓인다)는 서버가 판단한다 — 앱은 방 번호만
      // 넘긴다(ChatService.scheduleAutoMessage 주석 참고).
      await ChatService.scheduleAutoMessage(roomId: roomId);

      if (!context.mounted) return;
      await Navigator.push(
        context,
        webFramedRoute(
          (_) => ChatRoomScreen(
            roomId: roomId,
            otherName: hostName,
            relatedTitle: title,
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('채팅방을 열지 못했어요: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ── 조각들 ───────────────────────────────────────────────────────
  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
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
    child: child,
  );

  Widget _badge(String label, Color textColor, Color bgColor) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: textColor,
      ),
    ),
  );

  Widget _infoRow(
    IconData icon,
    String label,
    String value, {
    Color valueColor = Colors.black87,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: Colors.black38),
        const SizedBox(width: 8),
        SizedBox(
          width: 62,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Colors.black45),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ),
      ],
    ),
  );
}

// ══════════════════════════════════════════════════════════════════
// 목록 카드와 상세가 함께 쓰는 표시 규칙
// (같은 값을 두 벌로 계산하면 라벨이 갈라지므로 여기 한 곳에 둔다)
// ══════════════════════════════════════════════════════════════════

/// 원형 프로필 사진 — 실패하면 기본 사람 아이콘으로 떨어진다.
///
/// URL이 죽었거나(호스팅 만료) 네트워크가 끊겼을 때 회색 깨진 이미지가
/// 그대로 남지 않게, [Image.network]의 errorBuilder에서 아이콘으로 바꾼다.
Widget crewProfileAvatar(String url, {double size = 44}) {
  final placeholder = Container(
    width: size,
    height: size,
    color: const Color(0xFFF3F4F6),
    alignment: Alignment.center,
    child: Icon(Icons.person, size: size * 0.55, color: Colors.black26),
  );
  return ClipOval(
    child: SizedBox(
      width: size,
      height: size,
      child: url.isEmpty
          ? placeholder
          : Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, e, st) => placeholder,
            ),
    ),
  );
}

/// "3.05 ~ 3.20" / "항시 모집" 같은 모집 기간 라벨.
String crewPeriodLabel(Map<String, dynamic> d) {
  final isHiring = (d['crewType'] as String? ?? '') == '구인';
  if ((d['recruitType'] as String? ?? '항시') != '날짜지정') {
    return '항시 ${isHiring ? '모집' : '구직'}';
  }
  final start = (d['startDate'] as Timestamp?)?.toDate();
  final end = (d['endDate'] as Timestamp?)?.toDate();
  String fmt(DateTime dt) => '${dt.month}.${dt.day.toString().padLeft(2, '0')}';
  if (start != null && end != null) return '${fmt(start)} ~ ${fmt(end)}';
  if (start != null) return '${fmt(start)} ~';
  return '날짜 지정';
}

/// "오후 6:00 ~ 오후 11:00" 같은 활동 시간 라벨 — 시간이 없으면 null.
String? crewTimeLabel(Map<String, dynamic> d) {
  final start = d['startTime'] as String?;
  final end = d['endTime'] as String?;
  if (start == null) return null;
  String fmt(String t) {
    final parts = t.split(':');
    if (parts.length != 2) return t;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts[1];
    if (h == 0) return '오전 12:$m';
    if (h < 12) return '오전 $h:$m';
    if (h == 12) return '오후 12:$m';
    return '오후 ${h - 12}:$m';
  }

  return end != null ? '${fmt(start)} ~ ${fmt(end)}' : fmt(start);
}

/// "시급 1.2만원" / "급여 협의" 같은 급여 라벨.
String crewPayLabel(Map<String, dynamic> d) {
  final payType = d['payType'] as String? ?? '협의';
  final payAmount = (d['payAmount'] as num?)?.toInt() ?? 0;
  if (payType == '협의') return '급여 협의';
  return payAmount > 0 ? '$payType ${formatAmount(payAmount)}' : payType;
}

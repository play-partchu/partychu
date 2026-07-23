import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:party_app/screens/party_register_screen.dart';
import 'package:party_app/screens/party_place_combo_register_screen.dart';
import 'package:party_app/screens/place_party_combo_register_screen.dart';
import 'package:party_app/screens/place_register_screen.dart';
import 'package:party_app/screens/crew_register_screen.dart';
import 'package:party_app/screens/party_market_register_screen.dart';
import 'package:party_app/screens/event_register_screen.dart';

class RegisterTypeScreen extends StatefulWidget {
  const RegisterTypeScreen({super.key});

  @override
  State<RegisterTypeScreen> createState() => _RegisterTypeScreenState();
}

class _RegisterTypeScreenState extends State<RegisterTypeScreen> {
  bool _isCheckingParty = false;

  // 파티 등록 가능 여부 확인 후 화면 이동
  // Source.server 를 사용해 로컬 캐시를 우회하고 최신 데이터로 판단
  Future<void> _checkAndGoToPartyRegister() async {
    if (_isCheckingParty) return;
    setState(() => _isCheckingParty = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        // parties 컬렉션만 기준으로 계산 (places/placeRooms 제외)
        final snap = await FirebaseFirestore.instance
            .collection('parties')
            .where('hostId', isEqualTo: uid)
            .get(const GetOptions(source: Source.server)); // 캐시 우회

        // isDeleted 필드가 없는 기존 문서는 삭제되지 않은 것으로 간주
        final count = snap.docs.where((d) {
          final data = d.data();
          return data['isDeleted'] != true && data['status'] != 'deleted';
        }).length;

        if (count >= 10) {
          if (!mounted) return;
          await showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                '등록 불가',
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
              content: const Text(
                '등록 가능한 파티는 최대 10개입니다.\n마이 > 지난파티에서 재등록 또는 삭제 후 이용해 주세요.',
                style: TextStyle(height: 1.5),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    '확인',
                    style: TextStyle(color: Color(0xFFFF6FA0)),
                  ),
                ),
              ],
            ),
          );
          return;
        }
      }

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PartyRegisterScreen()),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('오류가 발생했습니다: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCheckingParty = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F8),
      appBar: AppBar(
        title: const Text(
          '등록하기',
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
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () => _showRegisterHelpSheet(context),
            icon: Container(
              width: 26,
              height: 26,
              decoration: const BoxDecoration(
                color: Color(0xFFFFE3EE),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.question_mark_rounded,
                size: 15,
                color: Color(0xFFFF6FA0),
              ),
            ),
            tooltip: '등록 유형 안내',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '어떤 걸 등록할까요?',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              '원하는 유형을 선택해주세요',
              style: TextStyle(fontSize: 14, color: Colors.black45),
            ),
            const SizedBox(height: 32),
            _TypeCard(
              emoji: '🎉',
              title: '파티 등록',
              description: '파티를 열고 참가자를 모집해요',
              accentColor: const Color(0xFFFF6FA0),
              bgColor: const Color(0xFFFFF0F5),
              isLoading: _isCheckingParty,
              onTap: _checkAndGoToPartyRegister,
            ),
            const SizedBox(height: 16),
            _TypeCard(
              emoji: '🥂',
              title: '플레이스 등록',
              description: '혼술바·이벤트·핫플 등 매장/장소를 올려요',
              accentColor: const Color(0xFFFF6FA0),
              bgColor: const Color(0xFFFFF0F5),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EventRegisterScreen()),
              ),
            ),
            const SizedBox(height: 16),
            _TypeCard(
              emoji: '🍷',
              title: '플레이스+파티 등록',
              description: '매장을 운영하며 파티도 함께 열어요',
              accentColor: const Color(0xFFFF6FA0),
              bgColor: const Color(0xFFFFF0F5),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PlacePartyComboRegisterScreen(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _TypeCard(
              emoji: '📍',
              title: '파티 장소 등록',
              description: '대여 가능한 파티 공간을 등록해요',
              accentColor: const Color(0xFF7C5CBF),
              bgColor: const Color(0xFFF3EFFA),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PlaceRegisterScreen()),
              ),
            ),
            const SizedBox(height: 16),
            _TypeCard(
              emoji: '🏨',
              title: '숙박+파티 등록',
              description: '숙박과 파티를 한 번에 등록해요',
              accentColor: const Color(0xFF7C5CBF),
              bgColor: const Color(0xFFF3EFFA),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PartyPlaceComboRegisterScreen(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _TypeCard(
              emoji: '🛍️',
              title: '파티샵 등록',
              description: '파티샵을 등록하고 상품을 판매해요',
              accentColor: const Color(0xFFFF8C42),
              bgColor: const Color(0xFFFFF4EC),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PartyMarketRegisterScreen(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _TypeCard(
              emoji: '🎤',
              title: '파티크루 글 등록',
              description: '구인·구직 글을 올리고 파티크루를 찾아요',
              accentColor: const Color(0xFFFF6FA0),
              bgColor: const Color(0xFFFFF0F5),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CrewRegisterScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String description;
  final Color accentColor;
  final Color bgColor;
  final VoidCallback? onTap;
  final bool isLoading;

  const _TypeCard({
    required this.emoji,
    required this.title,
    required this.description,
    required this.accentColor,
    required this.bgColor,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE8EBF2)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: isLoading
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: accentColor,
                        ),
                      )
                    : Text(emoji, style: const TextStyle(fontSize: 28)),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: isLoading ? Colors.black38 : accentColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isLoading ? '확인 중...' : description,
                    style: const TextStyle(fontSize: 13, color: Colors.black45),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: isLoading ? Colors.black26 : accentColor,
            ),
          ],
        ),
      ),
    );
  }
}

// ── 등록 유형 안내 BottomSheet ────────────────────────────────────────────
// 위 6개 등록 카드가 서로 어떻게 다른지 헷갈려하는 이용자를 위한 도움말 —
// AppBar의 '?' 버튼에서만 진입하며, 실제 등록 로직에는 관여하지 않는다.

void _showRegisterHelpSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFFFF7FA),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFFFD6E4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '등록 유형 안내',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close, color: Colors.black45),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: const [
                  _HelpTypeCard(
                    emoji: '🎉',
                    title: '파티 등록',
                    description: '개인 또는 모임 호스트가 파티를 직접 모집하는 경우 이용해주세요.',
                    examples: ['번개 모임', '생일파티', '술모임', '클럽모임', '캠핑모임'],
                    accentColor: Color(0xFFFF6FA0),
                    bgColor: Color(0xFFFFF0F5),
                  ),
                  SizedBox(height: 14),
                  _HelpTypeCard(
                    emoji: '🍷',
                    title: '플레이스+파티 등록',
                    description: '매장을 운영하면서 파티나 이벤트도 함께 운영하는 사장님들을 위한 등록입니다.',
                    examples: ['혼술바', '술집', '펍', '와인바', '라운지', '클럽', '카페'],
                    note: '매장 정보와 파티를 함께 등록하여 손님을 모집할 수 있습니다.',
                    accentColor: Color(0xFFFF6FA0),
                    bgColor: Color(0xFFFFF0F5),
                  ),
                  SizedBox(height: 14),
                  _HelpTypeCard(
                    emoji: '🏨',
                    title: '숙박+파티 등록',
                    description:
                        '숙박이 가능한 업장을 운영하면서 파티도 함께 진행하는 사장님들을 위한 등록입니다.',
                    examples: ['게스트하우스', '호텔', '펜션', '풀빌라'],
                    note: '숙박 정보와 파티를 함께 등록할 수 있습니다.',
                    accentColor: Color(0xFF7C5CBF),
                    bgColor: Color(0xFFF3EFFA),
                  ),
                  SizedBox(height: 14),
                  _HelpTypeCard(
                    emoji: '📍',
                    title: '파티 장소 등록',
                    description: '파티를 개최할 수 있는 공간을 시간 단위로 대여하는 경우 이용해주세요.',
                    examples: ['파티룸', '스튜디오', '루프탑', '공연장', '대관'],
                    accentColor: Color(0xFF7C5CBF),
                    bgColor: Color(0xFFF3EFFA),
                  ),
                  SizedBox(height: 14),
                  _HelpTypeCard(
                    emoji: '🛍️',
                    title: '파티샵 등록',
                    description: '파티와 관련된 상품이나 서비스를 판매하는 경우 이용해주세요.',
                    examples: ['케이크', '풍선', '파티용품', '꽃', '선물', '이벤트 소품'],
                    accentColor: Color(0xFFFF8C42),
                    bgColor: Color(0xFFFFF4EC),
                  ),
                  SizedBox(height: 14),
                  _HelpTypeCard(
                    emoji: '🎤',
                    title: '파티크루 등록',
                    description: '파티 운영을 함께할 스태프를 모집하거나 파티 관련 구직을 하는 공간입니다.',
                    examples: ['DJ', 'MC', '사진작가', '바텐더', '스태프', '공연팀'],
                    accentColor: Color(0xFFFF6FA0),
                    bgColor: Color(0xFFFFF0F5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _HelpTypeCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String description;
  final List<String> examples;
  final String? note;
  final Color accentColor;
  final Color bgColor;

  const _HelpTypeCard({
    required this.emoji,
    required this.title,
    required this.description,
    required this.examples,
    this.note,
    required this.accentColor,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accentColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 17)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black87,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: examples
                .map(
                  (e) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      e,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: accentColor,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          if (note != null) ...[
            const SizedBox(height: 10),
            Text(
              note!,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black45,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

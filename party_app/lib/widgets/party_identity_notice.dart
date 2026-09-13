import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 파티 신청 본인확인 안내 — 게스트용과 호스트용 한 쌍.
//
// 두 안내는 **같은 정책의 양면**이다. 게스트에게는 "신청한 본인만 참여할 수
// 있다"고 미리 말하고, 호스트에게는 "입장할 때 그것을 확인해달라"고 말한다.
// 문구가 갈리면 현장에서 "그런 말 못 들었다"가 나오므로 한 파일에 붙여 둔다.
//
// 왜 위젯인가: 안내가 들어갈 자리가 화면마다 다르고(상세의 카드, 신청자 목록
// 머리말) 앞으로 더 늘 수 있는데, 문구를 화면마다 적어 두면 한쪽만 고쳐진다.
// ─────────────────────────────────────────────────────────────────────────────

/// 게스트 — 파티 상세의 신청 영역에 붙는 안내.
///
/// **1인 1신청이라는 사실을 말이 아니라 규칙으로 못 박는 자리다.** 인원수를
/// 고르는 칸을 두지 않는 이유이기도 하다 — 동행인이 있으면 각자 자기 계정으로
/// 신청해야 신분증 대조가 성립한다.
class PartyApplyIdentityNotice extends StatelessWidget {
  /// 화면마다 카드 바깥 여백이 달라 호출부가 넘긴다.
  final EdgeInsets margin;

  const PartyApplyIdentityNotice({
    super.key,
    this.margin = const EdgeInsets.only(top: 16),
  });

  @override
  Widget build(BuildContext context) {
    return _NoticeCard(
      margin: margin,
      icon: Icons.verified_user_outlined,
      accent: const Color(0xFF4F46E5),
      background: const Color(0xFFF3F4FF),
      title: '본인확인이 완료된 회원만 신청할 수 있어요',
      lines: const [
        '신청한 본인만 참여할 수 있으며, 신청 권한을 다른 사람에게 양도하거나 '
            '대신 입장할 수 없습니다.',
        '동행인이 있는 경우 각자 본인 계정으로 신청해주세요.',
      ],
    );
  }
}

/// 호스트 — 신청자 관리·입장 확인 화면 머리말에 붙는 안내.
class PartyHostIdentityCheckNotice extends StatelessWidget {
  final EdgeInsets margin;

  const PartyHostIdentityCheckNotice({
    super.key,
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return _NoticeCard(
      margin: margin,
      icon: Icons.badge_outlined,
      accent: const Color(0xFF9A3412),
      background: const Color(0xFFFFF7ED),
      title: '안전한 파티 운영을 위해 입장 시 신청자 본인 여부를 확인해주세요',
      lines: const [
        '신청자 목록의 본인확인 실명과 참석자의 신분증상 이름이 일치하는지 '
            '확인해주세요.',
        // 게스트 안내와 짝을 이루는 줄 — 현장에서 "대신 왔다"는 요청을 받았을 때
        // 호스트가 근거로 삼을 문장이다.
        '신청자와 실제 참석자가 다르면 입장할 수 없습니다. 대리입장·양도는 '
            '허용되지 않아요.',
      ],
    );
  }
}

/// 두 안내가 공유하는 껍데기 — 제목 한 줄 + 점 목록.
class _NoticeCard extends StatelessWidget {
  final EdgeInsets margin;
  final IconData icon;
  final Color accent;
  final Color background;
  final String title;
  final List<String> lines;

  const _NoticeCard({
    required this.margin,
    required this.icon,
    required this.accent,
    required this.background,
    required this.title,
    required this.lines,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: margin,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: accent,
                    height: 1.4,
                  ),
                ),
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 점은 글자와 같은 줄높이에 맞춰 살짝 내려 찍는다.
                        Padding(
                          padding: const EdgeInsets.only(top: 6, right: 6),
                          child: Container(
                            width: 3,
                            height: 3,
                            decoration: BoxDecoration(
                              color: Colors.black38,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            line,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: Colors.black87,
                              height: 1.5,
                            ),
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
}

/// 신청자 한 줄에 붙는 **본인확인 상태 배지**.
///
/// 호스트가 입장 확인 때 "이 사람은 본인확인을 마쳤는가"를 목록에서 바로
/// 읽을 수 있어야 해서, 미확인일 때만 알리던 예전 배지를 양쪽 다 말하도록
/// 바꿨다 — 배지가 없는 줄이 "확인했다"인지 "아직 안 봤다"인지 알 수 없으면
/// 근거로 쓸 수 없다.
class IdentityVerifiedBadge extends StatelessWidget {
  final bool verified;

  const IdentityVerifiedBadge({super.key, required this.verified});

  @override
  Widget build(BuildContext context) {
    final accent = verified ? const Color(0xFF1D8F5F) : Colors.black54;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: verified
            ? const Color(0xFFEAFBF2)
            : Colors.grey.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            verified ? Icons.verified_rounded : Icons.help_outline_rounded,
            size: 12,
            color: accent,
          ),
          const SizedBox(width: 3),
          Text(
            verified ? '본인확인 완료' : '본인확인 미완료',
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.bold,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// 신청자 한 줄 아래에 붙는 **본인확인 실명** 줄.
///
/// 닉네임과 섞이지 않게 라벨을 붙여 그린다 — 입장 확인 때 대조할 값이
/// `냥냥이(홍길동)` 안의 괄호가 아니라 이 줄 하나로 분명해야 한다.
class VerifiedNameLine extends StatelessWidget {
  final String? verifiedName;

  const VerifiedNameLine({super.key, required this.verifiedName});

  @override
  Widget build(BuildContext context) {
    final name = verifiedName;
    if (name == null || name.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        const Icon(Icons.badge_outlined, size: 13, color: Color(0xFF1D8F5F)),
        const SizedBox(width: 5),
        const Text(
          '본인확인 실명',
          style: TextStyle(fontSize: 12, color: Colors.black45),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1B5E20),
            ),
          ),
        ),
      ],
    );
  }
}

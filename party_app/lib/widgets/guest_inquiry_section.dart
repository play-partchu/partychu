import 'package:flutter/material.dart';

import 'package:party_app/models/listing_inquiry.dart';

/// 등록·수정 화면의 **"게스트 문의 받기"** 설정 카드.
///
/// 파티·플레이스·장소대여 세 등록 화면이 **같은 위젯 하나**를 쓴다. 문구를
/// 화면마다 적어 두면 한쪽만 고쳐지고, 그러면 같은 설정인데 화면마다 다른
/// 말을 하게 된다(안내가 셋으로 갈라지면 호스트는 어느 쪽이 맞는지 알 수 없다).
///
/// 값 자체는 이 위젯이 들고 있지 않다 — 호출부가 [enabled]를 주고 [onChanged]로
/// 돌려받아 저장 payload에 [ListingInquiry.toMap]으로 넣는다(다른 섹션들과 같은
/// 규약이다).
///
/// ── 문구를 두 덩이로 나눈 이유 ──────────────────────────────────────────
/// 위 카드는 **왜 켜두면 좋은지**(권장), 아래 카드는 **켜면 무슨 일이
/// 일어나는지**(설명)다. 하나로 합치면 권유가 설명에 묻힌다.
///
/// 권장 문구에는 "신청률이 올라갑니다"·"노출이 증가합니다"처럼 **수치로
/// 보장할 수 없는 말을 쓰지 않는다.** 그런 표현은 호스트에게 사실상 약속이
/// 되고, 실제로 그렇지 않았을 때 서비스에 대한 신뢰를 깎는다. '연결될 수
/// 있어요'·'도움이 될 수 있어요' 정도가 우리가 정직하게 말할 수 있는 선이다.
class GuestInquirySection extends StatelessWidget {
  /// 지금 켜져 있는가. 등록 화면의 기본값은 ON이다
  /// ([ListingInquiry.defaultEnabled]).
  final bool enabled;

  final ValueChanged<bool> onChanged;

  /// "문의 전 안내" 입력 컨트롤러. ON일 때만 입력란이 보인다.
  ///
  /// null이면 안내문 입력을 아예 그리지 않는다 — 아직 이 값을 저장하지 않는
  /// 호출부가 남아 있어도 기존처럼 동작하게 하기 위한 것이다.
  final TextEditingController? guideController;

  /// OFF일 때 카드 안에 덧붙일 내용 — 지금은 **이벤트 화면만** 쓴다.
  ///
  /// 이벤트는 문의를 끈 자리에 "그럼 어떻게 하면 되는지"를 호스트가 골라
  /// 보여준다([EventInquiryNotice]). 파티·플레이스·장소대여는 이 값을 주지
  /// 않으므로 **화면도 저장 내용도 예전 그대로**다 — 공용 카드에 도메인
  /// 분기를 넣지 않기 위해 슬롯만 열어 둔다.
  final Widget? offExtra;

  /// 지금은 끌 수 없다는 사실과 그 이유 — 값이 있으면 스위치가 잠기고 이
  /// 문장이 아래에 붙는다.
  ///
  /// 다른 설정이 문의를 **필요로 할 때**만 쓴다. 지금은 매장 이벤트의 '사전
  /// 예약 필요' 하나다 — 예약 기능이 따로 없어 문의가 예약을 잡는 유일한
  /// 길이라, 그 상태에서 문의를 끄면 손님이 갈 곳이 없어진다. 잠긴 이유를
  /// 말없이 감추지 않고 카드 안에서 밝힌다(호스트는 왜 못 끄는지 알아야
  /// 한다). null이면 예전과 똑같이 자유롭게 켜고 끈다.
  final String? lockedNote;

  const GuestInquirySection({
    super.key,
    required this.enabled,
    required this.onChanged,
    this.guideController,
    this.offExtra,
    this.lockedNote,
  });

  static const _accent = Color(0xFF4F46E5);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _accent.withValues(alpha: 0.25), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('💬', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '게스트 문의 받기',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              // 꺼져 있을 때만 'ON 권장'을 띄운다 — 이미 켠 호스트에게 계속
              // 권하는 것은 잔소리가 된다.
              if (!enabled) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'ON 권장',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _accent,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Switch(
                value: enabled,
                activeThumbColor: _accent,
                // 잠겨 있으면 누를 수 없다 — 눌리는데 값이 안 바뀌면
                // 고장으로 읽힌다.
                onChanged: lockedNote == null ? onChanged : null,
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'ON으로 설정하면 신청·예약 전에도 게스트가 상세페이지의 문의하기를 통해 '
            '호스트에게 파티츄 채팅으로 문의할 수 있습니다.',
            style: TextStyle(fontSize: 12, height: 1.45, color: Colors.black54),
          ),
          if (lockedNote != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 15,
                  color: _accent,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    lockedNote!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                      color: _accent,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          const _InquiryNoteCard(
            emoji: '✨',
            title: '문의를 열어두면 더 많은 게스트와 연결될 수 있어요',
            body:
                '신청·예약 전에 궁금한 점을 바로 물어볼 수 있어 게스트의 참여 결정에 '
                '도움이 될 수 있어요. 문의가 오면 파티츄 알림으로 바로 알려드려요.',
            background: Color(0xFFF3F4FF),
            accent: _accent,
          ),
          // 문의 전 안내 — ON일 때만 의미가 있다. OFF 상태에서 입력란을
          // 남겨 두면 "적어도 아무도 못 보는 글"이 된다.
          if (enabled && guideController != null) ...[
            const SizedBox(height: 14),
            _InquiryGuideField(controller: guideController!),
          ],
          const SizedBox(height: 8),
          const _InquiryNoteCard(
            emoji: '💌',
            title: '문의부터 신청까지 파티츄에서 한 번에',
            body:
                '게스트의 궁금한 점을 파티츄 채팅으로 바로 받아보세요. 새 문의는 '
                '알림으로 알려드리고, 게스트는 상세 페이지를 보면서 간편하게 문의할 '
                '수 있어요.\n'
                '문의 및 신청 과정의 안전한 관리를 위해 외부 링크 대신 파티츄 채팅을 '
                '이용해 주세요.',
            background: Color(0xFFFFF4F8),
            accent: Color(0xFFD9407A),
          ),
          // 끈 상태에서 무슨 일이 벌어지는지도 같은 카드 안에서 말해 준다 —
          // 저장하고 상세를 열어 봐야 알게 되면 늦다.
          if (!enabled) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: Colors.black45,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    '지금은 상세 페이지에 문의하기 버튼이 나오지 않고, 문의를 받지 '
                    '않는다는 안내가 대신 표시돼요. 이미 주고받은 문의 대화는 그대로 '
                    '남아 계속 이어갈 수 있어요.',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.45,
                      color: Colors.black45,
                    ),
                  ),
                ),
              ],
            ),
            if (offExtra != null) ...[
              const SizedBox(height: 14),
              offExtra!,
            ],
          ],
        ],
      ),
    );
  }
}

/// "문의 전 안내" 입력란 — 남은 글자 수를 함께 보여준다.
///
/// 게스트가 문의하기를 누르면 채팅방에 들어가기 전에 이 글을 먼저 본다.
/// 비워 두면 안내 없이 바로 채팅으로 연결된다(빈 팝업을 띄우지 않는다).
class _InquiryGuideField extends StatefulWidget {
  final TextEditingController controller;
  const _InquiryGuideField({required this.controller});

  @override
  State<_InquiryGuideField> createState() => _InquiryGuideFieldState();
}

class _InquiryGuideFieldState extends State<_InquiryGuideField> {
  static const _accent = Color(0xFF4F46E5);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    // 컨트롤러 자체는 호출부(등록 화면)가 만들고 지운다 — 여기서는 리스너만 뗀다.
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final used = widget.controller.text.characters.length;
    final left = ListingInquiry.maxGuideLength - used;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '문의 전 안내 (선택)',
          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        const Text(
          '게스트가 문의하기를 누르면 채팅을 시작하기 전에 이 안내를 먼저 봅니다. '
          '비워 두면 안내 없이 바로 채팅으로 연결돼요.',
          style: TextStyle(fontSize: 11.5, height: 1.45, color: Colors.black45),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: widget.controller,
          maxLines: 4,
          minLines: 3,
          maxLength: ListingInquiry.maxGuideLength,
          // 기본 카운터는 '12/300'만 보여준다 — 아래에서 남은 글자로 직접 그린다.
          buildCounter:
              (_, {required currentLength, required isFocused, maxLength}) =>
                  null,
          decoration: InputDecoration(
            // 예시를 두 줄로 보여준다 — 이 칸이 받는 것이 "문의 조건"과
            // "적어 달라는 것" **두 가지**임을 한눈에 알려야 한다.
            // 'ㅇㅇ'은 호스트가 자기 상황에 맞게 갈아 끼우라는 자리다
            // (예약 관련 문의 / 대관 문의 …).
            hintText:
                '예: 채팅 문의는 ㅇㅇ만 가능합니다.\n'
                '예: 예약 가능한 날짜, 시간, 인원수를 적어주세요.',
            // 힌트는 기본값으로도 여러 줄이 그려지지만, 두 줄이라는 것을
            // 여기서 못 박아 둔다(입력칸은 minLines 3이라 자리도 충분하다).
            hintMaxLines: 2,
            hintStyle: const TextStyle(color: Colors.black38, fontSize: 12.5),
            filled: true,
            fillColor: const Color(0xFFFAFAFF),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 13,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _accent.withValues(alpha: 0.25)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _accent.withValues(alpha: 0.25)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _accent, width: 1.4),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            left >= 0 ? '$left자 남음' : '${-left}자 초과',
            style: TextStyle(
              fontSize: 11.5,
              color: left >= 0 ? Colors.black45 : Colors.redAccent,
            ),
          ),
        ),
      ],
    );
  }
}

/// 제목 한 줄 + 본문 한 덩이짜리 안내 카드.
class _InquiryNoteCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String body;
  final Color background;
  final Color accent;

  const _InquiryNoteCard({
    required this.emoji,
    required this.title,
    required this.body,
    required this.background,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: accent,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            body,
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

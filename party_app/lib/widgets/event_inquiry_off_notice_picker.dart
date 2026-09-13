// ─────────────────────────────────────────────────────────────────────────────
// 이벤트 문의를 껐을 때 게스트에게 대신 보여줄 안내를 고르는 칸.
//
// 공용 문의 카드([GuestInquirySection])의 `offExtra` 슬롯에 끼워 쓴다 —
// 카드 자체에 도메인 분기를 넣지 않기 위해서다. 파티·플레이스·장소대여는
// 이 위젯을 주지 않으므로 그 화면들의 모양도 저장 내용도 그대로다.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import 'package:party_app/models/event_inquiry_notice.dart';

class EventInquiryOffNoticePicker extends StatelessWidget {
  const EventInquiryOffNoticePicker({
    super.key,
    required this.notice,
    required this.onNoticeChanged,
    required this.textController,
  });

  final EventInquiryNotice notice;
  final ValueChanged<EventInquiryNotice> onNoticeChanged;

  /// [EventInquiryNotice.custom]일 때만 쓰이는 직접 입력 문구.
  final TextEditingController textController;

  static const _accent = Color(0xFF4F46E5);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '대신 이렇게 안내할게요',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '문의 버튼 자리에 아래 문구가 표시돼요.',
          style: TextStyle(fontSize: 11.5, color: Colors.black45),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final n in EventInquiryNotice.values)
              _Choice(
                label: n.label,
                selected: n == notice,
                onTap: () => onNoticeChanged(n),
              ),
          ],
        ),
        // 직접 입력을 골랐을 때만 칸이 열린다. 프리셋을 고른 채 입력란을
        // 남겨 두면 "적어도 아무도 못 보는 글"이 된다.
        if (notice == EventInquiryNotice.custom) ...[
          const SizedBox(height: 10),
          TextField(
            controller: textController,
            maxLength: EventInquiryNoticeFields.maxTextLength,
            maxLines: 2,
            minLines: 1,
            style: const TextStyle(fontSize: 13, height: 1.4),
            decoration: InputDecoration(
              hintText: '예) 예약은 전화로만 받아요',
              hintStyle: const TextStyle(
                fontSize: 13,
                color: Colors.black26,
              ),
              counterText: '',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              filled: true,
              fillColor: const Color(0xFFF7F7FA),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _accent, width: 1.2),
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '비워 두면 안내 없이 문의 버튼만 사라져요.',
            style: TextStyle(fontSize: 11, color: Colors.black38),
          ),
        ],
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: selected
            ? EventInquiryOffNoticePicker._accent.withValues(alpha: 0.10)
            : const Color(0xFFF7F7FA),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected
              ? EventInquiryOffNoticePicker._accent
              : Colors.transparent,
          width: 1.2,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected
              ? EventInquiryOffNoticePicker._accent
              : Colors.black54,
        ),
      ),
    ),
  );
}

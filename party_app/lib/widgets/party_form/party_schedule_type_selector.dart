import 'package:flutter/material.dart';
import 'package:party_app/models/party_schedule.dart';

const _kAccent = Color(0xFFFF6FA0);

/// 등록 화면의 "일정 유형" 선택 — 일회성 파티 / 정기 파티.
///
/// 호스트 계정 전체의 운영 방식이 아니라 **지금 등록하는 게시글 한 건**의
/// 일정 유형이라는 점을 안내 문구로 분명히 한다. 정기 파티를 이미 운영 중인
/// 호스트도 이 화면에서 일회성 파티를 별도 게시글로 얼마든지 추가 등록할 수
/// 있으며, 기존 게시글은 전혀 바뀌지 않는다.
class PartyScheduleTypeSelector extends StatelessWidget {
  final PartyScheduleType value;
  final ValueChanged<PartyScheduleType> onChanged;

  /// 수정 모드처럼 유형을 바꾸면 곤란한 경우 잠글 수 있다.
  final bool enabled;

  const PartyScheduleTypeSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '이번에 등록할 게시글의 일정 유형이에요. 계정 전체의 운영 방식이 아니라서, '
          '정기 파티를 운영 중이어도 일회성 파티를 따로 등록할 수 있어요.',
          style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.5),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final type in PartyScheduleType.values) ...[
              if (type != PartyScheduleType.values.first)
                const SizedBox(width: 8),
              Expanded(child: _card(type)),
            ],
          ],
        ),
        if (!enabled) ...[
          const SizedBox(height: 8),
          const Text(
            '이미 등록된 게시글의 일정 유형은 바꿀 수 없어요.',
            style: TextStyle(fontSize: 11.5, color: Colors.black38),
          ),
        ],
      ],
    );
  }

  Widget _card(PartyScheduleType type) {
    final selected = value == type;
    return GestureDetector(
      onTap: enabled && !selected ? () => onChanged(type) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF0F5) : const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _kAccent : const Color(0xFFE8EBF2),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Opacity(
          opacity: enabled || selected ? 1 : 0.5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    type == PartyScheduleType.single
                        ? Icons.event_rounded
                        : Icons.repeat_rounded,
                    size: 16,
                    color: selected ? _kAccent : Colors.black38,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      type.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: selected ? _kAccent : Colors.black87,
                      ),
                    ),
                  ),
                  if (selected)
                    const Icon(Icons.check_circle, size: 16, color: _kAccent),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                type.description,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Colors.black54,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

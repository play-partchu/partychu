import 'package:flutter/material.dart';

/// 평일/주말 "공통 시간" 입력 + 그 값을 월~금 / 토·일에 한 번에 넣는 버튼.
///
/// 예전에는 '평일 동일 적용'·'주말 동일 적용'이 **월요일 값**을 복사하는 방식이라
/// 화면만 봐서는 무엇이 복사되는지 알 수 없었다. 이제는 여기서 직접 고른 시간이
/// 그대로 들어가므로, 누르기 전에 어떤 값이 적용될지 눈으로 확인할 수 있다.
/// 적용한 뒤에도 아래 요일별 칸에서 개별 요일만 다시 고칠 수 있다.
class WeeklyHoursBulkApply extends StatelessWidget {
  /// 평일(월~금)에 넣을 공통 시간. null이면 아직 안 고른 상태.
  final TimeOfDay? weekdayStart;
  final TimeOfDay? weekdayEnd;

  /// 주말(토·일)에 넣을 공통 시간.
  final TimeOfDay? weekendStart;
  final TimeOfDay? weekendEnd;

  /// 시간 칸을 눌렀을 때 — (주말 그룹인가?, 시작 시간인가?).
  final void Function(bool weekend, bool isStart) onPickTime;

  /// 적용 버튼을 눌렀을 때 — (주말 그룹인가?).
  /// 두 시간이 모두 채워진 그룹에서만 호출된다.
  final void Function(bool weekend) onApply;

  /// 화면마다 다른 시각 표기(24시간제 '19:00' / '오후 7:00')를 그대로 쓴다.
  final String Function(TimeOfDay) formatTime;

  final Color accent;
  final Color accentFill;

  /// 버튼 아래 안내 문구. null이면 문구 줄을 넣지 않는다.
  final String? footnote;

  /// 시간 입력과 별개로 그 그룹에 적용할 수 있는지 — 정기 파티처럼 "운영 요일로
  /// 고른 날에만" 넣는 화면이 쓴다(그 그룹에 켜진 요일이 없으면 false).
  final bool weekdayApplicable;
  final bool weekendApplicable;

  const WeeklyHoursBulkApply({
    super.key,
    required this.weekdayStart,
    required this.weekdayEnd,
    required this.weekendStart,
    required this.weekendEnd,
    required this.onPickTime,
    required this.onApply,
    required this.formatTime,
    this.accent = const Color(0xFF7C5CBF),
    this.accentFill = const Color(0xFFF3EFFA),
    this.weekdayApplicable = true,
    this.weekendApplicable = true,
    this.footnote = '적용을 누르면 아래 요일별 시간이 한 번에 바뀌어요. 그 뒤 요일별로 따로 수정할 수 있어요.',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _group(weekend: false),
        const SizedBox(height: 8),
        _group(weekend: true),
        if (footnote != null) ...[
          const SizedBox(height: 8),
          Text(
            footnote!,
            style: const TextStyle(
              fontSize: 11.5,
              color: Colors.black45,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  Widget _group({required bool weekend}) {
    final start = weekend ? weekendStart : weekdayStart;
    final end = weekend ? weekendEnd : weekdayEnd;
    final ready =
        start != null &&
        end != null &&
        (weekend ? weekendApplicable : weekdayApplicable);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EBF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  weekend ? '주말 공통 시간 (토·일)' : '평일 공통 시간 (월~금)',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              TextButton(
                // 시간을 다 고르기 전에는 무엇이 적용될지 알 수 없으므로 막는다.
                onPressed: ready ? () => onApply(weekend) : null,
                style: TextButton.styleFrom(
                  foregroundColor: accent,
                  backgroundColor: accentFill,
                  disabledForegroundColor: Colors.black26,
                  disabledBackgroundColor: const Color(0xFFF0F1F5),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  weekend ? '주말 전체 적용' : '평일 전체 적용',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _timeBox(weekend: weekend, isStart: true, time: start),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('~', style: TextStyle(color: Colors.black54)),
              ),
              Expanded(
                child: _timeBox(weekend: weekend, isStart: false, time: end),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _timeBox({
    required bool weekend,
    required bool isStart,
    required TimeOfDay? time,
  }) {
    return GestureDetector(
      onTap: () => onPickTime(weekend, isStart),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: time == null
                ? const Color(0xFFE8EBF2)
                : accent.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isStart ? '시작 시간' : '종료 시간',
              style: const TextStyle(fontSize: 10.5, color: Colors.black38),
            ),
            const SizedBox(height: 2),
            Text(
              time == null ? '선택하세요' : formatTime(time),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: time == null ? FontWeight.normal : FontWeight.w600,
                color: time == null ? Colors.black38 : accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

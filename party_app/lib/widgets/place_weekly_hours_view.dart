import 'package:flutter/material.dart';

import 'package:party_app/models/place_weekly_hours.dart';

/// 상세 화면의 "운영시간" 카드 — 요일별 영업시간 + 정기 휴무 + 브레이크 타임.
///
/// 등록/수정 화면이 쓰는 모델([PlaceWeeklyHours])을 그대로 읽으므로, 저장한
/// 내용과 보이는 내용이 어긋나지 않는다. 휴무·브레이크가 없는 예전 문서는
/// 영업일·브레이크 없음으로 읽히므로 예전 그대로 보인다.
class PlaceWeeklyHoursView extends StatelessWidget {
  final PlaceWeeklyHours hours;

  /// 장소 전체 24시간 운영. 켜져 있으면 요일별 표 대신 그 문구만 보여준다.
  final bool isOpen24Hours;

  /// 기준 시각 — 테스트에서 고정하려고 열어 둔다. 비우면 지금.
  final DateTime? now;

  final Color accent;

  const PlaceWeeklyHoursView({
    super.key,
    required this.hours,
    this.isOpen24Hours = false,
    this.now,
    this.accent = const Color(0xFF7C5CBF),
  });

  static String _fmt(TimeOfDay t) => PlaceWeeklyHours.formatTime(t);

  @override
  Widget build(BuildContext context) {
    final at = now ?? DateTime.now();
    final todayKey = PlaceWeeklyHours.weekdayKeyOf(at);
    final status = isOpen24Hours ? null : hours.statusAt(at);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule_outlined, size: 16, color: accent),
              const SizedBox(width: 6),
              const Text(
                '운영시간',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              _badge(status),
            ],
          ),
          const SizedBox(height: 10),
          if (isOpen24Hours)
            const Text(
              '24시간 운영',
              style: TextStyle(fontSize: 13, color: Colors.black87),
            )
          else
            ...PlaceWeeklyHours.weekdays.map(
              (day) => _dayRow(day, isToday: day == todayKey),
            ),
        ],
      ),
    );
  }

  /// 지금 상태 배지 — 휴무·브레이크 타임이 '영업 중/영업 종료'보다 앞선다.
  Widget _badge(PlaceHoursStatus? status) {
    final (label, color) = switch (status) {
      null => ('24시간 운영', accent),
      PlaceHoursStatus.closedToday => ('오늘 휴무', Colors.redAccent),
      PlaceHoursStatus.onBreak => ('브레이크 타임', const Color(0xFFB45309)),
      PlaceHoursStatus.open => ('영업 중', const Color(0xFF15803D)),
      PlaceHoursStatus.closedNow => ('영업 종료', Colors.black45),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _dayRow(String day, {required bool isToday}) {
    final value = hours.get(day);
    if (value == null) return const SizedBox.shrink();
    final text = value.isClosed
        ? '휴무'
        : value.is24Hours
        ? '24시간'
        : '${_fmt(value.open)}~${_fmt(value.close)}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 62,
                child: Text(
                  PlaceWeeklyHours.fullDayName(day),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                    color: isToday ? accent : Colors.black54,
                  ),
                ),
              ),
              Text(
                text,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                  color: value.isClosed
                      ? Colors.redAccent
                      : (isToday ? Colors.black87 : Colors.black54),
                ),
              ),
            ],
          ),
          if (value.hasEffectiveBreak)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 62),
              child: Text(
                '브레이크 ${_fmt(value.breakStart)}~${_fmt(value.breakEnd)}',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFFB45309),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

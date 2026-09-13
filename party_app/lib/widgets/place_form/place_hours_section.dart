import 'package:flutter/material.dart';

import 'package:party_app/models/place_weekly_hours.dart';
import 'package:party_app/widgets/place_form/weekly_hours_editor.dart';

/// "운영시간" 섹션 — 24시간 운영 여부 + 요일별 운영시간(휴무·브레이크 타임 포함).
///
/// 요일별 입력은 [WeeklyHoursEditor] 하나로 모아 두었다. 대표 운영시간
/// ([openTime]/[closeTime], 문서의 openTime/closeTime으로 저장된다)은 편집기의
/// "평일 공통 기준" 칸이 그대로 쓴다 — 평일 기준을 고치면 대표 시간도 같이
/// 바뀌므로 두 값이 어긋나지 않는다.
///
/// [weeklyHours]는 가변 객체라 호출부가 들고 있는 인스턴스를 그대로 고치고
/// [onWeeklyChanged]로 다시 그려달라고 알린다.
class PlaceHoursSection extends StatefulWidget {
  final String title;

  /// 카드 상단 안내 문구. null이면 문구 줄 자체를 넣지 않는다.
  final String? description;

  final bool isOpen24Hours;
  final ValueChanged<bool> onOpen24HoursChanged;

  final TimeOfDay? openTime;
  final TimeOfDay? closeTime;
  final void Function(bool isOpen, TimeOfDay picked) onTimeChanged;

  final PlaceWeeklyHours weeklyHours;
  final VoidCallback onWeeklyChanged;

  const PlaceHoursSection({
    super.key,
    required this.isOpen24Hours,
    required this.onOpen24HoursChanged,
    required this.openTime,
    required this.closeTime,
    required this.onTimeChanged,
    required this.weeklyHours,
    required this.onWeeklyChanged,
    this.title = '운영시간',
    this.description,
  });

  static const _accent = Color(0xFF7C5CBF);

  /// "오전 9:00" 형식. 등록 화면과 같은 표기.
  static String formatDisplay(TimeOfDay t) {
    final h = t.hour;
    final m = t.minute.toString().padLeft(2, '0');
    if (h == 0) return '오전 12:$m';
    if (h < 12) return '오전 $h:$m';
    if (h == 12) return '오후 12:$m';
    return '오후 ${h - 12}:$m';
  }

  @override
  State<PlaceHoursSection> createState() => _PlaceHoursSectionState();
}

class _PlaceHoursSectionState extends State<PlaceHoursSection> {
  /// 주말(토·일)에 한 번에 넣을 기준 시간 — 요일별 시간표에만 반영되고 따로
  /// 저장되지 않으므로 이 위젯이 들고 있는다.
  TimeOfDay? _weekendStart;
  TimeOfDay? _weekendEnd;

  Future<TimeOfDay?> _showPicker(TimeOfDay initial) => showTimePicker(
    context: context,
    initialTime: initial,
    builder: (ctx, child) => MediaQuery(
      data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
      child: Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: PlaceHoursSection._accent,
          ),
        ),
        child: child!,
      ),
    ),
  );

  Future<void> _pickBaseTime(bool weekend, bool isStart) async {
    final current = weekend
        ? (isStart ? _weekendStart : _weekendEnd)
        : (isStart ? widget.openTime : widget.closeTime);
    final picked = await _showPicker(
      current ??
          (isStart
              ? const TimeOfDay(hour: 9, minute: 0)
              : const TimeOfDay(hour: 23, minute: 0)),
    );
    if (picked == null || !mounted) return;
    if (!weekend) {
      widget.onTimeChanged(isStart, picked);
      return;
    }
    setState(() {
      if (isStart) {
        _weekendStart = picked;
      } else {
        _weekendEnd = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          if (widget.description != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(
                widget.description!,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black45,
                  height: 1.5,
                ),
              ),
            )
          else
            const SizedBox(height: 8),
          Row(
            children: [
              Checkbox(
                value: widget.isOpen24Hours,
                onChanged: (v) => widget.onOpen24HoursChanged(v ?? false),
                activeColor: PlaceHoursSection._accent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const Text(
                '24시간 운영',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          if (!widget.isOpen24Hours) ...[
            const SizedBox(height: 4),
            WeeklyHoursEditor(
              hours: widget.weeklyHours,
              onChanged: widget.onWeeklyChanged,
              weekdayStart: widget.openTime,
              weekdayEnd: widget.closeTime,
              weekendStart: _weekendStart,
              weekendEnd: _weekendEnd,
              onPickBaseTime: _pickBaseTime,
              formatTime: PlaceHoursSection.formatDisplay,
            ),
          ] else
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF3EFFA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.schedule,
                    size: 16,
                    color: PlaceHoursSection._accent,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '오전 12:00 ~ 자정 (24:00)',
                      style: TextStyle(
                        fontSize: 14,
                        color: PlaceHoursSection._accent,
                        fontWeight: FontWeight.w600,
                      ),
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

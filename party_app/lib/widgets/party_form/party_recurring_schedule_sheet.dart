import 'package:flutter/material.dart';
import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/widgets/party_form/recruit_deadline_editor.dart';
import 'package:party_app/widgets/party_form/wheel_time_picker_sheet.dart';
import 'package:party_app/widgets/weekly_hours_bulk_apply.dart';

const _kAccent = Color(0xFFFF6FA0);
const _kBoxFill = Color(0xFFF7F7FA);

/// 정기 파티 일정 편집 시트 — 운영 요일 다중 선택, 요일별 시작/종료 시간,
/// 운영 시작일/종료일(또는 종료일 없음), 회차별 모집 마감 기준.
///
/// 평일·주말처럼 시간이 같은 요일은 묶어서 한 번에 설정할 수 있고, 그 뒤
/// 개별 요일을 다시 수정해도 다른 요일에는 영향을 주지 않는다.
Future<PartyRecurringSchedule?> showPartyRecurringScheduleSheet(
  BuildContext context, {
  required PartyRecurringSchedule initial,
}) {
  return showModalBottomSheet<PartyRecurringSchedule>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _PartyRecurringScheduleSheetBody(initial: initial),
  );
}

class _PartyRecurringScheduleSheetBody extends StatefulWidget {
  final PartyRecurringSchedule initial;

  const _PartyRecurringScheduleSheetBody({required this.initial});

  @override
  State<_PartyRecurringScheduleSheetBody> createState() =>
      _PartyRecurringScheduleSheetBodyState();
}

class _PartyRecurringScheduleSheetBodyState
    extends State<_PartyRecurringScheduleSheetBody> {
  late PartyRecurringSchedule _schedule = widget.initial;

  // 평일/주말에 한 번에 넣을 공통 시간. 여기 적은 값이 그대로 요일별 칸에
  // 들어가므로, 누르기 전에 무엇이 적용될지 눈으로 확인할 수 있다.
  TimeOfDay? _weekdayStart;
  TimeOfDay? _weekdayEnd;
  TimeOfDay? _weekendStart;
  TimeOfDay? _weekendEnd;

  @override
  void initState() {
    super.initState();
    // 이미 설정된 일정을 다시 열면 지금 값이 공통 칸에도 그대로 보이게 한다.
    final weekday = _firstEnabled(kPartyWeekdayKeysWeekday);
    if (weekday != null) {
      _weekdayStart = _schedule.slotFor(weekday).startTime;
      _weekdayEnd = _schedule.slotFor(weekday).endTime;
    }
    final weekend = _firstEnabled(kPartyWeekdayKeysWeekend);
    if (weekend != null) {
      _weekendStart = _schedule.slotFor(weekend).startTime;
      _weekendEnd = _schedule.slotFor(weekend).endTime;
    }
  }

  String? _firstEnabled(List<String> keys) {
    for (final key in keys) {
      if (_schedule.slotFor(key).enabled) return key;
    }
    return null;
  }

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  // ── 요일 on/off ─────────────────────────────────────────────────────
  void _toggleDay(String key) {
    final slot = _schedule.slotFor(key);
    setState(() {
      _schedule = _schedule.withSlot(
        key,
        slot.copyWith(enabled: !slot.enabled),
      );
    });
  }

  // ── 평일/주말 공통 시간 ─────────────────────────────────────────────
  bool _groupHasEnabledDay(List<String> keys) =>
      keys.any((k) => _schedule.slotFor(k).enabled);

  Future<void> _pickCommonTime({
    required bool weekend,
    required bool isStart,
  }) async {
    final current = weekend
        ? (isStart ? _weekendStart : _weekendEnd)
        : (isStart ? _weekdayStart : _weekdayEnd);
    final picked = await showWheelTimePicker(
      context,
      initial:
          current ??
          (isStart
              ? const TimeOfDay(hour: 19, minute: 0)
              : const TimeOfDay(hour: 22, minute: 0)),
      title: '${weekend ? '주말' : '평일'} 공통 ${isStart ? '시작' : '종료'} 시간',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (weekend) {
        if (isStart) {
          _weekendStart = picked;
        } else {
          _weekendEnd = picked;
        }
      } else {
        if (isStart) {
          _weekdayStart = picked;
        } else {
          _weekdayEnd = picked;
        }
      }
    });
  }

  /// 공통 시간을 그 묶음에서 **운영 요일로 켜 둔 날**에만 넣는다.
  /// 요일 on/off는 위 '운영 요일'이 정하고, 여기서는 시간만 바꾼다.
  void _applyCommonTimes({required bool weekend}) {
    final start = weekend ? _weekendStart : _weekdayStart;
    final end = weekend ? _weekendEnd : _weekdayEnd;
    if (start == null || end == null) return;
    final group = weekend ? kPartyWeekdayKeysWeekend : kPartyWeekdayKeysWeekday;
    final days = group.where((k) => _schedule.slotFor(k).enabled).toList();
    if (days.isEmpty) return;
    setState(() {
      _schedule = _schedule.applyTimesTo(
        days,
        PartyWeeklySlot(enabled: true, startTime: start, endTime: end),
      );
    });
  }

  Future<void> _pickDayTime(String key, {required bool isStart}) async {
    final slot = _schedule.slotFor(key);
    final picked = await showWheelTimePicker(
      context,
      initial: isStart ? slot.startTime : slot.endTime,
      title: '${kPartyWeekdayLabels[key]}요일 ${isStart ? '시작' : '종료'} 시간',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _schedule = _schedule.withSlot(
        key,
        isStart
            ? slot.copyWith(startTime: picked)
            : slot.copyWith(endTime: picked),
      );
    });
  }

  // ── 운영 기간 ───────────────────────────────────────────────────────
  Future<void> _pickStartDate() async {
    final base = _schedule.startDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: base.isBefore(_today) ? _today : base,
      firstDate: _today,
      lastDate: DateTime(_today.year + 3),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _schedule = _schedule.copyWith(
        startDate: picked,
        // 시작일이 종료일보다 뒤로 가면 종료일을 지운다(무기한으로 되돌림).
        clearEndDate:
            _schedule.endDate != null && picked.isAfter(_schedule.endDate!),
      );
    });
  }

  Future<void> _pickEndDate() async {
    final base = _schedule.endDate ?? _schedule.startDate;
    final first = _schedule.startDate.isBefore(_today)
        ? _today
        : _schedule.startDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: base.isBefore(first) ? first : base,
      firstDate: first,
      lastDate: DateTime(_today.year + 3),
    );
    if (picked == null || !mounted) return;
    setState(() => _schedule = _schedule.copyWith(endDate: picked));
  }

  // ── 조각 위젯 ───────────────────────────────────────────────────────
  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
    ),
  );

  Widget _box(String text, VoidCallback onTap, {bool hasValue = true}) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _kBoxFill,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            text,
            style: TextStyle(color: hasValue ? Colors.black87 : Colors.black38),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );

  Widget _dayChip(String key) {
    final selected = _schedule.slotFor(key).enabled;
    return GestureDetector(
      onTap: () => _toggleDay(key),
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? _kAccent : _kBoxFill,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? _kAccent : const Color(0xFFE8EBF2),
          ),
        ),
        child: Text(
          kPartyWeekdayLabels[key]!,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : Colors.black45,
          ),
        ),
      ),
    );
  }

  Widget _dayTimeRow(String key) {
    final slot = _schedule.slotFor(key);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EBF2)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              kPartyWeekdayLabels[key]!,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _kAccent,
              ),
            ),
          ),
          Expanded(
            child: _box(
              formatScheduleTime(slot.startTime),
              () => _pickDayTime(key, isStart: true),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('~'),
          ),
          Expanded(
            child: _box(
              // 자정을 넘기면 "익일"을 붙여 다음 날 종료임을 분명히 한다.
              '${slot.crossesMidnight ? '익일 ' : ''}'
              '${formatScheduleTime(slot.endTime)}',
              () => _pickDayTime(key, isStart: false),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) => '${d.year}년 ${d.month}월 ${d.day}일';

  @override
  Widget build(BuildContext context) {
    final enabledDays = _schedule.enabledDayKeys;
    final rule = _schedule.deadlineRule;
    // 마감 미리보기의 기준 — 지금 설정으로 가장 먼저 열리는 회차.
    final nextOccurrence = _schedule.nextOccurrence(DateTime.now());

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '정기 일정 설정',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  '매주 반복되는 요일과 시간을 정해주세요. 자정을 넘기는 시간(예: 19:00~03:00)은 '
                  '다음 날 종료로 처리돼요.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black45,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 18),

                _label('운영 요일'),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final key in kPartyWeekdayKeys) _dayChip(key),
                  ],
                ),
                const SizedBox(height: 14),
                // 어느 요일을 복사할지 고민할 필요 없이, 여기 적은 시간이
                // 그대로 선택한 평일/주말에 들어간다.
                WeeklyHoursBulkApply(
                  weekdayStart: _weekdayStart,
                  weekdayEnd: _weekdayEnd,
                  weekendStart: _weekendStart,
                  weekendEnd: _weekendEnd,
                  onPickTime: (weekend, isStart) =>
                      _pickCommonTime(weekend: weekend, isStart: isStart),
                  onApply: (weekend) => _applyCommonTimes(weekend: weekend),
                  formatTime: formatScheduleTime,
                  accent: _kAccent,
                  accentFill: const Color(0xFFFFF0F5),
                  weekdayApplicable: _groupHasEnabledDay(
                    kPartyWeekdayKeysWeekday,
                  ),
                  weekendApplicable: _groupHasEnabledDay(
                    kPartyWeekdayKeysWeekend,
                  ),
                  footnote:
                      '위에서 고른 운영 요일에만 적용돼요. 적용한 뒤에도 요일별로 시간을 따로 바꿀 수 있어요.',
                ),
                const SizedBox(height: 20),

                _label('요일별 시간'),
                if (enabledDays.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      '운영 요일을 하나 이상 선택해주세요.',
                      style: TextStyle(fontSize: 12, color: Colors.black45),
                    ),
                  )
                else
                  ...enabledDays.map(_dayTimeRow),
                const SizedBox(height: 12),

                _label('정기 운영 시작일'),
                _box(_formatDate(_schedule.startDate), _pickStartDate),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(child: _label('운영 종료일')),
                    Text(
                      _schedule.endDate == null ? '종료일 없음' : '종료일 지정',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black45,
                      ),
                    ),
                    Switch(
                      value: _schedule.endDate != null,
                      onChanged: (v) {
                        if (v) {
                          _pickEndDate();
                        } else {
                          setState(
                            () => _schedule = _schedule.copyWith(
                              clearEndDate: true,
                            ),
                          );
                        }
                      },
                      activeThumbColor: _kAccent,
                    ),
                  ],
                ),
                if (_schedule.endDate != null)
                  _box(_formatDate(_schedule.endDate!), _pickEndDate)
                else
                  const Text(
                    '종료일을 정하지 않으면 계속 반복돼요.',
                    style: TextStyle(fontSize: 12, color: Colors.black45),
                  ),
                const SizedBox(height: 20),

                // 시작 카드와 마감 카드를 따로 감싼다 — 지금 어느 시점을
                // 정하는 중인지 한눈에 구분되도록.
                RecruitRuleCard(
                  title: '모집 시작 기준',
                  subtitle: '언제부터 신청을 받을지 정해요.',
                  child: RecruitDeadlineEditor(
                    value: _schedule.openRule,
                    onChanged: (next) => setState(
                      () => _schedule = _schedule.copyWith(openRule: next),
                    ),
                    kind: PartyRecruitRuleKind.open,
                    referenceStart: nextOccurrence?.start,
                    referenceEnd: nextOccurrence?.end,
                    allowCustomDateTime: false,
                    previewPrefix: '다음 회차',
                    noneNotice: '등록하는 즉시 신청을 받아요.',
                    afterStartNotice: '파티 시작 후에 모집이 열립니다.',
                  ),
                ),
                const SizedBox(height: 14),

                RecruitRuleCard(
                  title: '모집 마감 기준',
                  subtitle: '언제 신청을 닫을지 정해요.',
                  // 회차마다 날짜가 달라지므로 고정 날짜 마감('직접 지정')은
                  // 쓸 수 없다 — 첫 회차만 열리고 나머지가 전부 마감된
                  // 상태가 되기 때문이다.
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RecruitDeadlineEditor(
                        value: rule,
                        onChanged: (next) => setState(
                          () => _schedule = _schedule.copyWith(
                            deadlineRule: next,
                          ),
                        ),
                        referenceStart: nextOccurrence?.start,
                        referenceEnd: nextOccurrence?.end,
                        allowCustomDateTime: false,
                        previewPrefix: '다음 회차',
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '회차마다 그 회차의 시작 시각을 기준으로 다시 계산돼요.',
                        style: TextStyle(fontSize: 12, color: Colors.black45),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: enabledDays.isEmpty
                        ? null
                        : () => Navigator.pop(context, _schedule),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAccent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFE8EBF2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      '선택 완료',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

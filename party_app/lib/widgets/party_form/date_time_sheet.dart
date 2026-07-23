import 'package:flutter/material.dart';
import 'package:party_app/widgets/party_form/custom_time_picker_sheet.dart';

/// 날짜/시간 선택 바텀시트가 다루는 값. [deadlineHasOwnDate]가 false(등록/수정)면
/// 모집마감은 파티 날짜를 그대로 공유하고 시간만 따로 고른다(등록 화면 기존
/// 동작). true(재등록)면 모집마감 날짜도 파티 날짜와 독립적으로 고른다 —
/// 두 모델을 하나로 합치면 재등록의 기존 저장 의미가 바뀌므로 절대 합치지 않는다.
class PartyDateTimeDraft {
  final DateTime? partyDate;
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;
  final TimeOfDay? recruitDeadlineTime;
  final DateTime? recruitDeadlineDate;

  const PartyDateTimeDraft({
    this.partyDate,
    this.startTime,
    this.endTime,
    this.recruitDeadlineTime,
    this.recruitDeadlineDate,
  });

  PartyDateTimeDraft copyWith({
    DateTime? partyDate,
    bool clearPartyDate = false,
    TimeOfDay? startTime,
    bool clearStartTime = false,
    TimeOfDay? endTime,
    bool clearEndTime = false,
    TimeOfDay? recruitDeadlineTime,
    bool clearRecruitDeadlineTime = false,
    DateTime? recruitDeadlineDate,
    bool clearRecruitDeadlineDate = false,
  }) {
    return PartyDateTimeDraft(
      partyDate: clearPartyDate ? null : (partyDate ?? this.partyDate),
      startTime: clearStartTime ? null : (startTime ?? this.startTime),
      endTime: clearEndTime ? null : (endTime ?? this.endTime),
      recruitDeadlineTime: clearRecruitDeadlineTime
          ? null
          : (recruitDeadlineTime ?? this.recruitDeadlineTime),
      recruitDeadlineDate: clearRecruitDeadlineDate
          ? null
          : (recruitDeadlineDate ?? this.recruitDeadlineDate),
    );
  }
}

String formatPartyDate(DateTime? date) {
  if (date == null) return '날짜 선택';
  return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
}

String formatPartyTime(TimeOfDay? time) {
  if (time == null) return '시간 선택';
  final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
  final period = time.period == DayPeriod.am ? '오전' : '오후';
  return '$period ${hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

Future<PartyDateTimeDraft?> showPartyDateTimeSheet(
  BuildContext context, {
  required PartyDateTimeDraft initial,
  bool deadlineHasOwnDate = false,
}) {
  return showModalBottomSheet<PartyDateTimeDraft>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _DateTimeSheetBody(
      initial: initial,
      deadlineHasOwnDate: deadlineHasOwnDate,
    ),
  );
}

class _DateTimeSheetBody extends StatefulWidget {
  final PartyDateTimeDraft initial;
  final bool deadlineHasOwnDate;

  const _DateTimeSheetBody({
    required this.initial,
    required this.deadlineHasOwnDate,
  });

  @override
  State<_DateTimeSheetBody> createState() => _DateTimeSheetBodyState();
}

class _DateTimeSheetBodyState extends State<_DateTimeSheetBody> {
  late PartyDateTimeDraft _draft = widget.initial;

  Future<void> _pickPartyDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = (_draft.partyDate != null && !_draft.partyDate!.isBefore(today))
        ? _draft.partyDate!
        : today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: DateTime(now.year + 3),
    );
    if (picked != null) setState(() => _draft = _draft.copyWith(partyDate: picked));
  }

  Future<void> _pickStartTime() async {
    final picked = await showCustomTimePicker(
      context,
      initial: _draft.startTime ?? const TimeOfDay(hour: 20, minute: 0),
      title: '시작 시간',
    );
    if (picked != null) setState(() => _draft = _draft.copyWith(startTime: picked));
  }

  Future<void> _pickEndTime() async {
    final picked = await showCustomTimePicker(
      context,
      initial: _draft.endTime ?? const TimeOfDay(hour: 23, minute: 0),
      title: '종료 시간',
    );
    if (picked != null) setState(() => _draft = _draft.copyWith(endTime: picked));
  }

  Future<void> _pickRecruitDeadlineDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final base = _draft.recruitDeadlineDate ?? _draft.partyDate ?? today;
    final initial = base.isBefore(today) ? today : base;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: DateTime(now.year + 3),
    );
    if (picked != null) {
      setState(() => _draft = _draft.copyWith(recruitDeadlineDate: picked));
    }
  }

  Future<void> _pickRecruitDeadlineTime() async {
    final picked = await showCustomTimePicker(
      context,
      initial: _draft.recruitDeadlineTime ?? const TimeOfDay(hour: 18, minute: 0),
      title: '모집 마감 시간',
    );
    if (picked != null) {
      setState(() => _draft = _draft.copyWith(recruitDeadlineTime: picked));
    }
  }

  void _clearDeadline() {
    setState(() {
      _draft = _draft.copyWith(
        clearRecruitDeadlineTime: true,
        clearRecruitDeadlineDate: true,
      );
    });
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      );

  Widget _box(String text, VoidCallback onTap, {bool hasValue = false}) => InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F7FA),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            text,
            style: TextStyle(color: hasValue ? Colors.black87 : Colors.black38),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final hasDeadline = widget.deadlineHasOwnDate
        ? (_draft.recruitDeadlineDate != null || _draft.recruitDeadlineTime != null)
        : _draft.recruitDeadlineTime != null;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
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
                      borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 16),
              const Text('날짜 및 시간 선택',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 18),
              _label('파티 날짜'),
              _box(formatPartyDate(_draft.partyDate), _pickPartyDate,
                  hasValue: _draft.partyDate != null),
              const SizedBox(height: 16),
              _label('시작 시간'),
              _box(formatPartyTime(_draft.startTime), _pickStartTime,
                  hasValue: _draft.startTime != null),
              const SizedBox(height: 16),
              _label('종료 시간'),
              _box(formatPartyTime(_draft.endTime), _pickEndTime,
                  hasValue: _draft.endTime != null),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _label('모집마감시간 (선택)')),
                  if (hasDeadline)
                    IconButton(
                      onPressed: _clearDeadline,
                      icon: const Icon(Icons.clear, size: 18),
                      color: Colors.black38,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
              if (widget.deadlineHasOwnDate)
                Row(
                  children: [
                    Expanded(
                      child: _box(
                        formatPartyDate(_draft.recruitDeadlineDate),
                        _pickRecruitDeadlineDate,
                        hasValue: _draft.recruitDeadlineDate != null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _box(
                        formatPartyTime(_draft.recruitDeadlineTime),
                        _pickRecruitDeadlineTime,
                        hasValue: _draft.recruitDeadlineTime != null,
                      ),
                    ),
                  ],
                )
              else ...[
                _box(
                  formatPartyTime(_draft.recruitDeadlineTime),
                  _pickRecruitDeadlineTime,
                  hasValue: _draft.recruitDeadlineTime != null,
                ),
                const SizedBox(height: 6),
                const Text(
                  '설정 시 마감시간 이후 자동으로 신청 불가 처리됩니다.',
                  style: TextStyle(fontSize: 12, color: Colors.black45),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, _draft),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6FA0),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('선택 완료',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

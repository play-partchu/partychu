import 'package:flutter/material.dart';
import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/widgets/party_form/recruit_deadline_editor.dart';
import 'package:party_app/widgets/party_form/wheel_time_picker_sheet.dart';
import 'package:party_app/widgets/party_form/date_time_sheet.dart'
    show formatPartyDate, formatPartyTime;

const _kAccent = Color(0xFFFF6FA0);
const _kBoxFill = Color(0xFFF7F7FA);

/// "날짜 직접 선택" 방식의 일정 목록 시트.
///
/// 여러 날짜·시간대를 자유롭게 추가/수정/삭제한다. 같은 날짜라도 시간대가
/// 다르면 별개 일정으로 추가할 수 있고, 날짜·시작·종료가 모두 같은 일정은
/// 중복이라 추가되지 않는다.
///
/// 매주 반복은 이 시트가 아니라 **일정 방식 자체**로 분리돼 있다
/// ([PartyScheduleType.recurring] → party_recurring_schedule_sheet.dart).
/// 예전에 이 시트가 갖고 있던 "매주 반복 + 반복 횟수(최대 52회)" 자동 생성은
/// 제거됐다 — 반복은 날짜를 미리 찍어내지 않고 규칙 하나로 저장한다.

/// 날짜 목록 시트가 입출력하는 값.
class PartyDateListDraft {
  final List<PartyDateSlot> slots;

  /// 모집 시작 규칙 — 날짜마다 **자기 시작 시각**에 적용된다.
  final PartyRecruitDeadlineRule openRule;

  /// 모집 마감 규칙 — 날짜마다 **자기 시작 시각**에 적용된다.
  final PartyRecruitDeadlineRule deadlineRule;

  const PartyDateListDraft({
    this.slots = const [],
    this.openRule = PartyRecruitDeadlineRule.noDeadline,
    this.deadlineRule = PartyRecruitDeadlineRule.noDeadline,
  });
}

Future<PartyDateListDraft?> showPartyDateListSheet(
  BuildContext context, {
  required PartyDateListDraft initial,
}) {
  return showModalBottomSheet<PartyDateListDraft>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _PartyDateListSheetBody(initial: initial),
  );
}

class _PartyDateListSheetBody extends StatefulWidget {
  final PartyDateListDraft initial;

  const _PartyDateListSheetBody({required this.initial});

  @override
  State<_PartyDateListSheetBody> createState() =>
      _PartyDateListSheetBodyState();
}

class _PartyDateListSheetBodyState extends State<_PartyDateListSheetBody> {
  final List<PartyDateSlot> _slots = [];
  late PartyRecruitDeadlineRule _openRule = widget.initial.openRule;
  late PartyRecruitDeadlineRule _deadlineRule = widget.initial.deadlineRule;

  /// 마감 미리보기의 기준 — 추가한 일정 중 가장 이른 회차.
  ({DateTime start, DateTime? end})? get _firstOccurrence {
    final ready = _slots.where((s) => s.startTime != null).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    if (ready.isEmpty) return null;
    final slot = ready.first;
    return (start: slot.start, end: slot.toSingleSchedule().end);
  }

  @override
  void initState() {
    super.initState();
    _slots.addAll(widget.initial.slots);
  }

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  void _msg(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  /// [candidate]와 날짜·시작·종료가 모두 같은 일정이 이미 있으면 true.
  /// [ignoreIndex]는 지금 수정 중인 자기 자신을 비교에서 뺀다.
  bool _isDuplicate(PartyDateSlot candidate, {int? ignoreIndex}) {
    for (var i = 0; i < _slots.length; i++) {
      if (i == ignoreIndex) continue;
      if (_slots[i].dedupeKey == candidate.dedupeKey) return true;
    }
    return false;
  }

  /// 중복이면 안내만 하고 값을 되돌린다(저장하지 않음).
  bool _applySlot(int index, PartyDateSlot next) {
    if (_isDuplicate(next, ignoreIndex: index)) {
      _msg('이미 추가된 일정입니다.');
      return false;
    }
    setState(() => _slots[index] = next);
    return true;
  }

  Future<void> _addDateSlot() async {
    final last = _slots.isNotEmpty ? _slots.last : null;
    final initial = last != null
        ? last.date.add(const Duration(days: 1))
        : _today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(_today) ? _today : initial,
      firstDate: _today,
      lastDate: DateTime(_today.year + 3),
    );
    if (picked == null || !mounted) return;
    // 직전 일정의 시간대를 가져와 두면 "같은 시간, 다른 날짜"를 빠르게 넣을 수
    // 있다. 그대로 두면 날짜만 다르므로 중복이 되지 않는다.
    final candidate = PartyDateSlot(
      id: newPartyDateSlotId(),
      date: picked,
      startTime: last?.startTime,
      endTime: last?.endTime,
    );
    if (_isDuplicate(candidate)) {
      _msg('이미 추가된 일정입니다.');
      return;
    }
    setState(() => _slots.add(candidate));
  }

  Future<void> _pickSlotDate(int index) async {
    final slot = _slots[index];
    final initial = slot.date.isBefore(_today) ? _today : slot.date;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: _today,
      lastDate: DateTime(_today.year + 3),
    );
    if (picked == null || !mounted) return;
    _applySlot(index, slot.copyWith(date: picked));
  }

  Future<void> _pickSlotStartTime(int index) async {
    final slot = _slots[index];
    final picked = await showWheelTimePicker(
      context,
      initial: slot.startTime ?? const TimeOfDay(hour: 20, minute: 0),
      title: '시작 시간',
    );
    if (picked == null || !mounted) return;
    _applySlot(index, slot.copyWith(startTime: picked));
  }

  Future<void> _pickSlotEndTime(int index) async {
    final slot = _slots[index];
    final picked = await showWheelTimePicker(
      context,
      initial: slot.endTime ?? const TimeOfDay(hour: 23, minute: 0),
      title: '종료 시간',
    );
    if (picked == null || !mounted) return;
    _applySlot(index, slot.copyWith(endTime: picked));
  }

  void _deleteSlot(int index) => setState(() => _slots.removeAt(index));

  Widget _box(String text, VoidCallback onTap, {bool hasValue = false}) =>
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

  Widget _slotCard(int index) {
    final slot = _slots[index];
    // 자정을 넘기는 시간대(20:00~02:00)는 다음 날 종료로 처리된다 — 저장
    // 로직(PartySingleSchedule.end)과 같은 규칙이라 여기서도 그대로 알려준다.
    final crossesMidnight =
        slot.startTime != null &&
        slot.endTime != null &&
        (slot.endTime!.hour * 60 + slot.endTime!.minute) <=
            (slot.startTime!.hour * 60 + slot.startTime!.minute);
    return Container(
      key: ValueKey(slot.id),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
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
              Text(
                '일정 ${index + 1}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: _kAccent,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => _deleteSlot(index),
                icon: const Icon(Icons.delete_outline, size: 20),
                color: Colors.redAccent,
                tooltip: '이 일정 삭제',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _box(
            formatPartyDate(slot.date),
            () => _pickSlotDate(index),
            hasValue: true,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _box(
                  formatPartyTime(slot.startTime),
                  () => _pickSlotStartTime(index),
                  hasValue: slot.startTime != null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _box(
                  formatPartyTime(slot.endTime),
                  () => _pickSlotEndTime(index),
                  hasValue: slot.endTime != null,
                ),
              ),
            ],
          ),
          if (crossesMidnight) ...[
            const SizedBox(height: 6),
            const Text(
              '자정을 넘겨 다음 날 종료로 처리돼요.',
              style: TextStyle(fontSize: 12, color: Colors.black45),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final first = _firstOccurrence;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
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
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '날짜 및 시간 선택',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  '여러 날짜를 추가할 수 있어요. 같은 날짜라도 시간대가 다르면 따로 추가하면 돼요.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black45,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 18),
                if (_slots.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      '아직 추가된 일정이 없어요. 아래에서 날짜를 추가해주세요.',
                      style: TextStyle(fontSize: 12, color: Colors.black45),
                    ),
                  ),
                ...List.generate(_slots.length, _slotCard),
                GestureDetector(
                  onTap: _addDateSlot,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3F7),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _kAccent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, size: 16, color: _kAccent),
                        SizedBox(width: 4),
                        Text(
                          '일정 추가',
                          style: TextStyle(
                            fontSize: 13,
                            color: _kAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 시작 카드와 마감 카드를 따로 감싼다 — 두 규칙이 나란히 있어서
                // 지금 어느 시점을 정하는 중인지 헷갈리던 문제를 없앤다.
                RecruitRuleCard(
                  title: '모집 시작 기준',
                  subtitle: '언제부터 신청을 받을지 정해요.',
                  child: RecruitDeadlineEditor(
                    value: _openRule,
                    onChanged: (next) => setState(() => _openRule = next),
                    kind: PartyRecruitRuleKind.open,
                    referenceStart: first?.start,
                    referenceEnd: first?.end,
                    previewPrefix: _slots.length > 1 ? '첫 일정' : null,
                    noneNotice: '등록하는 즉시 신청을 받아요.',
                    afterStartNotice: '파티 시작 후에 모집이 열립니다.',
                  ),
                ),
                const SizedBox(height: 14),

                RecruitRuleCard(
                  title: '모집 마감 기준',
                  subtitle: '언제 신청을 닫을지 정해요.',
                  // 날짜를 여러 개 넣어도 규칙은 하나다 — 날짜마다 자기 시작
                  // 시각에 규칙을 적용해 마감이 따로 계산된다. 미리보기는 가장
                  // 이른 일정 기준이다.
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RecruitDeadlineEditor(
                        value: _deadlineRule,
                        onChanged: (next) =>
                            setState(() => _deadlineRule = next),
                        referenceStart: first?.start,
                        referenceEnd: first?.end,
                        previewPrefix: _slots.length > 1 ? '첫 일정' : null,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _slots.length <= 1
                            ? '모집 마감 이후에는 자동으로 신청 불가 처리됩니다.'
                            // '직접 지정'만 고정된 한 시각이고, 나머지는 날짜마다
                            // 자기 파티 시작 시각을 기준으로 따로 계산된다.
                            : _deadlineRule.mode ==
                                  PartyDeadlineMode.customDateTime
                            ? '고른 날짜·시각 하나가 모든 일정의 모집 마감이 돼요.'
                            : '날짜마다 그 파티의 시작 시각을 기준으로 모집 마감이 '
                                  '따로 계산돼요.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black45,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(
                      context,
                      PartyDateListDraft(
                        slots: _slots,
                        openRule: _openRule,
                        deadlineRule: _deadlineRule,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAccent,
                      foregroundColor: Colors.white,
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:party_app/models/party_early_bird.dart';
import 'package:party_app/models/party_early_bird_schedule.dart';
import 'package:party_app/models/party_schedule.dart' show formatScheduleTime;
import 'package:party_app/utils/format_utils.dart';
import 'package:party_app/widgets/party_form/wheel_time_picker_sheet.dart';

const _kAccent = Color(0xFFFF6FA0);
const _kBoxFill = Color(0xFFF7F7FA);

/// 얼리버드 할인 입력 — 등록 화면들이 공유하는 섹션.
///
/// 무료 파티에는 할인이 의미가 없으므로 [isFree]일 때는 안내만 보여주고
/// 입력을 막는다(검증도 같은 규칙: [PartyEarlyBird.validate]).
///
/// 종료 기준은 두 가지 중에서 고른다.
///   - 날짜 직접 선택 : 종료 날짜 + 종료 시간
///   - 파티 시작 전   : 숫자 + 단위(일/시간). 파티(회차) 시작 시각에서 그만큼
///                      앞선 시점에 종료되며, 날짜가 여러 개거나 정기 파티여도
///                      각 시작 시각 기준으로 자동 계산된다.
///
/// [isRecurring]이면 고정 종료일을 쓸 수 없어(회차마다 날짜가 다르다) 종료
/// 기준이 "파티 시작 전"으로 고정된다.
class PartyEarlyBirdSection extends StatefulWidget {
  final PartyEarlyBird value;
  final ValueChanged<PartyEarlyBird> onChanged;
  final bool isFree;

  /// 정기 파티인지 — "날짜 직접 선택"을 쓸 수 없다.
  final bool isRecurring;

  /// 정가(원). 있으면 "얼리버드 참가비 N원" 미리보기를 함께 보여준다.
  final int? basePrice;

  const PartyEarlyBirdSection({
    super.key,
    required this.value,
    required this.onChanged,
    required this.isFree,
    this.isRecurring = false,
    this.basePrice,
  });

  @override
  State<PartyEarlyBirdSection> createState() => _PartyEarlyBirdSectionState();
}

class _PartyEarlyBirdSectionState extends State<PartyEarlyBirdSection> {
  late final _percentCtrl = TextEditingController(
    text: widget.value.percent?.toString() ?? '',
  );

  /// "N일 전 / N시간 전" 숫자 입력 — 단위를 바꾸면 그 단위의 현재값으로
  /// 다시 채운다.
  late final _amountCtrl = TextEditingController(
    text: widget.value.beforeStartRule.mode == EarlyBirdDeadlineMode.hoursBefore
        ? '${widget.value.beforeStartRule.hours}'
        : '${widget.value.beforeStartRule.days}',
  );

  /// 이 화면에서 실제로 적용되는 종료 기준(정기 파티는 항상 '파티 시작 전').
  PartyEarlyBirdEndType get _endType =>
      widget.value.effectiveEndTypeFor(isRecurring: widget.isRecurring);

  @override
  void dispose() {
    _percentCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickRuleTime(PartyEarlyBird value) async {
    final picked = await showWheelTimePicker(
      context,
      initial: value.beforeStartRule.time,
      title: '얼리버드 종료 시각',
    );
    if (picked == null || !mounted) return;
    widget.onChanged(
      value.copyWith(
        beforeStartRule: value.beforeStartRule.copyWith(time: picked),
      ),
    );
  }

  Future<void> _pickEndDate() async {
    final now = DateTime.now();
    final base = widget.value.endDate ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: base.isBefore(now) ? now : base,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null || !mounted) return;
    widget.onChanged(widget.value.copyWith(endDate: picked));
  }

  Future<void> _pickEndTime() async {
    final picked = await showWheelTimePicker(
      context,
      initial: widget.value.endTime ?? const TimeOfDay(hour: 18, minute: 0),
      title: '얼리버드 종료 시간',
    );
    if (picked == null || !mounted) return;
    widget.onChanged(widget.value.copyWith(endTime: picked));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isFree) {
      return const Text(
        '무료 파티는 얼리버드 할인을 사용할 수 없어요.',
        style: TextStyle(fontSize: 12, color: Colors.black45),
      );
    }

    final value = widget.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '정해진 시각까지 신청하면 참가비를 할인해줘요.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
            Switch(
              value: value.enabled,
              onChanged: (v) => widget.onChanged(value.copyWith(enabled: v)),
              activeThumbColor: _kAccent,
            ),
          ],
        ),
        if (value.enabled) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(
                width: 88,
                child: Text('할인율', style: TextStyle(fontSize: 13)),
              ),
              Expanded(
                child: TextField(
                  controller: _percentCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  onChanged: (v) => widget.onChanged(
                    value.copyWith(
                      percent: int.tryParse(v.trim()),
                      clearPercent: v.trim().isEmpty,
                    ),
                  ),
                  decoration: _deco(hint: '1~99', suffix: '%'),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('얼리버드 종료 기준', style: TextStyle(fontSize: 13)),
          ),
          _endTypeToggle(value),
          const SizedBox(height: 8),
          if (_endType == PartyEarlyBirdEndType.beforeStart)
            ..._beforeStartFields(value)
          else
            Row(
              children: [
                Expanded(
                  child: _box(
                    value.endDate == null
                        ? '종료일 선택'
                        : '${value.endDate!.month}월 ${value.endDate!.day}일',
                    _pickEndDate,
                    hasValue: value.endDate != null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _box(
                    value.endTime == null
                        ? '종료 시간 선택'
                        : '${value.endTime!.hour.toString().padLeft(2, '0')}:'
                              '${value.endTime!.minute.toString().padLeft(2, '0')}',
                    _pickEndTime,
                    hasValue: value.endTime != null,
                  ),
                ),
              ],
            ),
          ..._previewLines(value),
        ],
      ],
    );
  }

  /// [ 날짜 직접 선택 ] [ 파티 시작 전 ] 토글.
  /// 정기 파티는 고정 종료일을 쓸 수 없어 "날짜 직접 선택"이 잠긴다.
  Widget _endTypeToggle(PartyEarlyBird value) {
    Widget tab(PartyEarlyBirdEndType type) {
      final selected = _endType == type;
      final locked =
          widget.isRecurring && type == PartyEarlyBirdEndType.fixedDate;
      return Expanded(
        child: GestureDetector(
          onTap: locked || selected
              ? null
              : () => widget.onChanged(value.copyWith(endType: type)),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: selected ? _kAccent : _kBoxFill,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? _kAccent : const Color(0xFFE8EBF2),
              ),
            ),
            child: Opacity(
              opacity: locked ? 0.4 : 1,
              child: Text(
                type.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : Colors.black54,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            tab(PartyEarlyBirdEndType.fixedDate),
            const SizedBox(width: 8),
            tab(PartyEarlyBirdEndType.beforeStart),
          ],
        ),
        if (widget.isRecurring)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              '매주 반복 파티는 회차마다 날짜가 달라서 "파티 시작 전" 기준만 쓸 수 있어요.',
              style: TextStyle(fontSize: 11.5, color: Colors.black38),
            ),
          ),
      ],
    );
  }

  /// "파티 시작 전" — 숫자 + 단위(일/시간), 일 단위면 종료 시각까지.
  List<Widget> _beforeStartFields(PartyEarlyBird value) {
    final rule = value.beforeStartRule;
    // 예전 문서의 '당일 특정 시각'(sameDayTime)은 '0일 전'과 같은 의미라
    // 일 단위로 보여준다.
    final isHours = rule.mode == EarlyBirdDeadlineMode.hoursBefore;
    return [
      Row(
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              onChanged: (v) {
                final n = int.tryParse(v.trim());
                if (n == null) return;
                widget.onChanged(
                  value.copyWith(
                    beforeStartRule: isHours
                        ? rule.copyWith(hours: n)
                        : rule.copyWith(
                            mode: EarlyBirdDeadlineMode.daysBefore,
                            days: n,
                          ),
                  ),
                );
              },
              decoration: _deco(hint: isHours ? '1~720' : '0~30', suffix: ''),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(flex: 4, child: _unitToggle(value, isHours: isHours)),
        ],
      ),
      // 일 단위는 "며칠 전 몇 시에" 끝낼지까지 정해야 시각이 확정된다.
      if (!isHours) ...[
        const SizedBox(height: 8),
        Row(
          children: [
            const SizedBox(
              width: 88,
              child: Text('종료 시각', style: TextStyle(fontSize: 13)),
            ),
            Expanded(
              child: _box(
                formatScheduleTime(rule.time),
                () => _pickRuleTime(value),
                hasValue: true,
              ),
            ),
          ],
        ),
      ],
    ];
  }

  /// 단위 선택 — 일 / 시간.
  Widget _unitToggle(PartyEarlyBird value, {required bool isHours}) {
    Widget unit(String label, bool selectedWhenHours) {
      final selected = isHours == selectedWhenHours;
      return Expanded(
        child: GestureDetector(
          onTap: selected
              ? null
              : () {
                  final rule = value.beforeStartRule;
                  final next = selectedWhenHours
                      ? rule.copyWith(mode: EarlyBirdDeadlineMode.hoursBefore)
                      : rule.copyWith(mode: EarlyBirdDeadlineMode.daysBefore);
                  _amountCtrl.text = selectedWhenHours
                      ? '${next.hours}'
                      : '${next.days}';
                  widget.onChanged(value.copyWith(beforeStartRule: next));
                },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFF3EFFA) : _kBoxFill,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? _kAccent : const Color(0xFFE8EBF2),
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                color: selected ? _kAccent : Colors.black54,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        unit('일 전', false),
        const SizedBox(width: 6),
        unit('시간 전', true),
      ],
    );
  }

  /// 미리보기 — 언제까지 적용되는지 + (정가를 알면) 실제 얼리버드 참가비.
  List<Widget> _previewLines(PartyEarlyBird value) {
    final lines = <String>[];
    if (_endType == PartyEarlyBirdEndType.beforeStart) {
      final preview = value.beforeStartRule.previewLabelFor(
        isRecurring: widget.isRecurring,
      );
      if (preview.isNotEmpty) lines.add(preview);
    }
    final base = widget.basePrice;
    final pct = value.percent;
    if (base != null && base > 0 && pct != null && pct >= 1 && pct <= 99) {
      final discounted = (base * (100 - pct) / 100).round();
      lines.add(
        '얼리버드 참가비 ${formatPrice(discounted)} (정가 ${formatPrice(base)})',
      );
    }
    if (lines.isEmpty) return const [];
    return [
      const SizedBox(height: 10),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF0F5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  line,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFD94F7A),
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ),
          ],
        ),
      ),
    ];
  }

  InputDecoration _deco({required String hint, required String suffix}) =>
      InputDecoration(
        isDense: true,
        hintText: hint,
        suffixText: suffix,
        hintStyle: const TextStyle(fontSize: 13, color: Colors.black38),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        filled: true,
        fillColor: _kBoxFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      );

  Widget _box(String text, VoidCallback onTap, {required bool hasValue}) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          decoration: BoxDecoration(
            color: _kBoxFill,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: hasValue ? Colors.black87 : Colors.black38,
              fontWeight: hasValue ? FontWeight.w600 : FontWeight.normal,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
}

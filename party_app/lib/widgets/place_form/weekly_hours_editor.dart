import 'package:flutter/material.dart';

import 'package:party_app/models/place_weekly_hours.dart';

/// 요일별 운영시간 편집기 — 휴무·24시간·영업시간·브레이크 타임을 한 위젯에서
/// 다룬다.
///
/// 장소 등록/수정, 플레이스+파티 통합 등록, 술집·바 등록([PlaceHoursSection])이
/// **모두 이 위젯 하나**를 쓴다. 예전에는 화면마다 같은 UI를 따로 붙여 놓아
/// 휴무 체크박스가 어떤 화면에는 있고 어떤 화면에는 없었다.
///
/// [hours]는 가변 객체라 이 위젯이 그 자리에서 고치고 [onChanged]로 다시
/// 그려달라고 알린다(호출부가 들고 있는 인스턴스가 그대로 바뀐다).
class WeeklyHoursEditor extends StatefulWidget {
  final PlaceWeeklyHours hours;
  final VoidCallback onChanged;

  /// 평일/주말 기준 영업시간. 화면이 대표 운영시간(openTime/closeTime)으로도
  /// 쓰기 때문에 값과 선택 콜백은 화면이 들고 있는다.
  final TimeOfDay? weekdayStart;
  final TimeOfDay? weekdayEnd;
  final TimeOfDay? weekendStart;
  final TimeOfDay? weekendEnd;

  /// 기준 시간 칸을 눌렀을 때 — (주말 그룹인가?, 시작 시간인가?).
  final void Function(bool weekend, bool isStart) onPickBaseTime;

  /// 화면마다 다른 시각 표기('19:00' / '오후 7:00')를 그대로 쓴다.
  final String Function(TimeOfDay) formatTime;

  final Color accent;
  final Color accentFill;

  const WeeklyHoursEditor({
    super.key,
    required this.hours,
    required this.onChanged,
    required this.weekdayStart,
    required this.weekdayEnd,
    required this.weekendStart,
    required this.weekendEnd,
    required this.onPickBaseTime,
    required this.formatTime,
    this.accent = const Color(0xFF7C5CBF),
    this.accentFill = const Color(0xFFF3EFFA),
  });

  @override
  State<WeeklyHoursEditor> createState() => _WeeklyHoursEditorState();
}

class _WeeklyHoursEditorState extends State<WeeklyHoursEditor> {
  /// 펼쳐 둔 요일. 기본은 모두 접힘 — 7개를 다 펼쳐 두면 화면이 너무 길어진다.
  final Set<String> _expanded = {};

  /// 평일/주말 그룹에 적용할 기준값 중 **시간 말고** 나머지(휴무·24시간·
  /// 브레이크). 시간은 화면이 들고 있는 값을 적용 순간에 합친다.
  PlaceDayHours _weekdayTemplate = const PlaceDayHours(
    open: TimeOfDay(hour: 10, minute: 0),
    close: TimeOfDay(hour: 22, minute: 0),
  );
  PlaceDayHours _weekendTemplate = const PlaceDayHours(
    open: TimeOfDay(hour: 10, minute: 0),
    close: TimeOfDay(hour: 22, minute: 0),
  );

  static const _border = Color(0xFFE8EBF2);
  static const _fill = Color(0xFFF7F7FA);

  void _msg(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  Future<TimeOfDay?> _pick(TimeOfDay initial) => showTimePicker(
    context: context,
    initialTime: initial,
    builder: (ctx, child) => MediaQuery(
      data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
      child: Theme(
        data: Theme.of(
          ctx,
        ).copyWith(colorScheme: ColorScheme.light(primary: widget.accent)),
        child: child!,
      ),
    ),
  );

  // ── 요일별 ──────────────────────────────────────────────────────────
  Future<void> _pickDayTime(String day, {required bool isOpen}) async {
    final current = widget.hours.get(day)!;
    final picked = await _pick(isOpen ? current.open : current.close);
    if (picked == null || !mounted) return;
    widget.hours.update(
      day,
      (d) => isOpen ? d.copyWith(open: picked) : d.copyWith(close: picked),
    );
    _afterDayChange(day);
  }

  Future<void> _pickDayBreak(String day, {required bool isStart}) async {
    final current = widget.hours.get(day)!;
    final picked = await _pick(isStart ? current.breakStart : current.breakEnd);
    if (picked == null || !mounted) return;
    final next = isStart
        ? current.copyWith(breakStart: picked)
        : current.copyWith(breakEnd: picked);
    // 영업시간을 벗어나는 값은 넣지 않는다 — 왜 막혔는지 바로 알려 준다.
    final error = next.breakError;
    if (error != null) {
      _msg(error);
      return;
    }
    widget.hours.setDay(day, next);
    widget.onChanged();
  }

  /// 영업시간을 고치면 그 안에 있던 브레이크 타임이 밖으로 밀려날 수 있다.
  /// 그때는 브레이크를 새 영업시간 안으로 다시 잡아 주고 무엇이 바뀌었는지
  /// 알려 준다 — "저장은 됐는데 브레이크가 영업시간 밖"인 상태를 남기지 않는다.
  void _afterDayChange(String day) {
    if (widget.hours.get(day)?.breakError != null) {
      widget.hours.update(day, (d) => d.withBreakEnabled(true));
      _msg('$day요일 브레이크 타임을 새 영업시간 안으로 옮겼어요.');
    }
    widget.onChanged();
  }

  // ── 평일/주말 일괄 적용 ─────────────────────────────────────────────
  PlaceDayHours _templateFor(bool weekend) {
    final base = weekend ? _weekendTemplate : _weekdayTemplate;
    final start = weekend ? widget.weekendStart : widget.weekdayStart;
    final end = weekend ? widget.weekendEnd : widget.weekdayEnd;
    return base.copyWith(open: start ?? base.open, close: end ?? base.close);
  }

  bool _canApply(bool weekend) {
    final template = _templateFor(weekend);
    if (template.isClosed) return true;
    if (template.breakError != null) return false;
    if (template.is24Hours) return true;
    final start = weekend ? widget.weekendStart : widget.weekdayStart;
    final end = weekend ? widget.weekendEnd : widget.weekdayEnd;
    return start != null && end != null;
  }

  void _apply(bool weekend) {
    // 휴무·24시간·영업시간·브레이크 타임이 통째로 복사된다.
    widget.hours.applyToDays(
      weekend ? PlaceWeeklyHours.weekendOnly : PlaceWeeklyHours.weekdayOnly,
      _templateFor(weekend),
    );
    widget.onChanged();
    _msg(weekend ? '주말(토·일)에 적용했어요.' : '평일(월~금)에 적용했어요.');
  }

  void _updateTemplate(bool weekend, PlaceDayHours next) => setState(() {
    if (weekend) {
      _weekendTemplate = next;
    } else {
      _weekdayTemplate = next;
    }
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupCard(weekend: false),
        const SizedBox(height: 8),
        _groupCard(weekend: true),
        const SizedBox(height: 8),
        const Text(
          '적용을 누르면 아래 요일별 설정이 한 번에 바뀌어요. 그 뒤 요일별로 따로 수정할 수 있어요.',
          style: TextStyle(fontSize: 11.5, color: Colors.black45, height: 1.4),
        ),
        const SizedBox(height: 14),
        const Text(
          '요일별 운영시간',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ...PlaceWeeklyHours.weekdays.map(_dayCard),
      ],
    );
  }

  // ── 기준 카드 ───────────────────────────────────────────────────────
  Widget _groupCard({required bool weekend}) {
    final template = _templateFor(weekend);
    final ready = _canApply(weekend);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  weekend ? '주말 공통 기준 (토·일)' : '평일 공통 기준 (월~금)',
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
                onPressed: ready ? () => _apply(weekend) : null,
                style: TextButton.styleFrom(
                  foregroundColor: widget.accent,
                  backgroundColor: widget.accentFill,
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
              _toggleChip(
                '휴무',
                template.isClosed,
                () => _updateTemplate(
                  weekend,
                  template.withClosed(!template.isClosed),
                ),
              ),
              const SizedBox(width: 6),
              _toggleChip(
                '24시간',
                template.is24Hours,
                () => _updateTemplate(
                  weekend,
                  template.with24Hours(!template.is24Hours),
                ),
              ),
            ],
          ),
          if (template.isClosed)
            _notice('이 그룹은 휴무로 적용돼요.')
          else ...[
            if (template.is24Hours)
              _notice('24시간 영업으로 적용돼요.')
            else ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _timeBox(
                      label: '시작 시간',
                      time: weekend ? widget.weekendStart : widget.weekdayStart,
                      onTap: () => widget.onPickBaseTime(weekend, true),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('~', style: TextStyle(color: Colors.black54)),
                  ),
                  Expanded(
                    child: _timeBox(
                      label: '종료 시간',
                      time: weekend ? widget.weekendEnd : widget.weekdayEnd,
                      onTap: () => widget.onPickBaseTime(weekend, false),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            _breakSwitch(
              value: template.hasBreakTime,
              onChanged: (v) =>
                  _updateTemplate(weekend, template.withBreakEnabled(v)),
            ),
            if (template.hasBreakTime) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _timeBox(
                      label: '브레이크 시작',
                      time: template.breakStart,
                      onTap: () => _pickTemplateBreak(weekend, isStart: true),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('~', style: TextStyle(color: Colors.black54)),
                  ),
                  Expanded(
                    child: _timeBox(
                      label: '브레이크 종료',
                      time: template.breakEnd,
                      onTap: () => _pickTemplateBreak(weekend, isStart: false),
                    ),
                  ),
                ],
              ),
              if (template.breakError != null) _errorLine(template.breakError!),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _pickTemplateBreak(bool weekend, {required bool isStart}) async {
    final template = _templateFor(weekend);
    final picked = await _pick(
      isStart ? template.breakStart : template.breakEnd,
    );
    if (picked == null || !mounted) return;
    final next = isStart
        ? template.copyWith(breakStart: picked)
        : template.copyWith(breakEnd: picked);
    final error = next.breakError;
    if (error != null) {
      _msg(error);
      return;
    }
    _updateTemplate(weekend, next);
  }

  // ── 요일 카드 ───────────────────────────────────────────────────────
  Widget _dayCard(String day) {
    final value = widget.hours.get(day)!;
    final open = _expanded.contains(day);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: value.isClosed ? const Color(0xFFF4F5F8) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 58,
                child: Text(
                  PlaceWeeklyHours.fullDayName(day),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ),
              _toggleChip('휴무', value.isClosed, () {
                widget.hours.update(day, (d) => d.withClosed(!d.isClosed));
                widget.onChanged();
              }),
              const SizedBox(width: 6),
              _toggleChip('24시간', value.is24Hours, () {
                widget.hours.update(day, (d) => d.with24Hours(!d.is24Hours));
                widget.onChanged();
              }),
              const Spacer(),
              IconButton(
                onPressed: () => setState(
                  () => open ? _expanded.remove(day) : _expanded.add(day),
                ),
                icon: Icon(open ? Icons.expand_less : Icons.expand_more),
                iconSize: 20,
                color: Colors.black45,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: open ? '접기' : '펼치기',
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 접혀 있을 때는 요약 줄만, 펼치면 같은 값을 고칠 수 있는 칸으로
          // 바뀐다 — 같은 시간을 두 번 보여주지 않는다.
          if (!open || value.isClosed) _daySummary(value),
          if (open && !value.isClosed) ...[
            const SizedBox(height: 10),
            if (!value.is24Hours)
              Row(
                children: [
                  Expanded(
                    child: _timeBox(
                      label: '영업 시작',
                      time: value.open,
                      onTap: () => _pickDayTime(day, isOpen: true),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('~', style: TextStyle(color: Colors.black54)),
                  ),
                  Expanded(
                    child: _timeBox(
                      label: '영업 종료',
                      time: value.close,
                      onTap: () => _pickDayTime(day, isOpen: false),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            _breakSwitch(
              value: value.hasBreakTime,
              onChanged: (v) {
                widget.hours.update(day, (d) => d.withBreakEnabled(v));
                widget.onChanged();
              },
            ),
            if (value.hasBreakTime) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _timeBox(
                      label: '브레이크 시작',
                      time: value.breakStart,
                      onTap: () => _pickDayBreak(day, isStart: true),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('~', style: TextStyle(color: Colors.black54)),
                  ),
                  Expanded(
                    child: _timeBox(
                      label: '브레이크 종료',
                      time: value.breakEnd,
                      onTap: () => _pickDayBreak(day, isStart: false),
                    ),
                  ),
                ],
              ),
            ],
          ],
          if (value.breakError != null) _errorLine(value.breakError!),
        ],
      ),
    );
  }

  /// 접혀 있을 때도 그 요일이 어떤 상태인지 한눈에 보이는 줄.
  Widget _daySummary(PlaceDayHours value) {
    if (value.isClosed) {
      return const Text(
        '휴무',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.black45,
        ),
      );
    }
    final hours = value.is24Hours
        ? '24시간 영업'
        : '${widget.formatTime(value.open)} ~ ${widget.formatTime(value.close)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 58,
              child: Text(
                '영업시간',
                style: TextStyle(fontSize: 11.5, color: Colors.black38),
              ),
            ),
            Expanded(
              child: Text(
                hours,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
          ],
        ),
        if (value.hasEffectiveBreak) ...[
          const SizedBox(height: 3),
          Row(
            children: [
              const SizedBox(
                width: 58,
                child: Text(
                  '브레이크',
                  style: TextStyle(fontSize: 11.5, color: Colors.black38),
                ),
              ),
              Expanded(
                child: Text(
                  '${widget.formatTime(value.breakStart)} ~ '
                  '${widget.formatTime(value.breakEnd)}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: widget.accent,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ── 조각 ────────────────────────────────────────────────────────────
  Widget _toggleChip(String text, bool selected, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? widget.accentFill : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? widget.accent : _border,
              width: selected ? 1.2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: 13,
                color: selected ? widget.accent : Colors.black26,
              ),
              const SizedBox(width: 4),
              Text(
                text,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? widget.accent : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _breakSwitch({
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => GestureDetector(
    onTap: () => onChanged(!value),
    child: Row(
      children: [
        SizedBox(
          height: 24,
          width: 38,
          child: FittedBox(
            fit: BoxFit.fill,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: widget.accent,
            ),
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          '브레이크 타임 있음',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );

  Widget _timeBox({
    required String label,
    required TimeOfDay? time,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: time == null ? _border : widget.accent.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10.5, color: Colors.black38),
          ),
          const SizedBox(height: 2),
          Text(
            time == null ? '선택하세요' : widget.formatTime(time),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: time == null ? FontWeight.normal : FontWeight.w600,
              color: time == null ? Colors.black38 : widget.accent,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _notice(String text) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: _fill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: Colors.black54),
      ),
    ),
  );

  Widget _errorLine(String text) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, size: 14, color: Colors.redAccent),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 11.5,
              color: Colors.redAccent,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/widgets/party_form/wheel_duration_picker_sheet.dart';
import 'package:party_app/widgets/party_form/wheel_time_picker_sheet.dart';

const _kAccent = Color(0xFFFF6FA0);
const _kBoxFill = Color(0xFFF7F7FA);

/// 모집 시작/마감 규칙 입력 — 날짜 직접 선택 시트와 정기 일정 시트가 **같은
/// 위젯**을 쓴다. 어느 화면에서 고르든 저장되는 규칙([PartyRecruitDeadlineRule])이
/// 같으므로, 등록·수정·임시저장·재등록이 서로 어긋나지 않는다.
///
/// 방식마다 "무엇을 기준으로 언제 열리고 닫히는지"를 이름에 못박고, 실제로
/// 계산된 일시를 항상 아래에 함께 보여준다 — 밤에 시작해 다음 날 새벽에 끝나는
/// 파티에서 "당일"이 어느 날인지 헷갈리던 문제를 없애기 위한 것이다.
///
/// 화면 문구는 전부 [kind] 하나에서 나온다. 모집 시작을 편집하는데 '마감 날짜'
/// 같은 반대편 용어가 섞이지 않도록, 칩·입력칸·피커 제목·안내를 한 곳에서
/// 갈아 끼운다.
class RecruitDeadlineEditor extends StatefulWidget {
  final PartyRecruitDeadlineRule value;
  final ValueChanged<PartyRecruitDeadlineRule> onChanged;

  /// 지금 편집 중인 쪽 — 모집 시작인지 모집 마감인지.
  final PartyRecruitRuleKind kind;

  /// 마감 일시 미리보기의 기준이 되는 회차. 아직 일정 입력이 없으면 null이고,
  /// 그때는 미리보기 대신 안내만 보여준다.
  final DateTime? referenceStart;
  final DateTime? referenceEnd;

  /// 정기 파티는 회차마다 날짜가 달라 고정 날짜 마감을 쓸 수 없다.
  final bool allowCustomDateTime;

  /// 미리보기 앞에 붙는 말 — 정기 파티는 '다음 회차 기준' 같은 걸 넣는다.
  final String? previewPrefix;

  /// [PartyDeadlineMode.none]을 골랐을 때 보여줄 문구.
  final String noneNotice;

  /// 시각이 파티 시작 이후로 잡혔을 때 띄울 안내. null이면 확인 절차도 경고도
  /// 띄우지 않는다(시작 이후가 정상인 화면용).
  final String? afterStartNotice;

  const RecruitDeadlineEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.kind = PartyRecruitRuleKind.close,
    this.referenceStart,
    this.referenceEnd,
    this.allowCustomDateTime = true,
    this.previewPrefix,
    this.noneNotice = '파티가 시작될 때까지 계속 신청받아요.',
    this.afterStartNotice = '파티 시작 후에도 참가 신청을 받습니다.',
  });

  @override
  State<RecruitDeadlineEditor> createState() => _RecruitDeadlineEditorState();
}

class _RecruitDeadlineEditorState extends State<RecruitDeadlineEditor> {
  /// 숫자 칸이 지금 '분'인지 '시간'인지. 값 자체는 언제나 분으로 저장되고,
  /// 이 토글은 입력 편의를 위한 화면 상태일 뿐이다.
  late bool _hourUnit = _looksLikeHours(widget.value.minutesBefore);
  late final TextEditingController _numberCtrl = TextEditingController(
    text: '${_numberFor(widget.value.minutesBefore)}',
  );

  static bool _looksLikeHours(int minutes) =>
      minutes >= 60 && minutes % 60 == 0;

  int _numberFor(int minutes) => _hourUnit ? minutes ~/ 60 : minutes;

  @override
  void didUpdateWidget(RecruitDeadlineEditor old) {
    super.didUpdateWidget(old);
    // 밖에서 값이 바뀌었을 때만 칸을 다시 맞춘다 — 타이핑 중에 커서가 튀지
    // 않도록, 지금 칸에 적힌 숫자가 이미 그 값이면 건드리지 않는다.
    final minutes = widget.value.minutesBefore;
    if (old.value.minutesBefore == minutes) return;
    if (_numberFor(minutes) == int.tryParse(_numberCtrl.text)) return;
    _hourUnit = _looksLikeHours(minutes);
    _numberCtrl.text = '${_numberFor(minutes)}';
  }

  @override
  void dispose() {
    _numberCtrl.dispose();
    super.dispose();
  }

  PartyRecruitDeadlineRule get _rule => widget.value;

  /// 이 편집기가 쓰는 모든 문구의 출처 — 시작/마감 용어가 섞이지 않게 한다.
  PartyRecruitRuleKind get _kind => widget.kind;

  void _setMinutes(int minutes) {
    final clamped = minutes.clamp(0, kMaxDeadlineMinutesBefore);
    widget.onChanged(_rule.copyWith(minutesBefore: clamped));
  }

  void _setMode(PartyDeadlineMode mode) {
    if (mode == _rule.mode) return;
    // '직접 지정'으로 옮길 땐 기준 회차 시작 시각을 첫 값으로 채워 준다 —
    // 빈 칸으로 두면 무엇을 고르는 중인지 알 수 없다.
    if (mode == PartyDeadlineMode.customDateTime && _rule.customAt == null) {
      final base = widget.referenceStart ?? DateTime.now();
      widget.onChanged(
        _rule.copyWith(
          mode: mode,
          customAt: DateTime(
            base.year,
            base.month,
            base.day,
            base.hour,
            base.minute,
          ),
        ),
      );
      return;
    }
    widget.onChanged(_rule.copyWith(mode: mode));
  }

  Future<void> _pickWithWheel() async {
    final picked = await showWheelDurationPicker(
      context,
      initialMinutes: _rule.minutesBefore,
      title: _kind.beforeStartPickerTitle,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _hourUnit = _looksLikeHours(picked);
      _numberCtrl.text = '${_hourUnit ? picked ~/ 60 : picked}';
    });
    _setMinutes(picked);
  }

  void _toggleUnit(bool hourUnit) {
    if (hourUnit == _hourUnit) return;
    final minutes = _rule.minutesBefore;
    // 단위를 바꾸면 지금 값을 그 단위로 옮겨 담는다. 시간으로 바꿀 때 남는
    // 분은 버려지므로(90분 → 1시간) 결과를 아래 문구로 바로 확인할 수 있다.
    final nextNumber = hourUnit ? (minutes ~/ 60) : minutes;
    setState(() {
      _hourUnit = hourUnit;
      _numberCtrl.text = '$nextNumber';
    });
    _setMinutes(hourUnit ? nextNumber * 60 : nextNumber);
  }

  void _onNumberChanged(String text) {
    final n = int.tryParse(text.trim());
    if (n == null) return;
    _setMinutes(_hourUnit ? n * 60 : n);
  }

  Future<void> _pickDayTime() async {
    final picked = await showWheelTimePicker(
      context,
      initial: _rule.dayTime,
      title: _kind.dayTimeFieldLabel(
        prevDay: _rule.mode == PartyDeadlineMode.prevDayTime,
      ),
    );
    if (picked == null || !mounted) return;
    widget.onChanged(_rule.copyWith(dayTime: picked));
  }

  // ── 직접 지정(날짜·시각 직접 고르기) ─────────────────────────────────
  DateTime get _customBase =>
      _rule.customAt ?? widget.referenceStart ?? DateTime.now();

  Future<void> _pickCustomDate() async {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, now.day);
    final base = _customBase;
    final picked = await showDatePicker(
      context: context,
      initialDate: base.isBefore(first) ? first : base,
      firstDate: first,
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null || !mounted) return;
    await _commitCustom(
      DateTime(picked.year, picked.month, picked.day, base.hour, base.minute),
    );
  }

  Future<void> _pickCustomTime() async {
    final base = _customBase;
    final picked = await showWheelTimePicker(
      context,
      initial: TimeOfDay(hour: base.hour, minute: base.minute),
      title: _kind.isOpen ? '모집 시작 시각' : '모집 마감 시각',
    );
    if (picked == null || !mounted) return;
    await _commitCustom(
      DateTime(base.year, base.month, base.day, picked.hour, picked.minute),
    );
  }

  /// 직접 고른 시각을 확정한다.
  ///
  /// 회차 종료 뒤로는 잡을 수 없고(이미 끝난 파티를 모집할 수는 없다),
  /// 시작 이후라면 "시작 후에도 신청을 받는다"는 걸 한 번 확인받는다.
  Future<void> _commitCustom(DateTime at) async {
    final end = widget.referenceEnd;
    if (end != null && at.isAfter(end)) {
      _msg(
        '파티가 끝나는 ${formatPartyDeadlineAt(end)}까지만 '
        '${_kind.isOpen ? '모집 시작을' : '모집 마감을'} 잡을 수 있어요.',
      );
      return;
    }
    final start = widget.referenceStart;
    final notice = widget.afterStartNotice;
    if (notice != null && start != null && at.isAfter(start)) {
      final ok = await _confirmAfterStart(at, notice);
      if (!ok || !mounted) return;
    }
    widget.onChanged(_rule.copyWith(customAt: at));
  }

  Future<bool> _confirmAfterStart(DateTime at, String notice) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(notice),
        content: Text(
          '${formatPartyDeadlineAt(at)}로 잡으면 파티가 시작된 뒤의 시각이 돼요. '
          '이대로 설정할까요?',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: _kAccent),
            child: const Text('이대로 설정'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _msg(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  // ── 조각 위젯 ───────────────────────────────────────────────────────
  Widget _modeChip(PartyDeadlineMode mode) {
    final selected = _rule.mode == mode;
    return GestureDetector(
      onTap: () => _setMode(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF0F5) : _kBoxFill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? _kAccent : const Color(0xFFE8EBF2),
          ),
        ),
        child: Text(
          mode.shortLabel,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? _kAccent : Colors.black54,
          ),
        ),
      ),
    );
  }

  Widget _box(String text, VoidCallback onTap, {String? label}) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: _kBoxFill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null) ...[
            Text(
              label,
              style: const TextStyle(fontSize: 10.5, color: Colors.black38),
            ),
            const SizedBox(height: 2),
          ],
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _unitButton(String text, bool hourUnit) {
    final selected = _hourUnit == hourUnit;
    return GestureDetector(
      onTap: () => _toggleUnit(hourUnit),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _kAccent : Colors.white,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : Colors.black45,
          ),
        ),
      ),
    );
  }

  Widget _beforeStartBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 78,
              child: TextField(
                controller: _numberCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: _kBoxFill,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: _onNumberChanged,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: _kBoxFill,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  _unitButton('분 전', false),
                  _unitButton('시간 전', true),
                ],
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _pickWithWheel,
              icon: const Icon(Icons.unfold_more, size: 16),
              label: const Text('휠 선택'),
              style: TextButton.styleFrom(
                foregroundColor: _kAccent,
                backgroundColor: const Color(0xFFFFF0F5),
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${formatMinutesBeforeStart(_rule.minutesBefore)}'
          '${_kind.isOpen ? '부터 모집 시작' : '에 모집 마감'}',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _kAccent,
          ),
        ),
      ],
    );
  }

  Widget _customBody() {
    final at = _rule.customAt;
    return Row(
      children: [
        Expanded(
          child: _box(
            at == null
                ? '날짜 선택'
                : '${at.year}.${at.month.toString().padLeft(2, '0')}.'
                      '${at.day.toString().padLeft(2, '0')}',
            _pickCustomDate,
            label: _kind.dateFieldLabel,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _box(
            at == null
                ? '시간 선택'
                : formatKoreanTimeOfDay(
                    TimeOfDay(hour: at.hour, minute: at.minute),
                  ),
            _pickCustomTime,
            label: _kind.timeFieldLabel,
          ),
        ),
      ],
    );
  }

  /// 규칙을 기준 회차에 적용한 실제 일시 한 줄.
  Widget _preview() {
    if (_rule.isNone) {
      return Text(
        widget.noneNotice,
        style: const TextStyle(
          fontSize: 12,
          color: Colors.black45,
          height: 1.5,
        ),
      );
    }
    final start = widget.referenceStart;
    if (start == null) {
      return Text(
        '일정을 먼저 정하면 실제 ${_kind.term} 일시를 여기에 보여드려요.',
        style: const TextStyle(
          fontSize: 12,
          color: Colors.black45,
          height: 1.5,
        ),
      );
    }
    final at = _rule.resolve(start, occurrenceEnd: widget.referenceEnd);
    if (at == null) {
      return Text(
        '${_kind.term} 시각을 선택해주세요.',
        style: const TextStyle(
          fontSize: 12,
          color: Colors.black45,
          height: 1.5,
        ),
      );
    }
    final notice = widget.afterStartNotice;
    final afterStart = notice != null && at.isAfter(start);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF0F5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kAccent.withValues(alpha: 0.35)),
          ),
          child: Text(
            '${widget.previewPrefix == null ? '' : '${widget.previewPrefix} '}'
            '${formatPartyDeadlineAt(at)} ${_kind.term}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _kAccent,
            ),
          ),
        ),
        if (afterStart) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline,
                size: 14,
                color: Color(0xFFB45309),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  notice,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFB45309),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final modes = [
      PartyDeadlineMode.beforeStart,
      PartyDeadlineMode.startDayTime,
      PartyDeadlineMode.prevDayTime,
      if (widget.allowCustomDateTime) PartyDeadlineMode.customDateTime,
      PartyDeadlineMode.none,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final mode in modes) _modeChip(mode)],
        ),
        const SizedBox(height: 8),
        // 칩 이름은 짧게 줄여 두므로, 고른 방식의 뜻을 한 줄로 풀어 준다.
        Text(
          _rule.mode.labelFor(_kind),
          style: const TextStyle(fontSize: 11.5, color: Colors.black45),
        ),
        const SizedBox(height: 10),
        switch (_rule.mode) {
          PartyDeadlineMode.beforeStart => _beforeStartBody(),
          PartyDeadlineMode.startDayTime ||
          PartyDeadlineMode.prevDayTime => _box(
            formatKoreanTimeOfDay(_rule.dayTime),
            _pickDayTime,
            label: _kind.dayTimeFieldLabel(
              prevDay: _rule.mode == PartyDeadlineMode.prevDayTime,
            ),
          ),
          PartyDeadlineMode.customDateTime => _customBody(),
          PartyDeadlineMode.none => const SizedBox.shrink(),
        },
        if (!_rule.isNone) const SizedBox(height: 10),
        _preview(),
      ],
    );
  }
}

/// 모집 시작/마감 규칙 하나를 감싸는 카드.
///
/// 두 규칙이 한 화면에 세로로 붙어 있으면 어느 칩·어느 미리보기가 어느 쪽
/// 것인지 헷갈린다. 제목 줄과 테두리로 영역을 확실히 끊고, 지금 정하는 시점이
/// 무엇인지 한 줄로 알려 준다.
class RecruitRuleCard extends StatelessWidget {
  final String title;

  /// 제목 아래 한 줄 — '언제부터 신청을 받을지 정해요.'처럼.
  final String subtitle;

  final Widget child;

  const RecruitRuleCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EBF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: _kAccent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11.5, color: Colors.black45),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, thickness: 1, color: Color(0xFFF0F2F7)),
          ),
          child,
        ],
      ),
    );
  }
}

/// 모집 시작/마감 규칙을 바텀시트로 고르게 한다.
///
/// 차수 카드처럼 한 화면에 규칙이 여러 개 들어가는 곳에서 쓴다 — 편집기를
/// 카드마다 펼쳐 두면 카드가 너무 길어져서, 요약 한 줄만 두고 누르면 이
/// 시트가 열리도록 했다. 돌려주는 값은 확인을 누른 규칙(취소면 null).
Future<PartyRecruitDeadlineRule?> showRecruitRuleSheet(
  BuildContext context, {
  required String title,
  required PartyRecruitDeadlineRule initial,
  PartyRecruitRuleKind kind = PartyRecruitRuleKind.close,
  DateTime? referenceStart,
  DateTime? referenceEnd,
  bool allowCustomDateTime = true,
  String noneNotice = '파티가 시작될 때까지 계속 신청받아요.',
  String? afterStartNotice = '파티 시작 후에도 참가 신청을 받습니다.',
  String? description,
}) {
  return showModalBottomSheet<PartyRecruitDeadlineRule>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _RecruitRuleSheet(
      title: title,
      initial: initial,
      kind: kind,
      referenceStart: referenceStart,
      referenceEnd: referenceEnd,
      allowCustomDateTime: allowCustomDateTime,
      noneNotice: noneNotice,
      afterStartNotice: afterStartNotice,
      description: description,
    ),
  );
}

class _RecruitRuleSheet extends StatefulWidget {
  final String title;
  final PartyRecruitDeadlineRule initial;
  final PartyRecruitRuleKind kind;
  final DateTime? referenceStart;
  final DateTime? referenceEnd;
  final bool allowCustomDateTime;
  final String noneNotice;
  final String? afterStartNotice;
  final String? description;

  const _RecruitRuleSheet({
    required this.title,
    required this.initial,
    required this.kind,
    required this.referenceStart,
    required this.referenceEnd,
    required this.allowCustomDateTime,
    required this.noneNotice,
    required this.afterStartNotice,
    required this.description,
  });

  @override
  State<_RecruitRuleSheet> createState() => _RecruitRuleSheetState();
}

class _RecruitRuleSheetState extends State<_RecruitRuleSheet> {
  late PartyRecruitDeadlineRule _rule = widget.initial;

  @override
  Widget build(BuildContext context) {
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
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (widget.description != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    widget.description!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black45,
                      height: 1.5,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                RecruitDeadlineEditor(
                  value: _rule,
                  onChanged: (next) => setState(() => _rule = next),
                  referenceStart: widget.referenceStart,
                  referenceEnd: widget.referenceEnd,
                  kind: widget.kind,
                  allowCustomDateTime: widget.allowCustomDateTime,
                  noneNotice: widget.noneNotice,
                  afterStartNotice: widget.afterStartNotice,
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, _rule),
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

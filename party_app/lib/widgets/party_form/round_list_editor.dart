import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:party_app/models/party_early_bird_schedule.dart';
import 'package:party_app/models/party_round.dart';
import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/widgets/party_form/recruit_deadline_editor.dart';
import 'package:party_app/widgets/party_form/register_field_anchor.dart';
import 'package:party_app/widgets/party_form/wheel_time_picker_sheet.dart';

const _kAccent = Color(0xFFFF6FA0);
const _kError = Color(0xFFE53935);

/// 2차 이상 차수 한 건의 입력 상태.
///
/// 값 자체는 불변 모델 [PartyRound]가 들고, 이 클래스는 텍스트 칸의 컨트롤러와
/// 스크롤 앵커만 얹는다 — 등록 화면은 [round]만 읽어 저장하면 된다.
class PartyRoundDraft {
  /// 검증에 걸렸을 때 이 카드까지 자동으로 스크롤하기 위한 앵커.
  final GlobalKey anchorKey = GlobalKey();

  PartyRound round;

  final TextEditingController labelCtrl;
  final TextEditingController minCapacityCtrl;
  final TextEditingController capacityCtrl;
  final TextEditingController maleCapacityCtrl;
  final TextEditingController femaleCapacityCtrl;
  final TextEditingController maleFeeCtrl;
  final TextEditingController femaleFeeCtrl;
  final TextEditingController earlyBirdPercentCtrl;

  PartyRoundDraft(this.round)
    : labelCtrl = TextEditingController(text: round.label),
      minCapacityCtrl = TextEditingController(text: _num(round.minCapacity)),
      capacityCtrl = TextEditingController(text: _num(round.maxCapacity)),
      maleCapacityCtrl = TextEditingController(text: _num(round.maleCapacity)),
      femaleCapacityCtrl = TextEditingController(
        text: _num(round.femaleCapacity),
      ),
      maleFeeCtrl = TextEditingController(text: _num(round.maleFee)),
      femaleFeeCtrl = TextEditingController(text: _num(round.femaleFee)),
      earlyBirdPercentCtrl = TextEditingController(
        text: round.earlyBird.percent?.toString() ?? '',
      );

  factory PartyRoundDraft.empty() =>
      PartyRoundDraft(PartyRound(id: PartyRound.newId()));

  static String _num(int v) => v == 0 ? '' : '$v';

  String get id => round.id;

  /// 다른 차수 설정을 복사해 넣는다 — 텍스트 칸도 함께 다시 채운다.
  void applySettingsFrom(PartyRound source) {
    round = round.copyingSettingsFrom(source);
    minCapacityCtrl.text = _num(round.minCapacity);
    capacityCtrl.text = _num(round.maxCapacity);
    maleCapacityCtrl.text = _num(round.maleCapacity);
    femaleCapacityCtrl.text = _num(round.femaleCapacity);
    maleFeeCtrl.text = _num(round.maleFee);
    femaleFeeCtrl.text = _num(round.femaleFee);
    earlyBirdPercentCtrl.text = round.earlyBird.percent?.toString() ?? '';
  }

  void dispose() {
    labelCtrl.dispose();
    minCapacityCtrl.dispose();
    capacityCtrl.dispose();
    maleCapacityCtrl.dispose();
    femaleCapacityCtrl.dispose();
    maleFeeCtrl.dispose();
    femaleFeeCtrl.dispose();
    earlyBirdPercentCtrl.dispose();
  }
}

/// 2차 이상 차수 목록 편집 위젯.
///
/// 차수마다 모집 시작·모집 마감·파티 시작·파티 종료·정원·참가비·얼리버드를
/// 따로 잡을 수 있고, 카드 머리에 지금 상태(모집 예정/모집 중/…)와 계산된
/// 실제 일시를 함께 보여준다. 순서 변경은 없다 — 차수는 항상 시간순이라
/// index+2로 번호를 매긴다.
class RoundListEditor extends StatefulWidget {
  final List<PartyRoundDraft> rounds;

  /// 'unified'면 정원·참가비를 1차 값에 맞추고, 'perRound'면 차수마다 받는다.
  final String roundCapacityMode;

  /// 'unlimited' | 'separate'
  final String genderCapacityMode;

  /// 1차(위 일정·정원·참가비 섹션)의 설정 — '1차 설정 복사'와 상태 표시의
  /// 기준이다. 아직 일정을 안 골랐으면 null.
  final PartyRound? primaryRound;

  /// 상태·일시 계산의 기준 날짜(첫 일정의 날짜). 없으면 미리보기를 감춘다.
  final DateTime? referenceDate;

  final VoidCallback onChanged;

  /// 차수 id → 문제가 난 칸. 등록 버튼을 눌렀을 때 검증이 채워주며, 해당
  /// 칸에만 빨간 테두리와 안내 문구를 그린다.
  final Map<String, List<PartyRoundIssue>> errors;

  /// '모든 차수 동일'일 때 차수 목록 **위**에 그릴 공통 정원·참가비 입력.
  ///
  /// 위젯을 통째로 받는 이유는 그 입력들이 등록 화면의 기존 상태(정원·참가비
  /// 컨트롤러)를 그대로 쓰기 때문이다 — 값을 이 위젯으로 옮기면 저장·검증
  /// 경로가 둘로 갈라진다. 넘기지 않으면 예전처럼 안내 문구만 나온다.
  final Widget? commonSettings;

  /// '차수별 설정'일 때 **1차 카드 안**에 그릴 정원·참가비·얼리버드 입력.
  /// [commonSettings]와 같은 이유로 위젯을 그대로 받는다.
  final Widget? primarySettings;

  /// 'none' | 'uniform' | 'perRound' — 차수 카드에 얼리버드 입력을 그릴지.
  /// 기본값은 예전 동작(차수마다 따로).
  final String earlyBirdMode;

  const RoundListEditor({
    super.key,
    required this.rounds,
    required this.roundCapacityMode,
    required this.genderCapacityMode,
    required this.onChanged,
    this.primaryRound,
    this.referenceDate,
    this.errors = const {},
    this.commonSettings,
    this.primarySettings,
    this.earlyBirdMode = 'perRound',
  });

  @override
  State<RoundListEditor> createState() => RoundListEditorState();
}

class RoundListEditorState extends State<RoundListEditor> {
  bool get _perRound => widget.roundCapacityMode == 'perRound';
  bool get _separate => widget.genderCapacityMode == 'separate';

  void _notify() {
    widget.onChanged();
    setState(() {});
  }

  void addRound() {
    final draft = PartyRoundDraft.empty();
    // 새 차수는 1차(또는 직전 차수) 설정을 물려받아 시작한다 — 그대로 쓰거나
    // 시간만 고치면 되므로 입력이 훨씬 빠르다.
    final source = widget.rounds.isNotEmpty
        ? widget.rounds.last.round
        : widget.primaryRound;
    if (source != null) {
      draft.applySettingsFrom(source);
      // 같은 시각이 두 번 잡히면 헷갈리므로 2시간 뒤로 밀어 둔다.
      draft.round = draft.round.copyWith(
        startTime: _shift(source.startTime, hours: 2),
        endTime: source.endTime == null
            ? null
            : _shift(source.endTime!, hours: 2),
      );
    }
    widget.rounds.add(draft);
    _notify();
  }

  static TimeOfDay _shift(TimeOfDay t, {required int hours}) =>
      TimeOfDay(hour: (t.hour + hours) % 24, minute: t.minute);

  void _removeRound(int i) {
    widget.rounds.removeAt(i).dispose();
    _notify();
  }

  void _update(PartyRoundDraft d, PartyRound next) {
    setState(() => d.round = next);
    widget.onChanged();
  }

  void _copyFromPrimary(PartyRoundDraft d) {
    final source = widget.primaryRound;
    if (source == null) {
      _msg('먼저 위에서 1차 일정·인원·참가비를 정해주세요.');
      return;
    }
    setState(() => d.applySettingsFrom(source));
    widget.onChanged();
    _msg('1차 설정을 복사했어요. 필요한 값만 고치면 됩니다.');
  }

  void _msg(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _pickTime(PartyRoundDraft d, {required bool isStart}) async {
    final r = d.round;
    final picked = await showWheelTimePicker(
      context,
      initial: isStart
          ? r.startTime
          : (r.endTime ?? _shift(r.startTime, hours: 2)),
      title: isStart ? '차수 시작 시간' : '차수 종료 시간',
    );
    if (picked == null || !mounted) return;
    _update(
      d,
      isStart ? r.copyWith(startTime: picked) : r.copyWith(endTime: picked),
    );
  }

  Future<void> _pickRule(
    PartyRoundDraft d, {
    required bool isOpen,
    required int roundNumber,
  }) async {
    final r = d.round;
    final date = widget.referenceDate;
    final w = date == null ? null : r.resolveOn(date);
    final picked = await showRecruitRuleSheet(
      context,
      title: isOpen ? '$roundNumber차 모집 시작' : '$roundNumber차 모집 마감',
      initial: isOpen ? r.openRule : r.closeRule,
      kind: isOpen ? PartyRecruitRuleKind.open : PartyRecruitRuleKind.close,
      referenceStart: w?.start,
      referenceEnd: w?.end,
      noneNotice: isOpen ? '등록하는 즉시 이 차수 신청을 받아요.' : '이 차수가 시작될 때까지 계속 신청받아요.',
      afterStartNotice: isOpen
          ? '파티 시작 후에 모집이 열립니다.'
          : '파티 시작 후에도 참가 신청을 받습니다.',
      description: isOpen
          ? '이 차수의 시작 시각을 기준으로 언제부터 신청을 받을지 정해요.'
          : '이 차수의 시작 시각을 기준으로 언제 신청을 닫을지 정해요.',
    );
    if (picked == null || !mounted) return;
    _update(
      d,
      isOpen ? r.copyWith(openRule: picked) : r.copyWith(closeRule: picked),
    );
  }

  // ── 숫자 칸 ─────────────────────────────────────────────────────────
  int _parse(String s) => int.tryParse(s.trim()) ?? 0;

  void _onCapacityChanged(PartyRoundDraft d) => _update(
    d,
    d.round.copyWith(
      minCapacity: _parse(d.minCapacityCtrl.text),
      maxCapacity: _parse(d.capacityCtrl.text),
      maleCapacity: _parse(d.maleCapacityCtrl.text),
      femaleCapacity: _parse(d.femaleCapacityCtrl.text),
    ),
  );

  void _onFeeChanged(PartyRoundDraft d) => _update(
    d,
    d.round.copyWith(
      maleFee: _parse(d.maleFeeCtrl.text),
      femaleFee: _parse(d.femaleFeeCtrl.text),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 모든 차수가 같은 정원·참가비를 쓰는 모드에서는 그 값을 **여기 한 번**
        // 받는다. 차수 카드마다 같은 칸을 그리면 어느 쪽이 정본인지 알 수 없다.
        if (widget.commonSettings case final common?) ...[
          common,
          const SizedBox(height: 12),
        ],
        _primaryCard(),
        ...List.generate(widget.rounds.length, _roundCard),
        GestureDetector(
          onTap: addRound,
          child: Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3F7),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kAccent.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add, size: 16, color: _kAccent),
                const SizedBox(width: 4),
                Text(
                  '${widget.rounds.length + 2}차 추가하기',
                  style: const TextStyle(
                    fontSize: 13,
                    color: _kAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 1차 카드.
  ///
  /// 일정(시작·종료 시각과 모집 창구)은 파티 일정 그 자체라 위 '일정' 섹션이
  /// 정본이고 여기서는 계산된 결과만 보여준다 — 여기서 따로 받으면 문서의
  /// `partyDateTime`과 `rounds[0].time`이 갈라진다.
  ///
  /// 정원·참가비·얼리버드는 [primarySettings]로 받아 **이 카드 안에서** 고친다
  /// (2차 이후 카드와 같은 자리). 넘어오지 않으면 예전처럼 요약만 보여준다.
  Widget _primaryCard() {
    final primary = widget.primaryRound;
    final date = widget.referenceDate;
    final window = (primary != null && date != null)
        ? primary.resolveOn(date)
        : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EBF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '1차',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(width: 6),
              if (window != null) _statusBadge(window),
            ],
          ),
          const SizedBox(height: 6),
          if (window != null)
            _windowSummary(window)
          else
            Text(
              widget.primarySettings != null || widget.commonSettings != null
                  ? '위에서 날짜와 시간을 정하면 1차 일정이 잡혀요.'
                  : '위에서 일정·모집 인원·참가비를 정하면 1차가 됩니다.',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black45,
                height: 1.4,
              ),
            ),
          const SizedBox(height: 6),
          Text(
            switch ((widget.primarySettings, widget.commonSettings)) {
              // 차수별 설정 — 1차도 이 카드 안에서 정원·참가비를 받는다.
              (final _?, _) => '1차 시간과 모집 마감은 위 일정 설정을 그대로 씁니다.',
              // 모든 차수 동일 — 인원·참가비는 위 공통 칸 하나가 정본이다.
              (null, final _?) =>
                '1차 시간과 모집 마감은 위 일정 설정을, 인원·참가비는 위 공통 설정을 씁니다.',
              _ =>
                '1차는 위 일정·모집 마감·인원·참가비 설정을 그대로 씁니다. '
                    '여기서는 2차부터 추가하세요.',
            },
            style: const TextStyle(
              fontSize: 11.5,
              color: Colors.black45,
              height: 1.4,
            ),
          ),
          if (widget.primarySettings case final settings?) ...[
            const SizedBox(height: 10),
            settings,
          ],
        ],
      ),
    );
  }

  Widget _statusBadge(PartyRoundWindow w) {
    final status = w.statusAt(DateTime.now());
    final (bg, fg) = switch (status) {
      PartyRoundStatus.upcoming => (
        const Color(0xFFEEF2FF),
        const Color(0xFF4F46E5),
      ),
      PartyRoundStatus.open => (
        const Color(0xFFECFDF5),
        const Color(0xFF047857),
      ),
      PartyRoundStatus.closed => (
        const Color(0xFFF3F4F6),
        const Color(0xFF6B7280),
      ),
      PartyRoundStatus.ongoing => (
        const Color(0xFFFFF7ED),
        const Color(0xFFB45309),
      ),
      PartyRoundStatus.ended => (
        const Color(0xFFF3F4F6),
        const Color(0xFF9CA3AF),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  /// 계산된 실제 일시 두 줄 — 무엇이 저장될지 눈으로 확인하는 곳이다.
  Widget _windowSummary(PartyRoundWindow w) {
    String at(DateTime? d) => d == null ? '제한 없음' : formatPartyDeadlineAt(d);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '파티  ${formatPartyDeadlineAt(w.start)} ~ ${formatPartyDeadlineAt(w.end)}',
          style: const TextStyle(
            fontSize: 12,
            color: Colors.black87,
            height: 1.5,
          ),
        ),
        Text(
          '모집  ${at(w.recruitOpenAt)} ~ ${at(w.recruitCloseAt)}',
          style: const TextStyle(
            fontSize: 12,
            color: Colors.black87,
            height: 1.5,
          ),
        ),
        if (w.acceptsAfterStart)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 13, color: Color(0xFFB45309)),
                SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '파티 시작 후에도 참가 신청을 받습니다.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFFB45309),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _roundCard(int i) {
    final d = widget.rounds[i];
    final r = d.round;
    final roundNumber = i + 2;
    final issues = widget.errors[d.id] ?? const <PartyRoundIssue>[];
    bool has(PartyRoundField f) => issues.any((e) => e.field == f);
    final date = widget.referenceDate;
    final window = date == null ? null : r.resolveOn(date);

    // 필수항목 안내가 "2차 모집 인원을 입력해주세요" 같은 문구로 데려오는
    // 자리다 — 도착하면 이 카드에 잠깐 분홍 테두리가 켜진다.
    return RegisterFieldAnchor(
      key: d.anchorKey,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: issues.isEmpty
              ? const Color(0xFFFAFAFC)
              : const Color(0xFFFFF5F5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: issues.isEmpty ? const Color(0xFFE8EBF2) : _kError,
            width: issues.isEmpty ? 1 : 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '$roundNumber차',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: _kAccent,
                  ),
                ),
                const SizedBox(width: 6),
                if (window != null) _statusBadge(window),
                const Spacer(),
                TextButton(
                  onPressed: () => _copyFromPrimary(d),
                  style: TextButton.styleFrom(
                    foregroundColor: _kAccent,
                    backgroundColor: const Color(0xFFFFF0F5),
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                  child: const Text(
                    '1차 설정 복사',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: Colors.redAccent,
                  ),
                  onPressed: () => _removeRound(i),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            TextField(
              controller: d.labelCtrl,
              onChanged: (v) => _update(d, r.copyWith(label: v)),
              decoration: _deco('차수 이름 (선택, 예: 술집)'),
            ),

            // ── 파티 시작 / 종료 ────────────────────────────────────────
            const SizedBox(height: 10),
            _sectionLabel('파티 시간'),
            Row(
              children: [
                Expanded(
                  child: _timeBox(
                    '시작',
                    r.startTime,
                    () => _pickTime(d, isStart: true),
                    error: has(PartyRoundField.schedule),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('~'),
                ),
                Expanded(
                  child: _timeBox(
                    '종료',
                    r.endTime,
                    () => _pickTime(d, isStart: false),
                    error: has(PartyRoundField.schedule),
                  ),
                ),
              ],
            ),

            // ── 모집 시작 / 마감 ────────────────────────────────────────
            const SizedBox(height: 10),
            _sectionLabel('모집 기간'),
            _ruleRow(
              '모집 시작',
              r.openRule.isNone ? '제한 없음 (바로 모집)' : r.openRule.label,
              () => _pickRule(d, isOpen: true, roundNumber: roundNumber),
              error: has(PartyRoundField.recruit),
            ),
            const SizedBox(height: 6),
            _ruleRow(
              '모집 마감',
              r.closeRule.isNone ? '이 차수 시작까지' : r.closeRule.label,
              () => _pickRule(d, isOpen: false, roundNumber: roundNumber),
              error: has(PartyRoundField.recruit),
            ),

            // ── 정원 / 참가비 ───────────────────────────────────────────
            const SizedBox(height: 10),
            if (_perRound) ...[
              _sectionLabel('모집 인원 · 참가비'),
              // 최소 인원은 성별 모드와 무관하게 "이 차수 전체" 기준이다.
              TextField(
                controller: d.minCapacityCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => _onCapacityChanged(d),
                decoration: _deco(
                  '최소 인원 (선택)',
                  error: has(PartyRoundField.capacity),
                ),
              ),
              const SizedBox(height: 8),
              if (!_separate)
                TextField(
                  controller: d.capacityCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => _onCapacityChanged(d),
                  decoration: _deco(
                    '최대 인원',
                    error: has(PartyRoundField.capacity),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: d.maleCapacityCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (_) => _onCapacityChanged(d),
                        decoration: _deco(
                          '남자 인원',
                          error: has(PartyRoundField.capacity),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: d.femaleCapacityCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (_) => _onCapacityChanged(d),
                        decoration: _deco(
                          '여자 인원',
                          error: has(PartyRoundField.capacity),
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: d.maleFeeCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => _onFeeChanged(d),
                      decoration: _deco(
                        '남자 참가비 (원)',
                        error: has(PartyRoundField.fee),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: d.femaleFeeCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => _onFeeChanged(d),
                      decoration: _deco(
                        '여자 참가비 (원)',
                        error: has(PartyRoundField.fee),
                      ),
                    ),
                  ),
                ],
              ),
              // 얼리버드는 '차수별 설정'일 때만 이 카드에서 받는다. '모든 차수
              // 동일'은 위 공통 입력 한 벌이 정본이고, 그 규칙이 저장 시 모든
              // 차수에 그대로 복사된다(할인 금액은 각 차수 참가비 기준으로 계산).
              if (widget.earlyBirdMode == 'perRound') ...[
                const SizedBox(height: 10),
                _earlyBirdRow(d, roundNumber),
              ],
            ] else
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE8EBF2)),
                ),
                child: Text(
                  widget.commonSettings != null
                      ? '모집 인원·참가비·얼리버드는 위 공통 설정을 모든 차수가 함께 씁니다. '
                            '차수마다 다르게 받으려면 "차수별 설정"을 선택하세요.'
                      : '모집 인원·참가비·얼리버드는 1차와 같이 운영해요. '
                            '차수마다 따로 받으려면 위에서 "차수별로 정원 설정"을 선택하세요.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.black45,
                    height: 1.4,
                  ),
                ),
              ),

            // ── 계산된 일시 + 오류 ──────────────────────────────────────
            if (window != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE8EBF2)),
                ),
                child: _windowSummary(window),
              ),
            ],
            for (final issue in issues) _errorText(issue.message),
          ],
        ),
      ),
    );
  }

  Widget _earlyBirdRow(PartyRoundDraft d, int roundNumber) {
    final eb = d.round.earlyBird;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '얼리버드 할인',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
            ),
            Switch(
              value: eb.enabled,
              activeThumbColor: _kAccent,
              onChanged: (v) => _update(
                d,
                d.round.copyWith(
                  earlyBird: eb.copyWith(
                    enabled: v,
                    percent: eb.percent ?? 10,
                    // 차수는 날짜가 바뀌므로 고정 종료 시각을 쓸 수 없다.
                    endType: PartyEarlyBirdEndType.beforeStart,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (eb.enabled) ...[
          Row(
            children: [
              SizedBox(
                width: 90,
                child: TextField(
                  controller: d.earlyBirdPercentCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (v) => _update(
                    d,
                    d.round.copyWith(
                      earlyBird: eb.copyWith(percent: int.tryParse(v.trim())),
                    ),
                  ),
                  decoration: _deco('할인율 %'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ruleBox(
                  '${eb.beforeStartRule.label}'
                  '${eb.beforeStartRule.usesTime ? ' ${formatScheduleTime(eb.beforeStartRule.time)}' : ''}까지',
                  () => _pickEarlyBirdEnd(d, roundNumber),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '이 차수의 시작 시각을 기준으로 계산돼요.',
            style: TextStyle(fontSize: 11, color: Colors.black38),
          ),
        ],
      ],
    );
  }

  /// 차수 얼리버드 종료 기준 — 며칠/몇 시간 전인지만 고르면 된다.
  Future<void> _pickEarlyBirdEnd(PartyRoundDraft d, int roundNumber) async {
    final eb = d.round.earlyBird;
    final picked = await showModalBottomSheet<PartyEarlyBirdDeadlineRule>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$roundNumber차 얼리버드 종료 기준',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              for (final option in _earlyBirdOptions)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    option.label,
                    style: const TextStyle(fontSize: 14),
                  ),
                  trailing: option == eb.beforeStartRule
                      ? const Icon(Icons.check, size: 18, color: _kAccent)
                      : null,
                  onTap: () => Navigator.pop(ctx, option),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    _update(
      d,
      d.round.copyWith(earlyBird: eb.copyWith(beforeStartRule: picked)),
    );
  }

  /// 선택지는 모델에 한 벌만 둔다 — '모든 차수 동일' 입력도 같은 목록을 쓴다.
  static const _earlyBirdOptions = kRoundEarlyBirdRuleOptions;

  // ── 조각 위젯 ───────────────────────────────────────────────────────
  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        color: Colors.black54,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _timeBox(
    String label,
    TimeOfDay? time,
    VoidCallback onTap, {
    bool error = false,
  }) {
    final has = time != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: has ? const Color(0xFFFFF3F7) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: error
                ? _kError
                : has
                ? _kAccent.withValues(alpha: 0.4)
                : const Color(0xFFE8EBF2),
            width: error ? 1.5 : 1,
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
              has ? formatKoreanTimeOfDay(time) : '선택하세요',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: has ? FontWeight.w600 : FontWeight.normal,
                color: has ? _kAccent : Colors.black38,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ruleRow(
    String label,
    String value,
    VoidCallback onTap, {
    bool error = false,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: error ? _kError : const Color(0xFFE8EBF2),
          width: error ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 62,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11.5, color: Colors.black38),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          const Icon(Icons.chevron_right, size: 18, color: Colors.black26),
        ],
      ),
    ),
  );

  Widget _ruleBox(String value, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8EBF2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: Colors.black87),
            ),
          ),
          const Icon(Icons.chevron_right, size: 18, color: Colors.black26),
        ],
      ),
    ),
  );

  Widget _errorText(String text) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline_rounded, size: 14, color: _kError),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              height: 1.35,
              color: _kError,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  InputDecoration _deco(String hint, {bool error = false}) {
    OutlineInputBorder side(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: color, width: width),
    );
    final normal = side(const Color(0xFFE8EBF2), 1);
    final red = side(_kError, 1.5);
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      // 오류일 때는 포커스가 들어와도 빨간 테두리를 유지한다 — 값을 채우면
      // 부모가 errors를 다시 계산해 자동으로 사라진다.
      border: error ? red : normal,
      enabledBorder: error ? red : normal,
      focusedBorder: error ? red : side(_kAccent, 1.5),
    );
  }
}

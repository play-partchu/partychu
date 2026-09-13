import 'package:flutter/material.dart';

import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/widgets/early_bird_price_line.dart';
import 'package:party_app/widgets/partychu_ui.dart';

/// 반복 파티의 **회차(날짜) 선택**.
///
/// 왜 공용인가: 호스트가 신청자를 보는 화면이 둘이다(호스트 허브의 신청자 시트,
/// 파티 상세의 신청자 목록). 회차 목록을 만드는 규칙이 두 벌로 갈라지면 같은
/// 파티인데 화면마다 다른 날짜가 뜬다. 목록 계산([buildOccurrenceIds])과 기본
/// 선택([defaultOccurrenceId]), 라벨까지 여기 한 곳에 둔다.
///
/// 회차 식별자는 신청 문서가 이미 쓰고 있는 `occurrenceId`(`YYYY-MM-DD`)를
/// 그대로 쓴다 — 서버가 저장된 `recurringSchedule`로 검증해 기록하는 값이고
/// (functions/index.js `applyToParty`), 문서 ID도 `{uid}_{occurrenceId}`다.
/// **새 식별자를 따로 만들지 않는다.**
///
/// ── 왜 달력인가 ─────────────────────────────────────────────────────────
/// 처음에는 날짜를 가로 칩으로 늘어놓았다. 매일 반복 파티는 회차가 수십 개라
/// **화면 밖 날짜는 있는 줄도 몰랐다.** 세로 목록으로 바꿔도 8/18·8/20·8/25가
/// 화·목이라는 **요일 주기가 보이지 않는다** — 반복 파티에서는 그게 곧 일정이다.
/// 그래서 [showOccurrenceSheet]는 월간 달력을 띄운다. 파티가 열리는 날만 살아
/// 있고 나머지는 눌리지 않으며, 신청자가 있는 날에는 수가 함께 붙는다.
/// 신청자 목록 위에는 지금 보고 있는 날짜를 [OccurrenceHeaderButton]으로
/// 못 박아 둔다.

/// 신청자 목록 위에 붙는 **지금 보고 있는 회차** 표시 겸 날짜 변경 버튼.
class OccurrenceHeaderButton extends StatelessWidget {
  /// 지금 보고 있는 회차(`YYYY-MM-DD`).
  final String occurrenceId;

  /// 이 회차의 신청자 수(취소 제외). 모르면 null — 그러면 숫자를 쓰지 않는다.
  final int? count;

  final VoidCallback onTap;

  const OccurrenceHeaderButton({
    super.key,
    required this.occurrenceId,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: PartyChuColors.primary),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.event_rounded,
                  size: 18,
                  color: PartyChuColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    count == null
                        ? occurrenceLabel(occurrenceId)
                        : '${occurrenceLabel(occurrenceId)} · 신청자 $count명',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Text(
                  '날짜 변경',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: PartyChuColors.primary,
                  ),
                ),
                const Icon(
                  Icons.expand_more_rounded,
                  size: 18,
                  color: PartyChuColors.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 회차를 **월간 달력**으로 고르게 한다.
///
/// 고른 회차를 돌려준다. 그냥 닫으면 null — 호출부는 **보고 있던 회차를
/// 그대로 유지**해야 한다(닫았다고 날짜가 바뀌면 안 된다).
///
/// 왜 달력인가: 반복 파티는 "무슨 요일에 열리는 파티인지"가 곧 일정이다.
/// 세로 목록으로 늘어놓으면 8/18·8/20·8/25가 화·목이라는 사실이 안 보인다.
/// 달력은 열리는 날만 살아 있고 나머지는 비활성이라, 요일 주기가 그대로 눈에
/// 들어온다.
Future<String?> showOccurrenceSheet({
  required BuildContext context,
  required List<String> occurrenceIds,
  required String? selected,
  required Map<String, int> counts,
  DateTime? now,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _OccurrenceCalendarSheet(
      occurrenceIds: occurrenceIds,
      selected: selected,
      counts: counts,
      now: now ?? DateTime.now(),
    ),
  );
}

class _OccurrenceCalendarSheet extends StatefulWidget {
  final List<String> occurrenceIds;
  final String? selected;
  final Map<String, int> counts;
  final DateTime now;

  const _OccurrenceCalendarSheet({
    required this.occurrenceIds,
    required this.selected,
    required this.counts,
    required this.now,
  });

  @override
  State<_OccurrenceCalendarSheet> createState() =>
      _OccurrenceCalendarSheetState();
}

class _OccurrenceCalendarSheetState extends State<_OccurrenceCalendarSheet> {
  /// 지금 펼쳐 놓은 달(그 달 1일).
  late DateTime _month;

  /// 회차가 있는 날 — 달력 칸이 살아 있는지 판단하는 단 하나의 기준이다.
  /// **달력이 스스로 요일을 계산하지 않는다** — 매주 화·목인지, 격주인지,
  /// 공휴일에 쉬는지는 이미 [buildOccurrenceIds]가 파티의 일정으로 정해서
  /// 넘겨준 목록에 들어 있다. 여기서 다시 따지면 규칙이 두 벌이 된다.
  late final Set<String> _open = widget.occurrenceIds.toSet();

  @override
  void initState() {
    super.initState();
    // 처음 펼치는 달은 **지금 보고 있는 회차의 달**. 아직 고른 게 없으면
    // 기본 회차(오늘 이후 가장 가까운 회차)가 있는 달을 연다.
    final anchor =
        parseOccurrenceId(widget.selected ?? '') ??
        parseOccurrenceId(defaultOccurrenceId(widget.occurrenceIds) ?? '') ??
        widget.now;
    _month = DateTime(anchor.year, anchor.month);
  }

  /// 회차가 있는 첫 달 / 마지막 달 — 여기를 벗어나면 빈 달만 나오므로
  /// 이전·다음 화살표를 막는다.
  DateTime? get _firstMonth {
    final at = parseOccurrenceId(widget.occurrenceIds.first);
    return at == null ? null : DateTime(at.year, at.month);
  }

  DateTime? get _lastMonth {
    final at = parseOccurrenceId(widget.occurrenceIds.last);
    return at == null ? null : DateTime(at.year, at.month);
  }

  bool get _canGoPrev {
    final first = _firstMonth;
    return first != null && _month.isAfter(first);
  }

  bool get _canGoNext {
    final last = _lastMonth;
    return last != null && _month.isBefore(last);
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SheetGrip(),
            const SizedBox(height: 14),
            const Text(
              '날짜 선택',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              '파티가 열리는 날짜만 고를 수 있어요.',
              style: TextStyle(fontSize: 12, color: Colors.black45),
            ),
            const SizedBox(height: 12),
            OccurrenceMonthCalendar(
              month: _month,
              now: widget.now,
              canGoPrev: _canGoPrev,
              canGoNext: _canGoNext,
              onShiftMonth: _shiftMonth,
              isOpen: (day) => _open.contains(occurrenceIdOf(day)),
              isSelected: (day) => occurrenceIdOf(day) == widget.selected,
              // 신청자가 있는 날만 수를 적는다. 0명은 굳이 강조하지 않는다 —
              // 열리는 날 대부분이 0명이라 다 쓰면 오히려 안 보인다.
              badgeOf: (day) {
                final count = widget.counts[occurrenceIdOf(day)] ?? 0;
                if (count <= 0) return null;
                return Text(
                  '$count명',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: PartyChuColors.primary,
                  ),
                );
              },
              onTapDay: (day) => Navigator.pop(context, occurrenceIdOf(day)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 바텀시트 위쪽 손잡이 — 이 파일의 시트 두 개가 같은 모양을 쓴다.
class _SheetGrip extends StatelessWidget {
  const _SheetGrip();

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 4,
    decoration: BoxDecoration(
      color: Colors.grey.shade300,
      borderRadius: BorderRadius.circular(4),
    ),
  );
}

/// 회차용 **월간 달력 격자** — 달 이동 막대 + 요일 머리 + 날짜 칸.
///
/// 신청 흐름의 참가 날짜 선택과 호스트의 신청자 날짜 변경이 **같은 달력**을
/// 쓴다. 둘이 따로 그리면 같은 파티인데 화면마다 다른 날이 살아 있는 달력을
/// 보게 된다.
///
/// ## 이 위젯은 일정을 계산하지 않는다
///
/// 어느 날이 열리는지([isOpen])는 전부 호출부가 정한다 — 매주 화·목인지,
/// 격주인지, 이미 지난 날인지, 모집이 마감됐는지는 이미 [PartySchedule]이
/// 판정해서 넘겨준다. 여기서 다시 따지면 일정 규칙이 두 벌이 된다.
class OccurrenceMonthCalendar extends StatelessWidget {
  /// 지금 펼쳐 놓은 달(그 달 1일).
  final DateTime month;

  /// '오늘'의 기준 시각 — 테스트가 고정할 수 있도록 주입받는다.
  final DateTime now;

  final bool canGoPrev;
  final bool canGoNext;

  /// 달 이동 — +1이 다음 달.
  final void Function(int delta) onShiftMonth;

  /// 이 날에 회차가 있어 고를 수 있는가.
  final bool Function(DateTime day) isOpen;

  /// 지금 골라져 있는 날인가.
  final bool Function(DateTime day) isSelected;

  /// 날짜 숫자 아래에 붙일 작은 표시(신청자 수·얼리버드 점 등). 없으면 null.
  final Widget? Function(DateTime day)? badgeOf;

  final void Function(DateTime day) onTapDay;

  const OccurrenceMonthCalendar({
    super.key,
    required this.month,
    required this.now,
    required this.canGoPrev,
    required this.canGoNext,
    required this.onShiftMonth,
    required this.isOpen,
    required this.isSelected,
    required this.onTapDay,
    this.badgeOf,
  });

  static const _columnNames = ['일', '월', '화', '수', '목', '금', '토'];

  /// 일요일은 붉게, 토요일은 푸르게 — 달력에서 늘 쓰는 구분이다.
  static Color _columnColor(int column, {bool muted = false}) {
    if (column == 0) return muted ? Colors.red.shade300 : Colors.red.shade400;
    if (column == 6) return muted ? Colors.blue.shade300 : Colors.blue.shade400;
    return muted ? Colors.black45 : Colors.black87;
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _monthBar(),
      const SizedBox(height: 8),
      _weekdayHeader(),
      const SizedBox(height: 4),
      _grid(),
    ],
  );

  Widget _monthBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: canGoPrev ? () => onShiftMonth(-1) : null,
          icon: const Icon(Icons.chevron_left_rounded),
          color: PartyChuColors.primary,
          disabledColor: Colors.black12,
          tooltip: '이전 달',
        ),
        SizedBox(
          width: 130,
          child: Text(
            '${month.year}년 ${month.month}월',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          onPressed: canGoNext ? () => onShiftMonth(1) : null,
          icon: const Icon(Icons.chevron_right_rounded),
          color: PartyChuColors.primary,
          disabledColor: Colors.black12,
          tooltip: '다음 달',
        ),
      ],
    );
  }

  Widget _weekdayHeader() {
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Text(
              _columnNames[i],
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _columnColor(i, muted: true),
              ),
            ),
          ),
      ],
    );
  }

  Widget _grid() {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // 그 달 1일이 몇 번째 칸에서 시작하는지. DateTime의 월요일=1 … 일요일=7을
    // 일요일 시작 달력(0열=일)으로 옮긴다.
    final leading = month.weekday % 7;
    final rows = ((leading + daysInMonth) / 7).ceil();

    return Column(
      children: [
        for (var r = 0; r < rows; r++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(child: _cell(r * 7 + c - leading, c, daysInMonth)),
            ],
          ),
      ],
    );
  }

  /// [day]가 1..daysInMonth 밖이면 빈 칸.
  Widget _cell(int day, int column, int daysInMonth) {
    if (day < 1 || day > daysInMonth) return const SizedBox(height: 52);

    final date = DateTime(month.year, month.month, day);
    final open = isOpen(date);
    final selected = isSelected(date);
    final today = date == DateTime(now.year, now.month, now.day);
    final badge = open ? badgeOf?.call(date) : null;

    // 파티가 없는 날, 이미 지난 날, 모집이 닫힌 날은 아예 누를 수 없다 —
    // 어느 쪽인지는 호출부가 isOpen 하나로 알려준다.
    final textColor = !open
        ? Colors.black26
        : selected
        ? Colors.white
        : _columnColor(column);

    return InkWell(
      onTap: open ? () => onTapDay(date) : null,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: 52,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // 선택된 날은 **채우고**, 오늘은 **테두리만** — 둘이 겹쳐도
                // 어느 쪽이 선택인지 헷갈리지 않는다.
                color: selected ? PartyChuColors.primary : null,
                shape: BoxShape.circle,
                border: today && !selected
                    ? Border.all(color: PartyChuColors.primary, width: 1.5)
                    : null,
              ),
              child: Text(
                '$day',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected || today
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: textColor,
                ),
              ),
            ),
            if (badge != null)
              Padding(padding: const EdgeInsets.only(top: 2), child: badge)
            else
              const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }
}

// ── 신청 흐름의 참가 날짜 선택 ─────────────────────────────────────────────

/// 달력에서 고른 날 아래에 붙는 요약 — 값은 **전부 호출부가 만든다**.
///
/// 시각·모집 마감·얼리버드 금액은 이미 정본이 있는 값이라(PartySchedule /
/// EarlyBird / PartyPricing) 이 시트가 다시 계산하지 않는다. 그래야 달력에
/// 적힌 금액과 실제 신청 금액이 어긋날 수 없다.
@immutable
class OccurrenceDaySummary {
  /// '8월 25일(화)'.
  final String title;

  /// '오후 8:00'.
  final String timeText;

  /// '모집 마감 오후 6:00'. 마감 규칙이 없으면 null.
  final String? deadlineText;

  /// 그 회차에 얼리버드가 적용될 때의 **정상가와 실제 낼 금액**. 적용되지
  /// 않으면 null이다.
  ///
  /// 두 금액을 함께 받는 이유: 할인가만 보여주면 그게 할인가인지 알 수 없다
  /// ([EarlyBirdPriceLine] 상단 주석). 하나의 레코드로 묶어 둬서 "정상가만
  /// 있고 할인가는 없는" 반쪽 상태가 아예 만들어지지 않게 한다.
  ///
  /// **이 값은 날짜를 고른 뒤에만 쓰인다.** 달력 칸에는 얼리버드를 미리
  /// 드러내지 않는다([showApplyOccurrenceCalendar] 주석 참고).
  final ({int regular, int discounted})? earlyBird;

  const OccurrenceDaySummary({
    required this.title,
    required this.timeText,
    this.deadlineText,
    this.earlyBird,
  });
}

/// 참가할 회차를 **월간 달력**으로 고르게 한다(반복·정기 파티 전용).
///
/// 고른 회차를 돌려주고, 그냥 닫으면 null이다 — 호출부가 앞 단계로 돌아갈지
/// 신청을 그만둘지 정한다([canGoBack]).
///
/// ## 판정은 전부 넘겨받는다
///
/// [occurrences]는 `PartySchedule.selectableOccurrences`가 만든 목록 그대로다
/// — **실제로 존재하고, 아직 오지 않았고, 모집이 열려 있는** 회차만 들어 있다.
/// 그래서 달력은 "이 목록에 있는 날만 살아 있다"는 규칙 하나만 지키면 되고,
/// 오늘 이전·모집 마감·요일 주기를 따로 계산하지 않는다.
///
/// ## 달력은 얼리버드를 미리 알려주지 않는다
///
/// 예전에는 얼리버드가 붙는 날 아래에 분홍 점을 찍고 아래에 범례까지 뒀다.
/// 그러면 **날짜를 고르기도 전에 할인 날짜가 전부 드러난다.** 지금은 달력에서
/// 할인 여부를 읽을 수 있는 표시가 하나도 없다 — 날짜 숫자 스타일도 얼리버드
/// 여부와 무관하게 같고(열림/선택/오늘/요일만 본다), 할인은 **날짜를 고른 뒤**
/// 아래 요약([OccurrenceDaySummary.earlyBird])에서만 말한다.
///
/// 할인 **계산**은 이 변경과 무관하다 — 정본은 그대로 `EarlyBird`이고, 고른
/// 회차의 실제 신청 금액에는 예전과 똑같이 적용된다.
Future<PartyOccurrence?> showApplyOccurrenceCalendar({
  required BuildContext context,
  required List<PartyOccurrence> occurrences,
  required String? selectedId,
  required OccurrenceDaySummary Function(PartyOccurrence) summaryOf,
  bool canGoBack = false,
  DateTime? now,
}) {
  return showModalBottomSheet<PartyOccurrence>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ApplyOccurrenceCalendarSheet(
      occurrences: occurrences,
      selectedId: selectedId,
      summaryOf: summaryOf,
      canGoBack: canGoBack,
      now: now ?? DateTime.now(),
    ),
  );
}

class _ApplyOccurrenceCalendarSheet extends StatefulWidget {
  final List<PartyOccurrence> occurrences;
  final String? selectedId;
  final OccurrenceDaySummary Function(PartyOccurrence) summaryOf;
  final bool canGoBack;
  final DateTime now;

  const _ApplyOccurrenceCalendarSheet({
    required this.occurrences,
    required this.selectedId,
    required this.summaryOf,
    required this.canGoBack,
    required this.now,
  });

  @override
  State<_ApplyOccurrenceCalendarSheet> createState() =>
      _ApplyOccurrenceCalendarSheetState();
}

class _ApplyOccurrenceCalendarSheetState
    extends State<_ApplyOccurrenceCalendarSheet> {
  /// 회차 id → 회차. 달력 칸이 살아 있는지, 어떤 회차인지를 이 하나로 본다.
  late final Map<String, PartyOccurrence> _byId = {
    for (final o in widget.occurrences) o.id: o,
  };

  /// 지금 펼쳐 놓은 달(그 달 1일).
  late DateTime _month;

  /// 지금 고른 회차. 시트를 열 때 이미 고른 게 있으면 그대로 이어 받는다 —
  /// 다음 단계에서 ←로 돌아왔을 때 어느 날을 골랐었는지 보여야 한다.
  PartyOccurrence? _picked;

  @override
  void initState() {
    super.initState();
    // 처음 펼치는 달 — 이미 고른 회차가 있으면 그 달, 없으면 **가장 가까운
    // 신청 가능한 회차**가 있는 달이다. selectableOccurrences가 오늘 이후만
    // 담아 오름차순이라 first가 곧 그 회차이고, 대개 오늘이 든 달이 된다.
    _picked = widget.selectedId == null ? null : _byId[widget.selectedId];
    final anchor =
        _picked?.start ??
        (widget.occurrences.isEmpty
            ? widget.now
            : widget.occurrences.first.start);
    _month = DateTime(anchor.year, anchor.month);
  }

  /// 회차가 있는 첫 달 / 마지막 달 — 그 밖은 빈 달뿐이라 화살표를 막는다.
  DateTime get _firstMonth {
    final at = widget.occurrences.first.start;
    return DateTime(at.year, at.month);
  }

  DateTime get _lastMonth {
    final at = widget.occurrences.last.start;
    return DateTime(at.year, at.month);
  }

  bool get _canGoPrev => _month.isAfter(_firstMonth);
  bool get _canGoNext => _month.isBefore(_lastMonth);

  void _shiftMonth(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta));

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _SheetGrip(),
              const SizedBox(height: 12),
              _titleBar(),
              const SizedBox(height: 10),
              OccurrenceMonthCalendar(
                month: _month,
                now: widget.now,
                canGoPrev: _canGoPrev,
                canGoNext: _canGoNext,
                onShiftMonth: _shiftMonth,
                isOpen: (day) => _byId.containsKey(occurrenceIdOf(day)),
                isSelected: (day) => occurrenceIdOf(day) == _picked?.id,
                // badgeOf를 주지 않는다 — 날짜 아래에 아무 표시도 붙이지
                // 않아야 어느 날이 얼리버드인지 미리 읽히지 않는다.
                onTapDay: (day) =>
                    setState(() => _picked = _byId[occurrenceIdOf(day)]),
              ),
              const SizedBox(height: 10),
              _pickedSummary(),
              const SizedBox(height: 12),
              _confirmButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _titleBar() => Row(
    children: [
      if (widget.canGoBack)
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, size: 20),
          color: Colors.black54,
          tooltip: '참가할 일정 다시 고르기',
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
      const Expanded(
        child: Text(
          '참가할 날짜를 선택해주세요',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      // ←를 넣은 만큼 오른쪽을 비워 제목이 가운데에 남게 한다.
      if (widget.canGoBack) const SizedBox(width: 36),
    ],
  );

  /// 고른 날의 정보 — 날짜 / 시각·모집 마감 / 얼리버드 금액.
  ///
  /// 얼리버드를 말하는 자리는 **여기 하나뿐**이다. 달력 칸에는 점도 범례도
  /// 두지 않는다 — 고르기 전에 할인 날짜가 전부 드러나지 않게 한다.
  Widget _pickedSummary() {
    final occ = _picked;
    if (occ == null) {
      return const SizedBox(
        height: 62,
        child: Center(
          child: Text(
            '날짜를 누르면 그날의 시간과 참가비를 볼 수 있어요.',
            style: TextStyle(fontSize: 12.5, color: Colors.black38),
          ),
        ),
      );
    }
    final s = widget.summaryOf(occ);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD6E4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            s.title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            s.deadlineText == null
                ? s.timeText
                : '${s.timeText} · ${s.deadlineText}',
            style: const TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
          // 얼리버드가 붙는 날에만, 그것도 **고른 뒤에만** 나타난다.
          // 할인가만 적으면 그게 할인가인지 알 수 없어 정상가를 함께 보여주는
          // 공용 줄(EarlyBirdPriceLine)을 그대로 쓴다 — 결제수단 화면·금액
          // 분해 카드와 같은 표시다.
          if (s.earlyBird case final eb?) ...[
            const SizedBox(height: 6),
            EarlyBirdPriceLine(
              originalAmount: eb.regular,
              discountedAmount: eb.discounted,
              valueFontSize: 15,
            ),
          ],
        ],
      ),
    );
  }

  Widget _confirmButton() => SizedBox(
    width: double.infinity,
    height: 50,
    child: ElevatedButton(
      // 날짜를 고르기 전에는 누를 수 없다 — 무엇으로 신청하는지 모르는 채로
      // 다음 단계(차수 선택)로 넘어가지 않게 한다.
      onPressed: _picked == null ? null : () => Navigator.pop(context, _picked),
      style: ElevatedButton.styleFrom(
        backgroundColor: PartyChuColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFF0F0F4),
        disabledForegroundColor: Colors.black26,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: const Text(
        '이 날짜로 신청하기',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
      ),
    ),
  );
}

const _weekdayNames = ['월', '화', '수', '목', '금', '토', '일'];

/// `2026-08-20` → `8/20(목)`. 파싱할 수 없으면 원본을 그대로 돌려준다.
String occurrenceLabel(String occurrenceId) {
  final at = parseOccurrenceId(occurrenceId);
  if (at == null) return occurrenceId;
  return '${at.month}/${at.day}(${_weekdayNames[at.weekday - 1]})';
}

/// `YYYY-MM-DD` → 그 날 자정. 형식이 다르면 null.
DateTime? parseOccurrenceId(String occurrenceId) {
  final parts = occurrenceId.split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}

/// 날짜 하나 → 회차 식별자 `YYYY-MM-DD`. 신청 문서·서버가 쓰는 값과 같다.
String occurrenceIdOf(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// 화면에 늘어놓을 회차 목록.
///
/// 두 갈래를 합친다:
///  - **일정에서 나오는 앞으로의 회차** — 아직 신청자가 없어도 보여야 한다.
///  - **신청 문서에 실제로 찍힌 회차** — 지난 회차라도 신청자가 있으면 보여야
///    한다(지난 회차 확인이 필요하다는 요구).
///
/// 정기 파티가 아니거나 회차가 하나뿐이면 빈 목록을 돌려준다 — 그때는 날짜
/// 고르는 단계를 건너뛰고 바로 신청자 목록을 보여준다.
List<String> buildOccurrenceIds({
  Map<String, dynamic>? partyData,
  required Iterable<String?> fromApplications,
  DateTime? now,
  int aheadDays = 60,
}) {
  final today = now ?? DateTime.now();
  final ids = <String>{};

  for (final id in fromApplications) {
    if (id != null && id.isNotEmpty) ids.add(id);
  }

  if (partyData != null && PartySchedule.isRecurring(partyData)) {
    final schedule = PartySchedule.recurringOf(partyData);
    if (schedule != null) {
      final from = DateTime(today.year, today.month, today.day);
      final occurrences = schedule.occurrencesBetween(
        from,
        from.add(Duration(days: aheadDays)),
      );
      for (final occ in occurrences) {
        ids.add(occurrenceIdOf(occ.start));
      }
    }
  }

  final sorted = ids.toList()..sort();
  return sorted.length < 2 ? const [] : sorted;
}

/// 기본으로 열어 둘 회차 — **오늘 이후 가장 가까운 회차**.
///
/// 앞으로의 회차가 하나도 없으면(전부 지난 파티) 가장 최근 회차를 연다 —
/// 빈 화면을 띄우는 것보다 낫다.
String? defaultOccurrenceId(List<String> occurrenceIds, {DateTime? now}) {
  if (occurrenceIds.isEmpty) return null;
  final today = now ?? DateTime.now();
  final todayId = occurrenceIdOf(DateTime(today.year, today.month, today.day));
  for (final id in occurrenceIds) {
    if (id.compareTo(todayId) >= 0) return id;
  }
  return occurrenceIds.last;
}

// ── 호스트: 상태를 바꿀 회차(여러 날) 고르기 ───────────────────────────────

/// 호스트가 **모집 상태를 바꿀 회차들**을 달력에서 고른다(여러 날 선택).
///
/// 게스트 쪽 달력([showApplyOccurrenceCalendar])과 **같은 달력 위젯**
/// ([OccurrenceMonthCalendar])을 쓰고, 다른 점은 셋뿐이다.
///
///  1. 여러 날을 고른다(신청은 한 회차, 상태 변경은 여러 회차).
///  2. 칸 아래에 그 회차의 **현재 상태**를 적는다([statusLabelOf]) — 호스트는
///     "지금 어떤 날이 닫혀 있는지"를 보고 고른다.
///  3. 모집이 닫힌 회차도 고를 수 있다 — 닫힌 것을 **다시 여는** 것이 이
///     화면의 일이라, 열린 회차만 보여주면 되돌릴 방법이 사라진다.
///
/// [days]는 그 파티에 **실제로 존재하는 회차 날짜**다
/// ([PartySchedule.occurrenceDays]). 달력은 여기 있는 날만 살아 있고 나머지
/// 날은 눌리지 않는다 — 일정 계산을 다시 하지 않는다.
///
/// 돌려주는 값은 고른 회차 id(`YYYY-MM-DD`) 집합이고, 그냥 닫으면 null이다.
Future<Set<String>?> showHostOccurrenceStatusPicker({
  required BuildContext context,
  required List<DateTime> days,
  required Set<String> initialIds,
  required String Function(String occurrenceId) statusLabelOf,
  DateTime? now,
}) {
  return showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _HostOccurrencePickerSheet(
      days: days,
      initialIds: initialIds,
      statusLabelOf: statusLabelOf,
      now: now ?? DateTime.now(),
    ),
  );
}

class _HostOccurrencePickerSheet extends StatefulWidget {
  const _HostOccurrencePickerSheet({
    required this.days,
    required this.initialIds,
    required this.statusLabelOf,
    required this.now,
  });

  final List<DateTime> days;
  final Set<String> initialIds;
  final String Function(String occurrenceId) statusLabelOf;
  final DateTime now;

  @override
  State<_HostOccurrencePickerSheet> createState() =>
      _HostOccurrencePickerSheetState();
}

class _HostOccurrencePickerSheetState
    extends State<_HostOccurrencePickerSheet> {
  /// 이 파티에 실제로 있는 회차 id — 달력 칸이 살아 있는지의 정본이다.
  late final List<String> _ids = widget.days.map(occurrenceIdOf).toSet().toList()
    ..sort();

  late final Set<String> _picked = {
    for (final id in widget.initialIds)
      if (_ids.contains(id)) id,
  };

  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final anchorId = _picked.isEmpty
        ? (_ids.isEmpty ? null : _ids.first)
        : (_picked.toList()..sort()).first;
    final at =
        (anchorId == null ? null : parseOccurrenceId(anchorId)) ?? widget.now;
    _month = DateTime(at.year, at.month);
  }

  DateTime _monthOf(String? id) {
    final at = (id == null ? null : parseOccurrenceId(id)) ?? widget.now;
    return DateTime(at.year, at.month);
  }

  void _toggle(DateTime day) {
    final id = occurrenceIdOf(day);
    setState(() {
      if (!_picked.remove(id)) _picked.add(id);
    });
  }

  /// 달력 칸 아래 한 줄 — '모집중'은 적지 않는다(전부 모집중인 달이 글자로
  /// 가득 차면 정작 닫힌 날이 눈에 안 띈다).
  String _badgeText(String id) {
    final label = widget.statusLabelOf(id);
    return label == '모집중' ? '' : label;
  }

  @override
  Widget build(BuildContext context) {
    final first = _monthOf(_ids.isEmpty ? null : _ids.first);
    final last = _monthOf(_ids.isEmpty ? null : _ids.last);
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SheetGrip(),
              const SizedBox(height: 12),
              const Text(
                '어느 날짜의 모집 상태를 바꿀까요?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                '이 파티가 실제로 열리는 날짜만 고를 수 있어요. 여러 날을 함께 고를 수 있어요.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.black45),
              ),
              const SizedBox(height: 6),
              OccurrenceMonthCalendar(
                month: _month,
                now: widget.now,
                canGoPrev: _month.isAfter(first),
                canGoNext: _month.isBefore(last),
                onShiftMonth: (delta) => setState(
                  () => _month = DateTime(_month.year, _month.month + delta),
                ),
                isOpen: (day) => _ids.contains(occurrenceIdOf(day)),
                isSelected: (day) => _picked.contains(occurrenceIdOf(day)),
                badgeOf: (day) {
                  final id = occurrenceIdOf(day);
                  final text = _badgeText(id);
                  if (text.isEmpty) return null;
                  return Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                      fontSize: 9,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      color: _picked.contains(id)
                          ? PartyChuColors.primaryDeep
                          : Colors.black54,
                    ),
                  );
                },
                onTapDay: _toggle,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() {
                    if (_picked.length == _ids.length) {
                      _picked.clear();
                    } else {
                      _picked
                        ..clear()
                        ..addAll(_ids);
                    }
                  }),
                  child: Text(
                    _picked.length == _ids.length ? '선택 해제' : '전체 선택',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              _pickedSummary(),
              const SizedBox(height: 12),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _picked.isEmpty
                      ? null
                      : () => Navigator.pop(context, {..._picked}),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: PartyChuColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFF0F0F4),
                    disabledForegroundColor: Colors.black26,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _picked.isEmpty
                        ? '날짜를 골라주세요'
                        : '${_picked.length}개 날짜 상태 바꾸기',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 고른 날짜와 **그 날의 현재 상태**를 그대로 늘어놓는다 — 여러 날을 골랐을
  /// 때 상태가 서로 다르면 여기서 먼저 보인다.
  Widget _pickedSummary() {
    if (_picked.isEmpty) {
      return const SizedBox(
        height: 44,
        child: Center(
          child: Text(
            '날짜를 누르면 그 회차의 상태를 바꿀 수 있어요.',
            style: TextStyle(fontSize: 12.5, color: Colors.black38),
          ),
        ),
      );
    }
    final sorted = _picked.toList()..sort();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD6E4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final id in sorted)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      occurrenceLabel(id),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    widget.statusLabelOf(id),
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Colors.black54,
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

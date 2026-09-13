import 'package:flutter/material.dart';

import 'package:party_app/models/event_filter.dart';
import 'package:party_app/models/korean_holidays.dart';

const _kPink = Color(0xFFFF6FA0);
const _kRed = Color(0xFFE53935);
const _kBlue = Color(0xFF3D6DF0);

/// 방문 날짜를 **여러 개(최대 [maxCount]일)** 고르는 한국식 달력 시트.
///
/// Material 기본 [showDatePicker]는 하루만 고를 수 있고 표기도 영어 기준이라
/// (Select date / Wed, Aug 19 / OK) 이 필터에는 맞지 않았다. 그래서 달력 자체를
/// 직접 그린다.
///
/// - 요일 머리는 일·월·화·수·목·금·토, 제목은 '2026년 8월'
/// - **일요일과 공휴일은 빨강**, 토요일은 파랑([KoreanHolidays])
/// - 고른 날은 핑크로 채우고, 그 안의 숫자 아래 **빨간 점**으로 공휴일임을 계속
///   알려준다(핑크에 덮여 색이 사라지지 않게)
/// - 오늘은 핑크 테두리로만 표시해서 선택(채움)과 구별된다
///
/// 돌려주는 값은 고른 날짜 집합이고, 취소하면 null이라 기존 선택이 그대로
/// 남는다. 공휴일 데이터는 [KoreanHolidays] 한곳에서만 온다.
Future<Set<DateTime>?> showKoreanCalendarSheet(
  BuildContext context, {
  required Set<DateTime> selected,
  required DateTime firstDate,
  required DateTime lastDate,
  int maxCount = EventFilter.maxVisitDates,
}) {
  return showModalBottomSheet<Set<DateTime>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _KoreanCalendarSheet(
      selected: selected,
      firstDate: firstDate,
      lastDate: lastDate,
      maxCount: maxCount,
    ),
  );
}

class _KoreanCalendarSheet extends StatefulWidget {
  const _KoreanCalendarSheet({
    required this.selected,
    required this.firstDate,
    required this.lastDate,
    required this.maxCount,
  });

  final Set<DateTime> selected;
  final DateTime firstDate;
  final DateTime lastDate;
  final int maxCount;

  @override
  State<_KoreanCalendarSheet> createState() => _KoreanCalendarSheetState();
}

class _KoreanCalendarSheetState extends State<_KoreanCalendarSheet> {
  late final Set<DateTime> _picked = {...widget.selected};

  /// 지금 보고 있는 달(1일로 정규화).
  late DateTime _month = DateTime(
    widget.selected.isEmpty
        ? widget.firstDate.year
        : widget.selected.reduce((a, b) => a.isBefore(b) ? a : b).year,
    widget.selected.isEmpty
        ? widget.firstDate.month
        : widget.selected.reduce((a, b) => a.isBefore(b) ? a : b).month,
  );

  static const _weekdayLabels = ['일', '월', '화', '수', '목', '금', '토'];

  bool get _canGoPrev =>
      _month.isAfter(DateTime(widget.firstDate.year, widget.firstDate.month));
  bool get _canGoNext =>
      _month.isBefore(DateTime(widget.lastDate.year, widget.lastDate.month));

  void _shiftMonth(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta));

  bool _inRange(DateTime d) =>
      !d.isBefore(EventFilter.dayOf(widget.firstDate)) &&
      !d.isAfter(EventFilter.dayOf(widget.lastDate));

  void _toggle(DateTime day) {
    if (_picked.remove(day)) {
      setState(() {});
      return;
    }
    if (_picked.length >= widget.maxCount) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('방문 날짜는 최대 ${widget.maxCount}일까지 고를 수 있어요.'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      return;
    }
    setState(() => _picked.add(day));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        14 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 12),
          _monthHeader(),
          const SizedBox(height: 10),
          _weekdayHeader(),
          const SizedBox(height: 4),
          _monthGrid(),
          // 음력 공휴일 표가 없는 해 — 설·추석이 평일처럼 보이는 것을 그냥 두면
          // 안 되므로, 빠진 것이 있다는 사실을 그 자리에서 알린다.
          if (!KoreanHolidays.hasLunarData(_month.year)) _lunarDataNotice(),
          const SizedBox(height: 10),
          _pickedSummary(),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, _picked),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPink,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                _picked.isEmpty ? '날짜 선택 안 함' : '${_picked.length}일 적용',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 음력 공휴일(설·추석·부처님오신날)을 아직 모르는 해에 띄우는 안내.
  /// 양력 공휴일과 일요일은 그대로 빨갛게 뜨므로 "공휴일이 없다"가 아니라
  /// "덜 표시된다"고 정확히 말해준다.
  Widget _lunarDataNotice() => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      children: [
        const Icon(Icons.info_outline_rounded, size: 13, color: Colors.black38),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            '${_month.year}년은 설·추석 등 음력 공휴일 정보가 아직 없어요. '
            '${KoreanHolidays.maxSupportedYear}년까지만 표시돼요.',
            style: const TextStyle(fontSize: 11, color: Colors.black45),
          ),
        ),
      ],
    ),
  );

  Widget _monthHeader() {
    return Row(
      children: [
        _arrow(
          Icons.chevron_left_rounded,
          _canGoPrev ? () => _shiftMonth(-1) : null,
        ),
        Expanded(
          child: Text(
            '${_month.year}년 ${_month.month}월',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        _arrow(
          Icons.chevron_right_rounded,
          _canGoNext ? () => _shiftMonth(1) : null,
        ),
      ],
    );
  }

  Widget _arrow(IconData icon, VoidCallback? onTap) => IconButton(
    onPressed: onTap,
    icon: Icon(icon, size: 24),
    color: Colors.black54,
    disabledColor: Colors.black12,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
  );

  Widget _weekdayHeader() => Row(
    children: [
      for (var i = 0; i < 7; i++)
        Expanded(
          child: Center(
            child: Text(
              _weekdayLabels[i],
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                // 일요일 빨강 / 토요일 파랑 — 달력의 기본 약속.
                color: i == 0
                    ? _kRed
                    : i == 6
                    ? _kBlue
                    : Colors.black45,
              ),
            ),
          ),
        ),
    ],
  );

  /// 한 달치 칸 — 1일이 무슨 요일인지에 맞춰 앞을 비우고, 6줄까지 그린다.
  Widget _monthGrid() {
    final first = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    // DateTime.weekday는 월=1…일=7이라 일요일 시작 달력으로 옮긴다.
    final leading = first.weekday % 7;
    final rows = ((leading + daysInMonth) / 7).ceil();

    return Column(
      children: [
        for (var r = 0; r < rows; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(
                  child: Builder(
                    builder: (_) {
                      final dayNum = r * 7 + c - leading + 1;
                      if (dayNum < 1 || dayNum > daysInMonth) {
                        return const SizedBox(height: 42);
                      }
                      return _dayCell(
                        DateTime(_month.year, _month.month, dayNum),
                      );
                    },
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _dayCell(DateTime day) {
    final selected = _picked.contains(day);
    final enabled = _inRange(day);
    final holiday = KoreanHolidays.isHoliday(day);
    final red = holiday || day.weekday == DateTime.sunday;
    final today = day == EventFilter.dayOf(DateTime.now());

    final fg = !enabled
        ? Colors.black12
        : selected
        ? Colors.white
        : red
        ? _kRed
        : day.weekday == DateTime.saturday
        ? _kBlue
        : Colors.black87;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => _toggle(day) : null,
      child: SizedBox(
        height: 42,
        child: Center(
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? _kPink : Colors.transparent,
              shape: BoxShape.circle,
              // 오늘은 테두리로만 — 고른 날(채움)과 헷갈리지 않는다.
              border: today && !selected
                  ? Border.all(color: _kPink, width: 1.4)
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.1,
                    fontWeight: selected || today
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: fg,
                  ),
                ),
                // 공휴일 표시 — 핑크로 채워져 글자색이 흰색이 되어도 이 점은
                // 남아서 "빨간 날"이라는 것을 계속 알려준다.
                if (holiday && enabled)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: selected ? Colors.white : _kRed,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 고른 날짜를 이름표로 — 공휴일이면 무슨 날인지까지 적는다.
  Widget _pickedSummary() {
    final days = _picked.toList()..sort();
    return SizedBox(
      height: 30,
      child: days.isEmpty
          ? Center(
              child: Text(
                '최대 ${widget.maxCount}일까지 고를 수 있어요. 다시 누르면 해제돼요.',
                style: const TextStyle(fontSize: 11.5, color: Colors.black38),
              ),
            )
          : ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: days.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final d = days[i];
                final name = KoreanHolidays.nameOf(d);
                return GestureDetector(
                  onTap: () => setState(() => _picked.remove(d)),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF0F5),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: const Color(0xFFFFD6E4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${d.month}/${d.day}'
                          '(${_weekdayLabels[d.weekday % 7]})'
                          '${name == null ? '' : ' $name'}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: name == null ? _kPink : _kRed,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.close_rounded,
                          size: 12,
                          color: _kPink,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

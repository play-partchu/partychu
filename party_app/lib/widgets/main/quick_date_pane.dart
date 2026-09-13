import 'package:flutter/material.dart';

import 'package:party_app/models/event_filter.dart';

/// 빠른 필터가 펼쳤을 때 쓰는 **알약 칩** 하나 — 플레이스 탭의 날짜·시간 칩과
/// 파티츄 탭의 날짜 칩이 같은 위젯을 쓴다.
///
/// 각자 그리면 같은 뜻의 칩이 탭마다 다른 높이·색으로 보인다. 모양(둥근 알약,
/// 선택 시 핑크 채움)은 여기 한 곳에만 있다.
class QuickFilterChip extends StatelessWidget {
  static const Color pink = Color(0xFFFF6FA0);

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// 글자 앞에 붙는 작은 아이콘('날짜 선택'의 달력 등).
  final IconData? icon;

  /// 좌우 여백만 줄인다 — 칩 여러 개를 한 줄에 밀어 넣을 때만 쓴다.
  final bool dense;

  /// 밤 모드 — 다크 글래스 재질로 바꾼다.
  final bool night;

  const QuickFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.dense = false,
    this.night = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? pink
        : night
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFF6F6F8);
    final border = selected
        ? pink
        : night
        ? Colors.white.withValues(alpha: 0.14)
        : const Color(0xFFEDEDF0);
    final fg = selected
        ? Colors.white
        : night
        ? Colors.white70
        : const Color(0xFF4A4A4A);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 11, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: fg),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: dense ? 11.5 : 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 📅 아이콘을 눌렀을 때 그 자리에서 펼쳐지는 **날짜 빠른선택 줄**.
///
///    오늘(수)  내일(목)  모레(금)  📅 날짜 선택   ← 그 뒤 날짜는 달력으로
///
/// 플레이스 탭이 쓰던 줄을 그대로 뽑아 파티츄 탭과 함께 쓴다 — 버튼 모양·높이·
/// 간격·선택 색이 두 탭에서 갈라질 수 없다. 표기는 [EventFilter.dayLabel]
/// 하나로 통일한다(상단 필터 칩·상세검색 요약도 같은 글자를 쓴다).
///
/// 이 위젯은 화면만 담당한다 — 고른 날짜를 어디에 담고 어떻게 거를지는 탭마다
/// 자기 필터([EventFilter] / [PartyFilter])에 그대로 남아 있다.
class QuickDatePane extends StatelessWidget {
  /// 지금 걸려 있는 날짜들 — 시각이 잘린 날짜여야 한다.
  final Set<DateTime> selected;

  /// 칩 하나를 켜고 끌 때. 최대 개수를 넘겨 아무것도 바뀌지 않는 경우의 안내는
  /// 호출부가 맡는다(탭마다 최대 개수가 자기 필터에 있다).
  final ValueChanged<DateTime> onToggleDate;

  /// '날짜 선택' — 달력 바텀시트를 여는 것은 호출부다.
  final VoidCallback onPickCalendar;

  /// '초기화' — null이면 칩 자체를 두지 않는다.
  final VoidCallback? onClear;

  /// 밤 모드 재질.
  final bool night;

  /// 칩이 붙는 쪽 — 자기를 연 아이콘 쪽에 맞춘다.
  final WrapAlignment alignment;

  const QuickDatePane({
    super.key,
    required this.selected,
    required this.onToggleDate,
    required this.onPickCalendar,
    this.onClear,
    this.night = false,
    this.alignment = WrapAlignment.start,
  });

  /// 바로 누를 수 있는 날 수 — 오늘·내일·모레.
  static const int quickDayCount = 3;

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final today = _dayOf(DateTime.now());
    final quick = [
      for (var i = 0; i < quickDayCount; i++) today.add(Duration(days: i)),
    ];
    // 달력으로 고른 날짜도 칩으로 보여야 다시 눌러 해제할 수 있다.
    final extra = (selected.toList()..sort()).where((d) => !quick.contains(d));

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: alignment,
      children: [
        for (final d in [...quick, ...extra])
          QuickFilterChip(
            label: EventFilter.dayLabel(d),
            selected: selected.contains(d),
            night: night,
            onTap: () => onToggleDate(d),
          ),
        QuickFilterChip(
          label: '날짜 선택',
          icon: Icons.calendar_month_rounded,
          selected: false,
          night: night,
          onTap: onPickCalendar,
        ),
        // 여러 날을 골랐을 때 하나씩 끄지 않아도 되게 — 날짜 조건만 비운다.
        if (onClear != null && selected.isNotEmpty)
          QuickFilterChip(
            label: '초기화',
            icon: Icons.close_rounded,
            selected: false,
            night: night,
            onTap: onClear!,
          ),
      ],
    );
  }
}

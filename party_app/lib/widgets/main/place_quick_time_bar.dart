import 'package:flutter/material.dart';

import 'package:party_app/models/capacity_filter.dart';
import 'package:party_app/models/event_filter.dart';
import 'package:party_app/models/korean_holidays.dart';
import 'package:party_app/models/place_availability.dart';
import 'package:party_app/widgets/main/capacity_picker_sheet.dart';
import 'package:party_app/widgets/main/korean_calendar_sheet.dart';
import 'package:party_app/widgets/main/quick_date_pane.dart';
import 'package:party_app/widgets/main/quick_filter_icon_button.dart';
import 'package:party_app/widgets/main/visit_time_picker_sheet.dart';

/// 플레이스 목록 위 **상단 컨트롤 한 줄**의 왼쪽 절반 — 방문 조건(날짜·시간·
/// 인원) 버튼 하나와, 그 아래로 펼쳐지는 선택지.
///
/// 줄의 최종 모습은 넷이다(오른쪽 둘은 [middle]·[trailing]로 받는다):
///
///     ╭──────────╮ ╭────────────────╮            ╭────╮ ╭────╮
///     │ 📅 🕐 👥 │ │ ✨ 편의·서비스 ▾│            │ ▦ │ │ 🔍 │
///     ╰──────────╯ ╰────────────────╯            ╰────╯ ╰────╯
///
/// ## 왜 셋이 한 버튼인가
///
/// 예전에는 📅 / 🕐 / 👥가 각자 버튼이었고 누른 쪽만 펼쳐졌다. 그런데 이 줄에
/// 편의·서비스와 보기 방식·돋보기까지 함께 앉으면서 셋만으로 줄의 절반을 먹게
/// 됐다(좁은 화면에서는 넘쳤다). 그래서 **버튼은 하나로 묶고, 열면 셋이 함께
/// 펼쳐진다** — 셋 중 하나를 고르러 들어와 다른 하나도 바꾸는 일이 흔해서
/// 오히려 손이 덜 간다.
///
/// 무엇이 걸려 있는지는 접힌 상태에서도 보인다 — 아이콘 하나하나가 자기
/// 조건이 켜졌을 때만 핑크로 물든다([QuickConditionGroupButton]).
///
/// 메인은 위 카테고리 영역이 이미 크다. 그래서 이 줄은 평소에 **버튼 한 개
/// 높이(32px)** 밖에 쓰지 않는다 — 고르는 동안에만 아래로 열리고, 고르고 나면
/// 다시 접혀 원래 높이로 돌아간다(팝업도 바텀시트도 아니다).
///
/// 상세검색과 **같은 [EventFilter] 하나**를 그대로 고쳐 쓴다(별도 상태를 두지
/// 않는다) — 여기서 고른 날짜·시각은 상세검색 시트를 열면 이미 선택된 채로
/// 보이고, 반대로 시트에서 바꾼 값도 이 버튼에 즉시 나타난다. 이 위젯은 화면만
/// 담당하고, 판정(그 시각에 영업하는가)은 main_screen의 영업시간 판정이
/// 그대로 맡는다.
///
/// 날짜·시간·인원은 서로 독립이라 하나만 골라도 된다.
/// - 날짜만  → 그날(들) 여는 곳
/// - 시간대만 → 요일과 상관없이 그 시간대에 여는 곳
/// - 둘 다   → 그 날짜(들)의 그 시간대
/// - 인원    → 그 인원을 받을 수 있는 곳([CapacityFilter])
///
/// 고른 시간대를 "전부"로 볼지 "일부라도 겹치면"으로 볼지는 상세검색의
/// 운영시간 조건([EventFilter.openMode])을 그대로 따른다 — '24시간'처럼 일부만
/// 겹쳐서는 뜻이 사라지는 칩 하나만 예외로 '전부'로 맞춘다.
///
/// 날짜는 [EventFilter.maxVisitDates]일까지 **중복 선택**할 수 있고, 여러 날을
/// 고르면 "그중 하루라도 여는 곳"이 된다.
class PlaceQuickTimeBar extends StatefulWidget {
  /// 상세검색과 공유하는 필터 — 이 위젯이 직접 고치고 [onChanged]를 부른다.
  final EventFilter filter;

  /// 값이 바뀔 때마다 호출 — 호출부는 setState만 하면 목록이 다시 걸러진다.
  final VoidCallback onChanged;

  /// 플레이스 탭의 밤 모드 여부 — 버튼·칩 재질을 다크 글래스로 바꾼다.
  final bool night;

  /// 줄 좌우 여백 — 목록 위에 그대로 놓을 때는 16, 이미 여백이 있는 좌측 필터
  /// 패널 안에서는 0을 준다.
  final double horizontalPadding;

  /// 방문 조건 버튼 **바로 오른쪽**에 붙는 위젯(✨ 편의·서비스 버튼).
  /// 남는 폭을 전부 가져가므로, 이것을 주면 [trailing]이 줄 맨 오른쪽에 붙는다.
  final Widget? middle;

  /// 같은 줄 **오른쪽 끝**에 함께 앉히는 위젯(보기 방식 + 돋보기).
  /// 필터와 보기 방식이 각자 한 줄씩 쓰지 않게 하기 위함이다.
  final Widget? trailing;

  const PlaceQuickTimeBar({
    super.key,
    required this.filter,
    required this.onChanged,
    this.night = false,
    this.horizontalPadding = 16,
    this.middle,
    this.trailing,
  });

  /// 바로 누를 수 있는 방문 **시간대** 두 가지 — 구간 자체가 조건이다.
  ///
  /// - `심야 00~05시` → 00:00 ~ 05:00
  /// - `24시간`       → 00:00 ~ 익일 00:00, 즉 하루 전체. 종료가 시작과 같아
  ///   자정을 넘긴 구간이 되므로 "하루 내내 문이 열려 있는 곳"이 된다
  ///   ([wholeDay]일 때만 운영시간 조건을 '전체'로 맞춘다 — '일부라도'로 두면
  ///   24시간이라는 말이 뜻을 잃는다).
  static const List<
    ({TimeOfDay start, TimeOfDay end, String label, bool wholeDay})
  >
  presetRanges = [
    (
      start: TimeOfDay(hour: 0, minute: 0),
      end: TimeOfDay(hour: 5, minute: 0),
      label: '심야 00~05시',
      wholeDay: false,
    ),
    (
      start: TimeOfDay(hour: 0, minute: 0),
      end: TimeOfDay(hour: 0, minute: 0),
      label: '24시간',
      wholeDay: true,
    ),
  ];

  @override
  State<PlaceQuickTimeBar> createState() => _PlaceQuickTimeBarState();
}

class _PlaceQuickTimeBarState extends State<PlaceQuickTimeBar> {
  /// 선택지가 펼쳐져 있는가 — 날짜·시간·인원이 **함께** 열리고 함께 닫힌다.
  bool _open = false;

  EventFilter get _filter => widget.filter;
  bool get _night => widget.night;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 아래 여백은 두지 않는다 — 목록이 이 줄 바로 다음부터 시작해야 한다.
      padding: EdgeInsets.fromLTRB(
        widget.horizontalPadding,
        2,
        widget.horizontalPadding,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 평소 모습은 이 한 줄이 전부다:
          //   [📅 🕐 👥]  [✨ 편의·서비스 ▼]        [보기 방식] [🔍]
          // 왼쪽 끝이 방문 조건, 그 옆이 [middle](편의·서비스), 오른쪽 끝이
          // [trailing](보기 방식 + 돋보기)이다. 가운데 칸이 남는 폭을 다
          // 가져가므로 돋보기는 언제나 줄 맨 오른쪽에 앉는다.
          Row(
            children: [
              QuickConditionGroupButton(
                label: _groupLabel(),
                opened: _open,
                night: _night,
                onTap: _toggle,
                icons: [
                  QuickConditionIcon(
                    icon: Icons.calendar_today_rounded,
                    active: _filter.visitDates.isNotEmpty,
                  ),
                  QuickConditionIcon(
                    icon: Icons.schedule_rounded,
                    active: _filter.hasTimeCondition,
                  ),
                  QuickConditionIcon(
                    icon: Icons.people_alt_rounded,
                    active: _filter.minCapacity != null,
                  ),
                ],
              ),
              if (widget.middle != null) ...[
                const SizedBox(width: 6),
                // 남는 폭을 전부 가져가되 알맹이는 왼쪽에 붙인다 — 폭이
                // 모자라면 칩이 스스로 줄어든다(글자는 …로 잘린다).
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: widget.middle!,
                  ),
                ),
              ] else if (widget.trailing != null)
                const Spacer(),
              if (widget.trailing != null) ...[
                const SizedBox(width: 6),
                widget.trailing!,
              ],
            ],
          ),
          // 펼쳐지는 선택지 — 팝업이 아니라 버튼 바로 밑에 붙는 인라인 영역
          // 이고, 닫으면 위젯 자체가 사라져 높이가 그대로 돌아온다.
          if (_open) _pane(),
        ],
      ),
    );
  }

  /// 접힌 버튼의 툴팁·접근성 라벨 — 지금 걸린 조건을 그대로 읽어준다.
  /// 아이콘 색만으로는 스크린리더에 아무것도 전달되지 않기 때문이다.
  String _groupLabel() {
    final on = [
      if (_filter.visitDates.isNotEmpty) '날짜 ${_filter.visitDates.length}일',
      if (_timeLabel() != null) '시간 ${_timeLabel()}',
      if (_filter.minCapacity != null)
        '인원 ${CapacityFilter.label(_filter.minCapacity!)}',
    ];
    return on.isEmpty ? '방문 조건 · 날짜 시간 인원' : '방문 조건 · ${on.join(' · ')}';
  }

  /// 인원 선택 — 고르는 즉시 목록에 반영된다(적용 버튼 없음).
  /// 시트를 그냥 닫으면 기존 값이 그대로 남는다.
  Future<void> _pickCapacity() async {
    final picked = await showCapacityPickerSheet(
      context,
      selected: _filter.minCapacity,
    );
    if (!mounted) return;
    if (picked == _filter.minCapacity) return;
    setState(() => _filter.minCapacity = picked);
    widget.onChanged();
  }

  /// 펼쳐진 선택지 — **날짜 · 시간 · 인원 세 줄이 함께** 열린다. 어느 줄인지
  /// 작은 글씨로 앞에 붙여 두어, 셋이 한 번에 보여도 뒤섞여 읽히지 않는다.
  /// 적용 버튼은 없다(누르는 즉시 반영).
  ///
  /// 날짜 줄은 파티츄 탭과 함께 쓰는 [QuickDatePane]이다 — 두 탭의 날짜
  /// 빠른선택이 갈라지지 않게 그리기를 한 곳에 두었다.
  Widget _pane() {
    return Padding(
      padding: const EdgeInsets.only(top: 7, bottom: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _section(
            '날짜',
            // 날짜는 여러 날을 고를 수 있으므로 하나 골랐다고 접지 않는다
            // (다 고르고 버튼을 다시 누르면 접힌다).
            QuickDatePane(
              selected: _filter.visitDates,
              onToggleDate: _toggleDate,
              onPickCalendar: () =>
                  _pickDate(EventFilter.dayOf(DateTime.now())),
              onClear: () => _apply(_filter.clearDate),
              night: _night,
              alignment: WrapAlignment.start,
            ),
          ),
          _section(
            '시간',
            Wrap(spacing: 6, runSpacing: 6, children: _timeChips()),
          ),
          _section(
            '인원',
            Wrap(spacing: 6, runSpacing: 6, children: _capacityChips()),
          ),
        ],
      ),
    );
  }

  /// 펼친 선택지의 한 줄 — 왼쪽에 이름표, 오른쪽에 칩들.
  Widget _section(String title, Widget body) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 이름표 폭을 고정해 세 줄의 칩 시작점이 정확히 맞는다.
        SizedBox(
          width: 30,
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _night ? Colors.white54 : Colors.black38,
              ),
            ),
          ),
        ),
        Expanded(child: body),
      ],
    ),
  );

  /// 시간 — 시간대 하나만 걸 수 있으므로 고르면 그 값만 바뀐다(줄은 열린 채).
  /// 한 줄에 그대로 들어가도록 칩을 조금 더 좁게 그린다(dense).
  List<Widget> _timeChips() {
    final custom = _customTimeLabel();
    return [
      // '전체' = 시간 조건 해제. 날짜 조건은 그대로 남는다(서로 독립).
      _chip(
        label: '전체',
        selected: !_filter.hasTimeCondition,
        dense: true,
        onTap: () => _apply(_filter.clearTime),
      ),
      for (final r in PlaceQuickTimeBar.presetRanges)
        _chip(
          label: r.label,
          selected: _filter.isVisitRange(r.start, r.end),
          dense: true,
          onTap: () => _apply(
            () => _filter.setVisitRange(
              r.start,
              r.end,
              mode: r.wholeDay ? PlaceAvailabilityMode.full : null,
            ),
          ),
        ),
      _chip(
        // 상세검색에서 고른 값이나 여기서 직접 지정한 범위가 그대로 뜬다 —
        // 두 입구가 같은 상태를 보고 있다는 것이 바로 보이게.
        label: custom ?? '시간지정',
        selected: custom != null,
        dense: true,
        onTap: _pickCustom,
      ),
    ];
  }

  /// 인원 — 일행 규모 구간([CapacityFilter.presets])을 지름길로 두고, 목록에
  /// 없는 인원(7명·13명·27명)은 '직접'이 스테퍼 시트를 연다.
  ///
  /// 저장값도 판정도 예전 그대로 정수 하나다 — 구간은 그 정수를 읽기 좋게
  /// 부르는 이름일 뿐이고, 시트가 돌려주는 값과 완전히 같은 자리에 들어간다.
  List<Widget> _capacityChips() {
    final picked = _filter.minCapacity;
    final isPreset =
        picked != null && CapacityFilter.presetLabel(picked) != null;
    return [
      _chip(
        label: '전체',
        selected: picked == null,
        dense: true,
        onTap: () => _apply(() => _filter.minCapacity = null),
      ),
      for (final p in CapacityFilter.presets)
        _chip(
          label: p.label,
          selected: picked == p.people,
          dense: true,
          onTap: () => _apply(() => _filter.minCapacity = p.people),
        ),
      _chip(
        // 구간에 없는 인원을 고른 상태면 그 값을 칩이 그대로 말한다('7명').
        label: picked != null && !isPreset
            ? CapacityFilter.label(picked)
            : '직접',
        selected: picked != null && !isPreset,
        dense: true,
        onTap: _pickCapacity,
      ),
    ];
  }

  // ── 라벨 ────────────────────────────────────────────────────────────
  /// 시간대 표기 — '00–05' / 자정을 넘기면 '22–02', 종료 자정은 '20–24'.
  /// 프리셋과 똑같은 구간이면 프리셋 이름('24시간')을 그대로 쓴다.
  static String _rangeLabel(TimeOfDay start, TimeOfDay end) {
    for (final r in PlaceQuickTimeBar.presetRanges) {
      if (r.start == start && r.end == end) return r.label;
    }
    return '${_hourText(start)}–${_hourText(end, isEnd: true)}';
  }

  /// 정각이면 '18'/'02'처럼 시만, 분이 있으면 '19:30'까지.
  /// 끝의 자정은 하루의 끝이라 '00'이 아니라 '24'로 읽는다.
  static String _hourText(TimeOfDay t, {bool isEnd = false}) {
    final h = isEnd && t.hour == 0 && t.minute == 0 ? 24 : t.hour;
    final hh = h.toString().padLeft(2, '0');
    return t.minute == 0 ? hh : '$hh:${t.minute.toString().padLeft(2, '0')}';
  }

  /// 지금 걸린 시간 조건의 짧은 표기 — 시각 하나면 '20:00', 범위면
  /// '20:00–02:00'. 조건이 없으면 null.
  String? _timeLabel() {
    if (_filter.hasTimePoint) return _filter.timePointChipLabel;
    if (!_filter.hasTimeRange) return null;
    return _rangeLabel(_filter.startTime!, _filter.endTime!);
  }

  /// 프리셋 칩으로는 표현되지 않는 조건의 표기 — '시간지정' 칩에 그대로 얹는다.
  /// 시각 하나는 프리셋(시간대)과 겹칠 수 없으므로 언제나 여기 뜬다.
  String? _customTimeLabel() {
    if (_filter.hasTimePoint) return _filter.timePointChipLabel;
    if (!_filter.hasTimeRange) return null;
    final preset = PlaceQuickTimeBar.presetRanges.any(
      (r) => _filter.isVisitRange(r.start, r.end),
    );
    return preset ? null : _rangeLabel(_filter.startTime!, _filter.endTime!);
  }

  // ── 입력 ────────────────────────────────────────────────────────────
  /// 버튼을 누르면 셋이 함께 펼쳐지고, 다시 누르면 함께 접힌다.
  void _toggle() => setState(() => _open = !_open);

  /// 고른 순간 필터에 바로 반영한다.
  ///
  /// 고르고 나서 **접지 않는다** — 셋이 한 번에 열려 있으므로, 시간을 골랐다고
  /// 접히면 그 아래 인원 줄까지 함께 사라져 다시 열어야 한다.
  void _apply(VoidCallback change) {
    setState(change);
    widget.onChanged();
  }

  /// 날짜 하나를 켜고 끈다 — 여러 날을 고르는 중이므로 여기서는 접지 않는다.
  /// 이미 최대 개수를 골랐으면 [EventFilter.toggleVisitDate]가 아무것도 바꾸지
  /// 않고 false를 주므로, 그때만 안내를 띄운다.
  void _toggleDate(DateTime date) {
    var changed = false;
    _apply(() => changed = _filter.toggleVisitDate(date));
    if (changed) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text(
            '방문 날짜는 최대 ${EventFilter.maxVisitDates}일까지 고를 수 있어요.',
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
  }

  /// '날짜 선택'만 달력을 띄운다 — 한 번에 여러 날(최대
  /// [EventFilter.maxVisitDates]일)을 고를 수 있는 한국식 달력이다(일요일·공휴일
  /// 빨강, 토요일 파랑). 확인을 누르면 고른 날짜가 그대로 필터가 된다.
  ///
  /// 고를 수 있는 마지막 날은 **공휴일 표가 아는 범위까지**로 줄인다 — 표에
  /// 없는 해를 열어 설·추석이 평일처럼 보이는 일을 막기 위함이다. 표가 낡아
  /// 오늘보다 앞서면 범위를 그대로 두고, 달력이 안내 문구를 대신 띄운다
  /// ([KoreanHolidays.clampToSupported]).
  Future<void> _pickDate(DateTime today) async {
    final picked = await showKoreanCalendarSheet(
      context,
      selected: _filter.visitDates,
      firstDate: today,
      lastDate: KoreanHolidays.clampToSupported(
        DateTime(today.year + 1, today.month, today.day),
        notBefore: today,
      ),
    );
    if (picked == null || !mounted) return;
    _apply(() => _filter.visitDates = {...picked});
  }

  /// '시간지정' — 지정시간(20:00)이든 지정구간(20:00 ~ 익일 02:00)이든 여기서
  /// 고른다.
  /// 두 방식은 뜻이 다른 별개의 조건이라 시트 안에서 먼저 방식을 고르게 하고,
  /// 고르는 자체는 30분 단위 휠로 돌린다(긴 목록 스크롤 없음).
  ///
  /// 취소하면 기존 조건은 그대로 둔다.
  Future<void> _pickCustom() async {
    final picked = await showVisitTimePicker(
      context,
      start: _filter.startTime,
      end: _filter.endTime,
    );
    if (picked == null || !mounted) return;
    _apply(() {
      final end = picked.end;
      if (end == null) {
        // 시각 하나 — "그 시각에 영업 중"(hasTimePoint).
        _filter.startTime = picked.start;
        _filter.endTime = null;
      } else {
        _filter.setVisitRange(picked.start, end);
      }
    });
  }

  // ── 부품 ──────────────────────────────────────
  /// 펼친 선택지 안의 칩 — 그리기는 파티츄 탭과 함께 쓰는 [QuickFilterChip]이
  /// 맡는다(밤은 다크 글래스, 낮은 옅은 회색 알약, 선택만 핑크 채움).
  /// [dense]는 좌우 여백만 줄인다 — 시간대 칩 여섯 개가 한 줄에 들어가게.
  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
    bool dense = false,
  }) => QuickFilterChip(
    label: label,
    selected: selected,
    onTap: onTap,
    icon: icon,
    dense: dense,
    night: _night,
  );
}

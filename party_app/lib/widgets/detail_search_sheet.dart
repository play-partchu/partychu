import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:party_app/models/party_filter.dart';
import 'package:party_app/models/party_constants.dart';
import 'package:party_app/models/region_data.dart';
import 'package:party_app/widgets/partychu_ui.dart';

/// 메인·지도 화면에서 공유하는 상세검색 바텀시트.
/// [partyDates] — 달력에 점(●)을 표시할 파티 날짜 집합.
///
/// 모든 필터 항목(지역/날짜/성별/연령/참가비/파티 유형/분위기/태그/정렬/기타)은
/// 기본적으로 접혀 있고, 탭하면 그 자리에서 펼쳐지는 아코디언 형태다. 선택된
/// 값이 있으면 접힌 상태에서도 헤더 우측에 한 줄 요약으로 보여준다
/// (`_accordion`의 summary/hasSelection 파라미터).
class DetailSearchSheet extends StatefulWidget {
  final PartyFilter initialFilter;
  final Set<DateTime> partyDates;

  const DetailSearchSheet({
    super.key,
    required this.initialFilter,
    this.partyDates = const {},
  });

  @override
  State<DetailSearchSheet> createState() => _DetailSearchSheetState();
}

class _DetailSearchSheetState extends State<DetailSearchSheet> {
  late PartyFilter _draft;

  // 달력 상태
  bool _showCalendar = false;
  DateTime _focusedDay = DateTime.now();

  // 펼쳐진 아코디언 섹션 키 집합 — 기본은 전부 접힘.
  final Set<String> _expanded = {};

  // 지역 아코디언에서 현재 보고 있는 시/도 탭.
  late String _regionActiveCity;

  final _tagCtrl = TextEditingController();

  static const _genderConditions = ['남녀무관', '남자만', '여자만', '성비 맞춤'];
  static const _ageGroups = ['20대', '30대', '40대 이상'];
  static const _feeRanges = [
    '무료', '1만원 이하', '1~3만원', '3~5만원', '5~10만원', '10~20만원', '20만원 이상',
  ];
  static const _dateOptions = ['오늘', '내일', '이번주', '이번주말'];

  @override
  void initState() {
    super.initState();
    _draft = widget.initialFilter.copy();
    _showCalendar = _draft.selectedDate != null;
    if (_draft.selectedDate != null) _focusedDay = _draft.selectedDate!;
    _regionActiveCity = RegionData.regions.first;
  }

  @override
  void dispose() {
    _tagCtrl.dispose();
    super.dispose();
  }

  // ── 날짜 포맷 헬퍼 ─────────────────────────────────────────────────
  static String _fmtTime(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static String _fmtDate(DateTime d) => '${d.month}월 ${d.day}일';

  // ── 파티 날짜 여부 (달력 점 표시용) ───────────────────────────────
  bool _hasParty(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return widget.partyDates.contains(d);
  }

  // ── 시간 피커 ────────────────────────────────────────────────────
  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart
          ? (_draft.startTime ?? const TimeOfDay(hour: 18, minute: 0))
          : (_draft.endTime ?? const TimeOfDay(hour: 23, minute: 0)),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _draft.startTime = picked;
        } else {
          _draft.endTime = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => DecoratedBox(
        // 기본 흰 시트 대신 아주 은은한 핑크 톤 배경으로 — PartyChu다운
        // 화사한 분위기를 화면 전체에 깔아준다(카드 자체는 흰색으로 남겨
        // 카드/배경 구분이 또렷하게 보이게 한다).
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFF7FA), Color(0xFFFFFCFD)],
            stops: [0.0, 0.3],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 14),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD1E4),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Icon(Icons.tune_rounded, size: 20, color: PartyChuColors.primary),
                  const SizedBox(width: 8),
                  const Text(
                    '상세검색',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: PartyChuColors.heading,
                    ),
                  ),
                  const Spacer(),
                  _ResetButton(
                    onTap: () => setState(() {
                      _draft = PartyFilter();
                      _showCalendar = false;
                    }),
                  ),
                ],
              ),
              _selectedChipsRow(),
              const SizedBox(height: 4),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  children: [
                    const SizedBox(height: 6),
                    _accordion(
                      sectionKey: 'region',
                      title: '지역',
                      icon: Icons.place_rounded,
                      iconColor: const Color(0xFFFF6FA0),
                      summary: _regionSummaryLabel(),
                      hasSelection: _draft.districts.isNotEmpty,
                      child: _regionAccordionBody(),
                    ),
                    _accordion(
                      sectionKey: 'date',
                      title: '날짜',
                      icon: Icons.calendar_month_rounded,
                      iconColor: const Color(0xFF5B8DEF),
                      summary: _dateSummaryLabel(),
                      hasSelection: _dateHasSelection,
                      child: _dateAccordionBody(),
                    ),
                    _accordion(
                      sectionKey: 'gender',
                      title: '성별',
                      icon: Icons.wc_rounded,
                      iconColor: const Color(0xFF4ECBA7),
                      summary: _summaryOrAll(_draft.genderConditions),
                      hasSelection: _draft.genderConditions.isNotEmpty,
                      child: _multiChipWrap(_genderConditions, _draft.genderConditions),
                    ),
                    _accordion(
                      sectionKey: 'age',
                      title: '연령',
                      icon: Icons.cake_rounded,
                      iconColor: const Color(0xFFB06CFF),
                      summary: _summaryOrAll(_draft.ageGroups),
                      hasSelection: _draft.ageGroups.isNotEmpty,
                      child: _multiChipWrap(_ageGroups, _draft.ageGroups),
                    ),
                    _accordion(
                      sectionKey: 'fee',
                      title: '참가비',
                      icon: Icons.payments_rounded,
                      iconColor: const Color(0xFFFFA552),
                      summary: _summaryOrAll(_draft.feeRanges),
                      hasSelection: _draft.feeRanges.isNotEmpty,
                      child: _multiChipWrap(_feeRanges, _draft.feeRanges),
                    ),
                    _accordion(
                      sectionKey: 'partyTypes',
                      title: '파티 유형',
                      icon: Icons.celebration_rounded,
                      iconColor: const Color(0xFFFF5C93),
                      summary: _summaryOrAll(
                        _draft.partyTypes.map(PartyConstants.labelFor),
                        joiner: ' · ',
                      ),
                      hasSelection: _draft.partyTypes.isNotEmpty,
                      child: _multiChipWrap(
                        PartyConstants.partyTypes,
                        _draft.partyTypes,
                        labelBuilder: PartyConstants.labelFor,
                        titleFont: true,
                      ),
                    ),
                    _accordion(
                      sectionKey: 'vibes',
                      title: '분위기',
                      icon: Icons.auto_awesome_rounded,
                      iconColor: const Color(0xFF9C6BFF),
                      summary: _summaryOrAll(_draft.vibes, joiner: ' · '),
                      hasSelection: _draft.vibes.isNotEmpty,
                      child: _multiChipWrap(PartyConstants.vibes, _draft.vibes),
                    ),
                    _accordion(
                      sectionKey: 'tags',
                      title: '태그',
                      icon: Icons.sell_rounded,
                      iconColor: const Color(0xFF4DB6E0),
                      summary: _summaryOrAll(
                        _draft.tagKeywords.map((t) => '#$t'),
                      ),
                      hasSelection: _draft.tagKeywords.isNotEmpty,
                      child: _tagAccordionBody(),
                    ),
                    _accordion(
                      sectionKey: 'sort',
                      title: '정렬',
                      icon: Icons.sort_rounded,
                      iconColor: const Color(0xFFFF8FB3),
                      summary: _draft.sortMode.label,
                      hasSelection: _draft.sortMode != PartySortMode.defaultOrder,
                      child: _sortAccordionBody(),
                    ),
                    _accordion(
                      sectionKey: 'other',
                      title: '기타 필터',
                      icon: Icons.stars_rounded,
                      iconColor: const Color(0xFF6C8CFF),
                      summary: _draft.earlyBirdOnly ? '얼리버드 진행중' : '전체',
                      hasSelection: _draft.earlyBirdOnly,
                      child: _otherFiltersAccordionBody(),
                    ),
                    const SizedBox(height: 6),
                    // "모집중만 보기"를 대체 — 단순 모집 상태가 아니라 로그인한
                    // 사용자의 성별/연령 조건과 정원까지 반영해 실제로 신청
                    // 가능한 파티만 보여준다(checkPartyEligibility 재사용).
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: PartyChuColors.primary.withValues(alpha: 0.06),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: PartyChuColors.primary,
                        title: const Text('내가 참여 가능한 파티만 보기',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        subtitle: const Text(
                          '성별·연령 조건과 모집 마감 여부를 반영해 실제로 신청 가능한 파티만 보여줘요.',
                          style: TextStyle(fontSize: 11.5, color: PartyChuColors.muted),
                        ),
                        value: _draft.eligibleOnly,
                        onChanged: (v) => setState(() => _draft.eligibleOnly = v),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              PartyChuPrimaryButton(
                label: '적용하기',
                height: 56,
                showBadge: false,
                onTap: () => Navigator.pop(context, _draft),
              ),
              SizedBox(height: 14 + MediaQuery.of(context).padding.bottom),
            ],
          ),
        ),
      ),
    );
  }

  // ── 아코디언 공통 틀 — 기본 접힘, 탭하면 펼침. 선택값이 있으면 접힌
  // 상태에서도 헤더 우측에 요약(summary)을 강조 색으로 보여준다. 은은한
  // 그림자가 있는 흰 카드 + 항목 성격에 맞는 컬러 아이콘 + 부드럽게
  // 회전하는 화살표 + 펼침/접힘 애니메이션으로 구성한다. ─────────
  Widget _accordion({
    required String sectionKey,
    required String title,
    required IconData icon,
    required Color iconColor,
    required String summary,
    required bool hasSelection,
    required Widget child,
  }) {
    final expanded = _expanded.contains(sectionKey);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: PartyChuColors.primary.withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ScaleTap(
            rippleRadius: BorderRadius.circular(20),
            onTap: () => setState(() {
              if (expanded) {
                _expanded.remove(sectionKey);
              } else {
                _expanded.add(sectionKey);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  Icon(icon, size: 21, color: iconColor),
                  const SizedBox(width: 10),
                  Text(title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: PartyChuColors.heading,
                      )),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: hasSelection
                            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 5)
                            : EdgeInsets.zero,
                        decoration: BoxDecoration(
                          color: hasSelection
                              ? PartyChuColors.surfaceTint
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          summary,
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                hasSelection ? FontWeight.w800 : FontWeight.normal,
                            color: hasSelection
                                ? PartyChuColors.primaryDeep
                                : PartyChuColors.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: const Icon(
                      Icons.expand_more_rounded,
                      size: 22,
                      color: PartyChuColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: child,
            ),
            crossFadeState:
                expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
            sizeCurve: Curves.easeInOut,
            firstCurve: Curves.easeIn,
            secondCurve: Curves.easeOut,
          ),
        ],
      ),
    );
  }

  // 값이 없으면 "전체"로 표시하는 공통 요약 포맷터.
  String _summaryOrAll(Iterable<String> values, {String joiner = ', '}) =>
      values.isEmpty ? '전체' : values.join(joiner);

  // ── 지역 아코디언 ─────────────────────────────────────────────────
  // 선택된 지역을 요약 문구로("전체" / "서울 강남구" / "서울 강남구, 마포구" /
  // "서울 강남구 외 2곳").
  String _regionSummaryLabel() {
    final districts = _draft.districts;
    if (districts.isEmpty) return '전체';
    final list = districts.toList();
    String withRegion(String d) {
      final regions = RegionData.regionsOfDistrict(d);
      return regions.isNotEmpty ? '${regions.first} $d' : d;
    }

    if (list.length == 1) return withRegion(list[0]);
    if (list.length == 2) return '${withRegion(list[0])}, ${list[1]}';
    return '${withRegion(list[0])} 외 ${list.length - 1}곳';
  }

  Widget _regionAccordionBody() {
    final activeDistricts = RegionData.regionDistricts[_regionActiveCity] ?? [];
    final maxed = _draft.districts.length >= PartyFilter.maxDistricts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: RegionData.regions.map((city) {
              final isActive = _regionActiveCity == city;
              final hasInCity = (RegionData.regionDistricts[city] ?? [])
                  .any(_draft.districts.contains);
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _ScaleTap(
                  onTap: () => setState(() => _regionActiveCity = city),
                  rippleRadius: BorderRadius.circular(16),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: isActive
                          ? PartyChuColors.primary
                          : hasInCity
                              ? const Color(0xFFFFE8F2)
                              : const Color(0xFFF5F5F7),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                color: PartyChuColors.primary.withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      city,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: isActive
                            ? Colors.white
                            : hasInCity
                                ? PartyChuColors.primary
                                : Colors.black54,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: activeDistricts.map((d) {
            final sel = _draft.districts.contains(d);
            final blocked = !sel && maxed;
            return _chip(
              d,
              sel,
              dim: blocked,
              onTap: blocked
                  ? null
                  : () => setState(() {
                        if (sel) {
                          _draft.districts.remove(d);
                        } else {
                          _draft.districts.add(d);
                        }
                      }),
            );
          }).toList(),
        ),
        if (maxed) ...[
          const SizedBox(height: 8),
          Text(
            '지역은 최대 ${PartyFilter.maxDistricts}개까지 선택할 수 있어요.',
            style: const TextStyle(fontSize: 11, color: Colors.black38),
          ),
        ],
      ],
    );
  }

  // ── 날짜 아코디언 (빠른 날짜 칩+달력 + 파티 시작 시간대) ──────────
  bool get _dateHasSelection =>
      _draft.dateOptions.isNotEmpty ||
      _draft.selectedDate != null ||
      _draft.timeOfDayStart != null ||
      _draft.timeOfDayEnd != null;

  String _dateSummaryLabel() {
    if (_draft.dateOptions.isNotEmpty) return _draft.dateOptions.join(', ');
    if (_draft.selectedDate != null) {
      var s = _fmtDate(_draft.selectedDate!);
      if (_draft.startTime != null || _draft.endTime != null) {
        final st = _draft.startTime != null ? _fmtTime(_draft.startTime!) : '';
        final et = _draft.endTime != null ? _fmtTime(_draft.endTime!) : '';
        s += ' $st~$et';
      }
      return s;
    }
    if (_draft.timeOfDayStart != null || _draft.timeOfDayEnd != null) {
      final s = _draft.timeOfDayStart != null
          ? PartyFilter.formatAmPm(_draft.timeOfDayStart!)
          : '';
      final e = _draft.timeOfDayEnd != null
          ? PartyFilter.formatAmPm(_draft.timeOfDayEnd!)
          : '';
      return '$s ~ $e';
    }
    return '전체';
  }

  Widget _dateAccordionBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 기존 빠른 날짜 칩
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ..._dateOptions.map((opt) {
              final isSelected = _draft.dateOptions.contains(opt);
              return _chip(
                opt,
                isSelected,
                onTap: () => setState(() {
                  if (isSelected) {
                    _draft.dateOptions.remove(opt);
                  } else {
                    _draft.dateOptions.add(opt);
                    // 날짜 직접선택 초기화
                    _draft.selectedDate = null;
                    _draft.startTime = null;
                    _draft.endTime = null;
                    _showCalendar = false;
                  }
                }),
              );
            }),

            // 날짜 직접선택 버튼
            _chip(
              _draft.selectedDate != null
                  ? _fmtDate(_draft.selectedDate!)
                  : '날짜 선택',
              _showCalendar || _draft.selectedDate != null,
              icon: Icons.calendar_today_rounded,
              onTap: () => setState(() {
                _showCalendar = !_showCalendar;
                if (!_showCalendar) {
                  _draft.selectedDate = null;
                  _draft.startTime = null;
                  _draft.endTime = null;
                } else {
                  // 기존 빠른 칩 해제
                  _draft.dateOptions.clear();
                }
              }),
            ),
          ],
        ),

        // 달력 (날짜 선택 버튼 눌렀을 때)
        if (_showCalendar) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8FB),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: PartyChuColors.border),
            ),
            child: TableCalendar(
              firstDay: DateTime.now().subtract(const Duration(days: 1)),
              lastDay: DateTime.now().add(const Duration(days: 365)),
              focusedDay: _focusedDay,
              selectedDayPredicate: (day) =>
                  _draft.selectedDate != null &&
                  isSameDay(day, _draft.selectedDate!),
              onDaySelected: (selected, focused) {
                setState(() {
                  _draft.selectedDate =
                      DateTime(selected.year, selected.month, selected.day);
                  _focusedDay = focused;
                });
              },
              eventLoader: (day) => _hasParty(day) ? [true] : [],
              calendarStyle: CalendarStyle(
                selectedDecoration: const BoxDecoration(
                  color: Color(0xFFFF6FA0),
                  shape: BoxShape.circle,
                ),
                todayDecoration: BoxDecoration(
                  color: const Color(0xFFFF6FA0).withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                markerDecoration: const BoxDecoration(
                  color: Color(0xFFFF6FA0),
                  shape: BoxShape.circle,
                ),
                markerSize: 5,
                markersMaxCount: 1,
                outsideDaysVisible: false,
              ),
              headerStyle: const HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextStyle:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                leftChevronIcon:
                    Icon(Icons.chevron_left, color: Color(0xFFFF6FA0)),
                rightChevronIcon:
                    Icon(Icons.chevron_right, color: Color(0xFFFF6FA0)),
              ),
              onPageChanged: (focused) => setState(() => _focusedDay = focused),
              locale: 'ko_KR',
            ),
          ),

          // 시간 범위 선택 (날짜 선택 후에만 표시)
          if (_draft.selectedDate != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: PartyChuColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.access_time_outlined,
                      size: 16, color: PartyChuColors.primary),
                  const SizedBox(width: 6),
                  const Text('시간 범위',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: PartyChuColors.heading)),
                  const Spacer(),
                  // 시작 시간
                  _ScaleTap(
                    onTap: () => _pickTime(true),
                    rippleRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: _draft.startTime != null
                            ? PartyChuColors.primary
                            : PartyChuColors.surfaceTint,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _draft.startTime != null
                            ? _fmtTime(_draft.startTime!)
                            : '시작',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _draft.startTime != null
                              ? Colors.white
                              : PartyChuColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text('~',
                        style: TextStyle(fontSize: 14, color: Colors.black45)),
                  ),
                  // 종료 시간
                  _ScaleTap(
                    onTap: () => _pickTime(false),
                    rippleRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: _draft.endTime != null
                            ? PartyChuColors.primary
                            : PartyChuColors.surfaceTint,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _draft.endTime != null
                            ? _fmtTime(_draft.endTime!)
                            : '종료',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _draft.endTime != null
                              ? Colors.white
                              : PartyChuColors.primary,
                        ),
                      ),
                    ),
                  ),
                  // 시간 초기화
                  if (_draft.startTime != null || _draft.endTime != null) ...[
                    const SizedBox(width: 6),
                    _ScaleTap(
                      onTap: () => setState(() {
                        _draft.startTime = null;
                        _draft.endTime = null;
                      }),
                      rippleRadius: BorderRadius.circular(12),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.close_rounded,
                            size: 16, color: Colors.black38),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],

        const SizedBox(height: 20),
        const Divider(height: 1, color: PartyChuColors.border),
        const SizedBox(height: 16),

        // ── 파티 시작 시간(날짜와 무관하게 시간대만 비교) ──────────
        Row(
          children: [
            const Icon(Icons.schedule_rounded, size: 15, color: PartyChuColors.primary),
            const SizedBox(width: 6),
            const Text('파티 시작 시간',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: PartyChuColors.heading)),
            const Spacer(),
            if (_draft.timeOfDayStart == null && _draft.timeOfDayEnd == null)
              const Text('전체 시간',
                  style: TextStyle(fontSize: 11, color: PartyChuColors.muted)),
          ],
        ),
        const SizedBox(height: 4),
        const Text('날짜와 상관없이 이 시간대에 시작하는 파티를 모두 찾아요.',
            style: TextStyle(fontSize: 11, color: PartyChuColors.muted)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: PartyChuColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: _ScaleTap(
                  onTap: () => _pickTimeOfDay(true),
                  rippleRadius: BorderRadius.circular(10),
                  child: _timeSelectorBox(_draft.timeOfDayStart, '시작'),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child:
                    Text('~', style: TextStyle(fontSize: 14, color: Colors.black45)),
              ),
              Expanded(
                child: _ScaleTap(
                  onTap: () => _pickTimeOfDay(false),
                  rippleRadius: BorderRadius.circular(10),
                  child: _timeSelectorBox(_draft.timeOfDayEnd, '끝'),
                ),
              ),
              if (_draft.timeOfDayStart != null || _draft.timeOfDayEnd != null) ...[
                const SizedBox(width: 6),
                _ScaleTap(
                  onTap: () => setState(() {
                    _draft.timeOfDayStart = null;
                    _draft.timeOfDayEnd = null;
                  }),
                  rippleRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded, size: 18, color: Colors.black38),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── 파티 시작 시간 피커 ────────────────────────────────────────────
  Future<void> _pickTimeOfDay(bool isStart) async {
    final current = isStart ? _draft.timeOfDayStart : _draft.timeOfDayEnd;
    final picked = await showModalBottomSheet<TimeOfDay>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _TimeOfDayPickerSheet(
        title: isStart ? '시작 시간' : '종료 시간',
        selected: current,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _draft.timeOfDayStart = picked;
        } else {
          _draft.timeOfDayEnd = picked;
        }
      });
    }
  }

  Widget _timeSelectorBox(TimeOfDay? value, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: value != null ? PartyChuColors.primary : PartyChuColors.surfaceTint,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                value != null ? PartyFilter.formatAmPm(value) : label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: value != null ? Colors.white : PartyChuColors.primary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down_rounded,
                size: 18, color: value != null ? Colors.white : PartyChuColors.primary),
          ],
        ),
      );

  // ── 태그 아코디언 ─────────────────────────────────────────────────
  void _addTagKeyword() {
    final v = _tagCtrl.text.trim().replaceFirst('#', '');
    if (v.isEmpty) return;
    setState(() {
      _draft.tagKeywords.add(v);
      _tagCtrl.clear();
    });
  }

  Widget _tagAccordionBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _tagCtrl,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _addTagKeyword(),
          style: const TextStyle(fontSize: 14, color: PartyChuColors.heading),
          decoration: InputDecoration(
            hintText: '태그 검색어 입력 (예: 감성, 소규모)',
            hintStyle: const TextStyle(fontSize: 13, color: PartyChuColors.muted),
            isDense: true,
            filled: true,
            fillColor: PartyChuColors.surfaceTint,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: PartyChuColors.primary, width: 1.4),
            ),
            suffixIcon: IconButton(
              icon: const Icon(Icons.add_circle_rounded, color: PartyChuColors.primary),
              onPressed: _addTagKeyword,
            ),
          ),
        ),
        if (_draft.tagKeywords.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _draft.tagKeywords
                .map((t) => Chip(
                      label: Text('#$t',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: PartyChuColors.primaryDeep)),
                      deleteIcon: const Icon(Icons.close_rounded, size: 14),
                      deleteIconColor: PartyChuColors.primary,
                      onDeleted: () =>
                          setState(() => _draft.tagKeywords.remove(t)),
                      backgroundColor: PartyChuColors.surfaceTint,
                      side: BorderSide(color: PartyChuColors.border),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ))
                .toList(),
          ),
        ],
      ],
    );
  }

  // ── 정렬 아코디언 ─────────────────────────────────────────────────
  Widget _sortAccordionBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: PartySortMode.values.map((mode) {
        final sel = _draft.sortMode == mode;
        return _ScaleTap(
          onTap: () => setState(() => _draft.sortMode = mode),
          rippleRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: sel ? PartyChuColors.surfaceTint : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 19,
                  height: 19,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: sel ? PartyChuColors.primary : Colors.black26,
                      width: 2,
                    ),
                  ),
                  child: sel
                      ? Center(
                          child: Container(
                            width: 9,
                            height: 9,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: PartyChuColors.primary,
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Text(
                  mode.label,
                  style: TextStyle(
                    fontSize: 14,
                    color: sel ? PartyChuColors.primaryDeep : PartyChuColors.heading,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── 기타 필터 아코디언 ────────────────────────────────────────────
  Widget _otherFiltersAccordionBody() {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      activeThumbColor: PartyChuColors.primary,
      secondary: const Icon(Icons.bolt_rounded, color: Color(0xFFFFA552)),
      title: const Text('얼리버드 진행중만 보기',
          style: TextStyle(
              fontWeight: FontWeight.w700, fontSize: 14, color: PartyChuColors.heading)),
      value: _draft.earlyBirdOnly,
      onChanged: (v) => setState(() => _draft.earlyBirdOnly = v),
    );
  }

  // ── 선택된 조건 칩 행 ─────────────────────────────────────────────
  Widget _selectedChipsRow() {
    final entries = _draft.selectedEntries;
    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('선택된 조건이 없습니다',
              style: TextStyle(fontSize: 12, color: PartyChuColors.muted)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: entries
            .map((e) => Chip(
                  avatar: e.key == 'districts'
                      ? const Icon(Icons.place_rounded,
                          size: 15, color: PartyChuColors.primary)
                      : null,
                  label: Text(
                    e.key == 'partyTypes'
                        ? PartyConstants.labelFor(e.value)
                        : e.value,
                    style: TextStyle(
                      fontFamily: e.key == 'partyTypes' ? 'SeoulHangang' : null,
                      fontSize: 12,
                    ),
                  ),
                  labelStyle: const TextStyle(
                      color: PartyChuColors.primaryDeep, fontWeight: FontWeight.w600),
                  deleteIcon: const Icon(Icons.close_rounded, size: 14),
                  deleteIconColor: PartyChuColors.primary,
                  onDeleted: () => setState(() {
                    _draft.removeValue(e.key, e.value);
                    if (e.key == 'selectedDate') _showCalendar = false;
                  }),
                  backgroundColor: PartyChuColors.surfaceTint,
                  side: BorderSide(color: PartyChuColors.border),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ))
            .toList(),
      ),
    );
  }

  // 칩 하나하나가 (선택 시) 살짝 눌리는 스케일 + 리플을 받도록 _ScaleTap으로
  // 감싸 자체 완결형으로 만든다 — 호출부는 더 이상 별도 GestureDetector로
  // 감쌀 필요 없이 onTap만 넘기면 된다. dim(선택 불가)일 때는 onTap이
  // null로 넘어와 자연히 탭이 막힌다.
  Widget _chip(
    String label,
    bool isSelected, {
    bool dim = false,
    IconData? icon,
    VoidCallback? onTap,
    bool titleFont = false,
  }) {
    return _ScaleTap(
      onTap: onTap,
      rippleRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected
              ? PartyChuColors.primary
              : dim
                  ? const Color(0xFFF5F5F7)
                  : PartyChuColors.surfaceTint,
          borderRadius: BorderRadius.circular(18),
          border: isSelected
              ? null
              : Border.all(
                  color: dim ? const Color(0xFFEDEDF0) : PartyChuColors.border,
                ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: PartyChuColors.primary.withValues(alpha: 0.28),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: isSelected ? Colors.white : PartyChuColors.primary,
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontFamily: titleFont ? 'SeoulHangang' : null,
                fontSize: 13,
                color: isSelected
                    ? Colors.white
                    : dim
                        ? Colors.black26
                        : PartyChuColors.heading,
                fontWeight: titleFont
                    ? FontWeight.w500
                    : (isSelected ? FontWeight.w700 : FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _multiChipWrap(
    List<String> options,
    Set<String> selected, {
    String Function(String)? labelBuilder,
    bool titleFont = false,
  }) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: options.map((opt) {
        final isSelected = selected.contains(opt);
        return _chip(
          labelBuilder != null ? labelBuilder(opt) : opt,
          isSelected,
          titleFont: titleFont,
          onTap: () => setState(() {
            if (isSelected) {
              selected.remove(opt);
            } else {
              selected.add(opt);
            }
          }),
        );
      }).toList(),
    );
  }
}

/// 탭하면 살짝 눌리는 스케일 애니메이션 + (선택 시) Material 잉크 리플을
/// 함께 주는 공통 터치 래퍼 — 아코디언 헤더/칩/지역 탭/시간 버튼 등 상세검색
/// 시트 전체의 터치 피드백을 이 위젯 하나로 통일한다. [rippleRadius]를
/// 주면 Material+InkWell로 리플이 함께 뜨고, 생략하면 스케일만 적용된다.
class _ScaleTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? rippleRadius;

  const _ScaleTap({required this.child, required this.onTap, this.rippleRadius});

  @override
  State<_ScaleTap> createState() => _ScaleTapState();
}

class _ScaleTapState extends State<_ScaleTap> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (widget.onTap == null) return;
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final hasRipple = widget.rippleRadius != null;
    final content = hasRipple
        ? Material(
            color: Colors.transparent,
            borderRadius: widget.rippleRadius,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: widget.rippleRadius,
              child: widget.child,
            ),
          )
        : widget.child;

    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: hasRipple ? null : widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: content,
      ),
    );
  }
}

/// "전체 초기화" — 텍스트 버튼 대신 발바닥이 아닌 새로고침 아이콘이 붙은
/// 연핑크 필 버튼으로, 눌리는 촉감이 느껴지는 실제 액션 버튼처럼 보이게 한다.
class _ResetButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ResetButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _ScaleTap(
      onTap: onTap,
      rippleRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: PartyChuColors.surfaceTint,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: PartyChuColors.border),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.refresh_rounded, size: 15, color: PartyChuColors.primaryDeep),
            SizedBox(width: 5),
            Text(
              '전체 초기화',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: PartyChuColors.primaryDeep,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "파티 시작 시간" 선택 시트 — 하루를 30분 단위로 나눈 목록에서 하나를 고른다.
class _TimeOfDayPickerSheet extends StatefulWidget {
  final String title;
  final TimeOfDay? selected;

  const _TimeOfDayPickerSheet({required this.title, this.selected});

  @override
  State<_TimeOfDayPickerSheet> createState() => _TimeOfDayPickerSheetState();
}

class _TimeOfDayPickerSheetState extends State<_TimeOfDayPickerSheet> {
  late final ScrollController _scrollCtrl;

  @override
  void initState() {
    super.initState();
    // 이미 고른 시간이 있으면 그 위치로 바로 스크롤해서 보여준다.
    final slots = PartyFilter.halfHourSlots;
    final selectedIndex = widget.selected == null
        ? -1
        : slots.indexWhere((t) =>
            t.hour == widget.selected!.hour && t.minute == widget.selected!.minute);
    final initialOffset = selectedIndex > 0 ? (selectedIndex - 2).clamp(0, slots.length) * 48.0 : 0.0;
    _scrollCtrl = ScrollController(initialScrollOffset: initialOffset);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slots = PartyFilter.halfHourSlots;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFFFD1E4),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 14),
            Text(widget.title,
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: PartyChuColors.heading)),
            const Divider(height: 24, color: PartyChuColors.border),
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                itemCount: slots.length,
                itemBuilder: (ctx, i) {
                  final t = slots[i];
                  final isSelected = widget.selected != null &&
                      widget.selected!.hour == t.hour &&
                      widget.selected!.minute == t.minute;
                  return _ScaleTap(
                    onTap: () => Navigator.pop(context, t),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? PartyChuColors.surfaceTint : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Text(
                            PartyFilter.formatAmPm(t),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                              color: isSelected
                                  ? PartyChuColors.primaryDeep
                                  : PartyChuColors.heading,
                            ),
                          ),
                          const Spacer(),
                          if (isSelected)
                            const Icon(Icons.check_circle_rounded,
                                color: PartyChuColors.primary, size: 20),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

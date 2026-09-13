import 'package:flutter/material.dart';
import 'package:party_app/models/custom_amenity.dart';
import 'package:party_app/models/place_availability.dart';
import 'package:party_app/models/place_filter.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/models/region_selection.dart';
import 'package:party_app/models/reservation_modes.dart';
import 'package:party_app/widgets/custom_amenity_browse_sheet.dart';
import 'package:party_app/widgets/filter_sheet_ui.dart';
import 'package:party_app/widgets/main/search_entry_sheet.dart';
import 'package:party_app/widgets/partychu_ui.dart';

/// 장소대여 탭 전용 상세검색 바텀시트.
///
/// **화면 구조는 파티 상세검색([DetailSearchSheet])과 같다** — 같은
/// [FilterSheetShell] 골격에, 모든 항목이 기본 접힘인 [FilterAccordionSection]
/// 아코디언으로만 이루어진다. 처음 열면 '이용 날짜·시간 / 장소 유형 / 가격
/// 범위 / 수용 인원 / 편의시설 / 기타 조건' 제목만 보이고, 누른 항목만 그
/// 자리에서 펼쳐진다. 고른 값은 접힌 상태에서도 제목 옆 요약으로 보인다.
///
/// **'지역'은 이 시트의 칸이 아니다.** 목록 위 줄 왼쪽 끝의 '지역선택'
/// 버튼이 같은 값([PlaceFilter.regions])을 고른다 — 같은 조건을 두 곳에 두면
/// 어느 쪽이 지금 값인지 알기 어려워서다. **조건 자체는 그대로 살아 있다** —
/// 거기서 고른 지역은 이 시트를 열면 제목 줄 아래 선택 칩(핀 아이콘)으로
/// 보이고 거기서 하나씩 뺄 수 있으며, '전체 초기화'도 예전처럼 함께 푼다.
/// '예약 방식'도 같은 이유로 이 시트에 없다(아래 sections의 ⚠️ 주석 참고).
///
/// **달라지는 건 항목뿐이다** — 필터 로직(무엇을 어떻게 거를지)은 [PlaceFilter]
/// 가, 지역 선택 규칙(최대 5개, 시/도 전체와 개별 구의 정리)은
/// [RegionSelection]이 그대로 맡는다.
class PlaceDetailSearchSheet extends StatefulWidget {
  final PlaceFilter initialFilter;

  /// 목록 헤더의 돋보기로 열렸을 때만 채워진다 — 그러면 이 시트가 곧 검색
  /// 시트가 되어 조건들 위에 검색어 입력창이 함께 붙는다([FilterSheetShell]).
  final SearchEntryConfig? search;

  /// "전체 초기화"로 조건이 풀렸을 때, 시트를 닫지 않고도 목록에 바로
  /// 반영하라고 호출부에 건네는 길 — 검색어가 즉시 풀리는 것과 짝을 맞춘다
  /// ([DetailSearchSheet.onFilterReset]과 같은 규칙).
  final ValueChanged<PlaceFilter>? onFilterReset;

  /// 지금 검색 범위에 실제로 등록돼 있는 **기타 편의 서비스** 목록(개수 포함).
  ///
  /// 플레이스 상세검색([EventDetailSearchSheet])과 **같은 계약**이다 —
  /// 호출부가 이미 메모리에 들고 있는 문서에서 만들어 넘기고, 이 시트는
  /// 조회를 하지 않는다. 비어 있으면 그 칸 자체가 그려지지 않는다.
  final List<CustomAmenityEntry> customAmenityEntries;

  const PlaceDetailSearchSheet({
    super.key,
    required this.initialFilter,
    this.search,
    this.onFilterReset,
    this.customAmenityEntries = const [],
  });

  @override
  State<PlaceDetailSearchSheet> createState() => _PlaceDetailSearchSheetState();
}

class _PlaceDetailSearchSheetState extends State<PlaceDetailSearchSheet> {
  late PlaceFilter _draft;

  /// 펼쳐진 아코디언 섹션 키 — 기본은 전부 접힘(파티 상세검색과 같은 규칙).
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _draft = widget.initialFilter.copy();
  }

  @override
  Widget build(BuildContext context) {
    return FilterSheetShell(
      title: '장소대여 상세검색',
      search: widget.search,
      selectedChips: FilterSelectedChips(
        entries: _draft.selectedEntries,
        avatarBuilder: (e) => e.key == 'regions'
            ? const Icon(
                Icons.place_rounded,
                size: 15,
                color: PartyChuColors.primary,
              )
            : null,
        onDelete: (e) => setState(() => _draft.removeValue(e.key, e.value)),
      ),
      onReset: () {
        setState(() => _draft = PlaceFilter());
        // 사본을 넘긴다 — 이어서 고르는 값이 "검색" 전에 목록으로 새면 안 된다.
        widget.onFilterReset?.call(_draft.copy());
      },
      onApply: () => Navigator.pop(context, _draft),
      sections: [
        // ⚠️ '지역' 칸은 여기 없다 — 목록 위 줄 왼쪽 끝의 '지역선택'
        //    버튼이 같은 값([PlaceFilter.regions])을 고른다.
        _accordion(
          sectionKey: 'schedule',
          title: '이용 날짜·시간',
          icon: Icons.calendar_month_rounded,
          iconColor: const Color(0xFF5B8DEF),
          summary: _scheduleSummaryLabel(),
          hasSelection: _draft.useDate != null,
          child: _scheduleBody(),
        ),
        // ⚠️ '예약 방식' 칸도 없다 — 같은 줄의 ⏱/🛏 대여유형 버튼이 같은
        //    한 칸([PlaceFilter.reservationMode])을 고친다.
        //
        //    두 조건 모두 **그대로 살아 있다** — 목록 위에서 고른 값은 이
        //    시트를 열어도 풀리지 않고 판정도 예전 그대로다. '전체 초기화'는
        //    예전처럼 지역·대여유형까지 함께 푼다.
        // 🏠 장소 유형은 여기와 **목록 위 대여유형 버튼** 두 곳에서 고를 수
        // 있고, 고치는 칸은 하나다([PlaceFilter.placeTypes]) — 위에서 파티룸을
        // 골랐으면 이 칸에도 켜져 있고, 여기서 호텔을 더하면 위 버튼 글자도
        // 따라 바뀐다. 목록 판정도 한 함수뿐이다
        // ([PlaceFilter.matchesPlaceTypes] — 고른 것 중 하나라도 해당하면 통과).
        _accordion(
          sectionKey: 'placeTypes',
          title: '장소 유형',
          icon: Icons.home_work_rounded,
          iconColor: const Color(0xFFFF5C93),
          summary: filterSummaryOrAll(_draft.placeTypes),
          hasSelection: _draft.placeTypes.isNotEmpty,
          child: FilterChipWrap(
            options: ListingConstants.placeTypes,
            selected: _draft.placeTypes,
            onChanged: () => setState(() {}),
          ),
        ),
        _accordion(
          sectionKey: 'price',
          title: '가격 범위',
          icon: Icons.payments_rounded,
          iconColor: const Color(0xFFFFA552),
          summary: filterSummaryOrAll(_draft.priceRanges),
          hasSelection: _draft.priceRanges.isNotEmpty,
          child: FilterChipWrap(
            options: ListingConstants.placePriceRanges,
            selected: _draft.priceRanges,
            onChanged: () => setState(() {}),
          ),
        ),
        _accordion(
          sectionKey: 'capacity',
          title: '수용 인원',
          icon: Icons.groups_rounded,
          iconColor: const Color(0xFFB06CFF),
          summary: filterSummaryOrAll(_draft.capacityRanges),
          hasSelection: _draft.capacityRanges.isNotEmpty,
          child: FilterChipWrap(
            options: ListingConstants.placeCapacityRanges,
            selected: _draft.capacityRanges,
            onChanged: () => setState(() {}),
          ),
        ),
        _accordion(
          sectionKey: 'facilities',
          title: '편의시설',
          icon: Icons.chair_rounded,
          iconColor: const Color(0xFF4ECBA7),
          summary: filterSummaryOrAll(_draft.facilities),
          hasSelection: _draft.facilities.isNotEmpty,
          child: FilterChipWrap(
            options: ListingConstants.placeFacilities,
            selected: _draft.facilities,
            onChanged: () => setState(() {}),
          ),
        ),
        // ✨ 기타 편의 서비스 — 위 '편의시설'(프리셋, OR)과 **다른 축**이다.
        // 여기서 고른 값은 AND로 걸린다(플레이스 탭과 같은 규칙).
        if (widget.customAmenityEntries.isNotEmpty) _customAmenityRow(context),
        _accordion(
          sectionKey: 'other',
          title: '기타 조건',
          icon: Icons.stars_rounded,
          iconColor: const Color(0xFF6C8CFF),
          summary: filterSummaryOrAll([
            if (_draft.petFriendlyOnly) '애견동반',
            if (_draft.outsideFoodOnly) '외부 음식',
          ]),
          hasSelection: _draft.petFriendlyOnly || _draft.outsideFoodOnly,
          child: _otherBody(),
        ),
      ],
    );
  }

  /// 파티 상세검색과 같은 아코디언 — 화면은 공용 [FilterAccordionSection]이
  /// 그리고, 여기서는 어느 섹션이 펼쳐져 있는지만 관리한다.
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
    return FilterAccordionSection(
      title: title,
      icon: icon,
      iconColor: iconColor,
      summary: summary,
      hasSelection: hasSelection,
      expanded: expanded,
      onToggle: () => setState(() {
        if (expanded) {
          _expanded.remove(sectionKey);
        } else {
          _expanded.add(sectionKey);
        }
      }),
      child: child,
    );
  }

  // ── 요약 문구 ─────────────────────────────────────────────────────
  /// '전체' / '서울 강남구' / '서울 강남구 외 2곳'.
  // 아래 둘은 지금 화면에 걸려 있지 않다 — 그 칸들을 목록 위 줄로 넘겼기
  // 때문이다(위 sections 주석). 되돌릴 일이 생기면 칸만 다시 넣으면 되도록
  // 그리는 코드는 그대로 둔다.
  // ignore: unused_element
  String _regionSummaryLabel() {
    final regions = _draft.regions.toList();
    if (regions.isEmpty) return '전체';
    final first = RegionSelection.label(regions.first);
    return regions.length == 1 ? first : '$first 외 ${regions.length - 1}곳';
  }

  String _scheduleSummaryLabel() {
    final date = _draft.useDate;
    if (date == null) return '전체';
    if (!_draft.hasTimeRange) return PlaceFilter.formatDate(date);
    return '${PlaceFilter.formatDate(date)} ${_draft.timeRangeLabel}';
  }

  // ── 이용 날짜 + 이용 시간 ────────────────────────────────────────────
  // 날짜만 고르면 "그날 이용할 수 있는 장소", 시간까지 고르면 "그 시간
  // 전체가 비어 있는 장소"만 남는다. 판정 자체는 PlaceAvailability(공용)가
  // 하고, 여기서는 조건만 받는다.
  Widget _scheduleBody() {
    final date = _draft.useDate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '이용 날짜',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: PartyChuColors.heading,
              ),
            ),
            const Spacer(),
            if (date != null)
              FilterScaleTap(
                onTap: () => setState(_draft.clearSchedule),
                rippleRadius: BorderRadius.circular(10),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text(
                    '날짜·시간 지우기',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: PartyChuColors.primary,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        FilterPickerButton(
          icon: Icons.calendar_today_rounded,
          label: date == null ? '날짜 선택' : PlaceFilter.formatDate(date),
          filled: date != null,
          onTap: _pickDate,
        ),
        const SizedBox(height: 16),
        const Text(
          '이용 시간',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: PartyChuColors.heading,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilterPickerButton(
                icon: Icons.schedule_rounded,
                label: _draft.startTime == null
                    ? '시작 시간'
                    : PlaceFilter.formatTime(_draft.startTime!),
                filled: _draft.startTime != null,
                enabled: date != null,
                onTap: () => _pickTime(isStart: true),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('~', style: TextStyle(color: Colors.black38)),
            ),
            Expanded(
              child: FilterPickerButton(
                icon: Icons.schedule_rounded,
                label: _draft.endTime == null
                    ? '종료 시간'
                    : PlaceFilter.formatTime(_draft.endTime!),
                filled: _draft.endTime != null,
                enabled: date != null,
                onTap: () => _pickTime(isStart: false),
              ),
            ),
          ],
        ),
        // 이용 가능 조건 — 시간을 다 골랐을 때만 뜻이 있다.
        if (_draft.hasTimeRange) ...[
          const SizedBox(height: 16),
          const Text(
            '이용 가능 조건',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: PartyChuColors.heading,
            ),
          ),
          const SizedBox(height: 4),
          for (final mode in PlaceAvailabilityMode.values)
            FilterRadioOption(
              label: mode.label,
              description: mode.description,
              selected: _draft.availabilityMode == mode,
              onTap: () => setState(() => _draft.availabilityMode = mode),
            ),
        ],
        const SizedBox(height: 8),
        FilterHintText(_scheduleHint()),
      ],
    );
  }

  String _scheduleHint() {
    if (_draft.useDate == null) {
      return '날짜를 고르면 그날 이용할 수 있는 장소만 검색돼요.';
    }
    if (!_draft.hasTimeRange) {
      return '시작·종료 시간까지 고르면 그 시간 전체가 비어 있는 장소만 보여줘요.';
    }
    final crosses = _draft.availabilityRequest?.crossesMidnight ?? false;
    final partial = _draft.availabilityMode == PlaceAvailabilityMode.partial;
    final base = partial
        ? '${PlaceFilter.formatDate(_draft.useDate!)} ${_draft.timeRangeLabel} '
              '중 일부라도 이용할 수 있는 장소까지 검색되고, 카드에 실제 이용 '
              '가능한 시간을 보여줘요.'
        : '${PlaceFilter.formatDate(_draft.useDate!)} ${_draft.timeRangeLabel} '
              '전체를 이용할 수 있는 장소만 검색돼요.';
    // 종료가 시작보다 이르면 다음 날로 넘어간 것 — 오해하지 않도록 짚어준다.
    return crosses ? '$base 자정을 넘겨 다음 날까지 이용하는 조건이에요.' : base;
  }

  // ── 기타 조건 (애견동반 / 외부 음식) ────────────────────────────────
  // 외부 음식은 등록 화면이 facilityOptions에 저장한 "외부 음식 반입 가능"만
  // 통과시킨다("협의 후 가능"은 조건이 붙는 곳이라 제외).
  /// 예약 방식 — '전체 / ⏱ 시간제 / 🛏 숙박' 중 **하나만** 고른다.
  ///
  /// 다른 항목들처럼 여러 개를 담는 Set이 아닌 이유: 시간제와 숙박을 둘 다
  /// 고르는 것은 '전체'와 같은 말이라, 세 번째 상태를 만들 뿐 결과가 같다.
  ///
  /// 판정은 룸 문서가 정본이다([placeReservationModes]) — 두 방식을 모두
  /// 받는 장소는 어느 쪽을 골라도 목록에 남는다.
  // ignore: unused_element
  Widget _reservationModeBody() {
    Widget chip(String label, ReservationMode? mode) => FilterOptionChip(
      label: label,
      selected: _draft.reservationMode == mode,
      onTap: () => setState(() => _draft.reservationMode = mode),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            chip('전체', null),
            chip(ReservationMode.hourly.chipLabel, ReservationMode.hourly),
            chip(ReservationMode.stay.chipLabel, ReservationMode.stay),
          ],
        ),
        const SizedBox(height: 8),
        // 목록 위 빠른 선택 시트와 **같은 문장**이다(reservation_modes.dart).
        const FilterHintText(reservationModeOverlapHint),
      ],
    );
  }

  /// 기타 편의 서비스 칸 — 아코디언이 아니라 **누르면 시트가 열리는 줄**이다.
  /// 항목 수가 수십 개가 될 수 있어 아코디언 안에 펼치면 다른 조건이 화면
  /// 밖으로 밀린다(초성 탐색도 자기 화면이 있어야 한다).
  /// 플레이스 상세검색과 **같은 시트**([CustomAmenityBrowseSheet])를 연다.
  Widget _customAmenityRow(BuildContext context) {
    final selected = _draft.customAmenities;
    return FilterAccordionSection(
      title: '기타 편의 서비스',
      icon: Icons.auto_awesome_rounded,
      iconColor: const Color(0xFF7C5CBF),
      summary: selected.isEmpty ? '전체' : selected.join(' · '),
      hasSelection: selected.isNotEmpty,
      expanded: false,
      onToggle: () => _openCustomAmenitySheet(context),
      child: const SizedBox.shrink(),
    );
  }

  Future<void> _openCustomAmenitySheet(BuildContext context) async {
    final picked = await CustomAmenityBrowseSheet.open(
      context,
      entries: widget.customAmenityEntries,
      selected: {..._draft.customAmenities},
    );
    if (picked == null || !mounted) return;
    setState(() {
      _draft.customAmenities
        ..clear()
        ..addAll(picked);
    });
  }

  Widget _otherBody() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilterOptionChip(
          label: '🐶 애견동반 가능만 보기',
          selected: _draft.petFriendlyOnly,
          onTap: () =>
              setState(() => _draft.petFriendlyOnly = !_draft.petFriendlyOnly),
        ),
        FilterOptionChip(
          label: '🍕 외부 음식 가능만 보기',
          selected: _draft.outsideFoodOnly,
          onTap: () =>
              setState(() => _draft.outsideFoodOnly = !_draft.outsideFoodOnly),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _draft.useDate ?? today,
      firstDate: today,
      lastDate: DateTime(now.year + 1, now.month, now.day),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: PartyChuColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(
      () => _draft.useDate = DateTime(picked.year, picked.month, picked.day),
    );
  }

  /// 30분 단위 시간 선택 — 종료 시간이 시작보다 이르면 자정을 넘긴 이용으로
  /// 해석하므로(22:00~02:00) 종료 목록에서도 하루 전체를 그대로 보여준다.
  Future<void> _pickTime({required bool isStart}) async {
    final slots = [
      for (int i = 0; i < 48; i++)
        TimeOfDay(hour: i ~/ 2, minute: (i % 2) * 30),
    ];
    final current = isStart ? _draft.startTime : _draft.endTime;
    final picked = await showModalBottomSheet<TimeOfDay>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text(
                    isStart ? '시작 시간' : '종료 시간',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (current != null)
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isStart) {
                            _draft.startTime = null;
                          } else {
                            _draft.endTime = null;
                          }
                        });
                        Navigator.pop(ctx);
                      },
                      child: const Text(
                        '선택 해제',
                        style: TextStyle(
                          fontSize: 13,
                          color: PartyChuColors.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: 320,
              child: ListView.builder(
                itemCount: slots.length,
                itemBuilder: (_, i) {
                  final t = slots[i];
                  final selected =
                      current?.hour == t.hour && current?.minute == t.minute;
                  return ListTile(
                    dense: true,
                    title: Text(
                      PlaceFilter.formatTime(t),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.normal,
                        color: selected
                            ? PartyChuColors.primary
                            : Colors.black87,
                      ),
                    ),
                    trailing: selected
                        ? const Icon(
                            Icons.check,
                            size: 18,
                            color: PartyChuColors.primary,
                          )
                        : null,
                    onTap: () => Navigator.pop(ctx, t),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _draft.startTime = picked;
      } else {
        _draft.endTime = picked;
      }
    });
  }
}

import 'package:flutter/material.dart';

import 'package:party_app/models/custom_amenity.dart';
import 'package:party_app/models/custom_play_item.dart';
import 'package:party_app/models/event_filter.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/models/place_attributes.dart';
import 'package:party_app/models/place_taxonomy.dart';
import 'package:party_app/models/place_availability.dart';
import 'package:party_app/models/region_selection.dart';
import 'package:party_app/widgets/custom_amenity_browse_sheet.dart';
import 'package:party_app/widgets/filter_sheet_ui.dart';
import 'package:party_app/widgets/main/search_entry_sheet.dart';
import 'package:party_app/widgets/partychu_ui.dart';
import 'package:party_app/widgets/region_grid_selector.dart';

/// 플레이스(events) 탭 전용 상세검색 바텀시트.
///
/// **화면 구조는 파티 상세검색([DetailSearchSheet])·장소대여
/// ([PlaceDetailSearchSheet])와 같다** — 같은 [FilterSheetShell] 골격에, 모든
/// 항목이 기본 접힘인 [FilterAccordionSection] 아코디언이다. 세 탭을 오갈 때
/// 다시 배우는 것이 없도록 겉모습과 조작법을 통째로 맞췄고, **달라지는 건
/// 항목뿐이다**: 장소대여가 수용 인원·시간당 요금·예약 가능 여부를 묻는
/// 자리에서 플레이스는 업종·가격대·영업시간을 묻는다.
///
/// ── 이 시트에서 **빠진** 칸 ───────────────────────────────────────────────
/// 조건이 사라진 것이 아니라 **묻는 자리를 하나로 모은 것**이다. 값도
/// ([EventFilter]) 판정도([EventFilter.matchesDiscovery]) 하나도 바뀌지 않았고,
/// 목록 위에서 켠 값은 이 시트를 열어도 풀리지 않으며 위 선택 칩에 그대로
/// 보인다(거기서 하나씩 뺄 수 있고, '전체 초기화'도 예전처럼 전부 푼다).
///
///   · 분위기(themeTags) — 📸 사진맛집은 ✨ 편의·서비스 시트가, 🎉 이벤트는
///     카테고리 영역이 같은 것을 묻는다. 세 자리에서 같은 조건을 고르게 두면
///     지금 걸린 값이 어느 쪽인지 알 수 없어진다.
///   · 🎁 파티츄 혜택 — ✨ 편의·서비스 시트의 같은 칸
///     ([PlaceFeatures.partychuPerk])이 맡는다.
///
/// 🟢 현재 영업 중만은 반대로 **서랍에서 꺼냈다** — 아래 [FilterToggleCard]
/// 참고.
class EventDetailSearchSheet extends StatefulWidget {
  final EventFilter initialFilter;

  /// 목록 헤더의 돋보기로 열렸을 때만 채워진다 — 그러면 이 시트가 곧 검색
  /// 시트가 되어 조건들 위에 검색어 입력창이 함께 붙는다([FilterSheetShell]).
  final SearchEntryConfig? search;

  /// "전체 초기화"로 조건이 풀렸을 때, 시트를 닫지 않고도 목록에 바로
  /// 반영하라고 호출부에 건네는 길 — 검색어가 즉시 풀리는 것과 짝을 맞춘다
  /// ([DetailSearchSheet.onFilterReset]과 같은 규칙).
  final ValueChanged<EventFilter>? onFilterReset;

  /// 지금 검색 범위에 실제로 등록돼 있는 **기타 편의 서비스** 목록(개수 포함).
  ///
  /// 호출부가 이미 메모리에 들고 있는 문서에서 만들어 넘긴다 — 이 시트는
  /// 조회를 하지 않는다. 비어 있으면 그 칸 자체가 그려지지 않는다(등록된
  /// 기타가 하나도 없는 상태에서 빈 서랍만 남기지 않으려는 것).
  final List<CustomAmenityEntry> customAmenityEntries;

  /// 지금 검색 범위에 실제로 등록돼 있는 **기타 놀거리** 목록(개수 포함).
  ///
  /// 위와 같은 방식으로 호출부가 만들어 넘긴다([CustomPlayItems.catalogOf]).
  /// 비어 있으면 '기타'를 눌렀을 때 "아직 등록된 항목이 없어요"가 뜬다 —
  /// 없는 항목을 만들어 보여주지 않는다.
  final List<CustomPlayItemEntry> customPlayItemEntries;

  /// 🎲 놀거리 줄을 가리키는 키 — '기타' 칩은 생일 혜택 그룹에도 있어서,
  /// 화면 검사가 어느 줄의 '기타'인지 가려낼 수 있어야 한다.
  static const playItemsRowKey = ValueKey('filter-play-items');

  const EventDetailSearchSheet({
    super.key,
    required this.initialFilter,
    this.search,
    this.onFilterReset,
    this.customAmenityEntries = const [],
    this.customPlayItemEntries = const [],
  });

  @override
  State<EventDetailSearchSheet> createState() => _EventDetailSearchSheetState();
}

class _EventDetailSearchSheetState extends State<EventDetailSearchSheet> {
  late EventFilter _draft;

  /// 펼쳐진 아코디언 섹션 키 — 기본은 전부 접힘.
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _draft = widget.initialFilter.copy();
  }

  @override
  Widget build(BuildContext context) {
    return FilterSheetShell(
      title: '플레이스 상세검색',
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
        setState(() => _draft = EventFilter());
        // 사본을 넘긴다 — 이어서 고르는 값이 "검색" 전에 목록으로 새면 안 된다.
        widget.onFilterReset?.call(_draft.copy());
      },
      onApply: () => Navigator.pop(context, _draft),
      sections: [
        _accordion(
          sectionKey: 'region',
          title: '지역',
          icon: Icons.place_rounded,
          iconColor: const Color(0xFFFF6FA0),
          summary: _regionSummaryLabel(),
          hasSelection: _draft.regions.isNotEmpty,
          // 전국 시/도 그리드 → 누른 시/도의 '전체 / 구·시·군' 그리드로
          // 화면이 갈아끼워지는 구조(아래로 펼쳐지지 않는다). 최대 5개
          // 제한도 이 위젯이 그대로 맡는다.
          child: RegionGridSelector(
            selected: _draft.regions,
            onChanged: (_) => setState(() {}),
          ),
        ),
        // ⚠️ '방문 날짜·시간' · '업종 대분류' · '특징' 칸은 여기 없다 —
        //    셋 다 **목록 위에서 이미 고르는 조건**이다:
        //      · 날짜·시간 → 빠른 조건 줄(📅 🕐 👥)
        //      · 업종 대분류·소분류 → 카테고리 격자와 그 드릴다운
        //      · 특징 → ✨ 편의·서비스 시트
        //    같은 선택지를 두 곳에 두면 어느 쪽이 지금 값인지 알기 어렵다.
        //
        //    **조건 자체는 그대로다** — 값은 같은 [EventFilter](visitDates ·
        //    시간 · categories/subcategories · features)에 있고 판정도
        //    [EventFilter.matchesDiscovery] 하나 그대로다. 목록 위에서 고른
        //    값은 이 시트를 열어도 풀리지 않고, 위 선택 칩에 그대로 보이며
        //    거기서 하나씩 뺄 수 있다. '전체 초기화'는 예전처럼 전부 푼다.
        _accordion(
          sectionKey: 'attributes',
          title: '세부 조건',
          icon: Icons.tune_rounded,
          iconColor: const Color(0xFF1F9E77),
          summary: filterSummaryOrAll([
            ..._draft.attributes.values.expand((v) => v),
            ..._draft.customPlayItems,
          ], joiner: ' · '),
          hasSelection:
              _draft.attributes.values.any((v) => v.isNotEmpty) ||
              _draft.customPlayItems.isNotEmpty,
          child: _attributeBody(),
        ),
        // ✨ 기타 편의 서비스 — 호스트가 직접 등록한 항목.
        //
        // 여기서는 "기타 있음/없음"을 묻지 않는다. 그 질문으로는 아무것도
        // 좁혀지지 않고, 호스트가 굳이 적어 넣은 말이 통째로 버려진다.
        // 누르면 실제 항목 목록(초성 탐색 포함)이 열린다.
        if (widget.customAmenityEntries.isNotEmpty) _customAmenityRow(context),
        _accordion(
          sectionKey: 'businessTypes',
          title: '업종',
          icon: Icons.storefront_rounded,
          iconColor: const Color(0xFFFF5C93),
          summary: filterSummaryOrAll(_draft.businessTypes),
          hasSelection: _draft.businessTypes.isNotEmpty,
          child: FilterChipWrap(
            options: ListingConstants.eventBusinessTypes,
            selected: _draft.businessTypes,
            onChanged: () => setState(() {}),
          ),
        ),
        _accordion(
          sectionKey: 'price',
          title: '가격대',
          icon: Icons.payments_rounded,
          iconColor: const Color(0xFFFFA552),
          summary: filterSummaryOrAll(_draft.priceRanges),
          hasSelection: _draft.priceRanges.isNotEmpty,
          child: FilterChipWrap(
            options: ListingConstants.eventPriceRanges,
            selected: _draft.priceRanges,
            onChanged: () => setState(() {}),
          ),
        ),
        // ③ 🟢 현재 영업 중 — **접히지 않는 독립 토글 카드**로 맨 아래,
        //    적용/검색 버튼 바로 위에 둔다.
        //
        //    예전에는 '기타 조건' 아코디언 안에 있었다. 한 칸짜리 서랍이라
        //    열어 보기 전에는 있는 줄도 몰랐고, 정작 "지금 문 연 곳"은 이
        //    시트에서 가장 자주 쓰는 조건이다(파티의 ⚡ 얼리버드를 서랍에서
        //    꺼낸 것과 같은 이유이고, 같은 카드를 쓴다).
        //
        //    ⚠️ 값도 판정도 **예전 그대로**다 — [EventFilter.openNowOnly]
        //    하나이고 [EventFilter.matchesDiscovery]가 그대로 본다. 자리만
        //    옮긴 것이라 목록 위에서 켠 값도, 저장된 조건도 그대로 살아 있다.
        FilterToggleCard(
          icon: const Icon(Icons.storefront_rounded, color: Color(0xFF2FB86B)),
          title: '🟢 현재 영업 중만 보기',
          value: _draft.openNowOnly,
          onChanged: (v) => setState(() => _draft.openNowOnly = v),
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
  String _regionSummaryLabel() {
    final regions = _draft.regions.toList();
    if (regions.isEmpty) return '전체';
    final first = RegionSelection.label(regions.first);
    return regions.length == 1 ? first : '$first 외 ${regions.length - 1}곳';
  }

  /// 날짜만 / 시간만 / 둘 다 — 고른 것만 요약에 담는다. 시각 하나만 고른
  /// 경우('22:00 영업 중')도 메인 화면 빠른 필터와 같은 표기를 쓴다.
  // 아래 셋은 지금 화면에 걸려 있지 않다 — 그 칸들을 목록 위로 넘겼기
  // 때문이다(위 sections 주석). 되돌릴 일이 생기면 칸만 다시 넣으면 되도록
  // 그리는 코드는 그대로 둔다(값을 읽고 쓰지 않으므로 남아 있어도 무해하다).
  // ignore: unused_element
  String _scheduleSummaryLabel() {
    final date = _draft.visitDateLabel;
    final time = _draft.hasTimeCondition ? _draft.timeChipLabel : null;
    if (date == null && time == null) return '전체';
    if (time == null) return date!;
    return date == null ? time : '$date $time';
  }

  // ── 방문 예정 날짜 + 시간 + 운영시간 조건 ──────────────────────────────
  // 장소대여의 "이용 날짜/시간"과 같은 자리·같은 모양이지만 뜻이 다르다 —
  // 장소대여는 "그 시간에 예약이 비어 있는가"를 묻고, 플레이스는 "그 시간에
  // 문을 여는가"를 묻는다(예약 개념이 없는 매장이므로).
  //
  // 그래서 **날짜와 시간이 서로 묶여 있지 않다** — 날짜 없이 시간만 골라
  // "밤 10시~새벽 3시에 여는 가게"를 찾을 수 있고, 한쪽을 지워도 다른 쪽은
  // 그대로 남는다([EventFilter.clearDate]/[EventFilter.clearTime]).
  // ignore: unused_element
  Widget _scheduleBody() {
    final date = _draft.visitDate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(
          '방문 예정 날짜',
          onClear: date == null ? null : () => setState(_draft.clearDate),
        ),
        const SizedBox(height: 8),
        // 오늘·내일은 한 번에 고르고, 그 밖의 날짜만 달력을 연다.
        Row(
          children: [
            _quickDateChip('오늘', 0),
            const SizedBox(width: 8),
            _quickDateChip('내일', 1),
            const SizedBox(width: 8),
            Expanded(
              child: FilterPickerButton(
                icon: Icons.calendar_today_rounded,
                label: _isQuickDate(date)
                    ? '직접 선택'
                    : EventFilter.formatDate(date!),
                filled: date != null && !_isQuickDate(date),
                onTap: _pickDate,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // 시간은 날짜와 별개로 고를 수 있다 — 날짜를 안 골라도 잠기지 않는다.
        _sectionLabel(
          '방문 예정 시간',
          onClear: _draft.startTime == null && _draft.endTime == null
              ? null
              : () => setState(_draft.clearTime),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilterPickerButton(
                icon: Icons.schedule_rounded,
                label: _draft.startTime == null
                    ? '시작 시간'
                    : EventFilter.formatTime(_draft.startTime!),
                filled: _draft.startTime != null,
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
                    : EventFilter.formatTime(_draft.endTime!),
                filled: _draft.endTime != null,
                onTap: () => _pickTime(isStart: false),
              ),
            ),
          ],
        ),
        // 운영시간 조건 — 시간을 다 골랐을 때만 뜻이 있다. 장소대여의
        // "이용 가능 조건"과 같은 enum·같은 라디오 모양을 쓴다.
        if (_draft.hasTimeRange) ...[
          const SizedBox(height: 16),
          const Text(
            '운영시간 조건',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: PartyChuColors.heading,
            ),
          ),
          const SizedBox(height: 4),
          for (final mode in PlaceAvailabilityMode.values)
            FilterRadioOption(
              label: _modeText(mode).label,
              description: _modeText(mode).description,
              selected: _draft.openMode == mode,
              onTap: () => setState(() => _draft.openMode = mode),
            ),
        ],
        const SizedBox(height: 8),
        FilterHintText(_scheduleHint()),
      ],
    );
  }

  /// 아코디언 안의 작은 제목 한 줄 — 값을 고른 뒤에만 오른쪽에 "지우기"가
  /// 붙는다. 날짜와 시간이 각자 자기 것만 지우도록 [onClear]를 따로 받는다.
  /// 대분류 + 고른 대분류의 소분류.
  ///
  /// 소분류는 **고른 대분류 아래 것만** 보여준다 — 60개를 한꺼번에 늘어놓으면
  /// 고를 수가 없고, 어느 대분류에 속한 값인지도 읽히지 않는다.
  // ignore: unused_element
  Widget _categoryBody() {
    final picked = PlaceTaxonomy.all
        .where((c) => _draft.categories.contains(c.label))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilterChipWrap(
          options: PlaceTaxonomy.all.map((c) => c.label).toList(),
          selected: _draft.categories,
          labelBuilder: PlaceTaxonomy.displayOf,
          // 대분류를 끄면 그 아래 소분류도 함께 빠져야 한다 — 부모 없는
          // 소분류만 남으면 무엇을 걸러 주는 조건인지 읽히지 않는다.
          onChanged: () => setState(() {
            _draft.subcategories.removeWhere(
              (sub) => !_draft.categories.any(
                (c) => PlaceTaxonomy.hasSubcategory(c, sub),
              ),
            );
          }),
        ),
        for (final c in picked) ...[
          const SizedBox(height: 14),
          _sectionLabel('${c.display} 세부'),
          const SizedBox(height: 8),
          FilterChipWrap(
            options: c.subcategories,
            selected: _draft.subcategories,
            onChanged: () => setState(() {}),
          ),
        ],
      ],
    );
  }

  /// 세부 속성 — **등록 화면과 같은 목록**을 보여준다
  /// ([PlaceAttributeCatalog.askableFor]).
  ///
  /// 대분류를 고르면 그 업종에서 먼저 묻는 그룹이 앞에 오고, 편의·서비스를
  /// 켜는 나머지 그룹도 뒤따라 나온다 — 호스트가 켤 수 있는 것은 어느 업종
  /// 이든 같으므로, 게스트가 고를 수 있는 것도 같아야 한다. 음악 장르·주류
  /// 종류처럼 특징을 안 켜는 그룹만 업종 안에 머무른다(클럽을 고르지도 않고
  /// 장르를 묻는 것은 뜻이 없고, 목록만 길어진다).
  /// 기타 편의 서비스 칸 — 아코디언이 아니라 **누르면 시트가 열리는 줄**이다.
  /// 항목 수가 수십 개가 될 수 있어 아코디언 안에 펼치면 다른 조건이 화면
  /// 밖으로 밀린다(초성 탐색도 자기 화면이 있어야 한다).
  Widget _customAmenityRow(BuildContext context) {
    final selected = _draft.customAmenities;
    return FilterAccordionSection(
      title: '기타 편의 서비스',
      icon: Icons.auto_awesome_rounded,
      iconColor: const Color(0xFF7C5CBF),
      summary: selected.isEmpty ? '전체' : selected.join(' · '),
      hasSelection: selected.isNotEmpty,
      expanded: false,
      onToggle: () => _openBrowseSheet(context),
      child: const SizedBox.shrink(),
    );
  }

  Future<void> _openBrowseSheet(BuildContext context) async {
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

  Widget _attributeBody() {
    final categories = _draft.categories;
    final all = categories.isEmpty
        ? PlaceAttributeCatalog.askableFor(null)
        : [
            // 여러 업종을 골랐으면 각 업종에서 물어보는 것의 합집합 —
            // 카탈로그 순서를 유지해 화면 순서가 흔들리지 않게 한다.
            for (final g in PlaceAttributeCatalog.all)
              if (categories.any(
                (c) => PlaceAttributeCatalog.askableFor(c).contains(g),
              ))
                g,
          ];
    // ♾ 무제한만 뺀다 — 목록 위 ✨ 편의·서비스 시트 맨 아래가 **같은 값**을
    // 세부종류째 고르는 자리라(업종별 추천 순서까지 거기 있다) 여기 또 두면
    // 같은 조건을 켜는 자리가 둘이 된다. 나머지 그룹(흡연·주차·반입 …)은
    // 목록 위에서 고를 수 없으므로 그대로 남는다.
    final groups = all
        .where((g) => g.key != PlaceAttributeCatalog.unlimitedKey)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < groups.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          _sectionLabel(groups[i].display),
          const SizedBox(height: 8),
          if (groups[i].key == CustomPlayItems.groupKey)
            _playItemsBody(context, groups[i])
          else
            FilterChipWrap(
              options: groups[i].options.map((o) => o.label).toList(),
              // 그룹마다 자기 집합을 그대로 넘긴다 — 비어 있는 집합이
              // 남아도 판정·칩·isActive가 모두 무시하므로 해가 없다.
              selected: _draft.attributes.putIfAbsent(
                groups[i].key,
                () => <String>{},
              ),
              onChanged: () => setState(() {}),
            ),
        ],
      ],
    );
  }

  /// 🎲 놀거리 — 프리셋 칩 + **'기타'는 목록을 여는 칸**.
  ///
  /// '기타'를 있음/없음으로 켜 봐야 아무것도 좁혀지지 않는다(호스트가 만든
  /// 말이라 그 안에 무엇이 있는지가 조건이다). 그래서 이 칩은 켜지는 대신
  /// 지금 등록돼 있는 자유기재 놀거리 목록을 연다 — 목록은 호출부가 이미
  /// 들고 있는 문서에서 만들어 넘긴 것이라 없는 항목이 뜰 수 없다.
  ///
  /// 줄에 키를 다는 이유: '기타' 칩은 생일 혜택 그룹에도 있어서, 화면 검사가
  /// 어느 줄의 '기타'인지 가려낼 수 있어야 한다.
  /// 키는 공개 클래스에 둔다 — 검사가 참조할 수 있어야 한다.

  Widget _playItemsBody(BuildContext context, PlaceAttributeGroup group) {
    final picked = _draft.customPlayItems;
    return Column(
      key: EventDetailSearchSheet.playItemsRowKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            // 프리셋은 예전 그대로 켜고 끈다. '기타'만 빼서 아래 칸이 받는다.
            for (final o in group.options)
              if (o.label != CustomPlayItems.etcOption)
                FilterOptionChip(
                  label: o.display,
                  selected: _presetPlayItems.contains(o.label),
                  onTap: () => setState(() {
                    final set = _presetPlayItems;
                    if (!set.remove(o.label)) set.add(o.label);
                  }),
                ),
            FilterOptionChip(
              label: picked.isEmpty
                  ? CustomPlayItems.etcOption
                  : '${CustomPlayItems.etcOption} ${picked.length}',
              selected: picked.isNotEmpty,
              onTap: () => _openPlayItemSheet(context),
            ),
          ],
        ),
        if (picked.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            picked.join(' · '),
            style: const TextStyle(fontSize: 11.5, color: Colors.black45),
          ),
        ],
      ],
    );
  }

  /// 놀거리 프리셋이 담기는 집합 — 자유기재와 **다른 축**이다.
  Set<String> get _presetPlayItems =>
      _draft.attributes.putIfAbsent(CustomPlayItems.groupKey, () => <String>{});

  Future<void> _openPlayItemSheet(BuildContext context) async {
    final picked = await CustomAmenityBrowseSheet.open(
      context,
      entries: widget.customPlayItemEntries,
      selected: {..._draft.customPlayItems},
      title: CustomPlayItems.sectionTitle,
      subtitle: CustomPlayItems.browseSubtitle,
      emptyText: CustomPlayItems.emptyBrowseMessage,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _draft.customPlayItems
        ..clear()
        ..addAll(picked);
    });
  }

  Widget _sectionLabel(String title, {VoidCallback? onClear}) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: PartyChuColors.heading,
          ),
        ),
        const Spacer(),
        if (onClear != null)
          FilterScaleTap(
            onTap: onClear,
            rippleRadius: BorderRadius.circular(10),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                '지우기',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: PartyChuColors.primary,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 고른 날짜가 오늘/내일 버튼으로 고른 것인지 — 그렇다면 "직접 선택"
  /// 버튼은 비어 있는 모양으로 둔다.
  bool _isQuickDate(DateTime? date) {
    if (date == null) return true;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = date.difference(today).inDays;
    return diff == 0 || diff == 1;
  }

  Widget _quickDateChip(String label, int offsetDays) {
    final now = DateTime.now();
    final target = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(Duration(days: offsetDays));
    return FilterOptionChip(
      label: label,
      selected: _draft.isVisitDate(target),
      // 켜져 있는 것을 다시 누르면 꺼진다 — 시간 조건은 건드리지 않는다.
      // 날짜는 메인 화면과 같은 규칙으로 여러 날을 담을 수 있고(최대
      // [EventFilter.maxVisitDates]일), 꽉 차면 더 담기지 않는다.
      onTap: () => setState(() => _draft.toggleVisitDate(target)),
    );
  }

  /// 플레이스는 예약이 아니라 영업시간을 묻는 것이라, 같은 enum을 쓰되 문구는
  /// 이 화면에 맞게 바꿔 보여준다(장소대여는 '이용', 플레이스는 '영업').
  ({String label, String description}) _modeText(PlaceAvailabilityMode mode) =>
      switch (mode) {
        PlaceAvailabilityMode.full => (
          label: '전체 시간 영업',
          description: '고른 시간 전체 동안 문을 여는 곳만',
        ),
        PlaceAvailabilityMode.partial => (
          label: '일부 시간이라도 영업',
          description: '고른 시간 중 일부라도 문을 여는 곳까지',
        ),
      };

  /// 날짜·시간을 독립으로 고를 수 있게 되면서 경우의 수가 넷이 됐다 — 지금
  /// 무엇으로 검색되는지 문장으로 그대로 알려준다.
  String _scheduleHint() {
    final date = _draft.visitDate;

    // 시작 시각만 고른 경우 — 메인 화면 빠른 방문시간과 같은 뜻이다
    // ("그 시각에 문이 열려 있는 곳"). 종료까지 고르면 시간대 조건이 된다.
    if (_draft.hasTimePoint) {
      final at = _draft.timePointChipLabel;
      final base = date == null
          ? '요일과 상관없이 $at에 영업 중인 곳을 찾아요.'
          : '${_draft.visitDateLabel} $at에 영업 중인 곳만 검색돼요.';
      return '$base 종료 시간까지 고르면 시간대 전체로 조건이 바뀌어요.';
    }

    if (!_draft.hasTimeRange) {
      return date == null
          ? '날짜만, 시간만, 또는 둘 다 고를 수 있어요. 날짜를 고르면 그날 영업하는 '
                '곳만 검색돼요.'
          : '${_draft.visitDateLabel}에 영업하는 곳만 검색돼요. 시간까지 고르면 '
                '그 시간에 문을 여는 곳만 보여줘요.';
    }

    final partial = _draft.openMode == PlaceAvailabilityMode.partial;
    final range = _draft.timeRangeLabel;
    final base = date == null
        // 날짜 없이 시간만 — 요일을 특정하지 않고 영업시간 패턴으로 찾는다.
        ? (partial
              ? '요일과 상관없이 $range 중 일부라도 영업하는 날이 있는 곳까지 검색돼요.'
              : '요일과 상관없이 $range 전체를 영업하는 날이 있는 곳만 검색돼요.')
        : (partial
              ? '${_draft.visitDateLabel} $range 중 일부라도 영업하는 곳까지 검색돼요.'
              : '${_draft.visitDateLabel} $range 전체를 영업하는 곳만 검색돼요.');
    // 종료가 시작보다 이르면 다음 날로 넘어간 것 — 오해하지 않도록 짚어준다.
    return _draft.crossesMidnight ? '$base 자정을 넘겨 다음 날까지 보는 조건이에요.' : base;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _draft.visitDate ?? today,
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
      () => _draft.visitDate = DateTime(picked.year, picked.month, picked.day),
    );
  }

  /// 30분 단위 시간 선택 — 종료가 시작보다 이르면 자정을 넘긴 방문으로
  /// 해석하므로(22:00~03:00) 종료 목록에서도 하루 전체를 그대로 보여준다.
  /// 장소대여 시트의 시간 선택과 완전히 같은 화면이다.
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
                      EventFilter.formatTime(t),
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

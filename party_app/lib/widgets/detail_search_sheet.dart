import 'package:flutter/material.dart';
import 'package:party_app/models/listing_price_match.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:party_app/models/party_filter.dart';
import 'package:party_app/utils/party_scale_filter.dart';
import 'package:party_app/models/party_constants.dart';
import 'package:party_app/models/region_data.dart';
import 'package:party_app/widgets/filter_option_sheet.dart';
import 'package:party_app/widgets/filter_sheet_ui.dart';
import 'package:party_app/widgets/main/search_entry_sheet.dart';
import 'package:party_app/widgets/party_type_vibe_icon.dart';
import 'package:party_app/widgets/partychu_ui.dart';

/// 격자 → 토글 → 토글 → 검색 버튼 사이의 **공통 세로 간격**.
/// 한 곳에서 바꾸면 네 구간이 함께 움직인다.
const double _kSectionGap = 8;

// 토글 카드의 크기·설명 줄 규칙은 [FilterToggleCard](filter_sheet_ui.dart)로
// 옮겼다 — 플레이스 상세검색의 🟢 현재 영업 중 카드와 **같은 하나**를 쓴다.

/// 메인·지도 화면에서 공유하는 상세검색 바텀시트.
/// [partyDates] — 달력에 점(●)을 표시할 파티 날짜 집합.
///
/// **정렬은 여기에 없다** — 메인 목록 우측의 정렬 버튼([PartySortSheet])이
/// 같은 일을 하고 있어 입구가 둘이면 어느 쪽이 지금 값인지 알기 어려웠다.
/// 이 시트는 "무엇을 걸러낼지"만 다루고, 목록을 어떤 순서로 볼지는 정렬 버튼
/// 하나가 맡는다(시트를 열고 닫아도 정렬은 그대로 유지된다).
///
/// ── 배치 ────────────────────────────────────────────────────────────────
/// 필터 항목 다섯(지역/성별/연령/참가비/파티 유형·분위기)은 **2열 균일 격자**의
/// 미니 카드로 깔린다([FilterGridLayout.uniform2]) — 모든 카드의 폭·높이·안쪽
/// 여백·모서리가 같고, 마지막 줄에 한 칸만 남아도 그 칸을 넓히지 않는다.
/// 선택값은 접힌 카드에도 한 줄 요약으로 보인다(`_gridItem`의 summary).
///
/// 시트 자체는 **내용 높이만큼만** 올라온다([FilterSheetSizing.content]) —
/// 고정 높이가 없어서 조건을 펼치면 함께 자라고, 화면 상한에 닿으면 그때부터
/// 항목 목록 안쪽만 스크롤된다(제목 줄과 검색 버튼은 늘 제자리).
///
/// 카드를 누르면 대부분 그 자리에서 펼쳐지지만, **파티 유형·분위기는
/// 바텀시트**가 열린다 — 칸이 마흔이 넘어 펼치면 화면이 그만큼
/// 길어졌다. 시트의 모양은 플레이스의 ♾ 무제한 시트와 공용이다
/// ([showFilterOptionSheet]).
///
/// 격자에 들어가지 않는 on/off 조건(⚡ 얼리버드 · 내가 참여 가능한 파티만)은
/// 맨 아래 독립 토글 카드([FilterToggleCard])로 늘 보인다 — 예전에는 얼리버드가
/// 한 칸짜리 '기타 필터' 서랍 안에 있어 열어 보기 전에는 있는 줄도 몰랐다.
/// 플레이스 상세검색의 🟢 현재 영업 중도 같은 이유로 같은 카드를 쓴다.
class DetailSearchSheet extends StatefulWidget {
  final PartyFilter initialFilter;
  final Set<DateTime> partyDates;

  /// 목록 헤더의 돋보기로 열렸을 때만 채워진다 — 그러면 이 시트가 곧 검색
  /// 시트가 되어 조건들 위에 검색어 입력창이 함께 붙는다([FilterSheetShell]).
  /// 지도 화면처럼 상세검색만 여는 곳에서는 null이라 예전 모습 그대로다.
  final SearchEntryConfig? search;

  /// "전체 초기화"로 조건이 풀렸을 때, 시트를 닫지 않고도 목록에 바로
  /// 반영하라고 호출부에 건네는 길 — 검색어가 즉시 풀리는 것과 짝을 맞춘다.
  /// 빈 필터는 이 시트가 만든 것을 넘기므로(정렬 유지 같은 규칙이 한 곳에만
  /// 있다), 호출부는 "검색"으로 받을 때와 같은 자리에 꽂기만 하면 된다.
  /// 상세검색만 여는 곳(지도 화면·좌측 필터 패널)에서는 null이다.
  final ValueChanged<PartyFilter>? onFilterReset;

  const DetailSearchSheet({
    super.key,
    required this.initialFilter,
    this.partyDates = const {},
    this.search,
    this.onFilterReset,
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

  static const _genderConditions = ['남녀무관', '남자만', '여자만', '성비 맞춤'];
  // 예전에는 마지막 칸이 '40대 이상' 하나였다 — 40대와 50대가 한 칸에 묶여
  // 있어서 50대를 받는 파티만 골라낼 수 없었다. 40대를 따로 떼고 '50대+'를
  // 새로 둔다. 옛 값('40대 이상')은 고르는 자리에서만 빠지고 **판정에서는
  // 계속 받는다**(_matchesAgeGroups) — 저장된 필터가 있어도 깨지지 않게.
  static const _ageGroups = ['20대', '30대', '40대', '50대+'];
  // 참가비 칸은 판정 함수와 **같은 목록**을 쓴다([partyFeeRanges]).
  static const _feeRanges = partyFeeRanges;
  static const _dateOptions = ['오늘', '내일', '이번주', '이번주말'];

  @override
  void initState() {
    super.initState();
    _draft = widget.initialFilter.copy();
    _showCalendar = _draft.selectedDates.isNotEmpty;
    // 여러 날을 골랐으면 가장 이른 날이 있는 달부터 보여준다.
    final dates = _draft.selectedDatesSorted;
    if (dates.isNotEmpty) _focusedDay = dates.first;
    _regionActiveCity = RegionData.regions.first;
  }

  @override
  void dispose() {
    super.dispose();
  }

  // ── 날짜 포맷 헬퍼 ─────────────────────────────────────────────────
  static String _fmtTime(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static String _fmtDate(DateTime d) => PartyFilter.formatDateLabel(d);

  /// 달력에서 날짜를 켜고 끈다 — 최대 개수를 넘기면 안내만 띄우고 선택은
  /// 그대로 둔다(판정은 [PartyFilter.toggleDate] 한 곳에 있다).
  void _toggleDate(DateTime day) {
    if (_draft.toggleDate(day)) {
      setState(() {});
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('날짜는 최대 ${PartyFilter.maxSelectedDates}개까지 선택할 수 있습니다.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

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
    return FilterSheetShell(
      title: '상세검색',
      search: widget.search,
      // 내용 높이만큼만 올라오는 시트 — 조건 칸이 다섯이라 비율로 열면
      // 검색 버튼 아래가 통째로 비어 보였다. 항목이 늘거나 조건을 펼치면
      // 시트도 함께 자라고, 화면 상한에 닿는 순간부터 안쪽이 스크롤된다.
      sizing: FilterSheetSizing.content,
      selectedChips: _selectedChipsRow(),
      // 정렬은 이 시트가 다루는 조건이 아니다 — 초기화해도 목록의 정렬
      // 버튼에서 고른 값은 그대로 둔다.
      onReset: () {
        setState(() {
          _draft = PartyFilter(sortMode: _draft.sortMode);
          _showCalendar = false;
        });
        // 사본을 넘긴다 — 이어서 시트에서 고르는 값이 "검색"을 누르기 전에
        // 목록으로 새어 나가면 안 된다(_draft는 계속 이 시트가 고쳐 쓴다).
        widget.onFilterReset?.call(_draft.copy());
      },
      onApply: () => Navigator.pop(context, _draft),
      sections: [
        // 다섯 항목 — **2열 균일 격자**(지역/성별 · 연령/참가비 · 파티 유형·
        // 분위기 + 빈 칸). 모든 카드의 폭·높이·안쪽 여백·모서리가 같다.
        //
        // 예전에는 3열이라 3+2로 갈렸고, 마지막 한 칸이 줄을 넓게 쓰는 규칙
        // 까지 겹쳐 카드 폭이 세 가지였다. 2열로 놓으면 칸 폭이 늘 1/2이고,
        // 마지막 줄의 빈 자리는 비워 두므로 '파티 유형·분위기'도 다른 카드와
        // 똑같은 한 칸이다([FilterGridLayout.uniform2]).
        //
        // 칸을 누르면 둘 중 하나가 일어난다. 지역·성별·연령·참가비는 예전처럼
        // 줄 아래에서 펼쳐지고, 파티 유형·분위기는 **바텀시트**가 열린다
        // ([_openTypeVibeSheet]) — 칸이 마흔이 넘어 그 자리에서 펼치면 검색
        // 버튼이 화면 밖으로 밀려났다.
        FilterGridSection(
          layout: FilterGridLayout.uniform2,
          items: [
            _gridItem(
              sectionKey: 'region',
              title: '지역',
              icon: Icons.place_rounded,
              iconColor: const Color(0xFFFF6FA0),
              summary: _regionSummaryLabel(),
              hasSelection: _draft.districts.isNotEmpty,
              child: _regionAccordionBody(),
            ),
            // ⚠️ '날짜/시간'과 '파티 규모' 칸은 여기 없다 — 목록 위 빠른필터
            //    줄(📅 날짜 · 🕐 시간 · 👥 인원)에서 이미 고르는 조건이라,
            //    같은 선택지를 두 곳에 두면 어느 쪽이 지금 값인지 알기 어렵다.
            //
            //    **조건 자체는 그대로 살아 있다** — 값은 같은
            //    [PartyFilter](selectedDates · timeOfDayStart/End · partyScale)
            //    에 있고 판정도 예전 그대로다. 빠른필터에서 고른 값은 이 시트를
            //    열어도 풀리지 않고, 위 선택 칩에 그대로 보이며 거기서 하나씩
            //    뺄 수 있다. '전체 초기화'도 예전처럼 그 값들까지 함께 푼다.
            _gridItem(
              sectionKey: 'gender',
              title: '성별',
              icon: Icons.wc_rounded,
              iconColor: const Color(0xFF4ECBA7),
              summary: _summaryOrAll(_draft.genderConditions),
              hasSelection: _draft.genderConditions.isNotEmpty,
              child: _multiChipWrap(_genderConditions, _draft.genderConditions),
            ),
            _gridItem(
              sectionKey: 'age',
              title: '연령',
              icon: Icons.cake_rounded,
              iconColor: const Color(0xFFB06CFF),
              summary: _summaryOrAll(_draft.ageGroups),
              hasSelection: _draft.ageGroups.isNotEmpty,
              child: _multiChipWrap(_ageGroups, _draft.ageGroups),
            ),
            _gridItem(
              sectionKey: 'fee',
              title: '참가비',
              icon: Icons.payments_rounded,
              iconColor: const Color(0xFFFFA552),
              summary: _summaryOrAll(_draft.feeRanges),
              hasSelection: _draft.feeRanges.isNotEmpty,
              child: _multiChipWrap(_feeRanges, _draft.feeRanges),
            ),
            // 파티 유형과 분위기는 **한 칸**이고, 시트를 열면 **한 목록**
            // 이다(소제목도 구분선도 없다). 둘 다 '어떤 파티인가'에 대한
            // 답이라 고르는 사람에게는 애초에 한 가지 질문이었다.
            // 저장값만 그대로 둘로 남는다([PartyFilter.partyTypes] /
            // [PartyFilter.vibes]) — 판정도 예전과 같다.
            _gridItem(
              sectionKey: 'partyTypes',
              title: '파티 유형·분위기',
              icon: Icons.celebration_rounded,
              iconColor: const Color(0xFFFF5C93),
              summary: _summaryOrAll([
                ..._draft.partyTypes.map(PartyConstants.labelFor),
                ..._draft.vibes.map(PartyConstants.vibeLabelFor),
              ], joiner: ' · '),
              hasSelection:
                  _draft.partyTypes.isNotEmpty || _draft.vibes.isNotEmpty,
              // 마흔 칸이 넘어 그 자리에서 펼치면 검색 버튼이 화면 밖으로
              // 밀린다 — 플레이스의 ♾ 무제한과 같은 시트로 받는다.
              onOpenSheet: _openTypeVibeSheet,
            ),
            // ⚠️ '태그' 칸은 없앴다 — 상단 검색창이 태그까지 함께 찾는다
            //    (main_screen의 `_matchesSearch`). 저장값과 판정은 그대로
            //    남아 있어([PartyFilter.tagKeywords]) 예전에 걸어 둔 태그
            //    조건은 계속 동작하고, 위 선택 칩에서 지울 수 있다.
          ],
        ),
        // 격자 → 토글 → 토글 → 검색 버튼 사이를 **모두 같은 간격**으로 둔다.
        const SizedBox(height: _kSectionGap),
        // ⚡ 얼리버드 — 예전엔 '기타 필터' 아코디언 안에 혼자 들어 있었다.
        // 한 칸짜리 서랍이라 열어 보기 전에는 있는 줄도 몰랐다. 판정·저장
        // 상태는 그대로 두고([PartyFilter.earlyBirdOnly]) 자리만 꺼냈다.
        FilterToggleCard(
          icon: const Icon(Icons.bolt_rounded, color: Color(0xFFFFA552)),
          title: '얼리버드 진행중만 보기',
          value: _draft.earlyBirdOnly,
          onChanged: (v) => setState(() => _draft.earlyBirdOnly = v),
        ),
        const SizedBox(height: _kSectionGap),
        // "모집중만 보기"를 대체 — 단순 모집 상태가 아니라 로그인한
        // 사용자의 성별/연령 조건과 정원까지 반영해 실제로 신청
        // 가능한 파티만 보여준다(checkPartyEligibility 재사용).
        FilterToggleCard(
          title: '내가 참여 가능한 파티만 보기',
          subtitle: '성별·연령 조건과 모집 마감 여부를 반영해 실제로 신청 가능한 파티만 보여줘요.',
          value: _draft.eligibleOnly,
          onChanged: (v) => setState(() => _draft.eligibleOnly = v),
        ),
      ],
    );
  }

  /// 3×3 그리드 칸 하나 — 아코디언 시절과 **같은 펼침 상태**([_expanded])를
  /// 쓴다. 배치만 다를 뿐 선택 UI·요약·토글 동작은 한 벌이다.
  FilterGridItem _gridItem({
    required String sectionKey,
    required String title,
    required IconData icon,
    required Color iconColor,
    required String summary,
    required bool hasSelection,
    Widget? child,
    VoidCallback? onOpenSheet,
  }) {
    // [onOpenSheet]를 준 칸은 그 자리에서 펼쳐지지 않고 바텀시트를 연다.
    final expanded = child != null && _expanded.contains(sectionKey);
    return FilterGridItem(
      title: title,
      icon: icon,
      iconColor: iconColor,
      summary: summary,
      hasSelection: hasSelection,
      expanded: expanded,
      onToggle:
          onOpenSheet ??
          () => setState(() {
            if (expanded) {
              _expanded.remove(sectionKey);
            } else {
              _expanded.add(sectionKey);
            }
          }),
      child: child,
    );
  }

  // 값이 없으면 "전체"로 표시하는 공통 요약 포맷터.
  String _summaryOrAll(Iterable<String> values, {String joiner = ', '}) =>
      filterSummaryOrAll(values, joiner: joiner);

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
              // '(전체)'만 골라 둔 지역도 "고른 게 있음"으로 보여야 한다 —
              // 낱개 구만 세면 서울 (전체)를 고른 뒤 다른 지역으로 넘어갔을 때
              // 서울 칩이 아무것도 안 고른 것처럼 보인다.
              final hasInCity =
                  _draft.districts.contains(RegionData.allDistrictOf(city)) ||
                  (RegionData.regionDistricts[city] ?? []).any(
                    _draft.districts.contains,
                  );
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterScaleTap(
                  onTap: () => setState(() => _regionActiveCity = city),
                  rippleRadius: BorderRadius.circular(16),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
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
                                color: PartyChuColors.primary.withValues(
                                  alpha: 0.3,
                                ),
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
          children: [
            // 맨 앞에 '(전체)' — 그 시/도의 시·구를 전부 포함해 검색한다.
            // 특정 지역만 다루지 않는다: RegionData에 있는 시/도면 무엇이든
            // 같은 규칙으로 이 칩이 생긴다(서울·경기·인천…).
            _allDistrictChip(),
            ...activeDistricts.map((d) {
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
                          // 낱개를 고르면 그 지역의 '(전체)'는 뜻이 없어진다 —
                          // 둘을 함께 두면 칩만 늘고 결과는 '(전체)'와 똑같다.
                          _draft.districts.remove(
                            RegionData.allDistrictOf(_regionActiveCity),
                          );
                        }
                      }),
              );
            }),
          ],
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

  /// 지금 보고 있는 시/도의 '(전체)' 칩.
  ///
  /// 값은 [RegionData.allDistrictOf]가 만드는 문자열 하나로, 다른 선택값과
  /// 똑같이 [PartyFilter.districts]에 담긴다 — 칩 삭제·개수 상한·검색 판정이
  /// 전부 기존 경로를 그대로 탄다(그 지역의 구를 25개 담는 방식이 아니다).
  Widget _allDistrictChip() {
    final value = RegionData.allDistrictOf(_regionActiveCity);
    final sel = _draft.districts.contains(value);
    // 이 지역에서 낱개로 골라 둔 시·구가 있으면 '(전체)'가 그것들을 **대체**하므로
    // 개수가 늘지 않는다 — 상한에 걸렸다는 이유로 막으면 "5개 골랐더니 전체를
    // 고를 수 없는" 막다른 길이 생긴다.
    final replaces = (RegionData.regionDistricts[_regionActiveCity] ?? const [])
        .any(_draft.districts.contains);
    final blocked =
        !sel &&
        !replaces &&
        _draft.districts.length >= PartyFilter.maxDistricts;
    return _chip(
      value,
      sel,
      dim: blocked,
      icon: Icons.select_all_rounded,
      onTap: blocked
          ? null
          : () => setState(() {
              if (sel) {
                _draft.districts.remove(value);
                return;
              }
              // 이 지역에서 낱개로 골라 둔 시·구는 '(전체)'가 덮으므로 정리한다.
              _draft.districts.removeAll(
                RegionData.regionDistricts[_regionActiveCity] ?? const [],
              );
              _draft.districts.add(value);
            }),
    );
  }

  // ── 날짜/시간 · 파티 규모 아코디언 ────────────────────────────────
  //
  // 이 아래 넷은 **지금 화면에 걸려 있지 않다** — 두 칸을 목록 위 빠른필터
  // 줄에 넘겼기 때문이다(위 격자 주석). 지우지 않고 그대로 두는 이유는
  // 출시 직전이라 되돌릴 일이 생기면 한 줄(격자에 칸을 다시 넣는 것)로
  // 끝나야 하기 때문이고, 값을 읽고 쓰는 자리가 아니라 그리기만 하는
  // 코드라 남아 있어도 아무 일도 하지 않는다.
  // ignore: unused_element
  bool get _dateHasSelection =>
      _draft.dateOptions.isNotEmpty ||
      _draft.selectedDates.isNotEmpty ||
      _draft.timeOfDayStart != null ||
      _draft.timeOfDayEnd != null;

  // ignore: unused_element
  String _dateSummaryLabel() {
    if (_draft.dateOptions.isNotEmpty) return _draft.dateOptions.join(', ');
    if (_draft.selectedDates.isNotEmpty) {
      var s = _draft.selectedDatesSorted.map(_fmtDate).join(', ');
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

  // ignore: unused_element
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
                    _draft.selectedDates.clear();
                    _draft.startTime = null;
                    _draft.endTime = null;
                    _showCalendar = false;
                  }
                }),
              );
            }),

            // 날짜 직접선택 버튼 — 여러 날을 고를 수 있으므로 개수를 함께 적는다.
            _chip(
              _draft.selectedDates.isEmpty
                  ? '날짜 선택'
                  : '${_fmtDate(_draft.selectedDatesSorted.first)}'
                        '${_draft.selectedDates.length > 1 ? ' 외 ${_draft.selectedDates.length - 1}일' : ''}',
              _showCalendar || _draft.selectedDates.isNotEmpty,
              icon: Icons.calendar_today_rounded,
              onTap: () => setState(() {
                _showCalendar = !_showCalendar;
                if (!_showCalendar) {
                  _draft.selectedDates.clear();
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
              // 여러 날을 고를 수 있다 — 이미 고른 날을 다시 누르면 해제된다.
              selectedDayPredicate: (day) =>
                  _draft.selectedDates.any((d) => isSameDay(day, d)),
              onDaySelected: (selected, focused) {
                setState(() => _focusedDay = focused);
                _toggleDate(selected);
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
                titleTextStyle: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
                leftChevronIcon: Icon(
                  Icons.chevron_left,
                  color: Color(0xFFFF6FA0),
                ),
                rightChevronIcon: Icon(
                  Icons.chevron_right,
                  color: Color(0xFFFF6FA0),
                ),
              ),
              onPageChanged: (focused) => setState(() => _focusedDay = focused),
              locale: 'ko_KR',
            ),
          ),

          // 고른 날짜 목록 — 달력은 한 달만 보이므로, 다른 달에 골라 둔 날짜도
          // 여기서 한눈에 보이고 바로 뺄 수 있어야 한다.
          if (_draft.selectedDates.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final d in _draft.selectedDatesSorted)
                  _chip(
                    _fmtDate(d),
                    true,
                    icon: Icons.close_rounded,
                    onTap: () => _toggleDate(d),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            _draft.selectedDates.length >= PartyFilter.maxSelectedDates
                ? '날짜는 최대 ${PartyFilter.maxSelectedDates}개까지 선택할 수 있어요.'
                : '날짜는 최대 ${PartyFilter.maxSelectedDates}개까지 고를 수 있고, '
                      '고른 날짜 중 하루라도 열리는 파티를 모두 보여줘요. '
                      '날짜를 고르면 아래에서 시간대까지 좁힐 수 있어요.',
            style: const TextStyle(fontSize: 11, color: PartyChuColors.muted),
          ),

          // 시간 범위 선택 (날짜를 하나라도 고른 뒤에만 표시)
          if (_draft.selectedDates.isNotEmpty) ...[
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
                  const Icon(
                    Icons.access_time_outlined,
                    size: 16,
                    color: PartyChuColors.primary,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    // 고른 날짜에만 걸리는 시간이라 '고른 날짜의'를 붙인다 —
                    // 아래 '파티 시작 시간'(날짜와 무관)과 헷갈리지 않게.
                    '고른 날짜의 시간대',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: PartyChuColors.heading,
                    ),
                  ),
                  const Spacer(),
                  // 시작 시간
                  FilterScaleTap(
                    onTap: () => _pickTime(true),
                    rippleRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
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
                    child: Text(
                      '~',
                      style: TextStyle(fontSize: 14, color: Colors.black45),
                    ),
                  ),
                  // 종료 시간
                  FilterScaleTap(
                    onTap: () => _pickTime(false),
                    rippleRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
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
                    FilterScaleTap(
                      onTap: () => setState(() {
                        _draft.startTime = null;
                        _draft.endTime = null;
                      }),
                      rippleRadius: BorderRadius.circular(12),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: Colors.black38,
                        ),
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

        // ── 파티 시간(지정 시간 / 지정 구간 — PartyTimeFilter가 판정한다) ──
        Row(
          children: [
            const Icon(
              Icons.schedule_rounded,
              size: 15,
              color: PartyChuColors.primary,
            ),
            const SizedBox(width: 6),
            const Text(
              '파티 시간',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: PartyChuColors.heading,
              ),
            ),
            const Spacer(),
            if (_draft.timeOfDayStart == null && _draft.timeOfDayEnd == null)
              const Text(
                '전체 시간',
                style: TextStyle(fontSize: 11, color: PartyChuColors.muted),
              ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          '시작만 고르면 그 시각에 진행 중인 파티를, 시작·끝을 모두 고르면 그 '
          '시간대와 겹치는 파티를 찾아요.',
          style: TextStyle(fontSize: 11, color: PartyChuColors.muted),
        ),
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
                child: FilterScaleTap(
                  onTap: () => _pickTimeOfDay(true),
                  rippleRadius: BorderRadius.circular(10),
                  child: _timeSelectorBox(_draft.timeOfDayStart, '시작'),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '~',
                  style: TextStyle(fontSize: 14, color: Colors.black45),
                ),
              ),
              Expanded(
                child: FilterScaleTap(
                  onTap: () => _pickTimeOfDay(false),
                  rippleRadius: BorderRadius.circular(10),
                  child: _timeSelectorBox(_draft.timeOfDayEnd, '끝'),
                ),
              ),
              if (_draft.timeOfDayStart != null ||
                  _draft.timeOfDayEnd != null) ...[
                const SizedBox(width: 6),
                FilterScaleTap(
                  onTap: () => setState(() {
                    _draft.timeOfDayStart = null;
                    _draft.timeOfDayEnd = null;
                  }),
                  rippleRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: Colors.black38,
                    ),
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
      color: value != null
          ? PartyChuColors.primary
          : PartyChuColors.surfaceTint,
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
        Icon(
          Icons.keyboard_arrow_down_rounded,
          size: 18,
          color: value != null ? Colors.white : PartyChuColors.primary,
        ),
      ],
    ),
  );

  // ⚠️ 태그 입력 UI는 없앴다 — 상단 검색창이 태그까지 함께 찾는다
  //    (main_screen의 `_matchesSearch`). 조건 자체는
  //    [PartyFilter.tagKeywords]에 그대로 남아 있어, 예전에 걸어 둔 태그는
  //    계속 걸러 주고 위 선택 칩에서 하나씩 뺄 수 있다.

  // ── 파티 규모 아코디언 ────────────────────────────────────────────
  //
  // 하나만 고른다(구간끼리 겹치지 않으므로 '2~5명이면서 11~20명'인 파티는
  // 없다). 이미 고른 구간을 다시 누르면 해제된다.
  // ignore: unused_element
  Widget _partyScaleAccordionBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: PartyScaleFilter.options.map((r) {
            final sel = _draft.partyScale == r.id;
            return _chip(
              r.label,
              sel,
              onTap: () =>
                  setState(() => _draft.partyScale = sel ? null : r.id),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        const Text(
          '파티의 최대 모집 인원을 기준으로 찾아요.',
          style: TextStyle(fontSize: 11.5, color: PartyChuColors.muted),
        ),
      ],
    );
  }

  // ── 선택형 필터 바텀시트 ──────────────────────────────────────────
  //
  // 플레이스의 '♾ 무제한' 시트와 **같은 그릇**을 쓴다
  // ([showFilterOptionSheet]). 공용인 것은 UI뿐이고, 켜고 끄는 값은 여기서
  // [PartyFilter]의 집합을 직접 고친다 — 아코디언이 쓰던
  // [FilterChipWrap]과 완전히 같은 방식이라 판정도 저장값도 그대로다.
  /// 🎉 파티 유형 · 분위기 — **하나의 목록**이다.
  ///
  /// 소제목도 구분선도 없이 칩이 같은 레벨로 쭉 이어진다. 고르는 사람에게
  /// '하우스'와 '술 중심'은 둘 다 "어떤 파티인가"에 대한 답 하나일 뿐이라,
  /// 어느 쪽이 유형이고 어느 쪽이 분위기인지 먼저 알아야 할 이유가 없다.
  ///
  /// 저장·판정은 그대로 둘로 남는다 — 칩을 누르면 그 값이 원래 살던 칸
  /// ([PartyFilter.partyTypes] 또는 [PartyFilter.vibes])에 그대로 들어간다.
  /// 화면에서만 합쳤을 뿐이라 예전에 걸어 둔 조건도, 이미 저장된 파티의
  /// 값도 하나도 건드리지 않는다.
  void _openTypeVibeSheet() {
    showFilterOptionSheet(
      context: context,
      night: false,
      title: '🎉 파티 유형 · 분위기',
      // 한도는 등록 화면과 **같은 하나**다([PartyConstants.maxTypeVibes]).
      // 다 채우면 안내가 그 자리에서 바뀐다 — 시트 위로는 스낵바가 뜨지
      // 않아서, 칩이 안 켜지는 이유를 여기서 말해 주어야 한다.
      hint: () {
        final picked = _draft.partyTypes.length + _draft.vibes.length;
        return PartyConstants.canPickTypeVibe(picked)
            ? '여러 개 고르면 그중 하나라도 해당하는 파티를 찾아요. '
                  '(최대 ${PartyConstants.maxTypeVibes}개 · $picked개 선택)'
            : PartyConstants.typeVibeLimitMessage;
      },
      hasSelection: () =>
          _draft.partyTypes.isNotEmpty || _draft.vibes.isNotEmpty,
      // 초기화는 이 시트가 다루는 둘 다 푼다 — 하나만 남으면 '초기화했는데
      // 조건이 남아 있는' 상태가 된다.
      onReset: () => setState(() {
        _draft.partyTypes.clear();
        _draft.vibes.clear();
      }),
      onChanged: () => setState(() {}),
      // 그룹은 하나뿐이고 이름도 없다 — 소제목 없이 칩만 이어진다.
      groups: () => [
        FilterSheetGroup(
          // 목록·라벨·순서의 정본은 등록 화면과 **같은 하나**다
          // ([PartyConstants.typeVibeOptionsFor]) — 등록할 때 고른 항목이
          // 여기서 같은 얼굴로 다시 나와야 검색이 이어진다.
          options: [
            for (final o in PartyConstants.typeVibeOptionsFor(
              selectedTypes: _draft.partyTypes,
              selectedVibes: _draft.vibes,
            ))
              FilterSheetOption(
                label: o.label,
                // 이미지로 표기하는 항목('돌싱')만 아이콘이 붙는다 — 등록
                // 화면의 선택 시트와 **같은 위젯**을 쓰므로 두 화면에서
                // 같은 얼굴로 나온다.
                leading: partyTypeVibeIconFor(o.value, size: 13.5),
                // 어느 칸에 저장되는지만 갈릴 뿐, 고르는 사람에게는 같은
                // 목록의 같은 칩이다.
                selected: (o.isVibe ? _draft.vibes : _draft.partyTypes)
                    .contains(o.value),
                onToggle: () {
                  final target = o.isVibe ? _draft.vibes : _draft.partyTypes;
                  if (target.remove(o.value)) return;
                  // 유형·분위기를 가리지 않는 합계 한도 — 등록 화면과 같다.
                  if (!PartyConstants.canPickTypeVibe(
                    _draft.partyTypes.length + _draft.vibes.length,
                  )) {
                    return;
                  }
                  target.add(o.value);
                },
              ),
          ],
        ),
      ],
    );
  }

  // ── 선택된 조건 칩 행 ─────────────────────────────────────────────
  Widget _selectedChipsRow() {
    return FilterSelectedChips(
      entries: _draft.selectedEntries,
      labelBuilder: (e) => switch (e.key) {
        // 저장값과 보이는 글자가 다른 둘만 표기를 거친다.
        'partyTypes' => PartyConstants.labelFor(e.value),
        'vibes' => PartyConstants.vibeLabelFor(e.value),
        _ => e.value,
      },
      titleFontWhen: (e) => e.key == 'partyTypes',
      avatarBuilder: (e) => switch (e.key) {
        'districts' => const Icon(
          Icons.place_rounded,
          size: 15,
          color: PartyChuColors.primary,
        ),
        // 골라 둔 조건 칩에서도 같은 아이콘이 앞에 선다 — 시트에서 고를 때와
        // 고른 뒤가 다른 얼굴이면 무엇을 켰는지 되짚기 어렵다.
        'partyTypes' => partyTypeVibeIconFor(e.value, size: 14),
        _ => null,
      },
      onDelete: (e) => setState(() {
        _draft.removeValue(e.key, e.value);
        // 마지막 날짜까지 뺐으면 달력도 접는다.
        if (e.key == 'selectedDates' && _draft.selectedDates.isEmpty) {
          _showCalendar = false;
        }
      }),
    );
  }

  // 칩·칩 묶음도 공용 부품([FilterOptionChip]/[FilterChipWrap])을 그대로 쓴다 —
  // 여기 있는 건 기존 호출부를 그대로 두기 위한 얇은 껍데기다.
  Widget _chip(
    String label,
    bool isSelected, {
    bool dim = false,
    IconData? icon,
    VoidCallback? onTap,
    bool titleFont = false,
  }) {
    return FilterOptionChip(
      label: label,
      selected: isSelected,
      dim: dim,
      icon: icon,
      onTap: onTap,
      titleFont: titleFont,
    );
  }

  Widget _multiChipWrap(
    List<String> options,
    Set<String> selected, {
    String Function(String)? labelBuilder,
    bool titleFont = false,
  }) {
    return FilterChipWrap(
      options: options,
      selected: selected,
      onChanged: () => setState(() {}),
      labelBuilder: labelBuilder,
      titleFont: titleFont,
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
        : slots.indexWhere(
            (t) =>
                t.hour == widget.selected!.hour &&
                t.minute == widget.selected!.minute,
          );
    final initialOffset = selectedIndex > 0
        ? (selectedIndex - 2).clamp(0, slots.length) * 48.0
        : 0.0;
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
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: PartyChuColors.heading,
              ),
            ),
            const Divider(height: 24, color: PartyChuColors.border),
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                itemCount: slots.length,
                itemBuilder: (ctx, i) {
                  final t = slots[i];
                  final isSelected =
                      widget.selected != null &&
                      widget.selected!.hour == t.hour &&
                      widget.selected!.minute == t.minute;
                  return FilterScaleTap(
                    onTap: () => Navigator.pop(context, t),
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 2,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? PartyChuColors.surfaceTint
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Text(
                            PartyFilter.formatAmPm(t),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: isSelected
                                  ? PartyChuColors.primaryDeep
                                  : PartyChuColors.heading,
                            ),
                          ),
                          const Spacer(),
                          if (isSelected)
                            const Icon(
                              Icons.check_circle_rounded,
                              color: PartyChuColors.primary,
                              size: 20,
                            ),
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

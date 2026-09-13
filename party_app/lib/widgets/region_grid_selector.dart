import 'package:flutter/material.dart';

import 'package:party_app/models/region_data.dart';
import 'package:party_app/models/region_selection.dart';
import 'package:party_app/widgets/partychu_ui.dart';

/// 전국 시/도 → 구·시·군 **2단계 그리드**로 지역을 고르는 공용 선택기.
///
/// 시/도를 세로로 늘어놓고 누른 곳만 아래로 펼치는 아코디언은, 한 지역이
/// 한 줄씩 차지해 전국을 보려면 한참 스크롤해야 했고 펼칠 때마다 화면 높이가
/// 널뛰었다. 그래서 **같은 영역을 화면 전환처럼 갈아끼우는** 방식으로 바꿨다.
///
///     [1단계] 전국 4열 그리드          [2단계] ← 서울
///      서울  경기  인천  부산            서울 전체  강남구  강동구
///      대구  광주  대전  울산            강북구     강서구  관악구
///      …                                 …
///
/// '○○ 전체'는 **구·시·군 그리드의 첫 칸**이다. 예전에는 머리줄 오른쪽 끝에
/// 따로 떠 있었는데, 고를 수 있는 선택지인데도 뒤로가기 줄에 얹혀 있어
/// 제목의 일부처럼 읽혔다. 이제 나머지 구·시·군과 같은 모양·같은 자리에
/// 놓여 '가장 넓은 선택지'로 먼저 눈에 들어온다(고르는 규칙은 그대로다).
///
/// 시/도를 누르면 그 자리가 그 시/도의 구·시·군 그리드로 바뀌고, ←를 누르면
/// 다시 전국 그리드로 돌아온다. 어느 단계에서도 높이가 갑자기 늘어나지 않는다.
///
/// 지역 목록은 [RegionData], 선택값 규격·토글 규칙·한도는 [RegionSelection]을
/// 그대로 쓴다 — 이 위젯은 화면만 담당한다. 플레이스 상세검색·장소대여
/// 상세검색·장소대여 상단 지역 시트가 이 위젯 하나를 공유한다.
class RegionGridSelector extends StatefulWidget {
  /// 선택된 지역 키들(`'서울'` / `'서울 강남구'`). 이 Set을 직접 고쳐서
  /// 돌려주므로, 호출부는 필터가 들고 있는 Set을 그대로 넘기면 된다.
  final Set<String> selected;

  /// 한 번에 고를 수 있는 지역 수.
  final int maxCount;

  /// 선택이 바뀔 때마다 호출 — 호출부에서 setState만 해주면 된다.
  final ValueChanged<Set<String>>? onChanged;

  /// 목록 위에 붙는 제목. 주면 '지역 3/5'처럼 선택 개수를 함께 보여준다.
  /// null이면 제목 줄 없이 그리드만 그린다.
  final String? title;

  const RegionGridSelector({
    super.key,
    required this.selected,
    this.maxCount = RegionSelection.maxCount,
    this.onChanged,
    this.title,
  });

  @override
  State<RegionGridSelector> createState() => _RegionGridSelectorState();
}

class _RegionGridSelectorState extends State<RegionGridSelector> {
  /// 지금 들어가 있는 시/도. null이면 1단계(전국 그리드).
  String? _city;

  void _toggleSelection(String key) {
    if (!RegionSelection.toggle(widget.selected, key, max: widget.maxCount)) {
      return; // 한도 초과 — 안내 문구는 그리드 아래에 항상 떠 있다.
    }
    setState(() {});
    widget.onChanged?.call(widget.selected);
  }

  @override
  Widget build(BuildContext context) {
    final maxed = widget.selected.length >= widget.maxCount;
    final city = _city;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.title != null) ...[
          Row(
            children: [
              Text(
                widget.title!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              // 어느 단계에 있든 몇 개를 골랐는지 항상 제목 옆에 붙인다.
              Text(
                '${widget.selected.length}/${widget.maxCount}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: widget.selected.isEmpty
                      ? Colors.black38
                      : PartyChuColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        // 같은 자리를 갈아끼운다 — 아래로 펼치지 않으므로 높이가 튀지 않는다.
        if (city == null) _cityGrid() else _districtView(city),
        if (maxed) ...[
          const SizedBox(height: 8),
          Text(
            RegionSelection.maxReachedMessage,
            style: const TextStyle(fontSize: 11.5, color: Colors.black45),
          ),
        ],
      ],
    );
  }

  // ── 1단계: 전국 시/도 4열 그리드 ──────────────────────────────────
  Widget _cityGrid() {
    final cities = RegionData.regions;
    return GridView.count(
      crossAxisCount: 4,
      childAspectRatio: 2.1,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      // 바깥(시트·상세검색)이 이미 스크롤을 맡고 있어 그리드는 제 높이만 쓴다.
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        for (final city in cities)
          _cityCell(city, RegionSelection.countInCity(widget.selected, city)),
      ],
    );
  }

  /// 시/도 칸 — 누르면 그 시/도의 구·시·군 그리드로 들어간다.
  /// '서울 전체'로 통째 고른 상태면 칸 자체가 핑크로 차고, 개별 구만 골랐으면
  /// 옅은 핑크 + 개수 배지로 "안에 몇 개 골라뒀다"를 알려준다.
  Widget _cityCell(String city, int picked) {
    final whole = widget.selected.contains(RegionSelection.cityKey(city));
    return _Cell(
      label: city,
      state: whole
          ? _CellState.selected
          : picked > 0
          ? _CellState.partial
          : _CellState.plain,
      badge: !whole && picked > 0 ? '$picked' : null,
      trailing: Icons.chevron_right_rounded,
      onTap: () => setState(() => _city = city),
    );
  }

  // ── 2단계: 고른 시/도의 구·시·군 그리드 ────────────────────────────
  Widget _districtView(String city) {
    final districts = RegionData.regionDistricts[city] ?? const [];
    final wholeKey = RegionSelection.cityKey(city);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 머리줄 — ← 로 전국 그리드로 돌아가는 일만 한다. 여기에 선택지를
        // 얹지 않는다('${city} 전체'는 아래 그리드의 첫 칸이다).
        Row(
          children: [
            InkWell(
              onTap: () => setState(() => _city = null),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.arrow_back_rounded, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      city,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // 구·시·군은 수가 많다(경기 31개) — 칸을 낮고 촘촘하게 깔아 한 화면에
        // 최대한 많이 들어오게 한다. 열 수(3)와 글자 크기는 그대로 두고 높이와
        // 간격만 줄인다.
        GridView.count(
          crossAxisCount: 3,
          childAspectRatio: 4.1,
          mainAxisSpacing: 5,
          crossAxisSpacing: 6,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            // 첫 칸(왼쪽 위)은 언제나 '${city} 전체' — 그 시/도의 모든 구를
            // 뜻한다. 개별 구 선택과 겹치지 않게 정리하는 일도, 최대 선택
            // 개수 판정도 전부 [RegionSelection]이 예전 그대로 맡는다
            // (여기서 바뀐 것은 이 칸이 놓이는 **자리**뿐이다).
            _districtCell(wholeKey, '$city 전체'),
            for (final d in districts)
              _districtCell(RegionSelection.districtKey(city, d), d),
          ],
        ),
      ],
    );
  }

  Widget _districtCell(String key, String label) {
    final state = _stateOf(key);
    return _Cell(
      label: label,
      state: state,
      dense: true,
      onTap: state == _CellState.blocked ? null : () => _toggleSelection(key),
    );
  }

  /// 고른 상태 / 한도에 걸려 못 고르는 상태 / 그냥 상태.
  _CellState _stateOf(String key) {
    if (widget.selected.contains(key)) return _CellState.selected;
    return RegionSelection.canSelect(widget.selected, key, max: widget.maxCount)
        ? _CellState.plain
        : _CellState.blocked;
  }
}

enum _CellState {
  /// 고른 것 — 파티츄 핑크 + 흰 글씨.
  selected,

  /// 안에 고른 것이 있는 시/도 — 옅은 핑크.
  partial,

  /// 아직 안 고른 것 — 흰색/연한 회색.
  plain,

  /// 한도에 걸려 지금은 못 고르는 것.
  blocked,
}

/// 그리드 한 칸 — 시/도·구·시·군·'전체' 버튼이 모두 이 모양을 쓴다.
class _Cell extends StatelessWidget {
  final String label;
  final _CellState state;
  final VoidCallback? onTap;

  /// 오른쪽 끝에 붙는 작은 아이콘(시/도 칸의 '>').
  final IconData? trailing;

  /// 칸 안에 고른 개수를 알리는 작은 숫자.
  final String? badge;

  /// 촘촘하게 까는 칸(구·시·군)인지 — 글자 크기는 그대로 두고 안쪽 여백과
  /// 모서리만 줄인다. 높이는 그리드의 childAspectRatio가 정한다.
  final bool dense;

  const _Cell({
    required this.label,
    required this.state,
    this.onTap,
    this.trailing,
    this.badge,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final (bg, border, fg) = switch (state) {
      _CellState.selected => (
        PartyChuColors.primary,
        PartyChuColors.primary,
        Colors.white,
      ),
      _CellState.partial => (
        const Color(0xFFFFF0F5),
        const Color(0xFFFFD6E4),
        PartyChuColors.primary,
      ),
      _CellState.plain => (
        const Color(0xFFF7F7FA),
        const Color(0xFFEDEDF2),
        const Color(0xFF3A3A3A),
      ),
      _CellState.blocked => (
        const Color(0xFFF5F5F7),
        const Color(0xFFEEEEF2),
        Colors.black26,
      ),
    };

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        padding: EdgeInsets.symmetric(horizontal: dense ? 4 : 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(dense ? 8 : 12),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  // 낮아진 칸에서도 글자가 잘리지 않게 줄 높이만 붙인다
                  // (글자 크기는 그대로 둔다).
                  height: dense ? 1.1 : null,
                  fontWeight: state == _CellState.selected
                      ? FontWeight.w700
                      : FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 4),
              Container(
                width: 15,
                height: 15,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: PartyChuColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    fontSize: 9,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
            if (trailing != null)
              Icon(
                trailing,
                size: 14,
                color: state == _CellState.selected
                    ? Colors.white70
                    : Colors.black26,
              ),
          ],
        ),
      ),
    );
  }
}

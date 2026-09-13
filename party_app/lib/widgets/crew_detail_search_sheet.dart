import 'package:flutter/material.dart';
import 'package:party_app/models/crew_filter.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/widgets/filter_sheet_ui.dart'
    show filterSheetBottomInset;
import 'package:party_app/widgets/main/search_entry_sheet.dart';

/// 파티크루(파트너) 탭 전용 상세검색 바텀시트.
/// 파티 탭의 DetailSearchSheet와 완전히 분리된 화면 — 구인/구직 서비스에 맞는 검색 항목만 사용.
class CrewDetailSearchSheet extends StatefulWidget {
  final CrewFilter initialFilter;

  /// 목록 헤더의 돋보기로 열렸을 때만 채워진다 — 그러면 이 시트가 곧 검색
  /// 시트가 되어 조건들 위에 검색어 입력창([SearchEntryField])이 함께 붙는다
  /// (다른 탭과 같은 규칙: 상세검색을 따로 한 번 더 띄우지 않는다).
  final SearchEntryConfig? search;

  /// "전체 초기화"로 조건이 풀렸을 때, 시트를 닫지 않고도 목록에 바로
  /// 반영하라고 호출부에 건네는 길 — 검색어가 즉시 풀리는 것과 짝을 맞춘다
  /// (다른 탭의 상세검색 시트와 같은 규칙).
  final ValueChanged<CrewFilter>? onFilterReset;

  const CrewDetailSearchSheet({
    super.key,
    required this.initialFilter,
    this.search,
    this.onFilterReset,
  });

  @override
  State<CrewDetailSearchSheet> createState() => _CrewDetailSearchSheetState();
}

class _CrewDetailSearchSheetState extends State<CrewDetailSearchSheet> {
  late CrewFilter _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialFilter.copy();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  widget.search?.title ?? '파트너 상세검색',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton(
                  // 검색 시트로 열렸으면 검색어까지 함께 푼다 — 다른 탭의
                  // 전체 초기화([FilterSheetShell])와 같은 규칙이다.
                  onPressed: () {
                    widget.search?.clearQuery();
                    setState(() => _draft = CrewFilter());
                    // 사본을 넘긴다 — 이어서 고르는 값이 "검색" 전에 목록으로
                    // 새면 안 된다.
                    widget.onFilterReset?.call(_draft.copy());
                  },
                  child: const Text('전체 초기화'),
                ),
              ],
            ),
            // 돋보기로 열었으면 조건들 바로 위에 검색어 입력창이 붙는다.
            if (widget.search != null) ...[
              const SizedBox(height: 12),
              SearchEntryField(config: widget.search!),
            ],
            _selectedChipsRow(),
            const Divider(),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  _multiChipGroup(
                    '활동 지역',
                    ListingConstants.regions,
                    _draft.regions,
                  ),
                  _multiChipGroup(
                    '모집 역할',
                    ListingConstants.crewRoles,
                    _draft.roles,
                  ),
                  _multiChipGroup(
                    '보수',
                    ListingConstants.crewPayTypes,
                    _draft.payTypes,
                  ),
                  _multiChipGroup(
                    '모집 인원',
                    ListingConstants.crewRecruitCounts,
                    _draft.recruitCounts,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '모집 조건',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  _switchRow(
                    '초보 가능',
                    _draft.beginnerFriendly,
                    (v) => setState(() => _draft.beginnerFriendly = v),
                  ),
                  _switchRow(
                    '경력 우대',
                    _draft.experiencedPreferred,
                    (v) => setState(() => _draft.experiencedPreferred = v),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, _draft),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6FA0),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  widget.search == null ? '적용하기' : '검색',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            SizedBox(height: 16 + filterSheetBottomInset(context)),
          ],
        ),
      ),
    );
  }

  Widget _selectedChipsRow() {
    final entries = _draft.selectedEntries;
    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '선택된 조건이 없습니다',
            style: TextStyle(fontSize: 12, color: Colors.black38),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: entries
            .map(
              (e) => Chip(
                label: Text(e.value, style: const TextStyle(fontSize: 12)),
                deleteIcon: const Icon(Icons.close, size: 14),
                onDeleted: () =>
                    setState(() => _draft.removeValue(e.key, e.value)),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _chip(String label, bool isSelected) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: isSelected ? const Color(0xFFFF6FA0) : const Color(0xFFFFF4F8),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 13,
        color: isSelected ? Colors.white : Colors.black87,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
    ),
  );

  Widget _multiChipGroup(
    String title,
    List<String> options,
    Set<String> selected,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((opt) {
              final isSelected = selected.contains(opt);
              return GestureDetector(
                onTap: () => setState(() {
                  if (isSelected) {
                    selected.remove(opt);
                  } else {
                    selected.add(opt);
                  }
                }),
                child: _chip(opt, isSelected),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) =>
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        value: value,
        activeThumbColor: const Color(0xFFFF6FA0),
        onChanged: onChanged,
      );
}

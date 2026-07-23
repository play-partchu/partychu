import 'package:flutter/material.dart';
import 'package:party_app/models/crew_filter.dart';
import 'package:party_app/models/listing_constants.dart';

/// 파티크루(파트너) 탭 전용 상세검색 바텀시트.
/// 파티 탭의 DetailSearchSheet와 완전히 분리된 화면 — 구인/구직 서비스에 맞는 검색 항목만 사용.
class CrewDetailSearchSheet extends StatefulWidget {
  final CrewFilter initialFilter;

  const CrewDetailSearchSheet({super.key, required this.initialFilter});

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
                const Text('파트너 상세검색',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _draft = CrewFilter()),
                  child: const Text('전체 초기화'),
                ),
              ],
            ),
            _selectedChipsRow(),
            const Divider(),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                children: [
                  _multiChipGroup('활동 지역', ListingConstants.regions, _draft.regions),
                  _multiChipGroup('모집 역할', ListingConstants.crewRoles, _draft.roles),
                  _multiChipGroup('보수', ListingConstants.crewPayTypes, _draft.payTypes),
                  _multiChipGroup('모집 인원', ListingConstants.crewRecruitCounts, _draft.recruitCounts),
                  const SizedBox(height: 6),
                  Text('모집 조건', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  _switchRow('초보 가능', _draft.beginnerFriendly,
                      (v) => setState(() => _draft.beginnerFriendly = v)),
                  _switchRow('경력 우대', _draft.experiencedPreferred,
                      (v) => setState(() => _draft.experiencedPreferred = v)),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('적용하기',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            SizedBox(height: 16 + MediaQuery.of(context).padding.bottom),
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
          child: Text('선택된 조건이 없습니다',
              style: TextStyle(fontSize: 12, color: Colors.black38)),
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
                  label: Text(e.value, style: const TextStyle(fontSize: 12)),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  onDeleted: () => setState(() => _draft.removeValue(e.key, e.value)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ))
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

  Widget _multiChipGroup(String title, List<String> options, Set<String> selected) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((opt) {
              final isSelected = selected.contains(opt);
              return GestureDetector(
                onTap: () => setState(() {
                  if (isSelected) { selected.remove(opt); } else { selected.add(opt); }
                }),
                child: _chip(opt, isSelected),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        value: value,
        activeThumbColor: const Color(0xFFFF6FA0),
        onChanged: onChanged,
      );
}

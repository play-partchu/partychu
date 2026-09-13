import 'package:flutter/material.dart';
import 'package:party_app/models/place_facility_options.dart';

/// 상세페이지에서 선택된 좌석·공간/편의 옵션을 아이콘과 함께 보여준다.
/// 등록 화면의 접히는 섹션([PlaceFacilityOptionsSection])과 같은 카탈로그를
/// 읽으므로, 카탈로그에 항목을 추가하면 여기에도 자동으로 나타난다.
///
/// 선택된 항목이 하나도 없으면 [SizedBox.shrink]를 돌려주므로, 호출부에서
/// 별도로 빈 값을 확인하지 않아도 된다.
class PlaceFacilityOptionsView extends StatelessWidget {
  final PlaceFacilityOptions options;

  /// 보여줄 그룹(기본: 좌석·공간 섹션).
  final List<PlaceFacilityGroup> groups;

  final Color accent;

  const PlaceFacilityOptionsView({
    super.key,
    required this.options,
    this.groups = PlaceFacilityCatalog.seatingSection,
    this.accent = const Color(0xFF7C5CBF),
  });

  @override
  Widget build(BuildContext context) {
    final visible = groups
        .where((g) => options.selected(g.key).isNotEmpty)
        .toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final group in visible) ...[
          Text(
            group.title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // 카탈로그 순서대로 그린다 — 저장 순서와 무관하게 항상 같은 배열.
              for (final option in group.options)
                if (options.isSelected(group.key, option.label))
                  _tile(
                    option,
                    group.supportsCapacity
                        ? options.capacityOf(group.key, option.label)
                        : null,
                  ),
              // 카탈로그에서 사라진(예전 버전에서 저장된) 항목도 빠뜨리지 않는다.
              for (final label in options.selected(group.key))
                if (group.optionOf(label) == null)
                  _tile(PlaceFacilityOption(label, '•'), null),
            ],
          ),
          if (group != visible.last) const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _tile(PlaceFacilityOption option, int? capacity) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(option.emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(
            option.label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          if (capacity != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '최대 $capacity명',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

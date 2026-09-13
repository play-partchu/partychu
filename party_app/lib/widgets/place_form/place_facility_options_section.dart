import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:party_app/models/place_facility_options.dart';

const _kAccent = Color(0xFFFF6FA0);
const _kBoxFill = Color(0xFFF7F7FA);
const _kBorder = Color(0xFFE8EBF2);

/// 등록/수정 화면의 접히는 선택 섹션 — 좌석·공간뿐 아니라 앞으로 추가될
/// 흡연실·주차·와이파이 같은 편의시설도 [groups]만 바꿔 그대로 재사용한다.
///
/// 기본은 접힌 상태이고, 접혀 있을 때는 선택한 항목 요약만 한 줄로 보여준다.
///
/// ```
/// 🪑 좌석·공간
/// 카운터석 · 단체석 · 1인 방문 가능
/// ▼ 자세히 설정
/// ```
class PlaceFacilityOptionsSection extends StatefulWidget {
  final String emoji;
  final String title;

  /// 선택한 항목이 하나도 없을 때 요약 자리에 보여줄 안내 문구.
  final String emptyHint;

  /// 펼쳤을 때 보여줄 선택지 묶음(순서대로 그려진다).
  final List<PlaceFacilityGroup> groups;

  final PlaceFacilityOptions value;
  final ValueChanged<PlaceFacilityOptions> onChanged;

  /// 인원 입력 그룹 아래에 덧붙일 안내(예: 전체 최대 수용 인원과의 관계).
  final String? capacityNote;

  final bool initiallyExpanded;

  const PlaceFacilityOptionsSection({
    super.key,
    required this.title,
    required this.groups,
    required this.value,
    required this.onChanged,
    this.emoji = '🪑',
    this.emptyHint = '정보를 설정해주세요.',
    this.capacityNote,
    this.initiallyExpanded = false,
  });

  @override
  State<PlaceFacilityOptionsSection> createState() =>
      _PlaceFacilityOptionsSectionState();
}

class _PlaceFacilityOptionsSectionState
    extends State<PlaceFacilityOptionsSection> {
  late bool _expanded = widget.initiallyExpanded;

  /// 인원 입력칸 컨트롤러 — '그룹키/라벨'을 키로 재사용한다. 선택을 껐다
  /// 켜도 직전에 입력한 값이 남아 있도록 dispose 전까지 보관한다.
  final Map<String, TextEditingController> _capacityCtrls = {};

  @override
  void dispose() {
    for (final c in _capacityCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _capacityCtrl(PlaceFacilityGroup group, String label) {
    final key = '${group.key}/$label';
    final existing = _capacityCtrls[key];
    final stored = widget.value.capacityOf(group.key, label);
    if (existing != null) {
      // 외부에서 값이 바뀐 경우(임시저장 복원 등)에만 텍스트를 맞춘다 —
      // 사용자가 타이핑하는 중에는 건드리지 않는다.
      final storedText = stored?.toString() ?? '';
      if (stored != int.tryParse(existing.text.trim())) {
        existing.text = storedText;
      }
      return existing;
    }
    final created = TextEditingController(text: stored?.toString() ?? '');
    _capacityCtrls[key] = created;
    return created;
  }

  void _toggle(PlaceFacilityGroup group, String label) {
    widget.onChanged(widget.value.toggle(group.key, label));
  }

  void _setCapacity(PlaceFacilityGroup group, String label, String text) {
    widget.onChanged(
      widget.value.withCapacity(group.key, label, int.tryParse(text.trim())),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.value.summaryText();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 접힌 상태에서도 항상 보이는 머리말 ──────────────────────
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.emoji} ${widget.title}',
                    style: const TextStyle(
                      fontFamily: 'SeoulHangang',
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      shadows: [
                        Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
                        Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
                        Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
                        Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    summary.isEmpty ? widget.emptyHint : summary,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: summary.isEmpty ? Colors.black38 : Colors.black87,
                      fontWeight: summary.isEmpty
                          ? FontWeight.normal
                          : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: _kAccent,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        _expanded ? '접기' : '자세히 설정',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: _kAccent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (!_expanded && widget.value.selectedCount > 3) ...[
                        const SizedBox(width: 6),
                        Text(
                          '외 ${widget.value.selectedCount - 3}개',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black38,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          // ── 펼쳤을 때만 그리는 상세 설정 ────────────────────────────
          // 접혀 있을 때는 아예 만들지 않는다(칩/입력칸을 미리 만들어두면
          // 등록 화면 전체가 무거워지고, 화면에 없는 입력칸이 검색·탐색
          // 대상으로 잡히는 문제도 생긴다).
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final group in widget.groups) _groupBlock(group),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _groupBlock(PlaceFacilityGroup group) {
    final selected = group.options
        .map((o) => o.label)
        .where((label) => widget.value.isSelected(group.key, label))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1, color: _kBorder),
        const SizedBox(height: 14),
        Text(
          group.title,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        ),
        if (group.hint != null) ...[
          const SizedBox(height: 4),
          Text(
            group.hint!,
            style: const TextStyle(fontSize: 12, color: Colors.black45),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in group.options)
              _chip(
                option,
                widget.value.isSelected(group.key, option.label),
                () => _toggle(group, option.label),
              ),
          ],
        ),
        // 인원 입력은 "선택한 항목"에만 나타난다 — 고르지 않은 좌석까지
        // 입력칸이 깔려 화면이 길어지지 않게.
        if (group.supportsCapacity && selected.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text(
            '좌석별 최대 이용 인원 (선택)',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          for (final label in selected) _capacityRow(group, label),
          if (widget.capacityNote != null) ...[
            const SizedBox(height: 4),
            Text(
              widget.capacityNote!,
              style: const TextStyle(fontSize: 12, color: Colors.black45),
            ),
          ],
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _chip(PlaceFacilityOption option, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFE8F2) : _kBoxFill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? _kAccent : _kBorder),
        ),
        child: Text(
          // 등록 화면에서는 짧은 표기를 쓴다 — 그룹 제목이 이미 맥락을 준다
          // ("외부 음식 반입" > "가능"). 저장값·상세 표기는 option.label 그대로.
          '${option.emoji} ${option.shortLabel}',
          style: TextStyle(
            fontSize: 12,
            color: selected ? _kAccent : Colors.black87,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _capacityRow(PlaceFacilityGroup group, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              '${PlaceFacilityCatalog.emojiFor(label)} $label',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 5,
            child: TextField(
              controller: _capacityCtrl(group, label),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              onChanged: (v) => _setCapacity(group, label, v),
              decoration: InputDecoration(
                isDense: true,
                hintText: '최대 인원',
                suffixText: '명',
                hintStyle: const TextStyle(fontSize: 13, color: Colors.black38),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                filled: true,
                fillColor: _kBoxFill,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'package:party_app/models/custom_play_item.dart';
import 'package:party_app/models/place_attributes.dart';
import 'package:party_app/widgets/place_form/custom_play_item_section.dart';

const _kAccent = Color(0xFFFF6FA0);
const _kBoxFill = Color(0xFFF7F7FA);
const _kBorder = Color(0xFFE8EBF2);

/// 등록/수정 화면의 **세부 속성** 입력 — 고른 대분류에 필요한 그룹만 그린다.
///
/// ── 폼이 100개 항목으로 늘어나지 않게 하는 두 가지 ────────────────────────
///  1. **대분류로 순서를 준다** — [PlaceAttributeCatalog.groupsFor]가 그 업종에서
///     먼저 물어볼 그룹을 위로 올린다. 카페 사장에게 음악 장르를 묻지 않는다.
///  2. **고른 것만 펼친다** — 상세 입력란(크기·이용시간·비용)은 해당 항목을
///     실제로 켰을 때만 나타난다([PlaceAttributeGroup.showsDetails]).
///
/// ── 그래도 빠지는 항목은 없다 ─────────────────────────────────────────────
/// 업종 표에 없더라도 **게스트가 검색할 수 있는 조건**은 전부 아래
/// '그 밖의 편의·서비스' 묶음에 나온다([PlaceAttributeCatalog.extraGroupsFor]).
/// 편의·서비스 필터는 업종을 가리지 않으므로(지도 상세필터·✨ 편의·서비스
/// 시트가 [PlaceFeatures.selectable] 전부를 보여준다), 업종으로 잘라 버리면
/// "손님은 🍽️ 조리되어 나와요로 찾는데 카페 사장은 켤 자리가 없는" 상태가
/// 된다. 순서만 업종을 따르고, **고를 수 있는 것은 어느 업종이나 같다.**
///
/// 섹션 자체도 기본은 접혀 있고, 접힌 동안에는 고른 것 요약만 한 줄 보여준다
/// ([PlaceFacilityOptionsSection]과 같은 관례).
class PlaceAttributesSection extends StatefulWidget {
  const PlaceAttributesSection({
    super.key,
    required this.category,
    required this.value,
    required this.onChanged,
    this.initiallyExpanded = false,
    this.customPlayItems = const [],
    this.onCustomPlayItemsChanged,
  });

  /// 고른 대분류. 무엇을 **먼저** 물을지만 정한다 — null(옛 문서·미선택
  /// 상태)이어도 편의·서비스 항목은 '그 밖의 편의·서비스'로 전부 나온다.
  final String? category;

  final PlaceAttributes value;
  final ValueChanged<PlaceAttributes> onChanged;
  final bool initiallyExpanded;

  /// 놀거리 프리셋의 '기타'에 딸린 **자유기재 놀거리**(표시 원문).
  ///
  /// [value]와 달리 `placeAttributes`가 아니라 문서 루트의 별도 배열이라
  /// ([CustomPlayItems.field]) 따로 받는다 — 프리셋 배열에 섞지 않기 위한
  /// 구분이 화면 층에서도 그대로 유지된다.
  final List<String> customPlayItems;

  /// null이면 자유기재 칸을 아예 그리지 않는다 — 이 축을 쓰지 않는 화면이
  /// 값을 받을 곳 없이 입력칸만 갖게 되는 일을 막는다.
  final ValueChanged<List<String>>? onCustomPlayItemsChanged;

  @override
  State<PlaceAttributesSection> createState() => _PlaceAttributesSectionState();
}

class _PlaceAttributesSectionState extends State<PlaceAttributesSection> {
  late bool _expanded = widget.initiallyExpanded;

  /// 상세 입력칸 컨트롤러 — '그룹키/필드키'가 키다. 항목을 껐다 켜는 사이에도
  /// 직전 입력이 남아 있도록 dispose 전까지 보관한다.
  final Map<String, TextEditingController> _ctrls = {};

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrl(String groupKey, PlaceDetailField field) {
    final key = '$groupKey/${field.key}';
    final stored = widget.value.detailText(groupKey, field.key);
    final existing = _ctrls[key];
    if (existing != null) {
      // 밖에서 값이 바뀐 경우(임시저장 복원 등)에만 맞춘다 — 타이핑 중에는
      // 건드리지 않는다(커서가 튄다).
      if (existing.text.trim() != stored) existing.text = stored;
      return existing;
    }
    return _ctrls[key] = TextEditingController(text: stored);
  }

  @override
  Widget build(BuildContext context) {
    // 업종 표(위) + 그 밖의 편의·서비스(아래). 목록을 만드는 곳은 카탈로그
    // 하나뿐이라 상세검색 시트와 고를 수 있는 항목이 갈라질 수 없다.
    final groups = PlaceAttributeCatalog.groupsFor(widget.category);
    final extras = PlaceAttributeCatalog.extraGroupsFor(widget.category);
    if (groups.isEmpty && extras.isEmpty) return const SizedBox.shrink();

    final summary = widget.value.summaryLabels(max: 4).join(' · ');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '✨ 세부 정보',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            summary.isEmpty
                ? '무제한 · 콜키지 · 흡연 · 놀거리처럼 손님이 검색으로 찾는 정보예요.'
                : summary,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: summary.isEmpty ? Colors.black38 : const Color(0xFF5B5B66),
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Text(
                  _expanded ? '접기' : '자세히 설정',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: _kAccent,
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: _kAccent,
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 6),
            for (final group in groups) ...[
              const SizedBox(height: 14),
              _group(group),
            ],
            // 업종 표에 없는 것들 — 자주 묻는 것이 아닐 뿐, 손님은 업종과
            // 상관없이 이 조건으로 검색한다. 그래서 목록에서 빼지 않고
            // 소제목 아래로 내린다.
            if (extras.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Divider(height: 1, color: _kBorder),
              const SizedBox(height: 14),
              const Text(
                '그 밖의 편의·서비스',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Text(
                  '이 업종에서 자주 묻는 항목은 아니지만, 해당하면 켜 주세요. '
                  '손님은 업종과 상관없이 이 조건으로 검색해요.',
                  style: TextStyle(fontSize: 11.5, color: Colors.black45),
                ),
              ),
              for (final group in extras) ...[
                const SizedBox(height: 14),
                _group(group),
              ],
            ],
          ],
        ],
      ),
    );
  }

  /// 자유기재 놀거리 칸을 그릴 조건 — 놀거리 그룹에서 '기타'를 고른 상태이고,
  /// 값을 받아 갈 곳이 있을 때.
  ///
  /// '기타'를 끈다고 이미 적어 둔 항목을 **여기서 지우지는 않는다** — 칸이
  /// 접힐 뿐이다. 다시 켜면 그대로 돌아오고, 문서에 살아 있는 값인지는
  /// 저장 시점에 [CustomPlayItems.activeFor]가 정한다. 실수로 한 번 누른 것이
  /// 열 개를 되돌릴 수 없게 지우는 일이 없어야 한다.
  bool _showsCustomPlayItems(PlaceAttributeGroup group, Set<String> selected) =>
      widget.onCustomPlayItemsChanged != null &&
      group.key == CustomPlayItems.groupKey &&
      selected.contains(CustomPlayItems.etcOption);

  Widget _group(PlaceAttributeGroup group) {
    final selected = widget.value.selected(group.key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          group.display,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
        if (group.hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              group.hint!,
              style: const TextStyle(fontSize: 11.5, color: Colors.black45),
            ),
          ),
        if (group.options.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final option in group.options)
                _chip(
                  label: option.display,
                  selected: selected.contains(option.label),
                  onTap: () => widget.onChanged(
                    widget.value.toggle(group.key, option.label),
                  ),
                ),
            ],
          ),
        ],
        // 놀거리에서 '기타'를 고르면 자유기재 칸이 그 아래에 펼쳐진다.
        //
        // 상세 입력란(detailsOn)을 쓰지 않는 이유: 그쪽은 `placeAttributeDetails`
        // 맵에 문자열 한 칸을 담는 자리라 **여러 개의 이름**을 담을 수 없고,
        // 담더라도 목록·필터가 배열로 읽을 수 없다. 그래서 별도 필드를 쓴다
        // ([CustomPlayItems.field]).
        if (_showsCustomPlayItems(group, selected))
          CustomPlayItemSection(
            items: widget.customPlayItems,
            onChanged: widget.onCustomPlayItemsChanged!,
          ),
        // 상세 입력란은 **켰을 때만** 나타난다 — 처음부터 다 펼치면 등록 폼이
        // 항목 100개짜리로 보인다.
        if (group.showsDetails(selected)) ...[
          const SizedBox(height: 10),
          for (final field in group.details) _detail(group, field),
        ],
      ],
    );
  }

  Widget _detail(PlaceAttributeGroup group, PlaceDetailField field) {
    if (field.type == PlaceDetailFieldType.toggle) {
      final on = widget.value.detailFlag(group.key, field.key);
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onChanged(
            widget.value.withDetail(group.key, field.key, !on),
          ),
          child: Row(
            children: [
              Icon(
                on ? Icons.check_box : Icons.check_box_outline_blank,
                size: 19,
                color: on ? _kAccent : Colors.black26,
              ),
              const SizedBox(width: 6),
              Text(field.label, style: const TextStyle(fontSize: 12.5)),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: _ctrl(group.key, field),
        keyboardType: field.type == PlaceDetailFieldType.number
            ? TextInputType.number
            : TextInputType.text,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          labelText: field.label,
          labelStyle: const TextStyle(fontSize: 12.5),
          hintText: field.hint,
          hintStyle: const TextStyle(fontSize: 12.5, color: Colors.black26),
          isDense: true,
          filled: true,
          fillColor: _kBoxFill,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 11,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _kBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _kBorder),
          ),
        ),
        onChanged: (v) =>
            widget.onChanged(widget.value.withDetail(group.key, field.key, v)),
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? _kAccent : _kBoxFill,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: selected ? _kAccent : _kBorder),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: selected ? Colors.white : const Color(0xFF4A4A55),
        ),
      ),
    ),
  );
}

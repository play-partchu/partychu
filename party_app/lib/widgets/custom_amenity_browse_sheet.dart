import 'package:flutter/material.dart';

import 'package:party_app/models/custom_amenity.dart';

/// 게스트가 **자유기재 항목을 탐색해서 고르는** 시트 — 기타 편의 서비스가
/// 기본이고, 제목·부제·빈 문구만 갈아 끼우면 🎲 기타 놀거리도 같은 시트를
/// 쓴다([CustomPlayItems]). 목록·개수·초성 탐색·선택 규칙이 한 곳에만 있어야
/// 축마다 다르게 동작하지 않는다.
///
/// "기타 있음/없음"이 아니다 — 기타는 호스트가 만든 말이라 있음/없음으로는
/// 아무것도 좁혀지지 않는다. 지금 등록돼 있는 항목을 실제로 보여주고 그중
/// 하나(또는 여럿)를 고르게 한다.
///
/// ── 목록은 어디서 오나 ────────────────────────────────────────────────────
/// [entries]는 호출부가 **이미 메모리에 들고 있는 문서**에서
/// [CustomAmenities.catalogOf]로 만들어 넘긴다. 이 시트는 조회를 하지 않는다 —
/// 목록·지도가 events/places를 통째로 읽어 클라이언트에서 거르는 구조라
/// 추가 읽기가 필요 없고, 개수도 "지금 보고 있는 범위의 개수"가 된다.
/// 0건 항목은 애초에 만들어지지 않으므로 따로 거를 것도 없다.
///
/// ── 초성 탐색 ─────────────────────────────────────────────────────────────
/// 항목이 [CustomAmenities.initialTabThreshold]개 이하면 탭 없이 전부 보여준다 —
/// 열 몇 개짜리 목록에 탐색 탭을 얹으면 두 번 누르게 만들 뿐이다. 그보다 많으면
/// 상단에 `전체 ㄱ ㄴ ㄷ … ㅎ A-Z 0-9` 줄이 붙고, **실제로 항목이 있는 묶음만**
/// 그려진다(누르면 비어 있는 탭은 없다).
class CustomAmenityBrowseSheet extends StatefulWidget {
  /// 지금 검색 범위의 기타 편의 서비스 목록(개수 포함).
  final List<CustomAmenityEntry> entries;

  /// 이미 켜져 있는 항목(표시 원문). 필터가 들고 있는 값 그대로다 —
  /// 표기 차이는 [CustomAmenities.normalize]로 흡수하므로 호출부가 맞출
  /// 필요가 없다.
  final Set<String> selected;

  /// 시트 제목 — 같은 구조의 **다른 자유기재 축**이 이 시트를 그대로 쓸 수
  /// 있도록 열어 둔다(🎲 기타 놀거리). 목록·초성 탐색·개수 표시·선택 규칙이
  /// 한 곳에만 있어야 축마다 다르게 동작하지 않는다.
  final String title;

  /// 제목 아래 한 줄.
  final String subtitle;

  /// 항목이 하나도 없을 때 보여줄 문구.
  final String emptyText;

  const CustomAmenityBrowseSheet({
    super.key,
    required this.entries,
    required this.selected,
    this.title = '기타 편의 서비스',
    this.subtitle = '호스트가 직접 등록한 항목이에요',
    this.emptyText = '아직 등록된 기타 편의 서비스가 없어요.',
  });

  /// 시트를 열고 **고른 결과(표시 원문 집합)** 를 돌려준다. 취소하면 null.
  static Future<Set<String>?> open(
    BuildContext context, {
    required List<CustomAmenityEntry> entries,
    required Set<String> selected,
    String title = '기타 편의 서비스',
    String subtitle = '호스트가 직접 등록한 항목이에요',
    String emptyText = '아직 등록된 기타 편의 서비스가 없어요.',
  }) => showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => CustomAmenityBrowseSheet(
      entries: entries,
      selected: selected,
      title: title,
      subtitle: subtitle,
      emptyText: emptyText,
    ),
  );

  @override
  State<CustomAmenityBrowseSheet> createState() =>
      _CustomAmenityBrowseSheetState();
}

class _CustomAmenityBrowseSheetState extends State<CustomAmenityBrowseSheet> {
  /// 고른 항목 — 정규화 키 → 표시 원문. 키로 담아야 "루프탑"과 "루프 탑"이
  /// 두 번 켜지지 않고, 원문을 함께 들고 있어야 필터 칩에 그대로 적을 수 있다.
  late Map<String, String> _selected = {
    for (final label in widget.selected)
      CustomAmenities.normalize(label): label,
  };

  /// null이면 '전체'.
  CustomAmenityGroup? _group;

  late final Map<CustomAmenityGroup, List<CustomAmenityEntry>> _grouped =
      CustomAmenities.groupAll(widget.entries);

  bool get _showTabs =>
      widget.entries.length > CustomAmenities.initialTabThreshold;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            if (_showTabs) _buildTabs(),
            const Divider(height: 1),
            Flexible(
              child: widget.entries.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 32,
                      ),
                      child: Text(
                        widget.emptyText,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black45,
                        ),
                      ),
                    )
                  : _buildList(),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.subtitle,
                style: const TextStyle(fontSize: 12, color: Colors.black45),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 20, color: Colors.black45),
          onPressed: () => Navigator.pop(context),
          tooltip: '닫기',
        ),
      ],
    ),
  );

  /// `전체 ㄱ ㄴ … ㅎ A-Z 0-9` — **항목이 있는 묶음만** 그린다.
  Widget _buildTabs() => SizedBox(
    height: 44,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        _tab(label: '전체', group: null),
        for (final g in _grouped.keys) _tab(label: g.label, group: g),
      ],
    ),
  );

  Widget _tab({required String label, required CustomAmenityGroup? group}) {
    final on = _group == group;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => setState(() => _group = group),
        child: Container(
          alignment: Alignment.center,
          constraints: const BoxConstraints(minWidth: 34),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: on ? const Color(0xFF7C5CBF) : const Color(0xFFF7F7FA),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: on ? const Color(0xFF7C5CBF) : const Color(0xFFDDE1EC),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: on ? Colors.white : Colors.black54,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    // '전체'에서도 묶음 제목을 남긴다 — 초성 줄과 같은 구조로 읽혀야
    // 탭을 눌렀을 때 어디로 간 것인지 알 수 있다. 탭이 없을 만큼 항목이
    // 적으면 제목 없이 한 덩어리로 보여준다.
    final groups = _group == null
        ? _grouped
        : {_group!: _grouped[_group!] ?? const <CustomAmenityEntry>[]};
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        for (final entry in groups.entries) ...[
          if (_showTabs) _groupHeader(entry.key.label),
          for (final item in entry.value) _row(item),
        ],
      ],
    );
  }

  Widget _groupHeader(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: Color(0xFF7C5CBF),
      ),
    ),
  );

  Widget _row(CustomAmenityEntry item) {
    final on = _selected.containsKey(item.key);
    return InkWell(
      onTap: () => setState(() {
        if (_selected.remove(item.key) == null) {
          _selected[item.key] = item.label;
        }
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        child: Row(
          children: [
            Icon(
              on ? Icons.check_box : Icons.check_box_outline_blank,
              size: 20,
              color: on ? const Color(0xFF7C5CBF) : Colors.black26,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ),
            Text(
              '${item.count}',
              style: const TextStyle(fontSize: 12, color: Colors.black38),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
    child: Row(
      children: [
        TextButton(
          onPressed: _selected.isEmpty
              ? null
              : () => setState(() => _selected = {}),
          style: TextButton.styleFrom(foregroundColor: Colors.black54),
          child: const Text('초기화'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context, _selected.values.toSet()),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C5CBF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              _selected.isEmpty ? '적용' : '${_selected.length}개 적용',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    ),
  );
}

import 'package:flutter/material.dart';

import 'package:party_app/models/place_taxonomy.dart';

const _kAccent = Color(0xFFFF6FA0);
const _kBoxFill = Color(0xFFF7F7FA);
const _kBorder = Color(0xFFE8EBF2);

/// 플레이스 등록/수정의 **대분류 → 소분류** 선택.
///
/// ── 왜 대분류가 폼의 첫 갈림길인가 ────────────────────────────────────────
/// 대분류를 고르는 순간 그 업종에 필요한 항목만 아래에 펼쳐진다
/// ([PlaceAttributesSection]). 이 순서가 아니면 등록 폼이 모든 업종의 항목을
/// 한꺼번에 늘어놓게 되고("클럽 음악 장르"를 카페 사장이 보게 된다), 그러면
/// 대공사의 목적이던 "필요한 것만 묻기"가 무너진다.
///
/// 소분류는 고른 대분류 아래 것만 보여준다 — 대분류를 바꾸면 이전 대분류의
/// 소분류는 호출부가 함께 버린다.
class PlaceCategorySection extends StatelessWidget {
  const PlaceCategorySection({
    super.key,
    required this.category,
    required this.subcategories,
    required this.onCategoryChanged,
    required this.onSubcategoryToggled,
    this.maxSubcategories = 3,
  });

  /// 고른 대분류. null이면 아직 안 골랐다(= 옛 문서도 이 상태로 열린다).
  final String? category;

  final Set<String> subcategories;

  /// 대분류를 바꿨다. 같은 것을 다시 누르면 null이 온다(선택 해제).
  final ValueChanged<String?> onCategoryChanged;

  final ValueChanged<String> onSubcategoryToggled;

  /// 소분류는 몇 개까지 — 다 고르면 아무것도 안 고른 것과 같아진다.
  final int maxSubcategories;

  /// 칩으로 그릴 대분류들 — 고를 수 있는 것 + **지금 고른 것**.
  ///
  /// 은퇴한 대분류(BAR·라이브)는 새로 고를 수 없지만, 이미 그 값으로 등록된
  /// 가게를 수정할 때는 **보여야 한다.** 안 보이면 호스트 화면에서는 아무
  /// 업종도 안 고른 것처럼 뜨는데 문서에는 값이 그대로 있어, 무엇으로
  /// 등록돼 있는지 알 수 없고 실수로 다른 업종을 눌러 덮어쓰게 된다.
  ///
  /// 새 등록에서는 [category]가 null이라 이 목록은 [PlaceTaxonomy.selectable]
  /// 그대로다 — 은퇴한 칩이 새로 뜨는 일은 없다.
  List<PlaceCategory> get _chips {
    final list = PlaceTaxonomy.selectable;
    final current = PlaceTaxonomy.byLabel(category);
    if (current != null && !list.contains(current)) list.add(current);
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final picked = PlaceTaxonomy.byLabel(category);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Label('업종 대분류'),
        const _Hint('고른 대분류에 맞는 항목만 아래에 펼쳐져요.'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in _chips)
              _chip(
                label: c.display,
                selected: c.label == category,
                onTap: () =>
                    onCategoryChanged(c.label == category ? null : c.label),
              ),
          ],
        ),
        if (picked != null) ...[
          const SizedBox(height: 16),
          _Label('${picked.display} 세부 업종'),
          _Hint('최대 $maxSubcategories개까지 고를 수 있어요.'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final sub in picked.subcategories)
                _chip(
                  label: sub,
                  selected: subcategories.contains(sub),
                  // 이미 최대치면 새로 고르는 것만 막고, 끄는 것은 언제나 된다.
                  disabled:
                      !subcategories.contains(sub) &&
                      subcategories.length >= maxSubcategories,
                  onTap: () => onSubcategoryToggled(sub),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    bool disabled = false,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: disabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _kAccent : _kBoxFill,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? _kAccent : _kBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected
                ? Colors.white
                : disabled
                ? Colors.black26
                : const Color(0xFF4A4A55),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
  );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Text(
      text,
      style: const TextStyle(fontSize: 11.5, color: Colors.black45),
    ),
  );
}

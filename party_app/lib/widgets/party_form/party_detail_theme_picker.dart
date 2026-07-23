import 'package:flutter/material.dart';
import 'package:party_app/models/party_detail_theme_key.dart';
import 'package:party_app/widgets/party_detail_theme.dart';

/// 파티 상세페이지 에디터 상단의 "디자인 테마" 선택 — 텍스트 드롭다운이
/// 아니라 각 테마의 배경/포인트 색상을 미리 보여주는 작은 카드를 가로
/// 스크롤로 나열한다. 선택 즉시 [onChanged]를 호출해 호출부(에디터)가
/// draft 상태만 바꾸고, 실제 파티 저장 시에만 detailTheme으로 반영된다.
class PartyDetailThemePicker extends StatelessWidget {
  final PartyDetailThemeKey selected;
  final ValueChanged<PartyDetailThemeKey> onChanged;

  /// 보여줄 테마 목록 — 기본값은 전체 5종(`PartyDetailThemeRegistry.all`).
  /// "간편 자동 꾸미기" 화면처럼 일부만 고르게 하고 싶을 때 좁혀서 넘긴다.
  final List<PartyDetailThemeData> themes;

  PartyDetailThemePicker({
    super.key,
    required this.selected,
    required this.onChanged,
    List<PartyDetailThemeData>? themes,
  }) : themes = themes ?? PartyDetailThemeRegistry.all;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 128,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final theme in themes)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: _ThemeCard(
                theme: theme,
                selected: theme.key == selected,
                onTap: () => onChanged(theme.key),
              ),
            ),
        ],
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  final PartyDetailThemeData theme;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeCard({required this.theme, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 128,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.sectionBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? theme.primary : Colors.black12, width: selected ? 2 : 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    theme.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.headingColor),
                  ),
                ),
                if (selected) Icon(Icons.check_circle, size: 16, color: theme.primary),
              ],
            ),
            const SizedBox(height: 10),
            // 소제목 색 샘플
            Container(
              width: 22,
              height: 5,
              decoration: BoxDecoration(color: theme.subheadingColor, borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(height: 8),
            // 본문 라인 샘플
            Container(width: double.infinity, height: 5, color: theme.bodyColor.withValues(alpha: 0.55)),
            const SizedBox(height: 4),
            Container(width: 58, height: 5, color: theme.bodyColor.withValues(alpha: 0.35)),
            const SizedBox(height: 10),
            // 카드/아이콘 색 샘플
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: theme.cardBackground,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.cardBorder),
              ),
              child: Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(color: theme.iconBackground, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Container(height: 5, color: theme.mutedColor.withValues(alpha: 0.5)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:party_app/utils/party_view_mode.dart';

/// 파티 목록 보기 방식 아이콘 — 헤더 트리거 버튼과 이 시트가 동일한 아이콘을
/// 쓰도록 공용으로 둔다.
/// ◫(작은 카드) / ▣(기본 카드) / ▮(큰 카드·영상)에 대응.
IconData partyViewModeIcon(PartyViewMode mode) => switch (mode) {
      PartyViewMode.compact => Icons.grid_view_rounded,
      PartyViewMode.standard => Icons.crop_landscape_rounded,
      PartyViewMode.video => Icons.stay_current_portrait_rounded,
    };

/// "보기 방식" 선택 BottomSheet — 아이콘 중심, 설명은 짧은 불릿 2개만.
class PartyViewModeSheet extends StatelessWidget {
  final PartyViewMode current;
  const PartyViewModeSheet({super.key, required this.current});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '보기 방식',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _OptionTile(
                    mode: PartyViewMode.compact,
                    title: '작은 카드',
                    bullets: const ['정보 위주', '한 화면에 많이 보기'],
                    selected: current == PartyViewMode.compact,
                    onTap: () => Navigator.pop(context, PartyViewMode.compact),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _OptionTile(
                    mode: PartyViewMode.standard,
                    title: '기본 카드',
                    bullets: const ['균형형', '이미지와 정보를 적절하게 표시'],
                    selected: current == PartyViewMode.standard,
                    onTap: () => Navigator.pop(context, PartyViewMode.standard),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _OptionTile(
                    mode: PartyViewMode.video,
                    title: '큰 카드(영상)',
                    bullets: const ['영상 중심', '한 번에 하나씩 보기'],
                    selected: current == PartyViewMode.video,
                    onTap: () => Navigator.pop(context, PartyViewMode.video),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final PartyViewMode mode;
  final String title;
  final List<String> bullets;
  final bool selected;
  final VoidCallback onTap;

  const _OptionTile({
    required this.mode,
    required this.title,
    required this.bullets,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFFFF6FA0);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF0F5) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? accent : const Color(0xFFEFEFF2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 아이콘 크기는 기존 그대로 유지(34) — 시트의 다른 여백만 줄였다.
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  partyViewModeIcon(mode),
                  size: 34,
                  color: selected ? accent : Colors.black45,
                ),
                if (selected)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Icon(Icons.check_circle, color: accent, size: 16),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: selected ? accent : Colors.black87,
              ),
            ),
            const SizedBox(height: 3),
            ...bullets.map((b) => Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    b,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: Colors.black45),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

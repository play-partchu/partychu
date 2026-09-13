import 'package:flutter/material.dart';
import 'package:party_app/utils/place_view_mode.dart';

/// 플레이스/장소대여 "보기 방식" 선택 BottomSheet.
///
/// 파티의 [PartyViewModeSheet]와 **같은 모양·같은 구성**이다(아이콘 + 짧은
/// 제목 + 불릿 2개, 3열). 큰 카드가 전체화면 피드로 열리면서 목록 위의
/// 세그먼트 토글이 보이지 않게 되므로, 파티와 마찬가지로 전체화면 안에서도
/// 보기 방식을 바꿀 수 있어야 한다.
class PlaceViewModeSheet extends StatelessWidget {
  final PlaceViewMode current;
  const PlaceViewModeSheet({super.key, required this.current});

  static const _titles = {
    PlaceViewMode.compact: '작은 카드',
    PlaceViewMode.standard: '기본 카드',
    PlaceViewMode.large: '큰 카드',
  };

  static const _bullets = {
    PlaceViewMode.compact: ['정보 위주', '한 화면에 많이 보기'],
    PlaceViewMode.standard: ['균형형', '사진과 정보를 적절하게 표시'],
    PlaceViewMode.large: ['사진·영상 중심', '한 번에 하나씩 보기'],
  };

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
                for (final mode in PlaceViewMode.values) ...[
                  if (mode != PlaceViewMode.values.first)
                    const SizedBox(width: 10),
                  Expanded(
                    child: _OptionTile(
                      mode: mode,
                      title: _titles[mode]!,
                      bullets: _bullets[mode]!,
                      selected: current == mode,
                      onTap: () => Navigator.pop(context, mode),
                    ),
                  ),
                ],
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
  final PlaceViewMode mode;
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
    const accent = Color(0xFFFF6FA0);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF0F5) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? accent : const Color(0xFFEFEFF2),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  mode.icon,
                  size: 34,
                  color: selected ? accent : Colors.black45,
                ),
                if (selected)
                  const Positioned(
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
            ...bullets.map(
              (b) => Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  b,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: Colors.black45),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

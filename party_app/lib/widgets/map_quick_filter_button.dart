import 'package:flutter/material.dart';

/// 지도 홈 빠른 필터 줄의 작은 아이콘 버튼 — 🕐 날짜·시간, ₩ 가격.
///
/// 카테고리 칩과 **같은 줄·같은 높이**에 서고, 기본 상태에서는 아이콘 하나만
/// 있는 짧은 알약이다(글자를 늘 달면 여덟 칸이 한 줄에 못 든다).
///
/// 조건이 걸려 있으면([active]) 분홍으로 채운다. 자리가 넉넉할 때만 부르는
/// 쪽이 [label]에 아주 짧은 값('19:00'·'3~5만')을 넣는다 — 한 줄이 깨질 것
/// 같으면 label 없이 아이콘만 분홍으로 둔다.
class MapQuickFilterButton extends StatelessWidget {
  const MapQuickFilterButton({
    super.key,
    required this.icon,
    required this.active,
    required this.onTap,
    this.label,
    this.glyph,
    this.height = 42,
    this.textScale = 1,
    this.semanticLabel,
  });

  /// 아이콘. [glyph]를 주면 그 글자를 대신 그린다(₩ 같은 기호).
  final IconData icon;

  /// 아이콘 대신 그릴 글자(예 '₩').
  final String? glyph;

  /// 조건이 걸려 있는가 — 분홍으로 채운다.
  final bool active;

  /// 아이콘 옆에 붙일 아주 짧은 값. 없으면 아이콘만.
  final String? label;

  final double height;

  /// 한 줄에 맞추려고 줄인 글자 배율(칩과 같은 값).
  final double textScale;

  final String? semanticLabel;

  final VoidCallback onTap;

  static const Color _pink = Color(0xFFFF6FA0);
  static const double iconSize = 17;

  @override
  Widget build(BuildContext context) {
    final fg = active ? Colors.white : _pink;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? _pink : Colors.white,
            borderRadius: BorderRadius.circular(height / 2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (glyph != null)
                Text(
                  glyph!,
                  style: TextStyle(
                    fontSize: iconSize,
                    fontWeight: FontWeight.w800,
                    color: fg,
                    height: 1.1,
                  ),
                )
              else
                Icon(icon, size: iconSize, color: fg),
              if (label != null) ...[
                const SizedBox(width: 3),
                Text(
                  label!,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 13 * textScale,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : const Color(0xFF3A2E39),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

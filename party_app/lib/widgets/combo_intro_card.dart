import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 콤보 등록 화면(숙박+파티 / 플레이스+파티) 상단에 붙는 접이식 안내 카드.
//
// 두 화면이 같은 컴포넌트를 쓰기 때문에 색·여백·애니메이션이 자동으로 통일된다.
// 기본 상태는 한 줄짜리 요약 + "자세히 보기"뿐이라 폼 자체를 가리지 않고,
// 펼쳤을 때만 설명이 부드럽게 내려온다.
//
// 안내 UI 전용 — 등록 로직이나 데이터 구조와는 아무 관계가 없다.
// ─────────────────────────────────────────────────────────────────────────────

/// 펼쳤을 때 보이는 문단 하나 — 소제목(없을 수도 있음) + 줄 목록.
class ComboIntroSection {
  final String? heading;
  final List<String> lines;

  const ComboIntroSection({this.heading, required this.lines});
}

/// 연한 핑크 톤의 접이식 안내 카드.
class ComboIntroCard extends StatefulWidget {
  /// 접힌 상태에서 보이는 한 줄 요약(길면 두 줄까지).
  final String summary;

  /// 펼쳤을 때 보이는 내용.
  final List<ComboIntroSection> sections;

  const ComboIntroCard({
    super.key,
    required this.summary,
    required this.sections,
  });

  static const Color _bg = Color(0xFFFFF3F8);
  static const Color _border = Color(0xFFFFD9E7);
  static const Color _text = Color(0xFF8A5A72);
  static const Color _accent = Color(0xFFE75B93);

  @override
  State<ComboIntroCard> createState() => _ComboIntroCardState();
}

class _ComboIntroCardState extends State<ComboIntroCard> {
  static const Duration _kAnim = Duration(milliseconds: 220);

  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: ComboIntroCard._bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ComboIntroCard._border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 요약 줄 전체가 토글 영역 — 버튼만 정확히 누르지 않아도 열린다.
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Expanded(
                  // 줄 수를 강제로 자르지 않는다 — 대부분의 기기에서 두 줄로
                  // 끝나지만, 폭이 아주 좁은 기기(360dp 이하)에서 maxLines로
                  // 막으면 안내 문장 끝이 "..."로 잘려 버린다.
                  child: Text(
                    widget.summary,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: ComboIntroCard._text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _buildToggleLabel(),
              ],
            ),
          ),
          // 높이 0 ↔ 실제 높이로 자연스럽게 늘었다 줄어든다.
          // AnimatedCrossFade는 접힌 상태에서도 펼침 내용을 트리에 계속
          // 들고 있어(높이만 0), 스크린 리더가 숨은 문구를 읽는다 —
          // AnimatedSize로 바꿔 접히면 실제로 트리에서 빠지게 했다.
          AnimatedSize(
            duration: _kAnim,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _expanded
                ? _buildDetails()
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleLabel() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _expanded ? '접기' : '자세히 보기',
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.bold,
            color: ComboIntroCard._accent,
          ),
        ),
        // ⌄ / ⌃ 글리프는 기기 폰트에 따라 안 보이는 경우가 있어, 같은 모양의
        // 아이콘을 180° 돌려 쓴다(펼침/접힘이 애니메이션으로도 이어진다).
        AnimatedRotation(
          turns: _expanded ? 0.5 : 0,
          duration: _kAnim,
          curve: Curves.easeOutCubic,
          child: const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: ComboIntroCard._accent,
          ),
        ),
      ],
    );
  }

  Widget _buildDetails() {
    final children = <Widget>[
      const SizedBox(height: 8),
      const Divider(height: 1, thickness: 1, color: ComboIntroCard._border),
      const SizedBox(height: 8),
    ];
    for (var i = 0; i < widget.sections.length; i++) {
      final section = widget.sections[i];
      if (i > 0) children.add(const SizedBox(height: 10));
      if (section.heading != null) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(
              section.heading!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: ComboIntroCard._accent,
              ),
            ),
          ),
        );
      }
      for (final line in section.lines) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              line,
              style: const TextStyle(
                fontSize: 12,
                height: 1.45,
                color: ComboIntroCard._text,
              ),
            ),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

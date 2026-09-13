import 'package:flutter/material.dart';

/// 선택형 필터를 담는 **공용 바텀시트**.
///
/// ── 왜 아코디언이 아니라 시트인가 ─────────────────────────────────────────
/// 필터 항목을 그 자리에서 펼치면 고를수록 화면이 길어진다. 파티 상세검색은
/// 항목이 아홉이라, 파티 유형·분위기(마흔 칸)를 펼치는 순간 검색 버튼이
/// 화면 밖으로 밀려났다. 시트로 빼면 격자는 늘 같은 높이로 남고, 고르는 동안엔
/// 고르는 일만 보인다.
///
/// ── 무엇을 공용화했나 ─────────────────────────────────────────────────────
/// **UI만** 공용화한다. 플레이스의 '♾ 무제한' 시트는 [EventFilter]의 속성을
/// 켜고, 파티의 '파티 유형·분위기'는 [PartyFilter]의 문자열 집합을 켠다 —
/// 데이터의 뜻이 서로 달라서 억지로 한 모델로 합치면 어느 쪽도 자기 판정을
/// 못 하게 된다. 그래서 이 파일은 **그릇**만 제공하고, 무엇을 켜고 끄는지는
/// 부르는 쪽이 [FilterSheetOption.onToggle]에 그대로 들고 온다.
///
/// 덕분에 판정 로직은 한 줄도 옮겨오지 않았다 — 시트는 값을 읽지도 저장하지도
/// 않고, 눌린 사실만 전달한다.
///
/// ── 두 번 알린다 ──────────────────────────────────────────────────────────
/// 칸을 누르면 시트 자신을 다시 그리고([groups]를 다시 부른다), [onChanged]로
/// 뒤 화면에도 알린다. 시트를 닫아야 결과가 바뀌면 무엇을 고르고 있는지 알 수
/// 없기 때문이다.
Future<void> showFilterOptionSheet({
  required BuildContext context,
  required String title,
  // 칸을 누를 때마다 다시 부른다 — '8개 중 3개'처럼 지금 상태를 적으려면
  // 한 번 만들어 둔 글자로는 안 된다.
  required String Function() hint,
  required List<FilterSheetGroup> Function() groups,
  required bool Function() hasSelection,
  required VoidCallback onReset,
  VoidCallback? onChanged,
  bool night = true,
}) {
  final bg = night ? const Color(0xFF17171D) : Colors.white;
  final fg = night ? Colors.white : const Color(0xFF1B1B22);

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: bg,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      top: false,
      child: StatefulBuilder(
        builder: (context, setSheetState) {
          void toggle(FilterSheetOption option) {
            option.onToggle();
            setSheetState(() {});
            onChanged?.call();
          }

          final sections = groups();

          return Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: fg.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: fg,
                        ),
                      ),
                    ),
                    if (hasSelection())
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          onReset();
                          setSheetState(() {});
                          onChanged?.call();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          child: Text(
                            '초기화',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: fg.withValues(alpha: 0.55),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  hint(),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: fg.withValues(alpha: 0.55),
                  ),
                ),
                // 칸이 많은 시트(파티 유형 32칸)도 적용 버튼이 화면 밖으로
                // 밀리지 않게 칩 영역만 스크롤한다. 칸이 적으면 스크롤이 생기지
                // 않으므로 짧은 시트는 예전 모습 그대로다.
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < sections.length; i++) ...[
                          SizedBox(height: i == 0 ? 14 : 16),
                          if (sections[i].label != null) ...[
                            Text(
                              sections[i].label!,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: fg.withValues(alpha: 0.5),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          _chipWrap(sections[i].options, night, toggle),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(sheetContext).pop(),
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6FA0),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '적용',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

/// 시트 안 칸 하나 — 무엇을 켜는지는 [onToggle]이 들고 있다.
class FilterSheetOption {
  const FilterSheetOption({
    required this.label,
    required this.selected,
    required this.onToggle,
    this.leading,
  });

  final String label;
  final bool selected;

  /// 라벨 앞에 붙일 아이콘 — 이모지가 아니라 **이미지**로 표기하는 항목이
  /// 쓴다('돌싱'). null이면 글자만 그린다(대부분의 항목).
  final Widget? leading;

  /// 눌렸을 때 부르는 쪽이 자기 필터를 고친다. 시트는 값을 모른다.
  final VoidCallback onToggle;
}

/// 소제목이 붙는 칸 묶음 — '추천' / '다른 무제한'처럼.
/// [label]이 null이면 소제목 없이 칩만 깐다.
class FilterSheetGroup {
  const FilterSheetGroup({this.label, required this.options});

  final String? label;
  final List<FilterSheetOption> options;
}

/// 칸 묶음 하나. 소제목이 붙는 묶음과 안 붙는 묶음이 **같은 모양**을 쓴다 —
/// 아래쪽이 덜 눌러도 되는 것처럼 보이면 켜 둔 조건을 끄러 들어온 사람이 헤맨다.
Widget _chipWrap(
  List<FilterSheetOption> options,
  bool night,
  void Function(FilterSheetOption) onToggle,
) => Wrap(
  spacing: 8,
  runSpacing: 8,
  children: [
    for (final option in options)
      FilterSheetChip(
        label: option.label,
        selected: option.selected,
        night: night,
        leading: option.leading,
        onTap: () => onToggle(option),
      ),
  ],
);

/// 시트 안 칸 하나 — 빠른필터 줄과 **같은 알약 모양**을 쓴다.
/// 같은 조건을 켜는 칸이 자리마다 다르게 생기면 한 화면으로 안 읽힌다.
class FilterSheetChip extends StatelessWidget {
  const FilterSheetChip({
    super.key,
    required this.label,
    required this.selected,
    required this.night,
    required this.onTap,
    this.leading,
  });

  final String label;
  final bool selected;
  final bool night;
  final VoidCallback onTap;

  /// 라벨 앞 아이콘(이미지로 표기하는 항목 전용). null이면 글자만.
  final Widget? leading;

  static const Color _pink = Color(0xFFFF6FA0);

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? _pink
        : night
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFF6F6F8);
    final border = selected
        ? _pink
        : night
        ? Colors.white.withValues(alpha: 0.14)
        : const Color(0xFFEDEDF0);
    final fg = selected
        ? Colors.white
        : night
        ? Colors.white70
        : const Color(0xFF4A4A4A);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check_rounded, size: 14, color: Colors.white),
              const SizedBox(width: 4),
            ],
            // 체크와 글자 사이 — 이모지 항목의 이모지가 놓이는 자리와 같다.
            if (leading != null) ...[leading!, const SizedBox(width: 4)],
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

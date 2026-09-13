import 'package:flutter/material.dart';

/// 목록 정렬 선택 BottomSheet의 **정본** — 파티 목록과 장소대여 목록이
/// 이 위젯 하나를 함께 쓴다.
///
/// ## 왜 공용인가
///
/// 원래는 파티 전용 `PartySortSheet`만 있었다. 장소대여에도 정렬이 필요해지자
/// "비슷한 시트를 하나 더" 만들 수 있었지만, 그러면 알약 높이·선택 색·체크
/// 아이콘이 두 곳에 복사돼 한쪽만 고쳐지는 상태가 된다(보기 방식 세그먼트가
/// [ViewModeMenuButton] 하나로 합쳐진 것과 같은 이유다).
///
/// 그래서 **모양은 여기에만** 둔다. 정렬 모드가 무엇인지(enum), 어떤 아이콘을
/// 쓸지, 고른 뒤에 무슨 일이 일어나는지는 호출부가 그대로 갖고 있고, 이
/// 위젯은 받은 선택지를 그리고 고른 값을 `Navigator.pop`으로 돌려준다.
///
/// [T]는 정렬 모드 enum이면 무엇이든 된다 — `PartySortMode`, `PlaceSortMode`.
class ListSortSheet<T> extends StatelessWidget {
  /// 보여줄 선택지 — 넘긴 순서 그대로 위에서 아래로 그린다.
  final List<T> options;

  /// 지금 적용돼 있는 값(강조 표시).
  final T current;

  final String Function(T) labelOf;
  final IconData Function(T) iconOf;

  /// 제목 아래 작은 안내 한 줄. 없으면 줄 자체를 그리지 않는다.
  final String? subtitle;

  /// 선택지를 묶어 보여줄 때의 묶음 이름. 앞 선택지와 이름이 달라지는
  /// 자리에만 작은 제목 줄이 하나 들어간다(null이면 제목 없이 이어진다).
  ///
  /// 장소대여의 금액순처럼 **여러 줄이 한 덩어리로 읽혀야 하는** 경우를 위한
  /// 것이다 — 넘기지 않으면 예전처럼 평평한 목록 하나다(파티가 그렇다).
  final String? Function(T)? sectionOf;

  const ListSortSheet({
    super.key,
    required this.options,
    required this.current,
    required this.labelOf,
    required this.iconOf,
    this.subtitle,
    this.sectionOf,
  });

  static const Color accent = Color(0xFFFF6FA0);

  /// 이 자리에 묶음 제목을 그릴지 — 앞 선택지와 묶음 이름이 달라질 때만.
  String? _sectionHeader(int index, T mode) {
    final of = sectionOf;
    if (of == null) return null;
    final name = of(mode);
    if (name == null) return null;
    return index > 0 && of(options[index - 1]) == name ? null : name;
  }

  @override
  Widget build(BuildContext context) {
    final subtitleText = subtitle;
    // 화면 높이의 85%를 넘지 않는다 — 그 위로는 시트가 화면을 통째로 덮어
    // "무엇 위에 떠 있는지" 감이 사라진다. 이 높이는 **상한일 뿐**이고,
    // 선택지가 적으면 시트는 예전처럼 내용만큼만 올라온다(mainAxisSize.min).
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '정렬',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              if (subtitleText != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitleText,
                  style: const TextStyle(fontSize: 11, color: Colors.black45),
                ),
              ],
              const SizedBox(height: 10),
              // 선택지 줄만 스크롤한다 — 제목·안내는 위에 붙여 둔 채로
              // 마지막 옵션까지 내려갈 수 있다.
              //
              // ⚠️ 여기를 다시 고정 높이(SizedBox 등)로 바꾸지 말 것. 옵션이
              //    늘거나 기기 글꼴이 커지면 그 숫자가 곧바로 모자라
              //    'BOTTOM OVERFLOWED BY N PIXELS'로 돌아온다. 남는 높이를
              //    Flexible이 받고 넘치는 만큼만 스크롤되는 지금 구조는
              //    옵션 수·글자 크기가 어떻게 바뀌어도 깨지지 않는다.
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (index, mode) in options.indexed) ...[
                        if (_sectionHeader(index, mode) case final header?)
                          Padding(
                            padding: EdgeInsets.only(
                              top: index == 0 ? 0 : 8,
                              bottom: 6,
                            ),
                            child: Text(
                              header,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.black38,
                              ),
                            ),
                          ),
                        _SortTile(
                          icon: iconOf(mode),
                          label: labelOf(mode),
                          selected: current == mode,
                          onTap: () => Navigator.pop(context, mode),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _SortTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SortTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const accent = ListSortSheet.accent;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF0F5) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? accent : const Color(0xFFEFEFF2),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: selected ? accent : Colors.black45),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  color: selected ? accent : Colors.black87,
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, size: 17, color: accent),
          ],
        ),
      ),
    );
  }
}

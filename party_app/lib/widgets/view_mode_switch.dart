import 'package:flutter/material.dart';

/// 목록 "보기 방식" 컨트롤 — **파티 · 플레이스 · 장소대여 · 파티샵 네 목록이
/// 함께 쓴다.**
///
/// ## 왜 공용인가
///
/// 예전에는 탭마다 모양이 달랐다(한쪽은 둥근 세그먼트, 다른 쪽은 아이콘 버튼
/// 세 개). 같은 성격의 컨트롤이 탭마다 다르게 보이니 서비스가 따로 만든
/// 화면처럼 읽혔고, 한쪽 디자인을 고치면 다른 쪽은 그대로 남았다.
///
/// 그래서 **모양은 이 파일에만** 둔다. 알약 높이·색·아이콘 크기를 바꾸면 네
/// 화면이 언제나 함께 바뀐다 — 어느 한쪽에 비슷한 컨트롤을 새로 그리지 말고
/// [ViewModeMenuButton]에 옵션을 넘겨 쓴다.
///
/// ## 칸 셋을 늘어놓지 않는 이유
///
/// 예전에는 [ ▤ ][ ▦ ][ ▯ ] 세 칸을 그대로 펼친 세그먼트도 함께 있었다.
/// 그런데 목록 위 한 줄에는 방문 조건·편의·서비스·정렬·돋보기까지 함께 앉는다 —
/// 세 칸이 그중 폭을 가장 많이 먹어서, 조건을 두어 개만 켜도 줄이 밀리거나
/// 좁은 화면에서 넘쳤다. 지금은 네 목록 모두 **버튼 하나 + 메뉴**다.
///
/// ## 이 파일이 하지 않는 것
///
/// 선택 상태를 스스로 들고 있지 않고, 무엇을 고르면 무슨 일이 일어나는지도
/// 모른다. 화면마다 동작이 다르기 때문이다 — 플레이스의 '큰 카드'와 파티의
/// '영상 크게 보기'는 목록을 바꾸는 대신 전체화면으로 넘어가고, 저장 위치도
/// 각자 다른 SharedPreferences 키다([PlaceViewMode]/[PartyViewMode]).
/// 그 판단은 호출부가 그대로 하고, 여기는 [ViewModeOption]이 시키는 대로
/// 그리고 눌린 것만 알려준다.

/// 보기 방식 하나 — [ViewModeMenuButton]의 메뉴 한 줄이 된다.
/// [label]은 메뉴 글씨이자 버튼의 툴팁·접근성 라벨이다.
@immutable
class ViewModeOption {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const ViewModeOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
}

/// 알약 한 칸의 **그림만** — [ViewModeMenuButton]의 버튼이 이 그림을 쓴다.
/// 한 곳에만 두어 네 목록의 버튼이 절대 갈라지지 않는다.
class _ViewModePill extends StatelessWidget {
  final IconData icon;
  final bool selected;

  const _ViewModePill({required this.icon, required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFFF6FA0) : Colors.transparent,
        borderRadius: BorderRadius.circular(19),
      ),
      child: Icon(
        icon,
        size: 18,
        color: selected ? Colors.white : const Color(0xFFFFA8C8),
      ),
    );
  }
}

/// 보기 방식 **버튼 하나 + 버튼에 붙는 메뉴** — 파티·플레이스·장소대여·
/// 파티샵 네 목록이 **모두** 이것을 쓴다.
///
/// ## 세그먼트도 아니고 바텀시트도 아닌 이유
///
/// 칸 셋을 그대로 펼치면 목록 위 한 줄에서 폭을 가장 많이 먹는다. 그렇다고
/// 화면 아래에서 시트를 올리면 고작 셋 중 하나를 고르려고 화면 전체가
/// 움직인다. 그래서 **누른 그 자리에 붙어서** 셋이 한 번에 열리고, 하나를
/// 고르면 곧바로 닫힌다.
///
/// 버튼에는 **지금 쓰는 보기 방식** 아이콘 하나가 핑크로 채워져 앉고
/// ([_ViewModePill]), 메뉴가 열리면 셋의 이름과 지금 고른 것이 함께 보인다.
///
/// 이 위젯은 **선택 상태를 들고 있지 않다.**
/// 무엇을 고르면 무슨 일이 일어나는지(목록을 바꾸는지, 전체화면으로 가는지,
/// 어디에 저장하는지)는 전부 호출부가 [ViewModeOption]으로 정한다.
class ViewModeMenuButton extends StatelessWidget {
  /// 버튼에 그릴 아이콘 — 보통 지금 쓰는 보기 방식의 아이콘이다.
  final IconData currentIcon;

  /// 툴팁·접근성 라벨('보기 방식 · 기본 카드').
  final String label;

  /// 메뉴에 순서대로 그릴 선택지. 글씨까지 함께 보여주므로
  /// [ViewModeOption.label]이 여기서는 툴팁이 아니라 **메뉴 글씨**가 된다.
  final List<ViewModeOption> options;

  const ViewModeMenuButton({
    super.key,
    required this.currentIcon,
    required this.label,
    required this.options,
  });

  static const Color _pink = Color(0xFFFF6FA0);

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      // 버튼 자리에 딱 붙여 아래로 편다 — 화면 아래에서 올라오는 시트가 아니다.
      position: PopupMenuPosition.under,
      offset: const Offset(0, 4),
      color: Colors.white,
      elevation: 6,
      padding: EdgeInsets.zero,
      tooltip: label,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFFFD6E8)),
      ),
      onSelected: (index) => options[index].onTap(),
      itemBuilder: (context) => [
        for (final (index, option) in options.indexed)
          PopupMenuItem<int>(
            value: index,
            height: 44,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  option.icon,
                  size: 18,
                  color: option.selected ? _pink : Colors.black45,
                ),
                const SizedBox(width: 10),
                Text(
                  option.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: option.selected
                        ? FontWeight.w800
                        : FontWeight.w600,
                    color: option.selected ? _pink : Colors.black87,
                  ),
                ),
                const SizedBox(width: 12),
                // 지금 쓰는 방식임을 핑크 체크로도 한 번 더 밝힌다.
                Icon(
                  Icons.check_circle,
                  size: 16,
                  color: option.selected ? _pink : Colors.transparent,
                ),
              ],
            ),
          ),
      ],
      child: Semantics(
        label: label,
        button: true,
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFFFD6E8)),
          ),
          child: _ViewModePill(icon: currentIcon, selected: true),
        ),
      ),
    );
  }
}

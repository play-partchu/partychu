import 'package:flutter/material.dart';

/// 목록 정렬 시트를 여는 버튼 — **파티 목록과 장소대여 목록이 이 하나를
/// 함께 쓴다.**
///
/// ## 왜 공용인가
///
/// 예전에는 장소대여만 이 아이콘 버튼을 쓰고, 파티는 날짜 필터 바 안의
/// 알약(`DayFilterChip`)과 밤 모드 네온 바 안의 아이콘 — 이렇게 **모양이 셋**
/// 이었다. 같은 일을 하는 버튼이 화면마다 달라 보였고, 한쪽 크기·색을 고치면
/// 다른 쪽은 그대로 남았다(보기 방식 버튼이 [ViewModeMenuButton] 하나로
/// 합쳐진 것과 같은 이유다).
///
/// 지금은 **크기·터치 영역·색·배경/테두리·아이콘·활성 표시가 전부 여기에만**
/// 있다. 어느 탭이든 이 위젯을 쓰고, 호출부는 "누르면 무엇을 열지"와 "지금
/// 기본순이 아닌지"만 넘긴다 — 한쪽만 달라질 수가 없다.
///
/// ## 모양
///
/// 배경도 테두리도 없는 분홍 아이콘 하나에 40×40 터치 영역. 바로 왼쪽에 붙는
/// 돋보기([SearchEntryIconButton])와 **같은 규격**이라 두 버튼이 나란히 놓여도
/// 줄이 어긋나지 않는다 — 탭타깃 설정까지 같은 값을 쓴다(아래 build 주석).
class SortEntryIconButton extends StatelessWidget {
  final VoidCallback onTap;

  /// 기본순이 아닌 정렬이 걸려 있는지 — 걸려 있으면 오른쪽 위에 분홍 점을
  /// 찍어 "지금 순서가 기본이 아니다"를 알린다(돋보기의 조건 표시와 같은 규칙).
  final bool active;

  /// 툴팁 — 지금 무엇으로 정렬돼 있는지까지 적으면 좋다('정렬 · 거리순').
  final String tooltip;

  const SortEntryIconButton({
    super.key,
    required this.onTap,
    this.active = false,
    this.tooltip = '정렬',
  });

  static const Color _kPink = Color(0xFFFF6FA0);

  /// 정렬을 뜻하는 그림 — **정렬 시트의 '기본순'이 쓰는 그 아이콘 그대로**다
  /// ([PartySortSheet.iconFor]·[PlaceSortSheet.iconFor]의 defaultOrder).
  ///
  /// 예전에는 ▼(arrow_drop_down)이었다. 시트를 여는 버튼이라는 뜻은 맞았지만,
  /// 정작 시트를 열면 같은 뜻의 줄 세 개짜리 아이콘이 맨 위에 다시 나와서
  /// 버튼과 시트가 서로 다른 그림으로 같은 것을 가리켰다. 입구와 목적지가
  /// 같은 그림을 쓰도록 맞춘다 — 아이콘 정의는 시트 쪽이 정본이다.
  static const IconData icon = Icons.sort_rounded;

  /// 아이콘 지름 — 돋보기와 같은 20. (▼ 시절에는 삼각형 글리프가 아이콘 상자
  /// 안에서 작게 앉아 22로 키워야 했는데, 그 이유가 사라졌다.)
  static const double _iconSize = 20;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      // 돋보기와 **같은 이유로** 탭타깃을 줄인다 — 이게 없으면 아래
      // constraints가 40이어도 테마 기본값(48×48)이 그 위에 얹혀 실제로는 48로
      // 그려지고, 이 버튼이 들어간 줄의 높이만 조용히 8px 커진다
      // ([SearchEntryIconButton]의 같은 주석 참고). 두 버튼이 나란히 붙는
      // 자리라 한쪽만 48이면 줄이 그대로 어긋난다.
      style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(icon, size: _iconSize, color: _kPink),
          if (active)
            Positioned(
              right: -1,
              top: -1,
              child: Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: _kPink,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

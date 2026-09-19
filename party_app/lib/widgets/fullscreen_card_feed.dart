import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:party_app/utils/feed_video_manager.dart';
import 'package:party_app/widgets/partychu_icon_button.dart'
    show MuteToggleIconButton;

// ══════════════════════════════════════════════════════════════════════════
// 큰 카드 전체화면 피드 — 파티·플레이스·장소대여가 **함께 쓰는** 껍데기.
//
// 예전에는 파티만 이 구조(전체화면 세로 PageView)를 갖고 있었고,
// 플레이스/장소대여의 "큰 카드"는 목록 안에 높이 62%짜리 둥근 카드로 인라인
// 배치돼 있었다. 카드 내용물은 같은 위젯을 썼는데도 화면이 전혀 다르게 보인
// 이유가 이것이다 — 껍데기가 달랐다.
//
// 여기 있는 것:
//  - 상태바·내비게이션 바까지 숨기는 몰입 모드(화면에서 나가면 원복)
//  - 검은 배경 위 세로 PageView(위로 스와이프 = 다음, 아래로 = 이전)
//  - 좌상단 뒤로가기, 우하단 음소거 토글
//  - 진입 시 소리를 켠 채 시작(목록에 섞인 작은 미리보기와 달리 몰입 뷰라서)
//
// 화면마다 다른 것은 우상단 액션 버튼([actions])과 카드 위젯([itemBuilder])
// 둘뿐이다. 그 외 레이아웃·여백·스와이프 동작은 이 파일 하나로 고정된다.
// ══════════════════════════════════════════════════════════════════════════

/// 전체화면 피드 위에 얹는 원형 아이콘 버튼 — 뒤로가기·상세검색·보기방식이
/// 모두 같은 모양을 쓰도록 공용으로 둔다.
Widget feedRoundIconButton(
  IconData icon,
  VoidCallback onTap, {
  Color iconColor = Colors.white,
}) {
  return Material(
    color: Colors.black.withValues(alpha: 0.4),
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, color: iconColor, size: 22),
      ),
    ),
  );
}

/// 피드 안의 카드 한 장이 **자기 위치와 이웃 콘텐츠**를 아는 통로.
///
/// 사진 숏폼(`FeedPhotoStory`)이 쓴다 — 지금 이 카드가 현재 페이지인지 보고
/// 타이머를 돌리거나 멈추고, 마지막 사진이 끝나면 다음 콘텐츠로 넘긴다.
/// 동영상 카드는 이것을 읽지 않는다(가시성 기반 자동재생 그대로).
class FeedPager extends InheritedWidget {
  /// 이 카드의 페이지 번호.
  final int index;

  /// 지금 화면의 페이지 번호 — 스와이프가 절반을 넘는 순간 바뀐다.
  final ValueListenable<int> current;

  /// 이웃 콘텐츠로 넘긴다. 넘길 곳이 없으면 false.
  final bool Function() next;
  final bool Function() previous;

  const FeedPager({
    super.key,
    required this.index,
    required this.current,
    required this.next,
    required this.previous,
    required super.child,
  });

  static FeedPager? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FeedPager>();

  @override
  bool updateShouldNotify(FeedPager oldWidget) =>
      index != oldWidget.index || current != oldWidget.current;
}

class FullscreenCardFeed extends StatefulWidget {
  final int itemCount;
  final int initialIndex;

  /// 카드 한 장 — [PartyVideoFeedCard]/[PlaceLargeCard]처럼 자체 배경과
  /// 오버레이를 가진, 화면을 꽉 채우는 위젯이어야 한다.
  final Widget Function(BuildContext context, int index) itemBuilder;

  /// 우상단 액션 버튼들([feedRoundIconButton]으로 만든다).
  final List<Widget> actions;

  const FullscreenCardFeed({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.initialIndex = 0,
    this.actions = const [],
  });

  @override
  State<FullscreenCardFeed> createState() => _FullscreenCardFeedState();
}

class _FullscreenCardFeedState extends State<FullscreenCardFeed> {
  late final PageController _pageController;
  late final ValueNotifier<int> _currentPage;

  /// [target] 페이지로 넘긴다 — 사진 숏폼이 마지막/첫 사진에서 부른다.
  bool _goTo(int target) {
    if (target < 0 || target >= widget.itemCount) return false;
    if (!_pageController.hasClients) return false;
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
    return true;
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
    _currentPage = ValueNotifier(widget.initialIndex);
    // 상태바/내비게이션 바까지 숨겨 카드 한 장이 화면 전체를 쓰게 한다.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // 목록에 섞인 작은 미리보기와 달리 이 화면은 몰입해서 보는 전체화면
    // 뷰라 소리를 켠 채로 시작한다(사용자가 다시 끄면 그 선택은 존중된다).
    FeedVideoManager.instance.setMuted(false);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pageController.dispose();
    _currentPage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // immersiveSticky에서는 상태바가 숨겨져 topPadding이 0이 될 수 있으므로
    // 최소 여백을 보장한다.
    final topPad = MediaQuery.of(context).padding.top;
    final topInset = (topPad > 0 ? topPad : 8.0) + 8;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final bottomInset = (bottomPad > 0 ? bottomPad : 8.0) + 8;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: widget.itemCount,
            onPageChanged: (i) => _currentPage.value = i,
            itemBuilder: (context, index) => FeedPager(
              index: index,
              current: _currentPage,
              next: () => _goTo(index + 1),
              previous: () => _goTo(index - 1),
              child: widget.itemBuilder(context, index),
            ),
          ),
          Positioned(
            top: topInset,
            left: 12,
            child: feedRoundIconButton(
              Icons.arrow_back,
              () => Navigator.pop(context),
            ),
          ),
          // 스피커 on/off — 상세보기 버튼(좌측 하단)과 겹치지 않도록 우측
          // 하단에 둔다. 전역 음소거 상태(FeedVideoManager)를 그대로 보고
          // 누르면 이 화면뿐 아니라 다음에 재생되는 모든 카드에도 이어진다.
          Positioned(
            right: 12,
            bottom: bottomInset,
            child: const MuteToggleIconButton(size: 25),
          ),
          if (widget.actions.isNotEmpty)
            Positioned(
              top: topInset,
              right: 12,
              child: Row(children: widget.actions),
            ),
        ],
      ),
    );
  }
}

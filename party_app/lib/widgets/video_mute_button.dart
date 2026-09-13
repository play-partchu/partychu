import 'package:flutter/material.dart';
import 'package:party_app/utils/feed_video_manager.dart';
import 'package:party_app/widgets/partychu_icon_button.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 재생 중인 모든 동영상(기본·작은·큰 카드/지도/상세페이지 동영상)의 소리를
// 한 번에 켜고 끄는 전역 음소거 상태를 보여주고 전환하는
// 버튼 두 종류. 둘 다 FeedVideoManager.instance.mutedNotifier 하나만 보고
// 그리므로, 어느 쪽을 누르든 현재 재생 중인 모든 동영상의 볼륨이 동시에
// 바뀌고, 다음에 재생되는 영상에도 그대로 이어진다(SharedPreferences에
// 영구 저장).
// ─────────────────────────────────────────────────────────────────────────────

/// 상단 헤더의 검색·정렬 아이콘과 나란히 두는 용도 — 원형 배경 없이 아이콘
/// 하나로만 표시하는 PartyChu 프리미엄 스타일(기본/작은 카드가 있는 메인
/// 화면 파티 목록 헤더에서 사용).
class VideoMuteIconButton extends StatelessWidget {
  const VideoMuteIconButton({super.key});

  @override
  Widget build(BuildContext context) {
    return const MuteToggleIconButton(size: 21);
  }
}

/// 지도·영상 크게 보기(큰 카드)처럼 화면 위에 독립적으로 떠 있는 원형 버튼이
/// 필요한 화면에서 쓰는 Floating 스타일. (2026-07-16 기준 아직 어느 화면에도
/// 배치되지 않음 — 지도/큰 카드는 별도로 배치 예정.)
class GlobalMuteFab extends StatelessWidget {
  const GlobalMuteFab({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: FeedVideoManager.instance.mutedNotifier,
      builder: (context, muted, _) => FloatingActionButton(
        heroTag: 'global_mute_fab',
        mini: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFFFF6FA0),
        // tooltip을 켜면 FloatingActionButton이 내부적으로 Tooltip(길게 누르면
        // 뜨는 안내문구)을 쓰는데, Navigator 바깥(Overlay 조상이 없는 위치)에
        // 이 버튼을 두면 "No Overlay widget found" 예외가 매 프레임 발생해
        // 화면이 온통 빨간 에러로 덮여 보인다. 이 버튼을 어디에 배치하든
        // Navigator/Overlay 하위에 두거나, 그게 아니라면 툴팁을 비워야 한다.
        onPressed: () => FeedVideoManager.instance.setMuted(!muted),
        child: Icon(
          muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          color: muted ? const Color(0xFFE91E63) : const Color(0xFFFF6FA0),
        ),
      ),
    );
  }
}

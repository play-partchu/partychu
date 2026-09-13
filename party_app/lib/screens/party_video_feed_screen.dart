import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:party_app/utils/party_view_mode.dart';
import 'package:party_app/widgets/fullscreen_card_feed.dart';
import 'package:party_app/widgets/main/search_entry_sheet.dart';
import 'package:party_app/widgets/party_card_widget.dart';
import 'package:party_app/widgets/party_view_mode_sheet.dart';

/// 전체화면 영상 피드를 벗어날 때 돌려주는 결과 — 보기 방식을 바꿨는지,
/// 검색(검색어/상세검색 조건)을 바꿨는지. 플레이스의 [PlaceFeedExitResult]와
/// 같은 모양이다. MainScreen은 [searchChanged]면 새로 걸러진 목록으로
/// 전체화면을 자동으로 다시 띄우고, [viewMode]가 있으면(그리고 video가
/// 아니면) 목록의 보기 방식을 그 값으로 바꾼다.
class VideoFeedExitResult {
  final PartyViewMode? viewMode;

  /// 검색어나 상세검색 조건이 바뀌었는지 — 실제 값은 목록 화면이 자기 상태에
  /// 이미 반영해 두었으므로, 여기서는 "다시 띄워라"는 신호만 넘긴다.
  final bool searchChanged;

  const VideoFeedExitResult({this.viewMode, this.searchChanged = false});
}

// ─────────────────────────────────────────────────────────────────────────────
// 큰 카드(영상 크게 보기)를 탭했을 때 여는 완전한 전체화면 카드 피드 — 파티
// 목록의 고정 헤더/검색창/"파티 목록" 제목/정렬 버튼은 전혀 보이지 않고,
// 화면 전체를 카드 한 장이 차지한다.
//
// - SystemUiMode.immersiveSticky로 상태바·내비게이션 바까지 숨겨 최대한
//   넓은 공간을 쓰고, 화면을 벗어나면(dispose) 원래 모드로 되돌린다.
// - 세로 PageView로 카드를 넘긴다 — 위로 스와이프하면 다음 카드, 아래로
//   스와이프하면 이전 카드. PageView 기본 동작 그대로라 첫 카드에서 아래로,
//   마지막 카드에서 위로 당겨도 그냥 튕길 뿐 화면이 닫히지 않는다(드래그로
//   닫는 제스처를 별도로 붙이지 않았음).
// - 종료는 좌상단 뒤로가기 버튼 또는 시스템 뒤로가기로만 한다.
// - 우상단 아이콘으로 기존 PartyViewModeSheet를 그대로 띄운다. 작은/기본
//   카드를 고르면 이 화면을 닫으며 그 결과를 호출자(MainScreen)에 돌려줘
//   목록 화면에 바로 반영시킨다. 영상 크게 보기를 다시 고르면 지금 보던
//   카드를 그대로 유지한다.
// - 진입하는 순간 소리를 켠 채로 재생을 시작한다(목록에 섞여 있는 작은
//   미리보기와 달리, 이 화면은 몰입해서 보는 전체화면 뷰이므로). 카드
//   자체(재생/일시정지 토글, 소리 끄기, 상세보기 버튼)는 PartyVideoFeedCard를
//   그대로 재사용하므로 기존 기능이 전부 유지된다. 화면에 보이는 카드만
//   자동재생되는 것도 PartyVideoFeedCard 내부의 가시성 감지 로직이 그대로
//   보장한다.
// ─────────────────────────────────────────────────────────────────────────────

class PartyVideoFeedScreen extends StatefulWidget {
  final List<QueryDocumentSnapshot> docs;
  final int initialIndex;

  /// 우상단 돋보기를 눌렀을 때 목록 화면이 파티 탭의 검색 시트(검색어 +
  /// 상세검색)를 그대로 띄운다. 검색어나 조건이 바뀌었으면 true를 돌려주고,
  /// 그러면 이 화면은 닫히면서 목록 화면이 새로 걸러진 목록으로 전체화면을
  /// 다시 띄운다. 플레이스 전체화면([PlaceFeedScreen])과 완전히 같은 계약이다.
  final Future<bool> Function()? onOpenSearch;

  /// 지금 검색어나 조건이 걸려 있는지 — 돋보기 위 분홍 점 표시용.
  final bool searchActive;

  const PartyVideoFeedScreen({
    super.key,
    required this.docs,
    required this.initialIndex,
    this.onOpenSearch,
    this.searchActive = false,
  });

  @override
  State<PartyVideoFeedScreen> createState() => _PartyVideoFeedScreenState();
}

class _PartyVideoFeedScreenState extends State<PartyVideoFeedScreen> {
  Future<void> _showViewModeSheet() async {
    final selected = await showModalBottomSheet<PartyViewMode>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const PartyViewModeSheet(current: PartyViewMode.video),
    );
    if (selected == null || !mounted) return;
    await selected.save();
    if (!mounted) return;
    // 작은/기본 카드를 고르면 전체화면을 닫고 그 모드를 목록 화면에 전달한다.
    // 영상 크게 보기를 다시 고른 경우엔 지금 보던 카드를 그대로 유지한다.
    if (selected != PartyViewMode.video) {
      Navigator.pop(context, VideoFeedExitResult(viewMode: selected));
    }
  }

  // 메인 목록의 돋보기와 **완전히 같은 검색 시트** — 목록 화면이 열어주고
  // (SearchEntrySheet: 검색어 입력 + 상세검색), 검색어나 조건이 바뀌면
  // 전체화면을 닫는다. 목록 화면은 다시 걸러진 목록으로 전체화면을 즉시
  // 다시 띄운다(_maybeAutoOpenVideoFeed 재사용).
  Future<void> _openSearch() async {
    final changed = await widget.onOpenSearch!();
    if (!changed || !mounted) return;
    Navigator.pop(context, const VideoFeedExitResult(searchChanged: true));
  }

  @override
  Widget build(BuildContext context) {
    // 몰입 모드·세로 PageView·뒤로가기·음소거 토글은 전부 공용 껍데기가
    // 맡는다. 이 화면에 남는 건 우상단 액션(돋보기·보기방식)뿐이고, 그 둘 다
    // 플레이스 전체화면([PlaceFeedScreen])과 같은 위젯·같은 순서다.
    return FullscreenCardFeed(
      itemCount: widget.docs.length,
      initialIndex: widget.initialIndex,
      itemBuilder: (context, index) {
        final doc = widget.docs[index];
        final data = doc.data() as Map<String, dynamic>;
        return PartyVideoFeedCard(
          key: ValueKey(doc.id),
          party: data,
          docId: doc.id,
        );
      },
      actions: [
        if (widget.onOpenSearch != null) ...[
          feedSearchEntryButton(
            onTap: _openSearch,
            active: widget.searchActive,
          ),
          const SizedBox(width: 8),
        ],
        feedRoundIconButton(
          partyViewModeIcon(PartyViewMode.video),
          _showViewModeSheet,
        ),
      ],
    );
  }
}

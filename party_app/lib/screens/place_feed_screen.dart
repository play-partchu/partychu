import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:party_app/utils/place_view_mode.dart';
import 'package:party_app/widgets/fullscreen_card_feed.dart';
import 'package:party_app/widgets/main/search_entry_sheet.dart';
import 'package:party_app/widgets/place_card_widget.dart';
import 'package:party_app/widgets/place_view_mode_sheet.dart';

/// 전체화면 플레이스 피드를 벗어날 때 돌려주는 결과 — 보기 방식을 바꿨는지,
/// 검색(검색어/상세검색 조건)을 바꿨는지. 파티의 [VideoFeedExitResult]와 같다.
class PlaceFeedExitResult {
  final PlaceViewMode? viewMode;

  /// 검색어나 상세검색 조건이 바뀌었는지 — 실제 값은 목록 화면이 이미
  /// 자기 상태에 반영해 두었으므로, 여기서는 "다시 걸러서 전체화면을 새로
  /// 띄워야 한다"는 신호만 넘긴다.
  final bool searchChanged;

  const PlaceFeedExitResult({this.viewMode, this.searchChanged = false});
}

// ─────────────────────────────────────────────────────────────────────────────
// 플레이스/장소대여 "큰 카드" 전체화면 피드.
//
// 파티의 [PartyVideoFeedScreen]과 **완전히 같은 구조**다 — 껍데기
// ([FullscreenCardFeed])와 카드 오버레이(feedInfoOverlayBox·그라디언트·
// 진행바·상세보기 버튼)를 그대로 공유하고, 이 화면에 남는 것은 우상단
// 액션(돋보기·보기 방식)뿐이다.
//
// 검색 입구는 목록 화면과 **똑같이 돋보기 하나**다(별도 상세검색 튠 아이콘은
// 없앴다). 돋보기를 누르면 목록 화면이 자기 탭의 검색 시트(SearchEntrySheet)를
// 그대로 열고, 그 안에서 검색어와 상세검색을 함께 쓴다 — 시트를 여는 일은
// 필터 상태를 들고 있는 MainScreen에 [onOpenSearch]로 맡기므로, 이 화면에는
// 검색 UI도 필터 로직도 없다.
//
// 예전에는 큰 카드가 목록 안에 높이 62%짜리 둥근 카드로 인라인 배치돼 있어서
// 파티 큰 카드와 이질감이 컸다 — 그 인라인 배치를 없애고 이 화면으로 모았다.
// ─────────────────────────────────────────────────────────────────────────────

class PlaceFeedScreen extends StatefulWidget {
  final List<QueryDocumentSnapshot> docs;
  final int initialIndex;

  /// 어느 컬렉션의 문서인지 — 플레이스(events) / 장소대여(places).
  final PlaceCardSource source;

  /// 우상단 돋보기를 눌렀을 때 목록 화면이 자기 탭의 검색 시트(검색어 +
  /// 상세검색)를 그대로 띄운다. 검색어나 조건이 바뀌었으면 true를 돌려주고,
  /// 그러면 이 화면은 닫히면서 목록 화면이 새로 걸러진 목록으로 전체화면을
  /// 다시 띄운다(파티와 동일). null이면 버튼 자체를 그리지 않는다.
  final Future<bool> Function()? onOpenSearch;

  /// 지금 검색어나 조건이 걸려 있는지 — 돋보기 위 분홍 점 표시용(파티와 동일).
  final bool searchActive;

  const PlaceFeedScreen({
    super.key,
    required this.docs,
    required this.source,
    this.initialIndex = 0,
    this.onOpenSearch,
    this.searchActive = false,
  });

  @override
  State<PlaceFeedScreen> createState() => _PlaceFeedScreenState();
}

class _PlaceFeedScreenState extends State<PlaceFeedScreen> {
  Future<void> _showViewModeSheet() async {
    final selected = await showModalBottomSheet<PlaceViewMode>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const PlaceViewModeSheet(current: PlaceViewMode.large),
    );
    if (selected == null || !mounted) return;
    await selected.save();
    if (!mounted) return;
    // 작은/기본 카드를 고르면 전체화면을 닫고 그 모드를 목록 화면에 전달한다.
    // 큰 카드를 다시 고른 경우엔 지금 보던 카드를 그대로 유지한다.
    if (selected != PlaceViewMode.large) {
      Navigator.pop(context, PlaceFeedExitResult(viewMode: selected));
    }
  }

  /// 파티 전체화면의 `_openSearch`와 같은 동작 — 목록 화면이 자기 탭의 검색
  /// 시트를 띄우고(그 안에 상세검색이 있다), 검색어나 조건이 바뀌었으면
  /// 전체화면을 닫아 목록 화면이 새로 걸러진 목록으로 다시 띄우게 한다.
  Future<void> _openSearch() async {
    final changed = await widget.onOpenSearch!();
    if (!changed || !mounted) return;
    Navigator.pop(context, const PlaceFeedExitResult(searchChanged: true));
  }

  @override
  Widget build(BuildContext context) {
    return FullscreenCardFeed(
      itemCount: widget.docs.length,
      initialIndex: widget.initialIndex,
      itemBuilder: (context, index) {
        final doc = widget.docs[index];
        final data = doc.data() as Map<String, dynamic>;
        return PlaceLargeCard(
          key: ValueKey(doc.id),
          place: data,
          placeId: doc.id,
          source: widget.source,
        );
      },
      // 우상단 액션 — 파티 전체화면([PartyVideoFeedScreen])과 **같은 자리에
      // 같은 순서·같은 위젯**으로 둔다: 돋보기(조건이 걸려 있으면 분홍 점) →
      // 8px 간격 → 보기 방식. 두 화면을 오갈 때 버튼 위치가 튀지 않는다.
      actions: [
        if (widget.onOpenSearch != null) ...[
          feedSearchEntryButton(
            onTap: _openSearch,
            active: widget.searchActive,
          ),
          const SizedBox(width: 8),
        ],
        feedRoundIconButton(PlaceViewMode.large.icon, _showViewModeSheet),
      ],
    );
  }
}
